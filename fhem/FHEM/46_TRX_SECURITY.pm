#################################################################################
# 46_TRX_SECURITY.pm
#
# Modul for FHEM for X10, KD101, Visonic
# - X10 security messages tested for 
#               - ds10a: X10 Door / Window Sensor or compatible devices
#               - ss10a: X10 motion sensor
#               - sd90: Marmitek smoke detector
#		- kr18: X10 remote control
#
##################################
#
#  Willi Herzig, 2012
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
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
use Switch;

# Debug this module? YES = 1, NO = 0
my $TRX_SECURITY_debug = 0;

my $time_old = 0;

my $TRX_SECURITY_type_default = "ds10a";

my $DOT = q{_};

sub
TRX_SECURITY_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^(\\ |\\)).*"; # 0x20 or 0x29
  $hash->{DefFn}     = "TRX_SECURITY_Define";
  $hash->{UndefFn}   = "TRX_SECURITY_Undef";
  $hash->{ParseFn}   = "TRX_SECURITY_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
TRX_SECURITY_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $a = int(@a);

  if(int(@a) != 5 && int(@a) != 7) {
	Log 1,"TRX_SECURITY wrong syntax '@a'. \nCorrect syntax is  'define <name> TRX_SECURITY <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]'";
	return "wrong syntax: define <name> TRX_SECURITY <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]";
  }
	

  my $name = $a[0];

  my $type = lc($a[2]);
  my $deviceid = $a[3];
  my $devicelog = $a[4];


  $type = uc($type);

  my $device_name = "TRX".$DOT.$type.$DOT.$deviceid;

  if ($type ne "DS10A" && $type ne "SD90" && $type ne "MS10A" && $type ne "MS14A" && $type ne "KR18" && $type ne "KD101" && $type ne "VISONIC_WINDOW" & $type ne "VISONIC_MOTION" & $type ne "VISONIC_REMOTE") {
  	Log 1,"RFX10SEC define: wrong type: $type";
  	return "RFX10SEC: wrong type: $type";
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
sub TRX_SECURITY_parse_X10Sec {
  my $bytes = shift;

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
	Log 1, $error;
  	return $error;
    }
  } else {
 	$error = "TRX_SECURITY: error undefined subtype=$subtype";
	Log 1, $error;
  	return $error;
  }

  #Log 4, "device_type=$device_type";

  #--------------
  my $device_name = "TRX".$DOT.$dev_type.$DOT.$device;
  Log 4, "device_name=$device_name";

  my $firstdevice = 1;
  my $def = $modules{TRX_SECURITY}{defptr}{$device_name};
  if(!$def) {
  	$firstdevice = 0;
	$def = $modules{TRX_SECURITY}{defptr2}{$device_name};
	if (!$def) {
	Log 1, "UNDEFINED $device_name TRX_SECURITY $dev_type $device $dev_reading";
        	Log 3, "TRX_SECURITY: TRX_SECURITY Unknown device $device_name, please define it";
       		return "UNDEFINED $device_name TRX_SECURITY $dev_type $device $dev_reading";
	}
  }

  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};

  my $data = $bytes->[6];

  my $hexdata = sprintf '%02x', $data;

  my %x10_security =
    (
	0x00 => ['X10Sec', 'normal', 'min_delay', ''],
	0x01 => ['X10Sec', 'normal', 'max_delay', ''],

	0x02 => ['X10Sec', 'alert', 'min_delay', ''],
	0x03 => ['X10Sec', 'alert', 'max_delay', ''],

	0x04 => ['X10Sec', 'alert', '', ''],
	0x05 => ['X10Sec', 'normal', '', ''],

	0x06 => ['X10Sec', 'alert', '', ''],
	0x07 => ['X10Sec', 'normal', '', ''],

	0x08 => ['X10Sec', 'tamper', '', ''],

	0x09 => ['X10Sec', 'Security-Arm_Away', 'min_delay', ''], # kr18
	0x0a => ['X10Sec', 'Security-Arm_Away', 'max_delay', ''], # kr18
	0x0b => ['X10Sec', 'Security-Arm_Home', 'min_delay', ''], # kr18
	0x0c => ['X10Sec', 'Security-Arm_Home', 'max_delay', ''], # kr18
	0x0d => ['X10Sec', 'Security-Disarm', 'min_delay', ''], # kr18

	0x10 => ['X10Sec', 'ButtonA-on', '', ''], # kr18
	0x11 => ['X10Sec', 'ButtonA-off', '', ''], # kr18
	0x12 => ['X10Sec', 'ButtonB-on', '', ''], # kr18
	0x13 => ['X10Sec', 'ButtonB-off', '', ''], # kr18

	0x14 => ['X10Sec', 'dark', '', ''],
	0x15 => ['X10Sec', 'light', '', ''],
	0x16 => ['X10Sec', 'normal', '', 'batt_low'],

	0x17 => ['X10Sec', 'pair KD101', '', ''],

    );

  my $command = "";
  my $type = "";
  my $delay = "";
  my $battery = "";
  my @res;
  if (exists $x10_security{$data}) {
    my $rec = $x10_security{$data};
    if (ref $rec) {
      ($type, $command, $delay, $battery) = @$rec;
    } else {
      $command = $rec;
    }
  } else {
    Log 1, "TRX_SECURITY undefined command cmd=$data device-nr=$device, hex=$hexdata";
    return "TRX_SECURITY undefined command";
  }

  my $battery_level = $bytes->[7] & 0x0f;
  if (($battery eq "") && ($dev_type ne "kd101")) {
	if ($battery_level == 0x9) { $battery = 'batt_ok'}
	elsif ($battery_level == 0x0) { $battery = 'batt_low'}
	else {
		Log 1,"TRX-X10: X10Sec unkown battery_level=$battery_level";
	}
  }

  my $current = "";

  Log 1, "TRX_SECURITY: $name devn=$device_name first=$firstdevice subtype=$subtype command=$command, delay=$delay, batt=$battery cmd=$hexdata" if ($TRX_SECURITY_debug == 1);

  my $n = 0;
  my $tm = TimeNow();
  my $val = "";

  my $device_type = $def->{TRX_SECURITY_type};

  my $sensor = "";

  if ($device_type eq "sd90") {
	$sensor = $firstdevice == 1 ? $def->{TRX_SECURITY_devicelog} : $def->{TRX_SECURITY_devicelog2};
  } else {
  	$sensor = $def->{TRX_SECURITY_devicelog};
  } 

  $current =$command;
  if (($device_type eq "DS10A") || ($device_type eq "VISONIC_WINDOW")) {
	$current = "Error";
	$current = "Open" if ($command eq "alert");
	$current = "Closed" if ($command eq "normal");
  }

  if (($dev_type ne "kr18") || ($dev_type ne "VISONIC_REMOTE")) {  
  	if ($firstdevice == 1) {
		$val .= $current;
  	}
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;

  	if (($def->{STATE} ne $val)) {
		$sensor = "statechange";
		$def->{READINGS}{$sensor}{TIME} = $tm;
		$def->{READINGS}{$sensor}{VAL} = $current;
		$def->{CHANGED}[$n++] = $sensor . ": " . $current;		
  	}
  } else {
	# kr18 remote control or VISONIC_REMOTE
	$current = $command;

	#$sensor = $def->{TRX_SECURITY_devicelog};
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
  }

  if ($battery ne "") {
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

  if (($firstdevice == 1) && $val) {
  	$def->{STATE} = $val;
  	$def->{TIME} = $tm;
  	$def->{CHANGED}[$n++] = $val;
  }

  DoTrigger($name, undef);

  return "";
}


sub
TRX_SECURITY_Parse($$)
{
  my ($iohash, $hexline) = @_;

  my $time = time();
  # convert to binary
  my $msg = pack('H*', $hexline);
  if ($time_old ==0) {
  	Log 5, "TRX_SECURITY: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "TRX_SECURITY: decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $num_bytes = ord($msg);

  if ($num_bytes < 3) {
    return;
  }

  my $type = $rfxcom_data_array[0];

  #Log 1, "TRX_SECURITY: X10Sec num_bytes=$num_bytes hex=$hexline type=$type" if ($TRX_SECURITY_debug == 1);
  my $res = "";
  if ($type == 0x20) {
	Log 1, "TRX_SECURITY: X10Sec num_bytes=$num_bytes hex=$hexline" if ($TRX_SECURITY_debug == 1);
        $res = TRX_SECURITY_parse_X10Sec(\@rfxcom_data_array);
  	Log 1, "TRX_SECURITY: unsupported hex=$hexline" if ($res ne "" && $res !~ /^UNDEFINED.*/);
	return $res;
  } else {
	Log 0, "TRX_SECURITY: not implemented num_bytes=$num_bytes hex=$hexline";
  }

  return "";
}

1;
