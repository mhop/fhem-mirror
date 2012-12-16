# $Id$
##############################################################################
#
#     46_TRX_LIGHT.pm
#     FHEM module for lighting protocols:
#       X10 lighting, ARC, ELRO AB400D, Waveman, Chacon EMW200,
#       IMPULS, AC (KlikAanKlikUit, NEXA, CHACON, HomeEasy UK),
#       HomeEasy EU, ANSLUT, Ikea Koppla
#     Copyright by Willi Herzig
#     e-mail: 
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
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
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
	0x1006 => [ "RISINGSUN", "light"],
	0x1007 => [ "PHILIPS_SBC", "light"],
	# 0x11: Lighting2
	0x1100 => [ "AC", "light"],
	0x1101 => [ "HOMEEASY", "light"],
	0x1102 => [ "ANSLUT", "light"],
	# 0x12: Lighting3
	0x1200 => [ "KOPPLA", "light"], # IKEA Koppla
	0x1400 => [ "LIGHTWAVERF", "light"], # LightwaveRF
	0x1401 => [ "EMW100", "light"], # EMW100
	0x1402 => [ "BBSB", "light"], # BBSB
);

my %light_device_commands = (	# HEXSTRING => commands
	# 0x10: Lighting1
	0x1000 => [ "off", "on", "dim", "bright", "", "all_off", "all_on"], # X10
	0x1001 => [ "off", "on", "", "", "", "all_off", "all_on", "chime"], # ARC
	0x1002 => [ "off", "on"], # AB400D
	0x1003 => [ "off", "on"], # WAVEMAN
	0x1004 => [ "off", "on"], # EMW200
	0x1005 => [ "off", "on"], # IMPULS
	0x1006 => [ "off", "on"], # RisingSun
	0x1007 => [ "off", "on", "", "", "", "all_off", "all_on"], # Philips SBC
	# 0x11: Lighting2
	0x1100 => [ "off", "on", "level", "all_off", "all_on", "all_level"], # AC
	0x1101 => [ "off", "on", "level", "all_off", "all_on", "all_level"], # HOMEEASY
	0x1102 => [ "off", "on", "level", "all_off", "all_on", "all_level"], # ANSLUT
	# 0x12: Lighting3
	0x1200 => [ "bright", "", "", "", "", "", "", "dim", "", "", "", "", "", "", "", "", "",
		    "on", "level1", "level2", "level3", "level4", "level5", "level6", "level7", "level8", "level9", "off", "", "program", "", "", "", "",], # Koppla
	0x1400 => [ "off", "on", "all_off", "mood1", "mood2", "mood3", "mood4", "mood5", "reserved1", "reserved2", "unlock", "lock", "all_lock", "close", "stop", "open", "level"], # LightwaveRF, Siemens
	0x1401 => [ "off", "on", "learn"], # EMW100 GAO/Everflourish
	0x1402 => [ "off", "on", "all_off", "all_on"], # BBSB new types
);

my %light_device_c2b;        # DEVICE_TYPE->hash (reverse of light_device_codes)

sub
TRX_LIGHT_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %light_device_codes) {
    $light_device_c2b{$light_device_codes{$k}->[0]} = $k;
  }

  $hash->{Match}     = "^..(10|11|12|14).*";
  $hash->{SetFn}     = "TRX_LIGHT_Set";
  $hash->{DefFn}     = "TRX_LIGHT_Define";
  $hash->{UndefFn}   = "TRX_LIGHT_Undef";
  $hash->{ParseFn}   = "TRX_LIGHT_Parse";
  $hash->{AttrList}  = "IODev ignore:1,0 event-on-update-reading event-on-change-reading do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

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

#############################
sub
TRX_LIGHT_Do_On_Till($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  my $tname = $hash->{NAME} . "_timer";
  CommandDelete(undef, $tname) if($defs{$tname});
  my @b = ($a[0], "on");
  TRX_LIGHT_Set($hash, @b);
  CommandDefine(undef, "$tname at $hms_till set $a[0] off");

}


#############################
sub
TRX_LIGHT_Do_On_For_Timer($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-for-timer command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my $hms_for_timer = sprintf("+%02d:%02d:%02d", $hr, $min, $sec);

  my $tname = $hash->{NAME} . "_timer";
  CommandDelete(undef, $tname) if($defs{$tname});
  my @b = ($a[0], "on");
  TRX_LIGHT_Set($hash, @b);
  CommandDefine(undef, "$tname at $hms_for_timer set $a[0] off");

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

  # special for on-till
  return TRX_LIGHT_Do_On_Till($hash, @a) if($command eq "on-till");

  # special for on-for-timer
  return TRX_LIGHT_Do_On_For_Timer($hash, @a) if($command eq "on-for-timer");

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

  if (	lc($hash->{TRX_LIGHT_devicelog}) eq "window" || lc($hash->{TRX_LIGHT_devicelog}) eq "door" || 
   	lc($hash->{TRX_LIGHT_devicelog}) eq "motion" ||
	lc($hash->{TRX_LIGHT_devicelog}) eq "lightsensor" || lc($hash->{TRX_LIGHT_devicelog}) eq "photosensor" ||
	lc($hash->{TRX_LIGHT_devicelog}) eq "lock"
      ) {
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
	my $l = join(" ", sort @$rec); 
	if ($device_type eq "AC" || $device_type eq "HOMEEASY" || $device_type eq "ANSLUT") {
  		$l =~ s/ level / level:slider,0,1,15 /; 
	}
  	#my $error = "Unknown command $command, choose one of $l"; 
  	my $error = "Unknown command $command, choose one of $l "."on-till on-for-timer"; 

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
		return "error set name=$name  deviceid=$deviceid";
  	}

	# lightning1
  	$hex_prefix = sprintf "0710";
  	$hex_command = sprintf "%02x%02x%02x%02x%02x00", $device_type_num & 0xff, $seqnr, $house, $unit, $cmnd; 
  	Log 1,"TRX_LIGHT_Set name=$name device_type=$device_type, deviceid=$deviceid house=$house, unit=$unit command=$command" if ($TRX_LIGHT_debug == 1);
  	Log 1,"TRX_LIGHT_Set hexline=$hex_prefix$hex_command" if ($TRX_LIGHT_debug == 1);
  } elsif ($protocol_type == 0x11) {
	# lightning2
  	if (uc($deviceid) =~ /^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/ ) {
		;
  	} else {
		Log 4,"TRX_LIGHT_Set lightning2 wrong deviceid: name=$name device_type=$device_type, deviceid=$deviceid";
		return "error set name=$name  deviceid=$deviceid";
  	}
  	$hex_prefix = sprintf "0B11";
  	$hex_command = sprintf "%02x%02x%s%02x%02x00", $device_type_num & 0xff, $seqnr, $deviceid, $cmnd, $level; 
	if ($command eq "level") {
		$command .= sprintf " %d", $level;
	} 
  	Log 1,"TRX_LIGHT_Set lightning2 name=$name device_type=$device_type, deviceid=$deviceid command=$command" if ($TRX_LIGHT_debug == 1);
  	Log 1,"TRX_LIGHT_Set lightning2 hexline=$hex_prefix$hex_command" if ($TRX_LIGHT_debug == 1);
  } elsif ($protocol_type == 0x14) {
	# lightning4
  	if (uc($deviceid) =~ /^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/ ) {
		;
  	} else {
		Log 4,"TRX_LIGHT_Set lightning2 wrong deviceid: name=$name device_type=$device_type, deviceid=$deviceid";
		return "error set name=$name  deviceid=$deviceid";
  	}
  	$hex_prefix = sprintf "0A14";
  	$hex_command = sprintf "%02x%02x%s%02x%02x00", $device_type_num & 0xff, $seqnr, $deviceid, $cmnd, $level; 
	if ($command eq "level") {
		$command .= sprintf " %d", $level;
	} 
  	Log 1,"TRX_LIGHT_Set lightning4 name=$name device_type=$device_type, deviceid=$deviceid command=$command" if ($TRX_LIGHT_debug == 1);
  	Log 1,"TRX_LIGHT_Set lightning4 hexline=$hex_prefix$hex_command" if ($TRX_LIGHT_debug == 1);
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

  if ($type ne "X10" && $type ne "ARC" && $type ne "MS14A" && $type ne "AB400D" && $type ne "WAVEMAN" && $type ne "EMW200" && $type ne "IMPULS" && $type ne "RISINGSUN" && $type ne "PHILIPS_SBC" && $type ne "AC" && $type ne "HOMEEASY" && $type ne "ANSLUT" && $type ne "KOPPLA" && $type ne "LIGHTWAVERF" && $type ne "EMW100" && $type ne "BBSB") {
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

  if ($dev_type eq "BBSB") { return " "; } # ignore BBSB messages temporarily because of receiving problems  

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
  } elsif ($type == 0x14) {
  	$device = sprintf '%02x%02x%02x%02x', $bytes->[3], $bytes->[4], $bytes->[5], $bytes->[6];
  	$data = $bytes->[7];
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

  if (lc($def->{TRX_LIGHT_devicelog}) eq "window" || lc($def->{TRX_LIGHT_devicelog}) eq "door") {
		$command = ($command eq "on") ? "Open" : "Closed" ;
  } elsif (lc($def->{TRX_LIGHT_devicelog}) eq "motion") {
		$command = ($command eq "on") ? "alert" : "normal" ;
  } elsif (lc($def->{TRX_LIGHT_devicelog}) eq "lightsensor" || lc($def->{TRX_LIGHT_devicelog}) eq "photosensor") {
		$command = ($command eq "on") ? "dark" : "bright" ;
  } elsif (lc($def->{TRX_LIGHT_devicelog}) eq "lock") {
                $command = ($command eq "on") ? "Closed" : "Open" ;
  }

  readingsBeginUpdate($def);

  if ($type == 0x10 || $type == 0x11 || $type == 0x14) {
	# try to use it for all types:
	$current = $command;
	if ($type == 0x11 && $command eq "level") {
		# append level number
		my $level = $bytes->[9];
		$current .= sprintf " %d", $level;
	} elsif ($type == 0x14 && $command eq "level") {
		# append level number
		my $level = $bytes->[8];
		$current .= sprintf " %d", $level;
	}

	$sensor = $firstdevice == 1 ? $def->{TRX_LIGHT_devicelog} : $def->{TRX_LIGHT_devicelog2};
	$val .= $current;
	readingsBulkUpdate($def, $sensor, $current);
  } else {
	$error = sprintf "TRX_LIGHT: error unknown sensor type=%x device_type=%s devn=%s first=%d command=%s", $type, $device_type, $device_name, $firstdevice, $command;
	Log 1, $error;
	return $error;
  }

  if (($firstdevice == 1) && $val) {
  	#$def->{STATE} = $val;
	readingsBulkUpdate($def, "state", $val);
  }

  readingsEndUpdate($def, 1);

  return $name;
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
    return "";
  }

  my $type = $rfxcom_data_array[0];

  #Log 1, "TRX_LIGHT: num_bytes=$num_bytes hex=$hexline type=$type" if ($TRX_LIGHT_debug == 1);
  my $res = "";
  if ($type == 0x10 || $type == 0x11 || $type == 0x12 || $type == 0x14) {
	Log 1, "TRX_LIGHT: X10 num_bytes=$num_bytes hex=$hexline" if ($TRX_LIGHT_debug == 1);
        $res = TRX_LIGHT_parse_X10(\@rfxcom_data_array);
  	Log 1, "TRX_LIGHT: unsupported hex=$hexline" if ($res eq "");
	return $res;
  } else {
	Log 0, "TRX_LIGHT: not implemented num_bytes=$num_bytes hex=$hexline";
  }

  return "";
}

1;

=pod
=begin html

<a name="TRX_LIGHT"></a>
<h3>TRX_LIGHT</h3>
<ul>
  The TRX_LIGHT module receives and sends X10, ARC, ELRO AB400D, Waveman, Chacon EMW200, IMPULS, RisingSun, AC, HomeEasy EU and ANSLUT lighting devices (switches and remote control). Allows to send Philips SBC (receive not possible). ARC is a protocol used by devices from HomeEasy, KlikAanKlikUit, ByeByeStandBy, Intertechno, ELRO, AB600, Duewi, DomiaLite and COCO with address code wheels. AC is the protocol used by different brands with units having a learning mode button:
KlikAanKlikUit, NEXA, CHACON, HomeEasy UK. <br> You need to define an RFXtrx433 transceiver receiver first.
  See <a href="#TRX">TRX</a>.

  <br><br>

  <a name="TRX_LIGHTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TRX_LIGHT &lt;type&gt; &lt;deviceid&gt; &lt;devicelog&gt; [&lt;deviceid2&gt; &lt;devicelog2&gt;] </code> <br>
    <br>
    <code>&lt;type&gt;</code>
    <ul>
      specifies the type of the device: <br>
    X10 lighting devices:
        <ul>
          <li> <code>MS14A</code> (X10 motion sensor. Reports [normal|alert] on the first deviceid (motion sensor) and [on|off] for the second deviceid (light sensor)) </li>
          <li> <code>X10</code> (All other x10 devices. Report [off|on|dim|bright|all_off|all_on] on both deviceids.)</li>
          <li> <code>ARC</code> (ARC devices. ARC is a protocol used by devices from HomeEasy, KlikAanKlikUit, ByeByeStandBy, Intertechno, ELRO, AB600, Duewi, DomiaLite and COCO with address code wheels. Report [off|on|all_off|all_on|chime].)</li>
          <li> <code>AB400D</code> (ELRO AB400D devices. Report [off|on].)</li>
          <li> <code>WAVEMAN</code> (Waveman devices. Report [off|on].)</li>
          <li> <code>EMW200</code> (Chacon EMW200 devices. Report [off|on|all_off|all_on].)</li>
          <li> <code>IMPULS</code> (IMPULS devices. Report [off|on].)</li>
          <li> <code>RISINGSUN</code> (RisingSun devices. Report [off|on].)</li>
          <li> <code>PHILIPS_SBC</code> (Philips SBC devices. Send [off|on|all_off|all_on].)</li>
          <li> <code>AC</code> (AC devices. AC is the protocol used by different brands with units having a learning mode button: KlikAanKlikUit, NEXA, CHACON, HomeEasy UK. Report [off|on|level &lt;NUM&gt;|all_off|all_on|all_level &lt;NUM&gt;].)</li>
          <li> <code>HOMEEASY</code> (HomeEasy EU devices. Report [off|on|level|all_off|all_on|all_level].)</li>
          <li> <code>ANSLUT</code> (Anslut devices. Report [off|on|level|all_off|all_on|all_level].)</li>
        </ul>
    </ul>
    <br>
    <code>&lt;deviceid&gt;</code>
    <ul>
    specifies the first device id of the device. <br>
    A lighting device normally has a house code A..P followed by a unitcode 1..16 (example "B1").<br>
    For AC, HomeEasy EU and ANSLUT it is a 10 Character-Hex-String for the deviceid, consisting of <br>
	- unid-id: 8-Char-Hex: 00000001 to 03FFFFFF<br>
	- unit-code: 2-Char-Hex: 01 to 10  <br>
    </ul>
    <br>
    <code>&lt;devicelog&gt;</code>
    <ul>
    is the name of the Reading used to report. Suggested: "motion" for motion sensors.
    </ul>
    <br>
    <code>&lt;deviceid2&gt;</code>
    <ul>
    is optional and specifies the second device id of the device if it exists. For example ms14a motion sensors report motion status on the first deviceid and the status of the light sensor on the second deviceid.
    </ul>
    <br>
    <code>&lt;devicelog2&gt;</code>
    <ul>
    is optional for the name used for the Reading of <code>&lt;deviceid2&gt;</code>.
    </ul>
    <br>
      Example: <br>
    	<code>define motion_sensor2 TRX_LIGHT MS14A A1 motion A2 light</code>
	<br>
    	<code>define Steckdose TRX_LIGHT ARC G2 light</code>
	<br>
    	<code>define light TRX_LIGHT AC 0101010101 light</code>
      <br>
  </ul>
  <br>

  <a name="TRX_LIGHTset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;levelnum&gt;]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    off
    on
    dim                # only for X10, KOPPLA
    bright             # only for X10, KOPPLA
    all_off            # only for X10, ARC, EMW200, AC, HOMEEASY, ANSLUT
    all_on             # only for X10, ARC, EMW200, AC, HOMEEASY, ANSLUT
    chime              # only for ARC
    level &lt;levelnum&gt;    # only AC, HOMEEASY, ANSLUT: set level to &lt;levelnum&gt; (range: 0=0% to 15=100%)
    on-till           # Special, see the note
    on-for-timer      # Special, see the note
    </pre>
      Example: <br>
    	<code>set Steckdose on</code>
      <br>
    <br>
    Notes:
    <ul>
      <li><code>on-till</code> requires an absolute time in the "at" format
          (HH:MM:SS, HH:MM) or { &lt;perl code&gt; }, where the perl code
          returns a time specification).
          If the current time is greater than the specified time, then the
          command is ignored, else an "on" command is generated, and for the
          given "till-time" an off command is scheduleld via the at command.
          </li>
      <li><code>on-for-timer</code> requires a relative time in the "at" format
          (HH:MM:SS, HH:MM) or { &lt;perl code&gt; }, where the perl code
          returns a time specification).
          </li>
    </ul>
  </ul><br>

  <a name="TRX_LIGHTget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="TRX_LIGHTattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
  </ul>

</ul>

=end html
=cut
