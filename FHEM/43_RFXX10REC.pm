#################################################################################
# 43_RFXX10REC.pm
# Modul for FHEM for 
# - X10 security messages for 
#               - ds10a: X10 Door / Window Sensor or compatible devices
#               - ss10a: X10 motion sensor
#               - sd90: Marmitek smoke detector
#		- kr18: X10 remote control
# - X10 light messages for
#		- ms14a: motion sensor
#		- x10: generic X10 sensor
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##################################
#
# Special thanks to RFXCOM, http://www.rfxcom.com/, for their
# help. I own an USB-RFXCOM-Receiver (433.92MHz, USB, order code 80002)
# and highly recommend it.
#
##################################
#
# Some code from X10security code is derived from http://www.xpl-perl.org.uk/.
#       xpl-perl/lib/xPL/RF/X10Security.pm:
# Thanks a lot to Mark Hindess who wrote xPL.
#
#SEE ALSO
# Project website: http://www.xpl-perl.org.uk/
# AUTHOR: Mark Hindess, soft-xpl-perl@temporalanomaly.com
#
#Copyright (C) 2007, 2009 by Mark Hindess
#
#This library is free software; you can redistribute it and/or modify
#it under the same terms as Perl itself, either Perl version 5.8.7 or,
#at your option, any later version of Perl 5 you may have available.
#
##################################
#
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
# $Id$
package main;

use strict;
use warnings;

# Debug this module? YES = 1, NO = 0
my $RFXX10REC_debug = 0;

my $time_old = 0;

my $RFXX10REC_type_default = "ds10a";
my $RFXX10REC_X10_type_default = "x10";

my $DOT = q{_};

sub
RFXX10REC_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^(20|29).*";
  $hash->{DefFn}     = "RFXX10REC_Define";
  $hash->{UndefFn}   = "RFXX10REC_Undef";
  $hash->{ParseFn}   = "RFXX10REC_Parse";
  $hash->{AttrList}  = "IODev ignore:1,0 do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";
#Log 1, "RFXX10REC: Initialize";

}

#####################################
sub
RFXX10REC_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $a = int(@a);

  if(int(@a) != 5 && int(@a) != 7) {
	Log 1,"RFXX10REC wrong syntax '@a'. \nCorrect syntax is  'define <name> RFXX10REC <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]'";
	return "wrong syntax: define <name> RFXX10REC <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]";
  }
	

  my $name = $a[0];

  my $type = lc($a[2]);
  my $deviceid = $a[3];
  my $devicelog = $a[4];


  my $device_name = "RFXX10REC".$DOT.$deviceid;

  if ($type ne "ds10a" && $type ne "sd90" && $type ne "x10" && $type ne "ms10a" && $type ne "ms14a" && $type ne "kr18") {
  	Log 1,"RFX10SEC define: wrong type: $type";
  	return "RFX10SEC: wrong type: $type";
  }

  $hash->{RFXX10REC_deviceid} = $deviceid;
  $hash->{RFXX10REC_devicelog} = $devicelog;
  $hash->{RFXX10REC_type} = $type;
  #$hash->{RFXX10REC_CODE} = $deviceid;
  $modules{RFXX10REC}{defptr}{$device_name} = $hash;


  if (int(@a) == 7) {
	# there is a second deviceid:
	#
  	my $deviceid2 = $a[5];
  	my $devicelog2 = $a[6];

  	my $device_name2 = "RFXX10REC".$DOT.$deviceid2;

  	$hash->{RFXX10REC_deviceid2} = $deviceid2;
  	$hash->{RFXX10REC_devicelog2} = $devicelog2;
  	#$hash->{RFXX10REC_CODE2} = $deviceid2;
  	$modules{RFXX10REC}{defptr2}{$device_name2} = $hash;
  }

  AssignIoPort($hash);

  return undef;
}

#####################################
sub
RFXX10REC_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{RFXX10REC}{defptr}{$name});
  return undef;
}


