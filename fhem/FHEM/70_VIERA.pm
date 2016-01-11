# $Id$
##############################################################################
#
# 70_VIERA.pm
#
# a module to send messages or commands to a Panasonic TV
# inspired by Samsung TV Module from Gabriel Bentele <gabriel at bentele.de>
# written 2013 by Tobias Vaupel <fhem at 622 mbit dot de>
#
#
# Version = 1.24
#
# Version  History:
# - 1.24 - 2015-07-08
# -- Using non blocking as default for status update. Use attr to use blocking mode. 
# -- Replaced when/given with if/elsif
# -- Added color buttons for remoteControl Layout
# -- Added remoteControl Layout with SVG
# -- InternalTimer is deleted at define. Avoid multiple internalTimer running in parallel when redefining device
# -- Added TCP-Port to internal PORT instead of fixed coding
# -- increased byte length at command read (IO::Socket::INET) from 1 to 1024
# -- in very few cases the TV is answering with HTTP Code 400 BAD REQUEST. This is considered now and is interpreted as device on instead of off.
#
# - 1.23 - 2014-08-01
# -- Add parameter "HDMI1" - "HDMI4" for command remoteControl to select HDMI input directly
# -- Add command "input" to select a HDMI port, TV or SD-Card as source
#
# - 1.22 - 2013-12-28
# -- fixed set command remoteControl
#
# - 1.21 - 2013-08-19
# -- Log() deprecated/replaced by Log3()
# -- GetStatus() is called after set volume/mute to update readings immediately
#
# - 1.20 - 2013-08-16
# -- added support according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
#
# - 1.11 - 2013-08-13
# -- added "noArg" at get/set-command
# -- changed format of return() in VIERA_Get() for get-command drop down menu in FHEMWEB
#
# - 1.10 - 2013-06-29
# -- Added support for module 95_remotecontrol
# -- New functions: sub VIERA_RClayout_TV(); sub VIERA_RCmakenotify($$);
# -- Updated VIERA_Initialize for remotecontrol
#
# - 1.00 - 2013-03-16
# -- First release
#
##############################################################################

package main;
use strict;
use warnings;
use IO::Socket::INET;
use feature qw/say switch/;
use Time::HiRes qw(gettimeofday sleep);
use Blocking;


# Forward declaration for remotecontrol module
sub VIERA_RClayout_TV();
sub VIERA_RClayout_TV_SVG();
sub VIERA_RCmakenotify($$);


my %VIERA_remoteControl_args = (
  "NRC_CH_DOWN-ONOFF"   => "Channel down",
  "NRC_CH_UP-ONOFF"     => "Channel up",
  "NRC_VOLUP-ONOFF"     => "Volume up",
  "NRC_VOLDOWN-ONOFF"   => "Volume down",
  "NRC_MUTE-ONOFF"      => "Mute",
  "NRC_TV-ONOFF"        => "TV",
  "NRC_CHG_INPUT-ONOFF" => "AV",
  "NRC_RED-ONOFF"       => "Red",
  "NRC_GREEN-ONOFF"     => "Green",
  "NRC_YELLOW-ONOFF"    => "Yellow",
  "NRC_BLUE-ONOFF"      => "Blue",
  "NRC_VTOOLS-ONOFF"    => "VIERA tools",
  "NRC_CANCEL-ONOFF"    => "Cancel / Exit",
  "NRC_SUBMENU-ONOFF"   => "Option",
  "NRC_RETURN-ONOFF"    => "Return",
  "NRC_ENTER-ONOFF"     => "Control Center click / enter",
  "NRC_RIGHT-ONOFF"     => "Control RIGHT",
  "NRC_LEFT-ONOFF"      => "Control LEFT",
  "NRC_UP-ONOFF"        => "Control UP",
  "NRC_DOWN-ONOFF"      => "Control DOWN",
  "NRC_3D-ONOFF"        => "3D button",
  "NRC_SD_CARD-ONOFF"   => "SD-card",
  "NRC_DISP_MODE-ONOFF" => "Display mode / Aspect ratio",
  "NRC_MENU-ONOFF"      => "Menu",
  "NRC_INTERNET-ONOFF"  => "VIERA connect",
  "NRC_VIERA_LINK-ONOFF"=> "VIERA link",
  "NRC_EPG-ONOFF"       => "Guide / EPG",
  "NRC_TEXT-ONOFF"      => "Text / TTV",
  "NRC_STTL-ONOFF"      => "STTL / Subtitles",
  "NRC_INFO-ONOFF"      => "Info",
  "NRC_INDEX-ONOFF"     => "TTV index",
  "NRC_HOLD-ONOFF"      => "TTV hold / image freeze",
  "NRC_R_TUNE-ONOFF"    => "Last view",
  "NRC_POWER-ONOFF"     => "Power off",
  "NRC_REW-ONOFF"       => "Rewind",
  "NRC_PLAY-ONOFF"      => "Play",
  "NRC_FF-ONOFF"        => "Fast forward",
  "NRC_SKIP_PREV-ONOFF" => "Skip previous",
  "NRC_PAUSE-ONOFF"     => "Pause",
  "NRC_SKIP_NEXT-ONOFF" => "Skip next",
  "NRC_STOP-ONOFF"      => "Stop",
  "NRC_REC-ONOFF"       => "Record",
  "NRC_D1-ONOFF"        => "Digit 1",
  "NRC_D2-ONOFF"        => "Digit 2",
  "NRC_D3-ONOFF"        => "Digit 3",
  "NRC_D4-ONOFF"        => "Digit 4",
  "NRC_D5-ONOFF"        => "Digit 5",
  "NRC_D6-ONOFF"        => "Digit 6",
  "NRC_D7-ONOFF"        => "Digit 7",
  "NRC_D8-ONOFF"        => "Digit 8",
  "NRC_D9-ONOFF"        => "Digit 9",
  "NRC_D0-ONOFF"        => "Digit 0",
  "NRC_P_NR-ONOFF"      => "P-NR (Noise reduction)",
  "NRC_R_TUNE-ONOFF"    => "Seems to do the same as INFO",
  "NRC_HDMI1"           => "Switch to HDMI input 1",
  "NRC_HDMI2"           => "Switch to HDMI input 2",
  "NRC_HDMI3"           => "Switch to HDMI input 3",
  "NRC_HDMI4"           => "Switch to HDMI input 4",
);

