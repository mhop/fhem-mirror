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
my $missingModul;
my $missingModulRemote;
eval "use Net::Telnet;1" or $missingModulRemote .= "Net::Telnet ";
eval "use URI::Escape;1" or $missingModul .= "URI::Escape ";

sub FRITZBOX_Log($$$);
sub FRITZBOX_Init($);
sub FRITZBOX_Cmd_Start($);
sub FRITZBOX_Exec($$);
sub FRITZBOX_SendMail($@);
sub FRITZBOX_SetMOH($@);
sub FRITZBOX_StartRadio($@);

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
 
my %userType = (
   1 => "IP"
 , 2 => "PC User"
 , 3 => "Default"
 , 4 => "Guest"
);

my @mohtype = qw(default sound customer);

my %landevice = ();

# FIFO Buffer for commands
my @cmdBuffer=();
my $cmdBufferTimeout=0;

my $ttsCmdTemplate = 'wget -U Mozilla -O "[ZIEL]" "http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT]"';
my $ttsLinkTemplate = 'http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT]';
   
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
                ."pwdFile "
                ."ringWithIntern:0,1,2 "
                ."telnetUser "
                ."telnetTimeOut "
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
   if ( $missingModul ) 
   {
      $msg = "Cannot define a FRITZBOX device. Perl modul $missingModul is missing.";
      FRITZBOX_Log $hash, 1, $msg;
      return $msg;
   }

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

   $hash->{helper}{TimerReadout} = $name.".Readout";
   $hash->{helper}{TimerCmd} = $name.".Cmd";
   
   RemoveInternalTimer($hash->{helper}{TimerReadout});
 # Get first data after 6 seconds
   InternalTimer(gettimeofday() + 6, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 0);
 
   return undef;
} #end FRITZBOX_Define


