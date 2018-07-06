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

use vars qw(%defs);

sub Log3($$$);

# default maximum time_diff for dewpoint
my $dewpoint_time_diff_default = 1; # 1 Second

##########################
sub
dewpoint_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "dewpoint_Define";
  $hash->{NotifyFn} = "dewpoint_Notify";
  $hash->{AttrFn} = "dewpoint_Attr";
  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "disable:0,1 legacyStateHandling:0,1 verbose max_timediff absFeuchte"
                      . " absoluteHumidity vapourPressure";
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
    return "Bad regexp: $@" if($@);

    $hash->{DEV_REGEXP} = $devname;
    # set NOTIFYDEV
    notifyRegexpChanged($hash, $devname);
    $hash->{STATE} = "active";
    return undef;
}

##########################
sub
dewpoint_Attr(@)
{
    my ($cmd, $name, $a_name, $a_val) = @_;
    my $hash = $defs{$name};

    if ($cmd eq "set" && $a_name eq "absFeuchte") {
        Log(1, "dewpoint $name: attribute 'absFeuchte' is deprecated, please use 'absoluteHumidity'");
        return undef;
    }

    if ($cmd eq "set" && ($a_name eq "absoluteHumidity" || $a_name eq "vapourPressure")) {
	if (! goodReadingName($a_val)) {
            return "Value of $a_name is not a valid reading name";
        }
    }

    return undef;
}