# Initialize the module and tell FHEM name of additional functions
# Param1: Hash of FHEM-Device
# Return: no return code
sub VIERA_Initialize($){
  my ($hash) = @_;
  $hash->{DefFn}              = "VIERA_Define";
  $hash->{SetFn}              = "VIERA_Set";
  $hash->{GetFn}              = "VIERA_Get";
  $hash->{UndefFn}            = "VIERA_Undefine";
  $hash->{AttrList}           = "blocking:1,0 $readingFnAttributes";
  $data{RC_layout}{VIERA_TV}  = "VIERA_RClayout_TV";
  $data{RC_layout}{VIERA_TV_SVG}  = "VIERA_RClayout_TV_SVG";
  $data{RC_makenotify}{VIERA} = "VIERA_RCmakenotify";
}

# Callback when 'define' is used at FHEM
# Param1: Hash of FHEM-Device
# Param2: String of 'define' command
# Return: Help text for FHEMWEB
sub VIERA_Define($$){
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  
  if(int(@args) < 3 && int(@args) > 4) {
    my $msg = "wrong syntax: define <name> VIERA <host> [<interval>]";
    Log3 $name, 2, "VIERA: $msg";
    return $msg;
  }
  
  $hash->{helper}{HOST} = $args[2];
  $hash->{helper}{PORT} = 55000;
  
  if(defined($args[3]) and $args[3] > 10) {
    $hash->{helper}{INTERVAL}=$args[3];
  }
  else {
    $hash->{helper}{INTERVAL}=30;
  }

  CommandAttr(undef,$name.' webCmd off') if( !defined( AttrVal($hash->{NAME}, "webCmd", undef)) );
  
  BlockingKill($hash->{helper}{RUNNING_PID_GET}) if(defined($hash->{helper}{RUNNING_PID_GET}));
  delete($hash->{helper}{RUNNING_PID_GET});
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "VIERA_GetStatus", $hash, 0);
  
  Log3 $name, 2, "VIERA: defined with host: $hash->{helper}{HOST} and interval: $hash->{helper}{INTERVAL}";
  readingsSingleUpdate($hash,"state","Initialized",1);
  return undef;
}

# Callback when 'set' is used at FHEM
# Param1: Hash of FHEM-Device
# Param2: String of 'set' command
# Return: Help text for FHEMWEB
sub VIERA_Set($@){
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $host = $hash->{helper}{HOST};
  my $count = @a;
  my $key = "";
  my $tab = "";
  my $usage = "choose one of off:noArg mute:on,off " .
              "remoteControl:" . join(",", sort keys %VIERA_remoteControl_args) . " " .
              "volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg ".
              "channel channelUp:noArg channelDown:noArg input:hdmi1,hdmi2,hdmi3,hdmi4,sdCard,tv";
  $usage =~ s/(NRC_|-ONOFF)//g;
  
  my $what = lc($a[1]);
  return "VIERA: Device is not present or reachable, power on or check ethernet connection" if(ReadingsVal($name,"presence","absent")ne "present" && $what ne "?");
  return "VIERA: No argument given, $usage" if(!defined($a[1]));
  my $state = lc($a[2]) if(defined($a[2]));
  
  if ($what eq "mute"){
    Log3 $name, 3, "VIERA: Set mute $state";
    if ($state eq "on") {$state = 1;} else {$state = 0;}
    VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Set", "Mute", $state));
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "volume"){
    return "VIERA: Volume range is too high! Use Value 0 till 100 for volume." if($state < 0 || $state > 100);
    Log3 $name, 3, "VIERA: Set volume $state";
    VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Set", "Volume", $state));
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "volumeup"){
    return "VIERA: Volume range is too high!" if(ReadingsVal($name, "volume", "0") > 100);
    Log3 $name, 3, "VIERA: Set volumeUp";
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"VOLUP"));
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "volumedown"){
    return "VIERA: Volume range is too low!" if(ReadingsVal($name, "volume", "0") < 1);
    Log3 $name, 3, "VIERA: Set volumeDown";
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"VOLDOWN"));
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "channel"){
    return "VIERA: Channel is too high or low!" if($state < 1 || $state > 9999);
    Log3 $name, 3, "VIERA: Set channel $state";
    for(my $i = 0; $i <= length($state)-1; $i++) {
      VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"D" . substr($state, $i, 1)));
      sleep 0.1;
    }
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"ENTER"));
  } 
  elsif ($what eq "channelup"){
    Log3 $name, 3, "VIERA: Set channelUp";
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"CH_UP"));
  }
  elsif ($what eq "channeldown"){
    Log3 $name, 3, "VIERA: Set channelDown";
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"CH_DOWN"));
  }
  elsif ($what eq "remotecontrol"){
    if($state eq "?"){
    $usage = "choose one of the states:\n";
    foreach $key (sort keys %VIERA_remoteControl_args){
      if(length($key) < 17){ $tab = "\t\t"; }else{ $tab = "\t"; }
      $usage .= "$key $tab=> $VIERA_remoteControl_args{$key}\n";
    }
    $usage =~ s/(NRC_|-ONOFF)//g;
    return $usage;
    }
    else{
    $state = uc($state);
    Log3 $name, 3, "VIERA: Set remoteControl $state";   
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,$state));
    }
  }
  elsif ($what eq "off"){
    Log3 $name, 3, "VIERA: Set off";   
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,"POWER"));
  }
  elsif ($what eq "statusrequest"){
    Log3 $name, 3, "VIERA: Set statusRequest";
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "input"){
    $state = uc($state);
    return "VIERA: Input $state isn't available." if($state ne "HDMI1" && $state ne "HDMI2" && $state ne "HDMI3" && $state ne "HDMI4" && $state ne "SDCARD" && $state ne "TV");
    $state = "SD_CARD" if ($state eq "SDCARD");
    Log3 $name, 3, "VIERA: Set input $state";
    VIERA_connection($hash, VIERA_BuildXML_NetCtrl($hash,$state));
  }
  elsif ($what eq "?"){
    return "$usage";
  }
  else {
    Log3 $name, 3, "VIERA: Unknown argument $what, $usage";
    return "Unknown argument $what, $usage";
  }
  return undef;
}

