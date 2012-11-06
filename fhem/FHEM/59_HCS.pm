################################################################
# $Id: $
# vim: ts=2:et
#
#  (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################

package main;
use strict;
use warnings;

sub HCS_Initialize($$);
sub HCS_Define($$);
sub HCS_Undef($$);
sub HCS_checkState($);
sub HCS_Get($@);
sub HCS_Set($@);
sub HCS_setState($$);
sub HCS_getValves($$);

my %gets = (
  "valves"    => "",
);

my %sets = (
  "interval"          => "",
  "on"                => "",
  "off"               => "",
  "valveThresholdOn"  => "",
  "valveThresholdOff" => "",
);

#####################################
sub
HCS_Initialize($$)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "HCS_Define";
  $hash->{UndefFn}  = "HCS_Undef";
  $hash->{GetFn}    = "HCS_Get";
  $hash->{SetFn}    = "HCS_Set";
  $hash->{AttrList} = "device deviceCmdOn deviceCmdOff interval idleperiod ".
                      "sensor sensorThresholdOn sensorThresholdOff sensorReading ".
                      "valvesExcluded valveThresholdOn valveThresholdOff ".
                      "do_not_notify:1,0 event-on-update-reading event-on-change-reading ".
                      "showtime:1,0 loglevel:0,1,2,3,4,5,6 disable:0,1";
}

#####################################
sub
HCS_Define($$) {
  my ($hash, $def) = @_;

  # define <name> HCS <device> [interval] [valveThresholdOn] [valveThresholdOff]
  # define heatingControl HCS KG.hz.LC.SW1.01 10 40 30

  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use 'define <name> HCS <device> [interval] [valveThresholdOn] [valveThresholdOff]'"
    if(@a < 3 || @a > 6);

  my $name = $a[0];
  $attr{$name}{device}        = $a[2];
  $attr{$name}{deviceCmdOn}       = AttrVal($name,"deviceCmdOn","on");
  $attr{$name}{deviceCmdOff}      = AttrVal($name,"deviceCmdOff","off");
  $attr{$name}{interval}          = AttrVal($name,"interval",(defined($a[3]) ? $a[3] : 10));
  $attr{$name}{valveThresholdOn}  = AttrVal($name,"valveThresholdOn",(defined($a[4]) ? $a[4] : 40));
  $attr{$name}{valveThresholdOff} = AttrVal($name,"valveThresholdOff",(defined($a[5]) ? $a[5] : 35));

  my $type = $hash->{TYPE};
  my $ret;

  if(!defined($defs{$a[2]})) {
    $ret = "Device $a[2] not defined. Please add this device first!";
    Log 1, "$type $name $ret";
    return $ret;
  }

  $hash->{STATE} = "Defined";

  my $interval = AttrVal($name,"interval",10);
  my $timer;

  $ret = HCS_getValves($hash,0);
  HCS_setState($hash,$ret);

  $timer = gettimeofday()+60;
  InternalTimer($timer, "HCS_checkState", $hash, 0);
  $hash->{NEXTCHECK} = FmtTime($timer);

  return undef;
}

#####################################
sub
HCS_Undef($$) {
  my ($hash, $name) = @_;

  delete($modules{HCS}{defptr}{$hash->{NAME}});
  RemoveInternalTimer($hash);

  return undef;
}

#####################################
sub
HCS_checkState($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $interval = $attr{$name}{interval};
  my $timer;
  my $ret;

  $ret = HCS_getValves($hash,0);
  HCS_setState($hash,$ret);

  $timer = gettimeofday()+($interval*60);
  InternalTimer($timer, "HCS_checkState", $hash, 0);
  $hash->{NEXTCHECK} = FmtTime($timer);

  return undef;
}

#####################################
sub
HCS_Get($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $ret;

  # check syntax
  return "argument is missing @a"
    if(int(@a) != 2);
  # check argument
  return "Unknown argument $a[1], choose one of ".join(" ", sort keys %gets)
    if(!defined($gets{$a[1]}));
 
  # get argument
  my $arg = $a[1];

  if($arg eq "valves") {
    $ret = HCS_getValves($hash,1);
    return $ret;
  }

  return undef;
}

