##############################################
#
# fhem bridge to MySensors (see http://mysensors.org)
#
# Copyright (C) 2014 Norbert Truchsess
# Copyright (C) 2019 Hauswart@forum.fhem.de
# Copyright (C) 2010 Beta-User@forum.fhem.de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
##############################################

package MYSENSORS::DEVICE;  ## no critic 'Package declaration'

use strict;
use warnings;
use SetExtensions;
use Time::Local qw(timegm_nocheck);
use Time::HiRes qw(gettimeofday);
use GPUtils qw(:all);

sub main::MYSENSORS_DEVICE_Initialize { goto &Initialize };
    
BEGIN {
    main::LoadModule("MYSENSORS");
    MYSENSORS->import(qw(:all));

  GP_Import(qw(
    AttrVal
    readingsSingleUpdate
    readingsBeginUpdate
    readingsEndUpdate
    readingsBulkUpdate
    CommandAttr
    CommandDeleteAttr
    CommandDeleteReading
    AssignIoPort
    Log3
    SetExtensions
    SetExtensionsCancel
    ReadingsVal
    ReadingsNum
    InternalVal
    FileRead
    InternalTimer
    RemoveInternalTimer
    asyncOutput
    readingFnAttributes
  ))
};

sub Initialize {

  my $hash = shift // return;

  # Consumer
  $hash->{DefFn}    = \&Define;
  $hash->{UndefFn}  = \&UnDefine;
  $hash->{SetFn}    = \&Set;
  $hash->{GetFn}    = \&Get;
  $hash->{AttrFn}   = \&Attr;
  no warnings 'qw'; ## no critic 'Warnings'
  my @attrList = qw(
    config:M,I 
    mode:node,repeater
    setCommands
    setExtensionsEvent:1,0
    setReading_.+
    mapReadingType_.+
    mapReading_.+
    requestAck:1
    timeoutAck
    timeoutAlive
    IODev
    showtime:0,1
    OTA_autoUpdate:0,1
    OTA_BL_Type:Optiboot,MYSBootloader
    OTA_Chan76_IODev
    streamFilePatterns
    model
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  main::LoadModule("MYSENSORS");
  return;
}


my %gets = (
    "version" => "noArg",
    "heartbeat" => "noArg", 
    "presentation" => "noArg", 
    "RSSI" => "noArg", 
    "Extended_DEBUG"  => "noArg", 
    "ReadingsFromComment" => "noArg", 
);


my %static_types = (
  S_DOOR                  => { receives => [], sends => [V_TRIPPED,V_ARMED] }, # Door and window sensors
  S_MOTION                => { receives => [], sends => [V_TRIPPED,V_ARMED] }, # Motion sensors
  S_SMOKE                 => { receives => [], sends => [V_TRIPPED,V_ARMED] }, # Smoke sensor
  S_BINARY                => { receives => [V_STATUS,V_WATT], sends => [V_STATUS,V_WATT] }, # Binary device (on/off)
  S_DIMMER                => { receives => [V_STATUS,V_PERCENTAGE,V_WATT], sends => [V_STATUS,V_PERCENTAGE,V_WATT] }, # Dimmable device of some kind
  S_COVER                 => { receives => [V_UP,V_DOWN,V_STOP,V_PERCENTAGE], sends => [V_UP,V_DOWN,V_STOP,V_PERCENTAGE] }, # Window covers or shades
  S_TEMP                  => { receives => [], sends => [V_TEMP,V_ID] }, # Temperature sensor
  S_HUM                   => { receives => [], sends => [V_HUM] }, # Humidity sensor
  S_BARO                  => { receives => [], sends => [V_PRESSURE,V_FORECAST] }, # Barometer sensor (Pressure)
  S_WIND                  => { receives => [], sends => [V_WIND,V_GUST,V_DIRECTION] }, # Wind sensor
  S_RAIN                  => { receives => [], sends => [V_RAIN,V_RAINRATE] }, # Rain sensor
  S_UV                    => { receives => [], sends => [V_UV] }, # UV sensor
  S_WEIGHT                => { receives => [], sends => [V_WEIGHT,V_IMPEDANCE] }, # Weight sensor for scales etc.
  S_POWER                 => { receives => [V_VAR1], sends => [V_WATT,V_KWH,V_VAR,V_VA,V_POWER_FACTOR,V_VAR1] }, # Power measuring device, like power meters
  S_HEATER                => { receives => [], sends => [V_HVAC_SETPOINT_HEAT,V_HVAC_FLOW_STATE,V_TEMP,V_STATUS] }, # Heater device
  S_DISTANCE              => { receives => [], sends => [V_DISTANCE,V_UNIT_PREFIX] }, # Distance sensor
  S_LIGHT_LEVEL           => { receives => [], sends => [V_LIGHT_LEVEL,V_LEVEL] }, # Light sensor
  S_ARDUINO_NODE          => { receives => [], sends => [] }, # Arduino node device
  S_ARDUINO_REPEATER_NODE => { receives => [], sends => [] }, # Arduino repeating node device
  S_LOCK                  => { receives => [V_LOCK_STATUS], sends => [V_LOCK_STATUS] }, # Lock device
  S_IR                    => { receives => [V_IR_SEND], sends => [V_IR_RECEIVE,V_IR_RECORD,V_IR_SEND] }, # Ir sender/receiver device
  S_WATER                 => { receives => [V_VAR1], sends => [V_FLOW,V_VOLUME,V_VAR1] }, # Water meter
  S_AIR_QUALITY           => { receives => [], sends => [V_LEVEL,V_UNIT_PREFIX] }, # Air quality sensor e.g. MQ-2
  S_CUSTOM                => { receives => [V_VAR1,V_VAR2,V_VAR3,V_VAR4,V_VAR5], sends => [V_VAR1,V_VAR2,V_VAR3,V_VAR4,V_VAR5] }, # Use this for custom sensors where no other fits.
  S_DUST                  => { receives => [], sends => [V_LEVEL,V_UNIT_PREFIX] }, # Dust level sensor
  S_SCENE_CONTROLLER      => { receives => [], sends => [V_SCENE_ON,V_SCENE_OFF] }, # Scene controller device
  S_RGB_LIGHT             => { receives => [V_RGB,V_WATT,V_PERCENTAGE], sends => [V_RGB,V_WATT,V_PERCENTAGE] }, # RGB light
  S_RGBW_LIGHT            => { receives => [V_RGBW,V_WATT,V_PERCENTAGE], sends => [V_RGBW,V_WATT,V_PERCENTAGE] }, # RGBW light (with separate white component)
  S_COLOR_SENSOR          => { receives => [V_RGB], sends => [V_RGB] }, # Color sensor
  S_HVAC                  => { receives => [], sends => [V_STATUS,V_TEMP,V_HVAC_SETPOINT_HEAT,V_HVAC_SETPOINT_COOL,V_HVAC_FLOW_STATE,V_HVAC_FLOW_MODE,V_HVAC_SPEED] }, # Thermostat/HVAC device
  S_MULTIMETER            => { receives => [], sends => [V_VOLTAGE,V_CURRENT,V_IMPEDANCE] }, # Multimeter device
  S_SPRINKLER             => { receives => [], sends => [V_STATUS,V_TRIPPED] }, # Sprinkler device
  S_WATER_LEAK            => { receives => [], sends => [V_TRIPPED,V_ARMED] }, # Water leak sensor
  S_SOUND                 => { receives => [], sends => [V_LEVEL,V_TRIPPED,V_ARMED] }, # Sound sensor
  S_VIBRATION             => { receives => [], sends => [V_LEVEL,V_TRIPPED,V_ARMED] }, # Vibration sensor
  S_MOISTURE              => { receives => [], sends => [V_LEVEL,V_TRIPPED,V_ARMED] }, # Moisture sensor
  S_INFO                  => { receives => [V_TEXT], sends => [V_TEXT] }, # LCD text device
  S_GAS                   => { receives => [], sends => [V_FLOW,V_VOLUME] }, # Gas meter
  S_GPS                   => { receives => [], sends => [V_POSITION] }, # GPS Sensor
  S_WATER_QUALITY         => { receives => [], sends => [V_TEMP,V_PH,V_ORP,V_EC,V_STATUS] }, # Water quality sensor
);

my %static_mappings = (
  V_TEMP        => { type => "temperature" },
  V_HUM         => { type => "humidity" },
  V_STATUS      => { type => "status", val => { 0 => 'off', 1 => 'on' }},
  V_PERCENTAGE  => { type => "percentage", range => { min => 0, step => 1, max => 100 }},
  V_PRESSURE    => { type => "pressure" },
  V_FORECAST    => { type => "forecast", val => { # PressureSensor, DP/Dt explanation
                                                  0 => 'stable',      # 0 = "Stable Weather Pattern"
                                                  1 => 'sunny',       # 1 = "Slowly rising Good Weather", "Clear/Sunny"
                                                  2 => 'cloudy',      # 2 = "Slowly falling L-Pressure ", "Cloudy/Rain"
                                                  3 => 'unstable',    # 3 = "Quickly rising H-Press",     "Not Stable"
                                                  4 => 'thunderstorm',# 4 = "Quickly falling L-Press",    "Thunderstorm"
                                                  5 => 'unknown' }},  # 5 = "Unknown (More Time needed)
  V_RAIN        => { type => "rain" },
  V_RAINRATE    => { type => "rainrate" },
  V_WIND        => { type => "wind" },
  V_GUST        => { type => "gust" },
  V_DIRECTION   => { type => "direction" },
  V_UV          => { type => "uv" },
  V_WEIGHT      => { type => "weight" },
  V_DISTANCE    => { type => "distance" },
  V_IMPEDANCE   => { type => "impedance" },
  V_ARMED       => { type => "armed", val => { 0 => 'off', 1 => 'on' }},
  V_TRIPPED     => { type => "tripped", val => { 0 => 'off', 1 => 'on' }},
  V_WATT        => { type => "power" },
  V_KWH         => { type => "energy" },
  V_SCENE_ON    => { type => "button_on" },
  V_SCENE_OFF   => { type => "button_off" },
  V_HVAC_FLOW_STATE => { type => "hvacflowstate" },
  V_HVAC_SPEED  => { type => "hvacspeed" },
  V_LIGHT_LEVEL => { type => "brightness", range => { min => 0, step => 1, max => 100 }},
  V_VAR1        => { type => "value1" },
  V_VAR2        => { type => "value2" },
  V_VAR3        => { type => "value3" },
  V_VAR4        => { type => "value4" },
  V_VAR5        => { type => "value5" },
  V_UP          => { type => "up" },
  V_DOWN        => { type => "down" },
  V_STOP        => { type => "stop" },
  V_IR_SEND     => { type => "ir_send" },
  V_IR_RECEIVE  => { type => "ir_receive" },
  V_FLOW        => { type => "flow" },
  V_VOLUME      => { type => "volume" },
  V_LOCK_STATUS => { type => "lockstatus", val => { 0 => 'off', 1 => 'on' }},
  V_LEVEL       => { type => "level" },
  V_VOLTAGE     => { type => "voltage" },
  V_CURRENT     => { type => "current" },
  V_RGB         => { type => "rgb" },
  V_RGBW        => { type => "rgbw" },
  V_ID          => { type => "id" },
  V_UNIT_PREFIX => { type => "unitprefix" },
  V_HVAC_SETPOINT_COOL => { type => "hvacsetpointcool" },
  V_HVAC_SETPOINT_HEAT => { type => "hvacsetpointheat" },
  V_HVAC_FLOW_MODE => { type => "hvacflowmode" },
  V_TEXT        => { type => "text" },
  V_CUSTOM      => { type => "custom" },
  V_POSITION    => { type => "position" },
  V_IR_RECORD   => { type => "ir_record" },
  V_PH          => { type => "ph" },
  V_ORP         => { type => "orp" },
  V_EC          => { type => "ec" },
  V_VAR         => { type => "value" },
  V_VA          => { type => "va" },
  V_POWER_FACTOR => { type => "power_factor" },
);


sub Define {
    my $hash = shift;
    my $def  = shift // return;
    my ($name, $type, $radioId) = split m{\s+}xms, $def; # split("[ \t]+", $def);
    return "requires 1 parameter!" if (!defined $radioId || $radioId eq "");
    $hash->{radioId} = $radioId;
    $hash->{sets} = {
      'time'   => "noArg",
      'reboot' => "noArg",
      'clear'  => "noArg",
      'flash'  => "noArg",
      'fwType' => "",
    };

    $hash->{ack} = 0;
    $hash->{'.typeMappings'} = {map {variableTypeToIdx($_) => $static_mappings{$_}} keys %static_mappings};
    $hash->{'.sensorMappings'} = {map {sensorTypeToIdx($_) => $static_types{$_}} keys %static_types};
    $hash->{readingMappings} = {};
    AssignIoPort($hash);
    return;
};

sub UnDefine {
    my $hash = shift // return;
    RemoveInternalTimer($hash->{asyncGet}) if($hash->{asyncGet});
    return RemoveInternalTimer($hash);
}

sub Set {
    my ($hash,$name,$command,@values) = @_;
    return "At least one parameter is needed!" if !defined $command;
    if(!defined($hash->{sets}->{$command})) {
      $hash->{sets}->{fwType} = join(",", MYSENSORS::getFirmwareTypes($hash->{IODev}));
      my $list = join(" ", map {
        $hash->{sets}->{$_} ne "" ? "$_:$hash->{sets}->{$_}" 
                                       : $_
                               } sort keys %{$hash->{sets}});
      $hash->{sets}->{fwType} = "";
      return SetExtensions($hash, $list, $name, $command, @values);
    }
    
    if ($command =~ m{\A(time|reboot|clear|flash|fwType)\z}xms) {
      if ($command eq "time") {
        my $t = timegm_nocheck(localtime(time));
        return sendClientMessage($hash, 
                                 childId => 255, 
                                 cmd => C_INTERNAL, 
                                 ack => 0, 
                                 subType => I_TIME, 
                                 payload => $t
                                 );
      }
      
      if ($command eq "reboot") {
        my $blVersion = ReadingsVal($name, "BL_VERSION", "");
        defined($hash->{OTA_BL_Type}) or $blVersion eq "3.0" 
          ? return sendClientMessage($hash, 
                                     childId => 255, 
                                     cmd => C_INTERNAL, 
                                     ack => 0, 
                                     subType => I_REBOOT
                                     ) 
            : return;
      }
      
      if ($command eq "clear") {
        Log3 ($name,3,"MYSENSORS_DEVICE $name: clear");
        return sendClientMessage($hash, 
                                 childId => 255, 
                                 cmd => C_INTERNAL, 
                                 ack => 0, 
                                 subType => I_DEBUG, 
                                 payload => "E"
                                 );
      }
      
      if ($command eq "flash") {
        my $blVersion = ReadingsVal($name, "BL_VERSION", "");
        my $blType = AttrVal($name, "OTA_BL_Type", "");
        my $fwType = ReadingsNum($name, "FW_TYPE", -1);
        if ($fwType == -1) {
          Log3 ($name,3,"Firmware type not defined (FW_TYPE) for $name, update not started");
          return "$name: Firmware type not defined (FW_TYPE)";
        } elsif ($blVersion eq "3.0" or $blType eq "Optiboot") {
          Log3 ($name,4,"Startet flashing Firmware: Optiboot method");
          return flashFirmware($hash, $fwType);
        } elsif ($blType eq "MYSBootloader") {
          $hash->{OTA_requested} = 1;
          Log3 ($name,4,"Send reboot command to MYSBootloader node to start update");
          return sendClientMessage($hash, 
                                   childId => 255, 
                                   cmd => C_INTERNAL, 
                                   ack => 1, 
                                   subType => I_REBOOT
                                   );
        } else {
          return "$name: No valid OTA_BL_Type specified" if ($blVersion eq "");
          return "$name: Expected bootloader version 3.0 but found: $blVersion or specify a valid OTA_BL_Type";
        }
        return;
      }
      
      if ($command eq 'fwType') {
        my $type = shift @values // return;
        return "fwType must be numeric, but got >$type<." if ($type !~ m{^[0-9]{2,20}$}xms);
        return readingsSingleUpdate($hash, 'FW_TYPE', $type, 1);
      }
    }
    
    #most used setter part
    if (defined ($hash->{setcommands}->{$command})) {
        my $setcommand = $hash->{setcommands}->{$command};
        eval {
          my ($type,$childId,$mappedValue) = mappedReadingToRaw($hash,$setcommand->{var},$setcommand->{val});
          sendClientMessage($hash,
            childId => $childId,
            cmd => C_SET,
            subType => $type,
            payload => $mappedValue,
          );
          if (!$hash->{ack} && !$hash->{IODev}->{ack}) {
            readingsSingleUpdate($hash,$setcommand->{var},$setcommand->{val},1) ; 
            SetExtensionsCancel($hash) if ($command eq "on" || $command eq "off");
            if ($hash->{SetExtensionsCommand} && AttrVal($name, "setExtensionsEvent", undef)) {
              readingsSingleUpdate($hash,"state",$hash->{SetExtensionsCommand},1) ;  
            } else {
              readingsSingleUpdate($hash,"state","$command",1) ;
            } 
          } else {
          readingsSingleUpdate($hash,"state","set $command",1) ;
          }
        };
        return "$command not defined: ".GP_Catch($@) if $@;
        return;
    }
    
    my $value = @values ? join " ",@values : "";
    eval {
        my ($type,$childId,$mappedValue) = mappedReadingToRaw($hash,$command,$value);
        sendClientMessage($hash, 
                          childId => $childId, 
                          cmd => C_SET, 
                          subType => $type, 
                          payload => $mappedValue
                          );
        readingsSingleUpdate($hash,$command,$value,1) unless ($hash->{ack} or $hash->{IODev}->{ack});
    };
    return "$command not defined: ".GP_Catch($@) if $@;
    return;
}

sub Get {
    my ($hash, @list) = @_;
    my $type = $hash->{TYPE};
    return qq("get $type" needs at least one parameter) if (@list < 2);
    if(!defined($hash->{gets}->{$list[1]})) {
      if(!defined($gets{$list[1]})) {
        my @cList = map { $_ =~ m{\A(file|raw)\z}xms ? $_ : "$_:noArg" } sort keys %gets;
        return "Unknown argument $list[1], choose one of " . join(" ", @cList);
      }
    }
    my $command = $list[1];

    if ($command eq "version") {
      if($hash->{CL}) {
        my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$command};
        $hash->{asyncGet} = $tHash;
        InternalTimer(gettimeofday()+4, sub {
          asyncOutput($tHash->{CL}, "Timeout reading answer for $command - node might be asleep?");
          delete($hash->{asyncGet});
        }, $tHash, 0);
      }
      return sendClientMessage($hash, 
                               cmd => C_INTERNAL, 
                               ack => 0, 
                               subType => I_PRESENTATION
                               ); #I_VERSION);
    }

    if ($command eq "heartbeat") {
      if($hash->{CL}) {
        my $start = gettimeofday();
        my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$command, start=>$start};
        $hash->{asyncGet} = $tHash;
        InternalTimer(gettimeofday()+4, sub {
          asyncOutput($tHash->{CL}, "Timeout reading answer for $command - node might be asleep?");
          delete($hash->{asyncGet});
        }, $tHash, 0);
      }
      return sendClientMessage($hash, 
                               cmd => C_INTERNAL, 
                               ack => 0, 
                               subType => I_HEARTBEAT_REQUEST
                               );
    }
    
    if ($command eq "presentation") {
      if($hash->{CL}) {
        my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$command};
        $hash->{asyncGet} = $tHash;
        InternalTimer(gettimeofday()+4, sub {
          asyncOutput($tHash->{CL}, "Timeout reading answer for $command - node might be asleep.");
          delete($hash->{asyncGet});
        }, $tHash, 0);
      }
      return sendClientMessage($hash, 
                               cmd => C_INTERNAL, 
                               ack => 0, 
                               subType => I_PRESENTATION
                               );
    }
    
    if ($command eq "RSSI") {
      if($hash->{CL}) {
        my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$command};
        $hash->{asyncGet} = $tHash;
        InternalTimer(gettimeofday()+4, sub {
          asyncOutput($tHash->{CL}, "Timeout reading answer for $command - node might be asleep.");
          delete($hash->{asyncGet});
        }, $tHash, 0);
      }
        $hash->{I_RSSI} = 1; 
        return sendClientMessage($hash, 
                                 cmd => C_INTERNAL, 
                                 subType => I_SIGNAL_REPORT_REQUEST, 
                                 ack => 0, 
                                 payload => "R");
    }
    
    if ($command eq "Extended_DEBUG") {
      if($hash->{CL}) {
        my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$command};
        $hash->{asyncGet} = $tHash;
        InternalTimer(gettimeofday()+4, sub {
          asyncOutput($tHash->{CL}, "Timeout reading answer for $command. Is node configured to send extended debug info or might it be asleep?");
          delete($hash->{asyncGet});
        }, $tHash, 0);
      }
        $hash->{I_DEBUG} = 1;
        return sendClientMessage($hash, 
                                 cmd => C_INTERNAL, 
                                 subType => I_DEBUG, 
                                 ack => 0, 
                                 payload => "F"
                                 );
    }
    
    if ($command eq "ReadingsFromComment") {
        $hash->{getCommentReadings} = 1;
        return sendClientMessage($hash, 
                                 cmd => C_INTERNAL, 
                                 subType => I_PRESENTATION, 
                                 ack => 0
                                 );
    }
    return;
}

