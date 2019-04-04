##############################################################################
#
# 70_SamsungAV.pm
#
# module to send messages or commands to a Samsung TV
#
# written 2019 by k�lnsolar
# based on 70_STV which supports older generation of TV's. Thanks to Zwiebel.
# extended for newer moduls. Python script samsungctl was used as reference.
#
# $Id$
#
# Version = 1.0
#
##############################################################################

package main;
use strict;
use warnings;
use IO::Socket::INET;
use Sys::Hostname;
use MIME::Base64;
use DevIo;
use HttpUtils;

my @gets = ('dummy');

sub SamsungAV_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "SamsungAV_Define";
  $hash->{UndefFn}  = "SamsungAV_Undefine";
  $hash->{StateFn}  = "SamsungAV_SetState";
  $hash->{SetFn}    = "SamsungAV_Set";
  $hash->{AttrFn}   = "SamsungAV_Attr";
  $hash->{NotifyFn} = "SamsungAV_Notify";
  $hash->{ReadFn}   = "SamsungAV_Read";  
  $hash->{ReadyFn}  = "SamsungAV_Ready";
  $hash->{AttrList} = "callerURI screenURI delayRC delayMacro disable:0,1 " . $readingFnAttributes;;

  $data{RC_layout}{SamsungAV_TV}  = "SamsungAV_RClayout_TV";
  $data{RC_layout}{SamsungAV_TV_SVG}  = "SamsungAV_RClayout_TV_SVG";
  $data{RC_makenotify}{SamsungAV} = "SamsungAV_RCmakenotify";
}

sub SamsungAV_Define($$)
{
  my ($hash, $def) = @_;
#  DevIo_CloseDev($hash);
  my @args = split("[ \t]+", $def);

  if (int(@args) < 4)
  {
    return "[SamsungAV] Define: not enough arguments. Usage:\n" .
         "define <name> SamsungAV <host> <port>";
  }

  $hash->{Host} = $args[2];
  $hash->{Port} = $args[3];

  if ( $hash->{Port} ne "55000" && $hash->{Port} ne "52235" && $hash->{Port} ne "8000" && $hash->{Port} ne "8001" ){
	  return "[SamsungAV] Port is not supported";
  }
  if (defined $args[4]) { 
    $hash->{Mode} = $args[4];
	if (!defined ReadingsVal($args[4],"state",undef)) {  return "[SamsungAV] Define: optional DLNA device not known. $hash->{Mode} instead" }
    $hash->{".validcommands"} .= "volume:slider,0,1,100 sayText ";
  }
  else { $hash->{Mode} = undef }

  if ( $hash->{Port} eq 55000 || $hash->{Port} eq "8000" || $hash->{Port} eq "8001"){
      $hash->{".validcommands"} .= "0:noArg 1:noArg 2:noArg 3:noArg 4:noArg 5:noArg 6:noArg 7:noArg 8:noArg 9:noArg ".
"ad:noArg aspect:noArg av1:noArg av2:noArg channel:selectnumbers,0,1,99,0,lin channelDown:noArg channelUp:noArg channelList:noArg clear:noArg component1:noArg component2:noArg ".
"contents:noArg convergence:noArg cyan:noArg down:noArg enter:noArg esaving:noArg exit:noArg ff:noArg guide:noArg green:noArg hdmi:noArg hdmi1:noArg ".
"hdmi2:noArg help:noArg home:noArg info:noArg left:noArg menu:noArg mute:noArg pause:noArg pip_chdown:noArg pip_chup:noArg pip_onoff:noArg play:noArg ".
"pmode:noArg power:noArg poweroff:noArg poweron:noArg prech:noArg program:noArg red:noArg return:noArg rec:noArg rewind:noArg right:noArg sleep:noArg ".
"source:noArg stop:noArg tools:noArg ttx_mix:noArg tv:noArg tv_mode:noArg up:noArg volumeDown:noArg volumeUp:noArg yellow:noArg statusRequest:noArg ".
"0_text_line 0_macro ".  
"G_AUTO_:AUTO_ARC_ANTENNA_AIR,AUTO_ARC_ANTENNA_CABLE,AUTO_ARC_ANTENNA_SATELLITE,AUTO_ARC_ANYNET_AUTO_START,AUTO_ARC_ANYNET_MODE_OK,".
"AUTO_ARC_AUTOCOLOR_FAIL,AUTO_ARC_AUTOCOLOR_SUCCESS,AUTO_ARC_CAPTION_ENG,AUTO_ARC_CAPTION_KOR,AUTO_ARC_CAPTION_OFF,AUTO_ARC_CAPTION_ON,".
"AUTO_ARC_C_FORCE_AGING,AUTO_ARC_JACK_IDENT,AUTO_ARC_LNA_OFF,AUTO_ARC_LNA_ON,AUTO_ARC_PIP_CH_CHANGE,AUTO_ARC_PIP_DOUBLE,AUTO_ARC_PIP_LARGE,".
"AUTO_ARC_PIP_LEFT_BOTTOM,AUTO_ARC_PIP_LEFT_TOP,AUTO_ARC_PIP_RIGHT_BOTTOM,AUTO_ARC_PIP_RIGHT_TOP,AUTO_ARC_PIP_SMALL,AUTO_ARC_PIP_SOURCE_CHANGE,".
"AUTO_ARC_PIP_WIDE,AUTO_ARC_RESET,AUTO_ARC_USBJACK_INSPECT,AUTO_FORMAT,AUTO_PROGRAM ". 
"G_EXTx:EXT1,EXT2,EXT3,EXT4,EXT5,EXT6,EXT7,EXT8,EXT9,EXT10,EXT11,EXT12,EXT13,EXT14,EXT15,EXT16,EXT17,EXT18,EXT19,EXT20,EXT21,EXT22,EXT23,".
"EXT24,EXT25,EXT26,EXT27,EXT28,EXT29,EXT30,EXT31,EXT32,EXT33,EXT34,EXT35,EXT36,EXT37,EXT38,EXT39,EXT40,EXT41 ".
"G_Others:3SPEED,4_3,16_9,ADDDEL,ALT_MHP,ANGLE,ANTENA,ANYNET,ANYVIEW,APP_LIST,AV3,BACK_MHP,BOOKMARK,CALLER_ID,CAPTION,CATV_MODE,".
"CLOCK_DISPLAY,CONVERT_AUDIO_MAINSUB,CUSTOM,DEVICE_CONNECT,DISC_MENU,DMA,DNET,DNIe,DNSe,DOOR,DSS_MODE,DTV,DTV_LINK,DTV_SIGNAL,".
"DVD_MODE,DVI,DVR,DVR_MENU,DYNAMIC,ENTERTAINMENT,FACTORY,FAVCH,FF_,FM_RADIO,GAME,HDMI3,HDMI4,ID_INPUT,ID_SETUP,INSTANT_REPLAY,LINK,".
"LIVE,MAGIC_BRIGHT,MAGIC_CHANNEL,MDC,MIC,MORE,MOVIE1,MS,MTS,NINE_SEPERATE,OPEN,PANNEL_CHDOWN,PANNEL_CHUP,PANNEL_ENTER,PANNEL_MENU,".
"PANNEL_POWER,PANNEL_SOURCE,PANNEL_VOLDOW,PANNEL_VOLUP,PANORAMA,PCMODE,PERPECT_FOCUS,PICTURE_SIZE,".
"PIP_SCAN,PIP_SIZE,PIP_SWAP,PLUS100,POWER,PRINT,QUICK_REPLAY,REC,REPEAT,RESERVED1,REWIND_,RSS,RSURF,SCALE,SEFFECT,".
"SETUP_CLOCK_TIMER,SOUND_MODE,SOURCE,SRS,STANDARD,STB_MODE,STILL_PICTURE,SUB_TITLE,SVIDEO1,SVIDEO2,SVIDEO3,TOPMENU,TTX_SUBFACE,".
"TURBO,VCHIP,VCR_MODE,WHEEL_LEFT,WHEEL_RIGHT,W_LINK,ZOOM1,ZOOM2,ZOOM_IN,ZOOM_MOVE,ZOOM_OUT ";

  if($hash->{Port} ne "8000" && $hash->{Port} ne "8001") {
    my $rc = eval
    {
      require Net::Address::IP::Local;
      require IO::Interface::Simple;
      Net::Address::IP::Local->import();
      IO::Interface::Simple->import();
      1;
    };
    if($rc) {
      $hash->{MyIP} = getIP();
      $hash->{MAC} = getMAC4IP($hash->{MyIP});
    }
	else{
      Log3 $args[0], 3, "[SamsungAV] $args[0]  You are using a deprecated MAC detection mechanism using ifconfig.";
      Log3 $args[0], 3, "[SamsungAV] $args[0]  Please install Pearl Modules libnet-address-ip-local-perl and libio-interface-perl";
	  my $system = $^O;
      my $result = "";
      if($system =~ m/Win/) {
        $result = `ipconfig /all`;
        my @myarp=split(/\n/,$result);
        foreach (@myarp){
          if ( /([0-9a-f]{2}[:-][0-9a-f]{2}[:-][0-9a-f]{2}[:-][0-9a-f]{2}[:-][0-9a-f]{2}[:-][0-9a-f]{2})$/i ) {
             $result = $1;
             $result =~ s/-/:/g;
          }
        }
      }
      if($system eq "linux") {
        $result = `ifconfig -a eth0`;
        my @myarp=split(/\n/,$result);
        foreach (@myarp){
          if ( /(ether|lan|eth0) .*(..:..:..:..:..:..) .*$/ ) {
            $result = $2;
          }
        }
      }
      # Fritzbox "? (192.168.0.1) at 00:0b:5d:91:fc:bb [ether]  on lan"
      # debian   "192.168.0.1              ether   c0:25:06:1f:3c:14   C                     eth0"
      #$result = "? (192.168.0.1) at 00:0b:5d:91:fc:bb [ether]  on lan";

      $hash->{MAC} = $result;
      $hash->{MyIP} = getIP_old();
   }
  }
  else {
	eval {require JSON; 1;}
	or do {
		return "[SamsungAV] Define: Module JSON not installed. Run 'sudo apt-get install libjson-perl'";
	};
	eval {require Time::HiRes; 1;}
	or do {
		return "[SamsungAV] Define: Module Time:HiRes not installed. Check perl libraries'";
	};
#	import Time::HiRes qw(usleep);
  }
  my $dev = $hash->{DeviceName};
} 
else {
    $hash->{".validcommands"} = "mute:on,off volume:slider,0,1,100 call sms date ";
}

  $hash->{".validcommands"} .= "caller:noArg " if (defined(AttrVal($args[0], "callerURI", undef)));
  $hash->{".validcommands"} .= "screen:noArg " if (defined(AttrVal($args[0], "screenURI", undef)));

  Log3 $args[0], 3, "[SamsungAV] $args[0] defined with host: $hash->{Host} port: $hash->{Port}";
  readingsSingleUpdate($hash,"state","defined",1);
  return undef;
}

