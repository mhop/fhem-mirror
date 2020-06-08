# $Id$
####################################################################################################
#
#	44_TEK603.pm
#
#	Copyright: Stephan Eisler
#	Email: stephan@eisler.de 
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
use DevIo;

use Digest::CRC; # libdigest-crc-perl

sub TEK603_Initialize($);
sub TEK603_define($$);
sub TEK603_doInit($);
sub TEK603_undef($$);
sub TEK603_ready($);
sub TEK603_read($);
sub TEK603_reconnect($);


sub TEK603_Initialize($) {
	my ($hash) = @_;

	$hash->{ReadFn}		= 'TEK603_read';
	$hash->{ReadyFn}	= 'TEK603_ready';
	$hash->{DefFn}		= 'TEK603_define';
	$hash->{UndefFn}	= 'TEK603_undef';

	$hash->{AttrList}	= 'do_not_notify:0,1 dummy:1,0 disable:1,0 loglevel:0,1,2,3,4,5,6 ' .
				   $readingFnAttributes;
}

sub TEK603_define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	my $name = $a[0];
	my $dev = $a[2];

	$hash->{DEF} = $dev;

	my $msg = '';

	if( @a != 3) {
		$msg = 'wrong syntax: define <name> TEK603 {none | devicename | hostname:port}';
		Log3 $name, 3, $msg;
		return $msg;
	}

	DevIo_CloseDev($hash);
	$hash->{PORTSTATE} = $hash->{STATE};

	if($dev eq 'none') {
		Log3 $name, 3, "device is none, commands will be echoed only";
		$attr{$name}{dummy} = 1;
		return undef;
	}

	$hash->{DeviceName} = $dev;
	my $ret = DevIo_OpenDev($hash, 0, 'TEK603_doInit');

	return $ret;
}

