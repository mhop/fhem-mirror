#################################################################################
# 46_TRX_LIGHT.pm
#
# FHEM module for lighting protocols: 
#   X10 lighting, ARC, ELRO AB400D, Waveman, Chacon EMW200, 
#   IMPULS, AC (KlikAanKlikUit, NEXA, CHACON, HomeEasy UK), 
#   HomeEasy EU, ANSLUT, Ikea Koppla
#
# Copyright (C) 2012 Willi Herzig
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
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
my $TRX_LIGHT_debug = 0;

my $time_old = 0;

my $TRX_LIGHT_type_default = "ds10a";
my $TRX_LIGHT_X10_type_default = "x10";

my $DOT = q{_};

my %light_device_codes = (	# HEXSTRING => "NAME", "name of reading", 
	# 0x10: Lighting1
	0x1000 => [ "X10", "light" ],
	0x1001 => [ "ARC", "light" ],
	0x1002 => [ "AB400D", "light" ],
	0x1003 => [ "WAVEMAN", "light" ],
	0x1004 => [ "EMW200", "light"],
	0x1005 => [ "IMPULS", "light"],
	# 0x11: Lighting2
	0x1100 => [ "AC", "light"],
	0x1101 => [ "HOMEEASY", "light"],
	0x1102 => [ "ANSLUT", "light"],
	# 0x12: Lighting3
	0x1200 => [ "KOPPLA", "light"], # IKEA Koppla
);

my %light_device_commands = (	# HEXSTRING => commands
	# 0x10: Lighting1
	0x1000 => [ "off", "on", "dim", "bright", "", "all_off", "all_on"], # X10
	0x1001 => [ "off", "on", "", "", "", "all_off", "all_on", "chime"], # ARC
	0x1002 => [ "off", "on"], # AB400D
	0x1003 => [ "off", "on"], # WAVEMAN
	0x1004 => [ "off", "on"], # EMW200
	0x1005 => [ "off", "on"], # IMPULS
	# 0x11: Lighting2
	0x1100 => [ "off", "on", "level", "all_off", "all_on", "all_level"], # AC
	0x1101 => [ "off", "on", "level", "all_off", "all_on", "all_level"], # HOMEEASY
	0x1102 => [ "off", "on", "level", "all_off", "all_on", "all_level"], # ANSLUT
	# 0x12: Lighting3
	0x1200 => [ "bright", "", "", "", "", "", "", "dim", "", "", "", "", "", "", "", "", "",
		    "on", "level1", "level2", "level3", "level4", "level5", "level6", "level7", "level8", "level9", "off", "", "program", "", "", "", "",], # Koppla
);

my %light_device_c2b;        # DEVICE_TYPE->hash (reverse of light_device_codes)

sub
TRX_LIGHT_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %light_device_codes) {
    $light_device_c2b{$light_device_codes{$k}->[0]} = $k;
  }

  $hash->{Match}     = "^..(10|11|12).*";
  $hash->{SetFn}     = "TRX_LIGHT_Set";
  $hash->{DefFn}     = "TRX_LIGHT_Define";
  $hash->{UndefFn}   = "TRX_LIGHT_Undef";
  $hash->{ParseFn}   = "TRX_LIGHT_Parse";
  $hash->{AttrList}  = "IODev ignore:1,0 do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
TRX_LIGHT_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  # to be done. Just accept everything right now.
  #return "Undefined value $val" if(!defined($fs20_c2b{$val}));
  return undef;
}

