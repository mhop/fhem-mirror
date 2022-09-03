##############################################
# $Id$
package main;

use strict;
use warnings;
use TcpServerUtils;
use MIME::Base64;

sub MQTT2_SERVER_Read($@);
sub MQTT2_SERVER_Write($$$);
sub MQTT2_SERVER_Undef($@);
sub MQTT2_SERVER_doPublish($$$$;$);

use vars qw($FW_chash);   # client fhem hash
use vars qw(%FW_id2inform);

# See also:
# http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html

sub
MQTT2_SERVER_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "MQTT2_SERVER_Read";
  $hash->{DefFn}   = "MQTT2_SERVER_Define";
  $hash->{AttrFn}  = "MQTT2_SERVER_Attr";
  $hash->{SetFn}   = "MQTT2_SERVER_Set";
  $hash->{UndefFn} = "MQTT2_SERVER_Undef";
  $hash->{WriteFn} = "MQTT2_SERVER_Write";
  $hash->{StateFn} = "MQTT2_SERVER_State";
  $hash->{CanAuthenticate} = 1;

  no warnings 'qw';
  my @attrList = qw(
    SSL:0,1
    allowfrom
    autocreate:no,simple,complex
    binaryTopicRegexp
    clientId
    clientOrder
    disable:1,0
    disabledForIntervals
    hideRetain:1,0
    ignoreRegexp
    keepaliveFactor
    rePublish:1,0
    rawEvents
    sslVersion
    sslCertPrefix
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  $hash->{FW_detailFn} = "MQTT2_SERVER_fhemwebFn";
}

sub
MQTT2_SERVER_resetClients($)
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
MQTT2_SERVER_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> MQTT2_SERVER [IPV6:]<tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/);

  MQTT2_SERVER_resetClients($hash);
  MQTT2_SERVER_Undef($hash, undef) if($hash->{OLDDEF}); # modify
  my $ret = TcpServer_Open($hash, $port, $global);

  # Make sure that fhem only runs once
  if($ret && !$init_done) {
    Log3 $hash, 1, "$ret. Exiting.";
    exit(1);
  }
  readingsSingleUpdate($hash, "nrclients", 0, 0);
  $hash->{clients} = {};
  $hash->{retain} = {};
  InternalTimer(1, "MQTT2_SERVER_keepaliveChecker", $hash, 0);
  return $ret;
}

sub
MQTT2_SERVER_keepaliveChecker($)
{
  my ($hash) = @_;
  my $now = gettimeofday();
  my $multiplier = AttrVal($hash->{NAME}, "keepaliveFactor", 1.5);
  if($multiplier) {
    foreach my $clName (keys %{$hash->{clients}}) {
      my $cHash = $defs{$clName};
      next if(!$cHash || !$cHash->{keepalive} ||
               $now < $cHash->{lastMsgTime}+$cHash->{keepalive}*$multiplier );
      my $msgName = $clName;
      $msgName .= "/".$cHash->{cid} if($cHash->{cid});
      CommandDelete(undef, $clName);
      Log3 $hash, 3, "$hash->{NAME}: $msgName left us (keepalive check)"
        if(!$cHash->{isReplaced});
    }
  }
  InternalTimer($now+10, "MQTT2_SERVER_keepaliveChecker", $hash, 0);
}

sub
MQTT2_SERVER_Undef($@)
{
  my ($hash, $arg) = @_;
  my $ret = TcpServer_Close($hash);
  my $sname = $hash->{SNAME};
  return undef if(!$sname);

  my $shash = $defs{$sname};
  delete($shash->{clients}{$hash->{NAME}});
  readingsSingleUpdate($shash, "nrclients",
                       ReadingsVal($sname, "nrclients", 1)-1, 1);

  if($hash->{lwt}) {    # Last will

    # skip lwt if there is another connection with the same ip+cid (tasmota??)
    for my $dev (keys %defs) {
      my $h = $defs{$dev};
      next if($h->{TYPE} ne $hash->{TYPE} ||
              $h->{NR} == $hash->{NR} ||
              !$h->{cid}  || $h->{cid}  ne $hash->{cid} ||
              !$h->{PEER} || $h->{PEER} ne $hash->{PEER});
      Log3 $shash, 4,
        "Closing second connection for $h->{cid}/$h->{PEER} without lwt";
      $hash->{isReplaced} = 1;
      return $ret;
    }

    my ($tp, $val) = split(':', $hash->{lwt}, 2);
    MQTT2_SERVER_doPublish($hash, $shash, $tp, $val, $hash->{cflags} & 0x20);
  }
  return $ret;
}

