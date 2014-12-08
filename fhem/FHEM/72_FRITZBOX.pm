###############################################################
# $Id$
#
#  72_FRITZBOX.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module handles the Fritz!Box router and the Fritz!Phone MT-F 
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> FRITZBOX
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;
use Net::Telnet;


sub FRITZBOX_Log($$$);
sub FRITZBOX_Init($);
sub FRITZBOX_Ring_Start($@);
sub FRITZBOX_Exec($$);

our $telnet;

my %fonModel = ( 
        '0x01' => "MT-D"
      , '0x03' => "MT-F"
      , '0x04' => "C3"
      , '0x05' => "M2"
      , '0x08' => "C4"
   );

my %ringTone = ( 
     0 => "HandsetDefault"
   , 1 => "HandsetInternalTon"
   , 2 => "HandsetExternalTon"
   , 3 => "Standard"
   , 4 => "Eighties"
   , 5 => "Alert"
   , 6 => "Ring"
   , 7 => "RingRing"
   , 8 => "News"
   , 9 => "CustomerRingTon"
   , 10 => "Bamboo"
   , 11 => "Andante"
   , 12 => "ChaCha"
   , 13 => "Budapest"
   , 14 => "Asia"
   , 15 => "Kullabaloo"
   , 16 => "silent"
   , 17 => "Comedy"
   , 18 => "Funky",
   , 19 => "Fatboy"
   , 20 => "Calypso"
   , 21 => "Pingpong"
   , 22 => "Melodica"
   , 23 => "Minimal"
   , 24 => "Signal"
   , 25 => "Blok1"
   , 26 => "Musicbox"
   , 27 => "Blok2"
   , 28 => "2Jazz"
   , 33 => "InternetRadio"
   , 34 => "MusicList"
   );

my %ringToneNumber;
while (my ($key, $value) = each %ringTone) {
   $ringToneNumber{lc $value}=$key;
}

my %alarmDays = ( 
     1 => "Mo"
   , 2 => "Tu"
   , 4 => "We"
   , 8 => "Th"
   , 16 => "Fr"
   , 32 => "Sa"
   , 64 => "So"
);
   
my @radio = ();
my %landevice = ();

sub ##########################################
FRITZBOX_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "FRITZBOX $instName: $sub.$xline " . $text;
}

##########################################
sub FRITZBOX_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRITZBOX_Define";
  $hash->{UndefFn}  = "FRITZBOX_Undefine";

  $hash->{SetFn}    = "FRITZBOX_Set";
  $hash->{GetFn}    = "FRITZBOX_Get";
  $hash->{AttrFn}   = "FRITZBOX_Attr";
  $hash->{AttrList} = "disable:0,1 "
                ."defaultCallerName "
                ."defaultUploadDir "
                ."fritzBoxIP "
                ."INTERVAL "
                ."ringWithIntern:0,1,2 "
                ."telnetUser "
                .$readingFnAttributes;

} # end FRITZBOX_Initialize


##########################################
sub FRITZBOX_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Usage: define <name> FRITZBOX" if(@args <2 || @args >2);  

   my $name = $args[0];

   $hash->{NAME} = $name;

   my $msg;
 
#   unless (qx ( [ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0 ))
   unless ( -X "/usr/bin/ctlmgr_ctl" )
   {
      $hash->{REMOTE} = 1;
      FRITZBOX_Log $hash, 4, "FRITZBOX runs in remote mode";
   }
   elsif ( $< != 0 ) 
   {
      $msg = "Error - FHEM is not running under root (currently " .
          ( getpwuid( $< ) )[ 0 ] .
          ") but we need to be root";
      FRITZBOX_Log $hash, 1, $msg;
      return $msg;
   }
   else
   {
      $hash->{REMOTE} = 0;
      FRITZBOX_Log $hash, 4, "FRITZBOX runs in local mode";
   }
   
   $hash->{STATE}              = "Initializing";
   $hash->{fhem}{modulVersion} = '$Date$';
   $hash->{INTERVAL}           = 300; 
   $hash->{fhem}{lastHour}     = 0;
   $hash->{fhem}{LOCAL}        = 0;
      
   RemoveInternalTimer($hash);
 # Get first data after 6 seconds
   InternalTimer(gettimeofday() + 6, "FRITZBOX_Readout_Start", $hash, 0);
 
   return undef;
} #end FRITZBOX_Define


sub ##########################################
FRITZBOX_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

   BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} )
      if exists $hash->{helper}{READOUT_RUNNING_PID}; 

   BlockingKill( $hash->{helper}{RING_RUNNING_PID} )
      if exists $hash->{helper}{RING_RUNNING_PID}; 

  return undef;
} # end FRITZBOX_Undefine


sub ##########################################
FRITZBOX_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value
   my $hash = $defs{$name};

   if ($cmd eq "set")
   {
      if ($aName eq "fritzBoxIP" && $aVal ne "")
      {
         if ($hash->{REMOTE} == 0)
         {
            $hash->{REMOTE} = 1;
            FRITZBOX_Log $hash, 3, "Changed to remote access because attribute 'fritzBoxIP' is defined.";
         }
      }
   }

   return undef;
} # FRITZBOX_Attr ende


