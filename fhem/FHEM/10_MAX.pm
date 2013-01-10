##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;
use MIME::Base64;

sub MAX_Define($$);
sub MAX_Undef($$);
sub MAX_Initialize($);
sub MAX_Parse($$);
sub MAX_Set($@);
sub MAX_MD15Cmd($$$);
sub MAX_DateTime2Internal($);

my @ctrl_modes = ( "auto", "manual", "temporary", "boost" );

use vars qw(%device_types);
use vars qw(%msgId2Cmd);
use vars qw(%msgCmd2Id);

%device_types = (
  0 => "Cube",
  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton"
);

my %readingDef = ( #min/max/default
  "maximumTemperature"    => [4.5, 30.5, 30.5],
  "minimumTemperature"    => [4.5, 30.5, 4.5],
  "comfortTemperature"    => [4.5, 30.5, 21],
  "ecoTemperature"        => [4.5, 30.5, 17],
  "windowOpenTemperature" => [4.5, 30.5, 12],
  "windowOpenDuration"    => [0,   60,   15],
  "measurementOffset"     => [-3.5, 3.5, 0]
);

%msgId2Cmd = (
                 "00" => "PairPing",
                 "01" => "PairPong",
                 "02" => "Ack",
                 "03" => "TimeInformation",
                 "10" => "ConfigWeekProfile",
                 "11" => "ConfigTemperatures", #like boost/eco/comfort etc
                 "30" => "ShutterContactState",
                 "42" => "WallThermostatState", #by WallMountedThermostat
                 "50" => "PushButtonState",
                 "60" => "ThermostatState", #by HeatingThermostat
                 "40" => "SetTemperature", #to thermostat
                 "20" => "AddLinkPartner",
                 "21" => "RemoveLinkPartner",
                 "22" => "SetGroupId",
                 "23" => "RemoveGroupId",
                 "F1" => "WakeUp",
                 "F0" => "Reset",
               );
%msgCmd2Id = reverse %msgId2Cmd;

my @decalcDays = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");

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

  Log 5, "Calling MAX_Initialize";
  $hash->{Match}     = "^MAX";
  $hash->{DefFn}     = "MAX_Define";
  $hash->{UndefFn}   = "MAX_Undef";
  $hash->{ParseFn}   = "MAX_Parse";
  $hash->{SetFn}     = "MAX_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
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
  return "wrong syntax: define <name> MAX addr"
        if(int(@a)!=4 || $a[3] !~ m/^[A-F0-9]{6}$/i);

  my $type = $a[2];
  my $addr = lc($a[3]); #all addr should be lowercase
  if(exists($modules{MAX}{defptr}{$addr})) {
    my $msg = "MAX_Define: Device with addr $addr is already defined";
    Log 1, $msg;
    return $msg;
  }
  Log 5, "Max_define $type with addr $addr ";
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

sub
MAX_ReadingsVal(@)
{
  my ($hash,$name) = @_;

  my $val = ReadingsVal($hash->{NAME},$name,"");
  #$readingDef{$name} array is [min, max, default]
  if(exists($readingDef{$name}) and
    ($val eq "" or $val !~ /^-?(\d+\.?\d*|\.\d+)$/ or $val < $readingDef{$name}[0] or $val > $readingDef{$name}[1])) {
    #Error: invalid value
    Log 2, "MAX: Invalid value $val for READING $name. Forcing to $readingDef{$name}[2]";
    $val = $readingDef{$name}[2];
    readingsSingleUpdate($hash,$name,$val,0);
  }
  return $val;
}

