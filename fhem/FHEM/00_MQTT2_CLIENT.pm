##############################################
# $Id$
package main;

use strict;
use warnings;
use DevIo;

sub MQTT2_CLIENT_Read($@);
sub MQTT2_CLIENT_Write($$$);
sub MQTT2_CLIENT_Undef($@);
sub MQTT2_CLIENT_doPublish($@);
sub MQTT2_CLIENT_Disco($;$$);

# See also:
# http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html

sub
MQTT2_CLIENT_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}     = "MQTT2_CLIENT_Read";
  $hash->{DefFn}      = "MQTT2_CLIENT_Define";
  $hash->{AttrFn}     = "MQTT2_CLIENT_Attr";
  $hash->{SetFn}      = "MQTT2_CLIENT_Set";
  $hash->{UndefFn}    = "MQTT2_CLIENT_Undef";
  $hash->{ShutdownFn} = "MQTT2_CLIENT_Undef";
  $hash->{DeleteFn}   = "MQTT2_CLIENT_Delete";
  $hash->{WriteFn}    = "MQTT2_CLIENT_Write";
  $hash->{ReadyFn}    = "MQTT2_CLIENT_connect";

  no warnings 'qw';
  my @attrList = qw(
    autocreate:no,simple,complex
    clientId
    clientOrder
    connectTimeout
    disable:1,0
    disabledForIntervals
    disconnectAfter
    ignoreRegexp
    lwt
    lwtRetain
    keepaliveTimeout
    msgAfterConnect
    msgBeforeDisconnect
    mqttVersion:3.1.1,3.1
    privacy:0,1
    qosMaxQueueLength
    rawEvents
    subscriptions
    SSL
    sslargs
    username
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
}

sub
MQTT2_CLIENT_resetClients($)
{
  my ($hash) = @_;

  $hash->{ClientsKeepOrder} = 1;
  $hash->{Clients} = ":MQTT2_DEVICE:MQTT_GENERIC_BRIDGE:";
  $hash->{MatchList}= {
    "1:MQTT2_DEVICE"  => "^.",
    "2:MQTT_GENERIC_BRIDGE" => "^."
  };
  delete($hash->{".clientArray"});
}

#####################################
sub
MQTT2_CLIENT_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $host) = split("[ \t]+", $def);
  return "Usage: define <name> MQTT2_CLIENT <hostname>:<tcp-portnr>"
        if(!$host);

  MQTT2_CLIENT_resetClients($hash);
  MQTT2_CLIENT_Undef($hash, undef) if($hash->{OLDDEF}); # modify

  $hash->{DeviceName} = $host;
  $hash->{clientId} = AttrVal($hash->{NAME}, "clientId", $hash->{NAME});
  $hash->{connecting} = 1;

  InternalTimer(1, "MQTT2_CLIENT_connect", $hash, 0); # need attributes
  return undef;
}

sub
MQTT2_CLIENT_connect($)
{
  my ($hash) = @_;
  return if($hash->{authError});
  my $disco = (DevIo_getState($hash) eq "disconnected");
  $hash->{connecting} = 1 if($disco && !$hash->{connecting});
  $hash->{nextOpenDelay} = 5;
  $hash->{BUF}="";
  return DevIo_OpenDev($hash, $disco, "MQTT2_CLIENT_doinit", sub(){})
                if($hash->{connecting});
}

