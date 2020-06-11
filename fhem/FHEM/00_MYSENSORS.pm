##############################################
#
# fhem driver for MySensors serial or network gateway (see http://mysensors.org)
#
# Copyright (C) 2014 Norbert Truchsess
# Copyright (C) 2019 Hauswart@forum.fhem.de
# Copyright (C) 2019 Beta-User@forum.fhem.de
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

package MYSENSORS; ## no critic 'Package declaration'
## no critic 'constant'

use strict;
use warnings;

use List::Util qw(first); 
use Exporter ('import');

use DevIo;
use GPUtils qw(:all);

sub main::MYSENSORS_Initialize { goto &Initialize };

my %sets = (
  "connect" => [],
  "disconnect" => [],
  "inclusion-mode" => [qw(on off)],
);

my %gets = (
  "version"   => ""
);

my @clients = qw(
  MYSENSORS_DEVICE
);

sub Initialize {

  my $hash = shift // return;

  # Provider
  $hash->{Clients} = join (':',@clients);
  $hash->{ReadyFn} = \&Ready;
  $hash->{ReadFn}  = \&Read;

  # Consumer
  $hash->{DefFn}    = \&Define;
  $hash->{UndefFn}  = \&Undef;
  $hash->{SetFn}    = \&Set;
  $hash->{AttrFn}   = \&Attr;

   my @attrList = qw(
    autocreate:1
    requestAck:1
    first-sensorid
    last-sensorid
    stateFormat
    OTA_firmwareConfig
  );
  $hash->{AttrList} = $hash->{AttrList} = join(" ", @attrList);
  return;
}


BEGIN {GP_Import(qw(
  init_done
  defs
  CommandDefine
  CommandModify
  CommandAttr
  gettimeofday
  readingsSingleUpdate
  DevIo_OpenDev
  DevIo_SimpleWrite
  DevIo_SimpleRead
  DevIo_CloseDev
  RemoveInternalTimer
  InternalTimer
  AttrVal
  Log3
  FileRead
  ))};

my %sensorAttr = (
  LIGHT => ['setCommands on:V_LIGHT:1 off:V_LIGHT:0' ],
  ARDUINO_NODE => [ 'config M' ],
  ARDUINO_REPEATER_NODE => [ 'config M' ],
);

sub Define {
  my $hash = shift // return;

  InternalTimer(time(), "MYSENSORS::Start", $hash,0); 
  return;
}

sub Undef {
  Stop(shift);
  return;
}

#-- Message types
use constant {
  C_PRESENTATION => 0,
  C_SET          => 1,
  C_REQ          => 2,
  C_INTERNAL     => 3,
  C_STREAM       => 4,
};

use constant commands => qw( C_PRESENTATION C_SET C_REQ C_INTERNAL C_STREAM );

sub commandToStr {
    return (commands)[shift];
}

#-- Variable types
use constant {
  V_TEMP               => 0,
  V_HUM                => 1,
  V_STATUS             => 2,
  V_PERCENTAGE         => 3,
  V_PRESSURE           => 4,
  V_FORECAST           => 5,
  V_RAIN               => 6,
  V_RAINRATE           => 7,
  V_WIND               => 8,
  V_GUST               => 9,
  V_DIRECTION          => 10,
  V_UV                 => 11,
  V_WEIGHT             => 12,
  V_DISTANCE           => 13,
  V_IMPEDANCE          => 14,
  V_ARMED              => 15,
  V_TRIPPED            => 16,
  V_WATT               => 17,
  V_KWH                => 18,
  V_SCENE_ON           => 19,
  V_SCENE_OFF          => 20,
  V_HVAC_FLOW_STATE    => 21,
  V_HVAC_SPEED         => 22,
  V_LIGHT_LEVEL        => 23,
  V_VAR1               => 24,
  V_VAR2               => 25,
  V_VAR3               => 26,
  V_VAR4               => 27,
  V_VAR5               => 28,
  V_UP                 => 29,
  V_DOWN               => 30,
  V_STOP               => 31,
  V_IR_SEND            => 32,
  V_IR_RECEIVE         => 33,
  V_FLOW               => 34,
  V_VOLUME             => 35,
  V_LOCK_STATUS        => 36,
  V_LEVEL              => 37,
  V_VOLTAGE            => 38,
  V_CURRENT            => 39,
  V_RGB                => 40,
  V_RGBW               => 41,
  V_ID                 => 42,
  V_UNIT_PREFIX        => 43,
  V_HVAC_SETPOINT_COOL => 44,
  V_HVAC_SETPOINT_HEAT => 45,
  V_HVAC_FLOW_MODE     => 46,
  V_TEXT               => 47,
  V_CUSTOM             => 48,
  V_POSITION           => 49,
  V_IR_RECORD          => 50,
  V_PH                 => 51,
  V_ORP                => 52,
  V_EC                 => 53,
  V_VAR                => 54,
  V_VA                 => 55,
  V_POWER_FACTOR       => 56,
};