# Callback when 'get' is used at FHEM
# Param1: Hash of FHEM-Device
# Param2: String of 'set' command
# Return: Help text for FHEMWEB
sub VIERA_Get($@){
  my ($hash, @a) = @_;
  my $what;
  my $usage = "choose one of mute:noArg volume:noArg power:noArg presence:noArg";
  my $name = $hash->{NAME};

  return "VIERA: No argument given, $usage" if(int(@a) != 2);

  $what = lc($a[1]);

  if($what =~ /^(volume|mute|power|presence)$/) {
    if (defined($hash->{READINGS}{$what})) {
      ReadingsVal($name, $what, "undefined");
    }
    else{
      return "no such reading: $what";
    }
  }
  else{
    return "Unknown argument $what, $usage";
  }
}

# Callback when 'delete' is used at FHEM or FHEM is restarting/shutdown
# Param1: Hash of FHEM-Device
# Param2: Name of FHEM-Device
# Return: undef
sub VIERA_Undefine($$){
  my($hash, $name) = @_;
  
  # Stop the internal GetStatus-Loop and exist
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID_GET}) if(defined($hash->{helper}{RUNNING_PID_GET}));
  
  return undef;
}

# Function is called periodically by InternalTimer and fetch informations from device. The decision if blocking or nonBlocking is used is made here.
# Param1: Hash of FHEM-Device
# Param2: Optional, if set to 1 fetch information from device without interrupting InternalTimer
sub VIERA_GetStatus($;$){
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $host = $hash->{helper}{HOST};
  my $blocking = AttrVal($name, "blocking", 0);		#use non-blocking in standard. Just use blocking when set by attr
  
  #if $local is set to 1 just fetch informations from device without interrupting InternalTimer
  $local = 0 unless(defined($local));
  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "VIERA_GetStatus", $hash, 0) unless($local == 1);
  
  return "" if(!defined($hash->{helper}{HOST}) or !defined($hash->{helper}{INTERVAL}));

  if ($blocking == 0) {
    Log3 $name, 4, "VIERA[VIERA_GetStatus]: Using non blocking...";
    $hash->{helper}{RUNNING_PID_GET} = BlockingCall("VIERA_GetDoIt", $hash, "VIERA_GetDone", 10, "VIERA_GetAbortFn", $hash) unless(exists($hash->{helper}{RUNNING_PID_GET}));
    if($hash->{helper}{RUNNING_PID_GET}) { 
      Log3 $name, 4, "VIERA[VIERA_GetStatus]: VIERA_GetDoIt() BlockingCall process started with PID $hash->{helper}{RUNNING_PID_GET}{pid}"; 
    }
    else { 
      Log3 $name, 3,  "VIERA[VIERA_GetStatus]: BlockingCall process start failed for VIERA_GetDoIt()"; 
    }
    return;
  }
  Log3 $name, 4, "VIERA[VIERA_GetStatus]: Using blocking...";
  my $returnVol = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Volume", ""));
  Log3 $name, 5, "VIERA[VIERA_GetStatus]: Vol-Request returned: $returnVol" if(defined($returnVol));
  if(not defined($returnVol) or $returnVol eq "") {
    Log3 $name, 4, "VIERA[VIERA_GetStatus]: Vol-Request NO SOCKET!";
    if( ReadingsVal($name,"state","absent") ne "absent") {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "absent");
      readingsBulkUpdate($hash, "power", "off");
      readingsBulkUpdate($hash, "presence", "absent");
      readingsEndUpdate($hash, 1);
    }
    return;
  }

  my $returnMute = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Mute", ""));
  Log3 $name, 5, "VIERA[VIERA_GetStatus]: Mute-Request returned: $returnMute" if(defined($returnMute));
  if(not defined($returnMute) or $returnMute eq "") {
    Log3 $name, 4, "VIERA[VIERA_GetStatus]: Mute-Request NO SOCKET!";
    if( ReadingsVal($name,"state","absent") ne "absent") {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "absent");
      readingsBulkUpdate($hash, "power", "off");
      readingsBulkUpdate($hash, "presence", "absent");
      readingsEndUpdate($hash, 1);
    }
    return;
  }
  
  readingsBeginUpdate($hash);
  if($returnVol =~ /<CurrentVolume>(.+)<\/CurrentVolume>/){
    Log3 $name, 4, "VIERA[VIERA_GetStatus]: Set reading volume to $1";
    if( $1 != ReadingsVal($name, "volume", "0") ) {readingsBulkUpdate($hash, "volume", $1);}
  }
  
  if($returnMute =~ /<CurrentMute>(.+)<\/CurrentMute>/){
    my $myMute = $1;
    if ($myMute == 0) { $myMute = "off"; } else { $myMute = "on";}
    Log3 $name, 4, "VIERA[VIERA_GetStatus]: Set reading mute to $myMute";
    if( $myMute ne ReadingsVal($name, "mute", "0") ) {readingsBulkUpdate($hash, "mute", $myMute);}
  }
  if( ReadingsVal($name,"state","absent") ne "on") {
    readingsBulkUpdate($hash, "state", "on");
    readingsBulkUpdate($hash, "power", "on");
    readingsBulkUpdate($hash, "presence", "present");
  }
  readingsEndUpdate($hash, 1);
  
  return $hash->{STATE};
}

