#########################################################################
#
#  HMCCUConf.pm
#
#  $Id$
#
#  Version 3.9.001
#
#  Configuration parameters for Homematic devices.
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
#  Datapoints LOWBAT, LOW_BAT, UNREACH, ERROR*, SABOTAGE and FAULT* must
#  not be specified in ccureadingfilter. They are always stored as readings.
#  Datapoints LOWBAT, LOW_BAT and UNREACH must not be specified in
#  substitute because they are substituted by default.
#  See attributes ccudef-readingname and ccudef-substitute in module HMCCU.
#
#########################################################################

package HMCCUConf;

use strict;
use warnings;

use vars qw(%HMCCU_CHN_DEFAULTS);
use vars qw(%HMCCU_DEV_DEFAULTS);

# 
#
# Default attributes for Homematic devices of type HMCCUCHN
#
%HMCCU_CHN_DEFAULTS = (
	"HM-Sec-SCo|HM-Sec-SC|HM-Sec-SC-2|HMIP-SWDO" => {
	_description     => "Tuer/Fensterkontakt optisch und magnetisch",
	_channels        => "1",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR!7:sabotage;SABOTAGE!1:sabotage",
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
	"HM-LC-Sw1-Pl-2|HMIP-PS" => {
	_description     => "Steckdose",
	_channels        => "1,3",
	ccureadingfilter => "STATE",
	controldatapoint => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
"HM-LC-Dim1L-Pl|HM-LC-Dim1L-Pl-2|HM-LC-Dim1L-CV|HM-LC-Dim2L-CV|HM-LC-Dim2L-SM|HM-LC-Dim1L-Pl-3|HM-LC-Dim1L-CV-2" => {
	_description     => "Funk-Anschnitt-Dimmaktor",
	_channels        => "1",
	ccureadingfilter => "(^LEVEL$|DIRECTION)",
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
	ccureadingfilter => "(^LEVEL$|DIRECTION)",
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
	},	"HM-LC-Dim1T-Pl|HM-LC-Dim1T-CV|HM-LC-Dim1T-FM|HM-LC-Dim1T-CV-2|HM-LC-Dim2T-SM|HM-LC-Dim2T-SM-2|HM-LC-Dim1T-DR|HM-LC-Dim1T-FM-LF|HM-LC-Dim1T-FM-2|HM-LC-Dim1T-Pl-3|HM-LC-Dim1TPBU-FM|HM-LC-Dim1TPBU-FM-2" => {
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
	"HM-PB-2-FM" => {
	_description     => "Funk-Wandtaster 2-fach",
	_channels        => "1,2",
	ccureadingfilter => "PRESS",
	statedatapoint   => "PRESS_SHORT",
	statevals        => "press:true",
	substitute       => "PRESS_SHORT,PRESS_LONG,PRESS_CONT!(1|true):pressed,(0|false):released;PRESS_LONG_RELEASE!(0|false):no,(1|true):yes"
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
	"HM-SCI-3-FM" => {
	_description     => "3 Kanal Schliesserkontakt",
	_channels        => "1,2,3",
	ccureadingfilter => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HM-LC-Sw1-Pl|HM-LC-Sw1-Pl-2|HM-LC-Sw1-SM|HM-LC-Sw1-FM|HM-LC-Sw1-PB-FM" => {
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
	"HM-LC-Bl1PBU-FM|HM-LC-Bl1-FM|HM-LC-Bl1-SM|HM-LC-BlX|HM-LC-Bl1-SM-2|HM-LC-Bl1-FM-2" => {
	_description     => "Jalousienaktor",
	_channels        => "1",
	ccureadingfilter => "(LEVEL|INHIBIT|DIRECTION|WORKING)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "LEVEL",
	eventMap         => "/datapoint STOP true:stop/datapoint LEVEL 0:down/datapoint LEVEL 100:up/",
	statedatapoint   => "LEVEL",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LEVEL!#0-0:closed,#100-100:open;DIRECTION!0:stop,1:up,2:down,3:undefined;WORKING!(0|false):no,(1|true):yes",
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
	"HM-Sec-MD|HM-Sec-MDIR|HM-Sec-MDIR-2|HM-Sec-MDIR-3" => {
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
	statedatapoint   => "MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes"
	},
	"HM-Sen-LI-O" => {
	_description     => "Lichtsensor",
	_channels        => "1",
	ccureadingfilter => "LUX",
	statedatapoint   => "LUX",
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

#
# Default attributes for Homematic devices of type HMCCUDEV
#
%HMCCU_DEV_DEFAULTS = (
   "CCU2" => {
   _description     => "HomeMatic CCU2",
   "ccudef-readingfilter" => '^(LOW_?BAT|UNREACH)$',
   "ccudef-readingformat" => 'datapoint',
   "ccudef-readingname"   => '^(.+\.)?AES_KEY$:sign;^(.+\.)?LOW_?BAT$:battery;^(.+\.)?BATTERY_STATE$:batteryLevel;^(.+\.)?UNREACH$:Activity;^(.+\.)?TEMPERATURE$:+temperature;^(.+\.)?SET_TEMPERATURE$:+desired-temp;^(.+\.)?HUMIDITY$:+humidity;^(.+\.)?LEVEL$:+pct;^(.+\.)?CONTROL_MODE$:+controlMode',
   "ccudef-substitute"    => 'AES_KEY!(0|false):off,(1|true):on;LOWBAT,LOW_BAT!(0|false):ok,(1|true):low;UNREACH!(0|false):alive,(1|true):dead;MOTION!(0|false):noMotion,(1|true):motion;DIRECTION!0:stop,1:up,2:down,3:undefined;WORKING!0:false,1:true;INHIBIT!(0|false):unlocked,(1|true):locked'
   },
	"HM-Sec-SCo|HM-Sec-SC|HM-Sec-SC-2|HMIP-SWDO" => {
	_description     => "Tuer/Fensterkontakt optisch und magnetisch",
	ccureadingfilter => "STATE",
	hmstatevals      => "ERROR!7:sabotage;SABOTAGE!1:sabotage",
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
	"HM-LC-Sw1-Pl-2" => {
	_description     => "Steckdose",
	ccureadingfilter => "STATE",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HMIP-PS" => {
	_description     => "Steckdose IP",
	ccureadingfilter => "STATE",
	controldatapoint => "3.STATE",
	statedatapoint   => "3.STATE",
	statevals        => "on:1,off:0",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
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
	ccureadingfilter => "(STATE|CURRENT|^ENERGY_COUNTER$|POWER)",
	controldatapoint => "3.STATE",
	statedatapoint   => "3.STATE",
	statevals        => "on:true,off:false",
	stripnumber      => 1,
	substitute       => "STATE!(true|1):on,(false|0):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},	"HM-LC-Dim1L-Pl|HM-LC-Dim1L-Pl-2|HM-LC-Dim1L-CV|HM-LC-Dim2L-CV|HM-LC-Dim2L-SM|HM-LC-Dim1L-Pl-3|HM-LC-Dim1L-CV-2" => {
	_description     => "Funk-Anschnitt-Dimmaktor",
	ccureadingfilter => "(^LEVEL$|DIRECTION)",
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
	ccureadingfilter => "(^LEVEL$|DIRECTION)",
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
	},	"HM-LC-Dim1T-Pl|HM-LC-Dim1T-CV|HM-LC-Dim1T-FM|HM-LC-Dim1T-CV-2|HM-LC-Dim2T-SM|HM-LC-Dim2T-SM-2|HM-LC-Dim1T-DR|HM-LC-Dim1T-FM-LF|HM-LC-Dim1T-FM-2|HM-LC-Dim1T-Pl-3|HM-LC-Dim1TPBU-FM|HM-LC-Dim1TPBU-FM-2" => {
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
	"HM-PB-2-FM" => {
	_description     => "Funk-Wandtaster 2-fach",
	ccureadingfilter => "PRESS",
	substitute       => "PRESS_SHORT,PRESS_LONG,PRESS_CONT!(1|true):pressed,(0|false):released;PRESS_LONG_RELEASE!(0|false):no,(1|true):yes"
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
	"HM-LC-SW4-BA-PCB|HM-SCI-3-FM" => {
	_description     => "4 Kanal Funk Schaltaktor für Batteriebetrieb, 3 Kanal Schließerkontakt",
	ccureadingfilter => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HM-LC-Bl1PBU-FM|HM-LC-Bl1-FM|HM-LC-Bl1-SM|HM-LC-BlX|HM-LC-Bl1-SM-2|HM-LC-Bl1-FM-2" => {
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
	"HM-TC-IT-WM-W-EU" => {
	_description     => "Wandthermostat",
	ccureadingfilter => "(^HUMIDITY|^TEMPERATURE|^SET_TEMPERATURE|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "2.SET_TEMPERATURE",
	eventMap         => "/datapoint 2.MANU_MODE 20.0:Manu/datapoint 2.AUTO_MODE 1:Auto/datapoint 2.BOOST_MODE 1:Boost/datapoint 2.MANU_MODE 4.5:off/datapoint 2.MANU_MODE 30.5:on/",
	statedatapoint   => "2.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed;SET_TEMPERATURE!#0-3.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HM-CC-RT-DN" => {
	_description     => "Heizkoerperthermostat",
	ccureadingfilter => "(TEMPERATURE|VALVE_STATE|CONTROL)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "4.SET_TEMPERATURE",
	eventMap         => "/datapoint 4.MANU_MODE 20.0:Manu/datapoint 4.AUTO_MODE 1:Auto/datapoint 4.BOOST_MODE 1:Boost/datapoint 4.MANU_MODE 4.5:off/datapoint 4.MANU_MODE 30.5:on/",
	hmstatevals      => "FAULT_REPORTING!1:valve_tight,2:range_too_large,3:range_too_small,4:communication_error,5:other_error,6:battery_low,7:valve_error_pos",
	statedatapoint   => "4.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;SET_TEMPERATURE!#0-4.5:off,#30.5-40:on;FAULT_REPORTING!0:no,1:valve_tight,2:range_too_large,3:range_too_small,4:communication_error,5:other_error,6:battery_low,7:valve:error_pos",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HMIP-eTRV" => {
	_description     => "Heizkoerperthermostat HM-IP",
	ccureadingname   => "1.LEVEL:valve_position",
	ccuscaleval      => "LEVEL:0:1:0:100",
	controldatapoint => "1.SET_POINT_TEMPERATURE",
	eventMap         => "/datapoint 1.BOOST_MODE true:Boost/datapoint 1.CONTROL_MODE 0:Auto/datapoint 1.CONTROL_MODE 1:Manual/datapoint 1.CONTROL_MODE 2:Holiday/datapoint 1.SET_POINT_TEMPERATURE 4.5:off/datapoint 1.SET_POINT_TEMPERATURE 30.5:on/",
	statedatapoint   => "1.SET_POINT_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "SET_POINT_TEMPERATURE!#0-4.5:off,#30.5-40:on;WINDOW_STATE!(0|false):closed,(1|true):open",
	webCmd           => "control:Boost:Auto:Manual:Holiday:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HmIP-WTH|HmIP-WTH-2" => {
	_description     => "Wandthermostat HM-IP",
	controldatapoint => "1.SET_POINT_TEMPERATURE",
	eventMap         => "/datapoint 1.BOOST_MODE true:Boost/datapoint 1.CONTROL_MODE 0:Auto/datapoint 1.CONTROL_MODE 1:Manual/datapoint 1.CONTROL_MODE 2:Holiday/datapoint 1.SET_POINT_TEMPERATURE 4.5:off/datapoint 1.SET_POINT_TEMPERATURE 30.5:on/",
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
	"HM-ES-TX-WM" => {
	_description     => "Energiezaehler Sensor",
	ccureadingfilter => "(ENERGY_COUNTER|POWER)"
	},
	"HM-CC-VG-1" => {
	_description     => "Heizungsgruppe",
	ccureadingfilter => "(^SET_TEMPERATURE|^TEMPERATURE|^HUMIDITY|^VALVE|^CONTROL|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "1.SET_TEMPERATURE",
	eventMap         => "/datapoint 1.MANU_MODE 20.0:Manu/datapoint 1.AUTO_MODE 1:Auto/datapoint 1.BOOST_MODE 1:Boost/datapoint 1.MANU_MODE 4.5:off/datapoint 1.MANU_MODE 30.5:on/",
	statedatapoint   => "1.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed;SET_TEMPERATURE!#0-4.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,3.5,0.5,30.5,1"
	},
	"HM-Sec-MD|HM-Sec-MDIR|HM-Sec-MDIR-2|HM-Sec-MDIR-3" => {
	_description     => "Bewegungsmelder",
	ccureadingfilter => "(BRIGHTNESS|MOTION)",
	hmstatevals      => "ERROR!1:sabotage",
	statedatapoint   => "1.MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes;ERROR!0:no,1:sabotage"
	},
	"HmIP-SMI" => {
	_description     => "Bewegungsmelder",
	ccureadingfilter => "(ILLUMINATION|MOTION)",
	statedatapoint   => "1.MOTION",
	substitute       => "MOTION!(0|false):no,(1|true):yes"
	},
	"HM-Sen-LI-O" => {
	_description     => "Lichtsensor",
	ccureadingfilter => "LUX",
	statedatapoint   => "1.LUX",
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
	substitute       => "STATE!(0|false):ledOff,(1|true):ledOn;2.STATE!(0|false):soundOff,(1|true):soundOn"
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

	}
);

1;
