# $Id$
# This modules handles the communication with a Elsner Weather Station P03/3-R485 or P03/4-RS485.
# define: define WS ElsnerWS comtype=rs485 devicename=/dev/ttyUSB1@19200

package main;

use strict;
use warnings;
use DevIo;
use Time::HiRes qw(gettimeofday usleep);

sub ElsnerWS_Checksum($$);
sub ElsnerWS_Define($$$);
sub ElsnerWS_Delete($$);
sub ElsnerWS_Initialize($);
sub ElsnerWS_Read($);
sub ElsnerWS_Ready($);
sub ElsnerWS_Shutdown($);

# trigger values for down and up commands
my %customCmdTrigger = ('dayNight' => ['night', 'day'],
                        'isRaining' => ['no', 'yes'],
                        'isStormy' => ['no', 'yes'],
                        'isSunny' => ['yes', 'no'],
                        'isSunnyEast' => ['yes', 'no'],
                        'isSunnySouth' => ['yes', 'no'],
                        'isSunnyWest' => ['yes', 'no'],
                        'isWindy' => ['no', 'yes']);
my %customCmdPeriod =(once => -1,
                      threeTimes => -3,
                      3 => 3,
                      10 => 10,
                      180 => 180,
                      600 => 600);
my %specials;

# Init
sub ElsnerWS_Initialize($) {
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "ElsnerWS_Read";
  $hash->{ReadyFn} = "ElsnerWS_Ready";

# Normal devices
  $hash->{DefFn}    = "ElsnerWS_Define";
  $hash->{UndefFn}  = "ElsnerWS_Undef";
  $hash->{DeleteFn} = "ElsnerWS_Delete";
  $hash->{NotifyFn} = "ElsnerWS_Notify";
  $hash->{AttrFn}   = "ElsnerWS_Attr";
  $hash->{AttrList} = "brightnessDayNight brightnessDayNightCtrl:select,custom,sensor brightnessDayNightDelay " .
                      "brightnessSunny brightnessSunnySouth brightnessSunnyWest brightnessSunnyEast " .
                      "brightnessSunnyDelay brightnessSunnySouthDelay brightnessSunnyWestDelay brightnessSunnyEastDelay " .
                      "customCmdAlarmOff:textField-long customCmdAlarmOn:textField-long " .
                      "customCmdDown:textField-long customCmdDownPeriod:select," . join(",", sort keys %customCmdPeriod) . " " .
                      "customCmdDownTrigger:multiple-strict," . join(",", sort keys %customCmdTrigger) . " " .
                      "customCmdPriority:select,down,up " .
                      "customCmdUp:textField-long customCmdUpPeriod:select," . join(",", sort keys %customCmdPeriod) . " " .
                      "customCmdUpTrigger:multiple-strict," . join(",", sort keys %customCmdTrigger) . " " .
                      "signOfLife:select,off,on signOfLifeInterval:slider,1,1,15 timeEvent:select,no,yes updateGlobalAttr:select,no,yes " .
                      "windSpeedWindy windSpeedStormy windSpeedWindyDelay windSpeedStormyDelay " .
                      $readingFnAttributes;
  $hash->{ShutdownFn} = "ElsnerWS_Shutdown";
  $hash->{parseParams} = 1;
  #$hash->{NotifyOrderPrefix} = "45-";
  return;
}

# Define
sub ElsnerWS_Define($$$) {
  my ($hash, $a, $h) = @_;
  my $name = $a->[0];
  #return "ElsnerWS: wrong syntax, correct is: define <name> ElsnerWS {devicename[\@baudrate]|ip:port}" if($#$a != 2);
  if (defined $a->[2]) {
    $hash->{ComType} = $a->[2];
  } elsif (exists $h->{comtype}) {
    $hash->{ComType} = $h->{comtype};
  } else {
    return "ElsnerWS: wrong syntax, correct is: define <name> ElsnerWS [comtype=](rs485) [devicename=]{devicename[\@baudrate]|ip:port}";
  }
  if ($hash->{ComType} ne 'rs485') {
    return "ElsnerWS: wrong syntax, correct is: define <name> ElsnerWS [comtype=](rs485) [devicename=]{devicename[\@baudrate]|ip:port}";
  }
  if (defined $a->[3]) {
    $hash->{DeviceName} = $a->[3];
  } elsif (exists $h->{devicename}) {
    $hash->{DeviceName} = $h->{devicename};
  } else {
    return "ElsnerWS: wrong syntax, correct is: define <name> ElsnerWS [comtype=](rs485|modbus) [devicename=]{devicename[\@baudrate]|ip:port}";
  }
  $hash->{NOTIFYDEV} = "global";
  my ($autocreateFilelog, $autocreateHash, $autocreateName, $autocreateDeviceRoom, $autocreateWeblinkRoom) =
       ('./log/' . $name . '-%Y-%m.log', undef, 'autocreate', 'ElsnerWS', 'Plots');
  my ($cmd, $filelogName, $gplot, $ret, $weblinkName, $weblinkHash) =
       (undef, "FileLog_$name", "ElsnerWS:SunIntensity,ElsnerWS_2:Temperature/Brightness,ElsnerWS_3:WindSpeed/Raining,", undef, undef, undef);
  DevIo_CloseDev($hash);
  $ret = DevIo_OpenDev($hash, 0, undef);
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
    Log3 $name, 2, "ElsnerWS define " . join(' ', @$a);
    if (!defined(AttrVal($autocreateName, "disable", undef)) && !exists($defs{$filelogName})) {
      # create FileLog
      $autocreateFilelog = $attr{$autocreateName}{filelog} if (exists $attr{$autocreateName}{filelog});
      $autocreateFilelog =~ s/%NAME/$name/g;
      $cmd = "$filelogName FileLog $autocreateFilelog $name";
      $ret = CommandDefine(undef, $cmd);
      if($ret) {
        Log3 $filelogName, 2, "ElsnerWS ERROR: $ret";
      } else {
       $attr{$filelogName}{room} = $autocreateDeviceRoom;
       $attr{$filelogName}{logtype} = 'text';
       Log3 $filelogName, 2, "ElsnerWS define $cmd";
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
          Log3 $weblinkName, 2, "ElsnerWS define $cmd";
          $ret = CommandDefine(undef, $cmd);
          if($ret) {
            Log3 $weblinkName, 2, "ElsnerWS ERROR: define $cmd: $ret";
            last;
          }
          $attr{$weblinkName}{room} = $autocreateWeblinkRoom;
          $attr{$weblinkName}{title} = '"' . $name . ' Min $data{min1}, Max $data{max1}, Last $data{currval1}"';
          $ret = CommandSet(undef, "$weblinkName copyGplotFile");
          if($ret) {
            Log3 $weblinkName, 2, "ElsnerWS ERROR: set $weblinkName copyGplotFile: $ret";
            last;
          }
        }
      }
    }
  }
  return $ret;
}

# Initialize serial communication
sub ElsnerWS_InitSerialCom($) {
  # return if attribute list is incomplete
  #return undef if (!$init_done);
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if ($hash->{STATE} eq "disconnected") {
    Log3 $name, 2, "ElsnerWS $name not initialized";
    return undef;
  }
  $hash->{PARTIAL} = '';
  readingsSingleUpdate($hash, "state", "initialized", 1);
  Log3 $name, 2, "ElsnerWS $name initialized";
  return undef;
}

