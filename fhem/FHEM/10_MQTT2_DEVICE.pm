##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

my $bridgeTimerStarted;
my $subscrCheckTimerStarted;
sub zigbee2mqtt_devStateIcon255($;$$);
use vars qw($FW_ME);
use vars qw($FW_userAgent);

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
  $hash->{FW_detailFn} = "MQTT2_DEVICE_fhemwebFn";
  $hash->{FW_deviceOverview} = 1;

  no warnings 'qw';
  my @attrList = qw(
    IODev
    autocreate:0,1
    bridgeRegexp:textField-long
    devicetopic:textField-long
    devPos
    disable:0,1
    disabledForIntervals
    getList:textField-long
    imageLink
    jsonMap:textField-long
    model
    periodicCmd:textField-long
    readingList:textField-long
    setExtensionsEvent:1,0
    setList:textField-long
    setStateList
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  my %h = ( re=>{}, cid=>{}, bridge=>{} );
  $modules{MQTT2_DEVICE}{defptr} = \%h;

  # Create cache directory
  my $fn = $attr{global}{modpath}."/www/deviceimages";
  if(! -d $fn) { mkdir($fn) || Log 3, "Can't create $fn"; }
  $fn .= "/mqtt2";
  if(! -d $fn) { mkdir($fn) || Log 3, "Can't create $fn"; }
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
  my $ioname = (@a ? shift(@a) : undef);
  $hash->{DEF} = ($hash->{CID} ? $hash->{CID} : "") if($hash->{DEF}); #rm ioname

  return "wrong syntax for $name: define <name> MQTT2_DEVICE [clientid]"
        if(int(@a));
  $hash->{".DT"} = ();
  $hash->{".DT"}{DEVICETOPIC} = $name if(!AttrVal($name, "devicetopic", 0));
  if($hash->{CID}) {
    my $dpc = $modules{MQTT2_DEVICE}{defptr}{cid};
    if(!$dpc->{$hash->{CID}}) {
      $dpc->{$hash->{CID}} = [];
    }
    push(@{$dpc->{$hash->{CID}}},$hash);
  }

  InternalTimer(1, "MQTT2_DEVICE_setBridgeRegexp", undef, 0)
    if(!$init_done && !$bridgeTimerStarted);
  $bridgeTimerStarted = 1;

  AssignIoPort($hash, $ioname);

  if($init_done) {
    MQTT2_DEVICE_checkSubscr();
  } elsif(!$subscrCheckTimerStarted) {
    $subscrCheckTimerStarted = 1;
    InternalTimer(time()+60, "MQTT2_DEVICE_checkSubscr", undef, 0);
  }
  return undef;
}

# Set the subscriptions reading from the corresponding MQTT2_SERVER connection
sub
MQTT2_DEVICE_checkSubscr()
{
  $subscrCheckTimerStarted = 0;
  my %conn;
  for my $c (devspec2array("TYPE=MQTT2_SERVER")) {
    if($defs{$c} && $defs{$c}{cid} && $defs{$c}{subscriptions}) {
      $conn{$defs{$c}{cid}} = join(" ", sort keys %{$defs{$c}{subscriptions}});
    }
  }
  for my $dev (devspec2array("TYPE=MQTT2_DEVICE")) {
    next if(!$defs{$dev}{CID} || !$conn{$defs{$dev}{CID}});
    readingsSingleUpdate($defs{$dev},"subscriptions",$conn{$defs{$dev}{CID}},0);
  }
}

#############################
sub
MQTT2_DEVICE_getRegexpHash($$$)
{
  my ($step, $cid, $topic) = @_;

  return $modules{MQTT2_DEVICE}{defptr}{"re:$cid"}
    if($step == 1); # regexp for cid:topic:msg
  return $modules{MQTT2_DEVICE}{defptr}{"re"}
    if($step == 2); # regExp for topic:msg
  return $modules{MQTT2_DEVICE}{defptr}{"re:$cid:$topic"}
    if($step == 3); # regExp for msg, for specific cid:topic
  return $modules{MQTT2_DEVICE}{defptr}{"re:*:$topic"}
    if($step == 4); # regExp for msg, for specific topic
}

