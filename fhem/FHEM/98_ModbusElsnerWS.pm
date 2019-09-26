# $Id$
# This modules handles the communication with a Elsner Weather Station P03/3-Modbus.

package main;
use strict;
use warnings;
sub ModbusElsnerWS_Initialize($);

my %ModbusElsnerWS_ParseInfo = (
  'i0'  => {reading => 'raw',
            name => 'raw',
            expr => 'sprintf("%.1f %d %d %d %d %.1f %d %s %04d-%02d-%02d %02d:%02d:%02d %.1f %.1f %.2f %.2f",
	             $val[0] / 10,
	             $val[1] * 1000,
	             $val[2] * 1000,
	             $val[3] * 1000,
	             $val[4],
	             $val[5] / 10,
	             $val[6],
	             $val[7] == 1 ? "yes" : "no",
	             $val[10],
	             $val[9],
	             $val[8],
	             $val[11],
	             $val[12],
	             $val[13],
	             $val[14] / 10,
	             $val[15] / 10,
	             $val[16] / 100,
	             $val[17] / 100)',
            unpack => 's>nnnnnCCnnnnnnns>s>s>',
            len => 17,
            poll => 1
          }
);

my %ModbusElsnerWS_DeviceInfo = (
  'i' => {defShowGet => 1,
          combine => 17
	 }
);

sub ModbusElsnerWS_Initialize($) {
  my ($hash) = @_;
  require "$attr{global}{modpath}/FHEM/DevIo.pm";
  LoadModule "Modbus";

  $hash->{parseInfo}  = \%ModbusElsnerWS_ParseInfo;  # defines registers, inputs, coils etc. for this Modbus Device
  $hash->{deviceInfo} = \%ModbusElsnerWS_DeviceInfo; # defines properties of the device like defaults and supported function codes
  ModbusLD_Initialize($hash); # Generic function of the Modbus module does the rest

  $hash->{DefFn}            = "ModbusElsnerWS_Define";
  $hash->{UndefFn}          = "ModbusElsnerWS_Undef";
  $hash->{DeleteFn}         = "ModbusElsnerWS_Delete";
  $hash->{SetFn}            = "ModbusElsnerWS_Set";
  $hash->{GetFn}            = "ModbusElsnerWS_Get";
  $hash->{NotifyFn}         = "ModbusElsnerWS_Notify";
  $hash->{ModbusReadingsFn} = "ModbusElsnerWS_Eval";
  $hash->{AttrFn}           = "ModbusElsnerWS_Attr";
  $hash->{AttrList}        .= ' ' .
                              #$hash->{ObjAttrList} . ' ' . $hash->{DevAttrList}.
                              ' brightnessDayNight brightnessDayNightDelay' .
                              ' brightnessSunny brightnessSunnySouth brightnessSunnyWest brightnessSunnyEast' .
                              ' brightnessSunnyDelay brightnessSunnySouthDelay brightnessSunnyWestDelay brightnessSunnyEastDelay' .
                              ' poll-.* polldelay-.* timeEvent:no,yes updateGlobalAttr:no,yes' .
                              ' windSpeedWindy windSpeedStormy windSpeedWindyDelay windSpeedStormyDelay ' .
                              $readingFnAttributes;
  $hash->{parseParams}      = 1;
  $hash->{NotifyOrderPrefix} = "55-";
  return;
}