sub ElsnerWS_Checksum($$) {
  my ($packetType, $msg) = @_;
  $msg = $packetType . $msg;
  my $ml = length($msg);
  my $sum = 0;
  for(my $i = 0; $i < $ml; $i += 2) {
    $sum += hex(substr($msg, $i, 2));
  }
  return $sum;
}

# Read
# called from the global loop, when the select for hash->{FD} reports data
sub ElsnerWS_Read($) {
  my ($hash) = @_;
  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  $hash->{PARTIAL} = '' if(length($hash->{PARTIAL}) > 203);
  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  #Log3 $name, 5, "ElsnerWS $name received DATA: " . uc(unpack('H*', $buf));
  Log3 $name, 5, "ElsnerWS $name received DATA: $data";

  while($data =~ m/^(57)(2B|2D)(.{36})(.{8})(03)(.*)/ ||
        $data =~ m/^(57)(2B|2D)(.{66})(.{8})(03)(.*)/ ||
        $data =~ m/^(47)(2B|2D)(.{108})(.{8})(03)(.*)/) {
    my ($packetType, $ldata, $checksum, $etx, $rest) = ($1, $2 . $3, pack('H*', $4), hex($5), $6);
    # data telegram incomplete
    last if(!defined $etx);
    Log3 $name, 5, "ElsnerWS $name received $packetType, $ldata, $checksum, $etx";
    last if($etx != 3);
    my $tlen = length($ldata);
    $data = $ldata;
    my $checksumCalc = ElsnerWS_Checksum($packetType, $data);
    if($checksum != $checksumCalc) {
      Log3 $name, 2, "ElsnerWS $name wrong checksum: got $checksum, computed $checksumCalc" ;
      $data = $rest;
      next;
    }
    $data =~ m/^(..)(........)(....)(....)(....)(..)(......)(........)(..)(.*)/;
    my ($temperatureSign, $temperature, $sunSouth, $sunWest, $sunEast, $twilightFlag, $brightness, $windSpeed, $isRaining, $zdata) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
    $sunSouth = pack('H*', $sunSouth) * 1000;
    $sunWest = pack('H*', $sunWest) * 1000;
    $sunEast = pack('H*', $sunEast) * 1000;
    $brightness = pack('H*', $brightness);
    $windSpeed = pack('H*', $windSpeed);
    $hash->{helper}{wind}{windSpeedNumArrayElements} = ElsnerWS_updateArrayElement($hash, 'windSpeed', $windSpeed, 'wind', 600);
    my ($windAvg10min, $windSpeedMin10min, $windSpeedMax10min) = ElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windAvg10min', 'windSpeedMax10min', 'windSpeedMin10min', 'wind', 600);
    my ($windAvg2min, undef, undef) = ElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windAvg2min', undef, undef, 'wind', 120);
    my ($windAvg20s, $windSpeedMin20s, $windSpeedMax20s) = ElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windAvg20s', 'windSpeedMax20s', 'windSpeedMin20s', 'wind', 20);
    my ($windGustCurrent, undef, undef) = ElsnerWS_SMA($hash, 'windSpeed', $windSpeed, 'windGustCurrent', undef, undef, 'wind', 3);
    my $windPeak10min = $windSpeedMax10min >= 12.86 ? $windSpeedMax10min : $windAvg2min;
    my $windGust20s = $windGustCurrent >= $windSpeedMin20s + 5.144 ? $windGustCurrent : 0;
    $windGustCurrent = $windGustCurrent >= $windSpeedMin20s + 5.144 ? $windGustCurrent : $windAvg2min;
    $hash->{helper}{wind}{windGustNumArrayElements} = ElsnerWS_updateArrayElement($hash, 'windGust', $windGust20s, 'wind', 600);
    my ($windGustAvg10min, $windGustMin10min, $windGustMax10min) = ElsnerWS_SMA($hash, 'windGust', $windGust20s, 'windGustAvg10min', 'windGustMax10min', 'windGustMin10min', 'wind', 600);
    my $windGust10min = $windGustMax10min >= 5.144 ? $windGustMax10min : $windAvg2min;
    $windAvg2min = sprintf("%0.1f", $windAvg2min);
    $windGust10min = sprintf("%0.1f", $windGust10min);
    $windGustCurrent = sprintf("%0.1f", $windGustCurrent);
    $windPeak10min =  sprintf("%0.1f", $windPeak10min);
    my @sunlight = ($sunSouth, $sunWest, $sunEast);
    my ($sunMin, $sunMax) = (sort {$a <=> $b} @sunlight)[0,-1];
    $sunSouth = $sunSouth == 0 ? $brightness : $sunSouth;
    $sunWest = $sunWest == 0 ? $brightness : $sunWest;
    $sunEast = $sunEast == 0 ? $brightness : $sunEast;
    $brightness = ($sunMax > 0) ? $sunMax : $brightness;
    if (AttrVal($name, "brightnessDayNightCtrl", 'sensor') eq 'sensor') {
      $twilightFlag = $twilightFlag eq '4A' ? 'night' : 'day';
    } else {
      $twilightFlag = ElsnerWS_swayCtrl($hash, "dayNight", $brightness, "brightnessDayNight", "brightnessDayNightDelay", 10, 20, 600, 600, 'night', 'day');
    }
    readingsBeginUpdate($hash);
    $temperature = ElsnerWS_readingsBulkUpdate($hash, "temperature", ($temperatureSign eq '2B' ? '' : '-') . pack('H*', $temperature), 0.025, undef,  "%0.1f");
    $sunSouth = ElsnerWS_readingsBulkUpdate($hash, "sunSouth", $sunSouth, 0.1, 0.7, "%d");
    $sunWest = ElsnerWS_readingsBulkUpdate($hash, "sunWest", $sunWest, 0.1, 0.7, "%d");
    $sunEast = ElsnerWS_readingsBulkUpdate($hash, "sunEast", $sunEast, 0.1, 0.7, "%d");
    $brightness = ElsnerWS_readingsBulkUpdate($hash, "brightness", $brightness, 0.1, 0.7, "%d");
    $isRaining = $isRaining eq '4A' ? 'yes' : 'no';
    $windSpeed = ElsnerWS_readingsBulkUpdate($hash, "windSpeed", $windSpeed, 0.1, 0.7, "%0.1f");
    my @windStrength = (0.2, 1.5, 3.3, 5.4, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6);
    my $windStrength = 0;
    while($windSpeed > $windStrength[$windStrength] && $windStrength < @windStrength) {
      $windStrength ++;
    }
    my $isSunny = ElsnerWS_swayCtrl($hash, "isSunny", $brightness, "brightnessSunny", "brightnessSunnyDelay", 20000, 40000, 120, 30, 'no', 'yes');
    my $isSunnySouth = ElsnerWS_swayCtrl($hash, "isSunnySouth", $sunSouth, "brightnessSunnySouth", "brightnessSunnySouthDelay", 20000, 40000, 120, 30, 'no', 'yes');
    my $isSunnyWest = ElsnerWS_swayCtrl($hash, "isSunnyWest", $sunWest, "brightnessSunnyWest", "brightnessSunnyWestDelay", 20000, 40000, 120, 30, 'no', 'yes');
    my $isSunnyEast = ElsnerWS_swayCtrl($hash, "isSunnyEast", $sunEast, "brightnessSunnyEast", "brightnessSunnyEastDelay", 20000, 40000, 120, 30, 'no', 'yes');
    my $isStormy = ElsnerWS_swayCtrl($hash, "isStormy", $windSpeed, "windSpeedStormy", "windSpeedStormyDelay", 13.9, 17.2, 60, 3, 'no', 'yes');
    my $isWindy = ElsnerWS_swayCtrl($hash, "isWindy", $windSpeed, "windSpeedWindy", "windSpeedWindyDelay", 1.6, 3.4, 60, 3, 'no', 'yes');

    if (!exists($hash->{helper}{timer}{lastUpdate}) || $hash->{helper}{timer}{lastUpdate} < gettimeofday() - 60) {
      # update every 60 sec
      readingsBulkUpdateIfChanged($hash, "windAvg2min", $windAvg2min);
      readingsBulkUpdateIfChanged($hash, "windGust10min", $windGust10min);
      readingsBulkUpdateIfChanged($hash, "windGustCurrent", $windGustCurrent);
      readingsBulkUpdateIfChanged($hash, "windPeak10min", $windPeak10min);
      $hash->{helper}{timer}{lastUpdate} = gettimeofday();
    }
    if (exists $hash->{helper}{timer}{heartbeat}) {
      readingsBulkUpdateIfChanged($hash, "dayNight", $twilightFlag);
      readingsBulkUpdateIfChanged($hash, "isRaining", $isRaining);
      readingsBulkUpdateIfChanged($hash, "windStrength", $windStrength);
      readingsBulkUpdateIfChanged($hash, "isSunny", $isSunny);
      readingsBulkUpdateIfChanged($hash, "isSunnySouth", $isSunnySouth);
      readingsBulkUpdateIfChanged($hash, "isSunnyWest", $isSunnyWest);
      readingsBulkUpdateIfChanged($hash, "isSunnyEast", $isSunnyEast);
      readingsBulkUpdateIfChanged($hash, "isStormy", $isStormy);
      readingsBulkUpdateIfChanged($hash, "isWindy", $isWindy);
    } else {
      readingsBulkUpdate($hash, "dayNight", $twilightFlag);
      readingsBulkUpdate($hash, "isRaining", $isRaining);
      readingsBulkUpdate($hash, "windStrength", $windStrength);
      readingsBulkUpdate($hash, "isSunny", $isSunny);
      readingsBulkUpdate($hash, "isSunnySouth", $isSunnySouth);
      readingsBulkUpdate($hash, "isSunnyWest", $isSunnyWest);
      readingsBulkUpdate($hash, "isSunnyEast", $isSunnyEast);
      readingsBulkUpdate($hash, "isStormy", $isStormy);
      readingsBulkUpdate($hash, "isWindy", $isWindy);
    }
    readingsBulkUpdateIfChanged($hash, "state", "T: " . $temperature .
                                               " B: " . $brightness .
                                               " W: " . $windSpeed .
                                              " IR: " . $isRaining);

    my $weekday = '';
    my $date = '';
    my $timeZone = '';
    my $time = '';
    my $hemisphere = '';
    my $latitude = '';
    my $longitude = '';
    my $sunAzimuth = '';
    my $sunElevation = '';
    my $twilight = '';
    if (defined $zdata) {
      if ($packetType eq '47') {
        # packet type GPS
        $hash->{MODEL} = 'GPS';
        my %weekday = ('3F' => 'UTC_error',
                       '31' => 'Monday',
                       '32' => 'Tuesday',
                       '33' => 'Wednesday',
                       '34' => 'Thursday',
                       '35' => 'Friday',
                       '36' => 'Saturday',
                       '37' => 'Sunday');
        $zdata =~ m/^(..)(....)(....)(....)(....)(....)(....)(..)(..........)(..)(........)(..)(..........)(..)(........)/;
        my ($weekday, $day, $month, $year, $hour, $minute, $second, $gpsStatus, $sunAzimuth, $sunElevationSign, $sunElevation, $longitudeSign, $longitude, $latitudeSign, $latitude) =
             ($1, $2, $3, $4, $5, $6, $7, $8,$9, $10, $11, $12, $13, $14, $15);
        if ($weekday eq '3F') {
          # UTC error
          readingsDelete($hash, 'weekday');
          readingsDelete($hash, 'date');
          readingsDelete($hash, 'timeZone');
          readingsDelete($hash, 'time');
          delete $hash->{GPS_TIME};
        } else {
          $weekday = $weekday{$weekday};
	  $date = '20' . pack('H*', $year) . '-' . pack('H*', $month) . '-' . pack('H*', $day);
	  $timeZone = 'UTC';
	  $time = pack('H*', $hour) . ':' . pack('H*', $minute) . ':' . pack('H*', $second);
          readingsBulkUpdateIfChanged($hash, "weekday", $weekday);
          readingsBulkUpdateIfChanged($hash, "date", $date);
          readingsBulkUpdateIfChanged($hash, "timeZone", $timeZone);
          $hash->{GPS_TIME} = $time;
        }
        if ($gpsStatus eq '30') {
          # GPS error
          readingsDelete($hash, 'hemisphere');
          readingsDelete($hash, 'latitude');
          readingsDelete($hash, 'longitude');
          readingsDelete($hash, 'sunAzimuth');
          readingsDelete($hash, 'sunElevation');
          readingsDelete($hash, 'twilight');
        } else {
          $hemisphere = $latitudeSign eq '4E' ? "north" : "south";
          $latitude = sprintf("%0.1f", ($latitudeSign eq '4E' ? '' : '-') . pack('H*', $latitude));
          $longitude = sprintf("%0.1f", ($longitudeSign eq '4F' ? '' : '-') . pack('H*', $longitude));
          $sunAzimuth = sprintf("%0.1f", pack('H*', $sunAzimuth));
          $sunElevation = ($sunElevationSign eq '2B' ? '' : '-') . pack('H*', $sunElevation);
          $twilight = ($sunElevation + 12) / 18 * 100;
          $twilight = 0 if ($twilight < 0);
          $twilight = 100 if ($twilight > 100);
          $twilight = int($twilight);
          $sunElevation = sprintf("%0.1f", $sunElevation);
          readingsBulkUpdateIfChanged($hash, "sunAzimuth", $sunAzimuth);
          readingsBulkUpdateIfChanged($hash, "sunElevation", $sunElevation);
          readingsBulkUpdateIfChanged($hash, "twilight", $twilight);
          readingsBulkUpdateIfChanged($hash, "longitude", $longitude);
          if (AttrVal($name, "updateGlobalAttr", 'no') eq 'yes') {
            $attr{global}{longitude} = $longitude;
          }
          readingsBulkUpdateIfChanged($hash, "latitude", $latitude);
          if (AttrVal($name, "updateGlobalAttr", 'no') eq 'yes') {
            $attr{global}{latitude} = $latitude;
          }
          readingsBulkUpdateIfChanged($hash, "hemisphere", $hemisphere);
        }
      } elsif ($packetType eq '57') {
        # packet type CET
        $hash->{MODEL} = 'CET';
        my ($weekday, $day, $month, $year, $hour, $minute, $second);
        my %weekday = ('3F' => 'UTC_error',
                       '31' => 'Monday',
                       '32' => 'Tuesday',
                       '33' => 'Wednesday',
                       '34' => 'Thursday',
                       '35' => 'Friday',
                       '36' => 'Saturday',
                       '37' => 'Sunday');
        $zdata =~ m/^(..)(....)(....)(....)(....)(....)(....)(..)/;
        ($weekday, $day, $month, $year, $hour, $minute, $second, $timeZone) = ($1, $2, $3, $4, $5, $6, $7, $8);
        if ($weekday eq '3F') {
          # UTC error
          readingsDelete($hash, 'weekday');
          readingsDelete($hash, 'date');
          readingsDelete($hash, 'timeZone');
          readingsDelete($hash, 'time');
          delete $hash->{GPS_TIME};
        } else {
          $weekday = $weekday{$weekday};
	  $date = '20' . pack('H*', $year) . '-' . pack('H*', $month) . '-' . pack('H*', $day);
	  $timeZone = $timeZone eq '4E' ? 'CET' : 'CEST';
	  $time = pack('H*', $hour) . ':' . pack('H*', $minute) . ':' . pack('H*', $second);
          readingsBulkUpdateIfChanged($hash, "weekday", $weekday);
          readingsBulkUpdateIfChanged($hash, "date", $date);
          readingsBulkUpdateIfChanged($hash, "timeZone", $timeZone);
          $hash->{GPS_TIME} = $time;
        }
      }
    } else {
      $hash->{MODEL} = 'BASIC';
    }
    readingsEndUpdate($hash, 1);
    readingsSingleUpdate($hash, 'time', $hash->{GPS_TIME}, AttrVal($name, 'timeEvent', 'no') eq 'yes' ? 1 : 0) if (exists $hash->{GPS_TIME});
    $data = $rest;

    # custom command exec
    %specials = ("%NAME" => $name,
                 "%TYPE" => $hash->{TYPE},
                 "%BRIGHTNESS" => $brightness,
                 "%DATE" => $date,
                 "%DAYNIGHT" => $twilightFlag,
                 "%HEMISPHERE" => $hemisphere,
                 "%ISRAINING" => $isRaining,
                 "%ISSTORMY" => $isStormy,
                 "%ISSUNNY" => $isSunny,
                 "%ISSUNNYEAST" => $isSunnyEast,
                 "%ISSUNNYSOUTH" => $isSunnySouth,
                 "%ISSUNNYWEST" => $isSunnyWest,
                 "%ISWINDY" => $isWindy,
                 "%LATITUDE" => $latitude,
                 "%LONGITUDE" => $longitude,
                 "%SUNAZIMUTH" => $sunAzimuth,
                 "%SUNEAST" => $sunEast,
                 "%SUNELAVATION" => $sunElevation,
                 "%SUNSOUTH" => $sunSouth,
                 "%SUNWEST" => $sunWest,
                 "%TEMPERATURE" => $temperature,
                 "%TIME" => $time,
                 "%TIMEZONE" => $timeZone,
                 "%TWILIGHT" => $twilight,
                 "%WEEKDAY" => $weekday,
                 "%WINDAVG2MIN" => $windAvg2min,
                 "%WINDGUST10MIN" => $windGust10min,
                 "%WINDGUSTCURRNT" => $windGustCurrent,
                 "%WINDPEAK10MIN" => $windPeak10min,
                 "%WINDSPEED" => $windSpeed,
                 "%WINDSTENGTH" => $windStrength);

    my $customCmdDown = AttrVal($name, "customCmdDown", undef);
    my $customCmdDownPeriod = AttrVal($name, "customCmdDownPeriod", 'once');
    my $customCmdDownTrigger = AttrVal($name, 'customCmdDownTrigger', undef);
    my $customCmdUp = AttrVal($name, "customCmdUp", undef);
    my $customCmdUpPeriod = AttrVal($name, "customCmdUpPeriod", 'once');
    my $customCmdUpTrigger = AttrVal($name, 'customCmdUpTrigger', undef);
    #delete $hash->{helper}{customCmdDown}{do};
    #delete $hash->{helper}{customCmdUp}{do};

    if (defined ReadingsVal($name, 'alarm', undef)) {
      my $customCmdAlarmOff = AttrVal($name, 'customCmdAlarmOff', undef);
      if (defined $customCmdAlarmOff) {
        $hash->{helper}{customCmdAlarmOff}{do} = 1;
        ElsnerWS_CustomCmdDo($hash, 'customCmdAlarmOff', $customCmdAlarmOff, 'once');
      }
      readingsDelete($hash, 'alarm');
    }
    delete $hash->{helper}{customCmdAlarmOff};

    if (AttrVal($name, "signOfLife", 'on') eq 'on') {
      RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
      @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5, 0);
      InternalTimer(gettimeofday() + AttrVal($name, 'signOfLifeInterval', 3) + 0.5, 'ElsnerWS_AlarmOn', $hash->{helper}{timer}{alarm}, 0);
    }

    if (!exists $hash->{helper}{timer}{heartbeat}) {
      @{$hash->{helper}{timer}{heartbeat}} = ($hash, 'heartbeat');
      RemoveInternalTimer($hash->{helper}{timer}{heartbeat});
      InternalTimer(gettimeofday() + 600, 'ElsnerWS_cdmClearTimer', $hash->{helper}{timer}{heartbeat}, 0);
      #Log3 $hash->{NAME}, 3, "ElsnerWS $hash->{NAME} ElsnerWS_readingsBulkUpdate heartbeat executed.";
    }

    if (defined($customCmdDown) || defined($customCmdUp)) {
      ElsnerWS_CustomCmdDoTrigger($hash, 'customCmdDown', $customCmdDown, AttrVal($name, 'customCmdDownTrigger', undef), 0);
      ElsnerWS_CustomCmdDoTrigger($hash, 'customCmdUp', $customCmdUp, AttrVal($name, 'customCmdUpTrigger', undef), 1);

      if (exists($hash->{helper}{customCmdDown}{do}) && exists($hash->{helper}{customCmdUp}{do})) {
        if (AttrVal($name, 'customCmdPriority', 'up') eq 'up') {
          # up command has prority
          delete $hash->{helper}{customCmdDown} if (defined $customCmdDownTrigger);
        } else {
          # down command has prority
          delete $hash->{helper}{customCmdUp} if (defined $customCmdUpTrigger);
        }
      }
      ElsnerWS_CustomCmdDo($hash, 'customCmdDown', $customCmdDown, $customCmdDownPeriod);
      ElsnerWS_CustomCmdDo($hash, 'customCmdUp', $customCmdUp, $customCmdUpPeriod);
    }
  }
  if(length($data) >= 4) {
    $data =~ s/.*47/47/ if($data !~ m/^47(2B|2D)/);
    $data =~ s/.*57/57/ if($data !~ m/^57(2B|2D)/);
    $data = "" if($data !~ m/^47|57/);
  }
  $hash->{PARTIAL} = $data;
  return;
}

