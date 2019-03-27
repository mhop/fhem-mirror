# $Id$
##############################################################################
#
#     71_YAMAHA_MC.pm
#     An FHEM Perl module for controlling Yamaha Musiccast Devices
#     via network connection. As the interface is standardized
#     within all Yamaha Musiccast Devices, this module should work
#     with any musiccastdevice which has an ethernet or wlan connection.
#
#     Copyright by Stefan Leugers
#     e-mail: stefan.leugers@onlinehome.de
#
#    Changes
#	  8-1-19 by tobi73: 	Adding command to select NetRadio Favourites (setNetRadioPreset), correct URL in case API Version ist "dotted" 	
#     
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################



package main;

use strict;
use Blocking;
use warnings;
use Data::Dumper;
use HttpUtils;
use Time::HiRes qw(gettimeofday sleep);
use Encode qw(decode encode);
#use UPnP::ControlPoint;
#use Net::UPnP::ControlPoint;
use Net::UPnP::AV::MediaRenderer;
use Net::UPnP::ControlPoint;
use Net::UPnP::Device;
use Net::UPnP::Service;
use Net::UPnP::AV::MediaServer;


# Basis UPnP-Object und Search-Referenzen
my $YAMAHA_MC_RestartControlPoint = 0;
my $YAMAHA_MC_Controlpoint;
my $YAMAHA_MC_Search;
my $YAMAHA_MC_Renderer;
my $YAMAHA_MC_Media;

sub YAMAHA_MC_GetStatus($;$);
sub YAMAHA_MC_ResetTimer($;$);
sub YAMAHA_MC_Get($@);
sub YAMAHA_MC_Define($$);
sub YAMAHA_MC_Attr(@);
sub YAMAHA_MC_Undefine($$);
sub YAMAHA_MC_UpdateLists($;$);
sub YAMAHA_MC_httpRequestQueue($$$;$);
sub YAMAHA_MC_getDistributionInfo($);
sub YAMAHA_MC_hash_replace (\%$$);
sub YAMAHA_MC_volume_abs2rel($$);
sub YAMAHA_MC_volume_rel2abs($$);
sub YAMAHA_MC_getParamName($$$);
sub YAMAHA_MC_DiscoverDLNAProcess($);
sub YAMAHA_MC_DiscoverMediaServer($);
sub YAMAHA_MC_DiscoverRenderer($);


  # the Cmd List without Args will be generated from the cmd list with Args in YAMAHA_MC_UpdateLists
  #my %YAMAHA_MC_setCmdswithoutArgs = ();
  my %YAMAHA_MC_setCmdswithoutArgs = (
    "on"                    => "/v1/main/setPower?power=on",	   
	"off"                   => "/v1/main/setPower?power=standby",	
	"power"		=> "/v1/main/setPower?power=",
    "setAutoPowerStandby"    => "/v1/system/setAutoPowerStandby?enable=",	
	"volume"	=> "/v1/main/setVolume?volume=",
	"volumeStraight"	=> "/v1/main/setVolume?volume=",
	"volumeUp"	            => "/v1/main/setVolume?volume=",
	"volumeDown"            => "/v1/main/setVolume?volume=",
	"mute"		=> "/v1/main/setMute?enable=",
	"setSpeakerA"		=> "/v1/main/setSpeakerA?enable=",
	"setSpeakerB"		=> "/v1/main/setSpeakerB?enable=",
	"setToneBass"           => "/v1/main/setEqualizer?low=",
	"setToneMid"           => "/v1/main/setEqualizer?mid=",
	"setToneHigh"           => "/v1/main/setEqualizer?high=",
	"input"					=> "/v1/main/setInput?input=",
	"prepareInputChange"    => "/v1/main/prepareInputChange?input=",
	"getStatus"				=> "/v1/main/getStatus",
	"getFeatures"			=> "/v1/system/getFeatures",
	"getFuncStatus"         => "/v1/system/getFuncStatus",
	"selectMenu"			=> "/v1/netusb/setListControl?list_id=main&type=select&index=",
	"selectMenuItem"			=> "/v1/netusb/setListControl?list_id=main&type=select&index=",
	"selectPlayMenu"        => "/v1/netusb/setListControl?list_id=main&type=play&index=",	
	"selectPlayMenuItem"        => "/v1/netusb/setListControl?list_id=main&type=play&index=",	
	"getPlayInfo"           => "/v1/netusb/getPlayInfo",
	"playback"              => "/v1/netusb/setPlayback?playback=",
	"getMenu"			    => "/v1/netusb/getListInfo?input=net_radio&index=0&size=8&lang=en",
	"getMenuItems"			=> "/v1/netusb/getListInfo?input=net_radio&index=0&size=8&lang=en",
	"returnMenu"			=> "/v1/netusb/setListControl?list_id=main&type=return",
	"getDeviceInfo"         => "/v1/system/getDeviceInfo",
	"getSoundProgramList"   => "/v1/main/getSoundProgramList",	
	"setSoundProgramList"   => "/v1/main/setSoundProgram?program=",
    "setFmTunerPreset"      => "/v1/tuner/recallPreset?zone=main&band=fm&num=",
	"setDabTunerPreset"      => "/v1/tuner/recallPreset?zone=main&band=dab&num=",
	"setNetRadioPreset"		=> "/v1/netusb/recallPreset?zone=main&num=",
    "TurnFavNetRadioChannelOn"  => "batch_cmd",	
	"TurnFavServerChannelOn"  => "batch_cmd",	
	"navigateListMenu"  => "batch_cmd",	
	"NetRadioNextFavChannel" => "batch_cmd",	
	"NetRadioPrevFavChannel" => "batch_cmd",	
	"sleep"                 => "/v1/main/setSleep?sleep=",	
    "getNetworkStatus"      => "/v1/system/getNetworkStatus",
	"getLocationInfo"       => "/v1/system/getLocationInfo",
	"getDistributionInfo"   => "/v1/dist/getDistributionInfo",
	"getBluetoothInfo"	    => "/v1/system/getBluetoothInfo",
    "enableBluetooth"        => "/v1/system/setBluetoothTxSetting?enable=",
	"setGroupName"            => "/v1/dist/setGroupName",
	"mcLinkTo"                 => "batch_cmd",	
	"speakfile"                 => "batch_cmd",	
	"mcUnLink"                 => "batch_cmd",		
	"setServerInfo"           => "/v1/dist/setServerInfo",
	"setClientInfo"           => "/v1/dist/setClientInfo",
	"startDistribution"    => "/v1/dist/startDistribution?num=0",
	"isNewFirmwareAvailable"    => "/v1/system/isNewFirmwareAvailable?type=network",
    "statusRequest"         => "/v1/main/getStatus"		
  );
  
  # just a placeholder here
  # will be filled up programmatically
  my %YAMAHA_MC_setCmdsWithArgs = (
    "on:noArg"                    => "/v1/main/setPower?power=on",	
	"off:noArg"                   => "/v1/main/setPower?power=standby",	
	"power:on,standby"		=> "/v1/main/setPower?power=",	
	"setAutoPowerStandby:true,false"    => "/v1/system/setAutoPowerStandby?enable=",
	"volume:slider,0,1,100"	=> "/v1/main/setVolume?volume=",
	"volumeStraight"	=> "/v1/main/setVolume?volume=",
	"volumeUp:noArg"	            => "/v1/main/setVolume?volume=",
	"volumeDown:noArg"            => "/v1/main/setVolume?volume=",
	"mute:toggle,true,false"		=> "/v1/main/setMute?enable=",
    "setSpeakerA:toggle,true,false"		=> "/v1/main/setSpeakerA?enable=",
    "setSpeakerB:toggle,true,false"		=> "/v1/main/setSpeakerB?enable=",
	"setToneBass:slider,-10,1,10"           => "/v1/main/setEqualizer?low=",
	"setToneMid:slider,-10,1,10"           => "/v1/main/setEqualizer?mid=",
	"setToneHigh:slider,-10,1,10"           => "/v1/main/setEqualizer?high=",
    "input:napster,spotify,juke,airplay,mc_link,server,net_radio,bluetooth"  => "/v1/main/setInput?input=",	
	"prepareInputChange:napster,spotify,juke,airplay,mc_link,server,net_radio,bluetooth"  => "/v1/main/prepareInputChange?input=",		
	"getStatus:noArg"				=> "/v1/main/getStatus",
	"getFeatures:noArg"			=> "/v1/system/getFeatures",
	"getFuncStatus:noArg"			=> "/v1/system/getFuncStatus",	
	"selectMenu"			=> "/v1/netusb/setListControl?list_id=main&type=select&index=",
	"selectMenuItem"      => "/v1/netusb/setListControl?list_id=main&type=select&selectMenu=",		
	"selectPlayMenu"        => "/v1/netusb/setListControl?list_id=main&type=play&index=",	
	"selectPlayMenuItem"   => "/v1/netusb/setListControl?list_id=main&type=play&selectMenu=",		
	"getPlayInfo:noArg"           => "/v1/netusb/getPlayInfo",
	"playback:play,stop,pause,play_pause,previous,next,fast_reverse_start,fast_reverse_end,fast_forward_start,fast_forward_end"  => "/v1/netusb/setPlayback?playback=",
	"getMenu:noArg"			    => "/v1/netusb/getListInfo?input=net_radio&index=0&size=8&lang=en",
	"getMenuItems:noArg"			=> "/v1/netusb/getListInfo?input=net_radio&index=0&size=8&lang=en",
	"returnMenu:noArg"			=> "/v1/netusb/setListControl?list_id=main&type=return",
	"getDeviceInfo:noArg"         => "/v1/system/getDeviceInfo",
	"getSoundProgramList"   => "/v1/main/getSoundProgramList",	
	"setSoundProgramList"   => "/v1/main/setSoundProgram?program=",
    "setFmTunerPreset"      => "/v1/tuner/recallPreset?zone=main&band=fm&num=",
	"setDabTunerPreset"      => "/v1/tuner/recallPreset?zone=main&band=dab&num=",
	"setNetRadioPreset"		=> "/v1/netusb/recallPreset?zone=main&num=",
    "TurnFavNetRadioChannelOn:noArg"  => "batch_cmd",	
	"TurnFavServerChannelOn:noArg"  => "batch_cmd",	
	"navigateListMenu"  => "batch_cmd",	
	"NetRadioNextFavChannel:noArg" => "batch_cmd",	
	"NetRadioPrevFavChannel:noArg" => "batch_cmd",	
	"sleep:0,30,60,90,120"  => "/v1/main/setSleep?sleep=",	
    "getNetworkStatus:noArg"      => "/v1/system/getNetworkStatus",
	"getLocationInfo:noArg"       => "/v1/system/getLocationInfo",
	"getDistributionInfo:noArg"   => "/v1/dist/getDistributionInfo",
	"getBluetoothInfo:noArg"	    => "/v1/system/getBluetoothInfo",
    "enableBluetooth:true,false"      => "/v1/system/setBluetoothTxSetting?enable=",
	"setGroupName"            => "/v1/dist/setGroupName",
	"mcLinkTo"                 => "batch_cmd",	
	"speakfile"                 => "batch_cmd",	
	"mcUnLink"                 => "batch_cmd",		
	"setServerInfo"           => "/v1/dist/setServerInfo",
	"setClientInfo"           => "/v1/dist/setClientInfo",
	"startDistribution"    => "/v1/dist/startDistribution?num=0",
	"isNewFirmwareAvailable"    => "/v1/system/isNewFirmwareAvailable?type=network",
    "statusRequest:noArg"    => "/v1/main/getStatus"		
    );

# ------------------------------------------------------------------------------
# YAMAHA_MC_Initialize
# ------------------------------------------------------------------------------
sub YAMAHA_MC_Initialize($)  
{
  my ($hash) = @_;
  
#used to define funktions that are called from fhem
#see: http://www.fhemwiki.de/wiki/DevelopmentModuleIntro
  $hash->{DefFn}        = "YAMAHA_MC_Define";
  $hash->{GetFn}        = "YAMAHA_MC_Get";
  $hash->{SetFn}        = "YAMAHA_MC_Set";
  $hash->{AttrFn}       = "YAMAHA_MC_Attr";
  $hash->{UndefFn}      = "YAMAHA_MC_Undef";
  $hash->{ShutdownFn}	= "YAMAHA_MC_Shutdown";
  $hash->{DeleteFn}	    = "YAMAHA_MC_Delete";

# modules attributes
  $hash->{AttrList}     = "do_not_notify:0,1 ".
                          "disable:1,0 ".                         
						  "disabledForIntervals ".
                          "request-timeout:1,2,3,4,5,10 ".
                          "model ".
					      "standard_volume:15 ".
						  "ttsvolume ".
					      "volumeSteps:3 ".                                             					     
						  "pathToFavoriteServer ".
						  "FavoriteServerChannel ".						 
					      "FavoriteNetRadioChannel ".
					      "autoplay_disabled:true,false ".	
                          "autoReadReg:4_reqStatus ".
                          "actCycle:off ".
						  "DLNAsearch:on,off ".
						  "DLNAServer ".
                          "powerCmdDelay ".
						  "menuLayerDelay ".						
						  "homebridgeMapping ".
                          $readingFnAttributes;
}


# ------------------------------------------------------------------------------
# YAMAHA_MC_Define
# ------------------------------------------------------------------------------
sub YAMAHA_MC_Define($$)  # only called when defined, not on reload.
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $usg = "Use 'define <name> YAMAHA_MC <ip|fqdn> PORT  <ON-statusinterval> <OFF-statusinterval> ";

  if(! @a >= 4)
    {      
      Log3  $hash->{NAME}, 1, $usg;
      return $usg;
    }
	
  return "Wrong syntax: $usg" if(int(@a) < 2);

  # Init Vars 
  my $name = "unknown";
  my $type = "unknown";
  my $host = "unknown";
  my $zone = "unknown";
  
  $hash->{DEVICEID} = "0";
  $hash->{STATE} = "initialized";
  
  unless(defined($hash->{NAME})) {$hash->{NAME}="unknown";}
  unless(defined($hash->{HOST})) {$hash->{HOST}="unknown";}
  unless(defined($hash->{OFF_INTERVAL})) {$hash->{OFF_INTERVAL}=120;}
  unless(defined($hash->{ON_INTERVAL})) {$hash->{ON_INTERVAL}=60;}
  unless(defined($hash->{PORT})) {$hash->{PORT}=80;}
  unless(defined($hash->{ZONE})) {$hash->{ZONE}="main";}
  unless(defined($hash->{ACTIVE_ZONE})) {$hash->{ACTIVE_ZONE}="main";}
  unless(defined($hash->{API_VERSION})) {$hash->{API_VERSION}="1";}
  unless(defined($hash->{settingChannelInProgress})) {$hash->{settingChannelInProgress}=0;}
  unless(defined($hash->{attemptsToReturnMenu})) {$hash->{attemptsToReturnMenu}=0;}
  unless(defined($hash->{PowerOnInProgress})) {$hash->{PowerOnInProgress}=0;}
  unless(defined($hash->{LastTtsFile})) {$hash->{LastTtsFile}="";}
  unless(defined($hash->{helper}{TIMEOUT_COUNT})) {$hash->{helper}{TIMEOUT_COUNT}=0;}
      
    
  $name = $a[0];
  $type = $a[1];
  $host = $a[2];
  $hash->{PORT} = !$a[3] ? 80 : $a[3];
  
  # would be better to get this from http like
  # http://192.168.0.28:49154/MediaRenderer/desc.xml
  $hash->{URLCMD} = "/YamahaExtendedControl";
  
  my $VERSION = "v2.1.0";
  $hash->{VERSION} = $VERSION;
  Log3 $hash, 3, "Yamaha MC : $VERSION";


  #check that ip or fqdn are valid
  if (YAMAHA_MC_isIPv4($host) || YAMAHA_MC_isFqdn($host)) {
    $hash->{HOST} = $host
  } else {
    return "ERROR: invalid IPv4 address or fqdn: '$host'"
  }
  

   # if an update interval was given which is greater than zero, use it.
    if(defined($a[4]) and $a[4] > 0)
    {
        $hash->{OFF_INTERVAL} = $a[4];
    }
    else
    {
        $hash->{OFF_INTERVAL} = 120;
    }
      
    if(defined($a[5]) and $a[5] > 0)
    {
        $hash->{ON_INTERVAL} = $a[5];
    }
    else
    {
	  if(defined($a[4]) and $a[4] > 0){
        $hash->{ON_INTERVAL} = $hash->{OFF_INTERVAL};
		}
	   else{
	    $hash->{ON_INTERVAL} = 60;
	   }
    }
	
	# Select Zone
	if(defined($a[6])) {
	  unless(defined($hash->{helper}{SELECTED_ZONE})) {$hash->{helper}{SELECTED_ZONE}=$a[6];}
	  $hash->{ZONE}=$a[6];
	  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: $hash->{NAME} Setting selected zone to ".$a[6];	  
	}
	else {
	  $hash->{ZONE}="main";
	  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: $hash->{NAME} no zone defined in device using main ";
	}
	
	# create empty CMD Queue 
	$hash->{helper}{CMD_QUEUE} = [];
    delete($hash->{helper}{".HTTP_CONNECTION"}) if(exists($hash->{helper}{".HTTP_CONNECTION"}));
	
	
	# Presence Status setzen
	unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
    {
        $hash->{helper}{AVAILABLE} = 1;
        readingsSingleUpdate($hash, "presence", "present", 1);
		readingsSingleUpdate($hash, 'state', 'present',1);
    }
	
	# Disabled setzen Default=0
	$hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));	

	#Check if Json isntalled
    $hash->{helper}{noPm_JSON} = 1 if (YAMAHA_MC_isPmInstalled($hash,"JSON"));

	
	# In case of a redefine, check the zone parameter if the specified zone exist, otherwise use the main zone
	Log3 $hash->{NAME}, 4, "$hash->{TYPE}: $hash->{NAME} trying to get zones";
    if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
    {
        if(defined(YAMAHA_MC_getParamName($hash, lc($hash->{helper}{SELECTED_ZONE}), $hash->{helper}{ZONES})))
        {
            $hash->{ACTIVE_ZONE} = lc($hash->{helper}{SELECTED_ZONE}); 
			Log3 $name, 1, "$type: $name  - set active zone to ".$hash->{ACTIVE_ZONE};
        }
        else
        {
            Log3 $name, 1, "$type: $name  - selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available on device ".$hash->{NAME}.". Using Main Zone instead";
            $hash->{ACTIVE_ZONE} = "main";
        }
		Log3 $name, 1, "$type: $name  - selected zone getting inputs via YAMAHA_MC_getInputs ";		
    }
	
	readingsSingleUpdate($hash, 'state', 'opened',1);    
    
	my $DLNAsearch = AttrVal($hash->{NAME}, "DLNAsearch","on");
	
	readingsSingleUpdate($hash, "DLNARenderer", "unknown", 1);
    readingsSingleUpdate($hash, 'MediaServer', 'unknown',1);
	  
	if ($DLNAsearch eq "on") {
	  
	  YAMAHA_MC_setupControlpoint($hash);
	  YAMAHA_MC_setupMediaRenderer($hash);
	  
	  Log3 $hash->{NAME}, 2, "$type: $name  DLNAsearch turned $DLNAsearch setting timer for getting devices in 150Secs";
	  InternalTimer(gettimeofday() + 120, 'YAMAHA_MC_getNetworkStatus', $hash, 0);
	  InternalTimer(gettimeofday() + 150, 'YAMAHA_MC_DiscoverDLNAProcess', $hash, 0);	  
	 }
	 else
	 {
	   
	   Log3 $name, 1, "$type: $name  - DLNASearch turned $DLNAsearch";
	   Log3 $name, 1, "$type: $name  - starting InternalTimer YAMAHA_MC_DiscoverDLNAProcess anyway once in 150Secs";
	   
	   YAMAHA_MC_setupControlpoint($hash);
	   YAMAHA_MC_setupMediaRenderer($hash);
	   InternalTimer(gettimeofday() + 150, 'YAMAHA_MC_DiscoverDLNAProcess', $hash, 0);	  
	 }
    
	Log3 $hash->{NAME}, 1, "$type: $name  opened device $name -> host:$hash->{HOST}:".
                         "$hash->{PORT}".
						 " $hash->{OFF_INTERVAL}".
						 " $hash->{ON_INTERVAL}".
						 " $hash->{ZONE}";						 

						 
    # start the status update timer in one second  
    Log3 $hash->{NAME}, 2, "$type: $name  device $name defined for first time, starting Timer to get status YAMAHA_MC_ResetTimer";
    YAMAHA_MC_ResetTimer($hash,1);	
	
	return undef;
}
# ------------------------------------------------------------------------------
# YAMAHA_MC_setupControlpoint
# ------------------------------------------------------------------------------
sub YAMAHA_MC_setupControlpoint {
  my ($hash) = @_;
  my $error;
  my $cp;
  my @usedonlyIPs = split(/,/, AttrVal($hash->{NAME}, 'usedonlyIPs', ''));
  my @ignoredIPs = split(/,/, AttrVal($hash->{NAME}, 'ignoredIPs', ''));
  
  do {
    eval {
     #$cp = UPnP::ControlPoint->new(SearchPort => 0, SubscriptionPort => 0, MaxWait => 30, UsedOnlyIP => \@usedonlyIPs, IgnoreIP => \@ignoredIPs, LogLevel => AttrVal($hash->{NAME}, 'verbose', 0));
      $cp = Net::UPnP::ControlPoint->new();
	  $hash->{helper}{controlpoint} = $cp;            
    };
    $error = $@;
  } while($error);
  
  return undef;
}
# ------------------------------------------------------------------------------
# YAMAHA_MC_setupMediaRenderer
# ------------------------------------------------------------------------------
sub  YAMAHA_MC_setupMediaRenderer{
  my ($hash) = @_;
  my $error;
  my $MediaRenderer;
  my @usedonlyIPs = split(/,/, AttrVal($hash->{NAME}, 'usedonlyIPs', ''));
  my @ignoredIPs = split(/,/, AttrVal($hash->{NAME}, 'ignoredIPs', ''));
  
  do {
    eval {
      $MediaRenderer = Net::UPnP::AV::MediaRenderer->new();
      $hash->{helper}{MediaRenderer} = $MediaRenderer;            
    };
    $error = $@;
  } while($error);
  
  return undef;
}


# ------------------------------------------------------------------------------
#DiscoverDLNA: discover DLNA REnderer und MediaServer (miniDLNA)
#started vie Timer in Define
# ------------------------------------------------------------------------------
sub YAMAHA_MC_DiscoverDLNAProcess($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $hash->{NAME}, 4, "$name YAMAHA_MC_DiscoverDLNAProcess started";
    
  my $DLNAsearch = AttrVal($hash->{NAME}, "DLNAsearch","off");
  
  Log3 $name, 4, "$name YAMAHA_MC_DiscoverDLNAProcess started, DLNAsearch turned $DLNAsearch ";
  
  if(!$init_done) {
        #init not done yet, wait 5 more seconds
		Log3 $name, 4, "$name YAMAHA_MC_DiscoverDLNAProcess started, init not completed yet, restarting in 5 Seks ";
        InternalTimer(gettimeofday()+5, "YAMAHA_MC_DiscoverDLNAProcess", $hash, 0);
		return undef;
    }
	
  if ($DLNAsearch eq "on") {
  
	  Log3 $name, 4, "$name YAMAHA_MC_DiscoverDLNAProcess calling YAMAHA_MC_DiscoverDLNAServer";
	  YAMAHA_MC_DiscoverMediaServer($hash);
	  Log3 $name, 4, "$name YAMAHA_MC_DiscoverDLNAProcess calling YAMAHA_MC_DiscoverRenderer";
	  YAMAHA_MC_DiscoverRenderer($hash);
	  
	  Log3 $name, 4, "$name YAMAHA_MC_DiscoverDLNAProcess returning";
  }  
  else
  {
    Log3 $name, 4, "$name YAMAHA_MC_DiscoverDLNAProcess DLNAsearch is turned $DLNAsearch";
  }
  return undef;
}



# ------------------------------------------------------------------------------
# YAMAHA_MC_Undef
#UndefFn: called while deleting device (delete-command) or while rereadcfg
# ------------------------------------------------------------------------------
sub YAMAHA_MC_Undef($$)
{
  my ($hash, $arg) = @_;
  
  # Stop all timers and exit
  RemoveInternalTimer($hash);

  # kill BlockingCalls if still exists
  BlockingKill($hash->{helper}{DISCOVERY_SERVER_PID}) if(defined($hash->{helper}{DISCOVERY_SERVER_PID}));  
  BlockingKill($hash->{helper}{DISCOVERY_RENDERER_PID}) if(defined($hash->{helper}{DISCOVERY_RENDERER_PID}));  
     
    
  HttpUtils_Close($hash);
  return undef;
}


# ------------------------------------------------------------------------------
#ShutdownFn: called before fhem's shutdown command
# ------------------------------------------------------------------------------
sub YAMAHA_MC_Shutdown($)
{
	my ($hash) = @_;
	
	# kill BlockingCalls if still exists
  BlockingKill($hash->{helper}{DISCOVERY_SERVER_PID}) if(defined($hash->{helper}{DISCOVERY_SERVER_PID}));  
  BlockingKill($hash->{helper}{DISCOVERY_RENDERER_PID}) if(defined($hash->{helper}{DISCOVERY_RENDERER_PID}));  
	
  HttpUtils_Close($hash);
  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: device $hash->{NAME} shutdown requested";
	return undef;
}


# ------------------------------------------------------------------------------
#DeleteFn: called while deleting device (delete-command) but after UndefFn
# ------------------------------------------------------------------------------
sub YAMAHA_MC_Delete($$)
{
  my ($hash, $arg) = @_;
  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: $hash->{NAME} deleted";
  return undef;
}

# ------------------------------------------------------------------------------
# YAMAHA_MC_Attr
# ------------------------------------------------------------------------------
sub YAMAHA_MC_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{NAME};
  my $ret = undef;

  # InternalTimer will be called from notifyFn if disabled = 0
  if ($aName eq "disable") {
    $ret="0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/);
    if ($cmd eq "set" && $aVal == 1) {
      Log3 $name, 2,"$type: $name is disabled";
      readingsSingleUpdate($hash, "state", "disabled",1);
    }
    elsif ($cmd eq "del" || $aVal == 0) {
      readingsSingleUpdate($hash, 'state', 'opened',1);
    }
	
	# start the status update timer in one second   
	Log3 $name, 4,"$type: $name YAMAHA_MC_Attr Resetting timer";
    YAMAHA_MC_ResetTimer($hash,1);	
	
  }

  if (defined $ret) {
    Log3 $name, 4, "$type: attr $name $aName $aVal != $ret";
    return "$aName must be: $ret";
  }
  
  # wenn DLNAsearch eingeschaltet wird, dann Suche starten    
	if (($aName eq "DLNAsearch") && ($aVal eq "on") && ($init_done==1)){
		Log3 $name, 3, "YAMAHA_MC_Attr changed attr $name $aName $aVal, start DLNASearch via Timer in 150Seks";		
		InternalTimer(gettimeofday() + 120, 'YAMAHA_MC_getNetworkStatus', $hash, 0);
	    InternalTimer(gettimeofday() + 150, 'YAMAHA_MC_DiscoverDLNAProcess', $hash, 0);		
	}


  return undef; #attribut will be accepted if undef
}

