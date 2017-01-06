##############################################
# $Id$
#
# 21_VBUSDEV.pm
#
# (c) 2014 Arno Willig <akw@bytefeed.de>
# (c) 2015 Frank Wurdinger <frank@wurdinger.de>
# (c) 2015 Adrian Freihofer <adrian.freihofer gmail com>
# (c) 2016 Tobias Faust <tobias.faust gmx net>
# (c) 2016 Jörg (pejonp)
##############################################  

package main;

use strict;
use warnings;
use POSIX;
use SetExtensions;
use Data::Dumper;

my %VBUS_devices = (
	"0050" => {"name" => "DL_2", "cmd" => "0100", "fields" => [
			{ "offset" => 0,"name" => "Resistor_Sensor_01", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 2,"name" => "Resistor_Sensor_11", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 4,"name" => "Resistor_Sensor_02", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 6,"name" => "Resistor_Sensor_22", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 8,"name" => "Resistor_Sensor_03", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 10,"name" => "Resistor_Sensor_33", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 12,"name" => "Current_Sensor_01", "bitSize" => 15, "factor" => 0.1, "unit" => "mA" },
			{ "offset" => 14, "name" => "Current_Sensor_11", "bitSize" => 15, "factor" => 0.1, "unit" => "mA" },
			{ "offset" => 28,"name" => "Temperatur_01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 30,"name" => "Temperatur_02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 32,"name" => "Temperatur_03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 34,"name" => "Temperatur_04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			]},
	"0053" => {"name" => "DL_3", "cmd" => "0100", "fields" => [
			{ "offset" => 0,"name" => "Resistor_Sensor_01", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 2,"name" => "Resistor_Sensor_11", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 4,"name" => "Resistor_Sensor_02", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 6,"name" => "Resistor_Sensor_22", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 8,"name" => "Resistor_Sensor_03", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 10,"name" => "Resistor_Sensor_33", "bitSize" => 15, "factor" => 0.1, "unit" => "Ohm" },
			{ "offset" => 12,"name" => "Current_Sensor_01", "bitSize" => 15, "factor" => 0.1, "unit" => "mA" },
			{ "offset" => 14,"name" => "Current_Sensor_11", "bitSize" => 15, "factor" => 0.1, "unit" => "mA" },
			{ "offset" => 28,"name" => "Temperatur_01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 30,"name" => "Temperatur_02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 32,"name" => "Temperatur_03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 34,"name" => "Temperatur_04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			]},
	"1059" => {"name" => "DeltaThermHC_mini_Regler", "cmd" => "0100", "fields" => [
      { "offset" => 0, "name" => "Temperatur_Sensor_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "Temperatur_Sensor_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },	
      { "offset" => 10, "name" => "Drehzahl_Relais_1", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 11, "name" => "Drehzahl_Relais_2", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 12, "name" => "Drehzahl_Relais_3", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 13, "name" => "Drehzahl_Relais_4", "bitSize" => 7, "factor" => 1, "unit" => "%" },
     	{ "offset" => 14, "name" => "Regler_Ausgang_1", "bitSize" => 7, "factor" => 1, "unit" => "%" },
    	{ "offset" => 15, "name" => "Regler_Ausgang_2", "bitSize" => 7, "factor" => 1, "unit" => "%" },
    	{ "offset" => 16,"name" => "Systemdatum","bitSize" => 31 },
  		{ "offset" => 20, "name" => "Fehlermaske", "bitSize" => 31, "factor" => 1 },
  		{ "offset" => 24, "name" => "Warnungsmaske", "bitSize" => 31, "factor" => 1 },
 			]},
  	"1060" => {"name" => "Vitosolic200_SD4", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "temperature_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "temperature_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "temperature_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "temperature_T05","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => "temperature_T06","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => "temperature_T07","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => "temperature_T08","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => "temperature_T09","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => "temperature_T10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 20,"name" => "temperature_T11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 22,"name" => "temperature_T12","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 24,"name" => "insolation", "bitSize" => 15,"unit" => "W/qm" },
			{ "offset" => 28,"name" => "impulse_I01","bitSize" => 31 },
			{ "offset" => 32,"name" => "impulse_I02","bitSize" => 31 },
			{ "offset" => 36,"name" => "sensorbrokemask","bitSize" => 16 },
			{ "offset" => 38,"name" => "sensorshortmask","bitSize" => 16 },
			{ "offset" => 40,"name" => "sensorusagemask","bitSize" => 16 },
			{ "offset" => 44,"name" => "speed_R01","bitSize" => 8, "unit" => "%" },
			{ "offset" => 45,"name" => "speed_R02","bitSize" => 8, "unit" => "%" },
			{ "offset" => 46,"name" => "speed_R03","bitSize" => 8, "unit" => "%" },
			{ "offset" => 47,"name" => "speed_R04","bitSize" => 8, "unit" => "%" },
			{ "offset" => 48,"name" => "speed_R05","bitSize" => 8, "unit" => "%" },
			{ "offset" => 49,"name" => "speed_R06","bitSize" => 8, "unit" => "%" },
			{ "offset" => 50,"name" => "speed_R07","bitSize" => 8, "unit" => "%" },
			{ "offset" => 51,"name" => "speed_R08","bitSize" => 8, "unit" => "%" },
			{ "offset" => 52,"name" => "speed_R09","bitSize" => 8, "unit" => "%" },
			{ "offset" => 58,"name" => "relaisusagemask","bitSize" => 16 },
			{ "offset" => 60,"name" => "errormask","bitSize" => 16 },
			{ "offset" => 62,"name" => "warningmask","bitSize" => 16 },
			{ "offset" => 64,"name" => "SW-Version","bitSize" => 8,"factor" => 0.1 },
 			{ "offset" => 65,"name" => "Minorversion","bitSize" => 8,"factor" => 1 },
			{ "offset" => 66,"name" => "systemtime","bitSize" => 16 },
 			]},
  	"1065" => {"name" => "Vitosolic200_WMZ1", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "WMZ1_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "WMZ1_Ruecklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "WMZ1_volumeflow","bitSize" => 15,"unit" => "l/h" },
			{ "offset" =>  6,"name" => "WMZ1_heatquantity1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  8,"name" => "WMZ1_heatquantity2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" =>  10,"name" => "WMZ1_heatquantity3","bitSize" => 16,"unit" => "MWh" },
 			]},
  	"1066" => {"name" => "Vitosolic200_WMZ2", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "WMZ1_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "WMZ1_Ruecklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "WMZ1_volumeflow","bitSize" => 15,"unit" => "l/h" },
			{ "offset" =>  6,"name" => "WMZ1_heatquantity1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  8,"name" => "WMZ1_heatquantity2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" =>  10,"name" => "WMZ1_heatquantity3","bitSize" => 16,"unit" => "MWh" },
 			]},
   	"1140" => {"name" => "DeltaThermHC_mini_HK", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "HK_VorlaufSoll","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "HK_Betriebsstatus","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  4,"name" => "HK_Betriebsart","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  6,"name" => "HK_Brennerstarts1","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  8,"name" => "HK_Brennerstarts2","bitSize" => 8,"factor" => 1 },
     	{ "offset" =>  10,"name" => "HK_Brennerstarts3","bitSize" => 8,"factor" => 1 },
	   	]},
   	"2211" => {"name" => "DeltaSol_CS_Plus", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "Temperatur_Sensor1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "Temperatur_Sensor2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "Temperatur_Sensor3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "Temperatur_Sensor4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "Drehzahl_Relais1","bitSize" => 8, "unit" => "%" },
			{ "offset" => 10,"name" => "Betriebsstunden_Relais1","bitSize" => 16, "unit" => "h" },
			{ "offset" => 12,"name" => "Drehzahl_Relais2","bitSize" => 8,"unit" => "%"  },
      { "offset" => 14,"name" => "Betriebsstunden_Relais2","bitSize" => 16, "unit" => "h" },
      { "offset" => 16,"name" => "UnitType","bitSize" => 8 },
      { "offset" => 16,"name" => "System","bitSize" => 16 },
			{ "offset" => 28,"name" => "Waermemenge1","bitSize" => 8,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 29,"name" => "Waermemenge2","bitSize" => 8,"factor" => 100,"unit" => "Wh" },
      { "offset" => 30,"name" => "Waermemenge3","bitSize" => 8,"factor" => 10000,"unit" => "Wh" },
			{ "offset" => 31,"name" => "Waermemenge4","bitSize" => 8,"factor" => 10000000,"unit" => "Wh" },
  		]},
  	"2251" => {"name" => "DeltaSol_SL", "cmd" => "0100", "fields" => [
#			{ "offset" => 0, "name" => "Systemzeit", "bitSize" => 31, "timeRef" => 1 },
			{ "offset" => 4, "name" => "Kollektortemperatur", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Kesseltemperatur", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 10, "name" => "Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 12, "name" => "Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 14, "name" => "Temperatur_VFS/RPS", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 20, "name" => "Volumenstrom_V40", "bitSize" => 31, "factor" => 1, "unit" => "1/h" },
#			{ "offset" => 24, "name" => "Volumenstrom_VFS", "bitSize" => 31, "factor" => 1, "unit" => "1/h" },
#			{ "offset" => 28, "name" => "Volumenstrom_Flowrotor", "bitSize" => 31, "factor" => 1, "unit" => "1/h" },
#			{ "offset" => 32, "name" => "Druck_RPS", "bitSize" => 15, "factor" => 0.01, "unit" => "bar" },
			{ "offset" => 34, "name" => "Drehzahl_Relais_1", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 35, "name" => "Drehzahl_Relais_2", "bitSize" => 7, "factor" => 1, "unit" => "%" },
#			{ "offset" => 36, "name" => "Drehzahl_Relais_3", "bitSize" => 7, "factor" => 1, "unit" => "%" },
#			{ "offset" => 37, "name" => "Drehzahl_Relais_4", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 38, "name" => "PWM_A", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 39, "name" => "PWM_B", "bitSize" => 7, "factor" => 1, "unit" => "%" },
#			{ "offset" => 40, "name" => "Wärmemenge", "bitSize" => 31, "factor" => 1, "unit" => "Wh" },
			{ "offset" => 44, "name" => "SW-Version", "bitSize" => 7, "factor" => 0.01 },
			{ "offset" => 48, "name" => "Betriebsstunden_Relais_1", "bitSize" => 31, "factor" => 1, "unit" => "h" },
			{ "offset" => 52, "name" => "Betriebsstunden_Relais_2", "bitSize" => 31, "factor" => 1, "unit" => "h" },
#			{ "offset" => 56, "name" => "Betriebsstunden_Relais_3", "bitSize" => 31, "factor" => 1, "unit" => "h" },
#			{ "offset" => 60, "name" => "Betriebsstunden_Relais_4", "bitSize" => 31, "factor" => 1, "unit" => "h" },
			{ "offset" => 64, "name" => "Urlaubsfunktion", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 65, "name" => "Blockierschutz_1", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 66, "name" => "Blockierschutz_2", "bitSize" => 7, "factor" => 1, "unit" => "%" },
#			{ "offset" => 67, "name" => "Blockierschutz_3", "bitSize" => 7, "factor" => 1, "unit" => "%" },
			{ "offset" => 68, "name" => "Initialisieren", "bitSize" => 31, "factor" => 1 },
			{ "offset" => 72, "name" => "Füllung", "bitSize" => 31, "factor" => 1 },
			{ "offset" => 76, "name" => "Stabilisieren", "bitSize" => 31, "factor" => 1 },
			{ "offset" => 80, "name" => "Pumpenverzögerung", "bitSize" => 7, "factor" => 1 },
			{ "offset" => 81, "name" => "Überwärmeabfuhr", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 82, "name" => "Nachlauf", "bitSize" => 7, "factor" => 1 },
			{ "offset" => 83, "name" => "Thermische_Desinfektion", "bitSize" => 7, "factor" => 1 },
			{ "offset" => 84, "name" => "Speicherkühlung", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 85, "name" => "Systemkühlung", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 86, "name" => "Spreizung", "bitSize" => 7, "factor" => 1 },
			{ "offset" => 87, "name" => "Frostschutz", "bitSize" => 7, "factor" => 1 },
			{ "offset" => 88, "name" => "Kollektorkühlung", "bitSize" => 1, "factor" => 1 },
#			{ "offset" => 89, "name" => "Einheit_Temperatur", "bitSize" => 1, "factor" => 1 },
#			{ "offset" => 90, "name" => "Einheit_Durchfluss", "bitSize" => 1, "factor" => 1 },
#			{ "offset" => 91, "name" => "Einheit_Druck", "bitSize" => 1, "factor" => 1 },
#			{ "offset" => 93, "name" => "Einheit_Energie", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 94, "name" => "Speichermaximaltemperatur", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 95, "name" => "Neustarts", "bitSize" => 1, "factor" => 1 },
			{ "offset" => 96, "name" => "Fehlermaske", "bitSize" => 31, "factor" => 1 },
	  		]},
    "2271" => {"name" => "DeltaSol_SLL", "cmd" => "0100", "fields" => [
	      { "offset" => 0, "name" => "Systemzeit", "bitSize" => 31, "timeRef" => 1 },
	      { "offset" => 4, "name" => "Solar_Kollektortemp", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
	      { "offset" => 6, "name" => "Solar_Kesseltemp", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
	      { "offset" => 8, "name" => "Solar_VL", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
	      { "offset" => 10, "name" => "Solar_RL", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
	      { "offset" => 12, "name" => "Tage", "bitSize" => 15, "factor" => 1, "unit" => "T" },
	      { "offset" => 16, "name" => "Volumenstrom_V40", "bitSize" => 31, "factor" => 1, "unit" => "1/h" },
	      { "offset" => 20, "name" => "Drehzahl1", "bitSize" => 7, "factor" => 1, "unit" => "%" },
	      { "offset" => 24, "name" => "Waermemenge", "bitSize" => 31, "factor" => 1, "unit" => "Wh" },
	      { "offset" => 32, "name" => "Betriebstunden", "bitSize" => 31, "factor" => 1, "unit" => "h" },
	      { "offset" => 44, "name" => "SW-Version", "bitSize" => 7, "factor" => 0.01 },
	      { "offset" => 44, "name" => "Urlaubsfunktion", "bitSize" => 1, "factor" => 1 },
	      { "offset" => 45, "name" => "Blockierschutz_1", "bitSize" => 7, "factor" => 1, "unit" => "%" },
	      { "offset" => 69, "name" => "Speichermaximaltemperatur", "bitSize" => 1, "factor" => 1 },
	      { "offset" => 72, "name" => "Fehlermaske", "bitSize" => 31, "factor" => 1 },
	        ]},
    "2272" => {"name" => "DeltaSol_SLL_WMZ1", "cmd" => "0100", "fields" => [
	      { "offset" => 0, "name" => "Leistung_gesamt", "bitSize" => 31, "factor" => 1, "unit" => "Wh" },
	      { "offset" => 4, "name" => "Leistung", "bitSize" => 31, "factor" => 1, "unit" => "W" },
	      { "offset" => 8, "name" => "Leistung_heute", "bitSize" => 31, "factor" => 1, "unit" => "Wh" },
	      { "offset" => 12, "name" => "Leistung_Woche", "bitSize" => 31, "factor" => 1, "unit" => "Wh" },
	        ]},
  	"4010" => {"name" => "WMZ", "cmd" => "0100", "fields" => [
 			{ "offset" =>  0,"name" => "Heat_kWh","bitSize" => 15,"factor" => 1,"unit" => "kWh" },
 			{ "offset" =>  2,"name" => "Heat_Wh","bitSize" => 15,"factor" => 1,"unit" => "Wh" },
 			{ "offset" =>  4,"name" => "Flow_rate","bitSize" => 15,"factor" => 0.01,"unit" => "qm/h" },
 			{ "offset" =>  6,"name" => "Power","bitSize" => 8,"factor" => 10,"unit" => "W" },
 			{ "offset" =>  8,"name" => "Flow_temperature","bitSize" => 16,"factor" => 0.1,"unit" => "°C" },
 			{ "offset" =>  10,"name" => "Return_temperature","bitSize" => 16,"factor" => 0.1,"unit" => "°C" },
 			{ "offset" =>  12,"name" => "Heat_MWh","bitSize" => 15,"factor" => 1,"unit" => "MWh" },
 			{ "offset" =>  14,"name" => "Power2","bitSize" => 8,"factor" => 2560,"unit" => "W" },
 			{ "offset" =>  15,"name" => "Glycol","bitSize" => 8,"factor" => 1,"unit" => "" },
 			{ "offset" =>  16,"name" => "Pressure","bitSize" => 8,"factor" => 1,"unit" => "bar" },
     		]},
  	"4211" => {"name" => "SKSC1/2", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "Temperatur_Sensor1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "Temperatur_Sensor2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "Temperatur_Sensor3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "Temperatur_Sensor4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "Drehzahl_Pumpe1","bitSize" => 8, "unit" => "%" },
			{ "offset" =>  9,"name" => "Drehzahl_Pumpe2","bitSize" => 8, "unit" => "%" },
			{ "offset" => 10,"name" => "Fehlermaske","bitSize" => 8 },
			{ "offset" => 12,"name" => "Betriebsstunden_Pumpe1","bitSize" => 16,"factor" => 1,"unit" => "h"  },
			{ "offset" => 14,"name" => "Betriebsstunden_Pumpe2","bitSize" => 16,"factor" => 1,"unit" => "h"  },
			{ "offset" => 16,"name" => "Waermemenge1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 18,"name" => "Waermemenge2","bitSize" => 16,"factor" => 1000,"unit" => "Wh" },
			{ "offset" => 20,"name" => "Waermemenge3","bitSize" => 16,"factor" => 1000000,"unit" => "Wh" },
  			]},
 	"4212" => {"name" => "DeltaSolC", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "temperature_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "temperature_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "temperature_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "speed_R1","bitSize" => 8, "unit" => "%" },
			{ "offset" =>  9,"name" => "speed_R2","bitSize" => 8, "unit" => "%" },
			{ "offset" => 10,"name" => "errormask","bitSize" => 8 },
			{ "offset" => 11,"name" => "variante","bitSize" => 8 },
			{ "offset" => 12,"name" => "operating_hours_R1","bitSize" => 16,"factor" => 1,"unit" => "h"  },
			{ "offset" => 14,"name" => "operating_hours_R2","bitSize" => 16,"factor" => 1,"unit" => "h"  },
			{ "offset" => 16,"name" => "waermemenge_1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 18,"name" => "waermemenge_2","bitSize" => 16,"factor" => 1000,"unit" => "Wh" },
			{ "offset" => 20,"name" => "waermemenge_3","bitSize" => 16,"factor" => 1000000,"unit" => "Wh" },
			{ "offset" => 22,"name" => "systemtime","bitSize" => 15 },
 			]},			
	"4278" => {"name" => "DeltaSol_BS4", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "Kollektortemperatur_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "SpeichertemperaturUnten_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "SpeichertemperaturOben_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "speed_R1","bitSize" => 8,"unit" => "%" },
			{ "offset" =>  9,"name" => "speed_R2","bitSize" => 8,"unit" => "%" },
			{ "offset" => 10,"name" => "errorMask","bitSize" => 16 },
			{ "offset" => 12,"name" => "operating_hours_R1","bitSize" => 16,"factor" => 1,"unit" => "h" },
			{ "offset" => 14,"name" => "operating_hours_R2","bitSize" => 16,"factor" => 1,"unit" => "h" },
			{ "offset" => 23,"name" => "Programm","bitSize" => 8,"factor" => 1 },
			{ "offset" => 24,"name" => "sw_version","bitSize" => 16,"factor" => 0.01 },
			]},
	"427B" => {"name" => "DeltaSol_BS_2009", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "temperature_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "temperature_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "temperature_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "speed_R1","bitSize" => 8,"unit" => "%" },
			{ "offset" => 10,"name" => "operating_hours_R1","bitSize" => 16,"factor" => 1,"unit" => "h" },
			{ "offset" => 12,"name" => "speed_R2","bitSize" => 8,"unit" => "%" },
			{ "offset" => 14,"name" => "operating_hours_R2","bitSize" => 16,"factor" => 1,"unit" => "h" },
			{ "offset" => 16,"name" => "unit_type","bitSize" => 8,"factor" => 1 },
			{ "offset" => 17,"name" => "system","bitSize" => 8},
			{ "offset" => 20,"name" => "error_mask","bitSize" => 16},
			{ "offset" => 20,"name" => "error_S1","bitSize" => 1,"bitPos" => 0},
			{ "offset" => 20,"name" => "error_S2","bitSize" => 1,"bitPos" => 1},
			{ "offset" => 20,"name" => "error_S3","bitSize" => 1,"bitPos" => 2},
			{ "offset" => 20,"name" => "error_S4","bitSize" => 1,"bitPos" => 3},
			{ "offset" => 22,"name" => "systemtime","bitSize" => 15 },
			{ "offset" => 24,"name" => "status_mask","bitSize" => 32 },
			{ "offset" => 28,"name" => "heat_amount","bitSize" => 32,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 32,"name" => "sv_version","bitSize" => 16,"factor" => 0.01 },
			{ "offset" => 34,"name" => "variant_","bitSize" => 16 },
			]},
	"5251" => {"name" => "Frischwasserregler", "cmd" => "0100", "fields" => [
            { "offset" =>  0,  "name" => "temperature_T01"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" =>  2,  "name" => "temperature_T02"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" =>  4,  "name" => "temperature_T03"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" =>  6,  "name" => "temperature_T04"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" =>  8,  "name" => "temperature_T05"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" => 10,  "name" => "temperature_T06"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" => 22,  "name" => "temperature_VFS"     , "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
            { "offset" => 36,  "name" => "Volume_flow_VFS"     , "bitSize" => 31, "factor" =>   1, "unit" => "l/h"},
            { "offset" => 49,  "name" => "speed_R1"            , "bitSize" => 8 ,                  "unit" => "%"  },
            { "offset" => 50,  "name" => "speed_R2"            , "bitSize" => 8 ,                  "unit" => "%"  },
            { "offset" => 51,  "name" => "speed_R3"            , "bitSize" => 8 ,                  "unit" => "%"  },
            { "offset" => 52,  "name" => "speed_R4"            , "bitSize" => 8 ,                  "unit" => "%"  },
            { "offset" => 56,  "name" => "speed_PWM1"          , "bitSize" => 8 ,                  "unit" => "%"  },
            { "offset" => 57,  "name" => "speed_PWM2"          , "bitSize" => 8 ,                  "unit" => "%"  },
            { "offset" => 64,  "name" => "operating_hours_R1"  , "bitSize" => 31, "factor" =>   1, "unit" => "h"  },
            { "offset" => 68,  "name" => "operating_hours_R2"  , "bitSize" => 31, "factor" =>   1, "unit" => "h"  },
            { "offset" => 72,  "name" => "operating_hours_R3"  , "bitSize" => 31, "factor" =>   1, "unit" => "h"  },
            { "offset" => 76,  "name" => "operating_hours_R4"  , "bitSize" => 31, "factor" =>   1, "unit" => "h"  },
            { "offset" => 80,  "name" => "operating_hours_PWM1", "bitSize" => 31, "factor" =>   1, "unit" => "h"  },
            { "offset" => 84,  "name" => "operating_hours_PWM2", "bitSize" => 31, "factor" =>   1, "unit" => "h"  },
            { "offset" => 96,  "name" => "heat_amount"         , "bitSize" => 31, "factor" =>   1, "unit" => "Wh" },
            { "offset" => 100, "name" => "error_mask"          , "bitSize" => 15                                  },
            { "offset" => 108, "name" => "sv_version"          , "bitSize" => 15, "factor" => 0.01                },
            { "offset" => 112, "name" => "systemtime"          , "bitSize" => 15                                  },
            ]},
   	"5400" => {"name" => "DeltaThermHC_Regler", "cmd" => "0100", "fields" => [
    	{ "offset" => 0, "name" => "Temperatur_Sensor_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "Temperatur_Sensor_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 10, "name" => "Temperatur_Sensor_6", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 12, "name" => "Temperatur_Sensor_7", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 14, "name" => "Temperatur_Sensor_8", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 16, "name" => "Temperatur_Sensor_9", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
    	{ "offset" => 18, "name" => "Einstrahlung_Sensor", "bitSize" => 15, "factor" => 1, "unit" => "W/qm" },
    	{ "offset" => 20, "name" => "Temperatur_Sensor_11", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 22, "name" => "Temperatur_Sensor_12", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 24, "name" => "Volumenstrom_Sensor_1", "bitSize" => 31, "factor" => 1, "unit" => "l/h" },
			{ "offset" => 28, "name" => "Volumenstrom_Sensor_2", "bitSize" => 31, "factor" => 1, "unit" => "l/h" },
			{ "offset" => 32, "name" => "Volumenstrom_Sensor_3", "bitSize" => 31, "factor" => 1, "unit" => "l/h" },
			{ "offset" => 34,"name" => "Druck_Sensor_11","bitSize" => 15,"factor" => 0.01,"unit" => "bar" },
			{ "offset" => 36,"name" => "Druck_Sensor_12","bitSize" => 15,"factor" => 0.01,"unit" => "bar" },
			{ "offset" => 38, "name" => "Drehzahl_Relais_1", "bitSize" => 8, "factor" => 1, "unit" => "%" },
 			{ "offset" => 39, "name" => "Drehzahl_Relais_2", "bitSize" => 8, "factor" => 1, "unit" => "%" },
 			{ "offset" => 40, "name" => "Drehzahl_Relais_3", "bitSize" => 8, "factor" => 1, "unit" => "%" },
 			{ "offset" => 41, "name" => "Drehzahl_Relais_4", "bitSize" => 8, "factor" => 1, "unit" => "%" },
 			{ "offset" => 42, "name" => "Drehzahl_Relais_5", "bitSize" => 8, "factor" => 1, "unit" => "%" },
 			{ "offset" => 43, "name" => "Regler_Ausgang_1", "bitSize" => 7,  "factor" => 1, "unit" => "%" },
 			{ "offset" => 44, "name" => "Regler_Ausgang_2", "bitSize" => 7,  "factor" => 1, "unit" => "%" },
 			{ "offset" => 45,"name" => "Systemdatum","bitSize" => 31},
 			{ "offset" => 49, "name" => "Fehlermaske", "bitSize" => 31, "factor" => 1 },
  		{ "offset" => 53, "name" => "Warnungsmaske", "bitSize" => 31, "factor" => 1 },  
   			]},
  	"5410" => {"name" => "DeltaThermHC_HK0", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "TV_VorlaufSoll","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "TV_Betriebsstatus","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  4,"name" => "Betriebsart","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  6,"name" => "Brennerstarts1","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  8,"name" => "Brennerstarts2","bitSize" => 8,"factor" => 1 },
 			{ "offset" =>  10,"name" => "Brennerstarts3","bitSize" => 8,"factor" => 1 },
 			{ "offset" =>  12,"name" => "Brennerstarts4","bitSize" => 8,"factor" => 1 },
    		]},
    "5411" => {"name" => "DeltaThermHC_HK1", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "TV_VorlaufSoll","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "TV_Betriebsstatus","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  4,"name" => "Betriebsart","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  6,"name" => "Brennerstarts1","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  8,"name" => "Brennerstarts2","bitSize" => 8,"factor" => 1 },
 			{ "offset" =>  10,"name" => "Brennerstarts3","bitSize" => 8,"factor" => 1 },
 			{ "offset" =>  12,"name" => "Brennerstarts4","bitSize" => 8,"factor" => 1 },
    		]}, 
    "5412" => {"name" => "DeltaThermHC_HK2", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "TV_VorlaufSoll","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "TV_Betriebsstatus","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  4,"name" => "Betriebsart","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  6,"name" => "Brennerstarts1","bitSize" => 8,"factor" => 1 },
			{ "offset" =>  8,"name" => "Brennerstarts2","bitSize" => 8,"factor" => 1 },
 			{ "offset" =>  10,"name" => "Brennerstarts3","bitSize" => 8,"factor" => 1 },
 			{ "offset" =>  12,"name" => "Brennerstarts4","bitSize" => 8,"factor" => 1 },
    		]},        
  	"5420" => {"name" => "DeltaThermHC_WMZ", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "Wert","bitSize" => 32,"factor" => 1,"unit" => "kWh" },
			{ "offset" =>  4,"name" => "Leistung","bitSize" => 32,"unit" => "W" },
			{ "offset" =>  8,"name" => "WertHeute","bitSize" => 32,"factor" => 1,"unit" => "kWh" },
 			{ "offset" =>  12,"name" => "WertWoche","bitSize" => 32,"factor" => 1,"unit" => "kWh" },
    		]},   
  	"5611" => {"name" => "DeltaTherm_FK", "cmd" => "0100", "fields" => [
  		{ "offset" =>  0,"name" => "Temperatur_1","bitSize" => 16,"factor" => 0.1,"unit" => "°C" },
  		{ "offset" =>  2,"name" => "Temperatur_2","bitSize" => 16,"factor" => 0.1,"unit" => "°C" },
  		{ "offset" =>  4,"name" => "Temperatur_3","bitSize" => 16,"factor" => 0.1,"unit" => "°C" },
  		{ "offset" =>  6,"name" => "Temperatur_4","bitSize" => 16,"factor" => 0.1,"unit" => "°C" },
  		{ "offset" =>  8,"name" => "Drehzahl_Reais_1","bitSize" => 8,"factor" => 1,"unit" => "%" },
  		{ "offset" =>  9,"name" => "Drehzahl_Reais_2","bitSize" => 8,"factor" => 1,"unit" => "%" },
  		{ "offset" =>  10,"name" => "Mischer_Auf","bitSize" => 8,"factor" => 1,"unit" => "%" },
  		{ "offset" =>  11,"name" => "Mischer_Zu","bitSize" => 8,"factor" => 1,"unit" => "%" },
  		{ "offset" =>  12,"name" => "Datum","bitSize" => 32,"factor" => 1,"unit" => "Tage" },
  		{ "offset" =>  18,"name" => "Uhrzeit","bitSize" => 16,"factor" => 1,"unit" => "h" },
  		{ "offset" =>  20,"name" => "Systemmeldung","bitSize" => 8,"factor" => 1,"unit" => "m" },
   			]},
   	"6521" => {"name" => "MSR65_1", "cmd" => "0200", "fields" => [
 #  "7821" => {"name" => "MSR65_1", "cmd" => "0200", "fields" => [
  		{ "offset" => 0, "name" => "Temperatur_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "Temperatur_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "Temperatur_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Temperatur_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
 			{ "offset" => 8, "name" => "Temperatur_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
 			{ "offset" => 10, "name" => "Temperatur_6", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },	
  			]},
   	"6522" => {"name" => "MSR65_2", "cmd" => "0100", "fields" => [
 			{ "offset" => 0, "name" => "Temperatur_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "Temperatur_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "Temperatur_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Temperatur_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
 			{ "offset" => 8, "name" => "Temperatur_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
 			{ "offset" => 10, "name" => "Temperatur_6", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },	
  			]},  
   	"7160" => {"name" => "SKS3HE", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "7160_Temperatur_Sensor_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "7160_Temperatur_Sensor_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "7160_Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 6, "name" => "7160_Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "7160_Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 10, "name" => "7160_Temperatur_Sensor_6", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 12, "name" => "7160_Temperatur_Sensor_7", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 14, "name" => "7160_Temperatur_Sensor_8", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 36, "name" => "7160_Temperatur_GFD1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 38, "name" => "7160_Temperatur_GFD2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 16, "name" => "7160_Einstrahlung", "bitSize" => 15, "factor" => 1, "unit" => "W/qm" },
			{ "offset" => 18, "name" => "7160_Volumenstrom", "bitSize" => 31, "factor" => 1, "unit" => "l/h" },
			{ "offset" => 44, "name" => "7160_Volumenstrom_2", "bitSize" => 31, "factor" => 1, "unit" => "l/h" },
			{ "offset" => 48, "name" => "7160_Volumenstrom_3", "bitSize" => 31, "factor" => 1, "unit" => "l/h" },
			{ "offset" => 20, "name" => "7160_Drehzahl_A1", "bitSize" => 8, "factor" => 1, "unit" => "%" },
			{ "offset" => 21, "name" => "7160_Drehzahl_A2", "bitSize" => 8, "factor" => 1, "unit" => "%" },
			{ "offset" => 22, "name" => "7160_Drehzahl_A3", "bitSize" => 8, "factor" => 1, "unit" => "%" },
			{ "offset" => 23, "name" => "7160_Drehzahl_A4", "bitSize" => 8, "factor" => 1, "unit" => "%" },
			{ "offset" => 24, "name" => "7160_Wärme", "bitSize" => 15, "factor" => 1, "unit" => "Wh" },
			{ "offset" => 26, "name" => "7160_Wärme", "bitSize" => 15, "factor" => 1000, "unit" => "Wh" },
			{ "offset" => 28, "name" => "7160_Wärme", "bitSize" => 15, "factor" => 1000000, "unit" => "Wh" },
			{ "offset" => 30, "name" => "7160_Wärme", "bitSize" => 15, "factor" => 1000000000, "unit" => "Wh" },
			{ "offset" => 60, "name" => "7160_Wärme_2", "bitSize" => 15, "factor" => 1, "unit" => "Wh" },
			{ "offset" => 62, "name" => "7160_Wärme_2", "bitSize" => 15, "factor" => 1000, "unit" => "Wh" },
			{ "offset" => 64, "name" => "7160_Wärme_2", "bitSize" => 15, "factor" => 1000000, "unit" => "Wh" },
			{ "offset" => 66, "name" => "7160_Wärme_2", "bitSize" => 15, "factor" => 1000000000, "unit" => "Wh" },
			{ "offset" => 68, "name" => "7160_Wärme_3", "bitSize" => 15, "factor" => 1, "unit" => "Wh" },
			{ "offset" => 70, "name" => "7160_Wärme_3", "bitSize" => 15, "factor" => 1000, "unit" => "Wh" },
			{ "offset" => 72, "name" => "7160_Wärme_3", "bitSize" => 15, "factor" => 1000000, "unit" => "Wh" },
			{ "offset" => 74, "name" => "7160_Wärme_3", "bitSize" => 15, "factor" => 1000000000, "unit" => "Wh" },
			{ "offset" => 52, "name" => "7160_Leistung_2", "bitSize" => 31, "factor" => 0.001, "unit" => "kW" },
			{ "offset" => 56, "name" => "7160_Leistung_3", "bitSize" => 31, "factor" => 0.001, "unit" => "kW" },
			{ "offset" => 32, "name" => "7160_Fehlermaske", "bitSize" => 8, "factor" => 1 },
			{ "offset" => 33, "name" => "7160_Sensorbruchnummer", "bitSize" => 8, "factor" => 1 },
			{ "offset" => 34, "name" => "7160_Sensorkurzschlussnummer", "bitSize" => 8, "factor" => 1 },
			{ "offset" => 42, "name" => "7160_Systemzeit", "bitSize" => 15, "factor" => 1, },
			{ "offset" => 42, "name" => "7160_Systemzeit2", "bitSize" => 15, "factor" => 1, "timeRef" => 1 },
			]},
	"7161" => {"name" => "SKSC3HE_[HK1]", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "7161_HK1_Vorlaufsolltemperatur", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "7161_Mischerlaufzeit", "bitSize" => 8, "factor" => 1, "unit" => "s" },
			{ "offset" => 3, "name" => "7161_Mischerpausenzeit", "bitSize" => 8, "factor" => 1, "unit" => "s" },
			{ "offset" => 4, "name" => "7161_HK-Status", "bitSize" => 16, "factor" => 1, "unit" => "" },
			]},
	"7162" => {"name" => "SKSC3HE_[HK2]", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "7162_HK2_Vorlaufsolltemperatur", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "7162_Mischerlaufzeit", "bitSize" => 8, "factor" => 1, "unit" => "s" },
			{ "offset" => 3, "name" => "7162_Mischerpausenzeit", "bitSize" => 8, "factor" => 1, "unit" => "s" },
			{ "offset" => 4, "name" => "7162_HK-Status", "bitSize" => 16, "factor" => 1, "unit" => "" },
			]},
	"7311" => {"name" => "DeltaSol_M", "cmd" => "0100", "fields" => [
			{ "offset" => 0,"name" => "Temperatur_01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 2,"name" => "Temperatur_02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 4,"name" => "Temperatur_03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 6,"name" => "Temperatur_04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 8,"name" => "Temperatur_05","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => "Temperatur_06","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => "Temperatur_07","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => "Temperatur_08","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => "Temperatur_09","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => "Temperatur_10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 20,"name" => "Temperatur_11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 22,"name" => "Temperatur_12","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 24,"name" => "Einstrahlung", "bitSize" => 15,"unit" => "W/qm" },
			{ "offset" => 44,"name" => "Drehzahl_Pumpe_01","bitSize" => 7, "unit" => "%" },
			{ "offset" => 45,"name" => "Drehzahl_Pumpe_02","bitSize" => 7, "unit" => "%" },
			{ "offset" => 46,"name" => "Drehzahl_Pumpe_03","bitSize" => 7, "unit" => "%" },
			{ "offset" => 47,"name" => "Drehzahl_Pumpe_04","bitSize" => 7, "unit" => "%" },
			{ "offset" => 48,"name" => "Drehzahl_Pumpe_05","bitSize" => 7, "unit" => "%" },
			{ "offset" => 49,"name" => "Drehzahl_Pumpe_06","bitSize" => 7, "unit" => "%" },
			{ "offset" => 50,"name" => "Drehzahl_Pumpe_07","bitSize" => 7, "unit" => "%" },
			{ "offset" => 51,"name" => "Drehzahl_Pumpe_08","bitSize" => 7, "unit" => "%" },
			{ "offset" => 52,"name" => "Drehzahl_Pumpe_09","bitSize" => 7, "unit" => "%" },
			{ "offset" => 60,"name" => "Fehlermaske","bitSize" => 16 },
			{ "offset" => 62,"name" => "Warnmaske","bitSize" => 16 },
			{ "offset" => 64,"name" => "controllerversion","bitSize" => 16 },
			{ "offset" => 66,"name" => "systemtime","bitSize" => 16 },
	  		]},
	"7312" => {"name" => "DeltaSol_M_HKM", "cmd" => "0100", "fields" => [
			{ "offset" => 8,"name" => "Vorlauf_Soll_Temperatur","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
  			]},
	"7315" => {"name" => "DeltaSol_M_Volumen", "cmd" => "0100", "fields" => [
			{ "offset" => 0,"name" => "Betriebssekunden R1","bitSize" => 15,"unit" => "s" },
			{ "offset" => 4,"name" => "Betriebssekunden R2","bitSize" => 15,"unit" => "s" },
			{ "offset" => 8,"name" => "Betriebssekunden R3","bitSize" => 15,"unit" => "s" },
			{ "offset" => 12,"name" => "Betriebssekunden R4","bitSize" => 15,"unit" => "s" },
			{ "offset" => 16,"name" => "Betriebssekunden R5","bitSize" => 15,"unit" => "s" },
			{ "offset" => 20,"name" => "Betriebssekunden R6","bitSize" => 15,"unit" => "s" },
			{ "offset" => 24,"name" => "Betriebssekunden R7","bitSize" => 15,"unit" => "s" },
			{ "offset" => 28,"name" => "Betriebssekunden R8","bitSize" => 15,"unit" => "s" },
			{ "offset" => 32,"name" => "Betriebssekunden R9","bitSize" => 15,"unit" => "s" },
			{ "offset" => 36,"name" => "Volumen 1","bitSize" => 15,"unit" => "l" },
			{ "offset" => 40,"name" => "Volumen 2","bitSize" => 15,"unit" => "l" },
  			]},
	"7316" => {"name" => "DeltaSol_M_WMZ1", "cmd" => "0100", "fields" => [
#			{ "offset" => 0,"name" => "Kollektor_Rücklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
#			{ "offset" => 2,"name" => "Kollektor_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 4,"name" => "Volumenstrom_Kollektor","bitSize" => 15,"unit" => "l/h" },
			{ "offset" => 6,"name" => "Wärmemenge_1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 8,"name" => "Wärmemenge_2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" => 10,"name" => "Wärmemenge_3","bitSize" => 16,"unit" => "MWh" },
		  	]},
	"7317" => {"name" => "DeltaSol_M_WMZ2", "cmd" => "0100", "fields" => [
#			{ "offset" => 0,"name" => "Kollektor_Rücklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
#			{ "offset" => 2,"name" => "Kollektor_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 4,"name" => "Volumenstrom_Kollektor","bitSize" => 15,"unit" => "l/h" },
			{ "offset" => 6,"name" => "Wärmemenge_1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 8,"name" => "Wärmemenge_2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" => 10,"name" => "Wärmemenge_3","bitSize" => 16,"unit" => "MWh" },
  			]},
	"7321" => {"name" => "Vitosolic200", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "temperature_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "temperature_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "temperature_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "temperature_T05","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => "temperature_T06","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => "temperature_T07","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => "temperature_T08","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => "temperature_T09","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => "temperature_T10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 20,"name" => "temperature_T11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 22,"name" => "temperature_T12","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 24,"name" => "insolation", "bitSize" => 15,"unit" => "W/qm" },
			{ "offset" => 28,"name" => "impulse_I01","bitSize" => 31 },
			{ "offset" => 32,"name" => "impulse_I02","bitSize" => 31 },
			{ "offset" => 36,"name" => "sensorbrokemask","bitSize" => 16 },
			{ "offset" => 38,"name" => "sensorshortmask","bitSize" => 16 },
			{ "offset" => 40,"name" => "sensorusagemask","bitSize" => 16 },
			{ "offset" => 44,"name" => "speed_R01","bitSize" => 8, "unit" => "%" },
			{ "offset" => 45,"name" => "speed_R02","bitSize" => 8, "unit" => "%" },
			{ "offset" => 46,"name" => "speed_R03","bitSize" => 8, "unit" => "%" },
			{ "offset" => 47,"name" => "speed_R04","bitSize" => 8, "unit" => "%" },
			{ "offset" => 48,"name" => "speed_R05","bitSize" => 8, "unit" => "%" },
			{ "offset" => 49,"name" => "speed_R06","bitSize" => 8, "unit" => "%" },
			{ "offset" => 50,"name" => "speed_R07","bitSize" => 8, "unit" => "%" },
			{ "offset" => 51,"name" => "speed_R08","bitSize" => 8, "unit" => "%" },
			{ "offset" => 52,"name" => "speed_R09","bitSize" => 8, "unit" => "%" },
			{ "offset" => 58,"name" => "relaisusagemask","bitSize" => 16 },
			{ "offset" => 60,"name" => "errormask","bitSize" => 16 },
			{ "offset" => 62,"name" => "warningmask","bitSize" => 16 },
			{ "offset" => 64,"name" => "controllerversion","bitSize" => 16 },
			#{ "offset" => 66,"name" => "systemtime","bitSize" => 16 },
 			{ "offset" => 66,"name" => "systemtime","bitSize" => 15,"timeRef" => 1 },
   		]},
	"7326" => {"name" => "Vitosolic200_WMZ1", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "WMZ1_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "WMZ1_Ruecklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "WMZ1_volumeflow","bitSize" => 15,"unit" => "l/h" },
			{ "offset" =>  6,"name" => "WMZ1_heatquantity1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  8,"name" => "WMZ1_heatquantity2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" =>  10,"name" => "WMZ1_heatquantity3","bitSize" => 16,"unit" => "MWh" },
 			]},
	"7327" => {"name" => "Vitosolic200_WMZ2", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "WMZ2_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "WMZ2_Ruecklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "WMZ2_volumeflow","bitSize" => 15,"unit" => "l/h" },
			{ "offset" =>  6,"name" => "WMZ2_heatquantity1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  8,"name" => "WMZ2_heatquantity2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" =>  10,"name" => "WMZ2_heatquantity3","bitSize" => 16,"unit" => "MWh" },
 			]},
	"7331" => {"name" => "SLR", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => " Temperature_1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => " Temperature_2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => " Temperature_3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => " Temperature_4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => " Temperature_5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => " Temperature_6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => " Temperature_7","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => " Temperature_8","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => " Temperature_9","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => " Temperature_10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 20,"name" => " Temperature_11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 22,"name" => " Temperature_12","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 24,"name" => " Temperature_13","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 26,"name" => " Temperature_14","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 28,"name" => " Temperature_15","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 30,"name" => " Temperature_16","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 32,"name" => " Temperature_17","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 34,"name" => " Temperature_18","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 36,"name" => " Temperature_19","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 38,"name" => " Temperature_20","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 40,"name" => " Temperature_21","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 42,"name" => " Temperature_22","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 44,"name" => " Pump_R1","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 45,"name" => " Pump_R2","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 46,"name" => " Pump_R3","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 47,"name" => " Pump_R4","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 48,"name" => " Pump_R5","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 49,"name" => " Pump_R6","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 50,"name" => " Pump_R7","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 51,"name" => " Pump_R8","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 52,"name" => " Pump_R9","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 53,"name" => " Pump_R10","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 54,"name" => " Pump_R11","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 55,"name" => " Pump_R12","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 56,"name" => " Pump_R13","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 57,"name" => " Pump_R14","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 58,"name" => " Pump_R15","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 59,"name" => " Pump_R16","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 60,"name" => " Pump_R17","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 61,"name" => " Pump_R18","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 64,"name" => " Sensor_mask","bitSize" => 31,"factor" => 1,"unit" => "1" },
			{ "offset" => 68,"name" => " Sensor_mask","bitSize" => 31,"factor" => 2,"unit" => "1" },
			{ "offset" => 72,"name" => " Error_1","bitSize" => 15 },
			{ "offset" => 74,"name" => " Warning_1","bitSize" => 15 },
			{ "offset" => 76,"name" => " Version_","bitSize" => 15 },
			{ "offset" => 78,"name" => " System_1","bitSize" => 15 },
			{ "offset" => 80,"name" => " Variant_","bitSize" => 8 },
			]},
	"7341" => {"name" => "CitrinSLR_XT", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "S1-SF-K", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "S2-SF-1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "S3-SF-2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "S4-SF-3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "S5-FN-HK", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 10, "name" => "S6-FN-WW", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 12, "name" => "S7-FN-K2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 14, "name" => "S8-FZ", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 16, "name" => "S9-AF", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 18, "name" => "S10-VL-F1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 20, "name" => "S11-FV-1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 22, "name" => "S12-VL-F", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 24, "name" => "S13-FV-", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 26, "name" => "S14-KF", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 28, "name" => "S15-KF-", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 30, "name" => "S16-BF", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 32, "name" => "SensorVolumenstrom_Regler_GAS1_TotalWert_L", "bitSize" => 31, "unit" => "L" },
