##############################################
# $Id$
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

=pod
=begin html

<a name="PID"></a>
<h3>PID</h3>
<ul>
  The PID device is a loop controller, used to set the value e.g of a heating
  valve dependent of the current and desired temperature.
  <br>
  <br>

  <a name="PIDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PID sensor[:reading:regexp] actor[:cmd:min:max] [p i d]</code>
    <br><br>

    <code>sensor[:reading:regexp]</code> specifies the sensor, which is an
    already defined fhem device, e.g. a S300TH temperature sensor. The reading
    and regexp fields are necessary only for unknown devices (currently <a
    href="#CUL_WS">CUL_WS</a> and <a href="#HMS">HMS</a> devices are "known").
    Reading specifies the READINGS field of the sensor, and the regexp extracts
    the number from this field. E.g. for the complete definition for a CUL_WS
    device is: <code>s300th_dev:temperature:([\d\.]*)</code>
    <br><br>

    <code>actor[:cmd:min:max]</code> specifies the actor, which is an
    already defined fhem device, e.g. an FHT8V valve. The cmd, min and max
    fields are necessary only for unknown devices (currently <a
    href="#FHT8V">FHT8V</a> is "known"). cmd specifies the command name for the
    actor, min the minimum value and max the maximum value. The complete
    definition for an FHT8V device is:<code>fht8v_dev:valve:0:100</code>
    <br><br>

    p, i and d are the parameters use to controlling, see also the <a
    href="http://de.wikipedia.org/wiki/Regler">this</a> wikipedia entry.
    The default values are around 25.5, 3 and 5.88, you probably need to tune
    these values. They can be also changed later.
    <br><br>

    Examples:
    <ul>
      <code>define wz_pid PID wz_th wz_fht8v</code><br>
    </ul>
  </ul>
  <br>

  <a name="PIDset"></a>
  <b>Set </b>
  <ul>
      <li>set &lt;name&gt; factors p i d<br>
      Set the p, i and d factors, as described above.
      </li>
      <li>set &lt;name&gt; desired &lt;value&gt;<br>
      Set the desired value (e.g. temperature). Note: until this value is not
      set, no command is issued.
      </li>
  </ul>
  <br>

  <a name="PIDget"></a>
  <b>Get </b>
  <ul>
      N/A
  </ul>
  <br>

  <a name="PIDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
  <br>
</ul>



=end html
=cut
