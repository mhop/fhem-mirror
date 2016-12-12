#########################################################################
#
#  HMCCUConf.pm
#
#  $Id$
#
#  Version 3.6
#
#  Configuration parameters for Homematic devices.
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
#########################################################################

package HMCCUConf;

use strict;
use warnings;

use vars qw(%HMCCU_CHN_DEFAULTS);
use vars qw(%HMCCU_DEV_DEFAULTS);

#
# Default attributes for Homematic devices of type HMCCUCHN
#
%HMCCU_CHN_DEFAULTS = (
	"HM-Sec-SCo|HM-Sec-SC|HMIP-SWDO" => {
	_description     => "Tuer/Fensterkontakt optisch und magnetisch",
	_channels        => "1",
	ccureadingfilter => "(^UNREACH|LOWBAT|LOW_BAT|STATE)",
	statedatapoint   => "STATE",
	substitute       => "STATE!(0|false):closed,(1|true):open;UNREACH,LOWBAT,LOW_BAT!(0|false):no,(1|true):yes"
	},
	"HM-LC-Sw1-Pl-2|HMIP-PS" => {
	_description     => "Steckdose",
	_channels        => "1,3",
	ccureadingfilter => "(STATE|^UNREACH)",
	controldatapoint => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-LC-Dim1T-Pl-3" => {
	_description     => "Steckdose mit Dimmer",
	_channels        => "1",
	ccureadingfilter => "(^LEVEL\$|ERROR|^UNREACH)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "LEVEL",
	statedatapoint   => "LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR_OVERHEAT,ERROR_OVERLOAD,ERROR_REDUCED,UNREACH!(0|false):no,(1|true):yes;LEVEL!#0-0:off,#1-100:on",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"
	},
	"HM-LC-Sw1PBU-FM" => {
	_description     => "Unterputz Schaltaktor für Markenschalter",
	_channels        => "1",
	ccureadingfilter => "(STATE|^UNREACH)",
	controldatapoint => "STATE",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-SCI-3-FM" => {
	_description     => "3 Kanal Schliesserkontakt",
	_channels        => "1,2,3",
	ccureadingfilter => "(STATE|LOWBAT|^UNREACH)",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;LOWBAT,UNREACH!(1|true):yes,(0|false):no"
	},
	"HM-LC-Sw1-Pl|HM-LC-Sw1-Pl-2|HM-LC-Sw1-SM|HM-LC-Sw1-FM|HM-LC-Sw1-PB-FM" => {
	_description     => "1 Kanal Funk-Schaltaktor",
	_channels        => "1",
	ccureadingfilter => "(STATE|LOWBAT|^UNREACH)",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;LOWBAT,UNREACH!(1|true):yes,(0|false):no"	
	},
	"HM-LC-Sw2-SM|HM-LC-Sw2-FM|HM-LC-Sw2-PB-FM|HM-LC-Sw2-DR" => {
	_description     => "2 Kanal Funk-Schaltaktor",
	_channels        => "1,2",
	ccureadingfilter => "(STATE|LOWBAT|^UNREACH)",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;LOWBAT,UNREACH!(1|true):yes,(0|false):no"	
	},
	"HM-LC-Sw4-DR|HM-LC-Sw4-WM|HM-LC-Sw4-PCB|HM-LC-Sw4-SM" => {
	_description     => "4 Kanal Funk-Schaltaktor",
	_channels        => "1,2,3,4",
	ccureadingfilter => "(STATE|LOWBAT|^UNREACH)",
	statedatapoint   => "STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;LOWBAT,UNREACH!(1|true):yes,(0|false):no"	
	},
	"HM-Sen-LI-O" => {
	_description     => "Lichtsensor",
	_channels        => "1",
	ccureadingfilter => "(LUX|LOWBAT|UNREACH)",
	statedatapoint   => "LUX",
	stripnumber      => 1,
	substitute       => "LOWBAT,UNREACH!(0|false):no,(1|true):yes"
	}
);

