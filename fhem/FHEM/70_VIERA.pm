# $Id$
##############################################################################
#
# 70_VIERA.pm
#
# a module to send messages or commands to a Panasonic TV
# inspired by Samsung TV Module from Gabriel Bentele <gabriel at bentele.de>
# written 2013 by Tobias Vaupel <fhem at 622 mbit dot de>
# since version 1.25 modified by mabula
#
#
# Version = 1.31
#
# Version  History:
# - 1.31 - 2020-01-15 Dr. H-J Breymayer
# -- new command display web page on TV
#
# - 1.30 - 2020-01-10 Dr. H-J Breymayer
# -- implemented additional commands, changed definition of commands
# -- bugfix patch from Nestor
#
# - 1.28 - 2019-12-14 Dr. H-J Breymayer
# -- correction of "Rolling Key" in case of bad command
# -- GetStatus call after on_off command
#
# - 1.27 - 2019-12-14 Dr. H-J Breymayer
# -- recognition of orange power LED indicator, new state dormant
# -- attribute webCmd changed "webCmd on_off"
# -- replaced in all log3 statements fixed name VIERA with module name
# -- correction of "define" number of arguments and their test
#
# - 1.26 - 2019-11-24 Dr. H-J Breymayer
# -- problem with unexpected crypted command, correct Session Sequence
#
# - 1.25 - 2019-11-23 Dr. H-J Breymayer
# -- removed Readings "power". Redefined state -> Initialized/on/off
# -- removed spaces at remote control layout, problems with images not appearing
# -- PERL error line 481 and 516
# -- correction of sub call "sub VIERA_GetStatus($$)"
# -- Verschlüsselte Verbindung für neue TV's ab 2019 integriert.
#
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
use MIME::Base64;
use Crypt::Mode::CBC;
use Digest::SHA qw(hmac_sha256);
use Time::HiRes qw(gettimeofday sleep);
use utf8;
#use Blocking;

# Forward declaration for remotecontrol module
sub VIERA_RCmakenotify($$);
sub VIERA_RClayout_TV();
sub VIERA_RClayout_TV_SVG();

my %VIERA_remoteControl_args = (
   channel_down         => "CH_DOWN",
   channel_up           => "CH_UP",
   volume_up            => "VOLUP",
   volume_down          => "VOLDOWN",
   mute                 => "MUTE",
   TV                   => "TV",
   AV                   => "CHG_INPUT",
   red_button           => "RED",
   green_button         => "GREEN",
   yellow_button        => "YELLOW",
   blue_button          => "BLUE",
   VIERA_tools          => "VTOOLS",
   cancel               => "CANCEL",
   exit                 => "CANCEL",
   option               => "SUBMENU",
   return               => "RETURN",
   home                 => "HOME",
   program              => "PROG",
   enter                => "ENTER",
   right                => "RIGHT",
   left                 => "LEFT",
   up                   => "UP",
   down                 => "DOWN",
   "3D_button"          => "3D",
   SD_card              => "SD_CARD",
   display_mode         => "DISP_MODE",
   menu                 => "MENU",
   VIERA_connect        => "INTERNET",
   VIERA_link           => "VIERA_LINK",
   EPG                  => "EPG",
   guide                => "GUIDE",
   videotext            => "TEXT",
   subtitle             => "STTL",
   info                 => "INFO",
   index                => "INDEX",
   hold                 => "HOLD",
   last_view            => "R_TUNE",
   on_off               => "POWER",
   rewind               => "REW",
   play                 => "PLAY",
   fast_forward         => "FF",
   skip_previous        => "SKIP_PREV",
   pause                => "PAUSE",
   skip_next            => "SKIP_NEXT",
   stop                 => "STOP",
   record               => "REC",
   apps                 => "APPS",
   aspect               => "ASPECT",
   favorite             => "FAVORITE",
   game                 => "GAME",
   digit_1	            => "D1", 
   digit_2	            => "D2",
   digit_3	            => "D3",
   digit_4	            => "D4",
   digit_5	            => "D5",
   digit_6	            => "D6",
   digit_7	            => "D7",
   digit_8	            => "D8",
   digit_9	            => "D9",
   digit_0	            => "D0",
   noise_reduction      => "P_NR",
   tune                 => "R_TUNE",
   HDMI_1               => "HDMI1",
   HDMI_2               => "HDMI2",
   HDMI_3               => "HDMI3",
   HDMI_4               => "HDMI4",
);

my %VIERA_remoteControl_apps = (
   netflix              => "0010000200000001",
   youtube              => "0070000200180001",
   shoutcast            => "0070000400000001",
   calendar             => "0387878700150020",
   browser              => "0077777700160002",
   amazonprime          => "0010000100180001",
   iplayer              => "0020000A00000010",
   bbc_iplayer          => "0020000A00000010",
   itv                  => "0387878700000124",
   all_4                => "0387878700000125",
   demand_5             => "0387878700000125",
   recorded_tv          => "0387878700000013",
   multi_window         => "0387878700000050",
   bbc_news             => "0020000A00000006",
   bbc_sport            => "0020000A00000007",
   weather              => "0070000C00000001",
   developer            => "0077777777777778",
);

# Initialize the module and tell FHEM name of additional functions
# Param1: Hash of FHEM-Device
# Return: no return code
sub VIERA_Initialize($) {
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
sub VIERA_Define($$) {
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);
  my $name = $args[0];
  
  my $nom = $hash->{TYPE}."_".$hash->{NAME}."_";
  
  my $error = ""; 
  my $value = "";
  
  $hash->{helper}{session_id}        = "None";      
  $hash->{helper}{session_seq_num}   = "None";

  if(int(@args) < 3 || int(@args) > 6) {
    my $msg = "wrong syntax: define <name> VIERA <host> [<interval>] <pincode> <?>";
    Log3 $name, 2, "$name: \"$msg\"";
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
  
  if(defined($args[4])) {
    $hash->{helper}{pincode} = $args[4];
  }
  else {
    $hash->{helper}{pincode} = "0000";
    $hash->{helper}{ENCRYPTION} = "no";
  }
  
  if(defined($args[5])) {
    $hash->{helper}{ENCRYPTION} = $args[5];
    }
   else  {	   
	($error, $value) = getKeyValue("$nom.ENCRYPTION");
	$hash->{helper}{ENCRYPTION} = $value if (defined($value));
  }
		

#  communication can start again       
  if ($hash->{helper}{pincode} eq "0000") {
	  $hash->{helper}{stop} = "no"
     }
	 else {
	  ($error, $hash->{helper}{stop}) = getKeyValue("$nom.stop");  
  }
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "PinCode",           $hash->{helper}{pincode});
  readingsBulkUpdate($hash, "Encryption",        $hash->{helper}{ENCRYPTION});
  readingsBulkUpdate($hash, "session_id",        $hash->{helper}{session_id});
  readingsBulkUpdate($hash, "Sequence",          $hash->{helper}{session_seq_num});
  readingsEndUpdate($hash, 1);
  
  
  ($error, $hash->{helper}{app_id}) = getKeyValue("$nom.app_id");
  $hash->{helper}{app_id} = "None" if (!defined($hash->{helper}{app_id}));
  
  ($error, $value) = getKeyValue("$nom.session_IV");
  if (defined($value)) {$hash->{helper}{session_IV} = decode_base64($value)}
     else {$hash->{helper}{session_IV} = "None"}
     
  ($error, $value) = getKeyValue("$nom.session_key");
  if (defined($value)) {$hash->{helper}{session_key} = decode_base64($value)}
     else {$hash->{helper}{session_key} = "None"}
  
  ($error, $value) = getKeyValue("$nom.session_hmac_key");
  if (defined($value)) {$hash->{helper}{session_hmac_key} = decode_base64($value)}
     else {$hash->{helper}{session_hmac_key} = "None"}
  

  CommandAttr(undef,$name." webCmd on_off") if( !defined( AttrVal($hash->{NAME}, "webCmd", undef)) );
  
  BlockingKill($hash->{helper}{RUNNING_PID_GET}) if(defined($hash->{helper}{RUNNING_PID_GET}));
  delete($hash->{helper}{RUNNING_PID_GET});
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "VIERA_GetStatus", $hash, 0);
  
  Log3 $name, 2, "$name: defined with host: $hash->{helper}{HOST} interval: $hash->{helper}{INTERVAL} PIN: $hash->{helper}{pincode} ";
  readingsSingleUpdate($hash,"state","Initialized",1);

  return undef;
}