sub ElsnerWS_CustomCmdDoTrigger($$$$$) {
  # set do trigger
  my ($hash, $customCmdName, $customCmdVal, $customCmdTrigger, $element) = @_;
  my $readingName;
  if (defined($customCmdVal)) {
    if (defined $customCmdTrigger) {
      for (split(',', $customCmdTrigger)) {
        $readingName = "%" . uc($_);
        #Log3 $hash->{NAME}, 3, "ElsnerWS $hash->{NAME} $customCmdName Reading: $_ = " . $specials{$readingName} . " <=> " . $customCmdTrigger{$_}[$element];
        if ($customCmdTrigger{$_}[$element] eq $specials{$readingName}) {
          $hash->{helper}{$customCmdName}{do} = 1;
          last;
        } else {
          delete $hash->{helper}{$customCmdName}{do};
        }
      }
      # reset trigger
      if (!exists $hash->{helper}{$customCmdName}{do}) {
        delete $hash->{helper}{$customCmdName}{Count};
        delete $hash->{helper}{$customCmdName}{Period};
        delete $hash->{helper}{$customCmdName};
      }
    } else {
      # custom command always executed
      $hash->{helper}{$customCmdName}{Count} = -1;
      $hash->{helper}{$customCmdName}{Period} = -1;
      $hash->{helper}{$customCmdName}{do} = 1;
    }
  } else {
    # no custom command
    delete $hash->{helper}{$customCmdName}{Count};
    delete $hash->{helper}{$customCmdName}{do};
    delete $hash->{helper}{$customCmdName}{Period};
    delete $hash->{helper}{$customCmdName};
  }
  return;
}

