#
#
# 82_M232Voltage.pm
# written by Dr. Boris Neubert 2007-12-24
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub M232Voltage_Get($@);
sub M232Voltage_Define($$);
sub M232Voltage_GetStatus($);

###################################
sub
M232Voltage_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "M232Voltage_Get";
  $hash->{DefFn}     = "M232Voltage_Define";

  $hash->{AttrList}  = "dummy:1,0 model:M232Voltage";
}

###################################
sub
M232Voltage_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+60, "M232Voltage_GetStatus", $hash, 1);
  }

  my $name = $hash->{NAME};

  my $d = IOWrite($hash, "a" . $hash->{INPUT});
  if(!defined($d)) {
    my $msg = "M232Voltage $name read error";
    Log3 $name, 2, $msg;
    return $msg;
  }

  my $tn = TimeNow();
  my $value= (hex substr($d,0,3))*5.00/1024.0 *  $hash->{FACTOR};

  $hash->{READINGS}{value}{TIME} = $tn;
  $hash->{READINGS}{value}{VAL} = $value;

  $hash->{CHANGED}[0]= "value: $value";

  if(!$hash->{LOCAL}) {
    DoTrigger($name, undef) if($init_done);
  }

  $hash->{STATE} = $value;
  Log3 $name, 4, "M232Voltage $name: $value $hash->{UNIT}";

  return $hash->{STATE};
}

###################################
sub
M232Voltage_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $msg;

  if($a[1] ne "status") {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  my $v = M232Voltage_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}

#############################
sub
M232Voltage_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> M232Voltage an0..an5 [unit [factor]]"
    if(int(@a) < 3 && int(@a) > 5);

  my $reading= $a[2];
  return "$reading is not an analog input, valid: an0..an5"
    if($reading !~  /^an[0-5]$/) ;

  my $unit= ((int(@a) > 3) ? $a[3] : "volts");
  my $factor= ((int(@a) > 4) ? $a[4] : 1.0);
 
  $hash->{INPUT}= substr($reading,2);
  $hash->{UNIT}= $unit;
  $hash->{FACTOR}= $factor;

  AssignIoPort($hash);

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+60, "M232Voltage_GetStatus", $hash, 0);
  }
  return undef;
}

1;

=pod
=begin html

<a name="M232Voltage"></a>
<h3>M232Voltage</h3>
<ul>
  <br>

  <a name="M232Voltagedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; M232Voltage [an0..an5] [unit [factor]]</code>
    <br><br>

    Define as many M232Voltages as you like for a M232 device. Defining a
    M232Voltage will schedule an internal task, which reads the status of the
    analog input every minute, and triggers notify/filelog commands.
    <code>unit</code> is the unit name, <code>factor</code> is used to
    calibrate the reading of the analog input.<br><br>

    Note: the unit defaults to the string "volts", but it must be specified
    if you wish to set the factor, which defaults to 1.0. <br><br>

    Example:
    <ul>
      <code>define volt M232Voltage an0</code><br>
      <code>define brightness M232Voltage an5 lx 200.0</code><br>
    </ul>
    <br>
  </ul>

  <b>Set</b> <ul>N/A</ul><br>

  <a name="M232Voltageget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; status</code>
    <br><br>
  </ul>

  <a name="M232Voltageattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#model">model</a> (M232Voltage)</li>
  </ul>
  <br>

</ul>

=end html
=cut
