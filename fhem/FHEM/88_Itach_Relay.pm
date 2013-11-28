################################################################
#
#  Copyright notice
#
#  (c) 2011 Sacha Gloor (sacha@imp.ch)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################
# $Id$

##############################################
package main;

use strict;
use warnings;
use Data::Dumper;
use Net::Telnet;

sub
ITACH_RELAY_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "ITACH_RELAY_Set";
  $hash->{DefFn}     = "ITACH_RELAY_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
ITACH_RELAY_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of on off toggle" if($a[1] eq "?");

  my $v = $a[1];

  if($v eq "toggle")
  {
	if(defined $hash->{READINGS}{state}{VAL})
	{
		if($hash->{READINGS}{state}{VAL} eq "off")
		{
			$v="on";
		}
		else
		{
			$v="off";
		}
	}
	else
	{
		$v="off";
	}
  }

  ITACH_RELAY_execute($hash->{DEF},$v);

  Log GetLogLevel($a[0],2), "ITACH_RELAY set @a";

  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;

  DoTrigger($hash->{NAME}, undef);

  return undef;

}
###################################
sub
ITACH_RELAY_execute($@)
{
	my ($target,$cmd) = @_;
	my $URL='';
	my $v='';
	my $err_log='';

	if($cmd eq "on") { $v=1; }
	else { $v=0; }

  	my @a = split("[ \t][ \t]*", $target);

	my $tel=new Net::Telnet(Host => $a[0], Port => 4998,Timeout => 3, Binmode => 0, Telnetmode => 0, Errmode => "return");

  	if(!defined($tel))
  	{
  		Log 4,"Error connecting to ".$a[0].":4998";
  	}
  	else
  	{
		my $cmd="setstate,1:".$a[1].",".$v."\n";
		$tel->print($cmd);
		sleep(1);
	}

	return undef;
}

sub
ITACH_RELAY_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];

  return "Wrong syntax: use define <name> ITACH_RELAY <ip-address> <port-nr>" if(int(@a) != 4);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
 
  return undef;
}

1;

=pod
=begin html

<a name="Itach_Relay"></a>
<h3>ITACH_RELAY</h3>
<ul>
  Note: this module needs the Net::Telnet module.
  <br><br>
  <a name="ITACH_RELAYdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ITACH_RELAY &lt;ip-address&gt; &lt;port&gt;</code>
    <br><br>
    Defines an Global Cache iTach Relay device (Box with 3 relays) via its ip address. <br><br>


    Examples:
    <ul>
      <code>define motor1 ITACH_RELAY 192.168.8.200 1</code><br>
    </ul>
  </ul>
  <br>

  <a name="ITACH_RELAYset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    off
    on
    toggle
    </pre>
    Examples:
    <ul>
      <code>set motor1 on</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>Toggle is special implemented. List name returns "on" or "off" even after a toggle command</li>
    </ul>
  </ul>
</ul>

=end html
=cut
