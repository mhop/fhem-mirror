##############################################
package main;

use strict;
use warnings;

sub
CUL_HOERMANN_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^R..........";
  $hash->{DefFn}     = "CUL_HOERMANN_Define";
  $hash->{ParseFn}   = "CUL_HOERMANN_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6";

}

#############################
sub
CUL_HOERMANN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> CUL_HOERMANN housecode " .
                        "addr [fg addr] [lm addr] [gm FF]";

  return "wrong syntax: define <name> CUL_HOERMANN 10-digit-hex-code"
        if(int(@a) != 3 || $a[2] !~ m/^[a-f0-9]{10}$/i);

  $modules{CUL_HOERMANN}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";
  return undef;
}

sub
CUL_HOERMANN_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: R0123456789
  my $cde = substr($msg, 1, 10);
  my $def = $modules{CUL_HOERMANN}{defptr}{$cde};

  if($def) {
    my $name = $def->{NAME};
    $def->{CHANGED}[0] = "toggle";
    $def->{READINGS}{state}{TIME} = TimeNow();
    $def->{READINGS}{state}{VAL} = "toggle";
    Log GetLogLevel($name,4), "CUL_HOERMANN $name toggle";
    return $name;

  } else {
    Log 3, "CUL_HOERMANN Unknown device $cde, please define it";
    return "UNDEFINED CUL_HOERMANN_$cde CUL_HOERMANN $cde";
  }
}

1;
