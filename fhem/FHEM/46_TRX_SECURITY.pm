# $Id$
##############################################################################
#
#     46_TRX_SECURITY.pm
#     FHEM module for X10, KD101, Visonic
#
#     Copyright (C) 2012/2013 Willi Herzig
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#
#
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
package main;

use strict;
use warnings;

# Debug this module? YES = 1, NO = 0
my $TRX_SECURITY_debug = 0;

my $time_old = 0;
my $trx_rssi;

my $TRX_SECURITY_type_default = "ds10a";

my $DOT = q{_};

my %security_device_codes = (	# HEXSTRING => "NAME", "name of reading", 
	# 0x20: X10, KD101, Visonic, Meiantech
	0x2000 => [ "DS10A", "Window" ],
	0x2001 => [ "MS10A", "motion" ],
	0x2002 => [ "KR18", "key" ],
	0x2003 => [ "KD101", "smoke" ],
	0x2004 => [ "VISONIC_WINDOW", "window" ],
	0x2005 => [ "VISONIC_REMOTE", "key" ],
	0x2006 => [ "VISONIC_WINDOW", "window" ],
	0x2007 => [ "Meiantech", "alarm" ],
);

my %security_device_commands = (	# HEXSTRING => commands
	# 0x20: X10, KD101, Visonic, Meiantech
	0x2000 => [ "Closed", "", "Open", "", "", "", ""], # DS10A
	0x2001 => [ "", "", "", "", "alert", "normal", ""], # MS10A
	0x2002 => [ "", "", "", "", "", "", "Panic", "EndPanic", "", "Arm_Away", "Arm_Away_Delayed", "Arm_Home", "Arm_Home_Delayed", "Disarm"], # KR18
	0x2003 => [ "", "", "", "", "", "", "alert", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "pair",], # KD101
);

my %security_device_c2b;        # DEVICE_TYPE->hash (reverse of security_device_codes)

#####################################
sub
TRX_SECURITY_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %security_device_codes) {
    $security_device_c2b{$security_device_codes{$k}->[0]} = $k;
  }

  $hash->{Match}     = "^..(20).*";
  $hash->{SetFn}     = "TRX_SECURITY_Set";
  $hash->{DefFn}     = "TRX_SECURITY_Define";
  $hash->{UndefFn}   = "TRX_SECURITY_Undef";
  $hash->{ParseFn}   = "TRX_SECURITY_Parse";
  $hash->{AttrList}  = "IODev ignore:1,0 do_not_notify:1,0 ".
                       $readingFnAttributes;

}