sub ElsnerWS_CustomCmdDo($$$$) {
  my ($hash, $customCmdName, $customCmd, $customCmdPeriod) = @_;
  my $name = $hash->{NAME};
  #Log3 $name, 3, "ElsnerWS $name $customCmdName do: $hash->{helper}{$customCmdName}{do} Count: $hash->{helper}{$customCmdName}{Count}";
  #Log3 $name, 3, "ElsnerWS $name $customCmdName Count: $hash->{helper}{$customCmdName}{Count} Period: $hash->{helper}{$customCmdName}{Period} <> $customCmdPeriod{$customCmdPeriod}";
  if (exists $hash->{helper}{$customCmdName}{do}) {
    if (!exists($hash->{helper}{$customCmdName}{Period}) || $hash->{helper}{$customCmdName}{Period} != $customCmdPeriod{$customCmdPeriod}) {
      $hash->{helper}{$customCmdName}{Period} = $customCmdPeriod{$customCmdPeriod};
      $hash->{helper}{$customCmdName}{Count} = $customCmdPeriod{$customCmdPeriod};
    }
    #Log3 $name, 3, "ElsnerWS $name $customCmdName Count: $hash->{helper}{$customCmdName}{Count}";
    if ($hash->{helper}{$customCmdName}{Count} < -1) {
      $hash->{helper}{$customCmdName}{Count} ++;
    } elsif ($hash->{helper}{$customCmdName}{Count} == -1) {
      $hash->{helper}{$customCmdName}{Count} = 0;
    } elsif ($hash->{helper}{$customCmdName}{Count} == 0) {
      delete $hash->{helper}{$customCmdName}{do};
    } elsif ($hash->{helper}{$customCmdName}{Count} == $customCmdPeriod{$customCmdPeriod}) {
      $hash->{helper}{$customCmdName}{Count} --;
    } elsif ($hash->{helper}{$customCmdName}{Count} > 1) {
      $hash->{helper}{$customCmdName}{Count} --;
      delete $hash->{helper}{$customCmdName}{do};
    } elsif ($hash->{helper}{$customCmdName}{Count} == 1) {
      $hash->{helper}{$customCmdName}{Count} = $customCmdPeriod{$customCmdPeriod};
      delete $hash->{helper}{$customCmdName}{do};
    } else {
      delete $hash->{helper}{$customCmdName}{do};
    }
    if (exists $hash->{helper}{$customCmdName}{do}) {
      $customCmd = EvalSpecials($customCmd, %specials);
      my $ret = AnalyzeCommandChain(undef, $customCmd);
      Log3 $name, 2, "ElsnerWS $name $customCmdName ERROR: $ret" if($ret);
    }
  }
  return;
}

