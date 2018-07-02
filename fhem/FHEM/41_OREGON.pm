#################################################################################
# $Id$
#
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
# (c) 2010-2014 Copyright: Willi Herzig (Willi.Herzig@gmail.com)
# modified & fixes Ralf9 2015-2016 
# fixes Sidey79 2016
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

package main;

use strict;
use warnings;

my $time_old = 0;

sub
OREGON_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*", #38-78
  $hash->{DefFn}     = "OREGON_Define";
  $hash->{UndefFn}   = "OREGON_Undef";
  $hash->{ParseFn}   = "OREGON_Parse";
  $hash->{AttrList}  = "IODev ignore:0,1 do_not_notify:1,0 showtime:1,0"
                      ." $readingFnAttributes";
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
sub OREGON_hi_nibble {
  ($_[0]&0xf0)>>4;
}
sub OREGON_lo_nibble {
  $_[0]&0xf;
}
sub OREGON_nibble_sum {
  my $c = $_[0];
  my $s = 0;
  foreach (0..$_[0]-1) {
    $s += OREGON_hi_nibble($_[1]->[$_]);
    $s += OREGON_lo_nibble($_[1]->[$_]);
  }
  $s += OREGON_hi_nibble($_[1]->[$_[0]]) if (int($_[0]) != $_[0]);
  return $s;
}

# --------------------------------------------
# From xpl-perl/lib/xPL/RF/Oregon.pm:
# This function creates a simple key from a device type and message
# length (in bits).  It is used to as the index for the parts table.
sub OREGON_type_length_key {
  ($_[0] << 8) + $_[1]
}

# --------------------------------------------
# types from xpl-perl/lib/xPL/RF/Oregon.pm
# Changes: Use pointers to subs for method to allow strict use