sub ##########################################
FRITZBOX_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash->{helper}{TimerReadout});
  RemoveInternalTimer($hash->{helper}{TimerCmd});

   BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} )
      if exists $hash->{helper}{READOUT_RUNNING_PID}; 

   BlockingKill( $hash->{helper}{CMD_RUNNING_PID} )
      if exists $hash->{helper}{CMD_RUNNING_PID}; 

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
            . " createPwdFile"
            . " customerRingTone"
            . " diversity"
            . " guestWlan:on,off"
            . " moh"
            . " ring"
            . " sendMail"
            . " startRadio"
            . " tam"
            . " update:noArg"
            . " wlan:on,off";
            # . " convertMOH"
            # . " convertRingTone"
   if ( lc $cmd eq 'alarm')
   {
      if ( int @val == 2 && $val[0] =~ /^(1|2|3)$/ && $val[1] =~ /^(on|off)$/ ) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w telcfg settings/AlarmClock".( $val[0] - 1 )."/Active ".$state );
         readingsSingleUpdate($hash,"alarm".$val[0]."_state",$val[1], 1);
         return undef;
      }

   # } elsif ( lc $cmd eq 'convertmoh') {
      # if (int @val > 0) 
      # {
         # Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         # return FRITZBOX_ConvertMOH $hash, @val;
      # }

   # } elsif ( lc $cmd eq 'convertringtone') {
      # if (int @val > 0) 
      # {
         # Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         # return FRITZBOX_ConvertRingTone $hash, @val;
      # }
      
   } elsif ( lc $cmd eq 'createpwdfile') {
      if (int @val > 0) 
      {
         my $pwdFile = AttrVal( $name, "pwdFile", "fb_pwd.txt");
         open( FILE, ">".$pwdFile) 
            or return "Error when opening password file '$pwdFile': ".$!;
         print FILE join( " ", @val);
         close FILE
            or return "Error when closing password file '$pwdFile': ".$!;
         return "Created password file '$pwdFile'";
      }

   } elsif ( lc $cmd eq 'customerringtone') {
      if (int @val > 0) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         return FRITZBOX_SetCustomerRingTone $hash, @val;
      }
      
   } elsif ( lc $cmd eq 'diversity') {
      if ( int @val == 2 && defined( $hash->{READINGS}{"diversity".$val[0]} ) && $val[1] =~ /^(on|off)$/ ) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w telcfg settings/Diversity".( $val[0] - 1 )."/Active ".$state );
         readingsSingleUpdate($hash,"diversity".$val[0]."_state",$val[1], 1);
         return undef;
      }
      
   } elsif ( lc $cmd eq 'guestwlan') {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[0];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w wlan settings/guest_ap_enabled $state");
         readingsSingleUpdate($hash,"box_guestWlan",$val[0], 1);
         return undef;
      }
   }

   elsif ( lc $cmd eq 'moh')
   {
      if (int @val > 0) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         $resultStr = FRITZBOX_SetMOH $hash, @val;
         if ($resultStr =~ /^[012]$/ )
         {
            readingsSingleUpdate($hash,"box_guestWlan",$mohtype[$resultStr], 1);
            return undef;
         }
         else
         {
            return $resultStr;
         }
      }
   }

   elsif ( lc $cmd eq 'ring')
   {
      if (int @val > 0) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "ring ".join(" ", @val);
         FRITZBOX_Cmd_Start $hash->{helper}{TimerCmd};
         return undef;
      }
   }
   elsif ( lc $cmd eq 'sendmail')
   {
      Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
      FRITZBOX_SendMail $hash, @val;
      return undef;
   }
   elsif ( lc $cmd eq 'startradio')
   {
      if (int @val > 0) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         return FRITZBOX_StartRadio $hash, @val;
      }
   }
   elsif ( lc $cmd eq 'tam')
   {
      if ( int @val == 2 && defined( $hash->{READINGS}{"tam".$val[0]} ) && $val[1] =~ /^(on|off)$/ ) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w tam settings/TAM".( $val[0] - 1 )."/Active ".$state );
         readingsSingleUpdate($hash,"tam".$val[0]."_state",$val[1], 1);
         return undef;
      }
   }
   elsif( lc $cmd eq 'update' ) 
   {
      Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
      $hash->{fhem}{LOCAL}=1;
      FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL}=0;
      return undef;
   }
   elsif ( lc $cmd eq 'wlan')
   {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[0];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w wlan settings/wlan_enable $state");

         $hash->{fhem}{LOCAL}=2; #2 = short update without new trigger
         FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
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
   my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex( $timerpara, "." );    # rechter punkt
   my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash = $defs{$name};
      
   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL",  $hash->{INTERVAL} );
   $hash->{INTERVAL} = 60 
      if $hash->{INTERVAL} < 60 && $hash->{INTERVAL} != 0;
   
   if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} != 0) {
    RemoveInternalTimer($hash->{helper}{TimerReadout});
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 1);
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
 
   $result = FRITZBOX_Open_Connection( $hash );
   return "$name|Error|$result"
      if $result;
   
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
      push @readoutArray, ["", "ctlmgr_ctl r telcfg settings/RefreshDiversity" ];
      push @readoutArray, ["", "ctlmgr_ctl r telcfg settings/Diversity/count" ];

   # Box model and firmware
      push @readoutArray, [ "box_model", 'echo $CONFIG_PRODUKT_NAME' ];
      push @readoutArray, [ "box_fwVersion", "ctlmgr_ctl r logic status/nspver" ];
      push @readoutArray, [ "box_fwUpdate", "ctlmgr_ctl r updatecheck status/update_available_hint" ];
      push @readoutArray, [ "box_tr069", "ctlmgr_ctl r tr069 settings/enabled", "onoff" ];

   # Execute commands
      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings);

      my $dectCount = $resultArray->[1];
      my $radioCount = $resultArray->[2];
      my $userCount = $resultArray->[3];
      my $fonCount = $resultArray->[4];
      my $lanDeviceCount = $resultArray->[5];
      my $tamCount = $resultArray->[6];
      my $divCount = $resultArray->[8];
      
      
   # Internetradioliste erzeugen
      $i = 0;
      $rName = "radio00";
      while ( $i<$radioCount || defined $hash->{READINGS}{$rName} )
      {
         push @readoutArray, [ $rName, "ctlmgr_ctl r configd settings/WEBRADIO".$i."/Name" ];
         $i++;
         $rName = sprintf ("radio%02d",$i);
      }

      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );

      # @radio = ();
      for (0..$radioCount-1)
      {
         if ($resultArray->[$_] ne "")
         {
            # $radio[$_] = $resultArray->[$_];
            push @readoutReadings, "fhem->radio->".$_."|".$resultArray->[$_];
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
      for (610..615) { delete $hash->{fhem}{$_} if defined $hash->{fhem}{$_}; }
      
      for (1..$dectCount)
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
         push @readoutArray, [ "dect".$_."_imagePath", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/ImagePath" ];
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
      
      for (0..$dectCount-1)
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

   # Analog Fons Name
      for (1..$fonCount)
      {
         push @readoutArray, ["fon".$_, "ctlmgr_ctl r telcfg settings/MSN/Port".($_-1)."/Name" ];
      }
      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
   
   # Analog Fons Number
      for (1..$fonCount)
      {
         push @readoutReadings, "fon".$_."_intern", $_
            if $resultArray->[$_-1];
      }

# Prepare new command array
   # Check if TAM is displayed
      for (0..$tamCount-1)
      {
         push @readoutArray, [ "", "ctlmgr_ctl r tam settings/TAM".$_."/Display" ];
      }
   # Check if user (parent control) is not completely blocked
      for (0..$userCount-1)
      {
         push @readoutArray, ["", "ctlmgr_ctl r user settings/user".$_."/filter_profile_UID" ];
      }
   #!!! Execute commands !!!
      $resultArray = FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
      

# Prepare new command array
   #Get TAM readings
      for (0..$tamCount-1)
      {
         $rName = "tam".($_+1);
         if ($resultArray->[$_] eq "1" || defined $hash->{READINGS}{$rName} )
         {
            push @readoutArray, [ $rName, "ctlmgr_ctl r tam settings/TAM". $_ ."/Name" ];
            push @readoutArray, [ $rName."_state", "ctlmgr_ctl r tam settings/TAM".$_."/Active", "onoff" ];
            push @readoutArray, [ $rName."_newMsg", "ctlmgr_ctl r tam settings/TAM".$_."/NumNewMessages" ];
            push @readoutArray, [ $rName."_oldMsg", "ctlmgr_ctl r tam settings/TAM".$_."/NumOldMessages" ];
         }
      }

   # user profiles
      $i=0;
      $rName = "user01";
      while ($i<$userCount || defined $hash->{READINGS}{$rName})
      {
   # do not show data for unlimited, blocked or default access rights
         if ($resultArray->[$i+$tamCount] !~ /^filtprof[134]$/ || defined $hash->{READINGS}{$rName} )
         {
            push @readoutArray, [$rName, "ctlmgr_ctl r user settings/user".$i."/name", "deviceip" ];
            push @readoutArray, [$rName."_thisMonthTime", "ctlmgr_ctl r user settings/user".$i."/this_month_time", "secondsintime" ];
            push @readoutArray, [$rName."_todayTime", "ctlmgr_ctl r user settings/user".$i."/today_time", "secondsintime" ];
            push @readoutArray, [$rName."_todaySeconds", "ctlmgr_ctl r user settings/user".$i."/today_time" ];
            push @readoutArray, [$rName."_type", "ctlmgr_ctl r user settings/user".$i."/type", "usertype" ];
         }
         $i++;
         $rName = sprintf ("user%02d",$i+1);
      }

   # Diversity
      $i=0;
      $rName = "diversity1";
      while ( $i < $divCount || defined $hash->{READINGS}{$rName} )
      {
        # Diversity number
         push @readoutArray, [$rName, "ctlmgr_ctl r telcfg settings/Diversity".$i."/MSN" ];
        # Diversity state
         push @readoutArray, [$rName."_state", "ctlmgr_ctl r telcfg settings/Diversity".$i."/Active", "onoff" ];
        # Diversity destination
         push @readoutArray, [$rName."_dest", "ctlmgr_ctl r telcfg settings/Diversity".$i."/Destination"];
         $i++;
         $rName = "diversity".($i+1);
      }
      
   # !!! Execute commands !!!
      FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
   }
   
# WLAN
   push @readoutArray, [ "box_wlan_2.4GHz", "ctlmgr_ctl r wlan settings/ap_enabled", "onoff" ];
# 2nd WLAN
   push @readoutArray, [ "box_wlan_5GHz", "ctlmgr_ctl r wlan settings/ap_enabled_scnd", "onoff" ];
# Gäste WLAN
   push @readoutArray, [ "box_guestWlan", "ctlmgr_ctl r wlan settings/guest_ap_enabled", "onoff" ];
   push @readoutArray, [ "box_guestWlanRemain", "ctlmgr_ctl r wlan settings/guest_time_remain", ];
#Music on Hold
   push @readoutArray, [ "box_moh", "ctlmgr_ctl r telcfg settings/MOHType", "mohtype" ];
#Power Rate
   push @readoutArray, [ "box_powerRate", "ctlmgr_ctl r power status/rate_sumact"];

# Alarm clock
   for (0..2)
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

   FRITZBOX_Readout_Query( $hash, \@readoutArray, \@readoutReadings );
   
   
   $returnStr .= join('|', @readoutReadings );
   $returnStr .= "|readoutTime|";
   $returnStr .= sprintf "%.2f", time()-$startTime;

   FRITZBOX_Close_Connection ( $hash );

   FRITZBOX_Log $hash, 5, "Handover: ".$returnStr;
   return $returnStr

} # End FRITZBOX_Readout_Run

sub ##########################################
FRITZBOX_Readout_Done($) 
{
   my ($string) = @_;
   unless (defined $string)
   {
      Log3 "FRITZBOX_Readout_Done", 1, "Fatal Error: no parameter handed over";
      return;
   }
   
   my ($name, %values) = split("\\|", $string);
   my $hash = $defs{$name};
   
   # delete the marker for RUNNING_PID process
   delete($hash->{helper}{READOUT_RUNNING_PID});

   FRITZBOX_Log $hash, 5, "Processing ". keys(%values)." readouts.";

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
         elsif ($rName eq "box_fwVersion")
         {
            $rValue .= " (old)" if $values{box_fwUpdate} == 1;
            readingsBulkUpdate( $hash, $rName, $rValue );
         }
         elsif ($rName !~ /readoutTime|box_fwUpdate/)
         {
            readingsBulkUpdate( $hash, $rName, $rValue );
         }
      }

      my $msg = keys( %values )." values captured in ".$values{readoutTime}." s";
      readingsBulkUpdate( $hash, "lastReadout", $msg );
      FRITZBOX_Log $hash, 4, $msg;
      my $newState = "WLAN: ";
      if ( $values{"box_wlan_2.4GHz"} eq "on" ) {
         $newState .= "on";
      } elsif ( defined $values{box_wlan_5GHz} ) {
         if ( $values{box_wlan_5GHz} eq "on") {
            $newState .= "on";
         } else {
            $newState .= "off";
         }
      } else {
         $newState .= "off";
      }
      $newState .=" gWLAN: ".$values{box_guestWlan} ;
      $newState .=" (Remain: ".$values{box_guestWlanRemain}." min)"
         if $values{box_guestWlan} eq "on" && $values{box_guestWlanRemain} != 0;
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

##########################################
sub FRITZBOX_Readout_Format($$$) 
{
   my ($hash, $format, $readout) = @_;
   
   return $readout 
      unless defined $format;
   return $readout 
      unless $readout ne "" && $format ne "" ;

   if ($format eq "aldays") {
      if ($readout eq "0") {
         $readout = "once";
      } elsif ($readout eq "127") {
         $readout = "daily";
      } else {
         my $bitStr = $readout;
         $readout = "";
         foreach (sort {$a <=> $b} keys %alarmDays)
         {
            $readout .= (($bitStr & $_) == $_) ? $alarmDays{$_}." " : "";
         }
         chop $readout;
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
   
   } elsif ($format eq "altime") {
      $readout =~ s/(\d\d)(\d\d)/$1:$2/;
   
   } elsif ($format eq "deviceip") {
      $readout = $landevice{$readout}." ($readout)"
         if defined $landevice{$readout};
   
   } elsif ($format eq "model") {
      $readout = $fonModel{$readout} if defined $fonModel{$readout};
   
   } elsif ($format eq "mohtype") {
      $readout = $mohtype[$readout] if defined $mohtype[$readout];
   
   } elsif ($format eq "nounderline") {
      $readout =~ s/_/ /g;

   } elsif ($format eq "onoff") {
      $readout =~ s/0/off/;
      $readout =~ s/1/on/;
   
   } elsif ($format eq "radio") {
      $readout = $hash->{fhem}{radio}{$readout}
         if defined $hash->{fhem}{radio}{$readout};
  
   } elsif ($format eq "ringtone") {
      $readout = $ringTone{$readout};
   
   } elsif ($format eq "secondsintime") {
      if ($readout < 243600)
      {
         $readout = sprintf "%d:%02d", int $readout/3600, int( ($readout %3600) / 60);
      }
      else
      {
         $readout = sprintf "%dd %d:%02d", int $readout/24/3600, int ($readout%24*3600)/3600, int( ($readout %3600) / 60);
      }
   } elsif ($format eq "usertype") {
      $readout = $userType{$readout};
   
   }

   $readout = "" unless defined $readout;
   return $readout;
}

##########################################
sub FRITZBOX_Cmd_Start($) 
{
  my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex( $timerpara, "." );    # rechter punkt
   my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash = $defs{$name};
   
   return unless int @cmdBuffer;

 # kill old process if timeout + 10s is reached
   if ( exists( $hash->{helper}{CMD_RUNNING_PID}) && time()> $cmdBufferTimeout + 10 )
   {
      FRITZBOX_Log $hash, 1, "Old command still running. Killing old command: ".$cmdBuffer[0];
      shift @cmdBuffer;
      BlockingKill( $hash->{helper}{CMD_RUNNING_PID} ); 
      delete $hash->{helper}{CMD_RUNNING_PID};
      return unless int @cmdBuffer;
   }
   
 # (re)start timer if command buffer is still filled
   if (int @cmdBuffer >1)
   {
      RemoveInternalTimer($hash->{helper}{TimerCmd});
      InternalTimer(gettimeofday()+1, "FRITZBOX_Cmd_Start", $hash->{helper}{TimerCmd}, 1);
   }
   
# do not continue until running command has finished or is aborted
   return if exists $hash->{helper}{CMD_RUNNING_PID};

   my @val = split / /, $cmdBuffer[0];
   
   if ($val[0] eq "ring")
   {
      shift @val;
      
      my $timeout = 5;
      $timeout = $val[1]
         if $val[1] =~/^\d+$/; 
      $timeout += 60;
      $cmdBufferTimeout = time() + $timeout;

      my $handover = $name . "|" . join( "|", @val );
      $hash->{helper}{CMD_RUNNING_PID} = BlockingCall("FRITZBOX_Ring_Run", $handover,
                                          "FRITZBOX_Cmd_Done", $timeout,
                                          "FRITZBOX_Cmd_Aborted", $hash)
                                 unless exists $hash->{helper}{CMD_RUNNING_PID};
   }
} # end FRITZBOX_Cmd_Start

sub ##########################################
FRITZBOX_Ring_Run($) 
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   return "$name|0|Error: At least one parameter must be defined."
         unless int @val;

   my $result;
   my $curCallerName;
   my @cmdArray;
   my $duration = 5;
   my $intNo = $val[0];
   my @FritzFons;
   my $ringTone;
   my %field;
   my $lastField;
   my $ttsLink;
   my $fhemRadioStation = 39;

 # Check if 1st parameter are comma separated numbers
   return $name."|0|Error: Parameter '$intNo' not a number (only commas (,) are allowed to separate numbers)"
      unless $intNo =~ /^[\d,]+$/;
   
# Create a hash for the DECT devices whose ring tone (or radio station) can be changed
   foreach ( split( /,/, $intNo ) )
   {
      if ("AVM" eq $hash->{fhem}{$_}{brand})
      {
         FRITZBOX_Log $hash, 5, "Internal number $_ seems to be a Fritz!Fon.";
         push @FritzFons, $_ - 609
      }
   }
      
 # Check if 2nd parameter is the duration
   shift @val;
   if (int @val)
   {
      if ($val[0] =~ /^\d+$/ && int $val[0] > 0)
      {
         $duration = $val[0];
         FRITZBOX_Log $hash, 5, "Extracted ring duration of $duration s.";
         shift @val;
      }
   }
   
 # Check if next parameter is a valid ring tone
   if (int @val)
   {
      if ($val[0] !~ /^(msg|show|say):/i)
      {
         $ringTone = $val[0];
         $ringTone = $ringToneNumber{lc $val[0]};
         return $name."|0|Error: Ring tone '".$val[0]."' not valid"
            unless defined $ringTone;
         shift @val;
      }
   }

# Extract text to say or show
   foreach (@val)
    {
      if ($_ =~ /^(show|msg|say):/i)
      {
         $lastField = $1;
         $_ =~ s/^$1://;
      }
      $field{$lastField} .= $_." "
         if $lastField;
    }

   my $msg = AttrVal( $name, "defaultCallerName", "FHEM" );
   if ( $field{show} ) {
      chop $field{show};
      $msg = $field{show};
   } elsif ( $field{msg} ) {
      chop $field{msg};
      $msg = $field{msg};
   }
   $msg = substr($msg, 0, 30);
   
   if ( $field{say} ) {
      $ringTone = 33;
      chop $field{say};
      # http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT];
      $ttsLink = $ttsLinkTemplate;
      my $ttsText = $field{say};
      my $ttsLang = "de";
      if ($ttsText =~ /^\((en|es|fr|nl)\)/i )
      {
         $ttsLang = $1;
         $ttsText =~ s/^\($1\)\s*//i;
      }
      $ttsLink =~ s/\[SPRACHE\]/$ttsLang/;
      $ttsText = substr($ttsText,0,70);
      $ttsText = uri_escape($ttsText);
      $ttsLink =~ s/\[TEXT\]/$ttsText/;
      FRITZBOX_Log $hash, 5, "Created Text2Speech internet link: $ttsLink";
   }

   $result = FRITZBOX_Open_Connection( $hash );
   return "$name|0|$result" 
      if $result;

#Preparing 1st command array
   @cmdArray = ();
   
# Creation fhemRadioStation for ttsLink
   if (int (@FritzFons) && $ttsLink && $hash->{fhem}{radio}{$fhemRadioStation} ne "fhemTTS")
   {
      FRITZBOX_Log $hash, 3, "Create new internet radio station $fhemRadioStation: 'fhemTTS' for ringing with text-to-speech";
      push @cmdArray, "ctlmgr_ctl w configd settings/WEBRADIO39/Name fhemTTS";
      push @cmdArray, "ctlmgr_ctl w configd settings/WEBRADIO39/Bitmap 1023";
   #Execute command array
      FRITZBOX_Exec( $hash, \@cmdArray )
   }
   
# Change ring tone of Fritz!Fons
   foreach (@FritzFons)
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User$_/IntRingTone";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User$_/IntRingTone $ringTone";
      FRITZBOX_Log $hash, 4, "Change temporarily internal ring tone of Fritz!Fon DECT $_ to $ringTone";
      if ($ttsLink)
      {
         push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User$_/RadioRingID";
         push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User$_/RadioRingID ".$fhemRadioStation;
         FRITZBOX_Log $hash, 4, "Change radio station of Fritz!Fon DECT $_ to $fhemRadioStation (fhemTTS)";
      }
   }

# uses name of port 0-3 (dial port 1-4) to show messages on ringing phone
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 0 );
   if ($ringWithIntern =~ /^([1-3])$/ )
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/MSN/Port".($ringWithIntern-1)."/Name";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$msg'";
      FRITZBOX_Log $hash, 4, "Change temporarily name of calling number $ringWithIntern to '$msg'";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort $ringWithIntern"
   }
   