sub
MQTT2_DEVICE_Parse($$)
{
  my ($iodev, $msg) = @_;
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

  my $autocreate = "no";
  if($msg =~ m/^autocreate=([^\0]+)\0(.*)$/s) {
    $autocreate = $1;
    $msg = $2;
  }

  my ($cid, $topic, $value) = split("\0", $msg, 3);
  $cid = $iodev->{NAME} if($cid eq "");        # empty cid, #122525
  return "" if(!defined($topic));
  for my $step (1,2,3,4) {

    my $dp = MQTT2_DEVICE_getRegexpHash($step, $cid, $topic);
    next if(!$dp);

    foreach my $re (keys %{$dp}) {
      my $reAll = $re;
      $reAll =~ s/\$[a-z0-9_]+/\.\*/gi;

      next if(!("$topic:$value" =~ m/^$reAll$/s ||
                "$cid:$topic:$value" =~ m/^$reAll$/s));
      foreach my $key (keys %{$dp->{$re}}) { # multiple entries for one topic-re
        my ($dev, $code) = split(",",$key,2);
        my $hash = $defs{$dev};
        next if(!$hash);
        my $reRepl = $re;
        map { $reRepl =~ s/\$$_/$hash->{".DT"}{$_}/g } keys %{$hash->{".DT"}};

        my @matched = ("$topic:$value" =~ m/^$reRepl$/sg); # 143401
        @matched = ("$cid:$topic:$value" =~ m/^$reRepl$/sg) if(!@matched);
        next if(!@matched);

        next if(IsDisabled($dev));

        Log3 $dev, 4, "MQTT2_DEVICE_Parse: $dev $topic => $code";

        if($code =~ m/^{.*}$/s) {
          my %v = ("%TOPIC"=>$topic, "%EVENT"=>$value, "%NAME"=>$hash->{NAME},
                   "%CID"=>$cid, "%JSONMAP","\$defs{\"$dev\"}{JSONMAP}",
                   "%MATCHED"=>\@matched);
          map { $v{"%$_"} = $hash->{".DT"}{$_} } keys %{$hash->{".DT"}};
          $code = EvalSpecials($code, %v);
          my $ret = AnalyzePerlCommand(undef, $code);
          if($ret && ref $ret eq "HASH") {
            readingsBeginUpdate($hash);
            foreach my $k (keys %{$ret}) {
              readingsBulkUpdate($hash, makeReadingName($k), $ret->{$k});
              my $msg = ($ret->{$k} ? $ret->{$k} : "");
              checkForGet($hash, $k, $ret->{$k});
            }
            readingsEndUpdate($hash, 1);
          }

        } else {
          readingsSingleUpdate($hash, $code, $value, 1);
          checkForGet($hash, $code, $value);
        }

        $fnd{$dev} = 1;
      }
    }
  }

  #################################################
  # IODevs autocreate and/or expand readingList
  if($autocreate ne "no" && !%fnd) {
    return "" if($cid && $cid =~ m/^(mosqpub|mosq_)/); # mosquitto_pub default

    ################## bridge stuff
    my $newCid = $cid;
    my $bp = $modules{MQTT2_DEVICE}{defptr}{bridge};
    my $parentBridge;
    my %matching; # For debugging
    foreach my $re (keys %{$bp}) {
      next if(!("$topic:$value" =~ m/^$re$/s ||
                "$cid:$topic:$value" =~ m/^$re$/s));
      my $cidExpr = $bp->{$re}{name};
      $newCid = eval $cidExpr;
      if($@) {
        Log 1, "MQTT2_DEVICE: Error evaluating bridgeRegexp >$cidExpr<: $@";
        return "";
      }
      $parentBridge = $bp->{$re}{parent};
      $matching{$re} = 1;
    }
    return if(!$newCid);
    if(int(keys %matching) > 1) {
      Log 1, "MULTIPLE MATCH in bridgeRegexp for $cid:$topic:$value: ".
                join(",",keys %matching);
    }

    PrioQueue_add(sub{
      my $cidArr = $modules{MQTT2_DEVICE}{defptr}{cid}{$newCid};
      return if(!$cidArr);
      my $add;
      if(length($value) < 10000 && $value =~ m/^\s*[{[].*[}\]]\s*$/s) {
        my $ret = json2nameValue($value);
        if(keys %{$ret}) {
          $topic =~ m,.*/([^/]+),;
          my $ltopic = makeReadingName($1)."_";
          $add = $autocreate eq "simple" ?
                  "{ json2nameValue(\$EVENT) }" :
                  "{ json2nameValue(\$EVENT, '$ltopic', \$JSONMAP) }";
        }
      }
      if(!$add) {
        my @tEl = split("/",$topic);
        if(@tEl == 1) {
          $add = $tEl[0];

        } elsif($tEl[-1] =~ m/^\d+$/) { # relay_0
          $add = $tEl[-2]."_".$tEl[-1];

        } elsif($tEl[-2] =~ m/^\d+$/) { # relay_0_power
          $add = $tEl[-2]."_".$tEl[-1];
          $add = $tEl[-3]."_".$add if(@tEl > 2);

        } else {
          $add = $tEl[-1];

        }
        $add = makeReadingName($add); # Convert non-valid characters to _
      }

      my $reTopic = $topic;
      $reTopic =~ s#([^A-Z0-9_/-])#"\\x".sprintf("%02x",ord($1))#ige;

      for my $ch (@{$cidArr}) {
        my $nn = $ch->{NAME};
        next if(!AttrVal($nn, "autocreate", 1)); # device autocreate
        my $rl = AttrVal($nn, "readingList", "");
        $rl .= "\n" if($rl);
        my $regex = ($cid eq $newCid ? "$cid:" : "").$reTopic.":.*";
        CommandAttr(undef, "$nn readingList $rl$regex $add")
                if(index($rl, $regex) == -1);   # Forum #84372
        setReadingsVal($defs{$nn}, "associatedWith", $parentBridge, TimeNow())
                if($parentBridge && $defs{$nn});
      }
      MQTT2_DEVICE_Parse($iodev, $msg);
    }, undef);

    my $cidArr = $modules{MQTT2_DEVICE}{defptr}{cid}{$newCid};
    if(!$cidArr || !int(@{$cidArr})) {
      my $devName = $newCid;
      $devName = makeDeviceName($devName);
      return "UNDEFINED $devName MQTT2_DEVICE $newCid ".$iodev->{NAME}
        if(!$defs{$devName}); # 125159
    }
    return "";
  }

  my @ret = keys %fnd;
  unshift(@ret, "[NEXT]"); # for MQTT_GENERIC_BRIDGE
  return @ret;
}

# compatibility: the first version was implemented as MQTT2_JSON and published.
sub
MQTT2_JSON($;$)
{
  return json2nameValue($_[0], $_[1]);
}

