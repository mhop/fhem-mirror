##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012-2013
#
package main;

use strict;
use warnings;
use MIME::Base64;
use MaxCommon;

sub MAX_Define($$);
sub MAX_Undef($$);
sub MAX_Initialize($);
sub MAX_Parse($$);
sub MAX_Set($@);
sub MAX_MD15Cmd($$$);
sub MAX_DateTime2Internal($);

my @ctrl_modes = ( "auto", "manual", "temporary", "boost" );

my %boost_durations = (0 => 0, 1 => 5, 2 => 10, 3 => 15, 4 => 20, 5 => 25, 6 => 30, 7 => 60);
my %boost_durationsInv = reverse %boost_durations;

my %decalcDays = (0 => "Sat", 1 => "Sun", 2 => "Mon", 3 => "Tue", 4 => "Wed", 5 => "Thu", 6 => "Fri");
my %decalcDaysInv = reverse %decalcDays;

sub validWindowOpenDuration { return $_[0] =~ /^\d+$/ && $_[0] >= 0 && $_[0] <= 60; }
sub validMeasurementOffset { return $_[0] =~ /^-?\d+(\.[05])?$/ && $_[0] >= -3.5 && $_[0] <= 3.5; }
sub validBoostDuration { return $_[0] =~ /^\d+$/ && exists($boost_durationsInv{$_[0]}); }
sub validValveposition { return $_[0] =~ /^\d+$/ && $_[0] >= 0 && $_[0] <= 100; }
sub validDecalcification { my ($decalcDay, $decalcHour) = ($_[0] =~ /^(...) (\d{1,2}):00$/);
  return defined($decalcDay) && defined($decalcHour) && exists($decalcDaysInv{$decalcDay}) && 0 <= $decalcHour && $decalcHour < 24; }
sub validWeekProfile { return length($_[0]) == 4*13*7; }
sub validGroupid { return $_[0] =~ /^\d+$/ && $_[0] >= 0 && $_[0] <= 255; }

my %readingDef = ( #min/max/default
  "maximumTemperature"    => [ \&validTemperature, "on"],
  "minimumTemperature"    => [ \&validTemperature, "off"],
  "comfortTemperature"    => [ \&validTemperature, 21],
  "ecoTemperature"        => [ \&validTemperature, 17],
  "windowOpenTemperature" => [ \&validTemperature, 12],
  "windowOpenDuration"    => [ \&validWindowOpenDuration,   15],
  "measurementOffset"     => [ \&validMeasurementOffset, 0],
  "boostDuration"         => [ \&validBoostDuration, 5 ],
  "boostValveposition"    => [ \&validValveposition, 80 ],
  "decalcification"       => [ \&validDecalcification, "Sat 12:00" ],
  "maxValveSetting"       => [ \&validValveposition, 100 ],
  "valveOffset"           => [ \&validValveposition, 00 ],
  "groupid"               => [ \&validGroupid, 0 ],
  ".weekProfile"          => [ \&validWeekProfile, $defaultWeekProfile ],
);

my %interfaces = (
  "Cube" => undef,
  "HeatingThermostat" => "thermostat;battery;temperature",
  "HeatingThermostatPlus" => "thermostat;battery;temperature",
  "WallMountedThermostat" => "thermostat;temperature;battery",
  "ShutterContact" => "switch_active;battery",
  "PushButton" => "switch_passive;battery"
  );

sub
MAX_Initialize($)
{
  my ($hash) = @_;

  Log GetLogLevel($hash->{NAME}, 5), "Calling MAX_Initialize";
  $hash->{Match}     = "^MAX";
  $hash->{DefFn}     = "MAX_Define";
  $hash->{UndefFn}   = "MAX_Undef";
  $hash->{ParseFn}   = "MAX_Parse";
  $hash->{SetFn}     = "MAX_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 keepAuto:0,1 scanTemp:0,1 ".
                       $readingFnAttributes;
  return undef;
}

#############################
sub
MAX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  return "name \"$name\" is reserved for internal use" if($name eq "fakeWallThermostat" or $name eq "fakeShutterContact");
  return "wrong syntax: define <name> MAX type addr"
        if(int(@a)!=4 || $a[3] !~ m/^[A-F0-9]{6}$/i);

  my $type = $a[2];
  my $addr = lc($a[3]); #all addr should be lowercase
  if(exists($modules{MAX}{defptr}{$addr})) {
    my $msg = "MAX_Define: Device with addr $addr is already defined";
    Log 1, $msg;
    return $msg;
  }
  if($type eq "Cube") {
    my $msg = "MAX_Define: Device type 'Cube' is deprecated. All properties have been moved to the MAXLAN device.";
    Log 1, $msg;
    return $msg;
  }
  Log GetLogLevel($hash->{NAME}, 5), "Max_define $type with addr $addr ";
  $hash->{type} = $type;
  $hash->{addr} = $addr;
  $modules{MAX}{defptr}{$addr} = $hash;

  $hash->{internals}{interfaces} = $interfaces{$type};

  AssignIoPort($hash);
  return undef;
}

sub
MAX_Undef($$)
{
  my ($hash,$name) = @_;
  delete($modules{MAX}{defptr}{$hash->{addr}});
  return undef;
}

sub
MAX_DateTime2Internal($)
{
  my($day, $month, $year, $hour, $min) = ($_[0] =~ /^(\d{2}).(\d{2})\.(\d{4}) (\d{2}):(\d{2})$/);
  return (($month&0xE) << 20) | ($day << 16) | (($month&1) << 15) | (($year-2000) << 8) | ($hour*2 + int($min/30));
}

sub
MAX_TypeToTypeId($)
{
  foreach (keys %device_types) {
    return $_ if($_[0] eq $device_types{$_});
  }
  Log 1, "MAX_TypeToTypeId: Invalid type $_[0]";
  return 0;
}

sub
MAX_CheckIODev($)
{
  my $hash = shift;
  return !defined($hash->{IODev}) || ($hash->{IODev}{TYPE} ne "MAXLAN" && $hash->{IODev}{TYPE} ne "CUL_MAX");
}

# Print number in format "0.0", pass "on" and "off" verbatim, convert 30.5 and 4.5 to "on" and "off"
# Used for "desiredTemperature", "ecoTemperature" etc. but not "temperature"
sub
MAX_SerializeTemperature($)
{
  if($_[0] eq  "on" or $_[0] eq "off") {
    return $_[0];
  } elsif($_[0] == 4.5) {
    return "off";
  } elsif($_[0] == 30.5) {
    return "on";
  } else {
    return sprintf("%2.1f",$_[0]);
  }
}

