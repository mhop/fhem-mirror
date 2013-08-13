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
# Version = 1.11
#
# Version  History:
# - 1.11 - 2013-08-13
# -- added "noArg" at get/set-command
# -- changed format of return() in VIERA_Get() for get-command dropdown menu in FHEMWEB
#
# - 1.10 - 2013-06-29
# -- Added support for module 95_remotecontrol
# -- New functions: sub VIERA_RClayout_TV(); sub VIERA_RCmakenotify($$);
# -- Updated VIERA_Initialize for remotecontrol
#
# - 1.00 - yyy-mm-dd
# -- First release
#
##############################################################################
#
# define <name> VIERA <host>
#
# set <name> <key> <value>
#
# where <key> is one of mute, volume, remoteControl or off
# examples:
# set <name> mute on             < This will switch mute on
# set <name> volume 20           < This will set volume level to 20, mute will be set to off if enabled
# set <name> remoteControl mute  < This is equal to push the mute button at remote control. State of muting will be toggeled!
# set <name> remoteControl ?     < Print an overview of remotecontrol buttons 
#
##############################################################################

package main;
use strict;
use warnings;
use IO::Socket::INET;

#########################
# Forward declaration for remotecontrol module
sub VIERA_RClayout_TV();
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
);


sub VIERA_Initialize($){
  my ($hash) = @_;
  $hash->{DefFn}              = "VIERA_Define";
  $hash->{SetFn}              = "VIERA_Set";
  $hash->{GetFn}              = "VIERA_Get";
  $hash->{UndefFn}            = "VIERA_Undefine";
  $hash->{AttrList}           = "loglevel:0,1,2,3,4,5 " . $readingFnAttributes;
  $data{RC_layout}{VIERA_TV}  = "VIERA_RClayout_TV";
  $data{RC_makenotify}{VIERA} = "VIERA_RCmakenotify";
}

sub VIERA_Define($$){
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  if(int(@args) < 3 && int(@args) > 4) {
    my $msg = "wrong syntax: define <name> VIERA <host> [<interval>]";
    Log GetLogLevel($name, 2), $msg;
    return $msg;
  }

  $hash->{helper}{HOST} = $args[2];
  readingsSingleUpdate($hash,"state","Initialized",1);
  
  if(defined($args[3]) and $args[3] > 10) {
    $hash->{helper}{INTERVAL}=$args[3];
  }
  else{
    $hash->{helper}{INTERVAL}=30;
  }

  CommandAttr(undef,$name.' webCmd off') if( !defined( AttrVal($hash->{NAME}, "webCmd", undef) ) );
  Log GetLogLevel($name, 2), "VIERA: defined with host: $hash->{helper}{HOST} and interval: $hash->{helper}{INTERVAL}";
  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "VIERA_GetStatus", $hash, 0);

  return undef;
}

sub VIERA_Set($@){
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $host = $hash->{helper}{HOST};
  my $count = @a;
  my $ret = "";
  my $key = "";
  my $tab = "";
  my $usage = "choose one of off:noArg mute:on,off volume:slider,0,1,100 remoteControl:" . join(",", sort keys %VIERA_remoteControl_args);
  $usage =~ s/(NRC_|-ONOFF)//g;
  
  
  return "VIERA: No argument given, $usage" if(!defined($a[1]));
  my $what = $a[1];  
  
  return "VIERA: No state given, $usage" if(!defined($a[2]) && $what ne "off");
  my $state = $a[2];
  
  
  if($what eq "mute"){
    Log GetLogLevel($name, 3), "VIERA: Set mute $state";
    
    if ($state eq "on") {$state = 1;} else {$state = 0;}
    $ret = connection(VIERA_BuildXML_RendCtrl($hash, "Set", "Mute", $state), $host);
  }
  elsif($what eq "volume"){
    if($state < 0 || $state > 100){
      return "Range is too high! Use Value 0 till 100 for volume.";
    }
    Log GetLogLevel($name, 3), "VIERA: Set volume $state";
    $ret = connection(VIERA_BuildXML_RendCtrl($hash, "Set", "Volume", $state), $host);
  }
  elsif($what eq "remoteControl"){
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
      Log GetLogLevel($name, 3), "VIERA: Set remoteControl $state";   
      $ret = connection(VIERA_BuildXML_NetCtrl($hash,$state), $host);
    }
  }
  elsif($what eq "off"){
    Log GetLogLevel($name, 3), "VIERA: Set off";   
    $ret = connection(VIERA_BuildXML_NetCtrl($hash,"POWER"), $host);
  }
  else{
    Log GetLogLevel($name, 3), "VIERA: $usage";
    return "Unknown argument $what, $usage";
  }
  return;
}

