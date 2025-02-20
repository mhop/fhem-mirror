#########################################################################
# $Id$
# fhem Modul für Viessmann API. Based on investigation of "thetrueavatar"
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

#   https://wiki.fhem.de/wiki/DevelopmentModuleAPI
#   https://forum.fhem.de/index.php/topic,93664.0.html
#   https://www.viessmann-community.com/t5/Announcements/Important-adjustment-in-IoT-features-Split-heating-circuits-and/td-p/281527
#   https://forum.fhem.de/index.php/topic,93664.msg1257651.html#msg1257651
#   https://www.viessmann-community.com/t5/Getting-started-programming-with/Syntax-for-setting-a-value/td-p/374222
#   https://forum.fhem.de/index.php?msg=1326376

sub vitoconnect_Initialize;             # Modul initialisieren und Namen zusätzlicher Funktionen bekannt geben
sub vitoconnect_Define;                 # wird beim 'define' eines Gerätes aufgerufen
sub vitoconnect_Undef;                  # wird beim Löschen einer Geräteinstanz aufgerufen
sub vitoconnect_Get;                    # bisher kein 'get' implementiert
sub vitoconnect_Set;                    # Implementierung set-Befehle
sub vitoconnect_Set_New;                # Implementierung set-Befehle New dynamisch auf raw readings
sub vitoconnect_Set_SVN;                # Implementierung set-Befehle SVN
sub vitoconnect_Set_Roger;              # Implementierung set-Befehle Roger
sub vitoconnect_Attr;                   # Attribute setzen/ändern/löschen

sub vitoconnect_GetUpdate;              # Abfrage aller Werte starten

sub vitoconnect_getCode;                # Werte für: Access-Token, Install-ID, Gateway anfragen
sub vitoconnect_getCodeCallback;        # Rückgabe: Access-Token, Install-ID, Gateway von vitoconnect_getCode Anfrage

sub vitoconnect_getAccessToken;         # Access & Refresh-Token holen
sub vitoconnect_getAccessTokenCallback; # Access & Refresh-Token speichern, Antwort auf: vitoconnect_getAccessToken

sub vitoconnect_getRefresh;             # neuen Access-Token anfragen
sub vitoconnect_getRefreshCallback;     # neuen Access-Token speichern

sub vitoconnect_getGw;                  # Abfrage Gateway-Serial
sub vitoconnect_getGwCallback;          # Gateway-Serial speichern, Anwort von Abfrage Gateway-Serial

sub vitoconnect_getInstallation;        # Abfrage Install-ID
sub vitoconnect_getInstallationCallback;# Install-ID speichern, Antwort von Abfrage Install-ID

sub vitoconnect_getDevice;              # Abfrage Device-ID
sub vitoconnect_getDeviceCallback;      # Device-ID speichern, Anwort von Abfrage Device-ID

sub vitoconnect_getFeatures;            # Abruf GW Features
sub vitoconnect_getFeaturesCallback;    # gw_features speichern

sub vitoconnect_errorHandling;          # Errors bearbeiten für alle Calls
sub vitoconnect_getResource;            # API call for all Gateways
sub vitoconnect_getResourceCallback;    # Get all API readings
sub vitoconnect_getPowerLast;           # Write the power reading of the full last day to the DB

sub vitoconnect_action;                 # Send call to API

sub vitoconnect_getErrorCode;           # Resolve Error code 

sub vitoconnect_StoreKeyValue;          # Werte verschlüsselt speichern
sub vitoconnect_ReadKeyValue;           # verschlüsselte Werte auslesen
sub vitoconnect_DeleteKeyValue;         # verschlüsselte Werte löschen


package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
#use JSON::XS qw( decode_json ); #Could be faster, but caused error for Schlimbo PERL WARNING: Prototype mismatch: sub main::decode_json ($;$$) vs ($) at /usr/local/lib/perl5/5.36.3/Exporter.pm line 63.
use HttpUtils;
use Encode qw(decode encode);
use Data::Dumper;
use Path::Tiny;
use DateTime;
use Time::Piece;
use Time::Seconds;

eval "use FHEM::Meta;1"                   or my $modMetaAbsent = 1;                  ## no critic 'eval'
use FHEM::SynoModules::SMUtils qw (
                                   moduleVersion
                                  );                                                 # Hilfsroutinen Modul

my %vNotesIntern = (
  "0.8.1"  => "20.02.2025  replace U+FFFD (unknown character with [VUC] see https://forum.fhem.de/index.php?msg=1334504, also fill reason in error case from extended payload",
  "0.8.0"  => "18.02.2025  enhanced error mapping now also language dependent, closing of file_handles, removed JSON::XS",
  "0.7.8"  => "17.02.2025  fixed undef warning thanks cnkru",
  "0.7.7"  => "17.02.2025  introduced clearMappedErrors",
  "0.7.6"  => "17.02.2025  removed usage of html libraries",
  "0.7.5"  => "16.02.2025  Get mapped error codes and store them in readings",
  "0.7.4"  => "16.02.2025  Removed Unknow attr vitoconnect, small bugfix DeleteKeyValue",
  "0.7.3"  => "16.02.2025  Write *.err file in case of error. Fixed DeleteKeyValue thanks Schlimbo",
  "0.7.2"  => "07.02.2025  Attr logging improved",
  "0.7.1"  => "07.02.2025  Code cleanups",
  "0.7.0"  => "06.02.2025  vitoconnect_installationID checked now for at least length 2, see https://forum.fhem.de/index.php?msg=1333072, error handling when setting attributs automatic introduced",
  "0.6.3"  => "04.02.2025  Small bug fixes, removed warnings",
  "0.6.2"  => "28.01.2025  Very small bugfixes ",
  "0.6.1"  => "28.01.2025  Rework of module documentation",
  "0.6.0"  => "23.01.2025  Total rebuild of initialization and gw handling. In case of more than one installation or gw you have to set it via".
                          "selectDevice in the set of the device. The attributes vitoconnect_serial and vitoconnect_installationID will be populated".
                          "handling of getting installation and serial changed. StoredValues are now deleted. Other fixes and developments",
  "0.5.0"  => "02.01.2025  Added attribute installationID, in case you use two installations, see https://forum.fhem.de/index.php?msg=1329165",
  "0.4.2"  => "31.12.2024  Small fix for Vitoladens 300C, heating.circuits.0.operating.programs.comfort",
  "0.4.1"  => "30.12.2024  Bug fixes, fixed Releasenotes, changed debugging texts and messages in Set_New",
  "0.4.0"  => "28.12.2024  Fixed setNew to work again automatically in case of one serial in gateways,".
                           "for more than one serial you have to define the serial you want to use",
  "0.3.2"  => "27.12.2024  Set in case of activate and deactivate request the active value of the reading",
  "0.3.1"  => "19.12.2024  New attribute vitoconnect_disable_raw_readings",
  "0.3.0"  => "18.12.2024  Fix setter new for cases where more than one gateway is actively pulled in 2 devices.",
  "0.2.1"  => "16.12.2024  German and English texts in UI",
  "0.2.0"  => "14.12.2024  FVersion introduced, a bit of code beautifying".
                          "sort keys per reading to ensure power readings are in the right order, day before dayvalue",
  "0.1.1"  => "12.12.2024  In case of more than one Gateway only allow Set_New if serial is provided. ".
                          "Get Object and Hash in Array readings. E.g. device.messages.errors.raw. ".
                          "In case of expired token (every hour) do not do uncessary gateway calls, just get the new token. ".
                          "This will safe API calls and reduce the API overhead. ",
  "0.1.0"  => "12.12.2024  first release with Version. "
);

my $client_secret = "2e21faa1-db2c-4d0b-a10f-575fd372bc8c-575fd372bc8c";
my $callback_uri  = "http://localhost:4200/";
my $apiURL        = "https://api.viessmann.com/iot/v1/equipment/";
my $iotURL_V1     = "https://api.viessmann.com/iot/v1/equipment/";
my $iotURL_V2     = "https://api.viessmann.com/iot/v2/features/";
my $errorURL_V3   = "https://api.viessmann.com/service-documents/v3/error-database";

my $RequestListMapping; # Über das Attribut Mapping definierte Readings zum überschreiben der RequestList
my %translations;       # Über das Attribut translations definierte Readings zum überschreiben der RequestList


