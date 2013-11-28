##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub EMWZ_Get($@);
sub EMWZ_Set($@);
sub EMWZ_Define($$);
sub EMWZ_GetStatus($);

###################################
sub
EMWZ_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "EMWZ_Get";
  $hash->{SetFn}     = "EMWZ_Set";
  $hash->{DefFn}     = "EMWZ_Define";

  $hash->{AttrList}  = "IODev dummy:1,0 model:EM1000WZ loglevel:0,1,2,3,4,5,6";
}


###################################
sub
EMWZ_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+300, "EMWZ_GetStatus", $hash, 0);
  }

  my $dnr = $hash->{DEVNR};
  my $name = $hash->{NAME};

  return "Empty status: dummy IO device" if(IsIoDummy($name));

  my $d = IOWrite($hash, sprintf("7a%02x", $dnr-1));
  if(!defined($d)) {
    my $msg = "EMWZ $name read error (GetStatus 1)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }


  if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6)) {
    my $msg = "EMWZ no device no. $dnr present";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my $pulses=w($d,13);
  my $ec=w($d,49) / 10;
  if($ec <= 0) {
    my $msg = "EMWZ read error (GetStatus 2)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }
  my $cur_energy = $pulses / $ec;       # ec = U/kWh
  my $cur_power = $cur_energy / 5 * 60; # 5minute interval scaled to 1h

  if($cur_power > 30) { # 20Amp x 3 Phase
    my $msg = "EMWZ Bogus reading: curr. power is reported to be $cur_power";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my %vals;
  $vals{"5min_pulses"} = $pulses;
  $vals{"energy"} = sprintf("%0.3f", $cur_energy);
  $vals{"power"} = sprintf("%.3f", $cur_power);
  $vals{"alarm_PA"} = w($d,45) . " Watt";
  $vals{"price_CF"} = sprintf("%.3f", w($d,47)/10000);
  $vals{"RperKW_EC"} = $ec;
  $hash->{READINGS}{cum_kWh}{VAL} = 0 if(!$hash->{READINGS}{cum_kWh}{VAL});
  $vals{"cum_kWh"} = sprintf("%0.3f",
                      $hash->{READINGS}{cum_kWh}{VAL} + $vals{"energy"}); 
  $vals{summary} = sprintf("Pulses: %s Energy: %s Power: %s Cum: %s",
                      $vals{"5min_pulses"}, $vals{energy},
                      $vals{power}, $vals{cum_kWh});
  

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

  $hash->{STATE} = "$cur_power kW";
  Log GetLogLevel($name,4), "EMWZ $name: $cur_power kW / $vals{energy}";

  return $hash->{STATE};
}

###################################
sub
EMWZ_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] ne "status") {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  my $v = EMWZ_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}

sub
EMWZ_Set($@)
{
  my ($hash, @a) = @_;

  my $name = $hash->{NAME};

  my $v = $a[2];
  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] eq "price" && int(@a) == 3) {
    $v *= 10000; # Make display and input the same
    $msg = sprintf("79%02x2f02%02x%02x", $d-1, $v%256, int($v/256));
  } elsif($a[1] eq "alarm" && int(@a) == 3) {
    $msg = sprintf("79%02x2d02%02x%02x", $d-1, $v%256, int($v/256));
  } elsif($a[1] eq "rperkw" && int(@a) == 3) {
    $v *= 10; # Make display and input the same
    $msg = sprintf("79%02x3102%02x%02x", $d-1, $v%256, int($v/256));
  } else {
    return "Unknown argument $a[1], choose one of price alarm rperkw";
  }

  return "" if(IsIoDummy($name));
  my $ret = IOWrite($hash, $msg);
  if(!defined($ret)) {
    my $msg = "EMWZ $name read error (Set)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  if(ord(substr($ret,0,1)) != 6) {
    $ret = "EMWZ Error occured: " .  unpack('H*', $ret);
    Log GetLogLevel($name,2), $ret;
    return $ret;
  }

  return undef;
}

#############################
sub
EMWZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> EMWZ devicenumber"
    if(@a != 3 || $a[2] !~ m,^[1-4]$,);
  $hash->{DEVNR} = $a[2];
  AssignIoPort($hash);


  EMWZ_GetStatus($hash);
  return undef;
}

1;

=pod
=begin html

<a name="EMWZ"></a>
<h3>EMWZ</h3>
<ul>
  <a name="EMWZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EMWZ &lt;device-number&gt;</code>
    <br><br>

    Define up to 4 EM1000WZ attached to the EM1010PC. The device number must
    be between 1 and 4. Defining an EMWZ will schedule an internal task, which
    reads the status of the device every 5 minutes, and triggers notify/filelog
    commands.  <br><br>

    Example:
    <ul>
      <code>define emwz EMWZ 1</code><br>
    </ul>
  </ul>
  <br>

  <a name="EMWZset"></a>
  <b>Set</b>
  <ul>
    <code>set EMWZdevice  &lt;param&gt; &lt;value&gt;</code><br><br>
    where param is one of:
    <ul>
      <li>rperkw<br>
          Number of rotations for a KiloWatt of the EM1000WZ device (actually
          of the device where the EM1000WZ is attached to). Without setting
          this correctly, all other readings will be incorrect.
      <li>alarm<br>
          Alarm in WATT. if you forget to set it, the default value is
          rediculously low (random), and if a value above this threshold is
          received, the EM1010PC will start beeping once every minute. It can
          be very annoying.
      <li>price<br>
          The price of one KW in EURO (use e.g. 0.20 for 20 Cents). It is used
          only on the EM1010PC display, it is of no interest for FHEM.
    </ul>
  </ul>
  <br>


  <a name="EMWZget"></a>
  <b>Get</b>
  <ul>
    <code>get EMWZ status</code>
    <br><br>
    This is the same command which is scheduled every 5 minutes internally.
  </ul>
  <br>

  <a name="EMWZattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (EM1000WZ)</li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#IODev">IODev</a></li><br>
  </ul>
  <br>
</ul>


=end html
=cut