# Set tts-Message
   push @cmdArray, 'ctlmgr_ctl w configd settings/WEBRADIO'.$fhemRadioStation.'/URL "'.$ttsLink.'"'
      if $ttsLink;

#Execute command array
   $result = FRITZBOX_Exec( $hash, \@cmdArray )
      if int( @cmdArray ) > 0;

   $intNo =~ s/,/#/g;
   
#Preparing 2nd command array to ring and reset everything
   FRITZBOX_Log $hash, 4, "Ringing $intNo for $duration seconds";
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo;
   push @cmdArray, "sleep ".($duration+2); # 2s added because it takes sometime until it starts ringing
   push @cmdArray, "ctlmgr_ctl w telcfg command/Hangup **".$intNo;
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort 50"
      if $ringWithIntern != 0 ;
# Reset internal ring tones for the Fritz!Fons
   foreach (keys @FritzFons)
   {
      push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$FritzFons[$_]."/IntRingTone ".$result->[2*$_];
   # Reset internet station for the Fritz!Fons
      if ($ttsLink)
      {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$FritzFons[$_]."/RadioRingID ".$result->[2*(int(@FritzFons)+$_)];
      }
   }
   
# Reset name of calling number
   if ($ringWithIntern =~ /^([1-2])$/)
   {
      if ($ttsLink) {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[4*int(@FritzFons)]."'"
      } else {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[2*int(@FritzFons)]."'"
      }
   }
   