sub TEK603_doInit($) {
	my ($hash) = @_;

	my $po = $hash->{USBDev};
	my $dev = $hash->{DeviceName};
	my $name = $hash->{NAME};

	return if (IsDisabled($name));

	# Wenn / enthalten ist ist es kein ser2net-Device, daher initialisieren
	if ($dev =~ m/\//)
	{
		# Parameter 115200, 8, 1, even, none
		$po->reset_error();
		$po->baudrate(115200);
		$po->databits(8);
		$po->stopbits(1);
		$po->parity('none');
		$po->handshake('none');
		$po->dtr_active(1);
		$po->rts_active(1);

		if (!$po->write_settings) {
			undef $po;
			$hash->{STATE} = $name . 'Error on write serial line settings on device ' . $dev;
			Log3 $name, 3, $hash->{STATE};
			return $hash->{STATE} . "\n";
		}
	}

	Log3 $name, 3, "connected to device $dev";
	$hash->{STATE} = 'open';
	$hash->{PORTSTATE} = $hash->{STATE};

	return undef;
}

sub TEK603_undef($$) {
	my ($hash, $name) = @_;

	foreach my $d (sort keys %defs) {
		if(defined($defs{$d}) && defined($defs{$d}{IODev}) && $defs{$d}{IODev} == $hash) {
			Log3 $name, 4, "deleting port for $d";
			delete $defs{$d}{IODev};
		}
	}

	DevIo_CloseDev($hash);
	$hash->{PORTSTATE} = $hash->{STATE};

	return undef;
}


sub TEK603_ready() {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return if (IsDisabled($name));
	return DevIo_OpenDev($hash, 1, 'TEK603_doInit') if($hash->{STATE} eq 'disconnected');

	# This is relevant for windows/USB only
	my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
	my $po = $hash->{USBDev};

	if ($po) {
		($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
		return ($InBytes > 0);
	}

	# Someone set us up the bomb
	Log3($hash->{NAME}, 1, qq[Can't read from $hash->{DeviceName}]);

	# disable device
	Log3($hash->{NAME}, 1, qq[Disabled device due read errors]);
	CommandAttr(undef, $hash->{NAME} . ' disable 1');
	return;
}

sub TEK603_read($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return if (IsDisabled($name));

	my $buf = DevIo_SimpleRead($hash);
	return '' if(!defined($buf));

	# convert to hex string
	$hash->{buffer} = unpack ('H*', $buf);

	my $lenght		= hex(substr($hash->{buffer},4,4))*2;
	#my $cmd            	= substr($hash->{buffer},8,2);
	#my $flags          	= substr($hash->{buffer},10,2);
	my $time 		= sprintf '%02d:%02d:%02d', hex(substr($hash->{buffer},12,2)), hex(substr($hash->{buffer},14,2)), hex(substr($hash->{buffer},16,2));
	#my $epromStart     	= hex(substr($hash->{buffer},18,4));
	#my $epromEnd       	= hex(substr($hash->{buffer},22,4));
	my $payloadlenght	= $lenght - 26 - 4;
	my $payload        	= substr($hash->{buffer},26,$payloadlenght);
	my $crc            	= substr($hash->{buffer},26 + $payloadlenght,4);

	my $ctx = Digest::CRC->new(width=>16, init=>0x0, poly=>0x1021, refout=>0, xorout=>0);
	$ctx->add(pack 'H*',(substr($hash->{buffer},0,26 + $payloadlenght)));
	my $digest = $ctx->hexdigest;
	return '' if($crc ne $digest);

	# payload
	my $temp                   = sprintf '%.2f', ((hex(substr($payload, 0,2)) - 40 - 32) / 1.8);
	my $Ullage         	       = hex(substr($payload,2,2)) * 256 + hex(substr($payload,4,2));
	my $RemainingUsableLevel   = hex(substr($payload,6,2)) * 256 + hex(substr($payload,8,2));
	my $TotalUsableCapacity    = hex(substr($payload,10,2)) * 256 + hex(substr($payload,12,2));

	return '' if($temp eq "-40.00" && $Ullage eq "0"); # TankLevel=NO_DATA

	# Calculations
	my $RemainingUsablePercent = round($RemainingUsableLevel / $TotalUsableCapacity * 100,01);

	#Log3 $name, 5, $hash->{buffer};
	Log3 $name, 5, "Time:$time Temp:$temp Ullage:$Ullage RemainingUsableLevel:$RemainingUsableLevel RemainingUsablePercent:$RemainingUsablePercent TotalUsableCapacity:$TotalUsableCapacity";

    	readingsBeginUpdate($hash);
    	readingsBulkUpdate($hash, "Time", $time);
    	readingsBulkUpdate($hash, "Temperature", $temp);
    	readingsBulkUpdate($hash, "Ullage", $Ullage);
    	readingsBulkUpdate($hash, "RemainingUsableLevel", $RemainingUsableLevel);
    	readingsBulkUpdate($hash, "RemainingUsablePercent", $RemainingUsablePercent);
    	readingsBulkUpdate($hash, "TotalUsableCapacity", $TotalUsableCapacity);
    	readingsEndUpdate($hash, 1);
}


sub TEK603_reconnect($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 3, "Wrong Data received. We reconnect Device";

	# Sometime the device sends a lot of waste and we must reconnect.
	DevIo_CloseDev($hash);
	$hash->{PORTSTATE} = $hash->{STATE};

	select(undef, undef, undef, 0.1);
	DevIo_OpenDev($hash, 0, 'TEK603_doInit');
}


1;

=pod
=item summary devices communicating with TEK603
=begin html

<a name="TEK603"></a>
<h3>TEK603</h3>
<ul>
    The TEK603 is a fhem module for the Tekelek TEK603 Eco Monitor a liquid level monitor designed for residential and small commercial applications.
    It works in conjunction with a TEK653 Sonic transmitter mounted on the top of the tank.


  <br /><br /><br />
  <b>Prerequisites</b><br>
  The module requires the perl module Digest::CRC<br />
  On a debian based system the module can be installed with<br />
  <code>
  sudo apt-get install libdigest-crc-perl<br />
  </code>
  <br /><br />

  <a name="TEK603_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TEK603 /dev/ttyUSBx</code><br />
    <br />

    Defines an TEK603 Eco Monitor device connected to USB.<br /><br />

    Examples:
    <ul>
      <code>define OelTank TEK603 /dev/ttyUSB0</code><br />
    </ul>
    <br />
    <br />
    <code>define &lt;name&gt; TEK603 hostnameorip:port</code><br />
    <br />

    Defines an TEK603 Eco Monitor device via ethernet on a remote host running ser2net.<br /><br />

    Examples:
    <ul>
      <code>define OelTank TEK603 somehost:23000</code><br />
    </ul>
  </ul><br />

  <a name="TEK603_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>Time<br />
    TEK603 internal Time</li>
    <li>Temperature<br />
    Sensor Temperature</li>
    <li>Ullage<br />
    Sensor Measured Ullage</li>
    <li>RemainingUsableLevel<br />
    This is the usable level, with deductions due to the sensor offset and outlet height. (Liters)</li>
    <li>RemainingUsablePercent<br />
    This is the usable level in percent (calculated from RemainingUsableLevel and TotalUsableCapacity)</li>
    <li>TotalUsableCapacity<br />
    This is the usable volume, with deductions due to the sensor offset and outlet height. (Liters)</li>
  </ul><br />


</ul><br />

=end html

=cut