sub
MQTT2_getCmdHash($$)
{
  my ($hash, $list) = @_;
  my (%h, @cmd);

  $list = AnalyzePerlCommand($hash ? $hash->{CL} : undef, $1)
        if($list =~ m/^{(.*)}/s);    #133903

  map { 
    my ($k,$v) = split(" ",$_,2);
    push @cmd, $k;
    $k =~ s/:.*//; # potential arguments
    $h{$k} = $v;
  }
  grep /[^ ]+/,
  split("\n", $list);
  return (\%h, join(" ",@cmd));
}

#############################
# replace {} and $EVENT. Used both in set and get
sub
MQTT2_buildCmd($$$)
{
  my ($hash, $a, $cmd) = @_;

  shift @{$a};
  if($cmd =~ m/^{.*}\s*$/) {
    my %v = ("%EVENT"       => join(" ",@{$a}),
             "%NAME"        => $hash->{NAME});
    map { $v{"%$_"} = $hash->{".DT"}{$_} } keys %{$hash->{".DT"}};
    $cmd = EvalSpecials($cmd,%v);
    $cmd = AnalyzeCommandChain($hash->{CL}, $cmd);
    return if(!$cmd);

  } else {
    if($cmd =~ m/\$EV/) {       # replace EVENT & $EVTPART
      my $event = join(" ",@{$a});
      $cmd =~ s/\$EVENT/$event/g;
      for(my $i=0; $i<@{$a}; $i++) {
        my $n = "\\\$EVTPART$i";
        $cmd =~ s/$n/$a->[$i]/ge;
      }
    } else {
      shift @{$a};
      $cmd .= " ".join(" ",@{$a}) if(@{$a});
    }
    $cmd =~ s/\$NAME/$hash->{NAME}/g;
    map { $cmd =~ s/\$$_/$hash->{".DT"}{$_}/g } keys %{$hash->{".DT"}};
  }

  return $cmd;
}

#############################
sub
MQTT2_DEVICE_Get($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for get" if(!defined($a[1]));
  my $name = $hash->{NAME};

  my ($gets,$cmdList) = MQTT2_getCmdHash($hash, AttrVal($name, "getList", ""));
  return "Unknown argument $a[1], choose one of $cmdList" if(!$gets->{$a[1]});
  return undef if(IsDisabled($name));
  Log3 $hash, 3, "MQTT2_DEVICE get ".join(" ", @a);

  my ($getReading, $cmd) = split(" ",$gets->{$a[1]},2);
  if($hash->{CL}) {
    my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$getReading };
    $hash->{asyncGet} = $tHash;
    InternalTimer(gettimeofday()+4, sub {
      asyncOutput($tHash->{CL}, "Timeout reading answer for $cmd");
      delete($hash->{asyncGet});
    }, $tHash, 0);
  }

  $cmd = MQTT2_buildCmd($hash, \@a, $cmd);
  return if(!$cmd);
  IOWrite($hash, "publish", $cmd);

  return undef;
}

#############################
sub
MQTT2_DEVICE_Set($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for set" if(!defined($a[1]));
  my $name = $hash->{NAME};

  my ($sets,$cmdList) = MQTT2_getCmdHash($hash, AttrVal($name, "setList", ""));
  my $cmdName = $a[1];
  return MQTT2_DEVICE_addPos($hash,@a) if($cmdName eq "addPos"); # hidden cmd
  my $cmd = $sets->{$cmdName};
  return SetExtensions($hash, $cmdList, @a) if(!$cmd);
  return undef if(IsDisabled($name));

  Log3 $hash, 3, "MQTT2_DEVICE set ".join(" ", @a);
  my $a1 = (@a > 1 ? $a[1] : '');
  $cmd = MQTT2_buildCmd($hash, \@a, $cmd);
  return if(!$cmd);
  SetExtensionsCancel($hash) if($a1 eq "on" || $a1 eq "off");
  IOWrite($hash, "publish", $cmd);
  my $ssl = AttrVal($name, "setStateList", "");

  my $cmdSE = $cmdName;
  $cmdSE = $hash->{SetExtensionsCommand}
              if($hash->{SetExtensionsCommand} &&
                 AttrVal($name, "setExtensionsEvent", undef));
  if(!$ssl) {
    readingsSingleUpdate($hash, "state", $cmdSE, 1);

  } elsif($ssl ne "ignore") {
    if($ssl =~ m/\b$cmdName\b/) {
      $hash->{skipStateFormat} = 1;
      readingsSingleUpdate($hash, "state", "set_$cmdSE", 1);
      delete($hash->{skipStateFormat});
    } else {
      unshift(@a, "set");
      readingsSingleUpdate($hash, $cmdName, join(" ",@a), 1);
    }
  }
  return undef;
}