# Execute command array
   FRITZBOX_Exec( $hash, \@cmdArray );

   FRITZBOX_Close_Connection( $hash );

   return $name."|1|Ringing done";
}

sub ##########################################
FRITZBOX_Cmd_Done($) 
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, $success, $result) = split("\\|", $string);
   my $hash = $defs{$name};
   
   shift (@cmdBuffer);
   delete($hash->{helper}{CMD_RUNNING_PID});

   if ($success != 1)
   {
      FRITZBOX_Log $hash, 1, $result;
   }
   else
   {
      FRITZBOX_Log $hash, 4, $result;
   }
}

##########################################
sub FRITZBOX_Cmd_Aborted($) 
{
  my ($hash) = @_;
  my $lastCmd = shift (@cmdBuffer);
  delete($hash->{helper}{CMD_RUNNING_PID});
  FRITZBOX_Log $hash, 1, "Timeout reached for: $lastCmd";
}

############################################
sub FRITZBOX_SetMOH($@)
{  
   my ($hash, $type, @file) = @_;
   my $returnStr;
   my @cmdArray;
   my $result;
   my $name = $hash->{NAME};
   my $uploadFile = '/var/tmp/fhem_moh_upload';
   my $mohFile = '/var/tmp/fhem_fx_moh';

   if (lc $type eq lc $mohtype[0] || $type eq "0")
   {
      FRITZBOX_Exec ($hash, 'ctlmgr_ctl w telcfg settings/MOHType 0');
      return 0;
   }
   elsif (lc $type eq lc $mohtype[1] || $type eq "1")
   {
      FRITZBOX_Exec ($hash, 'ctlmgr_ctl w telcfg settings/MOHType 1');
      return 1;
   }
   return "Error: Unvalid parameter '$type'" unless lc $type eq lc $mohtype[2] || $type eq "2";

# Load customer MOH file

   my $inFile = join " ", @file;
   my $uploadDir = AttrVal( $name, "defaultUploadDir",  "" );
   $uploadDir .= "/"
      unless $uploadDir =~ /\/$|^$/;

   if ($inFile !~ /^say:/i)
   {
      $inFile = $uploadDir.$inFile
         unless $inFile =~ /^\//;
      return "Error: Please give a complete file path or define the attribute 'defaultUploadDir'"
         unless $inFile =~ /^\//;
      return "Error: Only MP3 files can be used for 'music on hold'."
         unless $inFile =~ /\.mp3$/i;
   }

   $result = FRITZBOX_Open_Connection( $hash );
   return "$name|0|$result" 
      if $result;

   push @cmdArray, '[ -f "'.$uploadFile.'" ] && rm "'.$uploadFile.'"';
   push @cmdArray, '[ -f "'.$mohFile.'" ] && rm "'.$mohFile.'"';
   
   if ($inFile =~ /^say:/i)
   {
      FRITZBOX_Log $hash, 4, "Converting Text2Speech";
      # 'wget -U Mozilla -O "[ZIEL]" "http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT]"';
      my $ttsCmd = $ttsCmdTemplate;
      $ttsCmd =~ s/\[ZIEL\]/$uploadFile/;
      my $ttsText = $inFile;
      $ttsText =~ s/^say:\s*//i;
      my $ttsLang = "de";
      if ($ttsText =~ /^\((en|es|fr|nl)\)/i )
      {
         $ttsLang = $1;
         $ttsText =~ s/^\($1\)\s*//i;
      }
      $ttsCmd =~ s/\[SPRACHE\]/$ttsLang/;
      # $ttsText = ($ttsText." ") x int(60/length($ttsText))
         # if length($ttsText) < 30;
      $ttsText = substr($ttsText,0,70);
      $ttsText = uri_escape($ttsText);
      $ttsCmd =~ s/\[TEXT\]/$ttsText/;
      push @cmdArray, $ttsCmd;
   } 
   elsif ($inFile =~ /^(ftp|http):\/\//)
   {
      push @cmdArray, 'wget -O "'.$uploadFile.'" "'.$inFile.'"';
   } else {
      push @cmdArray, 'cp "'.$inFile.'" "'.$uploadFile.'"';
   }
   push @cmdArray, '[ -f "'.$uploadFile.'" ] && echo 1 || echo 0';
# Execute command array
   $result = FRITZBOX_Exec ( $hash, \@cmdArray );
   return "Could not access '$inFile'"
      unless $result->[3] eq "1";

#Prepare 2nd command array
   push @cmdArray, 'ffmpegconv -i "'.$uploadFile.'" -o "'.$mohFile.'" --limit 32 --type 7';
   push @cmdArray, '[ -f "'.$mohFile.'" ] && echo 1 || echo 0';
# Execute 2nd command array
   $result = FRITZBOX_Exec ( $hash, \@cmdArray );
   return "Could not convert '$inFile'"
      unless $result->[1] eq "1";

#Prepare 3rd command array
   push @cmdArray, 'cat "'.$mohFile.'" >/var/flash/fx_moh';
   push @cmdArray, 'killall -sigusr1 telefon';
   push @cmdArray, 'rm "'.$uploadFile.'"';
   push @cmdArray, 'rm "'.$mohFile.'"';
# Execute 3rd command array
   $result = FRITZBOX_Exec ( $hash, \@cmdArray );

   FRITZBOX_Close_Connection( $hash );
   return 2;
}

############################################
sub FRITZBOX_SetCustomerRingTone($@)
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

############################################
sub FRITZBOX_ConvertMOH ($@)
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
      , 'ffmpegconv -i "'.$inFile.'" -o "'.$outFile.'.moh" --limit 32 --type 6');
   return $returnStr;
} # end FRITZBOX_ConvertMOH

############################################
sub FRITZBOX_ConvertRingTone ($@)
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
} # end FRITZBOX_ConvertRingTone