###################################
sub
TRX_SECURITY_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 3);

  # look for device_type

  my $name = $a[0];
  my $command = $a[1];
  my $level;

  if ($na == 3) {
  	$level = $a[2];
  } else {
	$level = 0;
  }

  my $device_type = $hash->{TRX_SECURITY_type};
  my $deviceid = $hash->{TRX_SECURITY_deviceid};

  if ($device_type ne "KD101" && $device_type ne "DS10A" && $device_type ne "MS10A" && $device_type ne "KR18") {
	return "No set implemented for $device_type";	
  }

  my $device_type_num = $security_device_c2b{$device_type};
  if(!defined($device_type_num)) {
	return "Unknown device_type, choose one of " .
                                join(" ", sort keys %security_device_c2b);
  }
  my $protocol_type = $device_type_num >> 8; # high bytes

  # Now check if the command is valid and retrieve the command id:
  my $rec = $security_device_commands{$device_type_num};
  my $i;
  for ($i=0; $i <= $#$rec && ($rec->[$i] ne $command); $i++) { ;}

  if($i > $#$rec) {
	my $l = join(" ", sort @$rec); 
	if ($device_type eq "AC" || $device_type eq "HOMEEASY" || $device_type eq "ANSLUT") {
  		$l =~ s/ level / level:slider,0,1,15 /; 
	}
  	my $error = "Unknown command $command, choose one of $l"; 

	Log3 $name, 1, "TRX_SECURITY_Set() ".$error if ($command ne "?" );
	return $error;
  }

  if ($na == 4 && $command ne "level") {
	my $error = "Error: level not possible for command $command";
  }

  my $seqnr = 0;
  my $cmnd = $i;

  my $hex_prefix;
  my $hex_command;
  if ($protocol_type == 0x20) {
  	my $id1;
  	my $id2;
  	my $id3;
  	if ($deviceid =~ /^(..)(..)$/) {
		$id1 = $2;
		$id2 = "00";
		$id3 = $1;
  	} elsif ($deviceid =~ /^(..)(..)(..)$/) {
                $id1 = $1;
                $id2 = $2;
                $id3 = $3;
  	} else {
		Log3 $name, 1,"TRX_SECURITY_Set() lightning1 wrong deviceid: name=$name device_type=$device_type, deviceid=$deviceid";
		return "error set name=$name  deviceid=$deviceid";
  	}

	# lightning1
  	$hex_prefix = sprintf "0820";
  	$hex_command = sprintf "%02x%02x%02s%02s%02s%02x00", $device_type_num & 0xff, $seqnr, $id1, $id2, $id3, $cmnd; 
  	Log3 $name, 1,"TRX_SECURITY_Set() name=$name device_type=$device_type, deviceid=$deviceid id1=$id1, id2=$id2, id3=$id3, command=$command";
  	Log3 $name, 5,"TRX_SECURITY_Set() hexline=$hex_prefix$hex_command";

  	if ($device_type ne "KD101") {
	  	my $sensor = "";

  		readingsBeginUpdate($hash);

		# Now set the statechange:
	  	if ($hash->{STATE} ne $command) { 
			$sensor = "statechange";
			readingsBulkUpdate($hash, $sensor, $command);
  		}

		# Now set the devicelog:
	  	$sensor = $hash->{TRX_SECURITY_devicelog};
		if ($sensor ne "none") { readingsBulkUpdate($hash, $sensor, $command); }

		# Set battery
	  	$sensor = "battery";
		readingsBulkUpdate($hash, $sensor, "ok");

  		readingsEndUpdate($hash, 1);
	}

  } else {
	return "No set implemented for $device_type . Unknown protocol type";	
  }

  IOWrite($hash, $hex_prefix, $hex_command);

  my $tn = TimeNow();
  $hash->{CHANGED}[0] = $command;
  $hash->{STATE} = $command;
  $hash->{READINGS}{state}{TIME} = $tn;
  $hash->{READINGS}{state}{VAL} = $command;

  return $ret;
}

#####################################
sub
TRX_SECURITY_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $a = int(@a);

  if(int(@a) != 5 && int(@a) != 7) {
	Log3 $hash, 1,"TRX_SECURITY_Define() wrong syntax '@a'. \nCorrect syntax is  'define <name> TRX_SECURITY <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]'";
	return "wrong syntax: define <name> TRX_SECURITY <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]";
  }
	

  my $name = $a[0];

  my $type = lc($a[2]);
  my $deviceid = $a[3];
  my $devicelog = $a[4];


  $type = uc($type);

  my $my_type;
  if ($type eq "WD18" || $type eq "GD18" ) {
	$my_type = "DS10A"; # device will be received as DS10A	
  } else {
	$my_type = $type;
  }
  my $device_name = "TRX".$DOT.$my_type.$DOT.$deviceid;

  if ($type ne "DS10A" && $type ne "SD90" && $type ne "MS10A" && $type ne "MS14A" && $type ne "KR18" && $type ne "KD101" && $type ne "VISONIC_WINDOW" & $type ne "VISONIC_MOTION" & $type ne "VISONIC_REMOTE" && $type ne "GD18" && $type ne "WD18") {
  	Log3 $hash, 1,"TRX_SECURITY_Define() wrong type: $type";
  	return "TRX_SECURITY: wrong type: $type";
  }

  $hash->{TRX_SECURITY_deviceid} = $deviceid;
  $hash->{TRX_SECURITY_devicelog} = $devicelog;
  $hash->{TRX_SECURITY_type} = $type;
  #$hash->{TRX_SECURITY_CODE} = $deviceid;
  $modules{TRX_SECURITY}{defptr}{$device_name} = $hash;


  if (int(@a) == 7) {
	# there is a second deviceid:
	#
  	my $deviceid2 = $a[5];
  	my $devicelog2 = $a[6];

  	my $device_name2 = "TRX_SECURITY".$DOT.$deviceid2;

  	$hash->{TRX_SECURITY_deviceid2} = $deviceid2;
  	$hash->{TRX_SECURITY_devicelog2} = $devicelog2;
  	#$hash->{TRX_SECURITY_CODE2} = $deviceid2;
  	$modules{TRX_SECURITY}{defptr2}{$device_name2} = $hash;
  }

  AssignIoPort($hash);

  return undef;
}

