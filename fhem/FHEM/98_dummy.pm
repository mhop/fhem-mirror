##############################################
# $Id$
package main;

use strict;
use warnings;

sub
dummy_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "dummy_Set";
  $hash->{DefFn}     = "dummy_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 setList";
}

###################################
sub
dummy_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my $setList = AttrVal($name, "setList", "*");
  return "Unknown argument ?, choose one of $setList" if($a[0] eq "?");

  my $v = join(" ", @a);
  Log GetLogLevel($name,2), "dummy set $name $v";

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
