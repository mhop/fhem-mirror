##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub EMEM_Get($@);
sub EMEM_Define($$);
sub EMEM_GetStatus($);

###################################
sub
EMEM_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "EMEM_Get";
  $hash->{DefFn}     = "EMEM_Define";

  $hash->{AttrList}  = "IODev dummy:1,0 model:EM1000EM";
}

###################################
sub
EMEM_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+300, "EMEM_GetStatus", $hash, 0);
  }

  my $dnr = $hash->{DEVNR};
  my $name = $hash->{NAME};

  return "Empty status: dummy IO device" if(IsIoDummy($name));

  my $d = IOWrite($hash, sprintf("7a%02x", $dnr-1));
  if(!defined($d)) {
    my $msg = "EMEM $name read error (GetStatus 1)";
    Log3 $name, 2, $msg;
    return $msg;
  }

  if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6)) {
    my $msg = "EMEM no device no. $dnr present";
    Log3 $name, 2, $msg;
    return $msg;
  }

  my $pulses=w($d,13);
  my $pulses_max= w($d,15);
  my $iec = 1000;
  my $cur_power = $pulses / 100;
  my $cur_power_max = $pulses_max / 100;

  if($cur_power > 30) { # 20Amp x 3 Phase
    my $msg = "EMEM Bogus reading: curr. power is reported to be $cur_power, setting to -1";
    Log3 $name, 2, $msg;
    #return $msg;
    $cur_power = -1.0;
  }
  if($cur_power_max > 30) { # 20Amp x 3 Phase
    $cur_power_max = -1.0;
  }

  my %vals;
  $vals{"5min_pulses"}        = $pulses;
  $vals{"5min_pulses_max"}    = $pulses_max;
  $vals{"energy_kWh_h"}       = sprintf("%0.3f", dw($d,33) / $iec);
  $vals{"energy_kWh_d"}	      = sprintf("%0.3f", dw($d,37) / $iec);
  $vals{"energy_kWh_w"}       = sprintf("%0.3f", dw($d,41) / $iec);
  $vals{"energy_kWh"}         = sprintf("%0.3f", dw($d, 7) / $iec);
  $vals{"power_kW"}           = sprintf("%.3f", $cur_power);
  $vals{"power_kW_max"}       = sprintf("%.3f", $cur_power_max);
  $vals{"alarm_PA_W"}         = w($d,45);
  $vals{"price_CF"}           = sprintf("%.3f", w($d,47)/10000);


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
  Log3 $name, 4, "EMEM $name: $cur_power kW / $vals{energy_kWh} kWh";

  return $hash->{STATE};
}

###################################
sub
EMEM_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] ne "status") {
    return "unknown argument $a[1], choose one of status";
  }
  $hash->{LOCAL} = 1;
  my $v = EMEM_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}

#############################
sub
EMEM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> EMEM devicenumber"
    if(@a != 3 || $a[2] !~ m,^[5-8]$,);
  $hash->{DEVNR} = $a[2];
  AssignIoPort($hash);


  EMEM_GetStatus($hash);
  return undef;
}

1;

=pod
=begin html

<a name="EMEM"></a>
<h3>EMEM</h3>
<ul>
  <br>

  <a name="EMEMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EMEM &lt;device-number&gt;</code>
    <br><br>

    Define up to 4 EM1000EM attached to the EM1010PC. The device number must
    be between 5 and 8.
    Defining an EMEM will schedule an internal task, which reads the
    status of the device every 5 minutes, and triggers notify/filelog commands.
    <br>Note: Currently this device does not support a "set" function.
    <br><br>

    Example:
    <ul>
      <code>define emem EMEM 5</code><br>
    </ul>
  </ul>
  <br>

  <b>Set</b> <ul>N/A</ul><br>


  <a name="EMEMget"></a>
  <b>Get</b>
  <ul>
    <code>get EMEM status</code>
    <br><br>
    This is the same command which is scheduled every 5 minutes internally.
  </ul>
  <br>

  <a name="EMEMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (EM1000EM)</li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#IODev">IODev</a></li><br>
  </ul>
  <br>
</ul>

=end html
=cut