#####################################
sub
HCS_Set($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $timer;
  my $ret;

  # check syntax
  return "argument is missing @a"
    if(int(@a) < 2 || int(@a) > 3);
  # check argument
  return "Unknown argument $a[1], choose one of ".join(" ", sort keys %sets)
    if(!defined($sets{$a[1]}));
 
  # get argument
  my $arg = $a[1];

  if($arg eq "interval") {

    return "Wrong interval format: Only digits are allowed!"
      if($a[2] !~ m/^\d+$/);

    my $intervalNew = $a[2];
    my $intervalOld = AttrVal($name,"interval",10);
    RemoveInternalTimer($hash);
    $attr{$name}{interval} = $intervalNew;
    $timer = gettimeofday()+($intervalNew*60);
    InternalTimer($timer, "HCS_checkState", $hash, 0);
    $hash->{NEXTCHECK} = FmtTime($timer);
    Log 1, "$type $name interval changed from $intervalOld to $intervalNew";

  } elsif($arg eq "valveThresholdOn") {

    return "Wrong interval format: Only digits are allowed!"
      if($a[2] !~ m/^\d+$/);

    my $thresholdNew = $a[2];
    my $thresholdOld = AttrVal($name,"valveThresholdOn",40);
    $attr{$name}{valveThresholdOn} = $thresholdNew;
    Log 1, "$type $name valveThresholdOn changed from $thresholdOld to $thresholdNew";

  } elsif($arg eq "valveThresholdOff") {

    return "Wrong interval format: Only digits are allowed!"
      if($a[2] !~ m/^\d+$/);

    my $thresholdNew = $a[2];
    my $thresholdOld = AttrVal($name,"valveThresholdOff",35);
    $attr{$name}{valveThresholdOff} = $thresholdNew;
    Log 1, "$type $name valveThresholdOff changed from $thresholdOld to $thresholdNew";

  } elsif($arg eq "on") {
    RemoveInternalTimer($hash);
    HCS_checkState($hash);
    Log 1, "$type $name monitoring of valves started";
  } elsif($arg eq "off") {
    RemoveInternalTimer($hash);
    #$hash->{STATE} = "off";
    $hash->{NEXTCHECK} = "offline";
    readingsBeginUpdate($hash);
    readingsUpdate($hash, "state", "off");
    readingsEndUpdate($hash, 1);
    Log 1, "$type $name monitoring of valves interrupted";
  }

}

#####################################
sub
HCS_setState($$) {
  my ($hash,$heatDemand) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $ll = AttrVal($name,"loglevel",3);
  my $device       = AttrVal($name,"device","");
  my $deviceCmdOn  = AttrVal($name,"deviceCmdOn","on");
  my $deviceCmdOff = AttrVal($name,"deviceCmdOff","off");
  my $idlePeriod   = AttrVal($name,"idleperiod",0);
  my $lastPeriodTime = ($hash->{helper}{lastSend}) ? $hash->{helper}{lastSend} : 0;
  my $newPeriodTime = gettimeofday();
  my $diffPeriodTime = int((int($newPeriodTime)-int($lastPeriodTime))/60);
  my $sensor = AttrVal($name,"sensor",undef);
  my $cmd;
  my $overdrive = 0;
  my $state;
  my $stateDevice;

  if($heatDemand == 1) {
    $state = "demand";
    $cmd = $deviceCmdOn;
  } elsif($heatDemand == 2) {
    $overdrive = 1;
    $state = "demand (overdrive)";
    $cmd = $deviceCmdOn;
  } elsif($heatDemand == 3) {
    $overdrive = 1;
    $state = "idle (overdrive)";
    $cmd = $deviceCmdOff;
  } else {
    $state = "idle";
    $cmd = $deviceCmdOff;
  }

  $state = "error" if(!defined($defs{$device}));
  $stateDevice = ReadingsVal($name,"device","");

  readingsBeginUpdate($hash);
  readingsUpdate($hash, "device", $cmd);
  readingsUpdate($hash, "overdrive", $overdrive) if($sensor);
  readingsUpdate($hash, "state", $state);
  readingsEndUpdate($hash, 1);

  if($defs{$device}) {
    my $eventOnChange = AttrVal($name,"event-on-change-reading","");
    my $eventOnUpdate = AttrVal($name,"event-on-update-reading","");
    if(!$eventOnChange ||
      ($eventOnUpdate && $eventOnUpdate =~ m/device/) || 
      ($eventOnChange && ($eventOnChange =~ m/device/ || $eventOnChange == 1) && $cmd ne $stateDevice)) {
      if(!$idlePeriod || ($idlePeriod && $diffPeriodTime >= $idlePeriod)) {
        my $cmdret = CommandSet(undef,"$device $cmd");
        $hash->{helper}{lastSend} = $newPeriodTime;
        Log 1, "$type $name An error occurred while switching device '$device': $cmdret"
          if($cmdret);
      } elsif($idlePeriod && $diffPeriodTime < $idlePeriod) {
        Log $ll, "$type $name device $device blocked by idleperiod ($idlePeriod min.)";
      }
    }
  } else {
    Log 1, "$type $name device '$device' does not exists.";
  }

  return undef;
}