sub onStreamMessage {
    my $hash = shift;
    my $msg  = shift // return;
    my $name = $hash->{NAME};
    my $type = $msg->{subType};
    my $blType = AttrVal($name, "OTA_BL_Type", "");
    my $fwType = hex2Short(substr($msg->{payload}, 0, 4));
    my $payload = $msg->{payload};

    if ($type == ST_FIRMWARE_CONFIG_REQUEST) {
      if (length($msg->{payload}) == 20) {
        my $blVersion = hex(substr($msg->{payload}, 16, 2)) . "." . hex(substr($msg->{payload}, 18, 2));
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'FW_TYPE', $fwType) if ($blType eq "Optiboot");
        readingsBulkUpdate($hash, 'FW_VERSION', hex2Short(substr($msg->{payload}, 4, 4))) if ($blType eq "Optiboot");
        readingsBulkUpdate($hash, 'FW_BLOCKS', hex2Short(substr($msg->{payload}, 8, 4)));
        readingsBulkUpdate($hash, 'FW_CRC', hex2Short(substr($msg->{payload}, 12, 4)));
        readingsBulkUpdate($hash, 'BL_VERSION', $blVersion);
        readingsEndUpdate($hash, 1);
        Log3($name, 4, "$name: received ST_FIRMWARE_CONFIG_REQUEST");
        if ((AttrVal($name, "OTA_autoUpdate", 0) == 1) && ($blVersion eq "3.0" or $blType eq "Optiboot")) {
          Log3($name, 4, "$name: Optiboot BL, Node set to OTA_autoUpdate => calling firmware update procedure");
          flashFirmware($hash, $fwType);
        } elsif ($blType eq "MYSBootloader" && $hash->{OTA_requested} == 1) {
          Log3($name, 4, "$name: MYSBootloader asking for firmware update, calling firmware update procedure");
          $fwType = ReadingsVal($name, "FW_TYPE", "unknown");
          flashFirmware($hash, $fwType);
        }
      } else {
        Log3($name, 2, "$name: Failed to parse ST_FIRMWARE_CONFIG_REQUEST - expected payload length 32 but retrieved ".length($msg->{payload}));
      }
      return;
    }
    
    if ($type == ST_FIRMWARE_REQUEST) {
        return if ($msg->{ack} || !defined $hash->{FW_DATA});
        if (length($msg->{payload}) == 12) {
          my $version = hex2Short(substr($msg->{payload}, 4, 4));
          my $block = hex2Short(substr($msg->{payload}, 8, 4));
          my $fromIndex = $block * 16;
          my @fwData = @{$hash->{FW_DATA}};
          Log3($name, 5, "$name: Firmware block request $block (type $fwType, version $version)");
          
          for (my $index = $fromIndex; $index < $fromIndex + 16; $index++) {
            $payload = $payload . sprintf("%02X", $fwData[$index]);
          }
          if (defined $hash->{OTA_Chan76_IODev}) {
            sendMessage($hash->{OTA_Chan76_IODev}, 
                        radioId => $hash->{radioId}, 
                        childId => 255, 
                        ack => 0, 
                        cmd => C_STREAM, 
                        subType => ST_FIRMWARE_RESPONSE, 
                        payload => $payload
                        );
          } else {
            $hash->{nowSleeping} = 0 if $hash->{nowSleeping};
            sendClientMessage($hash, 
                              childId => 255, 
                              cmd => C_STREAM, 
                              ack => 0, 
                              subType => ST_FIRMWARE_RESPONSE, 
                              payload => $payload
                              );
          }
          readingsSingleUpdate($hash, "state", "updating", 1) if ($hash->{STATE} ne "updating");
          readingsSingleUpdate($hash, "state", "update done", 1) if ($block == 0);
          if ($block == 0 && $blType ne "Optiboot") {
            readingsSingleUpdate($hash, 'FW_VERSION', $version, 1);
            delete $hash->{OTA_requested} if (defined $hash->{OTA_requested});
          }
        } else {
          Log3($name, 2, "$name: Failed to parse ST_FIRMWARE_REQUEST - expected payload length 12 but retrieved ".length($msg->{payload}));
        }
        return;
    }
    

    if ($type == ST_IMAGE||$type == ST_SOUND) {
        #code adopted from https://forum.mysensors.org/topic/1668/sending-image-data-over-the-mysensors-network/11
        #see also node example code there;
        
        #untested code, may work or not; packets are not numbered, so data may be scrambled when using wireless protocols 
        return if $msg->{ack};
        my $id = $msg->{childId};
        if($msg->{payload} eq "START") {
          my($arg, $hashes) = parseParams(AttrVal($name,"streamFilePatterns",'ST_IMAGE=./log/$name-$id-$time.jpg ST_SOUND=./log/$name-$id-$time.mpg'));
          if ($hashes->{$type}) {
            my $time = strftime("%Y-%m-%d-%H-%M-%S", localtime);
            $hash->{helper}{$type}{$id}{file} = qq($hashes->{$type});
          } else {
            Log3($name, 2, "$name: no $type streamFilePattern found. Transfer stream to file not possible!");
            return;
          }
          if ($hash->{helper}{$type}{$id}{running}) {
            ##delete uncompleted transfer
            delete $hash->{helper}{$type}{$id}{data};
          } 
          $hash->{helper}{$type}{$id}{start_time} = time();
          $hash->{helper}{$type}{$id}{count} = 0;
          $hash->{helper}{$type}{$id}{running} = 1;
          return;
        }  
        if($payload eq "END") {
          $hash->{helper}{$type}{$id}{running} = 0;
          
          my $err = FileWrite({ FileName => $hash->{helper}{$type}{$id}{file}, ForceType => "file" },$hash->{helper}{$type}{$id}{data});
          delete $hash->{helper}{$type}{$id}{data};
          my $duration = time() - $hash->{helper}{$type}{$id}{start_time};
          my $bps = $hash->{helper}{$type}{$id}{count} * 24 / $duration;
          $hash->{helper}{$type}{$id}{bps} = $bps;
          my $pps = $hash->{helper}{$type}{$id}{count} / $duration;
          $hash->{helper}{$type}{$id}{pps} = $pps;
          Log3($name, 4, "$name: Stream transfer finished, $duration seconds, $bps Bytes/s, $pps Packets/s");
          my $rname = $type == ST_IMAGE ? "IMAGE_$id" : "SOUND_$id";
          readingsSingleUpdate($hash, $rname, $hash->{helper}{$type}{$id}{file}, 1) if !$err;
          return $err;
        }
        #other paylaod than keywords START and END:
        $hash->{helper}{$type}{$id}{data} .= pack('H*',$payload);
        $hash->{helper}{$type}{$id}{count}++;
        Log3 ($hash->{NAME}, 5, "MYSENSORS_DEVICE $name: received stream-type payload"); # disable after debugging
        return;
    }
    return;
}