sub
MQTT2_DEVICE_Attr($$)
{
  my ($type, $dev, $attrName, $param) = @_;
  my $hash = $defs{$dev};
  $attrName = "" if(!$attrName);

  if($attrName eq "devicetopic") {
    $hash->{".DT"} = ();
    if($type eq "del") {
      $hash->{".DT"}{DEVICETOPIC} = $hash->{NAME};
    } elsif($param !~ m/=/) {
      $hash->{".DT"}{DEVICETOPIC} = $param
    } else {
      my ($a, $h) = parseParams($param); #126679
      foreach my $key (keys %{$h}) {
        return "$key is not valid, must only contain a-zA-Z0-9_"
                if($key !~ m/^[a-zA-Z0-9_]+$/);
      }
      $hash->{".DT"} = $h;
    }
    MQTT2_DEVICE_addReading($dev, AttrVal($dev, "readingList", ""));
    return undef;
  }

  if($attrName =~ m/^(get|set|reading)List/) {
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
        if($par2 =~ m/^{.*}\s*$/) {
          my %v = ("%TOPIC"=>1, "%EVENT"=>"0 1 2 3 4 5 6 7 8 9",
                 "%MATCHED" => [0,1,2,3,4,5,6,7,8,9],
                 "%NAME"=>$dev, "%CID"=>"clientId", "%JSONMAP"=>"");
          map { $v{"%$_"} = $hash->{".DT"}{$_} } keys %{$hash->{".DT"}};
          my $ret = perlSyntaxCheck($par2, %v);
          return $ret if($ret);
        } else {
          return "$dev: bad reading name $par2 ".
                        "(contains not A-Za-z/\\d_\\.- or is too long)"
              if(!goodReadingName($par2));
        }

      } else {
        my %v = ("%NAME"=>$dev, "%EVENT"=>"0 1 2 3 4 5 6 7 8 9");
        map { $v{"%$_"} = $hash->{".DT"}{$_} } keys %{$hash->{".DT"}};
        my $ret = perlSyntaxCheck($par2, %v);
        return $ret if($ret);

      }
    }
    if($atype eq "reading") {
      my $ret = MQTT2_DEVICE_addReading($dev, $param);
      return $ret if($ret);
    }
  }

  if($attrName eq "bridgeRegexp") {
    # Check the syntax
    foreach my $el (split("\n", ($param ? $param : ""))) { #del: param is undef
      my ($par1, $par2) = split(" ", $el, 2);
      next if(!$par1);
      return "$dev attr $attrName: more parameters needed" if(!$par2);
      my $errMsg = CheckRegexp($par1, "bridgeRegexp attribute for $dev");
      return $errMsg if($errMsg);
    }
    if($init_done) {
      my $name = $hash->{NAME};
      AnalyzeCommandChain(undef,
                      "deleteattr $name readingList; deletereading $name .*");
      InternalTimer(1, "MQTT2_DEVICE_setBridgeRegexp", undef, 0);
    }
  }

  if($attrName eq "jsonMap") {
    if($type eq "set") {
      my @ret = split(/[: \r\n]/, $param);
      return "jsonMap: Odd number of elements" if(int(@ret) % 2);
      my %ret = @ret;
      $hash->{JSONMAP} = \%ret;
    } else {
      delete $hash->{JSONMAP};
    }
  }

  if($attrName eq "periodicCmd") {
    if($type eq "set") {
      if($init_done) {
        my ($gets,undef) = MQTT2_getCmdHash($hash, AttrVal($dev,"getList",""));
        my ($sets,undef) = MQTT2_getCmdHash($hash, AttrVal($dev,"setList",""));
        for my $np (split(" ", $param)) {
          return "$np ist not of the form cmd:period" if($np !~ m/(.*):(.*)/);
          return "$1 is neither a get nor a set command"
                if(!$gets->{$1} && !$sets->{$1});
          return "$2 (from $np) is not an integer" if($2 !~ m/^\d+$/);
        }
      }
      RemoveInternalTimer($hash);
      $hash->{periodicCounter} = 0 if(!$hash->{periodicCounter});
      InternalTimer(time()+60, "MQTT2_DEVICE_periodic", $hash, 0);
    } else {
      RemoveInternalTimer($hash);
    }
  }

  return undef;
}

sub
MQTT2_DEVICE_periodic()
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $param = AttrVal($name, "periodicCmd", "");
  return if(!$param);
  my ($gets,undef) = MQTT2_getCmdHash($hash, AttrVal($name, "getList", ""));
  my $cnt = ++$hash->{periodicCounter};
  for my $np (split(" ", $param)) {
    next if($np !~ m/(.*):(.*)/ || $cnt % int($2));
    my $cmd = $1;
    my $ret;
    if($gets->{$cmd}) {
      $ret = MQTT2_DEVICE_Get($hash, $name, $cmd);
    } else {
      $ret = MQTT2_DEVICE_Set($hash, $name, $cmd);
    }
    Log3 $hash, 3, "$name periodicCmd $cmd: $ret" if($ret);
  }
  InternalTimer(time()+60, "MQTT2_DEVICE_periodic", $hash, 0);
}

sub
MQTT2_DEVICE_setBridgeRegexp()
{
  delete($modules{MQTT2_DEVICE}{defptr}{bridge});
  for my $dev (devspec2array("TYPE=MQTT2_DEVICE")) {
    my $bre = AttrVal($dev, "bridgeRegexp", "");
    next if(!$bre);
    foreach my $el (split("\n", $bre)) {
      my ($par1, $par2) = split(" ", $el, 2);
      next if(!$par1 || !$par2);
      $modules{MQTT2_DEVICE}{defptr}{bridge}{$par1}= {name=>$par2,parent=>$dev};
    }
  }
}

sub
MQTT2_DEVICE_delReading($)
{
  my ($name) = @_;
  my $cid = $defs{$name} ? $defs{$name}{CID} : undef;
  $cid = "" if(!defined($cid));
  for my $key1 (sort keys %{$modules{MQTT2_DEVICE}{defptr}}) {
    next if($key1 !~ m/^re/);
    my $dp = $modules{MQTT2_DEVICE}{defptr}{$key1};
    foreach my $re (keys %{$dp}) {
      foreach my $key2 (keys %{$dp->{$re}}) {
        delete($dp->{$re}{$key2}) if($key2 =~ m/^$name,/);
      }
      delete($dp->{$re}) if(!int(keys %{$dp->{$re}}));
    }
    if(!int(keys %{$modules{MQTT2_DEVICE}{defptr}{$key1}}) && $key1 ne "re") {
      delete($modules{MQTT2_DEVICE}{defptr}{$key1});
    }
  }
}

