############################################## 
# $Id$ 
#
#  (c) 2013, 2014 Copyright: Alex Storny (moselking at arcor dot de)
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
use SetExtensions;

sub
EGPM_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "EGPM_Set";
  $hash->{GetFn}     = "EGPM_Get";
  $hash->{DefFn}     = "EGPM_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 $readingFnAttributes ";
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
  my $cmdList = "off:noArg on:noArg toggle:noArg";

  return "no set value specified" if(int(@a) < 1);
  return SetExtensions($hash,$cmdList,$name,@a) if($a[0] eq "?");

  if(not Value($parent))
  {
    my $u = "$parent device not found. Please define EGPM2LAN device.";
    Log $loglevel, $u;
    return $u;
  }

  if($a[0] =~ /^(on|off|toggle)$/)
  {
    my $v = join(" ", @a);
    Log $loglevel, "EGPM set $name $v";
     CommandSet(undef,$hash->{IODEV}." $v ".$hash->{SOCKETNR});
     return undef;
  } else {
     Log $loglevel, "EGPM set $name $a[0]";
     return SetExtensions($hash,$cmdList,$name,@a);
  }
}


###################################
sub
EGPM_Get($@)
{
    my ($hash, @a) = @_;
    my $what;

    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    if($what =~ /^(state)$/)
    {
      if(defined($hash->{READINGS}{$what}))
      {
			   return $hash->{READINGS}{$what}{VAL};
		  }
      else
		  {
			   return "reading not found: $what";
		  }
    }
    else
    {
		  return "Unknown argument $what, choose one of state:noArg".(exists($hash->{READINGS}{output})?" output:noArg":"");
    }
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
  
  my $currentstate = ReadingsVal($parent, "state", "?");
  if ($currentstate eq "?")
  {
    $hash->{STATE} = "initialized";
  }
  else
  {
    my @powerstates = split(":", $currentstate);
    $hash->{STATE} = trim(substr $powerstates[$socket], 1, 3);
  }

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

  Defines a Socket from EGPM2LAN Module. If the global Module AUTOCREATE is enabled,
  this device will be created automatically. For manual Setup, pls. see the description of <a href="#EGPM2LAN">EGPM2LAN</a>.
  <br><br>

  <a name="EGPMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EGPM &lt;device&gt; &lt;socket-nr&gt;</code>
    <br>
  </ul>
  <br>

  <a name="EGPMset"></a>
  <b>Set</b>
    <ul><code>set &lt;name&gt; &lt;[on|off|toggle]&gt;</code><br>
    Switches the socket on or of.
    </ul>
    <ul><code>set &lt;name&gt; &lt;[on-for-timer|off-for-timer|on-till|off-till|blink|intervals]&gt;</code><br>
    Switches the socket for a specified time+duration or n-times. For Details see <a href="#setExtensions">set extensions</a>
    </ul><br>
    Example:
    <ul>
      <code>define lamp1 EGPM mainswitch 1</code><br>
      <code>set lamp1 on</code><br>
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
  <a name="EGPM2LANevents"></a>
  <b>Generated events</b>
  <ul>
  <li>EGPM &lt;name&gt; &lt;[on|off]&gt</li>
  </ul>

</ul>

=end html
=begin html_DE

<a name="EGPM"></a>
<h3>EGPM Steckdose</h3>
<ul>
  Definiert eine einzelne Netzwerk-Steckdose vom EGPM2LAN. Diese Definition wird beim Einrichten eines EGPM2LAN automatisch erstellt,
  wenn das globale FHEM-Attribut AUTOCREATE aktiviert wurde. F&uuml;r weitere Informationen, siehe Beschreibung von <a href="#EGPM2LAN">EGPM2LAN</a>.
  <br><br>

  <a name="EGPMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EGPM &lt;device&gt; &lt;socket-nr&gt;</code>
    <br>
  </ul>
  <br>

  <a name="EGPMset"></a>
  <b>Set</b>
    <ul><code>set &lt;name&gt; &lt;[on|off|toggle]&gt;</code><br>
    Schaltet die Steckdose ein oder aus.
    </ul>
    <ul><code>set &lt;name&gt; &lt;[on-for-timer|off-for-timer|on-till|off-till|blink|intervals]&gt;</code><br>
    Schaltet die Steckdose f&uuml; einen bestimmten Zeitraum oder mehrfach hintereinander. Weitere Infos hierzu unter <a href="#setExtensions">set extensions</a>.
    </ul><br>
    Beispiel:
    <ul>
      <code>define lampe1 EGPM steckdose 1</code><br>
      <code>set lampe1 on</code><br>
    </ul>
  <br>

  <a name="EGPMget"></a>
  <b>Get</b> <ul>N/A</ul>
  <br>

  <a name="EGPMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="EGPM2LANevents"></a>
  <b>Generated events</b>
  <ul>
  <li>EGPM &lt;name&gt; &lt;[on|off]&gt</li>
  </ul>
</ul>
=end html_DE

=cut