sub
MQTT2_SERVER_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};
  if($type eq "set" && $attrName eq "SSL") {
    InternalTimer(1, "TcpServer_SetSSL", $hash, 0); # Wait for sslCertPrefix
  }

  if($type eq "set" && $attrName eq "ignoreRegexp") {
    my $re = join(" ",@param);
    return "bad $devName ignoreRegexp: $re" if($re eq "1" || $re =~ m/^\*/);
    eval { "Hallo" =~ m/$re/ };
    return "bad $devName ignoreRegexp: $re: $@" if($@);
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
      MQTT2_SERVER_resetClients($hash);
    }
  }

  if($attrName eq "binaryTopicRegexp") {
    if($type eq "set") {
      return "Bad regexp $param[0]: starting with *" if($param[0] =~ m/^\*/);
      eval { "hallo" =~ m/^$param[0]$/ };
      return "Error checking regexp $param[0]:$@" if($@);
      $hash->{binaryTopicRegexp} = $param[0];
    } else {
      delete($hash->{binaryTopicRegexp});
    }
  }

  if($attrName eq "hideRetain") {
    my $hide = ($type eq "set" && $param[0]);
    if($hide) {
      if($hash->{READINGS}{RETAIN}) {
        $hash->{READINGS}{".RETAIN"} = $hash->{READINGS}{RETAIN};
        delete($hash->{READINGS}{RETAIN});
      }
    } else {
      if($hash->{READINGS}{".RETAIN"}) {
        $hash->{READINGS}{RETAIN} = $hash->{READINGS}{".RETAIN"};
        delete($hash->{READINGS}{".RETAIN"});
      }
    }
  }

  return undef;
} 

sub
MQTT2_SERVER_Set($@)
{
  my ($hash, @a) = @_;
  my %sets = ( publish=>":textField,[-r]&nbsp;topic&nbsp;message",
               clearRetain=>":noArg" );
  shift(@a);

  return "Unknown argument ?, choose one of ".
                    join(" ", map { "$_$sets{$_}" } keys %sets)
        if(!$a[0] || !defined($sets{$a[0]}));

  if($a[0] eq "publish") {
    shift(@a);
    my $retain;
    if(@a>1 && $a[0] eq "-r") {
      $retain = 1;
      shift(@a);
    }
    return "Usage: publish -r topic [value]" if(@a < 1);
    my $tp = shift(@a);
    my $val = join(" ", @a);
    readingsSingleUpdate($hash, "lastPublish", "$tp:$val", 1);
    MQTT2_SERVER_doPublish($hash->{CL}, $hash, $tp, $val, $retain);

  } elsif($a[0] eq "clearRetain") {
    my $rname = AttrVal($hash->{NAME}, "hideRetain", 0) ? ".RETAIN" : "RETAIN";
    delete($hash->{READINGS}{$rname});
    delete($hash->{retain});
    return undef;
  }
}

sub
MQTT2_SERVER_State()
{
  my ($hash, $ts, $name, $val) = @_;

  if($name eq "RETAIN" || $name eq ".RETAIN") {
    my $now = gettimeofday;
    my $ret = json2nameValue($val);
    for my $k (keys %{$ret}) {
      my %h = ( ts=>$now, val=>$ret->{$k} );
      $hash->{retain}{$k} = \%h;
    }

    my $rname = AttrVal($hash->{NAME}, "hideRetain", 0) ? "RETAIN" : ".RETAIN";
    if($name ne $rname) {
      InternalTimer(0, sub {
        $hash->{READINGS}{$rname} = $hash->{READINGS}{$name};
        delete($hash->{READINGS}{$name});
      }, undef);
    }
  }
  return undef;
}

