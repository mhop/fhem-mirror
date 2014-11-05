##############################################
#
# fhem bridge to MySensors (see http://mysensors.org)
#
# Copyright (C) 2014 Norbert Truchsess
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

use strict;
use warnings;

my %gets = (
  "version"   => "",
);

sub MYSENSORS_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MYSENSORS::DEVICE::Define";
  $hash->{UndefFn}  = "MYSENSORS::DEVICE::UnDefine";
  $hash->{SetFn}    = "MYSENSORS::DEVICE::Set";
  $hash->{AttrFn}   = "MYSENSORS::DEVICE::Attr";
  
  $hash->{AttrList} =
    "config:M,I ".
    "mode:node,repeater ".
    "version:1.4 ".
    "setCommands ".
    "setReading_.+ ".
    "mapReadingType_.+ ".
    "mapReading_.+ ".
    "requestAck:1 ". 
    "IODev ".
    $main::readingFnAttributes;

  main::LoadModule("MYSENSORS");
}

package MYSENSORS::DEVICE;

use strict;
use warnings;
use GPUtils qw(:all);

use Device::MySensors::Constants qw(:all);
use Device::MySensors::Message qw(:all);

BEGIN {
  MYSENSORS->import(qw(:all));

  GP_Import(qw(
    AttrVal
    readingsSingleUpdate
    CommandAttr
    CommandDeleteAttr
    CommandDeleteReading
    AssignIoPort
    Log3
  ))
};

my %static_types = (
  S_DOOR                  => { receives => [], sends => [V_TRIPPED] }, # BinarySwitchSensor
  S_MOTION                => { receives => [], sends => [V_TRIPPED] }, # MotionSensor
  S_SMOKE                 => { receives => [], sends => [] }, # Not used so far
  S_LIGHT                 => { receives => [V_LIGHT], sends => [V_LIGHT] }, # BinarySwitchSensor
  S_DIMMER                => { receives => [V_LIGHT,V_DIMMER], sends => [V_LIGHT,V_DIMMER] }, # DimmableLEDActuator
  S_COVER                 => { receives => [V_DIMMER,V_UP,V_DOWN,V_STOP], sends => [V_DIMMER] }, # ServoActuator
  S_TEMP                  => { receives => [], sends => [V_TEMP] }, # DallasTemperatureSensor
  S_HUM                   => { receives => [], sends => [V_HUM] }, # HumiditySensor
  S_BARO                  => { receives => [], sends => [V_PRESSURE,V_FORECAST] },
  S_WIND                  => { receives => [], sends => [] }, # Not used so far
  S_RAIN                  => { receives => [], sends => [] }, # Not used so far
  S_UV                    => { receives => [], sends => [V_UV] }, # UVSensor
  S_WEIGHT                => { receives => [], sends => [] }, # Not used so far
  S_POWER                 => { receives => [V_VAR1], sends => [V_WATT,V_KWH,V_VAR1] }, # EnergyMeterPulseSensor
  S_HEATER                => { receives => [], sends => [] }, # Not used so far
  S_DISTANCE              => { receives => [], sends => [V_DISTANCE] }, # DistanceSensor
  S_LIGHT_LEVEL           => { receives => [], sends => [V_LIGHT_LEVEL] }, # LightSensor
  S_ARDUINO_NODE          => { receives => [], sends => [] }, # Not used so far
  S_ARDUINO_REPEATER_NODE => { receives => [], sends => [] }, # Not used so far
  S_LOCK                  => { receives => [V_LOCK_STATUS], sends => [V_LOCK_STATUS] }, #R FIDLockSensor
  S_IR                    => { receives => [], sends => [] }, # Not used so far
  S_WATER                 => { receives => [V_VAR1], sends => [V_FLOW,V_VOLUME] }, # WaterMeterPulseSensor
  S_AIR_QUALITY           => { receives => [], sends => [V_VAR1] }, # AirQualitySensor
  S_CUSTOM                => { receives => [], sends => [] }, # Not used so far
  S_DUST                  => { receives => [], sends => [V_DUST_LEVEL] }, # Not used so far
  S_SCENE_CONTROLLER      => { receives => [], sends => [V_SCENE_ON,V_SCENE_OFF] }, # TouchDisplaySceneControllerDisplaySensor
);

