# $Id$
####################################################################################################
#
#	55_PIFACE.pm
#
#	An FHEM Perl module to control RaspberryPi extension board PiFace
#
#	The PiFace is an add-on board for the Raspberry Pi featuring 8 open-collector outputs,
#	with 2 relays and 8 inputs (with 4 on-board buttons). 
#	These functions are fairly well fixed in the hardware, 
#	so only the read, write and internal pull-up commands are implemented.
#
#	Please read commandref for details on prerequisits!
#	Depends on wiringPi library from http://wiringpi.com
#
#	Copyright: betateilchen ®
#	e-mail: fhem.development@betateilchen.de
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
####################################################################################################

package main;

use strict;
use warnings;

sub PIFACE_Define($$);
sub PIFACE_Undefine($$);
sub PIFACE_Set($@);
sub PIFACE_Get($@);

my $base = 199;

sub PIFACE_Initialize($){
	my ($hash) = @_;
	$hash->{DefFn}		=	"PIFACE_Define";
	$hash->{UndefFn}	=	"PIFACE_Undefine";
	$hash->{SetFn}		=	"PIFACE_Set";
	$hash->{GetFn}		=	"PIFACE_Get";
	$hash->{AttrList}	=	"pifaceAutoPoll:0,1 ".
							$readingFnAttributes;
}

sub PIFACE_Define($$){
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	Log3($name, 3, "PIFACE $name: created");
	PI_read_allports($hash);
	readingsSingleUpdate($hash, "state", "active",1);
	return undef;
}

sub PIFACE_Undefine($$){
	my($hash, $name) = @_;
	RemoveInternalTimer($hash);
	return;
}

sub PIFACE_Set($@){
	my ($hash, @a)	= @_;
	my $name = $hash->{NAME};

	my $port = $a[1];
	my $val  = $a[2];
	my ($adr, $cmd, $i, $j, $k);
	
	my $usage = "Unknown argument $port, choose one of 0 1:0,1 2:0,1 3:0,1 4:0,1 5:0,1 6:0,1 7:0,1 8:0,1 ";
	return $usage if $port eq "?";
	
	if ($port ne "0") {
		$adr = $base + $port;
		Log3($name, 3, "PIFACE $name: set port $port $val");
		$cmd = "/usr/local/bin/gpio -p write $adr $val";
		$cmd = `$cmd`;
		readingsSingleUpdate($hash, 'out'.$port, $val, 1);
	} else {
		$adr = $base + 1;
		Log3($name, 3, "PIFACE $name: set ports $val");
		readingsBeginUpdate($hash);
		for($i=0; $i<8; $i++){
			$j = 2**$i;
			$k = ($val & $j);
			$k = ($k) ? 1 : 0;
			$adr = 1 + $i;
			Log3($name, 3, "PIFACE $name: set port $adr $k");
			$adr += $base;
			$cmd = "/usr/local/bin/gpio -p write $adr $k";
			$cmd = `$cmd`;
			$j = $i + 1;
			readingsBulkUpdate($hash, 'out'.$j, $k);
		}
		readingsEndUpdate($hash, 1);
	}
	return "";
}

sub PIFACE_Get($@){
	my ($hash, @a)	= @_;
	my $name = $hash->{NAME};

	my $port = $a[1];
	my ($adr, $cmd, $pin, $pull, $val);

	my $usage = "Unknown argument $port, choose one of 0:noArg ".
				"1:noArg  2:noArg  3:noArg  4:noArg ".
				"5:noArg  6:noArg  7:noArg  8:noArg ".
				"11:noArg  12:noArg  13:noArg  14:noArg ".
				"15:noArg  16:noArg  17:noArg  18:noArg ".
				"21:noArg  22:noArg  23:noArg  24:noArg ".
				"25:noArg  26:noArg  27:noArg  28:noArg ";
	return $usage if $port eq "?";

	if ($port ~~ [11..18]) {
		Log3($name, 3, "PIFACE $name: get inports with internal pullups is DEPRECATED and may be removed in further versions!");
		# read single inport with pullup
		$pin  = $port - 10;
		$adr  = $base + $pin;
		$cmd = '/usr/local/bin/gpio -p mode '.$adr.' up';
		$val = `$cmd`;
		$cmd = '/usr/local/bin/gpio -p read '.$adr;
		$val = `$cmd`;
		readingsSingleUpdate($hash, 'in'.$port, $val, 1);
	} else {
		# read all inports and outports
		PI_read_allports($hash);
	}
	return "";
}

