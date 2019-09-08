#########################################################################
# $Id$ 
# fhem Modul für Vissmann API. Based on investigation of "thetrueavatar"
# (https://github.com/thetrueavatar/Viessmann-Api)
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
##############################################################################
#   Changelog:
#
#   2018-11-24		initial version
#	 2018-12-11		non-blocking
#                 Reading "status" in "state" umbenannt
#   2018-12-23    Neue Werte in der API werden unter ihrem JSON Name als Reading eingetragen
#                 Neue Readings:
#  					heating.boiler.sensors.temperature.commonSupply.status error
#  					heating.boiler.temperature.value	                      48.1
#  					heating.burner.modulation.value                        11
#  					heating.burner.statistics.hours                        933.336666666667
#  					heating.burner.statistics.starts                       2717
#  					heating.circuits.0.circulation.pump.status             on
#  					heating.dhw.charging.active                            0
#  					heating.dhw.pumps.circulation.schedule.active          1
#  					heating.dhw.pumps.circulation.schedule.entries         sun mode:on end:22:30 start:04:30 position:0, fri end:22:30 mode:on position:0 start:04:30,
#  					                                                       mon mode:on end:22:30 start:04:30 position:0, 
#  					                                                       wed start:04:30 position:0 end:22:30 mode:on, thu mode:on end:22:30 position:0 start:04:30, sat end:22:30 mode:on position:0 start:04:30,
#  					                                                       tue position:0 start:04:30 end:22:30 mode:on,
#  					heating.dhw.pumps.circulation.status                   on
#  					heating.dhw.pumps.primary.status                       off
#  					heating.dhw.sensors.temperature.outlet.status          error
#  					heating.dhw.temperature.main.value                     53 
#  2018-12-30     initial offical release
#                 remove special characters from readings
#                 some internal improvements suggested by CoolTux
#  2019-01-01     "disabled" implemented
#                 "set update implemented
#						renamed "WW-onTimeCharge_aktiv" into "WW-einmaliges_Aufladen_aktiv"
#						Attribute vitoconnect_raw_readings:0,1 " and  ."vitoconnect_actions_active:0,1 " implemented
#						"set clearReadings" implemented
#  2019-01-05		Passwort wird im KeyValue gespeichert statt im Klartext
#                 Action "oneTimeCharge" implemented
#  2019-01-14		installation, code and gw in den Internals unsichtbar gemacht
#                 Reading "counter" entfernt (ist weiterhin in Internals sichtbar)
#						Reading WW-einmaliges_Aufladen_active umbenannt in WW-einmaliges_Aufladen
#                 Befehle zum setzen von 
#                 		HK1-Betriebsart
#                 		HK2-Betriebsart
#                 		HK1-Solltemperatur_normal
#                 		HK2-Solltemperatur_normal
#                 		HK1-Solltemperatur_reduziert
#                 		HK2-Solltemperatur_reduziert
#                 		WW-einmaliges_Aufladen
#                 Bedienfehler (z.B. Ausführung einer Befehls für HK2, wenn die Hezung nur einen Heizkreis hat) 
#						führen zu einem "Bad Gateway" Fehlermeldung in Logfile
#						Achtung: Keine Prüfung ob Befehle sinnvoll und oder erlaubt sind! Nutzung auf eigene Gefahr!
# 2019-01-15	   Fehler bei der Befehlsausführung gefixt
# 2019-01-22      Klartext für Readings für HK3 und heating.dhw.charging.level.* hinzugefügt
#						set's für HK2 implementiert
#					   set für Slope und Shift implementiert
#						set WW-Haupttemperatur und WW-Solltemperatur implementiert 
#						set HK1-Solltemperatur_comfort_aktiv HK1-Solltemperatur_comfort implementiert
#						set  HK1-Solltemperatur_eco implementiert (set HK1-Solltemperatur_eco_aktiv scheint es nicht zu geben?!)
#						vor einem set vitoconnect update den alten Timer löschen
#						set vitoconnect logResponseOnce implementiert (eventuell werden zusätzliche perl Pakete benötigt?)
# 2019-01-26		Fehler, dass HK3 Readings auf HK2 gemappt wurden gefixt
# 2019-02-17		Readings für den Stromverbrauch (heating.power.consumption.*) und
#						  Raumtemperatur (heating.circuits.?.sensors.temperature.room.value) ergänzt
#						set-Befehle für HKs werden nur noch angezeigt, wenn der HK auch aktiv ist
#						Wiki aktualisiert
# 2019-02-27		stacktrace-Fehler (hoffentlich) behoben
#						Betriebsarten "heating" und "active" ergänzt
# 2019-03-02		Readings für heating.boiler.sensors.temperature.commonSupply.value und
#							heating.circuits.1.operating.modes.heating.active hinzugefügt
#						Typo fixed ("Brenner_Be-t-riebsstunden")
# 2019-03-29		neue Readings:
#							heating.circuits.1.operating.modes.dhwAndHeatingCooling.active 1
#							heating.circuits.1.operating.modes.normalStandby.active 0
#							heating.circuits.1.operating.programs.fixed.active 0
#							heating.compressor.active 0
#							heating.dhw.temperature.hysteresis.value 5
#							heating.dhw.temperature.temp2.value 60
#						Passwort wird bei "define" nur noch gesetzt, wenn noch kein Passwort gespeichert war
#                 Attribut "model" implementiert
# 2019-04-26		neue Readings für
#						heating.gas.consumption.dhw.unit kilowattHour
#						heating.gas.consumption.heating.unit kilowattHour
#						heating.power.consumption.unit kilowattHour
#						Typo in WW-Zirkulationspumpe_Zeitsteuerung_aktiv fixt
# 2019-06-01		neue Readings für 
#          			    heating.solar.power.production.day	3.984,3.797,5.8,5.5,6.771,5.77,5.441,9.477
#          			    heating.solar.power.production.month	
#          			    heating.solar.power.production.unit	kilowattHour
#          			    heating.solar.power.production.week	
#          			    heating.solar.power.production.year
#                     heating.circuits.X.name (wird im Moment noch nicht von der API gefüllt!)
#                 Format der "Schedule" Readings in JSON geändert
#						das Format von HKx-Urlaub_Start und _Ende ist jetzt YYYY-MM-TT. 
#                 	Wenn noch kein Urlaub aktiviert wurde, wird bei
#                    HKx-Urlaub_Start das Datum für _Ende auf den Folgetag gesetzt
#                    Dafür werden die Perl Module DateTime, Time:Piece und Time::Seconds
#                    benötigt (installieren mit apt install libdatetime-perl!)
# 
# 2019-08-11		Dokumentation aktualisiert
#						Das Reading 'stat' zeigt jetzt den "aggregatedStatus" an, der von der API geliefert wird
#									Bsp: "Offline", "WorksProperly"
#                 Readings werden nur noch aktualisiert (und ein entsprechendes Event erzeugt),
#                          wenn sich ihr Wert geändert hat. "state" wird immer aktualisiert.         
#						Reading für Solarunterstützung hinzugefügt:
#                          "heating.solar.active" 											=> "Solar_aktiv",	
#                          "heating.solar.pumps.circuit.status" 						=> "Solar_Pumpe_Status",	
#                          "heating.solar.rechargeSuppression.status" 				=> "Solar_Aufladeunterdrueckung_Status",	
#                          "heating.solar.sensors.power.status" 						=> "Solar_Sensor_Power_Status",	
#                          "heating.solar.sensors.power.value" 						=> "Solar_Sensor_Power",	
#                          "heating.solar.sensors.temperature.collector.status" 	=> "Solar_Sensor_Temperatur_Kollektor_Status",	
#                          "heating.solar.sensors.temperature.collector.value" 	=> "Solar_Sensor_Temperatur_Kollektor",	
#                          "heating.solar.sensors.temperature.dhw.status" 			=> "Solar_Sensor_Temperatur_WW_Status",
#                          "heating.solar.sensors.temperature.dhw.value" 			=> "Solar_Sensor_Temperatur_WW",	
#                          "heating.solar.statistics.hours" 						   => "Solar_Sensor_Statistik_Stunden"	
#						ErrorListChanges (Fehlereintraege_Historie und Fehlereintraege_aktive) werden jetzt im JSON
#                          JSON Format ausgegeben (z.B.: "{"new":[],"current":[],"gone":[]}")
#
# 2019-09-07		Readings werden wieder erzeugt auch wenn sich der Wert nicht ändert
#
#   ToDo:         timeout konfigurierbar machen
#						"set"s für Schedules zum Steuern der Heizung implementieren
#                 Nicht bei jedem Lesen neu einloggen (wenn möglich)
#                 Fehlerbehandlung verbessern
#						Attribute implementieren und dokumentieren 
#						"sinnvolle" Readings statt 1:1 aus der API übernommene
#                 mapping der Readings optional machen
#						Mehrsprachigkeit
#                 Auswerten der Reading in getCode usw.
#						devices/0 ? Was, wenn es mehrere Devices gibt?
#						vitoconnect_Set effizienter implementieren
#						nach einem set Befehl Readings aktualisieren, vorher alten Timer löschen
#						heating.circuits.0.operating.programs.holiday.changeEndDate action: end implementieren? 
#						set für:
#							heating.dhw.temperature.hysteresis.setHysteresis action: hysteresis und
#							heating.dhw.temperature.temp2.setTargetTemperature action: temperature implementieren
#


