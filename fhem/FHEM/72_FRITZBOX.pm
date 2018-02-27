###############################################################
# $Id$
#
#  72_FRITZBOX.pm 
#
#  (c) 2014 Torsten Poitzsch
#  (c) 2014-2016 tupol http://forum.fhem.de/index.php?action=profile;u=5432
#
#  This module handles the Fritz!Box router and the Fritz!Phone MT-F and C4
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
my $missingModul = "";
my $missingModulTelnet = "";
my $missingModulWeb = "";
my $missingModulTR064 = "";
our $FRITZBOX_TR064pwd;
our $FRITZBOX_TR064user;

eval "use URI::Escape;1" or $missingModul .= "URI::Escape ";
eval "use MIME::Base64;1" or $missingModul .= "MIME::Base64 ";

use FritzBoxUtils; ## only for web access login

eval "use Net::Telnet;1" or $missingModulTelnet .= "Net::Telnet ";
#sudo apt-get install libjson-perl
# eval "use JSON::XS;1" or $missingModulWeb .= "JSON::XS ";
eval "use JSON;1" or $missingModulWeb .= "JSON ";
eval "use LWP::UserAgent;1" or $missingModulWeb .= "LWP::UserAgent ";

eval "use URI::Escape;1" or $missingModulTR064 .= "URI::Escape ";
# sudo apt-get install libsoap-lite-perl
eval "use SOAP::Lite;1" or $missingModulTR064 .= "Soap::Lite ";
eval "use Data::Dumper;1" or $missingModulTR064 .= "Data::Dumper ";

sub FRITZBOX_Log($$$);
sub FRITZBOX_Init($);
sub FRITZBOX_Set_Cmd_Start($);
sub FRITZBOX_Shell_Exec($$);
sub FRITZBOX_StartRadio_Shell($@);
sub FRITZBOX_StartRadio_Web($@);
sub FRITZBOX_Readout_Add_Reading ($$$$@);
sub FRITZBOX_Readout_Process($$);
sub FRITZBOX_SendMail_Shell($@);
sub FRITZBOX_SetCustomerRingTone($@);
sub FRITZBOX_SetMOH($@);
sub FRITZBOX_TR064_Init($$);
sub FRITZBOX_Wlan_Run($);
sub FRITZBOX_Web_Query($$@);

our $telnet;

my %fonModel = ( 
        '0x01' => "MT-D"
      , '0x03' => "MT-F"
      , '0x04' => "C3"
      , '0x05' => "M2"
      , '0x08' => "C4"
   );

my %ringTone =  qw { 
    0 HandsetDefault 1 HandsetInternalTone 
    2 HandsetExternalTon 3 Standard 
    4 Eighties   5 Alert 
    6 Ring       7 RingRing 
    8 News       9 CustomerRingTone 
    10 Bamboo   11 Andante 
    12 ChaCha   13 Budapest 
    14 Asia     15 Kullabaloo 
    16 silent   17 Comedy 
    18 Funky    19 Fatboy 
    20 Calypso  21 Pingpong 
    22 Melodica 23 Minimal 
    24 Signal   25 Blok1 
    26 Musicbox 27 Blok2 
    28 2Jazz   
    33 InternetRadio 34 MusicList 
   };

my %dialPort = qw {
   1 fon1 2 fon2
   3 fon3
   50 allFons
   60 dect1 61 dect2
   62 dect3 63 dect4
   64 dect5 65 dect6
   };

my %gsmNetworkState = qw {
   0 disabled  1 registered_home
   2 searching 3 registration_denied
   4 unknown   5 registered_roaming
   6 limited_service
   };

my %gsmTechnology = qw {
   0 GPRS 1 GPRS
   2 UMTS 
   3 EDGE
   4 HSPA 5 HSPA 6 HSPA
   };

my %ringToneNumber;
while (my ($key, $value) = each %ringTone) {
   $ringToneNumber{lc $value}=$key;
}

my %alarmDays = qw{1 Mo 2 Tu 4 We 8 Th 16 Fr 32 Sa 64 Su};
 
my %userType = qw{1 IP 2 PC-User 3 Default 4 Guest};

my %mohtype = (0=>"default", 1=>"sound", 2=>"customer", "err"=>"" );

my %landevice = ();

# FIFO Buffer for commands
my @cmdBuffer=();
my $cmdBufferTimeout=0;

my $ttsCmdTemplate = 'wget -U Mozilla -O "[ZIEL]" "http://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&prev=input&tl=[SPRACHE]&q=[TEXT]"';
my $ttsLinkTemplate = 'http://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&prev=input&tl=[SPRACHE]&q=[TEXT]';
# VoiceRSS: http://www.voicerss.org/api/documentation.aspx

my $mohUpload = '/var/tmp/fhem_moh_upload';
my $mohOld = '/var/tmp/fhem_fx_moh_old';
my $mohNew = '/var/tmp/fhem_fx_moh_new';
   
#######################################################################
sub FRITZBOX_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "FRITZBOX $instName: $sub.$xline " . $text;
} # End FRITZBOX_Log

#######################################################################
sub FRITZBOX_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRITZBOX_Define";
  $hash->{UndefFn}  = "FRITZBOX_Undefine";
  $hash->{DeleteFn}  = "FRITZBOX_Delete";
  $hash->{RenameFn}  = "FRITZBOX_Rename";

  $hash->{SetFn}    = "FRITZBOX_Set";
  $hash->{GetFn}    = "FRITZBOX_Get";
  $hash->{AttrFn}   = "FRITZBOX_Attr";
  $hash->{AttrList} = "allowShellCommand:0,1 "
                ."allowTR064Command:0,1 "
                ."boxUser "
                ."disable:0,1 "
                ."defaultCallerName "
                ."defaultUploadDir "
                ."forceTelnetConnection:0,1 "
                ."fritzBoxIP "
                ."INTERVAL "
                ."m3uFileLocal "
                ."m3uFileURL "
                ."ringWithIntern:0,1,2 "
                ."telnetUser "
                ."telnetTimeOut "
                ."useGuiHack:0,1 "
                ."userTickets "
               # ."ttsRessource:Google,ESpeak "
                .$readingFnAttributes;
                
} # end FRITZBOX_Initialize

#######################################################################
sub FRITZBOX_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Usage: define <name> FRITZBOX [IP address]" if(@args <2 || @args >3);  

   my $name = $args[0];

   $hash->{NAME} = $name;
   
   $hash->{HOST} = "undefined";
   $hash->{HOST} = $args[2]     if defined $args[2];
   $hash->{fhem}{definedHost} = $hash->{HOST}; # to cope with old attribute definitions

   my $msg;
# stop if certain perl moduls are missing
   if ( $missingModul ) {
      $msg = "Cannot define a FRITZBOX device. Perl modul $missingModul is missing.";
      FRITZBOX_Log $hash, 1, $msg;
      return $msg;
   }

   $hash->{STATE}              = "Initializing";
   $hash->{INTERVAL}           = 300; 
   $hash->{fhem}{modulVersion} = '$Date$';
   $hash->{fhem}{lastHour}     = 0;
   $hash->{fhem}{LOCAL}        = 0;

   $hash->{helper}{TimerReadout} = $name.".Readout";
   $hash->{helper}{TimerCmd} = $name.".Cmd";

   # my $tr064Port = FRITZBOX_TR064_Init ($hash);
   # $hash->{SECPORT} = $tr064Port    if $tr064Port;
   
 # Check APIs after fhem.cfg is processed
   $hash->{APICHECKED} = 0;
   $hash->{fhem}->{is_double_wlan} = -1;
   $hash->{LUAQUERY} = -1;
   $hash->{REMOTE} = -1;
   $hash->{TELNET} = -1;
   $hash->{TR064} = -1;
   $hash->{WEBCM} = -1;
   RemoveInternalTimer($hash->{helper}{TimerReadout});
   InternalTimer(gettimeofday()+1 , "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 0);

# Inform about missing PERL modules
   if ( $missingModulTelnet || $missingModulWeb || $missingModulTR064 ) {
      my $msg = "Modul functionality limited because of missing perl modules: ".$missingModulTelnet . $missingModulWeb . $missingModulTR064;
      FRITZBOX_Log $hash, 2, $msg;
      $hash->{PERL} = $msg;
   }
   
   return undef;
} #end FRITZBOX_Define

#######################################################################
sub FRITZBOX_Undefine($$)
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

#######################################################################
sub FRITZBOX_Delete ($$)
{
   my ( $hash, $name ) = @_;
   
   my $index = $hash->{TYPE}."_".$name."_passwd";
   setKeyValue($index, undef);
 
   return undef;
}

#######################################################################
sub FRITZBOX_Rename($$)
{
    my ($new, $old) = @_; 
   
    my $old_index = "FRITZBOX_".$old."_passwd";
    my $new_index = "FRITZBOX_".$new."_passwd";
   
    my ($err, $old_pwd) = getKeyValue($old_index);
   
    setKeyValue($new_index, $old_pwd);
    setKeyValue($old_index, undef);
}

#######################################################################
sub FRITZBOX_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value
   my $hash = $defs{$name};

   if ($aName eq "fritzBoxIP") {
      if ($cmd eq "set") {
         $hash->{HOST} = $aVal;
      }
      else {
         $hash->{HOST} = $hash->{fhem}{definedHost};
      }
   }

   # Stop the sub if FHEM is not initialized yet
  return undef    unless $init_done;
  
   if ( $aName =~ /fritzBoxIP|m3uFileLocal|m3uFileURL/ && $hash->{APICHECKED} == 1 
        || $aName eq "disable" ) {
      $hash->{APICHECKED} = 0;
      RemoveInternalTimer($hash->{helper}{TimerReadout});
      InternalTimer(gettimeofday()+1, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 1);
      # FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
   }

   return undef;
} # FRITZBOX_Attr ende

#######################################################################
sub FRITZBOX_Set($$@) 
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";
   
   my $list = "call"
            . " checkAPIs:noArg"
            . " diversity"
            . " guestWlan:on,off"
            . " password"
            . " ring"
            . " tam"
            . " update:noArg"
            . " wlan:on,off";
   $list .= " wlan2.4:on,off"
          . " wlan5:on,off"         
         if $hash->{fhem}->{is_double_wlan} == 1;
   $list .= " alarm"
          . " dect:on,off"
          . " startRadio"
         if $hash->{WEBCM}==1 || $hash->{TELNET}==1;
   $list .= " sendMail"
          . " customerRingTone"
          . " moh"
         if $hash->{TELNET}==1;

# . " convertMOH"
            # . " convertRingTone"

   my $forceShell = ( AttrVal( $name, "forceTelnetConnection",  0 ) == 1 || defined $hash->{REMOTE} && $hash->{REMOTE} == 0 );

# set alarm
   if ( lc $cmd eq 'alarm') {
      if ( int @val > 0 && $val[0] =~ /^(1|2|3)$/ ) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         return "'set ... alarm' is not supported by the limited interfaces of your Fritz!Box firmware."
            unless $hash->{WEBCM}==1 || $forceShell;
         return FRITZBOX_Set_Alarm_Web ($hash, @val)
            unless $forceShell;
         return FRITZBOX_Set_Alarm_Shell ($hash, @val);
      }
   
   } 
# set call
   elsif ( lc $cmd eq 'call') {
      if (int @val > 0) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "call ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
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
   } 
   elsif ( lc $cmd eq 'checkapis') {
      Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
      $hash->{APICHECKED} = 0;
      $hash->{fhem}{sidTime} = 0;
      $hash->{fhem}{LOCAL} = 1;
      FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL} = 0;
      return undef;
   } 
   elsif ( lc $cmd eq 'customerringtone') {
      if (int @val > 0) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         return FRITZBOX_SetCustomerRingTone ($hash, @val);
      }
      
   } 
   elsif ( lc $cmd eq 'dect') {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[0];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         if ($forceShell) { # Shell
            FRITZBOX_Shell_Exec( $hash, "ctlmgr_ctl w dect settings/enabled $state");
         }
         else { #webcm
            my @webCmdArray = ( ["dect:settings/enabled" => $state] );
            return "'set ... dect' is not supported by the limited interfaces of your Fritz!Box firmware."
               unless $hash->{WEBCM}==1;
            FRITZBOX_Web_CmdPost ($hash, \@webCmdArray);
         }
         
         readingsSingleUpdate($hash,"box_dect",$val[0], 1);
         return undef;
      }
   } 
   elsif ( lc $cmd eq 'diversity') {
      if ( int @val == 2 && $val[1] =~ /^(on|off)$/ ) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         return "Error, no diversity".$val[0]." to set."   
               unless defined $hash->{READINGS}{"diversity".$val[0]};
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         if ($forceShell) { # Shell
            FRITZBOX_Shell_Exec( $hash, "ctlmgr_ctl w telcfg settings/Diversity".( $val[0] - 1 )."/Active ".$state );
         }
         elsif ( $hash->{WEBCM}==1 ) { #webcm
            my @webCmdArray = ( ["telcfg:settings/Diversity".( $val[0] - 1 )."/Active " => $state] );
            FRITZBOX_Web_CmdPost ($hash, \@webCmdArray);
         }
         elsif ( $hash->{TR064}==1 ) { #tr064
            my @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "SetDeflectionEnable", "NewDeflectionId", $val[0] - 1, "NewEnable", $state] );
            FRITZBOX_TR064_Cmd ($hash, 0, \@tr064CmdArray);
         }
         else {
            return "'set ... diversity' is not supported by the limited interfaces of your Fritz!Box firmware.";
         }
         readingsSingleUpdate($hash,"diversity".$val[0]."_state",$val[1], 1);
         return undef;
      }
   } 
   elsif ( lc $cmd eq 'guestwlan') {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "guestwlan ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   } 
   elsif ( lc $cmd eq 'moh') {
      if (int @val > 0) 
      {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         $resultStr = FRITZBOX_SetMOH $hash, @val;
         if ($resultStr =~ /^[012]$/ )
         {
            readingsSingleUpdate($hash,"box_guestWlan",$mohtype{$resultStr}, 1);
            return undef;
         }
         else
         {
            return $resultStr;
         }
      }
   }
# set password
   elsif ( lc $cmd eq 'password') {
      if (int @val == 1) 
      {
         return FRITZBOX_storePassword ( $hash, $val[0] );
      }
   }
#set Ring
   elsif ( lc $cmd eq 'ring') {
      if (int @val > 0) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "ring ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   }
   elsif ( lc $cmd eq 'sendmail') {
      Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
      return "'set ... sendMail' is not supported by the limited interfaces of your Fritz!Box firmware."
         unless $hash->{TELNET}==1;
      FRITZBOX_SendMail_Shell $hash, @val;
      return undef;
   }
   elsif ( lc $cmd eq 'startradio') {
      if (int @val > 0) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         return "'set ... startRadio' is not supported by the limited interfaces of your Fritz!Box firmware."
            unless $hash->{WEBCM}==1 || $forceShell;
         return FRITZBOX_StartRadio_Web $hash, @val unless $forceShell;
         return FRITZBOX_StartRadio_Shell $hash, @val;
      }
   } 
   elsif ( lc $cmd eq 'tam') {
      if ( int @val == 2 && defined( $hash->{READINGS}{"tam".$val[0]} ) && $val[1] =~ /^(on|off)$/ ) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;
         if ($forceShell) { # Shell
            FRITZBOX_Shell_Exec( $hash, "ctlmgr_ctl w tam settings/TAM".( $val[0] - 1 )."/Active ".$state );
         }
         elsif ($hash->{SECPORT}) { #TR-064
            my @tr064CmdArray = (["X_AVM-DE_TAM:1", "x_tam", "SetEnable", "NewIndex", $val[0] - 1 , "NewEnable", $state]);
            FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         }
         else { #webcm
            my @webCmdArray = ( ["tam:settings/TAM".( $val[0] - 1 )."/Active" => $state] );
            FRITZBOX_Web_CmdPost ($hash, \@webCmdArray);
         }
         
         readingsSingleUpdate($hash,"tam".$val[0]."_state",$val[1], 1);
         return undef;
      }
   } 
   elsif ( lc $cmd eq 'update' ) {
      Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
      $hash->{fhem}{LOCAL}=1;
      FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL}=0;
      return undef;
   }
   elsif ( lc $cmd eq 'wlan') {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "wlan ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   }
   elsif ( lc $cmd =~ /^wlan(2\.4|5)$/ && $hash->{fhem}->{is_double_wlan} == 1 ) {
      if ( int @val == 1 && $val[0] =~ /^(on|off)$/ ) {
         Log3 $name, 3, "FRITZBOX: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, lc ($cmd) . " " . join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   }

   return "Unknown argument $cmd or wrong parameter(s), choose one of $list";

} # end FRITZBOX_Set
# ctlmgr_ctl r timer settings/KidsTimerXML1/
# ctlmgr_ctl r filter_profile settings/profile5/timeprofile_id
# ctlmgr_ctl r filter_profile settings/profile5/name

#######################################################################
sub FRITZBOX_Get($@)
{
   my ($hash, $name, $cmd, @val) = @_;
   my $returnStr;

   if( lc $cmd eq "luaquery"  && AttrVal( $name, "allowTR064Command", 0 ) && defined $hash->{SECPORT}) {  
   # get Fritzbox luaQuery inetstat:status/Today/BytesReceivedLow
   # get Fritzbox luaQuery telcfg:settings/AlarmClock/list(Name,Active,Time,Number,Weekdays)
         Log3 $name, 3, "FRITZBOX: get $name $cmd ".join(" ", @val);

      return "Wrong number of arguments, usage: get $name luaQuery <query>"       if int @val !=1;

      $returnStr  = "Result of query = '$val[0]'\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      my $queryStr = "&result=".$val[0];
      my $result = FRITZBOX_Web_Query( $hash, $queryStr) ;
      
      my $tmp;
      if (ref $result->{result} eq "") {     $tmp = $result->{result}; }
      else {      $tmp = Dumper ($result->{result}); }
      return $returnStr . $tmp;
   }
   elsif( lc $cmd eq "ringtones" ) {
      Log3 $name, 3, "FRITZBOX: get $name $cmd ".join(" ", @val);
      $returnStr  = "Ring tones to use with 'set <name> ring <intern> <duration> <ringTone>'\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      $returnStr .= join "\n", sort values %ringTone;
      return $returnStr;
   }
   elsif( lc $cmd eq "shellcommand" && int @val && AttrVal( $name, "allowShellCommand", 0 ) ) {  
      Log3 $name, 3, "FRITZBOX: get $name $cmd ".join(" ", @val);
      return "'get ... shellcommand' is not supported by the limited interfaces of your Fritz!Box firmware."
         unless $hash->{TELNET}==1;
      my $shCmd = join " ", @val;
      return FRITZBOX_Shell_Exec( $hash, $shCmd );
   }
   elsif( lc $cmd eq "tr064command" && AttrVal( $name, "allowTR064Command", 0 ) ) {
# http://fritz.box:49000/tr64desc.xml
#get Fritzbox tr064command DeviceInfo:1 deviceinfo GetInfo
#get Fritzbox tr064command X_VoIP:1 x_voip X_AVM-DE_GetPhonePort NewIndex 1
#get Fritzbox tr064command X_VoIP:1 x_voip X_AVM-DE_DialNumber NewX_AVM-DE_PhoneNumber **612
#get Fritzbox tr064command X_VoIP:1 x_voip X_AVM-DE_DialHangup
#get Fritzbox tr064command WLANConfiguration:3 wlanconfig3 X_AVM-DE_GetWLANExtInfo
#get Fritzbox tr064command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetList
#get Fritzbox tr064command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetInfo NewDectID 1
#get Fritzbox tr064command X_AVM-DE_TAM:1 x_tam GetInfo NewIndex 0
#get Fritzbox tr064command X_AVM-DE_TAM:1 x_tam SetEnable NewIndex 0 NewEnable 0
#get Fritzbox tr064command InternetGatewayDevice:1 deviceinfo GetInfo
#get Fritzbox tr064command LANEthernetInterfaceConfig:1 lanethernetifcfg GetStatistics
      Log3 $name, 3, "FRITZBOX: get $name $cmd ".join(" ", @val);
      my ($a, $h) = parseParams( join (" ", @val) );
      @val = @$a;

      return "Wrong number of arguments, usage: get $name tr064command service control action [argName1 argValue1] [argName2 argValue2] ..."
         if int @val <3 || int(@val) %2 !=1;

      $returnStr  = "Result of TR064 call\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      $returnStr  = "Service='$val[0]'   Control='$val[1]'   Action='$val[2]'\n";
      for(my $i = 1; $i <= (int @val - 3)/2; $i++) {
         $returnStr .= "Parameter$i='$val[2*$i+1]' => '$val[2*$i+2]'\n";
      }
      $returnStr .= "----------------------------------------------------------------------\n";
      my @tr064CmdArray = ( \@val );
      my @result = FRITZBOX_TR064_Cmd( $hash, 1, \@tr064CmdArray );
      my $tmp = Dumper (@result);
      $returnStr .= $tmp;
      return $returnStr;
   }
   elsif( lc $cmd eq "tr064servicelist" ) {
      return FRITZBOX_TR064_Get_ServiceList ($hash);
   }
      
   my $list = "ringTones:noArg";
   $list .= " luaQuery"      if AttrVal( $name, "allowTR064Command", 0 );
   $list .= " tr064Command"  if AttrVal( $name, "allowTR064Command", 0 ) && defined $hash->{SECPORT};;
   $list .= " tr064ServiceList:noArg"      if AttrVal( $name, "allowTR064Command", 0 );
   $list .= " shellCommand"     if AttrVal( $name, "allowShellCommand", 0 ) && $hash->{TELNET}==1;
   return "Unknown argument $cmd, choose one of $list";
} # end FRITZBOX_Get

# Starts the data capturing and sets the new readout timer
#######################################################################
sub FRITZBOX_Readout_Start($)
{
   my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex( $timerpara, "." );    # rechter Punkt
   my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash = $defs{$name};

   my $runFn;
   
   if( AttrVal( $name, "disable", 0 ) == 1 ) {
      RemoveInternalTimer($hash->{helper}{TimerReadout});
      readingsSingleUpdate( $hash, "state", "disabled", 1 );
      return undef;
    }

# Set timer value (min. 60)
   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL",  $hash->{INTERVAL} );
   $hash->{INTERVAL} = 60     if $hash->{INTERVAL} < 60 && $hash->{INTERVAL} != 0;

   my $interval = $hash->{INTERVAL};
   
# First run is an API check
   unless ( $hash->{APICHECKED} ) {
      $interval = 10;
      $hash->{STATE} = "Check APIs";
      $runFn = "FRITZBOX_API_Check_Run";
   }
# Run shell or web api, restrict interval
   else {
      $runFn = "FRITZBOX_Readout_Run_Web";
      $runFn = "FRITZBOX_Readout_Run_Shell"     if AttrVal( $name, "forceTelnetConnection",  0 ) == 1 || $hash->{REMOTE} == 0;
   }
   
   if( $interval != 0 ) {
      RemoveInternalTimer($hash->{helper}{TimerReadout});
      InternalTimer(gettimeofday()+$interval, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 1);
   }

# Kill running process if "set update" is used
   if ( exists( $hash->{helper}{READOUT_RUNNING_PID} ) && $hash->{fhem}{LOCAL} == 1 ) {
      FRITZBOX_Log $hash, 1, "Old readout process still running. Killing old process ".$hash->{helper}{READOUT_RUNNING_PID};
      BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} ); 
      # stop FHEM, giving a FritzBox some time to free the memory 
      sleep 5     unless $hash->{REMOTE}==1; 
      delete( $hash->{helper}{READOUT_RUNNING_PID} );
   }
   
   $hash->{fhem}{LOCAL} = 2   if $hash->{fhem}{LOCAL} == 1;
   
   unless( exists $hash->{helper}{READOUT_RUNNING_PID} ) {
      $hash->{helper}{READOUT_RUNNING_PID} = BlockingCall($runFn, $name,
                                                       "FRITZBOX_Readout_Done", 55,
                                                       "FRITZBOX_Readout_Aborted", $hash);
      FRITZBOX_Log $hash, 4, "Fork process $runFn";
   } 
   else {
      FRITZBOX_Log $hash, 4, "Skip fork process $runFn";
   }

} # end FRITZBOX_Readout_Start

# Checks which API is available on the Fritzbox
#######################################################################
sub FRITZBOX_API_Check_Run($)
{
   my ($name) = @_;
   my $hash = $defs{$name};
   my $fritzShell = 0;
   my @roReadings;
   my $response;
   my $startTime = time();
   
   my $host = $hash->{HOST};

# if no FritzBoxIP is set, check if FHEM runs on a FritzBox under root user
    # unless (qx ( [ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0 ))
   if ( $host =~ /undefined|local/ ) {
      # set default host
      $host = "fritz.box";  
      if ( -X "/usr/bin/ctlmgr_ctl" ) {
         if ( $< != 0 ) {
            FRITZBOX_Log $hash, 3, "FHEM is running on a Fritz!Box but not as 'root' user (currently " .
                                    ( getpwuid( $< ) )[ 0 ] . "). Cannot run in local mode.";
         }
         else {
            $fritzShell = 1;
            $host = "local"; # mark as local host
            FRITZBOX_Log $hash, 5, "FHEM is running on a Fritz!Box as 'root' user.";
         }
      }
   }

# change host name if necessary
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HOST", $host)      if $host ne $hash->{HOST};

# Determine local or remote mode
   if ($fritzShell) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->REMOTE", 0;
      FRITZBOX_Log $hash, 4, "FRITZBOX modul runs in local mode.";
   }
   else {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->REMOTE", 1;
      FRITZBOX_Log $hash, 4, "FRITZBOX modul runs in remote mode.";
   }