#			{ "offset" => 36, "name" => "SensorVolumenstrom_Regler_GAS2_TotalWert_L", "bitSize" => 31, "unit" => "L" },
#			{ "offset" => 40, "name" => "SensorVolumenstrom_Regler_GDS1_TotalWert_L", "bitSize" => 31, "unit" => "L" },
#			{ "offset" => 44, "name" => "SensorVolumenstrom_Regler_GDS2_TotalWert_L", "bitSize" => 31, "unit" => "L" },
			{ "offset" => 48, "name" => "Sensor_Regler_Druck_GAS1_Wert_Bar", "bitSize" => 15, "factor" => 0.01, "unit" => "bar" },
			{ "offset" => 50, "name" => "Sensor_Regler_Druck_GAS2_Wert_Bar", "bitSize" => 15, "factor" => 0.01, "unit" => "bar" },
#			{ "offset" => 52, "name" => "Sensor_Regler_Druck_GDS1_Wert_Bar", "bitSize" => 15, "factor" => 0.01, "unit" => "bar" },
#			{ "offset" => 54, "name" => "Sensor_Regler_Druck_GDS2_Wert_Bar", "bitSize" => 15, "factor" => 0.01, "unit" => "bar" },
			{ "offset" => 56, "name" => "R1-SP-1", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 57, "name" => "R2-SP-2", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 58, "name" => "R3-BL", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 59, "name" => "R4-SV", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 60, "name" => "R5-HKP1", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 61, "name" => "R6-MV-1_auf", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 62, "name" => "R7-MV-1_zu", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 63, "name" => "R8-KLP-", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 64, "name" => "R9-KLP-", "bitSize" => 7, "unit" => "%", "bitSize" => 7 },
			{ "offset" => 65, "name" => "R10-SV-", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 66, "name" => "R11-MV-2_auf", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 67, "name" => "R12-MV-2_zu", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 68, "name" => "R13-ZP", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 69, "name" => "R14-RP", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 72, "name" => "Hk1_T_VorlSoll", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 74, "name" => "Hk2_T_VorlSoll", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 76, "name" => "Hk3_T_VorlSoll", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 78, "name" => "Hk4_T_VorlSoll", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
#			{ "offset" => 80, "name" => "Hk5_T_VorlSoll", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 82, "name" => "SW_VL_Soll", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 84, "name" => "Wmz1_Wert_Wh", "bitSize" => 31, "unit" => "Wh" },
			{ "offset" => 88, "name" => "Wmz2_Wert_Wh", "bitSize" => 31, "unit" => "Wh" },
#			{ "offset" => 92, "name" => "Systemdatum", "bitSize" => 31, },
			{ "offset" => 96, "name" => "SensorBenutzt_bit_0..31", "bitSize" => 32,  },
			{ "offset" => 100, "name" => "SensorBenutzt_bit_31..63", "bitSize" => 32,  },
			{ "offset" => 104, "name" => "Error_SensorBruch_bit_0..31", "bitSize" => 32,  },
			{ "offset" => 108, "name" => "Error_SensorBruch_bit_31..63", "bitSize" => 32,  },
			{ "offset" => 112, "name" => "Error_SensorKurzschluss_bit_0..31", "bitSize" => 32,  },
			{ "offset" => 116, "name" => "Error_SensorKurzschluss_bit_31..63", "bitSize" => 32,  },
			{ "offset" => 120, "name" => "Errormask", "bitSize" => 16,  },
			{ "offset" => 122, "name" => "Warningmask", "bitSize" => 16,  },
			{ "offset" => 124, "name" => "Systemflow.Parameteraenderungen", "bitSize" => 16,  },
 			]},      
	"7411" => {"name" => "DeltaSol_ES", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "Temperatur_Sensor_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "Temperatur_Sensor_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 10, "name" => "Temperatur_Sensor_6", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 12, "name" => "Temperatur_Sensor_7", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 14, "name" => "Temperatur_Sensor_8", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 16, "name" => "Volumenstrom", "bitSize" => 15, "factor" => 0.01, "unit" => "m" },
			{ "offset" => 18, "name" => "Einstrahlung", "bitSize" => 15 },
			{ "offset" => 20, "name" => "Relaisbyte", "bitSize" => 8 },
			{ "offset" => 21, "name" => "Drehzahl_1", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 22, "name" => "Drehzahl_2", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 23, "name" => "Drehzahl_3", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 20, "name" => "Relais_4", "bitSize" => 1, "bitPos" => 3 },
			{ "offset" => 20, "name" => "Relais_5", "bitSize" => 1, "bitPos" => 4 },
			{ "offset" => 20, "name" => "Relais_6", "bitSize" => 1, "bitPos" => 5 },
			{ "offset" => 24, "name" => "Systemzeit", "bitSize" => 15, "format" => "t", "timeRef" => 1 },
			{ "offset" => 26, "name" => "Schema", "bitSize" => 8 },
			{ "offset" => 27, "name" => "Option:_Kollektorkühlung", "bitSize" => 1, "bitPos" => 0 },
			{ "offset" => 27, "name" => "Option:_Kollektorminimalbegrenzung", "bitSize" => 1, "bitPos" => 1 },
			{ "offset" => 27, "name" => "Option:_Frostschutzfunktion", "bitSize" => 1, "bitPos" => 2 },
			{ "offset" => 27, "name" => "Option:_Röhrenkollektorfunktion", "bitSize" => 1, "bitPos" => 3 },
			{ "offset" => 27, "name" => "Option:_Rückkühlung", "bitSize" => 1, "bitPos" => 4 },
			{ "offset" => 27, "name" => "Option:_Wärmemengenzählung", "bitSize" => 1, "bitPos" => 5 },
			{ "offset" => 28, "name" => "Betriebsstunden_1", "bitSize" => 16, "unit" => "h" },
			{ "offset" => 30, "name" => "Betriebsstunden_2", "bitSize" => 16, "unit" => "h" },
			{ "offset" => 32, "name" => "Betriebsstunden_3", "bitSize" => 16, "unit" => "h" },
			{ "offset" => 34, "name" => "Betriebsstunden_4", "bitSize" => 16, "unit" => "h" },
			{ "offset" => 36, "name" => "Betriebsstunden_5", "bitSize" => 16, "unit" => "h" },
			{ "offset" => 38, "name" => "Betriebsstunden_6", "bitSize" => 16, "unit" => "h" },
			{ "offset" => 39, "name" => "Wärmemenge_1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 40, "name" => "Wärmemenge_2","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" => 42, "name" => "Wärmemenge_3","bitSize" => 16,"factor" => 1000,"unit" => "Wh" },
			{ "offset" => 44, "name" => "Wärmemenge_4","bitSize" => 16,"factor" => 1000000,"unit" => "Wh" },
			]},
	"7421" => {"name" => "DeltaSol_BX", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "Temperatur_Sensor_1", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 2, "name" => "Temperatur_Sensor_2", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 4, "name" => "Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 6, "name" => "Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 8, "name" => "Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 10, "name" => "Temperatur_RPS", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 12, "name" => "Druck_RPS", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 14, "name" => "Temperatur_VFS", "bitSize" => 15, "factor" => 0.1 },
			{ "offset" => 16, "name" => "Durchfluss_VFS", "bitSize" => 15, "factor" => 1 },
			{ "offset" => 24, "name" => "Drehzahl_Relais_1", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 25, "name" => "Drehzahl_Relais_2", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 26, "name" => "Drehzahl_Relais_3", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 27, "name" => "Drehzahl_Relais_4", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 22, "name" => "PWM_1", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 23, "name" => "PWM_2", "bitSize" => 8, "unit" => "%" },
			{ "offset" => 16, "name" => "Durchfluss_VFS", "bitSize" => 15, "factor" => 1 },
			{ "offset" => 18, "name" => "Durchfluss_V40", "bitSize" => 15, "factor" => 1 },
			{ "offset" => 48, "name" => "Waermemenge", "bitSize" => 31, "factor" => 1 },
			{ "offset" => 54, "name" => "Systemzeit", "bitSize" => 16 },
			{ "offset" => 56, "name" => "Datum", "bitSize" => 32 },
			{ "offset" => 52, "name" => "Version", "bitSize" => 16, "factor" => 0.01 },
			{ "offset" => 28, "name" => "Betriebssekunden_Relais_1", "bitSize" => 32, "unit" => "s" },
			{ "offset" => 32, "name" => "Betriebssekunden_Relais_2", "bitSize" => 32, "unit" => "s" },
			{ "offset" => 36, "name" => "Betriebssekunden_Relais_3", "bitSize" => 32, "unit" => "s" },
			{ "offset" => 40, "name" => "Betriebssekunden_Relais_4", "bitSize" => 32, "unit" => "s" },
			{ "offset" => 46, "name" => "Status", "bitSize" => 16 },
			{ "offset" => 46, "name" => "Blockierschutz_1", "bitSize" => 1, "bitPos" => 0 },
			{ "offset" => 46, "name" => "Blockierschutz_2", "bitSize" => 1, "bitPos" => 1 },
			{ "offset" => 46, "name" => "Blockierschutz_3", "bitSize" => 1, "bitPos" => 2 },
			{ "offset" => 46, "name" => "Blockierschutz_4", "bitSize" => 1, "bitPos" => 3 },
			{ "offset" => 46, "name" => "Initialisierung", "bitSize" => 1, "bitPos" => 4 },
			{ "offset" => 46, "name" => "Fuellung", "bitSize" => 1, "bitPos" => 5 },
			{ "offset" => 46, "name" => "Stabilisierung", "bitSize" => 1, "bitPos" => 6 },
			{ "offset" => 46, "name" => "Pumpenverzoegerung", "bitSize" => 1, "bitPos" => 7 },
			{ "offset" => 47, "name" => "ueberwaermeabfuhr", "bitSize" => 1, "bitPos" => 0 },
			{ "offset" => 47, "name" => "Nachlauf", "bitSize" => 1, "bitPos" => 1 },
			{ "offset" => 47, "name" => "Thermische_Desinfektion", "bitSize" => 1, "bitPos" => 2 },
			{ "offset" => 47, "name" => "Systemkuehlung", "bitSize" => 1, "bitPos" => 3 },
			{ "offset" => 47, "name" => "Speicherkuehlung", "bitSize" => 1, "bitPos" => 4 },
			{ "offset" => 47, "name" => "Spreizung", "bitSize" => 1, "bitPos" => 5 },
			{ "offset" => 47, "name" => "Frostschutz", "bitSize" => 1, "bitPos" => 6 },
			{ "offset" => 47, "name" => "Kollektorkuehlung", "bitSize" => 1, "bitPos" => 7 },
			{ "offset" => 20, "name" => "Einheit", "bitSize" => 8 },
			{ "offset" => 44, "name" => "Fehler", "bitSize" => 16 },
			{ "offset" => 44, "name" => "Fehler_S1", "bitSize" => 1, "bitPos" => 0 },
			{ "offset" => 44, "name" => "Fehler_S2", "bitSize" => 1, "bitPos" => 1 },
			{ "offset" => 44, "name" => "Fehler_S3", "bitSize" => 1, "bitPos" => 2 },
			{ "offset" => 44, "name" => "Fehler_S4", "bitSize" => 1, "bitPos" => 3 },
			{ "offset" => 44, "name" => "Fehler_S5", "bitSize" => 1, "bitPos" => 4 },
			{ "offset" => 44, "name" => "Fehler_S6", "bitSize" => 1, "bitPos" => 5 },
			{ "offset" => 44, "name" => "Fehler_S7", "bitSize" => 1, "bitPos" => 6 },
			{ "offset" => 44, "name" => "Fehler_S8", "bitSize" => 1, "bitPos" => 7 },
			{ "offset" => 45, "name" => "Fehler_S9", "bitSize" => 1, "bitPos" => 0 },
			{ "offset" => 45, "name" => "Fehler_V40", "bitSize" => 1, "bitPos" => 1 },
			{ "offset" => 45, "name" => "Leckage", "bitSize" => 1, "bitPos" => 2 },
			{ "offset" => 45, "name" => "ueberdruck", "bitSize" => 1, "bitPos" => 3 },
			{ "offset" => 45, "name" => "Durchflussfehler", "bitSize" => 1, "bitPos" => 4 },
			]},		
	"7721" => {"name" => "DeltaSolE_Regler", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "temperature_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "temperature_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "temperature_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "temperature_T05","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => "temperature_T06","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => "temperature_T07","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => "temperature_T08","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => "temperature_T09","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => "temperature_T10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
#			{ "offset" => 20,"name" => "insolation", "bitSize" => 15,"unit" => "W/qm" },
			{ "offset" => 26,"name" => "speed_R01","bitSize" => 7, "unit" => "%" },
			{ "offset" => 27,"name" => "speed_R02","bitSize" => 7, "unit" => "%" },
			{ "offset" => 28,"name" => "speed_R03","bitSize" => 7, "unit" => "%" },
			{ "offset" => 29,"name" => "speed_R04","bitSize" => 7, "unit" => "%" },
			{ "offset" => 30,"name" => "speed_R05","bitSize" => 7, "unit" => "%" },
			{ "offset" => 31,"name" => "speed_R06","bitSize" => 7, "unit" => "%" },
			{ "offset" => 32,"name" => "speed_R07","bitSize" => 7, "unit" => "%" },
			{ "offset" => 36,"name" => "errormask","bitSize" => 16 },
			{ "offset" => 38,"name" => "warningmask","bitSize" => 16 },
			{ "offset" => 56,"name" => "temperature_T11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 58,"name" => "statusHK","bitSize" => 16 },
#			{ "offset" => 64,"name" => "controllerversion","bitSize" => 16 },
#			{ "offset" => 66,"name" => "systemtime","bitSize" => 16 },
 			]},      
	"7722" => {"name" => "DeltaSolE_WMZ", "cmd" => "0100", "fields" => [ 	
			{ "offset" =>  0,"name" => "T10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "T9","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "volumeflow","bitSize" => 15,"unit" => "l/h" },
			{ "offset" =>  6,"name" => "heatquantity1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  8,"name" => "heatquantity2","bitSize" => 16,"unit" => "kWh" },
			{ "offset" =>  10,"name" => "heatquantity3","bitSize" => 16,"unit" => "MWh" },
 			]},
	"7751" => {"name" => "DiemasolC", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "temperature_T01","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "temperature_T02","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "temperature_T03","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "temperature_T04","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "temperature_T05","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => "temperature_T06","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => "temperature_T07","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => "temperature_T08","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => "temperature_T09","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => "temperature_T10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 20,"name" => "temperature_T11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
  			{ "offset" => 22,"name" => "volumeflow", "bitSize" => 15,"factor" => 0.1,"unit" => "l/min"},
  			{ "offset" => 24,"name" => "speed_R01", "bitSize" => 8, "unit" => "%"},
  			{ "offset" => 25,"name" => "speed_R02", "bitSize" => 8, "unit" => "%"},
  			{ "offset" => 26,"name" => "speed_R03", "bitSize" => 8, "unit" => "%"},
  			{ "offset" => 27,"name" => "relais_R04", "bitPos" => 0, "bitSize" => 1 },
  			{ "offset" => 27,"name" => "relais_R05", "bitPos" => 1, "bitSize" => 1 },
  			{ "offset" => 27,"name" => "relais_R06", "bitPos" => 2, "bitSize" => 1 },
  			{ "offset" => 27,"name" => "relais_R07", "bitPos" => 3, "bitSize" => 1 },
  			{ "offset" => 27,"name" => "relais_R08", "bitPos" => 4, "bitSize" => 1 },
  			{ "offset" => 27,"name" => "relais_R09", "bitPos" => 5, "bitSize" => 1 },
  			{ "offset" => 28,"name" => "heatquantity", "bitSize" => 32, "factor" => 0.001,"unit" => "kWh" },
 			]},
	"7821" => {"name" => "Cosmo_Multi_Regler", "cmd" => "0100", "fields" => [
			{ "offset" => 0, "name" => "Temperatur_Sensor_1", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 2, "name" => "Temperatur_Sensor_2", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 4, "name" => "Temperatur_Sensor_3", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 6, "name" => "Temperatur_Sensor_4", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 8, "name" => "Temperatur_Sensor_5", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 10, "name" => "Temperatur_Sensor_6", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 12, "name" => "Temperatur_Sensor_7", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 14, "name" => "Temperatur_Sensor_8", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 16, "name" => "Temperatur_Sensor_9", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 18, "name" => "Temperatur_Sensor_10", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 20, "name" => "Einstrahlung_CS", "bitSize" => 15, "factor" => 1 },
			{ "offset" => 22, "name" => "Impulse_1_V40", "bitSize" => 16, "factor" => 1 },
			{ "offset" => 24, "name" => "Digital_Input", "bitSize" => 16, "factor" => 1 },
			{ "offset" => 26, "name" => "Drehzahl_Relais_1", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 27, "name" => "Drehzahl_Relais_2", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 28, "name" => "Drehzahl_Relais_3", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 29, "name" => "Drehzahl_Relais_4", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 30, "name" => "Drehzahl_Relais_5", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 31, "name" => "Drehzahl_Relais_6", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 32, "name" => "Drehzahl_Relais_7", "bitSize" => 7, "unit" => "%" },
			{ "offset" => 36, "name" => "Fehlermaske", "bitSize" => 16 },
			{ "offset" => 38, "name" => "Meldungen", "bitSize" => 16  },
			{ "offset" => 40, "name" => "System", "bitSize" => 7 },
			{ "offset" => 42, "name" => "Schema", "bitSize" => 16 },
			{ "offset" => 44, "name" => "Vorlauf_Soll_HK1_Modul_Sensor_18", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 46, "name" => "Status_HK1_Modul", "bitSize" => 16 },
			{ "offset" => 48, "name" => "Vorlauf_Soll_HK2_Modul_Sensor_25", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 50, "name" => "Status_HK2_Modul", "bitSize" => 16},
			{ "offset" => 52, "name" => "Vorlauf_Soll_HK3_Modul_Sensor_32", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 54, "name" => "Status_HK3_Modul", "bitSize" => 16 },
			{ "offset" => 56, "name" => "Vorlauf_Soll_Heizkreis_Sensor_11", "bitSize" => 15, "factor" => 0.1, "unit" => "°C" },
			{ "offset" => 58, "name" => "Status_Heizkreis", "bitSize" => 16 },
			{ "offset" => 62, "name" => "Systemzeit", "bitSize" => 15, "timeRef" => 1 },
			{ "offset" => 64, "name" => "Jahr", "bitSize" => 15, "factor" => 1 },
			{ "offset" => 66, "name" => "Monat", "bitSize" => 7, "factor" => 1 },
			{ "offset" => 67, "name" => "Tag", "bitSize" => 7, "factor" => 1 },
			]},
  	"7822" => {"name" => "Cosmo_Multi_WMZ", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "Temperatur_Vorlauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "Temperatur_Ruecklauf","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "Durchfluss_Sensor_8","bitSize" => 15,"unit" => "l/h" },
			{ "offset" =>  6,"name" => "heatquantity1","bitSize" => 16,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  8,"name" => "heatquantity2","bitSize" => 16,"factor" => 1000,"unit" => "kWh" },
			{ "offset" =>  10,"name" => "heatquantity3","bitSize" => 16,"factor" => 1000000,"unit" => "MWh" },
			]},
	"7E11" => {"name" => "DeltaSol_MX_Regler", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "Temperatur_1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "Temperatur_2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "Temperatur_3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "Temperatur_4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "Temperatur_5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 10,"name" => "Temperatur_6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 12,"name" => "Temperatur_7","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 14,"name" => "Temperatur_8","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 16,"name" => "Temperatur_9","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 18,"name" => "Temperatur_10","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 20,"name" => "Temperatur_11","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 22,"name" => "Temperatur_12","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 24,"name" => "Temperatur_13","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 26,"name" => "Temperatur_14","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 28,"name" => "Temperatur_15","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 30,"name" => "Temperatur_16","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 32,"name" => "Temperatur_17","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 34,"name" => "Temperatur_18","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 36,"name" => "Temperatur_19","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 38,"name" => "Temperatur_20","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" => 40,"name" => "Volumenstrom_13","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 44,"name" => "Volumenstrom_14","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 48,"name" => "Volumenstrom_15","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 52,"name" => "Volumenstrom_17","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 56,"name" => "Volumenstrom_18","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 60,"name" => "Volumenstrom_19","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 64,"name" => "Volumenstrom_20","bitSize" => 31,"factor" => 1,"unit" => "l/h" },
			{ "offset" => 68,"name" => "Drucksensor_17","bitSize" => 15,"factor" => 0.01,"unit" => "bar" },
			{ "offset" => 70,"name" => "Drucksensor_18","bitSize" => 15,"factor" => 0.01,"unit" => "bar" },
			{ "offset" => 72,"name" => "Drucksensor_19","bitSize" => 15,"factor" => 0.01,"unit" => "bar" },
			{ "offset" => 74,"name" => "Drucksensor_20","bitSize" => 15,"factor" => 0.01,"unit" => "bar" },
			{ "offset" => 76,"name" => "Drehzahl_1","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 77,"name" => "Drehzahl_2","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 78,"name" => "Drehzahl_3","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 79,"name" => "Drehzahl_4","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 80,"name" => "Drehzahl_5","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 81,"name" => "Drehzahl_6","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 82,"name" => "Drehzahl_7","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 83,"name" => "Drehzahl_8","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 84,"name" => "Drehzahl_9","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 85,"name" => "Drehzahl_10","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 86,"name" => "Drehzahl_11","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 87,"name" => "Drehzahl_12","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 88,"name" => "Drehzahl_13","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 89,"name" => "Drehzahl_14","bitSize" => 8,"factor" => 1,"unit" => "%" },
			{ "offset" => 92,"name" => "Systemdatum","bitSize" => 31},
			{ "offset" => 96,"name" => "Fehlermaske","bitSize" => 31},
			]},
	"7E12" => {"name" => "DeltaSol_MX_Module", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "Temperatur_M1_S1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "Temperatur_M1_S2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  4,"name" => "Temperatur_M1_S3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  6,"name" => "Temperatur_M1_S4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  8,"name" => "Temperatur_M1_S5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  10,"name" => "Temperatur_M1_S6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  12,"name" => "Temperatur_M2_S1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  14,"name" => "Temperatur_M2_S2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  16,"name" => "Temperatur_M2_S3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  18,"name" => "Temperatur_M2_S4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  20,"name" => "Temperatur_M2_S5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  22,"name" => "Temperatur_M2_S6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  24,"name" => "Temperatur_M3_S1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  26,"name" => "Temperatur_M3_S2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  28,"name" => "Temperatur_M3_S3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  30,"name" => "Temperatur_M3_S4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  32,"name" => "Temperatur_M3_S5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  34,"name" => "Temperatur_M3_S6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  36,"name" => "Temperatur_M4_S1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  38,"name" => "Temperatur_M4_S2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  40,"name" => "Temperatur_M4_S3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  42,"name" => "Temperatur_M4_S4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  44,"name" => "Temperatur_M4_S5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  46,"name" => "Temperatur_M4_S6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  48,"name" => "Temperatur_M5_S1","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  50,"name" => "Temperatur_M5_S2","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  52,"name" => "Temperatur_M5_S3","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  54,"name" => "Temperatur_M5_S4","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  56,"name" => "Temperatur_M5_S5","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  58,"name" => "Temperatur_M5_S6","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			]},		
	"7E21" => {"name" => "DeltaSol_MX_Heizkreis", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "Vorlauf_Soll_Temperatur","bitSize" => 15,"factor" => 0.1,"unit" => "°C" },
			{ "offset" =>  2,"name" => "Betriebsstatus","bitSize" => 8},
			]},		
	"7E31" => {"name" => "DeltaSol_MX_WMZ", "cmd" => "0100", "fields" => [
			{ "offset" =>  0,"name" => "Waermemenge","bitSize" => 31,"factor" => 1,"unit" => "Wh" },
#      { "offset" =>  4,"name" => "Leistung","bitSize" => 31,"factor" => 1,"unit" => "W" },
			{ "offset" =>  8,"name" => "Waermemenge_heute","bitSize" => 31,"factor" => 1,"unit" => "Wh" },
			{ "offset" =>  12,"name" => "Waermemenge_Woche","bitSize" => 31,"factor" => 1,"unit" => "Wh" },
      			{ "offset" =>  16,"name" => "Gesamtvolumen","bitSize" => 31,"factor" => 1,"unit" => "Wh" },
			]},	
);


