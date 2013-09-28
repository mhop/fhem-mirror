################################################################
# $Id$
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
sub HCS_DoInit($);
sub HCS_Undef($$);
sub HCS_checkState($);
sub HCS_Get($@);
sub HCS_Set($@);
sub HCS_setState($$);
sub HCS_getValues($$);

my %gets = (
  "values"      => "",
);

my %sets = (
  "interval"    => "",
  "eco"         => "",
  "mode"        => "",
  "on"          => "",
  "off"         => "",
);

my %defaults = (
  "idleperiod"             => 10,
  "interval"               => 5,
  "deviceCmdOn"            => "on",
  "deviceCmdOff"           => "off",
  "ecoTemperatureOn"       => 16.0,
  "ecoTemperatureOff"      => 17.0,
  "eventOnChangeReading"   => "state,devicestate,eco,overdrive",
  "loglevel"               => 3,
  "mode"                   => "thermostat",
  "thermostatThresholdOn"  => 0.5,
  "thermostatThresholdOff" => 0.5,
  "valveThresholdOn"       => 35,
  "valveThresholdOff"      => 40,
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
  $hash->{NotifyFn} = "HCS_Notify";
  $hash->{AttrList} = "deviceCmdOn deviceCmdOff exclude ecoTemperatureOn ecoTemperatureOff ".
                      "interval idleperiod mode:thermostat,valve ".
                      "sensor sensorThresholdOn sensorThresholdOff sensorReading ".
                      "thermostatThresholdOn thermostatThresholdOff ".
                      "valveThresholdOn valveThresholdOff ".
                      "do_not_notify:1,0 event-on-update-reading event-on-change-reading ".
                      "loglevel:0,1,2,3,4,5,6 disable:0,1";
}

#####################################
sub
HCS_Define($$) {
  my ($hash, $def) = @_;
  my $type = $hash->{TYPE};

  # define <name> HCS <device>
  # define heatingControl HCS KG.hz.LC.SW1.01

  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use 'define <name> HCS <device>'"
    if(@a < 3 || @a > 6);

  my $name = $a[0];

  if(!defined($defs{$a[2]})) {
    my $ret = "Device $a[2] not defined. Please add this device first!";
    Log 1, "$type $name $ret";
    return $ret;
  }

  $hash->{STATE} = "Defined";

  readingsSingleUpdate($hash,"device",$a[2],1);

  HCS_DoInit($hash);

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
HCS_Notify($$) {
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global" ||
            !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));

  return if($attr{$name} && $attr{$name}{disable});

  delete $modules{HCS}{NotifyFn};
  delete $hash->{NTFY_ORDER} if($hash->{NTFY_ORDER});

  HCS_DoInit($hash);

  return undef;
}

#####################################
sub
HCS_DoInit($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  # clean upd old stuff
  foreach my $r ( keys %{$hash->{READINGS}} ) {
    delete $hash->{READINGS}{$r} if($r =~ m/.*_state$/ || $r =~ m/.*_demand$/);
  }

  $attr{$name}{deviceCmdOn}       = AttrVal($name,"deviceCmdOn",$defaults{deviceCmdOn});
  $attr{$name}{deviceCmdOff}      = AttrVal($name,"deviceCmdOff",$defaults{deviceCmdOff});
  $attr{$name}{"event-on-change-reading"} = AttrVal($name,"event-on-change-reading",$defaults{eventOnChangeReading});
  $attr{$name}{interval}          = AttrVal($name,"interval",$defaults{interval});
  $attr{$name}{idleperiod}        = AttrVal($name,"idleperiod",$defaults{idleperiod});
  $attr{$name}{mode}              = AttrVal($name,"mode",$defaults{mode});
  if($attr{$name}{mode} ne "thermostat" && $attr{$name}{mode} ne "valve") {
    Log 1, "$type $name unknown attribute mode '".$attr{$name}{mode}."'. Please use 'thermostat' or 'valve'.";
    return undef;
  }
  $attr{$name}{thermostatThresholdOn}   = AttrVal($name,"thermostatThresholdOn",$defaults{thermostatThresholdOn});
  $attr{$name}{thermostatThresholdOff} = AttrVal($name,"thermostatThresholdOff",$defaults{thermostatThresholdOff});
  $attr{$name}{valveThresholdOn}       = AttrVal($name,"valveThresholdOn",$defaults{valveThresholdOn});
  $attr{$name}{valveThresholdOff}      = AttrVal($name,"valveThresholdOff",$defaults{valveThresholdOff});

  readingsSingleUpdate($hash,"state","Initialized",1);

  if($init_done) {
    my $ret = HCS_getValues($hash,0);
    HCS_setState($hash,$ret);

    RemoveInternalTimer($hash);
    my $timer = gettimeofday()+($attr{$name}{interval}*60);
    InternalTimer($timer, "HCS_checkState", $hash, 0);
    $hash->{NEXTCHECK} = FmtTime($timer);
  }

  return undef;
}