# Check if perl modules for remote APIs exists
   if ($missingModulWeb) {
      FRITZBOX_Log $hash, 3, "Cannot check for box model and APIs webcm, luaQuery and TR064 because perl modul $missingModulWeb is missing on this system.";
   }
# Check for remote APIs
   else {
      my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);

   # Check if webcm exists
      $response = $agent->get( "http://".$host."/cgi-bin/webcm" );

      if ($response->is_success) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->WEBCM", 1;
         FRITZBOX_Log $hash, 4, "API webcm found (".$response->code.").";
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->WEBCM", 0;
         FRITZBOX_Log $hash, 4, "API webcm does not exist (".$response->status_line.")";
      }

   # Check if query.lua exists
      $response = $agent->get( "http://".$host."/query.lua" );

      if ($response->is_success) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 1;
         FRITZBOX_Log $hash, 4, "API luaQuery found (".$response->code.").";
      }
      elsif ($response->code eq "500" || $response->code eq "403") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 1;
         FRITZBOX_Log $hash, 4, "API luaQuery found but responded with: ".$response->status_line;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 0;
         FRITZBOX_Log $hash, 4, "API luaQuery does not exist (".$response->status_line.")";
      }

   # Check if tr064 specification exists and determine TR064-Port
      $response = $agent->get( "http://".$host.":49000/tr64desc.xml" );

      if ($response->is_success) { #determine TR064-Port
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TR064", 1;
         FRITZBOX_Log $hash, 4, "API TR-064 found.";
      #Determine TR064-Port
         my $tr064Port = FRITZBOX_TR064_Init ( $hash, $host );
         if ($tr064Port) {
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->SECPORT", $tr064Port;
            FRITZBOX_Log $hash, 4, "TR-064-SecurePort is $tr064Port.";
         }
         else {
            FRITZBOX_Log $hash, 4, "TR-064-SecurePort does not exist";
         }
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TR064", 0;
         FRITZBOX_Log $hash, 4, "API TR-064 does not exist: ".$response->status_line;
      }

   
   # Check if m3u can be created and the URL tested
      my $globalModPath = AttrVal( "global", "modpath", "." );
      my $m3uFileLocal = AttrVal( $name, "m3uFileLocal", $globalModPath."/www/images/".$name.".m3u" );
      if (open my $fh, '>', $m3uFileLocal) {
         my $ttsText = uri_escape("Lirumlarumlöffelstielwerdasnichtkannderkannnichtviel");
         my $ttsLink = $ttsLinkTemplate;
         $ttsLink =~ s/\[TEXT\]/$ttsText/;
         $ttsLink =~ s/\[SPRACHE\]/fr/;
         print $fh $ttsLink;
         close $fh;
         FRITZBOX_Log $hash, 4, "Created m3u file '$m3uFileLocal'.";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->M3U_LOCAL", $m3uFileLocal;

      # Get the m3u-URL
         my $m3uFileURL = AttrVal( $name, "m3uFileURL", "unknown" );
      # if no URL and no local file defined, then try to build the correct URL 
         if ( $m3uFileURL eq "unknown" && AttrVal( $name, "m3uFileLocal", "" ) eq "" ) {
         # Getting IP of FHEM host
            FRITZBOX_Log $hash, 4, "Try to get my IP address.";
            my $socket = IO::Socket::INET->new( Proto => 'tcp', PeerAddr => $host, PeerPort    => 'http(80)' );
            my $ip;
            $ip = $socket->sockhost if $socket; #A side-effect of making a socket connection is that our IP address is available from the 'sockhost' method
               FRITZBOX_Log $hash, 4, "Could not determine my ip address"  unless $ip;
         # Get a web port
            my $port;
               FRITZBOX_Log $hash, 4, "Try to get a FHEMWEB port.";
            foreach( keys %defs ) {
            if ( $defs{$_}->{TYPE} eq "FHEMWEB" && defined $defs{$_}->{PORT} ) {
                  $port = $defs{$_}->{PORT};
                  last;
               }
            }
            FRITZBOX_Log $hash, 4, "Could not find a FHEMWEB device."  unless $port;
            $m3uFileURL = "http://$ip:$port/fhem/images/$name.m3u"     if defined $ip && defined $port;
         }
      # Check if m3u can be accessed
         unless ( $m3uFileURL eq "unknown" ) {
            FRITZBOX_Log $hash, 4, "Try to get '$m3uFileURL'";
            $response = $agent->get( $m3uFileURL );
            if ($response->is_error) {
               FRITZBOX_Log $hash, 4, "Failed to get '$m3uFileURL': ".$response->status_line;
               $m3uFileURL = "unknown"     ;
            }
         }
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->M3U_URL", $m3uFileURL;
      } 
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->M3U_LOCAL", "undefined";
         FRITZBOX_Log $hash, 4, "Error: Cannot create save file '$m3uFileLocal' because $!\n";
      }

   # Box model per jason
      FRITZBOX_Log $hash, 5, "Read 'jason_boxinfo'";
      my $url = "http://".$host."/jason_boxinfo.xml";
      
      $response = $agent->get( $url );
      my $content  = $response->content;
      # FRITZBOX_Log $hash, 5, "jason_boxinfo returned: $content";

      FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_model", $1)   if ( $content =~ /<j:Name>(.*)<\/j:Name>/ );    
      
      FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_oem", $1)    if $content =~ /<j:OEM>(.*)<\/j:OEM>/;
      FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_fwVersion", $1)    if $content =~ /<j:Version>(.*)<\/j:Version>/;
    
    # Ansonsten Box-Model per system_status einlesen
      unless ($content =~ /<j:Name>/) {
      # Muss nochmal neu gesetzt werden, sonst gibt es einen Fehler (keine Ahnung warum)
         $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
         $url = "http://".$host."/cgi-bin/system_status";
         FRITZBOX_Log $hash, 5, "Read 'system_status'";
         
         $response = $agent->get( $url );
         $content  = $response->content;
         # FRITZBOX_Log $hash, 5, "system_status returned: $content";
         if ($response->is_success) {
            $content=$1    if $content =~ /<body>(.*)<\/body>/;
            
            my @result = split /-/, $content;
            # http://www.tipps-tricks-kniffe.de/fritzbox-wie-lange-ist-die-box-schon-gelaufen/
            # 0 FritzBox-Modell
            # 1 Annex/Erweiterte Kennzeichnung
            # 2 Gesamtlaufzeit der Box in Stunden, Tage, Monate
            # 3 Gesamtlaufzeit der Box in Jahre, Anzahl der Neustarts
            # 4+5 Hashcode
            # 6 Status
            # 7 Firmwareversion
            # 8 Sub-Version/Unterversion der Firmware
            # 9 Branding, z.B. 1und1 (Provider 1&1) oder avm (direkt von AVM)
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_model",  $result[0];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwVersion", $result[7];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_oem",    $result[9];
         }
         else {
            FRITZBOX_Log $hash, 4, "Error: ".$response->status_line;
         };
      };
   }
   
# Check if telnet modul exists
   if ($missingModulTelnet) {
      FRITZBOX_Log $hash, 4, "Cannot check for telnet access because perl modul $missingModulTelnet is missing on this system.\n";
   }
   else {
      my $timeout = AttrVal( $name, "telnetTimeOut", "10");
      my $telnet = new Net::Telnet ( Host=>$host, Port => 23, Timeout=>$timeout, Errmode=>'return', Prompt=>'/# $/');
      if (!$telnet) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TELNET", 0;
         $telnet = undef;
         FRITZBOX_Log $hash, 4, "Could not open telnet connection to $host: $!";
      }   
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TELNET", 1;
         $telnet->close;
         FRITZBOX_Log $hash, 4, "Telnet connection availabel.";
      }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECKED", 1;

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   my $returnStr = join('|', @roReadings );

   FRITZBOX_Log $hash, 4, "Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 5, "Handover to main process (".length ($returnStr)."): ".$returnStr;
   
   return $name."|".encode_base64($returnStr,"");
   
} #end FRITZBOX_API_Check_Run
   
# Starts the data capturing via Telnet and sets the new timer
#######################################################################
sub FRITZBOX_Readout_Run_Shell($)
{
   my ($name) = @_;
   my $hash = $defs{$name};

   my $result;
   my $rName;
   my @cmdArray;
   my @readoutCmdArray;
   my $resultArray;
   my @roReadings;
   my %dectFonID;
   my $i;
   my $startTime = time();

   my $slowRun = 0;
   if ( int(time/3600) != $hash->{fhem}{lastHour} || $hash->{fhem}{LOCAL} != 0) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->lastHour", int(time/3600);
      $slowRun = 1;
      FRITZBOX_Log $hash, 4, "Start update of slow changing device readings.";
   }
   else {
      FRITZBOX_Log $hash, 4, "Start update of fast changing device readings.";
   }

   my $returnStr;
 
   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return $name."|".encode_base64("Error|$result","")
      if $result;
   
   if ($slowRun == 1) {
      
     # Init and Counters
      push @readoutCmdArray, ["", "ctlmgr_ctl r telcfg settings/Foncontrol" ];
      push @readoutCmdArray, ["", "ctlmgr_ctl r telcfg settings/Foncontrol/User/count" ];
      push @readoutCmdArray, ["", "ctlmgr_ctl r dect settings/Handset/count" ];
      push @readoutCmdArray, ["fhem->radioCount", "ctlmgr_ctl r configd settings/WEBRADIO/count" ];
      push @readoutCmdArray, ["", "ctlmgr_ctl r user settings/user/count" ];
      push @readoutCmdArray, ["", 'echo $CONFIG_AB_COUNT'];
      push @readoutCmdArray, ["", "ctlmgr_ctl r landevice settings/landevice/count" ];
      push @readoutCmdArray, ["", "ctlmgr_ctl r tam settings/TAM/count" ];
      push @readoutCmdArray, ["", "ctlmgr_ctl r telcfg settings/RefreshDiversity" ];
      push @readoutCmdArray, ["", "ctlmgr_ctl r telcfg settings/Diversity/count" ];

   # Box Features
      push @readoutCmdArray, [ "fhem->is_double_wlan", "ctlmgr_ctl r wlan settings/feature_flags/DBDC", "01" ];

   # Box model and firmware
      push @readoutCmdArray, [ "box_model", 'echo $CONFIG_PRODUKT_NAME' ];
      push @readoutCmdArray, [ "box_oem", 'echo $OEM' ];
      push @readoutCmdArray, [ "box_fwVersion", "ctlmgr_ctl r logic status/nspver" ];
      push @readoutCmdArray, [ "box_fwUpdate", "ctlmgr_ctl r updatecheck status/update_available_hint" ];
      push @readoutCmdArray, [ "box_tr069", "ctlmgr_ctl r tr069 settings/enabled", "onoff" ];


   # Execute commands
      $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings);

      return $name."|".encode_base64("Error|No STDOUT from shell command.","") 
         unless defined $resultArray;

      my $dectCount = $resultArray->[1];
      $dectCount = 1 unless $dectCount=~ /\d/;
      $dectCount--;
      my $handsetCount = $resultArray->[2];
      $handsetCount = 1 unless $dectCount=~ /\d/;
      $handsetCount--;
      my $radioCount = $resultArray->[3];
      $radioCount = 0 unless $radioCount=~ /\d/;
      my $userCount = $resultArray->[4];
      my $fonCount = $resultArray->[5];
      my $lanDeviceCount = $resultArray->[6];
      my $tamCount = $resultArray->[7];
      my $divCount = $resultArray->[9];
      
      
   # Internetradioliste erzeugen
      $i = 0;
      $rName = "radio00";
      while ( $i<$radioCount || defined $hash->{READINGS}{$rName} )
      {
         push @readoutCmdArray, [ $rName, "ctlmgr_ctl r configd settings/WEBRADIO".$i."/Name" ];
         $i++;
         $rName = sprintf ("radio%02d",$i);
      }

      $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );

      my @radio = ();
      for (0..$radioCount-1)
      {
         if ($resultArray->[$_] ne "")
         {
            $radio[$_] = $resultArray->[$_];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->radio->".$_, $resultArray->[$_];
         }
      }

   # LanDevice-Liste erzeugen
      if ($lanDeviceCount > 0 )
      {
         for (0..$lanDeviceCount-1)
         {
            push @readoutCmdArray, [ "", "ctlmgr_ctl r landevice settings/landevice".$_."/ip" ];
            push @readoutCmdArray, [ "", "ctlmgr_ctl r landevice settings/landevice".$_."/name" ];
         }
         $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );

         %landevice = ();
         for (0..$lanDeviceCount-1)
         {
            my $offset = 2 * $_;
            my $dIp = $resultArray->[ $offset ];
            my $dName = $resultArray->[ $offset +1];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->landevice->$dIp", $dName;
            $landevice{$dIp}=$dName;
         }  
      }