#####################################
sub
HCS_getValves($$) {
  my ($hash,$list) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $excluded = AttrVal($name,"valvesExcluded","");
  my $heatDemand = 0;
  my $valveThresholdOn  = AttrVal($name,"valveThresholdOn",40);
  my $valveThresholdOff = AttrVal($name,"valveThresholdOff",35);
  my $ll = AttrVal($name,"loglevel",3);
  my %valves = ();
  my $valvesIdle = 0;
  my $valveState;
  my $valveLastDemand;
  my $valveNewDemand;
  my $value;
  my $ret;

  # reset counter
  my $sumDemand   = 0;
  my $sumFHT      = 0;
  my $sumHMCCTC   = 0;
  my $sumValves   = 0;
  my $sumExcluded = 0;
  my $sumIgnored  = 0;


  foreach my $d (sort keys %defs) {
    # skipping unneeded devices
    next if($defs{$d}{TYPE} ne "FHT" && $defs{$d}{TYPE} ne "CUL_HM");
    next if($defs{$d}{TYPE} eq "CUL_HM" && !$attr{$d}{model});
    next if($defs{$d}{TYPE} eq "CUL_HM" && $attr{$d}{model}  ne "HM-CC-TC");
    next if($defs{$d}{TYPE} eq "CUL_HM" && $attr{$d}{model} eq "HM-CC-TC" && ($attr{$d}{device} || $attr{$d}{chanNo}));

    # get current actuator state from each device
    $valveState = $defs{$d}{READINGS}{"actuator"}{VAL};
    $valveState =~ s/[\s%]//g;

    if($attr{$d}{ignore}) {
      $value = "$valveState% (ignored)";
      $valves{$defs{$d}{NAME}}{state} = $value;
      $valves{$defs{$d}{NAME}}{demand} = 0;
      $ret .= "$defs{$d}{NAME}: $value\n" if($list);
      Log $ll+1, "$type $name $defs{$d}{NAME}: $value";
      $sumIgnored++;
      $sumValves++;
      $sumFHT++     if($defs{$d}{TYPE} eq "FHT");
      $sumHMCCTC++  if(defined($attr{$d}{model}) && $attr{$d}{model} eq "HM-CC-TC");
      next;
    }

    if($excluded =~ m/$d/) {
      $value = "$valveState% (excluded)";
      $valves{$defs{$d}{NAME}}{state} = $value;
      $valves{$defs{$d}{NAME}}{demand} = 0;
      $ret .= "$defs{$d}{NAME}: $value\n" if($list);
      Log $ll+1, "$type $name $defs{$d}{NAME}: $value";
      $sumExcluded++;
      $sumValves++;
      $sumFHT++     if($defs{$d}{TYPE} eq "FHT");
      $sumHMCCTC++  if(defined($attr{$d}{model}) && $attr{$d}{model} eq "HM-CC-TC");
      next;
    }

    $value = "$valveState%";
    $valves{$defs{$d}{NAME}}{state} = $value;
    $ret .= "$defs{$d}{NAME}: $value" if($list);
    Log $ll+1, "$type $name $defs{$d}{NAME}: $value";

    # get last readings
    $valveLastDemand = ReadingsVal($name,$d."_demand",0);

    # check heat demand from each valve
    if($valveState >= $valveThresholdOn) {
      $heatDemand = 1;
      $valveNewDemand = $heatDemand;
      $ret .= " (demand)\n" if($list);
      $sumDemand++;
    } else {

      if($valveLastDemand == 1) {
        if($valveState > $valveThresholdOff) {
          $heatDemand = 1;
          $valveNewDemand = $heatDemand;
          $ret .= " (demand)\n" if($list);
          $sumDemand++;
        } else {
          $valveNewDemand = 0;
          $ret .= " (idle)\n" if($list);
          $valvesIdle++;
        }
      } else {
        $valveNewDemand = 0;
        $ret .= " (idle)\n" if($list);
        $valvesIdle++;
      }
    }

    $valves{$defs{$d}{NAME}}{demand} = $valveNewDemand;

    # count devices
    $sumFHT++     if($defs{$d}{TYPE} eq "FHT");
    $sumHMCCTC++  if($attr{$d}{model} eq "HM-CC-TC");
    $sumValves++;
  }

  # overdrive mode
  my $sensor = AttrVal($name,"sensor",undef);
  my $sensorReading      = AttrVal($name,"sensorReading",undef);
  my $sensorThresholdOn  = AttrVal($name,"sensorThresholdOn",undef);
  my $sensorThresholdOff = AttrVal($name,"sensorThresholdOff",undef);
  my $tempValue;
  my $overdrive = "no";

  if(defined($sensor) && defined($sensorThresholdOn) && defined($sensorThresholdOff) && defined($sensorReading)) {
    
    if(!defined($defs{$sensor})) {
      Log 1, "$type $name Device $sensor not defined. Please add this device first!";
    } else {
      $tempValue = ReadingsVal($sensor,$sensorReading,"");
      if(!$tempValue || $tempValue !~ m/^.*\d+.*$/) {
        Log 1, "$type $name Device $sensor has no valid value.";
      } else {
        $tempValue =~ s/(\s|°|[A-Z]|[a-z])+//g;
    
        $heatDemand = 2 if($tempValue <= $sensorThresholdOn);
        $heatDemand = 3 if($tempValue > $sensorThresholdOff);
        $overdrive = "yes" if($heatDemand == 2 || $heatDemand == 3);
      }
    }
  } else {
    if(!$sensor) {
      delete $hash->{READINGS}{sensor};
      delete $hash->{READINGS}{overdrive};
      delete $attr{$name}{sensorReading};
      delete $attr{$name}{sensorThresholdOn};
      delete $attr{$name}{sensorThresholdOff};
    }
  }

  #my $sumDemand = $sumValves-$valvesIdle-$sumIgnored-$sumExcluded;
  Log $ll, "$type $name Found $sumValves Device(s): $sumFHT FHT, $sumHMCCTC HM-CC-TC. ".
         "demand: $sumDemand, idle: $valvesIdle, ignored: $sumIgnored, excluded: $sumExcluded, overdrive: $overdrive";

  readingsBeginUpdate($hash);
  for my $d (sort keys %valves) {
    readingsUpdate($hash, $d."_state", $valves{$d}{state});
    readingsUpdate($hash, $d."_demand", $valves{$d}{demand});
  }
  readingsUpdate($hash, "sensor", $tempValue) if(defined($tempValue) && $tempValue ne "");
  readingsEndUpdate($hash, 1);

  return ($list) ? $ret : $heatDemand;
}