# ------------------------------------------------------------------------------
# YAMAHA_MC_GetStatus
# ------------------------------------------------------------------------------
sub YAMAHA_MC_GetStatus($;$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};    
	my $type = $hash->{NAME};
   
    $local = 0 unless(defined($local));
	
	# default priority for local called (=immediate) request
    my $priority = 3;
	
	my $currentpower= ReadingsVal($name, "power", "off");
	my $currentstate= ReadingsVal($name, "state", "off");
	
	Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus cancelled, missing parameter Host=$hash->{HOST} Off_Interval=$hash->{OFF_INTERVAL} On_Interval=$hash->{ON_INTERVAL}" if(!defined($hash->{HOST}) or !defined($hash->{OFF_INTERVAL}) or !defined($hash->{ON_INTERVAL}));
    return undef if(!defined($hash->{HOST}) or !defined($hash->{OFF_INTERVAL}) or !defined($hash->{ON_INTERVAL}));

	# if not called local, so through standard request time 
	# then lower priority
	if ($local==0){	 
	 $priority = 5;
	}
	
    Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus try to getInputs ";
	
	# get all available inputs if nothing is available
    Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus fetching Inputs now, also getting status";
	
	# this calls getstatus 
	YAMAHA_MC_getInputs($hash);
		
    if ($currentpower eq "on"){
		# get current menuitems nothing is available
		Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus fetching ListInfos now";
		YAMAHA_MC_getMenu($hash,$priority);
		
		# get current play info
		Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus fetching getPlaybackStatus now";
		YAMAHA_MC_getPlaybackStatus($hash,$priority);
		
		Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus updating ListValues for cmd now";
        YAMAHA_MC_UpdateLists($hash,$priority);	
		
    }
    else{
	  Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus device turned off , not getting some detailled status ";	  
	  Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus device turned off , deleting readings for menu layer and name ";	  
	  
	  readingsSingleUpdate($hash, 'currentMenuLayer', undef,1 );	
	  readingsSingleUpdate($hash, 'currentMenuName', undef,1 );	
	  
	  if (defined($hash->{$name}{READINGS}{currentMenuLayer})) {
	    delete($hash->{$name}{READINGS}{currentMenuLayer});
	  }
	  if (defined($hash->{$name}{READINGS}{currentMenuName})) {
	    delete($hash->{$name}{READINGS}{currentMenuName});
	  } 	
	  if (defined($hash->{READINGS}{currentMenuLayer})) {
	    delete($hash->{READINGS}{currentMenuLayer});
	  }	
	  if (defined($hash->{$name}{READINGS}{currentMenuName})) {
	    delete($hash->{READINGS}{currentMenuName});
	  }	
	  
	  	  
	  
	if((($currentpower eq "off") || ($currentpower eq "standby")) && ($currentstate eq "on")) {
	  Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus device turned off , resetting state to off status ";
	  readingsSingleUpdate($hash, "state", "off",1);
	}
			
	# get current network info
	Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus fetching getNetworkStatus now";
	YAMAHA_MC_getNetworkStatus($hash,$priority);
	
	# get current location info, including zones
	Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus fetching getLocationInfo now";
	YAMAHA_MC_getLocationInfo($hash,$priority);	
	
	
	Log3 $name, 4, "YAMAHA_MC_GetStatus Device is powered off, calling getFeatures";
	YAMAHA_MC_httpRequestQueue($hash, "getFeatures", "", {options => {at_first => 0, priority => $priority, unless_in_queue => 1}}); # call fn that will do the http request

  
	
	# get the model informations and available zones if no informations are available
	if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{helper}{ZONES}) or not defined($hash->{MODEL}) or not defined($hash->{SYSTEM_VERSION}))		
	{
		Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus updating Zones with getDeviceInfo now";
		YAMAHA_MC_getDeviceInfo($hash,$priority);			
	}
	my $zone = YAMAHA_MC_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});

	
	Log3 $name, 4, "YAMAHA_MC_GetStatus Device is powered off, calling getFuncStatus";
	YAMAHA_MC_httpRequestQueue($hash, "getFuncStatus", "", {options => {at_first => 0, priority => $priority, unless_in_queue => 1}}); # call fn that will do the http request
	
	  
	  $hash->{attemptsToReturnMenu}=0;
	  $hash->{settingChannelInProgress}=0;
	}	
	# Reset Timer for the next loop.
	# without interval parameter, so standard is used
	Log3 $name, 4, "$type: $name YAMAHA_MC_GetStatus device turned off, resetting Timer "  unless($local == 1);
    YAMAHA_MC_ResetTimer($hash) unless($local == 1);
    
    return undef;
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getInputs
# queries all available inputs and scenes
# ------------------------------------------------------------------------------