# To sent RAW-Data as TCP Client to device
# param1: Hash of FHEM-Device
# param2: RAW Data
#return: RAW answer when successful or undef if no socket is available.
sub VIERA_connection($$){
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};
  my $buffer = "";
  my $buff = "";
  my $blocking = "NonBlocking-VIERA_connection()" if (AttrVal($name, "blocking", 0) == 0);
  $blocking = "Blocking-VIERA_connection()" if (AttrVal($name, "blocking", 0) == 1);

  my $sock = new IO::Socket::INET (
    PeerAddr => $hash->{helper}{HOST},
    PeerPort => $hash->{helper}{PORT},
    Proto => 'tcp',
    Timeout => 2
  );

  if(defined ($sock)) {
    Log3 $hash, 5, "VIERA[$blocking]: Send Data to $hash->{helper}{HOST}:$hash->{helper}{PORT}:\n$data";
    print $sock $data;
  
    while ((read $sock, $buff, 1024) > 0){
      $buffer .= $buff;
    }
 
    Log3 $hash, 5, "VIERA[$blocking]: $hash->{helper}{HOST} buffer response:\n$buffer";
    $sock->close();
    return $buffer;
  }
  else {
    Log3 $hash, 4, "VIERA[$blocking]: $hash->{helper}{HOST}: not able to open socket";
    return undef;
  }
}

# Callback from 95_remotecontrol for command makenotify.
# Param1: Name of remoteControl device
# Param2: Name of target FHEM device
sub VIERA_RCmakenotify($$) {
  my ($nam, $ndev) = @_;
  my $nname="notify_$nam";
  
  fhem("define $nname notify $nam set $ndev remoteControl ".'$EVENT',1);
  Log3 undef, 2, "[remoteControl:VIERA] Notify created: $nname";
  return "Notify created by VIERA: $nname";
}

# Callback from 95_remotecontrol for command layout. Creates non svg layout
sub VIERA_RClayout_TV() {
  my @row;
  my $i = 0;

  $row[$i++]="power:POWEROFF2,  TV,                 CHG_INPUT:HDMI";
  $row[$i++]="MENU,             disp_mode:ASPECT,   epg:GUIDE";
  $row[$i++]="VIERA_LINK,       VTOOLS,             INTERNET";
  $row[$i++]=":blank,           :blank,             :blank";
  $row[$i++]="INFO:INFO2,       UP,                 cancel:EXIT";
  $row[$i++]="LEFT,             ENTER,              RIGHT";
  $row[$i++]="SUBMENU,          DOWN,               RETURN";
  $row[$i++]="red:RED,          :blank,             green:GREEN";
  $row[$i++]="yellow:YELLOW,    :blank,             blue:BLUE";
  $row[$i++]="d1:1,             d2:2,               d3:3";
  $row[$i++]="d4:4,             d5:5,               d6:6";
  $row[$i++]="d7:7,             d8:8,               d9:9";
  $row[$i++]="MUTE,             d0:0,               r_tune:PRECH";
  $row[$i++]=":blank,           :blank,             :blank";
  $row[$i++]="VOLUP,            :blank,             ch_up:CHUP";
  $row[$i++]=":VOL,             :blank,             :PROG";
  $row[$i++]="VOLDOWN,          :blank,             ch_down:CHDOWN";
  $row[$i++]=":blank,           :blank,             :blank";
  $row[$i++]="rew:REWIND,       PLAY,               FF";
  $row[$i++]="STOP,             PAUSE,              REC";

  #Replace two or more spaces with one space
  for (@row) {s/\s+/ /g}
  
  $row[$i++]="attr rc_iconpath icons/remotecontrol";
  $row[$i++]="attr rc_iconprefix black_btn_";

  return @row;
}

