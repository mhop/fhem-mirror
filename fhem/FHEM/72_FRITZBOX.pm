###############################################################
# $Id$
#
#  72_FRITZBOX.pm
#
#  (c) 2014 Torsten Poitzsch
#  (c) 2014-2020 tupol http://forum.fhem.de/index.php?action=profile;u=5432
#  (c) 2021-2023 jowiemann https://forum.fhem.de/index.php?action=profile
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
use HttpUtils;

my $ModulVersion = "07.50.9b";
my $missingModul = "";
my $missingModulWeb = "";
my $missingModulTR064 = "";
my $FRITZBOX_TR064pwd;
my $FRITZBOX_TR064user;

eval "use URI::Escape;1" or $missingModul .= "URI::Escape ";
eval "use MIME::Base64;1" or $missingModul .= "MIME::Base64 ";

use FritzBoxUtils; ## only for web access login

#sudo apt-get install libjson-perl
# eval "use JSON::XS;1" or $missingModulWeb .= "JSON::XS ";
eval "use JSON;1" or $missingModulWeb .= "JSON ";

eval "use LWP::UserAgent;1" or $missingModulWeb .= "LWP::UserAgent ";
eval "use URI::Escape;1" or $missingModulTR064 .= "URI::Escape ";

# sudo apt-get install libsoap-lite-perl
eval "use SOAP::Lite;1" or $missingModulTR064 .= "Soap::Lite ";

eval "use Data::Dumper;1" or $missingModulTR064 .= "Data::Dumper ";

sub FRITZBOX_Log($$$);
sub FRITZBOX_Initialize($);
sub FRITZBOX_Set_Cmd_Start($);
sub FRITZBOX_StartRadio_Web($@);
sub FRITZBOX_Readout_Add_Reading ($$$$@);
sub FRITZBOX_Readout_Process($$);
sub FRITZBOX_SendMail_Shell($@);
sub FRITZBOX_SetCustomerRingTone($@);
sub FRITZBOX_SetMOH($@);
sub FRITZBOX_TR064_Init($$);
sub FRITZBOX_Wlan_Run($);
sub FRITZBOX_Web_Query($$@);
sub FRITZBOX_Lua_Data($$@);
sub FRITZBOX_Process_JSON($$$@);
sub FRITZBOX_ERR_Result($$;@);
sub FRITZBOX_Run_GuestWlan_Web($);
sub FRITZBOX_Run_Call_Web($);
sub FRITZBOX_Run_macFilter($);
sub FRITZBOX_Run_chgProfile($);
sub FRITZBOX_Run_lockLandevice($);
sub FRITZBOX_Run_enableVPNshare($);
sub FRITZBOX_Run_rescan_neighborhood($);

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
my $mohOld    = '/var/tmp/fhem_fx_moh_old';
my $mohNew    = '/var/tmp/fhem_fx_moh_new';

#######################################################################
sub FRITZBOX_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];

   my $xsubroutine = ( caller(1) )[3];

   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//       if ( defined $sub );
   $sub ||= 'no-subroutine-specified';

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;

   my $avmModel = InternalVal($instName, "MODEL", "0000");
   $avmModel = $1 if $avmModel =~ m/(\d+)/;

   Log3 $hash, $loglevel, "FRITZBOX!$avmModel [$instName: $sub.$xline] - " . $text;

} # End FRITZBOX_Log

#######################################################################
sub FRITZBOX_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRITZBOX_Define";
  $hash->{UndefFn}  = "FRITZBOX_Undefine";
  $hash->{DeleteFn} = "FRITZBOX_Delete";
  $hash->{RenameFn} = "FRITZBOX_Rename";

  $hash->{SetFn}    = "FRITZBOX_Set";
  $hash->{GetFn}    = "FRITZBOX_Get";
  $hash->{AttrFn}   = "FRITZBOX_Attr";
  $hash->{AttrList} = "boxUser "
#               ."allowTR064Command:0,1 ";
                ."disable:0,1 "
#                ."defaultCallerName "
#                ."defaultUploadDir "
                ."fritzBoxIP "
                ."INTERVAL "
                ."m3uFileLocal "
                ."m3uFileURL "
#                ."ringWithIntern:0,1,2 "
#                ."useGuiHack:0,1 "
                ."userTickets "
                ."enablePassivLanDevices:0,1 "
                ."enableVPNShares:0,1 "
                ."enableUserInfo:0,1 "
                ."enableAlarmInfo:0,1 "
                ."enableWLANneighbors:0,1 "
                ."wlanNeighborsPrefix "
                ."disableDectInfo:0,1 "
                ."disableFonInfo:0,1 "
                ."enableSIP:0,1 "
                ."disableBoxReadings:multiple-strict,box_connect,box_cpuTemp,box_dect,box_dsl_downStream,box_dsl_upStream,"
                                ."box_guestWlan,box_guestWlanCount,box_guestWlanRemain,box_macFilter_active,box_ipExtern,box_ipv6Extern,"
                                ."box_ipv6Prefix,box_last_connect_err,box_moh,box_powerRate,box_rateDown,"
                                ."box_rateUp,box_stdDialPort,box_tr064,box_tr069,box_uptimeConnect,box_uptime,box_wlanCount,box_wlan_2.4GHz,"
                                ."box_wlan_5GHz,box_vdsl_downStreamRate,box_vdsl_upStreamRate "
                ."deviceInfo:sortable,ipv4,name,uid,connection,speed,rssi,_noDefInf_ "
                ."disableTableFormat:multiple-strict,border(8),cellspacing(10),cellpadding(20) "
                .$readingFnAttributes;

} # end FRITZBOX_Initialize

#######################################################################
sub FRITZBOX_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Usage: define <name> FRITZBOX [IP address]" if(@args <2 || @args >3);

   return "Error: no valid IPv4 Address: $args[2]" if defined $args[2] && $args[2] !~ m/^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/;

   my $name = $args[0];

   $hash->{NAME}    = $name;
   $hash->{VERSION} = $ModulVersion;

   $hash->{HOST} = "undefined";
   $hash->{HOST} = $args[2]     if defined $args[2] && $args[2] =~ m/^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/;
   $hash->{fhem}{definedHost} = $hash->{HOST}; # to cope with old attribute definitions

   my $msg;