use constant variableTypes => qw( 
   V_TEMP V_HUM V_STATUS V_PERCENTAGE V_PRESSURE V_FORECAST V_RAIN
   V_RAINRATE V_WIND V_GUST V_DIRECTION V_UV V_WEIGHT V_DISTANCE
   V_IMPEDANCE V_ARMED V_TRIPPED V_WATT V_KWH V_SCENE_ON V_SCENE_OFF
   V_HVAC_FLOW_STATE V_HVAC_SPEED V_LIGHT_LEVEL 
   V_VAR1 V_VAR2 V_VAR3 V_VAR4 V_VAR5
   V_UP V_DOWN V_STOP V_IR_SEND V_IR_RECEIVE V_FLOW V_VOLUME V_LOCK_STATUS 
   V_LEVEL V_VOLTAGE V_CURRENT V_RGB V_RGBW V_ID V_UNIT_PREFIX
   V_HVAC_SETPOINT_COOL V_HVAC_SETPOINT_HEAT V_HVAC_FLOW_MODE
   V_TEXT V_CUSTOM V_POSITION V_IR_RECORD V_PH V_ORP V_EC 
   V_VAR V_VA V_POWER_FACTOR 
);

sub variableTypeToStr {
  return (variableTypes)[shift];
}

sub variableTypeToIdx {
  my $var = shift // return;
  return first { (variableTypes)[$_] eq $var } 0 .. scalar(variableTypes);
}

#-- Internal messages
use constant {
  I_BATTERY_LEVEL           => 0,
  I_TIME                    => 1,
  I_VERSION                 => 2,
  I_ID_REQUEST              => 3,
  I_ID_RESPONSE             => 4,
  I_INCLUSION_MODE          => 5,
  I_CONFIG                  => 6,
  I_FIND_PARENT             => 7,
  I_FIND_PARENT_RESPONSE    => 8,
  I_LOG_MESSAGE             => 9,
  I_CHILDREN                => 10,
  I_SKETCH_NAME             => 11,
  I_SKETCH_VERSION          => 12,
  I_REBOOT                  => 13,
  I_GATEWAY_READY           => 14,
  I_REQUEST_SIGNING         => 15,
  I_GET_NONCE               => 16,
  I_GET_NONCE_RESPONSE      => 17,
  I_HEARTBEAT_REQUEST       => 18,
  I_PRESENTATION            => 19,
  I_DISCOVER_REQUEST        => 20,
  I_DISCOVER_RESPONSE       => 21,
  I_HEARTBEAT_RESPONSE      => 22,
  I_LOCKED                  => 23, # Node is locked (reason in string-payload)
  I_PING                    => 24, # Ping sent to node, payload incremental hop counter
  I_PONG                    => 25, # In return to ping, sent back to sender, payload incremental hop counter
  I_REGISTRATION_REQUEST    => 26, # Register request to GW
  I_REGISTRATION_RESPONSE   => 27, # Register response from GW
  I_DEBUG                   => 28, 
  I_SIGNAL_REPORT_REQUEST   => 29,
  I_SIGNAL_REPORT_REVERSE   => 30,
  I_SIGNAL_REPORT_RESPONSE  => 31,
  I_PRE_SLEEP_NOTIFICATION  => 32,
  I_POST_SLEEP_NOTIFICATION => 33,
};

use constant internalMessageTypes => qw{ 
  I_BATTERY_LEVEL I_TIME I_VERSION I_ID_REQUEST I_ID_RESPONSE 
  I_INCLUSION_MODE I_CONFIG I_FIND_PARENT I_FIND_PARENT_RESPONSE 
  I_LOG_MESSAGE I_CHILDREN I_SKETCH_NAME I_SKETCH_VERSION 
  I_REBOOT I_GATEWAY_READY I_REQUEST_SIGNING I_GET_NONCE I_GET_NONCE_RESPONSE 
  I_HEARTBEAT_REQUEST I_PRESENTATION I_DISCOVER_REQUEST 
  I_DISCOVER_RESPONSE I_HEARTBEAT_RESPONSE I_LOCKED I_PING I_PONG
  I_REGISTRATION_REQUEST I_REGISTRATION_RESPONSE I_DEBUG 
  I_SIGNAL_REPORT_REQUEST I_SIGNAL_REPORT_REVERSE I_SIGNAL_REPORT_RESPONSE
  I_PRE_SLEEP_NOTIFICATION I_POST_SLEEP_NOTIFICATION };

sub internalMessageTypeToStr {
    return (internalMessageTypes)[shift];
}