my %types =
  (
   # THGR810 v3
   OREGON_type_length_key(0xfa28, 80) =>
   {
    part => 'THGR810', checksum => \&OREGON_checksum2, method => \&OREGON_common_temphydro,
   },
   # WTGR800 Temp hydro v3
   OREGON_type_length_key(0xfab8, 80) =>
   {
    part => 'WTGR800_T', checksum => \&OREGON_checksum2, method => \&OREGON_alt_temphydro,
   },
   # WTGR800 Anenometer v3
   OREGON_type_length_key(0x1a99, 88) =>
   {
    part => 'WTGR800_A', checksum => \&OREGON_checksum4, method => \&OREGON_wtgr800_anemometer,
   },
   # WGR800 v3
   OREGON_type_length_key(0x1a89, 88) =>
   {
    part => 'WGR800', checksum => \&OREGON_checksum4, method => \&OREGON_wtgr800_anemometer,
   },
   # UVN800 v3
   OREGON_type_length_key(0xda78, 72) =>
   {
    part => 'UVN800', checksum => \&OREGON_checksum7, method => \&OREGON_uvn800,
   },
   OREGON_type_length_key(0xea7c, 120) =>
   {
    part => 'UV138', checksum => \&OREGON_checksum1, method => \&OREGON_uv138,
   },
   OREGON_type_length_key(0xea4c, 80) =>
   {
    part => 'THWR288A', checksum => \&OREGON_checksum1, method => \&OREGON_common_temp,
   },
   # THN132N
   OREGON_type_length_key(0xea4c, 64) =>
   {
    part => 'THN132N', checksum => \&OREGON_checksum1, method => \&OREGON_common_temp,
   },
   # 
   OREGON_type_length_key(0x9aec, 104) =>
   {
    part => 'RTGR328N', checksum => \&OREGON_checksum3, method => \&OREGON_rtgr328n_datetime,
   },
   # 
   OREGON_type_length_key(0x9aea, 104) =>
   {
    part => 'RTGR328N', checksum => \&OREGON_checksum3, method => \&OREGON_rtgr328n_datetime,
   },
   # THGN122N,THGR122NX,THGR228N,THGR268
   OREGON_type_length_key(0x1a2d, 80) =>
   {
    part => 'THGR228N', checksum => \&OREGON_checksum2, method => \&OREGON_common_temphydro,
   },
   # THGR918
   OREGON_type_length_key(0x1a3d, 80) =>
   {
    part => 'THGR918', checksum => \&OREGON_checksum2, method => \&OREGON_common_temphydro,
   },
   # BTHR918
   OREGON_type_length_key(0x5a5d, 88) =>
   {
    part => 'BTHR918', checksum => \&OREGON_checksum5plus, method => \&OREGON_common_temphydrobaro,
   },
   # BTHR918N, BTHR968
   OREGON_type_length_key(0x5a6d, 88) =>
   {
    part => 'BTHR918N', checksum => \&OREGON_checksum5, method => \&OREGON_alt_temphydrobaro,
   },
   # 
   OREGON_type_length_key(0x3a0d, 80) =>
   {
    part => 'WGR918',  checksum => \&OREGON_checksum4, method => \&OREGON_wgr918_anemometer,
   },
   # RGR126, RGR682, RGR918:
   OREGON_type_length_key(0x2a1d, 80) =>
   {
    part => 'RGR918', checksum => \&OREGON_checksum6plus, method => \&OREGON_common_rain,
   },
   # 
   OREGON_type_length_key(0x0a4d, 80) =>
   {
    part => 'THR128', checksum => \&OREGON_checksum2, method => \&OREGON_common_temp,
   },
   # THGR328N
   OREGON_type_length_key(0xca2c, 80) =>
   {
    part => 'THGR328N', checksum => \&OREGON_checksum2, method => \&OREGON_common_temphydro,
   },
   # 
   OREGON_type_length_key(0xca2c, 120) =>
   {
    part => 'THGR328N', checksum => \&OREGON_checksum2, method => \&OREGON_common_temphydro,
   },
   # masked
   OREGON_type_length_key(0x0acc, 80) =>
   {
    part => 'RTGR328N', checksum => \&OREGON_checksum2, method => \&OREGON_common_temphydro,
   },
   # PCR800. v3
   OREGON_type_length_key(0x2a19, 92) =>
   {
    part => 'PCR800', checksum => \&OREGON_checksum8, method => \&OREGON_rain_PCR800,
   },
   # THWR800 v3
   OREGON_type_length_key(0xca48, 68) =>
   {
    part => 'THWR800', checksum => \&OREGON_checksum9, method => \&OREGON_common_temp,
   },
   OREGON_type_length_key(0x0adc, 64) =>  # masked to ?adc due to rolling code
   {
     part => 'RTHN318', checksum => \&OREGON_checksum1, method => \&OREGON_common_temp,
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

sub OREGON_temperature {
  my ($bytes, $dev, $res) = @_;

  my $temp =
    (($bytes->[6]&0x8) ? -1 : 1) *
      (OREGON_hi_nibble($bytes->[5])*10 + OREGON_lo_nibble($bytes->[5]) +
       OREGON_hi_nibble($bytes->[4])/10);

  push @$res, {
       		device => $dev,
       		type => 'temp',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

sub OREGON_humidity {
  my ($bytes, $dev, $res) = @_;
  my $hum = OREGON_lo_nibble($bytes->[7])*10 + OREGON_hi_nibble($bytes->[6]);
  my $hum_str = ['normal', 'comfortable', 'dry', 'wet']->[$bytes->[7]>>6];
  push @$res, {
		device => $dev,
                type => 'humidity',
                current => $hum,
                string => $hum_str,
		units => '%'
	}
}

sub OREGON_pressure {
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

sub OREGON_simple_battery {
  my ($bytes, $dev, $res) = @_;
  my $battery_low = $bytes->[4]&0x4;
  #my $bat = $battery_low ? 10 : 90;
  my $battery = $battery_low ? "low" : "ok";
  push @$res, {
		device => $dev,
		type => 'battery',
		current => $battery,
		units => '%',
	}, 
	{
		device => $dev,
		type => 'batteryState',
		current => $battery,
		units => '',
	}
}

sub OREGON_percentage_battery {
  my ($bytes, $dev, $res) = @_;

  my $battery;
  my $batteryState;
  my $battery_level = 100-10*OREGON_lo_nibble($bytes->[4]);
  if ($battery_level > 50) {
    $battery = sprintf("ok %d%%",$battery_level);
    $batteryState="ok";
  } else {
    $battery = sprintf("low %d%%",$battery_level);
    $batteryState="low";
  }

  push @$res, {
		device => $dev,
		type => 'battery',
		current => $battery,
		units => '%',
	}, {
		device => $dev,
		type => 'batteryPercent',
		current => $battery_level,
		units => '%',
	},
	{
		device => $dev,
		type => 'batteryState',
		current => $batteryState,
		units => '',
	}
	
	
}

my @uv_str =
  (
   qw/low low low/, # 0 - 2
   qw/medium medium medium/, # 3 - 5
   qw/high high/, # 6 - 7
   'very high', 'very high', 'very high', # 8 - 10
  );

sub OREGON_uv_string {
  $uv_str[$_[0]] || 'dangerous';
}

sub OREGON_uv {
  my ($bytes, $dev, $res) = @_;
  my $uv =  OREGON_lo_nibble($bytes->[5])*10 + OREGON_hi_nibble($bytes->[4]);
  my $risk = OREGON_uv_string($uv);

  push @$res, {
		device => $dev,
		type => 'uv',
		current => $uv,
		risk => $risk,
	}
}

sub OREGON_uv2 {
  my ($bytes, $dev, $res) = @_;
  my $uv =  OREGON_hi_nibble($bytes->[4]);
  my $risk = OREGON_uv_string($uv);

  push @$res, {
		device => $dev,
		type => 'uv',
		current => $uv,
		risk => $risk,
	}
}

# Test if to use longid for device type
sub OREGON_use_longid {
  my ($longids,$dev_type) = @_;

  return 0 if ($longids eq "");
  return 0 if ($longids eq "NONE");
  return 0 if ($longids eq "0");

  return 1 if ($longids eq "1");
  return 1 if ($longids eq "ALL");

  return 1 if(",$longids," =~ m/,$dev_type,/);

  return 0;
}

# --------------------------------------------------------

sub OREGON_uv138 {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();

  OREGON_uv($bytes, $dev_str, \@res);
  OREGON_simple_battery($bytes, $dev_str, \@res);

  return @res;
}

sub OREGON_uvn800 {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();

  OREGON_uv2($bytes, $dev_str, \@res);
  OREGON_percentage_battery($bytes, $dev_str, \@res);

  return @res;
}


sub OREGON_wgr918_anemometer {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();

  my $dir = sprintf("%02x",$bytes->[5])*10 + OREGON_hi_nibble($bytes->[4]);
  my $dirname = $OREGON_winddir_name[$dir/22.5];
  my $speed = OREGON_lo_nibble($bytes->[7]) * 10 + sprintf("%02x",$bytes->[6])/10;
  my $avspeed = sprintf("%02x",$bytes->[8]) + OREGON_hi_nibble($bytes->[7]) / 10;

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
  OREGON_percentage_battery($bytes, $dev_str, \@res);

  return @res;
}


# -----------------------------
sub OREGON_wtgr800_anemometer {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();

  my $dir = OREGON_hi_nibble($bytes->[4]) % 16;
  my $dirname = $OREGON_winddir_name[$dir];
  $dir = $dir * 22.5;
  my $speed = OREGON_lo_nibble($bytes->[7]) * 10 + sprintf("%02x",$bytes->[6])/10;
  my $avspeed = sprintf("%02x",$bytes->[8]) + OREGON_hi_nibble($bytes->[7]) / 10;

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
  OREGON_percentage_battery($bytes, $dev_str, \@res);

  return @res;
}

# -----------------------------
sub OREGON_alt_temphydro {
    	my $type = shift;
  	my $longids = shift;
    	my $bytes = shift;

  #
  my $hex_line = "";
  for (my $i=0;$i<=9;$i++) {
   	$hex_line .= sprintf("%02x",$bytes->[$i]);
  } 
  
  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }
  my @res = ();

  OREGON_temperature($bytes, $dev_str, \@res);
  OREGON_humidity($bytes, $dev_str, \@res);
  OREGON_percentage_battery($bytes, $dev_str, \@res);
  
  return @res;
}


# -----------------------------
sub OREGON_alt_temphydrobaro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my @res = ();

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  OREGON_temperature($bytes, $dev_str, \@res);
  OREGON_humidity($bytes, $dev_str, \@res);
  OREGON_pressure($bytes, $dev_str, \@res, OREGON_hi_nibble($bytes->[9]), 856);
  OREGON_percentage_battery($bytes, $dev_str, \@res);

  return @res;
}

# -----------------------------
sub OREGON_rtgr328n_datetime {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my $time =
    (
     OREGON_lo_nibble($bytes->[7]).OREGON_hi_nibble($bytes->[6]).
     OREGON_lo_nibble($bytes->[6]).OREGON_hi_nibble($bytes->[5]).
     OREGON_lo_nibble($bytes->[5]).OREGON_hi_nibble($bytes->[4])
    );
  my $day =
    [ 'Mon', 'Tue', 'Wed',
      'Thu', 'Fri', 'Sat', 'Sun' ]->[($bytes->[9]&0x7)-1];
  my $date =
    2000+(OREGON_lo_nibble($bytes->[10]).OREGON_hi_nibble($bytes->[9])).
      sprintf("%02d",OREGON_hi_nibble($bytes->[8])).
        OREGON_lo_nibble($bytes->[8]).OREGON_hi_nibble($bytes->[7]);

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
sub OREGON_common_temp {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();
  OREGON_temperature($bytes, $dev_str, \@res);
  OREGON_simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
sub OREGON_common_temphydro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();
  OREGON_temperature($bytes, $dev_str, \@res);
  OREGON_humidity($bytes, $dev_str, \@res);
  OREGON_simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
sub OREGON_common_temphydrobaro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();
  OREGON_temperature($bytes, $dev_str, \@res);
  OREGON_humidity($bytes, $dev_str, \@res);
  OREGON_pressure($bytes, $dev_str, \@res, OREGON_lo_nibble($bytes->[9]));
  OREGON_simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
sub OREGON_common_rain {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();
  my $rain = sprintf("%02x",$bytes->[5])*10 + OREGON_hi_nibble($bytes->[4]);
  my $train = OREGON_lo_nibble($bytes->[8])*1000 +
    sprintf("%02x", $bytes->[7])*10 + OREGON_hi_nibble($bytes->[6]);
  my $flip = OREGON_lo_nibble($bytes->[6]);
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
  OREGON_simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
# under development............
sub OREGON_rain_PCR800 {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  #
  my $hexline = "";
  for (my $i=0;$i<=10;$i++) {
   	$hexline .= sprintf("%02x",$bytes->[$i]);
  } 
  
  my $device = sprintf "%02x", $bytes->[3];
  #my $dev_str = $type.$DOT.$device;
  my $dev_str = $type;
  if (OREGON_use_longid($longids,$type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if (OREGON_hi_nibble($bytes->[2]) > 0) {
  	$dev_str .= $DOT.sprintf("%d", OREGON_hi_nibble($bytes->[2]));
  }

  my @res = ();

  my $rain = OREGON_lo_nibble($bytes->[6])*10 + sprintf("%02x",$bytes->[5])/10 + OREGON_hi_nibble($bytes->[4])/100;
  $rain *= 25.4; # convert from inch to mm

  my $train = OREGON_lo_nibble($bytes->[9])*100 + sprintf("%02x",$bytes->[8]) + 
	sprintf("%02x",$bytes->[7])/100 + OREGON_hi_nibble($bytes->[6])/1000;
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
  OREGON_simple_battery($bytes, $dev_str, \@res);
  return @res;
}

# -----------------------------
# CHECKSUM METHODS

sub OREGON_checksum1 {
  my $hash = $_[1];
  my $c = OREGON_hi_nibble($_[0]->[6]) + (OREGON_lo_nibble($_[0]->[7]) << 4);
  my $s = ( ( OREGON_nibble_sum(6, $_[0]) + OREGON_lo_nibble($_[0]->[6]) - 0xa) & 0xff);
  Log3 $hash, 5, "OREGON: checksum1 = $c berechnet: $s";
  $s == $c;
}

sub OREGON_checksum2 {
  my $hash = $_[1];
  my $c = $_[0]->[8];
  my $s = ((OREGON_nibble_sum(8,$_[0]) - 0xa) & 0xff);
  Log3 $hash, 5, "OREGON: checksum2 = $c berechnet: $s";
  $s == $c;
}

sub OREGON_checksum3 {
  $_[0]->[11] == ((OREGON_nibble_sum(11,$_[0]) - 0xa) & 0xff);
}

sub OREGON_checksum4 {
  $_[0]->[9] == ((OREGON_nibble_sum(9,$_[0]) - 0xa) & 0xff);
}

sub OREGON_checksum5 {
  $_[0]->[10] == ((OREGON_nibble_sum(10,$_[0]) - 0xa) & 0xff);
}

sub OREGON_checksum5plus {
  my $hash = $_[1];
  my $c = ($_[0]->[10]);
  
  my $s = ((OREGON_nibble_sum(10,$_[0]) - 0xa) & 0xff);
  Log3 $hash, 5, "OREGON: checksum5plus = $c berechnet: $s";
  $s == $c;
}

sub OREGON_checksum6 {
  OREGON_hi_nibble($_[0]->[8]) + (OREGON_lo_nibble($_[0]->[9]) << 4) ==
    ((OREGON_nibble_sum(8,$_[0]) - 0xa) & 0xff);
}

sub OREGON_checksum6plus {
  my $hash = $_[1];
  my $c = OREGON_hi_nibble($_[0]->[8]) + (OREGON_lo_nibble($_[0]->[9]) << 4);
  my $s = (((OREGON_nibble_sum(8,$_[0]) + (($_[0]->[8] & 0x0f) - 0x00)) - 0xa) & 0xff);
  Log3 $hash, 5, "OREGON: checksum6plus = $c berechnet: $s";
  $s == $c;
}

sub OREGON_checksum7 {
  $_[0]->[7] == ((OREGON_nibble_sum(7,$_[0]) - 0xa) & 0xff);
}

sub OREGON_checksum8 {
  my $hash = $_[1];
  my $c = OREGON_hi_nibble($_[0]->[9]) + (OREGON_lo_nibble($_[0]->[10]) << 4);
  my $s = ( ( OREGON_nibble_sum(9, $_[0]) + OREGON_lo_nibble($_[0]->[9]) - 0xa) & 0xff);
  Log3 $hash, 5, "OREGON: checksum8 = $c berechnet: $s";
  $s == $c;
}

sub OREGON_checksum9 {
  my $hash = $_[1];
  my $c = OREGON_hi_nibble($_[0]->[6]) + (OREGON_lo_nibble($_[0]->[7]) << 4);
  my $s = ((OREGON_nibble_sum(6,$_[0]) - 0xa) & 0xff);
  Log3 $hash, 5, "OREGON: checksum9 = $c berechnet: $s";
  $s == $c;
}
  
  
sub OREGON_raw {
  $_[0]->{raw} or $_[0]->{raw} = pack 'H*', $_[0]->{hex};
}


# -----------------------------
sub
OREGON_Parse($$)
{
  my ($iohash, $msg) = @_;

  my $longids = 1;
  if (defined($attr{$iohash->{NAME}}{longids})) {
  	$longids = $attr{$iohash->{NAME}}{longids};
  	#Log 1,"0: attr longids = $longids";
  }

  my $time = time();
  if ($time_old ==0) {
  	Log3 $iohash, 5, "OREGON: decoding delay=0 hex=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log3 $iohash, 5, "OREGON: decoding delay=$time_diff hex=$msg";
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
  my $bitsMsg = $bits;
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }

  my $type1 = $rfxcom_data_array[0];
  my $type2 = $rfxcom_data_array[1];
	
  my $type = ($type1 << 8) + $type2;

  my $sensor_id = unpack('H*', chr $type1) . unpack('H*', chr $type2);

  my $key = OREGON_type_length_key($type, $bits);
  my $rec = $types{$key} || $types{$key&0xfffff};
  if (!$rec) {
     $bits -= 4;
     $key = OREGON_type_length_key($type, $bits);
     $rec = $types{$key} || $types{$key&0xfffff};
     if (!$rec) {
          $bits -= 4;
          $key = OREGON_type_length_key($type, $bits);
          $rec = $types{$key} || $types{$key&0xfffff};
          if (!$rec) {
               Log3 $iohash, 4, "OREGON: ERROR: Unknown sensor_id=$sensor_id bits=$bitsMsg message='$msg'.";
               return "";
          }
     }
  }
  Log3 $iohash, 5, "OREGON: sensor_id=$sensor_id BitsMsg=$bitsMsg Bits=$bits";

  # test checksum as defines in %types:
  my $checksum = $rec->{checksum};
  if ($checksum && !$checksum->(\@rfxcom_data_array, $iohash) ) {
    Log3 $iohash, 4, "OREGON: ERROR: checksum error sensor_id=$sensor_id (bits=$bits)";
    return "";
  }

  my $method = $rec->{method};
  unless ($method) {
    Log3 $iohash, 4, "OREGON: Possible message from Oregon part '$rec->{part}'";
    Log3 $iohash, 4, "OREGON: sensor_id=$sensor_id (bits=$bits)";
    return "";
  }

  my @res;

  if (! defined(&$method)) {
    Log3 $iohash, 4, "OREGON: Error: Unknown function=$method. Please define it in file $0";
    Log3 $iohash, 4, "OREGON: sensor_id=$sensor_id (bits=$bits)\n";
    return "";
  } else {
    @res = $method->($rec->{part}, $longids, \@rfxcom_data_array);
  }

  # get device name from first entry
  my $device_name = $res[0]->{device};
  #Log 1, "device_name=$device_name";

  my $def = $modules{OREGON}{defptr}{"$device_name"};
  if(!$def) {
	Log3 $iohash, 3, "OREGON: Unknown device $device_name, please define it";
    	return "UNDEFINED $device_name OREGON $device_name";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  #Log 1, "name=$new_name";
  return "" if(IsIgnored($name));

  my $n = 0;
  my $tm = TimeNow();

  my $i;
  my $val = "";
  my $sensor = "";
  readingsBeginUpdate($def);

  foreach $i (@res){
  	
 	#print "!> i=".$i."\n";
	#printf "%s\t",$i->{device};
	if ($i->{type} eq "temp") { 
			#printf "Temperatur %2.1f %s ; ",$i->{current},$i->{units};
			$val .= "T: ".$i->{current}." ";
			
			readingsBulkUpdate($def,"temperature",$i->{current});
			
			##$sensor = "temperature";		
				
			##$def->{READINGS}{$sensor}{TIME} = $tm;
			##$def->{READINGS}{$sensor}{VAL} = $i->{current};
			##$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};*/
  	} 
	elsif ($i->{type} eq "humidity") { 
			#printf "Luftfeuchtigkeit %d%s, %s ;",$i->{current},$i->{units},$i->{string};
			$val .= "H: ".$i->{current}." ";
			readingsBulkUpdate($def,"humidity",$i->{current});

			##$sensor = "humidity";			
			##$def->{READINGS}{$sensor}{TIME} = $tm;
			##$def->{READINGS}{$sensor}{VAL} = $i->{current};
			##$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};
	}
	elsif ($i->{type} eq "battery") { 
			#printf "Batterie %d%s; ",$i->{current},$i->{units};
			my @words = split(/\s+/,$i->{current});
			$val .= "BAT: ".$words[0]." "; #use only first word
			
			readingsBulkUpdate($def,"battery",$i->{current});

			##$sensor = "battery";			
			##$def->{READINGS}{$sensor}{TIME} = $tm;
			##$def->{READINGS}{$sensor}{VAL} = $i->{current};
			##$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}	elsif ($i->{type} eq "batterPercent" || $i->{type} eq "batteryState") { 
			readingsBulkUpdate($def,$i->{type},$i->{current});
	}
	elsif ($i->{type} eq "pressure") { 
			#printf "Luftdruck %d %s, Vorhersage=%s ; ",$i->{current},$i->{units},$i->{forecast};
			# do not add it due to problems with hms.gplot
			$val .= "P: ".$i->{current}."  ";
			readingsBulkUpdate($def,"pressure",$i->{current});
			readingsBulkUpdate($def,"forecast",$i->{forecast});
			
			#$sensor = "pressure";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			#$sensor = "forecast";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{forecast};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{forecast};;
	}
	elsif ($i->{type} eq "speed") { 
			$val .= "W: ".$i->{current}." ";
			$val .= "WA: ".$i->{average}." ";
			readingsBulkUpdate($def,"wind_speed",$i->{current});
			readingsBulkUpdate($def,"wind_avspeed",$i->{average});

			#$sensor = "wind_speed";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			#$sensor = "wind_avspeed";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{average};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{average};;
	}
	elsif ($i->{type} eq "direction") { 
			$val .= "WD: ".$i->{current}."  ";
			$val .= "WDN: ".$i->{string}."  ";
			readingsBulkUpdate($def,"wind_dir",$i->{current} . " " . $i->{string});

			#$sensor = "wind_dir";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current} . " " . $i->{string};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current} . " " . $i->{string};;
	}
	elsif ($i->{type} eq "rain") { 
			$val .= "RR: ".$i->{current}." ";
			readingsBulkUpdate($def,"rain_rate",$i->{current});

			#$sensor = "rain_rate";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "train") { 
			$val .= "TR: ".$i->{current}."  ";
			readingsBulkUpdate($def,"rain_total",$i->{current});

			#$sensor = "rain_total";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "flip") { 
			#$val .= "F: ".$i->{current}." ";
			readingsBulkUpdate($def,"rain_flip",$i->{current});

			#$sensor = "rain_flip";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "uv") { 
			$val .= "UV: ".$i->{current}."  ";
			$val .= "UVR: ".$i->{risk}."  ";
			readingsBulkUpdate($def,"uv_val",$i->{current});
			readingsBulkUpdate($def,"uv_risk",$i->{risk});

			#$sensor = "uv_val";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			#$sensor = "uv_risk";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{risk};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{risk};;
	}
	elsif ($i->{type} eq "hexline") { 
			readingsBulkUpdate($def,"hexline",$i->{current});
		
			#$sensor = "hexline";			
			#$def->{READINGS}{$sensor}{TIME} = $tm;
			#$def->{READINGS}{$sensor}{VAL} = $i->{current};
			#$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
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

    Log3 $iohash, 4, "$name decoded Oregon: $val";
    readingsBulkUpdate($def, "state", $val);
    
    $def->{STATE} = $val;
    #$def->{TIME} = $tm;
    #$def->{CHANGED}[$n++] = $val;
  }
  

  #
  #$def->{READINGS}{state}{TIME} = $tm;
  #$def->{READINGS}{state}{VAL} = $val;
  #$def->{CHANGED}[$n++] = "state: ".$val;
  readingsEndUpdate($def, 1);

  #DoTrigger($name, undef);

  return $name;
}

1;

=pod
=item summary    interprets Oregon sensors received by a rf receiver
=item summary_DE interpretiert Oregon Sensoren von einem Funkempf&aumlngern
=begin html

<a name="OREGON"></a>
<h3>OREGON</h3>
<ul>
  The OREGON module interprets Oregon sensor messages received by a RFXCOM or SIGNALduino or CUx receiver. You need to define a receiver (RFXCOM, SIGNALduino or CUx) first.
  See <a href="#RFXCOM">RFXCOM</a>.
  See <a href="#SIGNALduino">SIGNALduino</a>.
  <br><br>

  <a name="OREGONdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OREGON &lt;deviceid&gt;</code> <br>
    <br>
    &lt;deviceid&gt; is the device identifier of the Oregon sensor. It consists of the sensors name and a one byte hex string (00-ff) that identifies the sensor. The define statement with the deviceid is generated automatically by autocreate. The following sensor names are used:
BTHR918, BTHR918N, PCR800 RGR918, RTGR328N, THN132N, THGR228N, THGR328N, THGR918, THR128, THWR288A, THGR810, UV138, UVN800, WGR918, WGR800, WTGR800_A, WTGR800_T.
    <br>
The one byte hex string is generated by the Oregon sensor when is it powered on. The value seems to be randomly generated. This has the advantage that you may use more than one Oregon sensor of the same type even if it has no switch to set a sensor id. For exampple the author uses three BTHR918 sensors at the same time. All have different deviceids. The drawback is that the deviceid changes after changing batteries.
    <br><br>
      Example: <br>
    <code>define Kaminzimmer OREGON BTHR918N_ab</code>
      <br>
  </ul>
  <br>

  <a name="OREGONset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="OREGONget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="OREGONattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>

=end html
=cut