package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
use HttpUtils;
use Encode qw(decode encode);
use Data::Dumper;
use Path::Tiny;
use DateTime;
use Time::Piece;
use Time::Seconds;

my $client_id = '79742319e39245de5f91d15ff4cac2a8';
my $client_secret = '8ad97aceb92c5892e102b093c7c083fa';
my $authorizeURL = 'https://iam.viessmann.com/idp/v1/authorize';
# my $token_url = 'https://iam.viessmann.com/idp/v1/token';
my $apiURLBase = 'https://api.viessmann-platform.io';
my $general = '/general-management/installations?expanded=true&';
my $callback_uri = "vicare://oauth-callback/everest"; 

#my $RequestList2 = {
#    "heating.boiler.serial.value" 												=> "Kessel_Seriennummer"
#};

my $RequestList = {
    "heating.boiler.serial.value" 												=> "Kessel_Seriennummer",
    "heating.boiler.temperature.value"											=> "Kesseltemperatur_exact",
    "heating.boiler.sensors.temperature.commonSupply.status"			=> "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.commonSupply.value"				=> "Kessel_Common_Supply_Temperatur",
    "heating.boiler.sensors.temperature.main.status" 						=> "Kessel_Status",
    "heating.boiler.sensors.temperature.main.value" 						=> "Kesseltemperatur",
    
    "heating.burner.active" 														=> "Brenner_aktiv",
    "heating.burner.automatic.status" 											=> "Brenner_Status",
    "heating.burner.automatic.errorCode" 										=> "Brenner_Fehlercode",
    "heating.burner.current.power.value"                             => "Brenner_Leistung", 
    "heating.burner.modulation.value"                                => "Brenner_Modulation",
    "heating.burner.statistics.hours"                                => "Brenner_Betriebsstunden",
	 "heating.burner.statistics.starts" 									 	=> "Brenner_Starts",

    "heating.circuits.enabled" 													=> "Aktive_Heizkreise",
    "heating.circuits.0.active" 													=> "HK1-aktiv",
    "heating.circuits.0.circulation.pump.status"          				=> "HK1-Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active" 						=> "HK1-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries" 					=> "HK1-Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status" 							=> "HK1-Frostschutz_Status",
    "heating.circuits.0.heating.curve.shift" 								=> "HK1-Heizkurve-Niveau",
    "heating.circuits.0.heating.curve.slope" 								=> "HK1-Heizkurve-Steigung",
    "heating.circuits.0.heating.schedule.active" 							=> "HK1-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries" 							=> "HK1-Zeitsteuerung_Heizung",
    "heating.circuits.0.name" 						                  	=> "HK1-Name",
    "heating.circuits.0.operating.modes.active.value" 					=> "HK1-Betriebsart",
    "heating.circuits.0.operating.modes.dhw.active" 						=> "HK1-WW_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeating.active" 			=> "HK1-WW_und_Heizen_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeatingCooling.active" => "HK1-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active" 			=> "HK1-Solltemperatur_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active" 			=> "HK1-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.0.operating.modes.heating.active" 					=> "HK1-heizen_aktiv",
    "heating.circuits.0.operating.modes.normalStandby.active"			=> "HK1-Normal_Standby_aktiv",
    "heating.circuits.0.operating.modes.standby.active" 					=> "HK1-Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value" 				=> "HK1-Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active" 				=> "HK1-Solltemperatur_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.temperature" 		=> "HK1-Solltemperatur_comfort",
    "heating.circuits.0.operating.programs.eco.active" 					=> "HK1-Solltemperatur_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature" 			=> "HK1-Solltemperatur_eco",
    "heating.circuits.0.operating.programs.external.active" 			=> "HK1-External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature" 		=> "HK1-External_Temperatur",
    "heating.circuits.0.operating.programs.fixed.active"					=> "HK1-Fixed_aktiv",
    "heating.circuits.0.operating.programs.holiday.active" 				=> "HK1-Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start" 				=> "HK1-Urlaub_Start",
    "heating.circuits.0.operating.programs.holiday.end" 					=> "HK1-Urlaub_Ende",
    "heating.circuits.0.operating.programs.normal.active" 				=> "HK1-Solltemperatur_aktiv",
    "heating.circuits.0.operating.programs.normal.temperature" 		=> "HK1-Solltemperatur_normal",
    "heating.circuits.0.operating.programs.reduced.active"				=> "HK1-Solltemperatur_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.temperature" 		=> "HK1-Solltemperatur_reduziert",
    "heating.circuits.0.operating.programs.standby.active" 				=> "HK1-Standby_aktiv",
    "heating.circuits.0.sensors.temperature.room.status" 				=> "HK1-Raum_Status",
    "heating.circuits.0.sensors.temperature.room.value"	 				=> "HK1-Raum_Temperatur",
    "heating.circuits.0.sensors.temperature.supply.status"				=> "HK1-Vorlauftemperatur_aktiv",
    "heating.circuits.0.sensors.temperature.supply.value" 				=> "HK1-Vorlauftemperatur",

    "heating.circuits.1.active" 													=> "HK2-aktiv",
    "heating.circuits.1.circulation.pump.status"                     => "HK2-Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active" 						=> "HK2-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries" 					=> "HK2-Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status" 							=> "HK2-Frostschutz_Status",
    "heating.circuits.1.heating.curve.shift" 								=> "HK2-Heizkurve-Niveau",
    "heating.circuits.1.heating.curve.slope" 								=> "HK2-Heizkurve-Steigung",
    "heating.circuits.1.heating.schedule.active" 							=> "HK2-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries" 							=> "HK2-Zeitsteuerung_Heizung",
    "heating.circuits.1.name" 						                  	=> "HK2-Name",
    "heating.circuits.1.operating.modes.active.value" 					=> "HK2-Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active" 						=> "HK2-WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active" 			=> "HK2-WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeatingCooling.active" => "HK2-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" 			=> "HK2-Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" 			=> "HK2-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.heating.active" 					=> "HK2-heizen_aktiv",
    "heating.circuits.1.operating.modes.normalStandby.active"			=> "HK2-Normal_Standby_aktiv",
    "heating.circuits.1.operating.modes.standby.active" 					=> "HK2-Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" 				=> "HK2-Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" 				=> "HK2-Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.temperature" 		=> "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" 					=> "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" 			=> "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" 			=> "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" 		=> "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.fixed.active"					=> "HK2-Fixed_aktiv",
    "heating.circuits.1.operating.programs.holiday.active" 				=> "HK2-Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" 				=> "HK2-Urlaub_Start",
    "heating.circuits.1.operating.programs.holiday.end" 					=> "HK2-Urlaub_Ende",
    "heating.circuits.1.operating.programs.normal.active" 				=> "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.temperature" 		=> "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active"				=> "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.temperature" 		=> "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.standby.active" 				=> "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" 				=> "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.room.value"	 				=> "HK2-Raum_Temperatur",
    "heating.circuits.1.sensors.temperature.supply.status"				=> "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.value" 				=> "HK2-Vorlauftemperatur",

    "heating.circuits.2.active" 													=> "HK3-aktiv",
    "heating.circuits.2.circulation.pump.status"                     => "HK3-Zirkulationspumpe",
    "heating.circuits.2.circulation.schedule.active" 						=> "HK3-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.2.circulation.schedule.entries" 					=> "HK3-Zeitsteuerung_Zirkulation",
    "heating.circuits.2.frostprotection.status" 							=> "HK3-Frostschutz_Status",
    "heating.circuits.2.heating.curve.shift" 								=> "HK3-Heizkurve-Niveau",
    "heating.circuits.2.heating.curve.slope" 								=> "HK3-Heizkurve-Steigung",
    "heating.circuits.2.heating.schedule.active" 							=> "HK3-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.2.heating.schedule.entries" 							=> "HK3-Zeitsteuerung_Heizung",
    "heating.circuits.2.name" 						                  	=> "HK3-Name",
    "heating.circuits.2.operating.modes.active.value" 					=> "HK3-Betriebsart",
    "heating.circuits.2.operating.modes.dhw.active" 						=> "HK3-WW_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeating.active" 			=> "HK3-WW_und_Heizen_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeatingCooling.active" => "HK3-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.2.operating.modes.forcedNormal.active" 			=> "HK3-Solltemperatur_erzwungen",
    "heating.circuits.2.operating.modes.forcedReduced.active" 			=> "HK3-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.2.operating.modes.heating.active" 					=> "HK3-heizen_aktiv",
    "heating.circuits.2.operating.modes.normalStandby.active"			=> "HK3-Normal_Standby_aktiv",
    "heating.circuits.2.operating.modes.standby.active" 					=> "HK3-Standby_aktiv",
    "heating.circuits.2.operating.programs.active.value" 				=> "HK3-Programmstatus",
    "heating.circuits.2.operating.programs.comfort.active" 				=> "HK3-Solltemperatur_comfort_aktiv",
    "heating.circuits.2.operating.programs.comfort.temperature" 		=> "HK3-Solltemperatur_comfort",
    "heating.circuits.2.operating.programs.eco.active" 					=> "HK3-Solltemperatur_eco_aktiv",
    "heating.circuits.2.operating.programs.eco.temperature" 			=> "HK3-Solltemperatur_eco",
    "heating.circuits.2.operating.programs.external.active" 			=> "HK3-External_aktiv",
    "heating.circuits.2.operating.programs.external.temperature" 		=> "HK3-External_Temperatur",
    "heating.circuits.2.operating.programs.fixed.active"					=> "HK3-Fixed_aktiv",
    "heating.circuits.2.operating.programs.holiday.active" 				=> "HK3-Urlaub_aktiv",
    "heating.circuits.2.operating.programs.holiday.start" 				=> "HK3-Urlaub_Start",
    "heating.circuits.2.operating.programs.holiday.end" 					=> "HK3-Urlaub_Ende",
    "heating.circuits.2.operating.programs.normal.active" 				=> "HK3-Solltemperatur_aktiv",
    "heating.circuits.2.operating.programs.normal.temperature" 		=> "HK3-Solltemperatur_normal",
    "heating.circuits.2.operating.programs.reduced.active"				=> "HK3-Solltemperatur_reduziert_aktiv",
    "heating.circuits.2.operating.programs.reduced.temperature" 		=> "HK3-Solltemperatur_reduziert",
    "heating.circuits.2.operating.programs.standby.active" 				=> "HK3-Standby_aktiv",
    "heating.circuits.2.sensors.temperature.room.status" 				=> "HK3-Raum_Status",
    "heating.circuits.2.sensors.temperature.room.value"	 				=> "HK3-Raum_Temperatur",
    "heating.circuits.2.sensors.temperature.supply.status"				=> "HK3-Vorlauftemperatur_aktiv",
    "heating.circuits.2.sensors.temperature.supply.value" 				=> "HK3-Vorlauftemperatur",
    
    "heating.compressor.active"													=> "Kompressor_aktiv",
    "heating.configuration.multiFamilyHouse.active" 						=> "Mehrfamilenhaus_aktiv",
    "heating.controller.serial.value" 											=> "Controller_Seriennummer",
    "heating.device.time.offset.value" 										=> "Device_Time_Offset",
    "heating.dhw.active" 															=> "WW-aktiv",
    "heating.dhw.charging.active"                                    => "WW-Aufladung",
    
    "heating.dhw.charging.level.bottom"                              => "WW-Speichertemperatur_unten",
    "heating.dhw.charging.level.middle"                              => "WW-Speichertemperatur_mitte",
    "heating.dhw.charging.level.top"                                 => "WW-Speichertemperatur_oben",
    "heating.dhw.charging.level.value"                               => "WW-Speicherladung",    
    
    "heating.dhw.oneTimeCharge.active" 										=> "WW-einmaliges_Aufladen",
  	 "heating.dhw.pumps.circulation.schedule.active"                  => "WW-Zirkulationspumpe_Zeitsteuerung_aktiv",
  	 "heating.dhw.pumps.circulation.schedule.entries"                 => "WW-Zirkulationspumpe_Zeitplan",
  	 "heating.dhw.pumps.circulation.status"                           => "WW-Zirkulationspumpe_Status",
  	 "heating.dhw.pumps.primary.status"                               => "WW-Zirkulationspumpe_primaer",
  	 "heating.dhw.sensors.temperature.outlet.status"                  => "WW-Sensoren_Auslauf_Status",
  	 "heating.dhw.sensors.temperature.outlet.value"                   => "WW-Sensoren_Auslauf_Wert",
  	 "heating.dhw.temperature.main.value"                             => "WW-Haupttemperatur",
    "heating.dhw.temperature.hysteresis.value"								=> "WW-Hysterese",
	 "heating.dhw.temperature.temp2.value"										=> "WW-Temperatur_2",
	 "heating.dhw.sensors.temperature.hotWaterStorage.status" 			=> "WW-Temperatur_aktiv",
    "heating.dhw.sensors.temperature.hotWaterStorage.value" 			=> "WW-Isttemperatur",
    "heating.dhw.temperature.value" 											=> "WW-Solltemperatur",
    "heating.dhw.schedule.active" 												=> "WW-zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries" 												=> "WW-Zeitplan",
    
    "heating.errors.active.entries" 											=> "Fehlereintraege_aktive",
    "heating.errors.history.entries" 											=> "Fehlereintraege_Historie",

    "heating.gas.consumption.dhw.day" 											=> "Gasverbrauch_WW/Tag",
    "heating.gas.consumption.dhw.week" 										=> "Gasverbrauch_WW/Woche",
    "heating.gas.consumption.dhw.month" 										=> "Gasverbrauch_WW/Monat",
    "heating.gas.consumption.dhw.year" 										=> "Gasverbrauch_WW/Jahr",
    "heating.gas.consumption.dhw.unit"											=> "Gasverbrauch_WW/Einheit",
    "heating.gas.consumption.heating.day" 									=> "Gasverbrauch_Heizung/Tag",
    "heating.gas.consumption.heating.week" 									=> "Gasverbrauch_Heizung/Woche",
    "heating.gas.consumption.heating.month" 									=> "Gasverbrauch_Heizung/Monat",
    "heating.gas.consumption.heating.year" 									=> "Gasverbrauch_Heizung/Jahr",
    "heating.gas.consumption.heating.unit"									=> "Gasverbrauch_Heizung/Einheit",
    "heating.power.consumption.day"												=> "Stromverbrauch/Tag",         
	 "heating.power.consumption.month"											=> "Stromverbrauch/Monat",     
	 "heating.power.consumption.week"											=> "Stromverbrauch/Woche",      
    "heating.power.consumption.year"											=> "Stromverbrauch/Jahr", 
	 "heating.power.consumption.unit"											=> "Stromverbrauch/Einheit",
    "heating.sensors.temperature.outside.status" 							=> "Aussen_Status",
    "heating.sensors.temperature.outside.statusWired" 					=> "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" 				=> "Aussen_StatusWireless",
    "heating.sensors.temperature.outside.value" 							=> "Aussentemperatur",
    
    "heating.service.timeBased.serviceDue" 									=> "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" 					=> "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" 			=> "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" 									=> "Service_Letzter",
    "heating.service.burnerBased.serviceDue" 								=> "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" 			=> "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" 	=> "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" 								=> "Service_Letzter_brennerbasiert",
    
    "heating.solar.active" 														=> "Solar_aktiv",	
    "heating.solar.pumps.circuit.status" 										=> "Solar_Pumpe_Status",	
    "heating.solar.rechargeSuppression.status" 								=> "Solar_Aufladeunterdrueckung_Status",	
    "heating.solar.sensors.power.status" 										=> "Solar_Sensor_Power_Status",	
    "heating.solar.sensors.power.value" 										=> "Solar_Sensor_Power",	
    "heating.solar.sensors.temperature.collector.status" 				=> "Solar_Sensor_Temperatur_Kollektor_Status",	
    "heating.solar.sensors.temperature.collector.value" 					=> "Solar_Sensor_Temperatur_Kollektor",	
    "heating.solar.sensors.temperature.dhw.status" 						=> "Solar_Sensor_Temperatur_WW_Status",
    "heating.solar.sensors.temperature.dhw.value" 							=> "Solar_Sensor_Temperatur_WW",	
    "heating.solar.statistics.hours" 						   				=> "Solar_Sensor_Statistik_Stunden",	
    
    "heating.solar.power.production.month"									=> "Solarproduktion/Monat",	
    "heating.solar.power.production.day"										=> "Solarproduktion/Tag",
    "heating.solar.power.production.unit"										=> "Solarproduktion/Einheit",
    "heating.solar.power.production.week"										=> "Solarproduktion/Woche",
    "heating.solar.power.production.year"										=> "Solarproduktion/Jahr"
};


