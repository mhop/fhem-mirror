#
#
# 82_M232Voltage.pm
# written by Dr. Boris Neubert 2007-12-24
# e-mail: omega at online dot de
#
##############################################
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

  $hash->{AttrList}  = "dummy:1,0 model;M232Voltage loglevel:0,1,2,3,4,5";
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
    Log GetLogLevel($name,2), $msg;
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
  Log GetLogLevel($name,4), "M232Voltage $name: $value $hash->{UNIT}";

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