#-- Sensor types
use constant {
  S_DOOR                  => 0,
  S_MOTION                => 1,
  S_SMOKE                 => 2,
  S_BINARY                => 3,
  S_DIMMER                => 4,
  S_COVER                 => 5,
  S_TEMP                  => 6,
  S_HUM                   => 7,
  S_BARO                  => 8,
  S_WIND                  => 9,
  S_RAIN                  => 10,
  S_UV                    => 11,
  S_WEIGHT                => 12,
  S_POWER                 => 13,
  S_HEATER                => 14,
  S_DISTANCE              => 15,
  S_LIGHT_LEVEL           => 16,
  S_ARDUINO_NODE          => 17,
  S_ARDUINO_REPEATER_NODE => 18,
  S_LOCK                  => 19,
  S_IR                    => 20,
  S_WATER                 => 21,
  S_AIR_QUALITY           => 22,
  S_CUSTOM                => 23,
  S_DUST                  => 24,
  S_SCENE_CONTROLLER      => 25,
  S_RGB_LIGHT             => 26,
  S_RGBW_LIGHT            => 27,
  S_COLOR_SENSOR          => 28,
  S_HVAC                  => 29,
  S_MULTIMETER            => 30,
  S_SPRINKLER             => 31,
  S_WATER_LEAK            => 32,
  S_SOUND                 => 33,
  S_VIBRATION             => 34,
  S_MOISTURE              => 35,
  S_INFO                  => 36,
  S_GAS                   => 37,
  S_GPS                   => 38,
  S_WATER_QUALITY         => 39,
};

use constant sensorTypes => qw{ 
  S_DOOR S_MOTION S_SMOKE S_BINARY S_DIMMER S_COVER S_TEMP S_HUM S_BARO S_WIND
  S_RAIN S_UV S_WEIGHT S_POWER S_HEATER S_DISTANCE S_LIGHT_LEVEL
  S_ARDUINO_NODE S_ARDUINO_REPEATER_NODE S_LOCK S_IR S_WATER S_AIR_QUALITY
  S_CUSTOM S_DUST S_SCENE_CONTROLLER S_RGB_LIGHT S_RGBW_LIGHT S_COLOR_SENSOR
  S_HVAC S_MULTIMETER S_SPRINKLER S_WATER_LEAK S_SOUND S_VIBRATION
  S_MOISTURE S_INFO S_GAS S_GPS S_WATER_QUALITY 
};

sub sensorTypeToStr {
  return (sensorTypes)[shift];
}

sub sensorTypeToIdx {
  my $var = shift // return;
  return first { (sensorTypes)[$_] eq $var } 0 .. scalar(sensorTypes);
}

#-- Datastream types
use constant {
  ST_FIRMWARE_CONFIG_REQUEST  => 0,
  ST_FIRMWARE_CONFIG_RESPONSE => 1,
  ST_FIRMWARE_REQUEST         => 2,
  ST_FIRMWARE_RESPONSE        => 3,
  ST_SOUND                    => 4,
  ST_IMAGE                    => 5,
};

use constant datastreamTypes => qw{ 
  ST_FIRMWARE_CONFIG_REQUEST ST_FIRMWARE_CONFIG_RESPONSE 
  ST_FIRMWARE_REQUEST ST_FIRMWARE_RESPONSE ST_SOUND ST_IMAGE 
};

sub datastreamTypeToStr {
  return (datastreamTypes)[shift];
}

#-- Payload types
use constant {
  P_STRING  => 0,
  P_BYTE    => 1,
  P_INT16   => 2,
  P_UINT16  => 3,
  P_LONG32  => 4,
  P_ULONG32 => 5,
  P_CUSTOM  => 6,
  P_FLOAT32 => 7,
};

use constant payloadTypes => qw{ P_STRING P_BYTE P_INT16 P_UINT16 P_LONG32 P_ULONG32 P_CUSTOM P_FLOAT32 };

sub payloadTypeToStr {
  return (payloadTypes)[shift];
}

sub subTypeToStr {
  my $cmd = shift;
  my $subType = shift // return;

  # Convert subtype to string, depending on message type
  if ($cmd == C_SET) {
    return $subType = (variableTypes)[$subType];
  }

  if ($cmd == C_INTERNAL) {
    return $subType = (internalMessageTypes)[$subType];
  }

if ($cmd == C_STREAM) {
    return $subType = (datastreamTypes)[$subType];
  }

  if ($cmd == C_PRESENTATION) {
    return $subType = (sensorTypes)[$subType];
  }

  if ($cmd == C_REQ) {
    return $subType = (variableTypes)[$subType];
  }

  return $subType = "<UNKNOWN_$subType>";
}