sub SamsungAV_Undefine($$) 
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  return undef;
}

sub SamsungAV_Attr(@)
{
	my @a = @_;
	my $hash = $defs{$a[1]};
	my $cmd      = $a[0];
	my $attrName = $a[2];
	my $attrParm = $a[3];
	my $mac = AttrVal($a[1], "MAC", undef);
	$hash->{MAC} = $mac if (defined($mac));
	if( defined(index($attrName,"URI"))) {
		if( $cmd eq "set" ) { 
			$hash->{".validcommands"} .= "caller:noArg " if ($attrName eq "callerURI"); 
			$hash->{".validcommands"} .= "screen:noArg " if ($attrName eq "screenURI"); 
		}
	}

    if($cmd eq "set" && $attrName eq "disable") {
        if($attrParm eq "0") {
            readingsSingleUpdate($hash, "state", "defined",0) if(exists($hash->{helper}{DISABLED}) && $hash->{helper}{DISABLED} == 1);	
			SamsungAV_Init($hash);
        }
        elsif($attrParm eq "1") {
            RemoveInternalTimer($hash);
            readingsSingleUpdate($hash, "presence", "absent",1);
            readingsSingleUpdate($hash, "state", "disabled",1);
        }
		$hash->{helper}{DISABLED} = $attrParm;
    }
    elsif($cmd eq "del" && $attrName eq "disable") {
        readingsSingleUpdate($hash, "state", "defined",0) if(exists($hash->{helper}{DISABLED}) && $hash->{helper}{DISABLED} == 1);
		SamsungAV_Init($hash);
        $hash->{helper}{DISABLED} = 0;
    }

    return undef;
}

sub SamsungAV_Init($) 
{
  my ($hash) = @_;
  
  SamsungAV_State($hash);

  RemoveInternalTimer($hash, "SamsungAV_Init");
  InternalTimer(gettimeofday()+60, "SamsungAV_Init", $hash, 0);	

}
sub SamsungAV_State($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
	my $port = $hash->{Port};
	my $param = {
				url        => "http://$hash->{Host}:$port/",
				timeout    => 5,
				hash       => $hash,
				method     => "GET",
				header     => "",  
				callback   =>  \&SamsungAV_ParseState 
				};

	HttpUtils_NonblockingGet($param);
}

sub SamsungAV_ParseState($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
#        Log3 $name, 1, "[SamsungAV] $name parameter - code: $param->{code} - error: $err";
    my ($state, $stateAV, $presence)  = "";
    $param->{code} = "" if(!defined($param->{code}));
    if($err ne "" && index($err,"empty") < 0) {    # workaround for C/D/E/F-Series still to figure out http server Port 7676(ne "" $param->{code} ne "40")  
        Log3 $name, 4, "[SamsungAV] $name not able to connect to $hash->{Host}:$hash->{Port} with $param->{url} - code: $param->{code} - error: $err";
		$state = $stateAV = $presence = "absent";
    }
    else {
        Log3 $name, 4, "[SamsungAV] $name online with $hash->{Host}:$hash->{Port} - HTTP-Response: $param->{code}";  
		$state = $stateAV = "on";
		$presence = "present";
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash, "state", $state,1);

    if (defined($hash->{Mode})) {
      my $mute = ReadingsVal($hash->{Mode},"mute","not found");
      if($mute eq "1")     {$mute = "on"}
      elsif ($mute eq "0") {$mute = "off"}	
      if ($presence ne "absent") {
		my $DLNAstate = ReadingsVal($hash->{Mode},"state","not found");
		if ($mute eq "on") { $stateAV = "muted" }
		elsif ($DLNAstate ne "online") { $stateAV = $DLNAstate }
      }
      readingsBulkUpdateIfChanged($hash, "stateAV", $stateAV);
      readingsBulkUpdateIfChanged($hash, "presence", $presence);
      readingsBulkUpdateIfChanged($hash, "mute", $mute);
      readingsBulkUpdateIfChanged($hash, "volume", ReadingsVal($hash->{Mode},"volume","not found"));
	  readingsBulkUpdateIfChanged($hash, "friendlyName", ReadingsVal($hash->{Mode},"friendlyName","not found"));
	  readingsBulkUpdateIfChanged($hash, "modelName", ReadingsVal($hash->{Mode},"modelName","not found"));
	}
    readingsEndUpdate($hash, 1);
 }

sub SamsungAV_Notify($$)
{
    my ($hash,$dev) = @_;

    return undef if(!defined($hash) or !defined($dev));

    my $name = $hash->{NAME};
    my $dev_name = $dev->{NAME};

    return undef if(!defined($dev_name) || !defined($name));

    my $events = deviceEvents($dev,1);

    if($dev_name eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
       if(!exists($hash->{helper}{DISABLED}) || $hash->{helper}{DISABLED} == 0) {
			Log3 $name, 3, "[SamsungAV] device $name initialising....";
			SamsungAV_Init($hash); 
			SamsungAV_Tizen_App_list($hash) if ($hash->{Port} ne "8000");
		}
    }
}

sub SamsungAV_Ready($)
{
  my ($hash) = @_;
  if(AttrVal($hash->{NAME},'fork','disable') eq 'enable') {
  } 
  else {
    Log3 $hash->{NAME}, 5, "[SamsungAV] $hash->{NAME} SamsungAV_Ready(connection seems to be closed) OpenDev for DeviceName: $hash->{DeviceName}";
  }
  return undef;
}

sub SamsungAV_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  $val = $1 if($val =~ m/^(.*) \d+$/);
#  return "Undefined value $val" if(!defined($it_c2b{$val}));
  return undef;
}

sub SamsungAV_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 3, "[SamsungAV] $name SamsungAV_Read: connection DeviceName $hash->{DeviceName} may be closed";
}