# Callback from 95_remotecontrol for command layout. Creates svg layout
sub VIERA_RClayout_TV_SVG() {
  my @row;
  my $i = 0;
  
  $row[$i++]="power:rc_POWER.svg,             TV:rc_TV2.svg,              CHG_INPUT:rc_AV.svg";
  $row[$i++]="MENU:rc_MENU.svg,               disp_mode:rc_ASPECT.svg,    epg:rc_EPG.svg";
  $row[$i++]="VIERA_LINK:rc_VIERA_LINK.svg,   VTOOLS:rc_VIERA_TOOLS.svg,  INTERNET:rc_WEB.svg";
  $row[$i++]=":rc_BLANK.svg,                  :rc_BLANK.svg,              :rc_BLANK.svg";
  $row[$i++]="INFO:rc_INFO2.svg,              UP:rc_UP.svg,               cancel:rc_EXIT.svg";
  $row[$i++]="LEFT:rc_LEFT.svg,               ENTER:rc_dot.svg,           RIGHT:rc_RIGHT.svg";
  $row[$i++]="SUBMENU:rc_OPTIONS.svg,         DOWN:rc_DOWN.svg,           RETURN:rc_BACK.svg";
  $row[$i++]="red:rc_RED.svg,                 :rc_BLANK.svg,              green:rc_GREEN.svg";
  $row[$i++]="yellow:rc_YELLOW.svg,           :rc_BLANK.svg,              blue:rc_BLUE.svg";
  $row[$i++]="d1:rc_1.svg,                    d2:rc_2.svg,                d3:rc_3.svg";
  $row[$i++]="d4:rc_4.svg,                    d5:rc_5.svg,                d6:rc_6.svg";
  $row[$i++]="d7:rc_7.svg,                    d8:rc_8.svg,                d9:rc_9.svg";
  $row[$i++]="MUTE:rc_MUTE.svg,               d0:rc_0.svg,                r_tune:rc_BACK.svg";
  $row[$i++]=":rc_BLANK.svg,                  :rc_BLANK.svg,              :rc_BLANK.svg";
  $row[$i++]="VOLUP:rc_UP.svg,                :rc_BLANK.svg,              ch_up:rc_UP.svg";
  $row[$i++]=":rc_VOL.svg,                    :rc_BLANK.svg,              :rc_PROG.svg";
  $row[$i++]="VOLDOWN:rc_DOWN.svg,            :rc_BLANK.svg,              ch_down:rc_DOWN.svg";
  $row[$i++]=":rc_BLANK.svg,                  :rc_BLANK.svg,              :rc_BLANK.svg";
  $row[$i++]="rew:rc_REW.svg,                 PLAY:rc_PLAY.svg,           FF:rc_FF.svg";
  $row[$i++]="STOP:rc_STOP.svg,               PAUSE:rc_PAUSE.svg,         REC:rc_REC.svg";

  #Replace two or more spaces with one space
  for (@row) {s/\s+/ /g}
  return @row;
}

# Create RAW Data to sent pressed keys of remoteControl to device.
# Param1: Hash of FHEM-Device
# Param2: Name of key to send
# Return: RAW html request for xml soap
sub VIERA_BuildXML_NetCtrl($$){
  my ($hash, $command) = @_;
  my $host = $hash->{helper}{HOST};
  my $port = $hash->{helper}{PORT};
  
  my $callsoap = "";
  my $message = "";
  my $head = "";
  my $size = "";
  
  $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>";
  $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">";
  $callsoap .= "<s:Body>";
  $callsoap .= "<u:X_SendKey xmlns:u=\"urn:panasonic-com:service:p00NetworkControl:1\">";
  $callsoap .= "<X_KeyEvent>NRC_$command-ONOFF</X_KeyEvent>";
  $callsoap .= "</u:X_SendKey>";
  $callsoap .= "</s:Body>";
  $callsoap .= "</s:Envelope>";

  $size = length($callsoap);

  $head .= "POST /nrc/control_0 HTTP/1.1\r\n";
  $head .= "Host: $host:$port\r\n";
  $head .= "SOAPACTION: \"urn:panasonic-com:service:p00NetworkControl:1#X_SendKey\"\r\n";
  $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
  $head .= "Content-Length: $size\r\n";
  $head .= "\r\n";

  $message .= $head;
  $message .= $callsoap;
  #Log3 $hash, 5, "VIERA: Building XML SOAP (NetworkControl) for command $command to host $host:\n$message";
  return $message;
}

# Create RAW Data to send or get volume/mute state
# Param1: Hash of FHEM-Device
# Param2: get|set 
# Param3: volume|mute
# Param4: value for set command
# Return: RAW html request for xml soap
sub VIERA_BuildXML_RendCtrl($$$$){
  my ($hash, $methode, $command, $value) = @_;
  my $host = $hash->{helper}{HOST};
  my $port = $hash->{helper}{PORT};
  
  my $callsoap = "";
  my $message = "";
  my $head = "";
  my $size = "";
  
  #Log3 $hash, 5, "VIERA: $command with $value to $host";

  $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
  $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">\r\n";
  $callsoap .= "<s:Body>\r\n";
  $callsoap .= "<u:$methode$command xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">\r\n";
  $callsoap .= "<InstanceID>0</InstanceID>\r\n";
  $callsoap .= "<Channel>Master</Channel>\r\n";
  $callsoap .= "<Desired$command>$value</Desired$command>\r\n" if(defined($value));
  $callsoap .= "</u:$methode$command>\r\n";
  $callsoap .= "</s:Body>\r\n";
  $callsoap .= "</s:Envelope>\r\n";

  $size = length($callsoap);

  $head .= "POST /dmr/control_0 HTTP/1.0\r\n";
  $head .= "Host: $host:$port\r\n";
  $head .= "SOAPACTION: \"urn:schemas-upnp-org:service:RenderingControl:1#$methode$command\"\r\n";
  $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
  $head .= "Content-Length: $size\r\n";
  $head .= "\r\n";

  $message .= $head;
  $message .= $callsoap;
  #Log3 $hash, 5, "VIERA: Building XML SOAP (RenderingControl) for command $command with value $value to host $host:\n$message";
  return $message;
}