sub Set {
  my $hash    = shift;
  my $name    = shift;
  my $command = shift // return "set $name needs at least one argument !";
  my $value   = shift // '';
  
  return "Unknown argument $command, choose one of " 
    . join(" ", map {
        @{$sets{$_}} ? $_
                      .':'
                      .join ',', @{$sets{$_}} : $_} sort keys %sets)
    if !defined($sets{$command});

  if ($command eq "connect") {
    return Start($hash);
  }
  
  if ($command eq "disconnect") {
    return Stop($hash);
  }
  
  if ($command eq "inclusion-mode") {
    sendMessage($hash,
                radioId => 0, 
                childId => 0, 
                cmd => C_INTERNAL, 
                ack => 0, 
                subType => I_INCLUSION_MODE, 
                payload => $value eq 'on' ? 1 : 0
    );
    $hash->{'inclusion-mode'} = $value eq 'on' ? 1 : 0;
    return;
  }
  return;
}

sub Attr {
  my $command   = shift;
  my $name      = shift;
  my $attribute = shift; 
  my $value     = shift;

  my $hash = $defs{$name};
  if ($attribute eq "autocreate" && $init_done) {
    my $mode = $command eq "set" ? 1 : 0;
    $hash->{'inclusion-mode'} = $mode;
    return sendMessage($hash,
                       radioId => $hash->{radioId}, 
                       childId => $hash->{childId}, 
                       ack => 0, 
                       subType => I_INCLUSION_MODE, 
                       payload => $mode
    );
  }
  
  if ($attribute eq "requestAck") {
    if ($command eq "set") {
      $hash->{ack} = 1;
    } else {
      $hash->{ack} = 0;
      $hash->{messages} = {};
      $hash->{outstandingAck} = 0;
    }
    return;
  }

  if ($attribute eq "OTA_firmwareConfig") {
    return;
  }
  return;
}

sub Start {
  my $hash = shift // return;
  my ($dev) = split m{\s+}xms, $hash->{DEF};
  $hash->{DeviceName} = $dev;
  if (!AttrVal($hash->{NAME},"stateFormat",0)) {
    CommandAttr(undef, "$hash->{NAME} stateFormat connection")
  }
  DevIo_CloseDev($hash);
  return DevIo_OpenDev($hash, 0, "MYSENSORS::Init");
}

sub Stop {
  my $hash = shift // return;
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);
  readingsSingleUpdate($hash,"connection","disconnected",1);
  return;
}

sub Ready {
  my $hash = shift // return;
  return DevIo_OpenDev($hash, 1, "MYSENSORS::Init") if($hash->{STATE} eq "disconnected");
  if(defined($hash->{USBDev})) {
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    return ( $InBytes > 0 );
  }
  return;
}

sub Init {
  my $hash = shift // return;
  my $name = $hash->{NAME};
  $hash->{'inclusion-mode'} = AttrVal($name,"autocreate",0);
  $hash->{ack} = AttrVal($name,"requestAck",0);
  $hash->{outstandingAck} = 0;
  if ($hash->{ack}) {
    GP_ForallClients($hash,sub {
      my $client = shift;
      $hash->{messagesForRadioId}->{$client->{radioId}} = {
        lastseen => -1,
        nexttry  => -1,
        numtries => 1,
        messages => [],
      };
    });
  }
  readingsSingleUpdate($hash,"connection","connected",1);
  return sendMessage($hash, 
                     radioId => 0, 
                     childId => 0, 
                     cmd => C_INTERNAL, 
                     ack => 0, 
                     subType => I_VERSION, 
                     payload => ''
  );
}


# GetConnectStatus
sub GetConnectStatus {
  my $hash = shift // return;
  my $name = $hash->{NAME};
  Log3 $name, 4, "MySensors: GetConnectStatus called ...";

  # neuen Timer starten in einem konfigurierten Interval.
  InternalTimer(gettimeofday()+300, "MYSENSORS::GetConnectStatus", $hash);# Restart check in 5 mins again
  InternalTimer(gettimeofday()+5, "MYSENSORS::Start", $hash);  #Start timer for reset if after 5 seconds RESPONSE is not received
  #query heartbeat from gateway 
  return sendMessage($hash, 
                     radioId => 0, 
                     childId => 0, 
                     cmd => C_INTERNAL, 
                     ack => 0, 
                     subType => I_HEARTBEAT_REQUEST, 
                     payload => ''
  )
}

sub Timer {
  my $hash = shift // return;
  my $now = time;
  for my $radioid (keys %{$hash->{messagesForRadioId}}) {
    my $msgsForId = $hash->{messagesForRadioId}->{$radioid};
    if ($now > $msgsForId->{nexttry}) {
      for my $msg (@{$msgsForId->{messages}}) {
        my $txt = createMsg(%$msg);
        Log3 ($hash->{NAME},5,"MYSENSORS outstanding ack, re-send: ".dumpMsg($msg));
        DevIo_SimpleWrite($hash,"$txt\n",undef);
      }
      $msgsForId->{numtries}++;
      $msgsForId->{nexttry} = gettimeofday()+$msgsForId->{numtries};
    }
  }
  return _scheduleTimer($hash);
}

