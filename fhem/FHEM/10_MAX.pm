##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;
use MIME::Base64;
use Data::Dumper;

sub MAX_Define($$);
sub MAX_Initialize($);
sub MAX_Parse($$);
sub MAX_Set($@);
sub MAX_MD15Cmd($$$);
sub MAX_DateTime2Internal($);

my @ctrl_modes = ( "auto", "manual", "temporary" );

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
  my $addr = $a[3];
  Log 5, "Max_define $type with addr $addr ";
  $hash->{type} = $type;
  $hash->{addr} = $addr;
  $hash->{STATE} = "waiting for data";
  $modules{MAX}{defptr}{$addr} = $hash;

  $hash->{internals}{interfaces} = $interfaces{$type};

  AssignIoPort($hash);
  return undef;
}

sub
MAX_DateTime2Internal($)
{
  my($day, $month, $year, $hour, $min) = ($_[0] =~ /^(\d{2}).(\d{2})\.(\d{4}) (\d{2}):(\d{2})$/);
  return (($month&0xE) << 20) | ($day << 16) | (($month&1) << 15) | (($year-2000) << 8) | ($hour*2 + int($min/30));
}

#############################
sub
MAX_Set($@)
{
  my ($hash, $devname, @a) = @_;
  my ($setting, @args) = @a;

  return "Cannot set without IODev" if(!exists($hash->{IODev}));

  if($setting eq "desiredTemperature"){
    return "can only set desiredTemperature for HeatingThermostat" if($hash->{type} ne "HeatingThermostat");
    return "missing a value" if(@args == 0);

    my $temperature;
    my $until = undef;
    my $ctrlmode = 1; #0=auto, 1=manual; 2=temporary

    if($args[0] eq "auto") {
      #This enables the automatic/schedule mode where the thermostat follows the weekly program
      $temperature = 0;
      $ctrlmode = 0; #auto
      #TODO: auto mode with temperature is also possible
    } elsif($args[0] eq "eco") {
      return "No ecoTemperature defined" if(!exists($hash->{ecoTemperature}));
      $temperature = $hash->{ecoTemperature};
    } elsif($args[0] eq "comfort") {
      return "No comfortTemperature defined" if(!exists($hash->{comfortTemperature}));
      $temperature = $hash->{comfortTemperature};
    } elsif($args[0] eq "on") {
      $temperature = 30.5;
    } elsif($args[0] eq "off") {
      $temperature = 4.5;
    }else{
      $temperature = $args[0];
    }

    if(@args > 1 and $args[1] eq "until" and $ctrlmode == 1) {
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

    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},pack("CCCCCCH6CC",0x00,0x00,34,0x00,0x00,0x00,$hash->{addr},0x00,$args[0]));

  }elsif( $setting ~~ ["ecoTemperature", "comfortTemperature", "temperatureOffset", "maximumTemperature", "minimumTemperature", "windowOpenTemperature", "windowOpenDuration" ]) {

    return "can only set configuration for HeatingThermostat" if($hash->{type} ne "HeatingThermostat");
    return "Invalid comfortTemperature" if(!exists($hash->{comfortTemperature}) or $hash->{comfortTemperature} < 4.5 or $hash->{comfortTemperature} > 30.5);
    return "Invalid ecoTemperature" if(!exists($hash->{ecoTemperature}) or $hash->{ecoTemperature} < 4.5 or $hash->{ecoTemperature} > 30.5);
    return "Invalid maximumTemperature" if(!exists($hash->{maximumTemperature}) or $hash->{maximumTemperature} < 4.5 or $hash->{maximumTemperature} > 30.5);
    return "Invalid minimumTemperature" if(!exists($hash->{minimumTemperature}) or $hash->{minimumTemperature} < 4.5 or $hash->{minimumTemperature} > 30.5);
    return "Invalid windowOpenTemperature" if(!exists($hash->{windowOpenTemperature}) or $hash->{windowOpenTemperature} < 4.5 or $hash->{windowOpenTemperature} > 30.5);
    return "Invalid temperatureOffset" if(!exists($hash->{temperatureOffset}) or $hash->{temperatureOffset} < -3.5 or $hash->{temperatureOffset} > 3.5);
    return "Invalid windowOpenDuration" if(!exists($hash->{windowOpenDuration}) or $hash->{windowOpenDuration} < 0 or $hash->{windowOpenDuration} > 60);

    $hash->{$setting} = $args[0];

    my $comfort = int($hash->{comfortTemperature}*2);
    my $eco = int($hash->{ecoTemperature}*2);
    my $max = int($hash->{maximumTemperature}*2);
    my $min = int($hash->{minimumTemperature}*2);
    my $offset = int(($hash->{temperatureOffset} + 3.5)*2);
    my $windowOpenTemp = int($hash->{windowOpenTemperature}*2);
    my $windowOpenTime = int($hash->{windowOpenDuration}/5);

    my $payload = pack("CCCCCCH6C"."CCCCCCC",0x00,0x00,17,0x00,0x00,0x00,$hash->{addr},0x00,
                                              $comfort,$eco,$max,$min,$offset,$windowOpenTemp,$windowOpenTime);
    return ($hash->{IODev}{SendDeviceCmd})->($hash->{IODev},$payload);
  }elsif($setting eq "removeDevice") {
    return ($hash->{IODev}{RemoveDevice})->($hash->{IODev},$hash->{addr});
  }else{
    if($hash->{type} eq "HeatingThermostat") {
      #Create numbers from 4.5 to 30.5
      my $templist = join(",",map { $_/2 }  (9..61));
      return "Unknown argument $setting, choose one of desiredTemperature:eco,comfort,$templist ecoTemperature comfortTemperature temperatureOffset maximumTemperature minimumTemperature windowOpenTemperature windowOpenDuration groupid removeDevice";
    } else {
      return "Unknown argument $setting, choose one of groupid removeDevice";
    }
  }
}