sub ModbusElsnerWS_Define($$) {
  # my ($hash, $def) = @_;
  #return "ModbusElsnerWS: wrong syntax, correct is: define <name> ModbusElsnerWS (modbusid) {interval}" if($#$a != 2);

  my ($hash, $a, $h) = @_;
  my $name = $a->[0];
  if (defined $a->[2]) {
    $hash->{MODBUSID} = $a->[2];
  } elsif (exists $h->{id}) {
    $hash->{MODBUSID} = $h->{id};
  } else {
    return "ModbusElsnerWS: wrong syntax, correct is: define <name> ModbusElsnerWS [id=](modbusid) [interval=]{interval}";
  }
  if (defined $a->[3]) {
    $hash->{INTERVAL} = $a->[3];
  } elsif (exists $h->{interval}) {
    $hash->{INTERVAL} = $h->{interval};
  } else {
    return "ModbusElsnerWS: wrong syntax, correct is: define <name> ModbusElsnerWS [id=](modbusid) [interval=]{interval}";
  }
  if ($hash->{INTERVAL} !~ m/^(\d+|passive)$/) {
    return "ModbusElsnerWS: wrong syntax, correct is: interval >= 1 or passive";
  }
  my $def = "$name ModbusElsnerWS $hash->{MODBUSID} $hash->{INTERVAL}";
  $hash->{NOTIFYDEV} = "global";
  # deactivate modbus set commands
  $attr{$name}{enableControlSet} = 0;
  my ($autocreateFilelog, $autocreateHash, $autocreateName, $autocreateDeviceRoom, $autocreateWeblinkRoom) =
       ('./log/' . $name . '-%Y-%m.log', undef, 'autocreate', 'ElsnerWS', 'Plots');
  my ($cmd, $filelogName, $gplot, $ret, $weblinkName, $weblinkHash) =
       (undef, "FileLog_$name", "ElsnerWS:SunIntensity,ElsnerWS_2:Temperature/Brightness,ElsnerWS_3:WindSpeed/Raining,", undef, undef, undef);
  # find autocreate device
  while (($autocreateName, $autocreateHash) = each(%defs)) {
    last if ($defs{$autocreateName}{TYPE} eq "autocreate");
  }
  $autocreateDeviceRoom = AttrVal($autocreateName, "device_room", $autocreateDeviceRoom) if (defined $autocreateName);
  $autocreateDeviceRoom = 'ElsnerWS' if ($autocreateDeviceRoom eq '%TYPE');
  $autocreateDeviceRoom = $name if ($autocreateDeviceRoom eq '%NAME');
  $autocreateDeviceRoom = AttrVal($name, "room", $autocreateDeviceRoom);
  $attr{$name}{room} = $autocreateDeviceRoom if (!exists $attr{$name}{room});
  if ($init_done) {
    Log3 $name, 2, "ModbusElsnerWS define " . join(' ', @$a);
    if (!defined(AttrVal($autocreateName, "disable", undef)) && !exists($defs{$filelogName})) {
      # create FileLog
      $autocreateFilelog = $attr{$autocreateName}{filelog} if (exists $attr{$autocreateName}{filelog});
      $autocreateFilelog =~ s/%NAME/$name/g;
      $cmd = "$filelogName FileLog $autocreateFilelog $name";
      $ret = CommandDefine(undef, $cmd);
      if($ret) {
        Log3 $filelogName, 2, "ModbusElsnerWS ERROR: $ret";
      } else {
       $attr{$filelogName}{room} = $autocreateDeviceRoom;
       $attr{$filelogName}{logtype} = 'text';
       Log3 $filelogName, 2, "ModbusElsnerWS define $cmd";
      }
    }
    if (!defined(AttrVal($autocreateName, "disable", undef)) && exists($defs{$filelogName})) {
      # create FileLog
      # add GPLOT parameters
      $attr{$filelogName}{logtype} = $gplot . $attr{$filelogName}{logtype}
        if (!exists($attr{$filelogName}{logtype}) || $attr{$filelogName}{logtype} eq 'text');
      if (AttrVal($autocreateName, "weblink", 1)) {
        $autocreateWeblinkRoom = $attr{$autocreateName}{weblink_room} if (exists $attr{$autocreateName}{weblink_room});
        $autocreateWeblinkRoom = 'ElsnerWS' if ($autocreateWeblinkRoom eq '%TYPE');
        $autocreateWeblinkRoom = $name if ($autocreateWeblinkRoom eq '%NAME');
        $autocreateWeblinkRoom = $attr{$name}{room} if (exists $attr{$name}{room});
        my $wnr = 1;
        #create SVG devices
        foreach my $wdef (split(/,/, $gplot)) {
          next if(!$wdef);
          my ($gplotfile, $stuff) = split(/:/, $wdef);
          next if(!$gplotfile);
          $weblinkName = "SVG_$name";
          $weblinkName .= "_$wnr" if($wnr > 1);
          $wnr++;
          next if (exists $defs{$weblinkName});
          $cmd = "$weblinkName SVG $filelogName:$gplotfile:CURRENT";
          Log3 $weblinkName, 2, "ModbusElsnerWS define $cmd";
          $ret = CommandDefine(undef, $cmd);
          if($ret) {
            Log3 $weblinkName, 2, "ModbusElsnerWS ERROR: define $cmd: $ret";
            last;
          }
          $attr{$weblinkName}{room} = $autocreateWeblinkRoom;
          $attr{$weblinkName}{title} = '"' . $name . ' Min $data{min1}, Max $data{max1}, Last $data{currval1}"';
          $ret = CommandSet(undef, "$weblinkName copyGplotFile");
          if($ret) {
            Log3 $weblinkName, 2, "ModbusElsnerWS ERROR: set $weblinkName copyGplotFile: $ret";
            last;
          }
        }
      }
    }
  }
  ModbusLD_Define($hash, $def);
  return;
}