sub
MQTT2_CLIENT_doinit($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ############################## CONNECT
  if($hash->{connecting} == 1) {
    my $usr = AttrVal($name, "username", "");
    my ($err, $pwd) = getKeyValue($name);
    $pwd = undef if($usr eq "");
    if($err) {
      Log 1, "ERROR: $err";
      return;
    }
    my ($lwtt, $lwtm) = split(" ",AttrVal($name, "lwt", ""),2);
    my $lwtr = AttrVal($name, "lwtRetain", 0);
    my $m31 = (AttrVal($name, "mqttVersion", "3.1") eq "3.1");
    my $keepalive = AttrVal($name, "keepaliveTimeout", 30);
    $keepalive = 30 if($keepalive !~ m/^[0-9]+$/);
    my $msg = 
        ($m31 ? pack("n",6)."MQIsdp".pack("C",3):
                pack("n",4)."MQTT"  .pack("C",4)).
        pack("C", ($usr  ? 0x80 : 0)+
                  ($pwd  ? 0x40 : 0)+
                  ($lwtr ? 0x20 : 0)+
                  ($lwtt ? 0x04 : 0)+2). # clean session
        pack("n", $keepalive).
        pack("n", length($hash->{clientId})).$hash->{clientId}.
        ($lwtt ? (pack("n", length($lwtt)).$lwtt).
                 (pack("n", length($lwtm)).$lwtm) : "").
        ($usr ? (pack("n", length($usr)).$usr) : "").
        ($pwd ? (pack("n", length($pwd)).$pwd) : "");
    $hash->{connecting} = 2;
    MQTT2_CLIENT_send($hash,
      pack("C",0x10).
      MQTT2_CLIENT_calcRemainingLength(length($msg)).$msg, 1, 1); # Forum #92946
    RemoveInternalTimer($hash);
    $hash->{waitingForConnack} = 1;
    if($keepalive) {
      InternalTimer(gettimeofday()+$keepalive,"MQTT2_CLIENT_keepalive",$hash,0);
    }

  ############################## SUBSCRIBE & RESEND Non-Acked
  } elsif($hash->{connecting} == 2) {
    my $s = AttrVal($name, "subscriptions", "#");
    if($s eq "setByTheProgram") {
      $s = ($hash->{".subscriptions"} ? $hash->{".subscriptions"} : "#");
    }
    my $msg = 
        pack("n", $hash->{FD}). # packed Identifier
        join("", map { pack("n", length($_)).$_.pack("C",0) } # QOS:0
                 split(" ", $s));
    MQTT2_CLIENT_send($hash,
      pack("C",0x82).
      MQTT2_CLIENT_calcRemainingLength(length($msg)).$msg, 0, 1);
    $hash->{connecting} = 3;


  } elsif($hash->{connecting} == 3) {
    my $onc = AttrVal($name, "msgAfterConnect", "");
    delete($hash->{connecting});
    MQTT2_CLIENT_doPublish($hash, $2, $3, $1, 1)
      if($onc && $onc =~ m/^(-r\s)?([^\s]*)\s*(.*)$/);

    if($hash->{qosQueue} && @{$hash->{qosQueue}}) {
      my $pa = $hash->{qosQueue};
      $hash->{qosQueue} = [];
      for(my $i1=0; $i1<@{$pa}; $i1++) {
        my $r = $pa->[$i1];
        MQTT2_CLIENT_doPublish($hash, $r->[0], $r->[1], $r->[2], 0);
      }
    }
    if($hash->{sendHash}) {
      map { MQTT2_CLIENT_doPublish($hash,$_->[1],$_->[2],$_->[3]) }
                @{$hash->{sendHash}};
      delete($hash->{sendHash});
    } 
    MQTT2_CLIENT_updateDisconnectTimer($hash);

  }

  return undef;
}

sub
MQTT2_CLIENT_keepalive($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if($hash->{waitingForConnack}) {
    Log3 $name, 2, "$hash->{NAME}: No CONNACK, disconnecting";
    return  MQTT2_CLIENT_Disco($hash);
  }
  if($hash->{waitingForPingRespSince}) {
    Log3 $name, 2, "$hash->{NAME}: No PINGRESP for last PINGREQ (".
            "at $hash->{waitingForPingRespSince}), disconnecting";
    return  MQTT2_CLIENT_Disco($hash);
  }
  my $keepalive = AttrVal($name, "keepaliveTimeout", 30);
  $keepalive = 30 if($keepalive !~ m/^[0-9]+$/);
  return if(ReadingsVal($name, "state", "") ne "opened" || $hash->{connecting});
  MQTT2_CLIENT_send($hash, pack("C",0xC0).pack("C",0)); # PINGREQ
  $hash->{waitingForPingRespSince} = TimeNow();
  InternalTimer(gettimeofday()+$keepalive, "MQTT2_CLIENT_keepalive", $hash, 0);
}