sub Read {
  my $hash = shift // return;
  my $name = $hash->{NAME};

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $data = $hash->{PARTIAL};
  Log3 ($name, 4, "MYSENSORS/RAW: $data/$buf");
  $data .= $buf;

  while ($data =~ m{\n}xms) {
    my $txt;
    ($txt,$data) = split("\n", $data, 2);
    $txt =~ s/\r//xms;
    if (my $msg = parseMsg($txt)) {
      Log3 ($name,4,"MYSENSORS Read: ".dumpMsg($msg));
      if ($msg->{ack}) {
        onAcknowledge($hash,$msg);
      }
      RemoveInternalTimer($hash,"MYSENSORS::GetConnectStatus");
      InternalTimer(gettimeofday()+300, "MYSENSORS::GetConnectStatus", $hash);# Restart check in 5 mins again
      
      my $type = $msg->{cmd};
      my $dispatch = {
        C_PRESENTATION() => \&onPresentationMsg, #() due to constant type of key
        C_SET()          => \&onSetMsg,
        C_REQ()          => \&onRequestMsg,
        C_INTERNAL()     => \&onInternalMsg,
        C_STREAM()       => \&onStreamMsg,
      };

      ref $dispatch->{$type} eq 'CODE' ? $dispatch->{$type}->($hash, $msg) : Log3($hash->{NAME},2,"MYSENSORS: Dispatch failure, no valid type: >$type<");

    } else {
      Log3 ($name,5,"MYSENSORS Read: ".$txt."is no parsable mysensors message");
    }
  }
  $hash->{PARTIAL} = $data;
  return;
}

sub onPresentationMsg {
  my ($hash,$msg) = @_;
  my $client = matchClient($hash,$msg);
  my $clientname;
  my $sensorType = $msg->{subType};
  unless ($client) {
    if ($hash->{'inclusion-mode'}) {
      $clientname = "MYSENSOR_$msg->{radioId}";
      $clientname = "$hash->{NAME}_DEVICE_0"if defined $defs{$clientname}; 
      CommandDefine(undef,"$clientname MYSENSORS_DEVICE $msg->{radioId}");
      CommandAttr(undef,"$clientname IODev $hash->{NAME}");
      CommandAttr(undef,"$clientname room MYSENSORS_DEVICE");
      $client = $defs{$clientname};
      return unless ($client);
    } else {
      Log3($hash->{NAME},3,"MYSENSORS: ignoring presentation-msg from unknown radioId $msg->{radioId}, childId $msg->{childId}, sensorType $sensorType");
      return;
    }
  }
  return MYSENSORS::DEVICE::onPresentationMessage($client,$msg);
};

sub onSetMsg {
  my ($hash,$msg) = @_;
  if (my $client = matchClient($hash,$msg)) {
    return MYSENSORS::DEVICE::onSetMessage($client,$msg);
  } 
  Log3($hash->{NAME},3,"MYSENSORS: ignoring set-msg from unknown radioId $msg->{radioId}, childId $msg->{childId} for ".variableTypeToStr($msg->{subType}));
  return;
};

sub onRequestMsg {
  my ($hash,$msg) = @_;
  if (my $client = matchClient($hash,$msg)) {
    return MYSENSORS::DEVICE::onRequestMessage($client,$msg);
  } 
  Log3($hash->{NAME},3,"MYSENSORS: ignoring req-msg from unknown radioId $msg->{radioId}, childId $msg->{childId} for ".variableTypeToStr($msg->{subType}));
  return;
};