#############################
sub
MAX_Set($@)
{
  my ($hash, $devname, @a) = @_;
  my ($setting, @args) = @a;

  return "Invalid IODev" if(MAX_CheckIODev($hash));

  if($setting eq "desiredTemperature" and ($hash->{type} eq "HeatingThermostat" or $hash->{type} eq "WallMountedThermostat")) {
    return "missing a value" if(@args == 0);

    my $temperature;
    my $until = undef;
    my $ctrlmode = 1; #0=auto, 1=manual; 2=temporary

    if($args[0] eq "auto") {
      #This enables the automatic/schedule mode where the thermostat follows the weekly program
      $temperature = 0;
      $ctrlmode = 0; #auto
    } elsif($args[0] eq "boost") {
      $temperature = 0;
      $ctrlmode = 3;
      #TODO: auto mode with temperature is also possible
    } elsif($args[0] eq "eco") {
      $temperature = MAX_ReadingsVal($hash,"ecoTemperature");
      return "No ecoTemperature defined" if(!$temperature);
    } elsif($args[0] eq "comfort") {
      $temperature = MAX_ReadingsVal($hash,"comfortTemperature");
      return "No comfortTemperature defined" if(!$temperature);
    } elsif($args[0] eq "on") {
      $temperature = 30.5;
    } elsif($args[0] eq "off") {
      $temperature = 4.5;
    }else{
      $temperature = $args[0];
    }

    if(@args > 1 and ($args[1] eq "until") and ($ctrlmode == 1)) {
      $ctrlmode = 2; #temporary
      $until = sprintf("%06x",MAX_DateTime2Internal($args[2]." ".$args[3]));
    }

    my $groupid = $hash->{groupid};
    $groupid = 0; #comment this line to control the whole group, no only one device

    $temperature = int($temperature*2.0) | ($ctrlmode << 6); #convert to internal representation
    my $payload;
    if(defined($until)) {
      $payload = pack("CCCCCCH6CCH6",0x00,$groupid?0x04:0,0x40,0x00,0x00,0x00,$hash->{addr},$groupid,$temperature,$until);
    }else{
      $payload = pack("CCCCCCH6CC"  ,0x00,$groupid?0x04:0,0x40,0x00,0x00,0x00,$hash->{addr},$groupid,$temperature);
    }
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);

  }elsif($setting eq "groupid"){
    return "argument needed" if(@args == 0);

    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},pack("CCCCCCH6CC",0x00,0x00,0x22,0x00,0x00,0x00,$hash->{addr},0x00,$args[0]));

  }elsif( $setting ~~ ["ecoTemperature", "comfortTemperature", "measurementOffset", "maximumTemperature", "minimumTemperature", "windowOpenTemperature", "windowOpenDuration" ] and ($hash->{type} eq "HeatingThermostat" or $hash->{type} eq "WallMountedThermostat")) {
    return "Cannot set without IODev" if(!exists($hash->{IODev}));

    my $comfortTemperature = MAX_ReadingsVal($hash,"comfortTemperature");
    my $ecoTemperature = MAX_ReadingsVal($hash,"ecoTemperature");
    my $maximumTemperature = MAX_ReadingsVal($hash,"maximumTemperature");
    my $minimumTemperature = MAX_ReadingsVal($hash,"minimumTemperature");
    my $windowOpenTemperature = MAX_ReadingsVal($hash,"windowOpenTemperature");
    my $windowOpenDuration = MAX_ReadingsVal($hash,"windowOpenDuration");
    my $measurementOffset = MAX_ReadingsVal($hash,"measurementOffset");

    readingsSingleUpdate($hash, $setting, $args[0], 0);

    my $comfort = int($comfortTemperature*2);
    my $eco = int($ecoTemperature*2);
    my $max = int($maximumTemperature*2);
    my $min = int($minimumTemperature*2);
    my $offset = int(($measurementOffset + 3.5)*2);
    my $windowOpenTemp = int($windowOpenTemperature*2);
    my $windowOpenTime = int($windowOpenDuration/5);

    my $payload = pack("CCCCCCH6C"."CCCCCCC",0x00,0x00,0x11,0x00,0x00,0x00,$hash->{addr},0x00,
                                              $comfort,$eco,$max,$min,$offset,$windowOpenTemp,$windowOpenTime);
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);

  } elsif($setting eq "displayActualTemperature" and $hash->{type} eq "WallMountedThermostat") {
    return "Invalid arg" if($args[0] ne "0" and $args[0] ne "1");

    readingsSingleUpdate($hash, $setting, $args[0], 0);
    my $payload = pack("CCCCCCH6CC",0x00,0x00,0x82,0x00,0x00,0x00,$hash->{addr},0x00, $args[0] ? 4 : 0);
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);

  } elsif($setting eq "associate") {
    my $dest = $args[0];
    if(exists($defs{$dest})) {
      return "Destination is not a MAX device" if($defs{$dest}{TYPE} ne "MAX");
      #return "Destination is not a thermostat" if($defs{$dest}{type} ne "HeatingThermostat" and $defs{$dest}{type} ne "WallMountedThermostat");
      $dest = $defs{$dest}{addr};
    } else {
      return "No MAX device with address $dest" if(!exists($modules{MAX}{defptr}{$dest}));
    }
    my $destType = MAX_TypeToTypeId($modules{MAX}{defptr}{$dest}{type});
    Log 2, "Warning: Device do not have same groupid" if($hash->{groupid} != $modules{MAX}{defptr}{groupid});
    Log 5, "Using dest $dest, destType $destType";
    my $payload = pack("CCCCCCH6CH6C",0x00,0x00,0x20,0x00,0x00,0x00,$hash->{addr}, $hash->{groupid}, $dest, $destType);
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);

  } elsif($setting eq "factoryReset") {

    if(exists($hash->{IODev}{RemoveDevice})) {
      #MAXLAN
      return ($hash->{IODev}{RemoveDevice})->($hash->{IODev},$hash->{addr});
    } else {
      #CUL_MAX
      my $payload = pack("CCCCCCH6C",0x00,0x00,0xF0,0x00,0x00,0x00,$hash->{addr}, 0);
      return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);
    }

  } elsif($setting eq "wakeUp") {
    my $payload = pack("CCCCCCH6CC",0x00,0x00,0xF1,0x00,0x00,0x00,$hash->{addr}, 0, 0x3F);
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);

  }else{
    my $templist = join(",",map { sprintf("%2.1f",$_/2) }  (9..61));
    my $ret = "Unknown argument $setting, choose one of wakeUp factoryReset groupid";

    my $assoclist;
    #Build list of devices which this device can be associated to
    if($hash->{type} eq "HeatingThermostat") {
      $assoclist = join(",", map { defined($_->{type}) && $_->{type} ~~ ["HeatingThermostat", "WallMountedThermostat", "ShutterContact"] ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
    } elsif($hash->{type} ~~ ["ShutterContact", "WallMountedThermostat"]) {
      $assoclist = join(",", map { defined($_->{type}) && $_->{type} eq "HeatingThermostat" ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
    }

    if($hash->{type} eq "HeatingThermostat") {
      #Create numbers from 4.5 to 30.5
      my $templistOffset = join(",",map { sprintf("%2.1f",($_-7)/2) }  (0..14));
      return "$ret associate:$assoclist desiredTemperature:eco,comfort,boost,auto,$templist ecoTemperature:$templist comfortTemperature:$templist measurementOffset:$templistOffset maximumTemperature:$templist minimumTemperature:$templist windowOpenTemperature:$templist windowOpenDuration";

    } elsif($hash->{type} eq "WallMountedThermostat") {
      return "$ret associate:$assoclist displayActualTemperature:0,1 desiredTemperature:eco,comfort,boost,auto,$templist ecoTemperature:$templist comfortTemperature:$templist maximumTemperature:$templist";
    } elsif($hash->{type} eq "ShutterContact") {
      return "$ret associate:$assoclist";
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
  return if($MAX ne "MAX");

  Log 5, "MAX_Parse $msg";
  #Find the device with the given addr
  my $shash = $modules{MAX}{defptr}{$addr};

  if(!$shash)
  {
    my $devicetype = undef;
    $devicetype = $args[0] if($msgtype eq "define");
    $devicetype = "ShutterContact" if($msgtype eq "ShutterContactState");
    $devicetype = "Cube" if($msgtype eq "CubeClockState" or $msgtype eq "CubeConnectionState");
    if($devicetype) {
      return "UNDEFINED MAX_$addr MAX $devicetype $addr";
    } else {
      Log 2, "Got message for undefined device, and failed to guess type from msg '$msgtype' - ignoring";
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
    if(@args > 1){
      my $serial = $args[1];
      Log 1, "Device changed serial from $shash->{serial} to $serial" if($shash->{serial} and ($shash->{serial} ne $serial));
      $shash->{serial} = $serial;
    }
    $shash->{groupid} = $args[2];
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
    my $measuredTemperature = defined($until2) ? $until2/10 : 0;
    #If the control mode is not "temporary", the cube sends the current (measured) temperature
    $measuredTemperature = "" if($mode == 2 || $measuredTemperature == 0);
    $untilStr = "" if($mode != 2);

    $desiredTemperature = $desiredTemperature/2.0; #convert to degree celcius
    Log 5, "battery $batterylow, rferror $rferror, panel $panel, langateway $langateway, dstsetting $dstsetting, mode $mode, valveposition $valveposition %, desiredTemperature $desiredTemperature, until $untilStr, curTemp $measuredTemperature";

    #Very seldomly, the HeatingThermostat sends us temperatures like 0.2 or 0.3 degree Celcius - ignore them
    $measuredTemperature = "" if($measuredTemperature ne "" and $measuredTemperature < 1);

    #The HeatingThermostat uses the measurementOffset during control
    #but does not apply it to measuredTemperature before sending it to us (guessed)
    my $measOffset = MAX_ReadingsVal($shash,"measurementOffset");
    $measuredTemperature -= $measOffset if($measuredTemperature ne "" and $measOffset ne "");

    $shash->{mode} = $mode;
    $shash->{rferror} = $rferror;
    $shash->{dstsetting} = $dstsetting;
    if($mode eq "temporary"){
      $shash->{until} = "$untilStr";
    }else{
      delete($shash->{until});
    }

    readingsBulkUpdate($shash, "mode", $ctrl_modes[$mode] );
    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    #This formatting must match with in MAX_Set:$templist
    readingsBulkUpdate($shash, "desiredTemperature", sprintf("%2.1f",$desiredTemperature));
    readingsBulkUpdate($shash, "valveposition", $valveposition);
    if($measuredTemperature ne "") {
      readingsBulkUpdate($shash, "temperature", $measuredTemperature);
    }

  }elsif($msgtype eq "WallThermostatState"){
    my ($bits2,$valveposition,$desiredTemperature,$null1,$unk,$null2,$temperature) = unpack("aCCCCCC",pack("H*",$args[0]));
    my $mode = vec($bits2, 0, 2); #
    my $dstsetting = vec($bits2, 3, 1); #is automatically switching to DST activated
    my $langateway = vec($bits2, 4, 1); #??
    my $panel = vec($bits2, 5, 1); #1 if the heating thermostat is locked for manually setting the temperature at the device
    my $rferror = vec($bits2, 6, 1); #communication with link partner (what does that mean?)
    my $batterylow = vec($bits2, 7, 1); #1 if battery is low

    $desiredTemperature = $desiredTemperature/2.0; #convert to degree celcius
    Log 2, "Warning: WallThermostatState null1: $null1 null2: $null2 should be both zero" if($null1 != 0 || $null2 != 0);

    Log 5, "battery $batterylow, rferror $rferror, panel $panel, langateway $langateway, dstsetting $dstsetting, mode $mode, valveposition $valveposition %, desiredTemperature $desiredTemperature, unknown: $unk, temperature $temperature";

    $shash->{rferror} = $rferror;
    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    #This formatting must match with in MAX_Set:$templist
    readingsBulkUpdate($shash, "desiredTemperature", sprintf("%2.1f",$desiredTemperature));
    readingsBulkUpdate($shash, "valveposition", $valveposition);
    readingsBulkUpdate($shash, "temperature", $temperature);
    readingsBulkUpdate($shash, "displayActualTemperature", ($valveposition & 0x0C) ? 1 : 0);

  }elsif($msgtype eq "ShutterContactState"){
    my $bits = pack("H2",$args[0]);
    my $isopen = vec($bits,0,2) == 0 ? 0 : 1;
    my $unkbits = vec($bits,2,4);
    my $rferror = vec($bits,6,1);
    my $batterylow = vec($bits,7,1);
    Log 5, "ShutterContact isopen $isopen, rferror $rferror, battery $batterylow, unkbits $unkbits";

    $shash->{rferror} = $rferror;

    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    readingsBulkUpdate($shash,"onoff",$isopen);

  }elsif($msgtype eq "PushButtonState") {
    my ($bits2, $onoff) = unpack("CC",pack("H*",$args[0]));
    #The meaning of $bits2 is completly guessed based on similarity to other devices, TODO: confirm
    my $rferror = vec($bits2, 6, 1); #communication with link partner (what does that mean?)
    my $batterylow = vec($bits2, 7, 1); #1 if battery is low

    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    readingsBulkUpdate($shash,"onoff",$onoff);

  }elsif($msgtype eq "CubeClockState"){
    my $clockset = $args[0];
    $shash->{clocknotset} = !$clockset;

  }elsif($msgtype eq "CubeConnectionState"){
    my $connected = $args[0];

    readingsBulkUpdate($shash, "connection", $connected);

  } elsif($msgtype ~~ ["HeatingThermostatConfig", "WallThermostatConfig"]) {
    readingsBulkUpdate($shash, "ecoTemperature", $args[0]);
    readingsBulkUpdate($shash, "comfortTemperature", $args[1]);
    readingsBulkUpdate($shash, "maximumTemperature", $args[2]);
    readingsBulkUpdate($shash, "minimumTemperature", $args[3]);
    if($shash->{type} eq "HeatingThermostat") {
      readingsBulkUpdate($shash, "boostValveposition", $args[4]);
      readingsBulkUpdate($shash, "boostDuration", $args[5]);
      readingsBulkUpdate($shash, "measurementOffset", $args[6]);
      readingsBulkUpdate($shash, "windowOpenTemperature", $args[7]);
      readingsBulkUpdate($shash, "windowOpenDuration", $args[8]);
      readingsBulkUpdate($shash, "maxValveSetting", $args[9]);
      readingsBulkUpdate($shash, "valveOffset", $args[10]);
      readingsBulkUpdate($shash, "decalcification", "$decalcDays[$args[11]], $args[12]:00");
      $shash->{internal}{weekProfile} = $args[13];
    } else {
      $shash->{internal}{weekProfile} = $args[4];
    }

    #parse weekprofiles for each day
    for (my $i=0;$i<7;$i++) {
      my (@time_prof, @temp_prof);
      for(my $j=0;$j<13;$j++) {
        @time_prof[$j] = (hex(substr($shash->{internal}{weekProfile},($i*52)+ 4*$j,4))& 0x1FF) * 5;
        @temp_prof[$j] = (hex(substr($shash->{internal}{weekProfile},($i*52)+ 4*$j,4))>> 9 & 0x3F ) / 2;
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
        $temp_prof_str .= $temp_prof[$k];
        if ($k < $j) {
          $time_prof_str .= "  /  " . sprintf("%02d:%02d", $hours[$k], $minutes[$k]);
          $temp_prof_str .= "  /  ";
        }
     }

     readingsBulkUpdate($shash, "weekprofile-$i-$decalcDays[$i]-time", $time_prof_str );
     readingsBulkUpdate($shash, "weekprofile-$i-$decalcDays[$i]-temp", $temp_prof_str );

     } # Endparse weekprofiles for each day

  } elsif($msgtype eq "Error") {
    if(@args == 0) {
      delete $shash->{ERROR} if(exists($shash->{ERROR}));
    } else {
      $shash->{ERROR} = join(",",$args[0]);
    }

  } elsif($msgtype eq "Ack") {
    #The payload of an Ack is a 2-digit hex number (I just saw it being "01")
    #with unknown meaning plus the data of a State broadcast from the same device
    #For HeatingThermostats, it does not contain the last three "until" bytes (or measured temperature)
    if($shash->{type} ~~ ["HeatingThermostat", "WallMountedThermostat"] ) {
      return MAX_Parse($hash, "MAX,$isToMe,ThermostatState,$addr,". substr($args[0],2));
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
    The &lt;type&gt; is one of Cube, HeatingThermostat, HeatingThermostatPlus, WallMountedThermostat, ShutterContact, PushButton.
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
          <li>"on" or "off" correspondig to 30.5 and 4.5 degree celcius</li>
          <li>"eco" or "comfort" using the eco/comfort temperature set on the device (just as the right-most physical button on the device itself does)</li>
          <li>"auto", where the weekly program saved on the thermostat is processed</li>
          <li>"boost", activates the boost mode, where for boostDuration minutes the valve is opened up boostValveposition percent.</li>
        </ul>
        All values but "auto" maybe accompanied by the "until" clause, with &lt;data&gt; in format "dd.mm.yyyy HH:MM" (minutes may only be "30" or "00"!)
        to set a temporary temperature until that date/time. Make sure that the cube has valid system time!</li>
    <li>groupid &lt;id&gt;<br>
      For devices of type HeatingThermostat only.
      Writes the given group id the device's memory. It is usually not necessary to change this.</li>
    <li>ecoTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given eco temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <li>comfortTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given comfort temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <li>measurementOffset &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given temperature offset to the device's memory. The thermostat tries to match desiredTemperature to (measured temperature at sensor - measurementOffset). Usually, the measured temperature is a bit higher than the overall room temperature (due to closeness to the heater), so one uses a small positive offset. Must be between -3.5 and 3.5 degree.</li>
    <li>minimumTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given minimum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>maximumTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given maximum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>windowOpenTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open temperature to the device's memory. That is the temperature the heater will temporarily set if an open window is detected.</li>
    <li>windowOpenDuration &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open duration to the device's memory. That is the duration the heater will temporarily set the window open temperature if an open window is detected by a rapid temperature decrease. (Not used if open window is detected by ShutterControl. Must be between 0 and 60 minutes in multiples of 5.</li>
    <li>factoryReset<br>
        Resets the device to factory values. It has to be paired again afterwards.<br>
        ATTENTION: When using this on a ShutterContact using the MAXLAN backend, the ShutterContact has to be triggered once manually to complete
        the factoryReset.</li>
    <li>associate &lt;value&gt;<br>
        Associated one device to another. &lt;value&gt; can be the name of MAX device or its 6-digit hex address.<br>
        Associating a ShutterContact to a {Heating,WallMounted}Thermostat makes it send message to that device to automatically lower temperature to windowOpenTemperature while the shutter is opened. The thermostat must be associated to the ShutterContact, too, to accept those messages.
        Associating HeatingThermostat and WallMountedThermostat makes them sync their desiredTemperature and uses the measured temperature of the
 WallMountedThermostat for control.</li>
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
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>desiredTemperature<br>Only for HeatingThermostat and WallMountedThermostat</li>
    <li>valveposition<br>Only for HeatingThermostat</li>
    <li>battery</li>
    <li>temperature<br>The measured(!) temperature, only for HeatingThermostat and WallMountedThermostat</li>
  </ul>
</ul>

=end html
=cut