# Feste Readings, orignal Verhalten des Moduls, können über RequestListMapping oder translations überschrieben werden.
# letzte SVN Version vor meinen Änderungen am 2024-11-16 oder letzte Version von Roger vom 8. November (https://forum.fhem.de/index.php?msg=1292441)
my $RequestListSvn = {
    "heating.boiler.serial.value"      => "Kessel_Seriennummer",
    "heating.boiler.temperature.value" => "Kessel_Solltemperatur",
    "heating.boiler.sensors.temperature.commonSupply.status" =>
      "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.commonSupply.unit" =>
      "Kessel_Common_Supply_Temperatur/Einheit",
    "heating.boiler.sensors.temperature.commonSupply.value" =>
      "Kessel_Common_Supply_Temperatur",
    "heating.boiler.sensors.temperature.main.status" => "Kessel_Status",
    "heating.boiler.sensors.temperature.main.unit" =>
      "Kesseltemperatur/Einheit",
    "heating.boiler.sensors.temperature.main.value" => "Kesseltemperatur",
    "heating.boiler.temperature.unit" => "Kesseltemperatur/Einheit",

    "heating.burner.active"              => "Brenner_aktiv",
    "heating.burner.automatic.status"    => "Brenner_Status",
    "heating.burner.automatic.errorCode" => "Brenner_Fehlercode",
    "heating.burner.current.power.value" => "Brenner_Leistung",
    "heating.burner.modulation.value"    => "Brenner_Modulation",
    "heating.burner.statistics.hours"    => "Brenner_Betriebsstunden",
    "heating.burner.statistics.starts"   => "Brenner_Starts",

    "heating.burners.0.active"            => "Brenner_1_aktiv",
    "heating.burners.0.modulation.unit"   => "Brenner_1_Modulation/Einheit",
    "heating.burners.0.modulation.value"  => "Brenner_1_Modulation",
    "heating.burners.0.statistics.hours"  => "Brenner_1_Betriebsstunden",
    "heating.burners.0.statistics.starts" => "Brenner_1_Starts",

    "heating.circuits.enabled"                   => "Aktive_Heizkreise",
    "heating.circuits.0.active"                  => "HK1-aktiv",
    "heating.circuits.0.type"                    => "HK1-Typ",
    "heating.circuits.0.circulation.pump.status" => "HK1-Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active" =>
      "HK1-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries" =>
      "HK1-Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status" => "HK1-Frostschutz_Status",
    "heating.circuits.0.geofencing.active"      => "HK1-Geofencing",
    "heating.circuits.0.geofencing.status"      => "HK1-Geofencing_Status",
    "heating.circuits.0.heating.curve.shift"    => "HK1-Heizkurve-Niveau",
    "heating.circuits.0.heating.curve.slope"    => "HK1-Heizkurve-Steigung",
    "heating.circuits.0.heating.schedule.active" =>
      "HK1-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries" =>
      "HK1-Zeitsteuerung_Heizung",
    "heating.circuits.0.name"                         => "HK1-Name",
    "heating.circuits.0.operating.modes.active.value" => "HK1-Betriebsart",
    "heating.circuits.0.operating.modes.dhw.active"   => "HK1-WW_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeating.active" =>
      "HK1-WW_und_Heizen_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeatingCooling.active" =>
      "HK1-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active" =>
      "HK1-Solltemperatur_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active" =>
      "HK1-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.0.operating.modes.heating.active" => "HK1-heizen_aktiv",
    "heating.circuits.0.operating.modes.normalStandby.active" =>
      "HK1-Normal_Standby_aktiv",
    "heating.circuits.0.operating.modes.standby.active" => "HK1-Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value" =>
      "HK1-Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active" =>
      "HK1-Solltemperatur_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.demand" =>
      "HK1-Solltemperatur_comfort_Anforderung",
    "heating.circuits.0.operating.programs.comfort.temperature" =>
      "HK1-Solltemperatur_comfort",
    "heating.circuits.0.operating.programs.eco.active" =>
      "HK1-Solltemperatur_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature" =>
      "HK1-Solltemperatur_eco",
    "heating.circuits.0.operating.programs.external.active" =>
      "HK1-External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature" =>
      "HK1-External_Temperatur",
    "heating.circuits.0.operating.programs.fixed.active" => "HK1-Fixed_aktiv",
    "heating.circuits.0.operating.programs.forcedLastFromSchedule.active" =>
      "HK1-forcedLastFromSchedule_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.active" =>
      "HK1-HolidayAtHome_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.end" =>
      "HK1-HolidayAtHome_Ende",
    "heating.circuits.0.operating.programs.holidayAtHome.start" =>
      "HK1-HolidayAtHome_Start",
    "heating.circuits.0.operating.programs.holiday.active" =>
      "HK1-Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start" => "HK1-Urlaub_Start",
    "heating.circuits.0.operating.programs.holiday.end"   => "HK1-Urlaub_Ende",
    "heating.circuits.0.operating.programs.normal.active" =>
      "HK1-Solltemperatur_aktiv",
    "heating.circuits.0.operating.programs.normal.demand" =>
      "HK1-Solltemperatur_Anforderung",
    "heating.circuits.0.operating.programs.normal.temperature" =>
      "HK1-Solltemperatur_normal",
    "heating.circuits.0.operating.programs.reduced.active" =>
      "HK1-Solltemperatur_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.demand" =>
      "HK1-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.0.operating.programs.reduced.temperature" =>
      "HK1-Solltemperatur_reduziert",
    "heating.circuits.0.operating.programs.summerEco.active" =>
      "HK1-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.0.operating.programs.standby.active" =>
      "HK1-Standby_aktiv",
    "heating.circuits.0.zone.mode.active" => "HK1-ZoneMode_aktive",
    "heating.circuits.0.sensors.temperature.room.status" => "HK1-Raum_Status",
    "heating.circuits.0.sensors.temperature.room.value" =>
      "HK1-Raum_Temperatur",
    "heating.circuits.0.sensors.temperature.supply.status" =>
      "HK1-Vorlauftemperatur_aktiv",
    "heating.circuits.0.sensors.temperature.supply.unit" =>
      "HK1-Vorlauftemperatur/Einheit",
    "heating.circuits.0.sensors.temperature.supply.value" =>
      "HK1-Vorlauftemperatur",
    "heating.circuits.0.zone.mode.active" => "HK1-ZoneMode_aktive",

    "heating.circuits.1.active"                  => "HK2-aktiv",
    "heating.circuits.1.type"                    => "HK2-Typ",
    "heating.circuits.1.circulation.pump.status" => "HK2-Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active" =>
      "HK2-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries" =>
      "HK2-Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status" => "HK2-Frostschutz_Status",
    "heating.circuits.1.geofencing.active"      => "HK2-Geofencing",
    "heating.circuits.1.geofencing.status"      => "HK2-Geofencing_Status",
    "heating.circuits.1.heating.curve.shift"    => "HK2-Heizkurve-Niveau",
    "heating.circuits.1.heating.curve.slope"    => "HK2-Heizkurve-Steigung",
    "heating.circuits.1.heating.schedule.active" =>
      "HK2-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries" =>
      "HK2-Zeitsteuerung_Heizung",
    "heating.circuits.1.name"                         => "HK2-Name",
    "heating.circuits.1.operating.modes.active.value" => "HK2-Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active"   => "HK2-WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active" =>
      "HK2-WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeatingCooling.active" =>
      "HK2-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" =>
      "HK2-Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" =>
      "HK2-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.heating.active" => "HK2-heizen_aktiv",
    "heating.circuits.1.operating.modes.normalStandby.active" =>
      "HK2-Normal_Standby_aktiv",
    "heating.circuits.1.operating.modes.standby.active" => "HK2-Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" =>
      "HK2-Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" =>
      "HK2-Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.demand" =>
      "HK2-Solltemperatur_comfort_Anforderung",
    "heating.circuits.1.operating.programs.comfort.temperature" =>
      "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" =>
      "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" =>
      "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" =>
      "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" =>
      "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.fixed.active" => "HK2-Fixed_aktiv",
    "heating.circuits.1.operating.programs.forcedLastFromSchedule.active" =>
      "HK2-forcedLastFromSchedule_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.active" =>
      "HK2-HolidayAtHome_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.end" =>
      "HK2-HolidayAtHome_Ende",
    "heating.circuits.1.operating.programs.holidayAtHome.start" =>
      "HK2-HolidayAtHome_Start",
    "heating.circuits.1.operating.programs.holiday.active" =>
      "HK2-Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" => "HK2-Urlaub_Start",
    "heating.circuits.1.operating.programs.holiday.end"   => "HK2-Urlaub_Ende",
    "heating.circuits.1.operating.programs.normal.active" =>
      "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.demand" =>
      "HK2-Solltemperatur_Anforderung",
    "heating.circuits.1.operating.programs.normal.temperature" =>
      "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active" =>
      "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.demand" =>
      "HK2-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.1.operating.programs.reduced.temperature" =>
      "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.summerEco.active" =>
      "HK2-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.1.operating.programs.standby.active" =>
      "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" => "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.room.value" =>
      "HK2-Raum_Temperatur",
    "heating.circuits.1.sensors.temperature.supply.status" =>
      "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.unit" =>
      "HK2-Vorlauftemperatur/Einheit",
    "heating.circuits.1.sensors.temperature.supply.value" =>
      "HK2-Vorlauftemperatur",
    "heating.circuits.1.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.2.active"                  => "HK3-aktiv",
    "heating.circuits.2.type"                    => "HK3-Typ",
    "heating.circuits.2.circulation.pump.status" => "HK3-Zirkulationspumpe",
    "heating.circuits.2.circulation.schedule.active" =>
      "HK3-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.2.circulation.schedule.entries" =>
      "HK3-Zeitsteuerung_Zirkulation",
    "heating.circuits.2.frostprotection.status" => "HK3-Frostschutz_Status",
    "heating.circuits.2.geofencing.active"      => "HK3-Geofencing",
    "heating.circuits.2.geofencing.status"      => "HK3-Geofencing_Status",
    "heating.circuits.2.heating.curve.shift"    => "HK3-Heizkurve-Niveau",
    "heating.circuits.2.heating.curve.slope"    => "HK3-Heizkurve-Steigung",
    "heating.circuits.2.heating.schedule.active" =>
      "HK3-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.2.heating.schedule.entries" =>
      "HK3-Zeitsteuerung_Heizung",
    "heating.circuits.2.name"                         => "HK3-Name",
    "heating.circuits.2.operating.modes.active.value" => "HK3-Betriebsart",
    "heating.circuits.2.operating.modes.dhw.active"   => "HK3-WW_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeating.active" =>
      "HK3-WW_und_Heizen_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeatingCooling.active" =>
      "HK3-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.2.operating.modes.forcedNormal.active" =>
      "HK3-Solltemperatur_erzwungen",
    "heating.circuits.2.operating.modes.forcedReduced.active" =>
      "HK3-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.2.operating.modes.heating.active" => "HK3-heizen_aktiv",
    "heating.circuits.2.operating.modes.normalStandby.active" =>
      "HK3-Normal_Standby_aktiv",
    "heating.circuits.2.operating.modes.standby.active" => "HK3-Standby_aktiv",
    "heating.circuits.2.operating.programs.active.value" =>
      "HK3-Programmstatus",
    "heating.circuits.2.operating.programs.comfort.active" =>
      "HK3-Solltemperatur_comfort_aktiv",
    "heating.circuits.2.operating.programs.comfort.demand" =>
      "HK3-Solltemperatur_comfort_Anforderung",
    "heating.circuits.2.operating.programs.comfort.temperature" =>
      "HK3-Solltemperatur_comfort",
    "heating.circuits.2.operating.programs.eco.active" =>
      "HK3-Solltemperatur_eco_aktiv",
    "heating.circuits.2.operating.programs.eco.temperature" =>
      "HK3-Solltemperatur_eco",
    "heating.circuits.2.operating.programs.external.active" =>
      "HK3-External_aktiv",
    "heating.circuits.2.operating.programs.external.temperature" =>
      "HK3-External_Temperatur",
    "heating.circuits.2.operating.programs.fixed.active" => "HK3-Fixed_aktiv",
    "heating.circuits.2.operating.programs.forcedLastFromSchedule.active" =>
      "HK3-forcedLastFromSchedule_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.active" =>
      "HK3-HolidayAtHome_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.end" =>
      "HK3-HolidayAtHome_Ende",
    "heating.circuits.2.operating.programs.holidayAtHome.start" =>
      "HK3-HolidayAtHome_Start",
    "heating.circuits.2.operating.programs.holiday.active" =>
      "HK3-Urlaub_aktiv",
    "heating.circuits.2.operating.programs.holiday.start" => "HK3-Urlaub_Start",
    "heating.circuits.2.operating.programs.holiday.end"   => "HK3-Urlaub_Ende",
    "heating.circuits.2.operating.programs.normal.active" =>
      "HK3-Solltemperatur_aktiv",
    "heating.circuits.2.operating.programs.normal.demand" =>
      "HK3-Solltemperatur_Anforderung",
    "heating.circuits.2.operating.programs.normal.temperature" =>
      "HK3-Solltemperatur_normal",
    "heating.circuits.2.operating.programs.reduced.active" =>
      "HK3-Solltemperatur_reduziert_aktiv",
    "heating.circuits.2.operating.programs.reduced.demand" =>
      "HK3-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.2.operating.programs.reduced.temperature" =>
      "HK3-Solltemperatur_reduziert",
    "heating.circuits.2.operating.programs.summerEco.active" =>
      "HK3-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.2.operating.programs.standby.active" =>
      "HK3-Standby_aktiv",
    "heating.circuits.2.sensors.temperature.room.status" => "HK3-Raum_Status",
    "heating.circuits.2.sensors.temperature.room.value" =>
      "HK3-Raum_Temperatur",
    "heating.circuits.2.sensors.temperature.supply.status" =>
      "HK3-Vorlauftemperatur_aktiv",
    "heating.circuits.2.sensors.temperature.supply.unit" =>
      "HK3-Vorlauftemperatur/Einheit",
    "heating.circuits.2.sensors.temperature.supply.value" =>
      "HK3-Vorlauftemperatur",
    "heating.circuits.2.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.3.geofencing.active" => "HK4-Geofencing",
    "heating.circuits.3.geofencing.status" => "HK4-Geofencing_Status",
    "heating.circuits.3.operating.programs.summerEco.active" =>
      "HK4-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.3.zone.mode.active" => "HK4-ZoneMode_aktive",

    "heating.compressor.active"                     => "Kompressor_aktiv",
    "heating.configuration.multiFamilyHouse.active" => "Mehrfamilenhaus_aktiv",
    "heating.configuration.regulation.mode"         => "Regulationmode",
    "heating.controller.serial.value"  => "Controller_Seriennummer",
    "heating.device.time.offset.value" => "Device_Time_Offset",
    "heating.dhw.active"               => "WW-aktiv",
    "heating.dhw.status"               => "WW-Status",
    "heating.dhw.charging.active"      => "WW-Aufladung",

    "heating.dhw.charging.level.bottom" => "WW-Speichertemperatur_unten",
    "heating.dhw.charging.level.middle" => "WW-Speichertemperatur_mitte",
    "heating.dhw.charging.level.top"    => "WW-Speichertemperatur_oben",
    "heating.dhw.charging.level.value"  => "WW-Speicherladung",

    "heating.dhw.oneTimeCharge.active" => "WW-einmaliges_Aufladen",
    "heating.dhw.pumps.circulation.schedule.active" =>
      "WW-Zirkulationspumpe_Zeitsteuerung_aktiv",
    "heating.dhw.pumps.circulation.schedule.entries" =>
      "WW-Zirkulationspumpe_Zeitplan",
    "heating.dhw.pumps.circulation.status" => "WW-Zirkulationspumpe_Status",
    "heating.dhw.pumps.primary.status"     => "WW-Zirkulationspumpe_primaer",
    "heating.dhw.sensors.temperature.outlet.status" =>
      "WW-Sensoren_Auslauf_Status",
    "heating.dhw.sensors.temperature.outlet.unit" =>
      "WW-Sensoren_Auslauf_Wert/Einheit",
    "heating.dhw.sensors.temperature.outlet.value" =>
      "WW-Sensoren_Auslauf_Wert",
    "heating.dhw.temperature.main.value"       => "WW-Haupttemperatur",
    "heating.dhw.temperature.hysteresis.value" => "WW-Hysterese",
    "heating.dhw.temperature.temp2.value"      => "WW-Temperatur_2",
    "heating.dhw.sensors.temperature.hotWaterStorage.status" =>
      "WW-Temperatur_aktiv",
    "heating.dhw.sensors.temperature.hotWaterStorage.unit" =>
      "WW-Isttemperatur/Einheit",
    "heating.dhw.sensors.temperature.hotWaterStorage.value" =>
      "WW-Isttemperatur",
    "heating.dhw.temperature.value" => "WW-Solltemperatur",
    "heating.dhw.schedule.active"   => "WW-zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries"  => "WW-Zeitplan",

    "heating.errors.active.entries"  => "Fehlereintraege_aktive",
    "heating.errors.history.entries" => "Fehlereintraege_Historie",

    "heating.flue.sensors.temperature.main.status" => "Abgassensor_Status",
    "heating.flue.sensors.temperature.main.unit" =>
      "Abgassensor_Temperatur/Einheit",
    "heating.flue.sensors.temperature.main.value" => "Abgassensor_Temperatur",

    "heating.fuelCell.operating.modes.active.value" => "Brennstoffzelle_Mode",
    "heating.fuelCell.operating.modes.ecological.active" =>
      "Brennstoffzelle_Mode_Ecological",
    "heating.fuelCell.operating.modes.economical.active" =>
      "Brennstoffzelle_Mode_Economical",
    "heating.fuelCell.operating.modes.heatControlled.active" =>
      "Brennstoffzelle_wärmegesteuert",
    "heating.fuelCell.operating.modes.maintenance.active" =>
      "Brennstoffzelle_Wartung",
    "heating.fuelCell.operating.modes.standby.active" =>
      "Brennstoffzelle_Standby",
    "heating.fuelCell.operating.phase.value" => "Brennstoffzelle_Phase",
    "heating.fuelCell.power.production.day" =>
      "Brennstoffzelle_Stromproduktion/Tag",
    "heating.fuelCell.power.production.month" =>
      "Brennstoffzelle_Stromproduktion/Monat",
    "heating.fuelCell.power.production.unit" =>
      "Brennstoffzelle_Stromproduktion/Einheit",
    "heating.fuelCell.power.production.week" =>
      "Brennstoffzelle_Stromproduktion/Woche",
    "heating.fuelCell.power.production.year" =>
      "Brennstoffzelle_Stromproduktion/Jahr",
    "heating.fuelCell.sensors.temperature.return.status" =>
      "Brennstoffzelle_Temperatur_Ruecklauf_Status",
    "heating.fuelCell.sensors.temperature.return.unit" =>
      "Brennstoffzelle_Temperatur_Ruecklauf/Einheit",
    "heating.fuelCell.sensors.temperature.return.value" =>
      "Brennstoffzelle_Temperatur_Ruecklauf",
    "heating.fuelCell.sensors.temperature.supply.status" =>
      "Brennstoffzelle_Temperatur_Vorlauf_Status",
    "heating.fuelCell.sensors.temperature.supply.unit" =>
      "Brennstoffzelle_Temperatur_Vorlauf/Einheit",
    "heating.fuelCell.sensors.temperature.supply.value" =>
      "Brennstoffzelle_Temperatur_Vorlauf",
    "heating.fuelCell.statistics.availabilityRate" =>
      "Brennstoffzelle_Statistic_Verfügbarkeit",
    "heating.fuelCell.statistics.insertions" =>
      "Brennstoffzelle_Statistic_Einschub",
    "heating.fuelCell.statistics.operationHours" =>
      "Brennstoffzelle_Statistic_Bestriebsstunden",
    "heating.fuelCell.statistics.productionHours" =>
      "Brennstoffzelle_Statistic_Produktionsstunden",
    "heating.fuelCell.statistics.productionStarts" =>
      "Brennstoffzelle_Statistic_Produktionsstarts",

    "heating.gas.consumption.dhw.day"   => "Gasverbrauch_WW/Tag",
    "heating.gas.consumption.dhw.week"  => "Gasverbrauch_WW/Woche",
    "heating.gas.consumption.dhw.month" => "Gasverbrauch_WW/Monat",
    "heating.gas.consumption.dhw.year"  => "Gasverbrauch_WW/Jahr",
    "heating.gas.consumption.dhw.dayValueReadAt" =>
      "Gasverbrauch_WW/Tag_gelesen_am",
    "heating.gas.consumption.dhw.weekValueReadAt" =>
      "Gasverbrauch_WW/Woche_gelesen_am",
    "heating.gas.consumption.dhw.monthValueReadAt" =>
      "Gasverbrauch_WW/Monat_gelesen_am",
    "heating.gas.consumption.dhw.yearValueReadAt" =>
      "Gasverbrauch_WW/Jahr_gelesen_am",
    "heating.gas.consumption.dhw.unit" => "Gasverbrauch_WW/Einheit",

    "heating.gas.consumption.heating.day"   => "Gasverbrauch_Heizung/Tag",
    "heating.gas.consumption.heating.week"  => "Gasverbrauch_Heizung/Woche",
    "heating.gas.consumption.heating.month" => "Gasverbrauch_Heizung/Monat",
    "heating.gas.consumption.heating.year"  => "Gasverbrauch_Heizung/Jahr",
    "heating.gas.consumption.heating.dayValueReadAt" =>
      "Gasverbrauch_Heizung/Tag_gelesen_am",
    "heating.gas.consumption.heating.weekValueReadAt" =>
      "Gasverbrauch_Heizung/Woche_gelesen_am",
    "heating.gas.consumption.heating.monthValueReadAt" =>
      "Gasverbrauch_Heizung/Monat_gelesen_am",
    "heating.gas.consumption.heating.yearValueReadAt" =>
      "Gasverbrauch_Heizung/Jahr_gelesen_am",
    "heating.gas.consumption.heating.unit" => "Gasverbrauch_Heizung/Einheit",
    "heating.gas.consumption.total.day"    => "Gasverbrauch_Total/Tag",
    "heating.gas.consumption.total.month"  => "Gasverbrauch_Total/Monat",
    "heating.gas.consumption.total.unit"   => "Gasverbrauch_Total/Einheit",
    "heating.gas.consumption.total.week"   => "Gasverbrauch_Total/Woche",
    "heating.gas.consumption.total.year"   => "Gasverbrauch_Total/Jahr",
    "heating.gas.consumption.total.dayValueReadAt" =>
      "Gasverbrauch_Total/Tag_gelesen_am",
    "heating.gas.consumption.total.monthValueReadAt" =>
      "Gasverbrauch_Total/Woche_gelesen_am",
    "heating.gas.consumption.total.weekValueReadAt" =>
      "Gasverbrauch_Total/Woche_gelesen_am",
    "heating.gas.consumption.total.yearValueReadAt" =>
      "Gasverbrauch_Total/Jahr_gelesen_am",

    "heating.gas.consumption.fuelCell.day" =>
      "Gasverbrauch_Brennstoffzelle/Tag",
    "heating.gas.consumption.fuelCell.week" =>
      "Gasverbrauch_Brennstoffzelle/Woche",
    "heating.gas.consumption.fuelCell.month" =>
      "Gasverbrauch_Brennstoffzelle/Monat",
    "heating.gas.consumption.fuelCell.year" =>
      "Gasverbrauch_Brennstoffzelle/Jahr",
    "heating.gas.consumption.fuelCell.unit" =>
      "Gasverbrauch_Brennstoffzelle/Einheit",

    "heating.heat.production.day"   => "Wärmeproduktion/Tag",
    "heating.heat.production.month" => "Wärmeproduktion/Woche",
    "heating.heat.production.unit"  => "Wärmeproduktion/Einheit",
    "heating.heat.production.week"  => "Wärmeproduktion/Woche",
    "heating.heat.production.year"  => "Wärmeproduktion/Jahr",

    "heating.operating.programs.holiday.active" => "Urlaub_aktiv",
    "heating.operating.programs.holiday.end"    => "Urlaub_Ende",
    "heating.operating.programs.holiday.start"  => "Urlaub_Start",

    "heating.operating.programs.holidayAtHome.active" => "holidayAtHome_aktiv",
    "heating.operating.programs.holidayAtHome.end"    => "holidayAtHome_Ende",
    "heating.operating.programs.holidayAtHome.start"  => "holidayAtHome_Start",

    "heating.power.consumption.day"   => "Stromverbrauch/Tag",
    "heating.power.consumption.month" => "Stromverbrauch/Monat",
    "heating.power.consumption.week"  => "Stromverbrauch/Woche",
    "heating.power.consumption.year"  => "Stromverbrauch/Jahr",
    "heating.power.consumption.unit"  => "Stromverbrauch/Einheit",

    "heating.power.consumption.dhw.day"   => "Stromverbrauch_WW/Tag",
    "heating.power.consumption.dhw.month" => "Stromverbrauch_WW/Monat",
    "heating.power.consumption.dhw.week"  => "Stromverbrauch_WW/Woche",
    "heating.power.consumption.dhw.year"  => "Stromverbrauch_WW/Jahr",
    "heating.power.consumption.dhw.unit"  => "Stromverbrauch_WW/Einheit",

    "heating.power.consumption.heating.day"   => "Stromverbrauch_Heizung/Tag",
    "heating.power.consumption.heating.month" => "Stromverbrauch_Heizung/Monat",
    "heating.power.consumption.heating.week"  => "Stromverbrauch_Heizung/Woche",
    "heating.power.consumption.heating.year"  => "Stromverbrauch_Heizung/Jahr",
    "heating.power.consumption.heating.unit" =>
      "Stromverbrauch_Heizung/Einheit",

    "heating.power.consumption.total.day"   => "Stromverbrauch_Total/Tag",
    "heating.power.consumption.total.month" => "Stromverbrauch_Total/Monat",
    "heating.power.consumption.total.week"  => "Stromverbrauch_Total/Woche",
    "heating.power.consumption.total.year"  => "Stromverbrauch_Total/Jahr",
    "heating.power.consumption.total.dayValueReadAt" =>
      "Stromverbrauch_Total/Tag_gelesen_am",
    "heating.power.consumption.total.monthValueReadAt" =>
      "Stromverbrauch_Total/Monat_gelesen_am",
    "heating.power.consumption.total.weekValueReadAt" =>
      "Stromverbrauch_Total/Woche_gelesen_am",
    "heating.power.consumption.total.yearValueReadAt" =>
      "Stromverbrauch_Total/Jahr_gelesen_am",
    "heating.power.consumption.total.unit" => "Stromverbrauch_Total/Einheit",

    "heating.power.production.current.status" =>
      "Stromproduktion_aktueller_Status",
    "heating.power.production.current.value" => "Stromproduktion",

    "heating.power.production.demandCoverage.current.unit" =>
      "Stromproduktion_Bedarfsabdeckung/Einheit",
    "heating.power.production.demandCoverage.current.value" =>
      "Stromproduktion_Bedarfsabdeckung",
    "heating.power.production.demandCoverage.total.day" =>
      "Stromproduktion_Bedarfsabdeckung_total/Tag",
    "heating.power.production.demandCoverage.total.month" =>
      "Stromproduktion_Bedarfsabdeckung_total/Monat",
    "heating.power.production.demandCoverage.total.unit" =>
      "Stromproduktion_Bedarfsabdeckung_total/Einheit",
    "heating.power.production.demandCoverage.total.week" =>
      "Stromproduktion_Bedarfsabdeckung_total/Woche",
    "heating.power.production.demandCoverage.total.year" =>
      "Stromproduktion_Bedarfsabdeckung_total/Jahr",

    "heating.power.production.day"   => "Stromproduktion_Total/Tag",
    "heating.power.production.month" => "Stromproduktion_Total/Monat",
    "heating.power.production.productionCoverage.current.unit" =>
      "Stromproduktion_Produktionsabdeckung/Einheit",
    "heating.power.production.productionCoverage.current.value" =>
      "Stromproduktion_Produktionsabdeckung",
    "heating.power.production.productionCoverage.total.day" =>
      "Stromproduktion_Produktionsabdeckung_Total/Tag",
    "heating.power.production.productionCoverage.total.month" =>
      "Stromproduktion_Produktionsabdeckung_Total/Monat",
    "heating.power.production.productionCoverage.total.unit" =>
      "Stromproduktion_Produktionsabdeckung_Total/Einheit",
    "heating.power.production.productionCoverage.total.week" =>
      "Stromproduktion_Produktionsabdeckung_Total/Woche",
    "heating.power.production.productionCoverage.total.year" =>
      "Stromproduktion_Produktionsabdeckung_Total/Jahr",
    "heating.power.production.unit" => "Stromproduktion_Total/Einheit",
    "heating.power.production.week" => "Stromproduktion_Total/Woche",
    "heating.power.production.year" => "Stromproduktion_Total/Jahr",

    "heating.power.purchase.current.unit"  => "Stromkauf/Einheit",
    "heating.power.purchase.current.value" => "Stromkauf",
    "heating.power.sold.current.unit"      => "Stromverkauf/Einheit",
    "heating.power.sold.current.value"     => "Stromverkauf",
    "heating.power.sold.day"               => "Stromverkauf/Tag",
    "heating.power.sold.month"             => "Stromverkauf/Monat",
    "heating.power.sold.unit"              => "Stromverkauf/Einheit",
    "heating.power.sold.week"              => "Stromverkauf/Woche",
    "heating.power.sold.year"              => "Stromverkauf/Jahr",

    "heating.sensors.pressure.supply.status" => "Drucksensor_Vorlauf_Status",
    "heating.sensors.pressure.supply.unit"   => "Drucksensor_Vorlauf/Einheit",
    "heating.sensors.pressure.supply.value"  => "Drucksensor_Vorlauf",

    "heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
    "heating.sensors.power.output.value"  => "Sensor_Stromproduktion",

    "heating.sensors.temperature.outside.status"      => "Aussen_Status",
    "heating.sensors.temperature.outside.statusWired" => "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" =>
      "Aussen_StatusWireless",
    "heating.sensors.temperature.outside.unit"  => "Aussentemperatur/Einheit",
    "heating.sensors.temperature.outside.value" => "Aussentemperatur",

    "heating.service.timeBased.serviceDue" => "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" =>
      "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" =>
      "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" => "Service_Letzter",
    "heating.service.burnerBased.serviceDue" =>
      "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" =>
      "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" =>
      "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" =>
      "Service_Letzter_brennerbasiert",

    "heating.solar.active"               => "Solar_aktiv",
    "heating.solar.pumps.circuit.status" => "Solar_Pumpe_Status",
    "heating.solar.rechargeSuppression.status" =>
      "Solar_Aufladeunterdrueckung_Status",
    "heating.solar.sensors.power.status" => "Solar_Sensor_Power_Status",
    "heating.solar.sensors.power.value"  => "Solar_Sensor_Power",
    "heating.solar.sensors.temperature.collector.status" =>
      "Solar_Sensor_Temperatur_Kollektor_Status",
    "heating.solar.sensors.temperature.collector.value" =>
      "Solar_Sensor_Temperatur_Kollektor",
    "heating.solar.sensors.temperature.dhw.status" =>
      "Solar_Sensor_Temperatur_WW_Status",
    "heating.solar.sensors.temperature.dhw.value" =>
      "Solar_Sensor_Temperatur_WW",
    "heating.solar.statistics.hours" => "Solar_Sensor_Statistik_Stunden",

    "heating.solar.power.cumulativeProduced.value" =>
      "Solarproduktion_Gesamtertrag",
    "heating.solar.power.production.month" => "Solarproduktion/Monat",
    "heating.solar.power.production.day"   => "Solarproduktion/Tag",
    "heating.solar.power.production.unit"  => "Solarproduktion/Einheit",
    "heating.solar.power.production.week"  => "Solarproduktion/Woche",
    "heating.solar.power.production.year"  => "Solarproduktion/Jahr"
};