sub YAMAHA_MC_getInputs($;$)
{
    my ($hash, $priority) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
   
    Log3 $name, 4, " $name YAMAHA_MC_getInputs cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
	
	$priority = 3 unless(defined($priority));
    
	Log3 $name, 4, " $name YAMAHA_MC_getInputs starting with getStatus Function";
	
    # query all inputs and features
	YAMAHA_MC_httpRequestQueue($hash, "getStatus", "", {options => {at_first => 0, priority => $priority, unless_in_queue => 1}}); # call fn that will do the http request
	
	
	Log3 $name, 4, "$name YAMAHA_MC_getInputs ready, leaving now";
	return undef;
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getMenu
# queries all available menu infos
# ------------------------------------------------------------------------------
sub YAMAHA_MC_getMenu($;$)
{
    my ($hash, $priority) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
	
	$priority = 3 unless(defined($priority));
    
    Log3 $name, 4, "$name YAMAHA_MC_getMenu cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
    
	Log3 $name, 4, "$name YAMAHA_MC_getMenu starting getting Menu now";
	
    # query current MenuItems    
	if(ReadingsVal($name, "power", "off") eq "on"){
	  Log3 $name, 4, "$name YAMAHA_MC_getMenu Device is powered on, getting details now with getMenu";
	  YAMAHA_MC_httpRequestQueue($hash, "getMenu", "", {options => {can_fail => 1, unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	}
	else {
	  Log3 $name, 4, "$name YAMAHA_MC_getMenu Device is powered off, cannot getting details with getMenu";
	}
	
	Log3 $name, 4, "$name YAMAHA_MC_getMenu ready, leaving now";
	return undef;	
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getPlaybackStatus
# queries play status
# ------------------------------------------------------------------------------
sub YAMAHA_MC_getPlaybackStatus($;$)
{
    my ($hash, $priority) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
	
	$priority = 3 unless(defined($priority));
    
    Log3 $name, 4, "$name YAMAHA_MC_getPlaybackStatus cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
    
    # query current MenuItems    
	YAMAHA_MC_httpRequestQueue($hash, "getPlayInfo", "",{options => {unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	
	return undef;
	
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getNetworkStatus
# queries netowork status
# ------------------------------------------------------------------------------
sub YAMAHA_MC_getNetworkStatus($;$)
{
    my ($hash, $priority) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
	
	$priority = 3 unless(defined($priority));
    
	Log3 $name, 4, "$name YAMAHA_MC_getNetworkStatus cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
    
    # query current MenuItems    
	YAMAHA_MC_httpRequestQueue($hash, "getNetworkStatus", "", {options => {unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	
	# check if firmware is available
	YAMAHA_MC_httpRequestQueue($hash, "isNewFirmwareAvailable", "", {options => {unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	
	
	return undef;
	
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getLocationInfo
# queries location info
# ------------------------------------------------------------------------------
sub YAMAHA_MC_getLocationInfo($;$)
{
    my ($hash, $priority) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
	
	$priority = 3 unless(defined($priority));
    
	Log3 $name, 4, "$name YAMAHA_MC_getLocationInfo cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
    
    # query current MenuItems    
	YAMAHA_MC_httpRequestQueue($hash, "getLocationInfo", "", {options => {unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	
	return undef;
	
}


#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getDeviceInfo
# queries device info
# ------------------------------------------------------------------------------
sub YAMAHA_MC_getDeviceInfo($;$)
{
    my ($hash, $priority) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
	
	$priority = 3 unless(defined($priority));
    
	Log3 $name, 4, "$name YAMAHA_MC_getDeviceInfo cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
    
    # query current MenuItems    
	YAMAHA_MC_httpRequestQueue($hash, "getDeviceInfo", "", {options => {unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	
	return undef;
	
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_getDistributionInfo
# queries infos about linked devices
# ------------------------------------------------------------------------------
sub YAMAHA_MC_getDistributionInfo($)
{
    my ($hash) = @_;  
    my $name = $hash->{NAME};
    my $HOST = $hash->{HOST};
	
	my $priority = 3; #unless(defined($priority));
    
	Log3 $name, 4, "$name YAMAHA_MC_getDistributionInfo cancelled, missing parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));
    
    # query current MenuItems    
	Log3 $name, 4, "$name YAMAHA_MC_getDistributionInfo calling RequestQueue ";
	YAMAHA_MC_httpRequestQueue($hash, "getDistributionInfo", "", {options => {unless_in_queue => 1, priority => $priority}}); # call fn that will do the http request
	
	return undef;
	
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_DiscoverRenderer
# searching for own device as MediaREnderer for DLNA
# ------------------------------------------------------------------------------
sub  YAMAHA_MC_DiscoverRenderer($)
{    
    my ($hash) = @_;
	my $name = $hash->{NAME};
    #my ($name, $hash) = split("\\|", $string);
    #my $return = "$name";
    
	Log3 $name, 4, "$name  YAMAHA_MC_DiscoverRenderer START";
	
    #$hash = $main::defs{$name};    
	#my ($hash) = @_;  
    
	my $HOST = $hash->{HOST};    
	my $DLNAsearch = AttrVal($hash->{NAME}, "DLNAsearch","off");
  
    Log3 $name, 4, "$name  YAMAHA_MC_DiscoverRenderer DLNAsearch is turned " . $DLNAsearch . "\n";
    if ($DLNAsearch eq "on") {
  
		#my $ControlPointDLNA = Net::UPnP::ControlPoint->new();
		my $ControlPointDLNA = $hash->{helper}{controlpoint} ;  
		
		#my $MediaRendererDLNA = Net::UPnP::AV::MediaRenderer->new();
		my $MediaRendererDLNA = $hash->{helper}{MediaRenderer};
	 
		Log3 $name, 4, "$name YAMAHA_MC_DiscoverRenderer start search for own dlna Renderer";
	 
		my @dev_list = ();
		my $retry_cnt = 0;
		while (@dev_list <= 0 || $retry_cnt > 5) {
			@dev_list = $ControlPointDLNA->search(st =>'upnp:rootdevice', mx => 3);
			$retry_cnt++;
		} 
	 
		# Network Name als DLNA Renderer verwenden		
		if (!defined($hash->{network_name})) {
		  Log3 $name, 4, "$name YAMAHA_MC_DiscoverRenderer Networkname not yet defined, query network first, i try again later, exiting";	  
		  YAMAHA_MC_getNetworkStatus($hash,2);
		  InternalTimer(gettimeofday() + 5, 'YAMAHA_MC_DiscoverRenderer', $hash, 0);
		  return undef;
		}
	
        
        unless(defined($hash->{network_name})) {$hash->{network_name}='No Network name available'};
	 
		my $devNum= 0;
		foreach my $dev (@dev_list) {
			my $device_type = $dev->getdevicetype();
			if  ($device_type ne 'urn:schemas-upnp-org:device:MediaRenderer:1') {
				next;
			}
			my $friendlyname = $dev->getfriendlyname(); 
			Log3 $name, 4, "$name  YAMAHA_MC_DiscoverRenderer MediaRendererDLNA found [$devNum] : " . $friendlyname . "\n";
			
			if ($friendlyname eq $hash->{network_name}) {		  
			  Log3 $name, 4, "$name  YAMAHA_MC_DiscoverRenderer MediaRendererDLNA searched device found [$devNum] : " . $friendlyname . "\n";
			  $MediaRendererDLNA->setdevice($dev);
			  $MediaRendererDLNA->stop();
			  
					  
			  Log3 $name, 4, "$name YAMAHA_MC_DiscoverRenderer Saving MediaRendererDLNA in helper ";
			  $hash->{helper}{MediaRendererDLNA}=$MediaRendererDLNA;
			  
			  readingsSingleUpdate($hash, "DLNARenderer", $friendlyname, 1);
      			  
			  Log3 $name, 4, "$name YAMAHA_MC_DiscoverRenderer Saving MediaRendererDLNA in helper done";
			  
			  if (exists($hash->{helper}{MediaRendererDLNA})) {
				 Log3 $hash, 3,   "$name YAMAHA_MC_DiscoverRenderer MediaRendererDLNA exists now";				 
			 }		   
			 else {
			   Log3 $hash, 3,  "$name YAMAHA_MC_DiscoverRenderer MediaRendererDLNA still does not exist";			
			 }
			  
			  #Log3 $name, 4, "$name  getting Media Renderer Transport Service ";
			  #my $condir_service = $dev->getservicebyname('urn:schemas-upnp-org:service:AVTransport:1');
			  #Log3 $name, 4, "$name  saving Media Renderer Transport Service in Helper";
			  #$hash->{helper}{MediaRendererDLNACondirService}=$dev;
			  
			  last;
			}
			$devNum++;
		}
  }

     if($@) {
        Log3 $hash, 3, "YAMAHA_MC_DiscoverRenderer: Discovery failed with: $@";
    }

    return undef;
  }
  
#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_DiscoverMediaServer
# searching for MediaServer which has access to speak files for DLNA
# ------------------------------------------------------------------------------  

sub  YAMAHA_MC_DiscoverMediaServer($)
{
 
    my ($hash) = @_;
	my $name = $hash->{NAME};
    #my ($name, $hash) = split("\\|", $string);
    #my $return = "$name";    
    #$hash = $main::defs{$name}; 
    #my ($hash) = @_;  
	Log3 $name, 4, "$name  YAMAHA_MC_DiscoverMediaServer START";
    
	my $HOST = $hash->{HOST};    
	my $miniDLNAname = AttrVal($hash->{NAME}, "DLNAServer","miniDLNA");	
	my $DLNAsearch = AttrVal($hash->{NAME}, "DLNAsearch","off");
  
    if ($DLNAsearch eq "on") {
	    
		my @dev_list = ();
	    my $retry_cnt = 0;    
	
		while (@dev_list <= 0 ) {
			Log3 $hash, 3,  "$name  Searching for MediaServer.. @dev_list";
			my $obj = Net::UPnP::ControlPoint->new();
			@dev_list =$obj->search(st =>'urn:schemas-upnp-org:device:MediaServer:1', mx => 5);
			$retry_cnt++;
			if ($retry_cnt >= 3) {
			Log3 $hash, 3, "$name  [!] No media found. Releasing semaphore, exiting.";		
				return undef;
			}
		}
		Log3 $hash, 3,  "$name Found $#dev_list MediaServer\n";
	 
		my $devNum= 0;
		my $dev;
		foreach $dev (@dev_list) {
		  my $device_type = $dev->getdevicetype();
		  if  ($device_type ne 'urn:schemas-upnp-org:device:MediaServer:1') {
				next;
			}
		  $devNum++;
		  my $friendlyname = $dev->getfriendlyname();
		  Log3 $hash, 3, "$name  found [$devNum] : device name: [" . $friendlyname . "] " ;
		  if ($friendlyname ne $miniDLNAname) {  
			Log3 $hash, 3,  "$name  skipping this device.";
			next;
			}
		  else {
	        Log3 $name, 4, "$name YAMAHA_MC_DiscoverMediaServer found correct media server : $friendlyname";
	      }

		  Log3 $hash, 3,  "Init MediaServer now";
		   my $MediaServer = Net::UPnP::AV::MediaServer->new();
		   $MediaServer->setdevice($dev);
		   Log3 $name, 4, "$name  Saving MediaServer in helper ";
		   $hash->{helper}{MediaServerDLNA}=$dev;
		   readingsSingleUpdate($hash, 'MediaServer', $friendlyname,1);
		   		   
		   Log3 $name, 4, "$name  Saving MediaServer in helper done";		  
		   last;	   
		  }		
	}
	
	if($@) {
        Log3 $hash, 3, "YAMAHA_MC_DiscoverMediaServer: $name  Discovery failed with: $@";
    }

    return undef;
}


#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_SpeakFile
# playing speakfile provided by tts to MediaServer via DLNAREnderer
# ------------------------------------------------------------------------------  


sub YAMAHA_MC_SpeakFile($$)  # only called when defined, not on reload.
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
  
    my $HOST = $hash->{HOST};
    my $name = $hash->{NAME};
	
	# wenn nicht definiert, dann gleich beenden
	Log3 $name, 4, "$name YAMAHA_MC_SpeakFile called, parameter Host=$hash->{HOST} " if(!defined($hash->{HOST}));
    return undef if(not defined($HOST));

	my $DLNAsearch = AttrVal($hash->{NAME}, "DLNAsearch","off");
    if ($DLNAsearch eq "off") {
	 Log3 $name, 5, "$name YAMAHA_MC_SpeakFile called without DLNAsearch ";
     return undef;	
	}
	
    my $searchfilename = $a[0];
		
	if (defined($searchfilename)) {
	  $hash->{LastTtsFile}=$searchfilename;
	}
	else
	{
	  if (defined($hash->{LastTtsFile})) {
	    $searchfilename=$hash->{LastTtsFile};
	  }
	}
  
    my $originalSearchfilename = $searchfilename; 
    if (substr($searchfilename,-4) eq '.mp3') {
	  $searchfilename = substr($searchfilename,1,-4);
    }
    Log3 $name, 4, "$name YAMAHA_MC_SpeakFile searchfile $searchfilename";
	
	# Dateinamen merken fuers Loeschen
	# Bereinigung Searchfilename
    # Pfad und Endung entfernen
	#
	
	# Fuer DLNA suche nur den basename verwenden
    my $lastslashpos = rindex($searchfilename, "/");  
    $searchfilename = substr($searchfilename,$lastslashpos+1);
    Log3 $name, 4, "$name YAMAHA_MC_SpeakFile searchfile $searchfilename";
  	 

	#
	# aktuelle Werte merken
	# Volume Steuerung und Power
	#
	my $currentPower= ReadingsVal($name, "power", "off");
	my $currentState= ReadingsVal($name, "state", "off");
	my $currentPlayback= ReadingsVal($name, "playback_status", "play");
	my $powerCmdDelay = AttrVal($hash->{NAME}, "powerCmdDelay",3);
	
	my $standardVolume = AttrVal($hash->{NAME}, "standard_volume",15);
	my $ttsvolume = AttrVal($hash->{NAME}, "ttsvolume",undef);	
	my $currentInput = ReadingsVal($name, "input", "unknown"); 	
	my $currentVolume = ReadingsVal($name, "volume", 0); 
	my $currentMute = ReadingsVal($name, "mute", "false"); 
		
		
	if ($currentPower ne "on") {
	  Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile device not turned on powerstate is ($currentPower), power on first ";
	  # Power merken, um spaeter zurückschalten zu können
	  $hash->{helper}{OriginalPowerState} = $currentPower;
	  
	  YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options    => {unless_in_queue => 1, at_first => 1, priority => 1, wait_after_response => $powerCmdDelay, original_cmd => "speakfile", original_priority => 1}}); # call fn that will do the http request
	  return undef;
	}
	else {
	  Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile device already turned on, continue ";
	}
	
	if (not defined($hash->{helper}{OriginalPowerState})) {
	  $hash->{helper}{OriginalPowerState} = $currentPower;
	}
	
		
	if ( (!defined($currentInput)) || ($currentInput ne "server")) {
	  Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile current input is set $currentInput and not to server, setting input first ";
	  # Input merken, um spaeter zurückschalten zu können
	  $hash->{helper}{OriginalInput} = $currentInput;
	  $hash->{helper}{OriginalPlayback} = $currentPlayback;
	  # Server input ohne Autoplay aufrufen
	  YAMAHA_MC_httpRequestQueue($hash, "input", "server mode=autoplay_disabled",  {options    => {unless_in_queue => 1, can_fail => 1, priority => 1, original_cmd => "speakfile", original_priority => 1}}); # call fn that will do the http request
	  return undef;
	}
	else {
	  Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile input defined and already set to $currentInput, continue ";
	}
			
    Log3 $name, 4, "YAMAHA_MC_SpeakFile setting volume from old $currentVolume to new volume $ttsvolume"; 
	if (defined($ttsvolume)) {
	  if ($ttsvolume != $currentVolume) {
		  # Volume merken, um spaeter zurückschalten zu können
		  $hash->{helper}{OriginalVolume} = $currentVolume;	  
		  YAMAHA_MC_httpRequestQueue($hash, "volume",   YAMAHA_MC_volume_rel2abs($hash,$ttsvolume), {options    => {unless_in_queue => 1, can_fail => 1,priority => 2, volume_target => $ttsvolume, original_cmd => "speakfile", original_priority => 1}}); # call fn that will do the http request			  
		  return undef; 
		  }  	
		else {
		  Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile volume correctly set to  and already set to $currentVolume, continue ";
		}  
     }
     else {
        Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile no ttsvolume set, continue with current volumne ";
    }	 
	
	# turn muting off
	if ($currentMute eq "true"){
	  Log3 $name, 4, "YAMAHA_MC_SpeakFile mute not false $currentMute setting to false ";
	  YAMAHA_MC_httpRequestQueue($hash, "mute", "false", {options    => {unless_in_queue => 1, can_fail => 1}}); 
	}    
	else {
	  Log3 $name, 4, "$name : YAMAHA_MC_SpeakFile mute correctly set to $currentMute, continue ";
	}  
	
	my $URILink;
	my @usedonlyIPs = split(/,/, AttrVal($hash->{NAME}, 'usedonlyIPs', '')); 
    my @ignoredIPs = split(/,/, AttrVal($hash->{NAME}, 'ignoredIPs', ''));
	
	# Network Name als DLNA Renderer verwenden
	
	unless(defined($hash->{network_name})) {$hash->{network_name}='No Network name available'};
	
	
	Log3 $name, 4, "$name YAMAHA_MC_SpeakFile Networkname $hash->{network_name}";	
	Log3 $name, 4, "$name YAMAHA_MC_SpeakFile restart minidlna and rescan";
	
	# restarting miniDLNA to rescan files
	my $ret = "";
    $ret .= qx([ -f /usr/sbin/minidlnad ] && sudo minidlnad -R || sudo minidlna -R);
	Log3 $name, 4, "$name YAMAHA_MC_SpeakFile rescan return $ret";
	$ret .= qx(sudo service minidlna restart);
	Log3 $name, 4, "$name YAMAHA_MC_SpeakFile restart return $ret";
	   
    
	my $DLNARendererName = ReadingsVal($name, "DLNARenderer", "unknown");
	my $DLNAMediaServerName = ReadingsVal($name, "MediaServer", "unknown");
	
	
	#
	# Renderer ermitteln
	#
	 if ((exists($hash->{helper}{MediaRendererDLNA})) && ($DLNARendererName ne "unknown"))  {
		 Log3 $hash, 3,   "$name YAMAHA_MC_SpeakFile MediaRendererDLNA exists, not restarting discovery";				 
		 Log3 $hash, 3,   "$name YAMAHA_MC_SpeakFile  Stopping   MediaRendererDLNA";
		 $hash->{helper}{MediaRendererDLNA}->stop(); 
	 }		   
	 else {
	   Log3 $hash, 3,   "$name YAMAHA_MC_SpeakFile MediaRendererDLNA does not exists, restarting discovery";		
       YAMAHA_MC_DiscoverRenderer($hash);		
	 } 
	
	
	
	
	#
    # searching for mediaServer miniDLNA
	#	 
	 if ((exists($hash->{helper}{MediaServerDLNA})) && ($DLNAMediaServerName ne "unknown")) {
	     Log3 $name, 4, "$name YAMAHA_MC_SpeakFile MediaServerDLNA exists, not restarting discovery";		 
     }		   
	 else {
	   Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile  MediaServerDLNA still not defined";
	   Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile  restarting YAMAHA_MC_DiscoverMediaServer again ...";
	   YAMAHA_MC_DiscoverMediaServer($hash);	
	 }
	 
	 # perhaps after re-discovering, now available ?
	 $DLNARendererName = ReadingsVal($name, "DLNARenderer", "unknown");
	 $DLNAMediaServerName = ReadingsVal($name, "MediaServer", "unknown");

	 Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Getting  ContentDirectory";
     #my $condir_service = $dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1'); 
	 if ((exists($hash->{helper}{MediaServerDLNA})) && ($DLNAMediaServerName ne "unknown")) {
		  my $condir_service = $hash->{helper}{MediaServerDLNA}->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1');
	  
		  #unless (defined(condir_service)) {
		  #      next;
		  #  }
		  Log3 $hash, 3,  "Setting Browse Args";
		  if (defined($condir_service)) 
		  {
			my %action_in_arg = (
					'ObjectID' => '64',
					'BrowseFlag' => 'BrowseDirectChildren',
					'Filter' => '*',
					'StartingIndex' => 0,
					'RequestedCount' => 100,
					'SortCriteria' => '',
				);
			Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFileStart Browsing";		
			my $action_res = $condir_service->postcontrol('Browse', \%action_in_arg);
			Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFileGetting Browsing result";		
			my $actrion_out_arg = $action_res->getargumentlist();
			
			Log3 $hash, 4, "$name YAMAHA_MC_SpeakFileArgument List is  $actrion_out_arg";
			
			Log3 $hash, 4, "$name YAMAHA_MC_SpeakFileDumper List is  \n";
			Log3 $name, 5, Dumper($actrion_out_arg);
			
				
			
			#Net::UPnP::ActionResponse
			
			#Log3 $hash, 3,  "Getting CurrentTransportState result";		
			#my $CurrentTransportState = $actrion_out_arg->{'CurrentTransportState'};
			#Log3 $hash, 4, "Device current state is <<$CurrentTransportState>>. ";
			
			my $result = $actrion_out_arg->{'Result'};
			my @durationresult;
			
			# ID'1 ermitteln
			
			Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Gebe gefundene Titel aus";		 
			while ($result =~ m/<dc:title>(.*?)<\/dc:title>/sgi) {			
				Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile searchfilename is <<$searchfilename>> content is <<$1>>. ";
				Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile result is <<$result>>";
				
				if ($1 eq $searchfilename) {
				  Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile searchfilename found ! "; 
				  my @resresult = $result =~ m/\<res(.+?)\<\/res\>/sgi;
				  #my $resresult = ($result =~ m/\<res(.+?)\<\/res\>/sgi);
				  
				  Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile resresult is @resresult "; 
				  
				  my $resresult = $resresult[0];
				  my @uriresult = $resresult =~ m/http:\/\/(.+?).mp3/sgi;
				  @durationresult = $resresult =~ m/duration="0:00:(.+?)"/sgi;
				  Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile uriresult is @uriresult "; 
				  Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile duration is @durationresult "; 
				  
				  $URILink = "http://@uriresult.mp3";
				  
				 # while ($result =~ m/\<res(.+?)\<\/res\>/sgi) {			
				#	Log3 $hash, 4, "html tag res content is <<$1>>. ";
				#	while ($1 =~ m/http:\/\/(.+?).mp3/sgi) {
				#	  Log3 $hash, 4, "html http url content is <<$1>>. ";
				#	  $URILink = "http://$1.mp3";
				#	}
				  #}
				  #
				  
				  last;
				}
				
			}	
					
			
			if ((defined($URILink)) and (defined($hash->{helper}{MediaRendererDLNA})) ) {
				Log3 $hash, 3,  "URI Link to play is $URILink";		 
										#$hash->{helper}{renderer}->setAVTransportURI(CurrentURI => $URILink);		
				#$hash->{helper}{renderer}->play(); 
				Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Sending Link $URILink to Renderer now";		
					$hash->{helper}{MediaRendererDLNA}->setAVTransportURI(CurrentURI => $URILink);
				Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Playing Link via Renderer now";		
	
				$hash->{helper}{MediaRendererDLNA}->play(); 
				
				Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile waiting for end @durationresult";	
				Time::HiRes::sleep(@durationresult); #.1 seconds
	
			}
			else
			{
			  Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile File $searchfilename not found or MediaRendererDLNA not found ";		
			  return "File $searchfilename not found ";
			}

		  } 
       # end if (defined($condir_service))
			
			
		Log3 $name, 4, "$name YAMAHA_MC_SpeakFile MEdia Ende";
		
			if($@) {
		
			  Log3 $hash, 4, "$name YAMAHA_MC_SpeakFile DLNARenderer: Search failed with error $@";
	  
			 }			
			 
		#warten bis AUsgabe beendet	
		#my $stillplaying = "yes";
		#while ($stillplaying eq "yes") {
	#		if (defined($hash->{helper}{MediaRendererDLNA}))  {
	#			Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Waiting for end of play  $URILink";		 					
	#			Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Getting AVTransport from Renderer now";		
	#			#my $condir_service = $hash->{helper}{MediaRendererDLNA}->getservicebyname('urn:schemas-upnp-org:service:AVTransport:1');
	#			#$hash->{helper}{MediaRendererDLNA}->getTransportInfo(CurrentURI => $URILink);
	#			
	#			Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Getting status via Renderer now";		
	#			 my %action_in_arg = (               
	#                'InstanceID' => '0'
	#            );
	#			
	#		Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Creating New Media Renderer";		
	#		my $rendererCtrl = Net::UPnP::AV::MediaRenderer->new();
	#		Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile assigning New Media Renderer";
	#        $rendererCtrl = $hash->{helper}{MediaRendererDLNA};
	#		Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile getting condirService New Media Renderer";
	#   	    my $condir_service = $rendererCtrl->getservicebyname('urn:schemas-upnp-org:service:AVTransport:1');
	#	    Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile starting postcontrol GetTransportInfo New Media Renderer";
	#        #my $action_res = $hash->{helper}{MediaRendererDLNACondirService}->postcontrol('GetTransportInfo', \%action_in_arg);
	#		my $action_res = $condir_service->postcontrol('GetTransportInfo', \%action_in_arg);
	#		Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Got CondirService from Renderer, getting arguments now";	
	#		#$hash->{helper}{MediaRendererDLNA}->setAVTransportURI(CurrentURI => $URILink);
	#        my $actrion_out_arg = $action_res->getargumentlist();
	#		Log3 $hash, 3,  "$name YAMAHA_MC_SpeakFile Got Argumentlist from CondirService, getting CurrentTransportState now";	
	#	    my $x = $actrion_out_arg->{'CurrentTransportState'};
	#	    Log3 $hash, 3, "$name YAMAHA_MC_SpeakFile Device current state is <<$x>>. ";
	#		if (uc($x) eq "STOPPED") {
	#	       Log3 $hash, 3, "$name YAMAHA_MC_SpeakFile end waiting it is  <<$x>> now. ";
	#		   $stillplaying = "no";
	#			last;
	#		}	
	#		}
	 #   }
		
		
		# Deleting tts File
		Log3 $name, 4, "$name YAMAHA_MC_SpeakFile try delete tts file $originalSearchfilename : $ret";
		$ret .= qx(timeout 2 sudo id && sudo rm -f $originalSearchfilename || rm -f $originalSearchfilename );
		Log3 $name, 4, "$name YAMAHA_MC_SpeakFile delete tts file $originalSearchfilename : $ret";
		
		if ( (defined($URILink)) and (defined($hash->{helper}{MediaRendererDLNA})) ) {
		  Log3 $name, 4, "$name YAMAHA_MC_SpeakFile stopping via Media Renderer";
		  $hash->{helper}{MediaRendererDLNA}->stop();
		}
		$hash->{LastTtsFile}="";
    }
    else {
	  Log3 $name, 3, "$name YAMAHA_MC_SpeakFile stopping MediaServerDLNA does not exist";
	}
	
	#
	# resetting input back
	# ALte Werte wiederherstellen	
	# wenn vorher eingeschaltet warn
	#if ( ($currentInput ne "server") and ($currentPower ne "on")) {
	if (($hash->{helper}{OriginalPowerState} eq "on") or ($hash->{helper}{OriginalPowerState} eq "")) {
		if  ((defined($hash->{helper}{OriginalInput})) and ($hash->{helper}{OriginalInput}  ne "server") and ($hash->{helper}{OriginalInput}  ne "")) {
		  Log3 $name, 4, "$name YAMAHA_MC_SpeakFile setting from $currentInput back to old input $hash->{helper}{OriginalInput} ";
		  YAMAHA_MC_httpRequestQueue($hash, "input", $hash->{helper}{OriginalInput},   {options => { priority => 2, unless_in_queue => 1}} ); # call fn that will do the http request
		  $hash->{helper}{OriginalInput}="";
		}
	
     	# resetting volume back
		Log3 $name, 4, "$name YAMAHA_MC_SpeakFile setting volume back to $currentVolume "; 
		if ( defined($ttsvolume) and ($ttsvolume != $hash->{helper}{OriginalVolume})){
		  YAMAHA_MC_httpRequestQueue($hash, "volume",   YAMAHA_MC_volume_rel2abs($hash,$hash->{helper}{OriginalVolume}), {options    => {unless_in_queue => 1, can_fail => 1,priority => 2, volume_target => $hash->{helper}{OriginalVolume}}}); # call fn that will do the http request			  
		  $hash->{helper}{OriginalVolume}="";
		}  	
		
		#$currentPlayback
		if (defined($hash->{helper}{OriginalInput})) { 
			Log3 $name, 4, "$name YAMAHA_MC_SpeakFile setting playback from $currentPlayback back to $hash->{helper}{OriginalPlayback}  "; 
			if ( defined($hash->{helper}{OriginalPlayback}) and ($hash->{helper}{OriginalPlayback} ne "stop") and ($hash->{helper}{OriginalPlayback} ne $currentPlayback)){
			  YAMAHA_MC_httpRequestQueue($hash, "playback", $hash->{helper}{OriginalPlayback},{options => {can_fail => 1}}); # ca
			  $hash->{helper}{OriginalPlayback} ="";
			  Log3 $name, 4, "$name YAMAHA_MC_SpeakFile setting playback from $currentPlayback back to $hash->{helper}{OriginalPlayback}  "; 
			}	
			Log3 $name, 4, "$name YAMAHA_MC_SpeakFile setting playback2 from $currentPlayback back to $hash->{helper}{OriginalPlayback}  "; 
        }
		
		# Löschen des Original Power Status
		$hash->{helper}{OriginalPowerState}="";
		# Löschen des Original Inputs
		$hash->{helper}{OriginalInput}="";
    }
    else {	
	    #
        # wenn vorher ausgeschaltet war, dann einfach wieder ausschalten
	    #
		if ( ($hash->{helper}{OriginalPowerState} ne "on") and ($hash->{helper}{OriginalPowerState} ne "") ) {
		  Log3 $name, 4, "$name YAMAHA_MC_SpeakFile device was powered off before, power off again ";
		  Log3 $name, 4, "$name YAMAHA_MC_SpeakFile OriginalPowerState is $hash->{helper}{OriginalPowerState} ";
		  YAMAHA_MC_httpRequestQueue($hash, "power", "standby", {options    => {unless_in_queue => 1, at_first => 0, priority => 2}}); # call fn that will do the http request
		  $hash->{helper}{OriginalPowerState}="";
		  # Löschen des Original Inputs
		  $hash->{helper}{OriginalInput}="";
		  return undef;
		}
	}
	
	
	Log3 $name, 4, "$name YAMAHA_MC_SpeakFile returning ... "; 
	return undef;
	
}





#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_ResetTimer
# Restarts the internal status request timer according to the given interval or current receiver state
# ------------------------------------------------------------------------------
sub YAMAHA_MC_ResetTimer($;$)
{
    my ($hash, $interval) = @_;
    my $name = $hash->{NAME};
    
	Log3 $hash->{NAME}, 4, "$hash->{TYPE}: device_ $hash->{NAME} YAMAHA_MC_ResetTimer reset timer requested";
    RemoveInternalTimer($hash, "YAMAHA_MC_GetStatus");
	
	if (($hash->{ON_INTERVAL} <5) || ($hash->{OFF_INTERVAL} <5) || (!defined($hash->{ON_INTERVAL})) ||  (!defined($hash->{OFF_INTERVAL}))){
	  Log3 $hash->{NAME}, 4, "$hash->{TYPE}: device_ $hash->{NAME} refresh interval to small or not defined";
	  return undef;
	}
    
    unless(IsDisabled($name))
    {
        if(defined($interval))
        {
            InternalTimer(gettimeofday()+$interval, "YAMAHA_MC_GetStatus", $hash,0);
			Log3 $hash->{NAME}, 4, "$hash->{TYPE}: device_ $hash->{NAME} reset timer1 in Seks $interval";
        }
        elsif((ReadingsVal($name, "presence", "absent") eq "present") && (ReadingsVal($name, "power", "off") eq "on"))
        {
            InternalTimer(gettimeofday()+$hash->{ON_INTERVAL}, "YAMAHA_MC_GetStatus", $hash, 0);
			Log3 $hash->{NAME}, 4, "$hash->{TYPE}: device_ $hash->{NAME} reset timer (on) in Seks " . $hash->{ON_INTERVAL};
        }
        else
        {
            InternalTimer(gettimeofday()+$hash->{OFF_INTERVAL}, "YAMAHA_MC_GetStatus", $hash, 0);
			Log3 $hash->{NAME}, 4, "$hash->{TYPE}: device_ $hash->{NAME} reset timer (of) in Seks" . $hash->{OFF_INTERVAL};			
        }
    }
    
    return undef;
}


#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_Get
# 
# ------------------------------------------------------------------------------

sub YAMAHA_MC_Get($@)
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  my $reading = $a[1];
  my $ret;

  if(exists($hash->{READINGS}{$reading})) {
    if(defined($hash->{READINGS}{$reading})) {
      return $hash->{READINGS}{$reading}{VAL};
    }
    else {
      return "no such reading: $reading";
    }
  }
  else {
    $ret = "unknown argument $reading, choose one of";
    foreach my $reading (sort keys %{$hash->{READINGS}}) {
      $ret .= " $reading:noArg" if ($reading ne "firmware");
    }
    return $ret;
  }
}

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_UpdateLists
# 
# ------------------------------------------------------------------------------

sub YAMAHA_MC_UpdateLists($;$)
{ 
    my ($hash, $priority) = @_;
    my $name = $hash->{NAME};	
    my $host = $hash->{HOST};
	$priority = 3 unless(defined($priority));
 
    # get all available inputs if nothing is available
    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
	    Log3 $name, 4, "YAMAHA_MC_UpdateLists helper inputs not available calling YAMAHA_MC_getInputs";
        YAMAHA_MC_getInputs($hash,$priority);			
    }
	
	# get current menu if nothing is available
    if(not defined($hash->{helper}{MENUITEMS}) or length($hash->{helper}{MENUITEMS}) == 0)
    {
        Log3 $name, 4, "YAMAHA_MC_UpdateLists helper menuitems not available calling YAMAHA_MC_getMenu";
		if(defined($hash->{helper}{MENUITEMS})){
		  Log3 $name, 4, "YAMAHA_MC_UpdateLists helper menuitems length is " .length($hash->{helper}{MENUITEMS});
		}  
		#YAMAHA_MC_getMenu($hash,$priority);			
    }

  my $inputs_piped = "";
  my $inputs_comma = "";	   
  my $menuitems_piped = "";	   
  my $menuitems_comma = "";	   
  my $soundprograms_comma = "";
  
  $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_MC_Param2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
  $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_MC_Param2Fhem(($hash->{helper}{INPUTS}), 1) : "" ;	
  $menuitems_piped = defined($hash->{helper}{MENUITEMS}) ? YAMAHA_MC_Param2Fhem(lc($hash->{helper}{MENUITEMS}), 0) : "" ;	
  $menuitems_comma = defined($hash->{helper}{MENUITEMS}) ? YAMAHA_MC_Param2Fhem(($hash->{helper}{MENUITEMS}), 1) : "" ;	
  $soundprograms_comma = defined($hash->{helper}{SOUNDPROGRAMS}) ? YAMAHA_MC_Param2Fhem(($hash->{helper}{SOUNDPROGRAMS}), 1) : "" ;	
  #my $currentMaxVolume = ReadingsVal($name, "max_volume",60);
  #my $currentMaxVolume = defined($hash->{max_volume}) ? $hash->{max_volume} : 60 ;	
      
  $hash->{helper}{menuitems_piped} = $menuitems_piped;
  $hash->{helper}{inputs_piped} = $inputs_piped;
  $hash->{helper}{inputs_comma} = $inputs_comma;
  $hash->{helper}{menuitems_comma} = $menuitems_comma;
  $hash->{helper}{soundprograms_comma} = $soundprograms_comma;
  my $currentInput = ReadingsVal($name, "input", "net_radio"); 
    
  
  Log3 $name, 5, "YAMAHA_MC_UpdateLists rearranging possible inputs inputs:".join(",",$inputs_comma);  
  Log3 $name, 5, "YAMAHA_MC_UpdateLists current menu items:".join(",",$menuitems_comma);  
  Log3 $name, 5, "YAMAHA_MC_UpdateLists current soundprograms:".join(",",$soundprograms_comma);  
  #Log3 $name, 5, "YAMAHA_MC_UpdateLists current max_volume:".join(",",$currentMaxVolume);  
  
  
  # must be set here again, because of dynamic elements with input and menulist items  
  %YAMAHA_MC_setCmdsWithArgs = (
    "on:noArg"                    => "/v1/main/setPower?power=on",	
	"off:noArg"                   => "/v1/main/setPower?power=standby",	
	"power:on,standby"		=> "/v1/main/setPower?power=",	
	"setAutoPowerStandby:true,false"    => "/v1/system/setAutoPowerStandby?enable=",
	"volume:slider,0,1,100"	=> "/v1/main/setVolume?volume=",	
	"volumeStraight"	=> "/v1/main/setVolume?volume=",
	"volumeUp:noArg"	            => "/v1/main/setVolume?volume=",	
	"volumeDown:noArg"            => "/v1/main/setVolume?volume=",
	"mute:toggle,true,false"		=> "/v1/main/setMute?enable=",	
	"setSpeakerA:toggle,true,false"		=> "/v1/main/setSpeakerA?enable=",	
	"setSpeakerB:toggle,true,false"		=> "/v1/main/setSpeakerB?enable=",		
	"setToneBass:slider,-10,1,10"           => "/v1/main/setEqualizer?low=",
	"setToneMid:slider,-10,1,10"           => "/v1/main/setEqualizer?mid=",
	"setToneHigh:slider,-10,1,10"           => "/v1/main/setEqualizer?high=",
    (exists($hash->{helper}{INPUTS}) ? "input:".$inputs_comma." " : "")  => "/v1/main/setInput?input=",	
	(exists($hash->{helper}{INPUTS}) ? "prepareInputChange:".$inputs_comma." " : "")  => "/v1/main/prepareInputChange?input=",		
	"getStatus:noArg"				=> "/v1/main/getStatus",
	"getFeatures:noArg"			=> "/v1/system/getFeatures",
	"getFuncStatus:noArg"			=> "/v1/system/getFuncStatus",	
	"selectMenu"			=> "/v1/netusb/setListControl?list_id=main&type=select&index=",
	(exists($hash->{helper}{MENUITEMS}) ? "selectMenuItem:".$menuitems_comma." " : "")  => "/v1/netusb/setListControl?list_id=main&type=select&selectMenu=",		
	"selectPlayMenu"        => "/v1/netusb/setListControl?list_id=main&type=play&index=",	
	(exists($hash->{helper}{MENUITEMS}) ? "selectPlayMenuItem:".$menuitems_comma." " : "")  => "/v1/netusb/setListControl?list_id=main&type=play&selectMenu=",		
	"getPlayInfo:noArg"           => "/v1/netusb/getPlayInfo",
	"playback:play,stop,pause,play_pause,previous,next,fast_reverse_start,fast_reverse_end,fast_forward_start,fast_forward_end"  => "/v1/netusb/setPlayback?playback=",
	"getMenu:noArg"			    => "/v1/netusb/getListInfo?input=".$currentInput."&index=0&size=8&lang=en",
	"getMenuItems:noArg"			=> "/v1/netusb/getListInfo?input=".$currentInput."&index=0&size=8&lang=en",
	"returnMenu:noArg"			=> "/v1/netusb/setListControl?list_id=main&type=return",
	"getDeviceInfo:noArg"         => "/v1/system/getDeviceInfo",
	"getSoundProgramList:noArg"   => "/v1/main/getSoundProgramList",	
	(exists($hash->{helper}{SOUNDPROGRAMS}) ? "setSoundProgramList:".$soundprograms_comma." " : "")  => "/v1/main/setSoundProgram?program=",		
    "setFmTunerPreset"      => "/v1/tuner/recallPreset?zone=main&band=fm&num=",
	"setDabTunerPreset"      => "/v1/tuner/recallPreset?zone=main&band=dab&num=",
	"setNetRadioPreset"		=> "/v1/netusb/recallPreset?zone=main&num=",
    "TurnFavNetRadioChannelOn:1,2,3,4,5,6,7,8"  => "batch_cmd",	
	"TurnFavServerChannelOn:noArg"  => "batch_cmd",	
	"navigateListMenu"  => "batch_cmd",	
	"NetRadioNextFavChannel:noArg" => "batch_cmd",	
	"NetRadioPrevFavChannel:noArg" => "batch_cmd",	
	"sleep:0,30,60,90,120"  => "/v1/main/setSleep?sleep=",	
    "getNetworkStatus:noArg"      => "/v1/system/getNetworkStatus",
	"getLocationInfo:noArg"       => "/v1/system/getLocationInfo",
	"getDistributionInfo:noArg"   => "/v1/dist/getDistributionInfo",
	"getBluetoothInfo:noArg"	    => "/v1/system/getBluetoothInfo",
    "enableBluetooth:true,false"      => "/v1/system/setBluetoothTxSetting?enable=",
	"setGroupName"            => "/v1/dist/setGroupName",
	"mcLinkTo"                 => "batch_cmd",	
	"speakfile"                 => "batch_cmd",	
	"mcUnLink"                 => "batch_cmd",		
	"setServerInfo"           => "/v1/dist/setServerInfo",
	"setClientInfo"           => "/v1/dist/setClientInfo",
	"startDistribution"    => "/v1/dist/startDistribution?num=0",
	"isNewFirmwareAvailable:noArg"    => "/v1/system/isNewFirmwareAvailable?type=network",
    "statusRequest:noArg"    => "/v1/main/getStatus"		
    );
  
  
  # create new hash without arguments
  my $key2="";
  foreach (keys%YAMAHA_MC_setCmdsWithArgs) {
  
	  my @key2 = split(/\:/, $_);   
	  my $value = $YAMAHA_MC_setCmdsWithArgs{$_};
	  my $split_key_one = "";
	  $split_key_one = ($key2[0]);
	  my %newDynamicKey;  
	  
	  if((defined($split_key_one)) && ($split_key_one ne "")){
		#Log3 $name,1, " Splitted Keyvalues : $split_key_one and Value: $value\n" ;	
		$YAMAHA_MC_setCmdswithoutArgs{$split_key_one} = $value;  
	  }	
  }

  Log3 $name, 5, "YAMAHA_MC_UpdateLists new YAMAHA_MC_setCmdswithoutArgs List for cmds :";
  Log3 $name, 5, Dumper(%YAMAHA_MC_setCmdswithoutArgs);
  Log3 $name, 5, "YAMAHA_MC_UpdateLists returning now";
  return undef;
  
}  
  

#############################
# 
# ------------------------------------------------------------------------------
# YAMAHA_MC_Set
# 
# ------------------------------------------------------------------------------

sub YAMAHA_MC_Set($$@)
{ 
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};	
    my $host = $hash->{HOST};
	my $cmd = $a[1];
	
	# create List with args only shift two times
	my @argsOnly = @a;	
	my $dummy = shift @argsOnly;
	$dummy = shift @argsOnly;
	my $argsOnlyList = join(",",@argsOnly);
	
	if($cmd eq "mcLinkTo"){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set All Args = ".join(",",@a);
	  Log3 $name, 4, "$name : YAMAHA_MC_Set Args Only = ".join(",",@argsOnly);
	 }  
    #join(",",@params);	
	   
	if(defined($cmd)){
     Log3 $name, 4, "$name : YAMAHA_MC_Set start with cmd $cmd";	 
    }
    else {
     Log3 $name, 4, "$name :YAMAHA_MC_Set start with undefined cmd";
    }   
	
   # only update cmd list if not just cmd=?	
   # otherwise to much overhead ?
   if ($cmd ne "?"){
	 # get all available inputs if nothing is available
     if(not defined($hash->{helper}{INPUTS}) || length( (exists($hash->{helper}{INPUTS}) ? $hash->{helper}{INPUTS} : "") ) == 0)
     {
        YAMAHA_MC_getInputs($hash);
     }   
	 
	# get the model informations and available zones if no informations are available
    if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{helper}{ZONES}))
    {
        YAMAHA_MC_getDeviceInfo($hash);
    }

    if(defined(YAMAHA_MC_getParamName($hash, lc($hash->{helper}{SELECTED_ZONE}), $hash->{helper}{ZONES}))) {    
      my $zone = YAMAHA_MC_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
	}
	
  	YAMAHA_MC_UpdateLists($hash);
   }  	
   
         
  my $inputs_piped = "";
  my $inputs_comma = "";	   
  my $menuitems_piped = "";	   
  my $menuitems_comma = "";	   
  my $soundprograms_comma = "";
  
  $menuitems_piped = $hash->{helper}{menuitems_piped} ;
  $inputs_piped = $hash->{helper}{inputs_piped};
  $inputs_comma = $hash->{helper}{inputs_comma};
  $menuitems_comma = $hash->{helper}{menuitems_comma};
  $soundprograms_comma = $hash->{helper}{soundprograms_comma};
  
  if ((exists($hash->{helper}{INPUTS})) && (defined($inputs_comma)) ){
    Log3 $name, 4, "$name : YAMAHA_MC_Set cmd $cmd Helper Inputs available ".$inputs_comma;	 
  }
  else {
    Log3 $name, 4, "$name : YAMAHA_MC_Set cmd $cmd NO Helper Inputs available";	 
	$inputs_comma ="";
  }
  
   if ((exists($hash->{helper}{MENUITEMS}))  && (defined($menuitems_comma)) ) {
    Log3 $name, 4, "$name : YAMAHA_MC_Set cmd $cmd Helper MENUITEMS available".$menuitems_comma;	 
  }
  else {
    Log3 $name, 4, "$name : YAMAHA_MC_Set cmd $cmd NO Helper MENUITEMS available";	 
  }
  
  return if (IsDisabled $name);

  $cmd = "?" unless defined $cmd;
  my $usage = "Unknown argument $cmd, choose one of ". "on:noArg ".
	"off:noArg ".
	"power:on,standby ".
	"setAutoPowerStandby:true,false ".
	"volume:slider,0,1,100 ".
	"volumeStraight ".
	"volumeUp:noArg ".
	"volumeDown:noArg ".
	"mute:toggle,true,false ".
	"setSpeakerA:toggle,true,false ".
	"setSpeakerB:toggle,true,false ".	
	"setToneBass:slider,-10,1,10 ".
	"setToneMid:slider,-10,1,10 ".
	"setToneHigh:slider,-10,1,10 ".
    (exists($hash->{helper}{INPUTS}) ? "input:".$inputs_comma." " : "input ")  .
	(exists($hash->{helper}{INPUTS}) ? "prepareInputChange:".$inputs_comma." " : "prepareInputChange ").
	"getStatus:noArg ".
	"getFeatures:noArg ".
	"getFuncStatus:noArg ".	
	"selectMenu ".
	(exists($hash->{helper}{MENUITEMS}) ? "selectMenuItem:".$menuitems_comma." " : "selectMenuItem ").
	"selectPlayMenu ".
	(exists($hash->{helper}{MENUITEMS}) ? "selectPlayMenuItem:".$menuitems_comma." " : "").
	"getPlayInfo:noArg ".
	"playback:play,stop,pause,play_pause,previous,next,fast_reverse_start,fast_reverse_end,fast_forward_start,fast_forward_end ".
	"getMenu:noArg ".
	"getMenuItems:noArg ".
	"returnMenu:noArg ".
	"getDeviceInfo:noArg ".
	"getSoundProgramList:noArg ".
	(exists($hash->{helper}{SOUNDPROGRAMS}) ? "setSoundProgramList:".$soundprograms_comma." " : "").	
    "setFmTunerPreset:slider,0,1,20 ". 
	"setDabTunerPreset:slider,0,1,20 ".
	"setNetRadioPreset ".
    "TurnFavNetRadioChannelOn:1,2,3,4,5,6,7,8 ".
	"TurnFavServerChannelOn:noArg ".
	"navigateListMenu ".
	"NetRadioNextFavChannel:noArg ".
	"NetRadioPrevFavChannel:noArg ".
	"sleep:uzsuSelectRadio,0,30,60,90,120 ".
    "getNetworkStatus:noArg ". 
	"getLocationInfo:noArg ".
	"getDistributionInfo:noArg ".
	"getBluetoothInfo:noArg ".
    "enableBluetooth:true,false ".
	"setGroupName ".
	"mcLinkTo ".
	"speakfile ".
	"mcUnLink ".	
	"setServerInfo ".
	"setClientInfo ".
	"startDistribution ".
	"isNewFirmwareAvailable:noArg ".
    "statusRequest:noArg ";

  # delay in Seks for next request after turning on device	   	 
  my $powerCmdDelay = AttrVal($hash->{NAME}, "powerCmdDelay",3);
    
  if(lc($cmd) eq "on")
    {        
        Log3 $name, 4, "$name : YAMAHA_MC_Set power on";
		YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options    => {at_first => 1, priority => 1, wait_after_response => $powerCmdDelay}}); # call fn that will do the http request
		
		# setting volume to standard
		my $standardVolume = AttrVal($hash->{NAME}, "standard_volume",15);
		my $currentVolume = ReadingsVal($name, "volume", 0); 
		if($currentVolume != $standardVolume){
		  Log3 $name, 4, "$name : YAMAHA_MC_Set volume not standard $currentVolume setting to standard $standardVolume first ";
		  YAMAHA_MC_httpRequestQueue($hash, "volume",   YAMAHA_MC_volume_rel2abs($hash,$standardVolume), {options    => {unless_in_queue => 1, can_fail => 1,priority => 2, volume_target => $standardVolume}}); # call fn that will do the http request		
		}
		
		# start the status update timer in one second to get new values 
        # already done in ParseResponse		
        #YAMAHA_MC_ResetTimer($hash,1);	
    }
  elsif(lc($cmd) eq "off")
    {
        Log3 $name, 4, "$name : YAMAHA_MC_Set power off=standby";
		YAMAHA_MC_httpRequestQueue($hash, "power", "standby",{options    => { unless_in_queue => 1, wait_after_response => $powerCmdDelay}}); # call fn that will do the http request
		#YAMAHA_MC_ResetTimer($hash);
    }
  elsif(lc($cmd) eq "toggle")
    {
        Log3 $name, 4, "$name : YAMAHA_MC_Set power toggle";
		if (ReadingsVal($name, "power", "off") eq "off"){
		  YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options    => {at_first => 1, priority => 1, wait_after_response => $powerCmdDelay}}); # call fn that will do the http request
		  }
		else{
		  YAMAHA_MC_httpRequestQueue($hash, "power", "off"); # call fn that will do the http request
		  }
    } 
  elsif($cmd eq "power")  {
	 if (lc($a[2]) eq "on") {
        Log3 $name, 4, "$name : YAMAHA_MC_Set power2 on";
		YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options    => {at_first => 1, priority => 1, wait_after_response => $powerCmdDelay}}); # call fn that will do the http request
		#YAMAHA_MC_ResetTimer($hash);
		}
	 elsif((lc($a[2]) eq "off") || ( lc($a[2]) eq "standby")){
        Log3 $name, 4, "$name : YAMAHA_MC_Set power2 off";
		YAMAHA_MC_httpRequestQueue($hash, "power", "standby", {options    => { unless_in_queue => 1, wait_after_response => $powerCmdDelay}}); # call fn that will do the http request
		#YAMAHA_MC_ResetTimer($hash);
		}
    else {
      return "invalid parameter $a[2] for set power";
	  }       
    }
  elsif($cmd eq "input")  {
    if(defined($a[2]))
        {
		 if(not $inputs_piped eq "")
            {
                if($a[2] =~ /^($inputs_piped)$/)
				{
					Log3 $name, 4, "$name : YAMAHA_MC_Set prepareInputChange to $a[2]";
					YAMAHA_MC_httpRequestQueue($hash, "prepareInputChange", $a[2],{options    => {at_first => 1, priority => 1}}); # call fn that will do the http request		
					
					Log3 $name, 4, "$name : YAMAHA_MC_Set input to $a[2]";
					
					my $autoplayDisabled = AttrVal($hash->{NAME}, "autoplay_Disabled","false");
					if(defined($a[3])) {
					  $autoplayDisabled = $a[3];
					}
					
					
					if ($autoplayDisabled eq "false"){
					  YAMAHA_MC_httpRequestQueue($hash, "input", $a[2],{options    => {at_first => 1, priority => 2}}); # call fn that will do the http request		
					 }
					 else {
					   YAMAHA_MC_httpRequestQueue($hash, "input", $a[2] . " mode=autoplay_disabled",{options    => {at_first => 1, priority => 2}}); # call fn that will do the http request		
					 }
				}
				else
                {
				    Log3 $name, 4, "$name : YAMAHA_MC_Set InputChange to $a[2] not possible not in input list ".$inputs_piped;
                    return $usage;
                }
            }
            else
            {
                return "No inputs are avaible. Please try an statusUpdate.";
            }
		}
    	else{
	      return "No input stated to select. Please choose one of " . $inputs_comma;
		}
    }
  elsif($cmd eq "mute")  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set mute to $a[2]";
	if((defined($a[2])) && ((lc($a[2]) eq  "true") || (lc($a[2]) eq  "false"))) {
	  YAMAHA_MC_httpRequestQueue($hash, "mute", lc($a[2])); # call fn that will do the http request		
	 }
	elsif ((defined($a[2])) && (lc($a[2]) eq  "toggle") )
    {
        Log3 $name, 4, "$name : YAMAHA_MC_Set mute toggle";
		if (ReadingsVal($name, "mute", "false") eq "false"){
		  YAMAHA_MC_httpRequestQueue($hash, "mute", "true",{options    => {can_fail => 1}}); # call fn that will do the http request		
		  }
		else{
		  YAMAHA_MC_httpRequestQueue($hash, "mute", "false",{options    => {can_fail => 1}}); # call fn that will do the http request		
		  }
	}	  
    else {
	  return "invalid parameter $a[2] for set mute";	
	}	 
    }
  elsif($cmd eq "setSpeakerA")  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set setSpeakerA to $a[2]";
	if((defined($a[2])) && ((lc($a[2]) eq  "true") || (lc($a[2]) eq  "false"))) {
	  YAMAHA_MC_httpRequestQueue($hash, "setSpeakerA", lc($a[2])); # call fn that will do the http request		
	 }
	elsif ((defined($a[2])) && (lc($a[2]) eq  "toggle") )
    {
        Log3 $name, 4, "$name : YAMAHA_MC_Set setSpeakerA toggle";
		if (ReadingsVal($name, "speaker_a", "false") eq "false"){
		  YAMAHA_MC_httpRequestQueue($hash, "setSpeakerA", "true",{options    => {can_fail => 1}}); # call fn that will do the http request		
		  }
		else{
		  YAMAHA_MC_httpRequestQueue($hash, "setSpeakerA", "false",{options    => {can_fail => 1}}); # call fn that will do the http request		
		  }
	}	  
    else {
	  return "invalid parameter $a[2] for set setSpeakerA";	
	}	 
    }	
  elsif($cmd eq "setSpeakerB")  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set setSpeakerB to $a[2]";
	if((defined($a[2])) && ((lc($a[2]) eq  "true") || (lc($a[2]) eq  "false"))) {
	  YAMAHA_MC_httpRequestQueue($hash, "setSpeakerB", lc($a[2])); # call fn that will do the http request		
	 }
	elsif ((defined($a[2])) && (lc($a[2]) eq  "toggle") )
    {
        Log3 $name, 4, "$name : YAMAHA_MC_Set setSpeakerB toggle";
		if (ReadingsVal($name, "speaker_b", "false") eq "false"){
		  YAMAHA_MC_httpRequestQueue($hash, "setSpeakerB", "true",{options    => {can_fail => 1}}); # call fn that will do the http request		
		  }
		else{
		  YAMAHA_MC_httpRequestQueue($hash, "setSpeakerB", "false",{options    => {can_fail => 1}}); # call fn that will do the http request		
		  }
	}	  
    else {
	  return "invalid parameter $a[2] for set setSpeakerB";	
	}	 
    }		
  elsif($cmd  =~ /^(setToneBass|setToneMid|setToneHigh)$/)  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set setToneBass|setToneTreble to $a[2]";
	if(defined($a[2])) {
	  YAMAHA_MC_httpRequestQueue($hash, $cmd, ($a[2])); # call fn that will do the http request		
	 }	
    else {
	  return "invalid parameter $a[2] for set mute";	
	}	 
    }
  elsif($cmd eq "setSoundProgramList")  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set setSoundProgramList to $a[2]";
	if(defined($a[2])) {
	  YAMAHA_MC_httpRequestQueue($hash, $cmd, ($a[2])); # call fn that will do the http request		
	 }	
    else {
	  return "invalid parameter $a[2] for set setSoundProgramList";	
	}	 
    }	
 elsif($cmd  =~ /^(setFmTunerPreset|setDabTunerPreset|setNetRadioPreset)$/)  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set TunerPreset to $a[2]";
	if(defined($a[2])) {
	  YAMAHA_MC_httpRequestQueue($hash, $cmd, ($a[2])); # call fn that will do the http request		
	 }	
    else {
	  return "invalid parameter $a[2] for set setFmTunerPreset / setDabTunerPreset / setNetRadioPreset";
	}	 
    }	  
   elsif($cmd eq "enableBluetooth")  {
    Log3 $name, 4, "$name : YAMAHA_MC_Set enableBluetooth to $a[2]";
	if((defined($a[2])) && ((lc($a[2]) eq  "true") || (lc($a[2]) eq  "false"))) {
	  YAMAHA_MC_httpRequestQueue($hash, "enableBluetooth", lc($a[2])); # call fn that will do the http request		
	 }
    else {
	  return "invalid parameter $a[2] for set enableBluetooth";	
	}	 
    }	
  elsif($cmd eq "sleep")  {
    
	if((defined($a[2])) && (($a[2]) eq "30") || (($a[2]) eq "60") || (($a[2]) eq "90") || (($a[2]) eq "120") || (($a[2]) eq "0") ) {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set sleep to $a[2]";
	  YAMAHA_MC_httpRequestQueue($hash, "sleep", $a[2]); # call fn that will do the http request		
	 }
    else {
	  return "invalid parameter $a[2] for set sleep";	
	}	 
    }	
  elsif($cmd eq "playback")  {
    
	if((defined($a[2])) && (lc($a[2]) eq "play") || (lc($a[2]) eq "stop") || (lc($a[2]) eq "pause") || (lc($a[2]) eq "previous") || (lc($a[2]) eq "next")
        || (lc($a[2]) eq "fast_reverse_start") || (lc($a[2]) eq "fast_reverse_end") || (lc($a[2]) eq "fast_forward_start") || (lc($a[2]) eq "fast_forward_end")) {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set playback to $a[2]";
	  YAMAHA_MC_httpRequestQueue($hash, "playback", lc($a[2]),{options => {can_fail => 1}}); # call fn that will do the http request		
	 }
    else {
	  return "invalid parameter $a[2] for set playback";	
	}	 
    }	
  elsif($cmd eq "selectMenuItem")  {
    if(defined($a[2]))
    {
    Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem to $a[2]";
	
	if(defined($hash->{helper}{MENUITEMS}) and length($hash->{helper}{MENUITEMS}) > 0){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem Suche $a[2] in " . $menuitems_piped;
	  my $indexMEnuItem = 0;
	  my @allcurrentMenuItems = split( /\|/ , $menuitems_piped);
	  
	  #Log3 $name, 5, "YAMAHA_MC_Set selectMenuItem menuitem1 = ".@allcurrentMenuItems[0]; 
	  #Log3 $name, 5, "YAMAHA_MC_Set selectMenuItem menuitem2 = ".@allcurrentMenuItems[1]; 
	 
	 
      foreach my $currentMenuItems (@allcurrentMenuItems) 
#      foreach my $reading (sort keys %{$hash->{READINGS}})
	  { 
	    Log3 $name, 4, "YAMAHA_MC_Set selectMenuItem Versuch Nr $indexMEnuItem Name $currentMenuItems";
	    if (lc(YAMAHA_MC_Param2Fhem($currentMenuItems,0)) eq lc($a[2])){
		  Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem Bei Index Nr $indexMEnuItem gefunden";
		  last;
		}
		else {
		 Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem nicht gefunden ".lc($a[2])." ist ungleich ".lc(YAMAHA_MC_Param2Fhem($currentMenuItems,0));
		 $indexMEnuItem++;
		 Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem Bei Index nicht gefunden, suche jetzt bei nächsten Index  $indexMEnuItem";
		} 
	  }
	  
	  
	  # Select on Index of menu	  
	  Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem starte Request selectMenu mit Index  $indexMEnuItem";
	  YAMAHA_MC_httpRequestQueue($hash, "selectMenu", $indexMEnuItem,{options => {can_fail => 1, priority => 2}});
	  # getting new menu information in parsing reponse
	}	
    else {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set selectMenuItem helper MENUITEMS not defined ";
	} 	
    }
	else{
	  return "missing parameter for set selectMenuItem";	
	}
    }	
    elsif($cmd eq "selectPlayMenuItem")  {
    if(defined($a[2]))
    {
		Log3 $name, 4, "YAMAHA_MC_Set selectPlayMenuItem to $a[2]";
		
		if(defined($hash->{helper}{MENUITEMS}) and length($hash->{helper}{MENUITEMS}) > 0){
		  Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem Suche $a[2] in " . $menuitems_piped;
		  my $indexMEnuItem = 0;
		  my @allcurrentMenuItems = split( /\|/ , $menuitems_piped);
		  
		  #Log3 $name, 5, "YAMAHA_MC_Set selectPlayMenuItem menuitem1 = ".@allcurrentMenuItems[0]; 
		  #Log3 $name, 5, "YAMAHA_MC_Set selectPlayMenuItem menuitem2 = ".@allcurrentMenuItems[1]; 
		 
		 
		  foreach my $currentMenuItems (@allcurrentMenuItems) 	
		  { 
			Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem Versuch Nr $indexMEnuItem Name $currentMenuItems";
			if (lc(YAMAHA_MC_Param2Fhem($currentMenuItems,0)) eq lc($a[2])){
			  Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem Bei Index Nr $indexMEnuItem gefunden";
			  last;
			}
			else {
			 Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem nicht gefunden ".lc($a[2])." ist ungleich ".lc(YAMAHA_MC_Param2Fhem($currentMenuItems,0));
			 $indexMEnuItem++;
			 Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem Bei Index nicht gefunden, suche jetzt bei nächsten Index  $indexMEnuItem";
			} 
		  }
		  		  
		  # Select on Index of menu
		  Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem starte Request selectMenu mit Index  $indexMEnuItem";
		  YAMAHA_MC_httpRequestQueue($hash, "selectPlayMenu", $indexMEnuItem,{options => {can_fail => 1, priority => 2}});
		  # get new play info
		  YAMAHA_MC_getPlaybackStatus($hash);
		}			
		else {
		  Log3 $name, 4, "$name : YAMAHA_MC_Set selectPlayMenuItem helper MENUITEMS not defined ";
		} 		
    }
	else{
	  return "missing parameter for set selectPlayMenuItem";	
	}
    }	
  elsif($cmd =~ /^(volume|volumeStraight|volumeUp|volumeDown)$/) {
    Log3 $name, 4, "YAMAHA_MC_Set cmd=$cmd setting new volume ";
	my $targetVolume = 0;
	my $targetVolumeRel = 0;
	
	#check mute status, turn off if enabled
	my $currentMute = ReadingsVal($name, "mute", "true"); 	
	if ($currentMute eq "true"){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set in volume but mute not false $currentMute setting to false ";
	  YAMAHA_MC_httpRequestQueue($hash, "mute", "false", {options    => {unless_in_queue => 1, can_fail => 1}}); 
	}  
	
	if (($cmd eq "volume") &&  (defined($a[2])) and ($a[2] =~ /^\d{1,3}$/) and ($a[2] >= 0 &&  $a[2] <= 100)) {	  	  
	  $targetVolume = YAMAHA_MC_volume_rel2abs($hash,$a[2]);
	  $targetVolumeRel = $a[2];
	  Log3 $name, 4, "$name : YAMAHA_MC_Set in volume converting volume von ".$a[2]." to $targetVolume";
	  }
	elsif (($cmd eq "volumeStraight") && (defined($a[2])) && ($a[2] =~ /^-?\d+(?:\.\d)?$/ )) {
	  $targetVolume = $a[2];	
      $targetVolumeRel = YAMAHA_MC_volume_abs2rel($hash,$a[2]);	  
	  }  
	elsif ($cmd eq "volumeUp") {
	  # raise volume regarding to the Steps in attr VolumeSteps
	  my $standardVolume = AttrVal($hash->{NAME}, "standard_volume",15);
	  $targetVolume = ReadingsVal($name, "volume", $standardVolume) + AttrVal($hash->{NAME}, "VolumeSteps",3);
	  $targetVolumeRel = $targetVolume; 
	  $targetVolume = YAMAHA_MC_volume_rel2abs($hash,$targetVolume);
	  Log3 $name, 4, "$name : YAMAHA_MC_Set in volumeup setting new volume to abs $targetVolume rel $targetVolumeRel ";
	  }
	elsif ($cmd eq "volumeDown") {
	  # lower volume regarding to the Steps in attr VolumeSteps
	  my $standardVolume = AttrVal($hash->{NAME}, "standard_volume",15);
	  $targetVolume = ReadingsVal($name, "volume", $standardVolume) - AttrVal($hash->{NAME}, "VolumeSteps",3);  
	  $targetVolumeRel = $targetVolume; 
	  $targetVolume = YAMAHA_MC_volume_rel2abs($hash,$targetVolume);
	  }
	else {
	  return "wrong syntac for set volume";	
	}  
	 
	Log3 $name, 4, "$name : YAMAHA_MC_Set cmd=$cmd volume to new volume $targetVolume"; 
	if(defined($targetVolume)) {
	  YAMAHA_MC_httpRequestQueue($hash, "volume", $targetVolume, {options => {volume_target => $targetVolumeRel}}); # call fn that will do the http request		
	}  
    }	
	elsif($cmd eq "returnMenu") {
	  YAMAHA_MC_httpRequestQueue($hash, "returnMenu", "",{options => {can_fail => 1, priority => 2}});
	  # getting new menu info in parsing response
	 }
   elsif($cmd eq "navigateListMenu") {
        Log3 $name, 4, "$name : YAMAHA_MC_Set start handling for navigateListMenu, starte getMenu"; 		
		YAMAHA_MC_httpRequestQueue($hash, "getMenu", "",{options => {can_fail => 1, init => 1, not_before => gettimeofday()+1}}); # call fn that will do the http request	  
	}	
  elsif($cmd eq "TurnFavNetRadioChannelOn") {
    Log3 $name, 4, "$name : YAMAHA_MC_Set start handling for TurnFavNetRadioChannelOn"; 
	
	my $FavoriteNetRadioChannelParam = AttrVal($hash->{NAME}, "FavoriteNetRadioChannel",1);
	
	# no Args allowed here
    if (defined($a[2])) 
    {
	  $FavoriteNetRadioChannelParam = $a[2];
	}  
	
	# check if device is on and current input is net_radio
	my $currentInput = ReadingsVal($name, "input", "unknown"); 
	my $currentPower = ReadingsVal($name, "power", "off"); 
	my $currentVolume = ReadingsVal($name, "volume", 0); 
	my $currentMute = ReadingsVal($name, "mute", "true"); 
	my $standardVolume = AttrVal($hash->{NAME}, "standard_volume",15);
	
	
	if (!defined($hash->{PowerOnInProgress})) {
	 $hash->{PowerOnInProgress}=0;
	}
	
	if (!defined($hash->{FavoriteNetRadioChannelInProgress})) {
	 $hash->{FavoriteNetRadioChannelInProgress}=0;
	}
	
	#if (!defined($hash->{attemptsToReturnMenu}))  {
	#  Log3 $name, 4, "$name : TurnFavNetRadioChannelOn start setting attempts to return menu to 0 ";
	#  $hash->{attemptsToReturnMenu}=0;      
    #}	  
	
	# turn on device and restart - wait some seconds to continue
	if ($currentPower ne "on")   {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set device not turned on, is set to $currentPower, power on first ";
	  if($hash->{PowerOnInProgress}==0) {
	    Log3 $name, 4, "$name : YAMAHA_MC_Set device not turned on, power on not in progress, turn on now ";
	    $hash->{PowerOnInProgress}=1; 
		$hash->{FavoriteNetRadioChannelInProgress}=1;
	    YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options    => {unless_in_queue => 1, at_first => 1, priority => 1, wait_after_response => $powerCmdDelay, original_cmd => "TurnFavNetRadioChannelOn", original_arg => $FavoriteNetRadioChannelParam, original_priority => 1 }}); # call fn that will do the http request
	    return undef;
	  }
      else {
        Log3 $name, 4, "$name : YAMAHA_MC_Set device not turned on, but power on already in progress, continueing ... ";
      }	  
	}
	
	# setting correct input and restart 
	if ( (!defined($currentInput)) || ($currentInput ne "net_radio")) {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set current input is set $currentInput and not to net_radio, setting input first ";
	  YAMAHA_MC_httpRequestQueue($hash, "input", "net_radio", {options    => {unless_in_queue => 1, can_fail => 1, priority => 1, original_cmd => "TurnFavNetRadioChannelOn", original_arg => $FavoriteNetRadioChannelParam, original_priority => 1}}); # call fn that will do the http request
	  $hash->{FavoriteNetRadioChannelInProgress}=1;
	  return undef;
	}
	
	$hash->{FavoriteNetRadioChannelInProgress}=0;
	
	# setting volume to standard
	if($currentVolume != $standardVolume){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set volume not standard $currentVolume setting to standard $standardVolume first ";
	  YAMAHA_MC_httpRequestQueue($hash, "volume",   YAMAHA_MC_volume_rel2abs($hash,$standardVolume), {options    => {unless_in_queue => 1, can_fail => 1,priority => 2, volume_target => $standardVolume}}); # call fn that will do the http request		
	}
	
	# turn muting off
	if ($currentMute eq "true"){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set mute not false $currentMute setting to false ";
	  YAMAHA_MC_httpRequestQueue($hash, "mute", "false", {options    => {unless_in_queue => 1, can_fail => 1}}); 
	}    
	
	my $alreadyInCorrectMenu = 0;
	my $powerCmdDelay = AttrVal($hash->{NAME}, "powerCmdDelay",3);
	my $menuLayerDelay = AttrVal($hash->{NAME}, "menuLayerDelay",0.5); 
	
	$hash->{FavoriteNetRadioChannelInProgress}=0;
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavNetRadioChannelOn Current Input set to  $currentInput";
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavNetRadioChannelOn  Favourite Channel $FavoriteNetRadioChannelParam";	
    			
	# playing Favourite channel now
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavNetRadioChannelOn now playing channel $FavoriteNetRadioChannelParam via setNetRadioPreset";	
	YAMAHA_MC_httpRequestQueue($hash, "setNetRadioPreset", $FavoriteNetRadioChannelParam,{options => {unless_in_queue => 1, priority => 2, can_fail => 1}}); # call fn that will do the http request
		
	# setting current Channel
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavNetRadioChannelOn now setting current Channel to $FavoriteNetRadioChannelParam";
	readingsSingleUpdate($hash, 'currentFavNetRadioChannel', $FavoriteNetRadioChannelParam,1 );
	

  }  
  elsif($cmd eq "TurnFavServerChannelOn") {
	Log3 $name, 4, "$name : YAMAHA_MC_Set start handling for TurnFavServerChannelOn"; 
	
	# no Args allowed here
	if (defined($a[2])) 
	{
	  return "TurnFavServerChannelOn has no parameters";	
	}  
	
	# check if device is on and current input is server
	my $currentInput = ReadingsVal($name, "input", "unknown"); 
	my $currentPower = ReadingsVal($name, "power", "off"); 
	my $currentVolume = ReadingsVal($name, "volume", 0); 
	my $currentMute = ReadingsVal($name, "mute", "true"); 
	my $standardVolume = AttrVal($hash->{NAME}, "standard_volume",15);
	
	if (!defined($hash->{attemptsToReturnMenu}))  {
	  Log3 $name, 4, "$name : TurnFavServerChannelOn start setting attempts to return menu to 0 ";
	  $hash->{attemptsToReturnMenu}=0;      
	}	  
	
	if ($currentPower ne "on") {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set device not turned on, power on first ";
	  YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options    => {unless_in_queue => 1, at_first => 1, priority => 1, wait_after_response => $powerCmdDelay, original_cmd => "TurnFavServerChannelOn", original_priority => 1}}); # call fn that will do the http request
	  return undef;
	}
	
	if ( (!defined($currentInput)) || ($currentInput ne "server")) {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set current input is set $currentInput and not to server, setting input first ";
	  YAMAHA_MC_httpRequestQueue($hash, "input", "server", {options    => {unless_in_queue => 1, can_fail => 1, priority => 1, original_cmd => "TurnFavServerChannelOn", original_priority => 1}}); # call fn that will do the http request
	  return undef;
	}
	
	# setting volume to standard
	if($currentVolume != $standardVolume){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set volume not standard $currentVolume setting to standard $standardVolume first ";
	  YAMAHA_MC_httpRequestQueue($hash, "volume",   YAMAHA_MC_volume_rel2abs($hash,$standardVolume), {options    => {unless_in_queue => 1, can_fail => 1,priority => 2, volume_target => $standardVolume}}); # call fn that will do the http request		
	}
	
	# turn muting off
	if ($currentMute eq "true"){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set mute not false $currentMute setting to false ";
	  YAMAHA_MC_httpRequestQueue($hash, "mute", "false", {options    => {unless_in_queue => 1, can_fail => 1}}); 
	}    
	
	my $pathToFavoriteServer = YAMAHA_MC_Param2SpaceList(AttrVal($hash->{NAME}, "pathToFavoriteServer","4 1 0 7 1"),0);
	my $menuNameFavoriteServer = YAMAHA_MC_Param2SpaceList(AttrVal($hash->{NAME}, "menuNameFavoriteServer","My__Favorites"),0);
	my $FavoriteServerChannel = AttrVal($hash->{NAME}, "FavoriteServerChannel",0);
	
	
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn Current Input set to  $currentInput";
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn Menu Path to Favourites $pathToFavoriteServer";
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn menuNameFavoriteServer $menuNameFavoriteServer";
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn  Favourite Channel $FavoriteServerChannel";	
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn Going Back to root menu";
	
		
	# first go back- if not already first menu
	my $currentMenuLayer = ReadingsVal($name, "currentMenuLayer", undef); 
	my $currentMenuName = ReadingsVal($name, "currentMenuName", undef); 
		
	# If Menu Layer Attribute does not exist first getMenu
	if (!defined($currentMenuLayer)){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannel no currentMenuLayer defined calling getMenuItems";
	  YAMAHA_MC_httpRequestQueue($hash, "getMenuItems", "",{options => { can_fail => 1, priority => 2, original_cmd => "TurnFavServerChannelOn", original_priority => 2}}); # call fn that will do the http request	 
	  return undef;
	} 
	else {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannel currentMenuLayer is defined : $currentMenuLayer";
	}
	
	my $alreadyInCorrectMenu = 0;
	my $powerCmdDelay = AttrVal($hash->{NAME}, "powerCmdDelay",3);
	my $menuLayerDelay = AttrVal($hash->{NAME}, "menuLayerDelay",$powerCmdDelay); 
	
	if(($currentMenuLayer==0) && (lc($currentMenuName) eq "server")){
	  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn already in root menu";
	}
	#elsif(($currentMenuLayer==2) && (lc($currentMenuName) eq lc($menuNameFavoriteServer))){
	# Log3 $name, 4, "YAMAHA_MC_Set TurnFavServerChannelOn already in correct menu Layer $currentMenuLayer and menuname $currentMenuName";
	# $alreadyInCorrectMenu = 1;
	#}
	else {
	
		Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn NOT in correct menu Layer $currentMenuLayer and menuname $currentMenuName";
		
		Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn  incrementing attempts to returnmenu; attempt".$hash->{attemptsToReturnMenu};
		$hash->{attemptsToReturnMenu}=$hash->{attemptsToReturnMenu}+1;
		
		if ($hash->{attemptsToReturnMenu}==6) {
		   Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn  more than 5 attempts to returnmenu; try to get Menu again";
		   YAMAHA_MC_httpRequestQueue($hash, "getMenuItems", "",{options => { can_fail => 1, priority => 1, original_cmd => "TurnFavServerChannelOn", original_priority => 1}}); # call fn that will do the http request	
		   return undef;		   
		}
		elsif($hash->{attemptsToReturnMenu}>9) {
		   Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn  more thn 9 attempts to returnmenu; giving up";
		   YAMAHA_MC_httpRequestQueue($hash, "getMenuItems", "",{options => { can_fail => 1, priority => 1, original_cmd => ""}}); # call fn that will do the http request	
		   $hash->{attemptsToReturnMenu}=0;
		}
		else {
		  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn not in root menu Layer $currentMenuLayer and menuname $currentMenuName";
		  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn  next attempts to returnmenu started";
		  YAMAHA_MC_httpRequestQueue($hash, "returnMenu", "",{ options    => {unless_in_queue => 1, priority => 2, can_fail => 1,  original_cmd => "TurnFavServerChannelOn", original_priority => 2}}); # call fn that will do the http request
		  return undef;	
		}
		
	}
	
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn  resetting attempts to 0";
	$hash->{attemptsToReturnMenu}=0;
	
	# now in root menu
	# navigate through Favourite Path if we are not already there
	if($alreadyInCorrectMenu == 0) 
	{
		Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn now Back to root menu, going through menu structure now";
		Log3 $name, 4, "$name : YAMAHA_MC_Set $cmd now Back to root menu, Menu Layer = $currentMenuLayer Menu Name=" . $currentMenuName;
					
		# going through menu path to Favourite			
		
		for my $favStartmenu ( split /\s+/, $pathToFavoriteServer ){    
		  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn now navigating to menu $favStartmenu";
		  YAMAHA_MC_httpRequestQueue($hash, "selectMenu", $favStartmenu,{options    => {priority => 2, can_fail => 1, not_before => gettimeofday()+$menuLayerDelay}}); # call fn that will do the http request
		  $menuLayerDelay = $menuLayerDelay + 0.5;
		  Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn menu $favStartmenu waiting one second";	  
		  #YAMAHA_MC_httpRequestQueue($hash, "getMenuItems", "",{options => {can_fail => 1, not_before => gettimeofday()+7}}); # call fn that will do the http request	  
		}
	}
	
	# playing Favourite channel now
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn now playing channel $FavoriteServerChannel";
	YAMAHA_MC_httpRequestQueue($hash, "selectPlayMenu", $FavoriteServerChannel,{options => {priority => 2, can_fail => 1, not_before => gettimeofday()+$menuLayerDelay+0.5, init_fav_menuname => 1}}); # call fn that will do the http request
		
	# setting current Channel
	Log3 $name, 4, "$name : YAMAHA_MC_Set TurnFavServerChannelOn now setting current Channel to $FavoriteServerChannel";
	readingsSingleUpdate($hash, 'currentFavNetRadioChannel', $FavoriteServerChannel,1 );

  }  
  elsif($cmd =~ /^(NetRadioNextFavChannel|NetRadioPrevFavChannel)$/) {
    
	 if (defined($a[2])) 
    {
	  return "NetRadioNextFavChannel has no parameters";	
	}  
	
    if ((defined($hash->{settingChannelInProgress})) && ($hash->{settingChannelInProgress}==1)) {
	  Log3 $name, 4, "$name : Setting Channel in progress Value=".$hash->{settingChannelInProgress}." returning ... ";
      return undef;
    }	  
	
	# check if device is on and current input is net_radio
	my $currentInput = ReadingsVal($name, "input", "unknown"); 
	my $currentPower = ReadingsVal($name, "power", "off"); 
	my $currentVolume = ReadingsVal($name, "volume", 0); 
	my $currentMute = ReadingsVal($name, "mute", "true"); 
	
	if ($currentPower ne "on") {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel device not turned on, power on first ";
	  YAMAHA_MC_httpRequestQueue($hash, "power", "on", {options => {unless_in_queue => 1, at_first => 1, priority => 1, wait_after_response => $powerCmdDelay, original_cmd => $cmd, original_priority => 1}}); # call fn that will do the http request
	  return undef;
	}
	
	if ( (!defined($currentInput)) || ($currentInput ne "net_radio")) {
	  Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel input not set to net_radio, setting input first ";
	  YAMAHA_MC_httpRequestQueue($hash, "input", "net_radio", {options    => {unless_in_queue => 1, can_fail => 1, at_first => 1, priority => 1, original_cmd => $cmd, original_priority => 1}}); # call fn that will do the http request
	  return undef;
	}
	    
	#my $pathToFavoritesNetRadio = YAMAHA_MC_Param2SpaceList(AttrVal($hash->{NAME}, "pathToFavoritesNetRadio","0 0 "),0);
	#my $menuNameFavoritesNetRadio = YAMAHA_MC_Param2SpaceList(AttrVal($hash->{NAME}, "menuNameFavoritesNetRadio","Best Radio"),0);
	my $FavoriteNetRadioChannel = AttrVal($hash->{NAME}, "FavoriteNetRadioChannel",1);
	my $currentFavNetRadioChannel = ReadingsVal($name, "currentFavNetRadioChannel", $FavoriteNetRadioChannel);
	
	# first go back- if not already first menu
	my $currentMenuLayer = ReadingsVal($name, "currentMenuLayer", undef); 
	my $currentMenuName = ReadingsVal($name, "currentMenuName", undef); 
	#my $currentMenumaxItems = ReadingsVal($name, "currentMenumaxItems", 8); 
	my $currentMenumaxItems = 8;
	my $menuLayerDelay = 0.5;
	my $alreadyInCorrectMenu = 0;
	
	Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel Current Input set to  $currentInput";
	#Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel Menu Path to Favourites $pathToFavoritesNetRadio";
	#Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel menuNameFavoritesNetRadio $menuNameFavoritesNetRadio";
	Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel  Favourite Channel $FavoriteNetRadioChannel";	
	Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel  currentFavNetRadioChannel $currentFavNetRadioChannel";	
	#Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel Going Back to root menu";
	
	
	# playing Favourite channel now	
	# setting current Channel
	my $newTargetChannel = 0;
	if($cmd eq "NetRadioNextFavChannel"){
	  $newTargetChannel = $currentFavNetRadioChannel + 1;
	  
	 }
    elsif($cmd eq "NetRadioPrevFavChannel"){
	  $newTargetChannel = $currentFavNetRadioChannel - 1;
	 }	 
	
	if (($newTargetChannel==0) && ($cmd eq "NetRadioPrevFavChannel")){
	  $newTargetChannel = $currentMenumaxItems;	
	}
	elsif(($newTargetChannel==0) && ($cmd eq "NetRadioNextFavChannel")){
	  $newTargetChannel = 1;	
	}
	
	if($newTargetChannel>($currentMenumaxItems)){
	  $newTargetChannel = 1;
	}
	
	# remember that setting channel is in progress
	# will be reset in parse request of playChannel
	#$hash->{settingChannelInProgress} = 1;
	
	
	Log3 $name, 4, "$name : YAMAHA_MC_Set NetRadioNextFavChannel now setting current Channel to $newTargetChannel";
	
	
	# playing channel now
	Log3 $name, 4, "$name : YAMAHA_MC_Set $cmd now playing channel $newTargetChannel";	
	
	YAMAHA_MC_httpRequestQueue($hash, "setNetRadioPreset", $newTargetChannel,{options => {priority => 2, can_fail => 1, original_cmd => "" }}); # call fn that will do the http request
	
	# setting current Channel
	Log3 $name, 4, "$name : YAMAHA_MC_Set $cmd now setting current Channel $newTargetChannel";
	readingsSingleUpdate($hash, 'currentFavNetRadioChannel', $newTargetChannel, 1);
	
	Log3 $name, 4, "YAMAHA_MC_Set $cmd setting current Channel done"
	}
  elsif($cmd eq "statusRequest") {
	    Log3 $name, 4, "$name : YAMAHA_MC_Set statusRequest calling YAMAHA_MC_GetStatus ";
		YAMAHA_MC_GetStatus($hash, 1);
		# das gibt zuviele anfragen, vielleicht mal so probieren :
		#YAMAHA_MC_GetStatus($hash);
    }  
  # valid "set cmds" are defind in %cmd_hash (see above)	
  elsif($cmd =~ /^(prepareInputChange|getStatus|getFeatures|getFuncStatus|getPlayInfo|getDeviceInfo|sleep|getNetworkStatus|getLocationInfo|getDistributionInfo|getSoundProgramList)$/) {  
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set known cmd in List starting request for $cmd now, not allowed to fail";
    YAMAHA_MC_httpRequestQueue($hash, $cmd, ""); # call fn that will do the http request
  }    
  elsif($cmd =~ /^(setAutoPowerStandby|selectMenu|selectPlayMenu|playback|getMenu|getMenuItems|getBluetoothInfo|enableBluetooth)$/) {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set known cmd in List starting request for $cmd now, allowed to fail";
    YAMAHA_MC_httpRequestQueue($hash, $cmd, "",{options => {can_fail => 1}}); # call fn that will do the http request
  }
  elsif($cmd eq "setGroupName") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set setGroupName now, direct execution not using queue";    
	YAMAHA_MC_httpRequestQueue($hash, $cmd, "",{options => {can_fail => 1}}); # call fn that will do the http request
	}
  elsif($cmd eq "mcLinkTo") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set mcLinkTo now, direct execution not using queue";    
	YAMAHA_MC_httpRequestQueue($hash, $cmd, $argsOnlyList,{options => {can_fail => 1}}); # call fn that will do the http request		
	}
   elsif($cmd eq "speakfile") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set SpeakFile now,  using queue";    
	YAMAHA_MC_httpRequestQueue($hash, $cmd, $argsOnlyList,{options => {unless_in_queue => 1, priority => 2, can_fail => 1}}); # call fn that will do the http request		
	}
	
  elsif($cmd eq "mcUnLink") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set mcUnLink now, direct execution not using queue";    
	YAMAHA_MC_httpRequestQueue($hash, $cmd, $argsOnlyList,{options => {can_fail => 1}}); # call fn that will do the http request		
	}	  	
  elsif($cmd eq "setServerInfo") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set setServerInfo now, direct execution not using queue";    	   
	YAMAHA_MC_httpRequestQueue($hash, $cmd, "",{options => {can_fail => 1}}); # call fn that will do the http request
	}
  elsif($cmd eq "setClientInfo") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set setClientInfo now, direct execution not using queue";    
	YAMAHA_MC_httpRequestQueue($hash, $cmd, "",{options => {can_fail => 1}}); # call fn that will do the http request			
  }  
  elsif($cmd eq "startDistribution") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set startDistribution now, direct execution not using queue";
    YAMAHA_MC_httpRequestQueue($hash, $cmd, "",{options => {can_fail => 1}}); # call fn that will do the http request			
  }
  elsif($cmd eq "isNewFirmwareAvailable") {
      # known cmd, is in cmd_hash but no particular handling above
	# so execute standard url associated
	Log3 $name, 4, "$name : YAMAHA_MC_Set isNewFirmwareAvailable now, direct execution not using queue";
    YAMAHA_MC_httpRequestQueue($hash, $cmd, "",{options => {can_fail => 1}}); # call fn that will do the http request			
  }  
  else{
    # if $cmd is not valid then return all valid cmds
	Log3 $name, 4, "$name : YAMAHA_MC_Set unknown cmd not in List $cmd returning usage";
    return $usage;
  }
  Log3 $name, 4, "$name : YAMAHA_MC_Set returning now, last cmd=$cmd";  
  
  # according to documentation in 
  # https://wiki.fhem.de/wiki/DevelopmentModuleIntro#Modulfunktionen
  # return undef means successful completion of set command
  return undef;
} #ENDE sub YAMAHA_MC_Set