#####################################
sub RFXX10REC_parse_X10 {
  my $bytes = shift;


  # checksum test
  (($bytes->[0]^0xff) == $bytes->[1] && ($bytes->[2]^0xff) == $bytes->[3])
    or return "";

  #RFXX10REC_reverse_bits($bytes);

  my %x10_devname =
    (
	0x60 => "A",
	0x70 => "B",
	0x40 => "C",
	0x50 => "D",
	0x80 => "E",
	0x90 => "F",
	0xA0 => "G",
	0xB0 => "H",
	0xE0 => "I",
	0xF0 => "J",
	0xC0 => "K",
	0xD0 => "L",
	0x00 => "M",
	0x10 => "N",
	0x20 => "O",
	0x30 => "P",
  );

  my $dev_first = "?";

  my $devnr = $bytes->[0] & 0xf0;
  if (exists $x10_devname{$devnr}) {
  	$dev_first = $x10_devname{$devnr};
  }

  my $unit_bit0 = ($bytes->[2] & 0x10) ? 1 : 0;
  my $unit_bit1 = ($bytes->[2] & 0x08) ? 1 : 0;
  my $unit_bit2 = ($bytes->[2] & 0x40) ? 1 : 0;
  my $unit_bit3 = ($bytes->[0] & 0x04) ? 1 : 0;
  my $unit = $unit_bit0 * 1 + $unit_bit1 * 2 + $unit_bit2 * 4 +$unit_bit3 * 8 + 1;

  my $device = sprintf '%s%0d', $dev_first, $unit;

  my $data = $bytes->[2];
  my $hexdata = sprintf '%02x', $bytes->[2];
  my $error;
  if ($data == 0x98) {
	$error = "RFXX10REC: X10 command 'Dim' not implemented, device=".$dev_first;
	Log 1,$error;
       	return $error;
  } elsif ($data == 0x88) {
	$error = "RFXX10REC: X10 command 'Bright' not implemented, device=".$dev_first;
	Log 1,$error;
       	return $error;
  } elsif ($data == 0x90) {
	$error = "RFXX10REC: X10 command 'All Lights on' not implemented, device=".$dev_first;
	Log 1,$error;
       	return $error;
  } elsif ($data == 0x80) {
	$error = "RFXX10REC: X10 command 'All Lights off' not implemented, device=".$dev_first;
	Log 1,$error;
       	return $error;
  }
  my $command;
  if ($data & 0x20) {
	$command = "off";
  } else {
	$command = "on";
  }

  my @res;
  my $current = "";

  #--------------
  my $device_name = "RFXX10REC".$DOT.$device;
  #Log 1, "RFXX10REC: device_name=$device_name command=$command" if ($RFXX10REC_debug == 1);

  my $firstdevice = 1;
  my $def = $modules{RFXX10REC}{defptr}{$device_name};
  if(!$def) {
	#Log 1, "-1- not device_name=$device_name";
  	$firstdevice = 0;
	$def = $modules{RFXX10REC}{defptr2}{$device_name};
	if (!$def) {
		#Log 1, "-2- not device_name=$device_name";
        	Log 3, "RFXX10REC: RFXX10REC Unknown device $device_name, please define it";
        	return "UNDEFINED $device_name RFXX10REC $RFXX10REC_X10_type_default $device Unknown";
	}
  }

  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  Log 1, "RFXX10REC: $name devn=$device_name first=$firstdevice type=$command, cmd=$hexdata" if ($RFXX10REC_debug == 1);

  my $n = 0;
  my $tm = TimeNow();
  my $val = "";

  my $device_type = $def->{RFXX10REC_type};
  #Log 1,"device_name=$device_name name=$name, type=$type";

  my $sensor = "";

  if ($device_type eq "ms14a") {
	# for ms14a behave like x11, but flip second deviceid
	$device_type = "x10";
  	if ($firstdevice == 1) {
		$command = ($command eq "on") ? "alert" : "normal" ;
	} else {	
		$command = ($command eq "on") ? "off" : "on" ;	
	}
  }

  if ($device_type eq "x10") {

	$current = $command;

	$sensor = $firstdevice == 1 ? $def->{RFXX10REC_devicelog} : $def->{RFXX10REC_devicelog2};
	$val .= $current;
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;
  } else {
  	Log 1, "RFXX10REC: X10 error unknown sensor type=$device_type $name devn=$device_name first=$firstdevice type=$command, user=$device (hex $hexdata)";
        return "RFXX10REC X10 error unknown sensor type=$device_type for $device_name device=$device";
  }

  if (($firstdevice == 1) && $val) {
  	$def->{STATE} = $val;
  	$def->{TIME} = $tm;
  	$def->{CHANGED}[$n++] = $val;
  }

  DoTrigger($name, undef);

  return "";
}