sub vitoconnect_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}      = 'vitoconnect_Define';
    $hash->{UndefFn}    = 'vitoconnect_Undef';
    $hash->{SetFn}      = 'vitoconnect_Set';
    $hash->{GetFn}      = 'vitoconnect_Get';
    $hash->{AttrFn}     = 'vitoconnect_Attr';
    $hash->{ReadFn}     = 'vitoconnect_Read';
    $hash->{AttrList} =  "disable:0,1 "
    	."mapping:textField-long "
		."model:Vitodens_200-W_(B2HB),Vitodens_200-W_(B2KB),"
		."Vitotronic_200_(HO1),Vitotronic_200_(HO1A),Vitotronic_200_(HO1B),Vitotronic_200_(HO1D),Vitotronic_200_(HO2B),"
		."Vitotronic_200_RF_(HO1C),Vitotronic_200_RF_(HO1E),"
		."Vitotronic_200_(KO1B),Vitotronic_200_(KO2B),Vitotronic_200_(KW6),Vitotronic_200_(KW6A),Vitotronic_200_(KW6B),Vitotronic_200_(KW1),Vitotronic_200_(KW2),Vitotronic_200_(KW4),Vitotronic_200_(KW5),"
		."Vitotronic_300_(KW3),Vitotronic_200_(WO1A),Vitotronic_200_(WO1B),Vitotronic_200_(WO1C),"
		."Vitoligno_300-C,Vitoligno_200-S,Vitoligno_300-P_mit_Vitotronic_200_(FO1),Vitoligno_250-S,Vitoligno_300-S "
    ."vitoconnect_raw_readings:0,1 "
    ."vitoconnect_actions_active:0,1 "
    .$readingFnAttributes;
}