my $RequestListRoger = {
    "device.serial.value"                                       => "Seriennummer",
    "device.messages.errors.raw.entries"                        => "Fehlermeldungen",

    "heating.boiler.serial.value"                               => "Kessel_Seriennummer",
    "heating.boiler.temperature.value"                          => "Kessel_Solltemp__C",
    "heating.boiler.sensors.temperature.commonSupply.status"    => "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.commonSupply.unit"      => "Kessel_Common_Supply_Temp_Einheit",
    "heating.boiler.sensors.temperature.commonSupply.value"     => "Kessel_Common_Supply_Temp__C",
    "heating.boiler.sensors.temperature.main.status"            => "Kessel_Status",
    "heating.boiler.sensors.temperature.main.value"             => "Kessel_Temp__C",
    "heating.boiler.sensors.temperature.main.unit"              => "Kessel_Temp_Einheit",
    "heating.boiler.temperature.unit"                           => "Kesseltemp_Einheit",

    "heating.device.time.offset.value"                          => "Device_Time_Offset",
    "heating.sensors.temperature.outside.status"                => "Aussen_Status",
    "heating.sensors.temperature.outside.unit"                  => "Temp_aussen_Einheit",
    "heating.sensors.temperature.outside.value"                 => "Temp_aussen__C",

    "heating.burners.0.active"                                  => "Brenner_1_aktiv",
    "heating.burners.0.statistics.starts"                       => "Brenner_1_Starts",
    "heating.burners.0.statistics.hours"                        => "Brenner_1_Betriebsstunden__h",
    "heating.burners.0.modulation.value"                        => "Brenner_1_Modulation__Prz",
    "heating.burners.0.modulation.unit"                         => "Brenner_1_Modulation_Einheit",



    "heating.burner.active"                                     => "Brenner_aktiv",
    "heating.burner.automatic.status"                           => "Brenner_Status",
    "heating.burner.automatic.errorCode"                        => "Brenner_Fehlercode",
    "heating.burner.current.power.value"                        => "Brenner_Leistung",
    "heating.burner.modulation.value"                           => "Brenner_Modulation",
    "heating.burner.statistics.hours"                           => "Brenner_Betriebsstunden__h",
    "heating.burner.statistics.starts"                          => "Brenner_Starts",

    "heating.sensors.volumetricFlow.allengra.status"            => "Heiz_Volumenstrom_Status",
    "heating.sensors.volumetricFlow.allengra.value"             => "Heiz_Volumenstrom__l/h",

    "heating.circuits.enabled"                                  => "aktive_Heizkreise",
    "heating.circuits.0.name"                                   => "HK1_Name",
    "heating.circuits.0.operating.modes.active.value"           => "HK1_Betriebsart",
    "heating.circuits.0.active"                                 => "HK1_aktiv",
    "heating.circuits.0.type"                                   => "HK1_Typ",
    "heating.circuits.0.circulation.pump.status"                => "HK1_Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active"            => "HK1_Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries"           => "HK1_Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status"                 => "HK1_Frostschutz_Status",
    "heating.circuits.0.geofencing.active"                      => "HK1_Geofencing",
    "heating.circuits.0.geofencing.status"                      => "HK1_Geofencing_Status",
    "heating.circuits.0.heating.curve.shift"                    => "HK1_Heizkurve_Niveau",
    "heating.circuits.0.heating.curve.slope"                    => "HK1_Heizkurve_Steigung",
    "heating.circuits.0.heating.schedule.active"                => "HK1_Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries"               => "HK1_Zeitsteuerung_Heizung",

    "heating.circuits.0.operating.modes.dhwAndHeatingCooling.active"    => "HK1_WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active"            => "HK1_Soll_Temp_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active"           => "HK1_Reduzierte_Temp_erzwungen",
    "heating.circuits.0.operating.modes.heating.active"                 => "HK1_heizen_aktiv",
    "heating.circuits.0.operating.modes.normalStandby.active"           => "HK1_Normal_Standby_aktiv",
    "heating.circuits.0.operating.modes.standby.active"                 => "HK1_Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value"                => "HK1_Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active"              => "HK1_Soll_Temp_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.demand"              => "HK1_Soll_Temp_comfort_Anforderung",
    "heating.circuits.0.operating.programs.comfort.temperature"         => "HK1_Soll_Temp_comfort__C",
    "heating.circuits.0.operating.programs.eco.active"                  => "HK1_Soll_Temp_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature"             => "HK1_Soll_Temp_eco__C",
    "heating.circuits.0.operating.programs.external.active"             => "HK1_External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature"        => "HK1_External_Temp",
    "heating.circuits.0.operating.programs.fixed.active"                => "HK1_Fixed_aktiv",
    "heating.circuits.0.operating.programs.forcedLastFromSchedule.active"   => "HK1_forcedLastFromSchedule_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.active"        => "HK1_HolidayAtHome_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.end"           => "HK1_HolidayAtHome_Ende",
    "heating.circuits.0.operating.programs.holidayAtHome.start"         => "HK1_HolidayAtHome_Start",
    "heating.circuits.0.operating.programs.holiday.active"              => "HK1_Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start"               => "HK1_Urlaub_Start_Zeit",
    "heating.circuits.0.operating.programs.holiday.end"                 => "HK1_Urlaub_Ende_Zeit",
    "heating.circuits.0.operating.programs.normal.active"               => "HK1_Soll_Temp_aktiv",
    "heating.circuits.0.operating.programs.normal.demand"               => "HK1_Soll_Temp_Anforderung",
    "heating.circuits.0.operating.programs.normal.temperature"          => "HK1_Soll_Temp_normal",
    "heating.circuits.0.operating.programs.reduced.active"              => "HK1_Soll_Temp_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.demand"              => "HK1_Soll_Temp_reduziert_Anforderung",
    "heating.circuits.0.operating.programs.reduced.temperature"         => "HK1_Soll_Temp_reduziert",
    "heating.circuits.0.operating.programs.summerEco.active"            => "HK1_Soll_Temp_SummerEco_aktiv",
    "heating.circuits.0.operating.programs.standby.active"              => "HK1_Standby_aktiv",
    "heating.circuits.0.zone.mode.active"                               => "HK1_ZoneMode_aktive",
    "heating.circuits.0.sensors.temperature.room.status"                => "HK1_Raum_Status",
    "heating.circuits.0.sensors.temperature.room.value"                 => "HK1_Raum_Temp",
    "heating.circuits.0.sensors.temperature.supply.status"              => "HK1_Vorlauf_Temp_Status",
    "heating.circuits.0.sensors.temperature.supply.unit"                => "HK1_Vorlauf_Temp_Einheit",
    "heating.circuits.0.sensors.temperature.supply.value"               => "HK1_Vorlauf_Temp__C",
    "heating.circuits.0.zone.mode.active"                               => "HK1_ZoneMode_aktive",

    "heating.dhw.operating.modes.active.value"                  => "WW_Betriebsart",
    "heating.dhw.operating.modes.balanced.active"               => "WW_Betriebsart_balanced",
    "heating.dhw.operating.modes.off.active"                    => "WW_Betriebsart_off",
    "heating.dhw.temperature.main.value"                        => "WW_Temp_Soll__C",
    "heating.dhw.sensors.temperature.hotWaterStorage.value"     => "WW_Temp_Ist__C",
    "heating.dhw.sensors.temperature.hotWaterStorage.unit"      => "WW_Temp_Ist_Einheit",
    "heating.dhw.oneTimeCharge.active"                          => "WW_einmaliges_Aufladen",
    "heating.dhw.sensors.temperature.dhwCylinder.value"         => "WW_Temp__C",
    "heating.dhw.sensors.temperature.dhwCylinder.status"        => "WW_Temp_Status",
    "heating.dhw.hygiene.active"                                => "WW_Hygiene_laeft",
    "heating.dhw.hygiene.enabled"                               => "WW_Hygiene_enabled",
    "heating.dhw.hygiene.trigger.startHour"                     => "WW_Hygiene_Start__hh",
    "heating.dhw.hygiene.trigger.startMinute"                   => "WW_Hygiene_Start__mm",
    "heating.dhw.hygiene.trigger.weekdays"                      => "WW_Hygiene_Start__dd",
    "heating.dhw.temperature.hygiene.value"                     => "WW_Hygiene_Temp__C",

    "heating.dhw.pumps.circulation.schedule.active"             => "WW_Zirkulationspumpe_Zeitsteuerung_aktiv",
    "heating.dhw.pumps.circulation.schedule.entries"            => "WW_Zirkulationspumpe_Zeitplan",
    "heating.dhw.pumps.circulation.status"                      => "WW_Zirkulationspumpe_Status",
    "heating.dhw.pumps.primary.status"                          => "WW_Zirkulationspumpe_primaer",
    "heating.dhw.sensors.temperature.outlet.status"             => "WW_Sensoren_Auslauf_Status",
    "heating.dhw.sensors.temperature.outlet.unit"               => "WW_Sensoren_Auslauf_Wert_Einheit",
    "heating.dhw.sensors.temperature.outlet.value"              => "WW_Sensoren_Auslauf_Wert",
    "heating.dhw.temperature.hysteresis.value"                  => "WW_Hysterese",
    "heating.dhw.sensors.temperature.hotWaterStorage.status"    => "WW_Temp_aktiv",
#   "heating.dhw.temperature.value"                             => "WW_Solltemp__C",
    "heating.dhw.schedule.active"                               => "WW_zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries"                              => "WW_Zeitplan",
    "heating.dhw.temperature.temp2.value"                       => "WW_Temp2__C",

    "heating.gas.consumption.summary.dhw.currentDay"            => "Gas_WW_Day__m3",
    "heating.gas.consumption.summary.dhw.lastSevenDays"         => "Gas_WW_7dLast__m3",
    "heating.gas.consumption.summary.dhw.currentMonth"          => "Gas_WW_Month__m3",
    "heating.gas.consumption.summary.dhw.lastMonth"             => "Gas_WW_MonthLast__m3",
    "heating.gas.consumption.summary.dhw.currentYear"           => "Gas_WW_Year__m3",
    "heating.gas.consumption.summary.dhw.lastYear"              => "Gas_WW_YearLast__m3",

    "heating.gas.consumption.summary.heating.currentDay"        => "Gas_Day__m3",
    "heating.gas.consumption.summary.heating.lastSevenDays"     => "Gas_7dLast__m3",
    "heating.gas.consumption.summary.heating.currentMonth"      => "Gas_Month__m3",
    "heating.gas.consumption.summary.heating.lastMonth"         => "Gas_MonthLast__m3",
    "heating.gas.consumption.summary.heating.currentYear"       => "Gas_Year__m3",
    "heating.gas.consumption.summary.heating.lastYear"          => "Gas_YearLast__m3",

    "heating.gas.consumption.dhw.day"                           => "Gas_WW_Tage__m3",
    "heating.gas.consumption.dhw.dayValueReadAt"                => "Gas_WW_Tage_Zeit",
    "heating.gas.consumption.dhw.week"                          => "Gas_WW_Wochen__m3",
    "heating.gas.consumption.dhw.weekValueReadAt"               => "Gas_WW_Wochen_Zeit",
    "heating.gas.consumption.dhw.month"                         => "Gas_WW_Monate__m3",
    "heating.gas.consumption.dhw.monthValueReadAt"              => "Gas_WW_Monate_Zeit",
    "heating.gas.consumption.dhw.year"                          => "Gas_WW_Jahre__m3",
    "heating.gas.consumption.dhw.yearValueReadAt"               => "Gas_WW_Jahre_Zeit",
    "heating.gas.consumption.dhw.unit"                          => "Gas_WW_Einheit",

    "heating.gas.consumption.heating.day"                       => "Gas_Heiz_Tage__m3",
    "heating.gas.consumption.heating.dayValueReadAt"            => "Gas_Heiz_Tage_Zeit",
    "heating.gas.consumption.heating.week"                      => "Gas_Heiz_Wochen__m3",
    "heating.gas.consumption.heating.weekValueReadAt"           => "Gas_Heiz_Wochen_Zeit",
    "heating.gas.consumption.heating.month"                     => "Gas_Heiz_Monate__m3",
    "heating.gas.consumption.heating.monthValueReadAt"          => "Gas_Heiz_Monate_Zeit",
    "heating.gas.consumption.heating.year"                      => "Gas_Heiz_Jahre__m3",
    "heating.gas.consumption.heating.yearValueReadAt"           => "Gas_Heiz_Jahre_Zeit",
    "heating.gas.consumption.heating.unit"                      => "Gas_Heiz_Einheit",

    "heating.gas.consumption.total.day"                         => "Gas_Total_Tage__m3",
    "heating.gas.consumption.total.dayValueReadAt"              => "Gas_Total_Tage_Zeit",
    "heating.gas.consumption.total.week"                        => "Gas_Total_Wochen__m3",
    "heating.gas.consumption.total.weekValueReadAt"             => "Gas_Total_Wochen_Zeit",
    "heating.gas.consumption.total.month"                       => "Gas_Total_Monate__m3",
    "heating.gas.consumption.total.monthValueReadAt"            => "Gas_Total_Monate_Zeit",
    "heating.gas.consumption.total.year"                        => "Gas_Total_Jahre__m3",
    "heating.gas.consumption.total.yearValueReadAt"             => "Gas_Total_Jahre_Zeit",
    "heating.gas.consumption.total.unit"                        => "Gas_Total_Einheit",

    "heating.power.consumption.summary.dhw.currentDay"          => "Strom_WW_Day__kWh",
    "heating.power.consumption.summary.dhw.lastSevenDays"       => "Strom_WW_7dLast__kWh",
    "heating.power.consumption.summary.dhw.currentMonth"        => "Strom_WW_Month__kWh",
    "heating.power.consumption.summary.dhw.lastMonth"           => "Strom_WW_MonthLast__kWh",
    "heating.power.consumption.summary.dhw.currentYear"         => "Strom_WW_Year__kWh",
    "heating.power.consumption.summary.dhw.lastYear"            => "Strom_WW_YearLast__kWh",

    "heating.power.consumption.summary.heating.currentDay"      => "Strom_Heiz_Day__kWh",
    "heating.power.consumption.summary.heating.lastSevenDays"   => "Strom_Heiz_7dLast__kWh",
    "heating.power.consumption.summary.heating.currentMonth"    => "Strom_Heiz_Month__kWh",
    "heating.power.consumption.summary.heating.lastMonth"       => "Strom_Heiz_MonthLast__kWh",
    "heating.power.consumption.summary.heating.currentYear"     => "Strom_Heiz_Year__kWh",
    "heating.power.consumption.summary.heating.lastYear"        => "Strom_Heiz_YearLast__kWh",

    "heating.circuits.3.heating.curve.shift"                    => "HK4_Heizkurve_Niveau",
    "heating.circuits.3.heating.curve.slope"                    => "HK4_Heizkurve_Steigung",
    "heating.circuits.3.geofencing.active"                      => "HK4_Geofencing",
    "heating.circuits.3.geofencing.status"                      => "HK4_Geofencing_Status",
    "heating.circuits.3.operating.programs.summerEco.active"    => "HK4_Solltemperatur_SummerEco_aktiv",
    "heating.circuits.3.zone.mode.active"                       => "HK4_ZoneMode_aktive",


    "heating.circuits.1.active"                                 => "HK2_aktiv",
    "heating.circuits.1.type"                                   => "HK2_Typ",
    "heating.circuits.1.circulation.pump.status"                => "HK2_Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active"            => "HK2_Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries"           => "HK2_Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status"                 => "HK2_Frostschutz_Status",
    "heating.circuits.1.geofencing.active"                      => "HK2_Geofencing",
    "heating.circuits.1.geofencing.status"                      => "HK2_Geofencing_Status",
    "heating.circuits.1.heating.curve.shift"                    => "HK2_Heizkurve_Niveau",
    "heating.circuits.1.heating.curve.slope"                    => "HK2_Heizkurve_Steigung",
    "heating.circuits.1.heating.schedule.active"                => "HK2_Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries"               => "HK2_Zeitsteuerung_Heizung",
    "heating.circuits.1.name"                                   => "HK2_Name",
    "heating.circuits.1.operating.modes.active.value"           => "HK2_Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active"             => "HK2_WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active"   => "HK2_WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeatingCooling.active"    => "HK2_WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" => "HK2_Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" => "HK2_Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.heating.active" => "HK2_heizen_aktiv",
    "heating.circuits.1.operating.modes.normalStandby.active" => "HK2_Normal_Standby_aktiv",
    "heating.circuits.1.operating.modes.standby.active" => "HK2_Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" => "HK2_Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" => "HK2_Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.demand" =>
      "HK2-Solltemperatur_comfort_Anforderung",
    "heating.circuits.1.operating.programs.comfort.temperature" =>
      "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" =>
      "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" =>
      "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" =>
      "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" =>
      "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.fixed.active" => "HK2-Fixed_aktiv",
    "heating.circuits.1.operating.programs.forcedLastFromSchedule.active" =>
      "HK2-forcedLastFromSchedule_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.active" =>
      "HK2-HolidayAtHome_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.end" => "HK2-HolidayAtHome_Ende",
    "heating.circuits.1.operating.programs.holidayAtHome.start" => "HK2-HolidayAtHome_Start",
    "heating.circuits.1.operating.programs.holiday.active" => "HK2_Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" => "HK2_Urlaub_Start_Zeit",
    "heating.circuits.1.operating.programs.holiday.end"   => "HK2_Urlaub_Ende_Zeit",
    "heating.circuits.1.operating.programs.normal.active" =>
      "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.demand" =>
      "HK2-Solltemperatur_Anforderung",
    "heating.circuits.1.operating.programs.normal.temperature" =>
      "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active" =>
      "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.demand" =>
      "HK2-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.1.operating.programs.reduced.temperature" =>
      "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.summerEco.active" =>
      "HK2-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.1.operating.programs.standby.active" =>
      "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" => "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.room.value" =>
      "HK2-Raum_Temperatur",
    "heating.circuits.1.sensors.temperature.supply.status" =>
      "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.unit" =>
      "HK2-Vorlauftemperatur_Einheit",
    "heating.circuits.1.sensors.temperature.supply.value" =>
      "HK2-Vorlauftemperatur",
    "heating.circuits.1.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.2.active"                  => "HK3_aktiv",
    "heating.circuits.2.type"                    => "HK3_Typ",
    "heating.circuits.2.circulation.pump.status" => "HK3_Zirkulationspumpe",
    "heating.circuits.2.circulation.schedule.active" =>"HK3_Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.2.circulation.schedule.entries" =>"HK3_Zeitsteuerung_Zirkulation",
    "heating.circuits.2.frostprotection.status" => "HK3_Frostschutz_Status",
    "heating.circuits.2.geofencing.active"      => "HK3_Geofencing",
    "heating.circuits.2.geofencing.status"      => "HK3_Geofencing_Status",
    "heating.circuits.2.heating.curve.shift"    => "HK3_Heizkurve_Niveau",
    "heating.circuits.2.heating.curve.slope"    => "HK3_Heizkurve_Steigung",
    "heating.circuits.2.heating.schedule.active" => "HK3-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.2.heating.schedule.entries" => "HK3_Zeitsteuerung_Heizung",
    "heating.circuits.2.name"                         => "HK3_Name",
    "heating.circuits.2.operating.modes.active.value" => "HK3_Betriebsart",
    "heating.circuits.2.operating.modes.dhw.active"   => "HK3_WW_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeating.active" => "HK3_WW_und_Heizen_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeatingCooling.active" => "HK3-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.2.operating.modes.forcedNormal.active" => "HK3-Solltemperatur_erzwungen",
    "heating.circuits.2.operating.modes.forcedReduced.active" => "HK3-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.2.operating.modes.heating.active" => "HK3-heizen_aktiv",
    "heating.circuits.2.operating.modes.normalStandby.active" => "HK3-Normal_Standby_aktiv",
    "heating.circuits.2.operating.modes.standby.active" => "HK3-Standby_aktiv",
    "heating.circuits.2.operating.programs.active.value" => "HK3-Programmstatus",
    "heating.circuits.2.operating.programs.comfort.active" => "HK3-Solltemperatur_comfort_aktiv",
    "heating.circuits.2.operating.programs.comfort.demand" => "HK3-Solltemperatur_comfort_Anforderung",
    "heating.circuits.2.operating.programs.comfort.temperature" => "HK3-Solltemperatur_comfort",
    "heating.circuits.2.operating.programs.eco.active" => "HK3-Solltemperatur_eco_aktiv",
    "heating.circuits.2.operating.programs.eco.temperature" => "HK3-Solltemperatur_eco",
    "heating.circuits.2.operating.programs.external.active" => "HK3-External_aktiv",
    "heating.circuits.2.operating.programs.external.temperature" => "HK3-External_Temperatur",
    "heating.circuits.2.operating.programs.fixed.active" => "HK3-Fixed_aktiv",
    "heating.circuits.2.operating.programs.forcedLastFromSchedule.active" => "HK3-forcedLastFromSchedule_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.active" => "HK3-HolidayAtHome_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.end" => "HK3-HolidayAtHome_Ende",
    "heating.circuits.2.operating.programs.holidayAtHome.start" => "HK3-HolidayAtHome_Start",
    "heating.circuits.2.operating.programs.holiday.active" => "HK3_Urlaub_aktiv",
    "heating.circuits.2.operating.programs.holiday.start" => "HK3_Urlaub_Start_Zeit",
    "heating.circuits.2.operating.programs.holiday.end"   => "HK3_Urlaub_Ende_Zeit",
    "heating.circuits.2.operating.programs.normal.active" =>
      "HK3-Solltemperatur_aktiv",
    "heating.circuits.2.operating.programs.normal.demand" =>
      "HK3-Solltemperatur_Anforderung",
    "heating.circuits.2.operating.programs.normal.temperature" =>
      "HK3-Solltemperatur_normal",
    "heating.circuits.2.operating.programs.reduced.active" =>
      "HK3-Solltemperatur_reduziert_aktiv",
    "heating.circuits.2.operating.programs.reduced.demand" =>
      "HK3-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.2.operating.programs.reduced.temperature" =>
      "HK3-Solltemperatur_reduziert",
    "heating.circuits.2.operating.programs.summerEco.active" =>
      "HK3-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.2.operating.programs.standby.active" =>
      "HK3-Standby_aktiv",
    "heating.circuits.2.sensors.temperature.room.status" => "HK3-Raum_Status",
    "heating.circuits.2.sensors.temperature.room.value" =>
      "HK3-Raum_Temperatur",
    "heating.circuits.2.sensors.temperature.supply.status" =>
      "HK3-Vorlauftemperatur_aktiv",
    "heating.circuits.2.sensors.temperature.supply.unit" =>
      "HK3-Vorlauftemperatur_Einheit",
    "heating.circuits.2.sensors.temperature.supply.value" => "HK3-Vorlauftemperatur",
    "heating.circuits.2.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.compressor.active"                     => "Kompressor_aktiv",
    "heating.configuration.multiFamilyHouse.active" => "Mehrfamilenhaus_aktiv",
    "heating.configuration.regulation.mode"         => "Regulationmode",
    "heating.controller.serial.value"  => "Controller_Seriennummer",
    "heating.dhw.active"               => "WW_aktiv",
    "heating.dhw.status"               => "WW_Status",
    "heating.dhw.charging.active"      => "WW_Aufladung",

    "heating.dhw.charging.level.bottom" => "WW_Speichertemperatur_unten",
    "heating.dhw.charging.level.middle" => "WW_Speichertemperatur_mitte",
    "heating.dhw.charging.level.top"    => "WW_Speichertemperatur_oben",
    "heating.dhw.charging.level.value"  => "WW_Speicherladung",

    "heating.errors.active.entries"  => "Fehlereintraege_aktive",
    "heating.errors.history.entries" => "Fehlereintraege_Historie",

    "heating.flue.sensors.temperature.main.status" => "Abgassensor_Status",
    "heating.flue.sensors.temperature.main.unit" => "Abgassensor_Temperatur_Einheit",
    "heating.flue.sensors.temperature.main.value" => "Abgassensor_Temperatur",

    "heating.fuelCell.operating.modes.active.value" => "Brennstoffzelle_Mode",
    "heating.fuelCell.operating.modes.ecological.active" => "Brennstoffzelle_Mode_Ecological",
    "heating.fuelCell.operating.modes.economical.active" => "Brennstoffzelle_Mode_Economical",
    "heating.fuelCell.operating.modes.heatControlled.active" => "Brennstoffzelle_wärmegesteuert",
    "heating.fuelCell.operating.modes.maintenance.active" => "Brennstoffzelle_Wartung",
    "heating.fuelCell.operating.modes.standby.active" => "Brennstoffzelle_Standby",
    "heating.fuelCell.operating.phase.value" => "Brennstoffzelle_Phase",
    "heating.fuelCell.power.production.day" => "Brennstoffzelle_Stromproduktion/Tag",
    "heating.fuelCell.power.production.month" => "Brennstoffzelle_Stromproduktion/Monat",
    "heating.fuelCell.power.production.unit" => "Brennstoffzelle_Stromproduktion_Einheit",
    "heating.fuelCell.power.production.week" => "Brennstoffzelle_Stromproduktion/Woche",
    "heating.fuelCell.power.production.year" => "Brennstoffzelle_Stromproduktion/Jahr",
    "heating.fuelCell.sensors.temperature.return.status" => "Brennstoffzelle_Temperatur_Ruecklauf_Status",
    "heating.fuelCell.sensors.temperature.return.unit" => "Brennstoffzelle_Temperatur_Ruecklauf_Einheit",
    "heating.fuelCell.sensors.temperature.return.value" => "Brennstoffzelle_Temperatur_Ruecklauf",
    "heating.fuelCell.sensors.temperature.supply.status" => "Brennstoffzelle_Temperatur_Vorlauf_Status",
    "heating.fuelCell.sensors.temperature.supply.unit" => "Brennstoffzelle_Temperatur_Vorlauf_Einheit",
    "heating.fuelCell.sensors.temperature.supply.value" => "Brennstoffzelle_Temperatur_Vorlauf",
    "heating.fuelCell.statistics.availabilityRate" => "Brennstoffzelle_Statistic_Verfügbarkeit",
    "heating.fuelCell.statistics.insertions" => "Brennstoffzelle_Statistic_Einschub",
    "heating.fuelCell.statistics.operationHours" => "Brennstoffzelle_Statistic_Bestriebsstunden",
    "heating.fuelCell.statistics.productionHours" => "Brennstoffzelle_Statistic_Produktionsstunden",
    "heating.fuelCell.statistics.productionStarts" => "Brennstoffzelle_Statistic_Produktionsstarts",

    "heating.gas.consumption.fuelCell.day" => "Gas_Brennstoffzelle/Tag",
    "heating.gas.consumption.fuelCell.week" => "Gas_Brennstoffzelle/Woche",
    "heating.gas.consumption.fuelCell.month" => "Gas_Brennstoffzelle/Monat",
    "heating.gas.consumption.fuelCell.year" => "Gas_Brennstoffzelle/Jahr",
    "heating.gas.consumption.fuelCell.unit" => "Gas_Brennstoffzelle/Einheit",

    "heating.heat.production.day"   => "Wärmeproduktion/Tag",
    "heating.heat.production.month" => "Wärmeproduktion/Woche",
    "heating.heat.production.unit"  => "Wärmeproduktion/Einheit",
    "heating.heat.production.week"  => "Wärmeproduktion/Woche",
    "heating.heat.production.year"  => "Wärmeproduktion/Jahr",

    "heating.operating.programs.holiday.active"         => "Urlaub_aktiv",
    "heating.operating.programs.holiday.end"            => "Urlaub_Ende_Zeit",
    "heating.operating.programs.holiday.start"          => "Urlaub_Start_Zeit",

    "heating.operating.programs.holidayAtHome.active"   => "HolidayAtHome_aktiv",
    "heating.operating.programs.holidayAtHome.end"      => "HolidayAtHome_Ende",
    "heating.operating.programs.holidayAtHome.start"    => "HolidayAtHome_Start",

    "heating.power.consumption.day"                     => "Stromverbrauch_Tag",
    "heating.power.consumption.month"                   => "Stromverbrauch_Monat",
    "heating.power.consumption.week"                    => "Stromverbrauch_Woche",
    "heating.power.consumption.year"                    => "Stromverbrauch_Jahr",
    "heating.power.consumption.unit"                    => "Stromverbrauch_Einheit",

    "heating.power.consumption.dhw.day"                 => "Strom_WW_Tage",
    "heating.power.consumption.dhw.dayValueReadAt"      => "Strom_WW_Tage_Zeit",
    "heating.power.consumption.dhw.week"                => "Strom_WW_Wochen",
    "heating.power.consumption.dhw.weekValueReadAt"     => "Strom_WW_Wochen_Zeit",
    "heating.power.consumption.dhw.month"               => "Strom_WW_Monate",
    "heating.power.consumption.dhw.monthValueReadAt"    => "Strom_WW_Monate_Zeit",
    "heating.power.consumption.dhw.year"                => "Strom_WW_Jahre",
    "heating.power.consumption.dhw.yearValueReadAt"     => "Strom_WW_Jahre_Zeit",
    "heating.power.consumption.dhw.unit"                => "Strom_WW_Einheit",

    "heating.power.consumption.heating.day"             => "Strom_Heizung_Tage__kWh",
    "heating.power.consumption.heating.dayValueReadAt"  => "Strom_Heizung_Tage_Zeit",
    "heating.power.consumption.heating.week"            => "Strom_Heizung_Wochen__kWh",
    "heating.power.consumption.heating.weekValueReadAt" => "Strom_Heizung_Wochen_Zeit",
    "heating.power.consumption.heating.month"           => "Strom_Heizung_Monate__kWh",
    "heating.power.consumption.heating.monthValueReadAt"=> "Strom_Heizung_Monate_Zeit",
    "heating.power.consumption.heating.year"            => "Strom_Heizung_Jahre__kWh",
    "heating.power.consumption.heating.yearValueReadAt" => "Strom_Heizung_Jahre_Zeit",
    "heating.power.consumption.heating.unit"            => "Strom_Heizung_Einheit",

    "heating.power.consumption.total.day"               => "Strom_Total_Tage__kWh",
    "heating.power.consumption.total.dayValueReadAt"    => "Strom_Total_Tage_Zeit",
    "heating.power.consumption.total.week"              => "Strom_Total_Wochen__kWh",
    "heating.power.consumption.total.weekValueReadAt"   => "Strom_Total_Wochen_Zeit",
    "heating.power.consumption.total.month"             => "Strom_Total_Monate__kWh",
    "heating.power.consumption.total.monthValueReadAt"  => "Strom_Total_Monate_Zeit",
    "heating.power.consumption.total.year"              => "Strom_Total_Jahre__kWh",
    "heating.power.consumption.total.yearValueReadAt"   => "Strom_Total_Jahre_Zeit",
    "heating.power.consumption.total.unit"              => "Strom_Total_Einheit",

    "heating.power.production.current.status"           => "Stromproduktion_aktueller_Status",
    "heating.power.production.current.value"            => "Stromproduktion",

    "heating.power.production.demandCoverage.current.unit" => "Stromproduktion_Bedarfsabdeckung/Einheit",
    "heating.power.production.demandCoverage.current.value" => "Stromproduktion_Bedarfsabdeckung",
    "heating.power.production.demandCoverage.total.day" => "Stromproduktion_Bedarfsabdeckung_total/Tag",
    "heating.power.production.demandCoverage.total.month" => "Stromproduktion_Bedarfsabdeckung_total/Monat",
    "heating.power.production.demandCoverage.total.unit" => "Stromproduktion_Bedarfsabdeckung_total/Einheit",
    "heating.power.production.demandCoverage.total.week" => "Stromproduktion_Bedarfsabdeckung_total/Woche",
    "heating.power.production.demandCoverage.total.year" => "Stromproduktion_Bedarfsabdeckung_total/Jahr",

    "heating.power.production.day"   => "Stromproduktion_Total/Tag",
    "heating.power.production.month" => "Stromproduktion_Total/Monat",
    "heating.power.production.productionCoverage.current.unit" =>
      "Stromproduktion_Produktionsabdeckung/Einheit",
    "heating.power.production.productionCoverage.current.value" =>
      "Stromproduktion_Produktionsabdeckung",
    "heating.power.production.productionCoverage.total.day" =>
      "Stromproduktion_Produktionsabdeckung_Total/Tag",
    "heating.power.production.productionCoverage.total.month" =>
      "Stromproduktion_Produktionsabdeckung_Total/Monat",
    "heating.power.production.productionCoverage.total.unit" =>
      "Stromproduktion_Produktionsabdeckung_Total/Einheit",
    "heating.power.production.productionCoverage.total.week" =>
      "Stromproduktion_Produktionsabdeckung_Total/Woche",
    "heating.power.production.productionCoverage.total.year" =>
      "Stromproduktion_Produktionsabdeckung_Total/Jahr",
    "heating.power.production.unit" => "Stromproduktion_Total/Einheit",
    "heating.power.production.week" => "Stromproduktion_Total/Woche",
    "heating.power.production.year" => "Stromproduktion_Total/Jahr",

    "heating.power.purchase.current.unit"  => "Stromkauf/Einheit",
    "heating.power.purchase.current.value" => "Stromkauf",
    "heating.power.sold.current.unit"      => "Stromverkauf/Einheit",
    "heating.power.sold.current.value"     => "Stromverkauf",
    "heating.power.sold.day"               => "Stromverkauf/Tag",
    "heating.power.sold.month"             => "Stromverkauf/Monat",
    "heating.power.sold.unit"              => "Stromverkauf/Einheit",
    "heating.power.sold.week"              => "Stromverkauf/Woche",
    "heating.power.sold.year"              => "Stromverkauf/Jahr",

    "heating.sensors.pressure.supply.status" => "Drucksensor_Vorlauf_Status",
    "heating.sensors.pressure.supply.unit"   => "Drucksensor_Vorlauf/Einheit",
    "heating.sensors.pressure.supply.value"  => "Drucksensor_Vorlauf",

    "heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
    "heating.sensors.power.output.value"  => "Sensor_Stromproduktion",

    "heating.sensors.temperature.outside.statusWired" => "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" =>
      "Aussen_StatusWireless",

    "heating.service.timeBased.serviceDue" => "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" =>
      "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" =>
      "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" => "Service_Letzter",
    "heating.service.burnerBased.serviceDue" =>
      "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" =>
      "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" =>
      "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" =>
      "Service_Letzter_brennerbasiert",

    "heating.solar.active"               => "Solar_aktiv",
    "heating.solar.pumps.circuit.status" => "Solar_Pumpe_Status",
    "heating.solar.rechargeSuppression.status" =>
      "Solar_Aufladeunterdrueckung_Status",
    "heating.solar.sensors.power.status" => "Solar_Sensor_Power_Status",
    "heating.solar.sensors.power.value"  => "Solar_Sensor_Power",
    "heating.solar.sensors.temperature.collector.status" =>
      "Solar_Sensor_Temperatur_Kollektor_Status",
    "heating.solar.sensors.temperature.collector.value" =>
      "Solar_Sensor_Temperatur_Kollektor",
    "heating.solar.sensors.temperature.dhw.status" =>
      "Solar_Sensor_Temperatur_WW_Status",
    "heating.solar.sensors.temperature.dhw.value" =>
      "Solar_Sensor_Temperatur_WW",
    "heating.solar.statistics.hours" => "Solar_Sensor_Statistik_Stunden",

    "heating.solar.power.cumulativeProduced.value" =>
      "Solarproduktion_Gesamtertrag",
    "heating.solar.power.production.month" => "Solarproduktion/Monat",
    "heating.solar.power.production.day"   => "Solarproduktion/Tag",
    "heating.solar.power.production.unit"  => "Solarproduktion/Einheit",
    "heating.solar.power.production.week"  => "Solarproduktion/Woche",
    "heating.solar.power.production.year"  => "Solarproduktion/Jahr"
};