sub
MAX_Validate(@)
{
  my ($name,$val) = @_;
  return 1 if(!exists($readingDef{$name}));
  return $readingDef{$name}[0]->($val);
}

#Get a reading, validating it's current value (maybe forcing to the default if invalid)
#"on" and "off" are converted to their numeric values
sub
MAX_ReadingsVal(@)
{
  my ($hash,$name) = @_;

  my $val = ReadingsVal($hash->{NAME},$name,"");
  #$readingDef{$name} array is [validatingFunc, defaultValue]
  if(exists($readingDef{$name}) and !$readingDef{$name}[0]->($val)) {
    #Error: invalid value
    Log 2, "MAX: Invalid value $val for READING $name. Forcing to $readingDef{$name}[1]";
    $val = $readingDef{$name}[1];

    #Save default value to READINGS
    if(exists($hash->{".updateTimestamp"})) {
      readingsBulkUpdate($hash,$name,$val);
    } else {
      readingsSingleUpdate($hash,$name,$val,0);
    }
  }
  return MAX_ParseTemperature($val);
}

sub
MAX_ParseWeekProfile(@) {
  my ($hash ) = @_;
  # Format of weekprofile: 16 bit integer (high byte first) for every control point, 13 control points for every day
  # each 16 bit integer value is parsed as
  # int time = (value & 0x1FF) * 5;
  # int hour = (time / 60) % 24;
  # int minute = time % 60;
  # int temperature = ((value >> 9) & 0x3F) / 2;

  my $curWeekProfile = MAX_ReadingsVal($hash, ".weekProfile");
  #parse weekprofiles for each day
  for (my $i=0;$i<7;$i++) {
    my (@time_prof, @temp_prof);
    for(my $j=0;$j<13;$j++) {
      $time_prof[$j] = (hex(substr($curWeekProfile,($i*52)+ 4*$j,4))& 0x1FF) * 5;
      $temp_prof[$j] = (hex(substr($curWeekProfile,($i*52)+ 4*$j,4))>> 9 & 0x3F ) / 2;
    }

    my @hours;
    my @minutes;
    my $j;
    for($j=0;$j<13;$j++) {
      $hours[$j] = ($time_prof[$j] / 60 % 24);
      $minutes[$j] = ($time_prof[$j]%60);
      #if 00:00 reached, last point in profile was found
      last if(int($hours[$j])==0 && int($minutes[$j])==0 );
    }
    my $time_prof_str = "00:00";
    my $temp_prof_str;
    for (my $k=0;$k<=$j;$k++) {
      $time_prof_str .= sprintf("-%02d:%02d", $hours[$k], $minutes[$k]);
      $temp_prof_str .= sprintf("%2.1f °C",$temp_prof[$k]);
      if ($k < $j) {
        $time_prof_str .= "  /  " . sprintf("%02d:%02d", $hours[$k], $minutes[$k]);
        $temp_prof_str .= "  /  ";
      }
   }
   readingsBulkUpdate($hash, "weekprofile-$i-$decalcDays{$i}-time", $time_prof_str );
   readingsBulkUpdate($hash, "weekprofile-$i-$decalcDays{$i}-temp", $temp_prof_str );
  }
}
#############################

sub
MAX_WakeUp($)
{
  my $hash = $_[0];
  #3F corresponds to 31 seconds wakeup (so its probably the lower 5 bits)
  return ($hash->{IODev}{Send})->($hash->{IODev},"WakeUp",$hash->{addr}, "3F", callbackParam => "31" );
}