sub ElsnerWS_AlarmOn($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $ctrl, $log, $clear) = @$readingParam;
  if (defined $hash) {
    my $customCmdAlarmOn = AttrVal($hash->{NAME}, 'customCmdAlarmOn', undef);
    if (defined $customCmdAlarmOn) {
      $hash->{helper}{customCmdAlarmOn}{do} = 1;
      ElsnerWS_CustomCmdDo($hash, 'customCmdAlarmOn', $customCmdAlarmOn, 'once');
      delete $hash->{helper}{customCmdAlarmOn};
    }
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl) ;
    Log3 $hash->{NAME}, $log, " ElsnerWS " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
  }
  return;
}

sub ElsnerWS_updateArrayElement($$$$$) {
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

sub ElsnerWS_SMA($$$$$$$$) {
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

sub ElsnerWS_LWMA($$$$) {
  # linear weighted moving average (LWMA)
  my ($hash, $readingName, $readingVal, $numArrayElementsMax) = @_;
  push(@{$hash->{helper}{lwma}{$readingName}{val}}, $readingVal);
  my $average = 0;
  my $numArrayElements = $#{$hash->{helper}{lwma}{$readingName}{val}} + 1;
  for (my $i = 1; $i <= $numArrayElements; $i++) {
    $average += $i * $hash->{helper}{lwma}{$readingName}{val}[$numArrayElements - $i];
  }
  $average = $average * 2 / $numArrayElements / ($numArrayElements + 1);
  if ($numArrayElements >= $numArrayElementsMax) {
    shift(@{$hash->{helper}{lwma}{$readingName}{val}});
  }
  return $average;
}

sub ElsnerWS_EMA($$$$) {
  # exponential moving average (EMA)
  # 0 < $wheight < 1
  my ($hash, $readingName, $readingVal, $wheight) = @_;
  my $average = exists($hash->{helper}{ema}{$readingName}{average}) ? $hash->{helper}{ema}{$readingName}{average} : $readingVal;
  $average = $wheight * $readingVal + (1 - $wheight) * $average;
  $hash->{helper}{ema}{$readingName}{average} = $average;
  return $average;
}

sub ElsnerWS_Smooting($$$$$) {
  my ($hash, $readingName, $readingVal, $theshold, $averageParam) = @_;
  my $iniVal;
  $readingVal = ElsnerWS_EMA($hash, $readingName, $readingVal, $averageParam) if (defined $averageParam);
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

sub ElsnerWS_swayCtrl($$$$$$$$$$$) {
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
      InternalTimer(gettimeofday() + $swayDelay, 'ElsnerWS_swayCtrlDelay', $hash->{helper}{timer}{sway}{$readingName}{delay}, 0);
      $swayVal = $swayValLast;
    }
  }
  return $swayVal;
}

sub ElsnerWS_swayCtrlDelay($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $delay, $ctrl, $log, $clear) = @$readingParam;
  if (defined $hash) {
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl);
    Log3 $hash->{NAME}, $log, " ElsnerWS " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
    $hash->{helper}{sway}{$readingName} = $readingVal;
    delete $hash->{helper}{timer}{sway}{$readingName}{delay} if ($clear == 1);
  }
  return;
}

sub ElsnerWS_readingsSingleUpdate($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $ctrl, $log, $clear) = @$readingParam;
  if (defined $hash) {
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl) ;
    Log3 $hash->{NAME}, $log, " ElsnerWS " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
  }
  return;
}