my %cptype = (
  0 => "RESERVED_0",
  1 => "CONNECT",
  2 => "CONNACK",
  3 => "PUBLISH",
  4 => "PUBACK",
  5 => "PUBREC",
  6 => "PUBREL",
  7 => "PUBCOMP",
  8 => "SUBSCRIBE",
  9 => "SUBACK",
 10 => "UNSUBSCRIBE",
 11 => "UNSUBACK",
 12 => "PINGREQ",
 13 => "PINGRESP",
 14 => "DISCONNECT",
 15 => "RESERVED_15",
);

#####################################
sub
MQTT2_SERVER_out($$$;$)
{
  my ($hash, $msg, $dump, $callback) = @_;
  addToWritebuffer($hash, $msg, $callback) if(defined($hash->{FD}));
  if($dump) {
    my $cpt = $cptype{ord(substr($msg,0,1)) >> 4};
    $msg =~ s/([^ -~])/"(".ord($1).")"/ge;
    Log3 $dump, 5, "out\@$hash->{PEER}:$hash->{PORT} $cpt: $msg";
  }
}

sub
MQTT2_SERVER_Read($@)
{
  my ($hash, $reread) = @_;

  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $nhash = TcpServer_Accept($hash, "MQTT2_SERVER");
    return if(!$nhash);
    $nhash->{CD}->blocking(0);
    readingsSingleUpdate($hash, "nrclients",
                         ReadingsVal($hash->{NAME}, "nrclients", 0)+1, 1);
    return;
  }

  my $sname = $hash->{SNAME};
  my $shash = $defs{$sname};
  my $cname = $hash->{NAME};
  my $c = $hash->{CD};

  if(!$reread) {
    my $buf;
    my $ret = sysread($c, $buf, 1024);

    if(!defined($ret) && $! == EWOULDBLOCK ){
      $hash->{wantWrite} = 1
        if(TcpServer_WantWrite($hash));
      return;

    } elsif(!$ret) {
      CommandDelete(undef, $cname);
      Log3 $sname, 4, "Connection closed for $cname: ".
        (defined($ret) ? 'EOF' : $!);
      return;
    }

    $hash->{BUF} .= $buf;
    if($hash->{SSL} && $c->can('pending')) {
      while($c->pending()) {
        sysread($c, $buf, 1024);
        $hash->{BUF} .= $buf;
      }
    }
  }

  my ($tlen, $off) = MQTT2_SERVER_getRemainingLength($hash);
  if($tlen < 0) {
    Log3 $sname, 1, "Bogus data from $cname, closing connection";
    return CommandDelete(undef, $cname);
  }
  return if(length($hash->{BUF}) < $tlen+$off);

  my $fb = substr($hash->{BUF}, 0, 1);
  my $pl = substr($hash->{BUF}, $off, $tlen); # payload

  my $cp = ord(substr($fb,0,1)) >> 4;
  my $cpt = $cptype{$cp};
  $hash->{lastMsgTime} = gettimeofday();

  # Lowlevel debugging
  my $dump = (AttrVal($sname, "verbose", 1) >= 5) ? $sname : undef;
  if($dump) {
    my $msg = substr($hash->{BUF}, 0, $off+$tlen);
    $msg =~ s/([^ -~])/"(".ord($1).")"/ge;
    Log3 $sname, 5, "in\@$hash->{PEER}:$hash->{PORT} $cpt: $msg";
  }

  $hash->{BUF} = substr($hash->{BUF}, $tlen+$off);

  if(!defined($hash->{cid}) && $cpt ne "CONNECT") {
    Log3 $sname, 2, "$cname $cpt before CONNECT, disconnecting";
    return CommandDelete(undef, $cname);
  }

  ####################################
  if($cpt eq "CONNECT") {
    # V3:MQIsdb V4:MQTT
    if(ord($fb) & 0xf) { # lower nibble must be zero
      Log3 $sname, 3, "$cname with bogus CONNECT (".ord($fb)."), disconnecting";
      Log3 $sname, 3, "TLS activated on the client but not on the server?"
        if(!AttrVal($sname,"TLS",0) && ord($fb) == 22);
      return CommandDelete(undef, $cname);
    }
    ($hash->{protoTxt}, $off) = MQTT2_SERVER_getStr($hash, $pl, 0);
    $hash->{protoNum}  = unpack('C*', substr($pl,$off++,1)); # 3 or 4
    $hash->{cflags}    = unpack('C*', substr($pl,$off++,1));
    $hash->{keepalive} = unpack('n', substr($pl, $off, 2)); $off += 2;
    my $cid;
    ($cid, $off) = MQTT2_SERVER_getStr($hash, $pl, $off);

    if($hash->{protoNum} > 4) {
      return MQTT2_SERVER_out($hash, pack("C*", 0x20, 2, 0, 1), $dump,
                                sub{ CommandDelete(undef, $hash->{NAME}); });
    }

    my $desc = "keepAlive:$hash->{keepalive}";
    if($hash->{cflags} & 0x04) { # Last Will & Testament
      my ($wt, $wm);
      ($wt, $off) = MQTT2_SERVER_getStr($hash, $pl, $off);
      ($wm, $off) = MQTT2_SERVER_getStr($hash, $pl, $off);
      $hash->{lwt} = "$wt:$wm";
      $desc .= " LWT:$wt:$wm";
    }

    my ($pwd, $usr) = ("","");
    if($hash->{cflags} & 0x80) {
      ($usr,$off) = MQTT2_SERVER_getStr($hash, $pl,$off);
      $hash->{usr} = $usr;
      $desc .= " usr:$hash->{usr}";
    }

    if($hash->{cflags} & 0x40) {
      ($pwd, $off) = MQTT2_SERVER_getStr($hash, $pl,$off);
    }

    my $ret = Authenticate($hash, "basicAuth:".encode_base64("$usr:$pwd"));
    if($ret == 2) { # CONNACK, Error
      delete($hash->{lwt}); # Avoid autocreate, #121587
      return MQTT2_SERVER_out($hash, pack("C*", 0x20, 2, 0, 4), $dump, 
                                sub{ CommandDelete(undef, $hash->{NAME}); });
    }

    $hash->{subscriptions} = {};
    $shash->{clients}{$cname} = 1;
    $hash->{cid} = $cid; #124699

    Log3 $sname, 4, "  $cname cid:$hash->{cid} $cpt V:$hash->{protoNum} $desc";
    MQTT2_SERVER_out($hash, pack("C*", 0x20, 2, 0, 0), $dump); # CONNACK+OK

  ####################################
  } elsif($cpt eq "PUBLISH") {
    my $cf = ord(substr($fb,0,1)) & 0xf;
    my $qos = ($cf & 0x06) >> 1;
    my ($tp, $val, $pid);
    ($tp, $off) = MQTT2_SERVER_getStr($hash, $pl, 0);
    if($qos && length($pl) >= $off+2) {
      $pid = unpack('n', substr($pl, $off, 2));
      $off += 2;
    }
    $val = (length($pl)>$off ? substr($pl, $off) : "");
    if($unicodeEncoding) {
      if(!$shash->{binaryTopicRegexp} || $tp !~ m/^$shash->{binaryTopicRegexp}$/) {
        $val = Encode::decode('UTF-8', $val);
      }
    }
    Log3 $sname, 4, "  $cname $hash->{cid} $cpt $tp:$val";
    # PUBACK
    MQTT2_SERVER_out($hash, pack("CCnC*", 0x40, 2, $pid), $dump) if($qos);
    MQTT2_SERVER_doPublish($hash, $shash, $tp, $val, $cf & 0x01);

  ####################################
  } elsif($cpt eq "PUBACK") { # ignore it

  ####################################
  } elsif($cpt eq "SUBSCRIBE") {
    Log3 $sname, 4, "  $cname $hash->{cid} $cpt";
    my $pid = unpack('n', substr($pl, 0, 2));
    my ($subscr, @ret);
    $off = 2;
    while($off < $tlen) {
      ($subscr, $off) = MQTT2_SERVER_getStr($hash, $pl, $off);
      my $qos = unpack("C*", substr($pl, $off++, 1));
      $hash->{subscriptions}{$subscr} = $hash->{lastMsgTime};
      Log3 $sname, 4, "  topic:$subscr qos:$qos";
      push @ret, ($qos > 1 ? 1 : 0);    # max qos supported is 1
    }
    # SUBACK
    MQTT2_SERVER_out($hash, pack("CCnC*", 0x90, 2+@ret, $pid, @ret), $dump);

    if(!$hash->{answerScheduled}) {
      $hash->{answerScheduled} = 1;
      InternalTimer($hash->{lastMsgTime}+1, sub(){
        return if(!$hash->{FD}); # Closed in the meantime, #114425
        delete($hash->{answerScheduled});
        my $r = $shash->{retain};
        foreach my $tp (sort { $r->{$a}{ts} <=> $r->{$b}{ts} } keys %{$r}) {
          MQTT2_SERVER_sendto($shash, $hash, $tp, $r->{$tp}{val});
        }
      }, undef, 0);
    }

  ####################################
  } elsif($cpt eq "UNSUBSCRIBE") {
    Log3 $sname, 4, "  $cname $hash->{cid} $cpt";
    my $pid = unpack('n', substr($pl, 0, 2));
    my ($subscr, @ret);
    $off = 2;
    while($off < $tlen) {
      ($subscr, $off) = MQTT2_SERVER_getStr($hash, $pl, $off);
      delete $hash->{subscriptions}{$subscr};
      Log3 $sname, 4, "  topic:$subscr";
    }
    MQTT2_SERVER_out($hash, pack("CCn", 0xb0, 2, $pid), $dump); # UNSUBACK

  ####################################
  } elsif($cpt eq "PINGREQ") {
    Log3 $sname, 4, "  $cname $hash->{cid} $cpt";
    MQTT2_SERVER_out($hash, pack("C*", 0xd0, 0), $dump); # PINGRESP

  ####################################
  } elsif($cpt eq "DISCONNECT") {
    Log3 $sname, 4, "  $cname $hash->{cid} $cpt";
    delete($hash->{lwt}); # no LWT on disconnect, see doc, chapter 3.14
    return CommandDelete(undef, $cname);

  ####################################
  } else {
    Log 1, "ERROR: Unhandled packet $cpt, disconnecting $cname";
    return CommandDelete(undef, $cname);

  }
  if($hash->{stringError}) {
    Log3 $sname, 2,
        "ERROR: $cname $hash->{cid} received bogus data, disconnecting";
    return CommandDelete(undef, $cname);
  }

  # Allow some IO inbetween, for overloaded systems
  InternalTimer(0, sub{ MQTT2_SERVER_Read($hash,1)}, $hash, 0)
        if(length($hash->{BUF}) > 0);
}