sub ModbusElsnerWS_Eval($$$) {
  my ($hash, $readingName, $readingVal) = @_;
  my $name = $hash->{NAME};
  my $ctrl = 1;
  my ($temperature, $sunSouth, $sunWest, $sunEast, $brightness, $windSpeed, $gps, $isRaining, $date, $time, $sunAzimuth, $sunElevation, $latitude, $longitude) = split(' ', $readingVal);
  my ($windAvg2min, $windGust10min, $windGustCurrent, $windPeak10min);
  if ($hash->{INTERVAL} =~ m/^1$/) {
    $hash->{helper}{wind}{windSpeedNumArrayElements} = ModubusElsnerWS_updateArrayElement($hash, 'windSpeed', $windSpeed, 'wind', 600);
    my ($windAvg10min, $windSpeedMin10min, $windSpeedMax10min) = ModubusElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windAvg10min', 'windSpeedMax10min', 'windSpeedMin10min', 'wind', 600);
    ($windAvg2min, undef, undef) = ModubusElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windAvg2min', undef, undef, 'wind', 120);
    my ($windAvg20s, $windSpeedMin20s, $windSpeedMax20s) = ModubusElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windAvg20s', 'windSpeedMax20s', 'windSpeedMin20s', 'wind', 20);
    ($windGustCurrent, undef, undef) = ModubusElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windGustCurrent', undef, undef, 'wind', 3);
    $windPeak10min = $windSpeedMax10min >= 12.86 ? $windSpeedMax10min : $windAvg2min;
    my $windGust20s = $windGustCurrent >= $windSpeedMin20s + 5.144 ? $windGustCurrent : 0;
    $windGustCurrent = $windGustCurrent >= $windSpeedMin20s + 5.144 ? $windGustCurrent : $windAvg2min;
    $hash->{helper}{wind}{windGustNumArrayElements} = ModubusElsnerWS_updateArrayElement($hash, 'windGust', $windGust20s, 'wind', 600);
    my ($windGustAvg10min, $windGustMin10min, $windGustMax10min) = ModubusElsnerWS_SMA($hash, 'windGust', $windGust20s, 'windGustAvg10min', 'windGustMax10min', 'windGustMin10min', 'wind', 600);
    $windGust10min = $windGustMax10min >= 5.144 ? $windGustMax10min : $windAvg2min;
  }
  my @sunlight = ($sunSouth, $sunWest, $sunEast);
  my ($sunMin, $sunMax) = (sort {$a <=> $b} @sunlight)[0,-1];
  $sunSouth = $sunSouth == 0 ? $brightness : $sunSouth;
  $sunWest = $sunWest == 0 ? $brightness : $sunWest;
  $sunEast = $sunEast == 0 ? $brightness : $sunEast;
  $brightness = ($sunMax > 0) ? $sunMax : $brightness;
  readingsBeginUpdate($hash);
  $temperature = ModbusElsnerWS_readingsBulkUpdate($hash, "temperature", $temperature, 0.025, undef,  "%0.1f");
  $sunSouth = ModbusElsnerWS_readingsBulkUpdate($hash, "sunSouth", $sunSouth, 0.1, 0.7, "%d");
  $sunWest = ModbusElsnerWS_readingsBulkUpdate($hash, "sunWest", $sunWest, 0.1, 0.7, "%d");
  $sunEast = ModbusElsnerWS_readingsBulkUpdate($hash, "sunEast", $sunEast, 0.1, 0.7, "%d");
  $brightness = ModbusElsnerWS_readingsBulkUpdate($hash, "brightness", $brightness, 0.1, 0.7, "%d");
  $windSpeed = ModbusElsnerWS_readingsBulkUpdate($hash, "windSpeed", $windSpeed, 0.1, 0.3, "%0.1f");
  my @windStrength = (0.2, 1.5, 3.3, 5.4, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6);
  my $windStrength = 0;
  while($windSpeed > $windStrength[$windStrength] && $windStrength <= @windStrength + 1) {
    $windStrength ++;
  }
  if ($hash->{INTERVAL} =~ m/^1$/ && (!exists($hash->{helper}{timer}{lastUpdate}) || $hash->{helper}{timer}{lastUpdate} < gettimeofday() - 60)) {
    # update every 60 sec
    readingsBulkUpdateIfChanged($hash, "windAvg2min", sprintf("%0.1f", $windAvg2min));
    readingsBulkUpdateIfChanged($hash, "windGust10min", sprintf("%0.1f", $windGust10min));
    readingsBulkUpdateIfChanged($hash, "windGustCurrent", sprintf("%0.1f", $windGustCurrent));
    readingsBulkUpdateIfChanged($hash, "windPeak10min", sprintf("%0.1f", $windPeak10min));
    $hash->{helper}{timer}{lastUpdate} = gettimeofday();
  }
  if (exists $hash->{helper}{timer}{heartbeat}) {
    readingsBulkUpdateIfChanged($hash, "isRaining", $isRaining);
    readingsBulkUpdateIfChanged($hash, "windStrength", $windStrength);
    readingsBulkUpdateIfChanged($hash, "dayNight", ModbusElsnerWS_swayCtrl($hash, "dayNight", $brightness, "brightnessDayNight", "brightnessDayNightDelay", 10, 20, 600, 600, 'night', 'day'));
    readingsBulkUpdateIfChanged($hash, "isSunny", ModbusElsnerWS_swayCtrl($hash, "isSunny", $brightness, "brightnessSunny", "brightnessSunnyDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdateIfChanged($hash, "isSunnySouth", ModbusElsnerWS_swayCtrl($hash, "isSunnySouth", $sunSouth, "brightnessSunnySouth", "brightnessSunnySouthDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdateIfChanged($hash, "isSunnyWest", ModbusElsnerWS_swayCtrl($hash, "isSunnyWest", $sunWest, "brightnessSunnyWest", "brightnessSunnyWestDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdateIfChanged($hash, "isSunnyEast", ModbusElsnerWS_swayCtrl($hash, "isSunnyEast", $sunEast, "brightnessSunnyEast", "brightnessSunnyEastDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdateIfChanged($hash, "isStormy", ModbusElsnerWS_swayCtrl($hash, "isStormy", $windSpeed, "windSpeedStormy", "windSpeedStormyDelay", 13.9, 17.2, 60, 3, 'no', 'yes'));
    readingsBulkUpdateIfChanged($hash, "isWindy", ModbusElsnerWS_swayCtrl($hash, "isWindy", $windSpeed, "windSpeedWindy", "windSpeedWindyDelay", 1.6, 3.4, 60, 3, 'no', 'yes'));
  } else {
    readingsBulkUpdate($hash, "isRaining", $isRaining);
    readingsBulkUpdate($hash, "windStrength", $windStrength);
    readingsBulkUpdate($hash, "dayNight", ModbusElsnerWS_swayCtrl($hash, "dayNight", $brightness, "dayNightSwitch", "dayNightSwitchDelay", 10, 20, 600, 600, 'night', 'day'));
    readingsBulkUpdate($hash, "isSunny", ModbusElsnerWS_swayCtrl($hash, "isSunny", $brightness, "brightnessSunny", "brightnessSunnyDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdate($hash, "isSunnySouth", ModbusElsnerWS_swayCtrl($hash, "isSunnySouth", $sunSouth, "brightnessSunnySouth", "brightnessSunnySouthDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdate($hash, "isSunnyWest", ModbusElsnerWS_swayCtrl($hash, "isSunnyWest", $sunWest, "brightnessSunnyWest", "brightnessSunnyWestDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdate($hash, "isSunnyEast", ModbusElsnerWS_swayCtrl($hash, "isSunnyEast", $sunEast, "brightnessSunnyEast", "brightnessSunnyEastDelay", 20000, 40000, 120, 30, 'no', 'yes'));
    readingsBulkUpdate($hash, "isStormy", ModbusElsnerWS_swayCtrl($hash, "isStormy", $windSpeed, "windSpeedStormy", "windSpeedStormyDelay", 13.9, 17.2, 60, 3, 'no', 'yes'));
    readingsBulkUpdate($hash, "isWindy", ModbusElsnerWS_swayCtrl($hash, "isWindy", $windSpeed, "windSpeedWindy", "windSpeedWindyDelay", 1.6, 3.4, 60, 3, 'no', 'yes'));
  }
  readingsBulkUpdateIfChanged($hash, "state", "T: " . $temperature .
                                             " B: " . $brightness .
                                             " W: " . $windSpeed .
                                            " IR: " . $isRaining);
  if ($gps == 1) {
    readingsBulkUpdateIfChanged($hash, "date", $date);
    readingsBulkUpdateIfChanged($hash, "timeZone", 'UTC');
    $hash->{GPS_TIME} = $time;
    readingsBulkUpdateIfChanged($hash, "sunAzimuth", $sunAzimuth);
    my $twilight = ($sunElevation + 12) / 18 * 100;
    $twilight = 0 if ($twilight < 0);
    $twilight = 100 if ($twilight > 100);
    readingsBulkUpdateIfChanged($hash, "sunElevation", $sunElevation);
    readingsBulkUpdateIfChanged($hash, "twilight", int($twilight));
    readingsBulkUpdateIfChanged($hash, "longitude", $longitude);
    if (AttrVal($name, "updateGlobalAttr", 'no') eq 'yes') {
      $attr{global}{longitude} = $longitude;
    }
    readingsBulkUpdateIfChanged($hash, "latitude", $latitude);
    if (AttrVal($name, "updateGlobalAttr", 'no') eq 'yes') {
      $attr{global}{latitude} = $latitude;
    }
    readingsBulkUpdateIfChanged($hash, "hemisphere", $latitude < 0 ? "south" : "north");
  } else {
    delete $hash->{GPS_TIME};
    readingsDelete($hash, 'date');
    readingsDelete($hash, 'hemisphere');
    readingsDelete($hash, 'latitude');
    readingsDelete($hash, 'longitude');
    readingsDelete($hash, 'sunAzimuth');
    readingsDelete($hash, 'sunElevation');
    readingsDelete($hash, 'time');
    readingsDelete($hash, 'timeZone');
    readingsDelete($hash, 'twilight');
  }
  readingsEndUpdate($hash, 1);
  readingsSingleUpdate($hash, 'time', $hash->{GPS_TIME}, AttrVal($name, 'timeEvent', 'no') eq 'yes' ? 1 : 0) if (exists $hash->{GPS_TIME});
  readingsDelete($hash, 'alarm');
  RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
  @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5, 0);
  InternalTimer(gettimeofday() + $hash->{INTERVAL} * 1.5, 'ModbusElsnerWS_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
  if (!exists $hash->{helper}{timer}{heartbeat}) {
    @{$hash->{helper}{timer}{heartbeat}} = ($hash, 'heartbeat');
    RemoveInternalTimer($hash->{helper}{timer}{heartbeat});
    InternalTimer(gettimeofday() + 600, 'ModbusElsnerWS_cdmClearTimer', $hash->{helper}{timer}{heartbeat}, 0);
    #Log3 $hash->{NAME}, 3, "ModbusElsnerWS $hash->{NAME} ModbusElsnerWS_readingsBulkUpdate heartbeat executed.";
  }
  #Log3 $hash->{NAME}, 2, "ModbusElsnerWS_Eval $hash->{NAME} $readingName = $readingVal received";
  return $ctrl;
}

sub ModbusElsnerWS_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  # return if attribute list is incomplete
  return undef if (!$init_done);
  my $err;

  if ($attrName =~ m/^brightness(DayNight|Sunny).*$/) {
    if (!defined $attrVal) {

    } else {
      my ($attrVal0, $attrVal1) = split(':', $attrVal);
      if (!defined($attrVal0) && !defined($attrVal1)) {

      } else {
        if (!defined $attrVal0 || $attrVal0 eq '') {

        } elsif ($attrVal0 !~ m/^[+]?\d+$/ || $attrVal0 + 0 > 99000) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
        }
        if (!defined $attrVal1 || $attrVal1 eq '') {

        } elsif ($attrVal1 !~ m/^[+]?\d+$/ || $attrVal1 + 0 > 99000) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
        }
      }
    }
  } elsif ($attrName eq "timeEvent") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^yes|no$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName eq "updateGlobalAttr") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^yes|no$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName =~ m/^windSpeed.*$/) {
    my ($attrVal0, $attrVal1) = split(':', $attrVal);
    if (!defined $attrVal1) {
      if (!defined $attrVal0) {

      } elsif ($attrVal0 !~ m/^[+]?\d+(\.\d)?$/ || $attrVal0 + 0 > 35) {
        $err = "attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");
      }
    } elsif ($attrVal1 !~ m/^[+]?\d+(\.\d)?$/ || $attrVal1 + 0 > 35) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    } else {
      if (!defined $attrVal0) {

      } elsif ($attrVal0 !~ m/^[+]?\d+(\.\d)?$/ || $attrVal0 + 0 > 35) {
        $err = "attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");
      }
    }
  }

  ModbusLD_Attr($cmd, $name, $attrName, $attrVal);
  return $err;
}