sub VBUSDEV_Initialize($)
{
	my ($hash) = @_;
 # require "$attr{global}{modpath}/FHEM/19_VBUSIF.pm";


	my @modellist;
	foreach my $model (keys %VBUS_devices){
		push @modellist,$VBUS_devices{$model}->{name};
	}
	# aa100051771000010a0c5100382204507e01270200571b016000057e35003822056b38223822054638220000012400000000007f42744a00007f0f513301006b0a050001016e, help me!

	# Consumer
	$hash->{Match}		= "^aa.*";
	$hash->{DefFn}		= "VBUSDEV_Define";
	$hash->{UndefFn}	= "VBUSDEV_Undefine";
	$hash->{ParseFn}	= "VBUSDEV_Parse";
	$hash->{AttrList}	= "IODev "
                      	."$readingFnAttributes"
	                    ." model:"  .join(",", sort @modellist);
	$hash->{AutoCreate}	= { "VBUSDEV.*" => { ATTR => "event-min-interval:.*:120 event-on-change-reading:.* verbose:5 ",FILTER => "%NAME"}
		};
}




sub VBUSDEV_Define($$)
{
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	my $iodev;
	my $i = 0;
	foreach my $param ( @args ) {
		if ($param =~ m/IODev=(.*)/) {
			$iodev = $1;
		splice( @args, $i, 1 );
		last;
		}
		$i++;
	}
  
	return "Usage: define <name> VBUSDEV <code>"  if(@args < 3);
  
   $hash->{CODE} = $args[2];
   $modules{VBUSDEV}{defptr}{ $args[2]} = $hash;
   $hash->{STATE} = "Defined";
      
   my $name= $hash->{NAME};
   return undef;

	#my ($name, $type, $code, $interval) = @args;

	#$hash->{STATE} = 'Initialized';
	#$hash->{CODE} = $code;

	#AssignIoPort($hash,$iodev) if (!$hash->{IODev});
	#if(defined($hash->{IODev}->{NAME})) {
	#	Log3 $hash, 3, "VBUSDEV_Define: $name: I/O device is " . $hash->{IODev}->{NAME};
	#} else {
	#	Log3 $hash, 1, "VBUSDEV_Define: $name: no I/O device";
	#}
	#$modules{VBUSDEV}{defptr}{$code} = $hash;
	#return undef;
  
  
}