sub SamsungAV_Set($@)
{
  my ($hash, @a) = @_;
  my $nam = shift @a;
  my $name = $hash->{NAME};
  my $Port = $hash->{Port};
  my $Mode = $hash->{Mode};
  my $cmd = (defined($a[0]) ? shift @a : ""); #command
  my $par = (defined($a[0]) ? shift @a : ""); #1 parameter
  my %translate =  ("channelDown" => "CHDOWN", 
		"channelUp" => "CHUP",
		"channelList" => "CH_LIST", 
		"volumeDown" => "VOLDOWN",
		"volumeUp" => "VOLUP"   );
	
  if ($cmd eq "?" || $cmd eq "") {
       return $hash->{".validcommands"};
  }

  $cmd = $par if (substr($cmd,0,2) eq "G_" );

  if ($hash->{".validcommands"} =~ /$cmd/) {
	$cmd = $translate{$cmd}  if (defined($translate{$cmd})); 
    if ($cmd eq "statusRequest") {
		SamsungAV_Tizen_App_list($hash) if ($hash->{Port} ne "8000");
		return SamsungAV_State($hash);    # query connection state
    }
	# screen message via DLNA caller or individual
	return "$name currently not available. Try later. " if (ReadingsVal($name,"state","not found") ne "on" && !($cmd eq "power" || $cmd eq "poweron" ));
# screen message, absolute volume, TTS via DLNARenderer
	if (defined $Mode) {
	   my $command = "";
	   if  ($cmd eq "caller" ||
		    $cmd eq "screen") {
			my $URI ="";
			if ( $cmd ne "caller" ) {$URI = AttrVal($name, "screenURI", undef)}
			else                    {$URI = AttrVal($name, "callerURI", undef)}
			$command = "set ".$hash->{Mode}." stream ".$URI;
			readingsSingleUpdate($hash, "currentMedia", $URI, 1);
        }
	    elsif ($cmd eq "volume") {
	        $command = "set ".$hash->{Mode}." volume ".$par;
        }
	    elsif ($cmd eq "sayText") {
			$par = '"'.$par.' '.join(" ", @a).'"';
	        $command = "set ".$hash->{Mode}." speak ".$par;
        }
		if ($command ne "") { 
			Log3 $name, 4, "[SamsungAV] $name call DLNA-Renderer. Command: $command";
			return SamsungAV_DLNA($hash,$command) 
		}
	}

	if ($cmd eq "channel") {
	    if($par < 10){$cmd = $par}
		else {
			$cmd = "0_macro";
	        $par = substr($par,0,1). "," . substr($par,1,1);
        }
	}
# App functionality for Samsung Tizen since K-Series
	return SamsungAV_Tizen_App($hash,$name,$cmd,$par) if (substr($cmd,0,5) eq "0_App" ); 
# RC commands
	if ($Port eq 55000 ){
		return SamsungAV_55000($hash,$name,$cmd,$par);
	}
	elsif ($Port eq 52235 ){
		return SamsungAV_52235($hash,@_);
	}
	elsif ($Port eq 8001 ){
		return SamsungAV_Tizen_RC($hash,$name,$cmd,$par);
	}
	elsif ($Port eq 8000 ){
		return SamsungAV_Tizen_RC($hash,$name,$cmd,$par);
	}
  }
  else {
    my $ret = "[SamsungAV] Invalid command $cmd. Use any of:\n";
    my @cmds = split(" ",$hash->{".validcommands"});
    foreach my $line (0..$#cmds) {
      $ret .= "\n" if ($line > 1 && $line/10 == int($line/10));
      $ret .= $cmds[$line]." ";
    }
    return $ret;
  }
  return undef;
}

# Samsung Tizen Models
sub SamsungAV_Tizen_RC($$$$)
{
 my ($hash,$name,$cmd,$par) = @_;
    
 Log3 $name, 5, "[SamsungAV] $name command ".$cmd. " parameter ".$par;

 my $dev		= $hash->{Host};
 my $wsport     = $hash->{Port};
 my ($payload);

 if($cmd ne "0_macro") 	{@ARGV = split(" ",$cmd)}
 else			       	{@ARGV = split(",",$par)}

# screen message caller or individual via Webbrowser
if ( $cmd eq "caller" ||
     $cmd eq "screen") {
	return SamsungAV_7676($hash,$cmd) if ($wsport ne "8001");
	return SamsungAV_Tizen_App($hash, $name,$cmd,"Internet");
}

(my $msg, my $socket) = &SamsungAV_Tizen_websocket_open($hash,$name);

if ($msg ne "101") {return $msg}
else {
	syswrite $socket, build_frame (0, 1, 0, 0, 0, 0x1, '1::/com.samsung.companion') if ($wsport != 8001);
    eval {require Time::HiRes; 1;}
	or do {
		return "[SamsungAV] Module Time:HiRes not installed. Check perl libraries";
	};
	foreach my $argnum (0 .. $#ARGV) {	
	if ($argnum > 0) {
           Time::HiRes::usleep(AttrVal($name, 'delayMacro', 300000));
        }
        else {Time::HiRes::usleep(AttrVal($name, 'delayRC', 0)); }
		if ($ARGV[$argnum] ne "") {
			# Send remote key(s)
			Log3 $name, 4, "[SamsungAV] $name sending ".uc($ARGV[$argnum]);
			if ($wsport != 8001) {
				$payload = $hash->{".commands"}[$argnum];
			}
			else {
				$payload = JSON::encode_json({
					"method" => "ms.remote.control",
					"params" => {
						"Cmd" => "Click",
						"DataOfCmd" => "KEY_".uc($ARGV[$argnum]),
						"Option" => "false",
						"TypeOfRemote" => "SendRemoteKey"
					}
				});
			}
			SamsungAV_Tizen_write_payload($socket, $payload, $name);
#           BlockingCall("SamsungAV_execSamsungCtl", $name."|".$hash->{Host}."|".$ARGV[$argnum]);
		}
		else {Log3 $name, 4, "[SamsungAV] $name sending pause"}
	}
	SamsungAV_Tizen_websocket_close($socket);			
}

return undef;
}

