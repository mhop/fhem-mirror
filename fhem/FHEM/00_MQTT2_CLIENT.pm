##############################################
# $Id$
package main;

use strict;
use warnings;
use DevIo;

sub MQTT2_CLIENT_Read($@);
sub MQTT2_CLIENT_Write($$$);
sub MQTT2_CLIENT_Undef($@);

my $keepalive = 30;

# See also:
# http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html

sub
MQTT2_CLIENT_Initialize($)
{
  my ($hash) = @_;

  $hash->{Clients} = ":MQTT2_DEVICE:";
  $hash->{MatchList}= { "1:MQTT2_DEVICE"  => "^.*" },
  $hash->{ReadFn}  = "MQTT2_CLIENT_Read";
  $hash->{DefFn}   = "MQTT2_CLIENT_Define";
  $hash->{AttrFn}  = "MQTT2_CLIENT_Attr";
  $hash->{SetFn}   = "MQTT2_CLIENT_Set";
  $hash->{UndefFn} = "MQTT2_CLIENT_Undef";
  $hash->{WriteFn} = "MQTT2_CLIENT_Write";
  $hash->{ReadyFn} = "MQTT2_CLIENT_connect";

  no warnings 'qw';
  my @attrList = qw(
    autocreate
    clientId
    disable:0,1
    disabledForIntervals
    lwt
    lwtRetain
    mqttVersion:3.1.1,3.1
    rawEvents
    subscriptions
    SSL
    username
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
}

#####################################
sub
MQTT2_CLIENT_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $host) = split("[ \t]+", $def);
  return "Usage: define <name> MQTT2_CLIENT <hostname>:<tcp-portnr>"
        if(!$host);

  MQTT2_CLIENT_Undef($hash, undef) if($hash->{OLDDEF}); # modify

  $hash->{DeviceName} = $host;
  $hash->{clientId} = $hash->{NAME};
  $hash->{clientId} =~ s/[^0-9a-zA-Z]//g;
  $hash->{clientId} = "MQTT2_CLIENT" if(!$hash->{clientId});
  $hash->{connecting} = 1;

  InternalTimer(1, "MQTT2_CLIENT_connect", $hash, 0); # need attributes
  return undef;
}

sub
MQTT2_CLIENT_connect($)
{
  my ($hash) = @_;
  my $disco = (ReadingsVal($hash->{NAME}, "state", "") eq "disconnected");
  $hash->{connecting} = 1 if($disco && !$hash->{connecting});
  $hash->{nextOpenDelay} = 5;
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
    if($err) {
      Log 1, "ERROR: $err";
      return;
    }
    my ($lwtt, $lwtm) = split(" ",AttrVal($name, "lwt", ""),2);
    my $lwtr = AttrVal($name, "lwtRetain", 0);
    my $m31 = (AttrVal($name, "mqttVersion", "3.1") eq "3.1");
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
    addToWritebuffer($hash,
      pack("C",0x10).
      MQTT2_CLIENT_calcRemainingLength(length($msg)).$msg);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$keepalive, "MQTT2_CLIENT_keepalive",$hash,0);

  ############################## SUBSCRIBE
  } elsif($hash->{connecting} == 2) {
    my $msg = 
        pack("n", $hash->{FD}). # packed Identifier
        join("", map { pack("n", length($_)).$_.pack("C",0) } # QOS:0
                 split(" ", AttrVal($name, "subscriptions", "#")));
    addToWritebuffer($hash,
      pack("C",0x80).
      MQTT2_CLIENT_calcRemainingLength(length($msg)).$msg);
    $hash->{connecting} = 3;

  }
  return undef;
}

sub
MQTT2_CLIENT_keepalive($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return if(ReadingsVal($name, "state", "") ne "opened");
  Log3 $name, 5, "$name: keepalive $keepalive";
  my $msg = join("", map { pack("n", length($_)).$_.pack("C",0) } # QOS:0
                     split(" ", AttrVal($name, "subscriptions", "#")));
  addToWritebuffer($hash,
    pack("C",0xC0).pack("C",0));
  InternalTimer(gettimeofday()+$keepalive, "MQTT2_CLIENT_keepalive", $hash, 0);
}

sub
MQTT2_CLIENT_Undef($@)
{
  my ($hash, $arg) = @_;
  DevIo_CloseDev($hash);
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

  if($attrName eq "clientId") {
    $hash->{clientId} = $param[0];
    $hash->{clientId} =~ s/[^0-9a-zA-Z]//g;
    $hash->{clientId} = "MQTT2_CLIENT" if(!$hash->{clientId});
  }

  my %h = (clientId=>1,lwt=>1,lwtRetain=>1,subscriptions=>1,SSL=>1,username=>1);
  if($init_done && $h{$attrName}) {
    MQTT2_CLIENT_Disco($hash);
  }
  return undef;
} 

sub
MQTT2_CLIENT_Disco($)
{
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  $hash->{connecting} = 1;
  DevIo_Disconnected($hash);
}