# stop if certain perl moduls are missing
   if ( $missingModul ) {
      $msg = "ERROR: Cannot define a FRITZBOX device. Perl modul $missingModul is missing.";
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
   $hash->{LUADATA}  = -1;
   $hash->{TR064}    = -1;
   
   RemoveInternalTimer($hash->{helper}{TimerReadout});
   InternalTimer(gettimeofday() + 1 , "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 0);

# Inform about missing PERL modules
   if ( $missingModulWeb || $missingModulTR064 ) {
      my $msg = "INFO: Modul functionality limited because of missing perl modules: " . $missingModulWeb . $missingModulTR064;
      FRITZBOX_Log $hash, 2, $msg;
      $hash->{PERL} = $msg;
   } else {
      my $msg = "The support for telnet and operation on a Fritz!Box has been discontinued. The functions are disabled.";
      FRITZBOX_Log $hash, 2, $msg;
      $hash->{INFO} = $msg;
      $msg = "The following attributes are not longer supported:\n"
           . "useGuiHack, ringWithIntern, defaultCallerName, allowTR064Command,\n"
           . "forceTelnetConnection, telnetUser, telnetTimeOut\n"
           . "Use deleteattr to delete from Attributes.";
      FRITZBOX_Log $hash, 2, $msg;
      $hash->{INFO2} = $msg;
   }

   CommandDeleteAttr(undef,"$hash useGuiHack -silent");
   CommandDeleteAttr(undef,"$hash ringWithIntern -silent");
   CommandDeleteAttr(undef,"$hash defaultCallerName -silent");
   CommandDeleteAttr(undef,"$hash allowTR064Command -silent");
   CommandDeleteAttr(undef,"$hash forceTelnetConnection -silent");
   CommandDeleteAttr(undef,"$hash telnetUser -silent");
   CommandDeleteAttr(undef,"$hash telnetTimeOut -silent");

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

###############################################################################
# Expression r�guli�re pour valider une URL en Perl                           #
# Regular expression for URL validation in Perl                               #
#                                                                             #
# La sous-routine url_regex fournit l'expression r�guli�re pour valider une   #
# URL. Ne sont pas reconnus les noms de domaine en punycode et les addresses  #
# IPv6.                                                                       #
# The url_regex subroutine returns the regular expression used to validate an #
# URL. Domain names in punycode and IPv6 adresses are not recognized.         #
#                                                                             #
# La liste de tests est celle publi�e � l'adresse suivante, except� deux      #
# cas qui sont donn�s comme faux, alors qu'ils sont justes.                   #
# The test list is the one published at the following adress, except for two  #
# cases given as false, although they are correct.                            #
#                                                                             #
# https://mathiasbynens.be/demo/url-regex                                     #
#                                                                             #
# Droit d'auteur // Copyright                                                 #
# ===========================                                                 #
#                                                                             #
# Auteur // Author : Guillaume Lestringant                                    #
#                                                                             #
# L'expression r�guli�re est tr�s largement bas�e sur celle publi�e par       #
# Diego Perini sous licence MIT (https://gist.github.com/dperini/729294).     #
# Voir plus loin le texte de ladite licence (en anglais seulement).           #
# The regular expression is very largely based on the one published by        #
# Diego Perini under MIT license (https://gist.github.com/dperini/729294).    #
# See further for the text of sayed license.                                  #
#                                                                             #
# Le pr�sent code est plac� sous licence CeCIll-B, dont le texte se trouve �  #
# l'adresse http://cecill.info/licences/Licence_CeCILL-B_V1-fr.html           #
# This actual code is released under CeCIll-B license, whose text can be      #
# found at the adress http://cecill.info/licences/Licence_CeCILL-B_V1-en.html #
# It is an equivalent to BSD license, but valid under French law.             #
###############################################################################
sub FRITZBOX_Url_Regex {
    my $proto = "(?:https?|ftp)://";
    my $id = "?:\\S+(?::\\S*)?@";
    my $ip_excluded = "(?!(?:10|127)(?:\\.\\d{1,3}){3})"
        . "(?!(?:169\\.254|192\\.168)(?:\\.\\d{1,3}){2})"
        . "(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})";
    my $ip_included = "(?:1\\d\\d|2[01]\\d|22[0-3]|[1-9]\\d?)"
        . "(?:\\.(?:2[0-4]\\d|25[0-5]|1?\\d{1,2})){2}"
        . "(?:\\.(?:1\\d\\d|2[0-4]\\d|25[0-4]|[1-9]\\d?))";
#    my $ip = "$ip_excluded$ip_included";
    my $ip = "$ip_included";
    my $chars = "a-z\\x{00a1}-\\x{ffff}";
    my $base = "(?:[${chars}0-9]-*)*[${chars}0-9]+";
    my $host = "(?:$base)";
    my $domain = "(?:\\.$base)*";
    my $tld = "(?:\\.(?:[${chars}]{2,}))";
    my $fulldomain = $host . $domain . $tld . "\\.?";
    my $name = "(?:$ip|$fulldomain)";
    my $port = "(?::\\d{2,5})?";
    my $path = "(?:[/?#]\\S*)?";

#    return "^($proto($id)?$name$port$path)\$";
    return "^($name)\$";
}

#######################################################################
sub FRITZBOX_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value

   my $hash = $defs{$name};

   my $URL_MATCH = FRITZBOX_Url_Regex();

   if ($aName eq "fritzBoxIP") {
     if ($cmd eq "set") {
       return "plain IPv4/URL (without http(s)) or valid IPv4/URL recommended" if $aVal !~ m=$URL_MATCH=i;
       $hash->{HOST} = $aVal;
     }
     else {
       $hash->{HOST} = $hash->{fhem}{definedHost};
     }
   }

   if ($aName eq "deviceInfo") {
     if ($cmd eq "set") {
       my $count = () = ($aVal . ",") =~ m/_default_(.*?)\,/g;
       return "only one _default_... parameter possible" if $count > 1;
        
       return "character | not possible in _default_" if $aVal =~ m/\|/;

#       $aVal =~ s/\,/\,\n/g;
#       $_[3] = $aVal;
     }
   }

   if ($aName eq "disableBoxReadings") {
     if ($cmd eq "set") {
       my @reading_list = split(/\,/, $aVal);
       foreach ( @reading_list ) {
         readingsDelete($hash, $_) if exists $hash->{READINGS}{$_};
       }
#       $aVal =~ s/\,/\,\n/g;
#       $_[3] = $aVal;
     } 
   }

   if ($aName eq "enableVPNShares") {
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^vpn(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableSIP") {
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^sip(\d+)_/ && defined $hash->{READINGS}{$_}{VAL};
       }
       readingsDelete($hash, "sip_error");
     }
   }

   if ($aName eq "enableUserInfo") {
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^user(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableAlarmInfo") {
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^alarm(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "wlanNeighborsPrefix") {
     my $nbhPrefix = AttrVal( $name, "wlanNeighborsPrefix",  "nbh_" );
     if ($cmd eq "del") {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^${nbhPrefix}.*/ && defined $hash->{READINGS}{$_}{VAL};
       }
     } elsif($cmd eq "set") {
       return "no valid prefix: $aVal" if !goodReadingName($aVal);
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^${nbhPrefix}.*/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableWLANneighbors") {
     if ($cmd eq "del" || $aVal == 0) {
       my $nbhPrefix = AttrVal( $name, "wlanNeighborsPrefix",  "nbh_" );
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^${nbhPrefix}.*/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "disableDectInfo") {
     if ($cmd eq "del" || $aVal == 1) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^dect(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "disableFonInfo") {
     if ($cmd eq "del" || $aVal == 1) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^fon(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   # Stop the sub if FHEM is not initialized yet
   return undef    unless $init_done;

   if ( $aName =~ /fritzBoxIP|m3uFileLocal|m3uFileURL/ && $hash->{APICHECKED} == 1 || $aName eq "disable" ) {
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
   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   my $list =  " checkAPIs:noArg"
            .  " password"
            .  " update:noArg";

# set abh�ngig von TR064
   $list    .= " call"
            .  " diversity"
            .  " ring"
            .  " tam"
            if $hash->{TR064} == 1 && $hash->{SECPORT} && ($hash->{MODEL} =~ "Box") && $mesh eq "master";

# set abh�ngig von TR064 und luaCall
   $list    .= " wlan:on,off"
            .  " guestWlan:on,off"
            if $hash->{TR064} == 1 && $hash->{SECPORT} && $hash->{LUAQUERY} == 1;

   $list    .= " wlan2.4:on,off"
            .  " wlan5:on,off"
            if $hash->{fhem}->{is_double_wlan} == 1 && $hash->{TR064} == 1 && $hash->{SECPORT} && $hash->{LUAQUERY} == 1;

# set abh�ngig von TR064 und data.lua
   $list    .= " macFilter:on,off"
            .  " enableVPNshare"
            if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $hash->{TR064} == 1 && $hash->{SECPORT}  && $mesh eq "master";

# set abh�ngig von data.lua
   $list    .= " switchIPv4DNS:provider,other"
            .  " dect:on,off"
            .  " dectRingblock"
            .  " lockLandevice"
            .  " macFilter:on,off"
            .  " chgProfile"
            if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $mesh eq "master";

#   $list    .= " alarm"
#            .  " startRadio";

   $list    .= " rescanWLANneighbors:noArg"
            if ($hash->{LUADATA} == 1);

#   $list    .= " sendMail"
#            .  " customerRingTone"
#            .  " moh"
#            if $hash->{TELNET}==1;

            # . " convertMOH"
            # . " convertRingTone"

# set alarm
#   if ( lc $cmd eq 'alarm') {
#      if ( int @val > 0 && $val[0] =~ /^(1|2|3)$/ ) {
#         FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);
#      }
#
#   }
# set call
   if ( lc $cmd eq 'call' && $mesh eq "master") {
      if (int @val >= 0 && int @val <= 2) {
         FRITZBOX_Log $hash, 3, "DEBUG: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "call ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }         

   # } elsif ( lc $cmd eq 'convertmoh') {
      # if (int @val > 0)
      # {
         # FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);
         # return FRITZBOX_ConvertMOH $hash, @val;
      # }

   # } elsif ( lc $cmd eq 'convertringtone') {
      # if (int @val > 0)
      # {
         # FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);
         # return FRITZBOX_ConvertRingTone $hash, @val;
      # }
   }
   elsif ( lc $cmd eq 'checkapis') {
      FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);
      $hash->{APICHECKED} = 0;
      $hash->{fhem}{sidTime} = 0;
      $hash->{fhem}{LOCAL} = 1;
      FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL} = 0;
      return undef;
#   }
#   elsif ( lc $cmd eq 'customerringtone') {
#      if (int @val > 0)
#      {
#         FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);
#      }

   }
   elsif ( lc $cmd eq 'dect' && $mesh eq "master") {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);

         if ($hash->{LUADATA}==1) {
           # xhr 1 activateDect off apply nop lang de page dectSet

           my @webCmdArray;
           my $returnStr;

           push @webCmdArray, "xhr"            => "1";
           push @webCmdArray, "activateDect"   => $val[0];
           push @webCmdArray, "apply"          => "";
           push @webCmdArray, "lang"           => "de";
           push @webCmdArray, "page"           => "dectSet";

           FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd \n" . join(" ", @webCmdArray);

           my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

           my $tmp;
           if (defined $result->{Error} ) {
             $tmp = "ERROR: " . $result->{Error};
             FRITZBOX_Log $hash, 2, "ERROR: dectringblock " . $val[0] . " - " . $tmp;
           } elsif (defined $result->{sid} ) {
             if (defined $result->{data}->{vars}->{dectEnabled}) {
               readingsSingleUpdate($hash,"box_dect",$val[0], 1);
               $tmp = $result->{data}->{vars}->{dectEnabled} ? "DECT aktiv" : "DECT inaktiv";
               return $tmp;
             } else {
               $tmp = $result->{sid};
             }
           } else {
             $tmp = "Unexpected result: " . Dumper ($result);
           }
           return $tmp;

         }

         return "ERROR: data.lua not available";
      }
   }
   elsif ( lc $cmd eq 'diversity' && $mesh eq "master") {
      if ( int @val == 2 && $val[1] =~ /^(on|off)$/ ) {
         FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd ".join(" ", @val);
         unless (defined $hash->{READINGS}{"diversity".$val[0]}) {
            FRITZBOX_Log $hash, 2, "no diversity".$val[0]." to set.";
            return "ERROR: no diversity".$val[0]." to set.";
         }

         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;

         if ( $hash->{TR064}==1 ) { #tr064
            my @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "SetDeflectionEnable", "NewDeflectionId", $val[0] - 1, "NewEnable", $state] );
            FRITZBOX_TR064_Cmd ($hash, 0, \@tr064CmdArray);
         }
         else {
            FRITZBOX_Log $hash, 2, "'set ... diversity' is not supported by the limited interfaces of your Fritz!Box firmware.";
            return "ERROR: 'set ... diversity' is not supported by the limited interfaces of your Fritz!Box firmware.";
         }
         readingsSingleUpdate($hash,"diversity".$val[0]."_state",$val[1], 1);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'dectringblock' && $mesh eq "master") {
      my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

      my $FW1 = substr($fwV[1],0,2);
      my $FW2 = substr($fwV[2],0,2);

      FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd f�r Version: $FW1.$FW2 ";

      if ($FW1 <= 7 && $FW2 < 21) {
         FRITZBOX_Log $hash, 2, "ERROR: FritzOS version must be greater than 7.20";
         return "ERROR: FritzOS version must be greater than 7.20.";
      }

      # only on/off
      my $lm_OnOff = "0";
      my $kl_OnOff = "off";
      my $start_hh = "00";
      my $start_mm = "00";
      my $end_hh   = "00";
      my $end_mm   = "00";

      if ( int @val == 2 && $val[0] =~ /^dect(\d+)$/ && $val[1] =~ /^(on|off)$/ ) {
           $start_hh = "00";
	    $start_mm = "00";
	    $end_hh   = "00";
	    $end_mm   = "00";
      } elsif ( int @val >= 3 && $val[0] =~ /^dect(\d+)$/ && lc($val[1]) =~ /^(ed|wd|we)$/ && $val[2] =~ /^(2[0-3]|[01]?[0-9]):([0-5]?[0-9])-(2[0-4]|[01]?[0-9]):([0-5]?[0-9])$/ ) {
            $start_hh = substr($val[2], 0, 2);
            $start_mm = substr($val[2], 3, 2);
            $end_hh   = substr($val[2], 6, 2);
            $end_mm   = substr($val[2], 9, 2);
            if ($end_hh eq "24") {
                  $end_mm = "24:00";
            }
            if ( int @val == 4 && ($val[3] =~ /^(lmode:on|lmode:off)$/ || $val[3] =~ /^(emode:on|emode:off)$/)) {
                  $lm_OnOff = "1" if( $val[3] =~ /^lmode:on$/ );
                  $kl_OnOff = "on"  if( $val[3] =~ /^emode:on$/ );
            } elsif ( int @val == 5  && ($val[3] =~ /^(lmode:on|lmode:off)$/ || $val[3] =~ /^(emode:on|emode:off)$/)  && ($val[4] =~ /^(lmode:on|lmode:off)$/ || $val[4] =~ /^(emode:on|emode:off)$/)) {
                  $lm_OnOff = "1" if( $val[3] =~ /^lmode:on$/ || $val[4] =~ /^lmode:on$/);
                  $kl_OnOff = "on"  if( $val[3] =~ /^emode:on$/ || $val[4] =~ /^emode:on$/);
            #} else {
                  #  return "Error for parameters: $val[3]; $val[4]";
            }
      } else {
         FRITZBOX_Log $hash, 2, "ERROR: for dectringblock arguments";
         return "ERROR: for dectringblock arguments";
      }

      if (ReadingsVal($name, $val[0], "nodect") eq "nodect") {
         FRITZBOX_Log $hash, 2, "ERROR: dectringblock $val[0] not found";
         return "ERROR: dectringblock $val[0] not found.";
      }

      my @webCmdArray;
      my $queryStr;
      my $returnStr;

      #xhr 1 idx 2 apply nop lang de page edit_dect_ring_block		 Klingelsperre aus
      #lockmode 0 nightsetting 1 lockday everyday starthh 00 startmm 00 endhh 00 endmm 00 Klingelsperre ein

      #xhr: 1
      #nightsetting: 1
      #lockmode: 0
      #lockday: everday
      #starthh: 10
      #startmm: 15
      #endhh: 20
      #endmm: 25
      #idx: 1
      #back_to_page: /fon_devices/fondevices_list.lua
      #apply:
      #lang: de
      #page: edit_dect_ring_block

      push @webCmdArray, "xhr"   => "1";

      $queryStr .= "'xhr'   => '1'\n";

      if ($val[1] eq "on") {
        push @webCmdArray, "lockmode"     => $lm_OnOff;
        push @webCmdArray, "nightsetting" => "1";
        push @webCmdArray, "lockday"      => "everyday";
        push @webCmdArray, "starthh"      => $start_hh;
        push @webCmdArray, "startmm"      => $start_mm;
        push @webCmdArray, "endhh"        => $end_hh;
        push @webCmdArray, "endmm"        => $end_mm;

      } elsif ( lc($val[1]) =~ /^(ed|wd|we)$/ ) {
        push @webCmdArray, "lockmode"     => $lm_OnOff;
        push @webCmdArray, "event"        => "on" if( $kl_OnOff eq "on");
        push @webCmdArray, "nightsetting" => "1";
        push @webCmdArray, "lockday"      => "everyday" if( lc($val[1]) eq "ed");
        push @webCmdArray, "lockday"      => "workday" if( lc($val[1]) eq "wd");
        push @webCmdArray, "lockday"      => "weekend" if( lc($val[1]) eq "we");
        push @webCmdArray, "starthh"      => $start_hh;
        push @webCmdArray, "startmm"      => $start_mm;
        push @webCmdArray, "endhh"        => $end_hh;
        push @webCmdArray, "endmm"        => $end_mm;

      }

      push @webCmdArray, "idx"   => substr($val[0], 4);
      push @webCmdArray, "apply" => "";
      push @webCmdArray, "lang"  => "de";
      push @webCmdArray, "page"  => "edit_dect_ring_block";

      FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd \n" . join(" ", @webCmdArray);

      my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

      my $tmp;
      if (defined $result->{Error} ) {
         $tmp = "ERROR: " . $result->{Error};
         FRITZBOX_Log $hash, 2, "ERROR: dectringblock " . $val[0] . " - " . $tmp;
      }
      elsif (defined $result->{sid} ) {
        if (defined $result->{data}->{apply}) {
          $tmp = $result->{data}->{apply};
          return $tmp;
        } else {
          $tmp = $result->{sid};
        }
      }
      else {
        $tmp = "Unexpected result: " . Dumper ($result);
      }
      return $tmp;

   }
   elsif ( lc $cmd eq 'switchipv4dns' && $mesh eq "master") {

      if (int @val == 1 && $val[0] =~ /^(provider|other)$/) {
         my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

         my $FW1 = substr($fwV[1],0,2);
         my $FW2 = substr($fwV[2],0,2);

         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

         if ($FW1 <= 7 && $FW2 < 21) {
           FRITZBOX_Log $hash, 2, "ERROR: FritzOS version must be greater than 7.20";
           return "ERROR: FritzOS version must be greater than 7.20.";
         }

         FRITZBOX_Log $hash, 3, "INFO: set $name $cmd " . join(" ", @val);

         if ( $val[0] eq "provider") {

           #xhr 1 ipv4_use_user_dns 0 page dnsSrv apply nop lang de
           my @webCmdArray;
           push @webCmdArray, "xhr"                       => "1";
           push @webCmdArray, "lang"                      => "de";
           push @webCmdArray, "page"                      => "dnsSrv";
           push @webCmdArray, "apply"                     => "";
           push @webCmdArray, "ipv4_use_user_dns"         => "0";

           FRITZBOX_Log $hash, 4, "INFO: data.lua: " . join(" ", @webCmdArray);

           my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

           if(defined $result->{Error}) {
              FRITZBOX_Log $hash, 2, "ERROR: DNS IPv4 not set to " . $val[0] . " - " . $result->{Error};
              return "ERROR: setting DNS IPv4: " . $result->{Error};
           }

           FRITZBOX_Log $hash, 4, "INFO: DNS IPv4 set to ".$val[0];
           return "DNS IPv4 set to ".$val[0];

         } elsif ( $val[0] eq "other") {

           #xhr 1 lang de page dnsSrv xhrId all
           my @webCmdArray;
           push @webCmdArray, "xhr"                       => "1";
           push @webCmdArray, "lang"                      => "de";
           push @webCmdArray, "page"                      => "dnsSrv";
           push @webCmdArray, "xhrId"                     => "all";

           FRITZBOX_Log $hash, 4, "INFO: data.lua: " . join(" ", @webCmdArray);

           my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

           if(defined $result->{Error}) {
              FRITZBOX_Log $hash, 2, "ERROR: DNS IPv4 not set to " . $val[0] . " - " . $result->{Error};
              return "ERROR: setting DNS IPv4: " . $result->{Error};
           }

           my @firstdns  = split(/\./,$result->{data}->{vars}->{ipv4}->{firstdns}{value});
           my @seconddns = split(/\./,$result->{data}->{vars}->{ipv4}->{seconddns}{value});

           #xhr 1 ipv4_use_user_dns 1
           #ipv4_user_firstdns0 8 ipv4_user_firstdns1 8 ipv4_user_firstdns2 8 ipv4_user_firstdns3 8
           #ipv4_user_seconddns0 1 ipv4_user_seconddns1 1 ipv4_user_seconddns2 1 ipv4_user_seconddns3 1
           #apply nop lang de page dnsSrv

           push @webCmdArray, "xhr"                       => "1";
           push @webCmdArray, "lang"                      => "de";
           push @webCmdArray, "page"                      => "dnsSrv";
           push @webCmdArray, "apply"                     => "";
           push @webCmdArray, "ipv4_use_user_dns"         => "1";
           push @webCmdArray, "ipv4_user_firstdns0"       => $firstdns[0];
           push @webCmdArray, "ipv4_user_firstdns1"       => $firstdns[1];
           push @webCmdArray, "ipv4_user_firstdns2"       => $firstdns[2];
           push @webCmdArray, "ipv4_user_firstdns3"       => $firstdns[3];
           push @webCmdArray, "ipv4_user_seconddns0"      => $seconddns[0];
           push @webCmdArray, "ipv4_user_seconddns1"      => $seconddns[1];
           push @webCmdArray, "ipv4_user_seconddns2"      => $seconddns[2];
           push @webCmdArray, "ipv4_user_seconddns3"      => $seconddns[3];

           FRITZBOX_Log $hash, 4, "INFO: data.lua: " . join(" ", @webCmdArray);

           $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

           if(defined $result->{Error}) {
              FRITZBOX_Log $hash, 2, "ERROR: DNS IPv4 not set to " . $val[0] . " - " . $result->{Error};
              return "ERROR: setting DNS IPv4: " . $result->{Error};
           }

           FRITZBOX_Log $hash, 4, "INFO: DNS IPv4 set to ".$val[0];
           return "DNS IPv4 set to ".$val[0];
         }

         return "Ok";
      } else {
         FRITZBOX_Log $hash, 2, "ERROR: for switchipv4dns arguments";
         return "ERROR: for switchipv4dns arguments";
      }

   }
   elsif ( lc $cmd eq 'enablevpnshare' && $mesh eq "master") {

      if ( int @val == 2 && $val[1] =~ /^(on|off)$/ ) {
         my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

         my $FW1 = substr($fwV[1],0,2);
         my $FW2 = substr($fwV[2],0,2);

         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

         if ($FW1 <= 7 && $FW2 < 21) {
           FRITZBOX_Log $hash, 2, "ERROR: FritzOS version must be greater than 7.20";
           return "ERROR: FritzOS version must be greater than 7.20.";
         }

         if ( AttrVal( $name, "enableVPNShares", "0")) {
            $val[0] = lc($val[0]);

            $val[0] = "vpn".$val[0] unless ($val[0] =~ /vpn/);

            unless (defined( $hash->{READINGS}{$val[0]})) {
               FRITZBOX_Log $hash, 2, "ERROR: set $name $cmd " . join(" ", @val);
               return "ERROR: no $val[0] available."
            }

            FRITZBOX_Log $hash, 4, "INFO: set $name $cmd " . join(" ", @val);
            push @cmdBuffer, "enablevpnshare " . join(" ", @val);
            return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};

         } else {
            FRITZBOX_Log $hash, 2, "ERROR: vpn readings not activated";
            return "ERROR: vpn readings not activated";
         }

      } else {
         FRITZBOX_Log $hash, 2, "ERROR: for enableVPNshare arguments";
         return "ERROR: for enableVPNshare arguments";
      }

   }
   elsif ( lc $cmd eq 'macfilter' && $mesh eq "master") {

      if ( int @val == 1 && $val[0] =~ /^(on|off)$/ ) {

         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd " . join(" ", @val);
         push @cmdBuffer, "macfilter " . join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};

      } else {
         FRITZBOX_Log $hash, 2, "ERROR: for macFilter arguments";
         return "ERROR: for macFilter arguments";
      }

   }
   elsif ( lc $cmd eq 'locklandevice' && $mesh eq "master") {

      if (int @val == 2) {

         $val[0] = FRITZBOX_Proof_Params($hash, $name, $cmd, "^(on|off)\$", @val);

         return $val[0] if($val[0] =~ /ERROR/);

         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd " . join(" ", @val);
         push @cmdBuffer, "locklandevice " . join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};

      } else {
         FRITZBOX_Log $hash, 2, "ERROR: for locklandevice arguments";
         return "ERROR: for locklandevice arguments";
      }

   }
   elsif ( lc $cmd eq 'chgprofile' && $mesh eq "master") {

      if(int @val == 2) {

         $val[1] = "filtprof" . $val[1] unless $val[0] =~ /^filtprof(\d+)$/;

         $val[0] = FRITZBOX_Proof_Params($hash, $name, $cmd, "^filtprof(\\d+)\$", @val);

         return $val[0] if($val[0] =~ /ERROR/);

         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "chgprofile " . join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};

      } else {
         FRITZBOX_Log $hash, 2, "ERROR: for chgprofile arguments";
         return "ERROR: for chgprofile arguments";
      }
   }
   elsif ( lc $cmd eq 'guestwlan') {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "guestwlan ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   }
#   elsif ( lc $cmd eq 'moh' && $mesh eq "master") {
#      if (int @val > 0)
#      {
#         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
#      }
#   }
# set password
   elsif ( lc $cmd eq 'password') {
      if (int @val == 1)
      {
         return FRITZBOX_storePassword ( $hash, $val[0] );
      }
   }
#set Ring
   elsif ( lc $cmd eq 'ring' && $mesh eq "master") {
      if (int @val > 0) {
         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "ring ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
#   }
#   elsif ( lc $cmd eq 'sendmail') {
#      FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
#      return "'set ... sendMail' is not supported by the limited interfaces of your Fritz!Box firmware."
#         unless $hash->{TELNET}==1;
#      FRITZBOX_SendMail_Shell $hash, @val;
#      return undef;
#   }
#   elsif ( lc $cmd eq 'startradio') {
#      if (int @val > 0) {
#         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
#         return FRITZBOX_StartRadio_Web $hash, @val;
#      }
   }
   elsif ( lc $cmd eq 'tam' && $mesh eq "master") {
      if ( int @val == 2 && defined( $hash->{READINGS}{"tam".$val[0]} ) && $val[1] =~ /^(on|off)$/ ) {
         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;

         if ($hash->{SECPORT}) { #TR-064
            my @tr064CmdArray = (["X_AVM-DE_TAM:1", "x_tam", "SetEnable", "NewIndex", $val[0] - 1 , "NewEnable", $state]);
            FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         }

         readingsSingleUpdate($hash,"tam".$val[0]."_state",$val[1], 1);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'update' ) {
      FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
      $hash->{fhem}{LOCAL}=1;
      FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL}=0;
      return undef;
   }
   elsif ( lc $cmd eq 'wlan') {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, "wlan ".join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   }
   elsif ( lc $cmd =~ /^wlan(2\.4|5)$/ && $hash->{fhem}->{is_double_wlan} == 1 ) {
      if ( int @val == 1 && $val[0] =~ /^(on|off)$/ ) {
         FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
         push @cmdBuffer, lc ($cmd) . " " . join(" ", @val);
         return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
      }
   }
   elsif ( lc $cmd eq 'rescanwlanneighbors' ) {
      FRITZBOX_Log $hash, 4, "INFO: set $name $cmd ".join(" ", @val);
      push @cmdBuffer, "rescanwlanneighbors " . join(" ", @val);
      return FRITZBOX_Set_Cmd_Start $hash->{helper}{TimerCmd};
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

   if( lc $cmd eq "luaquery" && $hash->{LUAQUERY}) {
   # get Fritzbox luaQuery inetstat:status/Today/BytesReceivedLow
   # get Fritzbox luaQuery telcfg:settings/AlarmClock/list(Name,Active,Time,Number,Weekdays)
      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd ".join(" ", @val);

      return "Wrong number of arguments, usage: get $name luaQuery <query>"       if int @val !=1;

      $returnStr  = "Result of query = '$val[0]'\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      my $queryStr = "&result=".$val[0];

      my $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

      my $tmp = FRITZBOX_ERR_Result($hash, $result);

      return $returnStr . $tmp;

   } elsif( lc $cmd eq "luafunction" && $hash->{LUAQUERY}) {
      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd ".join(" ", @val);

      return "Wrong number of arguments, usage: get $name luaQuery <query>" if int @val !=1;

      $returnStr  = "Result of function call '$val[0]' \n";
      $returnStr .= "----------------------------------------------------------------------\n";

      my $result = FRITZBOX_Web_Query( $hash, $val[0], "", "luaCall") ;
      #my $result = FRITZBOX_Lua_Call( $hash, $val[0], $val[1]) ;

      my $tmp = FRITZBOX_ERR_Result($hash, $result);

      return $returnStr . $tmp;

   } elsif( lc $cmd eq "luadata" && $hash->{LUADATA}) {
      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd [" . int(@val) . "] " . join(" ", @val);

      return "Wrong number of arguments, usage: get $name argName1 argValue1 [argName2 argValue2] ..." if int @val < 2 || int(@val) %2 == 1;

      my @webCmdArray;
      my $queryStr;
      for(my $i = 0; $i <= (int @val)/2 - 1; $i++) {
        $val[2*$i+1] = "" if lc($val[2*$i+1]) eq "nop";
        $val[2*$i+1] =~ tr/\&/ /;
        push @webCmdArray, $val[2*$i+0] => $val[2*$i+1];
        $queryStr .= "'$val[2*$i+0]' => '$val[2*$i+1]'\n";
      }

      $queryStr =~ tr/\&/ /;

      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd " . $queryStr;

      $returnStr  = "Result of data = " . $queryStr . "\n";
      $returnStr .= "----------------------------------------------------------------------\n";

      my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

      my $flag = 1;
      my $tmp = FRITZBOX_ERR_Result($hash, $result, 1);

      return $returnStr . $tmp;

   } elsif( lc $cmd eq "landeviceinfo" && $hash->{LUADATA})  {

      return "Wrong number of arguments, usage: get $name argName1 argValue1" if int @val != 1;

      my $erg = FRITZBOX_Proof_Params($hash, $name, $cmd, "", @val);

      return $erg if($erg =~ /ERROR/);

      return FRITZBOX_Lan_Device_Info( $hash, $erg, "info");

   } elsif( lc $cmd eq "luainfo")  {
      my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

      my $FW1 = substr($fwV[1],0,2);
      my $FW2 = substr($fwV[2],0,2);

      FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

      if ($FW1 <= 7 && $FW2 < 21) {
        FRITZBOX_Log $hash, 2, "ERROR: FritzOS version must be greater than 7.20";
        return "FritzOS version must be greater than 7.20.";
      }

      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd [" . int(@val) . "] " . join(" ", @val);

      return "Wrong number of arguments, usage: get $name argName1 argValue1" if int @val != 1;

      my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

      if ( $val[0] eq "lanDevices" && $hash->{LUADATA}) {
        $returnStr = FRITZBOX_Lan_Devices_List($hash);

      } elsif ( $val[0] eq "vpnShares" && $hash->{LUADATA}) {
        $returnStr = FRITZBOX_VPN_Shares_List($hash);

      } elsif ( $val[0] eq "kidProfiles" && $hash->{LUAQUERY}) {
        $returnStr = FRITZBOX_Kid_Profiles_List($hash);

      } elsif ( $val[0] eq "userInfos" && $hash->{LUAQUERY}) {
        $returnStr = FRITZBOX_User_Info_List($hash);

      } elsif ( $val[0] eq "wlanNeighborhood" && $hash->{LUADATA}) {
        $returnStr = FRITZBOX_WLAN_Environment($hash);

      } elsif ( $val[0] eq "docsisInformation" && $hash->{LUADATA} && ($avmModel =~ "Box") && (lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]")) {
        $returnStr = FRITZBOX_DOCSIS_Informations($hash);
      }

      return $returnStr;

#   } elsif( lc $cmd eq "ringtones" ) {
#      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd ".join(" ", @val);
#      $returnStr  = "Ring tones to use with 'set <name> ring <intern> <duration> <ringTone>'\n";
#      $returnStr .= "----------------------------------------------------------------------\n";
#      $returnStr .= join "\n", sort values %ringTone;
#      return $returnStr;
#
   } elsif( lc $cmd eq "tr064command" && defined $hash->{SECPORT}) {
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

      FRITZBOX_Log $hash, 4, "INFO: get $name $cmd ".join(" ", @val);
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

   } elsif( lc $cmd eq "tr064servicelist" && defined $hash->{SECPORT}) {
      return FRITZBOX_TR064_Get_ServiceList ($hash);
   }

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");
   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   my $list;
   $list .= "luaQuery"                if $hash->{LUAQUERY};
   $list .= " luaData"                if $hash->{LUADATA};
   $list .= " luaFunction"            if $hash->{LUAQUERY};

   # luaData
   $list .= " luaInfo:" if $hash->{LUADATA} || $hash->{LUAQUERY};
   $list .= "lanDevices,vpnShares,wlanNeighborhood" if $hash->{LUADATA};
   $list .= ",kidProfiles,userInfos" if $hash->{LUAQUERY};
   $list .= ",docsisInformation" if $hash->{LUADATA} && ($avmModel =~ "Box") && (lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]");

   $list .= " lanDeviceInfo"          if $hash->{LUADATA};

   $list .= " tr064Command"           if defined $hash->{SECPORT};
   $list .= " tr064ServiceList:noArg" if defined $hash->{SECPORT};

#   $list .= " ringTones:noArg";

   return "Unknown argument $cmd, choose one of $list";

} # end FRITZBOX_Get

# Proof params for set/get on landeviceID or MAC
#######################################################################
sub FRITZBOX_Proof_Params($@) {

   my ($hash, $name, $cmd, $mysearch, @val) = @_;
   $mysearch = "" unless( defined $mysearch);

   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

   my $FW1 = substr($fwV[1],0,2);
   my $FW2 = substr($fwV[2],0,2);

   FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

   if ($FW1 <= 7 && $FW2 < 21) {
      FRITZBOX_Log $hash, 2, "ERROR: FritzOS version must be greater than 7.20";
      return "ERROR: FritzOS version must be greater than 7.20.";
   }

   unless ($val[0] =~ /^([0-9a-f]{2}([:-_]|$)){6}$/i ) {
      if ( $val[0] =~ /(\d+)/ ) {
         $val[0] = "landevice" . $1; #$val[0];
      }
   }

   if ( int @val == 2 ) {
      unless ($val[1] =~ /$mysearch/ && ($val[0] =~ /^landevice(\d+)$/ || $val[0] =~ /^([0-9a-f]{2}([:-_]|$)){6}$/i) ) {
         $mysearch =~ s/\^|\$//g;
         FRITZBOX_Log $hash, 2, "ERROR: no valid $cmd parameter: " . $val[0] . " or " . $mysearch . " given";
         return "ERROR: no valid $cmd parameter: " . $val[0] . " or " . $mysearch . " given";
      }
   } elsif ( int @val == 1 ) {
      if ($mysearch ne "" && $val[0] =~ /$mysearch/ ) {
        FRITZBOX_Log $hash, 4, "INFO: $name $cmd " . join(" ", @val);
        return $val[0];
      } else {
         unless ( $val[0] =~ /^landevice(\d+)$/ || $val[0] =~ /^([0-9a-f]{2}([:-_]|$)){6}$/i ) {
            FRITZBOX_Log $hash, 2, "ERROR: no valid $cmd parameter: " . $val[0] . " given";
            return "ERROR: no valid $cmd parameter: " . $val[0] . " given";
         }
      }

   } else {
      FRITZBOX_Log $hash, 2, "ERROR: parameter missing";
      return "ERROR: $cmd parameter missing";
   }

   if ($val[0] =~ /^([0-9a-f]{2}([:-_]|$)){6}$/i) {
      my $mac = $val[0];
         $mac =~ s/:|-/_/g;

      if (exists($hash->{fhem}->{landevice}->{$mac}) eq "") {
         FRITZBOX_Log $hash, 2, "ERROR: non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }

      unless (defined $hash->{fhem}->{landevice}->{$mac}) {
         FRITZBOX_Log $hash, 2, "ERROR: non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }

      $val[0] = $hash->{fhem}->{landevice}->{$mac} ;

   } else {

      if (exists($hash->{fhem}->{landevice}->{$val[0]}) eq "") {
         FRITZBOX_Log $hash, 2, "ERROR: non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }

      unless (defined $hash->{fhem}->{landevice}->{$val[0]}) {
         FRITZBOX_Log $hash, 2, "ERROR: non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }
   }

   FRITZBOX_Log $hash, 4, "INFO: $name $cmd " . join(" ", @val);

   return $val[0];

} # FRITZBOX_Proof_Params

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
   }

   if( $interval != 0 ) {
      RemoveInternalTimer($hash->{helper}{TimerReadout});
      InternalTimer(gettimeofday()+$interval, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 1);
   }

# Kill running process if "set update" is used
   if ( exists( $hash->{helper}{READOUT_RUNNING_PID} ) && $hash->{fhem}{LOCAL} == 1 ) {
      FRITZBOX_Log $hash, 4, "INFO: Old readout process still running. Killing old process ".$hash->{helper}{READOUT_RUNNING_PID};
      BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} );
      # stop FHEM, giving a FritzBox some time to free the memory
      delete( $hash->{helper}{READOUT_RUNNING_PID} );
   }

   $hash->{fhem}{LOCAL} = 2   if $hash->{fhem}{LOCAL} == 1;

   unless( exists $hash->{helper}{READOUT_RUNNING_PID} ) {
      $hash->{helper}{READOUT_RUNNING_PID} = BlockingCall($runFn, $name,
                                                       "FRITZBOX_Readout_Done", 55,
                                                       "FRITZBOX_Readout_Aborted", $hash);
      FRITZBOX_Log $hash, 4, "INFO: Fork process $runFn";
   }
   else {
      FRITZBOX_Log $hash, 4, "INFO: Skip fork process $runFn";
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
   my $boxUser = AttrVal( $name, "boxUser", "" );

   if ( $host =~ /undefined/ || $boxUser eq "") {
     my $tmp = "";
        $tmp = "fritzBoxIP" if $host =~ /undefined/;
        $tmp .= ", " if $host =~ /undefined/ && $boxUser eq "";
        $tmp .= " boxUser (bei Repeatern nicht unbedingt notwendig)" if $boxUser eq "";
        $tmp .= " nicht definiert. Bitte auch das Passwort mit <set $name password> setzen.";

     FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HINWEIS", $tmp);

     FRITZBOX_Log $hash, 2, "ERROR: " . $tmp;
   }

# change host name if necessary
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HOST", $host) if $host ne $hash->{HOST};

# Check if perl modules for remote APIs exists
   if ($missingModulWeb) {
      FRITZBOX_Log $hash, 3, "INFO: Cannot check for box model and APIs webcm, luaQuery and TR064 because perl modul $missingModulWeb is missing on this system.";
   }
# Check for remote APIs
   else {
      my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);

   # Check if query.lua exists
      $response = $agent->get( "http://".$host."/query.lua" );

      if ($response->is_success) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 1;
         FRITZBOX_Log $hash, 4, "DEBUG: API luaQuery found (".$response->code.").";
      }
      elsif ($response->code eq "500" || $response->code eq "403") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 1;
         FRITZBOX_Log $hash, 3, "INFO: API luaQuery found but responded with: ".$response->status_line;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 0;
         FRITZBOX_Log $hash, 3, "INFO: API luaQuery does not exist (".$response->status_line.")";
      }

   # Check if data.lua exists
      $response = $agent->get( "http://".$host."/data.lua" );

      if ($response->is_success) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 1;
         FRITZBOX_Log $hash, 4, "DEBUG: API luaData found (".$response->code.").";
      }
      elsif ($response->code eq "500" || $response->code eq "403") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 1;
         FRITZBOX_Log $hash, 3, "INFO: API luaData found but responded with: ".$response->status_line;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 0;
         FRITZBOX_Log $hash, 3, "INFO: API luaData does not exist (".$response->status_line.")";
      }

   # Check if tr064 specification exists and determine TR064-Port
      $response = $agent->get( "http://".$host.":49000/tr64desc.xml" );

      if ($response->is_success) { #determine TR064-Port
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TR064", 1;
         FRITZBOX_Log $hash, 4, "DEBUG: API TR-064 found.";
      #Determine TR064-Port
         my $tr064Port = FRITZBOX_TR064_Init ( $hash, $host );
         if ($tr064Port) {
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->SECPORT", $tr064Port;
            FRITZBOX_Log $hash, 4, "DEBUG: TR-064-SecurePort is $tr064Port.";
         }
         else {
            FRITZBOX_Log $hash, 3, "INFO: TR-064-SecurePort does not exist";
         }
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TR064", 0;
         FRITZBOX_Log $hash, 3, "INFO: API TR-064 does not exist: ".$response->status_line;
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
         FRITZBOX_Log $hash, 3, "INFO: Created m3u file '$m3uFileLocal'.";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->M3U_LOCAL", $m3uFileLocal;

      # Get the m3u-URL
         my $m3uFileURL = AttrVal( $name, "m3uFileURL", "unknown" );

      # if no URL and no local file defined, then try to build the correct URL
         if ( $m3uFileURL eq "unknown" && AttrVal( $name, "m3uFileLocal", "" ) eq "" ) {

         # Getting IP of FHEM host
            FRITZBOX_Log $hash, 4, "DEBUG: Try to get my IP address.";
            my $socket = IO::Socket::INET->new( Proto => 'tcp', PeerAddr => $host, PeerPort    => 'http(80)' );
            my $ip;
            $ip = $socket->sockhost if $socket; #A side-effect of making a socket connection is that our IP address is available from the 'sockhost' method
            FRITZBOX_Log $hash, 3, "INFO: Could not determine my ip address"  unless $ip;

         # Get a web port
            my $port;
            FRITZBOX_Log $hash, 4, "DEBUG: Try to get a FHEMWEB port.";
            
            foreach( keys %defs ) {
               if ( $defs{$_}->{TYPE} eq "FHEMWEB" && !defined $defs{$_}->{TEMPORARY} && defined $defs{$_}->{PORT} ) {
                  $port = $defs{$_}->{PORT};
                  last;
               }
            }
            FRITZBOX_Log $hash, 3, "INFO: Could not find a FHEMWEB device." unless $port;
            if (defined $ip && defined $port) {
               $m3uFileURL = "http://$ip:$port/fhem/www/images/$name.m3u";
            }
         }

      # Check if m3u can be accessed
         unless ( $m3uFileURL eq "unknown" ) {
            FRITZBOX_Log $hash, 4, "DEBUG: Try to get '$m3uFileURL'";
            $response = $agent->get( $m3uFileURL );
            if ($response->is_error) {
               FRITZBOX_Log $hash, 3, "ERROR: Failed to get '$m3uFileURL': ".$response->status_line;
               $m3uFileURL = "unknown"     ;
            }
         }
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->M3U_URL", $m3uFileURL;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->M3U_LOCAL", "undefined";
         FRITZBOX_Log $hash, 2, "ERROR: Cannot create save file '$m3uFileLocal' because $!\n";
      }

      # Box model per jason
      FRITZBOX_Log $hash, 5, "DEBUG: Read 'jason_boxinfo'";
      my $url = "http://".$host."/jason_boxinfo.xml";

      $response = $agent->get( $url );
      my $content  = $response->content;
      my $fwVersion = "0.0.0.error";

      if ($content =~ /<j:Name>/) {
         FRITZBOX_Log $hash, 5, "DEBUG: jason_boxinfo returned: $content";

         FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_model", $1)     if $content =~ /<j:Name>(.*)<\/j:Name>/;
         FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_oem", $1)       if $content =~ /<j:OEM>(.*)<\/j:OEM>/;
         FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_fwVersion", $1) if $content =~ /<j:Version>(.*)<\/j:Version>/ ;
         $fwVersion = $1 if $content =~ /<j:Version>(.*)<\/j:Version>/ ;

      } else {
         # Ansonsten Box-Model per system_status einlesen
         # Muss nochmal neu gesetzt werden, sonst gibt es einen Fehler (keine Ahnung warum)
         $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
         $url = "http://".$host."/cgi-bin/system_status";
         FRITZBOX_Log $hash, 5, "DEBUG: Read 'system_status'";

         $response = $agent->get( $url );
         $content  = $response->content;
         FRITZBOX_Log $hash, 5, "DEBUG: system_status returned: $content";
         if ($response->is_success) {
            $content=$1    if $content =~ /<body>(.*)<\/body>/;

            my @result = split /-/, $content;
            # http://www.tipps-tricks-kniffe.de/fritzbox-wie-lange-ist-die-box-schon-gelaufen/
            # FRITZ!Box 7590 (UI)-B-132811-010030-XXXXXX-XXXXXX-787902-1540750-101716-1und1
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
            $fwVersion = $result[7];

         } else {
            FRITZBOX_Log $hash, 2, "ERROR: " . $response->status_line;
         }
      }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECKED", 1;

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   my $returnStr = join('|', @roReadings );

   FRITZBOX_Log $hash, 4, "INFO: Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process (" . length ($returnStr) . "): " . $returnStr;

   return $name."|".encode_base64($returnStr,"");

} #end FRITZBOX_API_Check_Run


# http://fritz.box/cgi-bin/webcm?wlan:settings/guest_ap_enabled=1&sid=
      # FRITZBOX_Log $hash, 3, "INFO: Web connection established with $sid";
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
      # FRITZBOX_Log $hash, 3, "DEBUG: ".$response->content;

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
   my $host = $hash->{HOST};
   my $Tag;
   my $Std;
   my $Min;
   my $Sek;

   my $views;
   my $nbViews;

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");
   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

   my $FW1 = substr($fwV[1],0,2);
   my $FW2 = substr($fwV[2],0,2);