##########################
sub
dewpoint_Notify($$)
{
    my ($hash, $dev) = @_;

    my $hashName = $hash->{NAME};
    my $devName = $dev->{NAME};
    my $re = $hash->{DEV_REGEXP};

    # fast exit
    return "" if (!defined($re) || $devName !~ m/^$re$/);

    return "" if (AttrVal($hashName, "disable", undef));

    my $cmd_type = $hash->{CMD_TYPE};

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
            Log3($hashName, 1, "Error dewpoint: TEMP_NAME || HUM_NAME || NEW_NAME undefined");
            return "";
        }
        $temp_name = $hash->{TEMP_NAME};
        $hum_name = $hash->{HUM_NAME};
        $new_name = $hash->{NEW_NAME};
        Log3($hashName, 4, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, "
                           . "dev_regex=$re temp_name=$temp_name hum_name=$hum_name");
    } elsif ($cmd_type eq "fan") {
        if (!defined($hash->{DEVNAME_OUT}) || !defined($hash->{MIN_TEMP})) {
            # should never happen!
            Log3($hashName, 1, "Error dewpoint: DEVNAME_OUT || MIN_TEMP undefined");
            return "";
        }
        $devname_out = $hash->{DEVNAME_OUT};
        $min_temp = $hash->{MIN_TEMP};
        $diff_temp = $hash->{DIFF_TEMP};
        Log3($hashName, 4, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, "
                           . " dev_regex=$re, devname_out=$devname_out, min_temp=$min_temp, diff_temp=$diff_temp");

    } elsif ($cmd_type eq "alarm") {
        if (!defined($hash->{DEVNAME_REF}) || !defined($hash->{DIFF_TEMP})) {
            # should never happen!
            Log3($hashName, 1, "Error dewpoint: DEVNAME_REF || DIFF_TEMP undefined");
            return "";
        }
        $devname_ref = $hash->{DEVNAME_REF};
        $diff_temp = $hash->{DIFF_TEMP};
        Log3($hashName, 4, "dewpoint_notify: cmd_type=$cmd_type devname=$devName dewname=$hashName, dev=$devName, "
                           . "dev_regex=$re, devname_ref=$devname_ref, diff_temp=$diff_temp");
    } else {
        # should never happen:
        Log3($hashName, 1, "Error notify_dewpoint: <1> unknown cmd_type ".$cmd_type);
        return "";
    }

    my $nev = int(@{$dev->{CHANGED}});

    # if we use the "T H" syntax we must track the index of the state event
    my $i_state_ev;

    my $temperature = "";
    my $humidity = "";

    for (my $i = 0; $i < $nev; $i++) {
        my $s = $dev->{CHANGED}[$i];

        Log3($hashName, 5, "dewpoint_notify: s='$s'");

        ################
        # Filtering
        next if(!defined($s));
        my ($evName, $val, $rest) = split(" ", $s, 3); # resets $1
        next if(!defined($evName));
        next if(!defined($val));
        Log3($hashName, 5, "dewpoint_notify: evName='$evName' val=$val'");
        if (($evName eq "T:") && ($temp_name eq "T")) {
            $i_state_ev = $i;
            #my ($evName1, $val1, $evName2, $val2, $rest) = split(" ", $s, 5); # resets $1
            if ($s =~ /T: ([-+]?[0-9]*\.[0-9]+|[-+]?[0-9]+)/) {
                $temperature = $1;
            }
            if ($s =~ /H: [-+]?([0-9]*\.[0-9]+|[0-9]+)/) {	
                $humidity = $1;
            }
            Log3($hashName, 5, "dewpoint_notify T: H:, temp=$temperature hum=$humidity");
        } elsif ($evName eq $temp_name.":") {
            $temperature = $val;
            Log3($hashName, 5, "dewpoint_notify temperature! dev=$devName, temp_name=$temp_name, temp=$temperature");
        } elsif ($evName eq $hum_name.":") {
            $humidity = $val;
            Log3($hashName, 5, "dewpoint_notify humidity! dev=$devName, hum_name=$hum_name, hum=$humidity");
        }

    }

    #if (($temperature eq "") || ($humidity eq "")) { return undef; } # no way to calculate dewpoint!

    # Check if Attribute timeout is set
    my $timeout = AttrVal($hash->{NAME}, "max_timediff", $dewpoint_time_diff_default);
    Log3($hashName, 5,"dewpoint max_timediff=$timeout");

    if (($humidity eq "") && (($temperature eq ""))) {
        return undef;  # no way to calculate dewpoint!
    } elsif (($humidity eq "") && (($temperature ne ""))) { 
        # temperature set, but humidity not. Try to use a valid value from the appropriate reading
        $humidity = ReadingsNum($devName, $hum_name, undef);
        my $time_diff = ReadingsAge($devName, $hum_name, undef);

        if (defined($humidity) && defined($time_diff)) {
            Log3($hashName, 5, ">dev=$devName, hum_name=$hum_name, reference humidity=$humidity ($time_diff),"
                               . " temp=$temperature");
        } else { return undef; }

        if ($time_diff > 0 && $time_diff > $timeout) { return undef; }  
    } elsif (($temperature eq "") && ($humidity ne "")) { 
        # humdidity set, but temperature not. Try to use a valid value from the appropriate reading
        $temperature = ReadingsNum($devName, $temp_name, undef);
        my $time_diff = ReadingsAge($devName, $temp_name, undef);

        if (defined($temperature) && defined($time_diff)) {
            Log3($hashName, 5, ">dev=$devName, temp_name=$temp_name, reference temperature=$temperature ($time_diff),"
                               . " hum=$humidity");
        } else { return undef; }
        if ($time_diff > 0 && $time_diff > $timeout) { return undef; }  
    } 

    # We found temperature and humidity. so we can calculate dewpoint first
    # Prüfen, ob humidity im erlaubten Bereich ist
    if (($humidity <= 0) || ($humidity >= 110)){
        Log3($hashName, 1, "Error dewpoint: humidity invalid: $humidity");
        return undef;
    }

    my $dewpoint = dewpoint_dewpoint($temperature, $humidity);
    Log3($hashName, 5, "dewpoint_notify: dewpoint=$dewpoint");

    my $tn = TimeNow();
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

        readingsBeginUpdate($dev);
        my $rval;
        my $rname;
        my $abs_hunidity = dewpoint_absFeuchte($temperature, $humidity);
        my $aFeuchte = AttrVal($hashName, "absFeuchte", undef);
        if (defined($aFeuchte)) {
            $rname = "absFeuchte";
            readingsBulkUpdate($dev, $rname, $abs_hunidity);
            Log3($hashName, 5, "dewpoint absFeuchte= $abs_hunidity");
            $aFeuchte = "A: " . $abs_hunidity;
    	}

        my $ah_rname = AttrVal($hashName, "absoluteHumidity", undef);
        if (defined($ah_rname)) {
            readingsBulkUpdate($dev, $ah_rname, $abs_hunidity);
            Log3($hashName, 5, "dewpoint $ah_rname= $abs_hunidity");
            $aFeuchte = "A: " . $abs_hunidity if !defined($aFeuchte);
        }	

        my $vp_rname = AttrVal($hashName, "vapourPressure", undef);
        if (defined($vp_rname)) {
            my $vp = round(10 * dewpoint_vp($temperature, $humidity), 1);
            readingsBulkUpdate($dev, $vp_rname, $vp);
            Log3($hashName, 5, "dewpoint $vp_rname= $vp");
        }	

        $rname = $new_name;

        my $has_state_format = defined(AttrVal($dev->{NAME}, "stateFormat", undef));
        my $legacy_sh = AttrVal($hash->{NAME}, "legacyStateHandling", 0);
        if ($temp_name ne "T" || ($has_state_format && ! $legacy_sh)) {
            $rval = $dewpoint;
            readingsBulkUpdate($dev, $rname, $rval);
            readingsEndUpdate($dev, 1);
        } else {
            # explicit manipulation of STATE here
            # first call readingsEndUpdate to finish STATE processing in the referenced device...

            readingsEndUpdate($dev, 1);

            # ... then update STATE
            # STATE begins with "T:". append dewpoint or insert before BAT
            my $lastval = $dev->{CHANGED}[$i_state_ev];
            if ($lastval =~ /BAT:/) {	
                $rval = $lastval;
                $rval =~ s/BAT:/$rname: $dewpoint BAT:/g;
            } elsif ($lastval =~ /<</) {	
                $rval = $lastval;
                $rval =~ s/<</$rname:$dewpoint   <</g;
            } else {
                $rval = $lastval." ".$rname.": ".$dewpoint;
                if (defined($aFeuchte)) {
                    $rval = $rval." ".$aFeuchte;
                }
            }

            $dev->{STATE} = $rval;
            # the state event must be REPLACED
            $dev->{CHANGED}[$i_state_ev] = $rval;		
        }

        # remove cached "state:..." events if any
        $dev->{CHANGEDWITHSTATE} = [];
        Log3($hashName, 5, "dewpoint_notify: rval=$rval");

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
        Log3($hashName, 5, "dewpoint_notify: fan devname_out=$devname_out, min_temp=$min_temp, diff_temp=$diff_temp");
        my $rname;
        my $rval;
        if (exists $defs{$devname_out}{READINGS}{temperature}{VAL} && exists $defs{$devname_out}{READINGS}{humidity}{VAL}) {
            my $temperature_out = $defs{$devname_out}{READINGS}{temperature}{VAL};
            my $humidity_out = $defs{$devname_out}{READINGS}{humidity}{VAL};
            my $dewpoint_out = dewpoint_dewpoint($temperature_out, $humidity_out);
            Log3($hashName, 5, "dewpoint_notify: fan dewpoint_out=$dewpoint_out");
            if (($dewpoint_out + $diff_temp) < $dewpoint && $temperature_out >= $min_temp) {
                $rval = "on";
                Log3($hashName, 3, "dewpoint_notify: fan ON");
            } else {
                $rval = "off";
                Log3($hashName, 3, "dewpoint_notify: fan OFF");
            }
            $rname = "fan";
            if (!exists $defs{$devName}{READINGS}{$rname}{VAL} || $defs{$devName}{READINGS}{$rname}{VAL} ne $rval) {
                Log3($hashName, 3, "dewpoint_notify: CHANGE fan $rval");
                $dev->{READINGS}{$rname}{TIME} = $tn;
                $dev->{READINGS}{$rname}{VAL} = $rval;
                $dev->{CHANGED}[$nev++] = $rname . ": " . $rval;
            }

        } else {
            Log3($hashName, 1, "dewpoint_notify: fan devname_out=$devname_out no temperature or humidity available"
                               . " for dewpoint calculation");
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
        Log3($hashName, 5, "dewpoint_notify: alarm devname_ref=$devname_ref, diff_temp=$diff_temp");
        my $rname;
        my $rval;
        if (exists $defs{$devname_ref}{READINGS}{temperature}{VAL}) {
            my $temperature_ref = $defs{$devname_ref}{READINGS}{temperature}{VAL};
            Log3($hashName, 5, "dewpoint_notify: alarm temperature_ref=$temperature_ref");
            if ($temperature_ref - $diff_temp < $dewpoint) {
                $rval = "on";
                Log3($hashName, 3, "dewpoint_notify: alarm ON");
            } else {
                $rval = "off";
                Log3($hashName, 3, "dewpoint_notify: alarm OFF");
            }
            $rname = "alarm";
            if (!exists $defs{$devName}{READINGS}{$rname}{VAL} || $defs{$devName}{READINGS}{$rname}{VAL} ne $rval) {
                Log3($hashName, 5, "dewpoint_notify: CHANGE alarm $rval");
                $dev->{READINGS}{$rname}{TIME} = $tn;
                $dev->{READINGS}{$rname}{VAL} = $rval;
                $dev->{CHANGED}[$nev++] = $rname . ": " . $rval;
            }
        } else {
            Log3($hashName, 1, "dewpoint_notify: alarm devname_out=$devname_out no temperature or humidity available"
                               . " for dewpoint calculation");
        }

    } else {
        # should never happen:
        Log3($hashName, 1, "Error notify_dewpoint: <2> unknown cmd_type ".$cmd_type);
        return "";
    }

    return undef;
}

