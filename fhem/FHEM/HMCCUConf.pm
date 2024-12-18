#########################################################################
#
#  HMCCUConf.pm
#
#  $Id$
#
#  Version 5.0
#
#  Configuration parameters for HomeMatic devices.
#
#  (c) 2024 by zap (zap01 <at> t-online <dot> de)
#
#########################################################################

package HMCCUConf;

use strict;
use warnings;

use vars qw($HMCCU_CONFIG_VERSION);
use vars qw(%HMCCU_DEF_ROLE);
use vars qw(%HMCCU_STATECONTROL);
use vars qw(%HMCCU_READINGS);
use vars qw(%HMCCU_ROLECMDS);
use vars qw(%HMCCU_ATTR);
use vars qw(%HMCCU_CONVERSIONS);
use vars qw(%HMCCU_CHN_DEFAULTS);
use vars qw(%HMCCU_DEV_DEFAULTS);
use vars qw(%HMCCU_SCRIPTS);

$HMCCU_CONFIG_VERSION = '5.0';

######################################################################
# Map subtype to default role. Subtype is only available for HMIP
# devices.
# Used by HMCCU to detect control channel of HMCCUDEV devices.
######################################################################

%HMCCU_DEF_ROLE = (
	'ASIR' => 'ALARM_SWITCH_VIRTUAL_RECEIVER',
	'FSM'  => 'SWITCH_VIRTUAL_RECEIVER',
	'PSM'  => 'SWITCH_VIRTUAL_RECEIVER',
	'SD'   => 'SMOKE_DETECTOR'
);

######################################################################
# Channel roles with state and control datapoints
#   F: 1=Channel/HMCCUCHN, 2=Device/HMCCUDEV, 3=Both
#   S: State datapoint, C: Control datapoint,
#   V: Control values, #=Enum or const:value[,...]
#   P: Priority (used by HMCCUDEV if more than 1 channel role fits)
#      1=lowest priority
######################################################################

%HMCCU_STATECONTROL = (
	'ACCELERATION_TRANSCEIVER' => {
		F => 3, S => 'MOTION', C => '', V => '', P => 1
	},
	'ACCESSPOINT_GENERIC_RECEIVER' => {
		F => 3, S => 'VOLTAGE', C => '', V => '', P => 1
	},
	'ACOUSTIC_SIGNAL_TRANSMITTER' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'on:100,off:0', P => 2
	},
	'ALARM_SWITCH_VIRTUAL_RECEIVER' => {
		F => 3, S => 'ACOUSTIC_ALARM_ACTIVE', C => 'ACOUSTIC_ALARM_SELECTION', V => '', P => 2
	},
	'ARMING' => {
		F => 3, S => 'ARMSTATE', C => 'ARMSTATE', V => '#', P => 2
	},
	'BLIND' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'open:100,close:0', P => 2
	},
	'BLIND_TRANSMITTER' => {
		F => 3, S => 'LEVEL', C => '', V => '', P => 1
	},
	'BLIND_VIRTUAL_RECEIVER' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'open:100,close:0', P => 2
	},
	'BRIGHTNESS_TRANSMITTER' => {
		F => 3, S => 'CURRENT_ILLUMINATION', C => '', V => '', P => 2
	},
	'CAPACITIVE_FILLING_LEVEL_SENSOR' => {
		F => 3, S => 'FILLING_LEVEL', C => '', V => '', P => 2
	},
	'CLIMATE_TRANSCEIVER' => {
		F => 3, S => 'ACTUAL_TEMPERATURE', C => '', V => '', P => 1
	},
	'CLIMATECONTROL_FLOOR_TRANSCEIVER' => {
		F => 3, S => 'LEVEL', C => '', V => '', P => 1
	},
	'CLIMATECONTROL_REGULATOR' => {
		F => 3, S => 'LEVEL', C => 'SETPOINT', V => 'on:30.5,off:4.5', P => 2
	},
	'CLIMATECONTROL_RT_TRANSCEIVER' => {
		F => 3, S => 'ACTUAL_TEMPERATURE', C => 'SET_TEMPERATURE', V => 'on:30.5,off:4.5', P => 2
	},
	'CLIMATECONTROL_VENT_DRIVE' => {
		F => 3, S => 'VALVE_STATE', C => '', V => '', P => 2
	},
	'COND_SWITCH_TRANSMITTER_TEMPERATURE' => {
		F => 3, S => 'ACTUAL_TEMPERATURE', C => '', V => '', P => 1
	},
	'DIMMER' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'on:100,off:0', P => 2
	},
	'DIMMER_TRANSMITTER' => {
		F => 3, S => 'LEVEL', C => '', V => '', P => 1
	},
	'DIMMER_VIRTUAL_RECEIVER' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'on:100,off:0', P => 2
	},
	'DIMMER_WEEK_PROFILE' => {
		F => 3, S => 'WEEK_PROGRAM_CHANNEL_LOCKS', C => 'WEEK_PROGRAM_TARGET_CHANNEL_LOCK', V => '', P => 2 
	},
	'DOOR_LOCK_STATE_TRANSMITTER' => {
		F => 3, S => 'LOCK_STATE', C => 'LOCK_TARGET_LEVEL', V => 'open:2,unlocked:1,locked:0', P => 2
	},
	'DOOR_RECEIVER' => {
		F => 3, S => 'DOOR_STATE', C => 'DOOR_COMMAND', V => 'open:1,stop:2,close:3,ventilate:4', P => 2
	},
	'ENERGIE_METER_TRANSMITTER' => {
		F => 3, S => 'CURRENT', C => '', V => '', P => 1
	},
	'HB_GENERIC_DIST' => {
		F => 3, S => 'DISTANCE', C => '', V => '', P => 1
	},
	'HEATING_CLIMATECONTROL_TRANSCEIVER' => {
		F => 3, S => 'ACTUAL_TEMPERATURE', C => 'SET_POINT_TEMPERATURE', V => 'on:30.5,off:4.5', P => 2
	},
	'JALOUSIE' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'open:100,close:0', P => 2
	},
	'KEY' => {
		F => 3, S => 'PRESS_SHORT', C => 'PRESS_SHORT', V => 'pressed:true', P => 1
	},
	'KEY_TRANSCEIVER' => {
		F => 3, S => 'PRESS_SHORT', C => '', V => '', P => 1
	},
	'KEYMATIC' => {
		F => 3, S => 'STATE', C => 'STATE', V => 'locked:false,unlocked:true', P => 2
	},
	'LUXMETER' => {
		F => 3, S => 'LUX', C => '', V => '', P => 2
	},
	'MOTION_DETECTOR' => {
		F => 3, S => 'MOTION', C => '', V => '', P => 2
	},
	'MOTIONDETECTOR_TRANSCEIVER' => {
		F => 3, S => 'MOTION', C => 'MOTION_DETECTION_ACTIVE', V => 'active:1,inactive:0', P => 2
	},
	'MULTI_MODE_INPUT_TRANSMITTER' => {
		F => 3, S => 'STATE', C => '', V => '', P => 1
	},
	'PASSAGE_DETECTOR_DIRECTION_TRANSMITTER' => {
		F => 3, S => 'CURRENT_PASSAGE_DIRECTION', C => '', V => '', P => 1
	},
	'POWERMETER' => {
		F => 3, S => 'CURRENT', C => '', V => '', P => 1
	},
	'POWERMETER_IEC1' => {
		F => 3, S => 'ENERGY_COUNTER', C => '', V => '', P => 1
	},
	'POWERMETER_IEC2' => {
		F => 3, S => 'IEC_ENERGY_COUNTER', C => '', V => '', P => 1
	},
	'PRESENCEDETECTOR_TRANSCEIVER' => {
		F => 3, S => 'PRESENCE_DETECTION_STATE', C => 'PRESENCE_DETECTION_ACTIVE', V => 'active:1,inactive:0', P => 2
	},
	'RAINDETECTOR' => {
		F => 3, S => 'STATE', C => '', V => '', P => 1
	},
	'RAINDETECTOR_HEAT' => {
		F => 3, S => 'STATE', C => 'STATE', V => 'on:true,off:false', P => 2
	},
	'RGBW_COLOR' => {
		F => 3, S => 'COLOR', C => 'COLOR', V => '', P => 2
	},
	'ROTARY_HANDLE_SENSOR' => {
		F => 3, S => 'STATE', C => '', V => '', P => 2
	},
	'ROTARY_HANDLE_TRANSCEIVER' => {
		F => 3, S => 'STATE', C => '', V => '', P => 2
	},
	'SHUTTER_CONTACT'  => {
		F => 3, S => 'STATE', C => '', V => '', P => 2
	},
	'SHUTTER_CONTACT_TRANSCEIVER' => {
		F => 3, S => 'STATE', C => '', V => '', P => 2
	},
	'SMOKE_DETECTOR' => {
		F => 3, S => 'BidCos-RF:STATE,SMOKE_DETECTOR_ALARM_STATUS', C => 'HmIP-RF:SMOKE_DETECTOR_COMMAND', V => '', P => 2
	},
	'SHUTTER_TRANSMITTER' => {
		F => 3, S => 'LEVEL', C => '', V => '', P => 1
	},
	'SHUTTER_VIRTUAL_RECEIVER' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'open:100,close:0', P => 2
	},
	'SWITCH' => {
		F => 3, S => 'STATE', C => 'STATE', V => 'on:true,off:false', P => 2
	},	
	'SWITCH_PANIC' => {
		F => 3, S => 'STATE', C => 'STATE', V => 'on:true,off:false', P => 2
	},
	'SWITCH_SENSOR' => {
		F => 3, S => 'STATE', C => 'STATE', V => 'on:true,off:false', P => 2
	},
	'SWITCH_TRANSMITTER' => {
		F => 3, S => 'STATE', C => '', V => '', P => 1
	},
	'SWITCH_VIRTUAL_RECEIVER' => {
		F => 3, S => 'STATE', C => 'STATE', V => 'on:true,off:false', P => 2
	},
	'THERMALCONTROL_TRANSMIT' => {
		F => 3, S => 'ACTUAL_TEMPERATURE', C => 'SET_TEMPERATURE', V => 'on:30.5,off:4.5', P => 2
	},
	'TILT_SENSOR' => {
		F => 3, S => 'STATE', C => '', V => '', P => 1
	},
	'UNIVERSAL_LIGHT_RECEIVER' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'on:100,off:0', P => 1
	},
	'VIRTUAL_KEY' => {
		F => 3, S => 'PRESS_SHORT', C => 'PRESS_SHORT', V => 'pressed:true', P => 1
	},
	'WATER_DETECTION_TRANSMITTER' => {
		F => 3, S => 'ALARMSTATE', C => '', V => '', P => 1
	},
	'WEATHER' => {
		F => 3, S => 'TEMPERATURE', C => '', V => '', P => 1
	},
	'WEATHER_TRANSMIT' => {
		F => 3, S => 'ACTUAL_TEMPERATURE', C => '', V => '', P => 1
	},
	'WINMATIC' => {
		F => 3, S => 'LEVEL', C => 'LEVEL', V => 'open:100,close:0,lock:-0.5', P => 2
	}
);

######################################################################
# Add or rename readings
# C# = Placeholder for state or control channel number 
# DEFAULT should not be used, if a HMCCUDEV device has multiple
# channels with identical datapoints (i.e. LEVEL)
######################################################################

%HMCCU_READINGS = (
	'ACCELERATION_TRANSCEIVER' =>
		'^(C#\.)?MOTION:+motion',
	'ARMING' =>
		'^(C#\.)?ARMSTATE$:+armState',
	'BLIND' =>
		'^(C#\.)?LEVEL$:+pct,+level',
	'BLIND_TRANSMITTER' =>
		'^(C#\.)?LEVEL$:+pct,+level;^(C#\.)?LEVEL_2$:+pctSlats',
	'CAPACITIVE_FILLING_LEVEL_SENSOR' =>
		'^(C#\.)?FILLING_LEVEL$:+level',
	'CLIMATECONTROL_REGULATOR' =>
		'^(C#\.)?SETPOINT$:+desired-temp',
	'CLIMATECONTROL_RT_TRANSCEIVER' =>
		'^(C#\.)?ACTUAL_TEMPERATURE$:+measured-temp;'.
		'^(C#\.)?ACTUAL_HUMIDITY$:+humidity;'.
		'^(C#\.)?SET_TEMPERATURE$:+desired-temp;'.
		'^(C#\.)?BOOST_MODE$:+boost',
	'CLIMATE_TRANSCEIVER' =>
		'^(C#\.)?ACTUAL_TEMPERATURE$:+measured-temp;'.
		'^(C#\.)?ACTUAL_HUMIDITY$:+humidity',
	'COND_SWITCH_TRANSMITTER_TEMPERATURE' =>
		'^(C#\.)?ACTUAL_TEMPERATURE$:+measured-temp',
	'DIMMER' =>
		'^(C#\.)?LEVEL$:+pct,+level',
	'DIMMER_TRANSMITTER' =>
		'^(C#\.)?LEVEL$:+pct,+level;(C#\.)?COLOR$:+color',
	'DIMMER_WEEK_PROFILE' =>
		'^(C#\.)?WEEK_PROGRAM_CHANNEL_LOCKS$:+progMode',
	'HB_GENERIC_DIST' =>
		'^(C#\.)?BATTERY_VOLTAGE$:voltage',
	'HEATING_CLIMATECONTROL_TRANSCEIVER' =>
		'^(C#\.)?ACTUAL_TEMPERATURE$:+measured-temp;'.
		'^(C#\.)?HUMIDITY$:+humidity;'.
		'^(C#\.)?ACTUAL_HUMIDITY$:+humidity;'.
		'^(C#\.)?SET_POINT_TEMPERATURE$:+desired-temp;'.
		'^(C#\.)?BOOST_MODE$:+boost;'.
		'^(C#\.)?ACTIVE_PROFILE$:+week-program',
	'JALOUSIE' =>
		'^(C#\.)?LEVEL$:+pct,+level;(C#\.)?LEVEL_SLATS$:+pctSlats',
	'KEY' =>
		'^(C#\.)?PRESS_(SHORT|LONG)$:+pressed',
	'KEY_TRANSCEIVER' =>
		'^(C#\.)?PRESS_(SHORT|LONG)$:+pressed',
	'MOTION_DETECTOR' =>
		'^(C#\.)?BRIGHTNESS$:brightness;(C#\.)?MOTION:motion',
	'MOTIONDETECTOR_TRANSCEIVER' =>
		'^(C#\.)?ILLUMINATION$:+brightness;^(C#\.)?MOTION$:+motion;(C#\.)?MOTION_DETECTION_ACTIVE$:+detection',
	'PRESENCEDETECTOR_TRANSCEIVER' =>
		'^(C#\.)?ILLUMINATION$:+brightness;(C#\.)?PRESENCE_DETECTION_STATE:+presence;(C#\.)?PRESENCE_DETECTION_ACTIVE:+detection',
	'SHUTTER_TRANSMITTER' =>
		'^(C#\.)?LEVEL$:+pct,+level',
	'SWITCH_PANIC' =>
		'^(C#\.)?STATE$:+panic',
	'SWITCH_SENSOR' =>
		'^(C#\.)?STATE$:+sensor',
	'THERMALCONTROL_TRANSMIT' =>
		'^(C#\.)?ACTUAL_TEMPERATURE$:+measured-temp;'.
		'^(C#\.)?ACTUAL_HUMIDITY$:+humidity;'.
		'^(C#\.)?SET_TEMPERATURE$:+desired-temp;'.
		'^(C#\.)?BOOST_MODE$:+boost',
	'VIRTUAL_KEY' =>
		'^(C#\.)?PRESS_(SHORT|LONG)$:+pressed',
	'WEATHER' =>
		'^(C#\.)?TEMPERATURE$:+measured-temp;'.
		'^(C#\.)?HUMIDITY$:+humidity',
	'WEATHER_TRANSMIT' =>
		'^(C#\.)?TEMPERATURE$:+measured-temp;'.
		'^(C#\.)?HUMIDITY$:+humidity',
	'DEFAULT' =>
		'^([0-9]{1,2}\.)?SET_TEMPERATURE$:+desired-temp;'.
		'^([0-9]{1,2}\.)?(ACTUAL_TEMPERATURE|TEMPERATURE)$:+measured-temp;'.
		'^([0-9]{1,2}\.)?SET_POINT_TEMPERATURE$:+desired-temp;'.
		'^([0-9]{1,2}\.)?ACTUAL_HUMIDITY$:+humidity;'.
		'^(P#)?WEEK_PROGRAM_POINTER$:+week-program'
);