#####################################
sub RFXX10REC_parse_X10Sec {
  my $bytes = shift;


  # checksum test
  (($bytes->[0]^0x0f) == $bytes->[1] && ($bytes->[2]^0xff) == $bytes->[3])
    or return "";

  #RFXX10REC_reverse_bits($bytes);

  #my $device = sprintf 'x10sec%02x', $bytes->[0];
  my $device = sprintf '%02x%02x', $bytes->[4], $bytes->[0];
  #Log 1, "X10Sec device-nr=$device";
  my $short_device = $bytes->[0];
  my $data = $bytes->[2];

  my $hexdata = sprintf '%02x', $bytes->[2];
  #Log 1, "X10Sec data=$hexdata";

  my %x10_security =
    (
	0x00 => ['X10Sec', 'alert', 'max_delay', 'batt_ok'],
	0x01 => ['X10Sec', 'alert', 'max_delay', 'batt_low'],
	0x04 => ['X10Sec', 'alert', 'min_delay', 'batt_ok'],
	0x05 => ['X10Sec', 'alert', 'min_delay', 'batt_low'],
	0x80 => ['X10Sec', 'normal', 'max_delay', 'batt_ok'],
	0x81 => ['X10Sec', 'normal', 'max_delay', 'batt_low'],
	0x84 => ['X10Sec', 'normal', 'min_delay', 'batt_ok'],  
	0x85 => ['X10Sec', 'normal', 'min_delay', 'batt_low'],
	0x26 => ['X10Sec', 'alert', '', ''],
	#
	0x0c => ['X10Sec', 'alert', '', 'batt_ok'],  # MS10a
	0x0d => ['X10Sec', 'alert', '', 'batt_low'], # MS10a
	0x8c => ['X10Sec', 'normal', '', 'batt_ok'], # MS10a
	0x8d => ['X10Sec', 'normal', '', 'batt_low'], # MS10a
	#
	0x06 => ['X10Sec', 'Security-Arm', '', ''], # kr18
	0x86 => ['X10Sec', 'Security-Disarm', '', ''], # kr18
	0x42 => ['X10Sec', 'ButtonA-on', '', ''], # kr18
	0xc2 => ['X10Sec', 'ButtonA-off', '', ''], # kr18
	0x46 => ['X10Sec', 'ButtonB-on', '', ''], # kr18
	0xc6 => ['X10Sec', 'ButtonB-off', '', ''], # kr18

    );

  my $command = "";
  my $type = "";
  my $delay = "";
  my $battery = "";

  my @res;
  my %args;
  if (exists $x10_security{$data}) {

    my $rec = $x10_security{$data};
    if (ref $rec) {
      ($type, $command, $delay, $battery) = @$rec;
    } else {
      $command = $rec;
    }

  } else {
    Log 1, "RFXX10REC undefined command cmd=$data device-nr=$device, hex=$hexdata";
    return "RFXX10REC undefined command";
  }

  my $current = "";

  #--------------
  my $device_name = "RFXX10REC".$DOT.$device;
  #Log 1, "device_name=$device_name";
  Log 4, "device_name=$device_name";


  my $firstdevice = 1;
  my $def = $modules{RFXX10REC}{defptr}{$device_name};
  if(!$def) {
	#Log 1, "-1- not device_name=$device_name";
  	$firstdevice = 0;
	$def = $modules{RFXX10REC}{defptr2}{$device_name};
	if (!$def) {
	#Log 1, "-2- not device_name=$device_name";
        	Log 3, "RFXX10REC: RFXX10REC Unknown device $device_name, please define it";
        	return "UNDEFINED $device_name RFXX10REC $RFXX10REC_type_default $device Window";
	}
  }

  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  #Log 1, "name=$new_name";
  return "" if(IsIgnored($name));

  Log 1, "RFXX10REC: $name devn=$device_name first=$firstdevice type=$command, delay=$delay, batt=$battery cmd=$hexdata" if ($RFXX10REC_debug == 1);

  my $n = 0;
  my $tm = TimeNow();
  my $val = "";

  my $device_type = $def->{RFXX10REC_type};
  #Log 1,"device_name=$device_name name=$name, type=$type";

  my $sensor = "";

  if ($device_type eq "ds10a") {


	$current = "Error";
	$current = "Open" if ($command eq "alert");
	$current = "Closed" if ($command eq "normal");

	$sensor = $def->{RFXX10REC_devicelog};
	$val .= $current;
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

	if (($def->{STATE} ne $val)) {
		$sensor = "statechange";
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;		
	}

	if ($battery ne '') {
		$sensor = "battery";
		$current = "Error";
		$current = "ok" if ($battery eq "batt_ok");
		$current = "low" if ($battery eq "batt_low");
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;
	}

	if ($delay ne '') {
		$sensor = "delay";
		$current = "Error";
		$current = "min" if ($delay eq "min_delay");
		$current = "max" if ($delay eq "max_delay");
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;
	}

  } elsif ($device_type eq "sd90") {


	$sensor = $firstdevice == 1 ? $def->{RFXX10REC_devicelog} : $def->{RFXX10REC_devicelog2};

	$current = $command;

	if ($firstdevice == 1) {
		$val .= $current;
	}
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

	if ($battery) {
		$sensor = "battery";
		$current = "Error";
		$current = "ok" if ($battery eq "batt_ok");
		$current = "low" if ($battery eq "bat_low");
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;
	}

	# sd90 does not have a delay switch
	if (0 && $delay) {
		$sensor = "delay";
		$current = "Error";
		$current = "min" if ($delay eq "min_delay");
		$current = "max" if ($delay eq "max_delay");
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;
	}

  } elsif ($device_type eq "ms10a") {

	$current = $command;

	$sensor = $def->{RFXX10REC_devicelog};
	$val .= $current;
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

	if (($def->{STATE} ne $val)) {
		$sensor = "statechange";
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;		
	}

	if ($battery ne '') {
		$sensor = "battery";
		$current = "Error";
		$current = "ok" if ($battery eq "batt_ok");
		$current = "low" if ($battery eq "batt_low");
  		$def->{READINGS}{$sensor}{TIME} = $tm;
  		$def->{READINGS}{$sensor}{VAL} = $current;
  		$def->{CHANGED}[$n++] = $sensor . ": " . $current;
	}

  } elsif ($device_type eq "kr18") {

	$current = $command;

	#$sensor = $def->{RFXX10REC_devicelog};
	$val = $current;
  	#$def->{READINGS}{$sensor}{TIME} = $tm;
  	#$def->{READINGS}{$sensor}{VAL} = $current;
  	#$def->{CHANGED}[$n++] = $sensor . ": " . $current;

	my @cmd_split = split(/-/, $command);
	$sensor = $cmd_split[0];
	$current = $cmd_split[1];
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

  } else {
  	Log 1, "RFXX10REC: error unknown sensor type=$device_type $name devn=$device_name first=$firstdevice type=$command, user=$device, delay=$delay, batt=$battery (hex $hexdata)";
        return "RFXX10REC error unknown sensor type=$device_type for $device_name device=$device";
  }

  if (($firstdevice == 1) && $val) {
  	$def->{STATE} = $val;
  	$def->{TIME} = $tm;
  	$def->{CHANGED}[$n++] = $val;
  }

  DoTrigger($name, undef);

  return "";
}