sub vitoconnect_Define($$) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @param = split('[ \t]+', $def);
    
    if(int(@param) < 5) { return "too few parameters: define <name> vitoconnect <user> <passwd> <intervall>"; }
    
    $hash->{user} = $param[2];
    $hash->{intervall} = $param[4];
    $hash->{counter} = 0;
    
    my $isiwebpasswd = vitoconnect_ReadKeyValue($hash, "passwd");
	 if ($isiwebpasswd eq ""){    
    	my $err = vitoconnect_StoreKeyValue($hash, "passwd", $param[3]);
    	return $err if ($err)
    } else {
		 Log3 $name, 3, "$name - Passwort war bereits gespeichert";   
    }
    
	 #my $value = AttrVal($name, "mapping", "");
	 #if ($value eq "") {
	 #	$Data::Dumper::Terse = 1; 
	 #	$Data::Dumper::Useqq = 1; 
	 #	#$Data::Dumper::Indent = 0;
	 #	my $cmd = "attr $name mapping ".Dumper($RequestList2);
	 #	Log3 $name, 3, "$name - Attribut mapping $cmd"; 
	 #	AnalyzeCommand($hash, $cmd);
	 #}   
    
	 InternalTimer(gettimeofday()+10, "vitoconnect_GetUpdate", $hash);   
    return undef;
}

sub vitoconnect_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    return undef;
}

sub vitoconnect_Get($@) {
	my ($hash, $name, $opt, @args) = @_;
	return "get $name needs at least one argument" unless (defined($opt));
	return undef;
}

