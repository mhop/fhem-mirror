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
sub vitoconnect_Get;                    # Implementierung get-Befehle
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

sub vitoconnect_actionTimerWrapper;     # Send call to API with timer
sub vitoconnect_action;                 # Send call to API

sub vitoconnect_FW_detailFn;            # Paint SVG
sub vitoconnect_fmt_fallback;           # Get numbers for SVG
sub vitoconnect_GetHtml;                # Return html for ftui

sub vitoconnect_mapCodeText;            # Resolve Message/Error code for OneBase not in API
sub vitoconnect_mapSeverityPrefix;      # Resolve Severity for OneBase not in API
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
use utf8; # test

eval "use FHEM::Meta;1"                   or my $modMetaAbsent = 1;                  ## no critic 'eval'
use FHEM::SynoModules::SMUtils qw (
                                   moduleVersion
                                  );                                                 # Hilfsroutinen Modul

my %vNotesIntern = (
  "1.1.1"  => "25.02.2026  Small fixes",
  "1.1.0"  => "24.02.2026  Small adaptions to SVG",
  "1.0.9"  => "17.02.2026  Special SVG handling for vitocal 200S",
  "1.0.8"  => "06.02.2026  SVG mapping with alternative readings",
  "1.0.7"  => "03.02.2026  HTML for ftui",
  "1.0.6"  => "30.01.2026  Messages and SVG Kaeltegreislauf",
  "1.0.5"  => "05.01.2026  Auth and token requests changed to V3 API",
  "1.0.4"  => "04.01.2026  Log response body in case off access token error",
  "1.0.3"  => "11.12.2025  asSingleValue fixed – this time for real",
  "1.0.2"  => "08.12.2025  Power reading asSingleValue finally fixed",
  "1.0.1"  => "29.11.2025  fix power reading logging",
  "1.0.0"  => "28.11.2025  power reading fixed again",
  "0.9.9"  => "28.11.2025  EOL from v1 API on 17.11.2025 changed to v2",
  "0.9.8"  => "28.11.2025  power reading fixed",
  "0.9.7"  => "02.11.2025  order of lists fixed",
  "0.9.6"  => "31.10.2025  One Base Message lists and translations",
  "0.9.5"  => "15.10.2025  Fix duplicate timer in case of password update (getCode)",
  "0.9.4"  => "15.10.2025  More logging for timers",
  "0.9.3"  => "15.10.2025  URL to dev portal updated",
  "0.9.2"  => "15.09.2025  Fix Not a HASH reference at ./FHEM/98_vitoconnect.pm line 3818 when set action error",
  "0.9.1"  => "11.09.2025  In case of set action when token is expired get new token and try again",
  "0.9.0"  => "09.03.2025  New api and iam URL (viessmann-climatesolutions.com)",
  "0.8.7"  => "09.03.2025  Fix return value when using SVN or Roger",
  "0.8.6"  => "24.02.2025  Adapt schedule data before sending",
  "0.8.5"  => "24.02.2025  fix error when calling setter from FHEMWEB",
  "0.8.4"  => "24.02.2025  also order mode, start, end, position in schedule",
  "0.8.3"  => "23.02.2025  fix order of days for type schedule readings",
  "0.8.2"  => "22.02.2025  improved State reading in case of unknown error",
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
my $apiBaseURL    = "https://api.viessmann-climatesolutions.com";
my $iamBaseURL    = "https://iam.viessmann-climatesolutions.com";
my $equipmentURL  = "$apiBaseURL/iot/v2/equipment/";
my $featureURL     = "$apiBaseURL/iot/v2/features/";
my $authorizeURL  = "$iamBaseURL/idp/v3/authorize";
my $tokenURL      = "$iamBaseURL/idp/v3/token";
my $errorURL_V3   = "$apiBaseURL/service-documents/v3/error-database";

my $RequestListMapping; # Über das Attribut Mapping definierte Readings zum überschreiben der RequestList
my %translations;       # Über das Attribut translations definierte Readings zum überschreiben der RequestList

# Meldungs / Fehler Mapping für One Base geräte
my %viessmann_code_text = (
    # Status codes (S-codes) - typically operational states
    # Heating and Cooling Operations
    'S.1' => 'Netzspannung eingeschaltet',
    'S.10' => 'Standby - Bereitschaftsmodus',
    'S.11' => 'Kompressor läuft - Heizbetrieb',
    'S.12' => 'Kompressor läuft - Kühlbetrieb',
    'S.13' => 'Abtauung aktiv',
    'S.14' => 'Notbetrieb/Störung',
    'S.15' => 'Verdichter-Anlaufverzögerung',

    # Temperature Management
    'S.20' => 'Vorlauftemperatur zu hoch',
    'S.21' => 'Vorlauftemperatur zu niedrig',
    'S.22' => 'Rücklauftemperatur zu hoch',
    'S.23' => 'Rücklauftemperatur zu niedrig',
    'S.24' => 'Außentemperatur zu niedrig',
    'S.25' => 'Außentemperatur zu hoch',

    # Pump Operations
    'S.30' => 'Umwälzpumpe läuft',
    'S.31' => 'Umwälzpumpe aus',
    'S.32' => 'Pumpe Heizkreis 1 läuft',
    'S.33' => 'Pumpe Heizkreis 2 läuft',
    'S.34' => 'Ladepumpe läuft',
    'S.35' => 'Zirkulationspumpe läuft',

    # Heat Generator
    'S.40' => 'Wärmepumpe läuft',
    'S.41' => 'Zusatzheizung aktiv',
    'S.42' => 'Elektrische Zusatzheizung aktiv',
    'S.43' => 'Bivalente Heizung aktiv',

    # Hot Water
    'S.50' => 'Warmwasserbereitung',
    'S.51' => 'Warmwasser-Nachladung',
    'S.52' => 'Legionellenschutz aktiv',
    'S.53' => 'Warmwasser-Zirkulation',

    # Additional Status Codes from PDF
    'S.60' => 'Sommerbetrieb aktiv (Sparfunktion Aussentemperatur)',
    'S.61' => 'Abtauung laeuft',
    'S.62' => 'Abtauung beendet',
    'S.63' => 'Verdampfer-Abtauung',
    'S.70' => 'Testbetrieb',
    'S.71' => 'Relaistest',
    'S.72' => 'Sensortest',
    'S.74' => 'Heizunterdrueckung Heizen bei Trinkwassererwaermung durch Sonnenkollektoren',
    'S.75' => 'Zirkulationspumpe aktiv',
    'S.80' => 'Kommunikation OK',
    'S.81' => 'Kommunikation gestoert',
    'S.82' => 'Bus-Kommunikation aktiv',
    'S.88' => 'Solarkreispumpe aktiv',
    'S.89' => 'Sonnenkollektoren in Stagnation',
    'S.90' => 'EVU-Sperre aktiv',
    'S.91' => 'Smart Grid aktiv',
    'S.92' => 'PV-Ueberschuss-Nutzung',
    'S.100' => 'Heizen - Normalbetrieb',
    'S.101' => 'Heizen - Reduzierter Betrieb',
    'S.102' => 'Heizen - Komfortbetrieb',
    'S.103' => 'Heizen - Eco-Betrieb',
    'S.104' => 'Heizen - Partybetrieb',
    'S.105' => 'Heizen - Urlaubsbetrieb',
    'S.110' => 'Kuehlen - Normalbetrieb',
    'S.111' => 'Kuehlen - Reduzierter Betrieb',
    'S.112' => 'Initialisierung 4/3-Wege-Ventil',
    'S.113' => '4/3-Wege-Ventil schaltet in Richtung Trinkwassererwaermung',
    'S.114' => '4/3-Wege-Ventil schaltet in Richtung Heiz-/Kuehlkreis 1',
    'S.115' => '4/3-Wege-Ventil in Position Trinkwassererwaermung',
    'S.116' => '4/3-Wege-Ventil in Position Heiz-/Kuehlkreis 1',
    'S.117' => '4/3-Wege-Ventil in Position Heiz-/Kuehlkreis 2',
    'S.118' => '4/3-Wege-Ventil in Position Integrierter Pufferspeicher',
    'S.119' => 'Verdichter-Mindestlaufzeit',
    'S.120' => 'Smart Grid: Normalbetrieb aktiv',
    'S.121' => 'Smart Grid: Empfohlener Betrieb aktiv',
    'S.122' => 'Smart Grid: Erzwungener Betrieb aktiv',
    'S.123' => 'Waermepumpe aus',
    'S.124' => 'Waermepumpe Vorlaufphase',
    'S.125' => 'Waermepumpe im Heizbetrieb',
    'S.126' => 'Waermepumpe im Kuehlbetrieb',
    'S.127' => 'Waermepumpe: Abtauen vorbereiten',
    'S.128' => 'Waermepumpe im Abtaubetrieb',
    'S.129' => 'Waermepumpe Nachlaufphase',
    'S.130' => 'Heizwasser-Durchlauferhitzer ausgeschaltet',
    'S.131' => 'Heizwasser-Durchlauferhitzer: Stufe 1 aktiv',
    'S.132' => 'Heizwasser-Durchlauferhitzer: Stufe 2 aktiv',
    'S.133' => 'Heizwasser-Durchlauferhitzer: Stufe 3 aktiv',
    'S.134' => '4/3-Wege-Ventil Leerlauf',
    'S.135' => '4/3-Wege-Ventil Abtauen',
    'S.136' => '4/3-Wege-Ventil Raumbeheizung/Raumkuehlung',
    'S.137' => 'Heizbetrieb in Anlaufphase',
    'S.138' => 'Heizbetrieb aktiv',
    'S.139' => 'Heizbetrieb inaktiv',
    'S.141' => 'Trinkwassererwaermung aktiv',
    'S.142' => 'Trinkwassererwaermung inaktiv',
    'S.143' => 'Kuehlbetrieb angefordert',
    'S.144' => 'Kuehlbetrieb aktiv',
    'S.145' => 'Kuehlbetrieb inaktiv',
    'S.146' => 'Abtauen angefordert',
    'S.147' => 'Waermebereitstellung fuer Abtauen aktiv',
    'S.148' => 'Abtauen ueber Waermepumpe aktiv',
    'S.149' => 'Abtauen ueber Waermepumpe inaktiv',
    'S.153' => 'Regelung im Standby',
    'S.160' => 'Lueftung - Stufe 1',
    'S.161' => 'Befuellung aktiv',
    'S.162' => 'Entlueftung aktiv',
    'S.163' => 'Waermepumpe: Systemstatus inaktiv',
    'S.164' => 'Waermepumpe: Systemstatus Wartung Standby',
    'S.165' => 'Waermepumpe: Systemstatus Regelung',
    'S.167' => 'Aktorentest aktiv',
    'S.168' => 'Lueftungsbypass offen',
    'S.170' => 'Systemcheck laeuft',
    'S.171' => 'Initialisierung',
    'S.172' => 'Software-Update',
    'S.176' => 'Waermepumpenregelung: Abtauen angefordert',
    'S.180' => 'Betriebsstundenzaehler',
    'S.181' => 'Passiver Frostschutz Heiz-/Kuehlkreis 1 eingeschaltet',
    'S.182' => 'Passiver Frostschutz Heiz-/Kuehlkreis 2 eingeschaltet',
    'S.183' => 'Passiver Frostschutz Heiz-/Kuehlkreis 3 eingeschaltet',
    'S.184' => 'Passiver Frostschutz Heiz-/Kuehlkreis 4 eingeschaltet',
    'S.185' => 'Passiver Frostschutz Heizwasser-Durchlauferhitzer eingeschaltet',
    'S.186' => 'Passiver Frostschutz Speicher-Wassererwärmer eingeschaltet',
    'S.187' => 'Passiver Frostschutz Waermepumpe eingeschaltet',
    'S.188' => 'Passiver Frostschutz externer Heiz-/Kuehlwasser-Pufferspeicher eingeschaltet',
    'S.189' => 'Passiver Frostschutz externer Heizwasser-Pufferspeicher eingeschaltet',
    'S.190' => 'Passiver Frostschutz externer Kuehlwasser-Pufferspeicher eingeschaltet',
    'S.191' => 'Filter reinigen',
    'S.192' => 'Wartung faellig',
    'S.193' => 'Anforderung externer Waermeerzeuger ueber potenzialfreien Schaltkontakt',
    'S.195' => 'Smart Grid: EVU-Sperre aktiv',
    'S.196' => 'EVU-Sperre aktiv',
    'S.197' => 'Waermeanforderung Heiz-/Kuehlkreis 1',
    'S.198' => 'Kuehlanforderung Heiz-/Kuehlkreis 1',
    'S.199' => 'Waermeanforderung Heiz-/Kuehlkreis 2',
    'S.205' => 'Anforderung externer Heizwasser-Pufferspeicher',
    'S.206' => 'Anforderung externer Kuehlwasser-Pufferspeicher',
    'S.207' => 'Anforderung Trinkwassererwaermung',
    'S.208' => 'Erwaermung integrierter Pufferspeicher aktiv',
    'S.209' => 'Abbruch Befuellfunktion',
    'S.210' => 'Abbruch Entlueftungsfunktion',
    'S.211' => 'Befuellvorgang abgeschlossen',
    'S.212' => 'Entlueftungsvorgang abgeschlossen',
    'S.213' => 'Inbetriebnahme-Assistent aktiv',
    'S.214' => 'Abbruch Inbetriebnahme',
    'S.215' => 'Inbetriebnahme abgeschlossen',
    'S.216' => 'Aktorentest aktiv',
    'S.217' => 'Heizwasser-Durchlauferhitzer: Stufe 1 inaktiv',
    'S.218' => 'Heizwasser-Durchlauferhitzer: Stufe 2 inaktiv',
    'S.219' => 'Heizwasser-Durchlauferhitzer: Stufe 3 inaktiv',
    'S.220' => 'Kaeltekreis ausgeschaltet',
    'S.221' => 'Kaeltekreis Startphase Heizbetrieb',
    'S.222' => 'Kaeltekreis Startphase Kuehlbetrieb',
    'S.223' => 'Kaeltekreis Startphase Abtaubetrieb',
    'S.224' => 'Kaeltekreis im Heizbetrieb',
    'S.225' => 'Kaeltekreis im Kuehlbetrieb',
    'S.226' => 'Kaeltekreis im Abtaubetrieb im Betriebsprogramm Frostschutz',
    'S.227' => 'Kaeltekreis im Abtaubetrieb bei Regelbetrieb',
    'S.228' => 'Kaeltekreis Abschaltsignal',
    'S.229' => 'Kaeltekreisregler im Uebergang von Heizbetrieb zu Kuehlbetrieb',
    'S.230' => 'Kaeltekreisregler im Uebergang von Kuehlbetrieb zu Heizbetrieb',
    'S.231' => 'Kaeltekreisregler im Uebergang von Abtaubetrieb zu Heizbetrieb',
    'S.240' => 'Kaeltekreisregler im Standby',
    'S.392' => 'Kaeltekreisregler im Uebergang von Heizbetrieb zu Abtaubetrieb',
    'S.393' => 'Aktiver Frostschutz Heiz-/Kuehlkreis 1 eingeschaltet',
    'S.394' => 'Aktiver Frostschutz Heiz-/Kuehlkreis 2 eingeschaltet',
    'S.395' => 'Aktiver Frostschutz Heiz-/Kuehlkreis 3 eingeschaltet',
    'S.396' => 'Aktiver Frostschutz Heiz-/Kuehlkreis 4 eingeschaltet',
    'S.397' => 'Aktiver Frostschutz Heizwasser-Durchlauferhitzer eingeschaltet',
    'S.398' => 'Aktiver Frostschutz Speicher-Wassererwärmer eingeschaltet',
    'S.399' => 'Aktiver Frostschutz Waermepumpe eingeschaltet',
    'S.400' => 'Aktiver Frostschutz externer Heiz-/Kuehlwasser-Pufferspeicher eingeschaltet',
    'S.401' => 'Aktiver Frostschutz externer Heizwasser-Pufferspeicher eingeschaltet',
    'S.402' => 'Aktiver Frostschutz externer Kuehlwasser-Pufferspeicher eingeschaltet',
    # Quelle: vieventlog (mschneider82)
    'S.427' => 'Leistungsbegrenzung durch den Netzbetreiber nach § 14a EnWG',

    # Missing codes from PDF
    'S.140' => 'Trinkwassererwaermung angefordert',
    'S.150' => 'Abtauen ueber Heiz-/Kuehlkreis 1 oder externen Heizwasser-Pufferspeicher (falls vorhanden) in Vorbereitung',
    'S.151' => 'Abtauen ueber Heiz-/Kuehlkreis 1 oder externen Heizwasser-Pufferspeicher (falls vorhanden) aktiv',
    'S.152' => 'Abtauen ueber Heiz-/Kuehlkreis 1 oder externen Heizwasser-Pufferspeicher (falls vorhanden) inaktiv',
    'S.200' => 'Kuehlanforderung Heiz-/Kuehlkreis 2',
    'S.201' => 'Waermeanforderung Heiz-/Kuehlkreis 3',
    'S.202' => 'Kuehlanforderung Heiz-/Kuehlkreis 3',
    'S.203' => 'Waermeanforderung Heiz-/Kuehlkreis 4',
    'S.204' => 'Kuehlanforderung Heiz-/Kuehlkreis 4',

    # Maintenance codes (P-codes) - maintenance messages
    'P.1' => 'Wartung nach Zeitintervall steht bevor',
    'P.4' => 'Heizwasser nachfuellen',
    'P.8' => 'Wartung nach Betriebsstunden steht bevor',
    'P.34' => 'Wartung Heizwasserfilter',
    'P.35' => 'Zeitintervall für Filterwechsel ist abgelaufen',

    # Alert codes (A-codes) - warning messages
    'A.2' => 'Frostschutzgrenze unterschritten',
    'A.11' => 'Anlagendruck zu niedrig',
    'A.12' => 'Batterie im Elektronikmodul HPMU',
    'A.27' => 'Batterie geringer Ladezustand',
    'A.16' => 'Mindestvolumenstrom unterschritten',
    'A.17' => 'Erhöhte Trinkwasserhygiene',
    'A.19' => 'Temperaturwächter hat ausgelöst',
    'A.21' => 'Hydraulischer Anlagendruck',
    'A.62' => 'PWM-Signal Heizkreispumpe Heiz-/Kühlkreis 1',
    'A.63' => 'PWM-Signal Heizkreispumpe Heiz-/Kühlkreis 2',
    'A.65' => 'Heizkreispumpe Heiz-/Kühlkreis 2 läuft trocken',
    'A.66' => 'Heizkreispumpe Heiz-/Kühlkreis 1 läuft nicht',
    'A.68' => 'Heizkreispumpe Heiz-/Kühlkreis 2 läuft nicht',
    'A.70' => 'Filter im Kugelhahn Außeneinheit',
    'A.71' => 'Überstrom am Verdichter',
    'A.72' => 'Strom Leistungsfaktor-Korrekturfilter',
    'A.73' => 'Frequenzabweichung Verdichterdrehzahl',
    'A.74' => 'Druckverlust im Sekundärkreis',
    'A.75' => 'Druckspitzen im Sekundärkreis',
    'A.80' => 'Ventilator blockiert',
    'A.81' => 'Unzureichende Wärmeübertragung Verdampfer',
    'A.82' => 'Fehler Drucksensor CAN-BUS-Teilnehmer',
    'A.83' => 'Signal Speichertemperatursensor fehlerhaft',
    'A.84' => 'Signal Rücklauftemperatursensor Sekundärkreis',
    'A.85' => 'Signal Vorlauftemperatursensor Sekundärkreis',
    'A.86' => 'Signal Vorlauftemperatursensor Heiz-/Kühlkreis 1',
    'A.87' => 'Signal Vorlauftemperatursensor Heiz-/Kühlkreis 2',
    'A.91' => 'Kältekreis vorübergehend aus',
    'A.93' => 'Heißgasdruck nicht plausibel',
    'A.94' => 'Sauggasdruck nicht plausibel',
    'A.96' => 'Luft im Sekundärkreis',
    'A.99' => 'Vorlauftemperatur Sekundärkreis zu niedrig',
    'A.100' => 'Einstellungen gelöscht',
    'A.101' => 'Heißgastemperatur nicht plausibel',
    'A.102' => 'Sauggastemperatur nicht plausibel',
    'A.109' => 'Kesseltemperatur-Istwert zu niedrig',
    'A.110' => 'Temperatur externer Wärmeerzeuger 1',
    'A.111' => 'Temperatur externer Wärmeerzeuger 2',
    'A.130' => 'Warnschwelle Einsatzgrenzen für Kühlbetrieb unterschritten',
    'A.152' => 'Überlastschutz Wallbox nicht aktiv',
    'A.153' => 'Kein PV-optimiertes Laden',
    'A.159' => 'Werkseitige Einstellung Inverter',
    'A.162' => 'Inverter Überspannung Zwischenkreis',
    'A.163' => 'Überspannung im Zwischenkreis Inverter',
    'A.164' => 'Gleichspannung im Zwischenkreis Inverter',
    'A.174' => 'Innenraumtemperatur zu hoch',
    

    # Information codes (I-codes) - informational messages
    'I.9' => 'Estrichtrocknung aktiv',
    'I.10' => 'Laufzeitbegrenzung Trinkwassererwaermung',
    'I.56' => 'Extern Anfordern aktiv',
    'I.57' => 'Extern Sperren aktiv',
    'I.63' => 'Kuehlkreis nicht bereit',
    'I.70' => 'Inverter: Laststrom im Zwischenkreis Inverter zu hoch (Ueberstrom)',
    'I.71' => 'Inverter: Netzspannung zu hoch, Verdichter temporaer aus',
    'I.72' => 'Inverter: Netzspannung zu niedrig, Verdichter temporaer aus',
    'I.73' => 'Inverter: Gleichspannung im Zwischenkreis Inverter zu hoch (Ueberspannung)',
    'I.74' => 'Inverter: Gleichspannung im Zwischenkreis Inverter zu niedrig (Unterspannung), Verdichter temporaer aus',
    'I.75' => 'Inverter: Temperatur am internen Leistungsmodul zu hoch, Verdichter temporaer aus',
    'I.76' => 'Inverter: Zu hohe Temperatur im Leistungsfaktor-Korrekturfilter (PFC), Verdichter temporaer aus',
    'I.77' => 'Inverter: Zu hoher Strom im Leistungsfaktor-Korrekturfilter (PFC), Verdichter temporaer aus',
    'I.78' => 'Inverter: Leistungsreduzierung durch Inverter bei zu hoher Leistungsanforderung (Derating)',
    'I.79' => 'Inverter: Leistungsreduzierung durch Inverter bei zu hoher Leistungsanforderung des Verdichters (Derating)',
    'I.80' => 'Inverter: Leistungsbegrenzung durch Inverter bei zu hoher Leistungsanforderung des Verdichters (Feldschwaechebetrieb)',
    'I.81' => 'Inverter: Leistungsreduzierung durch Inverter bei zu hoher Temperatur am internen Leistungsmodul (Derating)',
    'I.82' => 'Inverter: Leistungsreduzierung durch Inverter bei zu hoher Temperatur am Leistungsfaktor-Korrekturfilter (Derating)',
    'I.83' => '4/3-Wege-Ventil: Mindestvolumenstrom erreicht',
    'I.84' => '4/3-Wege-Ventil: Min. Ruecklauftemperatur erreicht',
    'I.85' => 'Kontrollierte Regelniederdruckabschaltung Kaeltekreis',
    'I.86' => 'Kontrollierte Regelhochdruckabschaltung Kaeltekreis',
    'I.89' => 'Uhrzeit vorgestellt (Sommerzeit)',
    'I.90' => 'Uhrzeit zurueckgestellt (Winterzeit)',
    'I.92' => 'Energiebilanz zurueckgesetzt',
    'I.94' => 'Wartung in 30 Tagen fällig',
    'I.95' => 'Filterwechsel in 14 Tagen fällig',
    'I.96' => 'Unbekannte Folge-Waermepumpe (weiteres Viessmann Geraet)',
    'I.98' => 'Neue Folge-Waermepumpe (weiteres Viessmann Geraet) wurde erkannt',
    'I.99' => 'Zieltemperatur Hygienefunktion erreicht',
    'I.100' => 'Max. Verfluessigungsdruck erreicht',
    'I.101' => 'Min. Verdampfungsdruck fuer Heizbetrieb erreicht',
    'I.102' => 'Min. Verdampfungsdruck fuer Kuehlbetrieb erreicht',
    'I.103' => 'Max. Verdampfungsdruck erreicht',
    'I.104' => 'Max. Heissgastemperatur erreicht',
    'I.105' => 'Max. Laufzeit untere Verdampfungstemperatur erreicht',
    'I.106' => 'Max. Druckdifferenz Verdichter erreicht',
    'I.107' => 'Max. Verfluessigungstemperatur erreicht',
    'I.108' => 'Max. Drehmoment Verdichter erreicht',
    'I.109' => 'Max. Verdampfungstemperatur Verdichter erreicht',
    'I.110' => 'Min. Druckverhaeltnis Verdichter erreicht',
    'I.111' => 'Min. Verdampfungstemperatur Verdichter erreicht',
    'I.112' => 'Min. Austrittstemperatur am Verfluessiger erreicht',
    'I.113' => 'Smart Grid: Erzwungene Abschaltung aktiv',
    'I.114' => 'Smart Grid: Normalbetrieb aktiv',
    'I.115' => 'Smart Grid: Empfohlene Einschaltung aktiv',
    'I.116' => 'Smart Grid: Erzwungene Einschaltung aktiv',
    'I.117' => 'Energie-Management-System aktiv',
    'I.118' => 'Fussbodentemperaturbegrenzer Heiz-/Kuehlkreis 1 aktiv',
    'I.119' => 'Fussbodentemperaturbegrenzer Heiz-/Kuehlkreis 2 aktiv',
    'I.120' => 'Geraeuschreduzierter Betrieb Waermepumpe aktiv',
    'I.121' => 'Feuchteanbauschalter Heiz-/Kuehlkreis 1 aktiv',
    'I.122' => 'Feuchteanbauschalter Heiz-/Kuehlkreis 2 aktiv',
    'I.123' => 'Max. Ruecklauftemperatur Kaeltekreis erreicht',
    'I.124' => 'Min. Ruecklauftemperatur Kaeltekreis erreicht',
    'I.125' => 'Max. Lufteintrittstemperatur Kaeltekreis erreicht',
    'I.126' => 'Min. Lufteintrittstemperatur Kaeltekreis erreicht',
    'I.127' => 'Max. Druckdifferenz fuer Verdichterstart erreicht',
    'I.128' => 'Min. Oelsumpftemperatur erreicht',
    'I.129' => 'Kaeltekreisumkehr: Druckunterschied zu gering',
    'I.130' => 'Startphase Waermepumpe: Zeitueberschreitung',
    'I.131' => 'Min. Verdampfungstemperatur erreicht',
    'I.132' => 'Neustart Waermepumpenregelung',
    'I.133' => 'Reset der Elektronikmodule durch Neustart',
    'I.134' => 'Abtauen aktiv im Betriebsprogramm Frostschutz',
    'I.135' => 'Abtauen aktiv im Regelbetrieb',
    'I.142' => 'Min. Laufzeit Verdichter unterschritten',
    'I.143' => 'EVU-Sperre aktiv',
    'I.144' => 'Frequenzabweichungen bei Spannungsversorgung des EVU',
    'I.145' => 'Leistungsueberschreitung Ausseneinheit',
    'I.146' => 'Ueberhitzung Verdampfer Kuehlbetrieb',
    'I.147' => 'Ueberhitzung Verfluessiger Heizbetrieb',
    'I.148' => 'Ueberhitzung Verdampfer Heizbetrieb',
    'I.149' => 'Waermeanforderung waehrend Abtaubetrieb',
    'I.150' => 'Anforderung Abtauen waehrend Regelbetrieb',
    'I.151' => 'Betriebsgrenze Fluessiggas temperatur Verfluessiger erreicht',
    'I.152' => 'Betriebsgrenze Niederdruck erreicht',
    'I.155' => 'Estrichtrocknung durch Anwender abgebrochen',
    'I.156' => 'Warnschwelle Wasser-Volumenstrom Abtaubetrieb erreicht',
    'I.157' => 'Erforderliche Heissgastemperatur fuer Heizbetrieb ueberschritten',
    'I.158' => 'Erforderliche Heissgastemperatur fuer Kuehlbetrieb ueberschritten',
    'I.159' => 'Erhoehte Innenraumtemperatur in Ausseneinheit',
    'I.163' => 'Strombegrenzung der Wallbox aktiv: Leistung der Photovoltaikanlage zu gering',
    'I.168' => 'Waermepumpe ist als Fuehrungs-Waermepumpe konfiguriert',
    'I.169' => 'Waermepumpe ist als Folge-Waermepumpe konfiguriert',
    'I.170' => 'Durch eine Stoerung uebernimmt eine Folge-Waermepumpe voruebergehend die Aufgabe der Fuehrungs-Waermepumpe',
    'I.171' => 'Inverter: Software-Update laeuft, Inverter aus',
    'I.173' => 'Inverter: Ausgangsstrom zu hoch, reduzierte Verdichterdrehzahl',
    'I.174' => 'Inverter: Leistung fuer Verdichter wird voruebergehend reduziert, reduzierte Verdichterdrehzahl',
    'I.175' => 'Verdichter startet nicht: Umgebungstemperatur ist niedriger als zulaessige Betriebstemperatur fuer Verdichter, Verdichter temporaer aus',
    'I.176' => 'Verdichter mit reduzierter Leistung: Umgebungstemperatur ist hoeher als zulaessige Betriebstemperatur fuer Verdichter',
    'I.182' => 'Verdichter ueberlastet: Normales Regelverhalten',

    # Fault codes (F-codes) - actual errors
    # Sensor Faults
    'F.01' => 'Außentemperatursensor defekt',
    'F.02' => 'Vorlauftemperatursensor 1 defekt',
    'F.03' => 'Speichertemperatursensor defekt',
    'F.04' => 'Rücklauftemperatursensor defekt',
    'F.05' => 'Abgastemperatursensor defekt',
    'F.10' => 'Kurzschluss Außentemperatursensor',
    'F.11' => 'Kurzschluss Vorlauftemperatursensor',
    'F.12' => 'Kurzschluss Speichertemperatursensor',
    'F.13' => 'Kurzschluss Rücklauftemperatursensor',

    # Pressure and Flow
    'F.20' => 'Wasserdruck zu niedrig',
    'F.21' => 'Wasserdruck zu hoch',
    'F.22' => 'Kein Durchfluss',
    'F.23' => 'Durchfluss zu gering',

    # Heat Pump Specific
    'F.454' => 'Kältekreis gesperrt',
    'F.472' => 'Fernbedienung nicht erreichbar',
    'F.518' => 'Keine Kommunikation mit Energiezähler',
    'F.519' => 'Betrieb mit internen Sollwerten',
    'F.542' => 'Mischer schließt',
    'F.543' => 'Mischer öffnet',
    'F.685' => 'HPMU Kommunikationsfehler',
    'F.686' => 'HPMU Modul defekt',
    'F.687' => 'HPMU Verbindungsfehler',
    'F.770' => 'Frostschutz aktiviert',
    'F.771' => 'Passiver Frostschutz',
    'F.764' => 'Weiterer CAN-BUS-Teilnehmer meldet eine Störung',
    'F.788' => 'Kältekreis startet nicht',
    'F.791' => 'Ausfall Heizwasser-Durchlauferhitzer Phase 1',
    'F.792' => 'Ausfall Heizwasser-Durchlauferhitzer Phase 2',
    'F.793' => 'Ausfall Heizwasser-Durchlauferhitzer Phase 3',
    'F.1078' => 'Wiederholt zu geringer Volumenstrom bei Verdichteranlauf',
    
    # Zusätzliche Wärmepumpen-Fehlercodes (F-Codes)
    'F.33'  => 'Unterbrechung Lufteintrittstemperatursensor – Kältekreis aus',
    'F.34'  => 'Kurzschluss Lufteintrittstemperatursensor – Kältekreis aus',
    'F.74'  => 'Hydraulischer Anlagendruck zu niedrig – Wärmepumpe ausschalten',
    'F.111' => 'Unterbrechung Flüssiggastemperatursensor (Heizen) – Kältekreis aus',
    'F.112' => 'Kurzschluss Flüssiggastemperatursensor (Heizen) – Kältekreis aus',
    'F.117' => 'Unterbrechung Sauggastemperatursensor Verdampfer – Kältekreis aus',
    'F.118' => 'Kurzschluss Sauggastemperatursensor Verdampfer – Kältekreis aus',
    'F.121' => 'Kommunikationsfehler Wechselrichter Inverter – Kältekreis aus',
    'F.123' => 'Unterbrechung Flüssiggastemperatursensor Verflüssiger',
    'F.124' => 'Kurzschluss Flüssiggastemperatursensor Verflüssiger',
    'F.160' => 'Kommunikationsstörung CAN-BUS',
    'F.425' => 'Zeitsynchronisation fehlgeschlagen – Batterie HPMU ersetzen',
    'F.430' => 'Kommunikationsfehler Gateway – Betrieb mit internen Sollwerten',
    'F.846' => 'Inverter Verdichterdrehfeld gegenläufig – Kältekreis aus',
    'F.1008'=> 'Anzahl unterstützter Geräte an Hauptsteuergerät überschritten',
    'F.1009'=> 'Fehler elektrische Verdichterheizung Wärmepumpe',
    'F.1010'=> 'Störung Wasserdrucksensor',
    'F.1011'=> 'Störung Hochdrucksensor Kältekreis',
    'F.1012'=> 'Störung Niederdrucksensor Kältekreis',
);

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

#SVG for Kältkreislauf
our $vitoconnect_svg_kaeltekreislauf = q{
<?xml version="1.0" encoding="utf-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="25 0 495 280" preserveAspectRatio="xMinYMin meet" style="background:white; width:100%; height:auto; max-width:950px; font-family:Arial,Helvetica,sans-serif; display:block; margin:0;" xmlns:bx="https://boxy-svg.com">
  <defs>
    <pattern x="0" y="0" width="25" height="25" patternUnits="userSpaceOnUse" viewBox="0 0 100 100" id="pattern-0">
      <rect x="0.261" y="8.964" width="99.484" height="2.597" style="stroke: rgb(0, 0, 0); fill: rgb(15, 11, 11); stroke-width: 1;"/>
      <rect y="23.509" width="99.484" height="2.597" style="stroke: rgb(0, 0, 0); fill: rgb(15, 11, 11); stroke-width: 1;"/>
      <rect x="0.26" y="39.094" width="99.484" height="2.597" style="stroke: rgb(0, 0, 0); fill: rgb(15, 11, 11); stroke-width: 1;"/>
      <rect x="-0.259" y="54.159" width="99.484" height="2.597" style="stroke: rgb(0, 0, 0); fill: rgb(15, 11, 11); stroke-width: 1;"/>
      <rect x="0.001" y="70.263" width="99.484" height="2.597" style="stroke: rgb(0, 0, 0); fill: rgb(15, 11, 11); stroke-width: 1;"/>
      <rect x="0.521" y="85.589" width="99.484" height="2.597" style="stroke: rgb(0, 0, 0); fill: rgb(15, 11, 11); stroke-width: 1;"/>
    </pattern>
    <pattern id="pattern-0-0" href="#pattern-0" patternTransform="matrix(1, 0, 0, 1, 97.505501, 83.795998)"/>
    <pattern id="pattern-1" href="#pattern-0" patternTransform="matrix(1, 0, 0, 1, 206.208389, 83.935008)"/>
    <pattern id="pattern-2" href="#pattern-0" patternTransform="matrix(1, 0, 0, 1, 392.85718, 86.385434)"/>
    <bx:guide x="-64.283" y="87.735" angle="0"/>
    <bx:guide x="69.82" y="-32.374" angle="90"/>
    <bx:guide x="46.836" y="352.215" angle="90"/>
    <bx:guide x="96.255" y="324.975" angle="90"/>
    <bx:guide x="157.999" y="317.708" angle="90"/>
    <bx:guide x="615.522" y="70.274" angle="0"/>
    <bx:guide x="562.908" y="58.355" angle="0"/>
    <bx:guide x="595.332" y="52.908" angle="0"/>
    <linearGradient gradientUnits="userSpaceOnUse" x1="463.191" y1="43.415" x2="463.191" y2="171.007" id="gradient-0" gradientTransform="matrix(0.999963, 0.008737, -0.00363, 0.41554, -53.553903, 50.971219)">
      <stop offset="0" style="stop-color: rgb(47, 106, 198);"/>
      <stop offset="1" style="stop-color: rgb(217, 1, 23);"/>
    </linearGradient>
    <bx:guide x="557.061" y="102.827" angle="0"/>
    <bx:guide x="-64.283" y="87.735" angle="0"/>
    <bx:guide x="69.82" y="-32.374" angle="90"/>
    <bx:guide x="46.836" y="352.215" angle="90"/>
    <bx:guide x="96.255" y="324.975" angle="90"/>
    <bx:guide x="157.999" y="317.708" angle="90"/>
    <bx:guide x="615.522" y="70.274" angle="0"/>
    <bx:guide x="562.908" y="58.355" angle="0"/>
    <bx:guide x="595.332" y="52.908" angle="0"/>
    <bx:guide x="557.061" y="102.827" angle="0"/>
  </defs>
  <rect x="111.764" y="126.722" width="118.851" height="63.673" rx="5" ry="5" style="fill: rgb(216, 216, 216); stroke: rgb(0, 0, 0);"/>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="132.586" cy="151.577" rx="9.438" ry="8.56"/>
  <line style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1;" x1="132.696" y1="145.581" x2="132.541" y2="155.475"/>
  <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17); stroke-width: 1;" cx="132.541" cy="154.161" rx="1.855" ry="1.778"/>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="194.466" cy="150.703" rx="9.438" ry="8.56"/>
  <path style="fill: none; stroke-width: 2px; stroke: rgb(30, 105, 208);" d="M 175.81 82.808 L 109.471 83.122 L 109.157 193.478 L 354.078 193.479 L 353.449 84.694 L 222.971 83.751 L 222.971 120.222 L 327.353 120.851 L 327.353 162.038 L 214.77 161.902"/>
  <path style="fill: none; stroke: rgb(231, 11, 11); stroke-width: 2px;" d="M 211.338 161.724 L 164.492 161.409 L 164.806 229.321 L 361.623 230.893 L 361.623 198.509 L 401.238 198.509 L 402.181 43.508 L 162.605 44.136 L 162.605 119.908 L 213.539 119.908 L 213.225 83.437 L 196.247 83.122"/>
  <rect x="392.96" y="71.564" width="24.793" height="54.642" rx="5" ry="5" style="stroke: rgb(0, 0, 0); paint-order: fill; fill: url(&quot;#pattern-2&quot;); stroke-width: 1;"/>
  <path style="fill: none; stroke-linejoin: round; stroke-width: 2px; paint-order: fill; stroke: url(&quot;#gradient-0&quot;);" d="M 517.461 43.415 L 409.209 43.415 L 408.92 171.007 L 517.461 171.007"/>
  <g transform="matrix(1, 0, 0, 1, -0.378524, 3.357992)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgba(216, 216, 216, 0);" cx="44.996" cy="81.87" rx="9.438" ry="8.56"/>
    <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, -16.826176, -0.000004)">
    <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="221.243" cy="162.447" rx="9.438" ry="8.56"/>
    <path d="M 99.896 78.38 Q 101.531 74.629 103.166 78.38 L 105.953 84.77 Q 107.588 88.521 104.317 88.521 L 98.745 88.521 Q 95.474 88.521 97.109 84.77 Z" bx:shape="triangle 95.474 74.629 12.114 13.892 0.5 0.27 1@c238e5f3" style="stroke: rgb(0, 0, 0); fill: rgb(13, 13, 13); stroke-width: 1; transform-box: fill-box; transform-origin: 50% 50%;" transform="matrix(0, -1, 1, 0, 118.753361, 79.795387)"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17); stroke-width: 1;" cx="211.184" cy="153.928" rx="1.855" ry="1.778"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, -33.288994, -20.075006)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgba(216, 216, 216, 0); stroke-width: 1;" cx="116.922" cy="105.303" rx="9.438" ry="8.56"/>
    <path style="fill: none; stroke: rgb(0, 0, 0);" d="M 115.7 105.414 C 114.737 105.414 113.774 105.414 112.811 105.414 C 112.33 105.414 110.014 105.729 109.699 105.414 C 108.42 104.135 110.597 101.751 112.366 102.635 C 113.135 103.02 113.76 103.695 114.367 104.302 C 114.586 104.521 115.811 105.015 115.811 105.414"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1; transform-box: fill-box; transform-origin: 50% 50%;" d="M 121.06 103.384 C 120.097 103.384 119.134 103.384 118.171 103.384 C 117.69 103.384 115.374 103.699 115.059 103.384 C 113.78 102.105 115.957 99.721 117.726 100.605 C 118.495 100.99 119.12 101.665 119.727 102.272 C 119.946 102.491 121.171 102.985 121.171 103.384" transform="matrix(0, 1, -1, 0, -0.000017, -0.000002)"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1; transform-origin: 119.535px 107.136px;" d="M 122.672 108.552 C 121.709 108.552 120.746 108.552 119.783 108.552 C 119.302 108.552 116.986 108.867 116.671 108.552 C 115.392 107.273 117.569 104.889 119.338 105.773 C 120.107 106.158 120.732 106.833 121.339 107.44 C 121.558 107.659 122.783 108.153 122.783 108.552" transform="matrix(-1, 0, 0, -1, 0.000002, 0.000005)"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1; transform-box: fill-box; transform-origin: 50% 50%;" d="M 118.17 110.163 C 117.207 110.163 116.244 110.163 115.281 110.163 C 114.8 110.163 112.484 110.478 112.169 110.163 C 110.89 108.884 113.067 106.5 114.836 107.384 C 115.605 107.769 116.23 108.444 116.837 109.051 C 117.056 109.27 118.281 109.764 118.281 110.163" transform="matrix(0, -1, 1, 0, -0.000006, 0.000006)"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, -33.288994, 7.000388)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgba(216, 216, 216, 0); stroke-width: 1;" cx="116.922" cy="105.303" rx="9.438" ry="8.56"/>
    <path style="fill: none; stroke: rgb(0, 0, 0);" d="M 115.7 105.414 C 114.737 105.414 113.774 105.414 112.811 105.414 C 112.33 105.414 110.014 105.729 109.699 105.414 C 108.42 104.135 110.597 101.751 112.366 102.635 C 113.135 103.02 113.76 103.695 114.367 104.302 C 114.586 104.521 115.811 105.015 115.811 105.414"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1; transform-box: fill-box; transform-origin: 50% 50%;" d="M 121.06 103.384 C 120.097 103.384 119.134 103.384 118.171 103.384 C 117.69 103.384 115.374 103.699 115.059 103.384 C 113.78 102.105 115.957 99.721 117.726 100.605 C 118.495 100.99 119.12 101.665 119.727 102.272 C 119.946 102.491 121.171 102.985 121.171 103.384" transform="matrix(0, 1, -1, 0, -0.000017, -0.000002)"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1; transform-origin: 119.535px 107.136px;" d="M 122.672 108.552 C 121.709 108.552 120.746 108.552 119.783 108.552 C 119.302 108.552 116.986 108.867 116.671 108.552 C 115.392 107.273 117.569 104.889 119.338 105.773 C 120.107 106.158 120.732 106.833 121.339 107.44 C 121.558 107.659 122.783 108.153 122.783 108.552" transform="matrix(-1, 0, 0, -1, 0.000002, 0.000005)"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1; transform-box: fill-box; transform-origin: 50% 50%;" d="M 118.17 110.163 C 117.207 110.163 116.244 110.163 115.281 110.163 C 114.8 110.163 112.484 110.478 112.169 110.163 C 110.89 108.884 113.067 106.5 114.836 107.384 C 115.605 107.769 116.23 108.444 116.837 109.051 C 117.056 109.27 118.281 109.764 118.281 110.163" transform="matrix(0, -1, 1, 0, -0.000006, 0.000006)"/>
  </g>
  <rect x="97.609" y="68.975" width="24.793" height="54.642" rx="5" ry="5" style="stroke: rgb(0, 0, 0); paint-order: fill; fill: url(&quot;#pattern-0-0&quot;);"/>
  <line style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1;" x1="194.513" y1="145.348" x2="194.358" y2="155.242"/>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="256.228" cy="162.447" rx="9.438" ry="8.56"/>
  <line style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1;" x1="256.338" y1="156.451" x2="256.183" y2="166.345"/>
  <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17); stroke-width: 1;" cx="256.183" cy="165.031" rx="1.855" ry="1.778"/>
  <rect x="206.311" y="69.114" width="24.793" height="54.642" rx="5" ry="5" style="stroke: rgb(0, 0, 0); paint-order: fill; fill: url(&quot;#pattern-1&quot;); stroke-width: 1;"/>
  <g transform="matrix(1, 0, 0, 1, 349.411072, -202.169891)">
    <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="144.132" cy="246.518" rx="9.438" ry="8.56"/>
    <path style="fill: none; stroke: rgb(0, 0, 0);" d="M 139.661 238.786 L 139.661 251.453 C 140.944 251.453 152.264 251.177 151.501 251.177"/>
  </g>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="356.927" cy="197.853" rx="9.438" ry="8.56"/>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="356.713" cy="197.681" rx="5.085" ry="4.396"/>
  <rect x="430.184" y="70.077" width="45.423" height="86.72" rx="5" ry="5" style="stroke: rgb(0, 0, 0); fill: rgba(216, 216, 216, 0);"/>
  <line style="fill: none; stroke: rgb(0, 0, 0);" x1="430.716" y1="115.7" x2="476.139" y2="115.7"/>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 27.9926px; stroke-width: 0.998643px; white-space: pre;" transform="matrix(0.337316, 0, 0, 0.327586, 300.168396, 52.801506)" x="455.318" y="83.568">WW</text>
  <g transform="matrix(1, 0, 0, 1, 403.088989, -36.514595)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.245" rx="9.438" ry="8.56"/>
    <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
  </g>
  <text style="white-space: pre; fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 28px;" x="455.318" y="83.568" transform="matrix(0.337316, 0, 0, 0.327586, 303.649292, 98.496986)">HK</text>
  <g transform="matrix(1, 0, 0, 1, 403.610016, 89.059113)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.87" rx="9.438" ry="8.56"/>
    <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, -1.696667, -23.990173)">
    <path d="M -236.547 -33.366 Q -234.601 -36.483 -232.655 -33.366 L -229.338 -28.054 Q -227.392 -24.937 -231.285 -24.937 L -237.917 -24.937 Q -241.81 -24.937 -239.864 -28.054 Z" bx:shape="triangle -241.81 -36.483 14.418 11.546 0.5 0.27 1@d97a9276" style="stroke: rgb(0, 0, 0); fill: rgb(9, 1, 1); stroke-width: 1; transform-origin: -234.604px -29.931px;" transform="matrix(0, 1, -1, 0, 534.537537, 96.460785)"/>
    <path d="M -236.547 -33.366 Q -234.601 -36.483 -232.655 -33.366 L -229.338 -28.054 Q -227.392 -24.937 -231.285 -24.937 L -237.917 -24.937 Q -241.81 -24.937 -239.864 -28.054 Z" bx:shape="triangle -241.81 -36.483 14.418 11.546 0.5 0.27 1@d97a9276" style="stroke: rgb(0, 0, 0); fill: rgb(9, 1, 1); stroke-width: 1; transform-origin: -234.604px -29.931px;" transform="matrix(0, 1, 1, 0, 544.299709, 96.307468)"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, 98.653221, 3.357992)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.87" rx="9.438" ry="8.56"/>
    <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, -118.751167, 17.294722)">
    <g>
      <path d="M -236.547 -33.366 Q -234.601 -36.483 -232.655 -33.366 L -229.338 -28.054 Q -227.392 -24.937 -231.285 -24.937 L -237.917 -24.937 Q -241.81 -24.937 -239.864 -28.054 Z" bx:shape="triangle -241.81 -36.483 14.418 11.546 0.5 0.27 1@d97a9276" style="stroke: rgb(0, 0, 0); fill: rgb(9, 1, 1); stroke-width: 1; transform-origin: -234.604px -29.931px;" transform="matrix(0, 1, -1, 0, 534.537537, 96.460785)"/>
      <path d="M 247.073 39.6 Q 249.019 36.483 250.965 39.6 L 254.282 44.912 Q 256.228 48.029 252.335 48.029 L 245.703 48.029 Q 241.81 48.029 243.756 44.912 Z" bx:shape="triangle 241.81 36.483 14.418 11.546 0.5 0.27 1@b84c7105" style="stroke: rgb(0, 0, 0); fill: rgb(9, 1, 1); stroke-width: 1; transform-origin: 249.016px 43.035px;" transform="matrix(0, 1, 1, 0, 60.679688, 23.341461)"/>
    </g>
  </g>
  <g>
    <g transform="matrix(1, 0, 0, 1, 258.55899, 3.357992)">
      <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.87" rx="9.438" ry="8.56"/>
      <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
      <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
    </g>
  </g>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="310.056" cy="162.447" rx="9.438" ry="8.56"/>
  <path d="M 309.748 157.655 L 312.53 166.467 L 306.965 166.467 L 309.748 157.655 Z" bx:shape="triangle 306.965 157.655 5.565 8.812 0.5 0 1@b71052ea" style="stroke: rgb(0, 0, 0); fill: rgb(17, 16, 16); stroke-width: 1;"/>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="218.312" cy="229.84" rx="9.438" ry="8.56"/>
  <line style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1;" x1="218.422" y1="223.844" x2="218.267" y2="233.738"/>
  <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17); stroke-width: 1;" cx="218.267" cy="232.424" rx="1.855" ry="1.778"/>
  <g transform="matrix(1, 0, 0, 1, 229.385986, 147.472778)">
    <g>
      <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="74.169" cy="82.367" rx="9.438" ry="8.56"/>
      <path d="M 73.861 77.575 L 76.643 86.387 L 71.078 86.387 L 73.861 77.575 Z" bx:shape="triangle 71.078 77.575 5.565 8.812 0.5 0 1@9a2e2204" style="stroke: rgb(0, 0, 0); fill: rgb(17, 16, 16);"/>
    </g>
  </g>
  <g transform="matrix(1, 0, 0, 1, 53.371994, -40.880001)">
    <g transform="matrix(1, 0, 0, 1, 258.55899, 3.357992)">
      <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.87" rx="9.438" ry="8.56"/>
      <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
      <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
    </g>
  </g>
  <g transform="matrix(1, 0, 0, 1, -83.71759, -40.880005)">
    <g transform="matrix(1, 0, 0, 1, 258.55899, 3.357992)">
      <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.87" rx="9.438" ry="8.56"/>
      <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
      <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
    </g>
  </g>
  <g transform="matrix(1, 0, 0, 1, 396.941376, -1.156075)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.245" rx="9.438" ry="8.56"/>
    <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, 397.527405, 45.397678)">
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(255, 255, 255);" cx="44.996" cy="81.245" rx="9.438" ry="8.56"/>
    <line style="fill: none; stroke: rgb(0, 0, 0);" x1="45.106" y1="75.874" x2="44.951" y2="85.768"/>
    <ellipse style="stroke: rgb(0, 0, 0); fill: rgb(17, 17, 17);" cx="44.951" cy="84.454" rx="1.855" ry="1.778"/>
  </g>
  <g transform="matrix(1, 0, 0, 1, 419.289001, 1.134982)">
    <g>
      <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="74.169" cy="82.367" rx="9.438" ry="8.56"/>
      <path d="M 73.861 77.575 L 76.643 86.387 L 71.078 86.387 L 73.861 77.575 Z" bx:shape="triangle 71.078 77.575 5.565 8.812 0.5 0 1@9a2e2204" style="stroke: rgb(0, 0, 0); fill: rgb(17, 16, 16);"/>
    </g>
  </g>
  <g>
    <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="493.458" cy="127.068" rx="9.438" ry="8.56"/>
    <path style="fill: none; stroke: rgb(0, 0, 0);" d="M 487.611 126.813 C 488.096 125.358 491.507 122.757 493.254 124.504 C 493.769 125.019 493.995 126.271 494.537 126.813 C 496.06 128.336 498.897 124.975 498.897 124.248"/>
    <path style="fill: none; stroke: rgb(0, 0, 0); stroke-width: 1;" d="M 487.516 130.483 C 488.001 129.028 491.412 126.427 493.159 128.174 C 493.674 128.689 493.9 129.941 494.442 130.483 C 495.965 132.006 498.802 128.645 498.802 127.918"/>
  </g>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 27px; white-space: pre;" x="27.06" y="100.494"> </text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; text-anchor: middle;" x="44.649" y="103.01">%out_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="83.787" y="72.96">%fan0%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="83.295" y="131.278">%fan1%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="143.717" y="102.598">%evp_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="256.625" y="180.185">%comp_in%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="218.222" y="248.488">%comp_out%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="204.836" y="180.185">%comp_speed%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="449.198" y="188.831">%heat_suppl%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="303.5" y="62.468">%valve1%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="186.976" y="102.98">%valve0%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="356.767" y="62.444">%cond_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="310.001" y="180.567">%comp_pres%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle; transform-box: fill-box; transform-origin: 55.1208% 50%;" x="303.614" y="103.362">%evp_tmp_over%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="193.754" y="139.241">%comp_motor%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle; transform-origin: 332.143px 245.429px;" x="304.21" y="248.297">%high_pres%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="448.264" y="62.252">%heat_return%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="493.194" y="63.018">%pump1%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="219.864" y="61.296">%eco_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="450.89" y="97.052">%dhw_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="453.826" y="143.706">%heat_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="493.959" y="144.854">%allengra%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="494.152" y="101.45">%heat_pres%</text>
  <ellipse style="stroke: rgb(0, 0, 0); stroke-width: 1; fill: rgb(255, 255, 255);" cx="142.115" cy="161.461" rx="9.438" ry="8.56"/>
  <path style="fill: none; stroke: rgb(0, 0, 0);" d="M 143.283 156.506 L 140.242 160.386 L 144.227 159.338 L 140.766 165.336 L 143.388 164.057"/>
  <path style="fill: none; stroke: rgb(0, 0, 0);" d="M 140.556 162.903 L 140.137 165.84"/>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="132.994" y="138.501">%inv_tmp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="141.642" y="178.677">%inv_watt%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="140.526" y="188.442">%inv_amp%</text>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 8px; white-space: pre; stroke-width: 1; text-anchor: middle;" x="206.897" y="189.256">Oil: %comp_oil%</text>
  <rect id="re_back" x="23.391" y="31.415" width="499.317" height="225.069" style="fill: %overlay_color%; pointer-events: none;"/>
  <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 18px; letter-spacing: 6px; white-space: pre; text-anchor: middle;" transform="matrix(1.063244, 0, 0, 1, 16.775244, -0.906249)" x="236.623" y="25.757">%TITEL%</text>
  <g transform="matrix(1, 0, 0, 1, 0.902341, 0.902341)">
    <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 11px; white-space: pre;" x="55.988" y="273.33">%status%</text>
    <g transform="matrix(0.02242, 0, -0.023405, 0.029996, 47.15366, 250.144562)">
      <ellipse cx="543.31" cy="862.2" rx="472.44" ry="35.433" fill="#c1c1c1" fill-opacity=".5"/>
    </g>
    <g transform="matrix(0.061256, 0, 0, 0.00055, -126.994232, 262.080444)">
      <path d="m2875.4 307.04 6.48 637.82v0.02h-330.71v-0.02l6.48-637.82h317.75z" fill="#b3b3b3"/>
    </g>
    <g transform="matrix(0.061274, 0, 0, 0.018663, -127.045197, 256.869293)">
      <rect x="2551.2" y="307.04" width="330.71" height="637.84" fill="#e6e6e6"/>
    </g>
    <g transform="matrix(0.01172, 0, 0, 0.010325, 7.367994, 251.027283)">
      <path d="m2362.2 1181.1c260.75 0 472.45 211.7 472.45 472.44 0 260.75-211.7 472.44-472.45 472.44-260.74 0-472.44-211.69-472.44-472.44 0-260.74 211.7-472.44 472.44-472.44zm0 29.53c-244.45 0-442.91 198.46-442.91 442.91s198.46 442.92 442.91 442.92c244.46 0 442.92-198.47 442.92-442.92s-198.46-442.91-442.92-442.91zm0 29.53c228.16 0 413.39 185.23 413.39 413.38 0 228.16-185.23 413.39-413.39 413.39-228.15 0-413.38-185.23-413.38-413.39 0-228.15 185.23-413.38 413.38-413.38zm0 29.52c-211.85 0-383.85 172.01-383.85 383.86 0 211.86 172 383.86 383.85 383.86 211.86 0 383.86-172 383.86-383.86 0-211.85-172-383.86-383.86-383.86zm0 29.53c195.56 0 354.33 158.77 354.33 354.33s-158.77 354.33-354.33 354.33-354.33-158.77-354.33-354.33 158.77-354.33 354.33-354.33zm0 29.53c-179.26 0-324.8 145.54-324.8 324.8 0 179.27 145.54 324.81 324.8 324.81 179.27 0 324.81-145.54 324.81-324.81 0-179.26-145.54-324.8-324.81-324.8zm0 29.53c162.97 0 295.28 132.31 295.28 295.27 0 162.97-132.31 295.28-295.28 295.28-162.96 0-295.27-132.31-295.27-295.28 0-162.96 132.31-295.27 295.27-295.27zm0 29.53c-146.67 0-265.74 119.07-265.74 265.74s119.07 265.75 265.74 265.75c146.68 0 265.75-119.08 265.75-265.75s-119.07-265.74-265.75-265.74zm0 29.52c130.38 0 236.23 105.85 236.23 236.22 0 130.38-105.85 236.22-236.23 236.22-130.37 0-236.22-105.84-236.22-236.22 0-130.37 105.85-236.22 236.22-236.22zm0 29.53c-114.07 0-206.69 92.62-206.69 206.69 0 114.08 92.62 206.7 206.69 206.7 114.08 0 206.7-92.62 206.7-206.7 0-114.07-92.62-206.69-206.7-206.69zm0 29.53c97.79 0 177.17 79.38 177.17 177.16s-79.38 177.17-177.17 177.17c-97.77 0-177.16-79.39-177.16-177.17s79.39-177.16 177.16-177.16zm0 29.53c-81.48 0-147.63 66.15-147.63 147.63 0 81.49 66.15 147.64 147.63 147.64 81.49 0 147.64-66.15 147.64-147.64 0-81.48-66.15-147.63-147.64-147.63z" fill="#999" fill-opacity=".8"/>
    </g>
    <g transform="matrix(0.020455, 0, 0, 0.017585, -9.371134, 241.830399)">
      <path d="m2456.7 1202.7v7.19h-566.93v-7.19h566.93zm0-21.57v7.19h-566.93v-7.19h566.93zm0 43.14v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.56v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 43.13v7.19h-566.93v-7.19h566.93zm0-21.56v7.19h-566.93v-7.19h566.93zm0 43.13v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.18h-566.93v-7.18h566.93zm0 21.56v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm-0.58 42.72v7.19h-566.93v-7.19h566.93zm0-21.57v7.19h-566.93v-7.19h566.93zm0 43.14v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.56v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 43.13v7.19h-566.93v-7.19h566.93zm0-21.56v7.19h-566.93v-7.19h566.93zm0 43.13v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93zm0 21.56v7.19h-566.93v-7.19h566.93zm0 21.57v7.19h-566.93v-7.19h566.93z"/>
    </g>
    <g transform="matrix(0.020382, 0, 0, 0.013467, -9.242441, 261.115326)">
      <rect x="1937" y="992.13" width="47.244" height="94.488"/>
    </g>
    <g transform="matrix(0.020382, 0, 0, 0.017956, -9.723906, 254.965027)">
      <rect x="1937" y="1157.5" width="94.488" height="23.622"/>
    </g>
    <g transform="matrix(0.020382, 0, 0, 0.017956, -10.205369, 257.529663)">
      <g transform="matrix(1 0 0 .75 897.64 200.79)">
        <rect x="1937" y="992.13" width="47.244" height="94.488"/>
      </g>
      <g transform="translate(874.02 -141.73)">
        <rect x="1937" y="1157.5" width="94.488" height="23.622"/>
      </g>
    </g>
  </g>
  <g transform="matrix(1, 0, 0, 1, 28.423752, 4.511705)">
    <text style="fill: rgb(51, 51, 51); font-family: Arial, sans-serif; font-size: 11px; white-space: pre;" x="415.66" y="269.948">%sec_status%</text>
    <g transform="matrix(0.135571, 0, 0, 0.117794, 396.783936, 258.119446)" id="Flamme" style="">
      <g>
        <radialGradient id="SVGID_1_" cx="68.8839" cy="124.2963" r="70.587" gradientTransform="matrix(-1 -4.343011e-03 -7.125917e-03 1.6408 131.9857 -79.3452)" gradientUnits="userSpaceOnUse">
          <stop offset="0.3144" style="stop-color:#FF9800"/>
          <stop offset="0.6616" style="stop-color:#FF6D00"/>
          <stop offset="0.9715" style="stop-color:#F44336"/>
        </radialGradient>
        <path style="fill:url(#SVGID_1_);" d="M35.56,40.73c-0.57,6.08-0.97,16.84,2.62,21.42c0,0-1.69-11.82,13.46-26.65 c6.1-5.97,7.51-14.09,5.38-20.18c-1.21-3.45-3.42-6.3-5.34-8.29C50.56,5.86,51.42,3.93,53.05,4c9.86,0.44,25.84,3.18,32.63,20.22 c2.98,7.48,3.2,15.21,1.78,23.07c-0.9,5.02-4.1,16.18,3.2,17.55c5.21,0.98,7.73-3.16,8.86-6.14c0.47-1.24,2.1-1.55,2.98-0.56 c8.8,10.01,9.55,21.8,7.73,31.95c-3.52,19.62-23.39,33.9-43.13,33.9c-24.66,0-44.29-14.11-49.38-39.65 c-2.05-10.31-1.01-30.71,14.89-45.11C33.79,38.15,35.72,39.11,35.56,40.73z"/>
        <g>
          <radialGradient id="SVGID_2_" cx="64.9211" cy="54.0621" r="73.8599" gradientTransform="matrix(-0.0101 0.9999 0.7525 7.603777e-03 26.1538 -11.2668)" gradientUnits="userSpaceOnUse">
            <stop offset="0.2141" style="stop-color:#FFF176"/>
            <stop offset="0.3275" style="stop-color:#FFF27D"/>
            <stop offset="0.4868" style="stop-color:#FFF48F"/>
            <stop offset="0.6722" style="stop-color:#FFF7AD"/>
            <stop offset="0.7931" style="stop-color:#FFF9C4"/>
            <stop offset="0.8221" style="stop-color:#FFF8BD;stop-opacity:0.804"/>
            <stop offset="0.8627" style="stop-color:#FFF6AB;stop-opacity:0.529"/>
            <stop offset="0.9101" style="stop-color:#FFF38D;stop-opacity:0.2088"/>
            <stop offset="0.9409" style="stop-color:#FFF176;stop-opacity:0"/>
          </radialGradient>
          <path style="fill:url(#SVGID_2_);" d="M76.11,77.42c-9.09-11.7-5.02-25.05-2.79-30.37c0.3-0.7-0.5-1.36-1.13-0.93 c-3.91,2.66-11.92,8.92-15.65,17.73c-5.05,11.91-4.69,17.74-1.7,24.86c1.8,4.29-0.29,5.2-1.34,5.36 c-1.02,0.16-1.96-0.52-2.71-1.23c-2.15-2.05-3.7-4.72-4.44-7.6c-0.16-0.62-0.97-0.79-1.34-0.28c-2.8,3.87-4.25,10.08-4.32,14.47 C40.47,113,51.68,124,65.24,124c17.09,0,29.54-18.9,19.72-34.7C82.11,84.7,79.43,81.69,76.11,77.42z"/>
        </g>
      </g>
    </g>
  </g>
  <g transform="matrix(0.028096, 0, 0, 0.021439, 408.741913, 259.626831)" style="">
    <path d="m311.12 179.09c1.6567 1.4172 3.4341 2.8902 3.9499 3.2734s0.58405 0.89986 0.15184 1.1481c-0.99688 0.57266 2.3311 4.0132 3.8294 3.959 0.61556-0.02231 1.0921 0.98723 1.0589 2.2434-0.03515 1.3312 0.72562 2.6989 1.8236 3.2787 2.4384 1.2874 5.0418 4.814 7.6296 10.335 1.1393 2.4306 3.0759 5.7362 4.3035 7.3457 2.8029 3.675 6.0305 9.5427 6.1741 11.225 0.06004 0.70324 0.29243 0.95371 0.51642 0.55661s2.2468 2.4514 4.4951 6.33 6.1454 10.502 8.6601 14.72c29.643 49.71 45.21 76.264 45.838 78.187 0.41865 1.2819 1.0283 2.4218 1.3547 2.5332s2.6748 3.5186 5.2185 7.5716l4.625 7.3691-24.291-3.1214c-13.36-1.7168-24.725-3.2857-25.255-3.4864s-2.4076-0.41842-4.1708-0.48365-10.009-0.99174-18.325-2.0589l-15.119-1.9403 4.7569 7.9982c2.6163 4.399 5.0703 9.0058 5.4533 10.237s0.84508 1.964 1.0269 1.6279c0.30778-0.56898 7.7295 11.697 8.057 13.316 0.08158 0.40331 0.61143 1.1737 1.1774 1.7119s1.6264 2.345 2.3564 4.0151 1.5626 3.1786 1.8503 3.3524c0.96579 0.5834 20.169 33.342 20.061 34.222-0.05875 0.47805 0.28523 1.106 0.76441 1.3955 1.2117 0.73197 21.196 34.448 23.094 38.963 0.85206 2.0267 1.6838 3.4361 1.8483 3.132 0.29394-0.54337 7.7384 11.935 8.0035 13.415 0.07455 0.41632 0.46891 1.0474 0.87638 1.4024 1.5399 1.3416 48.089 80.568 48.948 83.309 0.49474 1.579 1.0456 2.6009 1.2241 2.2709s1.6735 1.564 3.3222 4.2089l2.9976 4.8089-8.4713-1.1773c-4.6592-0.64755-9.0886-1.424-9.8431-1.7256s-1.6815-0.42892-2.0602-0.28311-9.3379-0.97371-19.909-2.4878c-20.466-2.9313-27.938-3.9379-31.828-4.2879-2.1534-0.19378 7.2624 15.134 85.669 139.46 48.449 76.823 87.638 139.81 87.088 139.97s-0.23156 0.4133 0.70787 0.5663c1.5886 0.2586 1.6573 0.1146 0.983-2.0588-0.39876-1.2853-1.825-7.9255-3.1695-14.756s-3.2466-16.174-4.2269-20.764-1.3582-8.5888-0.83955-8.8867 0.54864-0.6374 0.06674-0.7544c-0.88617-0.2152-3.1917-9.8023-7.1535-29.746-1.1938-6.0098-2.7217-13.671-3.3954-17.025s-0.82864-6.3277-0.34447-6.6082 0.35837-0.4912-0.27956-0.4681c-1.2196 0.0442-2.784-8.8682-1.7325-9.8698 0.33552-0.3195 0.18232-0.5655-0.34042-0.5466-1.0619 0.0385-7.2244-29.352-6.4534-30.778 0.26957-0.4983 0.15501-1.1085-0.25458-1.3559s-1.7738-5.6598-3.0314-12.027c-2.814-14.247-3.3072-16.701-5.8055-28.88-1.0947-5.3369-1.54-9.9622-0.9895-10.278s0.47809-0.55603-0.16092-0.53287c-1.3671 0.04953-11.601-49.935-10.369-50.643 0.46088-0.26474 0.43816-0.58043-0.05048-0.70154-1.072-0.26566-5.1604-18.319-4.3373-19.153 0.31823-0.32228 0.12528-1.3499-0.42881-2.2836s-1.6646-5.1854-2.4679-9.4482l-1.4605-7.7506 8.9473 1.1615c4.921 0.63882 9.6238 1.4417 10.451 1.7842s2.1947 0.42359 3.0397 0.18021 1.9602-0.1865 2.4782 0.1264 2.3149 0.6635 3.9931 0.7791c6.9597 0.4794 28.022 3.5862 29.221 4.3101 0.71196 0.43007-0.26529-3.3998-2.1716-8.5109s-4.0665-11.599-4.8003-14.418-1.6731-5.3301-2.0873-5.5803-0.71782-0.82236-0.67472-1.2715-1.3085-4.6001-3.0035-9.2244-3.3111-9.488-3.5912-10.808-1.4934-4.7364-2.6962-7.5916-1.7275-5.4551-1.166-5.7777 0.5186-0.56827-0.09539-0.54603c-1.026 0.03718-3.6634-6.5863-7.0464-17.696-0.74314-2.4405-1.8425-5.5115-2.443-6.8246s-2.0852-5.4221-3.2992-9.1312-4.4219-13.078-7.1286-20.819-4.6107-14.4-4.2313-14.797 0.27429-0.70652-0.23362-0.68813c-0.89187 0.03233-22.314-60.12-26.375-74.059-1.0977-3.7681-2.3417-7.06-2.7645-7.3154s-0.72465-0.84797-0.67086-1.3168-0.72065-2.8685-1.721-5.3325l-1.8188-4.48 5.3591 0.60396c2.9475 0.33218 5.56 0.9945 5.8055 1.4718s0.74426 0.6214 1.1083 0.32021c0.69652-0.57635 18.285 1.8216 20.934 2.8541 0.8484 0.33064 2.7036 0.62265 4.1227 0.64893s8.084 0.95457 14.811 2.0629l12.231 2.0151-0.31662-4.0996c-0.17413-2.2548-0.49044-4.5061-0.70292-5.003-1.1281-2.6378-1.6154-9.4951-0.71166-10.014 0.5751-0.33036 0.5436-0.58247-0.07-0.56024-1.0224 0.03704-7.4159-36.547-6.5744-37.619 0.20232-0.25774 0.05763-2.9223-0.32152-5.9212s-0.23536-5.7134 0.31956-6.0322 0.4873-0.5607-0.15031-0.53759c-0.95955 0.03476-10.915-47.592-10.278-49.166 0.11156-0.27531-0.52266-3.41-1.4094-6.966-1.8793-7.5365 2.8867-7.6574 2.9867-10.438 0.05932-1.649-223.4-21.212-220.65-18.857z"/>
  </g>