######################################
# Call sendto for all clients + Dispatch + dotrigger if rawEvents is set
# server is the "accept" server, src is the connection generating the data
sub
MQTT2_SERVER_doPublish($$$$;$)
{
  my ($src, $server, $tp, $val, $retain) = @_;
  $val = "" if(!defined($val));
  $src = $server if(!defined($src));

  if($retain) {
    if(!defined($val) || $val eq "") {
      delete($server->{retain}{$tp});
    } else {
      my $now = gettimeofday();
      my %h = ( ts=>$now, val=>$val );
      $server->{retain}{$tp} = \%h;
    }


    # Save it
    my %nots = map { $_ => $server->{retain}{$_}{val} }
               keys %{$server->{retain}};
    my $rname = AttrVal($server->{NAME}, "hideRetain", 0) ? ".RETAIN" : "RETAIN";
    setReadingsVal($server, $rname, toJSON(\%nots), FmtDateTime(gettimeofday()));
  }

  foreach my $clName (keys %{$server->{clients}}) {
    MQTT2_SERVER_sendto($server, $defs{$clName}, $tp, $val);
  }

  my $serverName = $server->{NAME};
  my $ir = AttrVal($serverName, "ignoreRegexp", undef);
  return if(defined($ir) && "$tp:$val" =~ m/$ir/);

  my $cid = $src->{cid};
  $tp =~ s/:/_/g; # 96608
  if(defined($cid) ||                    # "real" MQTT client
     AttrVal($serverName, "rePublish", undef)) {
    $cid = $src->{NAME} if(!defined($cid));
    $cid =~ s,[^a-z0-9._],_,gi;
    my $ac = AttrVal($serverName, "autocreate", "simple");
    $ac = $ac eq "1" ? "simple" : ($ac eq "0" ? "no" : $ac); # backward comp.

    $cid = AttrVal($serverName, "clientId", $cid);
    my %addvals = (CONN => $src->{NAME});
    Dispatch($server, "autocreate=$ac\0$cid\0$tp\0$val",\%addvals, $ac eq "no"); 
    my $re = AttrVal($serverName, "rawEvents", undef);
    DoTrigger($server->{NAME}, "$tp:$val") if($re && $tp =~ m/$re/);
  }

  my $fl = $server->{".feedList"};
  if($fl) {
    foreach my $fwid (keys %{$fl}) {
      my $cl = $FW_id2inform{$fwid};
      if(!$cl || !$cl->{inform}{filter} || $cl->{inform}{filter} ne '^$') {
        delete($fl->{$fwid});
        next;
      }
      FW_AsyncOutput($cl, "", toJSON([defined($cid)?$cid:"SENT", $tp, $val]));
    }
    delete($server->{".feedList"}) if(!keys %{$fl});
  }
}

