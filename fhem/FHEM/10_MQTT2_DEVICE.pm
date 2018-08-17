##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

sub
MQTT2_DEVICE_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}    = ".*";
  $hash->{SetFn}    = "MQTT2_DEVICE_Set";
  $hash->{GetFn}    = "MQTT2_DEVICE_Get";
  $hash->{DefFn}    = "MQTT2_DEVICE_Define";
  $hash->{UndefFn}  = "MQTT2_DEVICE_Undef";
  $hash->{AttrFn}   = "MQTT2_DEVICE_Attr";
  $hash->{ParseFn}  = "MQTT2_DEVICE_Parse";
  $hash->{RenameFn} = "MQTT2_DEVICE_Rename";

  no warnings 'qw';
  my @attrList = qw(
    IODev
    devicetopic
    disable:0,1
    disabledForIntervals
    readingList:textField-long
    setList:textField-long
    getList:textField-long
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  my %h = ( re=>{}, cid=>{});
  $modules{MQTT2_DEVICE}{defptr} = \%h;
}


#############################
sub
MQTT2_DEVICE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = shift @a;
  my $type = shift @a; # always MQTT2_DEVICE
  $hash->{CID} = shift(@a) if(@a);

  return "wrong syntax for $name: define <name> MQTT2_DEVICE [clientid]"
        if(int(@a));
  $hash->{DEVICETOPIC} = $name;
  $modules{MQTT2_DEVICE}{defptr}{cid}{$hash->{CID}} = $hash if($hash->{CID});

  AssignIoPort($hash);
  return undef;
}

#############################
sub
MQTT2_DEVICE_Parse($$)
{
  my ($iodev, $msg) = @_;
  my $ioname = $iodev->{NAME};
  my %fnd;

  sub
  checkForGet($$$)
  {
    my ($hash, $key, $value) = @_;
    if($hash->{asyncGet} && $key eq $hash->{asyncGet}{reading}) {
      RemoveInternalTimer($hash->{asyncGet});
      asyncOutput($hash->{asyncGet}{CL}, "$key $value");
      delete($hash->{asyncGet});
    }
  }

  my $autocreate;
  if($msg =~ m/^autocreate:(.*)/) {
    $msg = $1;
    $autocreate = 1;
  }

  my ($cid, $topic, $value) = split(":", $msg, 3);
  my $dp = $modules{MQTT2_DEVICE}{defptr}{re};
  foreach my $re (keys %{$dp}) {
    my $reAll = $re;
    $reAll =~ s/\$DEVICETOPIC/\.\*/g;

    next if(!("$topic:$value" =~ m/^$reAll$/s ||
              "$cid:$topic:$value" =~ m/^$reAll$/s));
    foreach my $dev (keys %{$dp->{$re}}) {
      next if(IsDisabled($dev));
      my $hash = $defs{$dev};
      my $reRepl = $re;
      $reRepl =~ s/\$DEVICETOPIC/$hash->{DEVICETOPIC}/g;
      next if(!("$topic:$value" =~ m/^$reRepl$/s ||
                "$cid:$topic:$value" =~ m/^$reRepl$/s));

      my @retData;
      my $code = $dp->{$re}{$dev};
      Log3 $dev, 4, "MQTT2_DEVICE_Parse: $dev $topic => $code";

      if($code =~ m/^{.*}$/s) {
        $code = EvalSpecials($code, ("%TOPIC"=>$topic, "%EVENT"=>$value,
                 "%DEVICETOPIC"=>$hash->{DEVICETOPIC}, "%NAME"=>$hash->{NAME}));
        my $ret = AnalyzePerlCommand(undef, $code);
        if($ret && ref $ret eq "HASH") {
          readingsBeginUpdate($hash);
          foreach my $k (keys %{$ret}) {
            readingsBulkUpdate($hash, $k, $ret->{$k});
            push(@retData, "$k $ret->{$k}");
            checkForGet($hash, $k, $ret->{$k});
          }
          readingsEndUpdate($hash, 1);
        }

      } else {
        readingsSingleUpdate($hash, $code, $value, 1);
        push(@retData, "$code $value");
        checkForGet($hash, $code, $value);
      }

      $fnd{$dev} = 1;
    }
  }

  # autocreate and expand readingList
  if($autocreate && !%fnd) {
    return "" if($cid =~ m/mosqpub.*/);
    my $cidHash = $modules{MQTT2_DEVICE}{defptr}{cid}{$cid};
    my $nn = $cidHash ? $cidHash->{NAME} : "MQTT2_$cid";
    PrioQueue_add(sub{
      return if(!$defs{$nn});
      my $add;
      if($value =~ m/^{.*}$/) {
        my $ret = json2nameValue($value);
        $add = "{ json2nameValue(\$EVENT) }" if(keys %{$ret});
      }
      if(!$add) {
        $topic =~ m,.*/([^/]+),;
        $add = ($1 ? $1 : $topic);
      }
      my $rl = AttrVal($nn, "readingList", "");
      $rl .= "\n" if($rl);
      CommandAttr(undef, "$nn readingList $rl$cid:$topic:.* $add");
    }, undef);
    return "UNDEFINED $nn MQTT2_DEVICE $cid" if(!$cidHash);
    return "";
  }

  return keys %fnd;
}