1;

=pod
=begin html

<a name="HCS"></a>
<h3>HCS</h3>
<ul>
  Defines a virtual device for monitoring heating valves (FHT, HM-CC-VD) to control
  a central heating unit.<br><br>

  <a name="HCSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HCS &lt;device&gt; &lt;interval&gt; &lt;valveThresholdOn&gt; &lt;valveThresholdOff&gt;</code>
    <br><br>

    <ul>
      <li><code>&lt;device&gt;</code> the name of a predefined device to switch.</li>
      <li><code>&lt;interval&gt;</code> is a digit number. The unit is minutes.</li>
      <li><code>&lt;valveThresholdOn&gt;</code> is a digit number. Threshold upon which device is switched on (heating required).</li>
      <li><code>&lt;valveThresholdOff&gt;</code> is a digit number. Threshold upon which device is switched off (idle).</li>
    </ul>
    <br>

    The HCS (heating control system) device monitors the state of all detected
    valves in a free definable interval (by default: 10 min). 
    <br><br>

    Regulation for heating requirement or suppression of the request can be controlled by 
    valve position using also free definable thresholds.
    <br><br>

    In doing so, the HCS device also includes the hysteresis between two states.
    <br><br>

    Example:<br>
    Threshold valve position for heating requirement: 40% (default)
    Threshold valve position for idle: 35% (default)
    <br><br>

    Heating is required when the "open" position of a valve is more than 40%. HCS
    then activates the defined device until the "open" position of the valve has
    lowered to 35% or less (threshold for idle).
    <br><br>

    In addition, the HCS device supports an optional temp-sensor. The valve-position oriented 
    regulation can be overriden by the reading of the temp-sensor.
    <br><br>

    Example:<br>
    Threshold temperature reading for heating requirement: 10&deg; Celsius
    Threshold temperature reading for idle: 18&deg; Celsius
    <br><br>

    Is a valve reaching or exceeding the threshold for heating requirement (&gt;=40%), but the 
    temperature reading is more than 18&deg; Celcius, the selected device will stay deactivated. 
    The valve-position oriented regulation has been overridden by the temperature reading in this example.
    <br><br>

    The HCS device automatically detects devices which are ignored. Furthermore, certain
    devices can also be excluded of the monitoring manually.
    <br><br>

    To reduce the transmission load, use the attribute event-on-change-reading, e.g.
    <code>attr &lt;name&gt; event-on-change-reading state,demand</code>
    <br><br>

    To avoid frequent switching "on" and "off" of the device, a timeout (in minutes) can be set
    using the attribute <code>idleperiod</code>.
    <br><br>

  <a name="HCSget"></a>
  <b>Get </b>
    <ul>
      <li>valves<br>
          returns the actual valve positions
      </li><br>
    </ul>
  <br>

  <a name="HCSset"></a>
  <b>Set</b>
   <ul>
      <li>interval<br>
          modifies the interval of reading the actual valve positions. The unit is minutes.
      </li><br>
      <li>on<br>
          restarts the monitoring after shutdown by <code>off</code> switch.<br>
          HCS device starts up automatically upon FHEM start or after new device implementation!
      </li><br>
      <li>off<br>
          shutdown of monitoring, can be restarted by using the <code>on</code> command.
      </li><br>
      <li>valveThresholdOn<br>
          defines threshold upon which device is switched on (heating required).
      </li><br>
      <li>valveThresholdOff<br>
          defines threshold upon which device is switched off (idle).
      </li><br>
   </ul>
  <br>

  <a name="HCSattr"></a>
  <b>Attributes</b>
  <ul>
    <li>device<br>
        optional; used to change the device. This is normally done in the <code>define</code> tag.
    </li><br>
    <li>deviceCmdOn<br>
        command to activate the device, e.g. <code>on</code>.
    </li><br>
    <li>deviceCmdOff<br>
        command to deactivate the device, e.g. <code>off</code>.
    </li><br>
    <li>idleperiod<br>
        locks the device to be switched for the specified period. The unit is minutes.
    </li><br>
    <li>sensor<br>
        device name of the temp-sensor (optional).
    </li><br>
    <li>sensorThresholdOn<br>
        threshold for temperature reading activating the defined device
        Must be set if <code>sensor</code> has been defined
    </li><br>
    <li>sensorThresholdOff<br>
        threshold for temperature reading deactivating the defined device.
        Must be set if <code>sensor</code> has been defined
    </li><br>
    <li>sensorReading<br>
         name which is used for saving the "reading" of the defined temp-sensor.
    </li><br>
    <li>valvesExcluded<br>
        space separated list of devices (FHT or HM-CC-TC) for excluding
    <li>valveThresholdOn<br>
         see Set
    </li><br>
    <li>valveThresholdOff<br>
    </li>see Set<br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li><br>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li><br>
  </ul>
  <br>

  </ul>
  <br>

</ul>

=end html
=cut