#
# Default attributes for Homematic devices of type HMCCUDEV
#
%HMCCU_DEV_DEFAULTS = (
	"HM-Sec-SCo|HM-Sec-SC" => {
	_description     => "Tuer/Fensterkontakt optisch und magnetisch",
	ccureadingfilter => "(^UNREACH|LOWBAT|LOW_BAT|STATE)",
	statedatapoint   => "1.STATE",
	substitute       => "STATE!(0|false):closed,(1|true):open;UNREACH,LOWBAT,LOW_BAT!(0|false):no,(1|true):yes"
	},
	"HM-LC-Sw1-Pl-2" => {
	_description     => "Steckdose",
	ccureadingfilter => "(STATE|^UNREACH)",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HMIP-PS" => {
	_description     => "Steckdose IP",
	ccureadingfilter => "(STATE|^UNREACH)",
	controldatapoint => "3.STATE",
	statedatapoint   => "3.STATE",
	statevals        => "on:1,off:0",
	substitute       => "STATE!(1|true):on,(0|false):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-ES-PMSw1-Pl" => {
	_description     => "Steckdose mit Energiemessung",
	ccureadingfilter => "(STATE|^UNREACH|CURRENT|ENERGY_COUNTER|POWER)",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:1,off:0",
	stripnumber      => 1,
	substitute       => "STATE!(1|true):on,(0|false):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HMIP-PSM" => {
	_description     => "Steckdose mit Energiemessung IP",
	ccureadingfilter => "(STATE|^UNREACH|CURRENT|ENERGY_COUNTER|POWER)",
	controldatapoint => "3.STATE",
	statedatapoin    => "3.STATE",
	statevals        => "on:true,off:false",
	stripnumber      => 1,
	substitute       => "STATE!(true|1):on,(false|0):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-LC-Dim1T-Pl-3" => {
	_description     => "Steckdose mit Dimmer",
	ccureadingfilter => "(^LEVEL\$|ERROR|^UNREACH)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "on:general_an off:general_aus",
	controldatapoint => "1.LEVEL",
	statedatapoint   => "1.LEVEL",
	statevals        => "on:100,off:0",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "ERROR_OVERHEAT,ERROR_OVERLOAD,ERROR_REDUCED,UNREACH!(0|false):no,(1|true):yes;LEVEL!#0-0:off,#1-100:on",
	webCmd           => "control:on:off",
	widgetOverride   => "control:slider,0,10,100"	
	},
	"HM-LC-Sw1PBU-FM" => {
	_description     => "Unterputz Schaltaktor für Markenschalter",
	ccureadingfilter => "(STATE|^UNREACH)",
	controldatapoint => "1.STATE",
	statedatapoint   => "1.STATE",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(true|1):on,(false|0):off;UNREACH!(true|1):yes,(false|0):no",
	webCmd           => "control",
	widgetOverride   => "control:uzsuToggle,off,on"
	},
	"HM-LC-SW4-BA-PCB|HM-SCI-3-FM" => {
	_description     => "4 Kanal Funk Schaltaktor für Batteriebetrieb, 3 Kanal Schließerkontakt",
	ccureadingfilter => "(STATE|LOWBAT|^UNREACH)",
	statevals        => "on:true,off:false",
	substitute       => "STATE!(1|true):on,(0|false):off;LOWBAT,UNREACH!(1|true):yes,(0|false):no"
	},
	"HM-LC-Bl1PBU-FM|HM-LC-Bl1-FM" => {
	_description     => "Rolladenaktor Markenschalter, Rolladenaktor unterputz",
	ccureadingfilter => "(LEVEL|^UNREACH)",
	ccuscaleval      => "LEVEL:0:1:0:100",
	cmdIcon          => "up:fts_shutter_up stop:fts_shutter_manual down:fts_shutter_down",
	controldatapoint => "1.LEVEL",
	eventMap         => "/datapoint 1.STOP 1:stop/datapoint 1.LEVEL 0:down/datapoint 1.LEVEL 100:up/",
	statedatapoint   => "1.LEVEL",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "UNREACH!(false|0):no,(true|1):yes;LEVEL!#0-0:closed,#100-100:open",
	webCmd           => "control:up:stop:down",
	widgetOverride   => "control:slider,0,10,100"  
	},
	"HM-TC-IT-WM-W-EU" => {
	_description     => "Wandthermostat",
	ccureadingfilter => "(^UNREACH|^HUMIDITY|^TEMPERATURE|^SET_TEMPERATURE|^LOWBAT\$|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "2.SET_TEMPERATURE",
	eventMap         => "/datapoint 2.MANU_MODE 20.0:Manu/datapoint 2.AUTO_MODE 1:Auto/datapoint 2.BOOST_MODE 1:Boost/datapoint 2.MANU_MODE 4.5:off/datapoint 2.MANU_MODE 30.5:on/",
	statedatapoint   => "2.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LOWBAT,UNREACH!(0|false):no,(1|true):yes;CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed;SET_TEMPERATURE!#0-3.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,4.5,0.5,30.5,1"
	},
	"HM-CC-RT-DN" => {
	_description     => "Heizkoerperthermostat",
	ccureadingfilter => "(^UNREACH|LOWBAT|TEMPERATURE|VALVE_STATE|CONTROL)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "4.SET_TEMPERATURE",
	eventMap         => "/datapoint 4.MANU_MODE 20.0:Manu/datapoint 4.AUTO_MODE 1:Auto/datapoint 4.BOOST_MODE 1:Boost/datapoint 4.MANU_MODE 4.5:off/datapoint 4.MANU_MODE 30.5:on/",
	statedatapoint   => "4.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "UNREACH,LOWBAT!(0|false):no,(1|true):yes;CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;SET_TEMPERATURE!#0-3.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,3.5,0.5,30.5,1"
	},
	"HM-WDS40-TH-I" => {
	_description     => "Temperatur/Luftfeuchte Sensor",
	ccureadingfilter => "(^UNREACH|^HUMIDITY|^TEMPERATURE|^LOWBAT\$)",
	statedatapoint   => "1.TEMPERATURE",
	stripnumber      => 1,
	substitute       => "UNREACH,LOWBAT!(0|false):no,(1|true):yes"
	},
	"HM-ES-TX-WM" => {
	_description     => "Stromzaehler Sensor",
	ccureadingfilter => "(^UNREACH|LOWBAT|^ENERGY_COUNTER|^POWER)",
	substitute       => "UNREACH,LOWBAT!(true|1):yes,(false|0):no"
	},
	"HM-CC-VG-1" => {
	_description     => "Heizungsgruppe",
	ccureadingfilter => "(^SET_TEMPERATURE|^TEMPERATURE|^HUMIDITY|LOWBAT\$|^VALVE|^CONTROL|^WINDOW_OPEN)",
	cmdIcon          => "Auto:sani_heating_automatic Manu:sani_heating_manual Boost:sani_heating_boost on:general_an off:general_aus",
	controldatapoint => "1.SET_TEMPERATURE",
	eventMap         => "/datapoint 1.MANU_MODE 20.0:Manu/datapoint 1.AUTO_MODE 1:Auto/datapoint 1.BOOST_MODE 1:Boost/datapoint 1.MANU_MODE 4.5:off/datapoint 1.MANU_MODE 30.5:on/",
	statedatapoint   => "1.SET_TEMPERATURE",
	stripnumber      => 1,
	substexcl        => "control",
	substitute       => "LOWBAT!(0|false):no,(1|true):yes;CONTROL_MODE!0:AUTO,1:MANU,2:PARTY,3:BOOST;WINDOW_OPEN_REPORTING!(true|1):open,(false|0):closed;SET_TEMPERATURE!#0-4.5:off,#30.5-40:on",
	webCmd           => "control:Auto:Manu:Boost:on:off",
	widgetOverride   => "control:slider,3.5,0.5,30.5,1"
	},
	"HM-Sec-MD|HM-Sec-MDIR|HM-Sec-MDIR-2|HM-Sec-MDIR-3" => {
	_description     => "Bewegungsmelder",
	ccureadingfilter => "(^UNREACH|LOWBAT|BRIGHTNESS|MOTION)",
	statedatapoint   => "1.MOTION",
	substitute       => "LOWBAT,UNREACH,MOTION!(0|false):no,(1|true):yes"
	},
	"HM-Sen-LI-O" => {
	_description     => "Lichtsensor",
	ccureadingfilter => "(^UNREACH|LUX|LOWBAT)",
	statedatapoint   => "1.LUX",
	stripnumber      => 1,
	substitute       => "LOWBAT,UNREACH!(0|false):no,(1|true):yes"
	},
	"HM-PB-4Dis-WM" => {
	_description     => "Funk-Display Wandtaster",
	ccureadingfilter => "(^UNREACH|LOWBAT|PRESS_SHORT|PRESS_LONG)",
	substitute       => "PRESS_SHORT,PRESS_LONG!(1|true):pressed;UNREACH,LOWBAT!(1|true):yes,(0|false):no"
	},
	"HM-Dis-EP-WM55" => {
	_description     => "E-Paper Display",
	ccureadingfilter => "(^UNREACH|LOWBAT|PRESS_SHORT|PRESS_LONG)",
	substitute       => "PRESS_LONG,PRESS_SHORT!(1|true):pressed;UNREACH,LOWBAT!(1|true):yes,(0|false):no"
	}
);

1;