#############################
sub
MAX_Parse($$)
{
  my ($hash, $msg) = @_;
  my ($MAX,$msgtype,$addr,@args) = split(",",$msg);

  #Find the device with the given addr
  my $shash = $modules{MAX}{defptr}{$addr};

  if(!$shash)
  {
    if($msgtype eq "define"){
      my $devicetype = $args[0];
      return "UNDEFINED MAX_$addr MAX $devicetype $addr";
    }else{
      return;
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
    if(@args > 2){
      my $groupid = $args[2];
      $shash->{groupid} = $groupid;
    }

  } elsif($msgtype eq "HeatingThermostatState") {
    my $settemp = $args[0];
    my $mode = $ctrl_modes[$args[1]];
    my $until = $args[2];
    my $batterylow = $args[3];
    my $rferror = $args[4];
    my $dstsetting = $args[5];
    my $valveposition = $args[6];
    my $measuredTemperature = "";
    $measuredTemperature = $args[7] if(@args > 7);

    $shash->{mode} = $mode;
    $shash->{rferror} = $rferror;
    $shash->{dstsetting} = $dstsetting;
    if($mode eq "temporary"){
      $shash->{until} = "$until";
    }else{
      delete($shash->{until});
    }

    readingsBeginUpdate($shash);
    readingsBulkUpdate($shash, "battery", $batterylow ? "low" : "ok");
    readingsBulkUpdate($shash, "desiredTemperature", $settemp);
    readingsBulkUpdate($shash, "valveposition", $valveposition);
    if($measuredTemperature ne "") {
      readingsBulkUpdate($shash, "temperature", $measuredTemperature);
    }
    readingsEndUpdate($shash, 0);

  }elsif($msgtype eq "ShutterContactState"){
    my $isopen = $args[0];
    my $batterylow = $args[1];
    my $rferror = $args[2];

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

    readingsSingleUpdate($shash,"connection",$connected,0);
  } elsif($msgtype eq "HeatingThermostatConfig") {

    $shash->{ecoTemperature} = $args[0];
    $shash->{comfortTemperature} = $args[1];
    $shash->{boostValveposition} = $args[2];
    $shash->{boostDuration} = $args[3];
    $shash->{temperatureOffset} = $args[4];
    $shash->{maximumTemperature} = $args[5];
    $shash->{minimumTemperature} = $args[6];
    $shash->{windowOpenTemperature} = $args[7];
    $shash->{windowOpenDuration} = $args[8];
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
        </ul>
        All values but "auto" maybe accompanied by the "until" clause, with &lt;data&gt; in format "dd.mm.yyyy HH:MM" (minutes may only be "30" or "00"!)
        to set a temporary temperature until that date/time. Make sure that the cube has valid system time!</li>
    <li>groupid &lt;id&gt;<br>
      For devices of type HeatingThermostat only.
      Writes the given group id the device's memory. It is usually not necessary to change this.</li>
    <li>removeDevice<br>
      Removes the device from the cube, i.e. deletes the pairing.</li>
    <li>ecoTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given eco temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <li>comfortTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given comfort temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <li>temperatureOffset &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given temperature offset to the device's memory. The thermostat tries to match desiredTemperature to (measuredTemperature+temperatureOffset). Usually, the measured temperature is a bit higher than the overall room temperature (due to closeness to the heater), so one uses a small negative offset. Must be between -3.5 and 3.5 degree.</li>
    <li>minimumTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given minimum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>maximumTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given maximum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <li>windowOpenTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open temperature to the device's memory. That is the temperature the heater will temporarily set if an open window is detected.</li>
    <li>windowOpenDuration &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open duration to the device's memory. That is the duration the heater will temporarily set the window open temperature if an open window is detected by a rapid temperature decrease. (Not used if open window is detected by ShutterControl. Must be between 0 and 60 minutes in multiples of 5.</li>
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