# Callback when 'set' is used at FHEM
# Param1: Hash of FHEM-Device
# Param2: String of 'set' command
# Return: Help text for FHEMWEB
sub VIERA_Set($@) {
  my ($hash, $name, @a) = @_;
  
  my $host = $hash->{helper}{HOST};
  
  my $key = "";
  my $tab = "";
  my $usage = "choose one of ".
              "on_off:noArg ".
              "mute:on,off ".
              "volume:slider,0,1,100 ".
              "channel ".
              "remoteControl:" . join(",", sort keys %VIERA_remoteControl_args) . " " .
              "remoteControlApp:" . join(",", sort keys %VIERA_remoteControl_apps) . " " .
              "input:HDMI_1,HDMI_2,HDMI_3,HDMI_4,SD_card,TV ".
              "statusRequest:noArg  ".
              "web ";
  $usage =~ s/(NRC_|-ONOFF)//g;
  
  my $what = $a[0]; 
  return "\"set $name\" needs at least one argument" if(!defined($a[0]));
  return "Unknown value $a[0] Device is not present or reachable (power on or check ethernet connection)" if(ReadingsVal($name,"state","off") eq "off" && $what ne "?");
  return "Unknown value $a[0] use set $name on_off, choose one of on_off ?"  if(ReadingsVal($name,"state","off") eq "dormant" && $what ne "on_off");
  my $state = $a[1] if(defined($a[1])); 
  
  if ($what eq "mute"){
    Log3 $name, 3, "$name: Set mute $state";
    if ($state eq "on") {$state = 1;} else {$state = 0;}
    VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Set", "Mute", $state));
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "volume"){
    return "$name: Volume range is too high! Use Value 0 till 100 for volume." if($state < 0 || $state > 100);
    Log3 $name, 3, "$name: Set volume $state";
    VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Set", "Volume", $state));
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "on_off"){
    Log3 $name, 3, "$name: Set on_off";
    VIERA_Encrypted_Command($hash, "POWER", "key");
    VIERA_Encrypt_Answer($hash);
    sleep 0.6;
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "channel"){
    return "$name: Channel is too high or low!" if($state < 1 || $state > 9999);
    Log3 $name, 3, "$name: Set channel $state";
    for(my $i = 0; $i <= length($state)-1; $i++) {
      VIERA_Encrypted_Command($hash, "D".substr($state, $i, 1), "key");
      sleep 0.1;
      VIERA_Encrypt_Answer($hash);
    }
    VIERA_Encrypted_Command($hash, "ENTER", "key");
    VIERA_Encrypt_Answer($hash);
  }
  elsif ($what eq "remoteControl"){
    Log3 $name, 3, "$name: Set remoteControl $state";
    
    if( defined($VIERA_remoteControl_args{$state}) ) {
       $state =  $VIERA_remoteControl_args{$state};  
       Log3 $name, 4, "$name: Set remoteControl $state";
    }
    else {return "Unknown argument $what, $usage"}
    
    VIERA_Encrypted_Command($hash, $state, "key");
    VIERA_Encrypt_Answer($hash);
  }
  elsif ($what eq "remoteControlApp"){
    Log3 $name, 3, "$name: Set remoteControlApp $state";
    
    if( defined($VIERA_remoteControl_apps{$state}) ) {
       $state =  $VIERA_remoteControl_apps{$state};
       Log3 $name, 4, "$name: Set remoteControlApp $state";
    }
    else {return "Unknown argument $what, $usage"}
    
    VIERA_Encrypted_Command($hash, $state, "app");
    VIERA_Encrypt_Answer($hash);
  }
  elsif ($what eq "input"){
	Log3 $name, 3, "$name: Set input $state";
    if( defined($VIERA_remoteControl_args{$state}) ) {
       $state =  $VIERA_remoteControl_args{$state};  
       Log3 $name, 4, "$name: Set remoteControl $state";
    }
    else {return "Unknown argument $what, $usage"}
    
    VIERA_Encrypted_Command($hash, $state, "key");
    VIERA_Encrypt_Answer($hash);
  }
  elsif ($what eq "statusRequest"){
    Log3 $name, 3, "$name: Set statusRequest";
    VIERA_GetStatus($hash, 1);
  }
  elsif ($what eq "web"){
    Log3 $name, 3, "$name: Set web $state";
    VIERA_webpage($hash, $state);
  }
  elsif ($what eq "?"){
    return "$usage";
  }
  else {
    Log3 $name, 3, "$name: Unknown argument $what, $usage";
    return "Unknown argument $what, $usage";
  }
  return undef;
}

# Callback when 'get' is used at FHEM
# Param1: Hash of FHEM-Device
# Param2: String of 'set' command
# Return: Help text for FHEMWEB
sub VIERA_Get($@) {
  my ($hash, @a) = @_;
  
  my $what;
  my $usage = "choose one of mute:noArg volume:noArg presence:noArg";
  my $name = $hash->{NAME};

  return "$name: No argument given, $usage" if(int(@a) != 2);

  $what = $a[1];

  if($what =~ /^(volume|mute|presence)$/) {
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
sub VIERA_Undefine($$) {
  my($hash, $name) = @_;
  
  # Stop the internal GetStatus-Loop and exit
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID_GET}) if(defined($hash->{helper}{RUNNING_PID_GET}));
  delete($hash->{helper}{RUNNING_PID_GET});
  
  return undef;
}

# Function is called periodically by InternalTimer and fetch informations from device. The decision if blocking or nonBlocking is used is made here.
# Param1: Hash of FHEM-Device
# Param2: Optional, if set to 1 fetch information from device without interrupting InternalTimer
sub VIERA_GetStatus($$) {
  my ($hash, $local) = @_;
  
  my $name = $hash->{NAME};
  my $host = $hash->{helper}{HOST};
  my $blocking = AttrVal($name, "blocking", 0);		#use non-blocking in standard. Just use blocking when set by attr
  
  #if $local is set to 1 just fetch informations from device without interrupting InternalTimer
  $local = 0 unless(defined($local));
  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "VIERA_GetStatus", $hash, 0) unless($local == 1);
  
  return "" if(!defined($hash->{helper}{HOST}) or !defined($hash->{helper}{INTERVAL}));
  
  return  if ($hash->{helper}{stop} eq "yes"); 

  VIERA_CeckEncryption($hash) if ($hash->{helper}{ENCRYPTION} eq "?");

  if ($blocking == 0) {
    Log3 $name, 4, "$name [VIERA_GetStatus]: Using non blocking...";
    $hash->{helper}{RUNNING_PID_GET} = BlockingCall("VIERA_GetDoIt", $hash, "VIERA_GetDone", 10, "VIERA_GetAbortFn", $hash) unless(exists($hash->{helper}{RUNNING_PID_GET}));
    if($hash->{helper}{RUNNING_PID_GET}) {
      Log3 $name, 4, "$name [VIERA_GetStatus]: VIERA_GetDoIt() BlockingCall process started with PID $hash->{helper}{RUNNING_PID_GET}{pid}"; 
    }
    else { 
      Log3 $name, 3,  "$name [VIERA_GetStatus]: BlockingCall process start failed for VIERA_GetDoIt()"; 
    }
    return;
  }
  Log3 $name, 4, "$name [VIERA_GetStatus]: Using blocking...";
  my $returnVol = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Volume", ""));
  Log3 $name, 5, "$name [VIERA_GetStatus]: Vol-Request returned: $returnVol" if(defined($returnVol));
  
  if ( not defined($returnVol) or $returnVol eq "" )  {
    Log3 $name, 4, "$name [VIERA_GetStatus]: Vol-Request NO SOCKET!";
    if (ReadingsVal($name,"state","off") ne "off") {
      $hash->{helper}{session_seq_num} = "None";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "off");
      readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
      readingsBulkUpdate($hash, "presence", "absent");
      readingsBulkUpdate($hash, "volume", "?");
      readingsBulkUpdate($hash, "mute", "?");      
      readingsEndUpdate($hash, 1);
    }
    return;
  }
    elsif ( index($returnVol, "Bad Request") != -1) {
    if (ReadingsVal($name,"state","off") ne "dormant") {
	  Log3 $name, 4, "$name [VIERA_GetStatus()]: TV answered. Seems to be on but delivering no data";
	  $hash->{helper}{session_seq_num} = "None";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "dormant");
      readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
      readingsBulkUpdate($hash, "presence", "absent");
      readingsBulkUpdate($hash, "volume", "?");
      readingsBulkUpdate($hash, "mute", "?");
      readingsEndUpdate($hash, 1);
    }     		
    return;
  }

  my $returnMute = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Mute", ""));
  Log3 $name, 5, "$name [VIERA_GetStatus]: Mute-Request returned: $returnMute" if(defined($returnMute));
  
  if( not defined($returnMute) or $returnMute eq "" ) {
    Log3 $name, 4, "$name [VIERA_GetStatus]: Mute-Request NO SOCKET!";
    if( ReadingsVal($name,"state","off") ne "off") {
	  $hash->{helper}{session_seq_num} = "None";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "off");
      readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
      readingsBulkUpdate($hash, "presence", "absent");
      readingsBulkUpdate($hash, "volume", "?");
      readingsBulkUpdate($hash, "mute", "?");
      readingsEndUpdate($hash, 1);
    }
    return;
  }
    elsif ( index($returnMute, "Bad Request") != -1) {
    if (ReadingsVal($name,"state","off") ne "dormant") {
	  Log3 $name, 4, "$name [VIERA_GetStatus()]: TV answered. Seems to be on but delivering no data";
	  $hash->{helper}{session_seq_num} = "None";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "dormant");
      readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
      readingsBulkUpdate($hash, "presence", "absent");
      readingsBulkUpdate($hash, "volume", "?");
      readingsBulkUpdate($hash, "mute", "?");
      readingsEndUpdate($hash, 1);
    }     		
    return;
  }
  
  readingsBeginUpdate($hash);
  if($returnVol =~ /<CurrentVolume>(.+)<\/CurrentVolume>/){
    Log3 $name, 4, "$name [VIERA_GetStatus]: Set reading volume to $1";
    if( $1 ne ReadingsVal($name, "volume", "0") ) {readingsBulkUpdate($hash, "volume", $1);}
  }
  
  if($returnMute =~ /<CurrentMute>(.+)<\/CurrentMute>/){
    my $myMute = $1;
    if ($myMute == 0) { $myMute = "off"; } else { $myMute = "on";}
    Log3 $name, 4, "$name [VIERA_GetStatus]: Set reading mute to $myMute";
    if( $myMute ne ReadingsVal($name, "mute", "0") ) {readingsBulkUpdate($hash, "mute", $myMute);}
  }
  if( ReadingsVal($name,"state","off") ne "on") {
    readingsBulkUpdate($hash, "state", "on");
    readingsBulkUpdate($hash, "presence", "present");
  }
  readingsEndUpdate($hash, 1);
  
  return $hash->{STATE};
}