# Samsung Tizen open websocket
sub SamsungAV_Tizen_websocket_open($$)
{
	my ($hash,$name) = @_;
		
	my $dev		= $hash->{Host};
	my $port    = $hash->{Port};
	my ($msg,$webclient_header,$path,$socket);
	my $token = ReadingsVal($name,".token",undef);  #  (my $error, my $token) = getKeyValue($name."token"); #
	if ($port != 8001) {
#   $hash->{Port} = 8443;
		$path = SamsungAV_Tizen_Encrypt_Init($hash,$name);
#   $hash->{Port} = $port;
		return $path if (substr($path,0,11) eq "[SamsungAV]");
		$webclient_header = "GET " . $path ." HTTP/1.1\r\n";
		$socket = IO::Socket::INET->new(PeerAddr=>"$dev:$port", Timeout=>2, Blocking=>1, ReuseAddr=>1);
#   $port = 8443; # secure port  8002 since K-series, 8443 for H-/J-Series
		Log3 $name, 4, "[SamsungAV] HTTP socket-connection to $name. Reply: ". $socket->error();
	}
	else {
		eval {require IO::Socket::SSL; 1;}
		or do {
			return "[SamsungAV] Set: Module IO::Socket::SSL not installed. Check perl libraries";
		};
#	   	$webclient_header = "GET /api/v2/channels/samsung.remote.control?name=RkhFTVJlbW90ZQ== HTTP/1.1\r\n";
		$webclient_header = "GET /api/v2/channels/samsung.remote.control?name=RkhFTVJlbW90ZQ==";
#	   	$webclient_header .= "&token=$hash->{token}" if (defined($hash->{token})) ;			 #temporary
		readingsSingleUpdate($hash, ".token", $hash->{token},0) if (defined($hash->{token}));        #temporary
		$webclient_header .= "&token=$token" if (defined($token)); 
		$webclient_header .= " HTTP/1.1\r\n";
		$port = 8002; # secure port  8002 since K-series, 8443 for H-/J-Series
		$IO::Socket::SSL::DEBUG = 3 if(AttrVal($name,"verbose","0") eq "5");
		$IO::Socket::SSL::DEBUG = 2 if(AttrVal($name,"verbose","0") eq "4");
		$socket = IO::Socket::SSL->new(PeerAddr=>"$dev:$port", SSL_verify_mode=>0,Timeout=>2, Blocking=>1, ReuseAddr=>1);
		Log3 $name, 4, "[SamsungAV] HTTP socket-connection to $name. SSL_Reply: ". IO::Socket::SSL::errstr();
		$IO::Socket::SSL::DEBUG = 0;   # stop detailed debug lines
	}

	if($socket) {
		Log3 $name, 4, "[SamsungAV] HTTP socket-connection to $name successful.";
		$webclient_header .= "Upgrade: websocket" . "\r\n" .
							"Connection: Upgrade" . "\r\n" .
							"Host: $dev:$port" . "\r\n" .
	#							"Origin: $dev:$port" . "\r\n" .
							"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" . "\r\n" .
							"Sec-WebSocket-Version: 13" . "\r\n\r\n";
		Log3 $name, 5, "[SamsungAV] $name send to TV: " . $webclient_header;	
		my $written  = syswrite $socket, $webclient_header;
		Log3 $name, 3, "[SamsungAV] $name header written with error $!" if (!defined($written));
		my $read = sysread $socket, my $buf, 10240;
		Log3 $name, 3, "[SamsungAV] $name read response with error $!" if (!defined($read));
		Log3 $name, 5, "[SamsungAV] $name first websocket response: $buf";
		$buf =~ /^[^ ]+ ([\d]{3})/;
		if (!defined($1)) {
			$msg = "[SamsungAV] HTTP websocket-connection to $name not successful; undefined response $buf of device";
			Log3 $name, 2, $msg; 
			return $msg;
		} 
		my $sysbytes ="";
		$buf = "";
		if ($port != 8000) {
		do {
			$sysbytes .= $buf;
 			$read = sysread $socket, $buf, 1;
			Log3 $name, 3, "[SamsungAV] $name read response with error $!" if (!defined($read));
		} until $buf eq "{";
		Log3 $name, 5, "[SamsungAV] $name Statusbytes of second websocket response: " . unpack('H*', $sysbytes);
		}
		$read = sysread $socket, $buf, 10240;
		Log3 $name, 3, "[SamsungAV] $name read response with error $!" if (!defined($read));
		$buf = "{" . $buf;
		Log3 $name, 5, "[SamsungAV] $name data of second websocket response: $buf";
#		$read = sysread $socket, $buf, 3;
#		Log3 $name, 3, "[SamsungAV] $name data of third read websocket error response: $!, data: ".unpack('H*', $buf)." , bytecount = $read";
#		$read = sysread $socket, $buf, 10240;
#		Log3 $name, 3, "[SamsungAV] $name data of fourth read websocket response: $buf, bytecount = $read";
		if ($1 eq '101') {
		   if ($port != 8000) {

#			my $line = '{"data":{"clients":[{"attributes":{"name":"RkhFTVJlbW90ZQ==","token":"14576607"},"connectTime":1542049383707,"deviceName":"RkhFTVJlbW90ZQ==","id":"c376a63e-61aa-4e73-b72e-7cb26596f9e7","isHost":false}],"id":"c376a63e-61aa-4e73-b72e-7cb26596f9e7","token":"11142450"},"event":"ms.channel.connect"}';
			my $json = eval{JSON::decode_json($buf)};
			if (defined($json->{data}->{token})) {
#	   			$hash->{token} = $json->{data}->{token};		#temporary
 				readingsSingleUpdate($hash, ".token", $json->{data}->{token},0); # setKeyValue($name."token", $json->{data}->{token}); #    
	   			Log3 $name, 5, "[SamsungAV] $name token: $json->{data}->{token} saved";
			}
		   }
			if ($buf =~ /timeOut/) {
				$msg = "[SamsungAV] $name connected but authorization timed out. Didn't you see the pop-up on TV ? ";
			}
			elsif ($buf =~ /unauthorized/) {
				$msg = "[SamsungAV] $name connected but authorization failed. Check authorizations of TV";
			}
			elsif ($buf =~ /touchDisabled/) {   # Trs received events ms.remote.touchDisable after committing new authorization request
				$msg = "[SamsungAV] $name connected but authorization failed as touchDisabled. Check authorizations of TV. Token deleted.";
	   			readingsDelete($hash, ".token") if (defined($token)); 
			}
			else {return ("101", $socket);}
			Log3 $name, 3, $msg; 
			SamsungAV_Tizen_websocket_close($socket);
			return $msg;
			}

		else {
			$msg = "[SamsungAV] HTTP websocket-connection to $name not successful; invalid response to websocket upgrade request";
			Log3 $name, 2, $msg; 
			return $msg;
		} 
	}
	else {
		$msg = "[SamsungAV] HTTP socket-connection to $name not successful. "; 
		$msg .= "SSL_Error: ". IO::Socket::SSL::errstr()   if ($port != 8000);
		#		$msg = "[SamsungAV] HTTP socket-connection to $name not successful. SSL_Error: ". $IO::SOCKET::SSL::SSL_Error . " SSL_Error: " .$SSL_Error . " IO_Error: " .$socket->error();
		Log3 $name, 2, $msg; 
		return $msg;
	} 

}
# Samsung Tizen close websocket
sub SamsungAV_Tizen_websocket_close($)
{
	my ($socket) = @_;
	syswrite $socket, build_frame (0, 1, 0, 0, 0, 0x8, '');			
	shutdown $socket, 2;
}

# Samsung Tizen write_payload
sub SamsungAV_Tizen_write_payload($$$)
{
	my ($socket, $payload, $name) = @_;
	syswrite $socket, build_frame (0, 1, 0, 0, 0, 0x1, $payload);
	Log3 $name, 5, "[SamsungAV] $name send payload: " . $payload;
}

# Initialization of H-, J-Series with encrypted websocket access
sub SamsungAV_Tizen_Encrypt_Init($$)
{
 my ($hash,$name) = @_;

 my $dev		= $hash->{Host};
 my $wsport     = $hash->{Port};

 my $msg = SamsungAV_Tizen_Encrypt($hash,$name);
 return $msg if (defined($msg));

 my $millis = int ([gettimeofday] * 1000);
 my ($err, $ret) = HttpUtils_BlockingGet ({
	url     => "http://$dev:$wsport/socket.io/1/?t=$millis",
	method  => 'GET'
    });

if( defined($err) && $err ) {
	$msg = "[SamsungAV] $name: Error getting websocket url";
	Log3 $name, 2, $msg;
	return $msg;
}

unless ($ret =~ m/:websocket,/i) {
	$msg = "[SamsungAV] $name: Content error in websocket url $err";
	Log3 $name, 2, $msg;
	return $msg;
}

my $websocket_url = "ws://$dev:$wsport/socket.io/1/websocket/" . (split(':', $ret))[0];

unless ( $websocket_url =~ /^ws:\/\/([^:\/]+):(\d+)(\/.+)$/ ) {
	$msg = "[SamsungAV] $name: Error websocket url $websocket_url"; 
	Log3 $name, 2, $msg;
	return $msg;
}

my ($host, $port, $path) = ($1, $2, $3);

Log3 $name, 4, "[SamsungAV] $name: websocket path $path";

return $path;
}		
# command encryption of H-, J-Series
sub SamsungAV_Tizen_Encrypt($$)
{
 my ($hash,$name) = @_;

 my $dev		= $hash->{Host};
 my $msg;

 my $KEYfile 	= $hash->{NAME} . "_session_key.txt";
 
#====================================================================================
#Read key and session-id from file, previously created with regapp.pl

my $json; my $enc_key; my $line; my $session = '';

unless ( -e $KEYfile) {
	$KEYfile = "samsung_session_key.txt";
}
	
if (open (KEY, $KEYfile)) {
	$line = <KEY>;
	close (KEY);
}
else  {
    $msg = "[SamsungAV] $name: ERROR cannot open file for input the session key.";
    Log3 $name, 1, $msg;
	return $msg;
}
eval {require Crypt::Rijndael; 1;}
or do {
	$msg = "[SamsungAV] $name: Module Crypt::Rijndael not installed. Run 'sudo apt-get install libcrypt-rijndael-perl'";
	Log3 $name, 1, $msg; 
	return $msg;
};


if (JSON::decode_json($line)) {
	$json = JSON::decode_json($line);
	$enc_key = $json->{session_key}; Log3 $name, 5, "session_key: ".$enc_key;
	$session = $json->{session_id};  Log3 $name, 5, "session_id:  ".$session;
}
else  {
    $msg = "[SamsungAV] $name: ERROR: $line is no JSON.";
    Log3 $name, 1, $msg;
	return $msg;
}

# unhexlify key
$enc_key =~ s/([a-fA-F0-9]{2})/chr(hex($1))/eg;

my ($cipher, $command_bytes, @chars, $int_array, $command);
undef $hash->{".commands"};
foreach (@ARGV) { # generate command array
	if ($_ ne "") {
		$_ = 'KEY_' . uc($_) if ( $_ !~ m/^KEY_/ );
		Log3 $name, 5, "[SamsungAV] $name: generate command for key '$_'";
		# generate json
		$json = '{"method":"POST","body":{"plugin":"RemoteControl","param1":"uuid:12345","param2":"Click","param3":"' . $_ . '","param4":false,"api":"SendRemoteKey","version":"1.000"}}';
		# encrypt json
		$json = $json . chr(16 - length($json)%16) x ( 16 - length($json)%16 ); # padding
		$cipher = Crypt::Rijndael->new( $enc_key, Crypt::Rijndael::MODE_ECB() );
		$command_bytes = $cipher->encrypt($json); 
		# generate command
		@chars = $command_bytes =~ /./sg; foreach (@chars) { $_ = ord($_); }
		$int_array = join (',', @chars);		
		$command = '5::/com.samsung.companion:{"name":"callCommon","args":[{"Session_Id":' . $session . ',"body":"[' . $int_array . ']"}]}';
	}
	else {$command = $_}
	Log3 $name, 5, "[SamsungAV] $name: command: '$command'";	
	push @{$hash->{".commands"}} , $command; # save command to array
}		
return undef;
}