sub Attr {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
    if ($attribute eq "config" && $main::init_done) {
      sendClientMessage($hash, 
                        cmd => C_INTERNAL, 
                        childId => 255, 
                        ack => 0, 
                        subType => I_CONFIG, 
                        payload => $command eq 'set' ? $value : "M"
                        );
      return;
    }
    
    if ($attribute eq "mode") {
      if ($command eq "set" and $value eq "repeater") {
        $hash->{repeater} = 1;
      } else {
        $hash->{repeater} = 0;
      }
      return;
    }
    
    if ($attribute eq "setCommands") {
      for my $set (keys %{$hash->{setcommands}}) {
        delete $hash->{sets}->{$set};
      }
      $hash->{setcommands} = {};
      if ($command eq "set" and $value) {
        for my $setCmd (split m{[,\s]}xms,$value) { 
          if ($setCmd =~ m{\A(.+):(.+):(.+)\z}xms) {
            $hash->{sets}->{$1}="";
            $hash->{setcommands}->{$1} = {
              var => $2,
              val => $3,
            };
          } else {
            return "unparsable value in setCommands for $name: $setCmd";
          }
        }
      }
      return;
    }
    
    if ($attribute =~ m{\A setReading_(.+) \z}xms) {
      if ($command eq "set") {
        $hash->{sets}->{$1}= (defined $value) ? join(",",split m{[,\s]}xms,$value) : "";
      } else {
        CommandDeleteReading(undef,"$hash->{NAME} $1");
        delete $hash->{sets}->{$1};
      }
      return;
    }
    
    if ($attribute =~ m{\A mapReadingType_(.+) \z}xms) {
      my $type = variableTypeToIdx("V_$1");
      if ($command eq "set") {
        my @values = split ("[, \t]",$value);
        $hash->{'.typeMappings'}->{$type}={
          type => shift @values,
          val => {map {$_ =~ m{m/^(.+):(.+)$}xms; $1 => $2} @values},
        }
      } else {
        if ($static_mappings{"V_$1"}) {
          $hash->{'.typeMappings'}->{$type}=$static_mappings{"V_$1"};
        } else {
          delete $hash->{'.typeMappings'}->{$type};
        }
        my $readings = $hash->{READINGS};
        my $readingMappings = $hash->{readingMappings};
        for my $todelete (map {$readingMappings->{$_}->{name}} grep {$readingMappings->{$_}->{type} == $type} keys %$readingMappings) {
          CommandDeleteReading(undef,"$hash->{NAME} $todelete"); #TODO do propper remap of existing readings
        }
      }
      return;
    }
    
    if ($attribute =~ m{\A mapReading_(.+) \z}xms) {
      my $readingMappings = $hash->{readingMappings};
      FIND: for my $id (keys %$readingMappings) {
        my $readingsForId = $readingMappings->{$id};
        for my $type (keys %$readingsForId) {
          if (($readingsForId->{$type}->{name} // "") eq $1) {
            delete $readingsForId->{$type};
            unless (keys %$readingsForId) {
              delete $readingMappings->{$id};
            }
          last FIND;
          }
        }
      }
      if ($command eq "set") {
        my ($id,$typeStr,@values) = split m{[,\s]}xms,$value;
        my $typeMappings = $hash->{'.typeMappings'};
        if (my @match = grep {$typeMappings->{$_}->{type} eq $typeStr} keys %$typeMappings) {
          my $type = shift @match;
          $readingMappings->{$id}->{$type}->{name} = $1;
          if (@values) {
            $readingMappings->{$id}->{$type}->{val} = {map {$_ =~ m{\A (.+):(.+) \z}xms; $1 => $2} @values}; #TODO range?
          }
        } else {
          return "unknown reading type $typeStr";
        }
      } else {
        CommandDeleteReading(undef,"$hash->{NAME} $1");
      }
      return;
    }
    
    if ($attribute eq "requestAck") {
      $hash->{ack} = $command eq "set" ? 1 : 0;
      return;
    }
    
    if ($attribute eq "timeoutAck") {
      $hash->{timeoutAck} = $command eq "set" ? $value : 0;
      return;
    }
    
    if ($attribute eq "timeoutAlive") {
      if ($command eq "set" and $value) {
        $hash->{timeoutAlive} = $value;
        refreshInternalMySTimer($hash,"Alive");
      } else {
        $hash->{timeoutAlive} = 0;
      }
      return;
    }
    
    if ($attribute eq "OTA_autoUpdate") {
      return;
    }
  return;
}

sub onGatewayStarted {
    my $hash = shift // return;
    refreshInternalMySTimer($hash,"Alive") if ($hash->{timeoutAlive});
    return;
}

sub onPresentationMessage {
    my $hash = shift;
    my $msg  = shift // return;
    my $name = $hash->{NAME};
    my $nodeType = $msg->{subType};
    my $id = $msg->{childId};
    if ($id == 255) { #special id
      if ($nodeType == S_ARDUINO_NODE) {
        CommandAttr(undef, "$name mode node");
      }
      if ($nodeType == S_ARDUINO_REPEATER_NODE) {
        CommandAttr(undef, "$name mode repeater");
      };
      $hash->{version} = $msg->{payload};
      if ($hash->{asyncGet} && $hash->{asyncGet}{reading} eq "version" ) {
        RemoveInternalTimer($hash->{asyncGet});
        my $version = $msg->{payload};
        asyncOutput($hash->{asyncGet}{CL}, "MySensors protocol info:\n----------------------------\nversion: $version");
        delete($hash->{asyncGet});
      }
      return;
    }

    my $readingMappings = $hash->{readingMappings};
    my $typeMappings = $hash->{'.typeMappings'};
    if (my $sensorMappings = $hash->{'.sensorMappings'}->{$nodeType}) {
        my $idStr = ($id > 0 ? $id : "");
    my @ret = ();
    for my $type (@{$sensorMappings->{sends}}) {
        if (defined $readingMappings->{$id}->{$type}) {
          next unless defined $hash->{getCommentReadings};
          next unless $hash->{getCommentReadings} eq "2";
        }
        my $typeStr = $typeMappings->{$type}->{type};
        if ($hash->{IODev}->{'inclusion-mode'}) {
          if ($msg->{payload} ne "" and $hash->{getCommentReadings} eq "2") {
            $idStr = "_".$msg->{payload};
            $idStr =~ s/\:/\./gx; #replace illegal characters
            $idStr =~ s/[^A-Za-z\d_\.-]+/_/gx;
          }
          if (defined (my $mapping = $hash->{readingMappings}->{$id}->{$type})) {
            if ($mapping->{name} ne "$typeStr$idStr" and $hash->{getCommentReadings} eq "2"and $msg->{payload} ne "") {
              my $oldMappingName = $mapping->{name}; 
              CommandDeleteAttr(undef, "$hash->{NAME} mapReading_$oldMappingName");
              CommandDeleteReading(undef,"$hash->{NAME} $oldMappingName");
              Log3 ($hash->{NAME}, 3, "MYSENSORS_DEVICE $hash->{NAME}: Deleted Reading $oldMappingName");
            }
          }
          if (my $ret = CommandAttr(undef,"$name mapReading_$typeStr$idStr $id $typeStr")) {
            push @ret,$ret;
          }
        } else {
          push @ret,"no mapReading for $id, $typeStr";
        }
    }
    for my $type (@{$sensorMappings->{receives}}) {
        my $typeMapping = $typeMappings->{$type};
        my $typeStr = $typeMapping->{type};
        if ($msg->{payload} ne "" and $hash->{getCommentReadings} eq "2") {
          $idStr = "_".$msg->{payload};
          $idStr =~ s/\:/\./gx; #replace illegal characters
          $idStr =~ s/[^A-Za-z\d_\.-]+/_/gx;
        }
        if (defined $hash->{sets}->{"$typeStr$idStr"}) {
          next unless (defined ($hash->{getCommentReadings}) && $hash->{getCommentReadings} eq "2");
        }
        if ($hash->{IODev}->{'inclusion-mode'}) {
          my @values = ();
          if ($typeMapping->{range}) {
            @values = ('slider',$typeMapping->{range}->{min},$typeMapping->{range}->{step},$typeMapping->{range}->{max});
          } elsif ($typeMapping->{val}) {
            @values = values %{$typeMapping->{val}};
          }
          if (my $ret = CommandAttr(undef,"$name setReading_$typeStr$idStr".(@values ? " ".join (",",@values) : ""))) {
            push @ret,$ret;
          } else {
            push @ret,"no setReading for $id, $typeStr";
          }
        }
        Log3 ($hash->{NAME}, 4, "MYSENSORS_DEVICE $hash->{NAME}: errors on C_PRESENTATION-message for childId $id, subType ".sensorTypeToStr($nodeType)." ".join (", ",@ret)) if @ret;
    }
    }
    return;
}

sub onSetMessage {
    my $hash = shift;
    my $msg  = shift // return;
    my $name = $hash->{NAME};
    if (defined $msg->{payload}) {
      eval {
        my ($reading,$value) = rawToMappedReading($hash,$msg->{subType},$msg->{childId},$msg->{payload});
        readingsSingleUpdate($hash, $reading, $value, 1);
        if ((defined ($hash->{setcommands}->{$value}) && $hash->{setcommands}->{$value}->{var} eq $reading)) { #$msg->{childId}
           if ($hash->{SetExtensionsCommand} && AttrVal($name, "setExtensionsEvent", undef)) { 
             readingsSingleUpdate($hash,"state",$hash->{SetExtensionsCommand},1) ;  
           } else {
             readingsSingleUpdate($hash,"state","$value",1);
             SetExtensionsCancel($hash) unless $msg->{ack};
           }
         }
      };
      Log3 ($hash->{NAME}, 4, "MYSENSORS_DEVICE $hash->{NAME}: ignoring C_SET-message ".GP_Catch($@)) if $@;
    } else {
      Log3 ($hash->{NAME}, 5, "MYSENSORS_DEVICE $hash->{NAME}: ignoring C_SET-message without payload");
    }
    return;
}

sub onRequestMessage {
    my $hash = shift;
    my $msg  = shift // return;
    eval {
      my ($readingname,$val) = rawToMappedReading($hash, $msg->{subType}, $msg->{childId}, $msg->{payload});
      $hash->{nowSleeping} = 0 if $hash->{nowSleeping};
      my $value = ReadingsVal($hash->{NAME},$readingname,$val);
      my ($type,$childId,$mappedValue) = mappedReadingToRaw($hash,$readingname,$value);
      $value = $mappedValue;
      sendClientMessage($hash,
        childId => $msg->{childId},
        cmd => C_SET,
        subType => $msg->{subType},
        payload => $value
      );
    };
    Log3 ($hash->{NAME}, 4, "MYSENSORS_DEVICE $hash->{NAME}: ignoring C_REQ-message ".GP_Catch($@)) if $@;
    return;
}

sub onInternalMessage {
    my $hash = shift;
    my $msg  = shift // return;
    my $name = $hash->{NAME};
    my $type = $msg->{subType};
    my $typeStr = internalMessageTypeToStr($type);

    if ($type == I_BATTERY_LEVEL) {
        readingsSingleUpdate($hash, "batteryPercent", $msg->{payload}, 1);
        refreshInternalMySTimer($hash,"Alive") if $hash->{timeoutAlive};
        Log3 ($name, 4, "MYSENSORS_DEVICE $name: batteryPercent $msg->{payload}");
        return;
    }
    
    if ($type == I_TIME) {
        if ($msg->{ack}) {
          Log3 ($name, 4, "MYSENSORS_DEVICE $name: response to time-request acknowledged");
        } else {
          $hash->{nowSleeping} = 0 if $hash->{nowSleeping};
          my $t = timegm_nocheck(localtime(time));
          sendClientMessage($hash,
                            cmd => C_INTERNAL, 
                            childId => 255, 
                            subType => I_TIME, 
                            payload => $t
                            );
          Log3 ($name, 4, "MYSENSORS_DEVICE $name: update of time requested");
        }
        return;
    }
    
    if ($type == I_SKETCH_NAME) {
        readingsSingleUpdate($hash, "state", "received presentation", 1) unless ($hash->{STATE} eq "received presentation");
        readingsSingleUpdate($hash, "SKETCH_NAME", $msg->{payload}, 1);
        delete $hash->{FW_DATA} if (defined $hash->{FW_DATA});
        $hash->{nowSleeping} = 0 if $hash->{nowSleeping};
        if (defined $hash->{getCommentReadings}){
          if ($hash->{getCommentReadings} == 2) {
            delete $hash->{getCommentReadings};
          } elsif ($hash->{getCommentReadings} == 1) {
            $hash->{getCommentReadings}++;
          }
        }
        Log3 $name, 5, "leaving Sketch Name update";
        return;
    }

    if ($type == I_SKETCH_VERSION) {
        #$hash->{$typeStr} = $msg->{payload};
        readingsSingleUpdate($hash, "SKETCH_VERSION", $msg->{payload}, 1);
        if( $hash->{asyncGet} && $hash->{asyncGet}{reading} eq "presentation" ) {
          RemoveInternalTimer($hash->{asyncGet});
          my $version = $msg->{payload};
          my $sketchn = ReadingsVal($hash->{NAME},'SKETCH_NAME','unknown');
          asyncOutput($hash->{asyncGet}{CL}, "Sketch info:\n----------------------------\nName: $sketchn\nfirmware version: $version");
          delete($hash->{asyncGet});
        } 
        return;
    }
    
    if ($type == I_HEARTBEAT_REQUEST) {
        refreshInternalMySTimer($hash,"Alive") if $hash->{timeoutAlive};
        return;
    }
    
    if ($type == I_HEARTBEAT_RESPONSE) {
        readingsSingleUpdate($hash, "heartbeat", "alive",1);
        if($hash->{asyncGet} && "heartbeat" eq $hash->{asyncGet}{reading}) {
          my $duration = sprintf( "%.1f", (gettimeofday() - $hash->{asyncGet}{start})*1000);
          RemoveInternalTimer($hash->{asyncGet});
          asyncOutput($hash->{asyncGet}{CL}, "heartbeat request answered, roundtrip duration: $duration ms");
          delete($hash->{asyncGet});
        }
        
        refreshInternalMySTimer($hash,"Alive") if $hash->{timeoutAlive};
        if ($hash->{nowSleeping}) {
          $hash->{nowSleeping} = 0 ;
          sendRetainedMessages($hash);
        }
        #$hash->{$typeStr} = $msg->{payload};
        return;
    }

    if ($type == I_PRE_SLEEP_NOTIFICATION) {
        $hash->{preSleep} = $msg->{payload}//500;
        refreshInternalMySTimer($hash,"Asleep");
        refreshInternalMySTimer($hash,"Alive") if $hash->{timeoutAlive};
        MYSENSORS::Timer($hash);
        sendRetainedMessages($hash) ;
        return;
    }

    if ($type == I_POST_SLEEP_NOTIFICATION) {
        readingsSingleUpdate($hash,"sleepState","awake",1);
        $hash->{nowSleeping} = 0;
        refreshInternalMySTimer($hash,"Alive") if $hash->{timeoutAlive};
        return;
    }
    

    if ($type == I_VERSION || $type == I_GATEWAY_READY || $type == I_INCLUSION_MODE || $type == I_LOG_MESSAGE || $type == I_LOCKED ) {
        $hash->{$typeStr} = $msg->{payload};
        return;
    }
    
    if ($type == I_CONFIG) {
        if ($msg->{ack}) {
          Log3 ($name, 4, "MYSENSORS_DEVICE $name: response to config-request acknowledged");
        } else {
          readingsSingleUpdate($hash, "parentId", $msg->{payload}, 1);
          $hash->{nowSleeping} = 0 if $hash->{nowSleeping};
          sendClientMessage($hash,
                            cmd => C_INTERNAL, 
                            ack => 0, 
                            childId => 255, 
                            subType => I_CONFIG, 
                            payload => AttrVal($name,"config","M")
                            );
          Log3 ($name, 4, "MYSENSORS_DEVICE $name: respond to config-request, node parentId = " . $msg->{payload});
        }
        return;
    }

    if ($type == I_CHILDREN) {
        readingsSingleUpdate($hash, "state", "routingtable cleared", 1);
        Log3 ($name, 3, "MYSENSORS_DEVICE $name: routingtable cleared");
        return;
    }

    
    if ($type == I_DEBUG) {
        last if ($msg->{ack});
        my $dbglev = $hash->{I_DEBUG};
        my %rnames2 = ( "1" => "XDBG_CPU_FREQUENCY","2" => "XDBG_CPU_VOLTAGE","3" => "XDBG_FREE_MEMORY");
        my %payloads2 = ( "1" => "V","2" => "M");
        readingsSingleUpdate($hash, $rnames2{$dbglev}, $msg->{payload}, 1);
        if ($dbglev < 3) {
          $hash->{I_DEBUG}++;
          sendClientMessage($hash, 
                            cmd => C_INTERNAL, 
                            ack => 0, 
                            subType => I_DEBUG, 
                            payload => $payloads2{$dbglev}
                            );
        } else {
          delete $hash->{I_DEBUG}; 
          if( $hash->{asyncGet} && $hash->{asyncGet}{reading} eq "RSSI" ) {
            RemoveInternalTimer($hash->{asyncGet});
            my $mem = $msg->{payload};
            my $freq = ReadingsVal($hash->{NAME},'XDBG_CPU_FREQUENCY','unknown');
            my $volt = ReadingsVal($hash->{NAME},'XDBG_CPU_VOLTAGE','unknown');
            asyncOutput($hash->{asyncGet}{CL}, "Debug info:\n----------------------------\nMCU CPU Frequency: $freq\nMCU Voltage: $volt\nMCU Free Memory: $mem");
            delete($hash->{asyncGet});
          }
        }
        return;
    }

    if ($type == I_SIGNAL_REPORT_RESPONSE) {
        return if $msg->{ack};

        if ($msg->{payload} != -256) {
          my $subSet = $hash->{I_RSSI};
          my %rnames = ( "1" => "R_RSSI_to_Parent","2" => "R_RSSI_from_Parent","3" => "R_SNR_to_Parent","4" => "R_SNR_from_Parent","5" => "R_TX_Powerlevel_Pct","6" => "R_TX_Powerlevel_dBm","7" => "R_Uplink_Quality");
          my %payloads = ( "1" => "R!","2" => "S","3" => "S!","4" => "P","5" => "T","6" => "U");
          readingsSingleUpdate($hash, $rnames{$subSet}, $msg->{payload}, 1);
          if ($subSet < 7) {
            $hash->{I_RSSI}++;
            sendClientMessage($hash, 
                              cmd => C_INTERNAL, 
                              ack => 0, 
                              subType => I_SIGNAL_REPORT_REQUEST, 
                              payload => $payloads{$subSet}
                              );
          } else {
            delete $hash->{I_RSSI}; 
            if( $hash->{asyncGet} && $hash->{asyncGet}{reading} eq "RSSI" ) {
              RemoveInternalTimer($hash->{asyncGet});
              my $uq = $msg->{payload};
              my $topar = ReadingsVal($hash->{NAME},'R_RSSI_to_Parent','unknown');
              my $frompar = ReadingsVal($hash->{NAME},'R_RSSI_from_Parent','unknown');
              my $snr2par = ReadingsVal($hash->{NAME},'R_SNR_to_Parent','unknown');
              my $snrfpar = ReadingsVal($hash->{NAME},'R_RSSI_from_Parent','unknown');
              my $powpct = ReadingsVal($hash->{NAME},'R_TX_Powerlevel_Pct','unknown');
              my $powdbm = ReadingsVal($hash->{NAME},'R_TX_Powerlevel_dBm','unknown');
              asyncOutput($hash->{asyncGet}{CL}, "RSSI info:\n----------------------------\nto parent:     $topar\nfrom parent: $frompar\nSNR to parent:    $snr2par\nSNR from parent: $snrfpar\nPower level %:   $powpct\nPower level dBm: powdbm\nUplink Quality: $uq");
              delete($hash->{asyncGet});
            }

          }
          return;
       } elsif( $hash->{asyncGet} && $hash->{asyncGet}{reading} eq "RSSI" ) {
          RemoveInternalTimer($hash->{asyncGet});
          asyncOutput($hash->{asyncGet}{CL}, "Your transport type seems to be RS485, so asking for RSSI values is not possible");
          delete($hash->{asyncGet});
       }
    }
    
    return;
}

sub sendClientMessage {
    my ($hash,%msg) = @_;
    $msg{radioId} = $hash->{radioId};
    my $name = $hash->{NAME};
    $msg{ack} = $hash->{ack} unless defined $msg{ack};
    my $messages = $hash->{retainedMessagesForRadioId}->{messages};
    unless ($hash->{nowSleeping}) {
      sendMessage($hash->{IODev},%msg);
      refreshInternalMySTimer($hash,"Ack") if (($msg{ack} or $hash->{IODev}->{ack}) and $hash->{timeoutAck});
      Log3 ($name,5,"$name is not sleeping, sending message!");
      if ($hash->{nowSleeping}) {
        $hash->{nowSleeping} = 0 ;
        sendRetainedMessages($hash);
      }
      $hash->{retainedMessages}=scalar(@$messages) if (defined $hash->{retainedMessages});
    } else {
      Log3 ($name,5,"$name is sleeping, enqueing message! ");
      #write to queue if node is asleep
      unless (defined $hash->{retainedMessages}) {
        $messages = {messages => [%msg]};
        $hash->{retainedMessages}=1;
        Log3 ($name,5,"$name: No array yet for enqueued messages, building it!");
      } else {
         @$messages = grep {
           $_->{childId} != $msg{childId}
           or $_->{cmd}     != $msg{cmd}
           or $_->{subType} != $msg{subType}
         } @$messages;
         push @$messages,\%msg;
         eval { $hash->{retainedMessages} = scalar(@$messages) }; #might be critical!
      }
    }
    return;
}

sub rawToMappedReading {
    my($hash, $type, $childId, $value) = @_;
    my $name;
    if (defined (my $mapping = $hash->{readingMappings}->{$childId}->{$type})) {
      my $val = $mapping->{val} // $hash->{'.typeMappings'}->{$type}->{val};
      return ($mapping->{name},defined $val ? ($val->{$value} // $value) : $value);
    }
    die "no reading-mapping for childId $childId, type ".($hash->{'.typeMappings'}->{$type}->{type} ? $hash->{'.typeMappings'}->{$type}->{type} : variableTypeToStr($type));
}

sub mappedReadingToRaw {
    my ($hash,$reading,$value) = @_;
    my $readingsMapping = $hash->{readingMappings};
    for my $id (keys %$readingsMapping) {
      my $readingTypesForId = $readingsMapping->{$id};
      for my $type (keys %$readingTypesForId) {
        if (($readingTypesForId->{$type}->{name} // "") eq $reading) {
          if (my $valueMappings = $readingTypesForId->{$type}->{val} // $hash->{'.typeMappings'}->{$type}->{val}) {
            if (my @mappedValues = grep {$valueMappings->{$_} eq $value} keys %$valueMappings) {
              return ($type,$id,shift @mappedValues);
            }
          }
          return ($type,$id,$value);
        }
      }
    }
    die "no mapping for reading $reading";
}

sub short2Hex {
    my $val = shift // return;
    my $temp = sprintf("%04X", $val);
    return substr($temp, 2, 2) . substr($temp, 0, 2);
}

sub hex2Short {
    my $val = shift // return;
    return hex(substr($val, 2, 2) . substr($val, 0, 2));
}

sub flashFirmware {
    my $hash   = shift;
    my $fwType = shift // return;
    my $name   = $hash->{NAME};
    my ($version, $filename, $firmwarename) = getLatestFirmware($hash->{IODev}, $fwType);
    if (not defined $filename) {
      Log3 ($name,3,"No firmware defined for type $fwType - not flashing!");
      return "No firmware defined for type " . $fwType ;
    }
    my ($err, @lines) = FileRead({FileName => "./FHEM/firmware/" . $filename, ForceType => "file"});
    if (defined($err) && $err) {
      Log3 ($name,3,"Could not read firmware file - $err: not flashing!");
      return "Could not read firmware file - $err";
    } else {
      my $start = 0;
      my $end = 0;
      my @fwdata = ();
      readingsSingleUpdate($hash, "state", "updating", 1) unless ($hash->{STATE} eq "updating");
      for (my $i = 0; $i < @lines ; $i++) {
        chomp(my $row = $lines[$i]);
        if (length($row) > 0) {
          $row =~ s/^:+//xms;
          my $reclen = hex(substr($row, 0, 2));
          my $offset = hex(substr($row, 2, 4));
          my $rectype = hex(substr($row, 6, 2));
          my $data = substr($row, 8, 2 * $reclen);
          if ($rectype == 0) {
            if (($start == 0) && ($end == 0)) {
              if ($offset % 128 > 0) {
                Log3 ($name,3,"error loading hex file - offset can't be devided by 128");
                return "error loading hex file - offset can't be devided by 128" ;
              }
              $start = $offset;
              $end = $offset;
            }
            if ($offset < $end) {
              Log3 ($name,3,"error loading hex file - offset can't be devided by 128");
              return "error loading hex file - offset lower than end" ;
            }
            while ($offset > $end) {
              push(@fwdata, 255);
              $end++;
            }
            for (my $i = 0; $i < $reclen; $i++) {
              push(@fwdata, hex(substr($data, $i * 2, 2)));
            }
            $end += $reclen;
         }
       }
    }
    my $pad = $end % 128; # ATMega328 has 64 words per page / 128 bytes per page
    for (my $i = 0; $i < 128 - $pad; $i++) {
        push(@fwdata, 255);
        $end++;
    }
    my $blocks = ($end - $start) / 16;
    my $crc = 0xFFFF;
    for (my $index = 0; $index < @fwdata; ++$index) {
        $crc ^= $fwdata[$index] & 0xFF;
        for (my $bit = 0; $bit < 8; ++$bit) {
          if (($crc & 0x01) == 0x01) {
            $crc = (($crc >> 1) ^ 0xA001);
          } else {
            $crc = ($crc >> 1);
          }
        }
    }
    if (($version != ReadingsNum($name, "FW_VERSION", -1)) || ($blocks != ReadingsNum($name, "FW_BLOCKS", -1)) || ($crc != ReadingsNum($name, "FW_CRC", -1))) {
        Log3($name, 4, "$name: Flashing './FHEM/firmware/" . $filename . "'");
        $hash->{FW_DATA} = \@fwdata;
        my $payload = short2Hex($fwType) . short2Hex($version) . short2Hex($blocks) . short2Hex($crc);
        if (defined $hash->{OTA_Chan76_IODev}) {
          sendMessage($hash->{OTA_Chan76_IODev}, radioId => $hash->{radioId}, childId => 255, ack => 0, cmd => C_STREAM, subType => ST_FIRMWARE_CONFIG_RESPONSE, payload => $payload);
          Log3 ($name,5,"Directly send firmware info to $name using OTA_Chan76_IODev");
        } elsif (AttrVal($name, "OTA_BL_Type", "") eq "MYSBootloader") {
          sendMessage($hash->{IODev}, radioId => $hash->{radioId}, childId => 255, ack => 0, cmd => C_STREAM,  subType => ST_FIRMWARE_CONFIG_RESPONSE, payload => $payload);
          Log3 ($name,5,"Directly send firmware info to $name using regular IODev");
        } else {
          sendClientMessage($hash, childId => 255, cmd => C_STREAM, ack => 0, subType => ST_FIRMWARE_CONFIG_RESPONSE, payload => $payload);
          Log3 ($name,5,"Send firmware info to $name using sendClientMessage");
        }
        return;
    } else {
        return "Nothing todo - latest firmware already installed";
    }
  }
  return;
}

sub refreshInternalMySTimer {
    my $hash = shift;
    my $calltype = shift // return;
    my $name = $hash->{NAME};
    my $heart = ReadingsVal($hash,"heartbeat","dead");
    Log3 $name, 5, "$name: refreshInternalMySTimer called ($calltype)";
    if ($calltype eq "Alive") {
     RemoveInternalTimer($hash,"MYSENSORS::DEVICE::timeoutAlive");
      my $nextTrigger = gettimeofday() + $hash->{timeoutAlive};
      InternalTimer($nextTrigger, "MYSENSORS::DEVICE::timeoutAlive",$hash);
      if ($heart ne "NACK" or $heart eq "NACK" and @{$hash->{IODev}->{messagesForRadioId}->{$hash->{radioId}}->{messages}} == 0) {
          readingsSingleUpdate($hash,"heartbeat","alive",1);
      }
    } elsif ($calltype eq "Ack") {
      RemoveInternalTimer($hash,"MYSENSORS::DEVICE::timeoutAck");
      my $nextTrigger = gettimeofday() + $hash->{timeoutAck};
      InternalTimer($nextTrigger, "MYSENSORS::DEVICE::timeoutAck",$hash);
      Log3 $name, 5, "$name: Ack timeout timer set at $nextTrigger";
    } elsif ($calltype eq "Asleep") {
      RemoveInternalTimer($hash,"MYSENSORS::DEVICE::timeoutAwake");
      my $postsleeptime=($hash->{preSleep} - 200)/1000;
      $postsleeptime=0 if $postsleeptime < 0;
      my $nextTrigger = gettimeofday() + $postsleeptime;  
      InternalTimer($nextTrigger, "MYSENSORS::DEVICE::timeoutAwake",$hash);
      Log3 $name, 5, "$name: Awake timeout timer set at $nextTrigger";
    }
    return;
}

sub timeoutAlive {
    my $hash = shift // return;
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: timeoutAlive called";
    readingsSingleUpdate($hash,"heartbeat","dead",1) unless (ReadingsVal($hash,"heartbeat","dead") eq "NACK");
    return;
}

sub timeoutAck {
    my $hash = shift // return;
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: timeoutAck called";
    if ($hash->{IODev}->{outstandingAck} == 0) {
      Log3 $hash->{NAME}, 4, "$hash->{NAME}: timeoutAck called, no outstanding Acks at all";
      readingsSingleUpdate($hash,"heartbeat","alive",1) if (ReadingsVal($hash,"heartbeat","dead") eq "NACK");
    } elsif (my $outs = $hash->{IODev}->{messagesForRadioId}->{$hash->{radioId}}->{messages}) {
      my $outstanding = @$outs;
      Log3 $hash->{NAME}, 4, "$hash->{NAME}: timeoutAck called, outstanding: $outstanding";
      readingsSingleUpdate($hash,"heartbeat","NACK",1) ;
    } else {
      Log3 $hash->{NAME}, 4, "$hash->{NAME}: timeoutAck called, no outstanding Acks for Node";
      readingsSingleUpdate($hash,"heartbeat","alive",1) if (ReadingsVal($hash,"heartbeat","dead") eq "NACK");
    }
    return;
}

sub timeoutAwake {
    my $hash = shift // return;
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: timeoutAwake called";
    readingsSingleUpdate($hash,"sleepState","asleep",1);
    $hash->{nowSleeping} = 1;
    return;
}

sub sendRetainedMessages {
    my $hash = shift // return;
    my $retainedMsg;
    while (ref ($retainedMsg = shift @{$hash->{retainedMessagesForRadioId}->{messages}}) eq 'HASH') {
       sendClientMessage($hash,%$retainedMsg);
    }
    return;
}
1;

__END__

=pod
=item device
=item summary includes MYSENSOR clients
=item summary_DE integriert MYSENSOR Sensoren

=begin html

<a name="MYSENSORS_DEVICE"></a>
<h3>MYSENSORS_DEVICE</h3>
<ul>
    <p>represents a mysensors sensor attached to a mysensor-node</p>
    <p>requires a <a href="#MYSENSORS">MYSENSORS</a>-device as IODev</p>
    <a name="MYSENSORS_DEVICE define"></a>
    <p><b>Define</b></p>
    <ul>
    <p><code>define &lt;name&gt; MYSENSORS_DEVICE &lt;Sensor-type&gt; &lt;node-id&gt;</code><br/>Specifies the MYSENSOR_DEVICE device.</p>
    </ul>
    <a name="MYSENSORS_DEVICEset"></a>
    <p><b>Set</b></p>
    <ul>
      <b>AttrTemplate</b>
      <li>Helps to easily configure your devices. Just get a list of all available attrTremplates by issuing
      <ul>
        <p><code>set &lt;name&gt; attrTemplate ?</code></p>
      </ul>
      Have a look at the descriptions and choose a suitable one. Then use the drop-down list and click "set" or issue a.<br>
      <ul>
        <p><code>set &lt;name&gt; attrTemplate A_02a_atmospheric_pressure</code></p>
      </ul>
      </li><br>
      <b>clear</b>
      <li>
         <p><code>set &lt;name&gt; clear</code><br/>clears MySensors EEPROM area and reboot (i.e. "factory" reset) - requires MY_SPECIAL_DEBUG</p>
      </li>
      <b>flash</b>
      <li>
         <p><code>set &lt;name&gt; flash</code><br/>
         Checks whether a newer firmware version is available. If a newer firmware version is
         available the flash procedure is started. The sensor node must support FOTA for
         this.</p>
      </li>
      <b>fwType</b>
      <li>
         <p><code>set &lt;name&gt; fwType &lt;value&gt;</code><br/>
         assigns a firmware type to this node (must be a numeric value in the range 0 .. 65536).
         Should be contained in the <a href="#MYSENSORSattrOTA_firmwareConfig">FOTA configuration
         file</a>.</p>
      </li>
      <b>time</b>
      <li>
        <p><code>set &lt;name&gt; time</code><br/>sets time for nodes (that support it)</p>
      </li>
      <b>reboot</b>
      <li>
        <p><code>set &lt;name&gt; reboot</code><br/>reboots a node (requires a bootloader that supports it).<br/>Attention: Nodes that run the standard arduino-bootloader will enter a bootloop!<br/>Dis- and reconnect the nodes power to restart in this case.</p>
    </li>

    </ul>
  <a name="MYSENSORS_DEVICEget"></a>
   <p><b>Get</b></p>
     <ul>
       <li>
         <p><code>get &lt;name&gt; Extended_DEBUG</code><br/>
           requires MY_SPECIAL_DEBUG</p>
       retrieves the CPU frequency, CPU voltage and free memory of the sensor</p>
       </li>
     </ul>
     <ul>
       <li>
         <p><code>get &lt;name&gt; ReadingsFromComment</code><br/>
           rebuild reding names from comments of presentation messages if available</p>
    After issuing this get check the log for changes. </p>
       </li>
     </ul>
    
     <ul>
      <li>
            <p><code>get &lt;name&gt; RSSI</code><br/>
            requires MY_SIGNAL_REPORT_ENABLED, not supported by all transportation layers</p>
        delievers a set of Signal Quality information.</p>
         </li>
    </ul>
    <a name="MYSENSORS_DEVICEattr"></a>
    <p><b>Attributes</b></p>
    <ul>
    <li>
        <p><code>attr &lt;name&gt; config [&lt;M|I&gt;]</code><br/>configures metric (M) or inch (I). Defaults to 'M'</p>
    </li>
    <li>
         <p><code>attr &lt;name&gt; OTA_autoUpdate [&lt;0|1&gt;]</code><br/>
          specifies whether an automatic update of the sensor node should be performed (1) during startup of the
          node or not (0). Defaults to 0</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; setCommands [&lt;command:reading:value&gt;]*</code><br/>configures one or more commands that can be executed by set.<br/>e.g.: <code>attr &lt;name&gt; setCommands on:switch_1:on off:switch_1:off</code><br/>if list of commands contains both 'on' and 'off' <a href="#setExtensions">set extensions</a> are supported</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; setReading_&lt;reading&gt; [&lt;value&gt;]*</code><br/>configures a reading that can be modified by set-command<br/>e.g.: <code>attr &lt;name&gt; setReading_switch_1 on,off</code></p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; setExtensionsEvent</code><br/>If set, the event will contain the command implemented by SetExtensions
      (e.g. on-for-timer 10), else the executed command (e.g. on).
    </li>
    <li>
        <p><code>attr &lt;name&gt; mapReading_&lt;reading&gt; &lt;childId&gt; &lt;readingtype&gt; [&lt;value&gt;:&lt;mappedvalue&gt;]*</code><br/>configures the reading-name for a given childId and sensortype<br/>e.g.: <code>attr xxx mapReading_aussentemperatur 123 temperature</code>
    or <code>attr xxx mapReading_leftwindow 10 status 1:closed 0:open</code>. See also mapReadingType for setting defaults for types without predefined defaults</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; requestAck</code><br/>request acknowledge from nodes.<br/>if set the Readings of nodes are updated not before requested acknowledge is received<br/>if not set the Readings of nodes are updated immediatly (not awaiting the acknowledge).<br/>May also be configured on the gateway for all nodes at once</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; mapReadingType_&lt;reading&gt; &lt;new reading name&gt; [&lt;value&gt;:&lt;mappedvalue&gt;]*</code><br/>configures reading type names that should be used instead of technical names<br/>e.g.: <code>attr xxx mapReadingType_LIGHT switch 0:on 1:off</code>to be used for mysensor Variabletypes that have no predefined defaults (yet)</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; OTA_BL_Type &lt;either Optiboot or MYSBootloader&gt;*</code><br/>For other bootloaders than Optiboot V3.0 OTA updates will only work if bootloader type is specified - MYSBootloader will reboot node if firmware update is started, so make sure, node will really recover</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; OTA_Chan76_IODev </code><br/>As MYSBootloader per default uses nRF24 channel 76, you may specify a different IODev for OTA data using channel 76</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; timeoutAck &lt;time in seconds&gt;*</code><br/>configures timeout to set device state to NACK in case not all requested acks are received</p>
    </li>
    <li>
        <p><code>attr &lt;name&gt; timeoutAlive &lt;time in seconds&gt;*</code><br/>configures timeout to set device state to alive or dead. If messages from node are received within timout spec, state will be alive, otherwise dead. If state is NACK (in case timeoutAck is also set), state will only be changed to alive, if there are no outstanding messages to be sent.</p>
    </li>
</ul>
</ul>

=end html
=cut