sub ModbusElsnerWS_Get($$$) {
  my ($hash, $a, $h) = @_;
  my ($result, $name, $opt) = (undef, $a->[1], $a->[2]);
  $result = ModbusLD_Get($hash, @$a);
  return $result;
}

sub ModbusElsnerWS_Set($$$) {
  my ($hash, $a, $h) = @_;
  my ($error, $name, $cmd) = (undef, $a->[1], $a->[2]);
  $error = ModbusLD_Set($hash, @$a);
  return $error;
}

sub ModbusElsnerWS_Notify(@) {
  my ($hash, $dev) = @_;
  return "" if (IsDisabled($hash->{NAME}));
  return undef if (!$init_done);
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}})) {
  }
  Modbus_Notify($hash, $dev);
  return undef;
}

sub ModubusElsnerWS_updateArrayElement($$$$$) {
  # read und update values to array
  my ($hash, $readingName, $readingVal, $arrayName, $numArrayElementsMax) = @_;
  my $numArrayElements = $#{$hash->{helper}{$arrayName}{$readingName}{val}};
  if (!defined $numArrayElements) {
    $numArrayElements = 1;
  } elsif ($numArrayElements + 1 >= $numArrayElementsMax) {
    $numArrayElements = $numArrayElementsMax;
    pop(@{$hash->{helper}{$arrayName}{$readingName}{val}});
  } else {
    $numArrayElements ++;
  }
  unshift(@{$hash->{helper}{$arrayName}{$readingName}{val}}, $readingVal);
  return $numArrayElements;
}