sub vitoconnect_Set($@) {
	my ($hash, $name, $opt, @args) = @_;
	my $access_token = $hash->{".access_token"};
	my $installation = $hash->{".installation"};
	my $gw = $hash->{".gw"};
	
	return "set $name needs at least one argument" unless (defined($opt));
	if ($opt eq "update"){
		RemoveInternalTimer($hash); 
		vitoconnect_GetUpdate($hash); return undef;
	} elsif ($opt eq "logResponseOnce") {
		$hash->{".logResponseOnce"} = 1;
		RemoveInternalTimer($hash); 
		vitoconnect_GetUpdate($hash);
		return undef;	
	} elsif ($opt eq "clearReadings") {
		AnalyzeCommand ($hash, "deletereading $name .*");
		return undef;
	} elsif ($opt eq "password") {
		my $err = vitoconnect_StoreKeyValue($hash, "passwd", $args[0]); return $err if ($err);
		return undef;	
	} elsif ($opt eq "HK1-Heizkurve-Niveau") {
		my $slope = ReadingsVal ($name, "HK1-Heizkurve-Steigung", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.heating.curve/setCurve",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"shift\":$args[0],\"slope\":$slope}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;
	} elsif ($opt eq "HK2-Heizkurve-Niveau") {
		my $slope = ReadingsVal ($name, "HK2-Heizkurve-Steigung", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.heating.curve/setCurve",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"shift\":$args[0],\"slope\":$slope}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Heizkurve-Niveau") {
		my $slope = ReadingsVal ($name, "HK3-Heizkurve-Steigung", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.heating.curve/setCurve",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"shift\":$args[0],\"slope\":$slope}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;		
	} elsif ($opt eq "HK1-Heizkurve-Steigung") {
		my $shift = ReadingsVal ($name, "HK1-Heizkurve-Niveau", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.heating.curve/setCurve",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"shift\":$shift,\"slope\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;
	} elsif ($opt eq "HK2-Heizkurve-Steigung") {
		my $shift = ReadingsVal ($name, "HK2-Heizkurve-Niveau", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.heating.curve/setCurve",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"shift\":$shift,\"slope\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;		
	} elsif ($opt eq "HK3-Heizkurve-Steigung") {
		my $shift = ReadingsVal ($name, "HK3-Heizkurve-Niveau", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.heating.curve/setCurve",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"shift\":$shift,\"slope\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;		
	} elsif ($opt eq "HK1-Urlaub_Start") {
		my $end = ReadingsVal ($name, "HK1-Urlaub_Ende", undef);
		if ($end eq ""){my $t = Time::Piece->strptime($args[0], "%Y-%m-%d"); $t += ONE_DAY; $end = $t->strftime("%Y-%m-%d");}
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.holiday/schedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK2-Urlaub_Start") {
		my $end = ReadingsVal ($name, "HK2-Urlaub_Ende", undef);
		if ($end eq ""){my $t = Time::Piece->strptime($args[0], "%Y-%m-%d"); $t += ONE_DAY; $end = $t->strftime("%Y-%m-%d");}
      vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.holiday/schedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Urlaub_Start") {
		my $end = ReadingsVal ($name, "HK3-Urlaub_Ende", undef);
		if ($end eq ""){my $t = Time::Piece->strptime($args[0], "%Y-%m-%d"); $t += ONE_DAY; $end = $t->strftime("%Y-%m-%d");}
	   vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.holiday/schedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK1-Urlaub_Ende") {
		my $start = ReadingsVal ($name, "HK1-Urlaub_Start", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.holiday/schedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK2-Urlaub_Ende") {
		my $start = ReadingsVal ($name, "HK2-Urlaub_Start", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.holiday/schedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Urlaub_Ende") {
		my $start = ReadingsVal ($name, "HK3-Urlaub_Start", undef);
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.holiday/schedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK1-Urlaub_unschedule") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.holiday/unschedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;		
	} elsif ($opt eq "HK2-Urlaub_unschedule") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.holiday/unschedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Urlaub_unschedule") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.holiday/unschedule",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      # Log3 $name, 1, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;			
	} elsif ($opt eq "HK1-Betriebsart") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.modes.active/setMode",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"mode\":\"$args[0]\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;
	} elsif ($opt eq "HK2-Betriebsart") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.modes.active/setMode",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"mode\":\"$args[0]\"}",
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;
	} elsif ($opt eq "HK3-Betriebsart") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.modes.active/setMode",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"mode\":\"$args[0]\"}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;
	} elsif ($opt eq "HK1-Solltemperatur_comfort_aktiv") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.comfort/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 3, "set $name $opt $args[0]"; }   
		return undef;	
	} elsif ($opt eq "HK2-Solltemperatur_comfort_aktiv") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.comfort/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 3, "set $name $opt $args[0]"; }   
		return undef;
	} elsif ($opt eq "HK3-Solltemperatur_comfort_aktiv") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.comfort/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 3, "set $name $opt $args[0]"; }   
		return undef;		
	} elsif ($opt eq "HK1-Solltemperatur_comfort") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.comfort/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "$name: Fehler während der Befehlsausführung: err= $err data= $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK2-Solltemperatur_comfort") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.comfort/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "$name: Fehler während der Befehlsausführung: err= $err data= $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Solltemperatur_comfort") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.comfort/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 3, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "$name: Fehler während der Befehlsausführung: err= $err data= $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;		
	} elsif ($opt eq "HK1-Solltemperatur_eco_aktiv") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.eco/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 3, "set $name $opt $args[0]"; }   
		return undef;
	} elsif ($opt eq "HK2-Solltemperatur_eco_aktiv") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.eco/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 3, "set $name $opt $args[0]"; }   
		return undef;
	} elsif ($opt eq "HK3-Solltemperatur_eco_aktiv") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.eco/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 3, "set $name $opt $args[0]"; }   
		return undef;
	} elsif ($opt eq "HK1-Solltemperatur_normal") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.normal/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 3, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) { Log3 $name, 1, "$name: Fehler während der Befehlsausführung: err= $err data= $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;
	} elsif ($opt eq "HK2-Solltemperatur_normal") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.normal/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			method     => "POST",
			timeout    => 10,
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 3, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Solltemperatur_normal") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.normal/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			method     => "POST",
			timeout    => 10,
			sslargs    => {SSL_verify_mode => 0},
      };
      #Log3 $name, 3, "$name: $param->{data}"; 
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne "" || defined($data)) {	Log3 $name, 1, "$name: Fehler während der Befehlsausführung: err= $err data= $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK1-Solltemperatur_reduziert") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.0.operating.programs.reduced/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK2-Solltemperatur_reduziert") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.1.operating.programs.reduced/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "HK3-Solltemperatur_reduziert") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.circuits.2.operating.programs.reduced/setTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"targetTemperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "WW-einmaliges_Aufladen") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.dhw.oneTimeCharge/$args[0]",
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => '{}',
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
   	};
   	(my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err  ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else { Log3 $name, 5, "set $name $opt $args[0]"; }   
		return undef;
	} elsif ($opt eq "WW-Zirkulationspumpe_Zeitplan") {
		return "not implemented";	
	} elsif ($opt eq "WW-ZeitplanDhwSchedule") {
		return "not implemented";	
	} elsif ($opt eq "WW-Haupttemperatur") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.dhw.temperature.main/setTargetTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"temperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	} elsif ($opt eq "WW-Solltemperatur") {
		vitoconnect_action($hash);
		my $param = {
			url        => "https://api.viessmann-platform.io/operational-data/v1/installations/$installation/gateways/$gw/devices/0/features/heating.dhw.temperature/setTargetTemperature", 
			hash       => $hash,
			header     => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
			data       => "{\"temperature\":$args[0]}",
			timeout    => 10,
			method     => "POST",
			sslargs    => {SSL_verify_mode => 0},
      };
      (my $err, my $data) = HttpUtils_BlockingGet($param);
  		if ($err ne ""|| defined($data)) { Log3 $name, 1, "set $name $opt $args[0]: Fehler während der Befehlsausführung: $err :: $data";
  		} else {	Log3 $name, 3, "set $name $opt $args[0]"; }
		return undef;	
	}
	my $val = "unknown value $opt, choose one of update:noArg clearReadings:noArg password logResponseOnce:noArg " .
				"WW-einmaliges_Aufladen:activate,deactivate " .
		# "WW-Zirkulationspumpe_Zeitplan " . Ist ein Schedule
		# "WW-Zeitplan " .                   Ist ein Schedule
		"WW-Haupttemperatur:slider,10,1,60 " .
		"WW-Solltemperatur:slider,10,1,60 ";

		if ( ReadingsVal($name, "HK1-aktiv", "0" ) eq "1" ) {
			$val .= "HK1-Heizkurve-Niveau:slider,-13,1,40 ".
				"HK1-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 ".
				"HK1-Urlaub_Start ".   #Start 2019-02-02T23:59:59.000Z und Ende 2019-02-16T00:00:00.000Z
				"HK1-Urlaub_Ende ".
				"HK1-Urlaub_unschedule:noArg ".
				"HK1-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal " .
				"HK1-Solltemperatur_comfort_aktiv:activate,deactivate " .
				"HK1-Solltemperatur_comfort:slider,4,1,37 " .
				"HK1-Solltemperatur_eco_aktiv:activate,deactivate " .
				# "HK1-Solltemperatur_eco:slider,?,?,? " . Warum gibt es das nicht?
				"HK1-Solltemperatur_normal:slider,3,1,37 " .
				"HK1-Solltemperatur_reduziert:slider,3,1,37 ";			 
		}
		if ( ReadingsVal($name, "HK2-aktiv", "0" ) eq "1" ) {
			$val .= "HK2-Heizkurve-Niveau:slider,-13,1,40 ".
				"HK2-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 ".
				"HK2-Urlaub_Start ".   #Start 2019-02-02T23:59:59.000Z und Ende 2019-02-16T00:00:00.000Z
				"HK2-Urlaub_Ende ".
				"HK2-Urlaub_unschedule:noArg ".
				"HK2-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal " .
				"HK2-Solltemperatur_comfort_aktiv:activate,deactivate " .
				"HK2-Solltemperatur_comfort:slider,4,1,37 " .
				"HK2-Solltemperatur_eco_aktiv:activate,deactivate " .
				# "HK2-Solltemperatur_eco:slider,?,?,? " . Warum gibt es das nicht?
				"HK2-Solltemperatur_normal:slider,3,1,37 " .
				"HK2-Solltemperatur_reduziert:slider,3,1,37 ";			 
		}
		
		if ( ReadingsVal($name, "HK3-aktiv", "0" ) eq "1" ) {
			$val .= "HK3-Heizkurve-Niveau:slider,-13,1,40 ".
				"HK3-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 ".
				"HK3-Urlaub_Start ".   #Start 2019-02-02T23:59:59.000Z und Ende 2019-02-16T00:00:00.000Z
				"HK3-Urlaub_Ende ".
				"HK3-Urlaub_unschedule:noArg ".
				"HK3-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal " .
				"HK3-Solltemperatur_comfort_aktiv:activate,deactivate " .
				"HK3-Solltemperatur_comfort:slider,4,1,37 " .
				"HK3-Solltemperatur_eco_aktiv:activate,deactivate " .
				# "HK3-Solltemperatur_eco:slider,?,?,? " . Warum gibt es das nicht?
				"HK3-Solltemperatur_normal:slider,3,1,37 " .
				"HK3-Solltemperatur_reduziert:slider,3,1,37 ";			 
		}
	
	return $val;
}	