sub
MQTT2_JSON($;$)
{
  return json2nameValue(@_);
}


#############################
sub
MQTT2_DEVICE_Get($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for get" if(!defined($a[1]));

  my %gets;
  map {  my ($k,$v) = split(" ",$_,2); $gets{$k} = $v; }
        split("\n", AttrVal($hash->{NAME}, "getList", ""));
  return "Unknown argument $a[1], choose one of ".join(" ",sort keys %gets)
        if(!$gets{$a[1]});
  return undef if(IsDisabled($hash->{NAME}));

  my ($getReading, $cmd) = split(" ",$gets{$a[1]},2);
  if($hash->{CL}) {
    my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$getReading };
    $hash->{asyncGet} = $tHash;
    InternalTimer(gettimeofday()+4, sub {
      asyncOutput($tHash->{CL}, "Timeout reading answer for $cmd");
      delete($hash->{asyncGet});
    }, $tHash, 0);
  }

  shift @a;
  if($cmd =~ m/^{.*}$/) {
    $cmd = EvalSpecials($cmd, ("%EVENT"=>join(" ",@a), "%NAME"=>$hash->{NAME}));
    $cmd = AnalyzeCommandChain($hash->{CL}, $cmd);
    return if(!$cmd);
  } else {
    shift @a;
    $cmd .= " ".join(" ",@a) if(@a);
  }

  $cmd =~ s/\$DEVICETOPIC/$hash->{DEVICETOPIC}/g;
  IOWrite($hash, split(" ",$cmd,2));
  return undef;
}

#############################
sub
MQTT2_DEVICE_Set($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for set" if(!defined($a[1]));

  my %sets;
  map {  my ($k,$v) = split(" ",$_,2); $sets{$k} = $v; }
        split("\n", AttrVal($hash->{NAME}, "setList", ""));
  my $cmd = $sets{$a[1]};
  return SetExtensions($hash, join(" ", sort keys %sets), @a) if(!$cmd);
  return undef if(IsDisabled($hash->{NAME}));

  shift @a;
  if($cmd =~ m/^{.*}$/) {
    my $NAME = $hash->{NAME};
    $cmd = EvalSpecials($cmd, ("%EVENT"=>join(" ",@a), "%NAME"=>$hash->{NAME}));
    $cmd = AnalyzeCommandChain($hash->{CL}, $cmd);
    return if(!$cmd);
  } else {
    shift @a;
    $cmd .= " ".join(" ",@a) if(@a);
  }

  $cmd =~ s/\$DEVICETOPIC/$hash->{DEVICETOPIC}/g;
  IOWrite($hash, split(" ",$cmd,2));
  return undef;
}