sub
MQTT2_CLIENT_Set($@)
{
  my ($hash, @a) = @_;
  my %sets = ( password=>2, publish=>2 );
  my $name = $hash->{NAME};
  shift(@a);

  return "Unknown argument ?, choose one of ".join(" ", keys %sets)
        if(!$a[0] || !$sets{$a[0]});

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
    MQTT2_CLIENT_doPublish($hash, $tp, $val, $retain);
  }

  if($a[0] eq "password") {
    return "Usage: set $name password <password>" if(@a < 1);
    setKeyValue($name, $a[1]);
    MQTT2_CLIENT_Disco($hash) if($init_done);
  }
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
    return "" if(!defined($buf));
    $hash->{BUF} .= $buf;
  }

  my ($tlen, $off) = MQTT2_CLIENT_getRemainingLength($hash);
  if($tlen < 0) {
    Log3 $name, 1, "Bogus data from $name, closing connection";
    MQTT2_CLIENT_Disco($hash);
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
    Log3 $name, 5, "$cpt: $pltxt";
  }

  ####################################
  if($cpt eq "CONNACK")  {
    my $rc = ord(substr($fb,1,1));
    if($rc == 0) {
      MQTT2_CLIENT_doinit($hash);

    } else {
      my @txt = ("Accepted", "bad proto", "bad id", "server unavailable",
                  "bad user name or password", "not authorized");
      Log3 1, $name, "$name: Connection refused, ".
        ($rc <= int(@txt) ? $txt[$rc] : "unknown error $rc");
      MQTT2_CLIENT_Disco($hash);
      return;
    }
  } elsif($cpt eq "PUBACK")   { # ignore it
  } elsif($cpt eq "SUBACK")   {
    delete($hash->{connecting});

  } elsif($cpt eq "PINGRESP") { # ignore it
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
    addToWritebuffer($hash, pack("CCnC*", 0x40, 2, $pid)) if($qos); # PUBACK

    $val = "" if(!defined($val));
    my $ac = AttrVal($name, "autocreate", undef) ? "autocreate:":"";
    my $cid = $hash->{clientId};
    Dispatch($hash, "$ac$cid:$tp:$val", undef, !$ac);

    my $re = AttrVal($name, "rawEvents", undef);
    DoTrigger($name, "$tp:$val") if($re && $tp =~ m/$re/);

  } else {
    Log 1, "M2: Unhandled packet $cpt, disconneting $name";
    MQTT2_CLIENT_Disco($hash);
  }
  return MQTT2_CLIENT_Read($hash, 1);
}

######################################
# send topic to client if its subscription matches the topic
sub
MQTT2_CLIENT_doPublish($$$$)
{
  my ($hash, $topic, $val, $retain) = @_;
  my $name = $hash->{NAME};
  return if(IsDisabled($name));
  $val = "" if(!defined($val));
  addToWritebuffer($hash,
    pack("C",0x30).
    MQTT2_CLIENT_calcRemainingLength(2+length($topic)+length($val)).
    pack("n", length($topic)).
    $topic.$val);
}

sub
MQTT2_CLIENT_Write($$$)
{
  my ($hash,$topic,$msg) = @_;
  my $retain;
  if($topic =~ m/^(.*):r$/) {
    $topic = $1;
    $retain = 1;
  }
  MQTT2_CLIENT_doPublish($hash, $topic, $msg, $retain);
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
=item helper
=item summary    Connection to an external MQTT server
=item summary_DE Verbindung zu einem externen MQTT Server
=begin html

<a name="MQTT2_CLIENT"></a>
<h3>MQTT2_CLIENT</h3>
<ul>
  MQTT2_CLIENT is a cleanroom implementation of an MQTT client (which connects
  to an external server, like mosquitto) using no perl libraries. It serves as
  an IODev to MQTT2_DEVICES.
  <br> <br>

  <a name="MQTT2_CLIENTdefine"></a>
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

  <a name="MQTT2_CLIENTset"></a>
  <b>Set</b>
  <ul>
    <li>publish -r topic value<br>
      publish a message, -r denotes setting the retain flag.
      </li><br>
    <li>password &lt;password&gt; value<br>
      set the password, which is stored in the FHEM/FhemUtils/uniqueID file.
      </li>
  </ul>
  <br>

  <a name="MQTT2_CLIENTget"></a>
  <b>Get</b>
  <ul>N/A</ul><br>

  <a name="MQTT2_CLIENTattr"></a>
  <b>Attributes</b>
  <ul>

    <a name="autocreate"></a>
    <li>autocreate<br>
      if set, at least one MQTT2_DEVICE will be created, and its readingsList
      will be expanded upon reception of published messages. Note: this is
      slightly different from MQTT2_SERVER, where each connection has its own
      clientId.  This parameter is sadly not transferred via the MQTT protocol,
      so the clientId of this MQTT2_CLIENT instance will be used.
      </li></br>

    <a name="clientId"></a>
    <li>clientId &lt;name&gt;<br>
      set the MQTT clientId. If not set, the name of the MQTT2_CLIENT instance
      is used, after deleting everything outside 0-9a-zA-Z
      </li></br>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a><br>
      disable dispatching of messages.
      </li><br>

    <a name="lwt"></a>
    <li>lwt &lt;topic&gt; &lt;message&gt; <br>
      set the LWT (last will and testament) topic and message, default is empty.
      </li></br>

    <a name="lwtRetain"></a>
    <li>lwtRetain<br>
      if set, the lwt retain flag is set
      </li></br>

    <a name="mqttVersion"></a>
    <li>mqttVersion 3.1,3.1.1<br>
      set the MQTT protocol version in the CONNECT header, default is 3.1
      </li></br>

    <a name="rawEvents"></a>
    <li>rawEvents &lt;topic-regexp&gt;<br>
      send all messages as events attributed to this MQTT2_CLIENT instance.
      Should only be used, if there is no MQTT2_DEVICE to process the topic.
      </li><br>

    <a name="subscriptions"></a>
    <li>subscriptions &lt;subscriptions&gt;<br>
      space separated list of MQTT subscriptions, default is #
      </li><br>

    <a name="SSL"></a>
    <li>SSL<br>
      Enable SSL (i.e. TLS)
      </li><br>

    <a name="username"></a>
    <li>username &lt;username&gt;<br>
      set the username. The password is set via the set command, and is stored
      separately, see above.
      </li><br>

  </ul>
</ul>
=end html

=cut
