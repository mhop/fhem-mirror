# $Id$
##############################################################################
#
#	51_BBB_BMP180.pm
#
#	An FHEM Perl module to retrieve pressure data from a BMP085/BMP180
#	sensor connected to I2C bus
#
#	Copyright: betateilchen ®
#	e-mail   : fhem.development@betateilchen.de
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
##############################################################################

package main;

use strict;
use warnings;
use feature qw/say switch/;
use Time::HiRes qw(gettimeofday);

sub BBB_BMP180_Initialize($){
	my ($hash) = @_;
	$hash->{DefFn}		=	"BBB_BMP180_Define";
	$hash->{UndefFn}	=	"BBB_BMP180_Undefine";
	$hash->{GetFn}		=	"BBB_BMP180_Get";
	$hash->{AttrFn}		=	"BBB_BMP180_Attr";
	$hash->{NotifyFn}	=	"BBB_BMP180_Notify";
	$hash->{ShutdoenFn}	=	"BBB_BMP180_Shutdown";
	$hash->{AttrList}	=	"bbbRoundPressure:0,1 ".
							"bbbRoundTemperature:0,1 ".
							"bbbInterval ".
							$readingFnAttributes;
}

sub BBB_BMP180_Define($$){
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);
	Log3($name, 3, "BBB_BMP180 $name: created");
	readingsSingleUpdate($hash, "state", "active",1);

	$hash->{helper}{i2cbus} = '1';
	$hash->{helper}{i2cbus} = $a[2] if(defined($a[2]));

	# check sensor presence
	my $bmpTest = '/sys/bus/i2c/drivers/bmp085/'.$hash->{helper}{i2cbus}.'-0077/pressure0_input';
	return 'BBB_BMP180: sensor not found!' unless -e $bmpTest;
	$bmpTest = '/sys/bus/i2c/drivers/bmp085/'.$hash->{helper}{i2cbus}.'-0077/temp0_input';
	return 'BBB_BMP180: sensor not found!' unless -e $bmpTest;

	if( $init_done ) {
		delete $modules{openweathermap}->{NotifyFn};
		bbb_getValues($hash,0);
	} else {
		readingsSingleUpdate($hash, "state", "defined",1);
	}

	return undef;
}

sub BBB_BMP180_Undefine($$){
	my($hash, $name) = @_;
	RemoveInternalTimer($hash);
	return;
}

sub BBB_BMP180_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,4,"BBB_BMP180 $name: shutdown requested");
	return undef;
}

sub BBB_BMP180_Get($@){
	my ($hash, @a)	= @_;
	my $name = $hash->{NAME};
	my ($cmd) = $a[1];

	my $usage = "Unknown argument $cmd, choose one of readValues:noArg";
	return $usage if($cmd eq "?");

	given($cmd) {
	
		when("readValues") {
			bbb_getValues($hash,1);		
		}	
		
		default {return}
	}

	return;
}

sub BBB_BMP180_Attr($@){
	my @a = @_;
	my $hash = $defs{$a[1]};
	my (undef, $name, $attrName, $attrValue) = @a;
	given($attrName){
		when("bbbInterval"){
			RemoveInternalTimer($hash);
			my $next = gettimeofday()+$attrValue;
			InternalTimer($next, "bbb_getValues", $hash, 0);
			break;
			}

		default {$attr{$name}{$attrName} = $attrValue;}
	}
	return "";
}

sub BBB_BMP180_Notify($$) {
	my ($hash,$dev) = @_;

	if( grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}) ) {
		delete $modules{BBB_BMP180}->{NotifyFn};

		foreach my $d (keys %defs) {
			next if($defs{$d}{TYPE} ne "openweathermap");
			bbb_getValues($hash,0);
		}
	}
}

sub bbb_getValues($$){
	my ($hash,$local) = @_;
	my $name = $hash->{NAME};

	my $a  = AttrVal('global','altitude',undef);
	my $t  = bbb_temp($hash);
	my $pa = bbb_absDruck($hash);
	my $pr = bbb_relDruck($hash,$a) if(defined($a));

	if(AttrVal($name,'bbbRoundPressure',undef)){
		$pa	= sprintf("%.0f", $pa);
		$pr = sprintf("%.0f", $pr) if(defined($a));
	} else {
		$pa	= sprintf("%.2f", $pa);
		$pr = sprintf("%.2f", $pr) if(defined($a));
	}

	if(AttrVal($name,'bbbRoundTemperature',undef)){
		$t	= sprintf("%.0f", $t);
	} else {
		$t	= sprintf("%.1f", $t);
	}

	my $s	 = "T: $t P: $pa";
	$s		.= " P-nn: $pr" if(defined($a));

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'temperature', $t);
	readingsBulkUpdate($hash, 'pressure', $pa);
	readingsBulkUpdate($hash, 'pressure-nn', $pr) if(defined($a));
	readingsBulkUpdate($hash, 'state', $s) if(defined($a));
	readingsEndUpdate($hash, 1);

	my $next = gettimeofday()+AttrVal($name,'bbbInterval',300);
	InternalTimer($next, "bbb_getValues", $hash, 0) unless $local;

	return;
}

