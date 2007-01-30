##############################################
# Example for notifying with perl-code, in a proper file, not inline.
# Add the following line to the configuration file (02_fs20):
#   notifyon btn3 {MyFunc("@", "%")}
# and put this file in the <modpath>/FHEM directory.

package main;
use strict;
use warnings;

sub
PRIV_Initialize($$)
{
  my ($hash, $init) = @_;
  $hash->{Category} = "none";
}

sub
MyFunc($$)
{
  my ($a1, $a2) = @_;

  Log 2, "Device $a1 was set to $a2 (type: $defs{$a1}{TYPE})";
  if($a2 eq "on") {
    fhz "roll1 on-for-timer 10";
    fhz "roll2 on-for-timer 16");
  } else {
    fhz "roll1 off";
    fhz "roll2 off";
  }
}

1;