</svg>
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
    $hash->{FW_detailFn} = \&vitoconnect_FW_detailFn;
    #$hash->{FW_summaryFn} = \&vitoconnect_FW_detailFn;
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
      . "vitoconnect_showKaeltekreislauf:0,1 "
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
# Getter
#####################################################################################################################
sub vitoconnect_Get {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    return "get ".$name." needs at least one argument" unless (defined($opt) );
    
    if ($opt =~ /^(html|ftui)$/) { 
      return vitoconnect_GetHtml($hash, @args); 
    }
    elsif ($opt eq 'Select...') {
      return "Select the action you want from the Drop-Down list";
    }
    
     my $getlist = "Unknown argument $opt, choose one of ".
                   "Select...:noArg ".
                   "html:noArg "
                   ;

    return $getlist;
}

#####################################################################################################################
# Html für ftui
#####################################################################################################################
sub vitoconnect_GetHtml {
    my ($hash) = @_; 
    my $name = $hash->{NAME};
    
    my $ret = "<html>";
    $ret   .= vitoconnect_FW_detailFn("WEB", $name, "", {});
    $ret   .= "</html>";
    # SVG responsive machen 
    $ret =~ s/<svg([^>]*)>/<svg$1 width="100%" height="100%" preserveAspectRatio="xMidYMid meet">/;
    # viewBox hinzufügen, falls nicht vorhanden 
    if ($ret !~ /viewBox=/) { $ret =~ s/<svg/<svg viewBox="0 0 1000 1000"/; }


    return $ret;
}