# Get volume and mute state from device. This function is called non blocking!
# Param1: Hash of FHEM-Device
# Return: <name of fhem-device>|<volume level>|<mute state>
sub VIERA_GetDoIt($) {
  my ($hash) = @_;
  my $myVol = "";
  my $myMute = "";
  
  Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: BlockingCall for ".$hash->{NAME}." start...";
  
  my $returnVol = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Volume", ""));
  Log3 $hash, 5, "VIERA[NonBlocking-VIERA_GetDoIt()]: GetStatusVol-Request returned: $returnVol" if(defined($returnVol));
  if(not defined($returnVol) or $returnVol eq "") {
    Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: GetStatusVol-Request NO SOCKET!";
    
    return $hash->{NAME}. "|". 
    "error-noSocket" . "|".
    "error-noSocket";
  }

  my $returnMute = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Mute", ""));
  Log3 $hash, 5, "VIERA[NonBlocking-VIERA_GetDoIt()]: GetStatusMute-Request returned: $returnMute" if(defined($returnMute));
  if(not defined($returnMute) or $returnMute eq "") {
    Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: GetStatusMute-Request NO SOCKET!";
    
    return $hash->{NAME}. "|". 
    "error-noSocket" . "|".
    "error-noSocket";
  }
  
  if ($returnVol =~ /HTTP\/1\.1 ([\d]{3}) (.*)/) {
    Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: Received HTTP Code $1 $2";
    $myVol = "error-$1 $2" if ($1 ne "200");
  }
  if($returnVol =~ /<CurrentVolume>(.+)<\/CurrentVolume>/){
  $myVol = $1;
  Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: Received volume with level $myVol";
  }
  
  if ($returnMute =~ /HTTP\/1\.1 ([\d]{3}) (.*)/) {
    Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: Received HTTP Code $1 $2";
    $myMute = "error-$1 $2" if ($1 ne "200");
  }
  if($returnMute =~ /<CurrentMute>(.+)<\/CurrentMute>/){
    $myMute = $1;
    if ($myMute == 0) { $myMute = "off"; } else { $myMute = "on";}
    Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDoIt()]: Received mute state $myMute";
  }
  
    return $hash->{NAME}. "|". 
    "$myVol" . "|".
    "$myMute";
}

# Callback of non blocking function VIERA_GetDoIt. Parse the results and set readings at fhem-device
# Param1: <name of fhem-device>|<volume level>|<mute state>
#       volume level = 0 - 100
#       mute state = 1 or 0
# If no socket is available Par1 and Par2 contains "error"
# Return: no return code
####################################################
sub VIERA_GetDone($) {
  my ($string) = @_;
  return unless(defined($string));
  
  my @a = split("\\|",$string);
  my $name = shift(@a);
  my $myVol = shift(@a);
  my $myMute = shift(@a);
  my $hash = $defs{$name};
  
  Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDone()]: Param: $string";
  
  if ($myVol =~ /error-(.*)/ || $myMute =~ /error-(.*)/) {
    if ($1 eq "noSocket") {
      Log3 $name, 4, "VIERA[NonBlocking-VIERA_GetDone()]: Seems to be there is no socket available. Guessing TV is off!";
      if (ReadingsVal($name,"state","absent") ne "absent") {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "state", "absent");
        readingsBulkUpdate($hash, "power", "off");
        readingsBulkUpdate($hash, "presence", "absent");
        readingsEndUpdate($hash, 1);
      }
      delete($hash->{helper}{RUNNING_PID_GET});
      return;
    }
    else {
      Log3 $name, 3, "VIERA[NonBlocking-VIERA_GetDone()]: TV answered with $1. Seems to be on but delivering no data";
      return;
    }
  }
  
  readingsBeginUpdate($hash);
  if ($myVol != ReadingsVal($name, "volume", "0")) {
    Log3 $hash, 4, "VIERA[NonBlocking-VIERA_GetDone()]: Set reading volume to $myVol";
    readingsBulkUpdate($hash, "volume", $myVol);
  } 
  
  if ($myMute ne ReadingsVal($name, "mute", "0")) {
    Log3 $name, 4, "VIERA[NonBlocking-VIERA_GetDone()]: Set reading mute to $myMute";  
    readingsBulkUpdate($hash, "mute", $myMute);
  }
  
  if (ReadingsVal($name,"state","absent") ne "on") {
    readingsBulkUpdate($hash, "state", "on");
    readingsBulkUpdate($hash, "power", "on");
    readingsBulkUpdate($hash, "presence", "present");
  }
  readingsEndUpdate($hash, 1);
  
  delete($hash->{helper}{RUNNING_PID_GET});
}

# Callback of non blocking when function VIERA_GetDoIt runs into timeout.
# Param1: Hash of FHEM-Device
# Return: no return code
sub VIERA_GetAbortFn($)     { 
  my ($hash) = @_;

  delete($hash->{helper}{RUNNING_PID_GET});
  Log3 $hash, 2, "VIERA[NonBlocking-VIERA_GetAbortFn()]: BlockingCall for $hash->{NAME} was aborted, timeout reached";
}

1;

=pod
=begin html

