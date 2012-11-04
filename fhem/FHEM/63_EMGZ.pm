##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub EMGZ_Get($@);
sub EMGZ_Set($@);
sub EMGZ_Define($$);
sub EMGZ_GetStatus($);

###################################
sub
EMGZ_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "EMGZ_Get";
  $hash->{SetFn}     = "EMGZ_Set";
  $hash->{DefFn}     = "EMGZ_Define";

  $hash->{AttrList}  = "IODev dummy:1,0 model:EM1000GZ loglevel:0,1,2,3,4,5,6";
}


###################################
sub
EMGZ_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+300, "EMGZ_GetStatus", $hash, 0);
  }

  my $dnr = $hash->{DEVNR};
  my $name = $hash->{NAME};

  return "Empty status: dummy IO device" if(IsIoDummy($name));

  my $d = IOWrite($hash, sprintf("7a%02x", $dnr-1));
  if(!defined($d)) {
    my $msg = "EMGZ $name read error (GetStatus 1)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }


  if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6)) {
    my $msg = "EMGZ no device no. $dnr present";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my $pulses=w($d,13);

  my $ec = 100; 	# fixed value
 
  my $cur_energy = $pulses / $ec;       # ec = U/m^3
  my $cur_power = $cur_energy / 5 * 60; # 5minute interval scaled to 1h

  if($cur_power > 30) { 		# depending on "Anschlussleistung" 
    my $msg = "EMGZ Bogus reading: curr. power is reported to be $cur_power";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my %vals;
  $vals{"5min_pulses"} = $pulses;
  $vals{"act_flow_m3"} = sprintf("%0.3f", $cur_energy);
  $vals{"m3ph"}     = sprintf("%.3f", $cur_power);
  $vals{"alarm_PA"} = w($d,45) . " Watt";		# nonsens
  $vals{"price_CF"} = sprintf("%.3f", w($d,47)/10000);
  $vals{"Rperm3_EC"} = $ec;
  $hash->{READINGS}{cum_m3}{VAL} = 0 if(!$hash->{READINGS}{cum_m3}{VAL});
  $vals{"cum_m3"} = sprintf("%0.3f",
                        $hash->{READINGS}{cum_m3}{VAL} + $vals{"act_flow_m3"});
  

  my $tn = TimeNow();
  my $idx = 0;
  foreach my $k (keys %vals) {
    my $v = $vals{$k};
    $hash->{CHANGED}[$idx++] = "$k: $v";
    $hash->{READINGS}{$k}{TIME} = $tn;
    $hash->{READINGS}{$k}{VAL} = $v
  }

  if(!$hash->{LOCAL}) {
    DoTrigger($name, undef) if($init_done);
  }

  $hash->{STATE} = "$cur_power m3ph";
  Log GetLogLevel($name,4), "EMGZ $name: $cur_power m3ph / $vals{act_flow_m3}";

  return $hash->{STATE};
}

###################################
sub
EMGZ_Get($@)
{
  my ($hash, @a) = @_;

  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] ne "status" && int(@a) != 2) {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  my $v = EMGZ_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}

sub
EMGZ_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my $v = $a[2];
  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] eq "price" && int(@a) != 3) {
    $v *= 10000; # Make display and input the same
    $msg = sprintf("79%02x2f02%02x%02x", $d-1, $v%256, int($v/256));
  } else {
    return "Unknown argument $a[1], choose one of price";
  }


  return "" if(IsIoDummy($name));
  my $ret = IOWrite($hash, $msg);
  if(!defined($ret)) {
    $msg = "EMWZ $name read error (Set)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  if(ord(substr($ret,0,1)) != 6) {
    $ret = "EMGZ Error occured: " .  unpack('H*', $ret);
    Log GetLogLevel($name,2), $ret;
    return $ret;
  }

  return undef;
}

#############################
sub
EMGZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> EMGZ devicenumber"
    if(@a != 3 || $a[2] !~ m,^[9]$,);
  $hash->{DEVNR} = $a[2];
  AssignIoPort($hash);


  EMGZ_GetStatus($hash);
  return undef;
}

1;

=pod
=begin html

<a name="EMGZ"></a>
<h3>EMGZ</h3>
<ul>
  <a name="EMGZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EMGZ &lt;device-number&gt;</code>
    <br><br>

    Define up to 4 EM1000GZ attached to the EM1010PC. The device number must
    be between 9 and 12.
    Defining an EMGZ will schedule an internal task, which reads the
    status of the device every 5 minutes, and triggers notify/filelog commands.
    <br><br>

    Example:
    <ul>
      <code>define emgz EMGZ 9</code><br>
    </ul>
  </ul>

  <a name="EMGZset"></a>
  <b>Set</b>
  <ul>
    <code>set EMGZdevice  &lt;param&gt; &lt;value&gt;</code><br><br>
    where param is:
    <ul>
      <li>price<br>
          The price of one KW in EURO (use e.g. 0.20 for 20 Cents). It is used
          only on the EM1010PC display, it is of no interest for FHEM.
    </ul>
  </ul>
  <br>

  <a name="EMGZget"></a>
  <b>Get</b>
  <ul>
    <code>get EMGZ status</code>
    <br><br>
    This is the same command which is scheduled every 5 minutes internally.
  </ul>
  <br>

  <a name="EMGZattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (EM1000GZ)</li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#IODev">IODev</a></li><br>
  </ul>
  <br>
</ul>

=end html
=cut