sub ##########################################
FRITZBOX_Set($$@) 
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";
   
   my $list = "alarm"
            . " customerRingTone"
            . " convertRingTone"
            . " guestWlan:on,off"
            . " message"
            . " ring"
            . " startRadio"
            . " tam"
            . " update:noArg"
            . " wlan:on,off";

   if ( lc $cmd eq 'alarm')
   {
      if ( int @val == 2 && $val[0] =~ /^(1|2|3)$/ && $val[1] =~ /^(on|off)$/ ) 
      {
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w telcfg settings/AlarmClock".( $val[0] - 1 )."/Active ".$state );
         readingsSingleUpdate($hash,"alarm".$val[0]."_state",$val[1], 1);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'convertringtone')
   {
      if (int @val > 0) 
      {
         return FRITZBOX_ConvertRingTone $hash, @val;
      }
   }
   elsif ( lc $cmd eq 'customerringtone')
   {
      if (int @val > 0) 
      {
         return FRITZBOX_SetCustomerRingTone $hash, @val;
      }
   }
   elsif ( lc $cmd eq 'guestwlan')
   {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) 
      {
         my $state = $val[0];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w wlan settings/guest_ap_enabled $state");
         readingsSingleUpdate($hash,"box_guestWlan",$val[0], 1);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'message')
   {
      if (int @val > 0) 
      {
         $hash->{Message} = substr (join(" ", @val),0,30) ;
         return undef;
      }
   }
   elsif ( lc $cmd eq 'ring')
   {
      if (int @val > 0) 
      {
         FRITZBOX_Ring_Start $hash, @val;
         return undef;
      }
   }
   elsif( lc $cmd eq 'update' ) 
   {
      $hash->{fhem}{LOCAL}=1;
      FRITZBOX_Readout_Start($hash);
      $hash->{fhem}{LOCAL}=0;
      return undef;
   }
   elsif ( lc $cmd eq 'startradio')
   {
      if (int @val > 0) 
      {
         # FRITZBOX_Ring $hash, @val; # join("|", @val);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'tam')
   {
      if ( int @val == 2 && defined( $hash->{READINGS}{"tam".$val[0]} ) && $val[1] =~ /^(on|off)$/ ) 
      {
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w tam settings/TAM".( $val[0] - 1 )."/Active ".$state );
         readingsSingleUpdate($hash,"tam".$val[0]."_state",$val[1], 1);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'wlan')
   {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) 
      {
         my $state = $val[0];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w wlan settings/wlan_enable $state");

         $hash->{fhem}{LOCAL}=2; #2 = short update without new trigger
         FRITZBOX_Readout_Start($hash);
         $hash->{fhem}{LOCAL}=0;

         return undef;
      }
   }

   return "Unknown argument $cmd or wrong parameter(s), choose one of $list";

} # end FRITZBOX_Set


sub ##########################################
FRITZBOX_Get($@)
{
   my ($hash, $name, $cmd) = @_;
   my $returnStr;

   if (lc $cmd eq "ringtones") 
   {
      $returnStr  = "Ring tones to use with 'set <name> ring <intern> <duration> <ringTone>'\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      $returnStr .= join "\n", sort values %ringTone;
      return $returnStr;
   }

   my $list = "ringTones:noArg";
   return "Unknown argument $cmd, choose one of $list";
} # end FRITZBOX_Get

# Starts the data capturing and sets the new timer
sub ##########################################
FRITZBOX_Readout_Start($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
      
   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL",  $hash->{INTERVAL} );
   $hash->{INTERVAL} = 60 
      if $hash->{INTERVAL} < 60 && $hash->{INTERVAL} != 0;
   
   if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} != 0) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "FRITZBOX_Readout_Start", $hash, 1);
    return undef if( AttrVal($name, "disable", 0 ) == 1 );
  }

   if ( exists( $hash->{helper}{READOUT_RUNNING_PID} ) && $hash->{fhem}{LOCAL} != 1 )
   {
      FRITZBOX_Log $hash, 1, "Old readout process still running. Killing old process ".$hash->{helper}{READOUT_RUNNING_PID};
      BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} ); 
      delete($hash->{helper}{READOUT_RUNNING_PID});
   }
   
   $hash->{helper}{READOUT_RUNNING_PID} = BlockingCall("FRITZBOX_Readout_Run", $name,
                                                       "FRITZBOX_Readout_Done", 55,
                                                       "FRITZBOX_Readout_Aborted", $hash)
                         unless exists( $hash->{helper}{READOUT_RUNNING_PID} );

} # end FRITZBOX_Readout_Start