#####################################################################################################################
# Modul initialisieren und Namen zusätzlicher Funktionen bekannt geben
#####################################################################################################################
sub vitoconnect_Initialize {
    my ($hash) = @_;
    $hash->{DefFn}   = \&vitoconnect_Define;    # wird beim 'define' eines Gerätes aufgerufen
    $hash->{UndefFn} = \&vitoconnect_Undef;     # # wird beim Löschen einer Geräteinstanz aufgerufen
    $hash->{DeleteFn} = \&vitoconnect_DeleteKeyValue;
    $hash->{SetFn}   = \&vitoconnect_Set;       # set-Befehle
    $hash->{GetFn}   = \&vitoconnect_Get;       # get-Befehle
    $hash->{AttrFn}  = \&vitoconnect_Attr;      # Attribute setzen/ändern/löschen
    $hash->{ReadFn}  = \&vitoconnect_Read;
    $hash->{AttrList} =
        "disable:0,1 "
      . "vitoconnect_mappings:textField-long "
      . "vitoconnect_translations:textField-long "
      . "vitoconnect_mapping_roger:0,1 "
      . "vitoconnect_raw_readings:0,1 "                 # Liefert nur die raw readings und verhindert das mappen wenn gesetzt
      . "vitoconnect_disable_raw_readings:0,1 "         # Wird ein mapping verwendet können die weiteren RAW Readings ausgeblendet werden
      . "vitoconnect_gw_readings:0,1 "                  # Schreibt die GW readings als Reading ins Device
      . "vitoconnect_actions_active:0,1 "
      . "vitoconnect_device:0,1 "                       # Hier kann Device 0 oder 1 angesprochen worden, default ist 0 und ich habe keinen GW mit Device 1
      . "vitoconnect_serial:textField-long "            # Legt fest welcher Gateway abgefragt werden soll, wenn nicht gesetzt werden alle abgefragt
      . "vitoconnect_installationID:textField-long "    # Legt fest welche Installation abgefragt werden soll, muss zur serial passen
      . "vitoconnect_timeout:selectnumbers,10,1.0,30,0,lin "
      . $readingFnAttributes;

      eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'
    return;
}


#####################################################################################################################
# wird beim 'define' eines Gerätes aufgerufen
#####################################################################################################################
sub vitoconnect_Define {
    my ( $hash, $def ) = @_;
    my $name  = $hash->{NAME};
    my $type  = $hash->{TYPE};
    
      my $params = {
      hash        => $hash,
      name        => $name,
      type        => $type,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 0,
  };

  use version 0.77; our $VERSION = moduleVersion ($params);                                              # Versionsinformationen setzen
  delete $params->{hash};
    
    
    my @param = split( '[ \t]+', $def );

    if ( int(@param) < 5 ) {
        return "too few parameters: "
          . "define <name> vitoconnect <user> <passwd> <intervall>";
    }

    $hash->{user}            = $param[2];
    $hash->{intervall}       = $param[4];
    $hash->{counter}         = 0;
    $hash->{timeout}         = 15;
    $hash->{".access_token"} = "";
    $hash->{devices}         = []; 
    $hash->{"Redirect_URI"}  = $callback_uri;

    my $isiwebpasswd = vitoconnect_ReadKeyValue($hash,"passwd");    # verschlüsseltes Kennwort auslesen
    if ($isiwebpasswd eq "")        {   # Kennwort (noch) nicht gespeichert
        my $err = vitoconnect_StoreKeyValue($hash,"passwd",$param[3]);  # Kennwort verschlüsselt speichern
        return $err if ($err);
    }
    else                            {   # Kennwort schon gespeichert
        Log3($name,3,$name." - Passwort war bereits gespeichert");
    }
    $hash->{apiKey} = vitoconnect_ReadKeyValue($hash,"apiKey");         # verschlüsselten apiKey auslesen
    RemoveInternalTimer($hash); # Timer löschen, z.b. bei intervall change
    InternalTimer(gettimeofday() + 10,"vitoconnect_GetUpdate",$hash);   # nach 10s
    return;
}


#####################################################################################################################
# wird beim Löschen einer Geräteinstanz aufgerufen
#####################################################################################################################
sub vitoconnect_Undef {
    my ($hash,$arg ) = @_;      # Übergabe-Parameter
    RemoveInternalTimer($hash); # Timer löschen
    return;
}


#####################################################################################################################
# bisher kein 'get' implementiert
#####################################################################################################################
sub vitoconnect_Get {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    return "get ".$name." needs at least one argument" unless (defined($opt) );
    return;
}


#####################################################################################################################
# Implementierung set-Befehle
#####################################################################################################################
sub vitoconnect_Set {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    
    # Standard Parameter setzen
    my $val = "unknown value $opt, choose one of update:noArg clearReadings:noArg password apiKey logResponseOnce:noArg clearMappedErrors:noArg ";
    Log(5,$name.", -vitoconnect_Set started: ". $opt); #debug
    
    # Setter für die Geräteauswahl dynamisch erstellen  
    Log3($name,4,$name." - Set devices: ".$hash->{devices});
    if (defined $hash->{devices} && ref($hash->{devices}) eq 'HASH' && keys %{$hash->{devices}} > 0) {
        my @device_serials = keys %{$hash->{devices}};
        $val .= " selectDevice:" . join(",", @device_serials);
    } else {
        $val .= " selectDevice:noArg"
    }
    $val .= " ";
    Log3($name,5,$name." - Set val: $val, Set Opt: $opt");
    
    # Hier richtig?
    return "set ".$name." needs at least one argument" unless (defined($opt) );
    
    # Setter für Device Werte rufen
    if  (AttrVal( $name, 'vitoconnect_raw_readings', 0 ) eq "1" ) {
        #use new dynamic parsing of JSON to get raw setters
        $val .= vitoconnect_Set_New ($hash,$name,$opt,@args) // '';
    } 
    elsif  (AttrVal( $name, 'vitoconnect_mapping_roger', 0 ) eq "1" ) {
        #use roger setters
        $val .= vitoconnect_Set_Roger ($hash,$name,$opt,@args) // '';
    } 
    else {
        #use svn setters
    $val .= vitoconnect_Set_SVN ($hash,$name,$opt,@args) // '';
    }
    


    if  ($opt eq "update")                            {   # set <name> update: update readings immeadiatlely
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_GetUpdate($hash);                       # neue Abfrage starten
        return;
    }
    elsif ($opt eq "logResponseOnce" )                  {   # set <name> logResponseOnce: dumps the json response of Viessmann server to entities.json, gw.json, actions.json in FHEM log directory
        $hash->{".logResponseOnce"} = 1;                    # in 'Internals' merken
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "clearReadings" )                    {   # set <name> clearReadings: clear all readings immeadiatlely
        AnalyzeCommand($hash,"deletereading ".$name." .*");
        return;
    }
    elsif ($opt eq "password" )                         {   # set <name> password: store password in key store
        my $err = vitoconnect_StoreKeyValue($hash,"passwd",$args[0]);   # Kennwort verschlüsselt speichern
        return $err if ($err);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "apiKey" )                           {   # set <name> apiKey: bisher keine Beschreibung
        $hash->{apiKey} = $args[0];
        my $err = vitoconnect_StoreKeyValue($hash,"apiKey",$args[0]);   # apiKey verschlüsselt speichern
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "selectDevice" )                           {   # set <name> selectDevice: Bei mehreren Devices eines auswählen
        Log3($name,4,$name." - Set selectedDevice serial: ".$args[0]);
        if (defined $args[0] && $args[0] ne '') {
        my $serial = $args[0];
        my %devices = %{ $hash->{devices} };
        if (exists $devices{$serial}) {
          my $installationId = $devices{$serial}{installationId};
          Log3($name,5,$name." - Set selectedDevice: instID: $installationId, serial $serial");
          CommandAttr (undef, "$name vitoconnect_installationID $installationId");
          CommandAttr (undef, "$name vitoconnect_serial $serial");
        }
        $hash->{selectedDevice} = $serial;
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_GetUpdate($hash);                       # neue Abfrage starten
        } else {
        readingsSingleUpdate($hash,"state","Kein Gateway/Device gefunden, bitte Setup überprüfen",1);  
        }
        return;
    }
    elsif ($opt eq "clearMappedErrors" ){
     AnalyzeCommand($hash,"deletereading ".$name." device.messages.errors.mapped.*");
     return;
    }


return $val;
}


#####################################################################################################################
# Implementierung set-Befehle neue logik aus raw readings
#####################################################################################################################
sub vitoconnect_Set_New {
    my ($hash, $name, $opt, @args) = @_;
    my $gw = AttrVal( $name, 'vitoconnect_serial', 0 );
    my $val = "";
    
    my $Response = $hash->{".response_$gw"};
    if ($Response) {  # Überprüfen, ob $Response Daten enthält
        my $data;
        eval { $data = decode_json($Response); };
        if ($@) {
            # JSON-Dekodierung fehlgeschlagen, nur Standardoptionen zurückgeben
            return $val;
        }
        
        foreach my $item (@{$data->{'data'}}) {

            if (exists $item->{commands}) {
                my $feature = $item->{feature};
                Log(5,$name.",vitoconnect_Set_New feature: ". $feature);

                foreach my $commandName (sort keys %{$item->{commands}}) {           #<====== Loop Commands, sort necessary for activate temperature for burners, see below
                    my $commandNr = keys %{$item->{commands}};
                    my @propertyKeys = keys %{$item->{properties}};
                    my $propertyKeysNr = keys %{$item->{properties}};
                    my $paramNr = keys %{$item->{commands}{$commandName}{params}};
                    
                    Log(5,$name.", -vitoconnect_Set_New isExecutable: ". $item->{commands}{$commandName}{isExecutable}); 
                    if ($item->{commands}{$commandName}{isExecutable} == 0) {
                    Log(5,$name.", -vitoconnect_Set_New $commandName nicht ausführbar"); 
                     next; #diser Befehl ist nicht ausführbar, nächster 
                    }

                    Log(5,$name.", -vitoconnect_Set_New feature: ". $feature);
                    Log(5,$name.", -vitoconnect_Set_New commandNr: ". $commandNr); 
                    Log(5,$name.", -vitoconnect_Set_New commandname: ". $commandName); 
                    my $readingNamePrep;
                    if ($commandNr == 1 and $propertyKeysNr == 1) {               # Ein command value = property z.B. heating.circuits.0.operating.modes.active
                     $readingNamePrep .= $feature.".". $propertyKeys[0];
                    } elsif ( $commandName eq "setTemperature" ) {
                        $readingNamePrep .= $feature.".temperature";              #<------- setTemperature only 1 param, so it can be defined here, 
                                                                                  # for burner Vitoladens 300C, heating.circuits.0.operating.programs.comfort
                                                                                  # activate (temperature), deactivate(noArg), setTemperature (targetTemperature) only one can work with value provided
                                                                                  # Activate should work, and is, since commands are sorted
                    } elsif ( $commandName eq "setHysteresis" ) {                 #<------- setHysteresis very special mapping, must be predefined
                        $readingNamePrep .= $feature.".value";
                    } elsif ( $commandName eq "setHysteresisSwitchOnValue" ) {    #<------- setHysteresis very special mapping, must be predefined
                        $readingNamePrep .= $feature.".switchOnValue";
                    } elsif ( $commandName eq "setHysteresisSwitchOffValue" ) {   #<------- setHysteresis very special mapping, must be predefined
                        $readingNamePrep .= $feature.".switchOffValue";
                    } elsif ( $commandName eq "setMin" ) {
                        $readingNamePrep .= $feature.".min";                      #<------- setMin/setMax very special mapping, must be predefined
                    } elsif ( $commandName eq "setMax" ) {
                        $readingNamePrep .= $feature.".max";
                    } elsif ( $commandName eq "setSchedule" ) {                   #<------- setSchedule very special mapping, must be predefined
                        $readingNamePrep .= $feature.".entries";
                    } elsif ( $commandName eq "setLevels" ) {
                        # duplicate, setMin, setMax can do this https://api.viessmann.com/iot/v2/features/installations/2772216/gateways/7736172146035226/devices/0/features/heating.circuits.0.temperature.levels/commands/setLevels
                        next;
                    }
                    else {
                    # all other cases, will be defined in param loop
                    }
                    if(defined($readingNamePrep))
                    {
                    Log(5,$name.", -vitoconnect_Set_New readingNamePrep: ". $readingNamePrep); 
                    }

                    if ($paramNr > 2) {                                          #<------- more then 2 parameters, with unsorted JSON can not be handled, but also do not exist at the moment
                        Log(5,$name.", -vitoconnect_Set_New mehr als 2 Parameter in Command $commandName, kann nicht berechnet werden"); 
                        next;
                    } elsif ($paramNr == 0){                                     #<------- no parameters, create here, param loop will not be executed
                        $readingNamePrep .= $feature.".".$commandName;
                        $val .= "$readingNamePrep:noArg ";
                        
                        # Set execution
                        if ($opt eq $readingNamePrep) {
                            my $uri = $item->{commands}->{$commandName}->{'uri'};
                            my ($shortUri) = $uri =~ m|.*features/(.*)|; #<=== URI ohne gateway zeug
                            Log(4,$name.", -vitoconnect_Set_New, 0 param, short uri: ".$shortUri);
                            vitoconnect_action($hash,
                                $shortUri,
                                "{}",
                                $name, $opt, @args
                            );
                            return;
                        }
                    }
                
                # 1 oder 2 Params, all other cases see above
                my @params = keys %{$item->{commands}{$commandName}{params}};
                    foreach my $paramName (@params) {   #<==== Loop params
                       
                       my $otherParam;
                       my $otherReadingName;
                       if ($paramNr == 2) {
                        $otherParam = $params[0] eq $paramName ? $params[1] : $params[0];
                       }
                       
                       my $readingName = $readingNamePrep;
                       if (!defined($readingName)) {                                            #<==== Bisher noch kein Reading gefunden, z.B. setCurve
                         $readingName = $feature.".".$paramName;
                         if (defined($otherParam)) {
                            $otherReadingName = $feature.".".$otherParam;
                         }
                       }
                       
                       my $param = $item->{commands}{$commandName}{params}{$paramName};
                       
                       # fill $val
                       if ($param->{type} eq 'number') {
                            $val .= $readingName.":slider," . ($param->{constraints}{min}) . "," . ($param->{constraints}{stepping}) . "," . ($param->{constraints}{max});
                        # Schauen ob float für slider
                          if ($param->{constraints}{stepping} =~ m/\./)  {
                                $val .= ",1 ";
                          } else { 
                            $val .= " ";
                          }
                       }
                        elsif ($param->{'type'} eq 'string') {
                            if ($commandName eq "setMode") {
                              my $enum = $param->{constraints}->{'enum'};
                              Log(5,$name.", -vitoconnect_Set_New enum: ". $enum); 
                              my $enumNr = scalar @$enum;
                              Log(5,$name.", -vitoconnect_Set_New enumNr: ". $enumNr); 
                            
                              my $i = 1;
                              $val .= $readingName.":";
                               foreach my $value (@$enum) {
                                if ($i < $enumNr) {
                                 $val .= $value.",";
                                } else {
                                 $val .= $value." ";
                                }
                                $i++;
                               }
                            } else {
                              $val .= $readingName.":textField-long ";
                            }
                            
                        } elsif ($param->{'type'} eq 'Schedule') {
                            $val .= $readingName.":textField-long ";
                        } elsif ($param->{'type'} eq 'boolean') {
                            $val .= "$readingName ";
                        } else {
                            # Ohne type direkter befehl ohne args
                            $val .= "$readingName:noArg ";
                            Log(5,$name.", -vitoconnect_Set_New unknown type: ".$readingName);
                        }
                        
                        Log(5,$name.", -vitoconnect_Set_New exec, opt:".$opt.", readingName:".$readingName);
                        # Set execution
                        if ($opt eq $readingName) {
                            
                            my $data;
                            my $otherData = '';
                            if ($param->{type} eq 'number') {
                             $data = "{\"$paramName\":@args";
                            } else {
                             $data = "{\"$paramName\":\"@args\"";
                            }
                            
                            # 2 params, one can be set the other must just be read and handed overload
                            # This logic ensures that we get the correct names in an unsortet JSON
                            if (defined($otherReadingName)) {
                               my $otherValue = ReadingsVal($name,$otherReadingName,"");
                              if ($param->{type} eq 'number') {
                               $otherData = ",\"$otherParam\":$otherValue";
                              } else {
                               $otherData = ",\"$otherParam\":\"$otherValue\"";
                              }
                            }
                            $data .= $otherData . '}';
                            my $uri = $item->{commands}->{$commandName}->{'uri'};
                            my ($shortUri) = $uri =~ m|.*features/(.*)|; #<=== URI ohne gateway zeug
                            Log(4,$name.", -vitoconnect_Set_New, short uri:".$shortUri.", data:".$data);
                            vitoconnect_action($hash,
                                $shortUri,
                                $data,
                                $name, $opt, @args
                            );
                            return;
                        }
                    }
                }
            }
        }
    }

    
    # Rückgabe der dynamisch erstellten $val Variable
    Log(5,$name.", -vitoconnect_Set_New val: ". $val);
    Log(5,$name.", -vitoconnect_Set_New ended ");
    
    return $val;
}