#####################################################################################################################
# Implementierung set-Befehle
#####################################################################################################################
sub vitoconnect_Set {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    
    # Standard Parameter setzen
    my $val = "Unknown argument $opt, choose one of Select...:noArg "
              ."update:noArg clearReadings:noArg password apiKey logResponseOnce:noArg clearMappedErrors:noArg";
    Log(5,$name.", -vitoconnect_Set started: ". $opt); #debug
    
    # Setter für die Geräteauswahl dynamisch erstellen  
    Log3($name,5,$name." - Set devices: ".$hash->{devices});
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
    my $return;
    if  (AttrVal( $name, 'vitoconnect_raw_readings', 0 ) eq "1" ) {
        #use new dynamic parsing of JSON to get raw setters
        $return = vitoconnect_Set_New ($hash,$name,$opt,@args);
    } 
    elsif  (AttrVal( $name, 'vitoconnect_mapping_roger', 0 ) eq "1" ) {
        #use roger setters
        $return = vitoconnect_Set_Roger ($hash,$name,$opt,@args);
    } 
    else {
        #use svn setters
        $return = vitoconnect_Set_SVN ($hash,$name,$opt,@args);
    }
    
    # Check if val was returned or action executed with return;
    if (defined $return) {
      $val .= $return;
    } else {
      return;
    }

    if ($opt eq 'Select...') {
      return "Select the action you want from the Drop-Down list";
    }
    elsif  ($opt eq "update")                            {   # set <name> update: update readings immeadiatlely
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
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "apiKey" )                           {   # set <name> apiKey: bisher keine Beschreibung
        $hash->{apiKey} = $args[0];
        my $err = vitoconnect_StoreKeyValue($hash,"apiKey",$args[0]);   # apiKey verschlüsselt speichern
        return $err if ($err);
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
 #Log(1,$name.", -vitoconnect_Set val: ". $val);
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
                            } 
                            elsif ($param->{type} eq 'Schedule') {
                             my $decoded_args = decode_json($args[0]);
                             
                             # Transformieren der Datenstruktur
                             my %schedule;
                             foreach my $day (@$decoded_args) {
                                 foreach my $key (keys %$day) {
                                     push @{$schedule{$key}}, $day->{$key};
                                 }
                             }
                             
                             # Konvertieren der transformierten Datenstruktur in JSON
                             my $schedule_data = encode_json(\%schedule);
                             $data = "{\"$paramName\":$schedule_data";
                            }
                            else {
                             $data = "{\"$paramName\":\"@args\"";
                            }
                            Log(5,$name.", -vitoconnect_Set_New, paramName:".$paramName.", args:".Dumper(\@args));
                            
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
    Log3($name,4,$name." GetUpdate called by caller name: $name, memoryadress: $hash");
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
        url    => $tokenURL,
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
            Log3($name,1,$name." Can not get Access Token - Access Token: not defined in response");
            Log3($name,2,$name." - Request url: " . $param->{"url"} . " data: " . $param->{"data"});
            Log3($name,2,$name." - Received response: ".$response_body."\n");
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
    my ($hash, $caller) = @_;
    my $name      = $hash->{NAME};
    my $client_id = $hash->{apiKey};
    my $param     = {
        url    => $tokenURL,
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=refresh_token"
          . "&client_id=$client_id"
          . "&refresh_token="
          . $hash->{"refresh_token"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        caller  => $caller,  # <–– Kontext hier speichern!
        callback => \&vitoconnect_getRefreshCallback
    };

    #Log3 $name, 1, "$name - Refresh token request url: " . $param->{"url"} . " data: " . $param->{"data"};
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
    my $caller = $param->{caller} // 'update';  # Default: update

    if ($err eq "")                 {
        Log3($name,4,$name.". - getRefreshCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $decode_json = eval {decode_json($response_body)};
        if ($@)                     {   # Fehler aufgetreten
            Log3($name,1,$name.", vitoconnect_getRefreshCallback: JSON error while request: ".$@);
            if ($caller ne 'action') {
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            }
            return;
        }
        my $access_token = $decode_json->{"access_token"};
        if ($access_token ne "")    {   # kein Fehler
            $hash->{".access_token"} = $access_token;   # in Internal merken
            Log3($name,4,$name." - Access Token: ".substr($access_token,0,20)."...");
            #vitoconnect_getGw($hash);  # Abfrage Gateway-Serial
            # directly call get resource to save API calls
             if ($caller eq 'action') {
                vitoconnect_action(
                    $hash,
                    $hash->{".retry_feature"},
                    $hash->{".retry_data"},
                    $name,
                    $hash->{".retry_opt"},
                    @{ $hash->{".retry_args"} }
                );
            } else {
                vitoconnect_getResource($hash);
            }
        }
        else {
            Log3($name,1,$name." Can not refresh Access Token - Access Token: not defined in response");
            Log3($name,2,$name." - Request url: " . $param->{"url"} . " data: " . $param->{"data"});
            Log3($name,2,$name." - Received response: ".$response_body."\n");
            # zurück zu getCode?
            if ($caller ne 'action') {
                InternalTimer(gettimeofday() + $hash->{intervall}, "vitoconnect_GetUpdate", $hash);
            }
            return;
        }
    }
    else {
        Log3 $name, 1, "$name - getRefresh: An error occured: $err";
        if ($caller ne 'action') {
            InternalTimer(gettimeofday() + $hash->{intervall}, "vitoconnect_GetUpdate", $hash);
        }
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
        url      => $equipmentURL
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
        url      => $equipmentURL
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
        url     => $featureURL
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
        url     => $equipmentURL
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
        url    => $featureURL
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
        RemoveInternalTimer($hash);  
        vitoconnect_getCode($hash);
        return;
    }
    my $param = {
        url => $featureURL
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
    my @days = qw(mon tue wed thu fri sat sun); # Reihenfolge der Wochentage festlegen für type Schedule
    
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
                    my @schedule;
                    foreach my $day (@days) {
                     if (exists $Value->{$day}) {
                       foreach my $entry (@{$Value->{$day}}) {
                         my $ordered_entry = sprintf('{"mode":"%s","start":"%s","end":"%s","position":%d}',
                                             $entry->{mode}, $entry->{start}, $entry->{end}, $entry->{position}
                       );
                       push @schedule, sprintf('{"%s":%s}', $day, $ordered_entry);
                       }
                     }
                    }
                    my $Result = '[' . join(',', @schedule) . ']';
                    readingsBulkUpdate($hash, $Reading, $Result);
                    Log3($name, 5, "$name - $Reading: $Result ($Type)");
                }
                else {
                    readingsBulkUpdate($hash,$Reading,$Value);
                    Log3 $name, 5, "$name - $Reading: $Value ($Type)";
                    #Log3 $name, 1, "$name - $Reading: $Value ($Type)";
                }
                
                # Store power readings as asSingleValue
                #if ($Reading =~ m/dayValueReadAt$/) {
                # Log(5,$name.", -call setpower $Reading");
                # vitoconnect_getPowerLast ($hash,$name,$Reading);
                #}
                
                # Get error codes from API
                if ($Reading =~ /^device\.messages\.(\w+)\.raw\.entries$/) {
                  my $type = $1;  # z.B. "errors", "info", "status", "service", etc.
                  Log3($name, 5, "$name: Calling vitoconnect_getErrorCode for message type '$type' (Reading: '$Reading')");

                  if (defined $comma_separated_string && $comma_separated_string ne '') {
                   vitoconnect_getErrorCode($hash, $name, $comma_separated_string);
                  }
                }
            }
        }

        readingsBulkUpdate($hash,"state","last update: ".TimeNow().""); # Reading 'state'
        readingsEndUpdate( $hash, 1 );  # Readings schreiben
        
        # NEU: jetzt alle relevanten Readings finden und Sub wie früher aufrufen
        foreach my $Reading (keys %{ $hash->{READINGS} }) {
         if ($Reading =~ m/dayValueReadAt$/) {
           my ($featureBase) = $Reading =~ /^(.*)\.dayValueReadAt$/;
           # passenden Feature-Block im bereits vorhandenen $items suchen
           my ($feature) = grep { $_->{feature} eq $featureBase } @{ $items->{data} };
           my $anchor = $feature->{timestamp};
           vitoconnect_getPowerLast($hash,$name,$Reading,$anchor);
         }
        }
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
#sub vitoconnect_getPowerLast {
#    my ($hash, $name, $Reading, $anchor) = @_;
#
#    # Basename ohne letztes Suffix
#    $Reading =~ s/\.[^.]*$//;
#
#    # Werte-Liste (robust gegen Leerzeichen, als Zahl)
#    my $raw = ReadingsVal($name, $Reading.".day", "");
#    my @values = map { 0+$_ } split(/\s*,\s*/, $raw);
#
#    # Basisdatum = dayValueReadAt (Kalendertag der Ablesung)
#    #my $timestamp = ReadingsVal($name, $Reading.".dayValueReadAt", "");
#    #return if (!$timestamp || $timestamp eq "");
#    #my $baseDate = Time::Piece->strptime(substr($timestamp, 0, 10), '%Y-%m-%d');
#    #my $one_day  = 24 * 60 * 60;
#
#    # Basisdatum = übergebener Snapshot-Timestamp
#    return if (!$anchor || $anchor eq "");
#    my $baseDate = Time::Piece->strptime(substr($anchor, 0, 10), '%Y-%m-%d');
#    my $one_day  = 24 * 60 * 60;
#
#    # Zielreading und letzter gespeicherter Zeitstempel
#    my $targetReading = $Reading.".day.asSingleValue";
#    my $readingLastTimestamp = ReadingsTimestamp($name, $targetReading, "0000-00-00 00:00:00");
#    my $lastTS = time_str2num($readingLastTimestamp);
#
#    Log3($name, 5, "$name -setpower: target=$targetReading lastTS='$readingLastTimestamp' (num=$lastTS), baseDate=".$baseDate->ymd);
#
#    readingsBeginUpdate($hash);
#    
#    # Älteste -> Neueste, Index 0 (aktueller Tag) wird implizit übersprungen
#    for (my $i = $#values; $i >= 1; $i--) {
#        my $dayDate     = $baseDate - ($one_day * $i);   # i Tage vor baseDate
#        my $readingDate = $dayDate->ymd . " 23:59:59";
#        my $readingTS   = time_str2num($readingDate);
#        my $newVal      = $values[$i];
#
#        Log3($name, 4, "$name - candidate i=$i date=$readingDate val=$newVal lastTS=$lastTS");
#
#        # Nur schreiben, wenn wirklich neuer Tag
#        # Nur schreiben, wenn wirklich neuer Tag UND keine gleiches-Datum-Updates
#        if ($readingTS > $lastTS) {
#            # Wert mit Tag-Zuordnung
#            readingsBulkUpdate($hash, $targetReading, $newVal, undef, $readingDate);
#        
#            # Snapshot-Zeitpunkt (ISO) – Zeitpunkt der Ablesung
#            my $snapReading = $targetReading . ".snapshotTimestamp";
#            readingsBulkUpdate($hash, $snapReading, $anchor);
#        
#            # Tag-Zuordnung separat sichtbar
#            my $tsReading = $targetReading . ".timestamp";
#            readingsBulkUpdate($hash, $tsReading, $readingDate);
#        
#            $lastTS = $readingTS;
#        } else {
#            Log3($name, 4, "$name - skip (not newer) dayTS=$readingTS <= lastTS=$lastTS");
#        }
#    }
#    
#    readingsEndUpdate($hash, 1);
#    return;
#}
sub vitoconnect_getPowerLast {
    my ($hash, $name, $Reading) = @_;

    # Basename ohne letztes Suffix
    $Reading =~ s/\.[^.]*$//;

    # Werte-Liste (robust gegen Leerzeichen, als Zahl)
    my $raw = ReadingsVal($name, $Reading.".day", "");
    my @values = map { 0+$_ } split(/\s*,\s*/, $raw);
    return if (!@values || $#values < 1);  # brauchen mind. Index 1 (gestern)

    # Zielreading und State-Readings
    my $targetReading   = $Reading.".day.asSingleValue";
    my $stateDateRd     = $targetReading.".lastWrittenDate";    # YYYY-MM-DD
    my $stateValRd      = $targetReading.".lastIndex1Value";    # Zahl (nur Sichtbarkeit)

    # Systembasierte Zeitachse (lokal)
    my $now      = localtime();           # Time::Piece
    my $one_day  = 24 * 60 * 60;
    my $yesterday_tp   = $now - $one_day; # Gestern
    my $yesterday_date = $yesterday_tp->ymd;  # 'YYYY-MM-DD'
    my $base_tp        = Time::Piece->strptime($yesterday_date, '%Y-%m-%d'); # Basis "gestern"

    # State laden
    my $lastWrittenDate = ReadingsVal($name, $stateDateRd, "");
    my $lastIndex1Value = 0 + ReadingsVal($name, $stateValRd, -1);

    # Letzter historischer Zeitstempel für das Zielreading (Event-Timestamp)
    my $readingLastTimestamp = ReadingsTimestamp($name, $targetReading, "0000-00-00 00:00:00");
    my $lastTS = time_str2num($readingLastTimestamp);

    # Hilfsfunktion: Tages-Differenz (in vollen Tagen) zwischen zwei YYYY-MM-DD
    my $days_between = sub {
        my ($d1, $d2) = @_; # d1 < d2 erwartet
        my $tp1 = Time::Piece->strptime($d1, '%Y-%m-%d');
        my $tp2 = Time::Piece->strptime($d2, '%Y-%m-%d');
        my $diff = ($tp2 - $tp1) / $one_day;
        return int($diff);
    };

    readingsBeginUpdate($hash);

    # Initialisierung: kein State vorhanden -> gestern schreiben und State setzen
    if (!$lastWrittenDate || $lastWrittenDate eq "") {
        my $val_yesterday = $values[1];
        my $ts = $yesterday_date . " 23:59:59";
        my $rts = time_str2num($ts);

        readingsBulkUpdate($hash, $targetReading, $val_yesterday, undef, $ts);
        readingsBulkUpdate($hash, $stateDateRd, $yesterday_date);
        readingsBulkUpdate($hash, $stateValRd, 0+$val_yesterday);

        Log3($name, 4, "$name - init: write yesterday=$val_yesterday at $ts; set lastWrittenDate=$yesterday_date");
        readingsEndUpdate($hash, 1);
        return;
    }

    # Bereits aktuell? -> nichts tun
    if ($lastWrittenDate eq $yesterday_date) {
        Log3($name, 4, "$name - up-to-date: lastWrittenDate=$lastWrittenDate equals yesterday=$yesterday_date");
        readingsEndUpdate($hash, 1);
        return;
    }

    # Gap-Fill: fehlende Tage bis gestern schreiben, in chronologischer Reihenfolge
    # Beispiel: lastWrittenDate=11., gestern=13. -> erst 12. (Index 2), dann 13. (Index 1)
    my $gapDays = $days_between->($lastWrittenDate, $yesterday_date);
    # Begrenzen auf Array-Länge (Index i muss existieren)
    my $maxFill = ($#values >= 1) ? ($#values >= $gapDays ? $gapDays : $#values) : 0;

    for (my $i = $maxFill; $i >= 1; $i--) {
        # Datum für Index i: i=1 -> gestern, i=2 -> vorgestern, usw.
        my $day_tp = $base_tp - ($one_day * ($i-1));
        my $rd     = $day_tp->ymd . " 23:59:59";
        my $rts    = time_str2num($rd);
        my $val    = $values[$i];

        # Nur anhängen, wenn zeitlich neuer als letzter Eintrag
        next if ($rts <= $lastTS);

        readingsBulkUpdate($hash, $targetReading, $val, undef, $rd);
        Log3($name, 4, "$name - write day i=$i val=$val at $rd");

        $lastTS = $rts;
    }

    # State fortschreiben: jetzt sind wir bis gestern aktuell
    readingsBulkUpdate($hash, $stateDateRd, $yesterday_date);
    readingsBulkUpdate($hash, $stateValRd, 0+$values[1]);

    readingsEndUpdate($hash, 1);
    return;
}




#####################################################################################################################
# Error Code auslesesn
#####################################################################################################################
sub vitoconnect_mapCodeText {
  my ($code) = @_;
  return $viessmann_code_text{$code} // "Unbekannter Fehlercode ($code)";
}

sub vitoconnect_mapSeverityPrefix {
  my ($code) = @_;
  return 'Status'      if $code =~ /^S\./;
  return 'Fehler'      if $code =~ /^F\./;
  return 'Wartung'     if $code =~ /^P\./;
  return 'Information' if $code =~ /^I\./;
  return 'Alarm'       if $code =~ /^A\./;
  return 'Unbekannt';
}

sub vitoconnect_getErrorCode {
  my ($hash, $name, $comma_separated_string) = @_;
  my $language = AttrVal('global', 'language', 0);
  my %severity_translations = (
    'note'          => 'Hinweis',
    'warning'       => 'Warnung',
    'error'         => 'Fehler',
    'criticalError' => 'kritischer Fehler'
  );

  return unless defined $comma_separated_string && $comma_separated_string ne '';

  my $serial = ReadingsVal($name, "device.serial.value", "");
  my $materialNumber = substr($serial, 0, 7);
  my @values = split(/, /, $comma_separated_string);
  my @entries;

  for (my $i = 0; $i < @values; $i += 4) {
    my $source     = $values[$i];
    my $code       = $values[$i + 1];
    my $category   = $values[$i + 2];
    my $ts_raw     = $values[$i + 3];

    $ts_raw =~ s/Z$//;
    my $t;
    eval { $t = Time::Piece->strptime($ts_raw, "%Y-%m-%dT%H:%M:%S") };
    my $timestamp = $t ? $t->strftime("%d.%m.%Y %H:%M:%S") : $ts_raw;

    my $severity = $severity_translations{$category} if uc($language) eq 'DE';
    $severity //= vitoconnect_mapSeverityPrefix($code);

    my $text = vitoconnect_mapCodeText($code);
    $text = "Unbekannter Code ($code)" if $text =~ /^Unbekannter Fehlercode/;

    my $url = "$errorURL_V3?materialNumber=$materialNumber&errorCode=$code&countryCode=${\uc($language)}&languageCode=${\lc($language)}";
    my $param = {
      url     => $url,
      hash    => $hash,
      timeout => $hash->{timeout},
      method  => "GET",
      sslargs => { SSL_verify_mode => 0 },
    };

    Log3($name, 5, "$name: API call for $code via $url");
    my ($err, $msg) = HttpUtils_BlockingGet($param);
    my $decode_json = eval { JSON->new->decode($msg) };

    if (!$err && !$decode_json->{statusCode} && ref($decode_json->{faultCodes}) eq 'ARRAY' && @{$decode_json->{faultCodes}}) {
      my $api_text = $decode_json->{faultCodes}[0]{systemCharacteristics};
      $api_text =~ s/<\/?(p|q)>//g if defined $api_text;
      $text = $api_text if defined $api_text && $api_text ne '';
    }

    push @entries, {
      timestamp => $timestamp,
      code      => $code,
      text      => $text,
    };
  }

  # Sort entries by timestamp descending using epoch
  @entries = sort {
    my $a_epoch = eval { Time::Piece->strptime($a->{timestamp}, "%d.%m.%Y %H:%M:%S")->epoch } || 0;
    my $b_epoch = eval { Time::Piece->strptime($b->{timestamp}, "%d.%m.%Y %H:%M:%S")->epoch } || 0;
    $b_epoch <=> $a_epoch;
  } @entries;

  my %grouped;
  foreach my $entry (@entries) {
    my $code = $entry->{code};
    my $type = 'unknown';
    $type = 'errors'  if $code =~ /^F\./;
    $type = 'info'    if $code =~ /^I\./;
    $type = 'status'  if $code =~ /^S\./;
    $type = 'service' if $code =~ /^P\./;
    push @{ $grouped{$type} }, $entry;
  }

  my $now = time();

  foreach my $type (keys %grouped) {
    my %raw_keys;
    foreach my $entry (@{ $grouped{$type} }) {
      my $key = "$entry->{timestamp}|$entry->{code}";
      $raw_keys{$key} = 1;
    }

    my $existing = ReadingsVal($name, "device.messages.$type.list", "");
    my @existing_entries = split(/\n/, $existing);
    my %existing_map;

    foreach my $line (@existing_entries) {
      if ($line =~ /^(\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}) - (\S+) - (.+)$/) {
        my ($ts, $code, $text) = ($1, $2, $3);
        my $t = eval { Time::Piece->strptime($ts, "%d.%m.%Y %H:%M:%S") };
        my $age = $t ? $now - $t->epoch : 0;
        my $key = "$ts|$code";
        $existing_map{$key} = "$ts - $code - $text" if $age <= 86400 || exists $raw_keys{$key};
      }
    }

    foreach my $entry (@{ $grouped{$type} }) {
      my $key = "$entry->{timestamp}|$entry->{code}";
      $existing_map{$key} = "$entry->{timestamp} - $entry->{code} - $entry->{text}" unless exists $existing_map{$key};
    }

    # Final sort by timestamp descending using epoch
    my @final = sort {
      my ($a_ts) = ($a =~ /^(\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})/);
      my ($b_ts) = ($b =~ /^(\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})/);
      my $a_epoch = eval { Time::Piece->strptime($a_ts, "%d.%m.%Y %H:%M:%S")->epoch } || 0;
      my $b_epoch = eval { Time::Piece->strptime($b_ts, "%d.%m.%Y %H:%M:%S")->epoch } || 0;
      $b_epoch <=> $a_epoch;
    } values %existing_map;

    my $joined = join("\n", @final) . "\n";
    readingsBulkUpdate($hash, "device.messages.$type.list", $joined);
  }

  return;
}