# Dect Telefonnummern bestimmen
      for (1..$dectCount)
      {
        # 0 Dect-Interne Nummer
         push @readoutCmdArray, [ "dect".$_."_intern", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Intern" ];
        # 1 Dect-Telefonname
         push @readoutCmdArray, [ "dect".$_, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Name" ];
        # 2 Internal Ring Tone Name
         push @readoutCmdArray, [ "dect".$_."_intRingTone", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/IntRingTone", "ringtone" ];
        # 3 Alarm Ring Tone Name
         push @readoutCmdArray, [ "dect".$_."_alarmRingTone", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/AlarmRingTone0", "ringtone" ];
        # 4 Radio Name
         push @readoutCmdArray, [ "dect".$_."_radio", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/RadioRingID", "radio" ];
        # 5 Background image
         push @readoutCmdArray, [ "dect".$_."_imagePath", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/ImagePath" ];
        # 6 Customer Ring Tone
         push @readoutCmdArray, [ "dect".$_."_custRingTone", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingTone" ];
        # 7 Customer Ring Tone Name
         push @readoutCmdArray, [ "dect".$_."_custRingToneName", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingToneName" ];
        # 8 UserID
         push @readoutCmdArray, [ "", "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Id" ];
      }
      $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );
      
      for (1..$dectCount)
      {
         my $offset = $_ * 9 - 9;
         my $intern = $resultArray->[$offset];
         my $ID = $resultArray->[ $offset + 8 ];
         if ($intern)
         {
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->$intern->name", $resultArray->[ $offset + 1 ];
            $dectFonID{$ID}{User} = $_;
            $dectFonID{$ID}{Intern} = $intern;
         }
      }

# Assign data of DECT handset to DECT numbers
      for (0..$handsetCount) {
        # 0 Handset FonUser
         push @readoutCmdArray, [ "", "ctlmgr_ctl r dect settings/Handset".$_."/User", "" ];   
        # 1 Handset manufacturer
         push @readoutCmdArray, [ "", "ctlmgr_ctl r dect settings/Handset".$_."/Manufacturer" ];   
        # 2 Phone Model
         push @readoutCmdArray, [ "", "ctlmgr_ctl r dect settings/Handset".$_."/Model", "model" ];   
        # 3 Firmware Version
         push @readoutCmdArray, [ "", "ctlmgr_ctl r dect settings/Handset".$_."/FWVersion" ];   
      }
      $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );
   
   # Handset and DECT user can be in different orders
      for (0..$handsetCount) {
         my $offset = $_ * 4;
         my $dectUserID = $resultArray->[$offset];
         if ($dectUserID) {
            my $dectUser = $dectFonID{$dectUserID}{User};
            push @roReadings, "dect".$dectUser."_manufacturer|" . $resultArray->[ $offset + 1 ];
            FRITZBOX_Log $hash, 5, "dect".$dectUser."_manufacturer: " . $resultArray->[ $offset + 1 ];
            push @roReadings, "dect".$dectUser."_model|" . $resultArray->[ $offset + 2 ];
            FRITZBOX_Log $hash, 5, "dect".$dectUser."_model: " . $resultArray->[ $offset + 2 ];
            push @roReadings, "dect".$dectUser."_fwVersion|" . $resultArray->[ $offset + 3 ];
            FRITZBOX_Log $hash, 5, "dect".$dectUser."_fwVersion: " . $resultArray->[ $offset + 3 ];
            my $intern = $dectFonID{$dectUserID}{Intern};
            push @roReadings, "fhem->$intern->brand|" . $resultArray->[ $offset + 1 ];
            push @roReadings, "fhem->$intern->model|" . $resultArray->[ $offset + 2 ];;
         }
      }
      
   # Analog Fons Name
      for (1..$fonCount) {
         push @readoutCmdArray, ["fon".$_, "ctlmgr_ctl r telcfg settings/MSN/Port".($_-1)."/Name" ];
         push @readoutCmdArray, ["fon".$_."_out", "ctlmgr_ctl r telcfg settings/MSN/Port".($_-1)."/MSN" ];
      }
      $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );
   
   # Number of analog Fons 
      for (1..$fonCount) {
         push @roReadings, "fon".$_."_intern|".$_
            if $resultArray->[($_-1)*2];
      }

# Prepare new command array
   # Check if TAM is displayed
      for (0..$tamCount-1) {
         push @readoutCmdArray, [ "", "ctlmgr_ctl r tam settings/TAM".$_."/Display" ];
      }
   # Check if user (parent control) is not completely blocked
      for (0..$userCount-1)
      {
         push @readoutCmdArray, ["", "ctlmgr_ctl r user settings/user".$_."/filter_profile_UID" ];
      }
   #!!! Execute commands !!!
      $resultArray = FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );
      

# Prepare new command array
   #Get TAM readings
      for (0..$tamCount-1) {
         $rName = "tam".($_+1);
         if ($resultArray->[$_] eq "1" || defined $hash->{READINGS}{$rName} )
         {
            push @readoutCmdArray, [ $rName, "ctlmgr_ctl r tam settings/TAM". $_ ."/Name" ];
            push @readoutCmdArray, [ $rName."_state", "ctlmgr_ctl r tam settings/TAM".$_."/Active", "onoff" ];
            push @readoutCmdArray, [ $rName."_newMsg", "ctlmgr_ctl r tam settings/TAM".$_."/NumNewMessages" ];
            push @readoutCmdArray, [ $rName."_oldMsg", "ctlmgr_ctl r tam settings/TAM".$_."/NumOldMessages" ];
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
            push @readoutCmdArray, [$rName, "ctlmgr_ctl r user settings/user".$i."/name", "deviceip" ];
            push @readoutCmdArray, [$rName."_thisMonthTime", "ctlmgr_ctl r user settings/user".$i."/this_month_time", "secondsintime" ];
            push @readoutCmdArray, [$rName."_todayTime", "ctlmgr_ctl r user settings/user".$i."/today_time", "secondsintime" ];
            push @readoutCmdArray, [$rName."_todaySeconds", "ctlmgr_ctl r user settings/user".$i."/today_time" ];
            push @readoutCmdArray, [$rName."_type", "ctlmgr_ctl r user settings/user".$i."/type", "usertype" ];
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
         push @readoutCmdArray, [$rName, "ctlmgr_ctl r telcfg settings/Diversity".$i."/MSN" ];
        # Diversity state
         push @readoutCmdArray, [$rName."_state", "ctlmgr_ctl r telcfg settings/Diversity".$i."/Active", "onoff" ];
        # Diversity destination
         push @readoutCmdArray, [$rName."_dest", "ctlmgr_ctl r telcfg settings/Diversity".$i."/Destination"];
         $i++;
         $rName = "diversity".($i+1);
      }
      
   # !!! Execute commands !!!
      FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );
   }
   
# WLAN
   push @readoutCmdArray, [ "box_wlan_2.4GHz", "ctlmgr_ctl r wlan settings/ap_enabled", "onoff" ];
# 2nd WLAN
   push @readoutCmdArray, [ "box_wlan_5GHz", "ctlmgr_ctl r wlan settings/ap_enabled_scnd", "onoff" ];
# Gäste WLAN
   push @readoutCmdArray, [ "box_guestWlan", "ctlmgr_ctl r wlan settings/guest_ap_enabled", "onoff" ];
   push @readoutCmdArray, [ "box_guestWlanRemain", "ctlmgr_ctl r wlan settings/guest_time_remain", ];
# Dect
   push @readoutCmdArray, [ "box_dect", "ctlmgr_ctl r dect settings/enabled", "onoff" ];
# Music on Hold
   push @readoutCmdArray, [ "box_moh", "ctlmgr_ctl r telcfg settings/MOHType", "mohtype" ];
# Power Rate
   push @readoutCmdArray, [ "box_powerRate", "ctlmgr_ctl r power status/rate_sumact"];

# Alarm clock
   for (0..2)
   {
     # Alarm clock name
      push @readoutCmdArray, ["alarm".($_+1), "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Name" ];
     # Alarm clock state
      push @readoutCmdArray, ["alarm".($_+1)."_state", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Active", "onoff" ];
     # Alarm clock time
      push @readoutCmdArray, ["alarm".($_+1)."_time", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Time", "altime" ];
     # Alarm clock number
      push @readoutCmdArray, ["alarm".($_+1)."_target", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Number", "alnumber" ];
     # Alarm clock weekdays
      push @readoutCmdArray, ["alarm".($_+1)."_wdays", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Weekdays", "aldays" ];
   }

   FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings );
   
   push @roReadings, "readoutTime|" . sprintf( "%.2f", time()-$startTime);
   $returnStr .= join('|', @roReadings );

   FRITZBOX_Telnet_CloseCon ( $hash );

   FRITZBOX_Log $hash, 4, "Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 5, "Handover to main process (".length ($returnStr)."): ".$returnStr;
   return $name."|".encode_base64($returnStr,"");

} # End FRITZBOX_Readout_Run_Shell

# http://fritz.box/cgi-bin/webcm?wlan:settings/guest_ap_enabled=1&sid=
      # FRITZBOX_Log $hash, 3, "Web connection established with $sid";
      # my $urlcgi = 'http://'.$host.'/cgi-bin/webcm';
      # my $response = $agent->post( $urlcgi,
         # [
          # "sid" => $sid,
          # "getpage"=>"../html/query.txt",
          # "var:cnt"=>"1",
          # "var:n[0]"=>"wlan:settings/ap_enabled"
          # "getpage" => "../html/de/menus/menu2.html",
          # "errorpage" => "../html/index.html",
          # "var:lang" => "de",
          # "var:pagename" => "home",
          # "var:menu" => "home",
          # "wlan:settings/guest_ap_enabled" => "1"
         # ],
       # );
      # FRITZBOX_Log $hash, 3, "Debug: ".$response->content;
   
# Starts the data capturing via query.lua and sets the new timer
#######################################################################
sub FRITZBOX_Readout_Run_Web($)
{
   my ($name) = @_;
   my $hash = $defs{$name};

   my $result;
   my $rName;
   my @roReadings;
   my %dectFonID;
   my %resultHash;
   my $startTime = time();
   my $runNo;
   my $sid;
   
#Start update 
   FRITZBOX_Log $hash, 4, "Prepare query string for luaQuery.";
   my $queryStr = "&radio=configd:settings/WEBRADIO/list(Name)"; # Webradio
   $queryStr .= "&box_dect=dect:settings/enabled"; # DECT Sender
   $queryStr .= "&handset=dect:settings/Handset/list(User,Manufacturer,Model,FWVersion)"; # DECT Handsets
   $queryStr .= "&wlanList=wlan:settings/wlanlist/list(mac,speed,speed_rx,rssi)"; # WLAN devices
   $queryStr .= "&wlanListNew=wlan:settings/wlanlist/list(mac,speed,rssi)"; # WLAN devices fw>=6.69
   #wlan:settings/wlanlist/list(hostname,mac,UID,state,rssi,quality,is_turbo,cipher,wmm_active,powersave,is_ap,ap_state,is_repeater,flags,flags_set,mode,is_guest,speed,speed_rx,channel_width,streams)   #wlan:settings/wlanlist/list(hostname,mac,UID,state,rssi,quality,is_turbo,wmm_active,cipher,powersave,is_repeater,flags,flags_set,mode,is_guest,speed,speed_rx,speed_rx_max,speed_tx_max,channel_width,streams,mu_mimo_group,is_fail_client)   
   $queryStr .= "&lanDevice=landevice:settings/landevice/list(mac,ip,ethernet,ethernet_port,guest,name,active,online,wlan,speed,UID)"; # LAN devices
   $queryStr .= "&lanDeviceNew=landevice:settings/landevice/list(mac,ip,ethernet,guest,name,active,online,wlan,speed,UID)"; # LAN devices fw>=6.69
   #landevice:settings/landevice/list(name,ip,mac,UID,dhcp,wlan,ethernet,active,static_dhcp,manu_name,wakeup,deleteable,source,online,speed,wlan_UIDs,auto_wakeup,guest,url,wlan_station_type,vendorname)
   #landevice:settings/landevice/list(name,ip,mac,parentname,parentuid,ethernet_port,wlan_show_in_monitor,plc,ipv6_ifid,parental_control_abuse,plc_UIDs)   #landevice:settings/landevice/list(name,ip,mac,UID,dhcp,wlan,ethernet,active,static_dhcp,manu_name,wakeup,deleteable,source,online,speed,wlan_UIDs,auto_wakeup,guest,url,wlan_station_type,vendorname,parentname,parentuid,ethernet_port,wlan_show_in_monitor,plc,ipv6_ifid,parental_control_abuse,plc_UIDs)
   $queryStr .= "&init=telcfg:settings/Foncontrol"; # Init
   $queryStr .= "&box_stdDialPort=telcfg:settings/DialPort"; #Dial Port
   $queryStr .= "&dectUser=telcfg:settings/Foncontrol/User/list(Id,Name,Intern,IntRingTone,AlarmRingTone0,RadioRingID,ImagePath,G722RingTone,G722RingToneName)"; # DECT Numbers
   $queryStr .= "&fonPort=telcfg:settings/MSN/Port/list(Name,MSN)"; # Fon ports
   $queryStr .= "&alarmClock=telcfg:settings/AlarmClock/list(Name,Active,Time,Number,Weekdays)"; # Alarm Clock
   $queryStr .= "&diversity=telcfg:settings/Diversity/list(MSN,Active,Destination)"; # Diversity (Rufumleitung)
   $queryStr .= "&box_moh=telcfg:settings/MOHType"; # Music on Hold
   $queryStr .= "&box_fwVersion=logic:status/nspver"; # FW Version #uimodlogic:status/nspver
   $queryStr .= "&box_fwVersion_neu=uimodlogic:status/nspver"; # FW Version
   $queryStr .= "&box_powerRate=power:status/rate_sumact"; # Power Rate
   $queryStr .= "&tam=tam:settings/TAM/list(Name,Display,Active,NumNewMessages,NumOldMessages)"; # TAM
   $queryStr .= "&box_cpuTemp=power:status/act_temperature"; # Box CPU Temperatur
   $queryStr .= "&box_ipExtern=connection0:status/ip"; # Externe IP-Adresse
   $queryStr .= "&box_connect=connection0:status/connect"; # Internet connection state
   $queryStr .= "&box_tr064=tr064:settings/enabled"; # TR064
   $queryStr .= "&box_tr069=tr069:settings/enabled"; # TR069
   $queryStr .= "&box_fwUpdate=updatecheck:status/update_available_hint";
   $queryStr .= "&userProfil=user:settings/user/list(name,filter_profile_UID,this_month_time,today_time,type)"; # User profiles
   $queryStr .= "&userProfilNew=user:settings/user/list(name,type)"; # User profiles fw>=6.69
   $queryStr .= "&is_double_wlan=wlan:settings/feature_flags/DBDC"; # Box Feature
   $queryStr .= "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
   $queryStr .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
   $queryStr .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # Gäste WLAN
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
   $queryStr .= "&TodayBytesReceivedHigh=inetstat:status/Today/BytesReceivedHigh";
   $queryStr .= "&TodayBytesReceivedLow=inetstat:status/Today/BytesReceivedLow";
   $queryStr .= "&TodayBytesSentHigh=inetstat:status/Today/BytesSentHigh";
   $queryStr .= "&TodayBytesSentLow=inetstat:status/Today/BytesSentLow";
   $queryStr .= "&GSM_RSSI=gsm:settings/RSSI";
   $queryStr .= "&GSM_NetworkState=gsm:settings/NetworkState";
   $queryStr .= "&GSM_AcT=gsm:settings/AcT";
   $queryStr .= "&UMTS_enabled=umts:settings/enabled"; 
   $queryStr .= "&userTicket=userticket:settings/ticket/list(id)";
   # $queryStr .= "&GSM_MaxUL=gsm:settings/MaxUL";
   # $queryStr .= "&GSM_MaxDL=gsm:settings/MaxDL";
   # $queryStr .= "&GSM_CurrentUL=gsm:settings/CurrentUL";
   # $queryStr .= "&GSM_CurrentDL=gsm:settings/CurrentDL";
   # $queryStr .= "&GSM_Established=gsm:settings/Established";
   # $queryStr .= "&GSM_BER=gsm:settings/BER";
   # $queryStr .= "&GSM_Manufacturer=gsm:settings/Manufacturer";
   # $queryStr .= "&GSM_Model=gsm:settings/Model";
   # $queryStr .= "&GSM_Operator=gsm:settings/Operator";
   # $queryStr .= "&GSM_PIN_State=gsm:settings/PIN_State";
   # $queryStr .= "&GSM_Trycount=gsm:settings/Trycount";
   # $queryStr .= "&GSM_ModemPresent=gsm:settings/ModemPresent";
   # $queryStr .= "&GSM_AllowRoaming=gsm:settings/AllowRoaming";
   # $queryStr .= "&GSM_VoiceStatus=gsm:settings/VoiceStatus";
   # $queryStr .= "&GSM_SubscriberNumber=gsm:settings/SubscriberNumber";
   # $queryStr .= "&GSM_InHomeZone=gsm:settings/InHomeZone";
   # $queryStr .= "&UMTS_enabled=umts:settings/enabled"; 
   # $queryStr .= "&UMTS_name=umts:settings/name";
   # $queryStr .= "&UMTS_provider=umts:settings/provider";
   # $queryStr .= "&UMTS_idle=umts:settings/idle";
   # $queryStr .= "&UMTS_backup_enable=umts:settings/backup_enable";
   # $queryStr .= "&UMTS_backup_downtime=umts:settings/backup_downtime";
   # $queryStr .= "&UMTS_backup_reverttime=umts:settings/backup_reverttime";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;
   
   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} ) {
      FRITZBOX_Log $hash, 2, "Error: ".$result->{Error};
      my $returnStr = "Error|" . $result->{Error};
      $returnStr .= "|fhem->sidTime|0"    if defined $result->{ResetSID};
      $returnStr .= "|" . join('|', @roReadings )     if int @roReadings;
      return $name."|".encode_base64($returnStr,"");
   }
   
   if ( defined $result->{AuthorizationRequired} ) {
      FRITZBOX_Log $hash, 2, "Error: AuthorizationRequired=".$result->{AuthorizationRequired};
      my $returnStr = "Error|Authorization required";
      $returnStr .= "|fhem->sidTime|0"    if defined $result->{ResetSID};
      $returnStr .= "|" . join('|', @roReadings )     if int @roReadings;
      return $name."|".encode_base64($returnStr,"");
   }

   # !!! copes with fw 6.69 !!!
   if ( ref $result->{wlanList} ne 'ARRAY' ) {
      FRITZBOX_Log $hash, 4, "Recognized query answer of firmware 6.69";
      my $result2;
      my $newQueryPart; 
      
    # gets WLAN speed for fw>=6.69
      $queryStr="";
      foreach ( @{ $result->{wlanListNew} } ) {
         $newQueryPart = "&".$_->{_node}."=wlan:settings/".$_->{_node}."/speed_rx";
         if (length($queryStr.$newQueryPart) < 4050) {
            $queryStr .= $newQueryPart;
         }
         else {
            $result2 = FRITZBOX_Web_Query( $hash, $queryStr );
            %{$result} = ( %{$result}, %{$result2 } );
            $queryStr = $newQueryPart;
         }
      }

    # gets LAN-Port for fw>=6.69
      foreach ( @{ $result->{lanDeviceNew} } ) {
         $newQueryPart = "&".$_->{_node}."=landevice:settings/".$_->{_node}."/ethernet_port";
         if (length($queryStr.$newQueryPart) < 4050) {
            $queryStr .= $newQueryPart;
         }
         else {
            $result2 = FRITZBOX_Web_Query( $hash, $queryStr );
            %{$result} = ( %{$result}, %{$result2 } );
            $queryStr = $newQueryPart;
         }
      }

    # get missing user-fields for fw>=6.69
      foreach ( @{ $result->{userProfilNew} } ) {
         $newQueryPart = "&".$_->{_node}."_filter=user:settings/".$_->{_node}."/filter_profile_UID";
         $newQueryPart .= "&".$_->{_node}."_month=user:settings/".$_->{_node}."/this_month_time";
         $newQueryPart .= "&".$_->{_node}."_today=user:settings/".$_->{_node}."/today_time";
         if (length($queryStr.$newQueryPart) < 4050) {
            $queryStr .= $newQueryPart;
         }
         else {
            $result2 = FRITZBOX_Web_Query( $hash, $queryStr );
            %{$result} = ( %{$result}, %{$result2 } );
            $queryStr = $newQueryPart;
         }
      }

    # Final Web-Query
      $result2 = FRITZBOX_Web_Query( $hash, $queryStr );
      %{$result} = ( %{$result}, %{$result2 } );
      
    # create fields for wlanList-Entries (for fw 6.69)
      $result->{wlanList} = $result->{wlanListNew};
      foreach ( @{ $result->{wlanList} } ) {
         $_->{speed_rx} = $result->{ $_->{_node} }; 
      }

    # Create fields for lanDevice-Entries (for fw 6.69)
      $result->{lanDevice} = $result->{lanDeviceNew};
      foreach ( @{ $result->{lanDevice} } ) {
         $_->{ethernet_port} = $result->{ $_->{_node} }; 
      }

    # Create fields for user-Entries (for fw 6.69)
      $result->{userProfil} = $result->{userProfilNew};
      foreach ( @{ $result->{userProfil} } ) {
         $_->{filter_profile_UID} = $result->{ $_->{_node}."_filter" }; 
         $_->{this_month_time} = $result->{ $_->{_node}."_month" }; 
         $_->{today_time} = $result->{ $_->{_node}."_today" }; 
      }
   }
   
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   
# Dect-Geräteliste erstellen
   $runNo = 0;
   foreach ( @{ $result->{dectUser} } ) {
      my $intern = $_->{Intern};
      my $id = $_->{Id};
      if ($intern) 
      {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo,                     $_->{Name} ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_intern",           $intern ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_alarmRingTone",    $_->{AlarmRingTone0}, "ringtone" ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_intRingTone",      $_->{IntRingTone}, "ringtone" ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_radio",            $_->{RadioRingID}, "radio" ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_custRingTone",     $_->{G722RingTone} ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_custRingToneName", $_->{G722RingToneName} ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$runNo."_imagePath",        $_->{ImagePath} ;

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->$intern->id",   $id ;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->$intern->userId", $runNo;
         
         $dectFonID{$id}{Intern} = $intern;
         $dectFonID{$id}{User} = $runNo;
      }
      $runNo++;
   }
   
# Handset der internen Nummer zuordnen
   foreach ( @{ $result->{handset} } ) {
      my $dectUserID = $_->{User};
      my $dectUser = $dectFonID{$dectUserID}{User};
      my $intern = $dectFonID{$dectUserID}{Intern};
      
      if ($dectUser) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$dectUser."_manufacturer", $_->{Manufacturer};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$dectUser."_model",        $_->{Model},         "model";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "dect".$dectUser."_fwVersion",    $_->{FWVersion};

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->$intern->brand", $_->{Manufacturer};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->$intern->model", $_->{Model},       "model";
      }
   }

# Analog Fons Name
   $runNo=1;
   foreach ( @{ $result->{fonPort} } ) {
      if ( $_->{Name} )
      {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fon".$runNo,           $_->{Name};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fon".$runNo."_out",    $_->{MSN};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fon".$runNo."_intern", $runNo;
      }
      $runNo++;
   }

# Internetradioliste erzeugen
   $runNo = 0;
   $rName = "radio00";
   foreach ( @{ $result->{radio} } ) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName,                 $_->{Name};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->radio->".$runNo, $_->{Name};
      $runNo++;
      $rName = sprintf ("radio%02d",$runNo);
   }
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->radioCount", $runNo;

# Create WLAN-List
   my %wlanList;
   #to keep compatibility with firmware <= v3.67
   if ( ref $result->{wlanList} eq 'ARRAY' ) {
      foreach ( @{ $result->{wlanList} } ) {
         my $mac = $_->{mac};
         $mac =~ s/:/_/g;
         $wlanList{$mac}{speed} .= $_->{speed};
         $wlanList{$mac}{speed_rx} .= $_->{speed_rx};
         #$wlanList{$mac}{speed_rx} = $result_lan->{$_->{_node}};
         $wlanList{$mac}{rssi} .= $_->{rssi};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->wlanDevice->".$mac."->speed", $_->{speed};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->wlanDevice->".$mac."->speed_rx", $wlanList{$mac}{speed_rx};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->wlanDevice->".$mac."->rssi", $_->{rssi};
      }
   }
   
# Create LanDevice list and delete inactive devices
   my %oldLanDevice;
   #collect current mac-readings (to delete the ones that are inactive or disappeared)
   foreach (keys %{ $hash->{READINGS} }) {
      $oldLanDevice{$_} = $hash->{READINGS}{$_}{VAL}     if $_ =~ /^mac_/ && defined $hash->{READINGS}{$_}{VAL};
   }
   %landevice = ();
   my $wlanCount = 0;
   my $gWlanCount = 0;
   if ( ref $result->{lanDevice} eq 'ARRAY' ) {
      foreach ( @{ $result->{lanDevice} } ) {
         my $dIp = $_->{ip};
         my $UID = $_->{UID};
         my $dName = $_->{name};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->landevice->$dIp", $dName;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->landevice->$UID", $dName;
         $landevice{$dIp}=$dName;
         $landevice{$UID}=$dName;
      # Create a reading if a landevice is connected
         if ( $_->{active} ) {
            my $mac = $_->{mac};
            $mac =~ s/:/_/g;
            if ( !$_->{ethernet} && $_->{wlan} ) {
               $dName .= " (";
               $dName .= "g"    if $_->{guest};
               $dName .= "WLAN";
               $dName .= ", " . $wlanList{$mac}{speed} . " / " . $wlanList{$mac}{speed_rx} . " Mbit/s, ". $wlanList{$mac}{rssi}
                      if defined $wlanList{$mac};
               $dName .= ")";
            }
            if ( $_->{ethernet_port} ) {
               $dName .= " (";
               $dName .= "g"         if $_->{guest};
               $dName .= "LAN" . $_->{ethernet_port};
               #$dName .= "LAN" . $result_lan->{$_->{_node}};
               $dName .= ", 1 Gbit/s"    if $_->{speed} eq "1000";
               $dName .= ", " . $_->{speed} . " Mbit/s"   if $_->{speed} ne "1000" && $_->{speed} ne "0";
               $dName .= ")";
            }
            my $rName = "mac_".$mac;
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, $dName;
            $wlanCount++      if $_->{wlan} ;
            $gWlanCount++      if $_->{wlan}  && $_->{guest} ;
            # Remove mac address from oldLanDevice-List
            delete $oldLanDevice{$rName}   if exists $oldLanDevice{$rName};
         }
      }
   }
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_wlanCount", $wlanCount);
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_guestWlanCount", $gWlanCount);

# Remove inactive or non existing mac-readings in two steps
   foreach ( keys %oldLanDevice ) {
      # set the mac readings to 'inactive' and delete at next readout
      if ( $oldLanDevice{$_} ne "inactive" ) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "inactive";
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "";
      }
   }

# WLANs
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};
# Dect
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_dect", $result->{box_dect}, "onoff";
# Music on Hold
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_moh", $result->{box_moh}, "mohtype";
# Power Rate
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_powerRate", $result->{box_powerRate};
# Box Features
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->is_double_wlan", $result->{is_double_wlan},  "01";
# Box model and firmware
   if ($result->{box_fwVersion}) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwVersion",   $result->{box_fwVersion};
   } else { # Ab Version 6.90
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwVersion",   $result->{box_fwVersion_neu};
   }
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwUpdate",    $result->{box_fwUpdate};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_tr064",       $result->{box_tr064},       "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_tr069",       $result->{box_tr069},       "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_stdDialPort", $result->{box_stdDialPort}, "dialport";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_ipExtern", $result->{box_ipExtern};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_connect", $result->{box_connect};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_cpuTemp", $result->{box_cpuTemp};
# GSM
#FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_modem", $result->{GSM_ModemPresent};
   if (defined $result->{GSM_NetworkState} && $result->{GSM_NetworkState} ne "0") {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_rssi", $result->{GSM_RSSI};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_state", $result->{GSM_NetworkState}, "gsmnetstate";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_technology", $result->{GSM_AcT}, "gsmact";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_internet", $result->{UMTS_enabled};
    }
   else {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_rssi", "";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_state", "";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_technology", "";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_internet", "";
   }
     
# Alarm clock
   $runNo = 1;
   foreach ( @{ $result->{alarmClock} } ) {
      next  if $_->{Name} eq "er";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "alarm".$runNo, $_->{Name};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "alarm".$runNo."_state", $_->{Active}, "onoff";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "alarm".$runNo."_time",  $_->{Time}, "altime";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "alarm".$runNo."_target", $_->{Number}, "alnumber";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "alarm".$runNo."_wdays", $_->{Weekdays}, "aldays";
      $runNo++;
   }

#Get TAM readings
   $runNo = 1;
   foreach ( @{ $result->{tam} } ) {
      $rName = "tam".$runNo;
      if ($_->{Display} eq "1")
      {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName,           $_->{Name};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_state",  $_->{Active}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_newMsg", $_->{NumNewMessages};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_oldMsg", $_->{NumOldMessages};
      }
# Löschen ausgeblendeter TAMs
      elsif (defined $hash->{READINGS}{$rName} )
      {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName,"";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_state", "";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_newMsg","";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_oldMsg","";
      }
      $runNo++;
   }

# user profiles
   $runNo = 1;
   $rName = "user01";
   if ( ref $result->{userProfil} eq 'ARRAY' ) {
      foreach ( @{ $result->{userProfil} } ) {
      # do not show data for unlimited, blocked or default access rights
         if ($_->{filter_profile_UID} !~ /^filtprof[134]$/ || defined $hash->{READINGS}{$rName} ) {
            if ( $_->{type} eq "1" && $_->{name} =~ /\(landev(.*)\)/ ) {
               my $UID = "landevice".$1;
               $_->{name} = $landevice{$UID};
            }
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName,                   $_->{name},            "deviceip";
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_thisMonthTime",  $_->{this_month_time}, "secondsintime";
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_todayTime",      $_->{today_time},      "secondsintime";
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_todaySeconds",   $_->{today_time};
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_type",           $_->{type},            "usertype";
         }
         $runNo++;
         $rName = sprintf ("user%02d",$runNo);
      }
   }

# user ticket (extension of online time)
   if ( ref $result->{userTicket} eq 'ARRAY' ) {
      $runNo=1;
      my $maxTickets = AttrVal( $name, "userTickets",  1 );
      $rName = "userTicket01";
      foreach ( @{ $result->{userTicket} } ) {
         last     if $runNo > $maxTickets;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, $_->{id};
         $runNo++;
         $rName = sprintf ("userTicket%02d",$runNo);
      }
   }

   # Diversity
   $runNo=1;
   $rName = "diversity1";
   foreach ( @{ $result->{diversity} } ) {
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName,          $_->{MSN};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_state", $_->{Active}, "onoff" ;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName."_dest",  $_->{Destination};
      $runNo++;
      $rName = "diversity".$runNo;
   }
   

# statistics
# attr global showInternalValues 0
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesReceivedHigh", $result->{TodayBytesReceivedHigh};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesReceivedLow", $result->{TodayBytesReceivedLow};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesSentHigh", $result->{TodayBytesSentHigh};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesSentLow", $result->{TodayBytesSentLow};
  
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   my $returnStr = join('|', @roReadings );

   FRITZBOX_Log $hash, 4, "Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 5, "Handover to main process (".length ($returnStr)."): ".$returnStr;
   return $name."|".encode_base64($returnStr,"");

} # End FRITZBOX_Readout_Run_Web

#######################################################################
sub FRITZBOX_Readout_Done($)
{
   my ($string) = @_;
   unless (defined $string)
   {
      Log 1, "Fatal Error: no parameter handed over";
      return;
   }

   my ($name,$string2) = split("\\|", $string, 2);
   my $hash = $defs{$name};
 
   FRITZBOX_Log $hash, 4, "Back at main process";

# delete the marker for RUNNING_PID process
   delete($hash->{helper}{READOUT_RUNNING_PID});

   $string2 = decode_base64($string2);
   FRITZBOX_Readout_Process ($hash, $string2);

}

#######################################################################
sub FRITZBOX_Readout_Process($$)
{
   my ($hash,$string) = @_;
 # Fatal Error: no hash parameter handed over
   unless (defined $hash) {
      Log 1, "Fatal Error: no hash parameter handed over";
      return;
   }
  
   my $name = $hash->{NAME};
   my (%values) = split("\\|", $string);
   FRITZBOX_Log $hash, 4, "Processing ". keys(%values)." readouts.";

   readingsBeginUpdate($hash);

   if ( defined $values{Error} ) {
      readingsBulkUpdate( $hash, "lastReadout", $values{Error} );
      readingsBulkUpdate( $hash, "state", $values{Error} );
      if (defined $values{"fhem->sidTime"}) {
         $hash->{fhem}{sidTime} = $values{"fhem->sidTime"};
            FRITZBOX_Log $hash, 4, "Reset SID";
      }
   }
   else {
   # Statistics
      if ( defined $values{".box_TodayBytesReceivedLow"} && defined $hash->{READINGS}{".box_TodayBytesReceivedLow"}) {
         my $valueHigh = $values{".box_TodayBytesReceivedHigh"} - $hash->{READINGS}{".box_TodayBytesReceivedHigh"}{VAL};
         my $valueLow = $values{".box_TodayBytesReceivedLow"} - $hash->{READINGS}{".box_TodayBytesReceivedLow"}{VAL};
      # Consider reset of day counter
         if ($valueHigh < 0 || $valueHigh == 0 && $valueLow < 0) {
            $valueLow = $values{".box_TodayBytesReceivedLow"};
            $valueHigh = $values{".box_TodayBytesReceivedHigh"};
         }
         $valueHigh *= 2**22;
         $valueLow /= 2**10;
         my $time = time()-time_str2num($hash->{READINGS}{".box_TodayBytesReceivedLow"}{TIME});
         $values{ "box_rateDown" } = sprintf ("%.3f", ($valueHigh+$valueLow) / $time ); 
      }
      if ( defined $values{".box_TodayBytesSentLow"} && defined $hash->{READINGS}{".box_TodayBytesSentLow"} ) {
         my $valueHigh = $values{".box_TodayBytesSentHigh"} - $hash->{READINGS}{".box_TodayBytesSentHigh"}{VAL};
         my $valueLow = $values{".box_TodayBytesSentLow"} - $hash->{READINGS}{".box_TodayBytesSentLow"}{VAL};
      # Consider reset of day counter
         if ($valueHigh < 0 || $valueHigh == 0 && $valueLow < 0) {
            $valueLow = $values{".box_TodayBytesSentLow"};
            $valueHigh = $values{".box_TodayBytesSentHigh"};
         }
         $valueHigh *= 2**22;
         $valueLow /= 2**10;
         my $time = time()-time_str2num($hash->{READINGS}{".box_TodayBytesSentLow"}{TIME});
         $values{ "box_rateUp" } = sprintf ("%.3f", ($valueHigh+$valueLow) / $time ); 
      }

   # Fill all handed over readings
      my $x = 0;
      while (my ($rName, $rValue) = each(%values) ) {
      #hash values
         if ($rName =~ /->/) {
         # 4 levels
            my ($rName1,$rName2,$rName3,$rName4) = split /->/, $rName;
         # 4th level (Internal Value)
            if ($rName1 ne "" && defined $rName4) {
               $hash->{$rName1}{$rName2}{$rName3}{$rName4} = $rValue;
            }
         # 3rd level (Internal Value)
            elsif ($rName1 ne "" && defined $rName3) {
               $hash->{$rName1}{$rName2}{$rName3} = $rValue;
            }
         # 1st level (Internal Value)
            elsif ($rName1 eq "") {
               $hash->{$rName2} = $rValue;
            }
         # 2nd levels
            else {
               $hash->{$rName1}{$rName2} = $rValue;
            }
         }
         elsif ($rName eq "box_fwVersion" && defined $values{box_fwUpdate}) {
            $rValue .= " (old)" if $values{box_fwUpdate} eq "1";
         }
         elsif ($rName eq "box_model") {
            $hash->{MODEL} = $rValue;
            $rValue .= " [".$values{box_oem}."]" if $values{box_oem};
         }
         if ($rName !~ /->|box_fwUpdate|box_oem|readoutTime/) {
            if ($rValue ne "") {
               readingsBulkUpdate( $hash, $rName, $rValue );
               FRITZBOX_Log $hash, 5, "SET $rName = '$rValue'";
            }
            elsif ( exists $hash->{READINGS}{$rName} ) {  
               delete $hash->{READINGS}{$rName};
               FRITZBOX_Log $hash, 5, "Delete reading $rName.";
            }
            else  {
               FRITZBOX_Log $hash, 5, "Ignore reading $rName.";
            }
         }
      }

   # Create state with wlan states
      if ( defined $values{"box_wlan_2.4GHz"} ) {
         my $newState = "WLAN: ";
         if ( $values{"box_wlan_2.4GHz"} eq "on" ) {
            $newState .= "on";
         } 
         elsif ( $values{box_wlan_5GHz} ) {
            if ( $values{box_wlan_5GHz} eq "on") {
               $newState .= "on";
            } else {
               $newState .= "off";
            }
         } 
         else {
            $newState .= "off";
         }
         $newState .=" gWLAN: ".$values{box_guestWlan} ;
         $newState .=" (Remain: ".$values{box_guestWlanRemain}." min)"
            if $values{box_guestWlan} eq "on" && $values{box_guestWlanRemain} > 0;
         readingsBulkUpdate( $hash, "state", $newState);
         FRITZBOX_Log $hash, 5, "SET state = '$newState'";
      }

   # adapt TR064-Mode
      if ( defined $values{box_tr064} ) {
         if ( $values{box_tr064} eq "off" && defined $hash->{SECPORT} ) {
               FRITZBOX_Log $hash, 3, "TR-064 is switched off";
            delete $hash->{SECPORT};
         }
         elsif ( $values{box_tr064} eq "on" && not defined $hash->{SECPORT} ) {
               FRITZBOX_Log $hash, 3, "TR-064 is switched on";
            my $tr064Port = FRITZBOX_TR064_Init ($hash, $hash->{HOST});
            $hash->{SECPORT} = $tr064Port    if $tr064Port;
         }
      }

      my $msg = keys( %values )." values captured in ".$values{readoutTime}." s";
      readingsBulkUpdate( $hash, "lastReadout", $msg );
      FRITZBOX_Log $hash, 4, $msg;
   }

   readingsEndUpdate( $hash, 1 );
}