sub
MQTT2_DEVICE_Attr($$)
{
  my ($type, $dev, $attrName, $param) = @_;
  my $hash = $defs{$dev};

  if($attrName eq "devicetopic") {
    $hash->{DEVICETOPIC} = ($type eq "del" ? $hash->{NAME} : $param);
    return undef;
  }

  if($attrName =~ m/(.*)List/) {
    my $atype = $1;

    if($type eq "del") {
      MQTT2_DEVICE_delReading($dev) if($atype eq "reading");
      return undef;
    }

    return "$dev attr $attrName: more parameters needed" if(!$param); #90145

    foreach my $el (split("\n", $param)) {
      my ($par1, $par2) = split(" ", $el, 2);
      next if(!$par1);

      (undef, $par2) = split(" ", $par2, 2) if($type eq "get");
      return "$dev attr $attrName: more parameters needed" if(!$par2);

      if($atype eq "reading") {
        if($par2 =~ m/^{.*}$/) {
          my $ret = perlSyntaxCheck($par2, 
                ("%TOPIC"=>1, "%EVENT"=>"0 1 2 3 4 5 6 7 8 9",
                 "%NAME"=>$dev, "%DEVICETOPIC"=>$hash->{DEVICETOPIC}));
          return $ret if($ret);
        } else {
          return "unsupported character in readingname $par2"
              if(!goodReadingName($par2));
        }

      } else {
        my $ret = perlSyntaxCheck($par2, ("%EVENT"=>"0 1 2 3 4 5 6 7 8 9"));
        return $ret if($ret);

      }
    }
    MQTT2_DEVICE_addReading($dev, $param) if($atype eq "reading");
  }
  return undef;
}

sub
MQTT2_DEVICE_delReading($)
{
  my ($name) = @_;
  my $dp = $modules{MQTT2_DEVICE}{defptr}{re};
  foreach my $re (keys %{$dp}) {
    if($dp->{$re}{$name}) {
      delete($dp->{$re}{$name});
      delete($dp->{$re}) if(!int(keys %{$dp->{$re}}));
    }
  }
}

sub
MQTT2_DEVICE_addReading($$)
{
  my ($name, $param) = @_;
  foreach my $line (split("\n", $param)) {
    my ($re,$code) = split(" ", $line,2);
    $modules{MQTT2_DEVICE}{defptr}{re}{$re}{$name} = $code;
  }
}


#####################################
sub
MQTT2_DEVICE_Rename($$)
{
  my ($new, $old) = @_;
  MQTT2_DEVICE_delReading($old);
  MQTT2_DEVICE_addReading($new, AttrVal($new, "readingList", ""));
  return undef;
}

#####################################
sub
MQTT2_DEVICE_Undef($$)
{
  my ($hash, $arg) = @_;
  MQTT2_DEVICE_delReading($arg);
  delete $modules{MQTT2_DEVICE}{defptr}{cid}{$hash->{CID}} if($hash->{CID});
  return undef;
}

1;

=pod
=item summary    devices communicating via the MQTT2_SERVER
=item summary_DE &uuml;ber den MQTT2_SERVER kommunizierende Ger&auml;te
=begin html