sub
MQTT2_CLIENT_Undef($@)
{
  my ($hash, $arg) = @_;
  MQTT2_CLIENT_Disco($hash, 1);
  return undef;
}

sub
MQTT2_CLIENT_Disco($;$$)
{
  my ($hash, $isUndef, $noMsg) = @_;
  RemoveInternalTimer($hash);
  $hash->{connecting} = 1 if(!$isUndef);
  if(!$noMsg) {
    my $ond = AttrVal($hash->{NAME}, "msgBeforeDisconnect", "");
    MQTT2_CLIENT_doPublish($hash, $2, $3, $1, 1)
          if($ond && $ond =~ m/^(-r\s)?([^\s]*)\s*(.*)$/);
    MQTT2_CLIENT_send($hash, pack("C",0xE0).pack("C",0), 1); # DISCONNECT
  }
  $isUndef ? DevIo_CloseDev($hash) : DevIo_Disconnected($hash);
  delete($hash->{BUF});

  if($hash->{disconnectTimerHash}) {
    RemoveInternalTimer($hash->{disconnectTimerHash});
    delete($hash->{disconnectTimerHash});
  }

  delete $hash->{waitingForConnack};
  delete $hash->{waitingForPingRespSince};

  readingsSingleUpdate($hash, "state", "disconnected", 1);
}

sub
MQTT2_CLIENT_updateDisconnectTimer($)
{
  my ($hash) = @_;
  return if(!$hash->{FD} || $hash->{connecting});
  if($hash->{disconnectTimerHash}) {
    RemoveInternalTimer($hash->{disconnectTimerHash});
    delete($hash->{disconnectTimerHash});
    delete($hash->{disconnectAt});
  }
  my $to = AttrVal($hash->{NAME}, "disconnectAfter", 0);
  return if(!$to);
  $to += time();
  $hash->{disconnectAt} = FmtDateTime($to);
  $hash->{disconnectTimerHash} = { h=>$hash };
  InternalTimer($to, sub{ MQTT2_CLIENT_Disco($_[0]->{h},1) },
        $hash->{disconnectTimerHash}, 0);
}

sub
MQTT2_CLIENT_Delete($@)
{
  my ($hash, $arg) = @_;
  setKeyValue($hash->{NAME}, undef);
  return undef;
}