#Start update
   FRITZBOX_Log $hash, 4, "INFO: Prepare query string for luaQuery.";
   my $queryStr = "&radio=configd:settings/WEBRADIO/list(Name)"; # Webradio
   $queryStr .= "&box_dect=dect:settings/enabled"; # DECT Sender
   $queryStr .= "&handsetCount=dect:settings/Handset/count"; # Anzahl Handsets
   $queryStr .= "&handset=dect:settings/Handset/list(User,Manufacturer,Model,FWVersion)"; # DECT Handsets
   $queryStr .= "&wlanList=wlan:settings/wlanlist/list(mac,speed,speed_rx,rssi,is_guest)"; # WLAN devices
   $queryStr .= "&wlanListNew=wlan:settings/wlanlist/list(mac,speed,rssi)"; # WLAN devices fw>=6.69
   #wlan:settings/wlanlist/list(hostname,mac,UID,state,rssi,quality,is_turbo,cipher,wmm_active,powersave,is_ap,ap_state,is_repeater,flags,flags_set,mode,is_guest,speed,speed_rx,channel_width,streams)   #wlan:settings/wlanlist/list(hostname,mac,UID,state,rssi,quality,is_turbo,wmm_active,cipher,powersave,is_repeater,flags,flags_set,mode,is_guest,speed,speed_rx,speed_rx_max,speed_tx_max,channel_width,streams,mu_mimo_group,is_fail_client)
   #$queryStr .= "&lanDevice=landevice:settings/landevice/list(mac,ip,ethernet,ethernet_port,guest,name,active,online,wlan,speed,UID)"; # LAN devices
   $queryStr .= "&lanDevice=landevice:settings/landevice/list(mac,ip,ethernet,ethernet_port,ethernetport,guest,name,active,online,wlan,speed,UID)"; # LAN devices
   $queryStr .= "&lanDeviceNew=landevice:settings/landevice/list(mac,ip,ethernet,guest,name,active,online,wlan,speed,UID)"; # LAN devices fw>=6.69
   #landevice:settings/landevice/list(name,ip,mac,UID,dhcp,wlan,ethernet,active,static_dhcp,manu_name,wakeup,deleteable,source,online,speed,wlan_UIDs,auto_wakeup,guest,url,wlan_station_type,vendorname)
   #landevice:settings/landevice/list(name,ip,mac,parentname,parentuid,ethernet_port,wlan_show_in_monitor,plc,ipv6_ifid,parental_control_abuse,plc_UIDs)   #landevice:settings/landevice/list(name,ip,mac,UID,dhcp,wlan,ethernet,active,static_dhcp,manu_name,wakeup,deleteable,source,online,speed,wlan_UIDs,auto_wakeup,guest,url,wlan_station_type,vendorname,parentname,parentuid,ethernet_port,wlan_show_in_monitor,plc,ipv6_ifid,parental_control_abuse,plc_UIDs)
   $queryStr .= "&init=telcfg:settings/Foncontrol"; # Init
   $queryStr .= "&box_stdDialPort=telcfg:settings/DialPort"; #Dial Port
   unless (AttrVal( $name, "disableDectInfo", "0")) {
      $queryStr .= "&dectUser=telcfg:settings/Foncontrol/User/list(Id,Name,Intern,IntRingTone,AlarmRingTone0,RadioRingID,ImagePath,G722RingTone,G722RingToneName)"; # DECT Numbers
   }
   unless (AttrVal( $name, "disableFonInfo", "0")) {
      $queryStr .= "&fonPort=telcfg:settings/MSN/Port/list(Name,MSN)"; # Fon ports
   }
   if (AttrVal( $name, "enableAlarmInfo", "0")) {
      $queryStr .= "&alarmClock=telcfg:settings/AlarmClock/list(Name,Active,Time,Number,Weekdays)"; # Alarm Clock
   }
   $queryStr .= "&diversity=telcfg:settings/Diversity/list(MSN,Active,Destination)"; # Diversity (Rufumleitung)
   $queryStr .= "&box_moh=telcfg:settings/MOHType"; # Music on Hold
   $queryStr .= "&box_uptimeHours=uimodlogic:status/uptime_hours"; # hours
   $queryStr .= "&box_uptimeMinutes=uimodlogic:status/uptime_minutes"; # hours
   $queryStr .= "&box_fwVersion=logic:status/nspver"; # FW Version #uimodlogic:status/nspver
   $queryStr .= "&box_fwVersion_neu=uimodlogic:status/nspver"; # FW Version
   $queryStr .= "&box_powerRate=power:status/rate_sumact"; # Power Rate
   $queryStr .= "&tam=tam:settings/TAM/list(Name,Display,Active,NumNewMessages,NumOldMessages)"; # TAM
   $queryStr .= "&box_cpuTemp=power:status/act_temperature"; # Box CPU Temperatur
   #$queryStr .= "&box_ipExtern=connection0:status/ip"; # Externe IP-Adresse
   #$queryStr .= "&box_connect=connection0:status/connect"; # Internet connection state
   $queryStr .= "&box_tr064=tr064:settings/enabled"; # TR064
   $queryStr .= "&box_tr069=tr069:settings/enabled"; # TR069
   $queryStr .= "&box_fwUpdate=updatecheck:status/update_available_hint";
   if (AttrVal( $name, "enableUserInfo", "0")) {
     $queryStr .= "&userProfil=user:settings/user/list(name,filter_profile_UID,this_month_time,today_time,type)"; # User profiles
     $queryStr .= "&userProfilNew=user:settings/user/list(name,type)"; # User profiles fw>=6.69
   }
   $queryStr .= "&is_double_wlan=wlan:settings/feature_flags/DBDC"; # Box Feature
   $queryStr .= "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
   $queryStr .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
   $queryStr .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # Gäste WLAN
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
   $queryStr .= "&box_macFilter_active=wlan:settings/is_macfilter_active";
   $queryStr .= "&TodayBytesReceivedHigh=inetstat:status/Today/BytesReceivedHigh";
   $queryStr .= "&TodayBytesReceivedLow=inetstat:status/Today/BytesReceivedLow";
   $queryStr .= "&TodayBytesSentHigh=inetstat:status/Today/BytesSentHigh";
   $queryStr .= "&TodayBytesSentLow=inetstat:status/Today/BytesSentLow";
   $queryStr .= "&GSM_RSSI=gsm:settings/RSSI";
   $queryStr .= "&GSM_NetworkState=gsm:settings/NetworkState";
   $queryStr .= "&GSM_AcT=gsm:settings/AcT";
   $queryStr .= "&UMTS_enabled=umts:settings/enabled";
   $queryStr .= "&userTicket=userticket:settings/ticket/list(id)";
   $queryStr .= "&dslStatGlobalIn=dslstatglobal:status/in";
   $queryStr .= "&dslStatGlobalOut=dslstatglobal:status/out";
   if (ReadingsNum($name, "box_model", "3490") ne "3490" && AttrVal( $name, "enableSIP", "0")) {
      $queryStr .= "&sip_info=sip:settings/sip/list(activated,displayname,connect)";
   }
   if (AttrVal( $name, "enableVPNShares", "0")) {
      $queryStr .= "&vpn_info=vpn:settings/connection/list(remote_ip,activated,name,state,access_type,connected_since)";
   }
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

   FRITZBOX_Log $hash, 4, "ReadOut gestartet: $queryStr";
   $result = FRITZBOX_Web_Query( $hash, $queryStr, "", "luaQuery") ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} ) {
      FRITZBOX_Log $hash, 2, "ERROR: ".$result->{Error};
      my $returnStr = "Error|" . $result->{Error};
      $returnStr .= "|fhem->sidTime|0"    if defined $result->{ResetSID};
      $returnStr .= "|" . join('|', @roReadings )     if int @roReadings;
      return $name."|".encode_base64($returnStr,"");
   }

   if ( defined $result->{AuthorizationRequired} ) {
      FRITZBOX_Log $hash, 2, "ERROR: AuthorizationRequired=".$result->{AuthorizationRequired};
      my $returnStr = "Error|Authorization required";
      $returnStr .= "|fhem->sidTime|0"    if defined $result->{ResetSID};
      $returnStr .= "|" . join('|', @roReadings )     if int @roReadings;
      return $name."|".encode_base64($returnStr,"");
   }

   # !!! copes with fw >=6.69 and fw < 7 !!!
   if ( ref $result->{wlanList} ne 'ARRAY' ) {
      FRITZBOX_Log $hash, 4, "INFO: Recognized query answer of firmware >=6.69 and < 7";
      my $result2;
      my $newQueryPart;

    # gets WLAN speed for fw>=6.69 and < 7
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

    # gets LAN-Port for fw>=6.69 and fw<7
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
   if ( $result->{handsetCount} =~ /[1-9]/ ) {
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
        next if defined $dectUserID eq "";
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

# SIP Lines
   my $boxModel = ReadingsNum($name, "box_model", "3490");
   FRITZBOX_Log $hash, 4, "INFO: sip for box-model: " . $boxModel;

   if ($boxModel ne "3490" && AttrVal( $name, "enableSIP", "0")) {

      my $sip_in_error = 0;
      my %oldSIPDevice;

      #collect current mac-readings (to delete the ones that are inactive or disappeared)
      foreach (keys %{ $hash->{READINGS} }) {
         $oldSIPDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^sip(\d+)_/ && defined $hash->{READINGS}{$_}{VAL};
      }

      foreach ( @{ $result->{sip_info} } ) {
        FRITZBOX_Log $hash, 4, "INFO: sip->info: " . $_->{_node} . ": " . $_->{activated};

        my $rName = $_->{_node} . "_" . $_->{displayname};

        if ($_->{activated} == 1) {								# sip activated und registriert

          if ($_->{connect} == 2) {								# sip activated und registriert
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, "active";
            delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
            FRITZBOX_Log $hash, 4, "INFO: $rName -> registration ok";
          }
          if ($_->{connect} == 0) {								# sip not activated
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, "inactive";
            delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
            FRITZBOX_Log $hash, 4, "INFO: $rName -> not active";
          }
          if ($_->{connect} == 1) {								# error condition for aktivated and unregistrated sips
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, "not registered";
            delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
            $sip_in_error++;
            FRITZBOX_Log $hash, 2, "INFO: $rName -> not registered";
          }
        } else {
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, "not in use";
          delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
          FRITZBOX_Log $hash, 4, "INFO: $rName -> not in use";
        }

        delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};

     }

   # Remove inactive or non existing sip-readings in two steps
      foreach ( keys %oldSIPDevice) {
         # set the sip readings to 'inactive' and delete at next readout
         if ( $oldSIPDevice{$_} ne "inactive" ) {
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "inactive";
         } else {
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "";
         }
      }

      FRITZBOX_Log $hash, 4, "INFO: end";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "sip_error", $sip_in_error;

   } # end ($boxModel ne "3490")

# VPN shares

   if ( AttrVal( $name, "enableVPNShares", "0")) {
     my %oldVPNDevice;
     #collect current vpn-readings (to delete the ones that are inactive or disappeared)
     foreach (keys %{ $hash->{READINGS} }) {
       $oldVPNDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^vpn(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
     }

     # 09128734qwe
     # vpn:settings/connection/list(remote_ip,activated,name,state,access_type,connected_since)

     foreach ( @{ $result->{vpn_info} } ) {
       $_->{_node} =~ m/(\d+)/;
       $rName = "vpn" . $1;

       FRITZBOX_Log $hash, 4, "INFO: vpn->info: $rName " . $_->{_node} . ": " . $_->{activated} . ": " . $_->{state};

       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, $_->{name};
       delete $oldVPNDevice{$rName} if exists $oldVPNDevice{$rName};

       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_access_type", "Corp VPN"    if $_->{access_type} == 1;
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_access_type", "User VPN"    if $_->{access_type} == 2;
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_access_type", "Lan2Lan VPN" if $_->{access_type} == 3;
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_access_type", "Wireguard Simple" if $_->{access_type} == 4;
       delete $oldVPNDevice{$rName . "_access_type"} if exists $oldVPNDevice{$rName . "_access_type"};

       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_remote_ip", $_->{remote_ip} eq "" ? "....":$_->{remote_ip};
       delete $oldVPNDevice{$rName . "_remote_ip"} if exists $oldVPNDevice{$rName . "_remote_ip"};

       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_activated", $_->{activated};
       delete $oldVPNDevice{$rName . "_activated"} if exists $oldVPNDevice{$rName . "_activated"};

       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_state", $_->{state} eq "" ? "none":$_->{state};
       delete $oldVPNDevice{$rName . "_state"} if exists $oldVPNDevice{$rName . "_state"};

       if ($_->{access_type} <= 3) {
         if ($_->{connected_since} == 0) {
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_connected_since", "none";
         } else {
           $Sek = $_->{connected_since};

           $Tag = int($Sek/86400);
           $Std = int(($Sek/3600)-(24*$Tag));
           $Min = int(($Sek/60)-($Std*60)-(1440*$Tag));
           $Sek -= (($Min*60)+($Std*3600)+(86400*$Tag));

           $Std = substr("0".$Std,-2);
           $Min = substr("0".$Min,-2);
           $Sek = substr("0".$Sek,-2);
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_connected_since", $_->{connected_since} . " sec = " . $Tag . "T $Std:$Min:$Sek";
         }
         delete $oldVPNDevice{$rName . "_connected_since"} if exists $oldVPNDevice{$rName . "_connected_since"};
       } else {
         if ($_->{connected_since} == 0) {
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_last_negotiation", "none";
         } else {
           $Sek = (int(time) - $_->{connected_since});
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName . "_last_negotiation", (strftime "%d-%m-%Y %H:%M:%S", localtime($_->{connected_since}));
         }
         delete $oldVPNDevice{$rName . "_last_negotiation"} if exists $oldVPNDevice{$rName . "_last_negotiation"};
       }

     }

   # Remove inactive or non existing vpn-readings in two steps
     foreach ( keys %oldVPNDevice) {
        # set the vpn readings to 'inactive' and delete at next readout
        if ( $oldVPNDevice{$_} ne "inactive" ) {
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "inactive";
        }
        else {
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "";
        }
     }
   }

# Create WLAN-List
   my %wlanList;
   #to keep compatibility with firmware <= v3.67 and >=7
   if ( ref $result->{wlanList} eq 'ARRAY' ) {
      foreach ( @{ $result->{wlanList} } ) {
         my $mac = $_->{mac};
         $mac =~ s/:/_/g;
         # Anscheinend gibt es Anmeldungen sowohl für Repeater als auch für FBoxen
         $wlanList{$mac}{speed} = $_->{speed}   if ! defined $wlanList{$mac}{speed} || $_->{speed} ne "0";
         $wlanList{$mac}{speed_rx} = $_->{speed_rx} if ! defined $wlanList{$mac}{speed_rx} || $_->{speed_rx} ne "0";
         #$wlanList{$mac}{speed_rx} = $result_lan->{$_->{_node}};
         $wlanList{$mac}{rssi} = $_->{rssi} if ! defined $wlanList{$mac}{rssi} || $_->{rssi} ne "0";
         $wlanList{$mac}{is_guest} = $_->{is_guest} if ! defined $wlanList{$mac}{is_guest} || $_->{is_guest} ne "0";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->wlanDevice->".$mac."->speed", $_->{speed};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->wlanDevice->".$mac."->speed_rx", $wlanList{$mac}{speed_rx};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->wlanDevice->".$mac."->rssi", $_->{rssi};
      }
   }

# Create LanDevice list and delete inactive devices
   my $allowPassiv = AttrVal( $name, "enablePassivLanDevices", "0");
   my %oldLanDevice;

   #collect current mac-readings (to delete the ones that are inactive or disappeared)
   foreach (keys %{ $hash->{READINGS} }) {
      $oldLanDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^mac_/ && defined $hash->{READINGS}{$_}{VAL};
   }

   %landevice = ();
   my $wlanCount = 0;
   my $gWlanCount = 0;

   if ( ref $result->{lanDevice} eq 'ARRAY' ) {
      #Ipv4,IPv6,lanName,devName,Mbit,RSSI "
      
      # iPad-Familie [landevice810] (WLAN: 142 / 72 Mbit/s RSSI: -53)
      my $deviceInfo = AttrVal($name, "deviceInfo", "_defDef_,name,[uid],(connection: speedcomma rssi)");

      $deviceInfo =~ s/\n//g;

      $deviceInfo = "_noDefInf_,_defDef_,name,[uid],(connection: speedcomma rssi)" if $deviceInfo eq "_noDefInf_";

      my $noDefInf = $deviceInfo =~ /_noDefInf_/ ? 1 : 0; #_noDefInf_ 
      $deviceInfo =~ s/\,_noDefInf_|_noDefInf_\,//g;

      my $defDef = $deviceInfo =~ /_defDef_/ ? 1 : 0;
      $deviceInfo =~ s/\,_defDef_|_defDef_\,//g;

      my $sep = "space";
      if ( ($deviceInfo . ",") =~ /_default_(.*?)\,/) {
         $sep = $1;
         $deviceInfo =~ s/,_default_${sep}|_default_${sep}\,//g;
      }
      $deviceInfo =~ s/\,/$sep/g;

      $deviceInfo =~ s/space/ /g;
      $deviceInfo =~ s/comma/\,/g;

      $sep =~ s/space/ /g;
      $sep =~ s/comma/\,/g;

      FRITZBOX_Log $hash, 5, "DEBUG: deviceInfo -> " . $deviceInfo;

      # FRITZBOX_Log $hash, 3, "DEBUG: Curl-> " . $strCurl;
      # unless(grep { /^(box_ipExtern)$/ } @dev_name);

      foreach ( @{ $result->{lanDevice} } ) {
         my $dIp   = $_->{ip};
         my $UID   = $_->{UID};
         my $dName = $_->{name};

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->landevice->$dIp", $dName;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->landevice->$UID", $dName;
         $landevice{$dIp} = $dName;
         $landevice{$UID} = $dName;

         my $srTmp = $deviceInfo;

      # lan IPv4 erg�nzen
         $srTmp =~ s/ipv4/$dIp/g;

      # lan DeviceName erg�nzen
         $srTmp =~ s/name/$dName/g;

      # lan DeviceID erg�nzen
         $srTmp =~ s/uid/$UID/g;

      # Create a reading if a landevice is connected
      #   if ( $_->{active} || $allowPassiv) {
         if ( ($_->{active} && $_->{ip}) || $allowPassiv) {
            my $mac = $_->{mac};
            $mac =~ s/:/_/g;

            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->landevice->$mac", $UID;
            $landevice{$mac}=$UID;

            # if ( !$_->{ethernet} && $_->{wlan} ) { # funktioniert nicht mehr seit v7
            # if ( defined $wlanList{$mac} ) {

            if ( defined $wlanList{$mac} and !$_->{ethernet_port} and !$_->{ethernetport} ) {
               # Copes with fw>=7
               $_->{guest} = $wlanList{$mac}{is_guest}  if defined $wlanList{$mac}{is_guest} && $_->{guest} eq "";
               $wlanCount++;
               $gWlanCount++      if $_->{guest} eq "1";

               $dName = $_->{guest} ? "g" : "";
               $dName .= "WLAN";
               $srTmp =~ s/connection/$dName/g;

               $dName = $wlanList{$mac}{speed} . " / " . $wlanList{$mac}{speed_rx} . " Mbit/s" ;
               $srTmp =~ s/speed/$dName/g;

               $dName = defined $wlanList{$mac} ? "RSSI: " . $wlanList{$mac}{rssi} : "";
               $srTmp =~ s/rssi/$dName/g;

            } else {
               $dName = "";
               $dName = $_->{guest} ? "g" : "" . "LAN" . $_->{ethernet_port} if $_->{ethernet_port};
               $dName = $_->{guest} ? "g" : "" . $_->{ethernetport} if $_->{ethernetport};

               if ($dName eq "") {
                 if ($noDefInf) {
                   $srTmp =~ s/connection:?/noConnectInfo/g;
                 } else {
                   $srTmp =~ s/connection:?${sep}|${sep}connection:?|connection:?//g;
                 }
               } else {
                 $srTmp =~ s/connection/$dName/g;
               }

               $dName = "1 Gbit/s"    if $_->{speed} eq "1000";
               $dName = $_->{speed} . " Mbit/s"   if $_->{speed} ne "1000" && $_->{speed} ne "0";
               if ($_->{speed} eq "0") {
                 if ($noDefInf) {
                   $srTmp =~ s/speed/noSpeedInfo/g;
                 } else {
                   $srTmp =~ s/speed${sep}|${sep}speed|speed//g;
                 }
               } else {
                 $srTmp =~ s/speed/$dName/g;
               }
            }

            $srTmp =~ s/rssi${sep}|${sep}rssi|rssi//g;

            if ($defDef) {
               $srTmp =~ s/\(: \, \)//gi;
               $srTmp =~ s/\, \)/ \)/gi;
               $srTmp =~ s/\,\)/\)/gi;

               $srTmp =~ s/\(:/\(/gi;

               $srTmp =~ s/\(\)//g;
            }

            $srTmp = "no match for Informations" if ($srTmp eq "");

            my $rName  = "mac_";
               $rName .= "pas_" if $allowPassiv && $_->{active} == 0;
               $rName .= $mac;

            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, $srTmp ;

            # Remove mac address from oldLanDevice-List
            delete $oldLanDevice{$rName} if exists $oldLanDevice{$rName};
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
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $result->{box_macFilter_active}, "onoff";

# Dect
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_dect", $result->{box_dect}, "onoff";

# Music on Hold
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_moh", $result->{box_moh}, "mohtype";

# Power Rate
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_powerRate", $result->{box_powerRate};

# Box Features
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->is_double_wlan", $result->{is_double_wlan}, "01";

# Box model, firmware and uptimes

   # Informationen �ber DSL Verbindung
   # xhr 1
   # lang de
   # page dslOv
   # xhrId all
   # xhr 1 lang de page dslOv xhrId all

   if($result->{box_uptimeHours} && $result->{box_uptimeHours} ne "no-emu") {
      $Tag = int($result->{box_uptimeHours} / 24);
      $Std = int($result->{box_uptimeHours} - (24 * $Tag));
      $Sek = int($result->{box_uptimeHours} * 3600) + $result->{box_uptimeMinutes} * 60;

      $Std = substr("0" . $Std,-2);
      $Min = substr("0" . $result->{box_uptimeMinutes},-2);

      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_uptime", $Sek . " sec = " . $Tag . "T " . $Std . ":" . $Min . ":00";
   } else {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_uptime", "no-emu";
   }

   if ($result->{box_fwVersion}) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwVersion", $result->{box_fwVersion};
   } else { # Ab Version 6.90
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwVersion", $result->{box_fwVersion_neu};
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwUpdate",    $result->{box_fwUpdate};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_tr064",       $result->{box_tr064},       "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_tr069",       $result->{box_tr069},       "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_stdDialPort", $result->{box_stdDialPort}, "dialport";
   # FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_ipExtern",    $result->{box_ipExtern};
   # FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_connect",     $result->{box_connect};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_cpuTemp",     $result->{box_cpuTemp};
   if ( defined ($result->{dslStatGlobalOut}) && looks_like_number($result->{dslStatGlobalOut}) ) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_dsl_upStream", sprintf ("%.3f", $result->{dslStatGlobalOut}/1000000);
   }
   if ( defined ($result->{dslStatGlobalIn}) && looks_like_number($result->{dslStatGlobalIn}) ) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_dsl_downStream", sprintf ("%.3f", $result->{dslStatGlobalIn}/1000000);
   }

# GSM
#FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_modem", $result->{GSM_ModemPresent};
   if (defined $result->{GSM_NetworkState} && $result->{GSM_NetworkState} ne "0") {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_rssi", $result->{GSM_RSSI};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_state", $result->{GSM_NetworkState}, "gsmnetstate";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_technology", $result->{GSM_AcT}, "gsmact";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "gsm_internet", $result->{UMTS_enabled};
   } else {
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
# L�schen ausgeblendeter TAMs
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


# attr global showInternalValues 0
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesReceivedHigh", $result->{TodayBytesReceivedHigh};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesReceivedLow", $result->{TodayBytesReceivedLow};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesSentHigh", $result->{TodayBytesSentHigh};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".box_TodayBytesSentLow", $result->{TodayBytesSentLow};


# informations depending on TR064 or data.lua
   # Getting Mesh Information

   my @webCmdArray;

   if ( $FW1 >= 7 && $FW2 >= 21 && $hash->{LUADATA}) {

     my %oldMeshDevice;

     #$oldMeshDevice{box_meshRole} = $hash->{READINGS}{box_meshRole}{VAL} if defined $hash->{READINGS}{box_meshRole}{VAL};

     # xhr 1 lang de page wlanmesh xhrId all
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "wlanmesh";
     push @webCmdArray, "xhrId"       => "all";

     my $resultMesh = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;
     my $tmpMesh;

     if(defined $resultMesh->{Error}) {
       $tmpMesh = FRITZBOX_ERR_Result($hash, $resultMesh);
       FRITZBOX_Log $hash, 3, "ERROR: " . $tmpMesh;
     } else {

       FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($resultMesh->{data}->{vars});

       if (defined $resultMesh->{data}->{vars}->{role}->{value}) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_meshRole", $resultMesh->{data}->{vars}->{role}->{value};
      #   delete $oldMeshDevice{box_meshRole} if exists $oldMeshDevice{box_meshRole};
       }

      # if ( $oldMeshDevice{box_meshRole} ne "inactive" ) {
      #   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_meshRole", "inactive";
      # } else {
      #   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_meshRole", "";
      # }
     }
   }

   # WLAN neighbors

   # "xhr 1 lang de page chan xhrId environment useajax 1;

   if (AttrVal( $name, "enableWLANneighbors", "0") && $hash->{LUADATA}) {
     my $nbhPrefix = AttrVal( $name, "wlanNeighborsPrefix",  "nbh_" );
     my %oldWanDevice;

     #collect current mac-readings (to delete the ones that are inactive or disappeared)
     foreach (keys %{ $hash->{READINGS} }) {
       $oldWanDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^${nbhPrefix}/ && defined $hash->{READINGS}{$_}{VAL};
     }

     @webCmdArray = ();
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "chan";
     push @webCmdArray, "xhrId"       => "environment";

     my $resultWan = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;
     my $tmpWan;

     if(defined $resultWan->{Error}) {
       $tmpWan = FRITZBOX_ERR_Result($hash, $resultWan);
       FRITZBOX_Log $hash, 3, "ERROR: " . $tmpWan;
     } else {

       FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($resultWan->{data}->{scanlist});

       $nbViews = 0;
       if (defined $resultWan->{data}->{scanlist}) {
         $views = $resultWan->{data}->{scanlist};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         eval {
           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             my $dName = $resultWan->{data}->{scanlist}->[$i]->{ssid};
             $dName   .= " (Kanal: " . $resultWan->{data}->{scanlist}->[$i]->{channel};
             $dName   .= ", Band: " . $resultWan->{data}->{scanlist}->[$i]->{bandId} . ")";

             $rName  = $resultWan->{data}->{scanlist}->[$i]->{mac};
             $rName =~ s/:/_/g;
             $rName  = $nbhPrefix . $rName;
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, $dName;
             delete $oldWanDevice{$rName} if exists $oldWanDevice{$rName};
           }
         };
         $rName  = "box_wlan_lastScanTime";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $rName, $resultWan->{data}->{lastScantime};
         delete $oldWanDevice{$rName} if exists $oldWanDevice{$rName};
       }
     }

     # Remove inactive or non existing wan-readings in two steps
     foreach ( keys %oldWanDevice ) {
       # set the wan readings to 'inactive' and delete at next readout
       if ( $oldWanDevice{$_} ne "inactive" ) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "inactive";
       }
       else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "";
       }
     }

   } else {
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_lastScanTime", "";
   }

   # DOCSIS Informationen FB Cable
   if (($avmModel =~ "Box") && (lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]") && ($FW1 >= 7) && ($FW2 >= 21) && $hash->{LUADATA}) { # FB Cable
#   if (1==1) {
      my $tmpSIS;
      my $returnStr;

      my $powerLevels;
      my $frequencys;
      my $latencys;
      my $corrErrors;
      my $nonCorrErrors;
      my $mses;

      my %oldDocDevice;

      #collect current mac-readings (to delete the ones that are inactive or disappeared)
      foreach (keys %{ $hash->{READINGS} }) {
        $oldDocDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^box_docsis/ && defined $hash->{READINGS}{$_}{VAL};
      }

      # xhr 1 lang de page docInfo xhrId all no_sidrenew nop
      my @webCmdArray;
      push @webCmdArray, "xhr"         => "1";
      push @webCmdArray, "lang"        => "de";
      push @webCmdArray, "page"        => "docInfo";
      push @webCmdArray, "xhrId"       => "all";
      push @webCmdArray, "no_sidrenew" => "";

#     for debugging
#      my $TestSIS = '{"pid":"docInfo","hide":{"mobile":true,"ssoSet":true,"liveTv":true},"time":[],"data":{"channelDs":{"docsis31":[{"powerLevel":"-1.6","type":"4K","channel":1,"channelID":0,"frequency":"751 - 861"},{"powerLevel":"7.7","type":"4K","channel":2,"channelID":1,"frequency":"175 - 237"}],"docsis30":[{"type":"256QAM","corrErrors":92890,"mse":"-36.4","powerLevel":"5.1","channel":1,"nonCorrErrors":9773,"latency":0.32,"channelID":7,"frequency":"538"},{"type":"256QAM","corrErrors":20553,"mse":"-37.4","powerLevel":"10.2","channel":2,"nonCorrErrors":9420,"latency":0.32,"channelID":26,"frequency":"698"},{"type":"256QAM","corrErrors":28673,"mse":"-37.6","powerLevel":"10.0","channel":3,"nonCorrErrors":140,"latency":0.32,"channelID":25,"frequency":"690"},{"type":"256QAM","corrErrors":25930,"mse":"-37.6","powerLevel":"10.0","channel":4,"nonCorrErrors":170,"latency":0.32,"channelID":27,"frequency":"706"},{"type":"256QAM","corrErrors":98698,"mse":"-36.6","powerLevel":"8.8","channel":5,"nonCorrErrors":9151,"latency":0.32,"channelID":30,"frequency":"746"},{"type":"256QAM","corrErrors":24614,"mse":"-37.4","powerLevel":"9.4","channel":6,"nonCorrErrors":9419,"latency":0.32,"channelID":28,"frequency":"730"},{"type":"256QAM","corrErrors":25882,"mse":"-37.4","powerLevel":"9.9","channel":7,"nonCorrErrors":9308,"latency":0.32,"channelID":24,"frequency":"682"},{"type":"256QAM","corrErrors":33817,"mse":"-37.4","powerLevel":"9.8","channel":8,"nonCorrErrors":146,"latency":0.32,"channelID":23,"frequency":"674"},{"type":"256QAM","corrErrors":112642,"mse":"-37.6","powerLevel":"7.8","channel":9,"nonCorrErrors":7783,"latency":0.32,"channelID":3,"frequency":"490"},{"type":"256QAM","corrErrors":41161,"mse":"-37.6","powerLevel":"9.8","channel":10,"nonCorrErrors":203,"latency":0.32,"channelID":21,"frequency":"658"},{"type":"256QAM","corrErrors":33219,"mse":"-37.4","powerLevel":"8.8","channel":11,"nonCorrErrors":10962,"latency":0.32,"channelID":18,"frequency":"634"},{"type":"256QAM","corrErrors":32680,"mse":"-37.6","powerLevel":"9.2","channel":12,"nonCorrErrors":145,"latency":0.32,"channelID":19,"frequency":"642"},{"type":"256QAM","corrErrors":33001,"mse":"-37.4","powerLevel":"9.8","channel":13,"nonCorrErrors":7613,"latency":0.32,"channelID":22,"frequency":"666"},{"type":"256QAM","corrErrors":42666,"mse":"-37.4","powerLevel":"8.1","channel":14,"nonCorrErrors":172,"latency":0.32,"channelID":17,"frequency":"626"},{"type":"256QAM","corrErrors":41023,"mse":"-37.4","powerLevel":"9.3","channel":15,"nonCorrErrors":10620,"latency":0.32,"channelID":20,"frequency":"650"},{"type":"256QAM","corrErrors":106921,"mse":"-37.6","powerLevel":"7.4","channel":16,"nonCorrErrors":356,"latency":0.32,"channelID":4,"frequency":"498"},{"type":"256QAM","corrErrors":86650,"mse":"-36.4","powerLevel":"4.9","channel":17,"nonCorrErrors":85,"latency":0.32,"channelID":12,"frequency":"578"},{"type":"256QAM","corrErrors":91838,"mse":"-36.4","powerLevel":"4.8","channel":18,"nonCorrErrors":168,"latency":0.32,"channelID":8,"frequency":"546"},{"type":"256QAM","corrErrors":110719,"mse":"-35.8","powerLevel":"4.5","channel":19,"nonCorrErrors":103,"latency":0.32,"channelID":10,"frequency":"562"},{"type":"256QAM","corrErrors":111846,"mse":"-37.6","powerLevel":"8.2","channel":20,"nonCorrErrors":247,"latency":0.32,"channelID":2,"frequency":"482"},{"type":"256QAM","corrErrors":668242,"mse":"-36.6","powerLevel":"5.8","channel":21,"nonCorrErrors":6800,"latency":0.32,"channelID":5,"frequency":"522"},{"type":"256QAM","corrErrors":104070,"mse":"-36.6","powerLevel":"5.3","channel":22,"nonCorrErrors":149,"latency":0.32,"channelID":6,"frequency":"530"},{"type":"256QAM","corrErrors":120994,"mse":"-35.8","powerLevel":"4.4","channel":23,"nonCorrErrors":10240,"latency":0.32,"channelID":9,"frequency":"554"},{"type":"256QAM","corrErrors":59145,"mse":"-36.4","powerLevel":"5.3","channel":24,"nonCorrErrors":9560,"latency":0.32,"channelID":11,"frequency":"570"},{"type":"256QAM","corrErrors":118271,"mse":"-37.6","powerLevel":"8.4","channel":25,"nonCorrErrors":810,"latency":0.32,"channelID":1,"frequency":"474"},{"type":"256QAM","corrErrors":40255,"mse":"-37.4","powerLevel":"6.5","channel":26,"nonCorrErrors":13474,"latency":0.32,"channelID":15,"frequency":"602"},{"type":"256QAM","corrErrors":62716,"mse":"-36.4","powerLevel":"5.3","channel":27,"nonCorrErrors":9496,"latency":0.32,"channelID":13,"frequency":"586"},{"type":"256QAM","corrErrors":131364,"mse":"-36.6","powerLevel":"8.9","channel":28,"nonCorrErrors":12238,"latency":0.32,"channelID":29,"frequency":"738"}]},"oem":"lgi","readyState":"ready","channelUs":{"docsis31":[],"docsis30":[{"powerLevel":"43.0","type":"64QAM","channel":1,"multiplex":"ATDMA","channelID":4,"frequency":"51"},{"powerLevel":"44.3","type":"64QAM","channel":2,"multiplex":"ATDMA","channelID":2,"frequency":"37"},{"powerLevel":"43.8","type":"64QAM","channel":3,"multiplex":"ATDMA","channelID":3,"frequency":"45"},{"powerLevel":"45.8","type":"64QAM","channel":4,"multiplex":"ATDMA","channelID":1,"frequency":"31"}]}},"sid":"14341afbc7d83b4c"}';
#      my $TestSIS = '{"pid":"docInfo","hide":{"mobile":true,"ssoSet":true,"liveTv":true},"time":[],"data":{"channelDs":{"docsis30":[{"type":"256QAM","corrErrors":92890,"mse":"-36.4","powerLevel":"5.1","channel":1,"nonCorrErrors":9773,"latency":0.32,"channelID":7,"frequency":"538"},{"type":"256QAM","corrErrors":20553,"mse":"-37.4","powerLevel":"10.2","channel":2,"nonCorrErrors":9420,"latency":0.32,"channelID":26,"frequency":"698"},{"type":"256QAM","corrErrors":28673,"mse":"-37.6","powerLevel":"10.0","channel":3,"nonCorrErrors":140,"latency":0.32,"channelID":25,"frequency":"690"},{"type":"256QAM","corrErrors":25930,"mse":"-37.6","powerLevel":"10.0","channel":4,"nonCorrErrors":170,"latency":0.32,"channelID":27,"frequency":"706"},{"type":"256QAM","corrErrors":98698,"mse":"-36.6","powerLevel":"8.8","channel":5,"nonCorrErrors":9151,"latency":0.32,"channelID":30,"frequency":"746"},{"type":"256QAM","corrErrors":24614,"mse":"-37.4","powerLevel":"9.4","channel":6,"nonCorrErrors":9419,"latency":0.32,"channelID":28,"frequency":"730"},{"type":"256QAM","corrErrors":25882,"mse":"-37.4","powerLevel":"9.9","channel":7,"nonCorrErrors":9308,"latency":0.32,"channelID":24,"frequency":"682"},{"type":"256QAM","corrErrors":33817,"mse":"-37.4","powerLevel":"9.8","channel":8,"nonCorrErrors":146,"latency":0.32,"channelID":23,"frequency":"674"},{"type":"256QAM","corrErrors":112642,"mse":"-37.6","powerLevel":"7.8","channel":9,"nonCorrErrors":7783,"latency":0.32,"channelID":3,"frequency":"490"},{"type":"256QAM","corrErrors":41161,"mse":"-37.6","powerLevel":"9.8","channel":10,"nonCorrErrors":203,"latency":0.32,"channelID":21,"frequency":"658"},{"type":"256QAM","corrErrors":33219,"mse":"-37.4","powerLevel":"8.8","channel":11,"nonCorrErrors":10962,"latency":0.32,"channelID":18,"frequency":"634"},{"type":"256QAM","corrErrors":32680,"mse":"-37.6","powerLevel":"9.2","channel":12,"nonCorrErrors":145,"latency":0.32,"channelID":19,"frequency":"642"},{"type":"256QAM","corrErrors":33001,"mse":"-37.4","powerLevel":"9.8","channel":13,"nonCorrErrors":7613,"latency":0.32,"channelID":22,"frequency":"666"},{"type":"256QAM","corrErrors":42666,"mse":"-37.4","powerLevel":"8.1","channel":14,"nonCorrErrors":172,"latency":0.32,"channelID":17,"frequency":"626"},{"type":"256QAM","corrErrors":41023,"mse":"-37.4","powerLevel":"9.3","channel":15,"nonCorrErrors":10620,"latency":0.32,"channelID":20,"frequency":"650"},{"type":"256QAM","corrErrors":106921,"mse":"-37.6","powerLevel":"7.4","channel":16,"nonCorrErrors":356,"latency":0.32,"channelID":4,"frequency":"498"},{"type":"256QAM","corrErrors":86650,"mse":"-36.4","powerLevel":"4.9","channel":17,"nonCorrErrors":85,"latency":0.32,"channelID":12,"frequency":"578"},{"type":"256QAM","corrErrors":91838,"mse":"-36.4","powerLevel":"4.8","channel":18,"nonCorrErrors":168,"latency":0.32,"channelID":8,"frequency":"546"},{"type":"256QAM","corrErrors":110719,"mse":"-35.8","powerLevel":"4.5","channel":19,"nonCorrErrors":103,"latency":0.32,"channelID":10,"frequency":"562"},{"type":"256QAM","corrErrors":111846,"mse":"-37.6","powerLevel":"8.2","channel":20,"nonCorrErrors":247,"latency":0.32,"channelID":2,"frequency":"482"},{"type":"256QAM","corrErrors":668242,"mse":"-36.6","powerLevel":"5.8","channel":21,"nonCorrErrors":6800,"latency":0.32,"channelID":5,"frequency":"522"},{"type":"256QAM","corrErrors":104070,"mse":"-36.6","powerLevel":"5.3","channel":22,"nonCorrErrors":149,"latency":0.32,"channelID":6,"frequency":"530"},{"type":"256QAM","corrErrors":120994,"mse":"-35.8","powerLevel":"4.4","channel":23,"nonCorrErrors":10240,"latency":0.32,"channelID":9,"frequency":"554"},{"type":"256QAM","corrErrors":59145,"mse":"-36.4","powerLevel":"5.3","channel":24,"nonCorrErrors":9560,"latency":0.32,"channelID":11,"frequency":"570"},{"type":"256QAM","corrErrors":118271,"mse":"-37.6","powerLevel":"8.4","channel":25,"nonCorrErrors":810,"latency":0.32,"channelID":1,"frequency":"474"},{"type":"256QAM","corrErrors":40255,"mse":"-37.4","powerLevel":"6.5","channel":26,"nonCorrErrors":13474,"latency":0.32,"channelID":15,"frequency":"602"},{"type":"256QAM","corrErrors":62716,"mse":"-36.4","powerLevel":"5.3","channel":27,"nonCorrErrors":9496,"latency":0.32,"channelID":13,"frequency":"586"},{"type":"256QAM","corrErrors":131364,"mse":"-36.6","powerLevel":"8.9","channel":28,"nonCorrErrors":12238,"latency":0.32,"channelID":29,"frequency":"738"}]},"oem":"lgi","readyState":"ready","channelUs":{"docsis30":[{"powerLevel":"43.0","type":"64QAM","channel":1,"multiplex":"ATDMA","channelID":4,"frequency":"51"},{"powerLevel":"44.3","type":"64QAM","channel":2,"multiplex":"ATDMA","channelID":2,"frequency":"37"},{"powerLevel":"43.8","type":"64QAM","channel":3,"multiplex":"ATDMA","channelID":3,"frequency":"45"},{"powerLevel":"45.8","type":"64QAM","channel":4,"multiplex":"ATDMA","channelID":1,"frequency":"31"}]}},"sid":"14341afbc7d83b4c"}';
#      my $resultSIS = FRITZBOX_Process_JSON($hash, $TestSIS, "14341afbc7d83b4c", ""); ;
      
      my $resultSIS = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

      if(defined $resultSIS->{Error}) {
        $tmpSIS = FRITZBOX_ERR_Result($hash, $resultSIS);
        FRITZBOX_Log $hash, 3, "ERROR: " . $tmpSIS;
      } else {

        FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($resultSIS->{data});

        $nbViews = 0;
        if (defined $resultSIS->{data}->{channelUs}->{docsis30}) {
          $views = $resultSIS->{data}->{channelUs}->{docsis30};
          $nbViews = scalar @$views;
        }

        if ($nbViews > 0) {

          $powerLevels = "";
          $frequencys  = "";

          eval {
            for(my $i = 0; $i <= $nbViews - 1; $i++) {
              $powerLevels .= $resultSIS->{data}->{channelUs}->{docsis30}->[$i]->{powerLevel} . " ";
              $frequencys  .= $resultSIS->{data}->{channelUs}->{docsis30}->[$i]->{frequency} . " ";
            }

            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Us_powerLevels", substr($powerLevels,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Us_frequencys", substr($frequencys,0,-1);
            delete $oldDocDevice{box_docsis30_Us_powerLevels} if exists $oldDocDevice{box_docsis30_Us_powerLevels};
            delete $oldDocDevice{box_docsis30_Us_frequencys} if exists $oldDocDevice{box_docsis30_Us_frequencys};
          };
        }

        $nbViews = 0;
        if (defined $resultSIS->{data}->{channelUs}->{docsis31}) {
          $views = $resultSIS->{data}->{channelUs}->{docsis31};
          $nbViews = scalar @$views;
        }

        if ($nbViews > 0) {

          $powerLevels = "";
          $frequencys  = "";

          eval {
            for(my $i = 0; $i <= $nbViews - 1; $i++) {
              $powerLevels .= $resultSIS->{data}->{channelUs}->{docsis31}->[$i]->{powerLevel} . " ";
              $frequencys  .= $resultSIS->{data}->{channelUs}->{docsis31}->[$i]->{frequency} . " ";
            }
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis31_Us_powerLevels", substr($powerLevels,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis31_Us_frequencys", substr($frequencys,0,-1);
            delete $oldDocDevice{box_docsis31_Us_powerLevels} if exists $oldDocDevice{box_docsis31_Us_powerLevels};
            delete $oldDocDevice{box_docsis31_Us_frequencys} if exists $oldDocDevice{box_docsis31_Us_frequencys};
          };

        }

        $nbViews = 0;
        if (defined $resultSIS->{data}->{channelDs}->{docsis30}) {
          $views = $resultSIS->{data}->{channelDs}->{docsis30};
          $nbViews = scalar @$views;
        }

        if ($nbViews > 0) {

          $powerLevels   = "";
          $latencys      = "";
          $frequencys    = "";
          $corrErrors    = "";
          $nonCorrErrors = "";
          $mses          = "";

          eval {
            for(my $i = 0; $i <= $nbViews - 1; $i++) {
              $powerLevels   .= $resultSIS->{data}->{channelDs}->{docsis30}->[$i]->{powerLevel} . " ";
              $latencys      .= $resultSIS->{data}->{channelDs}->{docsis30}->[$i]->{latency} . " ";
              $frequencys    .= $resultSIS->{data}->{channelDs}->{docsis30}->[$i]->{frequency} . " ";
              $corrErrors    .= $resultSIS->{data}->{channelDs}->{docsis30}->[$i]->{corrErrors} . " ";
              $nonCorrErrors .= $resultSIS->{data}->{channelDs}->{docsis30}->[$i]->{nonCorrErrors} . " ";
              $mses          .= $resultSIS->{data}->{channelDs}->{docsis30}->[$i]->{mse} . " ";
            }
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Ds_powerLevels", substr($powerLevels,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Ds_latencys", substr($latencys,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Ds_frequencys", substr($frequencys,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Ds_corrErrors", substr($corrErrors,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Ds_nonCorrErrors", substr($latencys,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis30_Ds_mses", substr($mses,0,-1);
            delete $oldDocDevice{box_docsis30_Ds_powerLevels} if exists $oldDocDevice{box_docsis30_Ds_powerLevels};
            delete $oldDocDevice{box_docsis30_Ds_latencys} if exists $oldDocDevice{box_docsis30_Ds_latencys};
            delete $oldDocDevice{box_docsis30_Ds_frequencys} if exists $oldDocDevice{box_docsis30_Ds_frequencys};
            delete $oldDocDevice{box_docsis30_Ds_corrErrors} if exists $oldDocDevice{box_docsis30_Ds_corrErrors};
            delete $oldDocDevice{box_docsis30_Ds_nonCorrErrors} if exists $oldDocDevice{box_docsis30_Ds_nonCorrErrors};
            delete $oldDocDevice{box_docsis30_Ds_mses} if exists $oldDocDevice{box_docsis30_Ds_mses};
          };

        }

        $nbViews = 0;
        if (defined $resultSIS->{data}->{channelDs}->{docsis31}) {
          $views = $resultSIS->{data}->{channelDs}->{docsis31};
          $nbViews = scalar @$views;
        }

        if ($nbViews > 0) {

          $powerLevels = "";
          $frequencys  = "";

          eval {
            for(my $i = 0; $i <= $nbViews - 1; $i++) {
              $powerLevels .= $resultSIS->{data}->{channelDs}->{docsis31}->[$i]->{powerLevel} . " ";
              $frequencys  .= $resultSIS->{data}->{channelDs}->{docsis31}->[$i]->{frequency} . " ";
            }
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis31_Ds_powerLevels", substr($powerLevels,0,-1);
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_docsis31_Ds_frequencys", substr($frequencys,0,-1);
            delete $oldDocDevice{box_docsis31_Ds_powerLevels} if exists $oldDocDevice{box_docsis31_Ds_powerLevels};
            delete $oldDocDevice{box_docsis31_Ds_frequencys} if exists $oldDocDevice{box_docsis31_Ds_frequencys};
          };
        }
      }

      # Remove inactive or non existing wan-readings in two steps
      foreach ( keys %oldDocDevice ) {
        # set the wan readings to 'inactive' and delete at next readout
        if ( $oldDocDevice{$_} ne "inactive" ) {
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "inactive";
        }
        else {
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "";
        }
      }
   }

   if ( $hash->{TR064} == 1 && $hash->{SECPORT} ) {

      my $strCurl;

      if (($avmModel =~ "Box") && (lc($avmModel) !~ "5[4,5][9,3]0|40[2,4,6]0|68[2,5]0|6[4,5,6][3,6,9][0,1]|fiber|cable") ) { # FB ohne VDSL
         my @tr064CmdArray = (["WANDSLInterfaceConfig:1", "wandslifconfig1", "GetInfo"]);
         my @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         if ($tr064Result[0]->{UPnPError}) {
            $strCurl = Dumper (@tr064Result);
            FRITZBOX_Log $hash, 2, "ERROR: Curl-> " . $strCurl;
         } else {
            $strCurl = Dumper (@tr064Result);
            FRITZBOX_Log $hash, 5, "DEBUG: Curl-> " . $strCurl;
            if ($strCurl =~ /.NewDownstreamCurrRate. => '(.*)'/) {
               FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_vdsl_downStreamRate", $1/1000;

            } else {
               FRITZBOX_Log $hash, 4, "INFO: box_vdsl_downStreamRate Curl-> " . $strCurl;
            }

            if ($strCurl =~ /.NewUpstreamCurrRate. => '(.*)'/) {
               FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_vdsl_upStreamRate", $1/1000;
            } else {
               FRITZBOX_Log $hash, 4, "INFO: box_vdsl_upStreamRate Curl-> " . $strCurl;
            }
         }
      } else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_vdsl_downStreamRate", "";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_vdsl_upStreamRate", "";
      }

      # box_uptimeConnect
      $strCurl = `curl "http://$host:49000/igdupnp/control/WANIPConn1" -H "Content-Type: text/xml; charset=\'utf-8\'" -H "SoapAction:urn:schemas-upnp-org:service:WANIPConnection:1#GetStatusInfo" -d "<?xml version=\'1.0\' encoding=\'utf-8\'?> <s:Envelope s:encodingStyle=\'http://schemas.xmlsoap.org/soap/encoding/\' xmlns:s=\'http://schemas.xmlsoap.org/soap/envelope/\'> <s:Body> <u:GetStatusInfo xmlns:u=\'urn:schemas-upnp-org:service:WANIPConnection:1\' /> </s:Body> </s:Envelope>" -s`;

      FRITZBOX_Log $hash, 5, "DEBUG: Curl-> " . $strCurl;

      if($strCurl =~ m/<NewConnectionStatus>(.*?)<\/NewConnectionStatus>/i) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_connect", $1;
      }
      if($strCurl =~ m/<NewLastConnectionError>(.*?)<\/NewLastConnectionError>/i) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_last_connect_err", $1;
      }

      if($strCurl =~ m/<NewUptime>(.*?)<\/NewUptime>/i) {
         $Sek = $1;
         $Tag  = int($Sek/86400);
         $Std  = int(($Sek/3600)-(24*$Tag));
         $Min = int(($Sek/60)-($Std*60)-(1440*$Tag));
         $Sek -= (($Min*60)+($Std*3600)+(86400*$Tag));

         $Std = substr("0".$Std,-2);
         $Min = substr("0".$Min,-2);
         $Sek = substr("0".$Sek,-2);

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_uptimeConnect", $1 . " sec = " . $Tag . "T $Std:$Min:$Sek";
      }

      # box_ipExtern
      $strCurl = `curl "http://$host:49000/igdupnp/control/WANIPConn1" -H "Content-Type: text/xml; charset=\'utf-8\'" -H "SoapAction:urn:schemas-upnp-org:service:WANIPConnection:1#GetExternalIPAddress" -d "<?xml version=\'1.0\' encoding=\'utf-8\'?> <s:Envelope s:encodingStyle=\'http://schemas.xmlsoap.org/soap/encoding/\' xmlns:s=\'http://schemas.xmlsoap.org/soap/envelope/\'> <s:Body> <u:GetExternalIPAddress xmlns:u=\'urn:schemas-upnp-org:service:WANIPConnection:1\' /> </s:Body> </s:Envelope>" -s`;

      FRITZBOX_Log $hash, 5, "DEBUG: Curl-> " . $strCurl;

      if($strCurl =~ m/<NewExternalIPAddress>(.*?)<\/NewExternalIPAddress>/i) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_ipExtern", $1;
      }

      # box_ipv6
      $strCurl = `curl "http://$host:49000/igdupnp/control/WANIPConn1" -H "Content-Type: text/xml; charset=\'utf-8\'" -H "SoapAction:urn:schemas-upnp-org:service:WANIPConnection:1#X_AVM_DE_GetExternalIPv6Address" -d "<?xml version=\'1.0\' encoding=\'utf-8\'?> <s:Envelope s:encodingStyle=\'http://schemas.xmlsoap.org/soap/encoding/\' xmlns:s=\'http://schemas.xmlsoap.org/soap/envelope/\'> <s:Body> <u:GetExternalIPAddress xmlns:u=\'urn:schemas-upnp-org:service:WANIPConnection:1\' /> </s:Body> </s:Envelope>" -s`;

      FRITZBOX_Log $hash, 5, "DEBUG: Curl-> " . $strCurl;

      if($strCurl =~ m/<NewPrefixLength>(.*?)<\/NewPrefixLength>/i) {
         if ($1 != 0) {
            if($strCurl =~ m/<NewExternalIPv6Address>(.*?)<\/NewExternalIPv6Address>/i) {
               FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_ipv6Extern", $1; 

               $strCurl = `curl "http://$host:49000/igdupnp/control/WANIPConn1" -H "Content-Type: text/xml; charset=\'utf-8\'" -H "SoapAction:urn:schemas-upnp-org:service:WANIPConnection:1#X_AVM_DE_GetIPv6Prefix" -d "<?xml version=\'1.0\' encoding=\'utf-8\'?> <s:Envelope s:encodingStyle=\'http://schemas.xmlsoap.org/soap/encoding/\' xmlns:s=\'http://schemas.xmlsoap.org/soap/envelope/\'> <s:Body> <u:GetExternalIPAddress xmlns:u=\'urn:schemas-upnp-org:service:WANIPConnection:1\' /> </s:Body> </s:Envelope>" -s`;

               FRITZBOX_Log $hash, 5, "DEBUG: Curl-> " . $strCurl;

               if($strCurl =~ m/<NewIPv6Prefix>(.*?)<\/NewIPv6Prefix>/i) {
                  FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_ipv6Prefix", $1;
               }
            }
         }
      }

   }