#############################
#
# YAMAHA_MC_httpRequestQueue
#
# sends a command to the device via HTTP
# this one is for execution with CMD Queue
#
#
# Structure of a request hash
# ===========================
#
#   { 
#      cmd           => name of the command which is related to the request
#      arg           => optional argument related to the command and request
#      original_hash => $hash of the originating definition. must be set, if a zone definition sends a request via the mainzones command queue.
#      options       => optional values, see following list of possibilities.
#   }
#
# following option values can be used to control the execution of the command:
#
#   {
#      unless_in_queue => don't insert the command if an equivalent command already exists in the queue. (flag: 0,1 - default: 0)
#      priority        => integer value of priority. lower values will be executed before higher values in the appropriate order. (integer value - default value: 3)
#      at_first        => insert the command at the beginning of the queue, not at the end. (flag: 0,1 - default: 0)
#      not_before      => don't execute the command before the given Unix timestamp is reached (integer/float value)
#      can_fail        => the request can return an error. If this flag is set, don't treat this as an communication error, ignore it instead. (flag: 0,1 - default: 0)
#      no_playinfo     => (only relevant for "statusRequest basicStatus") - don't retrieve extended playback information, after receiving a successful response (flag: 0,1 - default: 0)
#      init            => (only relevant for navigateListMenu) - marks the initial request to obtain the current menu level (flag: 0,1 - default: 0)
#      last_layer      => (only relevant for navigateListMenu) - the menu layer that was reached within the last request (integer value)
#      item_selected   => (only relevant for navigateListMenu) - is set, when the final item is going to be selected with the current request. (flag: 0,1 - default: 0)
#      volume_target   => (only relevant for volume) - the target volume, that should be reached by smoothing. (float value)
#      volume_diff     => (only relevant for volume) - the volume difference between each step to reach the target volume (float value)
#   }
#
# Syntax Example: #YAMAHA_MC_httpRequestQueue($hash, $what, $a[2], {options => {unless_in_queue => 1, can_fail => 1, at_first => 1, priority => 1,not_before => gettimeofday()+1}});
#
sub YAMAHA_MC_httpRequestQueue($$$;$)
{
    
    my ($hash, $cmd, $arg, $additional_args) = @_;
    my $name = $hash->{NAME};
    my $options;
    
	# data not used in this context, 
	# at the moment just http gets without data to send
    my $data = "";
	
	Log3 $name, 4, "($name) - YAMAHA_MC_httpRequestQueue start queuing ".$cmd;
    
    # In case any URL changes must be made, this part is separated in this function".    
    my $param = {
                    data       => $data,
                    cmd        => $cmd,
                    arg        => $arg
                };     
    
    map {$param->{$_} = $additional_args->{$_}} keys %{$additional_args};
    
    $options = $additional_args->{options} if(exists($additional_args->{options}));
    
    my $device = $hash;
       
    
	if (defined($arg)) {
	  Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - Args defined as <".$arg.">";
	}
	
	#if (defined($_->{arg})) {
	#  Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - vorhandene Args defined as ".$_->{arg};
	# }
	
	if (defined($cmd)) {
	  Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - cmd defined as <".$cmd.">";
	}
	
	#if (defined($_->{cmd})) {
	#  Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - vorhandene cmd defined as ".$_->{cmd};
	# }
	
	if(@{$hash->{helper}{CMD_QUEUE}}){
     Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - + Es gibt noch pending commands";
	 }
	
	my $alreadyinqueue = 0;
    if ($options->{unless_in_queue}) {
	if(($options->{unless_in_queue} and defined($arg) and grep( ($_->{cmd} eq $cmd and ( (not(defined($arg) or defined($_->{arg}))) )) ,@{$device->{helper}{CMD_QUEUE}}))
	  or ($options->{unless_in_queue} and !defined($arg) and grep( ($_->{cmd} eq $cmd and !defined($_->{arg})) ,@{$device->{helper}{CMD_QUEUE}}))
	  or ($options->{unless_in_queue} and defined($arg) and grep( ($_->{cmd} eq $cmd and defined($_->{arg}) and $_->{arg} eq $arg) ,@{$device->{helper}{CMD_QUEUE}}))
	  )
	    {
		my $alreadyinqueue = 1;
        Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - comand \"$cmd".(defined($arg) ? " ".$arg : "")."\" is already in queue, skip adding another one";
        }
	}
    
	if ($alreadyinqueue==0)
    {
        Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - append to queue ".($options->{at_first} ? "(at first) ":"")."of device ".$device->{NAME}." \"$cmd".(defined($arg) ? " ".$arg : "")."\": $data";
        
        if($options->{at_first})
        {
            Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - append to queue at first of device ".$device->{NAME}." \"$cmd".(defined($arg) ? " ".$arg : "")."\": $data";
			unshift @{$device->{helper}{CMD_QUEUE}}, $param;  
        }
        else
        {
		    Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - append to queue at end of device ".$device->{NAME}." \"$cmd".(defined($arg) ? " ".$arg : "")."\": $data";
            push @{$device->{helper}{CMD_QUEUE}}, $param;  
        }
    }
    
	
	if($cmd ne "-1"){
	  Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) -calling YAMAHA_MC_HandleCmdQueue now"; 
      YAMAHA_MC_HandleCmdQueue($device,$cmd,$arg);	  
    }
	else
	{
	  Log3 $name, 4, "YAMAHA_MC_httpRequestQueue ($name) - NOT calling YAMAHA_MC_HandleCmdQueue now because cmd is $cmd"; 
	}
    return undef;
}


