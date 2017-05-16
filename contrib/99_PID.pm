##############################################
# This is primary intended to use S300TH/S555TH in conjunction with FHT8v
# to control room temperature
# for this I defined the following:
# define conf_set_value dummy
# define conf_set_value notify config:pid_set_value { pid_set_value(%) }
# { pid_create("bz",0.0,255.0) }
# { pid_set_factors("bz",65.0,7.8,15.0) }
# define control_bz notify th_sensor_bz {my @@d=split(" ","%");;fhem("set CUL raw T16270126" . sprintf("%%02X", pid("bz",$d[1])))}
# trigger config:pid_set_value "bz",21.0
#
# Alexander Tietzel (Perl newby)
#
# TODO:
#   want to have references to the second hash inside %data. Some like
#   %ctrl = ${$data{$name}}...
#   Or better write this as a class and instantiate each controller
#   but I did not discover how to have persistent objects in FHEM
#   so I helped myself with the hash to have multiple instances.
###############################################
package main;
use strict;
use warnings;
use Math::Trig;

sub pid($$);
sub pid_create($$$);
sub pid_set_value($$);
sub pid_set_factors($$$$);

sub PID_Initialize($);

# See perldoc DateTime::Event::Sunrise for details
my %data;
sub
PID_Initialize($)
{
  my ($hash) = @_;
}


##########################

sub pid_create($$$) {
  my $name = shift;
  my $min = shift;
  my $max = shift;

  ${$data{$name}}{'last_time'} = 0.0;
  ${$data{$name}}{'p_factor'} = 0.0;
  ${$data{$name}}{'i_factor'} = 0.0;
  ${$data{$name}}{'d_factor'} = 0.0; 
  ${$data{$name}}{'error'} = 0.0;
  ${$data{$name}}{'actuation'} = 0.0;
  ${$data{$name}}{'integrator'} = 0.0;
  ${$data{$name}}{'set_value'} = 0.0;
  ${$data{$name}}{'sat_min'} = $min;
  ${$data{$name}}{'sat_max'} = $max;
  return undef;
}

sub pid_set_factors($$$$) {
  my $name = shift;
  my $p_factor = shift;
  my $i_factor = shift;
  my $d_factor = shift;

  ${$data{$name}}{'p_factor'} = $p_factor;
  ${$data{$name}}{'i_factor'} = $i_factor;
  ${$data{$name}}{'d_factor'} = $d_factor;
  return undef;
}

sub pid_set_value($$) {
  my $name = shift;
  my $set_value = shift;
  ${$data{$name}}{'set_value'} = $set_value;
  return undef;
}


sub saturate($$) {
  my $name = shift;
  my $v = shift;

  if ( $v > ${$data{$name}}{'sat_max'} ) {
    return ${$data{$name}}{'sat_max'};
  }
  if ( $v < ${$data{$name}}{'sat_min'} ) {
      return ${$data{$name}}{'sat_min'};
  }
  return $v;
}

sub pid($$) { 
  my $name = shift;
  my $in = shift;

  # Log 1, "PID (" . $name . "): kp: " . ${$data{$name}}{'p_factor'} . " ki: " . ${$data{$name}}{'i_factor'} . " kd: " .${$data{$name}}{'d_factor'};
  my $error = ${$data{$name}}{'set_value'} - $in;
  my $p = $error * ${$data{$name}}{'p_factor'};
  my $i = ${$data{$name}}{'integrator'}+$error*${$data{$name}}{'i_factor'};
  ${$data{$name}}{'integrator'} = saturate($name, $i);
  my $d = ($error - ${$data{$name}}{'error'}) * ${$data{$name}}{'d_factor'};
  ${$data{$name}}{'error_value'} = $error;
  my $a = $p + ${$data{$name}}{'integrator'} + $d;
  ${$data{$name}}{'actuation'} = saturate($name, $a);
  Log 4, sprintf("PID (%s): p: %.2f i: %.2f d: %.2f", $name, $p, ${$data{$name}}{'integrator'}, $d);
  return ${$data{$name}}{'actuation'};
}

1;