# To sent RAW-Data as TCP Client to device
# param1: Hash of FHEM-Device
# param2: RAW Data
#return: RAW answer when successful or undef if no socket is available.
sub VIERA_connection($$) {
  my ($hash, $data) = @_;
  
  my $name = $hash->{NAME};
  my $buffer = "";
  my $buff = "";
  my $blocking = "NonBlocking-VIERA_connection()" if (AttrVal($name, "blocking", 0) == 0);
     $blocking = "Blocking-VIERA_connection()" if (AttrVal($name, "blocking", 0) == 1);

  my $sock = new IO::Socket::INET ( 
             PeerAddr => $hash->{helper}{HOST},
             PeerPort => $hash->{helper}{PORT},
             Proto    => "tcp",
             Timeout  => 2
  );

  if(defined ($sock)) {
    Log3 $name, 5, "$name [$blocking]: Send Data to $hash->{helper}{HOST}:$hash->{helper}{PORT}:\n$data";
    print $sock $data;
  
    while (1){
	  my $res = read $sock, $buff, 1024;
      last if (not defined($res) or $res == 0);
      $buffer .= $buff;
    }
 
    Log3 $name, 5, "$name [$blocking]: $hash->{helper}{HOST} buffer response:\n$buffer";
    close($sock);
    $hash->{helper}{BUFFER} = $buffer;
    return $buffer;
  }
  else {
    Log3 $name, 4, "$name [$blocking]: $hash->{helper}{HOST}: not able to open socket";
    return undef;
  }
}


# Create RAW Data to send or get volume/mute state
# Param1: Hash of FHEM-Device
# Param2: get|set 
# Param3: volume|mute
# Param4: value for set command
# Return: RAW html request for xml soap
sub VIERA_BuildXML_RendCtrl($$$$) {
  my ($hash, $methode, $command, $value) = @_;
  
  my $host = $hash->{helper}{HOST};
  my $port = $hash->{helper}{PORT};
  my $name = $hash->{NAME};
  
  my $callsoap = "";
  my $message = "";
  my $head = "";
  my $blen  = "";
  
# Log3 $name, 5, "$name: $command with $value to $host";

  $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
  $callsoap .= "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"";
  $callsoap .= " s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">\r\n";

  $callsoap .= "<s:Body>\r\n";
  $callsoap .= "<u:$methode$command xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">\r\n";
  $callsoap .= "<InstanceID>0</InstanceID>\r\n";
  $callsoap .= "<Channel>Master</Channel>\r\n";
  $callsoap .= "<Desired$command>$value</Desired$command>\r\n" if(defined($value));
  $callsoap .= "</u:$methode$command>\r\n";
  $callsoap .= "</s:Body>\r\n";
  $callsoap .= "</s:Envelope>\r\n";

  $blen = length($callsoap);

  $head .= "POST /dmr/control_0 HTTP/1.1\r\n";
  $head .= "Host: $host:$port\r\n";
  $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
  $head .= "SOAPAction: \"urn:schemas-upnp-org:service:RenderingControl:1#$methode$command\"\r\n";
  $head .= "Content-Length: $blen\r\n";
  $head .= "\r\n";

  $message .= $head;
  $message .= $callsoap;
  Log3 $name, 5, "$name: Building XML SOAP (RenderingControl) for command $command with value $value to host $host:\n$message";
  return $message;
}


# ####################### create any SOAP Request message encrypted or not #################################
sub VIERA_Build_soap_message_Encrypt($$$$) {
  my ($hash, $action, $params, $body_elem) = @_;


  my $host = $hash->{helper}{HOST};
  my $port = $hash->{helper}{PORT};
  my $urn = "panasonic-com:service:p00NetworkControl:1";
  
  my $callsoap = "";
  my $soapbody = "";
  my $encrypted_command = "";
  my $message = "";
  my $head = "";
  my $blen  = "";
  
  my $session_id         = $hash->{helper}{session_id};
  my $session_seq_num    = $hash->{helper}{session_seq_num};
  my $session_hmac_key   = $hash->{helper}{session_hmac_key};
  my $session_IV         = $hash->{helper}{session_IV};
  my $session_key        = $hash->{helper}{session_key};
  
  my $is_encrypted = 0;
  
  if ($action ne "X_GetEncryptSessionId" and $action ne "X_DisplayPinCode" and $action ne "X_RequestAuth") {
	if ($session_key ne "None" and $session_IV ne "None" and $session_hmac_key ne "None" and
	   $session_id ne "None" and $session_seq_num ne "None" ) {
	
	   $is_encrypted = 1;
  
# Encapsulate URN_REMOTE_CONTROL command in an X_EncryptedCommand if we're using encryption
        
       $hash->{helper}{session_seq_num} += 1;
    
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
       readingsEndUpdate($hash, 1);
       
       $session_seq_num    = sprintf("%08d", $session_seq_num);
    
       $encrypted_command .= "<X_SessionId>$session_id</X_SessionId>\r\n";
       $encrypted_command .= "<X_SequenceNumber>$session_seq_num</X_SequenceNumber>\r\n";
       $encrypted_command .= "<X_OriginalCommand>\r\n";
       $encrypted_command .= "<$body_elem:$action xmlns:$body_elem=\"urn:$urn\">\r\n";
       $encrypted_command .= "$params\r\n";
       $encrypted_command .=  "</$body_elem:$action>\r\n";
       $encrypted_command .=  "</X_OriginalCommand>\r\n";
                
       $encrypted_command = VIERA_encrypt_soap_payload($encrypted_command, $session_key, $session_IV, $session_hmac_key);
                
       $action = "X_EncryptedCommand";
       my $app_id = $hash->{helper}{app_id};
       $params  =  "<X_ApplicationId>$app_id</X_ApplicationId>\r\n";
       $params .=  "<X_EncInfo>$encrypted_command</X_EncInfo>";
                            
       $body_elem = "u";
    }
  }
   
# Construct SOAP request        
  
  $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
  $callsoap .= "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"";
  $callsoap .= " s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">\r\n";

  $callsoap .= "<s:Body>\r\n";

  $callsoap .= "<$body_elem:$action xmlns:$body_elem=\"urn:$urn\">\r\n";
  $callsoap .= "$params\r\n";
  $callsoap .= "</$body_elem:$action>\r\n";

  $callsoap .= "</s:Body>\r\n";
  $callsoap .= "</s:Envelope>\r\n";

  $blen = length($callsoap);

  $head .= "POST /nrc/control_0 HTTP/1.1\r\n";
  $head .= "Host: $host:$port\r\n";
  $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
  $head .= "SOAPAction: \"urn:panasonic-com:service:p00NetworkControl:1#$action\"\r\n";
  $head .= "Content-Length: $blen\r\n";
  $head .= "\r\n";

  $message .= $head;
  $message .= $callsoap;
# Log3 $name, 5, "$name: Building XML SOAP (NetworkControl) for command $command to host $host:\n$message";
  
  $hash->{helper}{is_encrypted} = $is_encrypted;
  
  return $message;
}