sub ElsnerWS_readingsBulkUpdate($$$$$$) {
  my ($hash, $readingName, $readingVal, $theshold, $averageParam, $sFormat) = @_;
  if (exists $hash->{helper}{timer}{heartbeat}) {
    $readingVal = sprintf("$sFormat", ElsnerWS_Smooting($hash, $readingName, $readingVal, $theshold, $averageParam));
    readingsBulkUpdateIfChanged($hash, $readingName, $readingVal);
  } else {
    $readingVal = sprintf("$sFormat", ElsnerWS_Smooting($hash, $readingName, $readingVal, 0, $averageParam));
    readingsBulkUpdate($hash, $readingName, $readingVal);
  }
  return $readingVal;
}

#
sub ElsnerWS_cdmClearTimer($) {
  my ($functionArray) = @_;
  my ($hash, $timer) = @$functionArray;
  delete $hash->{helper}{timer}{$timer};
  #Log3 $hash->{NAME}, 3, "ElsnerWS $hash->{NAME} ElsnerWS_cdmClearTimer $timer executed.";
  return;
}

# Ready
sub ElsnerWS_Ready($) {
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, undef) if($hash->{STATE} eq "disconnected");
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  return undef if(!$po);
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

# Attributes check
sub ElsnerWS_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  # return if attribute list is incomplete
  return undef if (!$init_done);
  my $err;

  if ($attrName eq "brightnessDayNightCtrl") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^custom|sensor$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName =~ m/^.*Delay$/) {
    my ($attrVal0, $attrVal1) = split(':', $attrVal);
    if (!defined $attrVal1) {
      if (!defined $attrVal0) {

      } elsif ($attrVal0 !~ m/^[+]?\d+$/ || $attrVal0 + 0 > 3600) {
        $err = "attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");
      }
    } elsif ($attrVal1 !~ m/^[+]?\d+$/ || $attrVal1 + 0 > 3600) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    } else {
      if (!defined $attrVal0) {

      } elsif ($attrVal0 !~ m/^[+]?\d+$/ || $attrVal0 + 0 > 3600) {
        $err = "attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");
      }
    }
  } elsif ($attrName =~ m/^brightness(DayNight|Sunny).*$/) {
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
  } elsif ($attrName =~ m/^customCmd(Down|Up)Period$/) {
    my $attrValStr = join("|", keys %customCmdPeriod);
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^($attrValStr)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName =~ m/^customCmd(Down|Up)Trigger$/) {
    my $attrValStr = join("|", keys %customCmdTrigger);
    if (defined $attrVal) {
      for (split(',', $attrVal)) {
        if ($_ !~ m/^($attrValStr)$/) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
          last;
        }
      }
    }
  } elsif ($attrName eq "customCmdPriority") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^down|up$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName eq "signOfLife") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^off|on$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName eq "signOfLifeInterval") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+$/ || $attrVal + 0 < 1 || $attrVal + 0 > 15) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
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
  return $err;
}

# Notify actions
sub ElsnerWS_Notify(@) {
  my ($hash, $dev) = @_;
  return "" if (IsDisabled($hash->{NAME}));
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}})) {
    ElsnerWS_InitSerialCom($hash);
  }
  return undef;
}

# Undef
sub ElsnerWS_Undef($$) {
  my ($hash, $arg) = @_;
  DevIo_CloseDev($hash);
  return undef;
}

# Delete
sub ElsnerWS_Delete($$) {
  my ($hash, $name) = @_;
  my $logName = "FileLog_$name";
  my ($count, $gplotFile, $logFile, $weblinkName, $weblinkHash);
  Log3 $name, 2, "ElsnerWS $name deleted";
  # delete FileLog device and log files
  if (exists $defs{$logName}) {
    $logFile = $defs{$logName}{logfile};
    $logFile =~ /^(.*)($name).*\.(.*)$/;
    $logFile = $1 . $2 . "*." . $3;
    CommandDelete(undef, "FileLog_$name");
    Log3 $name, 2, "ElsnerWS FileLog_$name deleted";
    $count = unlink glob $logFile;
    Log3 $name, 2, "ElsnerWS $logFile >> $count files deleted";
  }
  # delete SVG devices and gplot files
  while (($weblinkName, $weblinkHash) = each(%defs)) {
    if ($weblinkName =~ /^SVG_$name.*/) {
      $gplotFile = "./www/gplot/" . $defs{$weblinkName}{GPLOTFILE} . "*.gplot";
      CommandDelete(undef, $weblinkName);
      Log3 $name, 2, "ElsnerWS $weblinkName deleted";
      $count = unlink glob $gplotFile;
      Log3 $name, 2, "ElsnerWS $gplotFile >> $count files deleted";
    }
  }
  return undef;
}

# Shutdown
sub ElsnerWS_Shutdown($) {
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  return undef;
}

1;

=pod
=item summary    ElsnerWS Elsner Weather Station P03/3-RS485 or P04/3-RS485 evaluation modul
=item summary_DE ElsnerWS Elsner Wetterstation P03/3-RS485 oder P04/3-RS485 Auswertemodul
=begin html