sub onInternalMsg {
  my ($hash,$msg) = @_;
  my $address = $msg->{radioId};
  my $type = $msg->{subType};
  my $client;

  if ($address == 0 or $address == 255) { #msg to or from gateway
    if ($type == I_INCLUSION_MODE) {
      if (AttrVal($hash->{NAME},"autocreate",0)) { #if autocreate is switched on, keep gateways inclusion-mode active
        if ($msg->{payload} == 0) {
          sendMessage($hash,
                      radioId => $msg->{radioId}, 
                      childId => $msg->{childId}, 
                      ack => 0, 
                      subType => I_INCLUSION_MODE, 
                      payload => 1
          );
        }
      } else {
        $hash->{'inclusion-mode'} = $msg->{payload};
      }
      return;
    }
    
    if ($type == I_GATEWAY_READY) {
      readingsSingleUpdate($hash,'connection','startup complete',1);
      GP_ForallClients($hash,sub {
        my $client = shift;
        MYSENSORS::DEVICE::onGatewayStarted($client);
      });
      return InternalTimer(gettimeofday()+300, "MYSENSORS::GetConnectStatus", $hash);
    }
    
    if ($type == I_HEARTBEAT_RESPONSE) {
      RemoveInternalTimer($hash,"MYSENSORS::Start"); ## Reset reconnect because timeout was not reached
      readingsSingleUpdate($hash, "heartbeat", "alive", 0);
      if ($client = matchClient($hash,$msg)){ MYSENSORS::DEVICE::onInternalMessage($client,$msg) };
      return;
    }
    
    if ($type == I_VERSION) {
      $hash->{version} = $msg->{payload};
      return;
    }
    
    if ($type == I_LOG_MESSAGE) {
      return Log3($hash->{NAME},5,"MYSENSORS gateway $hash->{NAME}: $msg->{payload}");
    }
    if ($type == I_ID_REQUEST) {
      if ($hash->{'inclusion-mode'}) {
        my %nodes = map {$_ => 1} (AttrVal($hash->{NAME},"first-sensorid",20) ... AttrVal($hash->{NAME},"last-sensorid",254));
        GP_ForallClients($hash,sub {
          my $client = shift;
          delete $nodes{$client->{radioId}};
        });
        if (keys %nodes) {
          my $newid = (sort keys %nodes)[0];
          sendMessage($hash,radioId => 255, childId => 255, cmd => C_INTERNAL, ack => 0, subType => I_ID_RESPONSE, payload => $newid);
          Log3($hash->{NAME},4,"MYSENSORS $hash->{NAME} assigned new nodeid $newid");
        } else {
          Log3($hash->{NAME},4,"MYSENSORS $hash->{NAME} cannot assign new nodeid");
        }
      } else {
        Log3($hash->{NAME},4,"MYSENSORS: ignoring id-request-msg from unknown radioId $msg->{radioId}");
      }
      return;
    }
    
    if ($type == I_TIME) {
      if ($client = matchClient($hash,$msg)){ 
        return MYSENSORS::DEVICE::onInternalMessage($client,$msg) 
      }
    }

  }
  if ($client = matchClient($hash,$msg)) {
    return MYSENSORS::DEVICE::onInternalMessage($client,$msg);
  } 
  if ($client = matchChan76GWClient($hash,$msg)) {
    Log3($hash->{NAME}, 4, "$hash->{NAME}: received stream message for $client - Chan76-IODev");
    return MYSENSORS::DEVICE::onInternalMessage($client,$msg);
  } 
  Log3($hash->{NAME},3,"MYSENSORS: ignoring internal-msg from unknown radioId $msg->{radioId}, childId $msg->{childId} for ".internalMessageTypeToStr($msg->{subType}));
  return;
}

sub onStreamMsg {
  my ($hash,$msg) = @_;
  my $client;
  if ($client = matchClient($hash, $msg)) {
    Log3($hash->{NAME}, 4, "$hash->{NAME}: received stream message for $client - regular IODev");
    return MYSENSORS::DEVICE::onStreamMessage($client, $msg);
  } 
  if ($client = matchChan76GWClient($hash,$msg)) {
    Log3($hash->{NAME}, 4, "$hash->{NAME}: received stream message for $client - Chan76-IODev");
    return MYSENSORS::DEVICE::onStreamMessage($client,$msg);
  } 
  Log3($hash->{NAME},3,"MYSENSORS: ignoring stream-msg from unknown radioId $msg->{radioId}, childId $msg->{childId} for ".datastreamTypeToStr($msg->{subType}).". IO: $hash->{NAME}");
  return;
}

sub onAcknowledge {
  my ($hash,$msg) = @_;
  my $ack;
  if (defined (my $outstanding = $hash->{messagesForRadioId}->{$msg->{radioId}}->{messages})) {
    my @remainMsg = grep {
         $_->{childId} != $msg->{childId}
      or $_->{cmd}     != $msg->{cmd}
      or $_->{subType} != $msg->{subType}
      or $_->{payload} ne $msg->{payload}
    } @$outstanding;
    if ($ack = @remainMsg < @$outstanding) {
      $hash->{outstandingAck} -= 1;
      @$outstanding = @remainMsg;
    }
    $hash->{messagesForRadioId}->{$msg->{radioId}}->{numtries} = 1;
  }
  Log3 ($hash->{NAME},4,"MYSENSORS Read: unexpected ack ".dumpMsg($msg)) if !$ack;
  return;
}

sub getFirmwareTypes {
  my $hash = shift;
  my $name = $hash->{NAME};
  my @fwTypes = ();
  my $filename = AttrVal($name, "OTA_firmwareConfig", undef);
  if (defined($filename)) {  
    my ($err, @lines) = FileRead({FileName => "./FHEM/firmware/" . $filename, 
                                  ForceType => "file"}); 
    if (defined($err) && $err) {
      Log3($name, 2, "$name: could not read MySensor firmware configuration file - $err");
    } else {
      for (my $i = 0; $i < @lines ; $i++) {
        chomp(my $row = $lines[$i]);
        if (index($row, "#") != 0) {
          my @tokens = split(",", $row);
          push(@fwTypes, $tokens[0]);
        }
      }
    }
  }
  Log3($name, 5, "$name: getFirmwareTypes - list contains: @fwTypes");
  return @fwTypes;
}