sub
MQTT2_CLIENT_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};
  if($type eq "set" && $attrName eq "SSL") {
    $hash->{SSL} = $param[0] ? $param[0] : 1;
  }

  if($type eq "set" && $attrName eq "ignoreRegexp") {
    my $re = join(" ",@param);
    return "bad $devName ignoreRegexp: $re" if($re eq "1" || $re =~ m/^\*/);
    eval { "Hallo" =~ m/$re/ };
    return "bad $devName ignoreRegexp: $re: $@" if($@);
  }

  if($attrName eq "clientId") {
    delete($hash->{clientId});
    $hash->{clientId} = $param[0] if($type eq "set");
  }

  if($attrName eq "connectTimeout") {
    delete($hash->{TIMEOUT});
    $hash->{TIMEOUT} = $param[0] if($type eq "set");
  }

  if($attrName eq "sslargs") {
    $hash->{sslargs} = {};
    for my $kv (split(" ",$param[0])) {
      my ($k, $v) = split(":", $kv, 2);
      $hash->{sslargs}{$k} = $v;
    }
  }

  my %h = (clientId=>1,lwt=>1,lwtRetain=>1,subscriptions=>1,SSL=>1,username=>1);
  if($init_done && $h{$attrName}) {
    delete($hash->{authError});
    MQTT2_CLIENT_Disco($hash);
  }

  if($attrName eq "qosMaxQueueLength") {
    if($type eq "set" && $param[0] ne "0") {
      return "qosMaxQueueLength must be an integer" if($param[0] !~ m/^\d+$/);
      $hash->{qosMaxQueueLength} = $param[0];
      $hash->{qosQueue} = [];
      $hash->{qosCnt} = 0;
    } else {
      delete $hash->{qosQueue};
      delete $hash->{qosMaxQueueLength};
    }
  }

  if($attrName eq "disconnectAfter") {
    $hash->{devioLoglevel} = ($type eq "set" ? 5 : 0);
    return undef if(!$init_done);
    InternalTimer(0, sub {
      MQTT2_CLIENT_updateDisconnectTimer($hash);
      MQTT2_CLIENT_connect($hash)
        if(!$hash->{FD} && ($type ne "set" || $param[0] eq "0"));
    }, undef, 0);
  }

  if($attrName eq "clientOrder") {
    if($type eq "set") {
      my @p = split(" ", $param[0]);
      $hash->{Clients} = ":".join(":",@p).":";
      my $cnt = 1;
      my %h = map { ($cnt++.":$_", "^.") } @p;
      $hash->{MatchList} = \%h;
      delete($hash->{".clientArray"}); # Force a recompute
    } else {
      MQTT2_CLIENT_resetClients($hash);
    }
  }


  return undef;
}

sub
MQTT2_CLIENT_Set($@)
{
  my ($hash, @a) = @_;
  my %sets = ( password=>2, publish=>2, connect=>0, disconnect=>0 );
  my $name = $hash->{NAME};
  shift(@a);

  return "Unknown argument ?, choose one of ".
        join(" ", map { $sets{$_} ? $_ : "$_:noArg" } keys %sets)
        if(!$a[0] || !defined($sets{$a[0]}));

  if($a[0] eq "publish") {
    shift(@a);
    my $retain;
    if(@a>2 && $a[0] eq "-r") {
      $retain = 1;
      shift(@a);
    }
    return "Usage: set $name publish -r topic [value]" if(@a < 1);
    my $tp = shift(@a);
    my $val = join(" ", @a);
    readingsSingleUpdate($hash, "lastPublish", "$tp:$val", 1);
    MQTT2_CLIENT_doPublish($hash, $tp, $val, $retain);

  } elsif($a[0] eq "password") {
    return "Usage: set $name password <password>" if(@a < 1);
    delete($hash->{authError});
    setKeyValue($name, $a[1]); # will delete, if argument is empty
    MQTT2_CLIENT_Disco($hash) if($init_done);

  } elsif($a[0] eq "connect") {
    MQTT2_CLIENT_connect($hash) if(!$hash->{FD});

  } elsif($a[0] eq "disconnect") {
    MQTT2_CLIENT_Disco($hash, 1) if($hash->{FD});

  }
  return undef;
}

my %cptype = (
  0 => "RESERVED_0",
  1 => "CONNECT",
  2 => "CONNACK", #
  3 => "PUBLISH", #
  4 => "PUBACK",  #
  5 => "PUBREC",
  6 => "PUBREL",
  7 => "PUBCOMP",
  8 => "SUBSCRIBE",
  9 => "SUBACK",  #
 10 => "UNSUBSCRIBE",
 11 => "UNSUBACK",
 12 => "PINGREQ",
 13 => "PINGRESP",  #
 14 => "DISCONNECT",#
 15 => "RESERVED_15",
);