sub build_frame {

	my ($masked, $fin, $rsv1, $rsv2, $rsv3, $op, $payload) = @_;

	# Head
	my $head = $op + ($fin ? 128 : 0);
	$head |= 0b01000000 if $rsv1;
	$head |= 0b00100000 if $rsv2;
	$head |= 0b00010000 if $rsv3;
	my $frame = pack 'C', $head;

	# Small payload
	my $len = length $payload;
	if ($len < 126) {
		$frame .= pack 'C', $masked ? ($len | 128) : $len;
	}

	# Extended payload (16-bit)
	elsif ($len < 65536) {
		$frame .= pack 'Cn', $masked ? (126 | 128) : 126, $len;
	}

	# Extended payload (64-bit with 32-bit fallback)
	else {
		$frame .= pack 'C', $masked ? (127 | 128) : 127;
		$frame .= pack('NN', 0, $len & 0xffffffff);
		#$frame .= MODERN ? pack('Q>', $len) : pack('NN', 0, $len & 0xffffffff);
	}

	# Mask payload
	if ($masked) {
		my $mask = pack 'N', int(rand 9 x 7);
		$payload = $mask . xor_encode($payload, $mask x 128);
	}

	return $frame . $payload;
}

# Samsung Tizen Model App list
sub SamsungAV_Tizen_App_list($)
{
 my ($hash) = @_;
 my $dev    = $hash->{Host};
 my $port   = $hash->{Port};
 my $name   = $hash->{NAME};
 
 return undef if ($hash->{STATE} ne "on");

 my ($msg, $payload, $webclient_header, $socket, $appnames);

 ($msg, $socket) = &SamsungAV_Tizen_websocket_open($hash,$name); 

 if ($msg ne "101") {return $msg}
 else {
	$payload = JSON::encode_json({
			"method" => "ms.channel.emit",
			"params" => {
				"event"        => "ed.installedApp.get",
				"to"           => "host",
				"TypeOfRemote" => "SendRemoteKey"
			}
	});
	SamsungAV_Tizen_write_payload($socket, $payload, $name);
	sysread $socket, my $buf, 4;                         # read hex header first
	Time::HiRes::usleep(500000);                         # just to get all data, otherwise crashing FHEM
	sysread $socket, $buf, 10240;
	Log3 $name, 5, "[SamsungAV] response $name to write_payload: $buf";
	SamsungAV_Tizen_websocket_close($socket);	
	my $json = eval {decode_json($buf)};

	if (   ref($json->{data}{data}) eq "ARRAY" ) {
		Log3 $name, 5, "[SamsungAV] ARRAY found";
        foreach my $rec (@{$json->{data}{data}}) {
#			Log3 $name, 3, "[SamsungAV] Application: $rec";
#			Log3 $name, 3, "[SamsungAV] Application: $rec->appId";
			Log3 $name, 5, '[SamsungAV] Application: '  . $rec->{"name"} . '  Id: ' . $rec->{"appId"};
			$rec->{"name"} =~ tr/A-Za-z0-9#.-_//cd;        # remove spaces an other characters
			$appnames .= $rec->{"name"} . ",";
			$hash->{helper}{app}{$rec->{"name"}} = $rec->{"appId"};
		}
		$hash->{".validcommands"} .= "0_App_start:" . $appnames . " 0_App_state:" . $appnames . " ";
	}
	else {
		Log3 $name, 3, "[SamsungAV] $name timelag to reach all json data for app list might be too small";
	}
}	

return undef;
}
# Samsung Tizen Model App commands
sub SamsungAV_Tizen_App($$$$) 
{
	my ($hash, $name, $cmd, $par) = @_;
	my $dev		= $hash->{Host};
	my $port	= $hash->{Port};
	my ($msg, $payload, $socket,$method,$action_type);
	if (substr($cmd,0,5) eq "0_App" &&        #App command, otherwise internal call(e.g. caller, screen...)
	    substr($cmd,9,1) ne "r") {         #not start command
		if (substr($cmd,9,1) ne "p") {         #status command
		   $method = "GET"
		}
		else {$method = "GET"}		#stop command
		my $param = {url        => "http://$dev:$port/ws/apps/$par",
				timeout    => 5,
		#		hash       => $hash,
				method     => $method,
				header     => "",  
		#		callback   =>  \&SamsungAV_Tizen_App_callback 
		};
		#	HttpUtils_NonblockingGet($param);
		my ($err, $data) = HttpUtils_BlockingGet($param);
		if ($method eq "GET") {
		   my $stateapp;
		   if ($data =~ m/running/) {$stateapp = "running"}
		   else 					{$stateapp = "stopped"}
		   $msg = "[SamsungAV] $name: state of app $par:  $stateapp";
		   Log3 $name, 4, $msg;
		   return $msg;
		}
	}
	else {
	#	$method = "POST"}		#start command ; only useable for selected Apps(Netflix, YouTube) to be used with simple http_request
 		($msg, $socket) = &SamsungAV_Tizen_websocket_open($hash,$name);
		if ($msg ne "101") {return $msg}
		else {
#			if ($hash->app_type ne "4") {$action_type = "DEEP_LINK"}
#			else 					 {$action_type = "NATIVE_LAUNCH"}
			my $URI = "";
			if ($par ne "Internet") {$action_type = "DEEP_LINK"}
			else  {
				if ( $cmd eq "caller" ) {$URI = AttrVal($name, "callerURI", undef)}
				elsif ( $cmd eq "screen" ) {$URI = AttrVal($name, "screenURI", undef)}
				Log3 $name, 4, "[SamsungAV] $name browser access with URI: $URI";
				$action_type = "NATIVE_LAUNCH"
			}
			$payload = JSON::encode_json({
						"method" => "ms.channel.emit",
						"params" => {
							"event" => "ed.apps.launch",
							"to" => "host",
							"data" => {
								"appId" => $hash->{helper}{app}{$par}, 
###								"appId" => "org.tizen.browser",   # app_type 4 --> $action_type = "NATIVE_LAUNCH"; with link in metaTag possible
##								"appId" => "3201710015067",   # app_type 1 --> $action_type = "DEEP_LINK"; Universal Guide
##								"appId" => "3201710015016",   # app_type 1 --> $action_type = "DEEP_LINK"; SmartThings
##								"appId" => "3201710015037",   # app_type 1 --> $action_type = "DEEP_LINK"; Gallery
#								"appId" => "111299001912",    # app_type 2 --> $action_type = "DEEP_LINK"; YouTube
#								"name" => "YouTube", 						#doesn't work
								"action_type" => $action_type,
								"metaTag" => $URI
							},
							"TypeOfRemote" => "SendRemoteKey"
						} 
			});
			SamsungAV_Tizen_write_payload($socket, $payload, $name);
			sysread $socket, my $buf, 10240;
			Log3 $name, 5, "[SamsungAV] response $name to write_payload: $buf";
			SamsungAV_Tizen_websocket_close($socket);	
		}	
	}
return undef;
}