# Get volume and mute state from device. This function is called non blocking!
# Param1: Hash of FHEM-Device
# Return: <name of fhem-device>|<volume level>|<mute state>
sub VIERA_GetDoIt($) {
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  
  my $myVol = "";
  my $myMute = "";
  
  Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: BlockingCall for ".$hash->{NAME}." start...";
  
  my $returnVol = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Volume", ""));
  Log3 $name, 5, "$name [NonBlocking-VIERA_GetDoIt()]: GetStatusVol-Request returned: $returnVol" if(defined($returnVol));
  if(not defined($returnVol) or $returnVol eq "") {
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: GetStatusVol-Request NO SOCKET!";
    
    return $hash->{NAME}. "|". 
    "error-noSocket" . "|".
    "error-noSocket";
  }

  my $returnMute = VIERA_connection($hash, VIERA_BuildXML_RendCtrl($hash, "Get", "Mute", ""));
  Log3 $name, 5, "$name [NonBlocking-VIERA_GetDoIt()]: GetStatusMute-Request returned: $returnMute" if(defined($returnMute));
  if(not defined($returnMute) or $returnMute eq "") {
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: GetStatusMute-Request NO SOCKET!";
    
    return $hash->{NAME}. "|". 
    "error-noSocket" . "|".
    "error-noSocket";
  }
  
  if ($returnVol =~ /HTTP\/1\.1 ([\d]{3}) (.*)/) {
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: Received HTTP Code $1 $2";
    $myVol = "error-$1 $2" if ($1 ne "200");
  }
  if($returnVol =~ /<CurrentVolume>(.+)<\/CurrentVolume>/){
  $myVol = $1;
  Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: Received volume with level $myVol";
  }
  
  if ($returnMute =~ /HTTP\/1\.1 ([\d]{3}) (.*)/) {
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: Received HTTP Code $1 $2";
    $myMute = "error-$1 $2" if ($1 ne "200");
  }
  if($returnMute =~ /<CurrentMute>(.+)<\/CurrentMute>/){
    $myMute = $1;
    if ($myMute == 0) { $myMute = "off"; } else { $myMute = "on";}
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDoIt()]: Received mute state $myMute";
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
  
  Log3 $name, 4, "$name [NonBlocking-VIERA_GetDone()]: Param: $string";
  
  if ($myVol =~ /error-(.*)/ || $myMute =~ /error-(.*)/) {
    if ($1 eq "noSocket") {
      Log3 $name, 4, "$name [NonBlocking-VIERA_GetDone()]: Seems to be there is no socket available. Guessing TV is off!";
      if (ReadingsVal($name,"state","off") ne "off") {
		$hash->{helper}{session_seq_num} = "None";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "state", "off");
        readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
        readingsBulkUpdate($hash, "presence", "absent");
        readingsBulkUpdate($hash, "volume", "?");
        readingsBulkUpdate($hash, "mute", "?");
        readingsEndUpdate($hash, 1);
      }
      delete($hash->{helper}{RUNNING_PID_GET});
      return;
    }
    else {
       if (ReadingsVal($name,"state","off") ne "dormant") {
		Log3 $name, 4, "$name [NonBlocking-VIERA_GetDone()]: TV answered with $1. Seems to be on but delivering no data";
		$hash->{helper}{session_seq_num} = "None";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "state", "dormant");
        readingsBulkUpdate($hash, "Sequence", $hash->{helper}{session_seq_num});
        readingsBulkUpdate($hash, "presence", "absent");
        readingsBulkUpdate($hash, "volume", "?");
        readingsBulkUpdate($hash, "mute", "?");
        readingsEndUpdate($hash, 1);
      }     
      delete($hash->{helper}{RUNNING_PID_GET});
      return;
    }
  }
  
  readingsBeginUpdate($hash);
  if ($myVol ne ReadingsVal($name, "volume", "0")) {
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDone()]: Set reading volume to $myVol";
    readingsBulkUpdate($hash, "volume", $myVol);
  } 
  
  if ($myMute ne ReadingsVal($name, "mute", "0")) {
    Log3 $name, 4, "$name [NonBlocking-VIERA_GetDone()]: Set reading mute to $myMute";  
    readingsBulkUpdate($hash, "mute", $myMute);
  }
  
  if (ReadingsVal($name,"state","off") ne "on") {
    readingsBulkUpdate($hash, "state", "on");
    readingsBulkUpdate($hash, "presence", "present");
  }
  readingsEndUpdate($hash, 1);
  
  delete($hash->{helper}{RUNNING_PID_GET});
}

# Callback of non blocking when function VIERA_GetDoIt runs into timeout.
# Param1: Hash of FHEM-Device
# Return: no return code
sub VIERA_GetAbortFn($) { 
  my ($hash) = @_;
  
  my $name = $hash->{NAME};

  delete($hash->{helper}{RUNNING_PID_GET});
  Log3 $name, 2, "$name [NonBlocking-VIERA_GetAbortFn()]: BlockingCall for $hash->{NAME} was aborted, timeout reached";
  return;
}

# open web page on the TV

sub VIERA_webpage($$) {
	  my ($hash, $url) = @_;
	  
	  my $name = $hash->{NAME};
	  
      my $i = 0;
	  my $params = "";
	  my $message = "";
	  my $answer = "";
	  my @msg ;
	  my $iS ;
	  my $iE ;
	  my $sock ;
	  my $clientsock ;
	
# check if Encryption is ready
      VIERA_Encrypted_Command($hash, "" , "web");
      
#start Web Browser and open url"""
      $params = "<X_AppType>vc_app</X_AppType><X_LaunchKeyword>resource_id=1063</X_LaunchKeyword>";
      $message   = VIERA_Build_soap_message_Encrypt($hash, "X_LaunchApp", $params, "s");
       
      $hash->{helper}{BUFFER} = "";
      if (exists($hash->{helper}{RUNNING_PID_GET}) and $i < 5) { 
	     sleep (0.1);
	  $i += 1;
      }
      VIERA_connection($hash, $message);
      
      $answer = VIERA_Encrypt_Answer($hash);
      if (!defined($answer)) {
		  Log3 $name, 3, "$name cannot start web browser"; 
		  return;
	  }
 
      $iS = index($answer, "<X_SessionId>");
      $iE = index($answer, "</X_SessionId>");
      my $sessionId = substr($answer, $iS+13, $iE-$iS-13);
        
# setup a server socket where URL will be served

      my $localip   = $hash->{helper}{mylocalIP} ;
      my $localport = 56000 + int(rand(9000));
      
      $sock = new IO::Socket::INET ( 
              LocalAddr => $localip,
              LocalPort => $localport,
              Proto     => 'tcp',
              Listen    => 5,
              Reuse     => 1
  );

      if(defined ($sock)) {
         Log3 $name, 4, "$name: open socket for web page address: $localip:$localport"; 
      }     
      else {
         Log3 $name, 3, "$name: not able to open socket for web page address";
         return undef;
      }	 
       
      $params  = "<X_AppType>vc_app</X_AppType><X_SessionId>$sessionId</X_SessionId>\r\n";
      $params .= "<X_ConnectKeyword>panasonic-viera 0.2</X_ConnectKeyword>\r\n";
      $params .= "<X_ConnectAddr>$localip:$localport</X_ConnectAddr>";
      $message  = VIERA_Build_soap_message_Encrypt($hash, "X_ConnectApp", $params, "s");

      $hash->{helper}{BUFFER} = "";
      if (exists($hash->{helper}{RUNNING_PID_GET}) and $i < 5) { 
	     sleep (0.1);
	  $i += 1;
      }
      VIERA_connection($hash, $message);
       
      $answer = VIERA_Encrypt_Answer($hash); 
      if (!defined($answer)) {
		  Log3 $name, 3, "$name: cannot transmit web address"; 
		  return;
	  }  

      $i = 0;
      $clientsock = $sock -> accept();
      if(!defined ($clientsock) and $i < 5) {
		  sleep 0.1;
		  $i += 1;
          $clientsock = $sock -> accept();
      }
      
      if(!defined ($clientsock)) {
		 Log3 $name, 3, "$name: not able to open new socket for web page address";
         return undef;
      }
      
      my $client_address = $clientsock -> peerhost();
      my $client_port = $clientsock -> peerport();
      Log3 $name, 4, "$name: connection from $client_address:$client_port established";
      
      my $l1 = length($url) & 0xFF;
      @msg = (0xf4, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, $l1);
      
      my $l2 = @msg;
      for($i = 0; $i < $l1; $i++) {$msg[$l2+$i] = ord(substr($url, $i, 1))}; # get unicode for characters
      $msg[$l2+$l1] = 0x00;
       
      my $msgH = "";
      for ($i = 0; $i <= $l1+$l2; $i++) {$msgH .= chr($msg[$i])};

#      print $clientsock $msgH;
      $clientsock->send($msgH);  
        
      shutdown($clientsock, 1);
      close($clientsock);
      close($sock);
        
      return;
}