######################################
# send topic to client if its subscription matches the topic
sub
MQTT2_SERVER_sendto($$$$)
{
  my ($shash, $hash, $topic, $val) = @_;
  return if(IsDisabled($hash->{NAME}));
  $val = "" if(!defined($val));
  my $dump = (AttrVal($shash->{NAME},"verbose",1)>=5) ? $shash->{NAME} :undef;

  my $ltopic = $topic;
  my $lval = $val;
  if($unicodeEncoding) {
    $ltopic = Encode::encode('UTF-8', $topic);
    $lval   = Encode::encode('UTF-8', $val);
  }

  foreach my $s (keys %{$hash->{subscriptions}}) {
    my $re = $s;
    $re =~ s,^#$,.*,g;
    $re =~ s,/?#,\\b.*,g;
    $re =~ s,\+,\\b[^/]+\\b,g;
    if($topic =~ m/^$re$/) {
      Log3 $shash, 5, "  $hash->{NAME} $hash->{cid} => $topic:$val";
      MQTT2_SERVER_out($hash,                  # PUBLISH
        pack("C",0x30).
        MQTT2_SERVER_calcRemainingLength(2+length($ltopic)+length($lval)).
        pack("n", length($ltopic)).
        $ltopic.$lval, $dump);
      last;       # send a message only once
    }
  }
}