#####################################
sub
TRX_SECURITY_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{TRX_SECURITY}{defptr}{$name});
  return undef;
}



#####################################
sub TRX_SECURITY_parse_X10Sec($$) {
  my ($hash, $bytes) = @_;

  my $error;

  my $subtype = $bytes->[1];

  my $device;
  if ($subtype >= 3) {
	$device = sprintf '%02x%02x%02x', $bytes->[3], $bytes->[4], $bytes->[5];
  } else {
	# that's how we do it on 43_RFXX10REC.pm
	$device = sprintf '%02x%02x', $bytes->[5], $bytes->[3];
  }

  my %security_devtype =
    (	# HEXSTRING => 
	0x00 => [ "DS10A", "Window" ], 			# X10 security door/window sensor
	0x01 => [ "MS10A", "motion" ], 			# X10 security motion sensor
	0x02 => [ "KR18", "key" ],			# X10 security remote (no alive packets)
	0x03 => [ "KD101", "smoke" ],			# KD101 (no alive packets)
	0x04 => [ "VISONIC_WINDOW", "window" ],	# Visonic PowerCode door/window sensor – primary contact (with alive packets)
	0x05 => [ "VISONIC_MOTION", "motion" ],	# Visonic PowerCode motion sensor (with alive packets)
	0x06 => [ "VISONIC_REMOTE", "key" ],	# Visonic CodeSecure (no alive packets)
	0x07 => [ "VISONIC_WINDOW", "window" ],	# Visonic PowerCode door/window sensor – auxiliary contact (no alive packets)
  );

  my $dev_type;
  my $dev_reading;
  if (exists $security_devtype{$subtype}) {
    my $rec = $security_devtype{$subtype};
    if (ref $rec) {
      ($dev_type, $dev_reading ) = @$rec;
    } else {
	$error = "TRX_SECURITY: x10_devtype wrong for subtype=$subtype";
	Log3 $hash, 1, "TRX_SECURITY_parse_X10Sec() ".$error;
  	return "";
    }
  } else {
 	$error = "TRX_SECURITY: error undefined subtype=$subtype";
	Log3 $hash, 1, "TRX_SECURITY_parse_X10Sec() ".$error;
  	return "";
  }

  #--------------
  my $device_name = "TRX".$DOT.$dev_type.$DOT.$device;
  Log3 $hash, 5, "TRX_SECURITY_parse_X10Sec() device_name=$device_name";

  my $firstdevice = 1;
  my $def = $modules{TRX_SECURITY}{defptr}{$device_name};
  if(!$def) {
  	$firstdevice = 0;
	$def = $modules{TRX_SECURITY}{defptr2}{$device_name};
	if (!$def) {
	Log3 $hash, 1, "TRX_SECURITY_parse_X10Sec() UNDEFINED $device_name TRX_SECURITY $dev_type $device $dev_reading";
        	Log3 $hash, 3, "TRX_SECURITY_parse_X10Sec() Unknown device $device_name, please define it";
       		return "UNDEFINED $device_name TRX_SECURITY $dev_type $device $dev_reading";
	}
  }

  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my $data = $bytes->[6];

  my $hexdata = sprintf '%02x', $data;

  my %x10_security =
    (
	0x00 => ['X10Sec', 'normal', 'min_delay', '', ''],
	0x01 => ['X10Sec', 'normal', 'max_delay', '', ''],

	0x02 => ['X10Sec', 'alert', 'min_delay', '', ''],
	0x03 => ['X10Sec', 'alert', 'max_delay', '', ''],

	0x04 => ['X10Sec', 'alert', '', '', ''],
	0x05 => ['X10Sec', 'normal', '', '', ''],

	0x06 => ['X10Sec', 'alert', '', '', ''],
	0x07 => ['X10Sec', 'Security-EndPanic', '', '', ''],

	0x08 => ['X10Sec', 'IR', '', '', ''],

	0x09 => ['X10Sec', 'Security-Arm_Away', 'min_delay', '', ''], # kr18
	0x0a => ['X10Sec', 'Security-Arm_Away', 'max_delay', '', ''], # kr18
	0x0b => ['X10Sec', 'Security-Arm_Home', 'min_delay', '', ''], # kr18
	0x0c => ['X10Sec', 'Security-Arm_Home', 'max_delay', '', ''], # kr18
	0x0d => ['X10Sec', 'Security-Disarm', 'min_delay', '', ''], # kr18

	0x10 => ['X10Sec', 'ButtonA-off', '', '', ''], # kr18
	0x11 => ['X10Sec', 'ButtonA-on', '', '', ''], # kr18
	0x12 => ['X10Sec', 'ButtonB-off', '', '', ''], # kr18
	0x13 => ['X10Sec', 'ButtonB-on', '', '', ''], # kr18

	0x14 => ['X10Sec', 'dark', '', '', ''],
	0x15 => ['X10Sec', 'light', '', '', ''],
	0x16 => ['X10Sec', 'normal', '', 'batt_low', ''],

	0x17 => ['X10Sec', 'pair KD101', '', '', ''],

	0x80 => ['X10Sec', 'normal', 'max_delay', '', 'tamper'],
	0x81 => ['X10Sec', 'normal', 'min_delay', '', 'tamper'],
	0x82 => ['X10Sec', 'alert', 'max_delay', '', 'tamper'],
	0x83 => ['X10Sec', 'alert', 'min_delay', '', 'tamper'],
	0x84 => ['X10Sec', 'alert', '', '', 'tamper'],
	0x85 => ['X10Sec', 'normal', '', '', 'tamper'],

    );

  my $command = "";
  my $type = "";
  my $delay = "";
  my $battery = "";
  my $rssi = "";
  my $option = "";
  my @res;
  if (exists $x10_security{$data}) {
    my $rec = $x10_security{$data};
    if (ref $rec) {
      ($type, $command, $delay, $battery, $option) = @$rec;
    } else {
      $command = $rec;
    }
  } else {
    Log3 $name, 1, "TRX_SECURITY_parse_X10Sec() undefined command cmd=$data device-nr=$device, hex=$hexdata";
    return "";
  }

  my $battery_level = $bytes->[7] & 0x0f;
  if (($battery eq "") && ($dev_type ne "KD101")) {
	if ($battery_level == 0x9) { $battery = 'batt_ok'}
	elsif ($battery_level == 0x0) { $battery = 'batt_low'}
	else {
		Log3 $name, 1,"TRX_SECURITY_parse_X10Sec() unkown battery_level=$battery_level";
	}
  }

  if ($trx_rssi == 1) {
  	$rssi = sprintf("%d", ($bytes->[7] & 0xf0) >> 4);
	Log3 $name, 5, "TRX_SECURITY_parse_X10Sec() $name devn=$device_name rssi=$rssi";
  }

  my $current = "";

  Log3 $name, 5, "TRX_SECURITY_parse_X10Sec() $name devn=$device_name first=$firstdevice subtype=$subtype command=$command, delay=$delay, batt=$battery cmd=$hexdata";


  my $n = 0;
  my $tm = TimeNow();
  my $val = "";

  my $device_type = uc($def->{TRX_SECURITY_type});

  my $sensor = "";

  if ($device_type eq "SD90") {
	$sensor = $firstdevice == 1 ? $def->{TRX_SECURITY_devicelog} : $def->{TRX_SECURITY_devicelog2};
  } else {
  	$sensor = $def->{TRX_SECURITY_devicelog};
  } 

  $current = $command;
  if (($device_type eq "DS10A") || ($device_type eq "VISONIC_WINDOW")) {
	$current = "Error";
	$current = "Open" if ($command eq "alert");
	$current = "Closed" if ($command eq "normal");
  } elsif ($device_type eq "WD18" || $device_type eq "GD18") {
	$current = "Error";
	$current = "normal" if ($command eq "alert");
	$current = "alert" if ($command eq "normal");
	$delay = "";  
	$option = "";  
  }

  readingsBeginUpdate($def);

  if (($device_type ne "KR18") && ($device_type ne "VISONIC_REMOTE")) {  
  	if ($firstdevice == 1) {
		$val .= $current;
  	}
	if ($sensor ne "none") { readingsBulkUpdate($def, $sensor, $current); }

	# KD101 does not show normal, so statechange does not make sense
  	if (($def->{STATE} ne $val) && ($device_type ne "KD101")) { 
		$sensor = "statechange";
		readingsBulkUpdate($def, $sensor, $current);
  	}
  } else {
	# kr18 remote control or VISONIC_REMOTE
	$current = $command;

	#$sensor = $def->{TRX_SECURITY_devicelog};
	#$val = $current;
	#readingsBulkUpdate($def, $sensor, $current);

	$current = "Security-Panic" if ($command eq "alert");

	my @cmd_split = split(/-/, $command);
	$sensor = $cmd_split[0];
	$current = $cmd_split[1];
	readingsBulkUpdate($def, $sensor, $current);

	$val .= $current;
  }

  if ($battery ne "") {
	$sensor = "battery";
	$current = "Error";
	$current = "ok" if ($battery eq "batt_ok");
	$current = "low" if ($battery eq "batt_low");
	readingsBulkUpdate($def, $sensor, $current);
  }

  if ($rssi ne "") {
	$sensor = "rssi";
	readingsBulkUpdate($def, $sensor, $rssi);
  }


  if ($delay ne '') {
	$sensor = "delay";
	$current = "Error";
	$current = "min" if ($delay eq "min_delay");
	$current = "max" if ($delay eq "max_delay");
	readingsBulkUpdate($def, $sensor, $current);
  }
  if ($option ne '') {
	$val .= " ".$option;
  }

  if (($firstdevice == 1) && $val) {
  	$def->{STATE} = $val;
	readingsBulkUpdate($def, "state", $val);
  }

  readingsEndUpdate($def, 1);

  return $name;
}