#######################################################################################
# Set/Get commands related to channel role
#   Role => { Command-Definition, ... }
# Command-Defintion:
#   '[Mode ]Command[:InterfaceExpr]' => '[CombDatapoint ][No:]Datapoint-Def[:Function] [...]'
# Mode:
#   Either 'set' or 'get'. Default is 'set'.
# Command:
#   The command name.
# InterfaceExpr:
#   Command is only available, if interface of device is matching the regular
#   expression.
# CombDatapoint:
#   Either 'COMBINED_PARAMETER' or 'SUBMIT'
#   Datapoint names are combined datapoint shortcuts.
# No:
#   Execution order of subcommands. By default subcommands are executed from left to
#   right.
# Function:
#   A Perl function name
# Datapoint-Def:
#   Command with no parameters:      Paramset:Datapoints:[Parameter=]Value
#   Toggle command:                  Paramset:Datapoints:[Parameter=]Value1,Value2[,...]
#   Command with one parameter:      Paramset:Datapoints:?Parameter
#   Optional parameter with default: Paramset:Datapoints:?Parameter=Default-Value
#   List of values:                  Paramset:Datapoints:#Parameter[=Value[,...]]
#   Internal value (paramset "I"):   I:Datapoints:*Parameter=Default-Value
# Paramset:
#   V=VALUES, M=MASTER (channel), D=MASTER (device), I=INTERNAL, S=VALUE_STRING
# Datapoints:
#   List of datapoint or config parameter names separated by ','. Multiple names can
#   be specified to support multiple firmware revisions with different names.
# Parameter characters:
#   ? = any value is accepted
#   # = If datapoint is of type ENUM, values are taken from parameter set description.
#       Otherwise a list of values must be specified after '='.
#   * = internal value $hash->{hmccu}{values}{parameterName}. See also paramset "I"
# FixedValue:
#   Parameter values are detected in the following order:
#     1. If command parameter name is identical with controldatapoint,
#        option values are taken from controldatapoint definition {V}. The
#        FixedValues are used as lookup key into HMCCU_STATECCONTROL.
#        The command options are identical to the FixedValues.
#     2. FixedValues are treated as option values. The option
#        names are taken from HMCCU_CONVERSIONS by using FixedValues as
#        lookup key.
#     3. As a fallback command options and option values are identical.
# Default-Value:
#   If Default-Value is preceeded by + or -, value is added to or 
#   subtracted from current datapoint value
#######################################################################################

%HMCCU_ROLECMDS = (
	'ACOUSTIC_SIGNAL_TRANSMITTER' => {
		'level' => 'V:LEVEL:?level',
		'on' => 'V:LEVEL:100',
		'off' => 'V:LEVEL:0'
	},
	'ALARM_SWITCH_VIRTUAL_RECEIVER' => {
		'opticalAlarm' => 'V:OPTICAL_ALARM_SELECTION:#alarmMode V:ACOUSTIC_ALARM_SELECTION:0 V:DURATION_UNIT:*unit=0 V:DURATION_VALUE:*duration=10',
		'acousticAlarm' => 'V:ACOUSTIC_ALARM_SELECTION:#alarmMode V:OPTICAL_ALARM_SELECTION:0 V:DURATION_UNIT:0 V:DURATION_VALUE:10',
		'duration' => 'I:DURATION_VALUE:?duration I:DURATION_UNIT:#unit'
	},
	'ARMING' => {
		'armState' => 'V:ARMSTATE:#armState'
	},
	'BLIND' => {
		'pct' => 'V:LEVEL:?level',
		'open' => 'V:LEVEL:100',
		'close' => 'V:LEVEL:0',
		'up' => 'V:LEVEL:?delta=+20',
		'down' => 'V:LEVEL:?delta=-20',
		'oldLevel' => 'V:LEVEL:1.005',
		'stop' => 'V:STOP:1',
		'toggle' => 'V:LEVEL:0,100'
	},
	'BLIND_VIRTUAL_RECEIVER' => {
		'pct' => 'V:LEVEL:?level',
		'open' => 'V:LEVEL:100',
		'close' => 'V:LEVEL:0',
		'oldLevel' => 'V:LEVEL:1.005',
		'up' => 'V:LEVEL:?delta=+20',
		'down' => 'V:LEVEL:?delta=-20',
		'stop' => 'V:STOP:1',
		'pctSlats' => 'V:LEVEL_2:?level V:LEVEL:1.005',
		'openSlats' => 'V:LEVEL_2:100 V:LEVEL:1.005',
		'closeSlats' => 'V:LEVEL_2:0 V:LEVEL:1.005',
		'allLevels' => 'V:LEVEL_2:?slatLevel V:LEVEL:?blindLevel',
		'toggle' => 'V:LEVEL:0,100'
	},
	'CLIMATECONTROL_REGULATOR' => {
		'desired-temp' => 'V:SETPOINT:?temperature',
		'on' => 'V:SETPOINT:30.5',
		'off' => 'V:SETPOINT:4.5'		
	},
	'CLIMATECONTROL_RT_TRANSCEIVER' => {
		'desired-temp' => 'V:SET_TEMPERATURE:?temperature',
		'manu' => 'V:MANU_MODE:?temperature=20',
		'on' => 'V:MANU_MODE:30.5',
		'off' => 'V:MANU_MODE:4.5',
		'auto' => 'V:AUTO_MODE:1',
		'boost' => 'V:BOOST_MODE:#boost=on,off',
		'week-program' => 'D:WEEK_PROGRAM_POINTER:#program',
		'get week-program' => 'D:WEEK_PROGRAM_POINTER:#program:HMCCU_DisplayWeekProgram'
	},
	'DIMMER' => {
		'pct' => '3:V:LEVEL:?level 1:V:ON_TIME:?time=0.0 2:V:RAMP_TIME:?ramp=0.5',
		'level' => 'V:LEVEL:?level',
		'on' => 'V:LEVEL:100',
		'off' => 'V:LEVEL:0',
		'on-for-timer' => 'V:ON_TIME:?duration V:LEVEL:100',
		'on-till' => 'V:ON_TIME:?time V:LEVEL:100',
		'up' => 'V:LEVEL:?delta=+10',
		'down' => 'V:LEVEL:?delta=-10',
		'stop' => 'V:RAMP_STOP:1',
		'toggle' => 'V:LEVEL:0,100'
	},
	'DIMMER_VIRTUAL_RECEIVER' => {
		'pct' => '5:V:LEVEL:?level 1:V:DURATION_UNIT:0 2:V:ON_TIME,DURATION_VALUE:?time=0.0 3:V:RAMP_TIME_UNIT:0 4:V:RAMP_TIME,RAMP_TIME_VALUE:?ramp=0.5',
		'level' => 'V:LEVEL:?level',
		'on' => 'V:LEVEL:100',
		'off' => 'V:LEVEL:0',
		'oldLevel' => 'V:LEVEL:1.005',
		'on-for-timer' => '1:V:DURATION_UNIT:0 2:V:ON_TIME,DURATION_VALUE:?duration 3:V:LEVEL:100',
		'on-till' => '1:V:DURATION_UNIT:0 2:V:ON_TIME,DURATION_VALUE:?time 3:V:LEVEL:100',
		'up' => 'V:LEVEL:?delta=+10',
		'down' => 'V:LEVEL:?delta=-10',
		'color' => 'V:COLOR:#color',
		'toggle' => 'V:LEVEL:0,100'
	},
	'DIMMER_WEEK_PROFILE' => {
		'progMode' => 'V:WEEK_PROGRAM_TARGET_CHANNEL_LOCK:#progMode'
	},
	'DOOR_LOCK_STATE_TRANSMITTER' => {
		'open' => 'V:LOCK_TARGET_LEVEL:2',
		'unlock' => 'V:LOCK_TARGET_LEVEL:1',
		'lock' => 'V:LOCK_TARGET_LEVEL:0'
	},
	'DOOR_RECEIVER' => {
		'open' => 'V:DOOR_COMMAND:1',
		'stop' => 'V:DOOR_COMMAND:2',
		'close' => 'V:DOOR_COMMAND:3',
		'ventilate' => 'V:DOOR_COMMAND:4'
	},
	'HEATING_CLIMATECONTROL_TRANSCEIVER' => {
		# CONTROL_MODE (write): 0=Auto, 1=Manual, 2=Holiday/Party 3=NoFunction
		# SET_POINT_MODE (read): 0=Auto, 1=Manual, 2=Holiday/Party
		# Party: CONTROL_MODE=2, PARTY_TIME_START=Ts, PARTY_TIME_END=Ts, Ts="YYYY_MM_DD HH:MM"
		'desired-temp' => 'V:SET_POINT_TEMPERATURE:?temperature',
		'auto' => 'V:CONTROL_MODE:0',
		'manu' => 'V:CONTROL_MODE:1 V:SET_POINT_TEMPERATURE:?temperature=20',
		'rpcset holiday' => 'V:SET_POINT_MODE:2 V:SET_POINT_TEMPERATURE:?temperature V:PARTY_TIME_START:?timeStart V:PARTY_TIME_END:?timeEnd',
		'rpcset party' => 'V:SET_POINT_MODE:2 V:SET_POINT_TEMPERATURE:?temperature V:PARTY_TIME_START:?timeStart V:PARTY_TIME_END:?timeEnd',
		'boost' => 'V:BOOST_MODE:#boost=on,off',
		'on' => 'V:CONTROL_MODE:1 V:SET_POINT_TEMPERATURE:30.5',
		'off' => 'V:CONTROL_MODE:1 V:SET_POINT_TEMPERATURE:4.5',
		'week-program' => 'V:ACTIVE_PROFILE:#profile=ACTIVE_PROFILE',
		'get week-program' => 'M:*:#profile=ACTIVE_PROFILE:HMCCU_DisplayWeekProgram'
	},
	'JALOUSIE' => {
		'pct' => 'V:LEVEL:?level',
		'open' => 'V:LEVEL:100',
		'close' => 'V:LEVEL:0',
		'up' => 'V:LEVEL:?delta=+20',
		'down' => 'V:LEVEL:?delta=-20',
		'stop' => 'V:STOP:1',
		'oldLevel' => 'V:LEVEL:1.005',
		'pctSlats' => 'V:LEVEL_SLATS:?level',
		'openSlats' => 'V:LEVEL_SLATS:100',
		'closeSlats' => 'V:LEVEL_SLATS:0',
		'allLevels' => 'V:LEVEL_SLATS:?slatLevel V:LEVEL:?blindLevel',
		'toggle' => 'V:LEVEL:0,100'
	},
	'KEY' => {
		'on' => 'V:PRESS_SHORT:1',
		'off' => 'V:PRESS_SHORT:1',
		'press' => 'V:PRESS_SHORT:1',
		'pressLong' => 'V:PRESS_LONG:1'
	},
	'KEYMATIC' => {
		'open' => 'V:OPEN:true',
		'lock' => 'V:STATE:0',
		'unlock' => 'V:STATE:1'
	},
	'MOTIONDETECTOR_TRANSCEIVER' => {
		'detection' => 'V:MOTION_DETECTION_ACTIVE:#detection=inactive,active',
		'reset' => 'V:RESET_MOTION:true'
	},
	'PASSAGE_DETECTOR_DIRECTION_TRANSMITTER' => {
		'detection' => 'M:PASSAGE_DETECTION,CHANNEL_OPERATION_MODE:#inactive,active'
	},
	'PRESENCEDETECTOR_TRANSCEIVER' => {
		'detection' => 'V:PRESENCE_DETECTION_ACTIVE:#detection=inactive,active',
		'reset' => 'V:RESET_PRESENCE:true'
	},
	'RAINDETECTOR_HEAT' => {
		'on' => 'V:STATE:1',
		'off' => 'V:STATE:0',
		'on-for-timer' => 'V:ON_TIME:?duration V:STATE:1',
		'on-till' => 'V:ON_TIME:?time V:STATE:1'
	},
	'RGBW_COLOR' => {
		'color' => 'V:COLOR:?color V:ACT_HSV_COLOR_VALUE:?hsvColor',
		'brightness' => 'V:ACT_BRIGHTNESS:?brightness'
	},
	'SHUTTER_TRANSMITTER' => {
		'calibrate' => 'V:SELF_CALIBRATION:#Mode'
	},
	'SHUTTER_VIRTUAL_RECEIVER' => {
		'pct' => 'V:LEVEL:?level',
		'open' => 'V:LEVEL:100',
		'oldLevel' => 'V:LEVEL:1.005',
		'close' => 'V:LEVEL:0',
		'up' => 'V:LEVEL:?delta=+20',
		'down' => 'V:LEVEL:?delta=-20',
		'stop' => 'V:STOP:1',
		'toggle' => 'V:LEVEL:0,100'
	},
	'SMOKE_DETECTOR' => {
		'command' => 'V:SMOKE_DETECTOR_COMMAND:#command'
	},
	'SWITCH' => {
		'on' => 'V:STATE:1',
		'off' => 'V:STATE:0',
		'on-for-timer' => 'V:ON_TIME:?duration V:STATE:1',
		'on-till' => 'V:ON_TIME:?time V:STATE:1',
		'toggle' => 'V:STATE:0,1'
	},
	'SWITCH_PANIC' => {
		'panic' => 'V:STATE:#panic=on,off',
		'panic-on-for-timer' => 'V:ON_TIME:?duration V:STATE:1',
		'panic-on-till' => 'V:ON_TIME:?time V:STATE:1'
	},
	'SWITCH_SENSOR' => {
		'sensor' => 'V:STATE:#sensor=on,off',
		'sensor-on-for-timer' => 'V:ON_TIME:?duration V:STATE:1',
		'sensor-on-till' => 'V:ON_TIME:?time V:STATE:1'
	},
	'SWITCH_VIRTUAL_RECEIVER' => {
		'on' => 'V:STATE:1',
		'off' => 'V:STATE:0',
		'on-for-timer' => '1:V:ON_TIME:?time=0.0 2:V:STATE:1',
		'on-till' => 'V:ON_TIME:?time V:STATE:1',
		'toggle' => 'V:STATE:0,1'
	},
	'THERMALCONTROL_TRANSMIT' => {
		'desired-temp' => 'V:SET_TEMPERATURE:?temperature',
		'manu' => 'V:MANU_MODE:?temperature=20',
		'on' => 'V:MANU_MODE:30.5',
		'off' => 'V:MANU_MODE:4.5',
		'auto' => 'V:AUTO_MODE:1',
		'boost' => 'V:BOOST_MODE:#boost=on,off',
		'week-program' => 'D:WEEK_PROGRAM_POINTER:#program',
		'get week-program' => 'D:WEEK_PROGRAM_POINTER:#program:HMCCU_DisplayWeekProgram'
	},
	'UNIVERSAL_LIGHT_RECEIVER' => {
		'COMBINED_PARAMETER' => {
			'L' => 'LEVEL',
			'OT'  => 'ON_TIME',
			'H' => 'HUE',
			'SAT' => 'SATURATION'
		},
		'pct' => '5:V:LEVEL:?level 1:V:DURATION_UNIT:0 2:V:DURATION_VALUE:?time=0.0 3:V:RAMP_TIME_UNIT:0 4:V:RAMP_TIME_VALUE:?ramp=0.5',
		'level' => 'V:LEVEL:?level',
		'on' => 'V:LEVEL:100',
		'off' => 'V:LEVEL:0',
		'on-for-timer' => '1:V:DURATION_UNIT:0 2:V:DURATION_VALUE:?duration 3:V:LEVEL:100',
		'on-till' => '1:V:DURATION_UNIT:0 2:V:DURATION_VALUE:?time 3:V:LEVEL:100',
		'up' => 'V:LEVEL:?delta=+10',
		'down' => 'V:LEVEL:?delta=-10',
		'toggle' => 'V:LEVEL:0,100',
		'color' => 'COMBINED_PARAMETER V:L:?level V:H:?hue V:SAT:?saturation'
	},
	'VIRTUAL_KEY' => {
		'on' => 'V:PRESS_SHORT:1',
		'off' => 'V:PRESS_SHORT:1',
		'press' => 'V:PRESS_SHORT:1'
	},
	'WINMATIC' => {
		'open' => 'V:LEVEL:100',
		'close' => 'V:LEVEL:0',
		'lock' => 'V:LEVEL:-0.5',
		'pct' => 'V:LEVEL:?level',
		'stop' => 'V:STOP:1'
	}
);