sub ModubusElsnerWS_SMA($$$$$$$$) {
  # simple moving average (SMA)
  my ($hash, $readingName, $readingVal, $averageName, $valMaxName, $valMinName, $arrayName, $numArrayElementsCalc) = @_;
  my $average = exists($hash->{helper}{$arrayName}{$readingName}{average}) ? $hash->{helper}{$arrayName}{$readingName}{average} : $readingVal;
  my ($valMin, $valMax) = ($readingVal, $readingVal);
  my $numArrayElements = $#{$hash->{helper}{$arrayName}{$readingName}{val}};
  if (!defined $numArrayElements) {
    $average = $readingVal;
  } else {
    $numArrayElements = $numArrayElementsCalc - 1 if ($numArrayElements + 1 >= $numArrayElementsCalc);
    $average = $average + $readingVal / ($numArrayElements + 1)
                        - $hash->{helper}{$arrayName}{$readingName}{val}[$numArrayElements] / ($numArrayElements + 1);
  }
  if (defined($valMaxName) && defined($valMinName)) {
    ($valMin, $valMax) = (sort {$a <=> $b} @{$hash->{helper}{$arrayName}{$readingName}{val}})[0, $numArrayElements];
    $hash->{helper}{$arrayName}{$readingName}{$valMaxName} = $valMax;
    $hash->{helper}{$arrayName}{$readingName}{$valMinName} = $valMin;
  }
  $hash->{helper}{$arrayName}{$readingName}{$averageName} = $average;
  return ($average, $valMin, $valMax);
}

sub ModbusElsnerWS_LWMA($$$$) {
  # linear weighted moving average (LWMA)
  my ($hash, $readingName, $readingVal, $averageOrder) = @_;
  push(@{$hash->{helper}{lwma}{$readingName}{val}}, $readingVal);
  my $average = 0;
  my $numArrayElements = $#{$hash->{helper}{lwma}{$readingName}{val}} + 1;
  for (my $i = 1; $i <= $numArrayElements; $i++) {
    $average += $i * $hash->{helper}{lwma}{$readingName}{val}[$numArrayElements - $i];
  }
  $average = $average * 2 / $numArrayElements / ($numArrayElements + 1);
  if ($numArrayElements >= $averageOrder) {
    shift(@{$hash->{helper}{lwma}{$readingName}{val}});
  }
  return $average;
}

sub ModbusElsnerWS_EMA($$$$) {
  # exponential moving average (EMA)
  # 0 < $wheight < 1
  my ($hash, $readingName, $readingVal, $wheight) = @_;
  my $average = exists($hash->{helper}{ema}{$readingName}{average}) ? $hash->{helper}{ema}{$readingName}{average} : $readingVal;
  $average = $wheight * $readingVal + (1 - $wheight) * $average;
  $hash->{helper}{ema}{$readingName}{average} = $average;
  return $average;
}

sub ModbusElsnerWS_Smooting($$$$$) {
  my ($hash, $readingName, $readingVal, $theshold, $averageParam) = @_;
  my $iniVal;
  $readingVal = ModbusElsnerWS_EMA($hash, $readingName, $readingVal, $averageParam) if (defined $averageParam);
  if (exists $hash->{helper}{smooth}{$readingName}{iniVal}) {
    $iniVal = $hash->{helper}{smooth}{$readingName}{iniVal};
    if ($readingVal > $iniVal && $readingVal - $iniVal > $readingVal * $theshold ||
        $readingVal < $iniVal && $iniVal - $readingVal > $iniVal * $theshold){
      $iniVal = $readingVal;
      $hash->{helper}{smooth}{$readingName}{iniVal} = $iniVal;
    }
  } else {
    $iniVal = $readingVal;
    $hash->{helper}{smooth}{$readingName}{iniVal} = $iniVal;
  }
  return $iniVal;
}