sub
MQTT2_SERVER_Write($$$)
{
  my ($hash,$function,$topicMsg) = @_;

  my $name = $hash->{NAME};
  if($function eq "publish") {
    my ($topic, $msg) = split(" ", $topicMsg, 2);
    my $retain;
    if($topic =~ m/^(.*):r$/) {
      $topic = $1;
      $retain = 1;
    }

    Log3 $name, 5, "$name: PUBLISH $topicMsg";
    MQTT2_SERVER_doPublish($hash, $hash, $topic, $msg, $retain);

  } else {
    Log3 $name, 1, "$name: ERROR: Ignoring function $function";
  }
  return undef;
}

sub
MQTT2_SERVER_calcRemainingLength($)
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
MQTT2_SERVER_getRemainingLength($)
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
MQTT2_SERVER_getStr($$$)
{
  my ($hash, $in, $off) = @_;
  my $l = unpack("n", substr($in, $off, 2));
  my $r = substr($in, $off+2, $l);
  $hash->{stringError} = 1 if(index($r, "\0") >= 0);
  $r = Encode::decode('UTF-8', $r) if($unicodeEncoding);
  return ($r, $off+2+$l);
}

sub
MQTT2_SERVER_fhemwebFn()
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return '' if($pageHash);

  return << "JSEND"
  <div id="m2s_cons"><a href="#">Show MQTT traffic</a></div>
  <script type="text/javascript">
    \$(document).ready(function() {
      \$("#m2s_cons a")
        .click(function(e){
          loadScript("pgm2/console.js", function() {
            cons4dev('#m2s_cons', '^\$', 'MQTT2_SERVER_addToFeedList', '$d');
          });
        });
    });
  </script>