# old Samsung Models
sub SamsungAV_52235($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $TV = $hash->{Host};
  my $count = @a;
  my $arg    = lc($a[2]);      # mute volume
  my $cont1  = ucfirst($arg);  # Mute
  my $cont2 = ""; 
  my $cont3 = "";
  my $cont4 = "";
  my $cont5 = "";
  my $cont6 = "";
  my $cont7 = "";
  my $cont8 = "";
  my $cont9 = "";
  
  if (defined $a[3]) { $cont2 = $a[3]}
  if (defined $a[4]) { $cont3 = $a[4]}
  if (defined $a[5]) { $cont4 = $a[5]}
  if (defined $a[6]) { $cont5 = $a[6]}
  if (defined $a[7]) { $cont6 = $a[7]}
  if (defined $a[8]) { $cont7 = $a[8]}
  if (defined $a[9]) { $cont8 = $a[9]}

  my $head = "";
  my $callsoap = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n".
                 "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" >\r\n".
				 "<s:Body>\r\n";

  my $kind = 0;

  if ( $arg eq "mute" )
  { 
    $kind = 1;
    if ( $cont2 eq "off" ){
      $cont2 = 0 ;
    }else {
      $cont2 = 1 ;
    }
  }
  if ( $arg eq "volume")
  { 
    if ( $cont2 > 0 and $cont2 < 100 ){
      $kind = 1;
    }else {
      Log3 $name, 3, "[SamsungAV] $name Volume: not correct"; 
      $kind = 0;
    }
  }
  if ( $kind eq 1){
    $callsoap .= "<ns0:Set$cont1 xmlns:ns0=\"urn:schemas-upnp-org:service:RenderingControl:1\">\r\n";
    $callsoap .= "<InstanceID>0</InstanceID>\r\n";
    $callsoap .= "<Desired$cont1>$cont2</Desired$cont1>\r\n";
    $callsoap .= "<Channel>Master</Channel>\r\n";
    $callsoap .= "</ns0:Set$cont1>\r\n";

    $head .= "POST /upnp/control/RenderingControl1 HTTP/1.1\r\n";
    $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
    $head .= "SOAPACTION: \"SoapAction:urn:schemas-upnp-org:service:RenderingControl:1#Set$cont1\"\r\n";
  }
  else {
    my $body = "";
	my $operator = "";
    my $calldate=`date +"%Y-%m-%d"`;
    chomp($calldate);
    my $calltime=`date +"%H:%M:%S"`;
    chomp($calltime);
#	if ( $arg ne "del")
#    {
		$operator = "Add";
#    }
#	else 
#	{
#		$kind = 5;
#		$operator = "Remove";
#    }		
	$head .= "POST /PMR/control/MessageBoxService HTTP/1.1\r\n";
    $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
    $head .= "SOAPACTION: \"urn:samsung.com:service:MessageBoxService:1#".$operator."Message\"\r\n";
	$callsoap .= "<u:".$operator."Message xmlns:u=\"urn:samsung.com:service:MessageBoxService:1\\\">\r\n";
	$callsoap .= "<MessageType>text/xml</MessageType>\r\n";
	$callsoap .= "<MessageID>1334799348</MessageID>\r\n";
	$callsoap .= "<Message>\r\n";
    if ( $arg eq "call")
    {
		$kind = 2;
		$callsoap .= "&lt;Category&gt;Incoming Call&lt;/Category&gt;\r\n";
		$callsoap .= "&lt;DisplayType&gt;Maximum&lt;/DisplayType&gt;\r\n";
		$callsoap .= "&lt;CallTime&gt;\r\n";
		$callsoap .= "&lt;Date&gt;$calldate&lt;/Date&gt;\r\n";
		$callsoap .= "&lt;Time&gt;$calltime&lt;/Time&gt;\r\n";
		$callsoap .= "&lt;/CallTime&gt;\r\n";
		$callsoap .= "&lt;Callee&gt;\r\n";
		$callsoap .= "&lt;Name&gt;An: $cont4&lt;/Name&gt;\r\n";
		$callsoap .= "&lt;Number&gt;Nr: $cont5&lt;/Number&gt;\r\n";
		$callsoap .= "&lt;/Callee&gt;\r\n";
		$callsoap .= "&lt;Caller&gt;\r\n";
		$callsoap .= "&lt;Name&gt;Von: $cont2&lt;/Name&gt;\r\n";
		$callsoap .= "&lt;Number&gt;Nr: $cont3&lt;/Number&gt;\r\n";
		$callsoap .= "&lt;/Caller&gt;\r\n";
    }
    if ( $arg eq "sms")
    {
		$kind = 3;
		for my $i (6..$count){
		  $body .= $a[$i];
		  $body .= " ";
		} 	 
		$callsoap .= "&lt;Category&gt;SMS&lt;/Category&gt;\r\n";
		$callsoap .= "&lt;DisplayType&gt;Maximum&lt;/DisplayType&gt;\r\n";
		$callsoap .= "&lt;ReceiveTime&gt;\r\n";
		$callsoap .= "&lt;Date&gt;$calldate&lt;/Date&gt;\r\n";
		$callsoap .= "&lt;Time&gt;$calltime&lt;/Time&gt;\r\n";
		$callsoap .= "&lt;/ReceiveTime&gt;\r\n";
		$callsoap .= "&lt;Receiver&gt;\r\n";
		$callsoap .= "&lt;Name&gt;An: $cont4&lt;/Name&gt;\r\n";
		$callsoap .= "&lt;Number&gt;Nr: $cont5&lt;/Number&gt;\r\n";
		$callsoap .= "&lt;/Receiver&gt;\r\n";
		$callsoap .= "&lt;Sender&gt;\r\n";
		$callsoap .= "&lt;Name&gt;Von: $cont2&lt;/Name&gt;\r\n";
		$callsoap .= "&lt;Number&gt;Nr: $cont3&lt;/Number&gt;\r\n";
		$callsoap .= "&lt;/Sender&gt;\r\n";
		$callsoap .= "&lt;Body&gt;Inhalt: $body&lt;/Body&gt;\r\n";
	} 
    if ( $arg eq "date")
    {
		$kind = 4;
		for my $i (10..$count){
		  $body .= $a[$i];
		  $body .= " ";
		} 
		$callsoap .= "&lt;Category&gt;Schedule Reminder&lt;/Category&gt;\r\n";
		$callsoap .= "&lt;DisplayType&gt;Maximum&lt;/DisplayType&gt;\r\n";
		$callsoap .= "&lt;StartTime&gt;\r\n";
		$callsoap .= "&lt;Date&gt;$cont2&lt;/Date&gt;\r\n";
		$callsoap .= "&lt;Time&gt;$cont3&lt;/Time&gt;\r\n";
		$callsoap .= "&lt;/StartTime&gt;\r\n";
		$callsoap .= "&lt;Owner&gt;\r\n";
		$callsoap .= "&lt;Name&gt;Fr: $cont4&lt;/Name&gt;\r\n";
		$callsoap .= "&lt;Number&gt;Nr: $cont5&lt;/Number&gt;\r\n";
		$callsoap .= "&lt;/Owner&gt;\r\n";
		$callsoap .= "&lt;Subject&gt;Betreff: $cont6&lt;/Subject&gt;\r\n";
		$callsoap .= "&lt;EndTime&gt;\r\n";
		$callsoap .= "&lt;Date&gt;$cont7&lt;/Date&gt;\r\n";
		$callsoap .= "&lt;Time&gt;$cont8&lt;/Time&gt;\r\n";
		$callsoap .= "&lt;/EndTime&gt;\r\n";
		$callsoap .= "&lt;Location&gt;Ort: $cont9&lt;/Location&gt;\r\n";
		$callsoap .= "&lt;Body&gt;Inhalt: $body&lt;/Body&gt;\r\n";
    }
	$callsoap .= "</Message>\r\n";
	$callsoap .= "</u:".$operator."Message>\r\n";
  }
  if ( $kind ne 0 ){
	return soap_call($hash,$head,$callsoap,52235);
  }else{
    return "Unknown argument, choose one of mute:on,off volume:slider,0,1,100 call sms date";
  }
}