<a name="VIERA"></a>
<h3>VIERA</h3>
<ul>  
  <a name="VIERAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; VIERA &lt;host&gt; [&lt;interval&gt;]</code>
    <br><br>
    This module controls Panasonic TV device over ethernet. It's possible to
    power down the tv, change volume or mute/unmute the TV. Also this modul is simulating
    the remote control and you are able to send different command buttons actions of remote control.
    The module is tested with Panasonic plasma TV tx-p50vt30e
    <br><br>
    Defining a VIERA device will schedule an internal task (interval can be set
    with optional parameter &lt;interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of volume and mute status and triggers
    notify/filelog commands.
    <br><br>
    <b>Notes:</b><br>
    <ul>Activate volume remotecontrol by DLNA: Menu -> Setup -> Network Setup -> Network Link Settings -> DLNA RemoteVolume -> On</ul>
    <br>
    Example:
    <ul><code>
      define myTV1 VIERA 192.168.178.20<br><br>
      define myTV1 VIERA 192.168.178.20 60   #with custom interval of 60 seconds
    </code></ul>
  </ul>

  <br>
  <a name="VIERAset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;value&gt;]</code>
    <br><br>
    Currently, the following commands are defined.
    <ul>
      <code>
        off<br>
        mute [on|off]<br>
        volume [0-100]<br>
        volumeUp<br>
        volumeDown<br>
        channel [1-9999]<br>
        channelUp<br>
        channelDown<br>
        statusRequest<br>
        remoteControl &lt;command&gt;<br>
        input [hdmi1|hdmi2|hdmi3|hdmi4|sdCard|tv]<br>
      </code>
    </ul>
  </ul>
  <ul>
    <br>
    <u>Remote control (depending on your model, maybe)</u><br>
    For this application the following commands are available:<br>
    <ul><code>
      3D 		=> 3D button<br>
      BLUE 		=> Blue<br>
      CANCEL 		=> Cancel / Exit<br>
      CHG_INPUT 	=> AV<br>
      CH_DOWN 	=> Channel down<br>
      CH_UP 		=> Channel up<br>
      D0 		=> Digit 0<br>
      D1 		=> Digit 1<br>
      D2 		=> Digit 2<br>
      D3 		=> Digit 3<br>
      D4 		=> Digit 4<br>
      D5 		=> Digit 5<br>
      D6 		=> Digit 6<br>
      D7 		=> Digit 7<br>
      D8 		=> Digit 8<br>
      D9 		=> Digit 9<br>
      DISP_MODE 	=> Display mode / Aspect ratio<br>
      DOWN 		=> Control DOWN<br>
      ENTER 		=> Control Center click / enter<br>
      EPG 		=> Guide / EPG<br>
      FF 		=> Fast forward<br>
      GREEN 		=> Green<br>
      HOLD 		=> TTV hold / image freeze<br>
      INDEX 		=> TTV index<br>
      INFO 		=> Info<br>
      INTERNET 	=> VIERA connect<br>
      LEFT 		=> Control LEFT<br>
      MENU 		=> Menu<br>
      MUTE 		=> Mute<br>
      PAUSE 		=> Pause<br>
      PLAY 		=> Play<br>
      POWER 		=> Power off<br>
      P_NR 		=> P-NR (Noise reduction)<br>
      REC 		=> Record<br>
      RED 		=> Red<br>
      RETURN 		=> Return<br>
      REW 		=> Rewind<br>
      RIGHT 		=> Control RIGHT<br>
      R_TUNE 		=> Seems to do the same as INFO<br>
      SD_CARD 	=> SD-card<br>
      SKIP_NEXT 	=> Skip next<br>
      SKIP_PREV 	=> Skip previous<br>
      STOP 		=> Stop<br>
      STTL 		=> STTL / Subtitles<br>
      SUBMENU 	=> Option<br>
      TEXT 		=> Text / TTV<br>
      TV 		=> TV<br>
      UP 		=> Control UP<br>
      VIERA_LINK 	=> VIERA link<br>
      VOLDOWN 	=> Volume down<br>
      VOLUP 		=> Volume up<br>
      VTOOLS 		=> VIERA tools<br>
      YELLOW 		=> Yellow<br>
    </code></ul>
    
    <br>
    Example:<br>
    <ul><code>
      set &lt;name&gt; mute on<br>
      set &lt;name&gt; volume 20<br>
      set &lt;name&gt; remoteControl CH_DOWN<br>
    </code></ul> 
  </ul>

  <br>
  <a name="VIERAget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br><br>
    Currently, the following commands are defined and return the current state of the TV.
    <ul><code>
      mute<br>
      volume<br>
      power<br>
      presence<br>
    </code></ul>
  </ul>
  
  <br>
  <a name="VIERAattr"></a>
  <b>Attributes</b>
  <ul>blocking [0|1]</ul>
  
  <br>
  <a name="VIERAevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>volume</li>
    <li>mute</li>
    <li>presence</li>
    <li>power</li>
    <li>state</li>
  </ul>
</ul>

=end html


=begin html_DE

<a name="VIERA"></a>
<h3>VIERA</h3>
<ul>  
  <a name="VIERAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; VIERA &lt;host&gt; [&lt;interval&gt;]</code>
    <br><br>
    Dieses Modul steuert einen Panasonic Fernseher &uuml;ber das Netzwerk. Es ist m&ouml;glich den Fernseher
    auszuschalten, die Lautst&auml;rke zu &auml;ndern oder zu muten bzw. unmuten. Dieses Modul kann zus&auml;tzlich
    die Fernbedienung simulieren. Somit k&ouml;nnen also die Schaltaktionen einer Fernbedienung simuliert werden.
    Getestet wurde das Modul mit einem Panasonic Plasma TV tx-p50vt30e
    <br><br>
    Beim definieren des Ger&auml;tes in FHEM wird ein interner Timer gestartet, welcher zyklisch alle 30 Sekunden
    den Status der Lautst&auml;rke und des Mute-Zustand ausliest. Das Intervall des Timer kann &uuml;ber den Parameter &lt;interval&gt;
    ge&auml;ndert werden. Wird kein Interval angegeben, liest das Modul alle 30 Sekunden die Werte aus und triggert ein notify.
    <br><br>
    <b>Anmerkung:</b><br>
    <ul>Aktivieren von Fernbedienung der Lautst&auml;rke per DLNA: Men&uuml; -> Setup -> Netzwerk-Setup -> Netzwerkverbindungsein. -> DLNA-Fernbed. Lautst. -> Ein</ul>
    <br>
    Beispiel:
    <ul><code>
      define myTV1 VIERA 192.168.178.20<br><br>
      define myTV1 VIERA 192.168.178.20 60   #Mit einem Interval von 60 Sekunden
    </code></ul>
  </ul>
  
  <br>
  <a name="VIERAset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;value&gt;]</code>
    <br><br>
    Zur Zeit sind die folgenden Befehle implementiert:
    <ul><code>
      off<br>
      mute [on|off]<br>
      volume [0-100]<br>
      volumeUp<br>
      volumeDown<br>
      channel [1-9999]<br>
      channelUp<br>
      channelDown<br>
      statusRequest<br>
      remoteControl &lt;command&gt;<br>
      input [hdmi1|hdmi2|hdmi3|hdmi4|sdCard|tv]<br>
    </code></ul>
  </ul>
  <ul>
  <br>
  <u>Fernbedienung (Kann vielleicht nach Modell variieren)</u><br>
    Das Modul hat die folgenden Fernbedienbefehle implementiert:<br>
    <ul><code>
      3D 		=> 3D Knopf<br>
      BLUE 		=> Blau<br>
      CANCEL 		=> Cancel / Exit<br>
      CHG_INPUT 	=> AV<br>
      CH_DOWN 	=> Kanal runter<br>
      CH_UP 		=> Kanal hoch<br>
      D0 		=> Ziffer 0<br>
      D1 		=> Ziffer 1<br>
      D2 		=> Ziffer 2<br>
      D3 		=> Ziffer 3<br>
      D4 		=> Ziffer 4<br>
      D5 		=> Ziffer 5<br>
      D6 		=> Ziffer 6<br>
      D7 		=> Ziffer 7<br>
      D8 		=> Ziffer 8<br>
      D9 		=> Ziffer 9<br>
      DISP_MODE 	=> Anzeigemodus / Seitenverh&auml;ltnis<br>
      DOWN 		=> Navigieren runter<br>
      ENTER 		=> Navigieren enter<br>
      EPG 		=> Guide / EPG<br>
      FF 		=> Vorspulen<br>
      GREEN 		=> Gr&uuml;n<br>
      HOLD 		=> Bild einfrieren<br>
      INDEX 		=> TTV index<br>
      INFO 		=> Info<br>
      INTERNET 	=> VIERA connect<br>
      LEFT 		=> Navigieren links<br>
      MENU 		=> Men&uuml;<br>
      MUTE 		=> Mute<br>
      PAUSE 		=> Pause<br>
      PLAY 		=> Play<br>
      POWER 		=> Power off<br>
      P_NR 		=> P-NR (Ger&auml;uschreduzierung)<br>
      REC 		=> Aufnehmen<br>
      RED 		=> Rot<br>
      RETURN 		=> Enter<br>
      REW 		=> Zur&uuml;ckspulen<br>
      RIGHT 		=> Navigieren Rechts<br>
      R_TUNE 		=> Vermutlich die selbe Funktion wie INFO<br>
      SD_CARD 	=> SD-card<br>
      SKIP_NEXT 	=> Skip next<br>
      SKIP_PREV 	=> Skip previous<br>
      STOP 		=> Stop<br>
      STTL 		=> Untertitel<br>
      SUBMENU 	=> Option<br>
      TEXT 		=> TeleText<br>
      TV 		=> TV<br>
      UP 		=> Navigieren Hoch<br>
      VIERA_LINK 	=> VIERA link<br>
      VOLDOWN 	=> Lauter<br>
      VOLUP 		=> Leiser<br>
      VTOOLS 		=> VIERA tools<br>
      YELLOW 		=> Gelb<br>
    </code></ul>
    
    <br>
    Beispiel:<br>
    <ul><code>
      set &lt;name&gt; mute on<br>
      set &lt;name&gt; volume 20<br>
      set &lt;name&gt; remoteControl CH_DOWN<br>
    </code></ul>
  </ul>
  
  <br>
  <a name="VIERAget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br><br>
    Die folgenden Befehle sind definiert und geben den entsprechenden Wert zur&uuml;ck, der vom Fernseher zur&uuml;ckgegeben wurde.
  <ul><code>
      mute<br>
      volume<br>
      power<br>
      presence<br>
  </code></ul>
  </ul>
  
  <br>
  <a name="VIERAattr"></a>
  <b>Attribute</b>
  <ul>blocking [0|1]</ul>
  
  <br>
  <a name="VIERAevents"></a>
  <b>Generierte events:</b>
  <ul>
    <li>volume</li>
    <li>mute</li>
    <li>presence</li>
    <li>power</li>
    <li>state</li>
  </ul>
</ul>

=end html_DE



=cut
