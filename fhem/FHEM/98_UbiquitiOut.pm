################################################################
#
#  $Id$
#
#  (c) 2015 Copyright: Wzut
#  forum : http://forum.fhem.de/index.php/topic,34131.0.html
#  All rights reserved
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################
#  Changelog:

package main;

use strict;
use warnings;
use SetExtensions;

sub UbiquitiOut_Initialize($)
{
  my ($hash) = @_;
  $hash->{SetFn}     = "UbiquitiOut_Set";
  $hash->{DefFn}     = "UbiquitiOut_Define";
  $hash->{UndefFn}   = "UbiquitiOut_Undef";
  $hash->{AttrList}  =  $readingFnAttributes;
}

###################################

sub UbiquitiOut_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  my @a = split("[ \t][ \t]*", $def);
  
  return "wrong syntax: use define $name UbiquitiOut <Device> <Out#>" if(int(@a) < 4);

  my $parent = $a[2];
  my $socket = $a[3];

  $hash->{IODEV}    = $parent;
  $hash->{SOCKETNR} = $socket;

  $modules{UbiquitiOut}{defptr}{$parent.$socket} = $hash;

  if (defined($attr{$parent}{room})) { $attr{$name}{room} = $attr{$parent}{room}; }

  my $currentstate = ReadingsVal($parent, $name, "defined");
  $hash->{STATE}   = $currentstate ;
  $hash->{READINGS}{lock}{VAL} = 0;
  return undef;
}

###################################

sub UbiquitiOut_Undef($$)
{
  my ($hash, undef) = @_;
  my $parent = $hash->{IODEV};
  my $socket = $hash->{SOCKETNR};
  delete $modules{UbiquitiOut}{defptr}{$parent.$socket} ;
  return undef;
}

###################################

sub UbiquitiOut_Set($@)
{
  my ($hash, $name , @a) = @_;
  my $cmd        = $a[0]; 

  my $cmdList    = "off:noArg on:noArg toggle:noArg";

  return "$name, no set value specified" if(int(@a) < 1);
  return "$name, I/O device not found please define UbiquitiPM device first" if(!defined($hash->{IODEV}));

  return undef if ($hash->{READINGS}{lock}{VAL} eq "1") && ($cmd eq "?");
  return "$name, set command is not available while device is locked !" if ($hash->{READINGS}{lock}{VAL} eq "1");


  if($cmd =~ /^(on|off|toggle)$/) # nur diese drei Kommandos kennt es selbst
  {
     CommandSet(undef,$hash->{IODEV}." Out".$hash->{SOCKETNR}. " $cmd");
     return undef;
  } 

  return SetExtensions($hash,$cmdList,$name,@a); 
}

#####################################

1;

=pod
=begin html

<a name="UbiquitiOut"></a>
<h3>UbiquitiOut</h3>
<ul>
  <table><tr><td>
  sub device for the UbiquitiMP or InfratekPM modul
  </td></tr></table>

  <a name="UbiquitiOutdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; UbiquitiOut &lt;UbiquitiMP device&gt;  &lt;Out #&gt;</code>
  </ul>

  <a name="UbiquitiOutset"></a>
  <b>Set </b>
  <ul><a href="#setExtensions">set Extensions</a>
  </ul>
</ul>
=end html