sub VIERA_get_local_ip_address ($) {
	my ($hash) = @_;
	
    my $socket = IO::Socket::INET->new(
                 Proto       => "tcp",
                 PeerAddr    => $hash->{helper}{HOST},   #  "google.com",
                 PeerPort    => $hash->{helper}{PORT},   #  "80", 
    );

    # A side-effect of making a socket connection is that our IP address
    # is available from the 'sockhost' method
    my $local_ip_address = $socket->sockhost;

    close($socket);

    return $local_ip_address;
}

################ special encryption ###########################################################

######################################################################################################################


sub VIERA_Encrypted_Command($$$) {
   my ($hash, $command, $type) = @_;
   
   my $i = 0;
   my $message = "";
   my $params  = "";
   my $task    = "";
   
   if ($hash->{helper}{ENCRYPTION} eq "yes") {
      
      if ($hash->{helper}{pincode} eq "0000") {return VIERA_request_pin_code($hash)};
      
      if ($hash->{helper}{stop} eq "yes") {return 0 if (!VIERA_authorize_pin_code($hash))};
      
      if ($hash->{helper}{session_seq_num} eq "None") {return 0 if (!VIERA_request_session_id($hash))};
   }
		 
   if ( $type eq "key" ) {
      $params = "<X_KeyEvent>NRC_$command-ONOFF</X_KeyEvent>";
      $task = "X_SendKey";
    }
    elsif ( $type eq "app" ) {
	  $params  = "<X_AppType>vc_app</X_AppType><X_LaunchKeyword>";
	  $params .= "product_id=$command</X_LaunchKeyword>";
	  $task = "X_LaunchApp";
    }
    elsif ( $type eq "web" ) {
	  return;
	}
    else {return};   
   
   $message   = VIERA_Build_soap_message_Encrypt($hash, $task, $params, "u");
   $hash->{helper}{BUFFER} = "";
   if (exists($hash->{helper}{RUNNING_PID_GET}) and $i < 5) { 
	  sleep (0.1);
	  $i += 1;
   }
   VIERA_connection($hash, $message);
   

   return;
}


sub VIERA_Encrypt_Answer($) {
   my ($hash) = @_;
   
   my $name = $hash->{NAME};
   
   my $answer = "";  
   $answer = $hash->{helper}{BUFFER} if ($hash->{helper}{BUFFER} ne "");
  
  if (index($answer, "HTTP/1.1 200 OK") == -1) {
     if (index($answer, "Bad Request") != -1) {
        if ($hash->{helper}{session_seq_num} ne  "None") {
          $hash->{helper}{session_seq_num} -= 1;
          readingsSingleUpdate($hash, "Sequence", $hash->{helper}{session_seq_num},1);
        }
      }  
      elsif (index($answer, "Internal Server Error") != -1) {
		 $hash->{helper}{session_seq_num} = "None";
		 readingsSingleUpdate($hash, "Sequence", $hash->{helper}{session_seq_num},1);
		 Log3 $name, 4, "$name reset of Rolling Key";
	  }
	  	  
      Log3 $name, 3, "$name wrong encrypted VIERA command:  \r\n\"$answer\"";
      return undef;
  }

  if ($hash->{helper}{is_encrypted} == 1) {
      my $iS = index($answer, "<X_EncResult>");
      my $iE = index($answer, "</X_EncResult>");
      $answer = substr($answer, $iS+13, $iE-$iS-13);
        
      $answer = VIERA_decrypt_soap_payload($answer, $hash->{helper}{session_key}, $hash->{helper}{session_IV});
      Log3 $name, 5, "$name decrypted VIERA answer:  \r\n\"$answer\"";
   }

   return $answer;
}

#check if TV is encrypted
sub VIERA_CeckEncryption($) {
  my ($hash) = @_;
  
  my $nom = $hash->{TYPE}."_".$hash->{NAME}."_";
  
  my $answer = "";
  my $iS = -1;


  $hash->{helper}{BUFFER} = "";
  VIERA_Encrypted_Command($hash, "INFO", "key");
  
    if ($hash->{helper}{BUFFER} ne "") {
      $answer = $hash->{helper}{BUFFER} ;
      $iS = index($answer, "<errorCode>401</errorCode>");
	  if ( $iS != -1) {
		$hash->{helper}{ENCRYPTION} = "yes";
	  }
      else {
	    $hash->{helper}{ENCRYPTION} = "no";
      }
    }
  
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "Encryption", $hash->{helper}{ENCRYPTION});
    readingsEndUpdate($hash, 1);
    
    my $error = setKeyValue("$nom.ENCRYPTION", $hash->{helper}{ENCRYPTION}); 

  return;
}


# Calculate encryption

sub VIERA_derive_session_keys($) {
  my ($hash) = @_;

  my $iv ="";
  my @iv_vals ;
  my @key_vals ;
  my $session_key = "";
  my $session_hmac_key = "";
  
  my $nom = $hash->{TYPE}."_".$hash->{NAME}."_";

  my $i = "";

# decode ChallengeKey 
  $iv = decode_base64($hash->{helper}{enc_key});
  $hash->{helper}{session_IV} = $iv;
  
  for($i = 0; $i < 16; $i++) {$iv_vals[$i] = ord(substr($iv, $i, 1))}; # get unicode for characters
  
  for($i = 0; $i < 16; $i++) {$key_vals[$i] = 0};
# Derive key from IV  
  $i = 0 ;
  while ($i < 16) {
    $key_vals[$i]     = $iv_vals[$i + 2];
    $key_vals[$i + 1] = $iv_vals[$i + 3];
    $key_vals[$i + 2] = $iv_vals[$i + 0];
    $key_vals[$i + 3] = $iv_vals[$i + 1];
    $i += 4;
  }
 
# Convert key character codes to bytes
    $session_key = "";
    for($i = 0; $i < 16; $i++) {$session_key .= chr($key_vals[$i] & 0xFF)};
    $hash->{helper}{session_key} = $session_key;
    
    $i = length ($session_key);

# HMAC key for comms is just the IV repeated twice
    $session_hmac_key = $iv.$iv;
    $hash->{helper}{session_hmac_key} = $session_hmac_key;
      
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "app_id",           $hash->{helper}{app_id});
    readingsEndUpdate($hash, 1);
    
    my $error = "";
    my $value = "";
    $error = setKeyValue("$nom.app_id", $hash->{helper}{app_id});
    
    $value = encode_base64($hash->{helper}{session_IV}, "");
    $error = setKeyValue("$nom.session_IV", $value);
    
    $value = encode_base64($hash->{helper}{session_key}, "");
    $error = setKeyValue("$nom.session_key", $value);
  
    $value = encode_base64($hash->{helper}{session_hmac_key}, "");
    $error = setKeyValue("$nom.session_hmac_key", $value); 
 

  return;
}

# The encrypted payload must begin with a 16-byte header (12 random bytes, and 4 bytes for the payload length in big endian)
# Note: the server does not appear to ever send back valid payload lengths in bytes 13-16, so I would assume these can also 
# be randomized by the client, but we'll set them anyway to be safe.

sub VIERA_encrypt_soap_payload($$$$) {
  my ($message, $key, $IV, $hmac_key) = @_;

  my $i = "";
  my $len = "";
  my $range = 255;
  my $payload = "";
  for($i = 0; $i < 12; $i++) {$payload .= chr( int(rand($range)) )};
#  for($i = 0; $i < 12; $i++) {$payload .= "A"};
  
  $len = length($message);
  $payload .= pack("N", $len);  # make big endian  
#  $len = (($len & 0x000000FF) + ($len & 0x0000FF00) * 2**8 + ($len & 0x00FF0000) * 2**16 + ($len & 0xFF000000) * 2**24);
  $payload .= $message;


# Initialize AES
  my $cbc = Crypt::Mode::CBC->new("AES", 4);
  
  my $ciphertext = $cbc->encrypt($payload, $key, $IV);

   my $sig = hmac_sha256($ciphertext, $hmac_key);

# Concat HMAC with AES-encrypted payload

  my $encrypttext = $ciphertext.$sig;
  $encrypttext = encode_base64($encrypttext, "");
  
  return $encrypttext;

  
}