#'picconv.sh "'.$inFile.'" "'.$outFile.'.g722" ringtonemp3'
#picconv.sh "file://$dir/upload.mp3" "$dir/$filename" ringtonemp3   
#"ffmpegconv  -i '$inFile' -o '$outFile.g722' --limit 240");
#ffmpegconv -i "${in}" -o "${out}" --limit 240
#pbd --set-image-url --book=255 --id=612 --url=/var/InternerSpeicher/FRITZ/fonring/1416431162.g722 --type=1
#pbd --set-image-url --book=255 --id=612 --url=file://var/InternerSpeicher/FRITZBOXtest.g722 --type=1
#ctlmgr_ctl r user settings/user0/bpjm_filter_enable
#/usr/bin/pbd --set-ringtone-url --book="255" --id="612" --url="file:///var/InternerSpeicher/claydermann.g722" --name="Claydermann"
# /usr/bin/moh_upload

# Opens a Telnet Connection to an external FritzBox
############################################
sub FRITZBOX_Open_Connection($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   return undef 
      unless $hash->{REMOTE} == 1;
   
   return "Error: Perl modul ".$missingModulRemote."is missing on this system. Please install before using this modul."
      if $missingModulRemote;
      
   my $host = AttrVal( $name, "fritzBoxIP", "fritz.box" );

   my $pwdFile = AttrVal( $name, "pwdFile", "fb_pwd.txt");
   my $pwd;
   my $msg;
   my $before;
   my $match;
   
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
   my $timeout = AttrVal( $name, "telnetTimeOut", "10");
   $telnet = new Net::Telnet ( Host=>$host, Port => 23, Timeout=>$timeout, Errmode=>'return', Prompt=>'/# $/');
   if (!$telnet) {
      $msg = "Could not open telnet connection to $host";
      FRITZBOX_Log $hash, 2, $msg;
      $telnet = undef;
      return $msg;
   }

   FRITZBOX_Log $hash, 5, "Wait for user or password prompt.";
   unless ( ($before,$match) = $telnet->waitfor('/(user|login|password): $/i') )
   {
      $msg = "Telnet error while waiting for user or password prompt: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   if ( $match =~ /(user|login): / && $user eq "")
   {
      $msg = "Telnet login requires user name but attribute 'telnetUser' not defined";
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   elsif ( $match =~ /(user|login): /)
   {
      FRITZBOX_Log $hash, 5, "Entering user name";
      $telnet->print( $user );

      FRITZBOX_Log $hash, 5, "Wait for password prompt";
      unless ($telnet->waitfor( '/password: $/i' ))
      {
         $msg = "Telnet error while waiting for password prompt: ".$telnet->errmsg;
         FRITZBOX_Log $hash, 2, $msg;
         $telnet->close;
         $telnet = undef;
         return $msg;
      }
   }
   elsif ( $match eq "password: " && $user ne "")
   {
      FRITZBOX_Log $hash, 3, "Attribute 'telnetUser' defined but telnet login did not prompt for user name.";
   }

   FRITZBOX_Log $hash, 5, "Entering password";
   $telnet->print( $pwd );

   FRITZBOX_Log $hash, 5, "Wait for command prompt";
   unless ( ($before,$match) = $telnet->waitfor( '/# $|Login failed./i' ))
   {
      $msg = "Telnet error while waiting for command prompt: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   elsif ( $match eq "Login failed.")
   {
      $msg = "Telnet error: Login failed. Wrong password.";
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }

   return undef;
} # end FRITZBOX_Open_Connection

   
# Closes a Telnet Connection to an external FritzBox
############################################
sub FRITZBOX_Close_Connection($)
{
   my ($hash) = @_;
   
   return undef 
      unless $hash->{REMOTE} == 1;

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
} # end FRITZBOX_Close_Connection
   
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
            if (FRITZBOX_Open_Connection($hash));
         $openedTelnet = 1;
      }
      my $retVal = FRITZBOX_Exec_Remote($hash, $cmd);
      FRITZBOX_Close_Connection ( $hash ) if $openedTelnet;
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
      my $log = join " ", @output;
      chomp $log;
      FRITZBOX_Log $hash, 4, "Result '$log'";
      return $result;
   }
   elsif (ref \$cmd eq "REF")
   {
      my @resultArray = ();
      if ( int (@{$cmd}) > 0 )
      {
         FRITZBOX_Log $hash, 4, "Execute " . int ( @{$cmd} ) . " command(s)";
  
         foreach (@{$cmd})
         {
            FRITZBOX_Log $hash, 5, "Execute '".$_."'";
            unless ($_ =~ /^sleep/)
            {
               @output=$telnet->cmd($_);
               $result = $output[0];
               chomp $result;
               my $log = join " ", @output;
               chomp $log;
               FRITZBOX_Log $hash, 4, "Result '$log'";
            }
            else
            {
               FRITZBOX_Log $hash, 4, "Do '$_' in perl.";
               eval ($_);
               $result = "";
            }
            push @resultArray, $result;
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
sub FRITZBOX_SendMail($@)
{
   my ($hash,@val) = @_;
   my $lastField;
   my %field;
   my @cmdArray;
   
   foreach (@val)
   {
      if ($_ =~ /^(to|subject|body):/i)
      {
         $lastField = $1;
         $_ =~ s/^$1://;
      }
      $field{$lastField} .= $_." "
         if $lastField;
   }

   my $cmd = "/sbin/mailer send";
   if ($field{body})
   {
      chop $field{body};
      $field{body} =~ s/"/\\"/g;
      push @cmdArray, '/bin/echo -e "'.$field{body}.'" >/var/tmp/fhem_nachricht.txt';
      $cmd .=  " -i '/var/tmp/fhem_nachricht.txt'";
   }

   chop $field{subject} if $field{subject};
   $field{subject} = "Message from FHEM " unless $field{subject};
   $cmd .= " -s \"".$field{subject}."\"";
   
   if ($field{to})
   {
      chop $field{to};
      $cmd .= " -t \"".$field{to}."\""
   }
   push @cmdArray, $cmd;
   push @cmdArray, "rm /var/tmp/fhem_nachricht.txt"
      if $field{body};

   FRITZBOX_Exec( $hash, \@cmdArray );
   
   return undef;
}

sub ##########################################
FRITZBOX_StartRadio($@) 
{
   my ($hash, @val) = @_;
   my @cmdArray;
   my $name = $hash->{NAME};
   my $intNo = $val[0];
   my $radioStation;
   my $radioStationName;
   my $result;
   
# Check if 1st parameter is a number
   return "Error: 1st Parameter '$intNo' not an internal DECT number"
      unless $intNo =~ /^61[012345]$/;

# Check if the 1st parameter is a Fritz!Fon
   return "Error: Internal number $intNo does not seem to be a Fritz!Fon."
      unless $hash->{fhem}{$intNo}{brand} eq "AVM";

# Check if remaining parameter is an internet Radio Station
   shift (@val);
   if (@val)
   {
      $radioStationName = join (" ", @val);
      if ($radioStationName =~ /^\d+$/)
      {
         $radioStation = $radioStationName;
         $radioStationName = $hash->{fhem}{radio}{$radioStation};
         return "Error: Unknown internet radio number $radioStation."
            unless defined $radioStationName;
      }
      else
      {
         foreach (keys %{$hash->{fhem}{radio}})
         {
            if (lc $hash->{fhem}{radio}{$_} eq lc $radioStationName)
            {
               $radioStation = $_;
               last;
            }
         }
         return "Error: Unknown internet radio station '$radioStationName'"
            unless defined $radioStation;
         
      }
   }

   $result = FRITZBOX_Open_Connection( $hash );
   return $result if $result;

# Get current ringtone
   my $userNo = $intNo-609;
   my $curRingTone = FRITZBOX_Exec( $hash, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$userNo."/IntRingTone" );

# Start Internet Radio and reset ring tone
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/IntRingTone 33";
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/RadioRingID $radioStation";
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo;
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/IntRingTone $curRingTone";

# Execute command array
   FRITZBOX_Exec( $hash, \@cmdArray );

   FRITZBOX_Close_Connection( $hash );

   return undef;
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
#   $returnStr .= '<link rel="stylesheet" type="text/css" href="http://fritz.box/css/default/main.css"/>';
   $returnStr .= '<link rel="stylesheet" type="text/css" href="http://fritz.box/css/default/static.css"/>';
   $returnStr .= '<!--[if lte IE 8]>';
   $returnStr .= '<link rel="stylesheet" type="text/css" href="http://fritz.box/css/default/ie_fix.css"/>';
   $returnStr .= '<![endif]-->';
   $returnStr .= '<style>#game table td {width: 10px;height: 10px;}</style>';
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
   $returnStr .= '<td><div id="page_content" class="page_content">';
   $returnStr .= '<div id="game" style="background:white;"></div></div></td></tr></table>';

   return $returnStr;
}
##################################### 

1;

=pod
=begin html

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
(en | <a href="commandref_DE.html#FRITZBOX">de</a>)
<div  style="width:800px"> 
<ul>
   Controls some features of a Fritz!Box router. Connected Fritz!Fon's (MT-F, MT-D, C3, C4) can be used as
   signaling devices. MP3 files and Text2Speech can be played as ring tone or when calling phones.
   <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki-Link</b></a>
   <br/><br/>
   The modul switches in local mode if FHEM runs on a Fritz!Box (as root user!). Otherwise, it tries to open a telnet connection to "fritz.box", so telnet (#96*7*) has to be enabled on the Fritz!Box. For remote access the password must be stored in the file 'fb_pwd.txt' in the root directory of FHEM.
   <br/><br/>
   The commands are directly executed on the Fritz!Box shell. That means, no official API is used but mainly the internal interface program that links web interface and firmware. An update of FritzOS might hence lead to modul errors if AVM changes the interface.
   <br>
   Check also the other Fritz!Box moduls: <a href="#SYSMON">SYSMON</a> and <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
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
      The FritzOS has a hidden function (easter egg).
      <br>
      <code>define MyEasterEgg weblink htmlCode { FRITZBOX_fritztris("Fritzbox") }</code>
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

      <li><code>set &lt;name&gt; convertRingTone &lt;fullFilePath&gt;</code>
         <br>
         Converts the mp3-file fullFilePath to the G722 format and puts it in the same path.
         <br>
         The file has to be placed on the file system of the Fritz!Box.
      </li><br>
      
      <li><code>set &lt;name&gt; convertMusicOnHold &lt;fullFilePath&gt;</code>
         <br>
         <i>Not implemented yet.</i> Converts the mp3-file fullFilePath to a format that can be used for "Music on Hold".
         <br>
         The file has to be placed on the file system of the fritzbox.
      </li><br>

      <li><code>set &lt;name&gt; createPwdFile &lt;password&gt;</code>
         <br>
         Creates a file that contains the telnet password. The file name corresponds to the one used for remote telnet access.
      </li><br>

      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;fullFilePath&gt;</code>
         <br>
         Uploads the file fullFilePath on the given handset. Only mp3 or G722 format is allowed.
         <br>
         The file has to be placed on the file system of the fritzbox.
         <br>
         The upload takes about one minute before the tone is available.
      </li><br>

      <li><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Switches the call diversity number (1, 2 ...) on or off.
         A call diversity for an incoming number has to be created with the Fritz!Box web interface.
         <br>
         Note! The Fritz!Box allows also forwarding in accordance to the calling number. This is not included in this feature. 
      </li><br>

      <li><code>set &lt;name&gt; guestWLAN &lt;on|off&gt;</code>
         <br>
         Switches the guest WLAN on or off.
      </li><br>

      <li><code>set &lt;name&gt; moh &lt;default|sound|customer&gt; [&lt;MP3FileIncludingPath|say:Text&gt;]</code>
         <br>
         Example: <code>set fritzbox moh customer say:Die Wanne ist voll</code>
         <br>
         <code>set fritzbox moh customer /var/InternerSpeicher/warnung.mp3</code>
         <br>
         Changes the 'music on hold' of the Box. The parameter 'customer' allows to upload a mp3 file. Alternatively a text can be spoken with "say:". The music on hold has a maximal length of 8 s. It is played during the broking of calls or if the modul rings a phone and the call is taken. So, it can be used to transmit little messages of 8 s.
         <br>
      </li><br>

      <li><code>set &lt;name&gt; ring &lt;internalNumbers&gt; [duration [ringTone]] [show:Text] [say:Text]</code>
         <br>
         Example:
         <br>
         <code>set fritzbox ring 611,612 5 Budapest show:It is raining</code>
         <br>
         <code>set fritzbox ring 611 say:(en)It is raining</code>
         <br>
         Rings the internal numbers for "duration" seconds and (on Fritz!Fons) with the given "ring tone" name.
         Different internal numbers have to be separated by a comma (without spaces).
         <br>
         Default duration is 5 seconds. Default ring tone is the internal ring tone of the device.
         Ring tone will be ignored for collected calls (9 or 50). 
         <br>
         If the <a href=#FRITZBOXattr>attribute</a> 'ringWithIntern' is specified, the text behind 'show:' will be shown as the callers name.
         Maximal 30 characters are allowed.
         <br>
         On Fritz!Fons the parameter 'say:' can be used to let the phone speak a message (and continue with the default ring tone of the handset). This feature creates a radio station 'fhemTTS' and uses the translate.google.com.
         <br>
         If the call is taken the callee hears the "music on hold" which can also be used to transmit messages.
      </li><br>

      <li><code>set &lt;name&gt; sendMail [to:&lt;Address&gt;] [subject:&lt;Subject&gt;] [body:&lt;Text&gt;]</code>
         <br>
         Sends an email via the email notification service that is configured in push service of the Fritz!Box. 
         Use "\n" for line breaks in the body.
         All parameters can be omitted. Make sure the messages are not classified as junk by your email client.
         <br>
      </li><br>

      <li><code>set &lt;name&gt; startRadio &lt;internalNumber&gt; [name or number]</code>
         <br>
         Plays the internet radio on the given Fritz!Fon. Default is the current station of the phone. 
         An available internet radio can be selected by its name or (reading) number.
         <br>
      </li><br>

      <li><code>set &lt;name&gt; tam &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Switches the answering machine number (1, 2 ...) on or off.
         The answering machine has to be created on the Fritz!Box web interface.
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
         Shows the list of ring tones that can be used.
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

      <li><code>pwdFile &lt;fileName&gt;</code>
         <br>
         File that contains the password for telnet access. Default is 'fb_pwd.txt' in the root directory of FHEM.
      </li><br>

      <li><code>telnetUser &lt;user name&gt;</code>
         <br>
         User name that is used for telnet access. By default no user name is required to login.
         <br>
         If the Fritz!Box is configured differently, the user name has to be defined with this attribute.
      </li><br>

      <li><code>ringWithIntern &lt;1 | 2 | 3&gt;</code>
         <br>
         To ring a fon a caller must always be specified. Default of this modul is 50 "ISDN:W&auml;hlhilfe".
         <br>
         To show a message (default: "FHEM") during a ring the internal phone numbers 1-3 can be specified here.
         The concerned analog phone socket must exist.
      </li><br>
      
      <li><code>telnetTimeOut &lt;seconds&gt;</code>
         <br>
         Maximal time to wait for an answer during a telnet session. Default is 10 s.
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
      <li><b>box_guestWlanRemain</b> - Remaining time until the guest WLAN is switched off</li>
      <li><b>box_model</b> - Fritz!Box model</li>
      <li><b>box_moh</b> - music-on-hold setting</li>
      <li><b>box_tr069</b> - provider remote access TR069 (safety issue!)</li>
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
      <li><b>dect</b><i>1</i><b>_radio</b> - Current internet radio station of the DECT device <i>1</i></li>

      <li><b>fon</b><i>1</i> - Internal name of the analog FON connection <i>1</i></li>
      <li><b>fon</b><i>1</i><b>_intern</b> - Internal number of the analog FON connection <i>1</i></li>

      <li><b>diversity</b><i>1</i> - Own (incoming) phone number of the call diversity <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_dest</b> - Destination of the call diversity <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_state</b> - Current state of the call diversity <i>1</i></li>

      <li><b>radio</b><i>01</i> - Name of the internet radio station <i>01</i></li>

      <li><b>tam</b><i>1</i> - Name of the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_newMsg</b> - New messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_oldMsg</b> - Old messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_state</b> - Current state of the answering machine <i>1</i></li>

      <li><b>user</b><i>01</i> - Name of user/IP <i>1</i> that is under parental control</li>
      <li><b>user</b><i>01</i>_thisMonthTime - this month internet usage of user/IP <i>1</i> (parental control)</li>
      <li><b>user</b><i>01</i>_todaySeconds - today's internet usage in seconds of user/IP <i>1</i> (parental control)</li>
      <li><b>user</b><i>01</i>_todayTime - today's internet usage of user/IP <i>1</i> (parental control)</li>
   </ul>
   <br>
</ul>
</div>

=end html

=begin html_DE

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
(<a href="commandref.html#FRITZBOX">en</a> | de)
<div  style="width:800px"> 
<ul>
   Steuert gewisse Funktionen eines Fritz!Box Routers. Verbundene Fritz!Fon's (MT-F, MT-D, C3, C4) k&ouml;nnen als Signalger&auml;te genutzt werden. MP3-Dateien und Text (Text2Speech) k&ouml;nnen als Klingelton oder einem angerufenen Telefon abgespielt werden.
   <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki-Link</b></a>
   <br/><br/>
   Das Modul schaltet in den lokalen Modus, wenn FHEM auf einer Fritz!Box l&auml;uft (als root-Benutzer!). Ansonsten versucht es eine Telnet Verbindung zu "fritz.box" zu &ouml;ffnen. D.h. Telnet (#96*7*) muss auf der Fritz!Box erlaubt sein. F&uuml;r diesen Fernzugriff muss das Passwort in der Datei 'fb_pwd.txt' im Wurzelverzeichnis von FHEM gespeichert sein.
   <br/><br/>
   Die Steuerung erfolgt direkt &uuml;ber die Fritz!Box Shell. D.h. es wird keine offizielle API genutzt sondern vor allem die interne Schnittstelle der Box zwischen Webinterface und Firmware. Eine Aktualisierung des FritzOS kann also zu Modul-Fehlern f&uuml;hren, wenn AVM diese Schnittstelle &auml;ndert.
   <br>
   Bitte auch die anderen Fritz!Box-Module beachten: <a href="#SYSMON">SYSMON</a> und <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>Das Modul nutzt das Perlmodule 'Net::Telnet' f&uuml;r den Fernzugriff.</i>
   <br/><br/>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX</code>
      <br/><br/>
      Beispiel: <code>define Fritzbox FRITZBOX</code>
      <br/><br/>
      Das FritzOS hat eine versteckte Funktion (Osterei).
      <br>
      <code>define MyEasterEgg weblink htmlCode { FRITZBOX_fritztris("Fritzbox") }</code>
      <br/><br/>
   </ul>
  
   <a name="FRITZBOXset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; alarm &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Schaltet den Weckruf Nummer 1, 2 oder 3 an oder aus.
      </li><br>

      <li><code>set &lt;name&gt; convertRingTone &lt;fullFilePath&gt;</code>
         <br>
         Konvertiert die  mp3-Datei fullFilePath in das G722-Format und legt es im selben Pfad ab.
         <br>
         Die Datei muss im Dateisystem der Fritz!Box liegen.
      </li><br>
      
      <li><code>set &lt;name&gt; convertMusicOnHold &lt;fullFilePath&gt;</code>
         <br>
         <i>Not implemented yet.</i> Converts the mp3-file fullFilePath to a format that can be used for "Music on Hold".
         <br>
         The file has to be placed on the file system of the fritzbox.
      </li><br>

      <li><code>set &lt;name&gt; createPwdFile &lt;password&gt;</code>
         <br>
         Erzeugt eine Datei welche das Telnet-Passwort enth&auml;lt. Der Dateiname entspricht demjenigen, der f&uuml;r den Telnetzugriff genutzt wird.
      </li><br>

      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;MP3DateiInklusivePfad&gt;</code>
         <br>
         L&auml;dt die MP3-Datei als Klingelton auf das angegebene Telefon. Die Datei muss im Dateisystem der Fritzbox liegen.
         <br>
         Das Hochladen dauert etwa eine Minute bis der Klingelton verf&uuml,gbar ist.
      </li><br>

      <li><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Schaltet die Rufumleitung (Nummer 1, 2 ...) an oder aus.
         Die Rufumleitung muss zuvor auf der Fritz!Box eingerichtet werden.
         <br>
         Achtung! Die Fritz!Box erm&ouml;glicht auch eine Weiterleitung in Abh&auml;ngigkeit von der anrufenden Nummer. Diese Art der Weiterleitung kann hiermit nicht geschaltet werden. 
      </li><br>

      <li><code>set &lt;name&gt; guestWLAN &lt;on|off&gt;</code>
         <br>
         Schaltet das G&auml;ste-WLAN an oder aus.
      </li><br>

      <li><code>set &lt;name&gt; moh &lt;default|sound|customer&gt; [&lt;MP3DateiInklusivePfad|say:Text&gt;]</code>
         <br>
         Beispiel: <code>set fritzbox moh customer say:Die Wanne ist voll</code>
         <br>
         <code>set fritzbox moh customer /var/InternerSpeicher/warnung.mp3</code>
         <br>
         &Auml;ndert die Wartemusik ('music on hold') der Box. Mit dem Parameter 'customer' kann eine eigene MP3-Datei aufgespielt werden.
         Alternativ kann mit "say:" auch ein Text gesprochen werden. Die Wartemusik hat eine maximale L&auml;nge von 8,13 s. Sie wird w&auml;hrend des Makelns von Gespr&auml;chen aber auch bei Nutzung der internen W&auml;hlhilfe bis zum Abheben des rufenden Telefons abgespielt. Dadurch k&ouml;nnen &uuml;ber FHEM dem Angerufenen 8s-Nachrichten vorgespielt werden.
         <br>
      </li><br>
      
      <li><code>set &lt;name&gt; ring &lt;interneNummern&gt; [Dauer [Klingelton]] [show:Nachricht]</code>
         Beispiel: <code>set fritzbox ring 611,612 5 Budapest show:Es regnet</code>
         <br>
         L&auml;sst die internen Nummern f&uuml;r "Dauer" Sekunden und (auf Fritz!Fons) mit dem angegebenen "Klingelton" klingeln.
         Mehrere interne Nummern m&uuml;ssen durch ein Komma (ohne Leerzeichen) getrennt werden.
         <br>
         Standard-Dauer ist 5 Sekunden. Standard-Klingelton ist der interne Klingelton des Ger&auml;tes.
         Der Klingelton wird f&uuml;r Rundrufe (9 oder 50) ignoriert. 
         <br>
         Wenn das <a href=#FRITZBOXattr>Attribut</a> 'ringWithIntern' existiert, wird der Text hinter 'show:' als Name des Anrufers angezeigt.
         Er darf maximal 30 Zeichen lang sein.
         <br>
         Auf Fritz!Fons wird der Text hinter dem Parameter 'say:' direkt angesagt (gefolgt vom dem Standard Klingelton). Dieses Feature erzeugt eine Radiostation 'fhemTTS' und nutzt translate.google.com.
         <br>
         Wenn der Anruf angenommen wird, h&ouml;rt der Angerufene die Wartemusik (music on hold), welche zur Nachrichten&uuml;bermittlung genutzt werden kann.
      </li><br>

      <li><code>set &lt;name&gt; sendMail [to:&lt;Address&gt;] [subject:&lt;Subject&gt;] [body:&lt;Text&gt;]</code>
         <br>
         Sendet eine Email &uuml;ber den Emailbenachrichtigungsservice der als Push Service auf der Fritz!Box konfiguriert wurde.
         Mit "\n" kann einen Zeilenumbruch im Textkörper erzeut werden.
         Alle Parameter k&ouml;nnen ausgelassen werden. Bitte kontrolliert, dass die Email nicht im Junk-Verzeichnis landet.
         <br>
      </li><br>
      
      <li><code>set &lt;name&gt; startRadio &lt;internalNumber&gt; [Name oder Nummer]</code>
         <br>
         Startet das Internetradio auf dem angegebenen Fritz!Fon. Ein verf&uuml;gbare Radiostation kann &uuml;ber den Namen oder die (Ger&auml;tewert)Nummer ausgew&auml;hlt werden. Ansonsten wird die aktuell eingestellte genommen.
         <br>
      </li><br>
      
      <li><code>set &lt;name&gt; tam &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Schaltet den Anrufbeantworter (Nummer 1, 2 ...) an oder aus.
         Der Anrufbeantworter muss zuvor auf der Fritz!Box eingerichtet werden.
      </li><br>
      
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet eine Aktualisierung der Ger&auml;tewerte.
      </li><br>
      
      <li><code>set &lt;name&gt; wlan &lt;on|off&gt;</code>
         <br>
         Schaltet WLAN an oder aus.
      </li><br>
   </ul>  

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; ringTones</code>
         <br>
         Zeigt die Liste der Klingelt&ouml;ne, die benutzt werden k&ouml;nnen.
      </li><br>
   </ul>  
  
   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>defaultCallerName</code>
         <br>
         Standard-Text, der auf dem angerufenen internen Telefon als "Anrufer" gezeigt wird.
         <br>
         Dies erfolgt, indem w&auml;hrend des Klingelns kurzzeitig der Name der internen anrufenden Nummer ge&auml;ndert wird.
         <br>
         Es ist maximal 30 Zeichen erlaubt. Das Attribute "ringWithIntern" muss ebenfalls spezifiziert sein.
      </li><br>
      <li><code>defaultUploadDir &lt;fritzBoxPath&gt;</code>
         <br>
         Dies ist der Standard-Pfad der f&uuml;r Dateinamen benutzt wird, die nicht mit einem / (Schr&auml;gstrich) beginnen.
         <br>
         Es muss ein Pfad auf der Fritz!Box sein. D.h., er sollte mit /var/InternerSpeicher starten, wenn es in Windows unter \\ip-address\fritz.nas erreichbar ist.
      </li><br>
      <li><code>fritzBoxIP</code>
         <br>
         IP Adresse oder ULR der Fritz!Box f&uuml;r Fernzugriff per Telnet. Standard ist "fritz.box".
      </li><br>
      <li><code>pwdFile &lt;fileName&gt;</code>
         <br>
         Damit kann die Datei ge&uuml;ndert werden, welche das Passwort f&uuml;r den Telnetzugang enth&auml;lt. Der Standard ist 'fb_pwd.txt' im Wurzelverzeichnis von FHEM.
      </li><br>
     
      <li><code>telnetUser &lt;user name&gt;</code>
         <br>
         Benutzername f&uuml;r den Telnetzugang. Normalerweise wird keine Benutzername f&uuml;r das Login ben&ouml;tigt.
         Wenn die Fritz!Box anders konfiguriert ist, kann der Nutzer &uuml;ber dieses Attribut definiert werden.
      </li><br>
    
      <li><code>ringWithIntern &lt;1 | 2 | 3&gt;</code>
         <br>
         Um ein Telefon klingeln zu lassen, muss eine Anrufer spezifiziert werden. Normalerweise ist dies die Nummer 50 "ISDN:W&auml;hlhilfe".
         <br>
         Um w&auml;hrend des Klingelns eine Nachricht (Standard: "FHEM") anzuzeigen, kann hier die interne Nummer 1-3 angegeben werden.
         Der entsprechende analoge Telefonanschluss muss vorhanden sein.
      </li><br>

      <li><code>telnetTimeOut &lt;Sekunden&gt;</code>
         <br>
         Maximale Zeit, bis zu der w&auml;hrend einer Telnet-Sitzung auf Antwort gewartet wird. Standard ist 10 s.
      </li><br>

      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="FRITZBOXreading"></a>
   <b>Readings</b>
   <ul><br>
      <li><b>alarm</b><i>1</i> - Name des Weckrufs <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_state</b> - Aktueller Status des Weckrufs <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_target</b> - Interne Nummer des Weckrufs <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_time</b> - Weckzeit des Weckrufs <i>1</i></li>
      <li><b>alarm</b><i>1</i><b>_wdays</b> - Wochentage des Weckrufs <i>1</i></li>
      
      <li><b>box_fwVersion</b> - Firmware-Version der Box, wenn veraltet dann wird '(old)' angehangen</li>
      <li><b>box_guestWlan</b> - Aktueller Status des G&auml;ste-WLAN</li>
      <li><b>box_guestWlanRemain</b> - Verbleibende Zeit bis zum Ausschalten des G&auml;ste-WLAN</li>
      <li><b>box_model</b> - Fritz!Box-Modell</li>
      <li><b>box_moh</b> - Wartemusik-Einstellung</li>
      <li><b>box_tr069</b> - Provider-Fernwartung TR069 (sicherheitsrelevant!)</li>
      <li><b>box_wlan_2.4GHz</b> - Aktueller Status des 2.4-GHz-WLAN</li>
      <li><b>box_wlan_5GHz</b> - Aktueller Status des 5-GHz-WLAN</li>
      
      <li><b>dect</b><i>1</i> - Name des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_alarmRingTone</b> - Klingelton beim Wecken &uuml;ber das DECT Telefon <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_custRingTone</b> - Benutzerspezifischer Klingelton des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_fwVersion</b> - Firmware-Version des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Interne Nummer des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Interner Klingelton des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Hersteller des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_model</b> - Modell des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_radio</b> - aktuelle Internet Radio Station des DECT Telefons <i>1</i></li>
      
      <li><b>fon</b><i>1</i> - Name des analogen Telefonanschlusses <i>1</i> an der Fritz!Box</li>
      <li><b>fon</b><i>1</i><b>_intern</b> - Interne Nummer des analogen Telefonanschlusses <i>1</i></li>
      
      <li><b>diversity</b><i>1</i> - Eigene Rufnummer der Rufumleitung <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_dest</b> - Zielnummer der Rufumleitung <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_state</b> - Aktueller Status der Rufumleitung <i>1</i></li>
      
      <li><b>radio</b><i>01</i> - Name der Internetradiostation <i>01</i></li>
      
      <li><b>tam</b><i>1</i> - Name des Anrufbeantworters <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_newMsg</b> - Anzahl neuer Nachrichten auf dem Anrufbeantworter <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_oldMsg</b> - Anzahl alter Nachrichten auf dem Anrufbeantworter <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_state</b> - Aktueller Status des Anrufbeantworters <i>1</i></li>
      
      <li><b>user</b><i>01</i> - Name von Nutzer/IP <i>1</i> f&uuml;r den eine Zugangsbeschr&auml;nkung (Kindersicherung) eingerichtet ist</li>
      <li><b>user</b><i>01</i>_thisMonthTime - Internetnutzung des Nutzers/IP <i>1</i> im aktuellen Monat (Kindersicherung)</li>
      <li><b>user</b><i>01</i>_todaySeconds - heutige Internetnutzung des Nutzers/IP <i>1</i> in Sekunden (Kindersicherung)</li>
      <li><b>user</b><i>01</i>_todayTime - heutige Internetnutzung des Nutzers/IP <i>1</i> (Kindersicherung)</li>
   </ul>
   <br>
</ul>
</div>

=end html_DE

=cut--