#####################################
sub
MQTT2_CLIENT_Read($@)
{
  my ($hash, $reread) = @_;

  my $name = $hash->{NAME};
  my $fd = $hash->{FD};

  if(!$reread) {
    my $buf = DevIo_SimpleRead($hash);
    if(!defined($buf)) {
      MQTT2_CLIENT_Disco($hash,0,1);
      return "";
    }
    $hash->{BUF} .= $buf;
  }

  my ($tlen, $off) = MQTT2_CLIENT_getRemainingLength($hash);
  if($tlen < 0 || $tlen+$off<=0) {
    Log3 $name, 1, "Bogus data from $name, closing connection";
    MQTT2_CLIENT_Disco($hash,0,1);
    return;
  }
  return if(length($hash->{BUF}) < $tlen+$off);

  my $fb = substr($hash->{BUF}, 0, 1);
  my $pl = substr($hash->{BUF}, $off, $tlen); # payload
  $hash->{BUF} = substr($hash->{BUF}, $tlen+$off);

  my $cp = ord(substr($fb,0,1)) >> 4;
  my $cpt = $cptype{$cp};
  $hash->{lastMsgTime} = gettimeofday();

  # Lowlevel debugging
  if(AttrVal($name, "verbose", 1) >= 5) {
    my $pltxt = $pl;
    $pltxt =~ s/([^ -~])/"(".ord($1).")"/ge;
    Log3 $name, 5, "$name: received $cpt $pltxt";
  }

  ####################################
  if($cpt eq "CONNACK")  {
    delete($hash->{waitingForConnack});
    my $rc = ord(substr($pl,1,1));
    if($rc == 0) {
      MQTT2_CLIENT_doinit($hash);

    } else {
      my @txt = ("Accepted", "bad proto", "bad id", "server unavailable",
                  "bad user name or password", "not authorized");
      Log3 $name, 1, "$name: Connection refused, ".
        ($rc <= int(@txt) ? $txt[$rc] : "unknown error $rc");
      $hash->{authError} = $rc;
      MQTT2_CLIENT_Disco($hash);
      return;
    }

  } elsif($cpt eq "PUBACK") { 
    shift(@{$hash->{qosQueue}}) if($hash->{qosQueue});

  } elsif($cpt eq "SUBACK") {
    MQTT2_CLIENT_doinit($hash) if($hash->{connecting});

  } elsif($cpt eq "PINGRESP") {
    delete($hash->{waitingForPingRespSince});
    
  } elsif($cpt eq "PUBLISH")  {
    my $cf = ord(substr($fb,0,1)) & 0xf;
    my $qos = ($cf & 0x06) >> 1;
    my ($tp, $val, $pid);
    ($tp, $off) = MQTT2_CLIENT_getStr($pl, 0);
    if($qos) {
      $pid = unpack('n', substr($pl, $off, 2));
      $off += 2;
    }
    $val = substr($pl, $off);
    MQTT2_CLIENT_send($hash, pack("CCnC*", 0x40, 2, $pid)) if($qos); # PUBACK
    MQTT2_CLIENT_updateDisconnectTimer($hash);

    if(!IsDisabled($name)) {
      $val = "" if(!defined($val));

      my $ir = AttrVal($name, "ignoreRegexp", undef);
      if(!defined($ir) || "$tp:$val" !~ m/$ir/) {
        my $ac = AttrVal($name, "autocreate", "no");
        $ac = $ac eq "1" ? "simple" : ($ac eq "0" ? "no" : $ac); # backward comp.

        my $cid = makeDeviceName($hash->{clientId});
        $tp =~ s/:/_/g; # 96608
        Dispatch($hash, "autocreate=$ac\0$cid\0$tp\0$val", undef, $ac eq "no");

        my $re = AttrVal($name, "rawEvents", undef);
        DoTrigger($name, "$tp:$val") if($re && $tp =~ m/$re/);
      }
    }

  } else {
    Log 1, "M2: Unhandled packet $cpt, disconneting $name";
    MQTT2_CLIENT_Disco($hash);
  }

  # Allow some IO inbetween, for overloaded systems
  InternalTimer(0, sub{ MQTT2_CLIENT_Read($_[0],1)}, $hash,0)
        if(length($hash->{BUF}) > 0);
}

######################################
# send topic to client if its subscriptions matches the topic