sub ModbusElsnerWS_swayCtrl($$$$$$$$$$$) {
  # sway range and delay calculation
  my ($hash, $readingName, $readingVal, $attrNameRange, $attrNameDelay, $swayRangeLow, $swayRangeHigh, $swayDelayLow, $swayDelayHigh, $swayRangeLowVal, $swayRangeHighVal) = @_;
  my ($swayRangeLowAttr, $swayRangeHighAttr) = split(':', AttrVal($hash->{NAME}, $attrNameRange, "$swayRangeLow:$swayRangeHigh"));
  my ($swayDelayLowAttr, $swayDelayHighAttr) = split(':', AttrVal($hash->{NAME}, $attrNameDelay, "$swayDelayLow:$swayDelayHigh"));
  my $swayValLast = exists($hash->{helper}{sway}{$readingName}) ? $hash->{helper}{sway}{$readingName} : $swayRangeLowVal;
  my $swayVal = $swayValLast;
  if (!defined($swayRangeLowAttr) && !defined($swayRangeHighAttr)) {
    $swayRangeLowAttr = $swayRangeLow;
    $swayRangeHighAttr = $swayRangeHigh;
  } elsif (!defined($swayRangeLowAttr) && $swayRangeHighAttr eq '' || !defined($swayRangeHighAttr) && $swayRangeLowAttr eq '') {
    $swayRangeLowAttr = $swayRangeLow;
    $swayRangeHighAttr = $swayRangeHigh;
  } elsif ($swayRangeHighAttr eq '' && $swayRangeLowAttr eq '') {
    $swayRangeLowAttr = $swayRangeLow;
    $swayRangeHighAttr = $swayRangeHigh;
  } elsif ($swayRangeLowAttr eq '') {
    $swayRangeLowAttr = $swayRangeHighAttr;
  } elsif ($swayRangeHighAttr eq '') {
    $swayRangeHighAttr = $swayRangeLowAttr;
  }
  ($swayRangeLowAttr, $swayRangeHighAttr) = ($swayRangeHighAttr, $swayRangeLowAttr) if ($swayRangeLowAttr > $swayRangeHighAttr);
  if ($readingVal < $swayRangeLowAttr) {
    $swayVal = $swayRangeLowVal;
  } elsif ($readingVal >= $swayRangeHighAttr) {
    $swayVal = $swayRangeHighVal;
  } elsif ($readingVal >= $swayRangeLowAttr && $swayVal eq $swayRangeLowVal) {
    $swayVal = $swayRangeLowVal;
  } elsif ($readingVal < $swayRangeHighAttr && $swayVal eq $swayRangeHighVal) {
    $swayVal = $swayRangeHighVal;
  }
  if (!defined($swayDelayLowAttr) && !defined($swayDelayHighAttr)) {
    $swayDelayLowAttr = $swayDelayLow;
    $swayDelayHighAttr = $swayDelayHigh;
  } elsif (!defined($swayDelayLowAttr) && $swayDelayHighAttr eq '' || !defined($swayDelayHighAttr) && $swayDelayLowAttr eq '') {
    $swayDelayLowAttr = $swayDelayLow;
    $swayDelayHighAttr = $swayDelayHigh;
  } elsif ($swayDelayHighAttr eq '' && $swayDelayLowAttr eq '') {
    $swayDelayLowAttr = $swayDelayLow;
    $swayDelayHighAttr = $swayDelayHigh;
  } elsif ($swayDelayLowAttr eq '') {
    $swayDelayLowAttr = $swayDelayHighAttr;
  } elsif ($swayDelayHighAttr eq '') {
    $swayDelayHighAttr = $swayDelayLowAttr;
  }
  if ($swayVal eq $swayValLast) {
    $hash->{helper}{sway}{$readingName} = $swayVal;
    if (exists $hash->{helper}{timer}{sway}{$readingName}{delay}) {
      # clear timer as sway reverses
      RemoveInternalTimer($hash->{helper}{timer}{sway}{$readingName}{delay});
      delete $hash->{helper}{timer}{sway}{$readingName}{delay};
    }
  } else {
    $hash->{helper}{sway}{$readingName} = $swayValLast;
    my $swayDelay = $swayVal eq $swayRangeHighVal ? $swayDelayHighAttr : $swayDelayLowAttr;
    if (exists $hash->{helper}{timer}{sway}{$readingName}{delay}) {
      $swayVal = $swayValLast;
    } elsif ($swayDelay > 0) {
      @{$hash->{helper}{timer}{sway}{$readingName}{delay}} = ($hash, $readingName, $swayVal, $swayDelay, 1, 5, 1);
      InternalTimer(gettimeofday() + $swayDelay, 'ModbusElsnerWS_swayCtrlDelay', $hash->{helper}{timer}{sway}{$readingName}{delay}, 0);
      $swayVal = $swayValLast;
    }
  }
  return $swayVal;
}

sub ModbusElsnerWS_swayCtrlDelay($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $delay, $ctrl, $log, $clear) = @$readingParam;
  if (defined $hash) {
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl);
    Log3 $hash->{NAME}, $log, " ModbusElsnerWS " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
    $hash->{helper}{sway}{$readingName} = $readingVal;
    delete $hash->{helper}{timer}{sway}{$readingName}{delay} if ($clear == 1);
  }
  return;
}

sub ModbusElsnerWS_readingsSingleUpdate($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $ctrl, $log, $clear) = @$readingParam;
  if (defined $hash) {
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl);
    delete $hash->{helper}{timer}{$readingName} if ($clear == 1);
    #Log3 $hash->{NAME}, $log, " ModbusElsnerWS " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
  }
  return;
}

sub ModbusElsnerWS_readingsBulkUpdate($$$$$$) {
  my ($hash, $readingName, $readingVal, $theshold, $averageParam, $sFormat) = @_;
  if (exists $hash->{helper}{timer}{heartbeat}) {
    $readingVal = sprintf("$sFormat", ModbusElsnerWS_Smooting($hash, $readingName, $readingVal, $theshold, $averageParam));
    readingsBulkUpdateIfChanged($hash, $readingName, $readingVal);
  } else {
    $readingVal = sprintf("$sFormat", ModbusElsnerWS_Smooting($hash, $readingName, $readingVal, 0, $averageParam));
    readingsBulkUpdate($hash, $readingName, $readingVal);
  }
  return $readingVal;
}

#
sub ModbusElsnerWS_cdmClearTimer($) {
  my ($functionArray) = @_;
  my ($hash, $timer) = @$functionArray;
  delete $hash->{helper}{timer}{$timer};
  #Log3 $hash->{NAME}, 3, "ModbusElsnerWS $hash->{NAME} ModbusElsnerWS_cdmClearTimer $timer executed.";
  return;
}

sub ModbusElsnerWS_Undef($$) {
  my ($hash, $arg) = @_;
  ModbusLD_Undef($hash, $arg);
  return;
}

# Delete
sub ModbusElsnerWS_Delete($$) {
  my ($hash, $name) = @_;
  my $logName = "FileLog_$name";
  my ($count, $gplotFile, $logFile, $weblinkName, $weblinkHash);
  Log3 $name, 2, "ModbusElsnerWS $name deleted";
  # delete FileLog device and log files
  if (exists $defs{$logName}) {
    $logFile = $defs{$logName}{logfile};
    $logFile =~ /^(.*)($name).*\.(.*)$/;
    $logFile = $1 . $2 . "*." . $3;
    CommandDelete(undef, "FileLog_$name");
    Log3 $name, 2, "ModbusElsnerWS FileLog_$name deleted";
    $count = unlink glob $logFile;
    Log3 $name, 2, "ModbusElsnerWS $logFile >> $count files deleted";
  }
  # delete SVG devices and gplot files
  while (($weblinkName, $weblinkHash) = each(%defs)) {
    if ($weblinkName =~ /^SVG_$name.*/) {
      $gplotFile = "./www/gplot/" . $defs{$weblinkName}{GPLOTFILE} . "*.gplot";
      CommandDelete(undef, $weblinkName);
      Log3 $name, 2, "ModbusElsnerWS $weblinkName deleted";
      $count = unlink glob $gplotFile;
      Log3 $name, 2, "ModbusElsnerWS $gplotFile >> $count files deleted";
    }
  }
  return undef;
}