sub vitoconnect_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
   	if($attr_name eq "vitoconnect_raw_readings") {
			if($attr_value !~ /^0|1$/) {
			   my $err = "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
			   Log 1, "$name: ".$err; return $err;
			}
		} elsif($attr_name eq "vitoconnect_actions_active") {
			if($attr_value !~ /^0|1$/) {
				my $err = "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
			   Log 1, "$name: ".$err; return $err;
			}
		} elsif($attr_name eq "mapping") {
			# $RequestList2 = "$attr_value";
		} elsif($attr_name eq "disable") {
		
		} elsif($attr_name eq "verbose") {
		
		} else {
		    # return "Unknown attr $attr_name";
		}
	}
	return undef;
}

# Subs
sub vitoconnect_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 4, "$name - GetUpdate called ...";
	if ( IsDisabled($name) ) { 
		Log3 $name, 4, "$name: device disabled";
		InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash); 
	} else {	vitoconnect_getCode($hash); } 	
	return undef;
}

sub vitoconnect_getCode($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $isiwebpasswd = vitoconnect_ReadKeyValue($hash, "passwd");
			        
   my $param = {
		url        => "$authorizeURL?client_id=$client_id&scope=openid&redirect_uri=$callback_uri&response_type=code",
		hash       => $hash,
		header     => "Content-Type: application/x-www-form-urlencoded",
		ignoreredirects => 1,
      user		  => $hash->{user},
      pwd		  => $isiwebpasswd,
      sslargs    => {SSL_verify_mode => 0},
		timeout    => 10,
      method     => "POST",
      callback   => \&vitoconnect_getCodeCallback     
      };
   
   #Log3 $name, 4, "$name: user=$param->{user} passwd=$param->{pwd}";
   # Log3 $name, 5, Dumper($hash);
   HttpUtils_NonblockingGet($param);
   return undef;
}

sub vitoconnect_getCodeCallback ($) {
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	if ($err eq "") {
   	Log3 $name, 4, "$name - getCodeCallback went ok";
      Log3 $name, 5, "$name: Received response: $response_body";
      $response_body =~ /code=(.*)"/;
      $hash->{".code"} = $1;
      Log3 $name, 5, "$name: code = " . $hash->{".code"};
      if ($hash->{".code"}) {
      	$hash->{login} = "ok";
      } else {
      	$hash->{login} = "failure";
      }
   } else {
   	# Error code, type of error, error message
      Log3 $name, 1, "$name: An error occured: $err";
      $hash->{login} = "failure";
   }
	if ($hash->{login} eq "ok") {
		vitoconnect_getAccessToken($hash);
	} else {
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", "login failure" );
		readingsEndUpdate($hash, 1);
		Log3 $name, 1, "$name: Login failure";
		# neuen Timer starten in einem konfigurierten Interval.
		InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
	}
	return undef;
}

sub vitoconnect_getAccessToken($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $param = {
		url        => 'https://iam.viessmann.com/idp/v1/token',
		hash       => $hash,
		header     => "Content-Type: application/x-www-form-urlencoded;charset=utf-8",
		data       => "client_id=$client_id&client_secret=$client_secret&code=" . $hash->{".code"} ."&redirect_uri=$callback_uri&grant_type=authorization_code",
      sslargs    => {SSL_verify_mode => 0},
      method     => "POST",      
		timeout    => 10,
      callback   => \&vitoconnect_getAccessTokenCallback     
      };
	HttpUtils_NonblockingGet($param);
	return undef;
}

sub vitoconnect_getAccessTokenCallback($) {
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	if ($err eq "") {
   	Log3 $name, 4, "$name - getAccessTokenCallback went ok";
      Log3 $name, 5, "$name: Received response: $response_body\n";
      my $decode_json = eval{decode_json($response_body)};
      if($@) {
        Log3 $name, 1, "$name - JSON error while request: $@";
        return;
      }  
      my $access_token = $decode_json->{"access_token"};
      if ($access_token ne "") {
			$hash->{".access_token"} =  $access_token;          
         Log3 $name, 5, "$name: Access Token: $access_token";
         vitoconnect_getGw($hash);
      } else {
      	Log3 $name, 1, "$name: Access Token: undef";
      	InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
      } 
    } else {
    	Log3 $name, 1, "$name: getAccessToken: An error occured: $err";
      InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
    }
	return undef;
}

sub vitoconnect_getGw($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $access_token = $hash->{".access_token"};
	my $param = {
		url        => "$apiURLBase$general",
		hash       => $hash,
		header     => "Authorization: Bearer $access_token",
		timeout    => 10,
		sslargs    => {SSL_verify_mode => 0},
      callback   => \&vitoconnect_getGwCallback     
      };
	HttpUtils_NonblockingGet($param);
	return undef;
}