sub
MQTT2_CLIENT_doPublish($@)
{
  my ($hash, $topic, $val, $retain, $immediate) = @_;
  my $name = $hash->{NAME};
  return if(IsDisabled($name));
  $val = "" if(!defined($val));

  if((!$hash->{FD} || $hash->{connecting}) &&
        AttrVal($name, "disconnectAfter", undef)) {
    $hash->{sendHash} = [] if(!defined($hash->{sendHash}));
    push(@{$hash->{sendHash}}, \@_);
    MQTT2_CLIENT_connect($hash) if(!$hash->{connecting});
    return;
  }
  MQTT2_CLIENT_updateDisconnectTimer($hash);

  if(!$hash->{FD}) {
    Log3 $name, 4, "$name: publish to $topic while not connected";
    return;
  }

  my $hdr = 0x30;
  my $pi = "";
  $hdr += 1 if($retain);
  if(defined($hash->{qosQueue}) &&
     @{$hash->{qosQueue}} < $hash->{qosMaxQueueLength}) {
    $hdr += 2; # QoS:1
    push(@{$hash->{qosQueue}}, [$topic,$val,$retain]);
    $pi = pack("n",1+($hash->{qosCnt}++%65535)); # Packet Identifier, if QoS > 0
  }
  my $msg = pack("C", $hdr).
            MQTT2_CLIENT_calcRemainingLength(2+length($topic)+length($val)+
                                length($pi)).
            pack("n", length($topic)).
            $topic.$pi.$val;
  MQTT2_CLIENT_send($hash, $msg, $immediate)
}

sub
MQTT2_CLIENT_send($$;$$)
{
  my ($hash, $msg, $immediate, $doSend) = @_;

  # Lowlevel debugging
  my $name = $hash->{NAME};
  $doSend = 1 if(!$doSend && !$hash->{connecting}); # ignore msgs before CONNECT
  if(AttrVal($name, "verbose", 1) >= 5) {
    my $cmd = $cptype{ord($msg)>>4};
    my $msgTxt = $msg;
    $msgTxt =~ s/([^ -~])/"(".ord($1).")"/ge;
    Log3 $name, 5, "$name: ".($doSend ? "sending":"discarding")." $cmd $msgTxt";
  }
  return if(!$doSend);

  if($immediate) {
    DevIo_SimpleWrite($hash, $msg, 0);
  } else {
    addToWritebuffer($hash, $msg, undef, 1); # nolimit
  }
}

sub
MQTT2_CLIENT_Write($$$)
{
  my ($hash, $function, $topicMsg) = @_;

  return "Ignoring the message as $hash->{NAME} is not yet connected"
        if($hash->{connecting});

  if($function eq "publish") {
    my ($topic, $msg) = split(" ", $topicMsg, 2);
    my $retain;
    if($topic =~ m/^(.*):r$/) {
      $topic = $1;
      $retain = 1;
    }
    MQTT2_CLIENT_doPublish($hash, $topic, $msg, $retain);

  } elsif($function eq "subscriptions") {
    $hash->{".subscriptions"} = $topicMsg;
    MQTT2_CLIENT_Disco($hash);

  } else {
    my $name = $hash->{NAME};
    Log3 $name, 1, "$name: ERROR: Ignoring function $function";
  }
  return undef;
}

sub
MQTT2_CLIENT_calcRemainingLength($)
{
  my ($l) = @_;
  my @r;
  while($l > 0) {
    my $eb = $l % 128;
    $l = int($l/128);
    $eb += 128 if($l);
    push(@r, $eb);
  }
  return pack("C*", @r);
}

sub
MQTT2_CLIENT_getRemainingLength($)
{
  my ($hash) = @_;
  return (2,2) if(length($hash->{BUF}) < 2);

  my $ret = 0;
  my $mul = 1;
  for(my $off = 1; $off <= 4; $off++) {
    my $b = ord(substr($hash->{BUF},$off,1));
    $ret += ($b & 0x7f)*$mul;
    return ($ret, $off+1) if(($b & 0x80) == 0);
    $mul *= 128;
  }
  return -1;
}