sub
TRX_SECURITY_Parse($$)
{
  my ($iohash, $hexline) = @_;

  $trx_rssi = 0;
  if (defined($attr{$iohash->{NAME}}{rssi})) {
  	$trx_rssi = $attr{$iohash->{NAME}}{rssi};
  	Log3 $iohash, 5,"TRX_SECURITY_Parse() attr rssi = $trx_rssi";
  }

  my $time = time();
  # convert to binary
  my $msg = pack('H*', $hexline);
  if ($time_old ==0) {
  	Log3 $iohash, 5, "TRX_SECURITY_Parse() decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log3 $iohash, 5, "TRX_SECURITY_Parse() decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $num_bytes = ord($msg);

  if ($num_bytes < 3) {
    return "";
  }

  my $type = $rfxcom_data_array[0];

  Log3 $iohash, 5, "TRX_SECURITY_Parse() X10Sec num_bytes=$num_bytes hex=$hexline type=$type";
  my $res = "";
  if ($type == 0x20) {
	Log3 $iohash, 5, "TRX_SECURITY_Parse() X10Sec num_bytes=$num_bytes hex=$hexline";
        $res = TRX_SECURITY_parse_X10Sec($iohash, \@rfxcom_data_array);
  	Log3 $iohash, 1, "TRX_SECURITY_Parse() unsupported hex=$hexline" if ($res eq "");
	return $res;
  } else {
	Log3 $iohash, 0, "TRX_SECURITY_Parse() not implemented num_bytes=$num_bytes hex=$hexline";
  }

  return "";
}

1;

=pod
=begin html

<a name="TRX_SECURITY"></a>
<h3>TRX_SECURITY</h3>
<ul>
  The TRX_SECURITY module interprets X10, KD101 and Visonic security sensors received by a RFXCOM RFXtrx433 RF receiver. You need to define an RFXtrx433 receiver first. See <a href="#TRX">TRX</a>.

  <br><br>

  <a name="TRX_SECURITYdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TRX_SECURITY &lt;type&gt; &lt;deviceid&gt; &lt;devicelog&gt; [&lt;deviceid2&gt; &lt;devicelog2&gt;] </code> <br>
    <br>
    <code>&lt;type&gt;</code>
    <ul>
      specifies one of the following security devices:
        <ul>
          <li> <code>DS10A</code> (X10 security ds10a Door/Window Sensor or compatible devices. This device type reports the status of the switch [Open/Closed], status of the delay switch [min|max]], and battery status [ok|low].)</li>
          <li> <code>MS10A</code> (X10 security ms10a motion sensor. This device type reports the status of motion sensor  [normal|alert] and battery status [ok|low].))</li>
          <li> <code>SD90</code> (Marmitek sd90 smoke detector. This device type reports the status of the smoke detector [normal|alert] and battery status [ok|low].)</li>
          <li> <code>KR18</code> (X10 security remote control. Report the Reading "Security" with values [Arm|Disarm], "ButtonA" and "ButtonB" with values [on|off] )</li>
          <li> <code>KD101</code> (KD101 smoke sensor. Report the Reading "smoke" with values [normal|alert])</li>
          <li> <code>VISONIC_WINDOW</code> (VISONIC security Door/Window Sensor or compatible devices. This device type reports the status of the switch [Open/Closed] and battery status [ok|low].)</li>
          <li> <code>VISONIC_MOTION</code> (VISONIC security motion sensor. This device type reports the status of motion sensor  [normal|alert] and battery status [ok|low].))</li>
        </ul>
    </ul>
    <br>
    <code>&lt;deviceid&gt;</code>
    <ul>
    specifies the first device id of the device. X10 security (DS10A, MS10A) and SD90 have a a 16 bit device id which has to be written as a hex-string (example "5a54"). All other devices have a 24 bit device id.
    </ul>
    <br>
    <code>&lt;devicelog&gt;</code>
    <ul>
    is the name of the Reading used to report. Suggested: "Window" or "Door" for ds10a, "motion" for motion sensors, "smoke" for sd90. If you use "none" then no additional Reading is reported. Just the state is used to report the change.
    </ul>
    <br>
    <code>&lt;deviceid2&gt;</code>
    <ul>
    is optional and specifies the second device id of the device if it exists. For example sd90 smoke sensors can be configured to report two device ids.
    </ul>
    <br>
    <code>&lt;devicelog2&gt;</code>
    <ul>
    is optional for the name used for the Reading of <code>&lt;deviceid2&gt;</code>. If you use "none" then no additional Reading is reported. Just the state is used to report the change.
    </ul>
    <br>
      Example: <br>
    <code>define livingroom_window TRX_SECURITY ds10a 72cd Window</code>
      <br>
    <code>define motion_sensor1 TRX_SECURITY ms10a 55c6 motion</code>
      <br>
    <code>define smoke_sensor1 TRX_SECURITY sd90 54d3 Smoke 54d3 Smoketest</code>
      <br>
  </ul>
  <br>

  <a name="TRX_SECURITYset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; </code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    alert              # only for KD101
    pair               # only for KD101
    </pre>
      Example: <br>
    	<code>set TRX_KD101_a5ca00 alert</code>
      <br>
  </ul><br>

  <a name="TRX_SECURITYget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="TRX_SECURITYattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>

=end html
=cut