<a name="MQTT2_DEVICE"></a>
<h3>MQTT2_DEVICE</h3>
<ul>
  MQTT2_DEVICE is used to represent single devices connected to the
  MQTT2_SERVER. MQTT2_SERVER and MQTT2_DEVICE is intended to simplify
  connecting MQTT devices to FHEM.
  <br> <br>

  <a name="MQTT2_DEVICEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MQTT2_DEVICE</code>
    <br><br>
    To enable a meaningful function you will need to set at least one of the
    readingList, setList or getList attributes below.<br>
  </ul>
  <br>

  <a name="MQTT2_DEVICEset"></a>
  <b>Set</b>
  <ul>
    see the setList attribute documentation below.
  </ul>
  <br>

  <a name="MQTT2_DEVICEget"></a>
  <b>Get</b>
  <ul>
    see the getList attribute documentation below.
  </ul>
  <br>

  <a name="MQTT2_DEVICEattr"></a>
  <b>Attributes</b>
  <ul>

    <a name="devicetopic"></a>
    <li>devicetopic value<br>
      replace $DEVICETOPIC in the topic part of readingList, setList and
      getList with value. if not set, $DEVICETOPIC will be replaced with the
      name of the device.
      </li><br>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a></li><br>

    <a name="readingList"></a>
    <li>readingList &lt;regexp&gt; [readingName|perl-Expression] ...
      <br>
      If the regexp matches topic:message or cid:topic:message either set
      readingName to the published message, or evaluate the perl expression,
      which has to return a hash consisting of readingName=>readingValue
      entries.
      You can define multiple such tuples, separated by newline, the newline
      does not have to be entered in the FHEMWEB frontend. cid is the client-id
      of the sending device.<br>
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev readingList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;myDev/temp:.* temperature\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;myDev/hum:.* { { humidity=>$EVTPART0 } }<br>
      </code><br>
      Notes:
      <ul>
        <li>in the perl expression the variables $TOPIC, $NAME, $DEVICETOPIC 
          and $EVENT are available (the letter containing the whole message),
          as well as $EVTPART0, $EVTPART1, ... each containing a single word of
          the message.</li>
        <li>the helper function json2nameValue($EVENT) can be used to parse a
          json encoded value. Importing all values from a Sonoff device with a
          Tasmota firmware can be done with:
          <ul><code>
            attr sonoff_th10 readingList tele/sonoff/S.* {
                json2nameValue($EVENT) }
          </code></ul></li>
      </ul>
      </li><br>

    <a name="setList"></a>
    <li>setList cmd [topic|perl-Expression] ...<br>
      When the FHEM command cmd is issued, publish the topic.
      Multiple tuples can be specified, each of them separated by newline, the
      newline does not have to be entered in the FHEMWEB frontend.
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev setList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;on tasmota/sonoff/cmnd/Power1 on\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;off tasmota/sonoff/cmnd/Power1 off
      </code><br>
      This example defines 2 set commands (on and off), which both publish
      the same topic, but with different messages (arguments).<br>
      Notes:
      <ul>
        <li>Arguments to the set command will be appended to the message
          published (not for the perl expression)</li>
        <li>If using a perl expressions, the command arguments are available as
          $EVENT, $EVTPART0, etc. The perl expression must return a string
          containing the topic and the message separated by a space.</li>
        <li>SetExtensions is activated</li>
      </ul>
      </li><br>

    <a name="getList"></a>
    <li>getList cmd reading [topic|perl-Expression] ...<br>
      When the FHEM command cmd is issued, publish the topic, wait for the
      answer (the specified reading), and show it in the user interface.
      Multiple triples can be specified, each of them separated by newline, the
      newline does not have to be entered in the FHEMWEB frontend.<br>
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev getList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;temp temperature myDev/cmd/getstatus\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;hum  hum  myDev/cmd/getStatus
      </code><br>
      This example defines 2 get commands (temp and hum), which both publish
      the same topic, but wait for different readings to be set.<br>
      Notes:
      <ul>
        <li>the readings must be parsed by a readingList</li>
        <li>get is asynchron, it is intended for frontends like FHEMWEB or
          telnet, the result cannot be used in self-written perl expressions.
          Use a set and a notify/DOIF/etc definition for such a purpose</li>
        <li>arguments to the get command will be appended to the message
          published (not for the perl expression)</li>
        <li>if using a perl expressions, the command arguments are available as
          $EVENT, $EVTPART0, etc. The perl expression must return a string
          containing the topic and the message separated by a space.</li>
      </ul>
      </li><br>

  </ul>
</ul>

=end html
=cut