#####################################################################################################################
# Setzen von Daten über Timer
#####################################################################################################################
sub vitoconnect_actionTimerWrapper {
    my ($argRef) = @_;
    
    unless (ref($argRef) eq 'ARRAY') {
        my $type = ref($argRef) // 'undef';
        my $name = ref($argRef) eq 'HASH' ? $argRef->{NAME} // 'unknown' : 'unknown';
        Log3($name, 1, "$name - vitoconnect_actionTimerWrapper: Fehlerhafte Argumentübergabe (Typ: $type), erwartet ARRAY-Referenz");
        return;
    }

    vitoconnect_action(@$argRef);
}


#####################################################################################################################
# Setzen von Daten
#####################################################################################################################
sub vitoconnect_action {
    my ($hash, $feature, $data, $name, $opt, @args) = @_;
    return delete $hash->{".action_retry_count"} if IsDisabled($name);  # Modul deaktiviert → abbrechen

    my $access_token = $hash->{".access_token"};
    my $installation = AttrVal($name, 'vitoconnect_installationID', 0);
    my $gw           = AttrVal($name, 'vitoconnect_serial', 0);
    my $dev          = AttrVal($name, 'vitoconnect_device', 0);
    my $Text         = join(' ', @args);
    my $retry_count = $hash->{".action_retry_count"} // 0;

    my $param = {
        url => $featureURL."installations/$installation/gateways/$gw/devices/$dev/features/$feature",
        hash   => $hash,
        header => "Authorization: Bearer $access_token\r\nContent-Type: application/json",
        data    => $data,
        timeout => $hash->{timeout},
        method  => "POST",
        sslargs => { SSL_verify_mode => 0 },
    };

    Log3($name,3,$name.", vitoconnect_action url=" .$param->{url}); # change back to 3
    Log3($name,3,$name.", vitoconnect_action data=".$param->{data}); # change back to 3
#   https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_BlockingGet
    my ($err, $msg) = HttpUtils_BlockingGet($param);
    my $decode_json = eval { decode_json($msg) };

    if ((defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "")) {
        $retry_count++;
        $hash->{".action_retry_count"} = $retry_count;
        readingsSingleUpdate($hash, "Aktion_Status", "Fehler ($retry_count/20): $opt $Text", 1);
        # Log3($name, 2, "$name - RetryLoop Fehler: $err :: $msg");
        Log3($name,1,$name.",vitoconnect_action: set ".$name." ".$opt." ".@args.", Fehler bei Befehlsausfuehrung ($retry_count/20): ".$err." :: ".$msg);

        # Token abgelaufen?
        if ($decode_json->{statusCode} eq "401" && $decode_json->{error} eq "EXPIRED TOKEN") {
            # Token erneuern, aber ohne getResource
            $hash->{".retry_feature"} = $feature;
            $hash->{".retry_data"}    = $data;
            $hash->{".retry_opt"}     = $opt;
            $hash->{".retry_args"}    = [@args];
            $hash->{".action_retry_count"} = $retry_count;
            vitoconnect_getRefresh($hash, 'action');  # Kontext 'action' → kein getResource
            return;
        }

        # Wiederholen in 10 Sekunden
        if ($retry_count < 20) {
          InternalTimer(gettimeofday() + 10, "vitoconnect_actionTimerWrapper", [$hash, $feature, $data, $name, $opt, @args]);
        } else {
            Log3($name, 1, "$name - vitoconnect_action: Abbruch nach 20 Fehlversuchen");
            readingsSingleUpdate($hash, "Aktion_Status", "Fehlgeschlagen: $opt $Text (nach 20 Versuchen)", 1);
            # Abbruch nach 20 versuchen → Retry-Zähler und Daten zurücksetzen
            delete $hash->{".action_retry_count"};
            delete $hash->{".retry_feature"};
            delete $hash->{".retry_data"};
            delete $hash->{".retry_opt"};
            delete $hash->{".retry_args"};
        }
        return;
    }

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
        
        # Erfolg → Retry-Zähler und Daten zurücksetzen
        delete $hash->{".action_retry_count"};
        delete $hash->{".retry_feature"};
        delete $hash->{".retry_data"};
        delete $hash->{".retry_opt"};
        delete $hash->{".retry_args"};

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
                vitoconnect_getRefresh($hash,'update');    # neuen Access-Token anfragen
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
                  "$name - Anzahl der möglichen API Calls in überschritten! Caller Name: $hash->{NAME}, memoryadress: $hash";
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
                readingsSingleUpdate($hash,"state","unbekannter Fehler, bitte den Entwickler informieren! (Typ: "
                                     . ($items->{errorType} // 'undef') . " Grund: "
                                     . ($items->{extendedPayload}->{reason} // 'NA') . ")",1);
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
# SVG füllen
#####################################################################################################################
sub vitoconnect_FW_detailFn {
    my ($FW_wname, $d, $room, $pageHash) = @_;

    # 1. Attribut abfragen (Default ist 0, wenn nicht gesetzt)
    my $showKK = AttrVal($d, "vitoconnect_showKaeltekreislauf", 0);

    # 2. Wenn 0, dann nichts anzeigen
    return undef if (!$showKK);
    
    my $svg = $main::vitoconnect_svg_kaeltekreislauf;

    # --- Logik für Stati und Farben ---
    my $valvePos    = ReadingsVal($d, 'heating.valves.fourThreeWay.position.value', '');
    my $isDefrost = ReadingsVal($d, 'heating.outdoor.defrosting.active', undef) // ReadingsVal($d, 'heating.circuits.1.frostprotection.status', 0);
    my $compActive  = ReadingsVal($d, 'heating.compressors.0.active', 0);
    my $secState    = ReadingsVal($d, 'heating.secondaryHeatGenerator.status.value', 'off');
    my $secTemp     = ReadingsVal($d, 'heating.secondaryHeatGenerator.temperature.current.value', '--');

    # Standardwerte (Standby / Aus)
    my $overlayColor = "rgba(180, 180, 180, 0.2)"; # Sehr helles, neutrales Grau
    my $statusStr    = "Standby";
    my $wpIconClr    = "#bdc3c7"; # Silbergrau für das Icon

    # Priorisierung der Zustände
    if ($isDefrost == 1) { #|| $valvePos eq "climatCircuitTwoDefrost") {
        # Abtauen (Türkis)
        $overlayColor = "rgba(94, 187, 189, 0.5)";  
        $statusStr    = "Abtauen";
        $wpIconClr    = "#0088cc";  
    } elsif ($compActive == 1) {
        # WP läuft (Kompressor an)
        $wpIconClr = "#2ecc71"; # Grün
        
        if ($valvePos eq "domesticHotWater") {
            # Warmwasser (Bernstein)
            $overlayColor = "rgba(255, 235, 150, 0.5)";
            $statusStr    = "Warmwasser";
        } else {
            # Heizbetrieb (Keine Färbung oder ganz zartes Blau)
            $overlayColor = "rgba(255, 255, 255, 0)";  
            $statusStr    = "Heizbetrieb";
        }
    } else {
        # Kompressor ist AUS, aber vielleicht läuft die interne Pumpe noch?
        $overlayColor = "rgba(200, 200, 200, 0.5)";
        $statusStr    = "WP Standby";
    }


    # Brenner-Status kombiniert mit Temperatur
    my $secStatusStr = ($secState eq "on") ? "Aktiv (" . $secTemp . " &#176;C)" : "Aus";
    my $secIconClr   = ($secState eq "on") ? "#ff4500" : "#999999";

    # --- Die Map (Präzise Kleinschreibung für die Ersetzung) ---
my %map = (

    # 1 Außentemperatur
    '%out_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.sensors.temperature.outside.value'
    ),

    # 18 Verdampfer Flüssiggas / Sauggas
    '%evp_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
       (ReadingsVal($d,'heating.coolingCircuits.0.type.value','') =~ /200-S/i)
           ? ()   # 200-S → kein echter Verdampfer-Flüssigsensor
           : ('heating.evaporators.0.sensors.temperature.liquid.value')
    ),

    # 3 Überhitzung
    '%evp_tmp_over%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.evaporators.0.sensors.temperature.overheat.value'
    ),

    # 5 Sauggastemperatur (vor Verdichter)
    '%comp_in%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.compressors.0.sensors.temperature.inlet.value',
    ),

    # 12 Heißgastemperatur (nach Verdichter)
    '%comp_out%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.compressors.0.sensors.temperature.outlet.value',
    ),

    # 6 Verdichtergehäuse / Motor
    '%comp_motor%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.compressors.0.sensors.temperature.motorChamber.value',
        'heating.compressors.0.sensors.temperature.ambient.value'
    ),

    # 16 Economizer Temperatur
    '%eco_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.economizers.0.sensors.temperature.liquid.value'
    ),

    # 14 Kondensator Flüssiggastemperatur
    '%cond_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        (ReadingsVal($d,'heating.coolingCircuits.0.type.value','') =~ /200-S/i)
           ? 'heating.evaporators.0.sensors.temperature.liquid.value'   # 200-S falsch gemappt → hier korrigieren
           : 'heating.condensors.0.sensors.temperature.liquid.value'    # 250-AH korrekt
    ),

    # 19 Vorlauf Sekundärkreis
    '%heat_suppl%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.secondaryCircuit.sensors.temperature.supply.value'
    ),

    # 21 Rücklauf Sekundärkreis
    '%heat_return%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.sensors.temperature.return.value'
    ),

    # 22 Warmwasser
    '%dhw_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.dhw.sensors.temperature.hotWaterStorage.value',
        'heating.dhw.sensors.temperature.hotWaterStorage.top.value',
        'heating.dhw.sensors.temperature.dhwCylinder.value',
        'heating.dhw.sensors.temperature.dhwCylinder.top.value'
    ),

    # 23 Pufferspeicher
    '%heat_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.buffer.sensors.temperature.main.value',
        'heating.bufferCylinder.sensors.temperature.main.value',
        'heating.bufferCylinder.sensors.temperature.top.value'
    ),

    # 4 Sauggasdruck
    '%comp_pres%' => vitoconnect_fmt_fallback($d, ' bar', 2,
        'heating.compressors.0.sensors.pressure.inlet.value',
    ),

    # 25 Durchfluss Heizkreis (Original: bar!)
    '%heat_pres%' => vitoconnect_fmt_fallback($d, ' bar', 1,
        'heating.sensors.pressure.supply.value'
    ),

    # 13 Hochdruck (Original: kein Wert)
    '%high_pres%' => vitoconnect_fmt_fallback($d, ' bar', 1,
        'heating.sensors.pressure.hotGas.value'
    ),

    # 7 Verdichterleistung
    '%comp_speed%' => vitoconnect_fmt_fallback($d, ' %', 0,
        'heating.compressors.0.speed.current.value',
        'heating.compressors.0.sensors.power.value'
    ),

    # 2.1 Ventilator 1
    '%fan0%' => vitoconnect_fmt_fallback($d, ' %', 0,
        'heating.primaryCircuit.fans.0.current.value',
        'heating.primaryCircuit.sensors.rotation.value'
    ),

    # 2.2 Ventilator 2
    '%fan1%' => vitoconnect_fmt_fallback($d, ' %', 0,
        'heating.primaryCircuit.fans.1.current.value',
        'heating.primaryCircuit.sensors.rotation.value'
    ),

    # 17 Expansionsventil 0
    '%valve0%' => vitoconnect_fmt_fallback($d, ' %', 0,
        'heating.sensors.valve.0.expansion.target.value'
    ),

    # 15 Expansionsventil 1
    '%valve1%' => vitoconnect_fmt_fallback($d, ' %', 0,
        'heating.sensors.valve.1.expansion.target.value'
    ),

    # 20 Sekundärpumpe
    '%pump1%' => vitoconnect_fmt_fallback($d, ' %', 0,
        'heating.boiler.pumps.internal.current.value'
    ),

    # 24 Allengra (Original: l/h!)
    '%allengra%' => vitoconnect_fmt_fallback($d, ' l/h', 0,
        'heating.sensors.volumetricFlow.allengra.value'
    ),

    # 8 Öltemperatur (Original: Reading, kein Status!)
    '%comp_oil%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.compressors.0.sensors.temperature.oil.value'
    ),

    # 9 Inverter Temperatur
    '%inv_tmp%' => vitoconnect_fmt_fallback($d, ' &#176;C', 1,
        'heating.inverters.0.sensors.temperature.powerModule.value'
    ),

    # 10 Inverter Leistung
    '%inv_watt%' => vitoconnect_fmt_fallback($d, ' W', 0,
        'heating.inverters.0.sensors.power.output.value'
    ),

    # 11 Inverter Strom
    '%inv_amp%' => vitoconnect_fmt_fallback($d, ' A', 1,
        'heating.inverters.0.sensors.power.current.value'
    ),

    # Status / Farben
    '%status%'        => $statusStr,
    '%overlay_color%' => $overlayColor,
    '%sec_status%'    => $secStatusStr,
    '%sec_icon_clr%'  => $secIconClr,
    '%wp_icon_clr%'   => $wpIconClr,

    '%TITEL%'         => 'K&#228;ltekreislauf',
);

    # Ersetzung im SVG
    for my $ph (keys %map) {
        my $val = $map{$ph};
        $svg =~ s/\Q$ph\E/$val/g;
    }

    return $svg;
}