#######################################################################
sub FRITZBOX_Readout_Aborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{READOUT_RUNNING_PID});
  my $msg = "Error: Timeout when reading Fritz!Box data.";
  readingsSingleUpdate($hash, "lastReadout", $msg, 1);
  readingsSingleUpdate($hash, "state", $msg, 1);
  FRITZBOX_Log $hash, 1, $msg;
}

#######################################################################
sub FRITZBOX_Readout_Format($$$)
{
   my ($hash, $format, $readout) = @_;

   $readout = ""        unless defined $readout;

   return $readout       unless defined( $format ) && $format ne "";
# return $readout       unless $readout ne "" && $format ne "" ; #Funktioniert nicht bei $format "01"

   if ($format eq "01" && $readout ne "1") {
      $readout = "0";
   }
   
   return $readout       unless $readout ne "";
   
   if ($format eq "aldays") {
      if ($readout eq "0") {
         $readout = "once";
      }
      elsif ($readout >= 127) {
         $readout = "daily";
      }
      else {
         my $bitStr = $readout;
         $readout = "";
         foreach (sort {$a <=> $b} keys %alarmDays) {
            $readout .= (($bitStr & $_) == $_) ? $alarmDays{$_}." " : "";
         }
         chop $readout;
      }
   } 
   elsif ($format eq "alnumber") {
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
   } 
   elsif ($format eq "altime") {
      $readout =~ s/(\d\d)(\d\d)/$1:$2/;
   } 
   elsif ($format eq "deviceip") {
      $readout = $landevice{$readout}." ($readout)"
         if defined $landevice{$readout};
   } 
   elsif ($format eq "dialport") {
      $readout = $dialPort{$readout}   if $dialPort{$readout};
   } 
   elsif ($format eq "gsmnetstate") {
      $readout = $gsmNetworkState{$readout} if defined $gsmNetworkState{$readout};
   } 
   elsif ($format eq "gsmact") {
      $readout = $gsmTechnology{$readout} if defined $gsmTechnology{$readout};
   } 
   elsif ($format eq "model") {
      $readout = $fonModel{$readout} if defined $fonModel{$readout};
   } 
   elsif ($format eq "mohtype") {
      $readout = $mohtype{$readout} if defined $mohtype{$readout};
   } 
   elsif ($format eq "nounderline") {
      $readout =~ s/_/ /g;
   } 
   elsif ($format eq "onoff") {
      $readout =~ s/er//;
      $readout =~ s/no-emu//;
      $readout =~ s/0/off/;
      $readout =~ s/1/on/;
   } 
   elsif ($format eq "radio") {
      if (defined $hash->{fhem}{radio}{$readout}) {
         $readout = $hash->{fhem}{radio}{$readout};
      }
      else {
         $readout .= " (unknown)";
      }
   } 
   elsif ($format eq "ringtone") {
      $readout = $ringTone{$readout}   if $ringTone{$readout};
   } 
   elsif ($format eq "secondsintime") {
      if ($readout < 243600) {
         $readout = sprintf "%d:%02d", int $readout/3600, int( ($readout %3600) / 60);
      }
      else {
         $readout = sprintf "%dd %d:%02d", int $readout/24/3600, int ($readout%24*3600)/3600, int( ($readout %3600) / 60);
      }
   } 
   elsif ($format eq "usertype") {
      $readout = $userType{$readout};
   }

   return $readout;
}

#######################################################################
sub FRITZBOX_Readout_Add_Reading ($$$$@)
{
   my ($hash, $roReadings, $rName, $rValue, $rFormat) = @_;
   $rFormat = "" unless defined $rFormat;
   $rValue = FRITZBOX_Readout_Format ($hash, $rFormat, $rValue);
   push @{$roReadings}, $rName."|" . $rValue;
   FRITZBOX_Log $hash, 5, "$rName: $rValue";
}

##############################################################################################################################################
sub FRITZBOX_Set_Cmd_Start($)
{
  my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex( $timerpara, "." );    # rechter punkt
   my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash = $defs{$name};
   my $cmdFunction;
   my $timeout;
   my $handover;
   
   return unless int @cmdBuffer;

 # kill old process if timeout + 10s is reached
   if ( exists( $hash->{helper}{CMD_RUNNING_PID}) && time()> $cmdBufferTimeout + 10 ) {
      FRITZBOX_Log $hash, 1, "Old command still running. Killing old command: ".$cmdBuffer[0];
      shift @cmdBuffer;
      BlockingKill( $hash->{helper}{CMD_RUNNING_PID} ); 
      # stop FHEM, giving FritzBox some time to free the memory 
      sleep 5     unless $hash->{REMOTE}==1; 
      delete $hash->{helper}{CMD_RUNNING_PID};
      return unless int @cmdBuffer;
   }
   
 # (re)start timer if command buffer is still filled
   if (int @cmdBuffer >1) {
      RemoveInternalTimer($hash->{helper}{TimerCmd});
      InternalTimer(gettimeofday()+1, "FRITZBOX_Set_Cmd_Start", $hash->{helper}{TimerCmd}, 1);
   }
   
# do not continue until running command has finished or is aborted
   return if exists $hash->{helper}{CMD_RUNNING_PID};

   my @val = split / /, $cmdBuffer[0];
   my $forceShell = (AttrVal( $name, "forceTelnetConnection",  0 ) == 1 || $hash->{REMOTE} == 0);
   
# Preparing SET Call
   if ($val[0] eq "call") {
      shift @val;
      $timeout = 60;
      $timeout = $val[2]         if defined $val[2] && $val[2] =~/^\d+$/; 
      $timeout += 30;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Call_Run_Web";
      $cmdFunction = "FRITZBOX_Call_Run_Shell" if $forceShell;
   }
# Preparing SET guestWLAN
   elsif ($val[0] eq "guestwlan") {
      shift @val;
      $timeout = 20;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_GuestWlan_Run_Web";
      $cmdFunction = "FRITZBOX_GuestWlan_Run_Shell" if $forceShell;
   }
# Preparing SET RING
   elsif ($val[0] eq "ring") {
      shift @val;
      $timeout = 20;
      if ($val[2]) {
         $timeout = $val[2] if $val[2] =~/^\d+$/; 
      }
      $timeout += 30;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Ring_Run_Web";
      $cmdFunction = "FRITZBOX_Ring_Run_Shell" if $forceShell;
   }
# Preparing SET WLAN
   elsif ($val[0] eq "wlan") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Wlan_Run_Web";
      $cmdFunction = "FRITZBOX_Wlan_Run_Shell" if $forceShell;
   }
# Preparing SET WLAN2.4
   elsif ( $val[0] =~ /^wlan(2\.4|5)$/ ) {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Wlan_Run_Web";
   }
# No valid set operation
   else {
      my $msg = "Unknown command '".join( " ", @val )."'";
      FRITZBOX_Log $hash, 1, $msg;
      return $msg;
   }

# Starting new command
   FRITZBOX_Log $hash, 4, "Fork process $cmdFunction";
   $hash->{helper}{CMD_RUNNING_PID} = BlockingCall($cmdFunction, $handover,
                                       "FRITZBOX_Set_Cmd_Done", $timeout,
                                       "FRITZBOX_Set_Cmd_Aborted", $hash);
   return undef;
} # end FRITZBOX_Set_Cmd_Start

#######################################################################
sub FRITZBOX_Set_Cmd_Done($)
{
   my ($string) = @_;
  unless (defined $string)
   {
      Log 1, "Fatal Error: no parameter handed over";
      return;
   }

   my ($name, $success, $result) = split("\\|", $string,3);
   my $hash = $defs{$name};

   FRITZBOX_Log $hash, 4, "Back at main process";
   
   shift (@cmdBuffer);
   delete($hash->{helper}{CMD_RUNNING_PID});

   if ( $success !~ /1|2/ )
   {
      FRITZBOX_Log $hash, 1, $result;
      FRITZBOX_Readout_Process ( $hash, "Error|".$result );
   }
   elsif ( $success == 1 )
   {
      FRITZBOX_Log $hash, 4, $result;
   }
   elsif  ($success == 2 )
   {
      $result = decode_base64($result);
      FRITZBOX_Readout_Process ( $hash, $result );
   }
}

#######################################################################
sub FRITZBOX_Set_Cmd_Aborted($)
{
  my ($hash) = @_;
  my $lastCmd = shift (@cmdBuffer);
  delete($hash->{helper}{CMD_RUNNING_PID});
  FRITZBOX_Log $hash, 1, "Timeout reached for: $lastCmd";
}

#######################################################################
sub FRITZBOX_Call_Run_Shell($) 
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   return "$name|0|Error: At least one parameter must be defined."
         unless int @val;

   my $result;
   my @cmdArray;
   my $duration = 60;
   my $extNo = $val[0];
   my %field;
   my $lastField;
   my $ttsLink;
 
 # Check if 1st parameter is a valid number
   return $name."|0|Error: Parameter '$extNo' not a valid phone number"
      unless $extNo =~ /^[\d\*\#+,]+$/;
   $extNo =~ s/#$//;
       
 # Check if 2nd parameter is the duration
   shift @val;
   if (int @val)
   {
      if ($val[0] =~ /^\d+$/ && int $val[0] > 0)
      {
         $duration = $val[0];
         FRITZBOX_Log $hash, 5, "Extracted call duration of $duration s.";
         shift @val;
      }
   }
   
# Extract text to say or play
   foreach (@val)
    {
      if ($_ =~ /^(say|play):/i)
      {
         $lastField = $1;
         $_ =~ s/^$1://;
      }
      $field{$lastField} .= $_." "
         if $lastField;
    }

# Create tts link to say as moh
   if ( $field{say} ) 
   {
      unless ($hash->{READINGS}{box_moh})
      {
         FRITZBOX_Log $hash, 2, "Cannot do Text2Speech because box has no music on hold";
      }
      else
      {
         chop $field{say};
         # http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT];
         $ttsLink = $ttsLinkTemplate;
         my $ttsText = substr $field{say},0,100;
         my $ttsLang = "de";
         if ($ttsText =~ /^\((en|es|fr|nl)\)/i )
         {
            $ttsLang = $1;
            $ttsText =~ s/^\($1\)\s*//i;
         }
         $ttsLink =~ s/\[SPRACHE\]/$ttsLang/;
         $ttsText = uri_escape($ttsText);
         $ttsLink =~ s/\[TEXT\]/$ttsText/;
         FRITZBOX_Log $hash, 5, "Created Text2Speech internet link: $ttsLink";
      }
   }

   if ($field{play})
   {
      unless ($hash->{READINGS}{box_moh})
      {
         FRITZBOX_Log $hash, 2, "Cannot play mp3 because box has no music on hold";
      }
      elsif ($ttsLink)
      {
         FRITZBOX_Log $hash, 3, "Ignore 'play:' because Text2Speech already defined.";
      }
      else
      {
         chop $field{play};
         $ttsLink = $field{play};
         FRITZBOX_Log $hash, 5, "Extracted MP3 ring tone: $ttsLink";
      }
   }
   
   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return "$name|0|$result" 
      if $result;

   @cmdArray = ();
   
# Creation fhemRadioStation for ttsLink
   if ($ttsLink) {
#Preparing 1st command array
      push @cmdArray, '[ -f "'.$mohUpload.'" ] && rm "'.$mohUpload.'"';
      push @cmdArray, '[ -f "'.$mohOld.'" ] && rm "'.$mohOld.'"';
      push @cmdArray, '[ -f "'.$mohNew.'" ] && rm "'.$mohNew.'"';
      push @cmdArray, 'wget -U Mozilla -O "'.$mohUpload.'" "'.$ttsLink.'"';
      push @cmdArray, '[ -f "'.$mohUpload.'" ] && echo 1 || echo 0';
      push @cmdArray, '[ -e /var/flash/fx_moh ] && echo 1 || echo 0';
# Execute 1st command array
      $result = FRITZBOX_Shell_Exec ( $hash, \@cmdArray );
      return "$name|0|Could not access '$ttsLink'"
         unless $result->[4] eq "1";
      return "$name|0|Could locate '/var/flash/fx_moh'"
         unless $result->[5] eq "1";

   #Prepare 2nd command array
      push @cmdArray, 'if [ ! -f "/var/tmp/ffmpeg_mp3.tables" ]; then playerd_tables; fi';
      push @cmdArray, 'ffmpegconv -i "'.$mohUpload.'" -o "'.$mohNew.'" --limit 32 --type 6';
      push @cmdArray, '[ -f "'.$mohNew.'" ] && echo 1 || echo 0';
   # Execute 2nd command array
      $result = FRITZBOX_Shell_Exec ( $hash, \@cmdArray );
      return "Could not convert '$ttsLink'"
         unless $result->[2] eq "1";

   #Execute 3rd command array
      FRITZBOX_Shell_Exec( $hash, \@cmdArray );

   #Prepare 4th command array
      push @cmdArray, 'cat /var/flash/fx_moh >"'.$mohOld.'"';
      push @cmdArray, 'cat "'.$mohNew.'" >/var/flash/fx_moh';
      push @cmdArray, 'killall -sigusr1 telefon';
      push @cmdArray, 'rm "'.$mohUpload.'"';
      push @cmdArray, 'rm "'.$mohNew.'"';
   # Execute 4th command array
      FRITZBOX_Shell_Exec ( $hash, \@cmdArray );
   }
   
#Preparing 4th command array
# switch to (dial port 1-3) to avoid ringing of internal phone
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 1 );
   # push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort 60";
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort $ringWithIntern"
         if $ringWithIntern =~ /^([1-3])$/ ;
   
   FRITZBOX_Log $hash, 4, "Call $extNo for $duration seconds";
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial ".$extNo."#";
   push @cmdArray, "sleep ".($duration+1); # 1s added because it takes sometime until it starts ringing
   push @cmdArray, "ctlmgr_ctl w telcfg command/Hangup $ringWithIntern";
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort 50";
   if ($ttsLink)
   {
      push @cmdArray, 'cat "'.$mohOld.'" >/var/flash/fx_moh';
      push @cmdArray, 'killall -sigusr1 telefon';
      push @cmdArray, 'rm "'.$mohOld.'"';
   }
      
# Execute command array
   FRITZBOX_Shell_Exec( $hash, \@cmdArray );

   FRITZBOX_Telnet_CloseCon( $hash );

   return $name."|1|Calling done";

} # End FRITZBOX_Call_Run_Shell

#######################################################################
sub FRITZBOX_Call_Run_Web($) 
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   return "$name|0|Error: At least one parameter must be defined."
         unless int @val;

   my $result;
   my @shellCmdArray;
   my @webCmdArray;
   my @tr064CmdArray;
   my $duration = 60;
   my $extNo = $val[0];
   my %field;
   my $lastField;
   my $ttsLink;
 
 # Check if 1st parameter is a valid number
   return $name."|0|Error: Parameter '$extNo' not a valid phone number"
      unless $extNo =~ /^[\d\*\#+,]+$/;
   $extNo =~ s/#$//;
       
 # Check if 2nd parameter is the duration
   shift @val;
   if (int @val) {
      if ($val[0] =~ /^\d+$/ && int $val[0] > 0) {
         $duration = $val[0];
         FRITZBOX_Log $hash, 5, "Extracted call duration of $duration s.";
         shift @val;
      }
   }
   
# Extract text to say or play
   foreach (@val) {
      if ($_ =~ /^(say|play):/i)  {
         $lastField = $1;
         $_ =~ s/^$1://;
      }
      $field{$lastField} .= $_." "    if $lastField;
    }

# Create tts link to say as moh
   if ( $field{say} ) {
      unless ($hash->{READINGS}{box_moh}) {
         FRITZBOX_Log $hash, 2, "Cannot do Text2Speech because box has no music on hold";
      }
      else {
         chop $field{say};
         # http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT];
         $ttsLink = $ttsLinkTemplate;
         my $ttsText = substr $field{say},0,100;
         my $ttsLang = "de";
         if ($ttsText =~ /^\((en|es|fr|nl)\)/i ) {
            $ttsLang = $1;
            $ttsText =~ s/^\($1\)\s*//i;
         }
         $ttsLink =~ s/\[SPRACHE\]/$ttsLang/;
         $ttsText = uri_escape($ttsText);
         $ttsLink =~ s/\[TEXT\]/$ttsText/;
         FRITZBOX_Log $hash, 5, "Created Text2Speech internet link: $ttsLink";
      }
   }

   if ($field{play}) {
      unless ($hash->{READINGS}{box_moh}) {
         FRITZBOX_Log $hash, 2, "Cannot play mp3 because box has no music on hold";
      }
      elsif ($ttsLink) {
         FRITZBOX_Log $hash, 3, "Ignore 'play:' because Text2Speech already defined.";
      }
      else {
         chop $field{play};
         $ttsLink = $field{play};
         FRITZBOX_Log $hash, 5, "Extracted MP3 ring tone: $ttsLink";
      }
   }
   
   if ( $hash->{TELNET} == 1 && $ttsLink ) {
      $result = FRITZBOX_Telnet_OpenCon( $hash );
      return "$name|0|$result"    if $result;

      @shellCmdArray = ();
      
   # Creation MOH for ttsLink
      if ($ttsLink) {
   #Preparing 1st command array
         push @shellCmdArray, '[ -f "'.$mohUpload.'" ] && rm "'.$mohUpload.'"';
         push @shellCmdArray, '[ -f "'.$mohOld.'" ] && rm "'.$mohOld.'"';
         push @shellCmdArray, '[ -f "'.$mohNew.'" ] && rm "'.$mohNew.'"';
         push @shellCmdArray, 'wget -U Mozilla -O "'.$mohUpload.'" "'.$ttsLink.'"';
         push @shellCmdArray, '[ -f "'.$mohUpload.'" ] && echo 1 || echo 0';
         push @shellCmdArray, '[ -e /var/flash/fx_moh ] && echo 1 || echo 0';
   # Execute 1st command array
         $result = FRITZBOX_Shell_Exec ( $hash, \@shellCmdArray );
         return "$name|0|Could not access '$ttsLink'"
            unless $result->[4] eq "1";
         return "$name|0|Could locate '/var/flash/fx_moh'"
            unless $result->[5] eq "1";

      #Prepare 2nd command array
         push @shellCmdArray, 'if [ ! -f "/var/tmp/ffmpeg_mp3.tables" ]; then playerd_tables; fi';
         push @shellCmdArray, 'ffmpegconv -i "'.$mohUpload.'" -o "'.$mohNew.'" --limit 32 --type 6';
         push @shellCmdArray, '[ -f "'.$mohNew.'" ] && echo 1 || echo 0';
      # Execute 2nd command array
         $result = FRITZBOX_Shell_Exec ( $hash, \@shellCmdArray );
         return "Could not convert '$ttsLink'"
            unless $result->[2] eq "1";

      #Execute 3rd command array
         FRITZBOX_Shell_Exec( $hash, \@shellCmdArray );

      #Prepare 4th command array
         push @shellCmdArray, 'cat /var/flash/fx_moh >"'.$mohOld.'"';
         push @shellCmdArray, 'cat "'.$mohNew.'" >/var/flash/fx_moh';
         push @shellCmdArray, 'killall -sigusr1 telefon';
         push @shellCmdArray, 'rm "'.$mohUpload.'"';
         push @shellCmdArray, 'rm "'.$mohNew.'"';
      # Execute 4th command array
         FRITZBOX_Shell_Exec ( $hash, \@shellCmdArray );
      }
   }
   elsif ( $hash->{TELNET} != 1 && $ttsLink ) {
      FRITZBOX_Log $hash, 3, "Your Fritz!OS version has limited interfaces. Parameter 'play:' and 'say:' ignored.";
   }

# Preparing 4th command array to switch to (dial port 1-3) to avoid ringing of internal phone
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 1 );
   if ($ringWithIntern =~ /^([1-3])$/ && $hash->{WEBCM} == 1 ) {
      push @webCmdArray, "telcfg:settings/DialPort" => $ringWithIntern;
      $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );
   }
  
#Preparing 5th command array to ring
      FRITZBOX_Log $hash, 4, "Call $extNo for $duration seconds";
   if ( $hash->{WEBCM} == 1 ) { # ring with webcm
      push @webCmdArray, "telcfg:command/Dial" => $extNo."#";
      $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );
   }
   elsif ($hash->{SECPORT}) { #or ring with TR-064
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", $extNo."#"];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }
   else {
      FRITZBOX_Log $hash, 3, "Your Fritz!OS version has limited interfaces. You cannot use call.";
   }
   
   sleep $duration; #+1; # 1s added because it takes sometime until it starts ringing
   
#Preparing 5th and 6th command array to stop ringing and reset dial port
   if ( $hash->{WEBCM} == 1 ) { # hangup with webcm
      push (@webCmdArray, "telcfg:command/Hangup" => "")      unless $hash->{SECPORT};
      push @webCmdArray, "telcfg:settings/DialPort" => 50;
      $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );
   }
   elsif ($hash->{SECPORT}) { #or hangup with TR-064
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialHangup"];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray )   if $hash->{SECPORT};
   }
   
#Preparing 7th command array to reset everything
   if ( $hash->{TELNET} == 1 && $ttsLink ) {
      push @shellCmdArray, 'cat "'.$mohOld.'" >/var/flash/fx_moh';
      push @shellCmdArray, 'killall -sigusr1 telefon';
      push @shellCmdArray, 'rm "'.$mohOld.'"';
      
   # Execute command array
      FRITZBOX_Shell_Exec( $hash, \@shellCmdArray );

      FRITZBOX_Telnet_CloseCon( $hash );
   }

   return $name."|1|Calling done";

} # End FRITZBOX_Call_Run_Web

#######################################################################
sub FRITZBOX_GuestWlan_Run_Shell($)
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @readoutCmdArray;
   my @roReadings;
   my $startTime = time();
   
   my $state = $val[0];
   $state =~ s/on/1/;
   $state =~ s/off/0/;
 
   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return "$name|0|$result" 
      if $result;

   my $returnStr;

   $result = FRITZBOX_Shell_Exec $hash, "[ -n `ctlmgr_ctl r wlan settings/guest_pskvalue` ] && echo 1 || echo 0";
   return "$name|0|Error: No password defined for guest WLAN."
      unless $result;

# Set WLAN on if guestWLAN on
   push @readoutCmdArray, [ "", "ctlmgr_ctl w wlan settings/wlan_enable 1"]
      if $state == 1;
# Set guestWLAN
   push @readoutCmdArray, [ "", "ctlmgr_ctl w wlan settings/guest_ap_enabled $state"];
# Read WLAN
   push @readoutCmdArray, [ "box_wlan_2.4GHz", "ctlmgr_ctl r wlan settings/ap_enabled", "onoff" ];
# Read 2nd WLAN
   push @readoutCmdArray, [ "box_wlan_5GHz", "ctlmgr_ctl r wlan settings/ap_enabled_scnd", "onoff" ];
# Read Gäste WLAN
   push @readoutCmdArray, [ "box_guestWlan", "ctlmgr_ctl r wlan settings/guest_ap_enabled", "onoff" ];
   push @readoutCmdArray, [ "box_guestWlanRemain", "ctlmgr_ctl r wlan settings/guest_time_remain", ];

# Execute commands
   FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings);

   FRITZBOX_Telnet_CloseCon ( $hash );

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   $returnStr .= join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_GuestWlan_Run_Shell

#######################################################################
sub FRITZBOX_GuestWlan_Run_Web($)
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();
   
   my $state = $val[0];
   $state =~ s/on/1/;
   $state =~ s/off/0/;
 
   # $result = FRITZBOX_Shell_Exec $hash, "[ -n `ctlmgr_ctl r wlan settings/guest_pskvalue` ] && echo 1 || echo 0";
   # return "$name|0|Error: No password defined for guest WLAN."
      # unless $result;


# Set guestWLAN, if necessary set also WLAN
   if ( $hash->{WEBCM}==1 ) { #webcm
      push @webCmdArray, "wlan:settings/wlan_enable" => "1"    if $state == 1;
      # push @webCmdArray, "active" => "on";
      # FRITZBOX_Web_CmdPost ($hash, \@webCmdArray, '/wlan/wlan_settings.lua');
      push @webCmdArray, "wlan:settings/guest_ap_enabled" => $state;
      $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );
   }
   elsif ( $hash->{SECPORT} ) { #TR-064
      if ($state == 1) { # WLAN on when Guest WLAN on
         push @tr064CmdArray, ["WLANConfiguration:2", "wlanconfig2", "SetEnable", "NewEnable", "1"]
                  if $hash->{fhem}->{is_double_wlan} == 1;
         push @tr064CmdArray, ["WLANConfiguration:1", "wlanconfig1", "SetEnable", "NewEnable", "1"];
      }
      my $gWlanNo = 2;
      $gWlanNo = 3 
         if $hash->{fhem}->{is_double_wlan} == 1;
      push @tr064CmdArray, ["WLANConfiguration:".$gWlanNo, "wlanconfig".$gWlanNo, "SetEnable", "NewEnable", $state];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }
   else { #no API
      FRITZBOX_Log $hash, 2, "Error: No API available to switch WLAN.";
   }

   # push @webCmdArray, "autoupdate" => "on";
   # push @webCmdArray, "activate_guest_access" => $val[0];
   # FRITZBOX_Web_CmdPost ($hash, \@webCmdArray, '/wlan/guest_access.lua');
#POSTDATA=autoupdate=on&activate_guest_access=on&guest_ssid=Gast-WLAN&sec_mode=3&wpa_key=Baby%2412sitter&push_service=on&group_access=on&down_time_activ=on&down_time_value=240&disconnect_guest_access=on&apply=
   