# new Samsung Models
sub SamsungAV_55000($$$$)
{
  my ($hash,$name,$cmd,$par) = @_;

  if($cmd ne "0_macro")  {@ARGV = split(" ",$cmd)}
  else			       			{@ARGV = split(",",$par)}
  #### Configuration
  my $tv    = "UE46ES8090";  # Might need changing to match your TV type  #"UE46ES8090"
  my $port  = $hash->{Port}; # TCP port of Samsung TV
  my $tvip  = $hash->{Host}; # IP Address of TV #"192.168.2.124"
  my $myip  = $hash->{MyIP}; # IP Address of FHEM Server
  my $mymac = $hash->{MAC};  # Used for the access control/validation '"24:65:11:80:0D:01"

# screen message caller or individual
if ( $cmd eq "caller" ||
     $cmd eq "screen") {
   return SamsungAV_7676($hash,$cmd);
}
  my $msg;
  my $appstring = "iphone..iapp.samsung"; # What the iPhone app reports
  my $tvappstring = "iphone.".$tv.".iapp.samsung"; # TV type
  my $remotename = "Perl Samsung Remote"; # What gets reported when it asks for permission/also shows in General->Wireless Remote Control menu
  
  #### MAC überprüfen wenn nicht gültig vom attribute übernehmen.
  if ($mymac !~ /^\w\w:\w\w:\w\w:\w\w|\w\w:\w\w:\w\w:\w\w$/) {
    Log3 $name, 3, "[SamsungAV] mymac: $mymac invalid format";
  }else{
    # command-line help
    if (!$tv|!$tvip|!$myip|!$mymac) {
      return "[SamsungAV] Error - Parameter missing:\nmodel, tvip, myip, mymac.";
    }

    Log3 $name, 5, "[SamsungAV] $name: opening socket with tvip: $tvip, cmd: $cmd";
    my $sock = new IO::Socket::INET (
      PeerAddr => $tvip,
      PeerPort => $port,
      Proto => 'tcp',
      Timout => 5
    );
  
    if (defined ($sock)){
        my $messagepart1 = chr(0x64) . chr(0x00) . chr(length(encode_base64($myip, ""))) . chr(0x00) . encode_base64($myip, "") . chr(length(encode_base64($mymac, ""))) . chr(0x00) . encode_base64($mymac, "") . chr(length(encode_base64($remotename, ""))) . chr(0x00) . encode_base64($remotename, "");
        my $part1 = chr(0x00) . chr(length($appstring)) . chr(0x00) . $appstring . chr(length($messagepart1)) . chr(0x00) . $messagepart1;
        print $sock $part1;

        my $messagepart2 = chr(0xc8) . chr(0x00);
        my $part2 = chr(0x00) . chr(length($appstring)) . chr(0x00) . $appstring . chr(length($messagepart2)) . chr(0x00) . $messagepart2;
        print $sock $part2;
        # Preceding sections all first time only

        if ($cmd eq "0_text_line") {
         # Send text, e.g. in YouTube app's search, N.B. NOT BBC iPlayer app.
         my $text = $par;
         my $messagepart3 = chr(0x01) . chr(0x00) . chr(length(encode_base64($text, ""))) . chr(0x00) . encode_base64($text, "");
         my $part3 = chr(0x01) . chr(length($appstring)) . chr(0x00) . $appstring . chr(length($messagepart3)) . chr(0x00) . $messagepart3;
         print $sock $part3;
        }
        else {
          foreach my $argnum (0 .. $#ARGV) {
			Time::HiRes::usleep(300000) if ($argnum > 0);
	  if ($ARGV[$argnum] ne "") {
            # Send remote key(s)
#            Log3 $name, 3, "[SamsungAV] sending ".uc($ARGV[$argnum]);
            my $key = "KEY_" . uc($ARGV[$argnum]);
            my $messagepart3 = chr(0x00) . chr(0x00) . chr(0x00) . chr(length(encode_base64($key, ""))) . chr(0x00) . encode_base64($key, "");
            my $part3 = chr(0x00) . chr(length($tvappstring)) . chr(0x00) . $tvappstring . chr(length($messagepart3)) . chr(0x00) . $messagepart3;
            print $sock $part3;
			Log3 $name, 4, "[SamsungAV] $name: command: '$key'";	
        #        select(undef, undef, undef, 0.5);
          }
          }
        }

        close($sock);
    }else{
		$msg = "Could not create socket. Port: $port. Aborting.";
		Log3 $name, 2, "[SamsungAV] $name: $msg";
    }
  }
  return $msg;
}

sub SamsungAV_7676($$)
{
   my ($hash,$arg) = @_;
   my $TV    = $hash->{Host};
   my $name  = $hash->{NAME};
   my ($URI, $location) = undef;
   
   if ($hash->{Port} eq "8000") {$location = "smp_4_" }
   else                         {$location = "smp_12_" }

   my $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
   $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" >\r\n";
   $callsoap .= "<s:Body>\r\n";
   $callsoap .= "<u:RunBrowser xmlns:u=\"urn:samsung.com:service:MainTVAgent2:1\">\r\n";
   if ( $arg ne "caller" ) {$URI = AttrVal($name, "screenURI", undef)}
   else                    {$URI = AttrVal($name, "callerURI", undef)}
   if (defined $URI) {$callsoap .= "<BrowserURL>".$URI."</BrowserURL>\r\n"}
   $callsoap .= "</u:RunBrowser>\r\n";

   my $head .= "POST /$location HTTP/1.1\r\n";
   $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
   $head .= "SOAPACTION: \"urn:samsung.com:service:MainTVAgent2:1#RunBrowser\"\r\n";

   return soap_call($hash,$head,$callsoap,7676);
}
sub soap_call($$$$)
{
  my ($hash,$head,$callsoap,$port) = @_;
  my $name = $hash->{NAME};
  my $TV   = $hash->{Host};
  my $msg;
  
  $callsoap .= "</s:Body>\r\n";
  $callsoap .= "</s:Envelope>\r\n";

  my $size = length($callsoap);
 
  $head .= "Cache-Control: no-cache\r\n";
  $head .= "Host: $TV:$port\r\n";
  $head .= "Content-Length: $size\r\n";
  $head .= "Connection: Close\r\n";
  $head .= "\r\n";
  
  my $buffer = "";
  my $tmp = $head . $callsoap;
  my @tmp2 = "";

  Log3 $name, 4, "[SamsungAV] $name: $TV:$port connection message: $tmp";

  my $sock = new IO::Socket::INET (
          PeerAddr => $TV,
          PeerPort => $port,
          Proto => 'tcp',
          Timout => 5
        );
  if (defined ($sock)){
    print $sock $tmp;
    my $buff ="";
    while ((read $sock, $buff, 1) > 0){
      $buffer .= $buff;
    }
    Log3 $name, 2, "[SamsungAV] $name $TV: empty answer received" if ($buffer eq "");
    @tmp2 = split (/\n/,$buffer);
    Log3 $name, 4, "[SamsungAV] $name $TV: socket answer $buffer";
    $sock->close();
    Log3 $name, 4, "[SamsungAV] $name $TV: socket closed";
  }else{
	$msg = "Could not create socket.  Port: $port Aborting.";
    Log3 $name, 2, "[SamsungAV] $name $TV: $msg";
  }
  return $msg;
}
sub SamsungAV_DLNA($$)
{
   my ($hash,$command) = @_;
   my $name    = $hash->{NAME};
   
   if (ReadingsVal($hash->{Mode},"state","offline") ne "offline") {
      # copying of picture for caller to be done outside of program
      fhem($command);
      Log3 $name, 5, "[SamsungAV] $name DLNA-command:  $command";
   }
   else {
      return "[SamsungAV] $name DLNAdevice $hash->{Mode} currently offline";
   }
}

sub getIP()
{
  my $address = eval {Net::Address::IP::Local->public_ipv4};
  if ($@) {
    $address = 'localhost';
  } 
  return "$address";
}

sub getIP_old()
{
  my $host = hostname();
  my $address = inet_ntoa(scalar gethostbyname(hostname() || 'localhost'));
  if ($@) {
    $address = 'localhost';
  } 
  return "$address";
}

sub getMAC4IP($)
{
  my $IP = shift;
  my @interfaces = IO::Interface::Simple->interfaces;
  foreach my $if (@interfaces) {
    next unless defined ($if->address);
    if ($if->address eq $IP) {
        return $if->hwaddr;
    }
  }
  return "";
}
# Callback from 95_remotecontrol for command makenotify.
# Param1: Name of remoteControl device
# Param2: Name of target FHEM device
sub SamsungAV_RCmakenotify($$) {
  my ($name, $ndev) = @_;
  my $nname="notify_$name";
  
  fhem("define $nname notify $name set $ndev remoteControl ".'$EVENT',1);
  Log3 undef, 2, "[remoteControl:SamsungAV] Notify created: $nname";
  return "Notify created by SamsungAV: $nname";
}