1;

=pod
=item summary    ModbusElsnerWS Elsner Weather Station P03/3-Modbus RS485 evaluation modul
=item summary_DE ModbusElsnerWS Elsner Wetterstation P03/3-Modbus RS485 Auswertemodul
=begin html

<a name="ModbusElsnerWS"></a>
<h3>ModbusElsnerWS</h3>
<ul>
    The ModbusElsnerWS weather evaluation modul serves as a connecting link between the
    <a href="https://www.elsner-elektronik.de/shop/de/produkte-shop/gebaeudetechnik-konventionell/modbus-sensoren/p03-3-modbus-747.html">Elsner P03/3-Modbus Weather Stations</a>
    and blind actuators. ModbusElsnerWS uses the low level Modbus module to provide a way to communicate with the
    <a href="https://www.elsner-elektronik.de/shop/de/produkte-shop/gebaeudetechnik-konventionell/modbus-sensoren/p03-3-modbus-747.html">Elsner P03/3-Modbus Weather Stations</a>.
    It read the modbus holding registers for the different values and process
    them in a periodic interval. It evaluates the received weather data and based on adjustable thresholds and delay
    times it generates up/down signals for blinds according to wind, rain and sun. This way blinds can be pilot-controlled
    and protected against thunderstorms. The GPS function of the sensor provides the current values of the date, time,
    sun azimuth, sun elevation, longitude and latitude.<br>
    As an alternative to the module for the Elsner Modbus sensors, sensors with the manufacturer-specific serial
    RS485 protocol can also be used. The <a href="#ElsnerWS">ElsnerWS</a> module is available for this purpose. EnOcean profiles
    "Environmental Applications" with the EEP A5-13-01 ... EEP A5-13-06 are also available for these weather stations,
    but they also require weather evaluation units from Eltako or AWAG, for example. The functional scope of
    the modules is widely similar.
    <br><br>

    <b>Functions</b>
    <ul>
      <li>Evaluation modul for the weather sensors P03/3-Modbus and P03/3-Modbus GPS</li>
      <li>Processing weather raw data and creates graphic representation</li>
      <li>For wind observations, average speeds, gusts and peak values are calculated.</li>
      <li>Alarm signal in case of failure of the weather sensor</li>
      <li>Up/down readings for blinds according to wind, rain and sun</li>
      <li>Adjustable switching thresholds and delay times</li>
      <li>Day/night signal</li>
      <li>Display of date, time, sun azimuth, sun elevation, longitude and latitude</li>
    </ul><br>

    <b>Prerequisites</b>
      <ul>
        This module requires the basic <a href="#Modbus">Modbus</a> module which itsef requires Device::SerialPort
	or Win32::SerialPort module.
      </ul><br>

    <b>Hardware Connection</b>
      <ul>
        The weather sensor P03/3-Modbus(GPS) is connected via a shielded cable 2x2x0.5 mm2 to a RS485 transceiver.
        The sensor is connected via the pins A to the RS485 B(+)-Port, B to RS485 A(-)-Port, 1 to + 12...28 V, 2 to GND and Shield.
        Please note that the RS485 connection names are reversed. Only the usual pins for serial Modbus communication A, B and Ground are needed.<br>
        The serial bus should be terminated at its most remote ends with 120 Ohm resistors. If several Modbus units are connected to
        the serial bus, only the termination resistor in the devices furthest ends must be switched on.<br>
        More information about the sensor, see
        <a href="https://www.elsner-elektronik.de/shop/de/fileuploader/download/download/?d=1&file=custom%2Fupload%2F30146-30147_P033-Modbus_P033-Modbus-GPS_Datenblatt2-0_19Mar18_DBEEA6010.pdf">P03/3-Modbus(GPS) User Guide</a>.<br>
        The USB adapters
        <a href="https://www.digitus.info/produkte/computer-zubehoer-und-komponenten/computer-zubehoer/seriell-und-parallel-adapter/da-70157/">Digitus DA-70157</a>,
        <a href="https://shop.in-circuit.de/product_info.php?cPath=33&products_id=81">In-Circuit USB-RS485-Bridge</a>
        and <a href="http://www.dsdtech-global.com/2018/01/sh-u10-spp.html">DSD TECH SH-U10 USB to RS485 converter</a>
        are successfully tested at a Raspberry PI in conjunction with the weather sensor.
      </ul><br>

    <a name="ModbusElsnerWSDefine"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; ModbusElsnerWS id=&lt;ID&gt; interval=&lt;Interval&gt;|passive</code><br><br>
      The module connects to the Elsner Weather Station with the Modbus Id &lt;ID&gt; through an already defined Modbus device
      and actively requests data from the system every &lt;Interval&gt; seconds. The query interval should be set to 1 second.
      The readings windAvg2min, windGust10min, windGustCurrent and windPeak10min required for wind observation are calculated
      only at a query interval of 1 second.<br>
      The following parameters apply to the default factory settings and an RS485 transceiver to USB.
      <br><br>
      Example:<br>
      <code>define modbus Modbus /dev/ttyUSB1@19200,8,E,1</code><br>
      <code>define WS ModbusElsnerWS id=1 interval=1</code>
    </ul><br>

    <a name="ModbusElsnerWSget"></a>
    <b>Get</b>
    <ul>
      <code>get &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      <ul>
       where <code>value</code> is
          <li>raw<br>
            get sensor dates manualy</li>
      </ul>
    </ul><br>

    <a name="ModbusElsnerWSattr"></a>
    <b>Attributes</b>
    <ul>
      <ul>
        <li><a name="ModbusElsnerWS_brightnessDayNight">brightnessDayNight</a> E_min/lx:E_max/lx,
          [brightnessDayNight] = 0...99000:0...99000, 10:20 is default.<br>
          Set switching thresholds for reading dayNight based on the reading brightness.
        </li>
        <li><a name="ModbusElsnerWS_brightnessDayNightDelay">brightnessDayNightDelay</a> t_reset/s:t_set/s,
          [brightnessDayNightDelay] = 0...99000:0...99000, 600:600 is default.<br>
          Set switching delay for reading dayNight based on the reading brightness. The reading dayNight is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunny">brightnessSunny</a> E_min/lx:E_max/lx,
          [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunny based on the reading brightness.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnyDelay">brightnessSunnyDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
          Set switching delay for reading isSunny based on the reading brightness. The reading isSunny is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnyEast">brightnessSunnyEast</a> E_min/lx:E_max/lx,
          [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunnyEast based on the reading sunEast.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnyEastDelay">brightnessSunnyEastDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
          Set switching delay for reading isSunnyEast based on the reading sunEast. The reading isSunnyEast is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnySouth">brightnessSunnySouth</a> E_min/lx:E_max/lx,
          [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunnySouth based on the reading sunSouth.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnySouthDelay">brightnessSunnySouthDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
          Set switching delay for reading isSunnySouth based on the reading sunSouth. The reading isSunnySouth is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnyWest">brightnessSunnyWest</a> E_min/lx:E_max/lx,
          [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunnyWest based on the reading sunWest.
        </li>
        <li><a name="ModbusElsnerWS_brightnessSunnyWestDelay">brightnessSunnyWestDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
          Set switching delay for reading isSunnyWest based on the reading sunWest. The reading isSunnyWest is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <li><a name="ModbusElsnerWS_timeEvent">timeEvent</a> no|yes,
          [timeEvent] = no|yes, no is default.<br>
          Update the reading time periodically.
        </li>
        <li><a name="ModbusElsnerWS_windSpeedStormy">windSpeedStormy</a> v_min/m/s:v_max/m/s,
          [windSpeedStormy] = 0...35:0...35, 13.9:17.2 is default.<br>
          Set switching thresholds for reading isStormy based on the reading windSpeed.
        </li>
        <li><a name="ModbusElsnerWS_windSpeedStormyDelay">windSpeedStormyDelay</a> t_reset/s:t_set/s,
          [windSpeedStormyDelay] = 0...99000:0...99000, 60:3 is default.<br>
          Set switching delay for reading isStormy based on the reading windSpeed. The reading isStormy is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a name="ModbusElsnerWS_windSpeedWindy">windSpeedWindy</a> v_min/m/s:v_max/m/s,
          [windSpeedWindy] = 0...35:0...35, 1.6:3.4 is default.<br>
          Set switching thresholds for reading isWindy based on the reading windSpeed.
        </li>
        <li><a name="ModbusElsnerWS_windSpeedWindyDelay">windSpeedWindyDelay</a> t_reset/s:t_set/s,
          [windSpeedWindyDelay] = 0...99000:0...99000, 60:3 is default.<br>
          Set switching delay for reading isWindy based on the reading windSpeed. The reading isWindy is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a name="ModbusElsnerWS_updateGlobalAttr">updateGlobalAttr</a> no|yes,
          [timeEvent] = no|yes, no is default.<br>
          Update the global attributes latitude and longitude with the received GPS coordinates.
        </li>
      </ul>
    </ul><br>

  <a name="ModbusElsnerWSevents"></a>
  <b>Generated events</b>
  <ul>
    <ul>
      <li>T: t/&#176C B: E/lx W: v/m/s IR: no|yes</li>
      <li>brightness: E/lx (Sensor Range: E = 0 lx ... 99000 lx)</li>
      <li>date: JJJJ-MM-TT</li>
      <li>dayNight: day|night</li>
      <li>hemisphere: north|south</li>
      <li>isRaining: no|yes</li>
      <li>isStormy: no|yes</li>
      <li>isSunny: no|yes</li>
      <li>isSunnyEast: no|yes</li>
      <li>isSunnySouth: no|yes</li>
      <li>isSunnyWest: no|yes</li>
      <li>isWindy: no|yes</li>
      <li>latitude: &phi;/&deg; (Sensor Range: &phi; = -90 &deg; ... 90 &deg;)</li>
      <li>longitude: &lambda;/&deg; (Sensor Range: &lambda; = -180 &deg; ... 180 &deg;)</li>
      <li>sunAzimuth: &alpha;/&deg; (Sensor Range: &alpha; = 0 &deg; ... 359 &deg;)</li>
      <li>sunEast: E/lx (Sensor Range: E = 0 lx ... 99000 lx)</li>
      <li>sunElevation: &beta;/&deg; (Sensor Range: &beta; = -90 &deg; ... 90 &deg;)</li>
      <li>sunSouth: E/lx (Sensor Range: E = 0 lx ... 99000 lx)</li>
      <li>sunWest: E/lx (Sensor Range: E = 0 lx ... 99000 lx)</li>
      <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 70 &#176C)</li>
      <li>time: hh:mm:ss</li>
      <li>timeZone: CET|CEST|UTC</li>
      <li>twilight: T/% (Sensor Range: T = 0 % ... 100 %)</li>
      <li>windAvg2min: v/m/s (Sensor Range: v = 0 m/s ... 70 m/s)</li>
      <li>windGust10min: v/m/s (Sensor Range: v = 0 m/s ... 70 m/s)</li>
      <li>windGustCurrent: v/m/s (Sensor Range: v = 0 m/s ... 70 m/s)</li>
      <li>windPeak10min: v/m/s (Sensor Range: v = 0 m/s ... 70 m/s)</li>
      <li>windSpeed: v/m/s (Sensor Range: v = 0 m/s ... 70 m/s)</li>
      <li>windStrength: B (Sensor Range: B = 0 Beaufort ... 12 Beaufort)</li>
      <li>state: T: t/&#176C B: E/lx W: v/m/s IR: no|yes</li>
    </ul>
  </ul>
</ul>

=end html
=cut