sub VIERA_decrypt_soap_payload($$$) {
  my ($message, $key, $IV) = @_;

# Initialize AES
  my $cbc = Crypt::Mode::CBC->new("AES", 4);
  
  $message = decode_base64($message);

# Decrypt
  my $decrypted = $cbc->decrypt($message, $key, $IV);

# Unpad and return
  my $i = length($decrypted) ;
  $decrypted = substr($decrypted, 16, $i-16);
  $i = index($decrypted, chr(0x00));
  $decrypted = substr($decrypted, 0, $i);

  return $decrypted ;

}

sub VIERA_request_pin_code($) {
    my ($hash) = @_;
    
    my $nom = $hash->{TYPE}."_".$hash->{NAME}."_";
    
#  Stop communication with TV until PIN authorized
   $hash->{helper}{stop} = "yes"; 
   my $error = setKeyValue("$nom.stop", $hash->{helper}{stop}); 
           
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, "stop", $hash->{helper}{stop});
   readingsEndUpdate($hash, 1);
    
# First let's ask for a pin code and get a challenge key back
   my $params = "<X_DeviceName>FHEMremote</X_DeviceName>";
   my $message = VIERA_Build_soap_message_Encrypt($hash, "X_DisplayPinCode", $params, "u");
   
   $hash->{helper}{BUFFER} = "";
   VIERA_connection($hash, $message);
   
   my $answer = VIERA_Encrypt_Answer($hash);
   if (!defined ($answer)) {return 0};
   
   my $iS = index($answer, "<X_ChallengeKey>");
   my $iE = index($answer, "</X_ChallengeKey>");
   if ($iS == -1) {return 0};
   $answer = substr($answer, $iS+16, $iE-$iS-16);
   
   $hash->{helper}{challenge} = decode_base64($answer);
 
  return 1;       
}


sub VIERA_authorize_pin_code($) {
    my ($hash) = @_;
   
   
    my $i = 0;
    my $iS = 0;
    my $iE = 0;
    my $pincode = $hash->{helper}{pincode};
    
    my $nom = $hash->{TYPE}."_".$hash->{NAME}."_";
   
# Second, let's encrypt the pin code using the challenge key and send it back to authenticate
        
# Derive key from IV
        my $iv = $hash->{helper}{challenge};
        
        my $key = "";
        $i = 0;
        while ($i < 16) {
            $key .= chr(~ord(substr($iv, $i+3, 1)) & 0xFF);
            $key .= chr(~ord(substr($iv, $i+2, 1)) & 0xFF);
            $key .= chr(~ord(substr($iv, $i+1, 1)) & 0xFF);
            $key .= chr(~ord(substr($iv, $i  , 1)) & 0xFF);
            $i += 4;
         }
        
# Derive HMAC key from IV & HMAC key mask (taken from libtvconnect.so)
        my @hmac_key_mask_vals = (0x15,0xC9,0x5A,0xC2,0xB0,0x8A,0xA7,0xEB,0x4E,0x22,0x8F,0x81,0x1E,0x34,0xD0,0x4F,
                                  0xA5,0x4B,0xA7,0xDC,0xAC,0x98,0x79,0xFA,0x8A,0xCD,0xA3,0xFC,0x24,0x4F,0x38,0x54);
                                  
        my $hmac_key = "";       
        $i = 0;
        while ($i < 32) {
            $hmac_key .= chr($hmac_key_mask_vals[$i]     ^ ord(substr($iv, (($i + 2) & 0x0F), 1)));
            $hmac_key .= chr($hmac_key_mask_vals[$i + 1] ^ ord(substr($iv, (($i + 3) & 0x0F), 1)));
            $hmac_key .= chr($hmac_key_mask_vals[$i + 2] ^ ord(substr($iv, (($i    ) & 0x0F), 1)));
            $hmac_key .= chr($hmac_key_mask_vals[$i + 3] ^ ord(substr($iv, (($i + 1) & 0x0F), 1)));
            $i += 4;
        }
        
# Encrypt X_PinCode argument and send it within an X_AuthInfo tag
        my $params = "<X_AuthInfo>";
        $params   .= VIERA_encrypt_soap_payload("<X_PinCode>$pincode</X_PinCode>", $key, $iv, $hmac_key);
        $params   .= "</X_AuthInfo>";      
        my $message = VIERA_Build_soap_message_Encrypt($hash, "X_RequestAuth", $params, "u");
       
       $hash->{helper}{BUFFER} = "";
       VIERA_connection($hash, $message);
       
 #  communication can start again      
       $hash->{helper}{stop} = "no";
       my $error = setKeyValue("$nom.stop", $hash->{helper}{stop});  
       
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash, "stop", $hash->{helper}{stop});
       readingsEndUpdate($hash, 1);
   
       my $answer = VIERA_Encrypt_Answer($hash);
       if (!defined ($answer)) {return 0};
        
# Parse and decrypt X_AuthResult
        
      $iS = index($answer, "<X_AuthResult>");
      $iE = index($answer, "</X_AuthResult>");
      $answer = substr($answer, $iS+14, $iE-$iS-14);
      
      $answer = VIERA_decrypt_soap_payload($answer, $key, $iv);
        
      # Set session application ID and encryption key
      $iS = index($answer, "<X_ApplicationId>");
      $iE = index($answer, "</X_ApplicationId>");
      $hash->{helper}{app_id} = substr($answer, $iS+17, $iE-$iS-17);
      
      $iS = index($answer, "<X_Keyword>");
      $iE = index($answer, "</X_Keyword>");
      $hash->{helper}{enc_key} = substr($answer, $iS+11, $iE-$iS-11);
      
# Derive AES & HMAC keys from X_Keyword
      VIERA_derive_session_keys($hash);
      
      return 1;
} 
    
sub VIERA_request_session_id($) {
       my ($hash) = @_;
   
# Thirdly, let's ask for a session. We'll need to use a valid session ID for encrypted NRC commands.
        
# We need to send an encrypted version of X_ApplicationId
        my $app_id           = $hash->{helper}{app_id};
        my $session_key      = $hash->{helper}{session_key};
        my $session_IV       = $hash->{helper}{session_IV};
        my $session_hmac_key = $hash->{helper}{session_hmac_key};
        
        $hash->{helper}{mylocalIP} = VIERA_get_local_ip_address($hash); 
        
        my $encinfo = VIERA_encrypt_soap_payload("<X_ApplicationId>$app_id</X_ApplicationId>", $session_key, $session_IV, $session_hmac_key);

# Send the encrypted SOAP request along with plain text X_ApplicationId
        my $params = "<X_ApplicationId>$app_id</X_ApplicationId><X_EncInfo>$encinfo</X_EncInfo>";
        
        my $message = VIERA_Build_soap_message_Encrypt($hash, "X_GetEncryptSessionId", $params, "u");
        
        $hash->{helper}{BUFFER} = "";
        VIERA_connection($hash, $message);
   
        my $answer = VIERA_Encrypt_Answer($hash);
        if (!defined ($answer)) {return 0};
        
        my $iS = index($answer, "<X_EncResult>");
        my $iE = index($answer, "</X_EncResult>");
        $answer = substr($answer, $iS+13, $iE-$iS-13);
        
        $answer = VIERA_decrypt_soap_payload($answer, $session_key, $session_IV);
        
# Set session ID and begin sequence number at 1. We have to increment the sequence number upon each successful NRC command.
        $iS = index($answer, "<X_SessionId>");
        $iE = index($answer, "</X_SessionId>");
        $hash->{helper}{session_id} = substr($answer, $iS+13, $iE-$iS-13);

        $hash->{helper}{session_seq_num} = 1;
        
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "session_id", $hash->{helper}{session_id});
        readingsBulkUpdate($hash, "Sequence",   $hash->{helper}{session_seq_num});
        readingsEndUpdate($hash, 1);
        
        return 1;
}