sub PI_read_allports($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my ($cmd, $val, $p, $pin, $v, $zeile, @ports);
	
	$cmd = '/usr/local/bin/gpio -p readall';
	$val = `$cmd`;
	@ports = split(/\n/, $val);

	foreach (@ports){
		$zeile = $_;
		$p = substr($zeile,  3, 3);
		$v = substr($zeile, 13, 1);
		if (substr($p,0,1) eq '2' && $p ~~ [200..207]){
			$pin = $p - 199;
			readingsSingleUpdate($hash, 'in'.$pin, $v, 1) if(ReadingsVal($name, 'in'.$pin, '') ne $v);
		} elsif (substr($p,0,1) eq '2' && $p ~~ [208..215]){
			$pin = $p - 207;
			readingsSingleUpdate($hash, 'out'.$pin, $v, 1) if(ReadingsVal($name, 'out'.$pin, '') ne $v);
		}
	}
	return;
}

1;

=pod
=begin html

<a name="PIFACE"></a>
<h3>PIFACE</h3>
<ul>

	<b>Prerequesits</b>
	<ul>
	
		<br/>
		Module needs wiringPi tools from <a href=http://wiringpi.com>http://wiringpi.com</a><br/><br/>
		<code>	git clone git://git.drogon.net/wiringPi<br/>
				cd wiringPi<br/>
				./build</code>
		<br/>

	</ul>
	<br/><br/>
	
	<a name="PIFACEdefine"></a>
	<b>Define</b>
	<ul>

		<br/>
		<code>define &lt;name&gt; PIFACE</code>
		<br/><br/>
		This module provides set/get functionality to control ports on RaspberryPi extension board PiFace
		<br/>

	</ul>
	<br/><br/>

	<a name="PIFACEset"></a>
	<b>Set-Commands</b><br/>
	<ul>

		<br/>
		<code>set &lt;name&gt; &lt;port&gt; &lt;value&gt;</code>
		<br/><br/>
		<ul>
			<li>set single port n to 1 (on) or 0 (off)<br/><br/>
				Examples:<br/>
				set &lt;name&gt; 3 1 =&gt; set port 3 on<br/>
				set &lt;name&gt; 5 0 =&gt; set port 5 off<br/></li>
			<br/>
			<li>set all ports in one command by bitmask<br/><br/>
				Example:<br/>
				set &lt;name&gt; 0 255 =&gt; set all ports on<br/>
				set &lt;name&gt; 0 0 =&gt; set all ports off<br/>
				set &lt;name&gt; 0 170 =&gt; bitmask(170) = 10101010 =&gt; set ports 2 4 6 8 on, ports 1 3 5 7 off<br/>
				<br/>
				<ul>
					<code>port 87654321<br/>
					bit&nbsp; 10101010</code>
				</ul></li>
		</ul>

	</ul>
	<br/><br/>

	<a name="PIFACEget"></a>
	<b>Get-Commands</b><br/>
	<ul>

		<br/>
		<code>get &lt;name&gt; &lt;port&gt;</code>
		<br/><br/>
		<ul>
			<li>get state of single input port with internal pullups <b>off</b><br/><br/>
				Example:<br/>
				get &lt;name&gt; 3 =&gt; get state of input port 3<br/></li>
			<br/>
			<li>get state of single input port with internal pullups <b>on</b><br/><br/>
				Add 10 to port number!<br/><br/>
				Example:<br/>
				get &lt;name&gt; 15 =&gt; get state of input port 5<br/></li>
			<li>get state of single output port with internal pullups <b>on</b><br/><br/>
				Add 20 to port number!<br/><br/>
				Example:<br/>
				get &lt;name&gt; 25 =&gt; get state of output port 5<br/>
				<b>Important:</b> reading with internal pullups is DEPRECATED and will be removed in further versions!<br/><br/></li>
			<li>get state of all input AND output ports and update readings.<br/>
				<b>Important:</b> in-ports are only read without pullup!<br/>
				Example:<br/>
				get &lt;name&gt; 0 =&gt; get state of all ports<br/></li>
		</ul>

	</ul>
	<br/><br/>

	<a name="PIFACEattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li><b>&lt;out1..out8&gt;</b> - state of output port 1..8</li>
		<li><b>&lt;in1..in8&gt;</b> - state of input port 1..8 without pullup resistor active</li>
		<li><b>&lt;in11..in18&gt;</b> - state of input port 1..8 with pullup resistor active</li>
	</ul>
	<br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>
		<li>Relays 1 and 2 have corresponding port 1 and 2</li>
		<li>Switches 1..4 have corresponding ports 1..4 and must be read with pullups on</li>
		<br/>
		<li>Have fun!</li><br/>

	</ul>

</ul>

=end html
=cut