# statistics
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HINWEIS", "");

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   my $returnStr = join('|', @roReadings );

   FRITZBOX_Log $hash, 4, "INFO: Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process (".length ($returnStr)."): ".$returnStr;
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

   FRITZBOX_Log $hash, 5, "DEBUG: Back at main process";

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

   my @reading_list = split(/\,/, AttrVal($name, "disableBoxReadings", "none"));

   readingsBeginUpdate($hash);

   if ( defined $values{Error} ) {
      readingsBulkUpdate( $hash, "lastReadout", $values{Error} );
      readingsBulkUpdate( $hash, "state", $values{Error} );
      if (defined $values{"fhem->sidTime"}) {
         $hash->{fhem}{sidTime} = $values{"fhem->sidTime"};
         FRITZBOX_Log $hash, 5, "DEBUG: Reset SID";
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
         $values{ "box_rateDown" } = (grep { /^(box_rateDown)$/ } @reading_list) ? "" : sprintf ("%.3f", ($valueHigh+$valueLow) / $time ) ;
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
         $values{ "box_rateUp" } = (grep { /^(box_rateUp)$/ } @reading_list) ? "" : sprintf ("%.3f", ($valueHigh+$valueLow) / $time ) ;
      }

   # Fill all handed over readings
      my $x = 0;
      while (my ($rName, $rValue) = each(%values) ) {
      #hash values
         if ($rName =~ /->/) {
         # 4 levels
            my ($rName1, $rName2, $rName3, $rName4) = split /->/, $rName;
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
            delete ($hash->{HINWEIS}) if $rName2 eq "HINWEIS" && $rValue eq "";
         }
         elsif ($rName eq "box_fwVersion" && defined $values{box_fwUpdate}) {
            $rValue .= " (old)" if $values{box_fwUpdate} eq "1";
         }
         elsif ($rName eq "box_model") {
            $hash->{MODEL} = $rValue;
            if (($rValue =~ "Box") && (lc($rValue) =~ "6[4,5,6][3,6,9][0,1]") ) {
            #if (1==1) {
                my $cable = "boxUser "
                ."disable:0,1 "
            #    ."defaultCallerName "
            #    ."defaultUploadDir "
                ."fritzBoxIP "
                ."INTERVAL "
                ."m3uFileLocal "
                ."m3uFileURL "
            #    ."ringWithIntern:0,1,2 "
            #    ."useGuiHack:0,1 "
                ."userTickets "
                ."enablePassivLanDevices:0,1 "
                ."enableVPNShares:0,1 "
                ."enableUserInfo:0,1 "
                ."enableAlarmInfo:0,1 "
                ."enableWLANneighbors:0,1 "
                ."wlanNeighborsPrefix "
                ."disableDectInfo:0,1 "
                ."disableFonInfo:0,1 "
                ."enableSIP:0,1 "
                ."disableBoxReadings:multiple-strict,box_connect,box_cpuTemp,box_dect,box_dsl_downStream,box_dsl_upStream,"
                                ."box_guestWlan,box_guestWlanCount,box_guestWlanRemain,box_macFilter_active,box_ipExtern,box_ipv6Extern,"
                                ."box_ipv6Prefix,box_last_connect_err,box_moh,box_powerRate,box_rateDown,"
                                ."box_rateUp,box_stdDialPort,box_tr064,box_tr069,box_uptimeConnect,box_uptime,box_wlanCount,box_wlan_2.4GHz,"
                                ."box_wlan_5GHz,box_vdsl_downStreamRate,box_vdsl_upStreamRate," #,box_model,box_oem
                                ."box_docsis30_Ds_powerLevels,box_docsis30_Ds_latencys,box_docsis30_Ds_frequencys,box_docsis30_Ds_corrErrors,box_docsis30_Ds_nonCorrErrors,box_docsis30_Ds_mses,"
                                ."box_docsis30_Us_powerLevels,box_docsis30_Us_frequencys,box_docsis31_Us_powerLevels,box_docsis31_Us_frequencys,box_docsis31_Ds_powerLevels,box_docsis31_Ds_frequencys "
                ."deviceInfo:sortable,ipv4,name,uid,connection,speed,rssi,_noDefInf_ "
                .$readingFnAttributes;

              setDevAttrList($hash->{NAME}, $cable);
            } else {
              setDevAttrList($hash->{NAME});
            }
            $rValue .= " [".$values{box_oem}."]" if $values{box_oem};
         }

         if ($rName !~ /->|box_fwUpdate|box_oem|readoutTime/) {
            if ($rValue ne "") {
               readingsBulkUpdate( $hash, $rName, $rValue );
               FRITZBOX_Log $hash, 5, "DEBUG: SET $rName = '$rValue'";
            }
            elsif ( exists $hash->{READINGS}{$rName} ) {
               delete $hash->{READINGS}{$rName};
               FRITZBOX_Log $hash, 5, "DEBUG: Delete reading $rName.";
            }
            else  {
               FRITZBOX_Log $hash, 5, "DEBUG: Ignore reading $rName.";
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
         $newState .=" (Remain: ".$values{box_guestWlanRemain}." min)" if $values{box_guestWlan} eq "on" && $values{box_guestWlanRemain} > 0;
         readingsBulkUpdate( $hash, "state", $newState);
         FRITZBOX_Log $hash, 5, "DEBUG: SET state = '$newState'";
      }

   # adapt TR064-Mode
      if ( defined $values{box_tr064} ) {
         if ( $values{box_tr064} eq "off" && defined $hash->{SECPORT} ) {
            FRITZBOX_Log $hash, 3, "INFO: TR-064 is switched off";
            delete $hash->{SECPORT};
            $hash->{TR064} = 0;
         }
         elsif ( $values{box_tr064} eq "on" && not defined $hash->{SECPORT} ) {
            FRITZBOX_Log $hash, 3, "INFO: TR-064 is switched on";
            my $tr064Port = FRITZBOX_TR064_Init ($hash, $hash->{HOST});
            $hash->{SECPORT} = $tr064Port if $tr064Port;
            $hash->{TR064} = 1;
         }
      }

      my $msg = keys( %values ) . " values captured in " . $values{readoutTime} . " s";
      readingsBulkUpdate( $hash, "lastReadout", $msg );
      FRITZBOX_Log $hash, 5, "DEBUG: BulkUpdate lastReadout: " . $msg;
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
  FRITZBOX_Log $hash, 1, "INFO: " . $msg;
}

#######################################################################
sub FRITZBOX_Readout_Format($$$)
{
   my ($hash, $format, $readout) = @_;

   $readout = "" unless defined $readout;

   return $readout       unless defined( $format ) && $format ne "";
# return $readout       unless $readout ne "" && $format ne "" ; #Funktioniert nicht bei $format "01"

   if ($format eq "01" && $readout ne "1") {
      $readout = "0";
   }

   return $readout unless $readout ne "";

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
   my $xline       = ( caller(0) )[2];

   my $name = $hash->{NAME};
   my @reading_list = split(/\,/, AttrVal($name, "disableBoxReadings", "none"));

   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];

   $rFormat = "" unless defined $rFormat;
   $rValue = FRITZBOX_Readout_Format ($hash, $rFormat, $rValue);

   $rValue = (grep { /^($rName)$/ } @reading_list) ? "" : $rValue;

   push @{$roReadings}, $rName . "|" . $rValue ;

   FRITZBOX_Log $hash, 5, "DEBUG: $rName: $rValue";
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
      FRITZBOX_Log $hash, 1, "INFO: Old command still running. Killing old command: ".$cmdBuffer[0];
      shift @cmdBuffer;
      BlockingKill( $hash->{helper}{CMD_RUNNING_PID} );
      # stop FHEM, giving FritzBox some time to free the memory
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

# Preparing SET Call
   if ($val[0] eq "call") {
      shift @val;
      $timeout = 60;
      $timeout = $val[2]         if defined $val[2] && $val[2] =~/^\d+$/;
      $timeout += 30;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_Call_Web";
   }
# Preparing SET guestWLAN
   elsif ($val[0] eq "guestwlan") {
      shift @val;
      $timeout = 20;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_GuestWlan_Web";
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
   }
# Preparing SET WLAN
   elsif ($val[0] eq "wlan") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Wlan_Run_Web";
   }
# Preparing SET WLAN2.4
   elsif ( $val[0] =~ /^wlan(2\.4|5)$/ ) {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Wlan_Run_Web";
   }
# Preparing SET rescanWLANneighbors
   elsif ( $val[0] eq "rescanwlanneighbors" ) {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_rescan_neighborhood";
   }
# Preparing SET macFilter
   elsif ($val[0] eq "macfilter") {
      $timeout = 25;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_macFilter";
   }
# Preparing SET chgProfile
   elsif ($val[0] eq "chgprofile") {
      $timeout = 25;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_chgProfile";
   }
# Preparing SET lockLandevice
   elsif ($val[0] eq "locklandevice") {
      $timeout = 25;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_lockLandevice";
   }
# Preparing SET enableVPNshare
   elsif ($val[0] eq "enablevpnshare") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Run_enableVPNshare";
   }