###################################### end of special encrytion commands #############################


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

  $row[$i++]="on_off:POWEROFF2,      TV:TV,                 AV:HDMI";
  $row[$i++]="menu:MENU,             display_mode:ASPECT,   EPG:GUIDE";
  $row[$i++]="VIERA_link:VIERA_LINK, VIERA_tools:VTOOLS,    VIERA_connect:INTERNET";
  $row[$i++]=":blank,                :blank,                :blank";
  $row[$i++]="info:INFO2,            up:UP,                 cancel:EXIT";
  $row[$i++]="left:LEFT,             enter:ENTER,           right:RIGHT";
  $row[$i++]="option:SUBMENU,        down:DOWN,             return:RETURN";
  $row[$i++]="red:RED,              :blank,                 green:GREEN";
  $row[$i++]="yellow:YELLOW,        :blank,                 blue:BLUE";
  $row[$i++]="digit_1:1,            digit_2:2,              digit_3:3";
  $row[$i++]="digit_4:4,            digit_5:5,              digit_6:6";
  $row[$i++]="digit_7:7,            digit_8:8,              digit_9:9";
  $row[$i++]="mute:MUTE,            digit_0:0,              tune:PRECH";
  $row[$i++]=":blank,               :blank,                 :blank";
  $row[$i++]="volume_up:VOLUP,      :blank,                 channel_up:CHUP";
  $row[$i++]=":VOL,                 :blank,                 :PROG";
  $row[$i++]="volume_down:VOLDOWN,  :blank,                 channel_down:CHDOWN";
  $row[$i++]=":blank,               :blank,                 :blank";
  $row[$i++]="rewind:REWIND,        play:PLAY,              fast_foreward:FF";
  $row[$i++]="stop:STOP,            pause:PAUSE,            record:REC";

# Replace spaces with no space
  for (@row)  {tr/ //d}
  
  $row[$i++]="attr rc_iconpath icons/remotecontrol";
  $row[$i++]="attr rc_iconprefix black_btn_";

  return @row;
}