my %static_mappings = (
  V_TEMP        => { type => "temperature" },
  V_HUM         => { type => "humidity", range => { min => 0, max => 100 }},
  V_PRESSURE    => { type => "pressure" },
  V_LIGHT_LEVEL => { type => "brightness" },
  V_LIGHT       => { type => "switch", val => { 0 => 'off', 1 => 'on' }},
  V_DIMMER      => { type => "dimmer", range => { min => 0, max => 100 }},
  V_FORECAST    => { type => "forecast", val => { # PressureSensor, DP/Dt explanation
                                                  0 => 'stable',       # 0 = "Stable Weather Pattern"
                                                  1 => 'slow rising',  # 1 = "Slowly rising Good Weather", "Clear/Sunny "
                                                  2 => 'slow falling', # 2 = "Slowly falling L-Pressure ", "Cloudy/Rain "
                                                  3 => 'quick rising', # 3 = "Quickly rising H-Press",     "Not Stable"
                                                  4 => 'quick falling',# 4 = "Quickly falling L-Press",    "Thunderstorm"
                                                  5 => 'unknown' }},   # 5 = "Unknown (More Time needed) 
  V_RAIN        => { type => "rain" },
  V_RAINRATE    => { type => "rainrate" },
  V_WIND        => { type => "wind" },
  V_GUST        => { type => "gust" },
  V_DIRECTION   => { type => "direction" },
  V_UV          => { type => "uv" },
  V_WEIGHT      => { type => "weight" },
  V_DISTANCE    => { type => "distance" },
  V_IMPEDANCE   => { type => "impedance" },
  V_ARMED       => { type => "armed" },
  V_TRIPPED     => { type => "tripped" },
  V_WATT        => { type => "power" },
  V_KWH         => { type => "energy" },
  V_SCENE_ON    => { type => "button_on" },
  V_SCENE_OFF   => { type => "button_off" },
  V_HEATER      => { type => "heater" },
  V_HEATER_SW   => { type => "heater_sw" },
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
  V_LOCK_STATUS => { type => "lockstatus", val => { 0 => 'locked', 1 => 'unlocked' }},
  V_DUST_LEVEL  => { type => "dustlevel" },
  V_VOLTAGE     => { type => "voltage" },
  V_CURRENT     => { type => "current" },
);

sub Define($$) {
  my ( $hash, $def ) = @_;
  my ($name, $type, $radioId) = split("[ \t]+", $def);
  return "requires 1 parameters" unless (defined $radioId and $radioId ne "");
  $hash->{radioId} = $radioId;
  $hash->{sets} = {
    'time' => "",
    reboot => "",
  };
  $hash->{ack} = 0;
  $hash->{typeMappings} = {map {variableTypeToIdx($_) => $static_mappings{$_}} keys %static_mappings};
  $hash->{sensorMappings} = {map {sensorTypeToIdx($_) => $static_types{$_}} keys %static_types};
  
  $hash->{readingMappings} = {};
  AssignIoPort($hash);
};

sub UnDefine($) {
  my ($hash) = @_;
  
  return undef;
}