sub
MQTT2_CLIENT_getStr($$)
{
  my ($in, $off) = @_;
  my $l = unpack("n", substr($in, $off, 2));
  return (substr($in, $off+2, $l), $off+2+$l);
}

1;

=pod
=item summary    Connection to an external MQTT server
=item summary_DE Verbindung zu einem externen MQTT Server
=begin html

<a id="MQTT2_CLIENT"></a>
<h3>MQTT2_CLIENT</h3>
<ul>
  MQTT2_CLIENT is a cleanroom implementation of an MQTT client (which connects
  to an external server, like mosquitto) using no perl libraries. It serves as
  an IODev to MQTT2_DEVICES.
  <br> <br>

  <a id="MQTT2_CLIENT-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MQTT2_CLIENT &lt;host&gt;:&lt;port&gt;</code>
    <br><br>
    Connect to the server on &lt;host&gt; and &lt;port&gt;. &lt;port&gt; 1883
    is default for mosquitto.
    <br>
    Notes:<br>
    <ul>
    <li>only QOS 0 and 1 is implemented</li>
    </ul>
  </ul>
  <br>

  <a id="MQTT2_CLIENT-set"></a>
  <b>Set</b>
  <ul>
    <li>publish -r topic value<br>
      publish a message, -r denotes setting the retain flag.
      </li><br>
    <li>password &lt;password&gt; value<br>
      set the password, which is stored in the FHEM/FhemUtils/uniqueID file.
      If the argument is empty, the password will be deleted.
      </li><br>
    <li>connect<br>
        disconnect<br>
      manually connect or disconnect to the MQTT server.  Needed for some
      strange embedded server.
      </li>
  </ul>
  <br>

  <a id="MQTT2_CLIENT-get"></a>
  <b>Get</b>
  <ul>N/A</ul><br>

  <a id="MQTT2_CLIENT-attr"></a>
  <b>Attributes</b>
  <ul>

    <a id="MQTT2_CLIENT-attr-autocreate"></a>
    <li>autocreate [no|simple|complex]<br>
      if set to simple/complex, at least one MQTT2_DEVICE will be created, and
      its readingsList will be expanded upon reception of published messages.
      Note: this is slightly different from MQTT2_SERVER, where each connection
      has its own clientId.  This parameter is sadly not transferred via the
      MQTT protocol, so the clientId of this MQTT2_CLIENT instance will be
      used.<br>
      With simple the one-argument version of json2nameValue is added:
      json2nameValue($EVENT), with complex the full version:
      json2nameValue($EVENT, 'SENSOR_', $JSONMAP). Which one is better depends
      on the attached devices and on the personal taste, and it is only
      relevant for json payload. For non-json payload there is no difference
      between simple and complex.<br>
      Default is no, as in absence of an MQTT2_DEVICE with a bridgeRegexp
      attribute it is not really useful.
      </li></br>

    <a id="MQTT2_CLIENT-attr-clientId"></a>
    <li>clientId &lt;name&gt;<br>
      set the MQTT clientId. If not set, the name of the MQTT2_CLIENT instance
      is used, after deleting everything outside 0-9a-zA-Z
      </li></br>

    <a id="MQTT2_CLIENT-attr-clientOrder"></a>
    <li>clientOrder [MQTT2_DEVICE] [MQTT_GENERIC_BRIDGE]<br>
      set the notification order for client modules. This is 
      relevant when autocreate is active, and the default order
      (MQTT2_DEVICE MQTT_GENERIC_BRIDGE) is not adequate.
      Note: Changing the attribute affects _all_ MQTT2_CLIENT instances.
      </li></br>

    <a id="MQTT2_CLIENT-attr-connectTimeout"></a>
    <li>connectTimeout &lt;seconds&gt;<br>
      change the HTTP connect timeout, default is 4 seconds. This seems to be
      necessary for some MQTT servers in robotic vacuum cleaners.
      </li></br>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a><br>
      disable dispatching of messages.
      </li><br>

    <a id="MQTT2_CLIENT-attr-disconnectAfter"></a>
    <li>disconnectAfter &lt;seconds&gt;<br>
      if set, the connection will be closed after &lt;seconds&gt; of
      inactivity, and will be automatically reopened when sending a command.
      </li>

    <a id="MQTT2_CLIENT-attr-ignoreRegexp"></a>
    <li>ignoreRegexp<br>
      if $topic:$message matches ignoreRegexp, then it will be silently ignored.
      </li>

    <a id="MQTT2_CLIENT-attr-lwt"></a>
    <li>lwt &lt;topic&gt; &lt;message&gt; <br>
      set the LWT (last will and testament) topic and message, default is empty.
      </li></br>

    <a id="MQTT2_CLIENT-attr-keepaliveTimeout"></a>
    <li>keepaliveTimeout &lt;seconds;&gt;<br>
      number of seconds for sending keepalive messages, 0 disables it.
      The broker will disconnect, if there were no messages for
      1.5 * keepaliveTimeout seconds.
      </li></br>

    <a id="MQTT2_CLIENT-attr-lwtRetain"></a>
    <li>lwtRetain<br>
      if set, the lwt retain flag is set
      </li></br>

    <a id="MQTT2_CLIENT-attr-mqttVersion"></a>
    <li>mqttVersion 3.1,3.1.1<br>
      set the MQTT protocol version in the CONNECT header, default is 3.1
      </li></br>

    <a id="MQTT2_CLIENT-attr-msgAfterConnect"></a>
    <li>msgAfterConnect [-r] topic message<br>
      publish the topic after each connect or reconnect.<br>
      If the optional -r is specified, then the publish sets the retain flag.
      </li></br>

    <a id="MQTT2_CLIENT-attr-msgBeforeDisconnect"></a>
    <li>msgBeforeDisconnect [-r] topic message<br>
      publish the topic bofore each disconnect.<br>
      If the optional -r is specified, then the publish sets the retain flag.
      </li></br>

    <a id="MQTT2_CLIENT-attr-qosMaxQueueLength"></a>
    <li>qosMaxQueueLength &lt;number&gt;<br>
      if set to a nonzero value, messages are published with QoS=1, and are
      kept in a memory-only buffer until acknowledged by the server.
      If there is no connection to the server, up to &lt;number&gt; messages
      are queued, and resent when the connection is esablished.
      </li></br>
      
    <a id="MQTT2_CLIENT-attr-rawEvents"></a>
    <li>rawEvents &lt;topic-regexp&gt;<br>
      send all messages as events attributed to this MQTT2_CLIENT instance.
      Should only be used, if there is no MQTT2_DEVICE to process the topic.
      </li><br>

    <a id="MQTT2_CLIENT-attr-subscriptions"></a>
    <li>subscriptions &lt;subscriptions&gt;<br>
      space separated list of MQTT subscriptions, default is #<br>
      Note: if the value is the literal setByTheProgram, then the value sent by
      the client (e.g. MQTT_GENERIC_BRIDGE) is used.
      </li><br>

    <a id="MQTT2_CLIENT-attr-SSL"></a>
    <li>SSL<br>
      Enable SSL (i.e. TLS)
      </li><br>

    <a id="MQTT2_CLIENT-attr-sslargs"></a>
    <li>sslargs<br>
      a list of space separated tuples of key:value, where key is one of the
      possible options documented in perldoc IO::Socket::SSL
      </li><br>

    <a id="MQTT2_CLIENT-attr-username"></a>
    <li>username &lt;username&gt;<br>
      set the username. The password is set via the set command, and is stored
      separately, see above.
      </li><br>

  </ul>
</ul>
=end html

=cut