# Callback from 95_remotecontrol for command layout. Creates non svg layout
sub SamsungAV_RClayout_TV() {
  my @row;
  my $i = 0;

  $row[$i++]="poweroff:POWEROFF,	:blank,			 	source:SOURCE";
  $row[$i++]=":blank,				hdmi:HDMI,			:blank";
  $row[$i++]="1,					2,					3";
  $row[$i++]="4,					5,					6";
  $row[$i++]="7,					8,					9";
  $row[$i++]="ttx_mix:TEXT,			0,					prech:PRECH";
#  $row[$i++]=":blank,				:blank,				:blank";
  $row[$i++]="volumeUp:UP,			mute:MUTE,			channelUp:CHUP";
  $row[$i++]=":VOL,					:blank,				:PROG";
  $row[$i++]="volumeDown:DOWN,		channelList:CH_LIST,channelDown:CHDOWN";
  $row[$i++]="menu:MENU,			:blank,				guide:GUIDE";
#  $row[$i++]=":blank,				:blank,				:blank";
  $row[$i++]="tools:TOOLS,			up:UP,				info:INFO";
  $row[$i++]="left:LEFT,			enter:ENTER,		right:RIGHT";
  $row[$i++]="reurn:RETURN,			down:DOWN,			exit:EXIT";
  $row[$i++]="red:RED,		        green:GREEN, 		yellow:YELLOW,  		cyan:BLUE";
  $row[$i++]=":blank,           	:SEARCH,          	:blank";
  $row[$i++]=":EGUIDE,           	aspect:PICTURE_SIZE,     	ad:AD";
  $row[$i++]="rewind:REWIND,        pause:PAUSE,        ff:FF";
  $row[$i++]="rec:REC,           	play:PLAY,          stop:STOP";

  # unused available commands
  # SOURCE PIP_ONOFF 
  # CONTENTS W_LINK
  # RSS MTS SRS CAPTION TOPMENU SLEEP ESAVING

  #Remove spaces
  for (@row) {s/\s+//g}

  $row[$i++]="attr rc_iconpath icons/remotecontrol";
  $row[$i++]="attr rc_iconprefix black_btn_";
		
  return @row;
}

# Callback from 95_remotecontrol for command layout. Creates svg layout
sub SamsungAV_RClayout_TV_SVG() {
  my @row;
  my $i = 0;
  
  $row[$i++]="poweroff:rc_POWER.svg,		:rc_BLANK.svg,				tv:rc_TV.svg";
  $row[$i++]=":rc_BLANK.svg,				hdmi:rc_HDMI.svg,			:rc_BLANK.svg";
  $row[$i++]="1:rc_1.svg,					2:rc_2.svg,					3:rc_3.svg";
  $row[$i++]="4:rc_4.svg,					5:rc_5.svg,					6:rc_6.svg";
  $row[$i++]="7:rc_7.svg,					8:rc_8.svg,					9:rc_9.svg";
  $row[$i++]="ttx_mix:rc_TEXT.svg,				0:rc_0.svg,					prech:rc_PREVIOUS.svg";
  $row[$i++]=":rc_BLANK.svg,			:rc_BLANK.svg,				:rc_BLANK.svg";
  $row[$i++]="volumeUp:rc_UP.svg,			mute:rc_MUTE.svg,			channelUp:rc_UP.svg";
  $row[$i++]=":rc_VOL.svg,					:rc_BLANK.svg,				:rc_PROG.svg";
  $row[$i++]="volumeDown:rc_DOWN.svg,		channelList:rc_PROG.svg,	channelDown:rc_DOWN.svg";
  $row[$i++]="menu:rc_MENU.svg,				:rc_BLANK.svg,				guide:rc_EPG.svg";
  $row[$i++]=":rc_BLANK.svg,				:rc_BLANK.svg,				:rc_BLANK.svg";
  $row[$i++]="tools:rc_OPTIONS.svg,			up:rc_UP.svg,				info:rc_INFO.svg";
  $row[$i++]="left:rc_LEFT.svg,				enter:rc_OK.svg,			right:rc_RIGHT.svg";
  $row[$i++]="reurn:rc_RETURN.svg,			down:rc_DOWN.svg,			exit:rc_EXIT.svg";
  $row[$i++]="red:rc_RED.svg,		        green:rc_GREEN.svg, 		yellow:rc_YELLOW.svg,  		cyan:rc_BLUE.svg";
  $row[$i++]=":rc_BLANK.svg,           		:rc_SEARCH.svg,          	:rc_BLANK.svg";
  $row[$i++]=":rc_HELP.svg,           	aspect:rc_PICTURE_SIZE.svg, ad:rc_AD.svg";
  $row[$i++]="rewind:rc_REW.svg,        	pause:rc_PAUSE.svg,        	ff:rc_FF.svg";
  $row[$i++]="rec:rc_REC.svg,           	play:rc_PLAY.svg,          	stop:rc_STOP.svg";

  #Remove spaces
  for (@row) {s/\s+//g}

  return @row;
}
				
1;

=pod
=item summary device to communicate with Samsung AV devices
=begin html

<a name="SamsungAV"></a>

<h3>SamsungAV</h3>
<ul><p>
This module supports Samsung devices like TV or BD players.<br>

</p>
 <b>Define</b><br>
  <code>define &lt;name&gt; SamsungAV &lt;host&gt; &lt;port&gt; [DLNA]</code><br>
  <p>
(B|C|D  Series) use port 52235 for screen messages: call, sms, date and volume change<br>                          
(C|D|E|F Series) use port 55000 for RC commands<br>
(H|J Series) use port 8000 for RC commands<br>
(newest Series) use port 8001 for RC commands<br>
(all Series)The device name of optional DLNA client might be defined to send full screen messages(OSD)<br>

  Example:<br>
  define Television SamsungAV 192.168.178.20 52235 <br>
  define Television SamsungAV 192.168.178.20 55000 <br>
  define Television SamsungAV 192.168.178.20 55000 DLNA_Client<br>
  </p>
 <b>Set</b><br>
  Port 52235 functionality:
  set &lt;name&gt; &lt;command&gt; [arguments]<br>where command is one of:<br>
  <ul>
  <li><code>mute</code> </li>
  <li><code>volume </code> </li>
  <li><code>call</code> </li>
  <li><code>sms  </code> </li>
  <li><code>date </code> </li>
  </ul>
  Example:<br>
  set Television mute on<br>
  set Television volume 20 <br>
  set Television call Peter 012345678 Phone 87654321 <br><br>
  RC functionality:  <br>
  set &lt;name&gt; &lt;RC command&gt; [arguments]<br> 
  Example:<br>
  set Television channelDown <br> <br>
  Special commands:  <br>
  caller/screen <br>
    send message(URI defined by attr callerURI/screenURI) via DLNA to device <br>
    Example:<br>
    set Television caller <br>
<br>
  sayText <br>
    TTS-function, if optional DLNA-device is defined  <br>
    Example:<br>
    set Television sayText das ist ein test <br>
    see commandref of DLNA-device for further information. <br>
<br>
  0_macro <br>
    macro function <br>
    send several comma separated RC commands to device(each command will cause a pause of delayMacro microsec.) <br>
    set &lt;name&gt; 0_macro &lt;RC command1&gt; [,RC command2,RC command3....] <br>
    Example:<br>
    set Television 0_macro contents,right,right,,down,enter <br>
    some TVs need different delays between RC commands in a macro. You may solve this with usage of multiple commas. <br>
<br>
  0_text_line <br>
  sent text to device(migh be helpful to submit data used by interactive apps) <br>
  set &lt;name&gt; 0_text_line &lt;TEXT&gt; <br>
    Example:<br>
    set Television 0_text_line http://192.168.178.1:8083/fhem/btip/info.html <br>
<br>
  0_App_start Netflix/YouTube (0_App_status Netflix/YouTube) <br>
  start app on TV  (get status of app) <br>
  <br>
   <b>Get</b><br>
   <ul>N/A</ul><br>
  <br>
   <b>Attributes</b><br>
 			<li>callerURI:  path to an URI of a media(jpg,mp3...)to be displayed on screen
			                main purpose: URI to be displayed on screen if a phone call comes in</li>
  <br>
			<li>screenURI:  path to an URI of a media(jpg,mp3...)to be displayed on screen
			                every other purpose than a phone call as event</li>
  <br>
			<li>delayRC:    delay in microsec. default=0
			                some TV's need a delay before transmition of a RC command.
			                be careful: attribute causes system freezes  </li>
  <br>
			<li>delayMacro: delay in microsec. default=300000
			                most TV's need a delay between each RC command in macro function.
			                be careful: attribute causes system freezes  </li>
  <br>
			<li>disable:    0/1: enables/disables device</li>
</ul>
   
=end html
=cut