# -----------------------------
# Dewpoint calculation.

# 'Magnus formula'
#
# Parameters from https://de.wikipedia.org/wiki/Taupunkt#S.C3.A4ttigungsdampfdruck
# Good summary of formulas in http://www.wettermail.de/wetter/feuchte.html

my $E0 = 0.6112; # saturation pressure at T=0 °C
my @ab_gt0 = (17.62, 243.12);    # T>0
my @ab_le0 = (22.46, 272.6);     # T<=0 over ice

### ** Public interface ** keep stable
# vapour pressure in kPa
sub dewpoint_vp($$)
{
    my ($T, $Hr) = @_;
    my ($a, $b);

    if ($T > 0) {
        ($a, $b) = @ab_gt0;
    } else {
        ($a, $b) = @ab_le0;
    }

    return 0.01 * $Hr * $E0 * exp($a * $T / ($T + $b));
}

### ** Public interface ** keep stable
# dewpoint in °C
sub
dewpoint_dewpoint($$)
{
    my ($T, $Hr) = @_;
    if ($Hr == 0) {
        Log(1, "Error: dewpoint() Hr==0 !: temp=$T, hum=$Hr");
        return undef;
    }

    my ($a, $b);

    if ($T > 0) {
        ($a, $b) = @ab_gt0;
    } else {
        ($a, $b) = @ab_le0;
    }

    # solve vp($dp, 100) = vp($T,$Hr) for $dp 
    my $v = log(dewpoint_vp($T, $Hr) / $E0);
    my $D = $a - $v;

    # can this ever happen for valid input?
    if ($D == 0) {
        Log(1, "Error: dewpoint() D==0 !: temp=$T, hum=$Hr");
        return undef;
    }

    return round($b * $v / $D, 1);
}