sub vitoconnect_fmt_fallback {
    my ($d, $unit, $dec, @paths) = @_;

    foreach my $path (@paths) {
        my $val = ReadingsVal($d, $path, undef);
        next unless defined $val;

        $unit =~ s/°/&#176;/g;
        return sprintf("%.${dec}f", $val) . $unit;
    }

    return "---";
}


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
            You need to create an API Key under <a href="https://developer.viessmann-climatesolutions.com/">https://developer.viessmann-climatesolutions.com/</a>.
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

    <a name="vitoconnect-get"></a>
    <b>Get</b><br>
    <ul>
        <a id="vitoconnect-get-html"></a>
        <li><code>html</code><br>
            get HTML of Kältekreislauf. Kältekreislauf can also be used in FTUI with widget_vitoconnect.js</li> 
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
        <a id="vitoconnect-attr-vitoconnect_showKaeltekreislauf"></a>
        <li><i>vitoconnect_showKaeltekreislauf</i>:<br>
            You can show the Viessmann Kältegreislauf at the top of the device view.
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
            Ein API-Schlüssel muss unter https://developer.viessmann-climatesolutions.com/ erstellt werden.
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

<br>

    <a name="vitoconnect-get"></a>
    <b>Get</b><br>
    <ul>
        <a id="vitoconnect-get-html"></a>
        <li><code>html</code><br>
            Kältekreislauf als HTML, auch zur Benutzung auf dem Tablet UI mit widget_vitoconnect.js</li> 
    </ul>
    <br>
</ul>

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
        <a id="vitoconnect-attr-vitoconnect_showKaeltekreislauf"></a>
        <li><i>vitoconnect_showKaeltekreislauf</i>:<br>
            Es kann der Viessmann Kältegreislauf oben in der Device Ansicht angeizeigt werden.
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