# Read WLAN-Status
   my $queryStr = "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
   $queryStr .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
   $queryStr .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # Gäste WLAN
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_GuestWlan_Run_Web

#######################################################################
sub FRITZBOX_Wlan_Run_Shell($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @readoutCmdArray;
   my @roReadings;
   my $startTime = time();
   
   my $state = $val[0];
   $state =~ s/on/1/;
   $state =~ s/off/0/;
   
   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return "$name|0|$result" 
      if $result;

   my $returnStr;

# Set WLAN
   push @readoutCmdArray, [ "", "ctlmgr_ctl w wlan settings/wlan_enable $state"];
# Read WLAN
   push @readoutCmdArray, [ "box_wlan_2.4GHz", "ctlmgr_ctl r wlan settings/ap_enabled", "onoff" ];
# Read 2nd WLAN
   push @readoutCmdArray, [ "box_wlan_5GHz", "ctlmgr_ctl r wlan settings/ap_enabled_scnd", "onoff" ];
# Read Gäste WLAN
   push @readoutCmdArray, [ "box_guestWlan", "ctlmgr_ctl r wlan settings/guest_ap_enabled", "onoff" ];
   push @readoutCmdArray, [ "box_guestWlanRemain", "ctlmgr_ctl r wlan settings/guest_time_remain", ];

# Execute commands
   FRITZBOX_Shell_Query( $hash, \@readoutCmdArray, \@roReadings);

   FRITZBOX_Telnet_CloseCon ( $hash );

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   $returnStr .= join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_Wlan_Run_Shell

#######################################################################
sub FRITZBOX_Wlan_Run_Web($) 
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();
   
   my $state = $val[0];
   $state =~ s/on/1/;
   $state =~ s/off/0/;
 
# Set WLAN
   if ($hash->{WEBCM}) { #webcm
      push @webCmdArray, "wlan:settings/wlan_enable" => $state         if $cmd eq "wlan";
      push @webCmdArray, "wlan:settings/ap_enabled" => $state          if $cmd eq "wlan2.4";
      push @webCmdArray, "wlan:settings/ap_enabled_scnd" => $state     if $cmd eq "wlan5";
      FRITZBOX_Web_CmdPost ($hash, \@webCmdArray);
      # push @webCmdArray, "active" => "on" if $val[0] eq "on";
      # FRITZBOX_Web_CmdPost ($hash, \@webCmdArray, '/wlan/wlan_settings.lua');
   }
   elsif ($hash->{SECPORT}) { #TR-064
      push @tr064CmdArray, ["WLANConfiguration:2", "wlanconfig2", "SetEnable", "NewEnable", $state]
               if $hash->{fhem}->{is_double_wlan} == 1 && $cmd ne "wlan2.4";
      push @tr064CmdArray, ["WLANConfiguration:1", "wlanconfig1", "SetEnable", "NewEnable", $state]
               if $cmd =~ /^(wlan|wlan2\.4)$/;
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }
   else { #no API
      FRITZBOX_Log $hash, 2, "Error: No API available to switch WLAN.";
   }
   
# Read WLAN-Status
   my $queryStr = "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
   $queryStr .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
   $queryStr .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # Gäste WLAN
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_Wlan_Run_Web
   
#######################################################################
sub FRITZBOX_Ring_Run_Shell($)
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
   my $fhemRadioStation;
 
 # Check if 1st parameter are comma separated numbers
   return $name."|0|Error: Parameter '$intNo' not a number (only commas (,) are allowed to separate numbers)"
      unless $intNo =~ /^[\d,]+$/;
   $intNo =~ s/#$//;
  
# Create a hash for the DECT devices whose ring tone (or radio station) can be changed
   foreach ( split( /,/, $intNo ) ) {
      if (defined $hash->{fhem}{$_}{brand} && "AVM" eq $hash->{fhem}{$_}{brand}) {
         FRITZBOX_Log $hash, 5, "Internal number $_ seems to be a Fritz!Fon.";
         push @FritzFons, $_ - 609;
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
      if ($val[0] !~ /^(msg|show|say|play):/i)
      {
         $ringTone = $val[0];
         $ringTone = $ringToneNumber{lc $val[0]};
         return $name."|0|Error: Ring tone '".$val[0]."' not valid"
            unless defined $ringTone;
         FRITZBOX_Log $hash, 5, "Ring tone $ringTone will be used.";
         shift @val;
      }
   }

# Extract text to say, play or show
   foreach (@val)
    {
      if ($_ =~ /^(show|msg|say|play):/i)
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

# Determine number of Internet Radio to play mp3 or say tts
   if ( $field{say} || $field{play} ) {
      foreach (keys %{$hash->{fhem}{radio}})
      {
         if ($hash->{fhem}{radio}{$_} eq "FHEM")
         {
            $fhemRadioStation = $_;
            last;
         }
      }
      if ( not defined $fhemRadioStation && $hash->{fhem}{radioCount} )
      {
         $fhemRadioStation = $hash->{fhem}{radioCount}-1;
      }
   }

# Create tts link to play as internet radio
   if ( $field{say} ) 
   {
      if ($fhemRadioStation)
      {
         $ringTone = 33;
         chop $field{say};
         # http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT];
         $ttsLink = $ttsLinkTemplate;
         my $ttsText = substr $field{say},0,100;
         my $ttsLang = "de";
         if ($ttsText =~ /^\((en|es|fr|nl)\)/i )
         {
            $ttsLang = $1;
            $ttsText =~ s/^\($1\)\s*//i;
         }
         $ttsLink =~ s/\[SPRACHE\]/$ttsLang/;
         $ttsText = uri_escape($ttsText);
         $ttsLink =~ s/\[TEXT\]/$ttsText/;
         FRITZBOX_Log $hash, 5, "Created Text2Speech internet link: $ttsLink";
      }
      else
      {
         FRITZBOX_Log $hash, 2, "Cannot do Text2Speech because box has no internet radio";
      }
   }

   if ($field{play})
   {
      unless ($fhemRadioStation)
      {
        FRITZBOX_Log $hash, 2, "Cannot play mp3 because box has no internet radio";
      }
      elsif ($ttsLink)
      {
         FRITZBOX_Log $hash, 3, "Ignore 'play:' because Text2Speech already defined.";
      }
      else
      {
         $ringTone = 33;
         chop $field{play};
         $ttsLink = $field{play};
         FRITZBOX_Log $hash, 5, "Extracted MP3 ring tone: $ttsLink";
      }
   }
   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return "$name|0|$result" 
      if $result;

#Preparing 1st command array
   @cmdArray = ();
   
# Creation fhemRadioStation for ttsLink
   if (int (@FritzFons) == 0 && $ttsLink)
   {
      FRITZBOX_Log $hash, 3, "No Fritz!Fon identified, parameter 'say:' will be ignored."
   }
   elsif (int (@FritzFons) && $ttsLink && $hash->{fhem}{radio}{$fhemRadioStation} ne "FHEM")
   {
      FRITZBOX_Log $hash, 3, "Create new internet radio station $fhemRadioStation: 'FHEM' for ringing with text-to-speech";
      push @cmdArray, "ctlmgr_ctl w configd settings/WEBRADIO".$fhemRadioStation."/Name FHEM";
      push @cmdArray, "ctlmgr_ctl w configd settings/WEBRADIO".$fhemRadioStation."/Bitmap 1023";
   #Execute command array
      FRITZBOX_Shell_Exec( $hash, \@cmdArray )
   }
   
#Preparing 2nd command array
# Change ring tone of Fritz!Fons
   if ($ringTone)
   {
      FRITZBOX_Log $hash, 3, "No Fritz!Fon identified, ring tone will be ignored."
         unless @FritzFons;
      foreach (@FritzFons)
      {
         push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User$_/IntRingTone";
         push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User$_/IntRingTone $ringTone";
         FRITZBOX_Log $hash, 4, "Change temporarily internal ring tone of Fritz!Fon DECT $_ to $ringTone";
         if ($ttsLink)
         {
            push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User$_/RadioRingID";
            push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User$_/RadioRingID ".$fhemRadioStation;
            FRITZBOX_Log $hash, 4, "Change temporarily radio station of Fritz!Fon DECT $_ to $fhemRadioStation (FHEM)";
         }
      }
   }

# uses name of port 0-3 (dial port 1-4) to show messages on ringing phone
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 0 );
   if ( $ringWithIntern =~ /^([1-3])$/ )
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/MSN/Port".($ringWithIntern-1)."/Name";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$msg'";
      FRITZBOX_Log $hash, 4, "Change temporarily name of calling number $ringWithIntern to '$msg'";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort $ringWithIntern"
   } 
   elsif ($field{show})
   {
      FRITZBOX_Log $hash, 3, "Parameter 'show:' ignored because attribute 'ringWithIntern' not defined."
   }
   
# Set tts-Message
   push @cmdArray, 'ctlmgr_ctl w configd settings/WEBRADIO'.$fhemRadioStation.'/URL "'.$ttsLink.'"'
      if $ttsLink;

#Execute command array
   $result = FRITZBOX_Shell_Exec( $hash, \@cmdArray )
      if int( @cmdArray ) > 0;

   $intNo =~ s/,/#/g;
   
#Preparing 3rd command array to ring and reset everything
   FRITZBOX_Log $hash, 4, "Ringing $intNo for $duration seconds";
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo."#";
   push @cmdArray, "sleep ".($duration+1); # 1s added because it takes sometime until it starts ringing
   push @cmdArray, "ctlmgr_ctl w telcfg command/Hangup **".$intNo;
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort 50"
      if $ringWithIntern != 0 ;
# Reset internal ring tones for the Fritz!Fons
   if ($ringTone)
   {
      for (0 .. $#FritzFons)
      {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$FritzFons[$_]."/IntRingTone ".$result->[2*$_];
      # Reset internet station for the Fritz!Fons
         if ($ttsLink)
         {
            push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$FritzFons[$_]."/RadioRingID ".$result->[2*(int(@FritzFons)+$_)];
         }
      }
   }
# Reset name of calling number
   if ($ringWithIntern =~ /^([1-2])$/)
   {
      if ($ttsLink) {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[4*int(@FritzFons)]."'";
         push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo;
         push @cmdArray, "ctlmgr_ctl w telcfg command/Hangup **".$intNo;
      } elsif ($ringTone) {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[2*int(@FritzFons)]."'";
      } else {
         push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[0]."'";
      }
   }
   
# Execute command array
   FRITZBOX_Shell_Exec( $hash, \@cmdArray );

   FRITZBOX_Telnet_CloseCon( $hash );

   return $name."|1|Ringing done";
} # End FRITZBOX_Ring_Run_Shell

#######################################################################
sub FRITZBOX_Ring_Run_Web($) 
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   return "$name|0|Error: At least one parameter must be defined."
         unless int @val;

   my $result;
   my @tr064Result;
   my $curCallerName;
   my @webCmdArray;
   my @getCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $duration = -1;
   my $intNo = $val[0];
   my @FritzFons;
   my $ringTone;
   my %field;
   my $lastField;
   my $ttsLink;
   my $fhemRadioStation;
   my $startValue;
   my $startTime = time();
   my $useGuiHack = AttrVal( $name, "useGuiHack", 0 );
 
 # Check if 1st parameter are comma separated numbers
   return $name."|0|Error (set ring): Parameter '$intNo' not a number (only commas (,) are allowed to separate phone numbers)"
      unless $intNo =~ /^[\d,]+$/;
   $intNo =~ s/#$//;
  
# Create a hash for the DECT devices whose ring tone (or radio station) can be changed
   foreach ( split( /,/, $intNo ) ) {
      if (defined $hash->{fhem}{$_}{brand} && "AVM" eq $hash->{fhem}{$_}{brand}) {
         my $userId = $hash->{fhem}{$_}{userId};
         FRITZBOX_Log $hash, 5, "Internal number $_ (dect$userId) seems to be a Fritz!Fon.";
         push @FritzFons, $hash->{fhem}{$_}{userId};
      }
   }
      
 # Check if 2nd parameter is the duration
   shift @val;
   if (int @val) {
      if ($val[0] =~ /^\d+$/ && int $val[0] >= 0) {
         $duration = $val[0];
         FRITZBOX_Log $hash, 5, "Extracted ring duration of $duration s.";
         shift @val;
      }
   }
   
 # Check if next parameter is a valid ring tone
   if (int @val) {
      if ($val[0] !~ /^(msg|show|say|play):/i) {
         $ringTone = $val[0];
         $ringTone = $ringToneNumber{lc $val[0]};
         return $name."|0|Error (set ring): Ring tone '".$val[0]."' not valid"
            unless defined $ringTone;
         FRITZBOX_Log $hash, 5, "Ring tone $ringTone will be used.";
         shift @val;
      }
   }

# Extract text to say, play or show
   foreach (@val) {
      if ($_ =~ /^(show|msg|say|play):/i) {
         $lastField = $1;
         $_ =~ s/^$1://;
      }
      $field{$lastField} .= $_." "     if $lastField;
    }

# build message to show
   my $msg = AttrVal( $name, "defaultCallerName", "FHEM" );
   if ( $field{show} ) {
      chop $field{show};
      $msg = $field{show};
   } 
   elsif ( $field{msg} ) {
      chop $field{msg};
      $msg = $field{msg};
   }
   $msg = substr($msg, 0, 30);
# no webcm no Message
   unless ( $hash->{WEBCM}==1 ) {
      $msg = "";
      FRITZBOX_Log $hash, 3, "Your Fritz!OS version has limited interfaces. Parameter 'show:' ignored."
         if $field{msg} || $field{show};
   }

# Determine number of Internet Radio to play mp3 or say tts
   if ( $field{say} || $field{play} ) {
      foreach (keys %{$hash->{fhem}{radio}}) {
         if ($hash->{fhem}{radio}{$_} eq "FHEM") {
            $fhemRadioStation = $_;
            last;
         }
      }
   # FHEM Radiostation needs to be created at last radio position
      $fhemRadioStation = $hash->{fhem}{radioCount}-1
         if not defined $fhemRadioStation && $hash->{fhem}{radioCount};
   }

# Create tts link to play as internet radio
   if ( $field{say} ) {
      if ($fhemRadioStation) {
         $ringTone = 33;
         chop $field{say};
         # my $ttsRessource = AttrVal( $name, "ttsRessource", "Google" );
         # Speak with espeak  # sudo apt-get install espeak
         # if ($ttsRessource eq "ESpeak"){
             # $cmd = "sudo espeak -vde+f3 -k5 -s150 \"" . $ttsText . "\""; 
             # Log3 $hash, 4, "Text2Speech:" .$cmd;
             # system($cmd);
         # }

      # speak with Translate.Google 
         # http://translate.google.com/translate_tts?ie=UTF-8&tl=[SPRACHE]&q=[TEXT];
         $ttsLink = $ttsLinkTemplate;
         my $ttsText = substr $field{say},0,100;
         my $ttsLang = "de";
         if ($ttsText =~ /^\((en|es|fr|nl)\)/i ) {
            $ttsLang = $1;
            $ttsText =~ s/^\($1\)\s*//i;
         }
         $ttsLink =~ s/\[SPRACHE\]/$ttsLang/;
         $ttsText = uri_escape($ttsText);
         $ttsLink =~ s/\[TEXT\]/$ttsText/;
         FRITZBOX_Log $hash, 5, "Created Text2Speech internet link: $ttsLink";
      }
      else {
         FRITZBOX_Log $hash, 2, "Cannot do Text2Speech because box has no internet radio";
      }
   }

# Extract play link
   if ( $field{play} ) {
      unless ($fhemRadioStation)
      {
        FRITZBOX_Log $hash, 3, "Cannot play mp3 because box has no internet radio";
      }
      elsif ($ttsLink)
      {
         FRITZBOX_Log $hash, 3, "Ignore 'play:' because Text2Speech already defined.";
      }
      else
      {
         $ringTone = 33;
         chop $field{play};
         $ttsLink = $field{play};
         FRITZBOX_Log $hash, 5, "Extracted MP3 ring tone: $ttsLink";
      }
   }
 
# Store current values for fon and dect port
   my $queryStr = "&dectUser=telcfg:settings/Foncontrol/User/list(Id,Intern,IntRingTone,RadioRingID)"; # DECT Numbers
   $queryStr .= "&fonPort=telcfg:settings/MSN/Port/list(Name,MSN)"; # Fon ports
   $queryStr .= "&dialPort=telcfg:settings/DialPort"; #Dial Port
   $queryStr .= "&useClickToDial=telcfg:settings/UseClickToDial"; # Use Click2Dial
   FRITZBOX_Log $hash, 4, "Read current dect and fon port values from box";
   $startValue = FRITZBOX_Web_Query( $hash, $queryStr, 'UTF-8') ;
   
#Preparing 1st command array
   @webCmdArray = ();
   
# Check ClickToDial
   unless ($startValue->{useClickToDial}) {
      if ($hash->{WEBCM}) { # mit webcm
         push @webCmdArray, "telcfg:settings/UseClickToDial" => 1;
         push @webCmdArray, "telcfg:settings/DialPort" => 50;
         $startValue->{dialPort}=50;
           FRITZBOX_Log $hash, 3, "Switch ClickToDial on, set dial port 50";
      }
      elsif ($hash->{SECPORT}) { # oder mit TR064
         # get port name
         push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_GetPhonePort", "NewIndex", "1"];
         @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         return $name."|0|Error (set ring): ".$tr064Result[0]->{Error}     if $tr064Result[0]->{Error};
         
         my $portName = $tr064Result[0]->{'X_AVM-DE_GetPhonePortResponse'}->{'NewX_AVM-DE_PhoneName'};
         # set click to dial
         if ($portName) {
            push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialSetConfig", "NewX_AVM-DE_PhoneName", $portName];
            @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
            FRITZBOX_Log $hash, 3, "Switch ClickToDial on, set dial port '$portName'";
         }
      }
      else { #oder Pech gehabt
         my $msg = "Error (set ring): Cannot ring because ClickToDial (Waehlhilfe) is off.";
           FRITZBOX_Log $hash, 2, $msg;
         return $name."|0|".$msg
      }
   }
   
   if (int (@FritzFons) == 0 && $ttsLink) {
      FRITZBOX_Log $hash, 3, "No Fritz!Fon identified, parameter 'say:' will be ignored.";
   }
# Creation fhemRadioStation for ttsLink
   elsif (int (@FritzFons) && $ttsLink && $hash->{fhem}{radio}{$fhemRadioStation} ne "FHEM") {
      push @webCmdArray, "configd:settings/WEBRADIO".$fhemRadioStation."/Name" => "FHEM";
      push @webCmdArray, "configd:settings/WEBRADIO".$fhemRadioStation."/Bitmap" => "1023";
      if (int @webCmdArray) {
         FRITZBOX_Log $hash, 3, "Create new internet radio station $fhemRadioStation: 'FHEM' for ringing with text-to-speech"
      }
      else {
         FRITZBOX_Log $hash, 3, "Your Fritz!OS version has limited interfaces. Cannot create radio station 'FHEM' for ringing with text-to-speech."
      }
   }
   
   #Execute command array
   FRITZBOX_Web_CmdPost( $hash, \@webCmdArray )       if int @webCmdArray;
   
#Preparing 2nd command array to set ring parameters
# Change ring tone of Fritz!Fons
   if ( $ringTone && $hash->{WEBCM}==0 && $useGuiHack == 0 ) {
      FRITZBOX_Log $hash, 3, "Your Fritz!OS version has limited interfaces. Ring tone cannot be changed."
   }
   elsif ($ringTone && @FritzFons == 0) {
      FRITZBOX_Log $hash, 3, "No Fritz!Fon identified, ring tone will be ignored.";
   }
   elsif ($ringTone) {
      foreach (@FritzFons) {
         push @webCmdArray, "telcfg:settings/Foncontrol/User".$_."/IntRingTone" => $ringTone
            unless $useGuiHack;
         my $getCmdStr = "&start_ringtest=1&idx=".$_."&ringtone=".$ringTone;
         FRITZBOX_Log $hash, 4, "Change temporarily internal ring tone of dect".$_." to $ringTone";
         if ($ttsLink) {
            push @webCmdArray, "telcfg:settings/Foncontrol/User".$_."/RadioRingID" => $fhemRadioStation
               unless $useGuiHack;
            $getCmdStr .= "&ring_tone_radio_test=".$fhemRadioStation;
            FRITZBOX_Log $hash, 4, "Change temporarily radio station of dect".$_." to $fhemRadioStation (FHEM)";
         }
         push @getCmdArray, [ "fon_devices/edit_dect_ring_tone.lua" => $getCmdStr]
               if $useGuiHack;
      }
   }

# Change dial port and its name (dial port 1-3) to show messages on ringing phones
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 0 );
   if ( $ringWithIntern =~ /^([1-3])$/ && $msg) {
      if ($startValue->{fonPort}->[$ringWithIntern-1]->{Name}) {
         push @webCmdArray, "telcfg:settings/MSN/Port".($ringWithIntern-1)."/Name" => $msg;
            FRITZBOX_Log $hash, 4, "Change temporarily name of dial port 'fon$ringWithIntern' to '$msg'";
      }
      else {
         FRITZBOX_Log $hash, 2, "Error: Current name of dial port 'fon$ringWithIntern' could not be determined -> Did not change the name.";
         my $temp = Dumper( $startValue );
         FRITZBOX_Log $hash, 3, "Debug info: \n".$temp;
      }
      push @webCmdArray, "telcfg:settings/DialPort" => $ringWithIntern;
         FRITZBOX_Log $hash, 4, "Set dial port to '" . $dialPort{$ringWithIntern} . "' (MSN: ".$startValue->{fonPort}->[$ringWithIntern-1]{MSN} .").";
   } 
# set dial port to 50 (all Fons)
   elsif ($msg) {
      FRITZBOX_Log $hash, 3, "Parameter 'show:' ignored because attribute 'ringWithIntern' not defined."
            if $field{show};
      push @webCmdArray, "telcfg:settings/DialPort" => 50;
         FRITZBOX_Log $hash, 4, "Set dial port to 50 (all fons)";
   }
  
# Set tts-Message
   if ($ttsLink) {
   # Create m3u-file (if ring tone and radio station cannot be changed because of missing interfaces)
      if ( $hash->{M3U_LOCAL} ne "undefined" ) {
         if (open my $fh, '>', $hash->{M3U_LOCAL}) {
            print $fh $ttsLink."\n";
            close $fh;
            FRITZBOX_Log $hash, 4, "Filled m3u file '".$hash->{M3U_LOCAL}."' with '$ttsLink'.";
            $ttsLink = $hash->{M3U_URL}      if $hash->{M3U_URL} ne "undefined";
         } 
         else {
            my $msg = "Error: Cannot create file '".$hash->{M3U_LOCAL}."' because: ".$!."\n";
            FRITZBOX_Log $hash, 4, $msg;
         }
      }
      push @webCmdArray, 'configd:settings/WEBRADIO'.$fhemRadioStation.'/URL' => $ttsLink;
   }
#Execute command array
   $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray )
      if $hash->{WEBCM}==1 && int( @webCmdArray ) > 0;

   $result = FRITZBOX_Web_CmdGet( $hash, \@getCmdArray )
      if int( @getCmdArray ) > 0;

   $intNo =~ s/,/#/g;
   
#Preparing 3rd command array to ring
   FRITZBOX_Log $hash, 4, "Ringing $intNo for $duration seconds";
   if ( $hash->{WEBCM}==1 ) {
      push @webCmdArray, "telcfg:command/Dial" => "**".$intNo."#";
      $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );
   }
   elsif ($hash->{SECPORT}) {
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", "**".$intNo."#"];
      @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
      return $name."|0|Error (set ring): ".$tr064Result[0]->{Error}     if $tr064Result[0]->{Error};
   }
   else {
      FRITZBOX_Log $hash, 3, "Your Fritz!OS version has limited interfaces. You cannot ring.";
   }
   
   sleep  5          if $duration <= 0; # always wait before reseting everything
   sleep $duration   if $duration > 0 ; #+1; # 1s added because it takes some time until it starts ringing
   
#Preparing 4th command array to stop ringing (but not when duration is 0 or play: and say: is used without duration)
   unless ( $duration == 0 || $duration == -1 && $ttsLink ) {
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialHangup"];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray )      if $hash->{SECPORT} && $hash->{WEBCM} != 1;
      push( @webCmdArray, "telcfg:command/Hangup" => "" )   if $hash->{WEBCM}==1;
   }
      
#Preparing 5th command array to reset everything
   push @webCmdArray, "telcfg:settings/DialPort" => $startValue->{dialPort}      if defined $startValue->{dialPort};
      FRITZBOX_Log $hash, 4, "Reset dial port to '".$dialPort{$startValue->{dialPort}}."'.";
# Reset internal ring tones for the Fritz!Fons
   if ($ringTone) {
      foreach (@FritzFons) {
         my $value = $startValue->{dectUser}->[$_]->{IntRingTone};
         push @webCmdArray, "telcfg:settings/Foncontrol/User".$_."/IntRingTone" => $value
            unless $useGuiHack;
         my $getCmdStr = "&ring_tone_radio_test=1&idx=".$_."&start_ringtest=1&ringtone=".$value;
            FRITZBOX_Log $hash, 4, "Reset ring tone of dect$_ to $value";
         # Reset internet station for the Fritz!Fons
         if ($ttsLink) {
            $value = $startValue->{dectUser}->[$_]->{RadioRingID};
            push @webCmdArray, "telcfg:settings/Foncontrol/User".$_."/RadioRingID" => $value
               unless $useGuiHack;
            $getCmdStr .= "&ring_tone_radio_test=".$value;
            FRITZBOX_Log $hash, 4, "Reset radio station of dect$_ to $value";
         }
         push @getCmdArray, [ "fon_devices/edit_dect_ring_tone.lua" => $getCmdStr ] 
               if $useGuiHack ;
      }
   }