sub getLatestFirmware {
  my $hash = shift;
  my $type = shift // return;
  my $name = $hash->{NAME};
  my $cfgfilename = AttrVal($name, "OTA_firmwareConfig", undef);
  my $version = undef;
  $name = undef;
  my $filename = undef;
  if (defined($cfgfilename)) {  
    my ($err, @lines) = FileRead({FileName => "./FHEM/firmware/" . $cfgfilename, 
                                  ForceType => "file"}); 
    if (defined($err) && $err) {
      Log3($name, 2, "$name: could not read MySensor firmware configuration file - $err");
    } else {
      for (my $i = 0; $i < @lines ; $i++) {
        chomp(my $row = $lines[$i]);
        if (index($row, "#") != 0) {
          my @tokens = split(",", $row);
          if ($tokens[0] eq $type) {
            if ((not defined $version) || ($tokens[2] > $version)) {
              $name = $tokens[1];
              $version = $tokens[2];
              $filename = $tokens[3];
            }
          }
        }
      }
    }
  }
  return ($version, $filename, $name);
}


sub sendMessage {
  my ($hash,%msg) = @_;
  $msg{ack} = $hash->{ack} unless defined $msg{ack};
  my $txt = createMsg(%msg);
  Log3 ($hash->{NAME},5,"MYSENSORS send: ".dumpMsg(\%msg));
  DevIo_SimpleWrite($hash,"$txt\n",undef);
  if ($msg{ack}) {
    my $messagesForRadioId = $hash->{messagesForRadioId}->{$msg{radioId}};
    if (!defined $messagesForRadioId) {
      $messagesForRadioId = {
        lastseen => -1,
        numtries => 1,
        messages => [],
      };
      $hash->{messagesForRadioId}->{$msg{radioId}} = $messagesForRadioId;
    }
    my $messages = $messagesForRadioId->{messages};
    @$messages = grep {
         $_->{childId} != $msg{childId}
      or $_->{cmd}     != $msg{cmd}
      or $_->{subType} != $msg{subType}
    } @$messages;
    push @$messages,\%msg;

    $messagesForRadioId->{nexttry} = gettimeofday()+$messagesForRadioId->{numtries};
    _scheduleTimer($hash);
  }
  return;
};

sub _scheduleTimer {
  my $hash = shift;
  $hash->{outstandingAck} = 0;
  RemoveInternalTimer($hash,"MYSENSORS::Timer");
  my $next;
  for my $radioid (keys %{$hash->{messagesForRadioId}}) {
    my $msgsForId = $hash->{messagesForRadioId}->{$radioid};
    $hash->{outstandingAck} += @{$msgsForId->{messages}};
    $next = $msgsForId->{nexttry} if (!defined $next || $next >= $msgsForId->{nexttry});
  };
  InternalTimer($next, "MYSENSORS::Timer", $hash, 0) if (defined $next);
  return;
}

sub matchClient {
  my ($hash,$msg) = @_;
  my $radioId = $msg->{radioId};
  my $found;
  GP_ForallClients($hash,sub {
    return if $found;
    my $client = shift;
    if ($client->{radioId} == $radioId) {
      $found = $client;
    }
  });
  return $found;
}

sub matchChan76GWClient {
  my ($hash,$msg) = @_;
  my $radioId = $msg->{radioId};
  my $name = $hash->{NAME};
  my $found;
  for my $d ( sort keys %defs ) {
    if ( defined( $defs{$d} )
      && defined( $defs{$d}{radioId} )
      && $defs{$d}{radioId} == $radioId ) {
        #my $clientname = $defs{$d}->{NAME};
        #$found = $defs{$d} if AttrVal($clientname,"OTA_Chan76_IODev","") eq 
        $found = $defs{$d} if AttrVal($d,"OTA_Chan76_IODev","") eq $name;
    }
  }
  
  Log3($hash, 4, "$name: matched firmware config request to IO-name $found->{NAME}") if $found;
  return $found;
}

sub parseMsg {
    my $txt = shift // return;

    use bytes;

    return if ($txt !~ m{\A
               (?<nodeid>  [0-9]+);
               (?<childid> [0-9]+);
               (?<command> [0-4]);
               (?<ack>     [01]);
               (?<type>    [0-9]{1,2});
               (?<payload> .*)
               \z}xms);

    return {
        radioId => $+{nodeid}, # docs speak of "nodeId"
        childId => $+{childid},
        cmd     => $+{command},
        ack     => $+{ack},
        subType => $+{type},
        payload => $+{payload}
    };
}