JSEND
}

sub
MQTT2_SERVER_addToFeedList($$)
{
  my ($name, $turnOn) = @_;
  my $hash = $defs{$name};
  return if(!$hash);

  my $fwid = $FW_chash->{FW_ID};
  $hash->{".feedList"} = () if(!$hash->{".feedList"});
  if($turnOn) {
    $hash->{".feedList"}{$fwid} = 1;

  } else {
    delete($hash->{".feedList"}{$fwid});
    delete($hash->{".feedList"}) if(!keys %{$hash->{".feedList"}});
  }
  return undef;
}

# {MQTT2_SERVER_ReadDebug("m2s", '0(12)(0)(5)HelloWorld')}
sub
MQTT2_SERVER_ReadDebug($$)
{
  my ($name, $s) = @_;
  $s =~ s/\((\d{1,3})\)/chr($1)/ge;
  Log 1, "Debug len:".length($s);
  my $cName = $name."_debugClient";
  $defs{$cName} = { NAME=>$cName, SNAME=>$name, cid=>$name,
                    TYPE=>"MQTT2_SERVER", PEER=>"", PORT=>"", BUF=>$s };
  MQTT2_SERVER_Read($defs{$cName}, 1);
  delete($attr{$cName});
  delete($defs{$cName});
}

1;

=pod
=item summary    Standalone MQTT message broker
=item summary_DE Standalone MQTT message broker
=begin html