sub
RFXX10REC_Parse($$)
{
  my ($hash, $msg) = @_;

  my $time = time();
  if ($time_old ==0) {
  	Log 5, "RFXX10REC: decoding delay=0 hex=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFXX10REC: decoding delay=$time_diff hex=$msg";
  }
  $time_old = $time;

  # convert to binary
  my $bin_msg = pack('H*', $msg);

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($bin_msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $bits = ord($bin_msg);
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }

  my $res = "";
  if ($bits == 41) {
	Log 1, "RFXX10REC: bits=$bits num_bytes=$num_bytes hex=$msg" if ($RFXX10REC_debug == 1);
        $res = RFXX10REC_parse_X10Sec(\@rfxcom_data_array);
  	Log 1, "RFXX10REC: unsupported hex=$msg" if ($res ne "" && $res !~ /^UNDEFINED.*/);
	return $res;
  } elsif ($bits == 32) {
	Log 1, "RFXX10REC: bits=$bits num_bytes=$num_bytes hex=$msg" if ($RFXX10REC_debug == 1);
        $res = RFXX10REC_parse_X10(\@rfxcom_data_array);
  	Log 1, "RFXX10REC: unsupported hex=$msg" if ($res ne "" && $res !~ /^UNDEFINED.*/);
	return $res;
  } else {
	Log 0, "RFXX10REC: bits=$bits num_bytes=$num_bytes hex=$msg";
  }

  return "";
}