sub VBUSDEV_Undefine($$)
{
	my ($hash,$arg) = @_;
	my $code = $hash->{CODE};
	$code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
	delete($modules{VBUSDEV}{defptr}{$code});
	return undef;
}

sub VBUSDEV_Parse($$) {
	my ($iodev, $msg, $local) = @_;
	my $ioName = $iodev->{NAME};


	my $dst_addr = substr($msg,4,2).substr($msg,2,2);
	my $src_addr = substr($msg,8,2).substr($msg,6,2);
	my $protoVersion = substr($msg,10,2);

	my $devtype = $VBUS_devices{$src_addr};
	my $hash = $modules{VBUSDEV}{defptr}{$src_addr};

	Log3 $iodev, 5, "VBUSDEV_Parse00: ioName: ".$ioName. " DST-ADR: " . $dst_addr . " SRC-ADR: " . $src_addr;;

	if ($dst_addr == "0000")
	{
		  Log3 $iodev, 5, "VBUSDEV_Parse01: Broadcast ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	}

	if ($dst_addr == "0010")
	{
			Log3 $iodev, 5, "VBUSDEV_Parse02: DFA       ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	}

	if ($dst_addr == "0015")
	{
			
	  Log3 $iodev, 5, "VBUSDEV_Parse03: Standard-Infos ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	  return "";
	}

	if ($dst_addr == "0020")
	{
			Log3 $iodev, 5, "VBUSDEV_Parse04: Computer       ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	}

	if ($dst_addr == "0040")
	{
			Log3 $iodev, 5, "VBUSDEV_Parse05: SD3 / GAx      ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	}

	if ($dst_addr == "0050")
	{
			Log3 $iodev, 5, "VBUSDEV_Parse06: DL2      ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	}

	 if ($dst_addr == "6521")
	{
			Log3 $iodev, 5, "VBUSDEV_Parse07: MSR65    ioName: ".$ioName. " DST-ADR: " . $dst_addr;
	  $dst_addr = "0010";
	  $src_addr = "6521";     
	}

	if ( defined $devtype->{dst_addr} ) {
		if ( $devtype->{dst_addr} ne $dst_addr ) {
			 Log3 $iodev, 5, "VBUSDEV_Parse10: $ioName : skip frame $devtype->{dst_addr} $dst_addr";
			return "";
		}
	}

	$hash = $modules{VBUSDEV}{defptr}{$src_addr};
	if(!$hash) {
		my $ret = "UNDEFINED VBUSDEV_$src_addr VBUSDEV $src_addr";
		Log3 $hash, 3, "VBUSDEV_Parse11: $ioName : $ret, please define it";
		DoTrigger("global", $ret);
		return "";
	}

	Log3 $iodev, 5, "VBUSDEV_Parse12: ".$ioName. " DST-ADR: " . $dst_addr . " SRC-ADR: " . $src_addr;


	foreach my $mod (keys %{$modules{VBUSDEV}{defptr}}) {
		my $hash = $modules{VBUSDEV}{defptr}{"$src_addr"};
		$attr{$hash->{NAME}}{model} = $devtype->{name};

		#Log3 $iodev, 5, "VBUSDEV_Parse200 : Command " . $command . " DevTyp: ".$devtype." Model: ".$mod." MSG: " . $payload;
		
		my $command = substr($msg,14,2).substr($msg,12,2);
		my $payload = substr($msg,20);

		Log3 $iodev, 5, "VBUSDEV_Parse20 : Command " . $command . " DevTyp: ".$devtype." Model: ".$mod." MSG: " . $payload;
		#Log3 $iodev, 5, "VBUSDEV_Parse20 : Command " . $command . " DevTyp: ".$devtype." Model: ".$mod;
		
		VBUSDEV_ParsePayload($hash, $devtype, $command, $payload);
		return $hash->{NAME};
	}

	return "";
}



sub VBUSDEV_ParsePayload($@) {
	my ($hash, $devtype, $cmd, $payload) = @_;
	my $name = $hash->{NAME};
  	my $code = $hash->{CODE};
	my $devname = $devtype->{name};
	#my $devname = $devtype->{code};

  	Log3 $hash, 4, "$name: VBUSDEV_ParsePayLoad1: Command: ".$cmd." Code " . $code . " DevTyp: ".$devname." Name: ".$name ;

#	return undef if ($cmd != $devtype->{cmd});
	Log3 $hash, 4, "$name: VBUSDEV_ParsePayload2: Dev: $devname CMD: $cmd  PayL: $payload";


	readingsBeginUpdate($hash);

	#my $fld = $hash->{READINGS}->{"model"};

	for my $field (@{$devtype->{fields}}) {
		my $fieldname = $field->{name};
		my $val;
		my $o = $field->{offset}*2;

		my $bitpos  = $field->{bitPos};
		my $bitsize = $field->{bitSize};

		if ($bitsize<=8) {
			$val = substr($payload, $o,2);
		} elsif ($bitsize<=16) {
			$val = substr($payload, $o+2,2).substr($payload, $o,2);
		} elsif ($bitsize<=32) {
			$val = substr($payload, $o+6,2).substr($payload, $o+4,2).substr($payload, $o+2,2).substr($payload, $o,2);
		}

		 #Log3 $hash, 4, "$name: VBUSDEV_ParsePayload3: code: " . $code ." : " . $fieldname . " = " . $val;

		#Aenderung: statt: $val = hex($val); um negative Werte anzuzeigen
		if ($bitsize == 15) {
			 $val = unpack('s', pack('S', hex($val)));
			 } else {
			 $val = hex($val);
		 }
		#Aenderung ende

		if ($val != 8888) {
			if (defined $bitpos) {
				$val = $val >> $bitpos;
				my $bitmask = ($bitsize == 32) ? 0xffffffff : (1 << $bitsize) - 1;
				$val = $val & $bitmask;
			}

			$val = $val * $field->{factor} if defined $field->{factor};

			if ($bitsize==1) {
				$val = ($val == 1) ? "on" : "off";
			}

			my $unit = $field->{unit};
			if (!$unit) {
				$unit = "";
			}
		# auf o,5 °C Runden
			elsif ($unit eq "°C") {
			 	$val =  ($val >= 0 ? ceil($val*2)/2 : floor($val*2)/2);
			}
		# Runden ende
			my $val2 = $val." ".$unit;
      
			my $fld = $hash->{READINGS}->{$fieldname};
			my $oldval = "";
			if ($fld) {
				$oldval = $fld->{VAL};
			}
			readingsBulkUpdate($hash,$fieldname,$val2); # if ($val ne $oldval);
		    #Log3 $hash, 4, "$name: VBUSDEV_ParsePayload4: code: " . $code ." : " . $fieldname . " = " . $val ." ".$unit;
			Log3 $hash, 4, "$name: VBUSDEV_ParsePayload4: code: " . $code ." : " . $fieldname . " = " . $val2;
     	}
	}
  
		# unklar was hier gemacht wird. Bei mir wird dauernd VBUSDEV_ParsePayload6: UNDEFINED Modul ausgelöst welches
		# das auslösen der Userreading verhindert. (readingsEndUpdate wird durch das return niemals aufgerufen)

			#$code = $hash->{CODE};
			#$code = $hash->{IODev}->{NAME} ."_". $code if( defined($hash->{IODev}->{NAME}) );
			#my $def = $modules{VBUSDEV}{defptr}{$hash->{NAME}.".".$code};
			#$def = $modules{VBUSDEV}{defptr}{$code} if(!$def);
			#Log3 $hash, 4, "$name VBUSDEV_ParsePayload5: $name ($code) $$devname";  
		  
		    
			#if(!$def) {
			#	Log3 $hash, 4, '$name VBUSDEV_ParsePayload6: UNDEFINED Modul ' . $code;
			#	return "UNDEFINED $name VBUSDEV $code";
			#}
		    
			#$hash = $def;
			#$name = $hash->{NAME};
			#$code = $hash->{CODE};    	
			#Log3 $hash, 4, "$name VBUSDEV_ParsePayload7: $name ($code) $devname)";  

	readingsEndUpdate($hash, 1);

	return undef;
}
1;

=pod
=item helper
=item summary    connects to the VBUSIF Dev and fetches data from specific model 
=item summary_DE verbindet sich mit einem VBUSIF Dev und holt Daten von einem spez. Modell
=begin html

<a name="VBUSDEV"></a>
<h3>VBUSDEV</h3>
<ul>

    RESOL-Adapter (USB oder LAN) Info:<br>
    <a href="http://www.resol.de/">http://www.resol.de/</a><br><br>
      
    Information <a href="http://hobbyelektronik.org/w/index.php/VBus-Decoder">  http://hobbyelektronik.org/w/index.php/VBus-Decoder/</a> 
    or github <a href="https://github.com/pejonp/vbus"> https://github.com/pejonp/vbus </a><br><br><br>


  <br />
  <a name="VBUSDEV_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; VBUSDEV &lt;id&gt; [&lt;interval&gt;]</code><br />
    <br />
    Connects to various RESOL VBus devices<br />
    Examples:
    <ul>
      <code>define VBUSDEV_7321 VBUSDEV 7321 </code><br />
    </ul>
  </ul><br />
  <a name="VBUSDEV_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>The readings are dependant of the model of the VBUS device.</li><br />
  </ul><br />
</ul><br />

=end html
=begin html_DE

<a name="VBUSDEV"></a>
<h3>VBUSDEV</h3>
<ul>
    Bei dem VBus handelt es sich um eine bidirektionale halbduplex Zweidrahtschnittstelle.<br><br>
    
    Notwendig ist dazu ein RESOL-Adapter (USB oder LAN), zu dem hier Informationen zu finden sind:<br>
    <a href="http://www.resol.de/">http://www.resol.de/</a><br><br>
      
    Weitere Informationen hierzu findet man unter <a href="http://hobbyelektronik.org/w/index.php/VBus-Decoder">  http://hobbyelektronik.org/w/index.php/VBus-Decoder/</a> 
    und auch auf github <a href="https://github.com/pejonp/vbus"> https://github.com/pejonp/vbus </a><br><br><br>

  <br />
  <a name="VBUSDEV_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; VBUSDEV &lt;id&gt; [&lt;interval&gt;]</code><br />
    <br />
    Definition eines RESOL VBus Geraetes. Wenn das Geraet schon in der Liste hinterlegt ist, wird es automatisch angelegt.<br />
    Beispiel:
    <ul>
      <code>define VBUSDEV_7321 VBUSDEV 7321 </code><br />
    </ul>
  </ul><br />
  <a name="VBUSDEV_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>The readings are dependant of the model of the VBUS device.</li><br />
  </ul><br />
  
</ul><br />

=end html_DE
=cut