sub VIERA_Get($@){
  my ($hash, @a) = @_;
  my $what;
  my $usage = "choose one of mute:noArg volume:noArg";

  return "VIERA: No argument given, $usage" if(int(@a) != 2);

  $what = $a[1];

  if($what =~ /^(volume|mute)$/) {
    if (defined($hash->{READINGS}{$what})) {
      return $hash->{READINGS}{$what}{VAL};
    }
    else{
      return "no such reading: $what";
    }
  }
  else{
    return "Unknown argument $what, $usage";
  }
}

sub VIERA_Undefine($$){
  my($hash, $name) = @_;
  
  # Stop the internal GetStatus-Loop and exist
  RemoveInternalTimer($hash);
  return undef;
}

sub VIERA_GetStatus($;$){
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $host = $hash->{helper}{HOST};
  
  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "VIERA_GetStatus", $hash, 0);
  
  return "" if(!defined($hash->{helper}{HOST}) or !defined($hash->{helper}{INTERVAL}));
  
  my $returnVol = connection(VIERA_BuildXML_RendCtrl($hash, "Get", "Volume", ""), $host);
  Log GetLogLevel($name, 5), "VIERA: GetStatusVol-Request returned: $returnVol" if(defined($returnVol));
  if(not defined($returnVol) or $returnVol eq "") {
    Log GetLogLevel($name, 4), "VIERA: GetStatusVol-Request NO SOCKET!";
    #readingsSingleUpdate($hash,"state","off",1);
    if( $hash->{STATE} ne "off") {readingsSingleUpdate($hash,"state","off",1);}
    return;
  }

  my $returnMute = connection(VIERA_BuildXML_RendCtrl($hash, "Get", "Mute", ""), $host);
  Log GetLogLevel($name, 5), "VIERA: GetStatusMute-Request returned: $returnMute" if(defined($returnMute));
  if(not defined($returnMute) or $returnMute eq "") {
    Log GetLogLevel($name, 4), "VIERA: GetStatusMute-Request NO SOCKET!";
    #readingsSingleUpdate($hash,"state","off",1);
    if( $hash->{STATE} ne "off") {readingsSingleUpdate($hash,"state","off",1);}
    return;
  }
  
  readingsBeginUpdate($hash);
  if($returnVol =~ /<CurrentVolume>(.+)<\/CurrentVolume>/){
    Log GetLogLevel($name, 4), "VIERA: GetStatus-Set reading volume to $1";
    if( $1 != $hash->{READINGS}{volume}{VAL} ) {readingsBulkUpdate($hash, "volume", $1);}
  }
  
  if($returnMute =~ /<CurrentMute>(.+)<\/CurrentMute>/){
    my $myMute = $1;
    if ($myMute == 0) { $myMute = "off"; } else { $myMute = "on";}
    Log GetLogLevel($name, 4), "VIERA: GetStatus-Set reading volume to $myMute";
    if( $myMute ne $hash->{READINGS}{mute}{VAL} ) {readingsBulkUpdate($hash, "mute", $myMute);}
  }
  #readingsBulkUpdate($hash, "state", "on");
  if( $hash->{STATE} ne "on") {readingsBulkUpdate($hash, "state", "on");}
  readingsEndUpdate($hash, 1);
  
  Log GetLogLevel($name,4), "VIERA $name: $hash->{STATE}";
  return $hash->{STATE};
}

sub connection($$){
  my $tmp =  shift ;
  my $TV = shift;
  my $buffer = "";
  my $tmp2 = "";
  my $sock = new IO::Socket::INET (
    PeerAddr => $TV,
    PeerPort => '55000',
    Proto => 'tcp',
    Timeout => 2
  );
  
  #Log 5, "VIERA: connection message: $tmp";
  
  if(defined ($sock)){
    print $sock $tmp;
    my $buff ="";

    while ((read $sock, $buff, 1) > 0){
      $buffer .= $buff;
    }
    
    my @tmp2 = split (/\n/,$buffer);
    #Log 4, "VIERA: $TV response: $tmp2[0]";
    #Log 5, "VIERA: $TV buffer response: $buffer";
    $sock->close();
    return $buffer;
  }
  else{
    #Log 4, "VIERA: $TV: not able to open socket";
    return undef;
  }
}

