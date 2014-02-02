# $Id$
################################################################
#
#	This module will connect a webbased thermometer
#	to your fhem installation.
#
#	Further informations about required hardware:
#	http://www.wut.de/e-57w0w-ww-dade-000.php
#
#	(c) 2010 Sacha Gloor (sacha@imp.ch)
#
#	corrections & documentation added for fhem 
#	2013-07-30 by betateilchen ®
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################

package main;

use strict;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;

sub
WEBTHERM_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "WEBTHERM_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

sub
WEBTHERM_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];
  my $interval=$a[4];
  $attr{$name}{interval}=$interval if $interval;

  return "Usage: define <name> WEBTHERM <ip-address> <port-nr> <poll-interval>" if(int(@a) != 5);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
 
  InternalTimer(gettimeofday()+$interval, "WEBTHERM_GetStatus", $hash, 0);
 
  return;
}

sub
WEBTHERM_GetStatus($)
{
	my ($hash) = @_;
	my $err_log='';
	my $line;

	my $name = $hash->{NAME};
	my $host = $hash->{Host};

	my $interval=$attr{$name}{interval}||300;
	InternalTimer(gettimeofday()+$interval, "WEBTHERM_GetStatus", $hash, 0);

	if(!defined($hash->{Host_Port})) { return(""); }
	my $host_port = $hash->{Host_Port};

### 2013-07-30 corrected by betateilchen
#	my $URL="http://".$host."/Single".$host_port;
	my $URL="http://".$host.":".$host_port."/Single";
### end-of-correction
	my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 3);
	my $header = HTTP::Request->new(GET => $URL);
	my $request = HTTP::Request->new('GET', $URL, $header);
	my $response = $agent->request($request);

	$err_log.= "Can't get $URL -- ".$response->status_line
                unless $response->is_success;

	if($err_log ne "")
	{
		Log GetLogLevel($name,2), "WEBTHERM $name ".$err_log;
		return;
	}

	my $body =  $response->content;
	my $text='';

	my @values=split(/;/,$body);
	my $last=$values[$#values];
	my $state=$last;
	$state=~s/,/./g;
	$state=substr($state,0,-2);

	my $sensor="temperature";
	Log 4, "WEBTHERM_GetStatus: $name $host_port ".$hash->{STATE}." -> ".$state;

	$text="Temperature: ".$state;
	$hash->{STATE} = "T: ".$state;
	$hash->{CHANGED}[0] = $text;

	readingsSingleUpdate($name, $sensor, $state, 1);
	return;
}

1;

=pod
not to be translated
=begin html

<a name="WEBTHERM"></a>
<h3>WEBTHERM</h3>
<ul>
	This module connects  a <a href="http://www.wut.de/e-57w0w-ww-dade-000.php">Web-Thermometer made by W&T</a> to your FHEM installation.<br/>
	Currently this module is no longer maintained, but it should work in its current state.<br/>
	It is provided "as is" for backward compatibility.<br/>
	<br />
	<a name="WEBTHERM_Define"></a>
	<b>Define</b>
	<ul><br/>
		<code>define &lt;name&gt; WEBTHERM &lt;ip-address&gt; &lt;port-nr&gt; &lt;interval&gt;</code><br/>
		<br/>
		Defines a WEBTHERM device at given ip and port.</br>
		Values are polled periodically defined by given interval (in seconds).<br/>
		Read temperature is written into reading "state".<br/>
	</ul>
	<br/><br />

	<a name="WEBTHERM_Set"></a>
	<b>Set</b>
	<ul>
		N/A
	</ul>
	<br/><br />

	<a name="WEBTHERM_Get"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>
	<br/><br />
	
	<a name="WEBTHERM_Attr"></a>
	<b>Attr</b>
	<ul>
		N/A
	</ul>
</ul>	
=end html
=begin html_DE

<a name="WEBTHERM"></a>
<h3>WEBTHERM</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#WEBTHERM'>WEBTHERM</a><br/><br/>;
</ul>
=end html_DE
=cut