sub
MQTT2_DEVICE_addReading($$)
{
  my ($name, $param) = @_;
  MQTT2_DEVICE_delReading($name);
  my $hash = $defs{$name};
  my $cid = $defs{$name}{CID};
  foreach my $line (split("\n", $param)) {
    next if($line eq "");
    my ($re,$code) = split(" ", $line,2);
    return "ERROR: empty code in line >$line< for $name" if(!defined($code));

    map { $re =~ s/\$$_/$hash->{".DT"}{$_}/g } keys %{$hash->{".DT"}};
    my $errMsg = CheckRegexp($re, "readingList attribute for $name");
    return $errMsg if($errMsg);

    if($cid && $re =~ m/^$cid:/) {
      if($re =~ m/^$cid:([^\\\?.*\[\](|)]+):\.\*$/) { # cid:topic:.*
        $modules{MQTT2_DEVICE}{defptr}{"re:$cid:$1"}{$re}{"$name,$code"} = 1;
      } else {
        $modules{MQTT2_DEVICE}{defptr}{"re:$cid"}{$re}{"$name,$code"} = 1;
      }
    } else {
      if($re =~ m/^([^:\\\?.*\[\](|)]+):\.\*$/) { # nothing smelling like regexp
        $modules{MQTT2_DEVICE}{defptr}{"re:*:$1"}{$re}{"$name,$code"} = 1;
      } else {
        $modules{MQTT2_DEVICE}{defptr}{re}{$re}{"$name,$code"} = 1;
      }
    }
  }
  return undef;
}

sub
MQTT2_DEVICE_dumpInternal()
{
  my $dp = $modules{MQTT2_DEVICE}{defptr};
  my @ret;
  for my $k1 (sort keys %{$dp}) {
    push(@ret, $k1);
    for my $k2 (sort keys %{$dp->{$k1}}) {
      push(@ret, "  $k2");
    }
  }
  return join("\n", @ret);
}


#####################################
sub
MQTT2_DEVICE_Rename($$)
{
  my ($new, $old) = @_;
  MQTT2_DEVICE_delReading($old);
  MQTT2_DEVICE_addReading($new, AttrVal($new, "readingList", ""));
  $defs{$new}{".DT"}{DEVICETOPIC} = $new if(!AttrVal($new,"devicetopic",undef));
  MQTT2_DEVICE_setBridgeRegexp();
  return undef;
}

#####################################
sub
MQTT2_DEVICE_Undef($$)
{
  my ($hash, $arg) = @_;
  MQTT2_DEVICE_delReading($arg);
  if($hash->{CID}) {
    my $dpc = $modules{MQTT2_DEVICE}{defptr}{cid}{$hash->{CID}};
    my @nh = grep { $_->{NAME} ne $hash->{NAME} } @{$dpc};
    $modules{MQTT2_DEVICE}{defptr}{cid}{$hash->{CID}} = \@nh;
  }
  MQTT2_DEVICE_setBridgeRegexp();
  RemoveInternalTimer($hash->{asyncGet}) if($hash->{asyncGet});
  RemoveInternalTimer($hash) if($hash->{periodicCounter});
  return undef;
}

#####################################
# Reuse the ZWDongle map for graphvis visualisation. Forum #91394
sub
MQTT2_DEVICE_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  if(ReadingsVal($d, ".graphviz", ReadingsVal($d, "graphviz", ""))) {
    my $js = "$FW_ME/pgm2/zwave_neighborlist.js";
    return
    "<div id='ZWDongleNr'><a id='zw_snm' href='#'>Show neighbor map</a></div>".
    "<div id='ZWDongleNrSVG'></div>".
    "<script type='text/javascript' src='$js'></script>".
    '<script type="text/javascript">'.<<"JSEND"
      \$(document).ready(function() {
        \$("div#ZWDongleNr a#zw_snm")
          .click(function(e){
            e.preventDefault();
            zw_nl('MQTT2_DEVICE_nlData("$d")');
          });
      });
    </script>
JSEND
  }

  my $img = AttrVal($d, "imageLink", "");
  if($img) {
    return
      "<div id='m2dimage' class='img' style='float:right'>".
        "<img style='max-width:96;max-height:96px;' src='$img'>".
      "</div>".
      '<script type="text/javascript">'.<<'JSEND'
        $(document).ready(function() {
          $("div#m2dimage").insertBefore("div.makeTable.internals"); // Move
        });
      </script>
JSEND
  }
}