#####################################
# Callback from 95_remotecontrol for command makenotify.
sub VIERA_RCmakenotify($$) {
  my ($nam, $ndev) = @_;
  my $nname="notify_$nam";
  
  fhem("define $nname notify $nam set $ndev remoteControl ".'$EVENT',1);
  Log 2, "[remotecontrol:VIERA] Notify created: $nname";
  return "Notify created by VIERA: $nname";
}

#####################################
# Default-layout for panasonic TV (maybe other VIERA devices will have other layouts)
sub VIERA_RClayout_TV() {
  my @row;

  $row[0]="power:POWEROFF2,TV, CHG_INPUT:HDMI";
  $row[1]="MENU, disp_mode:ASPECT,epg:GUIDE";
  $row[2]="VIERA_LINK,VTOOLS,INTERNET";
  $row[3]=":blank,:blank,:blank";
  $row[4]="INFO:INFO2,UP,cancel:EXIT";
  $row[5]="LEFT,ENTER,RIGHT";
  $row[6]="SUBMENU,DOWN,RETURN";
  $row[7]=":blank,:blank,:blank";
  $row[8]="d1:1,d2:2,d3:3";
  $row[9]="d4:4,d5:5,d6:6";
  $row[10]="d7:7,d8:8,d9:9";
  $row[11]="MUTE,d0:0,r_tune:PRECH";
  $row[12]=":blank,:blank,:blank";
  $row[13]="VOLUP,:blank,ch_up:CHUP";
  $row[14]=":VOL,:blank,:PROG";
  $row[15]="VOLDOWN,:blank,ch_down:CHDOWN";
  $row[16]=":blank,:blank,:blank";
  $row[17]="rew:REWIND,PLAY,FF";
  $row[18]="STOP,PAUSE,REC";

  $row[19]="attr rc_iconpath icons/remotecontrol";
  $row[20]="attr rc_iconprefix black_btn_";
  return @row;
}

sub VIERA_BuildXML_NetCtrl($$){
  my ($hash, $command) = @_;
  my $host = $hash->{helper}{HOST};
  
  my $callsoap = "";
  my $message = "";
  my $head = "";
  my $size = "";
  
  #Log 1, "DEBUG: $command, $host";
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
  $head .= "Host: $host:55000\r\n";
  $head .= "SOAPACTION: \"urn:panasonic-com:service:p00NetworkControl:1#X_SendKey\"\r\n";
  $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
  $head .= "Content-Length: $size\r\n";
  $head .= "\r\n";

  $message .= $head;
  $message .= $callsoap;
  return $message;
}

sub VIERA_BuildXML_RendCtrl($$$$){
  my ($hash, $methode, $command, $value) = @_;
  my $host = $hash->{helper}{HOST};
  
  my $callsoap = "";
  my $message = "";
  my $head = "";
  my $size = "";
  
  #Log 1, "DEBUG: $command with $value to $host";

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

  $head .= "POST /dmr/control_0 HTTP/1.1\r\n";
  $head .= "Host: $host:55000\r\n";
  $head .= "SOAPACTION: \"urn:schemas-upnp-org:service:RenderingControl:1#$methode$command\"\r\n";
  $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
  $head .= "Content-Length: $size\r\n";
  $head .= "\r\n";

  $message .= $head;
  $message .= $callsoap;
  return $message;
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
    notify/filelog commands.<br><br>
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
    <ul><code>
      off<br>
      mute [on|off]<br>
      volume &lt;value&gt;<br>
      remoteControl &lt;command&gt;<br>
    </code></ul>
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
    
    <br>
    Notes:<br>
    <ul>Activate volume remotecontrol by DLNA: Menu -> Setup -> Network Setup -> Network Link Settings -> DLNA RemoteVolume -> On</ul>
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
    </code></ul>
  </ul>
  
  <br>
  <a name="VIERAattr"></a>
  <b>Attributes</b>
  <ul>N/A</ul>
  
  <br>
  <a name="VIERAevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>volume</li>
    <li>mute</li>
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
      volume &lt;Wert&gt;<br>
      remoteControl &lt;Befehl&gt;<br>
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

    <br>
    Anmerkung:<br>
    <ul>Aktivieren von Fernbedienung der Lautst&auml;rke per DLNA: Men&uuml; -> Setup -> Netzwerk-Setup -> Netzwerkverbindungsein. -> DLNA-Fernbed. Lautst. -> Ein</ul>
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
  </code></ul>
  </ul>
  
  <br>
  <a name="VIERAattr"></a>
  <b>Attribute</b>
  <ul>N/A</ul>
  
  <br>
  <a name="VIERAevents"></a>
  <b>Generierte events:</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>volume</li>
    <li>mute</li>
  </ul>
</ul>

=end html_DE



=cut