1;

=pod
=begin html

<a name="RFXX10REC"></a>
<h3>RFXX10REC</h3>
<ul>
  The RFXX10REC module interprets X10 security and X10 lighting messages received by a RFXCOM RF receiver. Reported also to work with KlikAanKlikUit. You need to define an RFXCOM receiver first.
  See <a href="#RFXCOM">RFXCOM</a>.

  <br><br>

  <a name="RFXX10RECdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RFXX10REC &lt;type&gt; &lt;deviceid&gt; &lt;devicelog&gt; [&lt;deviceid&gt; &lt;devicelog&gt;] </code> <br>
    <br>
    <code>&lt;type&gt;</code>
    <ul>
      specifies the type of the X10 device: <br>
    X10 security devices:
        <ul>
          <li> <code>ds10a</code> (X10 security ds10a Door/Window Sensor or compatible devices. This device type reports the status of the switch [Open/Closed], status of the delay switch [min|max]], and battery status [ok|low].)</li>
          <li> <code>ms10a</code> (X10 security ms10a motion sensor. This device type reports the status of motion sensor  [normal|alert] and battery status [ok|low].))</li>
          <li> <code>sd90</code> (Marmitek sd90 smoke detector. This device type reports the status of the smoke detector [normal|alert] and battery status [ok|low].)</li>
          <li> <code>kr18</code> (X10 security remote control. Report the Reading "Security" with values [Arm|Disarm], "ButtonA" and "ButtonB" with values [on|off] )</li>
        </ul>
    X10 lighting devices:
        <ul>
          <li> <code>ms14a</code> (X10 motion sensor. Reports [normal|alert] on the first deviceid (motion sensor) and [on|off] for the second deviceid (light sensor)) </li>
          <li> <code>x10</code> (All other x10 devices. Report [on|off] on both deviceids.)</li>
        </ul>
    </ul>
    <br>
    <code>&lt;deviceid&gt;</code>
    <ul>
    specifies the first device id of the device. X10 security have a a 16-Bit device id which has to be written as a hex-string (example "5a54").
    A X10 lighting device has a house code A..P followed by a unitcode 1..16 (example "B1").
    </ul>
    <br>
    <code>&lt;devicelog&gt;</code>
    <ul>
    is the name of the Reading used to report. Suggested: "Window" or "Door" for ds10a, "motion" for motion sensors, "Smoke" for sd90.
    </ul>
    <br>
    <code>&lt;deviceid2&gt;</code>
    <ul>
    is optional and specifies the second device id of the device if it exists. For example sd90 smoke sensors can be configured to report two device ids. ms14a motion sensors report motion status on the first deviceid and the status of the light sensor on the second deviceid.
    </ul>
    <br>
    <code>&lt;devicelog2&gt;</code>
    <ul>
    is optional for the name used for the Reading of <code>&lt;deviceid2&gt;</code>.
    </ul>
    <br>
      Example: <br>
    <code>define livingroom_window RFXX10REC ds10a 72cd Window</code>
      <br>
    <code>define motion_sensor1 RFXX10REC ms10a 55c6 motion</code>
      <br>
    <code>define smoke_sensor1 RFXX10REC sd90 54d3 Smoke 54d3 Smoketest</code>
      <br>
    <code>define motion_sensor2 RFXX10REC ms14a A1 motion A2 light</code>
      <br>
  </ul>
  <br>

  <a name="RFXX10RECset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="RFXX10RECget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="RFXX10RECattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
  </ul>
</ul>

=end html
=cut