#####################################
sub
HCS_checkState($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $interval = AttrVal($name,"interval",$defaults{interval});
  my $timer;
  my $ret;

  $ret = HCS_getValues($hash,0);
  HCS_setState($hash,$ret);

  RemoveInternalTimer($hash);
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

  if($arg eq "values") {
    $ret = HCS_getValues($hash,1);
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
  my $str;

  # check syntax
  return "argument is missing @a"
    if(int(@a) < 2 || int(@a) > 3);
  # check argument
  return "Unknown argument $a[1], choose one of ".join(" ", sort keys %sets)
    if(!defined($sets{$a[1]}));
 
  # get argument
  my $arg = $a[1];

  if($arg eq "eco") {
    return "argument is missing, choose one of on off"
      if(int(@a) < 3);
    return "Unknown argument $a[2], choose one of on off"
      if(lc($a[2]) ne "on" && lc($a[2]) ne "off");

    my $ecoModeNew = lc($a[2]);
    my $ecoTempOn  = AttrVal($name,"ecoTemperatureOn",undef);
    my $ecoTempOff = AttrVal($name,"ecoTemperatureOff",undef);

    if((!$ecoTempOn || !$ecoTempOff) && $ecoModeNew eq "on") {
      $str = "missing attribute 'ecoTemperatureOn'. Please define this attribute first."
        if(!$ecoTempOn);
      $str = "missing attribute 'ecoTemperatureOff'. Please define this attribute first."
        if(!$ecoTempOff);
      Log 1, "$type $name $str";
      return $str;
    }

    my $ecoModeOld = ReadingsVal($name,"eco","off");
    if($ecoModeNew ne $ecoModeOld) {
      readingsSingleUpdate($hash, "eco",$ecoModeNew,1);
      $str = "eco mode changed from $ecoModeOld to $ecoModeNew";
      Log 1, "$type $name $str";
      return $str;
    } else {
      return "eco mode '$ecoModeNew' already set.";
    }

  } elsif($arg eq "interval") {

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

  } elsif($arg eq "mode") {
    return "argument is missing, choose one of thermostat valve"
      if(int(@a) < 3);
    return "Unknown argument $a[2], choose one of thermostat valve"
      if(lc($a[2]) ne "thermostat" && lc($a[2]) ne "valve");

    my $modeNew = $a[2];
    my $modeOld = AttrVal($name,"mode","thermostat");

    if($modeNew ne $modeOld) {
      $attr{$name}{mode} = "thermostat" if(lc($a[2]) eq "thermostat");
      $attr{$name}{mode} = "valve"      if(lc($a[2]) eq "valve");
      $str = "mode changed from $modeOld to $modeNew";
      Log 1, "$type $name $str";
    } else {
      return "mode '$modeNew' already set.";
    }

  } elsif($arg eq "on") {
    RemoveInternalTimer($hash);
    HCS_checkState($hash);
    Log 1, "$type $name monitoring of devices started";
  } elsif($arg eq "off") {
    RemoveInternalTimer($hash);
    $hash->{NEXTCHECK} = "offline";
    readingsSingleUpdate($hash, "state", "off",1);
    Log 1, "$type $name monitoring of devices interrupted";
  }

}

#####################################
sub
HCS_setState($$) {
  my ($hash,$heatDemand) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $ll   = AttrVal($name,"loglevel",$defaults{loglevel});
  my $device         = ReadingsVal($name,"device","");
  my $deviceState    = Value($device);
  my $deviceCmdOn    = AttrVal($name,"deviceCmdOn",$defaults{deviceCmdOn});
  my $deviceCmdOff   = AttrVal($name,"deviceCmdOff",$defaults{deviceCmdOff});
  my $eco            = ReadingsVal($name,"eco","off");
  my $idlePeriod     = AttrVal($name,"idleperiod",$defaults{idleperiod});
  my $lastPeriodTime = ($hash->{helper}{lastSentDeviceCmdOn}) ? $hash->{helper}{lastSentDeviceCmdOn} : 0;
  my $newPeriodTime  = int(gettimeofday());
  my $diffPeriodTime = int((int($newPeriodTime)-int($lastPeriodTime))/60);
  my $overdrive      = "off";
  my $idle           = 0;
  my $wait           = "00:00:00";
  my $cmd;
  my $mode;
  my $state;
  my $stateDevice;

  if($heatDemand == 0) {
    $state = "idle";
    $cmd = $deviceCmdOff;
  } elsif($heatDemand == 1) {
    $state = "demand";
    $cmd = $deviceCmdOn;
  } elsif($heatDemand == 2) {
    $eco = "on";
    $state = "idle (eco)";
    $cmd = $deviceCmdOff;
  } elsif($heatDemand == 3) {
    $eco = "on";
    $state = "demand (eco)";
    $cmd = $deviceCmdOn;
  } elsif($heatDemand == 4) {
    $overdrive = "on";
    $state = "idle (overdrive)";
    $cmd = $deviceCmdOff;
  } elsif($heatDemand == 5) {
    $overdrive = "on";
    $state = "demand (overdrive)";
    $cmd = $deviceCmdOn;
  }

  my $eventOnChange = AttrVal($name,"event-on-change-reading","");
  my $eventOnUpdate = AttrVal($name,"event-on-update-reading","");
  $stateDevice = ReadingsVal($name,"devicestate",$defaults{deviceCmdOff});

  if($idlePeriod && $diffPeriodTime < $idlePeriod) {
    $wait = FmtTime((($idlePeriod-$diffPeriodTime)*60)-3600);
    if($heatDemand == 1 || $heatDemand == 3 || $heatDemand == 5 && $cmd eq $deviceCmdOn) {
      $idle = 1;
      $state = "locked" if($stateDevice eq $deviceCmdOff);
    }
  }

  readingsBeginUpdate($hash);
  if(!$defs{$device}) {
    $state = "error";
    Log 1, "$type $name device '$device' does not exists.";
  } else {
    if($idle == 1 && $cmd eq $deviceCmdOn && $stateDevice ne $deviceCmdOn) {
      Log $ll, "$type $name device $device locked for $wait min.";
    } else {

      if(!$eventOnChange ||
          ($eventOnUpdate && $eventOnUpdate =~ m/devicestate/ ||
           $eventOnChange && $eventOnChange =~ m/devicestate/ ) &&
          ($cmd ne $stateDevice || $deviceState ne $stateDevice)) {
        my $cmdret = CommandSet(undef,"$device $cmd");
        if($cmdret) {
          Log 1, "$type $name An error occurred while switching device '$device': $cmdret";
        } else {
          readingsBulkUpdate($hash, "devicestate", $cmd);
          if($cmd eq $deviceCmdOn) {
            $hash->{helper}{lastSentDeviceCmdOn} = $newPeriodTime;
            $wait = FmtTime((($idlePeriod)*60)-3600);
          }
        }
      }

    }

  }

  readingsBulkUpdate($hash, "eco", $eco);
  readingsBulkUpdate($hash, "locked", $wait);
  readingsBulkUpdate($hash, "overdrive", $overdrive);
  readingsBulkUpdate($hash, "state", $state);
  readingsEndUpdate($hash, 1);

  return undef;
}

#####################################
sub
HCS_getValues($$) {
  my ($hash,$list) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my %devs = ();
  my $exclude = AttrVal($name,"exclude","");
  my @lengthNames;
  my @lengthValves;
  my $ret;

  # get devices
  foreach my $d (sort keys %defs) {
    my $t = $defs{$d}{TYPE};
    # skipping unneeded devices
    next if($t ne "FHT" && $t ne "CUL_HM");

    next if($t eq "CUL_HM" &&(   !$attr{$d}{model}
	                          ||!(  ($attr{$d}{model} eq "HM-CC-TC"    && !$defs{$d}{device})
	                              ||($attr{$d}{model} eq "HM-CC-RT-DN" && !$defs{$d}{device}))));

    $devs{$d}{actuator}     = ReadingsVal($d,"actuator","n/a");
	
    if ($devs{$d}{actuator} =~ m/^\d+\s*%$/) { $devs{$d}{actuator} =~ s/(\s+|%)//g;
    } else {                                   $devs{$d}{actuator} = 0;
    }
    $devs{$d}{excluded}     = ($exclude =~ m/$d/) ? 1 : 0;
    $devs{$d}{ignored}      = ($attr{$d}{ignore} && $attr{$d}{ignore} == 1) ? 1 : 0;
    $devs{$d}{tempDesired}  = ReadingsVal($d,"desired-temp","n/a");
    $devs{$d}{tempMeasured} = ReadingsVal($d,"measured-temp","n/a");
    $devs{$d}{type}         = $t;
    $hash->{helper}{device}{$d}{excluded} = $devs{$d}{excluded};
    $hash->{helper}{device}{$d}{ignored}  = $devs{$d}{ignored};
    push(@lengthNames,$d);
    push(@lengthValves,$devs{$d}{actuator});
  }

  my $ln = (reverse sort { $a <=> $b } map { length($_) } @lengthNames)[0];
  my $lv = (reverse sort { $a <=> $b } map { length($_) } @lengthValves)[0];

  # show list of devices
  if($list) {
    my $nextCheck = ($hash->{NEXTCHECK}) ? $hash->{NEXTCHECK} : "n/a";
    my $delta;
    my $str;

    foreach my $d (sort keys %{$hash->{helper}{device}}) {
      my $info = "";
      my $act = ($hash->{helper}{device}{$d}{actuator} eq "n/a")     ? " n/a" :
                  sprintf("%${lv}d",$hash->{helper}{device}{$d}{actuator});
      my $td  = ($hash->{helper}{device}{$d}{tempDesired} eq "n/a")  ? " n/a" :
                  sprintf("%4.1f",$hash->{helper}{device}{$d}{tempDesired});
      my $tm  = ($hash->{helper}{device}{$d}{tempMeasured} eq "n/a") ? " n/a" :
                  sprintf("%4.1f",$hash->{helper}{device}{$d}{tempMeasured});
      $info   = "idle"       if($hash->{helper}{device}{$d}{demand} == 0);
      $info   = "demand"     if($hash->{helper}{device}{$d}{demand} == 1);
      $info   = "(excluded)" if($hash->{helper}{device}{$d}{excluded} == 1);
      $info   = "(ignored)"  if($hash->{helper}{device}{$d}{ignored} == 1);

      if($td eq " n/a" || $tm eq " n/a") {
        $delta = " n/a";
      } else {
        $delta  = sprintf(" %.1f",$td-$tm);
        $delta  = sprintf("+%.1f",$tm-$td) if($tm > $td);
        $delta  = sprintf("-%.1f",$td-$tm) if($td > $tm);
      }
      $str   .= sprintf("%-${ln}s: desired: %s°C measured: %s°C delta: %s valve: %${lv}d%% state: %s\n",
                      $d,$td,$tm,$delta,$act,$info);
    }

    $str .= "next check: $nextCheck\n";
    $ret = $str;

    return $ret;
  }

  # housekeeping
  foreach my $d (sort keys %{$hash->{helper}{device}}) {
    delete $hash->{helper}{device}{$d} if(!exists $devs{$d});
  }

  # reset counter
  my $sumDemand   = 0;
  my $sumExcluded = 0;
  my $sumFHT      = 0;
  my $sumHMCCTC   = 0;
  my $sumIdle     = 0;
  my $sumIgnored  = 0;
  my $sumTotal    = 0;
  my $sumUnknown  = 0;

  my $ll   = AttrVal($name,"loglevel",$defaults{loglevel});
  my $mode = AttrVal($name,"mode",$defaults{mode});

  readingsBeginUpdate($hash);
  foreach my $d (sort keys %devs) {
    my $devState;
    $hash->{helper}{device}{$d}{actuator}     = $devs{$d}{actuator};
    $hash->{helper}{device}{$d}{excluded}     = $devs{$d}{excluded};
    $hash->{helper}{device}{$d}{ignored}      = $devs{$d}{ignored};
    $hash->{helper}{device}{$d}{tempDesired}  = $devs{$d}{tempDesired};
    $hash->{helper}{device}{$d}{tempMeasured} = $devs{$d}{tempMeasured};
    $hash->{helper}{device}{$d}{type}         = $devs{$d}{type};
    $sumFHT++       if(lc($devs{$d}{type}) eq "fht");
    $sumHMCCTC++    if(lc($devs{$d}{type}) eq "cul_hm");
    $sumTotal++;

    if($devs{$d}{ignored}) {
      $devState = "ignored";
      $hash->{helper}{device}{$d}{demand} = 0;
      readingsBulkUpdate($hash,$d,$devState);
      Log $ll+1, "$type $name $d: $devState";
      $sumIgnored++;
      next;
    }

    if($devs{$d}{excluded}) {
      $devState = "excluded";
      $hash->{helper}{device}{$d}{demand} = 0;
      readingsBulkUpdate($hash,$d,$devState);
      Log $ll+1, "$type $name $d: $devState";
      $sumExcluded++;
      next;
    }

    if($mode eq "thermostat" && ($devs{$d}{tempMeasured} eq "n/a" || $devs{$d}{tempDesired} eq "n/a")) {
      $devState = "unknown";
      $hash->{helper}{device}{$d}{demand} = 0;
      readingsBulkUpdate($hash,$d,$devState);
      Log $ll+1, "$type $name $d: $devState";
      $sumUnknown++;
      next;
    }

    my $lastState = ReadingsVal($name,$d,"idle");
    my $act = $devs{$d}{actuator};
    my $tm  = $devs{$d}{tempMeasured};
    my $td  = $devs{$d}{tempDesired};
    my $delta;
    my $str;

    if(!$hash->{helper}{device}{$d}{demand}) {
      $hash->{helper}{device}{$d}{demand} = 0;
      $lastState = "idle";
    }

    if($mode eq "thermostat") {
      my $tOn   = AttrVal($name,"thermostatThresholdOn",$defaults{thermostatThresholdOn});
      my $tOff  = AttrVal($name,"thermostatThresholdOff",$defaults{thermostatThresholdOff});

      if($tm > $td && $tm-$td >= $tOff) {
        $devState = "idle";
        $hash->{helper}{device}{$d}{demand} = 0;
        $delta = $tm-$td;
        $str = sprintf("desired: %4.1f measured: %4.1f delta: +%.1f open: %${lv}d%% state: %s",$td,$tm,$delta,$act,$devState);
        $sumIdle++;
      } elsif($td > $tm && $td-$tm >= $tOn) {
        $devState = "demand";
        $hash->{helper}{device}{$d}{demand} = 1;
        $delta = $td-$tm;
        $str = sprintf("desired: %4.1f measured: %4.1f delta: -%.1f open: %${lv}d%% state: %s",$td,$tm,$delta,$act,$devState);
        $sumDemand++;
      } elsif($tm > $td) {
        $devState = $lastState;
        $delta = $tm-$td;
        $str = sprintf("desired: %4.1f measured: %4.1f delta: +%.1f open: %${lv}d%% state: %s",$td,$tm,$delta,$act,$devState);
        $sumIdle++   if($devState eq "idle");
        $sumDemand++ if($devState eq "demand");
      } elsif($td > $tm) {
        $devState = $lastState;
        $delta = $td-$tm;
        $str = sprintf("desired: %4.1f measured: %4.1f delta: -%.1f open: %${lv}d%% state: %s",$td,$tm,$delta,$act,$devState);
        $sumIdle++   if($devState eq "idle");
        $sumDemand++ if($devState eq "demand");
      } else {
        $devState = $lastState;
        $delta = $td-$tm;
        $str = sprintf("desired: %4.1f measured: %4.1f delta:  %.1f open: %${lv}d%% state: %s",$td,$tm,$delta,$act,$devState);
        $sumIdle++   if($devState eq "idle");
        $sumDemand++ if($devState eq "demand");
      }
    } elsif($mode eq "valve") {
      my $vOn   = AttrVal($name,"valveThresholdOn",$defaults{valveThresholdOn});
      my $vOff  = AttrVal($name,"valveThresholdOff",$defaults{valveThresholdOff});
      my $valve = $devs{$d}{actuator};

      if($valve >= $vOn) {
        $devState = "demand";
        $hash->{helper}{device}{$d}{demand} = 1;
        $sumDemand++;
      } else {

        if($lastState eq "demand") {
          if($valve > $vOff) {
            $devState = "demand";
            $hash->{helper}{device}{$d}{demand} = 1;
            $sumDemand++;
          } else {
            $devState = "idle";
            $hash->{helper}{device}{$d}{demand} = 0;
            $sumIdle++;
          }
        } else {
          $devState = "idle";
          $hash->{helper}{device}{$d}{demand} = 0;
          $sumIdle++;
        }

      }
      $delta = sprintf(" %.1f",$td-$tm);
      $delta = sprintf("+%.1f",$tm-$td) if($tm > $td);
      $delta = sprintf("-%.1f",$td-$tm) if($td > $tm);
      $str = sprintf("desired: %4.1f measured: %4.1f delta: %s valve: %${lv}d%% state: %s",$td,$tm,$delta,$valve,$devState);
    }

    Log $ll+1, "$type $name $d: $str";
    readingsBulkUpdate($hash,$d,$devState);

  }
  readingsEndUpdate($hash,1);

  my $heatDemand = 0;

  foreach my $d (sort keys %{$hash->{helper}{device}}) {
    $heatDemand = 1 if($hash->{helper}{device}{$d}{demand} && $hash->{helper}{device}{$d}{demand} == 1);
  }

  # eco mode
  my $eco = "no";
  my $ecoTempOn  = AttrVal($name,"ecoTemperatureOn",undef);
  my $ecoTempOff = AttrVal($name,"ecoTemperatureOff",undef);
  my $ecoState   = ReadingsVal($name,"eco","off");

  if($ecoState eq "on" && (!$ecoTempOn || !$ecoTempOff)) {
    Log 1, "$type $name missing attribute 'ecoTemperatureOn'. Please define this attribute first."
      if(!$ecoTempOn);
    Log 1, "$type $name missing attribute 'ecoTemperatureOff'. Please define this attribute first."
      if(!$ecoTempOff);
  } elsif($ecoState eq "on") {
    foreach my $d (sort keys %{$hash->{helper}{device}}) {
      my $ignore  = $hash->{helper}{device}{$d}{ignored};
      my $exclude = $hash->{helper}{device}{$d}{excluded};
      my $tempMeasured = $hash->{helper}{device}{$d}{tempMeasured};
      next if($tempMeasured eq "n/a");
      if(!$ignore && !$exclude) {
        $heatDemand = 2 if($tempMeasured >= $ecoTempOff && $heatDemand != 3);
        $heatDemand = 3 if($tempMeasured <= $ecoTempOn);
        $eco = "yes" if($heatDemand == 2 || $heatDemand == 3);
      }
    }
  }

  # overdrive mode
  my $overdrive    = "no";
  my $sensor       = AttrVal($name,"sensor",undef);
  my $sReading     = AttrVal($name,"sensorReading",undef);
  my $sTresholdOn  = AttrVal($name,"sensorThresholdOn",undef);
  my $sTresholdOff = AttrVal($name,"sensorThresholdOff",undef);

  if(!$sensor) {
    delete $hash->{READINGS}{sensor}    if($hash->{READINGS}{sensor});
  } else {
    Log 1, "$type $name Device $sensor not defined. Please add this device first!"
      if(!defined($defs{$sensor}));
    Log 1, "$type $name missing attribute 'sensorReading'. Please define this attribute first."
      if(!$sReading);
    Log 1, "$type $name missing attribute 'sensorThresholdOn'. Please define this attibute first."
      if(!$sTresholdOn);
    Log 1, "$type $name missing attribute 'sensorThresholdOff'. Please define this attribute first."
      if(!$sTresholdOff);

    if($defs{$sensor} && $sReading && $sTresholdOn && $sTresholdOff) {
      my $tValue = ReadingsVal($sensor,$sReading,"n/a");
      if($tValue eq "n/a" || $tValue !~ m/^.*\d+.*$/) {
        Log 1, "$type $name Device $sensor has no valid value.";
      } else {
        $tValue =~ s/(\s|°|[A-Z]|[a-z])+//g;
        $heatDemand = 4 if($tValue >= $sTresholdOff);
        $heatDemand = 5 if($tValue <= $sTresholdOn);
        $overdrive  = "yes" if($heatDemand == 4 || $heatDemand == 5);
        readingsSingleUpdate($hash,"sensor",$tValue,1);
      }
    }

  }
  my $str = sprintf("Found %d Device(s): %d FHT, %d HM-CC-TC, demand: %d, idle: %d, ignored: %d, exlcuded: %d, unknown: %d",
                    $sumTotal,$sumFHT,$sumHMCCTC,$sumDemand,$sumIdle,$sumIgnored,$sumExcluded,$sumUnknown);
  Log $ll, "$type $name $str, eco: $eco overdrive: $overdrive";

  return $heatDemand;

}

1;

=pod
=begin html

<a name="HCS"></a>
<h3>HCS</h3>
<ul>
  Defines a virtual device for monitoring thermostats (FHT, HM-CC-TC) to control a central
  heating unit.<br><br>

  <a name="HCSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HCS &lt;device&gt;</code>
    <br><br>

    <ul>
      <li><code>&lt;device&gt;</code> the name of a predefined device to switch.</li>
    </ul>
    <br>

    The HCS (heating control system) device monitors the state of all detected thermostats
    in a free definable interval (by default: 10 min). 
    <br><br>

    Regulation for heating requirement or suppression of the request can be controlled by 
    valve position or measured temperature (default) using also free definable thresholds.
    In doing so, the HCS device also includes the hysteresis between two states.
    <br><br>

    Example for monitoring measured temperature:
    <ul>
      Threshold temperature for heating requirement: 0.5 (default)<br>
      Threshold temperature for idle: 0.5 (default)<br>
      <br>

      Heating is required when the measured temperature of a thermostat is lower than
      0.5&deg; Celsius as the desired temperature. HCS then activates the defined device
      until the measured temperature of the thermostat is 0.5&deg; Celsius higher as the
      desired temperature (threshold for idle). In this example, both tresholds are equal.
    </ul>
    <br>

    Example for monitoring valve position:
    <ul>
      Threshold valve position for heating requirement: 40% (default)<br>
      Threshold valve position for idle: 35% (default)<br>
      <br>

      Heating is required when the "open" position of a valve is more than 40%. HCS then
      activates the defined device until the "open" position of the valve has lowered to
      35% or less (threshold for idle).
    </ul>
    <br>

    The HCS device supports an optional eco mode. The threshold oriented regulation by
    measured temperature or valve position can be overridden by setting economic thresholds.
    <br><br>
    
    Example:
    <ul>
      Threshold temperature economic mode on: 15&deg; Celsius<br>
      Threshold temperature economic mode off: 25&deg; Celsius<br>
      <br>
    
      HCS activates the defined device until the measured temperature of one ore more
      thermostats is lower or equal than 15&deg; Celsius. If a measured temperature of one 
      or more thermostats is higher or equal than 25&deg; Celsius, HCS switch of the defined 
      device (if none of the measured temperatures of all thermostats is lower or equal as
      15&deg; Celsius).
    </ul>
    <br>
    
    In addition, the HCS device supports an optional temp-sensor. The threshold and economic
    oriented regulation can be overriden by the reading of the temp-sensor (overdrive mode).
    <br><br>

    Example:
    <ul>
      Threshold temperature reading for heating requirement: 10&deg; Celsius<br>
      Threshold temperature reading for idle: 18&deg; Celsius<br>
      <br>

      Is a measured temperature ore valve position reaching or exceeding the threshold for
      heating requirement, but the temperature reading is more than 18&deg; Celcius, the 
      selected device will stay deactivated. The measured temperature or valve-position 
      oriented regulation has been overridden by the temperature reading in this example.
    </ul>
    <br>

    The HCS device automatically detects devices which are ignored. Furthermore, certain
    devices can also be excluded of the monitoring manually.
    <br><br>

    To reduce the transmission load, use the attribute event-on-change-reading, e.g.
    <code>attr &lt;name&gt; event-on-change-reading state,devicestate,eco,overdrive</code>
    <br><br>

    To avoid frequent switching "on" and "off" of the device, a timeout (in minutes) can be set
    using the attribute <code>idleperiod</code>.
    <br><br>

  <a name="HCSget"></a>
  <b>Get </b>
    <ul>
      <li><code>values</code><br>
          returns the actual values of each device
      </li>
    </ul>
  <br>

  <a name="HCSset"></a>
  <b>Set</b>
   <ul>
      <li><code>eco &lt;on&gt;|&lt;off&gt;</code><br>
          enable (<code>on</code>) or disable (<code>off</code>) the economic mode.
      </li>
      <li><code>interval &lt;value&gt;</code><br>
          <code>value</code> modifies the interval of reading the actual valve positions.
          The unit is minutes.
      </li>
      <li><code>mode &lt;thermostat&gt;|&lt;valve&gt;</code><br>
          changes the operational mode:<br>
          <code>thermostat</code> controls the heating demand by defined temperature
          thresholds.<br>
          <code>valve</code> controls the heating demand by defined valve position thresholds.
      </li>
      <li><code>on</code><br>
          restarts the monitoring after shutdown by <code>off</code> switch.<br>
          HCS device starts up automatically upon FHEM start or after new device implementation!
      </li>
      <li><code>off</code><br>
          shutdown of monitoring, can be restarted by using the <code>on</code> command.
      </li>
   </ul>
  <br>

  <a name="HCSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><code>deviceCmdOn</code> (mandatory)<br>
        command to activate the device, e.g. <code>on</code>.
        Default value: <code>on</code>
    </li>
    <li><code>deviceCmdOff</code> (mandatory)<br>
        command to deactivate the device, e.g. <code>off</code>.
        Default value: <code>off</code>
    </li>
    <li><code>ecoTemperatureOn</code> (Required by <code>eco</code> mode)<br>
        defines threshold for measured temperature upon which device is allways switched on
    </li>
    <li><code>ecoTemperatureOff</code> (Required by <code>eco</code> mode)<br>
        defines threshold for measured temperature upon which device is switched off
    </li>
    <li><code>exclude</code> (optional)<br>
        space or comma separated list of devices (FHT or HM-CC-TC) for excluding from
        monitoring
    </li>
    <li><code>idleperiod</code> (mandatory)<br>
        locks the device to be switched for the specified period. The unit is minutes.
        Default value: <code>10</code>
    </li>
    <li><code>mode</code> (mandatory)<br>
        defines the operational mode:<br>
        <code>thermostat</code> controls the heating demand by defined temperature
        thresholds.<br>
        <code>valve</code> controls the heating demand by defined valve position thresholds.<br>
        Default value: <code>thermostat</code>
    </li>
    <li><code>sensor</code> (optional)<br>
        device name of the temp-sensor
    </li>
    <li><code>sensorThresholdOn</code> (Required by <code>sensor</code>)<br>
        threshold for temperature reading activating the defined device
        Must be set if <code>sensor</code> has been defined
    </li>
    <li><code>sensorThresholdOff</code> (Required by <code>sensor</code>)<br>
        threshold for temperature reading deactivating the defined device.
        Must be set if <code>sensor</code> has been defined
    </li>
    <li><code>sensorReading</code> (Required by <code>sensor</code>)<br>
         name which is used for saving the "reading" of the defined temp-sensor.
    </li>
    <li><code>thermostatThresholdOn</code> (Required by operational mode <code>thermostat</code>)<br>
        defines delta threshold between desired and measured temperature upon which device
        is switched on (heating required).<br>
        Default value: <code>0.5</code>
    </li>
    <li><code>thermostatThresholdOff</code> (Required by operational mode <code>thermostat</code>)<br>
        defines delta threshold between desired and measured temperature upon which
        device is switched off (idle).<br>
        Default value: <code>0.5</code>
    </li>
    <li><code>valveThresholdOn</code> (Required by operational mode <code>valve</code>)<br>
        defines threshold of valve-position upon which device is switched on (heating
        required).<br>
        Default value: <code>40</code>
    </li>
    <li><code>valveThresholdOff</code> (Required by operational mode <code>valve</code>)<br>
        defines threshold of valve-position upon which device is switched off (idle).<br>
        Default value: <code>35</code>
    </li>
    <li><a href="#disable"><code>disable</code></a></li>
    <li><a href="#do_not_notify"><code>do_not_notify</code></a></li>
    <li><a href="#event-on-change-reading"><code>event-on-change-reading</code></a><br>
        default value: <code>state,devicestate,eco,overdrive</code>
    </li>
    <li><a href="#event-on-update-reading"><code>event-on-update-reading</code></a></li>
    <li><a href="#loglevel"><code>loglevel</code></a><br>
        loglevel 3 (or lower) shows a complete statistic of scanned devices (FHT or HM-CC-TC).<br>
        loglevel 4 shows a short summary of scanned devices.<br>
        loglevel 5 suppressed the above messages.
    </li>
  </ul>
  <br>

  </ul>
  <br>

</ul>

=end html
=cut