# No valid set operation
   else {
      my $msg = "Unknown command '".join( " ", @val )."'";
      FRITZBOX_Log $hash, 1, "INFO: " . $msg;
      return $msg;
   }

# Starting new command
   FRITZBOX_Log $hash, 4, "INFO: Fork process $cmdFunction";
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
      Log 1, "FATAL ERROR: no parameter handed over";
      return;
   }

   my ($name, $success, $result) = split("\\|", $string, 3);
   my $hash = $defs{$name};

   FRITZBOX_Log $hash, 4, "INFO: Back at main process";

   shift (@cmdBuffer);
   delete($hash->{helper}{CMD_RUNNING_PID});

   if ( $success !~ /1|2/ )
   {
      FRITZBOX_Log $hash, 1, "ERROR: " . $result;
      FRITZBOX_Readout_Process ( $hash, "Error|" . $result );
   }
   elsif ( $success == 1 )
   {
      FRITZBOX_Log $hash, 4, "INFO: " . $result;
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
  FRITZBOX_Log $hash, 1, "INFO: Timeout reached for: $lastCmd";
}

#######################################################################
sub FRITZBOX_Run_macFilter($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();

   # xhr 1
   # MACFilter 0
   # currMACFilter 1
   # apply nop
   # lang de
   # page wKey

   # xhr 1 MACFilter 0 currMACFilter 1 apply nop lang de page wKey
   # xhr 1 MACFilter 1 currMACFilter 0 apply nop lang de page wKey

   my $queryStr;
   my $returnStr;

   my $switch = $val[0];
      $switch =~ s/on/1/;
      $switch =~ s/off/0/;

   my $currMACFilter = ReadingsVal($name, "box_macFilter_active", "ERROR");

   $queryStr = "&box_macFilter_active=wlan:settings/is_macfilter_active";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   if ( defined $result->{Error} ) {
      FRITZBOX_Log $hash, 2, "ERROR: macFilter -> " . $result->{Error};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->ERROR: " . $result->{Error};
   } elsif ( defined $result->{AuthorizationRequired} ) {
      FRITZBOX_Log $hash, 2, "ERROR: AuthorizationRequired -> " . $result->{AuthorizationRequired};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->ERROR: AuthorizationRequired";
   } elsif ( ! defined ($result->{box_macFilter_active}) ) {
      FRITZBOX_Log $hash, 2, "ERROR: MAC Filter not available";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->ERROR: MAC Filter not available";
   } elsif ( $switch == $result->{box_macFilter_active} ) {
      FRITZBOX_Log $hash, 4, "INFO: no macFilter change necessary";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->INFO: change necessary";
   } else {

      push @webCmdArray, "xhr" => "1";

      push @webCmdArray, "MACFilter"     => $switch;
      push @webCmdArray, "currMACFilter" => $switch == 1? 0 : 1;

      push @webCmdArray, "apply" => "";
      push @webCmdArray, "lang"  => "de";
      push @webCmdArray, "page"  => "wKey";

      my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

      my $FW1 = substr($fwV[1],0,2);
      my $FW2 = substr($fwV[2],0,2);

      FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

      FRITZBOX_Log $hash, 5, "DEBUG: set $name $cmd " . join(" ", @webCmdArray);

      $queryStr = "'xhr' => '1'\n";
      $queryStr = "'MACFilter'     => '" . $switch . "'\n";
      $queryStr = "'currMACFilter' => '" . $switch == 1? 0 : 1 . "'\n";

      $queryStr = "'apply' => ''\n";
      $queryStr = "'lang'  => 'de'\n";
      $queryStr = "'page'  => 'wKey'\n";

      FRITZBOX_Log $hash, 5, "DEBUG: get $name $cmd " . $queryStr;

      $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

      if(defined $result->{Error}) {
         FRITZBOX_Log $hash, 2, "ERROR: setting MAC Filter: " . $result->{Error};
         return "ERROR: setting MAC Filter: " . $result->{Error};
      } else {

         $queryStr = "&box_macFilter_active=wlan:settings/is_macfilter_active";

         $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

         if ( defined $result->{Error} ) {
            FRITZBOX_Log $hash, 2, "ERROR: macFilter -> " . $result->{Error};
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->ERROR: " . $result->{Error};
         } elsif ( defined $result->{AuthorizationRequired} ) {
            FRITZBOX_Log $hash, 2, "ERROR: AuthorizationRequired -> " . $result->{AuthorizationRequired};
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->ERROR: AuthorizationRequired";
         } elsif( !defined ($result->{box_macFilter_active}) ) {
            FRITZBOX_Log $hash, 2, "ERROR: MAC Filter not available";
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->ERROR: MAC Filter not available";
         } elsif ( $switch != $result->{box_macFilter_active} ) {
            FRITZBOX_Log $hash, 4, "INFO: no macFilter change necessary";
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->INFO: change necessary";
         } else {

            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $val[0];

            FRITZBOX_Log $hash, 4, "INFO: macFilter set to " . $val[0];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "macFilterStat", "macFilter->set to " . $val[0];
         }
      }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr,"");

}

#######################################################################
sub FRITZBOX_Run_rescan_neighborhood($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();

   # xhr 1 refresh nop lang de page chan
   # xhr: 1
   # refresh nop
   # lang: de
   # page: chan

   push @webCmdArray, "xhr"      => "1";
   push @webCmdArray, "refresh"  => "";
   push @webCmdArray, "lang"     => "de";
   push @webCmdArray, "page"     => "chan";

   FRITZBOX_Log $hash, 5, "DEBUG: data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

   if(defined $result->{Error}) {
     FRITZBOX_Log $hash, 2, "ERROR: rescan WLAN neighborhood: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "rescanWLANneighbors", "->ERROR: " . $result->{Error};
   } else {
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "rescanWLANneighbors", "done";
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr,"");

} # End FRITZBOX_Run_rescan_neighborhood

#######################################################################
sub FRITZBOX_Run_chgProfile($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();

   my $dev_name = $hash->{fhem}->{landevice}->{$val[0]};

   my $state = $val[1];

   # xhr: 1
   # dev_name: amazon-echo-show
   # dev_ip3: 59
   # dev_ip: 192.168.0.59
   # static_dhcp: on
   # allow_pcp_and_upnp: off
   # realtimedevice: off
   # kisi_profile: filtprof1
   # interface_id1: 42a2
   # interface_id2: dbff
   # interface_id3: fe51
   # interface_id4: a472
   # back_to_page: netDev
   # dev: landevice7720
   # apply:
   # sid: e921ffcd7bbbd614
   # lang: de
   # page: edit_device

   # ab 7.50
   # xhr: 1
   # dev_name: Wetterstation
   # internetdetail: unlimited / internetdetail: realtime
   # kisi_profile: filtprof1
   # allow_pcp_and_upnp: off
   # dev_ip0: 192
   # dev_ip1: 168
   # dev_ip2: 0
   # dev_ip3: 96
   # dev_ip: 192.168.0.96
   # static_dhcp: on
   # back_to_page: netDev
   # dev: landevice9824
   # apply: true
   # sid: 0f2c4b19eaa23f44
   # lang: de
   # page: edit_device

   my @webCmdArrayP;
   my $queryStr;

   push @webCmdArrayP, "xhr"         => "1";
   push @webCmdArrayP, "lang"        => "de";
   push @webCmdArrayP, "page"        => "kidPro";

   FRITZBOX_Log $hash, 5, "DEBUG: get $name $cmd " . join(" ", @webCmdArrayP);

   $result = FRITZBOX_Lua_Data( $hash, \@webCmdArrayP) ;

   if(defined $result->{Error}) {
      FRITZBOX_Log $hash, 2, "ERROR: changing Kid Profile: " . $result->{Error};
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "chgProfileStat", $val[1] . "->ERROR: " . $result->{Error};
      return "ERROR: $val[1] -> " . $result->{Error};
   } else {

      my $views = $result->{data}->{kidProfiles};
      my $ProfileOK = "false";

      eval {
         foreach my $key (keys %$views) {
            FRITZBOX_Log $hash, 5, "DEBUG: Kid Profiles: ".$key;
            if ($result->{data}->{kidProfiles}->{$key}{Id} eq $val[1]) {
               $ProfileOK = "true";
               last;
            }
         }
      };

      if ($ProfileOK eq "false") {
         FRITZBOX_Log $hash, 2, "ERROR: " . $val[1] . " not available/defined.";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "chgProfileStat", $val[1] . "->ERROR: not available/defined";
      } else {

         FRITZBOX_Log $hash, 4, "INFO: Profile $val[1] available.";

         my $lanDevice_Info = FRITZBOX_Lan_Device_Info( $hash, $val[0], "chgProf");

         return $lanDevice_Info if $lanDevice_Info =~ /ERROR/;

         FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper $lanDevice_Info;

         if($lanDevice_Info->{data}->{vars}->{dev}->{UID} eq $val[0]) {

            my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

            my $FW1 = substr($fwV[1],0,2);
            my $FW2 = substr($fwV[2],0,2);

            FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

            push @webCmdArray, "xhr"                => "1";
            push @webCmdArray, "dev_name"           => $lanDevice_Info->{data}->{vars}->{dev}->{name}->{displayName};
            push @webCmdArray, "dev_ip"             => $lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{ip};
            push @webCmdArray, "kisi_profile"       => $val[1];
            push @webCmdArray, "back_to_page"       => "netDev";
            push @webCmdArray, "dev"                => $val[0];
            push @webCmdArray, "lang"               => "de";

            if ($lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{dhcp} eq "1") {
               push @webCmdArray, "static_dhcp"        => "on";
            } else {
               push @webCmdArray, "static_dhcp"        => "off";
            }

            if ($FW1 <= 7 && $FW2 < 21) {
               push @webCmdArray, "page"      => "edit_device";
            } elsif ($FW1 >= 7 && $FW2 < 50) {
               push @webCmdArray, "page"      => "edit_device2";
            } else {
               push @webCmdArray, "page"      => "edit_device";
            }

            if ($FW1 <= 7 && $FW2 < 50) {
               push @webCmdArray, "dev_ip3"            => (split(/\./, $lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{ip}))[3];

               if ($lanDevice_Info->{data}->{vars}->{dev}->{portForwarding}->{allowForwarding} eq "true") {
                  push @webCmdArray, "allow_pcp_and_upnp" => "on";
               } else {
                  push @webCmdArray, "allow_pcp_and_upnp" => "off";
               }

               if ($lanDevice_Info->{data}->{vars}->{dev}->{realtime}->{state} eq "true") {
                  push @webCmdArray, "realtimedevice"     => "on";
               } else {
                  push @webCmdArray, "realtimedevice"     => "off";
               }

               push @webCmdArray, "interface_id1"      => (split(/:/, $lanDevice_Info->{data}->{vars}->{dev}->{ipv6}->{iface}->{ifaceid}))[2]; #42a2
               push @webCmdArray, "interface_id2"      => (split(/:/, $lanDevice_Info->{data}->{vars}->{dev}->{ipv6}->{iface}->{ifaceid}))[3]; #dbff
               push @webCmdArray, "interface_id3"      => (split(/:/, $lanDevice_Info->{data}->{vars}->{dev}->{ipv6}->{iface}->{ifaceid}))[4]; #fe51
               push @webCmdArray, "interface_id4"      => (split(/:/, $lanDevice_Info->{data}->{vars}->{dev}->{ipv6}->{iface}->{ifaceid}))[5]; #a472
               push @webCmdArray, "apply"              => "";

            } else {
               if ($lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{portForwarding}->{allowForwarding}) {
                  push @webCmdArray, "allow_pcp_and_upnp" => "on";
               } else {
                  push @webCmdArray, "allow_pcp_and_upnp" => "off";
               }

               if ($lanDevice_Info->{data}->{vars}->{dev}->{realtime}->{state} eq "true") {
                  push @webCmdArray, "internetdetail"     => "realtime";
               } else {
                  push @webCmdArray, "internetdetail"  => $lanDevice_Info->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid};
               }

               push @webCmdArray, "dev_ip0"            => (split(/\./, $lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{ip}))[0];
               push @webCmdArray, "dev_ip1"            => (split(/\./, $lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{ip}))[1];
               push @webCmdArray, "dev_ip2"            => (split(/\./, $lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{ip}))[2];
               push @webCmdArray, "dev_ip3"            => (split(/\./, $lanDevice_Info->{data}->{vars}->{dev}->{ipv4}->{current}->{ip}))[3];
               push @webCmdArray, "apply"              => "true";
            }

            FRITZBOX_Log $hash, 5, "DEBUG: get $name $cmd " . join(" ", @webCmdArray);

            $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

            my $tmp = FRITZBOX_ERR_Result($hash, $result, 1);

            if( substr($tmp, 0, 6) eq "ERROR:") {
               FRITZBOX_Log $hash, 2, "ERROR: result $name $cmd " . $tmp;
               FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "chgProfileStat", $val[0] . "->ERROR: changing profile";
            } else {
               FRITZBOX_Log $hash, 4, "INFO: result $name $cmd " . $tmp;
               FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "chgProfileStat", $val[0] . "->INFO: profile ". $val[1];
            }

         } else {
            FRITZBOX_Log $hash, 2, "ERROR: " . $val[0] . " not available/defined.";
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "chgProfileStat", $val[0] . "->ERROR: not available/defined";
         }
      }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr,"");

} # End FRITZBOX_Run_chgProfile

#######################################################################
sub FRITZBOX_Run_enableVPNshare($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();

   # xhr: 1
   # connection0: off
   # active_connection0: 0
   # apply:
   # lang: de
   # page: shareVpn

   my $queryStr = "&vpn_info=vpn:settings/connection/list(remote_ip,activated,name,state,access_type)";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "ERROR: evaluating $val[0] -> general error: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->ERROR: " . $result->{Error};
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "ERROR: evaluating vpn$val[0] -> AuthorizationRequired";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->ERROR: AuthorizationRequired";
   } else {

     my $vpnok = 0;
     my $vpnShare = substr($val[0],3);

     foreach ( @{ $result->{vpn_info} } ) {
       $_->{_node} =~ m/(\d+)/;
       if ( $1 == $vpnShare) {
         $vpnok = 1;
         last;
       }
     }

     if ($vpnok == 0){
       FRITZBOX_Log $hash, 2, "ERROR: vo valid " . $val[0] . " found";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->ERROR: not found";
     } else {
       FRITZBOX_Log $hash, 4, "INFO: set $name $cmd " . join(" ", @val);

       my $state = $val[1] eq "on"?"1":"0";

       #xhr 1 connection0 on active_connection0 1 apply nop lang de page shareVpn

       push @webCmdArray, "xhr"                         => "1";
       push @webCmdArray, "lang"                        => "de";
       push @webCmdArray, "page"                        => "shareVpn";
       push @webCmdArray, "apply"                       => "";
       push @webCmdArray, "connection".$vpnShare        => $val[1];
       push @webCmdArray, "active_connection".$vpnShare => $state;

       FRITZBOX_Log $hash, 5, "DEBUG: data.lua: \n" . join(" ", @webCmdArray);

       $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

       if(defined $result->{Error}) {
         FRITZBOX_Log $hash, 2, "ERROR: enable $val[0] share: " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->ERROR: " . $result->{Error};
       } else {

         $queryStr = "&vpn_info=vpn:settings/connection$vpnShare/activated";
         my $vpnState = FRITZBOX_Web_Query( $hash, $queryStr) ;

         FRITZBOX_Log $hash, 5, "DEBUG: $vpnState->{vpn_info} \n" . Dumper $vpnState;

         if(defined $vpnState->{Error}) {
            FRITZBOX_Log $hash, 2, "ERROR: enable $val[0] share: " . $vpnState->{Error};
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->ERROR: " . $vpnState->{Error};
         } elsif ($vpnState->{vpn_info} != $state) {
            FRITZBOX_Log $hash, 2, "ERROR: VPNshare " . $val[0] . " not set to " . $val[1] . " <> " . $vpnState->{vpn_info};
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->ERROR: " . $vpnState->{vpn_info};
         } else {
            FRITZBOX_Log $hash, 4, "INFO: VPNshare " . $val[0] . " set to " . $val[1];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "enableVPNshareStat", $val[0] . "->" . $val[1];
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $val[0] . "_activated", $vpnState->{vpn_info};
         }
       }
     }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr,"");

} # End FRITZBOX_Run_enableVPNshare

#######################################################################
sub FRITZBOX_Run_lockLandevice($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my @webCmdArray;
   my @roReadings;
   my $startTime = time();

   # xhr 1
   # kisi_profile filtprof1
   # back_to_page netDev
   # dev landevice7731
   # block_dev nop
   # lang de
   # page edit_device2

   my $returnStr;

   push @webCmdArray, "xhr" => "1";
   if ($val[1] eq "on") {
     push @webCmdArray, "kisi_profile" => "filtprof1";
   }

   push @webCmdArray, "dev"       => $val[0];
   push @webCmdArray, "lang"      => "de";

   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

   my $FW1 = substr($fwV[1],0,2);
   my $FW2 = substr($fwV[2],0,2);
   my $dev_name = $hash->{fhem}->{landevice}->{$val[0]};

   FRITZBOX_Log $hash, 4, "INFO: set $name $cmd f�r Version: $FW1.$FW2 ";

   if ($FW1 <= 7 && $FW2 < 21) {
     push @webCmdArray, "page"      => "edit_device2";
     push @webCmdArray, "block_dev" => "";
   } elsif ($FW1 >= 7 && $FW2 < 50) {
     push @webCmdArray, "page"      => "edit_device";
     push @webCmdArray, "block_dev" => "";
   } else {
     if($val[1] eq "on") {
       push @webCmdArray, "internetdetail" => "blocked";
     } else {
       push @webCmdArray, "internetdetail" => "unlimited";
     }
     push @webCmdArray, "page"      => "edit_device";
     push @webCmdArray, "apply"     => "true";
     push @webCmdArray, "dev_name"  => "$dev_name";
   }

   FRITZBOX_Log $hash, 4, "INFO: set $name $cmd " . join(" ", @webCmdArray);

   FRITZBOX_Log $hash, 5, "DEBUG: get $name $cmd " . join(" ", @webCmdArray);

   my $lock_res = FRITZBOX_Lan_Device_Info( $hash, $val[0], "lockLandevice");

   unless (($lock_res =~ /blocked/ && $val[1] eq "on") || ($lock_res =~ /unlimited/ && $val[1] eq "off")) {

     my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray);

     if ( defined $result->{Error} ) {
       FRITZBOX_Log $hash, 2, "ERROR: lockLandevice status: " . $result->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "lockLandevStat", $val[0] . "->ERROR: " . $result->{Error};
     } else {

       $lock_res = FRITZBOX_Lan_Device_Info( $hash, $val[0], "lockLandevice");

       if ($lock_res =~ /ERROR/) {
          FRITZBOX_Log $hash, 2, "ERROR: setting locklandevice: " . substr($lock_res, 7);
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "lockLandevStat", $val[0] . "->ERROR:" . substr($lock_res, 7);
       } else {

         unless (($lock_res =~ /blocked/ && $val[1] eq "on") || ($lock_res =~ /unlimited/ && $val[1] eq "off")) {
           FRITZBOX_Log $hash, 2, "ERROR: setting locklandevice: " . $val[0];
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "lockLandevStat", $val[0] . "->ERROR: setting locklandevice " . $val[1];
         } else {
           FRITZBOX_Log $hash, 4, "INFO: " . $lock_res . " -> $name $cmd $val[1]";
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "lockLandevStat", $val[0] . "->" . $val[1];
         }
       }
     }
   } else {
     FRITZBOX_Log $hash, 4, "INFO: " . $lock_res . " -> $name $cmd $val[1]";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "lockLandevStat", $val[0] . "->" . $val[1];
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr,"");

} # End FRITZBOX_Run_lockLandevice

#######################################################################
sub FRITZBOX_Run_Call_Web($)
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   FRITZBOX_Log $hash, 3, "DEBUG: set $name " . join(" ", @val);

   unless (int @val) {
     FRITZBOX_Log $hash, 3, "DEBUG: At least one parameter must be defined.";
     return "$name|0|Error: At least one parameter must be defined."
   }

   my $result;
   my @tr064CallArray;
   my $duration = 60;
   my $extNo = $val[0];

 # Check if 1st parameter is a valid number

   unless ($extNo =~ /^[\d\*\#+,]+$/) {
     FRITZBOX_Log $hash, 3, "DEBUG: Parameter '$extNo' not a valid phone number.";
     return $name."|0|Error: Parameter '$extNo' not a valid phone number"
   }

   $extNo =~ s/#$//;

 # Check if 2nd parameter is the duration

   shift @val;
   if (int @val) {
      if ($val[0] =~ /^\d+$/ && int $val[0] > 0) {
         $duration = $val[0];
         FRITZBOX_Log $hash, 3, "DEBUG: Extracted call duration of $duration s.";
         shift @val;
      }
   }

#Preparing command array to ring // X_VoIP:1 x_voip X_AVM-DE_DialNumber NewX_AVM-DE_PhoneNumber 01622846962#
   FRITZBOX_Log $hash, 3, "INFO: Call $extNo for $duration seconds - " . $hash->{SECPORT};
   if ($hash->{SECPORT}) {
      push @tr064CallArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", $extNo."#"];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CallArray);
      FRITZBOX_Log $hash, 3, "DEBUG: result of calling number $extNo -> " .  $result;
   }
   else {
      FRITZBOX_Log $hash, 3, "INFO: Your Fritz!OS version has limited interfaces. You cannot use call.";
   }

   FRITZBOX_Log $hash, 3, "DEBUG: waiting";
   sleep $duration; #+1; # 1s added because it takes sometime until it starts ringing
   FRITZBOX_Log $hash, 3, "DEBUG: stop ringing ";

#Preparing command array to stop ringing and reset dial port // X_VoIP:1 x_voip X_AVM-DE_DialHangup
   if ($hash->{SECPORT}) { #or hangup with TR-064
      push @tr064CallArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialHangup"];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CallArray);
      FRITZBOX_Log $hash, 3, "DEBUG: result of stop ringing number $extNo -> ".  $result;
   }

   return $name."|1|Calling done";

} # End FRITZBOX_Run_Call_Web

#######################################################################
sub FRITZBOX_Run_GuestWlan_Web($)
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

# Set guestWLAN, if necessary set also WLAN
   if ( $hash->{SECPORT} ) { #TR-064
      if ($state == 1) { # WLAN on when Guest WLAN on
         push @tr064CmdArray, ["WLANConfiguration:2", "wlanconfig2", "SetEnable", "NewEnable", "1"]
                  if $hash->{fhem}->{is_double_wlan} == 1;
         push @tr064CmdArray, ["WLANConfiguration:1", "wlanconfig1", "SetEnable", "NewEnable", "1"];
      }
      my $gWlanNo = 2;
      $gWlanNo = 3 if $hash->{fhem}->{is_double_wlan} == 1;
      push @tr064CmdArray, ["WLANConfiguration:".$gWlanNo, "wlanconfig".$gWlanNo, "SetEnable", "NewEnable", $state];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }
   else { #no API
      FRITZBOX_Log $hash, 2, "ERROR: No API available to switch WLAN.";
   }

# Read WLAN-Status
   my $queryStr = "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
   $queryStr .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
   $queryStr .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # G�ste WLAN
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
   $queryStr .= "&box_macFilter_active=wlan:settings/is_macfilter_active";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   my @reading_list = split(/\,/, AttrVal($name, "disableBoxReadings", "none"));

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $result->{box_macFilter_active}, "onoff";

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_Run_GuestWlan_Shell

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
   if ($hash->{SECPORT}) { #TR-064
      push @tr064CmdArray, ["WLANConfiguration:2", "wlanconfig2", "SetEnable", "NewEnable", $state]
               if $hash->{fhem}->{is_double_wlan} == 1 && $cmd ne "wlan2.4";
      push @tr064CmdArray, ["WLANConfiguration:1", "wlanconfig1", "SetEnable", "NewEnable", $state]
               if $cmd =~ /^(wlan|wlan2\.4)$/;
      FRITZBOX_Log $hash, 3, "INFO: TR-064 Command";
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }
   else { #no API
      FRITZBOX_Log $hash, 2, "ERROR: No API available to switch WLAN.";
   }

# Read WLAN-Status
   my $queryStr = "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
   $queryStr .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
   $queryStr .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # G�ste WLAN
   $queryStr .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
   $queryStr .= "&box_macFilter_active=wlan:settings/is_macfilter_active";

   $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   my @reading_list = split(/\,/, AttrVal($name, "disableBoxReadings", "none"));

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $result->{box_macFilter_active}, "onoff";

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_Wlan_Run_Web

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
   my @tr064CmdArray;
   my @roReadings;
   my $duration = -1;
   my $intNo = $val[0];
   my @FritzFons;
   my $ringTone;
   my %field;
   my $lastField;
   my $ttsLink;
   my $startValue;
   my $startTime = time();

 # Check if 1st parameter are comma separated numbers
   return $name."|0|Error (set ring): Parameter '$intNo' not a number (only commas (,) are allowed to separate phone numbers)"
      unless $intNo =~ /^[\d,]+$/;
   $intNo =~ s/#$//;

# Create a hash for the DECT devices whose ring tone (or radio station) can be changed
   foreach ( split( /,/, $intNo ) ) {
      if (defined $hash->{fhem}{$_}{brand} && "AVM" eq $hash->{fhem}{$_}{brand}) {
         my $userId = $hash->{fhem}{$_}{userId};
         FRITZBOX_Log $hash, 5, "DEBUG: Internal number $_ (dect$userId) seems to be a Fritz!Fon.";
         push @FritzFons, $hash->{fhem}{$_}{userId};
      }
   }

 # Check if 2nd parameter is the duration
   shift @val;
   if (int @val) {
      if ($val[0] =~ /^\d+$/ && int $val[0] >= 0) {
         $duration = $val[0];
         FRITZBOX_Log $hash, 5, "DEBUG: Extracted ring duration of $duration s.";
         shift @val;
      }
   }

# Check ClickToDial
   unless ($startValue->{useClickToDial}) {
      if ($hash->{SECPORT}) { # oder mit TR064
         # get port name
         push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_GetPhonePort", "NewIndex", "1"];
         @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         return $name."|0|Error (set ring): ".$tr064Result[0]->{Error}     if $tr064Result[0]->{Error};

         my $portName = $tr064Result[0]->{'X_AVM-DE_GetPhonePortResponse'}->{'NewX_AVM-DE_PhoneName'};
         # set click to dial
         if ($portName) {
            push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialSetConfig", "NewX_AVM-DE_PhoneName", $portName];
            @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
            FRITZBOX_Log $hash, 3, "INFO: Switch ClickToDial on, set dial port '$portName'";
         }
      }
      else { #oder Pech gehabt
         my $msg = "ERROR (set ring): Cannot ring because ClickToDial (Waehlhilfe) is off.";
           FRITZBOX_Log $hash, 2, $msg;
         return $name."|0|".$msg
      }
   }

   if (int (@FritzFons) == 0 && $ttsLink) {
      FRITZBOX_Log $hash, 3, "INFO: No Fritz!Fon identified, parameter 'say:' will be ignored.";
   }

   $intNo =~ s/,/#/g;

#Preparing 3rd command array to ring
   FRITZBOX_Log $hash, 4, "INFO: Ringing $intNo for $duration seconds";
   if ($hash->{SECPORT}) {
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", "**".$intNo."#"];
      @tr064Result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
      return $name."|0|Error (set ring): ".$tr064Result[0]->{Error} if $tr064Result[0]->{Error};
   }
   else {
      FRITZBOX_Log $hash, 3, "INFO: Your Fritz!OS version has limited interfaces. You cannot ring.";
   }

   sleep  5          if $duration <= 0; # always wait before reseting everything
   sleep $duration   if $duration > 0 ; #+1; # 1s added because it takes some time until it starts ringing

#Preparing 4th command array to stop ringing (but not when duration is 0 or play: and say: is used without duration)
   unless ( $duration == 0 || $duration == -1 && $ttsLink ) {
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialHangup"];
      $result = FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray ) if $hash->{SECPORT};
   }

   if ( $result->[0] == 1 ) {
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->[1];
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   }
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "DEBUG: Handover to main process: ".$returnStr;
   return $name."|2|".encode_base64($returnStr,"");

   # return $name."|1|Ringing done";
} # End FRITZBOX_Ring_Run_Web

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

   return undef;
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

   return undef;
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

   return undef;

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

   return undef