sub bbb_temp($){
	my ($hash) = @_;
	my $bmpT = '/sys/bus/i2c/drivers/bmp085/'.$hash->{helper}{i2cbus}.'-0077/temp0_input';
	my $temp;

	open (IN,"<$bmpT");
	while (<IN>){
		$temp = $_;
		last;
	}
	close IN;

	$temp = substr($temp,0,length($temp)-1);

	return $temp/10;
}

sub bbb_absDruck($){
	my ($hash) = @_;
	my $bmpP = '/sys/bus/i2c/drivers/bmp085/'.$hash->{helper}{i2cbus}.'-0077/pressure0_input';
	my $p;

	open (IN,"<$bmpP");
	while (<IN>){
		$p = $_;
		last;
	}
	close IN;

	$p = substr($p,0,length($p)-1);

	return $p/100;
}

sub bbb_relDruck($$){
	my($hash,$Alti) = @_;
	my $Pa   = bbb_absDruck($hash);
	my $Temp = bbb_temp($hash);

	# Konstanten
	my $g0 = 9.80665;
	my $R  = 287.05;
	my $T  = 273.15;
	my $Ch = 0.12;
	my $a  = 0.065;
	my $E  = 0;

	if($Temp < 9.1){
	   $E = 5.6402*(-0.0916 + exp(0.06 * $Temp));
	   }
	else {
	   $E = 18.2194*(1.0463 - exp(-0.0666 * $Temp));
	   }

	my $xp = $Alti * $g0 / ($R*($T+$Temp + $Ch*$E + $a*$Alti/2));
	my $Pr = $Pa*exp($xp);

	return $Pr;
}

1;

=pod
not to be translated
=begin html

<a name="BBB_BMP180"></a>
<h3>BBB_BMP180</h3>
<ul>

	<b>Prerequesits</b>
	<ul>
		<br/>
		Module was developed for use with Beaglebone Black.<br/><br/>
		To create the device, run the following command on system console:<br/><br/>
		<code>echo bmp085 0x77 > /sys/class/i2c-adapter/i2c-1/new_device</code><br/><br/>
		To check if successful:<br/><br/>
		<code>
			dmesg | grep bmp<br/>
			[   76.989945] i2c i2c-1: new_device: Instantiated device bmp085 at 0x77<br/>
			[   77.040606] bmp085 1-0077: Successfully initialized bmp085!<br/>
		</code>
		<br/>
	</ul>
	<br/><br/>
	
	<a name="BBB_BMP180define"></a>
	<b>Define</b>
	<ul>
		<br/>
		<code>define &lt;name&gt; BBB_BMP180 [bus]</code>
		<br/><br/>
		This module provides air pressure measurement by a BMP180 sensor connected to I2C bus.<br/>
		Optional parameter [bus] defines number of I2C-bus in your hardware (default = 1).<br/>
		<br/>
	</ul>
	<br/><br/>

	<a name="BBB_BMP180set"></a>
	<b>Set-Commands</b><br/>
	<ul>
		<br/>
		No set commands implemented.<br/>
		<br/>
	</ul>
	<br/><br/>

	<a name="BBB_BMP180get"></a>
	<b>Get-Commands</b><br/>
	<ul>
		<br/>
		<code>get &lt;name&gt; readValues</code>
		<br/><br/>
		<ul>
			Update all values immediately.
		</ul>
	</ul>
	<br/><br/>

	<a name="BBB_BMP180attr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><b>bbbInterval</b> - Interval for readings update (default = 300 seconds)</li>
		<li><b>bbbRoundPressure</b> - If set to 1 = pressure value will be presented without decimals (default = 2 decimals)</li>
		<li><b>bbbRoundTemperatue</b> - If set to 1 = temperature value will be presented without decimals (default = 1 decimal)</li>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li><b>temperature</b> - temperature at sensor</li>
		<li><b>pressure</b> - pressure (absolute)</li>
		<li><b>pressure-nn</b> - pressure (relative), global attribute altitude needed for calculation</li>
	</ul>
	<br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>
		<li>Have fun!</li><br/>
	</ul>

</ul>

=end html
=begin html_DE

<a name="BBB_BMP180"></a>
<h3>BBB_BMP180</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#BBB_BMP180'>BBB_BMP180</a><br/>
</ul>
=end html_DE
=cut