# Starts the data capturing and sets the new timer
sub ##########################################
FRITZBOX_Readout_Run($)
{
   my ($name) = @_;
   my $hash = $defs{$name};

   my $result;
   my $rName;
   my @cmdArray;
   my @readoutArray;
   my $resultArray;
   my @readoutReadings;
   my $i;
   my $startTime = time();

   my $slowRun = 0;
   if ( int(time/3600) != $hash->{fhem}{lastHour} || $hash->{fhem}{LOCAL} == 1)
   {
      push @readoutReadings, "fhem->lastHour|".int(time/3600);
      $slowRun = 1;
      FRITZBOX_Log $hash, 4, "Start update of slow changing device readings.";
   }
   else
   {
      FRITZBOX_Log $hash, 4, "Start update of fast changing device readings.";
   }

   my $returnStr = "$name|";
 
   if ($hash->{REMOTE})
   {
      $result = FRITZBOX_Telnet_Open( $hash );
      if ($result)
      {
         $returnStr .= "Error|".$result;
         return $returnStr;
      }
   }

   if ($slowRun == 1)
   {
      
     # Init and Counters
      push @readoutArray, ["", "ctlmgr_ctl r telcfg settings/Foncontrol" ];
      push @readoutArray, ["", "ctlmgr_ctl r telcfg settings/Foncontrol/User/count" ];
      push @readoutArray, ["", "ctlmgr_ctl r configd settings/WEBRADIO/count" ];
      push @readoutArray, ["", "ctlmgr_ctl r user settings/user/count" ];
      push @readoutArray, ["", 'echo $CONFIG_AB_COUNT'];
      push @readoutArray, ["", "ctlmgr_ctl r landevice settings/landevice/count" ];
      push @readoutArray, ["", "ctlmgr_ctl r tam settings/TAM/count" ];

      # Box model and firmware
      push @readoutArray, [ "box_model", 'echo $CONFIG_PRODUKT_NAME' ];
      push @readoutArray, [ "box_fwVersion", "ctlmgr_ctl r logic status/nspver", "fwupdate" ];
      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings);

      my $dectCount = $resultArray->[1];
      my $radioCount = $resultArray->[2];
      my $userCount = $resultArray->[3];
      my $fonCount = $resultArray->[4];
      my $lanDeviceCount = $resultArray->[5];
      my $tamCount = $resultArray->[6];
      
      
   # Internetradioliste erzeugen
      if ($radioCount > 0 )
      {
         $i = 0;
         @radio = ();
         $rName = "radio00";
         do 
         {
            push @readoutArray, [ $rName, "ctlmgr_ctl r configd settings/WEBRADIO".$i."/Name" ];
            $i++;
            $rName = sprintf ("radio%02d",$i);
         }
         while ( $radioCount > $i || defined $hash->{READINGS}{$rName} );

         $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );

         for (0..$radioCount-1)
         {
            $radio[$_] = $result
               if $resultArray->[$_] ne "";
            
         }
      }

   # LanDevice-Liste erzeugen
      if ($lanDeviceCount > 0 )
      {
         for (0..$lanDeviceCount-1)
         {
            push @readoutArray, [ "", "ctlmgr_ctl r landevice settings/landevice".$_."/ip" ];
            push @readoutArray, [ "", "ctlmgr_ctl r landevice settings/landevice".$_."/name" ];
         }
         $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );

         %landevice = ();
         for (0..$lanDeviceCount-1)
         {
            my $offset = 2 * $_;
            my $dIp = $resultArray->[ $offset ];
            my $dName = $resultArray->[ $offset +1];
            push @readoutReadings, "fhem->landevice->$dIp|$dName";
            $landevice{$dIp}=$dName;
         }  
      }

      # Dect Phones
      if ($dectCount>0)
      {
         for (610..615) { delete $hash->{fhem}{$_} if defined $hash->{fhem}{$_}; }
         
         for (1..6)
         {
           # 0 Dect-Interne Nummer
            push @readoutArray, [ "dect".$_."_intern", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Intern" ];
           # 1 Dect-Telefonname
            push @readoutArray, [ "dect".$_, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Name" ];
           # 2 Handset manufacturer
            push @readoutArray, [ "dect".$_."_manufacturer", "ctlmgr_ctl r dect settings/Handset".($_-1)."/Manufacturer" ];   
           # 3 Internal Ring Tone Name
            push @readoutArray, [ "dect".$_."_intRingTone", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/IntRingTone", "ringtone" ];
           # 4 Alarm Ring Tone Name
            push @readoutArray, [ "dect".$_."_alarmRingTone", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/AlarmRingTone0", "ringtone" ];
           # 5 Radio Name
            push @readoutArray, [ "dect".$_."_radio", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/RadioRingID", "radio" ];
           # 6 Background image
            push @readoutArray, [ "dect".$_."_imagePath ", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/ImagePath " ];
           # 7 Customer Ring Tone
            push @readoutArray, [ "dect".$_."_custRingTone", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingTone" ];
           # 8 Customer Ring Tone Name
            push @readoutArray, [ "dect".$_."_custRingToneName", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingToneName" ];
           # 9 Firmware Version
            push @readoutArray, [ "dect".$_."_fwVersion", "ctlmgr_ctl r dect settings/Handset".($_-1)."/FWVersion" ];   
           # 10 Phone Model
            push @readoutArray, [ "dect".$_."_model", "ctlmgr_ctl r dect settings/Handset".($_-1)."/Model", "model" ];   
         }
         $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
         for (0..5)
         {
            my $offset = $_ * 11;
            my $intern = $resultArray->[ $offset ];
            if ( $intern )
            {
               push @readoutReadings, "fhem->$intern->name|" . $resultArray->[ $offset + 1 ];
               push @readoutReadings, "fhem->$intern->brand|" . $resultArray->[ $offset + 2 ];
               push @readoutReadings, "fhem->$intern->model|" . FRITZBOX_Readout_Format($hash, "model", $resultArray->[ $offset + 10 ] );
            }
         }
      }

   # Analog Fons Name
      foreach (1..$fonCount)
      {
         push @readoutArray, ["fon".$_, "ctlmgr_ctl r telcfg settings/MSN/Port".($_-1)."/Name" ];
      }
      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
   
   # Analog Fons Number
      foreach (1..$fonCount)
      {
         push @readoutReadings, "fon".$_."_intern", $_
            if $resultArray->[$_-1];
      }

   # Anrufbeantworter (TAM)
      if ($tamCount > 0 )
      {
      # Check if TAM is displayed
         for (0..$tamCount-1)
         {
            push @readoutArray, [ "", "ctlmgr_ctl r tam settings/TAM".$_."/Display" ];
         }
         $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
      #Get TAM readings
         for (0..$tamCount-1)
         {
            $rName = "tam".($_+1);
            if ($resultArray->[$_] == 1 || defined $hash->{READINGS}{$rName} )
            {
               push @readoutArray, [ $rName, "ctlmgr_ctl r tam settings/TAM". $_ ."/Name" ];
               push @readoutArray, [ $rName."_state", "ctlmgr_ctl r tam settings/TAM".$_."/Active", "onoff" ];
               push @readoutArray, [ $rName."_newMsg", "ctlmgr_ctl r tam settings/TAM".$_."/NumNewMessages" ];
               push @readoutArray, [ $rName."_oldMsg", "ctlmgr_ctl r tam settings/TAM".$_."/NumOldMessages" ];
            }
         }
         FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
      }

# user profiles
      $i=0;
      $rName = "user01";
      do 
      {
         push @readoutArray, [$rName, "ctlmgr_ctl r user settings/user".$i."/name", "deviceip" ];
         push @readoutArray, [$rName."_thisMonthTime", "ctlmgr_ctl r user settings/user".$i."/this_month_time", "timeinhours" ];
         push @readoutArray, [$rName."_todayTime", "ctlmgr_ctl r user settings/user".$i."/today_time", "timeinhours" ];
         push @readoutArray, [$rName."_type", "ctlmgr_ctl r user settings/user".$i."/type" ];
         $i++;
         $rName = sprintf ("user%02d",$i+1);
      }
      while ($i<$userCount || defined $hash->{READINGS}{$rName});
      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
   }
   
# WLAN
   push @readoutArray, [ "box_wlan_2.4GHz", "ctlmgr_ctl r wlan settings/ap_enabled", "onoff" ];
# 2nd WLAN
   push @readoutArray, [ "box_wlan_5GHz", "ctlmgr_ctl r wlan settings/ap_enabled_scnd", "onoff" ];
# Gäste WLAN
   push @readoutArray, [ "box_guestWlan", "ctlmgr_ctl r wlan settings/guest_ap_enabled", "onoff" ];
# Alarm clock
   foreach (0..2)
   {
     # Alarm clock name
      push @readoutArray, ["alarm".($_+1), "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Name" ];
     # Alarm clock state
      push @readoutArray, ["alarm".($_+1)."_state", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Active", "onoff" ];
     # Alarm clock time
      push @readoutArray, ["alarm".($_+1)."_time", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Time", "altime" ];
     # Alarm clock number
      push @readoutArray, ["alarm".($_+1)."_target", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Number", "alnumber" ];
     # Alarm clock weekdays
      push @readoutArray, ["alarm".($_+1)."_wdays", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Weekdays", "aldays" ];
   }
   $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
   
   
   $returnStr .= join('|', @readoutReadings );
   $returnStr .= "|readoutTime|";
   $returnStr .= sprintf "%.2f", time()-$startTime;

   FRITZBOX_Telnet_Close ( $hash )
      if $hash->{REMOTE};
   
   return $returnStr
   
} # End FRITZBOX_Readout_Run

sub ##########################################
FRITZBOX_Readout_Done($) 
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, %values) = split("\\|", $string);
   my $hash = $defs{$name};
   
   # delete the marker for RUNNING_PID process
   delete($hash->{helper}{READOUT_RUNNING_PID});

   readingsBeginUpdate($hash);

   if ( defined $values{Error} )
   {
      readingsBulkUpdate( $hash, "lastReadout", $values{Error} );
      readingsBulkUpdate( $hash, "state", $values{Error} );
   }
   else
   {
      my $x = 0;
      while (my ($rName, $rValue) = each(%values) )
      {
         if ($rName =~ /->/)
         {
            my ($rName1,$rName2,$rName3) = split /->/, $rName;
            if (defined $rName3)
            {
               $hash->{$rName1}{$rName2}{$rName3} = $rValue;
            }
            else
            {
               $hash->{$rName1}{$rName2} = $rValue;
            }
         }
         elsif ($rName ne "readoutTime")
         {
            readingsBulkUpdate( $hash, $rName, $rValue );
         }
      }

      my $msg = keys( %values )." values captured in ".$values{readoutTime}." s";
      readingsBulkUpdate( $hash, "lastReadout", $msg );
      FRITZBOX_Log $hash, 4, $msg;
      my $newState = "WLAN: ";
      if ($values{"box_wlan_2.4GHz"} eq "on" || $values{box_wlan_5GHz} eq "on")
      {
         $newState .= "on";
      }
      else
      {
         $newState .= "off";
      }
      $newState .=" gWLAN: ".$values{box_guestWlan} ;
      readingsBulkUpdate( $hash, "state", $newState);
   }

   readingsEndUpdate( $hash, 1 );
}

sub ##########################################
FRITZBOX_Readout_Aborted($) 
{
  my ($hash) = @_;
  delete($hash->{helper}{READOUT_RUNNING_PID});
  FRITZBOX_Log $hash, 1, "Timeout when reading Fritz!Box data.";
}

##########################################
sub FRITZBOX_Readout_Query($$$)
{
   my ($hash, $readoutArray, $readoutReadings) = @_;
   my @cmdArray;
   my $rValue;
   my $rName;
   my $rFormat;
      
   my $count = int @{$readoutArray} - 1;
   for (0..$count)
   {
      push @cmdArray, $readoutArray->[$_][1];
   }

   my $resultArray = FRITZBOX_Exec( $hash, \@cmdArray);
   $count = int @{$resultArray} -1;
   for (0..$count)
   {
      $rValue = $resultArray->[$_];
      $rFormat = $readoutArray->[$_][2];
      $rFormat = "" unless defined $rFormat;
      $rValue = FRITZBOX_Readout_Format ($hash, $rFormat, $rValue);
      $rName = $readoutArray->[$_][0];
      if ($rName ne "")
      {
         if ($rValue ne "")
         {
            FRITZBOX_Log $hash, 5, "$rName: $rValue";
            push @{$readoutReadings}, $rName."|".$rValue;
         }
         elsif (defined $hash->{READINGS}{$rName} ) 
         {
            FRITZBOX_Log $hash, 5, "Delete $rName";
            delete $hash->{READINGS}{$rName};
         }
      }
   }
   @{$readoutArray} = ();
   
   return $resultArray;
}

sub ##########################################
FRITZBOX_Readout_Format($$$) 
{
   my ($hash, $format, $readout) = @_;
   
   return $readout 
      unless defined $format;
   return $readout 
      unless $readout ne "" && $format ne "" ;

   if ($format eq "altime") {
      $readout =~ s/(\d\d)(\d\d)/$1:$2/;
   } elsif ($format eq "aldays") {
      if ($readout == 0) {
         $readout = "once";
      } elsif ($readout == 127) {
         $readout = "daily";
      } else {
         my $bitStr = $readout;
         $readout = "";
         foreach (sort keys %alarmDays)
         {
            $readout .= (($bitStr & $_) == $_) ? $alarmDays{$_}." " : "";
         }
      }
   } elsif ($format eq "alnumber") {
      my $intern = $readout;
      if (1 <= $readout && $readout <=2) {
         $readout = "FON $intern";
      } elsif ($readout == 9) {
         $readout = "all DECT";
      } elsif (60 <= $readout && $readout <=65) {
         $intern = $readout + 550;
         $readout = "DECT $intern";
      } elsif ($readout == 50) {
         $readout = "all";
      }
      $readout .= " (".$hash->{fhem}{$intern}{name}.")"
         if defined $hash->{fhem}{$intern}{name};
   } elsif ($format eq "fwupdate") {
      my $update = FRITZBOX_Exec( $hash, "ctlmgr_ctl r updatecheck status/update_available_hint");
      $readout .= " (old)" if $update == 1;
   } elsif ($format eq "model") {
      $readout = $fonModel{$readout} if defined $fonModel{$readout};
   
   } elsif ($format eq "nounderline") {
      $readout =~ s/_/ /g;

   } elsif ($format eq "onoff") {
      $readout =~ s/0/off/;
      $readout =~ s/1/on/;
   
   } elsif ($format eq "radio") {
      $readout = $radio[$readout];
  
   } elsif ($format eq "ringtone") {
      $readout = $ringTone{$readout};
   
   } elsif ($format eq "timeinhours") {
      $readout = sprintf "%d h %d min", int $readout/3600, int( ($readout %3600) / 60);

   } elsif ($format eq "deviceip") {
      $readout = $landevice{$readout}." ($readout)"
         if defined $landevice{$readout};
   }
   $readout = "" unless defined $readout;
   return $readout;
}

sub ##########################################
FRITZBOX_Ring_Start($@) 
{
   my ($hash, @val) = @_;
   my $name = $hash->{NAME};
   
   $val[1] = 5 
      unless defined $val[1]; 

   if ( exists( $hash->{helper}{RING_RUNNING_PID} ) )
   {
      FRITZBOX_Log $hash, 1, "Old process still running. Killing old process ".$hash->{helper}{RING_RUNNING_PID};
      BlockingKill( $hash->{helper}{RING_RUNNING_PID} ); 
      delete($hash->{helper}{RING_RUNNING_PID});
   }
   
   my $timeout = $val[1] + 30;
   my $handover = $name . "|" . join( "|", @val );
   
   $hash->{helper}{RING_RUNNING_PID} = BlockingCall("FRITZBOX_Ring_Run", $handover,
                                       "FRITZBOX_Ring_Done", $timeout,
                                       "FRITZBOX_Ring_Aborted", $hash)
                              unless exists $hash->{helper}{RING_RUNNING_PID};
} # end FRITZBOX_Ring_Start

sub ##########################################
FRITZBOX_Ring_Run($) 
{
   my ($string) = @_;
   my ($name, @val) = split /\|/, $string;
   my $hash = $defs{$name};
   
   my $fonType;
   my $fonTypeNo;
   my $result;
   my $curIntRingTone;
   my $curCallerName;
   my $cmd;
   my @cmdArray;

   my $intNo;
   $intNo = $val[0]
      if $val[0] =~ /^\d+$/;
   return $name."|0|Error: Parameter '".$val[0]."' not a number"
      unless defined $intNo;
   shift @val;
   
   $fonType = $hash->{fhem}{$intNo}{brand};
   return $name."|0|Error: Internal number '$intNo' not a DECT number" 
      unless defined $fonType;
   $fonTypeNo = $intNo - 609;
   
   
   my $duration = 5;
   if ($val[0] !~ /^msg:/i)
   {
      $duration = $val[0]
         if defined $val[0];
      shift @val;
      return $name."|0|Error: Duration '".$val[0]."' not a positiv integer" 
         unless $duration =~ /^\d+$/;
   }
   
   my $ringTone;
   if (int @val)
   {
      if ($val[0] !~ /^msg:/i)
      {
         $ringTone = $val[0]
            unless $fonType ne "AVM";
         if (defined $ringTone)
         {
            $ringTone = $ringToneNumber{lc $val[0]};
            return $name."|0|Error: Ring tone '".$val[0]."' not valid"
               unless defined $ringTone;
         }
         shift @val;
      }
   }
      
   my $msg = AttrVal( $name, "defaultCallerName", "FHEM" );
   if (int @val > 0)
   {
      return $name."|0|Error: Too many parameter. Message has to start with 'msg:'"
         if ($val[0] !~ /^msg:/i);
      $msg = join " ", @val;
      $msg =~ s/^msg:\s*//;
      $msg = substr($msg, 0, 30);
   }
   if ($hash->{REMOTE})
   {
      $result = FRITZBOX_Telnet_Open( $hash );
      return "$name|0|$result" if $result;
   }

#Preparing 1st command array
   @cmdArray = ();
# Change ring tone of Fritz!Fons
   if (defined $ringTone)
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$ringTone;
      FRITZBOX_Log $hash, 4, "Change temporarily internal ring tone of DECT ".$fonTypeNo." to ".$ringTone;
   }

# uses name of virtual port 0 (dial port 1) to show message on ringing phone
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 0 );
   if ($ringWithIntern =~ /^(1|2)$/ )
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/MSN/Port".($ringWithIntern-1)."/Name";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$msg'";
      FRITZBOX_Log $hash, 4, "Change temporarily name of calling number $ringWithIntern to '$msg'";
   }
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort ".$ringWithIntern
      if $ringWithIntern != 0 ;
   $result = FRITZBOX_Exec( $hash, \@cmdArray )
      if int( @cmdArray ) > 0;

#Preparing 2nd command array to ring and reset everything
   FRITZBOX_Log $hash, 4, "Ringing $intNo for $duration seconds";
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo;
   push @cmdArray, "sleep ".($duration+1);
   push @cmdArray, "ctlmgr_ctl w telcfg command/Hangup **".$intNo;
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort 50"
      if $ringWithIntern != 0 ;
   if (defined $ringTone)
   {
      push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$result->[0];
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[2]."'"
         if $ringWithIntern =~ /^(1|2)$/;
   }
   elsif ($ringWithIntern =~ /^(1|2)$/)
   {
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[0]."'";
   }
   FRITZBOX_Exec( $hash, \@cmdArray );

   FRITZBOX_Telnet_Close( $hash )
      if ($hash->{REMOTE});

   return $name."|1|Ringing done";
}

sub ##########################################
FRITZBOX_Ring_Done($) 
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, $success, $result) = split("\\|", $string);
   my $hash = $defs{$name};
   
   delete($hash->{helper}{RING_RUNNING_PID});

   if ($success != 1)
   {
      FRITZBOX_Log $hash, 1, $result;
   }
   else
   {
      FRITZBOX_Log $hash, 4, $result;
   }
}

sub ##########################################
FRITZBOX_Ring_Aborted($) 
{
  my ($hash) = @_;
  delete($hash->{helper}{RING_RUNNING_PID});
  FRITZBOX_Log $hash, 1, "Timeout when ringing";
}

sub ############################################
FRITZBOX_SetCustomerRingTone($@)
{  
   my ($hash, $intern, @file) = @_;
   my $returnStr;
   my $name = $hash->{NAME};

   my $uploadDir = AttrVal( $name, "defaultUploadDir",  "" );
   $uploadDir .= "/"
      unless $uploadDir =~ /\/$|^$/;

   my $inFile = join " ", @file;
   $inFile = $uploadDir.$inFile
      unless $inFile =~ /^\//;
   
   return "Error: Please give a complete file path or the attribute 'defaultUploadDir'"
      unless $inFile =~ /^\//;
   
   return "Error: Only MP3 or G722 files can be uploaded to the phone."
      unless $inFile =~ /\.mp3$|.g722$/i;
   
   my $uploadFile = '/var/InternerSpeicher/FRITZ/fonring/'.time().'.g722';
   
   $inFile =~ s/file:\/\///i;
   if ( $inFile =~ /\.mp3$/i )
   {
      # mp3 files are converted
      $returnStr = FRITZBOX_Exec ($hash
      , 'picconv.sh "file://'.$inFile.'" "'.$uploadFile.'" ringtonemp3');
   }
   elsif ( $inFile =~ /\.g722$/i )
   {
      # G722 files are copied
      $returnStr = FRITZBOX_Exec ($hash,
         "cp '$inFile' '$uploadFile'");
   }
   else
   {
      return "Error: only MP3 or G722 files can be uploaded to the phone";
   }
   # trigger the loading of the file to the phone, file will be deleted as soon as the upload finished
   $returnStr .= "\n".FRITZBOX_Exec ($hash,
      '/usr/bin/pbd --set-ringtone-url --book="255" --id="'.$intern.'" --url="file://'.$uploadFile.'" --name="FHEM'.time().'"');
   return $returnStr;
}

sub ############################################
FRITZBOX_ConvertRingTone ($@)
{  
   my ($hash, @file) = @_;

   my $name = $hash->{NAME};

   my $uploadDir = AttrVal( $name, "defaultUploadDir",  "" );
   $uploadDir .= "/"
      unless $uploadDir =~ /\/$|^$/;

   my $inFile = join " ", @file;
   $inFile = $uploadDir.$inFile
      unless $inFile =~ /^\//;
   
   return "Error: You have to give a complete file path or to set the attribute 'defaultUploadDir'"
      unless $inFile =~ /^\//;
   
   return "Error: only MP3 or WAV files can be converted"
      unless $inFile =~ /\.mp3$|.wav$/i;
   
   $inFile =~ s/file:\/\///;

   my $outFile = $inFile;
   $outFile = substr($inFile,0,-4)
      if ($inFile =~ /\.(mp3|wav)$/i);
   my $returnStr = FRITZBOX_Exec ($hash
      , 'picconv.sh "file://'.$inFile.'" "'.$outFile.'.g722" ringtonemp3');
   return $returnStr;
}

#'picconv.sh "'.$inFile.'" "'.$outFile.'.g722" ringtonemp3'
#picconv.sh "file://$dir/upload.mp3" "$dir/$filename" ringtonemp3   
#"ffmpegconv  -i '$inFile' -o '$outFile.g722' --limit 240");
#ffmpegconv -i "${in}" -o "${out}" --limit 240
#pbd --set-image-url --book=255 --id=612 --url=/var/InternerSpeicher/FRITZ/fonring/1416431162.g722 --type=1
#pbd --set-image-url --book=255 --id=612 --url=file://var/InternerSpeicher/FRITZBOXtest.g722 --type=1
#ctlmgr_ctl r user settings/user0/bpjm_filter_enable
#/usr/bin/pbd --set-ringtone-url --book="255" --id="612" --url="file:///var/InternerSpeicher/claydermann.g722" --name="Claydermann"
# telcfg:settings/MOHType
# /usr/bin/moh_upload
# ffmpegconv -i $file -o fx_moh --limit 32 --type 6
# cat fx_moh >/var/flash/fx_moh

# Opens a Telnet Connection to an external FritzBox
############################################
sub FRITZBOX_Telnet_Open($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $host = AttrVal( $name, "fritzBoxIP", "fritz.box" );

   my $pwdFile = "fb_pwd.txt";
   my $pwd;
   my $msg;
   
   FRITZBOX_Log $hash, 5, "Open password file '$pwdFile' to extract password";
   if (open(IN, "<" . $pwdFile)) {
      $pwd = <IN>;
      close(IN);
     FRITZBOX_Log $hash, 5, "Close password file";
   } else {
      $msg = "Error: Cannot open password file '$pwdFile': $!";
      FRITZBOX_Log $hash, 2, $msg;
      return $msg;
   }
   
   my $user = AttrVal( $name, "telnetUser", "" );

   FRITZBOX_Log $hash, 4, "Open Telnet Connection to $host";
   $telnet = new Net::Telnet ( Host=>$host, Port => 23, Timeout=>10, Errmode=>'return', Prompt=>'/# $/');
   if (!$telnet) {
      $msg = "Error while opening telnet connection: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet = undef;
      return $msg;
   }

   if ( $user ne "" )
   {
      FRITZBOX_Log $hash, 5, "Telnet: Wait for user prompt";
      unless ($telnet->waitfor( '/user: $/i' ))
      {
         $msg = "Error while waiting for user prompt: ".$telnet->errmsg;
         FRITZBOX_Log $hash, 2, $msg;
         $telnet->close;
         $telnet = undef;
         return $msg;
      }
      FRITZBOX_Log $hash, 5, "Telnet: Entering user";
      $telnet->print( $user );
   }
   
   FRITZBOX_Log $hash, 5, "Telnet: Wait for password prompt";
   unless ($telnet->waitfor( '/password: $/i' ))
   {
      $msg = "Error while waiting for password prompt: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   FRITZBOX_Log $hash, 5, "Telnet: Entering password";
   $telnet->print( $pwd );

   FRITZBOX_Log $hash, 5, "Telnet: Wait for command prompt";
   unless ($telnet->waitfor( '/# $/i' ))
   {
      $msg = "Error while waiting for command prompt: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }

   return undef;
} # end FRITZBOX_Telnet_Open

   
# Closes a Telnet Connection to an external FritzBox
############################################
sub FRITZBOX_Telnet_Close($)
{
   my ($hash) = @_;
   if (defined $telnet)
   {
      FRITZBOX_Log $hash, 4, "Close Telnet connection";
      $telnet->close;
      $telnet = undef;
   }
   else
   {
      FRITZBOX_Log $hash, 1, "Cannot close an undefined Telnet connection";
   }
} # end FRITZBOX_Telnet_Close
   
# Executed the command on the FritzBox Shell
############################################
sub FRITZBOX_Exec($$)
{
   my ($hash, $cmd) = @_;
   my $openedTelnet = 0;
   
   if ($hash->{REMOTE} == 1)
   {
      unless (defined $telnet)
      {
         return undef
            if (FRITZBOX_Telnet_Open($hash));
         $openedTelnet = 1;
      }
      my $retVal = FRITZBOX_Exec_Remote($hash, $cmd);
      FRITZBOX_Telnet_Close ( $hash ) if $openedTelnet;
      return $retVal;
   }
   else
   {
      return FRITZBOX_Exec_Local($hash, $cmd);
   }

}

# Executed the command via Telnet
sub ############################################
FRITZBOX_Exec_Remote($$)
{
   my ($hash, $cmd) = @_;
   my @output;
   my $result;

      
   if (ref \$cmd eq "SCALAR")
   {
      FRITZBOX_Log $hash, 4, "Execute '".$cmd."'";
      @output=$telnet->cmd($cmd);
      $result = $output[0];
      chomp $result;
      FRITZBOX_Log $hash, 4, "Result '$result'";
      return $result;
   }
   elsif (ref \$cmd eq "REF")
   {
      my @resultArray = ();
      if ( int (@{$cmd}) > 0 )
      {
         FRITZBOX_Log $hash, 4, "Execute " . int ( @{$cmd} ) . " command(s)";

         # my $cmdStr = join "\n", @{$cmd};
         # $cmdStr .= "\necho Ende1  Ende2\n";
         # $telnet->put( $cmdStr );
         # my ( $result,$match ) = $telnet->waitfor('/Ende1\sEnde2/');
         # my @test = split( /\n/, "# ".$result );
         # my $lastValue = "";
         # foreach (@test)
         # { 
            # if ($_ =~ /^# /)
            # {
               # push @resultArray, $lastValue;
               # $lastValue = "";
            # }
            # else
            # {
               # $lastValue = $_;
            # }
         # }
         # shift @resultArray;
         # $telnet->buffer_empty;
    
         foreach (@{$cmd})
         {
            FRITZBOX_Log $hash, 5, "Execute '".$_."'";
            unless ($_ =~ /^sleep/)
            {
               @output=$telnet->cmd($_);
               $result = $output[0];;
               $result =~ s/\n|\r|\s$//g;
            }
            else
            {
               FRITZBOX_Log $hash, 4, "Do '$_' in perl.";
               eval ($_);
               $result = "";
            }
            push @resultArray, $result;
            FRITZBOX_Log $hash, 5, "Result '$result'";
         }
         @{$cmd} = ();
         FRITZBOX_Log $hash, 4, "Received ".int(@resultArray)." answer(s)";
      }
      else
      {
         FRITZBOX_Log $hash, 4, "No shell command to execute.";
      }
      return \@resultArray;
   }
   else
   {
      FRITZBOX_Log $hash, 1, "Error: wrong perl parameter";
      return undef;
   }
}

# Executed the command on the FritzBox Shell
sub ############################################
FRITZBOX_Exec_Local($$)
{
   my ($hash, $cmd) = @_;
   
   
   if (ref \$cmd eq "SCALAR")
   {
      FRITZBOX_Log $hash, 5, "Execute '".$cmd."'";
      my $result = qx($cmd);
      chomp $result;
      FRITZBOX_Log $hash, 5, "Result '$result'";
      return $result;
   }
   elsif (ref \$cmd eq "REF")
   {
      if ( int (@{$cmd}) > 0 )
      {
         FRITZBOX_Log $hash, 4, "Execute " . int ( @{$cmd} ) . " command(s)";
         FRITZBOX_Log $hash, 5, "Commands: '" . join( " | ", @{$cmd} ) . "'";
         my $cmdStr = join "\necho ' |#|'\n", @{$cmd};
         $cmdStr .= "\necho ' |#|'";
         my $result = qx($cmdStr);
         $result =~ s/\n|\r//g;
         my @resultArray = split /\|#\|/, $result;
         foreach (keys @resultArray)
         { 
            $resultArray[$_] =~ s/\s$//;
         }
         @{$cmd} = ();
         FRITZBOX_Log $hash, 4, "Received ".int(@resultArray)." answer(s)";
         FRITZBOX_Log $hash, 5, "Result: '" . join (" | ", @resultArray)."'";
         return \@resultArray;
      }
      else
      {
         FRITZBOX_Log $hash, 4, "No shell command to execute.";
      }
   }
   else
   {
      FRITZBOX_Log $hash, 1, "Error: wrong perl parameter";
   }
}

##################################### 
sub FRITZBOX_fritztris($)
{
  my ($d) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a FRITZBOX instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "FRITZBOX");

   my $returnStr = '<script type="text/javascript" src="http://fritz.box/js/fritztris.js"></script>';
   $returnStr .= '<link rel="stylesheet" type="text/css" href="http://fritz.box/css/default/fritztris.css"/>';
   $returnStr .= '<style>#game table td {width:15px;height:15px;border-width:0px;background-repeat: no-repeat;background-position: center;-moz-border-radius: 4px;-webkit-border-radius: 4px;border-radius: 4px;}</style>';
   $returnStr .= '<script type="text/javascript">';
   $returnStr .= 'var game = null;';
   $returnStr .= 'function play() {';
   $returnStr .= 'if (game) {';
   $returnStr .= 'game.stop();';
   $returnStr .= 'game = null;';
   $returnStr .= '}';
   $returnStr .= 'var game = new FRITZtris(document.getElementById("game"));';
   $returnStr .= 'game.start();';
   $returnStr .= 'game.gameOverCb = gameOver;';
   $returnStr .= '}';
   $returnStr .= 'function gameOver() {';
#   $returnStr .= 'alert("Das Spiel ist vorbei.");';
   $returnStr .= 'game.stop();';
   $returnStr .= 'game = null;';
   $returnStr .= '}';
   $returnStr .= '</script>';
   $returnStr .= '<table><tr><td valign=top><u><b>FritzTris</b></u>';
   $returnStr .= '<br><a href="#" onclick="play();">Start</a>';
   $returnStr .= '<br><a href="#" onclick="gameOver();">Stop</a></td>';
   $returnStr .= '<td><div id="game"></div></td></tr></table>';

   return $returnStr;
}
##################################### 

1;

=pod
=begin html

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
<div  style="width:800px"> 
<ul>
   Controls some features of a Fritz!Box router. Connected Fritz!Fon's (MT-F, MT-D, C3, C4) can be used as
   signaling devices. The modul switches in local mode if FHEM runs on a Fritz!Box (as root user!).
   <br/><br/>
   If FHEM does not run on a Fritz!Box, it tries to open a telnet connection to "fritz.box", so telnet (#96*7*) has to be enabled on the Fritz!Box. For remote access the password must be stored in the file 'fb_pwd.txt' in the root directory of FHEM.
   <br/><br/>
   Check also the other Fritz!Box moduls: <a href="#SYSMON">SYSMON</a> and <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>So fare, the module has been tested on Fritz!Box 7390 and 7490 and Fritz!Fon MT-F and C4.</i>
   <br>
   <i>The modul uses the Perl modul 'Net::Telnet' for remote access.</i>
   <br/><br/>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX</code>
      <br/><br/>
      Example: <code>define Fritzbox FRITZBOX</code>
      <br/><br/>
      The Fritz!Box OS has a hidden function (easter egg).
      <br>
      Test it with: <code>define MyEasterEgg weblink htmlCode { FRITZBOX_fritztris("Fritzbox") }</code>
      <br/><br/>
   </ul>
  
   <a name="FRITZBOXset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; alarm &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Switches the alarm number (1, 2 or 3) on or off.
      </li><br>
      <li><code>set &lt;name&gt; guestWLAN &lt;on|off&gt;</code>
         <br>
         Switches the guest WLAN on or off.
      </li><br>
      <li><code>set &lt;name&gt; convertRingTone &lt;fullFilePath&gt;</code>
         <br>
         Converts the mp3-file fullFilePath to a G722 format and puts it in the same path.
         <br>
         The file has to be placed on the file system of the fritzbox.
      </li><br>
      <li><code>set &lt;name&gt; convertMusicOnHold &lt;fullFilePath&gt;</code>
         <br>
         <i>Not implemented yet.</i> Converts the mp3-file fullFilePath to a format that can be used for "Music on Hold".
         <br>
         The file has to be placed on the file system of the fritzbox.
      </li><br>
      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;fullFilePath&gt;</code>
         <br>
         Uploads the file fullFilePath on the given handset. Only mp3 or G722 format is allowed.
         <br>
         The file has to be placed on the file system of the fritzbox.
         <br>
         The upload takes about one minute before the tone is available.
      </li><br>
      <li><code>set &lt;name&gt; musicOnHold &lt;fullFilePath&gt;</code>
         <br>
         <i>Not implemented yet.</i> Uploads the file fullFilePath as "Music on Hold". Only mp3 or the MOH-format is allowed.
         <br>
         The file has to be placed on the file system of the fritzbox.
         <br>
         The upload takes about one minute before the tone is available.
      </li><br>
      <li><code>set &lt;name&gt; ring &lt;internalNumber&gt; [duration [ringTone]] [msg:yourMessage]</code>
         Example: <code>set fritzbox ring 612 5 Budapest msg:It is raining</code>
         <br>
         Rings the internal number for "duration" seconds with the given "ring tone" name.
         <br>
         Default duration is 5 seconds. Default ring tone is the internal ring tone of the device.
         <br>
         The text behind 'msg:' will be shown as the callers name. 
         Maximal 30 characters are allowed.
         The attribute "ringWithIntern" must also be specified.
         <br>
         If the call is taken the callee hears the "music on hold" which can be used to transmit messages.
      </li><br>
      <li><code>set &lt;name&gt; startradio &lt;internalNumber&gt; [name]</code>
         <br>
         <i>Not implemented yet.</i> Starts the internet radio on the given Fritz!Fon
         <br>
      </li><br>
      <li><code>set &lt;name&gt; tam &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Switches the answering machine number (1-10) on or off.
      </li><br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Starts an update of the device readings.
      </li><br>
      <li><code>set &lt;name&gt; wlan &lt;on|off&gt;</code>
         <br>
         Switches WLAN on or off.
      </li><br>
   </ul>  

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; ringTones</code>
         <br>
         Shows a list of ring tones that can be used.
      </li><br>
   </ul>  
  
   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>defaultCallerName</code>
         <br>
         The default text to show on the ringing phone as 'caller'.
         <br>
         This is done by temporarily changing the name of the calling internal number during the ring.
         <br>
         Maximal 30 characters are allowed. The attribute "ringWithIntern" must also be specified.
      </li><br>
      <li><code>defaultUploadDir &lt;fritzBoxPath&gt;</code>
         <br>
         This is the default path that will be used if a file name does not start with / (slash).
         <br>
         It needs to be the name of the path on the Fritz!Box. So, it should start with /var/InternerSpeicher if it equals in Windows \\ip-address\fritz.nas
      </li><br>
      <li><code>fritzBoxIP</code>
         <br>
         IP address or URL of the Fritz!Box for remote telnet access. Default is "fritz.box".
      </li><br>
      <li><code>telnetUser &lt;user name&gt;</code>
         <br>
         User name that is used for telnet access. By default no user name is required to login.
         <br>
         If the Fritz!Box is configured differently, the user name has to be defined with this attribute.
      </li><br>
      <li><code>ringWithIntern &lt;internalNumber&gt;</code>
         <br>
         To ring a fon a caller must always be specified. Default of this modul is 50 "ISDN:W&auml;hlhilfe".
         <br>
         To show a message (default: "FHEM") during a ring the internal phone numbers 1 or 2 can be specified here.
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="FRITZBOXreading"></a>
   <b>Readings</b>
   <ul><br>
      <li><b>alarm</b><i>1</i> - Name of the alarm clock <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_state</b> - Current state of the alarm clock <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_target</b> - Internal number of the alarm clock <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_time</b> - Alarm time of the alarm clock <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_wdays</b> - Weekdays of the alarm clock <i>1</i></li>
      <li><b>box_fwVersion</b> - Firmware version of the box, if outdated then '(old)' is appended</li>
      <li><b>box_guestWlan</b> - Current state of the guest WLAN</li>
      <li><b>box_model</b> - Fritz!Box model</li>
      <li><b>box_wlan_2.4GHz</b> - Current state of the 2.4 GHz WLAN</li>
      <li><b>box_wlan_5GHz</b> - Current state of the 5 GHz WLAN</li>
      <li><b>dect</b><i>1</i> - Name of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_alarmRingTone</b> - Alarm ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_custRingTone</b> - Customer ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_fwVersion</b> - Firmware Version of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Internal number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Internal ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Manufacturer of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_model</b> - Model of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i> - Internal name of the analog FON connection <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Internal number of the analog FON connection <i>1</i></li>
      <li><b>radio</b><i>01</i> - Name of the internet radio station <i>01</i></li>
      <li><b>tam</b><i>1</i> - Name of the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_newMsg</b> - New messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_oldMsg</b> - Old messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_state</b> - Current state of the answering machine <i>1</i></li>
   </ul>
   <br>
</ul>
</div>

=end html

=cut-