### ** Public interface ** keep stable
# absolute Feuchte in g Wasserdampf pro m3 Luft
sub
dewpoint_absFeuchte ($$)
{
    my ($T, $Hr) = @_;

    # 110 ?
    if (($Hr < 0) || ($Hr > 110)) {
        Log(1, "Error dewpoint: humidity invalid: $Hr");
        return "";
    }
    my $DD = dewpoint_vp($T, $Hr);
    my $AF  = 1.0E6 * (18.016 / 8314.3) * ($DD / (273.15 + $T));
    return round($AF, 1);
}

1;


=pod
=item helper
=item summary compute dewpoint and/or generate events for starting a fan
=item summary_DE berechne Taupunkt und/oder erzeuge events zum starten eines Lüfters
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
        <b>Obsolete, avoid for new definitions</b><br>
	&nbsp;&nbsp;If &lt;temp_name&gt; is T then use temperature from state T: H:, add &lt;new_name&gt; to the STATE.
        The addition to STATE only occurs if the target device does not define attribute "stateFormat".<br>
        If the obsolete behaviour of STATE is mandatory set attribute <code>legacyStateHandling</code>
        should be set.
    </ul>
    <br><br>

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
    # and insert is into STATE unless Aussen_1 has attribute "stateFormat" defined.
    # If "stateFormat" is defined then a reading D will be generated.
    define dew_state dewpoint dewpoint Aussen_1 T H D

    # Compute the dewpoint for the temperature/humidity
    # events of all devices offering temperature and humidity
    # and insert the result into the STATE. (See example above).
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
    <li>absoluteHumidity &lt;reading_name&gt;</li>
      <ul>
        In addition the absolute humidity in g/m&sup3; will be computed as reading &lt;reading_name&gt;.
      </ul><br>
    <li>vapourPressure &lt;reading_name&gt;</li>
      <ul>
        In addition the vapour pressure in hPa will be computed as reading &lt;reading_name&gt;.
      </ul><br>
    <li>max_timediff</li>
      <ul>
        Maximum time difference in seconds allowed between the temperature and humidity values for a device. dewpoint uses the Readings for temperature or humidity if they are not delivered in the event. This is necessary for using dewpoint with event-on-change-reading. Also needed for sensors that do deliver temperature and humidity in different events like for example technoline sensors TX3TH.<br>
		If not set default is 1 second.
      <br><br>
      Examples:<PRE>
		# allow maximum time difference of 60 seconds
		define dew_all dewpoint dewpoint .*
		attr dew_all max_timediff 60
    </ul>
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
      Erzeugt ein Ereignis, um einen L&uuml;fter einzuschalten, wenn die Au&szlig;enluft 
      weniger Wasser als die Raumluft enth&auml;lt.</li>
    <li><b>alarm</b>: Alarm<br>
      Erzeugt einen Schimmel-Alarm, wenn eine Referenz-Temperatur unter den Taupunkt f&auml;llt.</li>
  </ul>
  <br/>

  <a name="dewpointdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dewpoint dewpoint &lt;devicename-regex&gt; [&lt;temp_name&gt; 
    &lt;hum_name&gt; &lt;new_name&gt;]</code><br>
    <br/>
    Berechnet den Taupunkt des Ger&auml;ts &lt;devicename-regex&gt; basierend auf Temperatur 
    und Luftfeuchte und erzeugt daraus ein neues Reading namens dewpoint.<br/>
    Wenn &lt;temp_name&gt;, &lt;hum_name&gt; und &lt;new_name&gt; angegeben sind, 
    werden die Temperatur aus dem Reading &lt;temp_name&gt;, die Luftfeuchte aus dem 
    Reading &lt;hum_name&gt; gelesen und als berechneter Taupunkt ins Reading &lt;new_name&gt; geschrieben.<br><br>
    <b>Veraltet, f&uuml;r neue Definitionen nicht mehr benutzen</b><br>
    &nbsp;&nbsp;Wenn &lt;temp_name&gt; T lautet, wird die Temperatur aus state T: H: benutzt 
    und &lt;new_name&gt; zu STATE hinzugef&uuml;gt. Das hinzuf&uuml;gen zu STATE erfolgt nur, falls im Zielger&auml;t
    das Attribut "stateFormat" nicht definiert ist.<br>
    Falls das veraltete Verhalten zum Update unbedingt gew&uuml;scht ist,
    kann das Attribut <code>legacyStateHandling</code> gesetzt werden.
    <br/>
    Beispiele:
    <pre>
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
    # mit diesem Wert den Status STATE, falls in Aussen_1 das Attribut "stateFormat" nicht definiert ist.
    # Falls "stateFormat" definiert ist, wird das reading "D" angelegt.
    define dew_state dewpoint dewpoint Aussen_1 T H D

    # Berechnet den Taupunkt aufgrund von Temperatur und Luftfeuchte
    # in Ereignissen, die von allen Ger&auml;ten erzeugt wurden die diese Werte ausgeben
    # und erg&auml;nzt mit diesem Wert den Status STATE. (Siehe Beispiel oben).
    # Beispiel STATE: "T: 10 H: 62.5" wird ver&auml;ndert nach
    # "T: 10 H: 62.5 D: 3.2"
    define dew_state dewpoint dewpoint .* T H D
    </pre>

    <br/>
    <br/>
    <code>define &lt;name&gt; dewpoint fan &lt;devicename-regex&gt; &lt;devicename-outside&gt; &lt;min-temp&gt; [&lt;diff_temp&gt;]</code><br>
    <br>
    <ul>
      <li>Erzeugt ein Ereignis, um einen L&uuml;fter einzuschalten, wenn die Au&szlig;enluft 
        weniger Wasser als die Raumluft enth&auml;lt.</li>
      <li>Erzeugt das Ereignis "fan: on" wenn (Taupunkt von &lt;devicename-outside&gt;) + 
        &lt;diff_temp&gt; ist niedriger als der Taupunkt von &lt;devicename&gt; und die Temperatur 
        von &lt;devicename-outside&gt; &gt;= min-temp ist. Das Ereignis wird nur erzeugt wenn das 
        Reading "fan" nicht schon "on" war. Das Ereignis wird f&uuml;r das Ger&auml;t &lt;devicename&gt; erzeugt. 
        Der Parameter &lt;diff-temp&gt; ist optional.</li>
      <li>Andernfalls wird das Ereignis "fan: off" erzeugt, wenn das Reading von "fan" nicht bereits  "off" war.</li>
    </ul>
    <br>
    Beispiel:
    <pre>
    # Erzeugt das Ereignis "fan: on", wenn der Taupunkt des Ger&auml;ts Aussen_1 zum ersten Mal
    # niedriger ist als der Taupunkt des Ger&auml;ts basement_tempsensor und die 
    # Au&szlig;entemperatur &gt;= 0 ist und wechselt nach "fan: off" wenn diese Bedingungen nicht 
    # mehr zutreffen.
    # Schaltet den Schalter fan_switch abh&auml;ngig vom Zustand ein oder aus.
    define dew_fan1 dewpoint fan basement_tempsensor Aussen_1 0
    define dew_fan1_on notify basement_tempsensor.*fan:.*on set fan_switch on
    define dew_fan1_off notify basement_tempsensor.*fan:.*off set fan_switch off
    </pre>

    <code>define &lt;name&gt; dewpoint alarm &lt;devicename-regex&gt; &lt;devicename-reference&gt; &lt;diff-temp&gt;</code><br>
    <br>
    <ul>
      <li>Erzeugt einen Schimmel-Alarm, wenn eine Referenz-Temperatur unter den Taupunkt f&auml;llt.</li>
      <li>Erzeugt ein Reading/Ereignis "alarm: on" wenn die Temperatur von 
        &lt;devicename-reference&gt; - &lt;diff-temp&gt; unter den Taupunkt von 
        &lt;devicename&gt; f&auml;llt und das Reading "alarm" nicht bereits "on" ist. 
        Das Ereignis wird f&uuml;r &lt;devicename&gt; erzeugt.</li>
      <li>Erzeugt ein Reading/Ereignis "alarm: off" wenn die Temperatur von 
           &lt;devicename-reference&gt; - &lt;diff-temp&gt; &uuml;ber den Taupunkt 
           von &lt;devicename&gt; steigt und das Reading "alarm" nicht bereits "off" ist.</li>
    </ul>
    <br>
    Beispiel:
    <pre>
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
    </pre>
  </ul>

  <a name="dewpointset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="dewpointget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dewpointattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li>absoluteHumidity &lt;reading_name&gt;</li>
      <ul>
        Zus&auml;tzlich wird die absolute Feuchte in g/m&sup3; als Reading &lt;reading_name&gt; berechnet.
      </ul><br>
    <li>vapourPressure &lt;reading_name&gt;</li>
      <ul>
        Zus&auml;tzlich wird der Dampfdruck in hPa als Reading &lt;reading_name&gt; berechnet.
      </ul><br>
    <li>max_timediff</li>
      <ul>
        Maximale erlaubter Zeitunterschied in Sekunden zwischen den Temperatur- und Luftfeuchtewerten eines 
        Ger&auml;ts. dewpoint verwendet Readings von Temperatur oder Luftfeuchte wenn sie nicht im Ereignis 
        mitgeliefert werden. Das ist sowohl f&uuml;r den Betrieb mit event-on-change-reading n&ouml;tig 
        als auch bei Sensoren die Temperatur und Luftfeuchte in getrennten Ereignissen kommunizieren 
        (z.B. Technoline Sensoren TX3TH).<br>
        Der Standardwert ist 1 Sekunde.
        <br><br>
        Beispiel:
        <pre>
        # Maximal erlaubter Zeitunterschied soll 60 Sekunden sein
        define dew_all dewpoint dewpoint .*
        attr dew_all max_timediff 60
        </pre>
      </ul>
  </ul>
</ul>

=end html_DE

=cut