<a id="ElsnerWS"></a>
<h3>ElsnerWS</h3>
<ul>
    The ElsnerWS weather evaluation modul serves as a connecting link between the
    <a href="https://www.elsner-elektronik.de/shop/de/produkte-shop/gebaeudetechnik-konventionell/rs485-sensoren/p03-3-rs485.html">Elsner P03/3-RS485 Weather Stations</a> or
    <a href="https://www.elsner-elektronik.de/shop/de/produkte-shop/gebaeudetechnik-konventionell/rs485-sensoren/p04-3-rs485.html">Elsner P04/3-RS485 Weather Stations</a> or
    and blind actuators. ElsnerWS use a RS485 connection to communicate with the
    <a href="https://www.elsner-elektronik.de/shop/de/produkte-shop/gebaeudetechnik-konventionell/rs485-sensoren.html">Elsner P0x/3-RS485 Weather Stations</a>.
    It received the raw weather data periodically once a second, which manufacturer-specific coded via an RS485 bus serially are sent.
    It evaluates the received weather data and based on adjustable thresholds and delay times it generates up/down signals
    for blinds according to wind, rain and sun. This way blinds can be pilot-controlled and protected against thunderstorms.
    The GPS function of the sensor provides the current values of the date, time, weekday, sun azimuth, sun elevation, longitude
    and latitude.<br>
    As an alternative to the module for the Elsner RS485 sensors, sensors with Modbus RS485 protocol can also be used.
    The <a href="#ModbusElsnerWS">ModbusElsnerWS</a> module is available for this purpose. EnOcean profiles
    "Environmental Applications" with the EEP A5-13-01 ... EEP A5-13-06 are also available for these weather stations,
    but they also require weather evaluation units from Eltako or AWAG, for example. The functional scope of the
    modules is widely similar.
    <br><br>

    <b>Functions</b>
    <ul>
      <li>Evaluation modul for the weather sensors P03/3-RS485 or P04/3-RS485 (Basic|CET|GPS)</li>
      <li>Processing weather raw data and creates graphic representation</li>
      <li>For wind observations, average speeds, gusts and peak values are calculated.</li>
      <li>Alarm signal in case of failure of the weather sensor</li>
      <li>Up/down readings for blinds according to wind, rain and sun</li>
      <li>Adjustable switching thresholds and delay times</li>
      <li>Day/night signal</li>
      <li>Display of date, time, sun azimuth, sun elevation, longitude and latitude</li>
      <li>Execution of custom alarm commands, see <a href="#ElsnerWS-attr-customCmdAlarmOff">customCmdAlarmOff</a> and
      <a href="#ElsnerWS-attr-customCmdAlarmOn">customCmdAlarmOn</a>.</li>
      <li>Execution of custom up and down commands that can be triggered by the readings dayNight, isRaining, isStormy,
      isSunny, isSunnyEast, isSunnySouth, isSunnyWest and isWindy, see <a href="#ElsnerWS-attr-customCmdDown">customCmdDown</a> and
      <a href="#ElsnerWS-attr-customCmdUp">customCmdUp</a>.</li>
    </ul><br>

    <b>Prerequisites</b>
      <ul>
        This module requires the basic Device::SerialPort or Win32::SerialPort module.
      </ul><br>

    <b>Hardware Connection</b>
      <ul>
        The weather sensors P03/3-RS485 or P04/3-RS485 are connected via a shielded cable 2x2x0.5 mm2 to a RS485 transceiver.
        The sensor is connected via the pins A to the RS485 B(+)-Port, B to RS485 A(-)-Port, 1 to + 24 V, 2 to GND and Shield.
        Please note that the RS485 connection names are reversed. Only the usual pins for serial Modbus communication A, B and Ground are needed. Multiple Fhem devices can be connected to the sensor
        via the RS485 bus at the same time.<br>
        The serial bus should be terminated at its most remote ends with 120 Ohm resistors. If several RS485 transceiver are connected to
        the serial bus, only the termination resistor in the devices furthest ends must be switched on.<br>
        More information about the sensors, see for example
        <a href="https://www.elsner-elektronik.de/shop/de/fileuploader/download/download/?d=1&file=custom%2Fupload%2F30145_P033-RS485-GPS_Datenblatt_13Sep18_DBEEA6042.pdf">P03/3-RS485-GPS User Guide</a>.<br>
        The USB adapters
        <a href="https://www.digitus.info/produkte/computer-und-office-zubehoer/computer-zubehoer/usb-komponenten-und-zubehoer/schnittstellen-adapter/da-70157/">Digitus DA-70157</a>,
        <a href="https://shop.in-circuit.de/product_info.php?cPath=33&products_id=81">In-Circuit USB-RS485-Bridge</a>
        and <a href="http://www.dsdtech-global.com/2018/01/sh-u10-spp.html">DSD TECH SH-U10 USB to RS485 converter</a>
        are successfully tested at a Raspberry PI in conjunction with the weather sensor.
      </ul><br>

    <a id="ElsnerWS-Define"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; ElsnerWS comtype=&lt;comtype&gt; devicename=&lt;devicename&gt;</code><br><br>
      The module connects to the Elsner Weather Station via serial bus &lt;rs485&gt; through the device &lt;device&gt;.<br>
      The following parameters apply to an RS485 transceiver to USB.
      <br><br>
      Example:<br>
      <code>define WS ElsnerWS comtype=rs485 devicename=/dev/ttyUSB1@19200</code><br>
      <code>define WS ElsnerWS comtype=rs485 devicename=COM1@19200</code> (Windows)
      <br><br>
      Alternatively, the device can also be created automatically by autocreate. Once the weather station is connected
      to Fhem via the RS485 USB transceiver, Fhem is to be restarted. The active but not yet configured USB ports are
      searched for a ready-to-operate weather station during the Fhem boot.
    </ul><br>

    <a id="ElsnerWS-attr"></a>
    <b>Attributes</b>
    <ul>
      <ul>
        <li><a id="ElsnerWS-attr-brightnessDayNight">brightnessDayNight</a> E_min/lx:E_max/lx,
          [brightnessDayNight] = 0...99000:0...99000, 10:20 is default.<br>
          Set switching thresholds for reading dayNight based on the reading brightness.
        </li>
        <li><a id="ElsnerWS-attr-brightnessDayNightCtrl">brightnessDayNightCtrl</a> custom|sensor,
          [brightnessDayNightCtrl] = custom|sensor, sensor is default.<br>
          Control the dayNight reading through the device-specific or custom threshold and delay.
        </li>
        <li><a id="ElsnerWS-attr-brightnessDayNightDelay">brightnessDayNightDelay</a> t_reset/s:t_set/s,
          [brightnessDayNightDelay] = 0...3600:0...3600, 600:600 is default.<br>
          Set switching delay for reading dayNight based on the reading brightness. The reading dayNight is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunny">brightnessSunny</a> E_min/lx:E_max/lx,
          [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunny based on the reading brightness.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnyDelay">brightnessSunnyDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyDelay] = 0...3600:0...3600, 120:30 is default.<br>
          Set switching delay for reading isSunny based on the reading brightness. The reading isSunny is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnyEast">brightnessSunnyEast</a> E_min/lx:E_max/lx,
          [brightnessSunnyEast] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunnyEast based on the reading sunEast.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnyEastDelay">brightnessSunnyEastDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyEastDelay] = 0...3600:0...3600, 120:30 is default.<br>
          Set switching delay for reading isSunnyEast based on the reading sunEast. The reading isSunnyEast is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnySouth">brightnessSunnySouth</a> E_min/lx:E_max/lx,
          [brightnessSunnySouth] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunnySouth based on the reading sunSouth.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnySouthDelay">brightnessSunnySouthDelay</a> t_reset/s:t_set/s,
          [brightnessSunnySouthDelay] = 0...3600:0...3600, 120:30 is default.<br>
          Set switching delay for reading isSunnySouth based on the reading sunSouth. The reading isSunnySouth is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnyWest">brightnessSunnyWest</a> E_min/lx:E_max/lx,
          [brightnessSunnyWest] = 0...99000:0...99000, 20000:40000 is default.<br>
          Set switching thresholds for reading isSunnyWest based on the reading sunWest.
        </li>
        <li><a id="ElsnerWS-attr-brightnessSunnyWestDelay">brightnessSunnyWestDelay</a> t_reset/s:t_set/s,
          [brightnessSunnyWestDelay] = 0...3600:0...3600, 120:30 is default.<br>
          Set switching delay for reading isSunnyWest based on the reading sunWest. The reading isSunnyWest is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a id="ElsnerWS-attr-customCmdAlarmOff">customCmdAlarmOff</a> &lt;command&gt;<br>
          <a id="ElsnerWS-attr-customCmdAlarmOn">customCmdAlarmOn</a> &lt;command&gt;<br>
          Command being executed if an alarm is set (on) or deleted (off).  If &lt;command&gt; is enclosed in {},
          then it is a perl expression, if it is enclosed in "", then it is a shell command,
          else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the name of the device by using $NAME, $TYPE
          and the current readings<br>
          $BRIGHTNESS, $DATE, $DAYNIGHT, $HEMISPHERE, $ISRAINING, $ISSTORMY, $ISSUNNY, $ISSUNNYEAST, $ISSUNNYSOUTH",
          $ISSUNNYWEST, $ISWINDY, $LATITUDE, $LONGITUDE, $NAME, $SUNAZIMUTH, $SUNEAST, $SUNELAVATION, $SUNSOUTH, $SUNWEST, $TEMPERATURE, $TIME,
          $TIMEZONE, $TWILIGHT, $TYPE, $WEEKDAY, $WINDAVG2MIN, $WINDGUST10MIN, $WINDGUSTCURRNT, $WINDPEAK10MIN, $WINDSPEED, $WINDSTENGTH.<br>
          The <a href="#eventMap">eventMap</a> replacements are taken into account. This data
          is available as a local variable in perl, as environment variable for shell
          scripts, and will be textually replaced for Fhem commands.<br>
          The alarm commands have a higher priority than the up and down commands.
        </li>
        <li><a id="ElsnerWS-attr-customCmdDown">customCmdDown</a> &lt;command&gt;<br>
          <a id="ElsnerWS-attr-customCmdUp">customCmdUp</a> &lt;command&gt;<br>
          The command is executed if the Up or Down command is triggered, see <a href="#ElsnerWS-attr-customCmdDownTrigger">customCmdDownTrigger</a> or
          <a href="#ElsnerWS-attr-customCmdUpTrigger">customCmdUpTrigger</a>. If &lt;command&gt; is enclosed in {},
          then it is a perl expression, if it is enclosed in "", then it is a shell command,
          else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the name of the device by using $NAME, $TYPE
          and the current readings<br>
          $BRIGHTNESS, $DATE, $DAYNIGHT, $HEMISPHERE, $ISRAINING, $ISSTORMY, $ISSUNNY, $ISSUNNYEAST, $ISSUNNYSOUTH",
          $ISSUNNYWEST, $ISWINDY, $LATITUDE, $LONGITUDE, $NAME, $SUNAZIMUTH, $SUNEAST, $SUNELAVATION, $SUNSOUTH, $SUNWEST, $TEMPERATURE, $TIME,
          $TIMEZONE, $TWILIGHT, $TYPE, $WEEKDAY, $WINDAVG2MIN, $WINDGUST10MIN, $WINDGUSTCURRNT, $WINDPEAK10MIN, $WINDSPEED, $WINDSTENGTH.<br>
          The <a href="#eventMap">eventMap</a> replacements are taken into account. This data
          is available as a local variable in perl, as environment variable for shell
          scripts, and will be textually replaced for Fhem commands.<br>
          The alarm commands have a higher priority than the up and down commands.
        </li>
        <li><a id="ElsnerWS-attr-customCmdDownPeriod">customCmdDownPeriod</a> once|threeTimes|3|10|180|600<br>
          <a id="ElsnerWS-attr-customCmdUpPeriod">customCmdUpPeriod</a> once|threeTimes|3|10|180|600<br>
          [customCmdDownPeriod] = once|threeTimes|3|10|180|600, once is default.<br>
          Number or period of custom command to be executed.
        </li>
        <li><a id="ElsnerWS-attr-customCmdDownTrigger">customCmdDownTrigger</a> dayNight|isRaining|isStormy|isSunny|isSunnyEast|isSunnySouth|isSunnyWest|isWindy<br>
          The commands in the attribute <a href="#ElsnerWS-attr-customCmdDown">customCmdDown</a> are executed if one of the selected readings is triggered as follows:
          <ul>
            <li>[dayNight] = night</li>
            <li>[isRaining] = no</li>
            <li>[isStormy] = no</li>
            <li>[isSunny] = yes</li>
            <li>[isSunnyEast] = yes</li>
            <li>[isSunnySouth] = yes</li>
            <li>[isSunnyWest] = yes</li>
            <li>[isWindy] = no</li>
           </ul>
          The commands in the attribute <a href="#ElsnerWS-attr-customCmdDown">customCmdDown</a> are executed periodically every second if the attribute is not set.
        </li>
        <li><a id="ElsnerWS-attr-customCmdUpTrigger">customCmdUpTrigger</a> dayNight|isRaining|isStormy|isSunny|isSunnyEast|isSunnySouth|isSunnyWest|isWindy<br>
          The commands in the attribute <a href="#ElsnerWS-attr-customCmdUp">customCmdUp</a> are executed if one of the selected readings is triggered as follows:
          <ul>
             <li>[dayNight] = day</li>
              <li>[isRaining] = yes</li>
              <li>[isStormy] = yes</li>
              <li>[isSunny] = no</li>
              <li>[isSunnyEast] = no</li>
              <li>[isSunnySouth] = no</li>
              <li>[isSunnyWest] = no</li>
              <li>[isWindy] = yes</li>
           </ul>
          The commands in the attribute <a href="#ElsnerWS-attr-customCmdUp">customCmdUp</a> are executed periodically every second if the attribute is not set.
        </li>
        <li><a id="ElsnerWS-attr-customCmdPriority">customCmdPriority</a> down|up,
          [customCmdPriority] = down|up, up is default.<br>
          Priority of custom commands. If both the up and down command are triggered, only the prioritized command is executed.
        </li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <li><a id="ElsnerWS-attr-signOfLife">signOfLife</a> off|on,
          [signOfLife] = off|on, on is default.<br>
          Monitoring of the periodic telegrams from sensor.
        </li>
        <li><a id="ElsnerWS-attr-signOfLifeInterval">signOfLifeInterval</a> t/s,
          [signOfLifeInterval] = 1 ... 15, 3 is default.<br>
          Monitoring period in seconds of the periodic telegrams from sensor.
        </li>
        <li><a id="ElsnerWS-attr-timeEvent">timeEvent</a> no|yes,
          [timeEvent] = no|yes, no is default.<br>
          Update the reading time periodically.
        </li>
        <li><a id="ElsnerWS-attr-updateGlobalAttr">updateGlobalAttr</a> no|yes,
          [updateGlobalAttr] = no|yes, no is default.<br>
          Update the global attributes latitude and longitude with the received GPS coordinates.
        </li>
        <li><a id="ElsnerWS-attr-windSpeedStormy">windSpeedStormy</a> v_min/m/s:v_max/m/s,
          [windSpeedStormy] = 0...35:0...35, 13.9:17.2 (windStrength = 7 B - 8 B) is default.<br>
          Set switching thresholds for reading isStormy based on the reading windSpeed.
        </li>
        <li><a id="ElsnerWS-attr-windSpeedStormyDelay">windSpeedStormyDelay</a> t_reset/s:t_set/s,
          [windSpeedStormyDelay] = 0...3600:0...3600, 60:3 is default.<br>
          Set switching delay for reading isStormy based on the reading windSpeed. The reading isStormy is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
        <li><a id="ElsnerWS-attr-windSpeedWindy">windSpeedWindy</a> v_min/m/s:v_max/m/s,
          [windSpeedWindy] = 0...35:0...35, 1.6:3.4 (windStrength = 2 B - 3 B) is default.<br>
          Set switching thresholds for reading isWindy based on the reading windSpeed.
        </li>
        <li><a id="ElsnerWS-attr-windSpeedWindyDelay">windSpeedWindyDelay</a> t_reset/s:t_set/s,
          [windSpeedWindyDelay] = 0...3600:0...3600, 60:3 is default.<br>
          Set switching delay for reading isWindy based on the reading windSpeed. The reading isWindy is reset or set
          if the thresholds are permanently undershot or exceed during the delay time.
        </li>
      </ul>
    </ul><br>

  <a id="ElsnerWS-events"></a>
  <b>Generated events</b>
  <ul>
    <ul>
      <li>T: t/&#176C B: E/lx W: v/m/s IR: no|yes</li>
      <li>alarm: dead_sensor</li>
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
      <li>weekday: Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday</li>
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