######################################################################
# Channel roles with attributes
# If key '_none_' exists, role doesn't have default attributes
######################################################################

%HMCCU_ATTR = (
	'BLIND' => {
		'substexcl' => 'pct',
		'cmdIcon' => 'open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down',
		'webCmd' => 'pct:open:close:stop',
		'widgetOverride' => 'pct:slider,0,10,100'
	},
	'BLIND_TRANSMITTER' => {
		'substexcl' => 'pct',
	},
	'BLIND_VIRTUAL_RECEIVER' => {
		'substexcl' => 'pct',
		'cmdIcon' => 'open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down',
		'webCmd' => 'pct:open:close:stop',
		'widgetOverride' => 'pct:slider,0,10,100'
	},
	'DIMMER' => {
		'cmdIcon' => 'on:general_an off:general_aus',
		'substexcl' => 'pct|level',
		'webCmd' => 'level:on:off',
		'widgetOverride' => 'level:slider,0,10,100'
	},
	'DIMMER_TRANSMITTER' => {
		'substexcl' => 'pct|level'
	},
	'DIMMER_VIRTUAL_RECEIVER' => {
		'cmdIcon' => 'on:general_an off:general_aus',
		'substexcl' => 'pct|level',
		'webCmd' => 'level:on:off',
		'widgetOverride' => 'level:slider,0,10,100'
	},
	'DOOR_LOCK_STATE_TRANSMITTER' => {
		'cmdIcon' => 'open:fts_door_open unlock:secur_open lock:secur_locked',
		'webCmd' => 'lock:unlock:open'
	},
	'DOOR_RECEIVER' => {
		'cmdIcon' => 'open:fts_garage_door_up stop:fts_garage_door_manual close:fts_garage_door_down ventilate:fts_garage_door_80',
		'webCmd' => 'open:close:stop:ventilate'
	},
	'JALOUSIE' => {
		'substexcl' => 'pct',
		'cmdIcon' => 'open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down',
		'webCmd' => 'pct:open:close:stop',
		'widgetOverride' => 'pct:slider,0,10,100'
	},
	'KEY' => {
		'event-on-update-reading' => '.*',
		'cmdIcon' => 'press:taster',
		'webCmd' => 'press'
	},
	'KEY_TRANSCEIVER' => {
		'event-on-update-reading' => '.*'
	},
	'KEYMATIC' => {
		'cmdIcon' => 'open:fts_door_right_open lock:secur_locked unlock:secur_open',
		'webCmd' => 'open:lock:unlock'
	},
	'MOTIONDETECTOR_TRANSCEIVER' => {
		'cmdIcon' => 'reset:rc_BACK',
		'webCmd' => 'detection:reset'
	},
	'PRESENCEDETECTOR_TRANSCEIVER' => {
		'cmdIcon' => 'reset:rc_BACK',
		'webCmd' => 'detection:reset'
	},
	'RAINDETECTOR_HEAT' => {
		'cmdIcon' => 'on:general_an off:general_aus'
	},
	'SHUTTER_CONTACT' => {
		'devStateIcon' => 'close:fts_window_1w open:fts_window_1w_open'
	},
	'SHUTTER_CONTACT_TRANSCEIVER' => {
		'devStateIcon' => 'close:fts_window_1w open:fts_window_1w_open'
	},
	'SHUTTER_TRANSMITTER' => {
		'substexcl' => 'pct',
	},
	'SHUTTER_VIRTUAL_RECEIVER' => {
		'substexcl' => 'pct',
		'cmdIcon' => 'open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down',
		'webCmd' => 'pct:open:close:stop',
		'widgetOverride' => 'pct:slider,0,10,100'
	},
	'SWITCH' => {
		'cmdIcon' => 'on:general_an off:general_aus'
	},
	'SWITCH_VIRTUAL_RECEIVER' => {
		'cmdIcon' => 'on:general_an off:general_aus'
	},
	'THERMALCONTROL_TRANSMIT' => {
		'substexcl' => 'desired-temp',
		'cmdIcon' => 'auto:sani_heating_automatic manu:sani_heating_manual on:general_an off:general_aus',
		'webCmd' => 'desired-temp:auto:manu:boost:on:off',
		'widgetOverride' => 'desired-temp:slider,4.5,0.5,30.5,1'
	},
	'UNIVERSAL_LIGHT_RECEIVER' => {
		'cmdIcon' => 'on:general_an off:general_aus',
		'substexcl' => 'pct|level',
		'webCmd' => 'level:on:off',
		'widgetOverride' => 'level:slider,0,10,100'
	},
	'CLIMATECONTROL_RT_TRANSCEIVER' => {
		'substexcl' => 'desired-temp',
		'cmdIcon' => 'auto:sani_heating_automatic manu:sani_heating_manual on:general_an off:general_aus',
		'webCmd' => 'desired-temp:auto:manu:boost:on:off',
		'widgetOverride' => 'desired-temp:slider,4.5,0.5,30.5,1'
	},
	'HEATING_CLIMATECONTROL_TRANSCEIVER' => {
		'substexcl' => 'desired-temp',
		'cmdIcon' => 'auto:sani_heating_automatic manu:sani_heating_manual on:general_an off:general_aus',
		'webCmd' => 'desired-temp:auto:manu:boost:on:off',
		'widgetOverride' => 'desired-temp:slider,4.5,0.5,30.5,1'
	},
	'CLIMATECONTROL_REGULATOR' => {
		'substexcl' => 'desired-temp',
		'cmdIcon' => 'on:general_an off:general_aus',
		'webCmd' => 'desired-temp:on:off',
		'widgetOverride' => 'desired-temp:slider,4.5,0.5,30.5,1'
	},
	'WINMATIC' => {
		'ccuflags' => 'noBoundsChecking',
		'substexcl' => 'pct',
		'cmdIcon' => 'open:fts_window_1w_tilt stop:rc_STOP close:fts_window_1w lock:secur_locked',
		'webCmd' => 'pct:open:close:lock:stop',
		'widgetOverride' => 'pct:slider,0,10,100'
	}
);

######################################################################
# Value conversions
#   Role => {
#     Datapoint => { Value => 'Conversion', ... },
#     ...
#   }
######################################################################