###################################
sub
TRX_LIGHT_Set($@)
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

  my $device_type = $hash->{TRX_LIGHT_type};
  my $deviceid = $hash->{TRX_LIGHT_deviceid};

  if ($device_type eq "MS14A") {
	return "No set implemented for $device_type";	
  }

  my $device_type_num = $light_device_c2b{$device_type};
  if(!defined($device_type_num)) {
	return "Unknown device_type, choose one of " .
                                join(" ", sort keys %light_device_c2b);
  }
  my $protocol_type = $device_type_num >> 8; # high bytes

  # Now check if the command is valid and retrieve the command id:
  my $rec = $light_device_commands{$device_type_num};
  my $i;
  for ($i=0; $i <= $#$rec && ($rec->[$i] ne $command); $i++) { ;}

  if($i > $#$rec) {
	my $error = "Unknown command $command, choose one of " . join(" ", sort @$rec);
	Log 4, $error;
	return $error;
  }

  if ($na == 4 && $command ne "level") {
	my $error = "Error: level not possible for command $command";
  }

  my $seqnr = 0;
  my $cmnd = $i;

  my $hex_prefix;
  my $hex_command;
  if ($protocol_type == 0x10) {
  	my $house;
  	my $unit;
  	if ($deviceid =~ /(.)(.*)/ ) {
		$house = ord("$1");
		$unit = $2;
  	} else {
		Log 4,"TRX_LIGHT_Set lightning1 wrong deviceid: name=$name device_type=$device_type, deviceid=$deviceid";
		return "error set name=$name  deviveid=$deviceid";
  	}

	# lightning1
  	$hex_prefix = sprintf "0710";
  	$hex_command = sprintf "%02x%02x%02x%02x%02x00", $device_type_num & 0xff, $seqnr, $house, $unit, $cmnd; 
  	Log 1,"TRX_LIGHT_Set name=$name device_type=$device_type, deviceid=$deviceid house=$house, unit=$unit command=$command" if ($TRX_LIGHT_debug == 1);
  	Log 1,"TRX_LIGHT_Set hexline=$hex_command" if ($TRX_LIGHT_debug == 1);
  } elsif ($protocol_type == 0x11) {
	# lightning2
  	if (uc($deviceid) =~ /^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/ ) {
		;
  	} else {
		Log 4,"TRX_LIGHT_Set lightning2 wrong deviceid: name=$name device_type=$device_type, deviceid=$deviceid";
		return "error set name=$name  deviveid=$deviceid";
  	}
  	$hex_prefix = sprintf "0B11";
  	$hex_command = sprintf "%02x%02x%s%02x%02x00", $device_type_num & 0xff, $seqnr, $deviceid, $cmnd, $level; 
	if ($command eq "level") {
		$command .= sprintf " %d", $level;
	} 
  	Log 1,"TRX_LIGHT_Set name=$name device_type=$device_type, deviceid=$deviceid command=$command" if ($TRX_LIGHT_debug == 1);
  	Log 1,"TRX_LIGHT_Set hexline=$hex_command" if ($TRX_LIGHT_debug == 1);
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
TRX_LIGHT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $a = int(@a);

  if(int(@a) != 5 && int(@a) != 7) {
	Log 1,"TRX_LIGHT wrong syntax '@a'. \nCorrect syntax is  'define <name> TRX_LIGHT <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]'";
	return "wrong syntax: define <name> TRX_LIGHT <type> <deviceid> <devicelog> [<deviceid2> <devicelog2>]";
  }
	

  my $name = $a[0];

  my $type = lc($a[2]);
  my $deviceid = $a[3];
  my $devicelog = $a[4];


  $type = uc($type);

  if ($type ne "X10" && $type ne "ARC" && $type ne "MS14A" && $type ne "AB400D" && $type ne "WAVEMAN" && $type ne "EMW200" && $type ne "IMPULS" && $type ne "AC" && $type ne "HOMEEASY" && $type ne "ANSLUT" && $type ne "KOPPLA") {
  	Log 1,"TRX_LIGHT define: wrong type: $type";
  	return "TRX_LIGHT: wrong type: $type";
  }

  my $my_type;
  if ($type eq "MS14A") {
	$my_type = "X10"; # device will be received as X10	
  } else {
	$my_type = $type;
  }

  my $device_name = "TRX".$DOT.$my_type.$DOT.$deviceid;

  $hash->{TRX_LIGHT_deviceid} = $deviceid;
  $hash->{TRX_LIGHT_devicelog} = $devicelog;
  $hash->{TRX_LIGHT_type} = $type;
  #$hash->{TRX_LIGHT_CODE} = $deviceid;
  $modules{TRX_LIGHT}{defptr}{$device_name} = $hash;


  if (int(@a) == 7) {
	# there is a second deviceid:
	#
  	my $deviceid2 = $a[5];
  	my $devicelog2 = $a[6];

  	my $device_name2 = "TRX".$DOT.$my_type.$DOT.$deviceid2;

  	$hash->{TRX_LIGHT_deviceid2} = $deviceid2;
  	$hash->{TRX_LIGHT_devicelog2} = $devicelog2;
  	#$hash->{TRX_LIGHT_CODE2} = $deviceid2;
  	$modules{TRX_LIGHT}{defptr2}{$device_name2} = $hash;
  }

  AssignIoPort($hash);

  return undef;
}

#####################################
sub
TRX_LIGHT_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{TRX_LIGHT}{defptr}{$name});
  return undef;
}


