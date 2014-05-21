##############################################
# $Id$
##############################################
package main;

use strict;
use warnings;

sub
FRM_LCD_Initialize($)
{
  my ($hash) = @_;
  main::LoadModule("I2C_LCD");
  I2C_LCD_Initialize($hash);
  $hash->{DefFn}  = "FRM_LCD_Define";
  $hash->{InitFn} = "FRM_LCD_Init";
};

sub
FRM_LCD_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  shift @a;
  return I2C_LCD_Define($hash,join(' ',@a));
}

sub
FRM_LCD_Init($)
{
  my ($hash,$args) = @_;
  my $u = "wrong syntax: define <name> FRM_LCD i2c <size-x> <size-y> [<address>]";
  return $u if(int(@$args) < 3);
  shift @$args;
  return I2C_LCD_Init($hash,$args);
}

1;

=pod
=begin html

<a name="FRM_LCD"></a>
<h3>FRM_LCD</h3>
<ul>
  deprecated, use <a href="#I2C_LCD">I2C_LCD</a>
</ul>
=end html
=cut