sub createMsg {
  my %msgRef = @_;
  my @fields = ( $msgRef{'radioId'} // -1,
                 $msgRef{'childId'} // -1,
                 $msgRef{'cmd'} // -1,
                 $msgRef{'ack'} // -1,
                 $msgRef{'subType'} // -1,
                 $msgRef{'payload'}  // "");
  return join(';', @fields);
}

sub dumpMsg {
  my $msgRef = shift;
  my $cmd = defined $msgRef->{'cmd'} ? commandToStr($msgRef->{'cmd'}) : "''";
  my $st = (defined $msgRef->{'cmd'} and defined $msgRef->{'subType'}) ? subTypeToStr( $msgRef->{'cmd'}, $msgRef->{'subType'} ) : "''";
  return sprintf("Rx: fr=%03d ci=%03d c=%03d(%-14s) st=%03d(%-16s) ack=%d %s\n", $msgRef->{'radioId'} // -1, $msgRef->{'childId'} // -1, $msgRef->{'cmd'} // -1, $cmd, $msgRef->{'subType'} // -1, $st, $msgRef->{'ack'} // -1, "'".($msgRef->{'payload'} // "")."'");
}

#our @EXPORT = ();
our @EXPORT_OK = (
  commands,
  variableTypes,
  internalMessageTypes,
  sensorTypes,
  datastreamTypes,
  payloadTypes,
    qw(
       sendMessage
       getFirmwareTypes
       getLatestFirmware
       variableTypeToStr
       variableTypeToIdx
       internalMessageTypeToStr
       sensorTypeToStr
       sensorTypeToIdx
       )
  );
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

1;

__END__

=pod
=item device
=item summary includes a MYSENSORS gateway
=item summary_DE integriert ein MYSENSORS Gateway

=begin html

<a name="MYSENSORS"></a>
<h3>MYSENSORS</h3>
<ul>
  <p>connects fhem to <a href="http://MYSENSORS.org">MYSENSORS</a>.</p>
  <p>A single MYSENSORS device can serve multiple <a href="#MYSENSORS_DEVICE">MYSENSORS_DEVICE</a> clients.<br/>
     Each <a href="#MYSENSORS_DEVICE">MYSENSORS_DEVICE</a> represents a mysensors node.<br/>
  <a name="MYSENSORSdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MYSENSORS &lt;serial device&gt|&lt;ip:port&gt;</code></p>
    <p>Specifies the MYSENSORS device.</p>
  </ul>
  <a name="MYSENSORSset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; connect</code><br/>
         (re-)connects the MYSENSORS-device to the MYSENSORS-gateway</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; disconnect</code><br/>
         disconnects the MYSENSORS-device from the MYSENSORS-gateway</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; inclusion-mode on|off</code><br/>
         turns the gateways inclusion-mode on or off</p>
    </li>
  </ul>
  <a name="MYSENSORSattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; autocreate</code><br/>
         enables auto-creation of MYSENSOR_DEVICE-devices on receival of presentation-messages</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; requestAck</code><br/>
         request acknowledge from nodes.<br/>
         if set the Readings of nodes are updated not before requested acknowledge is received<br/>
         if not set the Readings of nodes are updated immediatly (not awaiting the acknowledge).
         May also be configured for individual nodes if not set for gateway.</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; first-sensorid <&lt;number &lth; 255&gt;></code><br/>
         configures the lowest node-id assigned to a mysensor-node on request (defaults to 20)</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; OTA_firmwareConfig &lt;filename&gt;</code><br/>
         specifies a configuration file for the <a href="https://www.mysensors.org/about/fota">FOTA</a>
         (firmware over the air - wireless programming of the nodes) configuration. It must be stored 
         in the folder FHEM/firmware. The format of the configuration file is the following (csv):</p>
      <p><code>#Type,Name,Version,File,Comments</code><br/>
         <code>10,Blink,1,Blink.hex,blinking example</code><br/></p>
      <p>The meaning of the columns is the following:</br>
         <dl>
           <dt><code>Type</code></dt>
           <dd>a numeric value (range 0 .. 65536) - each node will be assigned a firmware type</dd>
           <dt><code>Name</code></dt>
           <dd>a short name for this type</dd>
           <dt><code>Version</code></dt> 
           <dd>a numeric value (range 0 .. 65536) - the version of the firmware (may be different 
               to the value that is send during the node presentation)</dd>
           <dt><code>File</code></dt>
           <dd>the filename containing the firmware - must also be stored in the folder FHEM/firmware</dd>
           <dt><code>Comments</code></dt>
           <dd>a description / comment for the firmware</dd>
         </dl></p>
    </li>
  </ul>
</ul>

=end html
=cut
