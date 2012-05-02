##############################################
#
# Dewpoint computing 
#
# based / modified from 98_average.pm (C) by Rudolf Koenig
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
# $Id$
#
package main;
use strict;
use warnings;

# Debug this module? YES = 1, NO = 0
my $dewpoint_debug = 0;

##########################
sub
dewpoint_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "dewpoint_Define";
  $hash->{NotifyFn} = "dewpoint_Notify";
  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "disable:0,1";
}


##########################
sub
dewpoint_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> dewpoint (dewpoint|fan|alarm) devicename [options]"
    if(@a < 4);


  my $name = $a[0];
  my $cmd_type = $a[2]; # dewpoint, fan, alarm
  my $devname = $a[3];

  if ($cmd_type eq "dewpoint") {
	# define <name> dewpoint dewpoint devicename-regex [temp_name hum_name new_name]
  	if(@a == 7) {
  		$hash->{TEMP_NAME} = $a[4];
  		$hash->{HUM_NAME} = $a[5];
  		$hash->{NEW_NAME} = $a[6];
  	} elsif (@a == 4) {
  		$hash->{TEMP_NAME} = "temperature";
  		$hash->{HUM_NAME} = "humidity";
  		$hash->{NEW_NAME} = "dewpoint";
	} else {
		return "wrong syntax: define <name> dewpoint dewpoint devicename-regex [temp_name hum_name new_name]"
	}
  } elsif ($cmd_type eq "fan") {
	# define <name> dewpoint fan devicename-regex devicename-outside min_temp
  	if(@a == 6) {
  		$hash->{DEVNAME_OUT} = $a[4];
  		$hash->{MIN_TEMP} = $a[5];
	} else {
		return "wrong syntax: define <name> dewpoint fan devicename-regex devicename-outside min_temp"
	}
  } elsif ($cmd_type eq "alarm") {
	# define <name> dewpoint alarm devicename-regex devicename-reference diff_temp
  	if(@a == 6) {
  		$hash->{DEVNAME_REF} = $a[4];
  		$hash->{DIFF_TEMP} = $a[5];
	} else {
		return "wrong syntax: define <name> dewpoint alarm devicename-regex devicename-reference diff_temp"
	}
  } else {
  	return "wrong syntax: define <name> dewpoint (dewpoint|fan|alarm) devicename-regex [options]"
  }

  $hash->{CMD_TYPE} = $cmd_type;

  eval { "Hallo" =~ m/^$devname$/ };
  return "Bad regecaxp: $@" if($@);
  $hash->{DEV_REGEXP} = $devname;


  $hash->{STATE} = "active";
  return undef;
}