<a id="MQTT2_SERVER"></a>
<h3>MQTT2_SERVER</h3>
<ul>
  MQTT2_SERVER is a builtin/cleanroom implementation of an MQTT server using no
  external libraries. It serves as an IODev to MQTT2_DEVICES, but may be used
  as a replacement for standalone servers like mosquitto (with less features
  and performance). It is intended to simplify connecting MQTT devices to FHEM.
  <br> <br>

  <a id="MQTT2_SERVER-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MQTT2_SERVER &lt;tcp-portnr&gt; [global|IP]</code>
    <br><br>
    Enable the server on port &lt;tcp-portnr&gt;. If global is specified,
    then requests from all interfaces (not only localhost / 127.0.0.1) are
    serviced. If IP is specified, then MQTT2_SERVER will only listen on this
    IP.<br>
    To enable listening on IPV6 see the comments <a href="#telnet">here</a>.
    <br>
    Notes:<br>
    <ul>
    <li>to set user/password use an allowed instance and its basicAuth
      feature (set/attr)</li>
    <li>the retain flag is not propagated by publish</li>
    <li>only QOS 0 and 1 is implemented</li>
    </ul>
  </ul>
  <br>

  <a id="MQTT2_SERVER-set"></a>
  <b>Set</b>
  <ul>
    <a id="MQTT2_SERVER-set-publish"></a>
    <li>publish [-r] topic value<br>
      publish a message, -r denotes setting the retain flag.
      </li>
    <a id="MQTT2_SERVER-set-clearRetain"></a>
    <li>clearRetain<br>
      delete all the retained topics.
      </li>
  </ul>
  <br>

  <a id="MQTT2_SERVER-get"></a>
  <b>Get</b>
  <ul>N/A</ul><br>

  <a id="MQTT2_SERVER-attr"></a>
  <b>Attributes</b>
  <ul>

    <li><a href="#allowfrom">allowfrom</a>
      </li><br>

    <a id="MQTT2_SERVER-attr-autocreate"></a>
    <li>autocreate [no|simple|complex]<br>
      MQTT2_DEVICES will be automatically created upon receiving an
      unknown message. Set this value to no to disable autocreating, the
      default is simple.<br>
      With simple the one-argument version of json2nameValue is added:
      json2nameValue($EVENT), with complex the full version:
      json2nameValue($EVENT, 'SENSOR_', $JSONMAP). Which one is better depends
      on the attached devices and on the personal taste, and it is only
      relevant for json payload. For non-json payload there is no difference
      between simple and complex.
      </li><br>

    <a id="MQTT2_SERVER-attr-binaryTopicRegexp"></a>
    <li>binaryTopicRegexp &lt;regular-expression&gt;<br>
      this attribute is only relevant, if the global attribute "encoding
      unicode" is set.<br>
      In this case the MQTT payload is automatically assumed to be UTF-8, which
      may cause conversion-problems if the payload is binary. This conversion
      wont take place, if the topic matches the regular expression specified.
      Note: as is the case with other modules, ^ and $ is added to the regular
      expression.
    </li><br>

    <a id="MQTT2_SERVER-attr-clientId"></a>
    <li>clientId &lt;name&gt;<br>
      set the MQTT clientId for all connections, for setups with clients
      creating a different MQTT-ID for each connection. The autocreate
      capabilities are greatly reduced in this case, and setting it requires to
      remove the clientId from all existing MQTT2_DEVICE readingList
      attributes.
      </li></br>

    <a id="MQTT2_SERVER-attr-clientOrder"></a>
    <li>clientOrder [MQTT2_DEVICE] [MQTT_GENERIC_BRIDGE]<br>
      set the notification order for client modules. This is 
      relevant when autocreate is active, and the default order
      (MQTT2_DEVICE MQTT_GENERIC_BRIDGE) is not adequate.
      Note: Changing the attribute affects _all_ MQTT2_SERVER instances.
      </li></br>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a><br>
      disable distribution of messages. The server itself will accept and store
      messages, but not forward them.
      </li><br>

    <a id="MQTT2_SERVER-attr-hideRetain"></a>
    <li>hideRetain [0|1]<br>
      if set to 1, the RETAIN reading will be named .RETAIN, i.e. hidden by
      default.
      </li>

    <a id="MQTT2_SERVER-attr-ignoreRegexp"></a>
    <li>ignoreRegexp<br>
      if $topic:$message matches ignoreRegexp, then it will be silently ignored.
      </li>

    <a id="MQTT2_SERVER-attr-keepaliveFactor"></a>
    <li>keepaliveFactor<br>
      the oasis spec requires a disconnect, if after 1.5 times the client
      supplied keepalive no data or PINGREQ is sent. With this attribute you
      can modify this factor, 0 disables the check. 
      Notes:
      <ul>
        <li>dont complain if you set this attribute to less or equal to 1.</li>
        <li>MQTT2_SERVER checks the keepalive only every 10 second.</li>
      </ul>
      </li>
    
    <a id="MQTT2_SERVER-attr-rawEvents"></a>
    <li>rawEvents &lt;topic-regexp&gt;<br>
      Send all messages as events attributed to this MQTT2_SERVER instance.
      Should only be used, if there is no MQTT2_DEVICE to process the topic.
      </li><br>

    <a id="MQTT2_SERVER-attr-rePublish"></a>
    <li>rePublish<br>
      if a topic is published from a source inside of FHEM (e.g. MQTT2_DEVICE),
      it is only sent to real MQTT clients, and it will not internally
      republished. By setting this attribute the topic will also be dispatched
      to the FHEM internal clients.
      </li><br>

    <a id="MQTT2_SERVER-attr-SSL"></a>
    <li>SSL<br>
      Enable SSL (i.e. TLS). Note: after deleting this attribute FHEM must be
      restarted.
      </li><br>

    <a id="MQTT2_SERVER-attr-sslVersion"></a>
    <li>sslVersion<br>
       See the global attribute sslVersion.
       </li><br>

    <a id="MQTT2_SERVER-attr-sslCertPrefix"></a>
    <li>sslCertPrefix<br>
       Set the prefix for the SSL certificate, default is certs/server-, see
       also the SSL attribute.
       </li><br>

  </ul>
</ul>
=end html

=cut
