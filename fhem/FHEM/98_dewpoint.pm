# $Id$
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
package main;
use strict;
use warnings;

# Debug this module? YES = 1, NO = 0
my $dewpoint_debug = 0;
# default maximum time_diff for dewpoint
my $dewpoint_time_diff_default = 1; # 1 Second

##########################
sub
dewpoint_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "dewpoint_Define";
  $hash->{NotifyFn} = "dewpoint_Notify";
  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "max_timediff disable:0,1";
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
  	if (@a == 6 || @a == 7) {
  		$hash->{DEVNAME_OUT} = $a[4];
  		$hash->{MIN_TEMP} = $a[5];
		if (@a == 6) { 		
			$hash->{DIFF_TEMP} = 0;
		} else {
			$hash->{DIFF_TEMP} = $a[6];
		}
	} else {
		return "wrong syntax: define <name> dewpoint fan devicename-regex devicename-outside min_temp [diff_temp]"
	}
  } elsif ($cmd_type eq "alarm") {
	# define <name> dewpoint alarm devicename-regex devicename-reference diff_temp
  	if (@a == 6) {
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
	$diff_temp = $hash->{DIFF_TEMP};
  	Log 1, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, dev_regex=$re, devname_out=$devname_out, min_temp=$min_temp, diff_temp=$diff_temp" if ($dewpoint_debug == 1);

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
  my $time_diff;

  for (my $i = 0; $i < $max; $i++) {
    	my $s = $dev->{CHANGED}[$i];

    	Log 1, "dewpoint_notify: s='$s'" if ($dewpoint_debug == 1);

    	################
    	# Filtering
    	next if(!defined($s));
    	my ($evName, $val, $rest) = split(" ", $s, 3); # resets $1
    	next if(!defined($evName));
    	next if(!defined($val));
    	Log 1, "dewpoint_notify: evName='$evName' val=$val'" if ($dewpoint_debug == 1);
	if (($evName eq "T:") && ($temp_name eq "T")) {
		$n = $i;
   		#my ($evName1, $val1, $evName2, $val2, $rest) = split(" ", $s, 5); # resets $1
		#$lastval = $evName1." ".$val1." ".$evName2." ".$val2;		
		$lastval = $s;
		if ($s =~ /T: ([-+]?[0-9]*\.[0-9]+|[-+]?[0-9]+)/) {
			$temperature = $1;
		}
		if ($s =~ /H: [-+]?([0-9]*\.[0-9]+|[0-9]+)/) {	
			$humidity = $1;
		}
    		Log 1, "dewpoint_notify T: H:, temp=$temperature hum=$humidity" if ($dewpoint_debug == 1);
	} elsif ($evName eq $temp_name.":") {
		$temperature = $val;
    		Log 1, "dewpoint_notify temperature! dev=$devName, temp_name=$temp_name, temp=$temperature" if ($dewpoint_debug == 1);
	} elsif ($evName eq $hum_name.":") {
		$humidity = $val;
    		Log 1, "dewpoint_notify humidity! dev=$devName, hum_name=$hum_name, hum=$humidity" if ($dewpoint_debug == 1);
	}
 
  }

  if ($n == -1) { $n = $max; }

  #if (($temperature eq "") || ($humidity eq "")) { return undef; } # no way to calculate dewpoint!

  $time_diff = -1;
  if (($humidity eq "") && (($temperature eq ""))) {
	return undef;  # no way to calculate dewpoint!
  } elsif (($humidity eq "") && (($temperature ne ""))) { 
	# temperature set, but humidity not. Try to use a valid value from the appropiate reading
	if (defined($dev->{READINGS}{$hum_name}{VAL}) && defined($dev->{READINGS}{$temp_name}{TIME})) {
		# calculate time difference
		$time_diff = time() - time_str2num($dev->{READINGS}{$hum_name}{TIME});

		$humidity = $dev->{READINGS}{$hum_name}{VAL};
		Log 1,">dev=$devName, hum_name=$hum_name, reference humidity=$humidity ($time_diff), temp=$temperature" if ($dewpoint_debug == 1);
	} else { return undef; }
	# Check if Attribute timeout is set
	my $timeout = AttrVal($hash->{NAME},"max_timediff", undef);
	if (defined($timeout)) {
		Log 1,"dewpoint timeout=$timeout" if ($dewpoint_debug == 1); 
	} else { 
		$timeout = $dewpoint_time_diff_default;
	}
	if ($time_diff > 0 && $time_diff > $timeout) { return undef; }  
  } elsif (($temperature eq "") && ($humidity ne "")) { 
	# humdidity set, but temperature not. Try to use a valid value from the appropiate reading
	if (defined($dev->{READINGS}{$temp_name}{VAL}) && defined($dev->{READINGS}{$temp_name}{TIME})) {
		# calculate time difference
		$time_diff = time() - time_str2num($dev->{READINGS}{$temp_name}{TIME});

		$temperature = $dev->{READINGS}{$temp_name}{VAL};
		Log 1,">dev=$devName, temp_name=$temp_name, reference temperature=$temperature ($time_diff), hum=$humidity" if ($dewpoint_debug == 1);
	} else { return undef; }
	# Check if Attribute timeout is set
	my $timeout = AttrVal($hash->{NAME},"max_timediff", undef);
	if (defined($timeout)) {
		Log 1,"dewpoint timeout=$timeout" if ($dewpoint_debug == 1);
	} else { 
		$timeout = $dewpoint_time_diff_default;
	}
	if ($time_diff > 0 && $time_diff > $timeout) { return undef; }  
  } 

  # We found temperature and humidity. so we can calculate dewpoint first
  
  if ($humidity == 0) { return undef; }  # humdidity is no valid value to calculate dewpoint

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
		#Log 1,">dev=$devName, lastval='$lastval' devSTATE='".$dev->{STATE}."' state=".$dev->{READINGS}{state}{VAL}."'";
		# state begins with "T:". append dewpoint or insert before BAT
		if ($lastval =~ /BAT:/) {	
			$current = $lastval;
			$current =~ s/BAT:/$sensor: $dewpoint BAT:/g;
		} elsif ($lastval =~ /<</) {	
			$current = $lastval;
			$current =~ s/<</$sensor:$dewpoint   <</g;
		} else {
			$current = $lastval." ".$sensor.": ".$dewpoint;
		}
		$dev->{STATE} = $current; 
		$dev->{CHANGED}[$n++] = $current;
	}

    	Log 1, "dewpoint_notify: current=$current" if ($dewpoint_debug == 1);
  } elsif ($cmd_type eq "fan") {
	# >define <name> dewpoint fan devicename devicename-outside min-temp [diff-temp]
	#
	#  This define may be used to turn an fan on or off if the outside air has less
	#  water 
	#
	# - Generate reading/event "fan: on" if (dewpoint of <devicename-outside>) + diff_temp is lower 
	#   than dewpoint of <devicename> and temperature of <devicename-outside> is >= min-temp
	#   and reading "fan" was not already "on".
	# - Generate reading/event "fan: off": else and if reading "fan" was not already "off".
	Log 1, "dewpoint_notify: fan devname_out=$devname_out, min_temp=$min_temp, diff_temp=$diff_temp" if ($dewpoint_debug == 1);
	my $sensor;
	my $current;
	if (exists $defs{$devname_out}{READINGS}{temperature}{VAL} && exists $defs{$devname_out}{READINGS}{humidity}{VAL}) {
		my $temperature_out = $defs{$devname_out}{READINGS}{temperature}{VAL};
		my $humidity_out = $defs{$devname_out}{READINGS}{humidity}{VAL};
		my $dewpoint_out = sprintf("%.1f", dewpoint_dewpoint($temperature_out,$humidity_out));;
		Log 1, "dewpoint_notify: fan dewpoint_out=$dewpoint_out" if ($dewpoint_debug == 1);
		if (($dewpoint_out + $diff_temp) < $dewpoint && $temperature_out >= $min_temp) {
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


=pod
=begin html

<a name="dewpoint"></a>
<h3>dewpoint</h3>
<ul>
  Dewpoint calculations. Offers three different ways to use dewpoint: <br>
  <ul>
    <li><b>dewpoint</b><br>
        Compute additional event dewpoint from a sensor offering temperature and humidity.</li>
    <li><b>fan</b><br>
        Generate a event to turn a fan on if the outside air has less water than the inside.</li>
    <li><b>alarm</b><br>
        Generate a mold alarm if a reference temperature is lower that the current dewpoint.</li>
  <br>
  </ul>

  <a name="dewpointdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dewpoint dewpoint &lt;devicename-regex&gt; [&lt;temp_name&gt; &lt;hum_name&gt; &lt;new_name&gt;]</code><br>
    <br>
    <ul>
      	Calculates dewpoint for device &lt;devicename-regex&gt; from temperature and humidity
	and write it to a new reading named dewpoint.
	If optional &lt;temp_name&gt;, &lt;hum_name&gt; and &lt;new_name&gt; is specified
	then read temperature from reading &lt;temp_name&gt;, humidity from reading &lt;hum_name&gt;
	and write the calculated dewpoint to reading &lt;new_name&gt;.<br>
	If &lt;temp_name&gt; is T then use temperature from state T: H:, add &lt;new_name&gt; to the state.
    </ul>
    <br>

    Example:<PRE>
    # Compute the dewpoint for the temperature/humidity
    # events of the temp1 device and generate reading dewpoint.
    define dew_temp1 dewpoint dewpoint temp1
    define dew_temp1 dewpoint dewpoint temp1 temperature humidity dewpoint

    # Compute the dewpoint for the temperature/humidity
    # events of all devices offering temperature and humidity
    # and generate reading dewpoint.
    define dew_all dewpoint dewpoint .*
    define dew_all dewpoint dewpoint .* temperature humidity dewpoint

    # Compute the dewpoint for the temperature/humidity
    # events of the device Aussen_1 offering temperature and humidity
    # and insert is into STATE.
    define dew_state dewpoint dewpoint Aussen_1 T H D

    # Compute the dewpoint for the temperature/humidity
    # events of all devices offering temperature and humidity
    # and insert the result into the STATE.
    # Example STATE: "T: 10 H: 62.5" will change to
    # "T: 10 H: 62.5 D: 3.2"
    define dew_state dewpoint dewpoint .* T H D

    </PRE>
  </ul>

  <ul>
    <code>define &lt;name&gt; dewpoint fan &lt;devicename-regex&gt; &lt;devicename-outside&gt; &lt;min-temp&gt; [&lt;diff_temp&gt;]</code><br>
    <br>
    <ul>
      	May be used to turn an fan on or off if the outside air has less water.
	<ul>
        <li>
	Generate event "fan: on" if (dewpoint of &lt;devicename-outside&gt;) + &lt;diff_temp&gt; is lower
	than dewpoint of &lt;devicename&gt; and temperature of &lt;devicename-outside&gt; is &gt;= min-temp
	and reading "fan" was not already "on". The event will be generated for &lt;devicename&gt;. Parameter &lt;diff-temp&gt; is optional</li>
	<li>Generate event "fan: off": else and if reading "fan" was not already "off".</li>
	</ul>
    </ul>
    <br>

    Example:<PRE>
    # Generate event "fan: on" when dewpoint of Aussen_1 is first
    # time lower than basement_tempsensor and outside temperature is &gt;= 0
    # and change it to "fan: off" is this condition changes.
    # Set a switch on/off (fan_switch) depending on the state.
    define dew_fan1 dewpoint fan basement_tempsensor Aussen_1 0
    define dew_fan1_on notify basement_tempsensor.*fan:.*on set fan_switch on
    define dew_fan1_off notify basement_tempsensor.*fan:.*off set fan_switch off

    </PRE>
  </ul>

  <ul>
    <code>define &lt;name&gt; dewpoint alarm &lt;devicename-regex&gt; &lt;devicename-reference&gt; &lt;diff-temp&gt;</code><br>
    <br>
    <ul>
        Generate a mold alarm if a reference temperature is lower that the current dewpoint.
	<ul>
        <li>
	Generate reading/event "alarm: on" if temperature of &lt;devicename-reference&gt; - &lt;diff-temp&gt; is lower
	than dewpoint of &lt;devicename&gt; and reading "alarm" was not already "on". The event will be generated for &lt;devicename&gt;.</li>
	<li>Generate reading/event "alarm: off" if temperature of &lt;devicename-reference&gt; - &lt;diff-temp&gt; is 		higher than dewpoint of &lt;devicename&gt; and reading "alarm" was not already "off".</li>
	</ul>
    </ul>
    <br>

    Example:<PRE>
    # Using a wall temperature sensor (wallsensor) and a temp/hum sensor
    # (roomsensor) to alarm if the temperature of the wall is lower than
    # the dewpoint of the air. In this case the water of the air will
    # condense on the wall because the wall is cold.
    # Set a switch on (alarm_siren) if alarm is on using notify.
    define dew_alarm1 dewpoint alarm roomsensor wallsensor 0
    define roomsensor_alarm_on notify roomsensor.*alarm:.*on set alarm_siren on
    define roomsensor_alarm_off notify roomsensor.*alarm:.*off set alarm_siren off

    # If you do not have a temperature sensor in/on the wall, you may also
    # compare the rooms dewpoint to the temperature of the same or another
    # inside sensor. Alarm is temperature is 5 degrees colder than the
    # inside dewpointinside.
    define dev_alarm2 dewpoint alarm roomsensor roomsensor 5

    </PRE>
  </ul>

  <a name="dewpointset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="dewpointget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dewpointattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li>max_timediff<br>
        Maximum time difference in seconds allowed between the temperature and humidity values for a device. dewpoint uses the Readings for temperature or humidity if they are not delivered in the event. This is necessary for using dewpoint with event-on-change-reading. Also needed for sensors that do deliver temperature and humidity in different events like for example technoline sensors TX3TH.<br>
If not set default is 1 second.
      <br><br>
      Examples:<PRE>
# allow maximum time difference of 60 seconds
define dew_all dewpoint dewpoint .*
attr dew_all max_timediff 60
    </li><br>
  </ul>
</ul>


=end html
=begin html_DE
<a name="dewpoint"></a>
<h3>dewpoint</h3>
<ul>
  Berechnungen des Taupunkts. Es gibt drei Varianten, das Modul dewpoint zu verwenden: <br>
  <ul>
    <li><b>dewpoint</b>: Taupunkt<br>
        Erzeugt ein zus&auml;tzliches Ereignis "dewpoint" aus Temperatur- und Luftfeuchtewerten eines F&uuml;hlers.</li>
    <li><b>fan</b>: L&uuml;fter<br>
        Erzeugt ein Ereignis, um einen L&uuml;fter einzuschalten, wenn die Au&szlig;enluft weniger Wasser als die Raumluft enth&auml;lt.</li>
    <li><b>alarm</b>: Alarm<br>
        Erzeugt einen Schimmel-Alarm, wenn eine Referenz-Temperatur unter den Taupunkt f&auml;llt.</li>
  <br>
  </ul>

  <a name="dewpointdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dewpoint dewpoint &lt;devicename-regex&gt; [&lt;temp_name&gt; &lt;hum_name&gt; &lt;new_name&gt;]</code><br>
    <br>
    <ul>
    Berechnet den Taupunkt des Ger&auml;ts &lt;devicename-regex&gt; basierend auf Temperatur und Luftfeuchte und erzeugt daraus ein neues Reading namens dewpoint.
    Wenn &lt;temp_name&gt;, &lt;hum_name&gt; und &lt;new_name&gt; angegeben sind, werden die Temperatur aus dem Reading &lt;temp_name&gt;, die Luftfeuchte aus dem Reading &lt;hum_name&gt; gelesen und als berechneter Taupunkt ins Reading &lt;new_name&gt; geschrieben.<br>
    Wenn &lt;temp_name&gt; T lautet, wird die Temperatur aus state T: H: benutzt und &lt;new_name&gt; zu state hinzugef&uuml;gt.
    </ul>
    <br>

    Beispiele:<PRE>
    # Berechnet den Taupunkt aufgrund von Temperatur und Luftfeuchte
    # in Ereignissen, die vom Ger&auml;t temp1 erzeugt wurden und erzeugt ein Reading dewpoint.
    define dew_temp1 dewpoint dewpoint temp1
    define dew_temp1 dewpoint dewpoint temp1 temperature humidity dewpoint

    # Berechnet den Taupunkt aufgrund von Temperatur und Luftfeuchte
    # in Ereignissen, die von allen Ger&auml;ten erzeugt wurden die diese Werte ausgeben
    # und erzeugt ein Reading dewpoint.
    define dew_all dewpoint dewpoint .*
    define dew_all dewpoint dewpoint .* temperature humidity dewpoint

    # Berechnet den Taupunkt aufgrund von Temperatur und Luftfeuchte
    # in Ereignissen, die vom Ger&auml;t Aussen_1 erzeugt wurden und erg&auml;nzt 
    # mit diesem Wert den Status STATE.
    define dew_state dewpoint dewpoint Aussen_1 T H D

    # Berechnet den Taupunkt aufgrund von Temperatur und Luftfeuchte
    # in Ereignissen, die von allen Ger&auml;ten erzeugt wurden die diese Werte ausgeben
    # und erg&auml;nzt mit diesem Wert den Status STATE.
    # Beispiel STATE: "T: 10 H: 62.5" wird ver&auml;ndert nach
    # "T: 10 H: 62.5 D: 3.2"
    define dew_state dewpoint dewpoint .* T H D

    </PRE>
  </ul>

  <ul>
    <code>define &lt;name&gt; dewpoint fan &lt;devicename-regex&gt; &lt;devicename-outside&gt; &lt;min-temp&gt; [&lt;diff_temp&gt;]</code><br>
    <br>
    <ul>
      Erzeugt ein Ereignis, um einen L&uuml;fter einzuschalten, wenn die Au&szlig;enluft weniger Wasser als die Raumluft enth&auml;lt.</li>
    <ul>
        <li>
    Erzeugt das Ereignis "fan: on" wenn (Taupunkt von &lt;devicename-outside&gt;) + &lt;diff_temp&gt; ist niedriger als der Taupunkt von &lt;devicename&gt; und die Temperatur von &lt;devicename-outside&gt; &gt;= min-temp ist. Das Ereignis wird nur erzeugt wenn das Reading "fan" nicht schon "on" war. Das Ereignis wird f&uuml;r das Ger&auml;t &lt;devicename&gt; erzeugt. Der Parameter &lt;diff-temp&gt; ist optional.</li>
    <li>Andernfalls wird das Ereignis "fan: off" erzeugt, wenn das Reading von "fan" nicht bereits  "off" war.</li>
    </ul>
    </ul>
    <br>

    Beispiel:<PRE>
    # Erzeugt das Ereignis "fan: on", wenn der Taupunkt des Ger&auml;ts Aussen_1 zum ersten Mal
    # niedriger ist als der Taupunkt des Ger&auml;ts basement_tempsensor und die 
    # Au&szlig;entemperatur &gt;= 0 ist und wechselt nach "fan: off" wenn diese Bedingungen nicht 
    # mehr zutreffen.
    # Schaltet den Schalter fan_switch abh&auml;ngig vom Zustand ein oder aus.
    define dew_fan1 dewpoint fan basement_tempsensor Aussen_1 0
    define dew_fan1_on notify basement_tempsensor.*fan:.*on set fan_switch on
    define dew_fan1_off notify basement_tempsensor.*fan:.*off set fan_switch off

    </PRE>
  </ul>

  <ul>
    <code>define &lt;name&gt; dewpoint alarm &lt;devicename-regex&gt; &lt;devicename-reference&gt; &lt;diff-temp&gt;</code><br>
    <br>
    <ul>
    Erzeugt einen Schimmel-Alarm, wenn eine Referenz-Temperatur unter den Taupunkt f&auml;llt.</li>
    <ul>
        <li>
    Erzeugt ein Reading/Ereignis "alarm: on" wenn die Temperatur von &lt;devicename-reference&gt; - &lt;diff-temp&gt; unter den Taupunkt von &lt;devicename&gt; f&auml;llt und das Reading "alarm" nicht bereits "on" ist. Das Ereignis wird f&uuml;r &lt;devicename&gt; erzeugt.</li>
    <li>Erzeugt ein Reading/Ereignis "alarm: off" wenn die Temperatur von &lt;devicename-reference&gt; - &lt;diff-temp&gt; &uuml;ber den Taupunkt von &lt;devicename&gt; steigt und das Reading "alarm" nicht bereits "off" ist.</li>
</li>
    </ul>
    </ul>
    <br>

    Beispiel:<PRE>
    # Es wird ein Anlegef&uuml;hler (Wandsensor) und ein Thermo-/Hygrometer (Raumf&uuml;hler)
    # verwendet, um einen Alarm zu erzeugen, wenn die Wandtemperatur
    # unter den Taupunkt der Luft f&auml;llt. In diesem Fall w&uuml;rde sich Wasser an der Wand
    # niederschlagen (kondensieren), weil die Wand zu kalt ist.
    # Der Schalter einer Sirene (alarm_siren) wird &uuml;ber ein notify geschaltet.
    define dew_alarm1 dewpoint alarm roomsensor wallsensor 0
    define roomsensor_alarm_on notify roomsensor.*alarm:.*on set alarm_siren on
    define roomsensor_alarm_off notify roomsensor.*alarm:.*off set alarm_siren off

    # Ohne Wandsensor l&auml;sst sich auch der Taupunkt eines Raums mit der Temperatur desselben
    # (oder eines anderen) F&uuml;hlers vergleichen.
    # Die Alarmtemperatur ist 5 Grad niedriger gesetzt als die des Vergleichsthermostats.
    define dev_alarm2 dewpoint alarm roomsensor roomsensor 5

    </PRE>
  </ul>

  <a name="dewpointset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="dewpointget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dewpointattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li>max_timediff<br>
        Maximale erlaubter Zeitunterschied in Sekunden zwischen den Temperatur- und Luftfeuchtewerten eines Ger&auml;ts. dewpoint verwendet Readings von Temperatur oder Luftfeuchte wenn sie nicht im Ereignis mitgeliefert werden. Das ist sowohl f&uuml;r den Betrieb mit event-on-change-reading n&ouml;tig als auch bei Sensoren die Temperatur und Luftfeuchte in getrennten Ereignissen kommunizieren (z.B. Technoline Sensoren TX3TH).<br>
Der Standardwert ist 1 Sekunde.
      <br><br>
      Beispiel:<PRE>
    # Maximal erlaubter Zeitunterschied soll 60 Sekunden sein
    define dew_all dewpoint dewpoint .*
    attr dew_all max_timediff 60
    </li><br>
  </ul>
</ul>

=end html_DE
=cut
