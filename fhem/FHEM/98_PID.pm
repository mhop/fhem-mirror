##############################################
# This module is derived from the contrib/99_PID by Alexander Titzel.

package main;
use strict;
use warnings;

sub PID_sv($$$);
sub PID_setValue($);

##########################
sub
PID_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "PID_Define";
  $hash->{SetFn}   = "PID_Set";
  $hash->{NotifyFn} = "PID_Notify";
  $hash->{AttrList} = "disable:0,1 loglevel:0,1,2,3,4,5,6";
}


##########################
sub
PID_Define($$$)
{
  my ($pid, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $n = $a[0];

  if(@a < 4 || @a > 7) {
    my $msg = "wrong syntax: define <name> PID " .
                "<sensor>[:reading:regexp] <actor>[:cmd:min:max] [p i d]";
    Log 2, $msg;
    return $msg;
  }

  ###################
  # Sensor
  my ($sensor, $reading, $regexp) = split(":", $a[2], 3);
  if(!$defs{$sensor}) {
    my $msg = "$n: Unknown sensor device $sensor specified";
    Log 2, $msg;
    return $msg;
  }
  $pid->{sensor} = $sensor;
  if(!$regexp) {
    my $t = $defs{$sensor}{TYPE};
    if($t eq "HMS" || $t eq "CUL_WS") {
      $reading = "temperature";
      $regexp = '([\\d\\.]*)';
    } else {
      my $msg = "$n: Unknown sensor type $t, specify regexp";
      Log 2, $msg;
      return $msg;
    }
  }
  $pid->{reading} = $reading;
  $pid->{regexp} = $regexp;


  ###################
  # Actor
  my ($actor, $cmd, $min, $max) = split(":", $a[3], 4);
  my ($p_p, $p_i, $p_d) = (0, 0, 0);
  if(!$defs{$actor}) {
    my $msg = "$n: Unknown actor device $actor specified";
    Log 2, $msg;
    return $msg;
  }
  $pid->{actor} = $actor;
  if(!$max) {
    my $t = $defs{$actor}{TYPE};
    if($t eq "FHT8V") {
      $cmd = "valve";
      $min = 0;
      $max = 100;
      $p_p = 65.0/2.55;
      $p_i = 7.8/2.55;
      $p_d = 15.0/2.55;
    } else {
      my $msg = "$n: Unknown actor type $t, specify command:min:max";
      Log 2, $msg;
      return $msg;
    }
  }
  $pid->{command} = $cmd;

  $pid->{pFactor}    = (@a > 4 ? $a[4] : $p_p);
  $pid->{iFactor}    = (@a > 5 ? $a[5] : $p_i);
  $pid->{dFactor}    = (@a > 6 ? $a[6] : $p_d);
  $pid->{satMin}     = $min;
  $pid->{satMax}     = $max;

  PID_sv($pid, 'delta',      0.0);
  PID_sv($pid, 'actuation',  0.0);
  PID_sv($pid, 'integrator', 0.0);
  $pid->{STATE} = 'initialized';

  return undef;
}

##########################
sub
PID_Set($@)
{
  my ($pid, @a) = @_;
  my $n = $pid->{NAME};

  return "Need a parameter for set" if(@a < 2);
  my $arg = $a[1];

  if($arg eq "factors" ) {
    return "Set factors needs 3 parameters (p i d)" if(@a != 5);
    $pid->{pFactor} = $a[2];
    $pid->{iFactor} = $a[3];
    $pid->{dFactor} = $a[4];
    # modify DEF, alse save won't work.
    my @d = split(' ', $pid->{DEF});
    $pid->{DEF} = "$d[0] $d[1] $a[2] $a[3] $a[4]";

  } elsif ($arg eq "desired" ) {
    return "Set desired needs a numeric parameter"
        if(@a != 3 || $a[2] !~ m/^[\d\.]*$/);
    Log GetLogLevel($n,3), "PID set $n $arg $a[2]";
    PID_sv($pid, 'desired', $a[2]);
    PID_setValue($pid);

  } else {
    return "Unknown argument $a[1], choose one of factors desired"

  }
  return "";
}

##########################
sub
PID_Notify($$)
{
  my ($pid, $dev) = @_;
  my $pn = $pid->{NAME};

  return "" if($attr{$pn} && $attr{$pn}{disable});

  return if($dev->{NAME} ne $pid->{sensor});

  my $reading = $pid->{reading};
  my $max = int(@{$dev->{CHANGED}});

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    next if($s !~ m/$reading/);
    PID_setValue($pid);
    last;
  }
  return "";
}

##########################
sub
PID_saturate($$)
{
  my ($pid, $v) = @_;
  return $pid->{satMax} if($v > $pid->{satMax});
  return $pid->{satMin} if($v < $pid->{satMin});
  return $v;
}

sub
PID_sv($$$)
{
  my ($pid,$name,$val) = @_;
  $pid->{READINGS}{$name}{VAL} = $val;
  $pid->{READINGS}{$name}{TIME} = TimeNow();
}

sub
PID_gv($$)
{
  my ($pid,$name) = @_;
  return $pid->{READINGS}{$name}{VAL}
    if($pid->{READINGS} && $pid->{READINGS}{$name});
  return undef;
}


sub
PID_setValue($)
{
  my ($pid) = @_;
  my $n = $pid->{NAME};
  my $sensor = $pid->{sensor};
  my $reading = $pid->{reading};
  my $re = $pid->{regexp};

  # Get the value from the READING
  my $inStr;
  $inStr = $defs{$sensor}{READINGS}{$reading}{VAL}
    if($defs{$sensor}{READINGS} && $defs{$sensor}{READINGS}{$reading});
  if(!$inStr) {
    Log GetLogLevel($n,4), "PID $n: no $reading yet for $sensor";
    return;
  }
  $inStr =~ m/$re/;
  my $in = $1;
   
  my $desired = PID_gv($pid, 'desired');
  return if(!defined($desired));

  my $delta = $desired - $in;
  my $p = $delta * $pid->{pFactor};

  my $i = PID_saturate($pid, PID_gv($pid,'integrator')+$delta*$pid->{iFactor});
  PID_sv($pid, 'integrator', $i);

  my $d = ($delta - PID_gv($pid,'delta')) * $pid->{dFactor};
  PID_sv($pid, 'delta',  $delta);

  my $a =  PID_saturate($pid, $p + $i + $d);
  PID_sv($pid, 'actuation', $a);

  Log GetLogLevel($n,4), sprintf("PID $n: p:%.2f i:%.2f d:%.2f", $p, $i, $d);

  # Hack to round.
  $a = int($a) if(($pid->{satMax} - $pid->{satMin}) >= 100);

  my $ret = fhem sprintf("set %s %s %g", $pid->{actor}, $pid->{command}, $a);
  Log GetLogLevel($n,1), "output of $n command: $ret" if($ret);
  $pid->{STATE} = "$in (delta $delta)";
}

1;
