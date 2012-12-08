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

my %device_types = (
  0 => "Cube",
  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton"
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

  Log 5, "Calling MAX_Initialize";
  $hash->{Match}     = "^MAX";
  $hash->{DefFn}     = "MAX_Define";
  $hash->{UndefFn}   = "MAX_Undef";
  $hash->{ParseFn}   = "MAX_Parse";
  $hash->{SetFn}     = "MAX_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 event-on-update-reading event-on-change-reading";
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
  $hash->{STATE} = "waiting for data";
  $hash->{usingCube} = 0;
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
  while (my ($typeId, $type) = each (%device_types)) {
    return $typeId if($_[0] eq $type);
  }
  Log 1, "MAX_TypeToTypeId: Invalid type $_[0]";
  return 0;
}
#############################
sub
MAX_Set($@)
{
  my ($hash, $devname, @a) = @_;
  my ($setting, @args) = @a;

  if($setting eq "desiredTemperature" and ($hash->{type} eq "HeatingThermostat" or $hash->{type} eq "WallMountedThermostat")) {
    return "Cannot set without IODev" if(!defined($hash->{IODev}));
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
      $temperature = ReadingsVal($hash->{NAME},"ecoTemperature","");
      return "No ecoTemperature defined" if(!$temperature);
    } elsif($args[0] eq "comfort") {
      $temperature = ReadingsVal($hash->{NAME},"comfortTemperature","");
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
    return "Cannot set without IODev" if(!defined($hash->{IODev}));
    return "argument needed" if(@args == 0);

    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},pack("CCCCCCH6CC",0x00,0x00,0x22,0x00,0x00,0x00,$hash->{addr},0x00,$args[0]));

  }elsif( $setting ~~ ["ecoTemperature", "comfortTemperature", "measurementOffset", "maximumTemperature", "minimumTemperature", "windowOpenTemperature", "windowOpenDuration" ] and ($hash->{type} eq "HeatingThermostat" or $hash->{type} eq "WallMountedThermostat")) {
    return "Cannot set without IODev" if(!exists($hash->{IODev}));

    readingsSingleUpdate($hash, $setting, $args[0], 0);

    my $comfortTemperature = ReadingsVal($hash->{NAME},"comfortTemperature","");
    my $ecoTemperature = ReadingsVal($hash->{NAME},"ecoTemperature","");
    my $maximumTemperature = ReadingsVal($hash->{NAME},"maximumTemperature","");
    my $minimumTemperature = ReadingsVal($hash->{NAME},"minimumTemperature","");
    my $windowOpenTemperature = ReadingsVal($hash->{NAME},"windowOpenTemperature","");
    my $windowOpenDuration = ReadingsVal($hash->{NAME},"windowOpenDuration","");
    my $measurementOffset = ReadingsVal($hash->{NAME},"measurementOffset","");

    return "Invalid comfortTemperature"    if($comfortTemperature eq "" or $comfortTemperature < 4.5 or $comfortTemperature > 30.5);
    return "Invalid ecoTemperature"        if($ecoTemperature eq "" or $ecoTemperature < 4.5 or $ecoTemperature > 30.5);
    return "Invalid maximumTemperature"    if($maximumTemperature eq "" or $maximumTemperature < 4.5 or $maximumTemperature > 30.5);
    return "Invalid minimumTemperature"    if($minimumTemperature eq "" or $minimumTemperature < 4.5 or $minimumTemperature > 30.5);
    return "Invalid windowOpenTemperature" if($windowOpenTemperature eq "" or $windowOpenTemperature < 4.5 or $windowOpenTemperature > 30.5);
    return "Invalid windowOpenDuration"    if($windowOpenDuration eq "" or $windowOpenDuration < 0 or $windowOpenDuration > 60);
    return "Invalid measurementOffset"     if($measurementOffset eq "" or $measurementOffset < -3.5 or $measurementOffset > 3.5);

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
    return "Cannot set without IODev" if(!exists($hash->{IODev}));
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
      #CUL_MAXK
      my $payload = pack("CCCCCCH6C",0x00,0x00,0xF0,0x00,0x00,0x00,$hash->{addr}, 0);
      return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);
    }

  } elsif($setting eq "wakeUp") {
    my $payload = pack("CCCCCCH6CC",0x00,0x00,0xF1,0x00,0x00,0x00,$hash->{addr}, 0, 0x3F);
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);

  }else{
    my $removeDevice = exists($hash->{IODev}{RemoveDevice}) ? " removeDevice" : "";
    my $templist = join(",",map { sprintf("%2.1f",$_/2) }  (9..61));
    my $ret = "Unknown argument $setting, choose one of wakeUp factoryReset groupid$removeDevice";

    my $assoclist;
    #Build list of devices which this device can be associated to
    if($hash->{type} eq "HeatingThermostat") {
      $assoclist = join(",", map { $_->{type} ~~ ["HeatingThermostat", "WallMountedThermostat", "ShutterContact"] ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
    } elsif($hash->{type} ~~ ["ShutterContact", "WallMountedThermostat"]) {
      $assoclist = join(",", map { $_->{type} eq "HeatingThermostat" ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
    }

    if($hash->{type} eq "HeatingThermostat") {
      #Create numbers from 4.5 to 30.5
      my $templistOffset = join(",",map { sprintf("%2.1f",($_-7)/2) }  (0..14));
      return "$ret associate:$assoclist desiredTemperature:eco,comfort,boost,auto,$templist ecoTemperature:$templist comfortTemperature:$templist measurementOffset:$templistOffset maximumTemperature:$templist minimumTemperature:$templist windowOpenTemperature:$templist windowOpenDuration";

    } elsif($hash->{type} eq "WallMountedThermostat") {
      return "$ret associate:$assoclist displayActualTemperature:0,1 desiredTemperature:eco,comfort,boost,auto,$templist";
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
  my ($MAX,$msgtype,$addr,@args) = split(",",$msg);
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

  if($msgtype eq "define"){
    my $devicetype = $args[0];
    Log 1, "Device changed type from $shash->{type} to $devicetype" if($shash->{type} ne $devicetype);
    if(@args > 1){
      my $serial = $args[1];
      Log 1, "Device changed serial from $shash->{serial} to $serial" if($shash->{serial} and ($shash->{serial} ne $serial));
      $shash->{serial} = $serial;
    }
    $shash->{groupid} = $args[2];
    $shash->{usingCube} = $args[3];
    $shash->{IODev} = $hash;

  } elsif($msgtype eq "ThermostatState") {

    my ($bits2,$valveposition,$temperaturesetpoint,$until1,$until2,$until3) = unpack("aCCCCC",pack("H*",$args[0]));
    my $mode = vec($bits2, 0, 2); #
    my $dstsetting = vec($bits2, 3, 1); #is automatically switching to DST activated
    my $langateway = vec($bits2, 4, 1); #??
    my $panel = vec($bits2, 5, 1); #1 if the heating thermostat is locked for manually setting the temperature at the device
    my $rferror = vec($bits2, 6, 1); #communication with link partner (what does that mean?)
    my $batterylow = vec($bits2, 7, 1); #1 if battery is low

    my $untilStr = defined($until3) ? MAX_ParseDateTime($until1,$until2,$until3)->{str} : "";
    my $measuredTemperature = $until2/10;
    #If the control mode is not "temporary", the cube sends the current (measured) temperature
    $measuredTemperature = "" if($mode == 2 || $measuredTemperature == 0);
    $untilStr = "" if($mode != 2);

    $temperaturesetpoint = $temperaturesetpoint/2.0; #convert to degree celcius
    Log 5, "battery $batterylow, rferror $rferror, panel $panel, langateway $langateway, dstsetting $dstsetting, mode $mode, valveposition $valveposition %, temperaturesetpoint $temperaturesetpoint, until $untilStr, curTemp $measuredTemperature";
    #my $settemp = $args[0];
    #my $mode = $ctrl_modes[$args[1]];
    #my $until = $args[2];
    #my $batterylow = $args[3];
    #my $rferror = $args[4];
    #my $dstsetting = $args[5];
    #my $valveposition = $args[6];
    #my $measuredTemperature = "";

    #The HeatingThermostat uses the measurementOffset during control
    #but does not apply it to measuredTemperature before sending it to us
    $measuredTemperature += $shash->{measurementOffset} if($measuredTemperature ne "" and exists($shash->{measurementOffset}));

    $shash->{mode} = $mode;
    $shash->{rferror} = $rferror;
    $shash->{dstsetting} = $dstsetting;
    if($mode eq "temporary"){
      $shash->{until} = "$untilStr";
    }else{
      delete($shash->{until});
    }

    readingsBeginUpdate($shash);
    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    #This formatting must match with in MAX_Set:$templist
    readingsBulkUpdate($shash, "desiredTemperature", sprintf("%2.1f",$temperaturesetpoint));
    if($shash->{type} eq "HeatingThermostat") {
      readingsBulkUpdate($shash, "valveposition", $valveposition);
    } else {
      #This is a WallMountedThermostat
      readingsBulkUpdate($shash, "displayActualTemperature", $valveposition ? 1 : 0);
    }
    if($measuredTemperature ne "") {
      readingsBulkUpdate($shash, "temperature", $measuredTemperature);
    }
    readingsEndUpdate($shash, 0);

  }elsif($msgtype eq "ShutterContactState"){
    my $bits = pack("H2",$args[0]);
    my $isopen = vec($bits,0,2) == 0 ? 0 : 1;
    my $unkbits = vec($bits,2,4);
    my $rferror = vec($bits,6,1);
    my $batterylow = vec($bits,7,1);
    Log 5, "ShutterContact isopen $isopen, rferror $rferror, battery $batterylow, unkbits $unkbits";

    $shash->{rferror} = $rferror;

    readingsBeginUpdate($shash);
    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    readingsBulkUpdate($shash,"onoff",$isopen);
    readingsEndUpdate($shash, 0);

  }elsif($msgtype eq "CubeClockState"){
    my $clockset = $args[0];
    $shash->{clocknotset} = !$clockset;

  }elsif($msgtype eq "CubeConnectionState"){
    my $connected = $args[0];

    readingsSingleUpdate($shash,"connection",$connected, 0);

  } elsif($msgtype eq "ThermostatConfig") {
    readingsBeginUpdate($shash);
    readingsBulkUpdate($shash, "ecoTemperature", $args[0]);
    readingsBulkUpdate($shash, "comfortTemperature", $args[1]);
    readingsBulkUpdate($shash, "boostValveposition", $args[2]);
    readingsBulkUpdate($shash, "boostDuration", $args[3]);
    readingsBulkUpdate($shash, "measurementOffset", $args[4]);
    readingsBulkUpdate($shash, "maximumTemperature", $args[5]);
    readingsBulkUpdate($shash, "minimumTemperature", $args[6]);
    readingsBulkUpdate($shash, "windowOpenTemperature", $args[7]);
    readingsBulkUpdate($shash, "windowOpenDuration", $args[8]) if($shash->{type} eq "HeatingThermostat");
    readingsEndUpdate($shash, 0);

  } elsif($msgtype eq "Error") {
    if(@args == 0) {
      delete $shash->{ERROR} if(exists($shash->{ERROR}));
    } else {
      $shash->{ERROR} = join(",",$args[0]);
    }

  } else {
    Log 1, "MAX_Parse: Unknown message $msgtype";
  }

  #Build $shash->{STATE}
  $shash->{STATE} = "waiting for data";
  if(exists($shash->{READINGS})) {
    $shash->{STATE} = $shash->{READINGS}{connection}{VAL} ? "connected" : "not connected" if(exists($shash->{READINGS}{connection}));
    $shash->{STATE} = "$shash->{READINGS}{desiredTemperature}{VAL} °C" if(exists($shash->{READINGS}{desiredTemperature}));
    $shash->{STATE} = $shash->{READINGS}{onoff}{VAL} ? "opened" : "closed" if(exists($shash->{READINGS}{onoff}));
  }

  $shash->{STATE} .= " (clock not set)" if($shash->{clocknotset});
  $shash->{STATE} .= " (auto)" if(exists($shash->{mode}) and $shash->{mode} eq "auto");
  #Don't print this: it's the standard mode
  #$shash->{STATE} .= " (manual)" if(exists($shash->{mode}) and  $shash->{mode} eq "manual");
  $shash->{STATE} .= " (until ".$shash->{until}.")" if(exists($shash->{mode}) and $shash->{mode} eq "temporary" );
  $shash->{STATE} .= " (battery low)" if($shash->{batterylow});
  $shash->{STATE} .= " (rf error)" if($shash->{rferror});
  
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
    <code>attr Heater_0 event-on-change-reading battery,desiredTemperature,valveposition</code>
    because the polling mechanism will otherwise create events every 10 seconds.

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
      For devices of type HeatingThermostat only. Writes the given temperature offset to the device's memory. The thermostat tries to match desiredTemperature to (measured temperature at sensor + measurementOffset). Usually, the measured temperature is a bit higher than the overall room temperature (due to closeness to the heater), so one uses a small negative offset. Must be between -3.5 and 3.5 degree.</li>
    <li>minimumTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given minimum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>maximumTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given maximum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>windowOpenTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open temperature to the device's memory. That is the temperature the heater will temporarily set if an open window is detected.</li>
    <li>windowOpenDuration &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open duration to the device's memory. That is the duration the heater will temporarily set the window open temperature if an open window is detected by a rapid temperature decrease. (Not used if open window is detected by ShutterControl. Must be between 0 and 60 minutes in multiples of 5.</li>
    <li>factoryReset<br>
        Resets the device to factory values. It has to be paired again afterwards. (If you use MAXLAN, you have to use removeDevice, before you can re-pair.)</li>
    <li>associate<br>
        Associating a ShutterContact to a {Heating,WallMounted}Thermostat makes it send message to that device to automatically lower temperature to windowOpenTemperature while the shutter is opened.</li>
  </ul>
  <br>

  <a name="MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>desiredTemperature<br>Only for HeatingThermostat</li>
    <li>valveposition<br>Only for HeatingThermostat</li>
    <li>battery</li>
    <li>temperature<br>The measured(!) temperature, only for HeatingThermostat</li>
  </ul>
</ul>

=end html
=cut