sub vitoconnect_getGwCallback($) {
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	if ($err eq "") {	
   	Log3 $name, 4, "$name - getGwCallback went ok";
      Log3 $name, 5, "$name: Received response: $response_body\n";

      my $decode_json = eval{decode_json($response_body)};
		if($@) { Log3 $name, 1, "$name - JSON error while request: $@"; return; } 

      if ($hash->{".logResponseOnce"}) {
      	my $dir = path("log"); 
			my $file = $dir->child("gw.json"); 
			my $file_handle = $file->openw_utf8();
			$file_handle->print(Dumper($decode_json));
		}
      
      my $aggregatedStatus = $decode_json->{entities}[0]->{properties}->{aggregatedStatus};
      Log3 $name, 5, "$name: aggregatedStatus: $aggregatedStatus";
      readingsSingleUpdate($hash, "state", $aggregatedStatus, 1);             
      
      my $installation = $decode_json->{entities}[0]->{properties}->{id};
      Log3 $name, 5, "$name: installation: $installation";
      $hash->{".installation"} = $installation;
      my $gw = $decode_json->{entities}[0]->{entities}[0]->{properties}->{serial};
      Log3 $name, 5, "$name gw: $gw";
      $hash->{".gw"} = $gw;
      vitoconnect_getResource($hash);
   } else {
   	Log3 $name, 1, "$name: An error occured: $err";
      InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
   }	
	return undef;
}

sub vitoconnect_getResource($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $access_token = $hash->{".access_token"};
	my $installation = $hash->{".installation"};
	my $gw = $hash->{".gw"};
	my $param = {
		url        => "https://api.viessmann-platform.io/operational-data/installations/$installation/gateways/$gw/devices/0/features/",
		hash       => $hash,
		header     => "Authorization: Bearer $access_token",
		timeout    => 10,
		sslargs    => {SSL_verify_mode => 0},
      callback   => \&vitoconnect_getResourceCallback     
      };
  	HttpUtils_NonblockingGet($param);
	return undef;
}

sub vitoconnect_getResourceCallback($) { 
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	my $file_handle2 = undef;

	readingsBeginUpdate($hash);		
	if ($err eq "") {	
		Log3 $name, 4, "$name - getResourceCallback went ok";
   	Log3 $name, 5, "Received response: $response_body\n";
   	my $decode_json = eval{decode_json($response_body)};
      if($@) { Log3 $name, 1, "$name - JSON error while request: $@";
        return; } 
      my $items = $decode_json;
      
 		###########################################      
      if ($hash->{".logResponseOnce"}) {
      	my $dir = path("log"); 
			my $file = $dir->child("entities.json"); 
			my $file_handle = $file->openw_utf8();
			#$file_handle->print(Dumper($items));
			$file_handle->print( Dumper(@{$items->{entities}} ));
			my $file2 = $dir->child("actions.json"); 
			$file_handle2 = $file2->openw_utf8();
		}
				
		###########################################
					
		for my $item( @{$items->{entities}} ) {
			my $FieldName = $item->{class}[0];
			Log3 $name, 5, "FieldName $FieldName";
			my %Properties = %{$item->{properties}};
			my @Keys = keys( %Properties );
			for my $Key ( @Keys ) {
				my $Reading = $RequestList->{$FieldName.".".$Key};
				if ( !defined($Reading) || AttrVal($name,'vitoconnect_raw_readings',undef) eq "1" )  {
					$Reading = $FieldName.".".$Key; }
				# Log3 $name, 5, "Property: $FieldName $Key";
				my $Type = $Properties{$Key}{type};
				my $Value = $Properties{$Key}{value};
				if ( $Type eq "string" ) {
					readingsBulkUpdate($hash, $Reading, $Value);
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				} elsif ( $Type eq "number" ) {
					readingsBulkUpdate($hash, $Reading, $Value);
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				} elsif ( $Type eq "array" ) {
					my $Array = join(",", @$Value);
					readingsBulkUpdate($hash, $Reading, $Array);
					Log3 $name, 5, "$FieldName".".$Key: $Array ($Type)";
				} elsif ( $Type eq "boolean" ) {
					readingsBulkUpdate($hash, $Reading, $Value);
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				} elsif ( $Type eq "Schedule" ) {
					# my %Entries = %$Value;
					# my @Days = keys (%Entries);
					# my $Result = "";
					# for my $Day ( @Days ){
					#	my $Entry = $Entries{$Day};
					#	$Result = "$Result $Day";
					#	for my $Element ( @$Entry ) {
					#		#$Result = "$Result $Element";
					#		while(my($k, $v) = each %$Element)  { $Result = "$Result $k:$v"; }
					#	}
					#}
					my $Result = encode_json($Value);
					readingsBulkUpdate($hash, $Reading, $Result);
					Log3 $name, 5, "$FieldName".".$Key: $Result ($Type)";
				} elsif ( $Type eq "ErrorListChanges" ) {
					# not implemented yet
					#readingsBulkUpdate($hash, $Reading, "ErrorListChanges");
					#Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
					
					my $Result = encode_json($Value);
					readingsBulkUpdate($hash, $Reading, $Result);
					Log3 $name, 5, "$FieldName".".$Key: $Result ($Type)";					
					
 				} else {
					readingsBulkUpdate($hash, $Reading, "Unknown: $Type");
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				}	
			}
			###########################################
			if (AttrVal($name,'vitoconnect_actions_active',undef) eq "1" )  {
				my @actions =  @{$item->{actions}};
				if (@actions) {
					if ($hash->{".logResponseOnce"}) { $file_handle2->print(Dumper(@actions)); }
					for my $action (@actions) {
						my @fields = @{$action->{fields}};
						my $Result = "action: ";
						for my $field (@fields) { $Result .= $field->{name}." ";	}
						readingsBulkUpdate($hash, $FieldName.".".$action->{"name"}, $Result);
					}	
				}
			}
			###########################################
		};
		
		$hash->{counter} = $hash->{counter} + 1;
		#readingsBulkUpdate($hash, "state", "ok");             
   } else {
		readingsBulkUpdate($hash, "state", "An error occured: $err");
      Log3 $name, 1, "$name - An error occured: $err";
   }
	readingsEndUpdate($hash, 1);
	InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
	$hash->{".logResponseOnce"} = 0;
	return undef;
}

sub vitoconnect_action($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $isiwebuserid = $hash->{user};
	my $isiwebpasswd = vitoconnect_ReadKeyValue($hash, "passwd"); 	
	my $err = "";
	my $response_body = "";
	my $code = "";	
	my $access_token = "";
	my $installation = "";
	my $gw = "";
	
	my $param = {
		url        => "$authorizeURL?client_id=$client_id&scope=openid&redirect_uri=$callback_uri&response_type=code",
		hash       => $hash,
		header     => "Content-Type: application/x-www-form-urlencoded",
		ignoreredirects => 1,
      user		  => $isiwebuserid,
      pwd		  => $isiwebpasswd,
      sslargs    => {SSL_verify_mode => 0},
		timeout    => 10,
      method     => "POST" };
   Log3 $name, 4, "$name: user=$param->{user} passwd=$param->{pwd}";
   ($err, $response_body) = HttpUtils_BlockingGet($param);
	if ($err eq "") {
   	$response_body =~ /code=(.*)"/;
      $code = $1;
      Log3 $name, 5, "$name - response_body: $response_body";
      Log3 $name, 5, "$name - code: $code";
   } else { Log3 $name, 1, "$name An error occured: $err"; }
   
   $param = {
		url        => 'https://iam.viessmann.com/idp/v1/token',
		hash       => $hash,
		header     => "Content-Type: application/x-www-form-urlencoded;charset=utf-8",
		data       => "client_id=$client_id&client_secret=$client_secret&code=$code&redirect_uri=$callback_uri&grant_type=authorization_code",
      sslargs    => {SSL_verify_mode => 0},
 		timeout    => 10,
      method     => "POST" };
      
	($err, $response_body) = HttpUtils_BlockingGet($param);
	
	if ($err eq "") {
   	my $decode_json = eval{decode_json($response_body)};
      if($@) { Log3 $name, 1, "$name - JSON error while request: $@"; return; }  
      $access_token = $decode_json->{access_token}; 
      Log3 $name, 5, "$name - access_token: $access_token"; 
    } else { Log3 $name, 1, "$name: getAccessToken: An error occured: $err"; }
    
    $param = {
		url        => "$apiURLBase$general",
		hash       => $hash,
		header     => "Authorization: Bearer $access_token",
		timeout    => 10,
		sslargs    => {SSL_verify_mode => 0}    
      };
	($err, $response_body) = HttpUtils_BlockingGet($param);
   if ($err eq "") {
		Log3 $name, 5, "$name - action (installation and gw): $response_body";   	
      my $decode_json = eval{decode_json($response_body)};
      if($@) { Log3 $name, 1, "$name - JSON error while request: $@"; return; } 
      $installation = $decode_json->{entities}[0]->{properties}->{id};
      $gw = $decode_json->{entities}[0]->{entities}[0]->{properties}->{serial};
      Log3 $name, 4, "$name: installation: $installation :: gw: $gw"
   } else { Log3 $name, 1, "$name: An error occured: $err"; }	
   
	   
    
	return undef;
}


