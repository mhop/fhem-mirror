###############################################################
# $Id$
#
#  72_FRITZBOX.pm
#
#  (c) 2014 Torsten Poitzsch
#  (c) 2014-2020 tupol http://forum.fhem.de/index.php?action=profile;u=5432
#  (c) 2021-2024 jowiemann https://forum.fhem.de/index.php?action=profile
#
#  Setting the offset of the Fritz!Dect radiator controller is based on preliminary
#  work by Tobias (https://forum.fhem.de/index.php?action=profile;u=53943)
#
#
#  This module handles the Fritz!Box router/repeater
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

my $ModulVersion = "08.03.00";
my $missingModul = "";
my $FRITZBOX_TR064pwd;
my $FRITZBOX_TR064user;

eval "use URI::Escape;1"  or $missingModul .= "URI::Escape ";
eval "use MIME::Base64;1" or $missingModul .= "MIME::Base64 ";
eval "use IO::Socket;1"   or $missingModul .= "IO::Socket ";
eval "use Net::Ping;1"    or $missingModul .= "Net::Ping ";

use FritzBoxUtils; ## only for web access login

#sudo apt-get install libjson-perl
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";

eval "use URI::Escape;1" or $missingModul .= "URI::Escape ";
# sudo apt-get install libsoap-lite-perl
eval "use SOAP::Lite;1" or $missingModul .= "Soap::Lite ";

# $Data::Dumper::Terse = 1;
# $Data::Dumper::Purity = 1;
# $Data::Dumper::Sortkeys = 1;
eval "use Data::Dumper;1" or $missingModul .= "Data::Dumper ";

#use JSON::Parse 'parse_json';
#use HTML::Make;
#binmode STDOUT, ":encoding(utf8)";

sub FRITZBOX_Log($$$);
sub FRITZBOX_DebugLog($$$$;$);
sub FRITZBOX_dbgLogInit($@);
sub FRITZBOX_Initialize($);

# Sub, die den nonBlocking Timer umsetzen
sub FRITZBOX_Readout_Start($);
sub FRITZBOX_Readout_Run_Web($);
sub FRITZBOX_Readout_Run_Web_LuaQuery($$$$);
sub FRITZBOX_Readout_Run_Web_LuaData($$$$);
sub FRITZBOX_Readout_Run_Web_TR064($$$$);
sub FRITZBOX_Readout_Response($$$@);
sub FRITZBOX_Readout_Done($);
sub FRITZBOX_Readout_Process($$);
sub FRITZBOX_Readout_Aborted($);
sub FRITZBOX_Readout_Add_Reading($$$$@);
sub FRITZBOX_Readout_Format($$$);

# Sub, die den nonBlocking Set/Get Befehl umsetzen
sub FRITZBOX_Readout_SetGet_Start($);
sub FRITZBOX_Readout_SetGet_Done($);
sub FRITZBOX_Readout_SetGet_Aborted($);

# Sub, die einen Set Befehl nonBlocking umsetzen
sub FRITZBOX_Set_check_APIs($);
sub FRITZBOX_Set_block_Incoming_Phone_Call($);
sub FRITZBOX_Set_GuestWlan_OnOff($);
sub FRITZBOX_Set_call_Phone($);
sub FRITZBOX_Set_ring_Phone($);
sub FRITZBOX_Set_rescan_Neighborhood($);
sub FRITZBOX_Set_macFilter_OnOff($);
sub FRITZBOX_Set_change_Profile($);
sub FRITZBOX_Set_lock_Landevice_OnOffRt($);
sub FRITZBOX_Set_lock_Landevice_OnOffRt_8($);
sub FRITZBOX_Set_enable_VPNshare_OnOff($);
sub FRITZBOX_Set_wake_Up_Call($);
sub FRITZBOX_Set_Wlan_Log_Ext_OnOff($);
sub FRITZBOX_Set_Wlan_Guest_Params($);

# Sub, die einen Get Befehl nonBlocking umsetzen
sub FRITZBOX_Get_MobileInfo($);
sub FRITZBOX_Get_WLAN_globalFilters($);
sub FRITZBOX_Get_LED_Settings($);
sub FRITZBOX_Get_VPN_Shares_List($);
sub FRITZBOX_Get_DOCSIS_Informations($);
sub FRITZBOX_Get_WLAN_Environment($);
sub FRITZBOX_Get_SmartHome_Devices_List($@);
sub FRITZBOX_Get_Lan_Devices_List($);
sub FRITZBOX_Get_User_Info_List($);
sub FRITZBOX_Get_Fritz_Log_Info_nonBlk($);
sub FRITZBOX_Get_Kid_Profiles_List($);

# Sub, die einen Get Befehl blocking umsetzen
sub FRITZBOX_Get_Fritz_Log_Info_Std($$$);
sub FRITZBOX_Get_Lan_Device_Info($$$);

# Sub, die SOAP Anfragen umsetzen
sub FRITZBOX_SOAP_Request($$$$);
sub FRITZBOX_SOAP_Test_Request($$$$);

# Sub, die TR064 umsetzen
sub FRITZBOX_init_TR064($$);
sub FRITZBOX_get_TR064_ServiceList($);
sub FRITZBOX_call_TR064_Cmd($$$);

# Sub, die die Web Verbindung erstellt und aufrecht erhält
sub FRITZBOX_open_Web_Connection($);

# Sub, die die Funktionen data.lua, query.lua, function.lua und javascript abbilden
sub FRITZBOX_call_Lua_Query($$@);
sub FRITZBOX_call_LuaData($$$@);
sub FRITZBOX_write_javaScript($$;@);
sub FRITZBOX_call_javaScript($$@);

# Sub, die Helferfunktionen bereit stellen
sub FRITZBOX_Helper_make_TableRow($@);
sub FRITZBOX_Helper_process_JSON($$$@);
sub FRITZBOX_Helper_analyse_Lua_Result($$;@);

sub FRITZBOX_Phonebook_readRemote($$);
sub FRITZBOX_Phonebook_parse($$$$);
sub FRITZBOX_Phonebook_Number_normalize($$);

sub FRITZBOX_Helper_retMsg($$;@);
sub FRITZBOX_Helper_html2txt($);
sub FRITZBOX_Helper_store_Password($$);
sub FRITZBOX_Helper_read_Password($);
sub FRITZBOX_Helper_Url_Regex;
# sub FRITZBOX_Helper_Json2HTML($);

my %LuaQueryCmd = (
        box_uptimeHours        => { cmd   => "uimodlogic:status/uptime_hours"},
        box_uptimeMinutes      => { cmd   => "uimodlogic:status/uptime_minutes"},
        box_fwVersion_neu      => { cmd   => "uimodlogic:status/nspver"},

        box_fwVersion          => { cmd   => "logic:status/nspver"},
        box_fwUpdate           => { cmd   => "updatecheck:status/update_available_hint"},

        box_powerRate          => { cmd   => "power:status/rate_sumact"},
        box_cpuTemp            => { cmd   => "power:status/act_temperature"},

        box_tr064              => { cmd   => "tr064:settings/enabled"},
        box_tr069              => { cmd   => "tr069:settings/enabled"},

        box_upnp               => { cmd   => "box:settings/upnp_activated"},
        box_upnpCtrl           => { cmd   => "box:settings/upnp_control_activated"},

        lanDevice              => { cmd   => "landevice:settings/landevice/list(mac,ip,ethernet,ethernet_port,ethernetport,guest,name,active,online,wlan,speed,UID,static_dhcp)"},
        lanDeviceNew           => { cmd   => "landevice:settings/landevice/list(mac,ip,ethernet,guest,name,active,online,wlan,speed,UID)"},

        box_is_double_wlan     => { cmd   => "wlan:settings/feature_flags/DBDC"},
        box_wlan_24GHz         => { cmd   => "wlan:settings/ap_enabled"},
        box_wlan_5GHz          => { cmd   => "wlan:settings/ap_enabled_scnd"},
        box_guestWlan          => { cmd   => "wlan:settings/guest_ap_enabled"},
        box_guestWlanRemain    => { cmd   => "wlan:settings/guest_time_remain"},
        box_macFilter_active   => { cmd   => "wlan:settings/is_macfilter_active"},
        wlanList               => { cmd   => "wlan:settings/wlanlist/list(mac,speed,speed_rx,rssi,is_guest,is_remote,is_repeater,is_ap)"},
        wlanListNew            => { cmd   => "wlan:settings/wlanlist/list(mac,speed,rssi)"},

        box_dect               => { cmd   => "dect:settings/enabled"},
        handsetCount           => { cmd   => "dect:settings/Handset/count"},
        handset                => { cmd   => "dect:settings/Handset/list(User,Manufacturer,Model,FWVersion,Productname)"},

        box_stdDialPort        => { cmd   => "telcfg:settings/DialPort"},
        init                   => { cmd   => "telcfg:settings/Foncontrol"},
        dectUser               => { cmd   => "telcfg:settings/Foncontrol/User/list(Id,Name,Intern,IntRingTone,AlarmRingTone0,RadioRingID,ImagePath,G722RingTone,G722RingToneName,NoRingTime,RingAllowed,NoRingTimeFlags,NoRingWithNightSetting)"},
        fonPort                => { cmd   => "telcfg:settings/MSN/Port/list(Name,MSN)"},
        ringGender             => { cmd   => "telcfg:settings/VoiceRingtoneGender"},
        diversity              => { cmd   => "telcfg:settings/Diversity/list(MSN,Active,Destination)"},
        box_moh                => { cmd   => "telcfg:settings/MOHType"},
        dectUser               => { cmd   => "telcfg:settings/Foncontrol/User/list(Id,Name,Intern,IntRingTone,AlarmRingTone0,RadioRingID,ImagePath,G722RingTone,G722RingToneName,NoRingTime,RingAllowed,NoRingTimeFlags,NoRingWithNightSetting)"},
        fonPort                => { cmd   => "telcfg:settings/MSN/Port/list(Name,MSN)"},
        alarmClock             => { cmd   => "telcfg:settings/AlarmClock/list(Name,Active,Time,Number,Weekdays)"},

        tam                    => { cmd   => "tam:settings/TAM/list(Name,Display,Active,NumNewMessages,NumOldMessages)"},

        TodayBytesReceivedHigh => { cmd   => "inetstat:status/Today/BytesReceivedHigh"},
        TodayBytesReceivedLow  => { cmd   => "inetstat:status/Today/BytesReceivedLow"},
        TodayBytesSentHigh     => { cmd   => "inetstat:status/Today/BytesSentHigh"},
        TodayBytesSentLow      => { cmd   => "inetstat:status/Today/BytesSentLow"},

        userProfil             => { cmd   => "user:settings/user/list(name,filter_profile_UID,this_month_time,today_time,type)"},
        userProfilNew          => { cmd   => "user:settings/user/list(name,type)"},
        userTicket             => { cmd   => "userticket:settings/ticket/list(id)"},

        radio                  => { cmd   => "configd:settings/WEBRADIO/list(Name)"},

        dslStatGlobalIn        => { cmd   => "dslstatglobal:status/in"},
        dslStatGlobalOut       => { cmd   => "dslstatglobal:status/out"},

        sip_info               => { cmd   => "sip:settings/sip/list(activated,displayname,connect)"},

        vpn_info               => { cmd   => "vpn:settings/connection/list(remote_ip,activated,name,state,access_type,connected_since)"},

        GSM_RSSI               => { cmd   => "gsm:settings/RSSI"},
        GSM_NetworkState       => { cmd   => "gsm:settings/NetworkState"},
        GSM_AcT                => { cmd   => "gsm:settings/AcT"},
#        GSM_MaxUL              => { cmd   => "gsm:settings/MaxUL"},
#        GSM_MaxDL              => { cmd   => "gsm:settings/MaxDL"},
#        GSM_CurrentUL          => { cmd   => "gsm:settings/CurrentUL"},
#        GSM_CurrentDL          => { cmd   => "gsm:settings/CurrentDL"},
#        GSM_Established        => { cmd   => "gsm:settings/Established"},
#        GSM_BER                => { cmd   => "gsm:settings/BER"},
#        GSM_Manufacturer       => { cmd   => "gsm:settings/Manufacturer"},
#        GSM_Model              => { cmd   => "gsm:settings/Model"},
#        GSM_Operator           => { cmd   => "gsm:settings/Operator"},
#        GSM_PIN_State          => { cmd   => "gsm:settings/PIN_State"},
#        GSM_Trycount           => { cmd   => "gsm:settings/Trycount"},
#        GSM_ModemPresent       => { cmd   => "gsm:settings/ModemPresent"},
#        GSM_AllowRoaming       => { cmd   => "gsm:settings/AllowRoaming"},
#        GSM_VoiceStatus        => { cmd   => "gsm:settings/VoiceStatus"},
#        GSM_SubscriberNumber   => { cmd   => "gsm:settings/SubscriberNumber"},
#        GSM_InHomeZone         => { cmd   => "gsm:settings/InHomeZone"},

        UMTS_enabled           => { cmd   => "umts:settings/enabled"} # if last item change, change last comma
#        UMTS_name              => { cmd   => "umts:settings/name"},
#        UMTS_provider          => { cmd   => "umts:settings/provider"},
#        UMTS_idle              => { cmd   => "umts:settings/idle"},
#        UMTS_backup_enable     => { cmd   => "umts:settings/backup_enable"},
#        UMTS_backup_downtime   => { cmd   => "umts:settings/backup_downtime"},
#        UMTS_backup_reverttime => { cmd   => "umts:settings/backup_reverttime"},
#        UMTS_backup_reverttime => { cmd   => "umts:settings/backup_reverttime"},
);

# https://www.pcwelt.de/article/1196302/die-neuesten-updates-fuer-fritzbox-co.html
my %FB_Model = (
       '7690'        => { Version => "8.02", Datum => "16.01.2025"},
       '7682'        => { Version => "8.03", Datum => "21.01.2025"},
       '7590 AX'     => { Version => "8.02", Datum => "09.01.2025"},
       '7590'        => { Version => "8.02", Datum => "16.01.2025"},
       '7583 VDSL'   => { Version => "8.03", Datum => "13.02.2025"},
       '7583'        => { Version => "8.03", Datum => "13.02.2025"},
       '7582'        => { Version => "7.18", Datum => "19.08.2024"},
       '7581'        => { Version => "7.18", Datum => "19.08.2024"},
       '7580'        => { Version => "7.30", Datum => "04.09.2023"},
       '7560'        => { Version => "7.30", Datum => "04.09.2023"},
       '7530'        => { Version => "8.02", Datum => "13.01.2025"},
       '7530 AX'     => { Version => "8.02", Datum => "09.01.2025"},
       '7520 B'      => { Version => "8.00", Datum => "17.10.2024"},
       '7520'        => { Version => "8.00", Datum => "17.10.2024"},
       '7510'        => { Version => "8.02", Datum => "21.01.2025"},
       '7490'        => { Version => "7.60", Datum => "29.01.2025"},
       '7430'        => { Version => "7.31", Datum => "04.09.2023"},
       '7412'        => { Version => "6.88", Datum => "04.09.2023"},
       '7390'        => { Version => "6.88", Datum => "04.09.2023"},
       '7362 SL'     => { Version => "7.14", Datum => "04.09.2023"},
       '7360 v2'     => { Version => "6.88", Datum => "04.09.2023"},
       '7360 v1'     => { Version => "6.36", Datum => "06.09.2023"},
       '7360'        => { Version => "6.85", Datum => "13.03.2017"},
       '7360 SL'     => { Version => "6.35", Datum => "07.09.2023"},
       '7312'        => { Version => "6.56", Datum => "07.09.2023"},
       '7272'        => { Version => "6.89", Datum => "04.09.2023"},
       '6890 LTE'    => { Version => "7.57", Datum => "04.09.2023"},
       '6860 5G'     => { Version => "7.61", Datum => "01.01.2025"},
       '6850 5G'     => { Version => "8.00", Datum => "19.12.2024"},
       '6850 LTE'    => { Version => "8.00", Datum => "19.12.2024"},
       '6842 LTE'    => { Version => "6.35", Datum => "07.09.2023"},
       '6840 LTE'    => { Version => "6.88", Datum => "07.09.2023"},
       '6820 LTE v3' => { Version => "7.57", Datum => "04.09.2023"},
       '6820 LTE v2' => { Version => "7.57", Datum => "04.09.2023"},
       '6820 LTE'    => { Version => "7.30", Datum => "04.09.2023"},
       '6810 LTE'    => { Version => "6.35", Datum => "07.09.2023"},
       '6690 Cable'  => { Version => "8.02", Datum => "09.01.2025"},
       '6670 Cable'  => { Version => "8.02", Datum => "09.01.2025"},
       '6660 Cable'  => { Version => "8.02", Datum => "09.01.2025"},
       '6591 Cable'  => { Version => "8.02", Datum => "09.01.2025"},
       '6590 Cable'  => { Version => "7.57", Datum => "04.09.2023"},
       '6490 Cable'  => { Version => "7.57", Datum => "04.09.2023"},
       '6430 Cable'  => { Version => "7.30", Datum => "04.09.2023"},
       '5690 Pro  '  => { Version => "8.03", Datum => "06.02.2025"},
       '5590 Fiber'  => { Version => "8.02", Datum => "09.01.2025"},
       '5530 Fiber'  => { Version => "8.02", Datum => "09.01.2025"},
       '5491'        => { Version => "7.31", Datum => "04.09.2023"},
       '5490'        => { Version => "7.31", Datum => "04.09.2023"},
       '4060'        => { Version => "8.02", Datum => "09.01.2025"},
       '4050'        => { Version => "8.02", Datum => "09.01.2025"},
       '4040'        => { Version => "8.00", Datum => "16.10.2024"},
       '4020'        => { Version => "7.04", Datum => "18.08.2024"},
       '3490'        => { Version => "7.31", Datum => "04.09.2023"},
       '3272'        => { Version => "6.89", Datum => "07.09.2023"}
   );

my %RP_Model = (
        'Gateway'     => "8.01"
      , '6000 v2'     => "7.58"
      , '3000 AX'     => "7.58"
      , '3000'        => "7.58"
      , '2400'        => "7.58"
      , 'DVB-C'       => "7.03"
      , '1750E'       => "7.31"
      , '1200 AX'     => "7.58"
      , '1200'        => "7.58"
      , '1160'        => "7.15"
      , '600 (V2)'    => "7.58"
      , '600'         => "7.58"
      , '450E'        => "7.15"
      , '310 a/b'     => "7.16"
      , '300E'        => "6.34"
      , 'N/G'         => "4.88"
   );

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
my %userType  = qw{1 IP 2 PC-User 3 Default 4 Guest};
my %mohtype   = (0=>"default", 1=>"sound", 2=>"customer", "err"=>"" );
my %landevice = ();

my %LOG_Text = (
   0 => "SERVER:",
   1 => "ERROR:",
   2 => "SIGNIFICANT:",
   3 => "BASIC:",
   4 => "EXPANDED:",
   5 => "DEBUG:"
); 

# FIFO Buffer for commands
my @cmdBuffer = ();
my $cmdBufferTimeout = 0;

#######################################################################
sub FRITZBOX_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;

   my $instHash = ( ref($hash) eq "HASH" ) ? $hash : $defs{$hash};
   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   
   if ($instHash->{helper}{FhemLog3Std}) {
      Log3 $hash, $loglevel, $instName . ": " . $text;
      return undef;
   }

   my $xline       = ( caller(0) )[2];

   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//       if ( defined $sub );
   $sub ||= 'no-subroutine-specified';

   my $avmModel = InternalVal($instName, "MODEL", defined $instHash->{boxModel} ? $instHash->{boxModel} : "0000");
   $avmModel = $1 if $avmModel =~ m/(\d+)/;

   my $fwV = ReadingsVal($instName, "box_fwVersion", "none");

   $text = $LOG_Text{$loglevel} . $text;
   $text = "[$instName | $avmModel | $fwV | $sub.$xline] - " . $text;

   if ( $instHash->{helper}{logDebug} ) {
     FRITZBOX_DebugLog $instHash, $instHash->{helper}{debugLog} . "-%Y-%m.dlog", $loglevel, $text;
   } else {
     Log3 $hash, $loglevel, $text;
   }

} # End FRITZBOX_Log

#######################################################################
sub FRITZBOX_DebugLog($$$$;$) {

  my ($hash, $filename, $loglevel, $text, $timestamp) = @_;
  my $name = $hash->{'NAME'};
  my $tim;

  $loglevel .= ":" if ($loglevel);
  $loglevel ||= "";

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards("%L/" . $filename, @t);

  unless ($timestamp) {

    $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);

    if ($attr{global}{mseclog}) {
      $tim .= sprintf(".%03d", $microseconds / 1000);
    }
  } else {
    $tim = $timestamp;
  }

  open(my $fh, '>>', $nfile);
  print $fh "$tim $loglevel$text\n";
  close $fh;

  return undef;

} # end FRITZBOX__DebugLog

#######################################################################
sub FRITZBOX_dbgLogInit($@) {

   my ($hash, $cmd, $aName, $aVal) = @_;
   my $name = $hash->{NAME};

   if ($cmd eq "init" ) {
     $hash->{DEBUGLOG}             = "OFF";
     $hash->{helper}{debugLog}     = $name . "_debugLog";
     $hash->{helper}{logDebug}     = AttrVal($name, "verbose", 0) == 5;
     if ($hash->{helper}{logDebug}) {
       my ($seconds, $microseconds) = gettimeofday();
       my @t = localtime($seconds);
       my $nfile = ResolveDateWildcards($hash->{helper}{debugLog} . '-%Y-%m.dlog', @t);

       $hash->{DEBUGLOG} = '<html>'
                         . '<a href="/fhem/FileLog_logWrapper&amp;dev='
                         . $hash->{helper}{debugLog}
                         . '&amp;type=text&amp;file='
                         . $nfile
                         . '">DEBUG Log kann hier eingesehen werden</a>'
                         . '</html>';
     }
   }

   return if $aVal && $aVal == -1;

   my $dirdef     = Logdir() . "/";
   my $dbgLogFile = $dirdef . $hash->{helper}{debugLog} . '-%Y-%m.dlog';

   if ($cmd eq "set" ) {
     
     if($aVal == 5) {

       unless (defined $defs{$hash->{helper}{debugLog}}) {
         my $dMod  = 'defmod ' . $hash->{helper}{debugLog} . ' FileLog ' . $dbgLogFile . ' FakeLog readonly';

         fhem($dMod, 1);

         if (my $dRoom = AttrVal($name, "room", undef)) {
           $dMod = 'attr -silent ' . $hash->{helper}{debugLog} . ' room ' . $dRoom;
           fhem($dMod, 1);
         }

         if (my $dGroup = AttrVal($name, "group", undef)) {
           $dMod = 'attr -silent ' . $hash->{helper}{debugLog} . ' group ' . $dGroup;
           fhem($dMod, 1);
         }
       }

       FRITZBOX_Log $name, 3, "redirection debugLog: $dbgLogFile started";

       $hash->{helper}{logDebug} = 1;

       FRITZBOX_Log $name, 3, "redirection debugLog: $dbgLogFile started";

       my ($seconds, $microseconds) = gettimeofday();
       my @t = localtime($seconds);
       my $nfile = ResolveDateWildcards($hash->{helper}{debugLog} . '-%Y-%m.dlog', @t);

       $hash->{DEBUGLOG} = '<html>'
                         . '<a href="/fhem/FileLog_logWrapper&amp;dev='
                         . $hash->{helper}{debugLog}
                         . '&amp;type=text&amp;file='
                         . $nfile
                         . '">DEBUG Log kann hier eingesehen werden</a>'
                         . '</html>';

     } elsif($aVal < 5 && $hash->{helper}{logDebug}) {
       fhem("delete " . $hash->{helper}{debugLog}, 1);

       FRITZBOX_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

       $hash->{helper}{logDebug} = 0;
       $hash->{DEBUGLOG}         = "OFF";

       FRITZBOX_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

#       unless (unlink glob($dirdef . $hash->{helper}{debugLog} . '*.dlog')) {
#         return "Temporary debug file: " . $dirdef . $hash->{helper}{debugLog} . "*.dlog could not be removed: $!";
#       }
     }
   }

   if ($cmd eq "del" ) {
     fhem("delete " . $hash->{helper}{debugLog}, 1) if $hash->{helper}{logDebug};

     FRITZBOX_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

     $hash->{helper}{logDebug} = 0;
     $hash->{DEBUGLOG}         = "OFF";

     FRITZBOX_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

     unless (unlink glob($dirdef . $hash->{helper}{debugLog} . '*.dlog')) {
       FRITZBOX_Log $name, 3, "Temporary debug file: " . $dirdef . $hash->{helper}{debugLog} . "*.dlog could not be removed: $!";
     }

   }

} # end FRITZBOX_dbgLogInit

#######################################################################
sub FRITZBOX_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash
 
  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
  my $devName = $dev_hash->{NAME}; # Device that created the events
  my $events = deviceEvents($dev_hash, 1);

  if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
  {
     # initialize DEGUB LOg function
     FRITZBOX_dbgLogInit($own_hash, "init", "verbose", AttrVal($ownName, "verbose", -1));
     # end initialize DEGUB LOg function
  }
}

#######################################################################
sub FRITZBOX_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}       = "FRITZBOX_Define";
  $hash->{UndefFn}     = "FRITZBOX_Undefine";
  $hash->{DeleteFn}    = "FRITZBOX_Delete";
  $hash->{RenameFn}    = "FRITZBOX_Rename";
  $hash->{NotifyFn}    = "FRITZBOX_Notify";
  # $hash->{FW_detailFn} = "FRITZBOX_detailFn";

  $hash->{SetFn}    = "FRITZBOX_Set";
  $hash->{GetFn}    = "FRITZBOX_Get";
  $hash->{AttrFn}   = "FRITZBOX_Attr";
  $hash->{AttrList} = "boxUser "
                ."disable:0,1 "
                ."nonblockingTimeOut:30,35,40,50,75,100,125 "
                ."setgetTimeout:10,30,40,50,75,100,125 "
                ."userAgentTimeOut "
                ."INTERVAL "
                ."reConnectInterval "
                ."maxSIDrenewErrCnt "
                ."userTickets "
                ."enablePhoneBookInfo:0,1 "
                ."enableKidProfiles:0,1 "
                ."enablePassivLanDevices:0,1 "
                ."enableVPNShares:0,1 "
                ."enableUserInfo:0,1 "
                ."enableAlarmInfo:0,1 "
                ."enableWLANneighbors:0,1 "
                ."enableMobileInfo:0,1 "
                ."wlanNeighborsPrefix "
                ."disableHostIPv4check:0,1 "
                ."disableDectInfo:0,1 "
                ."disableFonInfo:0,1 "
                ."enableSIP:0,1 "
                ."enableSmartHome:off,all,group,device "
                ."enableReadingsFilter:multiple-strict,"
                                ."dectID_alarmRingTone,dectID_custRingTone,dectID_device,dectID_fwVersion,dectID_intern,dectID_intRingTone,"
                                ."dectID_manufacturer,dectID_model,dectID_NoRingWithNightSetting,dectID_radio,dectID_NoRingTime,"
                                ."shdeviceID_battery,shdeviceID_category,shdeviceID_device,shdeviceID_firmwareVersion,shdeviceID_manufacturer,"
                                ."shdeviceID_model,shdeviceID_status,shdeviceID_tempOffset,shdeviceID_temperature,shdeviceID_type,"
                                ."shdeviceID_voltage,shdeviceID_power,shdeviceID_current,shdeviceID_consumtion,shdeviceSD_ledState,shdeviceSH_state "
                ."enableBoxReadings:multiple-strict,"
                                ."box_energyMode,box_globalFilter,box_led,box_vdsl,box_dns_Srv,box_pwr,box_guestWlan,box_usb,box_notify "
                ."enableLogReadings:multiple-strict,"
                                ."box_sys_Log,box_wlan_Log,box_fon_Log "
                ."disableBoxReadings:multiple-strict,"
                                ."box_connect,box_connection_Type,box_cpuTemp,box_dect,box_dns_Server,box_dsl_downStream,box_dsl_upStream,"
                                ."box_guestWlan,box_guestWlanCount,box_guestWlanRemain,"
                                ."box_ipv4_Extern,box_ipv6_Extern,box_ipv6_Prefix,box_last_connect_err,box_mac_Address,box_macFilter_active,"
                                ."box_moh,box_powerRate,box_rateDown,box_rateUp,box_stdDialPort,box_tr064,box_tr069,"
                                ."box_upnp,box_upnp_control_activated,box_uptime,box_uptimeConnect,box_wan_AccessType,"
                                ."box_wlan_Count,box_wlan_2.4GHz,box_wlan_5GHz,box_wlan_Active,box_wlan_LogExtended "
                ."deviceInfo:sortable,ipv4,name,uid,connection,speed,rssi,statIP,_noDefInf_ "
                ."disableTableFormat:multiple-strict,border(8),cellspacing(10),cellpadding(20) "
                ."FhemLog3Std:0,1 "
                ."lanDeviceReading:mac,ip "
                ."retMsgbySet:all,error,none "
                .$readingFnAttributes;

    $hash->{AttrRenameMap} = { "enableMobileModem" => "enableMobileInfo"
                             };


} # end FRITZBOX_Initialize

#######################################################################
sub FRITZBOX_detailFn {

   my ($FW_wname, $name, $room, $pageHash) = @_;

   my $hash = $defs{$name};
   my $csrf = ($FW_CSRF ? "&fwcsrf=$defs{$FW_wname}{CSRFTOKEN}" : '');

   my $csfr_Chg = "";

         # eventuell auch als Internal
         # $defs{$name}{link} = "<html><a href='$FW_ME?cmd=set $d reopen'>reopen</a></html>";

#   foreach (keys %{ $hash->{READINGS} }) {
#     if (defined $hash->{READINGS}{$_}{VAL} && $_ =~ /^box_notify_.*/ && $_ !~ /_info/ ) {
#       $csfr_Chg = $hash->{READINGS}{$_}{VAL};
#       if ($csfr_Chg =~ s/&fwcsrf=\d+' target/${csrf}' target/ ) {
#         readingsSingleUpdate($hash, $_, $csfr_Chg, 0);
#       } else {
#         FRITZBOX_Log $hash, 5, "box_notify: CSFR-Token not changed to $csrf in: \n" . $hash->{READINGS}{$_}{VAL};
#       }
#     }
#   }

   return undef;
}


#######################################################################
sub FRITZBOX_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   my $URL_MATCH = FRITZBOX_Helper_Url_Regex();

   if ($init_done) {

     return "FRITZBOX-define: define <name> FRITZBOX <IP address | DNS name>" if(@args != 3);

     delete $hash->{INFO_DEFINE} if $hash->{INFO_DEFINE};

   } else {

     $hash->{INFO_DEFINE} = "Please redefine Device: defmod <name> FRITZBOX <IP address | DNS name>" if @args == 2;

     delete $hash->{INFO_DEFINE} if $hash->{INFO_DEFINE} && @args == 3;

     return "FRITZBOX-define: define <name> FRITZBOX <IP address | DNS name>" if(@args < 2 || @args > 3);
   }

   return "FRITZBOX-define: no valid IPv4 Address or DNS name: $args[2]" if defined $args[2] && $args[2] !~ m=$URL_MATCH=i;

   my $name = $args[0];

   $hash->{NAME}    = $name;
   $hash->{VERSION} = $ModulVersion;

   # initialize DEGUB LOg function
   FRITZBOX_dbgLogInit($hash, "init", "verbose", AttrVal($name, "verbose", -1));
   # end initialize DEGUB LOg function

   # blocking variant !
   $URL_MATCH = FRITZBOX_Helper_Url_Regex(1);

   if (defined $args[2] && $args[2] !~ m=$URL_MATCH=i) {
     my $phost = inet_aton($args[2]);
     if (! defined($phost)) {
       FRITZBOX_Log $hash, 2, "phost -> not defined";
       return "FRITZBOX-define: DNS name $args[2] could not be resolved";
     }

     my $host = inet_ntoa($phost);

     if (! defined($host)) {
       FRITZBOX_Log $hash, 2, "host -> $host";
       return "FRITZBOX-define: DNS name could not be resolved";
     }
     $hash->{HOST} = $host;
   } else {
     $hash->{HOST} = $args[2];
   }

   $hash->{fhem}{definedHost} = $hash->{HOST}; # to cope with old attribute definitions

   my $msg;
# stop if certain perl moduls are missing
   if ( $missingModul ) {
      $msg = "ERROR: Cannot define a FRITZBOX device. Perl modul $missingModul is missing.";
      FRITZBOX_Log $hash, 1, $msg;
      $hash->{PERL} = $msg;
      return $msg;
   }

   readingsSingleUpdate( $hash, "state", "initializing", 1 );

   # INTERNALS
   $hash->{INTERVAL}              = 300;
   $hash->{TIMEOUT}               = 55;
   $hash->{SID_RENEW_ERR_CNT}     = 0;
   $hash->{SID_RENEW_CNT}         = 0;
   $hash->{STATUS}                = "active";

   $hash->{fhem}{LOCAL}           = 0;
   $hash->{fhem}{is_double_wlan}  = -1;
   $hash->{fhem}{fwVersion}       = 0;
   $hash->{fhem}{fwVersionStr}    = 0.0;

   $hash->{helper}{TimerReadout}  = $name . ".Readout";
   $hash->{helper}{TimerCmd}      = $name . ".Cmd";
   $hash->{helper}{FhemLog3Std}   = AttrVal($name, "FhemLog3Std", 0);
   $hash->{helper}{timerInActive} = 0;

   $hash->{fhem}{sidTime}     = 0;
   $hash->{fhem}{sidErrCount} = 0;
   $hash->{fhem}{sidNewCount} = 0;

   # $hash->{LuaQueryCmd} = \%LuaQueryCmd;
   foreach my $key (keys %LuaQueryCmd) {
     $hash->{LuaQueryCmd}{$key}{cmd}     = $LuaQueryCmd{$key}{cmd};
     $hash->{LuaQueryCmd}{$key}{active}  = 1;
     $hash->{LuaQueryCmd}{$key}{AttrVal} = 1;
   }

   # Check APIs after fhem.cfg is processed
   $hash->{APICHECKED} = 0;
   $hash->{WEBCONNECT} = 0;
   $hash->{LUAQUERY}   = -1;
   $hash->{LUADATA}    = -1;
   $hash->{TR064}      = -1;
   $hash->{UPNP}       = -1;
   
   CommandDeleteAttr(undef,"$hash m3uFileLocal -silent");
   CommandDeleteAttr(undef,"$hash m3uFileURL -silent");
   CommandDeleteAttr(undef,"$hash m3uFileActive -silent");

   FRITZBOX_Log $hash, 4, "start of Device readout parameters";
   RemoveInternalTimer($hash->{helper}{TimerReadout});
   InternalTimer(gettimeofday() + 1 , "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 0);

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

}  # end FRITZBOX_Delete 

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
   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

   if ($aName eq "verbose") {
     FRITZBOX_dbgLogInit($hash, $cmd, $aName, $aVal) if !$hash->{helper}{FhemLog3Std};
   }

   if($aName eq "FhemLog3Std") {
     if ($cmd eq "set") {
       return "FhemLog3Std: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
       $hash->{helper}{FhemLog3Std} = $aVal;
       if ($aVal) {
         FRITZBOX_dbgLogInit($hash, "del", "verbose", 0) if AttrVal($name, "verbose", 0) == 5;
       } else {
         FRITZBOX_dbgLogInit($hash, "set", "verbose", 5) if AttrVal($name, "verbose", 0) == 5 && $aVal == 0;
       }
     } else {
       $hash->{helper}{FhemLog3Std} = 0;
       FRITZBOX_dbgLogInit($hash, "set", "verbose", 5) if AttrVal($name, "verbose", 0) == 5;
     }
   }

   my $URL_MATCH = FRITZBOX_Helper_Url_Regex();

   if ($aName eq "setgetTimeout") {
     if ($cmd eq "set") {
       return "the set/get non BlockingCall timeout ($aVal sec) should be less than the INTERVAL timer ($hash->{INTERVAL} sec)" if $aVal > $hash->{INTERVAL};
     }
   }

   if ($aName eq "nonblockingTimeOut") {
     if ($cmd eq "set") {
       return "the non BlockingCall timeout ($aVal sec) should be less than the INTERVAL timer ($hash->{INTERVAL} sec)" if $aVal > $hash->{INTERVAL};
     }
   }

   if ($aName eq "INTERVAL") {
     if ($cmd eq "set") {
       return "the INTERVAL timer ($aVal sec) should be graeter than the non BlockingCall tiemout ($hash->{TIMEOUT} sec)" if $aVal < $hash->{TIMEOUT};
     }
   }

   if ($aName eq "userAgentTimeOut") {
     if ($cmd eq "set") {
       return "the userAgentTimeOut should be equal or graeter than 10 and equal or less than 200." if $aVal < 10 || $aVal > 200;
     }
   }

   if ($aName eq "reConnectInterval") {
     if ($cmd eq "set") {
       return "the reConnectInterval timer ($aVal sec) should be graeter than 10 sec." if $aVal < 55;
     }
   }

   if ($aName eq "maxSIDrenewErrCnt") {
     if ($cmd eq "set") {
       return "the maxSIDrenewErrCnt should be equal or graeter than 5 and equal or less than 20." if $aVal < 5 || $aVal > 20;
     }
   }

   if ($aName eq "deviceInfo") {
     if ($cmd eq "set") {
       my $count = () = ($aVal . ",") =~ m/_default_(.*?)\,/g;
       return "only one _default_... parameter possible" if $count > 1;
        
       return "character | not possible in _default_" if $aVal =~ m/\|/;
     }
   }

   if ($aName eq "retMsgbySet") {
     if ($cmd eq "set") {
       return "unknown parameter. Please use all,error or none" if $aVal !~ /all|error|none/;
     }
   }

#   if ($aName eq "enableReadingsFilter") {
#     my @reading_list = qw(box_led box_energyMode box_globalFilter box_vdsl");
#     if ($cmd eq "set") {
#       $aVal =~ s/\,/\|/g;
#       foreach ( @reading_list ) {
#         my $boxDel = $_;
#         if ( $boxDel !~ /${aVal}/  ) {
#           foreach (keys %{ $hash->{READINGS} }) {
#             readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
#           }
#         }
#       }
#     } 
#     if ($cmd eq "del") {
#       foreach ( @reading_list ) {
#         my $boxDel = $_;
#         foreach (keys %{ $hash->{READINGS} }) {
#           readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
#         }
#       }
#     } 
#   }

   if ($aName eq "enableBoxReadings") {
     my @reading_list = qw(box_led box_energyMode box_globalFilter box_vdsl box_dns_Srv box_pwr box_guestWlan box_usb box_notify);
     if ($cmd eq "set" && $init_done) {
       if ( ("box_dns_Srv" =~ /$aVal/) && $hash->{fhem}{fwVersion} <= 731 ) {
         return "box_dns_Srv not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_led" =~ /$aVal/) && ($hash->{fhem}{fwVersion} < 680) ) {
         return "box_led not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_energyMode" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 721 ) {
         return "box_energyMode not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_globalFilter" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 721 ) {
         return "box_globalFilter not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_vdsl" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 680 ) {
         return "box_vdsl not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_pwr" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 700 ) {
         return "box_pwr not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_pwr" =~ /$aVal/) && $hash->{fhem}{fwVersion} >= 790 && $avmModel =~ /Cable/) {
         return "box_pwr not available for FiritzBox Cable with Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_guestWlan" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 700 ) {
         return "box_guestWlan not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_usb" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 700 ) {
         return "box_usb not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }
       if ( ("box_notify" =~ /$aVal/) && $hash->{fhem}{fwVersion} < 700 ) {
         return "box_notify not available for Fritz!OS: $hash->{fhem}{fwVersionStr}";
       }

       $aVal =~ s/\,/\|/g;
       foreach ( @reading_list ) {
         my $boxDel = $_;
         if ( $boxDel !~ /${aVal}/  ) {
           foreach (keys %{ $hash->{READINGS} }) {
             readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
           }
           readingsDelete($hash, "box_powerLine") if $_ =~ /box_guestWlan/ && defined $hash->{READINGS}{box_powerLine}{VAL};
         }
       }
     } 
     if ($cmd eq "del") {
       foreach ( @reading_list ) {
         my $boxDel = $_;
         foreach (keys %{ $hash->{READINGS} }) {
           readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
         }
       }
       readingsDelete($hash, "box_powerLine") if defined $hash->{READINGS}{box_powerLine}{VAL};
     } 
     delete $hash->{helper}{infoActive} if(exists $hash->{helper}{infoActive});
   }

   if ($aName eq "enableLogReadings") {
     my @reading_list = qw(box_sys_Log box_wlan_Log box_fon_Log);
     if ($cmd eq "set") {
       $aVal =~ s/\,/\|/g;
       foreach ( @reading_list ) {
         my $boxDel = $_;
         if ( $boxDel !~ /${aVal}/  ) {
           foreach (keys %{ $hash->{READINGS} }) {
             readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
           }
         }
       }
     } 
     if ($cmd eq "del") {
         my $boxDel = $_;
         if ( $boxDel !~ /${aVal}/  ) {
         foreach (keys %{ $hash->{READINGS} }) {
           readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
         }
       }
     } 
   }

   if ($aName eq "disableBoxReadings") {
     if ($cmd eq "set") {
       my @reading_list = split(/\,/, $aVal);
       foreach ( @reading_list ) {
         if ($_ =~ m/box_dns_Server/) {
           my $boxDel = $_;
           foreach (keys %{ $hash->{READINGS} }) {
             readingsDelete($hash, $_) if $_ =~ /^${boxDel}.*/ && defined $hash->{READINGS}{$_}{VAL};
           }
         } else {
           readingsDelete($hash, $_) if exists $hash->{READINGS}{$_};
         }
       }
     } 
   }

   if ($aName eq "enablePhoneBookInfo") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^fon_phoneBook_.*?/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enablePassivLanDevices") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^mac_pas_/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableKidProfiles") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^kidprofile(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableVPNShares") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
       $hash->{LuaQueryCmd}{vpn_info}{AttrVal} = $aVal;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^vpn(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableSIP") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^sip[(\d+)_|_]/ && defined $hash->{READINGS}{$_}{VAL};
       }
       readingsDelete($hash, "sip_error");
     }
   }

   if ($aName eq "enableUserInfo") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
       $hash->{LuaQueryCmd}{userProfil}{AttrVal} = $aVal;
       $hash->{LuaQueryCmd}{userProfilNew}{AttrVal} = $aVal;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^user(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableAlarmInfo") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
       $hash->{LuaQueryCmd}{alarmClock}{AttrVal} = $aVal;
     }
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
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 0) {
       my $nbhPrefix = AttrVal( $name, "wlanNeighborsPrefix",  "nbh_" );
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^${nbhPrefix}.*/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableSmartHome") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is off,all,group or device" if $aVal !~ /off|all|group|device/;
      
       if ($aVal !~ /all|group/) {
         foreach (keys %{ $hash->{READINGS} }) {
           readingsDelete($hash, $_) if $_ =~ /^shgroup.*/ && defined $hash->{READINGS}{$_}{VAL};
         }
       }

       if ($aVal !~ /all|device/) {
         foreach (keys %{ $hash->{READINGS} }) {
           readingsDelete($hash, $_) if $_ =~ /^shdevice.*/ && defined $hash->{READINGS}{$_}{VAL};
         }
       }
     }
     if ($cmd eq "del" || $aVal eq "off") {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^shgroup.*/ && defined $hash->{READINGS}{$_}{VAL};
         readingsDelete($hash, $_) if $_ =~ /^shdevice.*/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "enableMobileInfo") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 0) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^usbMobile[(\d+)_.*|_.*]/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }

     if ($cmd eq "set" && $hash->{APICHECKED} == 1) {
        return "only available for Fritz!OS equal or greater than 7.50" if $hash->{fhem}{fwVersion} < 750;
     }
   }

   if ($aName eq "disableDectInfo") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
     }
     if ($cmd eq "del" || $aVal == 1) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^dect(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "disableFonInfo") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is 0 or 1." if $aVal !~ /[0-1]/;
       $hash->{LuaQueryCmd}{fonPort}{AttrVal} = $aVal;
     }
     if ($cmd eq "del" || $aVal == 1) {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^fon(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   if ($aName eq "lanDeviceReading") {
     if ($cmd eq "set") {
       return "$aName: $aVal. Valid is mac or ip." if $aVal !~ /mac|ip/;
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^mac_|ip_/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
     if ($cmd eq "del" || $aVal eq "mac") {
       foreach (keys %{ $hash->{READINGS} }) {
         readingsDelete($hash, $_) if $_ =~ /^ip_/ && defined $hash->{READINGS}{$_}{VAL};
       }
     }
   }

   # Stop the sub if FHEM is not initialized yet
   unless ($init_done) {
     FRITZBOX_Log $hash, 4, "Attr $cmd $aName -> no action while init running";
     return undef;
   }

   if ( ( $hash->{APICHECKED} == 1) || $aName =~ /disable|INTERVAL|nonblockingTimeOut/ ) {
      FRITZBOX_Log $hash, 3, "Attr $cmd $aName -> Neustart internal Timer - APICHECKED = $hash->{APICHECKED}";
      $hash->{APICHECKED} = 0;
      $hash->{WEBCONNECT} = 0;
      $hash->{fhem}{LOCAL} = 1;
      FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL} = 0;
      # InternalTimer(gettimeofday()+1, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 1);
      # FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
   }

   return undef;
} # end FRITZBOX_Attr

#######################################################################
# retMsgbySet:all,error,none
#
sub FRITZBOX_Helper_retMsg($$;@) {
   my ($hash, $retMsg, $retType, $verbose) = @_;

   $retType ||= "all";
   $verbose ||= 4;

   $verbose = 2 if $retMsg =~ /ERROR/;

   FRITZBOX_Log $hash, $verbose, $retMsg;

   if ($retType eq "all") {
     return $retMsg;
   } elsif ($retType eq "error" && $retMsg =~ /ERROR/) {
     return $retMsg;
   } else {
     return undef;
   }

   return undef;

}

#######################################################################
sub FRITZBOX_Set($$@)
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";
   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   my $retMsgbySet = AttrVal($name, "retMsgbySet", "all");
   my $retMsg = "";

   my $list =  " checkAPIs:noArg"
            .  " password"
            .  " update:noArg"
            .  " inActive:on,off";

   FRITZBOX_Log $hash, 3, "set $name $cmd - " . join(" ", @val) if $val[0] && $cmd ne 'password' && $val[0] ne "?";

   if ( lc $cmd eq 'checkapis') {

      $hash->{APICHECKED}         = 0;
      $hash->{WEBCONNECT}         = 0;
      $hash->{APICHECK_RET_CODES} = "-";
      $hash->{fhem}{sidTime}      = 0;
      $hash->{fhem}{sidErrCount}  = 0;
      $hash->{fhem}{sidNewCount}  = 0;
      $hash->{fhem}{LOCAL}        = 1;
      $hash->{SID_RENEW_ERR_CNT}  = 0;
      $hash->{SID_RENEW_CNT}      = 0;

      $retMsg = "set <name> checkAPIs: " . FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL}        = 0;
      return FRITZBOX_Helper_retMsg($hash, $retMsg, "error");

   } # end checkapis

   # set password
   elsif ( lc $cmd eq 'password') {

      if (int @val == 1)
      {
         $retMsg = FRITZBOX_Helper_store_Password ( $hash, $val[0] );
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $retMsg =~ /ERROR/;

         my $result = FRITZBOX_open_Web_Connection( $hash );

         if (defined $result->{Error}) {
           $hash->{fhem}{sidErrCount} += 1;
           $hash->{fhem}{sidTime} = 0;
           $hash->{WEBCONNECT} = 0;
           $retMsg = "ERROR: " . $result->{Error};
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         } else {
           $hash->{fhem}{sid} = $result->{sid};
           $hash->{fhem}{sidNewCount} = defined $result->{sidNew} ? $result->{sidNew} : 0;
           $hash->{fhem}{sidTime} = time();
           $hash->{fhem}{sidErrCount} = 0;
           $hash->{WEBCONNECT} = 1;
         }

         $hash->{fhem}{LOCAL} = 1;
         $retMsg = FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
         $hash->{fhem}{LOCAL} = 0;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, "error");

      } else {
         $retMsg = "ERROR: please give a password as one parameter.";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, "error");
      }

   } # end password

   elsif ( lc $cmd eq 'update' ) {

      $hash->{fhem}{LOCAL} = 1;
      $retMsg = FRITZBOX_Readout_Start($hash->{helper}{TimerReadout});
      $hash->{fhem}{LOCAL} = 0;
      return FRITZBOX_Helper_retMsg($hash, $retMsg, "error");

   } # end update

   elsif ( lc $cmd eq 'inactive') {
      if ( (int @val != 1) || ($val[0] !~ /on|off/) ) {
        $retMsg = "ERROR: arguments not valid. Required on|off.";
        return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
      }

      if ($val[0] eq "on") {
        $hash->{helper}{timerInActive} = 1;
        readingsSingleUpdate( $hash, "state", "inactiv", 1 );
        $hash->{STATUS}     = "inactive";
      } else {
        $hash->{helper}{timerInActive} = 0;
        FRITZBOX_Log $hash, 4, "set $name $cmd -> Neustart internal Timer";
        $hash->{APICHECKED} = 0;
        $hash->{WEBCONNECT} = 0;
        $hash->{STATUS}     = "active";
        RemoveInternalTimer($hash->{helper}{TimerReadout});
        InternalTimer(gettimeofday()+1, "FRITZBOX_Readout_Start", $hash->{helper}{TimerReadout}, 1);
      }

      $retMsg = "set $name $cmd " . join(" ", @val);
      FRITZBOX_Log $hash, 3, $retMsg;
      return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

   } #end inactive


   # available, if password is set correctly
   if ($hash->{WEBCONNECT}) {
     # set abhängig von TR064
     $list    .= " reboot"
              if $hash->{TR064} == 1 && $hash->{SECPORT};

     $list    .= " call"
              .  " diversity"
              .  " ring"
              .  " tam"
              if $hash->{TR064} == 1 && $hash->{SECPORT} && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $mesh eq "master";

     # set abhängig von TR064 und luaCall
     $list    .= " wlan:on,off"
              .  " guestWlan:on,off"
              if $hash->{TR064} == 1 && $hash->{SECPORT} && $hash->{LUAQUERY} == 1;

     $list    .= " wlan2.4:on,off"
              .  " wlan5:on,off"
              if $hash->{fhem}{is_double_wlan} == 1 && $hash->{TR064} == 1 && $hash->{SECPORT} && $hash->{LUAQUERY} == 1;

     # set abhängig von TR064 und data.lua
     $list    .= " macFilter:on,off"
              if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $hash->{TR064} == 1 && $hash->{SECPORT}  && $mesh eq "master";

     $list    .= " enableVPNshare"
              if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $hash->{TR064} == 1 && $hash->{SECPORT}  && $mesh eq "master" && ($hash->{fhem}{fwVersion} >= 721);

     $list    .= " phoneBookEntry"
              if defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $hash->{TR064} == 1 && $hash->{SECPORT};


     # set abhängig von data.lua
     $list    .= " switchIPv4DNS:provider,other"
              .  " dect:on,off"
              .  " lockLandevice"
              .  " chgProfile"
              .  " lockFilterProfile"
              if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $mesh eq "master";

     $list    .= " wakeUpCall"
              .  " dectRingblock"
              .  " blockIncomingPhoneCall"
              .  " smartHome"
              if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && ($hash->{fhem}{fwVersion} >= 721);

     $list    .= " ledSetting"
              if ($hash->{LUADATA} == 1) && ($hash->{fhem}{fwVersion} >= 721);

     $list    .= " energyMode:default,eco"
              if ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && ($hash->{fhem}{fwVersion} >= 750);

     $list    .= " rescanWLANneighbors:noArg"
              .  " wlanLogExtended:on,off"
              .  " wlanGuestParams"
              if ($hash->{LUADATA} == 1);

     if ( lc $cmd eq 'smarthome') {

       $retMsg = "ERROR: required <deviceID> <tempOffset:value> | <tmpAdjust:value> | <tmpPerm:0|1> | <switch:0|1> | <automatic:0|1>  | <preDefSave:name> | <preDefDel:name>| <preDefLoad[:deviceID]:name[:A|:G]";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if (int @val < 1 || int @val > 2);

       $retMsg = "ERROR: required numeric value for first parameter: $val[0]";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if ($val[0] =~ /\D/ && int @val == 2);

       my $newValue     = undef;
       my $action       = "";
       my $preDefName   = "";
       my $preDefWeb    = "all";
       my $preDefDevice = "";
       my $preDefResA   = "no";
       my $preDefResG   = "no";
       my @webCmdArray;

       if (int @val == 2) {

         if( $val[1] !~ /^tempOffset:-?\d+(\.[05])?$|^tmpAdjust:([8-9]|1[0-9]|2[2-8])(\.[05])?$
                                                  |^tmpPerm:[01]$|^switch:[01]$|^automatic:[01]$
                                                  |^preDefSave:[-\w]+$|^preDefDel:[-\w]+$||^preDefLoad:[-\w]+(:A|:G)?$|^preDefLoad:[\d]+:[-\w]+(:A|:G)?$/ ) {

           $retMsg = "ERROR: second parameter not valid. Value steps 0.5: <tempOffset:value>"
                                   . " or <tmpAdjust:[8..28]>" 
                                   . " or <tmpPerm:0|1>"
                                   . " or <switch:0|1>"
                                   . " or <automatic:0|1>"
                                   . " or <preDefSave:name>"
                                   . " or <preDefDel:name>"
                                   . " or <preDefLoad:[id:]name[:A|:G]>";

           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) ;
         }

         $preDefDevice = $val[0];

         if ($val[1] =~ /^tempOffset:(-?\d+(\.[05])?)$/ ) {
           $newValue = $1;
         } elsif ( $val[1] =~ /^tmpAdjust:(([8-9]|1[0-9]|2[2-8])(\.[05])?)$/ ) {
           $newValue = $1;
         } elsif ( $val[1] =~ /^tmpPerm:([01])$/ ) {
           $newValue = "ALWAYS_ON"  if $1 == 1;
           $newValue = "ALWAYS_OFF" if $1 == 0;
         } elsif ( $val[1] =~ /^switch:([01])$/ ) {
           $newValue = "ON"  if $1 == 1;
           $newValue = "OFF" if $1 == 0;
         } elsif ( $val[1] =~ /^automatic:([01])$/ ) {
           $newValue = "ON"  if $1 == 1;
           $newValue = "OFF" if $1 == 0;
         } elsif ( $val[1] =~ /^preDefSave:([-\w]+)$/ ) {
           $preDefName = $1;
         } elsif ( $val[1] =~ /^preDefDel:([-\w]+)$/ ) {
           $preDefName = $1;
         } elsif ( $val[1] =~ /^preDefLoad:([-\w]+)(:A|:G)?$/ ) {
           $preDefName = $1;
           $preDefWeb  = $2 if $2;
         } elsif ( $val[1] =~ /^preDefLoad:([\d]+):([-\w]+)(:A|:G)?$/ ) {
           $preDefDevice = $1;
           $preDefName   = $2;
           $preDefWeb    = $3 if $3;
         }

         $preDefWeb =~ s/\://gs;

         # return "$val[0] : $preDefDevice : $preDefName : $preDefWeb";

         $retMsg = "ERROR: no valid second Paramter: $preDefName : $preDefWeb";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if !defined $newValue && $preDefName eq "";

         ($action) = ($val[1] =~ /(.*?):.*?/) if $action eq "";

       } else {
         $action     = "preDefShow";
         $preDefName = "__List__All";
       }

       my $returnData;

       if ($action =~ /preDefLoad/ ) {

         my $retDataVgl;

         $returnData = FRITZBOX_Get_SmartHome_Devices_List($hash, $preDefDevice, "load", $preDefName);

         if ($returnData->{Error}) {
           $retMsg = "ERROR: " . $returnData->{Error} . " " . $returnData->{Info};
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         FRITZBOX_Log $hash, 5, "SmartHome Device preDefLoad-> \n" . Dumper($returnData);

         if ($val[0] ne $preDefDevice) {
           $retDataVgl = FRITZBOX_Get_SmartHome_Devices_List($hash, $val[0], "load", $preDefName);

           if ($retDataVgl->{Error}) {
             $retMsg = "ERROR: " . $retDataVgl->{Error} . " " . $retDataVgl->{Info};
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

           FRITZBOX_Log $hash, 5, "SmartHome Device preDefLoad-> \n" . Dumper($retDataVgl);

           unless ($returnData->{device_name_category} && $retDataVgl->{device_name_category} && $returnData->{device_name_category} eq $retDataVgl->{device_name_category}) {
             $retMsg = "ERROR: category device:" . $retDataVgl->{device} . " not equal to category device:" . $returnData->{device};
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

         }

         if ($returnData->{device_name_category} && $returnData->{device_name_category} eq "SOCKET") {

           if ($preDefWeb ne "A") {
             my $returnDataG = FRITZBOX_Get_SmartHome_Devices_List($hash, $preDefDevice, "loads", $preDefName);
             delete $returnDataG->{device_name_category} if exists $returnDataG->{device_name_category};
             delete $returnDataG->{device_web_site}      if exists $returnDataG->{device_web_site};
                    $returnDataG->{device}               = $val[0];
                    $returnDataG->{ule_device_name}      = encode("ISO-8859-1", $returnDataG->{ule_device_name});

             @webCmdArray = %$returnDataG;

             push @webCmdArray, "xhr"            => "1";
             push @webCmdArray, "view"           => "";
             push @webCmdArray, "apply"          => "";
             push @webCmdArray, "lang"           => "de";
             push @webCmdArray, "page"           => "home_auto_edit_view";

             FRITZBOX_Log $hash, 4, "set $name $cmd \n" . join(" ", @webCmdArray);

             my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);

             my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

             FRITZBOX_Log $hash, 4, "SmartHome Device " . $val[0] . " - " . $analyse;

             if ( $analyse =~ /ERROR/) {
               FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . $analyse;
               return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet);
             }

             if (defined $result->{data}->{apply}) {
               if ($result->{data}->{apply} eq "ok") {
                 readingsSingleUpdate($hash,"retStat_smartHome","ID:$val[0] - preDef loaded with name $preDefName $preDefWeb", 1);
                 $retMsg = "ID:$val[0] - preDef loaded with name $preDefName - $preDefWeb";
                 return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $preDefWeb eq "G";
               } else {
                 FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . Dumper($result);
                 readingsSingleUpdate($hash,"retStat_smartHome","failed: ID:$val[0] - preDef not loaded with name $preDefName $preDefWeb", 1);
                 $retMsg = "ERROR: ID:$val[0] - preDef not loaded with name $preDefName $preDefWeb";
                 return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
               }
             }
           }

           if ($preDefWeb ne "G") {
             delete $returnData->{device_name_category} if exists $returnData->{device_name_category};
             delete $returnData->{device_web_site}      if exists $returnData->{device_web_site};
                    $returnData->{device}               = $val[0];

             @webCmdArray = %$returnData;

             push @webCmdArray, "xhr"            => "1";
             push @webCmdArray, "view"           => "";
             push @webCmdArray, "apply"          => "";
             push @webCmdArray, "lang"           => "de";
             push @webCmdArray, "page"           => "home_auto_timer_view";
           }


         } elsif ($returnData->{device_name_category} && $returnData->{device_name_category} eq "THERMOSTAT") {

           delete $returnData->{device_name_category} if exists $returnData->{device_name_category};
           delete $returnData->{device_web_site}      if exists $returnData->{device_web_site};
                  $returnData->{device}               = $val[0];
                  $returnData->{ule_device_name}      = encode("ISO-8859-1", $returnData->{ule_device_name});

           @webCmdArray = %$returnData;

           push @webCmdArray, "xhr"            => "1";
           push @webCmdArray, "view"           => "";
           push @webCmdArray, "apply"          => "";
           push @webCmdArray, "lang"           => "de";
           push @webCmdArray, "page"           => "home_auto_hkr_edit";

         } else {

           readingsSingleUpdate($hash,"retStat_smartHome","ERROR: ID:$val[0] - preDef loading not possible for $preDefName", 1);
           $retMsg = "ERROR: ID:$val[0] - preDef loading not possible for $preDefName";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

         }

         FRITZBOX_Log $hash, 4, "set $name $cmd \n" . join(" ", @webCmdArray);

         my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);

         my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

         FRITZBOX_Log $hash, 4, "SmartHome Device " . $val[0] . " - " . $analyse;

         if ( $analyse =~ /ERROR/) {
           FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . $analyse;
           return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet);
         }

         if (defined $result->{data}->{apply}) {
           if ($result->{data}->{apply} eq "ok") {
             readingsSingleUpdate($hash,"retStat_smartHome","ID:$val[0] - preDef loaded with name $preDefName $preDefWeb", 1);
             $retMsg = "ID:$val[0] - preDef loaded with name $preDefName $preDefWeb";
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           } else {
             FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . Dumper($result);
             readingsSingleUpdate($hash,"retStat_smartHome","failed: ID:$val[0] - preDef not loaded with name $preDefName $preDefWeb", 1);
             $retMsg = "ERROR: ID:$val[0] - preDef not loaded with name $preDefName $preDefWeb";
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }
         }

         FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . Dumper($result);
         readingsSingleUpdate($hash,"retStat_smartHome","failed: ID:$val[0] - unexpected result", 1);
         $retMsg = "ERROR: Unexpected result: " . Dumper ($result);
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } elsif ($action =~ /preDefSave/ ) {

         $returnData = FRITZBOX_Get_SmartHome_Devices_List($hash, $preDefDevice, "save", $preDefName);

         if ($returnData->{Error}) {
           $retMsg = "ERROR: " . $returnData->{Error} . " " . $returnData->{Info};
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $returnData->{Error};
         }

         FRITZBOX_Log $hash, 4, "SmartHome Device preDefSave-> \n" . Dumper($returnData);

         readingsSingleUpdate($hash,"retStat_smartHome","ID:$val[0] - preDef saved with name $preDefName", 1);
         $retMsg = "ID:$val[0] - preDef saved with name $preDefName";

         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } elsif ($action =~ /preDefDel/ ) {

         $returnData = FRITZBOX_Get_SmartHome_Devices_List($hash, $preDefDevice, "delete", $preDefName);

         if ($returnData->{Error}) {
           $retMsg = "ERROR: " . $returnData->{Error} . " " . $returnData->{Info};
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $returnData->{Error};
         }

         FRITZBOX_Log $hash, 4, "SmartHome Device preDefDel-> \n" . Dumper($returnData);

         readingsSingleUpdate($hash,"retStat_smartHome","ID:$val[0] - preDef deleted with name $preDefName", 1);
         $retMsg = "ID:$val[0] - preDef deleted with name $preDefName";

         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } elsif ($action =~ /tmpAdjust|tmpPerm|switch/ ) {

         push @webCmdArray, "page" => "sh_control";

         if ($action =~ /switch/ ) {
           push @webCmdArray, "saveState[id]"    => $val[0];
           push @webCmdArray, "saveState[state]" => $newValue;
         } else {
           push @webCmdArray, "saveTemperature[id]"          => $val[0];
           push @webCmdArray, "saveTemperature[temperature]" => $newValue;
         }

         FRITZBOX_Log $hash, 3, "set $name $cmd \n" . join(" ", @webCmdArray);

         my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);

         my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

         if ( $analyse =~ /ERROR/) {
           FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . $analyse;
           return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet) if $analyse =~ /ERROR/;
         }

         if($result->{data}->{done}) {
           if ($result->{data}->{done}) {

             my $msg = "ID:$val[0] - $newValue";
                $msg .= " - set adjustment to " . $result->{data}->{mode} if $result->{data}->{mode};
                $msg .= ": " . $result->{data}->{temperature} if $result->{data}->{temperature};

             readingsSingleUpdate($hash, "retStat_smartHome", $msg, 1);
             readingsSingleUpdate($hash, "shdevice" . $val[0] . "_state", $newValue, 1) if $action =~ /switch/;
             readingsSingleUpdate($hash, "shdevice" . $val[0] . "_tempOffset", $newValue, 1) if $action =~ /tmpAdjust|tmpPerm/;

             return FRITZBOX_Helper_retMsg($hash, $msg, $retMsgbySet);

           } else {

             my $msg = "failed - ID:$val[0] - $newValue";
                $msg .= " - set adjustment to " . $result->{data}->{mode} if $result->{data}->{mode};
                $msg .= ": " . $result->{data}->{temperature} if $result->{data}->{temperature};

             readingsSingleUpdate($hash, "retStat_smartHome", $msg, 1);

             return FRITZBOX_Helper_retMsg($hash, $msg, $retMsgbySet);

           }
         }

         $retMsg = "ERROR: Unexpected result: " . Dumper ($result);
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } elsif ($action eq "tempOffset") {

         $returnData->{ule_device_name} = encode("ISO-8859-1", $returnData->{ule_device_name});
         $returnData->{Offset} = $newValue;

         @webCmdArray = %$returnData;

         push @webCmdArray, "xhr"            => "1";
         push @webCmdArray, "view"           => "";
         push @webCmdArray, "apply"          => "";
         push @webCmdArray, "lang"           => "de";
         push @webCmdArray, "page"           => "home_auto_hkr_edit";

         FRITZBOX_Log $hash, 3, "set $name $cmd \n" . join(" ", @webCmdArray);

         my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);
         
         my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

         if ( $analyse =~ /ERROR/) {
           FRITZBOX_Log $hash, 2, "SmartHome Device " . $val[0] . " - " . $analyse;
           return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet) if $analyse =~ /ERROR/;
         }

         if (defined $result->{data}->{apply}) {
           if ($result->{data}->{apply} eq "ok") {
             readingsSingleUpdate($hash,"retStat_smartHome","ID:$val[0] - set offset to:$newValue", 1);
             $retMsg = "ID:$val[0] - set offset to:$newValue";
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           } else {
             readingsSingleUpdate($hash,"retStat_smartHome","failed: ID:$val[0] - set offset to:$newValue", 1);
             $retMsg = "ERROR: ID:$val[0] - set offset to:$newValue";
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }
         }

         $retMsg = "ERROR: Unexpected result: " . Dumper ($result);
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       return undef;

     } #end smarthome

     elsif ( lc $cmd eq 'call' && $mesh eq "master") {
       
       $retMsg = "ERROR: At least one parameter must be defined.";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) unless int @val;

       $retMsg = "ERROR: Parameter '$val[0]' not a valid phone number.";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) unless $val[0] =~ /^[\d\*\#+,]+$/;

       if (int @val >= 0 && int @val <= 2) {
         push @cmdBuffer, "call " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start $hash->{helper}{TimerCmd};
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }         
     } # end call

     elsif ( (lc $cmd eq 'blockincomingphonecall') && ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && ($hash->{fhem}{fwVersion} >= 721) ) {

       # set <name> blockIncomingPhoneCall <new> <name> <number> <home|work|mobile|fax_work>
       # set <name> blockIncomingPhoneCall <new> <name> <number> <home|work|mobile|fax_work> <yyyy-mm-ddThh:mm:ss>
       # set <name> blockIncomingPhoneCall <chg> <name> <number> <home|work|mobile|fax_work> <uid>
       # set <name> blockIncomingPhoneCall <del> <name> <uid>

       $retMsg = "";
       $retMsg = "new, tmp, chg or del as first parameter needed" if int @val == 0;

       $retMsg = "chg not implemented" if $val[0] eq "chg";

       $retMsg = "new, tmp, chg or del at first parameter: $val[0]" if $val[0] !~ /^(new|tmp|chg|del)$/;

       $retMsg = "wrong amount of parameters for: del" if $val[0] eq "del" && int @val != 2;
       $retMsg = "wrong amount of parameters for: new" if $val[0] eq "new" && int @val != 4;
       $retMsg = "wrong amount of parameters for: chg" if $val[0] eq "chg" && int @val != 5;
       $retMsg = "wrong amount of parameters for: new" if $val[0] eq "tmp" && int @val != 5;
       $retMsg = "home, work, mobile or fax_work at fourth parameter: $val[3]" if $val[0] =~ /^(new|chg)$/ && $val[3] !~ /^(home|work|mobile|fax_work)$/;
       $retMsg = "wrong phone number format: $val[2]" if $val[0] =~ /^(new|tmp|chg)$/ && $val[2] !~ /^[\d\*\#+,]+$/;

       if ($val[0] eq "tmp") {
         if ( $val[4] =~ m!^((?:19|20)\d\d)[- /.](0[1-9]|1[012])[- /.](0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3])[/:.]([0-5][0-9])[/:.]([0-5][0-9])$!) {
           # At this point, $1 holds the year, $2 the month and $3 the day,
           # $4 the hours, $5 the minutes and $6 the seconds of the date/time entered
           if ($3 == 31 and ($2 == 4 or $2 == 6 or $2 == 9 or $2 == 11))
           {
             $retMsg = "wrong at date/time format: 31st of a month with 30 days";
           } elsif ($3 >= 30 and $2 == 2) {
             $retMsg = "wrong at date/time format: February 30th or 31st";
           } elsif ($2 == 2 and $3 == 29 and not ($1 % 4 == 0 and ($1 % 100 != 0 or $1 % 400 == 0))) {
             $retMsg = "wrong at date/time format: February 29th outside a leap year";
           } else {
   #          $retMsg = "Valid date/time";
           }
         } else {
           $retMsg = "wrong at date/time format: No valid date/time $val[4]";
         }
       }

       return FRITZBOX_Helper_retMsg($hash, "ERROR: set blockIncomingPhoneCall " . $retMsg, $retMsgbySet) if $retMsg ne "";

       push @cmdBuffer, "blockincomingphonecall " . join(" ", @val);
       $retMsg = FRITZBOX_Readout_SetGet_Start $hash->{helper}{TimerCmd};

       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

     } # end blockincomingphonecall

     elsif ( lc $cmd eq 'chgprofile' && $mesh eq "master") {

       if(int @val == 2) {

         $val[1] = "filtprof" . $val[1] unless $val[0] =~ /^filtprof(\d+)$/;

         $val[0] = FRITZBOX_SetGet_Proof_Params($hash, $name, $cmd, "^filtprof(\\d+)\$", @val);

         return FRITZBOX_Helper_retMsg($hash, $val[0], $retMsgbySet) if($val[0] =~ /ERROR/);

         push @cmdBuffer, "chgprofile " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start $hash->{helper}{TimerCmd};
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } else {
         FRITZBOX_Log $hash, 2, "for chgprofile arguments";
         $retMsg = "ERROR: set chgprofile arguments";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }
     } # end chgprofile

     elsif ( lc $cmd eq 'dect' && $mesh eq "master") {
       if (int @val == 1 && $val[0] =~ /^(on|off)$/) {

         if ($hash->{LUADATA}==1) {
           # xhr 1 activateDect off apply nop lang de page dectSet

           my @webCmdArray;
           my $returnStr;

           push @webCmdArray, "xhr"            => "1";
           push @webCmdArray, "activateDect"   => $val[0];
           push @webCmdArray, "apply"          => "";
           push @webCmdArray, "lang"           => "de";
           push @webCmdArray, "page"           => "dectSet";

           FRITZBOX_Log $hash, 4, "set $name $cmd \n" . join(" ", @webCmdArray);

           my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);
           
           my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
           if ( $analyse =~ /ERROR/) {
             $retMsg = "dect enabled " . $val[0] . " - " . $analyse;
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

           if (defined $result->{data}->{vars}->{dectEnabled}) {
             readingsSingleUpdate($hash,"box_dect",$val[0], 1);
             $retMsg = $result->{data}->{vars}->{dectEnabled} ? "DECT aktiv" : "DECT inaktiv";
             return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet);
           }

           FRITZBOX_Helper_retMsg($hash, "ERROR: Unexpected result: " . Dumper ($result), $retMsgbySet);

         }

         FRITZBOX_Helper_retMsg($hash, "ERROR: data.lua not available", $retMsgbySet);
       }
     } # end dect

     elsif ( lc $cmd eq 'dectringblock' && $mesh eq "master" && $hash->{fhem}{fwVersion} >= 721) {

       if ($hash->{fhem}{fwVersion} < 721) {
         FRITZBOX_Helper_retMsg($hash, "ERROR: FritzOS version must be greater than 7.20.", $retMsgbySet);
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
         return FRITZBOX_Helper_retMsg($hash, "ERROR: for dectringblock arguments", $retMsgbySet);
       }

       if (ReadingsVal($name, $val[0], "nodect") eq "nodect") {
         return FRITZBOX_Helper_retMsg($hash, "ERROR: dectringblock $val[0] not found.", $retMsgbySet);
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

       FRITZBOX_Log $hash, 4, "set $name $cmd \n" . join(" ", @webCmdArray);

       my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
       if ( $analyse =~ /ERROR/) {
         return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet);
       }

       if (defined $result->{data}->{apply}) {
         return FRITZBOX_Helper_retMsg($hash, $result->{data}->{apply}, $retMsgbySet);
       }

       return FRITZBOX_Helper_retMsg($hash, "ERROR: Unexpected result: " . Dumper ($result), $retMsgbySet);

     } # end dectringblock

     elsif ( lc $cmd eq 'diversity' && $mesh eq "master") {
       if ( int @val == 2 && $val[1] =~ /^(on|off)$/ ) {

         unless (defined $hash->{READINGS}{"diversity".$val[0]}) {
           return FRITZBOX_Helper_retMsg($hash, "ERROR: no diversity".$val[0]." to set.", $retMsgbySet);
         }

         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;

         if ( $hash->{TR064}==1 ) { #tr064
           my @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "SetDeflectionEnable", "NewDeflectionId", $val[0] - 1, "NewEnable", $state] );
           FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);
         }
         else {
           FRITZBOX_Log $hash, 2, "'set ... diversity' is not supported by the limited interfaces of your Fritz!Box firmware.";
           return "ERROR: 'set ... diversity' is not supported by the limited interfaces of your Fritz!Box firmware.";
         }
         readingsSingleUpdate($hash, "diversity".$val[0]."_state", $val[1], 1);
         return undef;
       }
     } # end diversity

     elsif ( lc $cmd eq 'energymode') {
       if ( $hash->{TR064} != 1 || ($hash->{fhem}{fwVersion} < 750) ) { #tr064
         return FRITZBOX_Helper_retMsg($hash, "ERROR: 'set ... energyMode' is not supported by the limited interfaces of your Fritz!Box firmware.", $retMsgbySet);
       } elsif ($val[0] !~ /default|eco/ || int @val != 1) {
         return FRITZBOX_Helper_retMsg($hash, "ERROR: parameter not ok: $val[0]. Requested default or eco.", $retMsgbySet);
       }

       my @webCmdArray;
       my $resultData;
       my $timerWLAN     = "";
       my $startWLANoffH = "";
       my $startWLANoffM = "";
       my $endWLANoffH   = "";
       my $endWLANoffM   = "";
       my $forceDisableWLAN   = "";

       # xhr 1 lang de page save_energy xhrId all
       @webCmdArray = ();
       push @webCmdArray, "xhr"                => "1";
       push @webCmdArray, "lang"               => "de";
       push @webCmdArray, "page"               => "save_energy";
       push @webCmdArray, "xhrId"              => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $resultData);
       if ( $analyse =~ /ERROR/) {
         return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet);
       }

       if (defined $resultData->{data}->{mode}) {
         return "nothing to do- energy mode:$val[0] is actually set" if $val[0] eq $resultData->{data}->{mode};
         $timerWLAN        = $resultData->{data}->{wlan}{timerActive};
         $startWLANoffH    = $resultData->{data}->{wlan}{dailyStart}{hour};
         $startWLANoffM    = $resultData->{data}->{wlan}{dailyStart}{minute};
         $endWLANoffH      = $resultData->{data}->{wlan}{dailyEnd}{hour};
         $endWLANoffM      = $resultData->{data}->{wlan}{dailyEnd}{minute};
         $forceDisableWLAN = $resultData->{data}->{wlan}{enabled} == 1? "off" : "on";
       } else {
         return FRITZBOX_Helper_retMsg($hash, "ERROR: data missing " . $analyse, $retMsgbySet);
       }

       # xhr 1 lang de page save_energy mode eco wlan_force_disable off wlan_night off apply nop

       # xhr: 1
       # mode: eco
       # wlan_night: off
       # dailyStartHour: 
       # dailyStartMinute: 
       # dailyEndHour: 
       # dailyEndMinute: 
       # wlan_force_disable: off
       # apply: 
       # lang: de
       # page: save_energy
       # energyMode:default,eco"

       @webCmdArray = ();
       push @webCmdArray, "xhr"                => "1";
       push @webCmdArray, "lang"               => "de";
       push @webCmdArray, "page"               => "save_energy";
       push @webCmdArray, "mode"               => $val[0];
       push @webCmdArray, "wlan_force_disable" => $forceDisableWLAN;
       push @webCmdArray, "wlan_night"         => $timerWLAN ? "on" : "off";
       push @webCmdArray, "dailyStartHour"     => $startWLANoffH;
       push @webCmdArray, "dailyStartMinute"   => $startWLANoffM;
       push @webCmdArray, "dailyEndHour"       => $endWLANoffH;
       push @webCmdArray, "dailyEndMinute"     => $endWLANoffM;
       push @webCmdArray, "apply"              => "";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $resultData);
       if ( $analyse =~ /ERROR/) {
         return FRITZBOX_Helper_retMsg($hash, $analyse, $retMsgbySet);
       }

       if (defined $resultData->{data}->{mode}) {
         return FRITZBOX_Helper_retMsg($hash, "energy mode $val[0] activated", $retMsgbySet);
       }

       return FRITZBOX_Helper_retMsg($hash, "ERROR: unexpected result: " . $analyse, $retMsgbySet);

     } # end energymode

     elsif ( lc $cmd eq 'guestwlan') {
       if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         push @cmdBuffer, "guestwlan " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start $hash->{helper}{TimerCmd};
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       $retMsg = "ERROR: wrong parameter. Use on|off";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

     } # end guestwlan

     elsif ( lc $cmd eq 'ledsetting') {

       # led:on|off brightness:1..2 ledenv:on|off

       unless ( ($hash->{LUADATA} == 1) && ($hash->{fhem}{fwVersion} >= 721)) {
         $retMsg = "ERROR: 'set ... ledsetting' is not supported by the limited interfaces of your Fritz!Box firmware.";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       my $arg = join ' ', @val[0..$#val];

       my @webCmdArray;

       if($val[0] =~ /notifyoff/) {

         my $uid = "";

         if ($val[0] =~ m/^notifyoff:(.*?)$/g) {
           $uid = $1;
         } else {
           $retMsg = "ERROR: ledSetting: $val[0] not supportet. Please use [notifyoff:notify_ID]";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         unless(exists $hash->{helper}{infoActive}{"id".$uid}) {
           $retMsg = "ERROR: ledSetting: $uid - no notify active on $name";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         if ($hash->{fhem}{fwVersion} >= 800) {

           my $result = FRITZBOX_write_javaScript($hash, "boxnotifications/" . $uid, "", "delete");

           # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
           if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
             $retMsg = "ERROR: ledSetting: $uid " . $result->{Error};
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

         } else {

           # get fritzbox luaData xhr 1 delete on id 8_1 deletenotify nop lang de page overview

           push @webCmdArray, "xhr"          => "1";
           push @webCmdArray, "delete "      => "on";
           push @webCmdArray, "id"           => $uid;
           push @webCmdArray, "deletenotify" => "";
           push @webCmdArray, "apply"        => "";
           push @webCmdArray, "lang"         => "de";
           push @webCmdArray, "page"         => "overview";

           FRITZBOX_Log $hash, 4, "set $name $cmd \n" . join(" ", @webCmdArray);

           my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

           FRITZBOX_Log $hash, 5, "ledsetting " . $val[0] . " - \n" . Dumper($result);

           my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

           if ( $analyse =~ /ERROR/) {
             $retMsg = "ledsetting " . $val[0] . " - " . $analyse;
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

           if ($result->{data}->{notify}) {
             $retMsg = "ERROR: ledsetting  " . $arg . " - not applied";
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

         }

         my $content = ReadingsVal($name, "box_notify_" . $uid, undef);
         if ($content && $content !~ /- solved/) {
           # $content = "<html>-solved by click- <a href='/fhem?cmd=deletereading%20-q%20" . $name . "%20box_notify_" . $uid . ".*" . $FW_CSRF . "' target='_self'>&lt;quittieren&gt;</a></html>";

           $content = "<html><div id=\"button\"><button id=\"delLED\" onclick=\"JS:FW_cmd(FW_root+\'?cmd=deletereading ";
           $content .= $name;
           $content .= " box_notify_";
           $content .= $uid . ".*";
           $content .= "&XHR=1\', function(data){FW_okDialog(data)})\">-solved by click- Readings löschen</button></div></html>";

           readingsSingleUpdate($hash, "box_notify_" . $uid, $content, 1 );
         }

         $content = ReadingsVal($name, "box_notify_" . $uid . "_info", undef);
         if ($content && $content !~ /- solved/) {
           my ($infText) = ($content =~ /'JS:FW_okDialog\("(.*?)"\)'\>/gs);
           $content = "<html><div id='button'><button id='dis' onclick='JS:FW_okDialog(" . '"' .$infText. '"' . ")'>-solved by click- Information anzeigen</button></div></html>";
           readingsSingleUpdate($hash, "box_notify_" . $uid . "_info", $content, 1 );
         }


         delete $hash->{helper}{infoActive}{"id$uid"} if exists $hash->{helper}{infoActive}{"id$uid"};

         $retMsg = "ledsetting  " . $arg . " - applied";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, "all");

       }

       $hash->{helper}{ledSet} = 1;
       my $result = FRITZBOX_Get_LED_Settings($hash);

       my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
       if ( $analyse =~ /ERROR/) {
         $retMsg = "ERROR: ledsetting " . $val[0] . " - " . $analyse;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       my $ledDisplay = $result->{data}->{ledSettings}->{ledDisplay};
       my $hasEnv     = $result->{data}->{ledSettings}->{hasEnv};
       my $envLight   = $result->{data}->{ledSettings}->{hasEnv}?$result->{data}->{ledSettings}->{envLight}:0;
       my $canDim     = $result->{data}->{ledSettings}->{canDim};
       my $dimValue   = $result->{data}->{ledSettings}->{canDim}?$result->{data}->{ledSettings}->{dimValue}:0;

       $retMsg = ""; 
       if($hasEnv && $canDim) {
         $retMsg = "ERROR: ledsetting1: wrong amount of parameters: $arg. Required: <led:<on|off> and/or <bright:1..3> and/or <env:on|off>" unless (int @val > 0 && int @val <= 3);
         $retMsg = "ERROR: ledsetting1: wrong parameters: $arg. Required: <led:<on|off> and/or <bright:1..3> and/or <env:on|off>" if $arg !~ /led:[on,off]|bright:[1-3]|env:[on,off]/;
       } elsif ( $hasEnv && !$canDim) {
         $retMsg = "ERROR: ledsetting2: wrong amount of parameters: $arg Required: <led:<on|off> and/or <env:on|off>" unless (int @val > 0 && int @val <= 2);
         $retMsg = "ERROR: ledsetting2: wrong parameters: $arg Required: <led:<on|off> and/or <env:on|off>" if $arg !~ /led:[on,off]|env:[on,off]/;
       } elsif ( !$hasEnv && $canDim) {
         $retMsg = "ERROR: ledsetting3: wrong amount of parameters: $arg Required: <led:<on|off> and/or <bright:1..3>" unless (int @val > 0 && int @val <= 2);
         $retMsg = "ERROR: ledsetting3: wrong parameters: $arg Required: <led:<on|off> and/or <bright:1..3>" if $arg !~ /led:[on,off]|bright:[1-3]/;
       } else {
         $retMsg = "ERROR: ledsetting4: wrong amount of parameters: $arg Required: <led:<on|off>" unless (int @val > 0 && int @val <= 1);
         $retMsg = "ERROR: ledsetting4: wrong parameters: $arg Required: <led:<on|off>" if $arg !~ /led:[on,off]/;
       }

       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $retMsg ne "";

       for (my $i = 0; $i < (int @val); $i++) {
         if ($val[$i] =~ m/^led:(.*?)$/g) {
           $ledDisplay = $1 eq "on" ? 0 : 2;
         } elsif ($val[$i] =~ m/^bright:(.*?)$/g) {
           $dimValue = $1;
         } elsif ($val[$i] =~ m/^env:(.*?)$/g) {
           $envLight = $1 eq "on" ? 1 : 0;
         }
       }

       # xhr 1 led_brightness 3 dimValue 3 environment_light 0 envLight 0 ledDisplay 0 apply nop lang de page led
       # xhr 1 led_display 0 envLight 0 dimValue 1 apply nop lang de page led

       # xhr: 1
       # led_brightness: 3
       # environment_light: 0
       # led_display: 0
       # envLight: 0
       # dimValue: 3
       # ledDisplay: 0
       # apply: 
       # lang: de
       # page: led

       push @webCmdArray, "xhr"            => "1";
       push @webCmdArray, "ledDisplay"     => $ledDisplay;
       push @webCmdArray, "envLight"       => $hasEnv?$envLight:"null";
       push @webCmdArray, "dimValue"       => $canDim?$dimValue:"null";
       push @webCmdArray, "apply"          => "";
       push @webCmdArray, "lang"           => "de";
       push @webCmdArray, "page"           => "led";

       FRITZBOX_Log $hash, 4, "set $name $cmd \n" . join(" ", @webCmdArray);

       $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
       if ( $analyse =~ /ERROR/) {
         $retMsg = "ERROR: ledsetting " . $val[0] . " - " . $analyse;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       if ($result->{data}->{apply} ne "ok") {
         $retMsg = "ERROR: ledsetting " . $arg . " - " . Dumper($result);
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       return FRITZBOX_Helper_retMsg($hash, "ledsetting: ok", $retMsgbySet);

     } # end ledsetting

     elsif ( lc $cmd eq 'lockfilterprofile') {
       if ( $hash->{TR064} != 1 ) { #tr064
         $retMsg = "ERROR: 'set ... lockFilterProfile' is not supported by the limited interfaces of your Fritz!Box firmware.";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       return "list of parameters not ok. Requested profile name, profile status and bpmj status." if int @val < 2;

       my $profileName = "";
       my $profileID   = "";
       my $findPara    = 0;

       for (my $i = 0; $i < (int @val); $i++) {
         if ($val[$i] =~ /status:|bpjm:/) {
           $findPara = $i;
           last;
         }
         $profileName .= $val[$i] . " ";
       }
       chop($profileName);

       $retMsg = "ERROR: list of parameters not ok. Requested profile name, profile status and bpmj status." if $findPara == int @val;
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       my $profileStatus = "";
       my $bpjmStatus    = "";
       my $inetStatus    = "";
       my $disallowGuest = "";

       for (my $i = $findPara; $i < (int @val); $i++) {
         if ($val[$i] =~ /status:unlimited|status:never/) {
           $profileStatus = $val[$i];
           $profileStatus =~ s/status://;
         }
         if ($val[$i] =~ /bpjm:on|bpjm:off/) {
           $bpjmStatus = $val[$i];
           $bpjmStatus =~ s/bpjm://;
         }
       }
      
       $retMsg = "ERROR: list of parameters not ok. Requested profile name, profile status and bpmj status." if $findPara == int @val;
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       my @webCmdArray;
       my $resultData;

       # xhr 1 lang de page kidPro

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "kidPro";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $resultData);
       if ( $analyse =~ /ERROR/) {
         $retMsg = "ERROR: lockfilterprofile " . $val[0] . " - " . $analyse;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       # unbegrenzt [filtprof3]";

       my $views = $resultData->{data}->{kidProfiles};

       eval {
         foreach my $key (keys %$views) {
           FRITZBOX_Log $hash, 4, "Kid Profiles: " . $key;

           if ($profileName eq $resultData->{data}->{kidProfiles}->{$key}{Name}) {
             $profileID = $resultData->{data}->{kidProfiles}->{$key}{Id};
             last;
           }
         }
       };
        
       $retMsg = "ERROR: wrong profile name: $profileName" if $profileID eq "";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       # xhr 1 page kids_profileedit edit filtprof1
       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "page"        => "kids_profileedit";
       push @webCmdArray, "edit"        => $profileID; 

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $resultData);
       if ( $analyse =~ /ERROR/) {
         $retMsg = "ERROR: lockfilterprofile " . $val[0] . " - " . $analyse;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       if (defined $resultData->{data}) {
         # $resultData->{data}->{profileStatus} # unlimited | never | limited
         # $resultData->{data}->{bpjmStatus}    # on | off
         # $resultData->{data}->{inetStatus}    # white | black

         return "because timetable is aktiv status unlimited or never is not supported." if $resultData->{data}{profileStatus} eq "limited";

         $profileStatus = $resultData->{data}{profileStatus} if $profileStatus eq "";
         $disallowGuest = $resultData->{data}{disallowGuest};
     
         if ($bpjmStatus eq "on") {
           $inetStatus = "black";
         } else {
           $inetStatus    = $resultData->{data}{inetStatus} if $inetStatus eq "";
           $bpjmStatus    = $resultData->{data}{bpjmStatus} if $bpjmStatus eq "";
           $bpjmStatus    = $inetStatus eq "black" ? $bpjmStatus : "";
         }
       } else {
         $retMsg = "ERROR: unexpected result: " . $analyse;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       # xhr 1 edit filtprof3299 name: TestProfil time unlimited timer_item_0 0000;1;1 timer_complete 1 budget unlimited bpjm on netappschosen nop choosenetapps choose apply nop lang de page kids_profileedit

       # xhr: 1
       # back_to_page: kidPro
       # edit: filtprof3299
       # name: TestProfil
       # time: never
       # timer_item_0: 0000;1;1
       # timer_complete: 1
       # budget: unlimited
       # bpjm: on
       # netappschosen: 
       # choosenetapps: choose
       # apply: 
       # lang: de
       # page: kids_profileedit

       @webCmdArray = ();
       push @webCmdArray, "xhr"             => "1";
       push @webCmdArray, "lang"            => "de";
       push @webCmdArray, "page"            => "kids_profileedit";
       push @webCmdArray, "apply"           => "";
       push @webCmdArray, "edit"            => $profileID;
       push @webCmdArray, "name"            => $profileName;
       push @webCmdArray, "time"            => $profileStatus;
       push @webCmdArray, "timer_item_0"    => "0000;1;1";
       push @webCmdArray, "timer_complete"  => 1;
       push @webCmdArray, "budget"          => "unlimited";
       push @webCmdArray, "parental"        => $bpjmStatus;
       push @webCmdArray, "bpjm"            => $bpjmStatus;
       push @webCmdArray, "filtertype"      => $inetStatus;
       push @webCmdArray, "netappschosen"   => ""; 
       push @webCmdArray, "choosenetapps"   => "choose";
       push @webCmdArray, "disallow_guest"  => $disallowGuest;

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;


       $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $resultData);
       if ( $analyse =~ /ERROR/) {
         $retMsg = "ERROR: lockfilterprofile " . $val[0] . " - " . $analyse;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       if (defined $resultData->{data}{apply}) {
         $retMsg = "ERROR during apply" if $resultData->{data}{apply} ne "ok";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       $retMsg = "ERROR: profile $profileName set to status $profileStatus";
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

     } # end lockfilterprofile

     elsif ( lc $cmd eq 'locklandevice' && $mesh eq "master") {

       if (int @val == 2) {

         if ($hash->{fhem}{fwVersion} < 800) {
           $val[0] = FRITZBOX_SetGet_Proof_Params($hash, $name, $cmd, "^(on|off|rt)\$", @val);
         } else {
           $val[0] = FRITZBOX_SetGet_Proof_Params($hash, $name, $cmd, "^(on|off|rt|rtoff)\$", @val);
         }

         return FRITZBOX_Helper_retMsg($hash, $val[0], $retMsgbySet) if($val[0] =~ /ERROR/);

         push @cmdBuffer, "locklandevice " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } else {
         if ($hash->{fhem}{fwVersion} < 800) {
           $retMsg = "ERROR: locklandevice arguments missing. Use set <name> lockLandevice <number|mac> <on|off|rt>";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         } else {
           $retMsg = "ERROR: locklandevice arguments missing. Use set <name> lockLandevice <number|mac> <on|off|rt|rtoff>";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }
       }

     } # end locklandevice

     elsif ( lc $cmd eq 'macfilter' && $mesh eq "master") {

       if ( int @val == 1 && $val[0] =~ /^(on|off)$/ ) {

         push @cmdBuffer, "macfilter " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start $hash->{helper}{TimerCmd};
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       } else {
         $retMsg = "ERROR: for macFilter arguments";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

     } # end macfilter

     # set phonebookentry
     elsif ( lc $cmd eq 'phonebookentry') {

       #         PhoneBookID VIP EntryName      NumberType:PhoneNumber
       # new|chg 0           0   Mein_Test_Name home:02234983523
       # new     PhoneBookID category entryName home|mobile|work|fax_work|other:phoneNumber

       #         PhoneBookID VIP EntryName      NumberType:PhoneNumber
       # del     PhoneBookID     Mein_Test_Name

       unless ( defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && $hash->{TR064} == 1 && $hash->{SECPORT} ) { #tr064
         $retMsg = "ERROR: 'set ... PhonebookEntry' is not supported by the limited interfaces of your Fritz!Box firmware.";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       # check for command
       $retMsg = "ERROR: wrong function: $val[0]. Requested new, chg or del." if $val[0] !~ /new|chg|del/;
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       if ($val[0] eq "del" && int @val < 3) {
         $retMsg = "ERROR: wrong amount of parameters: " . int @val . ". Parameters are: del <PhoneBookID> <name>";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       } elsif ($val[0] eq "new" && int @val < 4) {
         $retMsg = "ERROR: wrong amount of parameters: " . int @val . ". Parameters are: new <PhoneBookID> <category> <name> <numberType:phoneNumber>";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       # check for phonebook ID
       my $uniqueID = $val[1];
       my $pIDs     = ReadingsVal($name, "fon_phoneBook_IDs", undef);

       if ($pIDs) {
         $retMsg = "ERROR: wrong phonebook ID: $uniqueID in ID's $pIDs" if $uniqueID !~ /[$pIDs]/;
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       } else {
         my @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "GetPhonebookList"] );
         my @tr064Result = FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);

         if ($tr064Result[0]->{Error}) {
           $retMsg = "ERROR: identifying phonebooks via TR-064:" . Dumper (@tr064Result);
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         } else {

           FRITZBOX_Log $hash, 5, "get Phonebooks -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetPhonebookListResponse}) {
             if (defined $tr064Result[0]->{GetPhonebookListResponse}->{NewPhonebookList}) {
               my $PhoneIDs = $tr064Result[0]->{GetPhonebookListResponse}->{NewPhonebookList};
               $retMsg = "ERROR: wrong phonebook ID: $uniqueID in ID's $PhoneIDs" if $uniqueID !~ /[$PhoneIDs]/;
               return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
             } else {
               $retMsg = "ERROR: no phonebook result via TR-064:" . Dumper (@tr064Result);
               return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
             }
           } else {
             $retMsg = "ERROR: no phonebook ID's via TR-064:" . Dumper (@tr064Result);
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }
         }
       }

       # check for parameter list for command new
       if ($val[0] eq "new") {
         return "change not yet implemented" if $val[0] eq "chg";
         # Change existing entry:
         # - set phonebook ID an entry ID and XML entry data (without the unique ID tag)
         # - set phonebook ID and an empty value for PhonebookEntryID and XML entry data
         # structure with the unique ID tag (e.g. <uniqueid>28</uniqueid>)

         # new 0 0 super phone home:02234 983523 work:+49 162 2846962
         # new PhoneBookID category entryName home|mobile|work|fax_work|other:phoneNumber
         # 0   1           2        3         4       
        
         # xhr: 1
         # idx: 
         # uid: 193
         # entryname: super phone
         # numbertype0: home
         # number0: 02234983523
         # numbertype2: mobile
         # number2: 5678
         # numbertype3: work
         # number3: 1234
         # numbertypenew4: fax_work
         # numbernew4: 789
         # emailnew1: 
         # prionumber: none
         # bookid: 0
         # back_to_page: /fon_num/fonbook_list.lua
         # apply: 
         # lang: de
         # page: fonbook_entry

         # check for important person
         if ($val[2] !~ /[0,1]/) {
           $retMsg = "ERROR: wrong category: $val[2]. Requested 0,1. 1 for important person.";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         # getting entry name
         my $entryName   = "";
         my $nextParaPos = 0;

         for (my $i = 3; $i < (int @val); $i++) {
           if ($val[$i] =~ /home:|mobile:|work:|fax_work:|other:/) {
             $nextParaPos = $i;
             last;
           }
           $entryName .= $val[$i] . " ";
         }
         chop($entryName);

         if (!$nextParaPos) {
           $retMsg = "ERROR: parameter home|mobile|work|fax_work|other:phoneNumber missing";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         my $phonebook = FRITZBOX_Phonebook_readRemote($hash, $uniqueID);

         if ($phonebook->{Error}) {
           $retMsg = "ERROR: $phonebook->{Error}";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         my $uniqueEntryID = FRITZBOX_Phonebook_parse($hash, $phonebook->{data}, undef, $entryName);

         if ($uniqueEntryID !~ /ERROR/) {
           $retMsg = "ERROR: entry name <$entryName> exists";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         my $typePhone = "";
         my @phoneArray = ();
         my $cnt = 0;

         $typePhone .= $val[$nextParaPos];
         return "ERROR: parameter home|mobile|work|fax_work|other:phoneNumber missing" if $typePhone !~ /home:|mobile:|work:|fax_work:|other:/;
         $nextParaPos++;

         # FRITZBOX_Phonebook_Number_normalize($hash, $2);
         for (my $i = $nextParaPos; $i < (int @val); $i++) {
           if ($val[$i] =~ /home:|mobile:|work:|fax_work:|other:/) {
             if($typePhone =~ m/^(.*?):(.*?)$/g) {
               push @phoneArray, [$1, FRITZBOX_Phonebook_Number_normalize($hash, $2)];
             }
             $cnt++;
             $typePhone = "";
           }
           $typePhone .= $val[$i];
         }
         if($typePhone =~ m/^(.*?):(.*?)$/g) {
           push @phoneArray, [$1, FRITZBOX_Phonebook_Number_normalize($hash, $2)];
         }

         # '<number type="' . $val[3] .'" prio="1" id="0">' . $extNo . '</number>'
         my $xmlStr = "";
         for (my $i = 0; $i < (int @phoneArray); $i++) {
           $xmlStr .= '<number type="' . $phoneArray[$i][0] .'" prio="1" id="' . $i . '">' . $phoneArray[$i][1] . '</number>'
         } 

         # 2.17 SetPhonebookEntryUID 
         # Add a new or change an existing entry in a telephone book using the unique ID of the entry.
         # Add new entry:
         # - set phonebook ID and XML entry data structure (without the unique ID tag)
         # Change existing entry:
         # - set phonebook ID and XML entry data structure with the unique ID tag
         # (e.g. <uniqueid>28</uniqueid>)
         # The action returns the unique ID of the new or changed entry

         # my $xmlUniqueID = $val[0] eq "chg"? '<uniqueid>' . $uniqueEntryID . '</uniqueid>' : "";

         my $para  = '<Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
                   . '<?xml version="1.0" encoding="utf-8"?>'
                   . '<contact>'
                   .   '<category>' . $val[2] . '</category>'
                   .   '<person>'
                   .     '<realName>' . $entryName . '</realName>'
                   .   '</person>'
                   .   '<telephony nid="'. (int @phoneArray) . '">'
                   .     $xmlStr
                   .   '</telephony>'
                 #  .   $xmlUniqueID
                   . '</contact>';

         my @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "SetPhonebookEntryUID", "NewPhonebookID", $uniqueID, "NewPhonebookEntryData", $para] );
         my @tr064Result = FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);

         if ($tr064Result[0]->{Error}) {
           $retMsg = "ERROR: identifying phonebooks via TR-064:" . Dumper (@tr064Result);
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         } else {

           if ($tr064Result[0]->{SetPhonebookEntryUIDResponse}) {
             if (defined $tr064Result[0]->{SetPhonebookEntryUIDResponse}->{NewPhonebookEntryUniqueID}) {
               my $EntryID = $tr064Result[0]->{SetPhonebookEntryUIDResponse}->{NewPhonebookEntryUniqueID};
               $retMsg = "set new phonebook entry: $entryName with NewPhonebookEntryUniqueID: $EntryID";
               return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
             } else {
               $retMsg = "ERROR: no NewPhonebookEntryUniqueID via TR-064:" . Dumper (@tr064Result);
               return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
             }
           } else {
             $retMsg = "ERROR: no SetPhonebookEntryUIDResponse via TR-064:" . Dumper (@tr064Result);
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }
         }
       } elsif ($val[0] eq "del") {
         # del 0 Mein_Test_Name

         my $phonebook = FRITZBOX_Phonebook_readRemote($hash, $uniqueID);

         if ($phonebook->{Error}) {
           $retMsg = "ERROR: $phonebook->{Error}";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         my $rName = join ' ', @val[2..$#val];

         my $uniqueEntryID = FRITZBOX_Phonebook_parse($hash, $phonebook->{data}, undef, $rName);

         if ($uniqueEntryID =~ /ERROR/) {
           $retMsg = "ERROR: getting uniqueID for phonebook $uniqueID with entry name: $rName";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         # "X_AVM-DE_OnTel:1" "x_contact" "DeletePhonebookEntryUID" "NewPhonebookID" 0 "NewPhonebookEntryUniqueID" 181
         my @tr064CmdArray = ();
         @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "DeletePhonebookEntryUID", "NewPhonebookID", $uniqueID, "NewPhonebookEntryUniqueID", $uniqueEntryID] );
         my @tr064Result = FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);
 
         if ($tr064Result[0]->{Error}) {
           return "ERROR: identifying phonebooks via TR-064:" . Dumper (@tr064Result);
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         } else {

           if (exists($tr064Result[0]->{DeletePhonebookEntryUIDResponse})) {
             $retMsg = "deleted phonebook entry:<$rName> with UniqueID: $uniqueID";
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           } else {
             $retMsg = "ERROR: no SetPhonebookEntryUIDResponse via TR-064:" . Dumper (@tr064Result);
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }
         }
       }
       return undef;
     } # end phonebookentry

     elsif ( lc $cmd eq 'reboot') {
       if ( int @val != 1 ) {
        $retMsg = "ERROR: wrong amount of parammeters. Please use: set <name> reboot <minutes>";
        return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       } else {

          if ( $hash->{TR064} == 1 ) { #tr064
            readingsSingleUpdate($hash, "box_lastFhemReboot", strftime("%d.%m.%Y %H:%M:%S", localtime(time() + ($val[0] * 60))), 1 );
#              my @tr064CmdArray = (["DeviceConfig:1", "deviceconfig", "Reboot"] );
#              FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);

            my $RebootTime = strftime("%H:%M",localtime(time() + ($val[0] * 60)));

            fhem("delete act_Reboot_$name", 1);
            fhem('defmod act_Reboot_' . $name . ' at ' . $RebootTime . ' {fhem("get ' . $name . ' tr064Command DeviceConfig:1 deviceconfig Reboot")}');

          }
          else {
            $retMsg = "ERROR: 'set ... reboot' is not supported by the limited interfaces of your Fritz!Box firmware.";
            return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
          }
          return undef;
       }
     } # end reboot

     elsif ( lc $cmd eq 'rescanwlanneighbors' ) {
       push @cmdBuffer, "rescanwlanneighbors " . join(" ", @val);
       $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
     } # end rescanwlanneighbors

     #set Ring
     elsif ( lc $cmd eq 'ring' && $mesh eq "master") {
       unless (int @val) {
         $retMsg = "ERROR: At least one parameter must be defined.";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       if (int @val > 0 && $val[0] !~ /^[\d,]+$/) {

         # Check if 1st parameter are comma separated numbers
         
         $retMsg = "ERROR: Parameter '$val[0]' not a (list) of number(s) (only commas (,) are allowed to separate phone numbers)";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

         push @cmdBuffer, "ring " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

       }

       return undef;
     } # end ring

     elsif ( lc $cmd eq 'switchipv4dns' && $mesh eq "master") {

       if (int @val == 1 && $val[0] =~ /^(provider|other)$/) {

         if ($hash->{fhem}{fwVersion} < 721) {
           $retMsg = "ERROR: FritzOS version must be greater than 7.20.";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         if ( $val[0] eq "provider") {

           #xhr 1 ipv4_use_user_dns 0 page dnsSrv apply nop lang de
           my @webCmdArray;
           push @webCmdArray, "xhr"                       => "1";
           push @webCmdArray, "lang"                      => "de";
           push @webCmdArray, "page"                      => "dnsSrv";
           push @webCmdArray, "apply"                     => "";
           push @webCmdArray, "ipv4_use_user_dns"         => "0";

           FRITZBOX_Log $hash, 4, "data.lua: " . join(" ", @webCmdArray);

           my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

           my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
           if ( $analyse =~ /ERROR/) {
             $retMsg = "ERROR: switchipv4dns " . $val[0] . " - " . $analyse;
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

           $retMsg = "DNS IPv4 set to " . $val[0];
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

         } elsif ( $val[0] eq "other") {

           #xhr 1 lang de page dnsSrv xhrId all
           my @webCmdArray;
           push @webCmdArray, "xhr"                       => "1";
           push @webCmdArray, "lang"                      => "de";
           push @webCmdArray, "page"                      => "dnsSrv";
           push @webCmdArray, "xhrId"                     => "all";

           FRITZBOX_Log $hash, 4, "data.lua: " . join(" ", @webCmdArray);

           my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

           my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
           if ( $analyse =~ /ERROR/) {
             $retMsg = "ERROR: switchipv4dns " . $val[0] . " - " . $analyse;
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
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

           FRITZBOX_Log $hash, 4, "data.lua: " . join(" ", @webCmdArray);

           $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

           $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);
           if ( $analyse =~ /ERROR/) {
             $retMsg = "ERROR: switchipv4dns " . $val[0] . " - " . $analyse;
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

           $retMsg = "DNS IPv4 set to " . $val[0];
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         $retMsg = "DNS IPv4 set to " . $val[0];
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       } else {
         $retMsg = "ERROR: for switchipv4dns arguments";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

     } # end switchipv4dns

     elsif ( lc $cmd eq 'tam' && $mesh eq "master") {
       if ( int @val == 2 && defined( $hash->{READINGS}{"tam".$val[0]} ) && $val[1] =~ /^(on|off)$/ ) {
         my $state = $val[1];
         $state =~ s/on/1/;
         $state =~ s/off/0/;

         if ($hash->{SECPORT}) { #TR-064
           my @tr064CmdArray = (["X_AVM-DE_TAM:1", "x_tam", "SetEnable", "NewIndex", $val[0] - 1 , "NewEnable", $state]);
           FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         }

         readingsSingleUpdate($hash,"tam".$val[0]."_state",$val[1], 1);
         return undef;
       }
     } # end tam

     elsif ( lc $cmd eq 'enablevpnshare' && $mesh eq "master" && ($hash->{fhem}{fwVersion} >= 721)) {

       if ( int @val == 2 && $val[1] =~ /^(on|off)$/ ) {

         FRITZBOX_Log $hash, 3, "INFO: set $name $cmd " . join(" ", @val);

         if ($hash->{fhem}{fwVersion} < 721 ) {
           $retMsg = "ERROR: FritzOS version must be greater than 7.20";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

         if ( AttrVal( $name, "enableVPNShares", "0")) {
           $val[0] = lc($val[0]);

           $val[0] = "vpn".$val[0] unless ($val[0] =~ /vpn/);

           unless (defined( $hash->{READINGS}{$val[0]})) {
             $retMsg = "ERROR: set $name $cmd " . join(" ", @val);
             return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
           }

           FRITZBOX_Log $hash, 4, "INFO: set $name $cmd " . join(" ", @val);
           push @cmdBuffer, "enablevpnshare " . join(" ", @val);
           $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

         } else {
           $retMsg = "ERROR: vpn readings not activated";
           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
         }

       } else {
         $retMsg = "ERROR: for enableVPNshare arguments";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

     } # end enablevpnshare

     elsif ( (lc $cmd eq 'wakeupcall') && ($hash->{LUADATA} == 1) && defined ($hash->{MODEL}) && ($hash->{MODEL} =~ "Box") && ($hash->{fhem}{fwVersion} >= 721) ) {
       # xhr 1 lang de page alarm xhrId all / get Info

       # xhr: 1
       # active: 1 | 0
       # hour: 07
       # minutes: 00
       # device: 70
       # name: Wecker 1
       # optionRepeat: daily | only_once | per_day { mon: 1 tue: 0 wed: 1 thu: 0 fri: 1 sat: 0 sun: 0 }
       # apply: true
       # lang: de
       # page: alarm | alarm1 | alarm2

       # alarm1 62 per_day 10:00 mon:1 tue:0 wed:1 thu:0 fri:1 sat:0 sun:0

       # set <name> wakeUpCall <device> <alarm1|alarm2|alarm3> <on|off>

       if (int @val < 2) {
         $retMsg = "ERROR: wakeUpCall - to few parameters";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       # return "Amount off parameter:" . int @val;

       $retMsg = "";
       if (int @val == 2) {
         $retMsg = "ERROR: wakeUpCall - 1st Parameter must be one of the alarm pages: alarm1,alarm2 or alarm3" if $val[0] !~ /^(alarm1|alarm2|alarm3)$/;
         $retMsg = "ERROR: wakeUpCall - 2nd Parameter must be 'off'" if $val[1] !~ /^(off)$/;
       } elsif (int @val > 2) {
         return "wakeUpCall: 2nd Parameter must be one of the alarm pages: alarm1,alarm2 or alarm3" if $val[0] !~ /^(alarm1|alarm2|alarm3)$/;

         my $device = "fd_" . $val[1];
         my $devname = "fdn_" . $val[1];

         $devname =~ s/\|/&#0124/g;  # handling valid character | in FritzBox names
         $devname =~ s/%20/ /g;      # handling spaces

         unless ($hash->{fhem}->{$device} || $hash->{fhem}->{$devname}) {
           $retMsg = "ERROR: wakeUpCall - dect or fon Device name/number $val[1] not defined ($devname)"; # unless $hash->{fhem}->{$device};
         }
       
         if ($hash->{fhem}->{$devname}) {
           $val[1] = $hash->{fhem}->{$devname};
           $val[1] =~ s/&#0124/\|/g;  # handling valid character | in FritzBox names
         }
       }
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $retMsg ne "" ;

       $retMsg = "";
       if ( int @val >= 3 && $val[2] !~ /^(daily|only_once|per_day)$/) {
         $retMsg = "ERROR: wakeUpCall - 3rd Parameter must be daily, only_once or per_day";
       } elsif ( int @val >= 3 && $val[3] !~ /^(2[0-3]|[01]?[0-9]):([0-5]?[0-9])$/) {
         $retMsg = "ERROR: wakeUpCall - 4th Parameter must be a valid time";
       } elsif ( int @val == 11 && $val[2] ne "per_day") {
         $retMsg = "ERROR: wakeUpCall - 3rd Parameter must be per_day";
       } elsif ( int @val == 11 && $val[2] eq "per_day") {

         my $fError = 0;
         for(my $i = 4; $i <= 10; $i++) {
           if ($val[$i] !~ /^(mon|tue|wed|thu|fri|sat|sun):(0|1)$/) {
             $fError = $i;
             last;
           }
         }

         $retMsg = "ERROR: wakeUpCall - wrong argument for per_day: $val[$fError]" if ($fError);

       } elsif (int(@val) != 4 && int(@val) != 11 && $val[1] !~ /^(off)$/)  {
         $retMsg = "ERROR: wakeUpCall- wrong number of arguments per_day.";
       }
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $retMsg ne "" ;

       push @cmdBuffer, "wakeupcall " . join(" ", @val);
       $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

     } # end wakeupcall

     elsif ( lc $cmd eq 'wlan') {
       if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         push @cmdBuffer, "wlan " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }
     } # end wlan

     elsif ( lc $cmd =~ /^wlan(2\.4|5)$/ && $hash->{fhem}{is_double_wlan} == 1 ) {
       if ( int @val == 1 && $val[0] =~ /^(on|off)$/ ) {
         push @cmdBuffer, lc ($cmd) . " " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }
     } # end wlan

     elsif ( lc $cmd eq 'wlanlogextended') {
       if (int @val == 1 && $val[0] =~ /^(on|off)$/) {
         push @cmdBuffer, "wlanlogextended " . join(" ", @val);
         $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd});
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }
     } # end wlanlogextended

     elsif ( lc $cmd eq 'wlanguestparams') {

       # getting Parameters
       my %paraPos;
       my $lastPos = (int @val) - 1;
       my $returnStr = "";

       for (my $i = (int @val) - 1; $i >= 0; $i--) {
         if ($val[$i] =~ /ssid:|pwd:|wlan:|mode:|tmo:|tmoActive:|tmoNoForcedOff:/) {
           my $para = $val[$i];
	    $para =~ s/\:.*//;

           my $paraValue = join(' ', @val[$i..$lastPos]);
           $paraValue =~ s/.*?\://;

           $retMsg = "";
           if ($para =~ /ssid/ && ((substr($paraValue,0,1) eq " ") || $paraValue !~ /[A-Za-z0-9 _!"#%&',:;<=>@`~\-\$\(\)\*\+\.\?\[\]\^\{\|\}\\]{8,63}/) ) {
             $retMsg = "ERROR: wlanguestparams: SSID - wrong number of characters (8 - 63) or not allowed characters: $paraValue.\nSee also: 'https://fritzhelp.avm.de/help/de/FRITZ-Box-7590/1und1/021/hilfe_zeichen_fuer_kennwoerter'";

           } elsif ($para =~ /pwd/ && ((substr($paraValue,0,4) eq '$$$$') || (substr($paraValue,0,1) eq " ") || ($paraValue !~ /[A-Za-z0-9 _!"#%&',:;<=>@`~\-\$\(\)\*\+\.\?\[\]\^\{\|\}\\]{8,32}/)) ) {
             $retMsg = "ERROR: wlanguestparams: Password - wrong number of characters (8 - 63) or not allowed characters: " . $paraValue . ".\nSee also: 'https://fritzhelp.avm.de/help/de/FRITZ-Box-7590/1und1/021/hilfe_zeichen_fuer_kennwoerter'";

           } elsif ($para =~ /wlan|tmoActive|tmoNoForcedOff/ && ($paraValue !~ /on|off/) ) {
             $retMsg = "ERROR: wlanguestparams: $val[0] - not allowed command: $paraValue. Recommended: on or off";

           } elsif ($para =~ /tmo/ && ($paraValue !~ /[0-9]{2,4}/ || $paraValue < 15 || $paraValue > 4320) ) {
             $retMsg = "ERROR: wlanguestparams: tmo (timeout) - not allowed command: $paraValue. Recommended: number in between 15 - 4320 minutes";

           } elsif ($para =~ /mode/ && ($paraValue !~ /private|public/) ) {
             $retMsg = "ERROR: wlanguestparams: MODE - not allowed command: $paraValue. Recommended: private or public";
           }

           return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet) if $retMsg ne "";

           $returnStr .= $para . ":" . $paraValue . "\n";

           $lastPos = $i - 1;
         }
       }

       if ($returnStr eq "") {
         $retMsg = "ERROR: wlanguestparams: no valid command. Please use ssid:|pwd:|wlan:|mode:|tmo:|tmoActive:|tmoNoForcedOff: as commands";
         return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);
       }

       push @cmdBuffer, "wlanguestparams " . join(" ", @val);
       $retMsg = FRITZBOX_Readout_SetGet_Start($hash->{helper}{TimerCmd}) . "\n" . $returnStr;
       return FRITZBOX_Helper_retMsg($hash, $retMsg, $retMsgbySet);

     } # end wlanguestparams
   }

   return "Unknown argument $cmd or wrong parameter(s), choose one of $list";

} # end FRITZBOX_Set

#######################################################################
sub FRITZBOX_Get($@)
{
   my ($hash, $name, $cmd, @val) = @_;
   my $returnStr;

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");
   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   # available, if password is set correctly
   if ($hash->{WEBCONNECT}) {

     if( lc $cmd eq "smarthomepredef" && $hash->{LUADATA} == 1) {

       return "ERROR: required no parameter or deviceID or deviceID prefdef-name" if (int @val != 0 && int @val > 2);

       return "ERROR: required no parameter or deviceID or deviceID prefdef-name" if (int @val == 1 && $val[0] =~ /\D/ );

       return "ERROR: required no parameter or deviceID or deviceID prefdef-name" if (int @val == 2 && ( $val[0] =~ /\D/ || $val[1] !~ /^([-\w]+)$/) );

       my $retMsg       = "";
       my $newValue     = undef;
       my $action       = "";
       my $preDefName   = "";
       my $preDefWeb    = "no";
       my $preDefDevice = "";
       my @webCmdArray;

       if (int @val == 1) {

         $preDefDevice = $val[0];
         $preDefName = "NO_nAME";

       } elsif (int @val == 2) {

         $preDefDevice = $val[0];
         $preDefName = $val[1];

       } else {
         $preDefName = "__List__All";
       }

       my $returnData;

       my $preDefs = "";

       my $smh_pre_path = $attr{global}{modpath} . "/FHEM/FhemUtils/smart_home_predefs.txt";
       my ($err, @l) = FileRead($smh_pre_path);

       if ($err) {
         return "ERROR: SmartHome Device reading the $smh_pre_path - $err";
       }

       if ($preDefName eq "__List__All") {
         for my $l (@l) {
           if($l =~ m/^$name:(\d+):([-\w]+):.*$/) {
             $preDefs .= "Device:$1 preDef:$2\n";
           }
         }
       } elsif ($preDefName eq "NO_nAME") {
         for my $l (@l) {
           if($l =~ m/^$name:$val[0]:([-\w]+):.*$/) {
             $preDefs .= "Device:$val[0] preDef:$1\n";
           }
         }
       } else {
         $returnData = FRITZBOX_Get_SmartHome_Devices_List($hash, $preDefDevice, "load", $preDefName);

         if ($returnData->{Error}) {
           $retMsg = "ERROR: " . $returnData->{Error} . " " . $returnData->{Info};
           return $retMsg;
         }

         $Data::Dumper::Sortkeys = 1;
         my $retPreDef = "saved preDef for device:$val[0] with name:$preDefName\n" . Dumper($returnData);

         if ($returnData->{device_name_category} eq 'SOCKET') {
           $returnData = FRITZBOX_Get_SmartHome_Devices_List($hash, $preDefDevice, "loads", $preDefName);

           if ($returnData->{Error}) {
             $retMsg = "ERROR: " . $returnData->{Error} . " " . $returnData->{Info};
             return $retMsg;
           }

           $retPreDef .= "\n" . Dumper($returnData);
         }

         return $retPreDef;
       }

       return "saved preDefs:\n" . $preDefs;

     } elsif( lc $cmd eq "luaquery" && $hash->{LUAQUERY} == 1) {
     # get Fritzbox luaQuery inetstat:status/Today/BytesReceivedLow
     # get Fritzbox luaQuery telcfg:settings/AlarmClock/list(Name,Active,Time,Number,Weekdays)
       FRITZBOX_Log $hash, 3, "get $name $cmd " . join(" ", @val);

       return "Wrong number of arguments, usage: get $name luaQuery <query>"       if int @val !=1;

       $returnStr   = "Result of query = '$val[0]'\n";
       $returnStr   .= "----------------------------------------------------------------------\n";

       my $queryStr = "&result=".$val[0];

       my $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

       my $tmp = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

       return $returnStr . $tmp;

     } elsif( lc $cmd eq "luafunction" && $hash->{LUAQUERY} == 1) {
       FRITZBOX_Log $hash, 3, "get $name $cmd " . join(" ", @val);

       return "Wrong number of arguments, usage: get $name luafunction <query>" if int @val !=1;

       $returnStr  = "Result of function call '$val[0]' \n";
       $returnStr .= "----------------------------------------------------------------------\n";

       my $result = FRITZBOX_call_Lua_Query( $hash, $val[0], "", "luaCall") ;

       my $tmp = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

       return $returnStr . $tmp;

     } elsif( lc $cmd eq "luadata" && $hash->{LUADATA} == 1) {
       FRITZBOX_Log $hash, 3, "get $name $cmd [" . int(@val) . "] " . join(" ", @val);

       my $mode = "";

       if ($val[0] =~ /json/) {
         return "Wrong number of arguments, usage: get $name hash argName1 argValue1 [argName2 argValue2] ..." if int @val < 3 || (int(@val) - 1) %2 == 1;
         $mode = shift (@val); # remove 1st element and store it.
       } else {
         return "Wrong number of arguments, usage: get $name argName1 argValue1 [argName2 argValue2] ..." if int @val < 2 || int(@val) %2 == 1;
       }

       my @webCmdArray;
       my $queryStr;
       for (my $i = 0; $i <= (int @val)/2 - 1; $i++) {
         $val[2*$i+1] =~ s/#x003B/;/g;
         $val[2*$i+1] = "" if lc($val[2*$i+1]) eq "nop";
         $val[2*$i+1] =~ tr/\&/ /;
         push @webCmdArray, $val[2*$i+0] => $val[2*$i+1];
         $queryStr .= "'$val[2*$i+0]' => '$val[2*$i+1]'\n";
       }

       $queryStr =~ tr/\&/ /;

       FRITZBOX_Log $hash, 4, "get $name $cmd " . $queryStr;

       my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       if ($mode eq "json") {
         return to_json( $result, { pretty => 0 } );
       }

#       if ($mode eq "html") {
#         return FRITZBOX_Helper_Json2HTML(parse_json(to_json( $result, { pretty => 0 } )));
#       }

       $returnStr  = "Result of data = " . $queryStr . "\n";
       $returnStr .= "----------------------------------------------------------------------\n";

       my $flag = 1;
       my $tmp = FRITZBOX_Helper_analyse_Lua_Result($hash, $result, 1);

       return $returnStr . $tmp;

     } elsif( lc $cmd eq "javascript" && $hash->{LUADATA} == 1) {
       FRITZBOX_Log $hash, 3, "get $name $cmd [" . int(@val) . "] " . join(" ", @val);

       my $mode = "";

       if ($val[0] =~ /json/) {
         return "Wrong number of arguments, usage: get $name hash JS-Name" if int @val != 2;
         $mode = shift (@val); # remove 1st element and store it.
       } else {
         return "Wrong number of arguments, usage: get $name JS-Name" if int @val != 1;
       }

       FRITZBOX_Log $hash, 4, "get $name $cmd " . $val[0];

       my $result = FRITZBOX_call_javaScript($hash, $val[0] ) ;

       if ($mode eq "json") {
         return to_json( $result, { pretty => 0 } );
       }

#       if ($mode eq "html") {
#         return FRITZBOX_Helper_Json2HTML(parse_json(to_json( $result, { pretty => 0 } )));
#       }

       $returnStr  = "Result of data = " . $val[0] . "\n";
       $returnStr .= "----------------------------------------------------------------------\n";

       my $flag = 1;
       my $tmp = FRITZBOX_Helper_analyse_Lua_Result($hash, $result, 1);

#       my $tmp = Dumper($result);

       return $returnStr . $tmp;

     } elsif( lc $cmd eq "luadectringtone" && $hash->{LUADATA} == 1) {
       FRITZBOX_Log $hash, 3, "get $name $cmd [" . int(@val) . "] " . join(" ", @val);

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

       FRITZBOX_Log $hash, 4, "get $name $cmd " . $queryStr;

       $returnStr  = "Result of data = " . $queryStr . "\n";
       $returnStr .= "----------------------------------------------------------------------\n";

       my $result = FRITZBOX_call_LuaData($hash, "fon_devices\/edit_dect_ring_tone", \@webCmdArray) ;

       my $flag = 1;
       my $tmp = FRITZBOX_Helper_analyse_Lua_Result($hash, $result, 1);

       return $returnStr . $tmp;

     } elsif( lc $cmd eq "landeviceinfo" && $hash->{LUADATA} == 1)  {

       FRITZBOX_Log $hash, 3, "get $name $cmd " . join(" ", @val);

       return "Wrong number of arguments, usage: get $name argName1 argValue1" if int @val != 1;

       my $erg = FRITZBOX_SetGet_Proof_Params($hash, $name, $cmd, "", @val);

       return $erg if($erg =~ /ERROR/);

       return FRITZBOX_Get_Lan_Device_Info( $hash, $erg, "info");

     } elsif( lc $cmd eq "fritzlog" && $hash->{LUADATA} == 1)  {

       FRITZBOX_Log $hash, 3, "get $name $cmd " . join(" ", @val);

       if ($hash->{fhem}{fwVersion} < 721) {
         FRITZBOX_Log $hash, 2, "FritzOS version must be greater than 7.20";
         return "FritzOS version must be greater than 7.20.";
       }

       if (int @val == 2) {
         return "1st parmeter is wrong, usage hash or table for first parameter" if $val[0] !~ /hash|table/;
         return "2nd parmeter is wrong, usage &lt;all|sys|wlan|usb|net|fon&gt" if $val[1] !~ /all|sys|wlan|usb|net|fon/;
       } elsif(int @val == 3 && $val[0] eq "hash") {
         return "1st parmeter is wrong, usage hash or table for first parameter" if $val[0] !~ /hash|table/;
         return "2nd parmeter is wrong, usage &lt;all|sys|wlan|usb|net|fon&gt" if $val[1] !~ /all|sys|wlan|usb|net|fon/;
         return "3nd parmeter is wrong, usage on or off" if $val[2] !~ /on|off/;
       } elsif(int @val == 1) {
         return "number of arguments is wrong, usage: get fritzLog &lt;" . $name. "&gt; &lt;hash&gt; &lt;all|sys|wlan|usb|net|fon&gt; [on|off]" if $val[0] eq "hash";
         return "number of arguments is wrong, usage: get fritzLog &lt;" . $name. "&gt; &lt;table&gt; &lt;all|sys|wlan|usb|net|fon&gt;" if $val[0] eq "table";
       } else {
         return "number of arguments is wrong, usage: get fritzLog &lt;" . $name. "&gt; &lt;hash|table&gt; &lt;all|sys|wlan|usb|net|fon&gt; [on|off]";
       }

       if ($val[0] eq "hash") {
         push @cmdBuffer, "fritzloginfo " . join(" ", @val);
         return FRITZBOX_Readout_SetGet_Start $hash->{helper}{TimerCmd};
       } else {
         return FRITZBOX_Get_Fritz_Log_Info_Std( $hash, $val[0], $val[1]);
       }

     } elsif( lc $cmd eq "luainfo")  {

       FRITZBOX_Log $hash, 4, "get $name $cmd [" . int(@val) . "] " . join(" ", @val);

       if ($hash->{fhem}{fwVersion} < 721) {
         FRITZBOX_Log $hash, 2, "FritzOS version must be greater than 7.20";
         return "FritzOS version must be greater than 7.20.";
       }

       return "Wrong number of arguments, usage: get $name argName1 argValue1" if int @val != 1;

       my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

       if ( $val[0] eq "mobileInfo" && $hash->{LUADATA} == 1) {
         $returnStr = FRITZBOX_Get_MobileInfo($hash);

       } elsif ( $val[0] eq "smartHome" && $hash->{LUADATA} == 1) {
         $returnStr = FRITZBOX_Get_SmartHome_Devices_List($hash);

       } elsif ( $val[0] eq "lanDevices" && $hash->{LUADATA} == 1) {
         $returnStr = FRITZBOX_Get_Lan_Devices_List($hash);

       } elsif ( $val[0] eq "vpnShares" && $hash->{LUADATA} == 1) {
         $returnStr = FRITZBOX_Get_VPN_Shares_List($hash);

       } elsif ( $val[0] eq "wlanNeighborhood" && $hash->{LUADATA} == 1) {
         $returnStr = FRITZBOX_Get_WLAN_Environment($hash);

       } elsif ( $val[0] eq "globalFilters" && $hash->{LUADATA} == 1 && ($avmModel =~ "Box")) {
         $hash->{helper}{gFilters} = 0;
         $returnStr = FRITZBOX_Get_WLAN_globalFilters($hash);

       } elsif ( $val[0] eq "ledSettings" && $hash->{LUADATA} == 1) {
         $hash->{helper}{ledSet} = 0;
         $returnStr = FRITZBOX_Get_LED_Settings($hash);

       } elsif ( $val[0] eq "docsisInformation" && $hash->{LUADATA} == 1 && ($avmModel =~ "Box") && (lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]")) {
         $returnStr = FRITZBOX_Get_DOCSIS_Informations($hash);

       } elsif ( $val[0] eq "kidProfiles" && $hash->{LUAQUERY} == 1) {
         $returnStr = FRITZBOX_Get_Kid_Profiles_List($hash);

       } elsif ( $val[0] eq "userInfos" && $hash->{LUAQUERY} == 1) {
         $returnStr = FRITZBOX_Get_User_Info_List($hash);
       }

       return $returnStr;

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

       FRITZBOX_Log $hash, 3, "get $name $cmd ".join(" ", @val);

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
       my @result = FRITZBOX_call_TR064_Cmd( $hash, 1, \@tr064CmdArray );
       my $tmp = Dumper (@result);
       $returnStr .= $tmp;
       return $returnStr;

     } elsif( lc $cmd eq "tr064servicelist" && defined $hash->{SECPORT}) {
       FRITZBOX_Log $hash, 4, "get $name $cmd [" . int(@val) . "] " . join(" ", @val);
       return FRITZBOX_get_TR064_ServiceList ($hash);

     } elsif( lc $cmd eq "soapcommand") {

       FRITZBOX_Log $hash, 3, "get $name $cmd ".join(" ", @val);

       #return "Wrong number of arguments, usage: get $name soapCommand controlURL serviceType serviceCommand"
       #   if int @val != 3;

       my $soap_resp;
       my $control_url     = "upnp/control/aura/ServerVersion";
       my $service_type    = "urn:schemas-any-com:service:aura:1";
       my $service_command = "GetVersion";

       $soap_resp = FRITZBOX_SOAP_Request($hash,$control_url, $service_type, $service_command);
 
       if(defined $soap_resp->{Error}) {
         return "SOAP-ERROR -> " . $soap_resp->{Error};
 
       } elsif ( $soap_resp->{Response} ) {

         my $strCurl = $soap_resp->{Response};
         return "Curl-> " . $strCurl;
       }
     }

     my $list;

     $list .= "luaQuery"                if $hash->{LUAQUERY} == 1;
     $list .= " luaData"                if $hash->{LUADATA} == 1;

     # Eventuell mal eine Liste hinterlegen
     if ($hash->{fhem}{fwVersion} >= 790) {
       $list .= " javaScript";
     }

     $list .= " luaDectRingTone"        if $hash->{LUADATA} == 1;
     $list .= " luaFunction"            if $hash->{LUAQUERY} == 1;

     # luaData
     if (($hash->{LUADATA} == 1 || $hash->{LUAQUERY} == 1) && ($hash->{fhem}{fwVersion} >= 700) ){
       $list .= " luaInfo:";
       $list .= "lanDevices,ledSettings,vpnShares,wlanNeighborhood" if $hash->{LUADATA} == 1;
       $list .= ",mobileInfo,globalFilters" if $hash->{LUADATA} == 1 && ($avmModel =~ "Box");
       $list .= ",smartHome" if $hash->{LUADATA} == 1 && ($avmModel =~ "Box|Smart");
       $list .= ",kidProfiles,userInfos" if $hash->{LUAQUERY} == 1;
       $list .= ",docsisInformation" if $hash->{LUADATA} == 1 && ($avmModel =~ "Box") && (lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]");

       $list .= " smartHomePreDef";
     }

     $list .= " fritzLog" if $hash->{LUADATA} == 1 && ($hash->{fhem}{fwVersion} >= 680);

     $list .= " lanDeviceInfo"          if $hash->{LUADATA} == 1;

     $list .= " tr064Command"           if defined $hash->{SECPORT};
     $list .= " tr064ServiceList:noArg" if defined $hash->{SECPORT};
#     $list .= " soapCommand"            if defined $hash->{SECPORT};

     return "Unknown argument $cmd, choose one of $list" if defined $list;
   }

   return "get command not available";

} # end FRITZBOX_Get

# Proof params for set/get on landeviceID or MAC
#######################################################################
sub FRITZBOX_SetGet_Proof_Params($@) {

   my ($hash, $name, $cmd, $mysearch, @val) = @_;
   $mysearch = "" unless( defined $mysearch);

   FRITZBOX_Log $hash, 4, "set $name $cmd (Fritz!OS: $hash->{fhem}{fwVersionStr})";

   if ($hash->{fhem}{fwVersion} < 721) {
      FRITZBOX_Log $hash, 2, "FritzOS version must be greater than 7.20";
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
         FRITZBOX_Log $hash, 2, "no valid $cmd parameter: " . $val[0] . " or " . $mysearch . " given";
         return "ERROR: no valid $cmd parameter: " . $val[0] . " or " . $mysearch . " given";
      }
   } elsif ( int @val == 1 ) {
      if ($mysearch ne "" && $val[0] =~ /$mysearch/ ) {
        FRITZBOX_Log $hash, 4, "$name $cmd " . join(" ", @val);
        return $val[0];
      } else {
         unless ( $val[0] =~ /^landevice(\d+)$/ || $val[0] =~ /^([0-9a-f]{2}([:-_]|$)){6}$/i ) {
            FRITZBOX_Log $hash, 2, "no valid $cmd parameter: " . $val[0] . " given";
            return "ERROR: no valid $cmd parameter: " . $val[0] . " given";
         }
      }

   } else {
      FRITZBOX_Log $hash, 2, "parameter missing";
      return "ERROR: $cmd parameter missing";
   }

   if ($val[0] =~ /^([0-9a-f]{2}([:-_]|$)){6}$/i) {
      my $mac = $val[0];
         $mac =~ s/:|-/_/g;

      if (exists($hash->{fhem}->{landevice}->{$mac}) eq "") {
         FRITZBOX_Log $hash, 2, "non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }

      unless (defined $hash->{fhem}->{landevice}->{$mac}) {
         FRITZBOX_Log $hash, 2, "non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }

      if ( (split(/\|/, $hash->{fhem}->{landevice}->{$val[0]}))[0] ) {
        $val[0] = (split(/\|/, $hash->{fhem}->{landevice}->{$val[0]}))[0];
      } else {
        $val[0] = $hash->{fhem}->{landevice}->{$val[0]};
      }

   } else {

      if (exists($hash->{fhem}->{landevice}->{$val[0]}) eq "") {
         FRITZBOX_Log $hash, 2, "non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }

      unless (defined $hash->{fhem}->{landevice}->{$val[0]}) {
         FRITZBOX_Log $hash, 2, "non existing landevice: $val[0]";
         return "ERROR: non existing landevice: $val[0]";
      }
   }

   FRITZBOX_Log $hash, 4, "$name $cmd " . join(" ", @val);

   return $val[0];

} # end FRITZBOX_SetGet_Proof_Params

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

   $hash->{SID_RENEW_ERR_CNT} =  $hash->{fhem}{sidErrCount} if defined $hash->{fhem}{sidErrCount};
   $hash->{SID_RENEW_CNT}     += $hash->{fhem}{sidNewCount} if defined $hash->{fhem}{sidNewCount};

   if( defined $hash->{fhem}{sidErrCount} && $hash->{fhem}{sidErrCount} >= AttrVal($name, "maxSIDrenewErrCnt", 5) ) {
      RemoveInternalTimer($hash->{helper}{TimerReadout});

      if ($hash->{APICHECKED} == -1) {
        readingsSingleUpdate( $hash, "state", "stopped while to many network errors", 1 );
        FRITZBOX_Log $hash, 2, "stopped while to many network errors";
      } else {
        readingsSingleUpdate( $hash, "state", "stopped while to many authentication errors", 1 );
        FRITZBOX_Log $hash, 2, "stopped while to many API errors";
      }

      return "ERROR: starting ReadOutTimer not possible: network error.";
   }

   if( $hash->{helper}{timerInActive} && $hash->{fhem}{LOCAL} != 1) {
      FRITZBOX_Log $hash, 2, "stopped while timerInActive and LOCAL != 1";
      RemoveInternalTimer($hash->{helper}{TimerReadout});
      readingsSingleUpdate( $hash, "state", "inactive", 1 );
      $hash->{STATUS} = "active";
      return "ERROR: starting ReadOutTimer not possible: inactiv.";
   }

   if( AttrVal( $name, "disable", 0 ) == 1 && $hash->{fhem}{LOCAL} != 1) {
      FRITZBOX_Log $hash, 2, "stopped while disabled and LOCAL != 1";
      RemoveInternalTimer($hash->{helper}{TimerReadout});
      readingsSingleUpdate( $hash, "state", "disabled", 1 );
      $hash->{STATUS} = "disabled";
      return "ERROR: starting ReadOutTimer not possible: disabled.";
   }

# Set timer value (min. 60)
   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL", 300 );
   $hash->{INTERVAL} = 60     if $hash->{INTERVAL} < 60 && $hash->{INTERVAL} != 0;

   my $interval = $hash->{INTERVAL};

# Set timeout for BlockinCall
   $hash->{TIMEOUT} = AttrVal( $name, "nonblockingTimeOut", 55 );
   $hash->{TIMEOUT} = $interval - 10 if $hash->{TIMEOUT} > $hash->{INTERVAL};
   $hash->{AGENTTMOUT} = AttrVal( $name, "userAgentTimeOut", $hash->{TIMEOUT} - 5);
   $hash->{AGENTTMOUT} = $hash->{TIMEOUT} - 5 if $hash->{AGENTTMOUT} > $hash->{TIMEOUT};

   my $timeout = $hash->{TIMEOUT};

# First run is an API check
   if ( $hash->{APICHECKED} == 0 ) {
      $interval = 65;
      $timeout  = 60;
      readingsSingleUpdate( $hash, "state", "check APIs", 1 );
      $runFn = "FRITZBOX_Set_check_APIs";
   } elsif ( $hash->{APICHECKED} < 0 ) {
      $interval = AttrVal( $name, "reConnectInterval", 180 ) < 55 ? 55 : AttrVal( $name, "reConnectInterval", 180 );
      $timeout  = 60;
      readingsSingleUpdate( $hash, "state", "recheck APIs every $interval seconds", 1 );
      $runFn = "FRITZBOX_Set_check_APIs";
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
      FRITZBOX_Log $hash, 4, "Old readout process still running. Killing old process ".$hash->{helper}{READOUT_RUNNING_PID};
      BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} );
      # stop FHEM, giving a FritzBox some time to free the memory
      delete( $hash->{helper}{READOUT_RUNNING_PID} );
   }

   $hash->{fhem}{LOCAL} = 2   if $hash->{fhem}{LOCAL} == 1;

   unless( exists $hash->{helper}{READOUT_RUNNING_PID} ) {
      $hash->{helper}{READOUT_RUNNING_PID} = BlockingCall($runFn, $name,
                                                       "FRITZBOX_Readout_Done", $timeout,
                                                       "FRITZBOX_Readout_Aborted", $hash);
      $hash->{helper}{READOUT_RUNNING_PID}->{loglevel} = GetVerbose($name);
      FRITZBOX_Log $hash, 4, "Fork process $runFn";
   }
   else {
      FRITZBOX_Log $hash, 4, "Skip fork process $runFn";
   }

   $hash->{STATUS} = "active";

   return "starting ReadOutTimer ...";

} # end FRITZBOX_Readout_Start

##############################################################################################################################################
# Ab hier alle Sub, die für den nonBlocking Timer zuständig sind
##############################################################################################################################################



# Starts the data capturing and sets the new timer
#######################################################################
sub FRITZBOX_Readout_Run_Web($)
{
   my ($name) = @_;
   my $hash = $defs{$name};

   my @roReadings;
   my $returnStr = "";
   my $sid = "";
   my $sidNew = 0;

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

   my $startTime = time();

   $returnStr = FRITZBOX_Readout_Run_Web_LuaQuery($name, \@roReadings, \$sidNew, \$sid);
   return $returnStr if $returnStr =~/Error\|/;

#   if ( (($FW1 == 6 && $FW2 >= 80) || ($FW1 >= 7 && $FW2 >= 21)) && $hash->{LUADATA} == 1) {

   if ( $hash->{fhem}{fwVersion} >= 680 && $hash->{LUADATA} == 1) {
     $returnStr = FRITZBOX_Readout_Run_Web_LuaData($name, \@roReadings, \$sidNew, \$sid);
     return $returnStr if $returnStr =~/Error\|/;
   } else {
     FRITZBOX_Log $hash, 4, "wrong Fritz!OS: $hash->{fhem}{fwVersionStr} or data.lua not available";
   }

   if ( $hash->{TR064} == 1 && $hash->{SECPORT} ) {
     $returnStr = FRITZBOX_Readout_Run_Web_TR064($name, \@roReadings, \$sidNew, \$sid);
     return $returnStr if $returnStr =~/Error\|/;
   } else {
     FRITZBOX_Log $hash, 4, "TR064: $hash->{TR064} or secure Port:" . ($hash->{SECPORT} ? $hash->{SECPORT} : "none") . " not available or wrong Fritz!OS: $hash->{fhem}{fwVersionStr}.";
   }

   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HINWEIS_BOXUSER", "");
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HINWEIS_PASSWORD", "");

   # Ende und Rückkehr zum Hauptprozess

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".calledFrom", "runWeb";

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $sid if $sid ne "";
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidNewCount", $sidNew;
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->WEBCONNECT", 1;

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   $returnStr = join('|', @roReadings );

   FRITZBOX_Log $hash, 4, "Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 4, "Handover to main process (" . length ($returnStr) . "): " . $returnStr;
   return $name."|".encode_base64($returnStr,"");

} # End FRITZBOX_Readout_Run_Web

#######################################################################
# @{$roReadings}
sub FRITZBOX_Readout_Run_Web_LuaQuery($$$$) {

   my ($name, $roReadings, $sidNew, $sid) = @_;
   my $hash = $defs{$name};

   my $result;
   my $rName;
   my %dectFonID;
   my %fonFonID;
   my $startTime = time();
   my $runNo;
   my $host   = $hash->{HOST};
   my $Tag;
   my $Std;
   my $Min;
   my $Sek;

   my $views;
   my $nbViews;

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   my @webCmdArray;
   my $resultData;
   my $tmpData;

   FRITZBOX_Log $hash, 4, "luaQuery - start getting data";

   my $disableBoxReadings = AttrVal($name, "disableBoxReadings", "");

   my $queryStr = "";

   if ($hash->{LuaQueryCmd}{sip_info}{active} && ReadingsNum($name, "box_model", "3490") ne "3490" && AttrVal( $name, "enableSIP", "0")) {
     $hash->{LuaQueryCmd}{sip_info}{AttrVal} = 1;
   } else {
     $hash->{LuaQueryCmd}{sip_info}{AttrVal} = 0;
   }

   foreach my $key (keys %{ $hash->{LuaQueryCmd} }) {
     FRITZBOX_Log $hash, 4, $key . ": " . $hash->{LuaQueryCmd}{$key}{active};
     $queryStr .= "&" . $key . "=" . $hash->{LuaQueryCmd}{$key}{cmd} if $hash->{LuaQueryCmd}{$key}{active} && $hash->{LuaQueryCmd}{$key}{AttrVal};
   }

   FRITZBOX_Log $hash, 4, "ReadOut gestartet: $queryStr";
   $result = FRITZBOX_call_Lua_Query( $hash, $queryStr, "", "luaQuery") ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   return FRITZBOX_Readout_Response($hash, $result, $roReadings) if ( defined $result->{Error} || defined $result->{AuthorizationRequired});

   $$sidNew += $result->{sidNew} if defined $result->{sidNew};
   $$sid    = $result->{sid} if $result->{sid};

   # !!! copes with fw >=6.69 and fw < 7 !!!
   if ( ref $result->{wlanList} ne 'ARRAY' ) {

      FRITZBOX_Log $hash, 4, "Recognized query answer of firmware >=6.69 and < 7";

      my $result2;
      my $newQueryPart;

      # gets WLAN speed for fw >= 6.69 and < 7
      $queryStr="";
      foreach ( @{ $result->{wlanListNew} } ) {
         $newQueryPart = "&" . $_->{_node} . "=wlan:settings/" . $_->{_node}."/speed_rx";
         if (length($queryStr . $newQueryPart) < 4050) {
            $queryStr .= $newQueryPart;
         } else {
            FRITZBOX_Log $hash, 4, "getting WLAN speed for firmware >=6.69 and < 7: " . $queryStr;
            $result2 = FRITZBOX_call_Lua_Query( $hash, $queryStr );

            # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
            return FRITZBOX_Readout_Response($hash, $result2, $roReadings) if ( defined $result2->{Error} || defined $result2->{AuthorizationRequired});

            # $$sidNew += $result2->{sidNew} if defined $result2->{sidNew};

            %{$result} = ( %{$result}, %{$result2 } );
            $queryStr = $newQueryPart;
         }
      }

      # gets LAN-Port for fw >= 6.69 and fw < 7
      foreach ( @{ $result->{lanDeviceNew} } ) {
         $newQueryPart = "&" . $_->{_node} . "=landevice:settings/" . $_->{_node}."/ethernet_port";
         if (length($queryStr . $newQueryPart) < 4050) {
            $queryStr .= $newQueryPart;
         }
         else {
            FRITZBOX_Log $hash, 4, "getting LAN-Port for firmware >=6.69 and < 7: " . $queryStr;
            $result2 = FRITZBOX_call_Lua_Query( $hash, $queryStr );

            # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
            return FRITZBOX_Readout_Response($hash, $result2, $roReadings) if ( defined $result2->{Error} || defined $result2->{AuthorizationRequired});

            # $$sidNew += $result2->{sidNew} if defined $result2->{sidNew};

            %{$result} = ( %{$result}, %{$result2 } );
            $queryStr = $newQueryPart;
         }
      }

      # get missing user-fields for fw >= 6.69
      foreach ( @{ $result->{userProfilNew} } ) {
         $newQueryPart = "&"  . $_->{_node} . "_filter=user:settings/" . $_->{_node} . "/filter_profile_UID";
         $newQueryPart .= "&" . $_->{_node} . "_month=user:settings/"  . $_->{_node} . "/this_month_time";
         $newQueryPart .= "&" . $_->{_node} . "_today=user:settings/"  . $_->{_node} . "/today_time";
         if (length($queryStr.$newQueryPart) < 4050) {
            $queryStr .= $newQueryPart;
         }
         else {
            FRITZBOX_Log $hash, 4, "getting user-field for firmware >=6.69 and < 7: " . $queryStr;
            $result2 = FRITZBOX_call_Lua_Query( $hash, $queryStr );

            # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
            return FRITZBOX_Readout_Response($hash, $result2, $roReadings) if ( defined $result2->{Error} || defined $result2->{AuthorizationRequired});

            # $$sidNew += $result2->{sidNew} if defined $result2->{sidNew};

            %{$result} = ( %{$result}, %{$result2 } );
            $queryStr  = $newQueryPart;
         }
      }

      # Final Web-Query
      FRITZBOX_Log $hash, 4, "final web-query for firmware >=6.69 and < 7: " . $queryStr;
      $result2 = FRITZBOX_call_Lua_Query( $hash, $queryStr );

      # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
      return FRITZBOX_Readout_Response($hash, $result2, $roReadings) if ( defined $result2->{Error} || defined $result2->{AuthorizationRequired});

      # $$sidNew += $result2->{sidNew} if defined $result2->{sidNew};

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

#-------------------------------------------------------------------------------------
# Dect device list

   my %oldDECTDevice;

   #collect current dect-readings (to delete the ones that are inactive or disappeared)
   foreach (keys %{ $hash->{READINGS} }) {
     $oldDECTDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^dect(\d+)_|^dect(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
   }

   my $noDect = AttrVal( $name, "disableDectInfo", "0");

   if ( defined $result->{handsetCount} && $result->{handsetCount} =~ /[1-9]/ ) {

     FRITZBOX_Log $hash, 4, "luaQuery - start getting data: Dect device list";

     $runNo = 0;
     foreach ( @{ $result->{dectUser} } ) {
       my $intern = $_->{Intern};
       my $name = $_->{Name};
       my $id = $_->{Id};
       if ($intern) {
         unless ($noDect) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo,                           $_->{Name} ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_intern",                 $intern ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_alarmRingTone",          $_->{AlarmRingTone0}, "ringtone" ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_intRingTone",            $_->{IntRingTone}, "ringtone" ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_radio",                  $_->{RadioRingID}, "radio" ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_custRingTone",           $_->{G722RingTone} ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_custRingToneName",       $_->{G722RingToneName} ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_imagePath",              $_->{ImagePath} ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_NoRingWithNightSetting", $_->{NoRingWithNightSetting}, "onoff";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_NoRingTimeFlags"       , $_->{NoRingTimeFlags}, "onoff";

           # telcfg:settings/Foncontrol/User/list(Name,NoRingTime,RingAllowed,NoRingTimeFlags,NoRingWithNightSetting)
           if ($_->{NoRingTime}) {
             my $notAllowed;
             if($_->{RingAllowed} eq "1") {
               $notAllowed = "Mo-So";
             } elsif($_->{RingAllowed} eq "2") {
               $notAllowed = "Mo-Fr 00:00-24:00 Sa-So";
             } elsif($_->{RingAllowed} eq "3") {
               $notAllowed = "Sa-So 00:00-24:00 Mo-Fr";
             } elsif($_->{RingAllowed} eq "4" || $_->{RingAllowed} eq "2") {
               $notAllowed = "Sa-So";
             } elsif($_->{RingAllowed} eq "5" || $_->{RingAllowed} eq "3") {
               $notAllowed = "Mo-Fr";
             }

             my $NoRingTime  = $_->{NoRingTime};
             substr($NoRingTime, 2, 0) = ":";
             substr($NoRingTime, 5, 0) = "-";
             substr($NoRingTime, 8, 0) = ":";

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_NoRingTime", $notAllowed . " " . $NoRingTime;
           } else {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$runNo."_NoRingTime", "not defined";
           }

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->$intern->id",   $id ;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->$intern->userId", $runNo;
         }

         $dectFonID{$id}{Intern} = $intern;
         $dectFonID{$id}{User}   = $runNo;
         $dectFonID{$name}       = $runNo;

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "helper->dectFonID->$name", $runNo ;

         foreach (keys %oldDECTDevice) {
           delete $oldDECTDevice{$_} if $_ =~ /^dect${runNo}_|^dect${runNo}/ && defined $oldDECTDevice{$_};
         }
         FRITZBOX_Log $hash, 5, "dect: $name, $runNo";

       }
       $runNo++;
     }

  # Handset der internen Nummer zuordnen
     unless ($noDect) {
       foreach ( @{ $result->{handset} } ) {
         my $dectUserID = $_->{User};
         next if defined $dectUserID eq "";
         my $dectUser = $dectFonID{$dectUserID}{User};
         my $intern = $dectFonID{$dectUserID}{Intern};

         if ($dectUser) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$dectUser."_manufacturer", $_->{Manufacturer};
#           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$dectUser."_model",        $_->{Model}, "model";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$dectUser."_model",        $_->{Productname};
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "dect".$dectUser."_fwVersion",    $_->{FWVersion};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->$intern->brand", $_->{Manufacturer};
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->$intern->model", $_->{Model}, "model";
         }
       }
     }

   # Remove inactive or non existing sip-readings in two steps
     foreach ( keys %oldDECTDevice) {
       # set the sip readings to 'inactive' and delete at next readout
       if ( $oldDECTDevice{$_} ne "inactive" ) {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
       } else {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
       }
     }

     FRITZBOX_Log $hash, 4, "luaQuery - end getting data: Dect device list";
   }

#-------------------------------------------------------------------------------------
# phone device list

   unless (AttrVal( $name, "disableFonInfo", "0")) {

     FRITZBOX_Log $hash, 4, "luaQuery - start getting data: FonInfo";

     $runNo=1;
     foreach ( @{ $result->{fonPort} } ) {
       if ( $_->{Name} )
       {
          my $name = $_->{Name};
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fon".$runNo,           $_->{Name};
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fon".$runNo."_out",    $_->{MSN};
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fon".$runNo."_intern", $runNo;
          $fonFonID{$name} = $runNo;
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, "helper->fonFonID->$name", $runNo ;
       }
       $runNo++;
     }

     FRITZBOX_Log $hash, 4, "luaQuery - end getting data: FonInfo";
   }

#-------------------------------------------------------------------------------------
# Internetradioliste erzeugen
   $runNo = 0;
   $rName = "radio00";
   foreach ( @{ $result->{radio} } ) {
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName,                 $_->{Name};
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->radio->".$runNo, $_->{Name};
      $runNo++;
      $rName = sprintf ("radio%02d",$runNo);
   }
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->radioCount", $runNo;

#-------------------------------------------------------------------------------------
# SIP Lines
   my $boxModel = ReadingsNum($name, "box_model", "3490");
   FRITZBOX_Log $hash, 4, "sip for box-model: " . $boxModel;

   if ($boxModel ne "3490" && AttrVal( $name, "enableSIP", "0")) {

      FRITZBOX_Log $hash, 4, "luaQuery - start getting data: SIPInfo";

      my $sip_in_error = 0;
      my $sip_active = 0;
      my $sip_inactive = 0;
      my %oldSIPDevice;

      #collect current sip-readings (to delete the ones that are inactive or disappeared)
      foreach (keys %{ $hash->{READINGS} }) {
         $oldSIPDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^sip(\d+)_/ && defined $hash->{READINGS}{$_}{VAL};
      }

      foreach ( @{ $result->{sip_info} } ) {
        FRITZBOX_Log $hash, 4, "sip->info: " . $_->{_node} . ": " . $_->{activated};

        my $rName = $_->{_node} . "_" . $_->{displayname};
        $rName =~ s/\+/00/g;

        if ($_->{activated} == 1) {								# sip activated und registriert

          if ($_->{connect} == 2) {								# sip activated und registriert
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, "active";
            delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
            $sip_active ++;
            FRITZBOX_Log $hash, 4, "$rName -> registration ok";
          }
          if ($_->{connect} == 0) {								# sip not activated
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, "inactive";
            delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
            $sip_inactive ++;
            FRITZBOX_Log $hash, 4, "$rName -> not active";
          }
          if ($_->{connect} == 1) {								# error condition for aktivated and unregistrated sips
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, "not registered";
            delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
            $sip_in_error++;
            FRITZBOX_Log $hash, 2, "$rName -> not registered";
          }
        } else {
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, "not in use";
          delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};
          FRITZBOX_Log $hash, 4, "$rName -> not in use";
        }

        delete $oldSIPDevice{$rName} if exists $oldSIPDevice{$rName};

     }

   # Remove inactive or non existing sip-readings in two steps
      foreach ( keys %oldSIPDevice) {
         # set the sip readings to 'inactive' and delete at next readout
         if ( $oldSIPDevice{$_} ne "inactive" ) {
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
         } else {
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
         }
      }

      FRITZBOX_Log $hash, 4, "end";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "sip_error", $sip_in_error;
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "sip_active", $sip_active;
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "sip_inactive", $sip_inactive;

      FRITZBOX_Log $hash, 4, "luaQuery - end getting data: SIPInfo";

   } # end ($boxModel ne "3490")

#-------------------------------------------------------------------------------------
# VPN shares

   if ( AttrVal( $name, "enableVPNShares", "0")) {

     FRITZBOX_Log $hash, 4, "luaQuery - start getting data: VPNShares";

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

       FRITZBOX_Log $hash, 4, "vpn->info: $rName " . $_->{_node} . ": " . $_->{activated} . ": " . $_->{state};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $_->{name};
       delete $oldVPNDevice{$rName} if exists $oldVPNDevice{$rName};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_access_type", "Corp VPN"    if $_->{access_type} == 1;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_access_type", "User VPN"    if $_->{access_type} == 2;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_access_type", "Lan2Lan VPN" if $_->{access_type} == 3;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_access_type", "Wireguard Simple" if $_->{access_type} == 4;
       delete $oldVPNDevice{$rName . "_access_type"} if exists $oldVPNDevice{$rName . "_access_type"};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_remote_ip", $_->{remote_ip} eq "" ? "....":$_->{remote_ip};
       delete $oldVPNDevice{$rName . "_remote_ip"} if exists $oldVPNDevice{$rName . "_remote_ip"};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_activated", $_->{activated};
       delete $oldVPNDevice{$rName . "_activated"} if exists $oldVPNDevice{$rName . "_activated"};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_state", $_->{state} eq "" ? "none":$_->{state};
       delete $oldVPNDevice{$rName . "_state"} if exists $oldVPNDevice{$rName . "_state"};

       if ($_->{access_type} <= 3) {
         if ($_->{connected_since} == 0) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_connected_since", "none";
         } else {
           $Sek = $_->{connected_since};

           $Tag = int($Sek/86400);
           $Std = int(($Sek/3600)-(24*$Tag));
           $Min = int(($Sek/60)-($Std*60)-(1440*$Tag));
           $Sek -= (($Min*60)+($Std*3600)+(86400*$Tag));

           $Std = substr("0".$Std,-2);
           $Min = substr("0".$Min,-2);
           $Sek = substr("0".$Sek,-2);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_connected_since", $_->{connected_since} . " sec = " . $Tag . "T $Std:$Min:$Sek";
         }
         delete $oldVPNDevice{$rName . "_connected_since"} if exists $oldVPNDevice{$rName . "_connected_since"};
       } else {
         if ($_->{connected_since} == 0) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_last_negotiation", "none";
         } else {
           $Sek = (int(time) - $_->{connected_since});
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName . "_last_negotiation", (strftime "%d-%m-%Y %H:%M:%S", localtime($_->{connected_since}));
         }
         delete $oldVPNDevice{$rName . "_last_negotiation"} if exists $oldVPNDevice{$rName . "_last_negotiation"};
       }

     }

   # Remove inactive or non existing vpn-readings in two steps
     foreach ( keys %oldVPNDevice) {
        # set the vpn readings to 'inactive' and delete at next readout
        if ( $oldVPNDevice{$_} ne "inactive" ) {
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
        }
        else {
          FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
        }
     }

     FRITZBOX_Log $hash, 4, "luaQuery - end getting data: VPNShares";

   }

#-------------------------------------------------------------------------------------
# Create WLAN-List

   my %wlanList;
   #to keep compatibility with firmware <= v3.67 and >=7

   if ( ref $result->{wlanList} eq 'ARRAY' ) {
 
      FRITZBOX_Log $hash, 4, "luaQuery - start getting data: wlanList";

      foreach ( @{ $result->{wlanList} } ) {
         my $mac = $_->{mac};
         $mac =~ s/:/_/g;
         # Anscheinend gibt es Anmeldungen sowohl für Repeater als auch für FBoxen
         $wlanList{$mac}{speed} = $_->{speed}   if ! defined $wlanList{$mac}{speed} || $_->{speed} ne "0";
         $wlanList{$mac}{speed_rx} = $_->{speed_rx} if ! defined $wlanList{$mac}{speed_rx} || $_->{speed_rx} ne "0";
         #$wlanList{$mac}{speed_rx} = $result_lan->{$_->{_node}};
         $wlanList{$mac}{rssi} = $_->{rssi} if ! defined $wlanList{$mac}{rssi} || $_->{rssi} ne "0";
         $wlanList{$mac}{is_guest} = $_->{is_guest} if ! defined $wlanList{$mac}{is_guest} || $_->{is_guest} ne "0";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->wlanDevice->".$mac."->speed", $_->{speed};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->wlanDevice->".$mac."->speed_rx", $wlanList{$mac}{speed_rx};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->wlanDevice->".$mac."->rssi", $_->{rssi};
      }

      FRITZBOX_Log $hash, 4, "luaQuery - end getting data: wlanList";
   }

#-------------------------------------------------------------------------------------
# Create LanDevice list and delete inactive devices

   my $allowPassiv = AttrVal( $name, "enablePassivLanDevices", "0");
   my %oldLanDevice;
   my $lDevName = AttrVal( $name, "lanDeviceReading", "mac");

   #collect current mac-readings (to delete the ones that are inactive or disappeared)
   foreach (keys %{ $hash->{READINGS} }) {
      if ($_ =~ /^${lDevName}_/ && defined $hash->{READINGS}{$_}{VAL}) {
        my $mac_ip = $_;
        $mac_ip =~ s/^${lDevName}_//;

        if ( $hash->{fhem}->{landevice}->{$mac_ip} ) {
          if ( (split(/\|/, $hash->{fhem}->{landevice}->{$mac_ip}))[1] ) {
            $oldLanDevice{$_} .= (split(/\|/, $hash->{fhem}->{landevice}->{$mac_ip}))[1] . "|";
          } elsif ((split(/\|/, $hash->{fhem}->{landevice}->{$mac_ip}))[0]) {
            $oldLanDevice{$_} .= (split(/\|/, $hash->{fhem}->{landevice}->{$mac_ip}))[0] . "|";
          } else {
            $oldLanDevice{$_} .= $hash->{fhem}->{landevice}->{$mac_ip} . "|";
          }
        }
        $oldLanDevice{$_} .= $hash->{READINGS}{$_}{VAL};
      }
   }

   %landevice = ();
   my $wlanCount = 0;
   my $gWlanCount = 0;

   if ( ref $result->{lanDevice} eq 'ARRAY' ) {
      #Ipv4,IPv6,lanName,devName,Mbit,RSSI "
      # iPad-Familie [landevice810] (WLAN: 142 / 72 Mbit/s RSSI: -53)

      FRITZBOX_Log $hash, 4, "luaQuery - start getting data: lanDevice";

      my $deviceInfo = AttrVal($name, "deviceInfo", "_defDef_,name,[uid],(connection: speedcomma rssi) statIP");

      $deviceInfo =~ s/\n//g;

      $deviceInfo = "_noDefInf_,_defDef_,name,[uid],(connection: speedcomma rssi) statIP" if $deviceInfo eq "_noDefInf_";

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

      FRITZBOX_Log $hash, 4, "deviceInfo -> " . $deviceInfo;

      foreach ( @{ $result->{lanDevice} } ) {
         my $dIp   = $_->{ip};          # IP Adress
         my $UID   = $_->{UID};         # FritzBoy lan device ID
         my $dName = $_->{name};        # name of the device

         my $dhcp  = $_->{static_dhcp} eq "0" ? "statIP:off" : "statIP:on" if defined $_->{static_dhcp}; # IP is defined as static / dynamic

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->landevice->$dIp", $dName;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->landevice->$UID", $dName;
         $landevice{$dIp} = $dName;
         $landevice{$UID} = $dName;

         my $srTmp = $deviceInfo;

         # lan IPv4 ergänzen
         $srTmp =~ s/ipv4/$dIp/g;

         # lan DeviceName ergänzen
         $srTmp =~ s/name/$dName/g;

         # lan DeviceID ergänzen
         $srTmp =~ s/uid/$UID/g;

         # Create a reading if a landevice is connected
         if ( $_->{active} || $allowPassiv) {
            my $mac = $_->{mac};
            $mac =~ s/:/_/g;
            $mac = $UID if $mac eq "";

            FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->landevice->$mac", $UID . "|" . $dIp;
            $landevice{$mac} = $UID;

            # Copes with fw >= 7
            if ( defined $wlanList{$mac} and !$_->{ethernet_port} and !$_->{ethernetport} ) {
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

            $srTmp =~ s/statIP/${sep}${dhcp}/g if defined $dhcp;

            $srTmp =~ s/rssi${sep}|${sep}rssi|rssi//g;

            if ($defDef) {
               $srTmp =~ s/\(: \, \)//gi;
               $srTmp =~ s/\, \)/ \)/gi;
               $srTmp =~ s/\,\)/\)/gi;

               $srTmp =~ s/\(:/\(/gi;

               $srTmp =~ s/\(\)//g;
            }

            $srTmp = "no match for Informations" if ($srTmp eq "");

            $dIp = $UID if $dIp eq "";
            $mac = $UID if $mac eq "";
            my $rName  = $lDevName . "_";
               $rName .= "pas_" if $allowPassiv && $_->{active} == 0;
               $rName .= $lDevName eq "mac" ? $mac : $dIp;

            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $srTmp ;

            # Remove mac address from oldLanDevice-List
            delete $oldLanDevice{$rName} if exists $oldLanDevice{$rName};
         }
      }

      FRITZBOX_Log $hash, 4, "luaQuery - end getting data: lanDevice";

   }
   FRITZBOX_Readout_Add_Reading ($hash, $roReadings, "box_wlan_Count", $wlanCount);
   FRITZBOX_Readout_Add_Reading ($hash, $roReadings, "box_guestWlanCount", $gWlanCount);

# Remove inactive or non existing mac-readings in two steps
   foreach ( keys %oldLanDevice ) {
      # set the lanDevice readings to 'inactive' and delete at next readout
      if ( $oldLanDevice{$_} !~ /inactive/ ) {
         my $ip = ": ";
         if ($oldLanDevice{$_} =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|landevice\d+)/) {
           $ip .= $1;
         }

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive" . $ip;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
      }
   }

#-------------------------------------------------------------------------------------
# WLANs
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_macFilter_active", $result->{box_macFilter_active}, "onoff";

#-------------------------------------------------------------------------------------
# Dect
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dect", $result->{box_dect}, "onoff";

#-------------------------------------------------------------------------------------
# Music on Hold
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_moh", $result->{box_moh}, "mohtype";

#-------------------------------------------------------------------------------------
# Power Rate
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_powerRate", $result->{box_powerRate};

#-------------------------------------------------------------------------------------
# Box Features
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->is_double_wlan", $result->{box_is_double_wlan}, "01";

#-------------------------------------------------------------------------------------
# Box model, firmware and uptimes

   if($result->{box_uptimeHours} && $result->{box_uptimeHours} ne "no-emu") {
      $Tag = int($result->{box_uptimeHours} / 24);
      $Std = int($result->{box_uptimeHours} - (24 * $Tag));
      $Sek = int($result->{box_uptimeHours} * 3600) + $result->{box_uptimeMinutes} * 60;

      $Std = substr("0" . $Std,-2);
      $Min = substr("0" . $result->{box_uptimeMinutes},-2);

      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_uptime", $Sek . " sec = " . $Tag . "T " . $Std . ":" . $Min . ":00";
   } else {
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_uptime", "no-emu";
   }

   my @fwV = split(/\./, ReadingsVal($name, "box_fwVersion", "0.0.0.error"));
   if ($result->{box_fwVersion}) {
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fwVersion", $result->{box_fwVersion};
      @fwV = split(/\./, $result->{box_fwVersion});
   } else { # Ab Version 6.90
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fwVersion", $result->{box_fwVersion_neu};
      @fwV = split(/\./, $result->{box_fwVersion_neu});
   }
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->fwVersion", substr($fwV[1],0,2) * 100 + substr($fwV[2],0,2);
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->fwVersionStr", substr($fwV[1],0,2) . "." . substr($fwV[2],0,2);

   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fwUpdate",    $result->{box_fwUpdate};

   # Sonderbehandlung für FRITZ!Smart Gateway
   if($avmModel =~ /Smart Gateway/) {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_tr064",     0, "onoff";
   } else {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_tr064",     $result->{box_tr064}, "onoff";
   }

   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_tr069",       $result->{box_tr069}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_upnp",        $result->{box_upnp}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_upnp_control_activated", $result->{box_upnpCtrl}, "onoff";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "->UPNP",          $result->{box_upnp};
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_stdDialPort", $result->{box_stdDialPort}, "dialport";
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_cpuTemp",     $result->{box_cpuTemp};

   # FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv4_Extern",    $result->{box_ipExtern};
   # FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_connect",     $result->{box_connect};

   if ($mesh ne "slave") {
     if ( defined ($result->{dslStatGlobalOut}) && looks_like_number($result->{dslStatGlobalOut}) ) {
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dsl_upStream", sprintf ("%.3f", $result->{dslStatGlobalOut}/1000000);
     }
     if ( defined ($result->{dslStatGlobalIn}) && looks_like_number($result->{dslStatGlobalIn}) ) {
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dsl_downStream", sprintf ("%.3f", $result->{dslStatGlobalIn}/1000000);
     }
   } else {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dsl_upStream", "";
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dsl_downStream", "";
   }

#-------------------------------------------------------------------------------------
# GSM
#FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_modem", $result->{GSM_ModemPresent};
   if (defined $result->{GSM_NetworkState} && $result->{GSM_NetworkState} ne "0") {
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_rssi", $result->{GSM_RSSI};
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_state", $result->{GSM_NetworkState}, "gsmnetstate";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_technology", $result->{GSM_AcT}, "gsmact";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_internet", $result->{UMTS_enabled};
   } else {
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_rssi", "";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_state", "";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_technology", "";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "gsm_internet", "";
   }

#-------------------------------------------------------------------------------------
# Alarm clock
   $runNo = 1;
   foreach ( @{ $result->{alarmClock} } ) {
      next  if $_->{Name} eq "er";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "alarm".$runNo, $_->{Name};
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "alarm".$runNo."_state", $_->{Active}, "onoff";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "alarm".$runNo."_time",  $_->{Time}, "altime";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "alarm".$runNo."_target", $_->{Number}, "alnumber";
      FRITZBOX_Readout_Add_Reading $hash, $roReadings, "alarm".$runNo."_wdays", $_->{Weekdays}, "aldays";
      $runNo++;
   }

#-------------------------------------------------------------------------------------
#Get TAM readings
   $runNo = 1;
   foreach ( @{ $result->{tam} } ) {
      $rName = "tam".$runNo;
      if ($_->{Display} eq "1")
      {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName,           $_->{Name};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_state",  $_->{Active}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_newMsg", $_->{NumNewMessages};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_oldMsg", $_->{NumOldMessages};
      }
# Löchen ausgeblendeter TAMs
      elsif (defined $hash->{READINGS}{$rName} )
      {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName,"";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_state", "";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_newMsg","";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_oldMsg","";
      }
      $runNo++;
   }

#-------------------------------------------------------------------------------------
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
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName,                   $_->{name},            "deviceip";
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_thisMonthTime",  $_->{this_month_time}, "secondsintime";
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_todayTime",      $_->{today_time},      "secondsintime";
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_todaySeconds",   $_->{today_time};
            FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_type",           $_->{type},            "usertype";
         }
         $runNo++;
         $rName = sprintf ("user%02d",$runNo);
      }
   }

#-------------------------------------------------------------------------------------
# user ticket (extension of online time)
   if ( ref $result->{userTicket} eq 'ARRAY' ) {
      $runNo=1;
      my $maxTickets = AttrVal( $name, "userTickets",  1 );
      $rName = "userTicket01";
      foreach ( @{ $result->{userTicket} } ) {
         last     if $runNo > $maxTickets;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $_->{id};
         $runNo++;
         $rName = sprintf ("userTicket%02d",$runNo);
      }
   }

#-------------------------------------------------------------------------------------
# Diversity
   $runNo=1;
   $rName = "diversity1";
   foreach ( @{ $result->{diversity} } ) {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName,          $_->{MSN};
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_state", $_->{Active}, "onoff" ;
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName."_dest",  $_->{Destination};
      $runNo++;
      $rName = "diversity".$runNo;
   }

#-------------------------------------------------------------------------------------
# attr global showInternalValues 0

   FRITZBOX_Readout_Add_Reading $hash, $roReadings, ".box_TodayBytesReceivedHigh", $result->{TodayBytesReceivedHigh};
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, ".box_TodayBytesReceivedLow", $result->{TodayBytesReceivedLow};
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, ".box_TodayBytesSentHigh", $result->{TodayBytesSentHigh};
   FRITZBOX_Readout_Add_Reading $hash, $roReadings, ".box_TodayBytesSentLow", $result->{TodayBytesSentLow};

   FRITZBOX_Log $hash, 4, "luaQuery - end getting data";

   return "";

} # End FRITZBOX_Readout_Run_Web_LuaQuery

 
# informations depending on data.lua
#-------------------------------------------------------------------------------------

#######################################################################
sub FRITZBOX_Readout_Run_Web_LuaData($$$$)
{
   my ($name, $roReadings, $sidNew, $sid) = @_;
   my $hash = $defs{$name};

   my $result;
   my $rName;
   my $startTime = time();
   my $runNo;
   my $host   = $hash->{HOST};
   my $Tag;
   my $Std;
   my $Min;
   my $Sek;

   my $views;
   my $nbViews;

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   my $logFilter = AttrVal($name, "enableLogReadings", "");
   my $enableBoxReading  = AttrVal($name, "enableBoxReadings", "");
   my $disableBoxReading = AttrVal($name, "disableBoxReadings", "");

   my @webCmdArray;
   my $resultData;
   my $tmpData;

   #-------------------------------------------------------------------------------------
   # getting energy monitor
   # xhr 1 lang de page energy xhrId all

   #-------------------------------------------------------------------------------------
   # getting ...
   # xhr 1 lang de page ... xhrId all

   #-------------------------------------------------------------------------------------
   # getting Mesh Role and error notify 

   FRITZBOX_Log $hash, 4, "mesh_role/error notify - start getting data";

   # xhr 1 lang de page wlanmesh xhrId all
   @webCmdArray = ();
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "wlanmesh";
   push @webCmdArray, "xhrId"       => "all";

   $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

   $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data}->{vars});

   #-------------------------------------------------------------------------------------
   # getting error notify 

   if ( $enableBoxReading =~ /box_notify/ && ($hash->{fhem}{fwVersion} >= 700) ) {

     my %oldNotiDevice;
     my $id = 0;
     $rName = "box_notify_";
     my $uid = "";
     my $infText = "keine weitere Information vorhanden";

     #collect current notify-readings (to delete the ones that are inactive or disappeared)
     foreach (keys %{ $hash->{READINGS} }) {
       $oldNotiDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^box_notify_/ && defined $hash->{READINGS}{$_}{VAL};
     }

#     if ($name eq "FritzBox") {
#       my $tmsg  = "<html><div id=\"button\"><button id=\"delLED\" onclick=\"JS:FW_cmd(FW_root+\'?cmd=set ";
#          $tmsg .= $name;
#          $tmsg .= " ledSetting notifyoff:";
#          $tmsg .= "8_1";
#          $tmsg .= "&XHR=1\', function(data){FW_okDialog(data)})\">quittieren</button></div></html>";
#
#       FRITZBOX_Log $hash, 3, "tmsg: \n " . $tmsg;
#       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "a_Test_info", $tmsg;
#
#       my $content = "<html><div id=\"button\"><button id=\"delLED\" onclick=\"JS:FW_cmd(FW_root+\'?cmd=deletereading ";
#          $content .= $name;
#          $content .= " a_Test";
#          $content .= ".*";
#          $content .= "&XHR=1\', function(data){FW_okDialog(data)})\">-solved by FB- Readings löschen</button></div></html>";
#
#       FRITZBOX_Log $hash, 3, "tmsg: \n " . $content;
#       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "a_Test", $content;
#     }

     if ($hash->{fhem}{fwVersion} >= 800) {

       my $result = FRITZBOX_call_javaScript($hash, "boxnotifications");

       if (defined $result->{result}) {

         if ( ref $result->{result} eq 'ARRAY' ) {

           foreach ( @{ $result->{result} } ) {

             my $msg  = '<html>' . $_->{category} . " " . $_->{event_id};

             $uid = $_->{UID};
             my $rUID = $rName . $uid;

             # $msg .= " <a href='/fhem?cmd=set%20" .$name. "%20ledSetting%20notifyoff:" . $uid . $FW_CSRF . "' target='_self'>&lt;quittieren&gt;</a></html>";

             $msg  = "<html><div id=\"button\"><button id=\"delLED\" onclick=\"JS:FW_cmd(FW_root+\'?cmd=set ";
             $msg .= $name;
             $msg .= " ledSetting notifyoff:";
             $msg .= $uid;
             $msg .= "&XHR=1\', function(data){FW_okDialog(data)})\">quittieren</button></div></html>";

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rUID, $msg;
             delete $oldNotiDevice{$rUID} if exists $oldNotiDevice{$rUID};

             my $infResult = FRITZBOX_call_Lua_Query( $hash, "js3/views/dialogs/start-page/notification-center-details.js", "", "luaCall");
             FRITZBOX_Log $hash, 5, "rote LED Info: \n " . $infResult->{result};

             if ($infResult->{result} && $infResult->{result} =~ /^200 OK/) {
               my $iFrame = "";

               if ($infResult->{result} =~ /;case'$uid':return _t.(.*?).;case/) {

                 $infText = $1;

                 $iFrame = "<html><div id='button'><button id='dis' onclick='JS:FW_okDialog(" . '"' .$infText. '"' . ")'>Information anzeigen</button></div></html>";

               } else {

                 $iFrame = "<html><div id='button'><button id='dis' onclick='JS:FW_okDialog(" . '"' .$infText. '"' . ")'>Information anzeigen</button></div></html>";

               }

               $rUID .= "_info";

               FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rUID, $iFrame;
               delete $oldNotiDevice{$rUID} if exists $oldNotiDevice{$rUID};

               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "helper->infoActive->id$uid", 1;
             }

             $id ++;

           }

         }

       }

     } else {
       if (defined $resultData->{data}->{notify}) {
         if ( ref $resultData->{data}->{notify} eq 'ARRAY' ) {

           foreach ( @{ $resultData->{data}->{notify}} ) {

             my ($urlID) = ($_->{url} =~ /hilfe_syslog_(\d+).html/);
             my $msg  = '<html>' . $_->{category} . " " . $_->{event};
             if ($urlID) {
               $msg .= " <a href='http://" . $hash->{HOST} . $_->{url} . "' target='_blank'>" . $urlID . "</a>";
             }

             $uid = $_->{id};
             my $rUID = $rName . $uid;

             # $msg .= " <a href='/fhem?cmd=set%20" .$name. "%20ledSetting%20notifyoff:" . $uid . $FW_CSRF . "' target='_self'>&lt;quittieren&gt;</a></html>";

             $msg  = "<html><div id=\"button\"><button id=\"delLED\" onclick=\"JS:FW_cmd(FW_root+\'?cmd=set ";
             $msg .= $name;
             $msg .= " ledSetting notifyoff:";
             $msg .= $uid;
             $msg .= "&XHR=1\', function(data){FW_okDialog(data)})\">quittieren</button></div></html>";

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rUID, $msg;
             delete $oldNotiDevice{$rUID} if exists $oldNotiDevice{$rUID};

             $infText = $_->{message} if $_->{message};

             my $iFrame = "<html><div id='button'><button id='dis' onclick='JS:FW_okDialog(" . '"' .$infText. '"' . ")'>Information anzeigen</button></div></html>";

             $rUID .= "_info";

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rUID, $iFrame;
             delete $oldNotiDevice{$rUID} if exists $oldNotiDevice{$rUID};

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "helper->infoActive->id$uid", 1;

             $id ++;
           }
         }
       }
     }

     # Remove inactive or non existing sip-readings in two steps
     foreach ( keys %oldNotiDevice) {
       # set the notify readings to 'inactive' and delete at next readout
       my $sKey = $_;

       if ( $oldNotiDevice{$sKey} !~ /solved/ ) {

         my $content = "";

         my $nid = $sKey;
         $nid =~ s/_info//;
         ($nid) = ($nid =~ /^box_notify_(.*)/);

         if ($sKey !~ /_info/) {
           # $content = "<html>-solved by FB- <a href='/fhem?cmd=deletereading%20-q%20" . $name . "%20" . $rName . $nid . ".*" . $FW_CSRF . "' target='_self'>&lt;quittieren&gt;</a></html>";

           $content = "<html><div id=\"button\"><button id=\"delLED\" onclick=\"JS:FW_cmd(FW_root+\'?cmd=deletereading ";
           $content .= $name;
           $content .= " " . $rName;
           $content .= $nid . ".*";
           $content .= "&XHR=1\', function(data){FW_okDialog(data)})\">-solved by FB- Readings löschen</button></div></html>";

         } else {
           $content = $oldNotiDevice{$sKey};
           ($infText) = ($content =~ /'JS:FW_okDialog\("(.*?)"\)'\>/gs);
           $content = "<html><div id='button'><button id='dis' onclick='JS:FW_okDialog(" . '"' .$infText. '"' . ")'>-solved by FB- Information anzeigen</button></div></html>"
         }

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $sKey, $content;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "helper->infoActive->id$nid", "";

       } else {
       }

     }

   }

   #-------------------------------------------------------------------------------------
   # now, evaluating mesh role
   if (defined $resultData->{data}->{vars}->{role}->{value}) {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_meshRole", $resultData->{data}->{vars}->{role}->{value};

     if ($resultData->{data}->{vars}->{role}->{value} ne "slave") {
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalIn->AttrVal", 1;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalOut->AttrVal", 1;

       $hash->{LuaQueryCmd}{dslStatGlobalIn}{AttrVal} = 1;
       $hash->{LuaQueryCmd}{dslStatGlobalOut}{AttrVal} = 1;
     } else {
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalIn->AttrVal", 0;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalOut->AttrVal", 0;

       $hash->{LuaQueryCmd}{dslStatGlobalIn}{AttrVal} = 0;
       $hash->{LuaQueryCmd}{dslStatGlobalOut}{AttrVal} = 0;
     }

   } elsif (defined $resultData->{data}->{rep_data}->{is_repeater}) {

     my $meshRole = $resultData->{data}->{rep_data}->{is_repeater} ? "slave" : "master";

     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_meshRole", $meshRole;

     if ($meshRole ne "slave") {
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalIn->AttrVal", 1;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalOut->AttrVal", 1;

       $hash->{LuaQueryCmd}{dslStatGlobalIn}{AttrVal} = 1;
       $hash->{LuaQueryCmd}{dslStatGlobalOut}{AttrVal} = 1;
     } else {
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalIn->AttrVal", 0;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalOut->AttrVal", 0;

       $hash->{LuaQueryCmd}{dslStatGlobalIn}{AttrVal} = 0;
       $hash->{LuaQueryCmd}{dslStatGlobalOut}{AttrVal} = 0;
     }
   } else {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalIn->AttrVal", 1;
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "LuaQueryCmd->dslStatGlobalOut->AttrVal", 1;

     $hash->{LuaQueryCmd}{dslStatGlobalIn}{AttrVal} = 1;
     $hash->{LuaQueryCmd}{dslStatGlobalOut}{AttrVal} = 1;
   }

   FRITZBOX_Log $hash, 4, "mesh_role/error notify - end getting data";

   #-------------------------------------------------------------------------------------
   # Getting phone WakeUpCall Device Nr
   # uses $dectFonID (# Dect device list) and $dectFonID (phone device list)

   # xhr 1 lang de page alarm xhrId all

   FRITZBOX_Log $hash, 4, "WakeUpCall - start getting data";

   @webCmdArray = ();
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "alarm";
   push @webCmdArray, "xhrId"       => "all";
      
   $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

   $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data});

   my $devname;
   my $device;
   my %devID;

   # proof on redundant phone names
   if (defined $resultData->{data}->{phonoptions}) {
     if ( ref $resultData->{data}->{phonoptions} eq 'ARRAY' ) {

       my $id = 0;

       foreach ( @{ $resultData->{data}->{phonoptions}} ) {
         $devname = $_->{text};
         $device  = $_->{value};

         FRITZBOX_Log $hash, 4, "phone name($id): $devname $device";

         if ($devID{$devname}) {
           my $defNewName = $devname . "[" . $devID{$devname} ."] redundant name in FB:" . $devname;
           $devID{$defNewName} = $devID{$devname};
           $devID{$devname} = "";
           $defNewName = $devname . "[" . $device ."] redundant name in FB:" . $devname;
           $devID{$defNewName} = $device;
         } else {
           $devID{$devname} = $device;
         }

         $id ++;
       }
     }

     my $fonDisable  = AttrVal( $name, "disableFonInfo", "0");
     my $dectDisable = AttrVal( $name, "disableDectInfo", "0");

#     #collect current dect/fon devices (to delete the ones that are inactive or disappeared)
#     my %oldFonDevice;
#     foreach (keys %{ $hash->{READINGS} }) {
#       $oldFonDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^dect(\d+)|fon(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
#     }

     for(keys %devID) {

       next if $devID{$_} eq "";
       $devname = $_;
       $device  = $devID{$_};

       my $dectFonID = $hash->{helper}{dectFonID}{$devname};
       my $fonFonID  = $hash->{helper}{fonFonID}{$devname};

       if ($dectFonID && !$dectDisable) {
         $rName = "dect" . $dectFonID . "_device";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $device;
#         foreach ( keys %oldFonDevice ) {
#           delete $oldFonDevice{$_} if exists $oldFonDevice{$_} && ( $_ =~ /^dect${dectFonID}/ );
#         }
       }

       if ($fonFonID && !$fonDisable) {
         $rName = "fon"  . $fonFonID  . "_device";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $device;
#         delete $oldFonDevice{$rName} if exists $oldFonDevice{$rName};
       }

       if (!$fonFonID && !$dectFonID && !$fonDisable) {
         $rName = "fon" . $device;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $devname ;
#         delete $oldFonDevice{$rName} if exists $oldFonDevice{$rName};

         $rName = "fon" . $device . "_device";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $device ;
#         delete $oldFonDevice{$rName} if exists $oldFonDevice{$rName};
       }

       $devname =~ s/\|/&#0124/g;

       my $fd_devname = "fdn_" . $devname;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->$fd_devname", $device;

       my $fd_device = "fd_" . $device;
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fhem->$fd_device", $devname;
     }

#     # Remove inactive or non existing dect/fon devices-readings in two steps
#     foreach ( keys %oldFonDevice ) {
#       # set the dect/fon devices readings to 'inactive' and delete at next readout
#       if ( $oldFonDevice{$_} ne "inactive" ) {
#         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
#       } else {
#         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
#       }
#     }
   }

   FRITZBOX_Log $hash, 4, "WakeUpCall - end getting data";
 
   #-------------------------------------------------------------------------------------
   # WLAN neighbors

   # "xhr 1 lang de page chan xhrId environment useajax 1;

   if ( AttrVal( $name, "enableWLANneighbors", "0") ) {

     FRITZBOX_Log $hash, 4, "enableWLANneighbors - start getting data";

     @webCmdArray = ();
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "chan";
     push @webCmdArray, "xhrId"       => "environment";

     $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

     $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

     FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data}->{scanlist});

     my $nbhPrefix = AttrVal( $name, "wlanNeighborsPrefix",  "nbh_" );
     my %oldWanDevice;

     #collect current mac-readings (to delete the ones that are inactive or disappeared)
     foreach (keys %{ $hash->{READINGS} }) {
       $oldWanDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^${nbhPrefix}/ && defined $hash->{READINGS}{$_}{VAL};
     }

     $nbViews = 0;
     if (defined $resultData->{data}->{scanlist}) {
       $views = $resultData->{data}->{scanlist};
       $nbViews = scalar @$views;
     }

     if ($nbViews > 0) {

       eval {
         for(my $i = 0; $i <= $nbViews - 1; $i++) {
           my $dName = $resultData->{data}->{scanlist}->[$i]->{ssid};
           $dName   .= " (Kanal: " . $resultData->{data}->{scanlist}->[$i]->{channel};
           if ($hash->{fhem}{fwVersion} >= 750) {
             $dName   .= ", Band: " . $resultData->{data}->{scanlist}->[$i]->{bandId};
             $dName   =~ s/24ghz/2.4 GHz/;
             $dName   =~ s/5ghz/5 GHz/;
           }
           $dName  .= ")";

           $rName  = $resultData->{data}->{scanlist}->[$i]->{mac};
           $rName =~ s/:/_/g;
           $rName  = $nbhPrefix . $rName;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $dName;
           delete $oldWanDevice{$rName} if exists $oldWanDevice{$rName};
         }
       };

       $rName  = "box_wlan_lastScanTime";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, $rName, $resultData->{data}->{lastScantime};
       delete $oldWanDevice{$rName} if exists $oldWanDevice{$rName};
     }

     # Remove inactive or non existing wan-readings in two steps
     foreach ( keys %oldWanDevice ) {
       # set the wan readings to 'inactive' and delete at next readout
       if ( $oldWanDevice{$_} ne "inactive" ) {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
       } else {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
       }
     }

     FRITZBOX_Log $hash, 4, "enableWLANneighbors - end getting data";

   } else {
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_lastScanTime", "";
   }

   #-------------------------------------------------------------------------------------
   # kid profiles
   # xhr 1 lang de page kidPro

   if (AttrVal( $name, "enableKidProfiles", "0") ) {

     FRITZBOX_Log $hash, 4, "enableKidProfiles - start getting data";

     my %oldKidDevice;

     #collect current kid-readings (to delete the ones that are inactive or disappeared)
     foreach (keys %{ $hash->{READINGS} }) {
       $oldKidDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^kidprofile/ && defined $hash->{READINGS}{$_}{VAL};
     }

     my @webCmdArray;
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "kidPro";

     my $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

     $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "kidprofile2", "unbegrenzt [filtprof3]";

     my $views = $resultData->{data}->{kidProfiles};

     eval {
       foreach my $key (keys %$views) {
         FRITZBOX_Log $hash, 4, "Kid Profiles: " . $key;

         my $kProfile = $resultData->{data}->{kidProfiles}->{$key}{Name} . " [" . $resultData->{data}->{kidProfiles}->{$key}{Id} ."]";

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "kid" . $key, $kProfile;
         delete $oldKidDevice{"kid" . $key} if exists $oldKidDevice{"kid" . $key};
       }
     };

     # Remove inactive or non existing kid-readings in two steps
     foreach ( keys %oldKidDevice ) {
       # set the wan readings to 'inactive' and delete at next readout
       if ( $oldKidDevice{$_} ne "inactive" ) {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
       } else {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
       }
     }

     FRITZBOX_Log $hash, 4, "enableKidProfiles - end getting data";

   }

   #-------------------------------------------------------------------------------------
   # WLAN log expanded status

   # xhr 1 lang de page log xhrId log filter wlan

   if ($logFilter =~ /box_wlan_Log/) {

     FRITZBOX_Log $hash, 4, "LOG_WLAN - start getting data: $logFilter";

     @webCmdArray = ();
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "log";
     push @webCmdArray, "xhrId"       => "log";

     if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
       push @webCmdArray, "filter"      => "4";
     } elsif ($hash->{fhem}{fwVersion} >= 750) {
       push @webCmdArray, "filter"      => "wlan";
     }

     $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

     $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

     $tmpData = $resultData->{data}->{wlan} ? "on" : "off";
     FRITZBOX_Log $hash, 4, "wlanLogExtended -> " . $tmpData;
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_LogExtended", $tmpData;

     if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
       if ( defined $resultData->{data}->{filter} && $resultData->{data}->{filter} eq "4" && defined $resultData->{data}->{log}->[0]) {
         $tmpData = $resultData->{data}->{log}->[0][3] . " " . $resultData->{data}->{log}->[0][0] . " " . $resultData->{data}->{log}->[0][1] ;
         FRITZBOX_Log $hash, 4, "wlanLogLast -> " . $tmpData;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_LogNewest", $tmpData;
       } else {
         FRITZBOX_Log $hash, 4, "wlanLogLast -> none";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_LogNewest", "none";
       }
     } elsif ($hash->{fhem}{fwVersion} >= 750) {
       if ( defined $resultData->{data}->{filter} && $resultData->{data}->{filter} eq "wlan" && defined $resultData->{data}->{log}->[0]) {
         $tmpData = $resultData->{data}->{log}->[0]->{id} . " " . $resultData->{data}->{log}->[0]->{date} . " " . $resultData->{data}->{log}->[0]->{time} ;
         FRITZBOX_Log $hash, 4, "wlanLogLast -> " . $tmpData;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_LogNewest", $tmpData;
       } else {
         FRITZBOX_Log $hash, 4, "wlanLogLast -> none";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_LogNewest", "none";
       }
     }

     FRITZBOX_Log $hash, 4, "LOG_WLAN - end getting data: $logFilter";
   }

   #-------------------------------------------------------------------------------------
   # SYS log

   # xhr 1 lang de page log xhrId log filter sys

   if ($logFilter =~ /box_sys_Log/) {

     FRITZBOX_Log $hash, 4, "LOG_SYS - start getting data: $logFilter";

     # xhr 1 lang de page log xhrId log filter sys
     @webCmdArray = ();
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "log";
     push @webCmdArray, "xhrId"       => "log";

     if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
       push @webCmdArray, "filter"      => "1";
     } elsif ($hash->{fhem}{fwVersion} >= 750) {
       push @webCmdArray, "filter"      => "sys";
     }

     $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

     $$sidNew += $result->{sidNew} if defined $result->{sidNew};

     if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
       if ( defined $resultData->{data}->{filter} && $resultData->{data}->{filter} eq "1" && defined $resultData->{data}->{log}->[0]) {
         $tmpData = $resultData->{data}->{log}->[0][3] . " " . $resultData->{data}->{log}->[0][0] . " " . $resultData->{data}->{log}->[0][1] ;
         FRITZBOX_Log $hash, 4, "wlanLogLast -> " . $tmpData;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_sys_LogNewest", $tmpData;
       } else {
         FRITZBOX_Log $hash, 4, "wlanLogLast -> none";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_sys_LogNewest", "none";
       }
     } elsif ($hash->{fhem}{fwVersion} >= 750) {
       if ( defined $resultData->{data}->{filter} && $resultData->{data}->{filter} eq "sys" && defined $resultData->{data}->{log}->[0]) {
         $tmpData = $resultData->{data}->{log}->[0]->{id} . " " . $resultData->{data}->{log}->[0]->{date} . " " . $resultData->{data}->{log}->[0]->{time} ;
         FRITZBOX_Log $hash, 4, "wlanLogLast -> " . $tmpData;
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_sys_LogNewest", $tmpData;
       } else {
         FRITZBOX_Log $hash, 4, "wlanLogLast -> none";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_sys_LogNewest", "none";
       }
     }

     FRITZBOX_Log $hash, 4, "LOG_SYS - end getting data: $logFilter";
   }

   #-------------------------------------------------------------------------------------
   # info about LED settings

   if ( $enableBoxReading =~ /box_led/ && ($hash->{fhem}{fwVersion} >= 700) ) {

     FRITZBOX_Log $hash, 4, "BOX_LED - start getting data: $enableBoxReading";

     # "xhr 1 lang de page led xhrId all;

     @webCmdArray = ();
     push @webCmdArray, "xhr"         => "1";
     push @webCmdArray, "lang"        => "de";
     push @webCmdArray, "page"        => "led";
     push @webCmdArray, "xhrId"       => "all";

     $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

     $$sidNew += $result->{sidNew} if defined $result->{sidNew};

     FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data}->{ledSettings});

     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ledDisplay",  $resultData->{data}->{ledSettings}->{ledDisplay}?"off":"on";
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ledHasEnv",   $resultData->{data}->{ledSettings}->{hasEnv}?"yes":"no";
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ledEnvLight", $resultData->{data}->{ledSettings}->{envLight}?"on":"off" if $resultData->{data}->{ledSettings}->{hasEnv};
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ledCanDim",   $resultData->{data}->{ledSettings}->{canDim}?"yes":"no";
     FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ledDimValue", $resultData->{data}->{ledSettings}->{dimValue} if $resultData->{data}->{ledSettings}->{canDim};

     FRITZBOX_Log $hash, 4, "BOX_LED - end getting data: $enableBoxReading";

   }
   # end info about LED settings


   if ( $avmModel =~ /Smart/) {
   #-------------------------------------------------------------------------------------

     #-------------------------------------------------------------------------------------
     # getting matter network
     # xhr 1 lang de page sh_matter xhrId all

     if ( $hash->{fhem}{fwVersion} >= 762) {

       FRITZBOX_Log $hash, 4, "Matter detailed info - start getting data";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "sh_matter";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       $nbViews = 0;

       if (defined $resultData->{data}->{fabrics}) {
         $views = $resultData->{data}->{fabrics};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         for(my $i = 0; $i <= $nbViews - 1; $i++) {
           my $id = $resultData->{data}->{fabrics}->[$i]->{UID};
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "matter_" . $id . "_vendor", $resultData->{data}->{fabrics}->[$i]->{vendor};
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "matter_" . $id . "_node", $resultData->{data}->{fabrics}->[$i]->{_node};
         }
       }

       FRITZBOX_Log $hash, 4, "Matter detailed info - end getting data";
     } else {

       FRITZBOX_Log $hash, 4, "wrong Fritz!OS for Matter detailed informations: $hash->{fhem}{fwVersionStr}";

     }

   }

   if ( $avmModel !~ /Smart/) {
   #-------------------------------------------------------------------------------------

     #-------------------------------------------------------------------------------------
     # getting energy monitor
     # xhr 1 lang de page energy xhrId all

     if ( ($enableBoxReading =~ /box_pwr/) && (($hash->{fhem}{fwVersion} >= 680 && $avmModel !~ /Cable/) || ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 790 && $avmModel =~ /Cable/)) ) {

       FRITZBOX_Log $hash, 4, "Energy detailed info - start getting data";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "energy";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       $nbViews = 0;

       if (defined $resultData->{data}->{drain}) {
         $views = $resultData->{data}->{drain};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         for(my $i = 0; $i <= $nbViews - 1; $i++) {
           my $id = $resultData->{data}->{drain}->[$i]->{id};
           if ( $resultData->{data}->{drain}->[$i]->{name} =~ /Gesamtsystem/) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_pwr_Rate_Act", $resultData->{data}->{drain}->[$i]->{actPerc};
           } elsif ( $resultData->{data}->{drain}->[$i]->{name} =~ /Hauptprozessor/) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_pwr_mainCPU_Act", $resultData->{data}->{drain}->[$i]->{actPerc};
           } elsif ( $resultData->{data}->{drain}->[$i]->{name} =~ /WLAN/) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_pwr_WLAN_Act", $resultData->{data}->{drain}->[$i]->{actPerc};
           } elsif ( $resultData->{data}->{drain}->[$i]->{name} =~ /DSL/) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_pwr_DSL_Act", $resultData->{data}->{drain}->[$i]->{actPerc};
           }

         }
       }

       FRITZBOX_Log $hash, 4, "Energy detailed info - end getting data";
     } else {

       FRITZBOX_Log $hash, 4, "wrong Fritz!OS for Energy detailed informations: $hash->{fhem}{fwVersionStr}";

     }

     #-------------------------------------------------------------------------------------
     # WLAN Gastzugang

     # xhr 1
     # lang de
     # page wGuest 
     # xhrId all
     # xhr 1 lang de page wGuest xhrId all

     if ( ($hash->{fhem}{fwVersion} >= 700) && ($enableBoxReading =~ /box_guestWlan/)) {

       FRITZBOX_Log $hash, 4, "WLAN detailed info - start getting data";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "wGuest";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlan_SSID", $resultData->{data}->{guestAccess}->{ssid};
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlan_defPubSSID", $resultData->{data}->{guestAccess}->{defaultSsid}->{public};
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlan_defPrivSSID", $resultData->{data}->{guestAccess}->{defaultSsid}->{private};
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlan_groupAccess", $resultData->{data}->{guestAccess}->{guestGroupAccess}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_guestWlan_tmoActive", $resultData->{data}->{guestAccess}->{isTimeoutActive}, "onoff";

       # FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_powerLine", $resultData->{data}->{guestAccess}->{isPowerline} * 1, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_powerLine", $resultData->{data}->{guestAccess}->{isPowerline}, "onoff";

       FRITZBOX_Log $hash, 4, "WLAN detailed info - end getting data";
     } else {

       FRITZBOX_Log $hash, 4, "wrong Fritz!OS for Guest WLAN detailed informations: $hash->{fhem}{fwVersionStr}";

     }

   }

   if ( $avmModel =~ /Box|Smart/) {
   #-------------------------------------------------------------------------------------

     #-------------------------------------------------------------------------------------
     # get list of SmartHome groups / devices

     my $SmartHome = AttrVal($name, "enableSmartHome", "off");

     if ($SmartHome ne "off" && ($hash->{fhem}{fwVersion} >= 700) ) {

       FRITZBOX_Log $hash, 4, "SmartHome - start getting data: $SmartHome";

       my %oldSmartDevice;

       #collect current dect-readings (to delete the ones that are inactive or disappeared)
       foreach (keys %{ $hash->{READINGS} }) {
         $oldSmartDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^shdevice(\d+)|^shgroup(\d+)/ && defined $hash->{READINGS}{$_}{VAL};
       }

       # xhr 1 lang de page sh_dev xhrid all
       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "sh_dev";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $result->{sidNew} if defined $result->{sidNew};

       if ($SmartHome =~ /all|group/) {

         $nbViews = 0;

         if (defined $resultData->{data}->{groups}) {
           $views = $resultData->{data}->{groups};
           $nbViews = scalar @$views;
         }

         if ($nbViews > 0) {

           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             my $id = $resultData->{data}->{groups}->[$i]->{id};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shgroup" . $id,               $resultData->{data}->{groups}->[$i]->{displayName};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shgroup" . $id . "_device",   $resultData->{data}->{groups}->[$i]->{id};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shgroup" . $id . "_type",     $resultData->{data}->{groups}->[$i]->{type};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shgroup" . $id . "_category", $resultData->{data}->{groups}->[$i]->{category};

             foreach (keys %oldSmartDevice) {
               delete $oldSmartDevice{$_} if $_ =~ /^shgroup${id}_|^shgroup${id}/ && defined $oldSmartDevice{$_};
             }
           }
         }
       }

       if ($SmartHome =~ /all|device/ ) {
         $nbViews = 0;

         if (defined $resultData->{data}->{devices}) {
           $views = $resultData->{data}->{devices};
           $nbViews = scalar @$views;
         }

         if ($nbViews > 0) {

           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             my $id = $resultData->{data}->{devices}->[$i]->{id};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id,                      $resultData->{data}->{devices}->[$i]->{displayName};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_device",          $resultData->{data}->{devices}->[$i]->{id};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_type",            $resultData->{data}->{devices}->[$i]->{type};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_category",        $resultData->{data}->{devices}->[$i]->{category};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_manufacturer",    $resultData->{data}->{devices}->[$i]->{manufacturer}->{name};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_model",           $resultData->{data}->{devices}->[$i]->{model};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_firmwareVersion", $resultData->{data}->{devices}->[$i]->{firmwareVersion}->{current};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_status",          $resultData->{data}->{devices}->[$i]->{masterConnectionState};

             if ( $resultData->{data}->{devices}->[$i]->{units} ) {
               my $units = $resultData->{data}->{devices}->[$i]->{units};
               for my $unit (0 .. scalar @{$units} - 1) {
                 if( $units->[$unit]->{'type'} eq 'THERMOSTAT' ) {

                 } elsif ( $units->[$unit]->{'type'} eq 'TEMPERATURE_SENSOR' ) {
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_temperature", $units->[$unit]->{skills}->[0]->{currentInCelsius};
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_tempOffset",  $units->[$unit]->{skills}->[0]->{offset};

                 } elsif ( $units->[$unit]->{'type'} eq 'HUMIDITY_SENSOR' ) {
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_humidity",    $units->[$unit]->{skills}->[0]->{currentInPercent};

                 } elsif ( $units->[$unit]->{'type'} eq 'BATTERY' ) {
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_battery",     $units->[$unit]->{skills}->[0]->{chargeLevelInPercent};

                 } elsif ( $units->[$unit]->{'type'} eq 'SOCKET' ) {
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_voltage",     $units->[$unit]->{skills}->[0]->{voltageInVolt};
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_power",       $units->[$unit]->{skills}->[0]->{powerPerHour};
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_current",     $units->[$unit]->{skills}->[0]->{electricCurrentInAmpere};
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_consumtion",  $units->[$unit]->{skills}->[0]->{powerConsumptionInWatt};
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_ledState",    $units->[$unit]->{skills}->[1]->{ledState};
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "shdevice" . $id . "_state",       $units->[$unit]->{skills}->[2]->{state};

                 } elsif ( $units->[$unit]->{'type'} eq 'DETECTOR' ) {
                 }
               }
             }

             foreach (keys %oldSmartDevice) {
               delete $oldSmartDevice{$_} if $_ =~ /^shdevice${id}_|^shdevice${id}/ && defined $oldSmartDevice{$_};
             }
           }
         }
       }
       # Remove inactive or non existing sip-readings in two steps

       foreach ( keys %oldSmartDevice) {
         # set the sip readings to 'inactive' and delete at next readout
         if ( $oldSmartDevice{$_} ne "inactive" ) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
         } else {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
         }
       }

       FRITZBOX_Log $hash, 4, "SmartHome - end getting data: $SmartHome";

     }
   }

   if ( $avmModel =~ "Box") {
   #-------------------------------------------------------------------------------------

     #-------------------------------------------------------------------------------------
     # DSL Verbindungsinformationen

     # xhr 1
     # lang de
     # page dslOv
     # xhrId all
     # xhr 1 lang de page dslOv xhrId all

     #-------------------------------------------------------------------------------------
     # USB Storage

     # xhr 1 lang de page usbOv xhrId all

     if ( ($hash->{fhem}{fwVersion} >= 700) && ($enableBoxReading =~ /box_usb/) ) {

       FRITZBOX_Log $hash, 4, "USB Information - start getting data";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "usbOv";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       #  $resultData->{data}->{usbOverview}->{isFTPStorageEnabled} = 0   unless $resultData->{data}->{usbOverview}->{isFTPStorageEnabled};
       #  $resultData->{data}->{usbOverview}->{isFTPServerEnabled} = 0    unless $resultData->{data}->{usbOverview}->{isFTPServerEnabled};
       #  $resultData->{data}->{usbOverview}->{isNASEnabled} = 0          unless $resultData->{data}->{usbOverview}->{isNASEnabled};
       #  $resultData->{data}->{usbOverview}->{isSMBv1Enabled} = 0        unless $resultData->{data}->{usbOverview}->{isSMBv1Enabled};
       #  $resultData->{data}->{usbOverview}->{isWebdavEnabled} = 0       unless $resultData->{data}->{usbOverview}->{isWebdavEnabled};
       #  $resultData->{data}->{usbOverview}->{isAutoIndexingEnabled} = 0 unless $resultData->{data}->{usbOverview}->{isAutoIndexingEnabled};

       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_FTP_activ",    $resultData->{data}->{usbOverview}->{isFTPStorageEnabled} * 1, "onoff";
       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_FTP_enabled",  $resultData->{data}->{usbOverview}->{isFTPServerEnabled} * 1, "onoff";
       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_NAS_enabled",  $resultData->{data}->{usbOverview}->{isNASEnabled} * 1, "onoff";
       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_SMB_enabled",  $resultData->{data}->{usbOverview}->{isSMBv1Enabled} * 1, "onoff";
       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_webDav",       $resultData->{data}->{usbOverview}->{isWebdavEnabled} * 1, "onoff";
       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_autoIndex",    $resultData->{data}->{usbOverview}->{isAutoIndexingEnabled} * 1, "onoff";
       #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_indexStatus",  $resultData->{data}->{usbOverview}->{indexingStatus};

       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_FTP_activ",    $resultData->{data}->{usbOverview}->{isFTPStorageEnabled}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_FTP_enabled",  $resultData->{data}->{usbOverview}->{isFTPServerEnabled}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_NAS_enabled",  $resultData->{data}->{usbOverview}->{isNASEnabled}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_SMB_enabled",  $resultData->{data}->{usbOverview}->{isSMBv1Enabled}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_webDav",       $resultData->{data}->{usbOverview}->{isWebdavEnabled}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_autoIndex",    $resultData->{data}->{usbOverview}->{isAutoIndexingEnabled}, "onoff";
       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_indexStatus",  $resultData->{data}->{usbOverview}->{indexingStatus};

       $nbViews = 0;
       if (defined $resultData->{data}->{usbOverview}->{devices}) {
         $views = $resultData->{data}->{usbOverview}->{devices};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {
         my $i = 0;
         eval {
           for( $i = 0; $i <= $nbViews - 1; $i++) {

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devID",           $resultData->{data}->{usbOverview}->{devices}->[$i]->{id};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devType",         $resultData->{data}->{usbOverview}->{devices}->[$i]->{deviceType};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devName",         $resultData->{data}->{usbOverview}->{devices}->[$i]->{deviceName};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devStatus",       $resultData->{data}->{usbOverview}->{devices}->[$i]->{storageStatus};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devConType",      $resultData->{data}->{usbOverview}->{devices}->[$i]->{connectionType};
           #  FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devEject",        $resultData->{data}->{usbOverview}->{devices}->[$i]->{isEjectable} * 1, "onoff";
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devEject",        $resultData->{data}->{usbOverview}->{devices}->[$i]->{isEjectable}, "onoff";
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devStorageUsed",  $resultData->{data}->{usbOverview}->{devices}->[$i]->{partitions}->[0]->{usedStorageInBytes};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_usb_${i}_devStorageTotal", $resultData->{data}->{usbOverview}->{devices}->[$i]->{partitions}->[0]->{totalStorageInBytes};

           }
         }

       }

       FRITZBOX_Log $hash, 4, "USB Information - end getting data";
     } else {

       FRITZBOX_Log $hash, 4, "wrong Fritz!OS for USB Information: $hash->{fhem}{fwVersionStr}" if $enableBoxReading =~ /box_usb/;

     }

     #-------------------------------------------------------------------------------------
     # INET Monitor

     # xhr 1 lang de page netMoni xhrId all

     if ( ($hash->{fhem}{fwVersion} >= 731) && ($enableBoxReading =~ /box_dns_Srv/)) {

       FRITZBOX_Log $hash, 4, "NET_Monitor - start getting data";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "netMoni";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       $nbViews = 0;
       if (defined $resultData->{data}->{connections}) {
         $views = $resultData->{data}->{connections};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {
         my $i = 0;
         my $j = 0;

         eval {
           for( $i = 0; $i <= $nbViews - 1; $i++) {

             my $nbViews2nd = 0;

             if (defined $resultData->{data}->{connections}->[$i]->{ipv4}->{dns}) {
               $views = $resultData->{data}->{connections}->[$i]->{ipv4}->{dns};
               $nbViews2nd = scalar @$views;
             }

             if ($nbViews2nd > 0) {

               eval {
                 for(my $j = 0; $j <= $nbViews2nd - 1; $j++) {
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dns_Srv" . $i . "_used_IPv4_" .$j, $resultData->{data}->{connections}->[$i]->{ipv4}->{dns}->[$j]->{ip};
                 }
               }
             }

             if (defined $resultData->{data}->{connections}->[$i]->{ipv6}->{dns}) {
               $views = $resultData->{data}->{connections}->[$i]->{ipv6}->{dns};
               $nbViews2nd = scalar @$views;
             }

             if ($nbViews2nd > 0) {

               eval {
                 for($j = 0; $j <= $nbViews2nd - 1; $j++) {
                   FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dns_Srv" . $i . "_used_IPv6_" .$j, $resultData->{data}->{connections}->[$i]->{ipv6}->{dns}->[$j]->{ip};
                 }
               }
             }

           }
         }

       }

       FRITZBOX_Log $hash, 4, "NET_Monitor - end getting data";
     } else {

       FRITZBOX_Log $hash, 4, "wrong Fritz!OS for active DNS servers: $hash->{fhem}{fwVersionStr}" if $enableBoxReading =~ /box_dns_Srv/;

     }

     #-------------------------------------------------------------------------------------
     # FON log

     # xhr 1 lang de page log xhrId log filter fon

     if ($logFilter =~ /box_fon_Log/) {

       FRITZBOX_Log $hash, 4, "LOG_FON - start getting data: $logFilter";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "log";
       push @webCmdArray, "xhrId"       => "log";

       if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
         push @webCmdArray, "filter"      => "3";
       } elsif ($hash->{fhem}{fwVersion} >= 750) {
         push @webCmdArray, "filter"      => "fon";
       }

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
         if ( defined $resultData->{data}->{filter} && $resultData->{data}->{filter} eq "3" && defined $resultData->{data}->{log}->[0]) {
           $tmpData = $resultData->{data}->{log}->[0][3] . " " . $resultData->{data}->{log}->[0][0] . " " . $resultData->{data}->{log}->[0][1] ;
           FRITZBOX_Log $hash, 4, "wlanLogLast -> " . $tmpData;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fon_LogNewest", $tmpData;
         } else {
           FRITZBOX_Log $hash, 4, "wlanLogLast -> none";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fon_LogNewest", "none";
         }
       } elsif ($hash->{fhem}{fwVersion} >= 750) {
         if ( defined $resultData->{data}->{filter} && $resultData->{data}->{filter} eq "fon" && defined $resultData->{data}->{log}->[0]) {
           $tmpData = $resultData->{data}->{log}->[0]->{id} . " " . $resultData->{data}->{log}->[0]->{date} . " " . $resultData->{data}->{log}->[0]->{time} ;
           FRITZBOX_Log $hash, 4, "wlanLogLast -> " . $tmpData;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fon_LogNewest", $tmpData;
         } else {
           FRITZBOX_Log $hash, 4, "wlanLogLast -> none";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_fon_LogNewest", "none";
         }
       }

       FRITZBOX_Log $hash, 4, "LOG_FON - end getting data: $logFilter ";
     }

     #-------------------------------------------------------------------------------------
     if ( $hash->{fhem}{fwVersion} >= 721 ) {

       #-------------------------------------------------------------------------------------
       # get list of global filters

       if ($enableBoxReading =~ /box_globalFilter/) {

         FRITZBOX_Log $hash, 4, "globalFilter - start getting data: $enableBoxReading";

         # "xhr 1 lang de page trafapp xhrId all;

         @webCmdArray = ();
         push @webCmdArray, "xhr"         => "1";
         push @webCmdArray, "lang"        => "de";
         push @webCmdArray, "page"        => "trafapp";
         push @webCmdArray, "xhrId"       => "all";

         $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

         # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
         return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

         $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

         FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data}->{filterList});

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_globalFilterStealth", $resultData->{data}->{filterList}->{isGlobalFilterStealth}?"on":"off";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_globalFilterSmtp",    $resultData->{data}->{filterList}->{isGlobalFilterSmtp}?"on":"off";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_globalFilterNetbios", $resultData->{data}->{filterList}->{isGlobalFilterNetbios}?"on":"off";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_globalFilterTeredo",  $resultData->{data}->{filterList}->{isGlobalFilterTeredo}?"on":"off";
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_globalFilterWpad",    $resultData->{data}->{filterList}->{isGlobalFilterWpad}?"on":"off";

         FRITZBOX_Log $hash, 4, "globalFilter - end getting data: $enableBoxReading";

       }
       # end FRITZBOX_Get_WLAN_globalFilters

       #-------------------------------------------------------------------------------------
       # getting energy status

       if ($enableBoxReading =~ /box_energyMode/) {

         FRITZBOX_Log $hash, 4, "energyStatus - start getting data: $enableBoxReading";

         # xhr 1 lang de page save_energy xhrId all
         @webCmdArray = ();
         push @webCmdArray, "xhr"         => "1";
         push @webCmdArray, "lang"        => "de";
         push @webCmdArray, "page"        => "save_energy";
         push @webCmdArray, "xhrId"       => "all";

         $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

         # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
         return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

         $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

         FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data});

         if (defined $resultData->{data}->{mode}) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_energyMode", $resultData->{data}->{mode};
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_energyModeWLAN_Timer", $resultData->{data}->{wlan}{timerActive}?"on":"off";
           my $eTime  = $resultData->{data}->{wlan}{dailyStart}{hour} ? $resultData->{data}->{wlan}{dailyStart}{hour} : "__";
              $eTime .= ":";
              $eTime .= $resultData->{data}->{wlan}{dailyStart}{minute} ? $resultData->{data}->{wlan}{dailyStart}{minute} : "__";
              $eTime .= "-";
              $eTime .= $resultData->{data}->{wlan}{dailyEnd}{hour} ? $resultData->{data}->{wlan}{dailyEnd}{hour} : "__";
              $eTime .= ":";
              $eTime .= $resultData->{data}->{wlan}{dailyEnd}{minute} ? $resultData->{data}->{wlan}{dailyEnd}{minute} : "__";

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_energyModeWLAN_Time", $eTime;
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_energyModeWLAN_Repetition", $resultData->{data}->{wlan}{timerMode};
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wlan_Active", $resultData->{data}->{wlan}{enabled} == 1? "on":"off";
         }

         FRITZBOX_Log $hash, 4, "energyStatus - end getting data: $enableBoxReading";

       } #  end getting energy status
     }

     #-------------------------------------------------------------------------------------
     # USB Mobilfunk-Modem Konfiguration

     # xhr 1 lang de page mobile # xhrId modemSettings useajax 1

     if (AttrVal($name, "enableMobileInfo", 0) && ($hash->{fhem}{fwVersion} >= 750) ) {

       FRITZBOX_Log $hash, 4, "MobileInfo - start getting data";

       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "mobile";
       push @webCmdArray, "xhrId"       => "all";

       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       eval {
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_simOk",                        $resultData->{data}->{simOk}, "onoff"
         if $resultData->{data}->{simOk};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_activation",                   $resultData->{data}->{activation}
         if $resultData->{data}->{activation};

         if ($resultData->{data}->{fallback}) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_fallback_possible",          $resultData->{data}->{fallback}->{possible}, "onoff"
           if $resultData->{data}->{fallback}->{possible};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_fallback_enableable",        $resultData->{data}->{fallback}->{enableable}, "onoff"
           if $resultData->{data}->{fallback}->{enableable};
         }

         if ($resultData->{data}->{config}) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_config_dsl",                 $resultData->{data}->{config}->{dsl}
           if $resultData->{data}->{config}->{dsl};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_config_fiber",               $resultData->{data}->{config}->{fiber}
           if $resultData->{data}->{config}->{fiber};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_config_cable",               $resultData->{data}->{config}->{cable}
           if $resultData->{data}->{config}->{cable};

         }

         if ($resultData->{data}->{connection}) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_conn_operator",              $resultData->{data}->{connection}->{operator}
           if $resultData->{data}->{connection}->{operator};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_conn_state",                 $resultData->{data}->{connection}->{state}
           if $resultData->{data}->{connection}->{state};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_conn_quality",               $resultData->{data}->{connection}->{quality}
           if $resultData->{data}->{connection}->{quality};

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_conn_accessTechnology",      $resultData->{data}->{connection}->{accessTechnology}
           if $resultData->{data}->{connection}->{accessTechnology};
         }

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_voipOverMobile",               $resultData->{data}->{voipOverMobile}, "onoff"
         if $resultData->{data}->{voipOverMobile};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_wds",                          $resultData->{data}->{wds}, "onoff"
         if $resultData->{data}->{wds};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_progress_refreshNeeded",       $resultData->{data}->{progress}->{refreshNeeded}, "onoff"
         if $resultData->{data}->{progress}->{refreshNeeded};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_progress_error",               $resultData->{data}->{progress}->{error}
         if $resultData->{data}->{progress}->{error};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_ipclient",                     $resultData->{data}->{ipclient}, "onoff"
         if $resultData->{data}->{ipclient};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_sipNumberCount",               "";
#         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_sipNumberCount",               $resultData->{data}->{sipNumberCount}
#         if $resultData->{data}->{sipNumberCount};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_compatibilityMode_enabled",    $resultData->{data}->{compatibilityMode}->{enabled}, "onoff"
         if $resultData->{data}->{compatibilityMode}->{enabled};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_compatibilityMode_enableable", $resultData->{data}->{compatibilityMode}->{enableable}, "onoff"
         if $resultData->{data}->{compatibilityMode}->{enableable};

         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_capabilities",                 $resultData->{data}->{capabilities}->{voice}, "onoff"
         if $resultData->{data}->{capabilities}->{voice};
       };

       FRITZBOX_Log $hash, 4, "MobileInfo - end getting data";

     } else {
       FRITZBOX_Log $hash, 4, "wrong Fritz!OS for usb mobile: $hash->{fhem}{fwVersionStr}" if AttrVal($name, "enableMobileInfo", 0);
     }

     #-------------------------------------------------------------------------------------
     # DOCSIS Informationen FB Cable

     if ( ( lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]") && $hash->{fhem}{fwVersion} >= 721 ) { # FB Cable
#     if (1==1) {
       my $returnStr;

       my $powerLevels;
       my $frequencys;
       my $modulations;
       my $modType;
       my $latencys;
       my $corrErrors;
       my $nonCorrErrors;
       my $mses;

       my %oldDocDevice;

       # xhr 1 lang de page docInfo xhrId all no_sidrenew nop
       @webCmdArray = ();
       push @webCmdArray, "xhr"         => "1";
       push @webCmdArray, "lang"        => "de";
       push @webCmdArray, "page"        => "docInfo";
       push @webCmdArray, "xhrId"       => "all";
       push @webCmdArray, "no_sidrenew" => "";

#       for debugging
#       my $TestSIS = '{"pid":"docInfo","hide":{"mobile":true,"ssoSet":true,"liveTv":true},"time":[],"data":{"channelDs":{"docsis31":[{"powerLevel":"-1.6","type":"4K","channel":1,"channelID":0,"frequency":"751 - 861"},{"powerLevel":"7.7","type":"4K","channel":2,"channelID":1,"frequency":"175 - 237"}],"docsis30":[{"type":"256QAM","corrErrors":92890,"mse":"-36.4","powerLevel":"5.1","channel":1,"nonCorrErrors":9773,"latency":0.32,"channelID":7,"frequency":"538"},{"type":"256QAM","corrErrors":20553,"mse":"-37.4","powerLevel":"10.2","channel":2,"nonCorrErrors":9420,"latency":0.32,"channelID":26,"frequency":"698"},{"type":"256QAM","corrErrors":28673,"mse":"-37.6","powerLevel":"10.0","channel":3,"nonCorrErrors":140,"latency":0.32,"channelID":25,"frequency":"690"},{"type":"256QAM","corrErrors":25930,"mse":"-37.6","powerLevel":"10.0","channel":4,"nonCorrErrors":170,"latency":0.32,"channelID":27,"frequency":"706"},{"type":"256QAM","corrErrors":98698,"mse":"-36.6","powerLevel":"8.8","channel":5,"nonCorrErrors":9151,"latency":0.32,"channelID":30,"frequency":"746"},{"type":"256QAM","corrErrors":24614,"mse":"-37.4","powerLevel":"9.4","channel":6,"nonCorrErrors":9419,"latency":0.32,"channelID":28,"frequency":"730"},{"type":"256QAM","corrErrors":25882,"mse":"-37.4","powerLevel":"9.9","channel":7,"nonCorrErrors":9308,"latency":0.32,"channelID":24,"frequency":"682"},{"type":"256QAM","corrErrors":33817,"mse":"-37.4","powerLevel":"9.8","channel":8,"nonCorrErrors":146,"latency":0.32,"channelID":23,"frequency":"674"},{"type":"256QAM","corrErrors":112642,"mse":"-37.6","powerLevel":"7.8","channel":9,"nonCorrErrors":7783,"latency":0.32,"channelID":3,"frequency":"490"},{"type":"256QAM","corrErrors":41161,"mse":"-37.6","powerLevel":"9.8","channel":10,"nonCorrErrors":203,"latency":0.32,"channelID":21,"frequency":"658"},{"type":"256QAM","corrErrors":33219,"mse":"-37.4","powerLevel":"8.8","channel":11,"nonCorrErrors":10962,"latency":0.32,"channelID":18,"frequency":"634"},{"type":"256QAM","corrErrors":32680,"mse":"-37.6","powerLevel":"9.2","channel":12,"nonCorrErrors":145,"latency":0.32,"channelID":19,"frequency":"642"},{"type":"256QAM","corrErrors":33001,"mse":"-37.4","powerLevel":"9.8","channel":13,"nonCorrErrors":7613,"latency":0.32,"channelID":22,"frequency":"666"},{"type":"256QAM","corrErrors":42666,"mse":"-37.4","powerLevel":"8.1","channel":14,"nonCorrErrors":172,"latency":0.32,"channelID":17,"frequency":"626"},{"type":"256QAM","corrErrors":41023,"mse":"-37.4","powerLevel":"9.3","channel":15,"nonCorrErrors":10620,"latency":0.32,"channelID":20,"frequency":"650"},{"type":"256QAM","corrErrors":106921,"mse":"-37.6","powerLevel":"7.4","channel":16,"nonCorrErrors":356,"latency":0.32,"channelID":4,"frequency":"498"},{"type":"256QAM","corrErrors":86650,"mse":"-36.4","powerLevel":"4.9","channel":17,"nonCorrErrors":85,"latency":0.32,"channelID":12,"frequency":"578"},{"type":"256QAM","corrErrors":91838,"mse":"-36.4","powerLevel":"4.8","channel":18,"nonCorrErrors":168,"latency":0.32,"channelID":8,"frequency":"546"},{"type":"256QAM","corrErrors":110719,"mse":"-35.8","powerLevel":"4.5","channel":19,"nonCorrErrors":103,"latency":0.32,"channelID":10,"frequency":"562"},{"type":"256QAM","corrErrors":111846,"mse":"-37.6","powerLevel":"8.2","channel":20,"nonCorrErrors":247,"latency":0.32,"channelID":2,"frequency":"482"},{"type":"256QAM","corrErrors":668242,"mse":"-36.6","powerLevel":"5.8","channel":21,"nonCorrErrors":6800,"latency":0.32,"channelID":5,"frequency":"522"},{"type":"256QAM","corrErrors":104070,"mse":"-36.6","powerLevel":"5.3","channel":22,"nonCorrErrors":149,"latency":0.32,"channelID":6,"frequency":"530"},{"type":"256QAM","corrErrors":120994,"mse":"-35.8","powerLevel":"4.4","channel":23,"nonCorrErrors":10240,"latency":0.32,"channelID":9,"frequency":"554"},{"type":"256QAM","corrErrors":59145,"mse":"-36.4","powerLevel":"5.3","channel":24,"nonCorrErrors":9560,"latency":0.32,"channelID":11,"frequency":"570"},{"type":"256QAM","corrErrors":118271,"mse":"-37.6","powerLevel":"8.4","channel":25,"nonCorrErrors":810,"latency":0.32,"channelID":1,"frequency":"474"},{"type":"256QAM","corrErrors":40255,"mse":"-37.4","powerLevel":"6.5","channel":26,"nonCorrErrors":13474,"latency":0.32,"channelID":15,"frequency":"602"},{"type":"256QAM","corrErrors":62716,"mse":"-36.4","powerLevel":"5.3","channel":27,"nonCorrErrors":9496,"latency":0.32,"channelID":13,"frequency":"586"},{"type":"256QAM","corrErrors":131364,"mse":"-36.6","powerLevel":"8.9","channel":28,"nonCorrErrors":12238,"latency":0.32,"channelID":29,"frequency":"738"}]},"oem":"lgi","readyState":"ready","channelUs":{"docsis31":[],"docsis30":[{"powerLevel":"43.0","type":"64QAM","channel":1,"multiplex":"ATDMA","channelID":4,"frequency":"51"},{"powerLevel":"44.3","type":"64QAM","channel":2,"multiplex":"ATDMA","channelID":2,"frequency":"37"},{"powerLevel":"43.8","type":"64QAM","channel":3,"multiplex":"ATDMA","channelID":3,"frequency":"45"},{"powerLevel":"45.8","type":"64QAM","channel":4,"multiplex":"ATDMA","channelID":1,"frequency":"31"}]}},"sid":"14341afbc7d83b4c"}';
#       my $TestSIS = '{"pid":"docInfo","hide":{"mobile":true,"ssoSet":true,"liveTv":true},"time":[],"data":{"channelDs":{"docsis30":[{"type":"256QAM","corrErrors":92890,"mse":"-36.4","powerLevel":"5.1","channel":1,"nonCorrErrors":9773,"latency":0.32,"channelID":7,"frequency":"538"},{"type":"256QAM","corrErrors":20553,"mse":"-37.4","powerLevel":"10.2","channel":2,"nonCorrErrors":9420,"latency":0.32,"channelID":26,"frequency":"698"},{"type":"256QAM","corrErrors":28673,"mse":"-37.6","powerLevel":"10.0","channel":3,"nonCorrErrors":140,"latency":0.32,"channelID":25,"frequency":"690"},{"type":"256QAM","corrErrors":25930,"mse":"-37.6","powerLevel":"10.0","channel":4,"nonCorrErrors":170,"latency":0.32,"channelID":27,"frequency":"706"},{"type":"256QAM","corrErrors":98698,"mse":"-36.6","powerLevel":"8.8","channel":5,"nonCorrErrors":9151,"latency":0.32,"channelID":30,"frequency":"746"},{"type":"256QAM","corrErrors":24614,"mse":"-37.4","powerLevel":"9.4","channel":6,"nonCorrErrors":9419,"latency":0.32,"channelID":28,"frequency":"730"},{"type":"256QAM","corrErrors":25882,"mse":"-37.4","powerLevel":"9.9","channel":7,"nonCorrErrors":9308,"latency":0.32,"channelID":24,"frequency":"682"},{"type":"256QAM","corrErrors":33817,"mse":"-37.4","powerLevel":"9.8","channel":8,"nonCorrErrors":146,"latency":0.32,"channelID":23,"frequency":"674"},{"type":"256QAM","corrErrors":112642,"mse":"-37.6","powerLevel":"7.8","channel":9,"nonCorrErrors":7783,"latency":0.32,"channelID":3,"frequency":"490"},{"type":"256QAM","corrErrors":41161,"mse":"-37.6","powerLevel":"9.8","channel":10,"nonCorrErrors":203,"latency":0.32,"channelID":21,"frequency":"658"},{"type":"256QAM","corrErrors":33219,"mse":"-37.4","powerLevel":"8.8","channel":11,"nonCorrErrors":10962,"latency":0.32,"channelID":18,"frequency":"634"},{"type":"256QAM","corrErrors":32680,"mse":"-37.6","powerLevel":"9.2","channel":12,"nonCorrErrors":145,"latency":0.32,"channelID":19,"frequency":"642"},{"type":"256QAM","corrErrors":33001,"mse":"-37.4","powerLevel":"9.8","channel":13,"nonCorrErrors":7613,"latency":0.32,"channelID":22,"frequency":"666"},{"type":"256QAM","corrErrors":42666,"mse":"-37.4","powerLevel":"8.1","channel":14,"nonCorrErrors":172,"latency":0.32,"channelID":17,"frequency":"626"},{"type":"256QAM","corrErrors":41023,"mse":"-37.4","powerLevel":"9.3","channel":15,"nonCorrErrors":10620,"latency":0.32,"channelID":20,"frequency":"650"},{"type":"256QAM","corrErrors":106921,"mse":"-37.6","powerLevel":"7.4","channel":16,"nonCorrErrors":356,"latency":0.32,"channelID":4,"frequency":"498"},{"type":"256QAM","corrErrors":86650,"mse":"-36.4","powerLevel":"4.9","channel":17,"nonCorrErrors":85,"latency":0.32,"channelID":12,"frequency":"578"},{"type":"256QAM","corrErrors":91838,"mse":"-36.4","powerLevel":"4.8","channel":18,"nonCorrErrors":168,"latency":0.32,"channelID":8,"frequency":"546"},{"type":"256QAM","corrErrors":110719,"mse":"-35.8","powerLevel":"4.5","channel":19,"nonCorrErrors":103,"latency":0.32,"channelID":10,"frequency":"562"},{"type":"256QAM","corrErrors":111846,"mse":"-37.6","powerLevel":"8.2","channel":20,"nonCorrErrors":247,"latency":0.32,"channelID":2,"frequency":"482"},{"type":"256QAM","corrErrors":668242,"mse":"-36.6","powerLevel":"5.8","channel":21,"nonCorrErrors":6800,"latency":0.32,"channelID":5,"frequency":"522"},{"type":"256QAM","corrErrors":104070,"mse":"-36.6","powerLevel":"5.3","channel":22,"nonCorrErrors":149,"latency":0.32,"channelID":6,"frequency":"530"},{"type":"256QAM","corrErrors":120994,"mse":"-35.8","powerLevel":"4.4","channel":23,"nonCorrErrors":10240,"latency":0.32,"channelID":9,"frequency":"554"},{"type":"256QAM","corrErrors":59145,"mse":"-36.4","powerLevel":"5.3","channel":24,"nonCorrErrors":9560,"latency":0.32,"channelID":11,"frequency":"570"},{"type":"256QAM","corrErrors":118271,"mse":"-37.6","powerLevel":"8.4","channel":25,"nonCorrErrors":810,"latency":0.32,"channelID":1,"frequency":"474"},{"type":"256QAM","corrErrors":40255,"mse":"-37.4","powerLevel":"6.5","channel":26,"nonCorrErrors":13474,"latency":0.32,"channelID":15,"frequency":"602"},{"type":"256QAM","corrErrors":62716,"mse":"-36.4","powerLevel":"5.3","channel":27,"nonCorrErrors":9496,"latency":0.32,"channelID":13,"frequency":"586"},{"type":"256QAM","corrErrors":131364,"mse":"-36.6","powerLevel":"8.9","channel":28,"nonCorrErrors":12238,"latency":0.32,"channelID":29,"frequency":"738"}]},"oem":"lgi","readyState":"ready","channelUs":{"docsis30":[{"powerLevel":"43.0","type":"64QAM","channel":1,"multiplex":"ATDMA","channelID":4,"frequency":"51"},{"powerLevel":"44.3","type":"64QAM","channel":2,"multiplex":"ATDMA","channelID":2,"frequency":"37"},{"powerLevel":"43.8","type":"64QAM","channel":3,"multiplex":"ATDMA","channelID":3,"frequency":"45"},{"powerLevel":"45.8","type":"64QAM","channel":4,"multiplex":"ATDMA","channelID":1,"frequency":"31"}]}},"sid":"14341afbc7d83b4c"}';
#       my $resultData = FRITZBOX_Helper_process_JSON($hash, $TestSIS, "14341afbc7d83b4c", ""); ;
      
       $resultData = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       return FRITZBOX_Readout_Response($hash, $resultData, $roReadings) if ( defined $resultData->{Error} || defined $resultData->{AuthorizationRequired});

       $$sidNew += $resultData->{sidNew} if defined $resultData->{sidNew};

       FRITZBOX_Log $hash, 5, "\n" . Dumper ($resultData->{data});
 
       #collect current mac-readings (to delete the ones that are inactive or disappeared)
       foreach (keys %{ $hash->{READINGS} }) {
         $oldDocDevice{$_} = $hash->{READINGS}{$_}{VAL} if $_ =~ /^box_docsis/ && defined $hash->{READINGS}{$_}{VAL};
       }

       $nbViews = 0;
       if (defined $resultData->{data}->{channelUs}->{docsis30}) {
         $views = $resultData->{data}->{channelUs}->{docsis30};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         $powerLevels = "";
         $frequencys  = "";
         $modulations = "";

         $modType = $resultData->{data}->{channelUs}->{docsis30}->[0]->{type}?"type":"modulation";

         eval {
           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             $powerLevels .= $resultData->{data}->{channelUs}->{docsis30}->[$i]->{powerLevel} . " ";
             $frequencys  .= $resultData->{data}->{channelUs}->{docsis30}->[$i]->{frequency} . " ";
             $modulations .= $1 if($resultData->{data}->{channelUs}->{docsis30}->[$i]->{$modType} =~ /(\d+)/);
             $modulations .= " ";
           }

           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Us_powerLevels", substr($powerLevels,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Us_frequencys", substr($frequencys,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Us_modulations", substr($modulations,0,-1);
           delete $oldDocDevice{box_docsis30_Us_powerLevels} if exists $oldDocDevice{box_docsis30_Us_powerLevels};
           delete $oldDocDevice{box_docsis30_Us_frequencys} if exists $oldDocDevice{box_docsis30_Us_frequencys};
           delete $oldDocDevice{box_docsis30_Us_modulations} if exists $oldDocDevice{box_docsis30_Us_modulations};
         };
       }

       $nbViews = 0;
       if (defined $resultData->{data}->{channelUs}->{docsis31}) {
         $views = $resultData->{data}->{channelUs}->{docsis31};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         $powerLevels = "";
         $frequencys  = "";
         $modulations  = "";

         $modType = $resultData->{data}->{channelUs}->{docsis31}->[0]->{type}?"type":"modulation";

         eval {
           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             $powerLevels .= $resultData->{data}->{channelUs}->{docsis31}->[$i]->{powerLevel} . " ";
             $frequencys  .= $resultData->{data}->{channelUs}->{docsis31}->[$i]->{frequency} . " ";
             $modulations .= $1 if($resultData->{data}->{channelUs}->{docsis31}->[$i]->{$modType} =~ /(\d+)/);
             $modulations .= " ";
           }
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis31_Us_powerLevels", substr($powerLevels,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis31_Us_frequencys", substr($frequencys,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis31_Us_modulations", substr($modulations,0,-1);
           delete $oldDocDevice{box_docsis31_Us_powerLevels} if exists $oldDocDevice{box_docsis31_Us_powerLevels};
           delete $oldDocDevice{box_docsis31_Us_frequencys} if exists $oldDocDevice{box_docsis31_Us_frequencys};
           delete $oldDocDevice{box_docsis31_Us_modulations} if exists $oldDocDevice{box_docsis31_Us_modulations};
         };

       }

       $nbViews = 0;
       if (defined $resultData->{data}->{channelDs}->{docsis30}) {
           $views = $resultData->{data}->{channelDs}->{docsis30};
           $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         $powerLevels   = "";
         $latencys      = "";
         $frequencys    = "";
         $corrErrors    = "";
         $nonCorrErrors = "";
         $mses          = "";
         $modulations   = "";

         $modType = $resultData->{data}->{channelDs}->{docsis30}->[0]->{type}?"type":"modulation";

         eval {
           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             $powerLevels   .= $resultData->{data}->{channelDs}->{docsis30}->[$i]->{powerLevel} . " ";
             $latencys      .= $resultData->{data}->{channelDs}->{docsis30}->[$i]->{latency} . " ";
             $frequencys    .= $resultData->{data}->{channelDs}->{docsis30}->[$i]->{frequency} . " ";
             $corrErrors    .= $resultData->{data}->{channelDs}->{docsis30}->[$i]->{corrErrors} . " ";
             $nonCorrErrors .= $resultData->{data}->{channelDs}->{docsis30}->[$i]->{nonCorrErrors} . " ";
             $mses          .= $resultData->{data}->{channelDs}->{docsis30}->[$i]->{mse} . " ";
             $modulations   .= $1 if($resultData->{data}->{channelDs}->{docsis30}->[$i]->{$modType} =~ /(\d+)/);
             $modulations   .= " ";
           }
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_powerLevels", substr($powerLevels,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_latencys", substr($latencys,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_frequencys", substr($frequencys,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_corrErrors", substr($corrErrors,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_nonCorrErrors", substr($latencys,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_mses", substr($mses,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis30_Ds_modulations", substr($modulations,0,-1);
           delete $oldDocDevice{box_docsis30_Ds_powerLevels}   if exists $oldDocDevice{box_docsis30_Ds_powerLevels};
           delete $oldDocDevice{box_docsis30_Ds_latencys}      if exists $oldDocDevice{box_docsis30_Ds_latencys};
           delete $oldDocDevice{box_docsis30_Ds_frequencys}    if exists $oldDocDevice{box_docsis30_Ds_frequencys};
           delete $oldDocDevice{box_docsis30_Ds_corrErrors}    if exists $oldDocDevice{box_docsis30_Ds_corrErrors};
           delete $oldDocDevice{box_docsis30_Ds_nonCorrErrors} if exists $oldDocDevice{box_docsis30_Ds_nonCorrErrors};
           delete $oldDocDevice{box_docsis30_Ds_mses}          if exists $oldDocDevice{box_docsis30_Ds_mses};
           delete $oldDocDevice{box_docsis30_Ds_modulations}   if exists $oldDocDevice{box_docsis30_Ds_modulations};
         };

       }

       $nbViews = 0;
       if (defined $resultData->{data}->{channelDs}->{docsis31}) {
         $views = $resultData->{data}->{channelDs}->{docsis31};
         $nbViews = scalar @$views;
       }

       if ($nbViews > 0) {

         $powerLevels = "";
         $frequencys  = "";
         $modulations   = "";

         $modType = $resultData->{data}->{channelDs}->{docsis31}->[0]->{type}?"type":"modulation";

         eval {
           for(my $i = 0; $i <= $nbViews - 1; $i++) {
             $powerLevels .= $resultData->{data}->{channelDs}->{docsis31}->[$i]->{powerLevel} . " ";
             $frequencys  .= $resultData->{data}->{channelDs}->{docsis31}->[$i]->{frequency} . " ";
             $modulations .= $1 if($resultData->{data}->{channelDs}->{docsis31}->[$i]->{$modType} =~ /(\d+)/);
             $modulations .= " ";
           }
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis31_Ds_powerLevels", substr($powerLevels,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis31_Ds_frequencys", substr($frequencys,0,-1);
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_docsis31_Ds_modulations", substr($modulations,0,-1);
           delete $oldDocDevice{box_docsis31_Ds_powerLevels} if exists $oldDocDevice{box_docsis31_Ds_powerLevels};
           delete $oldDocDevice{box_docsis31_Ds_frequencys}  if exists $oldDocDevice{box_docsis31_Ds_frequencys};
           delete $oldDocDevice{box_docsis31_Ds_modulations} if exists $oldDocDevice{box_docsis31_Ds_modulations};
         };
       }

       # Remove inactive or non existing wan-readings in two steps
       foreach ( keys %oldDocDevice ) {
         # set the wan readings to 'inactive' and delete at next readout
         if ( $oldDocDevice{$_} ne "inactive" ) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "inactive";
         } else {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, $_, "";
         }
       }

     } else {
       FRITZBOX_Log $hash, 4, "wrong Fritz!OS: $hash->{fhem}{fwVersionStr} or AVM-Model: $avmModel for docsis informations.";
     }

   } # end for Model == "Box"

   return "";

} # End FRITZBOX_Readout_Run_Web_LuaData


# informations depending on TR064
#-------------------------------------------------------------------------------------

#######################################################################
sub FRITZBOX_Readout_Run_Web_TR064($$$$)
{
   my ($name, $roReadings, $sidNew, $sid) = @_;
   my $hash = $defs{$name};

   my $result;
   my $rName;
   my $startTime = time();
   my $runNo;
   my $host   = $hash->{HOST};
   my $Tag;
   my $Std;
   my $Min;
   my $Sek;

   my $views;
   my $nbViews;

   my $avmModel = InternalVal($name, "MODEL", "FRITZ!Box");

   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   my @webCmdArray;
   my $resultData;
   my $tmpData;

     my $strCurl;
     my @tr064CmdArray;
     my @tr064Result;

     if ($avmModel =~ "Box") {

       #-------------------------------------------------------------------------------------
       # USB Mobilfunk-Modem Informationen

       if (AttrVal($name, "enableMobileInfo", 0) && ($hash->{fhem}{fwVersion} >= 750) ) { # FB mit Mobile Modem-Stick

         FRITZBOX_Log $hash, 4, "MobileInfo - start getting TR064 data";

         @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetInfoEx"]);

         @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

         if ($tr064Result[0]->{UPnPError}) {
           $strCurl = Dumper (@tr064Result);
           FRITZBOX_Log $hash, 2, "Mobile GetInfoEX -> \n" . $strCurl;
         } else {

           FRITZBOX_Log $hash, 5, "Mobile GetInfoEx -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetInfoExResponse}) {

             if (defined $tr064Result[0]->{GetInfoExResponse}->{NewCellList}) {
               my $data = $tr064Result[0]->{GetInfoExResponse}->{NewCellList};
               $data =~ s/&lt;/</isg;
               $data =~ s/&gt;/>/isg;

               FRITZBOX_Log $hash, 4, "Data Mobile GetInfoEx (NewCellList): \n" . $data;

               while( $data =~ /<Cell>(.*?)<\/Cell>/isg ) {
                 my $cellList = $1;
 
                 FRITZBOX_Log $hash, 4, "Data Mobile GetInfoEx (Cell): \n" . $1;
                
                 my $Index      = $1 if $cellList =~ m/<Index>(.*?)<\/Index>/is;
                 my $Connected  = $1 if $cellList =~ m/<Connected>(.*?)<\/Connected>/is;
                 my $CellType   = $1 if $cellList =~ m/<CellType>(.*?)<\/CellType>/is;
                 my $PLMN       = $1 if $cellList =~ m/<PLMN>(.*?)<\/PLMN>/is;
                 my $Provider   = $1 if $cellList =~ m/<Provider>(.*?)<\/Provider>/is;
                 my $TAC        = $1 if $cellList =~ m/<TAC>(.*?)<\/TAC>/is;
                 my $PhysicalId = $1 if $cellList =~ m/<PhysicalId>(.*?)<\/PhysicalId>/is;
                 my $Distance   = $1 if $cellList =~ m/<Distance>(.*?)<\/Distance>/is;
                 my $Rssi       = $1 if $cellList =~ m/<Rssi>(.*?)<\/Rssi>/is;
                 my $Rsrq       = $1 if $cellList =~ m/<Rsrq>(.*?)<\/Rsrq>/is;
                 my $RSRP       = $1 if $cellList =~ m/<RSRP>(.*?)<\/RSRP>/is;
                 my $Cellid     = $1 if $cellList =~ m/<Cellid>(.*?)<\/Cellid>/is;
 
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_Connected", $Connected;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_CellType", $CellType;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_PLMN", $PLMN;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_Provider", $Provider;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_TAC", $TAC;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_PhysicalId", $PhysicalId;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_Distance", $Distance;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_Rssi", $Rssi;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_Rsrq", $Rsrq;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_RSRP", $RSRP;
                 FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo" . $Index ."_Cellid", $Cellid;
               }

             }

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PPPUsername",             $tr064Result[0]->{GetInfoExResponse}->{NewPPPUsername};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PDN2_MTU",                $tr064Result[0]->{GetInfoExResponse}->{NewPDN2_MTU};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_APN",                     $tr064Result[0]->{GetInfoExResponse}->{NewAPN};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_SoftwareVersion",         $tr064Result[0]->{GetInfoExResponse}->{NewSoftwareVersion};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_Roaming",                 $tr064Result[0]->{GetInfoExResponse}->{NewRoaming};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PDN1_MTU",                $tr064Result[0]->{GetInfoExResponse}->{NewPDN1_MTU};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_IMSI",                    $tr064Result[0]->{GetInfoExResponse}->{NewIMSI};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_SignalRSRP1",             $tr064Result[0]->{GetInfoExResponse}->{NewSignalRSRP1};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_CurrentAccessTechnology", $tr064Result[0]->{GetInfoExResponse}->{NewCurrentAccessTechnology};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PPPUsernameVoIP",         $tr064Result[0]->{GetInfoExResponse}->{NewPPPUsernameVoIP};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_EnableVoIPPDN",           $tr064Result[0]->{GetInfoExResponse}->{NewEnableVoIPPDN};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_APN_VoIP",                $tr064Result[0]->{GetInfoExResponse}->{NewAPN_VoIP};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_Uptime",                  $tr064Result[0]->{GetInfoExResponse}->{NewUptime};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_SignalRSRP0",             $tr064Result[0]->{GetInfoExResponse}->{NewSignalRSRP0};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_SerialNumber",            $tr064Result[0]->{GetInfoExResponse}->{NewSerialNumber};
           }
          
         }

         @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetInfo"]);

         @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

         if ($tr064Result[0]->{UPnPError}) {
           $strCurl = Dumper (@tr064Result);
           FRITZBOX_Log $hash, 2, "Mobile GetInfo -> \n" . $strCurl;
         } else {

           FRITZBOX_Log $hash, 5, "Mobile GetInfo -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetInfoResponse}) {

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PINFailureCount", $tr064Result[0]->{GetInfoResponse}->{NewPINFailureCount};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PUKFailureCount", $tr064Result[0]->{GetInfoResponse}->{NewPUKFailureCount};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_Enabled",         $tr064Result[0]->{GetInfoResponse}->{NewEnabled};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_Status",          $tr064Result[0]->{GetInfoResponse}->{NewStatus};
  
           }
          
         }

         @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetBandCapabilities"]);

         @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

         if ($tr064Result[0]->{UPnPError}) {
           $strCurl = Dumper (@tr064Result);
           FRITZBOX_Log $hash, 2, "Mobile GetInfo -> \n" . $strCurl;
         } else {

           FRITZBOX_Log $hash, 5, "Mobile GetInfo -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetInfoResponse}) {

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_CapabilitiesLTE",   $tr064Result[0]->{GetInfoResponse}->{NewBandCapabilitiesLTE};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_Capabilities5GSA",  $tr064Result[0]->{GetInfoResponse}->{NewBandCapabilities5GSA};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_Capabilities5GNSA", $tr064Result[0]->{GetInfoResponse}->{NewBandCapabilities5GNSA};
  
           }
          
         }

         @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetAccessTechnology"]);

         @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

         if ($tr064Result[0]->{UPnPError}) {
           $strCurl = Dumper (@tr064Result);
           FRITZBOX_Log $hash, 2, "Mobile GetInfo -> \n" . $strCurl;
         } else {

           FRITZBOX_Log $hash, 5, "Mobile GetInfo -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetInfoResponse}) {

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_CurrentAccessTechnology",  $tr064Result[0]->{GetInfoResponse}->{NewCurrentAccessTechnology};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_PossibleAccessTechnology", $tr064Result[0]->{GetInfoResponse}->{NewPossibleAccessTechnology};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "mobileInfo_AccessTechnology",         $tr064Result[0]->{GetInfoResponse}->{NewAccessTechnology};
  
           }
          
         }

         FRITZBOX_Log $hash, 4, "MobileInfo - end getting TR064 data";

       } else {
         FRITZBOX_Log $hash, 4, "wrong Fritz!OS: $hash->{fhem}{fwVersionStr} for usb mobile via TR064 or not a Fritz!Box" if AttrVal($name, "enableMobileInfo", 0);
       }

       #-------------------------------------------------------------------------------------
       # getting PhoneBook ID's

       if (AttrVal($name, "enablePhoneBookInfo", 0)) { 

         FRITZBOX_Log $hash, 4, "PhoneBookInfo - start getting TR064 data";

         @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "GetPhonebookList"] );
         @tr064Result = FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);

         if ($tr064Result[0]->{Error}) {
           $strCurl = Dumper (@tr064Result);
           FRITZBOX_Log $hash, 4, "error identifying phonebooks via TR-064 -> \n" . $strCurl;
         } else {

           FRITZBOX_Log $hash, 5, "get Phonebooks -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetPhonebookListResponse}) {
             if (defined $tr064Result[0]->{GetPhonebookListResponse}->{NewPhonebookList}) {

               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fon_phoneBook_IDs", $tr064Result[0]->{GetPhonebookListResponse}->{NewPhonebookList};

               my @phonebooks = split(",", $tr064Result[0]->{GetPhonebookListResponse}->{NewPhonebookList});

               foreach (@phonebooks) {

                 my $item_id = $_;
                 my $phb_id;

                 @tr064CmdArray = (["X_AVM-DE_OnTel:1", "x_contact", "GetPhonebook", "NewPhonebookID", $item_id] );
                 @tr064Result = FRITZBOX_call_TR064_Cmd ($hash, 0, \@tr064CmdArray);

                 if ($tr064Result[0]->{Error}) {
                   $strCurl = Dumper (@tr064Result);
                   FRITZBOX_Log $hash, 4, "error getting phonebook infos via TR-064 -> \n" . $strCurl;
                 } else {
                   FRITZBOX_Log $hash, 5, "get Phonebook Infos -> \n" . Dumper (@tr064Result);

                   if ($tr064Result[0]->{GetPhonebookResponse}) {
                     if (defined $tr064Result[0]->{GetPhonebookResponse}->{NewPhonebookName}) {
                       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fon_phoneBook_$item_id", $tr064Result[0]->{GetPhonebookResponse}->{NewPhonebookName};
                     }
                     if (defined $tr064Result[0]->{GetPhonebookResponse}->{NewPhonebookURL}) {
                       FRITZBOX_Readout_Add_Reading $hash, $roReadings, "fon_phoneBook_URL_$item_id", $tr064Result[0]->{GetPhonebookResponse}->{NewPhonebookURL};
                     }
                   } else {
                     FRITZBOX_Log $hash, 4, "no phonebook infos result via TR-064:\n" . Dumper (@tr064Result);
                   }
                 }
               }
             } else {
               FRITZBOX_Log $hash, 4, "no phonebook result via TR-064:\n" . Dumper (@tr064Result);
             }
           } else {
             FRITZBOX_Log $hash, 4, "no phonebook ID's via TR-064:\n" . Dumper (@tr064Result);
           }
         }

         FRITZBOX_Log $hash, 4, "PhoneBookInfo - end getting TR064 data";

       }

       #-------------------------------------------------------------------------------------
       # getting DSL down/up stream rate

       my $globalvdsl = AttrVal($name, "enableBoxReadings", "");
     
       if ($globalvdsl =~ /box_vdsl/) {

         FRITZBOX_Log $hash, 4, "down/up stream - start getting TR064 data: $globalvdsl";

         if (($mesh ne "slave") && ($hash->{fhem}{fwVersion} >= 680) && (lc($avmModel) !~ "5[4,5][9,3]0|40[2,4,6]0|68[2,5]0|6[4,5,6][3,6,9][0,1]|fiber|cable") ) { # FB ohne VDSL

           @tr064CmdArray = (["WANDSLInterfaceConfig:1", "wandslifconfig1", "GetInfo"]);
           @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

           if ($tr064Result[0]->{UPnPError}) {
             $strCurl = Dumper (@tr064Result);
             FRITZBOX_Log $hash, 2, "VDSL up/down rate GetInfo -> \n" . $strCurl;
           } else {

             FRITZBOX_Log $hash, 5, "VDSL up/down rate GetInfo -> \n" . Dumper (@tr064Result);

             if ($tr064Result[0]->{GetInfoResponse}) {
               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_downStreamRate", $tr064Result[0]->{GetInfoResponse}->{NewDownstreamCurrRate} / 1000;
               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_downStreamMaxRate", $tr064Result[0]->{GetInfoResponse}->{NewDownstreamMaxRate} / 1000;
               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_upStreamRate", $tr064Result[0]->{GetInfoResponse}->{NewUpstreamCurrRate} / 1000;
               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_upStreamMaxRate", $tr064Result[0]->{GetInfoResponse}->{NewUpstreamMaxRate} / 1000;
             }
           }

         } else {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_downStreamRate", "";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_downStreamMaxRate", "";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_upStreamRate", "";
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_vdsl_upStreamMaxRate", "";
         }

         FRITZBOX_Log $hash, 4, "down/up stream - end getting TR064 data: $globalvdsl";

       } # end getting DSL donw/up stream rate

       #-------------------------------------------------------------------------------------
       # getting WANPPPConnection Info

       my $getInfo2cd = 0;

       if ( lc($avmModel) !~ "6[4,5,6][3,6,9][0,1]" ) {

         FRITZBOX_Log $hash, 4, "wanpppconn - start getting TR064 data";

         #-------------------------------------------------------------------------------------
         # box_ipIntern WANPPPConnection:1 wanpppconn1 GetInfo

         @tr064CmdArray = (["WANPPPConnection:1", "wanpppconn1", "GetInfo"]);
         @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

         if ($tr064Result[0]->{UPnPError}) {
           $strCurl = Dumper (@tr064Result);
           FRITZBOX_Log $hash, 4, "wanpppconn GetInfo -> \n" . $strCurl;
           $getInfo2cd = 1;
         } else {

           FRITZBOX_Log $hash, 5, "wanpppconn GetInfo -> \n" . Dumper (@tr064Result);

           if ($tr064Result[0]->{GetInfoResponse}) {
             my $dns_servers = $tr064Result[0]->{GetInfoResponse}->{NewDNSServers};
             $dns_servers =~ s/ //;
             my @dns_list = split(/\,/, $dns_servers);
             my $cnt = 0;
             foreach ( @dns_list ) {
               FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_dns_Server$cnt", $_;
               $cnt++;
             }

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv4_Extern", $tr064Result[0]->{GetInfoResponse}->{NewExternalIPAddress};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_connection_Type", $tr064Result[0]->{GetInfoResponse}->{NewConnectionType};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_connect", $tr064Result[0]->{GetInfoResponse}->{NewConnectionStatus};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_last_connect_err", $tr064Result[0]->{GetInfoResponse}->{NewLastConnectionError};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_last_auth_err", $tr064Result[0]->{GetInfoResponse}->{NewLastAuthErrorInfo};
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_mac_Address", $tr064Result[0]->{GetInfoResponse}->{NewMACAddress};

             $strCurl = $tr064Result[0]->{GetInfoResponse}->{NewUptime};
             $Sek = $strCurl;
             $Tag  = int($Sek/86400);
             $Std  = int(($Sek/3600)-(24*$Tag));
             $Min = int(($Sek/60)-($Std*60)-(1440*$Tag));
             $Sek -= (($Min*60)+($Std*3600)+(86400*$Tag));

             $Std = substr("0".$Std,-2);
             $Min = substr("0".$Min,-2);
             $Sek = substr("0".$Sek,-2);

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_uptimeConnect", ($mesh ne "slave") ? $strCurl . " sec = " . $Tag . "T $Std:$Min:$Sek" : "";
           }
         }

         FRITZBOX_Log $hash, 4, "wanpppconn - end getting TR064 data";

       } # end getting WANPPPConnection Info

       #-------------------------------------------------------------------------------------
       # TR064 with xml enveloap via SOAP request wanipconnection1

       my $soap_resp;
       my $control_url     = "igdupnp/control/";
       my $service_type    = "urn:schemas-upnp-org:service:WANIPConnection:1";
       my $service_command = "GetStatusInfo";

       if ( (lc($avmModel) =~ "6[4,5,6][3,6,9][0,1]") || $getInfo2cd ) {

         #-------------------------------------------------------------------------------------
         # box_uptimeConnect

         FRITZBOX_Log $hash, 4, "uptimeConnect- start getting TR064 data";

         $soap_resp = FRITZBOX_SOAP_Request($hash,$control_url . "WANIPConn1", $service_type, $service_command);

         if(defined $soap_resp->{Error}) {
           FRITZBOX_Log $hash, 4, "SOAP-ERROR -> " . $soap_resp->{Error};
 
         } elsif ( $soap_resp->{Response} ) {

           $strCurl = $soap_resp->{Response};
           FRITZBOX_Log $hash, 5, "Curl-> " . $strCurl;

           if($strCurl =~ m/<NewConnectionStatus>(.*?)<\/NewConnectionStatus>/i) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_connect", $1;
           }
           if($strCurl =~ m/<NewLastConnectionError>(.*?)<\/NewLastConnectionError>/i) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_last_connect_err", $1;
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

             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_uptimeConnect", $1 . " sec = " . $Tag . "T $Std:$Min:$Sek";
           }

         }

         FRITZBOX_Log $hash, 4, "uptimeConnect- end getting TR064 data";

         #-------------------------------------------------------------------------------------
         # box_ipExtern

         FRITZBOX_Log $hash, 4, "ipExtern- start getting TR064 data";

         $service_command = "GetExternalIPAddress";

         $soap_resp = FRITZBOX_SOAP_Request($hash,$control_url . "WANIPConn1", $service_type, $service_command);

         if(exists $soap_resp->{Error}) {
           FRITZBOX_Log $hash, 4, "SOAP-ERROR -> " . $soap_resp->{Error};
 
         } elsif ( $soap_resp->{Response} ) {

           $strCurl = $soap_resp->{Response};
           FRITZBOX_Log $hash, 5, "Curl-> " . $strCurl;

           if($strCurl =~ m/<NewExternalIPAddress>(.*?)<\/NewExternalIPAddress>/i) {
             FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv4_Extern", $1;
           }
         }

         FRITZBOX_Log $hash, 4, "ipExtern- end getting TR064 data";

       }

       #-------------------------------------------------------------------------------------

       # box_ipv6 ->  NewPreferedLifetime, NewExternalIPv6Address, NewValidLifetime, NewPrefixLength

       FRITZBOX_Log $hash, 4, "ipv6 - start getting TR064 data";

       $service_command = "X_AVM_DE_GetExternalIPv6Address";

       $soap_resp = FRITZBOX_SOAP_Request($hash,$control_url . "WANIPConn1", $service_type, $service_command);

       if(exists $soap_resp->{Error}) {
         FRITZBOX_Log $hash, 4, "SOAP/TR064-ERROR -> " . $soap_resp->{Error};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv6_Extern", $soap_resp->{ErrLevel} == 2?"unknown error":"";
 
       } elsif ( $soap_resp->{Response} ) {

         $strCurl = $soap_resp->{Response};
         FRITZBOX_Log $hash, 5, "Curl-> " . $strCurl;

         if($strCurl =~ m/<NewExternalIPv6Address>(.*?)<\/NewExternalIPv6Address>/i) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv6_Extern", $1;
         }
       }

       FRITZBOX_Log $hash, 4, "ipv6 - end getting TR064 data";

       #-------------------------------------------------------------------------------------
       # box_ipv6_Prefix ->  NewPreferedLifetime, NewIPv6Prefix, NewValidLifetime, NewPrefixLength

       FRITZBOX_Log $hash, 4, "ipv6_Prefix - start getting TR064 data";

       $service_command = "X_AVM_DE_GetIPv6Prefix";

       $soap_resp = FRITZBOX_SOAP_Request($hash,$control_url . "WANIPConn1", $service_type, $service_command);

       if(exists $soap_resp->{Error}) {
         FRITZBOX_Log $hash, 4, "SOAP/TR064-ERROR -> " . $soap_resp->{Error};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv6_Extern", $soap_resp->{ErrLevel} == 2?"unknown error":"";
 
       } elsif ( $soap_resp->{Response} ) {

         $strCurl = $soap_resp->{Response};
         FRITZBOX_Log $hash, 5, "Curl-> " . $strCurl;

         if($strCurl =~ m/<NewIPv6Prefix>(.*?)<\/NewIPv6Prefix>/i) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_ipv6_Prefix", $1;
         }
       }

       FRITZBOX_Log $hash, 4, "ipv6_Prefix - start getting TR064 data";

       # box_wan_AccessType

       FRITZBOX_Log $hash, 4, "AccessType - start getting TR064 data";

       $service_command = "GetCommonLinkProperties";

       $soap_resp = FRITZBOX_SOAP_Request($hash,$control_url . "WANCommonIFC1", "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1", $service_command);

       if(exists $soap_resp->{Error}) {
         FRITZBOX_Log $hash, 4, "SOAP/TR064-ERROR -> " . $soap_resp->{Error};
         FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wan_AccessType", $soap_resp->{ErrLevel} == 2?"unknown error":"";
 
       } elsif ( $soap_resp->{Response} ) {

         $strCurl = $soap_resp->{Response};
         FRITZBOX_Log $hash, 5, "Curl-> " . $strCurl;

         if($strCurl =~ m/<NewWANAccessType>(.*?)<\/NewWANAccessType>/i) {
           FRITZBOX_Readout_Add_Reading $hash, $roReadings, "box_wan_AccessType", $1;
         }
       }

     } elsif ($avmModel =~ "Repeater") {

     } else {
       FRITZBOX_Log $hash, 4, "unknown AVM Model $avmModel";
     }

   FRITZBOX_Log $hash, 4, "AccessType - end getting TR064 data";

   return "";

} # End FRITZBOX_Readout_Run_Web_TR064

#######################################################################
sub FRITZBOX_Readout_Response($$$@)
{
  my ($hash, $result, $roReadings, $retInfo, $sidNew, $addString) = @_;

  my $name      = $hash->{NAME};
  my $returnStr = "";

  my $xline       = ( caller(0) )[2];

  my $xsubroutine = ( caller(1) )[3];
  my $sub         = ( split( ':', $xsubroutine ) )[2];
  $sub =~ s/FRITZBOX_//       if ( defined $sub );
  $sub ||= 'no-subroutine-specified';


  if ( defined $result->{sid} && !defined $result->{AuthorizationRequired}) {
    push @{$roReadings}, "fhem->sid", $result->{sid} if $result->{sid};
    push @{$roReadings}, "fhem->sidTime", time();
    push @{$roReadings}, "fhem->sidErrCount", 0;
    push @{$roReadings}, "->WEBCONNECT", 1;

    if (defined $sidNew) {
      push @{$roReadings}, "fhem->sidNewCount", $sidNew;
    } elsif (defined $result->{sidNew}) {
      push @{$roReadings}, "fhem->sidNewCount", $result->{sidNew};
    } else {
      push @{$roReadings}, "fhem->sidNewCount", 0;
    }
  }

  elsif ( defined $result->{Error} ) {
    # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
    push @{$roReadings}, "->APICHECKED", -1;
    push @{$roReadings}, "->APICHECK_RET_CODES", $result->{Error};
    push @{$roReadings}, "Error", "cannot connect due to network error 500";
    push @{$roReadings}, "->WEBCONNECT", 0;
    push @{$roReadings}, "fhem->sidErrCount", $hash->{fhem}{sidErrCount} + 1;

    FRITZBOX_Log $hash, 2, "" . $result->{Error} . " - " . $sub . "(" . $xline . ")";
    $returnStr = "Error|" . $result->{Error};
    $returnStr .= "|";
  }

  elsif ( defined $result->{AuthorizationRequired} ) {
    # Abbruch wenn Fehler bei der Anmeldung an die FritzBox
    push @{$roReadings}, "->APICHECKED", -1;
    push @{$roReadings}, "->APICHECK_RET_CODES", $result->{AuthorizationRequired};
    push @{$roReadings}, "Error", "cannot connect due to authorisation error";
    push @{$roReadings}, "->WEBCONNECT", 0;
    push @{$roReadings}, "fhem->sidErrCount", $hash->{fhem}{sidErrCount} + 1;

    FRITZBOX_Log $hash, 2, "AuthorizationRequired=" . $result->{AuthorizationRequired} . " - " . $sub . "(" . $xline . ")";
    $returnStr = "Error|Authorization required";
    $returnStr .= "|";
  } 

  else {
    FRITZBOX_Log $hash, 4, "undefined situation\n" . " - " . $sub . "(" . $xline . ")"; # . Dumper($result);
    push @{$roReadings}, "->WEBCONNECT", 0;
    $returnStr = "Error|undefined situation" . " - " . $sub . "(" . $xline . ")";
    $returnStr .= "|";
  }

  if (defined $result->{ResetSID}) {
    if ($result->{ResetSID}) {
      my $sidCnt = $hash->{fhem}{sidErrCount} + 1;
      $returnStr .= "fhem->sidTime|0" . "|fhem->sidErrCount|$sidCnt";
      $returnStr .= "|";
    }
  }

  $returnStr .= join('|', @{$roReadings} ) if int @{$roReadings};

  if (defined $retInfo && $retInfo) {
    $returnStr = $name . "|" . $retInfo . "|" . encode_base64($returnStr,"");
    $returnStr .= $addString if defined $addString;
  } else {
    $returnStr = $name . "|" . encode_base64($returnStr,"");
  }

  FRITZBOX_Log $hash, 4, "Captured " . @{$roReadings} . " values";
  FRITZBOX_Log $hash, 4, "Handover to main process (" . length ($returnStr) . "): \n" . $returnStr;

  return $returnStr;

} # End FRITZBOX_Readout_Response

#######################################################################
sub FRITZBOX_Readout_Done($)
{
   my ($string) = @_;
   unless (defined $string)
   {
      Log 1, "Fatal Error: no parameter handed over";
      return;
   }

   my ($name, $string2) = split("\\|", $string, 2);
   my $hash = $defs{$name};

   FRITZBOX_Log $hash, 4, "Back at main process";

# delete the marker for RUNNING_PID process
   delete($hash->{helper}{READOUT_RUNNING_PID});

   $string2 = decode_base64($string2);

   FRITZBOX_Readout_Process ($hash, $string2);

} # end FRITZBOX_Readout_Done

#######################################################################
sub FRITZBOX_Readout_Process($$)
{
   my ($hash, $string) = @_;
 # Fatal Error: no hash parameter handed over
   unless (defined $hash) {
      Log 1, "Fatal Error: no hash parameter handed over";
      return;
   }

   my $startTime = time();

   my $name = $hash->{NAME};
   my (%values) = split("\\|", $string);

   my $reading_list = AttrVal($name, "disableBoxReadings", "none");
   my $filter_list  = AttrVal($name, "enableReadingsFilter", "none");

   $reading_list =~ s/,/\|/g;
   FRITZBOX_Log $hash, 4, "box_ disable list: $reading_list";

   $filter_list  =~ s/,/\|/g;
   $filter_list  =~ s/ID_/_/g;
   FRITZBOX_Log $hash, 4, "filter list: $filter_list";

   my $mesh = ReadingsVal($name, "box_meshRole", "master");

   readingsBeginUpdate($hash);

   if ( defined $values{Error} ) {
     readingsBulkUpdate( $hash, "retStat_lastReadoutError", $values{Error} );
     readingsBulkUpdate( $hash, "state", $values{Error} );
   }

   # Statistics
   if (defined $values{".calledFrom"} && $values{".calledFrom"} eq "runWeb") {

     if  ($mesh ne "slave") {
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
         $values{ "box_rateDown" } = sprintf ("%.3f", ($valueHigh+$valueLow) / $time ) ;
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
         $values{ "box_rateUp" } = sprintf ("%.3f", ($valueHigh+$valueLow) / $time ) ;
       }
     } else {
       $values{ "box_rateDown" } = "";
       $values{ "box_rateUp" } = "";
     }
   }

   # Fill all handed over readings
   my $x = 0;
   while (my ($rName, $rValue) = each(%values) ) {

     $rValue =~ s/&#0124/\|/g;  # handling valid character | in FritzBox names

     #hash values
     if ($rName =~ /->/) {

       # 4 levels
       my ($rName1, $rName2, $rName3, $rName4) = split /->/, $rName;

       # 4th level (Internal Value)
       if ($rName1 ne "" && defined $rName4) {
#         FRITZBOX_Log $hash, 3, "4th Level: $rName1 $rName2 $rName3 $rName4 - " . $rValue if $name eq "FritzBox";
         if($rValue eq "") {
           delete $hash->{$rName1}{$rName2}{$rName3}{$rName4} if exists $hash->{$rName1}{$rName2}{$rName3}{$rName4};
         } else {
           $hash->{$rName1}{$rName2}{$rName3}{$rName4} = $rValue;
         }
       }

       # 3rd level (Internal Value)
       elsif ($rName1 ne "" && defined $rName3) {
#         FRITZBOX_Log $hash, 3, "3rd Level: $rName1 $rName2 $rName3 - " . $rValue if $name eq "FritzBox";
         if($rValue eq "") {
           delete $hash->{$rName1}{$rName2}{$rName3} if exists $hash->{$rName1}{$rName2}{$rName3};
         } else {
           $hash->{$rName1}{$rName2}{$rName3} = $rValue;
         }
       }

       # 1st level (Internal Value)
       elsif ($rName1 eq "") {
#         FRITZBOX_Log $hash, 3, "1st Level: $rName2 - " . $rValue if $name eq "FritzBox";
         if($rValue eq "") {
           delete $hash->{$rName2} if exists $hash->{$rName2};
         } else {
           $hash->{$rName2} = $rValue;
         }
       }

       # 2nd levels
       else {
#         FRITZBOX_Log $hash, 3, "2nd Level: $rName1 $rName2 - " . $rValue if $name eq "FritzBox";
         if($rValue eq "") {
           delete $hash->{$rName1}{$rName2} if exists $hash->{$rName1}{$rName2};
         } else {
           $hash->{$rName1}{$rName2} = $rValue;
         }
       }
       
       delete ($hash->{HINWEIS_BOXUSER}) if $rName2 eq "HINWEIS_BOXUSER" && $rValue eq "";
       delete ($hash->{HINWEIS_PASSWORD}) if $rName2 eq "HINWEIS_PASSWORD" && $rValue eq "";
       readingsBulkUpdate( $hash, "state", "check API done" ) if $rName2 eq "APICHECKED";
       
     }

     elsif ($rName eq "-<fhem") {
       FRITZBOX_Log $hash, 4, "calling fhem() with: " . $rValue;
       fhem($rValue,1);
     }

     elsif ($rName eq "box_fwVersion" && defined $values{box_fwUpdate}) {
       $rValue .= " (old)" if $values{box_fwUpdate} eq "1";
     }

     elsif ( $rName eq "Error" ) {
       readingsBulkUpdate( $hash, "retStat_lastReadoutError", $rValue );
       readingsBulkUpdate( $hash, "state", $rValue );
     }
 
     elsif ($rName eq "box_model") {
       $hash->{MODEL} = $rValue;
       if (($rValue =~ "Box") && (lc($rValue) =~ "6[4,5,6][3,6,9][0,1]") ) {
         my $cable = "boxUser "
                  ."disable:0,1 "
                  ."nonblockingTimeOut:30,35,40,50,75,100,125 "
                  ."setgetTimeout:10,30,40,50,75,100,125 "
                  ."userAgentTimeOut "
                  ."INTERVAL "
                  ."reConnectInterval "
                  ."maxSIDrenewErrCnt "
                  ."userTickets "
                  ."enablePassivLanDevices:0,1 "
                  ."enableKidProfiles:0,1 "
                  ."enableVPNShares:0,1 "
                  ."enableUserInfo:0,1 "
                  ."enableAlarmInfo:0,1 "
                  ."enableWLANneighbors:0,1 "
                  ."enableMobileInfo:0,1 "
                  ."enableSmartHome:off,all,group,device "
                  ."wlanNeighborsPrefix "
                  ."disableHostIPv4check:0,1 "
                  ."disableDectInfo:0,1 "
                  ."disableFonInfo:0,1 "
                  ."enableSIP:0,1 "
                  ."enableReadingsFilter:multiple-strict,"
                                ."dectID_alarmRingTone,dectID_custRingTone,dectID_device,dectID_fwVersion,dectID_intern,dectID_intRingTone,"
                                ."dectID_manufacturer,dectID_model,dectID_NoRingWithNightSetting,dectID_radio,dectID_NoRingTime,"
                                ."shdeviceID_battery,shdeviceID_category,shdeviceID_device,shdeviceID_firmwareVersion,shdeviceID_manufacturer,"
                                ."shdeviceID_model,shdeviceID_status,shdeviceID_tempOffset,shdeviceID_temperature,shdeviceID_type,"
                                ."shdeviceID_voltage,shdeviceID_power,shdeviceID_current,shdeviceID_consumtion,shdeviceID_ledState,shdeviceID_state "
                  ."enableBoxReadings:multiple-strict,"
                                ."box_energyMode,box_globalFilter,box_led,box_dns_Srv,box_pwr,box_guestWlan,box_usb,box_notify "
                  ."enableLogReadings:multiple-strict,"
                                ."box_sys_Log,box_wlan_Log,box_fon_Log "
                  ."disableBoxReadings:multiple-strict,"
                                ."box_connect,box_connection_Type,box_cpuTemp,box_dect,box_dns_Server,box_dsl_downStream,box_dsl_upStream,"
                                ."box_guestWlan,box_guestWlanCount,box_guestWlanRemain,"
                                ."box_ipv4_Extern,box_ipv6_Extern,box_ipv6_Prefix,box_last_connect_err,box_mac_Address,box_macFilter_active,"
                                ."box_moh,box_powerRate,box_rateDown,box_rateUp,box_stdDialPort,box_tr064,box_tr069,"
                                ."box_upnp,box_upnp_control_activated,box_uptime,box_uptimeConnect,box_wan_AccessType,"
                                ."box_wlan_Count,box_wlan_2.4GHz,box_wlan_5GHz,box_wlan_Active,box_wlan_LogExtended,"
                                ."box_docsis30_Ds_powerLevels,box_docsis30_Ds_frequencys,box_docsis30_Ds_modulations,box_docsis30_Ds_latencys,box_docsis30_Ds_corrErrors,box_docsis30_Ds_nonCorrErrors,box_docsis30_Ds_mses,"
                                ."box_docsis31_Ds_powerLevels,box_docsis31_Ds_frequencys,box_docsis31_Ds_modulations,"
                                ."box_docsis30_Us_powerLevels,box_docsis30_Us_frequencys,box_docsis30_Us_modulations,"
                                ."box_docsis31_Us_powerLevels,box_docsis31_Us_frequencys,box_docsis31_Us_modulations "
                  ."deviceInfo:sortable,ipv4,name,uid,connection,speed,rssi,statIP,_noDefInf_ "
                  ."lanDeviceReading:mac,ip "
                  .$readingFnAttributes;

         setDevAttrList($hash->{NAME}, $cable);
       } else {
         setDevAttrList($hash->{NAME});
       }

       $rValue .= " [".$values{box_oem}."]" if $values{box_oem};
     }

     # writing all other readings
     if ($rName !~ /-<|->|box_fwUpdate|box_oem|readoutTime|Error/) {
       my $rFilter = $rName;
       $rFilter =~ s/[1-9]//g;
       if ($rValue ne "" && $rName !~ /$reading_list/) {
         if ( $rFilter =~ /$filter_list/) {
           delete $hash->{READINGS}{$rName} if ( exists $hash->{READINGS}{$rName} );
           readingsBulkUpdate( $hash, "." . $rName, $rValue );
           FRITZBOX_Log $hash, 4, "SET ." . $rName . " = '$rValue'";
         } else {
           $rFilter = "." . $rName;
           delete $hash->{READINGS}{$rFilter} if ( exists $hash->{READINGS}{$rFilter} );
           readingsBulkUpdate( $hash, $rName, $rValue );
           FRITZBOX_Log $hash, 4, "SET $rName = '$rValue'";
         }
       }
       elsif ( exists $hash->{READINGS}{$rName} ) {
         delete $hash->{READINGS}{$rName};
         FRITZBOX_Log $hash, 4, "Delete reading $rName.";
       }
       else  {
         FRITZBOX_Log $hash, 4, "Ignore reading $rName.";
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
     FRITZBOX_Log $hash, 4, "SET state = '$newState'";
   }

   # adapt TR064-Mode
   if ( defined $values{box_tr064} ) {
     if ( $values{box_tr064} eq "off" && defined $hash->{SECPORT} ) {
       FRITZBOX_Log $hash, 4, "TR-064 is switched off";
       delete $hash->{SECPORT};
       $hash->{TR064} = 0;
     }
     elsif ( $values{box_tr064} eq "on" && not defined $hash->{SECPORT} ) {
       FRITZBOX_Log $hash, 4, "TR-064 is switched on";
       my $tr064Port = FRITZBOX_init_TR064 ($hash, $hash->{HOST});
       $hash->{SECPORT} = $tr064Port if $tr064Port;
       $hash->{TR064} = 1;
     }
   }

   my $msg;
   if (keys( %values ) && $values{readoutTime}) {
     $msg = keys( %values ) . " values captured in " . $values{readoutTime} . " s";
   } else {
     $msg = "no values read out";
   }

   readingsBulkUpdate( $hash, "retStat_lastReadout", $msg );
   FRITZBOX_Log $hash, 4, "BulkUpdate lastReadout: " . $msg;

   readingsEndUpdate( $hash, 1 );

   readingsSingleUpdate( $hash, "retStat_processReadout", sprintf( "%.2f s", time()-$startTime), 1);

} # end FRITZBOX_Readout_Process

#######################################################################
sub FRITZBOX_Readout_Aborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{READOUT_RUNNING_PID});

  my $xline       = ( caller(0) )[2];

  my $xsubroutine = ( caller(1) )[3];
  my $sub         = ( split( ':', $xsubroutine ) )[2];
  $sub =~ s/FRITZBOX_//       if ( defined $sub );
  $sub ||= 'no-subroutine-specified';

  my $msg = "Error: Timeout when reading Fritz!Box data. $xline | $sub";

  readingsSingleUpdate($hash, "retStat_lastReadout", $msg, 1);
  readingsSingleUpdate($hash, "state", $msg, 1);

  FRITZBOX_Log $hash, 1, $msg;

} # end FRITZBOX_Readout_Aborted

#######################################################################
sub FRITZBOX_Readout_Format($$$)
{
   my ($hash, $format, $readout) = @_;

   return "" unless defined $readout;
   return $readout unless defined( $format ) && $format ne "";

   if ($format eq "01" && $readout ne "1") {
      $readout = "0";
   }

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
         chop($readout);
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
      $readout .= " (".$hash->{fhem}{$intern}{name}.")" if defined $hash->{fhem}{$intern}{name};
   }
   elsif ($format eq "altime") {
      $readout =~ s/(\d\d)(\d\d)/$1:$2/;
   }
   elsif ($format eq "deviceip") {
      $readout = $landevice{$readout}." ($readout)" if defined $landevice{$readout};
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
      $readout =~ s/^0*$/off/;
      $readout =~ s/^1*$/on/;
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

} # end FRITZBOX_Readout_Format

#######################################################################
sub FRITZBOX_Readout_Add_Reading ($$$$@)
{
   my ($hash, $roReadings, $rName, $rValue, $rFormat) = @_;

   # Handling | as valid character in FritzBox names
   $rValue =~ s/\|/&#0124/g if defined $rValue;

   $rFormat = "" unless defined $rFormat;
   $rValue = FRITZBOX_Readout_Format ($hash, $rFormat, $rValue);

   push @{$roReadings}, $rName . "|" . $rValue ;

   FRITZBOX_Log $hash, 4, "$rName: $rValue";

} # end FRITZBOX_Readout_Add_Reading

##############################################################################################################################################
# Ab hier alle Sub, die für die nonBlocking set/get Aufrufe zuständig sind
##############################################################################################################################################

#######################################################################

sub FRITZBOX_Readout_SetGet_Start($)
{
   my ($timerpara) = @_;

   my $index = rindex( $timerpara, "." );    # rechter punkt
   my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash = $defs{$name};
   my $cmdBufTimeoutOffSet = $cmdBufferTimeout + AttrVal($name, "setgetTimeout", 10);

   my $cmdFunction;
   my $timeout;
   my $handover;

   return "no command in buffer." unless int @cmdBuffer;

 # kill old process if timeout + 10s is reached
   if ( exists( $hash->{helper}{CMD_RUNNING_PID}) && time() > ($cmdBufTimeoutOffSet) ) {
      FRITZBOX_Log $hash, 1, "Old command still running. Killing old command: " . $cmdBuffer[0];
      shift @cmdBuffer;
      BlockingKill( $hash->{helper}{CMD_RUNNING_PID} );
      # stop FHEM, giving FritzBox some time to free the memory
      delete $hash->{helper}{CMD_RUNNING_PID};
      return "INFO: no more command in buffer." unless int @cmdBuffer;
   }

 # (re)start timer if command buffer is still filled
   if (int @cmdBuffer > 1) {
      my @val = split / /, $cmdBuffer[0];
      FRITZBOX_Log $hash, 3, "restarting internal Timer: next set/get: $val[0] will be processed";
      RemoveInternalTimer($hash->{helper}{TimerCmd});
      InternalTimer(gettimeofday() + 1, "FRITZBOX_Readout_SetGet_Start", $hash->{helper}{TimerCmd}, 1);
   }

# do not continue until running command has finished or is aborted
   return "INFO: Process " . $hash->{helper}{CMD_RUNNING_PID} . " is still running" if exists $hash->{helper}{CMD_RUNNING_PID};

   my @val = split / /, $cmdBuffer[0];

   my $xline       = ( caller(0) )[2];
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//       if ( defined $sub );
   $sub ||= 'no-subroutine-specified';

   FRITZBOX_Log $hash, 4, "Set_CMD_Start -> $sub.$xline -> $val[0]";

# Preparing SET Call
   if ($val[0] eq "call") {
      shift @val;
      $timeout = 60;
      $timeout = $val[2]         if defined $val[2] && $val[2] =~/^\d+$/;
      $timeout += 30;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_call_Phone";
   }
# Preparing SET guestWLAN
   elsif ($val[0] eq "guestwlan") {
      shift @val;
      $timeout = 20;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_GuestWlan_OnOff";
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
      $cmdFunction = "FRITZBOX_Set_ring_Phone";
   }
# Preparing SET WLAN
   elsif ($val[0] eq "wlan") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_Wlan_OnOff";
   }
# Preparing SET WLAN2.4
   elsif ( $val[0] =~ /^wlan(2\.4|5)$/ ) {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_Wlan_OnOff";
   }
# Preparing SET wlanlogextended
   elsif ($val[0] eq "wlanlogextended") {
      $timeout = 20;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_Wlan_Log_Ext_OnOff";
   }
# Preparing SET wlanguestparams
   elsif ($val[0] eq "wlanguestparams") {
      $timeout = 20;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_Wlan_Guest_Params";
   }
# Preparing SET rescanWLANneighbors
   elsif ( $val[0] eq "rescanwlanneighbors" ) {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_rescan_Neighborhood";
   }
# Preparing SET macFilter
   elsif ($val[0] eq "macfilter") {
      $timeout = 25;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_macFilter_OnOff";
   }
# Preparing SET chgProfile
   elsif ($val[0] eq "chgprofile") {
      $timeout = 25;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_change_Profile";
   }
# Preparing SET lockLandevice
   elsif ($val[0] eq "locklandevice") {
      $timeout = 25;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      if ($hash->{fhem}{fwVersion} < 800) {
        $cmdFunction = "FRITZBOX_Set_lock_Landevice_OnOffRt";
      } else {
        $cmdFunction = "FRITZBOX_Set_lock_Landevice_OnOffRt_8";
      }
   }
# Preparing SET enableVPNshare
   elsif ($val[0] eq "enablevpnshare") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_enable_VPNshare_OnOff";
   } 
# Preparing SET blockIncomingPhoneCall
   elsif ($val[0] eq "blockincomingphonecall") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_block_Incoming_Phone_Call";
   }
# Preparing SET wakeUpCall
   elsif ($val[0] eq "wakeupcall") {
      $timeout = 10;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Set_wake_Up_Call";
   }
# Preparing GET fritzlog information
   elsif ($val[0] eq "fritzloginfo") {
      $timeout = 20;
      $cmdBufferTimeout = time() + $timeout;
      $handover = $name . "|" . join( "|", @val );
      $cmdFunction = "FRITZBOX_Get_Fritz_Log_Info_nonBlk";
   }
# No valid set operation 
   else {
      my $msg = "ERROR: Unknown command '".join( " ", @val )."'";
      FRITZBOX_Log $hash, 4, "" . $msg;
      return $msg;
   }

# Starting new command
   FRITZBOX_Log $hash, 4, "Fork process $cmdFunction";
   $hash->{helper}{CMD_RUNNING_PID} = BlockingCall($cmdFunction, $handover,
                                       "FRITZBOX_Readout_SetGet_Done", $timeout,
                                       "FRITZBOX_Readout_SetGet_Aborted", $hash);
   $hash->{helper}{CMD_RUNNING_PID}->{loglevel} = GetVerbose($name);

   return "FRITZBOX_Readout_SetGet_Start done";

} # end FRITZBOX_Readout_SetGet_Start

#######################################################################
sub FRITZBOX_Readout_SetGet_Done($)
{
   my ($string) = @_;

   unless (defined $string)
   {
      Log 1, "FATAL ERROR: no parameter handed over";
      return;
   }

   my ($name, $success, $result) = split("\\|", $string, 3);
   my $hash = $defs{$name};

   FRITZBOX_Log $hash, 4, "Back at main process";

   shift (@cmdBuffer);
   delete($hash->{helper}{CMD_RUNNING_PID});

   # ungültiger Rückgabewerte. Darf nicht vorkommen
   if ( $success !~ /1|2|3/ )
   {
      FRITZBOX_Log $hash, 1, "" . $result;
      FRITZBOX_Readout_Process ( $hash, "Error|" . $result );
   }
   # alles ok. Es wird keine weitere Bearbeitung benötigt
   elsif ( $success == 1 )
   {
      FRITZBOX_Log $hash, 4, "" . $result;
   }
   # alles ok und es müssen noch Readings verarbeitet werden
   elsif  ($success == 2 )
   {
      $result = decode_base64($result);
      FRITZBOX_Readout_Process ( $hash, $result );
   }
   # internes FritzBox Log: alles ok und es findet noch eine Nachverarbeitung durch eine sub in einer 99_...pm statt.
   elsif  ($success == 3 )
   {
      my ($resultOut, $cmd, $logJSON) = split("\\|", $result, 3);
      $result = decode_base64($resultOut);
      FRITZBOX_Readout_Process ( $hash, $result );

      FRITZBOX_Log $hash, 5, "fritzLog to Sub: $cmd \n" . $logJSON;

      my $jsonResult = eval { JSON->new->latin1->decode( $logJSON ) };
      if ($@) {
        FRITZBOX_Log $hash, 2, "Decode JSON string: decode_json failed, invalid json. error:$@";
      }

      FRITZBOX_Log $hash, 5, "Decode JSON string: " . ref($jsonResult);

      my $returnStr = eval { myUtilsFritzLogExPost ($hash, $cmd, $jsonResult); };

      if ($@) {
        FRITZBOX_Log $hash, 2, "fritzLogExPost: " . $@;
        readingsSingleUpdate($hash, "retStat_fritzLogExPost", "->ERROR: " . $@, 1);
      } else {
        readingsSingleUpdate($hash, "retStat_fritzLogExPost", $returnStr, 1);
      }
   }

} # end FRITZBOX_Readout_SetGet_Done

#######################################################################
sub FRITZBOX_Readout_SetGet_Aborted($)
{
  my ($hash) = @_;
  my $lastCmd = shift (@cmdBuffer);
  delete($hash->{helper}{CMD_RUNNING_PID});
  FRITZBOX_Log $hash, 1, "Timeout reached for: $lastCmd";

} # end FRITZBOX_Readout_SetGet_Aborted

# Checks which API is available on the Fritzbox
#######################################################################
sub FRITZBOX_Set_check_APIs($)
{
   my ($name)     = @_;
   my $hash       = $defs{$name};
   my $fritzShell = 0;
   my $content    = "";
   my $fwVersion  = "0.0.0.error";
   my $startTime  = time();
   my $apiError   = "";
   my $luaQueryOk = 0;
   my $crdOK      = 0;
   my @roReadings;
   my $response;

   my $host       = $hash->{HOST};
   my $myVerbose  = $hash->{APICHECKED} == 0? 1 : 0;
   my $boxUser    = AttrVal( $name, "boxUser", "" );

   if ( $host =~ /undefined/ || $boxUser eq "") {
     my $tmp = "";
        $tmp = "fritzBoxIP" if $host =~ /undefined/;
        $tmp .= ", " if $host =~ /undefined/ && $boxUser eq "";
        $tmp .= " boxUser (bei Repeatern oder Fritz!OS < 7.25 nicht unbedingt notwendig)" if $boxUser eq "";
        $tmp .= " nicht definiert. Bitte auch das Passwort mit <set $name password> setzen.";

     FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HINWEIS_BOXUSER", $tmp);

     FRITZBOX_Log $hash, 3, "" . $tmp;
   } else {
     FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HINWEIS_BOXUSER", "");
   }

   unless (FRITZBOX_Helper_read_Password($hash)) {
     FRITZBOX_Log $hash, 2, "No password set. Please define it (once) with 'set $name password YourPassword'";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->HINWEIS_PASSWORD", "No password set. Please define it (once) with 'set $name password YourPassword'";
   } else {
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->HINWEIS_PASSWORD", "";
     $crdOK = 1;
   }

# change host name if necessary
   FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "->HOST", $host) if $host ne $hash->{HOST};

# Check if perl modules for remote APIs exists
   if ($missingModul) {
      FRITZBOX_Log $hash, 3, "Cannot check for box model and APIs webcm, luaQuery and TR064 because perl modul $missingModul is missing on this system.";
   }

# Check for remote APIs
   else {
      my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);

      # Check if query.lua exists
      $response = $agent->get( "http://".$host."/query.lua" );

      if ($response->is_success) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 1;
         FRITZBOX_Log $hash, 5-$myVerbose, "API luaQuery found (" . $response->code . ").";
         $luaQueryOk = 1;
      }
      elsif ($response->code eq "403") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 1;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaQuery call responded with: " . $response->status_line;
         $luaQueryOk = 1;
      }
      elsif ($response->code eq "500") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaQuery call responded with: " . $response->status_line;
      }
      elsif ($response->code eq "303") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaQuery call responded with: " . $response->status_line;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUAQUERY", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaQuery does not exist (" . $response->status_line . ")";
      }

      $apiError = "luaQuery:" . $response->code;

   # Check if data.lua exists
      $response = $agent->get( "http://".$host."/data.lua" );

      if ($response->is_success) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 1;
         FRITZBOX_Log $hash, 5-$myVerbose, "API luaData found (" . $response->code . ").";
         # xhr 1 lang de page netSet xhrId all
      }
      elsif ($response->code eq "403") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 1;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaData call responded with: " . $response->status_line;
      }
      elsif ($response->code eq "500") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaData call responded with: " . $response->status_line;
      }
      elsif ($response->code eq "303") {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaData call responded with: " . $response->status_line;
      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->LUADATA", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API luaData does not exist (" . $response->status_line . ")";
      }

      $apiError .= " luaData:" . $response->code;

   # Check if tr064 specification exists and determine TR064-Port
      $response = $agent->get( "http://".$host.":49000/tr64desc.xml" );

      if ($response->is_success) { #determine TR064-Port
         $content   = $response->content;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TR064", 1;
         FRITZBOX_Log $hash, 5-$myVerbose, "API TR-064 found.";

         #Determine TR064-Port
         my $tr064Port = FRITZBOX_init_TR064 ( $hash, $host );
         if ($tr064Port) {
            FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->SECPORT", $tr064Port;
            $hash->{SECPORT} = $tr064Port;
            FRITZBOX_Log $hash, 5-$myVerbose, "TR-064-SecurePort is $tr064Port.";
         }
         else {
            FRITZBOX_Log $hash, 4-$myVerbose, "TR-064-SecurePort does not exist";
         }

      }
      else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->TR064", 0;
         FRITZBOX_Log $hash, 4-$myVerbose, "API TR-064 not available: " . $response->status_line if $response->code != 500;
      }

      $apiError .= " TR064:" . $response->code;

      # Ermitteln Box Model, FritzOS Version, OEM aus TR064 Informationen
      if ($response->is_success && $content =~ /<modelName>/) {
        FRITZBOX_Log $hash, 5-$myVerbose, "TR064 returned: $content";

        if ($content =~ /<modelName>(.*)<\/modelName>/) {
          FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_model", $1);
          $hash->{boxModel} = $1;
        }
        FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_oem", $1)       if $content =~ /<modelNumber>(.*)<\/modelNumber>/;
        FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_fwVersion", $1) if $content =~ /<Display>(.*)<\/Display>/ ;
        $fwVersion = $1 if $content =~ /<Display>(.*)<\/Display>/ ;

      }

      if ( $fwVersion =~ /error/ && $response->code != 500 && $crdOK) {
        # Ansonsten ermitteln Box Model, FritzOS Version, OEM aus jason_boxinfo
        FRITZBOX_Log $hash, 4, "Read 'jason_boxinfo' from " . $host;

        $FRITZBOX_TR064pwd = FRITZBOX_Helper_read_Password($hash);

        if ($FRITZBOX_TR064pwd) {

          $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
          my $url   = "http://" . $host . "/jason_boxinfo.xml";
          $response = $agent->get( $url );

          unless ($response->is_success) {

            FRITZBOX_Log $hash, 4, "retry with password 'jason_boxinfo' from " . $host;

            my $agentPW  = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
            my $req      = HTTP::Request->new( GET => "http://" . $host . "/jason_boxinfo.xml");
               $req->authorization_basic( "$boxUser", "$FRITZBOX_TR064pwd" );
            $response    = $agentPW->request( $req );
          }

          $content   = $response->content;
          $apiError .= " boxModelJason:" . $response->code;

          if ($response->is_success && $content =~ /<j:Name>/) {
            FRITZBOX_Log $hash, 5-$myVerbose, "jason_boxinfo returned: $content";

            if ($content =~ /<j:Name>(.*)<\/j:Name>/) {
              FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_model", $1);
              $hash->{boxModel} = $1;
            }
            FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_oem", $1)       if $content =~ /<j:OEM>(.*)<\/j:OEM>/;
            FRITZBOX_Readout_Add_Reading ($hash, \@roReadings, "box_fwVersion", $1) if $content =~ /<j:Version>(.*)<\/j:Version>/ ;
            $fwVersion = $1 if $content =~ /<j:Version>(.*)<\/j:Version>/ ;

          } else {
            FRITZBOX_Log $hash, 4-$myVerbose, "jason_boxinfo returned: $response->is_success with $content";

            # Ansonsten ermitteln Box Model, FritzOS Version, OEM aus cgi-bin/system_status
            FRITZBOX_Log $hash, 4, "retry with password 'cgi-bin/system_status' from " . $host;

            $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
            $url = "http://".$host."/cgi-bin/system_status";
            $response = $agent->get( $url );

            unless ($response->is_success) {
              FRITZBOX_Log $hash, 4, "read 'cgi-bin/system_status' from " . $host;
  
              my $agentPW  = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10);
              my $req      = HTTP::Request->new( GET => "http://" . $host . "/cgi-bin/system_status");
                 $req->authorization_basic( "$boxUser", "$FRITZBOX_TR064pwd" );
              $response    = $agentPW->request( $req );
            }

            $apiError   .= " boxModelSystem:" . $response->code;
            $content     = $response->content;

            FRITZBOX_Log $hash, 5-$myVerbose, "system_status returned: $content";

            if ($response->is_success) {
              $content = $1 if $content =~ /<body>(.*)<\/body>/;

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
              $hash->{boxModel} = $result[0];

              my $FBOS = $result[7];
              $FBOS = substr($FBOS,0,3) . "." . substr($FBOS,3,2) . "." . substr($FBOS,5,2);
              FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_fwVersion", $FBOS;
              FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_oem",    $result[9];
              $fwVersion = $result[7];

            } else {
              FRITZBOX_Log $hash, 4-$myVerbose, "" . $response->status_line;
            }
          }
          $FRITZBOX_TR064pwd = undef;
        } else {
          FRITZBOX_Log $hash, 2, "No password set. Please define it (once) with 'set $name password YourPassword'";
          FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->HINWEIS_PASSWORD", "No password set. Please define it (once) with 'set $name password YourPassword'";
        }
      }
   }

   my @fwV = split(/\./, $fwVersion);
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->fwVersion", substr($fwV[1],0,2) * 100 + substr($fwV[2],0,2);
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->fwVersionStr", substr($fwV[1],0,2) . "." . substr($fwV[2],0,2);

   if ($apiError =~ /303|500/) {

     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECKED", -1;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECK_RET_CODES", $apiError;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "Error", "cannot connect due to network error " . $apiError;

     $hash->{fhem}{sidTime} = 0;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", 0;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", $hash->{fhem}{sidErrCount} + 1;

   } else {

     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECKED", 1;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECK_RET_CODES", "Ok";

     $hash->{fhem}{sidTime} = 0;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", 0;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;

     # initialize first SID if password available
     if ( $crdOK ) {
       my $result = FRITZBOX_open_Web_Connection( $hash );

       if (defined $result->{Error}) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "Error", $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->WEBCONNECT", 0;

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", 0;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", $hash->{fhem}{sidErrCount} + 1;

       } else {
         my $sidNew = defined $result->{sidNew} ? $result->{sidNew} : 0;

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidNewCount", $sidNew;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->WEBCONNECT", 1;


         if($luaQueryOk) {

           my $queryStr = "";

           foreach my $key (keys %{ $hash->{LuaQueryCmd} }) {
             FRITZBOX_Log $hash, 4, $key . ": " . $hash->{LuaQueryCmd}{$key}{active} . ": " . $hash->{LuaQueryCmd}{$key}{AttrVal};
             $queryStr .= "&" . $key . "=" . $hash->{LuaQueryCmd}{$key}{cmd};
           }

           FRITZBOX_Log $hash, 4, "ReadOut gestartet: $queryStr";
           $response = FRITZBOX_call_Lua_Query( $hash, $queryStr, "", "luaQuery") ;

           if ( !defined $response->{sid} || defined $response->{Error} || defined $response->{AuthorizationRequired} ) {
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->APICHECKED", -1;
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "->WEBCONNECT", 0;
             $apiError = "luaQuery:";
             $apiError .= " empty sid" if !defined $response->{sid};
             $apiError .= " error: $response->{Error}" if defined $response->{Error};
             $apiError .= " authorization: $response->{AuthorizationRequired}" if defined $response->{AuthorizationRequired};
             FRITZBOX_Log $hash, 4, "$queryStr: not Ok";
           } else {

             foreach my $key (keys %{ $hash->{LuaQueryCmd} }) {

               if((ref $response->{$key} ne 'ARRAY') && ref \$response->{$key} ne "SCALAR") {
                 FRITZBOX_Log $hash, 4, "$key = $hash->{LuaQueryCmd}{$key}{cmd}: 2 not Ok";

                 FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "LuaQuery->" . $key . "->active", 0;

               } elsif(ref $response->{$key} eq 'ARRAY') {
                 my $views = $response->{$key};
                 if(scalar(@$views) == 0) {
                   FRITZBOX_Log $hash, 4, "$key = $hash->{LuaQueryCmd}{$key}{cmd}: 3 not Ok";

                   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "LuaQueryCmd->" . $key . "->active", 0;
                 } else {
                   FRITZBOX_Log $hash, 4, "$key = $hash->{LuaQueryCmd}{$key}{cmd}: Ok";
                   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "LuaQueryCmd->" . $key . "->active", 1;
                 }

               } elsif ($response->{$key} eq "") {
                 FRITZBOX_Log $hash, 4, "$key = $hash->{LuaQueryCmd}{$key}{cmd}: 4 not Ok";

                 FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "LuaQueryCmd->" . $key . "->active", 0;

               } else {
                 FRITZBOX_Log $hash, 4, "$key = $hash->{LuaQueryCmd}{$key}{cmd}: Ok";
                 FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "LuaQueryCmd->" . $key . "->active", 1;
               }
             }
           }

         } # End if($luaQueryOk)

       }

     }
   }

   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, ".calledFrom", "checkApis";

   my $returnStr = join('|', @roReadings );

   FRITZBOX_Log $hash, 3, "Response -> " . $apiError;
   FRITZBOX_Log $hash, 4, "Captured " . @roReadings . " values";
   FRITZBOX_Log $hash, 5, "Handover to main process (" . length ($returnStr) . "): " . $returnStr;

   return $name . "|" . encode_base64($returnStr,"");

} #end FRITZBOX_Set_check_APIs

#######################################################################
sub FRITZBOX_Set_block_Incoming_Phone_Call($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $startTime = time();

   # create new one
   # numbertype0..n: home, work, mobile, fax_work

   # xhr 1 idx nop uid nop entryname Testsperre numbertypenew0 home numbernew0 02234983525 bookid 258 apply nop lang de page fonbook_entry

   # xhr: 1
   # idx: 
   # uid: 
   # entryname: NeuTest
   # numbertypenew1: home
   # numbernew1: 02234983525
   # numbertypenew2: mobile
   # numbernew2: 
   # numbertypenew3: work
   # numbernew3: 
   # bookid: 258
   # back_to_page: /fon_num/fonbook_list.lua
   # sid: 263f9332a5f818b7
   # apply: 
   # lang: de
   # page: fonbook_entry

   # change exsisting
   # xhr: 1
   # idx: 
   # uid: 142
   # entryname: Testsperre
   # numbertype0: home
   # number0: 02234983524
   # numbertypenew2: mobile
   # numbernew2: 
   # numbertypenew3: work
   # numbernew3: 
   # bookid: 258
   # back_to_page: /fon_num/fonbook_list.lua
   # sid: 263f9332a5f818b7
   # apply: 
   # lang: de
   # page: fonbook_entry

   # delete all
   # xhr: 1
   # sid: 263f9332a5f818b7
   # bookid: 258
   # delete_entry: 137
   # oldpage: /fon_num/sperre.lua
   # page: callLock

   # get info
   # xhr: 1
   # sid: 263f9332a5f818b7
   # page: callLock
   # xhr 1 page callLock

   # set <name> blockIncomingPhoneCall <new> <name> <number> <home|work|mobile|fax_work>
   # set <name> blockIncomingPhoneCall <chg|del> <name> <number> <home|work|mobile|fax_work> <id>

   # get info about existing income call blockings
   push @webCmdArray, "xhr"  => "1";
   push @webCmdArray, "page" => "callLock";

   FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting blockIncomingPhoneCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_blockIncomingPhoneCall", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   if($val[0] =~ /new|tmp/) {
     # xhr 1 idx nop uid nop entryname Testsperre numbertypenew0 home numbernew0 02234983525 bookid 258 apply nop lang de page fonbook_entry

     my $search = Dumper($result);
     FRITZBOX_Log $hash, 5, "blockIncomingPhoneCall result: " . $search;

     if ($search =~ /$val[1]/) {
       FRITZBOX_Log $hash, 3, "setting blockIncomingPhoneCall: new name $val[1] exists";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_blockIncomingPhoneCall", "->ERROR: new name $val[1] exists";

       $sidNew += $result->{sidNew} if $result->{sidNew};

       # Ende und Rückkehr zum Hauptprozess
       push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
       return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);
     }

     @webCmdArray = ();
     push @webCmdArray, "xhr"            => "1";
     push @webCmdArray, "idx"            => "";
     push @webCmdArray, "uid"            => "";
     push @webCmdArray, "entryname"      => $val[1];
     push @webCmdArray, "numbertypenew0" => $val[3];
     push @webCmdArray, "numbernew0"     => $val[2];
     push @webCmdArray, "bookid"         => "258";
     push @webCmdArray, "apply"          => "";
     push @webCmdArray, "lang"           => "de";
     push @webCmdArray, "page"           => "fonbook_entry";

   } elsif ($val[0] eq "chg") {
     @webCmdArray = ();
     push @webCmdArray, "xhr"            => "1";

   } elsif ($val[0] eq "del") {
     @webCmdArray = ();
     push @webCmdArray, "xhr"            => "1";
     push @webCmdArray, "bookid"         => "258";
     push @webCmdArray, "delete_entry"   => $val[1];
     push @webCmdArray, "page"           => "callLock";
   }

   FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting blockIncomingPhoneCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_blockIncomingPhoneCall", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   # get refreshed info about existing income call blockings
   @webCmdArray = ();
   push @webCmdArray, "xhr"  => "1";
   push @webCmdArray, "page" => "callLock";

   FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;
   my $search = Dumper($result);

   FRITZBOX_Log $hash, 5, "blockIncomingPhoneCall change result: " . $search;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting blockIncomingPhoneCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_blockIncomingPhoneCall", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

# tmp TestTmpNeu 02234983525 home 2023-10-12T22:00:00
   if($val[0] =~ /new|tmp/ ) {
     my $views = $result->{data};
     my $nbViews = scalar @$views;

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         if ($result->{data}->[$i]->{name} eq $val[1]) {
           if ( $val[0] eq "tmp" ) {
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "blocked_tmp_" . $val[2], "name: " . $result->{data}->[$i]->{name} . " UID: " . $result->{data}->[$i]->{uid};
             my $dMod = 'defmod tmp_block_' . $val[1] . ' at ' . $val[4] . ' { ' . $name . ' blockIncomingPhoneCall del ' . $result->{data}->[$i]->{uid} . '", 0)} ';
             FRITZBOX_Log $hash, 4, "setting blockIncomingPhoneCallDelAt: " . $dMod;
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "-<fhem", $dMod;
           } else {
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "blocked_" . $val[2], "name: " . $result->{data}->[$i]->{name} . " UID: " . $result->{data}->[$i]->{uid};
           }
         }
       }
     };

     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_blockIncomingPhoneCall", "done";

   } elsif ($val[0] eq "chg") {
     # not implemented and will not be implemented

   } elsif ($val[0] eq "del") {
     foreach (keys %{ $hash->{READINGS} }) {
       if ($_ =~ /^blocked_/ && $hash->{READINGS}{$_}{VAL} =~ /$val[1]/) {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $_, "";
         FRITZBOX_Log $hash, 4, "blockIncomingPhoneCall Reading " . $_ . ":" . $hash->{READINGS}{$_}{VAL};
       }
     }

     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_blockIncomingPhoneCall", "done with readingsDelete";
   }

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_block_Incoming_Phone_Call

sub FRITZBOX_Set_wake_Up_Call($)
#######################################################################
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $startTime = time();

   # xhr 1 lang de page alarm xhrId all

   # xhr: 1
   # active: 1 | 0
   # hour: 07
   # minutes: 00
   # device: 70
   # name: Wecker 1
   # optionRepeat: daily | only_once | per_day { mon: 1 tue: 0 wed: 1 thu: 0 fri: 1 sat: 0 sun: 0 }
   # apply: true
   # lang: de
   # page: alarm | alarm1 | alarm2

   my $wecker = "Fhem Device $name Wecker ";
   $wecker .= substr($val[0],-1);

   my $page;
       $page = "alarm"  if $val[0] =~ /alarm1/;
       $page = "alarm1" if $val[0] =~ /alarm2/;
       $page = "alarm2" if $val[0] =~ /alarm3/;

   push @webCmdArray, "xhr"      => "1";

#   if ($FW1 == 7 && $FW2 < 50) {
   if ($hash->{fhem}{fwVersion} >= 700 && $hash->{fhem}{fwVersion} < 750) {
     push @webCmdArray, "apply"    => "";
   } else {
     push @webCmdArray, "apply"    => "true";
   }
   push @webCmdArray, "lang"     => "de";

   # alarm1 62 per_day 10:00 mon:1 tue:0 wed:1 thu:0 fri:1 sat:0 sun:0
   # alarm1 62 only_once 08:03

   # set <name> wakeUpCall <alarm1|alarm2|alarm3> <off>
   if (int @val == 2) {          # turn wakeUpCall off
     push @webCmdArray, "page"     => $page;
     push @webCmdArray, "active"   => "0";
   } elsif (int @val > 2) {
     push @webCmdArray, "active"   => "1";
     push @webCmdArray, "page"     => $page;
     push @webCmdArray, "device"   => $val[1];
     push @webCmdArray, "hour"     => substr($val[3],0,2);
     push @webCmdArray, "minutes"  => substr($val[3],3,2);
     push @webCmdArray, "name"     => $wecker;

     if ( $val[2] =~ /^(daily|only_once)$/) {
       push @webCmdArray, "optionRepeat"   => $val[2];
     } elsif ( $val[2] eq "per_day" ) {
       push @webCmdArray, "optionRepeat"   => $val[2];

       for(my $i = 4; $i <= 10; $i++) {
         push @webCmdArray, substr($val[$i],0,3) => substr($val[$i],4,1);
       }
     }
   }

   FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting wakeUpCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wakeUpCall", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wakeUpCall", "done";

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_wake_Up_Call

#######################################################################
sub FRITZBOX_Set_Wlan_Log_Ext_OnOff($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $startTime = time();
   my $returnCase = 2;
   my $returnLog = "";

   # Frizt!OS >= 7.50
   # xhr 1 lang de page log apply nop filter wlan wlan on | off             -> on oder off erweitertes WLAN-Logging

   # xhr 1 lang de page log xhrId log filter all  useajax 1 no_sidrenew nop -> Log-Einträge Alle
   # xhr 1 lang de page log xhrId log filter sys  useajax 1 no_sidrenew nop -> Log-Einträge System
   # xhr 1 lang de page log xhrId log filter wlan useajax 1 no_sidrenew nop -> Log-Einträge WLAN
   # xhr 1 lang de page log xhrId log filter usb  useajax 1 no_sidrenew nop -> Log-Einträge USB
   # xhr 1 lang de page log xhrId log filter net  useajax 1 no_sidrenew nop -> Log-Einträge Internetverbindung
   # xhr 1 lang de page log xhrId log filter fon  useajax 1 no_sidrenew nop -> Log-Einträge Fon

   # Frizt!OS < 7.50
   # xhr 1 lang de page log xhrId all             wlan 7 (on) | 6 (off)     -> on oder off erweitertes WLAN-Logging

   # xhr 1 lang de page log xhrId log filter 0    useajax 1 no_sidrenew nop -> Log-Einträge Alle
   # xhr 1 lang de page log xhrId log filter 1    useajax 1 no_sidrenew nop -> Log-Einträge System
   # xhr 1 lang de page log xhrId log filter 4    useajax 1 no_sidrenew nop -> Log-Einträge WLAN
   # xhr 1 lang de page log xhrId log filter 5    useajax 1 no_sidrenew nop -> Log-Einträge USB
   # xhr 1 lang de page log xhrId log filter 2    useajax 1 no_sidrenew nop -> Log-Einträge Internetverbindung
   # xhr 1 lang de page log xhrId log filter 3    useajax 1 no_sidrenew nop -> Log-Einträge Fon

   FRITZBOX_Log $hash, 4, "fritzlog -> $cmd, $val[0]";
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "log";

   if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
     push @webCmdArray, "wlan"        => $val[0] eq "on" ? "7" : "6";
   } elsif ($hash->{fhem}{fwVersion} >= 750) {
     push @webCmdArray, "filter"      => "wlan";
     push @webCmdArray, "apply"       => "";
     push @webCmdArray, "wlan"        => $val[0];
   } else {
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanLogExtended", "Not supported Fritz!OS $hash->{fhem}{fwVersionStr}";
   }

   FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting wakeUpCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanGuestParams", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Log $hash, 4, "wlanLogExtended: " . $result->{data}->{wlan};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanLogExtended", $result->{data}->{apply};
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_LogExtended", $result->{data}->{wlan} ? "on" : "off";

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_Wlan_Log_Ext_OnOff

#######################################################################
sub FRITZBOX_Set_Wlan_Guest_Params($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $startTime = time();
   my $returnCase = 2;
   my $returnLog = "";

   FRITZBOX_Log $hash, 4, "wlan_guest_name -> $cmd, " . join( " ", @val );

   # xhr 1 lang de page wGuest xhrId all

   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "wGuest";
   push @webCmdArray, "xhrId"       => "all";

   FRITZBOX_Log $hash, 4, "data.lua status: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting wakeUpCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanGuestParams", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   # getting Parameters
   my %paraPos;
   my $lastPos = (int @val) - 1;

   for (my $i = (int @val) - 1; $i >= 0; $i--) {
     if ($val[$i] =~ /ssid:|pwd:|wlan:|mode:|tmo:|tmoActive:|tmoNoForcedOff:/) {
       my $para = $val[$i];
	   $para =~ s/\:.*//;

       my $text = join(' ', @val[$i..$lastPos]);
       $text =~ s/.*?\://;

       $paraPos{$para} = $text;

       $lastPos = $i - 1;
     }
   }

   for my $cmds (keys %paraPos) {
     if ($cmds eq "ssid") {
       $result->{data}->{guestAccess}->{ssid} = $paraPos{$cmds};
     } elsif ( $cmds eq "pwd") {
       $result->{data}->{guestAccess}->{psk} = $paraPos{$cmds};
     } elsif ( $cmds eq "wlan") {
       $result->{data}->{guestAccess}->{isEnabled} = $paraPos{$cmds} eq "on" ? 1 : 0;
     } elsif ( $cmds eq "mode") {
       $result->{data}->{guestAccess}->{mode} = $paraPos{$cmds} eq "public" ? 2 : 1;
     } elsif ( $cmds eq "tmo") {
       $result->{data}->{guestAccess}->{timeout} = "$paraPos{$cmds}";
       $result->{data}->{guestAccess}->{isTimeoutActive} = 1;
     } elsif ( $cmds eq "tmoActive") {
       $result->{data}->{guestAccess}->{isTimeoutActive} = $paraPos{$cmds} eq "on" ? 1 : 0;
     } elsif ( $cmds eq "tmoNoForcedOff") {
       $result->{data}->{guestAccess}->{timeoutNoForcedOff} = $paraPos{$cmds} eq "on" ? 1 : 0;
     }
   }

   @webCmdArray = ();

   push @webCmdArray, "xhr"                => "1";
   push @webCmdArray, "lang"               => "de";
   push @webCmdArray, "page"               => "wGuest";
   push @webCmdArray, "apply"              => "";
   push @webCmdArray, "isEnabled"          => $result->{data}->{guestAccess}->{isEnabled};
   push @webCmdArray, "mode"               => $result->{data}->{guestAccess}->{mode};
   push @webCmdArray, "ssid"               => $result->{data}->{guestAccess}->{ssid};
   push @webCmdArray, "encryption"         => $result->{data}->{guestAccess}->{encryption};
   push @webCmdArray, "psk"                => $result->{data}->{guestAccess}->{psk};
   push @webCmdArray, "notification"       => $result->{data}->{guestAccess}->{notification};
   push @webCmdArray, "isTimeoutActive"    => $result->{data}->{guestAccess}->{isTimeoutActive};
   push @webCmdArray, "timeout"            => $result->{data}->{guestAccess}->{timeout};
   push @webCmdArray, "timeoutNoForcedOff" => $result->{data}->{guestAccess}->{timeoutNoForcedOff};
   push @webCmdArray, "isolated"           => $result->{data}->{guestAccess}->{isolated};
   push @webCmdArray, "guestGroupAccess"   => $result->{data}->{guestAccess}->{guestGroupAccess};
   push @webCmdArray, "guestAccessType"    => $result->{data}->{guestAccess}->{guestAccessType} if $result->{data}->{guestAccess}->{guestAccessType};
   push @webCmdArray, "guestAccessActive"  => $result->{data}->{guestAccess}->{guestAccessActive} if $result->{data}->{guestAccess}->{guestAccessActive};
   push @webCmdArray, "lPEnabled"          => $result->{data}->{guestAccess}->{lPEnabled};
   push @webCmdArray, "lPReguire"          => $result->{data}->{guestAccess}->{lPReguire};
   push @webCmdArray, "lPTxt"              => $result->{data}->{guestAccess}->{lPTxt};
   push @webCmdArray, "lPRedirect"         => $result->{data}->{guestAccess}->{lPRedirect};
   push @webCmdArray, "lPRedirectUrl"      => $result->{data}->{guestAccess}->{lPRedirectUrl};
   push @webCmdArray, "isOWEEnabled"       => $result->{data}->{guestAccess}->{isOWEEnabled};
   push @webCmdArray, "isOWESupported"     => $result->{data}->{guestAccess}->{isOWESupported};

#   FRITZBOX_Log $hash, 3, "data.lua isEnabled: " . $result->{data}->{guestAccess}->{isEnabled};
#   FRITZBOX_Log $hash, 3, "data.lua mode: " . $result->{data}->{guestAccess}->{mode};
#   FRITZBOX_Log $hash, 3, "data.lua ssid: " . $result->{data}->{guestAccess}->{ssid};
#   FRITZBOX_Log $hash, 3, "data.lua encryption: " . $result->{data}->{guestAccess}->{encryption};
#   FRITZBOX_Log $hash, 3, "data.lua psk: " . $result->{data}->{guestAccess}->{psk};
#   FRITZBOX_Log $hash, 3, "data.lua notification: " . $result->{data}->{guestAccess}->{notification};
#   FRITZBOX_Log $hash, 3, "data.lua isTimeoutActive: " . $result->{data}->{guestAccess}->{isTimeoutActive};
#   FRITZBOX_Log $hash, 3, "data.lua timeout: " . $result->{data}->{guestAccess}->{timeout};
#   FRITZBOX_Log $hash, 3, "data.lua timeoutNoForcedOff: " . $result->{data}->{guestAccess}->{timeoutNoForcedOff};
#   FRITZBOX_Log $hash, 3, "data.lua isolated: " . $result->{data}->{guestAccess}->{isolated};
#   FRITZBOX_Log $hash, 3, "data.lua guestGroupAccess: " . $result->{data}->{guestAccess}->{guestGroupAccess};
#   FRITZBOX_Log $hash, 3, "data.lua guestAccessType: " . $result->{data}->{guestAccess}->{guestAccessType} if $result->{data}->{guestAccess}->{guestAccessType};
#   FRITZBOX_Log $hash, 3, "data.lua guestAccessActive: " . $result->{data}->{guestAccess}->{guestAccessActive} if $result->{data}->{guestAccess}->{guestAccessActive};
#   FRITZBOX_Log $hash, 3, "data.lua lPEnabled: " . $result->{data}->{guestAccess}->{lPEnabled};
#   FRITZBOX_Log $hash, 3, "data.lua lPReguire: " . $result->{data}->{guestAccess}->{lPReguire};
#   FRITZBOX_Log $hash, 3, "data.lua lPTxt: " . $result->{data}->{guestAccess}->{lPTxt};
#   FRITZBOX_Log $hash, 3, "data.lua lPRedirect: " . $result->{data}->{guestAccess}->{lPRedirect};
#   FRITZBOX_Log $hash, 3, "data.lua lPRedirectUrl: " . $result->{data}->{guestAccess}->{lPRedirectUrl};
#   FRITZBOX_Log $hash, 3, "data.lua isOWEEnabled: " . $result->{data}->{guestAccess}->{isOWEEnabled};
#   FRITZBOX_Log $hash, 3, "data.lua isOWESupported: " . $result->{data}->{guestAccess}->{isOWESupported};

# xhr 1 lang de page wGuest apply nop isEnabled 0 mode 1 ssid Unser oeffentliches WLAN encryption 6 psk Unser01GastZugang notification 1 isTimeoutActive 0 timeout 30 timeoutNoForcedOff 0 isolated 1 guestGroupAccess 0 lPEnabled 0 lPReguire 0 lPTxt nop  lPRedirect 0 lPRedirectUrl  nop isOWEEnabled 0 isOWESupported 1

   FRITZBOX_Log $hash, 4, "data.lua change: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);
         
   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "setting wakeUpCall: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanGuestParams", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   if (defined $result->{data}->{apply}) {
     if ($result->{data}->{apply} eq "ok") {
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanGuestParams", "done";
     } else {
       my $applyError = $result->{data}->{apply};
       $applyError .= " - " . $result->{data}->{$result->{data}->{apply}}->{result} if $result->{data}->{$result->{data}->{apply}}->{result};
       $applyError .= " - " . $result->{data}->{$result->{data}->{apply}}->{tomark}[0] if $result->{data}->{$result->{data}->{apply}}->{tomark}[0];
       $applyError .= " - " . $result->{data}->{$result->{data}->{apply}}->{alert} if $result->{data}->{$result->{data}->{apply}}->{alert};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanGuestParams", $applyError;
     }
   } else {
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_wlanGuestParams", "no apply result";
   }

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_Wlan_Guest_Name

#######################################################################
sub FRITZBOX_Set_macFilter_OnOff($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @tr064CmdArray;
   my @roReadings;
   my $startTime = time();
   my $queryStr;

   # xhr 1
   # MACFilter 0
   # currMACFilter 1
   # apply nop
   # lang de
   # page wKey

   # xhr 1 MACFilter 0 currMACFilter 1 apply nop lang de page wKey
   # xhr 1 MACFilter 1 currMACFilter 0 apply nop lang de page wKey

   my $returnStr;

   my $switch = $val[0];
      $switch =~ s/on/1/;
      $switch =~ s/off/0/;

   my $currMACFilter = ReadingsVal($name, "box_macFilter_active", "ERROR");

   FRITZBOX_Log $hash, 3, "set $name $cmd (Fritz!OS: $hash->{fhem}{fwVersionStr})";

   $queryStr = "&box_macFilter_active=wlan:settings/is_macfilter_active";

   $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "macFilter -> " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   if ( ! defined ($result->{box_macFilter_active}) ) {
      FRITZBOX_Log $hash, 2, "MAC Filter not available";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: MAC Filter not available";
   } elsif ( $switch == $result->{box_macFilter_active} ) {
      FRITZBOX_Log $hash, 4, "no macFilter change necessary";
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->INFO: change necessary";
   } else {

     if ($hash->{fhem}{fwVersion} >= 800) {
     
       push @webCmdArray, "xhr"   => "1";
       push @webCmdArray, "xhrId" => "all";
       push @webCmdArray, "lang"  => "de";
       push @webCmdArray, "page"  => "wKey";

       FRITZBOX_Log $hash, 4, "set $name $cmd " . join(" ", @webCmdArray);

       $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "macFilter -> " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: " . $result->{Error};
         return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};

       @webCmdArray = ();

       push @webCmdArray, "xhr"                  => "1";
       push @webCmdArray, "wpaEncrypted"         => "wpaEncrypted";
       push @webCmdArray, "wpaType"              => $result->{data}->{wlan}->{wpaType};
       push @webCmdArray, "psk"                  => $result->{data}->{wlan}->{psk};
       push @webCmdArray, "stickAndSurf"         => $result->{data}->{wlan}->{stickAndSurf};
       push @webCmdArray, "pmfMode"              => $result->{data}->{wlan}->{pmfMode};
       push @webCmdArray, "encInterop"           => "0";
       push @webCmdArray, "isolation"            => $result->{data}->{wlan}->{isolation};
       push @webCmdArray, "wlanAccountVisible"   => $result->{data}->{wlan}->{wlanAccountVisible};
       push @webCmdArray, "MACFilter"            => $switch; 
       push @webCmdArray, "currMACFilter"        => "";
       push @webCmdArray, "activeMACFilter"      => $switch;
       push @webCmdArray, "isEncInterop"         => $result->{data}->{wlan}->{isEncInterop};
       push @webCmdArray, "hasWlanAccountOption" => $result->{data}->{wlan}->{hasWlanAccountOption} == 1 ? "true" : "false";
       push @webCmdArray, "apply"                => "";
       push @webCmdArray, "lang"                 => "de";
       push @webCmdArray, "page"                 => "wKey";

       FRITZBOX_Log $hash, 4, "set $name $cmd " . join(" ", @webCmdArray);

       $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "macFilter -> " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: " . $result->{Error};
         return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};

     } else {

       push @webCmdArray, "xhr"           => "1";
       push @webCmdArray, "MACFilter"     => $switch;
       push @webCmdArray, "currMACFilter" => $switch == 1? 0 : 1;
       push @webCmdArray, "apply"         => "";
       push @webCmdArray, "lang"          => "de";
       push @webCmdArray, "page"          => "wKey";

       FRITZBOX_Log $hash, 4, "set $name $cmd " . join(" ", @webCmdArray);

       $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "macFilter -> " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: " . $result->{Error};
         return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};
     }

     $queryStr = "&box_macFilter_active=wlan:settings/is_macfilter_active";

     $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
       FRITZBOX_Log $hash, 2, "macFilter -> " . $result->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: " . $result->{Error};
       return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
     }

     $sidNew += $result->{sidNew} if defined $result->{sidNew};

     if( !defined ($result->{box_macFilter_active}) ) {
       FRITZBOX_Log $hash, 2, "MAC Filter not available";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->ERROR: MAC Filter not available";
     } elsif ( $switch != $result->{box_macFilter_active} ) {
       FRITZBOX_Log $hash, 4, "no macFilter change necessary";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->INFO: change necessary";
     } else {

       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $val[0];

       FRITZBOX_Log $hash, 4, "macFilter set to " . $val[0];
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_macFilter", "macFilter->set to " . $val[0];
     }
   }

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_macFilter_OnOff

#######################################################################
sub FRITZBOX_Set_rescan_Neighborhood($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
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

   FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "rescan WLAN neighborhood: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_rescanWLANneighbors", "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_rescanWLANneighbors", "done";

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_rescan_Neighborhood

#######################################################################
sub FRITZBOX_Set_change_Profile($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
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

   FRITZBOX_Log $hash, 4, "get $name $cmd " . join(" ", @webCmdArrayP);

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArrayP) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "changing Kid Profile: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[1] . "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

   $sidNew += $result->{sidNew} if defined $result->{sidNew};

   my $views = $result->{data}->{kidProfiles};
   my $ProfileOK = "false";

   eval {
     foreach my $key (keys %$views) {
       FRITZBOX_Log $hash, 4, "Kid Profiles: ".$key;
       if ($result->{data}->{kidProfiles}->{$key}{Id} eq $val[1]) {
         $ProfileOK = "true";
         last;
       }
     }
   };

   if ($ProfileOK eq "false") {
     FRITZBOX_Log $hash, 2, "" . $val[1] . " not available/defined.";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[1] . "->ERROR: not available/defined";
   } else {

     FRITZBOX_Log $hash, 4, "Profile $val[1] available.";

     my $lanDevice_Info = FRITZBOX_Get_Lan_Device_Info( $hash, $val[0], "chgProf");

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     if ( defined $lanDevice_Info->{Error} || defined $lanDevice_Info->{AuthorizationRequired}) {
       FRITZBOX_Log $hash, 2, "changing Kid Profile: " . $lanDevice_Info->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[1] . "->ERROR: " . $lanDevice_Info->{Error};
       return FRITZBOX_Readout_Response($hash, $lanDevice_Info, \@roReadings, 2);
     }

     $sidNew += $lanDevice_Info->{sidNew} if defined $lanDevice_Info->{sidNew};

     FRITZBOX_Log $hash, 5, "\n" . Dumper($lanDevice_Info);

     if($lanDevice_Info->{data}->{vars}->{dev}->{UID} eq $val[0]) {

       FRITZBOX_Log $hash, 4, "set $name $cmd (Fritz!OS: $hash->{fhem}{fwVersionStr})";

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

       if ($hash->{fhem}{fwVersion} < 721) {
         push @webCmdArray, "page"      => "edit_device";
       } elsif ($hash->{fhem}{fwVersion} >= 700 && $hash->{fhem}{fwVersion} < 750) {
         push @webCmdArray, "page"      => "edit_device2";
       } else {
         push @webCmdArray, "page"      => "edit_device";
       }

       if ($hash->{fhem}{fwVersion} < 750) {
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

       FRITZBOX_Log $hash, 4, "get $name $cmd " . join(" ", @webCmdArray);

       $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "changing Kid Profile: " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[1] . "->ERROR: " . $result->{Error};
         return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};

       my $tmp = FRITZBOX_Helper_analyse_Lua_Result($hash, $result, 1);

       if( substr($tmp, 0, 6) eq "ERROR:") {
         FRITZBOX_Log $hash, 2, "result $name $cmd " . $tmp;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[0] . "->ERROR: changing profile";
       } else {
         FRITZBOX_Log $hash, 4, "result $name $cmd " . $tmp;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[0] . "->INFO: profile ". $val[1];
       }

     } else {
       FRITZBOX_Log $hash, 2, "" . $val[0] . " not available/defined.";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_chgProfile", $val[0] . "->ERROR: not available/defined";
     }
   }

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time() - $startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_change_Profile

#######################################################################
sub FRITZBOX_Set_enable_VPNshare_OnOff($)
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

   $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "enable_VPNshare: " . $result->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_enableVPNshare", $val[0] . "->ERROR: " . $result->{Error};
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
   }

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
     FRITZBOX_Log $hash, 2, "vo valid " . $val[0] . " found";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_enableVPNshare", $val[0] . "->ERROR: not found";
   } else {
     FRITZBOX_Log $hash, 4, "set $name $cmd " . join(" ", @val);

     my $state = $val[1] eq "on"?"1":"0";

     #xhr 1 connection0 on active_connection0 1 apply nop lang de page shareVpn

     push @webCmdArray, "xhr"                         => "1";
     push @webCmdArray, "lang"                        => "de";
     push @webCmdArray, "page"                        => "shareVpn";
     push @webCmdArray, "apply"                       => "";
     push @webCmdArray, "connection".$vpnShare        => $val[1];
     push @webCmdArray, "active_connection".$vpnShare => $state;

     FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

     $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
       FRITZBOX_Log $hash, 2, "enable_VPNshare: " . $result->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_enableVPNshare", $val[0] . "->ERROR: " . $result->{Error};
       return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
     }

     $queryStr = "&vpn_info=vpn:settings/connection$vpnShare/activated";
     my $vpnState = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

     FRITZBOX_Log $hash, 5, "$vpnState->{vpn_info} \n" . Dumper($vpnState);

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
       FRITZBOX_Log $hash, 2, "enable_VPNshare: " . $result->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_enableVPNshare", $val[0] . "->ERROR: " . $result->{Error};
       return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
     }

     if ($vpnState->{vpn_info} != $state) {
       FRITZBOX_Log $hash, 2, "VPNshare " . $val[0] . " not set to " . $val[1] . " <> " . $vpnState->{vpn_info};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_enableVPNshare", $val[0] . "->ERROR: " . $vpnState->{vpn_info};
     } else {
       FRITZBOX_Log $hash, 4, "VPNshare " . $val[0] . " set to " . $val[1];
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_enableVPNshare", $val[0] . "->" . $val[1];
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, $val[0] . "_activated", $vpnState->{vpn_info};
     }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);

} # end FRITZBOX_Set_enable_VPNshare_OnOff

#######################################################################
# {FRITZBOX_write_javaScript($defs{FritzBox},"user/user", '{"filter_profile_UID":"filtprof1","landeviceUID":"landevice1805","disallowed":"1","type":"1"}', "post")}
#
# {FRITZBOX_write_javaScript($defs{FritzBox},"trafficprio/user", '{"ip":"192.168.0.37", "mac":"88:71:E5:0E:38:98","type":"1"}', "post")}
#
# {FRITZBOX_write_javaScript($defs{FritzBox},"landevice/landevice/landevice1805", '{"device_class_user":"Generic","friendly_name":"amazon-echo","rrd":"0"}', "put")}
# {FRITZBOX_write_javaScript($defs{FritzBox},"user/user/user8564", '{"filter_profile_UID":"filtprof1","disallowed:"0"}', "put")}
#######################################################################

sub FRITZBOX_Set_lock_Landevice_OnOffRt_8($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $jsonMsgId;
   my $startTime = time();

   my $returnStr;

   my $dev_name = $hash->{fhem}->{landevice}->{$val[0]}; # friendly name

   FRITZBOX_Log $hash, 3, "set $name $cmd $val[0] $val[1] $dev_name (Fritz!OS: $hash->{fhem}{fwVersionStr})";

   my $nbViews = 0;
   my $views;
   my $user;
   my $user_ctrl;
   my $dc_user;
   my $fp_uid;
   my $mac;
   my $ip;
   my $friendlyName;
   my $i;

#  { Dumper (FRITZBOX_call_javaScript($defs{FritzBox}, "landevice"))}

   $result = FRITZBOX_call_javaScript($hash, "landevice");

   if (defined $result->{data}->{landevice}) {
     $views = $result->{data}->{landevice};
     $nbViews = scalar @$views;
   }

   for($i = 0; $i <= $nbViews - 1; $i++) {
     if ($result->{data}->{landevice}->[$i]->{UID} eq $val[0]) {
       $user         = $result->{data}->{landevice}->[$i]->{user_UIDs};
       $dc_user      = $result->{data}->{landevice}->[$i]->{device_class_user};
       $mac          = $result->{data}->{landevice}->[$i]->{mac};
       $ip           = $result->{data}->{landevice}->[$i]->{ip};
       $friendlyName = $result->{data}->{landevice}->[$i]->{name};
       FRITZBOX_Log $hash, 2, "locklandevice: $i " . $dev_name . " $user $mac $friendlyName";
       last;
     }
   }

   $result = FRITZBOX_call_javaScript($hash, "user");

   if (defined $result->{data}->{user}) {
     $views = $result->{data}->{user};
     $nbViews = scalar @$views;
   }

   for($i = 0; $i <= $nbViews - 1; $i++) {
     if ($result->{data}->{user}->[$i]->{landeviceUID} eq $val[0]) {
       $user_ctrl = $result->{data}->{user}->[$i]->{UID};
       $fp_uid    = $result->{data}->{user}->[$i]->{filter_profile_UID};
       FRITZBOX_Log $hash, 2, "locklandevice: $i " . $fp_uid . " $user $mac $friendlyName";
       last;
     }
   }

   if ($i >= $nbViews) {
     $fp_uid    = "filtprof1";
   }

   if ($val[1] eq "off") {  

     if ($user) {

       FRITZBOX_Log $hash, 4, "locklandevice: last change user: " . $user . " defined for changing";

       $result = FRITZBOX_write_javaScript($hash, "landevice/landevice/" . $val[0], '{"device_class_user":"' . $dc_user . '","friendly_name":"' . $friendlyName . '","rrd":"0"}', "put");
       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "locklandevice: $dev_name " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: $dev_name " . $result->{Error};
         FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};

       $result = FRITZBOX_write_javaScript($hash, "user/user/" . $user, '{"filter_profile_UID":"' . $fp_uid . '","disallowed":"0"}', "put");
       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "locklandevice: $friendlyName " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: $friendlyName " . $result->{Error};
         FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};

       FRITZBOX_Log $hash, 4, "locklandevice: " . $friendlyName . " disallowed canceld";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $friendlyName . " disallowed canceld";

     } else {

       FRITZBOX_Log $hash, 4, "locklandevice: " . $dev_name . " no change possible for " . $friendlyName;
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: no change possible for " . $friendlyName;

     }

   } elsif ($val[1] eq "rtoff") {

#    { Dumper (FRITZBOX_call_javaScript($defs{FritzBox}, "trafficprio"))}

     FRITZBOX_Log $hash, 4, "locklandevice: no last change user defined for changing. Trying for traffic prio.";

     my $trafficPrio = FRITZBOX_call_javaScript($hash, "trafficprio");
     my $nbViewsTr = 0;
     my $viewsTr;

     if (defined $trafficPrio->{data}->{user}) {
       $viewsTr = $trafficPrio->{data}->{user};
       $nbViewsTr = scalar @$viewsTr;
     }

     my $j;

     for($j = 0; $j <= $nbViewsTr - 1; $j++) {
       if ($trafficPrio->{data}->{user}->[$j]->{mac} eq $mac) {
         $user = $trafficPrio->{data}->{user}->[$j]->{UID};

         if ($user) {

           $sidNew += $result->{sidNew} if defined $result->{sidNew};

           FRITZBOX_write_javaScript($hash, "trafficprio/user/" . $user, "", "delete");
           # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
           if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
             FRITZBOX_Log $hash, 2, "locklandevice: $friendlyName " . $result->{Error};
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: $friendlyName " . $result->{Error};
             FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
           }

           $sidNew += $result->{sidNew} if defined $result->{sidNew};

           FRITZBOX_Log $hash, 4, "locklandevice: " . $friendlyName . " Priority deactivated";
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "Priority deactivated";

         } else {

           FRITZBOX_Log $hash, 4, "locklandevice: " . $dev_name . " no Prio Change possible for " . $friendlyName;
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: no Prio Change possible for " . $friendlyName;

         }
         last;
       }
     }

     if ($j >= $nbViewsTr) {
       FRITZBOX_Log $hash, 2, "locklandevice: " . $dev_name . " no Prio Change possible for " . $friendlyName;
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: no Prio Change possible for " . $friendlyName;
     }
 
   } elsif ( $val[1] eq "on") {

     if ($user_ctrl) {
       FRITZBOX_Log $hash, 3, "locklandevice: $friendlyName : $fp_uid : $val[0] : $user_ctrl : $dc_user";

       $result = FRITZBOX_write_javaScript($hash, "landevice/landevice/" . $val[0], '{"device_class_user":"' . $dc_user . '","friendly_name":"' . $friendlyName . '","rrd":"0"}', "put");
       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "locklandevice: $dev_name " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: $dev_name " . $result->{Error};
         FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       FRITZBOX_write_javaScript($defs{FritzBox},"user/user/" . $user_ctrl, '{"disallowed":"1"}', "put");
     } else {
       FRITZBOX_write_javaScript($defs{FritzBox},"user/user", '{"filter_profile_UID":"' . $fp_uid . '","landeviceUID":"' . $val[0] . '","disallowed":"1","type":"1"}', "post");
     }
     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
       FRITZBOX_Log $hash, 2, "locklandevice: $friendlyName " . $result->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: $friendlyName " . $result->{Error};
       FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
     }

     $sidNew += $result->{sidNew} if defined $result->{sidNew};

     FRITZBOX_Log $hash, 4, "locklandevice: " . $friendlyName . " disallowed activated";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $friendlyName . " disallowed activated";

   } elsif ( $val[1] eq "rt") {

     #FRITZBOX_write_javaScript($defs{FritzBox},"user/user", '{"filter_profile_UID":"' . $fp_uid .'","landeviceUID":"' . $val[0] . '","disallowed":"0","type":"1"}', "post");

     FRITZBOX_write_javaScript($defs{FritzBox},"trafficprio/user", '{"ip":"' . $ip . '", "mac":"' . $mac . '","type":"1"}', "post");
     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
       FRITZBOX_Log $hash, 2, "locklandevice: $friendlyName " . $result->{Error};
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: $friendlyName " . $result->{Error};
       FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
     }

     $sidNew += $result->{sidNew} if defined $result->{sidNew};

     FRITZBOX_Log $hash, 4, "locklandevice: " . $friendlyName . " priority activated";
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $friendlyName . " priority activated";

   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_lock_Landevice_OnOffRt_8

#######################################################################
sub FRITZBOX_Set_lock_Landevice_OnOffRt($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $jsonMsgId;
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
   push @webCmdArray, "dev"       => $val[0];
   push @webCmdArray, "lang"      => "de";

   my $dev_name = $hash->{fhem}->{landevice}->{$val[0]};

   FRITZBOX_Log $hash, 4, "set $name $cmd (Fritz!OS: $hash->{fhem}{fwVersionStr})";

   if ($hash->{fhem}{fwVersion} < 721) {
     push @webCmdArray, "page"      => "edit_device2";
     push @webCmdArray, "block_dev" => "";
   } elsif ($hash->{fhem}{fwVersion} >= 700 && $hash->{fhem}{fwVersion} < 750) {
     push @webCmdArray, "page"      => "edit_device";
     push @webCmdArray, "block_dev" => "";
   } else {
     if($val[1] eq "on") {
       push @webCmdArray, "internetdetail" => "blocked";
     } elsif($val[1] eq "rt") {
       push @webCmdArray, "internetdetail" => "realtime";
     } else {
       push @webCmdArray, "internetdetail" => "unlimited";
     }
     push @webCmdArray, "page"      => "edit_device";
     push @webCmdArray, "apply"     => "true";
     push @webCmdArray, "dev_name"  => "$dev_name";
   }

   # Abfrage, ob Anforderung ungleich Istzustand
   my $lock_res = FRITZBOX_Get_Lan_Device_Info( $hash, $val[0], "lockLandevice");

   # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
   if ( defined $lock_res->{Error} || defined $lock_res->{AuthorizationRequired}) {
     FRITZBOX_Log $hash, 2, "locklandevice: " . $lock_res->{Error};
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: " . $lock_res->{Error};
     return FRITZBOX_Readout_Response($hash, $lock_res, \@roReadings, 2);
   }

   $sidNew += $lock_res->{sidNew} if defined $lock_res->{sidNew};

   FRITZBOX_Log $hash, 5, "\n" . Dumper($lock_res);

   unless ($lock_res->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid}) {

     FRITZBOX_Log $hash, 2, "setting locklandevice: " . substr($lock_res, 7);
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[0] . "->ERROR:" . substr($lock_res, 7);

   } else {

     $jsonMsgId = $lock_res->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid};

     # wenn Anforderung ungleich Istzustand
     unless (($jsonMsgId =~ /blocked/ && $val[1] eq "on") || ($jsonMsgId =~ /unlimited|limited/ && $val[1] eq "off") || ($jsonMsgId =~ /realtime/ && $val[1] eq "rt")) {

       FRITZBOX_Log $hash, 4, "get $name $cmd " . join(" ", @webCmdArray);

       # Anforderung umsetzen
       my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray);

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         FRITZBOX_Log $hash, 2, "locklandevice: " . $result->{Error};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: " . $result->{Error};
         FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2);
       }

       $sidNew += $result->{sidNew} if defined $result->{sidNew};

       my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

       if ( $analyse =~ /ERROR/) {
         FRITZBOX_Log $hash, 2, "lockLandevice status: " . $analyse;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[0] . "->ERROR: " . $analyse;

       } else {

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid} if $result->{sid};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;

         # Prüfen, ob Anforderung umgesetzt worden ist
         $lock_res = FRITZBOX_Get_Lan_Device_Info( $hash, $val[0], "lockLandevice");

         # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
         if ( defined $lock_res->{Error} || defined $lock_res->{AuthorizationRequired}) {
           FRITZBOX_Log $hash, 2, "lockLandevice: " . $lock_res->{Error};
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[1] . "->ERROR: " . $lock_res->{Error};
           return FRITZBOX_Readout_Response($hash, $lock_res, \@roReadings, 2);
         }

         $sidNew += $lock_res->{sidNew} if defined $lock_res->{sidNew};

         FRITZBOX_Log $hash, 5, "\n" . Dumper($lock_res);

         unless ($lock_res->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid}) {

           FRITZBOX_Log $hash, 2, "setting locklandevice: " . substr($lock_res, 7);
           FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[0] . "->ERROR:" . substr($lock_res, 7);

         } else {

           $jsonMsgId = $lock_res->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid};

           unless (($jsonMsgId =~ /blocked/ && $val[1] eq "on") || ($jsonMsgId =~ /unlimited|limited/ && $val[1] eq "off") || ($jsonMsgId =~ /realtime/ && $val[1] eq "rt")) {
             FRITZBOX_Log $hash, 2, "setting locklandevice: " . $val[0];
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[0] . "->ERROR: setting locklandevice " . $val[1];
           } else {
             FRITZBOX_Log $hash, 4, "" . $lock_res . " -> $name $cmd $val[1]";
             FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[0] . "->" . $val[1];
           }
         }
       }
     } else {
       FRITZBOX_Log $hash, 4, "" . $jsonMsgId . " -> $name $cmd $val[1]";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_lockLandevice", $val[0] . " locked is " . $val[1];
     }
   }

   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, 2, $sidNew);

} # end FRITZBOX_Set_lock_Landevice_OnOffRt

#######################################################################
sub FRITZBOX_Set_call_Phone($)
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   FRITZBOX_Log $hash, 4, "set $name " . join(" ", @val);

   my $result;
   my @tr064CallArray;
   my $duration = 60;

   my $extNo = $val[0];
   $extNo =~ s/#$//;

 # Check if 2nd parameter is the duration

   shift @val;
   if (int @val) {
      if ($val[0] =~ /^\d+$/ && int $val[0] > 0) {
         $duration = $val[0];
         FRITZBOX_Log $hash, 4, "Extracted call duration of $duration s.";
         shift @val;
      }
   }

#Preparing command array to ring // X_VoIP:1 x_voip X_AVM-DE_DialNumber NewX_AVM-DE_PhoneNumber 01622846962#
   FRITZBOX_Log $hash, 3, "Call $extNo for $duration seconds - " . $hash->{SECPORT};
   if ($hash->{SECPORT}) {
      push @tr064CallArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", $extNo."#"];
      $result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CallArray);
      FRITZBOX_Log $hash, 4, "result of calling number $extNo -> " .  $result;
   }
   else {
     my $msg = "ERROR (set call): TR064 SECPORT not available for calling ";
     FRITZBOX_Log $hash, 2, $msg;
     return $name . "|0|" . $msg;
   }

   FRITZBOX_Log $hash, 4, "waiting";
   sleep $duration; #+1; # 1s added because it takes sometime until it starts ringing
   FRITZBOX_Log $hash, 4, "stop ringing ";

#Preparing command array to stop ringing and reset dial port // X_VoIP:1 x_voip X_AVM-DE_DialHangup
   if ($hash->{SECPORT}) { #or hangup with TR-064
      push @tr064CallArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialHangup"];
      $result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CallArray);
      FRITZBOX_Log $hash, 4, "result of stop ringing number $extNo -> ".  $result;
   }

   return $name . "|1|Calling done";

} # end FRITZBOX_Set_call_Phone

#######################################################################
sub FRITZBOX_Set_GuestWlan_OnOff($)
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
                 if $hash->{fhem}{is_double_wlan} == 1;

        push @tr064CmdArray, ["WLANConfiguration:1", "wlanconfig1", "SetEnable", "NewEnable", "1"];
     }

     my $gWlanNo = 2;
     $gWlanNo = 3 if $hash->{fhem}{is_double_wlan} == 1;
     push @tr064CmdArray, ["WLANConfiguration:".$gWlanNo, "wlanconfig".$gWlanNo, "SetEnable", "NewEnable", $state];

     my @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

     if( $tr064Result[0]->{Error}) {
       my $msg = "set guestWlan: TR064 error switching guestWlan: $val[0]";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", $msg;
       FRITZBOX_Log $hash, 2, $msg . " - " . $tr064Result[0]->{Error};
     } else {

       FRITZBOX_Log $hash, 4, "switch GuestWLAN: " . $tr064Result[0];

       # Read WLAN-Status
       my $queryStr = "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
       $queryStr   .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
       $queryStr   .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # GÃ¤ste WLAN
       $queryStr   .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
       $queryStr   .= "&box_macFilter_active=wlan:settings/is_macfilter_active";

       $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

       # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
       if ( defined $result->{Error} || defined $result->{AuthorizationRequired}) {
         my $msg = "set guestWlan: Lua_Query error verifying guestWlan: $val[0]";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", $msg;
         FRITZBOX_Log $hash, 2, $msg . " - " . $result->{Error};

       } else {

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz",      $result->{box_wlan_24GHz}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz",        $result->{box_wlan_5GHz}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan",        $result->{box_guestWlan}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain",  $result->{box_guestWlanRemain};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $result->{box_macFilter_active}, "onoff";

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", "set guestWlan: $val[0]";

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid} if $result->{sid};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
       }
     }
   } else { #no API
     my $msg = "set guestWlan: TR064 SECPORT not available to switch WLAN.";
     FRITZBOX_Log $hash, 2, $msg;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", $msg;
   }

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: " . $returnStr;
   return $name."|2|".encode_base64($returnStr,"");

} # end FRITZBOX_Set_GuestWlan_OnOff

#######################################################################
sub FRITZBOX_Set_Wlan_OnOff($)
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
               if $hash->{fhem}{is_double_wlan} == 1 && $cmd ne "wlan2.4";

     push @tr064CmdArray, ["WLANConfiguration:1", "wlanconfig1", "SetEnable", "NewEnable", $state]
               if $cmd =~ /^(wlan|wlan2\.4)$/;

     FRITZBOX_Log $hash, 4, "TR-064 Command";
     my @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

     if( $tr064Result[0]->{Error}) {
       my $msg = "set $cmd: TR064 error switching $cmd: $val[0]";
       FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", $msg;
       FRITZBOX_Log $hash, 2, $msg . " - " . $tr064Result[0]->{Error};
     } else {

       FRITZBOX_Log $hash, 4, "switch WLAN: " . $tr064Result[0];

       # Read WLAN-Status
       my $queryStr = "&box_wlan_24GHz=wlan:settings/ap_enabled"; # WLAN
       $queryStr   .= "&box_wlan_5GHz=wlan:settings/ap_enabled_scnd"; # 2nd WLAN
       $queryStr   .= "&box_guestWlan=wlan:settings/guest_ap_enabled"; # GÃ¤ste WLAN
       $queryStr   .= "&box_guestWlanRemain=wlan:settings/guest_time_remain";
       $queryStr   .= "&box_macFilter_active=wlan:settings/is_macfilter_active";

       $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

       if ( defined $result->{Error} ) {
         my $msg = "set $cmd: Lua_Query error verifiying $cmd: $val[0]";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", $msg;
         FRITZBOX_Log $hash, 2, $msg . " - " . $result->{Error};

       } else {

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_2.4GHz", $result->{box_wlan_24GHz}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_wlan_5GHz", $result->{box_wlan_5GHz}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlan", $result->{box_guestWlan}, "onoff";
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_guestWlanRemain", $result->{box_guestWlanRemain};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "box_macFilter_active", $result->{box_macFilter_active}, "onoff";

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", "set $cmd: $val[0]";

         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->{sid} if $result->{sid};
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
       }
     }
   } else { #no API
     my $msg = "set $cmd: TR064 SECPORT not available to switch WLAN.";
     FRITZBOX_Log $hash, 2, $msg;
     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_SetGet_nonBlocking", $msg;
   }

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr, "");

} # end FRITZBOX_Set_Wlan_OnOff

#######################################################################
sub FRITZBOX_Set_ring_Phone($)
{
   my ($string) = @_;
   my ($name, @val) = split "\\|", $string;
   my $hash = $defs{$name};

   my $result;
   my @tr064Result;
   my $curCallerName;
   my @tr064CmdArray;
   my @roReadings;
   my $duration = -1;
   my @FritzFons;
   my $ringTone;
   my %field;
   my $lastField;
   my $ttsLink;
   my $startValue;
   my $startTime = time();

   my $intNo = $val[0];
   $intNo =~ s/#$//;

# Create a hash for the DECT devices whose ring tone (or radio station) can be changed
   foreach ( split( /,/, $intNo ) ) {
      if (defined $hash->{fhem}{$_}{brand} && "AVM" eq $hash->{fhem}{$_}{brand}) {
         my $userId = $hash->{fhem}{$_}{userId};
         FRITZBOX_Log $hash, 4, "Internal number $_ (dect$userId) seems to be a Fritz!Fon.";
         push @FritzFons, $hash->{fhem}{$_}{userId};
      }
   }

 # Check if 2nd parameter is the duration
   shift @val;
   if (int @val) {
      if ($val[0] =~ /^\d+$/ && int $val[0] >= 0) {
         $duration = $val[0];
         FRITZBOX_Log $hash, 4, "Extracted ring duration of $duration s.";
         shift @val;
      }
   }

# Check ClickToDial
   unless ($startValue->{useClickToDial}) {
      if ($hash->{SECPORT}) { # oder mit TR064
         # get port name
         push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_GetPhonePort", "NewIndex", "1"];
         @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );
         return $name."|0|Error (set ring): ".$tr064Result[0]->{Error}     if $tr064Result[0]->{Error};

         my $portName = $tr064Result[0]->{'X_AVM-DE_GetPhonePortResponse'}->{'NewX_AVM-DE_PhoneName'};
         # set click to dial
         if ($portName) {
            push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialSetConfig", "NewX_AVM-DE_PhoneName", $portName];
            @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );
            FRITZBOX_Log $hash, 4, "Switch ClickToDial on, set dial port '$portName'";
         }
      }
      else { #oder Pech gehabt
         my $msg = "ERROR (set ring): Cannot ring because ClickToDial (Waehlhilfe) is off.";
         FRITZBOX_Log $hash, 2, $msg;
         return $name . "|0|" . $msg
      }
   }

   if (int (@FritzFons) == 0 && $ttsLink) {
      FRITZBOX_Log $hash, 3, "No Fritz!Fon identified, parameter 'say:' will be ignored.";
   }

   $intNo =~ s/,/#/g;

#Preparing 3rd command array to ring
   FRITZBOX_Log $hash, 4, "Ringing $intNo for $duration seconds";
   if ($hash->{SECPORT}) {
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialNumber", "NewX_AVM-DE_PhoneNumber", "**".$intNo."#"];
      @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );
      return $name."|0|Error (set ring): ".$tr064Result[0]->{Error} if $tr064Result[0]->{Error};
   }
   else {
      my $msg = "ERROR (set ring): TR064 SECPORT not available. You cannot ring.";
      FRITZBOX_Log $hash, 2, $msg;
      return $name . "|0|" . $msg
   }

   sleep  5          if $duration <= 0; # always wait before reseting everything
   sleep $duration   if $duration > 0 ; #+1; # 1s added because it takes some time until it starts ringing

#Preparing 4th command array to stop ringing (but not when duration is 0 or play: and say: is used without duration)
   unless ( $duration == 0 || $duration == -1 && $ttsLink ) {
      push @tr064CmdArray, ["X_VoIP:1", "x_voip", "X_AVM-DE_DialHangup"];
      $result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray ) if $hash->{SECPORT};
   }

#   if ( $result->[0] == 1 ) {
   if ( $result == "1" ) {
#      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sid", $result->[1];
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidTime", time();
      FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "fhem->sidErrCount", 0;
   }
   FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);

   my $returnStr = join('|', @roReadings );
   FRITZBOX_Log $hash, 5, "Handover to main process: " . $returnStr;
   return $name . "|2|" . encode_base64($returnStr,"");

   # return $name."|1|Ringing done";

} # end FRITZBOX_Set_ring_Phone


# get list of mobile informations

############################################
sub FRITZBOX_Get_MobileInfo($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $returnStr;

   my @webCmdArray = ();
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "mobile";
   push @webCmdArray, "xhrId"       => "all";

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   return $result if($hash->{helper}{gFilters});

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "Mobile informations\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "Mobile informations\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data});

   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="10">Mobile Informations depending on data.lua</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Information</td><td>Value</td>\n";
   $returnStr .= "</tr>\n";

   
   $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "SIM status",        $result->{data}->{simOk}, "onoff");
   $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Activation status", $result->{data}->{activation});

   if ($result->{data}->{fallback}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Fallback possible",   $result->{data}->{fallback}->{possible}, "onoff");
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Fallback enableable", $result->{data}->{fallback}->{enableable});
   }

   if ($result->{data}->{config}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Config DSL"  , ($result->{data}->{config}->{dsl} ? "on" : "off"));
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Config FIBER", ($result->{data}->{config}->{fiber} ? "on" : "off"));
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Config CABLE", ($result->{data}->{config}->{cable} ? "on" : "off"));
   }

   if ($result->{data}->{connection}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Connection operator"        , $result->{data}->{connection}->{operator});
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Connection state"           , $result->{data}->{connection}->{state});
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Connection quality"         , $result->{data}->{connection}->{quality});
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Connection accessTechnology", $result->{data}->{connection}->{accessTechnology});
   }

   if ($result->{data}->{progress}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Progress refreshNeeded", $result->{data}->{progress}->{refreshNeeded});
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Progress error"        , $result->{data}->{progress}->{error});
   }

   if ($result->{data}->{compatibilityMode}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "compatibilityMode enabled"   , ($result->{data}->{compatibilityMode}->{enabled} ? "on" : "off"));
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "compatibilityMode enableable", ($result->{data}->{compatibilityMode}->{enableable} ? "on" : "off"));
   }

   if ($result->{data}->{voipOverMobile}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "voipOverMobile", ($result->{data}->{voipOverMobile} ? "on" : "off"));
   }

   if ($result->{data}->{wds}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "wds", ($result->{data}->{wds} ? "on" : "off"));
   }

   if ($result->{data}->{ipclient}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "ipclient", ($result->{data}->{ipclient} ? "on" : "off"));
   }

   if ($result->{data}->{capabilities}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Capabilities voice", ($result->{data}->{capabilities}->{voice} ? "on" : "off"));
   }

   if ($result->{data}->{activation}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "activation", $result->{data}->{activation});
   }

   if ($result->{data}->{sipNumberCount}) {
     $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "sipNumberCount", $result->{data}->{sipNumberCount});
   }

   $returnStr .= "</table>\n";

   if ( $hash->{TR064} == 1 && $hash->{SECPORT} ) {

     $returnStr .= '<br><table';
     $returnStr .= ' border="8"'       if $tableFormat !~ "border";
     $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
     $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
     $returnStr .= '>';
     $returnStr .= "<tr>\n";
     $returnStr .= '<td colspan="10">Mobile Informations depending on TR064</td>';
     $returnStr .= "</tr>\n";
     $returnStr .= "<tr>\n";
     $returnStr .= "<td>Information</td><td>Value</td>\n";
     $returnStr .= "</tr>\n";

     my $strCurl;
     my @tr064CmdArray;
     my @tr064Result;

     @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetInfoEx"]);

     @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

     if ($tr064Result[0]->{UPnPError}) {
       $strCurl = Dumper (@tr064Result);
       FRITZBOX_Log $hash, 2, "Mobile GetInfoEX -> \n" . $strCurl;

     } else {

       FRITZBOX_Log $hash, 5, "Mobile GetInfoEx -> \n" . Dumper (@tr064Result);

       if ($tr064Result[0]->{GetInfoExResponse}) {

         if (defined $tr064Result[0]->{GetInfoExResponse}->{NewCellList}) {
           my $data = $tr064Result[0]->{GetInfoExResponse}->{NewCellList};
           $data =~ s/&lt;/</isg;
           $data =~ s/&gt;/>/isg;

           FRITZBOX_Log $hash, 5, "Data Mobile GetInfoEx (NewCellList): \n" . $data;

           while( $data =~ /<Cell>(.*?)<\/Cell>/isg ) {
             my $cellList = $1;
 
             FRITZBOX_Log $hash, 5, "Data Mobile GetInfoEx (Cell): \n" . $1;
                
             my $Index      = $1 if $cellList =~ m/<Index>(.*?)<\/Index>/is;
             my $Connected  = $1 if $cellList =~ m/<Connected>(.*?)<\/Connected>/is;
             my $CellType   = $1 if $cellList =~ m/<CellType>(.*?)<\/CellType>/is;
             my $PLMN       = $1 if $cellList =~ m/<PLMN>(.*?)<\/PLMN>/is;
             my $Provider   = $1 if $cellList =~ m/<Provider>(.*?)<\/Provider>/is;
             my $TAC        = $1 if $cellList =~ m/<TAC>(.*?)<\/TAC>/is;
             my $PhysicalId = $1 if $cellList =~ m/<PhysicalId>(.*?)<\/PhysicalId>/is;
             my $Distance   = $1 if $cellList =~ m/<Distance>(.*?)<\/Distance>/is;
             my $Rssi       = $1 if $cellList =~ m/<Rssi>(.*?)<\/Rssi>/is;
             my $Rsrq       = $1 if $cellList =~ m/<Rsrq>(.*?)<\/Rsrq>/is;
             my $RSRP       = $1 if $cellList =~ m/<RSRP>(.*?)<\/RSRP>/is;
             my $Cellid     = $1 if $cellList =~ m/<Cellid>(.*?)<\/Cellid>/is;
 
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Connected_$Index",  $Connected);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "CellType_$Index",   $CellType);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PLMN_$Index",       $PLMN);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Provider_$Index",   $Provider);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "TAC_$Index",        $TAC);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PhysicalId_$Index", $PhysicalId);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Distance_$Index",   $Distance);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Rssi_$Index",       $Rssi);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Rsrq_$Index",       $Rsrq);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "RSRP_$Index",       $RSRP);
             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Cellid_$Index",     $Cellid);

             $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "emptyRow");

           }

         }

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PPPUsername",             $tr064Result[0]->{GetInfoExResponse}->{NewPPPUsername});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PDN2_MTU",                $tr064Result[0]->{GetInfoExResponse}->{NewPDN2_MTU});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "APN",                     $tr064Result[0]->{GetInfoExResponse}->{NewAPN});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "SoftwareVersion",         $tr064Result[0]->{GetInfoExResponse}->{NewSoftwareVersion});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Roaming",                 $tr064Result[0]->{GetInfoExResponse}->{NewRoaming});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PDN1_MTU",                $tr064Result[0]->{GetInfoExResponse}->{NewPDN1_MTU});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "IMSI",                    $tr064Result[0]->{GetInfoExResponse}->{NewIMSI});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "SignalRSRP1",             $tr064Result[0]->{GetInfoExResponse}->{NewSignalRSRP1});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "CurrentAccessTechnology", $tr064Result[0]->{GetInfoExResponse}->{NewCurrentAccessTechnology});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PPPUsernameVoIP",         $tr064Result[0]->{GetInfoExResponse}->{NewPPPUsernameVoIP});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "EnableVoIPPDN",           $tr064Result[0]->{GetInfoExResponse}->{NewEnableVoIPPDN});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "APN_VoIP",                $tr064Result[0]->{GetInfoExResponse}->{NewAPN_VoIP});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Uptime",                  $tr064Result[0]->{GetInfoExResponse}->{NewUptime});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "SignalRSRP0",             $tr064Result[0]->{GetInfoExResponse}->{NewSignalRSRP0});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "SerialNumber",            $tr064Result[0]->{GetInfoExResponse}->{NewSerialNumber});

       }
        
     }

     @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetInfo"]);

     @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

     if ($tr064Result[0]->{UPnPError}) {
       $strCurl = Dumper (@tr064Result);
       FRITZBOX_Log $hash, 2, "Mobile GetInfo -> \n" . $strCurl;
     } else {

       FRITZBOX_Log $hash, 5, "Mobile GetInfo -> \n" . Dumper (@tr064Result);

       if ($tr064Result[0]->{GetInfoResponse}) {

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "emptyRow");

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PINFailureCount", $tr064Result[0]->{GetInfoResponse}->{NewPINFailureCount});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PUKFailureCount", $tr064Result[0]->{GetInfoResponse}->{NewPUKFailureCount});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Enabled",         $tr064Result[0]->{GetInfoResponse}->{NewEnabled});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Status",          $tr064Result[0]->{GetInfoResponse}->{NewStatus});
  
       }
          
     }

     @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetBandCapabilities"]);

     @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

     if ($tr064Result[0]->{UPnPError}) {
       $strCurl = Dumper (@tr064Result);
       FRITZBOX_Log $hash, 2, "Mobile GetInfo -> \n" . $strCurl;
     } else {

       FRITZBOX_Log $hash, 5, "Mobile GetInfo -> \n" . Dumper (@tr064Result);

       if ($tr064Result[0]->{GetInfoResponse}) {

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "emptyRow");

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "CapabilitiesLTE",   $tr064Result[0]->{GetInfoResponse}->{NewBandCapabilitiesLTE});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Capabilities5GSA",  $tr064Result[0]->{GetInfoResponse}->{NewBandCapabilities5GSA});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "Capabilities5GNSA", $tr064Result[0]->{GetInfoResponse}->{NewBandCapabilities5GNSA});
  
       }
          
     }

     @tr064CmdArray = (["X_AVM-DE_WANMobileConnection:1", "x_wanmobileconn", "GetAccessTechnology"]);

     @tr064Result = FRITZBOX_call_TR064_Cmd( $hash, 0, \@tr064CmdArray );

     if ($tr064Result[0]->{UPnPError}) {
       $strCurl = Dumper (@tr064Result);
       FRITZBOX_Log $hash, 2, "Mobile GetInfo -> \n" . $strCurl;
     } else {

       FRITZBOX_Log $hash, 5, "Mobile GetInfo -> \n" . Dumper (@tr064Result);

       if ($tr064Result[0]->{GetInfoResponse}) {

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "emptyRow");

         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "CurrentAccessTechnology",  $tr064Result[0]->{GetInfoResponse}->{NewCurrentAccessTechnology});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "PossibleAccessTechnology", $tr064Result[0]->{GetInfoResponse}->{NewPossibleAccessTechnology});
         $returnStr .= FRITZBOX_Helper_make_TableRow($hash, "AccessTechnology",         $tr064Result[0]->{GetInfoResponse}->{NewAccessTechnology});
  
       }
          
     }
   }

   $returnStr .= "</table>\n";

   return $returnStr;

} # end FRITZBOX_Get_MobileInfo

# make a table row
############################################
sub FRITZBOX_Helper_make_TableRow($@) {

   my ($hash, $column1, $column2, $format2) = @_;
   my $name = $hash->{NAME};

   my $trtd = "<tr>\n" . "<td>";
   my $tdtd = "</td><td> ";
   my $tdtr = "</td>" . "</tr>\n";

   return $trtd . " " . $tdtd . " " . $tdtr if $column1 eq "emptyRow";

   if (defined $format2) {
     if ($format2 eq "onoff") {
       $column2 = $column2 == 0 ? "off" : "on" if defined $column2;
     } elsif ($format2 ne "") {
       $column2 = $format2;
     }
   }

   return "" unless defined $column2;

   my $returnStr;

   $returnStr .= $trtd . $column1 . $tdtd . $column2 . $tdtr;

   return $returnStr;
  
} # end FRITZBOX_Helper_make_TableRow

# get list of global filters
############################################
sub FRITZBOX_Get_WLAN_globalFilters($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page trafapp xhrId all;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "trafapp";
   push @webCmdArray, "xhrId"       => "all";

   my $returnStr;

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   return $result if($hash->{helper}{gFilters});

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "VPN Shares: globale Filter\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "VPN Shares: globale Filter\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data}->{filterList});

   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="10">globale Filterlisten</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Filter</td><td>Status</td>\n";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "Firewall im Stealth Mode" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{filterList}->{isGlobalFilterStealth} ? "on" : "off") . "</td>";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "E-Mail-Filter über Port 25 aktiv" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{filterList}->{isGlobalFilterSmtp} ? "on" : "off") . "</td>";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "NetBIOS-Filter aktiv" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{filterList}->{isGlobalFilterNetbios} ? "on" : "off") . "</td>";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "Teredo-Filter aktiv" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{filterList}->{isGlobalFilterTeredo} ? "on" : "off") . "</td>";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "WPAD-Filter aktiv" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{filterList}->{isGlobalFilterWpad} ? "on" : "off") . "</td>";
   $returnStr .= "</tr>\n";

   $returnStr .= "</table>\n";

   return $returnStr;

} # end FRITZBOX_Get_WLAN_globalFilters

# get led sttings
############################################
sub FRITZBOX_Get_LED_Settings($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page led xhrId all;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "led";
   push @webCmdArray, "xhrId"       => "all";

   my $returnStr;

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   return $result if($hash->{helper}{ledSet});

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "VPN Shares: globale Filter\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "VPN Shares: globale Filter\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data}->{filterList});

   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");
   my $setpossible = "set $name ledSetting &lt;led:on|off&gt;";

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="10">LED Einstellungen</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>Einstellung</td><td>Status</td>\n";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "LED-Anzeige" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{ledSettings}->{ledDisplay} ? "off" : "on") . "</td>";
   $returnStr .= "</tr>\n";

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "LED-Helligkeit einstellbar" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{ledSettings}->{canDim} ? "yes" : "no") . "</td>";
   $returnStr .= "</tr>\n";

   if($result->{data}->{ledSettings}->{canDim}) {
     $returnStr   .= "<tr>\n";
     $returnStr   .= "<td>" . "LED-Helligkeit" . "</td>";
     $returnStr   .= "<td>" . ($result->{data}->{ledSettings}->{dimValue}) . "</td>";
     $returnStr   .= "</tr>\n";
     $setpossible .= " and/or &lt;bright:1..3&gt;";
   }

   $returnStr .= "<tr>\n";
   $returnStr .= "<td>" . "LED-Helligkeit an Umgebungslicht" . "</td>";
   $returnStr .= "<td>" . ($result->{data}->{ledSettings}->{hasEnv} ? "yes" : "no") . "</td>";
   $returnStr .= "</tr>\n";

   if($result->{data}->{ledSettings}->{hasEnv}) {
     $returnStr   .= "<tr>\n";
     $returnStr   .= "<td>" . "LED-Helligkeit Umgebungslicht" . "</td>";
     $returnStr   .= "<td>" . ($result->{data}->{ledSettings}->{envLight} ? "on" : "off") . "</td>";
     $returnStr   .= "</tr>\n";
     $setpossible .= " and/or &lt;env:on|off&gt;";
   }

   $returnStr .= "</table>\n";
   $returnStr .= "<br><br>" . $setpossible;

   return $returnStr;

} # end FRITZBOX_Get_LED_Settings

# get list of VPN Shares
############################################
sub FRITZBOX_Get_VPN_Shares_List($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page shareVpn xhrId all;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "shareVpn";
   push @webCmdArray, "xhrId"       => "all";

   my $returnStr;

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "VPN Shares: Benutzer-Verbindungen\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "VPN Shares: Benutzer-Verbindungen\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
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

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data}->{init}->{boxConnections});

   eval {
     foreach my $key (keys %$views) {
       FRITZBOX_Log $hash, 4, "userConnections: ".$key;
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

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data}->{init}->{boxConnections});

   eval {
     foreach my $key (keys %$views) {
       FRITZBOX_Log $hash, 4, "boxConnections: ".$key;
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

   # Wirguard VPN only available with Fritz!OS 7.50 and greater
   return $returnStr . "</table>\n" if $hash->{fhem}{fwVersion} < 750;

   @webCmdArray = ();
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "shareWireguard";
   push @webCmdArray, "xhrId"       => "all";

   $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "</table>\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "</table>\n";
     return $returnStr . "AuthorizationRequired";
   }

   if ($result->{data}->{init}->{boxConnections}) {
     $views = $result->{data}->{init}->{boxConnections};
     $jID = "init";

     FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data}->{init}->{boxConnections});

     eval {
       foreach my $key (keys %$views) {
         FRITZBOX_Log $hash, 4, "boxConnections: ".$key;
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

} # end FRITZBOX_Get_VPN_Shares_List

# get list of DOCSIS informations
############################################
sub FRITZBOX_Get_DOCSIS_Informations($) {

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

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "DOCSIS: Informationen\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "DOCSIS: Informationen\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data});

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

     my $modType = $result->{data}->{channelUs}->{docsis30}->[0]->{type}?"type":"modulation";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{multiplex} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis30}->[$i]->{frequency} . "</td>";
         $returnStr .= "<td>";
         $returnStr .= $1 if($result->{data}->{channelUs}->{docsis30}->[$i]->{$modType} =~ /(\d+)/);
         $returnStr .= "</td>";
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

     my $modType = $result->{data}->{channelUs}->{docsis31}->[0]->{type}?"type":"modulation";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{multiplex} . "</td>" if $result->{data}->{channelUs}->{docsis31}->[$i]->{multiplex};
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelUs}->{docsis31}->[$i]->{frequency} . "</td>";
         $returnStr .= "<td>";
         $returnStr .= $1 if($result->{data}->{channelUs}->{docsis31}->[$i]->{$modType} =~ /(\d+)/);
         $returnStr .= "</td>";
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

     my $modType = $result->{data}->{channelDs}->{docsis30}->[0]->{type}?"type":"modulation";

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
         $returnStr .= "<td>";
         $returnStr .= $1 if($result->{data}->{channelDs}->{docsis30}->[$i]->{$modType} =~ /(\d+)/);
         $returnStr .= "</td>";
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

     my $modType = $result->{data}->{channelDs}->{docsis31}->[0]->{type}?"type":"modulation";

     eval {
       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{channel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{channelID} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{powerLevel} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{channelDs}->{docsis31}->[$i]->{frequency} . "</td>";
         $returnStr .= "<td>";
         $returnStr .= $1 if($result->{data}->{channelDs}->{docsis31}->[$i]->{$modType} =~ /(\d+)/);
         $returnStr .= "</td>";
         $returnStr .= "</tr>\n";
       }
     };
   }

   $returnStr .= "</table>\n";

   return $returnStr;

} # end FRITZBOX_Get_DOCSIS_Informations

# get list of WLAN in environment
############################################
sub FRITZBOX_Get_WLAN_Environment($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page chan xhrId environment requestCount 0 useajax 1;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "chan";
   push @webCmdArray, "xhrId"       => "environment";

   my $returnStr;

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "WLAN: Netzwerke in der Umgebung\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "WLAN: Netzwerke in der Umgebung\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   FRITZBOX_Log $hash, 5, "\n" . Dumper ($result->{data}->{scanlist});

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

} # end sub FRITZBOX_Get_WLAN_Environment

# get list of SmartHome Devices
############################################
# Test: { Dumper FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17", "test")}
# Save: { FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17", "save")}
# Read: { FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17", "read")}
#
# Test: { FRITZBOX_Get_SmartHome_Devices_List($defs{"FB6660"}, "16", "test")}
#
# xhr 1 lang de page sh_dev xhrId all
# { FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17")}

sub FRITZBOX_Get_SmartHome_Devices_List($@) {

   my ($hash, $devID, $command, $preName) = @_;

   my $name = $hash->{NAME};
   $command ||= "read";
   $preName ||= "default";

   my $returnStr;
   my $views;
   my $nbViews = 0;
   
   FRITZBOX_Log $hash, 4, "FRITZBOX_SmartHome_Device_List (Fritz!OS: $hash->{fhem}{fwVersionStr}) ";

   my @webCmdArray;
   # xhr 1 lang de page sh_dev xhrId all
   # xhr 1 master 17 device 17 page home_auto_edit_view

   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "sh_dev";
   push @webCmdArray, "xhrId"       => "all";

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ($devID && $command =~ /read|save|test/) {

     if ( $analyse =~ /ERROR/) {
       FRITZBOX_Log $hash, 2, "getting smart home info -> " . $analyse;
       my %retHash = ("Error" => $returnStr, "Info" => $analyse);
       return \%retHash;
     }

     my $devData = $result->{'data'}{'devices'};  # hier entsteht die Referenz auf das Array

     my $dayOfWeekMap = { 'SUN' => 64, 'SAT' => 32, 'FRI' => 16, 'THU' => 8, 'WED' => 4, 'TUE' => 2, 'MON' => 1 };
     my $unitData;
     my $skills;
     my $allTimeSchedules;
     my $timeSchedule;
     my %ret;
     my %ret1;

     # find entry for requested devID
     for my $i (0 .. @{$devData} - 1) {

       if( $devData->[$i]{'id'} eq $devID ) {

         $ret{device_name_category} = $devData->[$i]{'category'}; # if $command =~ /test/;
         $ret{device_web_site}      = "GENERAL";
         $ret{device}               = $devID;

         my $isSocket               = $devData->[$i]{'category'} eq "SOCKET";

         unless ( $isSocket) {

           $ret{ule_device_name} = $devData->[$i]{'displayName'};

           if( $devData->[$i]{'pushService'}{'isEnabled'} ) {
             $ret{enabled}   = "on";
             $ret{mailto}    = $devData->[$i]{'pushService'}{'mailAddress'};
             $ret{mail_type} = $ret{mailto} eq "default" ? "custom" : "";
           }

         } else {

           @webCmdArray = ();
           # xhr 1 lang de page sh_dev xhrId all
           # xhr 1 master 17 device 17 page home_auto_edit_view

           push @webCmdArray, "xhr"         => "1";
           push @webCmdArray, "lang"        => "de";
           push @webCmdArray, "master"      => $devID;
           push @webCmdArray, "device"      => $devID;
           push @webCmdArray, "page"        => "home_auto_edit_view";

           my $result1 = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

           FRITZBOX_Log $hash, 5, "getting smart home info -> " . Dumper($result1);
 
           my $analyse1 = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

           if ( $analyse1 =~ /ERROR/) {
             FRITZBOX_Log $hash, 2, "getting smart home info -> " . $analyse1;
             my %retHash = ("Error" => $returnStr, "Info" => $analyse1);
             return \%retHash;
           }

           foreach (keys %{ $result1->{'data'}{'smartoptions'} }) {
             $ret1{$_} = $result1->{'data'}{'smartoptions'}{$_};
           }           

           $ret1{device_name_category}        = "SOCKET";
           $ret1{device_web_site}             = "GENERAL";

#           $ret1{ule_device_name}             = $result1->{'data'}{'smartoptions'}{'ule_device_name'};
#           $ret1{led_active}                  = $result1->{'data'}{'smartoptions'}{'led_active'};
#           $ret1{ule_device_acdc_rate}        = $result1->{'data'}{'smartoptions'}{'ule_device_acdc_rate'};
#           $ret1{ule_device_co2_emission}     = $result1->{'data'}{'smartoptions'}{'ule_device_co2_emission'};
#           $ret1{ShowEnergyStat}              = $result1->{'data'}{'smartoptions'}{'ShowEnergyStat'};
#           $ret1{switch_default_state}        = $result1->{'data'}{'smartoptions'}{'switch_default_state'};
#           $ret1{manuell_switch_active_local} = $result1->{'data'}{'smartoptions'}{'manuell_switch_active_local'};
#           $ret1{manuell_switch_active_uiapp} = $result1->{'data'}{'smartoptions'}{'manuell_switch_active_uiapp'};
#           $ret1{mail_type}                   = $result1->{'data'}{'smartoptions'}{'mail_type'};
#           $ret1{interval}                    = $result1->{'data'}{'smartoptions'}{'interval'};

#           $ret1{Offset}                      = $result1->{'data'}{'smartoptions'}{'Offset'} if exists $result1->{'data'}{'smartoptions'}{'Offset'};

#           if( exists $result1->{'data'}{'smartoptions'}{'enabled'} && $result1->{'data'}{'smartoptions'}{'enabled'} ) {
#             $ret1{enabled}             = "on";
#             $ret1{mailto}              = $result1->{'data'}{'smartoptions'}{'mailto'};
#             $ret1{ShowEnergyStat}      = $result1->{'data'}{'smartoptions'}{'ShowEnergyStat'};
#             $ret1{periodic}            = $result1->{'data'}{'smartoptions'}{'periodic'};
#             $ret1{TriggerSwitchChange} = $result1->{'data'}{'smartoptions'}{'TriggerSwitchChange'} if $result1->{'data'}{'smartoptions'}{'TriggerSwitchChange'};
#           }

         }
     
         # find needed unit
         $unitData = $devData->[$i]{'units'};

         for my $j (0 .. scalar @{$unitData} - 1) {
           my $unitData = $unitData->[$j];
 
           # Steckdosen
           if( $unitData->{'type'} eq 'THERMOSTAT' && $isSocket ) {

             my $interactionControls = $unitData->{'interactionControls'};
             for my $i ( 0 .. 1 ) {
               if( $interactionControls->[$i]{'isLocked'} ) { 
                 $ret1{manuell_switch_active_local} = $interactionControls->[$i]{'isLocked'} if( $interactionControls->[$i]{'devControlName'} eq 'BUTTON' );
                 $ret1{manuell_switch_active_uiapp} = $interactionControls->[$i]{'isLocked'} if( $interactionControls->[$i]{'devControlName'} eq 'EXTERNAL' );
               }
             }

             $skills = $unitData->{'skills'}[1];
             $ret1{'led_active'}           = $skills->{ledState} eq "ON" ? 1 : 0;
             $ret1{'switch_default_state'} = 0 if $skills->{powerLossOption} eq "OFF";
             $ret1{'switch_default_state'} = 1 if $skills->{powerLossOption} eq "ON";
             $ret1{'switch_default_state'} = 2 if $skills->{powerLossOption} eq "LAST";

           # Heizkörperthermostate
           } elsif( $unitData->{'type'} eq 'THERMOSTAT' && !$isSocket ) {

             $skills = $unitData->{'skills'}[0];

             # parse preset temperatures ...
             my $presets = $skills->{'presets'};

             # ... and lock status
             my $interactionControls = $unitData->{'interactionControls'};
             for my $i ( 0 .. 1 ) {
               $ret{Absenktemp}  = $presets->[$i]{'temperature'} if( $presets->[$i]{'name'} eq 'LOWER_TEMPERATURE' );
               $ret{Heiztemp}    = $presets->[$i]{'temperature'} if( $presets->[$i]{'name'} eq 'UPPER_TEMPERATURE' );
            
               if( $interactionControls->[$i]{'isLocked'} ) { 
                 $ret{locklocal} = "on" if( $interactionControls->[$i]{'devControlName'} eq 'BUTTON' );
                 $ret{lockuiapp} = "on" if( $interactionControls->[$i]{'devControlName'} eq 'EXTERNAL' );
               }
             }

             $ret{hkr_adaptheat}     = ( ( $skills->{'adaptivHeating'}{'isEnabled'} ) ? 1 : 0 );
             $ret{ExtTempsensorID}   = $skills->{'usedTempSensor'}{'id'};
             $ret{WindowOpenTrigger} = $skills->{'temperatureDropDetection'}{'sensitivity'};
             $ret{WindowOpenTimer}   = $skills->{'temperatureDropDetection'}{'doNotHeatOffsetInMinutes'};

             # find needed time schedule
             $allTimeSchedules = $skills->{'timeControl'}{'timeSchedules'};
             for my $ts (0 .. scalar @{$allTimeSchedules} - 1) {

               # parse weekly timetable
               if( $allTimeSchedules->[$ts]{'name'} eq 'TEMPERATURE' ) {
                 $timeSchedule = $allTimeSchedules->[$ts]{'actions'};
                 my $NumEntries = scalar @{$timeSchedule};
                 my @timerItems = ();
             
                 for my $i (0 .. $NumEntries - 1) {
                   my $startTime   = $timeSchedule->[$i]{'timeSetting'}{'startTime'};
                   my $dayOfWeek   = $timeSchedule->[$i]{'timeSetting'}{'dayOfWeek'};
                   my $temperature = $timeSchedule->[$i]{'description'}{'presetTemperature'}{'temperature'};
                   my %timerItem;
                   my $newItem = 1;
               
                   $startTime   =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1$2/;
                   $temperature = ( ( $temperature eq $ret{Heiztemp} ) ? 1 : 0 );
                   $dayOfWeek   = $dayOfWeekMap->{$dayOfWeek};
               
                   $timerItem{'startTime'}   = $startTime;
                   $timerItem{'dayOfWeek'}   = $dayOfWeek;
                   $timerItem{'temperature'} = $temperature;

                   foreach (@timerItems) {
                     if(( $_->{'startTime'} eq $startTime )&&( $_->{'temperature'} eq $temperature ) ) {
                       $_->{'dayOfWeek'} = $_->{'dayOfWeek'} + $dayOfWeek;
                       $newItem = 0;
                       last;
                     }
                   }

                   if( $newItem ) {
                     push( @timerItems, \%timerItem );
                   }

                 }

                 my $j = 0;

                 foreach (@timerItems) {
                   $ret{"timer_item_$j"} = $_->{'startTime'}.';'.$_->{'temperature'}.';'.$_->{'dayOfWeek'};
                   $j ++;
                 }

               } elsif( $allTimeSchedules->[$ts]{'name'} eq 'HOLIDAYS' ) {
                 $timeSchedule = $allTimeSchedules->[$ts]{'actions'};
                 my $NumEntries = scalar @{$timeSchedule};
 
                 $ret{"HolidayEnabledCount"} = 0;
                 for my $i (0 .. $NumEntries - 1) {
                   my $holiday     = "Holiday" . eval($i + 1);
                   my $startDate   = $timeSchedule->[$i]{'timeSetting'}{'startDate'};
                   my $startTime   = $timeSchedule->[$i]{'timeSetting'}{'startTime'};
                   my $endDate     = $timeSchedule->[$i]{'timeSetting'}{'endDate'};
                   my $endTime     = $timeSchedule->[$i]{'timeSetting'}{'endTime'};
               
                   $ret{$holiday . "ID"}        = $i + 1;
                   $ret{$holiday . "Enabled"}   = ( ( $timeSchedule->[$i]{'timeSetting'}{'isEnabled'} ) ? 1 : 0 );
                   $ret{$holiday ."StartDay"}   = $startDate;
                   $ret{$holiday ."StartDay"}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                   $ret{$holiday ."StartMonth"} = $startDate;
                   $ret{$holiday ."StartMonth"} =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                   $ret{$holiday ."StartHour"}  = $startTime;
                   $ret{$holiday ."StartHour"}  =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
               
                   $ret{$holiday ."EndDay"}     = $endDate;
                   $ret{$holiday ."EndDay"}     =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                   $ret{$holiday ."EndMonth"}   = $endDate;
                   $ret{$holiday ."EndMonth"}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                   $ret{$holiday ."EndHour"}    = $endTime;
                   $ret{$holiday ."EndHour"}    =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
               
                   $ret{"HolidayEnabledCount"} ++ if( 1 == $ret{$holiday . "Enabled"} );
               
                 }

               } elsif( $allTimeSchedules->[$ts]{'name'} eq 'SUMMER_TIME' ) {
                 $timeSchedule = $allTimeSchedules->[$ts]{'actions'};
                 my $NumEntries = scalar @{$timeSchedule};
 
                 for my $i (0 .. $NumEntries - 1) {
                   my $startDate   = $timeSchedule->[$i]{'timeSetting'}{'startDate'};
                   my $endDate     = $timeSchedule->[$i]{'timeSetting'}{'endDate'};
               
                   $ret{SummerStartDay}   = $startDate;
                   $ret{SummerStartDay}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                   $ret{SummerStartMonth} = $startDate;
                   $ret{SummerStartMonth} =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
               
                   $ret{SummerEndDay}     = $endDate;
                   $ret{SummerEndDay}     =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                   $ret{SummerEndMonth}   = $endDate;
                   $ret{SummerEndMonth}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
               
                   $ret{SummerEnabled}    = ( ( $timeSchedule->[$i]{'timeSetting'}{'isEnabled'} ) ? 1 : 0 );
                 }

               }
             }

           # Temperatursensor
           } elsif ( $unitData->{'type'} eq 'TEMPERATURE_SENSOR' && !$isSocket ) {

             $skills          = $unitData->{'skills'}[0];
             $ret{Offset}     = $skills->{'offset'};
             $ret{Roomtemp}   = $skills->{'currentInCelsius'};
             $ret{tempsensor} = $ret{Roomtemp} - $ret{Offset};

           # Luftfeuchtesensor
           } elsif ( $unitData->{'type'} eq 'HUMIDITY_SENSOR'  && !$isSocket ) {

             $skills          = $unitData->{'skills'}[0];
             $ret{Roomhum}    = $skills->{'currentInPercent'};

           # Mikrofon in Smart-Steckdose
           } elsif( $unitData->{'type'} eq 'MICROPHONE' ) {

             $ret{device_web_site} = "AUTOMATION";
             $skills = $unitData->{'skills'}[0];

             if ($skills->{'isEnabled'}) {
               $ret{"soundswitch"}  = $skills->{'isEnabled'} ? "on" : "off";

               # find needed time schedule
               $allTimeSchedules = $skills->{'timeControl'}{'timeSchedules'};

               Log3 $name, 4, "allTimeSchedules:\n" . Dumper($allTimeSchedules);

               for my $ts (0 .. scalar @{$allTimeSchedules} - 1) {
                 Log3 $name, 3, "kind[$ts]: " . $allTimeSchedules->[$ts]{'kind'};

                 if( $allTimeSchedules->[$ts]{'kind'} eq 'COUNTDOWN' ) {

                   $ret{"soundswitchstate"}            = $allTimeSchedules->[$ts]{'isEnabled'} ? "custom" : "permanent";
                   $ret{"soundswitch_actionresettime"} = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'durationInSeconds'} / 60;

                 } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'REPETITIVE' ) {

                   if ($allTimeSchedules->[$ts]{'isEnabled'}) {
                     $ret{"soundswitch_date_enabled"} = $allTimeSchedules->[$ts]{'isEnabled'} == 1 ? "on" : "off";

                     $ret{"soundswitch_start_day"}   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startDate'};
                     $ret{"soundswitch_start_day"}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                     $ret{"soundswitch_start_month"} = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startDate'};
                     $ret{"soundswitch_start_month"} =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                     $ret{"soundswitch_start_year"}  = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startDate'};
                     $ret{"soundswitch_start_year"}  =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$1/;

                     $ret{"soundswitch_start_hh"}    = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startTime'};
                     $ret{"soundswitch_start_hh"}    =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                     $ret{"soundswitch_start_mm"}    = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startTime'};
                     $ret{"soundswitch_start_mm"}    =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;

                     $ret{"soundswitch_end_day"}     = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endDate'};
                     $ret{"soundswitch_end_day"}     =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                     $ret{"soundswitch_end_month"}   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endDate'};
                     $ret{"soundswitch_end_month"}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                     $ret{"soundswitch_end_year"}    = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endDate'};
                     $ret{"soundswitch_end_year"}    =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$1/;

                     $ret{"soundswitch_end_hh"}      = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endTime'};
                     $ret{"soundswitch_end_hh"}      =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                     $ret{"soundswitch_end_mm"}      = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endTime'};
                     $ret{"soundswitch_end_mm"}      =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                   }
                 }

               }

               if ($skills->{'event'}) {
                 $ret{"soundswitchaction"} = 0 if $skills->{'event'}{'description'}{'action'} eq "SET_OFF";
                 $ret{"soundswitchaction"} = 1 if $skills->{'event'}{'description'}{'action'} eq "SET_ON";
                 $ret{"soundswitchaction"} = 2 if $skills->{'event'}{'description'}{'action'} eq "TOGGLE";
               }

               if ($skills->{'trigger'}) {
                 $ret{"soundswitchrule"}       = "clap" if $skills->{'trigger'}{'details'}{'type'} eq "SmartHomeClapping";
                 $ret{"soundswitchrule"}       = "free" if $skills->{'trigger'}{'details'}{'type'} eq "SmartHomeSound";
                 $ret{"soundswitch_intensity"} = $skills->{'trigger'}{'details'}{'intensity'};

                 $ret{"soundswitchrule_free_freq-min"}        = ($skills->{'trigger'}{'details'}{'lowerFrequencyBoundInHz'} - 125) / 62.5;
                 $ret{"soundswitchrule_free_freq-max"}        = ($skills->{'trigger'}{'details'}{'higherFrequencyBoundInHz'} - 125) / 62.5;

                 my $milliseconds = $skills->{'trigger'}{'details'}{'signalDurationInMilliseconds'};
                 my $seconds = int($milliseconds / 1000);
                 my $minutes = int($seconds / 60);

                 $seconds = $seconds % 60;
                 $milliseconds = $milliseconds % 1000;

                 $ret{"soundswitch_signal_duration_min"}      = $minutes;
                 $ret{"soundswitch_signal_duration_sec"}      = $seconds;
                 $ret{"soundswitch_signal_duration_millisec"} = $milliseconds;
                 $ret{"soundswitchrulefreetype"}              = $skills->{'trigger'}{'details'}{'event'} eq "SILENCE" ? 0 : 1;

               }
             }

           # Socket
           } elsif( $unitData->{'type'} eq 'SOCKET' ) {

             $ret{device_web_site} = "AUTOMATION";
             $skills = $unitData->{'skills'}[1];

             if ( $skills->{'standby'} ) {

               if ($skills->{'standby'}{'isEnabled'}) {
                 $ret{"standby"}           = $skills->{'standby'}{'isEnabled'} ? "on" : "off";
                 $ret{"stand_by_duration"} = $skills->{'standby'}{'seconds'} / 60;
                 $ret{"stand_by_power"}    = $skills->{'standby'}{'powerInWatt'} * 10;
               } else {
                 $ret{"stand_by_power"}    = "";
                 $ret{"stand_by_duration"} = "";
               }

             }

             $skills = $unitData->{'skills'}[2];

             Log3 $name, 4, "unitData->displayName: " . $unitData->{'displayName'};
             Log3 $name, 4, "skills->type: " . $skills->{'type'};

             $ret{"switchautomatic"}  = "on" if $skills->{'timeControl'}{'isEnabled'}; # ? "on" : "off";
             $ret{"graphState"}       = 1;

             $ret{"countdown_off_hh"} = 0;
             $ret{"countdown_off_mm"} = 0;
             $ret{"countdown_onoff"}  = 0;

             $ret{"timer_item_0"} = "0730;1;127";
             $ret{"timer_item_1"} = "1830;0;127";
             $ret{"switchtimer"}  = "weekly";

             # find needed time schedule
             $allTimeSchedules = $skills->{'timeControl'}{'timeSchedules'};

             Log3 $name, 4, "allTimeSchedules:\n" . Dumper($allTimeSchedules);



             for my $ts (0 .. scalar @{$allTimeSchedules} - 1) {

               Log3 $name, 4, "kind[$ts]: " . $allTimeSchedules->[$ts]{'kind'};

               # parse weekly timetable
               if( $allTimeSchedules->[$ts]{'kind'} eq 'WEEKLY_TIMETABLE') {

                 $ret{"switchtimer"} = "weekly" if $allTimeSchedules->[$ts]{'isEnabled'};

                 $timeSchedule = $allTimeSchedules->[$ts]{'actions'};
                 my $NumEntries = scalar @{$timeSchedule};
                 my @timerItems = ();
             
                 for my $i (0 .. $NumEntries - 1) {
                   my $startTime   = $timeSchedule->[$i]{'timeSetting'}{'startTime'};
                   my $dayOfWeek   = $timeSchedule->[$i]{'timeSetting'}{'dayOfWeek'};
                   my $action      = $timeSchedule->[$i]{'description'}{'action'};
                   my $isEnabled   = $timeSchedule->[$i]{'isEnabled'};
                   my %timerItem;
                   my $newItem = 1;
               
                   $startTime   =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1$2/;
                   $dayOfWeek   = $dayOfWeekMap->{$dayOfWeek};
               
                   foreach (@timerItems) {
                     if ($_->{'startTime'} == $startTime && $_->{'action'} eq $action) {
                       $_->{'dayOfWeek'} += $dayOfWeek;
                       $newItem = 0;
                       last;
                     }
                   }

                   if( $newItem ) {
                     $timerItem{'startTime'}   = $startTime;
                     $timerItem{'dayOfWeek'}   = $dayOfWeek;
                     $timerItem{'action'}      = $action;
                     $timerItem{'isEnabled'}   = $isEnabled;
                     push( @timerItems, \%timerItem );
                   }

                 }

                 if (@timerItems > 0) {
                   my $j = 0;
                   foreach (@timerItems) {
                     $ret{"timer_item_$j"} = $_->{'startTime'}.';' . ($_->{'action'} eq "SET_ON" ? 1 : 0) . ';' . $_->{'dayOfWeek'};
                     $j ++;
                   }
                 } else {
                   $ret{"timer_item_0"} = "0730;1;127";
                   $ret{"timer_item_1"} = "1830;0;127";
                 }

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'REPETITIVE') {

                 $ret{"switchtimer"} = "weekly" if $allTimeSchedules->[$ts]{'isEnabled'};

                 my $startTime   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startTime'};
                 my $endTime     = $allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'startTime'};

                 $ret{"daily_from_hh"} = $startTime;
                 $ret{"daily_from_hh"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                 $ret{"daily_from_mm"} = $startTime;
                 $ret{"daily_from_mm"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;

                 $ret{"daily_on"}      = $allTimeSchedules->[$ts]{'actions'}[0]{'description'}{action} eq 'SET_ON' ? 1 : 0;

                 $ret{"daily_to_hh"} = $endTime;
                 $ret{"daily_to_hh"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                 $ret{"daily_to_mm"} = $endTime;
                 $ret{"daily_to_mm"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;

                 $ret{"daily_off"}     = $allTimeSchedules->[$ts]{'actions'}[1]{'description'}{action} eq 'SET_OFF' ? 1 : 0;

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'RANDOM' ) {

                 $ret{"switchtimer"} = "zufall" if $allTimeSchedules->[$ts]{'isEnabled'};

                 my $startDate   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startDate'};
                 my $startTime   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startTime'};
                 my $endDate     = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endDate'};
                 my $endTime     = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'endTime'};
                 my $duration    = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'durationInSeconds'} / 60;
               
                 $ret{"zufall_from_day"}   = $startDate;
                 $ret{"zufall_from_day"}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                 $ret{"zufall_from_month"} = $startDate;
                 $ret{"zufall_from_month"} =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                 $ret{"zufall_from_year"}  = $startDate;
                 $ret{"zufall_from_year"}  =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$1/;

                 $ret{"zufall_to_day"}   = $endDate;
                 $ret{"zufall_to_day"}   =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                 $ret{"zufall_to_month"} = $endDate;
                 $ret{"zufall_to_month"} =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                 $ret{"zufall_to_year"}  = $endDate;
                 $ret{"zufall_to_year"}  =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$1/;

                 $ret{"zufall_from_hh"} = $startTime;
                 $ret{"zufall_from_hh"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                 $ret{"zufall_from_mm"} = $startTime;
                 $ret{"zufall_from_mm"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;

                 $ret{"zufall_to_hh"} = $endTime;
                 $ret{"zufall_to_hh"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                 $ret{"zufall_to_mm"} = $endTime;
                 $ret{"zufall_to_mm"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;

                 $ret{"zufall_duration"} = $duration;

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'COUNTDOWN' ) {

                 $ret{"switchtimer"} = "countdown" if $allTimeSchedules->[$ts]{'isEnabled'};

                 my $hms = strftime('%T', gmtime($allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'durationInSeconds'}));

                 if ( $allTimeSchedules->[$ts]{'actions'}[0]{'description'}{'action'} eq "SET_OFF") {
     
                   $ret{"countdown_off_hh"} = $hms;
                   $ret{"countdown_off_hh"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                   $ret{"countdown_off_mm"} = $hms;
                   $ret{"countdown_off_mm"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                   $ret{"countdown_onoff"}  = 0;

                 } else {

                   $ret{"countdown_on_hh"} = $hms;
                   $ret{"countdown_on_hh"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                   $ret{"countdown_on_mm"} = $hms;
                   $ret{"countdown_on_mm"} =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                   $ret{"countdown_onoff"} = 1;

                 }

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'PATTERN_REPETITION' ) {

                 $ret{"switchtimer"}   = "rythmisch" if $allTimeSchedules->[$ts]{'isEnabled'};

                 $ret{"rythmisch_off"} = $allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'durationInSeconds'} / 60;
                 $ret{"rythmisch_on"}  = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'durationInSeconds'} / 60;

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'ONCE' ) {

                 $ret{"switchtimer"}   = "single" if $allTimeSchedules->[$ts]{'isEnabled'};

                 my $startDate   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startDate'};
                 my $startTime   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startTime'};
                 my $duration    = -1;

                 $duration = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'durationInSeconds'} / 60 if $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'durationInSeconds'};

                 $ret{"single_onoff"}    = $allTimeSchedules->[$ts]{'actions'}[0]{'description'}{'action'} eq 'SET_ON' ? 1 : 0;
                 $ret{"single_day"}      = $startDate;
                 $ret{"single_day"}      =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$3/;
                 $ret{"single_month"}    = $startDate;
                 $ret{"single_month"}    =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$2/;
                 $ret{"single_year"}     = $startDate;
                 $ret{"single_year"}     =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/$1/;
                 $ret{"single_hh"}       = $startTime;
                 $ret{"single_hh"}       =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                 $ret{"single_mm"}       = $startTime;
                 $ret{"single_mm"}       =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                 $ret{"single_duration"} = $duration;

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'ASTRONOMICAL_CALENDAR' ) {

                 $ret{"switchtimer"} = "sun_calendar" if $allTimeSchedules->[$ts]{'isEnabled'};

                 $ret{"longitude"}   = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'location'}{'longitude'};
                 $ret{"latitude"}    = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'location'}{'latitude'};

                 my $posofsun        = lc($allTimeSchedules->[$ts]{'name'});

                 if (!$allTimeSchedules->[$ts]{'isEnabled'}) {

                   $ret{$posofsun."_on_relative"}  = "00:00";
                   $ret{$posofsun."_off_relative"} = "00:00";
                   $ret{$posofsun."_off_duration"} = "00:00";

                 } else {

                   $ret{$posofsun}     = $allTimeSchedules->[$ts]{'isEnabled'} == 0 ? "off" : "on"; #: on

                   # xhr 1 lang de page sh_dev xhrId all
                   # { Dumper FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "31", "test")}

                   if( $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'astronomicalEvent'} =~ /SUNRISE|SUNSET/ ) {

                     my $hms = strftime('%T', gmtime(abs($allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'timeOffsetInMinutes'}) * 60));

                     $ret{$posofsun."_on_option"}             = "relative";
                     $ret{$posofsun."_on_relative0"}          = $hms;
                     $ret{$posofsun."_on_relative0"}          =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                     $ret{$posofsun."_on_relative1"}          = $hms;
                     $ret{$posofsun."_on_relative1"}          =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                     $ret{$posofsun."_on_relative"}           = $hms;
                     $ret{$posofsun."_on_relative"}           =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1:$2/;
                     $ret{$posofsun."_on_relative_negative"}  = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'timeOffsetInMinutes'} >= 0 ? "false" : "true";

                     my $astroEvent = $allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'astronomicalEvent'}; 

                     if( ($astroEvent =~ /SUNRISE|SUNSET/) && ($astroEvent ne $allTimeSchedules->[$ts]{'name'}) ) {

                       $ret{$posofsun."_off_option"}             = lc($astroEvent);
                       $ret{$posofsun."_off_relative"}           = "00:00";
                       $ret{$posofsun."_off_relative_negative"}  = "false";
                       $ret{$posofsun."_off_duration"}           = "00:00";

                     } elsif( $astroEvent =~ /MANUALLY/ ) {

                       if ($allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'endTime'}) {

                         $ret{$posofsun."_off_option"}             = "absolute";
                         $ret{$posofsun."_off_absolute"}           = $allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'endTime'};
                         $ret{$posofsun."_off_absolute"}           =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1:$2/;
                         $ret{$posofsun."_off_relative"}           = "00:00";
                         $ret{$posofsun."_off_relative_negative"}  = "false";
                         $ret{$posofsun."_off_duration"}           = "00:00";

                       } else {

                         $ret{$posofsun."_off_option"}             = lc($astroEvent);
                         $ret{$posofsun."_off_relative"}           = "00:00";
                         $ret{$posofsun."_off_relative_negative"}  = "false";
                         $ret{$posofsun."_off_duration"}           = "00:00";

                       }

                     } elsif( $astroEvent =~ /SUNRISE|SUNSET/ && $astroEvent eq $allTimeSchedules->[$ts]{'name'} ) {

                       $hms = strftime('%T', gmtime(
                           ( $allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'timeOffsetInMinutes'}
                             - 
                             $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'timeOffsetInMinutes'} 
                           ) * 60 ));

                       $ret{$posofsun."_off_relative"}           = "00:00";
                       $ret{$posofsun."_off_relative_negative"}  = "false";
                       $ret{$posofsun."_off_option"}             = "duration";

                       $ret{$posofsun."_off_duration0"}          = $hms;
                       $ret{$posofsun."_off_duration0"}          =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                       $ret{$posofsun."_off_duration1"}          = $hms;
                       $ret{$posofsun."_off_duration1"}          =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                       $ret{$posofsun."_off_duration"}           = $hms;
                       $ret{$posofsun."_off_duration"}           =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1:$2/;
                     }


                   } elsif( $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'astronomicalEvent'} eq "MANUALLY" ) {

                     $ret{$posofsun."_on_relative"}           = "00:00";
                     $ret{$posofsun."_on_relative_negative"}  = "false";
                     $ret{$posofsun."_on_option"}             = "absolute";
                     $ret{$posofsun."_on_absolute"}           = $allTimeSchedules->[$ts]{'actions'}[0]{'timeSetting'}{'startTime'};
                     $ret{$posofsun."_on_absolute"}           =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1:$2/;

                     my $hms = strftime('%T', gmtime(abs($allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'timeOffsetInMinutes'}) * 60));

                     $ret{$posofsun."_off_option"}             = "relativ";
                     $ret{$posofsun."_off_relative0"}          = $hms;
                     $ret{$posofsun."_off_relative0"}          =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1/;
                     $ret{$posofsun."_off_relative1"}          = $hms;
                     $ret{$posofsun."_off_relative1"}          =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$2/;
                     $ret{$posofsun."_off_relative"}           = $hms;
                     $ret{$posofsun."_off_relative"}           =~ s/([0-9]{2}):([0-9]{2}):([0-9]{2})/$1:$2/;
                     $ret{$posofsun."_off_relative_negative"}  = $allTimeSchedules->[$ts]{'actions'}[1]{'timeSetting'}{'timeOffsetInMinutes'} >= 0 ? "false" : "true"; #: false
                     $ret{$posofsun."_off_duration"}           = "00:00";

                   }
                 }

               } elsif( $allTimeSchedules->[$ts]{'kind'} eq 'CALENDAR' ) {

                 $ret{"switchtimer"} = "calendar" if $allTimeSchedules->[$ts]{'isEnabled'};

                 $ret{"calendarname"} = $allTimeSchedules->[$ts]{'calendar'}{'name'}; #: https://calendar.google.com/calendar/u/0/r?pli=1

               }

             }

           }
         }
         last;
       }
     }


     if( keys(%ret) ) {

       FRITZBOX_Log $hash, 5, "SmartHome Device info\n" . Dumper(\%ret) if keys(%ret);

     } else {
       FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> ID:$devID not found";
       my %retHash = ("Error" => "SmartHome Device", "Info" => "ID:$devID not found");
       return \%retHash;
     }

     if ($command eq "table") {

       my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

       $returnStr .= '<table';
       $returnStr .= ' border="8"'       if $tableFormat !~ "border";
       $returnStr .= ' cellspacing="15"' if $tableFormat !~ "cellspacing";
       $returnStr .= ' cellpadding="25"' if $tableFormat !~ "cellpadding";
       $returnStr .= '>';
       $returnStr .= "<tr>\n";
       $returnStr .= '<td colspan="2">SmartHome Device</td>';
       $returnStr .= "</tr>\n";
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>TYPE</td><td>Value</td>\n";
       $returnStr .= "</tr>\n";

       foreach( sort keys %ret ) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $_ . "</td>";
         $returnStr .= "<td>" . $ret{$_} . "</td>";
         $returnStr .= "</tr>\n";
       }
       $returnStr .= "</table>\n";

       return $returnStr;

     } elsif ($command eq "save") {
       # { FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17", "save")}
       # setKeyValue

       my $categrory = $ret{device_name_category};

       if ( !$categrory || ($categrory !~ /[THERMOSTAT|SOCKET]/) ) {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> saving for " . $categrory . " not implemented yet.";
         my %retHash = ("Error" => "SmartHome Device", "Info" => "saving for " . $categrory . " not implemented yet.");
         return \%retHash;
       }

       my $smh_pre_path = $attr{global}{modpath} . "/FHEM/FhemUtils/smart_home_predefs.txt";

       my ($err, @old) = FileRead($smh_pre_path);

       my @new;
       if($err) {
         push(@new, "# This file is auto generated.",
               "# Please do not modify, move or delete it.",
               "");
         @old = ();
       }

       my $jsonStr = "";
       my $saveStr = "";
       my $retStr  = "";

       my @sortRet = ();
       if ($categrory eq "THERMOSTAT") {
         @sortRet = sort (keys %ret);
         $retStr  = "";

         foreach my $key (@sortRet) {
           $retStr .= $key . ": " . $ret{$key} . "\n";
         }

         $jsonStr = encode_json(\%ret);
         $saveStr = encode_base64($jsonStr,"");

       } elsif ($categrory eq "SOCKET") {
      
         @sortRet = sort (keys %ret);
         $retStr  = "";

         foreach my $key (@sortRet) {
           $retStr .= $key . ": " . $ret{$key} . "\n";
         }

         @sortRet = sort (keys %ret1);

         $retStr  .= "\n";
         foreach my $key (@sortRet) {
           $retStr .= $key . ": " . $ret1{$key} . "\n";
         }

         $jsonStr = encode_json(\%ret);
         $saveStr = encode_base64($jsonStr,"");

         $jsonStr = encode_json(\%ret1);
         $saveStr = encode_base64($jsonStr,"") . "|" . $saveStr;

       } else {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> saving for " . $categrory . " not implemented yet.";
         my %retHash = ("Error" => "SmartHome Device", "Info" => "saving for " . $categrory . " not implemented yet.");
         return \%retHash;
       }

       $saveStr = "|" . $categrory . "|" . $saveStr;

       my $fnd;
       foreach my $l (@old) {
         if($l =~ m/^$name:$devID:$preName/) {
           $fnd = 1;
           push @new, "$name:$devID:$preName:$saveStr" if defined($saveStr);
         } else {
           push @new, $l;
         }
       }
       push @new, "$name:$devID:$preName:$saveStr" if(!$fnd && defined($saveStr));

       my $errSave = FileWrite($smh_pre_path, @new);

       if(defined($errSave)) {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> saving the $smh_pre_path - $errSave";
         my %retHash = ("Error" => "SmartHome Device", "Info" => "saving the $smh_pre_path - $errSave");
         return \%retHash;

       } else {

         $retStr =~ s/\\n//;
         FRITZBOX_Log $hash, 4, "saved smart home predef for device:$devID and predef:$preName\n" . $retStr;
         return \%ret;

       }

     } elsif ($command eq "test") {

       my $categrory = $ret{device_name_category};
       my @sortRet = sort (keys %ret);
       my $retStr = "";

       if ($categrory =~ /SOCKET/) {

         my @sortRet1 = sort (keys %ret1);

         $retStr .= "Allgemein\n";
         foreach my $key (@sortRet1) {
           $retStr .= $key . ": " . $ret1{$key} . "\n";
         }

         $retStr .= "\nAutomatisch Schalten\n";
         foreach my $key (@sortRet) {
           $retStr .= $key . ": " . $ret{$key} . "\n";
         }

       } else {

         $retStr .= "Allgemein\n";
         foreach my $key (@sortRet) {
           $retStr .= $key . ": " . $ret{$key} . "\n";
         }

       }

       return $retStr;

     } else {

       my @sortRet = sort (keys %ret);
       my $retStr = "";

       foreach my $key (@sortRet) {
         $retStr .= $key . ": " . $ret{$key} . "|";
       }

       FRITZBOX_Log $hash, 4, "return smart home infos for device:$devID and predef:$preName\n" . $retStr;
       return \%ret;
     }

     # end only for one device

   } elsif ($devID && $command =~ /delete/) {

       my @new;
       my $smh_pre_path = $attr{global}{modpath} . "/FHEM/FhemUtils/smart_home_predefs.txt";

       my ($err, @old) = FileRead($smh_pre_path);

       if ($err) {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> reading the $smh_pre_path - $err";
         my %retHash = ("Error" => "SmartHome Device", "Info" => "reading the $smh_pre_path - $err");
         return \%retHash;
       }

       my $fnd;
       foreach my $l (@old) {
         if($l !~ m/^$name:$devID:$preName/) {
           push @new, $l;
         } else {
           $fnd = 1;
         }
       }

       my $errSave = FileWrite($smh_pre_path, @new) if $fnd;

       if(defined($errSave)) {
         FRITZBOX_Log $hash, 2, "deleting SmartHome preDef -> saving the $smh_pre_path - $errSave";
         my %retHash = ("Error" => "deleting SmartHome preDef", "Info" => "saving the $smh_pre_path - $errSave");
         return \%retHash;

       } else {
         if ($fnd) {
           FRITZBOX_Log $hash, 4, "deleting SmartHome preDef -> deleted preDef for device:$devID and predef:$preName";
           my %retHash = ( "apply" => "ok", "Info" => "deleted preDef for device:$devID and predef:$preName");
           return \%retHash;
         } else {
           FRITZBOX_Log $hash, 4, "deleting SmartHome preDef -> preDef for device:$devID and predef:$preName not found";
           my %retHash = ( "Error" => "deleting SmartHome preDef", "Info" => "for device:$devID and predef:$preName not found");
           return \%retHash;
         }
       }

   # { FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17", "load")}
   } elsif ($devID && $command =~ /load/) {

       my $codedStr = "";

       my $smh_pre_path = $attr{global}{modpath} . "/FHEM/FhemUtils/smart_home_predefs.txt";
       my ($err, @l) = FileRead($smh_pre_path);

       if ($err) {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> reading the $smh_pre_path - $err";
         my %retHash = ("Error" => "SmartHome Device", "Info" => "reading the $smh_pre_path - $err");
         return \%retHash;
       }

       for my $l (@l) {
         if($l =~ m/^$name:$devID:$preName:(.*)/) {
           $codedStr = $1;
           last;
         }
       }

       if ( $codedStr eq "" ) {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> no predef found for device:$devID and predef:$preName\n" . $codedStr;
         my %retHash = ("Error" => "SmartHome Device", "Info" => "no predef found for device:$devID and predef:$preName");
         return \%retHash;
       }
       #{ Dumper FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "17", "load", "SH17Neu")}
       #{ Dumper FRITZBOX_Get_SmartHome_Devices_List($defs{"FritzBox"}, "16", "load", "TH16Neu")}

       my @preDefs = split('\|', $codedStr);

       if (@preDefs && int(@preDefs) >= 2) {

         my $aut = $preDefs[2];
         my $gen = $preDefs[3] if $preDefs[3];

         my $msg = $codedStr . "\nautomation :" . $aut . "\ngeneral:";
            $msg .= $gen ? $gen : "leer";
            $msg .= "\ncnt: " . int(@preDefs);

         FRITZBOX_Log $hash, 5, $msg;

         if ($command =~ /loads/) {
           $codedStr = $aut;
         } else {
           $codedStr = $gen ? $gen : $aut;
         }

         $codedStr =~ s/\|//;

         my $jsonStr = decode_base64($codedStr);
         my %valueHash = %{ decode_json($jsonStr) };

         my @sortRet = sort (keys %valueHash);
         my $retStr  = "";

         foreach my $key (@sortRet) {
           $retStr .= $key . ": " . $valueHash{$key} . "\n";
         }

         FRITZBOX_Log $hash, 5, "read smart home predef for device:$devID and predef:$preName\n" . $retStr;
         return \%valueHash;

     } else {
         FRITZBOX_Log $hash, 2, "getting SmartHome Device info -> no predef found for device:$devID and predef:$preName\n" . $codedStr;
         my %retHash = ("Error" => "SmartHome Device", "Info" => "no predef found for device:$devID and predef:$preName");
         return \%retHash;
     }

   } else {

     if ( $analyse =~ /ERROR/) {
       FRITZBOX_Log $hash, 4, "getting smart home info -> " . $analyse;
       $returnStr  = "SmartHome Devices: Active\n";
       $returnStr .= "------------------\n";
       return $returnStr . $analyse;
     }

#    border(8),cellspacing(10),cellpadding(20)
     my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

     $returnStr .= '<table';
     $returnStr .= ' border="8"'       if $tableFormat !~ "border";
     $returnStr .= ' cellspacing="15"' if $tableFormat !~ "cellspacing";
     $returnStr .= ' cellpadding="25"' if $tableFormat !~ "cellpadding";
     $returnStr .= '>';
     $returnStr .= "<tr>\n";
     $returnStr .= '<td colspan="6">SmartHome Groups</td>';
     $returnStr .= "</tr>\n";
     $returnStr .= "<tr>\n";
     $returnStr .= "<td>ID</td><td>TYPE</td><td>Name</td><td>Category</td>\n";
     $returnStr .= "</tr>\n";

     $nbViews = 0;

     if (defined $result->{data}->{groups}) {
       $views = $result->{data}->{groups};
       $nbViews = scalar @$views;
     }

     if ($nbViews > 0) {

       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{groups}->[$i]->{id} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{groups}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{groups}->[$i]->{displayName} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{groups}->[$i]->{category} . "</td>";
         $returnStr .= "</tr>\n";

         if ( $result->{data}->{groups}->[$i]->{members} ) {
           my $members = $result->{data}->{groups}->[$i]->{members};

           $returnStr .= "<td></td>";
           $returnStr .= "<td>Members</td>";
           $returnStr .= "<td>ID</td>";
           $returnStr .= "<td>Displayname</td>";
           $returnStr .= "</tr>\n";

           for my $mem (0 .. scalar @{$members} - 1) {
             $returnStr .= "<td></td>";
             $returnStr .= "<td></td>";
             $returnStr .= "<td>" . $members->[$mem]->{id} . "</td>";
             $returnStr .= "<td>" . $members->[$mem]->{displayName} . "</td>";
             $returnStr .= "</tr>\n";
           }
         }
       }
     }
     $returnStr .= "</table>\n";

     $returnStr .= '<table';
     $returnStr .= ' border="8"'       if $tableFormat !~ "border";
     $returnStr .= ' cellspacing="15"' if $tableFormat !~ "cellspacing";
     $returnStr .= ' cellpadding="25"' if $tableFormat !~ "cellpadding";
     $returnStr .= '>';
     $returnStr .= "<tr>\n";
     $returnStr .= '<td colspan="10">SmartHome Devices</td><td colspan="7">Skills</td>';
     $returnStr .= "</tr>\n";
     $returnStr .= "<tr>\n";
     $returnStr .= "<td>ID</td><td>TYPE</td><td>Name</td><td>Status</td><td>Category</td><td>Manufacturer</td><td>Model</td><td>Firmware</td><td>Temp</td><td>Offset</td><td>Humidity</td>"
                 . "<td>Battery</td><td>Volt</td><td>Power</td><td>Current</td><td>Consumption</td><td>ledState</td><td>State</td>\n"; 
     $returnStr .= "</tr>\n";

     $nbViews = 0;

     if (defined $result->{data}->{devices}) {
       $views = $result->{data}->{devices};
       $nbViews = scalar @$views;
     }

     if ($nbViews > 0) {

       for(my $i = 0; $i <= $nbViews - 1; $i++) {
         $returnStr .= "<tr>\n";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{id} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{type} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{displayName} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{masterConnectionState} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{category} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{manufacturer}->{name} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{model} . "</td>";
         $returnStr .= "<td>" . $result->{data}->{devices}->[$i]->{firmwareVersion}->{current} . "</td>";

         if ( $result->{data}->{devices}->[$i]->{units} ) {
           my @skillInfo = ("<td></td>","<td></td>","<td></td>","<td></td>","<td></td>","<td></td>","<td></td>","<td></td>","<td></td>","<td></td>");
           my $units = $result->{data}->{devices}->[$i]->{units};
           for my $unit (0 .. scalar @{$units} - 1) {
             if( $units->[$unit]->{'type'} eq 'THERMOSTAT' ) {

             } 
            
             if ( $units->[$unit]->{'type'} eq 'TEMPERATURE_SENSOR' ) {
               $skillInfo[0] = "<td>" . $units->[$unit]->{skills}->[0]->{currentInCelsius} . "°C</td>";
               $skillInfo[1] = "<td>" . $units->[$unit]->{skills}->[0]->{offset} . "°C</td>";

             } elsif ( $units->[$unit]->{'type'} eq 'HUMIDITY_SENSOR' ) {
               $skillInfo[2] = "<td>" . $units->[$unit]->{skills}->[0]->{currentInPercent} . "%</td>";

             } elsif ( $units->[$unit]->{'type'} eq 'BATTERY' ) {
               $skillInfo[3] = "<td>" . $units->[$unit]->{skills}->[0]->{chargeLevelInPercent} . "%</td>";

             } elsif ( $units->[$unit]->{'type'} eq 'SOCKET' ) {
               if($units->[$unit]->{skills}->[0]->{voltageInVolt}) {
                 $skillInfo[4] = "<td>" . $units->[$unit]->{skills}->[0]->{voltageInVolt} . " V</td>";
                 $skillInfo[5] = "<td>" . $units->[$unit]->{skills}->[0]->{powerPerHour} . " w/h</td>";
                 $skillInfo[6] = "<td>" . $units->[$unit]->{skills}->[0]->{electricCurrentInAmpere} . " A</td>";
                 $skillInfo[7] = "<td>" . $units->[$unit]->{skills}->[0]->{powerConsumptionInWatt} . " W</td>";
               }
               $skillInfo[8] = "<td>" . $units->[$unit]->{skills}->[1]->{ledState};
               $skillInfo[9] = "<td>" . $units->[$unit]->{skills}->[2]->{state};
             }

           }
           $returnStr .= join("", @skillInfo);
         }

         $returnStr .= "</tr>\n";
       }
     }

     my $smh_pre_path = $attr{global}{modpath} . "/FHEM/FhemUtils/smart_home_predefs.txt";
     my ($err, @l) = FileRead($smh_pre_path);

     $returnStr .= '<table';
     $returnStr .= ' border="8"'       if $tableFormat !~ "border";
     $returnStr .= ' cellspacing="15"' if $tableFormat !~ "cellspacing";
     $returnStr .= ' cellpadding="25"' if $tableFormat !~ "cellpadding";
     $returnStr .= '>';
     $returnStr .= "<tr>\n";
     $returnStr .= '<td colspan="10">SmartHome preDefs</td>';
     $returnStr .= "</tr>\n";
     $returnStr .= "<tr>\n";
     $returnStr .= "<td>ID</td><td>preDef</td>";
     $returnStr .= "</tr>\n";

     if ($err) {
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>no</td>";
       $returnStr .= "<td>Information</td>";
     } else {
       for my $l (@l) {
         if($l =~ m/^$name:(\d+):([-\w]+):.*$/) {
           $returnStr .= "<tr>\n";
           $returnStr .= "<td>" . $1 . "</td>";
           $returnStr .= "<td>" . $2 . "</td>";
         }
       }
     }
     $returnStr .= "</tr>\n";

     $returnStr .= "</table>\n";
   }

   return $returnStr;

} # end FRITZBOX_Get_Lan_Devices_List

# get list of smartHome Devices
############################################
sub FRITZBOX_Get_Lan_Devices_List($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   FRITZBOX_Log $hash, 4, "FRITZBOX_Lan_Device_List (Fritz!OS: $hash->{fhem}{fwVersionStr}) ";

   my @webCmdArray;
   # "xhr 1 lang de page netDev xhrId cleanup useajax 1 no_sidrenew nop;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "netDev";
   push @webCmdArray, "xhrId"       => "all";

   my $returnStr;

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr  = "LanDevices: Active\n";
     $returnStr .= "------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr  = "LanDevices: Active\n";
     $returnStr .= "------------------\n";
     return $returnStr . "AuthorizationRequired";
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

} # end FRITZBOX_Get_Lan_Devices_List

# get list of User informations
############################################
sub FRITZBOX_Get_User_Info_List($) {
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $queryStr = "&user_info=boxusers:settings/user/list(name,box_admin_rights,enabled,email,myfritz_boxuser_uid,homeauto_rights,dial_rights,nas_rights,vpn_access)";

   my $returnStr;

   my $result = FRITZBOX_call_Lua_Query( $hash, $queryStr) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "Benutzer Informationen:\n";
     $returnStr .= "---------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "Benutzer Informationen:\n";
     $returnStr .= "---------------------------\n";
     return $returnStr . "AuthorizationRequired";
   }

   eval {
      FRITZBOX_Log $hash, 5, "evaluating user info: \n" . Dumper($result->{user_info});
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

} # end FRITZBOX_Get_User_Info_List

# get list of Kid Profiles
############################################
sub FRITZBOX_Get_Kid_Profiles_List($) {

   my ($hash) = @_;
   my $name = $hash->{NAME};

   # "xhr 1 lang de page kidPro;

   my @webCmdArray;
   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "kidPro";

   my $returnStr;

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   my $analyse = FRITZBOX_Helper_analyse_Lua_Result($hash, $result);

   if ( defined $result->{Error} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> " . $analyse;
     $returnStr .= "Kid Profiles:\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . $analyse;
   } elsif ( defined $result->{AuthorizationRequired} ) {
     FRITZBOX_Log $hash, 2, "evaluating user info -> AuthorizationRequired";
     $returnStr .= "Kid Profiles:\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "AuthorizationRequired";
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
       FRITZBOX_Log $hash, 5, "Kid Profiles: ".$key;
       $returnStr .= "<tr>\n";
       $returnStr .= "<td>" . $key . "</td>";
       $returnStr .= "<td>" . $result->{data}->{kidProfiles}->{$key}{Name} . "</td>";
       $returnStr .= "<td>" . $result->{data}->{kidProfiles}->{$key}{Id} . "</td>";
       $returnStr .= "</tr>\n";
     }
   };

   $returnStr .= "</table>\n";

   return $returnStr;

} # end FRITZBOX_Get_Kid_Profiles_List

#######################################################################
sub FRITZBOX_Get_Fritz_Log_Info_nonBlk($)
{
   my ($string) = @_;
   my ($name, $cmd, @val) = split "\\|", $string;
   my $hash = $defs{$name};
   my $result;
   my $sidNew = 0;
   my @webCmdArray;
   my @roReadings;
   my $startTime = time();
   my $returnCase = 2;
   my $returnLog = "";

   # Frizt!OS >= 7.50
   # xhr 1 lang de page log apply nop filter wlan wlan on | off             -> on oder off erweitertes WLAN-Logging

   # xhr 1 lang de page log xhrId log filter all  useajax 1 no_sidrenew nop -> Log-Einträge Alle
   # xhr 1 lang de page log xhrId log filter sys  useajax 1 no_sidrenew nop -> Log-Einträge System
   # xhr 1 lang de page log xhrId log filter wlan useajax 1 no_sidrenew nop -> Log-Einträge WLAN
   # xhr 1 lang de page log xhrId log filter usb  useajax 1 no_sidrenew nop -> Log-Einträge USB
   # xhr 1 lang de page log xhrId log filter net  useajax 1 no_sidrenew nop -> Log-Einträge Internetverbindung
   # xhr 1 lang de page log xhrId log filter fon  useajax 1 no_sidrenew nop -> Log-Einträge Fon

   # Frizt!OS < 7.50
   # xhr 1 lang de page log xhrId all             wlan 7 (on) | 6 (off)     -> on oder off erweitertes WLAN-Logging

   # xhr 1 lang de page log xhrId log filter 0    useajax 1 no_sidrenew nop -> Log-Einträge Alle
   # xhr 1 lang de page log xhrId log filter 1    useajax 1 no_sidrenew nop -> Log-Einträge System
   # xhr 1 lang de page log xhrId log filter 4    useajax 1 no_sidrenew nop -> Log-Einträge WLAN
   # xhr 1 lang de page log xhrId log filter 5    useajax 1 no_sidrenew nop -> Log-Einträge USB
   # xhr 1 lang de page log xhrId log filter 2    useajax 1 no_sidrenew nop -> Log-Einträge Internetverbindung
   # xhr 1 lang de page log xhrId log filter 3    useajax 1 no_sidrenew nop -> Log-Einträge Fon

   my $returnStr;

   FRITZBOX_Log $hash, 3, "fritzlog -> $cmd, $val[0], $val[1]";

   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "log";
   push @webCmdArray, "xhrId"       => "log";
   push @webCmdArray, "useajax"     => "1";
   push @webCmdArray, "no_sidrenew" => "";

   if ($hash->{fhem}{fwVersion} >= 683 && $hash->{fhem}{fwVersion} < 750) {
     push @webCmdArray, "filter"      => "0" if $val[1] =~ /all/;
     push @webCmdArray, "filter"      => "1" if $val[1] =~ /sys/;
     push @webCmdArray, "filter"      => "2" if $val[1] =~ /net/;
     push @webCmdArray, "filter"      => "3" if $val[1] =~ /fon/;
     push @webCmdArray, "filter"      => "4" if $val[1] =~ /wlan/;
     push @webCmdArray, "filter"      => "5" if $val[1] =~ /usb/;
   } elsif ($hash->{fhem}{fwVersion} >= 750) {
     push @webCmdArray, "filter"      => $val[1];
   } else {
   }

   if ($hash->{fhem}{fwVersion} >= 683) {
     FRITZBOX_Log $hash, 4, "data.lua: \n" . join(" ", @webCmdArray);

     $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

     # Abbruch wenn Fehler beim Lesen der Fritzbox-Antwort
     return FRITZBOX_Readout_Response($hash, $result, \@roReadings) if ( defined $result->{Error} || defined $result->{AuthorizationRequired});

     $sidNew += $result->{sidNew} if defined $result->{sidNew};

     FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_fritzLogInfo", "done";

     if (int @val == 3 && $val[2] eq "off") {
       $returnLog = "|" . $val[1] . "|" . toJSON ($result);
       $returnCase = 3;
     } else {

       my $returnExPost = eval { myUtilsFritzLogExPostnb ($hash, $val[1], $result); };

       if ($@) {
         FRITZBOX_Log $hash, 2, "fritzLogExPost: " . $@;
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_fritzLogExPost", "->ERROR: " . $@;
       } else {
         FRITZBOX_Readout_Add_Reading $hash, \@roReadings, "retStat_fritzLogExPost", $returnExPost;
       }
     }
   }

   # Ende und Rückkehr zum Hauptprozess
   push @roReadings, "readoutTime", sprintf( "%.2f", time()-$startTime);
   return FRITZBOX_Readout_Response($hash, $result, \@roReadings, $returnCase, $sidNew, $returnLog);

} # end FRITZBOX_Get_Fritz_Log_Info_nonBlk

##############################################################################################################################################
# Ab hier alle Sub, die für die standard set/get Aufrufe zuständig sind
##############################################################################################################################################

# get list of FritzBox log informations
############################################
sub FRITZBOX_Get_Fritz_Log_Info_Std($$$) {

   my ($hash, $retFormat, $logInfo) = @_;
   my $name = $hash->{NAME};

   # Frizt!OS >= 7.50

   # xhr 1 lang de page log xhrId log filter all  useajax 1 no_sidrenew nop -> Log-Einträge Alle
   # xhr 1 lang de page log xhrId log filter sys  useajax 1 no_sidrenew nop -> Log-Einträge System
   # xhr 1 lang de page log xhrId log filter wlan useajax 1 no_sidrenew nop -> Log-Einträge WLAN
   # xhr 1 lang de page log xhrId log filter usb  useajax 1 no_sidrenew nop -> Log-Einträge USB
   # xhr 1 lang de page log xhrId log filter net  useajax 1 no_sidrenew nop -> Log-Einträge Internetverbindung
   # xhr 1 lang de page log xhrId log filter fon  useajax 1 no_sidrenew nop -> Log-Einträge Fon

   # Frizt!OS < 7.50

   # xhr 1 lang de page log xhrId log filter 0    useajax 1 no_sidrenew nop -> Log-Einträge Alle
   # xhr 1 lang de page log xhrId log filter 1    useajax 1 no_sidrenew nop -> Log-Einträge System
   # xhr 1 lang de page log xhrId log filter 4    useajax 1 no_sidrenew nop -> Log-Einträge WLAN
   # xhr 1 lang de page log xhrId log filter 5    useajax 1 no_sidrenew nop -> Log-Einträge USB
   # xhr 1 lang de page log xhrId log filter 2    useajax 1 no_sidrenew nop -> Log-Einträge Internetverbindung
   # xhr 1 lang de page log xhrId log filter 3    useajax 1 no_sidrenew nop -> Log-Einträge Fon

   my @webCmdArray;

   push @webCmdArray, "xhr"         => "1";
   push @webCmdArray, "lang"        => "de";
   push @webCmdArray, "page"        => "log";
   push @webCmdArray, "xhrId"       => "log";
   push @webCmdArray, "useajax"     => "1";
   push @webCmdArray, "no_sidrenew" => "";

   my $returnStr;

   if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
     push @webCmdArray, "filter"      => "0" if $logInfo =~ /all/;
     push @webCmdArray, "filter"      => "1" if $logInfo =~ /sys/;
     push @webCmdArray, "filter"      => "2" if $logInfo =~ /net/;
     push @webCmdArray, "filter"      => "3" if $logInfo =~ /fon/;
     push @webCmdArray, "filter"      => "4" if $logInfo =~ /wlan/;
     push @webCmdArray, "filter"      => "5" if $logInfo =~ /usb/;
   } elsif ($hash->{fhem}{fwVersion} >= 750) {
     push @webCmdArray, "filter"      => $logInfo;
   } else {
     $returnStr .= "FritzLog Filter:$logInfo\n";
     $returnStr .= "---------------------------------\n";
     return $returnStr . "Not supported Fritz!OS $hash->{fhem}{fwVersionStr}";
   }

   FRITZBOX_Log $hash, 3, "set $name $logInfo " . join(" ", @webCmdArray);

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   if(defined $result->{Error}) {
     $returnStr .= "FritzLog Filter:$logInfo\n";
     $returnStr .= "---------------------------------\n";
     my $tmp = FRITZBOX_ERR_Result($hash, $result);
     return $returnStr . $tmp;
   }

   my $nbViews;
   my $views;

   $nbViews = 0;
   if (defined $result->{data}->{log}) {
     $views = $result->{data}->{log};
     $nbViews = scalar @$views;
   }

   my $tableFormat = AttrVal($name, "disableTableFormat", "undef");

   $returnStr .= '<table';
   $returnStr .= ' border="8"'       if $tableFormat !~ "border";
   $returnStr .= ' cellspacing="10"' if $tableFormat !~ "cellspacing";
   $returnStr .= ' cellpadding="20"' if $tableFormat !~ "cellpadding";
   $returnStr .= '>';
   $returnStr .= "<tr>\n";
   $returnStr .= '<td colspan="4">FritzLog Filter: ' . $logInfo . '</td>';
   $returnStr .= "</tr>\n";
   $returnStr .= "<tr>\n";
   $returnStr .= "<td>ID</td><td>Tag</td><td>Uhrzeit</td><td>Meldung</td>\n";
   $returnStr .= "</tr>\n";

   if ($nbViews > 0) {
     if ($hash->{fhem}{fwVersion} >= 680 && $hash->{fhem}{fwVersion} < 750) {
       eval {
         for(my $i = 0; $i <= $nbViews - 1; $i++) {
           $returnStr .= "<tr>\n";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i][3] . "</td>";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i][0] . "</td>";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i][1] . "</td>";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i][2] . "</td>";
           $returnStr .= "</tr>\n";
         }
       };
     } elsif ($hash->{fhem}{fwVersion} >= 750) {
       eval {
         for(my $i = 0; $i <= $nbViews - 1; $i++) {
           $returnStr .= "<tr>\n";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i]->{id}   . "</td>";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i]->{date} . "</td>";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i]->{time} . "</td>";
           $returnStr .= "<td>" . $result->{data}->{log}->[$i]->{msg}  . "</td>";
           $returnStr .= "</tr>\n";
         }
       };
     }
   }

   $returnStr .= "</table>\n";

   return $returnStr;

} # end FRITZBOX_Get_Fritz_Log_Info_Std

# get info for a lanDevice
############################################
sub FRITZBOX_Get_Lan_Device_Info($$$) {
   my ($hash, $lDevID, $action) = @_;
   my $name = $hash->{NAME};
   FRITZBOX_Log $hash, 4, "LanDevice to proof: " . $lDevID . " for: " . $action;

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

   FRITZBOX_Log $hash, 4, "FRITZBOX_Get_Lan_Device_Info (Fritz!OS: $hash->{fhem}{fwVersionStr}) ";

   if ($hash->{fhem}{fwVersion} >= 725) {
      push @webCmdArray, "page" => "edit_device";
   } else {
      push @webCmdArray, "page" => "edit_device2";
   }

   FRITZBOX_Log $hash, 4, "set $name $action " . join(" ", @webCmdArray);

   my $result = FRITZBOX_call_LuaData($hash, "data", \@webCmdArray) ;

   if ($action =~ /chgProf|lockLandevice/) {
     return $result;
   }

   if (defined $result->{Error} ) {
     return "ERROR: " . $result->{Error};
   } elsif (defined $result->{AuthorizationRequired}){
     return "ERROR: " . $result->{AuthorizationRequired};
   }

   if (exists $result->{data}->{vars}) {

     if($result->{data}->{vars}->{dev}->{UID} eq $lDevID) {

       my $returnStr  = "";

       $returnStr .= "MAC:"       . $result->{data}->{vars}->{dev}->{mac};
       $returnStr .= " IPv4:"     . $result->{data}->{vars}->{dev}->{ipv4}->{current}->{ip};
       $returnStr .= " UID:"      . $result->{data}->{vars}->{dev}->{UID};
       $returnStr .= " NAME:"     . $result->{data}->{vars}->{dev}->{name}->{displayName};
       if ( ref ($result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}) eq 'HASH' ) {
         my $kisi = $result->{data}->{vars}->{dev}->{netAccess}->{kisi};
#             $returnStr .= " ACCESS:"  . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid} if defined($result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{selectedRights}->{msgid});
#             $returnStr .= " USEABLE:" . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{onlineTime}->{useable};
#             $returnStr .= " UNSPENT:" . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{onlineTime}->{unspent};
#             $returnStr .= " PERCENT:" . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{onlineTime}->{percent};
#             $returnStr .= " USED:"    . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{onlineTime}->{used};
#             $returnStr .= " USEDSTR:" . $result->{data}->{vars}->{dev}->{netAccess}->{kisi}->{onlineTime}->{usedstr};
         $returnStr .= " ACCESS:"  . $kisi->{selectedRights}->{msgid} if defined($kisi->{selectedRights}->{msgid});
         $returnStr .= " USEABLE:" . $kisi->{onlineTime}->{useable} if defined($kisi->{onlineTime}->{useable});
         $returnStr .= " UNSPENT:" . $kisi->{onlineTime}->{unspent} if defined($kisi->{onlineTime}->{unspent});
         $returnStr .= " PERCENT:" . $kisi->{onlineTime}->{percent} if defined($kisi->{onlineTime}->{percent});
         $returnStr .= " USED:"    . $kisi->{onlineTime}->{used}    if defined($kisi->{onlineTime}->{used});
         $returnStr .= " USEDSTR:" . $kisi->{onlineTime}->{usedstr} if defined($kisi->{onlineTime}->{usedstr});
       }

       $returnStr .= " DEVTYPE:"  . $result->{data}->{vars}->{dev}->{devType};
       $returnStr .= " STATE:"    . $result->{data}->{vars}->{dev}->{wlan}->{state} if defined($result->{data}->{vars}->{dev}->{wlan}->{state}) and $result->{data}->{vars}->{dev}->{devType} eq 'wlan';
       $returnStr .= " ONLINE:"   . $result->{data}->{vars}->{dev}->{state};
       $returnStr .= " REALTIME:" . $result->{data}->{vars}->{dev}->{realtime}->{state} if defined($result->{data}->{vars}->{dev}->{realtime}->{state});

       return $returnStr;

     } else {
        return "ERROR: no lanDeviceInfo: " . $lDevID;
     }

   } else {
     FRITZBOX_Log $hash, 2, "landevice: " . $lDevID . "landevice: Fehler holen Lan_Device_Info";

     return "ERROR: Lan_Device_Info: " . $action . ": " . $lDevID;
   }

} # end FRITZBOX_Get_Lan_Device_Info

# get info for restrinctions for kids
############################################
sub FRITZBOX_Get_Lua_Kids($$@)
{
   my ($hash, $queryStr, $charSet) = @_;
   $charSet   = "" unless defined $charSet;
   my $name   = $hash->{NAME};
   my $sidNew = 0;

   my $result = FRITZBOX_open_Web_Connection( $hash );

   return $result unless $result->{sid};

   $sidNew = $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Log $hash, 4, "Request data via API dataQuery.";
   my $host = $hash->{HOST};
   my $url = 'http://' . $host . '/internet/kids_userlist.lua?sid=' . $result->{sid}; # . '&' . $queryStr;

   FRITZBOX_Log $hash, 4, "URL: $url";

   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => $hash->{AGENTTMOUT});
   my $response = $agent->post ( $url, $queryStr );

   FRITZBOX_Log $hash, 5, "Response: ".$response->status_line."\n".$response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 2, "".$response->status_line;
      return \%retHash;
   }

   my $jsonText = $response->content;

   if ($jsonText =~ /<html>|"pid": "logout"/) {
      FRITZBOX_Log $hash, 2, "Old SID not valid anymore. ResetSID";
      my %retHash = ("Error" => "Old SID not valid anymore.", "ResetSID" => "1");
      return \%retHash;
   }

   # Remove illegal escape sequences
   $jsonText =~ s/\\'/'/g; #Hochkomma
   $jsonText =~ s/\\x\{[0-9a-f]\}//g; #delete control codes (as hex numbers)

   FRITZBOX_Log $hash, 4, "Decode JSON string.";
   my $jsonResult ;
   if ($charSet eq "UTF-8") {
      $jsonResult = JSON->new->utf8->decode( $jsonText );
   }
   else {
      $jsonResult = JSON->new->latin1->decode( $jsonText );
   }

   if ( ref ($jsonResult) ne "HASH" ) {
      chop($jsonText);
      FRITZBOX_Log $hash, 4, "no json string returned (" . $jsonText . ")";
      my %retHash = ("Error" => "no json string returned (" . $jsonText . ")", "ResetSID" => "1");
      return \%retHash;
   }

   $jsonResult->{sid}    = $result->{sid};
   $jsonResult->{sidNew} = $sidNew;
   $jsonResult->{Error}  = $jsonResult->{error}  if defined $jsonResult->{error};
   return $jsonResult;

} # end FRITZBOX_Get_Lua_Kids

# Execute a Command via SOAP Request
#################################################
sub FRITZBOX_SOAP_Request($$$$)
{
   my ($hash,$control_url,$service_type,$service_command) = @_;

   my $name = $hash->{NAME};
   my $port = $hash->{SECPORT};

   my %retHash;

   unless ($port) {
     FRITZBOX_Log $hash, 2, "TR064 not used. No security port defined.";
     %retHash = ( "Error" => "TR064 not used. No security port defined", "ErrLevel" => "1" ) ;
     return \%retHash;
   }

   # disable SSL checks. No signed certificate!
   $ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
   $ENV{HTTPS_DEBUG} = 1;
 
   # Discover Service Parameters
   my $ua = new LWP::UserAgent;
   $ua->default_headers;
   $ua->ssl_opts( verify_hostname => 0 ,SSL_verify_mode => 0x00);
 
   my $host = $hash->{HOST};
   
   my $connectionStatus;

   # Prepare request for query LAN host
   $ua->default_header( 'SOAPACTION' => "$service_type#$service_command" );

   my $init_request = <<EOD;
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" >
                <s:Header>
                </s:Header>
                <s:Body>
                        <u:$service_command xmlns:u="$service_type">
                        </u:$service_command>
                </s:Body>
        </s:Envelope>
EOD

   # http port:49000
   # my $init_url = "http://$host:49000/$control_url";

   my $init_url = "https://$host:$port/$control_url";
   my $resp_init = $ua->post($init_url, Content_Type => 'text/xml; charset=utf-8', Content => $init_request);

   # Check the outcome of the response
   unless ($resp_init->is_success) {
     FRITZBOX_Log $hash, 4, "SOAP response error: " . $resp_init->status_line;
     %retHash = ( "Error" => "SOAP response error: " . $resp_init->status_line, "ErrLevel" => "1" ) ;
     return \%retHash;
   }

   unless( $resp_init->decoded_content ) {
     FRITZBOX_Log $hash, 4, "SOAP response error: " . $resp_init->status_line;
     %retHash = ( "Error" => "SOAP response error: " . $resp_init->status_line, "ErrLevel" => "1" ) ;
     return \%retHash;
   }

   if (ref($resp_init->decoded_content) eq "HASH") {
     FRITZBOX_Log $hash, 4, "XML_RESONSE:\n" . Dumper ($resp_init->decoded_content);
     %retHash = ( "Info" => "SOAP response: " . $resp_init->status_line, "Response" => Dumper ($resp_init->decoded_content) ) ;
   } elsif (ref($resp_init->decoded_content) eq "ARRAY") {
     FRITZBOX_Log $hash, 4, "XML_RESONSE:\n" . Dumper ($resp_init->decoded_content);
     %retHash = ( "Info" => "SOAP response: " . $resp_init->status_line, "Response" => Dumper ($resp_init->decoded_content) ) ;
   } else {
     FRITZBOX_Log $hash, 4, "XML_RESONSE:\n" . $resp_init->decoded_content;
     %retHash = ( "Info" => "SOAP response: " . $resp_init->status_line, "Response" => $resp_init->decoded_content) ;
   }

#<?xml version="1.0"?>
#  <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
#    <s:Body>
#      <s:Fault>
#      <faultcode>s:Client</faultcode>
#      <faultstring>UPnPError</faultstring>
#      <detail>
#        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
#          <errorCode>401</errorCode>
#          <errorDescription>Invalid Action</errorDescription>
#        </UPnPError>
#      </detail>
#    </s:Fault>
#  </s:Body>
#</s:Envelope>

   my $sFault = \%retHash;

   if($sFault =~ m/<s:Fault>(.*?)<\/s:Fault>/i) {
     my $sFaultDetail = $1;
     if($sFaultDetail =~ m/<errorCode>(.*?)<\/errorCode>/i) {
       my $errInfo = "Code: $1";
       if($sFaultDetail =~ m/<errorDescription>(.*?)<\/errorDescription>/i) {
         $errInfo .= " Text: $1";
       }
       FRITZBOX_Log $hash, 4, "SOAP response error: " . $errInfo;
       %retHash = ( "Error" => "SOAP response error: " . $errInfo, "ErrLevel" => "1" );
     } else {
       FRITZBOX_Log $hash, 4, "SOAP response error: " . $sFaultDetail;
       %retHash = ( "Error" => "SOAP response error: " . $sFaultDetail, "ErrLevel" => "1" );
     }
   }

   return \%retHash;

} # end of FRITZBOX_SOAP_Request

# Execute a Command via SOAP Request
# {FRITZBOX_SOAP_Test_Request("FritzBox", "igdupnp\/control\/WANIPConn1", "urn:schemas-upnp-org:service:WANIPConnection:1", "GetStatusInfo")}
#################################################
sub FRITZBOX_SOAP_Test_Request($$$$)
{
   my ($box,$control_url,$service_type,$service_command) = @_;
   my $hash = $defs{$box};

   use Data::Dumper;

   return Dumper (FRITZBOX_SOAP_Request($hash, $control_url, $service_type, $service_command));

} # end of FRITZBOX_SOAP_Test_Request

# Execute a Command via TR-064
#################################################
sub FRITZBOX_call_TR064_Cmd($$$)
{
   my ($hash, $xml, $cmdArray) = @_;

   my $name = $hash->{NAME};
   my $port = $hash->{SECPORT};

   unless ($port) {
      FRITZBOX_Log $hash, 2, "TR064 not used. No security port defined.";
      return undef;
   }

# Set Password und User for TR064 access
   $FRITZBOX_TR064pwd = FRITZBOX_Helper_read_Password($hash) unless defined $FRITZBOX_TR064pwd;
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
      foreach (sort keys %params) {
         $logMsg .= ", parameter" . (int(@soapParams)+1) . "='$_' => '$params{$_}'" ;
         push @soapParams, SOAP::Data->name( $_ => $params{$_} );
      }

      FRITZBOX_Log $hash, 4, "Perform TR-064 call - $action => " . $logMsg;

      my $soap = SOAP::Lite
         -> on_fault ( sub {} )
         -> uri( "urn:dslforum-org:service:".$service )
         -> proxy('https://'.$host.":".$port."/upnp/control/".$control, ssl_opts => [ SSL_verify_mode => 0 ], timeout => 10  )
         -> readable(1);

      my $res = eval { $soap -> call( $action => @soapParams )};

      if ($@) {
        FRITZBOX_Log $hash, 2, "TR064-PARAM-Error: " . $@;
        my %errorMsg = ( "Error" => $@ );
        push @retArray, \%errorMsg;
        $FRITZBOX_TR064pwd = undef;

      } else {

        unless( $res ) { # Transport-Error
          FRITZBOX_Log $hash, 4, "TR064-Transport-Error: ".$soap->transport->status;
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

          FRITZBOX_Log $hash, 4, "TR064 error $ecode:$edesc ($logMsg)";

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
   }

   @{$cmdArray} = ();
   return @retArray;

} # end of FRITZBOX_call_TR064_Cmd

# get Fritzbox tr064ServiceList
#################################################
sub FRITZBOX_get_TR064_ServiceList($)
{
   my ($hash) = @_;
   my $name = $defs{NAME};


   if ( $missingModul ) {
      my $msg = "ERROR: Perl modul " . $missingModul . " is missing on this system. Please install before using this modul.";
      FRITZBOX_Log $hash, 2, $msg;
      return $msg;
   }

   my $host = $hash->{HOST};
   my $url = 'http://'.$host.":49000/tr64desc.xml";

   my $returnStr = "_" x 130 ."\n\n";
   $returnStr .= " List of TR-064 services and actions that are provided by the device '$host'\n";

   return "TR-064 switched off."     if $hash->{READINGS}{box_tr064}{VAL} eq "off";

   FRITZBOX_Log $hash, 4, "Getting service page $url";
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

} # end FRITZBOX_get_TR064_ServiceList

#######################################################################
sub FRITZBOX_init_TR064 ($$)
{
   my ($hash, $host) = @_;
   my $name = $hash->{NAME};

   if ($missingModul) {
      FRITZBOX_Log $hash, 2,  "ERROR: Cannot use TR-064. Perl modul " . $missingModul . " is missing on this system. Please install.";
      return undef;
   }

# Security Port anfordern
   FRITZBOX_Log $hash, 4, "Open TR-064 connection and ask for security port";
   my $s = SOAP::Lite
      -> uri('urn:dslforum-org:service:DeviceInfo:1')
      -> proxy('http://' . $host . ':49000/upnp/control/deviceinfo', timeout => 10 )
      -> getSecurityPort();

   FRITZBOX_Log $hash, 5, "SecPort-String " . Dumper($s);

   my $port = $s->result;
   FRITZBOX_Log $hash, 5, "SecPort-Result " . Dumper($s->result);

   unless( $port ) {
      FRITZBOX_Log $hash, 2, "Could not get secure port: $!";
      return undef;
   }

#   $hash->{TR064USER} = "dslf-config";

   # jetzt die ZertifikatsÃ¼berprÃ¼fung (sofort) abschalten
   BEGIN {
      $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
   }

   # dieser Code authentifiziert an der Box
   sub SOAP::Transport::HTTP::Client::get_basic_credentials {return  $FRITZBOX_TR064user => $FRITZBOX_TR064pwd;}

   return $port;

} # end FRITZBOX_init_TR064

# Opens a Web connection to an external Fritzbox
############################################
sub FRITZBOX_open_Web_Connection ($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my %retHash;

   if ($missingModul) {
      FRITZBOX_Log $hash, 2, "Perl modul ".$missingModul." is missing on this system. Please install before using this modul.";
      %retHash = ( "Error" => "missing Perl module", "ResetSID" => "1" ) ;
      return \%retHash;
   }

   if( $hash->{fhem}{sidErrCount} && $hash->{fhem}{sidErrCount} >= AttrVal($name, "maxSIDrenewErrCnt", 5) ) {
      FRITZBOX_Log $hash, 2, "too many login attempts: " . $hash->{fhem}{sidErrCount};
      %retHash = ( "Error" => "too many login attempts: " . $hash->{fhem}{sidErrCount}, "ResetSID" => "1" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 4, "checking HOST -> " . $hash->{DEF} if defined $hash->{DEF};

   # my $hash = $defs{$name};
   my $host = $hash->{HOST};

   my $URL_MATCH = FRITZBOX_Helper_Url_Regex();

   if (defined $hash->{DEF} && $hash->{DEF} !~ m=$URL_MATCH=i) {

     my $phost = inet_aton($hash->{DEF});
     if (! defined($phost)) {
       FRITZBOX_Log $hash, 2, "phost -> not defined";
       %retHash = ( "Error" => "Device is offline", "ResetSID" => "1" ) ;
       return \%retHash  if !AttrVal($name, "disableHostIPv4check", 0);
     }

     my $host = inet_ntoa($phost);

     if (! defined($host)) {
       FRITZBOX_Log $hash, 2, "host -> $host";
       %retHash = ( "Error" => "Device is offline", "ResetSID" => "1" ) ;
       return \%retHash  if !AttrVal($name, "disableHostIPv4check", 0);
     }
     $hash->{HOST} = $host;
   }

   my $p = Net::Ping->new;
   my $isAlive = $p->ping($host);
   $p->close;

   if (!$isAlive) {
     FRITZBOX_Log $hash, 4, "Host $host not available";
     %retHash = ( "Error" => "Device is offline", "ResetSID" => "1" ) ;
     return \%retHash  if !AttrVal($name, "disableHostIPv4check", 0);
   }

# Use old sid if last access later than 9.5 minutes
   my $sid = $hash->{fhem}{sid};

   if (defined $sid && $hash->{fhem}{sidTime} > time() - 9.5 * 60) {
      FRITZBOX_Log $hash, 4, "using old SID from " . strftime "%H:%M:%S", localtime($hash->{fhem}{sidTime});
      %retHash = ( "sid" => $sid, "ResetSID" => "0" ) ;
      return \%retHash;

   } else {
      my $msg;
      $msg .= "SID: " if defined $sid ? $sid : "no SID";
      $msg .= " timed out" if defined $hash->{fhem}{sidTime} && $hash->{fhem}{sidTime} < time() - 9.5 * 60;
      FRITZBOX_Log $hash, 4, "renewing SID while: " . $msg;
   }

   my $avmModel = InternalVal($name, "MODEL", $hash->{boxModel});
   my $user = AttrVal( $name, "boxUser", "" );

   FRITZBOX_Log $hash, 4, "FRITZBOX_Get_Lan_Device_Info (Fritz!OS: $hash->{fhem}{fwVersionStr}) ";

   if ($user eq "" && $avmModel && $avmModel =~ "Box" && ($hash->{fhem}{fwVersion} >= 725) ) {
      FRITZBOX_Log $hash, 2, "No boxUser set. Please define it (once) with 'attr $name boxUser YourBoxUser'";
      %retHash = ( "Error" => "No attr boxUser set", "ResetSID" => "1" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 4, "Open Web connection to $host:" . $user ne "" ? $user : "user not defined";
   $FRITZBOX_TR064pwd = FRITZBOX_Helper_read_Password($hash);
   unless (defined $FRITZBOX_TR064pwd) {
      FRITZBOX_Log $hash, 2, "No password set. Please define it (once) with 'set $name password YourPassword'";
      %retHash = ( "Error" => "No password set", "ResetSID" => "1" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 4, "getting new SID";
   $sid = (FB_doCheckPW($host, $user, $FRITZBOX_TR064pwd));

   $FRITZBOX_TR064pwd = undef;

   if ($sid) {
      FRITZBOX_Log $hash, 4, "Web session opened with sid $sid";
      %retHash = ( "sid" => $sid, "sidNew" => 1, "ResetSID" => "0" ) ;
      return \%retHash;
   }

   FRITZBOX_Log $hash, 2, "Web connection could not be established. Please check your credentials (password, user).";

   %retHash = ( "Error" => "Web connection could not be established", "ResetSID" => "1" ) ;
   return \%retHash;

} # end FRITZBOX_open_Web_Connection


# Read box values via the web connection
############################################
sub FRITZBOX_call_Lua_Query($$@)
{
   my ($hash, $queryStr, $charSet, $f_lua) = @_;

   $charSet   = "" unless defined $charSet;
   $f_lua     = "luaQuery" unless defined $f_lua;
   my $name   = $hash->{NAME};
   my $sidNew = 0;

   my $result = FRITZBOX_open_Web_Connection( $hash );

   return $result unless $result->{sid};

   $sidNew = $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Log $hash, 4, "Request data via API " . $f_lua;
   my $host = $hash->{HOST};
   my $url = 'http://' . $host;

   if ( $f_lua eq "luaQuery") {
     $url .= '/query.lua?sid=' . $result->{sid} . $queryStr;
   } elsif ( $f_lua eq "luaCall") {
     $url .= '/' . $queryStr;
     $url .= '?sid=' . $result->{sid} if $queryStr ne "login_sid.lua";
   } else {
     FRITZBOX_Log $hash, 2, "Wrong function name. function_name: " . $f_lua;
     my %retHash = ( "Error" => "Wrong function name", "function_name" => $f_lua ) ;
     return \%retHash;
   }

   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => $hash->{AGENTTMOUT});
   my $response;

   FRITZBOX_Log $hash, 4, "get -> URL: $url";

   $response = $agent->get ( $url );

   FRITZBOX_Log $hash, 5, "Response: " . $response->status_line . "\n" . $response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 2, "" . $response->status_line;
      return \%retHash;
   }

#################
#     FRITZBOX_Log $hash, 5, "Response: " . $response->content;
#################

   my $jsonResult ;

   if ( $f_lua ne "luaCall") {

     return FRITZBOX_Helper_process_JSON($hash, $response->content, $result->{sid}, $charSet, $sidNew);

   } else {
     $jsonResult->{sid}     = $result->{sid};
     $jsonResult->{sidNew}  = $sidNew;
     $jsonResult->{result}  = $response->status_line  if defined $response->status_line;
     $jsonResult->{result} .= ", " . $response->content  if defined $response->content;
   }

   return $jsonResult;

} # end FRITZBOX_call_Lua_Query

# Read/write box values via the web connection
############################################
sub FRITZBOX_call_LuaData($$$@)
{
   my ($hash, $luaFunction, $queryArray, $charSet) = @_;

   $charSet   = "" unless defined $charSet;
   my $name   = $hash->{NAME};
   my $sidNew = 0;
   my $queryStr = join (' ', @$queryArray);

   if ($hash->{LUADATA} <= 0) {
      my %retHash = ( "Error" => "data.lua not supportet", "Info" => "Fritz!Box or Fritz!OS outdated" ) ;
      FRITZBOX_Log $hash, 2, "data.lua not supportet. Fritz!Box or Fritz!OS outdated.";
      return \%retHash;
   }

   my $result = FRITZBOX_open_Web_Connection( $hash );

   return $result unless $result->{sid};

   $sidNew = $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Log $hash, 4, "Request data via API dataQuery.";
   my $host = $hash->{HOST};
   my $url = 'http://' . $host . '/' . $luaFunction . '.lua?sid=' . $result->{sid};

   FRITZBOX_Log $hash, 4, "URL: $url";

   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => $hash->{AGENTTMOUT});
   my $response = $agent->post ( $url, $queryArray );

   FRITZBOX_Log $hash, 4, "Response: " . $response->status_line . "\n" . $response->content;

   unless ($response->is_success) {
      my %retHash = ("Error" => $response->status_line, "ResetSID" => "1");
      FRITZBOX_Log $hash, 4, "\n" . $response->status_line;
      return \%retHash;
   }

   my $data = $response->content;

   # handling profile informations
   ###########  HTML #################################
   # data: <input type="hidden" name="back_to_page" value="/internet/kids_profilelist.lua">

   if ( $data =~ m/\<input type="hidden" name="back_to_page" value="\/internet\/kids_profilelist.lua"\>(.*?)\<\/script\>/igs ) {

     FRITZBOX_Log $hash, 5, "Response Data: \n" . $1;

     my $profile_content;
     $profile_content = $1;

     my $profileStatus = $profile_content =~ m/checked id="uiTime:(.*?)"/igs? $1 : "";

     my $bpjmStatus = $profile_content =~ m/type="checkbox" name="bpjm" checked/igs? "on" : "off";

     my $inetStatus = $profile_content =~ m/id="uiBlack"  checked/igs? "black" : "white";

     my $disallowGuest = $profile_content =~ m/name="disallow_guest" checked/igs? "on" : "";

     $profile_content  = '{"pid":"Profile","data":{';
     $profile_content .= '"profileStatus":"' . $profileStatus . '",';
     $profile_content .= '"bpjmStatus":"' . $bpjmStatus . '",';
     $profile_content .= '"inetStatus":"' . $inetStatus . '",';
     $profile_content .= '"disallowGuest":"' . $disallowGuest . '"';
     $profile_content .= '},"sid":"' . $result->{sid} . '"}';

     FRITZBOX_Log $hash, 5, "Response 1: " . $profile_content;

     return FRITZBOX_Helper_process_JSON($hash, $profile_content, $result->{sid}, $charSet, $sidNew);

   }

   # handling for Smart Home Devices: 
   ###########  HTML #################################
   # xhr 1 lang de page sh_dev xhrId all
   # xhr 1 master 17 device 17 page home_auto_edit_view

   if ($queryStr =~ /home_auto_edit_view/) {

     my $profile_content;

     if ( $data =~ m/\<h4\>Smart-Home.*?\<\/h4\>\<div class="formular widetext"\>(.*?)\<div id="btn_form_foot"\>/igs ) {

       FRITZBOX_Log $hash, 5, "Response Data: \n" . $1;

       my $tmp = "";
       my $smartCont = $1;

       $profile_content = '{"sid":"'.$result->{sid}.'","pid":"SmartHomeDevice","data":{"smartoptions":{';

       ($tmp) = ($smartCont =~ m/name="ule_device_name" id="uiULEDeviceName" maxlength="[\d]+" value="(.*?)"\>\<\/div\>\<div class="formular widetext"\>/igs);
       $profile_content .= '"ule_device_name":"' . $tmp . '",';

       ($tmp) = ($smartCont =~ m/"uiView_SwitchDefaultState_Last" value="(.*?)" name="switch_default_state"\>/igs);
       $profile_content .= '"switch_default_state":' . $tmp . ',' if $tmp;

       ($tmp) = ($smartCont =~ m/name="ule_device_acdc_rate" value="([\d]+,[\d]+)" id/igs);
       $profile_content .= '"ule_device_acdc_rate":"' . $tmp . '",' if $tmp;

       ($tmp) = ($smartCont =~ m/name="ule_device_co2_emission" value="([\d]+,[\d]+)" id/igs);
       $profile_content .= '"ule_device_co2_emission":"' . $tmp . '",' if $tmp;

       ($tmp) = ($smartCont =~ m/checked id="uiView_LEDActive" value="(\d)" name/igs);
       # $profile_content .= '"led_active":' . $tmp . ',' if $tmp;
       $profile_content .= ($tmp ? '"led_active":1' : '"led_active":0') . ',' ;

       ($tmp) = ($smartCont =~ m/checked id="uiView_ManuellSwitchActiveLocal" value="(\d)" name/igs);
       # $profile_content .= '"manuell_switch_active_local":' . $tmp . ',' if $tmp;
       $profile_content .= ($tmp ? '"manuell_switch_active_local":1' : '"manuell_switch_active_local":0') . ',' ;

       ($tmp) = ($smartCont =~ m/checked id="uiView_ManuellSwitchActiveUIApp" value="(\d)" name/igs);
       # $profile_content .= '"manuell_switch_active_uiapp":' . $tmp . ',' if $tmp;
       $profile_content .= ($tmp ? '"manuell_switch_active_uiapp":1' : '"manuell_switch_active_uiapp":0') . ',' ;

       ($tmp) = ($smartCont =~ m/name="Offset" value="([\d]+\.[\d]+)">/igs);
       $profile_content .= '"Offset":' . $tmp . ',' if $tmp;

       ($tmp) = ($smartCont =~ m/id="uiEnabled" type="checkbox" name="enabled" (checked)\>/igs);
       $profile_content .= '"enabled":"on",' if $tmp;

       ($tmp) = ($smartCont =~ m/\<input id="uiPeriodic" type="checkbox" name="periodic" (checked)\>/igs);
       $profile_content .= '"periodic":"on",' if $tmp;

       ($tmp) = ($smartCont =~ m/\<input type="radio" checked value="(.*?)" id="uiInterval/igs);
       $profile_content .= '"interval":"' .$tmp . '",' if $tmp;

       ($tmp) = ($smartCont =~ m/type="radio" checked value="(24h|week|month|year)"/igs);
       $profile_content .= '"ShowEnergyStat":"' . $tmp . '",' if $tmp;

       ($tmp) = ($smartCont =~ m/name="mail_type"\>\<option value="default" (selected)\>/igs);
       $profile_content .= '"mail_type":"default",' if $tmp;

       ($tmp) = ($smartCont =~ m/name="mail_type"\>\<option value="default"\>.*?value="custom" (selected)\>/igs);
       $profile_content .= '"mail_type":"custom",' if $tmp;

       ($tmp) = ($smartCont =~ m/name="mailto" value="(.*?)"\>/igs);
       $profile_content .= '"mailto":"' . $tmp . '",' if $tmp;

       chop($profile_content);
       $profile_content .= '}}}';

       FRITZBOX_Log $hash, 4, "Response JSON: \n" . $profile_content;

       return FRITZBOX_Helper_process_JSON($hash, $profile_content, $result->{sid}, $charSet, $sidNew);

     } else {

       return FRITZBOX_Helper_process_JSON($hash, $response->content, $result->{sid}, $charSet, $sidNew);

     }
   }


   # handling for getting disabled incomming numbers
   ###########  HTML #################################
   # data: [{"numberstring":"030499189721","uid":128,"name":"030499189721","typeSuffix":"_entry","numbers":[{"number":"030499189721","type":"privat"}]},{"numberstring":"02234983525","uid":137,"name":"Testsperre","typeSuffix":"_entry","numbers":[{"number":"02234983525","type":"privat"}]}]};

   if ( $data =~ m/"uiBookblockContainer",.*?"uiBookblock",(.*?)const bookBlockTable = initTable\(bookBlockParams\);/igs ) {

      FRITZBOX_Log $hash, 5, "Response Data: \n" . $1;

      my $profile_content;

      $profile_content = $1;

      $profile_content =~ s/\n//;

      chop($profile_content);
      chop($profile_content);

      $profile_content =~ s/data/"data"/;

      $profile_content = '{"sid":"' . $result->{sid} . '","pid":"fonDevice",' . $profile_content;

      FRITZBOX_Log $hash, 5, "Response JSON: " . $profile_content;

      return FRITZBOX_Helper_process_JSON($hash, $profile_content, $result->{sid}, $charSet, $sidNew);
   }

   # handling for getting wakeUpCall Informations
   ###########  HTML #################################

   if ( $data =~ m/\<select size="1" id="uiViewDevice" name="device"\>(.*?)\<\/select\>/igs ) {
      FRITZBOX_Log $hash, 4, "Response : \n" . $data;
      my $profile_content;
      $profile_content = '{"sid":"'.$result->{sid}.'","pid":"fonDevice","data":{"phonoptions":[';

      my $mLine = $1;

      FRITZBOX_Log $hash, 5, "Response 1: \n" . $mLine;

      my $count = 0;

      foreach my $line ($mLine =~ m/\<option(.*?\<)\/option\>/igs) {
        FRITZBOX_Log $hash, 4, "Response 2: " . $line;

        if ($line =~ m/value="(.*?)".*?\>(.*?)\</igs) {
          FRITZBOX_Log $hash, 4, "Profile name: " . $1 . " Profile Id: " . $2;
          $profile_content .= '{"text":"' . $2 . '","value":"' .$1 . '"},';
        }
        $count ++;
      }

      $profile_content = substr($profile_content, 0, length($profile_content)-1);
 
      $profile_content .= ']}}';
 
      FRITZBOX_Log $hash, 5, "Response JSON: " . $profile_content;

      return FRITZBOX_Helper_process_JSON($hash, $profile_content, $result->{sid}, $charSet, $sidNew);
   }

   # handling for getting profile Informations
   ###########  HTML #################################

   my $pattern_tr = '\<tr\>\<td(.*?)\<\/td\>\<\/tr\>';

   my $pattern_vl = 'class="name".title="(.*?)".datalabel=.*?\<button.type="submit".name="edit".value="(.*?)".class="icon.edit".title="';

   if ( $data =~ m/\<table id="uiProfileList"(.*?)\<\/table\>/is ) {
     my $profile_content;
     $profile_content = '{"pid":"kidProfile","data":{"kidProfiles":{';

     FRITZBOX_Log $hash, 5, "Response 1: " . $1;

     my $count = 0;

     foreach my $line ($data =~ m/$pattern_tr/gs) {
       FRITZBOX_Log $hash, 5, "Response 2: " . $line;

       if ($line =~ m/$pattern_vl/gs) {
         FRITZBOX_Log $hash, 4, "Profile name: " . $1 . " Profile Id: " . $2;
         $profile_content .= '"profile' . $count . '":{"Id":"' .$2 . '","Name":"' . $1 . '"},';
       }
       $count ++;

     }

     $profile_content = substr($profile_content, 0, length($profile_content)-1);

     $profile_content .= '}},"sid":"' . $result->{sid} . '"}';

     FRITZBOX_Log $hash, 5, "Response 1: " . $profile_content;

     return FRITZBOX_Helper_process_JSON($hash, $profile_content, $result->{sid}, $charSet, $sidNew);
   }

   return FRITZBOX_Helper_process_JSON($hash, $response->content, $result->{sid}, $charSet, $sidNew);

} # end FRITZBOX_Lua_Data


# write box values via javascript functions
# landevice/landevice/landevice7721 {device_class_user: "Generic", friendly_name: "Brennen-01", rrd: "0"}
# user/user/FhemUser                {filter_profile_UID: "filtprof1", disallowed: "0"}
# reload 72_FRITZBOX.pm

# {FRITZBOX_write_javaScript($defs{FritzBox},"user/user", '{"filter_profile_UID":"filtprof1","landeviceUID":"landevice1805","disallowed":"1","type":"1"}', "post")}

# {FRITZBOX_write_javaScript($defs{FritzBox},"trafficprio/user", '{"ip":"192.168.0.37", "mac":"88:71:E5:0E:38:98","type":"1"}', "post")}

# {FRITZBOX_write_javaScript($defs{FritzBox},"landevice/landevice/landevice1805", '{"device_class_user":"Generic","friendly_name":"amazon-echo","rrd":"0"}', "put")}
# {FRITZBOX_write_javaScript($defs{FritzBox},"user/user/user8564", '{"filter_profile_UID":"filtprof1","disallowed:"0"}', "put")}


############################################
sub FRITZBOX_write_javaScript($$;@)
{
   my ($hash, $javaScript, $chgStr, $methode, $charSet) = @_;

   $charSet        = "utf-8" unless defined $charSet;
   my $name        = $hash->{NAME};
   my $sidNew      = 0;

   my $result = FRITZBOX_open_Web_Connection( $hash );

   return $result unless $result->{sid};

   $sidNew = $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Log $hash, 4, "Request data via API javaScript: $chgStr";
   my $host = $hash->{HOST};

   my $url = 'http://' . $host . '/api/v0/' . $javaScript;
   my $Authorisation = 'AVM-SID ' . $result->{sid};

   FRITZBOX_Log $hash, 4, "URL: $url";

   my $string_len = length($chgStr);
   my $agent    = LWP::UserAgent->new;
   my $response;

   if ($methode eq "put") {
     $response = $agent->put( 
        $url,
        Authorization          => $Authorisation, 
        Content                => $chgStr,
        'cache-control'        => 'no-cache',
        'content-type'         => 'application/json; charset=' . $charSet,
        'expires'              => '-1',
        'keep-alive'           => 'timeout=60, max=300',
        'pragma'               => 'no-cache',
     );
   } elsif ($methode eq "post") {
     $response = $agent->post( 
        $url,
        Authorization          => $Authorisation, 
        Content                => $chgStr,
        'cache-control'        => 'no-cache',
        'content-type'         => 'application/json; charset=' . $charSet,
        'expires'              => '-1',
        'keep-alive'           => 'timeout=60, max=300',
        'pragma'               => 'no-cache',
     );
   } elsif ($methode eq "delete") {
     $response = $agent->delete( 
        $url,
        Authorization          => $Authorisation, 
        'cache-control'        => 'no-cache',
        'content-type'         => 'application/json; charset=' . $charSet,
        'expires'              => '-1',
        'keep-alive'           => 'timeout=60, max=300',
        'pragma'               => 'no-cache',
     );
   }

   FRITZBOX_Log $hash, 4, "Response: " . $response->{_content} if $response->{_content};

   unless ($response->{_msg} && $response->{_msg} eq "OK") {
      my %retHash = ("Error" => $response->{_msg}, "ResetSID" => "1");
      FRITZBOX_Log $hash, 2, "Device $string_len\n" . $response->{_msg};
      return \%retHash;
#      return Dumper ($response);
   }

   my $data = $response->{_content};

   return FRITZBOX_Helper_process_JSON($hash, $data, $result->{sid}, $charSet, $sidNew, 1);

} # end FRITZBOX_write_javaScript

# Read box values via javascript functions
############################################
sub FRITZBOX_call_javaScript($$@)
{
   my ($hash, $javaScript, $charSet) = @_;

   $charSet   = "utf-8" unless defined $charSet;
   my $name   = $hash->{NAME};
   my $sidNew = 0;

   my $result = FRITZBOX_open_Web_Connection( $hash );

   return $result unless $result->{sid};

   $sidNew = $result->{sidNew} if defined $result->{sidNew};

   FRITZBOX_Log $hash, 4, "Request data via API javaScript.";
   my $host = $hash->{HOST};
   my $url = 'http://' . $host . '/api/v0/' . $javaScript;

   FRITZBOX_Log $hash, 4, "URL: $url";

   my $agent    = LWP::UserAgent->new;
   my $response = $agent->get( 
      $url,
      "Authorization"          => "AVM-SID " . $result->{sid}, 
      "cache-control"          => "no-cache",
      "content-type"           => "application/json; charset=" . $charSet,
      "expires"                => "-1",
      "keep-alive"             => "timeout=60, max=300",
      "pragma"                 => "no-cache",
   );

   FRITZBOX_Log $hash, 4, "Response: " . $response->{_content};

   unless ($response->{_msg} && $response->{_msg} eq "OK") {
      my %retHash = ("Error" => $response->{_msg}, "ResetSID" => "1");
      FRITZBOX_Log $hash, 4, "\n" . $response->{_msg};
      return \%retHash;
   }

   my $data = $response->{_content};

   return FRITZBOX_Helper_process_JSON($hash, $data, $result->{sid}, $charSet, $sidNew, 1);

} # end FRITZBOX_call_javaScript


##############################################################################################################################################
# Ab helfer Sub
##############################################################################################################################################

#######################################################################
sub FRITZBOX_ConvertMOH ($@)
{
   my ($hash, @file) = @_;

   my $name = $hash->{NAME};

   my $uploadDir = AttrVal( $name, "defaultUploadDir",  "" );
   $uploadDir .= "/" unless $uploadDir =~ /\/$|^$/;

   my $inFile = join " ", @file;
   $inFile = $uploadDir.$inFile unless $inFile =~ /^\//;

   return "Error: You have to give a complete file path or to set the attribute 'defaultUploadDir'"
      unless $inFile =~ /^\//;

   return "Error: only MP3 or WAV files can be converted"
      unless $inFile =~ /\.mp3$|.wav$/i;

   $inFile =~ s/file:\/\///;

   my $outFile = $inFile;
   $outFile = substr($inFile,0,-4) if ($inFile =~ /\.(mp3|wav)$/i);

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

   return undef;

} # end FRITZBOX_ConvertRingTone

# Process JSON from lua response
############################################
sub FRITZBOX_Helper_process_JSON($$$@) {

   my ($hash, $jsonText, $sid, $charSet, $sidNew, $fromJS) = @_;
   $charSet = "" unless defined $charSet;
   $sidNew  = 0 unless defined $sidNew;
   $fromJS  = 0 unless defined $fromJS;
   my $name = $hash->{NAME};

   if ($jsonText =~ /<html|"pid": "logout"|<head>/) {
      FRITZBOX_Log $hash, 4, "JSON: Old SID not valid anymore. ResetSID";
      my %retHash = ("Error" => "JSON: Old SID not valid anymore.", "ResetSID" => "1");
      return \%retHash;
   }

   # Remove illegal escape sequences
   $jsonText =~ s/\\'/'/g; #Hochkomma
   $jsonText =~ s/\\x\{[0-9a-f]\}//g; #delete control codes (as hex numbers)

   FRITZBOX_Log $hash, 4, "Decode JSON string:\n" . $jsonText;

   my $jsonResult ;
   if ($charSet eq "UTF-8") {
      $jsonResult = eval { JSON->new->utf8->decode( $jsonText ) };
      if ($@) {
        FRITZBOX_Log $hash, 3, "Decode JSON string: decode_json failed, invalid json. error:$@";
      }
   }
   else {
      $jsonResult = eval { JSON->new->latin1->decode( $jsonText ) };
      if ($@) {
        FRITZBOX_Log $hash, 3, "Decode JSON string: decode_json failed, invalid json. error:$@";
      }
   }

   FRITZBOX_Log $hash, 5, "JSON: " . Dumper($jsonResult);

   #Not a HASH reference at ./FHEM/72_FRITZBOX.pm line 4662.
   # 2018.03.19 18:43:28 3: FRITZBOX: get Fritzbox luaQuery settings/sip

   if ($fromJS == 1) {
     if ( ref ($jsonResult) ne "HASH" && ref ($jsonResult) ne "ARRAY") {
        chop($jsonText);
        FRITZBOX_Log $hash, 3, "no HASH/ARRAY from JSON returned\n (" . $jsonText . ")";
        my %retHash = ("Error" => "no HASH/ARRAY from JSON returned", "ResetSID" => "1");
        return \%retHash;
     }

     FRITZBOX_Log $hash, 4, "JSON: " . Dumper($jsonResult);

     if (ref ($jsonResult) eq "ARRAY") {
       FRITZBOX_Log $hash, 5, "JSON: is ARRAY";
       my %ReturnHash = (
           "sid"    => $sid,
           "sidNew" => $sidNew,
           "result" => $jsonResult
       );
       FRITZBOX_Log $hash, 5, "JSON =>result: " . Dumper(\%ReturnHash);
       return \%ReturnHash;

     } elsif (!defined $jsonResult->{data} && !defined $jsonResult->{result}) {
       FRITZBOX_Log $hash, 5, "JSON: no {data} or {result}";
       my %ReturnHash = (
           "sid"    => $sid,
           "sidNew" => $sidNew,
           "data"   => $jsonResult
       );
       FRITZBOX_Log $hash, 5, "JSON =>data: " . Dumper(\%ReturnHash);
       return \%ReturnHash;
     
     } else {
       FRITZBOX_Log $hash, 5, "JSON: Standard";
       $jsonResult->{sid}    = $sid;
       $jsonResult->{sidNew} = $sidNew;
       $jsonResult->{Error}  = $jsonResult->{error}  if defined $jsonResult->{error};

       return $jsonResult;
     }

   } else {
     if ( ref ($jsonResult) ne "HASH") {
        chop($jsonText);
        FRITZBOX_Log $hash, 3, "no HASH/ARRAY from JSON returned\n (" . $jsonText . ")";
        my %retHash = ("Error" => "no HASH/ARRAY from JSON returned", "ResetSID" => "1");
        return \%retHash;
     }

     $jsonResult->{sid}    = $sid;
     $jsonResult->{sidNew} = $sidNew;
     $jsonResult->{Error}  = $jsonResult->{error}  if defined $jsonResult->{error};

     return $jsonResult;
   }

} # end FRITZBOX_Helper_process_JSON

# create error response for lua return
############################################
sub FRITZBOX_Helper_analyse_Lua_Result($$;@)
{

   my ($hash, $result, $retData) = @_;
   $retData = 0 unless defined $retData;
   my $name = $hash->{NAME};

   my $tmp;

   if (defined $result->{Error} ) {
     return "ERROR: " . $result->{Error};
   } elsif (defined $result->{AuthorizationRequired}){
     return "ERROR: " . $result->{AuthorizationRequired};
   }

   if (defined $result->{ResetSID}) {
     if ($result->{ResetSID}) {
       $hash->{fhem}{sidErrCount} += 1;
       $hash->{SID_RENEW_ERR_CNT} += 1;
       $hash->{WEBCONNECT}  = 0;
     } else {
       $hash->{WEBCONNECT}  = 1;
     }
   }

   if (defined $result->{sid}) {

     $hash->{fhem}{sid}         = $result->{sid};
     $hash->{fhem}{sidTime}     = time();
     $hash->{fhem}{sidErrCount} = 0;
     $hash->{WEBCONNECT}        = 1;
     $hash->{SID_RENEW_ERR_CNT} = 0;

     if (defined $result->{sidNew} && $result->{sidNew}) {
       $hash->{fhem}{sidNewCount} += $result->{sidNew};
       $hash->{SID_RENEW_CNT}     += $result->{sidNew};
     }
   }

   if (ref ($result->{result}) eq "ARRAY" || ref ($result->{data}) eq "HASH" ){
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

} # end FRITZBOX_Helper_analyse_Lua_Result
#######################################################################
# loads internal and online phonebooks from extern FritzBox via web interface (http)
sub FRITZBOX_Phonebook_readRemote($$)
{
   my ($hash, $phonebookId) = @_;
   my $name   = $hash->{NAME};
   my $sidNew = 0;

   my $result = FRITZBOX_open_Web_Connection( $hash );

   return $result unless $result->{sid};

   $sidNew = $result->{sidNew} if defined $result->{sidNew};

   my $host = $hash->{HOST};
   my $url = 'http://' . $host;

   my $param;
   $param->{url}        = $url . "/cgi-bin/firmwarecfg";
   $param->{noshutdown} = 1;
   $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
   $param->{loglevel}   = 4;
   $param->{method}     = "POST";
   $param->{header}     = "Content-Type: multipart/form-data; boundary=boundary";

   $param->{data} = "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"sid\"\r\n".
                     "\r\n".
                     "$result->{sid}\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookId\"\r\n".
                     "\r\n".
                     "$phonebookId\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookExportName\"\r\n".
                     "\r\n".
#                     $hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}."\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookExport\"\r\n".
                     "\r\n".
                     "\r\n".
                     "--boundary--";

    FRITZBOX_Log $name, 4, "get export for phonebook: $phonebookId";

    my ($err, $phonebook) = HttpUtils_BlockingGet($param);

    FRITZBOX_Log $name, 5, "received http response code ".$param->{code} if(exists($param->{code}));

    if ($err ne "")
    {
      FRITZBOX_Log $name, 3, "got error while requesting phonebook: $err";
      my %retHash = ( "Error" => "got error while requesting phonebook" ) ;
      return \%retHash;
    }

    if($phonebook eq "" and exists($param->{code}))
    {
      FRITZBOX_Log $name, 3, "received http code ".$param->{code}." without any data";
      my %retHash = ( "Error" => "received http code ".$param->{code}." without any data" ) ;
      return \%retHash;
    }

    FRITZBOX_Log $name, 5, "received phonebook\n" . $phonebook;

    my %retHash = ( "data" => $phonebook ) ;
    return \%retHash;

} # end FRITZBOX_Phonebook_readRemote

#######################################################################
# reads the FritzBox phonebook file and parses the entries
sub FRITZBOX_Phonebook_parse($$$$)
{
    my ($hash, $phonebook, $searchNumber, $searchName) = @_;
    my $name = $hash->{NAME};
    my $contact;
    my $contact_name;
    my $number;
    my $uniqueID;
    my $count_contacts = 0;

    my $out;

# <contact>
#   <category />
#     <person>
#       <realName>1&amp;1 Kundenservice</realName>
#     </person>
#       <telephony nid="1"><number prio="1" type="work" id="0">0721 9600</number>
#     </telephony>
#     <services />
#     <setup />
#     <uniqueid>29</uniqueid>
# </contact>

    if($phonebook =~ /<phonebook/ and $phonebook =~ m,</phonebook>,) {

      if($phonebook =~ /<contact/ and $phonebook =~ /<realName>/ and $phonebook =~ /<number/) {

        while($phonebook =~ m,<contact[^>]*>(.+?)</contact>,gcs) {

          $contact = $1;

          if($contact =~ m,<realName>(.+?)</realName>,) {

            $contact_name = FRITZBOX_Helper_html2txt($1);

            FRITZBOX_Log $name, 5, "received contact_name: " . $contact_name;

            if($contact =~ m,<uniqueid>(.+?)</uniqueid>,) {
              $uniqueID = $1;
            } else {
              $uniqueID = "nil";
            }

            while($contact =~ m,<number[^>]*?type="([^<>"]+?)"[^<>]*?>([^<>"]+?)</number>,gs) {

              if($1 ne "intern" and $1 ne "memo") {
                $number = FRITZBOX_Phonebook_Number_normalize($hash, $2);
                
                if ($searchNumber) {
                }

                return $uniqueID if $contact_name eq $searchName;

                undef $number;
              }
            }
            undef $contact_name;
          }
        }
      }

      return "ERROR: non contacts/uniqueID found";
    } else {
      return "ERROR: this is not a FritzBox phonebook";
    }
} # end FRITZBOX_Phonebook_parse

#######################################################################
# normalizes a formated phone number
sub FRITZBOX_Phonebook_Number_normalize($$)
{
    my ($hash, $number) = @_;
    my $name = $hash->{NAME};

    my $area_code = AttrVal($name, "local-area-code", "");
    my $country_code = AttrVal($name, "country-code", "0049");

    $number =~ s/\s//g;                         # Remove spaces
    $number =~ s/^(\#[0-9]{1,10}\#)//g;         # Remove phone control codes
    $number =~ s/^\+/00/g;                      # Convert leading + to 00 country extension
    $number =~ s/[^\d\*#]//g if(not $number =~ /@/);  # Remove anything else isn't a number if it is no VoIP number
    $number =~ s/^$country_code/0/g;            # Replace own country code with leading 0

    if($number =~ /^\d/ and $number !~ /^0/ and $number !~ /^11/ and $number !~ /@/ and $area_code =~ /^0[1-9]\d+$/)
    {
       $number = $area_code.$number;
    }

    return $number;
} # end FRITZBOX_Phonebook_Number_normalize

#######################################################################
# replaces all HTML entities to their utf-8 counter parts.
sub FRITZBOX_Helper_html2txt($)
{
    my ($string) = @_;

    $string =~ s/&nbsp;/ /g;
    $string =~ s/&amp;/&/g;
    $string =~ s/&pos;/'/g;

#    $string =~ s/Ä/test/g;
#    return $string;

# %C3%B6 %C3%A4 %C3%BC + %C3%96 %C3%84 %C3%9C

    $string =~ s/ö/%C3%B6/g;
    $string =~ s/ä/%C3%A4/g;
    $string =~ s/ü/%C3%BC/g;
    $string =~ s/Ö/%C3%96/g;
    $string =~ s/Ä/%C3%84/g;
    $string =~ s/Ü/%C3%9C/g;
    $string =~ s/ß/\x{c3}\x{9f}/g;
    $string =~ s/@/\x{e2}\x{82}\x{ac}/g;

    return $string;

    $string =~ s/(\xe4|&auml;)/ä/g;
    $string =~ s/(\xc4|&Auml;)/Ä/g;
    $string =~ s/(\xf6|&ouml;)/ö/g;
    $string =~ s/(\xd6|&Ouml;)/Ö/g;
    $string =~ s/(\xfc|&uuml;)/ü/g;
    $string =~ s/(\xdc|&Uuml;)/Ü/g;
    $string =~ s/(\xdf|&szlig;)/ß/g;
    $string =~ s/(\xdf|&szlig;)/ß/g;
    $string =~ s/(\xe1|&aacute;)/á/g;
    $string =~ s/(\xe9|&eacute;)/é/g;
    $string =~ s/(\xc1|&Aacute;)/Á/g;
    $string =~ s/(\xc9|&Eacute;)/É/g;
    $string =~ s/\\u([a-f\d]{4})/encode('UTF-8',chr(hex($1)))/eig;
    $string =~ s/<[^>]+>//g;
    $string =~ s/&lt;/</g;
    $string =~ s/&gt;/>/g;
    $string =~ s/(?:^\s+|\s+$)//g;

    return $string;
} # end FRITZBOX_Helper_html2txt

#####################################
# checks and stores FritzBox password used for webinterface connection
sub FRITZBOX_Helper_store_Password($$)
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
    return "ERROR while saving the password - $err" if(defined($err));

    return "password successfully saved";

} # end FRITZBOX_Helper_store_Password

#####################################
# reads the FritzBox password
sub FRITZBOX_Helper_read_Password($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $xline       = ( caller(0) )[2];
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//       if ( defined $sub );
   $sub ||= 'no-subroutine-specified';

   if ($sub !~ /open_Web_Connection|call_TR064_Cmd|Set_check_APIs/) {
     FRITZBOX_Log $hash, 2, "EMERGENCY: unauthorized call for reading password from: [$sub]";
     $hash->{EMERGENCY} = "Unauthorized call for reading password from: [$sub]";
     return undef;
   }

   my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
   my $key = getUniqueId().$index;

   my ($password, $err);

   FRITZBOX_Log $hash, 4, "Read FritzBox password from file";
   ($err, $password) = getKeyValue($index);

   if ( defined($err) ) {
      FRITZBOX_Log $hash, 2, "unable to read FritzBox password from file: $err";
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

   } else {

      FRITZBOX_Log $hash, 2, "No password in file";
      return undef;

   }

} # end FRITZBOX_Helper_read_Password

###############################################################################
# Expression régulière pour valider une URL en Perl                           #
# Regular expression for URL validation in Perl                               #
#                                                                             #
# La sous-routine url_regex fournit l'expression régulière pour valider une   #
# URL. Ne sont pas reconnus les noms de domaine en punycode et les addresses  #
# IPv6.                                                                       #
# The url_regex subroutine returns the regular expression used to validate an #
# URL. Domain names in punycode and IPv6 adresses are not recognized.         #
#                                                                             #
# La liste de tests est celle publiée à l'adresse suivante, excepté deux      #
# cas qui sont donnés comme faux, alors qu'ils sont justes.                   #
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
# L'expression régulière est très largement basée sur celle publiée par       #
# Diego Perini sous licence MIT (https://gist.github.com/dperini/729294).     #
# Voir plus loin le texte de ladite licence (en anglais seulement).           #
# The regular expression is very largely based on the one published by        #
# Diego Perini under MIT license (https://gist.github.com/dperini/729294).    #
# See further for the text of sayed license.                                  #
#                                                                             #
# Le présent code est placé sous licence CeCIll-B, dont le texte se trouve à  #
# l'adresse http://cecill.info/licences/Licence_CeCILL-B_V1-fr.html           #
# This actual code is released under CeCIll-B license, whose text can be      #
# found at the adress http://cecill.info/licences/Licence_CeCILL-B_V1-en.html #
# It is an equivalent to BSD license, but valid under French law.             #
###############################################################################
sub FRITZBOX_Helper_Url_Regex {

    my $IPonly = shift;
    $IPonly //= 0;

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
    my $name = "(?:$ip|$host|$fulldomain)";
    my $port = "(?::\\d{2,5})?";
    my $path = "(?:[/?#]\\S*)?";

#    return "^($proto($id)?$name$port$path)\$";

    return "^($ip)\$" if $IPonly;

    return "^($name)\$";

} # end FRITZBOX_Helper_Url_Regex

#####################################

###############################################################################
# This example Perl script demonstrates converting arbitrary JSON             #
# to HTML using JSON::Parse and HTML::Make                                    #
# Regular expression for URL validation in Perl                               #
#                                                                             #
# https://www.lemoda.net/perl/json-to-html/index.html                         #
###############################################################################
# html xhr 1 lang de page mobile xhrId all
# 
# sub FRITZBOX_Helper_Json2HTML($) {
#   binmode STDOUT, ":encoding(utf8)";
# 
#   my ($input) = @_;
# 
#   my $element;
#   if (ref $input eq 'ARRAY') {
# 
#     $element = HTML::Make->new ('ol');
# 
#     for my $k (@$input) {
#       my $li = $element->push ('li');
#       $li->push (FRITZBOX_Helper_Json2HTML ($k));
#     }
# 
#   } elsif (ref $input eq 'HASH') {
# 
#     $element = HTML::Make->new ('table');
# 
#     for my $k (sort keys %$input) {
#       my $tr = $element->push ('tr');
#       $tr->push ('th', text => $k);
#       my $td = $tr->push ('td');
#       $td->push (FRITZBOX_Helper_Json2HTML ($input->{$k}));
#     }
# 
#   } else {
#     $element = HTML::Make->new ('span', text => $input);
#   }
#   
#   return $element->text();
# 
# } # end FRITZBOX_Helper_Json2HTML

#####################################

#sub isnum ($) {
#    return 0 if $_[0] eq '';
#    $_[0] ^ $_[0] ? 0 : 1
#}


1;

=pod
=item device
=item summary Controls some features of AVM's FRITZ!BOX, FRITZ!Repeater and Fritz!Fon.
=item summary_DE Steuert einige Funktionen von AVM's FRITZ!BOX, Fritz!Repeater und Fritz!Fon.

=begin html

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
<div>
   Controls some features of a FRITZ!BOX router or Fritz!Repeater. Connected Fritz!Fon's (MT-F, MT-D, C3, C4, C5) can be used as
   signaling devices. MP3 files and Text2Speech can be played as ring tone or when calling phones.
   <br>
   For detail instructions, look at and please maintain the <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki</b></a>.
   <br><br>
   The box is partly controlled via the official TR-064 interface but also via undocumented interfaces between web interface and firmware kernel.<br>
   <br>
   The modul was tested on FRITZ!BOX 7590, 7490 and FRITZ!WLAN Repeater 1750E with Fritz!OS 7.50 and higher.
   <br>
   Check also the other FRITZ!BOX moduls: <a href="#SYSMON">SYSMON</a> and <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>The modul uses the Perl modul 'JSON::XS', 'LWP', 'SOAP::Lite' for remote access.</i>
   <br>
   It is recommendet to set the attribute boxUser after defining the device.
   <br><br>

   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX &lt;host&gt;</code>
      <br>
      The parameter <i>host</i> is the web address (name or IP) of the FRITZ!BOX.
      <br><br>
      Example: <code>define Fritzbox FRITZBOX fritz.box</code>
      <br><br>
   </ul>

   <a name="FRITZBOXset"></a>
   <b>Set</b>
   <ul>
      <li><a name="blockIncomingPhoneCall"></a>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall Parameters</code></dt>
         <ul>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;new&gt; &lt;name&gt; &lt;phonenumber&gt; &lt;home|work|mobile|fax_work&gt;</code></dt>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;tmp&gt; &lt;name&gt; &lt;phonenumber&gt; &lt;home|work|mobile|fax_work&gt; &lt;dayTtime&gt;</code></dt>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;chg&gt; &lt;name&gt; &lt;phonenumber&gt; &lt;home|work|mobile|fax_work&gt; &lt;uid&gt;</code></dt>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;del&gt; &lt;uid&gt;</code></dt>
         </ul>
         <ul>
         <dt>&lt;new&gt; creates a new entry for a call barring for incoming calls </dt>
         <dt>&lt;tmp&gt; creates a new incoming call barring entry at time &lt;dayTtime&gt; is deleted again </dt>
         <dt>&lt;chg&gt; changes an existing entry for a call barring for incoming calls </dt>
         <dt>&lt;del&gt; deletes an existing entry for a call barring for incoming calls </dt>
         <dt>&lt;name&gt; unique name of the call blocking. Spaces are not permitted </dt>
         <dt>&lt;phonenumber&gt; Phone number that should be blocked </dt>
         <dt>&lt;home|work|mobile|fax_work&gt; Classification of the phone number </dt>
         <dt>&lt;uid&gt; UID of the call blocking. Unique for each call blocking name. If the reading says blocking_&lt;phonenumber&gt; </dt>
         <dt>&lt;dayTtime&gt; Fhem timestamp in format: yyyy-mm-ddThh:mm:ss to generate an 'at' command </dt>
         </ul>
         <br>
         Example of a daily call blocking from 8:00 p.m. to 6:00 a.m. the following day<br>
         <dt><code>
         defmod startNightblocking at *22:00:00 {\
           fhem('set FritzBox blockIncomingPhoneCall tmp nightBlocking 012345678 home ' . strftime("%Y-%m-%d", localtime(time + DAYSECONDS)) . 'T06:00:00', 1);;\
         }
         </code></dt><br>
      </li><br>

      <li><a name="call"></a>
         <dt><code>set &lt;name&gt; call &lt;number&gt; [duration]</code></dt>
         <br>
         Calls for 'duration' seconds (default 60) the given number from an internal port (default 1).
         <br>
         The ringing occurs via the dialing aid, which must be activated via "Telephony/Calls/Dialing aid".<br>
         A different port may need to be set via the Fritz!Box web interface. The current one is in “box_stdDialPort”.
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
         Execution is non-blocking. The feedback takes place in the reading: retStat_chgProfile<br>
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

      <li><a name="diversity"></a>
         <dt><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         Switches the call diversity number (1, 2 ...) on or off.
         A call diversity for an incoming number has to be created with the FRITZ!BOX web interface. Requires TR064 (>=6.50).
         <br>
         Note! Only a diversity for a concret home number and <u>without</u> filter for the calling number can be set. Hence, an approbriate <i>diversity</i>-reading must exist.
      </li><br>

      <li><a name="enableVPNshare"></a>
         <dt><code>set &lt;name&gt; enableVPNshare &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         &lt;number&gt; results from the reading vpn<i>n..n</i>_user.. or _box<br>
         Switches the vpn share with the given number nn on or off.<br>
         Execution is non-blocking. The feedback takes place in the reading: retStat_enableVPNshare <br>
         Needs FRITZ!OS 7.21 or higher
      </li><br>

      <li><a name="energyMode"></a>
         <dt><code>set &lt;name&gt; energyMode &lt;default|eco&gt;</code></dt>
         <br>
         Changes the energy mode of the FRITZ!Box. &lt;default&gt; uses a balanced mode with optimal performance.<br>
         The most important energy saving functions are already active.<br>
         &lt;eco&gt; reduces power consumption.<br>
         Requires FRITZ!OS 7.50 or higher.
      </li><br>

      <li><a name="guestWlan"></a>
         <dt><code>set &lt;name&gt; guestWlan &lt;on|off&gt;</code></dt>
         <br>
         Switches the guest WLAN on or off. The guest password must be set. If necessary, the normal WLAN is also switched on.
      </li><br>

      <li><a name="inActive"></a>
         <dt><code>set &lt;name&gt; inActive &lt;on|off&gt;</code></dt>
         <br>
         Temporarily deactivates the internal timer.
         <br>
      </li><br>

      <li><a name="ledSetting"></a>
         <dt><code>set &lt;name&gt; ledSetting &lt;led:on|off&gt; and/or &lt;bright:1..3&gt; and/or &lt;env:on|off&gt;</code></dt>
         <br>
         The number of parameters varies from FritzBox to Fritzbox to repeater.<br>
         The options can be checked using get &lt;name&gt; luaInfo ledSettings.<br><br>
         &lt;led:<on|off&gt; switches the LEDs on or off.<br>
         &lt;bright:1..3&gt; regulates the brightness of the LEDs from 1=weak, 2=medium to 3=very bright.<br>
         &lt;env:on|off&gt; switches the brightness control on or off depending on the ambient brightness.<br><br>
         Requires FRITZ!OS 7.21 or higher.<br><br>
         A special parameter is <code>set &lt;name&gt; ledSetting &lt;notifyoff:notify_ID&gt;</code> added.<br>
         This can be used to reset the red info LED on the FritzBox, which signals special operating states.
      </li><br>

      <li><a name="lockFilterProfile"></a>
         <dt><code>set &lt;name&gt; lockFilterProfile &lt;profile name&gt; &lt;status:never|unlimited&gt; &lt;bpjm:on|off&gt;</code></dt>
         <br>
         &lt;profile name&gt; Name of the access profile<br>
         &lt;status:&gt; switches the profile off (never) or on (unlimited)<br>
         &lt;bpjm:&gt; switches parental controls on/off<br>
         The parameters &lt;status:&gt; / &lt;bpjm:&gt; can be specified individually or together.<br>
         Requires FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="lockLandevice"></a>
         FritzOS < 8.00 <dt><code>set &lt;name&gt; lockLandevice &lt;number|mac&gt; &lt;on|off|rt&gt;</code></dt>
         FritzOS >= 8.00 <dt><code>set &lt;name&gt; lockLandevice &lt;number|mac&gt; &lt;on|off|rt|rtoff&gt;</code></dt>
         <br>
         &lt;number&gt; is the ID from landevice<i>n..n</i><br>
         Switches the landevice blocking to on (blocked), off (unlimited) or to rt (realtime).<br>
         Execution is non-blocking. The feedback takes place in the reading: retStat_lockLandevice<br>
         Needs FRITZ!OS 7.21 or higher
      </li><br>

      <li><a name="macFilter"></a>
         <dt><code>set &lt;name&gt; macFilter &lt;on|off&gt;</code></dt>
         <br>
         Activates/deactivates the MAC Filter. Depends to "new WLAN Devices in the FRITZ!BOX.<br>
         Execution is non-blocking. The feedback takes place in the reading: retStat_macFilter<br>
         Needs FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="phoneBookEntry"></a>
         <dt><code>set &lt;name&gt; phoneBookEntry &lt;new&gt; &lt;PhoneBookID&gt; &lt;category&gt; &lt;entryName&gt; &lt;home|mobile|work|fax_work|other:phoneNumber&gt; [home|mobile|work|fax_work|other:phoneNumber] ...</code></dt>
         <br>
         <dt><code>set &lt;name&gt; phoneBookEntry &ltdel&gt; &lt;PhoneBookID&gt; &lt;entryName&gt;</code></dt>
         <br>
         &lt;PhoneBookID&gt; can be found in the new Reading fon_phoneBook_IDs.<br>
         &lt;category&gt; 0 or 1. 1 stands for important person.<br>
         &lt;entryName&gt; Name of the phone book entry<br>
      </li><br>

      <li><a name="password"></a>
         <dt><code>set &lt;name&gt; password &lt;password&gt;</code></dt>
         <br>
      </li><br>

      <li><a name="reboot"></a>
         <dt><code>set &lt;name&gt; reboot &lt;minutes&gt</code></dt>
         <br>
         Restarts the FRITZ!BOX in &lt;minutes&gt. If this 'set' is executed, a one-time 'at' is generated in the room 'Unsorted',
         which is then used to execute the reboot. The new 'at' has the device name: act_Reboot_&lt;Name FB Device&gt;.
      </li><br>

      <li><a name="rescanWLANneighbors"></a>
         <dt><code>set &lt;name&gt; rescanWLANneighbors</code></dt>
         <br>
         Rescan of the WLAN neighborhood.
         Execution is non-blocking. The feedback takes place in the reading: retStat_rescanWLANneighbors<br>
      </li><br>

      <li><a name="ring"></a>
         <dt><code>set &lt;name&gt; ring &lt;intNumbers&gt; [duration] [show:Text]  [say:Text | play:MP3URL]</code></dt>
         <dt>Example:</dt>
         <dd>
         <code>set &lt;name&gt; ring 611,612 5</code>
         <br>
         </dd>
         Rings the internal numbers for "duration" seconds and (on Fritz!Fons) with the given "ring tone" name.
         Different internal numbers have to be separated by a comma (without spaces).
         <br>
         Default duration is 5 seconds. The FRITZ!BOX can create further delays. Default ring tone is the internal ring tone of the device.
         Ring tone will be ignored for collected calls (9 or 50).
         <br>
         If the call is taken the callee hears the "music on hold" which can also be used to transmit messages.
         <br>
         The behaviour may vary depending on the Fritz!OS.
      </li><br>

      <li><a name="smartHome"></a>
         <dt><code>set &lt;name&gt; smartHome Parameters</code></dt>

         <ul>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;tempOffset:value&gt;</code></dt>
         <dd>changes the temperature offset to the value for the SmartHome device with the specified ID.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;tmpAdjust:value&gt;</code></dt>
         <dd>sets the radiator controller temporarily to the temperature: value.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;tmpPerm:0|1&gt;</code></dt>
         <dd>sets the radiator controller to permanently off or on.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;switch:0|1&gt;</code></dt>
         <dd>switches the socket adapter off or on.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;preDefSave:nameSetting&gt;</code></dt>
         <dd>saves the settings for the device under the specified name.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;preDefDel:nameSetting&gt;</code></dt>
         <dd>deletes the settings for the device under the specified name.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;preDefLoad:[deviceID_load:]nameSetting[:A|:G]&gt;</code></dt>
         <dd>loads a saved setting into the Fritzbox.
         If [deviceID_load:] is specified, the saved setting of another functionally identical device will be loaded into the Fritzbox.<br>
         For devices of the 'socket' type, you can differentiate whether all settings or just those of the website should be loaded :A == 'Switch automatically' or :G == 'General'.
         </dd>
         </ul>
         The ID can be obtained via <code>get &lt;name&gt; luaInfo &lt;smartHome&gt;</code> can be determined.<br><br>
         The result of the command is stored in the Reading retStat_smartHome.
         <br>
         Requires FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="switchIPv4DNS"></a>
         <dt><code>set &lt;name&gt; switchIPv4DNS &lt;provider|other&gt;</code></dt>
         <br>
         Switches the ipv4 dns to the internet provider or another dns (must be defined for the FRITZ!BOX).
         <br>
         Needs FRITZ!OS 7.21 or higher
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

      <li><a name="wakeUpCall"></a>
         <dt><code>set &lt;name&gt; wakeUpCall &lt;alarm1|alarm2|alarm3&gt; &lt;off&gt;</code></dt>
         <dt><code>set &lt;name&gt; wakeUpCall &lt;alarm1|alarm2|alarm3&gt; &lt;Device Number|Name&gt; &lt;daily|only_once&gt; &lt;hh:mm&gt;</code></dt>
         <dt><code>set &lt;name&gt; wakeUpCall &lt;alarm1|alarm2|alarm3&gt; &lt;Device Number|Name&gt; &lt;per_day&gt; &lt;hh:mm&gt; &lt;mon:0|1 tue:0|1 wed:0|1 thu:0|1 fri:0|1 sat:0|1 sun:0|1&gt;</code></dt>
         <br>
         Disables or sets the wake up call: alarm1, alarm2 or alarm3.
         <br>
         If the device name is used, a space in the name must be replaced by %20.
         <br>
         THe DeviceNumber can be found in the reading <b>dect</b><i>n</i><b>_device</b> or <b>fon</b><i>n</i><b>_device</b>
         <br>
         If you get "redundant name in FB" in a reading <b>dect</b><i>n</i> or <b>fon</b><i>n</i> than the device name can not be used.
         <br>
         Needs FRITZ!OS 7.21 or higher
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

      <li><a name="wlanLogExtended"></a>
         <dt><code>set &lt;name&gt; wlanLogExtended &lt;on|off&gt;</code></dt>
         <br>
         Toggles "Also log logins and logouts and extended Wi-Fi information" on or off.
         <br>
         Status in reading: retStat_wlanLogExtended.
      </li><br>

      <li><a name="wlanGuestParams"></a>
         <dt><code>set &lt;name&gt; wlanGuestParams &lt;param:value&gt; [&lt;param:value&gt; ...]</code></dt>
         <br>
         Possible combinations of &lt;param:value&gt;
         <ul>
         <li>&lt;wlan:on|off&gt;</li>
         <li>&lt;ssid:name&gt;</li>
         <li>&lt;psk:password&gt;</li>
         <li>&lt;mode:private|public&gt;</li>
         <li>&lt;tmo:minutes&gt; , tmo == timeout in minutes (15 - 4320). If tmo is set, isTimeoutActive is automatically set to on.</li>
         <li>&lt;isTimeoutActive:on|off&gt;</li>
         <li>&lt;timeoutNoForcedOff:on|off&gt;</li>
         </ul>
         Status in Reading: retStat_wlanGuestParams
      </li><br>
   </ul>

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <br>

      <li><a name="fritzLog"></a>
         <dt><code>get &lt;name&gt; fritzLog &lt;table&gt; &lt;all | sys | wlan | usb | net | fon&gt;</code></dt>
         <br>
         &lt;table&gt; displays the result in FhemWeb as a table.
         <br><br>
         <dt><code>get &lt;name&gt; fritzLog &lt;hash&gt; &lt;all | sys | wlan | usb | net | fon&gt; [on|off]</code></dt>
         <br>
         &lt;hash&gt; [on] forwards the result to a function (non-blocking) myUtilsFritzLogExPostnb($hash, $filter, $result) for own processing.
         <br>
         &lt;hash&gt; &lt;off&gt; forwards the result to a function (blocking) myUtilsFritzLogExPost($hash, $filter, $result) f&uuml;r eigene Verarbeitung weiter.
         <br>
         where:<br>
         $hash -> Fhem Device hash,<br>
         $filter -> log filter,<br>
         $result -> return of the data.lua query as JSON.
         <br><br>
         &lt;all | sys | wlan | usb | net | fon&gt; these parameters are used to filter the log information.
         <br><br>
         [on|off] gives parameter &lt;hash&gt; indicates whether further processing is blocking [off] or non-blocking [on] (default).
         <br><br>
         Feeback stored in the readings:<br>
         retStat_fritzLogExPost = status of myUtilsFritzLogExPostnb / myUtilsFritzLogExPostnb<br>
         retStat_fritzLogInfo = status log info request
         <br><br>
         Needs FRITZ!OS 7.21 or higher.
         <br>
      </li><br>

      <li><a name="lanDeviceInfo"></a>
         <dt><code>get &lt;name&gt; lanDeviceInfo &lt;number&gt;</code></dt>
         <br>
         &lt;number&gt; is the ID from landevice<i>n..n</i> or its MAC<br>
         Shows informations about a specific lan device.<br>
         If there is a child lock, only then is the measurement taken, the following is also output:<br>
         USEABLE: Allocation in seconds<br>
         UNSPENT: not used in seconds<br>
         PERCENT: in percent<br>
         USED: used in seconds<br>
         USEDSTR: shows the time used in hh:mm of quota hh:mm<br>
         Needs FRITZ!OS 7.21 or higher.
      </li><br>

      <li><a name="luaData"></a>
         <dt><code>get &lt;name&gt; luaData [json] &lt;Command&gt;</code></dt>
         <br>
         Evaluates commands via data.lua codes.If there is a semicolon in the parameters, replace it with #x003B.
         Optionally, json can be specified as the first parameter. The result is then returned as JSON for further processing.
      </li><br>

      <li><a name="luaDectRingTone"></a>
         Experimental have a look at: <a href="https://forum.fhem.de/index.php?msg=1274864"><b>FRITZBOX - Fritz!Box und Fritz!Fon sprechen</b></a><br>
         <dt><code>get &lt;name&gt; luaDectRingTone &lt;Command&gt;</code></dt>
         <br>
      </li><br>

      <li><a name="luaFunction"></a>
         <dt><code>get &lt;name&gt; luaFunction &lt;function&gt;</code></dt>
         <br>
         Executes AVM lua functions.<br>
         function: <code>&lt;path/luaFunction?&gt;&lt;Parameter&gt;</code><br>
         function: <code>internet/inetstat_monitor.lua?myXhr=1&action=disconnect&useajax=1&xhr=1</code> gets a new IP address for the FritzBox.
      </li><br>

      <li><a name="luaInfo"></a>
         <dt><code>get &lt;name&gt; luaInfo &lt;landevices|ledSettings|smartHome|vpnShares|globalFilters|kidProfiles|userInfos|wlanNeighborhood|mobileInfo|docsisInformation&gt;</code></dt>
         <br>
         Needs FRITZ!OS 7.21 or higher.<br>
         lanDevices -> Shows a list of active and inactive lan devices.<br>
         ledSettings -> Generates a list of LED settings with an indication of which set ... ledSetting are possible.<br>
         smartHome -> Generates a list of SmartHome devices.<br>
         vpnShares -> Shows a list of active and inactive vpn shares.<br>
         kidProfiles -> Shows a list of internet access profiles.<br>
         globalFilters -> Shows the status (on|off) of the global filters: globalFilterNetbios, globalFilterSmtp, globalFilterStealth, globalFilterTeredo, globalFilterWpad<br>
         userInfos -> Shows a list of FRITZ!BOX users.<br>
         wlanNeighborhood -> Shows a list of WLAN neighborhood devices.<br>
         docsisInformation -> Shows DOCSIS informations (only Cable).<br>
         mobileInfo -> Shows cell phone informations.<br>
      </li><br>

      <li><a name="luaQuery"></a>
         <dt><code>get &lt;name&gt; luaQuery &lt;query&gt;</code></dt>
         <br>
         Displays information by caling query.lua.<br>
         query: <code>&lt;queryFunction:&gt;&lt;queryRequest&gt;</code><br>
         query: <code>uimodlogic:status/uptime_hours</code> gets the hours that the FritzBox has been running continuously since the last restart.
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

      <li><a name="smartHomePreDef"></a>
         <dt><code>get &lt;name&gt; smartHomePreDef [deviceID [Saved-PreDef-Name]]</code></dt>
         <br>
         <dt><code>get &lt;name&gt; smartHomePreDef</code></dt>
         <dd>lists all saved settings. This list is also displayed with get <name> luaInfo smartHome.</dd>
         <dt><code>get &lt;name&gt; smartHomePreDef &lt;deviceID&gt;</code></dt>
         <dd>lists all settings saved for the device.</dd>
         <dt><code>get &lt;name&gt; smartHomePreDef &lt;deviceID&gt; &lt;Saved-PreDef-Name&gt;</code></dt>
         <dd>shows the data saved for the device under the Saved-PreDef name.</dd>
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
         Polling-Interval. Default is 300 (seconds). Smallest possible value is 60 (seconds).
      </li><br>

      <li><a name="verbose"></a>
        <dt><code>attr &lt;name&gt; verbose &lt;0 .. 5&gt;</code></dt>
        If verbose is set to the value 5, all log data will be saved in its own log file written.<br>
        Log file name:deviceName_debugLog.dlog<br>
        In the INTERNAL Reading DEBUGLOG there is a link &lt;DEBUG log can be viewed here&gt; for direct viewing of the log.<br>
        Furthermore, a FileLog device:deviceName_debugLog is created in the same room and the same group as the FRITZBOX device.<br>
        If verbose is set to less than 5, the FileLog device is deleted and the log file is retained.
        If verbose is deleted, the FileLog device and the log file are deleted.
      </li><br>

      <li><a name="FhemLog3Std"></a>
        <dt><code>attr &lt;name&gt; FhemLog3Std &lt0 | 1&gt;</code></dt>
        If set, the log information will be written in standard Fhem format.<br>
        If the output to a separate log file was activated by a verbose 5, this will be ended.<br>
        The separate log file and the associated FileLog device are deleted.<br>
        If the attribute is set to 0 or deleted and the device verbose is set to 5, all log data will be written to a separate log file.<br>
        Log file name: deviceName_debugLog.dlog<br>
        In the INTERNAL Reading DEBUGLOG there is a link &lt;DEBUG log can be viewed here&gt; for direct viewing of the log.<br>
      </li><br>

      <li><a name="reConnectInterval"></a>
         <dt><code>reConnectInterval &lt;seconds&gt;</code></dt>
         <br>
         After network failure or FritzBox unavailability. Default is 180 (seconds). The smallest possible value is 55 (seconds).
      </li><br>

      <li><a name="maxSIDrenewErrCnt"></a>
         <dt><code>maxSIDrenewErrCnt &lt;5..20&gt;</code></dt>
         <br>
         Number of consecutive errors permitted when retrieving the SID from the FritzBox. Minimum is five, maximum is twenty. The default value is 5.<br>
         If the number is exceeded, the internal timer is deactivated. 
      </li><br>

                ."setgetTimeout:10,30,40,50,75,100,125 "

      <li><a name="nonblockingTimeOut"></a>
         <dt><code>nonblockingTimeOut &lt;30|35|40|50|75|100|125&gt;</code></dt>
         <br>
         Timeout for fetching data from the Fritz!Box. Default is 55 (seconds).
      </li><br>

      <li><a name="setgetTimeout"></a>
         <dt><code>setgetTimeout&lt;10|30|40|50|75|100|125&gt;</code></dt>
         <br>
         Timeout for fetching data from the Fritz!Box when calling non blocking set/get command. Default is 10 (seconds).
      </li><br>

      <li><a name="boxUser"></a>
         <dt><code>boxUser &lt;user name&gt;</code></dt>
         <br>
         Username for TR064 or other web-based access. The current FritzOS versions require a user name for login.
         <br>
      </li><br>

      <li><a name="deviceInfo"></a>
         <dt><code>deviceInfo &lt;ipv4, name, uid, connection, speed, rssi, statIP, _noDefInf_, _default_&, space, comma&gt;</code></dt>
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
         If the following readings are deactivated, an entire group of readings is always deactivated.<br>
         <b>box_dns_Server</b> -&gt; deactivates all readings <b>box_dns_Server</b><i>n</i><br>
         disable single box_ Readings.<br>
      </li><br>

      <li><a name="enableBoxReadings"></a>
         <dt><code>enableBoxReadings &lt;list&gt;</code></dt>
         <br>
         If the following readings are activated, an entire group of readings is always activated.<br>
         <b>box_energyMode</b> -&gt; activates all readings <b>box_energyMode</b><i>.*</i> FritzOS >= 7.21<br>
         <b>box_globalFilter</b> -&gt; activates all readings <b>box_globalFilter</b><i>.*</i> FritzOS >= 7.21<br>
         <b>box_led</b> -&gt; activates all readings <b>box_led</b><i>.*</i> FritzOS >= 6.00<br>
         <b>box_vdsl</b> -&gt; activates all readings <b>box_vdsl</b><i>.*</i> FritzOS >= 7.80<br>
         <b>box_dns_Srv</b> -&gt; activates all readings <b>box_dns_Srv</b><i>n</i> FritzOS > 7.31<br>
         <b>box_pwr</b> -&gt; activates all readings <b>box_pwr</b><i>...</i> FritzOS >= 7.00. ! not available for Cable with FritzOS 8.00<br>
         <b>box_guestWlan</b> -&gt; activates all readings <b>box_guestWlan</b><i>...</i> FritzOS >= 7.00<br>
         <b>box_usb</b> -&gt; activates all readings <b>box_usb</b><i>...</i> FritzOS >= 7.00<br>
         <b>box_notify</b> -&gt; activates all readings <b>box_notify</b><i>...</i> FritzOS > 7.00<br>
      </li><br>

      <li><a name="enableLogReadings"></a>
         <dt><code>enableLogReadings&lt;list&gt;</code></dt>
         <br>
         If the following readings are activated, the corresponding system log of the Fritz device is retrieved.<br>
         <b>box_sys_Log</b> -&gt; gets the system log. Last log date in reading: box_sys_LogNewest<br>
         <b>box_wlan_Log</b> -&gt; gets the WLAN log. Last log date in reading: box_wlan_LogNewest<br>
         <b>box_fon_Log</b> -&gt; gets the phone log. Last log date in reading: box_fon_LogNewest<br>
      </li><br>

      <li><a name="disableDectInfo"></a>
         <dt><code>disableDectInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of dect information off/on.
      </li><br>

      <li><a name="disableFonInfo"></a>
         <dt><code>disableFonInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of phone information off/on.
      </li><br>

      <li><a name="disableHostIPv4check"></a>
         <dt><code>disableHostIPv4check&lt;0 | 1&gt;</code></dt>
         <br>
         Disable the check if host is available.
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

      <li><a name="enablePhoneBookInfo"></a>
         <dt><code>enablePhoneBookInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of phonebook information off/on.
      </li><br>

      <li><a name="enableKidProfiles"></a>
         <dt><code>enableKidProfiles &lt;0 | 1&gt;</code></dt>
         <br>
         Switches the takeover of kid profiles as reading off / on.
      </li><br>

      <li><a name="enableMobileInfo"></a>
         <dt><code>enableMobileInfo &lt;0 | 1&gt;</code></dt>
         <br><br>
         ! Experimentel !
         <br><br>
         Switches the takeover of USB mobile devices as reading off / on.
         <br>
         Needs FRITZ!OS 7.50 or higher.
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

      <li><a name="enableSmartHome"></a>
         <dt><code>enableSmartHome &lt;off | all | group | device&gt;</code></dt>
         <br>
         Activates the transfer of SmartHome data as readings.
      </li><br>

      <li><a name="enableReadingsFilter"></a>
         <dt><code>enableReadingsFilter &lt;list&gt;</code></dt>
         <br>
         Activates filters for adopting Readings (SmartHome, Dect). A reading that matches the filter is <br>
         supplemented with a . as the first character. This means that the reading does not appear in the web frontend, but can be accessed via ReadingsVal.
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

      <li><a name="lanDeviceReading"></a>
         <dt><code>lanDeviceReading &lt;mac|ip&gt;</code></dt>
         <br>
         Specifies whether the reading name should be formed from the IP address with prefix ip_ or the MAC address with prefix mac_ for network devices.<br>
         Default is mac.
      </li><br>

      <li><a name="retMsgbySet"></a>
         <dt><code>retMsgbySet &lt;all|error|none&gt;</code></dt>
         <br>
         The attribute can be used to specify the return of the SET commands.<br>
         &lt;all&gt;: Default. All results of the SET's are returned.<br>
         &lt;error&gt;: Only errors are returned.<br>
         &lt;none&gt;: There is no return.<br>
      </li><br>

      <li><a name="wlanNeighborsPrefix"></a>
         <dt><code>wlanNeighborsPrefix &lt;prefix&gt;</code></dt>
         <br>
         Defines a new prefix for the reading name of the wlan neighborhood devices that is build from the mac address. Default prefix is nbh_.
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
      <li><b>box_box_dns_Server</b><i>n</i> - Provider DNS Server</li>
      <li><b>box_box_dns_Srv</b><i>n</i><b>_used_IPv4_</b><i>n</i> - used IPv4 DNS Server</li>
      <li><b>box_box_dns_Srv</b><i>n</i><b>_used_IPv6_</b><i>n</i> - used IPv6 DNS Server</li>
      <li><b>box_connection_Type</b> - connection type</li>
      <li><b>box_cpuTemp</b> - Tempreture of the Fritx!Box CPU</li>
      <li><b>box_dect</b> - Current state of the DECT base: activ, inactiv</li>
      <li><b>box_dsl_downStream</b> - minimum effective data rate  (MBit/s)</li>
      <li><b>box_dsl_upStream</b> - minimum effective data rate  (MBit/s)</li>
      <li><b>box_energyMode</b> - Energy mode of the FritzBox</li>
      <li><b>box_energyModeWLAN_Timer</b> - Mode of the WLAN timer</li>
      <li><b>box_energyModeWLAN_Time</b> - Period HH:MM - HH:MM of WLAN deactivation</li>
      <li><b>box_energyModeWLAN_Repetition</b> - Repeating the WLAN Tminer</li>
      <li><b>box_fon_LogNewest</b> - newest phone event: ID Date Time </li>
      <li><b>box_fwVersion</b> - Firmware version of the box, if outdated then '(old)' is appended</li>
      <li><b>box_guestWlan</b> - Current state of the guest WLAN</li>
      <li><b>box_guestWlanCount</b> - Number of devices connected to guest WLAN</li>
      <li><b>box_guestWlanRemain</b> - Remaining time until the guest WLAN is switched off</li>
      <li><b>box_guestWlan</b> - Aktueller Status des G&auml;ste-WLAN</li>
      <li><b>box_guestWlanCount</b> - Anzahl der Ger&auml;te die &uuml;ber das G&auml;ste-WLAN verbunden sind</li>
      <li><b>box_guestWlanRemain</b> - Verbleibende Zeit bis zum Ausschalten des G&auml;ste-WLAN</li>
      <li><b>box_guestWlan_SSID</b> - guest WLAN Name (SSID)</li>
      <li><b>box_guestWlan_defPubSSID</b> - default public name (SSID)</li>
      <li><b>box_guestWlan_defPrivSSID</b> - default private name (SSID)</li>
      <li><b>box_guestWlan_groupAccess</b> - group access active</li>
      <li><b>box_guestWlan_tmoActive</b> - time restriction active</li>
      <li><b>box_globalFilterNetbios</b> - Current status: NetBIOS filter active</li>
      <li><b>box_globalFilterSmtp</b> - Current status: Email filter active via port 25</li>
      <li><b>box_globalFilterStealth</b> - Current status: Firewall in stealth mode</li>
      <li><b>box_globalFilterTeredo</b> - Current status: Teredo filter active</li>
      <li><b>box_globalFilterWpad</b> - Current status: WPAD filter active</li>
      <li><b>box_ipv4_Extern</b> - Internet IPv4 of the FRITZ!BOX</li>
      <li><b>box_ipv6_Extern</b> - Internet IPv6 of the FRITZ!BOX</li>
      <li><b>box_ipv6_Prefix</b> - Internet IPv6 Prefix of the FRITZ!BOX for the LAN/WLAN</li>
      <li><b>box_ledCanDim</b> - shows whether setting the brightness of the LEDs is implemented in the Fritzbox/repeater</li>
      <li><b>box_ledDimValue</b> - shows to what value the LEDs are dimmed</li>
      <li><b>box_ledDisplay</b> - shows whether the LEDs are on or off</li>
      <li><b>box_ledEnvLight</b> - shows whether the ambient brightness controls the brightness of the LEDs</li>
      <li><b>box_ledHasEnv</b> - shows whether setting the LED brightness based on the ambient brightness is implemented in the Fritzbox/repeater</li>
      <li><b>box_last_auth_err</b> - last authentication error</li>
      <li><b>box_mac_Address</b> - MAC address</li>
      <li><b>box_macFilter_active</b> - Status of the WLAN MAC filter (restrict WLAN access to known WLAN devices)</li>
      <li><b>box_meshRole</b> - from version 07.21 the mesh role (master, slave) is displayed.</li>
      <li><b>box_model</b> - FRITZ!BOX model</li>
      <li><b>box_moh</b> - music-on-hold setting</li>
      <li><b>box_model</b> - FRITZ!BOX model</li>
      <li><b>box_notify_</b><i>...</i> - the two readings are created when the FritzBox activates the red info LED and a corresponding note</li>
      <li><b>box_notify_</b><i>...</i><b>_info</b> - placed on the website. The readings contain a link for further information and <br>
                                                     a link to acknowledge the information. This link confirms the information in the FritzBox<br>
                                                     and the two readings will be deleted. If the information is withdrawn from the FritzBox, then the <br>
                                                     Readings the addition solved and the link to acknowledge only deletes the readings</li>
      <li><b>box_connect</b> - connection state: Unconfigured, Connecting, Authenticating, Connected, PendingDisconnect, Disconnecting, Disconnected</li>
      <li><b>box_last_connect_err</b> - last connection error</li>
      <li><b>box_upnp</b> - application interface UPNP (needed by this modul)</li>
      <li><b>box_upnp_control_activated</b> - state if control via UPNP is enabled</li>
      <li><b>box_uptime</b> - uptime since last reboot</li>
      <li><b>box_uptimeConnect</b> - connect uptime since last reconnect</li>
      <li><b>box_DSL_Act</b> - DSL: current power in percent of maximal power</li>
      <li><b>box_Rate_Act</b> - over all: current power in percent of maximal power</li>
      <li><b>box_WLAN_Act</b> - WLAN: current power in percent of maximal power</li>
      <li><b>box_mainCPU_Act</b> - CPU: current power in percent of maximal power</li>
      <li><b>box_powerRate</b> - current power in percent of maximal power</li>
      <li><b>box_powerLine</b> - powerline active</li>
      <li><b>box_rateDown</b> - average download rate in the last update interval</li>
      <li><b>box_rateUp</b> - average upload rate in the last update interval</li>
      <li><b>box_stdDialPort</b> - standard caller port when using the dial function of the box</li>
      <li><b>box_sys_LogNewest</b> - newest system event: ID Date Time </li>
      <li><b>box_tr064</b> - application interface TR-064 (needed by this modul)</li>
      <li><b>box_tr069</b> - provider remote access TR-069 (safety issue!)</li>
      <li><b>box_usb_FTP_activ</b></li>
      <li><b>box_usb_FTP_enabled</b></li>
      <li><b>box_usb_NAS_enabled</b></li>
      <li><b>box_usb_SMB_enabled</b></li>
      <li><b>box_usb_autoIndex</b></li>
      <li><b>box_usb_indexStatus</b></li>
      <li><b>box_usb_webDav</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devConType</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devEject</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devID</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devName</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devStatus</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devStorageTotal</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devStorageUsed</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devType</b></li>
      <li><b>box_vdsl_downStreamRate</b> - Current down stream data rate (MBit/s)</li>
      <li><b>box_vdsl_downStreamMaxRate</b> - Max down stream data rate (MBit/s)</li>
      <li><b>box_vdsl_upStreamRate</b> - Current up stream data rate (MBit/s)</li>
      <li><b>box_vdsl_upStreamMaxRate</b> - Max up stream data rate (MBit/s)</li>
      <li><b>box_wan_AccessType</b> - access type (DSL, Ethernet, ...)</li>
      <li><b>box_wlan_Count</b> - Number of devices connected via WLAN</li>
      <li><b>box_wlan_Active</b> - Current status of the WLAN</li>
      <li><b>box_wlan_2.4GHz</b> - Current state of the 2.4 GHz WLAN</li>
      <li><b>box_wlan_5GHz</b> - Current state of the 5 GHz WLAN</li>
      <li><b>box_wlan_lastScanTime</b> - last scan of the WLAN neighborhood. This readings is only available if the attribut enableWLANneighbors is set.</li>
      <li><b>box_wlan_LogExtended</b> - Status -> "Also log logins and logouts and extended Wi-Fi information".</li>
      <li><b>box_wlan_LogNewest</b> - newest WLAN event: ID Date time </li>

      <br>

      <li><b>box_docsis30_Ds_corrErrors</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_frequencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_latencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_mses</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_nonCorrErrors</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_powerLevels</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_modulations</b> - Only Fritz!Box Cable</li>

      <li><b>box_docsis30_Us_frequencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Us_powerLevels</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis30_Us_modulations</b> - Only Fritz!Box Cable</li>

      <li><b>box_docsis31_Ds_frequencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis31_Ds_powerLevels</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis31_Ds_modulations</b> - Only Fritz!Box Cable</li>

      <li><b>box_docsis31_Us_frequencys</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis31_Us_powerLevels</b> - Only Fritz!Box Cable</li>
      <li><b>box_docsis31_Us_modulations</b> - Only Fritz!Box Cable</li>

      <br>

      <li><b>dect</b><i>n</i> - Name of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_alarmRingTone</b> - Alarm ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_custRingTone</b> - Customer ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_device</b> - Internal device number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_fwVersion</b> - Firmware Version of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_intern</b> - Internal phone number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_intRingTone</b> - Internal ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_manufacturer</b> - Manufacturer of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_model</b> - Model of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_NoRingWithNightSetting</b> - Do not signal any events for the DECT telephone <i>n</i> when the Do Not Disturb feature is active</li>
      <li><b>dect</b><i>n</i><b>_radio</b> - Current internet radio station ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>n</i><b>_NoRingTime</b> - declined ring times of the DECT telephone <i>n</i></li>
      <br>
      <li><b>diversity</b><i>n</i> - Own (incoming) phone number of the call diversity <i>1</i></li>
      <li><b>diversity</b><i>n</i><b>_dest</b> - Destination of the call diversity <i>1</i></li>
      <li><b>diversity</b><i>n</i><b>_state</b> - Current state of the call diversity <i>1</i></li>
      <br>
      <li><b>fon</b><i>n</i> - Internal name of the analog FON port <i>1</i></li>
      <li><b>fon</b><i>n</i><b>_device</b> - Internal device number of the FON port <i>1</i></li>
      <li><b>fon</b><i>n</i><b>_intern</b> - Internal phone number of the analog FON port <i>1</i></li>
      <li><b>fon</b><i>n</i><b>_out</b> - Outgoing number of the analog FON port <i>1</i></li>
      <li><b>fon_phoneBook_IDs</b> - ID's of the existing phone books </li>
      <li><b>fon_phoneBook_</b><i>n</i> - Name of the phone book <i>n</i></li>
      <li><b>fon_phoneBook_URL_</b><i>n</i> - URL to the phone book <i>n</i></li>
      <br>
      <li><b>gsm_internet</b> - connection to internet established via GSM stick</li>
      <li><b>gsm_rssi</b> - received signal strength indication (0-100)</li>
      <li><b>gsm_state</b> - state of the connection to the GSM network</li>
      <li><b>gsm_technology</b> - GSM technology used for data transfer (GPRS, EDGE, UMTS, HSPA)</li>
      <br>
      <li><b>matter_</b><i>...</i><b>_node</b> - matter node (SmartGateWay or FB with matter).</li>
      <li><b>matter_</b><i>...</i><b>_vendor</b> - matter vendor/fabric (SmartGateWay or FB with matter).</li>
      <br>
      <li><b>mobileInfo_</b><i>...</i> - Mobile radio readings (USB mobile radio stick or FritzBox LTE).</li>
      <br>
      <br>
      <li><b>mac_</b><i>nn_nn_nn_nn_nn_nn</i> - MAC address and name of an active network device.<br>
      If no MAC address is provided, e.g. Switch or VPN, then the FritzBox DeviceID is used instead of the MAC address.<br>
      For a WLAN connection, "WLAN" and (as seen from the box) the sending and receiving speed and the reception strength are appended. For a LAN connection, the LAN port and the LAN speed are appended. Guest connections are marked with “gWLAN” or “gLAN”.<br>
      Inactive or removed devices first receive the value "inactive: IP address" or "inactive: DeviceID" if no IP address is available<br>
      and will be deleted with the next update.</li>
      <br>
      <li><b>ip_</b><i>nnn.nnn.nnn.nnn</i> - IP address and name of an active network device.<br>
      For a WLAN connection, "WLAN" and (as seen from the box) the sending and receiving speed and the reception strength are appended. For a LAN connection, the LAN port and the LAN speed are appended. Guest connections are marked with “gWLAN” or “gLAN”.<br>
      Inactive or removed devices will first receive the value "inactive: DeviceID" and will be deleted with the next update.</li>
      <br>
      <li><b>nbh_</b><i>nn_nn_nn_nn_nn_nn</i> - MAC address and name of an active WLAN neighborhood device.<br>
      shown is the SSID, the channel and the bandwidth. Inactive or removed devices get first the value "inactive" and will be deleted during the next update.</li>
      <br>
      <li><b>radio</b><i>nn</i> - Name of the internet radio station <i>01</i></li>
      <br>
      <li><b>tam</b><i>n</i> - Name of the answering machine <i>1</i></li>
      <li><b>tam</b><i>n</i><b>_newMsg</b> - New messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>n</i><b>_oldMsg</b> - Old messages on the answering machine <i>1</i></li>
      <li><b>tam</b><i>n</i><b>_state</b> - Current state of the answering machine <i>1</i></li>
      <br>
      <li><b>user</b><i>nn</i> - Name of user/IP <i>1</i> that is under parental control</li>
      <li><b>user</b><i>nn</i>_thisMonthTime - this month internet usage of user/IP <i>1</i> (parental control)</li>
      <li><b>user</b><i>nn</i>_todaySeconds - today's internet usage in seconds of user/IP <i>1</i> (parental control)</li>
      <li><b>user</b><i>n</i>_todayTime - today's internet usage of user/IP <i>1</i> (parental control)</li>
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
      <li><b>sip_active</b> - shows the number of active SIP.</li>
      <li><b>sip_inactive</b> - shows the number of inactive SIP.</li>
      <li><b>sip_error</b> - counting of SIP's with error. 0 == everything ok.</li>
      <br>
      <li><b>shdevice</b><i>n</i><b>_battery</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_category</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_device</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_firmwareVersion</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_manufacturer</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_model</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_status</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_tempOffset</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_temperature</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_type</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_voltage</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_power</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_current</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_consumtion</b> - </li>
      <br>
      <li><b>retStat_chgProfile</b> - Return Status: set &lt;name&gt; chgProfile &lt;number&gt; &lt;filtprofn&gt;</li>
      <li><b>retStat_enableVPNshare</b> - Return Status: set &lt;name&gt; enableVPNshare &lt;number&gt; &lt;on|off&gt;</li>
      <li><b>retStat_fritzLogInfo</b> - Return Status: get &lt;name&gt; &lt;hash&gt; &lt;...&gt;</li>
      <li><b>retStat_fritzLogExPost</b> - Return Status of the hook-function myUtilsFritzLogExPost($hash, $filter, $result) depending to: get &lt;name&gt; &lt;hash&gt; &lt;...&gt;</li>
      <li><b>retStat_lastReadout</b> - Return Status: set &lt;name&gt; update or intervall update</li>
      <li><b>retStat_lockLandevice</b> - Return Status: set &lt;name&gt; lockLandevice &lt;number> &lt;on|off&gt;</li>
      <li><b>retStat_macFilter</b> - Return Status: set &lt;name&gt; macFilter &lt;on|off&gt;</li>
      <li><b>retStat_rescanWLANneighbors</b> - Return Status: set &lt;name&gt; rescanWLANneighbors</li>
      <li><b>retStat_smartHome</b> - Return Status: set &lt;name&gt; smartHome</li>
      <li><b>retStat_wakeUpCall</b> - Return Status: set &lt;name&gt; wakeUpCall</li>
      <li><b>retStat_wlanLogExtended</b> - Return Status: set &lt;name&gt; wlanLogExtended &lt;on|off&gt;</li>
      <li><b>retStat_wlanGuestParams</b> - Return Status</li>
   </ul>
   <br>
   <a name="FRITZBOX Event-Codes"></a>
   <b>Event-Codes</b>
   <ul><br>
      <li><b>1</b> IGMPv3 multicast router n.n.n.n active</li>
      <li><b>11</b> DSL ist verf&uuml;gbar (DSL-Synchronisierung besteht mit n/n kbit/s).</li>
      <li><b>12</b> DSL-Synchronisierung beginnt (Training).</li>
      <li><b>14</b> Mobilfunkmodem initialisiert.</li>
      <li><b>23</b> Internetverbindung wurde getrennt.</li>
      <li><b>24</b> Internetverbindung wurde erfolgreich hergestellt. IP-Adresse: ..., DNS-Server: ... und ..., Gateway: ..., Breitband-PoP: ..., LineID:...</li>
      <li><b>25</b> Internetverbindung IPv6 wurde erfolgreich hergestellt. IP-Adresse: ...:...:...:...:...:...:...:...</li>
      <li><b>26</b> Internetverbindung wurde getrennt.</li>
      <li><b>27</b> IPv6-Pr&auml;fix wurde erfolgreich bezogen. Neues Pr&auml;fix: ....:....:....:....:/nn</li>
      <li><b>28</b> Internetverbindung IPv6 wurde getrennt, Pr&auml;fix nicht mehr g&uuml;ltig.</li>
      <br>
      <li><b>73</b> Anmeldung der Internetrufnummer &lt;Nummer&gt; war nicht erfolgreich. Ursache: Gegenstelle antwortet nicht. Zeit&uuml;berschreitung.</li>
      <li><b>85</b> Die Internetverbindung wird kurz unterbrochen, um der Zwangstrennung durch den Anbieter zuvorzukommen.</li>
      <br>
     <li><b>119</b> Information des Anbieters &uuml;ber die Geschwindigkeit des Internetzugangs (verf&uuml;gbare Bitrate): nnnn/nnnn kbit/s</li>
     <li><b>131</b> USB-Ger&auml;t 1003, Klasse 'USB 2.0 (hi-speed) storage', angesteckt</li>
     <li><b>132</b> USB-Ger&auml;t 1002 abgezogen</li>
     <li><b>140</b> Der USB-Speicher ZTE-MMCStorage-01 wurde eingebunden.</li>
     <br>
     <li><b>201</b> Es liegt keine St&ouml;rung der Telefonie mehr vor. Alle Rufnummern sind ab sofort wieder verf&uuml;gbar.</li>
     <li><b>205</b> Anmeldung f&uuml;r IP-Telefonieger&auml;t "Telefonie-Ger&auml;t" von IP-Adresse ... nicht erfolgreich.</li>
     <li><b>267</b> Integrierter Faxempfang wurde aktiviert auf USB-Speicher 'xxx'.</li>
     <br>
     <li><b>401</b> SIP_UNAUTHORIZED, Beschreibung steht in der Hilfe (Webinterface)</li>
     <li><b>403</b> SIP_FORBIDDEN, Beschreibung steht in der Hilfe (Webinterface)</li>
     <li><b>404</b> SIP_NOT_FOUND, Gegenstelle nicht erreichbar (local part der SIP-URL nicht erreichbar (Host schon))</li>
     <li><b>405</b> SIP_METHOD_NOT_ALLOWED</li>
     <li><b>406</b> SIP_NOT_ACCEPTED</li>
     <li><b>408</b> SIP_NO_ANSWER</li>
     <br>
     <li><b>484</b> SIP_ADDRESS_INCOMPLETE, Beschreibung steht in der Hilfe (Webinterface)</li>
     <li><b>485</b> SIP_AMBIGUOUS, Beschreibung steht in der Hilfe (Webinterface)</li>
     <br>
     <li><b>486</b> SIP_BUSY_HERE, Ziel besetzt (vermutlich auch andere Gr&uuml;nde bei der Gegenstelle)</li>
     <li><b>487</b> SIP_REQUEST_TERMINATED, Anrufversuch beendet (Gegenstelle nahm nach ca. 30 Sek. nicht ab)</li>
     <br>
     <li><b>500</b> Anmeldung an der FRITZ!Box-Benutzeroberfl&auml;che von von IP-Adresse ...</li>
     <li><b>501</b> Anmeldung an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse ... gescheitert (falsches Kennwort).</li>
     <li><b>502</b> Die FRITZ!Box-Einstellungen wurden &uuml;ber die Benutzeroberfl&auml;che ge&auml;ndert.</li>
     <li><b>503</b> Anmeldung an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse yy gescheitert (ung&uuml;ltige Sitzungskennung). Zur Sicherheit werden</li>
     <li><b>504</b> Anmeldung des Benutzers FhemUser an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse ...</li>
     <li><b>505</b> Anmeldung des Benutzers xx an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse yy gescheitert (falsches Kennwort)</li>
     <li><b>506</b> Anmeldung einer App des Benutzers FhemUser von IP-Adresse</li>
     <li><b>510</b> Anmeldung einer App mit unbekanntem Anmeldenamen von IP-Adresse ... gescheitert.</li>
     <br>
     <li><b>689</b> WLAN-Anmeldung ist gescheitert : Die MAC-Adresse des WLAN-Ger&auml;ts ist gesperrt. MAC-Adresse</li>
     <li><b>692</b> WLAN-Anmeldung ist gescheitert : Verbindungsaufbau fehlgeschlagen. MAC-Adresse</li>
     <li><b>705</b> WLAN-Ger&auml;t Anmeldung gescheitert (5 GHz): ung&uuml;ltiger WLAN-Schl&uuml;ssel. MAC-Adresse</li>
     <li><b>706</b> [...] WLAN-Ger&auml;t Anmeldung am Gastzugang gescheitert (n,n GHz): ung&uuml;ltiger WLAN-Schl&uuml;ssel. MAC-Adresse: nn:nn:nn:nn:nn:nn.</li>
     <li><b>748</b> [...] WLAN-Ger&auml;t angemeldet (n,n GHz), nn Mbit/s, PC-..., IP ..., MAC ... .</li>
     <li><b>752</b> [...] WLAN-Ger&auml;t hat sich abgemeldet (n,n GHz), PC-..., IP ..., MAC ....</li>
     <li><b>754</b> [...] WLAN-Ger&auml;t wurde abgemeldet (.,. GHz), PC-..., IP ..., MAC ... .</li>
     <li><b>756</b> WLAN-Ger&auml;t hat sich neu angemeldet (n,n GHz), nn Mbit/s, Ger&auml;t, IP ..., MAC ....</li>
     <li><b>782</b> WLAN-Anmeldung ist gescheitert : Die erneute Anmeldung ist aufgrund aktiver "Unterst&uuml;tzung f&uuml;r gesch&uuml;tzte Anmeldungen von WLAN-Ger&auml;ten (PMF)</li>
     <li><b>786</b> 5-GHz-Band für [Anzahl] Min. nicht nutzbar wegen Pr&uuml;fung auf bevorrechtigten Nutzer (z. B. Radar) auf dem gew&auml;hlten Kanal (Frequenz [GHz])</li>
     <li><b>790</b> Radar wurde auf Kanal [Nummer] (Frequenz [Ziffer] GHz) erkannt, automatischer Kanalwechsel wegen bevorrechtigtem Benutzer ausgef&uuml;hrt</li>
     <br>
    <li><b>2104</b> Die Systemzeit wurde erfolgreich aktualisiert von Zeitserver nnn.nnn.nnn.nnn .</li>
     <br>
    <li><b>2364</b> Ein neues Ger&auml;t wurde an der FRITZ!Box angemeldet (Schnurlostelefon)</li>
    <li><b>2358</b> Einstellungen wurden gesichert. Diese &auml;nderung erfolgte von Ihrem Heimnetzger&auml;t ... (IP-Adresse: ...)</li>
    <li><b>2380</b> Es besteht keine Verbindung mehr zu den verschl&uuml;sselten DNS-Servern.</li>
    <li><b>2383</b> Es wurde erfolgreich eine Verbindung - samt vollst&auml;ndiger Validierung - zu den verschl&uuml;sselten DNS-Servern aufgebaut.</li>
    <li><b>2380</b> Es besteht keine Verbindung mehr zu den verschl&uuml;sselten DNS-Servern.</li>
    <li><b>3330</b> Verbindung zum Online-Speicher hergestellt.</li>
   </ul>
   <br>
</div>

=end html

=begin html_DE

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
<div>
   Steuert gewisse Funktionen eines FRITZ!BOX Routers. Verbundene Fritz!Fon's (MT-F, MT-D, C3, C4) k&ouml;nnen als Signalger&auml;te genutzt werden. MP3-Dateien und Text (Text2Speech) k&ouml;nnen als Klingelton oder einem angerufenen Telefon abgespielt werden.
   <br>
   F&uuml;r detailierte Anleitungen bitte die <a href="http://www.fhemwiki.de/wiki/FRITZBOX"><b>FHEM-Wiki</b></a> konsultieren und erg&auml;nzen.
   <br><br>
   Die Steuerung erfolgt teilweise &uuml;ber die offizielle TR-064-Schnittstelle und teilweise &uuml;ber undokumentierte Schnittstellen zwischen Webinterface und Firmware Kern.<br>
   <br>
   Das Modul wurde auf der FRITZ!BOX 7590, 7490 und dem FRITZ!WLAN Repeater 1750E mit Fritz!OS 7.50 und h&ouml;her getestet.
   <br>
   Bitte auch die anderen FRITZ!BOX-Module beachten: <a href="#SYSMON">SYSMON</a> und <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>Das Modul nutzt das Perlmodule 'JSON::XS', 'LWP', 'SOAP::Lite' f&uuml;r den Fernzugriff.</i>
   <br>
   Es muss zwingend das Attribut boxUser nach der Definition des Device gesetzt werden.
   <br><br>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX &lt;host&gt;</code>
      <br>
      Der Parameter <i>host</i> ist die Web-Adresse (Name oder IP) der FRITZ!BOX / Repeater.
      <br><br>
      Beispiel: <code>define Fritzbox FRITZBOX fritz.box</code>
      <br><br>
   </ul>

   <a name="FRITZBOXset"></a>
   <b>Set</b>
   <ul>
      <li><a name="blockIncomingPhoneCall"></a>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall Parameters</code></dt>
         <ul>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;new&gt; &lt;name&gt; &lt;phonenumber&gt; &lt;home|work|mobile|fax_work&gt;</code></dt>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;tmp&gt; &lt;name&gt; &lt;phonenumber&gt; &lt;home|work|mobile|fax_work&gt; &lt;dayTtime&gt;</code></dt>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;chg&gt; &lt;name&gt; &lt;phonenumber&gt; &lt;home|work|mobile|fax_work&gt; &lt;uid&gt;</code></dt>
         <dt><code>set &lt;name&gt; blockIncomingPhoneCall &lt;del&gt; &lt;uid&gt;</code></dt>
         </ul>
         <ul>
         <dt>&lt;new&gt; erzeugt einen neuen Eintrag für eine Rufsperre für ankommende Anrufe </dt>
         <dt>&lt;tmp&gt; erzeugt einen neuen Eintrag für eine Rufsperre für ankommende Anrufe, der zum Zeitpunkt &lt;dayTtime&gt; wieder gelöscht wird </dt>
         <dt>&lt;chg&gt; ändert einen bestehenden Eintrag für eine Rufsperre für ankommende Anrufe </dt>
         <dt>&lt;del&gt; löscht einen bestehenden Eintrag für eine Rufsperre für ankommende Anrufe </dt>
         <dt>&lt;name&gt; eindeutiger Name der Rufsperre. Leerzeichen sind nicht zulässig </dt>
         <dt>&lt;phonenumber&gt; Rufnummer, die gesperrt werden soll </dt>
         <dt>&lt;home|work|mobile|fax_work&gt; Klassifizierung der Rufnummer </dt>
         <dt>&lt;uid&gt; UID der Rufsperre. Eindeutig für jeden Rufsperren Namen. Steht im Reading blocking_&lt;phonenumber&gt; </dt>
         <dt>&lt;dayTtime&gt; Fhem Timestamp im Format: yyyy-mm-ddThh:mm:ss zur Generierung eines 'at' Befehls </dt>
         </ul>
         Beispiel für eine tägliche Rufsperre von 20:00 Uhr bis zum Folgetag 06:00 Uhr<br>
         <dt><code>
         defmod startNightblocking at *22:00:00 {\
           fhem('set FritzBox blockIncomingPhoneCall tmp nightBlocking 012345678 home ' .  strftime("%Y-%m-%d", localtime(time + DAYSECONDS)) . 'T06:00:00', 1);;\
         }
         </code></dt><br>
      </li><br>

      <li><a name="call"></a>
         <dt><code>set &lt;name&gt; call &lt;number&gt; [duration]</code></dt>
         <br>
         Ruft f&uuml;r 'Dauer' Sekunden (Standard 60 s) die angegebene Telefonnummer von einem internen Telefonanschluss an (Standard ist 1). Wenn der Angerufene abnimmt, h&ouml;rt er die Wartemusik.
         Der interne Telefonanschluss klingelt ebenfalls.
         <br>
         Das Klingeln erfolgt über die Wählhilfe, die über "Telefonie/Anrufe/Wählhilfe" aktiviert werden muss.<br>
         Eventuell muss über die Weboberfläche der Fritz!Box ein anderer Port eingestellt werden. Der aktuelle steht in "box_stdDialPort".
      </li><br>

      <li><a name="checkAPIs"></a>
         <dt><code>set &lt;name&gt; checkAPIs</code></dt>
         <br>
         Startet eine erneute Abfrage der exitierenden Programmierschnittstellen der FRITZ!BOX.
      </li><br>

      <li><a name="chgProfile"></a>
         <dt><code>set &lt;name&gt; chgProfile &lt;number&gt; &lt;filtprof<i>n</i>&gt;</code></dt><br>
         &lt;number&gt; ist die ID des landevice<i>n..n</i> oder dessen MAC <br>
         &auml;ndert das Profile filtprof mit der Nummer 1..n des Netzger&auml;ts.<br>
         Die Ausf&uuml;hrung erfolgt non Blocking. Die R&uuml;ckmeldung erfolgt im Reading: retStat_chgProfile <br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her. <br>
      </li><br>

      <li><a name="dect"></a>
         <dt><code>set &lt;name&gt; dect &lt;on|off&gt;</code></dt>
         <br>
         Schaltet die DECT-Basis der Box an oder aus.
         <br>
         Ben&ouml;tigt mindestens FRITZ!OS 7.21
      </li><br>

      <li><a name="dectRingblock"></a>
         <dt><code>set &lt;name&gt; dectRingblock &lt;dect&lt;nn&gt;&gt; &lt;on|off&gt;</code></dt>
         <br>
         Aktiviert / Deaktiviert die Klingelsperre f&uuml;r das DECT-Telefon mit der ID dect<n>. Die ID kann der Readingliste
         des &lt;name&gt; Device entnommen werden.<br><br>
          <code>set &lt;name&gt; dectRingblock &lt;dect&lt;nn&gt;&gt; &lt;days&gt; &lt;hh:mm-hh:mm&gt; [lmode:on|off] [emode:on|off]</code><br><br>
         Aktiviert / Deaktiviert die Klingelsperre f&uuml;r das DECT-Telefon mit der ID dect<n> f&uuml;r Zeitr&auml;ume:<br>
         &lt;hh:mm-hh:mm&gt; = Uhrzeit_von bis Uhrzeit_bis<br>
         &lt;days&gt; = wd f&uuml;r Werktags, ed f&uuml;r Jeden Tag, we f&uuml;r Wochenende<br>
         lmode:on|off = lmode definiert die Sperre. Bei off ist sie aus, au&szlig;er f&uuml;r den angegebenen Zeitraum.<br>
                                                    Bei on ist die Sperre an, au&szlig;er f&uuml;r den angegebenen Zeitraum<br>
         emode:on|off = emode schaltet Events bei gesetzter Klingelsperre ein/aus. Siehe hierzu die FRITZ!BOX Dokumentation<br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="diversity"></a>
         <dt><code>set &lt;name&gt; diversity &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         Schaltet die Rufumleitung (Nummer 1, 2 ...) f&uuml;r einzelne Rufnummern an oder aus.
         <br>
         Achtung! Es lassen sich nur Rufumleitungen f&uuml;r einzelne angerufene Telefonnummern (also nicht "alle") und <u>ohne</u> Abh&auml;ngigkeit von der anrufenden Nummer schalten.
         Es muss also ein <i>diversity</i>-Ger&auml;tewert geben.
         <br>
         Ben&ouml;tigt die API: TR064 (>=6.50).
      </li><br>

      <li><a name="enableVPNshare"></a>
         <dt><code>set &lt;name&gt; enableVPNshare &lt;number&gt; &lt;on|off&gt;</code></dt>
         <br>
         &lt;number&gt; ist die Nummer des Readings vpn<i>n..n</i>_user.. oder _box <br>
         Schaltet das VPN share mit der Nummer nn an oder aus.<br>
         Die Ausf&uuml;hrung erfolgt non Blocking. Die R&uuml;ckmeldung erfolgt im Reading: retStat_enableVPNshare <br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="energyMode"></a>
         <dt><code>set &lt;name&gt; energyMode &lt;default|eco&gt;</code></dt>
         <br>
         Ändert den Energiemodus der FRITZ!Box. &lt;default&gt; verwendet einen ausgewogenen Modus bei optimaler Leistung.<br>
         Die wichtigsten Energiesparfunktionen sind bereits aktiv.<br>
         &lt;eco&gt; verringert den Stromverbrauch.<br>
         Ben&ouml;tigt FRITZ!OS 7.50 oder h&ouml;her.
      </li><br>

      <li><a name="guestWlan"></a>
         <dt><code>set &lt;name&gt; guestWlan &lt;on|off&gt;</code></dt>
         <br>
         Schaltet das G&auml;ste-WLAN an oder aus. Das G&auml;ste-Passwort muss gesetzt sein. Wenn notwendig wird auch das normale WLAN angeschaltet.
      </li><br>

      <li><a name="inActive"></a>
         <dt><code>set &lt;name&gt; inActive &lt;on|off&gt;</code></dt>
         <br>
         Deaktiviert temporär den intern Timer.
         <br>
      </li><br>

      <li><a name="ledSetting"></a>
         <dt><code>set &lt;name&gt; ledSetting &lt;led:on|off&gt; und/oder &lt;bright:1..3&gt; und/oder &lt;env:on|off&gt;</code></dt>
         <br>
         Die Anzahl der Parameter variiert von FritzBox zu Fritzbox zu Repeater.<br>
         Die Möglichkeiten können über get &lt;name&gt; luaInfo ledSettings geprüft werden.<br><br>
         &lt;led:<on|off&gt; schaltet die LED's ein oder aus.<br>
         &lt;bright:1..3&gt; reguliert die Helligkeit der LED's von 1=schwach, 2=mittel bis 3=sehr hell.<br>
         &lt;env:on|off&gt; schaltet Regelung der Helligkeit in abhängigkeit der Umgebungshelligkeit an oder aus.<br><br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.<br><br>
         Als besonderer Parameter ist <code>set &lt;name&gt; ledSetting &lt;notifyoff:notify_ID&gt;</code> hinzugekommen.<br>
         Hiermit kann die rote Info-LED der FritzBox, die besondere Betriebszustände signalisiert, resetet werden.
      </li><br>

      <li><a name="lockFilterProfile"></a>
         <dt><code>set &lt;name&gt; lockFilterProfile &lt;profile name&gt; &lt;status:never|unlimited&gt; &lt;bpjm:on|off&gt;</code></dt>
         <br>
         &lt;profile name&gt; Name des Zugangsprofils<br>
         &lt;status:&gt; schaltet das Profil aus (never) oder ein (unlimited)<br>
         &lt;bpjm:&gt; schaltet den Jugendschutz ein/aus<br>
         Die Parameter &lt;status:&gt; / &lt;bpjm:&gt; können einzeln oder gemeinsam angegeben werden.<br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="lockLandevice"></a>
         FritzOS < 8.00: <dt><code>set &lt;name&gt; lockLandevice &lt;number|mac&gt; &lt;on|off|rt&gt;</code></dt>
         FritzOS >= 8.00: <dt><code>set &lt;name&gt; lockLandevice &lt;number|mac&gt; &lt;on|off|rt|rtoff&gt;</code></dt>
         <br>
         &lt;number&gt; ist die ID des landevice<i>n..n</i><br>
         Schaltet das Blockieren des Netzger&auml;t on(blocked), off(unlimited) oder rt(realtime).<br>
         Die Ausf&uuml;hrung erfolgt non Blocking. Die R&uuml;ckmeldung erfolgt im Reading: retStat_lockLandevice <br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="macFilter"></a>
         <dt><code>set &lt;name&gt; macFilter &lt;on|off&gt;</code></dt>
         <br>
         Schaltet den MAC Filter an oder aus. In der FRITZ!BOX unter "neue WLAN Ger&auml;te zulassen/sperren<br>
         Die Ausf&uuml;hrung erfolgt non Blocking. Die R&uuml;ckmeldung erfolgt im Reading: retStat_macFilter <br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="phoneBookEntry"></a>
         <dt><code>set &lt;name&gt; phoneBookEntry &lt;new&gt; &lt;PhoneBookID&gt; &lt;category&gt; &lt;entryName&gt; &lt;home|mobile|work|fax_work|other:phoneNumber&gt; [home|mobile|work|fax_work|other:phoneNumber] ...</code></dt>
         <br>
         <dt><code>set &lt;name&gt; phoneBookEntry &ltdel&gt; &lt;PhoneBookID&gt; &lt;entryName&gt;</code></dt>
         <br>
         &lt;PhoneBookID&gt; kann aus dem neuen Reading fon_phoneBook_IDs entnommen werden.<br>
         &lt;category&gt; 0 oder 1. 1 steht für wichtige Person.<br>
         &lt;entryName&gt; Name des Telefonbucheintrags<br>
      </li><br>

      <li><a name="password"></a>
         <dt><code>set &lt;name&gt; password &lt;password&gt;</code></dt>
         <br>
         Speichert das Passwort f&uuml;r den Fernzugriff.
      </li><br>

      <li><a name="reboot"></a>
         <dt><code>set &lt;name&gt; reboot &lt;Minuten&gt;</code></dt>
         <br>
         Startet die FRITZ!BOX in &lt;Minuten&gt; neu. Wird dieses 'set' ausgef&uuml;hrt, so wird ein einmaliges 'at' im Raum 'Unsorted' erzeugt,
         &uuml;ber das dann der Reboot ausgef&uuml;hrt wird. Das neue 'at' hat den Devicenamen: act_Reboot_&lt;Name FB Device&gt;.
      </li><br>

      <li><a name="rescanWLANneighbors"></a>
         <dt><code>set &lt;name&gt; rescanWLANneighbors</code></dt>
         <br>
         L&ouml;st eine Scan der WLAN Umgebung aus.
         Die Ausf&uuml;hrung erfolgt non Blocking. Die R&uuml;ckmeldung erfolgt im Reading: retStat_rescanWLANneighbors<br>
      </li><br>

      <li><a name="ring"></a>
         <dt><code>set &lt;name&gt; ring &lt;intNumbers&gt; [duration] [show:Text]  [say:Text | play:MP3URL]</code></dt>
         <br>
         <dt>Beispiel:</dt>
         <dd>
         <code>set &lt;name&gt; ring 611,612 5</code>
         <br>
         L&auml;sst die internen Nummern f&uuml;r "Dauer" Sekunden und (auf Fritz!Fons) mit dem übergebenen "ring tone" lingeln.
         <br>
         Mehrere interne Nummern m&uuml;ssen durch ein Komma (ohne Leerzeichen) getrennt werden.
         <br>
         Standard-Dauer ist 5 Sekunden. Es kann aber zu Verz&ouml;gerungen in der FRITZ!BOX kommen. Standard-Klingelton ist der interne Klingelton des Ger&auml;tes.
         Der Klingelton wird f&uuml;r Rundrufe (9 oder 50) ignoriert.
         <br>
         Wenn der Anruf angenommen wird, h&ouml;rt der Angerufene die Wartemusik (music on hold).
         <br>
         Je nach Fritz!OS kann das beschriebene Verhalten abweichen.</dd>
      </li><br>

      <li><a name="smartHome"></a>
         <dt><code>set &lt;name&gt; smartHome Parameters</code></dt>

         <ul>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;tempOffset:value&gt;</code></dt>
         <dd>ändert den Temperatur Offset auf den Wert:value für das SmartHome Gerät mit der angegebenen ID.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;tmpAdjust:value&gt;</code></dt>
         <dd>setzt den Heizköperregeler temporär auf die Temperatur: value.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;tmpPerm:0|1&gt;</code></dt>
         <dd>setzt den Heizköperregeler auf permanent aus oder an.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;switch:0|1&gt;</code></dt>
         <dd>schaltet den Steckdosenadapter aus oder an.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;preDefSave:nameEinstellung&gt;</code></dt>
         <dd>speichert die Einstellungen für das Device unter dem angegeben Namen.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;preDefDel:nameEinstellung&gt;</code></dt>
         <dd>löscht die Einstellungen für das Device unter dem angegeben Namen.</dd>
         <br>
         <dt><code>set &lt;name&gt; smartHome &lt;deviceID&gt; &lt;preDefLoad:[deviceID_load:]nameEinstellung[:A|:G]&gt;</code></dt>
         <dd>lädt eine gespeicherte Einstellung in die Fritzbox.
         Wird [deviceID_load:] angegeben, so wird die gespeicherte Einstellung eines anderen funktional identischen Device in die Fritzbox geladen.<br>
         Bei Devices vom Typ 'socket' kann noch differenziert werden, ob alle Einstellungen oder nur die der Webseite :A == 'Automatisch schalten' oder :G == 'Allgemein' geladen werden sollen.
         </dd>
         </ul>
         Die ID kann über <code>get &lt;name&gt; luaInfo &lt;smartHome&gt;</code> ermittelt werden.<br><br>
         Das Ergebnis des Befehls wird im Reading retStat_smartHome abgelegt.
         <br>
         Benötigt FRITZ!OS 7.21 oder höher.

      </li><br>

      <li><a name="switchIPv4DNS"></a>
         <dt><code>set &lt;name&gt; switchIPv4DNS &lt;provider|other&gt;</code></dt>
         <br>
         &Auml;ndert den IPv4 DNS auf Internetanbieter oder einem alternativen DNS (sofern in der FRITZ!BOX hinterlegt).<br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="tam"></a>
         <dt><code>set &lt;name&gt; tam &lt;number&gt; &lt;on|off&gt;</code></dt>
         Schaltet den Anrufbeantworter (Nummer 1, 2 ...) an oder aus.
         Der Anrufbeantworter muss zuvor auf der FRITZ!BOX eingerichtet werden.
      </li><br>

      <li><a name="update"></a>
         <dt><code>set &lt;name&gt; update</code></dt>
         <br>
         Startet eine Aktualisierung der Ger&auml;te Readings.
      </li><br>

      <li><a name="wakeUpCall"></a>
         <dt><code>set &lt;name&gt; wakeUpCall &lt;alarm1|alarm2|alarm3&gt; &lt;off&gt;</code></dt>
         <dt><code>set &lt;name&gt; wakeUpCall &lt;alarm1|alarm2|alarm3&gt; &lt;Device Nummer|Name&gt; &lt;daily|only_once&gt; &lt;hh:mm&gt;</code></dt>
         <dt><code>set &lt;name&gt; wakeUpCall &lt;alarm1|alarm2|alarm3&gt; &lt;Device Nummer|Name&gt; &lt;per_day&gt; &lt;hh:mm&gt; &lt;mon:0|1 tue:0|1 wed:0|1 thu:0|1 fri:0|1 sat:0|1 sun:0|1&gt;</code></dt>
         <br>
         Inaktiviert oder stellt den Wecker: alarm1, alarm2, alarm3.
         <br>
         Wird der Device Name gentutzt, so ist ein Leerzeichen im Namen durch %20 zu ersetzen.
         <br>
         Die Device Nummer steht im Reading <b>dect</b><i>n</i><b>_device</b> or <b>fon</b><i>n</i><b>_device</b>
         <br>
         Wird im Reading <b>dect</b><i>n</i> or <b>fon</b><i>n</i> "redundant name in FB" angezeigt, dann kann der Device Name nicht genutzt werden..
         <br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
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

      <li><a name="wlanLogExtended"></a>
         <dt><code>set &lt;name&gt; wlanLogExtended &lt;on|off&gt;</code></dt>
         <br>
         Schaltet "Auch An- und Abmeldungen und erweiterte WLAN-Informationen protokollieren" an oder aus.
         <br>
         Status in Reading: retStat_wlanLogExtended
      </li><br>

      <li><a name="wlanGuestParams"></a>
         <dt><code>set &lt;name&gt; wlanGuestParams &lt;param:value&gt; [&lt;param:value&gt; ...]</code></dt>
         <br>
         Mögliche Kombinationen aus &lt;param:value&gt;
         <ul>
         <li>&lt;wlan:on|off&gt;</li>
         <li>&lt;ssid:name&gt;</li>
         <li>&lt;psk:password&gt;</li>
         <li>&lt;mode:private|public&gt;</li>
         <li>&lt;tmo:minutes&gt; , tmo == timeout in Minuten (15 - 4320). Wird tmo gesetzt, so wird automatisch isTimeoutActive auf on gesetzt.</li>
         <li>&lt;isTimeoutActive:on|off&gt;</li>
         <li>&lt;timeoutNoForcedOff:on|off&gt;</li>
         </ul>
         Status in Reading: retStat_wlanGuestParams
      </li><br>
   </ul>

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><a name="fritzLog"></a>
         <dt><code>get &lt;name&gt; fritzLog &lt;table&gt; &lt;all | sys | wlan | usb | net | fon&gt;</code></dt>
         <br>
         &lt;table&gt; zeigt das Ergebnis im FhemWeb als Tabelle an.
         <br><br>
         <dt><code>get &lt;name&gt; fritzLog &lt;hash&gt; &lt;all | sys | wlan | usb | net | fon&gt; [on|off]</code></dt>
         <br>
         &lt;hash&gt; leitet das Ergebnis als Standard an eine Funktion (non blocking) myUtilsFritzLogExPostnb($hash, $filter, $result) f&uuml;r eigene Verarbeitung weiter.
         <br>
         &lt;hash&gt; &lt;off&gt; leitet das Ergebnis an eine Funktion (blocking) myUtilsFritzLogExPost($hash, $filter, $result) f&uuml;r eigene Verarbeitung weiter.
         <br>
         wobei:
         <br>
         $hash -> Fhem Device hash,<br>
         $filter -> gew&auml;hlter Log Filter,<br>
         $result -> R&uuml;ckgabe der data.lua Abfrage im JSON Format.<br>
         <br><br>
         &lt;all | sys | wlan | usb | net | fon&gt; &uuml;ber diese Parameter erfolgt die Filterung der Log-Informationen.
         <br><br>
         [on|off] gibt bei Parameter &lt;hash&gt; an, ob die Weiterverarbeitung blocking [off] oder non blocking [on] (default) erfolgt.
         <br><br>
	  Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
         <br><br>
         R&uuml;ckmeldung in den Readings:<br>
         retStat_fritzLogExPost = Status des Funktionsaufrufes myUtilsFritzLogExPostnb / myUtilsFritzLogExPost<br>
         retStat_fritzLogInfo = Status der Log Informations Abfrage.
         <br>
      </li><br>

      <li><a name="lanDeviceInfo"></a>
         <dt><code>get &lt;name&gt; lanDeviceInfo &lt;number&gt;</code></dt>
         <br>
         &lt;number&gt; ist die ID des landevice<i>n..n</i> oder dessen MAC
         Zeigt Informationen &uuml;ber das Netzwerkger&auml;t an.<br>
         Bei vorhandener Kindersicherung, nur dann wird gemessen, wird zusätzlich folgendes ausgegeben:<br>
         USEABLE: Zuteilung in Sekunden<br>
         UNSPENT: nicht genutzt in Sekunden<br>
         PERCENT: in Prozent<br>
         USED: genutzt in Sekunden<br>
         USEDSTR: zeigt die genutzte Zeit in hh:mm vom Kontingent hh:mm<br>
	 Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.
      </li><br>

      <li><a name="luaData"></a>
         <dt><code>get &lt;name&gt; luaData [json] &lt;Command&gt;</code></dt>
         <br>
         F&uuml;hrt Komandos &uuml;ber data.lua aus. Sofern in den Parametern ein Semikolon vorkommt ist dieses durch #x003B zu ersetzen.<br>
         Optional kann als erster Parameter json angegeben werden. Es wir dann für weitere Verarbeitungen das Ergebnis als JSON zurück gegeben.
      </li><br>

      <li><a name="luaDectRingTone"></a>
         Experimentel siehe: <a href="https://forum.fhem.de/index.php?msg=1274864"><b>FRITZBOX - Fritz!Box und Fritz!Fon sprechen</b></a><br>
         <dt><code>get &lt;name&gt; luaDectRingTone &lt;Command&gt;</code></dt>
         <br>
      </li><br>

      <li><a name="luaFunction"></a>
         <dt><code>get &lt;name&gt; luaFunction &lt;funktion&gt;</code></dt>
         <br>
         Führt AVM lua Funktionen aus.<br>
         funktion: <code>&lt;Pfad/luaFunktion?&gt;&lt;Parameter&gt;</code><br>
         funktion: <code>internet/inetstat_monitor.lua?myXhr=1&action=disconnect&useajax=1&xhr=1</code> holt eine neue IP-Adresse für die FritzBox.
      </li><br>

      <li><a name="luaInfo"></a>
         <dt><code>get &lt;name&gt; luaInfo &lt;landevices|ledSettings|smartHome|vpnShares|globalFilters|kidProfiles|userInfos|wlanNeighborhood|mobileInfo|docsisInformation&gt;</code></dt>
         <br>
         Ben&ouml;tigt FRITZ!OS 7.21 oder h&ouml;her.<br>
         lanDevices -> Generiert eine Liste der aktiven und inaktiven Netzwerkger&auml;te.<br>
         ledSettings -> Generiert eine Liste der LED Einstellungen mit einem Hinweis welche set ... ledSetting möglich sind.<br>
         smartHome -> Generiert eine Liste SmartHome Geräte und gespeicherten Gerätedefinitionen (Zeitschaltung, Tmperaturen, ...).<br>
         vpnShares -> Generiert eine Liste der aktiven und inaktiven VPN Shares.<br>
         globalFilters -> Zeigt den Status (on|off) der globalen Filter: globalFilterNetbios, globalFilterSmtp, globalFilterStealth, globalFilterTeredo, globalFilterWpad<br>
         kidProfiles -> Generiert eine Liste der Zugangsprofile.<br>
         userInfos -> Generiert eine Liste der FRITZ!BOX Benutzer.<br>
         wlanNeighborhood -> Generiert eine Liste der WLAN Nachbarschaftsger&auml;te.<br>
         mobileInfo -> Informationen über Mobilfunk.<br>
         docsisInformation -> Zeigt Informationen zu DOCSIS an (nur Cable).<br>
      </li><br>

      <li><a name="luaQuery"></a>
         <dt><code>get &lt;name&gt; luaQuery &lt;abfrage&gt;</code></dt>
         <br>
         Zeigt Informations durch Abfragen der query.lua.<br>
         abfrage: <code>&lt;queryFunction:&gt;&lt;queryRequest&gt;</code><br>
         abfrage: <code>uimodlogic:status/uptime_hours</code> holt die Stunden, die die FritzBox seit dem letzten Neustart ununterbrochen läuft.
      </li><br>

      <li><a name="smartHomePreDef"></a>
         <dt><code>get &lt;name&gt; smartHomePreDef [deviceID [Saved-PreDef-Name]]</code></dt>
         <br>
         <dt><code>get &lt;name&gt; smartHomePreDef</code></dt>
         <dd>listet alle gespeicherten Einstellungen auf. Diese Auflistung wird auch bei get <name> luaInfo smartHome mit angezeigt.</dd>
         <dt><code>get &lt;name&gt; smartHomePreDef &lt;deviceID&gt;</code></dt>
         <dd>listet alle für das Device gespeicherten Einstellungen auf.</dd>
         <dt><code>get &lt;name&gt; smartHomePreDef &lt;deviceID&gt; &lt;Saved-PreDef-Name&gt;</code></dt>
         <dd>zeigt die für das Device unter dem Saved-PreDef Namen gespeicherten Daten.</dd>
         <br>
      </li><br>

      <li><a name="tr064Command"></a>
         <dt><code>get &lt;name&gt; tr064Command &lt;service&gt; &lt;control&gt; &lt;action&gt; [[argName1 argValue1] ...]</code></dt>
         <br>
         F&uuml;hrt &uuml;ber TR-064 Aktionen aus (siehe <a href="http://avm.de/service/schnittstellen/">Schnittstellenbeschreibung</a> von AVM).
         <br>
         argValues mit Leerzeichen m&uuml;ssen in Anf&uuml;hrungszeichen eingeschlossen werden.
         <br>
         Beispiel: <code>get &lt;name&gt; tr064Command X_AVM-DE_OnTel:1 x_contact GetDECTHandsetInfo NewDectID 1</code>
         <br>
      </li><br>

      <li><a name="tr064ServiceList"></a>
         <dt><code>get &lt;name&gt; tr064ServiceListe</code></dt>
         <br>
         Zeigt die Liste der TR-064-Dienste und Aktionen, die auf dem Ger&auml;t erlaubt sind.
      </li><br>
   </ul>

   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><a name="INTERVAL"></a>
         <dt><code>INTERVAL &lt;seconds&gt;</code></dt>
         <br>
         Abfrage-Interval. Standard ist 300 (Sekunden). Der kleinste m&ouml;gliche Wert ist 60 (Sekunden).
      </li><br>

      <li><a name="verbose"></a>
        <dt><code>attr &lt;name&gt; verbose &lt;0 .. 5&gt;</code></dt>
        Wird verbose auf den Wert 5 gesetzt, so werden alle Log-Daten in eine eigene Log-Datei geschrieben.<br>
        Name der Log-Datei:deviceName_debugLog.dlog<br>
        Im INTERNAL Reading DEBUGLOG wird ein Link &lt;DEBUG Log kann hier eingesehen werden&gt; zur dierekten Ansicht des Logs angezeigt.<br>
        Weiterhin wird ein FileLog Device:deviceName_debugLog im selben Raum und der selben Gruppe wie das FRITZBOX Device erzeugt.<br>
        Wird verbose auf kleiner 5 gesetzt, so wird das FileLog Device gelöscht, die Log-Datei bleibt erhalten.
        Wird verbose gelöscht, so werden das FileLog Device und die Log-Datei gelöscht.
      </li><br>

      <li><a name="FhemLog3Std"></a>
        <dt><code>attr &lt;name&gt; FhemLog3Std &lt0 | 1&gt;</code></dt>
        Wenn gesetzt, werden die Log Informationen im Standard Fhem Format geschrieben.<br>
        Sofern durch ein verbose 5 die Ausgabe in eine seperate Log-Datei aktiviert wurde, wird diese beendet.<br>
        Die seperate Log-Datei und das zugehörige FileLog Device werden gelöscht.<br>
        Wird das Attribut auf 0 gesetzt oder gelöscht und ist das Device verbose auf 5 gesetzt, so werden alle Log-Daten in eine eigene Log-Datei geschrieben.<br>
        Name der Log-Datei:deviceName_debugLog.dlog<br>
        Im INTERNAL Reading DEBUGLOG wird ein Link &lt;DEBUG Log kann hier eingesehen werden&gt; zur direkten Ansicht des Logs angezeigt.<br>
      </li><br>

      <li><a name="reConnectInterval"></a>
         <dt><code>reConnectInterval &lt;seconds&gt;</code></dt>
         <br>
         reConnect-Interval. Nach Netzwerkausfall oder FritzBox Nichtverfügbarkeit. Standard ist 180 (Sekunden). Der kleinste m&ouml;gliche Wert ist 55 (Sekunden).
      </li><br>

      <li><a name="maxSIDrenewErrCnt"></a>
         <dt><code>maxSIDrenewErrCnt &lt;5..20&gt;</code></dt>
         <br>
         Anzahl der in Folge zulässigen Fehler beim abholen der SID von der FritzBox. Minimum ist fünf, maximum ist zwanzig. Standardwert ist 5.<br>
         Wird die Anzahl überschritten, dann wird der interne Timer deaktiviert.
      </li><br>

      <li><a name="nonblockingTimeOut"></a>
         <dt><code>nonblockingTimeOut &lt;30|35|40|50|75|100|125&gt;</code></dt>
         <br>
         Timeout f&uuml;r das regelm&auml;&szlig;ige Holen der Daten von der Fritz!Box. Standard ist 55 (Sekunden).
      </li><br>

      <li><a name="setgetTimeout"></a>
         <dt><code>setgetTimeout&lt;10|30|40|50|75|100|125&gt;</code></dt>
         <br>
         Timeout f&uuml;r das Ausführen von non blocking set/get Befehlen. Standard ist 10 (Sekunden).
      </li><br>

      <li><a name="boxUser"></a>
         <dt><code>boxUser &lt;user name&gt;</code></dt>
         <br>
         Benutzername für den TR064- oder einen anderen webbasierten Zugang. Die aktuellen FritzOS Versionen verlangen zwingend einen Benutzername f&uuml;r das Login.
      </li><br>

      <li><a name="deviceInfo"></a>
         <dt><code>deviceInfo &lt;ipv4, name, uid, connection, speed, rssi, statIP, _noDefInf_, _default_&, space, comma&gt;</code></dt>
         <br>
         Mit diesem Attribut kann der Inhalt der Device Readings (mac_...) gestaltet werden. Ist das Attribut nicht gesetzt, setzt
         sich der Inhalt wie folgt zusammen:<br>
         <code>name,[uid],(connection: speed, rssi)</code><br><br>

         Wird der Parameter <code>_noDefInf_</code> gesetzt, die Reihenfolge ind der Liste spielt hier keine Rolle, dann werden nicht vorhandene Werte der Netzwerkverbindung
         mit noConnectInfo (LAN oder WLAN nicht verf&uuml;gbar) und noSpeedInfo (Geschwindigkeit nicht verf&uuml;gbar) angezeigt.<br><br>
         &Uuml;ber das freie Eingabefeld k&ouml;nnen eigene Text oder Zeichen hinzugef&uuml;gt und zwischen die festen Paramter eingeordnet werden.<br>
         Hierbei gibt es folgende spezielle Texte:<br>
         <code>space</code> => wird zu einem Leerzeichen.<br>
         <code>comma</code> => wird zu einem Komma.<br>
         <code>_default_...</code> => ersetzt das default Leerzeichen als Trennzeichen.<br>
         Beispiele:<br>
         <code>_default_commaspace</code> => wird zu einem Komma gefolgt von einem Leerzeichen als Trenner.<br>
         <code>_default_space:space</code> => wird zu einem einem Leerzeichen:Leerzeichen als Trenner.<br>
         Es werden nicht alle m&ouml;glichen "unsinnigen" Kombinationen abgefangen. Es kann also auch mal schief gehen.
         <br>
      </li><br>

      <li><a name="disableBoxReadings"></a>
         <dt><code>disableBoxReadings &lt;liste&gt;</code></dt>
         <br>
         Abw&auml;hlen einzelner box_ Readings.<br>
         Werden folgende Readings deaktiviert, so wird immer eine ganze Gruppe von Readings deaktiviert.<br>
         <b>box_dns_Server</b> -&gt; deaktiviert alle Readings <b>box_dns_Server</b><i>n</i><br>
      </li><br>

      <li><a name="enableBoxReadings"></a>
         <dt><code>enableBoxReadings &lt;liste&gt;</code></dt>
         <br>
         Werden folgende Readings aktiviert, so wird immer eine ganze Gruppe von Readings aktiviert.<br>
         <b>box_energyMode</b> -&gt; aktiviert alle Readings <b>box_energyMode</b><i>.*</i> FritzOS >= 7.21<br>
         <b>box_globalFilter</b> -&gt; aktiviert alle Readings <b>box_globalFilter</b><i>.*</i> FritzOS >= 7.21<br>
         <b>box_led</b> -&gt; aktiviert alle Readings <b>box_led</b><i>.*</i> FritzOS >= 6.00<br>
         <b>box_vdsl</b> -&gt; aktiviert alle Readings <b>box_vdsl</b><i>.*</i> FritzOS >= 7.80<br>
         <b>box_dns_Srv</b> -&gt; aktiviert alle Readings <b>box_dns_Srv</b><i>n</i> FritzOS > 7.31<br>
         <b>box_pwr</b> -&gt; aktiviert alle Readings <b>box_pwr</b><i>...</i> FritzOS >= 7.00. Nicht verfügbar für Cable mit FritzOS 8.00<br>
         <b>box_guestWlan</b> -&gt; aktiviert alle Readings <b>box_guestWlan</b><i>...</i> FritzOS > 7.00<br>
         <b>box_usb</b> -&gt; aktiviert alle Readings <b>box_usb</b><i>...</i> FritzOS > 7.00<br>
         <b>box_notify</b> -&gt; aktiviert alle Readings <b>box_notify</b><i>...</i> FritzOS > 7.00<br>
      </li><br>

      <li><a name="enableLogReadings"></a>
         <dt><code>enableLogReadings&lt;liste&gt;</code></dt>
         <br>
         Werden folgende Readings aktiviert, wird das entsprechende SystemLog des Fritz Gerätes abgeholt.<br>
         <b>box_sys_Log</b> -&gt; holt das System-Log. Letztes Log-Datum im Reading: box_sys_LogNewest<br>
         <b>box_wlan_Log</b> -&gt; holt das WLAN-Log. Letztes Log-Datum im Reading: box_wlan_LogNewest<br>
         <b>box_fon_Log</b> -&gt; holt das Telefon-Log. Letztes Log-Datum im Reading: box_fon_LogNewest<br>
      </li><br>

      <li><a name="disableDectInfo"></a>
         <dt><code>disableDectInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von Dect Informationen aus/ein.
      </li><br>

      <li><a name="disableFonInfo"></a>
         <dt><code>disableFonInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von Telefon Informationen aus/ein.
      </li><br>

      <li><a name="disableHostIPv4check"></a>
         <dt><code>disableHostIPv4check&lt;0 | 1&gt;</code></dt>
         <br>
         Deaktiviert den Check auf Erreichbarkeit des Host.
      </li><br>

      <li><a name="disableTableFormat"></a>
         <dt><code>disableTableFormat&lt;border(8),cellspacing(10),cellpadding(20)&gt;</code></dt>
         <br>
         Deaktiviert Parameter f&uuml;r die Formatierung der Tabelle.
      </li><br>

      <li><a name="enableAlarmInfo"></a>
         <dt><code>enableAlarmInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von Alarm Informationen aus/ein.
      </li><br>

      <li><a name="enablePhoneBookInfo"></a>
         <dt><code>enablePoneBookInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme Telefonbuch Informationen aus/ein.
      </li><br>

      <li><a name="enableKidProfiles"></a>
         <dt><code>enableKidProfiles &lt;0 | 1&gt;</code></dt> 
         <br>
         Schaltet die &Uuml;bernahme von Kid-Profilen als Reading aus/ein.
      </li><br>

      <li><a name="enableMobileInfo"></a>
         <dt><code>enableMobileInfo &lt;0 | 1&gt;</code></dt>
         <br><br>
         ! Experimentel !
         <br><br>
         Schaltet die &Uuml;bernahme von USB Mobile Ger&auml;ten als Reading aus/ein.
         <br>
         Ben&ouml;tigt Fritz!OS 7.50 oder h&ouml;her.
      </li><br>

      <li><a name="enablePassivLanDevices"></a>
         <dt><code>enablePassivLanDevices &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von passiven Netzwerkger&auml;ten als Reading aus/ein.
      </li><br>

      <li><a name="enableSIP"></a>
         <dt><code>enableSIP &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von SIP's als Reading aus/ein.
      </li><br>

      <li><a name="enableSmartHome"></a>
         <dt><code>enableSmartHome &lt;off | all | group | device&gt;</code></dt>
         <br>
         Aktiviert die &Uuml;bernahme von SmartHome Daten als Readings.
      </li><br>

      <li><a name="enableReadingsFilter"></a>
         <dt><code>enableReadingsFilter &lt;liste&gt;</code></dt>
         <br>
         Aktiviert Filter für die &Uuml;bernahme von Readings (SmartHome, Dect). Ein Readings, dass dem Filter entspricht wird <br>
         um einen Punkt als erstes Zeichen ergänzt. Somit erscheint das Reading nicht im Web-Frontend, ist aber über ReadingsVal erreichbar. 
      </li><br>

      <li><a name="enableUserInfo"></a>
         <dt><code>enableUserInfo &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von Benutzer Informationen aus/ein.
      </li><br>

      <li><a name="enableVPNShares"></a>
         <dt><code>enableVPNShares &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die &Uuml;bernahme von VPN Shares als Reading aus/ein.
      </li><br>

      <li><a name="enableWLANneighbors"></a>
         <dt><code>enableWLANneighbors &lt;0 | 1&gt;</code></dt>
         <br>
         Schaltet die Anzeige von WLAN Nachbarschaft Ger&auml;ten als Reading aus/ein.
      </li><br>

      <li><a name="lanDeviceReading"></a>
         <dt><code>lanDeviceReading &lt;mac|ip&gt;</code></dt>
         <br>
         Legt fest, ob der Reading Name aus der IP-Adresse mit Präfix ip_ oder der MAC-Adresse mit Präfix mac_ für Netzwerk Geräte gebildet werden soll.<br>
         Standard ist mac.
      </li><br>

      <li><a name="retMsgbySet"></a>
         <dt><code>retMsgbySet &lt;all|error|none&gt;</code></dt>
         <br>
         Mit dem Attribut kann die Rückgabe der SET Befehle festgelegt werden.<br>
         &lt;all&gt;: Standard. Es werden alle Ergebnisse der SET's zurück gegeben.<br>
         &lt;error&gt;: Es werden nur Fehler zurück gegeben.<br>
         &lt;none&gt;: Es erfolgt keine Rückgabe.<br>
      </li><br>

      <li><a name="wlanNeighborsPrefix"></a>
         <dt><code>wlanNeighborsPrefix &lt;prefix&gt;</code></dt>
         <br>
         Definiert einen Pr&auml;fix f&uuml;r den Reading Namen der WLAN Nachbarschaftsger&auml;te, der aus der MAC Adresse gebildet wird. Der default Pr&auml;fix ist nbh_.
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
      <li><b>box_connection_Type</b> - Verbindungsart</li>
      <li><b>box_cpuTemp</b> - Temperatur der FritxBox CPU</li>
      <li><b>box_dect</b> - Aktueller Status des DECT-Basis: aktiv, inaktiv</li>
      <li><b>box_box_dns_Server</b><i>n</i> - Provider DNS Server</li>
      <li><b>box_box_dns_Srv</b><i>n</i><b>_used_IPv4_</b><i>n</i> - benutzte IPv4 DNS Server</li>
      <li><b>box_box_dns_Srv</b><i>n</i><b>_used_IPv6_</b><i>n</i> - benutzte IPv6 DNS Server</li>
      <li><b>box_dsl_downStream</b> - Min Effektive Datenrate  (MBit/s)</li>
      <li><b>box_dsl_upStream</b> - Min Effektive Datenrate  (MBit/s)</li>
      <li><b>box_energyMode</b> - Energiemodus der FritzBox</li>
      <li><b>box_energyModeWLAN_Timer</b> - Modus des WLAN Timers</li>
      <li><b>box_energyModeWLAN_Time</b> - Zeitraum HH:MM - HH:MM der WLAN Deaktivierung</li>
      <li><b>box_energyModeWLAN_Repetition</b> - Wiederholung des WLAN Tminers</li>
      <li><b>box_fon_LogNewest</b> - aktuellstes Telefonie-Ereignis: ID Datum Zeit </li>
      <li><b>box_fwVersion</b> - Firmware-Version der Box, wenn veraltet dann wird '(old)' angehangen</li>
      <li><b>box_globalFilterNetbios</b> - Aktueller Status: NetBIOS-Filter aktiv</li>
      <li><b>box_globalFilterSmtp</b> - Aktueller Status: E-Mail-Filter über Port 25 aktiv</li>
      <li><b>box_globalFilterStealth</b> - Aktueller Status: Firewall im Stealth Mode</li>
      <li><b>box_globalFilterTeredo</b> - Aktueller Status: Teredo-Filter aktiv</li>
      <li><b>box_globalFilterWpad</b> - Aktueller Status: WPAD-Filter aktiv</li>
      <li><b>box_guestWlan</b> - Aktueller Status des G&auml;ste-WLAN</li>
      <li><b>box_guestWlanCount</b> - Anzahl der Ger&auml;te die &uuml;ber das G&auml;ste-WLAN verbunden sind</li>
      <li><b>box_guestWlanRemain</b> - Verbleibende Zeit bis zum Ausschalten des G&auml;ste-WLAN</li>
      <li><b>box_guestWlan_SSID</b> - Name (SSID) des Gäste-WLAN</li>
      <li><b>box_guestWlan_defPubSSID</b> - Standard öffentlicher Name (SSID) des Gäste-WLAN</li>
      <li><b>box_guestWlan_defPrivSSID</b> - Standard privater Name (SSID) des Gäste-WLAN</li>
      <li><b>box_guestWlan_groupAccess</b> - Gruppenzugriff möglich</li>
      <li><b>box_guestWlan_tmoActive</b> - Zeitbrenzung aktiv</li>
      <li><b>box_ipv4_Extern</b> - Internet IPv4 der FRITZ!BOX</li>
      <li><b>box_ipv6_Extern</b> - Internet IPv6 der FRITZ!BOX</li>
      <li><b>box_ipv6_Prefix</b> - Internet IPv6 Prefix der FRITZ!BOX f&uuml;r das LAN/WLAN</li>
      <li><b>box_ledCanDim</b> - zeigt an, ob das setzen der Helligkeit der Led's in der Fritzbox/dem Repeater implementiert ist</li>
      <li><b>box_ledDimValue</b> - zeigt an, auf welchen Wert die Led's gedimmt sind</li>
      <li><b>box_ledDisplay</b> - zeigt an, ob die Led's an oder aus sind</li>
      <li><b>box_ledEnvLight</b> - zeigt an, ob die Umgebungshelligkeit die Helligkeit der Led's steuert</li>
      <li><b>box_ledHasEnv</b> - zeigt an, ob das setzen der Led Helligkeit durch die Umgebungshelligkeit in der Fritzbox/dem Repeater implementiert ist</li>
      <li><b>box_last_auth_err</b> - letzter Anmeldungsfehler</li>
      <li><b>box_mac_Address</b> - MAC Adresse</li>
      <li><b>box_macFilter_active</b> - Status des WLAN MAC-Filter (WLAN-Zugang auf die bekannten WLAN-GerÃ¤te beschr&auml;nken)</li>
      <li><b>box_meshRole</b> - ab Version 07.21 wird die Mesh Rolle (master, slave) angezeigt.</li>
      <li><b>box_model</b> - FRITZ!BOX-Modell</li>
      <li><b>box_moh</b> - Wartemusik-Einstellung</li>
      <li><b>box_notify_</b><i>...</i> - die beiden Readings werden erstellt, wenn die FritzBox die Info LED rot aktiviert und einen entsprechenden Hinweis</li>
      <li><b>box_notify_</b><i>...</i><b>_info</b> - auf der Webseite plaziert. In den Readings befinden sich ein Link für weitere Informationen und<br>
                                                     ein Link um die Information zu quittieren. Durch diesen Link wird die Info in der FritzBox quittiert<br>
                                                     und es werden die beiden Readings gelöscht. Wird die Info von der FritzBox zurückgezogen, dann erhalten die <br>
                                                     Readings die Ergänzung solved und der Link zum Quittieren löscht nur noch die Readings</li>
      <li><b>box_connect</b> - Verbindungsstatus: Unconfigured, Connecting, Authenticating, Connected, PendingDisconnect, Disconnecting, Disconnected</li>
      <li><b>box_last_connect_err</b> - letzter Verbindungsfehler</li>
      <li><b>box_upnp</b> - Status der Anwendungsschnittstelle UPNP (wird auch von diesem Modul ben&ouml;tigt)</li>
      <li><b>box_upnp_control_activated</b> - Status Kontrolle &uuml;ber UPNP</li>
      <li><b>box_uptime</b> - Laufzeit seit letztem Neustart</li>
      <li><b>box_uptimeConnect</b> - Verbindungsdauer seit letztem Neuverbinden</li>
      <li><b>box_DSL_Act</b> - DSL: aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_Rate_Act</b> - Gesamt: aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_WLAN_Act</b> - WLAN: aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_mainCPU_Act</b> - CPU: aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_powerRate</b> - aktueller Stromverbrauch in Prozent der maximalen Leistung</li>
      <li><b>box_powerLine</b> - verbindung über Powerline aktiv</li>
      <li><b>box_rateDown</b> - Download-Geschwindigkeit des letzten Intervals in kByte/s</li>
      <li><b>box_rateUp</b> - Upload-Geschwindigkeit des letzten Intervals in kByte/s</li>
      <li><b>box_sys_LogNewest</b> - aktuellstes Systemereignis: ID Datum Zeit </li>
      <li><b>box_stdDialPort</b> - Anschluss der ger&auml;teseitig von der W&auml;hlhilfe genutzt wird</li>
      <li><b>box_tr064</b> - Status der Anwendungsschnittstelle TR-064 (wird auch von diesem Modul ben&ouml;tigt)</li>
      <li><b>box_tr069</b> - Provider-Fernwartung TR-069 (sicherheitsrelevant!)</li>

      <li><b>box_usb_FTP_activ</b></li>
      <li><b>box_usb_FTP_enabled</b></li>
      <li><b>box_usb_NAS_enabled</b></li>
      <li><b>box_usb_SMB_enabled</b></li>
      <li><b>box_usb_autoIndex</b></li>
      <li><b>box_usb_indexStatus</b></li>
      <li><b>box_usb_webDav</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devConType</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devEject</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devID</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devName</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devStatus</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devStorageTotal</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devStorageUsed</b></li>
      <li><b>box_usb_</b><i>n</i><b>_devType</b></li>

      <li><b>box_vdsl_downStreamRate</b> - Aktuelle DownStream Datenrate (MBit/s)</li>
      <li><b>box_vdsl_downStreamMaxRate</b> - Maximale DownStream Datenrate (MBit/s)</li>
      <li><b>box_vdsl_upStreamRate</b> - Aktuelle UpStream Datenrate (MBit/s)</li>
      <li><b>box_vdsl_upStreamMaxRate</b> - Maximale UpStream Datenrate (MBit/s)</li>
      <li><b>box_wan_AccessType</b> - Verbindungstyp (DSL, Ethernet, ...)</li>
      <li><b>box_wlan_Count</b> - Anzahl der Ger&auml;te die &uuml;ber WLAN verbunden sind</li>
      <li><b>box_wlan_Active</b> - Akteuller Status des WLAN</li>
      <li><b>box_wlan_2.4GHz</b> - Aktueller Status des 2.4-GHz-WLAN</li>
      <li><b>box_wlan_5GHz</b> - Aktueller Status des 5-GHz-WLAN</li>
      <li><b>box_wlan_lastScanTime</b> - Letzter Scan der WLAN Umgebung. Ist nur vorhanden, wenn das Attribut enableWLANneighbors gesetzt ist.</li>
      <li><b>box_wlan_LogExtended</b> - Status -> "Auch An- und Abmeldungen und erweiterte WLAN-Informationen protokollieren".</li>
      <li><b>box_wlan_LogNewest</b> - aktuellstes WLAN-Ereignis: ID Datum Zeit </li>
      <br>
      <li><b>box_docsis30_Ds_corrErrors</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_frequencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_latencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_mses</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_nonCorrErrors</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_powerLevels</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Ds_modulations</b> - Nur Fritz!Box Cable</li>

      <li><b>box_docsis30_Us_frequencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Us_powerLevels</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis30_Us_modulations</b> - Nur Fritz!Box Cable</li>

      <li><b>box_docsis31_Ds_frequencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis31_Ds_powerLevels</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis31_Ds_modulations</b> - Nur Fritz!Box Cable</li>

      <li><b>box_docsis31_Us_frequencys</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis31_Us_powerLevels</b> - Nur Fritz!Box Cable</li>
      <li><b>box_docsis31_Us_modulations</b> - Nur Fritz!Box Cable</li>
      <br>
      <li><b>dect</b><i>n</i> - Name des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_alarmRingTone</b> - Klingelton beim Wecken &uuml;ber das DECT Telefon <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_custRingTone</b> - Benutzerspezifischer Klingelton des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_device</b> - Interne Device Nummer des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_fwVersion</b> - Firmware-Version des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_intern</b> - Interne Telefonnummer des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_intRingTone</b> - Interner Klingelton des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_manufacturer</b> - Hersteller des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_model</b> - Modell des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_NoRingWithNightSetting</b> - Bei aktiver Klingelsperre keine Ereignisse signalisieren f&uuml;r das DECT Telefon <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_radio</b> - aktueller Internet-Radio-Klingelton des DECT Telefons <i>n</i></li>
      <li><b>dect</b><i>n</i><b>_NoRingTime</b> - Klingelsperren des DECT Telefons <i>n</i></li>
      <br>
      <li><b>diversity</b><i>n</i> - Eigene Rufnummer der Rufumleitung <i>n</i></li>
      <li><b>diversity</b><i>n</i><b>_dest</b> - Zielnummer der Rufumleitung <i>n</i></li>
      <li><b>diversity</b><i>n</i><b>_state</b> - Aktueller Status der Rufumleitung <i>n</i></li>
      <br>
      <li><b>fon</b><i>n</i> - Name des analogen Telefonanschlusses <i>n</i> an der FRITZ!BOX</li>
      <li><b>fon</b><i>n</i><b>_device</b> - Interne Device Nummer des analogen Telefonanschlusses <i>n</i></li>
      <li><b>fon</b><i>n</i><b>_intern</b> - Interne Telefonnummer des analogen Telefonanschlusses <i>n</i></li>
      <li><b>fon</b><i>n</i><b>_out</b> - ausgehende Telefonnummer des Anschlusses <i>n</i></li>
      <li><b>fon_phoneBook_IDs</b> - ID's of the existing phone books </li>
      <li><b>fon_phoneBook_</b><i>n</i> - Name of the phone book <i>n</i></li>
      <li><b>fon_phoneBook_URL_</b><i>n</i> - URL to the phone book <i>n</i></li>
      <br>
      <li><b>gsm_internet</b> - Internetverbindung errichtet &uuml;ber Mobilfunk-Stick </li>
      <li><b>gsm_rssi</b> - Indikator der empfangenen GSM-Signalst&auml;rke (0-100)</li>
      <li><b>gsm_state</b> - Status der Mobilfunk-Verbindung</li>
      <li><b>gsm_technology</b> - GSM-Technologie, die f&uuml;r die Daten&uuml;bertragung genutzt wird (GPRS, EDGE, UMTS, HSPA)</li>
      <br>
      <li><b>matter_</b><i>...</i><b>_node</b> - matter node (SmartGateWay oder FB mit Matter).</li>
      <li><b>matter_</b><i>...</i><b>_vendor</b> - matter vendor/fabric (SmartGateWay oder FB mit Matter).</li>
      <br>
      <li><b>mobileInfo_</b><i>...</i> - Mobilfunk Readings (USB-Mobilfunk-Stick oder FritzBox LTE).</li>
      <br>
      <li><b>mac_</b><i>nn_nn_nn_nn_nn_nn</i> - MAC Adresse und Name eines aktiven Netzwerk-Ger&auml;tes.<br>
      Wird keine MAC-Adresse bereit gestellt,z.B. Switch oder VPN, dann wird anstatt der MAC-Adresse die FritzBox DeviceID genommen.<br>
      Bei einer WLAN-Verbindung wird "WLAN" und (von der Box gesehen) die Sende- und Empfangsgeschwindigkeit und die Empfangsst&auml;rke angehangen. Bei einer LAN-Verbindung wird der LAN-Port und die LAN-Geschwindigkeit angehangen. Gast-Verbindungen werden mit "gWLAN" oder "gLAN" gekennzeichnet.<br>
      Inaktive oder entfernte Ger&auml;te erhalten zuerst den Werte "inactive: IP-Adresse" bzw "inactiv: DeviceID" wenn keine IP-Adresse zur Verfügung steht<br>
      und werden beim n&auml;chsten Update gel&ouml;scht.</li>
      <br>
      <li><b>ip_</b><i>nnn.nnn.nnn.nnn</i> - IP-Adresse und Name eines aktiven Netzwerk-Ger&auml;tes.<br>
      Bei einer WLAN-Verbindung wird "WLAN" und (von der Box gesehen) die Sende- und Empfangsgeschwindigkeit und die Empfangsst&auml;rke angehangen. Bei einer LAN-Verbindung wird der LAN-Port und die LAN-Geschwindigkeit angehangen. Gast-Verbindungen werden mit "gWLAN" oder "gLAN" gekennzeichnet.<br>
      Inaktive oder entfernte Ger&auml;te erhalten zuerst den Wert "inactive: DeviceID" und werden beim n&auml;chsten Update gel&ouml;scht.</li>
      <br>
      <li><b>nbh_</b><i>nn_nn_nn_nn_nn_nn</i> - MAC-Adresse und Name eines aktiven WAN-Ger&auml;tes.<br>
      Es wird die SSID, der Kanal und das Frequenzband angezeigt.<br>
      Inaktive oder entfernte Ger&auml;te erhalten zuerst den Werte "inactive" und werden beim n&auml;chsten Update gel&ouml;scht.</li>
      <br>
      <li><b>radio</b><i>nn</i> - Name der Internetradiostation <i>01</i></li>
      <br>
      <li><b>tam</b><i>n</i> - Name des Anrufbeantworters <i>n</i></li>
      <li><b>tam</b><i>n</i><b>_newMsg</b> - Anzahl neuer Nachrichten auf dem Anrufbeantworter <i>n</i></li>
      <li><b>tam</b><i>n</i><b>_oldMsg</b> - Anzahl alter Nachrichten auf dem Anrufbeantworter <i>n</i></li>
      <li><b>tam</b><i>n</i><b>_state</b> - Aktueller Status des Anrufbeantworters <i>n</i></li>
      <br>
      <li><b>user</b><i>nn</i> - Name von Nutzer/IP <i>n</i> f&uuml;r den eine Zugangsbeschr&auml;nkung (Kindersicherung) eingerichtet ist</li>
      <li><b>user</b><i>nn</i>_thisMonthTime - Internetnutzung des Nutzers/IP <i>n</i> im aktuellen Monat (Kindersicherung)</li>
      <li><b>user</b><i>nn</i>_todaySeconds - heutige Internetnutzung des Nutzers/IP <i>n</i> in Sekunden (Kindersicherung)</li>
      <li><b>user</b><i>nn</i>_todayTime - heutige Internetnutzung des Nutzers/IP <i>n</i> (Kindersicherung)</li>
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
      <li><b>sip_active</b> - zeigt die Anzahl aktiver SIP.</li>
      <li><b>sip_inactive</b> - zeigt die Anzahl inaktiver SIP.</li>
      <li><b>sip_error</b> - zeigt die Anzahl fehlerhafter SIP. 0 == alles Ok.</li>
      <br>
      <li><b>shdevice</b><i>n</i><b>_battery</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_category</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_device</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_firmwareVersion</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_manufacturer</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_model</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_status</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_tempOffset</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_temperature</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_type</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_voltage</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_power</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_current</b> - </li>
      <li><b>shdevice</b><i>n</i><b>_consumtion</b> - </li>
      <br>
      <li><b>retStat_chgProfile</b> - Return Status: set &lt;name&gt; chgProfile &lt;number&gt; &lt;filtprofn&gt;</li>
      <li><b>retStat_enableVPNshare</b> - Return Status: set &lt;name&gt; enableVPNshare &lt;number&gt; &lt;on|off&gt;</li>
      <li><b>retStat_fritzLogInfo</b> - Return Status: get &lt;name&gt; &lt;hash&gt; &lt;...&gt;</li>
      <li><b>retStat_fritzLogExPost</b> - Return Status der Hook-Funktion myUtilsFritzLogExPost($hash, $filter, $result) zu: get &lt;name&gt; &lt;hash&gt; &lt;...&gt;</li>
      <li><b>retStat_lastReadout</b> - Return Status: set &lt;name&gt; update oder Intervall update</li>
      <li><b>retStat_lockLandevice</b> - Return Status: set &lt;name&gt; lockLandevice &lt;number> &lt;on|off&gt;</li>
      <li><b>retStat_macFilter</b> - Return Status: set &lt;name&gt; macFilter &lt;on|off&gt;</li>
      <li><b>retStat_rescanWLANneighbors</b> - Return Status: set &lt;name&gt; rescanWLANneighbors</li>
      <li><b>retStat_smartHome</b> - Return Status: set &lt;name&gt; smartHome</li>
      <li><b>retStat_wakeUpCall</b> - Return Status: set &lt;name&gt; wakeUpCall</li>
      <li><b>retStat_wlanLogExtended</b> - Return Status: set &lt;name&gt; wlanLogExtended &lt;on|off&gt;</li>
      <li><b>retStat_wlanGuestParams</b> - Return Status</li>
   </ul>
   <br>
   <a name="FRITZBOX Ereignis-Codes"></a>
   <b>Ereignis-Codes</b>
   <ul><br>
       <li><b>1</b> IGMPv3 multicast router n.n.n.n active</li>
      <li><b>11</b> DSL ist verf&uuml;gbar (DSL-Synchronisierung besteht mit n/n kbit/s).</li>
      <li><b>12</b> DSL-Synchronisierung beginnt (Training).</li>
      <li><b>14</b> Mobilfunkmodem initialisiert.</li>
      <li><b>23</b> Internetverbindung wurde getrennt.</li>
      <li><b>24</b> Internetverbindung wurde erfolgreich hergestellt. IP-Adresse: ..., DNS-Server: ... und ..., Gateway: ..., Breitband-PoP: ..., LineID:...</li>
      <li><b>25</b> Internetverbindung IPv6 wurde erfolgreich hergestellt. IP-Adresse: ...:...:...:...:...:...:...:...</li>
      <li><b>26</b> Internetverbindung wurde getrennt.</li>
      <li><b>27</b> IPv6-Pr&auml;fix wurde erfolgreich bezogen. Neues Pr&auml;fix: ....:....:....:....:/nn</li>
      <li><b>28</b> Internetverbindung IPv6 wurde getrennt, Pr&auml;fix nicht mehr g&uuml;ltig.</li>
      <br>
      <li><b>71</b> Anmeldung der Internetrufnummer &lt;Nummer&gt; war nicht erfolgreich. Ursache: DNS-Fehler.</li>
      <li><b>73</b> Anmeldung der Internetrufnummer &lt;Nummer&gt; war nicht erfolgreich. Ursache: Gegenstelle antwortet nicht. Zeit&uuml;berschreitung.</li>
      <li><b>85</b> Die Internetverbindung wird kurz unterbrochen, um der Zwangstrennung durch den Anbieter zuvorzukommen.</li>
      <br>
     <li><b>119</b> Information des Anbieters &uuml;ber die Geschwindigkeit des Internetzugangs (verf&uuml;gbare Bitrate): nnnn/nnnn kbit/s</li>
     <li><b>131</b> USB-Ger&auml;t ..., Klasse 'USB 2.0 (hi-speed) storage', angesteckt</li>
     <li><b>132</b> USB-Ger&auml;t ... abgezogen</li>
     <li><b>134</b> Es wurde ein nicht unterst&uuml;tzes USB-Ger&auml;t angeschlossen</li>
     <li><b>140</b> Der USB-Speicher ... wurde eingebunden.</li>
     <li><b>141</b> Der USB-Speicher ... wurde entfernt.</li>
     <li><b>189</b> Die Rufnummer &lt;Nummer&gt; ist seit mehr als einer Stunde nicht verfügbar.</li>
     <br>
     <li><b>201</b> Es liegt keine St&ouml;rung der Telefonie mehr vor. Alle Rufnummern sind ab sofort wieder verf&uuml;gbar.</li>
     <li><b>205</b> Anmeldung f&uuml;r IP-Telefonieger&auml;t "Telefonie-Ger&auml;t" von IP-Adresse ... nicht erfolgreich.</li>
     <li><b>267</b> Integrierter Faxempfang wurde aktiviert auf USB-Speicher 'xxx'.</li>
     <br>
     <li><b>401</b> SIP_UNAUTHORIZED, Beschreibung steht in der Hilfe (Webinterface)</li>
     <li><b>403</b> SIP_FORBIDDEN, Beschreibung steht in der Hilfe (Webinterface)</li>
     <li><b>404</b> SIP_NOT_FOUND, Gegenstelle nicht erreichbar (local part der SIP-URL nicht erreichbar (Host schon))</li>
     <li><b>405</b> SIP_METHOD_NOT_ALLOWED</li>
     <li><b>406</b> SIP_NOT_ACCEPTED</li>
     <li><b>408</b> SIP_NO_ANSWER</li>
     <br>
     <li><b>484</b> SIP_ADDRESS_INCOMPLETE, Beschreibung steht in der Hilfe (Webinterface)</li>
     <li><b>485</b> SIP_AMBIGUOUS, Beschreibung steht in der Hilfe (Webinterface)</li>
     <br>
     <li><b>486</b> SIP_BUSY_HERE, Ziel besetzt (vermutlich auch andere Gr&uuml;nde bei der Gegenstelle)</li>
     <li><b>487</b> SIP_REQUEST_TERMINATED, Anrufversuch beendet (Gegenstelle nahm nach ca. 30 Sek. nicht ab)</li>
     <br>
     <li><b>500</b> Anmeldung an der FRITZ!Box-Benutzeroberfl&auml;che von von IP-Adresse ...</li>
     <li><b>501</b> Anmeldung an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse ... gescheitert (falsches Kennwort).</li>
     <li><b>502</b> Die FRITZ!Box-Einstellungen wurden &uuml;ber die Benutzeroberfl&auml;che ge&auml;ndert.</li>
     <li><b>503</b> Anmeldung an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse yy gescheitert (ung&uuml;ltige Sitzungskennung). Zur Sicherheit werden</li>
     <li><b>504</b> Anmeldung des Benutzers FhemUser an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse ...</li>
     <li><b>505</b> Anmeldung des Benutzers xx an der FRITZ!Box-Benutzeroberfl&auml;che von IP-Adresse yy gescheitert (falsches Kennwort)</li>
     <li><b>506</b> Anmeldung einer App des Benutzers FhemUser von IP-Adresse</li>
     <li><b>510</b> Anmeldung einer App mit unbekanntem Anmeldenamen von IP-Adresse ... gescheitert.</li>
     <br>
     <li><b>689</b> WLAN-Anmeldung ist gescheitert : Die MAC-Adresse des WLAN-Ger&auml;ts ist gesperrt. MAC-Adresse</li>
     <li><b>692</b> WLAN-Anmeldung ist gescheitert : Verbindungsaufbau fehlgeschlagen. MAC-Adresse</li>
     <li><b>705</b> WLAN-Ger&auml;t Anmeldung gescheitert (5 GHz): ung&uuml;ltiger WLAN-Schl&uuml;ssel. MAC-Adresse</li>
     <li><b>706</b> [...] WLAN-Ger&auml;t Anmeldung am Gastzugang gescheitert (n,n GHz): ung&uuml;ltiger WLAN-Schl&uuml;ssel. MAC-Adresse: nn:nn:nn:nn:nn:nn.</li>
     <li><b>748</b> [...] WLAN-Ger&auml;t angemeldet (n,n GHz), nn Mbit/s, PC-..., IP ..., MAC ... .</li>
     <li><b>752</b> [...] WLAN-Ger&auml;t hat sich abgemeldet (n,n GHz), PC-..., IP ..., MAC ....</li>
     <li><b>754</b> [...] WLAN-Ger&auml;t wurde abgemeldet (.,. GHz), PC-..., IP ..., MAC ... .</li>
     <li><b>756</b> WLAN-Ger&auml;t hat sich neu angemeldet (n,n GHz), nn Mbit/s, Ger&auml;t, IP ..., MAC ....</li>
     <li><b>782</b> WLAN-Anmeldung ist gescheitert : Die erneute Anmeldung ist aufgrund aktiver "Unterst&uuml;tzung f&uuml;r gesch&uuml;tzte Anmeldungen von WLAN-Ger&auml;ten (PMF)</li>
     <li><b>786</b> 5-GHz-Band für [Anzahl] Min. nicht nutzbar wegen Pr&uuml;fung auf bevorrechtigten Nutzer (z. B. Radar) auf dem gew&auml;hlten Kanal (Frequenz [GHz])</li>
     <li><b>790</b> Radar wurde auf Kanal [Nummer] (Frequenz [Ziffer] GHz) erkannt, automatischer Kanalwechsel wegen bevorrechtigtem Benutzer ausgef&uuml;hrt</li>
     <li><b>801</b> Die FRITZ!Box ist seit mehr als einer Stunde nicht mehr mit dem Internet verbunden.</li>
     <li><b>801</b> Die FRITZ!Box ist seit mehr als einer Stunde nicht mehr mit dem Internet verbunden. Auch die Telefonie ist nicht oder nur eingeschränkt verfügbar.</li>
     <br>
    <li><b>2104</b> Die Systemzeit wurde erfolgreich aktualisiert von Zeitserver nnn.nnn.nnn.nnn .</li>
     <br>
    <li><b>2364</b> Ein neues Ger&auml;t wurde an der FRITZ!Box angemeldet (Schnurlostelefon)</li>
    <li><b>2358</b> Einstellungen wurden gesichert. Diese &auml;nderung erfolgte von Ihrem Heimnetzger&auml;t ... (IP-Adresse: ...)</li>
    <li><b>2380</b> Es besteht keine Verbindung mehr zu den verschl&uuml;sselten DNS-Servern.</li>
    <li><b>2383</b> Es wurde erfolgreich eine Verbindung - samt vollst&auml;ndiger Validierung - zu den verschl&uuml;sselten DNS-Servern aufgebaut.</li>
    <li><b>2380</b> Es besteht keine Verbindung mehr zu den verschl&uuml;sselten DNS-Servern.</li>
    <li><b>3330</b> Verbindung zum Online-Speicher hergestellt.</li>
   </ul>
   <br>
</div>
=end html_DE

=cut--

###############################################################
# HOST=box:settings/hostname 
# SSID1=wlan:settings/ssid
# SSID2=wlan:settings/ssid_scnd
# FORWARDS=forwardrules:settings/rule/list(activated,description,protocol,port,fwip,fwport,endport)
# SIPS=sip:settings/sip/list(ID,displayname)
# NUMBERS=telcfg:settings/VoipExtension/listwindow(2,2,Name,enabled) <=== eingeschrÃ¤nkte Ergebnismenge
# DEVICES=ctlusb:settings/device/count
# PHYS=usbdevices:settings/physmedium/list(name,vendor,serial,fw_version,conntype,capacity,status,usbspeed,model)
# PHYSCNT=usbdevices:settings/physmediumcnt
# VOLS=usbdevices:settings/logvol/list(name,status,enable,phyref,filesystem,capacity,usedspace,readonly)
# VOLSCNT=usbdevices:settings/logvolcnt
# PARTS=ctlusb:settings/storage-part/count
# SIP1=sip:settings/sip1/activated
# openports:settings/interfaces/list(name)
###############################################################
# xhr: 1
# holdmusic: 0 == Sprache, 1 == Musik
# apply: 
# sid: nnnnnnnnnnnnnnnn
# lang: de
# page: moh_upload
#
# xhr: 1
# sid: nnnnnnnnnnnnnnnn
# lang: de
# page: phoneline
# xhrId: all
#
# xhr: 1
# sid: nnnnnnnnnnnnnnnn
# page: sipQual
#
# xhr: 1
# sid: nnnnnnnnnnnnnnnn
# page: numLi
#
# xhr: 1
# chooseexport: cfgexport
# uiPass: xxxxxxxxx
# sid: nnnnnnnnnnnnnnnn
# ImportExportPassword: xxxxxxxxx
# ConfigExport: 
# AssetsImportExportPassword: xxxxxxxxx
# AssetsExport: 
# back_to_page: sysSave
# apply: 
# lang: de
# page: sysSave
#
###############################################################
#
# Mit der Firmware-Version FRITZ!OS 06.80 f&uuml;hrt AVM eine Zweifaktor-Authentifizierung f&uuml;r folgende sicherheitskritische Aktionen ein:
#
# - Deaktivierung der Konfigurationsoption der Zweifaktor-Authentifizierung selbst
# - Einrichtung und Benutzerdaten sowie Internetfreigabe von IP-Telefonen
# - Einrichten und Konfigurieren von Rufumleitungen
# - Anbietervorwahlen und ausgehende Wahlregeln
# - Konfiguration von Callthrough
# - Interner Anrufbeantworter: Konfiguration der Fernabfrage
# - Aktivierung der W&auml;hlhilfe
# - L&ouml;schen und &auml;ndern von Rufsperren
# - Telefonie/Anschlusseinstellungen: Deaktivierung des Filters f&uuml;r SIP Traffic aus dem Heimnetz
# - Einrichten bzw. &auml;ndern von E-Mail-Adresse oder Kennwort f&uuml;r die Push-Mail-Funktion zum Versenden der Einstellungssicherung
# - Fax senden: Starten eines Sendevorganges
# - Telefonie/Anschlusseinstellungen: Deaktivierung der Betrugserkennungs-Heuristik
# - Telefonie/Anschlusseinstellungen: Setzen/&auml;ndern der LKZ sowie des LKZ-Pr&auml;fix
# - Das Importieren und Exportieren von Einstellungen
#
###############################################################
# Time:1 time GetInfo
# 'GetInfoResponse' => {
#      'NewNTPServer1' => 'ntp.1und1.de',
#      'NewLocalTimeZoneName' => 'CET-1CEST-2,M3.5.0/02:00:00,M10.5.0/03:00:00',
#      'NewLocalTimeZone' => '',
#      'NewNTPServer2' => '',
#      'NewCurrentLocalTime' => '2023-04-21T18:42:03+02:00',
#      'NewDaylightSavingsStart' => '0001-01-01T00:00:00',
#      'NewDaylightSavingsUsed' => '0',
#      'NewDaylightSavingsEnd' => '0001-01-01T00:00:00'
#
# SetNTPServers ( NewNTPServer1 NewNTPServer2 )
#
# UserInterface:1 userif GetInfo
# 'GetInfoResponse' => {
#      'NewX_AVM-DE_BuildType' => 'Release',
#      'NewWarrantyDate' => '0001-01-01T00:00:00',
#      'NewUpgradeAvailable' => '0',
#      'NewX_AVM-DE_InfoURL' => '',
#      'NewX_AVM-DE_SetupAssistantStatus' => '1',
#      'NewX_AVM-DE_Version' => '',
#      'NewPasswordUserSelectable' => '1',
#      'NewX_AVM-DE_DownloadURL' => '',
#      'NewPasswordRequired' => '0',
#      'NewX_AVM-DE_UpdateState' => 'Stopped'
# }
#
# X_AVM-DE_AppSetup:1 x_appsetup GetAppRemoteInfo ab 7.29
#
# Service='X_AVM-DE_AppSetup:1'   Control='x_appsetup'   Action='GetAppRemoteInfo'
# ----------------------------------------------------------------------
# $VAR1 = {
#          'GetAppRemoteInfoResponse' => {
#                                          'NewSubnetMask' => '255.255.255.0',
#                                          'NewExternalIPAddress' => '91.22.231.84',
#                                          'NewRemoteAccessDDNSDomain' => 'ipwiemann.selfhost.eu',
#                                          'NewMyFritzEnabled' => '1',
#                                          'NewMyFritzDynDNSName' => 'r178c7aqb0gbdr62.myfritz.net',
#                                          'NewExternalIPv6Address' => '2003:c2:57ff:503:3ea6:2fff:feaf:c3ad',
#                                          'NewRemoteAccessDDNSEnabled' => '0',
#                                          'NewIPAddress' => '192.168.0.1'
#                                        }
#        };
#
#
# WLANConfiguration:1 wlanconfig1 GetInfo
# {FRITZBOX_SOAP_Test_Request("FB_Rep_OG", "igdupnp\/control\/wlanconfig1", "urn:schemas-upnp-org:service:WLANConfiguration:1", "GetInfo")}
# {FRITZBOX_SOAP_Test_Request("FritzBox", "igdupnp\/control\/WANCommonIFC1", "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1", "GetAddonInfos")}
# 
# http://fritz.box:49000/igddesc.xml
# http://fritz.box:49000/any.xml
# http://fritz.box:49000/igdicfgSCPD.xml
# http://fritz.box:49000/igddslSCPD.xml
# http://fritz.box:49000/igdconnSCPD.xml
# 
# ggf bei Repeater einbauen: xhr 1 lang de page overview xhrId all useajax 1
#
#   my $userNo = $intNo-609;
#   my $queryStr = "&curRingTone=telcfg:settings/Foncontrol/User".$userNo."/IntRingTone";
#   $queryStr .= "&curRadioStation=telcfg:settings/Foncontrol/User".$userNo."/RadioRingID";
#   my $startValue = FRITZBOX_call_Lua_Query( $hash, $queryStr );
#
#
###############################################################
# Eigenschaften Telefon setzen
#
# xhr: 1
# name: Schlafzimmer
# fonbook: 0
# out_num: 983523
# num_selection: all_nums
# idx: 4
# back_to_page: /fon_devices/fondevices_list.lua
# btn_save: 
# sid: b78f24ea4bf7ca59
# lang: de
# page: edit_dect_num
#
#
###############################################################
# boxnotifications
# Anforderungs-URL:
# http://192.168.0.1/api/v0/boxnotifications/32_1
# Anforderungsmethode:
# DELETE
# Statuscode:
# 200 OK
# Remoteadresse:
# 192.168.0.1:80
# Referrer-Richtlinie:
# same-origin
#
# {"success":0}
#
#
###############################################################
# javaScript Aufrufe
# - configflags / FritzBox Konfiguration
# - wlan_light  / WLAN Informationen
# - eventlog    / Ereignisse - Filterung über "group"
# - eventlog/groups    / listet die groups auf
# - box         / dhcp, led, night_time ...
# - boxnotifications
# - configflags 
# - uimodlogic  / uptime ...
# - power       / Diagramm Energieverbrauch
# - eht_ports   / LAN Informationen
# - ctlusb
# - umts
# - connections
# - cpu
# - books       / Telefonbücher
# - WLANTimer
# - TAM
# - wanStatus
# - updateStatus
# - tempsmarthome
# - nexus
# - power
# - providerlist / Provider
# - boxusers
# - updatecheck
# - mobiled
# - dect
# - vpn
# - phonecalls
# - sip
# - telcfg
# - webdavclient
# - plc
# - trafficprio
# - user
# - usbdevices
# - budget
# - ddns
# - emailnotify
# - forwardrules
# - inetstat
# - ipv6
# - ipv6firewall
# - jasonii
# - myfritzdevice
# - remoteman
# - igdforwardrules
# - userglobal
# - aura
# - pcp
# - remoteman
# - monitor/datasets
# - monitor/configuration
# - monitor/onlinemonitor_dsl_0/subset0000..0003
# - generic?ui=box,boxusers,connections,eth_ports,landevice,nexus,plc,power,providerlist,uimodlogic,updatecheck,dect,usbdevices
# - landevice
# - landevice/landevice
# - landevice/landevice/landevice9392