;
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
      $field{body} =~ s/�|Ä/\\304/g;
      $field{body} =~ s/�|Ö/\\326/g;
      $field{body} =~ s/�|Ü/\\334/g;
      $field{body} =~ s/�|ß/\\337/g;
      $field{body} =~ s/�|ä/\\344/g;
      $field{body} =~ s/�|ö/\\366/g;
      $field{body} =~ s/�|ü/\\374/g;

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

   FRITZBOX_Log $hash, 5, "DEBUG: Call $intNo";

   if ($hash->{SECPORT}) { #ring with TR-064
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", "**".$intNo."#"];
      FRITZBOX_TR064_Cmd( $hash, 0, \@tr064CmdArray );
   }

   return undef;
} # END sub FRITZBOX_StartRadio_Web

# Execute a Command via TR-064
#################################################
sub FRITZBOX_TR064_Cmd($$$)
{
   my ($hash, $xml, $cmdArray) = @_;

   my $name = $hash->{NAME};
   my $port = $hash->{SECPORT};

   unless ($port) {
      FRITZBOX_Log $hash, 2, "ERROR: TR064 not used. No security port defined.";
      return undef;
   }

# Set Password und User for TR064 access
   $FRITZBOX_TR064pwd = FRITZBOX_readPassword($hash)     unless defined $FRITZBOX_TR064pwd;
   $FRITZBOX_TR064user = AttrVal( $name, "boxUser", "dslf-config" );

   my $host = $hash->{HOST};

   FRITZBOX_Log $hash, 5, "DEBUG: Credentials: " . $host . " / " . $FRITZBOX_TR064user . " / " . $FRITZBOX_TR064pwd;

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

      FRITZBOX_Log $hash, 5, "DEBUG: Perform TR-064 call - " . $logMsg;

      my $soap = SOAP::Lite
         -> on_fault ( sub {} )
         -> uri( "urn:dslforum-org:service:".$service )
         -> proxy('https://'.$host.":".$port."/upnp/control/".$control, ssl_opts => [ SSL_verify_mode => 0 ], timeout => 10  )
         -> readable(1);
      my $res = $soap -> call( $action => @soapParams );

      unless( $res ) { # Transport-Error
         FRITZBOX_Log $hash, 5, "DEBUG: TR064-Transport-Error: ".$soap->transport->status;
         my %errorMsg = ( "Error" => $soap->transport->status );
         push @retArray, \%errorMsg;
         $FRITZBOX_TR064pwd = undef;
      }
      elsif( $res->fault ) { # SOAP Error - will be defined if Fault element is in the message
         # my $fcode   =  $s->faultcode;   #
         # my $fstring =  $s->faultstring; # also available
         # my $factor  =  $s->faultactor;

         my $ecode =  $res->faultdetail->{'UPnPError'}->{'errorCode'};
         my $edesc =  $res->faultdetail->{'UPnPError'}->{'errorDescription'};

         FRITZBOX_Log $hash, 5, "DEBUG: TR064 error $ecode:$edesc ($logMsg)";

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
      my $msg = "ERROR: Perl modul " . $missingModulWeb . "is missing on this system. Please install before using this modul.";
      FRITZBOX_Log $hash, 2, $msg;
      return $msg;
   }

   my $host = $hash->{HOST};
   my $url = 'http://'.$host.":49000/tr64desc.xml";

   my $returnStr = "_" x 130 ."\n\n";
   $returnStr .= " List of TR-064 services and actions that are provided by the device '$host'\n";

   return "TR-064 switched off."     if $hash->{READINGS}{box_tr064}{VAL} eq "off";

   FRITZBOX_Log $hash, 5, "DEBUG: Getting service page $url";
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

         FRITZBOX_Log $hash, 5, "DEBUG: Getting action page $url";
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

   if ($missingModulTR064) {
      FRITZBOX_Log $hash, 2,  "ERROR: Cannot use TR-064. Perl modul " . $missingModulTR064 . " is missing on this system. Please install.";
      return undef;
   }

# Security Port anfordern
      FRITZBOX_Log $hash, 4, "INFO: Open TR-064 connection and ask for security port";
   my $s = SOAP::Lite
      -> uri('urn:dslforum-org:service:DeviceInfo:1')
      -> proxy('http://' . $host . ':49000/upnp/control/deviceinfo', timeout => 10 )
      -> getSecurityPort();

   FRITZBOX_Log $hash, 4, "INFO: SecPort-String " . Dumper($s);

   my $port = $s->result;
   FRITZBOX_Log $hash, 4, "INFO: SecPort-Result " . Dumper($s->result);

   unless( $port ) {
      FRITZBOX_Log $hash, 2, "ERROR: Could not get secure port: $!";
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

   if ($missingModulWeb) {
      FRITZBOX_Log $hash, 2, "ERROR: Perl modul ".$missingModulWeb."is missing on this system. Please install before using this modul.";
      return undef;
   }

# Use old sid if last access later than 9.5 minutes
   my $sid = $hash->{fhem}{sid};

   if (defined $sid && $hash->{fhem}{sidTime} > time() - 9.5 * 60) {
      FRITZBOX_Log $hash, 4, "INFO: using old SID from " . $hash->{fhem}{sidTime};
      return $sid
   }

   my $host = $hash->{HOST};

   my $pwd = FRITZBOX_readPassword($hash);

   unless (defined $pwd) {
      FRITZBOX_Log $hash, 2, "ERROR: No password set. Please define it (once) with 'set $name password YourPassword'";
      return undef;
   }
   my $user = AttrVal( $name, "boxUser", "" );

   FRITZBOX_Log $hash, 4, "INFO: Open Web connection to $host : $user";
   FRITZBOX_Log $hash, 4, "INFO: getting new SID";
   $sid = (FB_doCheckPW($host, $user, $pwd));

   if ($sid) {
      FRITZBOX_Log $hash, 4, "INFO: Web session opened with sid $sid";
      return $sid;
   }

   FRITZBOX_Log $hash, 2, "ERROR: Web connection could not be established. Please check your credentials (password, user).";
   return undef;

 }


sub FRITZBOX_Web_CmdGet($$)
{
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
      my ($page, $getCmdStr) = @{$_};
      my $url =  'http://' . $host . "/" . $page . "?sid=" . $sid.$getCmdStr;
      FRITZBOX_Log $hash, 4, "INFO: Execute HTTP-Get '$url'";
      my $response = $agent->get( $url );

      if ($response->is_error) {
         FRITZBOX_Log $hash, 2, "ERROR: ".$response->status_line;
         my @retArray = (0, "Error: ".$response->status_line);
         return \@retArray;
      }
      else {
         FRITZBOX_Log $hash, 5, "DEBUG: Response: ".$response->content();
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
   my ($hash, $queryStr, $charSet, $f_lua) = @_;
   $charSet      = "" unless defined $charSet;
   $f_lua        = "luaQuery" unless defined $f_lua;

   my $name      = $hash->{NAME};

   my $sid = FRITZBOX_Web_OpenCon( $hash );
   unless ($sid) {
      FRITZBOX_Log $hash, 2, "ERROR: Didn't get a session ID. ResetSID";
      my %retHash = ( "Error" => "Didn't get a session ID", "ResetSID" => "1" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 5, "DEBUG: Request data via API " . $f_lua;
   my $host = $hash->{HOST};
   my $url = 'http://' . $host;

   if ( $f_lua eq "luaQuery") {
     $url .= '/query.lua?sid=' . $sid . $queryStr;
   } elsif ( $f_lua eq "luaCall") {
     $url .= '/' . $queryStr;
     $url .= '?sid=' . $sid if $queryStr ne "login_sid.lua";
   } else {
     FRITZBOX_Log $hash, 2, "ERROR: Wrong function name. function_name: " . $f_lua;
     my %retHash = ( "Error" => "Wrong function name", "function_name" => $f_lua ) ;
     return \%retHash;
   }

   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 180);
   my $response;

   FRITZBOX_Log $hash, 5, "get -> URL: $url";

   $response = $agent->get ( $url );

   FRITZBOX_Log $hash, 5, "DEBUG: Response: " . $response->status_line . "\n" . $response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 2, "ERROR: " . $response->status_line;
      return \%retHash;
   }

#################
     FRITZBOX_Log $hash, 5, "DEBUG: Response: " . $response->content;
#################

   my $jsonResult ;

   if ( $f_lua ne "luaCall") {

     return FRITZBOX_Process_JSON($hash, $response->content, $sid, $charSet);

   } else {
     $jsonResult->{sid} = $sid;
     $jsonResult->{result}  = $response->status_line  if defined $response->status_line;
     $jsonResult->{result} .= ", " . $response->content  if defined $response->content;
   }

   return $jsonResult;
}

# Read box values via the web connection
############################################
sub FRITZBOX_Lua_Data($$@)
{
   my ($hash, $queryStr, $charSet) = @_;
   $charSet = "" unless defined $charSet;

   my $name = $hash->{NAME};
   my $LogInfo = 4;

   if ($hash->{LUADATA} <= 0) {
      my %retHash = ( "Error" => "data.lua not supportet", "Info" => "Fritz!Box or Fritz!OS outdated" ) ;
      FRITZBOX_Log $hash, 2, "ERROR: data.lua not supportet. Fritz!Box or Fritz!OS outdated.";
      return \%retHash;
   }

   my $sid = FRITZBOX_Web_OpenCon( $hash );
   unless ($sid) {
      my %retHash = ( "Error" => "Didn't get a session ID", "ResetSID" => "1" ) ;
      FRITZBOX_Log $hash, 2, "ERROR: Didn't get a session ID";
      return \%retHash;
   }

   FRITZBOX_Log $hash, $LogInfo, "INFO: Request data via API dataQuery.";
   my $host = $hash->{HOST};
   my $url = 'http://' . $host . '/data.lua?sid=' . $sid;

   FRITZBOX_Log $hash, $LogInfo, "INFO: URL: $url";

   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 180);
   my $response = $agent->post ( $url, $queryStr );

   FRITZBOX_Log $hash, $LogInfo, "INFO: Response: " . $response->status_line . "\n" . $response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 2, "ERROR: ".$response->status_line;
      return \%retHash;
   }

   my $data = $response->content;

   # handling for getting profile Informations
   my $pattern_tr = '\<tr\>\<td(.*?)\<\/td\>\<\/tr\>';

   my $pattern_vl = 'class="name".title="(.*?)".datalabel=.*?\<button.type="submit".name="edit".value="(.*?)".class="icon.edit".title="';

   if ( $data =~ m/\<table id="uiProfileList"(.*?)\<\/table\>/is ) {
     my $profile_content;
     $profile_content = '{"pid":"kidProfile","data":{"kidProfiles":{';

     FRITZBOX_Log $hash, $LogInfo, "INFO: Response 1: " . $1;

     my $count = 0;

     foreach my $line ($data =~ m/$pattern_tr/gs) {
       FRITZBOX_Log $hash, $LogInfo, "INFO: Response 2: " . $line;

       if ($line =~ m/$pattern_vl/gs) {
         FRITZBOX_Log $hash, $LogInfo, "INFO: Profile name: " . $1 . "Profile Id: " . $2;
         $profile_content .= '"profile' . $count . '":{"Id":"' .$2 . '","Name":"' . $1 . '"},';
       }
       $count ++;

     }

     $profile_content = substr($profile_content, 0, length($profile_content)-1);

     $profile_content .= '}},"sid":"' . $sid . '"}';
#################
     FRITZBOX_Log $hash, $LogInfo, "INFO: Response 1: " . $profile_content;
#################

     return FRITZBOX_Process_JSON($hash, $profile_content, $sid, $charSet);
   }

#################
   FRITZBOX_Log $hash, $LogInfo, "INFO: Response: " . $response->content;
#################

   return FRITZBOX_Process_JSON($hash, $response->content, $sid, $charSet);

}

# Process JSON from lua response
############################################
sub FRITZBOX_Process_JSON($$$@) {

   my ($hash, $jsonText, $sid, $charSet) = @_;
   $charSet = "" unless defined $charSet;
   my $name = $hash->{NAME};

   if ($jsonText =~ /<html|"pid": "logout"|<head>/) {
      FRITZBOX_Log $hash, 5, "DEBUG: Old SID not valid anymore. ResetSID";
      my %retHash = ("Error" => "Old SID not valid anymore.", "ResetSID" => "1");
      return \%retHash;
   }

   # Remove illegal escape sequences
   $jsonText =~ s/\\'/'/g; #Hochkomma
   $jsonText =~ s/\\x\{[0-9a-f]\}//g; #delete control codes (as hex numbers)

   FRITZBOX_Log $hash, 5, "DEBUG: Decode JSON string.";

   my $jsonResult ;
   if ($charSet eq "UTF-8") {
      $jsonResult = eval { JSON->new->utf8->decode( $jsonText ) };
      if ($@) {
        FRITZBOX_Log $hash, 2, "INFO: Decode JSON string: decode_json failed, invalid json. error:$@";
      }
   }
   else {
      $jsonResult = eval { JSON->new->latin1->decode( $jsonText ) };
      if ($@) {
        FRITZBOX_Log $hash, 2, "INFO: Decode JSON string: decode_json failed, invalid json. error:$@";
      }
   }

   # FRITZBOX_Log $hash, 5, "DEBUG: JSON: " . Dumper($jsonResult);

   #Not a HASH reference at ./FHEM/72_FRITZBOX.pm line 4662.
   # 2018.03.19 18:43:28 3: FRITZBOX: get Fritzbox luaQuery settings/sip
   if ( ref ($jsonResult) ne "HASH" ) {
      chop $jsonText;
      FRITZBOX_Log $hash, 2, "ERROR: no json string returned (" . $jsonText . ")";
      my %retHash = ("Error" => "no json string returned (" . $jsonText . ")", "ResetSID" => "1");
      return \%retHash;
   }

   $jsonResult->{sid} = $sid;
   $jsonResult->{Error} = $jsonResult->{error}  if defined $jsonResult->{error};

   return $jsonResult;
}

# create error response for lua return
############################################
sub FRITZBOX_ERR_Result($$;@) {

   my ($hash, $result, $retData) = @_;
   $retData = 0 unless defined $retData;
   my $name = $hash->{NAME};

   my $tmp;

   if (defined $result->{Error} ) {
     $tmp = "ERROR: " . $result->{Error};
   }
   elsif (ref ($result->{result}) eq "ARRAY" || ref ($result->{data}) eq "HASH" ){
     $tmp = Dumper ($result);
     # $tmp = "\n";
   }
   elsif (defined $result->{result} ) {
     $tmp = $result->{result};
     # $tmp = "\n";
   }
   elsif (defined $result->{pid} ) {
     $tmp = "$result->{pid}";
     if (ref ($result->{data}) eq "ARRAY" || ref ($result->{data}) eq "HASH" ) {
       $tmp .= "\n" . Dumper ($result) if $retData == 1;
     }
     elsif (defined $result->{data} ) {
       $tmp .= "\n" . $result->{data} if $retData == 1;
     }
   }
   elsif (defined $result->{sid} ) {
     $tmp = $result->{sid};
   }
   else {
     $tmp = "Unexpected result: " . Dumper ($result);
   }

   return $tmp;
}

# get list of User informations
############################################
sub FRITZBOX_User_Info_List($) {
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $queryStr = "&user_info=boxusers:settings/user/list(name,box_admin_rights,enabled,email,myfritz_boxuser_uid,homeauto_rights,dial_rights,nas_rights,vpn_access)";

   my $returnStr;

   my $result = FRITZBOX_Web_Query( $hash, $queryStr) ;

   if ( defined $result->{Error} ) {
     my $tmp = FRITZBOX_ERR_Result($hash, $result);
     FRITZBOX_Log $hash, 2, "ERROR: evaluating user info -> " . $tmp;
     $returnStr .= "Benutzer Informationen:\n";
     $returnStr .= "---------------------------\n";
     return $returnStr . $tmp;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "ERROR: evaluating user info -> AuthorizationRequired";
     $returnStr .= "Benutzer Informationen:\n";
     $returnStr .= "---------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   eval {
      FRITZBOX_Log $hash, 5, "DEBUG: evaluating user info: \n" . Dumper $result->{user_info};
   };

   my $views = $result->{user_info};

#  border(8),cellspacing(10),cellpadding(20)
   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="4">Benutzer Informationen</td><td colspan="5">Berechtigungen</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Aktiv</td><td>Name</td><td>Box-ID</td><td>E-Mail</td><td>Box</td><td>Home</td><td>Dial</td><td>NAS</td><td>VPN</td>\n";
   $returnStr .= "</tr>\n";

   eval {
     for (my $cnt = 0; $cnt < @$views; $cnt++) {
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . @$views[$cnt]->{enabled} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{name} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{myfritz_boxuser_uid} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{email} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{box_admin_rights} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{homeauto_rights} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{dial_rights} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{nas_rights} . "</td>";
       $returnStr .= "<td>" . @$views[$cnt]->{vpn_access} . "</td>";
       $returnStr .= "</tr>\n";
     }
   };

   $returnStr .= "</table>\n";

   return $returnStr;

}

# get list of Kid Profiles
############################################
sub FRITZBOX_Kid_Profiles_List($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page shareVpn xhrId all;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "kidPro";

   my $returnStr;

   my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

   if(defined $result->{Error}) {
     my $tmp = FRITZBOX_ERR_Result($hash, $result);
     $returnStr .= "Kid Profiles:\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $tmp;
   }

   my $views = $result->{data}->{kidProfiles};

#  border(8),cellspacing(10),cellpadding(20)
   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="3">Kid Profiles</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Name</td><td>Id</td><td>Profil</td>\n";
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>profile2</td>";
   $returnStr .= "<td>unbegrenzt</td>";
   $returnStr .= "<td>filtprof3</td>";
   $returnStr .= "</tr>\n";

   eval {
     foreach my $key (keys %$views) {
       FRITZBOX_Log $hash, 5, "DEBUG: Kid Profiles: ".$key;
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $key . "</td>";
       $returnStr .= "<td>" . $result->{data}->{kidProfiles}->{$key}{Name} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{kidProfiles}->{$key}{Id} . "</td>";
       $returnStr .= "</tr>\n";
     }
   };

   $returnStr .= "</table>\n";

   return $returnStr;
}

# get list of DOCSIS informations
############################################
sub FRITZBOX_DOCSIS_Informations($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # xhr 1 lang de page docInfo xhrId all no_sidrenew nop
   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "docInfo";
   push @webCmdArray, "xhrId"       => "all";
   push @webCmdArray, "no_sidrenew" => "";

   my $returnStr;

   my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;
   my $tmp;

   if(defined $result->{Error}) {
     $tmp = FRITZBOX_ERR_Result($hash, $result);
     $returnStr .= "DOCSIS: Informationen\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $tmp;
   }

   FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($result->{data});

   my $views;
   my $nbViews;

#  border(8),cellspacing(10),cellpadding(20)
   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="10">DOCSIS Informationen</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Kanal</td><td>KanalID</td><td>Multiplex</td><td>Typ</td><td>Powerlevel</td><td>Frequenz</td>";
   $returnStr .= "<td>Latenz</td><td>corrErrors</td><td>nonCorrErrors</td><td>MSE</td>\n";
   $returnStr .= "</tr>\n";

   $nbViews = 0;
   if (defined $result->{data}->{channelUs}->{docsis30}) {
     $views = $result->{data}->{channelUs}->{docsis30};
     $nbViews = scalar @$views;
   }

   if ($nbViews > 0) {
     $returnStr .= "<tr>\n";
     $returnStr .= '<td colspan="10">channelUs - docsis30</td>';
     $returnStr .= "</tr>\n";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{multiplex} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{frequency} . "</td>";
         $returnStr .= "</tr>\n";
       }
     };

     $returnStr .= "</tr>\n";
     $returnStr .= '<td colspan="10"> </td>';
     $returnStr .= "</tr>\n";
   }

   $nbViews = 0;
   if (defined $result->{data}->{channelUs}->{docsis31}) {
     $views = $result->{data}->{channelUs}->{docsis31};
     $nbViews = scalar @$views;
   }

   if ($nbViews > 0) {
     $returnStr .= "</tr>\n";
     $returnStr .= '<td colspan="10">channelUs - docsis31</td>';
     $returnStr .= "</tr>\n";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{multiplex} . "</td>" if $result->{data}->{channelUs}->{docsis31}->[$i]->{multiplex};
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{frequency} . "</td>";
         $returnStr .= "</tr>\n";
       }
     };

     $returnStr .= "</tr>\n";
     $returnStr .= '<td colspan="10"> </td>';
     $returnStr .= "</tr>\n";
   }

   $nbViews = 0;
   if (defined $result->{data}->{channelDs}->{docsis30}) {
     $views = $result->{data}->{channelDs}->{docsis30};
     $nbViews = scalar @$views;
   }

   if ($nbViews > 0) {
     $returnStr .= "</tr>\n";
     $returnStr .= '<td colspan="10">channelDs - docsis30</td>';
     $returnStr .= "</tr>\n";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{latency} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{frequency} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{corrErrors} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{nonCorrErrors} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis30}->[$i]->{mse} . "</td>";
         $returnStr .= "</tr>\n";
       }
     };

     $returnStr .= "</tr>\n";
     $returnStr .= '<td colspan="10"> </td>';
     $returnStr .= "</tr>\n";
   }

   $nbViews = 0;
   if (defined $result->{data}->{channelDs}->{docsis31}) {
     $views = $result->{data}->{channelDs}->{docsis31};
     $nbViews = scalar @$views;
   }

   if ($nbViews > 0) {
     $returnStr .= "</tr>\n";
     $returnStr .= '<td colspan="10">channelDs - docsis31</td>';
     $returnStr .= "</tr>\n";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{frequency} . "</td>";
         $returnStr .= "</tr>\n";
       }
     };
   }

   $returnStr .= "</table>\n";

   return $returnStr;
}

# get list of WLAN in environment
############################################
sub FRITZBOX_WLAN_Environment($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page chan xhrId environment requestCount 0 useajax 1;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "chan";
   push @webCmdArray, "xhrId"       => "environment";

   my $returnStr;

   my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;
   my $tmp;

   if(defined $result->{Error}) {
     $tmp = FRITZBOX_ERR_Result($hash, $result);
     $returnStr .= "WLAN: Netzwerke in der Umgebung\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $tmp;
   }

   FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($result->{data}->{scanlist});

   my $views = $result->{data}->{scanlist};
   my $nbViews = scalar @$views;

#  border(8),cellspacing(10),cellpadding(20)
   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="4">WLAN: Netzwerke in der Umgebung</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>MAC</td><td>SSID</td><td>Kanal</td><td>BandID</td>\n";
   $returnStr .= "</tr>\n";

   eval {
     for(my $i = 0; $i <= $nbViews - 1; $i++) {
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $result->{data}->{scanlist}->[$i]->{mac} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{scanlist}->[$i]->{ssid} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{scanlist}->[$i]->{channel} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{scanlist}->[$i]->{bandId} . "</td>";
       $returnStr .= "</tr>\n";
     }
   };

   $returnStr .= "</table>\n";

   return $returnStr;
}

# get list of VPN Shares
############################################
sub FRITZBOX_VPN_Shares_List($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page shareVpn xhrId all;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "shareVpn";
   push @webCmdArray, "xhrId"       => "all";

   my $returnStr;

   my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;
   my $tmp;

   if(defined $result->{Error}) {
     $returnStr .= "VPN Shares: Benutzer-Verbindungen\n";
     $returnStr .= "---------------------------------\n";
     $tmp = FRITZBOX_ERR_Result($hash, $result);
     return $returnStr . $tmp;
   }

   my $views;
   my $jID;
   if ($result->{data}->{vpnInfo}->{userConnections}) {
      $views = $result->{data}->{vpnInfo}->{userConnections};
      $jID = "vpnInfo";
   } elsif ($result->{data}->{init}->{userConnections}) {
      $views = $result->{data}->{init}->{userConnections};
      $jID = "init";
   }

#  border(8),cellspacing(10),cellpadding(20)
   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="7">VPN Shares: Benutzer-Verbindungen</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Verbindung</td><td>Typ</td><td>Aktiv</td><td>Verbunden</td><td>UID</td><td>Name</td><td>Remote-IP</td>\n";
   $returnStr .= "</tr>\n";

   FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($result->{data}->{init}->{boxConnections});

   eval {
     foreach my $key (keys %$views) {
       FRITZBOX_Log $hash, 4, "INFO: userConnections: ".$key;
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $key . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{type} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{active} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{connected} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{userId} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{name} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{address} . "</td>";
       #$returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{deletable} . "</td>";
       #$returnStr .= "<td>" . $result->{data}->{$jID}->{userConnections}->{$key}{virtualAddress} . "</td>";
       $returnStr .= "</tr>\n";
     }
   };
   $returnStr .= "</table>\n";

   if ($result->{data}->{vpnInfo}->{boxConnections}) {
      $views = $result->{data}->{vpnInfo}->{boxConnections};
      $jID = "vpnInfo";
   } elsif ($result->{data}->{init}->{boxConnections}) {
      $views = $result->{data}->{init}->{boxConnections};
      $jID = "init";
   }

   $returnStr .= "\n";
#  border(8),cellspacing(10),cellpadding(20)
   $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="7">VPN Shares: Box-Verbindungen</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Verbindung</td><td>Typ</td><td>Aktiv</td><td>Verbunden</td><td>Host</td><td>Name</td><td>Remote-IP</td>\n";
   $returnStr .= "</tr>\n";

   FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($result->{data}->{init}->{boxConnections});

   eval {
     foreach my $key (keys %$views) {
       FRITZBOX_Log $hash, 4, "INFO: boxConnections: ".$key;
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $key . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{type} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{active} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{connected} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{accessHostname} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{name} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{remoteIP} . "</td>";
       $returnStr .= "</tr>\n";
     }
   };

   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

   my $FW1 = substr($fwV[1],0,2);
   my $FW2 = substr($fwV[2],0,2);

   # Wirguard VPN only available with Fritz!OS 7.50 and greater
   return $returnStr . "</table>\n" if $FW1 <= 7 && $FW2 < 50;

   @webCmdArray = ();
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "shareWireguard";
   push @webCmdArray, "xhrId"       => "all";

   $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

   if(defined $result->{Error}) {
     $tmp = FRITZBOX_ERR_Result($hash, $result);
     $returnStr .= "</table>\n";
     return $returnStr . $tmp;
   }

   if ($result->{data}->{init}->{boxConnections}) {
     $views = $result->{data}->{init}->{boxConnections};
     $jID = "init";

     FRITZBOX_Log $hash, 5, "DEBUG: \n" . Dumper ($result->{data}->{init}->{boxConnections});

     eval {
       foreach my $key (keys %$views) {
         FRITZBOX_Log $hash, 4, "INFO: boxConnections: ".$key;
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $key . "</td>";
         $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{active} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{connected} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{accessHostname} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{name} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{$jID}->{boxConnections}->{$key}{remoteIp} . "</td>";
         $returnStr .= "</tr>\n";
       }
     };
   }
   $returnStr .= "</table>\n";

   return $returnStr;
}

# get list of lanDevices
############################################
sub FRITZBOX_Lan_Devices_List($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

   my $FW1 = substr($fwV[1],0,2);
   my $FW2 = substr($fwV[2],0,2);

   FRITZBOX_Log $hash, 4, "INFO: FRITZBOX_Lan_Device_List f�r Version: $FW1.$FW2 ";

   my @webCmdArray;
   # "xhr 1 lang de page netDev xhrId cleanup useajax 1 no_sidrenew nop;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "netDev";
   push @webCmdArray, "xhrId"       => "all";

   my $returnStr;

   my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

   if(defined $result->{Error}) {
     my $tmp = FRITZBOX_ERR_Result($hash, $result);
     $returnStr  = "LanDevices: Active\n";
     $returnStr .= "------------------\n";
     return $returnStr . $tmp;
   }

#  border(8),cellspacing(10),cellpadding(20)
   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="6">LanDevices: Active</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>MAC</td><td>IPv4</td><td>UID</td><td>NAME</td><td>STATUS</td><td>INFO</td>\n";
   $returnStr .= "</tr>\n";

   my $views;
   my $nbViews = 0;

   if (defined $result->{data}->{active}) {
     $views = $result->{data}->{active};
     $nbViews = scalar @$views;
   }

   if ($nbViews > 0) {

     for(my $i = 0; $i <= $nbViews - 1; $i++) {
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{mac} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{ipv4}->{ip} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{UID} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{name} . "</td>";
       # if( exists $result->{data}->{active}->[$i]->{state}->{class}) {
       if( ref($result->{data}->{active}->[$i]->{state}) eq "HASH") {
         $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{state}->{class} . "</td>";
       } else {
         $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{state} . "</td>";
       }
       $returnStr .= "<td>" . $result->{data}->{active}->[$i]->{properties}->[1]->{txt} . "</td>" if defined ($result->{data}->{active}->[$i]->{properties}->[1]->{txt});
       $returnStr .= "</tr>\n";
     }
   }
   $returnStr .= "</table>\n";

   $returnStr .= "\n";
#  border(8),cellspacing(10),cellpadding(20)
   $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="6">LanDevices: Passiv</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>MAC</td><td>IPv4</td><td>UID</td><td>NAME</td><td>STATUS</td><td>INFO</td>\n";
   $returnStr .= "</tr>\n";

   $nbViews = 0;

   if (defined $result->{data}->{passive}) {
     $views = $result->{data}->{passive};
     $nbViews = scalar @$views;
   }

   if ($nbViews > 0) {

     for(my $i = 0; $i <= $nbViews - 1; $i++) {
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $result->{data}->{passive}->[$i]->{mac} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{passive}->[$i]->{ipv4}->{ip} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{passive}->[$i]->{UID} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{passive}->[$i]->{name} . "</td>";
       if (ref($result->{data}->{passive}->[$i]->{state}) ne "ARRAY") {
         $returnStr .= "<td>" . $result->{data}->{passive}->[$i]->{state} . "</td>";
       } else {
         $returnStr .= "<td>---</td>";
       }
       $returnStr .= "<td>" . $result->{data}->{passive}->[$i]->{properties}->[1]->{txt} . "</td>" if defined ($result->{data}->{passive}->[$i]->{properties}->[1]->{txt});
       $returnStr .= "</tr>\n";
     }
   }

   $returnStr .= "</table>\n";

   return $returnStr;

}

