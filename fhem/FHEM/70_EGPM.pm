############################################## 
# $Id: EGPM.pm 2892 2013-07-11 12:47:57Z alexus $ 
#
#  (c) 2013 Copyright: Alex Storny (moselking at arcor dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################
#  -> Module 17_EGPM2LAN.pm (Host) needed.
################################################################
package main;

use strict;
use warnings;

sub
EGPM_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "EGPM_Set";
  $hash->{DefFn}     = "EGPM_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6". $readingFnAttributes;
  $hash->{UndefFn}   = "EGPM_Undef";
}

###################################
sub
EGPM_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $parent = $hash->{IODEV};
  my $loglevel = GetLogLevel($name,4);

  return "no set value specified" if(int(@a) < 1);
  return "Unknown argument ?, choose one of off on toggle" if($a[0] eq "?");

  if(not Value($parent))
  {
    my $u = "$parent not found. Please define EGPM2LAN device.";
    Log $loglevel, $u;
    return $u;
  }

  my $v = join(" ", @a);
  Log $loglevel, "EGPM set $name $v";
  CommandSet(undef,$hash->{IODEV}." $v ".$hash->{SOCKETNR});
  
  return undef;
}

#####################################
sub
EGPM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  my $u = "wrong syntax: use define <name> EGPM <Device> <socketNr.>";

  return $u if(int(@a) < 4);

  my $name = $a[0];
  my $parent = $a[2];
  my $socket = $a[3];

  $hash->{IODEV} = $parent;
  $hash->{SOCKETNR} = $socket;
  $hash->{NAME} = $name;

  $modules{EGPM}{defptr}{$parent.$socket} = $hash;
		
  if (defined($attr{$parent}{room}))
  {
    $attr{$name}{room} = $attr{$parent}{room};
  }
  $hash->{STATE} = "initialized";

  return undef;
}

#####################################
sub
EGPM_Undef($$)
{
  my ($hash, $name) = @_;
  my $parent = $hash->{IODEV};
  my $socket = $hash->{SOCKETNR};

      Log GetLogLevel($name,4), "Delete ".$parent.$socket;
      delete $modules{EGPM}{defptr}{$parent.$socket} ;   
  
  return undef;
}

1;

=pod
=begin html

<a name="EGPM"></a>
<h3>EGPM Socket</h3>
<ul>

  Define a Socket from EGPM2LAN Module. If the global Module AUTOCREATE is enabled,
  this device will be created automatically. For manual Setup, pls. see the description of EGPM2LAN.
  <br><br>

  <a name="EGPMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EGPM &lt;device&gt; &lt;socket-nr&gt;</code>
    <br><br>

    Example:
    <ul>
      <code>define socket_lamp EGPM mainswitch 1</code><br>
      <code>set socket_lamp on</code><br>
    </ul>
  </ul>
  <br>

  <a name="EGPMset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set any value.
  </ul>
  <br>

  <a name="EGPMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="EGPMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html
=cut
