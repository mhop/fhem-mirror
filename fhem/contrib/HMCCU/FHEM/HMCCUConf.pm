#########################################################################
#
#  HMCCUConf.pm
#
#  $Id:$
#
#  Version 3.2
#
#  Configuration parameters for Homematic devices.
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
#########################################################################

package HMCCUConf;

use strict;
use warnings;

use vars qw(%HMCCU_DEV_DEFAULTS);

# Default attributes for Homematic devices of type HMCCUDEV
%HMCCU_DEV_DEFAULTS = (
	"HM-Sec-SCo" => {			# Tuer/Fensterkontakt optisch
	ccureadingfilter => "(ERROR|UNREACH|LOWBAT|STATE)",
	statechannel     => 1,
	substitute       => "STATE!(0|false):closed,(1|true):open;LOWBAT!(0|false):no,(1|true):yes"
	},
	"HM-Sec-SC" => {			# Tuer/Fensterkontakt magnetisch
	ccureadingfilter => "(ERROR|UNREACH|LOWBAT|STATE)",
	statechannel     => 1,
	substitute       => "STATE!(0|false):closed,(1|true):open;LOWBAT!(0|false):no,(1|true):yes"
	},
	"HM-LC-Sw1-Pl-2" => {	# Steckdose	
	ccureadingfilter => "(STATE|UNREACH)",
	controldatapoint => "1.STATE",
	statechannel     => 1,
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HMIP-PS" => {				# Steckdose (IP)
	ccureadingfilter => "(STATE|UNREACH)",
	statechannel     => 3,
	statevals        => "on:1,off:0",
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HM-ES-PMSw1-Pl" => {	# Steckdose mit Energiemessung
	ccureadingfilter => "(STATE|UNREACH|CURRENT|ENERGY_COUNTER|POWER)",
	statechannel     => 1,
	statevals        => "on:1,off:0",
	stripnumber      => 1,
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HMIP-PSM" => {			# Steckdose mit Energiemessung (IP)
	ccureadingfilter => "(STATE|UNREACH|CURRENT|ENERGY_COUNTER|POWER)",
	statechannel     => 3,
	statevals        => "on:true,off:false",
	stripnumber      => 1,
	substitute       => "STATE!(1|true):on,(0|false):off"
	},
	"HM-LC-Bl1PBU-FM" => {	# Rolladenaktor
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "1.LEVEL",
	eventMap         => "/datapoint 1.STOP 1:stop/datapoint 1.LEVEL 1:down/datapoint 1.LEVEL 0:up/",
	statechannel     => 1,
	statevals        => "up:0.0,down:1.0",
	stripnumber      => 1,
	webCmd           => "control:up:stop:down",
	widgetOverride   => "control:slider,0,0.05,1,1"  
	},
	"HM-TC-IT-WM-W-EU" => {	# Wandthermostat
	ccureadingfilter => "(UNREACH|^HUMIDITY|^TEMPERATURE|^SET_TEMPERATURE|^LOWBAT$|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "2.SET_TEMPERATURE",
	eventMap         => "/datapoint 2.MANU_MODE 20.0:Manu/datapoint 2.AUTO_MODE 1:Auto/datapoint 2.BOOST_MODE 1:Boost/datapoint 2.MANU_MODE 4.5:off/datapoint 2.MANU_MODE 30.5:on/",
	statechannel     => 2,
	statedatapoint   => "SET_TEMPERATURE",
	stripnumber      => 1,
	substitute       => "LOWBAT!(0|false):no,(1|true):yes;CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,10,1,25"
	},
	"HM-CC-RT-DN" => {		# Heizkörperthermostat
	ccureadingfilter => "(UNREACH|LOWBAT|TEMPERATURE|VALVE_STATE|CONTROL)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "4.SET_TEMPERATURE",
	eventMap         => "/datapoint 4.MANU_MODE 20.0:Manu/datapoint 4.AUTO_MODE 1:Auto/datapoint 4.BOOST_MODE 1:Boost/datapoint 4.MANU_MODE 4.5:off/datapoint 4.MANU_MODE 30.5:on/",
	statechannel     => 4,
	statedatapoint   => "SET_TEMPERATURE",
	stripnumber      => 1,
	substitute       => "LOWBAT!(0|false):no,(1|true):yes;CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,10,1,25"
	},
	"HM-WDS40-TH-I" => {		# Temperatur/Luftfeuchte Sensor
	ccureadingfilter => "(UNREACH|^HUMIDITY|^TEMPERATURE|^LOWBAT$)",
	statechannel     => 1,
	statedatapoint   => "TEMPERATURE",
	stripnumber      => 1,
	substitute       => "LOWBAT!(0|false):no,(1|true):yes"
	},
	"HM-ES-TX-WM" => {		# Stromzähler Sensor
	ccureadingfilter => "(UNREACH|LOWBAT|^ENERGY_COUNTER|^POWER)",
	substitute       => "LOWBAT!(true|1):yes,(false|0):no"
	},
	"HM-CC-VG-1" => {			# Heizungsgruppe
	ccureadingfilter => "(^SET_TEMPERATURE|^TEMPERATURE|^HUMIDITY|LOWBAT$|^VALVE|^CONTROL|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "1.SET_TEMPERATURE",
	eventMap         => "/datapoint 1.MANU_MODE 20.0:Manu/datapoint 1.AUTO_MODE 1:Auto/datapoint 1.BOOST_MODE 1:Boost/datapoint 1.MANU_MODE 4.5:off/datapoint 1.MANU_MODE 30.5:on/",
	statechannel     => 1,
	statedatapoint   => "SET_TEMPERATURE",
	stripnumber      => 1,
	substitute       => "LOWBAT!(0|false):no,(1|true):yes;CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,10,1,25"
	}
);

1;