#####################################################################################################################
# Implementierung set-Befehle alte logik fixes mapping letzte SVN Version
#####################################################################################################################
sub vitoconnect_Set_SVN {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    # SVN mapping original handling of modul

    if ( $opt eq "HK1-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK1-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK2-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK3-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK1-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK2-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK3-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK1-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK2-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK3-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK1-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK2-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK3-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;

    }
    elsif ( $opt eq "HK2-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
               "heating.circuits.2.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.0/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.1/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.2/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-einmaliges_Aufladen" ) {
        vitoconnect_action( $hash,
            "heating.dhw.oneTimeCharge/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Zirkulationspumpe_Zeitplan" ) {
        vitoconnect_action( $hash,
            "heating.dhw.pumps.circulation.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Zeitplan" ) {
        vitoconnect_action( $hash, "heating.dhw.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Haupttemperatur" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature.main/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Solltemperatur" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature/commands/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Temperatur_2" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature.temp2/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "Urlaub_unschedule" ) {
        vitoconnect_action( $hash,
            "heating.operating.programs.holiday/commands/unschedule",
            "{}", $name, $opt, @args );
        return;
    }

    my $val = "WW-einmaliges_Aufladen:activate,deactivate "
      . "WW-Zirkulationspumpe_Zeitplan:textField-long "
      . "WW-Zeitplan:textField-long "
      . "WW-Haupttemperatur:slider,10,1,60 "
      . "WW-Solltemperatur:slider,10,1,60 "
      . "WW-Temperatur_2:slider,10,1,60 "
      . "Urlaub_Start "
      . "Urlaub_Ende "
      . "Urlaub_unschedule:noArg ";

    if ( ReadingsVal( $name, "HK1-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK1-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK1-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK1-Zeitsteuerung_Heizung:textField-long "
          . "HK1-Urlaub_Start "
          . "HK1-Urlaub_Ende "
          . "HK1-Urlaub_unschedule:noArg "
          . "HK1-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK1-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK1-Solltemperatur_comfort:slider,4,1,37 "
          . "HK1-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK1-Solltemperatur_normal:slider,3,1,37 "
          . "HK1-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK1-Name ";
    }
    if ( ReadingsVal( $name, "HK2-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK2-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK2-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK2-Zeitsteuerung_Heizung:textField-long "
          . "HK2-Urlaub_Start "
          . "HK2-Urlaub_Ende "
          . "HK2-Urlaub_unschedule:noArg "
          . "HK2-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK2-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK2-Solltemperatur_comfort:slider,4,1,37 "
          . "HK2-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK2-Solltemperatur_normal:slider,3,1,37 "
          . "HK2-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK2-Name ";
    }
    if ( ReadingsVal( $name, "HK3-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK3-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK3-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK3-Zeitsteuerung_Heizung:textField-long "
          . "HK3-Urlaub_Start "
          . "HK3-Urlaub_Ende "
          . "HK3-Urlaub_unschedule:noArg "
          . "HK3-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK3-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK3-Solltemperatur_comfort:slider,4,1,37 "
          . "HK3-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK3-Solltemperatur_normal:slider,3,1,37 "
          . "HK3-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK3-Name ";
    }
    
    return $val;
}


#####################################################################################################################
# Implementierung set-Befehle alte logik fixes mapping von Roger letzte Version
#####################################################################################################################
sub vitoconnect_Set_Roger {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter

    if ($opt eq "HK1_Betriebsart" )                  {   # set <name> HKn_Betriebsart: sets HKn_Betriebsart to heating,standby
        vitoconnect_action($hash,
            "heating.circuits.0.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_normal" )     {   # set <name> HK1_Soll_Temp_normal: sets the normale target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_reduziert" )      {   # set <name> HK1_Soll_Temp_reduziert: sets the reduced target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_comfort" )        {   # set <name> HK1_Soll_Temp_comfort: set comfort target temperatur for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_comfort_aktiv" )  {   # set <name> HK1_Soll_Temp_comfort_aktiv: activate/deactivate comfort temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_eco_aktiv" )      {   # set <name> HK1_Soll_Temp_eco_aktiv: activate/deactivate eco temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.eco/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Betriebsart" )                   {   # set <name> HKn_Betriebsart: sets WW_Betriebsart to balanced,off
        vitoconnect_action($hash,
            "heating.dhw.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_einmaliges_Aufladen" )           {   # set <name> WW_einmaliges_Aufladen: activate or deactivate one time charge for hot water
        vitoconnect_action($hash,
            "heating.dhw.oneTimeCharge/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Solltemperatur" )                {   # set <name> WW_Solltemperatur: sets hot water main temperature to targetTemperature, targetTemperature is an integer between 10 and 60
        vitoconnect_action($hash,
            "heating.dhw.temperature.main/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Zirkulationspumpe_Zeitplan" )    {   # set <name> WW_Zirkulationspumpe_Zeitplan: sets the schedule in JSON format for hot water circulation pump
        vitoconnect_action($hash,
            "heating.dhw.pumps.circulation.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Zeitplan" )                      {   # set <name> WW_Zeitplan: sets the schedule in JSON format for hot water
        vitoconnect_action($hash,
            "heating.dhw.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
#   elsif ($opt eq "WW_Solltemperatur" )                {   # set <name> WW_Solltemperatur: sets hot water temperature to targetTemperature, targetTemperature is an integer between 10 and 60
#       vitoconnect_action($hash,
#           "heating.dhw.temperature/commands/commands/setTargetTemperature",
#           "{\"temperature\":$args[0]}",
#           $name,$opt,@args
#       );
#       return;
#   }
    elsif ($opt eq "WW_Temperatur_2" )                  {   # set <name> WW_Temperatur_2: sets hot water 2 temperature to targetTemperature, targetTemperature is an integer between 10 and 60
        vitoconnect_action($hash,
            "heating.dhw.temperature.temp2/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "Urlaub_Start_Zeit" )                        {   # set <name> Urlaub_Start_Zeit: set holiday start time, start has to look like this: 2019-02-02
        my $end = ReadingsVal($name,"Urlaub_Ende_Zeit","");
        if ($end eq "")                                 {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "Urlaub_Ende_Zeit" )                     {   # set <name> Urlaub_Ende_Zeit: set holiday end time, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "Urlaub_stop" )              {   # set <name> Urlaub_stop: remove holiday start and end time
        vitoconnect_action($hash,
            "heating.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Name" )                         {   # set <name> HK1_Name: sets the name of the circuit for HKn
        vitoconnect_action($hash,
            "heating.circuits.0/commands/setName",
            "{\"name\":\"@args\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Name" )                         {   # set <name> HK2_Name: sets the name of the circuit for HKn
        vitoconnect_action($hash,
            "heating.circuits.1/commands/setName",
            "{\"name\":\"@args\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Name" )                         {   # set <name> HK3_Name: sets the name of the circuit for HKn
        vitoconnect_action($hash,
            "heating.circuits.2/commands/setName",
            "{\"name\":\"@args\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Heizkurve_Niveau" )             {   # set <name> HK1_Heizkurve_Niveau: set shift of heating curve for HKn
        my $slope = ReadingsVal($name,"HK1_Heizkurve_Steigung","");
        vitoconnect_action($hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Heizkurve_Niveau" )             {   #  set <name> HK2_Heizkurve_Niveau: set shift of heating curve for HKn
        my $slope = ReadingsVal($name,"HK2_Heizkurve_Steigung","");
        vitoconnect_action($hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Heizkurve_Niveau" )             {   # set <name> HK3_Heizkurve_Niveau: set shift of heating curve for HKn
        my $slope = ReadingsVal($name,"HK3_Heizkurve_Steigung","");
        vitoconnect_action($hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Heizkurve_Steigung" )           {   # set <name> HK1_Heizkurve_Steigung: set slope of heating curve for HKn
        my $shift = ReadingsVal($name,"HK1_Heizkurve_Niveau","");
        vitoconnect_action($hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Heizkurve_Steigung" )           {   # set <name> HK2_Heizkurve_Steigung: set slope of heating curve for HKn
        my $shift = ReadingsVal($name,"HK2-Heizkurve-Niveau","");
        vitoconnect_action($hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Heizkurve_Steigung" )           {   # set <name> HK3_Heizkurve_Steigung:  set slope of heating curve for HKn
        my $shift = ReadingsVal($name,"HK3-Heizkurve-Niveau","");
        vitoconnect_action($hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Urlaub_Start_Zeit" )            {   # set <name> HK1_Urlaub_Start_Zeit: set holiday start time for HKn, start  has to look like this: 2019-02-16
        my $end = ReadingsVal($name,"HK1_Urlaub_Ende_Zeit","");
        if ($end eq "")         {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Urlaub_Start_Zeit" )            {   # set <name> HK2_Urlaub_Start_Zeit: set holiday start time for HKn, start  has to look like this: 2019-02-16
        my $end = ReadingsVal($name,"HK2_Urlaub_Ende_Zeit","");
        if ($end eq "")                                 {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Urlaub_Start_Zeit" )                    {   # set <name> HK3-HK3_Urlaub_Start_Zeit: set holiday start time for HKn, start  has to look like this: 2019-02-16
        my $end = ReadingsVal($name,"HK3_Urlaub_Ende_Zeit","");
        if ($end eq "")                                 {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Urlaub_Ende_Zeit" )                 {   # set <name> HK1_Urlaub_Ende_Zeit: set holiday end time for HKn, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"HK1_Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Urlaub_Ende_Zeit" )                 {   # set <name> HK2_Urlaub_Ende_Zeit: set holiday end time for HKn, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"HK2_Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Urlaub_Ende_Zeit" )                 {   # set <name> HK3_Urlaub_Ende_Zeit: set holiday end time for HKn, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"HK3_Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Urlaub_stop" )          {   # set <name> HK1_Urlaub_stop: remove holiday start and end time for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Urlaub_stop" )          {   # set <name> HK2_Urlaub_stop: remove holiday start and end time for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Urlaub_stop" )          {   # set <name> HK3_Urlaub_stop: remove holiday start and end time for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Zeitsteuerung_Heizung" )        {   # set <name> HK1_Zeitsteuerung_Heizung: sets the heating schedule in JSON format for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2-Zeitsteuerung_Heizung" )        {   # set <name> HK2-Zeitsteuerung_Heizung: sets the heating schedule in JSON format for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3-Zeitsteuerung_Heizung" )        {   # set <name> HK3-Zeitsteuerung_Heizung: sets the heating schedule in JSON format for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Betriebsart" )                  {   # set <name> HK2-Betriebsart: sets HKn_Betriebsart to  heating,standby
        vitoconnect_action($hash,
            "heating.circuits.1.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Betriebsart" )                  {   # set <name> HK3-Betriebsart: sets HKn_Betriebsart to  heating,standby
        vitoconnect_action($hash,
            "heating.circuits.2.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2-Solltemperatur_comfort_aktiv" ) {   # set <name> HK2-Solltemperatur_comfort_aktiv: activate/deactivate comfort temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3-Solltemperatur_comfort_aktiv" ) {   # set <name> HK3-Solltemperatur_comfort_aktiv: activate/deactivate comfort temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2-Solltemperatur_comfort" )       {   # set <name> HK2-Solltemperatur_comfort: set comfort target temperatur for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3-Solltemperatur_comfort" )       {   # set <name> HK3-Solltemperatur_comfort: set comfort target temperatur for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Solltemperatur_eco_aktiv" )     {   # set <name> HK2_Solltemperatur_eco_aktiv: activate/deactivate eco temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.eco/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Solltemperatur_eco_aktiv" )     {   # set <name> HK3_Solltemperatur_eco_aktiv: activate/deactivate eco temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.eco/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Solltemperatur_normal" )        {   # set <name> HK2_Solltemperatur_normal: sets the normale target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Solltemperatur_normal" )        {   # set <name> HK3_Solltemperatur_normal: sets the normale target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Solltemperatur_reduziert" )     {   # set <name> HK2_Solltemperatur_reduziert: sets the reduced target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Solltemperatur_reduziert" )     {   # set <name> HK3_Solltemperatur_reduziert: sets the reduced target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}"
            ,$name,$opt,@args
        );
        return;
    }

    my $val = "WW_einmaliges_Aufladen:activate,deactivate "
        ."WW_Zirkulationspumpe_Zeitplan:textField-long "
        ."WW_Zeitplan:textField-long "
#       ."WW_Haupttemperatur:slider,10,1,60 "
        ."WW_Solltemperatur:slider,10,1,60 "
        ."WW_Temperatur_2:slider,10,1,60 "
        ."WW_Betriebsart:balanced,off "
        ."Urlaub_Start_Zeit "
        ."Urlaub_Ende_Zeit "
        ."Urlaub_stop:noArg ";

    if (ReadingsVal($name,"HK1_aktiv","0") eq "1") {
        $val .=
             "HK1_Heizkurve_Niveau:slider,-13,1,40 "
            ."HK1_Heizkurve_Steigung:slider,0.2,0.1,3.5,1 "
            ."HK1_Zeitsteuerung_Heizung:textField-long "
            ."HK1_Urlaub_Start_Zeit "
            ."HK1_Urlaub_Ende_Zeit "
            ."HK1_Urlaub_stop:noArg "
            ."HK1_Betriebsart:active,standby "
            ."HK1_Soll_Temp_comfort_aktiv:activate,deactivate "
            ."HK1_Soll_Temp_comfort:slider,4,1,37 "
            ."HK1_Soll_Temp_eco_aktiv:activate,deactivate "
            ."HK1_Soll_Temp_normal:slider,3,1,37 "
            ."HK1_Soll_Temp_reduziert:slider,3,1,37 "
            ."HK1_Name ";
    }
    if (ReadingsVal($name,"HK2_aktiv","0") eq "1") {
        $val .=
            "HK2_Heizkurve_Niveau:slider,-13,1,40 "
          . "HK2_Heizkurve_Steigung:slider,0.2,0.1,3.5,1 "
          . "HK2_Zeitsteuerung_Heizung:textField-long "
          . "HK2_Urlaub_Start_Zeit "
          . "HK2_Urlaub_Ende_Zeit "
          . "HK2_Urlaub_stop:noArg "
          . "HK2_Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK2_Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK2_Solltemperatur_comfort:slider,4,1,37 "
          . "HK2_Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK2_Solltemperatur_normal:slider,3,1,37 "
          . "HK2_Solltemperatur_reduziert:slider,3,1,37 "
          . "HK2_Name ";
    }
    if (ReadingsVal($name,"HK3_aktiv","0") eq "1") {
        $val .=
            "HK3_Heizkurve_Niveau:slider,-13,1,40 "
          . "HK3_Heizkurve_Steigung:slider,0.2,0.1,3.5,1 "
          . "HK3_Zeitsteuerung_Heizung:textField-long "
          . "HK3_Urlaub_Start_Zeit "
          . "HK3_Urlaub_Ende_Zeit "
          . "HK3_Urlaub_stop:noArg "
          . "HK3_Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK3_Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK3_Solltemperatur_comfort:slider,4,1,37 "
          . "HK3_Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK3_Solltemperatur_normal:slider,3,1,37 "
          . "HK3_Solltemperatur_reduziert:slider,3,1,37 "
          . "HK3_Name ";
    }
    
    return $val;
}


#####################################################################################################################
# Attribute setzen/ändern/löschen
#####################################################################################################################
sub vitoconnect_Attr {
    my ($cmd,$name,$attr_name,$attr_value ) = @_;
    
    Log(5,$name.", ".$cmd ." vitoconnect_: ".($attr_name // 'undef')." value: ".($attr_value // 'undef'));
    if ($cmd eq "set")  {
        if ($attr_name eq "vitoconnect_raw_readings" )      {
            if ($attr_value !~ /^0|1$/)                     {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_disable_raw_readings")     {
            if ( $attr_value !~ /^0|1$/ ) {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_gw_readings")     {
            if ( $attr_value !~ /^0|1$/ ) {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_actions_active")  {
            if ($attr_value !~ /^0|1$/)                     {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_mappings")                        {
            $RequestListMapping = eval $attr_value;
            if ($@) {
                # Fehlerbehandlung
                my $err = "Invalid argument: $@\n";
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_translations")                        {
            %translations = eval $attr_value;
            if ($@) {
                # Fehlerbehandlung
                my $err = "Invalid argument: $@\n";
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_mapping_roger")   {
            if ($attr_value !~ /^0|1$/)                     {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_serial")                      {
            if (length($attr_value) != 16)                      {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 16 characters long.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_installationID")                      {
            if (length($attr_value) < 2)                      {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be at least 2 characters long.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "disable")                     {
        }
        elsif ($attr_name eq "verbose")                     {
        }
        else                                                {
            # return "Unknown attr $attr_name";
            # This will return all attr, e.g. room. We do not want to see messages here.
            # Log(1,$name.", ".$cmd ." Unknow attr vitoconnect_: ".($attr_name // 'undef')." value: ".($attr_value // 'undef'));
        }
    }
    elsif ($cmd eq "del") {
        if ($attr_name eq "vitoconnect_mappings") {
            undef $RequestListMapping;
        }
        elsif ($attr_name eq "vitoconnect_translations") {
            undef %translations;
        }
    }
    return;
}


#####################################################################################################################
# # Abfrage aller Werte starten
#####################################################################################################################
sub vitoconnect_GetUpdate {
    my ($hash) = @_;# Übergabe-Parameter
    my $name = $hash->{NAME};
    Log3($name,4,$name." - GetUpdate called ...");
    if (IsDisabled($name))      {   # Device disabled
        Log3($name,4,$name." - device disabled");
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);   # nach Intervall erneut versuchen
        return;
    }
    else                        {   # Device nicht disabled
        vitoconnect_getResource($hash);
    }
    return;
}


#####################################################################################################################
# Werte für: Access-Token, Install-ID, Gateway anfragen
#####################################################################################################################
sub vitoconnect_getCode {
    my ($hash)       = @_;  # Übergabe-Parameter
    my $name         = $hash->{NAME};
    my $isiwebpasswd = vitoconnect_ReadKeyValue($hash,"passwd");        # verschlüsseltes Kennwort auslesen
    my $client_id    = $hash->{apiKey};
    if (!defined($client_id))   {   # $client_id/apiKey nicht definiert
        Log3($name,1,$name." - set apiKey first");                      # Fehlermeldung ins Log
        readingsSingleUpdate($hash,"state","Set apiKey to continue",1); # Reading 'state' setzen
        return;
    }
    my $authorizeURL = 'https://iam.viessmann.com/idp/v2/authorize';

    my $param = {
        url => $authorizeURL
        ."?client_id=".$client_id
        ."&redirect_uri=".$callback_uri."&"
        ."code_challenge=2e21faa1-db2c-4d0b-a10f-575fd372bc8c-575fd372bc8c&"
        ."&scope=IoT%20User%20offline_access"
        ."&response_type=code",
        hash            => $hash,
        header          => "Content-Type: application/x-www-form-urlencoded",
        ignoreredirects => 1,
        user            => $hash->{user},
        pwd             => $isiwebpasswd,
        sslargs         => { SSL_verify_mode => 0 },
        timeout         => $hash->{timeout},
        method          => "POST",
        callback        => \&vitoconnect_getCodeCallback
    };

    #Log3 $name, 4, "$name - user=$param->{user} passwd=$param->{pwd}";
    #Log3 $name, 5, Dumper($hash);
    HttpUtils_NonblockingGet($param);   # Anwort an: vitoconnect_getCodeCallback()
    return;
}


#####################################################################################################################
# Rückgabe: Access-Token, Install-ID, Gateway von vitoconnect_getCode Anfrage
#####################################################################################################################
sub vitoconnect_getCodeCallback {
    my ($param,$err,$response_body ) = @_;  # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err eq "")                 {   # Antwort kein Fehler
        Log3($name,4,$name." - getCodeCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body);
        $response_body =~ /code=(.*)"/;
        $hash->{".code"} = $1;          # in Internal '.code' speichern
        Log3($name,4,$name." - code: ".$hash->{".code"});
        if ( $hash->{".code"} && $hash->{".code"} ne "4" )  {
            $hash->{login} = "ok";      # Internal 'login'
        }
        else {
            $hash->{login} = "failure"; # Internal 'login'
        }
    }
    else                            {   # Fehler als Antwort
        Log3($name,1,$name.", vitoconnect_getCodeCallback - An error occured: ".$err);
        $hash->{login} = "failure";
    }

    if ( $hash->{login} eq "ok" )   {   # Login hat geklappt
        readingsSingleUpdate($hash,"state","login ok",1);       # Reading 'state' setzen
        vitoconnect_getAccessToken($hash);  # Access & Refresh-Token holen
    }
    else                            {   # Fehler beim Login
        readingsSingleUpdate($hash,"state","Login failure. Check password and apiKey",1);   # Reading 'state' setzen
        Log3($name,1,$name." - Login failure. Check password and apiKey");
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);   # Forum: #880
        return;
    }
    return;
}


#####################################################################################################################
# Access & Refresh-Token holen
#####################################################################################################################
sub vitoconnect_getAccessToken {
    my ($hash)    = @_;                 # Übergabe-Parameter
    my $name      = $hash->{NAME};      # Device-Name
    my $client_id = $hash->{apiKey};    # Internal: apiKey
    my $param     = {
        url    => "https://iam.viessmann.com/idp/v2/token",
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=authorization_code"
        . "&code_verifier="
        . $client_secret
        . "&client_id=$client_id"
        . "&redirect_uri=$callback_uri"
        . "&code="
        . $hash->{".code"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        callback => \&vitoconnect_getAccessTokenCallback
    };

    #Log3 $name, 1, "$name - " . $param->{"data"};
    HttpUtils_NonblockingGet($param);   # Anwort an: vitoconnect_getAccessTokenCallback()
    return;
}


#####################################################################################################################
# Access & Refresh-Token speichern, Antwort auf: vitoconnect_getAccessToken
#####################################################################################################################
sub vitoconnect_getAccessTokenCallback {
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};   # Device-Name

    if ($err eq "")                 {   # kein Fehler bei Antwort
        Log3($name,4,$name." - getAccessTokenCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $decode_json = eval {decode_json($response_body)};
        if ($@)                     {
            Log3($name,1,$name.", vitoconnect_getAccessTokenCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        my $access_token = $decode_json->{"access_token"};              # aus JSON dekodieren
        if ($access_token ne "")    {
            $hash->{".access_token"} = $access_token;                   # in Internals speichern
            $hash->{"refresh_token"} = $decode_json->{"refresh_token"}; # in Internals speichern

            Log3($name,4,$name." - Access Token: ".substr($access_token,0,20)."...");
            vitoconnect_getGw($hash);   # Abfrage Gateway-Serial
        }
        else                        {
            Log3($name,1,$name." - Access Token: nicht definiert");
            Log3($name,5,$name." - Received response: ".$response_body."\n");
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
    }
    else                            {   # Fehler bei Antwort
        Log3($name,1,$name.",vitoconnect_getAccessTokenCallback - getAccessToken: An error occured: ".$err);
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
        return;
    }
    return;
}


#####################################################################################################################
# neuen Access-Token anfragen
#####################################################################################################################
sub vitoconnect_getRefresh {
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $client_id = $hash->{apiKey};
    my $param     = {
        url    => "https://iam.viessmann.com/idp/v2/token",
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=refresh_token"
          . "&client_id=$client_id"
          . "&refresh_token="
          . $hash->{"refresh_token"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        callback => \&vitoconnect_getRefreshCallback
    };

    #Log3 $name, 1, "$name - " . $param->{"data"};
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# neuen Access-Token speichern
#####################################################################################################################
sub vitoconnect_getRefreshCallback {
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err eq "")                 {
        Log3($name,4,$name.". - getRefreshCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $decode_json = eval {decode_json($response_body)};
        if ($@)                     {   # Fehler aufgetreten
            Log3($name,1,$name.", vitoconnect_getRefreshCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        my $access_token = $decode_json->{"access_token"};
        if ($access_token ne "")    {   # kein Fehler
            $hash->{".access_token"} = $access_token;   # in Internal merken
            Log3($name,4,$name." - Access Token: ".substr($access_token,0,20)."...");
            #vitoconnect_getGw($hash);  # Abfrage Gateway-Serial
            # directly call get resource to save API calls
            vitoconnect_getResource($hash);
        }
        else {
            Log3 $name, 1, "$name - Access Token: nicht definiert";
            Log3 $name, 5, "$name - Received response: $response_body\n";
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);    # zurück zu getCode?
            return;
        }
    }
    else {
        Log3 $name, 1, "$name - getRefresh: An error occured: $err";
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
        return;
    }
    return;
}


#####################################################################################################################
# Abfrage Gateway-Serial
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################
sub vitoconnect_getGw {
    my ($hash)       = @_;  # Übergabe-Parameter
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $param        = {
#       url      => $apiURL
        url      => $iotURL_V1
        ."gateways",
        hash     => $hash,
        header   => "Authorization: Bearer ".$access_token,
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getGwCallback
    };
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# Gateway-Serial speichern, Anwort von Abfrage Gateway-Serial
#####################################################################################################################
sub vitoconnect_getGwCallback {
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err eq "")                         {   # kein Fehler aufgetreten
        Log3($name,4,$name." - getGwCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $items = eval {decode_json($response_body)};
        if ($@)                             {   # Fehler beim JSON dekodieren
            readingsSingleUpdate($hash,"state","JSON error while request: ".$@,1);  # Reading 'state'
            Log3($name,1,$name.", vitoconnect_getGwCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        $err = vitoconnect_errorHandling($hash,$items);
        if ($err ==1){
           return;
        }
        
        if ($hash->{".logResponseOnce"} )   {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $file        = $dir->child("gw.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($items));            # Datei 'gw.json' schreiben
            $file_handle->close();
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
            }
            
            # Alle Gateways holen und in hash schreiben, immer machen falls neue Geräte hinzu kommen
            my %devices;
            
            # Über jedes Gateway-Element in der JSON-Datenstruktur iterieren
            foreach my $gateway (@{$items->{data}}) {
              if (defined $gateway->{serial} && defined $gateway->{installationId}) {
                $devices{$gateway->{serial}} = {
                     installationId => $gateway->{installationId},
                     gatewayType    => $gateway->{gatewayType},
                     version        => $gateway->{version}
                   };
              }
            }

            $hash->{devices} = { %devices };
            
            if ( defined(AttrVal( $name, 'vitoconnect_installationID', 0 )) 
                      && AttrVal( $name, 'vitoconnect_installationID', 0 ) ne "" 
                      && AttrVal( $name, 'vitoconnect_installationID', 0 ) != 0 
              && defined(AttrVal( $name, 'vitoconnect_serial', 0 )) 
                      && AttrVal( $name, 'vitoconnect_serial', 0 ) ne "" 
                      && AttrVal( $name, 'vitoconnect_serial', 0 ) != 0 )  {
              # Attribute sind gesetzt, nichts zu tun
              Log3($name,5,$name." - getGW all atributes set already attr: instID: ".AttrVal( $name, 'vitoconnect_installationID', 0 ).
                                                                        ", serial: ".AttrVal( $name, 'vitoconnect_serial', 0 ));
              } else 
              {
              # Prüfungen der Gateways und weiteres vorgehen 
              my $num_devices = scalar keys %devices;
            
              if ($num_devices == 0) {
                readingsSingleUpdate($hash,"state","Keine Gateways/Devices gefunden, Account prüfen",1);
                return;
              } elsif ($num_devices == 1) {
                readingsSingleUpdate($hash,"state","Genau ein Gateway/Device gefunden",1);
               
               my ($serial) = keys %devices;
               my $installationId = $devices{$serial}->{installationId};
               Log3($name,4,$name." - getGW exactly one Device found set attr: instID: $installationId, serial $serial");
               my $result;
               $result = CommandAttr (undef, "$name vitoconnect_installationID $installationId");
               if ($result) {
                Log3($name, 1, "Error setting vitoconnect_installationID: $result");
                return;
               }
               $result = CommandAttr (undef, "$name vitoconnect_serial $serial");
               if ($result) {
                Log3($name, 1, "Error setting vitoconnect_serial: $result");
                return;
               }
               Log3($name, 4, "Successfully set vitoconnect_serial and vitoconnect_installationID attributes for $name");
              } else {
                readingsSingleUpdate($hash,"state","Mehrere Gateways/Devices gefunden, bitte eines auswählen über selectDevice",1);
                return;
              }
            }
            
      if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
        readingsSingleUpdate($hash,"gw",$response_body,1);  # im Reading 'gw' merken
        readingsSingleUpdate($hash,"number_of_gateways",scalar keys %devices,1);
      }

        # Alle Infos besorgt, rest nur für logResponceOnce
        if ($hash->{".logResponseOnce"} )   {
          vitoconnect_getInstallation($hash);
          vitoconnect_getInstallationFeatures($hash);
        } else {
          vitoconnect_getResource($hash);
        }
    }
    else                                    {   # Fehler aufgetreten
        Log3($name,1,$name." - An error occured: ".$err);
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# Abfrage Install-ID
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################
sub vitoconnect_getInstallation {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $param        = {
#       url      => $apiURL
        url      => $iotURL_V1
        ."installations",
        hash     => $hash,
        header   => "Authorization: Bearer ".$access_token,
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getInstallationCallback
        };
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# Install-ID speichern, Antwort von Abfrage Install-ID
#####################################################################################################################
sub vitoconnect_getInstallationCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );

    if ($err eq "")                         {
        Log3 $name, 4, "$name - getInstallationCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body";
        my $items = eval { decode_json($response_body) };
        if ($@) {
            readingsSingleUpdate( $hash, "state","JSON error while request: ".$@,1);
            Log3($name,1,$name.", vitoconnect_getInstallationCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        if ($hash->{".logResponseOnce"})    {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $file        = $dir->child("installation_" . $gw . ".json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($items));                # Datei 'installation.json' schreiben
            $file_handle->close();
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
        }
            
        if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
           readingsSingleUpdate( $hash, "installation", $response_body, 1 );
        }
        
        vitoconnect_getDevice($hash);

    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# Abfrage von Install-features speichern
#####################################################################################################################
sub vitoconnect_getInstallationFeatures {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = AttrVal( $name, 'vitoconnect_installationID', 0 );
    
    
    # installation features      #Fixme call only once
    my $param = {
#       url     => $apiURL
        url     => $iotURL_V2
        ."installations/".$installation."/features",
        hash    => $hash,
        header  => "Authorization: Bearer ".$access_token,
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getInstallationFeaturesCallback
    };
    
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
#Install-features speichern
#####################################################################################################################
sub vitoconnect_getInstallationFeaturesCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );
    
    my $decode_json = eval {decode_json($response_body)};
    if ((defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "")) {   # Fehler aufgetreten
        Log3($name,1,$name.",vitoconnect_getFeatures: Fehler während installation features: ".$err." :: ".$response_body);
        $err = vitoconnect_errorHandling($hash,$decode_json);
        if ($err ==1){
           return;
        }
    }
    else                                                {   #  kein Fehler aufgetreten
    
         if ($hash->{".logResponseOnce"})    {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $file        = $dir->child("installation_features_" . $gw . ".json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($decode_json));                # Datei 'installation.json' schreiben
            $file_handle->close();
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
        }
        
        if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
        readingsSingleUpdate($hash,"installation_features",$response_body,1);   # im Reading 'installation_features' merken
        }

    return;
    }
}


#####################################################################################################################
# Abfrage Device-ID
#####################################################################################################################
sub vitoconnect_getDevice {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = AttrVal( $name, 'vitoconnect_installationID', 0 );
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );
    
    Log(5,$name.", --getDevice gw for call set: ".$gw);

    my $param        = {
        url     => $iotURL_V1
        ."installations/".$installation."/gateways/".$gw."/devices",
        hash    => $hash,
        header  => "Authorization: Bearer ".$access_token,
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getDeviceCallback
    };
    HttpUtils_NonblockingGet($param);

    return;
}


#####################################################################################################################
# Device-ID speichern, Anwort von Abfrage Device-ID
#####################################################################################################################
sub vitoconnect_getDeviceCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw   = AttrVal( $name, 'vitoconnect_serial', 0 );

   Log(5,$name.", -getDeviceCallback get device gw: ".$gw);
    if ($err eq "")                         {
        Log3 $name, 4, "$name - getDeviceCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body\n";
        my $items = eval { decode_json($response_body) };
        if ($@)                             {
            RemoveInternalTimer($hash);
            readingsSingleUpdate($hash,"state","JSON error while request: ".$@,1);
            Log3($name,1,$name.", vitoconnect_getDeviceCallback: JSON error while request: ".$@);           
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        if ( $hash->{".logResponseOnce"} )  {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $filename    = "device_" . $gw . ".json";
            my $file        = $dir->child($filename);
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($items));            # Datei 'device.json' schreiben
            $file_handle->close();
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
        }
        if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
          readingsSingleUpdate($hash,"device",$response_body,1);    # im Reading 'device' merken
        }
        vitoconnect_getFeatures($hash);
    }
    else {
        if ((defined($err) && $err ne "")) {    # Fehler aufgetreten
        Log3($name,1,$name." - An error occured: ".$err);
        } else {
        Log3($name,1,$name." - An undefined error occured");
        }
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# Abruf GW Features, Anwort von Abfrage Device-ID
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################
sub vitoconnect_getFeatures {
    my ($hash)       =  shift;  # Übergabe-Parameter
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = AttrVal( $name, 'vitoconnect_installationID', 0 );
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );
    my $dev          = AttrVal($name,'vitoconnect_device',0);   # Attribut: vitoconnect_device (0,1), Standard: 0

    Log3($name,4,$name." - getFeatures went ok");

# Gateway features
    my $param = {
        url    => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/features",
        hash   => $hash,
        header => "Authorization: Bearer ".$access_token,
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getFeaturesCallback
    };
    
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# GW Features speichern
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################
sub vitoconnect_getFeaturesCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );
    
    my $decode_json = eval {decode_json($response_body)};

    if ((defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "")) {   # Fehler aufgetreten
        Log3($name,1,$name.",vitoconnect_getFeatures: Fehler während Gateway features: ".$err." :: ".$response_body);
        $err = vitoconnect_errorHandling($hash,$decode_json);
        if ($err ==1){
           return;
        }
    }   
    else                                                {   # kein Fehler aufgetreten
    
      if ($hash->{".logResponseOnce"})    {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $file        = $dir->child("gw_features_" . $gw . ".json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($decode_json));                # Datei 'installation.json' schreiben
            $file_handle->close();
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
      }
    
    if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {    
        readingsSingleUpdate($hash,"gw_features",$response_body,1);  # im Reading 'gw_features' merken
    }
        vitoconnect_getResource($hash);
    }
}


#####################################################################################################################
# Get der Daten vom Gateway
# Hier für den normalen Update
# Es wird im Sub entschieden ob für alle Gateways oder für eine vorgegeben Gateway Serial
#####################################################################################################################
sub vitoconnect_getResource {
    my ($hash)       = shift;               # Übergabe-Parameter
    my $name         = $hash->{NAME};   # Device-Name
    my $access_token = $hash->{".access_token"};
    my $installation = AttrVal( $name, 'vitoconnect_installationID', 0 );
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );
    my $dev          = AttrVal($name,'vitoconnect_device',0);

    Log3($name,4,$name." - enter getResourceOnce");
    Log3($name,4,$name." - access_token: ".substr($access_token,0,20)."...");
    Log3($name,4,$name." - installation: ".$installation);
    Log3($name,4,$name." - gw: ".$gw);
    if ($access_token eq "" || $installation eq "" || $gw eq "") {  # noch kein: Token, ID, GW
        vitoconnect_getCode($hash);
        return;
    }
    my $param = {
        url => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/devices/".$dev."/features",
        hash     => $hash,
        gw       => $gw,
        header   => "Authorization: Bearer $access_token",
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getResourceCallback
    };
    HttpUtils_NonblockingGet($param);   # non-blocking aufrufen --> Antwort an: vitoconnect_getResourceCallback
    return;
}


#####################################################################################################################
# Verarbeiten der Daten vom Gateway und schreiben in Readings
# Entweder statisch gemapped oder über attribute mapping gemapped oder nur raw Werte
# Wenn gemapped wird wird für alle Treffer des Mappings kein raw Wert mehr aktualisiert
#####################################################################################################################
sub vitoconnect_getResourceCallback {   
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash   = $param->{hash};
    my $name   = $hash->{NAME};
    my $gw     = AttrVal( $name, 'vitoconnect_serial', 0 );
    
    Log(5,$name.", -getResourceCallback started");
    Log3($name,5,$name." getResourceCallback calles with gw:".$gw); 
    
    if ($err eq "")                         {   # kein Fehler aufgetreten
        Log3($name,4,$name." - getResourceCallback went ok");
        Log3($name,5,$name." - Received response: ".substr($response_body,0,100)."...");
        my $items = eval {decode_json($response_body)};
        if ($@)                             {   # Fehler beim JSON dekodieren
            readingsSingleUpdate($hash,"state","JSON error while request: ".$@,1);  # Reading 'state'
            Log3($name,1,$name.", vitoconnect_getResourceCallback: JSON error while request: ".$@);
             InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        
        $err = vitoconnect_errorHandling($hash,$items);
        if ($err ==1){
           return;
        }

        if ($hash->{".logResponseOnce"} ) {
            my $dir         = path(AttrVal("global","logdir","log"));   # Verzeichnis
            my $file        = $dir->child("resource_".$gw.".json");             # Dateiname
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($response_body));                        # Datei 'resource.json' schreiben
            $file_handle->close();
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
            $hash->{".logResponseOnce"} = 0;
        }
        
        $hash->{".response_$gw"} = $response_body;
        
        Log(5,$name.", translations count:".scalar keys %translations);
        Log(5,$name.", RequestListMapping count:".scalar keys %$RequestListMapping);
        
        readingsBeginUpdate($hash);
        foreach ( @{ $items->{data} } ) {
            my $feature    = $_;
            my $properties = $feature->{properties};
            
            
        if (AttrVal( $name, 'vitoconnect_actions_active', 0 ) eq "1") {
        # Write all commands
         if (exists $feature->{commands}) {
          foreach my $command (keys %{$feature->{commands}}) {
           my $Reading = $feature->{feature}.".".$command;
           my $Value = $feature->{commands}{$command}{uri};
            readingsBulkUpdate($hash,$Reading,$Value,1);
          }
         }
        }
        
            
            foreach my $key ( sort keys %$properties ) {
                
                
                my $Reading = "";
                
                if ( scalar keys %translations > 0) {
                    
                    # Use translation from attr
                    my @parts = split(/\./, $feature->{feature} . "." . $key);
                     foreach my $part (@parts) {
                      if ($part !~ /\d+/) {
                       $part = $translations{$part} // $part;  # Übersetze den Teil oder behalte ihn bei
                      }
                     }
                    
                    $Reading = join('.', @parts);
                    
                }
                elsif ( scalar keys %$RequestListMapping > 0) {
                # Use RequestListMapping from Attr
                $Reading =
                  $RequestListMapping->{ $feature->{feature} . "." . $key };
                }
                elsif (AttrVal( $name, 'vitoconnect_mapping_roger', 0 ) eq "1") {
                 # Use build in Mapping Roger (old way)
                 $Reading = $RequestListRoger->{ $feature->{feature} . "." . $key };
                }
                else {
                 # Use build in Mapping SVN (old way)
                 $Reading = $RequestListSvn->{ $feature->{feature} . "." . $key };
                };

                if ( !defined($Reading) || AttrVal( $name, 'vitoconnect_raw_readings', 0 ) eq "1" )
                {   
                    $Reading = $feature->{feature} . "." . $key;
                }
                
                if ( !defined($Reading) && AttrVal( $name, 'vitoconnect_disable_raw_readings', 0 ) eq "1" )
                {   
                    next;
                }
                
                my $Type  = $properties->{$key}->{type};
                my $Value = $properties->{$key}->{value};
                $Value =~ s/\x{FFFD}+/[VUC]/g; # Ersetze aufeinanderfolgende Vorkommen von U+FFFD durch "unknown characters" siehe https://forum.fhem.de/index.php?msg=1334504
                #$Value =~ s/[^[:print:]]+//g; # Behalte alle druckbaren Zeichen 
                my $comma_separated_string = "";
                if ( $Type eq "array" ) {
                    if ( defined($Value) ) {
                        if (ref($Value->[0]) eq 'HASH') {
                        foreach my $entry (@$Value) {
                            foreach my $hash_key (sort keys %$entry) {
                                if ($hash_key ne "audiences") {
                                    my $hash_value = $entry->{$hash_key};
                                    if (ref($hash_value) eq 'ARRAY') {
                                        $comma_separated_string .= join(", ", @$hash_value) . ", ";
                                    } else {
                                        $comma_separated_string .= $hash_value . ", ";
                                    }
                                }
                            }
                        }
                         # Entferne das letzte Komma und Leerzeichen
                         $comma_separated_string =~ s/, $//;
                         readingsBulkUpdate($hash,$Reading,$comma_separated_string);
                        }
                        elsif (ref($Value) eq 'ARRAY') {
                            $comma_separated_string = ( join(",",@$Value) );
                            readingsBulkUpdate($hash,$Reading,$comma_separated_string);
                            Log3($name,5,$name." - ".$Reading." ".$comma_separated_string." (".$Type.")");
                        }
                        else {
                            Log3($name,4,$name." - Array Workaround for Property: ".$Reading);
                        }
                    }
                }
                elsif ($Type eq 'object') {
                    # Iteriere durch die Schlüssel des Hashes
                    foreach my $hash_key (sort keys %$Value) {
                        my $hash_value = $Value->{$hash_key};
                        $comma_separated_string .= $hash_value . ", ";
                    }
                # Entferne das letzte Komma und Leerzeichen
                $comma_separated_string =~ s/, $//;
                readingsBulkUpdate($hash,$Reading,$comma_separated_string);
                }
                elsif ( $Type eq "Schedule" ) {
                    my $Result = encode_json($Value);
                    readingsBulkUpdate($hash,$Reading,$Result);
                    Log3($name, 5, "$name - $Reading: $Result ($Type)");
                }
                else {
                    readingsBulkUpdate($hash,$Reading,$Value);
                    Log3 $name, 5, "$name - $Reading: $Value ($Type)";
                    #Log3 $name, 1, "$name - $Reading: $Value ($Type)";
                }
                
                # Store power readings as asSingleValue
                if ($Reading =~ m/dayValueReadAt$/) {
                 Log(5,$name.", -call setpower $Reading");
                 vitoconnect_getPowerLast ($hash,$name,$Reading);
                }
                
                # Get error codes from API
                if ($Reading eq "device.messages.errors.raw.entries") {
                 Log(5,$name.", -call getErrorCode $Reading");
                 if (defined $comma_separated_string && $comma_separated_string ne '') {
                  vitoconnect_getErrorCode ($hash,$name,$comma_separated_string);
                 }
                }
            }
        }

        readingsBulkUpdate($hash,"state","last update: ".TimeNow().""); # Reading 'state'
        readingsEndUpdate( $hash, 1 );  # Readings schreiben
    }
    else {
        Log3($name,1,$name." - An error occured: ".$err);
    }
      
    InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    Log(5,$name.", -getResourceCallback ended");
    
    
    return;
}


#####################################################################################################################
# Implementierung power readings die nur sehr selten kommen in ein logbares reading füllen (asSingleValue)
#####################################################################################################################
sub vitoconnect_getPowerLast {
    my ($hash, $name, $Reading) = @_;

    # entferne alles hinter dem letzten Punkt
    $Reading =~ s/\.[^.]*$//;
    
    # Liste der Stromwerte
    my @values = split(",", ReadingsVal($name,$Reading.".day","")); #(1.2, 76.7, 52.6, 40.9, 40.4, 30, 33.9, 75);

    # Zeitpunkt des ersten Wertes
    my $timestamp = ReadingsVal($name,$Reading.".dayValueReadAt",""); #'2024-11-29T11:28:56.915Z';

    if (!defined($timestamp)) {
        return;
    }

    # Datum extrahieren und in ein Time::Piece Objekt umwandeln
    my $date = Time::Piece->strptime(substr($timestamp, 0, 10), '%Y-%m-%d');

    # Anzahl der Sekunden in einem Tag
    my $one_day = 24 * 60 * 60;
    
    # Hash für die Key-Value-Paare
    my %data;
    my $readingLastTimestamp = ReadingsTimestamp($name,$Reading.".day.asSingleValue","0000000000");
    #my $lastTS = "0000000000";
    #if ($readingLastTimestamp ne "") {
    my $lastTS = time_str2num($readingLastTimestamp);
    #}
    Log(5,$name.", -setpower: readinglast: $readingLastTimestamp lastTS $lastTS");
    
    # Werte den entsprechenden Tagen zuordnen, start mit 1, letzten Tag ausschließen weil unvollständig
    for (my $i = $#values; $i >= 1; $i--) {
        my $current_date = $date - ($one_day * $i);
        Log3($name, 5, ", -setpower: date:$current_date value:$values[$i] ($i)");
        my $readingDate = $current_date->ymd . " 23:59:59";
        my $readingTS = time_str2num($readingDate);
        Log(5,$name.", -setpower: date $readingDate lastdate $readingLastTimestamp");
        if ($readingTS > $lastTS) {
         readingsBulkUpdate ($hash, $Reading.".day.asSingleValue", $values[$i], undef, $readingDate);
         Log(4,$name.", -setpower: readingsBulkUpdate ($hash, $Reading.day.asSingleValue, $values[$i], undef, $readingDate");
        }
    }

    return;
}


#####################################################################################################################
# Error Code auslesesn
#####################################################################################################################
sub vitoconnect_getErrorCode {
    my ($hash, $name, $comma_separated_string) = @_;
    #$comma_separated_string = "customer, c2, warning, 2025-02-03T17:25:19.000Z"; # debug
    my $language = AttrVal( 'global', 'language', 0 );
    my %severity_translations = (
    'note'          => 'Hinweis',
    'warning'       => 'Warnung',
    'error'         => 'Fehler',
    'criticalError' => 'kritischer Fehler'
     );

    if (defined $comma_separated_string && $comma_separated_string ne '') {

        my $serial = ReadingsVal($name, "device.serial.value", "");
        my $materialNumber = substr($serial, 0, 7); #"7733738"; #debug
        my @values = split(/, /, $comma_separated_string);
        my $Reading = "device.messages.errors.mapped";

        my $fault_counter = -1;
        my $cause_counter = -1;
        
        for (my $i = 0; $i < @values; $i += 4) {
            my $errorCode = $values[$i + 1];
            my $severity = $values[$i + 2];
            if (uc($language) eq 'DE') {
            $severity = $severity_translations{$severity};
            }

            my $param = {
                url => "https://api.viessmann.com/service-documents/v3/error-database?materialNumber=$materialNumber&errorCode=$errorCode&countryCode=${\uc($language)}&languageCode=${\lc($language)}",
                hash => $hash,
                timeout => $hash->{timeout},  # Timeout von Internals = 15s
                method => "GET",  # Methode auf GET ändern
                sslargs => { SSL_verify_mode => 0 },
            };
            Log3($name, 5, $name . ", vitoconnect_getErrorCode url=" . $param->{url});

            my ($err, $msg) = HttpUtils_BlockingGet($param);
            my $decode_json = eval { JSON->new->decode($msg) };#decode_json($msg) };
            Log3($name, 5, $name . ", vitoconnect_getErrorCode debug err=$err msg=" . $msg . " json=" . Dumper($decode_json));  # wieder weg

            if (defined($err) && $err ne "") {   # Fehler bei Befehlsausführung
                Log3($name, 1, $name . ", vitoconnect_getErrorCode call finished with error, err:" . $err);
            } elsif (exists $decode_json->{statusCode} && $decode_json->{statusCode} ne "") {
                Log3($name, 1, $name . ", vitoconnect_getErrorCode call finished with error, status code:" . $decode_json->{statusCode});
            } else {   # Befehl korrekt ausgeführt
                Log3($name, 5, $name . ", vitoconnect_getErrorCode: finished ok");
                if (exists $decode_json->{faultCodes} && @{$decode_json->{faultCodes}}) {
                    foreach my $fault (@{$decode_json->{faultCodes}}) {
                        $fault_counter++;
                        my $fault_code = $fault->{faultCode};
                        my $system_characteristics = $fault->{systemCharacteristics};
                        # remove html paragraphs
                        $system_characteristics =~ s/<\/?(p|q)>//g;
                        readingsBulkUpdate($hash, $Reading . ".$fault_counter.faultCode", $fault_code);
                        readingsBulkUpdate($hash, $Reading . ".$fault_counter.severity", $severity);
                        readingsBulkUpdate($hash, $Reading . ".$fault_counter.systemCharacteristics", $system_characteristics);

                        foreach my $cause (@{$fault->{causes}}) {
                            $cause_counter++;
                            my $cause_text = $cause->{cause};
                            my $measure = $cause->{measure};
                            # remove html paragraphs
                            $cause_text =~ s/<\/?(p|q)>//g;
                            $measure =~ s/<\/?(p|q)>//g;
                            readingsBulkUpdate($hash, $Reading . ".$fault_counter.faultCodes.$cause_counter.cause", $cause_text);
                            readingsBulkUpdate($hash, $Reading . ".$fault_counter.faultCodes.$cause_counter.measure", $measure);
                        }
                    }
                } else {
                    Log3($name, 1, $name . ", vitoconnect_getErrorCode no faultcode in json found. json=" . Dumper($decode_json));
                }
            }
        }
    } else {
        Log3($name, 1, $name . " , vitoconnect_getErrorCode the variable \$comma_separated_string does not exist or is empty");
    }
    return;
}


#####################################################################################################################
# Setzen von Daten
#####################################################################################################################
sub vitoconnect_action {
    my ($hash,$feature,$data,$name,$opt,@args ) = @_;   # Übergabe-Parameter
    my $access_token = $hash->{".access_token"};        # Internal: .access_token
    my $installation = AttrVal( $name, 'vitoconnect_installationID', 0 );
    my $gw           = AttrVal( $name, 'vitoconnect_serial', 0 );
    my $dev          = AttrVal($name,'vitoconnect_device',0);
    
    my $param        = {
        url => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/"
        ."devices/".$dev."/features/".$feature,
        hash   => $hash,
        header => "Authorization: Bearer ".$access_token."\r\n"
        . "Content-Type: application/json",
        data    => $data,
        timeout => $hash->{timeout},            # Timeout von Internals = 15s
        method  => "POST",
        sslargs => { SSL_verify_mode => 0 },
    };
    Log3($name,3,$name.", vitoconnect_action url=" .$param->{url});
    Log3($name,3,$name.", vitoconnect_action data=".$param->{data});
#   https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_BlockingGet
    (my $err,my $msg) = HttpUtils_BlockingGet($param);
    my $decode_json = eval {decode_json($msg)};

    Log3($name,3,$name.", vitoconnect_action call finished, err:" .$err);
    my $Text = join(' ',@args); # Befehlsparameter in Text
    if ( (defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "") )                   {   # Fehler bei Befehlsausführung
        readingsSingleUpdate($hash,"Aktion_Status","Fehler: ".$opt." ".$Text,1);    # Reading 'Aktion_Status' setzen
        Log3($name,1,$name.",vitoconnect_action: set ".$name." ".$opt." ".@args.", Fehler bei Befehlsausfuehrung: ".$err." :: ".$msg);
    }
    else                                                                {   # Befehl korrekt ausgeführt
        readingsSingleUpdate($hash,"Aktion_Status","OK: ".$opt." ".$Text,1);    # Reading 'Aktion_Status' setzen
        #Log3($name,1,$name.",vitoconnect_action: set name:".$name." opt:".$opt." text:".$Text.", korrekt ausgefuehrt: ".$err." :: ".$msg); # TODO: Wieder weg machen $err
        Log3($name,3,$name.",vitoconnect_action: set name:".$name." opt:".$opt." text:".$Text.", korrekt ausgefuehrt"); 
        
        # Spezial Readings update
        if ($opt =~ /(.*)\.deactivate/) {
            $opt = $1 . ".active";
            $Text = "0";
        } elsif ($opt =~ /(.*)\.activate/) {
            $opt = $1 . ".active";
            $Text = "1";
        }
        readingsSingleUpdate($hash,$opt,$Text,1);   # Reading updaten
        #Log3($name,1,$name.",vitoconnect_action: reading upd1 hash:".$hash." opt:".$opt." text:".$Text); # TODO: Wieder weg machen $err
        
        # Spezial Readings update, activate mit temperatur siehe brenner Vitoladens300C
        if ($feature =~ /(.*)\.deactivate/) {
            # funktioniert da deactivate ohne temperatur gesendet wird
        } elsif ($feature =~ /(.*)\/commands\/activate/) {
            $opt = $1 . ".active";
            $Text = "1";
        }
        readingsSingleUpdate($hash,$opt,$Text,1);   # Reading updaten
        #Log3($name,1,$name.",vitoconnect_action: reading upd2 hash:".$hash." opt:".$opt." text:".$Text); # TODO: Wieder weg machen $err
        
        
        Log3($name,4,$name.",vitoconnect_action: set feature:".$feature." data:".$data.", korrekt ausgefuehrt"); #4
    }
    return;
}


#####################################################################################################################
# Errors bearbeiten
#####################################################################################################################
sub vitoconnect_errorHandling {
    my ($hash,$items) = @_;
    my $name          = $hash->{NAME};
    my $gw            = AttrVal( $name, 'vitoconnect_serial', 0 );
    
    #Log3 $name, 1, "$name - errorHandling StatusCode: $items->{statusCode} ";
    
        if (defined $items->{statusCode} && !$items->{statusCode} eq "")    {
            Log3 $name, 4, "$name - statusCode: " . ($items->{statusCode} // 'undef') . " "
                         . "errorType: " . ($items->{errorType} // 'undef') . " "
                         . "message: " . ($items->{message} // 'undef') . " "
                         . "error: " . ($items->{error} // 'undef') . " "
                         . "reason: " . ($items->{extendedPayload}->{reason} // 'undef');
             
            readingsSingleUpdate(
               $hash,
               "state",
               "statusCode: " . ($items->{statusCode} // 'undef') . " "
             . "errorType: " . ($items->{errorType} // 'undef') . " "
             . "message: " . ($items->{message} // 'undef') . " "
             . "error: " . ($items->{error} // 'undef') . " "
             . "reason: " . ($items->{extendedPayload}->{reason} // 'undef'),
               1
            );
            if ( $items->{statusCode} eq "401" ) {
                #  EXPIRED TOKEN
                vitoconnect_getRefresh($hash);    # neuen Access-Token anfragen
                return(1);
            }
            elsif ( $items->{statusCode} eq "404" ) {
                # DEVICE_NOT_FOUND
                readingsSingleUpdate($hash,"state","Device not found: Optolink prüfen!",1);
                Log3 $name, 1, "$name - Device not found: Optolink prüfen!";
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                return(1);
            }
            elsif ( $items->{statusCode} eq "429" ) {
                # RATE_LIMIT_EXCEEDED
                readingsSingleUpdate($hash,"state","Anzahl der möglichen API Calls in überschritten!",1);
                Log3 $name, 1,
                  "$name - Anzahl der möglichen API Calls in überschritten!";
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                return(1);
            }
            elsif ( $items->{statusCode} eq "502" ) {
                readingsSingleUpdate($hash,"state","temporärer API Fehler",1);
                # DEVICE_COMMUNICATION_ERROR error: Bad Gateway
                Log3 $name, 1, "$name - temporärer API Fehler";
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                return(1);
            }
            else {
                readingsSingleUpdate($hash,"state","unbekannter Fehler, bitte den Entwickler informieren!",1);
                Log3 $name, 1, "$name - unbekannter Fehler: "
                             . "Bitte den Entwickler informieren!";
                Log3 $name, 1, "$name - statusCode: " . ($items->{statusCode} // 'undef') . " "
                             . "errorType: " . ($items->{errorType} // 'undef') . " "
                             . "message: " . ($items->{message} // 'undef') . " "
                             . "error: " . ($items->{error} // 'undef') . " "
                             . "reason: " . ($items->{extendedPayload}->{reason} // 'undef');
             
                my $dir         = path( AttrVal("global","logdir","log"));
                my $file        = $dir->child("vitoconnect_" . $gw . ".err");
                my $file_handle = $file->openw_utf8();
                $file_handle->print(Dumper($items));                            # Datei 'vitoconnect_serial.err' schreiben
                $file_handle->close();
                Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
                
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                return(1);
            }
        }
};


#####################################################################################################################
# Werte verschlüsselt speichern
#####################################################################################################################
sub vitoconnect_StoreKeyValue {
    # checks and stores obfuscated keys like passwords
    # based on / copied from FRITZBOX_storePassword
    my ( $hash, $kName, $value ) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;
    my $enc   = "";

    if ( eval "use Digest::MD5;1" ) {
        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
    }
    for my $char ( split //, $value ) {
        my $encode = chop($key);
        $enc .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }
    my $err = setKeyValue( $index, $enc );      # Die Funktion setKeyValue() speichert die Daten $value unter dem Schlüssel $key ab.
    return "error while saving the value - ".$err if ( defined($err) ); # Fehler
    return;
}


#####################################################################################################################
# verschlüsselte Werte auslesen
#####################################################################################################################
sub vitoconnect_ReadKeyValue {

    # reads obfuscated value

    my ($hash,$kName) = @_;     # Übergabe-Parameter
    my $name = $hash->{NAME};

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;

    my ( $value, $err );

    Log3($name,5,$name." - ReadKeyValue tries to read value for ".$kName." from file");
    ($err,$value ) = getKeyValue($index);       # Die Funktion getKeyValue() gibt Daten, welche zuvor per setKeyValue() gespeichert wurden, zurück.

    if ( defined($err) )    {   # im Fehlerfall
        Log3($name,1,$name." - ReadKeyValue is unable to read value from file: ".$err);
        return;
    }

    if ( defined($value) )  {
        if ( eval "use Digest::MD5;1" ) {
            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }
        my $dec = '';
        for my $char ( map  { pack( 'C', hex($_) ) } ( $value =~ /(..)/g ) ) {
            my $decode = chop($key);
            $dec .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }
        return $dec;            # Rückgabe dekodierten Wert
    }
    else                    {   # Fehler: 
        Log3($name,1,$name." - ReadKeyValue could not find key ".$kName." in file");
        return;
    }
    return;
}


#####################################################################################################################
# verschlüsselte Werte löschen
#####################################################################################################################
sub vitoconnect_DeleteKeyValue {
    my ($hash,$kName) = @_;    # Übergabe-Parameter
    my $name = $hash->{NAME};

    Log3( $name, 5,$name." - called function Delete()" );

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    setKeyValue( $index, undef );
    $index = $hash->{TYPE}."_".$hash->{NAME}."_apiKey";
    setKeyValue( $index, undef );

    return;
}

1;


=pod
=item device
=item summary support for Viessmann API
=item summary_DE Unterstützung für die Viessmann API
=begin html

<a id="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implements a device for the Viessmann API
    <a href="https://www.viessmann.de/de/viessmann-apps/vitoconnect.html">Vitoconnect100</a> or E3 One Base
    based on the investigation of
    <a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a>.<br>
    
    You need the user and password from the ViCare App account.<br>
    Additionally also an apiKey, see set apiKey.<br>
     
    For details, see: <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (German)</a><br><br>
     
    vitoconnect requires the following libraries:
    <ul>
        <li>Path::Tiny</li>
        <li>JSON</li>
        <li>JSON:XS</li>
        <li>DateTime</li>
    </ul>   
         
    Use <code>sudo apt install libtypes-path-tiny-perl libjson-perl libdatetime-perl</code> or 
    install the libraries via CPAN. 
    Otherwise, you will get an error message: "cannot load module vitoconnect".
     
    <br><br>
    <a id="vitoconnect-define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code><br>
        It is a good idea to use a fake password here and set the correct one later because it is
        readable in the detail view of the device.
        <br><br>
        Example:<br>
        <code>define vitoconnect vitoconnect user@mail.xx fakePassword 60</code><br>
        <code>set vitoconnect password correctPassword</code>
        <code>set vitoconnect apiKey Client-ID</code>
        <br><br>
    </ul>
    <br>
    
    <a id="vitoconnect-set"></a>
    <b>Set</b><br>
    <ul>
        <a id="vitoconnect-set-update"></a>
        <li><code>update</code><br>
            Update readings immediately.</li>
        <a id="vitoconnect-set-selectDevice"></a>
        <li><code>selectDevice</code><br>
            Has to be used if you have more than one Viessmann Gateway/Device. You have to choose one Viessmann Device per FHEM Device.<br>
            You will be notified in the FHEM device state that you have to execute the set, and the Viessmann devices will be prefilled.<br>
            Selecting one Viessmann device and executing the set will fill the attributes <code>vitoconnect_serial</code> and <code>vitoconnect_installationId</code>.<br>
            If you have only one Viessmann device, this will be done automatically for you.<br>
            You should save the change after initialization or set.
        </li>
        <a id="vitoconnect-set-clearReadings"></a>
        <li><code>clearReadings</code><br>
            Clear all readings immediately.</li> 
        <a id="vitoconnect-set-clearMappedErrors"></a>
        <li><code>clearMappedErrors</code><br>
            Clear all mapped errors immediately.</li> 
        <a id="vitoconnect-set-password"></a>
        <li><code>password passwd</code><br>
            Store password in the key store.</li>
        <a id="vitoconnect-set-logResponseOnce"></a>
        <li><code>logResponseOnce</code><br>
            Dumps the JSON response of the Viessmann server to <code>entities.json</code>,
            <code>gw.json</code>, and <code>actions.json</code> in the FHEM log directory.
            If you have more than one gateway, the gateway serial is attached to the filenames.</li>
        <a id="vitoconnect-set-apiKey"></a>
        <li><code>apiKey</code><br>
            You need to create an API Key under <a href="https://developer.viessmann.com/">https://developer.viessmann.com/</a>.
            Create an account, add a new client (disable Google reCAPTCHA, Redirect URI = <code>http://localhost:4200/</code>).
            Copy the Client ID here as <code>apiKey</code>.</li>
        <li><code>Setters for your device will be available depending on the mapping method you choose with the help of the attributes <code>vitoconnect_raw_readings</code> or <code>vitoconnect_mapping_roger</code>.</code><br>
            New setters are used if <code>vitoconnect_raw_readings = 1</code>.
            The default is the static mapping of the old SVN version.
            For this, the following setters are available:</li>
        <li><code>HKn_Heizkurve_Niveau shift</code><br>
            Set shift of heating curve for HKn.</li>
        <li><code>HKn_Heizkurve_Steigung slope</code><br>
            Set slope of heating curve for HKn.</li>
        <li><code>HKn_Urlaub_Start_Zeit start</code><br>
            Set holiday start time for HKn.<br>
            <code>start</code> has to look like this: <code>2019-02-02</code>.</li>
        <li><code>HKn_Urlaub_Ende_Zeit end</code><br>
            Set holiday end time for HKn.<br>
            <code>end</code> has to look like this: <code>2019-02-16</code>.</li>
        <li><code>HKn_Urlaub_stop</code> <br>
            Remove holiday start and end time for HKn.</li>
        <li><code>HKn_Zeitsteuerung_Heizung schedule</code><br>
            Sets the heating schedule for HKn in JSON format.<br>
            Example: <code>{"mon":[],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[],"sun":[]}</code> is completely off,
            and <code>{"mon":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "tue":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "wed":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "thu":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "fri":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "sat":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "sun":[{"mode":"on","start":"00:00","end":"24:00","position":0}]}</code> is on 24/7.</li>
        <li><code>HKn_Betriebsart heating,standby</code> <br>
            Sets <code>HKn_Betriebsart</code> to <code>heating</code> or <code>standby</code>.</li>
        <li><code>WW_Betriebsart balanced,off</code> <br>
            Sets <code>WW_Betriebsart</code> to <code>balanced</code> or <code>off</code>.</li>
        <li><code>HKn_Soll_Temp_comfort_aktiv activate,deactivate</code> <br>
            Activate/deactivate comfort temperature for HKn.</li>
        <li><code>HKn_Soll_Temp_comfort targetTemperature</code><br>
            Set comfort target temperature for HKn.</li>
        <li><code>HKn_Soll_Temp_eco_aktiv activate,deactivate</code><br>
            Activate/deactivate eco temperature for HKn.</li>
        <li><code>HKn_Soll_Temp_normal targetTemperature</code><br>
            Sets the normal target temperature for HKn, where <code>targetTemperature</code> is an
            integer between 3 and 37.</li>
        <li><code>HKn_Soll_Temp_reduziert targetTemperature</code><br>
            Sets the reduced target temperature for HKn, where <code>targetTemperature</code> is an
            integer between 3 and 37.</li>
        <li><code>HKn_Name name</code><br>
            Sets the name of the circuit for HKn.</li>      
        <li><code>WW_einmaliges_Aufladen activate,deactivate</code><br>
            Activate or deactivate one-time charge for hot water.</li>
        <li><code>WW_Zirkulationspumpe_Zeitplan schedule</code><br>
            Sets the schedule in JSON format for the hot water circulation pump.</li>
        <li><code>WW_Zeitplan schedule</code> <br>
            Sets the schedule in JSON format for hot water.</li>
        <li><code>WW_Solltemperatur targetTemperature</code><br>
            <code>targetTemperature</code> is an integer between 10 and 60.<br>
            Sets hot water temperature to <code>targetTemperature</code>.</li>    
        <li><code>Urlaub_Start_Zeit start</code><br>
            Set holiday start time.<br>
            <code>start</code> has to look like this: <code>2019-02-02</code>.</li>
        <li><code>Urlaub_Ende_Zeit end</code><br>
            Set holiday end time.<br>
            <code>end</code> has to look like this: <code>2019-02-16</code>.</li>
        <li><code>Urlaub_stop</code> <br>
            Remove holiday start and end time.</li>
    </ul>
    </ul>
    <br>

    <a name="vitoconnectget"></a>
    <b>Get</b><br>
    <ul>
        Nothing to get here. 
    </ul>
    <br>
    
<a name="vitoconnect-attr"></a>
<b>Attributes</b>
<ul>
    <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
    <br><br>
    See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about the <code>attr</code> command.
    <br><br>
    Attributes:
    <ul>
        <a id="vitoconnect-attr-disable"></a>
        <li><i>disable</i>:<br>         
            Stop communication with the Viessmann server.
        </li>
        <a id="vitoconnect-attr-verbose"></a>
        <li><i>verbose</i>:<br>         
            Set the verbosity level.
        </li>           
        <a id="vitoconnect-attr-vitoconnect_raw_readings"></a>
        <li><i>vitoconnect_raw_readings</i>:<br>         
            Create readings with plain JSON names like <code>heating.circuits.0.heating.curve.slope</code> instead of German identifiers (old mapping), mapping attribute, or translation attribute.<br>
            When using raw readings, setters will be created dynamically matching the raw readings (new).<br>
            I recommend this setting since you get everything as dynamically as possible from the API.<br>
            You can use <code>stateFormat</code> or <code>userReadings</code> to display your important readings with a readable name.<br>
            If <code>vitoconnect_raw_readings</code> is set, no mapping will be used.
        </li>
        <a id="vitoconnect-attr-vitoconnect_disable_raw_readings"></a>
        <li><i>vitoconnect_disable_raw_readings</i>:<br>         
            This setting will disable the additional generation of raw readings.<br>
            This means you will only see the readings that are explicitly mapped in your chosen mapping.<br>
            This setting will not be active if you also choose <code>vitoconnect_raw_readings = 1</code>.
        </li>
        <a id="vitoconnect-attr-vitoconnect_gw_readings"></a>
        <li><i>vitoconnect_gw_readings</i>:<br>         
            Create readings from the gateway, including information if you have more than one gateway.
        </li>
        <a id="vitoconnect-attr-vitoconnect_actions_active"></a>
        <li><i>vitoconnect_actions_active</i>:<br>
            Create readings for actions, e.g., <code>heating.circuits.0.heating.curve.setCurve.setURI</code>.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mappings"></a>
        <li><i>vitoconnect_mappings</i>:<br>
            Define your own mapping of key-value pairs instead of using the built-in ones. The format has to be:<br>
            <code>mapping<br>
            {  'device.serial.value' => 'device_serial',<br>
                'heating.boiler.sensors.temperature.main.status' => 'status',<br>
                'heating.boiler.sensors.temperature.main.value' => 'haupt_temperatur'}</code><br>
            Mapping will be preferred over the old mapping.
        </li>
        <a id="vitoconnect-attr-vitoconnect_translations"></a>
        <li><i>vitoconnect_translations</i>:<br>
            Define your own translation; it will translate every word part by part. The format has to be:<br>
            <code>translation<br>
            {  'device' => 'gerät',<br>
                'messages' => 'nachrichten',<br>
                'errors' => 'fehler'}</code><br>
            Translation will be preferred over mapping and old mapping.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mapping_roger"></a>
        <li><i>vitoconnect_mapping_roger</i>:<br>
            Use the mapping from Roger from 8. November (<a href="https://forum.fhem.de/index.php?msg=1292441">https://forum.fhem.de/index.php?msg=1292441</a>) instead of the SVN mapping.
        </li>
        <a id="vitoconnect-attr-vitoconnect_serial"></a>
        <li><i>vitoconnect_serial</i>:<br>
            This handling will now take place during the initialization of the FHEM device.<br>
            You will be notified that you have to execute <code>set &lt;name&gt; selectDevice &lt;serial&gt;</code>.<br>
            The possible serials will be prefilled.<br>
            You do not need to set this attribute manually.<br>
            Defines the serial of the Viessmann device to be used.<br>
            If there is only one Viessmann device, you do not have to care about it.<br>
        </li>
        <a id="vitoconnect-attr-vitoconnect_installationID"></a>
        <li><i>vitoconnect_installationID</i>:<br>
            This handling will now take place during the initialization of the FHEM device.<br>
            You will be notified that you have to execute <code>set &lt;name&gt; selectDevice &lt;serial&gt;</code>.<br>
            The possible serials will be prefilled.<br>
            You do not need to set this attribute manually.<br>
            Defines the installationID of the Viessmann device to be used.<br>
            If there is only one Viessmann device, you do not have to care about it.<br>
        </li>
        <a id="vitoconnect-attr-vitoconnect_timeout"></a>
        <li><i>vitoconnect_timeout</i>:<br>
            Sets a timeout for the API call.
        </li>
        <a id="vitoconnect-attr-vitoconnect_device"></a>
        <li><i>vitoconnect_device</i>:<br>
            You can define the device 0 (default) or 1. I cannot test this because I have only one device.
        </li>
    </ul>
</ul>

=end html
=begin html_DE

<a id="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implementiert ein Gerät für die Viessmann API
    <a href="https://www.viessmann.de/de/viessmann-apps/vitoconnect.html">Vitoconnect100</a> oder E3 One Base,
    basierend auf der Untersuchung von
    <a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a><br>
    
    Es werden Benutzername und Passwort des ViCare App-Kontos benötigt.<br>
    Zusätzlich auch eine Client-ID, siehe set apiKey.<br>
     
    Weitere Details sind im <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (deutsch)</a> zu finden.<br><br>
     
    Für die Nutzung werden die folgenden Bibliotheken benötigt:
    <ul>
    <li>Path::Tiny</li>
    <li>JSON</li>
    <li>JSON::XS</li>
    <li>DateTime</li>
    </ul>   
         
    Die Bibliotheken können mit dem Befehl <code>sudo apt install libtypes-path-tiny-perl libjson-perl libdatetime-perl</code> installiert werden oder über cpan. Andernfalls tritt eine Fehlermeldung "cannot load module vitoconnect" auf.
     
    <br><br>
    <a id="vitoconnect-define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code><br>
        Es wird empfohlen, zunächst ein falsches Passwort zu verwenden und dieses später zu ändern, da es in der Detailansicht des Geräts sichtbar ist.
        <br><br>
        Beispiel:<br>
        <code>define vitoconnect vitoconnect user@mail.xx fakePassword 60</code><br>
        <code>set vitoconnect password correctPassword 60</code>
        <code>set vitoconnect apiKey Client-ID</code>
        <br><br>
    </ul>
    <br>
    
    <a id="vitoconnect-set"></a>
    <b>Set</b><br>
    <ul>
        <a id="vitoconnect-set-update"></a>
        <li><code>update</code><br>
            Liest sofort die aktuellen Werte aus.</li>
        <a id="vitoconnect-set-selectDevice"></a>
        <li><code>selectDevice</code><br>
            Wird benötigt, wenn mehr als ein Viessmann Gateway/Device vorhanden ist. Ein Viessmann Gerät muss für jedes FHEM Gerät ausgewählt werden.<br>
            Der Set-Befehl muss ausgeführt werden, nachdem die Viessmann Geräte im Gerätestatus vorgefüllt sind.<br>
            Bei Auswahl eines Viessmann Geräts und Ausführung des Set-Befehls werden die Attribute vitoconnect_serial und vitoconnect_installationId gefüllt.<br>
            Bei nur einem Viessmann Gerät erfolgt dies automatisch.<br>
            Es wird empfohlen, die Änderungen nach der Initialisierung oder dem Set zu speichern.
        </li>
        <a id="vitoconnect-set-clearReadings"></a>
        <li><code>clearReadings</code><br>
            Löscht sofort alle Werte.</li>
        <a id="vitoconnect-set-clearMappedErrors"></a>
        <li><code>clearMappedErrors</code><br>
            Löscht sofort alle gemappten Fehler Werte.</li> 
        <a id="vitoconnect-set-password"></a>
        <li><code>password passwd</code><br>
            Speichert das Passwort im Schlüsselbund.</li>
        <a id="vitoconnect-set-logResponseOnce"></a>
        <li><code>logResponseOnce</code><br>
            Speichert die JSON-Antwort des Viessmann-Servers in den Dateien entities.json, gw.json und actions.json im FHEM-Log-Verzeichnis.
            Wenn mehrere Gateways vorhanden sind, wird die Seriennummer des Gateways an die Dateinamen angehängt.</li>
        <a id="vitoconnect-set-apiKey"></a>
        <li><code>apiKey</code><br>
            Ein API-Schlüssel muss unter https://developer.viessmann.com/ erstellt werden.
            Dazu ein Konto anlegen, einen neuen Client hinzufügen (Google reCAPTCHA deaktivieren, Redirect URI = http://localhost:4200/).
            Die Client-ID muss als apiKey hier eingefügt werden.</li>
        <li><code>Die Setter für das Gerät hängen von der gewählten Mappingmethode ab, die durch die Attribute vitoconnect_raw_readings oder vitoconnect_mapping_roger gesteuert wird.</code><br>
            Neue Setter werden verwendet, wenn vitoconnect_raw_readings = 1 gesetzt ist.
            Standardmäßig wird das statische Mapping der alten SVN-Version verwendet.
            Die folgenden Setter sind verfügbar:
        </li>
        <li><code>HKn_Heizkurve_Niveau shift</code><br>
            Setzt die Verschiebung der Heizkurve für HKn.</li>
        <li><code>HKn_Heizkurve_Steigung slope</code><br>
            Setzt die Steigung der Heizkurve für HKn.</li>
        <li><code>HKn_Urlaub_Start_Zeit start</code><br>
            Setzt die Urlaubsstartzeit für HKn.<br>
            Start muss im Format: 2019-02-02 angegeben werden.</li>
        <li><code>HKn_Urlaub_Ende_Zeit end</code><br>
            Setzt die Urlaubsendzeit für HKn.<br>
            Ende muss im Format: 2019-02-16 angegeben werden.</li>
        <li><code>HKn_Urlaub_stop</code><br>
            Entfernt die Urlaubsstart- und Endzeit für HKn.</li>
        <li><code>HKn_Zeitsteuerung_Heizung schedule</code><br>
            Setzt den Heizplan für HKn im JSON-Format.<br>
            Beispiel: {"mon":[],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[],"sun":[]} für keinen Betrieb und {"mon":[{"mode":"on","start":"00:00","end":"24:00","position":0}],...} für 24/7 Betrieb.</li>
        <li><code>HKn_Betriebsart heating,standby</code><br>
            Setzt den Betriebsmodus für HKn auf heizen oder standby.</li>
        <li><code>WW_Betriebsart balanced,off</code><br>
            Setzt den Betriebsmodus für Warmwasser auf ausgeglichen oder aus.</li>
        <li><code>HKn_Soll_Temp_comfort_aktiv activate,deactivate</code><br>
            Aktiviert/deaktiviert die Komforttemperatur für HKn.</li>
        <li><code>HKn_Soll_Temp_comfort targetTemperature</code><br>
            Setzt die Komfortzieltemperatur für HKn.</li>
        <li><code>HKn_Soll_Temp_eco_aktiv activate,deactivate</code><br>
            Aktiviert/deaktiviert die Ökotemperatur für HKn.</li>
        <li><code>HKn_Soll_Temp_normal targetTemperature</code><br>
            Setzt die normale Zieltemperatur für HKn (zwischen 3 und 37 Grad Celsius).</li>
        <li><code>HKn_Soll_Temp_reduziert targetTemperature</code><br>
            Setzt die reduzierte Zieltemperatur für HKn (zwischen 3 und 37 Grad Celsius).</li>
        <li><code>HKn_Name name</code><br>
            Setzt den Namen des Kreislaufs für HKn.</li>      
        <li><code>WW_einmaliges_Aufladen activate,deactivate</code><br>
            Aktiviert oder deaktiviert einmaliges Aufladen für Warmwasser.</li>
        <li><code>WW_Zirkulationspumpe_Zeitplan schedule</code><br>
            Setzt den Zeitplan im JSON-Format für die Warmwasserzirkulationspumpe.</li>
        <li><code>WW_Zeitplan schedule</code><br>
            Setzt den Zeitplan im JSON-Format für Warmwasser.</li>
        <li><code>WW_Solltemperatur targetTemperature</code><br>
            Setzt die Warmwassertemperatur (zwischen 10 und 60 Grad Celsius) auf targetTemperature.</li>    
        <li><code>Urlaub_Start_Zeit start</code><br>
            Setzt die Urlaubsstartzeit.<br>
            Start muss im Format: 2019-02-02 angegeben werden.</li>
        <li><code>Urlaub_Ende_Zeit end</code><br>
            Setzt die Urlaubsendzeit.<br>
            Ende muss im Format: 2019-02-16 angegeben werden.</li>
        <li><code>Urlaub_stop</code><br>
            Entfernt die Urlaubsstart- und Endzeit.</li>
    </ul>
</ul>
<br>
    <a name="vitoconnectget"></a>
      <b>Get</b><br>
        <ul>
            Keine Daten zum Abrufen verfügbar.
        </ul>
<br>

<a name="vitoconnect-attr"></a>
<b>Attributes</b>
<ul>
    <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
    <br><br>
    Weitere Informationen zum attr-Befehl sind in der <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> zu finden.
    <br><br>
    Attribute:
    <ul>
        <a id="vitoconnect-attr-disable"></a>
        <li><i>disable</i>:<br>         
            Stoppt die Kommunikation mit dem Viessmann-Server.
        </li>
        <a id="vitoconnect-attr-verbose"></a>
        <li><i>verbose</i>:<br>         
            Setzt das Verbositätslevel.
        </li>
        <a id="vitoconnect-attr-vitoconnect_raw_readings"></a>
        <li><i>vitoconnect_raw_readings</i>:<br>         
            Erstellt Readings mit einfachen JSON-Namen wie 'heating.circuits.0.heating.curve.slope' anstelle von deutschen Bezeichnern (altes Mapping), Mapping-Attributen oder Übersetzungen.<br>
            Wenn raw Readings verwendet werden, werden die Setter dynamisch erstellt, die den raw Readings entsprechen.<br>
            Diese Einstellung wird empfohlen, um die Daten so dynamisch wie möglich von der API zu erhalten.<br>
            stateFormat oder userReadings können verwendet werden, um wichtige Readings mit einem lesbaren Namen anzuzeigen.<br>
            Wenn vitoconnect_raw_readings gesetzt ist, wird kein Mapping verwendet.
        </li>
        <a id="vitoconnect-attr-vitoconnect_disable_raw_readings"></a>
        <li><i>vitoconnect_disable_raw_readings</i>:<br>
            Deaktiviert die zusätzliche Generierung von raw Readings.<br>
            Es werden nur die Messwerte angezeigt, die im gewählten Mapping explizit zugeordnet sind.<br>
            Diese Einstellung wird nicht aktiv, wenn vitoconnect_raw_readings = 1 gesetzt ist.
        </li>
        <a id="vitoconnect-attr-vitoconnect_gw_readings"></a>
        <li><i>vitoconnect_gw_readings</i>:<br>         
            Erstellt ein Reading vom Gateway, einschließlich Informationen, wenn mehrere Gateways vorhanden sind.
        </li>
        <a id="vitoconnect-attr-vitoconnect_actions_active"></a>
        <li><i>vitoconnect_actions_active</i>:<br>
            Erstellt Readings für Aktionen, z.B. 'heating.circuits.0.heating.curve.setCurve.setURI'.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mappings"></a>
        <li><i>vitoconnect_mappings</i>:<br>
            Definiert eigene Zuordnungen von Schlüssel-Wert-Paaren anstelle der eingebauten Zuordnungen. Das Format muss wie folgt sein:<br>
            mapping<br>
            {  'device.serial.value' => 'device_serial',<br>
                'heating.boiler.sensors.temperature.main.status' => 'status',<br>
                'heating.boiler.sensors.temperature.main.value' => 'haupt_temperatur'}<br>
            Die eigene Zuordnung hat Vorrang vor der alten Zuordnung.
        </li>
        <a id="vitoconnect-attr-vitoconnect_translations"></a>
        <li><i>vitoconnect_translations</i>:<br>
            Definiert eigene Übersetzungen für Wörter, die dann Teil für Teil übersetzt werden. Das Format muss wie folgt sein:<br>
            translation<br>
            {  'device' => 'gerät',<br>
                'messages' => 'nachrichten',<br>
                'errors' => 'fehler'}<br>
            Die eigene Übersetzung hat Vorrang vor der Zuordnung und der alten Zuordnung.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mapping_roger"></a>
        <li><i>vitoconnect_mapping_roger</i>:<br>
            Verwendet das Mapping von Roger vom 8. November (https://forum.fhem.de/index.php?msg=1292441) anstelle der SVN-Zuordnung.
        </li>
        <a id="vitoconnect-attr-vitoconnect_serial"></a>
        <li><i>vitoconnect_serial</i>:<br>
            Dieses Attribut wird bei der Initialisierung des FHEM-Geräts gesetzt.<br>
            Der Befehl <code>set <name> selectDevice <serial></code> muss ausgeführt werden, wenn mehrere Seriennummern verfügbar sind.<br>
            Dieses Attribut muss nicht manuell gesetzt werden, wenn nur ein Viessmann Gerät vorhanden ist.
        </li>
        <a id="vitoconnect-attr-vitoconnect_installationID"></a>
        <li><i>vitoconnect_installationID</i>:<br>
            Dieses Attribut wird bei der Initialisierung des FHEM-Geräts gesetzt.<br>
            Der Befehl <code>set <name> selectDevice <serial></code> muss ausgeführt werden, wenn mehrere Seriennummern verfügbar sind.<br>
            Dieses Attribut muss nicht manuell gesetzt werden, wenn nur ein Viessmann Gerät vorhanden ist.
        </li>
        <a id="vitoconnect-attr-vitoconnect_timeout"></a>
        <li><i>vitoconnect_timeout</i>:<br>
            Setzt ein Timeout für den API-Aufruf.
        </li>
        <a id="vitoconnect-attr-vitoconnect_device"></a>
        <li><i>vitoconnect_device</i>:<br>
            Es kann zwischen den Geräten 0 (Standard) oder 1 gewählt werden. Diese Funktion konnte nicht getestet werden, da nur ein Gerät verfügbar ist.
        </li>
    </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 98_vitoconnect.pm
{
  "abstract": "Using the viessmann API to read and set data",
  "x_lang": {
    "de": {
      "abstract": "Benutzt die Viessmann API zum lesen und setzen von daten"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "heating",
    "burner",
    "heatpump",
    "gas",
    "oil"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Stefan Runge <stefanru@gmx.de>"
  ],
  "x_fhem_maintainer": [
    "Stefanru"
  ],
  "x_fhem_maintainer_github": [
    "stefanru1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "POSIX": 0,
        "GPUtils": 0,
        "Encode": 0,
        "Blocking": 0,
        "Color": 0,
        "utf8": 0,
        "HttpUtils": 0,
        "JSON": 4.020,
        "FHEM::SynoModules::SMUtils": 1.0270,
        "Time::HiRes": 0,
        "MIME::Base64": 0,
        "Math::Trig": 0,
        "List::Util": 0,
        "Storable": 0
      },
      "recommends": {
        "FHEM::Meta": 0,
        "FHEM::Utility::CTZ": 1.00,
        "DateTime": 0,
        "DateTime::Format::Strptime": 0,
        "AI::DecisionTree": 0,
        "Data::Dumper": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/Vitoconnect",
      "title": "vitoconnect"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/98_vitoconnect.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/98_vitoconnect.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut
