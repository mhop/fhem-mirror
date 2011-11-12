#################################################################################
# 41_OREGON.pm
# Module for FHEM to decode Oregon sensor messages
#
# derived from 18_CUL-HOERMANN.pm
#
# This code is derived from http://www.xpl-perl.org.uk/.
# Thanks a lot to Mark Hindess who wrote xPL.
#
# Special thanks to RFXCOM, http://www.rfxcom.com/, for their
# help. I own an USB-RFXCOM-Receiver (433.92MHz, USB, order code 80002)
# and highly recommend it.
#
# Willi Herzig, 2010
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##################################
#
# Most of the subs are copied and modified from xpl-perl 
# from the following two files:
#	xpl-perl/lib/xPL/Utils.pm:
#	xpl-perl/lib/xPL/RF/Oregon.pm:
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
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
# $Id$
package main;

use strict;
use warnings;

my $time_old = 0;

sub
OREGON_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^[\x38-\x78].*";
  #$hash->{Match}     = "^[^\x30]";
  $hash->{DefFn}     = "OREGON_Define";
  $hash->{UndefFn}   = "OREGON_Undef";
  $hash->{ParseFn}   = "OREGON_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
OREGON_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> OREGON code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];

  $hash->{CODE} = $code;
  #$modules{OREGON}{defptr}{$name} = $hash;
  $modules{OREGON}{defptr}{$code} = $hash;
  AssignIoPort($hash);

  return undef;
}

#####################################
sub
OREGON_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{OREGON}{defptr}{$name});
  return undef;
}



#########################################
# From xpl-perl/lib/xPL/Util.pm:
sub hi_nibble {
  ($_[0]&0xf0)>>4;
}
sub lo_nibble {
  $_[0]&0xf;
}
sub nibble_sum {
  my $c = $_[0];
  my $s = 0;
  foreach (0..$_[0]-1) {
    $s += hi_nibble($_[1]->[$_]);
    $s += lo_nibble($_[1]->[$_]);
  }
  $s += hi_nibble($_[1]->[$_[0]]) if (int($_[0]) != $_[0]);
  return $s;
}

# --------------------------------------------
# From xpl-perl/lib/xPL/RF/Oregon.pm:
# This function creates a simple key from a device type and message
# length (in bits).  It is used to as the index for the parts table.
sub type_length_key {
  ($_[0] << 8) + $_[1]
}

# --------------------------------------------
# types from xpl-perl/lib/xPL/RF/Oregon.pm
# Changes: Use pointers to subs for method to allow strict use

my %types =
  (
   # THGR810
   type_length_key(0xfa28, 80) =>
   {
    part => 'THGR810', checksum => \&checksum2, method => \&common_temphydro,
   },
   # WTGR800 Temp hydro
   type_length_key(0xfab8, 80) =>
   {
    part => 'WTGR800_T', checksum => \&checksum2, method => \&alt_temphydro,
   },
   # WTGR800 Anenometer
   type_length_key(0x1a99, 88) =>
   {
    part => 'WTGR800_A', checksum => \&checksum4, method => \&wtgr800_anemometer,
   },
   # 
   type_length_key(0x1a89, 88) =>
   {
    part => 'WGR800', checksum => \&checksum4, method => \&wtgr800_anemometer,
   },
   type_length_key(0xda78, 72) =>
   {
    part => 'UVN800', checksun => \&checksum7, method => \&uvn800,
   },
   type_length_key(0xea7c, 120) =>
   {
    part => 'UV138', checksum => \&checksum1, method => \&uv138,
   },
   type_length_key(0xea4c, 80) =>
   {
    part => 'THWR288A', checksum => \&checksum1, method => \&common_temp,
   },
   # 
   type_length_key(0xea4c, 68) =>
   {
    part => 'THN132N', checksum => \&checksum1, method => \&common_temp,
   },
   # 
   type_length_key(0x9aec, 104) =>
   {
    part => 'RTGR328N', checksum => \&checksum3, method => \&rtgr328n_datetime,
   },
   # 
   type_length_key(0x9aea, 104) =>
   {
    part => 'RTGR328N', checksum => \&checksum3, method => \&rtgr328n_datetime,
   },
   # THGN122N,THGR122NX,THGR228N,THGR268
   type_length_key(0x1a2d, 80) =>
   {
    part => 'THGR228N', checksum => \&checksum2, method => \&common_temphydro,
   },
   # THGR918
   type_length_key(0x1a3d, 80) =>
   {
    part => 'THGR918', checksum => \&checksum2, method => \&common_temphydro,
   },
   # BTHR918
   type_length_key(0x5a5d, 88) =>
   {
    part => 'BTHR918', checksum => \&checksum5, method => \&common_temphydrobaro,
   },
   # BTHR918N, BTHR968
   type_length_key(0x5a6d, 96) =>
   {
    part => 'BTHR918N', checksum => \&checksum5, method => \&alt_temphydrobaro,
   },
   # 
   type_length_key(0x3a0d, 80) =>
   {
    part => 'WGR918',  checksum => \&checksum4, method => \&wgr918_anemometer,
   },
   # 
   type_length_key(0x3a0d, 88) =>
   {
    part => 'WGR918',  checksum => \&checksum4, method => \&wgr918_anemometer,
   },
   # RGR126, RGR682, RGR918:
   type_length_key(0x2a1d, 84) =>
   {
    part => 'RGR918', checksum => \&checksum6plus, method => \&common_rain,
   },
   # 
   type_length_key(0x0a4d, 80) =>
   {
    part => 'THR128', checksum => \&checksum2, method => \&common_temp,
   },
   # THGR328N
   type_length_key(0xca2c, 80) =>
   {
    part => 'THGR328N', checksum => \&checksum2, method => \&common_temphydro,
   },
   # 
   type_length_key(0xca2c, 120) =>
   {
    part => 'THGR328N', checksum => \&checksum2, method => \&common_temphydro,
   },
   # masked
   type_length_key(0x0acc, 80) =>
   {
    part => 'RTGR328N', checksum => \&checksum2, method => \&common_temphydro,
   },
   # PCR800. Commented out until fully tested.
   type_length_key(0x2a19, 92) =>
   {
    part => 'PCR800', checksum => \&checksum8, method => \&rain_PCR800,
   },
  );

# --------------------------------------------

#my $DOT = q{.};
# Important: change it to _, because FHEM uses regexp
my $DOT = q{_};

my @OREGON_winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");

# --------------------------------------------
# The following functions are changed:
#	- some parameter like "parent" and others are removed
#	- @res array return the values directly (no usage of xPL::Message)

sub temperature {
  my ($bytes, $dev, $res) = @_;

  my $temp =
    (($bytes->[6]&0x8) ? -1 : 1) *
      (hi_nibble($bytes->[5])*10 + lo_nibble($bytes->[5]) +
       hi_nibble($bytes->[4])/10);

  push @$res, {
       		device => $dev,
       		type => 'temp',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

sub humidity {
  my ($bytes, $dev, $res) = @_;
  my $hum = lo_nibble($bytes->[7])*10 + hi_nibble($bytes->[6]);
  my $hum_str = ['normal', 'comfortable', 'dry', 'wet']->[$bytes->[7]>>6];
  push @$res, {
		device => $dev,
                type => 'humidity',
                current => $hum,
                string => $hum_str,
		units => '%'
	}
}

sub pressure {
  my ($bytes, $dev, $res, $forecast_nibble, $offset) = @_;
  $offset = 795 unless ($offset);
  my $hpa = $bytes->[8]+$offset;
  my $forecast = { 0xc => 'sunny',
                   0x6 => 'partly',
                   0x2 => 'cloudy',
                   0x3 => 'rain',
                 }->{$forecast_nibble} || 'unknown';
  push @$res, {
		device => $dev,
                type => 'pressure',
                current => $hpa,
                units => 'hPa',
                forecast => $forecast,
   	}
}

sub simple_battery {
  my ($bytes, $dev, $res) = @_;
  my $battery_low = $bytes->[4]&0x4;
  my $bat = $battery_low ? 10 : 90;
  push @$res, {
		device => $dev,
		type => 'battery',
		current => $bat,
		units => '%',
	}
}

sub percentage_battery {
  my ($bytes, $dev, $res) = @_;
  my $bat = 100-10*lo_nibble($bytes->[4]);
  push @$res, {
		device => $dev,
		type => 'battery',
		current => $bat,
		units => '%',
	}
}

my @uv_str =
  (
   qw/low low low/, # 0 - 2
   qw/medium medium medium/, # 3 - 5
   qw/high high/, # 6 - 7
   'very high', 'very high', 'very high', # 8 - 10
  );

sub uv_string {
  $uv_str[$_[0]] || 'dangerous';
}

sub uv {
  my ($bytes, $dev, $res) = @_;
  my $uv =  lo_nibble($bytes->[5])*10 + hi_nibble($bytes->[4]);
  my $risk = uv_string($uv);

  push @$res, {
		device => $dev,
		type => 'uv',
		current => $uv,
		risk => $risk,
	}
}

sub uv2 {
  my ($bytes, $dev, $res) = @_;
  my $uv =  hi_nibble($bytes->[4]);
  my $risk = uv_string($uv);

  push @$res, {
		device => $dev,
		type => 'uv',
		current => $uv,
		risk => $risk,
	}
}

# --------------------------------------------------------

sub uv138 {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;

  my @res = ();

  uv($bytes, $dev_str, \@res);
  simple_battery($bytes, $dev_str, \@res);

  return @res;
}

sub uvn800 {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;

  my @res = ();

  uv2($bytes, $dev_str, \@res);
  percentage_battery($bytes, $dev_str, \@res);

  return @res;
}


sub wgr918_anemometer {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;

  my @res = ();

  my $dir = sprintf("%02x",$bytes->[5])*10 + hi_nibble($bytes->[4]);
  my $dirname = $OREGON_winddir_name[$dir/22.5];
  my $speed = lo_nibble($bytes->[7]) * 10 + sprintf("%02x",$bytes->[6])/10;
  my $avspeed = sprintf("%02x",$bytes->[8]) + hi_nibble($bytes->[7]) / 10;

  push @res, {
                               device => $dev_str,
                               type => 'speed',
                               current => $speed,
                               average => $avspeed,
                               units => 'mps',
                              } , {
                               device => $dev_str,
                               type => 'direction',
                               current => $dir,
                               string => $dirname,
                               units => 'degrees',
                              } 
  ;
  percentage_battery($bytes, $dev_str, \@res);

  return @res;
}


# -----------------------------
sub wtgr800_anemometer {
    	my $type = shift;
    	my $bytes = shift;

  	my $device = sprintf "%02x", $bytes->[3];
  	my $dev_str = $type.$DOT.$device;

	my @res = ();

  	my $dir = hi_nibble($bytes->[4]) % 16;
        my $dirname = $OREGON_winddir_name[$dir];
        $dir = $dir * 22.5;
	my $speed = lo_nibble($bytes->[7]) * 10 + sprintf("%02x",$bytes->[6])/10;
  	my $avspeed = sprintf("%02x",$bytes->[8]) + hi_nibble($bytes->[7]) / 10;

 	push @res, {
                               device => $dev_str,
                               type => 'speed',
                               current => $speed,
                               average => $avspeed,
                               units => 'mps',
                              } , {
                               device => $dev_str,
                               type => 'direction',
                               current => $dir,
                               string => $dirname,
                               units => 'degrees',
                              } 
	;
  	percentage_battery($bytes, $dev_str, \@res);

	return @res;
}

# -----------------------------
sub alt_temphydro {
    	my $type = shift;
    	my $bytes = shift;

  #
  my $hex_line = "";
  for (my $i=0;$i<=9;$i++) {
   	$hex_line .= sprintf("%02x",$bytes->[$i]);
  } 
  
  	my $device = sprintf "%02x", $bytes->[3];
  	my $dev_str = $type.$DOT.$device;
	my @res = ();

  	temperature($bytes, $dev_str, \@res);
  	humidity($bytes, $dev_str, \@res);
  	percentage_battery($bytes, $dev_str, \@res);
  
# hexline debugging
  #push @res, {
  #                             device => $dev_str,
  #                             type => 'hexline',
  #                             current => $hex_line,
  #                             units => 'hex',
  #                            };

	return @res;
}


# -----------------------------
sub alt_temphydrobaro {
    	my $type = shift;
    	my $bytes = shift;

	my @res = ();

  	my $device = sprintf "%02x", $bytes->[3];
  	my $dev_str = $type.$DOT.$device;

  	temperature($bytes, $dev_str, \@res);
  	humidity($bytes, $dev_str, \@res);
  	pressure($bytes, $dev_str, \@res, hi_nibble($bytes->[9]), 856);
  	percentage_battery($bytes, $dev_str, \@res);

	return @res;
}

# -----------------------------
sub rtgr328n_datetime {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;
  my $time =
    (
     lo_nibble($bytes->[7]).hi_nibble($bytes->[6]).
     lo_nibble($bytes->[6]).hi_nibble($bytes->[5]).
     lo_nibble($bytes->[5]).hi_nibble($bytes->[4])
    );
  my $day =
    [ 'Mon', 'Tue', 'Wed',
      'Thu', 'Fri', 'Sat', 'Sun' ]->[($bytes->[9]&0x7)-1];
  my $date =
    2000+(lo_nibble($bytes->[10]).hi_nibble($bytes->[9])).
      sprintf("%02d",hi_nibble($bytes->[8])).
        lo_nibble($bytes->[8]).hi_nibble($bytes->[7]);

  #print STDERR "datetime: $date $time $day\n";
  my @res = ();

  push @res, {
                                     datetime => $date.$time,
                                     'date' => $date,
                                     'time' => $time,
                                     day => $day.'day',
                                     device => $dev_str,
                                    };
  return @res;
}


# -----------------------------
sub common_temp {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;
  my @res = ();
  temperature($bytes, $dev_str, \@res);
  simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
sub common_temphydro {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;
  my @res = ();
  temperature($bytes, $dev_str, \@res);
  humidity($bytes, $dev_str, \@res);
  simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
sub common_temphydrobaro {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;
  my @res = ();
  temperature($bytes, $dev_str, \@res);
  humidity($bytes, $dev_str, \@res);
  pressure($bytes, $dev_str, \@res, lo_nibble($bytes->[9]));
  simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
sub common_rain {
  my $type = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;
  my @res = ();
  my $rain = sprintf("%02x",$bytes->[5])*10 + hi_nibble($bytes->[4]);
  my $train = lo_nibble($bytes->[8])*1000 +
    sprintf("%02x", $bytes->[7])*10 + hi_nibble($bytes->[6]);
  my $flip = lo_nibble($bytes->[6]);
  #print STDERR "$dev_str rain = $rain, total = $train, flip = $flip\n";
  push @res, {
                               device => $dev_str,
                               type => 'rain',
                               current => $rain,
                               units => 'mm/h',
                              } ;
  push @res, {
                               device => $dev_str,
                               type => 'train',
                               current => $train,
                               units => 'mm',
                              };
  push @res, {
                               device => $dev_str,
                               type => 'flip',
                               current => $flip,
                               units => 'flips',
                              };
  simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
# under development............
sub rain_PCR800 {
  my $type = shift;
  my $bytes = shift;

  #
  my $hexline = "";
  for (my $i=0;$i<=10;$i++) {
   	$hexline .= sprintf("%02x",$bytes->[$i]);
  } 
  
  my $device = sprintf "%02x", $bytes->[3];
  my $dev_str = $type.$DOT.$device;
  my @res = ();

  my $rain = lo_nibble($bytes->[6])*10 + sprintf("%02x",$bytes->[5])/10 + hi_nibble($bytes->[4])/100;
  $rain *= 25.4; # convert from inch to mm

  my $train = lo_nibble($bytes->[9])*100 + sprintf("%02x",$bytes->[8]) + 
	sprintf("%02x",$bytes->[7])/100 + hi_nibble($bytes->[6])/1000;
  $train *= 25.4; # convert from inch to mm

  push @res, {
                               device => $dev_str,
                               type => 'rain',
                               current => $rain,
                               units => 'mm/h',
                              } ;
  push @res, {
                               device => $dev_str,
                               type => 'train',
                               current => $train,
                               units => 'mm',
                              };
  # hexline debugging
  #push @res, {
  #                             device => $dev_str,
  #                             type => 'hexline',
  #                             current => $hexline,
  #                             units => 'hex',
  #                            };
  simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
# CHECKSUM METHODS

sub checksum1 {
  my $c = hi_nibble($_[0]->[6]) + (lo_nibble($_[0]->[7]) << 4);
  my $s = ( ( nibble_sum(6, $_[0]) + lo_nibble($_[0]->[6]) - 0xa) & 0xff);
  $s == $c;
}

sub checksum2 {
  $_[0]->[8] == ((nibble_sum(8,$_[0]) - 0xa) & 0xff);
}

sub checksum3 {
  $_[0]->[11] == ((nibble_sum(11,$_[0]) - 0xa) & 0xff);
}

sub checksum4 {
  $_[0]->[9] == ((nibble_sum(9,$_[0]) - 0xa) & 0xff);
}

sub checksum5 {
  $_[0]->[10] == ((nibble_sum(10,$_[0]) - 0xa) & 0xff);
}

sub checksum6 {
  hi_nibble($_[0]->[8]) + (lo_nibble($_[0]->[9]) << 4) ==
    ((nibble_sum(8,$_[0]) - 0xa) & 0xff);
}

sub checksum6plus {
  my $c = hi_nibble($_[0]->[8]) + (lo_nibble($_[0]->[9]) << 4);
  my $s = (((nibble_sum(8,$_[0]) + (($_[0]->[8] & 0x0f) - 0x00)) - 0xa) & 0xff);
  $s == $c;
}

sub checksum7 {
  $_[0]->[7] == ((nibble_sum(7,$_[0]) - 0xa) & 0xff);
}

sub checksum8 {
  my $c = hi_nibble($_[0]->[9]) + (lo_nibble($_[0]->[10]) << 4);
  my $s = ( ( nibble_sum(9, $_[0]) - 0xa) & 0xff);
  $s == $c;
}

sub raw {
  $_[0]->{raw} or $_[0]->{raw} = pack 'H*', $_[0]->{hex};
}

# -----------------------------

sub
OREGON_Parse($$)
{
  my ($hash, $msg) = @_;

  my $time = time();
  my $hexline = unpack('H*', $msg);
  if ($time_old ==0) {
  	Log 5, "OREGON: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "OREGON: decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $bits = ord($msg);
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }

  my $type1 = $rfxcom_data_array[0];
  my $type2 = $rfxcom_data_array[1];
	
  my $type = ($type1 << 8) + $type2;

  my $sensor_id = unpack('H*', chr $type1) . unpack('H*', chr $type2);
  #Log 1, "OREGON: sensor_id=$sensor_id";

  my $key = type_length_key($type, $bits);

  my $rec = $types{$key} || $types{$key&0xfffff};
  unless ($rec) {
#Log 3, "OREGON: ERROR: Unknown sensor_id=$sensor_id bits=$bits message='$hexline'.";
    Log 4, "OREGON: ERROR: Unknown sensor_id=$sensor_id bits=$bits message='$hexline'.";
    return "OREGON: ERROR: Unknown sensor_id=$sensor_id bits=$bits.\n";
  }
  
  # test checksum as defines in %types:
  my $checksum = $rec->{checksum};
  if ($checksum && !$checksum->(\@rfxcom_data_array) ) {
    Log 3, "OREGON: ERROR: checksum error sensor_id=$sensor_id (bits=$bits)";
    return "OREGON: ERROR: checksum error sensor_id=$sensor_id (bits=$bits)";
  }

  my $method = $rec->{method};
  unless ($method) {
    Log 4, "OREGON: Possible message from Oregon part '$rec->{part}'";
    Log 4, "OREGON: sensor_id=$sensor_id (bits=$bits)";
    return;
  }

  my @res;

  if (! defined(&$method)) {
    Log 4, "OREGON: Error: Unknown function=$method. Please define it in file $0";
    Log 4, "OREGON: sensor_id=$sensor_id (bits=$bits)\n";
    return "OREGON: Error: Unknown function=$method. Please define it in file $0";
  } else {
    @res = $method->($rec->{part}, \@rfxcom_data_array);
  }

  # get device name from first entry
  my $device_name = $res[0]->{device};
  #Log 1, "device_name=$device_name";

  my $def = $modules{OREGON}{defptr}{"$device_name"};
  if(!$def) {
	Log 3, "OREGON: Unknown device $device_name, please define it";
    	return "UNDEFINED $device_name OREGON $device_name";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  #Log 1, "name=$new_name";

  my $n = 0;
  my $tm = TimeNow();

  my $i;
  my $val = "";
  my $sensor = "";
  foreach $i (@res){
 	#print "!> i=".$i."\n";
	#printf "%s\t",$i->{device};
	if ($i->{type} eq "temp") { 
			#printf "Temperatur %2.1f %s ; ",$i->{current},$i->{units};
			$val .= "T: ".$i->{current}."  ";

			$sensor = "temperature";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};
  	} 
	elsif ($i->{type} eq "humidity") { 
			#printf "Luftfeuchtigkeit %d%s, %s ;",$i->{current},$i->{units},$i->{string};
			$val .= "H: ".$i->{current}."  ";

			$sensor = "humidity";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "battery") { 
			#printf "Batterie %d%s; ",$i->{current},$i->{units};
			# do not add it due to problems with hms.gplot
			#$val .= "Bat: ".$i->{current}." ";

			$sensor = "battery";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "pressure") { 
			#printf "Luftdruck %d %s, Vorhersage=%s ; ",$i->{current},$i->{units},$i->{forecast};
			# do not add it due to problems with hms.gplot
			#$val .= "P: ".$i->{current}."  ";

			$sensor = "pressure";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			$sensor = "forecast";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{forecast};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{forecast};;
	}
	elsif ($i->{type} eq "speed") { 
			$val .= "W: ".$i->{current}." ";
			$val .= "WA: ".$i->{average}." ";

			$sensor = "wind_speed";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			$sensor = "wind_avspeed";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{average};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{average};;
	}
	elsif ($i->{type} eq "direction") { 
			$val .= "WD: ".$i->{current}."  ";
			$val .= "WDN: ".$i->{string}."  ";

			$sensor = "wind_dir";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current} . " " . $i->{string};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current} . " " . $i->{string};;
	}
	elsif ($i->{type} eq "rain") { 
			$val .= "RR: ".$i->{current}." ";

			$sensor = "rain_rate";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "train") { 
			$val .= "TR: ".$i->{current}."  ";

			$sensor = "rain_total";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "flip") { 
			#$val .= "F: ".$i->{current}." ";

			$sensor = "rain_flip";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "uv") { 
			$val .= "UV: ".$i->{current}."  ";
			$val .= "UVR: ".$i->{risk}."  ";

			$sensor = "uv_val";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			$sensor = "uv_risk";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{risk};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{risk};;
	}
	elsif ($i->{type} eq "hexline") { 
			$sensor = "hexline";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	else { 
			print "\nOREGON: Unknown: "; 
			print "Type: ".$i->{type}.", ";
			print "Value: ".$i->{current}."\n";
	}
  }

  if ("$val" ne "") {
    # remove heading and trailing space chars from $val
    $val =~ s/^\s+|\s+$//g;

    $def->{STATE} = $val;
    $def->{TIME} = $tm;
    $def->{CHANGED}[$n++] = $val;
  }

  #
  #$def->{READINGS}{state}{TIME} = $tm;
  #$def->{READINGS}{state}{VAL} = $val;
  #$def->{CHANGED}[$n++] = "state: ".$val;

  DoTrigger($name, undef);

  return $val;
}

1;