##########################
sub
dewpoint_Notify($$)
{
  my ($hash, $dev) = @_;
  my $hashName = $hash->{NAME};

  return "" if(AttrVal($hashName, "disable", undef));
  return "" if(!defined($hash->{DEV_REGEXP}));

  my $devName = $dev->{NAME};

  my $cmd_type = $hash->{CMD_TYPE};
  my $re = $hash->{DEV_REGEXP};

  # dewpoint
  my $temp_name = "temperature";
  my $hum_name = "humidity";
  my $new_name = "dewpoint";
  # fan
  my $devname_out = "";
  my $min_temp = 0;
  # alarm
  my $devname_ref = "";
  my $diff_temp = 0;


  if ($cmd_type eq "dewpoint") {
  	if (!defined($hash->{TEMP_NAME}) || !defined($hash->{HUM_NAME}) || !defined($hash->{NEW_NAME})) {
		# should never happen!
		Log 1, "Error dewpoint: TEMP_NAME || HUM_NAME || NEW_NAME undefined";
		return "";
  	}
  	$temp_name = $hash->{TEMP_NAME};
  	$hum_name = $hash->{HUM_NAME};
  	$new_name = $hash->{NEW_NAME};
  	Log 1, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, dev_regex=$re temp_name=$temp_name hum_name=$hum_name" if ($dewpoint_debug == 1);
  } elsif ($cmd_type eq "fan") {
  	if (!defined($hash->{DEVNAME_OUT}) || !defined($hash->{MIN_TEMP})) {
		# should never happen!
		Log 1, "Error dewpoint: DEVNAME_OUT || MIN_TEMP undefined";
		return "";
  	}
	$devname_out = $hash->{DEVNAME_OUT};
	$min_temp = $hash->{MIN_TEMP};
  	Log 1, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, dev_regex=$re, devname_out=$devname_out, min_temp=$min_temp" if ($dewpoint_debug == 1);

  } elsif ($cmd_type eq "alarm") {
  	if (!defined($hash->{DEVNAME_REF}) || !defined($hash->{DIFF_TEMP})) {
		# should never happen!
		Log 1, "Error dewpoint: DEVNAME_REF || DIFF_TEMP undefined";
		return "";
  	}
	$devname_ref = $hash->{DEVNAME_REF};
	$diff_temp = $hash->{DIFF_TEMP};
  	Log 1, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, dev_regex=$re, devname_ref=$devname_ref, diff_temp=$diff_temp" if ($dewpoint_debug == 1);
  } else {
	# should never happen:
	Log 1, "Error notify_dewpoint: <1> unknown cmd_type ".$cmd_type;
	return "";
  }

  my $max = int(@{$dev->{CHANGED}});
  my $tn;
  my $n = -1;
  my $lastval;

  return "" if($devName !~ m/^$re$/);

  my $temperature = "";
  my $humidity = "";

  for (my $i = 0; $i < $max; $i++) {
    	my $s = $dev->{CHANGED}[$i];

    	Log 1, "dewpoint_notify: s='$s'" if ($dewpoint_debug == 1);

    	################
    	# Filtering
    	next if(!defined($s));
    	my ($evName, $val, $rest) = split(" ", $s, 3); # resets $1
    	next if(!defined($evName));
    	Log 1, "dewpoint_notify: evName='$evName' val=$val'" if ($dewpoint_debug == 1);
	if (($evName eq "T:") && ($temp_name eq "T")) {
		$n = $i;
   		#my ($evName1, $val1, $evName2, $val2, $rest) = split(" ", $s, 5); # resets $1
		#$lastval = $evName1." ".$val1." ".$evName2." ".$val2;		
		$lastval = $s;
		if ($s =~ /T: [-+]?([0-9]*\.[0-9]+|[0-9]+)/) {	
			$temperature = $1;
		}
		if ($s =~ /H: [-+]?([0-9]*\.[0-9]+|[0-9]+)/) {	
			$humidity = $1;
		}
    		Log 1, "dewpoint_notify T: H:, temp=$temperature hum=$humidity" if ($dewpoint_debug == 1);
	} elsif ($evName eq $temp_name.":") {
		$temperature = $val;
    		Log 1, "dewpoint_notify temperature! temp=$temperature" if ($dewpoint_debug == 1);
	} elsif ($evName eq $hum_name.":") {
		$humidity = $val;
    		Log 1, "dewpoint_notify humidity! hum=$humidity" if ($dewpoint_debug == 1);
	}
 
  }

  if ($n == -1) { $n = $max; }

  if (($temperature eq "") || ($humidity eq "")) { return undef; } # no way to calculate dewpoint!

  # We found temperature and humidity. so we can calculate dewpoint first
  
  my $dewpoint = sprintf("%.1f", dewpoint_dewpoint($temperature,$humidity));
  Log 1, "dewpoint_notify: dewpoint=$dewpoint" if ($dewpoint_debug == 1);

  if ($cmd_type eq "dewpoint") {
	# >define <name> dewpoint dewpoint <devicename> [<temp_name> <hum_name> <new_name>]
	#
	# Calculates dewpoint for device <devicename> from temperature and humidity and write it 
	# to new Reading dewpoint. 
	# If optional <temp_name>, <hum_name> and <newname> is specified
	# then read temperature from reading <temp_name>, humidity from reading <hum_name>
	# and write dewpoint to reading <temp_name>.
	# if temp_name eq "T" then use temperature from state T: H:, add <newname> to the state
	# Example:
	# define dewtest1 dewpoint dewpoint .*
	# define dewtest2 dewpoint dewpoint .* T H D
	my $sensor = $new_name;
	my $current;
	if ($temp_name ne "T") {
		$current = $dewpoint;
        	$tn = TimeNow();
		$dev->{READINGS}{$sensor}{TIME} = $tn;
		$dev->{READINGS}{$sensor}{VAL} = $current;
		$dev->{CHANGED}[$n++] = $sensor . ": " . $current;
	} else {
		# state begins with "T:". append dewpoint or insert before BAT
		if ($lastval =~ /BAT:/) {	
			$current = $lastval;
			$current =~ s/BAT:/$sensor: $dewpoint BAT:/g;
		} else {
			$current = $lastval." ".$sensor.": ".$dewpoint;
		}
		$dev->{STATE} = $current;
		$dev->{CHANGED}[$n++] = $current;
	}

    	Log 1, "dewpoint_notify: current=$current" if ($dewpoint_debug == 1);
  } elsif ($cmd_type eq "fan") {
	# >define <name> dewpoint fan devicename devicename-outside min-temp
	#
	#  This define may be used to turn an fan on or off if the outside air has less
	#  water 
	#
	# - Generate reading/event "fan: on" if dewpoint of <devicename-outside> is lower 
	#   than dewpoint of <devicename> and temperature of <devicename-outside> is >= min-temp
	#   and reading "fan" was not already "on".
	# - Generate reading/event "fan: off": else and if reading "fan" was not already "off".
	Log 1, "dewpoint_notify: fan devname_out=$devname_out, min_temp=$min_temp" if ($dewpoint_debug == 1);
	my $sensor;
	my $current;
	if (exists $defs{$devname_out}{READINGS}{temperature}{VAL} && exists $defs{$devname_out}{READINGS}{humidity}{VAL}) {
		my $temperature_out = $defs{$devname_out}{READINGS}{temperature}{VAL};
		my $humidity_out = $defs{$devname_out}{READINGS}{humidity}{VAL};
		my $dewpoint_out = sprintf("%.1f", dewpoint_dewpoint($temperature_out,$humidity_out));;
		Log 1, "dewpoint_notify: fan dewpoint_out=$dewpoint_out" if ($dewpoint_debug == 1);
		if ($dewpoint_out < $dewpoint && $temperature_out >= $min_temp) {
			$current = "on";
			Log 1, "dewpoint_notify: fan ON" if ($dewpoint_debug == 1);
		} else {
			$current = "off";
			Log 1, "dewpoint_notify: fan OFF" if ($dewpoint_debug == 1);
		}
		$sensor = "fan";
		if (!exists $defs{$devName}{READINGS}{$sensor}{VAL} || $defs{$devName}{READINGS}{$sensor}{VAL} ne $current) {
			Log 1, "dewpoint_notify: CHANGE fan $current" if ($dewpoint_debug == 1);
        		$tn = TimeNow();
			$dev->{READINGS}{$sensor}{TIME} = $tn;
			$dev->{READINGS}{$sensor}{VAL} = $current;
			$dev->{CHANGED}[$n++] = $sensor . ": " . $current;
		}

	} else {
		Log 1, "dewpoint_notify: fan devname_out=$devname_out no temperature or humidity available for dewpoint calculation" if ($dewpoint_debug == 1);
	}
  } elsif ($cmd_type eq "alarm") {
	# >define <name> dewpoint alarm devicename devicename-reference diff
	#
	# - Generate reading/event "alarm: on" if temperature of <devicename-reference>-<diff> is lower 
	#   than dewpoint of <devicename> and reading "alarm" was not already "on".
	# - Generate reading/event "alarm: off" if temperature of <devicename-reference>-<diff> is higher 
	#   than dewpoint of <devicename> and reading "alarm" was not already "off".
	#
	#  You have different options to use this define:
	#  * Use a temperature sensor in or on the wall (<devicename-reference>) and use a temp/hum sensor
	#    to measure the dewpoint of the air. Alarm if the temperature of the wall is lower than the dewpoint of the air.
	#    In this case the water of the air will condense on the wall because the wall is cold.
	# 	Example: define alarmtest dewpoint alarm roomsensor wallsensor 0
	#  * If you do not have a temperature sensor in/on the wall, you may also compare the rooms dewpoint to the
	#    temperature of the same or another inside sensor. If you think that your walls are normally 5 degrees colder
	#    than the inside temperature, set diff to 5. 
	# 	Example: define alarmtest dewpoint alarm roomsensor roomsensor 5
	Log 1, "dewpoint_notify: alarm devname_ref=$devname_ref, diff_temp=$diff_temp" if ($dewpoint_debug == 1);
	my $sensor;
	my $current;
	if (exists $defs{$devname_ref}{READINGS}{temperature}{VAL}) {
		my $temperature_ref = $defs{$devname_ref}{READINGS}{temperature}{VAL};
		Log 1, "dewpoint_notify: alarm temperature_ref=$temperature_ref" if ($dewpoint_debug == 1);
		if ($temperature_ref - $diff_temp < $dewpoint) {
			$current = "on";
			Log 1, "dewpoint_notify: alarm ON" if ($dewpoint_debug == 1);
		} else {
			$current = "off";
			Log 1, "dewpoint_notify: alarm OFF" if ($dewpoint_debug == 1);
		}
		$sensor = "alarm";
		if (!exists $defs{$devName}{READINGS}{$sensor}{VAL} || $defs{$devName}{READINGS}{$sensor}{VAL} ne $current) {
			Log 1, "dewpoint_notify: CHANGE alarm $current" if ($dewpoint_debug == 1);
        		$tn = TimeNow();
			$dev->{READINGS}{$sensor}{TIME} = $tn;
			$dev->{READINGS}{$sensor}{VAL} = $current;
			$dev->{CHANGED}[$n++] = $sensor . ": " . $current;
		}
	} else {
		Log 1, "dewpoint_notify: alarm devname_out=$devname_out no temperature or humidity available for dewpoint calculation" if ($dewpoint_debug == 1);
	}

  } else {
	# should never happen:
	Log 1, "Error notify_dewpoint: <2> unknown cmd_type ".$cmd_type;
	return "";
  }

  return undef;
}

# -----------------------------
# Dewpoint calculation.
# see http://www.faqs.org/faqs/meteorology/temp-dewpoint/ "5. EXAMPLE"
sub
dewpoint_dewpoint($$)
{
        my ($temperature, $humidity) = @_;

        my $dp;

        my $A = 17.2694;
        my $B = ($temperature > 0) ? 237.3 : 265.5;
        my $es = 610.78 * exp( $A * $temperature / ($temperature + $B) );
        my $e = $humidity/ 100 * $es;
        if ($e == 0) {
                Log 1, "Error: dewpoint() e==0: temp=$temperature, hum=$humidity";
                return 0;
        }
        my $e1 = $e / 610.78;
        my $f = log( $e1 ) / $A;
        my $f1 = 1 - $f;
        if ($f1 == 0) {
                Log 1, "Error: dewpoint() (1-f)==0: temp=$temperature, hum=$humidity";
                return 0;
        }
        $dp = $B * $f / $f1  ;
        return($dp);
}

1;