# Reset name of calling number
   if ($ringWithIntern =~ /^([1-2])$/) {
      my $fonName = $startValue->{fonPort}->[$ringWithIntern-1]->{Name};
      if ($fonName) {# darf nie leer sein
         push( @webCmdArray, "telcfg:settings/MSN/Port".($ringWithIntern-1)."/Name" => $fonName ) ; 
            FRITZBOX_Log $hash, 4, "Reset name of dial port fon$ringWithIntern to '$fonName'";
      }
   }
   
# ??? Switch of Internet Radio stations 
   # if (!$ttsLink && defined $ringTone && $ringTone ==33 ) {
      # push @webCmdArray, "telcfg:command/Dial **".$intNo;
      # push @webCmdArray, "telcfg:command/Hangup **".$intNo;
   # }
#set Fritzbox ring 612 show:test test say:test test
   
# Execute command array
   $result = FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );

   $result = FRITZBOX_Web_CmdGet( $hash, \@getCmdArray )
      if int( @getCmdArray ) > 0;
   
   if ( $result->[0] == 1 ) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->[1];
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   }
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

   # return $name."|1|Ringing done";
} # End FRITZBOX_Ring_Run_Web

#######################################################################
sub FRITZBOX_Set_Alarm_Shell($@)
{
   my ($hash, @val) = @_;
   my $name = $hash->{NAME};
   
   my $alarm = $val[0];
   shift @val;
   
   my $para = " ".join(" ", @val);
   
   my $state = 1; 
   my $stateTxt = "on";
   if ($para =~ /off/i) 
   {
      $state = 0;
      $stateTxt = "off";
   }
   
   my $time;
   my $timeTxt;
   if ($para =~ /([0-2]?\d):([0-5]\d)/ )
   {
      if ($1<10)
      {
         $time = 0;
         $timeTxt = "0";
      }
      $time .= $1.$2;
      $timeTxt .= $1.":".$2;
      $time = undef if $time > 2359;
   }

   my $day; my $dayTxt;
   my %alDayValues = %alarmDays;
   $alDayValues{0} = "once";
   $alDayValues{127} = "daily";
   while (my ($key, $value) = each(%alDayValues) )
   {
      if ($para =~ /$value/i)
      {
         $day += $key ;
         $dayTxt .= $value." ";
      }
   }
   
   my $result = FRITZBOX_Telnet_OpenCon( $hash );
   return "$name|Error|$result"
      if $result;

   readingsBeginUpdate($hash);

   FRITZBOX_Shell_Exec( $hash, "ctlmgr_ctl w telcfg settings/AlarmClock".($alarm-1)."/Active ".$state );
   readingsBulkUpdate($hash,"alarm".$alarm."_state",$stateTxt);

   if (defined $time)
   {
      FRITZBOX_Shell_Exec( $hash, "ctlmgr_ctl w telcfg settings/AlarmClock".($alarm-1)."/Time ".$time );
      readingsBulkUpdate($hash,"alarm".$alarm."_time",$timeTxt);
   }

   if (defined $day)
   {
      FRITZBOX_Shell_Exec( $hash, "ctlmgr_ctl w telcfg settings/AlarmClock".($alarm-1)."/Weekdays ".$day );
      chop $dayTxt;
      readingsBulkUpdate($hash,"alarm".$alarm."_wdays",$dayTxt);
   }

   readingsEndUpdate($hash, 1);

   FRITZBOX_Telnet_CloseCon( $hash );
   
   return undef;
} # end FRITZBOX_Set_Alarm_Shell
   
#######################################################################
sub FRITZBOX_Set_Alarm_Web($@)
{
   my ($hash, @val) = @_;
   my $name = $hash->{NAME};
   my @webCmdArray;
   
   my $alarm = $val[0];
   shift @val;
   
   my $para = " ".join(" ", @val);
   
   my $state = 1; 
   my $stateTxt = "on";
   if ($para =~ /off/i) 
   {
      $state = 0;
      $stateTxt = "off";
   }
   
   my $time;
   my $timeTxt;
   if ($para =~ /([0-2]?\d):([0-5]\d)/ )
   {
      if ($1<10)
      {
         $time = 0;
         $timeTxt = "0";
      }
      $time .= $1.$2;
      $timeTxt .= $1.":".$2;
      $time = undef if $time > 2359;
   }

   my $day; my $dayTxt;
   my %alDayValues = %alarmDays;
   $alDayValues{0} = "once";
   $alDayValues{127} = "daily";
   while (my ($key, $value) = each(%alDayValues) )
   {
      if ($para =~ /$value/i)
      {
         $day += $key ;
         $dayTxt .= $value." ";
      }
   }
   
   readingsBeginUpdate($hash);

   push @webCmdArray, "telcfg:settings/AlarmClock".($alarm-1)."/Active" => $state;
   readingsBulkUpdate($hash,"alarm".$alarm."_state",$stateTxt);

   if (defined $time)
   {
      push @webCmdArray, "telcfg:settings/AlarmClock".($alarm-1)."/Time" => $time;
      readingsBulkUpdate($hash,"alarm".$alarm."_time",$timeTxt);
   }

   if (defined $day)
   {
      push @webCmdArray, "telcfg:settings/AlarmClock".($alarm-1)."/Weekdays" => $day;
      chop $dayTxt;
      readingsBulkUpdate($hash,"alarm".$alarm."_wdays",$dayTxt);
   }

   FRITZBOX_Web_CmdPost ($hash, \@webCmdArray);
   readingsEndUpdate($hash, 1);
   
   return undef;
} # end FRITZBOX_Set_Alarm_Web
   
#######################################################################
sub FRITZBOX_SetMOH($@)
{  
   my ($hash, $type, @file) = @_;
   my $returnStr;
   my @cmdArray;
   my $result;
   my $name = $hash->{NAME};
   my $uploadFile = '/var/tmp/fhem_moh_upload';
   my $mohFile = '/var/tmp/fhem_fx_moh';

   return "Error: Fritz!Box has no music on hold" unless defined $hash->{READINGS}{box_moh};

   if (lc $type eq lc $mohtype{0} || $type eq "0") {
      FRITZBOX_Shell_Exec ($hash, 'ctlmgr_ctl w telcfg settings/MOHType 0');
      return 0;
   }
   elsif (lc $type eq lc $mohtype{1} || $type eq "1") {
      FRITZBOX_Shell_Exec ($hash, 'ctlmgr_ctl w telcfg settings/MOHType 1');
      return 1;
   }
   return "Error: Unvalid parameter '$type'" unless lc $type eq lc $mohtype{2} || $type eq "2";

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

   $result = FRITZBOX_Telnet_OpenCon( $hash );
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
      push @cmdArray, 'wget -U Mozilla -O "'.$uploadFile.'" "'.$inFile.'"';
   } else {
      push @cmdArray, 'cp "'.$inFile.'" "'.$uploadFile.'"';
   }
   push @cmdArray, '[ -f "'.$uploadFile.'" ] && echo 1 || echo 0';
# Execute command array
   $result = FRITZBOX_Shell_Exec ( $hash, \@cmdArray );
   return "Could not access '$inFile'"
      unless $result->[3] eq "1";

#Prepare 2nd command array
   push @cmdArray, 'if [ ! -f "/var/tmp/ffmpeg_mp3.tables" ]; then playerd_tables; fi';
   push @cmdArray, 'ffmpegconv -i "'.$uploadFile.'" -o "'.$mohFile.'" --limit 32 --type 6';
   push @cmdArray, '[ -f "'.$mohFile.'" ] && echo 1 || echo 0';
# Execute 2nd command array
   $result = FRITZBOX_Shell_Exec ( $hash, \@cmdArray );
   return "Could not convert '$inFile'"
      unless $result->[2] eq "1";

#Prepare 3rd command array
   push @cmdArray, 'cat "'.$mohFile.'" >/var/flash/fx_moh';
   push @cmdArray, 'killall -sigusr1 telefon';
   push @cmdArray, 'rm "'.$uploadFile.'"';
   push @cmdArray, 'rm "'.$mohFile.'"';
# Execute 3rd command array
   $result = FRITZBOX_Shell_Exec ( $hash, \@cmdArray );

   FRITZBOX_Telnet_CloseCon( $hash );
   return 2;
}

#######################################################################
sub FRITZBOX_SetCustomerRingTone($@)
{  
   my ($hash, $intern, @file) = @_;
   my @cmdArray;
   my $result;
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
   
   my $uploadFile = '/var/InternerSpeicher/FRITZ/fonring/'.int(time()).'.g722';
   push @cmdArray, 'if [ ! -d /var/InternerSpeicher/FRITZ/fonring ]; then mkdir -p "/var/InternerSpeicher/FRITZ/fonring"; fi';
   push @cmdArray, '[ -x /etc/init.d/rc.preaudio.sh ] && /etc/init.d/rc.preaudio.sh start';
   
   $inFile =~ s/file:\/\///i;
 
# mp3 files are converted
   if ( $inFile =~ /\.mp3$/i ) { 
      push @cmdArray, 'picconv.sh "file://'.$inFile.'" "'.$uploadFile.'" ringtonemp3';
 
# G722 files are copied
   } elsif ( $inFile =~ /\.g722$/i ) { 
      push @cmdArray, "cp '$inFile' '$uploadFile'";

# all other formats fail
   } else {
      return "Error: only MP3 or G722 files can be uploaded to the phone";
   }
   
 # trigger the loading of the file to the phone, file will be deleted by the box as soon as the upload has finished
   push @cmdArray, '/usr/bin/pbd --set-ringtone-url --book="255" --id="'.$intern.'" --url="file://'.$uploadFile.'" --name="FHEM'.int(time()).'"';
   
   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return $result if $result;
   
   FRITZBOX_Shell_Exec ($hash, \@cmdArray);
   
   FRITZBOX_Telnet_CloseCon( $hash );
   
   return "Upload of ring tone will take about 1 minute. Do not work with the phone until its done.";
}

#######################################################################
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
   my $returnStr = FRITZBOX_Shell_Exec ($hash
      , 'ffmpegconv -i "'.$inFile.'" -o "'.$outFile.'.moh" --limit 32 --type 6');
   return $returnStr;
} # end FRITZBOX_ConvertMOH

#######################################################################
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
   my $returnStr = FRITZBOX_Shell_Exec ($hash
      , 'picconv.sh "file://'.$inFile.'" "'.$outFile.'.g722" ringtonemp3');
   return $returnStr;
} # end FRITZBOX_ConvertRingTone

#######################################################################
sub FRITZBOX_SendMail_Shell($@)
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
# change none ASCII chars in octal code for ISO-8859-1 (acc. http://www.pjb.com.au/comp/diacritics.html)
      $field{body} =~ s/Ä|Ã„/\\304/g;
      $field{body} =~ s/Ö|Ã–/\\326/g;
      $field{body} =~ s/Ü|Ãœ/\\334/g;
      $field{body} =~ s/ß|ÃŸ/\\337/g;
      $field{body} =~ s/ä|Ã¤/\\344/g;
      $field{body} =~ s/ö|Ã¶/\\366/g;
      $field{body} =~ s/ü|Ã¼/\\374/g;
   
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

   FRITZBOX_Shell_Exec( $hash, \@cmdArray );
   
   return undef;
}

#######################################################################
sub FRITZBOX_StartRadio_Shell($@) 
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
   if (@val) {
      $radioStationName = join (" ", @val);
      if ($radioStationName =~ /^\d+$/) {
         $radioStation = $radioStationName;
         $radioStationName = $hash->{fhem}{radio}{$radioStation};
         return "Error: Unknown internet radio number $radioStation."
            unless defined $radioStationName;
      }
      else {
         foreach (keys %{$hash->{fhem}{radio}}) {
            if (lc $hash->{fhem}{radio}{$_} eq lc $radioStationName) {
               $radioStation = $_;
               last;
            }
         }
         return "Error: Unknown internet radio station '$radioStationName'"
            unless defined $radioStation;
         
      }
   }

   $result = FRITZBOX_Telnet_OpenCon( $hash );
   return $result if $result;

# Get current ringtone
   my $userNo = $intNo-609;
   push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$userNo."/IntRingTone";
   push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$userNo."/RadioRingID";
   $result = FRITZBOX_Shell_Exec( $hash, \@cmdArray );
   
   my $curRingTone = $result->[0];
   my $curRadioStation = $result->[1];

# Start Internet Radio and reset ring tone
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/IntRingTone 33";
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/RadioRingID $radioStation"
      if defined $radioStation;
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo;
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/IntRingTone $curRingTone";
   push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$userNo."/RadioRingID $curRadioStation"
      if defined $radioStation;

# Execute command array
   FRITZBOX_Shell_Exec( $hash, \@cmdArray );

   FRITZBOX_Telnet_CloseCon( $hash );

   return undef;
}

#######################################################################
sub FRITZBOX_StartRadio_Web($@) 
{
   my ($hash, @val) = @_;
   my @webCmdArray;
   my @getCmdArray;
   my @tr064CmdArray;
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
   if (@val) {
      $radioStationName = join (" ", @val);
      if ($radioStationName =~ /^\d+$/) {
         $radioStation = $radioStationName;
         $radioStationName = $hash->{fhem}{radio}{$radioStation};
         return "Error: Unknown internet radio number $radioStation."
            unless defined $radioStationName;
      }
      else {
         foreach (keys %{$hash->{fhem}{radio}}) {
            if (lc $hash->{fhem}{radio}{$_} eq lc $radioStationName) {
               $radioStation = $_;
               last;
            }
         }
         return "Error: Unknown internet radio station '$radioStationName'"
            unless defined $radioStation;
         
      }
   }

# Get current ringtone
   my $userNo = $intNo-609;
   my $queryStr = "&curRingTone=telcfg:settings/Foncontrol/User".$userNo."/IntRingTone";
   $queryStr .= "&curRadioStation=telcfg:settings/Foncontrol/User".$userNo."/RadioRingID";
   my $startValue = FRITZBOX_Web_Query( $hash, $queryStr );
   
# Set ring tone Internet Radio
      FRITZBOX_Log $hash, 5, "Set ring tone of $intNo to radio $radioStation";
   push @webCmdArray, "telcfg:settings/Foncontrol/User".$userNo."/IntRingTone" => 33;
   push @webCmdArray, "telcfg:settings/Foncontrol/User".$userNo."/RadioRingID" => $radioStation
      if defined $radioStation;
   FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );

      FRITZBOX_Log $hash, 5, "Call $intNo";
   if ($hash->{SECPORT}) { #ring with TR-064
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", "**".$intNo."#"];
      FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }
   else { # ring with webcm
      push @webCmdArray, "telcfg:command/Dial" => "**".$intNo."#";
      FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );
   }

# Reset ring tone
      FRITZBOX_Log $hash, 5, "Reset ring tones.";
   push @webCmdArray, "telcfg:settings/Foncontrol/User".$userNo."/IntRingTone" => $startValue->{curRingTone};
   push @webCmdArray, "telcfg:settings/Foncontrol/User".$userNo."/RadioRingID" => $startValue->{curRadioStation}
      if defined $radioStation;
   FRITZBOX_Web_CmdPost( $hash, \@webCmdArray );

   return undef;
} # END sub FRITZBOX_StartRadio_Web

#'picconv.sh "'.$inFile.'" "'.$outFile.'.g722" ringtonemp3'
#picconv.sh "file://$dir/upload.mp3" "$dir/$filename" ringtonemp3   
#"ffmpegconv  -i '$inFile' -o '$outFile.g722' --limit 240");
#ffmpegconv -i "${in}" -o "${out}" --limit 240
#pbd --set-image-url --book=255 --id=612 --url=/var/InternerSpeicher/FRITZ/fonring/1416431162.g722 --type=1
#pbd --set-image-url --book=255 --id=612 --url=file://var/InternerSpeicher/FRITZBOXtest.g722 --type=1
#ctlmgr_ctl r user settings/user0/bpjm_filter_enable
#/usr/bin/pbd --set-ringtone-url --book="255" --id="612" --url="file:///var/InternerSpeicher/claydermann.g722" --name="Claydermann"
# /usr/bin/moh_upload

#######################################################################
sub FRITZBOX_Shell_Query($$$)
{
   my ($hash, $readoutCmdArray, $roReadings) = @_;
   my @cmdArray;
   my $rValue;
   my $rName;
   my $rFormat;
      
   my $count = int @{$readoutCmdArray} - 1;
   for (0..$count)
   {
      push @cmdArray, $readoutCmdArray->[$_][1];
   }

   my $resultArray = FRITZBOX_Shell_Exec( $hash, \@cmdArray);
   if (defined ($resultArray))
   {
      $count = int @{$resultArray} -1;
      for (0..$count)
      {
         $rValue = $resultArray->[$_];
         $rFormat = $readoutCmdArray->[$_][2];
         $rFormat = "" unless defined $rFormat;
         $rValue = FRITZBOX_Readout_Format ($hash, $rFormat, $rValue);
         $rName = $readoutCmdArray->[$_][0];
         if ($rName ne "")
         {
            FRITZBOX_Log $hash, 5, "$rName: $rValue";
            push @{$roReadings}, $rName."|".$rValue;
         }
      }
   }
   @{$readoutCmdArray} = ();
   
   return $resultArray;
}

# Executed the command on the FritzBox Shell (remote or local)
############################################
sub FRITZBOX_Shell_Exec($$)
{
   my ($hash, $cmd) = @_;
   my $openedTelnet = 0;
   
   if ($hash->{REMOTE} == 1) {
      unless (defined $telnet) {
         return undef
            if (FRITZBOX_Telnet_OpenCon($hash));
         $openedTelnet = 1;
      }
      my $retVal = FRITZBOX_Shell_Exec_Telnet($hash, $cmd);
      FRITZBOX_Telnet_CloseCon ( $hash ) if $openedTelnet;
      return $retVal;
   }
   else {
      return FRITZBOX_Shell_Exec_Local($hash, $cmd);
   }

}

