package Device::MySensors::Constants;

use List::Util qw(first); 
 
#-- Message types
use constant {
	C_PRESENTATION => 0,
	C_SET          => 1,
	C_REQ          => 2,
	C_INTERNAL     => 3,
	C_STREAM       => 4,
};

use constant commands => qw( C_PRESENTATION C_SET C_REQ C_INTERNAL C_STREAM );

sub commandToStr($) {
	(commands)[shift];
}

#-- Variable types
use constant {
  V_TEMP               => 0,
  V_HUM               => 1,
  V_STATUS               => 2,
  V_PERCENTAGE               => 3,
  V_PRESSURE               => 4,
  V_FORECAST               => 5,
  V_RAIN               => 6,
  V_RAINRATE               => 7,
  V_WIND               => 8,
  V_GUST               => 9,
  V_DIRECTION               => 10,
  V_UV               => 11,
  V_WEIGHT               => 12,
  V_DISTANCE               => 13,
  V_IMPEDANCE               => 14,
  V_ARMED               => 15,
  V_TRIPPED               => 16,
  V_WATT               => 17,
  V_KWH               => 18,
  V_SCENE_ON               => 19,
  V_SCENE_OFF               => 20,
  V_HVAC_FLOW_STATE               => 21,
  V_HVAC_SPEED               => 22,
  V_LIGHT_LEVEL               => 23,
  V_VAR1               => 24,
  V_VAR2               => 25,
  V_VAR3               => 26,
  V_VAR4               => 27,
  V_VAR5               => 28,
  V_UP               => 29,
  V_DOWN               => 30,
  V_STOP               => 31,
  V_IR_SEND               => 32,
  V_IR_RECEIVE               => 33,
  V_FLOW               => 34,
  V_VOLUME               => 35,
  V_LOCK_STATUS               => 36,
  V_LEVEL               => 37,
  V_VOLTAGE               => 38,
  V_CURRENT               => 39,
  V_RGB               => 40,
  V_RGBW               => 41,
  V_ID               => 42,
  V_UNIT_PREFIX               => 43,
  V_HVAC_SETPOINT_COOL               => 44,
  V_HVAC_SETPOINT_HEAT               => 45,
  V_HVAC_FLOW_MODE               => 46,
  V_TEXT               => 47,
  V_CUSTOM               => 48,
  V_POSITION               => 49,
  V_IR_RECORD               => 50,
  V_PH               => 51,
  V_ORP               => 52,
  V_EC               => 53,
  V_VAR               => 54,
  V_VA               => 55,
  V_POWER_FACTOR               => 56,
};

use constant variableTypes => qw{ V_TEMP V_HUM V_STATUS V_PERCENTAGE V_PRESSURE V_FORECAST V_RAIN
        V_RAINRATE V_WIND V_GUST V_DIRECTION V_UV V_WEIGHT V_DISTANCE
        V_IMPEDANCE V_ARMED V_TRIPPED V_WATT V_KWH V_SCENE_ON V_SCENE_OFF
        V_HVAC_FLOW_STATE V_HVAC_SPEED V_LIGHT_LEVEL V_VAR1 V_VAR2 V_VAR3 V_VAR4 V_VAR5
        V_UP V_DOWN V_STOP V_IR_SEND V_IR_RECEIVE V_FLOW V_VOLUME V_LOCK_STATUS 
        V_LEVEL V_VOLTAGE V_CURRENT V_RGB V_RGBW V_ID V_UNIT_PREFIX V_HVAC_SETPOINT_COOL V_HVAC_SETPOINT_HEAT V_HVAC_FLOW_MODE
        V_TEXT V_CUSTOM V_POSITION V_IR_RECORD V_PH V_ORP V_EC V_VAR V_VA V_POWER_FACTOR };

sub variableTypeToStr($) {
  (variableTypes)[shift];
}

sub variableTypeToIdx($) {
	my $var = shift;
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
  I_LOCKED                  => 23, # 	Node is locked (reason in string-payload)
  I_PING                    => 24, # 	Ping sent to node, payload incremental hop counter
  I_PONG                    => 25, # 	In return to ping, sent back to sender, payload incremental hop counter
  I_REGISTRATION_REQUEST    => 26, # 	Register request to GW
  I_REGISTRATION_RESPONSE   => 27, # 	Register response from GW
  I_DEBUG                   => 28, 
  I_SIGNAL_REPORT_REQUEST   => 29,
  I_SIGNAL_REPORT_REVERSE   => 30,
  I_SIGNAL_REPORT_RESPONSE  => 31,
  I_PRE_SLEEP_NOTIFICATION  => 32,
  I_POST_SLEEP_NOTIFICATION => 33,
};