sub Set($@) {
  my ($hash,$name,$command,@values) = @_;
  return "Need at least one parameters" unless defined $command;
  return "Unknown argument $command, choose one of " . join(" ", map {$hash->{sets}->{$_} ne "" ? "$_:$hash->{sets}->{$_}" : $_} sort keys %{$hash->{sets}})
    if(!defined($hash->{sets}->{$command}));
  COMMAND_HANDLER: {
    $command eq "clear" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_CHILDREN, payload => "C");
      last;
    };
    $command eq "time" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_TIME, payload => time);
      last;
    };
    $command eq "reboot" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_REBOOT);
      last;
    };
    (defined ($hash->{setcommands}->{$command})) and do {
      my $setcommand = $hash->{setcommands}->{$command};
      eval {
        my ($type,$childId,$mappedValue) = mappedReadingToRaw($hash,$setcommand->{var},$setcommand->{val});
        sendClientMessage($hash,
          childId => $childId,
          cmd => C_SET,
          subType => $type,
          payload => $mappedValue,
        );
        readingsSingleUpdate($hash,$setcommand->{var},$setcommand->{val},1) unless ($hash->{ack} or $hash->{IODev}->{ack});
      };
      return "$command not defined: ".GP_Catch($@) if $@;
      last;
    };
    my $value = @values ? join " ",@values : "";
    eval {
      my ($type,$childId,$mappedValue) = mappedReadingToRaw($hash,$command,$value);
      sendClientMessage($hash, childId => $childId, cmd => C_SET, subType => $type, payload => $mappedValue);
      readingsSingleUpdate($hash,$command,$value,1) unless ($hash->{ack} or $hash->{IODev}->{ack});
    };
    return "$command not defined: ".GP_Catch($@) if $@;
  }
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute eq "config" and do {
      if ($main::init_done) {
        sendClientMessage($hash, cmd => C_INTERNAL, childId => 255, subType => I_CONFIG, payload => $command eq 'set' ? $value : "M");
      }
      last;
    };
    $attribute eq "mode" and do {
      if ($command eq "set" and $value eq "repeater") {
        $hash->{repeater} = 1;
        $hash->{sets}->{clear} = "";
      } else {
        $hash->{repeater} = 0;
        delete $hash->{sets}->{clear};
      }
      last;
    };
    $attribute eq "version" and do {
      if ($command eq "set") {
        $hash->{protocol} = $value;
      } else {
        delete $hash->{protocol};
      }
      last;
    };
    $attribute eq "setCommands" and do {
      foreach my $set (keys %{$hash->{setcommands}}) {
        delete $hash->{sets}->{$set};
      }
      $hash->{setcommands} = {};
      if ($command eq "set" and $value) {
        foreach my $setCmd (split ("[, \t]+",$value)) {
          if ($setCmd =~ /^(.+):(.+):(.+)$/) {
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
      last;
    };
    $attribute =~ /^setReading_(.+)$/ and do {
      if ($command eq "set") {
        $hash->{sets}->{$1}= (defined $value) ? join(",",split ("[, \t]+",$value)) : "";
      } else {
        CommandDeleteReading(undef,"$hash->{NAME} $1");
        delete $hash->{sets}->{$1};
      }
      last;
    };
    $attribute =~ /^mapReadingType_(.+)/ and do {
      my $type = variableTypeToIdx("V_$1");
      if ($command eq "set") {
        my @values = split ("[, \t]",$value);
        $hash->{typeMappings}->{$type}={
          type => shift @values,
          val => {map {$_ =~ /^(.+):(.+)$/; $1 => $2} @values},
        }
      } else {
        if ($static_mappings{"V_$1"}) {
          $hash->{typeMappings}->{$type}=$static_mappings{"V_$1"};
        } else {
          delete $hash->{typeMappings}->{$type};
        }
        my $readings = $hash->{READINGS};
        my $readingMappings = $hash->{readingMappings};
        foreach my $todelete (map {$readingMappings->{$_}->{name}} grep {$readingMappings->{$_}->{type} == $type} keys %$readingMappings) {
          CommandDeleteReading(undef,"$hash->{NAME} $todelete"); #TODO do propper remap of existing readings
        }
      }
      last;
    };
    $attribute =~ /^mapReading_(.+)/ and do {
      my $readingMappings = $hash->{readingMappings};
      FIND: foreach my $id (keys %$readingMappings) {
        my $readingsForId = $readingMappings->{$id};
        foreach my $type (keys %$readingsForId) {
          if ($readingsForId->{$type}->{name} // "" eq $1) {
            delete $readingsForId->{$type};
            unless (keys %$readingsForId) {
              delete $readingMappings->{$id};
            }
            last FIND;
          }
        }
      }
      if ($command eq "set") {
        my ($id,$typeStr,@values) = split ("[, \t]",$value);
        my $typeMappings = $hash->{typeMappings};
        if (my @match = grep {$typeMappings->{$_}->{type} eq $typeStr} keys %$typeMappings) {
          my $type = shift @match;
          $hash->{readingMappings}->{$id}->{$type} = {
            name => $1,
          };
          if (@values) {
            $hash->{readingMappings}->{$id}->{$type}->{val} = {map {$_ =~ /^(.+):(.+)$/; $1 => $2} @values}; #TODO range?
          }
        } else {
          return "unknown reading type $typeStr";
        }
      } else {
        CommandDeleteReading(undef,"$hash->{NAME} $1");
      }
      last;
    };
    $attribute eq "requestAck" and do {
      if ($command eq "set") {
        $hash->{ack} = 1;
      } else {
        $hash->{ack} = 0;
      }
      last;
    };
  }
}

sub onGatewayStarted($) {
  my ($hash) = @_;
}

sub onPresentationMessage($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $nodeType = $msg->{subType};
  my $id = $msg->{childId};
  if ($id == 255) { #special id
    NODETYPE: {
      $nodeType == S_ARDUINO_NODE and do {
        CommandAttr(undef, "$name mode node");
        last;
      };
      $nodeType == S_ARDUINO_REPEATER_NODE and do {
        CommandAttr(undef, "$name mode repeater");
        last;
      };
    };
    CommandAttr(undef, "$name version $msg->{payload}");
  };

  my $readingMappings = $hash->{readingMappings};
  my $typeMappings = $hash->{typeMappings};
  if (my $sensorMappings = $hash->{sensorMappings}->{$nodeType}) {
    my $idStr = ($id > 1 ? $id : "");
    my @ret = ();
    foreach my $type (@{$sensorMappings->{sends}}) {
      next if (defined $readingMappings->{$id}->{$type});
      my $typeStr = $typeMappings->{$type}->{type};
      if ($hash->{IODev}->{'inclusion-mode'}) {
        if (my $ret = CommandAttr(undef,"$name mapReading_$typeStr$idStr $id $typeStr")) {
          push @ret,$ret;
        }
      } else {
        push @ret,"no mapReading for $id, $typeStr";
      }
    }
    foreach my $type (@{$sensorMappings->{receives}}) {
      my $typeMapping = $typeMappings->{$type};
      my $typeStr = $typeMapping->{type};
      next if (defined $hash->{sets}->{"$typeStr$idStr"});
      if ($hash->{IODev}->{'inclusion-mode'}) {
        if (my $ret = CommandAttr(undef,"$name setReading_$typeStr$idStr".($typeMapping->{val} ? " ".join (",",values %{$typeMapping->{val}}) : ""))) {
          push @ret,$ret;
        }
      } else {
        push @ret,"no setReading for $id, $typeStr";
      }
    }
    Log3 ($hash->{NAME},4,"MYSENSORS_DEVICE $hash->{NAME}: errors on C_PRESENTATION-message for childId $id, subType ".sensorTypeToStr($nodeType)." ".join (", ",@ret)) if @ret;
  }
}

sub onSetMessage($$) {
  my ($hash,$msg) = @_;
  if (defined $msg->{payload}) {
    eval {
      my ($reading,$value) = rawToMappedReading($hash,$msg->{subType},$msg->{childId},$msg->{payload});
      readingsSingleUpdate($hash,$reading,$value,1);
    };
    Log3 ($hash->{NAME},4,"MYSENSORS_DEVICE $hash->{NAME}: ignoring C_SET-message ".GP_Catch($@)) if $@;
  } else {
    Log3 ($hash->{NAME},5,"MYSENSORS_DEVICE $hash->{NAME}: ignoring C_SET-message without payload");
  }
}

sub onRequestMessage($$) {
  my ($hash,$msg) = @_;
  variableTypeToStr($msg->{subType}) =~ /^V_(.+)$/;
  sendClientMessage($hash,
    childId => $msg->{childId},
    cmd => C_SET,
    subType => $msg->{subType},
    payload => ReadingsVal($hash->{NAME},"$1\_$msg->{childId}","")
  );
}

sub onInternalMessage($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $type = $msg->{subType};
  my $typeStr = internalMessageTypeToStr($type);
  INTERNALMESSAGE: {
    $type == I_BATTERY_LEVEL and do {
      readingsSingleUpdate($hash,"batterylevel",$msg->{payload},1);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: batterylevel $msg->{payload}");
      last;
    };
    $type == I_TIME and do {
      if ($msg->{ack}) {
        Log3 ($name,4,"MYSENSORS_DEVICE $name: respons to time-request acknowledged");
      } else {
        sendClientMessage($hash,cmd => C_INTERNAL, childId => 255, subType => I_TIME, payload => time);
        Log3 ($name,4,"MYSENSORS_DEVICE $name: update of time requested");
      }
      last;
    };
    $type == I_VERSION and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_ID_REQUEST and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_ID_RESPONSE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_INCLUSION_MODE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_CONFIG and do {
      if ($msg->{ack}) {
        Log3 ($name,4,"MYSENSORS_DEVICE $name: respons to config-request acknowledged");
      } else {
        sendClientMessage($hash,cmd => C_INTERNAL, childId => 255, subType => I_CONFIG, payload => AttrVal($name,"config","M"));
        Log3 ($name,4,"MYSENSORS_DEVICE $name: respond to config-request");
      }
      last;
    };
    $type == I_PING and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_PING_ACK and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_LOG_MESSAGE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_CHILDREN and do {
      readingsSingleUpdate($hash,"state","routingtable cleared",1);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: routingtable cleared");
      last;
    };
    $type == I_SKETCH_NAME and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_SKETCH_VERSION and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_REBOOT and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
  }
}

sub sendClientMessage($%) {
  my ($hash,%msg) = @_;
  $msg{radioId} = $hash->{radioId};
  $msg{ack} = 1 if $hash->{ack};
  sendMessage($hash->{IODev},%msg);
}

sub rawToMappedReading($$$$) {
  my($hash, $type, $childId, $value) = @_;

  my $name;
  if (defined (my $mapping = $hash->{readingMappings}->{$childId}->{$type})) {
    if(defined (my $val = $mapping->{val} // $hash->{typeMappings}->{$type}->{val})) {
      return ($mapping->{name},$val->{$value} // $value);
    }
    die "not type-mapping for type ".variableTypeToStr($type);
  }
  die "no reading-mapping for childId $childId, type ".($hash->{typeMappings}->{$type}->{type} ? $hash->{typeMappings}->{$type}->{type} : variableTypeToStr($type));
}

sub mappedReadingToRaw($$$) {
  my ($hash,$reading,$value) = @_;
  
  my $readingsMapping = $hash->{readingMappings};
  foreach my $id (keys %$readingsMapping) {
    my $readingTypesForId = $readingsMapping->{$id};
    foreach my $type (keys %$readingTypesForId) {
      if (($readingTypesForId->{$type}->{name} // "") eq $reading) {
        if (my $valueMappings = $readingTypesForId->{$type}->{val} // $hash->{typeMappings}->{$type}->{val}) {
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

1;

=pod
=begin html

<a name="MYSENSORS_DEVICE"></a>
<h3>MYSENSORS_DEVICE</h3>
<ul>
  <p>represents a mysensors sensor attached to a mysensor-node</p>
  <p>requires a <a href="#MYSENSOR">MYSENSOR</a>-device as IODev</p>
  <a name="MYSENSORS_DEVICEdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MYSENSORS_DEVICE &lt;Sensor-type&gt; &lt;node-id&gt;</code><br/>
      Specifies the MYSENSOR_DEVICE device.</p>
  </ul>
  <a name="MYSENSORS_DEVICEset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; clear</code><br/>
         clears routing-table of a repeater-node</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; time</code><br/>
         sets time for nodes (that support it)</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; reboot</code><br/>
         reboots a node (requires a bootloader that supports it).<br/>
         Attention: Nodes that run the standard arduino-bootloader will enter a bootloop!<br/>
         Dis- and reconnect the nodes power to restart in this case.</p>
    </li>
  </ul>
  <a name="MYSENSORS_DEVICEattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; config [&lt;M|I&gt;]</code><br/>
         configures metric (M) or inch (I). Defaults to 'M'</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; setCommands [&lt;command:reading:value&gt;]*</code><br/>
         configures one or more commands that can be executed by set.<br/>
         e.g.: <code>attr &lt;name&gt; setCommands on:switch_1:on off:switch_1:off</code></p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; setReading_&lt;reading&gt; [&lt;value&gt;]*</code><br/>
         configures a reading that can be modified by set-command<br/>
         e.g.: <code>attr &lt;name&gt; setReading_switch_1 on,off</code></p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; mapReading_&lt;reading&gt; &lt;childId&gt; &lt;readingtype&gt; [&lt;value&gt;:&lt;mappedvalue&gt;]*</code><br/>
         configures the reading-name for a given childId and sensortype<br/>
         E.g.: <code>attr xxx mapReading_aussentemperatur 123 temperature</code></p>
    </li>
    <li>
      <p><code>att &lt;name&gt; requestAck</code><br/>
         request acknowledge from nodes.<br/>
         if set the Readings of nodes are updated not before requested acknowledge is received<br/>
         if not set the Readings of nodes are updated immediatly (not awaiting the acknowledge).<br/>
         May also be configured on the gateway for all nodes at once</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; mapReadingType_&lt;reading&gt; &lt;new reading name&gt; [&lt;value&gt;:&lt;mappedvalue&gt;]*</code><br/>
         configures reading type names that should be used instead of technical names<br/>
         E.g.: <code>attr xxx mapReadingType_LIGHT switch 0:on 1:off</code>
         to be used for mysensor Variabletypes that have no predefined defaults (yet)</p>
    </li>
  </ul>
</ul>

=end html
=cut
