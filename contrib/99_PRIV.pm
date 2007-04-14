##############################################
# Example perl functions. Put this file into the FHEM directory.
#
#   # Activate 2 rollades at once with one button, open them to
#   # a different degree.
#   define ntfy_1 notifyon btn3 {MyFunc("@", "%")}
#
#   # Swith the heater off if all FHT actuators are closed,
#   # and on if at least one is open
#   define at_1 at +*00:05 { fhem "set heater " . (sumactuator()?"on":"off") };

package main;
use strict;
use warnings;

sub
PRIV_Initialize($$)
{
  my ($hash, $init) = @_;
}

sub
sumactuator()
{
  my $sum = 0;
  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "FHT");
    my ($act, undef) = split(" ", $defs{$d}{READINGS}{"actuator"}{VAL});
    $act =~ s/%//;
    $sum += $act;
  }
  return $sum;
}

sub
MyFunc($$)
{
  my ($a1, $a2) = @_;

  Log 2, "Device $a1 was set to $a2 (type: $defs{$a1}{TYPE})";
  if($a2 eq "on") {
    fhem "set roll1 on-for-timer 10";
    fhem "set roll2 on-for-timer 16";
  } else {
    fhem "set roll1 off";
    fhem "set roll2 off";
  }
}

1;