sub vitoconnect_StoreKeyValue($$$) {
###################################################
# checks and stores obfuscated keys like passwords 
# based on / copied from FRITZBOX_storePassword
    my ($hash, $kName, $value) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;    
    my $enc   = "";
    
    if(eval "use Digest::MD5;1") {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }    
    for my $char (split //, $value) {
        my $encode=chop($key);
        $enc.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }    
    my $err = setKeyValue($index, $enc);
    return "error while saving the value - $err" if(defined($err));
    return undef;
} 
sub vitoconnect_ReadKeyValue($$) {
#####################################################
# reads obfuscated value 

   my ($hash, $kName) = @_;
   my $name = $hash->{NAME};

   my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
   my $key = getUniqueId().$index;

   my ($value, $err);

   Log3 $name, 5, "$name: ReadKeyValue tries to read value for $kName from file";
   ($err, $value) = getKeyValue($index);

   if ( defined($err) ) {
      Log3 $name, 1, "$name: ReadKeyValue is unable to read value from file: $err";
      return undef;
   }  
    
   if ( defined($value) ) {
      if ( eval "use Digest::MD5;1" ) {
         $key = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }
      my $dec = '';
      for my $char (map { pack('C', hex($_)) } ($value =~ /(..)/g)) {
         my $decode=chop($key);
         $dec.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
      return $dec;
   } else {
      Log3 $name, 1, "$name: ReadKeyValue could not find key $kName in file";
      return undef;
   }
   return;
} 

1;

=pod
=item device
=item summary support for Vissmann API
=item summary_DE Unterstützung für die Vissmann API
=begin html

<a name="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implements a device for the Vissmann API <a href="https://www.vissmann.de/de/vissmann-apps/vitoconnect.html">Vitoconnect100</a>
    based on investigation of <a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a><br>
    
	 You need the user and password from the ViCare App account.<br>
	 
	 For details see: <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (german)</a><br><br>
	 
	 vitoconnect needs the following libraries:
	 <ul>
	 <li>Path::Tiny</li>
	 <li>JSON</li>
	 <li>DateTime</li>
	 </ul>	 
	 	 
	 Use <code>sudo apt install libtypes-path-tiny-perl libjson-perl libdatetime-perl</code> or install the libraries via cpan. 
	 Otherwise you will get an error message "cannot load module vitoconnect".
	 
	 <br><br>
    <a name="vitoconnectdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code><br>
        It is a good idea to use a fake password here an set the correct one later because it is readable in the detail view of the device
        <br><br>
        Example:<br>
        <code>define vitoconnect vitoconnect user@mail.xx fakePassword 60</code><br>
        <code>set vitoconnect password correctPassword 60</code>
        <br><br>
                
    </ul>
    <br>
    
    <a name="vitoconnectset"></a>
    <b>Set</b><br>
    <ul>
    	<li><code>update</code><br>
        update readings immeadiatlely</li>
      <li><code>clearReadings</code><br>
        clear all readings immeadiatlely</li> 
      <li><code>password <passwd></code><br>
        store password in key store</li>
    	<li><code>logResponseOnce</code><br>
        dumps the json response of Vissmann server to entities.json, gw.json, actions.json in FHEM log directory</li>
        
      <li><code>HK1-Heizkurve-Niveau shift</code><br>
      set shift of heating curve</li>
      <li><code>HK1-Heizkurve-Steigung slope</code><br>
      set slope of heating curve</li>
      
		<li><code>HK1-Betriebsart standby,dhw,dhwAndHeating,forcedReduced,forcedNormal</code> <br>
		set HK1-Betriebsart to standby,dhw,dhwAndHeating,forcedReduced or forcedNormal</li>
		
		<li><code>HK1-Solltemperatur_comfort_aktiv activate,deactivate</code> <br>
       activate/deactivate comfort temperature</li>
		<li><code>HK1-Solltemperatur_comfort targetTemperature</code><br>
       set comfort target temperatur </li>
		<li><code>HK1-Solltemperatur_eco_aktiv activate,deactivate </code><br>
        activate/deactivate eco temperature</li>
		<li><code>HK1-Urlaub_Start start</code><br>
       set holiday start time <br>
       start has to look like this: 2019-02-02T23:59:59.000Z</li>
       <li><code>HK1-Urlaub_Ende end</code><br>
       set holiday end time <br>
       end has to look like this: 2019-02-16T00:00:00.000Z</li>
		<li><code>HK1-Urlaub_unschedule</code> <br>
       remove holiday start and end time </li>
       
		<li><code>HK1-Solltemperatur_normal targetTemperature</code><br>
       sets the normale target temperature where targetTemperature is an integer between 3 and 37</li>
		<li><code>HK1-Solltemperatur_reduziert targetTemperature</code><br>
       sets the reduced target temperature where targetTemperature is an integer between 3 and 37 </li>
       
		<li><code>WW-einmaliges_Aufladen activate,deactivate</code><br>
       activate or deactivate one time charge for hot water </li>
       
		<li><code>WW-Zirkulationspumpe_Zeitplan  schedule</code><br>
       not implemented </li>
		<li><code>WW-Zeitplan schedule</code> <br>
       not implemented </li>
		<li><code>WW-Haupttemperatur targetTemperature</code><br>
       targetTemperature is an integer between 10 and 60<br>
       sets hot water main temperature to targetTemperature </li>
		<li><code>WW-Solltemperatur targetTemperature</code><br>
       targetTemperature is an integer between 10 and 60<br>
       sets hot water temperature to targetTemperature </li>     
    </ul>
    <br>

    <a name="vitoconnectget"></a>
    <b>Get</b><br>
    <ul>
        nothing to get here 
    </ul>
    <br>
    
    <a name="vitoconnectattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
        the attr command.
        <br><br>
        Attributes:
        <ul>
				<li><i>disable</i>:<br>         
                stop communication with Vissmann server  
            </li>
            <li><i>verbose</i>:<br>         
                set the verbosity level  
            </li>
            <li><i>vitoconnect_raw_readings</i>:<br>         
                create readings with plain JSON names like 'heating.circuits.0.heating.curve.slope' instead of german identifiers  
            </li>
            <li><i>vitoconnect_actions_active</i>:<br>
            	create readings for actions e.g. 'heating.circuits.0.heating.curve.setCurve'
            </li>
        </ul>
    </ul>
    
    <a name="vitoconnectreadings"></a>
    <b>Readings</b>
    <br><br>
	 <i>vitoconnect</i> sets one reading for every value delivered by the API (depends on the type and the settings of your heater and the version of the API!).
	 Already known values will be mapped to clear names. Unknown values will added with their JSON path (e.g. "heating.burner.modulation.value").
	 Please report new readings to the module maintainer. A description of the known reading could be found <a href="https://wiki.fhem.de/wiki/Vitoconnect">here (german)</a>	    
    
</ul>

=end html

=cut
=cut