sub
MAX_Set($@)
{
  my ($hash, $devname, @a) = @_;
  my ($setting, @args) = @a;

  return "Invalid IODev" if(MAX_CheckIODev($hash));

  if($setting eq "desiredTemperature" and $hash->{type} =~ /.*Thermostat.*/) {
    return "missing a value" if(@args == 0);

    my $temperature;
    my $until = undef;
    my $ctrlmode = 1; #0=auto, 1=manual; 2=temporary

    if(AttrVal($hash->{NAME},"keepAuto","0") ne "0"
      && MAX_ReadingsVal($hash,"mode") eq "auto") {
      Log 5, "MAX_Set: staying in auto mode";
      $ctrlmode = 0; #auto
    }

    if($args[0] eq "auto") {
      #This enables the automatic/schedule mode where the thermostat follows the weekly program

      #There can be a temperature supplied, which will be kept until the next switch point of the weekly program
      if(@args > 1) {
        if($args[1] eq "eco") {
          $temperature = MAX_ReadingsVal($hash,"ecoTemperature");
        } elsif($args[1] eq "comfort") {
          $temperature = MAX_ReadingsVal($hash,"comfortTemperature");
        } else {
          $temperature = MAX_ParseTemperature($args[1]);
        }
      } else {
        $temperature = 0; #use temperature from weekly program
      }

      $ctrlmode = 0; #auto
    } elsif($args[0] eq "boost") {
      $temperature = 0;
      $ctrlmode = 3;
      #TODO: auto mode with temperature is also possible
    } elsif($args[0] eq "eco") {
      $temperature = MAX_ReadingsVal($hash,"ecoTemperature");
    } elsif($args[0] eq "comfort") {
      $temperature = MAX_ReadingsVal($hash,"comfortTemperature");
    }else{
      $temperature = MAX_ParseTemperature($args[0]);
    }

    if(@args > 1 and ($args[1] eq "until") and ($ctrlmode == 1)) {
      $ctrlmode = 2; #temporary
      $until = sprintf("%06x",MAX_DateTime2Internal($args[2]." ".$args[3]));
    }

    my $payload = sprintf("%02x",int($temperature*2.0) | ($ctrlmode << 6));
    $payload .= $until if(defined($until));
    my $groupid = MAX_ReadingsVal($hash,"groupid");
    return ($hash->{IODev}{Send})->($hash->{IODev},"SetTemperature",$hash->{addr},$payload, groupId => sprintf("%02x",$groupid), flags => ( $groupid ? "04" : "00" ));

  }elsif(grep (/^\Q$setting\E$/, ("boostDuration", "boostValveposition", "decalcification","maxValveSetting","valveOffset"))
      and $hash->{type} =~ /.*Thermostat.*/){

    my $val = join(" ",@args); #decalcification contains a space

    if(!MAX_Validate($setting, $val)) {
      my $msg = "Invalid value $args[0] for $setting";
      Log 1, $msg;
      return $msg;
    }

    my %h;
    $h{boostDuration} = MAX_ReadingsVal($hash,"boostDuration");
    $h{boostValveposition} = MAX_ReadingsVal($hash,"boostValveposition");
    $h{decalcification} = MAX_ReadingsVal($hash,"decalcification");
    $h{maxValveSetting} = MAX_ReadingsVal($hash,"maxValveSetting");
    $h{valveOffset} = MAX_ReadingsVal($hash,"valveOffset");

    $h{$setting} = MAX_ParseTemperature($val);

    my ($decalcDay, $decalcHour) = ($h{decalcification} =~ /^(...) (\d{1,2}):00$/);
    my $decalc = ($decalcDaysInv{$decalcDay} << 5) | $decalcHour;
    my $boost = ($boost_durationsInv{$h{boostDuration}} << 5) | int($h{boostValveposition}/5);

    my $payload = sprintf("%02x%02x%02x%02x", $boost, $decalc, int($h{maxValveSetting}*255/100), int($h{valveOffset}*255/100));
    return ($hash->{IODev}{Send})->($hash->{IODev},"ConfigValve",$hash->{addr},$payload,callbackParam => "$setting,$val");

  }elsif($setting eq "groupid"){
    return "argument needed" if(@args == 0);

    if($args[0]) {
      return ($hash->{IODev}{Send})->($hash->{IODev},"SetGroupId",$hash->{addr}, sprintf("%02x",$args[0]), callbackParam => "$args[0]" );
    } else {
      return ($hash->{IODev}{Send})->($hash->{IODev},"RemoveGroupId",$hash->{addr}, "00", callbackParam => "0");
    }

  }elsif( grep (/^\Q$setting\E$/, ("ecoTemperature", "comfortTemperature", "measurementOffset", "maximumTemperature", "minimumTemperature", "windowOpenTemperature", "windowOpenDuration" )) and $hash->{type} =~ /.*Thermostat.*/) {
    return "Cannot set without IODev" if(!exists($hash->{IODev}));

    if(!MAX_Validate($setting, $args[0])) {
      my $msg = "Invalid value $args[0] for $setting";
      Log 1, $msg;
      return $msg;
    }

    my %h;
    $h{comfortTemperature} = MAX_ReadingsVal($hash,"comfortTemperature");
    $h{ecoTemperature} = MAX_ReadingsVal($hash,"ecoTemperature");
    $h{maximumTemperature} = MAX_ReadingsVal($hash,"maximumTemperature");
    $h{minimumTemperature} = MAX_ReadingsVal($hash,"minimumTemperature");
    $h{windowOpenTemperature} = MAX_ReadingsVal($hash,"windowOpenTemperature");
    $h{windowOpenDuration} = MAX_ReadingsVal($hash,"windowOpenDuration");
    $h{measurementOffset} = MAX_ReadingsVal($hash,"measurementOffset");

    $h{$setting} = MAX_ParseTemperature($args[0]);

    my $comfort = int($h{comfortTemperature}*2);
    my $eco = int($h{ecoTemperature}*2);
    my $max = int($h{maximumTemperature}*2);
    my $min = int($h{minimumTemperature}*2);
    my $offset = int(($h{measurementOffset} + 3.5)*2);
    my $windowOpenTemp = int($h{windowOpenTemperature}*2);
    my $windowOpenTime = int($h{windowOpenDuration}/5);

    my $groupid = MAX_ReadingsVal($hash,"groupid");
    my $payload = sprintf("%02x%02x%02x%02x%02x%02x%02x",$comfort,$eco,$max,$min,$offset,$windowOpenTemp,$windowOpenTime);
    if($setting eq "measurementOffset") {
      return ($hash->{IODev}{Send})->($hash->{IODev},"ConfigTemperatures",$hash->{addr},$payload, groupId => "00", flags => "00", callbackParam => "$setting,$args[0]");
    } else {
      return ($hash->{IODev}{Send})->($hash->{IODev},"ConfigTemperatures",$hash->{addr},$payload, groupId => sprintf("%02x",$groupid), flags => ( $groupid ? "04" : "00" ), callbackParam => "$setting,$args[0]");
    }

  } elsif($setting eq "displayActualTemperature" and $hash->{type} eq "WallMountedThermostat") {
    return "Invalid arg" if($args[0] ne "0" and $args[0] ne "1");

    return ($hash->{IODev}{Send})->($hash->{IODev},"SetDisplayActualTemperature",$hash->{addr},
      sprintf("%02x",$args[0] ? 4 : 0), callbackParam => "$setting,$args[0]");

  } elsif($setting eq "fake") { #Deprecated, use fakeWT and fakeSC of CUL_MAX
    #Resolve first argument to address
    return "Invalid number of arguments" if(@args == 0);
    my $dest = $args[0];
    if(exists($defs{$dest})) {
      return "Destination is not a MAX device" if($defs{$dest}{TYPE} ne "MAX");
      $dest = $defs{$dest}{addr};
    } else {
      return "No MAX device with address $dest" if(!exists($modules{MAX}{defptr}{$dest}));
    }

    if($hash->{type} eq "ShutterContact") {
      return "Invalid number of arguments" if(@args != 2);
      Log 2, "fake is deprectaed and will be removed. Please use CUL_MAX's fakeSC";
      my $state = $args[1] ? "12" : "10";
      return ($hash->{IODev}{Send})->($hash->{IODev},"ShutterContactState",$dest,$state, flags => "06", src => $hash->{addr});
    } elsif($hash->{type} eq "WallMountedThermostat") {
      return "Invalid number of arguments" if(@args != 3);

      return "desiredTemperature is invalid" if($args[1] < 4.5 || $args[2] > 30.5);
      Log 2, "fake is deprectaed and will be removed. Please use CUL_MAX's fakeWT";
      $args[2] = 0 if($args[2] < 0); #Clamp temperature to minimum of 0 degree

      #Encode into binary form
      my $arg2 = int(10*$args[2]);
      #First bit is 9th bit of temperature, rest is desiredTemperature
      my $arg1 = (($arg2&0x100)>>1) | (int(2*$args[1])&0x7F);
      $arg2 &= 0xFF; #only take the lower 8 bits

      return ($hash->{IODev}{Send})->($hash->{IODev},"WallThermostatControl",$dest,
        sprintf("%02x%02x",$arg1,$arg2),flags => "04", src => $hash->{addr});
    } else {
      return "fake does not work for device type $hash->{type}";
    }

  } elsif(grep /^\Q$setting\E$/, ("associate", "deassociate")) {
    my $dest = $args[0];
    my $destType;
    if($dest eq "fakeWallThermostat") {
      return "IODev is not CUL_MAX" if($hash->{IODev}->{TYPE} ne "CUL_MAX");
      $dest = AttrVal($hash->{IODev}->{NAME}, "fakeWTaddr", "111111");
      return "Invalid fakeWTaddr attribute set (must not be 000000)" if($dest eq "000000");
      $destType = MAX_TypeToTypeId("WallMountedThermostat");

    } elsif($dest eq "fakeShutterContact") {
      return "IODev is not CUL_MAX" if($hash->{IODev}->{TYPE} ne "CUL_MAX");
      $dest = AttrVal($hash->{IODev}->{NAME}, "fakeSCaddr", "222222");
      return "Invalid fakeSCaddr attribute set (must not be 000000)" if($dest eq "000000");
      $destType = MAX_TypeToTypeId("ShutterContact");

    } else {
      if(exists($defs{$dest})) {
        return "Destination is not a MAX device" if($defs{$dest}{TYPE} ne "MAX");
        $dest = $defs{$dest}{addr};
      } else {
        return "No MAX device with address $dest" if(!exists($modules{MAX}{defptr}{$dest}));
      }
      $destType = MAX_TypeToTypeId($modules{MAX}{defptr}{$dest}{type});
    }

    Log GetLogLevel($hash->{NAME}, 5), "Using dest $dest, destType $destType";
    if($setting eq "associate") {
      return ($hash->{IODev}{Send})->($hash->{IODev},"AddLinkPartner",$hash->{addr},sprintf("%s%02x", $dest, $destType));
    } else {
      return ($hash->{IODev}{Send})->($hash->{IODev},"RemoveLinkPartner",$hash->{addr},sprintf("%s%02x", $dest, $destType));
    }


  } elsif($setting eq "factoryReset") {

    if(exists($hash->{IODev}{RemoveDevice})) {
      #MAXLAN
      return ($hash->{IODev}{RemoveDevice})->($hash->{IODev},$hash->{addr});
    } else {
      #CUL_MAX
      return ($hash->{IODev}{Send})->($hash->{IODev},"Reset",$hash->{addr});
    }

  } elsif($setting eq "wakeUp") {
    return MAX_WakeUp($hash);

  } elsif($setting eq "weekProfile" and $hash->{type} =~ /.*Thermostat.*/) {
    return "Number of arguments must be even" if(@args%2 == 1);

    #Send wakeUp, so we can send the weekprofile pakets without preamble
    #Disabled for now. Seems like the first packet is lost. Maybe inserting a delay after the wakeup will fix this
    #MAX_WakeUp($hash) if( @args > 2 );

    for(my $i = 0; $i < @args; $i += 2) {
      return "Expected day, got $args[$i]" if(!exists($decalcDaysInv{$args[$i]}));
      my $day = $decalcDaysInv{$args[$i]};
      my @controlpoints = split(',',$args[$i+1]);
      return "Not more than 13 control points are allowed!" if(@controlpoints > 13*2);
      my $newWeekprofilePart = "";
      for(my $j = 0; $j < 13*2; $j += 2) {
        if( $j >= @controlpoints ) {
          $newWeekprofilePart .= "4520";
          next;
        }
        my ($hour, $min);
        if($j + 1 == @controlpoints) {
          $hour = 0; $min = 0;
        } else {
          ($hour, $min) = ($controlpoints[$j+1] =~ /^(\d{1,2}):(\d{1,2})$/);
        }
        my $temperature = $controlpoints[$j];
        return "Invalid time: $controlpoints[$j+1]" if(!defined($hour) || !defined($min) || $hour > 23 || $min > 59);
        return "Invalid temperature" if(!validTemperature($temperature));
        $temperature = MAX_ParseTemperature($temperature); #replace "on" and "off" by their values
        $newWeekprofilePart .= sprintf("%04x", (int($temperature*2) << 9) | int(($hour * 60 + $min)/5));
      }
      Log GetLogLevel($hash->{NAME}, 5), "New Temperature part for $day: $newWeekprofilePart";
      #Each day has 2 bytes * 13 controlpoints = 26 bytes = 52 hex characters
      #we don't have to update the rest, because the active part is terminated by the time 0:00

      #First 7 controlpoints (2*7=14 bytes => 2*2*7=28 hex characters )
      ($hash->{IODev}{Send})->($hash->{IODev},"ConfigWeekProfile",$hash->{addr},
          sprintf("0%1d%s", $day, substr($newWeekprofilePart,0,2*2*7)),
          callbackParam => "$day,0,".substr($newWeekprofilePart,0,2*2*7));
      #And then the remaining 6
      ($hash->{IODev}{Send})->($hash->{IODev},"ConfigWeekProfile",$hash->{addr},
          sprintf("1%1d%s", $day, substr($newWeekprofilePart,2*2*7,2*2*6)),
          callbackParam => "$day,1,".substr($newWeekprofilePart,2*2*7,2*2*6))
            if(@controlpoints > 2*7);
    }
    Log GetLogLevel($hash->{NAME}, 5), "New weekProfile: " . MAX_ReadingsVal($hash, ".weekProfile");

  }else{
    my $templist = join(",",map { MAX_SerializeTemperature($_/2) }  (9..61));
    my $ret = "Unknown argument $setting, choose one of wakeUp factoryReset groupid";

    my $assoclist;
    #Build list of devices which this device can be associated to
    if($hash->{type} =~ /HeatingThermostat.*/) {
      $assoclist = join(",", map { defined($_->{type}) &&
        ($_->{type} eq "HeatingThermostat"
          || $_->{type} eq "HeatingThermostatPlus"
          || $_->{type} eq "WallMountedThermostat"
          || $_->{type} eq "ShutterContact")
        && $_ != $hash ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
      if($hash->{IODev}->{TYPE} eq "CUL_MAX") {
        $assoclist .= "," if(length($assoclist));
        $assoclist .= "fakeWallThermostat,fakeShutterContact";
      }

    } elsif($hash->{type} =~ /WallMountedThermostat/) {
      $assoclist = join(",", map { defined($_->{type}) &&
        ($_->{type} eq "HeatingThermostat"
          || $_->{type} eq "HeatingThermostatPlus"
          || $_->{type} eq "ShutterContact")
        && $_ != $hash ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
      if($hash->{IODev}->{TYPE} eq "CUL_MAX") {
        $assoclist .= "," if(length($assoclist));
        $assoclist .= "fakeShutterContact";
      }

    } elsif($hash->{type} eq "ShutterContact") {
      $assoclist = join(",", map { defined($_->{type}) && $_->{type} =~ /.*Thermostat.*/ ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
    }

    my $templistOffset = join(",",map { MAX_SerializeTemperature(($_-7)/2) }  (0..14));
    my $boostDurVal = join(",", values(%boost_durations));
    if($hash->{type} =~ /HeatingThermostat.*/) {
      my $shash;
      my $wallthermo = 0;
      # check if Wallthermo is in same group
      foreach my $addr ( keys %{$modules{MAX}{defptr}} ) {
        $shash = $modules{MAX}{defptr}{$addr};
        $wallthermo = 1 if(defined $shash->{type} && $shash->{type} eq "WallMountedThermostat" && (MAX_ReadingsVal($shash,"groupid") eq MAX_ReadingsVal($hash,"groupid")));
      }

      if ($wallthermo eq 1) {
        return "$ret associate:$assoclist deassociate:$assoclist desiredTemperature:eco,comfort,boost,auto,$templist measurementOffset:$templistOffset windowOpenDuration boostDuration:$boostDurVal boostValveposition decalcification maxValveSetting valveOffset";
      } else {
        return "$ret associate:$assoclist deassociate:$assoclist desiredTemperature:eco,comfort,boost,auto,$templist ecoTemperature:$templist comfortTemperature:$templist measurementOffset:$templistOffset maximumTemperature:$templist minimumTemperature:$templist windowOpenTemperature:$templist windowOpenDuration boostDuration:$boostDurVal boostValveposition decalcification maxValveSetting valveOffset";
      }
    } elsif($hash->{type} eq "WallMountedThermostat") {
      return "$ret associate:$assoclist deassociate:$assoclist displayActualTemperature:0,1 desiredTemperature:eco,comfort,boost,auto,$templist ecoTemperature:$templist comfortTemperature:$templist maximumTemperature:$templist minimumTemperature:$templist measurementOffset:$templistOffset windowOpenTemperature:$templist boostDuration:$boostDurVal boostValveposition ";
    } elsif($hash->{type} eq "ShutterContact") {
      return "$ret associate:$assoclist deassociate:$assoclist";
    } else {
      return $ret;
    }
  }
}

#############################
sub
MAX_ParseDateTime($$$)
{
  my ($byte1,$byte2,$byte3) = @_;
  my $day = $byte1 & 0x1F;
  my $month = (($byte1 & 0xE0) >> 4) | ($byte2 >> 7);
  my $year = $byte2 & 0x3F;
  my $time = ($byte3 & 0x3F);
  if($time%2){
    $time = int($time/2).":30";
  }else{
    $time = int($time/2).":00";
  }
  return { "day" => $day, "month" => $month, "year" => $year, "time" => $time, "str" => "$day.$month.$year $time" };
}

#############################
sub
MAX_Parse($$)
{
  my ($hash, $msg) = @_;
  my ($MAX,$isToMe,$msgtype,$addr,@args) = split(",",$msg);
  #$isToMe is 1 if the message was direct at the device $hash, and 0
  #if we just snooped a message directed at a different device (by CUL_MAX).
  return () if($MAX ne "MAX");

  Log 5, "MAX_Parse $msg";
  #Find the device with the given addr
  my $shash = $modules{MAX}{defptr}{$addr};

  if(!$shash)
  {
    my $devicetype = undef;
    $devicetype = $args[0] if($msgtype eq "define" and $args[0] ne "Cube");
    $devicetype = "ShutterContact" if($msgtype eq "ShutterContactState");
    $devicetype = "WallMountedThermostat" if(grep /^$msgtype$/, ("WallThermostatConfig","WallThermostatState","WallThermostatControl"));
    $devicetype = "HeatingThermostat" if(grep /^$msgtype$/, ("HeatingThermostatConfig", "ThermostatState"));
    if($devicetype) {
      return "UNDEFINED MAX_$addr MAX $devicetype $addr";
    } else {
      Log 2, "Got message for undefined device $addr, and failed to guess type from msg '$msgtype' - ignoring";
      return $hash->{NAME};
    }
  }

  #if $isToMe is true, then the message was directed at device $hash, thus we can also use it for sending
  if($isToMe) {
    $shash->{IODev} = $hash;
    $shash->{backend} = $hash->{NAME}; #for user information
  }

  readingsBeginUpdate($shash);
  if($msgtype eq "define"){
    my $devicetype = $args[0];
    Log 1, "Device changed type from $shash->{type} to $devicetype" if($shash->{type} ne $devicetype);
    $shash->{type} = $devicetype;
    if(@args > 1){
      my $serial = $args[1];
      Log 1, "Device changed serial from $shash->{serial} to $serial" if($shash->{serial} and ($shash->{serial} ne $serial));
      $shash->{serial} = $serial;
    }
    readingsBulkUpdate($shash, "groupid", $args[2]);
    $shash->{IODev} = $hash;

  } elsif($msgtype eq "ThermostatState") {

    my ($bits2,$valveposition,$desiredTemperature,$until1,$until2,$until3) = unpack("aCCCCC",pack("H*",$args[0]));
    my $mode = vec($bits2, 0, 2); #
    my $dstsetting = vec($bits2, 3, 1); #is automatically switching to DST activated
    my $langateway = vec($bits2, 4, 1); #??
    my $panel = vec($bits2, 5, 1); #1 if the heating thermostat is locked for manually setting the temperature at the device
    my $rferror = vec($bits2, 6, 1); #communication with link partner (what does that mean?)
    my $batterylow = vec($bits2, 7, 1); #1 if battery is low

    my $untilStr = defined($until3) ? MAX_ParseDateTime($until1,$until2,$until3)->{str} : "";
    my $measuredTemperature = defined($until2) ? ((($until1 &0x01)<<8) + $until2)/10 : 0;
    #If the control mode is not "temporary", the cube sends the current (measured) temperature
    $measuredTemperature = "" if($mode == 2 || $measuredTemperature == 0);
    $untilStr = "" if($mode != 2);

    $desiredTemperature = ($desiredTemperature&0x7F)/2.0; #convert to degree celcius
    Log GetLogLevel($shash->{NAME}, 5), "battery $batterylow, rferror $rferror, panel $panel, langateway $langateway, dstsetting $dstsetting, mode $mode, valveposition $valveposition %, desiredTemperature $desiredTemperature, until $untilStr, curTemp $measuredTemperature";

    #Very seldomly, the HeatingThermostat sends us temperatures like 0.2 or 0.3 degree Celcius - ignore them
    $measuredTemperature = "" if($measuredTemperature ne "" and $measuredTemperature < 1);

    my $measOffset = MAX_ReadingsVal($shash,"measurementOffset");
    $measuredTemperature -= $measOffset if($measuredTemperature ne "" and $measOffset ne "" and $shash->{type} =~ /HeatingThermostatPlus/ and $hash->{TYPE} eq "MAXLAN");

    $shash->{mode} = $mode;
    $shash->{rferror} = $rferror;
    $shash->{dstsetting} = $dstsetting;
    if($mode == 2){
      $shash->{until} = "$untilStr";
    }else{
      delete($shash->{until});
    }

    readingsBulkUpdate($shash, "mode", $ctrl_modes[$mode] );
    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    #The formatting of desiredTemperature must match with in MAX_Set:$templist
    #Sometime we get an MAX_Parse MAX,1,ThermostatState,01090d,180000000000, where desiredTemperature is 0 - ignore it
    readingsBulkUpdate($shash, "desiredTemperature", MAX_SerializeTemperature($desiredTemperature)) if($desiredTemperature != 0);
    if($measuredTemperature ne "") {
      readingsBulkUpdate($shash, "temperature", MAX_SerializeTemperature($measuredTemperature));
   }
    if($shash->{type} =~ /HeatingThermostatPlus/ and $hash->{TYPE} eq "MAXLAN") {
      readingsBulkUpdate($shash, "valveposition", int($valveposition*MAX_ReadingsVal($shash,"maxValveSetting")/100));
    } else {
      readingsBulkUpdate($shash, "valveposition", $valveposition);
    }

  }elsif(grep /^$msgtype$/,  ("WallThermostatState", "WallThermostatControl" )){
    my ($bits2,$displayActualTemperature,$desiredTemperatureRaw,$null1,$heaterTemperature,$null2,$temperature);
    if( length($args[0]) == 4 ) { #WallThermostatControl
      #This is the message that WallMountedThermostats send to paired HeatingThermostats
      ($desiredTemperatureRaw,$temperature) = unpack("CC",pack("H*",$args[0]));
    } elsif( length($args[0]) >= 6 and length($args[0]) <= 14) { #WallThermostatState
      #len=14: This is the message we get from the Cube over MAXLAN and which is probably send by WallMountedThermostats to the Cube
      #len=12: Payload of an Ack message, last field "temperature" is missing
      #len=10: Received by MAX_CUL as WallThermostatState
      #len=6 : Payload of an Ack message, last four fields (especially $heaterTemperature and $temperature) are missing
      ($bits2,$displayActualTemperature,$desiredTemperatureRaw,$null1,$heaterTemperature,$null2,$temperature) = unpack("aCCCCCC",pack("H*",$args[0]));
      #$heaterTemperature/10 is the temperature measured by a paired HeatingThermostat
      #we don't do anything with it here, because this value also appears as temperature in the HeatingThermostat's ThermostatState message
      my $mode = vec($bits2, 0, 2); #
      my $dstsetting = vec($bits2, 3, 1); #is automatically switching to DST activated
      my $langateway = vec($bits2, 4, 1); #??
      my $panel = vec($bits2, 5, 1); #1 if the heating thermostat is locked for manually setting the temperature at the device
      my $rferror = vec($bits2, 6, 1); #communication with link partner (what does that mean?)
      my $batterylow = vec($bits2, 7, 1); #1 if battery is low

      my $untilStr = "";
      if(defined($null2) and ($null1 != 0 or $null2 != 0)) {
        $untilStr = MAX_ParseDateTime($null1,$heaterTemperature,$null2)->{str};
        $heaterTemperature = "";
      }
      $heaterTemperature = "" if(!defined($heaterTemperature));

      Log GetLogLevel($shash->{NAME}, 5), "battery $batterylow, rferror $rferror, panel $panel, langateway $langateway, dstsetting $dstsetting, mode $mode, displayActualTemperature $displayActualTemperature, heaterTemperature $heaterTemperature, untilStr $untilStr";
      $shash->{rferror} = $rferror;
      readingsBulkUpdate($shash, "mode", $ctrl_modes[$mode] );
      readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
      readingsBulkUpdate($shash, "displayActualTemperature", ($displayActualTemperature) ? 1 : 0);
    } else {
      Log 2, "Invalid $msgtype packet"
    }

    my $desiredTemperature = ($desiredTemperatureRaw &0x7F)/2.0; #convert to degree celcius
    if(defined($temperature)) {
      $temperature = ((($desiredTemperatureRaw &0x80)<<1) + $temperature)/10;	# auch Temperaturen über 25.5 °C werden angezeigt !
      Log GetLogLevel($shash->{NAME}, 5), "desiredTemperature $desiredTemperature, temperature $temperature";
      readingsBulkUpdate($shash, "temperature", sprintf("%2.1f",$temperature));
    } else {
      Log GetLogLevel($shash->{NAME}, 5), "desiredTemperature $desiredTemperature"
    }

    #This formatting must match with in MAX_Set:$templist
    readingsBulkUpdate($shash, "desiredTemperature", MAX_SerializeTemperature($desiredTemperature));

  }elsif($msgtype eq "ShutterContactState"){
    my $bits = pack("H2",$args[0]);
    my $isopen = vec($bits,0,2) == 0 ? 0 : 1;
    my $unkbits = vec($bits,2,4);
    my $rferror = vec($bits,6,1);
    my $batterylow = vec($bits,7,1);
    Log GetLogLevel($shash->{NAME}, 5), "ShutterContact isopen $isopen, rferror $rferror, battery $batterylow, unkbits $unkbits";

    $shash->{rferror} = $rferror;

    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    readingsBulkUpdate($shash,"onoff",$isopen);

  }elsif($msgtype eq "PushButtonState") {
    my ($bits2, $onoff) = unpack("aC",pack("H*",$args[0]));
    #The meaning of $bits2 is completly guessed based on similarity to other devices, TODO: confirm
    my $gateway = vec($bits2, 4, 1); #Paired to a CUBE?
    my $rferror = vec($bits2, 6, 1); #communication with link partner (1 if we did not sent an Ack)
    my $batterylow = vec($bits2, 7, 1); #1 if battery is low

    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    readingsBulkUpdate($shash, "onoff", $onoff);
    readingsBulkUpdate($shash, "connection", $gateway);

  } elsif(grep /^$msgtype$/, ("HeatingThermostatConfig", "WallThermostatConfig")) {
    readingsBulkUpdate($shash, "ecoTemperature", MAX_SerializeTemperature($args[0]));
    readingsBulkUpdate($shash, "comfortTemperature", MAX_SerializeTemperature($args[1]));
    readingsBulkUpdate($shash, "maximumTemperature", MAX_SerializeTemperature($args[2]));
    readingsBulkUpdate($shash, "minimumTemperature", MAX_SerializeTemperature($args[3]));
    readingsBulkUpdate($shash, ".weekProfile", $args[4]);
    if(@args > 5) { #HeatingThermostat and WallThermostat with new firmware
      readingsBulkUpdate($shash, "boostValveposition", $args[5]);
      readingsBulkUpdate($shash, "boostDuration", $boost_durations{$args[6]});
      readingsBulkUpdate($shash, "measurementOffset", MAX_SerializeTemperature($args[7]));
      readingsBulkUpdate($shash, "windowOpenTemperature", MAX_SerializeTemperature($args[8]));
    }
    if(@args > 9) { #HeatingThermostat
      readingsBulkUpdate($shash, "windowOpenDuration", $args[9]);
      readingsBulkUpdate($shash, "maxValveSetting", $args[10]);
      readingsBulkUpdate($shash, "valveOffset", $args[11]);
      readingsBulkUpdate($shash, "decalcification", "$decalcDays{$args[12]} $args[13]:00");
    }

    MAX_ParseWeekProfile($shash);

  } elsif($msgtype eq "Error") {
    if(@args == 0) {
      delete $shash->{ERROR} if(exists($shash->{ERROR}));
    } else {
      $shash->{ERROR} = join(",",@args);
    }

  } elsif($msgtype eq "AckWakeUp") {
    my ($duration) = @args;
    #substract five seconds safety margin
    $shash->{wakeUpUntil} = gettimeofday() + $duration - 5;

  } elsif($msgtype eq "AckConfigWeekProfile") {
    my ($day, $part, $profile) = @args;

    my $curWeekProfile = MAX_ReadingsVal($shash, ".weekProfile");
    substr($curWeekProfile, $day*52+$part*2*2*7, length($profile)) = $profile;
    readingsBulkUpdate($shash, ".weekProfile", $curWeekProfile);
    MAX_ParseWeekProfile($shash);

  } elsif(grep /^$msgtype$/, ("AckConfigValve", "AckConfigTemperatures", "AckSetDisplayActualTemperature" )) {

    if($args[0] eq "windowOpenTemperature"
    || $args[0] eq "comfortTemperature"
    || $args[0] eq "ecoTemperature"
    || $args[0] eq "maximumTemperature"
    || $args[0] eq "minimumTemperature" ) {
      readingsBulkUpdate($shash, $args[0], MAX_SerializeTemperature($args[1]));
    } else {
      #displayActualTemperature, boostDuration, boostValveSetting, maxValve, decalcification, valveOffset
      readingsBulkUpdate($shash, $args[0], $args[1]);
    }

  } elsif(grep /^$msgtype$/, ("AckSetGroupId", "AckRemoveGroupId" )) {

    readingsBulkUpdate($shash, "groupid", $args[0]);

  } elsif($msgtype eq "Ack") {
    #The payload of an Ack is a 2-digit hex number (being "01" for okey and "81" for "invalid command/argument"
    if($isToMe and (unpack("C",pack("H*",$args[0])) & 0x80)) {
      my $device = $addr;
      $device = $modules{MAX}{defptr}{$device}{NAME} if(exists($modules{MAX}{defptr}{$device}));
      Log 1, "Device $device answered with: Invalid command/argument";
    }
    #with unknown meaning plus the data of a State broadcast from the same device
    #For HeatingThermostats, it does not contain the last three "until" bytes (or measured temperature)
    if($shash->{type} =~ /HeatingThermostat.*/ ) {
      return MAX_Parse($hash, "MAX,$isToMe,ThermostatState,$addr,". substr($args[0],2));
    } elsif($shash->{type} eq "WallMountedThermostat") {
      return MAX_Parse($hash, "MAX,$isToMe,WallThermostatState,$addr,". substr($args[0],2));
    } elsif($shash->{type} eq "ShutterContact") {
      return MAX_Parse($hash, "MAX,$isToMe,ShutterContactState,$addr,". substr($args[0],2));
    } elsif($shash->{type} eq "PushButton") {
      return MAX_Parse($hash, "MAX,$isToMe,PushButtonState,$addr,". substr($args[0],2));
    } elsif($shash->{type} eq "Cube") {
      ; #Payload is always "00"
    } else {
      Log 2, "MAX_Parse: Don't know how to interpret Ack payload for $shash->{type}";
    }

  } else {
    Log 1, "MAX_Parse: Unknown message $msgtype";
  }

  #Build state READING
  my $state = "waiting for data";
  if(exists($shash->{READINGS})) {
    $state = $shash->{READINGS}{connection}{VAL} ? "connected" : "not connected" if(exists($shash->{READINGS}{connection}));
    $state = "$shash->{READINGS}{desiredTemperature}{VAL} °C" if(exists($shash->{READINGS}{desiredTemperature}));
    $state = $shash->{READINGS}{onoff}{VAL} ? "opened" : "closed" if(exists($shash->{READINGS}{onoff}));
  }

  $state .= " (clock not set)" if($shash->{clocknotset});
  $state .= " (auto)" if(exists($shash->{mode}) and $shash->{mode} eq "auto");
  #Don't print this: it's the standard mode
  #$state .= " (manual)" if(exists($shash->{mode}) and  $shash->{mode} eq "manual");
  $state .= " (until ".$shash->{until}.")" if(exists($shash->{mode}) and $shash->{mode} eq "temporary" );
  $state .= " (battery low)" if($shash->{batterylow});
  $state .= " (rf error)" if($shash->{rferror});

  readingsBulkUpdate($shash, "state", $state);
  readingsEndUpdate($shash, 1);
  return $shash->{NAME}
}

1;

=pod
=begin html

<a name="MAX"></a>
<h3>MAX</h3>
<ul>
  Devices from the eQ-3 MAX! group.<br>
  When heating thermostats show a temperature of zero degrees, they didn't yet send any data to the cube. You can
  force the device to send data to the cube by physically setting a temperature directly at the device (not through fhem).
  <br><br>
  <a name="MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAX &lt;type&gt; &lt;addr&gt;</code>
    <br><br>

    Define an MAX device of type &lt;type&gt; and rf address &lt;addr&gt.
    The &lt;type&gt; is one of HeatingThermostat, HeatingThermostatPlus, WallMountedThermostat, ShutterContact, PushButton.
    The &lt;addr&gt; is a 6 digit hex number.
    You should never need to specify this by yourself, the <a href="#autocreate">autocreate</a> module will do it for you.<br>
    It's advisable to set event-on-change-reading, like
    <code>attr MAX_123456 event-on-change-reading .*</code>
    because the polling mechanism will otherwise create events every 10 seconds.<br>

    Example:
    <ul>
      <code>define switch1 MAX PushButton ffc545</code><br>
    </ul>
  </ul>
  <br>

  <a name="MAXset"></a>
  <b>Set</b>
  <ul>
    <li>desiredTemperature &lt;value&gt; [until &lt;date&gt;]<br>
        For devices of type HeatingThermostat only. &lt;value&gt; maybe one of
        <ul>
          <li>degree celcius between 3.5 and 30.5 in 0.5 degree steps</li>
          <li>"on" or "off" set the thermostat to full or no heating, respectively</li>
          <li>"eco" or "comfort" using the eco/comfort temperature set on the device (just as the right-most physical button on the device itself does)</li>
          <li>"auto &lt;temperature&gt;". The weekly program saved on the thermostat is processed. If the optional &lt;temperature&gt; is given, it is set as desiredTemperature until the next switch point of the weekly program.</li>
          <li>"boost", activates the boost mode, where for boostDuration minutes the valve is opened up boostValveposition percent.</li>
        </ul>
        All values but "auto" maybe accompanied by the "until" clause, with &lt;data&gt; in format "dd.mm.yyyy HH:MM" (minutes may only be "30" or "00"!)
        to set a temporary temperature until that date/time. Make sure that the cube/device has a correct system time.</li>
    <li>groupid &lt;id&gt;<br>
      For devices of type HeatingThermostat only.
      Writes the given group id the device's memory. To sync all devices in one room, set them to the same groupid greater than zero.</li>
    <li>ecoTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given eco temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <li>comfortTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given comfort temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <li>measurementOffset &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given temperature offset to the device's memory. If the internal temperature sensor is not well calibrated, it may produce a systematic error. Using measurementOffset, this error can be compensated. The reading temperature is equal to the measured temperature at sensor + measurementOffset. Usually, the internally measured temperature is a bit higher than the overall room temperature (due to closeness to the heater), so one uses a small negative offset. Must be between -3.5 and 3.5 degree celsius.</li>
    <li>minimumTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given minimum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>maximumTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given maximum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>windowOpenTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open temperature to the device's memory. That is the temperature the heater will temporarily set if an open window is detected. Setting it to 4.5 degree or "off" will turn off reacting on open windows.</li>
    <li>windowOpenDuration &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open duration to the device's memory. That is the duration the heater will temporarily set the window open temperature if an open window is detected by a rapid temperature decrease. (Not used if open window is detected by ShutterControl. Must be between 0 and 60 minutes in multiples of 5.</li>
    <li>decalcification &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given decalcification time to the device's memory. Value must be of format "Sat 12:00" with minutes being "00". Once per week during that time, the HeatingThermostat will open the valves shortly for decalcification.</li>
    <li>boostDuration &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given boost duration to the device's memory. Value must be one of 5, 10, 15, 20, 25, 30, 60. It is the duration of the boost function in minutes.</li>
    <li>boostValveposition &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given boost valveposition to the device's memory. It is the valve position in percent during the boost function.</li>
    <li>maxValveSetting &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given maximum valveposition to the device's memory. The heating thermostat will not open the valve more than this value (in percent).</li>
    <li>valveOffset &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given valve offset to the device's memory. The heating thermostat will add this to all computed valvepositions during control.</li>
    <li>factoryReset<br>
        Resets the device to factory values. It has to be paired again afterwards.<br>
        ATTENTION: When using this on a ShutterContact using the MAXLAN backend, the ShutterContact has to be triggered once manually to complete
        the factoryReset.</li>
    <li>associate &lt;value&gt;<br>
        Associated one device to another. &lt;value&gt; can be the name of MAX device or its 6-digit hex address.<br>
        Associating a ShutterContact to a {Heating,WallMounted}Thermostat makes it send message to that device to automatically lower temperature to windowOpenTemperature while the shutter is opened. The thermostat must be associated to the ShutterContact, too, to accept those messages.
        <b>!Attention: After sending this associate command to the ShutterContact, you have to press the button on the ShutterContact to wake it up and accept the command. See the log for a message regarding this!</b>
        Associating HeatingThermostat and WallMountedThermostat makes them sync their desiredTemperature and uses the measured temperature of the
 WallMountedThermostat for control.</li>
    <li>deassociate &lt;value&gt;<br>
        Removes the association set by associate.</li>
    <li>weekProfile [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] ...<br>
      Allows setting the week profile. For devices of type HeatingThermostat or WallMountedThermostat only. Example:<br>
      <code>set MAX_12345 weekProfile Fri 24.5,6:00,12,15:00,5 Sat 7,4:30,19,12:55,6</code><br>
      sets the profile <br>
      <code>Friday: 24.5 &deg;C for 0:00 - 6:00, 12 &deg;C for 6:00 - 15:00, 5 &deg;C for 15:00 - 0:00<br>
      Saturday: 7 &deg;C for 0:00 - 4:30, 19 &deg;C for 4:30 - 12:55, 6 &deg;C for 12:55 - 0:00</code><br>
      while keeping the old profile for all other days.
    </li>
  </ul>
  <br>

  <a name="MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>keepAuto<br>Default: 0. If set to 1, it will stay in the auto mode when you set a desiredTemperature while the auto (=weekly program) mode is active.</li>
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>desiredTemperature<br>Only for HeatingThermostat and WallMountedThermostat</li>
    <li>valveposition<br>Only for HeatingThermostat</li>
    <li>battery</li>
    <li>temperature<br>The measured temperature (= measured temperature at sensor + measurementOffset), only for HeatingThermostat and WallMountedThermostat</li>
  </ul>
</ul>

=end html
=cut