# Executed the command on the fhem server (on the FritzBox Shell)
############################################
sub FRITZBOX_Shell_Exec_Local($$)
{
   my ($hash, $cmd) = @_;
  
   if (ref \$cmd eq "SCALAR") {
      FRITZBOX_Log $hash, 5, "Execute '".$cmd."'";
      my $result = qx($cmd);
      chomp $result;
      FRITZBOX_Log $hash, 5, "Result '$result'";
      return $result;
   }
   elsif (ref \$cmd eq "REF") {
      if ( int (@{$cmd}) > 0 )
      {
         FRITZBOX_Log $hash, 4, "Execute " . int ( @{$cmd} ) . " command(s)";
         FRITZBOX_Log $hash, 5, "Commands: '" . join( " | ", @{$cmd} ) . "'";
         my $cmdStr = join "\necho ' |#|'\n", @{$cmd};
         $cmdStr .= "\necho ' |#|'";
         my $result = qx($cmdStr);
         unless (defined $result)
         {
            FRITZBOX_Log $hash, 1, "Error: No STDOUT from shell command.";
            return undef;
         }
         $result =~ s/\n|\r//g;
         my @resultArray = split /\|#\|/, $result;
         for (0 .. $#resultArray)
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
   else {
      FRITZBOX_Log $hash, 1, "Error: wrong perl parameter";
   }
}

# Executed a command via Telnet
############################################
sub FRITZBOX_Shell_Exec_Telnet($$)
{
   my ($hash, $cmd) = @_;
   my @output;
   my $result;

      
   if (ref \$cmd eq "SCALAR") {
      FRITZBOX_Log $hash, 4, "Execute '".$cmd."'";
      @output=$telnet->cmd($cmd);
      $result = $output[0];
      chomp $result;
      my $log = join " ", @output;
      chomp $log;
      FRITZBOX_Log $hash, 4, "Result '$log'";
      return $result;
   }
   elsif (ref \$cmd eq "REF") {
      my @resultArray = ();
      if ( int (@{$cmd}) > 0 )
      {
         FRITZBOX_Log $hash, 4, "Execute " . int ( @{$cmd} ) . " command(s)";
         
         foreach (@{$cmd})
         {
            FRITZBOX_Log $hash, 5, "Execute '$_'";
            unless ($_ =~ /^sleep/)
            {
               @output=$telnet->cmd($_);
               $result = $output[0] || "";
               chomp $result;
               my $log = join "", @output;
               chomp $log;
               FRITZBOX_Log $hash, 5, "Result '$log'";
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
   else {
      FRITZBOX_Log $hash, 1, "Error: wrong perl parameter";
      return undef;
   }
}

# Opens a Telnet Connection to an external FritzBox
############################################
sub FRITZBOX_Telnet_OpenCon($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   return undef       unless $hash->{REMOTE} == 1;
   
   if ($missingModulTelnet) {
      my $msg = "Error: Perl modul ".$missingModulTelnet."is missing on this system. Please install before using this modul.";
      FRITZBOX_Log $hash, 2, $msg;
      return $msg;
   }
      
   my $host = $hash->{HOST};

   my $pwd = FRITZBOX_readPassword($hash);
   my $msg;
   my $before;
   my $match;
   
   unless (defined $pwd) {
      $msg = "Error: No password set. Please define it with 'set $name password YourPassword'";
      FRITZBOX_Log $hash, 2, $msg;
      # return $msg;
      
      my $pwdFile = AttrVal( $name, "pwdFile", "fb_pwd.txt");
      FRITZBOX_Log $hash, 5, "Open password file '$pwdFile' to extract password";
      if (open(IN, "<" . $pwdFile)) {
         $pwd = <IN>;
         close(IN);
        FRITZBOX_Log $hash, 5, "Close password file";
      } else {
         FRITZBOX_Log $hash, 2, $msg;
         return $msg;
      }
   }
   
   my $user = AttrVal( $name, "telnetUser", "" );

      FRITZBOX_Log $hash, 4, "Open Telnet connection to $host";
   my $timeout = AttrVal( $name, "telnetTimeOut", "10");
   $telnet = new Net::Telnet ( Host=>$host, Port => 23, Timeout=>$timeout, Errmode=>'return', Prompt=>'/# $/');
   if (!$telnet) {
      $msg = "Could not open telnet connection to $host: $!";
      FRITZBOX_Log $hash, 2, $msg;
      $telnet = undef;
      return $msg;
   }

   FRITZBOX_Log $hash, 5, "Wait for user or password prompt.";
   unless ( ($before,$match) = $telnet->waitfor('/(user|login|password): $/i') ) {
      $msg = "Telnet error while waiting for user or password prompt: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   if ( $match =~ /(user|login): / && $user eq "") {
      $msg = "Telnet login requires user name but attribute 'telnetUser' not defined";
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   elsif ( $match =~ /(user|login): /) {
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
   elsif ( $match eq "password: " && $user ne "") {
      FRITZBOX_Log $hash, 3, "Attribute 'telnetUser' defined but telnet login did not prompt for user name.";
   }

      FRITZBOX_Log $hash, 5, "Entering password";
   $telnet->print( $pwd );

      FRITZBOX_Log $hash, 5, "Wait for command prompt";
   unless ( ($before,$match) = $telnet->waitfor( '/# $|Login failed./i' )) {
      $msg = "Telnet error while waiting for command prompt: ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   elsif ( $match eq "Login failed.") {
      $msg = "Telnet error: Login failed. Wrong password.";
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   
# redirect console messages
   $telnet->cmd("setconsole -r");

      FRITZBOX_Log $hash, 5, "Change command prompt";
   $telnet->prompt('/<xFHEMx> $/');
   unless ($telnet->cmd("PS1='<xFHEMx> '")) {
      $msg = "Telnet error: Could not change command prompt - ".$telnet->errmsg;
      FRITZBOX_Log $hash, 2, $msg;
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   
   return undef;
} # end FRITZBOX_Telnet_OpenCon
   
# Closes a Telnet Connection to an external FritzBox
############################################
sub FRITZBOX_Telnet_CloseCon($)
{
   my ($hash) = @_;
   
   return undef 
      unless $hash->{REMOTE} == 1;

   if (defined $telnet) {
      FRITZBOX_Log $hash, 4, "Close Telnet connection";
      $telnet->close;
      $telnet = undef;
   }
   else {
      FRITZBOX_Log $hash, 1, "Cannot close an undefined Telnet connection";
   }
} # end FRITZBOX_Telnet_CloseCon

# Execute a Command via TR-064
#################################################
sub FRITZBOX_TR064_Cmd($$$)
{
   my ($hash, $xml, $cmdArray) = @_;
   
   my $name = $hash->{NAME};
   my $port = $hash->{SECPORT};
   
   unless ($port) {
      FRITZBOX_Log $hash, 4, "TR064 not used. No security port defined.";
      return undef;
   }

# Set Password und User for TR064 access
   $FRITZBOX_TR064pwd = FRITZBOX_readPassword($hash)     unless defined $FRITZBOX_TR064pwd;
   $FRITZBOX_TR064user = AttrVal( $name, "boxUser", "dslf-config" );   
   
   my $host = $hash->{HOST};
   
   my @retArray;
   
   foreach( @{$cmdArray} ) {
      next     unless int @{$_} >=3 && int( @{$_} ) % 2 == 1;
      my( $service, $control, $action, %params) = @{$_};
      my @soapParams;

      $service =~ s/urn:dslforum-org:service://;
      $control =~ s#/upnp/control/##;
      
      my $logMsg = "service='$service', control='$control', action='$action'";
   # Prepare action parameter
      foreach (keys %params) {
         $logMsg .= ", parameter".(int(@soapParams)+1)."='$_' => '$params{$_}'" ;
         push @soapParams, SOAP::Data->name( $_ => $params{$_} );
      }
      
      FRITZBOX_Log $hash, 4, "Perform TR-064 call - ".$logMsg;

      my $soap = SOAP::Lite
         -> on_fault ( sub {} )
         -> uri( "urn:dslforum-org:service:".$service )
         -> proxy('https://'.$host.":".$port."/upnp/control/".$control, ssl_opts => [ SSL_verify_mode => 0 ], timeout => 10  )
         -> readable(1);
      my $res = $soap -> call( $action => @soapParams );
      
      unless( $res ) { # Transport-Error
         FRITZBOX_Log $hash, 2, "TR064-Transport-Error: ".$soap->transport->status;
         my %errorMsg = ( "Error" => $soap->transport->status );
         push @retArray, \%errorMsg;
         $FRITZBOX_TR064pwd = undef;
      }
      elsif( $res->fault ) { # SOAP Error - will be defined if Fault element is in the message
         # my $fcode =  $s->faultcode;   #
         # my $fstring =  $s->faultstring; # also available
         # my $factor =  $s->faultactor;
         my $ecode =  $res->faultdetail->{'UPnPError'}->{'errorCode'};
         my $edesc =  $res->faultdetail->{'UPnPError'}->{'errorDescription'};
         FRITZBOX_Log $hash, 2, "TR064-Error $ecode:$edesc ($logMsg)";
         @{$cmdArray} = ();
         # my $fdetail = Dumper($res->faultdetail); # returns value of 'detail' element as string or object
         # return "Error\n".$fdetail;
         push @retArray, $res->faultdetail;
         $FRITZBOX_TR064pwd = undef;
      } 
      else { # normal result
         push @retArray, $res->body;
      }
   }
   
   @{$cmdArray} = ();
   return @retArray;

} # End of FRITZBOX_TR064_Cmd

# get Fritzbox tr064ServiceList
#################################################
sub FRITZBOX_TR064_Get_ServiceList($)
{
   my ($hash) = @_;
   my $name = $defs{NAME};

   
   if ( $missingModulWeb ) {
      my $msg = "Error: Perl modul " . $missingModulWeb . "is missing on this system. Please install before using this modul.";
      FRITZBOX_Log $hash, 2, $msg;
      return $msg;
   }

   my $host = $hash->{HOST};
   my $url = 'http://'.$host.":49000/tr64desc.xml";

   my $returnStr = "_" x 130 ."\n\n";
   $returnStr .= " List of TR-064 services and actions that are provided by the device '$host'\n";

   return "TR-064 switched off."     if $hash->{READINGS}{box_tr064}{VAL} eq "off";

   FRITZBOX_Log $hash, 5, "Getting service page $url";
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
   my $response = $agent->get( $url );

   return "$url does not exist."     if $response->is_error();

   my $content = $response->content;
   my @serviceArray;
   
# Get basic service data
   while( $content =~ /<service>(.*?)<\/service>/isg ) {
      my $serviceXML = $1;
      my @service;
      my $service = $1     if $serviceXML =~ m/<servicetype>urn:dslforum-org:service:(.*?)<\/servicetype>/is;
      my $control = $1     if $serviceXML =~ m/<controlurl>\/upnp\/control\/(.*?)<\/controlurl>/is;
      my $scpd = $1     if $serviceXML =~ m/<scpdurl>(.*?)<\/scpdurl>/is;

      push @serviceArray, [$service, $control, $scpd];
   }

# Get actions of each service
   foreach (@serviceArray) {

      $url = 'http://'.$host.":49000".$_->[2];

         FRITZBOX_Log $hash, 5, "Getting action page $url";
      my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
      my $response = $agent->get( $url );

      return "ServiceSCPD $url does not exist"     if $response->is_error();

      my $content = $response->content;

   # get version
      $content =~ /<major>(.*?)<\/major>/isg;
      my $version = $1;
      $content =~ /<minor>(.*?)<\/minor>/isg;
      $version .= ".".$1;
      
      $returnStr .= "_" x 130 ."\n\n";
      $returnStr .= " Spec: http://".$host.":49000".$_->[2]."    Version: ".$version."\n";
      $returnStr .= " Service: ".$_->[0]."     Control: ".$_->[1]."\n";
      $returnStr .= "-" x 130 ."\n";
   
   # get name and arguments of each action
      while( $content =~ /<action>(.*?)<\/action>/isg ) {
         
         my $serviceXML = $1;
         $serviceXML =~ /<name>(.*?)<\/name>/is;
         my $action = $1;
         $serviceXML =~ /<argumentlist>(.*?)<\/argumentlist>/is;
         my $argXML = $1;

         my $lineStr = "  $action (";
         my $tab = " " x length( $lineStr );

         my @argArray = ($argXML =~ /<argument>(.*?)<\/argument>/isg);
         my @argOut;
         foreach (@argArray) {
            $_ =~ /<name>(.*?)<\/name>/is;
            my $argName = $1;
            $_ =~ /<direction>(.*?)<\/direction>/is;
            my $argDir = $1;
            if ($argDir eq "in") { 
               # Wrap
               if (length ($lineStr.$argName) > 129) {
                  $returnStr .= $lineStr."\n" ;
                  $lineStr = $tab;
               }
               $lineStr .= " $argName"; 
            }
            else { push @argOut, $argName; }
         }
         $lineStr .= " )";
         $lineStr .= " = ("        if int @argOut;
         foreach (@argOut) {
            # Wrap
            if (length ($lineStr.$_) > 129) {
               $returnStr .= $lineStr."\n" ;
               $lineStr = $tab ." " x 6;
            }
            $lineStr .= " $_";
         }
         $lineStr .= " )"        if int @argOut;
         $returnStr .= $lineStr."\n";
      }
   }

   return $returnStr;
}

#######################################################################
sub FRITZBOX_TR064_Init ($$)
{
   my ($hash, $host) = @_;
   my $name = $hash->{NAME};

   return   if AttrVal( $name, "forceTelnetConnection",  0 );   
   
   if ($missingModulTR064) {
      FRITZBOX_Log $hash, 2,  "Cannot use TR-064. Perl modul ".$missingModulTR064."is missing on this system. Please install.";
      return undef;
   }

# Security Port anfordern
      FRITZBOX_Log $hash, 4, "Open TR-064 connection and ask for security port";
   my $s = SOAP::Lite
      -> uri('urn:dslforum-org:service:DeviceInfo:1')
      -> proxy('http://'.$host.':49000/upnp/control/deviceinfo', timeout => 10 )
      -> getSecurityPort();

   my $port = $s->result;
   unless( $port ) {
      FRITZBOX_Log $hash, 2, "Could not get secure port: $!";
      return undef;
   }

#   $hash->{TR064USER} = "dslf-config";

   # jetzt die Zertifikatsüberprüfung (sofort) abschalten
   BEGIN {
      $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
   }

   # dieser Code authentifiziert an der Box
   sub SOAP::Transport::HTTP::Client::get_basic_credentials {return  $FRITZBOX_TR064user => $FRITZBOX_TR064pwd;}
   
   return $port;
}

# Opens a Web connection to an external Fritzbox
############################################
sub FRITZBOX_Web_OpenCon ($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   return undef 
      unless $hash->{REMOTE} == 1;
   
   if ($missingModulWeb) {
      FRITZBOX_Log $hash, 2, "Error: Perl modul ".$missingModulWeb."is missing on this system. Please install before using this modul.";
      return undef;
   }

# Use old sid if last access later than 9.5 minutes
   my $sid = $hash->{fhem}{sid};
   return $sid
      if defined $sid && $hash->{fhem}{sidTime}>time()-9.5*60;
   
   my $host = $hash->{HOST};

   my $pwd = FRITZBOX_readPassword($hash);

   unless (defined $pwd) {
      FRITZBOX_Log $hash, 2, "Error: No password set. Please define it (once) with 'set $name password YourPassword'";
      return undef;
   }
   my $user = AttrVal( $name, "boxUser", "" );
   $user = AttrVal( $name, "telnetUser", "" ) if $user eq "";

   FRITZBOX_Log $hash, 4, "Open Web connection to $host";
   $sid = (FB_doCheckPW($host, $user, $pwd));
   
   if ($sid) {
      FRITZBOX_Log $hash, 4, "Web session opened with sid $sid";
      return $sid;
   } 
   
   FRITZBOX_Log $hash, 2, "Web connection could not be established. Please check your credentials (password, user).";
   return undef;

 }

# Execute commands via the web connection
############################################
sub FRITZBOX_Web_CmdPost($$@)
{
   my ($hash, $webCmdArray, $page) = @_;
   my $name = $hash->{NAME};
   
   unless ( $hash->{WEBCM}==1 ) {
      @{$webCmdArray} = ();
      my $msg = "API webcm not available on the box.";
      FRITZBOX_Log $hash, 4, $msg;
      my @retArray = (0, $msg);
      return \@retArray;
   }

   my $sid = FRITZBOX_Web_OpenCon($hash);
   unless ($sid) {
      my @retArray = (2, "Didn't get a session ID");
      return \@retArray;
   }
   

# Complete the arguments
   if ($page) {
      $page .= "?sid=".$sid;
      push @{$webCmdArray}, "apply" => "";
   } 
   else {
      $page = '/cgi-bin/webcm';
   }
   push @{$webCmdArray}, "sid" => $sid;
   
   my $host = $hash->{HOST};
   my $url = 'http://'.$host.$page;

   FRITZBOX_Log $hash, 5, "Posting ".(@{$webCmdArray} /2) ." parameters to '$url'";
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
   my $response = $agent->post( $url, $webCmdArray );
   @{$webCmdArray} = ();

   if ($response->is_error) {
      my @retArray = (0, "Error: ".$response->status_line);
      return \@retArray;
   }

   # FRITZBOX_Log $hash, 3, "Response: ".$response->content;
# if ($response->content)
   # {
      # my @retArray = (0, "Command not executed");
      # return \@retArray;
   # }
   
   my @retArray = (1, $sid);
   return \@retArray;
}

# Execute commands via the web connection
############################################
sub FRITZBOX_Web_CmdGet($$)
{
#set Fritzbox ring 612 ringring
#URL=http://fritz.box/fon_devices/edit_dect_ring_tone.lua?idx=4&sid=5695bd219020152b&start_ringtest=1&ringtone=4&xhr=1&t1436900289183=nocache
#URL=http://fritz.box/fon_devices/edit_dect_ring_tone.lua?idx=4&sid=5695bd219020152b&start_ringtest=2&xhr=1&t1436900295372=nocache
   my ($hash, $getCmdArray) = @_;
   my $name = $hash->{NAME};

   my $sid = FRITZBOX_Web_OpenCon($hash);
   unless ($sid) {
      my @retArray = (0, "Didn't get a session ID");
      return \@retArray;
   }
   
   my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );

   my $host = $hash->{HOST};
   foreach ( @{$getCmdArray} ) {
      my ($page,$getCmdStr) = @{$_};
      my $url =  'http://'.$host."/".$page."?sid=".$sid.$getCmdStr;
      FRITZBOX_Log $hash, 4, "Execute HTTP-Get '$url'";
      my $response = $agent->get( $url );

      if ($response->is_error) {
         my @retArray = (0, "Error: ".$response->status_line);
         return \@retArray;
      }
      else {
         FRITZBOX_Log $hash, 5, "Response: ".$response->content();
      }
   }

   @{$getCmdArray} = ();

   my @retArray = (1, $sid);
   return \@retArray;
}

# Read box values via the web connection
############################################
sub FRITZBOX_Web_Query($$@)
{
   my ($hash, $queryStr, $charSet) = @_;
   $charSet = "" unless defined $charSet;
   my $name = $hash->{NAME};

   my $sid = FRITZBOX_Web_OpenCon( $hash );
   unless ($sid) {
      my %retHash = ( "Error" => "Didn't get a session ID", "ResetSID" => "1" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 5, "Request data via API luaQuery.";
   my $host = $hash->{HOST};
   my $url = 'http://' . $host . '/query.lua?sid=' . $sid . $queryStr;
   #FRITZBOX_Log $hash, 3, "URL: $url";
   
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 180);
   my $response = $agent->get ( $url );

   FRITZBOX_Log $hash, 5, "Response: ".$response->status_line."\n".$response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 3, "Error: ".$response->status_line;
      return \%retHash;
   }

   if ($response->content =~ /<html>|"pid": "logout"/) {
      my %retHash = ("Error" => "Old SID not valid anymore.", "ResetSID" => "1");
      return \%retHash;
   }

#################
   # FRITZBOX_Log $hash, 3, "Response: ".$response->content;
#################

   my $jsonText = $response->content;
   # Remove illegal escape sequences
   $jsonText =~ s/\\'/'/g; #Hochkomma
   $jsonText =~ s/\\x\{[0-9a-f]\}//g; #delete control codes (as hex numbers)
   
   FRITZBOX_Log $hash, 5, "Decode JSON string.";
   my $jsonResult ;
   if ($charSet eq "UTF-8") {
      $jsonResult = JSON->new->utf8->decode( $jsonText );
   } 
   else {
      $jsonResult = JSON->new->latin1->decode( $jsonText );
   }
   $jsonResult->{sid} = $sid;
   $jsonResult->{Error} = $jsonResult->{error}  if defined $jsonResult->{error};
   return $jsonResult;
}

#####################################
# checks and stores FritzBox password used for telnet or webinterface connection
sub FRITZBOX_storePassword($$)
{
    my ($hash, $password) = @_;
     
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    
    my $enc_pwd = "";
    
    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = setKeyValue($index, $enc_pwd);
    return "error while saving the password - $err" if(defined($err));
    
    return "password successfully saved";
} # end FRITZBOX_storePassword
   
#####################################
# reads the FritzBox password
sub FRITZBOX_readPassword($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
   my $key = getUniqueId().$index;

   my ($password, $err);

   FRITZBOX_Log $hash, 5, "Read FritzBox password from file";
   ($err, $password) = getKeyValue($index);

   if ( defined($err) ) {
      FRITZBOX_Log $hash, 4, "unable to read FritzBox password from file: $err";
      return undef;
   }  
    
   if ( defined($password) ) {
      if ( eval "use Digest::MD5;1" ) {
         $key = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }

      my $dec_pwd = '';
     
      for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
         my $decode=chop($key);
         $dec_pwd.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
     
      return $dec_pwd;
   }
   else {
      FRITZBOX_Log $hash, 4, "No password in file";
      return undef;
   }
} # end FRITZBOX_readPassword
   
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
#{my @cmd;; $cmd=webCmdArray, "active" => "on";
# FRITZBOX_Web_CmdPost ($hash, \@webCmdArray, '/wlan/wlan_settings.lua');


      # <li><code>set &lt;name&gt; convertRingTone &lt;fullFilePath&gt;</code>
         # <br>
         # Converts the mp3-file fullFilePath to the G722 format and puts it in the same path.
         # <br>
         # The file has to be placed on the file system of the Fritz!Box.
      # </li><br>
      
      # <li><code>set &lt;name&gt; convertMusicOnHold &lt;fullFilePath&gt;</code>
         # <br>
         # <i>Not implemented yet.</i> Converts the mp3-file fullFilePath to a format that can be used for "Music on Hold".
         # <br>
         # The file has to be placed on the file system of the fritzbox.
      # </li><br>

      # <li><code>set &lt;name&gt; convertRingTone &lt;fullFilePath&gt;</code>
         # <br>
         # Konvertiert die  mp3-Datei fullFilePath in das G722-Format und legt es im selben Pfad ab.
         # <br>
         # Die Datei muss im Dateisystem der Fritz!Box liegen.
      # </li><br>
      
      # <li><code>set &lt;name&gt; convertMusicOnHold &lt;fullFilePath&gt;</code>
         # <br>
         # <i>Not implemented yet.</i> Converts the mp3-file fullFilePath to a format that can be used for "Music on Hold".
         # <br>
         # The file has to be placed on the file system of the fritzbox.
      # </li><br>

1;

=pod
=item device
=item summary Controls some features of a Fritz!Box router and Fritz!Fon.
=item summary_DE Steuert gewisse Funktionen eines Fritz!Box Routers und verbundene Fritz!Fon.

=begin html

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
<div> 
<ul>
   Controls some features of a Fritz!Box router. Connected Fritz!Fon's (MT-F, MT-D, C3, C4) can be used as
   signaling devices. MP3 files and Text2Speech can be played as ring tone or when calling phones.
   <br>
   For detail instructions, look at and please maintain the <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki</b></a>.
   <br/><br/>
   The modul switches in local mode if FHEM runs on a Fritz!Box (as root user!). Otherwise, it tries to open a web or telnet connection to "fritz.box", so telnet (#96*7*) has to be enabled on the Fritz!Box. For remote access the password must <u>once</u> be set.
   <br/><br/>
   The box is partly controlled via the official TR-064 interface but also via undocumented interfaces between web interface and firmware kernel. The modul works best with Fritz!OS 6.24. AVM has removed internal interfaces (telnet, webcm) from later Fritz!OS versions without replacement. <b>For these versions, some modul functions are hence restricted or do not work at all (see remarks to required API).</b>
   <br>
   The modul was tested on Fritz!Box 7390 and 7490 with Fritz!OS 6.20 and higher.
   <br>
   Check also the other Fritz!Box moduls: <a href="#SYSMON">SYSMON</a> and <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>The modul uses the Perl modul 'Net::Telnet', 'JSON::XS', 'LWP', 'SOAP::Lite' for remote access.</i>
   <br/><br/>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX  [host]</code>
      <br/>
         The attribute <i>host</i> is the web address (name or IP) of the Fritz!Box. If it is missing, the modul switches in local mode or uses the default host address "fritz.box".
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
      <li><code>set &lt;name&gt; alarm &lt;number&gt; [on|off] [time] [once|daily|Mo|Tu|We|Th|Fr|Sa|So]</code>
         <br>
         Switches the alarm number (1, 2 or 3) on or off (default is on). Sets the time and weekday. If no state is given it is switched on.
         <br>
         Requires the API: Telnet or webcm.
      </li><br>

      <li><code>set &lt;name&gt; call &lt;number&gt; [duration] [say:text|play:MP3URL]</code>
         <br>
         Calls for 'duration' seconds (default 60) the given number from an internal port (default 1 or attribute 'ringWithIntern'). If the call is taken a text or sound can be played as music on hold (moh). The internal port will also ring.
         Say and play requires the API: Telnet or webcm.
      </li><br>

      <li><code>set &lt;name&gt; checkAPIs</code>
         <br>
         Restarts the initial check of the programming interfaces of the FRITZ!BOX.
      </li><br>

      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;fullFilePath&gt;</code>
         <br>
         Uploads the file fullFilePath on the given handset. Only mp3 or G722 format is allowed.
         <br>
         The file has to be placed on the file system of the fritzbox.
         <br>
         The upload takes about one minute before the tone is available.
      </li><br>

      <li><code>set &lt;name&gt; dect &lt;on|off&gt;</code>
         <br>
         Switches the DECT base of the box on or off. Requires the API: Telnet or webcm.
      </li><br>

      <li><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Switches the call diversity number (1, 2 ...) on or off.
         A call diversity for an incoming number has to be created with the Fritz!Box web interface. Requires the API: Telnet, webcm or TR064 (>=6.50).
         <br>
         Note! Only a diversity for a concret home number and <u>without</u> filter for the calling number can be set. Hence, an approbriate <i>diversity</i>-reading must exist.
      </li><br>

      <li><code>set &lt;name&gt; guestWLAN &lt;on|off&gt;</code>
         <br>
         Switches the guest WLAN on or off. The guest password must be set. If necessary, the normal WLAN is also switched on.
      </li><br>

      <li><code>set &lt;name&gt; moh &lt;default|sound|customer&gt; [&lt;MP3FileIncludingPath|say:Text&gt;]</code>
         <br>
         Example: <code>set fritzbox moh customer say:Die Wanne ist voll</code>
         <br>
         <code>set fritzbox moh customer /var/InternerSpeicher/warnung.mp3</code>
         <br>
         Changes the 'music on hold' of the Box. The parameter 'customer' allows to upload a mp3 file. Alternatively a text can be spoken with "say:". The music on hold has <u>always</u> a length of 8.2 s. It is played continousely during the broking of calls or if the modul rings a phone and the call is taken. So, it can be used to transmit little messages of 8 s.
         <br>
      </li><br>

      <li><code>set &lt;name&gt; password &lt;password&gt;</code>
         <br>
         Stores the password for remote telnet access.
      </li><br>

      <li><code>set &lt;name&gt; ring &lt;intNumbers&gt; [duration [ringTone]] [show:Text]  [say:Text | play:MP3URL]</code>
         <dt>Example:</dt>
         <dd>
         <code>set fritzbox ring 611,612 5 Budapest show:It is raining</code>
         <br>
         <code>set fritzbox ring 611 8 say:(en)It is raining</code>
         <br>
         <code>set fritzbox ring 610 10 play:http://raspberrypi/sound.mp3</code>
         </dd>
         Rings the internal numbers for "duration" seconds and (on Fritz!Fons) with the given "ring tone" name.
         Different internal numbers have to be separated by a comma (without spaces).
         <br>
         Default duration is 5 seconds. The Fritz!Box can create further delays. Default ring tone is the internal ring tone of the device.
         Ring tone will be ignored for collected calls (9 or 50). 
         <br>
         If the call is taken the callee hears the "music on hold" which can also be used to transmit messages.
         <br>
         The parameter <i>ringtone, show:, say:</i> and <i>play:</i> require the API Telnet or webcm.
         <br/><br/>
         If the <a href=#FRITZBOXattr>attribute</a> 'ringWithIntern' is specified, the text behind 'show:' will be shown as the callers name.
         Maximal 30 characters are allowed.
         <br/><br/>
         On Fritz!Fons the parameter 'say:' can be used to let the phone speak a message (max. 100 characters) instead of using the ringtone. 
         Alternatively, a MP3 link (from a web server) can be played with 'play:'. This creates the internet radio station 'FHEM' and uses translate.google.com for text2speech. It will <u>always</u> play the complete text/sound. It will than ring with standard ring tone until the end of the 'ring duration' is reached.
         Say and play <u>may</u> work only with one single Fritz!Fon at a time.
         <br>
         The behaviour may vary depending on the Fritz!OS.
      </li><br>

      <li><code>set &lt;name&gt; sendMail [to:&lt;Address&gt;] [subject:&lt;Subject&gt;] [body:&lt;Text&gt;]</code>
         <br>
         Sends an email via the email notification service that is configured in push service of the Fritz!Box. 
         Use "\n" for line breaks in the body.
         All parameters can be omitted. Make sure the messages are not classified as junk by your email client.
         <br>
         Requires Telnet access to the box.
         <br>
      </li><br>

      <li><code>set &lt;name&gt; startRadio &lt;internalNumber&gt; [name or number]</code>
         <br>
         Plays the internet radio on the given Fritz!Fon. Default is the current <u>ring tone</u> radio station of the phone. 
         So, <b>not</b> the station that is selected at the handset.
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

      <li><code>get &lt;name&gt; shellCommand &lt;Command&gt;</code>
         <br>
         Runs the given command on the Fritz!Box shell and returns the result.
         Can be used to run shell commands not included in this modul.
         <br>
         Only available if the attribute "allowShellCommand" is set.
      </li><br>

      <li><code>get &lt;name&gt; tr064Command &lt;service&gt; &lt;control&gt; &lt;action&gt; [[argName1 argValue1] ...] </code>
         <br>
         Executes TR-064 actions (see <a href="http://avm.de/service/schnittstellen/">API description</a> of AVM).
         <br>
         argValues with spaces have to be enclosed in quotation marks.
         <br>
         Example: <code>get Fritzbox tr064Command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetInfo NewDectID 1</code>
         <br>
         Only available if the attribute "allowTR064Command" is set.
      </li><br>

      <li><code>get &lt;name&gt; tr064ServiceListe</code>
         <br>
         Shows a list of TR-064 services and actions that are allowed on the device.
      </li><br>

   </ul>  
  
   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>allowShellCommand &lt;0 | 1&gt;</code>
         <br>
         Enables the get command "shellCommand"
      </li><br>

      <li><code>allowTR064Command &lt;0 | 1&gt;</code>
         <br>
         Enables the get command "tr064Command"
      </li><br>

      <li><code>boxUser &lt;user name&gt;</code>
         <br>
         User name that is used for TR064 or other web based access. By default no user name is required to login.
         <br>
         If the Fritz!Box is configured differently, the user name has to be defined with this attribute.
      </li><br>

      <li><code>defaultCallerName &lt;Text&gt;</code>
         <br>
         The default text to show on the ringing phone as 'caller'.
         <br>
         This is done by temporarily changing the name of the calling internal number during the ring.
         <br>
         Maximal 30 characters are allowed. The attribute "ringWithIntern" must also be specified.
         <br>
         Required API: Telnet or webcmd
      </li><br>

      <li><code>defaultUploadDir &lt;fritzBoxPath&gt;</code>
         <br>
         This is the default path that will be used if a file name does not start with / (slash).
         <br>
         It needs to be the name of the path on the Fritz!Box. So, it should start with /var/InternerSpeicher if it equals in Windows \\ip-address\fritz.nas
      </li><br>

      <li><code>forceTelnetConnection &lt;0 | 1&gt;</code>
         <br>
         Always use telnet for remote access (instead of access via the WebGUI or TR-064).
         <br>
         This attribute should be enabled for older boxes/firmwares.
      </li><br>

      <li><code>fritzBoxIP &lt;IP Address&gt;</code>
         <br>
         Depreciated.
      </li><br>

     <li><code>INTERVAL &lt;seconds&gt;</code>
         <br>
         Polling-Interval. Default is 300 (seconds). Smallest possible value is 60.
      </li><br>

      <li><code>m3uFileLocal &lt;/path/fileName&gt;</code>
         <br>
         Can be used as a work around if the ring tone of a Fritz!Fon cannot be changed because of firmware restrictions (missing telnet or webcm).
         <br>
         How it works: If the FHEM server has also a web server running, the FritzFon can play a m3u file from this web server as an internet radio station.
         For this an internet radio station on the FritzFon must point to the server URL of this file and the internal ring tone must be changed to that station.
         <br>
         If the attribute is set, the server file "m3uFileLocal" (local address of the FritzFon URL) will be filled with the URL of the text2speech engine (say:) or a MP3-File (play:). The FritzFon will then play this URL.
      </li><br>

      <li><code>ringWithIntern &lt;1 | 2 | 3&gt;</code>
         <br>
         To ring a fon a caller must always be specified. Default of this modul is 50 "ISDN:W&auml;hlhilfe".
         <br>
         To show a message (default: "FHEM") during a ring the internal phone numbers 1-3 can be specified here.
         The concerned analog phone socket <u>must</u> exist.
      </li><br>
      
      <li><code>telnetTimeOut &lt;seconds&gt;</code>
         <br>
         Maximal time to wait for an answer during a telnet session. Default is 10 s.
      </li><br>

      <li><code>telnetUser &lt;user name&gt;</code>
         <br>
         User name that is used for telnet access. By default no user name is required to login.
         <br>
         If the Fritz!Box is configured differently, the user name has to be defined with this attribute.
      </li><br>

      <li><code>useGuiHack &lt;0 | 1&gt;</code>
         <br>
         If the APIs do not allow the change of the ring tone (Fritz!OS >6.24), check the <a href="http://www.fhemwiki.de/wiki/FRITZBOX#Klingelton-Einstellung_und_Abspielen_von_Sprachnachrichten_bei_Fritz.21OS-Versionen_.3E6.24">WIKI</a> (German) to understand the use of this attribute.
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
      <br>
      <li><b>box_dect</b> - Current state of the DECT base</li>
      <li><b>box_fwVersion</b> - Firmware version of the box, if outdated then '(old)' is appended</li>
      <li><b>box_guestWlan</b> - Current state of the guest WLAN</li>
      <li><b>box_guestWlanCount</b> - Number of devices connected to guest WLAN</li>
      <li><b>box_guestWlanRemain</b> - Remaining time until the guest WLAN is switched off</li>
      <li><b>box_ipExtern</b> - Internet IP of the Fritz!Box</li>
      <li><b>box_model</b> - Fritz!Box model</li>
      <li><b>box_moh</b> - music-on-hold setting</li>
      <li><b>box_model</b> - Fritz!Box model</li>
      <li><b>box_powerRate</b> - current power in percent of maximal power</li>
      <li><b>box_rateDown</b> - average download rate in the last update interval</li>
      <li><b>box_rateUp</b> - average upload rate in the last update interval</li>
      <li><b>box_stdDialPort</b> - standard caller port when using the dial function of the box</li>
      <li><b>box_tr064</b> - application interface TR-064 (needed by this modul)</li>
      <li><b>box_tr069</b> - provider remote access TR-069 (safety issue!)</li>
      <li><b>box_wlanCount</b> - Number of devices connected via WLAN</li>
      <li><b>box_wlan_2.4GHz</b> - Current state of the 2.4 GHz WLAN</li>
      <li><b>box_wlan_5GHz</b> - Current state of the 5 GHz WLAN</li>
      <br>
      <li><b>dect</b><i>1</i> - Name of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_alarmRingTone</b> - Alarm ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_custRingTone</b> - Customer ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_fwVersion</b> - Firmware Version of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Internal number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Internal ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Manufacturer of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_model</b> - Model of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_radio</b> - Current internet radio station ring tone of the DECT device <i>1</i></li>
      <br>
      <li><b>diversity</b><i>1</i> - Own (incoming) phone number of the call diversity <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_dest</b> - Destination of the call diversity <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_state</b> - Current state of the call diversity <i>1</i></li>
      <br>
      <li><b>fon</b><i>1</i> - Internal name of the analog FON port <i>1</i></li>
      <li><b>fon</b><i>1</i><b>_intern</b> - Internal number of the analog FON port <i>1</i></li>
      <li><b>fon</b><i>1</i><b>_out</b> - Outgoing number of the analog FON port <i>1</i></li>
      <br>
      <li><b>gsm_internet</b> - connection to internet established via GSM stick</li>
      <li><b>gsm_rssi</b> - received signal strength indication (0-100)</li>
      <li><b>gsm_state</b> - state of the connection to the GSM network</li>
      <li><b>gsm_technology</b> - GSM technology used for data transfer (GPRS, EDGE, UMTS, HSPA)</li>
      <br>
      <li><b>mac_</b><i>01_26_FD_12_01_DA</i> - MAC address and name of an active network device.
      <br>
      If connect via WLAN, the term "WLAN" and (from boxes point of view) the down- and upload rate and the signal strength is added. For LAN devices the LAN port and its speed is added. Inactive or removed devices get first the value "inactive" and will be deleted during the next update.</li>
      <br>
      <li><b>radio</b><i>01</i> - Name of the internet radio station <i>01</i></li>
      <br>
      <li><b>tam</b><i>1</i> - Name of the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_newMsg</b> - New messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_oldMsg</b> - Old messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_state</b> - Current state of the answering machine <i>1</i></li>
      <br>
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
<div> 
<ul>
   Steuert gewisse Funktionen eines Fritz!Box Routers. Verbundene Fritz!Fon's (MT-F, MT-D, C3, C4) k&ouml;nnen als Signalger&auml;te genutzt werden. MP3-Dateien und Text (Text2Speech) k&ouml;nnen als Klingelton oder einem angerufenen Telefon abgespielt werden.
   <br>
   F&uuml;r detailierte Anleitungen bitte die <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki</b></a> konsultieren und erg&auml;nzen.
   <br/><br/>
   Das Modul schaltet in den lokalen Modus, wenn FHEM auf einer Fritz!Box l&auml;uft (als root-Benutzer!). Ansonsten versucht es eine Web oder Telnet Verbindung zu "fritz.box" zu &ouml;ffnen. D.h. Telnet (#96*7*) muss auf der Fritz!Box erlaubt sein. F&uuml;r diesen Fernzugriff muss <u>einmalig</u> das Passwort gesetzt werden.
   <br/><br/>
   Die Steuerung erfolgt teilweise &uuml;ber die offizielle TR-064-Schnittstelle und teilweise &uuml;ber undokumentierte Schnittstellen zwischen Webinterface und Firmware Kern. Das Modul funktioniert am besten mit dem Fritz!OS 6.24. Bei den nachfolgenden Fritz!OS Versionen hat AVM einige interne Schnittstellen (telnet, webcm) ersatzlos gestrichen. <b>Einige Modul-Funktionen sind dadurch nicht oder nur eingeschr&auml;nkt verf&uuml;gbar (siehe Anmerkungen zu ben&ouml;tigten API).</b>
   <br>
   Bitte auch die anderen Fritz!Box-Module beachten: <a href="#SYSMON">SYSMON</a> und <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>Das Modul nutzt das Perlmodule 'Net::Telnet', 'JSON::XS', 'LWP', 'SOAP::Lite' f&uuml;r den Fernzugriff.</i>
   <br/><br/>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX [host]</code>
      <br/>
      Das Attribut <i>host</i> ist die Web-Adresse (Name oder IP) der Fritz!Box. Fehlt es, so schaltet das Modul in den lokalen Modus oder nutzt die Standardadresse "fritz.box".
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
      <li><code>set &lt;name&gt; alarm &lt;Nummer&gt; [on|off] [time] [once|daily|Mo|Tu|We|Th|Fr|Sa|So]</code>
         <br>
         Schaltet den Weckruf Nummer 1, 2 oder 3 an oder aus (Standard ist on). Setzt die Zeit und den Wochentag.
         <br>
         Ben&ouml;tigt die API: Telnet oder webcm.
      </li><br>

      <li><code>set &lt;name&gt; call &lt;number&gt; [Dauer] [say:Text|play:MP3URL]</code>
         <br>
         Ruf f&uuml;r 'Dauer' Sekunden (Standard 60 s) die angegebene Telefonnummer von einem internen Telefonanschluss an (Standard ist 1 oder das Attribut 'ringWithIntern'). Wenn der Angerufene abnimmt, h&ouml;rt er die Wartemusik oder den angegebenen Text oder Klang.
         Der interne Telefonanschluss klingelt ebenfalls.
         <br>
         "say:" und "play:" ben&ouml;tigen die API: Telnet oder webcm.
      </li><br>

      <li><code>set &lt;name&gt; checkAPIs</code>
         <br>
         Startet eine erneute Abfrage der exitierenden Programmierschnittstellen der FRITZ!BOX.
      </li><br>

      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;MP3DateiInklusivePfad&gt;</code>
         <br>
         L&auml;dt die MP3-Datei als Klingelton auf das angegebene Telefon. Die Datei muss im Dateisystem der Fritzbox liegen.
         <br>
         Das Hochladen dauert etwa eine Minute bis der Klingelton verf&uuml;gbar ist. (API: Telnet)
      </li><br>

      <li><code>set &lt;name&gt; dect &lt;on|off&gt;</code>
         <br>
         Schaltet die DECT-Basis der Box an oder aus.
         <br>
         Ben&ouml;tigt die API: Telnet oder webcm.
      </li><br>

      <li><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code>
         <br>
         Schaltet die Rufumleitung (Nummer 1, 2 ...) f&uuml;r einzelne Rufnummern an oder aus.
         <br>
         Die Rufumleitung muss zuvor auf der Fritz!Box eingerichtet werden. Ben&ouml;tigt die API: Telnet oder webcm.
         <br>
         Achtung! Es lassen sich nur Rufumleitungen f&uuml;r einzelne angerufene Telefonnummern (also nicht "alle") und <u>ohne</u> Abh&auml;ngigkeit von der anrufenden Nummer schalten. 
         Es muss also ein <i>diversity</i>-Ger&auml;wert geben.
         <br>
         Ben&ouml;tigt die API: Telnet, webcm oder TR064 (>=6.50).
      </li><br>

      <li><code>set &lt;name&gt; guestWLAN &lt;on|off&gt;</code>
         <br>
         Schaltet das G&auml;ste-WLAN an oder aus. Das G&auml;ste-Passwort muss gesetzt sein. Wenn notwendig wird auch das normale WLAN angeschaltet.
      </li><br>

      <li><code>set &lt;name&gt; moh &lt;default|sound|customer&gt; [&lt;MP3DateiInklusivePfad|say:Text&gt;]</code>
         <br>
         Beispiel: <code>set fritzbox moh customer say:Die Wanne ist voll</code>
         <br>
         <code>set fritzbox moh customer /var/InternerSpeicher/warnung.mp3</code>
         <br>
         &Auml;ndert die Wartemusik ('music on hold') der Box. Mit dem Parameter 'customer' kann eine eigene MP3-Datei aufgespielt werden.
         Alternativ kann mit "say:" auch ein Text gesprochen werden. Die Wartemusik hat <u>immer</u> eine L&auml;nge von 8,13 s. Sie wird kontinuierlich w&auml;hrend des Makelns von Gespr&auml;chen aber auch bei Nutzung der internen W&auml;hlhilfe bis zum Abheben des rufenden Telefons abgespielt. Dadurch k&ouml;nnen &uuml;ber FHEM dem Angerufenen 8s-Nachrichten vorgespielt werden.
         <br>
      </li><br>
      
      <li><code>set &lt;name&gt; password &lt;Passwort&gt;</code>
         <br>
         Speichert das Passwort f&uuml;r den Fernzugriff &uuml;ber Telnet.
      </li><br>

      <li><code>set &lt;name&gt; ring &lt;intNummern&gt; [Dauer [Klingelton]] [show:Text] [say:Text | play:Link]</code>
         <dt>Beispiel:</dt>
         <dd>
         <code>set fritzbox ring 611,612 5 Budapest show:Es regnet</code>
         <br>
         <code>set fritzbox ring 610 8 say:Es regnet</code>
         <br>
         <code>set fritzbox ring 610 10 play:http://raspberrypi/sound.mp3</code>
         </dd>
         L&auml;sst die internen Nummern f&uuml;r "Dauer" Sekunden und (auf Fritz!Fons) mit dem angegebenen "Klingelton" klingeln.
         <br>
         Mehrere interne Nummern m&uuml;ssen durch ein Komma (ohne Leerzeichen) getrennt werden.
         <br>
         Standard-Dauer ist 5 Sekunden. Es kann aber zu Verz&ouml;gerungen in der Fritz!Box kommen. Standard-Klingelton ist der interne Klingelton des Ger&auml;tes.
         Der Klingelton wird f&uuml;r Rundrufe (9 oder 50) ignoriert. 
         <br>
         Wenn der Anruf angenommen wird, h&ouml;rt der Angerufene die Wartemusik (music on hold), welche ebenfalls zur Nachrichten&uuml;bermittlung genutzt werden kann.
         <br>
         Die Parameter <i>Klingelton, show:, say:</i> und <i>play:</i> ben&ouml;tigen die API Telnet oder webcm.
         <br/><br/>
         Wenn das <a href=#FRITZBOXattr>Attribut</a> 'ringWithIntern' existiert, wird der Text hinter 'show:' als Name des Anrufers angezeigt.
         Er darf maximal 30 Zeichen lang sein.
         <br/><br/>
         Auf Fritz!Fons wird der Text (max. 100 Zeichen) hinter dem Parameter 'say:' direkt angesagt und ersetzt den Klingelton.
         <br>
         Alternativ kann mit 'play:' auch ein MP3-Link (vom einem Webserver) abgespielt werden. Dabei wird die Internetradiostation 39 'FHEM' erzeugt und translate.google.com f&uuml;r Text2Speech genutzt. Es wird <u>immer</u> der komplette Text/Klang abgespielt. Bis zum Ende der 'Klingeldauer' klingelt das Telefon dann mit seinem Standard-Klingelton.
         Das Abspielen ist eventuell nicht auf mehreren Fritz!Fons gleichzeitig m&ouml;glich.
         <br>
         Je nach Fritz!OS kann das beschriebene Verhalten abweichen.
         <br>
      </li><br>

      <li><code>set &lt;name&gt; sendMail [to:&lt;Address&gt;] [subject:&lt;Subject&gt;] [body:&lt;Text&gt;]</code>
         <br>
         Sendet eine Email &uuml;ber den Emailbenachrichtigungsservice der als Push Service auf der Fritz!Box konfiguriert wurde.
         Mit "\n" kann einen Zeilenumbruch im Textk&ouml;rper erzeut werden.
         Alle Parameter k&ouml;nnen ausgelassen werden. Bitte kontrolliert, dass die Email nicht im Junk-Verzeichnis landet.
         <br>
         Ben&ouml;tigt einen Telnet Zugang zur Box.
         <br>
      </li><br>
      
      <li><code>set &lt;name&gt; startRadio &lt;internalNumber&gt; [Name oder Nummer]</code>
         <br>
         Startet das Internetradio auf dem angegebenen Fritz!Fon. Eine verf&uuml;gbare Radiostation kann &uuml;ber den Namen oder die (Ger&auml;tewert)Nummer ausgew&auml;hlt werden. Ansonsten wird die in der Box als Internetradio-Klingelton eingestellte Station abgespielt. (Also <b>nicht</b> die am Telefon ausgew&auml;hlte.)
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

      <li><code>get &lt;name&gt; shellCommand &lt;Befehl&gt;</code>
         <br>
         F&uuml;hrt den angegebenen Befehl auf der Fritz!Box-Shell aus und gibt das Ergebnis zur&uuml;ck.
         Kann benutzt werden, um Shell-Befehle auszuf&uuml;hren, die nicht im Modul implementiert sind.
         <br>
         Muss zuvor &uuml;ber das Attribute "allowShellCommand" freigeschaltet werden.
      </li><br>

      <li><code>get &lt;name&gt; tr064Command &lt;service&gt; &lt;control&gt; &lt;action&gt; [[argName1 argValue1] ...] </code>
         <br>
         F&uuml;hrt &uuml;ber TR-064 Aktionen aus (siehe <a href="http://avm.de/service/schnittstellen/">Schnittstellenbeschreibung</a> von AVM).
         <br>
         argValues mit Leerzeichen m&uuml;ssen in Anf&uuml;hrungszeichen eingeschlossen werden.
         <br>
         Beispiel: <code>get Fritzbox tr064Command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetInfo NewDectID 1</code>
         <br>
         Muss zuvor &uuml;ber das Attribute "allowTR064Command" freigeschaltet werden.
      </li><br>

      <li><code>get &lt;name&gt; tr064ServiceListe</code>
         <br>
         Zeigt die Liste der TR-064-Dienste und Aktionen, die auf dem Ger&auml;t erlaubt sind.
      </li><br>
   </ul>  
  
   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>allowShellCommand &lt;0 | 1&gt;</code>
         <br>
         Freischalten des get-Befehls "shellCommand"
      </li><br>
      
      <li><code>allowTR064Command &lt;0 | 1&gt;</code>
         <br>
         Freischalten des get-Befehls "tr064Command"
      </li><br>
      
      <li><code>boxUser &lt;user name&gt;</code>
         <br>
         Benutzername f&uuml;r den TR064- oder einen anderen webbasierten Zugang. Normalerweise wird keine Benutzername f&uuml;r das Login ben&ouml;tigt.
         Wenn die Fritz!Box anders konfiguriert ist, kann der Nutzer &uuml;ber dieses Attribut definiert werden.
      </li><br>
    
      <li><code>defaultCallerName &lt;Text&gt;</code>
         <br>
         Standard-Text, der auf dem angerufenen internen Telefon als "Anrufer" gezeigt wird.
         <br>
         Dies erfolgt, indem w&auml;hrend des Klingelns tempor&auml;r der Name der internen anrufenden Nummer ge&auml;ndert wird.
         <br>
         Es sind maximal 30 Zeichen erlaubt. Das Attribute "ringWithIntern" muss ebenfalls spezifiziert sein.
         <br>
         Ben&ouml;tigt die API: Telnet oder webcmd      
         </li><br>
      
      <li><code>defaultUploadDir &lt;fritzBoxPath&gt;</code>
         <br>
         Dies ist der Standard-Pfad der f&uuml;r Dateinamen benutzt wird, die nicht mit einem / (Schr&auml;gstrich) beginnen.
         <br>
         Es muss ein Pfad auf der Fritz!Box sein. D.h., er sollte mit /var/InternerSpeicher starten, wenn es in Windows unter \\ip-address\fritz.nas erreichbar ist.
      </li><br>

      <li><code>forceTelnetConnection &lt;0 | 1&gt;</code>
         <br>
         Erzwingt den Fernzugriff &uuml;ber Telnet (anstatt &uuml;ber die WebGUI oder TR-064).
         <br>
         Dieses Attribut muss bei &auml;lteren Ger&auml;ten/Firmware aktiviert werden.
      </li><br>

      <li><code>fritzBoxIP &lt;IP-Adresse&gt;</code>
         <br>
         Veraltet.
      </li><br>
     
      <li><code>INTERVAL &lt;Sekunden&gt;</code>
         <br>
         Abfrage-Interval. Standard ist 300 (Sekunden). Der kleinste m&ouml;gliche Wert ist 60.
      </li><br>

      <li><code>ringWithIntern &lt;1 | 2 | 3&gt;</code>
         <br>
         Um ein Telefon klingeln zu lassen, muss in der Fritzbox eine Anrufer (W&auml;hlhilfe, Wert 'box_stdDialPort') spezifiziert werden.
         <br>
         Um w&auml;hrend des Klingelns eine Nachricht (Standard: "FHEM") anzuzeigen, kann hier die interne Nummer 1-3 angegeben werden.
         Der entsprechende analoge Telefonanschluss muss vorhanden sein.
      </li><br>

      <li><code>telnetTimeOut &lt;Sekunden&gt;</code>
         <br>
         Maximale Zeit, bis zu der w&auml;hrend einer Telnet-Sitzung auf Antwort gewartet wird. Standard ist 10 s.
      </li><br>

      <li><code>telnetUser &lt;user name&gt;</code>
         <br>
         Benutzername f&uuml;r den Telnetzugang. Normalerweise wird keine Benutzername f&uuml;r das Login ben&ouml;tigt.
         Wenn die Fritz!Box anders konfiguriert ist, kann der Nutzer &uuml;ber dieses Attribut definiert werden.
      </li><br>
    
      <li><code>useGuiHack &lt;0 | 1&gt;</code>
         <br>
         Falls die APIs der Box nicht mehr die &Auml;nderung des Klingeltones unterst&uuml;tzen (Fritz!OS >6.24), kann dieses Attribute entsprechend der <a href="http://www.fhemwiki.de/wiki/FRITZBOX#Klingelton-Einstellung_und_Abspielen_von_Sprachnachrichten_bei_Fritz.21OS-Versionen_.3E6.24">WIKI-Anleitung</a> genutzt werden.
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
      <br>
      <li><b>box_dect</b> - Aktueller Status des DECT-Basis</li>
      <li><b>box_fwVersion</b> - Firmware-Version der Box, wenn veraltet dann wird '(old)' angehangen</li>
      <li><b>box_guestWlan</b> - Aktueller Status des G&auml;ste-WLAN</li>
      <li><b>box_guestWlanCount</b> - Anzahl der Ger&auml;te die &uuml;ber das G&auml;ste-WLAN verbunden sind</li>
      <li><b>box_guestWlanRemain</b> - Verbleibende Zeit bis zum Ausschalten des G&auml;ste-WLAN</li>
      <li><b>box_ipExtern</b> - Internet IP der Fritz!Box</li>
      <li><b>box_model</b> - Fritz!Box-Modell</li>
      <li><b>box_moh</b> - Wartemusik-Einstellung</li>
      <li><b>box_powerRate</b> - aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_rateDown</b> - Download-Geschwindigkeit des letzten Intervals in kByte/s</li>
      <li><b>box_rateUp</b> - Upload-Geschwindigkeit des letzten Intervals in kByte/s</li>
      <li><b>box_stdDialPort</b> - Anschluss der ger&auml;teseitig von der W&auml;hlhilfe genutzt wird</li>
      <li><b>box_tr064</b> - Anwendungsschnittstelle TR-064 (wird auch von diesem Modul ben&ouml;tigt)</li>
      <li><b>box_tr069</b> - Provider-Fernwartung TR-069 (sicherheitsrelevant!)</li>
      <li><b>box_wlanCount</b> - Anzahl der Ger&auml;te die &uuml;ber WLAN verbunden sind</li>
      <li><b>box_wlan_2.4GHz</b> - Aktueller Status des 2.4-GHz-WLAN</li>
      <li><b>box_wlan_5GHz</b> - Aktueller Status des 5-GHz-WLAN</li>
      
      <br>
      <li><b>dect</b><i>1</i> - Name des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_alarmRingTone</b> - Klingelton beim Wecken &uuml;ber das DECT Telefon <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_custRingTone</b> - Benutzerspezifischer Klingelton des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_fwVersion</b> - Firmware-Version des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Interne Nummer des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Interner Klingelton des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Hersteller des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_model</b> - Modell des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_radio</b> - aktueller Internet-Radio-Klingelton des DECT Telefons <i>1</i></li>
      <br>
      <li><b>diversity</b><i>1</i> - Eigene Rufnummer der Rufumleitung <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_dest</b> - Zielnummer der Rufumleitung <i>1</i></li>
      <li><b>diversity</b><i>1</i><b>_state</b> - Aktueller Status der Rufumleitung <i>1</i></li>
      <br>
      <li><b>fon</b><i>1</i> - Name des analogen Telefonanschlusses <i>1</i> an der Fritz!Box</li>
      <li><b>fon</b><i>1</i><b>_intern</b> - Interne Nummer des analogen Telefonanschlusses <i>1</i></li>
      <li><b>fon</b><i>1</i><b>_out</b> - ausgehende Nummer des Anschlusses <i>1</i></li>
      <br>
      <li><b>gsm_internet</b> - Internetverbindung errichtet &uuml;ber Mobilfunk-Stick </li>
      <li><b>gsm_rssi</b> - Indikator der empfangenen GSM-Signalst&auml;rke (0-100)</li>
      <li><b>gsm_state</b> - Status der Mobilfunk-Verbindung</li>
      <li><b>gsm_technology</b> - GSM-Technologie, die f&uuml;r die Daten&uuml;bertragung genutzt wird (GPRS, EDGE, UMTS, HSPA)</li>
      <br>
      <li><b>mac_</b><i>01_26_FD_12_01_DA</i> - MAC Adresse und Name eines aktiven Netzwerk-Ger&auml;tes.
      <br>
      Bei einer WLAN-Verbindung wird "WLAN" und (von der Box gesehen) die Sende- und Empfangsgeschwindigkeit und die Empfangsst&auml;rke angehangen. Bei einer LAN-Verbindung wird der LAN-Port und die LAN-Geschwindigkeit angehangen. Gast-Verbindungen werden mit "gWLAN" oder "gLAN" gekennzeichnet.
      <br>
      Inaktive oder entfernte Ger&auml;te erhalten zuerst den Werte "inactive" und werden beim n&auml;chsten Update gel&ouml;scht.</li>
      <br>
      <li><b>radio</b><i>01</i> - Name der Internetradiostation <i>01</i></li>
      <br>
      <li><b>tam</b><i>1</i> - Name des Anrufbeantworters <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_newMsg</b> - Anzahl neuer Nachrichten auf dem Anrufbeantworter <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_oldMsg</b> - Anzahl alter Nachrichten auf dem Anrufbeantworter <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_state</b> - Aktueller Status des Anrufbeantworters <i>1</i></li>
      <br>
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