##############################################
package main;

use strict;
use warnings;

sub
dummy_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "dummy_Set";
  $hash->{DefFn}     = "dummy_Define";
}

###################################
sub
dummy_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of *" if($a[1] eq "?");


  my $v = $a[1];

  Log GetLogLevel($a[0],2), "dummy set @a";

  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;
  return undef;
}

sub
dummy_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> dummy" if(int(@a) != 2);
  return undef;
}

1;