# Callback from 95_remotecontrol for command layout. Creates svg layout
sub VIERA_RClayout_TV_SVG() {
  my @row;
  my $i = 0;
  
  $row[$i++]="on_off:rc_POWER.svg,            TV:rc_TV2.svg,                  AV:rc_AV.svg";
  $row[$i++]="menu:rc_MENU.svg,               display_mode:rc_ASPECT.svg,     EPG:rc_EPG.svg";
  $row[$i++]="VIERA_link:rc_VIERA_LINK.svg,   VIERA_tools:rc_VIERA_TOOLS.svg, VIERA_connect:rc_WEB.svg";
  $row[$i++]=":rc_BLANK.svg,                  :rc_BLANK.svg,                  :rc_BLANK.svg";
  $row[$i++]="info:rc_INFO2.svg,              up:rc_UP.svg,                   cancel:rc_EXIT.svg";
  $row[$i++]="left:rc_LEFT.svg,               enter:rc_dot.svg,               right:rc_RIGHT.svg";
  $row[$i++]="option:rc_OPTIONS.svg,          down:rc_DOWN.svg,               return:rc_BACK.svg";
  $row[$i++]="red:rc_RED.svg,                 :rc_BLANK.svg,                  green:rc_GREEN.svg";
  $row[$i++]="yellow:rc_YELLOW.svg,           :rc_BLANK.svg,                  blue:rc_BLUE.svg";
  $row[$i++]="digit_1:rc_1.svg,               digit_2:rc_2.svg,               digit_3:rc_3.svg";
  $row[$i++]="digit_4:rc_4.svg,               digit_5:rc_5.svg,               digit_6:rc_6.svg";
  $row[$i++]="digit_7:rc_7.svg,               digit_8:rc_8.svg,               digit_9:rc_9.svg";
  $row[$i++]="mute:rc_MUTE.svg,               digit_0:rc_0.svg,               tune:rc_BACK.svg";
  $row[$i++]=":rc_BLANK.svg,                  :rc_BLANK.svg,                 :rc_BLANK.svg";
  $row[$i++]="volume_up:rc_UP.svg,            :rc_BLANK.svg,                 channel_up:rc_UP.svg";
  $row[$i++]=":rc_VOL.svg,                    :rc_BLANK.svg,                 :rc_PROG.svg";
  $row[$i++]="volume_down:rc_DOWN.svg,        :rc_BLANK.svg,                 channel_down:rc_DOWN.svg";
  $row[$i++]=":rc_BLANK.svg,                  :rc_BLANK.svg,                :rc_BLANK.svg";
  $row[$i++]="rewind:rc_REW.svg,              play:rc_PLAY.svg,             fast_foreward:rc_FF.svg";
  $row[$i++]="stop:rc_STOP.svg,               pause:rc_PAUSE.svg,           record:rc_REC.svg";

# Replace spaces with no space
  for (@row) {tr/ //d}
  

  return @row;
}



1;

=pod
=item summary    VIERA control Panasonic TV via network
=item summary_DE Steuerung von Panasonic TV über Netzwerk
=begin html

<a name="VIERA"></a>
<h3>VIERA</h3>
<ul>  
  <a name="VIERAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; VIERA &lt;host&gt; &lt;interval&gt; &lt;pin code&gt &lt;?&gt</code>
    <br><br>
    This module controls Panasonic TV device over ethernet, old TV's and new TV's with crypted communication. 
    It's possible to change volume, switch it off, mute/unmute the TV or send commands like the ones on the remote control.
    <br><br>
    Defining a VIERA device will schedule an internal task,
    which periodically reads the status of volume and mute status and triggers notify/filelog commands.
    <br><br>
    To implement the module several steps may be needed. 
    First define the TV with PinCode &lt0000&gt, ? for the encryption and any time interval you like (60 is ok). 
    Switch TV on and wait until the module detects the encyption mode yes/no. If encryption is equal no, you are done.
    If encryption is yes execute any command like "set myTV1 off". A PinCode should be displayed on the TV. Edit the definition
    delete the "?" and replace 0000 with the PinCode. Execute the command again while the PinCode is still displayed on TV.
    You are done.
    <br>
    state: Initialized - on (green) - dormant (orange) - off (red)
    <br><br>
    This module may require further PERL libraries. For raspbian you have to enter the following commands in the terminal:<br>
    <b>sudo cpan<br>
       install MIME::Base64<br>
       install Crypt::Mode::CBC<br>
       install Digest::SHA<br>
       q </b>  for exit.<br>
    <br>
    <b>Notes:</b><br>
    <ul>Activate volume remotecontrol by DLNA: Menu -> Setup -> Network Setup -> Network Link Settings -> DLNA RemoteVolume -> On</ul>
    <br>
    Example:
    <ul><code>
      <b>define myTV1 VIERA 192.168.178.20 ## PinCode ?</b>
      <br>
      <b>define myTV1 VIERA 192.168.178.20 60 0000 ?</b>  (with custom interval of 60 seconds and start PinCode)
	  <br>
      <b>define myTV1 VIERA 192.168.178.20 60 1234</b>  (changed definition with PinCode transfered from TV)
	  <br>
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
        on_off<br>
        mute [on|off]<br>
        volume [0-100]<br>
        channel [1-9999]<br>
        input [hdmi1|hdmi2|hdmi3|hdmi4|sdCard|tv]<br>
        statusRequest<br>
        web<br>
      </code>
    </ul>
    For the web command, please use <b>https://</b> up front. Example:<br>
    set &lt;name&gt; web https://google.de<br><br>
  </ul>
  <ul>
    <br>
       Remote control commands, depending on your TV<br>
       For this application the following commands are available:<br><br>
       
		set &lt;name&gt; remoteControl .........<br><br>
       
    <ul><code>
		3D_button				=> switch to 3D mode<br>
		apps					=> show apps<br>
		aspect					=> change aspect<br>
		AV						=> switch input to AV<br>
		blue_button				=> blue button<br>
		cancel					=> cancel or clear<br>
		channel_down			=> one channel down<br>
		channel_up				=> one channel up<br>
		digit_0					=> Digit 0<br>
		digit_1					=> Digit 1<br>
		digit_2					=> Digit 2<br>
		digit_3					=> Digit 3<br>
		digit_4					=> Digit 4<br>
		digit_5					=> Digit 5<br>
		digit_6					=> Digit 6<br>
		digit_7					=> Digit 7<br>
		digit_8					=> Digit 8<br>
		digit_9					=> Digit 9<br>
		display_mode			<br>
		down					=> cursor down<br>
		enter					=> enter<br>
		EPG						=> program guide<br>
		exit					=> exit<br>
		fast_forward			=> fast foreward<br>
		favorite				=> favorites<br>
		game					<br>
		green_button			=> green button<br>
		guide					=> guide<br>
		HDMI_1					=> input HDMI 1<br>
		HDMI_2					=> input HDMI 2<br>
		HDMI_3					=> input HDMI 3<br>
		HDMI_4					=> input HDMI 4<br>
		hold					=> hold<br>
		home					=> home<br>
		index					=> index<br>
		info					=> info<br>
		last_view				=> last view<br>
		left					=> cursor left<br>
		menu					=> menu<br>
		mute					=> mute<br>
		noise_reduction			=> noise reduction<br>
		on_off					=> on off switch<br>
		option					=> option<br>
		pause					=> pause<br>
		play					=> play<br>
		program					=> program<br>
		record					=> record<br>
		red_button				=> red button<br>
		return					=> return<br>
		rewind					=> rewind<br>
		right					=> cursor right<br>
		SD_card					=> SD card<br>
		skip_next				=> skip to next<br>
		skip_previous			=> skip to previous<br>
		stop					=> stop<br>
		subtitle				=> subtitle<br>
		tune					=> tune<br>
		TV						=> TV<br>
		up						=> cursor up<br>
		videotext				=> videotext<br>
		VIERA_connect			<br>
		VIERA_link				<br>
		VIERA_tools				<br>
		volume_down				=> volume down<br>
		volume_up				=> volume up<br>
		yellow_button			=> yellow button<br>
   </code></ul>
        
	    <br><br>
		set &lt;name&gt; remoteControlApp ......<br><br>

    <ul><code>	   	
		netflix              	<br>
		youtube              	<br>
		shoutcast            	<br>
		calendar             	<br>
		browser              	<br>
		amazonprime          	<br>
		iplayer              	<br>
		bbc_iplayer          	<br>
		itv                  	<br>
		all_4                	<br>
		demand_5             	<br>
		recorded_tv          	<br>
		multi_window         	<br>
		bbc_news             	<br>
		bbc_sport            	<br>
		weather              	<br>
		developer            	<br>
    </code></ul>
    
    <br>
    Example:<br>
    <ul><code>
      set &lt;name&gt; mute on<br>
      set &lt;name&gt; volume 20<br>
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
    <code>define &lt;name&gt; VIERA &lt;host&gt; &lt;interval&gt; &lt;pin code&gt &lt;?&gt</code>
    <br><br>
    Dieses Modul steuert einen Panasonic Fernseher (unverschl&uuml;sselt oder verschl&uuml;sselt) &uuml;ber das Netzwerk.
    Es ist m&ouml;glich den Fernseher auszuschalten, die Lautst&auml;rke zu &auml;ndern oder zu muten bzw. unmuten
    oder Befehle wie auf der Fernbedinung zu senden,
    <br><br>
    Beim definieren des Ger&auml;tes in FHEM wird ein interner Timer gestartet, welcher zyklisch
    den Status der Lautst&auml;rke und des Mute-Zustand ausliest. Das Intervall des Timer kann &uuml;ber den Parameter &lt;interval&gt;
    ge&auml;ndert werden und ein notify wird eingerichtet.
    <br><br>
    Um das Modul einzurichten k&ouml;nnen mehrere Schritte notwendig sein.
    Zuerst wird das Modul definiert mit dem PinCode &lt0000&gt, ? f&uuml;r die Abfrage der Verschl&uuml;sselung und einem 
    beliebigen Zeitinterval (60 ist ok). Dann den TV einschalten und warten bis die Verschl&uuml;sselung yes/no erkannt wird.
    Wenn der TV nicht verschl&uuml;sselt ist, ist die Einrichtung abgeschlossen. Ist der TV verschl&uuml;sselt, dann bitte ein Kommando
    ausf&uuml;hren (set myTV1 off), danach wird ein PinCode am TV angezeigt. Die Definition editieren den PinCode eintragen und das ? l&ouml;schen.
    Das Kommando nochmals ausf&uuml;hren, solange der PinCode angezeigt wird. Das wars.
    <br>
    state: Initialized - on (gr&uuml;n) - dormant (orange) - off (rot)
    <br><br>
    Diese Modul ben&ouml;tigt evtl. weitere PERL Bibliotheken. F&uuml;r raspbian bitte folgende Kommandos im Terminmal eingeben:<br>
    <b>sudo cpan<br>
       install MIME::Base64<br>
       install Crypt::Mode::CBC<br>
       install Digest::SHA<br>
       q </b>  f&uuml;r exit.<br>
    <br>
    <b>Anmerkung:</b><br>
    <ul>Aktivieren von Fernbedienung der Lautst&auml;rke per DLNA: Men&uuml; -> Setup -> Netzwerk-Setup -> Netzwerkverbindungsein. -> DLNA-Fernbed. Lautst. -> Ein</ul>
    <br>
    Beispiel:
    <ul><code>
      <b>define myTV1 VIERA 192.168.178.20 ## PinCode ?</b>
      <br>
      <b>define myTV1 VIERA 192.168.178.20 60 0000 ?</b>  (mit einem Interval von 60 Sekunden und dem PinCode für den 1. Schritt)
	  <br>
      <b>define myTV1 VIERA 192.168.178.20 60 1234</b>  (mit ge&auml;ndertem PinCode wie am TV angezeigt)
	  <br>
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
        on_off<br>
        mute [on|off]<br>
        volume [0-100]<br>
        channel [1-9999]<br>
        input [hdmi1|hdmi2|hdmi3|hdmi4|sdCard|tv]<br>
        statusRequest<br>
        web<br>
    </code></ul>
    Beim Kommando web, bitte immer <b>https://</b> voranstellen. Beispiel:<br>
    set &lt;name&gt; web https://google.de<br><br>
  </ul>
  <ul>
  <br>
     Fernbedienung (Kann vielleicht nach Modell variieren).<br>
     Das Modul hat die folgenden Fernbedienbefehle implementiert:<br><br>
     
     set &lt;name&gt; remoteControl .........<br><br>     
     
    <ul><code>
		3D_button				=> in 3D Modus schalten<br>
		apps					=> apps anzeigen<br>
		aspect					=> Aspekt aendern<br>
		AV						=> Eingang auf AV umschalten<br>
		blue_button				=> blaue Taste<br>
		cancel					=> loeschen<br>
		channel_down			=> Kanal nach unten schalten<br>
		channel_up				=> Kanal nach oben schalten<br>
		digit_0					=> Zahl 0<br>
		digit_1					=> Zahl 1<br>
		digit_2					=> Zahl 2<br>
		digit_3					=> Zahl 3<br>
		digit_4					=> Zahl 4<br>
		digit_5					=> Zahl 5<br>
		digit_6					=> Zahl 6<br>
		digit_7					=> Zahl 7<br>
		digit_8					=> Zahl 8<br>
		digit_9					=> Zahl 9<br>
		display_mode			<br>
		down					=> Pfeil nach unten<br>
		enter					=> Eingabe<br>
		EPG						=> elektronische Programmzeitschrift<br>
		exit					=> beenden<br>
		fast_forward			=> vorspulen<br>
		favorite				=> Favoriten<br>
		game					<br>
		green_button			=> gruene Taste<br>
		guide					=> Programmzeitschrift<br>
		HDMI_1					=> Eingang HDMI 1<br>
		HDMI_2					=> Eingang HDMI 2<br>
		HDMI_3					=> Eingang HDMI 3<br>
		HDMI_4					=> Eingang HDMI 4<br>
		hold					=> <br>
		home					=> Startbildschirm<br>
		index					=> Index<br>
		info					=> Info<br>
		last_view				=> letzte Ansicht<br>
		left					=> Pfeil nach unten<br>
		menu					=> Menue<br>
		mute					=> Ton aus<br>
		noise_reduction			=> Rauschreduzierung<br>
		on_off					=> Ein- / Ausschalter<br>
		option					=> Option<br>
		pause					=> Pause<br>
		play					=> Abspielen<br>
		program					=> Programm<br>
		record					=> Aufnahme<br>
		red_button				=> rote Taste<br>
		return					=> zurueck<br>
		rewind					=> zurueckspulen<br>
		right					=> Pfeil nach rechts<br>
		SD_card					=> => SD Karte<br>
		skip_next				=> springe vorwaerts<br>
		skip_previous			=> springe zurueck<br>
		stop					=> Stop<br>
		subtitle				=> Untertitel<br>
		tune					=> Suchlauf<br>
		TV						=> TV<br>
		up						=> Pfeil nach oben<br>
		videotext				=> Videotext<br>
		VIERA_connect			<br>
		VIERA_link				<br>
		VIERA_tools				<br>
		volume_down				=> Lautstaerke leiser<br>
		volume_up				=> Lautstaerke lauter<br>
		yellow_button			=> gelbe Taste<br>
    </code></ul>
	
	    <br><br>
	    set &lt;name&gt; remoteControlApp ......<br><br>	

    <ul><code>	
		netflix              	<br>
		youtube              	<br>
		shoutcast            	<br>
		calendar             	<br>
		browser              	<br>
		amazonprime          	<br>
		iplayer              	<br>
		bbc_iplayer          	<br>
		itv                  	<br>
		all_4                	<br>
		demand_5             	<br>
		recorded_tv          	<br>
		multi_window         	<br>
		bbc_news             	<br>
		bbc_sport            	<br>
		weather              	<br>
		developer            	<br>

    </code></ul>
    
    <br>
    Beispiel:<br>
    <ul><code>
      set &lt;name&gt; mute on<br>
      set &lt;name&gt; volume 20<br>
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
    <li>state</li>
  </ul>
</ul>

=end html_DE



=cut