#####################################
sub TRX_LIGHT_parse_X10 {
  my $bytes = shift;

  my $error = "";


  #my $device;

  my $type = $bytes->[0];
  my $subtype = $bytes->[1];
  my $dev_type;
  my $dev_reading;
  my $rest;

  my $type_subtype = ($type << 8) + $subtype;

  if (exists $light_device_codes{$type_subtype}) {
    my $rec = $light_device_codes{$type_subtype};
    ($dev_type, $dev_reading) = @$rec;
  } else {
 	$error = sprintf "TRX_LIGHT: error undefined type=%02x, subtype=%02x", $type, $subtype;
	Log 1, $error;
  	return $error;
  }


  my $device;
  my $data;
  if ($type == 0x10) {
  	my $dev_first = "?";

  	my %x10_housecode =
    	(
		0x41 => "A",
		0x42 => "B",
		0x43 => "C",
		0x44 => "D",
		0x45 => "E",
		0x46 => "F",
		0x47 => "G",
		0x48 => "H",
		0x49 => "I",
		0x4A => "J",
		0x4B => "K",
		0x4C => "L",
		0x4D => "M",
		0x4E => "N",
		0x4F => "O",
		0x50 => "P",
  	);
  	my $devnr = $bytes->[3]; # housecode
  	if (exists $x10_housecode{$devnr}) {
  		$dev_first = $x10_housecode{$devnr};
  	} else {
		$error = sprintf "TRX_LIGHT: x10_housecode wrong housecode=%02x", $devnr;
		Log 1, $error;
  		return $error;
  	}
	my $unit = $bytes->[4]; # unitcode
  	$device = sprintf '%s%0d', $dev_first, $unit;
  	$data = $bytes->[5];

  } elsif ($type == 0x11) {
  	$device = sprintf '%02x%02x%02x%02x%02x', $bytes->[3], $bytes->[4], $bytes->[5], $bytes->[6], $bytes->[7];
  	$data = $bytes->[8];
  } else {
	$error = sprintf "TRX_LIGHT: wrong type=%02x", $type;
	Log 1, $error;
  	return $error;
  }
  my $hexdata = sprintf '%02x', $data;


  my $command = "";
  if (exists $light_device_commands{$type_subtype}) {
  	my $code = $light_device_commands{$type_subtype};
  	if (exists $code->[$data]) {
  		$command = $code->[$data];
  	} else {
 		$error = sprintf "TRX_LIGHT: unknown cmd type_subtype=%02x cmd=%02x", $type_subtype, $data;
		Log 1, $error;
		return $error;
  	}
  } else {
	$error = sprintf "TRX_LIGHT: unknown type_subtype %02x data=%02x", $type_subtype, $data;
	Log 1, $error;
	return $error;
  }

  #my @res;
  my $current = "";

  #--------------
  my $device_name = "TRX".$DOT.$dev_type.$DOT.$device;
  Log 1, "TRX_LIGHT: device_name=$device_name data=$hexdata" if ($TRX_LIGHT_debug == 1);

  my $firstdevice = 1;
  my $def = $modules{TRX_LIGHT}{defptr}{$device_name};
  if(!$def) {
  	$firstdevice = 0;
	$def = $modules{TRX_LIGHT}{defptr2}{$device_name};
	if (!$def) {
		Log 1, "UNDEFINED $device_name TRX_LIGHT $dev_type $device $dev_reading" if ($TRX_LIGHT_debug == 1);
        	Log 3, "TRX_LIGHT: TRX_LIGHT Unknown device $device_name, please define it";
       		return "UNDEFINED $device_name TRX_LIGHT $dev_type $device $dev_reading";

	}
  }

  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  Log 1, "TRX_LIGHT: $name devn=$device_name first=$firstdevice command=$command, cmd=$hexdata" if ($TRX_LIGHT_debug == 1);

  my $n = 0;
  my $tm = TimeNow();
  my $val = "";

  my $device_type = $def->{TRX_LIGHT_type};

  my $sensor = "";

  if ($device_type eq "MS14A") {
	# for ms14a behave like x10, but flip second deviceid
	$device_type = "X10";
  	if ($firstdevice == 1) {
		$command = ($command eq "on") ? "alert" : "normal" ;
	} else {	
		$command = ($command eq "on") ? "off" : "on" ;	
	}
  }

  if ($type == 0x10 || $type == 0x11) {
	# try to use it for all types:
	$current = $command;
	if ($type == 0x11 && $command eq "level") {
		# append level number
		my $level = $bytes->[9];
		$current .= sprintf " %d", $level;
	}

	$sensor = $firstdevice == 1 ? $def->{TRX_LIGHT_devicelog} : $def->{TRX_LIGHT_devicelog2};
	$val .= $current;
  	$def->{READINGS}{$sensor}{TIME} = $tm;
  	$def->{READINGS}{$sensor}{VAL} = $current;
  	$def->{CHANGED}[$n++] = $sensor . ": " . $current;
  } else {
	$error = sprintf "TRX_LIGHT: error unknown sensor type=%x device_type=%s devn=%s first=%d command=%s", $type, $device_type, $device_name, $firstdevice, $command;
	Log 1, $error;
	return $error;
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
sub
TRX_LIGHT_Parse($$)
{
  my ($iohash, $hexline) = @_;

  my $time = time();
  # convert to binary
  my $msg = pack('H*', $hexline);
  if ($time_old ==0) {
  	Log 5, "TRX_LIGHT: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "TRX_LIGHT: decoding delay=$time_diff hex=$hexline";
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

  #Log 1, "TRX_LIGHT: num_bytes=$num_bytes hex=$hexline type=$type" if ($TRX_LIGHT_debug == 1);
  my $res = "";
  if ($type == 0x10 || $type == 0x11 || $type == 0x12) {
	Log 1, "TRX_LIGHT: X10 num_bytes=$num_bytes hex=$hexline" if ($TRX_LIGHT_debug == 1);
        $res = TRX_LIGHT_parse_X10(\@rfxcom_data_array);
  	Log 1, "TRX_LIGHT: unsupported hex=$hexline" if ($res ne "" && $res !~ /^UNDEFINED.*/);
	return $res;
  } else {
	Log 0, "TRX_LIGHT: not implemented num_bytes=$num_bytes hex=$hexline";
  }

  return "";
}

1;