# get info for a lanDevice
############################################
sub FRITZBOX_Lan_Device_Info($$$) {
   my ($hash, $lDevID, $action) = @_;
   my $name = $hash->{NAME};
   FRITZBOX_Log $hash, 4, "INFO: LanDevice to proof: " . $lDevID . " for: " . $action;

   my @webCmdArray;
   my $returnStr;

   #xhr 1
   #xhrId all
   #backToPage netDev
   #dev landevice7718 / landevice7731 Apollo
   #initalRefreshParamsSaved true
   #no_sidrenew nop
   #lang de
   #page edit_device2

   push @webCmdArray, "xhr" => "1";
   push @webCmdArray, "xhrId" => "all";
   push @webCmdArray, "backToPage" => "netDev";
   push @webCmdArray, "dev" => $lDevID;
   push @webCmdArray, "initalRefreshParamsSaved" => "true";
   push @webCmdArray, "lang" => "de";

   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));

   my $FW1 = substr($fwV[1],0,2);
   my $FW2 = substr($fwV[2],0,2);

   FRITZBOX_Log $hash, 4, "INFO: FRITZBOX_Lan_Device_Info f�r Version: $FW1.$FW2 ";

   if ($FW1 >= 7 && $FW2 >= 25) {
      push @webCmdArray, "page" => "edit_device";
   } else {
      push @webCmdArray, "page" => "edit_device2";
   }

   FRITZBOX_Log $hash, 4, "INFO: set $name $action " . join(" ", @webCmdArray);

   my $result = FRITZBOX_Lua_Data( $hash, \@webCmdArray) ;

   if(defined $result->{Error}) {
      FRITZBOX_Log $hash, 2, "ERROR: get $name $action \n" . FRITZBOX_ERR_Result($hash, $result);
      return "ERROR: holen Lan_Device_Info: " . $action . " f�r: " . $lDevID;
   }

   if (exists $result->{data}->{vars}) {
     FRITZBOX_Log $hash, 5, "DEBUG: landevice: " . $lDevID . "landevice: \n" . FRITZBOX_ERR_Result($hash, $result);

     if ($action eq "info") {
       if($result->{data}->{vars}->{dev}->{UID} eq $lDevID) {
          my $returnStr  = "";
          $returnStr .= "MAC:"       . $result->{data}->{vars}->{dev}->{mac};
          $returnStr .= " IPv4:"     . $result->{data}->{vars}->{dev}->{ipv4}->{current}->{ip};
          $returnStr .= " UID:"      . $result->{data}->{vars}->{dev}->{UID};
          $returnStr .= " NAME:"     . $result->{data}->{vars}->{dev}->{name}->{displayName};
          if ( ref ($result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}) eq 'HASH' ) {
             $returnStr .= " ACCESS:"   . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid} if defined($result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid});
          }
          $returnStr .= " DEVTYPE:"  . $result->{data}->{vars}->{dev}->{devType};
          $returnStr .= " STATE:"    . $result->{data}->{vars}->{dev}->{wlan}->{state} if defined($result->{data}->{vars}->{dev}->{wlan}->{state}) and $result->{data}->{vars}->{dev}->{devType} eq 'wlan';
          $returnStr .= " ONLINE:"   . $result->{data}->{vars}->{dev}->{state};
          $returnStr .= " REALTIME:" . $result->{data}->{vars}->{dev}->{realtime}->{state} if defined($result->{data}->{vars}->{dev}->{realtime}->{state});
          return $returnStr;
       } else {
          return "ERROR: no lanDeviceInfo: " . $lDevID;
       }
     } elsif ($action eq "chgProf") {
       if($result->{data}->{vars}->{dev}->{UID} eq $lDevID) {
         return $result;
       }
     } elsif ($action eq "lockLandevice") {
       unless (defined $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid}) {
         FRITZBOX_Log $hash, 2, "ERROR: no msgId returned";
         return "ERROR: no msgId returned";
       }

       my $jsonMsgId = $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid};

       FRITZBOX_Log $hash, 5, "DEBUG: MsgId: " . $jsonMsgId;
       return "INFO: " . $jsonMsgId;
     }
   } else {
     FRITZBOX_Log $hash, 2, "ERROR: landevice: " . $lDevID . "landevice: Fehler holen Lan_Device_Info";

     return "ERROR: Lan_Device_Info: " . $action . " f�r: " . $lDevID;
   }
}

# get info for restrinctions for kids
############################################
sub FRITZBOX_Lua_Kids($$@)
{
   my ($hash, $queryStr, $charSet) = @_;
   $charSet = "" unless defined $charSet;
   my $name = $hash->{NAME};

   my $sid = FRITZBOX_Web_OpenCon( $hash );
   unless ($sid) {
      FRITZBOX_Log $hash, 2, "ERROR: Didn't get a session ID. ResetSID.";
      my %retHash = ( "Error" => "Didn't get a session ID", "ResetSID" => "1" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 5, "DEBUG: Request data via API dataQuery.";
   my $host = $hash->{HOST};
   my $url = 'http://' . $host . '/internet/kids_userlist.lua?sid=' . $sid; # . '&' . $queryStr;

   FRITZBOX_Log $hash, 5, "DEBUG: URL: $url";

   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 180);
   my $response = $agent->post ( $url, $queryStr );

   FRITZBOX_Log $hash, 5, "DEBUG: Response: ".$response->status_line."\n".$response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 2, "ERROR: ".$response->status_line;
      return \%retHash;
   }

   my $jsonText = $response->content;

   if ($jsonText =~ /<html>|"pid": "logout"/) {
      FRITZBOX_Log $hash, 2, "ERROR: Old SID not valid anymore. ResetSID";
      my %retHash = ("Error" => "Old SID not valid anymore.", "ResetSID" => "1");
      return \%retHash;
   }


#################
   #FRITZBOX_Log $hash, 3, "INFO: Response: ".$response->content;
#################

   # Remove illegal escape sequences
   $jsonText =~ s/\\'/'/g; #Hochkomma
   $jsonText =~ s/\\x\{[0-9a-f]\}//g; #delete control codes (as hex numbers)

   FRITZBOX_Log $hash, 5, "DEBUG: Decode JSON string.";
   my $jsonResult ;
   if ($charSet eq "UTF-8") {
      $jsonResult = JSON->new->utf8->decode( $jsonText );
   }
   else {
      $jsonResult = JSON->new->latin1->decode( $jsonText );
   }
   #Not a HASH reference at ./FHEM/72_FRITZBOX.pm line 4662.
  # 2018.03.19 18:43:28 3: FRITZBOX: get Fritzbox luaQuery settings/sip
   if ( ref ($jsonResult) ne "HASH" ) {
      chop $jsonText;
      FRITZBOX_Log $hash, 5, "DEBUG: no json string returned (" . $jsonText . ")";
      my %retHash = ("Error" => "no json string returned (" . $jsonText . ")", "ResetSID" => "1");
      return \%retHash;
   }
   $jsonResult->{sid} = $sid;
   $jsonResult->{Error} = $jsonResult->{error}  if defined $jsonResult->{error};
   return $jsonResult;
}

#####################################
# checks and stores FritzBox password used for webinterface connection
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

   FRITZBOX_Log $hash, 4, "INFO: Read FritzBox password from file";
   ($err, $password) = getKeyValue($index);

   if ( defined($err) ) {
      FRITZBOX_Log $hash, 2, "ERROR: unable to read FritzBox password from file: $err";
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
      FRITZBOX_Log $hash, 2, "ERROR: No password in file";
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

} # End FRITZBOX_fritztris

#####################################

1;

=pod
=item device
=item summary Controls some features of AVM's FRITZ!BOX, FRITZ!Repeater and Fritz!Fon.
=item summary_DE Steuert einige Funktionen von AVM's FRITZ!BOX, Fritz!Repeater und Fritz!Fon.