%HMCCU_CONVERSIONS = (
	'ACCELERATION_TRANSCEIVER' => {
		'MOTION' => { '0' => 'noMotion', 'false' => 'noMotion', '1' => 'motion', 'true' => 'motion' }
	},
	'MOTION_DETECTOR' => {
		'MOTION' => { '0' => 'noMotion', 'false' => 'noMotion', '1' => 'motion', 'true' => 'motion' }
	},
	'MOTIONDETECTOR_TRANSCEIVER' => {
		'MOTION' => { '0' => 'noMotion', 'false' => 'noMotion', '1' => 'motion', 'true' => 'motion' },
		'MOTION_DETECTION_ACTIVE' => { '0' => 'inactive', 'false' => 'inactive', '1' => 'active', 'true' => 'active' }
	},
	'PRESENCEDETECTOR_TRANSCEIVER' => {
		'PRESENCE_DETECTION_STATE'  => { '0' => 'noPresence', 'false' => 'noPresence', '1' => 'presence', 'true' => 'presence' },
		'PRESENCE_DETECTION_ACTIVE' => { '0' => 'inactive', 'false' => 'inactive', '1' => 'active', 'true' => 'active' }
	},
	'PASSAGE_DETECTOR_DIRECTION_TRANSMITTER' => {
		'PASSAGE_DETECTION' => { '0' => 'inactive', 1 => 'active' },
		'CHANNEL_OPERATION_MODE' => { '0' => 'inactive', 1 => 'active'}
	},
	'KEY' => {
		'PRESS_SHORT' => { '1' => 'pressed', 'true' => 'pressed' },
		'PRESS_LONG' =>  { '1' => 'pressed', 'true' => 'pressed' }
	},
	'KEY_TRANSCEIVER' => {
		'PRESS_SHORT' => { '1' => 'pressed', 'true' => 'pressed' },
		'PRESS_LONG' =>  { '1' => 'pressed', 'true' => 'pressed' }
	},
	'KEYMATIC' => {
		'STATE' => { '0' => 'locked', 'false' => 'locked', '1' => 'unlocked', 'true' => 'unlocked' }
	},
	'VIRTUAL_KEY' => {
		'PRESS_SHORT' => { '1' => 'pressed', 'true' => 'pressed' },
		'PRESS_LONG' =>  { '1' => 'pressed', 'true' => 'pressed' }
	},
	'RAINDETECTOR' => {
		'STATE' => { '0' => 'dry', 1 => 'rain' }
	},
	'RAINDETECTOR_HEAT' => {
		'STATE' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on' }
	},
	'SHUTTER_CONTACT' => {
		'STATE' => { '0' => 'closed', '1' => 'open', 'false' => 'closed', 'true' => 'open' }
	},
	'SHUTTER_CONTACT_TRANSCEIVER' => {
		'STATE' => { '0' => 'closed', '1' => 'open', 'false' => 'closed', 'true' => 'open' }
	},
	'ROTARY_HANDLE_SENSOR' => {
		'STATE' => { '0' => 'closed', '1' => 'tilted', '2' => 'open' }
	},
	'ROTARY_HANDLE_TRANSCEIVER' => {
		'STATE' => { '0' => 'closed', '1' => 'tilted', '2' => 'open' }
	},
	'ALARM_SWITCH_VIRTUAL_RECEIVER' => {
		'STATE' => { '0' => 'ok', '1' => 'alarm', 'false' => 'ok', 'true' => 'alarm' }
	},
	'SWITCH' => {
		'STATE' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on', 'off' => '0', 'on' => '1' },
	},
	'SWITCH_PANIC' => {
		'STATE' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on', 'off' => '0', 'on' => '1' },
	},
	'SWITCH_SENSOR' => {
		'STATE' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on', 'off' => '0', 'on' => '1' },
	},
	'SWITCH_TRANSMITTER' => {
		'STATE' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on', 'off' => '0', 'on' => '1' },
	},
	'SWITCH_VIRTUAL_RECEIVER' => {
		'STATE' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on', 'off' => '0', 'on' => '1' },
	},
	'BLIND' => {
		'LEVEL' =>     { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' },
		'DIRECTION' => { '0' => 'none', '1' => 'up', '2' => 'down' },
		'WORKING' =>   { '0' => 'no', 'false' => 'no', '1' => 'yes', 'true' => 'yes' }
	},
	'BLIND_TRANSMITTER' => {
		'LEVEL' =>     { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' }
	},
	'BLIND_VIRTUAL_RECEIVER' => {
		'LEVEL' =>     { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' },
		'DIRECTION' => { '0' => 'none', '1' => 'up', '2' => 'down' },
		'WORKING' =>   { '0' => 'no', 'false' => 'no', '1' => 'yes', 'true' => 'yes' }
	},
	'JALOUSIE' => {
		'LEVEL' =>       { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' },
		'LEVEL_SLATS' => { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' },
		'DIRECTION' =>   { '0' => 'none', '1' => 'up', '2' => 'down' },
		'WORKING' =>     { '0' => 'no', 'false' => 'no', '1' => 'yes', 'true' => 'yes' }
	},
	'SHUTTER_TRANSMITTER' => {
		'LEVEL' =>     { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' }
	},
	'SHUTTER_VIRTUAL_RECEIVER' => {
		'LEVEL' => { '0' => 'closed', '100' => 'open', 'closed' => '0', 'open' => '100' }
	},
	'DIMMER' => {
		'LEVEL' =>     { '0' => 'off', '100' => 'on', 'off' => '0', 'on' => '100' },
		'DIRECTION' => { '0' => 'none', '1' => 'up', '2' => 'down' },
		'WORKING' =>   { '0' => 'no', 'false' => 'no', '1' => 'yes', 'true' => 'yes' }
	},
	'DIMMER_TRANSMITTER' => {
		'LEVEL' =>     { '0' => 'off', '100' => 'on', 'off' => '0', 'on' => '100' },
		'DIRECTION' => { '0' => 'none', '1' => 'up', '2' => 'down' },
		'WORKING' =>   { '0' => 'no', 'false' => 'no', '1' => 'yes', 'true' => 'yes' }
	},
	'DIMMER_VIRTUAL_RECEIVER' => {
		'LEVEL' =>     { '0' => 'off', '100' => 'on', 'off' => '0', 'on' => '100' },
		'DIRECTION' => { '0' => 'none', '1' => 'up', '2' => 'down' },
		'WORKING' =>   { '0' => 'no', 'false' => 'no', '1' => 'yes', 'true' => 'yes' }
	},
	'THERMALCONTROL_TRANSMIT' => {
		'SET_TEMPERATURE' =>       { '4.5' => 'off', '30.5' => 'on' },
		'WINDOW_OPEN_REPORTING' => { '0' => 'closed', '1' => 'open', 'false' => 'closed', 'true' => 'open' },
		'BOOST_MODE' =>            { '0' => 'off', '1' => 'on', 'false' => 'off', 'true' => 'on', 'off' => 0, 'on' => 1 }
	},
	'CLIMATECONTROL_RT_TRANSCEIVER' => {
		'SET_TEMPERATURE' => { '4.5' => 'off', '30.5' => 'on' },
		'BOOST_MODE' =>      { '0' => 'off', '1' => 'on', 'false' => 'off', 'true' => 'on', 'off' => 0, 'on' => 1 }
	},
	'HEATING_CLIMATECONTROL_TRANSCEIVER' => {
		'SET_POINT_TEMPERATURE' => { '4.5' => 'off', '30.5' => 'on' },
		'SET_POINT_MODE' =>        { '0' => 'auto', '1' => 'manual', '2' => 'party/holiday', '3' => 'off' },
		'WINDOW_STATE' =>          { '0' => 'closed', '1' => 'open', 'false' => 'closed', 'true' => 'open' },
		'BOOST_MODE' =>            { '0' => 'off', '1' => 'on', 'false' => 'off', 'true' => 'on', 'off' => 0, 'on' => 1 }
	},
	'CLIMATECONTROL_REGULATOR' => {
		'SETPOINT' => { '4.5' => 'off', '30.5' => 'on' }		
	},
	'UNIVERSAL_LIGHT_RECEIVER' => {
		'LEVEL' => { '0' => 'off', '100' => 'on', 'off' => '0', 'on' => '100' }
	},
	'WATER_DETECTION_TRANSMITTER' => {
		'ALARMSTATE' => { '0' => 'noAlarm', '1' => 'alarm', 'false' => 'noAlarm', 'true' => 'alarm' }
	},
	'WINMATIC' => {
		'LEVEL' => { '0' => 'closed', '100' => 'open', '-0.5' => 'locked' }
	},
	'DEFAULT' => {
		'AES_KEY' => { '0' => 'off', 'false' => 'off', '1' => 'on', 'true' => 'on' },
		'LOW_BAT' => { '0' => 'ok', 'false' => 'ok', '1' => 'low', 'true' => 'low' },
		'LOWBAT' =>  { '0' => 'ok', 'false' => 'ok', '1' => 'low', 'true' => 'low' },
		'STATE' =>   { '0' => 'false', '1' => 'true' },
		'UNREACH' => { '0' => 'alive', 'false' => 'alive', '1' => 'dead', 'true' => 'dead' }
	}
);

######################################################################
# Default attributes for Homematic devices of type HMCCUCHN
######################################################################

%HMCCU_CHN_DEFAULTS = (
	"HM-Sec-SCo|HM-Sec-SC|HM-Sec-SC-2|HMIP-SWDO" => {
	_description     => "Tuer/Fensterkontakt optisch und magnetisch",
	_channels        => "1",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR!7:sabotage;SABOTAGE!1:sabotage",
	statedatapoint   => "STATE",
	substitute       => "STATE!(0|false):closed,(1|true):open"
	},
	"HmIP-SWDO-I" => {
	_description     => "Tuer/Fensterkontakt verdeckt",
	_channels        => "1",
	ccureadingfilter => "STATE",
	hmstatevals      => "SABOTAGE!1:sabotage",
	statedatapoint   => "STATE",
	substitute       => "STATE!(0|false):closed,(1|true):open"
	},
	"HM-Sec-RHS|HM-Sec-RHS-2" => {
	_description     => "Fenster Drehgriffkontakt",
	_channels        => "1",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR!1:sabotage",
	statedatapoint   => "STATE",
	substitute       => "STATE!0:closed,1:tilted,2:open;ERROR!0:no,1:sabotage"
	},
	"HmIP-SRH" => {
	_description     => "Fenster Drehgriffkontakt",
	_channels        => "1",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	substitute       => "STATE!0:closed,1:tilted,2:open"
	},
	"HmIP-SAM" => {
	_description     => "Beschleunigungssensor",
	_channels        => "1",
	ccureadingfilter => "MOTION",
	statedatapoint   => "MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes"
	},
	"HM-Sec-Key|HM-Sec-Key-S|HM-Sec-Key-O|HM-Sec-Key-Generic" => {
	_description     => "Funk-Tuerschlossantrieb KeyMatic",
	_channels        => "1",
	ccureadingfilter => "(STATE|INHIBIT)",
   eventMap         => "/datapoint OPEN true:open/",
	hmstatevals      => "ERROR!1:clutch_failure,2:motor_aborted",
	statedatapoint   => "STATE",
   statevals        => "lock:false,unlock:true",
   substitute       => "STATE!(0|false):locked,(1|true):unlocked,2:open;INHIBIT!(0|false):no,(1|true):yes;STATE_UNCERTAIN!(1|true):manual;DIRECTION!0:none,1:up,2:down,3:undefined;ERROR!0:no,1:clutch_failure,2:motor_aborted"
	},
	"HM-LC-Sw1-Pl-CT-R1" => {
	_description     => "Schaltaktor mit Klemmanschluss",
	_channels        => "1",
	ccureadingfilter => "(STATE|WORKING)",
	cmdIcon          => "press:general_an",
	eventMap         => "/on-for-timer 1:press/",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(0|false):off,(1|true):on;WORKING!(0|false):no,(1|true):yes",
	webCmd           => "press"
	},
	"HM-LC-Sw1-Pl-2|HM-LC-Sw1-Pl-DN-R1" => {
	_description     => "Steckdose",
	_channels        => "1",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "devstate",
	widgetOverride   => "devstate:uzsuToggle,off,on"
	},
	"HmIP-PS" => {
	_description     => "Steckdose",
	_channels        => "3",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "devstate",
	widgetOverride   => "devstate:uzsuToggle,off,on"
	},
	"HM-LC-Dim1L-Pl|HM-LC-Dim1L-Pl-2|HM-LC-Dim1L-CV|HM-LC-Dim2L-CV|HM-LC-Dim2L-SM|HM-LC-Dim1L-Pl-3|HM-LC-Dim1L-CV-2" => {
	_description     => "Funk-Anschnitt-Dimmaktor",
	_channels        => "1",
	ccureadingfilter => "(^LEVEL\$|DIRECTION)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "LEVEL",
	hmstatevals      => "ERROR!1:load_failure",
	statedatapoint   => "LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR!0:no,1:load_failure:yes;LEVEL!#0-0:off,#1-100:on",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-LC-Dim1PWM-CV|HM-LC-Dim1PWM-CV-2" => {
	_description     => "Funk-PWM-Dimmaktor",
	_channels        => "1",
	ccureadingfilter => "(^LEVEL\$|DIRECTION)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "LEVEL",
	hmstatevals      => "ERROR_REDUCED!1:error_reduced;ERROR_OVERHEAT!1:error_overheat",
	statedatapoint   => "LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR_REDUCED,ERROR_OVERHEAT!(0|false):no,(1|true):yes;LEVEL!#0-0:off,#1-100:on;DIRECTION!0:none,1:up,2:down,3:undefined",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HmIP-BDT" => {
	_description     => "Dimmaktor",
	_channels        => "4",
	ccureadingfilter => "(ERROR_CODE|ERROR_OVERHEAT|ACTUAL_TEMPERATURE|ACTIVITY_STATE|LEVEL)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	controldatapoint => "LEVEL",
	hmstatevals      => "ACTUAL_TEMPERATURE_STATUS!2:tempOverflow,3:tempUnderflow;ERROR_OVERHEAT!(1|true):overheat",
	statedatapoint   => "LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LEVEL!#0-0:off,#1-100:on;ACTIVITY_STATE!0:unknown,1:up,2:down,3:stop;ERROR_OVERHEAT!(0|false):no,(1|true):yes;ACTUAL_TEMPERATURE_STATUS!0:normal,1:unknown,2:overflow,3:underflow",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-LC-Dim1T-Pl|HM-LC-Dim1T-CV|HM-LC-Dim1T-FM|HM-LC-Dim1T-CV-2|HM-LC-Dim2T-SM|HM-LC-Dim2T-SM-2|HM-LC-Dim1T-DR|HM-LC-Dim1T-FM-LF|HM-LC-Dim1T-FM-2|HM-LC-Dim1T-Pl-3|HM-LC-Dim1TPBU-FM|HM-LC-Dim1TPBU-FM-2" => {
	_description     => "Funk-Abschnitt-Dimmaktor",
	_channels        => "1",
	ccureadingfilter => "(^LEVEL\$|DIRECTION)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "LEVEL",
	hmstatevals      => "ERROR_REDUCED!1:error_reduced;ERROR_OVERHEAT!1:error_overheat;ERROR_OVERLOAD!1:error_overload",
	statedatapoint   => "LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR_OVERHEAT,ERROR_OVERLOAD,ERROR_REDUCED!(0|false):no,(1|true):yes;LEVEL!#0-0:off,#1-100:on;DIRECTION!0:none,1:up,2:down,3:undefined",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HmIP-FCI6" => {
	_description     => "IP Kontaktschnittstelle Unterputz 6-fach",
	_channels        => "1,2,3,4,5,6",
	ccureadingfilter => "STATE",
	controldatapoint => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(0|false):off,(1|true):on",
	webCmd           => "devstate",
	widgetOverride   => "devstate:uzsuToggle,off,on"
	},
	"HM-PB-2-FM" => {
	_description     => "Funk-Wandtaster 2-fach",
	_channels        => "1,2",
	ccureadingfilter => "PRESS",
	statedatapoint   => "PRESS_SHORT",
	statevals        => "press:true",
	substitute       => "PRESS_SHORT,PRESS_LONG,PRESS_CONT!(1|true):pressed,(0|false):released;PRESS_LONG_RELEASE!(0|false):no,(1|true):yes"
	},
	"HmIP-WRC6" => {
	_description     => "Wandtaster 6-fach",
	_channels        => "1,2,3,4,5,6",
	ccureadingfilter => "PRESS",
	statedatapoint   => "PRESS_SHORT",
	statevals        => "press:true",
	substitute       => "PRESS_SHORT,PRESS_LONG!(1|true):pressed,(0|false):released"
	},
	"HM-SwI-3-FM" => {
	_description     => "Funk-Schalterschnittstelle",
	_channels        => "1,2,3",
	ccureadingfilter => "PRESS",
	statedatapoint   => "PRESS",
	statevals        => "press:true",
	substitute       => "PRESS!(1|true):pressed,(0|false):released"
	},
	"HM-PBI-4-FM" => {
	_description     => "Funk-Tasterschnittstelle",
	_channels        => "1,2,3,4",
	ccureadingfilter => "PRESS",
	statedatapoint   => "PRESS_SHORT",
	statevals        => "press:true",
	substitute       => "PRESS_SHORT,PRESS_LONG,PRESS_CONT!(1|true):pressed,(0|false):released;PRESS_LONG_RELEASE!(0|false):no,(1|true):yes"
	},
	"HM-RC-Key4-2|HM-RC-Key4-3|HM-RC-Sec4-2|HM-RC-Sec4-3" => {
	_description     => "Funk-Handsender",
	_channels        => "1,2,3,4",
	ccureadingfilter => "PRESS",
	"event-on-update-reading" => ".*",
	statedatapoint   => "PRESS_SHORT",
	substitute       => "PRESS_SHORT,PRESS_LONG!(1|true):pressed"
	},
	"HM-LC-Sw1PBU-FM" => {
	_description     => "Unterputz Schaltaktor für Markenschalter",
	_channels        => "1",
	ccureadingfilter => "STATE",
	controldatapoint => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-LC-Sw2PBU-FM" => {
	_description     => "Funk-Schaltaktor 2-fach",
	_channels        => "1,2",
	ccureadingfilter => "STATE",
	controldatapoint => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"	
	},
	"HmIP-BSM" => {
	_description     => "Schalt-Mess-Aktor",
	_channels        => "4",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	controldatapoint => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"		
	},
	"HM-SCI-3-FM" => {
	_description     => "3 Kanal Schliesserkontakt",
	_channels        => "1,2,3",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HM-MOD-Re-8" => {
	_description     => "8 Kanal Empfangsmodul",
	_channels        => "1,2,3,4,5,6,7,8",
	ccureadingfilter => "(STATE|WORKING)",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;WORKING!(1|true):yes,(0|false):no"	
	},
	"HM-LC-Sw1-Pl|HM-LC-Sw1-Pl-2|HM-LC-Sw1-SM|HM-LC-Sw1-FM|HM-LC-Sw1-PB-FM|HM-LC-Sw1-DR" => {
	_description     => "1 Kanal Funk-Schaltaktor",
	_channels        => "1",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"	
	},
	"HM-LC-Sw2-SM|HM-LC-Sw2-FM|HM-LC-Sw2-PB-FM|HM-LC-Sw2-DR" => {
	_description     => "2 Kanal Funk-Schaltaktor",
	_channels        => "1,2",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"	
	},
	"HM-LC-Sw4-DR|HM-LC-Sw4-WM|HM-LC-Sw4-PCB|HM-LC-Sw4-SM" => {
	_description     => "4 Kanal Funk-Schaltaktor",
	_channels        => "1,2,3,4",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"	
	},
	"HM-LC-Bl1PBU-FM|HM-LC-Bl1-FM|HM-LC-Bl1-SM|HM-LC-BlX|HM-LC-Bl1-SM-2|HM-LC-Bl1-FM-2|HM-LC-Ja1PBU-FM" => {
	_description     => "Jalousienaktor",
	_channels        => "1",
	ccureadingfilter => "(LEVEL|INHIBIT|DIRECTION|WORKING)",
	ccureadingname   => "LEVEL:+pct",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "LEVEL",
	eventMap         => "/datapoint STOP true:stop/datapoint LEVEL 0:down/datapoint LEVEL 100:up/",
	statedatapoint   => "LEVEL",
	stripnumber      => 1,
	substexcl        => "control|pct",
	substitute       => "LEVEL!#0-0:closed,#100-100:open;DIRECTION!0:stop,1:up,2:down,3:undefined;WORKING!(0|false):no,(1|true):yes",
	webCmd           => "control:up:stop:down",
	widgetOverride   => "control:slider,0,10,100"
	},
	"HmIP-BROLL|HmIP-FROLL" => {
	_description     => "Rollladenaktor",
	_channels        => "4",
	ccureadingfilter => "(ERROR_CODE|ERROR_OVERHEAT|ACTUAL_TEMPERATURE|LEVEL|ACTIVITY_STATE)",
	ccureadingname   => "LEVEL:+pct",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "LEVEL",
	hmstatevals      => "ACTUAL_TEMPERATURE_STATUS!2:tempOverflow,3:tempUnderflow;ERROR_OVERHEAT!(1|true):overheat",
	eventMap         => "/datapoint STOP true:stop/datapoint LEVEL 0:down/datapoint LEVEL 100:up/",
	statedatapoint   => "LEVEL",
	stripnumber      => 1,
	substexcl        => "control|pct",
	substitute       => "LEVEL!#0-0:closed,#100-100:open;ACTIVITY_STATE!0:unknown,1:up,2:down,3:stop;ERROR_OVERHEAT!(0|false):no,(1|true):yes;ACTUAL_TEMPERATURE_STATUS!0:normal,1:unknown,2:overflow,3:underflow",
	webCmd           => "control:up:stop:down",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-WDS40-TH-I|HM-WDS10-TH-O|HM-WDS20-TH-O|IS-WDS-TH-OD-S-R3|ASH550I|ASH550" => {
	_description     => "Temperatur/Luftfeuchte Sensor",
	_channels        => "1",
	ccureadingfilter => "(^HUMIDITY|^TEMPERATURE)",
	statedatapoint   => "TEMPERATURE",
	stripnumber      => 1
	},
	"HM-WDS100-C6-O-2" => {
	_description     => "Funk-Kombisensor",
	_channels        => "1",
	ccureadingfilter => "(HUMIDITY|TEMPERATURE|WIND|RAIN|SUNSHINE|BRIGHTNESS)",
	statedatapoint   => "TEMPERATURE",
	stripnumber      => 1,
	substitute       => "RAINING!(1|true):yes,(0|false):no"
	},
	"HmIP-SWO-PR|HmIP-SWO-B|HmIP-SWO-PL" => {
	_description     => "Funk-Wettersensor",
	_channels        => "1",
	ccureadingfilter => "1!.*",
	stripnumber      => 1,
	substitute       => "RAINING,RAIN_COUNTER_OVERFLOW,SUNSHINEDURATION_OVERFLOW,SUNSHINE_THRESHOLD_OVERRUN,WIND_THRESHOLD_OVERRUN!(0|false):no,(1|true):yes"
	},
	"HM-Sec-MD|HM-Sec-MDIR|HM-Sec-MDIR-2|HM-Sec-MDIR-3|Hm-Sen-MDIR-O-3" => {
	_description     => "Bewegungsmelder",
	_channels        => "1",
	ccureadingfilter => "(BRIGHTNESS|MOTION)",
	hmstatevals      => "ERROR!1:sabotage",
	statedatapoint   => "MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes;ERROR!0:no,1:sabotage"
	},
	"HmIP-SMI" => {
	_description     => "Bewegungsmelder",
	_channels        => "1",
	ccureadingfilter => "(ILLUMINATION|MOTION)",
	controldatapoint => "MOTION_DETECTION_ACTIVE",
	eventMap         => "/datapoint RESET_MOTION 1:reset/datapoint MOTION_DETECTION_ACTIVE 1:detection-on/datapoint MOTION_DETECTION_ACTIVE 0:detection-off/",
   hmstatevals      => "SABOTAGE!(1|true):sabotage",
	statedatapoint   => "MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes;MOTION_DETECTION_ACTIVE!(0|false):off,(1|true):on",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HmIP-SPI" => {
	_description     => "Anwesenheitssensor",
	_channels        => "1",
	ccureadingfilter => "(ILLUMINATION|PRESENCE)",
	controldatapoint => "PRESENCE_DETECTION_ACTIVE",
	eventMap         => "/datapoint RESET_PRESENCE 1:reset/datapoint PRESENCE_DETECTION_ACTIVE 1:detection-on/datapoint PRESENCE_DETECTION_ACTIVE 0:detection-off/",
	hmstatevals      => "SABOTAGE!(1|true):sabotage",
	statedatapoint   => "PRESENCE_DETECTION_STATE",
	stripnumber      => 1,
	substitute       => "PRESENCE_DETECTION_STATE!(0|false):no,(1|true):yes;PRESENCE_DETECTION_ACTIVE!(0|false):off,(1|true):on",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-Sen-LI-O" => {
	_description     => "Lichtsensor",
	_channels        => "1",
	ccureadingfilter => "LUX",
	statedatapoint   => "LUX",
	stripnumber      => 1
	},
	"HmIP-SLO" => {
	_description     => "Lichtsensor",
	_channels        => "1",
	ccureadingfilter => "_ILLUMINATION\$",
	statedatapoint   => "CURRENT_ILLUMINATION",
	stripnumber      => 1
	},
	"HM-CC-SCD" => {
	_description     => "CO2 Sensor",
	_channels        => "1",
	statedatapoint   => "STATE",
	substitute       => "STATE!0:normal,1:added,2:strong"
	},
	"HM-Sec-SD-2" => {
	_description     => "Funk-Rauchmelder",
	_channels        => "1",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR_ALARM_TEST!1:alarm_test_failed;ERROR_SMOKE_CHAMBER!1:degraded_smoke_chamber",
	statedatapoint   => "STATE",
	substitute       => "ERROR_ALARM_TEST!0:no,1:failed;ERROR_SMOKE_CHAMBER!0:no,1:degraded"	
	},
	"HmIP-SWSD" => {
	_description     => "Funk-Rauchmelder",
	_channels        => "1",
	ccureadingfilter => "(ALARM_STATUS|TEST_RESULT|ERROR_CODE)",
	eventMap         => "/datapoint SMOKE_DETECTOR_COMMAND  0:reservedAlarmOff/datapoint SMOKE_DETECTOR_COMMAND  1:intrusionAlarmOff/datapoint SMOKE_DETECTOR_COMMAND  2:intrusionAlarmOn/datapoint SMOKE_DETECTOR_COMMAND  3:smokeTest/datapoint SMOKE_DETECTOR_COMMAND  4:comTest/datapoint SMOKE_DETECTOR_COMMAND  5:comTestRepeat/",
	statedatapoint   => "SMOKE_DETECTOR_ALARM_STATUS",
	substitute       => "SMOKE_DETECTOR_ALARM_STATUS!0:noAlarm,1:primaryAlarm,2:intrusionAlarm,3:secondaryAlarm;SMOKE_DETECTOR_TEST_RESULT!0:none,1:smokeTestOK,2:smokeTestFailed,3:comTestSent,4:comTestOK"
	},
	"HM-Sec-SFA-SM" => {
	_description     => "Alarmsirene",
	_channels        => "1",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR_POWER!1:power_failure;ERROR_SABOTAGE!1:sabotage;ERROR_BATTERY!1:battery_defect",
	statedatapoint   => "STATE",
	substitute       => "STATE!(0|false):off,(1|true):alarm;ERROR_POWER!0:no,1:failure;ERROR_SABOTAGE!0:no,1:sabotage;ERROR_BATTERY!0:no,1:defect"
	},
	"WS550|WS888|WS550Tech|WS550LCB|WS550LCW|HM-WDC7000" => {
	_description     => "Wetterstation",
	_channels        => "10",
	ccureadingfilter => "(TEMPERATURE|HUMIDITY|AIR_PRESSURE)",
	statedatapoint   => "TEMPERATURE",
	stripnumber      => 1
	},
	"HM-Sec-WDS|HM-Sec-WDS-2" => {
	_description     => "Funk-Wassermelder",
	_channels        => "1",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	substitute       => "STATE!0:dry,1:wet,2:water"	
	},
	"HM-WDS30-OT2-SM|HM-WDS30-OT2-SM-2" => {
	_description     => "Temperaturdifferenz-Sensor",
	_channels        => "1,2,3,4,5",
	ccureadingfilter => "TEMPERATURE",
	statedatapoint   => "TEMPERATURE",
	stripnumber      => 1
	},
	"HM-OU-LED16|HM-OU-X" => {
	_description     => "Statusanzeige 16 Kanal LED",
	_channels        => "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16",
	ccureadingfilter => "PRESS_SHORT|LED_STATUS",
	eventMap         => "/datapoint LED_SLEEP_MODE 0:sleep-off/datapoint LED_SLEEP_MODE 1:sleep-on/",
	statedatapoint   => "LED_STATUS",
	statevals        => "off:0,red:1,green:2,orange:3",
	substitute       => "LED_STATUS!0:off,1:red:2:green:3:orange"
	}
);

######################################################################
# Default attributes for Homematic devices of type HMCCUDEV
######################################################################

%HMCCU_DEV_DEFAULTS = (
   "CCU2" => {
   _description     => "HomeMatic CCU",
   "ccudef-readingformat" => 'datapoint'
   },
	"HM-Sec-SCo|HM-Sec-SC|HM-Sec-SC-2|HMIP-SWDO" => {
	_description     => "Tuer/Fensterkontakt optisch und magnetisch",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR!7:sabotage;SABOTAGE!1:sabotage",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!(0|false):closed,(1|true):open"
	},
	"HmIP-SWDO-I" => {
	_description     => "Tuer/Fensterkontakt verdeckt",
	ccureadingfilter => "STATE",
	hmstatevals      => "SABOTAGE!1:sabotage",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!(0|false):closed,(1|true):open"
	},
	"HM-Sec-RHS|HM-Sec-RHS-2" => {
	_description     => "Fenster Drehgriffkontakt",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR!1:sabotage",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!0:closed,1:tilted,2:open;ERROR!0:no,1:sabotage"
	},
	"HMIP-SRH" => {
	_description     => "Fenster Drehgriffkontakt",
	ccureadingfilter => "STATE",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!0:closed,1:tilted,2:open"
	},
	"HmIP-SAM" => {
	_description     => "Beschleunigungssensor",
	ccureadingfilter => "1.MOTION",
	statedatapoint   => "1.MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes"
	},
	"HM-Sec-Key|HM-Sec-Key-S|HM-Sec-Key-O|HM-Sec-Key-Generic" => {
	_description     => "Funk-Tuerschlossantrieb KeyMatic",
	ccureadingfilter => "(STATE|INHIBIT)",
   eventMap         => "/datapoint 1.OPEN true:open/",
	hmstatevals      => "ERROR!1:clutch_failure,2:motor_aborted",
	statedatapoint   => "1.STATE",
   statevals        => "lock:false,unlock:true",
   substitute       => "STATE!(0|false):locked,(1|true):unlocked,2:open;INHIBIT!(0|false):no,(1|true):yes;STATE_UNCERTAIN!(1|true):manual;DIRECTION!0:none,1:up,2:down,3:undefined;ERROR!0:no,1:clutch_failure,2:motor_aborted"
	},
	"HM-Sec-Win|HM-Sec-Win-Generic" => {
	_description     => "WinMatic",
	ccureadingfilter => "(STATE_UNCERTAIN|INHIBIT|LEVEL|STATUS)",
	ccuscaleval      => "LEVEL:0:1:0:100,SPEED:0.1:0:100",
	eventMap         => "/datapoint 1.STOP true:stop/",
	statedatapoint   => "1.LEVEL",
	statevals        => "open:100,close:0",
	stripnumber      => 1,
   substitute       => "LEVEL!-0.005:locked,#0-0:closed,#100-100:open;INHIBIT!(0|false):no,(1|true):yes;ERROR!0:no,1:motor_turn,2:motor_tilt;STATUS!0:trickle_charge,1:charge,2:discharge,3:unknown"
	},
	"HM-LC-Sw1-Pl-CT-R1" => {
	_description     => "Schaltaktor mit Klemmanschluss",
	ccureadingfilter => "(STATE|WORKING)",
	cmdIcon          => "press:general_an",
	eventMap         => "/on-for-timer 1:press/",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(0|false):off,(1|true):on;WORKING!(0|false):no,(1|true):yes",
	webCmd           => "press"
	},
	"HM-LC-Sw1-Pl-2|HM-LC-Sw1-Pl-DN-R1" => {
	_description     => "Steckdose",
	ccureadingfilter => "STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "devstate",
	widgetOverride   => "devstate:uzsuToggle,off,on"
	},
	"HMIP-PS" => {
	_description     => "Steckdose IP",
	ccureadingfilter => "STATE",
	statedatapoint   => "3.STATE",
	statevals        => "on:1,off:0",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "devstate",
	widgetOverride   => "devstate:uzsuToggle,off,on"
	},
	"HM-ES-PMSw1-Pl|HM-ES-PMSw1-Pl-DN-R1|HM-ES-PMSw1-Pl-DN-R2|HM-ES-PMSw1-Pl-DN-R3|HM-ES-PMSw1-Pl-DN-R4|HM-ES-PMSw1-Pl-DN-R5" => {
	_description     => "Steckdose mit Energiemessung",
	ccureadingfilter => "(STATE|CURRENT|ENERGY_COUNTER|POWER)",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:1,off:0",
	stripnumber      => 1,
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HMIP-PSM" => {
	_description     => "Steckdose mit Energiemessung IP",
	ccureadingfilter => "3.STATE;6.(CURRENT|^ENERGY_COUNTER\$|POWER)",
	controldatapoint => "3.STATE",
	statedatapoint   => "3.STATE",
	statevals        => "on:true,off:false",
	stripnumber      => 1,
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-LC-Dim1L-Pl|HM-LC-Dim1L-Pl-2|HM-LC-Dim1L-CV|HM-LC-Dim2L-CV|HM-LC-Dim2L-SM|HM-LC-Dim1L-Pl-3|HM-LC-Dim1L-CV-2" => {
	_description     => "Funk-Anschnitt-Dimmaktor",
	ccureadingfilter => "(^LEVEL\$|DIRECTION)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "1.LEVEL",
	hmstatevals      => "ERROR!1:load_failure",
	statedatapoint   => "1.LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR!0:no,1:load_failure;LEVEL!#0-0:off,#1-100:on",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-LC-Dim1PWM-CV|HM-LC-Dim1PWM-CV-2" => {
	_description     => "Funk-PWM-Dimmaktor",
	ccureadingfilter => "(^LEVEL\$|DIRECTION)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "1.LEVEL",
	hmstatevals      => "ERROR_REDUCED!1:error_reduced;ERROR_OVERHEAT!1:error_overheat",
	statedatapoint   => "1.LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR_REDUCED,ERROR_OVERHEAT!(0|false):no,(1|true):yes;LEVEL!#0-0:off,#1-100:on;DIRECTION!0:none,1:up,2:down,3:undefined",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-LC-Dim1T-Pl|HM-LC-Dim1T-CV|HM-LC-Dim1T-FM|HM-LC-Dim1T-CV-2|HM-LC-Dim2T-SM|HM-LC-Dim2T-SM-2|HM-LC-Dim1T-DR|HM-LC-Dim1T-FM-LF|HM-LC-Dim1T-FM-2|HM-LC-Dim1T-Pl-3|HM-LC-Dim1TPBU-FM|HM-LC-Dim1TPBU-FM-2" => {
	_description     => "Funk-Abschnitt-Dimmaktor",
	ccureadingfilter => "(^LEVEL\$|DIRECTION)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "1.LEVEL",
	hmstatevals      => "ERROR_REDUCED!1:error_reduced;ERROR_OVERHEAT!1:error_overheat;ERROR_OVERLOAD!1:error_overload",
	statedatapoint   => "1.LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR_OVERHEAT,ERROR_OVERLOAD,ERROR_REDUCED!(0|false):no,(1|true):yes;LEVEL!#0-0:off,#1-100:on;DIRECTION!0:none,1:up,2:down,3:undefined",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HmIP-BDT" => {
	_description     => "Dimmaktor",
	ccureadingfilter => "(ERROR_CODE|ERROR_OVERHEAT|ACTUAL_TEMPERATURE|ACTIVITY_STATE|LEVEL)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	controldatapoint => "4.LEVEL",
	hmstatevals      => "ACTUAL_TEMPERATURE_STATUS!2:tempOverflow,3:tempUnderflow;ERROR_OVERHEAT!(1|true):overheat",
	statedatapoint   => "4.LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LEVEL!#0-0:off,#1-100:on;ACTIVITY_STATE!0:unknown,1:up,2:down,3:stop;ERROR_OVERHEAT!(0|false):no,(1|true):yes;ACTUAL_TEMPERATURE_STATUS!0:normal,1:unknown,2:overflow,3:underflow",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-PB-2-FM" => {
	_description     => "Funk-Wandtaster 2-fach",
	ccureadingfilter => "PRESS",
	substitute       => "PRESS_SHORT,PRESS_LONG,PRESS_CONT!(1|true):pressed,(0|false):released;PRESS_LONG_RELEASE!(0|false):no,(1|true):yes"
	},
	"HmIP-WRC6" => {
	_description     => "Wandtaster 6-fach",
	ccureadingfilter => "PRESS",
	substitute       => "PRESS_SHORT,PRESS_LONG!(1|true):pressed,(0|false):released"
	},
	"HmIP-BSL" => {
	_description     => "Schaltaktor mit Signalleuchte",
	ccureadingfilter => "(LEVEL|STATE|COLOR|PRESS)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	statedatapoint   => "4.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(0|false):off,(1|true):on;COLOR!0:black,1:blue,2:green,3:turquoise,4:red,5:purple,6:yellow,7:white"
	},
	"HM-SwI-3-FM" => {
	_description     => "Funk-Schalterschnittstelle",
	ccureadingfilter => "PRESS",
	statevals        => "press:true",
	substitute       => "PRESS!(1|true):pressed,(0|false):released"
	},
	"HM-PBI-4-FM" => {
	_description     => "Funk-Tasterschnittstelle",
	ccureadingfilter => "PRESS",
	substitute       => "PRESS_SHORT,PRESS_LONG,PRESS_CONT!(1|true):pressed,(0|false):released;PRESS_LONG_RELEASE!(0|false):no,(1|true):yes"
	},
	"HM-RC-Key4-2|HM-RC-Key4-3|HM-RC-Sec4-2|HM-RC-Sec4-3" => {
	_description     => "Funk-Handsender",
	ccureadingfilter => "PRESS",
	"event-on-update-reading" => ".*",
	substitute       => "PRESS_SHORT,PRESS_LONG!(1|true):pressed"
	},
	"HM-LC-Sw1PBU-FM" => {
	_description     => "Unterputz Schaltaktor für Markenschalter",
	ccureadingfilter => "STATE",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-LC-Sw2PBU-FM" => {
	_description     => "Funk-Schaltaktor 2-fach",
	ccureadingfilter => "STATE",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"	
	},
	"HmIP-BSM" => {
	_description     => "Schalt-Mess-Aktor",
	ccureadingfilter => "(STATE|PRESS)",
	statedatapoint   => "4.STATE",
	controldatapoint => "4.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"		
	},
	"HM-LC-SW4-BA-PCB|HM-SCI-3-FM" => {
	_description     => "4 Kanal Funk Schaltaktor für Batteriebetrieb, 3 Kanal Schließerkontakt",
	ccureadingfilter => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HM-MOD-Re-8" => {
	_description     => "8 Kanal Empfangsmodul",
	ccureadingfilter => "(STATE|WORKING)",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;WORKING!(1|true):yes,(0|false):no"	
	},
	"HM-LC-Sw1-Pl|HM-LC-Sw1-Pl-2|HM-LC-Sw1-SM|HM-LC-Sw1-FM|HM-LC-Sw1-PB-FM|HM-LC-Sw1-DR" => {
	_description     => "1 Kanal Funk-Schaltaktor",
	ccureadingfilter => "STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"	
	},
	"HM-LC-Bl1PBU-FM|HM-LC-Bl1-FM|HM-LC-Bl1-SM|HM-LC-BlX|HM-LC-Bl1-SM-2|HM-LC-Bl1-FM-2|HM-LC-Ja1PBU-FM" => {
	_description     => "Jalousienaktor",
	ccureadingfilter => "(LEVEL|INHIBIT|DIRECTION|WORKING)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "1.LEVEL",
	eventMap         => "/datapoint 1.STOP true:stop/datapoint 1.LEVEL 0:down/datapoint 1.LEVEL 100:up/",
	statedatapoint   => "1.LEVEL",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LEVEL!#0-0:closed,#100-100:open;DIRECTION!0:none,1:up,2:down,3:undefined;WORKING!(0|false):no,(1|true):yes",
	webCmd           => "control:up:stop:down",
	widgetOverride   => "control:slider,0,10,100"
	},
	"HmIP-BROLL|HmIP-FROLL" => {
	_description     => "Rollladenaktor",
	ccureadingfilter => "3.LEVEL;(ERROR_CODE|ERROR_OVERHEAT|ACTUAL_TEMPERATURE|ACTIVITY_STATE|SELF_CALIBRATION_RESULT)",
	ccureadingname   => "3.LEVEL\$:+control,+pct",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "4.LEVEL",
	hmstatevals      => "ACTUAL_TEMPERATURE_STATUS!2:tempOverflow,3:tempUnderflow;ERROR_OVERHEAT!(1|true):overheat",
	eventMap         => "/datapoint 4.STOP true:stop/datapoint 4.LEVEL 0:down/datapoint 4.LEVEL 100:up/datapoint 3.SELF_CALIBRATION 0:stopCalibration/datapoint 3.SELF_CALIBRATION 1:startCalibration/",
	statedatapoint   => "3.LEVEL",
	stripnumber      => 1,
	substexcl        => "control|pct",
	substitute       => "LEVEL!#0-0:closed,#100-100:open;ACTIVITY_STATE!0:unknown,1:up,2:down,3:stop;ERROR_OVERHEAT!(0|false):no,(1|true):yes;ACTUAL_TEMPERATURE_STATUS!0:normal,1:unknown,2:overflow,3:underflow;SELF_CALIBRATION_RESULT!(0|false):failed,(1|true):ok",
	webCmd           => "control:up:stop:down",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-TC-IT-WM-W-EU" => {
	_description     => "Wandthermostat",
	ccureadingfilter => "(^HUMIDITY|^TEMPERATURE|^SET_TEMPERATURE|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "2.SET_TEMPERATURE",
	eventMap         => "/datapoint 2.MANU_MODE 20.0:Manu/datapoint 2.AUTO_MODE 1:Auto/datapoint 2.BOOST_MODE 1:Boost/datapoint 2.MANU_MODE 4.5:off/datapoint 2.MANU_MODE 30.5:on/",
	genericDeviceType => "thermostat",
	statedatapoint   => "2.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed;SET_TEMPERATURE!#0-3.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HM-CC-RT-DN" => {
	_description     => "Heizkoerperthermostat",
	ccureadingfilter => "(TEMPERATURE|VALVE_STATE|CONTROL|BATTERY_STATE)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "4.SET_TEMPERATURE",
	eventMap         => "/datapoint 4.MANU_MODE 20.0:Manu/datapoint 4.AUTO_MODE 1:Auto/datapoint 4.BOOST_MODE 1:Boost/datapoint 4.MANU_MODE 4.5:off/datapoint 4.MANU_MODE 30.5:on/",
	genericDeviceType => "thermostat",
	hmstatevals      => "FAULT_REPORTING!1:valve_tight,2:range_too_large,3:range_too_small,4:communication_error,5:other_error,6:battery_low,7:valve_error_pos",
	statedatapoint   => "4.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;SET_TEMPERATURE!#0-4.5:off,#30.5-40:on;FAULT_REPORTING!0:no,1:valve_tight,2:range_too_large,3:range_too_small,4:communication_error,5:other_error,6:battery_low,7:valve:error_pos",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HmIP-eTRV|HmIP-eTRV-2|HmIP-eTRV-B1" => {
	_description     => "Heizkoerperthermostat HM-IP",
	ccureadingfilter => "^ACTUAL_TEMPERATURE|^BOOST_MODE|^SET_POINT_MODE|^SET_POINT_TEMPERATURE|^LEVEL|^WINDOW_STATE",
	ccureadingname   => "1.LEVEL:valve_position",
	ccuscaleval      => "LEVEL:0:1:0:100",
	controldatapoint => "1.SET_POINT_TEMPERATURE",
	eventMap         => "/datapoint 1.BOOST_MODE true:Boost/datapoint 1.CONTROL_MODE 0:Auto/datapoint 1.CONTROL_MODE 1:Manual/datapoint 1.CONTROL_MODE 2:Holiday/datapoint 1.CONTROL_MODE 1 1.SET_POINT_TEMPERATURE 4.5:off/datapoint 1.CONTROL_MODE 0 1.SET_POINT_TEMPERATURE 30.5:on/",
	genericDeviceType => "thermostat",
	statedatapoint   => "1.SET_POINT_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "SET_POINT_TEMPERATURE!#0-4.5:off,#30.5-40:on;WINDOW_STATE!(0|false):closed,(1|true):open",
	webCmd           => "control:Boost:Auto:Manual:Holiday:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HmIP-WTH|HmIP-WTH-2|HmIP-BWTH" => {
	_description     => "Wandthermostat HM-IP",
	ccureadingfilter => ".*",
	controldatapoint => "1.SET_POINT_TEMPERATURE",
	eventMap         => "/datapoint 1.BOOST_MODE true:Boost/datapoint 1.CONTROL_MODE 0:Auto/datapoint 1.CONTROL_MODE 1:Manual/datapoint 1.CONTROL_MODE 2:Holiday/datapoint 1.SET_POINT_TEMPERATURE 4.5:off/datapoint 1.SET_POINT_TEMPERATURE 30.5:on/",
	genericDeviceType => "thermostat",
	statedatapoint   => "1.SET_POINT_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "SET_POINT_TEMPERATURE!#0-4.5:off,#30.5-40:on;WINDOW_STATE!(0|false):closed,(1|true):open",
	webCmd           => "control:Boost:Auto:Manual:Holiday:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HM-WDS40-TH-I|HM-WDS10-TH-O|HM-WDS20-TH-O|IS-WDS-TH-OD-S-R3|ASH550I|ASH550" => {
	_description     => "Temperatur/Luftfeuchte Sensor",
	ccureadingfilter => "(^HUMIDITY|^TEMPERATURE)",
	statedatapoint   => "1.TEMPERATURE",
	stripnumber      => 1
	},
	"HM-Sen-RD-O" => {
	_description     => "Regensensor",
	ccureadingfilter => "(STATE|WORKING)",
	controldatapoint => "2.STATE",
	eventMap         => "/datapoint 2.STATE 1:on/datapoint 2.STATE 0:off/",
	statedatapoint   => "1.STATE",
	substitute       => "1.STATE!(0|false):dry,(1|true):rain;2.STATE!(0|false):off,(1|true):on",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-WDS100-C6-O-2" => {
	_description     => "Funk-Kombisensor",
	ccureadingfilter => "(HUMIDITY|TEMPERATURE|WIND|RAIN|SUNSHINE|BRIGHTNESS)",
	statedatapoint   => "1.TEMPERATURE",
	stripnumber      => 1,
	substitute       => "RAINING!(1|true):yes,(0|false):no"
	},
	"HmIP-SWO-PR|HmIP-SWO-B|HmIP-SWO-PL" => {
	_description     => "Funk-Wettersensor",
	ccureadingfilter => "1!.*",
	stripnumber      => 1,
	substitute       => "RAINING,RAIN_COUNTER_OVERFLOW,SUNSHINEDURATION_OVERFLOW,SUNSHINE_THRESHOLD_OVERRUN,WIND_THRESHOLD_OVERRUN!(0|false):no,(1|true):yes"
	},
	"HM-ES-TX-WM" => {
	_description     => "Energiezaehler Sensor",
	ccureadingfilter => "(ENERGY_COUNTER|POWER)"
	},
	"HM-CC-VG-1" => {
	_description     => "Heizungsgruppe",
	ccucalculate     => "dewpoint:DEWPOINT:1.ACTUAL_TEMPERATURE,1.ACTUAL_HUMIDITY",
	ccureadingfilter => "1.(^SET_TEMPERATURE|^ACTUAL|^VALVE|^CONTROL);2.^WINDOW_OPEN;4.^VALVE",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "1.SET_TEMPERATURE",
	eventMap         => "/datapoint 1.MANU_MODE 20.0:Manu/datapoint 1.AUTO_MODE 1:Auto/datapoint 1.BOOST_MODE 1:Boost/datapoint 1.MANU_MODE 4.5:off/datapoint 1.MANU_MODE 30.5:on/",
	statedatapoint   => "1.SET_TEMPERATURE",
	stateFormat      => "T: 1.ACTUAL_TEMPERATURE° H: 1.ACTUAL_HUMIDITY% D: 1.SET_TEMPERATURE° P: DEWPOINT° V: 4.VALVE_STATE% 1.CONTROL_MODE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed;SET_TEMPERATURE!#0-4.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HM-Sec-MD|HM-Sec-MDIR|HM-Sec-MDIR-2|HM-Sec-MDIR-3|Hm-Sen-MDIR-O-3" => {
	_description     => "Bewegungsmelder",
	ccureadingfilter => "(BRIGHTNESS|MOTION)",
	hmstatevals      => "ERROR!1:sabotage",
	statedatapoint   => "1.MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes;ERROR!0:no,1:sabotage"
	},
	"HmIP-SMI" => {
	_description     => "Bewegungsmelder",
	ccureadingfilter => "(ILLUMINATION|MOTION)",
	controldatapoint => "1.MOTION_DETECTION_ACTIVE",
	eventMap         => "/datapoint 1.RESET_MOTION 1:reset/datapoint 1.MOTION_DETECTION_ACTIVE 1:detection-on/datapoint 1.MOTION_DETECTION_ACTIVE 0:detection-off/",
   hmstatevals      => "SABOTAGE!(1|true):sabotage",
	statedatapoint   => "1.MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes;MOTION_DETECTION_ACTIVE!(0|false):off,(1|true):on",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HmIP-SMI55" => {
	_description     => "Bewegungsmelder",
	ccureadingfilter => "(ILLUMINATION|MOTION|PRESS)",
	"event-on-update-reading" => ".*",
	eventMap         => "/datapoint 3.MOTION_DETECTION_ACTIVE 1:detection-on/datapoint 3.MOTION_DETECTION_ACTIVE 0:detection-off/datapoint 3.RESET_MOTION 1:reset/",
	statedatapoint   => "3.MOTION",
	substitute       => "PRESS_LONG,PRESS_SHORT!(1|true):pressed,(0|false):released;MOTION,MOTION_DETECTION_ACTIVE!(0|false):no,(1|true):yes;ILLUMINATION_STATUS!0:normal,1:unknown,2:overflow"
	},
	"HmIP-SPI" => {
	_description     => "Anwesenheitssensor",
	ccureadingfilter => "(ILLUMINATION|PRESENCE)",
	controldatapoint => "1.PRESENCE_DETECTION_ACTIVE",
	eventMap         => "/datapoint 1.RESET_PRESENCE 1:reset/datapoint 1.PRESENCE_DETECTION_ACTIVE 1:detection-on/datapoint 1.PRESENCE_DETECTION_ACTIVE 0:detection-off/",
	hmstatevals      => "SABOTAGE!(1|true):sabotage",
	statedatapoint   => "1.PRESENCE_DETECTION_STATE",
	stripnumber      => 1,
	substitute       => "PRESENCE_DETECTION_STATE!(0|false):no,(1|true):yes;PRESENCE_DETECTION_ACTIVE!(0|false):off,(1|true):on",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-Sen-LI-O" => {
	_description     => "Lichtsensor",
	ccureadingfilter => "LUX",
	statedatapoint   => "1.LUX",
	stripnumber      => 1
	},
	"HmIP-SLO" => {
	_description     => "Lichtsensor",
	ccureadingfilter => "_ILLUMINATION\$",
	statedatapoint   => "1.CURRENT_ILLUMINATION",
	stripnumber      => 1
	},
	"HM-CC-SCD" => {
	_description     => "CO2 Sensor",
	ccureadingfilter => "STATE",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!0:normal,1:added,2:strong"
	},
	"HM-Sec-SD-2" => {
	_description     => "Funk-Rauchmelder",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR_ALARM_TEST!1:alarm_test_failed;ERROR_SMOKE_CHAMBER!1:degraded_smoke_chamber",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!(0|false):ok,(1|true):alarm;ERROR_ALARM_TEST!0:no,1:failed;ERROR_SMOKE_CHAMBER!0:no,1:degraded"
	},
	"HM-Sec-SD-2-Team" => {
	_description     => "Rauchmeldergruppe",
	ccureadingfilter => "STATE",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!(0|false):ok,(1|true):alarm"
	},
	"HmIP-SWSD" => {
	_description     => "Funk-Rauchmelder",
	ccureadingfilter => "(ALARM_STATUS|TEST_RESULT|ERROR_CODE)",
	eventMap         => "/datapoint 1.SMOKE_DETECTOR_COMMAND  0:reservedAlarmOff/datapoint 1.SMOKE_DETECTOR_COMMAND  1:intrusionAlarmOff/datapoint 1.SMOKE_DETECTOR_COMMAND  2:intrusionAlarmOn/datapoint 1.SMOKE_DETECTOR_COMMAND  3:smokeTest/datapoint 1.SMOKE_DETECTOR_COMMAND  4:comTest/datapoint 1.SMOKE_DETECTOR_COMMAND  5:comTestRepeat/",
	statedatapoint   => "SMOKE_DETECTOR_ALARM_STATUS",
	substitute       => "SMOKE_DETECTOR_ALARM_STATUS!0:noAlarm,1:primaryAlarm,2:intrusionAlarm,3:secondaryAlarm;SMOKE_DETECTOR_TEST_RESULT!0:none,1:smokeTestOK,2:smokeTestFailed,3:comTestSent,4:comTestOK"
	},
	"HM-Sec-SFA-SM" => {
	_description     => "Alarmsirene",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR_POWER!1:power_failure;ERROR_SABOTAGE!1:sabotage;ERROR_BATTERY!1:battery_defect",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!(0|false):off,(1|true):alarm;ERROR_POWER!0:no,1:failure;ERROR_SABOTAGE!0:no,1:sabotage;ERROR_BATTERY!0:no,1:defect"
	},
	"HM-Sec-Sir-WM" => {
	_description     => "Funk-Innensirene",
	ccureadingfilter => "STATE",
	ccureadingname   => "1.STATE:STATE_SENSOR1;2.STATE:STATE_SENSOR2;3.STATE:STATE_PANIC",
	eventMap         => "/datapoint 3.STATE true:panic/",
	hmstatevals      => "ERROR_SABOTAGE!1:sabotage",
	statedatapoint   => "4.ARMSTATE",
	statevals        => "disarmed:0,extsens-armed:1,allsens-armed:2,alarm-blocked:3",
	substitute       => "ERROR_SABOTAGE!(0|false):no,(1|true):yes;ARMSTATE!0:disarmed,1:extsens_armed,2:allsens_armed,3:alarm_blocked"
	},
	"HM-LC-RGBW-WM" => {
	_description     => "Funk-RGBW-Controller",
	ccureadingfilter => "(COLOR|PROGRAM|LEVEL)",
	ccureadingname   => "2.COLOR:+color;3.PROGRAM:+prog",
	controldatapoint => "1.LEVEL",
	ccuscaleval      => "LEVEL:0:1:0:100",
	eventMap         => "/datapoint 3.PROGRAM :prog/datapoint 2.COLOR :color/",
	statedatapoint   => "1.LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LEVEL!#0-0:off,#1-100:on",
	webCmd           => "control:color:prog:on:off",
	widgetOverride   => "control:slider,0,1,100 prog:0,1,2,3,4,5,6 color:colorpicker,HUE,0,1,100"
	},
	"WS550|WS888|WS550Tech|WS550LCB|WS550LCW|HM-WDC7000" => {
	_description     => "Wetterstation",
	ccureadingfilter => "(TEMPERATURE|HUMIDITY|AIR_PRESSURE)",
	statedatapoint   => "10.TEMPERATURE",
	stripnumber      => 1
	},
	"HM-Sec-WDS|HM-Sec-WDS-2" => {
	_description     => "Funk-Wassermelder",
	ccureadingfilter => "STATE",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!0:dry,1:wet,2:water"	
	},
	"HM-WDS30-OT2-SM|HM-WDS30-OT2-SM-2" => {
	_description     => "Temperaturdifferenz-Sensor",
	ccureadingfilter => "TEMPERATURE",
	stripnumber      => 1
	},
	"HM-OU-CF-Pl|HM-OU-CFM-Pl|HM-OU-CFM-TW" => {
	_description     => "Funk-Gong mit Signalleuchte mit/ohne Batterie und Speicher",
	ccureadingfilter => "STATE",
	eventMap         => "/datapoint 1.STATE 1:led-on/datapoint 1.STATE 0:led-off/datapoint 2.STATE 1:sound-on/datapoint 2.STATE 0:sound-off",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "1.STATE!(0|false):ledOff,(1|true):ledOn;2.STATE!(0|false):soundOff,(1|true):soundOn"
	},
	"HM-PB-4Dis-WM" => {
	_description     => "Funk-Display Wandtaster",
	ccureadingfilter => "(PRESS_SHORT|PRESS_LONG)",
	substitute       => "PRESS_SHORT,PRESS_LONG!(1|true):pressed"
	},
	"HM-Dis-EP-WM55|HM-Dis-WM55" => {
	_description     => "E-Paper Display, Display Statusanzeige",
	ccureadingfilter => "PRESS",
	eventMap         => "/datapoint 3.SUBMIT:display/",
	substitute       => "PRESS_LONG,PRESS_SHORT,PRESS_CONT!(1|true):pressed,(0|false):notPressed;PRESS_LONG_RELEASE!(1|true):release",
	widgetOverride   => "display:textField"
	},
	"CUX-HM-TC-IT-WM-W-EU" => {
	_description     => "CUxD Wandthermostat",
	ccureadingfilter => "(TEMP|HUM|DEW)",
	stripnumber      => 1
	}
);

######################################################################
# Homematic scripts.
# Scripts can be executed via HMCCU set command 'hmscript'. Script
# name must be preceeded by a '!'.
# Example:
#  set mydev hmscript !CreateStringVariable MyVar test "Test variable"
######################################################################

%HMCCU_SCRIPTS = (
	"ActivateProgram" => {
		description => "Activate or deactivate a CCU program",
		syntax      => "name, mode",
		parameters  => 2,
		code        => qq(
object oPR = (dom.GetObject(ID_PROGRAMS)).Get("\$name");
if (oPR) {
  oPR.Active(\$mode);
}
		)
	},
	"CreateStringVariable" => {
		description => "Create CCU system variable of type STRING",
		syntax      => "name, unit, init, desc",
		parameters  => 4,
		code        => qq(
object oSV = dom.GetObject("\$name");
if (!oSV) {
  object oSysVars = dom.GetObject(ID_SYSTEM_VARIABLES);
  oSV = dom.CreateObject(OT_VARDP);
  oSysVars.Add(oSV.ID());
  oSV.Name("\$name");
  oSV.ValueType(ivtString);
  oSV.ValueSubType(istChar8859);
  oSV.DPInfo("\$desc");
  oSV.ValueUnit("\$unit");
  oSV.State("\$init");
  oSV.Internal(false);
  oSV.Visible(true);
  dom.RTUpdate(0);
}
else {
  oSV.State("\$init");
}
		)
	},
	"CreateNumericVariable" => {
		description => "Create CCU system variable of type FLOAT",
		syntax      => "name, unit, init, desc, min, max",
		parameters  => 6,
		code        => qq(
object oSV = dom.GetObject("\$name");
if (!oSV) {   
  object oSysVars = dom.GetObject(ID_SYSTEM_VARIABLES);
  oSV = dom.CreateObject(OT_VARDP);
  oSysVars.Add(oSV.ID());
  oSV.Name("\$name");
  oSV.ValueType(ivtFloat);
  oSV.ValueSubType(istGeneric);
  oSV.ValueMin(\$min);
  oSV.ValueMax(\$max);
  oSV.DPInfo("\$desc");
  oSV.ValueUnit("\$unit");
  oSV.State("\$init");
  oSV.Internal(false);
  oSV.Visible(true);
  dom.RTUpdate(0);
}
else {
  oSV.State("\$init");
}
		)
	},
	"CreateBoolVariable" => {
		description => "Create CCU system variable of type BOOL",
		syntax      => "name, unit, init, desc, valtrue, valfalse",
		parameters  => 6,
		code        => qq(
object oSV = dom.GetObject("\$name");
if (!oSV) {   
  object oSysVars = dom.GetObject(ID_SYSTEM_VARIABLES);
  oSV = dom.CreateObject(OT_VARDP);
  oSysVars.Add(oSV.ID());
  oSV.Name("\$name");
  oSV.ValueType(ivtBinary);
  oSV.ValueSubType(istBool);
  oSV.ValueName0("\$value1");
  oSV.ValueName1("\$value2");    
  oSV.DPInfo("\$desc");
  oSV.ValueUnit("\$unit");
  oSV.State("\$init");
  dom.RTUpdate(0);
}
else {
  oSV.State("\$init");
}
		)
	},
	"CreateListVariable" => {
		description => "Create CCU system variable of type LIST",
		syntax      => "name, unit, init, desc, list",
		parameters  => 5,
		code        => qq(
object oSV = dom.GetObject("\$name");
if (!oSV){   
  object oSysVars = dom.GetObject(ID_SYSTEM_VARIABLES);
  oSV = dom.CreateObject(OT_VARDP);
  oSysVars.Add(oSV.ID());
  oSV.Name("\$name");
  oSV.ValueType(ivtInteger);
  oSV.ValueSubType(istEnum);
  oSV.ValueList("\$list");
  oSV.DPInfo("\$desc");
  oSV.ValueUnit("\$unit");
  oSV.State("\$init");
  dom.RTUpdate(0);
}
else {
  oSV.State("\$init");
}
		)
	},
	"DeleteObject" => {
		description => "Delete CCU object",
		syntax      => "name, type",
		parameters  => 2,
		code        => qq(
object oSV = dom.GetObject("\$name");
if (oSV) {
  if (oSV.IsTypeOf(\$type)) {
    dom.DeleteObject(oSV.ID());
  }
}
		)
	},
	"GetVariables" => {
		description => "Query system variables",
		syntax      => "",
		parameters  => 0,
		code        => qq(
object osysvar;
string ssysvarid;
foreach (ssysvarid, (dom.GetObject(ID_SYSTEM_VARIABLES)).EnumIDs()) {
  osysvar = dom.GetObject(ssysvarid);
  Write(osysvar.Name());
  if(osysvar.ValueSubType() == 6) {
    Write ("=" # osysvar.AlType());
  }
  else {
    Write ("=" # osysvar.Variable());
  }
  WriteLine ("=" # osysvar.Value());
}
		)
	},
	"GetVariablesExt" => {
		description => "Query system variables",
		syntax      => "",
		parameters  => 0,
		code        => qq(
string sSysVarId;
foreach (sSysVarId, (dom.GetObject(ID_SYSTEM_VARIABLES)).EnumIDs()) {
  object oSysVar = dom.GetObject(sSysVarId);
  Write(oSysVar.Name());               
  if (oSysVar.ValueSubType() == 6) {
    Write(";" # oSysVar.AlType());
  } else {
    Write(";" # oSysVar.Variable());
  }
  Write(";" # oSysVar.Value() # ";");
  if (oSysVar.ValueType() == 16) {
    Write(oSysVar.ValueList());
  }
  Write(";" # oSysVar.ValueMin() # ";" # oSysVar.ValueMax());
  Write(";" # oSysVar.ValueUnit() # ";" # oSysVar.ValueType() # ";" # oSysVar.ValueSubType());
  Write(";" # oSysVar.DPArchive() # ";" # oSysVar.Visible());
  Write(";" # oSysVar.Timestamp().ToInteger());
  if (oSysVar.ValueType() == 2) {
    Write(";" # oSysVar.ValueName0());
  }
  if (oSysVar.ValueType() == 2) {
    Write(";" # oSysVar.ValueName1());
  }
  WriteLine("");
}
		)
	},
	"GetDeviceInfo" => {
		description => "Query device info",
		syntax      => "devname, ccuget",
		parameters  => 2,
		code        => qq(
string chnid;
string sDPId;
object odev = (dom.GetObject(ID_DEVICES)).Get("\$devname");
if (odev) {
  string intid=odev.Interface();
  string intna=dom.GetObject(intid).Name();
  WriteLine ("D;" # intna # ";" # odev.Address() # ";" # odev.Name() # ";" # odev.HssType());
  foreach (chnid, odev.Channels()) {
    object ochn = dom.GetObject(chnid);
    if (ochn) {
      foreach(sDPId, ochn.DPs()) {
        object oDP = dom.GetObject(sDPId);
        if (oDP) {
          integer op = oDP.Operations();
          string flags = "";
          if (OPERATION_READ & op) { flags = flags # "R"; }
          if (OPERATION_WRITE & op) { flags = flags # "W"; }
          if (OPERATION_EVENT & op) { flags = flags # "E"; }
          WriteLine ("C;" # ochn.Address() # ";" # ochn.Name() # ";" # oDP.Name() # ";" # oDP.ValueType() # ";" # oDP.\$ccuget() # ";" # flags);
        }
      }
    }
  }
}
else {
  WriteLine ("ERROR: Device not found");
}
		)
	},
	"GetDevice" => {
		description => "Query CCU device or channel",
		syntax      => "name",
		parameters  => 1,
		code        => qq(
object odev = (dom.GetObject(ID_DEVICES)).Get("\$name");
if (!odev) {
  object ochn = (dom.GetObject(ID_CHANNELS)).Get("\$name");
  if(ochn) {
    string devid = ochn.Device();
    odev = dom.GetObject (devid);
  }
}
if(odev) {
  string intid=odev.Interface();
  string intna=dom.GetObject(intid).Name();
  string chnid;
  integer cc=0;
  foreach (chnid, odev.Channels()) {
    object ochn=dom.GetObject(chnid);
    WriteLine("C;" # ochn.Address() # ";" # ochn.Name() # ";" # ochn.ChnDirection());
    cc=cc+1;
  }
  WriteLine("D;" # intna # ";" # odev.Address() # ";" # odev.Name() # ";" # odev.HssType() # ";" # cc);
}
		)
	},
	"GetDeviceList" => {
		description => "Query CCU devices, channels and interfaces",
		syntax      => "",
		parameters  => 0,
		code        => qq(
string devid;
string chnid;
string sifid;
string prgid;
foreach(devid, root.Devices().EnumUsedIDs()) {
  object odev=dom.GetObject(devid);
  if(odev) {
    var intid=odev.Interface();
    object oiface=dom.GetObject(intid);
    if(oiface) {
      string intna=oiface.Name();
      integer cc=0;
      foreach (chnid, odev.Channels()) {
        object ochn=dom.GetObject(chnid);
        WriteLine("C;" # ochn.Address() # ";" # ochn.Name() # ";" # ochn.ChnDirection());
        cc=cc+1;
      }
      WriteLine("D;" # intna # ";" # odev.Address() # ";" # odev.Name() # ";" # odev.HssType() # ";" # cc);
    }
  }
}
foreach(sifid, root.Interfaces().EnumIDs()) {
  object oIf=dom.GetObject(sifid);
  if (oIf) {
    WriteLine("I;" # oIf.Name() # ';' # oIf.InterfaceInfo() # ';' # oIf.InterfaceUrl());
  }
}
string prgid;
foreach(prgid, dom.GetObject(ID_PROGRAMS).EnumIDs()) {
  object oProg=dom.GetObject(prgid);
  if(oProg) {
    WriteLine ("P;" # oProg.Name() # ";" # oProg.Active() # ";" # oProg.Internal());
  }
}
		)
	},
	"GetDatapointsByChannel" => {
		description => "Query datapoints of channel list",
		syntax      => "list, ccuget",
		parameters  => 2,
		code        => qq(
string sDPId;
string sChnName;
string sChnList = "\$list";
integer c = 0;
foreach (sChnName, sChnList.Split(",")) {
  object oChannel = dom.GetObject (sChnName);
  if (oChannel) {
    foreach(sDPId, oChannel.DPs()) {
      object oDP = dom.GetObject(sDPId);
      if (oDP) {
        if (OPERATION_READ & oDP.Operations()) {
          if (oDP.TypeName() == "HSSDP") {
            WriteLine (sChnName # "=" # oDP.Name() # "=" # oDP.\$ccuget());
          }
          else {
            WriteLine (sChnName # "=sysvar.link." # oDP.Name() # "=" # oDP.\$ccuget());
          }
          c = c+1;
        }
      }
    }
  }
}
WriteLine (c);
		)
	},
	"GetDatapointsByDevice" => {
		description => "Query datapoints of device list",
		syntax      => "list, ccuget",
		parameters  => 2,
		code        => qq(
string chnid;
string sDPId;
string sDevName;
string sDevList = "\$list";
integer c = 0;
foreach (sDevName, sDevList.Split(",")) {
  object odev = (dom.GetObject(ID_DEVICES)).Get(sDevName);
  if (odev) {
    foreach (chnid, odev.Channels()) {
	   object ochn = dom.GetObject(chnid);
      if (ochn) {
		  foreach(sDPId, ochn.DPs()) {
		    object oDP = dom.GetObject(sDPId);
          if (oDP) {
            if (OPERATION_READ & oDP.Operations()) {
              if (oDP.TypeName() == "HSSDP") {
                WriteLine (ochn.Name() # "=" # oDP.Name() # "=" # oDP.\$ccuget());
              }
              else {
                WriteLine (ochn.Name() # "=sysvar.link." # oDP.Name() # "=" # oDP.\$ccuget());
              }
              c = c+1;
            }
          }
        }
      }
    }
  }
}
WriteLine (c);
		)
	},
	"GetDatapointList" => {
		description => "Query datapoint information of device list",
		syntax      => "list",
		parameters  => 1,
		code        => qq(
string chnid;
string sDPId;
string sDevice;
string sDevList = "\$list";
foreach (sDevice, sDevList.Split(",")) {
  object odev = (dom.GetObject(ID_DEVICES)).Get(sDevice);
  if (odev) {
    string intid = odev.Interface();
    string intna = dom.GetObject(intid).Name();
    string sType = odev.HssType();
    foreach (chnid, odev.Channels()) {
      object ochn = dom.GetObject(chnid);
      if (ochn) {
        string sAddr = ochn.Address();
        string sChnNo = sAddr.StrValueByIndex(":",1);
        foreach(sDPId, ochn.DPs()) {
          object oDP = dom.GetObject(sDPId);
          if (oDP) {
            string sDPName = oDP.Name();
            if (sDPName.Find(".") >= 0) {
              sDPName = sDPName.StrValueByIndex(".",2);
            }
            WriteLine (intna # ";" # sAddr # ";" # sType # ";" # sChnNo # ";" # sDPName # ";" # oDP.ValueType() # ";" # oDP.Operations());
          }
        }
      }
    }
  }
}
		)
	},
	"GetChannel" => {
		description => "Get datapoints of channel list",
		syntax      => "list, ccuget",
		parameters  => 2,
		code        => qq(
string sDPId;
string sChannel;
string sChnList = "\$list";
foreach (sChannel, sChnList.Split(",")) {
  object oChannel = (dom.GetObject(ID_CHANNELS)).Get(sChannel);
  if (oChannel) {
    foreach(sDPId, oChannel.DPs()) {
      object oDP = dom.GetObject(sDPId);
      if (oDP) {
        WriteLine (sChannel # "=" # oDP.Name() # "=" # oDP.\$ccuget());
      }
    }
  }
}
		)
	},
	"GetInterfaceList" => {
		description => "Get CCU RPC interfaces",
		syntax      => "",
		parameters  => 0,
		code        => qq(
string sifId;
foreach(sifId, root.Interfaces().EnumIDs()) {
  object oIf = dom.GetObject(sifId);
  if (oIf) {
    WriteLine (oIf.Name() # ';' # oIf.InterfaceInfo() # ';' # oIf.InterfaceUrl());
  }
}
		)
	},
	"ClearUnreachable" => {
		description => "Clear device unreachable alarms in CCU",
		syntax      => "",
		parameters  => 0,
		code        => qq(
string itemID;
string address;
object aldp_obj;
foreach(itemID, dom.GetObject(ID_DEVICES).EnumUsedIDs()) {
  address = dom.GetObject(itemID).Address();
  aldp_obj = dom.GetObject("AL-" # address # ":0.STICKY_UNREACH");
  if (aldp_obj) {
    if (aldp_obj.Value()) {
      aldp_obj.AlReceipt();
    }
  }
}
		)
	},
	"GetNameByAddress" => {
		description => "Get device or channel name by address",
		syntax      => "iface, address",
		parameters  => 2,
		code        => qq(
object lObjDevice = xmlrpc.GetObjectByHSSAddress(interfaces.Get("\$iface"),"\$address");
if (lObjDevice) {
  WriteLine (lObjDevice.Name());
}
		)
	},
	"GetGroupDevices" => {
		description => "Get virtual group configuration",
		syntax      => "",
		parameters  => 0,
		code        => qq(
string lGetOut = "";
string lGetErr = "";
string lCommand = "cat /usr/local/etc/config/groups.gson";
integer lResult;
lResult = system.Exec(lCommand,&lGetOut,&lGetErr);
if(lResult == 0) {
  WriteLine(lGetOut);
}
		)
	},
	"GetVersion" => {
		description => "Get CCU version information",
		syntax      => "",
		parameters  => 0,
		code        => qq(
string lGetOut = "";
string lGetErr = "";
string lCommand = "cat /VERSION";
integer lResult;
lResult = system.Exec(lCommand,&lGetOut,&lGetErr);
if(lResult == 0) {
  WriteLine(lGetOut);
}
		)
	},
	"GetMetaData" => {
		description => "Read metadata of device or channel",
		syntax      => "name",
		parameters  => 1,
		code        => qq(
string name = "\$name";
string ignore = "AUTOCONF,DEVDESC,MASTERDESC,LINKCOUNT,PARAMSETS";
string dataId;
object hmObj = dom.GetObject(name);
if (hmObj) {
  if (hmObj.IsTypeOf(OT_CHANNEL) || hmObj.IsTypeOf(OT_DEVICE)) {
    string dataIdList = hmObj.EnumMetaData();
    string address = hmObj.Address();
    foreach (dataId, dataIdList.Split(' ')) {
      if (!ignore.Contains(dataId)) {
        string metaVal = hmObj.MetaData(dataId);
        WriteLine(address # '=' # dataId # '=' # metaVal);
      }
    }
    if (hmObj.IsTypeOf(OT_DEVICE)) {
      string chnid;
      foreach (chnid, hmObj.Channels()) {
        object chnObj = dom.GetObject(chnid);
        if (chnObj) {
          string address = chnObj.Address();
          string dataIdList = chnObj.EnumMetaData();
          foreach (dataId, dataIdList.Split(' ')) {
            if (!ignore.Contains(dataId)) {
              string metaVal = chnObj.MetaData(dataId);
              WriteLine(address # '=' # dataId # '=' # metaVal);
            }
          }
        }
      }
    }
  }
  else {
    WriteLine(name # " is no device or channel");
  }
}
else {
	WriteLine("Device or channel " # name # " not found");
}
		)
	},
	"SetMetaData" => {
		description => "Set metadata value in device or channel",
		syntax      => "name key value",
		parameters  => 3,
		code        => qq(
string name = "\$name";
object hmObj = dom.GetObject(name);
if (hmObj) {
  if (hmObj.IsTypeOf(OT_CHANNEL) || hmObj.IsTypeOf(OT_DEVICE)) {
	hmObj.SetMetaData("\$key", "\$value");
  }
  else {
    WriteLine(name # " is no device or channel");
  }
}
else {
	WriteLine("Device or channel " # name # " not found");
}
		)
	},
	"DelMetaData" => {
		description => "Remove metadata from device or channel",
		syntax      => "name key",
		parameters  => 2,
		code        => qq(
string name = "\$name";
object hmObj = dom.GetObject(name);
if (hmObj) {
  if (hmObj.IsTypeOf(OT_CHANNEL) || hmObj.IsTypeOf(OT_DEVICE)) {
	hmObj.RemoveMetaData("\$key");
  }
  else {
    WriteLine(name # " is no device or channel");
  }
}
else {
	WriteLine("Device or channel " # name # " not found");
}
		)
	},
	"GetServiceMessages" => {
		description => "Read list of CCU service messages",
		syntax      => "",
		parameters  => 0,
		code        => qq(
integer c = 0;
object oTmpArray = dom.GetObject(ID_SERVICES);
if(oTmpArray) {
  string sTmp;
  string sdesc;
  string stest;
  foreach(sTmp, oTmpArray.EnumIDs()) {
    object oTmp = dom.GetObject(sTmp);
    if (oTmp) {
      if(oTmp.IsTypeOf(OT_ALARMDP) && (oTmp.AlState() == asOncoming)) {
        object trigDP = dom.GetObject(oTmp.AlTriggerDP());
        object och = dom.GetObject((trigDP.Channel()));
        object odev = dom.GetObject((och.Device()));
        var ival = trigDP.Value();
        time sftime = oTmp.AlOccurrenceTime(); ! erste Meldezeit
        time sltime = oTmp.LastTriggerTime();  ! letzte Meldezeit
        var sdesc = trigDP.HssType();
        var sserial = odev.Address();
        var sname = odev.Name();
        WriteLine(sftime.Format("%d.%m.%y %H:%M") # ";" # sltime.Format("%d.%m.%y %H:%M") # ";" # sserial # ";" # sname # ";" # sdesc);
        c = c+1;
      }
    }
  }
}
Write(c);
		)
	},
	"GetAlarms" => {
		description => "Read list of CCU alarm messages",
		syntax      => "",
		parameters  => 0,
		code        => qq(
integer c = 0;
object oTmpArray = dom.GetObject( ID_SYSTEM_VARIABLES );
if(oTmpArray) {
  string sTmp;
  foreach(sTmp,oTmpArray.EnumIDs()) {
    object oTmp = dom.GetObject(sTmp);
    if(oTmp) {
      if(oTmp.IsTypeOf(OT_ALARMDP) && (oTmp.AlState() == asOncoming)) {
         c = c+1;
		   object oSV = oTmp;
	      Write(oSV.AlOccurrenceTime());
	     	Write(";" # oSV.Timestamp());
	      object oDestDP = dom.GetObject( oSV.AlDestMapDP() );
	      string sDestDPName = "";
	      if(oDestDP) {
	        sDestDPName = oDestDP.Name();
	      }
	      else {
	        sDestDPName = "none";
	      }
	      Write(";" # sDestDPName);
	      
	      string sAlarmName = oSV.Name();
	      if(!sAlarmName.Length()) {
	        sAlarmName = "none";
	      }
	      Write(";" # sAlarmName);
	      
	      string sAlarmDescription = oSV.DPInfo();
	      if(!sAlarmDescription.Length()) {
	        sAlarmDescription = "none";
	      }
	      Write(";" # sAlarmDescription);
	      
	      string sRooms = "";
	      string sLastTriggerName = "";
	      string sLastTriggerMessage = "";
	      string sLastTriggerKey = "";
	      integer iTmpTriggerID = oSV.LastTriggerID();
	      if(iTmpTriggerID == ID_ERROR) {
	        iTmpTriggerID = oSV.AlTriggerDP();
	      }
	
	      string sAlarmMessage = "";
	      string sChannelName = "none";
	      object oLastTrigger = dom.GetObject(iTmpTriggerID);
	      if(oLastTrigger) {           
	        object oLastTriggerChannel = dom.GetObject(oLastTrigger.Channel());
	        if(oLastTriggerChannel) {
	          sChannelName = oLastTriggerChannel.Name();
             string sLastTriggerName = sChannelName;
             string sRID;
             foreach(sRID, oLastTriggerChannel.ChnRoom()) {
               object oRoom = dom.GetObject(sRID);
               if(oRoom) {
                 sRooms = sRooms # "," # oRoom.Name();
               }
             }
	          
	          if(oLastTrigger.IsTypeOf(OT_HSSDP)) {
	            string sLongKey = oLastTriggerChannel.ChnLabel()#"|"#oLastTrigger.HSSID();
	            string sShortKey = oLastTrigger.HSSID();
	            if((oLastTrigger.ValueType() == ivtInteger) && (oLastTrigger.ValueSubType() == istEnum)) {
	              sLongKey = sLongKey#"="#web.webGetValueFromList( oLastTrigger.ValueList(), oSV.Value() );
	              sShortKey = sShortKey#"="#web.webGetValueFromList( oLastTrigger.ValueList(), oSV.Value() );
	            }
	            sAlarmMessage = web.webKeyFromStringTable(sLongKey);
	            if(!sAlarmMessage.Length()) {
	              sAlarmMessage = web.webKeyFromStringTable(sShortKey);
	              if(!sAlarmMessage.Length()) {
	                sAlarmMessage = sShortKey;
	              }
	            }
	          }
	        }
	      }
	      else {
	        if (oSV.IsTypeOf(OT_ALARMDP)) {
	          if ((oSV.Value() == false) || (oSV.Value() == "")) {
	            sAlarmMessage = oSV.ValueName0();
	          }
	          else {
	            sAlarmMessage = oSV.ValueName1();
	          }
	        }
	      }
	      if(sRooms == "") {
	        sRooms = "none";
	      }
	      
	      Write(";" # sAlarmMessage # ";" # sRooms # ";" # sChannelName);
	      WriteLine("");
      }
    }
  }
}
Write(c);
		)
	}
);

1;