#############################
#
# ------------------------------------------------------------------------------
#see: http://www.fhemwiki.de/wiki/HttpUtils
# this one is for execution via CMD Queue
sub YAMAHA_MC_HandleCmdQueue($$$)
{
  my ($hash, $cmd, $plist) = @_;
  my ($name) = $hash->{NAME};
  my ($type) = $hash->{TYPE};  
  #my $plist="";
  
  #if((@params)){
  #  $plist = join(",",@params);
  #}
  
  my $reqCmd ="";
  my $reqArg ="";
  my $reqData ="";
  my $reqOptions ="";  
  
   Log3 $name, 4, "+++++++++++++++++++++++++++++++++++++++++++++++++++++";
   Log3 $name, 4, "+ YAMAHA_MC_HandleCmdQueue ";
   Log3 $name, 4, "+++++++++++++++++++++++++++++++++++++++++++++++++++++";
  #my $host = $hash->{helper}{host};
  if(not($hash->{helper}{RUNNING_REQUEST})){
     Log3 $name, 4, "($name) - + Es laeuft kein Request mehr";
	 }
	 if(@{$hash->{helper}{CMD_QUEUE}}){
     Log3 $name, 4, "($name) - + Es gibt noch pending commands";
	 }
  
  

  if(not($hash->{helper}{RUNNING_REQUEST}) and @{$hash->{helper}{CMD_QUEUE}})
    {
	  
	  Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - HandleCmdQueue no commands currently running, but queue has pending commands. preparing new request";
	  Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - getting new request";
	  my $request = YAMAHA_MC_getNextRequestHash($hash);
	  
	  Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - got new request, try to get params of request";
	  
	 # Init so no Perl Warning ragarding uninitialized value  
	 $reqCmd = "";
	 $reqArg = "";
	 $reqData = "";
	 $reqOptions ="";  
	 $reqCmd = (defined($request->{cmd}) ? $request->{cmd} : "");
	 $reqArg = (defined($request->{arg}) ? $request->{arg} : "");
	 $reqData = (defined($request->{data}) ? $request->{data} : "");
	 $reqOptions = (defined($request->{options}) ? $request->{options} : "");
	 
	 Log3 $name, 4, "$type YAMAHA_MC_HandleCmdQueue: new request has name $name CMD $reqCmd Args $reqArg";
	 
	 if($reqCmd ne "")
	 {
	 # musiccsast Befehle direkt ausführen
	 # alles andere per queue logik
	 if ($reqCmd eq "mcLinkTo"){
	   Log3 $name, 4, "$type YAMAHA_MC_HandleCmdQueue: musiccast cmd direct execution via YAMAHA_MC_Link";
	   YAMAHA_MC_Link($hash,$name,$reqCmd, $reqArg);
	   }	
	 elsif ($reqCmd eq "speakfile"){
	   Log3 $name, 4, "$type YAMAHA_MC_HandleCmdQueue: speakfile cmd direct execution via YAMAHA_MC_SpeakFile";
	   YAMAHA_MC_SpeakFile($hash,$reqArg);
	   }	  
     elsif ($reqCmd eq "mcUnLink"){
	   Log3 $name, 4, "$type YAMAHA_MC_HandleCmdQueue: musiccast cmd direct execution via YAMAHA_MC_UnLink";
	   YAMAHA_MC_UnLink($hash,$name,$reqCmd, $reqArg);
	 }
	 else {
      Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: execution cmd via CmdQueue";
	  my $url ="";
	  
	  if ((defined($hash->{HOST})) && (defined($hash->{PORT})) && (defined($hash->{URLCMD})))
	  {
		  $url = "http://".$hash->{HOST}.":".$hash->{PORT}.$hash->{URLCMD};
		  if( (defined($reqCmd)) && (%YAMAHA_MC_setCmdswithoutArgs)) { 
			if(defined($reqArg)){ 
			# Leerzeichen entfernen
			  #$reqArg =~ s/ //g;
			  #$reqArg =~ s/\s+//g;
			  $url .= $YAMAHA_MC_setCmdswithoutArgs{$reqCmd}.$reqArg;
			}
			else {
			  $url .= $YAMAHA_MC_setCmdswithoutArgs{$reqCmd};
			}
          Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: ALLOWED cmd=$reqCmd starte httpRequest url => $url";			
	     }
		 else {
		   Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: UNALLOWED cmd=$reqCmd starte httpRequest url => $url";
		 }
	  }	 
	  else {
	     # empty request for time keeping sake
	     Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: dummy request";
	  }
	
	 #wenn sich batch_cmd in der URL befindet, dann URL
	 ## umschreiben auf /v1/main/getStatus
	 # ansonsten gibt es einen Responsecode 3
	 # und keine Beachtung des weitergehenden Batch Bearbeitung in YAMAHA_MC
	 if ($url =~ /batch_cmd/) {
	   Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: batch_cmd detected, replacing in url $url ";
	   my ($url2) = split /batch_cmd/, $url, 2;
	   #$url =~ s/batch_cmd/\/v1\/main\/getStatus/g;
	   Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: batch_cmd detected, replaced - new url is $url ";	     
	   $url = $url2 . "/v1/main/getStatus";
	   Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: batch_cmd detected, replaced - new url2 is $url ";	   	   
	 }
	
     # v1/main/setPower?power=on in URL ersetzen durch tatsaechliche Zone	 
     #$url =~ s/\Q$find\E/$replace/g;	 	 
	 #my $url_replace = $url;
	 $url =~ s/main/$hash->{ZONE}/g;
	 $url =~ s/ mode/&mode/g;  
	 

	 
	  #TOE: Anpassungen auf "dotted" API Versionen mit "." 
	 my $shortAPI = $hash->{API_VERSION};
	 $shortAPI=~s/\.[0-9]+//;
     Log3 $name,4," $type ($name) - YAMAHA_MC_HandleCmdQueue: API Version cut to $shortAPI URL before $url";
	 
	 #api version setzen durch korrekte Version des Devices
	 $url =~ s/v1/v$shortAPI/g;
	 
	 Log3 $name, 4, "$type ($name) - YAMAHA_MC_HandleCmdQueue: cmd=$reqCmd starte httpRequest replaced url => $url";			
  
	  my $params =  {
		url         => $url,
		timeout     => AttrVal($name, "request-timeout", 4),
		noshutdown => 1, 
		keepalive => 0,
		httpversion => "1.1",
		loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
		httpversion => "1.0",
		#hideurl     => 0,
		method      => "GET",
		hash        => $hash,
		cmd         => $reqCmd,     #passthrouht to YAMAHA_MC_httpRequestParse
		plist       => $plist,   #passthrouht to YAMAHA_MC_httpRequestParse
		reqOptions   => $reqOptions, #passthrouht to YAMAHA_MC_httpRequestParse
	    callback    =>  \&YAMAHA_MC_httpRequestParse # This fn will be called when finished
	  };
	  
	  #if (($cmd ne "") &&  ($YAMAHA_MC_setCmdswithoutArgs{$cmd} ne "")) {
		

        unless(defined($request))
        {
            # still request in queue, but not mentioned to be executed now
            Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - still requests in queue, but no command shall be executed at the moment. Retry in 1 second.";
            RemoveInternalTimer($hash, "YAMAHA_MC_HandleCmdQueue");
            InternalTimer(gettimeofday()+1,"YAMAHA_MC_HandleCmdQueue", $hash);
            return undef;
        }
        
        $request->{options}{priority} = 4 unless(exists($request->{options}{priority}));
        delete($request->{data}) if(exists($request->{data}) and !$request->{data});
        #$request->{data}=~ s/\[CURRENT_INPUT_TAG\]/$hash->{helper}{CURRENT_INPUT_TAG}/g if(exists($request->{data}) and exists($hash->{helper}{CURRENT_INPUT_TAG}));

        
        map {$hash->{helper}{".HTTP_CONNECTION"}{$_} = $params->{$_}} keys %{$params};
        map {$hash->{helper}{".HTTP_CONNECTION"}{$_} = $request->{$_}} keys %{$request};
       
	   $request->{cmd}="" unless defined($request->{cmd});
	    if($request->{cmd} ne "")
		{
          $hash->{helper}{RUNNING_REQUEST} = 1;
		
          Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - send command via HttpUtils_NonblockingGet \"$request->{cmd}".(defined($request->{arg}) ? " ".$request->{arg} : "")."\"".(exists($request->{data}) ? ": ".$request->{data} : "");
          HttpUtils_NonblockingGet($hash->{helper}{".HTTP_CONNECTION"});
		}
	  else {
		Log3 $name, 4, "$type ($name) -: empty cmd no real request no CMD defined or dummy request, not executing real request";
		Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - dummy request. Retry in 1 second.";
		RemoveInternalTimer($hash, "YAMAHA_MC_HandleCmdQueue");
        InternalTimer(gettimeofday()+1,"YAMAHA_MC_HandleCmdQueue", $hash);
	  }
	}  
	}
	}
	
	
	$hash->{CMDs_pending} = @{$hash->{helper}{CMD_QUEUE}};
	Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_HandleCmdQueue - pending requests ".$hash->{CMDs_pending};	
	
    delete($hash->{CMDs_pending}) unless($hash->{CMDs_pending}); 

  return undef;
}

#############################
# selects the next command from command queue that has to be executed (undef if no command has to be executed now)
sub YAMAHA_MC_getNextRequestHash($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if(@{$hash->{helper}{CMD_QUEUE}})
    {
        my $last = $#{$hash->{helper}{CMD_QUEUE}};
        
        my $next_item;
        my $next_item_prio;
        
        for my $item (0 .. $last)
        {
            my $param = $hash->{helper}{CMD_QUEUE}[$item];
            
            if(defined($param))
            {
                my $cmd = (defined($param->{cmd}) ? $param->{cmd} : "");
                my $arg = (defined($param->{arg}) ? $param->{arg} : "");
                my $data = (defined($param->{data}) ? "1" : "0");
                my $options = $param->{options};
                
				## wenn not before exist, then prio 1 and at first.
                my $opt_not_before = (exists($options->{not_before}) ? sprintf("%.2fs", ($options->{not_before} - gettimeofday())): "0");
				
				if (exists($options->{not_before})) {
				  $options->{priority} = "1";
				  $options->{at_first} = "1";
				} 
                
				my $opt_priority = (exists($options->{priority}) ? $options->{priority} : "-");
                my $opt_at_first = (exists($options->{at_first}) ? $options->{at_first} : "0");
				
                
                Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - checking cmd queue item: $item (cmd: $cmd, arg: $arg, data: $data, priority: $opt_priority, at_first: $opt_at_first, not_before: $opt_not_before)";
            
			    # remove emtpty commands
			    #if ($cmd =="") {
				#  splice(@{$hash->{helper}{CMD_QUEUE}}, $item, 1);
				#  redo;
				#}			
                if(exists($param->{data}))
                {
                    if(defined($next_item) and ((defined($next_item_prio) and exists($options->{priority}) and  $options->{priority} < $next_item_prio) or (defined($options->{priority}) and not defined($next_item_prio))))
                    {
                        # choose actual item if priority of previous selected item is higher or not set
                        $next_item = $item;
                        $next_item_prio = $options->{priority};
                    }
            
                    unless((exists($options->{not_before}) and $options->{not_before} > gettimeofday()) or (defined($next_item)))
                    {
                        $next_item = $item;
                        $next_item_prio = $options->{priority};
                    }
                }
                else # dummy command to delay the execution of further commands in queue 
                {
                    if(exists($options->{not_before}) and $options->{not_before} <= gettimeofday() and not(defined($next_item)))
                    {
                        # if not_before timestamp of dummy item is reached, delete it and continue processing for next command
                        Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - item $item is a dummy cmd item with 'not_before' set which is already expired, delete it and recheck index $item again";
                        splice(@{$hash->{helper}{CMD_QUEUE}}, $item, 1);
                        redo;
                    }
                    elsif(exists($options->{not_before}) and not(defined($next_item) and defined($next_item_prio)))
                    {
                        Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - we have to wait ".sprintf("%.2fs", ($options->{not_before} - gettimeofday()))." seconds before next item can be checked"; 
						RemoveInternalTimer($hash, "YAMAHA_MC_HandleCmdQueue");
                        InternalTimer(gettimeofday()+1,"YAMAHA_MC_HandleCmdQueue", $hash);
						Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - anding queue handle, check in 1 Sek again"; 
						Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - restart timer in 1 Sek and exit handle Queue"; 
                        last;
                    }
                }
            }
        }
        
        if(defined($next_item))
        {
            if(exists($hash->{helper}{CMD_QUEUE}[$next_item]{options}{not_before}))
            {
                delete($hash->{helper}{CMD_QUEUE}[$next_item]{options}{not_before});
            }
        
            my $return = $hash->{helper}{CMD_QUEUE}[$next_item];
            
            splice(@{$hash->{helper}{CMD_QUEUE}}, $next_item, 1);
            $hash->{helper}{CMD_QUEUE} = () unless(defined($hash->{helper}{CMD_QUEUE}));
            
            Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - choosed item $next_item as next command";
            return $return;
        }
        else{
		  Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - no no next_item defined";
		}
        Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - no suitable command item found - returning";
		Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_getNextRequestHash - waiting for next call of YAMAHA_MC_getNextRequestHash ";
        return undef;
    }
}