use constant internalMessageTypes => qw{ I_BATTERY_LEVEL I_TIME I_VERSION I_ID_REQUEST I_ID_RESPONSE 
        I_INCLUSION_MODE I_CONFIG I_FIND_PARENT I_FIND_PARENT_RESPONSE 
        I_LOG_MESSAGE I_CHILDREN I_SKETCH_NAME I_SKETCH_VERSION 
        I_REBOOT I_GATEWAY_READY I_REQUEST_SIGNING I_GET_NONCE I_GET_NONCE_RESPONSE I_HEARTBEAT_REQUEST I_PRESENTATION I_DISCOVER_REQUEST 
        I_DISCOVER_RESPONSE I_HEARTBEAT_RESPONSE I_LOCKED I_PING I_PONG I_REGISTRATION_REQUEST I_REGISTRATION_RESPONSE I_DEBUG 
        I_SIGNAL_REPORT_REQUEST I_SIGNAL_REPORT_REVERSE I_SIGNAL_REPORT_RESPONSE I_PRE_SLEEP_NOTIFICATION I_POST_SLEEP_NOTIFICATION };

sub internalMessageTypeToStr($) {
	(internalMessageTypes)[shift];
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

use constant sensorTypes => qw{ S_DOOR S_MOTION S_SMOKE S_BINARY S_DIMMER S_COVER S_TEMP S_HUM S_BARO S_WIND
        S_RAIN S_UV S_WEIGHT S_POWER S_HEATER S_DISTANCE S_LIGHT_LEVEL S_ARDUINO_NODE
        S_ARDUINO_REPEATER_NODE S_LOCK S_IR S_WATER S_AIR_QUALITY S_CUSTOM S_DUST S_SCENE_CONTROLLER
        S_RGB_LIGHT S_RGBW_LIGHT S_COLOR_SENSOR S_HVAC S_MULTIMETER S_SPRINKLER S_WATER_LEAK S_SOUND S_VIBRATION
        S_MOISTURE S_INFO S_GAS S_GPS S_WATER_QUALITY };

sub sensorTypeToStr($) {
  (sensorTypes)[shift];
}

sub sensorTypeToIdx($) {
  my $var = shift;
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

use constant datastreamTypes => qw{ ST_FIRMWARE_CONFIG_REQUEST ST_FIRMWARE_CONFIG_RESPONSE ST_FIRMWARE_REQUEST ST_FIRMWARE_RESPONSE
        ST_SOUND ST_IMAGE };

sub datastreamTypeToStr($) {
  (datastreamTypes)[shift];
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

sub payloadTypeToStr($) {
	(payloadTypes)[shift];
}

sub subTypeToStr($$) {
  my $cmd = shift;
  my $subType = shift;
  # Convert subtype to string, depending on message type
  TYPE: {
    $cmd == C_PRESENTATION and do {
      $subType = (sensorTypes)[$subType];
      last;
    };
    $cmd == C_SET and do {
      $subType = (variableTypes)[$subType];
      last;
    };
    $cmd == C_REQ and do {
      $subType = (variableTypes)[$subType];
      last;
    };
    $cmd == C_INTERNAL and do {
      $subType = (internalMessageTypes)[$subType];
      last;
    };
    $subType = "<UNKNOWN_$subType>";
  }  
  return $subType;
}

use Exporter ('import');
@EXPORT = ();
@EXPORT_OK = (
  commands,
  variableTypes,
  internalMessageTypes,
  sensorTypes,
  datastreamTypes,
  payloadTypes,
  qw(commandToStr
    variableTypeToStr
    variableTypeToIdx
    internalMessageTypeToStr
    sensorTypeToStr
    sensorTypeToIdx
    datastreamTypeToStr
    payloadTypeToStr
    subTypeToStr
    commands
    variableTypes
    internalMessageTypes
    sensorTypes
    datastreamTypes
    payloadTypes
  ));

%EXPORT_TAGS = (all => [@EXPORT_OK]);

1;