=begin html

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
<div>
<ul>
   Controls some features of a FRITZ!BOX router or Fritz!Repeater. Connected Fritz!Fon's (MT-F, MT-D, C3, C4, C5) can be used as
   signaling devices. MP3 files and Text2Speech can be played as ring tone or when calling phones.
   <br>
   For detail instructions, look at and please maintain the <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki</b></a>.
   <br/><br/>
   The box is partly controlled via the official TR-064 interface but also via undocumented interfaces between web interface and firmware kernel.</br>
   <br>
   The modul was tested on FRITZ!BOX 7390 and 7490 with Fritz!OS 6.20 and higher.
   <br>
   Check also the other FRITZ!BOX moduls: <a href="#SYSMON">SYSMON</a> and <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>The modul uses the Perl modul 'JSON::XS', 'LWP', 'SOAP::Lite' for remote access.</i>
   <br/><br/>

   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX  [host]</code>
      <br/>
         The attribute <i>host</i> is the web address (name or IP) of the FRITZ!BOX. If it is missing, the modul switches in local mode or uses the default host address "fritz.box".
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
      <li><a name="call"></a>
         <dt><code>set &lt;name&gt; call &lt;number&gt; [duration]</code></dt>
         <br>
         Calls for 'duration' seconds (default 60) the given number from an internal port (default 1).
      </li><br>

      <li><a name="checkAPIs"></a>
         <dt><code>set &lt;name&gt; checkAPIs</code></dt>
         <br>
         Restarts the initial check of the programming interfaces of the FRITZ!BOX.
      </li><br>

      <li><a name="chgProfile"></a>
         <dt><code>set &lt;name&gt; chgProfile &lt;number&gt; &lt;filtprof<i>n</i>&gt;</code></dt>
         <br>
         &lt;number&gt; is the ID from landevice<i>n..n</i> or its MAC<br>
         Changes the profile filtprof with the given number 1..n of the landevice.<br>
         Execution is non-blocking. The feedback takes place in the reading: chgProfileStat <br>
         Needs FRITZ!OS 7.21 or higher
         <br>
      </li><br>

      <li><a name="dect"></a>
         <dt><code>set &lt;name&gt; dect &lt;on|off&gt;</code></dt>
         <br>
         Switches the DECT base of the box on or off.
         <br>
         Requires FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="diversity"></a>
         <dt><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         Switches the call diversity number (1, 2 ...) on or off.
         A call diversity for an incoming number has to be created with the FRITZ!BOX web interface. Requires TR064 (>=6.50).
         <br>
         Note! Only a diversity for a concret home number and <u>without</u> filter for the calling number can be set. Hence, an approbriate <i>diversity</i>-reading must exist.
      </li><br>

      <li><a name="guestWlan"></a>
         <dt><code>set &lt;name&gt; guestWlan &lt;on|off&gt;</code></dt>
         <br>
         Switches the guest WLAN on or off. The guest password must be set. If necessary, the normal WLAN is also switched on.
      </li><br>

      <li><a name="dectRingblock"></a>
         <dt><code>set &lt;name&gt; dectRingblock &lt;dect&lt;nn&gt;&gt; &lt;on|off&gt;</code></dt>
         <br>
         Activates / deactivates the Do Not Disturb for the DECT telephone with the ID dect<n>. The ID can be found in the reading list
         of the &lt;name&gt; device.<br><br>
         <code>set &lt;name&gt; dectRingblock &lt;dect&lt;nn&gt;&gt; &lt;days&gt; &lt;hh:mm-hh:mm&gt; [lmode:on|off] [emode:on|off]</code><br><br>
         Activates / deactivates the do not disturb for the DECT telephone with the ID dect<n> for periods:<br>
         &lt;hh:mm-hh:mm&gt; = Time from - time to<br>
         &lt;days&gt; = wd for weekdays, ed for every day, we for weekend<br>
         lmode:on|off = lmode defines the Do Not Disturb. If off, it is off except for the period specified.<br>
                                                    If on, the lock is on except for the specified period<br>
         emode:on|off = emode switches events on/off when Do Not Disturb is set. See the FRITZ!BOX documentation<br>
         Needs FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="macFilter"></a>
         <dt><code>set &lt;name&gt; macFilter &lt;on|off&gt;</code></dt>
         <br>
         Activates/deactivates the MAC Filter. Depends to "new WLAN Devices in the FRITZ!BOX.<br>
         Execution is non-blocking. The feedback takes place in the reading: macFilterStat <br>
         Needs FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="lockLandevice"></a>
         <dt><code>set &lt;name&gt; lockLandevice &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         &lt;number&gt; is the ID from landevice<i>n..n</i> or its MAC<br>
         Switches the landevice on or off.<br>
         Execution is non-blocking. The feedback takes place in the reading: lockLandeviceStat <br>
         Needs FRITZ!OS 7.21 or higher
      </li><br>

      <li><a name="enableVPNshare"></a>
         <dt><code>set &lt;name&gt; enableVPNshare &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         &lt;number&gt; results from the reading vpn<i>n..n</i>_user.. or _box<br>
         Switches the vpn share with the given number nn on or off.<br>
         Execution is non-blocking. The feedback takes place in the reading: enableVPNshareStat <br>
         Needs FRITZ!OS 7.21 or higher
      </li><br>

      <li><a name="switchIPv4DNS"></a>
         <dt><code>set &lt;name&gt; switchIPv4DNS &lt;provider|other&gt;</code></dt>
         <br>
         Switches the ipv4 dns to the internet provider or another dns (must be defined for the FRITZ!BOX).<br>
         Needs FRITZ!OS 7.21 or higher
      </li><br>

      <li><a name="password"></a>
         <dt><code>set &lt;name&gt; password &lt;password&gt;</code></dt>
         <br>
      </li><br>

      <li><a name="rescanWLANneighbors"></a>
         <dt><code>set &lt;name&gt; rescanWLANneighbors</code></dt>
         <br>
         Rescan of the WLAN neighborhood.
         Execution is non-blocking. The feedback takes place in the reading: rescanWLANneighbors <br>
      </li><br>

      <li><a name="ring"></a>
         <dt><code>set &lt;name&gt; ring &lt;intNumbers&gt; [duration] [show:Text]  [say:Text | play:MP3URL]</code></dt>
         <dt>Example:</dt>
         <dd>
         <code>set &lt;name&gt; ring 611,612 5 Budapest show:It is raining</code>
         <br>
         <code>set &lt;name&gt; ring 611 8 say:(en)It is raining</code>
         <br>
         <code>set &lt;name&gt; ring 610 10 play:http://raspberrypi/sound.mp3</code>
         </dd>
         Rings the internal numbers for "duration" seconds and (on Fritz!Fons) with the given "ring tone" name.
         Different internal numbers have to be separated by a comma (without spaces).
         <br>
         Default duration is 5 seconds. The FRITZ!BOX can create further delays. Default ring tone is the internal ring tone of the device.
         Ring tone will be ignored for collected calls (9 or 50).
         <br>
         If the call is taken the callee hears the "music on hold" which can also be used to transmit messages.
         <br/><br/>
         If the <a href=#FRITZBOXattr>attribute</a> 'ringWithIntern' is specified, the text behind 'show:' will be shown as the callers name.
         Maximal 30 characters are allowed.
         <br/><br/>
         On Fritz!Fons the parameter 'say:' can be used to let the phone speak a message (max. 100 characters) instead of using the ringtone.
         Alternatively, a MP3 link (from a web server) can be played with 'play:'. This creates the web radio station 'FHEM' and uses translate.google.com for text2speech. It will <u>always</u> play the complete text/sound. It will than ring with standard ring tone until the end of the 'ring duration' is reached.
         Say and play <u>may</u> work only with one single Fritz!Fon at a time.
         <br>
         The behaviour may vary depending on the Fritz!OS.
      </li><br>

      <li><a name="tam"></a>
         <dt><code>set &lt;name&gt; tam &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         Switches the answering machine number (1, 2 ...) on or off.
         The answering machine has to be created on the FRITZ!BOX web interface.
      </li><br>

      <li><a name="update"></a>
         <dt><code>set &lt;name&gt; update</code></dt>
         <br>
         Starts an update of the device readings.
      </li><br>

      <li><a name="wlan"></a>
         <dt><code>set &lt;name&gt; wlan &lt;on|off&gt;</code></dt>
         <br>
         Switches WLAN on or off.
      </li><br>

      <li><a name="wlan2.4"></a>
         <dt><code>set &lt;name&gt; wlan2.4 &lt;on|off&gt;</code></dt>
         <br>
         Switches WLAN 2.4 GHz on or off.
      </li><br>

      <li><a name="wlan5"></a>
         <dt><code>set &lt;name&gt; wlan5 &lt;on|off&gt;</code></dt>
         <br>
         Switches WLAN 5 GHz on or off.
      </li><br>
   </ul>

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <br>

      <li><a name="lanDeviceInfo"></a>
         <dt><code>get &lt;name&gt; lanDeviceInfo &lt;number&gt;</code></dt>
         <br>
         &lt;number&gt; is the ID from landevice<i>n..n</i> or its MAC<br>
         Shows informations about a specific lan device.<br>
         Needs FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="luaData"></a>
         <dt><code>get &lt;name&gt; luaData &lt;Command&gt;</code></dt>
         <br>
         Evaluates commands via data.lua codes.
      </li><br>

      <li><a name="luaFunction"></a>
         <dt><code>get &lt;name&gt; luaFunction &lt;Command&gt;</code></dt>
         <br>
         Evaluates commands via AVM lua functions.
      </li><br>

      <li><a name="luaInfo"></a>
         <dt><code>get &lt;name&gt; luaInfo &lt;landevices|vpnShares|kidProfiles|userInfos|wlanNeighborhood|docsisInformation&gt;</code></dt>
         <br>
         Needs FRITZ!OS 7.21 or higher.<br>
         lanDevices -> Shows a list of active and inactive lan devices.<br>
         vpnShares -> Shows a list of active and inactive vpn shares.<br>
         kidProfiles -> Shows a list of internet access profiles.<br>
         userInfos -> Shows a list of FRITZ!BOX users.<br>
         wlanNeighborhood -> Shows a list of WLAN neighborhood devices.<br>
         docsisInformation -> Shows DOCSIS informations (only Cable).<br>
      </li><br>

      <li><a name="luaQuery"></a>
         <dt><code>get &lt;name&gt; luaQuery &lt;Command&gt;</code></dt>
         <br>
         Shows informations via query.lua requests.
      </li><br>

      <li><a name="tr064Command"></a>
         <dt><code>get &lt;name&gt; tr064Command &lt;service&gt; &lt;control&gt; &lt;action&gt; [[argName1 argValue1] ...]</code></dt>
         <br>
         Executes TR-064 actions (see <a href="http://avm.de/service/schnittstellen/">API description</a> of AVM).
         <br>
         argValues with spaces have to be enclosed in quotation marks.
         <br>
         Example: <code>get &lt;name&gt; tr064Command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetInfo NewDectID 1</code>
         <br>
      </li><br>

      <li><a name="tr064ServiceList"></a>
         <dt><code>get &lt;name&gt; tr064ServiceListe</code></dt>
         <br>
         Shows a list of TR-064 services and actions that are allowed on the device.
      </li><br>

   </ul>

   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><a name="INTERVAL"></a>
         <dt><code>INTERVAL &lt;seconds&gt;</code></dt>
         <br>
         Polling-Interval. Default is 300 (seconds). Smallest possible value is 60.
      </li><br>

      <li><a name="allowShellCommand"></a>
         <dt><code>allowShellCommand &lt;0 | 1&gt;</code></dt>
         <br>
         Enables the get command "shellCommand"
      </li><br>

      <li><a name="boxUser"></a>
         <dt><code>boxUser &lt;user name&gt;</code></dt>
         <br>
         User name that is used for TR064 or other web based access. By default no user name is required to login.
         <br>
         If the FRITZ!BOX is configured differently, the user name has to be defined with this attribute.
      </li><br>

      <li><a name="deviceInfo"></a>
         <dt><code>deviceInfo &lt;ipv4, name, uid, connection, speed, rssi, _noDefInf_, _default_&, space, comma&gt;</code></dt>
         <br>
         This attribute can be used to design the content of the device readings (mac_...). If the attribute is not set, sets
         the content breaks down as follows:<br>
         <code>name,[uid],(connection: speed, rssi)</code><br><br>

         If the <code>_noDefInf_</code> parameter is set, the order in the list is irrelevant here, non-existent network connection values are shown
         as noConnectInfo (LAN or WLAN not available) and noSpeedInfo (speed not available).<br><br>
         You can add your own text or characters via the free input field and classify them between the fixed parameters.<br>
         There are the following special texts:<br>
         <code>space</code> => becomes a space.<br>
         <code>comma</code> => becomes a comma.<br>
         <code>_default_...</code> => replaces the default space as separator.<br>
         Examples:<br>
         <code>_default_commaspace</code> => becomes a comma followed by a space separator.<br>
         <code>_default_space:space</code> => becomes a space:space separator.<br>
         Not all possible "nonsensical" combinations are intercepted. So sometimes things can go wrong.
      </li><br>

      <li><a name="disableBoxReadings"></a>
         <dt><code>disableBoxReadings &lt;list&gt;</code></dt>
         <br>
         disable single box_ Readings.
      </li><br>

      <li><a name="disableDectInfo"></a>
         <dt><code>disableDectInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of phone information off/on.
      </li><br>

      <li><a name="disableFonInfo"></a>
         <dt><code>disableFonInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of dect information off/on.
      </li><br>

      <li><a name="disableTableFormat"></a>
         <dt><code>disableTableFormat&lt;border(8),cellspacing(10),cellpadding(20)&gt;</code></dt>
         <br>
         Disables table format parameters.
      </li><br>

      <li><a name="enableAlarmInfo"></a>
         <dt><code>enableAlarmInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of alarm information off/on.
      </li><br>

      <li><a name="enablePassivLanDevices"></a>
         <dt><code>enablePassivLanDevices &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of passive network devices as reading off / on.
      </li><br>

      <li><a name="enableSIP"></a>
         <dt><code>enableSIP &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of SIP's as reading off / on.
      </li><br>

      <li><a name="enableUserInfo"></a>
         <dt><code>enableUserInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of user information off/on.
      </li><br>

      <li><a name="enableVPNShares"></a>
         <dt><code>enableVPNShares &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of VPN shares as reading off / on.
      </li><br>

      <li><a name="enableWLANneighbors"></a>
         <dt><code>enableWLANneighbors &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of WLAN neighborhood devices as reading off / on.
      </li><br>

      <li><a name="wlanNeighborsPrefix"></a>
         <dt><code>wlanNeighborsPrefix &lt;prefix&gt;</code></dt>
         <br>
         Defines a new prefix for the reading name of the wlan neighborhood devices that is build from the mac address. Default prefix is nbh_.
      </li><br>

      <li><a name="fritzBoxIP"></a>
         <dt><code>fritzBoxIP &lt;IP Address&gt;</code></dt>
         <br>
         Depreciated.
      </li><br>

      <li><a name="m3uFileLocal"></a>
         <dt><code>m3uFileLocal &lt;/path/fileName&gt;</code></dt>
         <br>
         Can be used as a work around if the ring tone of a Fritz!Fon cannot be changed because of firmware restrictions (missing telnet or webcm).
         <br>
         How it works: If the FHEM server has also a web server running, the FritzFon can play a m3u file from this web server as an internet radio station.
         For this an internet radio station on the FritzFon must point to the server URL of this file and the internal ring tone must be changed to that station.
         <br>
         If the attribute is set, the server file "m3uFileLocal" (local address of the FritzFon URL) will be filled with the URL of the text2speech engine (say:) or a MP3-File (play:). The FritzFon will then play this URL.
      </li><br>

      <li><a name="m3uFileURL"></a>
         <dt><code>m3uFileURL &lt;URL&gt;</code></dt>
         <br>
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
      <li><b>box_cpuTemp</b> - Tempreture of the Fritx!Box CPU</li>
      <li><b>box_dect</b> - Current state of the DECT base: activ, inactiv</li>
      <li><b>box_dsl_downStream</b> - minimum effective data rate  (MBit/s)</li>
      <li><b>box_dsl_upStream</b> - minimum effective data rate  (MBit/s)</li>
      <li><b>box_fwVersion</b> - Firmware version of the box, if outdated then '(old)' is appended</li>
      <li><b>box_guestWlan</b> - Current state of the guest WLAN</li>
      <li><b>box_guestWlanCount</b> - Number of devices connected to guest WLAN</li>
      <li><b>box_guestWlanRemain</b> - Remaining time until the guest WLAN is switched off</li>
      <li><b>box_ipExtern</b> - Internet IPv4 of the FRITZ!BOX</li>
      <li><b>box_ipv6Extern</b> - Internet IPv6 of the FRITZ!BOX</li>
      <li><b>box_ipv6Prefix</b> - Internet IPv6 Prefix of the FRITZ!BOX for the LAN/WLAN</li>
      <li><b>box_macFilter_active</b> - Status of the WLAN MAC filter (restrict WLAN access to known WLAN devices)</li>
      <li><b>box_meshRole</b> - from version 07.21 the mesh role (master, slave) is displayed.</li>
      <li><b>box_model</b> - FRITZ!BOX model</li>
      <li><b>box_moh</b> - music-on-hold setting</li>
      <li><b>box_model</b> - FRITZ!BOX model</li>
      <li><b>box_connect</b> - connection state: Unconfigured, Connecting, Authenticating, Connected, PendingDisconnect, Disconnecting, Disconnected</li>
      <li><b>box_lat_connect_err</b> - last connection error</li>
      <li><b>box_uptime</b> - uptime since last reboot</li>
      <li><b>box_uptimeConnect</b> - connect uptime since last reconnect</li>
      <li><b>box_powerRate</b> - current power in percent of maximal power</li>
      <li><b>box_rateDown</b> - average download rate in the last update interval</li>
      <li><b>box_rateUp</b> - average upload rate in the last update interval</li>
      <li><b>box_stdDialPort</b> - standard caller port when using the dial function of the box</li>
      <li><b>box_tr064</b> - application interface TR-064 (needed by this modul)</li>
      <li><b>box_tr069</b> - provider remote access TR-069 (safety issue!)</li>
      <li><b>box_vdsl_downStreamRate</b> - Current date rate (MBit/s)</li>
      <li><b>box_vdsl_upStreamRate</b> - Current date rate (MBit/s)</li>
      <li><b>box_wlanCount</b> - Number of devices connected via WLAN</li>
      <li><b>box_wlan_2.4GHz</b> - Current state of the 2.4 GHz WLAN</li>
      <li><b>box_wlan_5GHz</b> - Current state of the 5 GHz WLAN</li>
      <li><b>box_wlan_lastScanTime</b> - last scan of the WLAN neighborhood. This readings is only available if the attribut enableWLANneighbors is set.</li>

      <br>
      <li><b>box_docsis30_Ds_powerLevels</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_latencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_frequencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_corrErrors</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_nonCorrErrors</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_mses</b> - Only Fritz!Box Cable</li>

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
      <li><b>nbh_</b><i>01_26_FD_12_01_DA</i> - MAC address and name of an active WLAN neighborhood device.
      <br>
      shown is the SSID, the channel and the bandwidth. Inactive or removed devices get first the value "inactive" and will be deleted during the next update.</li>
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
      <br>
      <li><b>vpn</b><i>n</i> - Name of the VPN</li>
      <li><b>vpn</b><i>n</i><b>_access_type</b> - access type: User VPN | Lan2Lan | Corporate VPN</li>
      <li><b>vpn</b><i>n</i><b>_activated</b> - status if VPN <i>n</i> is active</li>
      <li><b>vpn</b><i>n</i><b>_last_negotiation</b> - timestamp of the last negotiation of the connection (only wireguard)</li>
      <li><b>vpn</b><i>n</i><b>_connected_since</b> - duration of the connection in seconds (only VPN)</li>
      <li><b>vpn</b><i>n</i><b>_remote_ip</b> - IP from client site</li>
      <li><b>vpn</b><i>n</i><b>_state</b> - not active | ready | none</li>
      <li><b>vpn</b><i>n</i><b>_user_connected</b> - status of VPN <i>n</i> connection</li>
      <br>
      <li><b>sip</b><i>n</i>_<i>phone-number</i> - Status</li>
      <li><b>sip_error</b> - counting of SIP's with error. 0 == everything ok.</li>
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
   Steuert gewisse Funktionen eines FRITZ!BOX Routers. Verbundene Fritz!Fon's (MT-F, MT-D, C3, C4) können als Signalgeräte genutzt werden. MP3-Dateien und Text (Text2Speech) können als Klingelton oder einem angerufenen Telefon abgespielt werden.
   <br>
   Für detailierte Anleitungen bitte die <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki</b></a> konsultieren und ergänzen.
   <br/><br/>
   Die Steuerung erfolgt teilweise über die offizielle TR-064-Schnittstelle und teilweise über undokumentierte Schnittstellen zwischen Webinterface und Firmware Kern.</br>
   <br>
   Bitte auch die anderen FRITZ!BOX-Module beachten: <a href="#SYSMON">SYSMON</a> und <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>Das Modul nutzt das Perlmodule 'JSON::XS', 'LWP', 'SOAP::Lite' für den Fernzugriff.</i>
   <br/><br/>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX [host]</code>
      <br/>
      Das Attribut <i>host</i> ist die Web-Adresse (Name oder IP) der FRITZ!BOX. Fehlt es, so schaltet das Modul in den lokalen Modus oder nutzt die Standardadresse "fritz.box".
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
      <li><a name="call"></a>
         <dt><code>set &lt;name&gt; call &lt;number&gt; [duration]</code></dt>
         <br>
         Ruft für 'Dauer' Sekunden (Standard 60 s) die angegebene Telefonnummer von einem internen Telefonanschluss an (Standard ist 1). Wenn der Angerufene abnimmt, hört er die Wartemusik.
         Der interne Telefonanschluss klingelt ebenfalls.
         <br>
      </li><br>

      <li><a name="checkAPIs"></a>
         <dt><code>set &lt;name&gt; checkAPIs</code></dt>
         <br>
         Startet eine erneute Abfrage der exitierenden Programmierschnittstellen der FRITZ!BOX.
      </li><br>

      <li><a name="chgProfile"></a>
         <dt><code>set &lt;name&gt; chgProfile &lt;number&gt; &lt;filtprof<i>n</i>&gt;</code></dt><br>
         &lt;number&gt; ist die ID des landevice<i>n..n</i> oder dessen MAC <br>
         ändert das Profile filtprof mit der Nummer 1..n des Netzgeräts.<br>
         Die Ausführung erfolgt non Blocking. Die Rückmeldung erfolgt im Reading: chgProfileStat <br>
         Benötigt FRITZ!OS 7.21 oder höher. <br>
      </li><br>

      <li><a name="dect"></a>
         <dt><code>set &lt;name&gt; dect &lt;on|off&gt;</code></dt>
         <br>
         Schaltet die DECT-Basis der Box an oder aus.
         <br>
         Benötigt mindestens FRITZ!OS 7.21
      </li><br>

      <li><a name="diversity"></a>
         <dt><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         Schaltet die Rufumleitung (Nummer 1, 2 ...) für einzelne Rufnummern an oder aus.
         <br>
         Achtung! Es lassen sich nur Rufumleitungen für einzelne angerufene Telefonnummern (also nicht "alle") und <u>ohne</u> Abhängigkeit von der anrufenden Nummer schalten.
         Es muss also ein <i>diversity</i>-Geräwert geben.
         <br>
         Benötigt die API: TR064 (>=6.50).
      </li><br>

      <li><a name="guestWlan"></a>
         <dt><code>set &lt;name&gt; guestWlan &lt;on|off&gt;</code></dt>
         <br>
         Schaltet das Gäste-WLAN an oder aus. Das Gäste-Passwort muss gesetzt sein. Wenn notwendig wird auch das normale WLAN angeschaltet.
      </li><br>

      <li><a name="dectRingblock"></a>
         <dt><code>set &lt;name&gt; dectRingblock &lt;dect&lt;nn&gt;&gt; &lt;on|off&gt;</code></dt>
         <br>
         Aktiviert / Deaktiviert die Klingelsperre für das DECT-Telefon mit der ID dect<n>. Die ID kann der Readingliste
         des &lt;name&gt; Device entnommen werden.<br><br>
          <code>set &lt;name&gt; dectRingblock &lt;dect&lt;nn&gt;&gt; &lt;days&gt; &lt;hh:mm-hh:mm&gt; [lmode:on|off] [emode:on|off]</code><br><br>
         Aktiviert / Deaktiviert die Klingelsperre für das DECT-Telefon mit der ID dect<n> für Zeiträume:<br>
         &lt;hh:mm-hh:mm&gt; = Uhrzeit_von bis Uhrzeit_bis<br>
         &lt;days&gt; = wd für Werktags, ed für Jeden Tag, we für Wochenende<br>
         lmode:on|off = lmode definiert die Sperre. Bei off ist sie aus, außer für den angegebenen Zeitraum.<br>
                                                    Bei on ist die Sperre an, außer für den angegebenen Zeitraum<br>
         emode:on|off = emode schaltet Events bei gesetzter Klingelsperre ein/aus. Siehe hierzu die FRITZ!BOX Dokumentation<br>
         Benötigt FRITZ!OS 7.21 oder höher.
      </li><br>

      <li><a name="macFilter"></a>
         <dt><code>set &lt;name&gt; macFilter &lt;on|off&gt;</code></dt>
         <br>
         Schaltet den MAC Filter an oder aus. In der FRITZ!BOX unter "neue WLAN Geräte zulassen/sperren<br>
         Die Ausführung erfolgt non Blocking. Die Rückmeldung erfolgt im Reading: macFilterStat <br>
         Benötigt FRITZ!OS 7.21 oder höher.
      </li><br>

      <li><a name="lockLandevice"></a>
         <dt><code>set &lt;name&gt; lockLandevice &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         &lt;number&gt; ist die ID des landevice<i>n..n</i> oder dessen MAC.<br>
         Schaltet das Netzgerät an oder aus.<br>
         Die Ausführung erfolgt non Blocking. Die Rückmeldung erfolgt im Reading: lockLandevStat <br>
         Benötigt FRITZ!OS 7.21 oder höher.
      </li><br>

      <li><a name="enableVPNshare"></a>
         <dt><code>set &lt;name&gt; enableVPNshare &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         &lt;number&gt; ist die Nummer des Readings vpn<i>n..n</i>_user.. oder _box <br>
         Schaltet das VPN share mit der Nummer nn an oder aus.<br>
         Die Ausführung erfolgt non Blocking. Die Rückmeldung erfolgt im Reading: enableVPNshareStat <br>
         Benötigt FRITZ!OS 7.21 oder höher.
      </li><br>

      <li><a name="switchIPv4DNS"></a>
         <dt><code>set &lt;name&gt; switchIPv4DNS &lt;provider|other&gt;</code></dt>
         <br>
         Ändert den IPv4 DNS auf Internetanbieter oder einem alternativen DNS (sofern in der FRITZ!BOX hinterlegt).<br>
         Needs FRITZ!OS 7.21 or higher
      </li><br>

      <li><a name="password"></a>
         <dt><code>set &lt;name&gt; password &lt;password&gt;</code></dt>
         <br>
         Speichert das Passwort für den Fernzugriff.
      </li><br>

      <li><a name="rescanWLANneighbors"></a>
         <dt><code>set &lt;name&gt; rescanWLANneighbors</code></dt>
         <br>
         Löst eine Scan der WLAN Umgebung aus.
         Die Ausführung erfolgt non Blocking. Die Rückmeldung erfolgt im Reading: rescanWLANneighbors <br>
      </li><br>

      <li><a name="ring"></a>
         <dt><code>set &lt;name&gt; ring &lt;intNumbers&gt; [duration] [show:Text]  [say:Text | play:MP3URL]</code></dt>
         <br>
         <dt>Beispiel:</dt>
         <dd>
         <code>set &lt;name&gt; ring 611,612 5 Budapest show:Es regnet</code>
         <br>
         <code>set &lt;name&gt; ring 610 8 say:Es regnet</code>
         <br>
         <code>set &lt;name&gt; ring 610 10 play:http://raspberrypi/sound.mp3</code>
         </dd>
         Lässt die internen Nummern für "Dauer" Sekunden und (auf Fritz!Fons) mit dem angegebenen "Klingelton" klingeln.
         <br>
         Mehrere interne Nummern müssen durch ein Komma (ohne Leerzeichen) getrennt werden.
         <br>
         Standard-Dauer ist 5 Sekunden. Es kann aber zu Verzögerungen in der FRITZ!BOX kommen. Standard-Klingelton ist der interne Klingelton des Gerätes.
         Der Klingelton wird für Rundrufe (9 oder 50) ignoriert.
         <br>
         Wenn der Anruf angenommen wird, hört der Angerufene die Wartemusik (music on hold), welche ebenfalls zur Nachrichtenübermittlung genutzt werden kann.
         <br>
         Wenn das <a href=#FRITZBOXattr>Attribut</a> 'ringWithIntern' existiert, wird der Text hinter 'show:' als Name des Anrufers angezeigt.
         Er darf maximal 30 Zeichen lang sein.
         <br/><br/>
         Auf Fritz!Fons wird der Text (max. 100 Zeichen) hinter dem Parameter 'say:' direkt angesagt und ersetzt den Klingelton.
         <br>
         Alternativ kann mit 'play:' auch ein MP3-Link (vom einem Webserver) abgespielt werden. Dabei wird die Internetradiostation 39 'FHEM' erzeugt und translate.google.com für Text2Speech genutzt. Es wird <u>immer</u> der komplette Text/Klang abgespielt. Bis zum Ende der 'Klingeldauer' klingelt das Telefon dann mit seinem Standard-Klingelton.
         Das Abspielen ist eventuell nicht auf mehreren Fritz!Fons gleichzeitig möglich.
         <br>
         Je nach Fritz!OS kann das beschriebene Verhalten abweichen.
         <br>
      </li><br>

      <li><a name="tam"></a>
         <dt><code>set &lt;name&gt; tam &lt;number&gt; &lt;on|off&gt;</code></dt>
         Schaltet den Anrufbeantworter (Nummer 1, 2 ...) an oder aus.
         Der Anrufbeantworter muss zuvor auf der FRITZ!BOX eingerichtet werden.
      </li><br>

      <li><a name="update"></a>
         <dt><code>set &lt;name&gt; update</code></dt>
         <br>
         Startet eine Aktualisierung der Gerätewerte.
      </li><br>

      <li><a name="wlan"></a>
         <dt><code>set &lt;name&gt; wlan &lt;on|off&gt;</code></dt>
         <br>
         Schaltet WLAN an oder aus.
      </li><br>

      <li><a name="wlan2.4"></a>
         <dt><code>set &lt;name&gt; wlan2.4 &lt;on|off&gt;</code></dt>
         <br>
         Schaltet WLAN 2.4 GHz an oder aus.
      </li><br>

      <li><a name="wlan5"></a>
         <dt><code>set &lt;name&gt; wlan5 &lt;on|off&gt;</code></dt>
         <br>
         Schaltet WLAN 5 GHz an oder aus.
      </li><br>
   </ul>

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><a name="lanDeviceInfo"></a>
         <dt><code>get &lt;name&gt; lanDeviceInfo &lt;number&gt;</code></dt>
         <br>
         &lt;number&gt; ist die ID des landevice<i>n..n</i> oder dessen MAC
         Zeigt Informationen über das Netzwerkgerät an.<br>
	  Benötigt FRITZ!OS 7.21 oder höher.
      </li><br>

      <li><a name="luaData"></a>
         <dt><code>get &lt;name&gt; luaData &lt;Command&gt;</code></dt>
         <br>
         Führt Komandos über data.lua aus.
      </li><br>

      <li><a name="luaFunction"></a>
         <dt><code>get &lt;name&gt; luaFunction &lt;Command&gt;</code></dt>
         <br>
         Führt AVM lua Funktionen aus.
      </li><br>

      <li><a name="luaInfo"></a>
         <dt><code>get &lt;name&gt; luaInfo &lt;landevices|vpnShares|kidProfiles|userInfos&gt|wlanNeighborhood|docsisInformation;</code></dt>
         <br>
         Benötigt FRITZ!OS 7.21 oder höher.<br>
         lanDevices -> Generiert eine Liste der aktiven und inaktiven Netzwerkgeräte.<br>
         vpnShares -> Generiert eine Liste der aktiven und inaktiven VPN Shares.<br>
         kidProfiles -> Generiert eine Liste der Zugangsprofile.<br>
         userInfos -> Generiert eine Liste der FRITZ!BOX Benutzer.<br>
         wlanNeighborhood -> Generiert eine Liste der WLAN Nachbarschaftsgeräte.<br>
         docsisInformation -> Zeigt Informationen zu DOCSIS an (nur Cable).<br>
      </li><br>

      <li><a name="luaQuery"></a>
         <dt><code>get &lt;name&gt; luaQuery &lt;Command&gt;</code></dt>
         <br>
         Zeigt Informations durch Abfragen der query.lua.
      </li><br>

      <li><a name="tr064Command"></a>
         <dt><code>get &lt;name&gt; tr064Command &lt;service&gt; &lt;control&gt; &lt;action&gt; [[argName1 argValue1] ...]</code></dt>
         <br>
         Führt über TR-064 Aktionen aus (siehe <a href="http://avm.de/service/schnittstellen/">Schnittstellenbeschreibung</a> von AVM).
         <br>
         argValues mit Leerzeichen müssen in Anführungszeichen eingeschlossen werden.
         <br>
         Beispiel: <code>get &lt;name&gt; tr064Command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetInfo NewDectID 1</code>
         <br>
      </li><br>

      <li><a name="tr064ServiceList"></a>
         <dt><code>get &lt;name&gt; tr064ServiceListe</code></dt>
         <br>
         Zeigt die Liste der TR-064-Dienste und Aktionen, die auf dem Gerät erlaubt sind.
      </li><br>
   </ul>

   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><a name="INTERVAL"></a>
         <dt><code>INTERVAL &lt;seconds&gt;</code></dt>
         <br>
         Abfrage-Interval. Standard ist 300 (Sekunden). Der kleinste mögliche Wert ist 60.
      </li><br>

      <li><a name="allowShellCommand"></a>
         <dt><code>allowShellCommand &lt;0 | 1&gt;</code></dt>
         <br>
         Freischalten des get-Befehls "shellCommand"
      </li><br>

      <li><a name="boxUser"></a>
         <dt><code>boxUser &lt;user name&gt;</code></dt>
         <br>
         Benutzername für den TR064- oder einen anderen webbasierten Zugang. Normalerweise wird keine Benutzername für das Login benötigt.
         Wenn die FRITZ!BOX anders konfiguriert ist, kann der Nutzer über dieses Attribut definiert werden.
      </li><br>

      <li><a name="deviceInfo"></a>
         <dt><code>deviceInfo &lt;ipv4, name, uid, connection, speed, rssi, _noDefInf_, _default_&, space, comma&gt;</code></dt>
         <br>
         Mit diesem Attribut kann der Inhalt der Device Readings (mac_...) gestaltet werden. Ist das Attribut nicht gesetzt, setzt
         sich der Inhalt wie folgt zusammen:<br>
         <code>name,[uid],(connection: speed, rssi)</code><br><br>

         Wird der Parameter <code>_noDefInf_</code> gesetzt, die Reihenfolge ind der Liste spielt hier keine Rolle, dann werden nicht vorhandene Werte der Netzwerkverbindung
         mit noConnectInfo (LAN oder WLAN nicht verfügbar) und noSpeedInfo (Geschwindigkeit nicht verfügbar) angezeigt.<br><br>
         Über das freie Eingabefeld können eigene Text oder Zeichen hinzugefügt und zwischen die festen Paramter eingeordnet werden.<br>
         Hierbei gibt es folgende spezielle Texte:<br>
         <code>space</code> => wird zu einem Leerzeichen.<br>
         <code>comma</code> => wird zu einem Komma.<br>
         <code>_default_...</code> => ersetzt das default Leerzeichen als Trennzeichen.<br>
         Beispiele:<br>
         <code>_default_commaspace</code> => wird zu einem Komma gefolgt von einem Leerzeichen als Trenner.<br>
         <code>_default_space:space</code> => wird zu einem einem Leerzeichen:Leerzeichen als Trenner.<br>
         Es werden nicht alle möglichen "unsinnigen" Kombinationen abgefangen. Es kann also auch mal schief gehen.
         <br>
      </li><br>

      <li><a name="disableBoxReadings"></a>
         <dt><code>disableBoxReadings &lt;liste&gt;</code></dt>
         <br>
         Abwählen einzelner box_ Readings.
      </li><br>

      <li><a name="disableDectInfo"></a>
         <dt><code>disableDectInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von Dect Informationen aus/ein.
      </li><br>

      <li><a name="disableFonInfo"></a>
         <dt><code>disableFonInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von Telefon Informationen aus/ein.
      </li><br>

      <li><a name="disableTableFormat"></a>
         <dt><code>disableTableFormat&lt;border(8),cellspacing(10),cellpadding(20)&gt;</code></dt>
         <br>
         Deaktiviert Parameter für die Formatierung der Tabelle.
      </li><br>

      <li><a name="enableAlarmInfo"></a>
         <dt><code>enableAlarmInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von Alarm Informationen aus/ein.
      </li><br>

      <li><a name="enablePassivLanDevices"></a>
         <dt><code>enablePassivLanDevices &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von passiven Netzwerkgeräten als Reading aus/ein.
      </li><br>

      <li><a name="enableSIP"></a>
         <dt><code>enableSIP &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von SIP's als Reading aus/ein.
      </li><br>

      <li><a name="enableUserInfo"></a>
         <dt><code>enableUserInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von Benutzer Informationen aus/ein.
      </li><br>

      <li><a name="enableVPNShares"></a>
         <dt><code>enableVPNShares &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Übernahme von VPN Shares als Reading aus/ein.
      </li><br>

      <li><a name="enableWLANneighbors"></a>
         <dt><code>enableWLANneighbors &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Anzeige von WLAN Nachbarschaft Geräten als Reading aus/ein.
      </li><br>

      <li><a name="wlanNeighborsPrefix"></a>
         <dt><code>wlanNeighborsPrefix &lt;prefix&gt;</code></dt>
         <br>
         Definiert einen Präfix für den Reading Namen der WLAN Nachbarschaftsgeräte, der aus der MAC Adresse gebildet wird. Der default Präfix ist nbh_.
      </li><br>

      <li><a name="fritzBoxIP"></a>
         <dt><code>fritzBoxIP &lt;IP Address&gt;</code></dt>
         <br>
         Veraltet.
      </li><br>

      <li><a name="m3uFileLocal"></a>
         <dt><code>m3uFileLocal &lt;/path/fileName&gt;</code></dt>
         <br>
         Steht als Work around zur Verfügung, wenn der Klingelton eines Fritz!Fon, auf Grund von Firmware Restriktionen (fehlendes Telnet oder WebCMD) nicht gewechselt werden kann.
         <br>
         Funktionsweise: Wenn der Fhem Server zusätzlich einen Web Server zur Verfügung hat, dann kann das Fritz!Fon eine m3u Datei von diesem Web Server als eine Radio Station abspielen.
         Hierfür muss eine Internet Radio Station auf dem Fritz!Fon auf die Server URL für diese Datei zeigen und der interne Klingelton muss auf diese Station eingestellt werden.
         <br>
         Ist das Attribut gesetzt, wird die Server Datei "m3uFileLocal" (lokale Adresse der Fritz!Fon URL) mit der URL der text2speech Engine (say:) oder mit der MP3-Datei (play:) gefüllt. Das Fritz!Fon spielt dann diese URL ab.
      </li><br>

      <li><a name="m3uFileURL"></a>
         <dt><code>m3uFileURL &lt;URL&gt;</code></dt>
         <br>
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
      <li><b>box_cpuTemp</b> - Temperatur der FritxBox CPU</li>
      <li><b>box_dect</b> - Aktueller Status des DECT-Basis: aktiv, inaktiv</li>
      <li><b>box_dsl_downStream</b> - Min Effektive Datenrate  (MBit/s)</li>
      <li><b>box_dsl_upStream</b> - Min Effektive Datenrate  (MBit/s)</li>
      <li><b>box_fwVersion</b> - Firmware-Version der Box, wenn veraltet dann wird '(old)' angehangen</li>
      <li><b>box_guestWlan</b> - Aktueller Status des Gäste-WLAN</li>
      <li><b>box_guestWlanCount</b> - Anzahl der Geräte die über das Gäste-WLAN verbunden sind</li>
      <li><b>box_guestWlanRemain</b> - Verbleibende Zeit bis zum Ausschalten des Gäste-WLAN</li>
      <li><b>box_ipExtern</b> - Internet IPv4 der FRITZ!BOX</li>
      <li><b>box_ipv6Extern</b> - Internet IPv6 der FRITZ!BOX</li>
      <li><b>box_ipv6Prefix</b> - Internet IPv6 Prefix der FRITZ!BOX für das LAN/WLAN</li>
      <li><b>box_macFilter_active</b> - Status des WLAN MAC-Filter (WLAN-Zugang auf die bekannten WLAN-Ger�te beschränken)</li>
      <li><b>box_meshRole</b> - ab Version 07.21 wird die Mesh Rolle (master, slave) angezeigt.</li>
      <li><b>box_model</b> - FRITZ!BOX-Modell</li>
      <li><b>box_moh</b> - Wartemusik-Einstellung</li>
      <li><b>box_connect</b> - Verbindungsstatus: Unconfigured, Connecting, Authenticating, Connected, PendingDisconnect, Disconnecting, Disconnected</li>
      <li><b>box_last_connect_err</b> - letzter Verbindungsfehler</li>
      <li><b>box_uptime</b> - Laufzeit seit letztem Neustart</li>
      <li><b>box_uptimeConnect</b> - Verbindungsdauer seit letztem Neuverbinden</li>
      <li><b>box_powerRate</b> - aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_rateDown</b> - Download-Geschwindigkeit des letzten Intervals in kByte/s</li>
      <li><b>box_rateUp</b> - Upload-Geschwindigkeit des letzten Intervals in kByte/s</li>
      <li><b>box_stdDialPort</b> - Anschluss der geräteseitig von der Wählhilfe genutzt wird</li>
      <li><b>box_tr064</b> - Anwendungsschnittstelle TR-064 (wird auch von diesem Modul benötigt)</li>
      <li><b>box_tr069</b> - Provider-Fernwartung TR-069 (sicherheitsrelevant!)</li>
      <li><b>box_vdsl_downStreamRate</b> - Aktuelle Datenrate (MBit/s)</li>
      <li><b>box_vdsl_upStreamRate</b> - Aktuelle Datenrate (MBit/s)</li>
      <li><b>box_wlanCount</b> - Anzahl der Geräte die über WLAN verbunden sind</li>
      <li><b>box_wlan_2.4GHz</b> - Aktueller Status des 2.4-GHz-WLAN</li>
      <li><b>box_wlan_5GHz</b> - Aktueller Status des 5-GHz-WLAN</li>
      <li><b>box_wlan_lastScanTime</b> - Letzter Scan der WLAN Umgebung. Ist nur vorhanden, wenn das Attribut enableWLANneighbors gesetzt ist.</li>

      <br>
      <li><b>box_docsis30_Ds_powerLevels</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_latencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_frequencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_corrErrors</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_nonCorrErrors</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_mses</b> - Nur Fritz!Box Cable</li>

      <br>
      <li><b>dect</b><i>1</i> - Name des DECT Telefons <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_alarmRingTone</b> - Klingelton beim Wecken über das DECT Telefon <i>1</i></li>
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
      <li><b>fon</b><i>1</i> - Name des analogen Telefonanschlusses <i>1</i> an der FRITZ!BOX</li>
      <li><b>fon</b><i>1</i><b>_intern</b> - Interne Nummer des analogen Telefonanschlusses <i>1</i></li>
      <li><b>fon</b><i>1</i><b>_out</b> - ausgehende Nummer des Anschlusses <i>1</i></li>
      <br>
      <li><b>gsm_internet</b> - Internetverbindung errichtet über Mobilfunk-Stick </li>
      <li><b>gsm_rssi</b> - Indikator der empfangenen GSM-Signalstärke (0-100)</li>
      <li><b>gsm_state</b> - Status der Mobilfunk-Verbindung</li>
      <li><b>gsm_technology</b> - GSM-Technologie, die für die Datenübertragung genutzt wird (GPRS, EDGE, UMTS, HSPA)</li>
      <br>
      <li><b>mac_</b><i>01_26_FD_12_01_DA</i> - MAC Adresse und Name eines aktiven Netzwerk-Gerätes.
      <br>
      Bei einer WLAN-Verbindung wird "WLAN" und (von der Box gesehen) die Sende- und Empfangsgeschwindigkeit und die Empfangsstärke angehangen. Bei einer LAN-Verbindung wird der LAN-Port und die LAN-Geschwindigkeit angehangen. Gast-Verbindungen werden mit "gWLAN" oder "gLAN" gekennzeichnet.
      <br>
      Inaktive oder entfernte Geräte erhalten zuerst den Werte "inactive" und werden beim nächsten Update gelöscht.</li>
      <br>
      <li><b>nbh_</b><i>01_26_FD_12_01_DA</i> - MAC Adresse und Name eines aktiven WAN-Gerätes.
      <br>
      Es wird die SSID, der Kanal und das Frequenzband angezeigt.
      <br>
      Inaktive oder entfernte Geräte erhalten zuerst den Werte "inactive" und werden beim nächsten Update gelöscht.</li>
      <br>
      <li><b>radio</b><i>01</i> - Name der Internetradiostation <i>01</i></li>
      <br>
      <li><b>tam</b><i>1</i> - Name des Anrufbeantworters <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_newMsg</b> - Anzahl neuer Nachrichten auf dem Anrufbeantworter <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_oldMsg</b> - Anzahl alter Nachrichten auf dem Anrufbeantworter <i>1</i></li>
      <li><b>tam</b><i>1</i><b>_state</b> - Aktueller Status des Anrufbeantworters <i>1</i></li>
      <br>
      <li><b>user</b><i>01</i> - Name von Nutzer/IP <i>1</i> für den eine Zugangsbeschränkung (Kindersicherung) eingerichtet ist</li>
      <li><b>user</b><i>01</i>_thisMonthTime - Internetnutzung des Nutzers/IP <i>1</i> im aktuellen Monat (Kindersicherung)</li>
      <li><b>user</b><i>01</i>_todaySeconds - heutige Internetnutzung des Nutzers/IP <i>1</i> in Sekunden (Kindersicherung)</li>
      <li><b>user</b><i>01</i>_todayTime - heutige Internetnutzung des Nutzers/IP <i>1</i> (Kindersicherung)</li>
      <br>
      <li><b>vpn</b><i>n</i> - Name des VPN</li>
      <li><b>vpn</b><i>n</i><b>_access_type</b> - Verbindungstyp: Benutzer VPN | Netzwert zu Netzwerk | Firmen VPN</li>
      <li><b>vpn</b><i>n</i><b>_activated</b> - Status, ob VPN <i>n</i> aktiv ist</li>
      <li><b>vpn</b><i>n</i><b>_last_negotiation</b> - Uhrzeit der letzten Aushandlung der Verbindung (nur Wireguard)</li>
      <li><b>vpn</b><i>n</i><b>_connected_since</b> - Dauer der Verbindung in Sekunden (nur VPN)</li>
      <li><b>vpn</b><i>n</i><b>_remote_ip</b> - IP der Gegenstelle</li>
      <li><b>vpn</b><i>n</i><b>_state</b> - not active | ready | none</li>
      <li><b>vpn</b><i>n</i><b>_user_connected</b> - Status, ob Benutzer VPN <i>n</i> verbunden ist</li>
      <br>
      <li><b>sip</b><i>n</i>_<i>Telefon-Nummer</i> - Status</li>
      <li><b>sip_error</b> - zeigt die Anzahl fehlerhafter SIP. 0 == alles Ok.</li>
   </ul>
   <br>
</ul>
</div>
=end html_DE

=cut--

###############################################################
# HOST=box:settings/hostname
# SSID1=wlan:settings/ssid
# SSID2=wlan:settings/ssid_scnd
# FORWARDS=forwardrules:settings/rule/list(activated,description,protocol,port,fwip,fwport,endport)
# SIPS=sip:settings/sip/list(ID,displayname)
# NUMBERS=telcfg:settings/VoipExtension/listwindow(2,2,Name,enabled) <=== eingeschr�nkte Ergebnismenge
# DEVICES=ctlusb:settings/device/count
# PHYS=usbdevices:settings/physmedium/list(name,vendor,serial,fw_version,conntype,capacity,status,usbspeed,model)
# PHYSCNT=usbdevices:settings/physmediumcnt
# VOLS=usbdevices:settings/logvol/list(name,status,enable,phyref,filesystem,capacity,usedspace,readonly)
# VOLSCNT=usbdevices:settings/logvolcnt
# PARTS=ctlusb:settings/storage-part/count
# SIP1=sip:settings/sip1/activated
###############################################################