# ------------------------------------------------------------------------------
#see: http://www.fhemwiki.de/wiki/HttpUtils
sub YAMAHA_MC_httpRequestParse($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  my $cmd = $param->{cmd};
  my $arg = $param->{arg};  
  my $options = $param->{options};
  my $queue_hash = $param->{hash};
  my $reqOptions = $param->{reqOptions};
   
  
  $data = "" unless(defined($data));
  $err = "" unless(defined($err));
  $name = "" unless(defined($name));

  $hash->{helper}{SELECTED_ZONE} = [] unless(defined($hash->{helper}{SELECTED_ZONE}));
  $hash->{helper}{ZONES} = [] unless(defined($hash->{helper}{ZONES}));

  my $power = ReadingsVal($name, "power", "off");
  if(defined(YAMAHA_MC_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES}))){
    my $zone = YAMAHA_MC_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
  }
  
  # if cmd_queue is used delete request und helper  
  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse deleting http helper";
  $hash->{helper}{RUNNING_REQUEST} = 0;
  delete($hash->{helper}{".HTTP_CONNECTION"}) unless($param->{keepalive});
  
  #regardless of error reset state here
  if ($cmd =~ /^(selectPlayMenuItem|selectPlayMenu)$/){
    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse resetting settingChannelInProgress to 0";
    $hash->{settingChannelInProgress}=0;	
  }	
    
  # error handling here
  if (($err ne "")  and not $options->{can_fail}){
    Log3 $name, 2, "$type: $name YAMAHA_MC_httpRequestParse last cmd=$cmd failed with error: $err";
	
	
		
	if (($cmd eq "getDeviceInfo") and   ($err =~ m/empty answer received/sgi)) {
	  Log3 $name, 2, "$type: $name YAMAHA_MC_httpRequestParse seems to be okay when playing via dlna";
	  YAMAHA_MC_HandleCmdQueue($queue_hash,$cmd,$arg);
	  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse end ";
      return undef
	}
	
	# Perhaps device turned off, increasing timeout counter
	$hash->{helper}{TIMEOUT_COUNT} = $hash->{helper}{TIMEOUT_COUNT} + 1;
	Log3 $name, 2, "$type: $name YAMAHA_MC_httpRequestParse error occured increasing timeout counter to ".$hash->{helper}{TIMEOUT_COUNT};
	
	if ($hash->{helper}{TIMEOUT_COUNT} > 10) {
		Log3 $name, 2, "$type: $name YAMAHA_MC_httpRequestParse more than 10 timeouts, guessing device is absent, setting state and power to off";

		#see: http://www.fhemwiki.de/wiki/DevelopmentModuleIntro#Readings
		
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "presence", "absent", 1);
	    readingsBulkUpdate($hash, "state", "off", 1);	
		readingsBulkUpdate($hash, "power", "off",1);		
		readingsEndUpdate($hash, 1);
		
		#delete readings, because unsure if menu still avaliable
		if (defined($hash->{$name}{READINGS}{currentMenuLayer})) {
			delete($hash->{$name}{READINGS}{currentMenuLayer});
		  }
		  if (defined($hash->{$name}{READINGS}{currentMenuName})) {
			delete($hash->{$name}{READINGS}{currentMenuName});
		  } 	
		  if (defined($hash->{READINGS}{currentMenuLayer})) {
			delete($hash->{READINGS}{currentMenuLayer});
		  }	
		  if (defined($hash->{$name}{READINGS}{currentMenuName})) {
			delete($hash->{READINGS}{currentMenuName});
		  }	
	}
    else {
      readingsBeginUpdate($hash);
	  readingsBulkUpdate($hash, "last_error", $err, 1);
	  readingsEndUpdate($hash, 1);
    }	

	if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1))
        {
            Log3 $name, 2, "YAMAHA_MC ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
			readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "presence", "absent",1);
			if((lc($power) eq "standby") || (lc($power) eq "stdby") || (lc($power) eq "off"))
				{    
					readingsBulkUpdate($hash, "state", "off",1);
				}
			else{
			        readingsBulkUpdate($hash, "state", "on",1);
			}
            
			readingsBulkUpdate($hash, "power", "off",1);
			readingsEndUpdate($hash, 1);
        }  

    $hash->{helper}{AVAILABLE} = 0;	
	
	Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Resetting timer now and returning";
	YAMAHA_MC_ResetTimer($hash);
	 
	return undef;
  }

  # no errors occurred
  elsif ($data ne "") 
  { 
    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse data: \n $data";
    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse cmd: \n $cmd"; 
	
	# resetting timeout to 0
	$hash->{helper}{TIMEOUT_COUNT} = 0;
	
	if (defined($arg)){
	  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse args:  ".join(" ", $arg); 
	}  
	Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse argsEnde" ;
	
    if (!defined $hash->{helper}{noPm_JSON})
    {
      if ($data =~ /^\{/) { # $data contains json
        use JSON;
        use utf8;
        use Encode qw( encode_utf8 );
        use JSON   qw( decode_json );        

        # hash %res contains answer that must be parsed and be written into readings
        # with readings*Update...
        my %res = %{decode_json(encode_utf8($data))};
        my @getStatusVal = split(/\,/ , $data); 

        #Dumps hash to log, there you can see Yamaha's response
        #see: https://wiki.selfhtml.org/wiki/Perl/Hashes
	    Log3 $name, 5, "$type: $name YAMAHA_MC_httpRequestParse got json repsonse, following Dumper von result \n";
        Log3 $name, 5, Dumper(%res);

        my $responseCode = $res{"response_code"}; #see Dumper output what keyXYZ really is.
	    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse ResponseCode = $responseCode"; 
		
		#response code description
		#0 Successful request
		#1 Initializing
		#2 Internal Error
		#3 Invalid Request (A method did not exist, a method wasn’t appropriate etc.)
		#4 Invalid Parameter (Out of range, invalid characters etc.)
		#5 Guarded (Unable to setup in current status etc.)
		#6 Time Out
		#99 Firmware Updating
		#(100s are Streaming Service related errors)
		#100 Access Error
		
		if ($responseCode==1){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Initializing in progress',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode,1 );
		  readingsEndUpdate($hash, 1);
		  }
		elsif ($responseCode==2){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Internal Error',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  }  
		elsif ($responseCode==3){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Invalid Request',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  } 
		elsif ($responseCode==4){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Invalid Parameter (Out of range, invalid characters etc.)',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  
			# call original cmd again if requested original_cmd
			if (defined($options->{original_cmd}) && ($options->{original_cmd} ne "") && $cmd ne "?")
			{
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParseREsponse Code 4, current cmd $cmd original command for device ".$options->{original_cmd}." calling cmd again";
				#fhem("set ".$name." ". $options->{original_cmd});
			 }
			else {
			  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParseREsponse Code 4, current cmd $cmd original command for device not defined ";
			}
		
			my $original_data = "";
			my $original_arg = $options->{original_arg};

		  
		  # perhaps navigate too far back or forth in menu list
		  # call original cmd again if requested original_cmd
			if (defined($options->{original_cmd}) && ($options->{original_cmd} ne "") )
			{
				Log3 $name, 5, "YAMAHA_MC ($name) - REsponse Code 4, original command for device ".$options->{original_cmd}." calling cmd again";
				Log3 $name, 5, "YAMAHA_MC ($name) - fhem Befehl : ". "set ".$name." ". $options->{original_cmd};
				#YAMAHA_MC_httpRequestQueue($hash, $options->{original_cmd}, "",{options => {can_fail => 1, priority => 2}}); # call fn that will do the http request	 
				fhem("set ".$name." ". $options->{original_cmd}." ". $options->{original_arg});
				
				#unshift @{$queue_hash->{helper}{CMD_QUEUE}}, {options=> { priority => 1, not_before => (gettimeofday()+$options->{wait_after_response})} };
			}
		  
		  } 
		elsif ($responseCode==5){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Unable to setup in current status',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  } 
		elsif ($responseCode==6){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Time Out',1);
		  readingsBulkUpdate($hash, "power", "off",1);
          readingsBulkUpdate($hash, "state","off",1);
		  readingsBulkUpdate($hash, 'currentMenuLayer', undef,1 );	
		  readingsBulkUpdate($hash, 'currentMenuName', undef,1 );			  
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  } 
        elsif ($responseCode==99){
		  readingsBeginUpdate($hash); 
		  readingsBulkUpdate($hash, "last_error", 'Firmware Updating',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  } 
        elsif ($responseCode>=100){
		  readingsBeginUpdate($hash); 
		  #readingsBulkUpdate($hash, "power", "off",1);
          #readingsBulkUpdate($hash, "state", "off",1);
		  readingsBulkUpdate($hash, 'currentMenuLayer', undef,1 );	
		  readingsBulkUpdate($hash, 'currentMenuName', undef,1 );	
		  readingsBulkUpdate($hash, "last_error", 'Access Error',1);
		  readingsBulkUpdate($hash, "response_code", $responseCode, );
		  readingsEndUpdate($hash, 1);
		  } 
        else{		  
			readingsSingleUpdate($hash, "response_code", $responseCode,0 );	
			
			# add a dummy queue entry to wait a specific time before next command starts
			if($options->{wait_after_response})
			{
				Log3 $name, 5, "YAMAHA_MC ($name) - next command for device ".$queue_hash->{NAME}." has to wait at least ".$options->{wait_after_response}." seconds before execution";
				unshift @{$queue_hash->{helper}{CMD_QUEUE}}, {options=> { priority => 1, not_before => (gettimeofday()+$options->{wait_after_response})} };
			}
				
			
			# device reaappeared
			if(defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
			{
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - device $name reappeared";
				readingsBeginUpdate($hash);  
				readingsBulkUpdate($hash, "presence", "present", 1); 
				if((lc($power) eq "standby") || (lc($power) eq "stdby") | (lc($power) eq "off"))
				{    
					readingsBulkUpdate($hash, "state", "off",1);
					readingsBulkUpdate($hash, 'currentMenuLayer', undef,1 );	
					readingsBulkUpdate($hash, 'currentMenuName', undef,1 );	
		  
				}
				else{
						readingsBulkUpdate($hash, "state", "on",1);
				}
				readingsEndUpdate($hash, 1);			
			}
			
			$hash->{helper}{AVAILABLE} = 1;
			
			
			if($cmd eq "getStatus")
			{
			
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Starte Handling fuer getStatus"; 
			  
			  
			  #my $getStatusVal[1] =~ /"system".*/;
              my $sound_program="";
			  my $power = $res{"power"}; 
			  my $volume = $res{"volume"}; 
			  my $max_volume = $res{"max_volume"}; 
			  $sound_program = $res{"sound_program"}; 
			  my $input = $res{"input"}; 
			  my $mute = $res{"mute"}; 
			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse real volume $volume"; 
			  $volume = YAMAHA_MC_volume_abs2rel($hash,$volume);
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse relative volume $volume"; 
			  
			  
			  my $currentPower = ReadingsVal($name, "power","unknown");		
			  my $currentVolume = YAMAHA_MC_volume_abs2rel($hash,ReadingsVal($name, "volume",15));		
			  my $currentMaxVolume = ReadingsVal($name, "max_volume",60);		
			  my $currentInput = ReadingsVal($name, "input","unknown");		
			  my $currentsound_program = ReadingsVal($name, "sound_program","unknown");		
			  my $currentMute = ReadingsVal($name, "mute","false");		
			  my $currentState = ReadingsVal($name, "state","off");		
			  
			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Power $currentPower to Val $power"; 
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse volume $currentVolume to Val  $volume"; 
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse max_volume $currentMaxVolume to Val  $max_volume"; 
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParseinput $currentInput to Val  $input"; 
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse mute $currentMute to Val $mute"; 			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse cmd first Val $getStatusVal[1]"; 			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse cmd current state $currentState"; 			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse cmd currentsound_program $currentsound_program"; 			  
			  
			
			  # Update Readings only if really changed
			  if((lc($power) eq "standby") || (lc($power) eq "stdby")) 
				{   
                    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse setting power status from $currentPower to off"; 			   				
					$power = "off";
				}
				
			  if ($currentPower ne $power) {				
			    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse power status changed from $currentPower to $power"; 			   				
			    readingsSingleUpdate($hash, "power", lc($power),1  );
			  }	
			  if ($currentVolume ne $volume) {
			    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse volume status changed from $currentVolume to $volume"; 			   				
			    readingsSingleUpdate($hash, "volume", $volume,1 );
			  }		
			  #if ($currentMaxVolume ne $max_volume) {
			    readingsSingleUpdate($hash, "max_volume", $max_volume,1 );			    
			  #}	
			  if ($currentInput ne $input) {
			    readingsSingleUpdate($hash, "input", $input,1 );			    
			  }	
			  if ($currentMute ne $mute) {
			    readingsSingleUpdate($hash, "mute", $mute, 1 );			    
			  }	
			   if (lc($currentState) ne lc($power)) {
			    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse state status changed from $currentState to $power";
			    readingsSingleUpdate($hash, "state", lc($power),1);			    
			  }	
			  if (((lc($power) eq "standby") || (lc($power) eq "stdby") || (lc($power) eq "off")) && ($currentState eq "on"))
				{    
				    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse stetting status to off";
					readingsSingleUpdate($hash, "state", "off",1);
				}
			  if (defined($sound_program)) 
			  {
			    if ($currentsound_program ne $sound_program) {
			      readingsSingleUpdate($hash, "sound_program", $sound_program, 1 );			    
			    }		
			  }
              		  
			  #if ($currentMaxVolume ne $max_volume) {
			  #  readingsSingleUpdate($hash, "max_volume", $max_volume,1 );
			  #}
			  
			
			  #Reading Values for equalizer and update reading if changed ?			
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Reading Values of equalizer \n"; 
			  my $equalizer = $res{"equalizer"}; 
						
			  if (defined $equalizer->{low}) {
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse- found equalizer low : " . $equalizer->{"low"};
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse- found equalizer mid " . $equalizer->{"mid"};
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse- found equalizer high " . $equalizer->{"high"};		     
				#}
				
				
				my $currentEqualizerLow = ReadingsVal($name, "equalizer_low","0");	
				my $currentEqualizerMid = ReadingsVal($name, "equalizer_mid","0");	
				my $currentEqualizerHigh = ReadingsVal($name, "equalizer_high","0");	
				
				if ($currentEqualizerLow ne $equalizer->{"low"}) {
			      readingsSingleUpdate($hash, "equalizer_low", $equalizer->{"low"} ,0);			    
			    }	
				if ($currentEqualizerMid ne $equalizer->{"mid"}) {
			      readingsSingleUpdate($hash, "equalizer_mid", $equalizer->{"mid"} ,0);			    
			    }	
				if ($currentEqualizerHigh ne $equalizer->{"high"}) {
			      readingsSingleUpdate($hash, "equalizer_high", $equalizer->{"high"},0 );			    
			    }	
								
			  }
			  else {
			    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Reading Values of equalizer failed \n"; 
			  }				
			}
			elsif($cmd =~ /^(selectMenuItem|selectMenu|returnMenu)$/)
			{
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse handling selectMenuItem|selectMenu|returnMenu "; 
			  
			  if (defined($options->{newMenuLayer}) && ($options->{newMenuLayer} ne "") ) {
				  my $newMenuLayer = ($options->{newMenuLayer});
				  
				  if (defined($newMenuLayer)){
					 Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse selectMenuItem|selectMenu|returnMenu now in New Menu Layer ". $newMenuLayer; 
				  }
              }
			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse calling getMenut Items again to get new structure"; 
			  # get new menu info
		      YAMAHA_MC_httpRequestQueue($hash, "getMenuItems", "",{options => {can_fail => 1, priority => 1, at_first => 1, original_cmd => ""}}); # call fn that will do the http request	
              return undef;			  
		    }
			
			elsif($cmd =~ /^(selectPlayMenuItem|selectPlayMenu)$/)
			{
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse handling selectPlayMenuItemand selectPlayMenu "; 
			  
			  # Resetting Flag for setting in Progress
			  if ((defined($hash->{settingChannelInProgress})) && ($hash->{settingChannelInProgress}==1)) {
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse selectPlayMenu ended, deleting SettingChannelinprogress ";
				  $hash->{settingChannelInProgress}=0;				  
				}	  
			  # get new play info
			  # if option init then set fac MenuName
		      YAMAHA_MC_getPlaybackStatus($hash,2);		
              return undef;			  
		    }
			elsif($cmd eq "input")
			{
			 Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse handling input "; 
			 Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse setting input successfully to ".$arg; 
			 # mode=autoplay_disabled rausschneiden
			 $arg =~ s/ mode=autoplay_disabled//g;   
			 Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse setting input2 successfully to ".$arg; 
			 
			 
			 readingsSingleUpdate($hash, 'input', $arg, 1);	
			}
			elsif($cmd eq "TurnFavNetRadioChannelOn")
			{
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse handling TurnFavNetRadioChannelOn"; 
				my @list_cmds = split("/", $arg);
				
				if (!defined($hash->{FavoriteNetRadioChannelInProgress})) {
				 $hash->{FavoriteNetRadioChannelInProgress}=0;
				}
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse TurnFavServerChannelOn FavoriteNetRadioChannelInProgress=".$hash->{FavoriteNetRadioChannelInProgress}; 
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse TurnFavServerChannelOn should i call me again ?"; 
				
				if (defined($options->{original_cmd})) {
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse original cmd=".$options->{original_cmd}; 
				}
				
				if ((!defined($options->{original_cmd})) and ($hash->{FavoriteNetRadioChannelInProgress}==1)) {
                  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse TurnFavServerChannelOn yes i call me again with Arg ".$arg; 
			      #YAMAHA_MC_httpRequestQueue($hash, $cmd, $arg,{options => {unless_in_queue => 1, can_fail => 1, priority => 2}}); # call fn that will do the http request	
				  YAMAHA_MC_Set($hash,$hash,$cmd,$arg);
				}
				
				#if($data =~ /menu_layer/)
				#{
				   
				#	my $current_list = $res{"index"};
				#	my $current_line = $res{"index"};					
				#	
				#	my $menu_layer = $res{"menu_layer"}; 
			    #    my $max_line = $res{"max_line"}; 
			    #    my $index = $res{"index"}; 
			    #    my $menu_name = $res{"menu_name"}; 
			    #    my $playing_index = $res{"playing_index"}; 
				#	#my $list_info=%res->{list_info};
				#	my $list_info=$res{list_info};

				#	readingsBeginUpdate($hash);	 
				#	readingsBulkUpdate($hash, 'currentMenumaxItems', $max_line);		  
				#	readingsBulkUpdate($hash, 'currentMenuLayer', $menu_layer);		  
				#	readingsBulkUpdate($hash, 'currentMenuName', $menu_name);		  
				#	readingsBulkUpdate($hash, 'currentMenuPlayingIndex', $playing_index);		  
				#	readingsEndUpdate($hash, 1);
					
				#	my $menu_status = "Ready"; # musiccast devices do not provide <Menu_Status> so "Ready" must be assumed					
				#	my $last = ($options->{last_menu_item} or ($menu_layer == ($#list_cmds + 1)));

				#	Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse currentMenuLayer=$menu_layer"; 
				#	Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse currentMenuName=$menu_name"; 
				#	Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse index=$index"; 
				#}
				#if ($hash->{FavoriteNetRadioChannelInProgress}==1) {
				#	  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse TurnFavServerChannelOn still in progress restart with Arg ".$arg; 
			    #		  YAMAHA_MC_httpRequestQueue($hash, $cmd, $arg,{options => {unless_in_queue => 1, can_fail => 1, priority => 2}}); # call fn that will do the http request	 
				#	}
			
			}	            
			elsif($cmd eq "TurnFavServerChannelOn")
			{
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse handling TurnFavServerChannelOn"; 
				my @list_cmds = split("/", $arg);
				
				
				
				if($data =~ /menu_layer/)
				{
				   
					my $current_list = $res{"index"};
					my $current_line = $res{"index"};					
					
					my $menu_layer = $res{"menu_layer"}; 
			       my $max_line = $res{"max_line"}; 
			        my $index = $res{"index"}; 
			        my $menu_name = $res{"menu_name"}; 
			        my $playing_index = $res{"playing_index"}; 
					#my $list_info=%res->{list_info};
					my $list_info=$res{list_info};

					readingsBeginUpdate($hash);	 
					readingsBulkUpdate($hash, 'currentMenumaxItems', $max_line);		  
					readingsBulkUpdate($hash, 'currentMenuLayer', $menu_layer);		  
					readingsBulkUpdate($hash, 'currentMenuName', $menu_name);		  
					readingsBulkUpdate($hash, 'currentMenuPlayingIndex', $playing_index);		  
					readingsEndUpdate($hash, 1);
					
					my $menu_status = "Ready"; # musiccast devices do not provide <Menu_Status> so "Ready" must be assumed					
					my $last = ($options->{last_menu_item} or ($menu_layer == ($#list_cmds + 1)));

					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse currentMenuLayer=$menu_layer"; 
					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse currentMenuName=$menu_name"; 
					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse index=$index"; 
					
					
					
					
				}
			}	            
			elsif($cmd eq "NetRadioNextFavChannel")
			{
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse handling NetRadioNextFavChannel"; 
				my @list_cmds = split("/", $arg);
				
				if($data =~ /menu_layer/)
				{
				   
					my $current_list = $res{"index"};
					my $current_line = $res{"index"};					
					
					my $menu_layer = $res{"menu_layer"}; 
			        my $max_line = $res{"max_line"}; 
			        my $index = $res{"index"}; 
			        my $menu_name = $res{"menu_name"}; 
			        my $playing_index = $res{"playing_index"}; 
					#my $list_info=%res->{list_info};
					my $list_info=$res{list_info};

					readingsBeginUpdate($hash);	 
					readingsBulkUpdate($hash, 'currentMenumaxItems', $max_line);		  
					readingsBulkUpdate($hash, 'currentMenuLayer', $menu_layer);		  
					readingsBulkUpdate($hash, 'currentMenuName', $menu_name);		  
					readingsBulkUpdate($hash, 'currentMenuPlayingIndex', $playing_index);		  
					readingsEndUpdate($hash, 1);
					
					my $menu_status = "Ready"; # musiccast devices do not provide <Menu_Status> so "Ready" must be assumed					
					my $last = ($options->{last_menu_item} or ($menu_layer == ($#list_cmds + 1)));

					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse NetRadioNextFavChannel currentMenuLayer=$menu_layer"; 
					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse NetRadioNextFavChannel currentMenuName=$menu_name"; 
					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse NetRadioNextFavChannel index=$index"; 
				}
			}					
			elsif($cmd eq "navigateListMenu")
			{
				my @list_cmds = split("/", $arg);
				
				if($data =~ /menu_layer/)
				{
				   
					#my $menu_layer = $1;
					#my $menu_name = $2;
					my $current_list = $res{"index"};
					my $current_line = $res{"index"};
					#my $max_line = $5;
					
					my $menu_layer = $res{"menu_layer"}; 
			        my $max_line = $res{"max_line"}; 
			        my $index = $res{"index"}; 
			        my $menu_name = $res{"menu_name"}; 
			        my $playing_index = $res{"playing_index"}; 
					#my $list_info=%res->{list_info};
					my $list_info=$res{list_info};

					  readingsBeginUpdate($hash);	 
					  readingsBulkUpdate($hash, 'currentMenumaxItems', $max_line);		  
					  readingsBulkUpdate($hash, 'currentMenuLayer', $menu_layer);		  
					  readingsBulkUpdate($hash, 'currentMenuName', $menu_name);		  
					  readingsBulkUpdate($hash, 'currentMenuPlayingIndex', $playing_index);		  
					  readingsEndUpdate($hash, 0);
					
					my $menu_status = "Ready"; # musiccast devices do not provide <Menu_Status> so "Ready" must be assumed					
					my $last = ($options->{last_menu_item} or ($menu_layer == ($#list_cmds + 1)));

					if($menu_status eq "Ready")
					{               
						# menu browsing finished
						if(exists($options->{last_layer}) and $options->{last_layer} == $menu_layer and $last and $options->{item_selected})
						{
							Log3 $name, 5 ,"YAMAHA_MC ($name) - menu browsing to $arg is finished. requesting basic status";
							
							YAMAHA_MC_GetStatus($hash, 1);
							return undef;
						}
						
						# initialization sequence
						if($options->{init} and $menu_layer > 1)
						{
							Log3 $name, 5 ,"YAMAHA_MC ($name) - return to start of menu to begin menu browsing";
														
							YAMAHA_MC_httpRequestQueue($hash, "returnMenu", "",{options => {can_fail => 1, priority => 2}});
							#YAMAHA_MC_httpRequestQueue($hash, "getMenu", "",{options => {can_fail => 1, priority => 2}});
							
							# Original Queue Hash again until Layer 0 is reached
							Log3 $name, 5 ,"YAMAHA_MC ($name) - calling YAMAHA_MC_HandleCmdQueue to continue menu browsing";
							YAMAHA_MC_HandleCmdQueue($queue_hash,$cmd, $arg);
							return;
						}
						
						if($menu_layer > @list_cmds)
						{
							# menu is still not browsed fully, but no more commands are left.
							Log3 $name, 5 ,"YAMAHA_MC ($name) - no more commands left to browse deeper into current menu.";
						}
						else # play my $FavoriteNetRadioChannel = AttrVal($hash->{NAME}, "FavoriteNetRadioChannel",1);
						{
							Log3 $name, 5 ,"YAMAHA_MC ($name) - playing FavoriteNetRadioChannel )";
							my $FavoriteNetRadioChannel = AttrVal($hash->{NAME}, "FavoriteNetRadioChannel",1);				
                            Log3 $name, 5 ,"YAMAHA_MC ($name) - playing FavoriteNetRadioChannel Cahnnel is $FavoriteNetRadioChannel)";							
							YAMAHA_MC_httpRequestQueue($hash, "selectPlayMenu", $FavoriteNetRadioChannel, {options => {can_fail => 1, priority => 2}});
							
							}												
					}
					else
					{
						# list must be checked again in 1 second.
						Log3 $name, 5 ,"YAMAHA_MC ($name) - menu is busy. retrying in 1 second";
						
					}
				}
			}			
			elsif(($cmd eq "getListInfo") || ($cmd eq "getMenuItems") || ($cmd eq "getMenu")) {
			
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Starte Handling fuer getListInfo|getMenuItems|getMenu"; 
					  
			  my $menu_layer = $res{"menu_layer"}; 
			  my $max_line = $res{"max_line"}; 
			  my $index = $res{"index"}; 
			  my $menu_name = $res{"menu_name"}; 
			  my $playing_index = $res{"playing_index"}; 

			  readingsBeginUpdate($hash);	 
			  readingsBulkUpdate($hash, 'currentMenumaxItems', $max_line);		  
			  readingsBulkUpdate($hash, 'currentMenuLayer', $menu_layer);		    
			  readingsBulkUpdate($hash, 'currentMenuName', $menu_name);		  
			  readingsBulkUpdate($hash, 'currentMenuPlayingIndex', $playing_index);		  
			  readingsEndUpdate($hash, 1);
			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse new Menu Layer is $menu_layer"; 
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse new Menu Name is $menu_name"; 

			  # building new list with current menuitems 
			  #delete($hash->{helper}{"MENUITEMS"}) if(exists($hash->{helper}{"MENUITEMS"}));			  
			  $hash->{helper}{MENUITEMS} = "";		  
              my $menuitems ="";		
			
			  #foreach my $menu_item(@{%res->{list_info}}) {		  
			  foreach my $menu_item(@{$res{list_info}}) {		  
				 Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Starte Zerlegen List of MenuItems"; 
				 if(defined($hash->{helper}{MENUITEMS}) and length($hash->{helper}{MENUITEMS}) > 0)
					{
					   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found next menu_item: " . $menu_item->{"text"};
					   $hash->{helper}{MENUITEMS} .= "|".$menu_item->{"text"};
					   $menuitems .= "|".$menu_item->{"text"};
					}
				 else
				    {
					  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found first menu_item: " . $menu_item->{"text"};
					  $hash->{helper}{MENUITEMS} = $menu_item->{"text"};
					  $menuitems = $menu_item->{"text"};
					}
						
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse menu item list helper ".$hash->{helper}{MENUITEMS};
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse menu item list ".$menuitems;
			  }
			 if(($hash->{helper}{MENUITEMS} eq "") && ($max_line==0)){
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse ENDE menu item list, no MenuItems available ";
			 }
			 else {
			   $hash->{helper}{MENUITEMS}=$menuitems;
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse ENDE menu item list helper ".$hash->{helper}{MENUITEMS};
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse ENDE menu item list helper ".$menuitems;
			   YAMAHA_MC_UpdateLists($hash);			   
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse YAMAHA_MC_UpdateLists called ".$hash->{helper}{MENUITEMS}; 
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse YAMAHA_MC_UpdateLists called ".$menuitems; 
			 }  
			}

			elsif ($cmd eq "setSoundProgramList")  {
			  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse setSoundProgramList succesfully ended, getting soundprogam again "; 
			  YAMAHA_MC_httpRequestQueue($hash, "getStatus", "", {options => {can_fail => 1, priority => 2}});
			}			
			elsif($cmd eq "getSoundProgramList")  {
			
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Starte Handling fuer getSoundProgramList"; 
					  

			  # building new list with current sound programs 
			  
			  $hash->{helper}{SOUNDPROGRAMS} = "";		  
              my $soundprograms = "";
			  #my @array = @{ $soundprograms->{'sound_program_list'} }
			  
			  foreach my $sound_programm(@{$res{sound_program_list}}) {
			     Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Starte Zerlegen List of sound_program_list"; 
				 if(defined($hash->{helper}{SOUNDPROGRAMS}) and length($hash->{helper}{SOUNDPROGRAMS}) > 0)
					{
					   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found next sound_programm: " . $sound_programm;
					   $hash->{helper}{SOUNDPROGRAMS} .= "|".$sound_programm;
					   $soundprograms .= "|".$sound_programm;
					}
				 else
				    {
					  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found first sound_programm: " . $sound_programm;
					  $hash->{helper}{SOUNDPROGRAMS} = $sound_programm;
					  $soundprograms = $sound_programm;
					}
						
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse sound_programm list helper ".$hash->{helper}{SOUNDPROGRAMS};
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse sound_programm list ".$soundprograms;
			  
			  }
			  
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Starte Handling fuer getSoundProgramList setting helper now"; 
			  $hash->{helper}{SOUNDPROGRAMS} = $soundprograms;		    			 
			  
			 if($hash->{helper}{SOUNDPROGRAMS} eq "") {
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse ENDE soundprogram list, no soundprograms available ";
			 }
			 else {
			   $hash->{helper}{SOUNDPROGRAMS}=$soundprograms;
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse ENDE soundprogram list helper ".$hash->{helper}{SOUNDPROGRAMS};
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse ENDE soundprogram list helper ".$soundprograms;
			   YAMAHA_MC_UpdateLists($hash);			   
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse YAMAHA_MC_UpdateLists called ".$hash->{helper}{SOUNDPROGRAMS}; 
			   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse YAMAHA_MC_UpdateLists called ".$soundprograms; 
			 }  
			}

			elsif($cmd eq "getFeatures"){
			
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getFeatures"; 
			  
			  # building new list with current inputs 
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start building list for inputs"; 
			  delete($hash->{helper}{"INPUTS"}) if(exists($hash->{helper}{"INPUTS"}));
			  $hash->{helper}{INPUTS} = "";		  		  
			  
			  
			  #foreach my $input(@{%res->{system}->{input_list}}) {
			  foreach my $input(@{$res{system}{input_list}}) {
			  
				 #Log3 $name, 4, "$type: $name List of Inputs " . $input{"id"} . "\n"; 
				 Log3 $name, 4, "$type: $name SYAMAHA_MC_httpRequestParse starte Zerlegen List of Inputs \n"; 
				 if(defined($hash->{helper}{INPUTS}) and length($hash->{helper}{INPUTS}) > 0)
						{
						   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found next input: " . $input->{"id"};	
						   $hash->{helper}{INPUTS} .= "|".$input->{"id"};
						}
				 else
                       {
					    Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found first input: " . $input->{"id"};					
                        $hash->{helper}{INPUTS} = $input->{"id"};
                        }					   
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - added input to helper: " . $hash->{helper}{INPUTS};
			  }
			 
              delete($hash->{helper}{ZONES}) if(exists($hash->{helper}{ZONES}));
    
              Log3 $name, 4, "YAMAHA_MC ($name) - checking available zones"; 
    
	 
			  #foreach my $zone(@{%res->{zone}}) {			 		 
			  foreach my $zone(@{$res{zone}}) {			 		 
				 Log3 $name, 4, "$type: $name SYAMAHA_MC_httpRequestParse starte Zerlegen List of ZOnes \n"; 
				 if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
						{
						   Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found next zone: " . $zone->{"id"};	
						   $hash->{helper}{ZONES} .= "|".$zone->{"id"};
						}
				 else
                       {
					    Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found first zone: " . $zone->{"id"};					
                        $hash->{helper}{ZONES} = $zone->{"id"};
                        }					   
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - added zone to helper: " . $hash->{helper}{ZONES};
			  } 
			}
			
			
			elsif($cmd eq "getFuncStatus"){
			
			  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getFuncStatus"; 
			  
			  
				  
        		  my $auto_power_standby = $res{"auto_power_standby"}; 
				  my $speaker_a = $res{"speaker_a"}; 
				  my $speaker_b = $res{"speaker_b"}; 
				  my $headphone = $res{"headphone"}; 
				  my $hdmi_out_1 = $res{"hdmi_out_1"}; 
				  my $hdmi_out_2 = $res{"hdmi_out_2"}; 
				  my $ir_sensor = $res{"ir_sensor"}; 
				  my $party_mode = $res{"party_mode"}; 
				  
				  					  
			      unless(defined($speaker_a)) {$speaker_a="false"};			  
				  unless(defined($speaker_b)) {$speaker_b="false"};			  
				  unless(defined($headphone)) {$headphone="false"};			  
				  unless(defined($hdmi_out_1)) {$hdmi_out_1="false"};		
				  unless(defined($hdmi_out_2)) {$hdmi_out_2="false"};		
				  unless(defined($ir_sensor)) {$ir_sensor="false"};		
				  unless(defined($party_mode)) {$party_mode="false"};		
				  unless(defined($auto_power_standby)) {$auto_power_standby="false"};	
						  
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse auto_power_standby Val \n $auto_power_standby"; 
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse speaker_a Val \n $speaker_a"; 		  
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse speaker_b Val \n $speaker_b"; 
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse headphone Val \n $headphone"; 
				  
				  readingsBeginUpdate($hash);				
				  readingsBulkUpdate($hash, "auto_power_standby", $auto_power_standby,1 );
				  readingsBulkUpdate($hash, "speaker_a", $speaker_a,1 );				  
				  readingsBulkUpdate($hash, "speaker_b", $speaker_b,1 );				  
				  readingsBulkUpdate($hash, "headphone", $headphone,1 );
				  readingsBulkUpdate($hash, "hdmi_out_1", $hdmi_out_1,1 );
				  readingsBulkUpdate($hash, "hdmi_out_2", $hdmi_out_2,1 );
				  readingsBulkUpdate($hash, "ir_sensor", $ir_sensor,1 );
				  readingsBulkUpdate($hash, "party_mode", $party_mode,1 );
				  readingsEndUpdate($hash, 1);	
			}
		
			elsif($cmd eq "getPlayInfo"){
				
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getPlayInfo"; 
				  
				  my $playback_input = $res{"input"}; 
				  my $playback_status = $res{"playback"}; 
				  my $station_name = $res{"artist"}; 
				  my $album_name = $res{"album"}; 
				  my $track = $res{"track"}; 
				  my $albumart_url = $res{"albumart_url"};
				  my $albumart_id = $res{"albumart_id"};
				  my $HOST = $hash->{HOST};
				  
				  # komplette url als albumart_url
				  $albumart_url= "http://" . $HOST . $albumart_url;
						  
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse playback_input Val \n $playback_input"; 
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse playback_status Val \n $playback_status"; 		  
				  
				  readingsBeginUpdate($hash);				
				  readingsBulkUpdate($hash, "playback_input", $playback_input,1 );
				  readingsBulkUpdate($hash, "playback_status", $playback_status,1 );				  
				  readingsBulkUpdate($hash, "station_name", $station_name,1 );
				  readingsBulkUpdate($hash, "album_name", $album_name,1 );
				  readingsBulkUpdate($hash, "track", $track,1 );
                                  readingsBulkUpdate($hash, "albumart_url", $albumart_url, undef, 1 );	
				  readingsBulkUpdate($hash, "albumart_id", $albumart_id,1 );
				  readingsEndUpdate($hash, 1);		  
			}		  
			elsif($cmd eq "volume"){
				
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for volume"; 
				  my $target_volume = 15;
				  if (exists($options->{volume_target})) {
				    $target_volume = $options->{volume_target};
			      }
				  				  						  
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse volume target was $target_volume \n"; 
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Updating REading for volume to $target_volume \n"; 	  
				  readingsSingleUpdate($hash, "volume", $target_volume,1 );				  	  
			}
			elsif($cmd eq "getDeviceInfo"){
				
				  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getDeviceInfo"; 
				  my $model = $res{"model_name"}; 				  
				  my $system_id = $res{"system_id"}; 
				  my $device_id = $res{"device_id"}; 
				  my $system_version = $res{"system_version"}; 
				  my $api_version = $res{"api_version"}; 
				  				  				  
				  $hash->{MODEL} = $model;
				  $hash->{SYSTEM_ID} = $system_id;
				  $hash->{DEVICE_ID} = $device_id;
				  $hash->{SYSTEM_VERSION} = $system_version;
				  $hash->{API_VERSION} = $api_version;
				  
				  				   
				  
			 }
		    elsif($cmd eq "getNetworkStatus"){
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getNetworkStatus"; 
				my $network_name = $res{"network_name"}; 				  
				my $connection = $res{"connection"}; 
				my $vtuner_id = $res{"vtuner_id"}; 
				my $mac_address = $res{"mac_address"}; 				
				
                $hash->{network_name} = $network_name;				
				$hash->{connection} = $connection;				
				$hash->{vtuner_id} = $vtuner_id;				
				$hash->{mac_address} = $mac_address;								
				
				my $wireless_lan = $res{"wireless_lan"}; 
			
			
			    if (defined $wireless_lan->{ssid}) {
				  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found wireless_lan ssid : " . $wireless_lan->{"ssid"};
				  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found wireless_lan strength " . $wireless_lan->{"strength"};
								  
				  $hash->{WLAN_SSID} =$wireless_lan->{"ssid"};
				  $hash->{WLAND_STRENGTH} = $wireless_lan->{"strength"};
				}  
				  
			 }
            elsif($cmd eq "getLocationInfo"){
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getLocationInfo"; 
				my $name = $res{"name"}; 				  
				my $id = $res{"id"}; 
				my $vtuner_id = $res{"vtuner_id"}; 
				my $mac_address = $res{"mac_address"}; 				
				
                $hash->{location_name} = $name;				
				$hash->{location_id} = $id;				
				
				my $zone_list = $res{"zone_list"}; 				
				$hash->{helper}{ZONES} = () unless(defined($hash->{helper}{ZONES}));
			
			
			    if (defined $zone_list->{main}) {
				  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found zone_list main : " . $zone_list->{"main"}; 
				 					  				  
				  # In case of a redefine, check the zone parameter if the specified zone exist, otherwise use the main zone
					if(not defined($hash->{helper}{ZONES}) || length($hash->{helper}{ZONES}) == 0)
					{
						if ($zone_list->{"main"} eq "true")
						{
							$hash->{ACTIVE_ZONE} = "main";
							$hash->{SELECTED_ZONE} = "main";
							$hash->{helper}{AVAILABLE_ZONES} = "main"
						}
						if ($zone_list->{"zone2"} eq "true")
						{							
							Log3 $name, 4, "YAMAHA_MC ($name)YAMAHA_MC_httpRequestParse  - found zone_list zone2 " . $zone_list->{"zone2"};
							$hash->{helper}{AVAILABLE_ZONES} = $hash->{helper}{AVAILABLE_ZONES} ."|" ."zone2";
						}
						if ($zone_list->{"zone3"} eq "true")
						{							
							Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found zone_list zone3 " . $zone_list->{"zone3"};		
							$hash->{helper}{AVAILABLE_ZONES} = $hash->{helper}{AVAILABLE_ZONES} ."|" ."zone3";
						}
						if ($zone_list->{"zone4"} eq "true")
						{							
							Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found zone_list zone4 " . $zone_list->{"zone4"};		
							$hash->{helper}{AVAILABLE_ZONES} = $hash->{helper}{AVAILABLE_ZONES} ."|" ."zone4";
						}
					  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse -  zone_list created";	
					}
				}  
				  
			 }		
			elsif($cmd eq "getDistributionInfo"){
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getDistributionInfo"; 
				my $group_name = $res{"group_name"}; 				  
				my $group_id = $res{"group_id"}; 
				my $group_role = $res{"role"}; 	
				
                $hash->{dist_group_name} = $group_name;				
				$hash->{dist_group_id} = $group_id;				
				$hash->{dist_group_role} = $group_role;				
				
				my $client_list = $res{"client_list"}; 				
				$hash->{helper}{client_list} = () unless(defined($hash->{helper}{client_list}));
			
			
			    if (defined $client_list) {
				  Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse - found client_list "; 	 					  				  
				
				}  
				  
			 }		 
            elsif($cmd eq "getBluetoothInfo"){
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for getBluetoothInfo"; 
				
				my $bluetooth_tx_setting = $res{"bluetooth_tx_setting"}; 				  
				my $bluetooth_connected = $res{"bluetooth_device"=>"connected"}; 
				$bluetooth_connected = "" unless defined $bluetooth_connected;
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse bluetooth_tx_setting=".$bluetooth_tx_setting; 
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse bluetooth_connected=".$bluetooth_connected; 
				
                readingsBeginUpdate($hash);        
				readingsBulkUpdate($hash, "bluetooth_tx_setting", $bluetooth_tx_setting,1);
				readingsBulkUpdate($hash, "bluetooth_connected", $bluetooth_connected,1);
				readingsEndUpdate($hash, 1);				
				
				
				 }
			elsif (($cmd eq "mute")) {
			  if ($arg eq "true"){
			    readingsSingleUpdate($hash, "mute", "true",1 );	
			  }
			  else{
			    readingsSingleUpdate($hash, "mute", "false",1 );	
			  }
			
			}
			elsif (($cmd eq "setSpeakerA")) {
			  if ($arg eq "true"){
			    readingsSingleUpdate($hash, "speaker_a", "true",1 );	
			  }
			  else{
			    readingsSingleUpdate($hash, "speaker_a", "false",1 );	
			  }
			
			}
			elsif (($cmd eq "setSpeakerB")) {
			  if ($arg eq "true"){
			    readingsSingleUpdate($hash, "speaker_b", "true",1 );	
			  }
			  else{
			    readingsSingleUpdate($hash, "speaker_b", "false",1 );	
			  }
			
			}
			elsif($cmd eq "isNewFirmwareAvailable"){
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for isNewFirmwareAvailable"; 
				
				my $FirmwareAvailable = $res{"available"}; 				  
								
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse FirmwareAvailable=".$FirmwareAvailable; 
				
				readingsSingleUpdate($hash, "FirmwareAvailable", $FirmwareAvailable,1);
				
				
				 }
			elsif (($cmd eq "on") || ($cmd eq "off") || ($cmd eq "power") ){
				
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse Start Handling for on and off"; 
				
				my $power = ReadingsVal($name, "power", "off");
				Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse cmd is $cmd $arg and current power is set to $power"; 
				
				$hash->{attemptsToReturnMenu}=0;
				$hash->{PowerOnInProgress}=0;
								
				if (($cmd eq "on") || (($cmd eq "power") && ($arg eq "on"))){
				    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse device turned on, reset readings and start timer for getting status"; 
					readingsBeginUpdate($hash);        
					readingsBulkUpdate($hash, "state", "on",1);
					readingsBulkUpdate($hash, "power", "on",1);
					readingsBulkUpdate($hash, 'currentMenuLayer', undef,1 );
                    $hash->{settingChannelInProgress}=0;					
					readingsEndUpdate($hash, 1);
					Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse device successfully turned on - getting status via YAMAHA_MC_ResetTimer";
					# 2 seconds delay
					YAMAHA_MC_ResetTimer($hash,2);						
					
				}
				elsif(($cmd eq "off") || (($cmd eq "power") && ($arg eq "standby"))){
				    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse device turned off, reset readings and start timer for getting status"; 
					readingsBeginUpdate($hash);        
					readingsBulkUpdate($hash, "state", "off",1);
					readingsBulkUpdate($hash, "power", "off",1);
					#readingsBulkUpdate($hash, 'currentMenuLayer', undef,1 );	
					readingsEndUpdate($hash, 1);
					
					# CMD Queue Deleten
					$hash->{helper}{CMD_QUEUE} = [];
					$hash->{settingChannelInProgress}=0;
					delete($hash->{helper}{".HTTP_CONNECTION"}) if(exists($hash->{helper}{".HTTP_CONNECTION"}));
					#delete($hash->{helper}{CMD_QUEUE}) if(exists($hash->{helper}{CMD_QUEUE}));
					delete($hash->{CMDs_pending}) if(exists($hash->{CMDs_pending}));
					
					
					# 3 seconds delay
					YAMAHA_MC_ResetTimer($hash,3);						
				}			  
			 }	
			
			# call original cmd again if requested original_cmd
			if (defined($options->{original_cmd}) && ($options->{original_cmd} ne "") && $cmd ne "?")
			{
				Log3 $name, 4, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse: after all cmd handlings current cmd $cmd original command for device ".$options->{original_cmd}." calling cmd again";
				#fhem("set ".$name." ". $options->{original_cmd});
				
				my $original_data = "";
				my $original_arg = $options->{original_arg};
	
	            if (defined($original_arg)) {
				  Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse reset in queue orginal cmd ". $options->{original_cmd}." with args ".$original_arg." original prio ".$options->{original_priority};
				}
				else {
				  Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse reset in queue orginal cmd ". $options->{original_cmd}." without args original prio ".$options->{original_priority};
				}
				
				# In case any URL changes must be made, this part is separated in this function".    
				my $param = {
								data       => $original_data,
								cmd        => $options->{original_cmd},
								arg        => $original_arg,
								options    => {priority => $options->{original_priority}, unless_in_queue => 1}
							}; 
				
				push @{$hash->{helper}{CMD_QUEUE}}, $param;  
				
				Log3 $name, 5, "YAMAHA_MC ($name) YAMAHA_MC_httpRequestParse reset in queue orginal cmd  done  ". $options->{original_cmd};
				
				#unshift @{$queue_hash->{helper}{CMD_QUEUE}}, {options=> { priority => 1, not_before => (gettimeofday()+$options->{wait_after_response})} };
			}
			else {
			  Log3 $name, 4, "YAMAHA_MC ($name) - YAMAHA_MC_httpRequestParse end. no additional original_cmd stated";
			}
			
			
			#################################################################
			#see: http://www.fhemwiki.de/wiki/DevelopmentModuleIntro#Readings
			#
			# generell immer 
			#
			my $currentPower = ReadingsVal($name, "power", "off");
			my $currentPresence = ReadingsVal($name, "presence", "present");
			my $currentState = ReadingsVal($name, "state", "off");
			my $currentResponseCode = ReadingsVal($name, "responseCode", "0");
			
			# Update REadings if changed
			if ((lc($currentState) ne lc($power)) || ($currentResponseCode != $responseCode) || (lc($currentPower) ne lc($power)) || (lc($currentPresence) ne "present")) {
			    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse: status changed, updating Readings";
				readingsBeginUpdate($hash);        
				readingsBulkUpdate($hash, "presence", "present",1);
				
				if (((lc($power) eq "standby") || (lc($power) eq "stdby")) && ($currentState eq "on"))
				{    
					readingsBulkUpdate($hash, "state", "off",1);
					readingsBulkUpdate($hash, 'currentMenuLayer', undef,1 );	
				}
				elsif ($currentState ne "on") {
					readingsBulkUpdate($hash, "state", "on",1);
				}				
				readingsBulkUpdate($hash, "response_code", $responseCode, 1 );
				readingsEndUpdate($hash, 1);
            }			
			
			Log3 $name, 4, "YAMAHA_MC_httpRequestParse: end of parse of cmd $cmd, calling YAMAHA_MC_GetStatus again, should i really?"  unless($cmd =~ /^statusRequest|navigateListMenu|volume|input|tuner.+$/);
						
          } #responsecode=0
	  

		} #if data =~/^{//
      else { # no json returned
	    Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse noJson_response";
        readingsSingleUpdate($hash, "noJson_response", $data,1);
      } # end json
    }

    else { 
      Log3 $name, 4, "YAMAHA_MC_httpRequestParse type: perl module JSON not installed.";
    }
  
   
  } #($data ne "") 
  elsif($data eq "")
    {
        Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse calling YAMAHA_MC_HandleCmdQueue for cmd=$cmd";
		YAMAHA_MC_HandleCmdQueue($queue_hash,$cmd,$arg);
		Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse end1";
        return undef
    }
  
  
  Log3 $name, 4, "$type: $name YAMAHA_MC_httpRequestParse end calling YAMAHA_MC_HandleCmdQueue again ";	
  
  YAMAHA_MC_HandleCmdQueue($queue_hash,$cmd,$arg);
} # END of YAMAHA_MC_httpRequestParse


# ------------------------------------------------------------------------------
#
# check that needed perl modules are installed....
# ... without error messages

sub YAMAHA_MC_isPmInstalled($$)
{
  my ($hash,$pm) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  if (not eval "use $pm;1")
  {
    Log3 $name, 4, "$type: perl modul missing: $pm. Install it, please.";
    $hash->{MISSING_MODULES} .= "$pm ";
    return "failed: $pm";
  }
  return undef;
}

# ------------------------------------------------------------------------------

# some regexp examples...
#... checking ip and fqdn

sub YAMAHA_MC_isIPv4($) {return if(!defined $_[0]); return 1 if($_[0] =~ /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)}
sub YAMAHA_MC_isFqdn($) {return if(!defined $_[0]); return 1 if($_[0] =~ /^(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)$/)}


#############################
# Converts all Values to FHEM usable command lists
sub YAMAHA_MC_Param2Fhem($$)
{
    my ($param, $replace_pipes) = @_;

   
    $param =~ s/\s+//g;
    $param =~ s/,//g;
    #$param =~ s/_//g;
    $param =~ s/\(/_/g;
    $param =~ s/\)//g;
    $param =~ s/\|/,/g if($replace_pipes == 1);

    return lc $param;
}

#############################
# Converts all Values to FHEM usable command lists
# without removing empty spaces
sub YAMAHA_MC_Param2SpaceList($$)
{
    my ($param, $replace_pipes) = @_;
    
    $param =~ s/,//g;
    $param =~ s/"//g;
    $param =~ s/\(/_/g;
    $param =~ s/\)//g;
    $param =~ s/\|/,/g if($replace_pipes == 1);

    return lc $param;
}

#############################
# Returns the Yamaha Parameter Name for the FHEM like aquivalents
sub YAMAHA_MC_getParamName($$$)
{
    my ($hash, $name, $list) = @_;
    my $item;
   
    return undef if(not defined($list));
	
	if (!defined($name)){
	  $name = "";
	}
  
    my @commands = split("\\|",  $list);

    foreach $item (@commands)
    {
        if(YAMAHA_MC_Param2Fhem($item, 0) eq $name)
        {
            return $item;
        }
    }
    
    return undef;
}

#############################
# converts decibal volume in percentage volume (-80.5 .. 16.5dB => 0 .. 100%)
sub YAMAHA_MC_volume_rel2abs($$)
{
    my ($hash, $percentage) = @_;    
	my $currentMaxVolume = ReadingsVal($hash->{NAME},  "max_volume",60);	
    
    #  0 - 100% -equals 80.5 to 16.5 dB
    return int($percentage / 100*$currentMaxVolume);
}

#############################
# converts percentage volume in decibel volume (0 .. 100% => -80.5 .. 16.5dB)
sub YAMAHA_MC_volume_abs2rel($$)
{
    my ($hash,$absolut) = @_;
    my $currentMaxVolume = ReadingsVal($hash->{NAME},  "max_volume",60);	
	
    
    return int(($absolut )/ $currentMaxVolume*100 );
}

##############################
# replacing a hash key
sub YAMAHA_MC_hash_replace (\%$$) {
  $_[0]->{$_[2]} = delete $_[0]->{$_[1]}; # thanks mobrule!
}

sub YAMAHA_MC_httpRequestDirect($$$@)
{
  my ($hash, $cmd, $sendto, @params) = @_;
  my ($name) = $hash->{NAME};
  my ($type) = $hash->{TYPE};
  my $url = "";
  
  my $plist = join(",",@params);
  Log3 $name, 1, "$type: set $name $cmd sendto:$sendto Plist:$plist";

  #my $url = "http://".$hash->{HOST}.":".$hash->{PORT}.$hash->{URLCMD};
  
  #TOE: Anpassungen auf "dotted" API Versionen mit "." 
  my $shortAPI = $hash->{API_VERSION};
  $shortAPI=~s/\.[0-9]+//;
  Log3 $name,4,"TOe: API Version cut to $shortAPI";
  if($cmd eq "setGroupName"){
    $url = "http://$sendto:80/YamahaExtendedControl/v$shortAPI/dist/setGroupName";
  }
  elsif   ($cmd eq "setClientInfo"){
    $url = "http://$sendto:80/YamahaExtendedControl/v$shortAPI/dist/setClientInfo";
  }
  elsif   ($cmd eq "setServerInfo"){
    $url = "http://$sendto:80/YamahaExtendedControl/v$shortAPI/dist/setServerInfo";
  }
  elsif   ($cmd eq "startDistribution?num=0"){
    $url = "http://$sendto:80/YamahaExtendedControl/v$shortAPI/dist/startDistribution?num=0";
  }


  Log3 $name, 1, "$type: url => $url";

  my $httpParams = {
    url         => $url,
    timeout     => 10,
    keepalive   => 0,
    httpversion => "1.0",
    hideurl     => 0,
    method      => $hash->{HTTPMETHOD},
	data        => $hash->{POSTDATA},
    hash        => $hash,
    cmd         => $cmd,     #passthrouht to YAMAHA_MC_httpRequestParse
    plist       => $plist,   #passthrouht to YAMAHA_MC_httpRequestParse
    callback    =>  \&YAMAHA_MC_httpRequestParse # This fn will be called when finished
  };

  HttpUtils_NonblockingGet($httpParams); #Do http request with params above.

  return undef;
}

########################################################################################
#
#  YAMAHA_MC_Link - link Clients to server
#
#
########################################################################################
sub YAMAHA_MC_Link($$$@)
{
  my ($hash, $name, $cmd, @params) = @_;
#  $cmd = lc($cmd) if $cmd;

  # Parameters are all clients to be connected 
  my $plist ="";
  if((@params)){
     $plist = join(",",@params);
  }
  if ($plist eq "") {
  return "missing device name to link";
  }
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast Devices cmd:$cmd, params:".$plist;

  return if (IsDisabled $name);
  
  my $group_id = "";
  my $sendto="";
  my $groupName = "";
  my %postdata_hash = "";
  my $json = "";
  my $serverHost = $hash->{HOST};
  my $serverZone = $hash->{ZONE};
  unless(defined($hash->{location_name})) {$hash->{NAME}=$hash->{HOST};}
  my $locationName = $hash->{location_name};
  
  
  Log3 $name, 4, "$hash->{TYPE} $name: Link Musiccast Devices server is $serverHost with locatioName $locationName";
  Log3 $name, 4, "$hash->{TYPE} $name: Link Musiccast Devices try getting ip of CLient=".$plist;
   
  my $clientName= $plist;
  my $clientIp = "";
  my @clientListIP = ();
  
  #
  # first inform all clients that there is a server  
  #
  my @mc_clients = split(",", $clientName);
  foreach my $mc_client (@mc_clients) {
    Log3 $name, 4, "$hash->{TYPE} $name: Link Musiccast Devices mehr als 1 device ".$mc_client;
      if($mc_client ne "") 
	  {
		  $clientIp = "";
		  my $dev ="";
		  my $clienthash = $defs{$mc_client};
		  
		  my $clientIp = $clienthash->{HOST};
		  my $clientType = $clienthash->{TYPE};
		  my $clientZone = $clienthash->{ZONE};
			  
		  Log3 $name, 4, "$hash->{TYPE} $name: Link Musiccast Devices server=$serverHost CLientName $mc_client  IP=$clientIp Type=$clientType";
		  
		  # if device found with ip	and then send client signal to device
		  if (($clientIp ne "") && ($clientType eq "YAMAHA_MC") && ($clientIp ne $serverHost) )
		  {
			  #------------------------------------------------
			  #sent to client
			  #post /YamahaExtendedControl/v1/dist/setClientInfo
			  $group_id = "d2d82d2b86434a35a35ad77c7ec0241c";
			  my @zones = ('main');
			  
			  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast send setClientInfo to $clientIp zone $clientZone";
			  
			  my $server_ip_address="$serverHost";
			  $cmd="setClientInfo"; 
			  $sendto="$clientIp"; # Client  
				
			  #%postdata_hash = ('group_id'=>$group_id,'zone'=>\@zones,'server_ip_address'=>$server_ip_address);
			  %postdata_hash = ('group_id'=>$group_id,'zone'=>$clientZone,'server_ip_address'=>$server_ip_address);
			  
			  $json = encode_json \%postdata_hash;
			  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast send setClientInfo to $sendto Json Request ".$json;
			  $hash->{POSTDATA} = $json;  
				
			  YAMAHA_MC_httpRequestDirect($hash, $cmd, $sendto, @params); # call fn that will do the http request
			  
			  # Read Disribution Info for CLient
			  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast getting DistributionInfo for $mc_client ";		  
			  Log3 $name, 4, "$name : Link Musiccast getting DistributionInfo Ende for ". $clienthash->{NAME}; 
			  YAMAHA_MC_getDistributionInfo($clienthash);
			  Log3 $name, 4, "$clienthash->{NAME} $name : Link Musiccast getting DistributionInfo End";
						
			  Log3 $name, 4, "$name : Link Musiccast adding $clientIp to ClientList";	
			  push @clientListIP, $clientIp;
			  
			  
		   }
	  }
  }
  Log3 $name, 4, "$hash->{TYPE} $name: Link Musiccast Devices server=$serverHost List of Clients ".join(",",@clientListIP);
    
 
  #
  # now send the client list to server
  # 
  #------------------------------------------------  
  #post /YamahaExtendedControl/v1/dist/setServerInfo
  ##{"group_id":"d2d82d2b86434a35a35ad77c7ec0241c","type":"add","zone":"main","client_list":["192.168.0.28"]}
  
  my $distype="add";
  my $zone=$serverZone;
  
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast send setServerInfo client_list= ".join(";",@clientListIP);
  
  $cmd="setServerInfo"; 
  $sendto="$serverHost"; # Server
 
  %postdata_hash = ('group_id'=>$group_id,'type'=>$distype,'zone'=>$zone,'client_list'=>\@clientListIP);
  $json = encode_json \%postdata_hash;
  
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast send setServerInfo to $sendto Json Request ".$json;
  $hash->{POSTDATA} = $json;  
    
  YAMAHA_MC_httpRequestDirect($hash, $cmd, $sendto, @params); # call fn that will do the http request
  
  sleep 1;

  #------------------------------------------------
  # start Distribution - sending cmd to server 
  #http://192.168.0.25/YamahaExtendedControl/v1/dist/startDistribution?num=0
  $cmd="startDistribution?num=0"; 
  $sendto="$serverHost"; # Server
  $hash->{HTTPMETHOD}="GET";
   
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast send startDistribution to $sendto  ".$cmd;
  YAMAHA_MC_httpRequestDirect($hash, $cmd, $sendto, @params); # call fn that will do the http request
  
  # Disttibution Info des Servers auslesen
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast getting DistributionInfo for $name  ";
  
  # getting new distribtion info for server
  YAMAHA_MC_httpRequestQueue($hash, "getDistributionInfo", "", {options => {priority => 3, unless_in_queue => 1}}); # call fn that will do the http request
  
  #------------------------------------------------
  # set new name of group
  # http Post to Server
  #http://192.168.0.25/YamahaExtendedControl/v1/dist/setGroupName
  #{"name":"Wohnzimmer +1 Raum"}
  $sendto="$serverHost"; # Server
  $hash->{PORT}="80";
  $hash->{HTTPMETHOD}="POST";
  $cmd="setGroupName"; 
  
  my $countClientIp=$#clientListIP;
  my $countClientIp2=scalar(@clientListIP);
  
  Log3 $name, 4, "$hash->{TYPE} $name : Count Client IPs ".$countClientIp; 
  Log3 $name, 4, "$hash->{TYPE} $name : Count Client IPs2 ".$countClientIp2; 
  if ($countClientIp>0) {
    $groupName = $locationName." +".($countClientIp+1) ." Räume";
  }
  else {
    $groupName = $locationName." +".($countClientIp+1) ." Raum";
  }	
  %postdata_hash = ('name'=>$groupName);
  $json = encode_json \%postdata_hash;
  
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast Json Request ".$json;
  $hash->{POSTDATA} = $json;
  
  Log3 $name, 4, "$hash->{TYPE} $name : Link calling httpRequestDirect now cmd:$cmd, postdata:".$hash->{POSTDATA};
  
  YAMAHA_MC_httpRequestDirect($hash, $cmd, $sendto, @params); # call fn that will do the http request
  sleep 1;
  
  
  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast Ende ".$json;
  return undef;
}

########################################################################################
#
#  YAMAHA_MC_UnLink - Unlink Client and Server
#
#
########################################################################################
sub YAMAHA_MC_UnLink($$$@)
{
  my ($hash, $name, $cmd, @params) = @_;
#  $cmd = lc($cmd) if $cmd;

  # Parameters are all clients to be connected 
  my $plist ="";
  if((@params)){
     $plist = join(",",@params);
  }
  if ($plist eq "") {
  return "missing device name to link";
  }
  Log3 $name, 4, "$hash->{TYPE} $name : UNLink Musiccast Devices cmd:$cmd, params:".$plist;

  return if (IsDisabled $name);
  
  my $group_id = "";
  my $old_group_id = "d2d82d2b86434a35a35ad77c7ec0241c";
  my $sendto="";
  my $groupName = "";
  my %postdata_hash = "";
  my $json = "";
  my $serverHost = $hash->{HOST};
  my $serverZone = $hash->{ZONE};
  my $locationName = $hash->{location_name};
  
  Log3 $name, 4, "$hash->{TYPE} $name: UNLink Musiccast Devices server is $serverHost with locatioName $locationName";
  Log3 $name, 4, "$hash->{TYPE} $name: UNLink Musiccast Devices try getting ip of CLient=".$plist;
   
  my $clientName= $plist;
  my $clientIp = "";
  #my @clientListIP = ();
  
  #
  # unlinking all clients by deleting groupid
  #
  #1. set serverinfo {"group_id":""}   
  #2. set clientinfo {"group_id":""}  
  my @mc_clients = split(",", $clientName);
  foreach my $mc_client (@mc_clients) {
    Log3 $name, 4, "$hash->{TYPE} $name: UNLink Musiccast Devices mehr als 1 device ".$mc_client;
  
      $clientIp = "";
	  my $dev ="";
	  my $clienthash = $defs{$mc_client};
	  
      my $clientIp = $clienthash->{HOST};
	  my $clientType = $clienthash->{TYPE};
	  my $clientZone = $clienthash->{ZONE};
	  	  
	  Log3 $name, 4, "$hash->{TYPE} $name: UNLink Musiccast Devices server=$serverHost CLientName $mc_client  IP=$clientIp ClientZone=$clientZone Type=$clientType";
	  
	  # if device found with ip	and then send client signal to device
	  if (($clientIp ne "") && ($clientType eq "YAMAHA_MC") && ($clientIp ne $serverHost) )
	  {
	  #------------------------------------------------
	  #an Receiver -> als Client setzen
	  #post /YamahaExtendedControl/v1/dist/setClientInfo  
	  $group_id = "";   
		
	  Log3 $name, 4, "$hash->{TYPE} $name : UNLink Musiccast send setClientInfo";

	  $cmd="setClientInfo"; 
	  $sendto="$clientIp"; # Client  
		
	  %postdata_hash = ('group_id'=>$group_id,'zone'=>$clientZone);
	  $json = encode_json \%postdata_hash;
	  Log3 $name, 4, "$hash->{TYPE} $name : UnLink Musiccast send setClientInfo to $sendto Zone $clientZone Json Request ".$json;
	  $hash->{POSTDATA} = $json;  
		
	  YAMAHA_MC_httpRequestDirect($hash, $cmd, $sendto, @params); # call fn that will do the http request
	  
	  #------------------
      #
	  # now send the client list to server
	  # 
	  #------------------------------------------------  
	  #post /YamahaExtendedControl/v1/dist/setServerInfo
	  ##{"group_id":"d2d82d2b86434a35a35ad77c7ec0241c","type":"remove","zone":"main","client_list":["192.168.0.28"]}
	  
	  my $distype="remove";
	  my $zone=$serverZone;
	  
	  Log3 $name, 4, "$hash->{TYPE} $name : UnLink Musiccast send setServerInfo client_list= $clientIp";
	  
	  $cmd="setServerInfo"; 
	  $sendto="$serverHost"; # Server
	 
	  %postdata_hash = ('group_id'=>$old_group_id,'type'=>$distype,'zone'=>$zone,'client_list'=>$clientIp);
	  $json = encode_json \%postdata_hash;
	  
	  Log3 $name, 4, "$hash->{TYPE} $name : UnLink Musiccast send setServerInfo to $sendto Json Request ".$json;
	  $hash->{POSTDATA} = $json;  
		
	  YAMAHA_MC_httpRequestDirect($hash, $cmd, $sendto, @params); # call fn that will do the http request
	  #sleep 1;
	  
	  #---------------
	  
	  
				
	  #Log3 $name, 4, "$name : UNLink Musiccast adding $clientIp to ClientList";	
	  #here the delete from lsit is missing
	  #push @clientListIP, $clientIp;

     }  
  }
  
 	 
  #------------------------------------------------
  # delete group for Server 
  #post /YamahaExtendedControl/v1/dist/setServerInfo
  #
  # die Group darf nur geloescht werden, wenn alle Clients unlinkt sind
  # voher nur den Gruppen Namen des Servers reduzieren
  # fraglich ist, ob auch die Client List des Servers reduziert werden muss
  #
  Log3 $name, 4, "$hash->{TYPE} $name : UnLink Musiccast send setServerInfo ";
  
  $cmd="setServerInfo"; 
  $sendto="$serverHost"; # Server
 
  my $countUnlinkClients=scalar(@mc_clients);
  Log3 $name, 4, "$hash->{TYPE} $name : Count Clients to unlink ".$countUnlinkClients; 
  Log3 $name, 4, "$hash->{TYPE} $name : currently link group name $hash->{dist_group_name}"; 
  
  my $unlinkall=0;
   
  if (($hash->{dist_group_name} =~ /2 R/ ) && ($countUnlinkClients>1)) { #2Raeume sind gelinkt und es werden 2 unlinkt
    $unlinkall=1;	
	$hash->{dist_group_name} =~ s/ +2 Räume//g;
	$hash->{dist_group_name} =~ s/ +2 RÃ¤ume//g;	
  }
  elsif (($hash->{dist_group_name} =~ /2 R/ ) && ($countUnlinkClients=1)) { #2Raeume sind gelinkt und es wird 1 unlinkt
    $unlinkall=0;	
	$hash->{dist_group_name} =~ s/2 Räume/1 Raum/g;
	$hash->{dist_group_name} =~ s/2 RÃ¤ume/1 Raum/g;	
  }
  elsif ($hash->{dist_group_name} =~ /1 R/ ) { #1Raum ist gelinkt
    $unlinkall=1;
	$hash->{dist_group_name} =~ s/ +1 Raum//g;
  }	

  Log3 $name, 4, "$hash->{TYPE} $name : unlink all is set to $unlinkall new dist_group_name ".$hash->{dist_group_name};   
    

 if ($unlinkall==1) {
      %postdata_hash = ('group_id'=>"");
	  $json = encode_json \%postdata_hash;
	  
	  Log3 $name, 4, "$hash->{TYPE} $name : Link Musiccast send setServerInfo to unlink all $sendto Json Request ".$json;
	  $hash->{POSTDATA} = $json;  
 }
   
  YAMAHA_MC_httpRequestQueue($hash, "getDistributionInfo", "", {options => {priority => 3, unless_in_queue => 1}}); # call fn that will do the http request
  
  Log3 $name, 4, "$hash->{TYPE}: UnLink Musiccast Ende ".$json;
  return undef;
}

########################################################################################
#
#  YAMAHA_ReadFile - Read the content of the given filename
#
# Parameter $fileName = The filename, that has to be read
#
########################################################################################
sub YAMAHA_ReadFile($) {
	my ($fileName) = @_;

	if (-e $fileName) {
		my $fileContent = '';
		
		open IMGFILE, '<'.$fileName;
		binmode IMGFILE;
		while (<IMGFILE>){
			$fileContent .= $_;
		}
		close IMGFILE;
		
		return $fileContent;
	}
	
	return undef;
}

########################################################################################
#
#  YAMAHA_URI_Escape - Escapes the given string.
#
########################################################################################
sub YAMAHA_URI_Escape($) {
	my ($txt) = @_;
	
	eval {
		$txt = uri_escape($txt);
	};
	if ($@) {
		$txt = uri_escape_utf8($txt);
	};
	
	return $txt;
}


# command reference entry starts here...

=pod
=item device
=item summary    provides controling musiccast devices via LAN/WLAN connection
=begin html

<a name="YAMAHA_MC"></a>

<h3>YAMAHA_MC</h3>
<ul>
  <p>
    Provides control for YAMAHA_MC
  </p>
  <b>Notes</b>
  <ul>
    <li>Requirements: perl module <b>JSON</b> lately.
      There is reduced functionality if it is not installed, but the module
      will work with basic functions. Use "cpan install JSON" or operating
      system's package manager to install JSON Modul. Depending on your os
      the required package is named: libjson-perl or perl-JSON.
      </li><br>
  </ul>

  <br>
    This module controls musiccast devices from Yamaha via network connection. You are able
    to power your device on and off (=standby only), query it's power state,
    select the input (AirPlay, internet radio, Tuner, ...), select the volume
    or mute/unmute the volume.<br><br>
    Defining a YAMAHA_MC device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval_on&gt; and &lt;status_interval_off&gt; in seconds, if not set, the value is 60
    seconds), which periodically reads the status of the musiccast device (power state, selected
    input, volume and mute status) and triggers notify/filelog commands.
    <br><br>
    Different status update intervals depending on the power state can be given also. 
    If two intervals are given in the define statement, the first interval statement stands for the status update 
    interval in seconds in case the device is off, absent or any other non-normal state. The second 
    interval statement is used when the device is on.
	<br><br>
  <a name="YAMAHA_MCdefine"></a>
  <b>Define</b>
  <br><br>  

  <code>define &lt;name&gt; YAMAHA_MC &lt;ip_address|fqdn&gt; [&lt;port&gt;] [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
  </code>
  <br>

  <p><u>Mandatory:</u></p>
  <ul>
  <code>&lt;name&gt;</code>
  <ul>Specifies a device name of your choise.<br>
  eg. <code>WX030xx</code>
  </ul><br>
  <code>&lt;ip_address|fqdn&gt;</code>
  <ul>Specifies device IP address or hostname.<br>
    eg. <code>172.16.4.100</code><br>
    eg. <code>wx030.your.domain.net</code>
  </ul>
  </ul>

  <p><u>Mandatory</u></p>
  
  <code>&lt;port&gt;</code>
  <ul>Specifies your http port to be used. Default: 80<br>
  eg.<code> 88</code><br>
  </ul>
  
  <ul>
  <code>&lt;off_status_interval&gt;</code>
  Specifies time in seconds the status of the device is polled when it is turned off. Default: 60<br>
  eg.<code> 88</code><br>
  </ul>
  
 
  <code>&lt;on_status_interval&gt;</code>
  <ul>Specifies time in seconds the status of the device is polled when it is turned on. Default: 60<br>
  eg.<code> 88</code><br>
  </ul>


    <p><u>Define Examples:</u></p>
    <ul>      
      <li><code>define wx030 YAMAHA_MC 192.168.0.100 80 60 60</code></li>
    </ul>
<br>

<a name="YAMAHA_MC_set"></a>
  <b>Set </b>
  
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined; the available inputs are depending on the used device.
    The module only offers the real available inputs. The following input commands are just an example and can differ.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; set the device in standby, real shutdown not possible </li>
<li><b>power</b> on|standby &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device or sets it to standby</li>
<li><b>input</b> hdm1,hdmX,... &nbsp;&nbsp;-&nbsp;&nbsp; selects the input channel (only the real available inputs were given)</li>
<li><b>volume</b> 0...100 [direct] &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage. If you use "direct" as second argument, no volume smoothing is used (if activated) for this volume change. In this case, the volume will be set immediatly.</li>
<li><b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level by the value of attribute volumeSteps </li>
<li><b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level by the value of attribute volumeSteps </li>
<li><b>mute</b> on|off|toggle &nbsp;&nbsp;-&nbsp;&nbsp; activates volume mute</li>
<li><b>setSpeakerA</b> on|off|toggle &nbsp;&nbsp;-&nbsp;&nbsp; turns on/off speakers on A only possible if supported by device</li>
<li><b>setSpeakerB</b> on|off|toggle &nbsp;&nbsp;-&nbsp;&nbsp; turns on/off speakers on B only possible if supported by device</li>
<li><b>navigateListMenu</b> [item1]/[item2]/.../[itemN] &nbsp;&nbsp;-&nbsp;&nbsp; select a specific item within a menu structure. for menu-based inputs (e.g. Net Radio, USB, Server, ...) only. See chapter <a href="#YAMAHA_MC_MenuNavigation">Automatic Menu Navigation</a> for further details and examples.</li>
<li><b>sleep</b> off,30min,60min,...,last &nbsp;&nbsp;-&nbsp;&nbsp; activates the internal sleep timer</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause playback on current input</li>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playback on current input</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop playback on current input</li>
<li><b>skip</b> reverse,forward &nbsp;&nbsp;-&nbsp;&nbsp; skip track on current input</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
<li><b>getMenuItems</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current menu information and fills the menulist for selection in selectMenuItem</li>
<li><b>getMenu</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current menu information</li>
<li><b>selectMenu</b> &nbsp;&nbsp;-&nbsp;&nbsp; selects one menu item of the current menu by index, starts with 0</li>
<li><b>selectMenuItem</b> &nbsp;&nbsp;-&nbsp;&nbsp; selects one menu item of the current menu by current menu list items, use getMenuItems before</li>
<li><b>selectPlayMenu</b> &nbsp;&nbsp;-&nbsp;&nbsp; selects one menu item of the current menu to play by index, starts with 0</li>
<li><b>selectPlayMenuItem</b> &nbsp;&nbsp;-&nbsp;&nbsp; selects one menu item of the current menu to play by current menu list items, use getMenuItems before</li>
<li><b>returnMenu</b> &nbsp;&nbsp;-&nbsp;&nbsp; go back one level in current menu structure</li>
<li><b>TurnFavNetRadioChannelOn</b> &nbsp;&nbsp;-&nbsp;&nbsp; go to the menu defined by index in attribute pathToFavoritesNetRadio and play the favourite channel defined in FavoriteNetRadioChannel</li>
<li><b>NetRadioNextFavChannel</b> &nbsp;&nbsp;-&nbsp;&nbsp; go to the menu defined by index in attribute pathToFavoritesNetRadio and play the next channel in menu list</li>
<li><b>NetRadioPrevFavChannel</b> &nbsp;&nbsp;-&nbsp;&nbsp; go to the menu defined by index in attribute pathToFavoritesNetRadio and play the previous channel in menu list</li>
<li><b>getNetworkStatus</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current network info like network_name, wlan and wlan strength</li>
<li><b>getLocationInfo</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current location info like zones</li>
<li><b>getPlayInfo</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current playback info of the device like play status</li>
<li><b>getDeviceInfo</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current device info of the device like model_name, firmware, device_id</li>
<li><b>getFeatures</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the general status of the device, creates the possible inputs</li>
<li><b>getFuncStatus</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the general functions of the device, creates the possible speakers/headphone</li>
<li><b>getStatus</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the general status of the device, updates volume, current_input, mute tc.</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
</ul>
<br><br>
<a name="YAMAHA_MC_MenuNavigation"></a>
<u>Menu Navigation (only for menu based inputs like Net Radio, Server, USB, ...)</u><br><br>

For menu based inputs you have to select a specific item out of a complex menu structure to start playing music.
Mostly you want to start automatic playback for a specific internet radio (input: Net Radio) or similar, where you have to navigate through several menu and submenu items and at least play one item in the list items.
The exact menu structure depends on your own configuration and network devices who provide content. 
<br><br>
To ease such a complex menu navigation, you can use the following commands :
<br><br>1. "navigateListMenu". 
As Parameter you give the index in the current menu of the desired item you want to select - starting with index=0. 
so you need to know your menu sttructure, you could see this on yamaha musiccast app.
You may go through the menu and selects all menu items given as parameter from left to right. 
<br><br>

<br><br>2. "navigateListMenu". 
As Parameter you give the index in the current menu of the desired item you want to select - starting with index=0. 
so you need to know your menu sttructure, you could see this on yamaha musiccast app.
You may go through the menu and selects all menu items given as parameter from left to right. 
<br><br>


    
<br><br>
  <a name="YAMAHA_MC_get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code>
    <br><br>
    Currently, the get command only returns the reading values. For a specific list of possible values, see section "Generated Readings/Events".
    <br><br>
  </ul>
  <a name="YAMAHA_MC_attr"></a>
  <b>Attributes</b>
  <ul>
  
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="YAMAHA_MC_request-timeout">request-timeout</a></li>
    Optional attribute change the response timeout in seconds for all queries to the musiccast device.
    <br><br>
    Possible values: 1-5 seconds and 10 seconds. Default value is 4 seconds.<br><br>
    <li><a name="YAMAHA_MC_disable">disable</a></li>
    Optional attribute to disable the internal cyclic status update of the  musiccast device. Manual status updates via statusRequest command is still possible.
    <br><br>
    Possible values: 0 => perform cyclic status update, 1 => don't perform cyclic status updates.<br><br>
    <br><br>
	<li><a name="YAMAHA_MC_volume-steps">volumeSteps</a></li>
    Optional attribute to define the default increasing and decreasing level for the volumeUp and volumeDown set command. Default value is 3<br>
	<br><br>
	<li><a name="YAMAHA_MC_menuNameFavoritesNetRadio">menuNameFavoritesNetRadio</a></li>
    Optional attribute to set the name of netradio Menu where the personal favourite channels are stored. Is for faster setting channel up and down<br>
	<br><br>
	<li><a name="YAMAHA_MC_pathToFavoritesNetRadio">pathToFavoritesNetRadio</a></li>
    Neccessary attribute if you want to use set commands NetRadioNextFavChannel, NetRadioPrevFavChannel and TurnFavNetRadioChannelOn for personal favourite channels.<br>
	<br><br>
	<li><a name="YAMAHA_MC_FavoriteNetRadioChannel">FavoriteNetRadioChannel</a></li>
    Neccessary attribute if you want to use TurnFavNetRadioChannelOn. This is the channel number of your most favourite channel in your list of personal favourite channels. Starts with channel 0.<br>
	
	</ul>

  <br>
</ul>

=end html

=cut

1;