#########################
# Used for the graphical representation in Bridge devices. See Fn above.
sub
MQTT2_DEVICE_nlData($)
{
  my ($d) = @_;

  my (%img,%h,%n2n);
  my $fo="";

  # Needed for the image links
  my $dv = ReadingsVal($d, ".devices", ReadingsVal($d, "devices", ""));
  if($dv =~ m/ieeeAddr":/) { # {
    $dv =~ s@ieeeAddr":"([^"]+)"[^}]+model":"([^"]+)"@
            my $ieeeAddr = $1;
            my $img = $2;
            $img =~ s+[/: ]+-+g; # Forum #91394: supported-devices.js
            $img{$ieeeAddr} = "$img.jpg";
          @xeg;

  } elsif($dv =~ m/^\[\{/) { #139205
    my $h = json2nameValue($dv);
    my $dm;
    foreach my $key (sort keys %{$h}) {
      $dm = $h->{$key}
        if($key =~ m/^\d+_definition_model$/);
      if($key =~ m/^\d+_ieee_address$/ && $dm) {
        $img{$h->{$key}} = $dm;
        $dm = "";
      }
    }
  }

  # Name translation
  for my $n (devspec2array("TYPE=MQTT2_DEVICE")) {
    my $cid = $defs{$n}{CID};
    if($cid) {
      $cid =~ s/zigbee\d*_//;
      $n2n{$cid} = $n;
    }
    if(AttrVal($n, "readingList","") =~ m,zigbee\d*mqtt/(.*):,) {
      $n2n{$1} = $n;
    }
  }

  sub
  getImg($$$)
  {
    my ($imgName, $suffix, $fileName) = @_;

    #my $pref = "https://koenkk.github.io/zigbee2mqtt/images/devices";
    my $pref = "https://www.zigbee2mqtt.io/images/devices/";
    my $url = $pref . urlEncode($imgName) . $suffix;

    Log 3, "MQTT2_DEVICE: trying $url";
    my $data = GetFileFromURL($url);
    if($data && $data !~ m/<html/ && open(FH, ">$fileName")) {
      Log 3, "Got data, writing $fileName, length: ".length($data);
      binmode(FH);
      print FH $data;
      close(FH);
      return 1;
    } else {
      Log 3, "No result";
      return 0;
    }
  }

  my $fPref = "$attr{global}{modpath}/www/deviceimages/mqtt2";
  my $div = ($FW_userAgent =~ m/WebKit/ ? "&#xA;" : " ");
  my $gv = ReadingsVal($d, ".graphviz", ReadingsVal($d, "graphviz", ""));
  $gv =~ s/\\n/\n/g; #126970
  $gv =~ s/\\"/"/g;
  for my $l (split(/[\r\n]/, $gv)) {

    if($l =~ m/^\s*"([^"]+)"\s*\[.*label="([^"]+)"\]/) {
      my ($n,$v) = ($1,$2);
      my $nv = $n;
      $nv =~ s/^0x0*//;
      $h{$n}{img} = '';

      if($v =~ m/{(.*)\|(.*)\|(.*)\|(.*)}/) {
        my ($x1,$x2,$x3,$x4) = ($1,$2,$3,$4);
        $nv = $n2n{$x1} if($n2n{$x1});

        if($img{$n}) {
          $img{$n} =~ s,[ /],-,g;
          my $fJpg = "$fPref/$img{$n}.jpg";
          my $fPng = "$fPref/$img{$n}.png";
          my $fn;

          if(-e $fJpg) {
            $fn = (-z $fJpg ? "" : "$img{$n}.jpg");

          } elsif (-e $fPng) {
            $fn = "$img{$n}.png";

          } elsif (getImg($img{$n}, ".jpg", $fJpg)) {
            $fn = "$img{$n}.jpg";

          } elsif (getImg($img{$n}, ".png", $fPng)) {
            $fn = "$img{$n}.png";

          } else {
            if(open(FH, ">$fJpg")) { # empty file: dont try it again
              close(FH);
            }
          }
          $h{$n}{img} = "$FW_ME/deviceimages/mqtt2/$fn" if($fn);
        }

        if($img{$n} && $n2n{$x1} && !AttrVal($n2n{$x1}, "imageLink", "")) {
          CommandAttr(undef, "$nv imageLink $h{$n}{img}");
        }
        $h{$n}{class} = ($x2 =~ m/Coordinator|Router/ ? "zwDongle":"zwBox");
        if($x2 =~ m/Coordinator/) {
          $nv = $d;
          $fo = $n;
        }
      } else {
        $h{$n}{class}="zwBox";
      }

      $v =~ s/[{}]//g;
      $v =~ s/\|/$div/g;
      $h{$n}{txt} = $nv;

      $h{$n}{title} = $v;
      $fo = $n if(!$fo);
      my @a; $h{$n}{neighbors} = \@a;
      my @b; $h{$n}{neighborstyles} = \@b;

    } elsif($l =~ m/^\s*"([^"]+)"\s*->\s*"([^"]+)".*label="([^"]*)"/) {
      my ($from,$to,$title) = ($1,$2,$3);
      push @{$h{$from}{neighbors}}, $to;
      $h{$from}{title} .= "${div}lqi:$title";
      push @{$h{$from}{neighborstyles}}, ($l =~ m/style="([^"]+)"/ ? $1 : "");
    }
  }

  my @ret;
  my @dp = split(" ", AttrVal($d, "devPos", ""));
  my %dp = @dp;

  for my $k (keys %h) {
    my $n = $h{$k}{neighbors};
    my $ns = $h{$k}{neighborstyles};
    push @ret, '"'.$k.'":{'.
        '"class":"'.$h{$k}{class}.' col_link col_oddrow",'.
        '"img":"'.$h{$k}{img}.'",'.
        '"txt":"'.$h{$k}{txt}.'",'.
        '"title":"'.$h{$k}{title}.'",'.
        '"pos":['.($dp{$k} ? $dp{$k} : '').'],'.
        '"neighbors":['. (@{$n} ? ('"'.join('","',@{$n}).'"'):'').'],'.
        '"neighborstyles":['. (@{$ns} ? ('"'.join('","',@{$ns}).'"'):'').']}';
  }

  my $r = '{"firstObj":"'.$fo.'","el":{'.join(",",@ret).'},'.
           '"saveFn":"set '.$d.' addPos {1} {2}" }';
  return $r;
}

sub
MQTT2_DEVICE_addPos($@)
{
  my ($hash, @a) = @_;
  my @d = split(" ", AttrVal($a[0], "devPos", ""));
  my %d = @d;
  $d{$a[2]} = $a[3];
  CommandAttr(undef,"$a[0] devPos ".join(" ", map {"$_ $d{$_}"} sort keys %d));
}
# graphvis end
#####################################

#####################################
# Utility functions for the AttrTemplates
sub
zigbee2mqtt_RGB2JSON($;$)
{
  my ($rgb,$trans) = (@_);
  $rgb =~ m/^(..)(..)(..)/;
  return toJSON({'transition'=>defined($trans) ? $trans : 1,
                 'color'=>{r=>hex($1),g=>hex($2),b=>hex($3)}});
}

sub
zigbee2mqtt_devStateIcon255($;$$)
{
  my ($name, $rgbReadingName, $useSetExtension) = @_;

  return ".*:off:toggle" if(!$defs{$name});

  my $too = $defs{$name}->{TIMED_OnOff};
  $useSetExtension = 0 if(!$too);
  my $state = lc(ReadingsVal($name,"state","on"));
  if(!$useSetExtension && $state =~ m/off$/) { # set_off or off
    return ".*:off:toggle";
  }

  my $pct = ReadingsNum($name, "brightness", 255);

  my $s = "on";
  if($useSetExtension && $too->{CMD} =~ m/on-|off-|blink/) {
    $s = $too->{CMD} =~ m/on-/  ? "on-for-timer"  :
         $too->{CMD} =~ m/off-/ ? "off-for-timer" :
         $state      =~ m/off-/ ? "off-for-timer" : "light_toggle";
  } elsif ($pct < 254) {
    $s = sprintf("dim%02d%%", int((1+int($pct/18))*6.25));
  }

  if($rgbReadingName) {
    my $rgb = ReadingsVal($name, $rgbReadingName, "FFFFFF");
    $s .= "@#$rgb" if($rgb ne "FFFFFF");
  }

  return ".*:$s:toggle";
}

1;

=pod
=item summary    devices communicating via the MQTT2_SERVER or MQTT2_CLIENT
=item summary_DE &uuml;ber den MQTT2_SERVER oder MQTT2_CLIENT kommunizierende Ger&auml;te
=begin html

<a id="MQTT2_DEVICE"></a>
<h3>MQTT2_DEVICE</h3>
<ul>
  MQTT2_DEVICE is used to represent single devices connected to the
  MQTT2_SERVER. MQTT2_SERVER and MQTT2_DEVICE is intended to simplify
  connecting MQTT devices to FHEM.
  <br> <br>

  <a id="MQTT2_DEVICE-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MQTT2_DEVICE [clientId]</code>
    <br><br>
    To enable a meaningful function you will need to set at least one of the
    readingList, setList or getList attributes below.<br>
    Specifying the clientId (sometimes referred to as CID) is optional, and it
    makes only sense, if the IO Device is an MQTT2_SERVER.
  </ul>
  <br>

  <a id="MQTT2_DEVICE-set"></a>
  <b>Set</b>
  <ul>
    see the setList attribute documentation below.
  </ul>
  <br>

  <a id="MQTT2_DEVICE-get"></a>
  <b>Get</b>
  <ul>
    see the getList attribute documentation below.
  </ul>
  <br>

  <a id="MQTT2_DEVICE-attr"></a>
  <b>Attributes</b>
  <ul>

    <a id="MQTT2_DEVICE-attr-autocreate"></a>
    <li>autocreate {0|1}<br>
      if set to 0, disables extending the readingList, when the IODev
      autocreate is also set. Default is 1, i.e. new topics will be
      automatically added to the readingList. 
      </li><br>

    <a id="MQTT2_DEVICE-attr-bridgeRegexp"></a>
    <li>bridgeRegexp &lt;regexp&gt; newClientId ...<br>
      Used to automatically redirect some types of topics to different
      MQTT2_DEVICE instances. The regexp is checked against the
      clientid:topic:message and topic:message. The newClientId is a perl
      expression!. Example:
      <ul>
        attr zigbee2mqtt bridgeRegexp zigbee2mqtt/([A-Za-z0-9]*)[/]?.*:.*
                "zigbee_$1"
      </ul>
      will create different MQTT2_DEVICE instances for different hex numbers in
      the topic. Note: the newClientId is enclosed in "", as it is a perl
      expression, should be unique, and the automatically created device will
      be created also with this name.<br>
      Notes:
      <ul>
      <li>multiple tuples of &lt;regexp&gt; newClientId are separated by
        newline</li>
      <li>setting bridgeRegexp will remove the readingList attribute and all
        readings.</li>
      <li>For a zigbee2mqtt device connected via MQTT2_SERVER the following 
        is probably a better solution:<br>
        <ul>
          attr zigbee2mqtt bridgeRegexp zigbee2mqtt/0x........([^/]+):.*
                  "zigbee_$1"
        </ul>
        </li>
      </ul>
      </li><br>

    <a id="MQTT2_DEVICE-attr-devicetopic"></a>
    <li>devicetopic value<br>
      <ul>
        <li>if value does <b>not</b> contain an equal sign (=),
          replace $DEVICETOPIC in the topic part of the readingList, setList and
          getList attributes with value.</li>
        <li>if the value <b>does</b> contain an equal sign (=), then it is
          interpreted as
          <ul><code>Var1=Var1Value Var2="Value with space" Var3=...</code></ul>
          and $Var1,$Var2,$Var3 are replaced in the readingList, setList and
          getList attributes with the corresponding value.<br>
          Note: the name Var1,etc must only contain the letters A-Za-z0-9_.</li>
        <li>If the attribute is not set, $DEVICETOPIC will be replaced with the
          name of the device in the attributes mentioned above.</li>
      </ul>
      </li><br>

    <a id="MQTT2_DEVICE-attr-devPos"></a>
    <li>devPos value<br>
      used internally by the "Show neighbor map" visualizer in FHEMWEB.
      This function is active if the graphviz and devices readings are set,
      usually in the zigbee2mqtt bridge device.
      </li><br>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a></li><br>

    <a id="MQTT2_DEVICE-attr-getList"></a>
    <li>getList cmd reading [topic|perl-Expression] ...<br>
      When the FHEM command cmd is issued, publish the topic (and optional
      message, which is separated by space from the topic), wait for the answer
      which must contain the specified reading, and show the result in the user
      interface.<br>
      Multiple triples can be specified, each of them separated by newline.
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev getList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;temp temperature myDev/cmd/getstatus\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;hum humReading myDev/cmd/getHumidity now
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
        <li>the command arguments are available as $EVENT, $EVTPART0, etc.
          </li>
        <li>the perl expression must return a string containing the topic and
          the message separated by a space.</li>
      </ul>
      </li><br>


    <a id="MQTT2_DEVICE-attr-imageLink"></a>
    <li>imageLink href<br>
      sets the image to be shown. The "Show neighbor map" function initializes
      the value automatically.
      </li><br>

    <a id="MQTT2_DEVICE-attr-jsonMap"></a>
    <li>jsonMap oldReading1:newReading1 oldReading2:newReading2...<br>
      space or newline separated list of oldReading:newReading pairs.<br>
      Used in the automatically generated readingList json2nameValue function
      to map the generated reading name to a better one. E.g.
      <ul><code>
      attr m2d jsonMap SENSOR_AM2301_Humidity:Humidity<br>
      attr m2d readingList tele/sonoff/SENSOR:.* { json2nameValue($EVENT, 'SENSOR_', $JSONMAP) }
      </code></ul>
      The special newReading value of 0 will prevent creating a reading for
      oldReading.
      </li><br>

    <a id="MQTT2_DEVICE-attr-periodicCmd"></a>
    <li>periodicCmd &lt;cmd1&gt;:&lt;period1&gt; &lt;cmd2&gt;:&lt;period2&gt;...
      <br>
      periodically execute the get or set command. The command will not take
      any arguments, create a new command without argument, if necessary.
      period is measured in minutes, and it must be an integer.
      </li><br>

    <a id="MQTT2_DEVICE-attr-readingList"></a>
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
          $JSONMAP and $EVENT are available (the letter containing the whole
          message), as well as $EVTPART0, $EVTPART1, ... each containing a
          single word of the message.<br>
          The @MATCHED array contains the result of the regexp: the captured
          groups if present, or the whole matched string.
          </li>

        <li>the helper function json2nameValue($EVENT) can be used to parse a
          json encoded value. Importing all values from a Sonoff device with a
          Tasmota firmware can be done with:
          <ul><code>
            attr sonoff_th10 readingList tele/sonoff/S.* {
                json2nameValue($EVENT) }
          </code></ul>
          A second (optional) parameter to json2nameValue is treated as prefix,
          and will be prepended to each reading name.<br>
          The third (optional) parameter is $JSONMAP, see the jsonMap attribute
          above.
          </li>
      </ul>
      </li><br>

    <a id="MQTT2_DEVICE-attr-setExtensionsEvent"></a>
    <li>setExtensionsEvent<br>
      If set, the event will contain the command implemented by SetExtensions
      (e.g. on-for-timer 10), else the executed command (e.g. on).</li><br>

    <a id="MQTT2_DEVICE-attr-setList"></a>
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
        <li>arguments to the set command will be appended to the message
          published (this is not valid not for the perl expression)</li>
        <li>the command arguments are available as $EVENT, $EVTPART0, etc., 
          the name of the device as $NAME, both in the perl expression and the
          "normal" topic variant.</li>
        <li>the perl expression must return a string containing the topic and
          the message separated by a space. If it returns "", undef or 0, no
          MQTT message will be sent.</li>
        <li>SetExtensions is activated</li>
        <li>if the topic name ends with :r, then the retain flag is set</li>
        <li>if the whole argument is enclosed in {}, then it is evaluated as a
          perl expression. The string returned will be interpreted as described
          above.</li>
      </ul>
      </li><br>

    <a id="MQTT2_DEVICE-attr-setStateList"></a>
    <li>setStateList command command ...<br>
      This attribute is used to get more detailed feedback when switching
      devices.  I.e. when the command on is contained in the list, state will
      be first set to set_on, and after the device reports execution, state
      will be set to on (probably with the help of stateFormat). Commands not
      in the list will set a reading named after the command, with the word set
      and the command parameters as its value.<br><br>
      If this attribute is not defined, then a set command will set the state
      reading to the name of the command.<br>
      If this attribute is set to ignore, then a set command will not affect any
      reading in the device.
      </li><br>

  </ul>
</ul>

=end html
=cut
