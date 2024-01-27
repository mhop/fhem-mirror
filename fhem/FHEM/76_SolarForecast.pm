########################################################################################################################
# $Id$
#########################################################################################################################
#       76_SolarForecast.pm
#
#       (c) 2020-2024 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
#
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       This copyright notice MUST APPEAR in all copies of the script!
#
#########################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 76_SolarForecast.pm
#
#########################################################################################################################
package FHEM::SolarForecast;                              ## no critic 'package'

use strict;
use warnings;
use POSIX;
use GPUtils qw(GP_Import GP_Export);                                                 # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday tv_interval);

eval "use FHEM::Meta;1"                   or my $modMetaAbsent = 1;                  ## no critic 'eval'
eval "use FHEM::Utility::CTZ qw(:all);1;" or my $ctzAbsent     = 1;                  ## no critic 'eval'

use Encode;
use Color;
use utf8;
use HttpUtils;
eval "use JSON;1;"                        or my $jsonabs = 'JSON';                   ## no critic 'eval' # Debian: sudo apt-get install libjson-perl
eval "use AI::DecisionTree;1;"            or my $aidtabs = 'AI::DecisionTree';       ## no critic 'eval'

use FHEM::SynoModules::SMUtils qw(
                                   checkModVer
                                   evaljson
                                   getClHash
                                   delClHash
                                   moduleVersion
                                   trim
                                 );                                                  # Hilfsroutinen Modul

use Data::Dumper;
use Blocking;
use Storable qw(dclone freeze thaw nstore store retrieve);
use MIME::Base64;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          attr
          asyncOutput
          AnalyzePerlCommand
          AnalyzeCommandChain
          AttrVal
          AttrNum
          BlockingCall
          BlockingKill
          CommandAttr
          CommandGet
          CommandSet
          CommandSetReading
          data
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          DoTrigger
          Debug
          fhemTimeLocal
          fhemTimeGm
          fhem
          FileWrite
          FileRead
          FileDelete
          FmtTime
          FmtDateTime
          FW_makeImage
          getKeyValue
          getAllAttr
          getAllGets
          getAllSets
          HttpUtils_NonblockingGet
          HttpUtils_BlockingGet
          init_done
          InternalTimer
          InternalVal
          IsDisabled
          Log
          Log3
          modules
          parseParams
          perlSyntaxCheck
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          ReplaceEventMap
          readingFnAttributes
          setKeyValue
          sortTopicNum
          sunrise_abs_dat
          sunset_abs_dat
          FW_cmd
          FW_directNotify
          FW_ME
          FW_subdir
          FW_pH
          FW_room
          FW_detail
          FW_widgetOverride
          FW_wname
          readyfnlist
        )
  );

  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
          pageAsHtml
          NexthoursVal
        )
  );

}

# Versions History intern
my %vNotesIntern = (
  "1.13.0" => "27.01.2024  minor change of deleteOldBckpFiles, Setter writeHistory replaced by operatingMemory ".
                           "save, backup and recover in-memory operating data ",
  "1.12.0" => "26.01.2024  create backup files and delete old generations of them ",
  "1.11.1" => "26.01.2024  fix ___switchonTimelimits ",
  "1.11.0" => "25.01.2024  consumerXX: notbefore, notafter format extended to possible perl code {...} ",
  "1.10.0" => "24.01.2024  consumerXX: notbefore, notafter format extended to hh[:mm], new sub checkCode, checkhhmm ",
  "1.9.0"  => "23.01.2024  modify disable, add operationMode: active/inactive ",
  "1.8.0"  => "22.01.2024  add 'noLearning' Option to Setter pvCorrectionFactor_Auto ",
  "1.7.1"  => "20.01.2024  optimize battery management ",
  "1.7.0"  => "18.01.2024  Changeover Start centralTask completely to runCentralTask, ".
                           "aiAddRawData: Weekday from pvHistory not taken into account greater than current day  ".
                           "__reviewSwitchTime: new function for review consumer planning state ".
                           "___switchonTimelimits: The current time is taken into account during planning ".
                           "take info-tag into consumerxx Reading ".
                           "fix deletion of currentBatteryDev, currentInverterDev, currentMeterDev ",
  "1.6.5"  => "10.01.2024  new function runCentralTask in ReadyFn to run centralTask definitely at end/begin of an hour ",
  "1.6.4"  => "09.01.2024  fix get Automatic State, use key switchdev for auto-Reading if switchdev is set in consumer attr ",
  "1.6.3"  => "08.01.2024  optimize battery management once more ",
  "1.6.2"  => "07.01.2024  optimize battery management ",
  "1.6.1"  => "04.01.2024  new sub __setPhysSwState, edit ___setConsumerPlanningState, boost performance of collectAllRegConsumers ".
                           "CurrentVal ctrunning - Central Task running Statusbit, edit comref ",
  "1.6.0"  => "22.12.2023  store daily batmaxsoc in pvHistory, new attr ctrlBatSocManagement, reading Battery_OptimumTargetSoC ".
                           "currentBatteryDev: new optional key 'cap', adapt cloud2bin,temp2bin,rain2bin ".
                           "minor internal changes, isAddSwitchOffCond: change hysteresis algo, ctrlDebug: new entry batteryManagement ".
                           "check longitude, latitude in general audit, use coordinates (if set) for sun calc ",
  "1.5.1"  => "07.12.2023  function _getftui can now process arguments (compatibility to new ftui widgets), plant check ".
                           "reviews SolarForecast widget files ",
  "1.5.0"  => "05.12.2023  new getter ftuiFramefiles ",
  "1.4.3"  => "03.12.2023  hidden set or attr commands in user specific header area when called by 'get ... html' ".
                           "plantConfig: check module update in repo ",
  "1.4.2"  => "02.12.2023  ___getFWwidget: codechange ___getFWwidget using __widgetFallback function ",
  "1.4.1"  => "01.12.2023  ___getFWwidget: adjust for FHEMWEB feature forum:#136019 ",
  "1.4.0"  => "29.11.2023  graphicHeaderOwnspec: can manage attr / sets of other devs by <attr|set>@<dev> ",
  "1.3.0"  => "27.11.2023  new Attr graphicHeaderOwnspecValForm ",
  "1.2.0"  => "25.11.2023  graphicHeaderOwnspec: show readings of other devs by <reaging>@<dev>, Set/reset batteryTrigger ",
  "1.1.3"  => "24.11.2023  rename reset arguments according possible adjustable textField width ",
  "1.1.2"  => "20.11.2023  ctrlDebug Adjustment of column width, must have new fhemweb.js Forum:#135850 ",
  "1.1.1"  => "19.11.2023  graphicHeaderOwnspec: fix ignoring the last element of allsets/allattr ",
  "1.1.0"  => "14.11.2023  graphicHeaderOwnspec: possible add set/attr commands, new setter consumerNewPlanning ",
  "1.0.10" => "31.10.2023  fix warnings, edit comref ",
  "1.0.9"  => "29.10.2023  _aiGetSpread: set spread from 50 to 20 ",
  "1.0.8"  => "22.10.2023  codechange: add central readings store array, new function storeReading, writeCacheToFile ".
                           "solcastapi in sub __delObsoleteAPIData, save freespace if flowGraphicShowConsumer=0 is set ".
                           "pay attention to attr graphicEnergyUnit in __createOwnSpec ",
  "1.0.7"  => "21.10.2023  more design options for graphicHeaderOwnspec and a possible line title ",
  "1.0.6"  => "19.10.2023  new attr ctrlGenPVdeviation ",
  "1.0.5"  => "11.10.2023  new sub _aiGetSpread for estimate AI results stepwise, allow key 'noshow' values 0,1,2,3 ".
                           "calculate conForecastTillNextSunrise accurate to the minute ",
  "1.0.4"  => "10.10.2023  fix: print always Log in _calcCaQ* subroutines even if calaculated factors are equal ".
                           "new consumer attr key 'noshow' ",
  "1.0.3"  => "08.10.2023  change graphic header PV/CO detail, new attr graphicHeaderOwnspec, internal code changes ".
                           "fix isAddSwitchOffCond 0 Forum: https://forum.fhem.de/index.php?msg=1288877 ".
                           "change calcValueImproves and subroutines ",
  "1.0.2"  => "05.10.2023  replace calcRange by cloud2bin ",
  "1.0.1"  => "03.10.2023  fixes in comRef, bug fix Forum: https://forum.fhem.de/index.php?msg=1288637 ",
  "1.0.0"  => "01.10.2023  preparation for check in ",
  "0.83.3" => "28.09.2023  fix Illegal division by zero, Forum: https://forum.fhem.de/index.php?msg=1288032 ".
                           "delete AllPVforecastsToEvent after event generation ",
  "0.83.2" => "26.09.2023  setter reset consumption ",
  "0.83.1" => "26.09.2023  change currentRadiationDev to currentRadiationAPI, new attr ctrlAIdataStorageDuration ".
                           "new elements todayConsumptionForecast, conForecastTillNextSunrise for attr ctrlStatisticReadings ".
                           "add entry text in guided procedure ",
  "0.83.0" => "19.09.2023  add manageTrain for AI Training in parallel process ",
  "0.82.4" => "16.09.2023  generate DWD API graphics header information and extend plant check for DWD API errors, minor fixes ",
  "0.82.3" => "14.09.2023  more mouse over information in graphic header, ai support in autocorrection selectable ".
                           "substitute use of Test2::Suite ",
  "0.82.2" => "11.09.2023  activate implementation of DWD AI support, add runTimeTrainAI ",
  "0.82.1" => "08.09.2023  rebuild implementation of DWD AI support, some error fixing (FHEM restarts between 0 and 1) ",
  "0.82.0" => "02.09.2023  first implementation of DWD AI support, new ctrlDebug aiProcess aiData, reset aiData ",
  "0.81.1" => "30.08.2023  show forecast qualities when pressing quality icon in forecast grafic, store rad1h (model DWD) in ".
                           "pvhistory, removed: affectCloudfactorDamping, affectRainfactorDamping ",
  "0.81.0" => "27.08.2023  development version for Victron VRM API, __Pv_Fc_Simple_Dnum_Hist changed, available setter ".
                           "are now API specific, switch currentForecastDev to currentWeatherDev ".
                           "affectCloudfactorDamping default 0, affectRainfactorDamping default 0 ".
                           "call consumption forecast from Victron VRM API ",
  "0.80.20"=> "15.08.2023  hange calculation in ___setSolCastAPIcallKeyData once again, fix some warnings ",
  "0.80.19"=> "10.08.2023  fix Illegal division by zero, Forum: https://forum.fhem.de/index.php?msg=1283836 ",
  "0.80.18"=> "07.08.2023  change calculation of todayDoneAPIcalls in ___setSolCastAPIcallKeyData, add \$lagtime ".
                           "Forum: https://forum.fhem.de/index.php?msg=1283487 ",
  "0.80.17"=> "05.08.2023  change sequence of _createSummaries in centralTask, ComRef edited ",
  "0.80.16"=> "26.07.2023  new consumer type noSchedule, expand maxconsumer to 16, minor changes/fixes ",
  "0.80.15"=> "24.07.2023  new sub getDebug, new key switchdev in consumer attributes, change Debug consumtion ".
                           "reorg data in pvHistory when a hour of day was deleted ",
  "0.80.14"=> "21.07.2023  __substConsumerIcon: use isConsumerLogOn instead of isConsumerPhysOn ",
  "0.80.13"=> "18.07.2023  include parameter DoN in nextHours hash, new KPI's todayConForecastTillSunset, currentRunMtsConsumer_XX ".
                           "minor fixes and improvements ",
  "0.80.12"=> "16.07.2023  preparation for alternative switch device in consumer attribute, revise CommandRef ".
                           "fix/improve sub ___readCandQ and much more, get pvHistory -> one specific day selectable ".
                           "get valConsumerMaster -> one specific consumer selectable, enhance consumer key locktime by on-locktime ",
  "0.80.11"=> "14.07.2023  minor fixes and improvements ",
  "0.80.10"=> "13.07.2023  new key spignorecond in consumer attributes ",
  "0.80.9" => "13.07.2023  new method of prediction quality calculation -> sub __calcFcQuality, minor bug fixes ",
  "0.80.8" => "12.07.2023  store battery values initdaybatintot, initdaybatouttot, batintot, batouttot in circular hash ".
                           "new Attr ctrlStatisticReadings parameter todayBatIn, todayBatOut ",
  "0.80.7" => "10.07.2023  Model SolCastAPI: retrieve forecast data of 72h (old 48), create statistic reading dayAfterTomorrowPVforecast if possible ",
  "0.80.6" => "09.07.2023  get ... html has some possible arguments now ",
  "0.80.5" => "07.07.2023  calculate _calcCaQcomplex, _calcCaQsimple both at every time, change setter pvCorrectionFactor_Auto: on_simple, on_complex, off ",
  "0.80.4" => "06.07.2023  new transferprocess for DWD data from solcastapi-Hash to estimate calculation, consolidated ".
                           "the autocorrection model ",
  "0.80.3" => "03.06.2023  preparation for get DWD radiation data to solcastapi-Hash, fix sub isConsumerLogOn (use powerthreshold) ",
  "0.80.2" => "02.06.2023  new ctrlDebug keys epiecesCalc, change selfconsumption with graphic Adjustment, moduleDirection ".
                           "accepts azimut values -180 .. 0 .. 180 as well as azimut identifier (S, SE ..) ",
  "0.80.1" => "31.05.2023  adapt _calcCaQsimple to calculate corrfactor like _calcCaQcomplex ",
  "0.80.0" => "28.05.2023  Support for Forecast.Solar-API (https://doc.forecast.solar/api), rename Getter solCastData to solApiData ".
                           "rename ctrlDebug keys: solcastProcess -> apiProcess, solcastAPIcall -> apiCall ".
                           "calculate cloudiness correction factors proactively and store it in circular hash ".
                           "new reading Current_Surplus, ___noPlanRelease -> only one call releases the consumer planning ",
  "0.79.3" => "21.05.2023  new CircularVal initdayfeedin, deactivate \$hash->{HELPER}{INITFEEDTOTAL}, \$hash->{HELPER}{INITCONTOTAL} ".
                           "new statistic Readings statistic_todayGridFeedIn, statistic_todayGridConsumption ",
  "0.79.2" => "21.05.2023  change process to calculate solCastAPIcallMultiplier, todayMaxAPIcalls ",
  "0.79.1" => "19.05.2023  extend debug apiProcess, new key apiCall ",
  "0.79.0" => "13.05.2023  new consumer key locktime ",
  "0.78.2" => "11.05.2023  extend debug radiationProcess ",
  "0.78.1" => "08.05.2023  change default icon it_ups_on_battery to batterie ",
  "0.78.0" => "07.05.2023  activate NotifyFn Forum:https://forum.fhem.de/index.php?msg=1275005, new Consumerkey asynchron ",
  "0.77.1" => "07.05.2023  rewrite function pageRefresh ",
  "0.77.0" => "03.05.2023  new attribute ctrlUserExitFn ",
  "0.76.0" => "01.05.2023  new ctrlStatisticReadings SunMinutes_Remain, SunHours_Remain ",
  "0.75.3" => "23.04.2023  fix Illegal division by zero at ./FHEM/76_SolarForecast.pm line 6199 ",
  "0.75.2" => "16.04.2023  some minor changes ",
  "0.75.1" => "24.03.2023  change epieces for consumer type washingmachine, PV Vorhersage auf WR Kapazität begrenzen ",
  "0.75.0" => "16.02.2023  new attribute ctrlSolCastAPImaxReq, rename attr ctrlOptimizeSolCastInterval to ctrlSolCastAPIoptimizeReq ",
  "0.74.8" => "11.02.2023  change description of 'mintime', mintime with SunPath value possible ",
  "0.74.7" => "23.01.2023  fix evaljson evaluation ",
  "0.1.0"  => "09.12.2020  initial Version "
);

## default Variablen
######################
my @da;                                                                             # Readings-Store
my $deflang        = 'EN';                                                          # default Sprache wenn nicht konfiguriert
my @chours         = (5..21);                                                       # Stunden des Tages mit möglichen Korrekturwerten
my $kJtokWh        = 0.00027778;                                                    # Umrechnungsfaktor kJ in kWh
my $defmaxvar      = 0.5;                                                           # max. Varianz pro Tagesberechnung Autokorrekturfaktor
my $definterval    = 70;                                                            # Standard Abfrageintervall
my $defslidenum    = 3;                                                             # max. Anzahl der Arrayelemente in Schieberegistern
my $maxSoCdef      = 95;                                                            # default Wert (%) auf den die Batterie maximal aufgeladen werden soll bzw. als aufgeladen gilt
my $carecycledef   = 20;                                                            # max. Anzahl Tage die zwischen der Batterieladung auf maxSoC liegen dürfen
my $batSocChgDay   = 5;                                                             # prozentuale SoC Änderung pro Tag
my @widgetreadings = ();                                                            # Array der Hilfsreadings als Attributspeicher

my $root           = $attr{global}{modpath};                                        # Pfad zu dem Verzeichnis der FHEM Module
my $cachedir       = $root."/FHEM/FhemUtils";                                       # Directory für Cachefiles
my $pvhcache       = $root."/FHEM/FhemUtils/PVH_SolarForecast_";                    # Filename-Fragment für PV History (wird mit Devicename ergänzt)
my $pvccache       = $root."/FHEM/FhemUtils/PVC_SolarForecast_";                    # Filename-Fragment für PV Circular (wird mit Devicename ergänzt)
my $plantcfg       = $root."/FHEM/FhemUtils/PVCfg_SolarForecast_";                  # Filename-Fragment für PV Anlagenkonfiguration (wird mit Devicename ergänzt)
my $csmcache       = $root."/FHEM/FhemUtils/PVCsm_SolarForecast_";                  # Filename-Fragment für Consumer Status (wird mit Devicename ergänzt)
my $scpicache      = $root."/FHEM/FhemUtils/ScApi_SolarForecast_";                  # Filename-Fragment für Werte aus SolCast API (wird mit Devicename ergänzt)
my $aitrained      = $root."/FHEM/FhemUtils/AItra_SolarForecast_";                  # Filename-Fragment für AI Trainingsdaten (wird mit Devicename ergänzt)
my $airaw          = $root."/FHEM/FhemUtils/AIraw_SolarForecast_";                  # Filename-Fragment für AI Input Daten = Raw Trainigsdaten

my $aitrblto       = 7200;                                                          # KI Training BlockingCall Timeout
my $aibcthhld      = 0.2;                                                           # Schwelle der KI Trainigszeit ab der BlockingCall benutzt wird
my $aistdudef      = 1095;                                                          # default Haltezeit KI Raw Daten (Tage)

my $calcmaxd       = 30;                                                            # Anzahl Tage die zur Berechnung Vorhersagekorrektur verwendet werden
my @dweattrmust    = qw(TTT Neff R101 ww SunUp SunRise SunSet);                     # Werte die im Attr forecastProperties des Weather-DWD_Opendata Devices mindestens gesetzt sein müssen
my @draattrmust    = qw(Rad1h);                                                     # Werte die im Attr forecastProperties des Radiation-DWD_Opendata Devices mindestens gesetzt sein müssen
my $whistrepeat    = 900;                                                           # Wiederholungsintervall Cache File Daten schreiben

my $solapirepdef   = 3600;                                                          # default Abrufintervall SolCast API (s)
my $forapirepdef   = 900;                                                           # default Abrufintervall ForecastSolar API (s)
my $vrmapirepdef   = 300;                                                           # default Abrufintervall Victron VRM API Forecast
my $apimaxreqdef   = 50;                                                            # max. täglich mögliche Requests SolCast API
my $leadtime       = 3600;                                                          # relative Zeit vor Sonnenaufgang zur Freigabe API Abruf / Verbraucherplanung
my $lagtime        = 1800;                                                          # Nachlaufzeit relativ zu Sunset bis Sperrung API Abruf

my $prdef          = 0.85;                                                          # default Performance Ratio (PR)
my $tempcoeffdef   = -0.45;                                                         # default Temperaturkoeffizient Pmpp (%/°C) lt. Datenblatt Solarzelle
my $tempmodinc     = 25;                                                            # default Temperaturerhöhung an Solarzellen gegenüber Umgebungstemperatur bei wolkenlosem Himmel
my $tempbasedef    = 25;                                                            # Temperatur Module bei Nominalleistung

my $maxconsumer    = 16;                                                            # maximale Anzahl der möglichen Consumer (Attribut)
my $epiecMaxCycles = 10;                                                            # Anzahl Einschaltzyklen (Consumer) für verbraucherspezifische Energiestück Ermittlung
my @ctypes         = qw(dishwasher dryer washingmachine heater charger other
                        noSchedule);                                                # erlaubte Consumer Typen
my $defmintime     = 60;                                                            # default Einplanungsdauer in Minuten
my $defctype       = "other";                                                       # default Verbrauchertyp
my $defcmode       = "can";                                                         # default Planungsmode der Verbraucher
my $defpopercent   = 1.0;                                                           # Standard % aktuelle Leistung an nominaler Leistung gemäß Typenschild
my $defhyst        = 0;                                                             # default Hysterese

my $caicondef      = 'clock@gold';                                                  # default consumerAdviceIcon
my $flowGSizedef   = 400;                                                           # default flowGraphicSize
my $histhourdef    = 2;                                                             # default Anzeige vorangegangene Stunden
my $wthcolddef     = 'C7C979';                                                      # Wetter Icon Tag default Farbe
my $wthcolndef     = 'C7C7C7';                                                      # Wetter Icon Nacht default Farbe
my $b1coldef       = 'FFAC63';                                                      # default Farbe Beam 1
my $b1fontcoldef   = '0D0D0D';                                                      # default Schriftfarbe Beam 1
my $b2coldef       = 'C4C4A7';                                                      # default Farbe Beam 2
my $b2fontcoldef   = '000000';                                                      # default Schriftfarbe Beam 2
my $fgCDdef        = 130;                                                           # Abstand Verbrauchericons zueinander

my $bPath = 'https://svn.fhem.de/trac/browser/trunk/fhem/contrib/SolarForecast/';   # Basispfad Abruf contrib SolarForecast Files
my $pPath = '?format=txt';                                                          # Download Format
my $cfile = 'controls_solarforecast.txt';                                           # Name des Conrrolfiles

                                                                                    # default CSS-Style
my $cssdef = qq{.flowg.text           { stroke: none; fill: gray; font-size: 60px; }                                     \n}.
             qq{.flowg.sun_active     { stroke: orange; fill: orange; }                                                  \n}.
             qq{.flowg.sun_inactive   { stroke: gray; fill: gray; }                                                      \n}.
             qq{.flowg.bat25          { stroke: red; fill: red; }                                                        \n}.
             qq{.flowg.bat50          { stroke: darkorange; fill: darkorange; }                                          \n}.
             qq{.flowg.bat75          { stroke: green; fill: green; }                                                    \n}.
             qq{.flowg.grid_color1    { fill: green; }                                                                   \n}.
             qq{.flowg.grid_color2    { fill: red; }                                                                     \n}.
             qq{.flowg.grid_color3    { fill: gray; }                                                                    \n}.
             qq{.flowg.inactive_in    { stroke: gray;       stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; } \n}.
             qq{.flowg.inactive_out   { stroke: gray;       stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; } \n}.
             qq{.flowg.active_in      { stroke: red;        stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}.
             qq{.flowg.active_out     { stroke: darkorange; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}.
             qq{.flowg.active_bat_in  { stroke: darkorange; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}.
             qq{.flowg.active_bat_out { stroke: green;      stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}
             ;

                                                                                  # mögliche Debug-Module
my @dd    = qw( none
                aiProcess
                aiData
                apiCall
                apiProcess
                batteryManagement
                collectData
                consumerPlanning
                consumerSwitching
                consumption
                epiecesCalc
                graphic
                notifyHandling
                pvCorrection
                radiationProcess
                saveData2Cache
              );
                                                                                 # FTUI V2 Widget Files
  my @fs  = qw( ftui_forecast.css
                widget_forecast.js
                ftui_smaportalspg.css
                widget_smaportalspg.js
              );

my $allwidgets = 'icon|sortable|uzsu|knob|noArg|time|text|slider|multiple|select|bitfield|widgetList|colorpicker';

# Steuerhashes
###############

my %hset = (                                                                # Hash der Set-Funktion
  consumerImmediatePlanning => { fn => \&_setconsumerImmediatePlanning },
  consumerNewPlanning       => { fn => \&_setconsumerNewPlanning       },
  currentWeatherDev         => { fn => \&_setcurrentWeatherDev         },
  currentRadiationAPI       => { fn => \&_setcurrentRadiationAPI       },
  modulePeakString          => { fn => \&_setmodulePeakString          },
  inverterStrings           => { fn => \&_setinverterStrings           },
  clientAction              => { fn => \&_setclientAction              },
  currentInverterDev        => { fn => \&_setinverterDevice            },
  currentMeterDev           => { fn => \&_setmeterDevice               },
  currentBatteryDev         => { fn => \&_setbatteryDevice             },
  energyH4Trigger           => { fn => \&_setTrigger                   },
  plantConfiguration        => { fn => \&_setplantConfiguration        },
  batteryTrigger            => { fn => \&_setTrigger                   },
  operationMode             => { fn => \&_setoperationMode             },
  powerTrigger              => { fn => \&_setTrigger                   },
  pvCorrectionFactor_05     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_06     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_07     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_08     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_09     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_10     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_11     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_12     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_13     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_14     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_15     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_16     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_17     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_18     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_19     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_20     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_21     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_Auto   => { fn => \&_setpvCorrectionFactorAuto    },
  reset                     => { fn => \&_setreset                     },
  roofIdentPair             => { fn => \&_setroofIdentPair             },
  moduleRoofTops            => { fn => \&_setmoduleRoofTops            },
  moduleTiltAngle           => { fn => \&_setmoduleTiltAngle           },
  moduleDirection           => { fn => \&_setmoduleDirection           },
  operatingMemory           => { fn => \&_setoperatingMemory           },
  vrmCredentials            => { fn => \&_setVictronCredentials        },
  aiDecTree                 => { fn => \&_setaiDecTree                 },
);

my %hget = (                                                                # Hash für Get-Funktion (needcred => 1: Funktion benötigt gesetzte Credentials)
  data               => { fn => \&_getdata,                     needcred => 0 },
  html               => { fn => \&_gethtml,                     needcred => 0 },
  ftui               => { fn => \&_getftui,                     needcred => 0 },
  valCurrent         => { fn => \&_getlistCurrent,              needcred => 0 },
  valConsumerMaster  => { fn => \&_getlistvalConsumerMaster,    needcred => 0 },
  plantConfigCheck   => { fn => \&_setplantConfiguration,       needcred => 0 },
  pvHistory          => { fn => \&_getlistPVHistory,            needcred => 0 },
  pvCircular         => { fn => \&_getlistPVCircular,           needcred => 0 },
  forecastQualities  => { fn => \&_getForecastQualities,        needcred => 0 },
  nextHours          => { fn => \&_getlistNextHours,            needcred => 0 },
  rooftopData        => { fn => \&_getRoofTopData,              needcred => 0 },
  solApiData         => { fn => \&_getlistSolCastData,          needcred => 0 },
  valDecTree         => { fn => \&_getaiDecTree,                needcred => 0 },
  ftuiFramefiles     => { fn => \&_ftuiFramefiles,              needcred => 0 },
);

my %hattr = (                                                                # Hash für Attr-Funktion
  consumer                  => { fn => \&_attrconsumer            },
  ctrlConsRecommendReadings => { fn => \&_attrcreateConsRecRdgs   },
  ctrlStatisticReadings     => { fn => \&_attrcreateStatisticRdgs },
);

my %htr = (                                                                  # Hash even/odd für <tr>
  0 => { cl => 'even' },
  1 => { cl => 'odd' },
);

my %hff = (                                                                                           # Flächenfaktoren
  "0"  => { N => 100, NE => 100, E => 100, SE => 100, S => 100, SW => 100, W => 100, NW => 100 },     # http://www.ing-büro-junge.de/html/photovoltaik.html
  "5"  => { N => 95,  NE => 96,  E => 100, SE => 103, S => 105, SW => 103, W => 100, NW => 96  },
  "10" => { N => 90,  NE => 93,  E => 100, SE => 105, S => 107, SW => 105, W => 100, NW => 93  },
  "15" => { N => 85,  NE => 90,  E => 99,  SE => 107, S => 111, SW => 107, W => 99,  NW => 90  },
  "20" => { N => 80,  NE => 84,  E => 97,  SE => 108, S => 114, SW => 108, W => 97,  NW => 84  },
  "25" => { N => 75,  NE => 80,  E => 95,  SE => 109, S => 115, SW => 109, W => 95,  NW => 80  },
  "30" => { N => 69,  NE => 76,  E => 94,  SE => 110, S => 117, SW => 110, W => 94,  NW => 76  },
  "35" => { N => 65,  NE => 71,  E => 92,  SE => 110, S => 118, SW => 110, W => 92,  NW => 71  },
  "40" => { N => 59,  NE => 68,  E => 90,  SE => 109, S => 117, SW => 109, W => 90,  NW => 68  },
  "45" => { N => 55,  NE => 65,  E => 87,  SE => 108, S => 115, SW => 108, W => 87,  NW => 65  },
  "50" => { N => 49,  NE => 62,  E => 85,  SE => 107, S => 113, SW => 107, W => 85,  NW => 62  },
  "55" => { N => 45,  NE => 58,  E => 83,  SE => 105, S => 112, SW => 105, W => 83,  NW => 58  },
  "60" => { N => 42,  NE => 55,  E => 80,  SE => 102, S => 111, SW => 102, W => 80,  NW => 55  },
  "65" => { N => 39,  NE => 53,  E => 77,  SE => 99,  S => 108, SW => 99,  W => 77,  NW => 53  },
  "70" => { N => 37,  NE => 50,  E => 74,  SE => 95,  S => 104, SW => 95,  W => 74,  NW => 50  },
  "75" => { N => 36,  NE => 48,  E => 70,  SE => 90,  S => 100, SW => 90,  W => 70,  NW => 48  },
  "80" => { N => 35,  NE => 46,  E => 67,  SE => 86,  S => 95,  SW => 86,  W => 67,  NW => 46  },
  "85" => { N => 34,  NE => 44,  E => 64,  SE => 82,  S => 90,  SW => 82,  W => 64,  NW => 44  },
  "90" => { N => 33,  NE => 43,  E => 62,  SE => 78,  S => 85,  SW => 78,  W => 62,  NW => 43  },
);

my %hqtxt = (                                                                                                 # Hash (Setup) Texte
  entry  => { EN => qq{<b>Warm welcome!</b><br>
                       The next queries will guide you through the basic installation.<br>
                       If all entries are made, please check the configuration finally with
                       "set LINK plantConfiguration check" or by pressing the offered icon.<br>
                       Please correct any errors and take note of possible hints.<br>
                       (The display language can be changed with attribute "ctrlLanguage".)<hr><br> },
              DE => qq{<b>Herzlich Willkommen!</b><br>
                       Die n&auml;chsten Abfragen f&uuml;hren sie durch die Grundinstallation.<br>
                       Sind alle Eingaben vorgenommen, pr&uuml;fen sie bitte die Konfiguration abschlie&szlig;end mit
                       "set LINK plantConfiguration check" oder mit Druck auf das angebotene Icon.<br>
                       Korrigieren sie bitte eventuelle Fehler und beachten sie m&ouml;gliche Hinweise.<br>
                       (Die Anzeigesprache kann mit dem Attribut "ctrlLanguage" umgestellt werden.)<hr><br>}                },
  cfd    => { EN => qq{Please select the Weather forecast device with "set LINK currentWeatherDev"},
              DE => qq{Bitte geben sie das Wettervorhersage Device mit "set LINK currentWeatherDev" an}                     },
  crd    => { EN => qq{Please select the radiation forecast service with "set LINK currentRadiationAPI"},
              DE => qq{Bitte geben sie den Strahlungsvorhersage Dienst mit "set LINK currentRadiationAPI" an}               },
  cid    => { EN => qq{Please specify the Inverter device with "set LINK currentInverterDev"},
              DE => qq{Bitte geben sie das Wechselrichter Device mit "set LINK currentInverterDev" an}                      },
  mid    => { EN => qq{Please specify the device for energy measurement with "set LINK currentMeterDev"},
              DE => qq{Bitte geben sie das Device zur Energiemessung mit "set LINK currentMeterDev" an}                     },
  ist    => { EN => qq{Please define all of your used string names with "set LINK inverterStrings"},
              DE => qq{Bitte geben sie alle von Ihnen verwendeten Stringnamen mit "set LINK inverterStrings" an}            },
  mps    => { EN => qq{Please enter the DC peak power of each string with "set LINK modulePeakString"},
              DE => qq{Bitte geben sie die DC Spitzenleistung von jedem String mit "set LINK modulePeakString" an}          },
  mdr    => { EN => qq{Please specify the module direction with "set LINK moduleDirection"},
              DE => qq{Bitte geben sie die Modulausrichtung mit "set LINK moduleDirection" an}                              },
  mta    => { EN => qq{Please specify the module tilt angle with "set LINK moduleTiltAngle"},
              DE => qq{Bitte geben sie den Modulneigungswinkel mit "set LINK moduleTiltAngle" an}                           },
  rip    => { EN => qq{Please specify at least one combination Rooftop-ID/SolCast-API with "set LINK roofIdentPair"},
              DE => qq{Bitte geben Sie mindestens eine Kombination Rooftop-ID/SolCast-API mit "set LINK roofIdentPair" an}  },
  mrt    => { EN => qq{Please set the assignment String / Rooftop identification with "set LINK moduleRoofTops"},
              DE => qq{Bitte setzen sie die Zuordnung String / Rooftop Identifikation mit "set LINK moduleRoofTops"}        },
  coord  => { EN => qq{Please set attributes 'latitude' and 'longitude' in global device},
              DE => qq{Bitte setzen sie die Attribute 'latitude' und 'longitude' im global Device}                          },
  cnsm   => { EN => qq{Consumer},
              DE => qq{Verbraucher}                                                                                         },
  eiau   => { EN => qq{Off/On},
              DE => qq{Aus/Ein}                                                                                             },
  auto   => { EN => qq{Auto},
              DE => qq{Auto}                                                                                                },
  lupt   => { EN => qq{last&nbsp;update:},
              DE => qq{Stand:}                                                                                              },
  object => { EN => qq{Object},
              DE => qq{Pr&uuml;fobjekt}                                                                                     },
  state  => { EN => qq{Status},
              DE => qq{Status}                                                                                              },
  result => { EN => qq{Result},
              DE => qq{Ergebnis}                                                                                            },
  note   => { EN => qq{Note},
              DE => qq{Hinweis}                                                                                             },
  wfmdcf => { EN => qq{Wait for more days with a consumption figure},
              DE => qq{Warte auf weitere Tage mit einer Verbrauchszahl}                                                     },
  autoct => { EN => qq{Autocorrection:},
              DE => qq{Autokorrektur:}                                                                                      },
  plntck => { EN => qq{Plant Configurationcheck Information},
              DE => qq{Informationen zur Anlagenkonfigurationspr&uuml;fung}                                                 },
  lbpcq  => { EN => qq{Quality:},
              DE => qq{Qualit&auml;t:}                                                                                      },
  lblPvh => { EN => qq{next&nbsp;4h:},
              DE => qq{n&auml;chste&nbsp;4h:}                                                                               },
  lblPRe => { EN => qq{rest&nbsp;today:},
              DE => qq{Rest&nbsp;heute:}                                                                                    },
  lblPTo => { EN => qq{tomorrow:},
              DE => qq{morgen:}                                                                                             },
  lblPCu => { EN => qq{currently:},
              DE => qq{aktuell:}                                                                                            },
  bnsas  => { EN => qq{from <WT> minutes before the upcoming sunrise},
              DE => qq{ab <WT> Minuten vor dem kommenden Sonnenaufgang}                                                     },
  dvtn   => { EN => qq{Deviation},
              DE => qq{Abweichung}                                                                                          },
  pvgen  => { EN => qq{Generation},
              DE => qq{Erzeugung}                                                                                           },
  conspt => { EN => qq{Consumption},
              DE => qq{Verbrauch}                                                                                           },
  tday   => { EN => qq{today},
              DE => qq{heute}                                                                                               },
  ctnsly => { EN => qq{continuously},
              DE => qq{fortlaufend}                                                                                         },
  yday   => { EN => qq{yesterday},
              DE => qq{gestern}                                                                                             },
  after  => { EN => qq{after},
              DE => qq{nach}                                                                                                },
  aihtxt => { EN => qq{AI state:},
              DE => qq{KI Status:}                                                                                          },
  aimmts => { EN => qq{Perl module Test2::Suite is missing},
              DE => qq{Perl Modul Test2::Suite ist nicht vorhanden}                                                         },
  aiwook => { EN => qq{AI support works properly, but does not provide a value for the current hour},
              DE => qq{KI Unterst&uuml;tzung arbeitet einwandfrei, liefert jedoch keinen Wert f&uuml;r die aktuelle Stunde} },
  aiwhit => { EN => qq{the PV forecast value for the current hour is provided by the AI support},
              DE => qq{der PV Vorhersagewert f&uuml;r die aktuelle Stunde wird von der KI Unterst&uuml;tzung geliefert}     },
  nxtscc => { EN => qq{next SolCast call},
              DE => qq{n&auml;chste SolCast Abfrage}                                                                        },
  fulfd  => { EN => qq{fulfilled},
              DE => qq{erf&uuml;llt}                                                                                        },
  widnin => { EN => qq{FHEM Tablet UI V2 is not installed.},
              DE => qq{FHEM Tablet UI V2 ist nicht installiert.}                                                            },
  widok  => { EN => qq{The FHEM Tablet UI widget Files are up to date.},
              DE => qq{Die FHEM Tablet UI Widget-Dateien sind aktuell.}                                                     },
  widnup => { EN => qq{The SolarForecast FHEM Tablet UI widget files are not up to date.},
              DE => qq{Die FHEM Tablet UI Widget-Dateien sind nicht aktuell.}                                               },
  widerr => { EN => qq{The FHEM Tablet UI V2 is installed but the update status of widget Files can't be checked.},
              DE => qq{FTUI V2 ist installiert, der Aktualisierungsstatus der Widgets kann nicht gepr&uuml;ft werden.}      },
  pmtp   => { EN => qq{produced more than predicted :-D},
              DE => qq{mehr produziert als vorhergesagt :-D}                                                                },
  petp   => { EN => qq{produced same as predicted :-)},
              DE => qq{produziert wie vorhergesagt :-)}                                                                     },
  pltp   => { EN => qq{produced less than predicted :-(},
              DE => qq{weniger produziert als vorhergesagt :-(}                                                             },
  wusond => { EN => qq{wait until sunset},
              DE => qq{bis zum Sonnenuntergang warten}                                                                      },
  snbefb => { EN => qq{Should not be empty. Maybe the device has just been redefined.},
              DE => qq{Sollte nicht leer sein. Vielleicht wurde das Device erst neu definiert.}                             },
  scnp   => { EN => qq{Scheduling of the consumer is not provided},
              DE => qq{Die Einplanung des Verbrauchers ist nicht vorgesehen}                                                },
  vrmcr  => { EN => qq{Please set the Victron VRM Portal credentials with "set LINK vrmCredentials".},
              DE => qq{Bitte setzen sie die Victron VRM Portal Zugangsdaten mit "set LINK vrmCredentials". }                },
  awd    => { EN => qq{LINK is waiting for solar forecast data ... <br>},
              DE => qq{LINK wartet auf Solarvorhersagedaten ... <br>}                                                       },
  wexso  => { EN => qq{switched externally},
              DE => qq{von extern umgeschaltet}                                                                             },
  strok  => { EN => qq{Congratulations &#128522;, the system configuration is error-free. Please note any information (<I>).},
              DE => qq{Herzlichen Glückwunsch &#128522;, die Anlagenkonfiguration ist fehlerfrei. Bitte eventuelle Hinweise (<I>) beachten.}                   },
  strwn  => { EN => qq{Looks quite good &#128528;, the system configuration is basically OK. Please note the warnings (<W>).},
              DE => qq{Sieht ganz gut aus &#128528;, die Anlagenkonfiguration ist prinzipiell in Ordnung. Bitte beachten Sie die Warnungen (<W>).}             },
  strnok => { EN => qq{Oh no &#128577;, the system configuration is incorrect. Please check the settings and notes!},
              DE => qq{Oh nein &#128546;, die Anlagenkonfiguration ist fehlerhaft. Bitte überprüfen Sie die Einstellungen und Hinweise!}                       },
  pstate => { EN => qq{Planning&nbsp;status:&nbsp;<pstate><br>Info:&nbsp;<supplmnt><br>On:&nbsp;<start><br>Off:&nbsp;<stop><br>Remaining lock time:&nbsp;<RLT> seconds},
              DE => qq{Planungsstatus:&nbsp;<pstate><br>Info:&nbsp;<supplmnt><br>Ein:&nbsp;<start><br>Aus:&nbsp;<stop><br>verbleibende Sperrzeit:&nbsp;<RLT> Sekunden}    },
);

my %htitles = (                                                                                                 # Hash Hilfetexte (Mouse Over)
  iaaf     => { EN => qq{Automatic mode off -> Enable automatic mode},
                DE => qq{Automatikmodus aus -> Automatik freigeben}                                                },
  ieas     => { EN => qq{Automatic mode on -> Lock automatic mode},
                DE => qq{Automatikmodus ein -> Automatik sperren}                                                  },
  iave     => { EN => qq{Off -> Switch on consumer},
                DE => qq{Aus -> Verbraucher einschalten}                                                           },
  ians     => { EN => qq{Off -> no on-command defined!},
                DE => qq{Aus -> kein on-Kommando definiert!}                                                       },
  ieva     => { EN => qq{On -> Switch off consumer},
                DE => qq{Ein -> Verbraucher ausschalten}                                                           },
  iens     => { EN => qq{On -> no off-command defined!},
                DE => qq{Ein -> kein off-Kommando definiert!}                                                      },
  natc     => { EN => qq{automatic cycle:},
                DE => qq{automatischer Zyklus:}                                                                    },
  upd      => { EN => qq{Click for update},
                DE => qq{Klick f&#252;r Update}                                                                    },
  on       => { EN => qq{switched on},
                DE => qq{eingeschaltet}                                                                            },
  off      => { EN => qq{switched off},
                DE => qq{ausgeschaltet}                                                                            },
  undef    => { EN => qq{undefined},
                DE => qq{undefiniert}                                                                              },
  dela     => { EN => qq{delayed},
                DE => qq{verzoegert}                                                                               },
  conrec   => { EN => qq{Current time is within the consumption planning},
                DE => qq{Aktuelle Zeit liegt innerhalb der Verbrauchsplanung}                                      },
  conrecba => { EN => qq{Current time is within the consumption planning, Priority charging Battery is active},
                DE => qq{Aktuelle Zeit liegt innerhalb der Verbrauchsplanung, Vorrangladen Batterie ist aktiv}     },
  connorec => { EN => qq{Consumption planning is outside current time\n(Click for immediate planning)},
                DE => qq{Verbrauchsplanung liegt ausserhalb aktueller Zeit\n(Klick f&#252;r sofortige Einplanung)} },
  akorron  => { EN => qq{switched off\nenable auto correction with:\nset <NAME> pvCorrectionFactor_Auto on*},
                DE => qq{ausgeschaltet\nAutokorrektur einschalten mit:\nset <NAME> pvCorrectionFactor_Auto on*}                   },
  splus    => { EN => qq{PV surplus sufficient},
                DE => qq{PV-&#220;berschu&#223; ausreichend}                                                       },
  nosplus  => { EN => qq{PV surplus insufficient},
                DE => qq{PV-&#220;berschu&#223; unzureichend}                                                      },
  plchk    => { EN => qq{Configuration check of the plant},
                DE => qq{Konfigurationspr&#252;fung der Anlage}                                                    },
  scaresps => { EN => qq{API request successful},
                DE => qq{API Abfrage erfolgreich}                                                                  },
  scarespf => { EN => qq{API request failed},
                DE => qq{API Abfrage fehlgeschlagen}                                                               },
  dapic    => { EN => qq{done API requests},
                DE => qq{bisherige API-Anfragen}                                                                   },
  rapic    => { EN => qq{remaining API requests},
                DE => qq{verf&#252;gbare API-Anfragen}                                                             },
  yheyfdl  => { EN => qq{You have exceeded your free daily limit!},
                DE => qq{Sie haben Ihr kostenloses Tageslimit &#252;berschritten!}                                 },
  rlfaccpr => { EN => qq{Rate limit for API requests reached in current period!},
                DE => qq{Abfragegrenze f&#252;r API-Anfragen im aktuellen Zeitraums erreicht!}                     },
  raricp   => { EN => qq{remaining API requests in the current period},
                DE => qq{verf&#252;gbare API-Anfragen der laufenden Periode}                                       },
  scakdne  => { EN => qq{API key does not exist},
                DE => qq{API Schl&#252;ssel existiert nicht}                                                       },
  scrsdne  => { EN => qq{Rooftop site does not exist or is not accessible},
                DE => qq{Rooftop ID existiert nicht oder ist nicht abrufbar}                                       },
  norate   => { EN => qq{not rated},
                DE => qq{nicht bewertet}                                                                           },
  aimstt   => { EN => qq{Perl module AI::DecisionTree is missing},
                DE => qq{Perl Modul AI::DecisionTree ist nicht vorhanden}                                          },
  pstate   => { EN => qq{Planning&nbsp;status:&nbsp;<pstate>\nInfo:&nbsp;<supplmnt>\n\nOn:&nbsp;<start>\nOff:&nbsp;<stop>\nRemaining lock time:&nbsp;<RLT> seconds},
                DE => qq{Planungsstatus:&nbsp;<pstate>\nInfo:&nbsp;<supplmnt>\n\nEin:&nbsp;<start>\nAus:&nbsp;<stop>\nverbleibende Sperrzeit:&nbsp;<RLT> Sekunden}                      },
  ainuse   => { EN => qq{AI Perl module is installed, but the AI support is not used.\nRun 'set <NAME> plantConfiguration check' for hints.},
                DE => qq{KI Perl Modul ist installiert, aber die KI Unterst&uuml;tzung wird nicht verwendet.\nPr&uuml;fen sie 'set <NAME> plantConfiguration check' f&uuml;r Hinweise.} },
);

my %weather_ids = (
  # s =>  0 , 0 - 3   DWD -> kein signifikantes Wetter
  # s =>  1 , 45 - 99 DWD -> signifikantes Wetter
  '0'   => { s => '0', icon => 'weather_sun',              txtd => 'sonnig',                                                                   txte => 'sunny'                                                                      },
  '1'   => { s => '0', icon => 'weather_cloudy_light',     txtd => 'Bewölkung abnehmend',                                                      txte => 'Cloudiness decreasing'                                                      },
  '2'   => { s => '0', icon => 'weather_cloudy',           txtd => 'Bewölkung unverändert',                                                    txte => 'Cloudiness unchanged'                                                       },
  '3'   => { s => '0', icon => 'weather_cloudy_heavy',     txtd => 'Bewölkung zunehmend',                                                      txte => 'Cloudiness increasing'                                                      },
  '4'   => { s => '0', icon => 'unknown',                  txtd => 'Sicht durch Rauch oder Asche vermindert',                                  txte => 'Visibility reduced by smoke or ash'                                         },
  '5'   => { s => '0', icon => 'unknown',                  txtd => 'trockener Dunst (relative Feuchte < 80 %)',                                txte => 'dry haze (relative humidity < 80 %)'                                        },
  '6'   => { s => '0', icon => 'unknown',                  txtd => 'verbreiteter Schwebstaub, nicht vom Wind herangeführt',                    txte => 'widespread airborne dust, not brought in by the wind'                       },
  '7'   => { s => '0', icon => 'unknown',                  txtd => 'Staub oder Sand bzw. Gischt, vom Wind herangeführt',                       txte => 'Dust or sand or spray, brought in by the wind'                              },
  '8'   => { s => '0', icon => 'unknown',                  txtd => 'gut entwickelte Staub- oder Sandwirbel',                                   txte => 'well-developed dust or sand vortex'                                         },
  '9'   => { s => '0', icon => 'unknown',                  txtd => 'Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station',        txte => 'Dust or sand storm in the visual circle, but not at the station'            },

  '10'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel',                                                                    txte => 'Fog'                                                                        },
  '11'  => { s => '0', icon => 'weather_rain_fog',         txtd => 'Nebel mit Regen',                                                          txte => 'Fog with rain'                                                              },
  '12'  => { s => '0', icon => 'weather_fog',              txtd => 'durchgehender Bodennebel',                                                 txte => 'continuous ground fog'                                                      },
  '13'  => { s => '0', icon => 'unknown',                  txtd => 'Wetterleuchten sichtbar, kein Donner gehört',                              txte => 'Weather light visible, no thunder heard'                                    },
  '14'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag im Gesichtskreis, nicht den Boden erreichend',                txte => 'Precipitation in the visual circle, not reaching the ground'                },
  '15'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Ferne (> 5 km), aber nicht an der Station',            txte => 'Precipitation in the distance (> 5 km), but not at the station'             },
  '16'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Nähe (< 5 km), aber nicht an der Station',             txte => 'Precipitation in the vicinity (< 5 km), but not at the station'             },
  '17'  => { s => '0', icon => 'unknown',                  txtd => 'Gewitter (Donner hörbar), aber kein Niederschlag an der Station',          txte => 'Thunderstorm (thunder audible), but no precipitation at the station'        },
  '18'  => { s => '0', icon => 'unknown',                  txtd => 'Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station',    txte => 'marked gusts in the visual circle, but no precipitation at the station'     },
  '19'  => { s => '0', icon => 'unknown',                  txtd => 'Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis',               txte => 'Trombles (funnel-shaped cloud tubes) in the circle of vision'               },

  '20'  => { s => '0', icon => 'unknown',                  txtd => 'nach Sprühregen oder Schneegriesel',                                       txte => 'after drizzle or snow drizzle'                                              },
  '21'  => { s => '0', icon => 'unknown',                  txtd => 'nach Regen',                                                               txte => 'after rain'                                                                 },
  '22'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schnefall',                                                           txte => 'after snowfall'                                                             },
  '23'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeregen oder Eiskörnern',                                         txte => 'after sleet or ice grains'                                                  },
  '24'  => { s => '0', icon => 'unknown',                  txtd => 'nach gefrierendem Regen',                                                  txte => 'after freezing rain'                                                        },
  '25'  => { s => '0', icon => 'unknown',                  txtd => 'nach Regenschauer',                                                        txte => 'after rain shower'                                                          },
  '26'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeschauer',                                                       txte => 'after snow shower'                                                          },
  '27'  => { s => '0', icon => 'unknown',                  txtd => 'nach Graupel- oder Hagelschauer',                                          txte => 'after sleet or hail showers'                                                },
  '28'  => { s => '0', icon => 'unknown',                  txtd => 'nach Nebel',                                                               txte => 'after fog'                                                                  },
  '29'  => { s => '0', icon => 'unknown',                  txtd => 'nach Gewitter',                                                            txte => 'after thunderstorm'                                                         },

  '30'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität abnehmend',                 txte => 'light or moderate sandstorm, decreasing in intensity'                       },
  '31'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, unveränderte Intensität',                 txte => 'light or moderate sandstorm, unchanged intensity'                           },
  '32'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität zunehmend',                 txte => 'light or moderate sandstorm, increasing in intensity'                       },
  '33'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität abnehmend',                              txte => 'heavy sandstorm, decreasing in intensity'                                   },
  '34'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, unveränderte Intensität',                              txte => 'heavy sandstorm, unchanged intensity'                                       },
  '35'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität zunehmend',                              txte => 'heavy sandstorm, increasing in intensity'                                   },
  '36'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneefegen, unter Augenhöhe',                       txte => 'light or moderate snow sweeping, below eye level'                           },
  '37'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneefegen, unter Augenhöhe',                                     txte => 'heavy snow sweeping, below eye level'                                       },
  '38'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneetreiben, über Augenhöhe',                      txte => 'light or moderate blowing snow, above eye level'                            },
  '39'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneetreiben, über Augenhöhe',                                    txte => 'heavy snow drifting, above eye level'                                       },

  '40'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in einiger Entfernung',                                              txte => 'Fog in some distance'                                                       },
  '41'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in Schwaden oder Bänken',                                            txte => 'Fog in swaths or banks'                                                     },
  '42'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dünner werdend',                                  txte => 'Fog, sky recognizable, thinning'                                            },
  '43'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dünner werdend',                            txte => 'Fog, sky not recognizable, thinning'                                        },
  '44'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, unverändert',                                     txte => 'Fog, sky recognizable, unchanged'                                           },
  '45'  => { s => '1', icon => 'weather_fog',              txtd => 'Nebel',                                                                    txte => 'Fog'                                                                        },
  '46'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dichter werdend',                                 txte => 'Fog, sky recognizable, becoming denser'                                     },
  '47'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dichter werdend',                           txte => 'Fog, sky not visible, becoming denser'                                      },
  '48'  => { s => '1', icon => 'weather_fog',              txtd => 'Nebel mit Reifbildung',                                                    txte => 'Fog with frost formation'                                                   },
  '49'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel mit Reifansatz, Himmel nicht erkennbar',                             txte => 'Fog with frost, sky not visible'                                            },

  '50'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener leichter Sprühregen',                                       txte => 'intermittent light drizzle'                                                 },
  '51'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen',                                                      txte => 'light drizzle'                                                              },
  '52'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Sprühregen',                                        txte => 'intermittent moderate drizzle'                                              },
  '53'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen',                                                      txte => 'light drizzle'                                                              },
  '54'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Sprühregen',                                        txte => 'intermittent heavy drizzle'                                                 },
  '55'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Sprühregen',                                                       txte => 'heavy drizzle'                                                              },
  '56'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter gefrierender Sprühregen',                                         txte => 'light freezing drizzle'                                                     },
  '57'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker gefrierender Sprühregen',                             txte => 'moderate or heavy freezing drizzle'                                         },
  '58'  => { s => '0', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen mit Regen',                                            txte => 'light drizzle with rain'                                                    },
  '59'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker Sprühregen mit Regen',                                txte => 'moderate or heavy drizzle with rain'                                        },

  '60'  => { s => '0', icon => 'weather_rain_light',       txtd => 'unterbrochener leichter Regen oder einzelne Regentropfen',                 txte => 'intermittent light rain or single raindrops'                                },
  '61'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regen',                                                           txte => 'light rain'                                                                 },
  '62'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Regen',                                             txte => 'intermittent moderate rain'                                                 },
  '63'  => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger Regen',                                                            txte => 'moderate rain'                                                              },
  '64'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Regen',                                             txte => 'intermittent heavy rain'                                                    },
  '65'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Regen',                                                            txte => 'heavy rain'                                                                 },
  '66'  => { s => '1', icon => 'weather_rain_snow_light',  txtd => 'leichter gefrierender Regen',                                              txte => 'light freezing rain'                                                        },
  '67'  => { s => '1', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker gefrierender Regen',                                  txte => 'moderate or heavy freezing rain'                                            },
  '68'  => { s => '0', icon => 'weather_rain_snow_light',  txtd => 'leichter Schneeregen',                                                     txte => 'light sleet'                                                                },
  '69'  => { s => '0', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker Schneeregen',                                         txte => 'moderate or heavy sleet'                                                    },

  '70'  => { s => '0', icon => 'weather_snow_light',       txtd => 'unterbrochener leichter Schneefall oder einzelne Schneeflocken',           txte => 'intermittent light snowfall or single snowflakes'                           },
  '71'  => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneefall',                                                      txte => 'light snowfall'                                                             },
  '72'  => { s => '0', icon => 'weather_snow',             txtd => 'unterbrochener mäßiger Schneefall',                                        txte => 'intermittent moderate snowfall'                                             },
  '73'  => { s => '1', icon => 'weather_snow',             txtd => 'mäßiger Schneefall',                                                       txte => 'moderate snowfall'                                                          },
  '74'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'unterbrochener starker Schneefall',                                        txte => 'intermittent heavy snowfall'                                                },
  '75'  => { s => '1', icon => 'weather_snow_heavy',       txtd => 'starker Schneefall',                                                       txte => 'heavy snowfall'                                                             },
  '76'  => { s => '0', icon => 'weather_frost',            txtd => 'Eisnadeln (Polarschnee)',                                                  txte => 'Ice needles (polar snow)'                                                   },
  '77'  => { s => '1', icon => 'weather_frost',            txtd => 'Schneegriesel',                                                            txte => 'Snow drizzle'                                                               },
  '78'  => { s => '0', icon => 'weather_frost',            txtd => 'Schneekristalle',                                                          txte => 'Snow crystals'                                                              },
  '79'  => { s => '0', icon => 'weather_frost',            txtd => 'Eiskörner (gefrorene Regentropfen)',                                       txte => 'Ice grains (frozen raindrops)'                                              },

  '80'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regenschauer',                                                    txte => 'light rain shower'                                                          },
  '81'  => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger oder starker Regenschauer',                                        txte => 'moderate or heavy rain shower'                                              },
  '82'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'sehr starker Regenschauer',                                                txte => 'very heavy rain shower'                                                     },
  '83'  => { s => '0', icon => 'weather_snow',             txtd => 'mäßiger oder starker Schneeregenschauer',                                  txte => 'moderate or heavy sleet shower'                                             },
  '84'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer',                                                   txte => 'light snow shower'                                                          },
  '85'  => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer',                                                   txte => 'light snow shower'                                                          },
  '86'  => { s => '1', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Schneeschauer',                                       txte => 'moderate or heavy snow shower'                                              },
  '87'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Graupelschauer',                                      txte => 'moderate or heavy sleet shower'                                             },
  '88'  => { s => '0', icon => 'unknown',                  txtd => 'leichter Hagelschauer',                                                    txte => 'light hailstorm'                                                            },
  '89'  => { s => '0', icon => 'unknown',                  txtd => 'mäßiger oder starker Hagelschauer',                                        txte => 'moderate or heavy hailstorm'                                                },

  '90'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '91'  => { s => '0', icon => 'weather_storm',            txtd => '',                                                                         txte => ''                                                                           },
  '92'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '93'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '94'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '95'  => { s => '1', icon => 'weather_thunderstorm',     txtd => 'leichtes oder mäßiges Gewitter ohne Graupel oder Hagel',                   txte => 'light or moderate thunderstorm without sleet or hail'                       },
  '96'  => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter ohne Graupel oder Hagel,Gewitter mit Graupel oder Hagel', txte => 'strong thunderstorm without sleet or hail,thunderstorm with sleet or hail'  },
  '97'  => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Regen oder Schnee',                                   txte => 'heavy thunderstorm with rain or snow'                                       },
  '98'  => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Sandsturm',                                           txte => 'strong thunderstorm with sandstorm'                                         },
  '99'  => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Graupel oder Hagel',                                  txte => 'strong thunderstorm with sleet or hail'                                     },
  '100' => { s => '0', icon => 'weather_night',            txtd => 'sternenklarer Himmel',                                                     txte => 'starry sky'                                                                 },
);

my %hef = (                                                                      # Energiedaktoren für Verbrauchertypen
  "heater"         => { f => 1.00, m => 1.00, l => 1.00, mt => 240         },
  "other"          => { f => 1.00, m => 1.00, l => 1.00, mt => $defmintime },    # f   = Faktor Energieverbrauch in erster Stunde (wichtig auch für Kalkulation in __calcEnergyPieces !)
  "charger"        => { f => 1.00, m => 1.00, l => 1.00, mt => 120         },    # m   = Faktor Energieverbrauch zwischen erster und letzter Stunde
  "dishwasher"     => { f => 0.45, m => 0.10, l => 0.45, mt => 180         },    # l   = Faktor Energieverbrauch in letzter Stunde
  "dryer"          => { f => 0.40, m => 0.40, l => 0.20, mt => 90          },    # mt  = default mintime (Minuten)
  "washingmachine" => { f => 0.50, m => 0.30, l => 0.40, mt => 120         },
  "noSchedule"     => { f => 1.00, m => 1.00, l => 1.00, mt => $defmintime },
);

my %hcsr = (                                                                                                                               # Funktiontemplate zur Erstellung optionaler Statistikreadings
  currentAPIinterval          => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => 0           },      # par = Parameter zur spezifischen Verwendung
  lastretrieval_time          => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => '-'         },
  lastretrieval_timestamp     => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => '-'         },
  response_message            => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => '-'         },
  todayMaxAPIcalls            => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => 'apimaxreq' },
  todayDoneAPIcalls           => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => 0           },
  todayDoneAPIrequests        => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => 0           },
  todayRemainingAPIcalls      => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => 'apimaxreq' },
  todayRemainingAPIrequests   => { fnr => 1, fn => \&SolCastAPIVal, par => '',                  unit => '',     def => 'apimaxreq' },
  runTimeCentralTask          => { fnr => 2, fn => \&CurrentVal,    par => '',                  unit => '',     def => '-'         },
  runTimeLastAPIAnswer        => { fnr => 2, fn => \&CurrentVal,    par => '',                  unit => '',     def => '-'         },
  runTimeLastAPIProc          => { fnr => 2, fn => \&CurrentVal,    par => '',                  unit => '',     def => '-'         },
  allStringsFullfilled        => { fnr => 2, fn => \&CurrentVal,    par => '',                  unit => '',     def => 0           },
  todayConForecastTillSunset  => { fnr => 2, fn => \&CurrentVal,    par => 'tdConFcTillSunset', unit => ' Wh',  def => 0           },
  runTimeTrainAI              => { fnr => 3, fn => \&CircularVal,   par => 99,                  unit => '',     def => '-'         },
  SunHours_Remain             => { fnr => 4, fn => \&CurrentVal,    par => '',                  unit => '',     def => 0           },      # fnr => 3 -> Custom Calc
  SunMinutes_Remain           => { fnr => 4, fn => \&CurrentVal,    par => '',                  unit => '',     def => 0           },
  dayAfterTomorrowPVforecast  => { fnr => 4, fn => \&SolCastAPIVal, par => 'pv_estimate50',     unit => '',     def => 0           },
  todayGridFeedIn             => { fnr => 4, fn => \&CircularVal,   par => 99,                  unit => '',     def => 0           },
  todayGridConsumption        => { fnr => 4, fn => \&CircularVal,   par => 99,                  unit => '',     def => 0           },
  todayBatIn                  => { fnr => 4, fn => \&CircularVal,   par => 99,                  unit => '',     def => 0           },
  todayBatOut                 => { fnr => 4, fn => \&CircularVal,   par => 99,                  unit => '',     def => 0           },
  daysUntilBatteryCare        => { fnr => 4, fn => \&CircularVal,   par => 99,                  unit => '',     def => '-'         },
  todayConsumptionForecast    => { fnr => 4, fn => \&NexthoursVal,  par => 'confc',             unit => ' Wh',  def => '-'         },
  conForecastTillNextSunrise  => { fnr => 4, fn => \&NexthoursVal,  par => 'confc',             unit => ' Wh',  def => 0           },
);

  for my $csr (1..$maxconsumer) {
      $csr                                       = sprintf "%02d", $csr;
      $hcsr{'currentRunMtsConsumer_'.$csr}{fnr}  = 4;
      $hcsr{'currentRunMtsConsumer_'.$csr}{fn}   = \&ConsumerVal;
      $hcsr{'currentRunMtsConsumer_'.$csr}{par}  = 'cycleTime';
      $hcsr{'currentRunMtsConsumer_'.$csr}{unit} = ' min';
      $hcsr{'currentRunMtsConsumer_'.$csr}{def}  = 0;
  }


# Information zu verwendeten internen Datenhashes
# $data{$type}{$name}{circular}                                                  # Ringspeicher
# $data{$type}{$name}{current}                                                   # current values
# $data{$type}{$name}{pvhist}                                                    # historische Werte
# $data{$type}{$name}{nexthours}                                                 # NextHours Werte
# $data{$type}{$name}{consumers}                                                 # Consumer Hash
# $data{$type}{$name}{strings}                                                   # Stringkonfiguration Hash
# $data{$type}{$name}{solcastapi}                                                # Zwischenspeicher API-Daten
# $data{$type}{$name}{aidectree}{object}                                         # AI Decision Tree Object
# $data{$type}{$name}{aidectree}{aitrained}                                      # AI Decision Tree trainierte Daten
# $data{$type}{$name}{aidectree}{airaw}                                          # Rohdaten für AI Input = Raw Trainigsdaten
# $data{$type}{$name}{func}                                                      # interne Funktionen

################################################################
#               Init Fn
################################################################
sub Initialize {
  my $hash = shift;

  my $fwd  = join ",", devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
  my $hod  = join ",", map { sprintf "%02d", $_} (1..24);
  my $srd  = join ",", sort keys (%hcsr);

  my ($consumer,@allc);
  for my $c (1..$maxconsumer) {
      $c         = sprintf "%02d", $c;
      $consumer .= "consumer${c}:textField-long ";
      push @allc, $c;
  }

  my $allcs = join ",", @allc;
  my $dm    = join ",", @dd;

  $hash->{DefFn}              = \&Define;
  $hash->{UndefFn}            = \&Undef;
  $hash->{GetFn}              = \&Get;
  $hash->{SetFn}              = \&Set;
  $hash->{DeleteFn}           = \&Delete;
  $hash->{FW_summaryFn}       = \&FwFn;
  $hash->{FW_detailFn}        = \&FwFn;
  $hash->{ShutdownFn}         = \&Shutdown;
  $hash->{DbLog_splitFn}      = \&DbLogSplit;
  $hash->{AttrFn}             = \&Attr;
  $hash->{NotifyFn}           = \&Notify;
  $hash->{ReadyFn}            = \&runCentralTask;
  $hash->{AttrList}           = "affect70percentRule:1,dynamic,0 ".
                                "affectBatteryPreferredCharge:slider,0,1,100 ".
                                "affectConsForecastIdentWeekdays:1,0 ".
                                "affectConsForecastInPlanning:1,0 ".
                                "affectMaxDayVariance ".
                                "affectNumHistDays:slider,1,1,30 ".
                                "affectSolCastPercentile:select,10,50,90 ".
                                "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                "consumerAdviceIcon ".
                                "consumerLink:0,1 ".
                                "ctrlAIdataStorageDuration ".
                                "ctrlAutoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "ctrlAutoRefreshFW:$fwd ".
                                "ctrlBackupFilesKeep ".
                                "ctrlBatSocManagement:textField-long ".
                                "ctrlConsRecommendReadings:multiple-strict,$allcs ".
                                "ctrlDebug:multiple-strict,$dm,#14 ".
                                "ctrlGenPVdeviation:daily,continuously ".
                                "ctrlInterval ".
                                "ctrlLanguage:DE,EN ".
                                "ctrlNextDayForecastReadings:multiple-strict,$hod ".
                                "ctrlShowLink:1,0 ".
                                "ctrlSolCastAPImaxReq:selectnumbers,5,5,60,0,lin ".
                                "ctrlSolCastAPIoptimizeReq:1,0 ".
                                "ctrlStatisticReadings:multiple-strict,$srd ".
                                "ctrlUserExitFn:textField-long ".
                                "disable:1,0 ".
                                "flowGraphicSize ".
                                "flowGraphicAnimate:1,0 ".
                                "flowGraphicConsumerDistance:slider,80,10,500 ".
                                "flowGraphicShowConsumer:1,0 ".
                                "flowGraphicShowConsumerDummy:1,0 ".
                                "flowGraphicShowConsumerPower:0,1 ".
                                "flowGraphicShowConsumerRemainTime:0,1 ".
                                "flowGraphicCss:textField-long ".
                                "graphicBeamHeight ".
                                "graphicBeamWidth:slider,20,5,100 ".
                                "graphicBeam1Color:colorpicker,RGB ".
                                "graphicBeam2Color:colorpicker,RGB ".
                                "graphicBeam1Content:pvForecast,pvReal,gridconsumption,consumptionForecast ".
                                "graphicBeam2Content:pvForecast,pvReal,gridconsumption,consumptionForecast ".
                                "graphicBeam1FontColor:colorpicker,RGB ".
                                "graphicBeam2FontColor:colorpicker,RGB ".
                                "graphicBeam1MaxVal ".
                                "graphicEnergyUnit:Wh,kWh ".
                                "graphicHeaderOwnspec:textField-long ".
                                "graphicHeaderOwnspecValForm:textField-long ".
                                "graphicHeaderDetail:multiple-strict,all,co,pv,own,status ".
                                "graphicHeaderShow:1,0 ".
                                "graphicHistoryHour:slider,0,1,23 ".
                                "graphicHourCount:slider,4,1,24 ".
                                "graphicHourStyle ".
                                "graphicLayoutType:single,double,diff ".
                                "graphicSelect:both,flow,forecast,none ".
                                "graphicShowDiff:no,top,bottom ".
                                "graphicShowNight:1,0 ".
                                "graphicShowWeather:1,0 ".
                                "graphicSpaceSize ".
                                "graphicStartHtml ".
                                "graphicEndHtml ".
                                "graphicWeatherColor:colorpicker,RGB ".
                                "graphicWeatherColorNight:colorpicker,RGB ".
                                $consumer.
                                $readingFnAttributes;

  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667

  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  # $hash->{AttrRenameMap} = { "beam1Color"         => "graphicBeam1Color",
  #                            "beam1Content"       => "graphicBeam1Content",
  #                          };

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'

return;
}

###############################################################
#                  SolarForecast Define
###############################################################
sub Define {
  my ($hash, $def) = @_;

  my @a = split(/\s+/x, $def);

  return "Error: Perl module ".$jsonabs." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($jsonabs);

  my $name                       = $hash->{NAME};
  my $type                       = $hash->{TYPE};
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                                 # Modul Meta.pm nicht vorhanden

  my $params = {
      hash        => $hash,
      name        => $hash->{NAME},
      type        => $hash->{TYPE},
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 1,
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                                              # Versionsinformationen setzen

  createAssociatedWith ($hash);

  $params->{file}      = $pvhcache.$name;                                                                # Cache File PV History einlesen wenn vorhanden
  $params->{cachename} = 'pvhist';
  $params->{title}     = 'pvHistory';
  _readCacheFile ($params);

  $params->{file}      = $pvccache.$name;                                                                # Cache File PV Circular einlesen wenn vorhanden
  $params->{cachename} = 'circular';
  $params->{title}     = 'pvCircular';
  _readCacheFile ($params);

  $params->{file}      = $csmcache.$name;                                                                # Cache File Consumer einlesen wenn vorhanden
  $params->{cachename} = 'consumers';
  $params->{title}     = 'consumerMaster';
  _readCacheFile ($params);

  $params->{file}      = $scpicache.$name;                                                               # Cache File SolCast API Werte einlesen wenn vorhanden
  $params->{cachename} = 'solcastapi';
  $params->{title}     = 'solApiData';
  _readCacheFile ($params);

  $params->{file}      = $aitrained.$name;                                                               # AI Cache File einlesen wenn vorhanden
  $params->{cachename} = 'aitrained';
  $params->{title}     = 'aiTrainedData';
  _readCacheFile ($params);

  $params->{file}      = $airaw.$name;                                                                   # AI Rawdaten File einlesen wenn vorhanden
  $params->{cachename} = 'airaw';
  $params->{title}     = 'aiRawData';
  _readCacheFile ($params);

  singleUpdateState ( {hash => $hash, state => 'initialized', evt => 1} );

  $readyfnlist{$name} = $hash;                                                                           # Registrierung in Ready-Schleife
  InternalTimer (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0); # Einstieg periodisches Schreiben historische Daten

return;
}

################################################################
#                   Cachefile lesen
################################################################
sub _readCacheFile {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $type      = $paref->{type};
  my $file      = $paref->{file};
  my $cachename = $paref->{cachename};
  my $title     = $paref->{title};

  if ($cachename eq 'aitrained') {
      my ($err, $dtree) = fileRetrieve ($file);

      if (!$err && $dtree) {
          my $valid = $dtree->isa('AI::DecisionTree');

          if ($valid) {
              $data{$type}{$name}{aidectree}{aitrained}  = $dtree;
              $data{$type}{$name}{current}{aitrainstate} = 'ok';
              Log3 ($name, 3, qq{$name - cached data "$title" restored});
          }
      }

      return;
  }

  if ($cachename eq 'airaw') {
      my ($err, $data) = fileRetrieve ($file);

      if (!$err && $data) {
          $data{$type}{$name}{aidectree}{airaw}     = $data;
          $data{$type}{$name}{current}{aitrawstate} = 'ok';
          Log3 ($name, 3, qq{$name - cached data "$title" restored});
      }

      return;
  }

  my ($error, @content) = FileRead ($file);

  if (!$error) {
      my $json      = join "", @content;
      my ($success) = evaljson ($hash, $json);

      if ($success) {
           $data{$hash->{TYPE}}{$name}{$cachename} = decode_json ($json);
           Log3 ($name, 3, qq{$name - cached data "$title" restored});
      }
      else {
          Log3 ($name, 1, qq{$name - WARNING - The content of file "$file" is not readable or may be corrupt});
      }
  }

return;
}

###############################################################
#                  SolarForecast Set
###############################################################
sub Set {
  my ($hash, @a) = @_;
  return qq{"set X" needs at least an argument} if(@a < 2);
  my $name  = shift @a;
  my $opt   = shift @a;
  my @args  = @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
  my $prop1 = shift @a;
  my $prop2 = shift @a;

  return if((controller($name))[1]);

  my ($setlist,@fcdevs,@cfs,@condevs,@bkps);
  my ($fcd,$ind,$med,$cf,$sp,$coms) = ('','','','','','');
  my $type = $hash->{TYPE};

  my @re = qw( aiData
               batteryTriggerSet
               consumerMaster
               consumerPlanning
               consumption
               currentBatterySet
               currentInverterSet
               currentMeterSet
               energyH4TriggerSet
               inverterStringSet
               moduleRoofTopSet
               powerTriggerSet
               pvCorrection
               roofIdentPair
               pvHistory
             );
  my $resets = join ",",@re;

  @fcdevs = devspec2array("TYPE=DWD_OpenData");
  $fcd    = join ",", @fcdevs if(@fcdevs);

  push @fcdevs, 'SolCast-API';
  push @fcdevs, 'ForecastSolar-API';
  push @fcdevs, 'VictronKI-API';

  my $rdd = join ",", @fcdevs;

  for my $h (@chours) {
      push @cfs, 'pvCorrectionFactor_'. sprintf("%02d",$h);
  }
  $cf = join " ", @cfs;

  for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {
      push @condevs, $c if($c);
  }

  $coms    = @condevs ? join ",", @condevs : 'noArg';
  my $ipai = isPrepared4AI ($hash);

  opendir (DIR, $cachedir);

  while (my $file = readdir (DIR)) {
      next unless (-f "$cachedir/$file");
      next unless ($file =~ /_${name}_/);
      next unless ($file =~ /_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}$/);
      push @bkps, 'recover-'.$file;
  }

  closedir (DIR);
  my $rf = @bkps ? ','.join ",", reverse sort @bkps : '';

  ## allg. gültige Setter
  #########################
  $setlist = "Unknown argument $opt, choose one of ".
             "consumerImmediatePlanning:$coms ".
             "consumerNewPlanning:$coms ".
             "currentWeatherDev:$fcd ".
             "currentRadiationAPI:$rdd ".
             "currentBatteryDev:textField-long ".
             "currentInverterDev:textField-long ".
             "currentMeterDev:textField-long ".
             "energyH4Trigger:textField-long ".
             "inverterStrings ".
             "modulePeakString ".
             "operatingMemory:backup,save".$rf." ".
             "operationMode:active,inactive ".
             "plantConfiguration:check,save,restore ".
             "powerTrigger:textField-long ".
             "pvCorrectionFactor_Auto:noLearning,on_simple".($ipai ? ',on_simple_ai,' : ',')."on_complex".($ipai ? ',on_complex_ai,' : ',')."off ".
             "reset:$resets ".
             $cf." "
             ;

  ## API spezifische Setter
  ###########################
  if (isSolCastUsed ($hash)) {
      $setlist .= "moduleRoofTops ".
                  "roofIdentPair "
                  ;
  }
  elsif (isForecastSolarUsed ($hash)) {
      $setlist .= "moduleDirection ".
                  "moduleTiltAngle "
                  ;
  }
  elsif (isVictronKiUsed ($hash)) {
      $setlist .= "vrmCredentials "
                  ;
  }
  else {
      $setlist .= "moduleDirection ".
                  "moduleTiltAngle "
                  ;
  }

  ## KI spezifische Setter
  ##########################
  if ($ipai) {
      $setlist .= "aiDecTree:addInstances,addRawData,train ";
  }

  ## Batterie spezifische Setter
  ################################
  if (isBatteryUsed ($name)) {
      $setlist .= "batteryTrigger:textField-long ";
  }

  ## inactive (Setter überschreiben)
  ####################################
  if ((controller($name))[2]) {
      $setlist = "operationMode:active,inactive ";
  }

  my $params = {
      hash    => $hash,
      name    => $name,
      type    => $type,
      opt     => $opt,
      arg     => $arg,
      argsref => \@args,
      prop    => $prop,
      prop1   => $prop1,
      prop2   => $prop2,
      lang    => getLang  ($hash),
      debug   => getDebug ($hash)
  };

  if($hset{$opt} && defined &{$hset{$opt}{fn}}) {
      my $ret = q{};
      $ret    = &{$hset{$opt}{fn}} ($params);
      return $ret;
  }

return "$setlist";
}

################################################################
#                      Setter consumerImmediatePlanning
################################################################
sub _setconsumerImmediatePlanning {      ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $opt     = $paref->{opt};
  my $c       = $paref->{prop};
  my $evt     = $paref->{prop1} // 0;                                                          # geändert V 1.1.0 - 1 -> 0

  return qq{no consumer number specified} if(!$c);
  return qq{no valid consumer id "$c"}    if(!ConsumerVal ($hash, $c, "name", ""));

  if (ConsumerVal ($hash, $c, 'type', $defctype) eq 'noSchedule') {
      debugLog ($paref, "consumerPlanning", qq{consumer "$c" - }.$hqtxt{scnp}{EN});

      $paref->{ps}       = 'noSchedule';
      $paref->{consumer} = $c;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{consumer};
      return;
  }

  my $startts  = time;
  my $mintime  = ConsumerVal ($hash, $c, "mintime", $defmintime);

  if (isSunPath ($hash, $c)) {                                                                 # SunPath ist in mintime gesetzt
      my (undef, $setshift) = sunShift   ($hash, $c);                                          # Verschiebung (Sekunden) Sonnenuntergang bei SunPath Verwendung
      my $tdiff             = (CurrentVal ($hash, 'sunsetTodayTs', 0) + $setshift) - $startts;
      $mintime              = $tdiff / 60;                                                     # Minuten
  }

  my $stopdiff = $mintime * 60;
  my $stopts   = $startts + $stopdiff;

  $paref->{consumer} = $c;
  $paref->{ps}       = "planned:";
  $paref->{startts}  = $startts;                                                               # Unix Timestamp für geplanten Switch on
  $paref->{stopts}   = $stopts;                                                                # Unix Timestamp für geplanten Switch off

  ___setConsumerPlanningState ($paref);
  ___saveEhodpieces           ($paref);
  ___setPlanningDeleteMeth    ($paref);

  my $planstate = ConsumerVal ($hash, $c, 'planstate', '');
  my $calias    = ConsumerVal ($hash, $c, 'alias',     '');

  writeCacheToFile ($hash, "consumers", $csmcache.$name);                                      # Cache File Consumer schreiben

  Log3 ($name, 3, qq{$name - Consumer "$calias" $planstate}) if($planstate);

  centralTask ($hash, $evt);

return;
}

################################################################
#         Setter consumerNewPlanning
################################################################
sub _setconsumerNewPlanning {            ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $c       = $paref->{prop};
  my $evt     = $paref->{prop1} // 0;                                                          # geändert V 1.1.0 - 1 -> 0

  return qq{no consumer number specified} if(!$c);
  return qq{no valid consumer id "$c"}    if(!ConsumerVal ($hash, $c, 'name', ''));

  if ($c) {
      deleteConsumerPlanning ($hash, $c);
      writeCacheToFile       ($hash, 'consumers', $csmcache.$name);                            # Cache File Consumer schreiben
  }

  centralTask ($hash, $evt);

return;
}

################################################################
#       Setter currentWeatherDev (Wetterdaten)
################################################################
sub _setcurrentWeatherDev {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no forecast device specified};

  if(!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData") {
      return qq{The device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};
  }

  readingsSingleUpdate ($hash, "currentWeatherDev", $prop, 1);
  createAssociatedWith ($hash);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);                       # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentRadiationAPI
################################################################
sub _setcurrentRadiationAPI {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no radiation device specified};

  if($prop !~ /-API$/x && (!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData")) {
      return qq{The device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};
  }

  if ($prop eq 'SolCast-API') {
      return "The library FHEM::Utility::CTZ is missing. Please update FHEM completely." if($ctzAbsent);

      my $rmf = reqModFail();
      return "You have to install the required perl module: ".$rmf if($rmf);
  }

  if ($prop eq 'ForecastSolar-API') {
      my ($set, $lat, $lon) = locCoordinates();
      return qq{set attributes 'latitude' and 'longitude' in global device first} if(!$set);

      my $tilt = ReadingsVal ($name, 'moduleTiltAngle', '');                         # Modul Neigungswinkel für jeden Stringbezeichner
      return qq{Please complete command "set $name moduleTiltAngle".} if(!$tilt);

      my $dir = ReadingsVal ($name, 'moduleDirection', '');                          # Modul Ausrichtung für jeden Stringbezeichner
      return qq{Please complete command "set $name moduleDirection".} if(!$dir);
  }

  if ($prop eq 'VictronVRM-API') {

  }

  readingsSingleUpdate ($hash, "currentRadiationAPI", $prop, 1);
  createAssociatedWith ($hash);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);                      # Anlagenkonfiguration File schreiben
  setModel             ($hash);                                                      # Model setzen

  my $type                                           = $hash->{TYPE};
  $data{$type}{$name}{current}{allStringsFullfilled} = 0;                            # Stringkonfiguration neu prüfen lassen

return;
}

################################################################
#                      Setter roofIdentPair
################################################################
sub _setroofIdentPair {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my ($a,$h) = parseParams ($arg);
  my $pk  = $a->[0] // "";

  if(!$pk) {
      return qq{Every roofident pair needs a pairkey! Use: <pairkey> rtid=<Rooftop ID> apikey=<api key>};
  }

  if(!$h->{rtid} || !$h->{apikey}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  my $type = $hash->{TYPE};

  $data{$type}{$name}{solcastapi}{'?IdPair'}{'?'.$pk}{rtid}   = $h->{rtid};
  $data{$type}{$name}{solcastapi}{'?IdPair'}{'?'.$pk}{apikey} = $h->{apikey};

  writeCacheToFile ($hash, "solcastapi", $scpicache.$name);                             # Cache File SolCast API Werte schreiben

  my $msg = qq{The Roof identification pair "$pk" has been saved. }.
            qq{Repeat the command if you want to save more Roof identification pairs.};

return $msg;
}

######################################################################
#                      Setter victronCredentials
# user, pwd,
# idsite nach /installation// aus:
# https://vrm.victronenergy.com/installation/XXXXX/...
######################################################################
sub _setVictronCredentials {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  my $type  = $hash->{TYPE};

  my $msg;

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my ($a,$h) = parseParams ($arg);

  if ($a->[0] && $a->[0] eq 'delete') {
      delete $data{$type}{$name}{solcastapi}{'?VRM'};
      $msg = qq{Credentials for the Victron VRM API are deleted. };
  }
  else {
      if(!$h->{user} || !$h->{pwd} || !$h->{idsite}) {
          return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
      }

      my $serial = eval { freeze ($h)
                        }
                        or do { return "Serialization ERROR: $@" };

      $data{$type}{$name}{solcastapi}{'?VRM'}{'?API'}{credentials} = chew ($serial);

      $msg = qq{Credentials for the Victron VRM API has been saved.};
  }

  writeCacheToFile ($hash, "solcastapi", $scpicache.$name);                             # Cache File SolCast API Werte schreiben

return $msg;
}

################################################################
#                 Setter moduleRoofTops
################################################################
sub _setmoduleRoofTops {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no module RoofTop was provided};

  my ($a,$h) = parseParams ($arg);

  if(!keys %$h) {
      return qq{The provided module RoofTop has wrong format};
  }

  while (my ($is, $pk) = each %$h) {
      my $rtid   = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'rtid',   '');
      my $apikey = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'apikey', '');

      if(!$rtid || !$apikey) {
          return qq{The roofIdentPair "$pk" of String "$is" has no Rooftop-ID and/or SolCast-API key assigned ! \n}.
                 qq{Set the roofIdentPair "$pk" previously with "set $name roofIdentPair".} ;
      }
  }

  readingsSingleUpdate ($hash, "moduleRoofTops", $arg, 1);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                      # keine Stringkonfiguration wenn Setup noch nicht komplett

  my $ret = createStringConfig ($hash);
  return $ret if($ret);

return;
}

################################################################
#                      Setter currentInverterDev
################################################################
sub _setinverterDevice {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my ($a,$h) = parseParams ($arg);
  my $indev  = $a->[0] // "";

  if(!$indev || !$defs{$indev}) {
      return qq{The device "$indev" doesn't exist!};
  }

  if(!$h->{pv} || !$h->{etotal}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  readingsSingleUpdate ($hash, 'currentInverterDev', $arg, 1);
  createAssociatedWith ($hash);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter inverterStrings
################################################################
sub _setinverterStrings {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no inverter strings specified};

  if ($prop =~ /\?/xs) {
      return qq{The inverter string designation is wrong. An inverter string name must not contain a '?' character!};
  }

  my $type = $hash->{TYPE};

  my @istrings = split ",", $prop;

  for my $k (keys %{$data{$type}{$name}{solcastapi}}) {
      next if ($k =~ /\?/xs || $k ~~ @istrings);
      delete $data{$type}{$name}{solcastapi}{$k};
  }

  readingsSingleUpdate ($hash, "inverterStrings", $prop,    1);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);                    # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                       # keine Stringkonfiguration wenn Setup noch nicht komplett

  my $ret = qq{NOTE: After setting or changing "inverterStrings" please check }.
            qq{/ set all module parameter (e.g. moduleTiltAngle) again ! \n}.
            qq{Use "set $name plantConfiguration check" to validate your Setup.};

return $ret;
}

################################################################
#                      Setter currentMeterDev
################################################################
sub _setmeterDevice {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my ($a,$h) = parseParams ($arg);
  my $medev  = $a->[0] // "";

  if(!$medev || !$defs{$medev}) {
      return qq{The device "$medev" doesn't exist!};
  }

  if(!$h->{gcon} || !$h->{contotal} || !$h->{gfeedin} || !$h->{feedtotal}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  if($h->{gcon} eq "-gfeedin" && $h->{gfeedin} eq "-gcon") {
      return qq{Incorrect input. It is not allowed that the keys gcon and gfeedin refer to each other.};
  }

  ## alte Speicherwerte löschen
  ###############################
  delete $data{$type}{$name}{circular}{'99'}{feedintotal};
  delete $data{$type}{$name}{circular}{'99'}{initdayfeedin};
  delete $data{$type}{$name}{circular}{'99'}{gridcontotal};
  delete $data{$type}{$name}{circular}{'99'}{initdaygcon};

  readingsSingleUpdate ($hash, "currentMeterDev", $arg, 1);
  createAssociatedWith ($hash);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentBatteryDev
################################################################
sub _setbatteryDevice {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my ($a,$h) = parseParams ($arg);
  my $badev  = $a->[0] // "";

  if(!$badev || !$defs{$badev}) {
      return qq{The device "$badev" doesn't exist!};
  }

  if(!$h->{pin} || !$h->{pout}) {
      return qq{The keys "pin" and/or "pout" are not set. Please note the command reference.};
  }

  if(($h->{pin}  !~ /-/xs && $h->{pin} !~ /:/xs)   ||
     ($h->{pout} !~ /-/xs && $h->{pout} !~ /:/xs)) {
      return qq{The keys "pin" and/or "pout" are not set correctly. Please note the command reference.};
  }

  if($h->{pin} eq "-pout" && $h->{pout} eq "-pin") {
      return qq{Incorrect input. It is not allowed that the keys pin and pout refer to each other.};
  }

  ## alte Speicherwerte löschen
  ###############################
  delete $data{$type}{$name}{circular}{'99'}{initdaybatintot};
  delete $data{$type}{$name}{circular}{'99'}{batintot};
  delete $data{$type}{$name}{circular}{'99'}{initdaybatouttot};
  delete $data{$type}{$name}{circular}{'99'}{batouttot};
  delete $data{$type}{$name}{circular}{'99'}{lastTsMaxSocRchd};
  delete $data{$type}{$name}{circular}{'99'}{nextTsMaxSocChge};

  readingsSingleUpdate ($hash, "currentBatteryDev", $arg, 1);
  createAssociatedWith ($hash);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#       Setter operationMode
################################################################
sub _setoperationMode {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no mode specified};

  singleUpdateState ( {hash => $hash, state => $prop, evt => 1} );

return;
}

################################################################
#     Setter powerTrigger / batterytrigger / energyH4Trigger
################################################################
sub _setTrigger {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my ($a,$h) = parseParams ($arg);

  if(!$h) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  for my $key (keys %{$h}) {
      if($key !~ /^[0-9]+(?:on|off)$/x || $h->{$key} !~ /^[0-9]+$/x) {
          return qq{The key "$key" is invalid. Please consider the commandref.};
      }
  }

  if ($opt eq 'powerTrigger') {
      deleteReadingspec    ($hash, 'powerTrigger.*');
      readingsSingleUpdate ($hash, 'powerTrigger',    $arg, 1);
  }
  elsif ($opt eq 'batteryTrigger') {
      deleteReadingspec    ($hash, 'batteryTrigger.*');
      readingsSingleUpdate ($hash, 'batteryTrigger',  $arg, 1);
  }
  elsif ($opt eq 'energyH4Trigger') {
      deleteReadingspec    ($hash, 'energyH4Trigger.*');
      readingsSingleUpdate ($hash, 'energyH4Trigger', $arg, 1);
  }

  writeCacheToFile ($hash, "plantconfig", $plantcfg.$name);                              # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter modulePeakString
################################################################
sub _setmodulePeakString {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no PV module peak specified};

  $arg =~ s/,/./xg;

  my ($a,$h) = parseParams ($arg);

  if(!keys %$h) {
      return qq{The provided PV module peak has wrong format};
  }

  while (my ($key, $value) = each %$h) {
      if($value !~ /[0-9.]/x) {
          return qq{The module peak of "$key" must be specified by numbers and optionally with decimal places};
      }
  }

  readingsSingleUpdate ($hash, "modulePeakString", $arg, 1);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                      # keine Stringkonfiguration wenn Setup noch nicht komplett

  my $ret = createStringConfig ($hash);
  return $ret if($ret);

return;
}

################################################################
#                      Setter moduleTiltAngle
################################################################
sub _setmoduleTiltAngle {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no tilt angle was provided};

  my $tilt  = join "|", sort keys %hff;

  my ($a,$h) = parseParams ($arg);

  if(!keys %$h) {
      return qq{The provided tilt angle has wrong format};
  }

  while (my ($key, $value) = each %$h) {
      if($value !~ /^(?:$tilt)$/x) {
          return qq{The tilt angle of "$key" is wrong};
      }
  }

  readingsSingleUpdate ($hash, "moduleTiltAngle", $arg, 1);
  writeCacheToFile     ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                      # keine Stringkonfiguration wenn Setup noch nicht komplett

  my $ret = createStringConfig ($hash);
  return $ret if($ret);

return;
}

################################################################
#                 Setter moduleDirection
#
#  Angabe entweder als Azimut-Bezeichner oder direkte
#  Azimut Angabe -180 ...0...180
#
################################################################
sub _setmoduleDirection {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no module direction was provided};

  my $dirs  = "N|NE|E|SE|S|SW|W|NW";                                                # mögliche Azimut-Bezeichner wenn keine direkte Azimut Angabe

  my ($a,$h) = parseParams ($arg);

  if(!keys %$h) {
      return qq{The provided module direction has wrong format};
  }

  while (my ($key, $value) = each %$h) {
      if($value !~ /^(?:$dirs)$/x && ($value !~ /^(?:-?[0-9]{1,3})$/x || $value < -180 || $value > 180)) {
          return qq{The module direction of "$key" is wrong: $value};
      }
  }

  readingsSingleUpdate ($hash, "moduleDirection", $arg,         1);
  writeCacheToFile     ($hash, "plantconfig",     $plantcfg.$name);                # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                       # keine Stringkonfiguration wenn Setup noch nicht komplett

  my $ret = createStringConfig ($hash);
  return $ret if($ret);

return;
}

################################################################
#                      Setter plantConfiguration
################################################################
sub _setplantConfiguration {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  my ($err,@pvconf);

  $arg = 'check' if (!$arg);

  if ($arg eq "check") {
      my $out = checkPlantConfig ($hash);
      $out    = qq{<html>$out</html>};

      ## asynchrone Ausgabe
      #######################
      #$err          = getClHash($hash);
      #$paref->{out} = $out;
      #InternalTimer(gettimeofday()+3, "FHEM::SolarForecast::__plantCfgAsynchOut", $paref, 0);

      return $out;
  }

  if ($arg eq "save") {
      $err = writeCacheToFile ($hash, 'plantconfig', $plantcfg.$name);             # Anlagenkonfiguration File schreiben
      if ($err) {
          return $err;
      }
      else {
          return qq{Plant Configuration has been written to file "}.$plantcfg.$name.qq{"};
      }
  }

  if ($arg eq "restore") {
      ($err, @pvconf) = FileRead ($plantcfg.$name);

      if (!$err) {
          my $rbit = 0;

          for my $elem (@pvconf) {
              my ($reading, $val) = split "<>", $elem;
              next if(!$reading || !defined $val);
              CommandSetReading (undef,"$name $reading $val");
              $rbit = 1;
          }

          if ($rbit) {
              return qq{Plant Configuration restored from file "}.$plantcfg.$name.qq{"};
          }
          else {
              return qq{The Plant Configuration file "}.$plantcfg.$name.qq{" was empty, nothing restored};
          }
      }
      else {
          return $err;
      }
  }

return;
}

################################################################
#   asynchrone Ausgabe Ergbnis Plantconfig Check
################################################################
sub __plantCfgAsynchOut {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $out   = $paref->{out};

  asyncOutput($hash->{HELPER}{CL}{1}, $out);
  delClHash  ($name);

return;
}

################################################################
#                      Setter pvCorrectionFactor
################################################################
sub _setpvCorrectionFactor {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop} // return qq{no correction value specified};

  if($prop !~ /[0-9,.]/x) {
      return qq{The correction value must be specified by numbers and optionally with decimal places};
  }

  $prop =~ s/,/./x;

  readingsSingleUpdate($hash, $opt, $prop." (manual)", 1);

  my $cfnum = (split "_", $opt)[1];
  deleteReadingspec ($hash, "pvCorrectionFactor_${cfnum}_autocalc");

  centralTask ($hash, 0);

return;
}

################################################################
#                 Setter pvCorrectionFactor_Auto
################################################################
sub _setpvCorrectionFactorAuto {         ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop} // return qq{no correction value specified};

  if ($prop eq 'noLearning') {
      my $pfa = ReadingsVal ($name, 'pvCorrectionFactor_Auto', 'off');           # aktuelle Autokorrektureinstellung
      $prop   = $pfa.' '.$prop;
  }

  readingsSingleUpdate($hash, 'pvCorrectionFactor_Auto', $prop, 1);

  if ($prop eq 'off') {
      for my $n (1..24) {
          $n     = sprintf "%02d", $n;
          my $rv = ReadingsVal ($name, "pvCorrectionFactor_${n}", "");
          deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*")  if($rv !~ /manual/xs);
      }

      deleteReadingspec ($hash, "pvCorrectionFactor_.*_autocalc");
  }

   writeCacheToFile ($hash, 'plantconfig', $plantcfg.$name);                    # Anlagenkonfiguration sichern

return;
}

################################################################
#                      Setter reset
################################################################
sub _setreset {                          ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no source specified for reset};

  my $type  = $hash->{TYPE};

  if ($prop eq 'pvHistory') {
      my $dday  = $paref->{prop1} // "";                                       # ein bestimmter Tag der pvHistory angegeben ?
      my $dhour = $paref->{prop2} // "";                                       # eine bestimmte Stunde eines Tages der pvHistory angegeben ?

      if ($dday) {
          if ($dhour) {
              delete $data{$type}{$name}{pvhist}{$dday}{$dhour};
              Log3 ($name, 3, qq{$name - Day "$dday" hour "$dhour" deleted from pvHistory});

              $paref->{reorg}    = 1;                                          # den Tag Stunde "99" reorganisieren
              $paref->{reorgday} = $dday;
              setPVhistory ($paref);
              delete $paref->{reorg};
              delete $paref->{reorgday};
          }
          else {
              delete $data{$type}{$name}{pvhist}{$dday};
              Log3 ($name, 3, qq{$name - Day "$dday" deleted from pvHistory});
          }
      }
      else {
          delete $data{$type}{$name}{pvhist};
          Log3 ($name, 3, qq{$name - all days deleted from pvHistory});
      }

      return;
  }

  if ($prop eq 'consumption') {
      my $dday  = $paref->{prop1} // "";                                       # ein bestimmter Tag der pvHistory angegeben ?
      my $dhour = $paref->{prop2} // "";                                       # eine bestimmte Stunde eines Tages der pvHistory angegeben ?

      if ($dday) {
          if ($dhour) {
              delete $data{$type}{$name}{pvhist}{$dday}{$dhour}{con};
              Log3 ($name, 3, qq{$name - consumption day "$dday" hour "$dhour" deleted from pvHistory});

              $paref->{reorg}    = 1;                                          # den Tag Stunde "99" reorganisieren
              $paref->{reorgday} = $dday;
              setPVhistory ($paref);
              delete $paref->{reorg};
              delete $paref->{reorgday};
          }
          else {
              for my $hr (sort keys %{$data{$type}{$name}{pvhist}{$dday}}) {
                  delete $data{$type}{$name}{pvhist}{$dday}{$hr}{con};
              }

              Log3 ($name, 3, qq{$name - consumption day "$dday" deleted from pvHistory});
          }
      }
      else {
          for my $dy (sort keys %{$data{$type}{$name}{pvhist}}) {
              for my $hr (sort keys %{$data{$type}{$name}{pvhist}{$dy}}) {
                  delete $data{$type}{$name}{pvhist}{$dy}{$hr}{con};
              }
          }

          Log3 ($name, 3, qq{$name - all saved consumption deleted from pvHistory});
      }

      return;
  }

  if ($prop eq 'pvCorrection') {
      for my $n (1..24) {
          $n = sprintf "%02d", $n;
          deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*");
      }

      my $circ  = $paref->{prop1} // 'no';                                   # alle pvKorr-Werte aus Caches löschen ?
      my $circh = $paref->{prop2} // q{};                                    # pvKorr-Werte einer bestimmten Stunde aus Caches löschen ?

      if ($circ eq 'cached') {
          if ($circh) {
              delete $data{$type}{$name}{circular}{$circh}{pvcorrf};
              delete $data{$type}{$name}{circular}{$circh}{quality};

              for my $hid (keys %{$data{$type}{$name}{pvhist}}) {
                  delete $data{$type}{$name}{pvhist}{$hid}{$circh}{pvcorrf};
              }

              Log3($name, 3, qq{$name - stored PV correction factor of hour "$circh" from pvCircular and pvHistory deleted});
              return;
          }

          for my $hod (keys %{$data{$type}{$name}{circular}}) {
              delete $data{$type}{$name}{circular}{$hod}{pvcorrf};
              delete $data{$type}{$name}{circular}{$hod}{quality};
          }

          for my $hid (keys %{$data{$type}{$name}{pvhist}}) {
              for my $hidh (keys %{$data{$type}{$name}{pvhist}{$hid}}) {
                  delete $data{$type}{$name}{pvhist}{$hid}{$hidh}{pvcorrf};
              }
          }

          Log3($name, 3, qq{$name - all stored PV correction factors from pvCircular and pvHistory deleted});
      }

      return;
  }

  if ($prop eq 'aiData') {
      delete $data{$type}{$name}{current}{aiinitstate};
      delete $data{$type}{$name}{current}{aitrainstate};
      delete $data{$type}{$name}{current}{aiaddistate};
      delete $data{$type}{$name}{current}{aigetresult};

      my @ftd = ( $airaw.$name,
                  $aitrained.$name
                );

      for my $f (@ftd) {
          my $err = FileDelete($f);

          if ($err) {
              Log3 ($name, 1, qq{$name - Message while deleting file "$f": $err});
          }
      }

      aiInit ($paref);

      return;
  }

  if ($prop eq 'powerTriggerSet') {
      deleteReadingspec ($hash, "powerTrigger.*");
      writeCacheToFile  ($hash, "plantconfig", $plantcfg.$name);               # Anlagenkonfiguration File schreiben
      return;
  }

  if ($prop eq 'batteryTriggerSet') {
      deleteReadingspec ($hash, "batteryTrigger.*");
      writeCacheToFile  ($hash, "plantconfig", $plantcfg.$name);
      return;
  }

  if ($prop eq 'energyH4TriggerSet') {
      deleteReadingspec ($hash, "energyH4Trigger.*");
      writeCacheToFile  ($hash, "plantconfig", $plantcfg.$name);
      return;
  }

  if ($prop eq 'moduleRoofTopSet') {
      deleteReadingspec ($hash, "moduleRoofTops");
      writeCacheToFile  ($hash, "plantconfig", $plantcfg.$name);
      return;
  }

  readingsDelete ($hash, $prop);

  if ($prop eq 'roofIdentPair') {
      my $pk   = $paref->{prop1} // "";                                        # ein bestimmter PairKey angegeben ?

      if ($pk) {
          delete $data{$type}{$name}{solcastapi}{'?IdPair'}{'?'.$pk};
          Log3 ($name, 3, qq{$name - roofIdentPair: pair key "$pk" deleted});
      }
      else {
          delete $data{$type}{$name}{solcastapi}{'?IdPair'};
          Log3($name, 3, qq{$name - roofIdentPair: all pair keys deleted});
      }

      writeCacheToFile ($hash, "solcastapi", $scpicache.$name);                # Cache File SolCast API Werte schreiben
      return;
  }

  if ($prop eq 'currentMeterSet') {
      readingsDelete ($hash, "Current_GridConsumption");
      readingsDelete ($hash, "Current_GridFeedIn");
      readingsDelete ($hash, 'currentMeterDev');
      delete $data{$type}{$name}{circular}{'99'}{initdayfeedin};
      delete $data{$type}{$name}{circular}{'99'}{gridcontotal};
      delete $data{$type}{$name}{circular}{'99'}{initdaygcon};
      delete $data{$type}{$name}{circular}{'99'}{feedintotal};
      delete $data{$type}{$name}{current}{gridconsumption};
      delete $data{$type}{$name}{current}{tomorrowconsumption};
      delete $data{$type}{$name}{current}{gridfeedin};
      delete $data{$type}{$name}{current}{consumption};
      delete $data{$type}{$name}{current}{autarkyrate};
      delete $data{$type}{$name}{current}{selfconsumption};
      delete $data{$type}{$name}{current}{selfconsumptionrate};

      writeCacheToFile ($hash, "plantconfig", $plantcfg.$name);                       # Anlagenkonfiguration File schreiben
  }

  if ($prop eq 'currentBatterySet') {
      readingsDelete    ($hash, 'Current_PowerBatIn');
      readingsDelete    ($hash, 'Current_PowerBatOut');
      readingsDelete    ($hash, 'Current_BatCharge');
      readingsDelete    ($hash, 'currentBatteryDev');
      deleteReadingspec ($hash, 'Battery_.*');
      undef @{$data{$type}{$name}{current}{socslidereg}};
      delete $data{$type}{$name}{circular}{'99'}{lastTsMaxSocRchd};
      delete $data{$type}{$name}{circular}{'99'}{nextTsMaxSocChge};
      delete $data{$type}{$name}{circular}{'99'}{initdaybatintot};
      delete $data{$type}{$name}{circular}{'99'}{initdaybatouttot};
      delete $data{$type}{$name}{circular}{'99'}{batintot};
      delete $data{$type}{$name}{circular}{'99'}{batouttot};
      delete $data{$type}{$name}{current}{powerbatout};
      delete $data{$type}{$name}{current}{powerbatin};
      delete $data{$type}{$name}{current}{batcharge};

      writeCacheToFile ($hash, "plantconfig", $plantcfg.$name);                      # Anlagenkonfiguration File schreiben
  }

  if ($prop eq 'currentInverterSet') {
      undef @{$data{$type}{$name}{current}{genslidereg}};
      readingsDelete    ($hash, "Current_PV");
      readingsDelete    ($hash, "currentInverterDev");
      deleteReadingspec ($hash, ".*_PVreal" );
      writeCacheToFile  ($hash, "plantconfig", $plantcfg.$name);                     # Anlagenkonfiguration File schreiben
  }

  if ($prop eq 'consumerPlanning') {                                                 # Verbraucherplanung resetten
      my $c = $paref->{prop1} // "";                                                 # bestimmten Verbraucher setzen falls angegeben

      if ($c) {
          deleteConsumerPlanning ($hash, $c);
      }
      else {
          for my $cs (keys %{$data{$type}{$name}{consumers}}) {
              deleteConsumerPlanning ($hash, $cs);
          }
      }

      writeCacheToFile ($hash, "consumers", $csmcache.$name);                        # Cache File Consumer schreiben
  }

  if ($prop eq 'consumerMaster') {                                                   # Verbraucherhash löschen
      my $c = $paref->{prop1} // "";                                                 # bestimmten Verbraucher setzen falls angegeben

      if ($c) {
          my $calias = ConsumerVal ($hash, $c, "alias", "");
          delete $data{$type}{$name}{consumers}{$c};
          Log3($name, 3, qq{$name - Consumer "$calias" deleted from memory});
      }
      else {
          for my $cs (keys %{$data{$type}{$name}{consumers}}) {
              my $calias = ConsumerVal ($hash, $cs, "alias", "");
              delete $data{$type}{$name}{consumers}{$cs};
              Log3($name, 3, qq{$name - Consumer "$calias" deleted from memory});
          }
      }

      writeCacheToFile ($hash, "consumers", $csmcache.$name);                       # Cache File Consumer schreiben
  }

  createAssociatedWith ($hash);

return;
}

################################################################
#                Setter operatingMemory
#          (Ersatz für Setter writeHistory)
################################################################
sub _setoperatingMemory {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no operation specified for command};

  if ($prop eq 'save') {
      periodicWriteCachefiles ($hash);                                         # Cache File für PV History, PV Circular schreiben
  }

  if ($prop eq 'backup') {
      periodicWriteCachefiles ($hash, 'bckp');                                 # Backup Files erstellen und alte Versionen löschen
  }

  if ($prop =~ /^recover-/xs) {                                                # Sicherung wiederherstellen
      my $file = (split "-", $prop)[1];

      Log3 ($name, 3, "$name - recover saved cache file: $file");

      if ($file =~ /^PVH_/xs) {                                                # Cache File PV History einlesen
          $paref->{cachename} = 'pvhist';
          $paref->{title}     = 'pvHistory';
      }

      if ($file =~ /^PVC_/xs) {                                                # Cache File PV Circular einlesen
          $paref->{cachename} = 'circular';
          $paref->{title}     = 'pvCircular';
      }

      $paref->{file} = "$cachedir/$file";
      _readCacheFile ($paref);

      delete $paref->{file};
      delete $paref->{cachename};
      delete $paref->{title};
  }

return;
}

################################################################
#              Setter clientAction
#      ohne Menüeintrag ! für Aktivität aus Grafik
################################################################
sub _setclientAction {                 ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $opt     = $paref->{opt};
  my $arg     = $paref->{arg};
  my $argsref = $paref->{argsref};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }

  my @args = @{$argsref};

  my $c        = shift @args;                                                 # Consumer Index (Nummer)
  my $evt      = shift @args;                                                 # Readings Event (state wird nicht gesteuert)
  my $action   = shift @args;                                                 # z.B. set, setreading
  my $cname    = shift @args;                                                 # Consumername
  my $tail     = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @args;     ## no critic 'Map blocks' # restliche Befehlsargumente

  Log3 ($name, 4, qq{$name - Client Action received / execute: "$action $cname $tail"});

  if($action eq 'set') {
      CommandSet (undef, "$cname $tail");
      my $async = ConsumerVal ($hash, $c, 'asynchron', 0);
      centralTask ($hash, $evt) if(!$async);                                  # nur wenn Consumer synchron arbeitet direkte Statusabfrage, sonst via Notify
      return;
  }

  if($action eq 'get') {
      if($tail eq 'data') {
          centralTask ($hash, $evt);
          return;
      }
  }

  if($action eq 'setreading') {
      CommandSetReading (undef, "$cname $tail");
  }

  if($action eq 'consumerImmediatePlanning') {
      CommandSet (undef, "$name $action $cname $evt");
      return;
  }

  centralTask ($hash, $evt);

return;
}

################################################################
#                      Setter aiDecTree
################################################################
sub _setaiDecTree {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return;

  if($prop eq 'addInstances') {
      aiAddInstance ($paref);
  }

  if($prop eq 'addRawData') {
      aiAddRawData ($paref);
  }

  if($prop eq 'train') {
      manageTrain ($paref);
  }

return;
}

###############################################################
#                  SolarForecast Get
###############################################################
sub Get {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name = shift @a;
  my $opt  = shift @a;
  my $arg  = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'

  my $type = $hash->{TYPE};

  my @ho   = qw (both
                 both_noHead
                 both_noCons
                 both_noHead_noCons
                 flow
                 flow_noHead
                 flow_noCons
                 flow_noHead_noCons
                 forecast
                 forecast_noHead
                 forecast_noCons
                 forecast_noHead_noCons
                 none
                );

  my @pha  = map {sprintf "%02d", $_} sort {$a<=>$b} keys %{$data{$type}{$name}{pvhist}};
  my @vcm  = map {sprintf "%02d", $_} sort {$a<=>$b} keys %{$data{$type}{$name}{consumers}};

  my $hol  = join ",", @ho;
  my $pvl  = join ",", @pha;
  my $cml  = join ",", @vcm;

  my $getlist = "Unknown argument $opt, choose one of ".
                "valConsumerMaster:#,$cml ".
                "data:noArg ".
                "forecastQualities:noArg ".
                "ftuiFramefiles:noArg ".
                "html:$hol ".
                "nextHours:noArg ".
                "pvCircular:noArg ".
                "pvHistory:#,$pvl ".
                "rooftopData:noArg ".
                "solApiData:noArg ".
                "valCurrent:noArg "
                ;

  ## KI spezifische Getter
  ##########################
  if (isPrepared4AI ($hash)) {
       $getlist .= "valDecTree:aiRawData,aiRuleStrings ";
  }

  return if((controller($name))[1] || (controller($name))[2]);

  my $params = {
      hash  => $hash,
      name  => $name,
      type  => $type,
      opt   => $opt,
      arg   => $arg,
      t     => time,
      date  => (strftime "%Y-%m-%d", localtime(time)),
      debug => getDebug ($hash),
      lang  => getLang  ($hash)
  };

  if($hget{$opt} && defined &{$hget{$opt}{fn}}) {
      my $ret = q{};

      if (!$hash->{CREDENTIALS} && $hget{$opt}{needcred}) {
          return qq{Credentials for "$opt" are not set. Please save the the credentials with the appropriate Set command."};
      }

      $params->{force} = 1 if($opt eq 'rooftopData');                       # forcierter (manueller) Abruf SolCast API

      $ret = &{$hget{$opt}{fn}} ($params);
      return $ret;
  }

return $getlist;
}

################################################################
#                Getter roofTop data
################################################################
sub _getRoofTopData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $hash->{NAME};

  if($hash->{MODEL} eq 'SolCastAPI') {
      __getSolCastData ($paref);
      return;
  }
  elsif ($hash->{MODEL} eq 'ForecastSolarAPI') {
      __getForecastSolarData ($paref);
      return;
  }
  elsif ($hash->{MODEL} eq 'DWD') {
      my $ret = __getDWDSolarData ($paref);
      return $ret;
  }
  elsif ($hash->{MODEL} eq 'VictronKiAPI') {
      my $ret = __getVictronSolarData ($paref);
      return $ret;
  }

return "$hash->{NAME} ist not model DWD, SolCastAPI or ForecastSolarAPI";
}

################################################################
#                Abruf SolCast roofTop data
################################################################
sub __getSolCastData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $force = $paref->{force} // 0;
  my $t     = $paref->{t}     // time;
  my $debug = $paref->{debug};
  my $lang  = $paref->{lang};

  my $msg;
  if($ctzAbsent) {
      $msg = qq{The library FHEM::Utility::CTZ is missing. Please update FHEM completely.};
      Log3 ($name, 1, "$name - ERROR - $msg");
      return $msg;
  }

  my $rmf = reqModFail();
  if($rmf) {
      $msg = "You have to install the required perl module: ".$rmf;
      Log3 ($name, 1, "$name - ERROR - $msg");
      return $msg;
  }

  ## statische SolCast API Kennzahlen
  ## (solCastAPIcallMultiplier, todayMaxAPIcalls) berechnen
  ##########################################################
  my %mx;
  my $maxcnt = 1;

  my $type = $paref->{type};

  for my $pk (keys %{$data{$type}{$name}{solcastapi}{'?IdPair'}}) {
      my $apikey = SolCastAPIVal ($hash, '?IdPair', $pk, 'apikey', '');
      next if(!$apikey);

      $mx{$apikey} += 1;
      $maxcnt       = $mx{$apikey} if(!$maxcnt || $mx{$apikey} > $maxcnt);
  }

  my $apimaxreq = AttrVal ($name, 'ctrlSolCastAPImaxReq', $apimaxreqdef);
  my $madc      = sprintf "%.0f", ($apimaxreq / $maxcnt);                                          # max. tägliche Anzahl API Calls
  my $mpk       = $maxcnt;                                                                         # Requestmultiplikator

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{solCastAPIcallMultiplier}  = $mpk;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayMaxAPIcalls}          = $madc;

  #########################

  if (!$force) {                                                                                   # regulärer SolCast API Abruf
      my $trc       = SolCastAPIVal ($hash, '?All', '?All', 'todayRemainingAPIcalls', $madc);
      my $etxt      = $hqtxt{bnsas}{$lang};
      $etxt         =~ s{<WT>}{($leadtime/60)}eg;

      if ($trc <= 0) {
          readingsSingleUpdate($hash, 'nextSolCastCall', $etxt, 1);
          return qq{SolCast free daily limit is used up};
      }

      my $date   = $paref->{date};
      my $srtime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunRise", '23:59').':59');
      my $sstime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunSet",  '00:00').':00');

      if ($t < $srtime - $leadtime || $t > $sstime + $lagtime) {
          readingsSingleUpdate($hash, 'nextSolCastCall', $etxt, 1);
          return "The current time is not between sunrise minus ".($leadtime/60)." minutes and sunset";
      }

      my $lrt    = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_timestamp',            0);
      my $apiitv = SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval',     $solapirepdef);

      if ($lrt && $t < $lrt + $apiitv) {
          my $rt = $lrt + $apiitv - $t;
          return qq{The waiting time to the next SolCast API call has not expired yet. The remaining waiting time is $rt seconds};
      }
  }

  if($debug =~ /apiCall/x) {
      Log3 ($name, 1, "$name DEBUG> SolCast API Call - max possible daily API requests: $apimaxreq");
      Log3 ($name, 1, "$name DEBUG> SolCast API Call - Requestmultiplier: $mpk");
      Log3 ($name, 1, "$name DEBUG> SolCast API Call - possible daily API Calls: $madc");
  }

  $paref->{allstrings} = ReadingsVal ($name, 'inverterStrings', '');
  $paref->{firstreq}   = 1;                                                                   # 1. Request, V 0.80.18

  __solCast_ApiRequest ($paref);

return;
}

################################################################################################
#                SolCast Api Request
#
# noch testen und einbauen Abruf aktuelle Daten ohne Rooftops
# (aus https://www.solarquotes.com.au/blog/how-to-use-solcast/):
# https://api.solcast.com.au/pv_power/estimated_actuals?longitude=12.067722&latitude=51.285272&
# capacity=5130&azimuth=180&tilt=30&format=json&api_key=....
#
################################################################################################
sub __solCast_ApiRequest {
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $allstrings = $paref->{allstrings};                                # alle Strings
  my $debug      = $paref->{debug};

  if(!$allstrings) {                                                    # alle Strings wurden abgerufen
      writeCacheToFile ($hash, 'solcastapi', $scpicache.$name);         # Cache File SolCast API Werte schreiben
      return;
  }

  my $string;
  ($string, $allstrings) = split ",", $allstrings, 2;

  my $rft    = ReadingsVal ($name, "moduleRoofTops", "");
  my ($a,$h) = parseParams ($rft);

  my $pk     = $h->{$string} // q{};
  my $roofid = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'rtid',   '');
  my $apikey = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'apikey', '');

  if(!$roofid || !$apikey) {
      my $err = qq{The roofIdentPair "$pk" of String "$string" has no Rooftop-ID and/or SolCast-API key assigned !};
      singleUpdateState ( {hash => $hash, state => $err, evt => 1} );
      return $err;
  }

  my $url = "https://api.solcast.com.au/rooftop_sites/".
            $roofid.
            "/forecasts?format=json".
            "&hours=72".                                               # Forum:#134226 -> Abruf 72h statt 48h
            "&api_key=".
            $apikey;

  debugLog ($paref, "apiProcess|apiCall", qq{Request SolCast API for string "$string": $url});

  my $caller = (caller(0))[3];                                                                        # Rücksprungmarke

  my $param = {
      url        => $url,
      timeout    => 30,
      hash       => $hash,
      name       => $name,
      type       => $paref->{type},
      debug      => $debug,
      caller     => \&$caller,
      stc        => [gettimeofday],
      allstrings => $allstrings,
      string     => $string,
      lang       => $paref->{lang},
      firstreq   => $paref->{firstreq},
      method     => "GET",
      callback   => \&__solCast_ApiResponse
  };

  if($debug =~ /apiCall/x) {
      $param->{loglevel} = 1;
  }

  HttpUtils_NonblockingGet ($param);

return;
}

###############################################################
#                  SolCast Api Response
###############################################################
sub __solCast_ApiResponse {
  my $paref      = shift;
  my $err        = shift;
  my $myjson     = shift;

  my $hash        = $paref->{hash};
  my $name        = $paref->{name};
  my $caller      = $paref->{caller};
  my $string      = $paref->{string};
  my $allstrings  = $paref->{allstrings};
  my $stc         = $paref->{stc};                                                                          # Startzeit API Abruf
  my $lang        = $paref->{lang};
  my $debug       = $paref->{debug};
  my $type        = $paref->{type};

  $paref->{t}     = time;

  my $msg;

  my $sta = [gettimeofday];                                                                                # Start Response Verarbeitung

  if ($err ne "") {
      $msg = 'SolCast API server response: '.$err;

      Log3 ($name, 1, "$name - $msg");

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $err;

      singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
      $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
      $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

      return;
  }
  elsif ($myjson ne "") {                                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
      my ($success) = evaljson($hash, $myjson);

      if(!$success) {
          $msg = 'ERROR - invalid SolCast API server response';

          Log3 ($name, 1, "$name - $msg");

          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          return;
      }

      my $jdata = decode_json ($myjson);

      debugLog ($paref, "apiProcess", qq{SolCast API server response for string "$string":\n}. Dumper $jdata);

      ## bei Überschreitung Limit kommt:
      ####################################
      #  'response_status' => {
      #                         'message' => 'You have exceeded your free daily limit.',
      #                         'errors' => [],
      #                         'error_code' => 'TooManyRequests'
      #                       }

      if (defined $jdata->{'response_status'}) {
          $msg = 'SolCast API server response: '.$jdata->{'response_status'}{'message'};

          Log3 ($name, 3, "$name - $msg");

          ___setSolCastAPIcallKeyData ($paref);

          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $jdata->{'response_status'}{'message'};

          if ($jdata->{'response_status'}{'error_code'} eq 'TooManyRequests') {
              $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIrequests} = 0;
          }

          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          if($debug =~ /apiProcess|apiCall/x) {
              my $apimaxreq = AttrVal ($name, 'ctrlSolCastAPImaxReq', $apimaxreqdef);

              Log3 ($name, 1, "$name DEBUG> SolCast API Call - response status: ".$jdata->{'response_status'}{'message'});
              Log3 ($name, 1, "$name DEBUG> SolCast API Call - todayRemainingAPIrequests: ".SolCastAPIVal($hash, '?All', '?All', 'todayRemainingAPIrequests', $apimaxreq));
          }

          return;
      }

      my $k = 0;
      my ($period,$starttmstr);

      my $perc = AttrVal ($name, 'affectSolCastPercentile', 50);                                         # das gewählte zu nutzende Percentil

      debugLog ($paref, "apiProcess", qq{SolCast API used percentile: }. $perc);

      $perc = q{} if($perc == 50);

      while ($jdata->{'forecasts'}[$k]) {                                                                # vorhandene Startzeiten Schlüssel im SolCast API Hash löschen
          my $petstr          = $jdata->{'forecasts'}[$k]{'period_end'};
          ($err, $starttmstr) = ___convPendToPstart ($name, $lang, $petstr);

          if ($err) {
              Log3 ($name, 1, "$name - $err");

              singleUpdateState ( {hash => $hash, state => $err, evt => 1} );
              return;
          }

          if(!$k && $petstr =~ /T\d{2}:00/xs) {                                                          # spezielle Behandlung ersten Datensatz wenn period_end auf volle Stunde fällt (es fehlt dann der erste Teil der Stunde)
              $period   = $jdata->{'forecasts'}[$k]{'period'};                                           # -> dann bereits beim letzten Abruf gespeicherte Daten der aktuellen Stunde durch 2 teilen damit
              $period   =~ s/.*(\d\d).*/$1/;                                                             # -> die neuen Daten (in dem Fall nur die einer halben Stunde) im nächsten Schritt addiert werden

              my $est50 = SolCastAPIVal ($hash, $string, $starttmstr, 'pv_estimate50', 0) / (60/$period);
              $data{$type}{$name}{solcastapi}{$string}{$starttmstr}{pv_estimate50} = $est50 if($est50);

              $k++;
              next;
          }

          delete $data{$type}{$name}{solcastapi}{$string}{$starttmstr};

          $k++;
      }

      $k = 0;

      while ($jdata->{'forecasts'}[$k]) {
          if(!$jdata->{'forecasts'}[$k]{'pv_estimate'.$perc}) {                                              # keine PV Prognose -> Datensatz überspringen -> Verarbeitungszeit sparen
              $k++;
              next;
          }

          my $petstr          = $jdata->{'forecasts'}[$k]{'period_end'};
          ($err, $starttmstr) = ___convPendToPstart ($name, $lang, $petstr);

          my $pvest50         = $jdata->{'forecasts'}[$k]{'pv_estimate'.$perc};

          $period             = $jdata->{'forecasts'}[$k]{'period'};
          $period             =~ s/.*(\d\d).*/$1/;

          if($debug =~ /apiProcess/x) {                                                                      # nur für Debugging
              if (exists $data{$type}{$name}{solcastapi}{$string}{$starttmstr}) {
                  Log3 ($name, 1, qq{$name DEBUG> SolCast API Hash - Start Date/Time: }. $starttmstr);
                  Log3 ($name, 1, qq{$name DEBUG> SolCast API Hash - pv_estimate50 add: }.(sprintf "%.0f", ($pvest50 * ($period/60) * 1000)).qq{, contains already: }.SolCastAPIVal ($hash, $string, $starttmstr, 'pv_estimate50', 0));
              }
          }

          $data{$type}{$name}{solcastapi}{$string}{$starttmstr}{pv_estimate50} += sprintf "%.0f", ($pvest50 * ($period/60) * 1000);

          $k++;
      }
  }

  Log3 ($name, 4, qq{$name - SolCast API answer received for string "$string"});

  ___setSolCastAPIcallKeyData ($paref);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = 'success';

  my $param = {
      hash       => $hash,
      name       => $name,
      type       => $type,
      debug      => $debug,
      allstrings => $allstrings,
      lang       => $lang
  };

  $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
  $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

return &$caller($param);
}

###############################################################
#      SolCast API: berechne Startzeit aus 'period_end'
###############################################################
sub ___convPendToPstart {
  my $name   = shift;
  my $lang   = shift;
  my $petstr = shift;

  my $cpar = {
      name      => $name,
      pattern   => '%Y-%m-%dT%H:%M:%S',
      dtstring  => $petstr,
      tzcurrent => 'UTC',
      tzconv    => 'local',
      writelog  => 0
  };

  my ($err, $cpets) = convertTimeZone ($cpar);

  if ($err) {
      $err = 'ERROR while converting time zone: '.$err;
      return $err;
  }

  my ($cdatest,$ctimestr) = split " ", $cpets;                                            # Datumstring YYYY-MM-TT / Zeitstring hh:mm:ss
  my ($chrst,$cminutstr)  = split ":", $ctimestr;
  $chrst                  = int ($chrst);

  if ($cminutstr eq '00') {                                                               # Zeit/Periodenkorrektur
      $chrst -= 1;

      if($chrst < 0) {
          my $nt     = (timestringToTimestamp ($cdatest.' 00:00:00')) - 3600;
          $nt        = (timestampToTimestring ($nt, $lang))[1];
          ($cdatest) = split " ", $nt;
          $chrst     = 23;
      }
  }

  my $starttmstr = $cdatest." ".(sprintf "%02d", $chrst).":00:00";                        # Startzeit von pv_estimate

return ($err, $starttmstr);
}

################################################################
#  Kennzahlen des letzten Abruf SolCast API setzen
#  $t - Unix Timestamp
################################################################
sub ___setSolCastAPIcallKeyData {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $lang  = $paref->{lang};
  my $debug = $paref->{debug};
  my $t     = $paref->{t} // time;

  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];   # letzte Abrufzeit
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;                                       # letzter Abrufzeitstempel

  my $apimaxreq = AttrVal       ($name, 'ctrlSolCastAPImaxReq',         $apimaxreqdef);
  my $mpl       = SolCastAPIVal ($hash, '?All', '?All', 'solCastAPIcallMultiplier', 1);
  my $ddc       = SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIcalls',        0);

  $ddc         += 1 if($paref->{firstreq});
  my $drc       = SolCastAPIVal ($hash, '?All', '?All', 'todayMaxAPIcalls', $apimaxreq / $mpl) - $ddc;                 # verbleibende SolCast API Calls am aktuellen Tag
  $drc          = 0 if($drc < 0);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests} = $ddc * $mpl;

  my $drr       = $apimaxreq - ($mpl * $ddc);
  $drr          = 0 if($drr < 0);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIrequests} = $drr;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIcalls}    = $drc;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIcalls}         = $ddc;

  debugLog ($paref, "apiProcess|apiCall", "SolCast API Call - done API Calls: $ddc");

  ## Berechnung des optimalen Request Intervalls
  ################################################
  if (AttrVal($name, 'ctrlSolCastAPIoptimizeReq', 0)) {
      my $date   = strftime "%Y-%m-%d", localtime($t);
      my $sunset = $date.' '.ReadingsVal ($name, "Today_SunSet", '00:00').':00';
      my $sstime = timestringToTimestamp ($sunset);
      my $dart   = $sstime - $t;                                                                                      # verbleibende Sekunden bis Sonnenuntergang
      $dart      = 0 if($dart < 0);
      $drc      += 1;

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $solapirepdef;
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = int ($dart / $drc) if($dart && $drc);

      debugLog ($paref, "apiProcess|apiCall", "SolCast API Call - Sunset: $sunset, remain Sec to Sunset: $dart, new interval: ".SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval', $solapirepdef));
  }
  else {
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $solapirepdef;
  }

  ####

  my $apiitv = SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval', $solapirepdef);

  if($debug =~ /apiProcess|apiCall/x) {
      Log3 ($name, 1, "$name DEBUG> SolCast API Call - remaining API Calls: ".($drc - 1));
      Log3 ($name, 1, "$name DEBUG> SolCast API Call - next API Call: ".(timestampToTimestring ($t + $apiitv, $lang))[0]);
  }

  readingsSingleUpdate ($hash, 'nextSolCastCall', $hqtxt{after}{$lang}.' '.(timestampToTimestring ($t + $apiitv, $lang))[0], 1);

return;
}

################################################################
#             Abruf ForecastSolar-API data
################################################################
sub __getForecastSolarData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $force = $paref->{force} // 0;
  my $t     = $paref->{t}     // time;
  my $lang  = $paref->{lang};

  if (!$force) {                                                                                   # regulärer API Abruf
      my $etxt      = $hqtxt{bnsas}{$lang};
      $etxt         =~ s{<WT>}{($leadtime/60)}eg;

      my $date   = strftime "%Y-%m-%d", localtime($t);
      my $srtime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunRise", '23:59').':59');
      my $sstime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunSet",  '00:00').':00');

      if ($t < $srtime - $leadtime || $t > $sstime + $lagtime) {
          readingsSingleUpdate($hash, 'nextSolCastCall', $etxt, 1);
          return "The current time is not between sunrise minus ".($leadtime/60)." minutes and sunset";
      }

      my $lrt    = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_timestamp',            0);
      my $apiitv = SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval',     $forapirepdef);

      if ($lrt && $t < $lrt + $apiitv) {
          my $rt = $lrt + $apiitv - $t;
          return qq{The waiting time to the next SolCast API call has not expired yet. The remaining waiting time is $rt seconds};
      }
  }

  $paref->{allstrings} = ReadingsVal($name, 'inverterStrings', '');

  __forecastSolar_ApiRequest ($paref);

return;
}

################################################################################################
#                ForecastSolar Api Request
#
#  Quelle Seite: https://doc.forecast.solar/api:estimate
#  Aufruf:       https://api.forecast.solar/estimate/:lat/:lon/:dec/:az/:kwp
#  Beispiel:     https://api.forecast.solar/estimate/51.285272/12.067722/45/S/5.13
#
#  Locate Check: https://api.forecast.solar/check/:lat/:lon
#  Docku:        https://doc.forecast.solar/api
#
# :!:   Please note that the forecasts are updated at the earliest every 15 min.
#       due to the weather data used, so it makes no sense to query more often than every 15 min.!
#
# :!:   If you get an 404 Page not found please always double check your URL.
#       The API ist very strict configured to reject maleformed queries as early as possible to
#       minimize server load!
#
# :!:   Each quarter (1st of month around midnight UTC) there is a scheduled maintenance planned.
#       You will get then a HTTP code 503 as response.
#
################################################################################################
sub __forecastSolar_ApiRequest {
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $allstrings = $paref->{allstrings};                                # alle Strings
  my $debug      = $paref->{debug};

  if(!$allstrings) {                                                    # alle Strings wurden abgerufen
      writeCacheToFile ($hash, 'solcastapi', $scpicache.$name);         # Cache File API Werte schreiben
      return;
  }

  my $string;
  ($string, $allstrings) = split ",", $allstrings, 2;

  my ($set, $lat, $lon) = locCoordinates();

  if(!$set) {
      my $err = qq{the attribute 'latitude' and/or 'longitude' in global device is not set};
      singleUpdateState ( {hash => $hash, state => $err, evt => 1} );
      return $err;
  }

  my $tilt = StringVal ($hash, $string, 'tilt',   '<unknown>');
  my $az   = StringVal ($hash, $string, 'azimut', '<unknown>');
  my $peak = StringVal ($hash, $string, 'peak',   '<unknown>');

  my $url = "https://api.forecast.solar/estimate/watthours/period/".
            $lat."/".
            $lon."/".
            $tilt."/".
            $az."/".
            $peak;

  debugLog ($paref, "apiCall", qq{ForecastSolar API Call - Request for string "$string":\n$url});

  my $caller = (caller(0))[3];                                                                        # Rücksprungmarke

  my $param = {
      url        => $url,
      timeout    => 30,
      hash       => $hash,
      name       => $name,
      debug      => $debug,
      header     => 'Accept: application/json',
      caller     => \&$caller,
      stc        => [gettimeofday],
      allstrings => $allstrings,
      string     => $string,
      lang       => $paref->{lang},
      method     => "GET",
      callback   => \&__forecastSolar_ApiResponse
  };

  if($debug =~ /apiCall/x) {
      $param->{loglevel} = 1;
  }

  HttpUtils_NonblockingGet ($param);

return;
}

###############################################################
#                  ForecastSolar API Response
###############################################################
sub __forecastSolar_ApiResponse {
  my $paref      = shift;
  my $err        = shift;
  my $myjson     = shift;

  my $hash        = $paref->{hash};
  my $name        = $paref->{name};
  my $caller      = $paref->{caller};
  my $string      = $paref->{string};
  my $allstrings  = $paref->{allstrings};
  my $stc         = $paref->{stc};                                                                          # Startzeit API Abruf
  my $lang        = $paref->{lang};
  my $debug       = $paref->{debug};
  my $type        = $hash->{TYPE};

  my $t           = time;
  $paref->{t}     = $t;

  my $msg;

  my $sta = [gettimeofday];                                                                                # Start Response Verarbeitung

  if ($err ne "") {
      $msg = 'ForecastSolar API server response: '.$err;

      Log3 ($name, 1, "$name - $msg");

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $err;

      singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
      $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
      $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

      return;
  }
  elsif ($myjson ne "") {                                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
      my ($success) = evaljson($hash, $myjson);

      if(!$success) {
          $msg = 'ERROR - invalid ForecastSolar API server response';

          Log3 ($name, 1, "$name - $msg");

          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          return;
      }

      my $jdata = decode_json ($myjson);

      debugLog ($paref, "apiProcess", qq{ForecastSolar API Call - response for string "$string":\n}. Dumper $jdata);

      ## bei Überschreitung des Stundenlimit kommt:
      ###############################################
      # message -> code 429                                        (sonst 0)
      # message -> type error                                      (sonst 'success')
      # message -> text Rate limit for API calls reached.          (sonst leer)
      # message -> ratelimit ->  period    3600
      #                      ->  limit     12
      #                      ->  retry-at  2023-05-27T11:01:53+02:00  (= lokale Zeit)

      if ($jdata->{'message'}{'code'}) {
          $msg = "ForecastSolar API server ERROR response: $jdata->{'message'}{'text'} ($jdata->{'message'}{'code'})";

          Log3 ($name, 3, "$name - $msg");

          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message}        = $jdata->{'message'}{'text'};
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_code}           = $jdata->{'message'}{'code'};
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];                # letzte Abrufzeit
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;

          if (defined $jdata->{'message'}{'ratelimit'}{'remaining'}) {
              $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{requests_remaining} = $jdata->{'message'}{'ratelimit'}{'remaining'};          # verbleibende Requests in Periode
          }
          else {
              delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{requests_remaining};                                                   # verbleibende Requests unbestimmt
          }

          if($debug =~ /apiCall/x) {
              Log3 ($name, 1, "$name DEBUG> ForecastSolar API Call - $msg");
              Log3 ($name, 1, "$name DEBUG> ForecastSolar API Call - limit period: ".$jdata->{'message'}{'ratelimit'}{'period'});
              Log3 ($name, 1, "$name DEBUG> ForecastSolar API Call - limit: ".$jdata->{'message'}{'ratelimit'}{'limit'});
          }

          my $rtyat = timestringFormat ($jdata->{'message'}{'ratelimit'}{'retry-at'});

          if ($rtyat) {
              my $rtyatts = timestringToTimestamp ($rtyat);

              $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{retryat_time}      = $rtyat;
              $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{retryat_timestamp} = $rtyatts;

              debugLog ($paref, "apiCall", "ForecastSolar API Call - retry at: ".$rtyat." ($rtyatts)");
          }

          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          ___setForeCastAPIcallKeyData ($paref);

          return;
      }

      my $rt  = timestringFormat      ($jdata->{'message'}{'info'}{'time'});
      my $rts = timestringToTimestamp ($rt);

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = $rt;                                                    # letzte Abrufzeit
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $rts;                                                   # letzter Abrufzeitstempel

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message}        = $jdata->{'message'}{'type'};
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_code}           = $jdata->{'message'}{'code'};
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{requests_remaining}      = $jdata->{'message'}{'ratelimit'}{'remaining'};          # verbleibende Requests in Periode
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{requests_limit_period}   = $jdata->{'message'}{'ratelimit'}{'period'};             # Requests Limit Periode
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{requests_limit}          = $jdata->{'message'}{'ratelimit'}{'limit'};              # Requests Limit in Periode
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{place}                   = encode ("utf8", $jdata->{'message'}{'info'}{'place'});

      if($debug =~ /apiCall/x) {
          Log3 ($name, 1, qq{$name DEBUG> ForecastSolar API Call - server response for PV string "$string"});
          Log3 ($name, 1, "$name DEBUG> ForecastSolar API Call - request time: ".      $rt." ($rts)");
          Log3 ($name, 1, "$name DEBUG> ForecastSolar API Call - requests remaining: ".$jdata->{'message'}{'ratelimit'}{'remaining'});
          Log3 ($name, 1, "$name DEBUG> ForecastSolar API Call - status: ".            $jdata->{'message'}{'type'}." ($jdata->{'message'}{'code'})");
      }

      for my $k (sort keys %{$jdata->{'result'}}) {                                   # Vorhersagedaten in Hash eintragen
          my $kts        = (timestringToTimestamp ($k)) - 3600;                       # Endezeit der Periode auf Startzeit umrechnen
          my $starttmstr = (timestampToTimestring ($kts, $lang))[3];

          $data{$type}{$name}{solcastapi}{$string}{$starttmstr}{pv_estimate50} = $jdata->{'result'}{$k};

          debugLog ($paref, "apiProcess", "ForecastSolar API Call - PV estimate: ".$starttmstr.' => '.$jdata->{'result'}{$k}.' Wh');
      }
  }

  Log3 ($name, 4, qq{$name - ForecastSolar API answer received for string "$string"});

  ___setForeCastAPIcallKeyData ($paref);

  my $param = {
      hash       => $hash,
      name       => $name,
      debug      => $debug,
      allstrings => $allstrings,
      lang       => $lang
  };

  $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
  $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

return &$caller($param);
}

################################################################
#  Kennzahlen des letzten Abruf ForecastSolar API setzen
################################################################
sub ___setForeCastAPIcallKeyData {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $lang  = $paref->{lang};
  my $debug = $paref->{debug};
  my $t     = $paref->{t} // time;

  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  my $rts = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_timestamp', 0);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests} += 1;

  my $asc = CurrentVal    ($hash, 'allstringscount', 1);                                    # Anzahl der Strings
  my $dar = SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIrequests', 1);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIcalls} = $dar / $asc;

  ## Berechnung des optimalen Request Intervalls
  ################################################
  my $snum   = scalar (split ",", ReadingsVal($name, 'inverterStrings',   'Dummy'));        # Anzahl der Strings (mindestens ein String als Dummy)
  my $period = SolCastAPIVal ($hash, '?All', '?All', 'requests_limit_period', 3600);        # Requests Limit Periode
  my $limit  = SolCastAPIVal ($hash, '?All', '?All', 'requests_limit',          12);        # Request Limit in Periode

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $forapirepdef;

  my $interval = int ($period / ($limit / $snum));
  $interval    = 900 if($interval < 900);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $interval;

  ####

  my $apiitv  = SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval', $forapirepdef);
  my $rtyatts = SolCastAPIVal ($hash, '?All', '?All', 'retryat_timestamp',  0);
  my $smt     = q{};

  if ($rtyatts && $rtyatts > $t) {                                                          # Zwangswartezeit durch API berücksichtigen
      $apiitv = $rtyatts - $t;
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $apiitv;
      $smt    = '(forced waiting time)';
  }

  readingsSingleUpdate ($hash, 'nextSolCastCall', $hqtxt{after}{$lang}.' '.(timestampToTimestring ($t + $apiitv, $lang))[0].' '.$smt, 1);

return;
}

################################################################
#   Abruf DWD Strahlungsdaten und Rohdaten ohne Korrektur
#   speichern in solcastapi Hash
################################################################
sub __getDWDSolarData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $date  = $paref->{date};                                                                  # aktueller Tag "YYYY-MM-DD"
  my $t     = $paref->{t}     // time;
  my $lang  = $paref->{lang};

  my $type  = $hash->{TYPE};

  my $raname = ReadingsVal ($name, "currentRadiationAPI", "");                                 # Radiation Forecast API
  return if(!$raname || !$defs{$raname});

  my $stime   = $date.' 00:00:00';                                                             # Startzeit Soll Übernahmedaten
  my $sts     = timestringToTimestamp ($stime);
  my @strings = sort keys %{$data{$type}{$name}{strings}};
  my $ret     = q{};

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];                # letzte Abrufzeit
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests}   += 1;

  debugLog ($paref, "apiCall", "DWD API - collect DWD Radiation data with start >$stime<- device: $raname =>");

  for my $num (0..47) {
      my $dateTime = strftime "%Y-%m-%d %H:%M:00", localtime($sts + (3600 * $num));            # laufendes Datum ' ' Zeit
      my $runh     = int strftime "%H",            localtime($sts + (3600 * $num) + 3600);     # laufende Stunde in 24h format (00-23), DWD liefert Rad1h zum Ende der Stunde - Modul benutzt die Startzeit
      my ($fd,$fh) = _calcDayHourMove (0, $num);

      next if($fh == 24);

      my $stime = ReadingsVal ($raname, "fc${fd}_${runh}_time",      0);
      my $rad   = ReadingsVal ($raname, "fc${fd}_${runh}_Rad1h", undef);

      if (!defined $rad) {
          $ret                                                              = "The reading 'fc${fd}_${runh}_Rad1h' doesn't exist. Check the device $raname!";
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $ret;

          debugLog ($paref, "apiCall", "DWD API - ERROR - got no data of starttime: $dateTime. ".$ret);

          $rad = 0;
      }
      else {
          debugLog ($paref, "apiCall", "DWD API - got data -> starttime: $dateTime, reading: fc${fd}_${runh}_Rad1h, rad: $rad");
      }

      $data{$type}{$name}{solcastapi}{'?All'}{$dateTime}{Rad1h} = $rad;

      for my $string (@strings) {                                                              # für jeden String der Config ..
          my $peak = $data{$type}{$name}{strings}{$string}{peak};                              # String Peak (kWp)
          $peak   *= 1000;                                                                     # kWp in Wp umrechnen
          my $ta   = $data{$type}{$name}{strings}{$string}{tilt};                              # Neigungswinkel Solarmodule
          my $dir  = $data{$type}{$name}{strings}{$string}{dir};                               # Ausrichtung der Solarmodule

          my $af = $hff{$ta}{$dir} / 100;                                                      # Flächenfaktor: http://www.ing-büro-junge.de/html/photovoltaik.html
          my $pv = sprintf "%.1f", ($rad * $af * $kJtokWh * $peak * $prdef);

          debugLog ($paref, "apiProcess", "DWD API - PV estimate String >$string< => $pv Wh");

          $data{$type}{$name}{solcastapi}{$string}{$dateTime}{pv_estimate50} = $pv;
      }
  }

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = 'success' if(!$ret);

return;
}

################################################################
#                Abruf Victron VRM API Forecast
################################################################
sub __getVictronSolarData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $force = $paref->{force} // 0;
  my $t     = $paref->{t}     // time;
  my $lang  = $paref->{lang};

  my $lrt    = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_timestamp', 0);
  my $apiitv = $vrmapirepdef;

  if (!$force) {
      if ($lrt && $t < $lrt + $apiitv) {
          my $rt = $lrt + $apiitv - $t;
          return qq{The waiting time to the next SolCast API call has not expired yet. The remaining waiting time is $rt seconds};
      }
  }

  readingsSingleUpdate ($hash, 'nextSolCastCall', $hqtxt{after}{$lang}.' '.(timestampToTimestring ($t + $apiitv, $lang))[0], 1);

  __VictronVRM_ApiRequestLogin ($paref);

return;
}

################################################################
#                Victron VRM API Login
# https://vrm-api-docs.victronenergy.com/#/
################################################################
sub __VictronVRM_ApiRequestLogin {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $debug = $paref->{debug};
  my $type  = $paref->{type};

  my $url   = 'https://vrmapi.victronenergy.com/v2/auth/login';

  debugLog ($paref, "apiProcess|apiCall", qq{Request VictronVRM API Login: $url});

  my $caller = (caller(0))[3];                                                     # Rücksprungmarke

  my ($user, $pwd, $idsite);

  my $serial = SolCastAPIVal ($hash, '?VRM', '?API', 'credentials', '');

  if ($serial) {
      my $h   = eval { thaw (assemble ($serial)) };                                # Deserialisierung
      $user   = $h->{user}   // q{};
      $pwd    = $h->{pwd}    // q{};
      $idsite = $h->{idsite} // q{};

      debugLog ($paref, "apiCall", qq{Used credentials for Login: user->$user, pwd->$pwd, idsite->$idsite});
  }
  else {
      my $msg = "Victron VRM API credentials are not set or couldn't be decrypted. Use 'set $name vrmCredentials' to set it.";
      Log3              ($name, 2, "$name - $msg");
      singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $msg;
      return;
  }

  my $param = {
      url        => $url,
      timeout    => 30,
      hash       => $hash,
      name       => $name,
      type       => $paref->{type},
      stc        => [gettimeofday],
      debug      => $debug,
      caller     => \&$caller,
      lang       => $paref->{lang},
      idsite     => $idsite,
      header     => { "Content-Type" => "application/json" },
      data       => qq({ "username": "$user",  "password": "$pwd" }),
      method     => 'POST',
      callback   => \&__VictronVRM_ApiResponseLogin
  };

  if($debug =~ /apiCall/x) {
      $param->{loglevel} = 1;
  }

  HttpUtils_NonblockingGet ($param);

return;
}

###############################################################
#                  Victron VRM API Login Response
###############################################################
sub __VictronVRM_ApiResponseLogin {
  my $paref  = shift;
  my $err    = shift;
  my $myjson = shift;

  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $type   = $paref->{type};
  my $caller = $paref->{caller};
  my $stc    = $paref->{stc};
  my $lang   = $paref->{lang};
  my $debug  = $paref->{debug};

  my $msg;
  my $t   = time;
  my $sta = [gettimeofday];                                                                                # Start Response Verarbeitung

  if ($err ne "") {
      $msg = 'Victron VRM API error response: '.$err;
      Log3              ($name, 1, "$name - $msg");
      singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $err;
      $data{$type}{$name}{current}{runTimeLastAPIProc}                  = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
      $data{$type}{$name}{current}{runTimeLastAPIAnswer}                = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

      return;
  }
  elsif ($myjson ne "") {                                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
      my ($success) = evaljson($hash, $myjson);

      if(!$success) {
          $msg = 'ERROR - invalid Victron VRM API response';
          Log3              ($name, 1, "$name - $msg");
          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          return;
      }

      my $jdata = decode_json ($myjson);

      if (defined $jdata->{'error_code'}) {
          $msg = 'Victron VRM API error_code response: '.$jdata->{'error_code'};
          Log3              ($name, 3, "$name - $msg");
          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message}        = $jdata->{'error_code'};
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];  # letzte Abrufzeit
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;

          if($debug =~ /apiProcess|apiCall/x) {
              Log3 ($name, 1, "$name DEBUG> SolCast API Call - error_code: ".$jdata->{'error_code'});
              Log3 ($name, 1, "$name DEBUG> SolCast API Call - errors: "    .$jdata->{'errors'});
          }

          return;
      }
      else {
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message}        = 'success';
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{idUser}                  = $jdata->{'idUser'};
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{verification_mode}       = $jdata->{'verification_mode'};
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];                # letzte Abrufzeit
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{token}                   = 'got successful at '.SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_time', '-');;

          debugLog ($paref, "apiProcess", qq{Victron VRM API response Login:\n}. Dumper $jdata);

          $paref->{token} = $jdata->{'token'};

          __VictronVRM_ApiRequestForecast ($paref);
      }
  }

return;
}

################################################################################################
#                Victron VRM API Forecast Data
# https://vrm-api-docs.victronenergy.com/#/
# https://vrmapi.victronenergy.com/v2/installations/<instalation id>/stats?type=forecast&interval=hours&start=<start date and time>&end=<end date and time>
################################################################################################
sub __VictronVRM_ApiRequestForecast {
  my $paref  = shift;

  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $token  = $paref->{token};
  my $debug  = $paref->{debug};
  my $lang   = $paref->{lang};
  my $idsite = $paref->{idsite};

  my $tstart = time;
  my $tend   = time + 259200;                                                     # 172800 = 2 Tage

  my $url = "https://vrmapi.victronenergy.com/v2/installations/$idsite/stats?type=forecast&interval=hours&start=$tstart&end=$tend";

  debugLog ($paref, "apiProcess|apiCall", qq{Request VictronVRM API Forecast: $url});

  my $caller = (caller(0))[3];                                                    # Rücksprungmarke

  my $param = {
      url     => $url,
      timeout => 30,
      hash    => $hash,
      name    => $name,
      type    => $paref->{type},
      stc     => [gettimeofday],
      debug   => $debug,
      token   => $token,
      caller  => \&$caller,
      lang    => $paref->{lang},
      header  => { "Content-Type" => "application/json", "x-authorization" => "Bearer $token" },
      method  => 'GET',
      callback => \&__VictronVRM_ApiResponseForecast
  };

  if($debug =~ /apiCall/x) {
      $param->{loglevel} = 1;
  }

  HttpUtils_NonblockingGet ($param);

return;
}

###############################################################
#                  Victron VRM API Forecast Response
###############################################################
sub __VictronVRM_ApiResponseForecast {
  my $paref  = shift;
  my $err    = shift;
  my $myjson = shift;

  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $type   = $paref->{type};
  my $caller = $paref->{caller};
  my $stc    = $paref->{stc};
  my $lang   = $paref->{lang};
  my $debug  = $paref->{debug};

  my $msg;
  my $t   = time;
  my $sta = [gettimeofday];                                                                                # Start Response Verarbeitung

  if ($err ne "") {
      $msg = 'Victron VRM API Forecast response: '.$err;
      Log3              ($name, 1, "$name - $msg");
      singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $err;
      $data{$type}{$name}{current}{runTimeLastAPIProc}                  = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
      $data{$type}{$name}{current}{runTimeLastAPIAnswer}                = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

      return;
  }
  elsif ($myjson ne "") {                                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
      my ($success) = evaljson($hash, $myjson);

      if(!$success) {
          $msg = 'ERROR - invalid Victron VRM API Forecast response';
          Log3              ($name, 1, "$name - $msg");
          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          return;
      }

      my $jdata = decode_json ($myjson);

      if (defined $jdata->{'error_code'}) {
          $msg = 'Victron VRM API Forecast response: '.$jdata->{'error_code'};
          Log3              ($name, 3, "$name - $msg");
          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );

          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message}        = $jdata->{'error_code'};
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];  # letzte Abrufzeit
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;

          if($debug =~ /apiProcess|apiCall/x) {
              Log3 ($name, 1, "$name DEBUG> SolCast API Call - error_code: ".$jdata->{'error_code'});
              Log3 ($name, 1, "$name DEBUG> SolCast API Call - errors: "    .$jdata->{'errors'});
          }

          return;
      }
      else {
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests} += 1;
          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIcalls}    += 1;

          my $k = 0;
          while ($jdata->{'records'}{'solar_yield_forecast'}[$k]) {
              next if(ref $jdata->{'records'}{'solar_yield_forecast'}[$k] ne "ARRAY");                             # Forum: https://forum.fhem.de/index.php?msg=1288637

              my $starttmstr = $jdata->{'records'}{'solar_yield_forecast'}[$k][0];                                 # Millisekunden geliefert
              my $val        = $jdata->{'records'}{'solar_yield_forecast'}[$k][1];
              $starttmstr    = (timestampToTimestring ($starttmstr, $lang))[3];

              debugLog ($paref, "apiProcess", "Victron VRM API - PV estimate: ".$starttmstr.' => '.$val.' Wh');

              if ($val) {
                  $val = sprintf "%.0f", $val;

                  my $string = ReadingsVal ($name, 'inverterStrings', '?');

                  $data{$type}{$name}{solcastapi}{$string}{$starttmstr}{pv_estimate50} = $val;
              }

              $k++;
          }

          $k = 0;
          while ($jdata->{'records'}{'vrm_consumption_fc'}[$k]) {
              next if(ref $jdata->{'records'}{'vrm_consumption_fc'}[$k] ne "ARRAY");                             # Forum: https://forum.fhem.de/index.php?msg=1288637

              my $starttmstr = $jdata->{'records'}{'vrm_consumption_fc'}[$k][0];                                 # Millisekunden geliefert
              my $val        = $jdata->{'records'}{'vrm_consumption_fc'}[$k][1];
              $starttmstr    = (timestampToTimestring ($starttmstr, $lang))[3];

              if ($val) {
                  $val = sprintf "%.2f", $val;

                  my $string = ReadingsVal ($name, 'inverterStrings', '?');

                  $data{$type}{$name}{solcastapi}{$string.'_co'}{$starttmstr}{co_estimate} = $val;
              }

              $k++;
          }
      }
  }

  $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval  ($sta);                             # Verarbeitungszeit ermitteln
  $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval ($stc) - tv_interval ($sta));       # API Laufzeit ermitteln

  __VictronVRM_ApiRequestLogout ($paref);

return;
}

################################################################
#                Victron VRM API Logout
# https://vrm-api-docs.victronenergy.com/#/
################################################################
sub __VictronVRM_ApiRequestLogout {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $token = $paref->{token};
  my $debug = $paref->{debug};

  my $url = 'https://vrmapi.victronenergy.com/v2/auth/logout';

  debugLog ($paref, "apiProcess|apiCall", qq{Request VictronVRM API Logout: $url});

  my $caller = (caller(0))[3];                                                    # Rücksprungmarke

  my $param = {
      url        => $url,
      timeout    => 30,
      hash       => $hash,
      name       => $name,
      type       => $paref->{type},
      debug      => $debug,
      caller     => \&$caller,
      lang       => $paref->{lang},
      header     => { "Content-Type" => "application/json", "x-authorization" => "Bearer $token" },
      method     => 'GET',
      callback   => \&__VictronVRM_ApiResponseLogout
  };

  if($debug =~ /apiCall/x) {
      $param->{loglevel} = 1;
  }

  HttpUtils_NonblockingGet ($param);

return;
}

###############################################################
#                  Victron VRM API Logout Response
###############################################################
sub __VictronVRM_ApiResponseLogout {
  my $paref  = shift;
  my $err    = shift;
  my $myjson = shift;

  my $hash   = $paref->{hash};
  my $name   = $paref->{name};

  my $msg;

  if ($err ne "") {
      $msg = 'Victron VRM API error response: '.$err;
      Log3 ($name, 1, "$name - $msg");
      return;
  }
  elsif ($myjson ne "") {                                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
      my ($success) = evaljson($hash, $myjson);

      if(!$success) {
          $msg = 'ERROR - invalid Victron VRM API response';
          Log3 ($name, 1, "$name - $msg");
          return;
      }

      my $jdata = decode_json ($myjson);

      debugLog ($paref, "apiCall", qq{Victron VRM API response Logout:\n}. Dumper $jdata);
  }

return;
}

###############################################################
#                       Getter data
###############################################################
sub _getdata {
  my $paref = shift;
  my $hash  = $paref->{hash};

return centralTask ($hash);
}

###############################################################
#                       Getter html
###############################################################
sub _gethtml {
  my $paref = shift;
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // 'both';

return pageAsHtml ($name, '-', $arg);
}

###############################################################
#                       Getter ftui
#                ohne Eintrag in Get-Liste
###############################################################
sub _getftui {
  my $paref = shift;
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // '';

return pageAsHtml ($name, 'ftui', $arg);
}

###############################################################
#                       Getter pvHistory
###############################################################
sub _getlistPVHistory {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $arg   = $paref->{arg};

  my $ret = listDataPool   ($hash, 'pvhist', $arg);
  $ret   .= lineFromSpaces ($ret, 20);
  $ret    =~ s/\n/<br>/g;

return $ret;
}

###############################################################
#                       Getter pvCircular
###############################################################
sub _getlistPVCircular {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret = listDataPool   ($hash, 'circular');
  $ret   .= lineFromSpaces ($ret, 20);

return $ret;
}

###############################################################
#                       Getter nextHours
###############################################################
sub _getlistNextHours {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret = listDataPool   ($hash, 'nexthours');
  $ret   .= lineFromSpaces ($ret, 10);

return $ret;
}

###############################################################
#                       Getter pvQualities
###############################################################
sub _getForecastQualities {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $arg   = $paref->{arg} // q{};

  my $ret   = listDataPool ($hash, 'qualities');

  if ($arg eq 'imgget') {                                # Ausgabe aus dem Grafikheader Qualitätsicon
      $ret =~ s/\n/<br>/g;
  }

return $ret;
}

###############################################################
#                       Getter valCurrent
###############################################################
sub _getlistCurrent {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret = listDataPool   ($hash, 'current');
  $ret   .= lineFromSpaces ($ret, 5);

return $ret;
}

###############################################################
#                       Getter valConsumerMaster
###############################################################
sub _getlistvalConsumerMaster {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $arg   = $paref->{arg};

  my $ret = listDataPool   ($hash, 'consumer', $arg);
  $ret   .= lineFromSpaces ($ret, 10);

return $ret;
}

###############################################################
#                       Getter solApiData
###############################################################
sub _getlistSolCastData {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret = listDataPool   ($hash, 'solApiData');
  $ret   .= lineFromSpaces ($ret, 10);

return $ret;
}

###############################################################
#                       Getter aiDecTree
###############################################################
sub _getaiDecTree {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return;

  my $ret;

  if($arg eq 'aiRawData') {
      $ret = listDataPool   ($hash, 'aiRawData');
  }

  if($arg eq 'aiRuleStrings') {
      $ret = __getaiRuleStrings ($hash);
  }

  $ret .= lineFromSpaces ($ret, 5);

return $ret;
}

################################################################
#  Gibt eine Liste von Zeichenketten zurück, die den AI
#  Entscheidungsbaum in Form von Regeln beschreiben
################################################################
sub __getaiRuleStrings {                 ## no critic "not used"
  my $hash = shift;

  return 'the AI usage is not prepared' if(!isPrepared4AI ($hash));

  my $dtree = AiDetreeVal ($hash, 'aitrained', undef);

  if (!$dtree) {
      return 'AI trained object is missed';
  }

  my $rs = 'no rules delivered';
  my @rsl;

  eval { @rsl = $dtree->rule_statements()
       }
       or do { return $@;
             };

  if (@rsl) {
      my $l = scalar @rsl;
      $rs   = "<b>Number of rules: ".$l."</b>";
      $rs  .= "\n\n";
      $rs  .= join "\n", @rsl;
  }

return $rs;
}

###############################################################
#                       Getter ftuiFramefiles
# hole Dateien aus dem online Verzeichnis
# /fhem/contrib/SolarForecast/
# Ablage entsprechend Definition in controls_solarforecast.txt
###############################################################
sub _ftuiFramefiles {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  my $ret;
  my $upddo = 0;
  my $cfurl = $bPath.$cfile.$pPath;

  for my $file (@fs) {
      my $lencheck = 1;

      my ($cmerr, $cmupd, $cmmsg, $cmrec, $cmfile, $cmlen) = checkModVer ($name, $file, $cfurl);

      if ($cmerr && $cmmsg =~ /Automatic\scheck/xs && $cmrec =~ /Compare\syour\slocal/xs) {        # lokales control file ist noch nicht vorhanden -> update ohne Längencheck
          $cmfile   = 'FHEM/'.$cfile;
          $file     = $cfile;
          $lencheck = 0;
          $cmerr    = 0;
          $cmupd    = 1;

          Log3 ($name, 3, "$name - automatic install local control file $root/$cmfile");
      }

      if ($cmerr) {
          $ret = "$cmmsg<br>$cmrec";
          return $ret;
      }

      if ($cmupd) {
          $upddo = 1;
          $ret = __updPreFile ( { name     => $name,
                                  root     => $root,
                                  cmfile   => $cmfile,
                                  cmlen    => $cmlen,
                                  bPath    => $bPath,
                                  file     => $file,
                                  pPath    => $pPath,
                                  lencheck => $lencheck
                                }
                              );

          return $ret if($ret);
      }
  }

  ## finales Update control File
  ################################
  $ret = __updPreFile ( { name     => $name,
                          root     => $root,
                          cmfile   => 'FHEM/'.$cfile,
                          cmlen    => 0,
                          bPath    => $bPath,
                          file     => $cfile,
                          pPath    => $pPath,
                          lencheck => 0,
                          finalupd => 1
                        }
                      );

  return $ret if($ret);

  if (!$upddo) {
      return 'SolarForecast FTUI files are already up to date';
  }

return 'SolarForecast FTUI files updated';
}

###############################################################
#    File zum Abruf von url vorbereiten und in das
#    Zielverzeichnis schreiben
###############################################################
sub __updPreFile {
  my $pars = shift;

  my $name     = $pars->{name};
  my $root     = $pars->{root};
  my $cmfile   = $pars->{cmfile};
  my $cmlen    = $pars->{cmlen};
  my $bPath    = $pars->{bPath};
  my $file     = $pars->{file};
  my $pPath    = $pars->{pPath};
  my $lencheck = $pars->{lencheck};
  my $finalupd = $pars->{finalupd} // 0;

  my $err;

  my $dir = $cmfile;
  $dir    =~ m,^(.*)/([^/]*)$,;
  $dir    = $1;
  $dir    = "" if(!defined $dir);                                                          # file in .

  my @p = split "/", $dir;

  for (my $i = 0; $i < int @p; $i++) {
      my $path = "$root/".join ("/", @p[0..$i]);

      if (!-d $path) {
          $err  = "The FTUI does not appear to be installed.<br>";
          $err .= "Please check whether the path $path is present and accessible.<br>";
          $err .= "After installing FTUI, come back and execute the get command again.";
          return $err;

          #my $ok = mkdir $path;

          #if (!$ok) {
          #    $err = "MKDIR ERROR: $!";
          #    Log3 ($name, 1, "$name - $err");
          #    return $err;
          #}
          #else {
          #    Log3 ($name, 3, "$name - MKDIR $path");
          #}
      }
  }

  ($err, my $remFile) = __updGetUrl ($name, $bPath.$file.$pPath);

  if ($err) {
      Log3 ($name, 1, "$name - $err");
      return $err;
  }

  if ($lencheck && length $remFile ne $cmlen) {
      $err = "update ERROR: length of $file is not $cmlen Bytes";
      Log3 ($name, 1, "$name - $err");
      return $err;
  }

  $err = __updWriteFile ($root, $cmfile, $remFile);

  if ($err) {
      Log3 ($name, 1, "$name - $err");
      return $err;
  }

  Log3 ($name, 3, "$name - update done $file to $root/$cmfile ".($cmlen ? "(length: $cmlen Bytes)" : ''));

  if(!$lencheck && !$finalupd) {
      return 'SolarForecast update control file installed. Please retry the get command to update FTUI files.';
  }

return;
}

###############################################################
#                     File von url holen
###############################################################
sub __updGetUrl {
  my $name = shift;
  my $url  = shift;

  $url =~ s/%/%25/g;
  my %upd_connecthash;
  my $unicodeEncoding = 1;

  $upd_connecthash{url}           = $url;
  $upd_connecthash{keepalive}     = ($url =~ m/localUpdate/ ? 0 : 1);                        # Forum #49798
  $upd_connecthash{forceEncoding} = '' if($unicodeEncoding);

  my ($err, $data) = HttpUtils_BlockingGet (\%upd_connecthash);

  if ($err) {
      $err = "update ERROR: $err";
      return ($err, '');
  }

  if (!$data) {
      $err = 'update ERROR: empty file received';
      return ($err, '');
  }

return ('', $data);
}

###############################################################
#               Updated File schreiben
###############################################################
sub __updWriteFile {
  my $root    = shift;
  my $fName   = shift;
  my $content = shift;

  my $fPath = "$root/$fName";
  my $err;

  if (!open(FD, ">$fPath")) {
      $err = "update ERROR open $fPath failed: $!";
      return $err;
  }

  binmode(FD);
  print FD $content;
  close(FD);

  my $written = -s "$fPath";

  if ($written != length $content) {
      $err = "update ERROR writing $fPath failed: $!";
      return $err;
  }

return;
}

################################################################
sub Attr {
  my $cmd   = shift;
  my $name  = shift;
  my $aName = shift;
  my $aVal  = shift;

  my $hash  = $defs{$name};
  my $type  = $hash->{TYPE};

  my ($do,$val, $err);

  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value

  if($aName eq 'disable') {
      if($cmd eq 'set') {
          $do = $aVal ? 1 : 0;
      }
      $do  = 0 if($cmd eq 'del');
      $val = ($do == 1 ? 'disabled' : 'initialized');
      singleUpdateState ( {hash => $hash, state => $val, evt => 1} );
  }

  if($aName eq 'ctrlAutoRefresh') {
      delete $hash->{HELPER}{AREFRESH};
      delete $hash->{AUTOREFRESH};
  }

  if($aName eq 'ctrlNextDayForecastReadings') {
      deleteReadingspec ($hash, "Tomorrow_Hour.*");
  }

  if($aName eq 'ctrlBatSocManagement' && $init_done) {
      if ($cmd eq 'set') {
          return qq{Define the key "cap" with "set $name currentBatteryDev" before this attribute.}
                 if(ReadingsVal ($name, 'currentBatteryDev', '') !~ /\s+cap=/xs);

          my ($lowSoc, $upSoc, $maxsoc, $careCycle) = __parseAttrBatSoc ($name, $aVal);

          return 'The attribute syntax is wrong' if(!$lowSoc || !$upSoc || $lowSoc !~ /[0-9]+$/xs);

          if (!($lowSoc > 0 && $lowSoc < $upSoc && $upSoc < $maxsoc && $maxsoc <= 100)) {
              return 'The specified values are not plausible. Compare the attribute help.';
          }
      }
      else {
          deleteReadingspec ($hash, 'Battery_.*');
      }

      delete $data{$type}{$name}{circular}{'99'}{lastTsMaxSocRchd};
      delete $data{$type}{$name}{circular}{'99'}{nextTsMaxSocChge};
  }

  if($aName eq 'ctrlGenPVdeviation' && $aVal eq 'daily') {
      my $type = $hash->{TYPE};
      deleteReadingspec ($hash, 'Today_PVdeviation');
      delete $data{$type}{$name}{circular}{99}{tdayDvtn};
  }

  if ($aName eq 'graphicHeaderOwnspecValForm') {
      if ($cmd ne 'set') {
          delete $data{$type}{$name}{func}{ghoValForm};
          return;
      }

      my $code      = $aVal;
      ($err, $code) = checkCode ($name, $code);
      return $err if($err);

      $data{$type}{$name}{func}{ghoValForm} = $code;
  }

  if ($cmd eq 'set') {
      if ($aName eq 'ctrlInterval' || $aName eq 'ctrlBackupFilesKeep' || $aName eq 'ctrlAIdataStorageDuration') {
          unless ($aVal =~ /^[0-9]+$/x) {
              return qq{The value for $aName is not valid. Use only figures 0-9 !};
          }
      }

      if ($aName eq 'affectMaxDayVariance') {
          unless ($aVal =~ /^[0-9.]+$/x) {
              return qq{The value for $aName is not valid. Use only numbers with optional decimal places !};
          }
      }

      if ($init_done == 1 && $aName eq "ctrlSolCastAPIoptimizeReq") {
          if (!isSolCastUsed ($hash)) {
              return qq{The attribute $aName is only valid for device model "SolCastAPI".};
          }
      }

      if ($aName eq 'ctrlUserExitFn' && $init_done) {
          ($err) = checkCode ($name, $aVal, 'cc1');
          return $err if($err);
      }
  }

  my $params = {
      hash  => $hash,
      name  => $name,
      type  => $hash->{TYPE},
      cmd   => $cmd,
      aName => $aName,
      aVal  => $aVal
  };

  $aName = 'consumer' if($aName =~ /consumer?(\d+)$/xs);

  if($hattr{$aName} && defined &{$hattr{$aName}{fn}}) {
      my $ret = q{};
      $ret    = &{$hattr{$aName}{fn}} ($params);
      return $ret;
  }

return;
}

################################################################
#                      Attr consumer
################################################################
sub _attrconsumer {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $aName = $paref->{aName};
  my $aVal  = $paref->{aVal};
  my $cmd   = $paref->{cmd};

  return if(!$init_done);                                                                  # Forum: https://forum.fhem.de/index.php/topic,117864.msg1159959.html#msg1159959

  my ($err, $valid);

  if ($cmd eq "set") {
      my ($a,$h) = parseParams ($aVal);
      my $codev  = $a->[0] // "";

      if (!$codev || !$defs{$codev}) {
          return qq{The device "$codev" doesn't exist!};
      }

      if (!$h->{type} || !exists $h->{power}) {
          return qq{The syntax of "$aName" is not correct. Please consider the commandref.};
      }

      my $alowt = $h->{type} ~~ @ctypes ? 1 : 0;
      if (!$alowt) {
          return qq{The type "$h->{type}" isn't allowed!};
      }

      if (exists $h->{switchdev}) {
          my $dswitch = $h->{switchdev};                                                           # alternatives Schaltdevice

          if(!$defs{$dswitch}) {
              return qq{The device "$dswitch" doesn't exist!};
          }
      }

      if ($h->{power} !~ /^[0-9]+$/xs) {
          return qq{The key "power" must be specified only by numbers without decimal places};
      }

      if (exists $h->{mode} && $h->{mode} !~ /^(?:can|must)$/xs) {
          return qq{The mode "$h->{mode}" isn't allowed!};
      }

      if (exists $h->{notbefore}) {
          if ($h->{notbefore} =~ m/^\s*\{.*\}\s*$/xs) {
              ($err) = checkCode ($name, $h->{notbefore}, 'cc1');
              return $err if($err);
          }
          else {
              $valid = checkhhmm ($h->{notbefore});
              return qq{The syntax "notbefore=$h->{notbefore}" is wrong!} if(!$valid);
          }
      }

      if (exists $h->{notafter}) {
          if ($h->{notafter} =~ m/^\s*\{.*\}\s*$/xs) {
              ($err) = checkCode ($name, $h->{notafter}, 'cc1');
              return $err if($err);
          }
          else {
              $valid = checkhhmm ($h->{notafter});
              return qq{The syntax "notafter=$h->{notafter}" is wrong!} if(!$valid);
          }
      }

      if (exists $h->{interruptable}) {                                                            # Check Regex/Hysterese
          my (undef,undef,$regex,$hyst) = split ":", $h->{interruptable};

          $err = checkRegex ($regex);
          return $err if($err);

          if ($hyst && !isNumeric ($hyst)) {
              return qq{The hysteresis of key "interruptable" must be a numeric value like "0.5" or "2"};
          }
      }

      if (exists $h->{swoncond}) {                                                                 # Check Regex
          my (undef,undef,$regex) = split ":", $h->{swoncond};

          $err = checkRegex ($regex);
          return $err if($err);
      }

      if (exists $h->{swoffcond}) {                                                                # Check Regex
          my (undef,undef,$regex) = split ":", $h->{swoffcond};

          $err = checkRegex ($regex);
          return $err if($err);
      }

      if (exists $h->{swstate}) {                                                                  # Check Regex
          my (undef,$onregex,$offregex) = split ":", $h->{swstate};

          $err = checkRegex ($onregex);
          return $err if($err);

          $err = checkRegex ($offregex);
          return $err if($err);
      }

      if (exists $h->{mintime}) {                                                                  # Check Regex
          my $mintime = $h->{mintime};

          if (!isNumeric ($mintime) && $mintime !~ /^SunPath/xsi) {
              return qq(The key "mintime" must be an integer or a string starting with "SunPath.");
          }
      }
  }
  else {
      my $day  = strftime "%d", localtime(time);                                                   # aktueller Tag  (range 01 to 31)
      my ($c)  = $aName =~ /consumer([0-9]+)/xs;

      deleteReadingspec ($hash, "consumer${c}.*");

      for my $i (1..24) {                                                                          # Consumer aus History löschen
          delete $data{$type}{$name}{pvhist}{$day}{sprintf("%02d",$i)}{"csmt${c}"};
          delete $data{$type}{$name}{pvhist}{$day}{sprintf("%02d",$i)}{"csme${c}"};
      }

      delete $data{$type}{$name}{pvhist}{$day}{99}{"csmt${c}"};
      delete $data{$type}{$name}{pvhist}{$day}{99}{"csme${c}"};
      delete $data{$type}{$name}{consumers}{$c};                                                   # Consumer Hash Verbraucher löschen
  }

  writeCacheToFile ($hash, "consumers", $csmcache.$name);                                          # Cache File Consumer schreiben

  $data{$type}{$name}{current}{consumerCollected} = 0;                                             # Consumer neu sammeln

  InternalTimer (gettimeofday()+0.5, 'FHEM::SolarForecast::centralTask',          [$name, 0], 0);
  InternalTimer (gettimeofday()+2,   'FHEM::SolarForecast::createAssociatedWith', $hash,      0);

return;
}

################################################################
#               Attr ctrlConsRecommendReadings
################################################################
sub _attrcreateConsRecRdgs {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aName = $paref->{aName};

  if ($aName eq 'ctrlConsRecommendReadings') {
      deleteReadingspec ($hash, "consumer.*_ConsumptionRecommended");
  }

return;
}

################################################################
#               Attr ctrlStatisticReadings
################################################################
sub _attrcreateStatisticRdgs {           ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $aName = $paref->{aName};
  my $aVal  = $paref->{aVal};

  my $te = 'currentRunMtsConsumer_';

  if ($aVal =~ /$te/xs && $init_done) {
      my @aa = split ",", $aVal;

      for my $arg (@aa) {
          next if($arg !~ /$te/xs);

          my $cn = (split "_", $arg)[1];                                                # Consumer Nummer extrahieren

          if (!AttrVal ($name, 'consumer'.$cn, '')) {
              return qq{The consumer "consumer$cn" is currently not registered as an active consumer!};
          }
      }
  }

return;
}

###################################################################################
#       Eventverarbeitung
#       - Aktualisierung Consumerstatus bei asynchronen Consumern
###################################################################################
sub Notify {
  # Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
  # Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben.

  my $myHash   = shift;
  my $dev_hash = shift;
  my $myName   = $myHash->{NAME};                                                         # Name des eigenen Devices
  my $devName  = $dev_hash->{NAME};                                                       # Device welches Events erzeugt hat

  return if((controller($myName))[1] || !$myHash->{NOTIFYDEV});

  my $events = deviceEvents($dev_hash, 1);
  return if(!$events);

  my $cdref     = CurrentVal ($myHash, 'consumerdevs', '');                               # alle registrierten Consumer und Schaltdevices
  my @consumers = ();
  @consumers    = @{$cdref} if(ref $cdref eq "ARRAY");

  return if(!@consumers);

  my $debug = getDebug ($myHash);                                                         # Debug Mode

  if($devName ~~ @consumers) {
      my ($cname, $cindex);
      my $type = $myHash->{TYPE};

      for my $c (sort{$a<=>$b} keys %{$data{$type}{$myName}{consumers}}) {
          my ($cname, $dswname) = getCDnames ($myHash, $c);

          if ($devName eq $cname) {
              $cindex = $c;
              last;
          }

          if ($devName eq $dswname) {
              $cindex = $c;

              if ($debug =~ /notifyHandling/x) {
                  Log3 ($myName, 1, qq{$myName DEBUG> notifyHandling - Event device >$devName< is switching device of consumer >$cname< (index: $c)});
              }

              last;
          }
      }

      if (!$cindex) {
         Log3 ($myName, 2, qq{$myName notifyHandling - Device >$devName< has no consumer index and/or ist not a known switching device. Exiting...});
         return;
      }

      my $async    = ConsumerVal ($myHash, $cindex, 'asynchron',      0);
      my $rswstate = ConsumerVal ($myHash, $cindex, 'rswstate', 'state');

      if ($debug =~ /notifyHandling/x) {
          Log3 ($myName, 1, qq{$myName DEBUG> notifyHandling - Consumer >$cindex< asynchronous mode: $async});
      }

      return if(!$async);                                                                 # Consumer synchron -> keine Weiterverarbeitung

      my ($reading,$value,$unit);

      for my $event (@{$events}) {
          $event  = "" if(!defined($event));

          my @parts = split(/: /,$event, 2);
          $reading  = shift @parts;

          if (@parts == 2) {
            $value = $parts[0];
            $unit  = $parts[1];
          }
          else {
            $value = join(": ", @parts);
            $unit  = "";
          }

          if (!defined($reading)) { $reading = ""; }
          if (!defined($value))   { $value   = ""; }
          if ($value eq "") {
              if ($event =~ /^.*:\s$/) {
                  $reading = (split(":", $event))[0];
              }
              else {
                  $reading = "state";
                  $value   = $event;
              }
          }

          if ($reading eq $rswstate) {

              if ($debug =~ /notifyHandling/x) {
                  Log3 ($myName, 1, qq{$myName DEBUG> notifyHandling - start centralTask by Notify device: $devName, reading: $reading, value: $value});
              }

              centralTask ($myHash, 0);                                                  # keine Events in SolarForecast außer 'state'
          }
      }
  }

return;
}

###############################################################
#                  DbLog_splitFn
###############################################################
sub DbLogSplit {
  my $event  = shift;
  my $device = shift;
  my ($reading, $value, $unit) = ("","","");

  if($event =~ /\s(k?Wh?|%)$/xs) {
      my @parts = split(/\s/x, $event, 3);
      $reading  = $parts[0];
      $reading  =~ tr/://d;
      $value    = $parts[1];
      $unit     = $parts[2];

      # Log3 ($device, 1, qq{$device - Split for DbLog done -> Reading: $reading, Value: $value, Unit: $unit});
  }

return ($reading, $value, $unit);
}

################################################################
#                         Shutdown
################################################################
sub Shutdown {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  writeCacheToFile ($hash, "pvhist",      $pvhcache.$name);             # Cache File für PV History schreiben
  writeCacheToFile ($hash, "circular",    $pvccache.$name);             # Cache File für PV Circular schreiben
  writeCacheToFile ($hash, "consumers",   $csmcache.$name);             # Cache File Consumer schreiben
  writeCacheToFile ($hash, "solcastapi", $scpicache.$name);             # Cache File SolCast API Werte schreiben

return;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg,
# der ebenfalls alle Geräte löscht und danach das
# Konfigurationsfile neu einliest. Entsprechend müssen in der
# Funktion typische Aufräumarbeiten durchgeführt werden wie das
# saubere Schließen von Verbindungen oder das Entfernen von
# internen Timern.
################################################################
sub Undef {
 my $hash = shift;
 my $name = shift;

 RemoveInternalTimer($hash);
 delete $readyfnlist{$name};

return;
}

#################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion
# X_Undef aufgerufen um offene Verbindungen zu schließen,
# anschließend wird die Funktion X_Delete aufgerufen.
# Funktion: Aufräumen von dauerhaften Daten, welche durch das
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind.
# Es geht hier also eher darum, alle Spuren sowohl im laufenden
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben.
#################################################################
sub Delete {
  my $hash  = shift;
  my $arg   = shift;
  my $name  = $hash->{NAME};

  my @ftd = ( $pvhcache.$name,
              $pvccache.$name,
              $plantcfg.$name,
              $csmcache.$name,
              $scpicache.$name,
              $airaw.$name,
              $aitrained.$name
            );

  for my $f (@ftd) {
      my $err = FileDelete($f);

      if ($err) {
          Log3 ($name, 1, qq{$name - Message while deleting file "$f": $err});
      }
  }

return;
}

################################################################
#        Timer für Cache File Daten schreiben
################################################################
sub periodicWriteCachefiles {
  my $hash = shift;
  my $bckp = shift // '';

  my $name = $hash->{NAME};

  RemoveInternalTimer ($hash, "FHEM::SolarForecast::periodicWriteCachefiles");
  InternalTimer       (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0);

  return if((controller($name))[1] || (controller($name))[2]);

  writeCacheToFile ($hash, "circular", $pvccache.$name);                      # Cache File PV Circular schreiben
  writeCacheToFile ($hash, "pvhist",   $pvhcache.$name);                      # Cache File PV History schreiben

  if ($bckp) {
      my $tstr = (timestampToTimestring (0))[2];
      $tstr    =~ s/[-: ]/_/g;

      writeCacheToFile ($hash, "circular", $pvccache.$name.'_'.$tstr);        # Cache File PV Circular Sicherung schreiben
      writeCacheToFile ($hash, "pvhist",   $pvhcache.$name.'_'.$tstr);        # Cache File PV History Sicherung schreiben

      deleteOldBckpFiles ($name, 'PVH_SolarForecast_'.$name);                 # alte Backup Files löschen
      deleteOldBckpFiles ($name, 'PVC_SolarForecast_'.$name);
  }

return;
}

################################################################
#                       Backupfiles löschen
################################################################
sub deleteOldBckpFiles {
  my $name = shift;
  my $file = shift;

  my $dfk    = AttrVal ($name, 'ctrlBackupFilesKeep', 3);
  my $bfform = $file.'_.*';

  if (!opendir (DH, $cachedir)) {
      Log3 ($name, 1, "$name - ERROR - Can't open path '$cachedir'");
      return;
  }

  my @files = sort grep {/^$bfform$/} readdir(DH);
  return if(!@files);

  my $fref = stat ("$cachedir/$file");

  if ($fref) {
      if ($fref =~ /ARRAY/) {
          @files = sort { (@{stat "$cachedir/$a"})[9] cmp (@{stat "$cachedir/$b"})[9] } @files;
      }
      else {
          @files = sort { (stat "$cachedir/$a")[9] cmp (stat "$cachedir/$b")[9] } @files;
      }
  }

  closedir (DH);

  Log3 ($name, 4, "$name - Backup files were found in '$cachedir' directory: ".join(', ',@files));

  my $max = int @files - $dfk;

  for (my $i = 0; $i < $max; $i++) {
      my $done = 1;
      unlink "$cachedir/$files[$i]" or do { Log3 ($name, 1, "$name - WARNING - Could not delete '$cachedir/$files[$i]': $!");
                                            $done = 0;
                                          };

      Log3 ($name, 3, "$name - old backup file '$cachedir/$files[$i]' deleted") if($done);
  }

return;
}

################################################################
#             Daten in File wegschreiben
################################################################
sub writeCacheToFile {
  my $hash      = shift;
  my $cachename = shift;
  my $file      = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my @data;
  my ($error, $err, $lw);

  if ($cachename eq 'aitrained') {
      my $dtree = AiDetreeVal ($hash, 'aitrained', '');
      return if(ref $dtree ne 'AI::DecisionTree');

      $error = fileStore ($dtree, $file);

      if ($error) {
          $err = qq{ERROR while writing AI data to file "$file": $error};
          Log3 ($name, 1, "$name - $err");
          return $err;
      }

      $lw                 = gettimeofday();
      $hash->{LCACHEFILE} = "last write time: ".FmtTime($lw)." File: $file";
      singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );

      return;
  }

  if ($cachename eq 'airaw') {
      my $data = AiRawdataVal ($hash, '', '', '');

      if ($data) {
          $error = fileStore ($data, $file);
      }

      if ($error) {
          $err = qq{ERROR while writing AI data to file "$file": $error};
          Log3 ($name, 1, "$name - $err");
          return $err;
      }

      $lw                 = gettimeofday();
      $hash->{LCACHEFILE} = "last write time: ".FmtTime($lw)." File: $file";
      singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );

      return;
  }

  if ($cachename eq 'plantconfig') {
      @data = _savePlantConfig ($hash);
      return 'Plant configuration is empty, no data where written' if(!@data);
  }
  else {
      return if(!$data{$type}{$name}{$cachename});
      my $json = encode_json ($data{$type}{$name}{$cachename});
      push @data, $json;
  }

  $error = FileWrite ($file, @data);

  if ($error) {
      $err = qq{ERROR writing cache file "$file": $error};
      Log3 ($name, 1, "$name - $err");
      return $err;
  }

  $lw                 = gettimeofday();
  $hash->{LCACHEFILE} = "last write time: ".FmtTime($lw)." File: $file";
  singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );

return;
}

################################################################
#          Anlagenkonfiguration sichern
################################################################
sub _savePlantConfig {
  my $hash = shift;
  my $name = $hash->{NAME};

  my @pvconf;

  my @aconfigs = qw(
                     pvCorrectionFactor_Auto
                     currentBatteryDev
                     currentWeatherDev
                     currentInverterDev
                     currentMeterDev
                     currentRadiationAPI
                     inverterStrings
                     moduleDirection
                     modulePeakString
                     moduleTiltAngle
                     moduleRoofTops
                     powerTrigger
                     energyH4Trigger
                   );

  for my $cfg (@aconfigs) {
      my $val = ReadingsVal($name, $cfg, "");
      next if(!$val);
      push @pvconf, $cfg."<>".$val;
  }

return @pvconf;
}

################################################################
#              centralTask Start Management
################################################################
sub runCentralTask {
  my $hash = shift;

  return if(!$init_done);

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  return if(CurrentVal ($hash, 'ctrunning', 0));

  my $debug;
  my $t        = time;
  my $second   = int (strftime "%S", localtime($t));                                 # aktuelle Sekunde (00-61)
  my $minute   = int (strftime "%M", localtime($t));                                 # aktuelle Minute (00-59)
  my $interval = (controller ($name))[0];                                            # Interval

  if (!$interval) {
      $hash->{MODE} = 'Manual';
      storeReading ('nextCycletime', 'Manual');
      return;
  }

  if ((controller($name))[1]) {
      $hash->{MODE} = 'disabled';
      return;
  }

  if ((controller($name))[2]) {
      $hash->{MODE} = 'inactive';
      return;
  }

  my $nct = CurrentVal ($hash, 'nextCycleTime', 0);                                  # gespeicherte nächste CyleTime

  if ($t >= $nct) {
      my $new       = $t + $interval;                                                # nächste Wiederholungszeit
      $hash->{MODE} = 'Automatic - next Cycletime: '.FmtTime($new);

      $data{$type}{$name}{current}{nextCycleTime} = $new;

      storeReading ('nextCycletime', FmtTime($new));
      centralTask  ($hash, 1);
  }

  if ($minute == 59 && $second > 48 && $second < 58) {
      if (!exists $hash->{HELPER}{S58DONE}) {
          $debug                   = getDebug ($hash);
          $hash->{HELPER}{S58DONE} = 1;

          if ($debug =~ /collectData/x) {
              Log3 ($name, 1, "$name DEBUG> Start of unscheduled data collection at the end of an hour");
          }

          centralTask ($hash, 1);
      }
  }
  else {
      delete $hash->{HELPER}{S58DONE};
  }

  if ($minute == 0 && $second > 3 && $second < 20) {
      if (!exists $hash->{HELPER}{S20DONE}) {
          $debug                   = getDebug ($hash);
          $hash->{HELPER}{S20DONE} = 1;

          if ($debug =~ /collectData/x) {
              Log3 ($name, 1, "$name DEBUG> Start of unscheduled data collection at the beginning of an hour");
          }

          centralTask ($hash, 1);
      }
  }
  else {
      delete $hash->{HELPER}{S20DONE};
  }

return;
}

################################################################
#                       Zentraler Datenabruf
################################################################
sub centralTask {
  my $par = shift;
  my $evt = shift // 1;                                                # Readings Event generieren

  my ($hash, $name);
  if (ref $par eq 'HASH') {                                            # Standard Fn Aufruf
      $hash = $par;
      $name = $hash->{NAME};
  }
  elsif (ref $par eq 'ARRAY') {                                        # Array Referenz wurde übergeben
      $name = $par->[0];
      $evt  = $par->[1] // 1;                                          # Readings Event generieren
      $hash = $defs{$name};
  }
  else {
      Log (1, "ERROR module ".__PACKAGE__." - function >centralTask< was called with wrong data reference type: >".(ref $par)."<");
      return;
  }

  my $type = $hash->{TYPE};
  my $cst  = [gettimeofday];                                           # Zyklus-Startzeit

  RemoveInternalTimer ($hash, 'FHEM::SolarForecast::centralTask');
  RemoveInternalTimer ($hash, 'FHEM::SolarForecast::singleUpdateState');

  ### nicht mehr benötigte Readings/Daten löschen - Bereich kann später wieder raus !!
  ##########################################################################################
  #for my $i (keys %{$data{$type}{$name}{nexthours}}) {
  #    delete $data{$type}{$name}{nexthours}{$i}{Rad1h};
  #}

  #for my $c (keys %{$data{$type}{$name}{consumers}}) {
  #    delete $data{$type}{$name}{consumers}{$c}{epiecEstart};
  #    delete $data{$type}{$name}{consumers}{$c}{epiecStart};
  #    delete $data{$type}{$name}{consumers}{$c}{epiecStartEnergy};
  #}

  #for my $k (sort keys %{$data{$type}{$name}{circular}}) {
  #    my $val = $data{$type}{$name}{circular}{$k}{pvcorrf}{percentile};
  #    $data{$type}{$name}{circular}{$k}{pvcorrf}{percentile} = 1 if($val && $val >= 10);
  #}

  #my $fcdev = ReadingsVal  ($name, "currentForecastDev",  undef);
  #if ($fcdev) {
  #    readingsSingleUpdate ($hash, "currentWeatherDev", $fcdev, 0);
  #    deleteReadingspec    ($hash, "currentForecastDev");
  #}

  #my $rdev = ReadingsVal   ($name, "currentRadiationDev",  undef);
  #if ($rdev) {
  #    readingsSingleUpdate ($hash, "currentRadiationAPI", $rdev, 0);
  #    deleteReadingspec    ($hash, "currentRadiationDev");
  #}

  ############################################################################################

  return if(!$init_done);

  setModel ($hash);                                                                            # Model setzen

  return if((controller($name))[1] || (controller($name))[2]);                                 # disabled / inactive

  if (CurrentVal ($hash, 'ctrunning', 0)) {
      Log3 ($name, 3, "$name - INFO - central task was called when it was already running ... end this call");
      $data{$type}{$name}{current}{ctrunning} = 0;
      return;
  }

  if (!CurrentVal ($hash, 'allStringsFullfilled', 0)) {                                        # die String Konfiguration erstellen wenn noch nicht erfolgreich ausgeführt
      my $ret = createStringConfig ($hash);

      if ($ret) {
          singleUpdateState ( {hash => $hash, state => $ret, evt => 1} );                                                                    # Central Task running Statusbit
          return;
      }
  }

  my $t       = time;                                                                          # aktuelle Unix-Zeit
  my $date    = strftime "%Y-%m-%d", localtime($t);                                            # aktuelles Datum
  my $chour   = strftime "%H",       localtime($t);                                            # aktuelle Stunde in 24h format (00-23)
  my $minute  = strftime "%M",       localtime($t);                                            # aktuelle Minute (00-59)
  my $day     = strftime "%d",       localtime($t);                                            # aktueller Tag  (range 01 to 31)
  my $dayname = strftime "%a",       localtime($t);                                            # aktueller Wochentagsname
  my $debug   = getDebug ($hash);                                                              # Debug Module

  $data{$type}{$name}{current}{ctrunning} = 1;                                                 # Central Task running Statusbit

  my $centpars = {
      hash    => $hash,
      name    => $name,
      type    => $type,
      t       => $t,
      date    => $date,
      minute  => $minute,
      chour   => $chour,
      day     => $day,
      dayname => $dayname,
      debug   => $debug,
      lang    => getLang ($hash),
      state   => 'running',
      evt     => 0
  };

  if ($debug !~ /^none$/xs) {
      Log3 ($name, 4, "$name DEBUG> ################################################################");
      Log3 ($name, 4, "$name DEBUG> ###                  New centralTask cycle                   ###");
      Log3 ($name, 4, "$name DEBUG> ################################################################");
      Log3 ($name, 4, "$name DEBUG> current hour of day: ".($chour+1));
  }

  singleUpdateState           ($centpars);
  $centpars->{state} = 'updated';                                                     # kann durch Subs überschrieben werden!

  collectAllRegConsumers      ($centpars);                                            # alle Verbraucher Infos laden
  _specialActivities          ($centpars);                                            # zusätzliche Events generieren + Sonderaufgaben
  _transferWeatherValues      ($centpars);                                            # Wetterwerte übertragen

  createReadingsFromArray     ($hash, $evt);                                          # Readings erzeugen
  readingsDelete              ($hash, 'AllPVforecastsToEvent');

  _getRoofTopData             ($centpars);                                            # Strahlungswerte/Forecast-Werte in solcastapi-Hash erstellen
  _transferAPIRadiationValues ($centpars);                                            # Raw Erzeugungswerte aus solcastapi-Hash übertragen und Forecast mit/ohne Korrektur erstellen
  _calcMaxEstimateToday       ($centpars);                                            # heutigen Max PV Estimate & dessen Tageszeit ermitteln
  _transferInverterValues     ($centpars);                                            # WR Werte übertragen
  _transferMeterValues        ($centpars);                                            # Energy Meter auswerten
  _transferBatteryValues      ($centpars);                                            # Batteriewerte einsammeln
  _batSocTarget               ($centpars);                                            # Batterie Optimum Ziel SOC berechnen
  _createSummaries            ($centpars);                                            # Zusammenfassungen erstellen
  _manageConsumerData         ($centpars);                                            # Consumer Daten sammeln und Zeiten planen
  _estConsumptionForecast     ($centpars);                                            # Verbrauchsprognose erstellen
  _evaluateThresholds         ($centpars);                                            # Schwellenwerte bewerten und signalisieren
  _calcReadingsTomorrowPVFc   ($centpars);                                            # zusätzliche Readings Tomorrow_HourXX_PVforecast berechnen
  _calcTodayPVdeviation       ($centpars);                                            # Vorhersageabweichung erstellen (nach Sonnenuntergang)

  createReadingsFromArray     ($hash, $evt);                                          # Readings erzeugen

  calcValueImproves           ($centpars);                                            # neue Korrekturfaktor/Qualität und berechnen und speichern, AI anreichern

  createReadingsFromArray     ($hash, $evt);                                          # Readings erzeugen

  saveEnergyConsumption       ($centpars);                                            # Energie Hausverbrauch speichern
  genStatisticReadings        ($centpars);                                            # optionale Statistikreadings erstellen

  userExit                    ($centpars);                                            # User spezifische Funktionen ausführen
  setTimeTracking             ($hash, $cst, 'runTimeCentralTask');                    # Zyklus-Laufzeit ermitteln

  createReadingsFromArray     ($hash, $evt);                                          # Readings erzeugen

  if ($evt) {
      $centpars->{evt} = $evt;
      InternalTimer(gettimeofday()+1, "FHEM::SolarForecast::singleUpdateState", $centpars, 0);
  }
  else {
      $centpars->{evt} = 1;
      singleUpdateState ($centpars);
  }

  $data{$type}{$name}{current}{ctrunning} = 0;

return;
}

################################################################
#       Erstellen der Stringkonfiguration
#       Stringhash: $data{$type}{$name}{strings}
################################################################
sub createStringConfig {                 ## no critic "not used"
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  delete $data{$type}{$name}{strings};                                                            # Stringhash zurücksetzen
  $data{$type}{$name}{current}{allStringsFullfilled} = 0;

  my @istrings = split ",", ReadingsVal ($name, 'inverterStrings', '');                           # Stringbezeichner
  $data{$type}{$name}{current}{allstringscount} = scalar @istrings;                               # Anzahl der Anlagenstrings

  if (!@istrings) {
      return qq{Define all used strings with command "set $name inverterStrings" first.};
  }

  my $peak = ReadingsVal ($name, 'modulePeakString', '');                                         # kWp für jeden Stringbezeichner
  return qq{Please complete command "set $name modulePeakString".} if(!$peak);

  my ($aa,$ha) = parseParams ($peak);
  delete $data{$type}{$name}{current}{allstringspeak};

  while (my ($strg, $pp) = each %$ha) {
      if ($strg ~~ @istrings) {
          $data{$type}{$name}{strings}{$strg}{peak}     = $pp;
          $data{$type}{$name}{current}{allstringspeak} += $pp * 1000;                             # insgesamt installierte Peakleistung in W
      }
      else {
          return qq{Check "modulePeakString" -> the stringname "$strg" is not defined as valid string in reading "inverterStrings"};
      }
  }

  if (isSolCastUsed ($hash)) {                                                                   # SolCast-API Strahlungsquelle
      my $mrt = ReadingsVal ($name, 'moduleRoofTops', '');                                       # RoofTop Konfiguration -> Zuordnung <pk>
      return qq{Please complete command "set $name moduleRoofTops".} if(!$mrt);

      my ($ad,$hd) = parseParams ($mrt);

      while (my ($is, $pk) = each %$hd) {
          if ($is ~~ @istrings) {
              $data{$type}{$name}{strings}{$is}{pk} = $pk;
          }
          else {
              return qq{Check "moduleRoofTops" -> the stringname "$is" is not defined as valid string in reading "inverterStrings"};
          }
      }
  }
  elsif (isVictronKiUsed ($hash)) {
      my $invs = ReadingsVal ($name, 'inverterStrings', '');

      if ($invs ne 'KI-based') {
          return qq{You use a KI based model. Please set only "KI-based" as String with command "set $name inverterStrings".};
      }
  }
  elsif (!isVictronKiUsed ($hash)) {
      my $tilt = ReadingsVal ($name, 'moduleTiltAngle', '');                                      # Modul Neigungswinkel für jeden Stringbezeichner
      return qq{Please complete command "set $name moduleTiltAngle".} if(!$tilt);

      my ($at,$ht) = parseParams ($tilt);

      while (my ($key, $value) = each %$ht) {
          if ($key ~~ @istrings) {
              $data{$type}{$name}{strings}{$key}{tilt} = $value;
          }
          else {
              return qq{Check "moduleTiltAngle" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
          }
      }

      my $dir = ReadingsVal ($name, 'moduleDirection', '');                                      # Modul Ausrichtung für jeden Stringbezeichner
      return qq{Please complete command "set $name moduleDirection".} if(!$dir);

      my ($ad,$hd) = parseParams ($dir);
      my $iwrong   = qq{Please check the input of set "moduleDirection". It seems to be wrong.};

      while (my ($key, $value) = each %$hd) {
          if ($key ~~ @istrings) {
              $data{$type}{$name}{strings}{$key}{dir}    = _azimuth2ident ($value) // return $iwrong;
              $data{$type}{$name}{strings}{$key}{azimut} = _ident2azimuth ($value) // return $iwrong;
          }
          else {
              return qq{Check "moduleDirection" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
          }
      }
  }

  if(!keys %{$data{$type}{$name}{strings}}) {
      return qq{The string configuration seems to be incomplete. \n}.
             qq{Please check the settings of inverterStrings, modulePeakString, moduleDirection, moduleTiltAngle }.
             qq{and/or moduleRoofTops if SolCast-API is used.};
  }

  my @sca = keys %{$data{$type}{$name}{strings}};                                               # Gegencheck ob nicht mehr Strings in inverterStrings enthalten sind als eigentlich verwendet
  my @tom;

  for my $sn (@istrings) {
      next if ($sn ~~ @sca);
      push @tom, $sn;
  }

  if (@tom) {
      return qq{Some Strings are not used. Please delete this string names from "inverterStrings" :}.join ",",@tom;
  }

  $data{$type}{$name}{current}{allStringsFullfilled} = 1;

return;
}

################################################################
#  formt die Azimut Angabe in Azimut-Bezeichner um
#  Azimut-Bezeichner werden direkt zurück gegeben
################################################################
sub _azimuth2ident {
  my $az = shift;

  return $az if($az =~ /^[A-Za-z]*$/xs);

  my $id = $az == -180 ? 'N'  :
           $az <= -158 ? 'N'  :
           $az <= -134 ? 'NE' :
           $az == -135 ? 'NE' :
           $az <= -113 ? 'NE' :
           $az <= -89  ? 'E'  :
           $az == -90  ? 'E'  :
           $az <= -68  ? 'E'  :
           $az <= -44  ? 'SE' :
           $az == -45  ? 'SE' :
           $az <= -23  ? 'SE' :
           $az <= -1   ? 'S'  :
           $az == 0    ? 'S'  :
           $az <= 23   ? 'S'  :
           $az <= 44   ? 'SW' :
           $az == 45   ? 'SW' :
           $az <= 67   ? 'SW' :
           $az <= 89   ? 'W'  :
           $az == 90   ? 'W'  :
           $az <= 112  ? 'W'  :
           $az <= 134  ? 'NW' :
           $az == 135  ? 'NW' :
           $az <= 157  ? 'NW' :
           $az <= 179  ? 'N'  :
           $az == 180  ? 'N'  :
           undef;

return $id;
}

################################################################
#  formt einen Azimut-Bezeichner in ein Azimut um
#  numerische  werden direkt zurück gegeben
################################################################
sub _ident2azimuth {
  my $id = shift;

  return $id if(isNumeric ($id));

  my $az = $id eq 'N'  ? -180 :
           $id eq 'NE' ? -135 :
		   $id eq 'E'  ? -90  :
           $id eq 'SE' ? -45  :
		   $id eq 'S'  ? 0    :
           $id eq 'SW' ? 45   :
           $id eq 'W'  ? 90   :
           $id eq 'NW' ? 135  :
		   undef;

return $az;
}

################################################################
#             Steuerparameter berechnen / festlegen
################################################################
sub controller {
  my $name = shift;

  my $interval = AttrVal    ($name, 'ctrlInterval', $definterval);            # 0 wenn manuell gesteuert
  my $idval    = IsDisabled ($name);
  my $disabled = $idval == 1 ? 1 : 0;
  my $inactive = $idval == 3 ? 1 : 0;

return ($interval, $disabled, $inactive);
}

################################################################
#     Zusätzliche Readings/ Events für Logging generieren und
#     Sonderaufgaben !
################################################################
sub _specialActivities {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $date  = $paref->{date};                                              # aktuelles Datum
  my $chour = $paref->{chour};
  my $t     = $paref->{t};                                                 # aktuelle Zeit
  my $day   = $paref->{day};

  my ($ts,$ts1,$pvfc,$pvrl,$gcon);

  $ts1  = $date." ".sprintf("%02d",$chour).":00:00";

  $pvfc = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$chour)."_PVforecast", 0);
  storeReading ('LastHourPVforecast', "$pvfc Wh", $ts1);

  $pvrl = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$chour)."_PVreal", 0);
  storeReading ('LastHourPVreal', "$pvrl Wh", $ts1);

  $gcon = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$chour)."_GridConsumption", 0);
  storeReading ('LastHourGridconsumptionReal', "$gcon Wh", $ts1);

  ## Planungsdaten spezifisch löschen (Anfang und Ende nicht am selben Tag)
  ##########################################################################

  for my $c (keys %{$data{$type}{$name}{consumers}}) {
      next if(ConsumerVal ($hash, $c, "plandelete", "regular") eq "regular");

      my $planswitchoff = ConsumerVal    ($hash, $c, "planswitchoff", $t);
      my $simpCstat     = simplifyCstate (ConsumerVal ($hash, $c, "planstate", ""));

      if ($t > $planswitchoff && $simpCstat =~ /planned|finished|unknown/xs) {
          deleteConsumerPlanning ($hash, $c);

          $data{$type}{$name}{consumers}{$c}{minutesOn}       = 0;
          $data{$type}{$name}{consumers}{$c}{numberDayStarts} = 0;
          $data{$type}{$name}{consumers}{$c}{onoff}           = 'off';
      }
  }

  ## bestimmte einmalige Aktionen
  ##################################
  my $tlim = "00";
  if ($chour =~ /^($tlim)$/x) {
      if (!exists $hash->{HELPER}{H00DONE}) {
          $date = strftime "%Y-%m-%d", localtime($t-7200);                                   # Vortag (2 h Differenz reichen aus)
          $ts   = $date." 23:59:59";

          $pvfc = ReadingsNum ($name, "Today_Hour24_PVforecast", 0);
          storeReading ('LastHourPVforecast', "$pvfc Wh", $ts);

          $pvrl = ReadingsNum ($name, "Today_Hour24_PVreal", 0);
          storeReading ('LastHourPVreal', "$pvrl Wh", $ts);

          $gcon = ReadingsNum ($name, "Today_Hour24_GridConsumption", 0);
          storeReading ('LastHourGridconsumptionReal', "$gcon Wh", $ts);

          writeCacheToFile ($hash, "plantconfig", $plantcfg.$name);                           # Anlagenkonfiguration sichern

          deleteReadingspec ($hash, "Today_Hour.*_Grid.*");
          deleteReadingspec ($hash, "Today_Hour.*_PV.*");
          deleteReadingspec ($hash, "Today_Hour.*_Bat.*");
          deleteReadingspec ($hash, "powerTrigger_.*");
          deleteReadingspec ($hash, "Today_MaxPVforecast.*");
          deleteReadingspec ($hash, "Today_PVdeviation");
          deleteReadingspec ($hash, "Today_PVreal");

          for my $wdr (@widgetreadings) {
              deleteReadingspec ($hash, $wdr);
          }

          for my $n (1..24) {
              $n = sprintf "%02d", $n;

              deleteReadingspec ($hash, ".pvCorrectionFactor_${n}_cloudcover");               # verstecktes Reading löschen
              deleteReadingspec ($hash, ".pvCorrectionFactor_${n}_apipercentil");             # verstecktes Reading löschen
              deleteReadingspec ($hash, ".signaldone_${n}");                                  # verstecktes Reading löschen

              if (ReadingsVal ($name, "pvCorrectionFactor_Auto", "off") =~ /on/xs) {
                  deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*");
              }
          }

          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIcalls};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIrequests};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIcalls};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{solCastAPIcallMultiplier};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayMaxAPIcalls};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{idUser};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{token};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{verification_mode};

          delete $data{$type}{$name}{circular}{'99'}{initdayfeedin};
          delete $data{$type}{$name}{circular}{'99'}{initdaygcon};
          delete $data{$type}{$name}{circular}{'99'}{initdaybatintot};
          delete $data{$type}{$name}{circular}{'99'}{initdaybatouttot};
          delete $data{$type}{$name}{current}{sunriseToday};
          delete $data{$type}{$name}{current}{sunriseTodayTs};
          delete $data{$type}{$name}{current}{sunsetToday};
          delete $data{$type}{$name}{current}{sunsetTodayTs};

          $data{$type}{$name}{circular}{99}{ydayDvtn} = CircularVal ($hash, 99, 'tdayDvtn', '-');
          delete $data{$type}{$name}{circular}{'99'}{tdayDvtn};

          delete $data{$type}{$name}{pvhist}{$day};                                         # den (alten) aktuellen Tag aus History löschen
          Log3 ($name, 3, qq{$name - history day "$day" deleted});

          for my $c (keys %{$data{$type}{$name}{consumers}}) {                              # Planungsdaten regulär löschen
              next if(ConsumerVal ($hash, $c, "plandelete", "regular") ne "regular");

              deleteConsumerPlanning ($hash, $c);

              $data{$type}{$name}{consumers}{$c}{minutesOn}       = 0;
              $data{$type}{$name}{consumers}{$c}{numberDayStarts} = 0;
              $data{$type}{$name}{consumers}{$c}{onoff}           = 'off';
          }

          writeCacheToFile ($hash, "consumers", $csmcache.$name);                           # Cache File Consumer schreiben

          __createAdditionalEvents ($paref);                                                # zusätzliche Events erzeugen - PV Vorhersage bis Ende des kommenden Tages
          __delObsoleteAPIData     ($paref);                                                # Bereinigung obsoleter Daten im solcastapi Hash
          aiDelRawData             ($paref);                                                # KI Raw Daten löschen welche die maximale Haltezeit überschritten haben

          $paref->{taa} = 1;
          aiAddInstance ($paref);                                                           # AI füllen, trainieren und sichern
          delete $paref->{taa};

          periodicWriteCachefiles ($hash, 'bckp');                                          # Backup Files erstellen und alte Versionen löschen

          $hash->{HELPER}{H00DONE} = 1;
      }
  }
  else {
      delete $hash->{HELPER}{H00DONE};
  }

return;
}

#############################################################################
# zusätzliche Events erzeugen - PV Vorhersage bis Ende des kommenden Tages
#############################################################################
sub __createAdditionalEvents  {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};

  for my $idx (sort keys %{$data{$type}{$name}{nexthours}}) {
      my $nhts = NexthoursVal ($hash, $idx, 'starttime', undef);
      my $nhfc = NexthoursVal ($hash, $idx, 'pvfc',      undef);
      next if(!defined $nhts || !defined $nhfc);

      my ($dt, $h) = $nhts =~ /([\w-]+)\s(\d{2})/xs;
      storeReading ('AllPVforecastsToEvent', "$nhfc Wh", $dt." ".$h.":59:59");
  }

return;
}

#############################################################################
#            solcastapi Hash veraltete Daten löschen
#############################################################################
sub __delObsoleteAPIData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $date  = $paref->{date};                                                          # aktuelles Datum

  if (!keys %{$data{$type}{$name}{solcastapi}}) {
      return;
  }

  my $refts = timestringToTimestamp ($date.' 00:00:00');                               # Referenztimestring

  for my $idx (sort keys %{$data{$type}{$name}{solcastapi}}) {                         # alle Datumschlüssel kleiner aktueller Tag 00:00:00 selektieren
      for my $scd (sort keys %{$data{$type}{$name}{solcastapi}{$idx}}) {
          my $ds = timestringToTimestamp ($scd);
          delete $data{$type}{$name}{solcastapi}{$idx}{$scd} if ($ds && $ds < $refts);
      }
  }

  writeCacheToFile ($hash, "solcastapi", $scpicache.$name);                            # Cache File SolCast API Werte schreiben

  my @as = split ",", ReadingsVal($name, 'inverterStrings', '');
  return if(!scalar @as);

  for my $k (keys %{$data{$type}{$name}{strings}}) {                                   # veraltete Strings aus Strings-Hash löschen
      next if($k =~ /\?All/);
      next if($k ~~ @as);

      delete $data{$type}{$name}{strings}{$k};
      Log3 ($name, 2, "$name - obsolete PV-String >$k< was deleted from Strings-Hash");
  }

return;
}

################################################################
#    Wetter Werte aus dem angebenen Wetterdevice extrahieren
################################################################
sub _transferWeatherValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                      # Epoche Zeit
  my $chour = $paref->{chour};
  my $date  = $paref->{date};                                                                   # aktuelles Datum

  my $fcname = ReadingsVal($name, 'currentWeatherDev', "");                                     # Weather Forecast Device
  return if(!$fcname || !$defs{$fcname});

  my $err         = checkdwdattr ($name, $fcname, \@dweattrmust);
  $paref->{state} = $err if($err);

  debugLog ($paref, 'collectData', "collect Weather data - device: $fcname =>");

  my $time_str;
  my $type = $paref->{type};

  $paref->{fcname}                        = $fcname;
  my ($fc0_sr, $fc0_ss, $fc1_sr, $fc1_ss) = __sunRS ($paref);                                   # Sonnenauf- und untergang
  delete $paref->{fcname};

  $data{$type}{$name}{current}{sunriseToday}   = $date.' '.$fc0_sr.':00';
  $data{$type}{$name}{current}{sunriseTodayTs} = timestringToTimestamp ($date.' '.$fc0_sr.':00');

  $data{$type}{$name}{current}{sunsetToday}    = $date.' '.$fc0_ss.':00';
  $data{$type}{$name}{current}{sunsetTodayTs}  = timestringToTimestamp ($date.' '.$fc0_ss.':00');

  debugLog ($paref, 'collectData', "sunrise/sunset today: $fc0_sr / $fc0_ss, sunrise/sunset tomorrow: $fc1_sr / $fc1_ss");

  storeReading ('Today_SunRise',    $fc0_sr);
  storeReading ('Today_SunSet',     $fc0_ss);
  storeReading ('Tomorrow_SunRise', $fc1_sr);
  storeReading ('Tomorrow_SunSet',  $fc1_ss);

  my $fc0_sr_round = sprintf "%02d", (split ":", $fc0_sr)[0];
  my $fc0_ss_round = sprintf "%02d", (split ":", $fc0_ss)[0];
  my $fc1_sr_round = sprintf "%02d", (split ":", $fc1_sr)[0];
  my $fc1_ss_round = sprintf "%02d", (split ":", $fc1_ss)[0];

  for my $num (0..46) {
      my ($fd, $fh) = _calcDayHourMove ($chour, $num);
      last if($fd > 1);

      my $fh1   = $fh+1;
      my $fh2   = $fh1 == 24 ? 23 : $fh1;
      my $wid   = ReadingsNum ($fcname, "fc${fd}_${fh2}_ww",  -1);
      my $neff  = ReadingsNum ($fcname, "fc${fd}_${fh2}_Neff", 0);                             # Effektive Wolkendecke
      my $r101  = ReadingsNum ($fcname, "fc${fd}_${fh2}_R101", 0);                             # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
      my $temp  = ReadingsNum ($fcname, "fc${fd}_${fh2}_TTT",  0);                             # Außentemperatur

      my $don   = 1;                                                                           # es ist default "Tag"
      my $fhstr = sprintf "%02d", $fh;                                                         # hier kann Tag/Nacht-Grenze verstellt werden

      if($fd == 0 && ($fhstr lt $fc0_sr_round || $fhstr gt $fc0_ss_round)) {                   # Zeit vor Sonnenaufgang oder nach Sonnenuntergang heute
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
          $don  = 0;
      }
      elsif ($fd == 1 && ($fhstr lt $fc1_sr_round || $fhstr gt $fc1_ss_round)) {               # Zeit vor Sonnenaufgang oder nach Sonnenuntergang morgen
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
          $don  = 0;
      }

      my $txt = ReadingsVal($fcname, "fc${fd}_${fh2}_wwd", '');

      debugLog ($paref, 'collectData', "wid: fc${fd}_${fh1}_ww, val: $wid, txt: $txt, cc: $neff, rp: $r101, temp: $temp");

      $time_str                                             = "NextHour".sprintf "%02d", $num;
      $data{$type}{$name}{nexthours}{$time_str}{weatherid}  = $wid;
      $data{$type}{$name}{nexthours}{$time_str}{cloudcover} = $neff;
      $data{$type}{$name}{nexthours}{$time_str}{rainprob}   = $r101;
      $data{$type}{$name}{nexthours}{$time_str}{rainrange}  = rain2bin ($r101);
      $data{$type}{$name}{nexthours}{$time_str}{temp}       = $temp;
      $data{$type}{$name}{nexthours}{$time_str}{DoN}        = $don;

      if($num < 23 && $fh < 24) {                                                              # Ringspeicher Weather Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{weatherid}  = $wid;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{weathertxt} = $txt;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{wcc}        = $neff;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{wrp}        = $r101;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{temp}       = $temp;

          if($num == 0) {                                                                      # aktuelle Außentemperatur
              $data{$type}{$name}{current}{temp} = $temp;
          }
      }

      if($fd == 0 && $fh1) {                                                                   # Weather in pvhistory speichern
          $paref->{wid}      = $wid;
          $paref->{histname} = "weatherid";
          $paref->{nhour}    = sprintf("%02d",$fh1);
          setPVhistory ($paref);

          $paref->{wcc}      = $neff;
          $paref->{histname} = "weathercloudcover";
          setPVhistory ($paref);

          $paref->{wrp}      = $r101;
          $paref->{histname} = "weatherrainprob";
          setPVhistory ($paref);

          $paref->{temp}     = $temp;
          $paref->{histname} = "temperature";
          setPVhistory ($paref);

          delete $paref->{histname};
      }
  }

return;
}

################################################################
#   Sonnenauf- und untergang bei gesetzten global
#   latitude/longitude Koordinaten berechnen, sonst aus DWD
#   Device extrahieren
################################################################
sub __sunRS {
  my $paref  = shift;
  my $t      = $paref->{t};                                                       # aktuelle Zeit
  my $fcname = $paref->{fcname};

  my ($fc0_sr, $fc0_ss, $fc1_sr, $fc1_ss);

  my ($cset, $lat, $lon) = locCoordinates();

  if ($cset) {
      my $alt = 'HORIZON=-0.833';                                                 # default from https://metacpan.org/release/JFORGET/DateTime-Event-Sunrise-0.0505/view/lib/DateTime/Event/Sunrise.pm
      $fc0_sr = substr (sunrise_abs_dat ($t, $alt),         0, 5);                # SunRise heute
      $fc0_ss = substr (sunset_abs_dat  ($t, $alt),         0, 5);                # SunSet heute
      $fc1_sr = substr (sunrise_abs_dat ($t + 86400, $alt), 0, 5);                # SunRise morgen
      $fc1_ss = substr (sunset_abs_dat  ($t + 86400, $alt), 0, 5);                # SunSet morgen
  }
  else {                                                                          # Daten aus DWD Device holen
      $fc0_sr = ReadingsVal ($fcname, 'fc0_SunRise', '23:59');
      $fc0_ss = ReadingsVal ($fcname, 'fc0_SunSet',  '00:00');
      $fc1_sr = ReadingsVal ($fcname, 'fc1_SunRise', '23:59');
      $fc1_ss = ReadingsVal ($fcname, 'fc1_SunSet',  '00:00');
  }

return ($fc0_sr, $fc0_ss, $fc1_sr, $fc1_ss);
}

################################################################
#  Strahlungsvorhersage Werte aus solcastapi-Hash
#  übertragen und PV Vorhersage berechnen / in Nexthours
#  speichern
################################################################
sub _transferAPIRadiationValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $t     = $paref->{t};                                                                     # Epoche Zeit
  my $chour = $paref->{chour};
  my $date  = $paref->{date};

  return if(!keys %{$data{$type}{$name}{solcastapi}});

  my @strings = sort keys %{$data{$type}{$name}{strings}};
  return if(!@strings);

  my $lang = $paref->{lang};

  for my $num (0..47) {
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);

      if($fd > 1) {                                                                           # überhängende Werte löschen
          delete $data{$type}{$name}{nexthours}{"NextHour".sprintf "%02d", $num};
          next;
      }

      my $fh1      = $fh+1;
      my $wantts   = (timestringToTimestamp ($date.' '.$chour.':00:00')) + ($num * 3600);
      my $wantdt   = (timestampToTimestring ($wantts, $lang))[1];

      my $time_str = 'NextHour'.sprintf "%02d", $num;
      my ($hod)    = $wantdt =~ /\s(\d{2}):/xs;
      $hod         = sprintf "%02d", int $hod + 1;                                            # Stunde des Tages

      my $rad      = SolCastAPIVal ($hash, '?All', $wantdt, 'Rad1h', undef);

      my $params = {
          hash    => $hash,
          name    => $name,
          type    => $type,
          wantdt  => $wantdt,
          hod     => $hod,
          nhidx   => $time_str,
          num     => $num,
          fh1     => $fh1,
          fd      => $fd,
          day     => $paref->{day},
          debug   => $paref->{debug}
      };

      my $est = __calcPVestimates ($params);

      $data{$type}{$name}{nexthours}{$time_str}{pvapifc}   = $est;                            # durch API gelieferte PV Forecast
      $data{$type}{$name}{nexthours}{$time_str}{starttime} = $wantdt;
      $data{$type}{$name}{nexthours}{$time_str}{hourofday} = $hod;
      $data{$type}{$name}{nexthours}{$time_str}{today}     = $fd == 0 ? 1 : 0;
      $data{$type}{$name}{nexthours}{$time_str}{rad1h}     = $rad;

      my ($err, $pvaifc) = aiGetResult ($params);                                             # KI Entscheidungen abfragen
      my $pvfc;

      if (!$err) {
          $data{$type}{$name}{nexthours}{$time_str}{pvaifc} = $pvaifc;                        # durch AI gelieferte PV Forecast
          $data{$type}{$name}{nexthours}{$time_str}{pvfc}   = $pvaifc;
          $data{$type}{$name}{nexthours}{$time_str}{aihit}  = 1;

          $pvfc = $pvaifc;
      }
      else {
          delete $data{$type}{$name}{nexthours}{$time_str}{pvaifc};
          $data{$type}{$name}{nexthours}{$time_str}{pvfc}  = $est;
          $data{$type}{$name}{nexthours}{$time_str}{aihit} = 0;

          $pvfc = $est;
      }

      if ($num < 23 && $fh < 24) {                                                            # Ringspeicher PV forecast Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
          $data{$type}{$name}{circular}{sprintf "%02d",$fh1}{pvapifc} = NexthoursVal ($hash, $time_str, 'pvapifc', undef);
          $data{$type}{$name}{circular}{sprintf "%02d",$fh1}{pvfc}    = $pvfc;
          $data{$type}{$name}{circular}{sprintf "%02d",$fh1}{pvaifc}  = NexthoursVal ($hash, $time_str, 'pvaifc',  undef);
          $data{$type}{$name}{circular}{sprintf "%02d",$fh1}{aihit}   = NexthoursVal ($hash, $time_str, 'aihit',       0);
      }

      if($fd == 0 && int $pvfc > 0) {                                                         # Vorhersagedaten des aktuellen Tages zum manuellen Vergleich in Reading speichern
          storeReading ('Today_Hour'.sprintf ("%02d",$fh1).'_PVforecast', "$pvfc Wh");
      }

      if($fd == 0 && $fh1) {
          $paref->{nhour}    = sprintf "%02d", $fh1;

          $paref->{calcpv}   = $pvfc;
          $paref->{histname} = 'pvfc';
          setPVhistory ($paref);

          $paref->{rad1h}    = $rad;
          $paref->{histname} = 'radiation';
          setPVhistory ($paref);

          delete $paref->{histname};
      }
  }

  storeReading ('.lastupdateForecastValues', $t);                                             # Statusreading letzter update

return;
}

##################################################################################################
#                   !!!! NACHFOLGENDE INFO GILT NUR BEI DWD RAD1H VERWENDUNG !!!!
#                   #############################################################
#
#            PV Forecast Rad1h in kWh / Wh
# Berechnung nach Formel 1 aus http://www.ing-büro-junge.de/html/photovoltaik.html:
#
#    * Faktor für Umwandlung kJ in kWh:   0.00027778
#    * Eigene Modulfläche in qm z.B.:     31,04
#    * Wirkungsgrad der Module in % z.B.: 16,52
#    * Wirkungsgrad WR in % z.B.:         98,3
#    * Korrekturwerte wegen Ausrichtung/Verschattung etc.
#
# Die Formel wäre dann:
# Ertrag in Wh = Rad1h * 0.00027778 * 31,04 qm * 16,52% * 98,3% * 100% * 1000
#
# Berechnung nach Formel 2 aus http://www.ing-büro-junge.de/html/photovoltaik.html:
#
#    * Globalstrahlung:                G =  kJ / m2
#    * Korrektur mit Flächenfaktor f:  Gk = G * f
#    * Globalstrahlung (STC):          1 kW/m2
#    * Peak Leistung String (kWp):     Pnenn = x kW
#    * Performance Ratio:              PR (typisch 0,85 bis 0,9)
#    * weitere Korrekturwerte für Regen, Wolken etc.: Korr
#
#    pv (kWh) = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr
#    pv (Wh)  = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr * 1000
#
# Die Abhängigkeit der Strahlungsleistung der Sonnenenergie nach Wetterlage und Jahreszeit ist
# hier beschrieben:
# https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
#
# !!! PV Berechnungsgrundlagen !!!
# https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/ertrag
# http://www.ing-büro-junge.de/html/photovoltaik.html
#
##################################################################################################
sub __calcPVestimates {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $wantdt  = $paref->{wantdt};
  my $hod     = $paref->{hod};
  my $fd      = $paref->{fd};
  my $num     = $paref->{num};
  my $debug   = $paref->{debug};

  my $reld    = $fd == 0 ? "today" : $fd == 1 ? "tomorrow" : "unknown";

  my $rainprob    = NexthoursVal ($hash, "NextHour".sprintf ("%02d", $num), "rainprob", 0);           # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
  my $cloudcover  = NexthoursVal ($hash, "NextHour".sprintf ("%02d", $num), "cloudcover", 0);         # effektive Wolkendecke nächste Stunde X
  my $temp        = NexthoursVal ($hash, "NextHour".sprintf ("%02d",$num),  "temp", $tempbasedef);    # vorhergesagte Temperatur Stunde X
  my ($acu, $aln) = isAutoCorrUsed ($name);

  $paref->{cloudcover}  = $cloudcover;
  my ($hc, $hq)         = ___readCandQ ($paref);                                                      # liest den anzuwendenden Korrekturfaktor
  delete $paref->{cloudcover};

  my ($lh,$sq,$peakloss, $modtemp);
  my $pvsum   = 0;
  my $peaksum = 0;

  for my $string (sort keys %{$data{$type}{$name}{strings}}) {
      my $peak = StringVal ($hash, $string, 'peak', 0);                                               # String Peak (kWp)

      if ($acu =~ /on_complex/xs) {
          $paref->{peak}        = $peak;
          $paref->{cloudcover}  = $cloudcover;
          $paref->{temp}        = $temp;

          ($peakloss, $modtemp) = ___calcPeaklossByTemp ($paref);                                     # Reduktion Peakleistung durch Temperaturkoeffizienten der Module (vorzeichengehaftet)
          $peak                += $peakloss;

          delete $paref->{peak};
          delete $paref->{cloudcover};
          delete $paref->{temp};
      }

      $peak  *= 1000;
      my $est = SolCastAPIVal ($hash, $string, $wantdt, 'pv_estimate50', 0) * $hc;                    # Korrekturfaktor anwenden
      my $pv  = sprintf "%.1f", $est;

      if ($debug =~ /radiationProcess/xs) {
          $lh = {                                                                                     # Log-Hash zur Ausgabe
              "modulePeakString"               => $peak.    " W",
              "Estimated PV generation (raw)"  => $est.     " Wh",
              "Estimated PV generation (calc)" => $pv.      " Wh",
          };

          if ($acu =~ /on_complex/xs) {
              $lh->{"Module Temp (calculated)"}       = $modtemp. " &deg;C";
              $lh->{"Loss String Peak Power by Temp"} = $peakloss." kWP";
          }

          $sq = q{};
          for my $idx (sort keys %{$lh}) {
              $sq .= $idx." => ".$lh->{$idx}."\n";
          }

          Log3 ($name, 1, "$name DEBUG> PV estimate for $reld Hour ".sprintf ("%02d", $hod)." string $string ->\n$sq");
      }

      $pvsum   += $pv;
      $peaksum += $peak;
  }

  $data{$type}{$name}{current}{allstringspeak} = $peaksum;                                           # temperaturbedingte Korrektur der installierten Peakleistung in W

  $pvsum  = $peaksum if($peaksum && $pvsum > $peaksum);                                              # Vorhersage nicht größer als die Summe aller PV-Strings Peak

  my $invcapacity = CurrentVal ($hash, 'invertercapacity', 0);                                       # Max. Leistung des Invertrs

  if ($invcapacity && $pvsum > $invcapacity) {
      $pvsum = $invcapacity;                                                                         # PV Vorhersage auf WR Kapazität begrenzen

      debugLog ($paref, "radiationProcess", "PV forecast start time $wantdt limited to $pvsum Watt due to inverter capacity");
  }

  my $logao         = qq{};
  $paref->{pvsum}   = $pvsum;
  $paref->{peaksum} = $peaksum;
  ($pvsum, $logao)  = ___70percentRule ($paref);

  if ($debug =~ /radiationProcess/xs) {
      $lh = {                                                                                        # Log-Hash zur Ausgabe
          "Starttime"                   => $wantdt,
          "Forecasted temperature"      => $temp." &deg;C",
          "Cloudcover"                  => $cloudcover,
          "Rainprob"                    => $rainprob,
          "Use PV Correction"           => ($acu ? $acu : 'no'),
          "PV correction factor"        => $hc,
          "PV correction quality"       => $hq,
          "PV generation forecast"      => $pvsum." Wh ".$logao,
      };

      $sq = q{};
      for my $idx (sort keys %{$lh}) {
          $sq .= $idx." => ".$lh->{$idx}."\n";
      }

      Log3 ($name, 1, "$name DEBUG> PV estimate for $reld Hour ".sprintf ("%02d", $hod)." summary: \n$sq");
  }

return $pvsum;
}

######################################################################
#  Complex:
#  Liest bewölkungsabhängige Korrekturfaktor/Qualität und
#  speichert die Werte im Nexthours / pvHistory Hash
#
#  Simple:
#  Liest Korrekturfaktor/Qualität aus pvCircular percentile und
#  speichert die Werte im Nexthours / pvHistory Hash
######################################################################
sub ___readCandQ {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $num   = $paref->{num};
  my $fh1   = $paref->{fh1};
  my $fd    = $paref->{fd};
  my $cc    = $paref->{cloudcover};

  my ($acu, $aln) = isAutoCorrUsed ($name);                                                           # Autokorrekturmodus
  my $hc          = ReadingsNum ($name, 'pvCorrectionFactor_'.sprintf("%02d",$fh1), 1.00);            # Voreinstellung RAW-Korrekturfaktor
  my $hq          = '-';                                                                              # keine Qualität definiert

  delete $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{cloudrange};

  if ($acu =~ /on_complex/xs) {                                                                       # Autokorrektur complex soll genutzt werden
      my $range  = cloud2bin ($cc);                                                                   # Range errechnen
      ($hc, $hq) = CircularAutokorrVal ($hash, sprintf("%02d",$fh1), $range, undef);                  # Korrekturfaktor/Qualität der Stunde des Tages (complex)
      $hq      //= '-';
      $hc      //= 1;                                                                                 # Korrekturfaktor = 1 (keine Korrektur)                                                                                                        # keine Qualität definiert
      $hc        = 1 if(1 * $hc == 0);                                                                # 0.0-Werte ignorieren (Schleifengefahr)

      $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{cloudrange} = $range;
  }
  elsif ($acu =~ /on_simple/xs) {
      ($hc, $hq) = CircularAutokorrVal ($hash, sprintf("%02d",$fh1), 'percentile', undef);            # Korrekturfaktor/Qualität der Stunde des Tages (simple)
      $hq      //= '-';
      $hc      //= 1;                                                                                 # Korrekturfaktor = 1
      $hc        = 1 if(1 * $hc == 0);                                                                # 0.0-Werte ignorieren (Schleifengefahr)
  }
  else {                                                                                              # keine Autokorrektur
      ($hc, $hq) = CircularAutokorrVal ($hash, sprintf("%02d",$fh1), 'percentile', undef);            # Korrekturfaktor/Qualität der Stunde des Tages (simple)
      $hq      //= '-';
      $hc        = 1;
  }

  $hc = sprintf "%.2f", $hc;

  $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{pvcorrf} = $hc."/".$hq;

  if($fd == 0 && $fh1) {
      $paref->{pvcorrf}  = $hc."/".$hq;
      $paref->{nhour}    = sprintf "%02d", $fh1;
      $paref->{histname} = 'pvcorrfactor';

      setPVhistory ($paref);

      delete $paref->{histname};
  }

return ($hc, $hq);
}

###################################################################
# Zellen Leistungskorrektur Einfluss durch Wärmekoeffizienten
# berechnen
#
# Die Nominalleistung der Module wird bei 25 Grad
# Umgebungstemperatur und bei 1.000 Watt Sonneneinstrahlung
# gemessen.
# Steigt die Temperatur um 1 Grad Celsius sinkt die Modulleistung
# typisch um 0,4 Prozent. Solartellen können im Sommer 70°C heiß
# werden.
#
# Das würde für eine 10 kWp Photovoltaikanlage folgenden
# Leistungsverlust bedeuten:
#
#       Leistungsverlust = -0,4%/K * 45K * 10 kWp = 1,8 kWp
#
# https://www.enerix.de/photovoltaiklexikon/temperaturkoeffizient/
#
###################################################################
sub ___calcPeaklossByTemp {
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $peak       = $paref->{peak}       // return (0,0);
  my $cloudcover = $paref->{cloudcover} // return (0,0);                                    # vorhergesagte Wolkendecke Stunde X
  my $temp       = $paref->{temp}       // return (0,0);                                    # vorhergesagte Temperatur Stunde X

  my $modtemp  = $temp + ($tempmodinc * (1 - ($cloudcover/100)));                           # kalkulierte Modultemperatur
  my $peakloss = sprintf "%.2f", $tempcoeffdef * ($temp - $tempbasedef) * $peak / 100;

return ($peakloss, $modtemp);
}

################################################################
#                 70% Regel kalkulieren
################################################################
sub ___70percentRule {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $pvsum   = $paref->{pvsum};
  my $peaksum = $paref->{peaksum};
  my $num     = $paref->{num};                                                          # Nexthour

  my $logao = qq{};
  my $confc = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "confc", 0);
  my $max70 = $peaksum/100 * 70;

  if(AttrVal ($name, "affect70percentRule", "0") eq "1" && $pvsum > $max70) {
      $pvsum = $max70;
      $logao = qq{(reduced by 70 percent rule)};
  }

  if(AttrVal ($name, "affect70percentRule", "0") eq "dynamic" && $pvsum > $max70 + $confc) {
      $pvsum = $max70 + $confc;
      $logao = qq{(reduced by 70 percent dynamic rule)};
  }

  $pvsum = int $pvsum;

return ($pvsum, $logao);
}

################################################################
#    den Maximalwert PV Vorhersage für Heute ermitteln
################################################################
sub _calcMaxEstimateToday {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $date  = $paref->{date};

  my $maxest = 0;
  my $maxtim = '-';

  for my $h (1..23) {
      my $pvfc = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVforecast", 0);
      next if($pvfc <= $maxest);

      $maxtim = $date.' '.sprintf("%02d",$h-1).':00:00';
      $maxest = $pvfc;
  }

  return if(!$maxest);

  storeReading ('Today_MaxPVforecast',     $maxest.' Wh');
  storeReading ('Today_MaxPVforecastTime', $maxtim);

return;
}

################################################################
#    Werte Inverter Device ermitteln und übertragen
################################################################
sub _transferInverterValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                    # aktuelle Unix-Zeit
  my $chour = $paref->{chour};
  my $day   = $paref->{day};

  my $indev  = ReadingsVal($name, 'currentInverterDev', '');
  my ($a,$h) = parseParams ($indev);
  $indev     = $a->[0] // "";
  return if(!$indev || !$defs{$indev});

  my $type  = $paref->{type};

  my ($pvread,$pvunit) = split ":", $h->{pv};                                                 # Readingname/Unit für aktuelle PV Erzeugung
  my ($edread,$etunit) = split ":", $h->{etotal};                                             # Readingname/Unit für Energie total (PV Erzeugung)

  $data{$type}{$name}{current}{invertercapacity} = $h->{capacity} if($h->{capacity});         # optionale Angabe max. WR-Leistung

  return if(!$pvread || !$edread);

  my $pvuf = $pvunit =~ /^kW$/xi ? 1000 : 1;
  my $pv   = ReadingsNum ($indev, $pvread, 0) * $pvuf;                                        # aktuelle Erzeugung (W)
  $pv      = $pv < 0 ? 0 : sprintf("%.0f", $pv);                                              # Forum: https://forum.fhem.de/index.php/topic,117864.msg1159718.html#msg1159718, https://forum.fhem.de/index.php/topic,117864.msg1166201.html#msg1166201

  storeReading ('Current_PV', $pv.' W');
  $data{$type}{$name}{current}{generation} = $pv;                                             # Hilfshash Wert current generation Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251

  push @{$data{$type}{$name}{current}{genslidereg}}, $pv;                                     # Schieberegister PV Erzeugung
  limitArray ($data{$type}{$name}{current}{genslidereg}, $defslidenum);

  my $etuf   = $etunit =~ /^kWh$/xi ? 1000 : 1;
  my $etotal = ReadingsNum ($indev, $edread, 0) * $etuf;                                      # Erzeugung total (Wh)

  debugLog ($paref, "collectData", "collect Inverter data - device: $indev =>");
  debugLog ($paref, "collectData", "pv: $pv W, etotal: $etotal Wh");

  my $nhour    = $chour + 1;
  my $histetot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "etotal", 0);               # etotal zu Beginn einer Stunde

  my $ethishour;
  if (!$histetot) {                                                                           # etotal der aktuelle Stunde gesetzt ?
      $paref->{etotal}   = $etotal;
      $paref->{nhour}    = sprintf("%02d",$nhour);
      $paref->{histname} = 'etotal';

      setPVhistory ($paref);

      delete $paref->{histname};

      my $etot   = CurrentVal ($hash, "etotal", $etotal);
      $ethishour = int ($etotal - $etot);
  }
  else {
      $ethishour = int ($etotal - $histetot);
  }

  $data{$type}{$name}{current}{etotal} = $etotal;                                             # aktuellen etotal des WR speichern

  if ($ethishour < 0) {
      $ethishour = 0;
  }

  storeReading ('Today_Hour'.sprintf("%02d",$nhour).'_PVreal', $ethishour.' Wh');
  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{pvrl} = $ethishour;                   # Ringspeicher PV real Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

  my ($acu, $aln) = isAutoCorrUsed ($name);

  $paref->{ethishour} = $ethishour;
  $paref->{nhour}     = sprintf "%02d", $nhour;
  $paref->{histname}  = 'pvrl';
  $paref->{pvrlvd}    = $aln;                                                                 # 1: beim Learning berücksichtigen, 0: nicht

  setPVhistory ($paref);

  delete $paref->{pvrlvd};
  delete $paref->{histname};

return;
}

################################################################
#    Werte Meter Device ermitteln und übertragen
################################################################
sub _transferMeterValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};
  my $chour = $paref->{chour};

  my $medev  = ReadingsVal($name, "currentMeterDev", "");                                     # aktuelles Meter device
  my ($a,$h) = parseParams ($medev);
  $medev     = $a->[0] // "";
  return if(!$medev || !$defs{$medev});

  my $type = $paref->{type};

  my ($gc,$gcunit) = split ":", $h->{gcon};                                                   # Readingname/Unit für aktuellen Netzbezug
  my ($gf,$gfunit) = split ":", $h->{gfeedin};                                                # Readingname/Unit für aktuelle Netzeinspeisung
  my ($gt,$ctunit) = split ":", $h->{contotal};                                               # Readingname/Unit für Bezug total
  my ($ft,$ftunit) = split ":", $h->{feedtotal};                                              # Readingname/Unit für Einspeisung total

  return if(!$gc || !$gf || !$gt || !$ft);

  $gfunit //= $gcunit;
  $gcunit //= $gfunit;

  my ($gco,$gfin);

  my $gcuf = $gcunit =~ /^kW$/xi ? 1000 : 1;
  my $gfuf = $gfunit =~ /^kW$/xi ? 1000 : 1;

  $gco  = ReadingsNum ($medev, $gc, 0) * $gcuf;                                               # aktueller Bezug (W)
  $gfin = ReadingsNum ($medev, $gf, 0) * $gfuf;                                               # aktuelle Einspeisung (W)

  my $params;

  if ($gc eq "-gfeedin") {                                                                    # Spezialfall gcon bei neg. gfeedin                                                                                      # Spezialfall: bei negativen gfeedin -> $gco = abs($gf), $gf = 0
      $params = {
          dev  => $medev,
          rdg  => $gf,
          rdgf => $gfuf
      };

      ($gfin,$gco) = substSpecialCases ($params);
  }

  if ($gf eq "-gcon") {                                                                              # Spezialfall gfeedin bei neg. gcon
      $params = {
          dev  => $medev,
          rdg  => $gc,
          rdgf => $gcuf
      };

      ($gco,$gfin) = substSpecialCases ($params);
  }

  storeReading ('Current_GridConsumption', (int $gco).' W');
  $data{$type}{$name}{current}{gridconsumption} = int $gco;                                          # Hilfshash Wert current grid consumption Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251

  storeReading ('Current_GridFeedIn', (int $gfin).' W');
  $data{$type}{$name}{current}{gridfeedin} = int $gfin;                                              # Hilfshash Wert current grid Feed in

  my $ctuf    = $ctunit =~ /^kWh$/xi ? 1000 : 1;
  my $gctotal = ReadingsNum ($medev, $gt, 0) * $ctuf;                                                # Bezug total (Wh)

  my $ftuf    = $ftunit =~ /^kWh$/xi ? 1000 : 1;
  my $fitotal = ReadingsNum ($medev, $ft, 0) * $ftuf;                                                # Einspeisung total (Wh)

  $data{$type}{$name}{circular}{99}{gridcontotal} = $gctotal;                                        # Total Netzbezug speichern
  $data{$type}{$name}{circular}{99}{feedintotal}  = $fitotal;                                        # Total Feedin speichern

  debugLog ($paref, "collectData", "collect Meter data - device: $medev =>");
  debugLog ($paref, "collectData", "gcon: $gco W, gfeedin: $gfin W, contotal: $gctotal Wh, feedtotal: $fitotal Wh");

  my $gcdaypast = 0;
  my $gfdaypast = 0;

  for my $hour (0..int $chour) {                                                                     # alle bisherigen Erzeugungen des Tages summieren
      $gcdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridConsumption", 0);
      $gfdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridFeedIn",      0);
  }

  my $docon = 0;

  if ($gcdaypast == 0) {                                                                             # Management der Stundenberechnung auf Basis Totalwerte GridConsumtion
      if (defined CircularVal ($hash, 99, 'initdaygcon', undef)) {
          $docon = 1;
      }
      else {
          $data{$type}{$name}{circular}{99}{initdaygcon} = $gctotal;
      }
  }
  elsif (!defined CircularVal ($hash, 99, 'initdaygcon', undef)) {
      $data{$type}{$name}{circular}{99}{initdaygcon} = $gctotal - $gcdaypast - ReadingsNum ($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  }
  else {
      $docon = 1;
  }

  if ($docon) {
      my $gctotthishour = int ($gctotal - ($gcdaypast + CircularVal ($hash, 99, 'initdaygcon', 0)));

      if ($gctotthishour < 0) {
          $gctotthishour = 0;
      }

      my $nhour = $chour+1;
      storeReading ('Today_Hour'.sprintf("%02d",$nhour).'_GridConsumption', $gctotthishour.' Wh');
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gcons} = $gctotthishour;                  # Hilfshash Wert Bezug (Wh) Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

      $paref->{gctotthishour} = $gctotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "cons";
      setPVhistory ($paref);
      delete $paref->{histname};
  }

  my $dofeed = 0;

  if ($gfdaypast == 0) {                                                                              # Management der Stundenberechnung auf Basis Totalwerte GridFeedIn
      if (defined CircularVal ($hash, 99, 'initdayfeedin', undef)) {
          $dofeed = 1;
      }
      else {
          $data{$type}{$name}{circular}{99}{initdayfeedin} = $fitotal;
      }
  }
  elsif (!defined CircularVal ($hash, 99, 'initdayfeedin', undef)) {
      $data{$type}{$name}{circular}{99}{initdayfeedin} = $fitotal - $gfdaypast - ReadingsNum ($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridFeedIn", 0);
  }
  else {
      $dofeed = 1;
  }

  if ($dofeed) {
      my $gftotthishour = int ($fitotal - ($gfdaypast + CircularVal ($hash, 99, 'initdayfeedin', 0)));

      if ($gftotthishour < 0) {
          $gftotthishour = 0;
      }

      my $nhour = $chour+1;
      storeReading ('Today_Hour'.sprintf("%02d",$nhour).'_GridFeedIn', $gftotthishour.' Wh');
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gfeedin} = $gftotthishour;

      $paref->{gftotthishour} = $gftotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "gfeedin";
      setPVhistory ($paref);
      delete $paref->{histname};
  }

return;
}

################################################################
#                    Batteriewerte sammeln
################################################################
sub _transferBatteryValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  my $day   = $paref->{day};

  my ($badev,$a,$h) = isBatteryUsed ($name);
  return if(!$badev);

  my $type = $paref->{type};

  my ($pin,$piunit)    = split ":", $h->{pin};                                                # Readingname/Unit für aktuelle Batterieladung
  my ($pou,$pounit)    = split ":", $h->{pout};                                               # Readingname/Unit für aktuelle Batterieentladung
  my ($bin,$binunit)   = split ":", $h->{intotal}  // "-:-";                                  # Readingname/Unit der total in die Batterie eingespeisten Energie (Zähler)
  my ($bout,$boutunit) = split ":", $h->{outtotal} // "-:-";                                  # Readingname/Unit der total aus der Batterie entnommenen Energie (Zähler)
  my $batchr           = $h->{charge} // "";                                                  # Readingname Ladezustand Batterie
  my $instcap          = $h->{cap};                                                           # numerischer Wert (Wh) oder Readingname installierte Batteriekapazität

  return if(!$pin || !$pou);

  $pounit   //= $piunit;
  $piunit   //= $pounit;
  $boutunit //= $binunit;
  $binunit  //= $boutunit;

  my $piuf      = $piunit   =~ /^kW$/xi  ? 1000 : 1;
  my $pouf      = $pounit   =~ /^kW$/xi  ? 1000 : 1;
  my $binuf     = $binunit  =~ /^kWh$/xi ? 1000 : 1;
  my $boutuf    = $boutunit =~ /^kWh$/xi ? 1000 : 1;

  my $pbo       = ReadingsNum ($badev, $pou,    0) * $pouf;                                    # aktuelle Batterieentladung (W)
  my $pbi       = ReadingsNum ($badev, $pin,    0) * $piuf;                                    # aktueller Batterieladung (W)
  my $btotout   = ReadingsNum ($badev, $bout,   0) * $boutuf;                                  # totale Batterieentladung (Wh)
  my $btotin    = ReadingsNum ($badev, $bin,    0) * $binuf;                                   # totale Batterieladung (Wh)
  my $soc       = ReadingsNum ($badev, $batchr, 0);

  if ($instcap && !isNumeric ($instcap)) {                                                     # wenn $instcap Reading Wert abfragen
      my ($bcapr,$bcapunit) = split ':', $instcap;
      $bcapunit           //= 'Wh';
      $instcap              = ReadingsNum ($badev, $bcapr, 0);
      $instcap              = $instcap * ($bcapunit =~ /^kWh$/xi ? 1000 : 1);
  }

  my $debug = $paref->{debug};
  if ($debug =~ /collectData/x) {
      Log3 ($name, 1, "$name DEBUG> collect Battery data: device=$badev =>");
      Log3 ($name, 1, "$name DEBUG> pin=$pbi W, pout=$pbo W, totalin: $btotin Wh, totalout: $btotout Wh, soc: $soc");
  }

  my $params;

  if ($pin eq "-pout") {                                                                      # Spezialfall pin bei neg. pout
      $params = {
          dev  => $badev,
          rdg  => $pou,
          rdgf => $pouf
      };

      ($pbo,$pbi) = substSpecialCases ($params);
  }

  if ($pou eq "-pin") {                                                                        # Spezialfall pout bei neg. pin
      $params = {
          dev  => $badev,
          rdg  => $pin,
          rdgf => $piuf
      };

      ($pbi,$pbo) = substSpecialCases ($params);
  }

  # Batterielade-, enladeenergie in Circular speichern
  ######################################################
  if (!defined CircularVal ($hash, 99, 'initdaybatintot', undef)) {
      $data{$type}{$name}{circular}{99}{initdaybatintot} = $btotin;                            # total Batterieladung zu Tagbeginn (Wh)
  }

  if (!defined CircularVal ($hash, 99, 'initdaybatouttot', undef)) {                           # total Batterieentladung zu Tagbeginn (Wh)
      $data{$type}{$name}{circular}{99}{initdaybatouttot} = $btotout;
  }

  $data{$type}{$name}{circular}{99}{batintot}  = $btotin;                                      # aktuell total Batterieladung
  $data{$type}{$name}{circular}{99}{batouttot} = $btotout;                                     # aktuell total Batterieentladung

  my $nhour = $chour+1;

  # Batterieladung aktuelle Stunde in pvHistory speichern
  #########################################################
  my $histbatintot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "batintotal", undef);    # totale Batterieladung zu Beginn einer Stunde

  my $batinthishour;
  if (!defined $histbatintot) {                                                                # totale Batterieladung der aktuelle Stunde gesetzt ?
      $paref->{batintotal} = $btotin;
      $paref->{nhour}      = sprintf("%02d",$nhour);
      $paref->{histname}   = 'batintotal';
      setPVhistory ($paref);
      delete $paref->{histname};

      my $bitot      = CurrentVal ($hash, "batintotal", $btotin);
      $batinthishour = int ($btotin - $bitot);
  }
  else {
      $batinthishour = int ($btotin - $histbatintot);
  }

  if ($batinthishour < 0) {
      $batinthishour = 0;
  }

  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{batin} = $batinthishour;                # Ringspeicher Battery In Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

  $paref->{batinthishour} = $batinthishour;
  $paref->{nhour}         = sprintf "%02d", $nhour;
  $paref->{histname}      = 'batinthishour';
  setPVhistory ($paref);
  delete $paref->{histname};

  # Batterieentladung aktuelle Stunde in pvHistory speichern
  ############################################################
  my $histbatouttot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), 'batouttotal', undef);   # totale Betterieladung zu Beginn einer Stunde

  my $batoutthishour;
  if(!defined $histbatouttot) {                                                                 # totale Betterieladung der aktuelle Stunde gesetzt ?
      $paref->{batouttotal} = $btotout;
      $paref->{nhour}       = sprintf("%02d",$nhour);
      $paref->{histname}    = 'batouttotal';
      setPVhistory ($paref);
      delete $paref->{histname};

      my $botot       = CurrentVal ($hash, 'batouttotal', $btotout);
      $batoutthishour = int ($btotout - $botot);
  }
  else {
      $batoutthishour = int ($btotout - $histbatouttot);
  }

  if($batoutthishour < 0) {
      $batoutthishour = 0;
  }

  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{batout} = $batoutthishour;             # Ringspeicher Battery In Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

  $paref->{batoutthishour} = $batoutthishour;
  $paref->{nhour}          = sprintf("%02d",$nhour);
  $paref->{histname}       = 'batoutthishour';
  setPVhistory ($paref);
  delete $paref->{histname};

  # täglichen max. SOC in pvHistory speichern
  #############################################
  my $batmaxsoc = HistoryVal ($hash, $day, 99, 'batmaxsoc', 0);                               # gespeicherter max. SOC des Tages

  if ($soc >= $batmaxsoc) {
      $paref->{batmaxsoc} = $soc;
      $paref->{nhour}     = 99;
      $paref->{histname}  = 'batmaxsoc';
      setPVhistory ($paref);
      delete $paref->{histname};
  }

  ######

  storeReading ('Today_Hour'.sprintf("%02d",$nhour).'_BatIn', $batinthishour.' Wh');
  storeReading ('Today_Hour'.sprintf("%02d",$nhour).'_BatOut', $batoutthishour.' Wh');
  storeReading ('Current_PowerBatIn',  (int $pbi).' W');
  storeReading ('Current_PowerBatOut', (int $pbo).' W');
  storeReading ('Current_BatCharge',   $soc.' %');

  $data{$type}{$name}{current}{powerbatin}  = int $pbi;                                       # Hilfshash Wert aktuelle Batterieladung
  $data{$type}{$name}{current}{powerbatout} = int $pbo;                                       # Hilfshash Wert aktuelle Batterieentladung
  $data{$type}{$name}{current}{batcharge}   = $soc;                                           # aktuelle Batterieladung
  $data{$type}{$name}{current}{batinstcap}  = $instcap;                                       # installierte Batteriekapazität

  push @{$data{$type}{$name}{current}{socslidereg}}, $soc;                                    # Schieberegister Batterie SOC
  limitArray ($data{$type}{$name}{current}{socslidereg}, $defslidenum);

return;
}

################################################################
#          Batterie SOC optimalen Sollwert berechnen
################################################################
sub _batSocTarget {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $t     = $paref->{t};                                                    # aktuelle Zeit

  return if(!isBatteryUsed ($name));

  my $oldd2care = CircularVal ($hash, 99, 'days2care',            0);
  my $ltsmsr    = CircularVal ($hash, 99, 'lastTsMaxSocRchd', undef);
  my $batcharge = CurrentVal  ($hash, 'batcharge',                0);         # aktuelle Ladung in %

  __batSaveSocKeyFigures ($paref) if(!$ltsmsr || $batcharge >= $maxSoCdef || $oldd2care < 0);

  my $cgbt                                  = AttrVal ($name, 'ctrlBatSocManagement', undef);
  my ($lowSoc, $upSoc, $maxsoc, $careCycle) = __parseAttrBatSoc ($name, $cgbt);
  return if(!$lowSoc ||!$upSoc);

  $paref->{careCycle} = $careCycle;
  __batSaveSocKeyFigures ($paref) if($batcharge >= $maxsoc);
  delete $paref->{careCycle};

  my $nt;
  my $chargereq  = 0;                                                             # Ladeanforderung wenn SoC unter Minimum SoC gefallen ist
  my $target     = $lowSoc;
  my $yday       = strftime "%d", localtime($t - 86400);                          # Vortag  (range 01 to 31)
  my $batymaxsoc = HistoryVal ($hash, $yday, 99, 'batmaxsoc',       0);           # gespeicherter max. SOC des Vortages
  my $batysetsoc = HistoryVal ($hash, $yday, 99, 'batsetsoc', $lowSoc);           # gespeicherter SOC Sollwert des Vortages

  $target = $batymaxsoc <  $maxsoc ? $batysetsoc + $batSocChgDay :
            $batymaxsoc >= $maxsoc ? $batysetsoc - $batSocChgDay :
            $batysetsoc;                                                          # neuer Min SOC für den laufenden Tag

  debugLog ($paref, 'batteryManagement', "SoC calc Step1 - compare with SoC history -> new Target: $target %");

  ## Pflege-SoC (Soll SoC $maxSoCdef bei $batSocChgDay % Steigerung p. Tag)
  ###########################################################################
  my $sunset  = CurrentVal ($hash, 'sunsetTodayTs', $t);
  my $delayts = $sunset - 5400;                                                   # Pflege-SoC/Erhöhung SoC erst ab 1,5h vor Sonnenuntergang berechnen/anwenden
  my $la      = '';

  if ($t > $delayts) {
      my $ntsmsc    = CircularVal ($hash, 99, 'nextTsMaxSocChge', $t);
      my $days2care = ceil        (($ntsmsc - $t) / 86400);                       # verbleibende Tage bis der Batterie Pflege-SoC (default 95%) erreicht sein soll

      $paref->{days2care} = $days2care;
      __batSaveSocKeyFigures ($paref);
      delete $paref->{days2care};

      my $careSoc = $maxsoc - ($days2care * $batSocChgDay);                                     # Pflege-SoC um rechtzeitig den $maxsoc zu erreichen bei 5% Steigerung pro Tag
      $target     = $careSoc < $target ? $target : $careSoc;                                    # resultierender Target-SoC unter Berücksichtigung $caresoc
      $la         = "note remaining days until care SoC ($days2care days) -> Target: $target %";
  }
  else {
      $nt = (timestampToTimestring ($delayts, $paref->{lang}))[0];
      $la = "note remaining days until care SoC -> calculation & activation postponed to after $nt";
  }

  debugLog ($paref, 'batteryManagement', "SoC calc Step2 - $la");

  ## Aufladewahrscheinlichkeit beachten
  #######################################
  my $pvfctm     = ReadingsNum ($name, 'Tomorrow_PVforecast',            0);       # PV Prognose morgen
  my $pvfctd     = ReadingsNum ($name, 'RestOfDayPVforecast',            0);       # PV Prognose Rest heute
  my $csopt      = ReadingsNum ($name, 'Battery_OptimumTargetSoC', $lowSoc);       # aktuelles SoC Optimum
  my $pvexpect   = $pvfctm > $pvfctd ? $pvfctm : $pvfctd;

  my $batinstcap = CurrentVal ($hash, 'batinstcap', 0);                            # installierte Batteriekapazität Wh
  my $cantarget  = 100 - (100 / $batinstcap) * $pvexpect;                          # berechneter möglicher Min SOC nach Berücksichtigung Ladewahrscheinlichkeit

  my $newtarget  = sprintf "%.0f", ($cantarget < $target ? $cantarget : $target);  # Abgleich möglicher Min SOC gg. berechneten Min SOC
  my $logadd     = '';

  if ($newtarget > $csopt && $t > $delayts) {                                      # Erhöhung des SoC (wird ab Sonnenuntergang angewendet)
      $target = $newtarget;
      $logadd = "(new target > $csopt % and Sunset has passed)";
  }
  elsif ($newtarget > $csopt && $t <= $delayts) {                                  # bisheriges Optimum bleibt vorerst
      $target = $csopt;
      $nt     = (timestampToTimestring ($delayts, $paref->{lang}))[0];
      $logadd = "(calculated new target $newtarget % is only activated after $nt)";
  }
  elsif ($newtarget < $csopt) {                                                    # Targetminderung sofort umsetzen -> Freiplatz für Ladeprognose
      $target = $newtarget;
      $logadd = "(new target < current Target SoC $csopt)";
  }
  else {                                                                           # bisheriges Optimum bleibt
      $target = $newtarget;
      $logadd = "(no change)";
  }

  debugLog ($paref, 'batteryManagement', "SoC calc Step3 - note charging probability -> Target: $target % ".$logadd);

  ## low/up-Grenzen beachten
  ############################
  $target = $target > $upSoc  ? $upSoc  :
            $target < $lowSoc ? $lowSoc :
            $target;

  debugLog ($paref, 'batteryManagement', "SoC calc Step4 - observe low/up limits -> Target: $target %");

  ## auf 5er Schritte anpassen (40,45,50,...)
  #############################################
  my $flo = floor ($target / 5);
  my $rmn = $target - ($flo * 5);
  my $add = $rmn <= 2.5 ? 0 : 5;
  $target = ($flo * 5) + $add;

  debugLog ($paref, 'batteryManagement', "SoC calc Step5 - rounding the SoC to steps of 5 -> Target: $target %");

  ## Zwangsladeanforderung
  ##########################
  if ($batcharge < $target) {
      $chargereq = 1;
  }

  debugLog ($paref, 'batteryManagement', "SoC calc Step6 - force charging request: ".
                    ($chargereq ? 'yes (battery charge is below minimum SoC)' : 'no (Battery is sufficiently charged)'));

  ## pvHistory/Readings schreiben
  #################################
  $paref->{batsetsoc} = $target;
  $paref->{nhour}     = 99;
  $paref->{histname}  = 'batsetsoc';
  setPVhistory ($paref);
  delete $paref->{histname};

  storeReading ('Battery_OptimumTargetSoC', $target.' %');
  storeReading ('Battery_ChargeRequest',      $chargereq);

return;
}

################################################################
#                Parse ctrlBatSocManagement
################################################################
sub __parseAttrBatSoc {
  my $name = shift;
  my $cgbt = shift // return;

  my ($pa,$ph)  = parseParams ($cgbt);
  my $lowSoc    = $ph->{lowSoc};
  my $upSoc     = $ph->{upSoC};
  my $maxsoc    = $ph->{maxSoC}    // $maxSoCdef;                            # optional (default: $maxSoCdef)
  my $careCycle = $ph->{careCycle} // $carecycledef;                         # Ladungszyklus (Maintenance) für maxSoC in Tagen

return ($lowSoc, $upSoc, $maxsoc, $careCycle);
}

################################################################
#          Batterie Kennzahlen speichern
################################################################
sub __batSaveSocKeyFigures {
  my $paref     = shift;
  my $name      = $paref->{name};
  my $type      = $paref->{type};
  my $t         = $paref->{t};                                                               # aktuelle Zeit
  my $careCycle = $paref->{careCycle} // $carecycledef;

  if (defined $paref->{days2care}) {
      $data{$type}{$name}{circular}{99}{days2care} = $paref->{days2care};                     # verbleibende Tage bis zum Pflege-SoC erreicht werden soll
      return;
  }

  $data{$type}{$name}{circular}{99}{lastTsMaxSocRchd} = $t;                                   # Timestamp des letzten Erreichens von >= maxSoC
  $data{$type}{$name}{circular}{99}{nextTsMaxSocChge} = $t + (86400 * $careCycle);            # Timestamp bis zu dem die Batterie mindestens einmal maxSoC erreichen soll

return;
}

################################################################
#               Zusammenfassungen erstellen
################################################################
sub _createSummaries {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $type   = $paref->{type};
  my $chour  = $paref->{chour};                                                                       # aktuelle Stunde
  my $minute = $paref->{minute};                                                                      # aktuelle Minute

  $minute    = (int $minute) + 1;                                                                     # Minute Range umsetzen auf 1 bis 60

  ## Initialisierung
  ####################
  my $next1HoursSum = { "PV" => 0, "Consumption" => 0 };
  my $next2HoursSum = { "PV" => 0, "Consumption" => 0 };
  my $next3HoursSum = { "PV" => 0, "Consumption" => 0 };
  my $next4HoursSum = { "PV" => 0, "Consumption" => 0 };
  my $restOfDaySum  = { "PV" => 0, "Consumption" => 0 };
  my $tomorrowSum   = { "PV" => 0, "Consumption" => 0 };
  my $todaySumFc    = { "PV" => 0, "Consumption" => 0 };
  my $todaySumRe    = { "PV" => 0, "Consumption" => 0 };

  my $tdConFcTillSunset = 0;
  my $remainminutes     = 60 - $minute;                                                                # verbleibende Minuten der aktuellen Stunde

  my $restofhourpvfc   = (NexthoursVal($hash, "NextHour00", 'pvfc',  0)) / 60 * $remainminutes;
  my $restofhourconfc  = (NexthoursVal($hash, "NextHour00", 'confc', 0)) / 60 * $remainminutes;

  $next1HoursSum->{PV}          = $restofhourpvfc;
  $next2HoursSum->{PV}          = $restofhourpvfc;
  $next3HoursSum->{PV}          = $restofhourpvfc;
  $next4HoursSum->{PV}          = $restofhourpvfc;
  $restOfDaySum->{PV}           = $restofhourpvfc;

  $next1HoursSum->{Consumption} = $restofhourconfc;
  $next2HoursSum->{Consumption} = $restofhourconfc;
  $next3HoursSum->{Consumption} = $restofhourconfc;
  $next4HoursSum->{Consumption} = $restofhourconfc;
  $restOfDaySum->{Consumption}  = $restofhourconfc;

  for my $h (1..47) {
      my $pvfc  = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), 'pvfc',  0);
      my $confc = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), 'confc', 0);
      my $istdy = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), 'today', 0);
      my $don   = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), 'DoN',   0);
      $pvfc     = 0 if($pvfc  < 0);                                                         # PV Prognose darf nicht negativ sein
      $confc    = 0 if($confc < 0);                                                         # Verbrauchsprognose darf nicht negativ sein

      if($h == 1) {
          $next1HoursSum->{PV}          += $pvfc  / 60 * $minute;
          $next1HoursSum->{Consumption} += $confc / 60 * $minute;
      }

      if($h <= 2) {
          $next2HoursSum->{PV}          += $pvfc                 if($h <  2);
          $next2HoursSum->{PV}          += $pvfc  / 60 * $minute if($h == 2);
          $next2HoursSum->{Consumption} += $confc                if($h <  2);
          $next2HoursSum->{Consumption} += $confc / 60 * $minute if($h == 2);
      }

      if($h <= 3) {
          $next3HoursSum->{PV}          += $pvfc                 if($h <  3);
          $next3HoursSum->{PV}          += $pvfc  / 60 * $minute if($h == 3);
          $next3HoursSum->{Consumption} += $confc                if($h <  3);
          $next3HoursSum->{Consumption} += $confc / 60 * $minute if($h == 3);
      }

      if($h <= 4) {
          $next4HoursSum->{PV}          += $pvfc                 if($h <  4);
          $next4HoursSum->{PV}          += $pvfc  / 60 * $minute if($h == 4);
          $next4HoursSum->{Consumption} += $confc                if($h <  4);
          $next4HoursSum->{Consumption} += $confc / 60 * $minute if($h == 4);
      }

      if($istdy) {
          $restOfDaySum->{PV}          += $pvfc;
          $restOfDaySum->{Consumption} += $confc;
          $tdConFcTillSunset           += $confc if($don);
      }
      else {
          $tomorrowSum->{PV} += $pvfc;
      }
  }

  for my $th (1..24) {
      $todaySumFc->{PV} += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$th)."_PVforecast", 0);
      $todaySumRe->{PV} += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$th)."_PVreal",     0);
  }

  my $pvre = int $todaySumRe->{PV};

  push @{$data{$type}{$name}{current}{h4fcslidereg}}, int $next4HoursSum->{PV};                         # Schieberegister 4h Summe Forecast
  limitArray ($data{$type}{$name}{current}{h4fcslidereg}, $defslidenum);

  my $gcon    = CurrentVal ($hash, "gridconsumption",         0);                                       # aktueller Netzbezug
  my $tconsum = CurrentVal ($hash, "tomorrowconsumption", undef);                                       # Verbrauchsprognose für folgenden Tag
  my $pvgen   = CurrentVal ($hash, "generation",              0);
  my $gfeedin = CurrentVal ($hash, "gridfeedin",              0);
  my $batin   = CurrentVal ($hash, "powerbatin",              0);                                       # aktuelle Batterieladung
  my $batout  = CurrentVal ($hash, "powerbatout",             0);                                       # aktuelle Batterieentladung

  my $consumption         = int ($pvgen - $gfeedin + $gcon - $batin + $batout);
  my $selfconsumption     = int ($pvgen - $gfeedin - $batin);
  $selfconsumption        = $selfconsumption < 0 ? 0 : $selfconsumption;

  my $surplus             = int ($pvgen - $consumption);                                                # aktueller Überschuß
  $surplus                = 0 if($surplus < 0);                                                         # wegen Vergleich nompower vs. surplus

  my $selfconsumptionrate = 0;
  my $autarkyrate         = 0;
  my $divi                = $selfconsumption + $batout + $gcon;
  $selfconsumptionrate    = sprintf "%.0f", $selfconsumption / $pvgen * 100            if($pvgen * 1 > 0);
  $autarkyrate            = sprintf "%.0f", ($selfconsumption + $batout) / $divi * 100 if($divi);       # vermeide Illegal division by zero

  $data{$type}{$name}{current}{consumption}         = $consumption;
  $data{$type}{$name}{current}{selfconsumption}     = $selfconsumption;
  $data{$type}{$name}{current}{selfconsumptionrate} = $selfconsumptionrate;
  $data{$type}{$name}{current}{autarkyrate}         = $autarkyrate;
  $data{$type}{$name}{current}{surplus}             = $surplus;
  $data{$type}{$name}{current}{tdConFcTillSunset}   = $tdConFcTillSunset;

  storeReading ('Current_Consumption',          $consumption.         ' W');
  storeReading ('Current_SelfConsumption',      $selfconsumption.     ' W');
  storeReading ('Current_SelfConsumptionRate',  $selfconsumptionrate. ' %');
  storeReading ('Current_Surplus',              $surplus.             ' W');
  storeReading ('Current_AutarkyRate',          $autarkyrate.         ' %');
  storeReading ('Today_PVreal',                 $pvre.               ' Wh') if($pvre > ReadingsNum ($name, 'Today_PVreal', 0));
  storeReading ('Tomorrow_ConsumptionForecast', $tconsum.            ' Wh') if(defined $tconsum);

  storeReading ('NextHours_Sum01_PVforecast',          (int $next1HoursSum->{PV}).         ' Wh');
  storeReading ('NextHours_Sum02_PVforecast',          (int $next2HoursSum->{PV}).         ' Wh');
  storeReading ('NextHours_Sum03_PVforecast',          (int $next3HoursSum->{PV}).         ' Wh');
  storeReading ('NextHours_Sum04_PVforecast',          (int $next4HoursSum->{PV}).         ' Wh');
  storeReading ('RestOfDayPVforecast',                 (int $restOfDaySum->{PV}).          ' Wh');
  storeReading ('Tomorrow_PVforecast',                 (int $tomorrowSum->{PV}).           ' Wh');
  storeReading ('Today_PVforecast',                    (int $todaySumFc->{PV}).            ' Wh');
  storeReading ('NextHours_Sum04_ConsumptionForecast', (int $next4HoursSum->{Consumption}).' Wh');
  storeReading ('RestOfDayConsumptionForecast',        (int $restOfDaySum->{Consumption}). ' Wh');

return;
}

################################################################
#     Consumer - Energieverbrauch aufnehmen
#              - Masterdata ergänzen
#              - Schaltzeiten planen
################################################################
sub _manageConsumerData {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $t       = $paref->{t};                                                 # aktuelle Zeit
  my $date    = $paref->{date};                                              # aktuelles Datum
  my $chour   = $paref->{chour};
  my $day     = $paref->{day};

  my $nhour       = $chour + 1;
  $paref->{nhour} = sprintf("%02d",$nhour);

  for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {
      my $consumer = ConsumerVal ($hash, $c, "name",  "");
      my $alias    = ConsumerVal ($hash, $c, "alias", "");

      ## aktuelle Leistung auslesen
      ##############################
      my $paread = ConsumerVal ($hash, $c, "rpcurr", "");
      my $up     = ConsumerVal ($hash, $c, "upcurr", "");
      my $pcurr  = 0;

      if($paread) {
          my $eup = $up =~ /^kW$/xi ? 1000 : 1;
          $pcurr  = ReadingsNum ($consumer, $paread, 0) * $eup;

          storeReading ("consumer${c}_currentPower", $pcurr.' W');
      }

      ## Verbrauch auslesen + speichern
      ###################################
      my $ethreshold = 0;
      my $etotread   = ConsumerVal ($hash, $c, "retotal", "");
      my $u          = ConsumerVal ($hash, $c, "uetotal", "");

      if($etotread) {
          my $eu      = $u =~ /^kWh$/xi ? 1000 : 1;
          my $etot    = ReadingsNum ($consumer, $etotread, 0) * $eu;                               # Summe Energieverbrauch des Verbrauchers
          my $ehist   = HistoryVal  ($hash, $day, sprintf("%02d",$nhour), "csmt${c}", undef);      # gespeicherter Totalverbrauch
          $ethreshold = ConsumerVal ($hash, $c, "energythreshold", 0);                             # Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird

          ## aktuelle Leistung ermitteln wenn kein Reading d. aktuellen Leistung verfügbar
          ##################################################################################
          if(!$paread){
              my $timespan = $t    - ConsumerVal ($hash, $c, "old_etottime",  $t);
              my $delta    = $etot - ConsumerVal ($hash, $c, "old_etotal", $etot);
              $pcurr       = sprintf "%.6f", $delta / (3600 * $timespan) if($delta);               # Einheitenformel beachten !!: W = Wh / (3600 * s)

              $data{$type}{$name}{consumers}{$c}{old_etotal}   = $etot;
              $data{$type}{$name}{consumers}{$c}{old_etottime} = $t;

              storeReading ("consumer${c}_currentPower", $pcurr.' W');
          }

          if(defined $ehist && $etot >= $ehist && ($etot - $ehist) >= $ethreshold) {
              my $consumerco  = $etot - $ehist;
              $consumerco    += HistoryVal ($hash, $day, sprintf("%02d",$nhour), "csme${c}", 0);

              $paref->{consumerco} = $consumerco;                                                 # Verbrauch des Consumers aktuelle Stunde
              $paref->{histname}   = "csme${c}";
              setPVhistory ($paref);
              delete $paref->{histname};
          }

          $paref->{consumerco} = $etot;                                                           # Totalverbrauch des Verbrauchers
          $paref->{histname}   = "csmt${c}";
          setPVhistory ($paref);
          delete $paref->{histname};
      }

      deleteReadingspec ($hash, "consumer${c}_currentPower") if(!$etotread && !$paread);

      ## Verbraucher - Laufzeit und Zyklen pro Tag ermitteln
      ## Laufzeit (in Minuten) wird pro Stunde erfasst
      ## bei Tageswechsel Rücksetzen in _specialActivities
      #######################################################
      my $starthour;
      if (isConsumerLogOn ($hash, $c, $pcurr)) {                                                                                             # Verbraucher ist logisch "an"
            if (ConsumerVal ($hash, $c, "onoff", "off") eq "off") {
                $data{$type}{$name}{consumers}{$c}{onoff}           = 'on';
                $data{$type}{$name}{consumers}{$c}{startTime}       = $t;                                                                    # startTime ist nicht von "Automatic" abhängig -> nicht identisch mit planswitchon !!!
                $data{$type}{$name}{consumers}{$c}{cycleStarttime}  = $t;
                $data{$type}{$name}{consumers}{$c}{cycleTime}       = 0;
                my $stimes                                          = ConsumerVal ($hash, $c, "numberDayStarts", 0);                         # Anzahl der On-Schaltungen am Tag
                $data{$type}{$name}{consumers}{$c}{numberDayStarts} = $stimes+1;
                $data{$type}{$name}{consumers}{$c}{lastMinutesOn}   = ConsumerVal ($hash, $c, "minutesOn", 0);
            }
            else {
                $data{$type}{$name}{consumers}{$c}{cycleTime} = (($t - ConsumerVal ($hash, $c, 'cycleStarttime', $t)) / 60);
            }

            $starthour = strftime "%H", localtime(ConsumerVal ($hash, $c, "startTime", $t));

            if ($chour eq $starthour) {
                my $runtime                                   = (($t - ConsumerVal ($hash, $c, "startTime", $t)) / 60);                      # in Minuten ! (gettimeofday sind ms !)
                $data{$type}{$name}{consumers}{$c}{minutesOn} = ConsumerVal ($hash, $c, "lastMinutesOn", 0) + $runtime;
            }
            else {                                                                                                                           # neue Stunde hat begonnen
                if (ConsumerVal ($hash, $c, "onoff", "off") eq 'on') {
                    $data{$type}{$name}{consumers}{$c}{startTime}     = timestringToTimestamp ($date." ".sprintf("%02d",  $chour).":00:00");
                    $data{$type}{$name}{consumers}{$c}{minutesOn}     = ($t - ConsumerVal ($hash, $c, "startTime", $t)) / 60;                # in Minuten ! (gettimeofday sind ms !)
                    $data{$type}{$name}{consumers}{$c}{lastMinutesOn} = 0;
                }
            }
      }
      else {                                                                                                                                 # Verbraucher soll nicht aktiv sein
          $data{$type}{$name}{consumers}{$c}{onoff}     = 'off';
          $data{$type}{$name}{consumers}{$c}{cycleTime} = 0;
          $starthour                                    = strftime "%H", localtime(ConsumerVal ($hash, $c, "startTime", $t));

          if ($chour ne $starthour) {
              $data{$type}{$name}{consumers}{$c}{minutesOn} = 0;
              delete $data{$type}{$name}{consumers}{$c}{startTime};
          }
      }

      $paref->{val}      = ConsumerVal ($hash, $c, "numberDayStarts", 0);                                                                    # Anzahl Tageszyklen des Verbrauchers speichern
      $paref->{histname} = "cyclescsm${c}";
      setPVhistory ($paref);
      delete $paref->{histname};

      $paref->{val}      = ceil ConsumerVal ($hash, $c, "minutesOn", 0);                                                                     # Verbrauchsminuten akt. Stunde des Consumers
      $paref->{histname} = "minutescsm${c}";
      setPVhistory ($paref);
      delete $paref->{histname};

      ## Durchschnittsverbrauch / Betriebszeit ermitteln + speichern
      ################################################################
      my $consumerco = 0;
      my $runhours   = 0;
      my $dnum       = 0;

      for my $n (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {                                             # Betriebszeit und gemessenen Verbrauch ermitteln
          my $csme  = HistoryVal ($hash, $n, 99, "csme${c}", 0);
          my $hours = HistoryVal ($hash, $n, 99, "hourscsme${c}", 0);
          next if(!$hours);

          $consumerco += $csme;
          $runhours   += $hours;
          $dnum++;
      }

      if ($dnum) {
          if($consumerco && $runhours) {
              $data{$type}{$name}{consumers}{$c}{avgenergy} = sprintf "%.2f", ($consumerco/$runhours);            # Durchschnittsverbrauch pro Stunde in Wh
          }
          else {
              delete $data{$type}{$name}{consumers}{$c}{avgenergy};
          }

          $data{$type}{$name}{consumers}{$c}{avgruntime} = sprintf "%.2f", (($runhours / $dnum) * 60);            # Durchschnittslaufzeit am Tag in Minuten
      }

      $paref->{consumer} = $c;

      __getAutomaticState     ($paref);                                                                           # Automatic Status des Consumers abfragen
      __calcEnergyPieces      ($paref);                                                                           # Energieverbrauch auf einzelne Stunden für Planungsgrundlage aufteilen
      __planInitialSwitchTime ($paref);                                                                           # Consumer Switch Zeiten planen
      __setTimeframeState     ($paref);                                                                           # Timeframe Status ermitteln
      __setConsRcmdState      ($paref);                                                                           # Consumption Recommended Status setzen
      __switchConsumer        ($paref);                                                                           # Consumer schalten
      __reviewSwitchTime      ($paref);                                                                           # Planungsdaten überprüfen und ggf. neu planen
      __remainConsumerTime    ($paref);                                                                           # Restlaufzeit Verbraucher ermitteln
      __setPhysSwState        ($paref);                                                                           # physischen Schaltzustand festhalten

      ## Consumer Schaltstatus und Schaltzeit für Readings ermitteln
      ################################################################
      my $costate = isConsumerPhysOn  ($hash, $c) ? "on"  :
                    isConsumerPhysOff ($hash, $c) ? "off" :
                    "unknown";

      $data{$type}{$name}{consumers}{$c}{state} = $costate;

      my ($pstate,$starttime,$stoptime,$supplmnt) = __getPlanningStateAndTimes ($paref);
      my ($iilt,$rlt)                             = isInLocktime ($paref);                                        # Sperrzeit Status ermitteln
      my $mode                                    = ConsumerVal ($hash, $c, 'mode', 'can');
      my $constate                                = "name='$alias' state='$costate'";
      $constate                                  .= " mode='$mode' planningstate='$pstate'";
      $constate                                  .= " remainLockTime='$rlt'" if($rlt);
      $constate                                  .= " info='$supplmnt'"      if($supplmnt);

      storeReading ("consumer${c}",                $constate);                                                    # Consumer Infos
      storeReading ("consumer${c}_planned_start", $starttime) if($starttime);                                     # Consumer Start geplant
      storeReading ("consumer${c}_planned_stop",   $stoptime) if($stoptime);                                      # Consumer Stop geplant
  }

  delete $paref->{consumer};

return;
}

################################################################
#   Consumer Status Automatic Modus abfragen und im
#   Hash consumers aktualisieren
################################################################
sub __getAutomaticState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};

  my $consumer = ConsumerVal ($hash, $c, 'name', '');                                  # Name Consumer Device

  if (!$consumer || !$defs{$consumer}) {
      my $err = qq{ERROR - the device "$consumer" doesn't exist anymore! Delete or change the attribute "consumer${c}".};
      Log3 ($name, 1, "$name - $err");
      return;
  }

  my $dswitch = ConsumerVal ($hash, $c, 'dswitch', '');                                # alternatives Schaltdevice

  if ($dswitch) {
      if (!$defs{$dswitch}) {
          my $err = qq{ERROR - the device "$dswitch" doesn't exist anymore! Delete or change the attribute "consumer${c}".};
          Log3 ($name, 1, "$name - $err");
          return;
      }
  }
  else {
      $dswitch = $consumer;
  }

  my $autord = ConsumerVal ($hash, $c, 'autoreading', '');                             # Readingname f. Automatiksteuerung
  my $auto   = 1;
  $auto      = ReadingsVal ($dswitch, $autord, 1) if($autord);                         # Reading für Ready-Bit -> Einschalten möglich ?

  $data{$type}{$name}{consumers}{$c}{auto} = $auto;                                    # Automaticsteuerung: 1 - Automatic ein, 0 - Automatic aus

return;
}

###################################################################
#    Energieverbrauch auf einzelne Stunden für Planungsgrundlage
#    aufteilen
#    Consumer specific epieces ermitteln + speichern
#    (in Wh)
###################################################################
sub __calcEnergyPieces {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};

  my $etot = HistoryVal ($hash, $paref->{day}, sprintf("%02d",$paref->{nhour}), "csmt${c}", 0);

  if($etot) {
      $paref->{etot} = $etot;
      ___csmSpecificEpieces ($paref);
      delete $paref->{etot};
  }
  else {
      delete $data{$type}{$name}{consumers}{$c}{epiecAVG};
      delete $data{$type}{$name}{consumers}{$c}{epiecAVG_hours};
      delete $data{$type}{$name}{consumers}{$c}{epiecStartEtotal};
      delete $data{$type}{$name}{consumers}{$c}{epiecHist};
      delete $data{$type}{$name}{consumers}{$c}{epiecHour};

      for my $h (1..$epiecMaxCycles) {
          delete $data{$type}{$name}{consumers}{$c}{"epiecHist_".$h};
          delete $data{$type}{$name}{consumers}{$c}{"epiecHist_".$h."_hours"};
      }
  }

  delete $data{$type}{$name}{consumers}{$c}{epieces};

  my $cotype  = ConsumerVal ($hash, $c, "type",    $defctype  );
  my $mintime = ConsumerVal ($hash, $c, "mintime", $defmintime);

  if (isSunPath ($hash, $c)) {                                                                            # SunPath ist in mintime gesetzt
      my ($riseshift, $setshift) = sunShift    ($hash, $c);
      my $tdiff                  = (CurrentVal ($hash, 'sunsetTodayTs',  0) + $setshift) -
                                   (CurrentVal ($hash, 'sunriseTodayTs', 0) + $riseshift);
      $mintime                   = $tdiff / 60;
  }

  my $hours   = ceil ($mintime / 60);                                                          # Einplanungsdauer in h
  my $ctote   = ConsumerVal ($hash, $c, "avgenergy", undef);                                   # gemessener durchschnittlicher Energieverbrauch pro Stunde (Wh)
  $ctote      = $ctote ?
                $ctote :
                ConsumerVal ($hash, $c, "power", 0);                                           # alternativer nominaler Energieverbrauch in W (bzw. Wh bezogen auf 1 h)

  if (int($hef{$cotype}{f}) == 1) {                                                            # bei linearen Verbrauchertypen die nominale Leistungsangabe verwenden statt Durchschnitt
      $ctote = ConsumerVal ($hash, $c, "power", 0);
  }

  my $epiecef = $ctote * $hef{$cotype}{f};                                                     # Gewichtung erste Laufstunde
  my $epiecel = $ctote * $hef{$cotype}{l};                                                     # Gewichtung letzte Laufstunde

  my $epiecem = $ctote * $hef{$cotype}{m};

  for my $h (1..$hours) {
      my $he;
      $he = $epiecef    if($h == 1               );                                            # kalk. Energieverbrauch Startstunde
      $he = $epiecem    if($h >  1 && $h < $hours);                                            # kalk. Energieverbrauch Folgestunde(n)
      $he = $epiecel    if($h == $hours          );                                            # kalk. Energieverbrauch letzte Stunde

      $data{$type}{$name}{consumers}{$c}{epieces}{${h}} = sprintf('%.2f', $he);
  }

return;
}

####################################################################################
#  Verbraucherspezifische Energiestück Ermittlung
#
#  epiecMaxCycles    => gibt an wie viele Zyklen betrachtet werden
#                       sollen
#  epiecHist         => ist die Nummer des Zyklus der aktuell
#                       benutzt wird.
#
#  epiecHist_x       => 1=.. 2=.. 3=.. 4=.. epieces eines Zyklus
#  epiecHist_x_hours => Stunden des Durchlauf bzw. wie viele
#                       Einträge epiecHist_x hat
#  epiecAVG          => 1=.. 2=.. durchschnittlicher Verbrauch pro Betriebsstunde
#                       1, 2, .. usw.
#                       wäre ein KPI um eine angepasste Einschaltung zu
#                       realisieren
#  epiecAVG_hours    => durchschnittliche Betriebsstunden für einen Ein/Aus-Zyklus
#
####################################################################################
sub ___csmSpecificEpieces {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $etot  = $paref->{etot};
  my $t     = $paref->{t};

  if (ConsumerVal ($hash, $c, "onoff", "off") eq "on") {                                                # Status "Aus" verzögern um Pausen im Waschprogramm zu überbrücken
      $data{$type}{$name}{consumers}{$c}{lastOnTime} = $t;
  }

  my $tsloff = defined $data{$type}{$name}{consumers}{$c}{lastOnTime} ?
                $t - $data{$type}{$name}{consumers}{$c}{lastOnTime}    :
                99;

  debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - time since last Switch Off (tsloff): $tsloff seconds});

  if ($tsloff < 300) {                                                                                  # erst nach Auszeit >= X Sekunden wird ein neuer epiec-Zyklus gestartet
      my $ecycle          = "";
      my $epiecHist_hours = "";

      if (ConsumerVal ($hash, $c, "epiecHour", -1) < 0) {                                               # neue Aufzeichnung
          $data{$type}{$name}{consumers}{$c}{epiecStartTime} = $t;
          $data{$type}{$name}{consumers}{$c}{epiecHist}     += 1;
          $data{$type}{$name}{consumers}{$c}{epiecHist}      = 1 if(ConsumerVal ($hash, $c, "epiecHist", 0) > $epiecMaxCycles);

          $ecycle = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0);

          delete $data{$type}{$name}{consumers}{$c}{$ecycle};                                           # Löschen, wird neu erfasst
      }

      $ecycle          = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0);                          # Zyklusnummer für Namen
      $epiecHist_hours = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0)."_hours";
      my $epiecHour    = floor (($t - ConsumerVal ($hash, $c, "epiecStartTime", $t)) / 60 / 60) + 1;    # aktuelle Betriebsstunde ermitteln, ( / 60min) mögliche wäre auch durch 15min /Minute /Stunde

      debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - current cycle number (ecycle): $ecycle});
      debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - Operating hour after switch on (epiecHour): $epiecHour});

      if (ConsumerVal ($hash, $c, "epiecHour", 0) != $epiecHour) {                                      # Betriebsstundenwechsel ? Differenz von etot noch auf die vorherige Betriebsstunde anrechnen
          my $epiecHour_last = $epiecHour - 1;

          $data{$type}{$name}{consumers}{$c}{$ecycle}{$epiecHour_last} = sprintf '%.2f', ($etot - ConsumerVal ($hash, $c, "epiecStartEtotal", 0)) if($epiecHour > 1);
          $data{$type}{$name}{consumers}{$c}{epiecStartEtotal}         = $etot;

          debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - Operating hours change - new etotal (epiecStartEtotal): $etot});
      }

      my $ediff                                               = $etot - ConsumerVal ($hash, $c, "epiecStartEtotal", 0);
      $data{$type}{$name}{consumers}{$c}{$ecycle}{$epiecHour} = sprintf '%.2f', $ediff;
      $data{$type}{$name}{consumers}{$c}{epiecHour}           = $epiecHour;
      $data{$type}{$name}{consumers}{$c}{$epiecHist_hours}    = $ediff ? $epiecHour : $epiecHour - 1;    # wenn mehr als 1 Wh verbraucht wird die Stunde gezählt

      debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - energy consumption in operating hour $epiecHour (ediff): $ediff});
  }
  else {                                                                                                 # Durchschnitt ermitteln
      if (ConsumerVal ($hash, $c, "epiecHour", 0) > 0) {
          my $hours = 0;

          for my $h (1..$epiecMaxCycles) {                                                               # durchschnittliche Betriebsstunden über alle epieces ermitteln und aufrunden
              $hours += ConsumerVal ($hash, $c, "epiecHist_".$h."_hours", 0);
          }

          my $avghours                                       = ceil ($hours / $epiecMaxCycles);
          $data{$type}{$name}{consumers}{$c}{epiecAVG_hours} = $avghours;                                # durchschnittliche Betriebsstunden pro Zyklus

          debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - Average operating hours per cycle (epiecAVG_hours): $avghours});

          delete $data{$type}{$name}{consumers}{$c}{epiecAVG};                                           # Durchschnitt für epics ermitteln

          for my $hour (1..$avghours) {                                                                  # jede Stunde durchlaufen
              my $hoursE = 1;

              for my $h (1..$epiecMaxCycles) {                                                           # jedes epiec durchlaufen
                  my $ecycle = "epiecHist_".$h;

                  if (defined $data{$type}{$name}{consumers}{$c}{$ecycle}{$hour}) {
                      if ($data{$type}{$name}{consumers}{$c}{$ecycle}{$hour} > 5) {
                          $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} += $data{$type}{$name}{consumers}{$c}{$ecycle}{$hour};
                          $hoursE += 1;
                      }
                  }

              }

              my $eavg  = defined $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} ?
                          $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour}         :
                          0;

              my $ahval = sprintf '%.2f', $eavg / $hoursE;                                               # Durchschnitt ermittelt und speichern
              $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} = $ahval;

              debugLog ($paref, "epiecesCalc", qq{specificEpieces -> consumer "$c" - Average epiece of operating hour $hour: $ahval});
          }
      }

      $data{$type}{$name}{consumers}{$c}{epiecHour} = -1;                                                # epiecHour auf initialwert setzen für nächsten durchlauf
  }

return;
}

###################################################################
#    Consumer Schaltzeiten planen
###################################################################
sub __planInitialSwitchTime {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $debug = $paref->{debug};

  my $dnp = ___noPlanRelease ($paref);

  if ($dnp) {
      if ($debug =~ /consumerPlanning/x) {
          Log3 ($name, 4, qq{$name DEBUG> Planning consumer "$c" - name: }.ConsumerVal ($hash, $c, 'name', '').
                          qq{ alias: }.ConsumerVal ($hash, $c, 'alias', ''));
          Log3 ($name, 4, qq{$name DEBUG> Planning consumer "$c" - $dnp});
      }

      return;
  }

  debugLog ($paref, "consumerPlanning", qq{Planning consumer "$c" - name: }.ConsumerVal ($hash, $c, 'name', '').
                                        qq{ alias: }.ConsumerVal ($hash, $c, 'alias', ''));

  if (ConsumerVal ($hash, $c, 'type', $defctype) eq 'noSchedule') {
      debugLog ($paref, "consumerPlanning", qq{consumer "$c" - }.$hqtxt{scnp}{EN});

      $paref->{ps} = 'noSchedule';

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      return;
  }

  ___doPlanning ($paref);

return;
}

###################################################################
#    Entscheidung ob die Planung für den Consumer
#    vorgenommen werden soll oder nicht
###################################################################
sub ___noPlanRelease {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $t     = $paref->{t};                                                                 # aktuelle Zeit
  my $c     = $paref->{consumer};

  my $dnp   = 0;                                                                           # 0 -> Planung, 1 -> keine Planung

  if (ConsumerVal ($hash, $c, 'planstate', undef)) {                                       # Verbraucher ist schon geplant/gestartet/fertig
      $dnp = qq{consumer is already planned};
  }
  elsif (isSolCastUsed ($hash) || isForecastSolarUsed ($hash)) {
      my $tdc = SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIcalls', 0);

      if ($tdc < 1) {                                                                      # Planung erst nach dem zweiten API Abruf freigeben
           $dnp = qq{do not plan because off "todayDoneAPIcalls" is not set};
      }
  }
  else {                                                                                   # Planung erst ab "$leadtime" vor Sonnenaufgang freigeben
      my $sunrise = CurrentVal ($hash, 'sunriseTodayTs', 32529945600);

      if ($t < $sunrise - $leadtime) {
          $dnp = "do not plan because off current time is less than sunrise minus ".($leadtime / 3600)." hour";
      }
  }

return $dnp;
}

###################################################################
#    Consumer Review Schaltzeiten und neu planen wenn der
#    Consumer noch nicht in Operation oder finished ist
#    (nach Consumer Schaltung)
###################################################################
sub __reviewSwitchTime {
  my $paref = shift;

  my $hash      = $paref->{hash};
  my $c         = $paref->{consumer};
  my $pstate    = ConsumerVal    ($hash, $c, 'planstate',   '');
  my $plswon    = ConsumerVal    ($hash, $c, 'planswitchon', 0);                      # bisher geplante Switch on Zeit
  my $simpCstat = simplifyCstate ($pstate);
  my $t         = $paref->{t};

  if ($simpCstat =~ /planned|suspended/xs) {
      if ($t < $plswon || $t > $plswon + 300) {                                       # geplante Switch-On Zeit ist 5 Min überschritten und immer noch "planned"
          my $minute = $paref->{minute};

          for my $m (qw(15 45)) {
              if (int $minute >= $m) {
                  if (!exists $hash->{HELPER}{$c.'M'.$m.'DONE'}) {
                      my $name                          = $paref->{name};
                      $hash->{HELPER}{$c.'M'.$m.'DONE'} = 1;

                      debugLog ($paref, "consumerPlanning", qq{consumer "$c" - Review switch time planning name: }.ConsumerVal ($hash, $c, 'name', '').
                                                            qq{ alias: }.ConsumerVal ($hash, $c, 'alias', ''));

                      ___doPlanning ($paref);
                  }
              }
              else {
                  delete $hash->{HELPER}{$c.'M'.$m.'DONE'};
              }
          }
      }
  }
  else {
      delete $hash->{HELPER}{$c.'M15DONE'};
      delete $hash->{HELPER}{$c.'M45DONE'};
  }

return;
}

###################################################################
#    Consumer Planung ausführen
###################################################################
sub ___doPlanning {
  my $paref = shift;

  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $c      = $paref->{consumer};
  my $debug  = $paref->{debug};
  my $type   = $paref->{type};
  my $nh     = $data{$type}{$name}{nexthours};
  my $cicfip = AttrVal ($name, 'affectConsForecastInPlanning', 0);                         # soll Consumption Vorhersage in die Überschußermittlung eingehen ?

  debugLog ($paref, "consumerPlanning", qq{consumer "$c" - Consider consumption forecast in consumer planning: }.($cicfip ? 'yes' : 'no'));

  my %max;
  my %mtimes;

  ## max. Überschuß ermitteln
  #############################
  for my $idx (sort keys %{$nh}) {
      my $pvfc    = NexthoursVal ($hash, $idx, 'pvfc',    0);
      my $confcex = NexthoursVal ($hash, $idx, 'confcEx', 0);                              # prognostizierter Verbrauch ohne registrierte Consumer

      my $spexp   = $pvfc - ($cicfip ? $confcex : 0);                                      # prognostizierter Energieüberschuß (kann negativ sein)

      my ($hour)              = $idx =~ /NextHour(\d+)/xs;
      $max{$spexp}{starttime} = NexthoursVal ($hash, $idx, "starttime", "");
      $max{$spexp}{today}     = NexthoursVal ($hash, $idx, "today",      0);
      $max{$spexp}{nexthour}  = int ($hour);
  }

  my $order = 1;
  for my $k (reverse sort{$a<=>$b} keys %max) {
      my $ts                  = timestringToTimestamp ($max{$k}{starttime});

      $max{$order}{spexp}     = $k;
      $max{$order}{ts}        = $ts;
      $max{$order}{starttime} = $max{$k}{starttime};
      $max{$order}{nexthour}  = $max{$k}{nexthour};
      $max{$order}{today}     = $max{$k}{today};

      $mtimes{$ts}{spexp}     = $k;
      $mtimes{$ts}{starttime} = $max{$k}{starttime};
      $mtimes{$ts}{nexthour}  = $max{$k}{nexthour};
      $mtimes{$ts}{today}     = $max{$k}{today};

      delete $max{$k};

      $order++;
  }

  my $epiece1 = (~0 >> 1);
  my $epieces = ConsumerVal ($hash, $c, "epieces", "");

  if (ref $epieces eq "HASH") {
      $epiece1 = $data{$type}{$name}{consumers}{$c}{epieces}{1};
  }
  else {
      return;
  }

  debugLog ($paref, "consumerPlanning", qq{consumer "$c" - epiece1: $epiece1});

  my $mode     = ConsumerVal ($hash, $c, 'mode',          'can');
  my $calias   = ConsumerVal ($hash, $c, 'alias',            '');
  my $mintime  = ConsumerVal ($hash, $c, 'mintime', $defmintime);                                      # Einplanungsdauer

  debugLog ($paref, "consumerPlanning", qq{consumer "$c" - mode: $mode, mintime: $mintime, relevant method: surplus});

  if (isSunPath ($hash, $c)) {                                                                         # SunPath ist in mintime gesetzt
      my ($riseshift, $setshift) = sunShift    ($hash, $c);
      my $tdiff                  = (CurrentVal ($hash, 'sunsetTodayTs',  0) + $setshift) -
                                   (CurrentVal ($hash, 'sunriseTodayTs', 0) + $riseshift);
      $mintime                   = $tdiff / 60;

      if ($debug =~ /consumerPlanning/x) {
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - Sunrise is shifted by >}.($riseshift / 60).'< minutes');
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - Sunset is shifted by >}. ($setshift /  60).'< minutes');
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - mintime calculated: }.$mintime.' minutes');
      }
  }

  my $stopdiff       = $mintime * 60;
  $paref->{maxref}   = \%max;
  $paref->{mintime}  = $mintime;
  $paref->{stopdiff} = $stopdiff;

  if ($mode eq "can") {                                                                                # Verbraucher kann geplant werden
      if ($debug =~ /consumerPlanning/x) {
          for my $m (sort{$a<=>$b} keys %mtimes) {
              Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - surplus expected: $mtimes{$m}{spexp}, }.
                              qq{starttime: }.$mtimes{$m}{starttime}.", ".
                              qq{nexthour: $mtimes{$m}{nexthour}, today: $mtimes{$m}{today}});
          }
      }

      for my $ts (sort{$a<=>$b} keys %mtimes) {

          if ($mtimes{$ts}{spexp} >= $epiece1) {                                                       # die früheste Startzeit sofern Überschuß größer als Bedarf
              my $starttime       = $mtimes{$ts}{starttime};

              $paref->{starttime} = $starttime;
              $starttime          = ___switchonTimelimits ($paref);
              delete $paref->{starttime};

              my $startts       = timestringToTimestamp ($starttime);                                  # Unix Timestamp für geplanten Switch on

              $paref->{ps}      = 'planned:';
              $paref->{startts} = $startts;
              $paref->{stopts}  = $startts + $stopdiff;

              ___setConsumerPlanningState ($paref);
              ___saveEhodpieces           ($paref);

              delete $paref->{ps};
              delete $paref->{startts};
              delete $paref->{stopts};

              last;
          }
          else {
              $paref->{supplement} = "expected max surplus less $epiece1";
              $paref->{ps}         = 'suspended:';

              ___setConsumerPlanningState ($paref);

              delete $paref->{ps};
              delete $paref->{supplement};
          }
      }
  }
  else {                                                                                               # Verbraucher _muß_ geplant werden
      if ($debug =~ /consumerPlanning/x) {
          for my $o (sort{$a<=>$b} keys %max) {
              Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - surplus: $max{$o}{spexp}, }.
                              qq{starttime: }.$max{$o}{starttime}.", ".
                              qq{nexthour: $max{$o}{nexthour}, today: $max{$o}{today}});
          }
      }

      my $done;

      for my $o (sort{$a<=>$b} keys %max) {
          next if(!$max{$o}{today});                                                                   # der max-Wert von heute ist auszuwählen

          $paref->{elem} = $o;
          ___planMust ($paref);
          delete $paref->{elem};

          $done = 1;

          last;
      }

      if (!$done) {
          $paref->{supplement} = 'no max surplus found for current day';
          $paref->{ps}         = 'suspended:';

          ___setConsumerPlanningState ($paref);

          delete $paref->{ps};
          delete $paref->{supplement};
      }
  }

  my $planstate = ConsumerVal ($hash, $c, 'planstate',      '');
  my $planspmlt = ConsumerVal ($hash, $c, 'planSupplement', '');

  if ($planstate) {
      Log3 ($name, 3, qq{$name - Consumer "$calias" $planstate $planspmlt});
  }

  writeCacheToFile ($hash, "consumers", $csmcache.$name);                                              # Cache File Consumer schreiben

  ___setPlanningDeleteMeth ($paref);

return;
}

################################################################
#   die geplanten EIN-Stunden des Tages mit den dazu gehörigen
#   Consumer spezifischen epieces im Consumer-Hash speichern
################################################################
sub ___saveEhodpieces {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $c       = $paref->{consumer};
  my $startts = $paref->{startts};                                           # Unix Timestamp für geplanten Switch on
  my $stopts  = $paref->{stopts};                                            # Unix Timestamp für geplanten Switch off

  my $p = 1;
  delete $data{$type}{$name}{consumers}{$c}{ehodpieces};

  for (my $i = $startts; $i <= $stopts; $i+=3600) {
      my $chod    = (strftime "%H", localtime($i)) + 1;
      my $epieces = ConsumerVal ($hash, $c, 'epieces', '');

      my $ep = 0;
      if(ref $epieces eq "HASH") {
          $ep = defined $data{$type}{$name}{consumers}{$c}{epieces}{$p} ?
                        $data{$type}{$name}{consumers}{$c}{epieces}{$p} :
                        0;
      }
      else {
          last;
      }

      $chod                                                 = sprintf '%02d', $chod;
      $data{$type}{$name}{consumers}{$c}{ehodpieces}{$chod} = sprintf '%.2f', $ep if($ep);

      $p++;
  }

return;
}

################################################################
#     Planungsdaten bzw. aktuelle Planungszustände setzen
################################################################
sub ___setConsumerPlanningState {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $type      = $paref->{type};
  my $c         = $paref->{consumer};
  my $ps        = $paref->{ps};                    # Planstatus
  my $supplmnt  = $paref->{supplement} // '';
  my $startts   = $paref->{startts};               # Unix Timestamp für geplanten Switch on
  my $stopts    = $paref->{stopts};                # Unix Timestamp für geplanten Switch off
  my $lonts     = $paref->{lastAutoOnTs};          # Timestamp des letzten On-Schaltens bzw. letzter Fortsetzung im Automatikmodus
  my $loffts    = $paref->{lastAutoOffTs};         # Timestamp des letzten Off-Schaltens bzw. letzter Unterbrechnung im Automatikmodus
  my $lang      = $paref->{lang};

  $data{$type}{$name}{consumers}{$c}{planSupplement} = $supplmnt;

  return if(!$ps);

  my ($starttime,$stoptime);

  if (defined $lonts) {
      $data{$type}{$name}{consumers}{$c}{lastAutoOnTs} = $lonts;
  }

  if (defined $loffts) {
      $data{$type}{$name}{consumers}{$c}{lastAutoOffTs} = $loffts;
  }

  if ($startts) {
      $starttime                                       = (timestampToTimestring ($startts, $lang))[3];
      $data{$type}{$name}{consumers}{$c}{planswitchon} = $startts;
  }

  if ($stopts) {
      $stoptime                                         = (timestampToTimestring ($stopts, $lang))[3];
      $data{$type}{$name}{consumers}{$c}{planswitchoff} = $stopts;
  }

  $ps .= " "              if($starttime || $stoptime);
  $ps .= $starttime       if($starttime);
  $ps .= $stoptime        if(!$starttime && $stoptime);
  $ps .= " - ".$stoptime  if($starttime  && $stoptime);

  $data{$type}{$name}{consumers}{$c}{planstate} = $ps;

return;
}

################################################################
#          Consumer Zeiten MUST planen
################################################################
sub ___planMust {
  my $paref    = shift;
  my $hash     = $paref->{hash};
  my $name     = $paref->{name};
  my $type     = $paref->{type};
  my $c        = $paref->{consumer};
  my $maxref   = $paref->{maxref};
  my $elem     = $paref->{elem};
  my $mintime  = $paref->{mintime};
  my $stopdiff = $paref->{stopdiff};
  my $lang     = $paref->{lang};

  my $maxts     = timestringToTimestamp ($maxref->{$elem}{starttime});                 # Unix Timestamp des max. Überschusses heute
  my $half      = floor ($mintime / 2 / 60);                                           # die halbe Gesamtplanungsdauer in h als Vorlaufzeit einkalkulieren
  my $startts   = $maxts - ($half * 3600);
  my $starttime = (timestampToTimestring ($startts, $lang))[3];

  $paref->{starttime} = $starttime;
  $starttime          = ___switchonTimelimits ($paref);
  delete $paref->{starttime};

  $startts   = timestringToTimestamp ($starttime);
  my $stopts = $startts + $stopdiff;

  $paref->{ps}      = "planned:";
  $paref->{startts} = $startts;                                                        # Unix Timestamp für geplanten Switch on
  $paref->{stopts}  = $stopts;                                                         # Unix Timestamp für geplanten Switch off

  ___setConsumerPlanningState ($paref);
  ___saveEhodpieces           ($paref);

  delete $paref->{ps};
  delete $paref->{startts};
  delete $paref->{stopts};

return;
}

################################################################
#   Einschaltgrenzen berücksichtigen und Korrektur
#   zurück liefern
#   notbefore, notafter muß in der Form "hh[:mm]" vorliegen
################################################################
sub ___switchonTimelimits {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $c         = $paref->{consumer};
  my $date      = $paref->{date};
  my $starttime = $paref->{starttime};
  my $lang      = $paref->{lang};
  my $t         = $paref->{t};

  my $startts;

  if (isSunPath ($hash, $c)) {                                                        # SunPath ist in mintime gesetzt
      my ($riseshift, $setshift) = sunShift   ($hash, $c);
      $startts                   = CurrentVal ($hash, 'sunriseTodayTs', 0) + $riseshift;
      $starttime                 = (timestampToTimestring ($startts, $lang))[3];

      debugLog ($paref, "consumerPlanning", qq{consumer "$c" - starttime is set to >$starttime< due to >SunPath< is used});
  }

  my $origtime  = $starttime;
  my $notbefore = ConsumerVal ($hash, $c, "notbefore", 0);
  my $notafter  = ConsumerVal ($hash, $c, "notafter",  0);

  my ($err, $vala, $valb);

  if ($notbefore =~ m/^\s*\{.*\}\s*$/xs) {                                          # notbefore als Perl-Code definiert
      ($err, $valb) = checkCode ($name, $notbefore, 'cc1');
      if (!$err && checkhhmm ($valb)) {
          $notbefore = $valb;
          debugLog ($paref, "consumerPlanning", qq{consumer "$c" - got 'notbefore' function result: $valb});
      }
      else {
          Log3 ($name, 1, "$name - ERROR - the result of the Perl code in 'notbefore' is incorrect: $valb");
          $notbefore = 0;
      }
  }

  if ($notafter =~ m/^\s*(\{.*\})\s*$/xs) {                                           # notafter als Perl-Code definiert
      ($err, $vala) = checkCode ($name, $notafter, 'cc1');
      if (!$err && checkhhmm ($vala)) {
          $notafter = $vala;
          debugLog ($paref, "consumerPlanning", qq{consumer "$c" - got 'notafter' function result: $vala})
      }
      else {
          Log3 ($name, 1, "$name - ERROR - the result of the Perl code in the 'notafter' key is incorrect: $vala");
          $notafter = 0;
      }
  }

  my ($nbfhh, $nbfmm, $nafhh, $nafmm);

  if ($notbefore) {
      ($nbfhh, $nbfmm) = split ":", $notbefore;
      $nbfmm         //= '00';
      $notbefore       = (int $nbfhh) . $nbfmm;
  }

  if ($notafter) {
      ($nafhh, $nafmm) = split ":", $notafter;
      $nafmm         //= '00';
      $notafter        = (int $nafhh) . $nafmm;
  }

  debugLog ($paref, "consumerPlanning", qq{consumer "$c" - used 'notbefore' term: }.(defined $notbefore ? $notbefore : ''));
  debugLog ($paref, "consumerPlanning", qq{consumer "$c" - used 'notafter' term: } .(defined $notafter  ? $notafter  : ''));

  my $change = q{};

  if ($t > timestringToTimestamp ($starttime)) {
      $starttime   = (timestampToTimestring ($t, $lang))[3];
      $change      = 'current time';
  }

  my ($starthour, $startminute) = $starttime =~ /\s(\d{2}):(\d{2}):/xs;
  my $start = (int $starthour) . $startminute;

  if ($notbefore && $start < $notbefore) {
      $nbfhh     = sprintf "%02d", $nbfhh;
      $starttime =~ s/\s(\d{2}):(\d{2}):/ $nbfhh:$nbfmm:/x;
      $change    = 'notbefore';
  }

  if ($notafter && $start > $notafter) {
      $nafhh     = sprintf "%02d", $nafhh;
      $starttime =~ s/\s(\d{2}):(\d{2}):/ $nafhh:$nafmm:/x;
      $change    = 'notafter';
  }

  if ($change) {
      my $cname = ConsumerVal ($hash, $c, "name", "");
      debugLog ($paref, "consumerPlanning", qq{consumer "$c" - Planned starttime of "$cname" changed from "$origtime" to "$starttime" due to $change condition});
  }

return $starttime;
}

################################################################
#   Löschmethode der Planungsdaten setzen
################################################################
sub ___setPlanningDeleteMeth {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};

  my $sonkey  = ConsumerVal ($hash, $c, "planswitchon",  "");
  my $soffkey = ConsumerVal ($hash, $c, "planswitchoff", "");

  if($sonkey && $soffkey) {
      my $onday  = strftime "%d", localtime($sonkey);
      my $offday = strftime "%d", localtime($soffkey);

      if ($offday ne $onday) {                                                          # Planungsdaten spezifische Löschmethode
          $data{$type}{$name}{consumers}{$c}{plandelete} = "specific";
      }
      else {                                                                            # Planungsdaten Löschmethode jeden Tag in Stunde 0 (_specialActivities)
          $data{$type}{$name}{consumers}{$c}{plandelete} = "regular";
      }
  }

return;
}

################################################################
#   Timeframe Status ermitteln
################################################################
sub __setTimeframeState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                            # aktueller Unixtimestamp

  my $startts = ConsumerVal ($hash, $c, "planswitchon",  undef);                      # geplante Unix Startzeit
  my $stopts  = ConsumerVal ($hash, $c, "planswitchoff", undef);                      # geplante Unix Stopzeit

  if ($startts && $t >= $startts && $stopts && $t <= $stopts) {                       # ist Zeit innerhalb der Planzeit ein/aus ?
      $data{$type}{$name}{consumers}{$c}{isIntimeframe} = 1;
  }
  else {
      $data{$type}{$name}{consumers}{$c}{isIntimeframe} = 0;
  }

return;
}

################################################################
#   Consumption Recommended Status setzen
################################################################
sub __setConsRcmdState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $debug = $paref->{debug};

  my $surplus    = CurrentVal  ($hash, 'surplus',                    0);                  # aktueller Energieüberschuß
  my $nompower   = ConsumerVal ($hash, $c, 'power',                  0);                  # Consumer nominale Leistungsaufnahme (W)
  my $ccr        = AttrVal     ($name, 'ctrlConsRecommendReadings', '');                  # Liste der Consumer für die ConsumptionRecommended-Readings erstellt werden sollen
  my $rescons    = isConsumerPhysOn($hash, $c) ? 0 : $nompower;                           # resultierender Verbauch nach Einschaltung Consumer

  my ($spignore, $info, $err) = isSurplusIgnoCond ($hash, $c, $debug);                    # Vorhandensein PV Überschuß ignorieren ?
  Log3 ($name, 1, "$name - $err") if($err);

  if (!$nompower || $surplus - $rescons > 0 || $spignore) {
      $data{$type}{$name}{consumers}{$c}{isConsumptionRecommended} = 1;                   # Einschalten des Consumers günstig bzw. Freigabe für "on" von Überschußseite erteilt
  }
  else {
      $data{$type}{$name}{consumers}{$c}{isConsumptionRecommended} = 0;
  }

  if ($ccr =~ /$c/xs) {
      storeReading ("consumer${c}_ConsumptionRecommended", ConsumerVal ($hash, $c, 'isConsumptionRecommended', 0));
  }

return;
}

################################################################
#   Planungsdaten Consumer prüfen und ggf. starten/stoppen
################################################################
sub __switchConsumer {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                           # aktueller Unixtimestamp
  my $state = $paref->{state};

  $state    = ___switchConsumerOn          ($paref);                                 # Verbraucher Einschaltbedingung prüfen + auslösen
  $state    = ___switchConsumerOff         ($paref);                                 # Verbraucher Ausschaltbedingung prüfen + auslösen
  $state    = ___setConsumerSwitchingState ($paref);                                 # Consumer aktuelle Schaltzustände ermitteln & setzen

  $paref->{state} = $state;

return;
}

################################################################
#  Verbraucher einschalten
################################################################
sub ___switchConsumerOn {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                                        # aktueller Unixtimestamp
  my $state = $paref->{state};
  my $debug = $paref->{debug};

  my ($cname, $dswname) = getCDnames  ($hash, $c);                                                # Consumer und Switch Device Name

  if(!$defs{$dswname}) {
      $state = qq{ERROR - the device "$dswname" is invalid. Please check device names in consumer "$c" attribute};
      Log3 ($name, 1, "$name - $state");
      return $state;
  }

  my $pstate    = ConsumerVal ($hash, $c, 'planstate',        '');
  my $startts   = ConsumerVal ($hash, $c, 'planswitchon',  undef);                                # geplante Unix Startzeit
  my $oncom     = ConsumerVal ($hash, $c, 'oncom',            '');                                # Set Command für "on"
  my $auto      = ConsumerVal ($hash, $c, 'auto',              1);
  my $calias    = ConsumerVal ($hash, $c, 'alias',        $cname);                                # Consumer Device Alias
  my $simpCstat = simplifyCstate ($pstate);
  my $isInTime  = isInTimeframe  ($hash, $c);

  my ($swoncond,$swoffcond,$infon,$infoff,$err);

  ($swoncond,$infon,$err) = isAddSwitchOnCond ($hash, $c);                                        # zusätzliche Switch on Bedingung
  Log3 ($name, 1, "$name - $err") if($err);

  ($swoffcond,$infoff,$err) = isAddSwitchOffCond ($hash, $c);                                     # zusätzliche Switch off Bedingung
  Log3 ($name, 1, "$name - $err") if($err);

  my ($iilt,$rlt) = isInLocktime ($paref);                                                        # Sperrzeit Status ermitteln

  if ($debug =~ /consumerSwitching/x) {                                                           # nur für Debugging
      my $cons   = CurrentVal  ($hash, 'consumption',  0);
      my $nompow = ConsumerVal ($hash, $c, 'power',  '-');
      my $sp     = CurrentVal  ($hash, 'surplus',      0);
      my $lang   = $paref->{lang};

      Log3 ($name, 1, qq{$name DEBUG> ############### consumer "$c" ############### });
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - general switching parameters => }.
                      qq{auto mode: $auto, current Consumption: $cons W, nompower: $nompow, surplus: $sp W, }.
                      qq{planstate: $pstate, starttime: }.($startts ? (timestampToTimestring ($startts, $lang))[0] : "undef")
           );
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - isInLocktime: $iilt}.($rlt ? ", remainLockTime: $rlt seconds" : ''));
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - current Context is >switch on< => }.
                      qq{swoncond: $swoncond, on-command: $oncom }
           );
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - isAddSwitchOnCond Info: $infon})   if($swoncond && $infon);
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - isAddSwitchOffCond Info: $infoff}) if($swoffcond && $infoff);
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - device >$dswname< is used as switching device});

      if ($simpCstat =~ /planned|priority|starting/xs && $isInTime && $iilt) {
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - switching on postponed by >isInLocktime<});
      }
  }

  my $isintable  = isInterruptable ($hash, $c, 0, 1);                                             # mit Ausgabe Interruptable Info im Debug
  my $isConsRcmd = isConsRcmd      ($hash, $c);

  $paref->{supplement} = 'swoncond not met' if(!$swoncond);
  $paref->{supplement} = 'swoffcond met'    if($swoffcond);

  if ($paref->{supplement}) {
      ___setConsumerPlanningState ($paref);
      delete $paref->{supplement};
  }

  if ($auto && $oncom && $swoncond && !$swoffcond && !$iilt &&                                    # kein Einschalten wenn zusätzliche Switch off Bedingung oder Sperrzeit zutrifft
      $simpCstat =~ /planned|priority|starting/xs && $isInTime) {                                 # Verbraucher Start ist geplant && Startzeit überschritten
      my $mode    = ConsumerVal ($hash, $c, "mode", $defcmode);                                   # Consumer Planungsmode
      my $enable  = ___enableSwitchByBatPrioCharge ($paref);                                      # Vorrangladung Batterie ?

      debugLog ($paref, "consumerSwitching", qq{$name DEBUG> Consumer switch enable by battery state: $enable});

      if ($mode eq "can" && !$enable) {                                                           # Batterieladung - keine Verbraucher "Einschalten" Freigabe
          $paref->{ps} = "priority charging battery";

          ___setConsumerPlanningState ($paref);

          delete $paref->{ps};
      }
      elsif ($mode eq "must" || $isConsRcmd) {                                                    # "Muss"-Planung oder Überschuß > Leistungsaufnahme (can)
          CommandSet(undef,"$dswname $oncom");

          $paref->{ps} = "switching on:";

          ___setConsumerPlanningState ($paref);

          delete $paref->{ps};

          $state = qq{switching Consumer '$calias' to '$oncom'};

          writeCacheToFile ($hash, "consumers", $csmcache.$name);                                  # Cache File Consumer schreiben

          Log3 ($name, 2, "$name - $state (Automatic = $auto)");
      }
  }
  elsif ((($isintable == 1 && $isConsRcmd)          ||                                             # unterbrochenen Consumer fortsetzen
          ($isintable == 3 && $isConsRcmd))         &&
         $isInTime && $auto && $oncom && !$iilt     &&
         $simpCstat =~ /interrupted|interrupting/xs) {

      CommandSet(undef,"$dswname $oncom");

      $paref->{ps} = "continuing:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      my $cause = $isintable == 3 ? 'interrupt condition no longer present' : 'existing surplus';
      $state    = qq{switching Consumer '$calias' to '$oncom', cause: $cause};

      writeCacheToFile ($hash, "consumers", $csmcache.$name);                                     # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state");
  }

return $state;
}

################################################################
#  Verbraucher ausschalten
################################################################
sub ___switchConsumerOff {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                                        # aktueller Unixtimestamp
  my $state = $paref->{state};
  my $debug = $paref->{debug};

  my $pstate  = ConsumerVal ($hash, $c, "planstate",        "");
  my $stopts  = ConsumerVal ($hash, $c, "planswitchoff", undef);                                  # geplante Unix Stopzeit
  my $auto    = ConsumerVal ($hash, $c, "auto",              1);
  my $calias  = ConsumerVal ($hash, $c, "alias",            "");                                  # Consumer Device Alias
  my $mode    = ConsumerVal ($hash, $c, "mode",      $defcmode);                                  # Consumer Planungsmode
  my $hyst    = ConsumerVal ($hash, $c, "hysteresis", $defhyst);                                  # Hysterese

  my ($cname, $dswname)        = getCDnames         ($hash, $c);                                  # Consumer und Switch Device Name
  my $offcom                   = ConsumerVal        ($hash, $c, 'offcom', '');                    # Set Command für "off"
  my ($swoffcond,$infoff,$err) = isAddSwitchOffCond ($hash, $c);                                  # zusätzliche Switch off Bedingung
  my $simpCstat                = simplifyCstate     ($pstate);
  my $cause;

  Log3 ($name, 1, "$name - $err") if($err);

  my ($iilt,$rlt) = isInLocktime ($paref);                                                        # Sperrzeit Status ermitteln

  if ($debug =~ /consumerSwitching/x) {                                                           # nur für Debugging
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - current Context is >switch off< => }.
                      qq{swoffcond: $swoffcond, off-command: $offcom}
           );

      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - isAddSwitchOffCond Info: $infoff}) if($swoffcond && $infoff);

      if ($stopts && $t >= $stopts && $iilt) {
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - switching off postponed by >isInLocktime<});
      }
  }

  my $isintable = isInterruptable ($hash, $c, $hyst, 1);                                          # mit Ausgabe Interruptable Info im Debug

  if(($swoffcond || ($stopts && $t >= $stopts)) && !$iilt &&
     ($auto && $offcom && $simpCstat =~ /started|starting|stopping|interrupt|continu/xs)) {
      CommandSet(undef,"$dswname $offcom");

      $paref->{ps} = "switching off:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      $cause = $swoffcond ? "switch-off condition (key swoffcond) is true" : "planned switch-off time reached/exceeded";
      $state = qq{switching Consumer '$calias' to '$offcom', cause: $cause};

      writeCacheToFile ($hash, "consumers", $csmcache.$name);                                                                # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state (Automatic = $auto)");
  }
  elsif ((($isintable && !isConsRcmd ($hash, $c)) || $isintable == 2) &&                          # Consumer unterbrechen
         isInTimeframe ($hash, $c) && $auto && $offcom && !$iilt      &&
         $simpCstat =~ /started|continued|interrupting/xs) {

      CommandSet(undef,"$dswname $offcom");

      $paref->{ps} = "interrupting:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      $cause = $isintable == 2 ? 'interrupt condition' : 'surplus shortage';
      $state = qq{switching Consumer '$calias' to '$offcom', cause: $cause};

      writeCacheToFile ($hash, "consumers", $csmcache.$name);                                                                # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state");
  }

return $state;
}

################################################################
#     Consumer aktuelle Schaltzustände ermitteln &
#     logische Zustände ableiten/setzen
################################################################
sub ___setConsumerSwitchingState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};
  my $state = $paref->{state};

  my $simpCstat = simplifyCstate (ConsumerVal ($hash, $c, 'planstate', ''));
  my $calias    = ConsumerVal    ($hash, $c, 'alias',                   '');                       # Consumer Device Alias
  my $auto      = ConsumerVal    ($hash, $c, 'auto',                     1);
  my $oldpsw    = ConsumerVal    ($hash, $c, 'physoffon',            'off');                       # gespeicherter physischer Schaltzustand
  my $dowri     = 0;

  debugLog ($paref, "consumerSwitching", qq{consumer "$c" - current planning state: $simpCstat \n});

  if (isConsumerPhysOn ($hash, $c) && $simpCstat eq 'starting') {
      my $mintime = ConsumerVal ($hash, $c, "mintime", $defmintime);

      if (isSunPath ($hash, $c)) {                                                                 # SunPath ist in mintime gesetzt
          my (undef, $setshift) = sunShift   ($hash, $c);
          $mintime              = (CurrentVal ($hash, 'sunsetTodayTs', 0) + $setshift) - $t;
          $mintime             /= 60;
      }

      my $stopdiff           = $mintime * 60;
      $paref->{ps}           = "switched on:";
      $paref->{startts}      = $t;
      $paref->{lastAutoOnTs} = $t;
      $paref->{stopts}       = $t + $stopdiff;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{startts};
      delete $paref->{lastAutoOnTs};
      delete $paref->{stopts};

      $state = qq{Consumer '$calias' switched on};
      $dowri = 1;
  }
  elsif (isConsumerPhysOff ($hash, $c) && $simpCstat eq 'stopping') {
      $paref->{ps}            = "switched off:";
      $paref->{stopts}        = $t;
      $paref->{lastAutoOffTs} = $t;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{stopts};
      delete $paref->{lastAutoOffTs};

      $state = qq{Consumer '$calias' switched off};
      $dowri = 1;
  }
  elsif (isConsumerPhysOn ($hash, $c) && $simpCstat eq 'continuing') {
      $paref->{ps} = "continued:";
      $paref->{lastAutoOnTs} = $t;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{lastAutoOnTs};

      $state = qq{Consumer '$calias' switched on (continued)};
      $dowri = 1;
  }
  elsif (isConsumerPhysOff ($hash, $c) && $simpCstat eq 'interrupting') {
      $paref->{ps}            = "interrupted:";
      $paref->{lastAutoOffTs} = $t;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{lastAutoOffTs};

      $state = qq{Consumer '$calias' switched off (interrupted)};
      $dowri = 1;
  }
  elsif ($oldpsw eq 'off' && isConsumerPhysOn ($hash, $c)){
      $paref->{supplement} = "$hqtxt{wexso}{$paref->{lang}}";

      ___setConsumerPlanningState ($paref);

      delete $paref->{supplement};

      $state = qq{Consumer '$calias' was external switched on};
      $dowri = 1;
  }
  elsif ($oldpsw eq 'on' && isConsumerPhysOff ($hash, $c)) {
      $paref->{supplement} = "$hqtxt{wexso}{$paref->{lang}}";

      ___setConsumerPlanningState ($paref);

      delete $paref->{supplement};

      $state = qq{Consumer '$calias' was external switched off};
      $dowri = 1;
  }

  if ($dowri) {
      writeCacheToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben
      Log3 ($name, 2, "$name - $state");
  }

return $state;
}

################################################################
#   Restlaufzeit Verbraucher ermitteln
################################################################
sub __remainConsumerTime {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                                   # aktueller Unixtimestamp

  my ($planstate,$startstr,$stoptstr) = __getPlanningStateAndTimes ($paref);
  my $stopts                          = ConsumerVal ($hash, $c, "planswitchoff", undef);     # geplante Unix Stopzeit

  $data{$type}{$name}{consumers}{$c}{remainTime} = 0;

  if (isInTimeframe($hash, $c) && (($planstate =~ /started/xs && isConsumerPhysOn($hash, $c)) | $planstate =~ /interrupt|continu/xs)) {
      my $remainTime                                 = $stopts - $t ;
      $data{$type}{$name}{consumers}{$c}{remainTime} = sprintf "%.0f", ($remainTime / 60) if($remainTime > 0);
  }

return;
}

################################################################
#   Consumer physischen Schaltstatus setzen
################################################################
sub __setPhysSwState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};

  my $pon = isConsumerPhysOn ($hash, $c) ? 'on' : 'off';

  $data{$type}{$name}{consumers}{$c}{physoffon} = $pon;

return;
}

################################################################
# Freigabe Einschalten Verbraucher durch Batterie Vorrangladung
#    return 0 -> keine Einschaltfreigabe Verbraucher
#    return 1 -> Einschaltfreigabe Verbraucher
################################################################
sub ___enableSwitchByBatPrioCharge {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};

  my $ena     = 1;
  my $pcb     = AttrVal ($name, 'affectBatteryPreferredCharge', 0);          # Vorrangladung Batterie zu X%
  my ($badev) = isBatteryUsed ($name);

  return $ena if(!$pcb || !$badev);                                          # Freigabe Schalten Consumer wenn kein Prefered Battery/Soll-Ladung 0 oder keine Batterie installiert

  my $cbcharge = CurrentVal ($hash, "batcharge", 0);                         # aktuelle Batterieladung
  $ena         = 0 if($cbcharge < $pcb);                                     # keine Freigabe wenn Batterieladung kleiner Soll-Ladung

return $ena;
}

###################################################################
#    Consumer Planstatus und Planzeit ermitteln
###################################################################
sub __getPlanningStateAndTimes {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $c     = $paref->{consumer};
  my $lang  = $paref->{lang};

  my $simpCstat = simplifyCstate (ConsumerVal ($hash, $c, 'planstate', ''));
  my $supplmnt  = ConsumerVal ($hash, $c, 'planSupplement', '');
  my $startts   = ConsumerVal ($hash, $c, 'planswitchon',   '');
  my $stopts    = ConsumerVal ($hash, $c, 'planswitchoff',  '');

  my $starttime = '';
  my $stoptime  = '';
  $starttime    = (timestampToTimestring ($startts, $lang))[0] if($startts);
  $stoptime     = (timestampToTimestring ($stopts, $lang))[0]  if($stopts);

return ($simpCstat, $starttime, $stoptime, $supplmnt);
}

################################################################
#     Energieverbrauch Vorhersage kalkulieren
#
#     Es werden nur gleiche Wochentage (Mo ... So)
#     zusammengefasst und der Durchschnitt ermittelt als
#     Vorhersage
################################################################
sub _estConsumptionForecast {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $chour   = $paref->{chour};
  my $t       = $paref->{t};
  my $day     = $paref->{day};                                                      # aktuelles Tagdatum (01...31)
  my $dayname = $paref->{dayname};                                                  # aktueller Tagname

  my $medev    = ReadingsVal ($name, "currentMeterDev",                "");         # aktuelles Meter device
  my $swdfcfc  = AttrVal     ($name, "affectConsForecastIdentWeekdays", 0);         # nutze nur gleiche Wochentage (Mo...So) für Verbrauchsvorhersage
  my ($am,$hm) = parseParams ($medev);

  $medev       = $am->[0] // "";
  return if(!$medev || !$defs{$medev});

  my $type  = $paref->{type};
  my $acref = $data{$type}{$name}{consumers};

  ## Verbrauchsvorhersage für den nächsten Tag
  ##############################################
  my $tomorrow = strftime "%a", localtime($t+86400);                                                    # Wochentagsname kommender Tag
  my $totcon   = 0;
  my $dnum     = 0;

  debugLog ($paref, "consumption", "################### Consumption forecast for the next day ###################");

  for my $n (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {
      next if ($n eq $day);                                                                             # aktuellen (unvollständigen) Tag nicht berücksichtigen

      if ($swdfcfc) {                                                                                   # nur gleiche Tage (Mo...So) einbeziehen
          my $hdn = HistoryVal ($hash, $n, 99, 'dayname', undef);
          next if(!$hdn || $hdn ne $tomorrow);
      }

      my $dcon = HistoryVal ($hash, $n, 99, 'con', 0);
      next if(!$dcon);

      debugLog ($paref, "consumption", "History Consumption day >$n<: $dcon");

      $totcon += $dcon;
      $dnum++;
  }

  if ($dnum) {
       my $tomavg                                        = int ($totcon / $dnum);
       $data{$type}{$name}{current}{tomorrowconsumption} = $tomavg;                                      # prognostizierter Durchschnittsverbrauch aller (gleicher) Wochentage

       debugLog ($paref, "consumption", "estimated Consumption for tomorrow: $tomavg, days for avg: $dnum");
  }
  else {
      my $lang = $paref->{lang};
      $data{$type}{$name}{current}{tomorrowconsumption} = $hqtxt{wfmdcf}{$lang};
  }

  ## Verbrauchsvorhersage für die nächsten Stunden
  ##################################################
  my $conh = { "01" => 0, "02" => 0, "03" => 0, "04" => 0,
               "05" => 0, "06" => 0, "07" => 0, "08" => 0,
               "09" => 0, "10" => 0, "11" => 0, "12" => 0,
               "13" => 0, "14" => 0, "15" => 0, "16" => 0,
               "17" => 0, "18" => 0, "19" => 0, "20" => 0,
               "21" => 0, "22" => 0, "23" => 0, "24" => 0,
             };

  my $conhex = { "01" => 0, "02" => 0, "03" => 0, "04" => 0,
                 "05" => 0, "06" => 0, "07" => 0, "08" => 0,
                 "09" => 0, "10" => 0, "11" => 0, "12" => 0,
                 "13" => 0, "14" => 0, "15" => 0, "16" => 0,
                 "17" => 0, "18" => 0, "19" => 0, "20" => 0,
                 "21" => 0, "22" => 0, "23" => 0, "24" => 0,
               };

  debugLog ($paref, "consumption", "################### Consumption forecast for the next hours ###################");

  for my $k (sort keys %{$data{$type}{$name}{nexthours}}) {
      my $nhtime = NexthoursVal ($hash, $k, "starttime", undef);                                    # Startzeit
      next if(!$nhtime);

      $dnum          = 0;
      my $consumerco = 0;
      my $utime      = timestringToTimestamp ($nhtime);
      my $nhday      = strftime "%a", localtime($utime);                                            # Wochentagsname des NextHours Key
      my $nhhr       = sprintf("%02d", (int (strftime "%H", localtime($utime))) + 1);               # Stunde des Tages vom NextHours Key  (01,02,...24)

      for my $m (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {
          next if($m eq $day);                                                                      # next wenn gleicher Tag (Datum) wie heute

          if ($swdfcfc) {                                                                           # nur gleiche Tage (Mo...So) einbeziehen
              my $hdn = HistoryVal ($hash, $m, 99, "dayname", undef);
              next if(!$hdn || $hdn ne $nhday);
          }

          my $hcon = HistoryVal ($hash, $m, $nhhr, "con", 0);
          next if(!$hcon);

          for my $c (sort{$a<=>$b} keys %{$acref}) {                                                # historischer Verbrauch aller registrierten Verbraucher aufaddieren
              $consumerco += HistoryVal ($hash, $m, $nhhr, "csme${c}", 0);
          }

          $conhex->{$nhhr} += $hcon - $consumerco if($hcon >= $consumerco);                         # prognostizierter Verbrauch Ex registrierter Verbraucher

          $conh->{$nhhr} += $hcon;
          $dnum++;
      }

      if ($dnum) {
           $data{$type}{$name}{nexthours}{$k}{confcEx} = int ($conhex->{$nhhr} / $dnum);
           my $conavg                                  = int ($conh->{$nhhr}   / $dnum);
           $data{$type}{$name}{nexthours}{$k}{confc}   = $conavg;                                   # Durchschnittsverbrauch aller gleicher Wochentage pro Stunde

           if (NexthoursVal ($hash, $k, "today", 0)) {                                              # nur Werte des aktuellen Tag speichern
               $data{$type}{$name}{circular}{sprintf("%02d",$nhhr)}{confc} = $conavg;

               $paref->{confc}    = $conavg;
               $paref->{nhour}    = sprintf("%02d",$nhhr);
               $paref->{histname} = "confc";
               setPVhistory ($paref);
               delete $paref->{histname};
           }

           debugLog ($paref, "consumption", "estimated Consumption for $nhday -> starttime: $nhtime, confc: $conavg, days for avg: $dnum, hist. consumption registered consumers: ".sprintf "%.2f", $consumerco);
      }
  }

return;
}

################################################################
#     Schwellenwerte auswerten und signalisieren
################################################################
sub _evaluateThresholds {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  my $bt    = ReadingsVal($name, 'batteryTrigger',  '');
  my $pt    = ReadingsVal($name, 'powerTrigger',    '');
  my $eh4t  = ReadingsVal($name, 'energyH4Trigger', '');

  if ($bt) {
      $paref->{cobj}   = 'socslidereg';
      $paref->{tname}  = 'batteryTrigger';
      $paref->{tholds} = $bt;

      __evaluateArray ($paref);
  }

  if ($pt) {
      $paref->{cobj}   = 'genslidereg';
      $paref->{tname}  = 'powerTrigger';
      $paref->{tholds} = $pt;

      __evaluateArray ($paref);
  }

  if ($eh4t) {
      $paref->{cobj}   = 'h4fcslidereg';
      $paref->{tname}  = 'energyH4Trigger';
      $paref->{tholds} = $eh4t;

      __evaluateArray ($paref);
  }

  delete $paref->{cobj};
  delete $paref->{tname};
  delete $paref->{tholds};

return;
}

################################################################
#     Threshold-Array auswerten und Readings vorbereiten
################################################################
sub __evaluateArray {
  my $paref  = shift;

  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $cobj   = $paref->{cobj};           # das CurrentVal Objekt, z.B. genslidereg
  my $tname  = $paref->{tname};          # Thresholdname, z.B. powerTrigger
  my $tholds = $paref->{tholds};         # Triggervorgaben, z.B. aus Reading powerTrigger

  my $aaref = CurrentVal ($hash, $cobj, '');
  my @aa    = ();
  @aa       = @{$aaref} if (ref $aaref eq 'ARRAY');

  return if(scalar @aa < $defslidenum);

  my $gen1   = $aa[0];
  my $gen2   = $aa[1];
  my $gen3   = $aa[2];

  my ($a,$h) = parseParams ($tholds);

  for my $key (keys %{$h}) {
      my ($knum,$cond) = $key =~ /^([0-9]+)(on|off)$/x;

      if($cond eq "on" && $gen1 > $h->{$key}) {
          next if($gen2 < $h->{$key});
          next if($gen3 < $h->{$key});
          storeReading ("${tname}_${knum}", 'on') if(ReadingsVal($name, "${tname}_${knum}", "off") eq "off");
      }

      if($cond eq "off" && $gen1 < $h->{$key}) {
          next if($gen2 > $h->{$key});
          next if($gen3 > $h->{$key});
          storeReading ("${tname}_${knum}", 'off') if(ReadingsVal($name, "${tname}_${knum}", "on") eq "on");
      }
  }

return;
}

################################################################
#      zusätzliche Readings Tomorrow_HourXX_PVforecast
#      berechnen
################################################################
sub _calcReadingsTomorrowPVFc {
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $type   = $paref->{type};

  my $h    = $data{$type}{$name}{nexthours};
  my $hods = AttrVal($name, 'ctrlNextDayForecastReadings', '');
  return if(!keys %{$h} || !$hods);

  for my $idx (sort keys %{$h}) {
      my $today = NexthoursVal ($hash, $idx, 'today', 1);
      next if($today);                                                             # aktueller Tag wird nicht benötigt

      my $h  = NexthoursVal ($hash, $idx, 'hourofday', '');
      next if(!$h);

      next if($hods !~ /$h/xs);                                                    # diese Stunde des Tages soll nicht erzeugt werden

      my $st   = NexthoursVal ($hash, $idx, 'starttime', 'XXXX-XX-XX XX:XX:XX');   # Starttime
      my $pvfc = NexthoursVal ($hash, $idx, 'pvfc', 0);

      storeReading ('Tomorrow_Hour'.$h.'_PVforecast', $pvfc.' Wh');
  }

return;
}

################################################################
#  Korrektur von Today_PVreal +
#  berechnet die prozentuale Abweichung von Today_PVforecast
#  und Today_PVreal
################################################################
sub _calcTodayPVdeviation {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $t     = $paref->{t};
  my $date  = $paref->{date};
  my $day   = $paref->{day};

  my $pvfc = ReadingsNum ($name, 'Today_PVforecast', 0);
  my $pvre = ReadingsNum ($name, 'Today_PVreal',     0);

  return if(!$pvre);

  my $dp;

  if (AttrVal($name, 'ctrlGenPVdeviation', 'daily') eq 'daily') {
      my $sstime = timestringToTimestamp ($date.' '.ReadingsVal ($name, "Today_SunSet",  '22:00').':00');
      return if($t < $sstime);

      my $diff = $pvfc - $pvre;
      $dp      = sprintf "%.2f" , (100 * $diff / $pvre);
  }
  else {
      my $rodfc = ReadingsNum ($name, 'RestOfDayPVforecast', 0);
      my $dayfc = $pvre + $rodfc;                                            # laufende Tagesprognose aus PVreal + Prognose Resttag
      $dp       = sprintf "%.2f", (100 * ($pvfc - $dayfc) / $dayfc);
  }

  $data{$type}{$name}{circular}{99}{tdayDvtn} = $dp;

  storeReading ('Today_PVdeviation', $dp.' %');

return;
}

################################################################
#     Berechnen Forecast Tag / Stunden Verschieber
#     aus aktueller Stunde + lfd. Nummer
################################################################
sub _calcDayHourMove {
  my $chour = shift;
  my $num   = shift;

  my $fh = $chour + $num;
  my $fd = int ($fh / 24) ;
  $fh    = $fh - ($fd * 24);

return ($fd,$fh);
}

################################################################
#    Spezialfall auflösen wenn Wert von $val2 dem
#    Redingwert von $val1 entspricht sofern $val1 negativ ist
################################################################
sub substSpecialCases {
  my $paref = shift;
  my $dev   = $paref->{dev};
  my $rdg   = $paref->{rdg};
  my $rdgf  = $paref->{rdgf};

  my $val1  = ReadingsNum ($dev, $rdg, 0) * $rdgf;
  my $val2;

  if($val1 <= 0) {
      $val2 = abs($val1);
      $val1 = 0;
  }
  else {
      $val2 = 0;
  }

return ($val1,$val2);
}

################################################################
#     Energieverbrauch des Hauses in History speichern
################################################################
sub saveEnergyConsumption {
  my $paref = shift;
  my $name  = $paref->{name};
  my $chour = $paref->{chour};

  my $shr     = $chour+1;
  my $pvrl    = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$shr)."_PVreal",          0);
  my $gfeedin = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$shr)."_GridFeedIn",      0);
  my $gcon    = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$shr)."_GridConsumption", 0);
  my $batin   = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$shr)."_BatIn",           0);
  my $batout  = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$shr)."_BatOut",          0);

  my $con = $pvrl - $gfeedin + $gcon - $batin + $batout;

  $paref->{con}      = $con;
  $paref->{nhour}    = sprintf "%02d", $shr;
  $paref->{histname} = 'con';
  setPVhistory ($paref);
  delete $paref->{histname};

return;
}

################################################################
#    optionale Statistikreadings erstellen
################################################################
sub genStatisticReadings {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};              # aktueller UNIX Timestamp

  my @srd = sort keys (%hcsr);
  my @csr = split ',', AttrVal ($name, 'ctrlStatisticReadings', '');

  for my $item (@srd) {
      next if($item ~~ @csr);

      deleteReadingspec ($hash, 'statistic_'.$item);
      deleteReadingspec ($hash, 'statistic_'.$item.'_.*') if($item eq 'todayConsumptionForecast');
  }

  return if(!@csr);

  for my $kpi (@csr) {
      my $def = $hcsr{$kpi}{def};
      my $par = $hcsr{$kpi}{par};

      if ($def eq 'apimaxreq') {
          $def = AttrVal ($name, 'ctrlSolCastAPImaxReq', $apimaxreqdef);
      }

      if ($hcsr{$kpi}{fnr} == 1) {
          storeReading ('statistic_'.$kpi, &{$hcsr{$kpi}{fn}} ($hash, '?All', '?All', $kpi, $def));
      }

      if ($hcsr{$kpi}{fnr} == 2) {
          $par = $kpi if(!$par);
          storeReading ('statistic_'.$kpi, &{$hcsr{$kpi}{fn}} ($hash, $par, $def).$hcsr{$kpi}{unit});
      }

      if ($hcsr{$kpi}{fnr} == 3) {
          storeReading ('statistic_'.$kpi, &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, $kpi, $def).$hcsr{$kpi}{unit});
      }

      if ($hcsr{$kpi}{fnr} == 4) {
          if ($kpi eq 'SunHours_Remain') {
              my $ss  = &{$hcsr{$kpi}{fn}} ($hash, 'sunsetTodayTs',  $def);
              my $shr = ($ss - $t) / 3600;
              $shr    = $shr < 0 ? 0 : $shr;

              storeReading ('statistic_'.$kpi, sprintf "%.2f", $shr);
          }

          if ($kpi eq 'SunMinutes_Remain') {
              my $ss  = &{$hcsr{$kpi}{fn}} ($hash, 'sunsetTodayTs',  $def);
              my $smr = ($ss - $t) / 60;
              $smr    = $smr < 0 ? 0 : $smr;

              storeReading ('statistic_'.$kpi, sprintf "%.0f", $smr);
          }

          if ($kpi eq 'runTimeTrainAI') {
              my $rtaitr = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, $kpi, $def);

              storeReading ('statistic_'.$kpi, $rtaitr);
          }

          if ($kpi eq 'daysUntilBatteryCare') {
              my $d2c = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'days2care', $def);

              storeReading ('statistic_'.$kpi, $d2c);
          }

          if ($kpi eq 'todayGridFeedIn') {
              my $idfi = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'initdayfeedin', $def);         # initialer Tagesstartwert
              my $cfi  = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'feedintotal',   $def);         # aktuelles total Feed In

              my $dfi  = $cfi - $idfi;

              storeReading ('statistic_'.$kpi, (sprintf "%.1f", $dfi).' Wh');
          }

          if ($kpi eq 'todayGridConsumption') {
              my $idgcon = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'initdaygcon',  $def);         # initialer Tagesstartwert
              my $cgcon  = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'gridcontotal', $def);         # aktuelles total Netzbezug

              my $dgcon  = $cgcon - $idgcon;

              storeReading ('statistic_'.$kpi, (sprintf "%.1f", $dgcon).' Wh');
          }

          if ($kpi eq 'todayBatIn') {
              my $idbitot = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'initdaybatintot', $def);     # initialer Tagesstartwert Batterie In total
              my $cbitot  = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'batintot',   $def);          # aktuelles total Batterie In

              my $dbi = $cbitot - $idbitot;

              storeReading ('statistic_'.$kpi, (sprintf "%.1f", $dbi).' Wh');
          }

          if ($kpi eq 'todayBatOut') {
              my $idbotot = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'initdaybatouttot', $def);     # initialer Tagesstartwert Batterie Out total
              my $cbotot  = &{$hcsr{$kpi}{fn}} ($hash, $hcsr{$kpi}{par}, 'batouttot',   $def);          # aktuelles total Batterie Out

              my $dbo = $cbotot - $idbotot;

              storeReading ('statistic_'.$kpi, (sprintf "%.1f", $dbo).' Wh');
          }

          if ($kpi eq 'dayAfterTomorrowPVforecast') {                                                  # PV Vorhersage Summe für Übermorgen (falls Werte vorhanden), Forum:#134226
              my $dayaftertomorrow = strftime "%Y-%m-%d", localtime($t + 172800);                      # Datum von Übermorgen
              my @allstrings       = split ",", ReadingsVal ($name, 'inverterStrings', '');
              my $fcsumdat         = 0;
              my $type             = $paref->{type};

              for my $strg (@allstrings) {
                 for my $starttmstr (sort keys %{$data{$type}{$name}{solcastapi}{$strg}}) {
                     next if($starttmstr !~ /$dayaftertomorrow/xs);

                     my $val    = &{$hcsr{$kpi}{fn}} ($hash, $strg, $starttmstr, $hcsr{$kpi}{par}, $def);
                     $fcsumdat += $val;

                     debugLog ($paref, 'radiationProcess', "dayaftertomorrow PV forecast (raw) - $strg -> $starttmstr -> $val Wh");
                 }
              }

              if ($fcsumdat) {
                  storeReading ('statistic_'.$kpi, (int $fcsumdat). ' Wh');
              }
              else {
                  storeReading ('statistic_'.$kpi, $fcsumdat. ' (no data available)');
              }
          }

          if ($kpi =~ /currentRunMtsConsumer_/xs) {
              my $c = (split "_", $kpi)[1];                                                          # Consumer Nummer extrahieren

              if (!AttrVal ($name, 'consumer'.$c, '')) {
                  deleteReadingspec ($hash, 'statistic_currentRunMtsConsumer_'.$c);
                  return;
              }

              my $mion = &{$hcsr{$kpi}{fn}} ($hash, $c, $hcsr{$kpi}{par}, $def);

              storeReading ('statistic_'.$kpi, (sprintf "%.0f", $mion).$hcsr{$kpi}{unit});
          }

          if ($kpi eq 'todayConsumptionForecast') {
             my $type  = $paref->{type};

             for my $idx (sort keys %{$data{$type}{$name}{nexthours}}) {
                 my $istoday = NexthoursVal ($hash, $idx, 'today', 0);
                 last if(!$istoday);

                 my $hod   = NexthoursVal ($hash, $idx, 'hourofday', '01');
                 my $confc = &{$hcsr{$kpi}{fn}} ($hash, $idx, $hcsr{$kpi}{par}, $def);

                 storeReading ('statistic_'.$kpi.'_'.$hod, $confc.$hcsr{$kpi}{unit});
             }
          }

          if ($kpi eq 'conForecastTillNextSunrise') {
             my $type  = $paref->{type};
             my $confc = 0;
             my $dono  = 1;
             my $hrs   = 0;
             my $sttm  = '';

             for my $idx (sort keys %{$data{$type}{$name}{nexthours}}) {
                 my $don = NexthoursVal ($hash, $idx, 'DoN', 2);                     # Wechsel von 0 -> 1 relevant
                 last if($don == 2);

                 $confc += &{$hcsr{$kpi}{fn}} ($hash, $idx, $hcsr{$kpi}{par}, $def);
                 $sttm   = NexthoursVal ($hash, $idx, 'starttime', '');
                 $hrs++;                                                             # Anzahl berücksichtigte Stunden

                 if ($dono == 0 && $don == 1) {
                     last;
                 }

                 $dono = $don;
             }

             my $sttmp = timestringToTimestamp ($sttm) // return;
             $sttmp   += 3600;                                                       # Beginnzeitstempel auf volle Stunde ergänzen
             my $mhrs  = $hrs * 60;                                                  # berücksichtigte volle Minuten
             my $mtsr  = ($sttmp - $t) / 60;                                         # Minuten bis nächsten Sonnenaufgang (gerundet)

             $confc    = $confc / $mhrs * $mtsr;

             storeReading ('statistic_'.$kpi, ($confc ? (sprintf "%.0f", $confc).$hcsr{$kpi}{unit} : '-'));
          }
      }
  }

return;
}

################################################################
#         Grunddaten aller registrierten Consumer speichern
################################################################
sub collectAllRegConsumers {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};

  return if(CurrentVal ($hash, 'consumerCollected', 0));                                          # Abbruch wenn Consumer bereits gesammelt

  delete $data{$type}{$name}{current}{consumerdevs};

  for my $c (1..$maxconsumer) {
      $c           = sprintf "%02d", $c;
      my $consumer = AttrVal ($name, "consumer${c}", "");
      next if(!$consumer);

      my ($ac,$hc) = parseParams ($consumer);
      $consumer    = $ac->[0] // "";

      if (!$consumer || !$defs{$consumer}) {
          my $err = qq{ERROR - the device "$consumer" doesn't exist anymore! Delete or change the attribute "consumer${c}".};
          Log3 ($name, 1, "$name - $err");
          next;
      }

      push @{$data{$type}{$name}{current}{consumerdevs}}, $consumer;                              # alle Consumerdevices in CurrentHash eintragen

      my $dswitch = $hc->{switchdev};                                                             # alternatives Schaltdevice

      if ($dswitch) {
          if (!$defs{$dswitch}) {
              my $err = qq{ERROR - the device "$dswitch" doesn't exist anymore! Delete or change the attribute "consumer${c}".};
              Log3 ($name, 1, "$name - $err");
              next;
          }

          push @{$data{$type}{$name}{current}{consumerdevs}}, $dswitch;                           # Switchdevice zusätzlich in CurrentHash eintragen
      }
      else {
          $dswitch = $consumer;
      }

      my $alias = AttrVal ($consumer, "alias", $consumer);

      my ($rtot,$utot,$ethreshold);
      if (exists $hc->{etotal}) {
          my $etotal                = $hc->{etotal};
          ($rtot,$utot,$ethreshold) = split ":", $etotal;
      }

      my ($rpcurr,$upcurr,$pthreshold);
      if (exists $hc->{pcurr}) {
          my $pcurr                     = $hc->{pcurr};
          ($rpcurr,$upcurr,$pthreshold) = split ":", $pcurr;
      }

      my $asynchron;
      if (exists $hc->{asynchron}) {
          $asynchron = $hc->{asynchron};
      }

      my $noshow;
      if (exists $hc->{noshow}) {                                                                  # Consumer ausblenden in Grafik
          $noshow = $hc->{noshow};
      }

      my ($rswstate,$onreg,$offreg);
      if(exists $hc->{swstate}) {
          ($rswstate,$onreg,$offreg) = split ":", $hc->{swstate};
      }

      my ($dswoncond,$rswoncond,$swoncondregex);
      if (exists $hc->{swoncond}) {                                                                # zusätzliche Einschaltbedingung
          ($dswoncond,$rswoncond,$swoncondregex) = split ":", $hc->{swoncond};
      }

      my ($dswoffcond,$rswoffcond,$swoffcondregex);
      if (exists $hc->{swoffcond}) {                                                               # vorrangige Ausschaltbedingung
          ($dswoffcond,$rswoffcond,$swoffcondregex) = split ":", $hc->{swoffcond};
      }

      my ($dspignorecond,$rigncond,$spignorecondregex);
      if(exists $hc->{spignorecond}) {                                                            # Bedingung um vorhandenen PV Überschuß zu ignorieren
          ($dspignorecond,$rigncond,$spignorecondregex) = split ":", $hc->{spignorecond};
      }

      my $interruptable = 0;
      my ($hyst);
      if (exists $hc->{interruptable} && $hc->{interruptable} ne '0') {
          $interruptable         = $hc->{interruptable};
          ($interruptable,$hyst) = $interruptable =~ /(.*):(.*)$/xs if($interruptable ne '1');
      }

      delete $data{$type}{$name}{consumers}{$c}{sunriseshift};
      delete $data{$type}{$name}{consumers}{$c}{sunsetshift};
      my ($riseshift, $setshift);

      if (exists $hc->{mintime}) {                                                                # Check Regex
          my $mintime = $hc->{mintime};

          if ($mintime =~ /^SunPath/xsi) {
              (undef, $riseshift, $setshift) = split ":", $mintime, 3;
              $riseshift *= 60 if($riseshift);
              $setshift  *= 60 if($setshift);
          }
      }

      my $clt;
      if (exists $hc->{locktime}) {
          $clt = $hc->{locktime};
      }

      my $rauto = $hc->{auto} // q{};
      my $ctype = $hc->{type} // $defctype;

      $data{$type}{$name}{consumers}{$c}{name}              = $consumer;                                # Name des Verbrauchers (Device)
      $data{$type}{$name}{consumers}{$c}{alias}             = $alias;                                   # Alias des Verbrauchers (Device)
      $data{$type}{$name}{consumers}{$c}{type}              = $hc->{type}         // $defctype;         # Typ des Verbrauchers
      $data{$type}{$name}{consumers}{$c}{power}             = $hc->{power};                             # Leistungsaufnahme des Verbrauchers in W
      $data{$type}{$name}{consumers}{$c}{avgenergy}         = q{};                                      # Initialwert Energieverbrauch (evtl. Überschreiben in manageConsumerData)
      $data{$type}{$name}{consumers}{$c}{mintime}           = $hc->{mintime}      // $hef{$ctype}{mt};  # Initialwert min. Einplanungsdauer (evtl. Überschreiben in manageConsumerData)
      $data{$type}{$name}{consumers}{$c}{mode}              = $hc->{mode}         // $defcmode;         # Planungsmode des Verbrauchers
      $data{$type}{$name}{consumers}{$c}{icon}              = $hc->{icon}         // q{};               # Icon für den Verbraucher
      $data{$type}{$name}{consumers}{$c}{oncom}             = $hc->{on}           // q{};               # Setter Einschaltkommando
      $data{$type}{$name}{consumers}{$c}{offcom}            = $hc->{off}          // q{};               # Setter Ausschaltkommando
      $data{$type}{$name}{consumers}{$c}{dswitch}           = $dswitch;                                 # Switchdevice zur Kommandoausführung
      $data{$type}{$name}{consumers}{$c}{autoreading}       = $rauto;                                   # Readingname zur Automatiksteuerung
      $data{$type}{$name}{consumers}{$c}{retotal}           = $rtot               // q{};               # Reading der Leistungsmessung
      $data{$type}{$name}{consumers}{$c}{uetotal}           = $utot               // q{};               # Unit der Leistungsmessung
      $data{$type}{$name}{consumers}{$c}{rpcurr}            = $rpcurr             // q{};               # Reading der aktuellen Leistungsaufnahme
      $data{$type}{$name}{consumers}{$c}{upcurr}            = $upcurr             // q{};               # Unit der aktuellen Leistungsaufnahme
      $data{$type}{$name}{consumers}{$c}{energythreshold}   = $ethreshold;                              # Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird
      $data{$type}{$name}{consumers}{$c}{powerthreshold}    = $pthreshold;                              # Schwellenwert d. aktuellen Leistung(W) ab der ein Verbraucher als aktiv gewertet wird
      $data{$type}{$name}{consumers}{$c}{notbefore}         = $hc->{notbefore}    // q{};               # nicht einschalten vor Stunde in 24h Format (00-23)
      $data{$type}{$name}{consumers}{$c}{notafter}          = $hc->{notafter}     // q{};               # nicht einschalten nach Stunde in 24h Format (00-23)
      $data{$type}{$name}{consumers}{$c}{rswstate}          = $rswstate           // 'state';           # Schaltstatus Reading
      $data{$type}{$name}{consumers}{$c}{asynchron}         = $asynchron          // 0;                 # Arbeitsweise FHEM Consumer Device
      $data{$type}{$name}{consumers}{$c}{noshow}            = $noshow             // 0;                 # ausblenden in Grafik
      $data{$type}{$name}{consumers}{$c}{locktime}          = $clt                // '0:0';             # Sperrzeit im Automatikmodus ('offlt:onlt')
      $data{$type}{$name}{consumers}{$c}{onreg}             = $onreg              // 'on';              # Regex für 'ein'
      $data{$type}{$name}{consumers}{$c}{offreg}            = $offreg             // 'off';             # Regex für 'aus'
      $data{$type}{$name}{consumers}{$c}{dswoncond}         = $dswoncond          // q{};               # Device zur Lieferung einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{rswoncond}         = $rswoncond          // q{};               # Reading zur Lieferung einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{swoncondregex}     = $swoncondregex      // q{};               # Regex einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{dswoffcond}        = $dswoffcond         // q{};               # Device zur Lieferung einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{rswoffcond}        = $rswoffcond         // q{};               # Reading zur Lieferung einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{swoffcondregex}    = $swoffcondregex     // q{};               # Regex einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{dspignorecond}     = $dspignorecond      // q{};               # Device liefert Ignore Bedingung
      $data{$type}{$name}{consumers}{$c}{rigncond}          = $rigncond           // q{};               # Reading liefert Ignore Bedingung
      $data{$type}{$name}{consumers}{$c}{spignorecondregex} = $spignorecondregex  // q{};               # Regex der Ignore Bedingung
      $data{$type}{$name}{consumers}{$c}{interruptable}     = $interruptable;                           # Ein-Zustand des Verbrauchers ist unterbrechbar
      $data{$type}{$name}{consumers}{$c}{hysteresis}        = $hyst               // $defhyst;          # Hysterese
      $data{$type}{$name}{consumers}{$c}{sunriseshift}      = $riseshift if(defined $riseshift);        # Verschiebung (Sekunden) Sonnenaufgang bei SunPath Verwendung
      $data{$type}{$name}{consumers}{$c}{sunsetshift}       = $setshift  if(defined $setshift);         # Verschiebung (Sekunden) Sonnenuntergang bei SunPath Verwendung
  }

  $data{$type}{$name}{current}{consumerCollected} = 1;

  Log3 ($name, 3, "$name - all registered consumers collected");

return;
}

################################################################
#              FHEMWEB Fn
################################################################
sub FwFn {
  my ($FW_wname, $name, $room, $pageHash) = @_;                                  # pageHash is set for summaryFn.
  my $hash = $defs{$name};

  $hash->{HELPER}{FW} = $FW_wname;

  my $ret = "<html>";
  $ret   .= entryGraphic ($name);
  $ret   .= "</html>";

  # Autorefresh nur des aufrufenden FHEMWEB-Devices
  my $al = AttrVal ($name, 'ctrlAutoRefresh', 0);
  if($al) {
      pageRefresh ($hash);
  }

return $ret;
}

###########################################################################
# Seitenrefresh festgelegt durch SolarForecast-Attribut "ctrlAutoRefresh"
# und "ctrlAutoRefreshFW"
###########################################################################
sub pageRefresh {
  my $hash = shift;
  my $name = $hash->{NAME};

  my $al = AttrVal($name, 'ctrlAutoRefresh', 0);

  if($al) {
      my $rftime = gettimeofday()+$al;

      if (!$hash->{HELPER}{AREFRESH} || $hash->{HELPER}{AREFRESH} <= gettimeofday()) {
          RemoveInternalTimer ($hash, \&pageRefresh);
          InternalTimer($rftime, \&pageRefresh, $hash, 0);

          my $rd = AttrVal ($name, 'ctrlAutoRefreshFW', $hash->{HELPER}{FW});
          { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }       ## no critic 'Map blocks'

          $hash->{HELPER}{AREFRESH} = $rftime;
          $hash->{AUTOREFRESH}      = FmtDateTime($rftime);
      }
  }
  else {
      delete $hash->{HELPER}{AREFRESH};
      delete $hash->{AUTOREFRESH};
      RemoveInternalTimer ($hash, \&pageRefresh);
  }

return;
}

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub pageAsHtml {
  my $name = shift;
  my $ftui = shift // '';
  my $gsel = shift // '';                                                                  # direkte Auswahl welche Grafik zurück gegeben werden soll (both, flow, forecast)

  my $ret = "<html>";
  $ret   .= entryGraphic ($name, $ftui, $gsel, 1);
  $ret   .= "</html>";

return $ret;
}

################################################################
#                  Einstieg Grafikanzeige
################################################################
sub entryGraphic {
  my $name = shift;
  my $ftui = shift // '';
  my $gsel = shift // '';                                                                  # direkte Auswahl welche Grafik zurück gegeben werden soll (both, flow, forecast)
  my $pah  = shift // 0;                                                                   # 1 wenn durch pageAsHtml aufgerufen

  my $hash = $defs{$name};

  # Setup Vollständigkeit/disabled prüfen
  #########################################
  my $incomplete = _checkSetupNotComplete ($hash);
  return $incomplete if($incomplete);

  # Kontext des SolarForecast-Devices speichern für Refresh
  ##########################################################
  $hash->{HELPER}{SPGDEV}    = $name;                                                      # Name des aufrufenden SolarForecastSPG-Devices
  $hash->{HELPER}{SPGROOM}   = $FW_room   ? $FW_room   : "";                               # Raum aus dem das SolarForecastSPG-Device die Funktion aufrief
  $hash->{HELPER}{SPGDETAIL} = $FW_detail ? $FW_detail : "";                               # Name des SolarForecastSPG-Devices (wenn Detailansicht)

  # Parameter f. Anzeige extrahieren
  ###################################
  my $width      = AttrNum ($name, 'graphicBeamWidth',    20);                             # zu klein ist nicht problematisch
  my $maxhours   = AttrNum ($name, 'graphicHourCount',    24);
  my $alias      = AttrVal ($name, 'alias',            $name);                             # Linktext als Aliasname oder Devicename setzen  my $html_start = AttrVal ($name, 'graphicStartHtml', undef);                             # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_start = AttrVal ($name, 'graphicStartHtml', undef);                             # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_end   = AttrVal ($name, 'graphicEndHtml',   undef);                             # beliebige HTML Strings die nach der Grafik ausgegeben werden  my $w          = $width * $maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  my $w          = $width * $maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  my $offset     = -1 * AttrNum ($name, 'graphicHistoryHour', $histhourdef);
  my $dlink      = qq{<a href="$FW_ME$FW_subdir?detail=$name">$alias</a>};

  if (!$gsel) {
      $gsel = AttrVal ($name, 'graphicSelect', 'both');                                    # Auswahl der anzuzeigenden Grafiken
  }

  my $paref = {
      hash           => $hash,
      name           => $name,
      type           => $hash->{TYPE},
      ftui           => $ftui,
      pah            => $pah,
      maxhours       => $maxhours,
      t              => time,
      modulo         => 1,
      dstyle         => qq{style='padding-left: 10px; padding-right: 10px; padding-top: 3px; padding-bottom: 3px; white-space:nowrap;'},     # TD-Style
      offset         => $offset,
      hourstyle      => AttrVal ($name, 'graphicHourStyle',                  ''),
      colorb1        => AttrVal ($name, 'graphicBeam1Color',          $b1coldef),
      colorb2        => AttrVal ($name, 'graphicBeam2Color',          $b2coldef),
      fcolor1        => AttrVal ($name, 'graphicBeam1FontColor',  $b1fontcoldef),
      fcolor2        => AttrVal ($name, 'graphicBeam2FontColor',  $b2fontcoldef),
      beam1cont      => AttrVal ($name, 'graphicBeam1Content',         'pvReal'),
      beam2cont      => AttrVal ($name, 'graphicBeam2Content',     'pvForecast'),
      caicon         => AttrVal ($name, 'consumerAdviceIcon',        $caicondef),                # Consumer AdviceIcon
      clegend        => AttrVal ($name, 'consumerLegend',            'icon_top'),                # Lage und Art Cunsumer Legende
      clink          => AttrVal ($name, 'consumerLink'  ,                     1),                # Detail-Link zum Verbraucher
      lotype         => AttrVal ($name, 'graphicLayoutType',           'double'),
      kw             => AttrVal ($name, 'graphicEnergyUnit',               'Wh'),
      height         => AttrNum ($name, 'graphicBeamHeight',                200),
      width          => $width,
      fsize          => AttrNum ($name, 'graphicSpaceSize',                  24),
      maxVal         => AttrNum ($name, 'graphicBeam1MaxVal',                 0),                # dyn. Anpassung der Balkenhöhe oder statisch ?
      show_night     => AttrNum ($name, 'graphicShowNight',                   0),                # alle Balken (Spalten) anzeigen ?
      show_diff      => AttrVal ($name, 'graphicShowDiff',                 'no'),                # zusätzliche Anzeige $di{} in allen Typen
      weather        => AttrNum ($name, 'graphicShowWeather',                 1),
      colorw         => AttrVal ($name, 'graphicWeatherColor',      $wthcolddef),                # Wetter Icon Farbe Tag
      colorwn        => AttrVal ($name, 'graphicWeatherColorNight', $wthcolndef),                # Wetter Icon Farbe Nacht
      wlalias        => AttrVal ($name, 'alias',                          $name),
      sheader        => AttrNum ($name, 'graphicHeaderShow',                  1),                # Anzeigen des Grafik Headers
      hdrDetail      => AttrVal ($name, 'graphicHeaderDetail',            'all'),                # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten
      flowgsize      => AttrVal ($name, 'flowGraphicSize',        $flowGSizedef),                # Größe Energieflußgrafik
      flowgani       => AttrVal ($name, 'flowGraphicAnimate',                 0),                # Animation Energieflußgrafik
      flowgcons      => AttrVal ($name, 'flowGraphicShowConsumer',            1),                # Verbraucher in der Energieflußgrafik anzeigen
      flowgconX      => AttrVal ($name, 'flowGraphicShowConsumerDummy',       1),                # Dummyverbraucher in der Energieflußgrafik anzeigen
      flowgconsPower => AttrVal ($name, 'flowGraphicShowConsumerPower'     ,  1),                # Verbraucher Leistung in der Energieflußgrafik anzeigen
      flowgconsTime  => AttrVal ($name, 'flowGraphicShowConsumerRemainTime',  1),                # Verbraucher Restlaufeit in der Energieflußgrafik anzeigen
      flowgconsDist  => AttrVal ($name, 'flowGraphicConsumerDistance', $fgCDdef),                # Abstand Verbrauchericons zueinander
      css            => AttrVal ($name, 'flowGraphicCss',               $cssdef),                # flowGraphicCss Styles
      genpvdva       => AttrVal ($name, 'ctrlGenPVdeviation',           'daily'),                # Methode der Abweichungsberechnung
      lang           => AttrVal ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang)),
      debug          => getDebug ($hash),                                                        # Debug Module
  };

  my $ret = q{};

  $ret .= "<span>$dlink </span><br>"  if(AttrVal($name, 'ctrlShowLink', 0));

  $ret .= $html_start if (defined($html_start));
  #$ret .= "<style>TD.solarfc {text-align: center; padding-left:1px; padding-right:1px; margin:0px;}</style>";
  $ret .= "<style>TD.solarfc {text-align: center; padding-left:5px; padding-right:5px; margin:0px;}</style>";
  $ret .= "<table class='roomoverview' width='$w' style='width:".$w."px'><tr class='devTypeTr'></tr>";
  $ret .= "<tr><td class='solarfc'>";

  # Headerzeile generieren
  ##########################
  my $header = _graphicHeader ($paref);

  # Verbraucherlegende und Steuerung
  ###################################
  my $legendtxt = _graphicConsumerLegend ($paref);

  # Headerzeile und/oder Verbraucherlegende ausblenden
  ######################################################
  if ($gsel =~ /_noHead/xs) {
      $header = q{};
  }

  if ($gsel =~ /_noCons/xs) {
      $legendtxt = q{};
  }

  $ret .= "\n<table class='block'>";                                                                        # das \n erleichtert das Lesen der debug Quelltextausgabe
  my $m = $paref->{modulo} % 2;

  if ($header) {                                                                                            # Header ausgeben
      $ret .= "<tr class='$htr{$m}{cl}'>";
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$header</td>";
      $ret .= "</tr>";

      $paref->{modulo}++;
  }

  my $clegend = $paref->{clegend};
  $m          = $paref->{modulo} % 2;

  if ($legendtxt && ($clegend eq 'top')) {
      $ret .= "<tr class='$htr{$m}{cl}'>";
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='padding-left: 10px; padding-top: 5px; padding-bottom: 5px; word-break: normal'>";
      $ret .= $legendtxt;
      $ret .= "</td>";
      $ret .= "</tr>";

      $paref->{modulo}++;
  }

  $m = $paref->{modulo} % 2;

  # Balkengrafik
  ################
  if ($gsel =~ /both/xs || $gsel =~ /forecast/xs) {
      my %hfch;
      my $hfcg  = \%hfch;                                                                                   #(hfcg = hash forecast graphic)

      # Werte aktuelle Stunde
      ##########################
      $paref->{hfcg}     = $hfcg;
      $paref->{thishour} = _beamGraphicFirstHour ($paref);

      # get consumer list and display it in Graphics
      ################################################
      _showConsumerInGraphicBeam ($paref);

      # Werte restliche Stunden
      ###########################
      my $back         = _beamGraphicRemainingHours ($paref);
      $paref->{maxVal} = $back->{maxVal};                                                                  # Startwert wenn kein Wert bereits via attr vorgegeben ist
      $paref->{maxCon} = $back->{maxCon};
      $paref->{maxDif} = $back->{maxDif};                                                                  # für Typ diff
      $paref->{minDif} = $back->{minDif};                                                                  # für Typ diff

      # Balkengrafik
      ################
      $ret .= _beamGraphic ($paref);
  }

  $m = $paref->{modulo} % 2;

  # Flußgrafik
  ##############
  if ($gsel =~ /both/xs || $gsel =~ /flow/xs) {
      $ret  .= "<tr class='$htr{$m}{cl}'>";
      my $fg = _flowGraphic ($paref);
      $ret  .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>";
      $ret  .= "$fg</td>";
      $ret  .= "</tr>";

      $paref->{modulo}++;
  }

  $m = $paref->{modulo} % 2;

  # Legende unten
  #################
  if ($legendtxt && ($clegend eq 'bottom')) {
      $ret .= "<tr class='$htr{$m}{cl}'>";
      #$ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>";
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='padding-left: 10px; padding-top: 5px; padding-bottom: 5px; word-break: normal'>";
      $ret .= "$legendtxt</td>";
      $ret .= "</tr>";
  }

  $ret .= "</table>";

  $ret .= "</td></tr>";
  $ret .= "</table>";
  $ret .= $html_end if (defined($html_end));

return $ret;
}

################################################################
#       Vollständigkeit Setup prüfen
################################################################
sub _checkSetupNotComplete {
  my $hash  = shift;
  my $ret   = q{};

  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  ### nicht mehr benötigte Readings/Daten löschen - Bereich kann später wieder raus !!
  ##########################################################################################
  #my $fcdev = ReadingsVal  ($name, "currentForecastDev",  undef);

  #if ($fcdev) {
  #    readingsSingleUpdate ($hash, "currentWeatherDev", $fcdev, 0);
  #    deleteReadingspec    ($hash, "currentForecastDev");
  #}
  ##########################################################################################

  my $is    = ReadingsVal   ($name, 'inverterStrings',     undef);                        # String Konfig
  my $wedev = ReadingsVal   ($name, 'currentWeatherDev',   undef);                        # Device Vorhersage Wetterdaten (Bewölkung etc.)
  my $radev = ReadingsVal   ($name, 'currentRadiationAPI', undef);                        # Device Strahlungsdaten Vorhersage
  my $indev = ReadingsVal   ($name, 'currentInverterDev',  undef);                        # Inverter Device
  my $medev = ReadingsVal   ($name, 'currentMeterDev',     undef);                        # Meter Device

  my $peaks = ReadingsVal   ($name, 'modulePeakString',    undef);                        # String Peak
  my $dir   = ReadingsVal   ($name, 'moduleDirection',     undef);                        # Modulausrichtung Konfig (Azimut)
  my $ta    = ReadingsVal   ($name, 'moduleTiltAngle',     undef);                        # Modul Neigungswinkel Konfig
  my $mrt   = ReadingsVal   ($name, 'moduleRoofTops',      undef);                        # RoofTop Konfiguration (SolCast API)

  my $vrmcr = SolCastAPIVal ($hash, '?VRM', '?API', 'credentials', '');                   # Victron VRM Credentials gesetzt

  my ($coset, $lat, $lon) = locCoordinates();                                             # Koordinaten im global device
  my $rip;
  $rip      = 1 if(exists $data{$type}{$name}{solcastapi}{'?IdPair'});                    # es existiert mindestens ein Paar RoofTop-ID / API-Key

  my $pv0   = NexthoursVal ($hash, 'NextHour00', 'pvfc', undef);                          # der erste PV ForeCast Wert

  my $link   = qq{<a href="$FW_ME$FW_subdir?detail=$name">$name</a>};
  my $height = AttrNum ($name, 'graphicBeamHeight', 200);
  my $lang   = getLang ($hash);

  if ((controller($name))[1] || (controller($name))[2]) {
      $ret .= "<table class='roomoverview'>";
      $ret .= "<tr style='height:".$height."px'>";
      $ret .= "<td>";
      $ret .= qq{SolarForecast device $link is disabled or inactive};
      $ret .= "</td>";
      $ret .= "</tr>";
      $ret .= "</table>";

      return $ret;
  }

  ## Anlagen Check-Icon
  #######################
  my $cmdplchk = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name plantConfigCheck', function(data){FW_okDialog(data)})"};
  my $img      = FW_makeImage('edit_settings@grey');
  my $chkicon  = "<a onClick=$cmdplchk>$img</a>";
  my $chktitle = $htitles{plchk}{$lang};

  if (!$is || !$wedev || !$radev || !$indev || !$medev || !$peaks                                       ||
     (isSolCastUsed ($hash) ? (!$rip || !$mrt) : isVictronKiUsed ($hash) ? !$vrmcr : (!$dir || !$ta )) ||
     (isForecastSolarUsed ($hash) ? !$coset : '')                                                      ||
     !defined $pv0) {
      $ret .= "<table class='roomoverview'>";
      $ret .= "<tr style='height:".$height."px'>";
      $ret .= "<td>";
      $ret .= $hqtxt{entry}{$lang};                                                         # Entry Text

      if (!$wedev) {                                                                        ## no critic 'Cascading'
          $ret .= $hqtxt{cfd}{$lang};
      }
      elsif (!$radev) {
          $ret .= $hqtxt{crd}{$lang};
      }
      elsif (!$indev) {
          $ret .= $hqtxt{cid}{$lang};
      }
      elsif (!$medev) {
          $ret .= $hqtxt{mid}{$lang};
      }
      elsif (!$is) {
          $ret .= $hqtxt{ist}{$lang};
      }
      elsif (!$peaks) {
          $ret .= $hqtxt{mps}{$lang};
      }
      elsif (!$rip && isSolCastUsed ($hash)) {
          $ret .= $hqtxt{rip}{$lang};
      }
      elsif (!$mrt && isSolCastUsed ($hash)) {
          $ret .= $hqtxt{mrt}{$lang};
      }
      elsif (!$dir && !isSolCastUsed ($hash) && !isVictronKiUsed ($hash)) {
          $ret .= $hqtxt{mdr}{$lang};
      }
      elsif (!$ta && !isSolCastUsed ($hash) && !isVictronKiUsed ($hash)) {
          $ret .= $hqtxt{mta}{$lang};
      }
      elsif (!$vrmcr && isVictronKiUsed ($hash)) {
          $ret .= $hqtxt{vrmcr}{$lang};
      }
      elsif (!$coset && isForecastSolarUsed ($hash)) {
          $ret .= $hqtxt{coord}{$lang};
      }
      elsif (!defined $pv0) {
          $ret .= $hqtxt{awd}{$lang};
          $ret .= "</td>";
          $ret .= "</tr>";
          $ret .= "<tr>";
          $ret .= qq{<td align="left" title="$chktitle"> $chkicon};
      }

      $ret .= "</td>";
      $ret .= "</tr>";
      $ret .= "</table>";
      $ret  =~ s/LINK/$link/gxs;

      return $ret;
  }

return;
}

################################################################
#         forecastGraphic Headerzeile generieren
################################################################
sub _graphicHeader {
  my $paref   = shift;
  my $sheader = $paref->{sheader};

  return if(!$sheader);

  my $hdrDetail = $paref->{hdrDetail};                     # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten
  my $ftui      = $paref->{ftui};
  my $lang      = $paref->{lang};
  my $name      = $paref->{name};
  my $hash      = $paref->{hash};
  my $kw        = $paref->{kw};
  my $dstyle    = $paref->{dstyle};                        # TD-Style

  my $lup       = ReadingsTimestamp ($name, ".lastupdateForecastValues", "0000-00-00 00:00:00");   # letzter Forecast Update

  my $co4h      = ReadingsNum ($name, "NextHours_Sum04_ConsumptionForecast", 0);
  my $coRe      = ReadingsNum ($name, "RestOfDayConsumptionForecast",        0);
  my $coTo      = ReadingsNum ($name, "Tomorrow_ConsumptionForecast",        0);
  my $coCu      = CurrentVal  ($hash, 'consumption',                         0);
  my $pv4h      = ReadingsNum ($name, "NextHours_Sum04_PVforecast",          0);
  my $pvRe      = ReadingsNum ($name, "RestOfDayPVforecast",                 0);
  my $pvTo      = ReadingsNum ($name, "Tomorrow_PVforecast",                 0);
  my $pvCu      = ReadingsNum ($name, "Current_PV",                          0);

  if ($kw eq 'kWh') {
      $co4h = sprintf ("%.1f", $co4h/1000)."&nbsp;kWh";
      $coRe = sprintf ("%.1f", $coRe/1000)."&nbsp;kWh";
      $coTo = sprintf ("%.1f", $coTo/1000)."&nbsp;kWh";
      $coCu = sprintf ("%.1f", $coCu/1000)."&nbsp;kW";
      $pv4h = sprintf ("%.1f", $pv4h/1000)."&nbsp;kWh";
      $pvRe = sprintf ("%.1f", $pvRe/1000)."&nbsp;kWh";
      $pvTo = sprintf ("%.1f", $pvTo/1000)."&nbsp;kWh";
      $pvCu = sprintf ("%.1f", $pvCu/1000)."&nbsp;kW";
  }
  else {
      $co4h .= "&nbsp;Wh";
      $coRe .= "&nbsp;Wh";
      $coTo .= "&nbsp;Wh";
      $coCu .= "&nbsp;W";
      $pv4h .= "&nbsp;Wh";
      $pvRe .= "&nbsp;Wh";
      $pvTo .= "&nbsp;Wh";
      $pvCu .= "&nbsp;W";
  }

  my $lupt    = $hqtxt{lupt}{$lang};
  my $autoct  = $hqtxt{autoct}{$lang};
  my $aihtxt  = $hqtxt{aihtxt}{$lang};
  my $lbpcq   = $hqtxt{lbpcq}{$lang};
  my $lblPv4h = $hqtxt{lblPvh}{$lang};
  my $lblPvRe = $hqtxt{lblPRe}{$lang};
  my $lblPvTo = $hqtxt{lblPTo}{$lang};
  my $lblPvCu = $hqtxt{lblPCu}{$lang};

  ## Header Start
  #################
  my $header = qq{<table width='100%'>};

  # Header Link + Status + Update Button
  #########################################
  if ($hdrDetail =~ /all|status/xs) {
      my ($scicon,$img);

      my ($year, $month, $day, $time) = $lup =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
      $lup                            = "$year-$month-$day&nbsp;$time";

      if($lang eq "DE") {
         $lup = "$day.$month.$year&nbsp;$time";
      }

      my $cmdplchk = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name plantConfigCheck', function(data){FW_okDialog(data)})"};          # Plant Check Button generieren

      if ($ftui eq 'ftui') {
          $cmdplchk = qq{"ftui.setFhemStatus('get $name plantConfigCheck')"};
      }

      ## Anlagen Check-Icon
      #######################
      $img         = FW_makeImage('edit_settings@grey');
      my $chkicon  = "<a onClick=$cmdplchk>$img</a>";
      my $chktitle = $htitles{plchk}{$lang};

      ## Update-Icon
      ################
      my $upicon =  __createUpdateIcon ($paref);

      ## Sonnenauf- und untergang
      ############################
      my $sriseimg = FW_makeImage('weather_sunrise@darkorange');
      my $ssetimg  = FW_makeImage('weather_sunset@LightCoral');
      my $srisetxt = ReadingsVal ($name, 'Today_SunRise', '-');
      my $ssettxt  = ReadingsVal ($name, 'Today_SunSet',  '-');

      ## Autokorrektur-Icon
      ######################
      my $acicon = __createAutokorrIcon ($paref);

      ## Solare API Sektion
      ########################
      my $api = isSolCastUsed       ($hash) ? 'SolCast:'        :
                isForecastSolarUsed ($hash) ? 'Forecast.Solar:' :
                isVictronKiUsed     ($hash) ? 'VictronVRM:'     :
                isDWDUsed           ($hash) ? 'DWD:'            :
                q{};

      my $nscc = ReadingsVal   ($name, 'nextSolCastCall', '?');
      my $lrt  = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_time', '-');
      my $scrm = SolCastAPIVal ($hash, '?All', '?All', 'response_message',   '-');

      if ($lrt =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x) {
          my ($sly, $slmo, $sld, $slt) = $lrt =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
          $lrt                         = "$sly-$slmo-$sld&nbsp;$slt";

          if($lang eq "DE") {
             $lrt = "$sld.$slmo.$sly&nbsp;$slt";
          }
      }

      if ($api eq 'SolCast:') {
          $api .= '&nbsp;'.$lrt;

          if ($scrm eq 'success') {
              $img = FW_makeImage ('10px-kreis-gruen.png', $htitles{scaresps}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$nscc);
          }
          elsif ($scrm =~ /Rate limit for API calls reached/i) {
              $img = FW_makeImage ('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{yheyfdl}{$lang});
          }
          elsif ($scrm =~ /ApiKey does not exist/i) {
              $img = FW_makeImage ('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{scakdne}{$lang});
          }
          elsif ($scrm =~ /Rooftop site does not exist or is not accessible/i) {
              $img = FW_makeImage ('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{scrsdne}{$lang});
          }
          else {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.': '. $scrm);
          }

          $scicon = "<a>$img</a>";

          $api .= '&nbsp;&nbsp;'.$scicon;
          $api .= '<span title="'.$htitles{dapic}{$lang}.' / '.$htitles{rapic}{$lang}.'">';
          $api .= '&nbsp;&nbsp;(';
          $api .= SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIrequests', 0);
          $api .= '/';
          $api .= SolCastAPIVal ($hash, '?All', '?All', 'todayRemainingAPIrequests', 50);
          $api .= ')';
          $api .= '</span>';
      }
      elsif ($api eq 'Forecast.Solar:') {
          $api .= '&nbsp;'.$lrt;

          if ($scrm eq 'success') {
              $img = FW_makeImage('10px-kreis-gruen.png', $htitles{scaresps}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$nscc);
          }
          elsif ($scrm =~ /You have exceeded your free daily limit/i) {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{rlfaccpr}{$lang});
          }
          else {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.': '. $scrm);
          }

          $scicon = "<a>$img</a>";

          $api .= '&nbsp;&nbsp;'.$scicon;
          $api .= '<span title="'.$htitles{dapic}{$lang}.' / '.$htitles{raricp}{$lang}.'">';
          $api .= '&nbsp;&nbsp;(';
          $api .= SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIrequests', 0);
          $api .= '/';
          $api .= SolCastAPIVal ($hash, '?All', '?All', 'requests_remaining', '-');
          $api .= ')';
          $api .= '</span>';
      }
      elsif ($api eq 'VictronVRM:') {
          $api .= '&nbsp;'.$lrt;

          if ($scrm eq 'success') {
              $img = FW_makeImage('10px-kreis-gruen.png', $htitles{scaresps}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$nscc);
          }
          else {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.': '. $scrm);
          }

          $scicon = "<a>$img</a>";

          $api .= '&nbsp;&nbsp;'.$scicon;
          $api .= '<span title="'.$htitles{dapic}{$lang}.'">';
          $api .= '&nbsp;&nbsp;(';
          $api .= SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIrequests', 0);
          $api .= ')';
          $api .= '</span>';
      }
      elsif ($api eq 'DWD:') {
          $nscc = ReadingsVal ($name, 'nextCycletime', '?');
          $api .= '&nbsp;'.$lrt;

          if ($scrm eq 'success') {
              $img = FW_makeImage('10px-kreis-gruen.png', $htitles{scaresps}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$nscc);
          }
          else {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.': '. $scrm);
          }

          $scicon = "<a>$img</a>";

          $api .= '&nbsp;&nbsp;'.$scicon;
          $api .= '<span title="'.$htitles{dapic}{$lang}.'">';
          $api .= '&nbsp;&nbsp;(';
          $api .= SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIrequests', 0);
          $api .= ')';
          $api .= '</span>';
      }

      ## Qualitäts-Icon
      ######################
      my $pcqicon = __createQuaIcon ($paref);

      ## KI Status
      ##############
      my $aiicon = __createAIicon ($paref);

      ## Abweichung PV Prognose/Erzeugung
      #####################################
      my $tdayDvtn = CircularVal ($hash, 99, 'tdayDvtn', '-');
      my $ydayDvtn = CircularVal ($hash, 99, 'ydayDvtn', '-');
      $tdayDvtn    = sprintf "%.1f %%", $tdayDvtn if(isNumeric($tdayDvtn));
      $ydayDvtn    = sprintf "%.1f %%", $ydayDvtn if(isNumeric($ydayDvtn));
      $tdayDvtn    =~ s/\./,/;
      $tdayDvtn    =~ s/\,0//;
      $ydayDvtn    =~ s/\./,/;
      $ydayDvtn    =~ s/,0//;

      my $genpvdva = $paref->{genpvdva};

      my $dvtntxt  = $hqtxt{dvtn}{$lang}.'&nbsp;';
      my $tdaytxt  = ($genpvdva eq 'daily' ? $hqtxt{tday}{$lang} : $hqtxt{ctnsly}{$lang}).':&nbsp;'."<b>".$tdayDvtn."</b>";
      my $ydaytxt  = $hqtxt{yday}{$lang}.':&nbsp;'."<b>".$ydayDvtn."</b>";

      my $text_tdayDvtn = $tdayDvtn =~ /^-[1-9]/? $hqtxt{pmtp}{$lang} :
                          $tdayDvtn =~ /^-?0,/  ? $hqtxt{petp}{$lang} :
                          $tdayDvtn =~ /^[1-9]/ ? $hqtxt{pltp}{$lang} :
                          $hqtxt{wusond}{$lang};

      my $text_ydayDvtn = $ydayDvtn =~ /^-[1-9]/? $hqtxt{pmtp}{$lang} :
                          $ydayDvtn =~ /^-?0,/  ? $hqtxt{petp}{$lang} :
                          $ydayDvtn =~ /^[1-9]/ ? $hqtxt{pltp}{$lang} :
                          $hqtxt{snbefb}{$lang};


      ## erste Header-Zeilen
      #######################
      my $alias = AttrVal ($name, "alias", $name );                                               # Linktext als Aliasname
      my $dlink = qq{<a href="$FW_ME$FW_subdir?detail=$name">$alias</a>};

      $header  .= qq{<tr>};
      $header  .= qq{<td colspan="2" align="left"  $dstyle>                <b>$dlink</b>                 </td>};
      $header  .= qq{<td colspan="1" align="left"  title="$chktitle" $dstyle> $chkicon                   </td>};
      $header  .= qq{<td colspan="3" align="left"  $dstyle>                   $lupt $lup &nbsp; $upicon  </td>};
      $header  .= qq{<td colspan="3" align="right" $dstyle>                   $api                       </td>};
      $header  .= qq{</tr>};
      $header  .= qq{<tr>};
      $header  .= qq{<td colspan="3" align="left"  $dstyle> $sriseimg &nbsp; $srisetxt &nbsp;&nbsp;&nbsp; $ssetimg &nbsp; $ssettxt  </td>};
      $header  .= qq{<td colspan="3" align="left"  $dstyle> $autoct &nbsp;&nbsp; $acicon &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; $lbpcq &nbsp;&nbsp; $pcqicon &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; $aihtxt &nbsp;&nbsp; $aiicon </td>};
      $header  .= qq{<td colspan="3" align="right" $dstyle> $dvtntxt};
      $header  .= qq{<span title="$text_tdayDvtn">};
      $header  .= qq{$tdaytxt};
      $header  .= qq{</span>};
      $header  .= qq{,&nbsp;};
      $header  .= qq{<span title="$text_ydayDvtn">};
      $header  .= qq{$ydaytxt};
      $header  .= qq{</span>};
      $header  .= qq{</td>};
      $header  .= qq{</tr>};
      $header  .= qq{<tr>};
      $header  .= qq{<td colspan="9" align="left" $dstyle><hr></td>};
      $header  .= qq{</tr>};
  }

  # Header Information pv
  ########################
  if ($hdrDetail =~ /all|pv/xs) {
      $header .= "<tr>";
      $header .= "<td $dstyle><b>".$hqtxt{pvgen}{$lang}."&nbsp;</b></td>";
      $header .= "<td $dstyle><b>$lblPvCu</b></td> <td align=right $dstyle>$pvCu</td>";
      $header .= "<td $dstyle><b>$lblPv4h</b></td> <td align=right $dstyle>$pv4h</td>";
      $header .= "<td $dstyle><b>$lblPvRe</b></td> <td align=right $dstyle>$pvRe</td>";
      $header .= "<td $dstyle><b>$lblPvTo</b></td> <td align=right $dstyle>$pvTo</td>";
      $header .= "</tr>";
  }


  # Header Information co
  #########################
  if ($hdrDetail =~ /all|co/xs) {
      $header .= "<tr>";
      $header .= "<td $dstyle><b>".$hqtxt{conspt}{$lang}."&nbsp;</b></td>";
      $header .= "<td $dstyle><b>$lblPvCu</b></td><td align=right $dstyle>$coCu</td>";
      $header .= "<td $dstyle><b>$lblPv4h</b></td><td align=right $dstyle>$co4h</td>";
      $header .= "<td $dstyle><b>$lblPvRe</b></td><td align=right $dstyle>$coRe</td>";
      $header .= "<td $dstyle><b>$lblPvTo</b></td><td align=right $dstyle>$coTo</td>";
      $header .= "</tr>";
  }

  if ($hdrDetail =~ /all|pv|co/xs) {
      $header .= qq{<tr>};
      $header .= qq{<td colspan="9" align="left" $dstyle><hr></td>};
      $header .= qq{</tr>};
  }

  # Header User Spezifikation
  #############################
  my $ownv = __createOwnSpec ($paref);
  $header .= $ownv if($ownv);

  $header .= qq{</table>};

return $header;
}

################################################################
#    erstelle Update-Icon
################################################################
sub __createUpdateIcon {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $lang  = $paref->{lang};
  my $ftui  = $paref->{ftui};

  my $upstate = ReadingsVal ($name, 'state',         '');
  my $naup    = ReadingsVal ($name, 'nextCycletime', '');

  my $cmdupdate = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction - 0 get $name data')"};                               # Update Button generieren

  if ($ftui eq 'ftui') {
      $cmdupdate = qq{"ftui.setFhemStatus('set $name clientAction - 0 get $name data')"};
  }

  my ($img, $upicon);

  if ($upstate =~ /updated|successfully|switched/ix) {
      $img    = FW_makeImage('10px-kreis-gruen.png', $htitles{upd}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$naup.'');
      $upicon = "<a onClick=$cmdupdate>$img</a>";
  }
  elsif ($upstate =~ /running/ix) {
      $img    = FW_makeImage('10px-kreis-gelb.png', 'running');
      $upicon = "<a>$img</a>";
  }
  elsif ($upstate =~ /initialized/ix) {
      $img    = FW_makeImage('1px-spacer.png', 'initialized');
      $upicon = "<a>$img</a>";
  }
  else {
      $img    = FW_makeImage('10px-kreis-rot.png', $htitles{upd}{$lang}.' ('.$htitles{natc}{$lang}.' '.$naup.')');
      $upicon = "<a onClick=$cmdupdate>$img</a>";
  }

return $upicon;
}

################################################################
#    erstelle Autokorrektur-Icon
################################################################
sub __createAutokorrIcon {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $lang  = $paref->{lang};

  my $aciimg;
  my $acitit      = q{};
  my ($acu, $aln) = isAutoCorrUsed ($name);

  if ($acu =~ /on/xs) {
      $aciimg = FW_makeImage ('10px-kreis-gruen.png', $htitles{on}{$lang}." ($acu)");
  }
  elsif ($acu =~ /standby/ixs) {
      my $pcfa    = ReadingsVal ($name, 'pvCorrectionFactor_Auto', 'off');
      my ($rtime) = $pcfa =~ /for (.*?) hours/x;
      my $img     = FW_makeImage ('10px-kreis-gelb.png', $htitles{dela}{$lang});
      $aciimg     = "$img&nbsp;(Start in ".$rtime." h)";
  }
  else {
      $acitit = $htitles{akorron}{$lang};
      $acitit =~ s/<NAME>/$name/xs;
      $aciimg = '-';
  }

  my $acicon = qq{<a title="$acitit">$aciimg</a>};

return $acicon;
}

################################################################
#    erstelle Qualitäts-Icon
################################################################
sub __createQuaIcon {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $lang  = $paref->{lang};
  my $ftui  = $paref->{ftui};

  my $pvfc00     = NexthoursVal ($hash, 'NextHour00', 'pvfc',    undef);
  my $pvcorrf00  = NexthoursVal ($hash, "NextHour00", "pvcorrf", "-/-");
  my ($pcf,$pcq) = split "/", $pvcorrf00;
  my $pvcanz     = qq{factor: $pcf / quality: $pcq};

  my $cmdfcqal = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name forecastQualities imgget', function(data){FW_okDialog(data)})"};

  if ($ftui eq 'ftui') {
      $cmdfcqal = qq{"ftui.setFhemStatus('get $name forecastQualities imgget')"};
  }

  $pcq       =~ s/-/-1/xs;
  my $pcqimg = $pcq < 0.00 ? FW_makeImage ('15px-blank',          $pvcanz) :
               $pcq < 0.60 ? FW_makeImage ('10px-kreis-rot.png',  $pvcanz) :
               $pcq < 0.80 ? FW_makeImage ('10px-kreis-gelb.png', $pvcanz) :
               FW_makeImage ('10px-kreis-gruen.png', $pvcanz);

  my $pcqtit = q();

  if(!$pvfc00 || $pcq == -1) {
      $pcqimg = "-";
      $pcqtit = $htitles{norate}{$lang};
  }

  my $pcqicon = qq{<a title="$pcqtit", onClick=$cmdfcqal>$pcqimg</a>};

return $pcqicon;
}

################################################################
#    erstelle KI Icon
################################################################
sub __createAIicon {
  my $paref    = shift;

  my $hash     = $paref->{hash};
  my $name     = $paref->{name};
  my $lang     = $paref->{lang};

  my $aiprep   = isPrepared4AI ($hash, 'full');                      # isPrepared4AI full vor Abfrage 'aicanuse' ausführen !
  my $aicanuse = CurrentVal    ($hash, 'aicanuse',       '');
  my $aitst    = CurrentVal    ($hash, 'aitrainstate', 'ok');
  my $aihit    = NexthoursVal  ($hash, 'NextHour00', 'aihit', 0);

  my $aitit = $aidtabs          ? $htitles{aimstt}{$lang} :
              $aicanuse ne 'ok' ? $htitles{ainuse}{$lang} :
              q{};
  $aitit   =~ s/<NAME>/$name/xs;

  my $aiimg  = $aidtabs          ? '--' :
               $aicanuse ne 'ok' ? '-'  :
               $aitst ne 'ok'    ? FW_makeImage ('10px-kreis-rot.png', $aitst) :
               $aihit            ? FW_makeImage ('10px-kreis-gruen.png', $hqtxt{aiwhit}{$lang}) :
               FW_makeImage ('10px-kreis-gelb.png', $hqtxt{aiwook}{$lang});

  my $aiicon = qq{<a title="$aitit">$aiimg</a>};

return $aiicon;
}

################################################################
#    erstelle Übersicht eigener Readings
################################################################
sub __createOwnSpec {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $dstyle    = $paref->{dstyle};                                                    # TD-Style
  my $hdrDetail = $paref->{hdrDetail};
  my $pah       = $paref->{pah};                                                       # 1 wenn durch pageAsHtml abgerufen

  my $vinr = 4;                                                                        # Spezifikationen in einer Zeile
  my $spec = AttrVal ($name, 'graphicHeaderOwnspec', '');
  my $uatr = AttrVal ($name, 'graphicEnergyUnit',  'Wh');
  my $show = $hdrDetail =~ /all|own/xs ? 1 : 0;

  return if(!$spec || !$show);

  my $allsets  = ' '.FW_widgetOverride ($name, getAllSets ($name),  'set').' ';
  my $allattrs = ' '.FW_widgetOverride ($name, getAllAttr ($name), 'attr').' ';        # Leerzeichen wichtig für Regexvergleich

  my @fields = split (/\s+/sx, $spec);

  my (@cats, @vals);

  for my $f (@fields) {
      if ($f =~ /^\#(.*)/xs) {
          push @cats, $1;
          next;
      }

      push @vals, $f;
  }

  my $ownv;
  my $rows = ceil (scalar(@vals) / $vinr);
  my $col  = 0;

  for (my $i = 1 ; $i <= $rows; $i++) {
      my ($h, $v, $u);

      for (my $k = 0 ; $k < $vinr; $k++) {
          ($h->{$k}{label}, $h->{$k}{elm}) = split ":", $vals[$col] if($vals[$col]);  # Label und darzustellendes Element

          $h->{$k}{elm}   //= '';
          my ($elm, $dev)   = split "@", $h->{$k}{elm};                               # evtl. anderes Devices
          $dev            //= $name;

          $col++;

          if (!$h->{$k}{label}) {
              undef $h->{$k}{label};
              next;
          }

          my $setcmd = ___getFWwidget ($name, $dev, $elm, $allsets, 'set');           # Set-Kommandos identifizieren

          if ($setcmd) {
              if ($pah) {                                                             # bei get pageAsHtml setter/attr nicht anzeigen (js Fehler)
                  undef $h->{$k}{label};
                  $setcmd = '<hidden by pageAsHtml>';
              }

              $v->{$k} = $setcmd;
              $u->{$k} = q{};

              debugLog ($paref, 'graphic', "graphicHeaderOwnspec - set-command genereated:\n$setcmd");
              next;
          }

          my $attrcmd = ___getFWwidget ($name, $dev, $elm, $allattrs, 'attr');        # Attr-Kommandos identifizieren

          if ($attrcmd) {
              if ($pah) {                                                             # bei get pageAsHtml setter/attr nicht anzeigen (js Fehler)
                  undef $h->{$k}{label};
                  $attrcmd = '<hidden by pageAsHtml>';
              }

              $v->{$k} = $attrcmd;
              $u->{$k} = q{};

              debugLog ($paref, 'graphic', "graphicHeaderOwnspec - attr-command genereated:\n$attrcmd");
              next;
          }

          $v->{$k} = ReadingsVal ($dev, $elm, '');

          if ($v->{$k} =~ /^\s*(-?\d+(\.\d+)?)/xs) {
              ($v->{$k}, $u->{$k}) = split /\s+/, ReadingsVal ($dev, $elm, '');       # Value und Unit trennen wenn Value numerisch
          }

          $v->{$k} //= q{};
          $u->{$k} //= q{};

          $paref->{dev}  = $dev;
          $paref->{rdg}  = $elm;
          $paref->{val}  = $v->{$k};
          $paref->{unit} = $u->{$k};

          ($v->{$k}, $u->{$k}) = ___ghoValForm ($paref);

          delete $paref->{dev};
          delete $paref->{rdg};
          delete $paref->{val};
          delete $paref->{unit};

          next if(!$u->{$k});

          if ($uatr eq 'kWh') {
              if ($u->{$k} =~ /^Wh/xs) {
                  $v->{$k} = sprintf "%.1f",($v->{$k} / 1000);
                  $u->{$k} = 'kWh';
              }
          }

          if ($uatr eq 'Wh') {
              if ($u->{$k} =~ /^kWh/xs) {
                  $v->{$k} = sprintf "%.0f",($v->{$k} * 1000);
                  $u->{$k} = 'Wh';
              }
          }
      }

      $ownv .= "<tr>";
      $ownv .= "<td $dstyle>".($cats[$i-1] ? '<b>'.$cats[$i-1].'</b>' : '')."</td>";
      $ownv .= "<td $dstyle><b>".$h->{0}{label}.":</b></td> <td align=right $dstyle>".$v->{0}." ".$u->{0}."</td>" if(defined $h->{0}{label});
      $ownv .= "<td $dstyle><b>".$h->{1}{label}.":</b></td> <td align=right $dstyle>".$v->{1}." ".$u->{1}."</td>" if(defined $h->{1}{label});
      $ownv .= "<td $dstyle><b>".$h->{2}{label}.":</b></td> <td align=right $dstyle>".$v->{2}." ".$u->{2}."</td>" if(defined $h->{2}{label});
      $ownv .= "<td $dstyle><b>".$h->{3}{label}.":</b></td> <td align=right $dstyle>".$v->{3}." ".$u->{3}."</td>" if(defined $h->{3}{label});
      $ownv .= "</tr>";
  }

  $ownv .= qq{<tr>};
  $ownv .= qq{<td colspan="9" align="left" $dstyle><hr></td>};
  $ownv .= qq{</tr>};

return $ownv;
}

################################################################
#  liefert ein FHEMWEB set/attr Widget zurück
################################################################
sub ___getFWwidget {
  my $name = shift;
  my $dev  = shift // $name;                # Device des Elements, default=$name
  my $elm  = shift;                         # zu prüfendes Element (setter / attribut)
  my $allc = shift;                         # Kommandovorrat -> ist Element enthalten?
  my $ctyp = shift // 'set';                # Kommandotyp: set/attr

  return if(!$elm);

  my $widget = '';
  my ($current, $reading);

  if ($dev ne $name) {                                                                   # Element eines anderen Devices verarbeiten
      if ($ctyp eq 'set') {
          $allc = ' '.FW_widgetOverride ($dev, getAllSets($dev), 'set').' ';             # Leerzeichen wichtig für Regexvergleich
      }
      elsif ($ctyp eq 'attr') {
          $allc = ' '.FW_widgetOverride ($dev, getAllAttr($dev), 'attr').' ';
      }
  }

  if ($allc =~ /\s$elm:?(.*?)\s/xs) {                                                    # Element in allen Sets oder Attr enthalten
      my $arg = $1;

      if (!$arg || $arg eq 'textField' || $arg eq 'textField-long') {                    # Label (Reading) ausblenden -> siehe fhemweb.js function FW_createTextField Zeile 1657
          $arg = 'textFieldNL';
      }

      if ($arg !~ /^\#/xs && $arg !~ /^$allwidgets/xs) {
          $arg = '#,'.$arg;
      }

      if ($arg =~ 'slider') {                                                            # Widget slider in selectnumbers für Kopfgrafik umsetzen
          my ($wid, $min, $step, $max, $float) = split ",", $arg;
          $arg = "selectnumbers,$min,$step,$max,0,lin";
      }

      if ($ctyp eq 'attr') {                                                             # Attributwerte als verstecktes Reading abbilden
          $current = AttrVal ($dev, $elm, '');
          $reading = '.'.$dev.'_'.$elm;
      }
      else {
          $current = ReadingsVal ($dev, $elm, '');
          if($dev ne $name) {
              $reading = '.'.$dev.'_'.$elm;                                              # verstecktes Reading in SolCast abbilden wenn Set-Kommando aus fremden Device
          }
          else {
              $reading = $elm;
          }
      }

      if ($reading && $reading =~ /^\./xs) {                                             # verstecktes Reading für spätere Löschung merken
          push @widgetreadings, $reading;
          readingsSingleUpdate ($defs{$name}, $reading, $current, 0);
      }

      $widget = ___widgetFallback ( { name     => $name,
                                      dev      => $dev,
                                      ctyp     => $ctyp,
                                      elm      => $elm,
                                      reading  => $reading,
                                      arg      => $arg
                                    }
                                  );

      if (!$widget) {
          $widget = FW_pH ("cmd=$ctyp $dev $elm", $elm, 0, "", 1, 1);
      }
  }

return $widget;
}

################################################################
#        adaptierte FW_widgetFallbackFn aus FHEMWEB
################################################################
sub ___widgetFallback {
  my $pars     = shift;
  my $name     = $pars->{name};
  my $dev      = $pars->{dev};
  my $ctyp     = $pars->{ctyp};
  my $elm      = $pars->{elm};
  my $reading  = $pars->{reading};
  my $arg      = $pars->{arg};

  return '' if(!$arg || $arg eq "noArg");

  my $current = ReadingsVal ($name, $reading, undef);

  if (!defined $current) {
      $reading = 'state';
      $current = ' ';
  }

  if ($current =~ /((<td|<div|<\/div>).*?)/xs) {                   # Eleminierung von störenden HTML Elementen aus aktuellem Readingwert
      $current = ' ';
  }

  $current =~ s/$elm //;
  $current = ReplaceEventMap ($dev, $current, 1);

  return "<div class='fhemWidget' cmd='$elm' reading='$reading' ".
                "dev='$dev' arg='$arg' current='$current' type='$ctyp'></div>";
}

################################################################
#      ownHeader ValueFormat
################################################################
sub ___ghoValForm {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $dev   = $paref->{dev};
  my $rdg   = $paref->{rdg};
  my $val   = $paref->{val};
  my $unit  = $paref->{unit};
  my $type  = $paref->{type};

  my $fn = $data{$type}{$name}{func}{ghoValForm};
  return ($val, $unit) if(!$fn || !$dev || !$rdg || !defined $val);

  my $DEVICE  = $dev;
  my $READING = $rdg;
  my $VALUE   = $val;
  my $UNIT    = $unit;
  my $err;

  if (!ref $fn && $fn =~ m/^\{.*\}$/xs) {                                       # normale Funktionen
      my $efn = eval $fn;

      if ($@) {
          Log3 ($name, 1, "$name - ERROR in execute graphicHeaderOwnspecValForm: ".$@);
          $err = $@;
      }
      else {
          if (ref $efn ne 'HASH') {
              $val  = $VALUE;
              $unit = $UNIT;
          }
          else {
              $fn = $efn;
          }
      }
  }

  if (ref $fn eq 'HASH') {                                                     # Funktionshash
      my $vf = "";
      $vf = $fn->{$rdg}             if(exists $fn->{$rdg});
      $vf = $fn->{"$dev.$rdg"}      if(exists $fn->{"$dev.$rdg"});
      $vf = $fn->{"$rdg.$val"}      if(exists $fn->{"$rdg.$val"});
      $vf = $fn->{"$dev.$rdg.$val"} if(exists $fn->{"$dev.$rdg.$val"});
      $fn = $vf;

      if ($fn =~ m/^%/xs) {
          $val = sprintf $fn, $val;
      }
      elsif ($fn ne "") {
          my $vnew = eval $fn;

          if ($@) {
              Log3 ($name, 1, "$name - ERROR in execute graphicHeaderOwnspecValForm: ".$@);
              $err = $@;
          }
          else {
              $val = $vnew;
          }
      }
  }

  if ($val =~ /^\s*(-?\d+(\.\d+)?)/xs) {                                       # Value und Unit numerischer Werte trennen
      ($val, my $u1) = split /\s+/, $val;
      $unit          = $u1 ? $u1 : $unit;
  }

  if ($err) {
      $err            = (split "at", $err)[0];
      $paref->{state} = 'ERROR - graphicHeaderOwnspecValForm: '.$err;
      singleUpdateState ($paref);
  }

return ($val, $unit);
}

################################################################
#    Consumer in forecastGraphic (Balken) anzeigen
#    (Hat zur Zeit keine Wirkung !)
################################################################
sub _showConsumerInGraphicBeam {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hfcg  = $paref->{hfcg};
  my $lang  = $paref->{lang};

  # get consumer list and display it in Graphics
  ################################################
  my @consumers = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};                          # definierte Verbraucher ermitteln

  for (@consumers) {
      next if(!$_);
      my ($itemName, undef) = split(':',$_);
      $itemName =~ s/^\s+|\s+$//gx;                                                              # trim it, if blanks were used
      $_        =~ s/^\s+|\s+$//gx;                                                              # trim it, if blanks were used

      # check if listed device is planned
      ####################################
      if (ReadingsVal($name, $itemName."_Planned", "no") eq "yes") {
          #get start and end hour
          my ($start, $end);                                                                     # werden auf Balken Pos 0 - 23 umgerechnet, nicht auf Stunde !!, Pos = 24 -> ungültige Pos = keine Anzeige

          if($lang eq "DE") {
              (undef,undef,undef,$start) = ReadingsVal($name, $itemName."_PlannedOpTimeBegin", '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name, $itemName."_PlannedOpTimeEnd",   '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
          }
          else {
              (undef,undef,undef,$start) = ReadingsVal($name, $itemName."_PlannedOpTimeBegin", '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name, $itemName."_PlannedOpTimeEnd",   '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
          }

          $start   = int($start);
          $end     = int($end);
          my $flag = 0;                                                                          # default kein Tagesverschieber

          #correct the hour for accurate display
          #######################################
          if ($start < $hfcg->{0}{time}) {                                                       # gridconsumption seems to be tomorrow
              $start = 24-$hfcg->{0}{time}+$start;
              $flag  = 1;
          }
          else {
              $start -= $hfcg->{0}{time};
          }

          if ($flag) {                                                                           # gridconsumption seems to be tomorrow
              $end = 24-$hfcg->{0}{time}+$end;
          }
          else {
              $end -= $hfcg->{0}{time};
          }

          $_ .= ":".$start.":".$end;
      }
      else {
          $_ .= ":24:24";
      }
  }

return;
}

################################################################
#         Verbraucherlegende und Steuerung
################################################################
sub _graphicConsumerLegend {
  my $paref                    = shift;
  my $hash                     = $paref->{hash};
  my $name                     = $paref->{name};                                                    # Consumer AdviceIcon
  my ($clegendstyle, $clegend) = split '_', $paref->{clegend};
  my $clink                    = $paref->{clink};

  my $type                     = $paref->{type};
  my @consumers                = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};              # definierte Verbraucher ermitteln

  $clegend                     = '' if($clegendstyle eq 'none' || !int @consumers);
  $paref->{clegend}            = $clegend;

  return if(!$clegend );

  my $ftui   = $paref->{ftui};
  my $lang   = $paref->{lang};
  my $dstyle = $paref->{dstyle};                        # TD-Style

  my $staticon;

  ## Tabelle Start
  #################
  my $ctable = qq{<table align='left' width='100%'>};
  $ctable   .= qq{<tr style='font-weight:bold; text-align:center;'>};

  $ctable   .= qq{<td style='text-align:left' $dstyle> $hqtxt{cnsm}{$lang}  </td>};
  $ctable   .= qq{<td>                                                      </td>};
  $ctable   .= qq{<td>                                                      </td>};
  $ctable   .= qq{<td $dstyle>                         $hqtxt{eiau}{$lang}  </td>};
  $ctable   .= qq{<td $dstyle>                         $hqtxt{auto}{$lang}  </td>};

  $ctable   .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;</td>};
  $ctable   .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;</td>};

  my $cnum   = @consumers;

  if ($cnum > 1) {
      $ctable .= qq{<td style='text-align:left' $dstyle> $hqtxt{cnsm}{$lang}  </td>};
      $ctable .= qq{<td>                                                      </td>};
      $ctable .= qq{<td>                                                      </td>};
      $ctable .= qq{<td $dstyle>                         $hqtxt{eiau}{$lang}  </td>};
      $ctable .= qq{<td $dstyle>                         $hqtxt{auto}{$lang}  </td>};
  }
  else {
      my $blk  = '&nbsp;' x 8;
      $ctable .= qq{<td $dstyle> $blk </td>};
      $ctable .= qq{<td>         $blk </td>};
      $ctable .= qq{<td>         $blk </td>};
      $ctable .= qq{<td $dstyle> $blk </td>};
      $ctable .= qq{<td $dstyle> $blk </td>};
  }

  $ctable   .= qq{</tr>};

  if ($clegend ne 'top') {
       $ctable .= qq{<tr><td colspan="12"><hr></td></tr>};
  }

  my $modulo = 1;
  my $tro    = 0;

  for my $c (@consumers) {
      next if(isConsumerNoshow ($hash, $c) =~ /^[12]$/xs);                                          # Consumer ausblenden

      my $caicon            = $paref->{caicon};                                                     # Consumer AdviceIcon
      my ($cname, $dswname) = getCDnames  ($hash, $c);                                              # Consumer und Switch Device Name
      my $calias            = ConsumerVal ($hash, $c, 'alias',   $cname);                           # Alias des Consumerdevices
      my $cicon             = ConsumerVal ($hash, $c, 'icon',        '');                           # Icon des Consumerdevices
      my $oncom             = ConsumerVal ($hash, $c, 'oncom',       '');                           # Consumer Einschaltkommando
      my $offcom            = ConsumerVal ($hash, $c, 'offcom',      '');                           # Consumer Ausschaltkommando
      my $autord            = ConsumerVal ($hash, $c, 'autoreading', '');                           # Readingname f. Automatiksteuerung
      my $auto              = ConsumerVal ($hash, $c, 'auto',         1);                           # Automatic Mode

      my $cmdon      = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction $c 0 set $dswname $oncom')"};
      my $cmdoff     = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction $c 0 set $dswname $offcom')"};
      my $cmdautoon  = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction $c 0 setreading $dswname $autord 1')"};
      my $cmdautooff = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction $c 0 setreading $dswname $autord 0')"};
      my $implan     = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction $c 0 consumerImmediatePlanning $c')"};

      if ($ftui eq "ftui") {
          $cmdon      = qq{"ftui.setFhemStatus('set $name clientAction $c 0 set $dswname $oncom')"};
          $cmdoff     = qq{"ftui.setFhemStatus('set $name clientAction $c 0 set $dswname $offcom')"};
          $cmdautoon  = qq{"ftui.setFhemStatus('set $name clientAction $c 0 setreading $cname $autord 1')"};
          $cmdautooff = qq{"ftui.setFhemStatus('set $name clientAction $c 0 setreading $cname $autord 0')"};
          $implan     = qq{"ftui.setFhemStatus('set $name clientAction $c 0 consumerImmediatePlanning $c')"};
      }

      $cmdon      = q{} if(!$oncom);
      $cmdoff     = q{} if(!$offcom);
      $cmdautoon  = q{} if(!$autord);
      $cmdautooff = q{} if(!$autord);

      my $swicon  = q{};                                                                              # Schalter ein/aus Icon
      my $auicon  = q{};                                                                              # Schalter Automatic Icon
      my $isricon = q{};                                                                              # Zustand IsRecommended Icon

      $paref->{consumer} = $c;

      my ($planstate,$starttime,$stoptime,$supplmnt) = __getPlanningStateAndTimes ($paref);
      $supplmnt                                      = '-' if(!$supplmnt);
      my ($iilt,$rlt)                                = isInLocktime ($paref);                         # Sperrzeit Status ermitteln

      my $pstate      = $caicon eq "times"    ? $hqtxt{pstate}{$lang}  : $htitles{pstate}{$lang};
      my $surplusinfo = isConsRcmd($hash, $c) ? $htitles{splus}{$lang} : $htitles{nosplus}{$lang};

      $pstate =~ s/<pstate>/$planstate/xs;
      $pstate =~ s/<supplmnt>/$supplmnt/xs;
      $pstate =~ s/<start>/$starttime/xs;
      $pstate =~ s/<stop>/$stoptime/xs;
      $pstate =~ s/<RLT>/$rlt/xs;
      $pstate =~ s/\s+/&nbsp;/gxs         if($caicon eq "times");

      if ($clink) {
          $calias = qq{<a title="$cname" href="$FW_ME$FW_subdir?detail=$cname" style="color: inherit !important;" target="_blank">$c - $calias</a>};
      }

      if ($caicon ne "none") {
          if (isInTimeframe($hash, $c)) {                                                             # innerhalb Planungszeitraum ?
              if ($caicon eq "times") {
                  $isricon = $pstate.'<br>'.$surplusinfo;
              }
              else {
                  $isricon = "<a title='$htitles{conrec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage($caicon, '')." </a>";
                  if ($planstate =~ /priority/xs) {
                      my (undef,$color) = split '@', $caicon;
                      $color            = $color ? '@'.$color : '';
                      $isricon          = "<a title='$htitles{conrecba}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage('batterie'.$color, '')." </a>";
                  }
              }
          }
          else {
              if ($caicon eq "times") {
                  $isricon =  $pstate.'<br>'.$surplusinfo;
              }
              else {
                  ($caicon) = split '@', $caicon;
                  $isricon  = "<a title='$htitles{connorec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage($caicon.'@grey', '')." </a>";
              }
          }
      }

      if ($modulo % 2){
          $ctable .= qq{<tr>};
          $tro     = 1;
      }

      if (!$auto) {
          $staticon = FW_makeImage('ios_off_fill@red', $htitles{iaaf}{$lang});
          $auicon   = "<a title= '$htitles{iaaf}{$lang}' onClick=$cmdautoon> $staticon</a>";
      }

      if ($auto) {
          $staticon = FW_makeImage('ios_on_till_fill@orange', $htitles{ieas}{$lang});
          $auicon   = "<a title='$htitles{ieas}{$lang}' onClick=$cmdautooff> $staticon</a>";
      }

      if (isConsumerPhysOff($hash, $c)) {                                                       # Schaltzustand des Consumerdevices off
          if ($cmdon) {
              $staticon = FW_makeImage('ios_off_fill@red', $htitles{iave}{$lang});
              $swicon   = "<a title='$htitles{iave}{$lang}' onClick=$cmdon> $staticon</a>";
          }
          else {
              $staticon = FW_makeImage('ios_off_fill@grey', $htitles{ians}{$lang});
              $swicon   = "<a title='$htitles{ians}{$lang}'> $staticon</a>";
          }
      }

      if (isConsumerPhysOn($hash, $c)) {                                                        # Schaltzustand des Consumerdevices on
          if($cmdoff) {
              $staticon = FW_makeImage('ios_on_fill@green', $htitles{ieva}{$lang});
              $swicon   = "<a title='$htitles{ieva}{$lang}' onClick=$cmdoff> $staticon</a>";
          }
          else {
              $staticon = FW_makeImage('ios_on_fill@grey', $htitles{iens}{$lang});
              $swicon   = "<a title='$htitles{iens}{$lang}'> $staticon</a>";
          }
      }

      if ($clegendstyle eq 'icon') {
          $cicon   = FW_makeImage($cicon);
          $ctable .= "<td style='text-align:left; white-space:nowrap;' $dstyle>$calias       </td>";
          $ctable .= "<td style='text-align:center'                    $dstyle>$cicon        </td>";
          $ctable .= "<td style='text-align:center'                    $dstyle>$isricon      </td>";
          $ctable .= "<td style='text-align:center'                    $dstyle>$swicon       </td>";
          $ctable .= "<td style='text-align:center'                    $dstyle>$auicon       </td>";
      }
      else {
          my (undef,$co) = split '@', $cicon;
          $co      = '' if (!$co);
          $ctable .= "<td style='text-align:left'   $dstyle><font color='$co'>$calias </font></td>";
          $ctable .= "<td>                                                                   </td>";
          $ctable .= "<td>                                  $isricon                         </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$swicon                          </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$auicon                          </td>";
      }

      if (!($modulo % 2)) {
          $ctable .= qq{</tr>};
          $tro     = 0;
      }
      else {
          $ctable .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;</td>};
          $ctable .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;</td>};
      }

      $modulo++;
  }

  delete $paref->{consumer};

  $ctable .= qq{</tr>} if($tro);

  if ($clegend ne 'bottom') {
       $ctable .= qq{<tr><td colspan='12'><hr></td></tr>};
  }

  $ctable .= qq{</table>};

return $ctable;
}

################################################################
#    Werte aktuelle Stunde für forecastGraphic
################################################################
sub _beamGraphicFirstHour {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $hfcg      = $paref->{hfcg};
  my $offset    = $paref->{offset};
  my $hourstyle = $paref->{hourstyle};
  my $beam1cont = $paref->{beam1cont};
  my $beam2cont = $paref->{beam2cont};

  my $day;

  my $stt                              = NexthoursVal ($hash, "NextHour00", "starttime", '0000-00-00 24');
  my ($year,$month,$day_str,$thishour) = $stt =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
  my ($val1,$val2,$val3,$val4)         = (0,0,0,0);

  $thishour++;

  $hfcg->{0}{time_str} = $thishour;
  $thishour            = int($thishour);                                                                    # keine führende Null

  $hfcg->{0}{time}     = $thishour;
  $hfcg->{0}{day_str}  = $day_str;
  $day                 = int($day_str);
  $hfcg->{0}{day}      = $day;
  $hfcg->{0}{mktime}   = fhemTimeLocal(0,0,$thishour,$day,int($month)-1,$year-1900);                        # gleich die Unix Zeit dazu holen

  if ($offset) {
      $hfcg->{0}{time} += $offset;

      if ($hfcg->{0}{time} < 0) {
          $hfcg->{0}{time}   += 24;
          my $n_day           = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * abs($offset)));       # Achtung : Tageswechsel - day muss jetzt neu berechnet werden !
          $hfcg->{0}{day}     = int($n_day);
          $hfcg->{0}{day_str} = $n_day;
      }

      $hfcg->{0}{time_str} = sprintf('%02d', $hfcg->{0}{time});

      $val1 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'pvfc',  0);
      $val2 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'pvrl',  0);
      $val3 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'gcons', 0);
      $val4 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'confc', 0);

      $hfcg->{0}{weather} = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'weatherid', 999);
      $hfcg->{0}{wcc}     = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'wcc',       '-');
  }
  else {
      $val1 = CircularVal ($hash, $hfcg->{0}{time_str}, 'pvfc',  0);
      $val2 = CircularVal ($hash, $hfcg->{0}{time_str}, 'pvrl',  0);
      $val3 = CircularVal ($hash, $hfcg->{0}{time_str}, 'gcons', 0);
      $val4 = CircularVal ($hash, $hfcg->{0}{time_str}, 'confc', 0);

      $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, 'weatherid', 999);
      #$val4   = (ReadingsVal($name,"ThisHour_IsConsumptionRecommended",'no') eq 'yes' ) ? $icon : 999;
  }

  $hfcg->{0}{time_str} = sprintf('%02d', $hfcg->{0}{time}-1).$hourstyle;
  $hfcg->{0}{beam1}    = ($beam1cont eq 'pvForecast') ? $val1 : ($beam1cont eq 'pvReal') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
  $hfcg->{0}{beam2}    = ($beam2cont eq 'pvForecast') ? $val1 : ($beam2cont eq 'pvReal') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;
  $hfcg->{0}{diff}     = $hfcg->{0}{beam1} - $hfcg->{0}{beam2};

return ($thishour);
}

################################################################
#    Werte restliche Stunden für forecastGraphic
################################################################
sub _beamGraphicRemainingHours {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $hfcg      = $paref->{hfcg};
  my $offset    = $paref->{offset};
  my $maxhours  = $paref->{maxhours};
  my $hourstyle = $paref->{hourstyle};
  my $beam1cont = $paref->{beam1cont};
  my $beam2cont = $paref->{beam2cont};
  my $maxVal    = $paref->{maxVal};                                                                     # dyn. Anpassung der Balkenhöhe oder statisch ?

  $maxVal  //= $hfcg->{0}{beam1};                                                                       # Startwert wenn kein Wert bereits via attr vorgegeben ist

  my ($val1,$val2,$val3,$val4);

  my $maxCon = $hfcg->{0}{beam1};
  my $maxDif = $hfcg->{0}{diff};                                                                        # für Typ diff
  my $minDif = $hfcg->{0}{diff};                                                                        # für Typ diff

  for my $i (1..($maxhours*2)-1) {                                                                      # doppelte Anzahl berechnen    my $val1 = 0;
      $val2 = 0;
      $val3 = 0;
      $val4 = 0;

      $hfcg->{$i}{time}  = $hfcg->{0}{time} + $i;

      while ($hfcg->{$i}{time} > 24) {
          $hfcg->{$i}{time} -= 24;                                                                      # wird bis zu 2x durchlaufen
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time});

      my $nh;                                                                                           # next hour

      if ($offset < 0) {
          if ($i <= abs($offset)) {                                                                     # $daystr stimmt nur nach Mitternacht, vor Mitternacht muß $hfcg->{0}{day_str} als Basis verwendet werden !
              my $ds = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * abs($offset+$i)));         # V0.49.4

              # Sonderfall Mitternacht
              $ds   = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * (abs($offset-$i+1)))) if ($hfcg->{$i}{time} == 24);  # V0.49.4

              $val1 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'pvfc',  0);
              $val2 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'pvrl',  0);
              $val3 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'gcons', 0);
              $val4 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'confc', 0);

              $hfcg->{$i}{weather} = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'weatherid', 999);
              $hfcg->{$i}{wcc}     = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'wcc',       '-');
          }
          else {
              $nh = sprintf '%02d', $i + $offset;
          }
      }
      else {
          $nh = sprintf '%02d', $i;
      }

      if (defined $nh) {
          $val1                = NexthoursVal ($hash, 'NextHour'.$nh, 'pvfc',         0);
          $val4                = NexthoursVal ($hash, 'NextHour'.$nh, 'confc',        0);
          $hfcg->{$i}{weather} = NexthoursVal ($hash, 'NextHour'.$nh, 'weatherid',  999);
          $hfcg->{$i}{wcc}     = NexthoursVal ($hash, 'NextHour'.$nh, 'cloudcover', '-');
          #$val4   = (ReadingsVal($name,"NextHour".$ii."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time}-1).$hourstyle;
      $hfcg->{$i}{beam1}    = ($beam1cont eq 'pvForecast') ? $val1 : ($beam1cont eq 'pvReal') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
      $hfcg->{$i}{beam2}    = ($beam2cont eq 'pvForecast') ? $val1 : ($beam2cont eq 'pvReal') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;

      $hfcg->{$i}{beam1} //= 0;
      $hfcg->{$i}{beam2} //= 0;
      $hfcg->{$i}{diff}    = $hfcg->{$i}{beam1} - $hfcg->{$i}{beam2};

      $maxVal = $hfcg->{$i}{beam1} if ($hfcg->{$i}{beam1} > $maxVal);
      $maxCon = $hfcg->{$i}{beam2} if ($hfcg->{$i}{beam2} > $maxCon);
      $maxDif = $hfcg->{$i}{diff}  if ($hfcg->{$i}{diff}  > $maxDif);
      $minDif = $hfcg->{$i}{diff}  if ($hfcg->{$i}{diff}  < $minDif);
  }

  my $back = {
      maxVal => $maxVal,
      maxCon => $maxCon,
      maxDif => $maxDif,
      minDif => $minDif,
  };

return ($back);
}

################################################################
#    Balkenausgabe für forecastGraphic
################################################################
sub _beamGraphic {
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $hfcg       = $paref->{hfcg};
  my $maxhours   = $paref->{maxhours};
  my $weather    = $paref->{weather};
  my $show_night = $paref->{show_night};                     # alle Balken (Spalten) anzeigen ?
  my $show_diff  = $paref->{show_diff};                      # zusätzliche Anzeige $di{} in allen Typen
  my $lotype     = $paref->{lotype};
  my $height     = $paref->{height};
  my $fsize      = $paref->{fsize};
  my $kw         = $paref->{kw};
  my $colorb1    = $paref->{colorb1};
  my $colorb2    = $paref->{colorb2};
  my $fcolor1    = $paref->{fcolor1};
  my $fcolor2    = $paref->{fcolor2};
  my $offset     = $paref->{offset};
  my $thishour   = $paref->{thishour};
  my $maxVal     = $paref->{maxVal};
  my $maxCon     = $paref->{maxCon};
  my $maxDif     = $paref->{maxDif};
  my $minDif     = $paref->{minDif};
  my $beam1cont  = $paref->{beam1cont};
  my $beam2cont  = $paref->{beam2cont};

  $lotype        = 'single' if ($beam1cont eq $beam2cont);                                                       # User Auswahl Layout überschreiben bei gleichen Beamcontent !

  # Wenn Table class=block alleine steht, zieht es bei manchen Styles die Ausgabe auf 100% Seitenbreite
  # lässt sich durch einbetten in eine zusätzliche Table roomoverview eindämmen
  # Die Tabelle ist recht schmal angelegt, aber nur so lassen sich Umbrüche erzwingen

  my ($val,$z2,$z3,$z4,$he);
  my $ret;

  $ret .= __weatherOnBeam ($paref);

  my $m = $paref->{modulo} % 2;

  if($show_diff eq 'top') {                                                                                      # Zusätzliche Zeile Ertrag - Verbrauch
      $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";
      my $ii;
      for my $i (0..($maxhours * 2) - 1) {                                                                       # gleiche Bedingung wie oben
          next if(!$show_night && $hfcg->{$i}{weather} > 99
                               && !$hfcg->{$i}{beam1}
                               && !$hfcg->{$i}{beam2});
          $ii++;                                                                                                 # wieviele Stunden haben wir bisher angezeigt ?

          last if ($ii > $maxhours);                                                                             # vorzeitiger Abbruch

          $val  = formatVal6 ($hfcg->{$i}{diff}, $kw, $hfcg->{$i}{weather});

          if ($val ne '&nbsp;') {                                                                                # Forum: https://forum.fhem.de/index.php/topic,117864.msg1166215.html#msg1166215
          $val  = $hfcg->{$i}{diff} < 0 ? '<b>'.$val.'<b/>' :
                  $val > 0              ? '+'.$val          :
                  $val;                                                                                          # negative Zahlen in Fettschrift, 0 aber ohne +
          }

          $ret .= "<td class='solarfc' style='vertical-align:middle; text-align:center;'>$val</td>";
      }
      $ret .= "<td class='solarfc'></td></tr>";                                                                  # freier Platz am Ende
  }

  $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";                                                  # Neue Zeile mit freiem Platz am Anfang

  my $ii = 0;

  for my $i (0..($maxhours * 2) - 1) {                                                                           # gleiche Bedingung wie oben
      next if(!$show_night && $hfcg->{$i}{weather} > 99
                           && !$hfcg->{$i}{beam1}
                           && !$hfcg->{$i}{beam2});
      $ii++;
      last if ($ii > $maxhours);

      # maxVal kann gerade bei kleineren maxhours Ausgaben in der Nacht leicht auf 0 fallen
      $height = 200 if (!$height);                                                                               # Fallback, sollte eigentlich nicht vorkommen, außer der User setzt es auf 0
      $maxVal = 1   if (!int $maxVal);
      $maxCon = 1   if (!$maxCon);

      # Der zusätzliche Offset durch $fsize verhindert bei den meisten Skins
      # dass die Grundlinie der Balken nach unten durchbrochen wird

      if ($lotype eq 'single') {
          $he = int(($maxVal-$hfcg->{$i}{beam1}) / $maxVal*$height) + $fsize;
          $z3 = int($height + $fsize - $he);
      }

      if ($lotype eq 'double') {
          # Berechnung der Zonen
          # he - freier der Raum über den Balken. fsize wird nicht verwendet, da bei diesem Typ keine Zahlen über den Balken stehen
          # z2 - der Ertrag ggf mit Icon
          # z3 - der Verbrauch , bei zu kleinem Wert wird der Platz komplett Zone 2 zugeschlagen und nicht angezeigt
          # z2 und z3 nach Bedarf tauschen, wenn der Verbrauch größer als der Ertrag ist

          $maxVal = $maxCon if ($maxCon > $maxVal);                                                              # wer hat den größten Wert ?

          if ($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                                         # Beam1 oben , Beam2 unten
              $z2 = $hfcg->{$i}{beam1}; $z3 = $hfcg->{$i}{beam2};
          }
          else {                                                                                                 # tauschen, Verbrauch ist größer als Ertrag
              $z3 = $hfcg->{$i}{beam1}; $z2 = $hfcg->{$i}{beam2};
          }

          $he = int(($maxVal-$z2)/$maxVal*$height);
          $z2 = int(($z2 - $z3)/$maxVal*$height);

          $z3 = int($height - $he - $z2);                                                                        # was von maxVal noch übrig ist

          if ($z3 < int($fsize/2)) {                                                                             # dünnen Strichbalken vermeiden / ca. halbe Zeichenhöhe
              $z2 += $z3;
              $z3  = 0;
          }
      }

      if ($lotype eq 'diff') {
          # Berechnung der Zonen
          # he - freier der Raum über den Balken , Zahl positiver Wert + fsize
          # z2 - positiver Balken inkl Icon
          # z3 - negativer Balken
          # z4 - Zahl negativer Wert + fsize

          my ($px_pos,$px_neg);
          my $maxValBeam = 0;                                                                                    # ToDo:  maxValBeam noch aus Attribut graphicBeam1MaxVal ableiten

          if ($maxValBeam) {                                                                                     # Feste Aufteilung +/- , jeder 50 % bei maxValBeam = 0
              $px_pos = int($height/2);
              $px_neg = $height - $px_pos;                                                                       # Rundungsfehler vermeiden
          }
          else {                                                                                                 # Dynamische hoch/runter Verschiebung der Null-Linie
              if ($minDif >= 0 ) {                                                                               # keine negativen Balken vorhanden, die Positiven bekommen den gesammten Raum
                  $px_neg = 0;
                  $px_pos = $height;
              }
              else {
                  if ($maxDif > 0) {
                      $px_neg = int($height * abs($minDif) / ($maxDif + abs($minDif)));                          # Wieviel % entfallen auf unten ?
                      $px_pos = $height-$px_neg;                                                                 # der Rest ist oben
                  }
                  else {                                                                                         # keine positiven Balken vorhanden, die Negativen bekommen den gesammten Raum
                      $px_neg = $height;
                      $px_pos = 0;
                  }
              }
          }

          if ($hfcg->{$i}{diff} >= 0) {                                                                          # Zone 2 & 3 mit ihren direkten Werten vorbesetzen
              $z2 = $hfcg->{$i}{diff};
              $z3 = abs($minDif);
          }
          else {
              $z2 = $maxDif;
              $z3 = abs($hfcg->{$i}{diff});                                                                      # Nur Betrag ohne Vorzeichen
          }
                                                                                                                 # Alle vorbesetzen Werte umrechnen auf echte Ausgabe px
          $he = (!$px_pos || !$maxDif) ? 0 : int(($maxDif-$z2)/$maxDif*$px_pos);                                 # Teilung durch 0 vermeiden
          $z2 = ($px_pos - $he) ;

          $z4 = (!$px_neg || !$minDif) ? 0 : int((abs($minDif)-$z3)/abs($minDif)*$px_neg);                       # Teilung durch 0 unbedingt vermeiden
          $z3 = ($px_neg - $z4);
                                                                                                                 # Beiden Zonen die Werte ausgeben könnten muß fsize als zusätzlicher Raum zugeschlagen werden !
          $he += $fsize;
          $z4 += $fsize if ($z3);                                                                                # komplette Grafik ohne negativ Balken, keine Ausgabe von z3 & z4
      }

      # das style des nächsten TD bestimmt ganz wesentlich das gesammte Design
      # das \n erleichtert das lesen des Seitenquelltext beim debugging
      # vertical-align:bottom damit alle Balken und Ausgaben wirklich auf der gleichen Grundlinie sitzen

      $ret .="<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px; vertical-align:bottom; padding-top:0px'>\n";

      if ($lotype eq 'single') {
          $val = formatVal6 ($hfcg->{$i}{beam1}, $kw, $hfcg->{$i}{weather});

          $ret .="<table width='100%' height='100%'>";                                                           # mit width=100% etwas bessere Füllung der Balken
          $ret .="<tr class='$htr{$m}{cl}' style='height:".$he."px'>";
          $ret .="<td class='solarfc' style='vertical-align:bottom; color:#$fcolor1;'>".$val.'</td></tr>';

          if ($hfcg->{$i}{beam1} || $show_night) {                                                               # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
              my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style   .= defined $colorb1 ? " background-color:#$colorb1\"" : '"';                              # Syntaxhilight

              $ret .= "<tr class='odd' style='height:".$z3."px;'>";
              $ret .= "<td align='center' class='solarfc' ".$style.">";

              my $sicon = 1;

              # inject the new icon if defined
              ##################################
              #$ret .= consinject($hash,$i,@consumers) if($s);

              $ret .= "</td></tr>";
          }
      }

      if ($lotype eq 'double') {
          my ($color1, $color2, $style1, $style2, $v);
          my $style = "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";

          $ret .="<table width='100%' height='100%'>\n";                                                         # mit width=100% etwas bessere Füllung der Balken
                                                                                                                 # der Freiraum oben kann beim größten Balken ganz entfallen
          $ret .="<tr class='$htr{$m}{cl}' style='height:".$he."px'><td class='solarfc'></td></tr>" if($he);

          if ($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                                         # wer ist oben, Beam2 oder Beam1 ? Wert und Farbe für Zone 2 & 3 vorbesetzen
              $val     = formatVal6 ($hfcg->{$i}{beam1}, $kw, $hfcg->{$i}{weather});
              $color1  = $colorb1;
              $style1  = $style." background-color:#$color1; color:#$fcolor1;'";

              if ($z3) {                                                                                         # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
                  $v       = formatVal6 ($hfcg->{$i}{beam2}, $kw, $hfcg->{$i}{weather});
                  $color2  = $colorb2;
                  $style2  = $style." background-color:#$color2; color:#$fcolor2;'";
              }
          }
          else {
              $val    = formatVal6 ($hfcg->{$i}{beam2}, $kw, $hfcg->{$i}{weather});
              $color1 = $colorb2;
              $style1 = $style." background-color:#$color1; color:#$fcolor2;'";

              if ($z3) {
                  $v      = formatVal6 ($hfcg->{$i}{beam1}, $kw, $hfcg->{$i}{weather});
                  $color2 = $colorb1;
                  $style2 = $style." background-color:#$color2; color:#$fcolor1;'";
              }
          }

          $ret .= "<tr class='odd' style='height:".$z2."px'>";
          $ret .= "<td align='center' class='solarfc' ".$style1.">$val";

          # inject the new icon if defined
          ##################################
          #$ret .= consinject($hash,$i,@consumers) if($s);

          $ret .= "</td></tr>";

          if ($z3) {                                                                                             # die Zone 3 lassen wir bei zu kleinen Werten auch ganz weg
              $ret .= "<tr class='odd' style='height:".$z3."px'>";
              $ret .= "<td align='center' class='solarfc' ".$style2.">$v</td></tr>";
          }
      }

      if ($lotype eq 'diff') {                                                                                   # Type diff
          my $style = "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
          $ret .= "<table width='100%' border='0'>\n";                                                           # Tipp : das nachfolgende border=0 auf 1 setzen hilft sehr Ausgabefehler zu endecken

          $val = ($hfcg->{$i}{diff} > 0) ? formatVal6 ($hfcg->{$i}{diff}, $kw, $hfcg->{$i}{weather}) : '';
          $val = '&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;' if ($hfcg->{$i}{diff} == 0);                                  # Sonderfall , hier wird die 0 gebraucht !

          if ($val) {
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$he."px'>";
              $ret .= "<td class='solarfc' style='vertical-align:bottom; color:#$fcolor1;'>".$val."</td></tr>";
          }

          if ($hfcg->{$i}{diff} >= 0) {                                                                          # mit Farbe 1 colorb1 füllen
              $style .= " background-color:#$colorb1'";
              $z2     = 1 if ($hfcg->{$i}{diff} == 0);                                                           # Sonderfall , 1px dünnen Strich ausgeben
              $ret   .= "<tr class='odd' style='height:".$z2."px'>";
              $ret   .= "<td align='center' class='solarfc' ".$style.">";
              $ret   .= "</td></tr>";
          }
          else {                                                                                                 # ohne Farbe
              $z2 = 2 if ($hfcg->{$i}{diff} == 0);                                                               # Sonderfall, hier wird die 0 gebraucht !
              if ($z2 && $val) {                                                                                 # z2 weglassen wenn nicht unbedigt nötig bzw. wenn zuvor he mit val keinen Wert hatte
                  $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z2."px'>";
                  $ret .= "<td class='solarfc'></td></tr>";
              }
          }

          if ($hfcg->{$i}{diff} < 0) {                                                                           # Negativ Balken anzeigen ?
              $style .= " background-color:#$colorb2'";                                                          # mit Farbe 2 colorb2 füllen
              $ret   .= "<tr class='odd' style='height:".$z3."px'>";
              $ret   .= "<td align='center' class='solarfc' ".$style."></td></tr>";
          }
          elsif ($z3) {                                                                                          # ohne Farbe
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z3."px'>";
              $ret .= "<td class='solarfc'></td></tr>";
          }

          if($z4) {                                                                                              # kann entfallen wenn auch z3 0 ist
              $val  = ($hfcg->{$i}{diff} < 0) ? formatVal6 ($hfcg->{$i}{diff}, $kw, $hfcg->{$i}{weather}) : '&nbsp;';
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z4."px'>";
              $ret .= "<td class='solarfc' style='vertical-align:top'>".$val."</td></tr>";
          }
      }

      if ($show_diff eq 'bottom') {                                                                                                      # zusätzliche diff Anzeige
          $val  = formatVal6 ($hfcg->{$i}{diff}, $kw, $hfcg->{$i}{weather});
          $val  = ($hfcg->{$i}{diff} < 0) ?  '<b>'.$val.'<b/>' : ($val > 0 ) ? '+'.$val : $val if ($val ne '&nbsp;');                    # negative Zahlen in Fettschrift, 0 aber ohne +
          $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc' style='vertical-align:middle; text-align:center;'>$val</td></tr>";
      }

      $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc' style='vertical-align:bottom; text-align:center;'>";
      $ret .= $hfcg->{$i}{time} == $thishour ?                                                                                           # wenn Hervorhebung nur bei gesetztem Attr 'graphicHistoryHour' ? dann hinzufügen: "&& $offset < 0"
                                   '<a class="changed" style="visibility:visible"><span>'.$hfcg->{$i}{time_str}.'</span></a>' :
                                   $hfcg->{$i}{time_str};

      if($hfcg->{$i}{time} == $thishour) {
          $thishour = 99;                                                                                                                # nur einmal verwenden !
      }

      $ret .="</td></tr></table></td>";
  }

  $paref->{modulo}++;

  $ret .= "<td class='solarfc'></td>";
  $ret .= "</tr>";

return $ret;
}

################################################################
#                   Wetter Icon Zeile
################################################################
sub __weatherOnBeam {
  my $paref      = shift;
  my $name       = $paref->{name};
  my $hfcg       = $paref->{hfcg};
  my $maxhours   = $paref->{maxhours};
  my $weather    = $paref->{weather};
  my $show_night = $paref->{show_night};                     # alle Balken (Spalten) anzeigen ?
  my $colorw     = $paref->{colorw};                         # Wetter Icon Farbe
  my $colorwn    = $paref->{colorwn};                        # Wetter Icon Farbe Nacht
  my $width      = $paref->{width};
  my $lang       = $paref->{lang};

  my $ret = q{};

  return $ret if(!$weather);

  my $m  = $paref->{modulo} % 2;
  my $ii = 0;

  $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";                                              # freier Platz am Anfang

  for my $i (0..($maxhours * 2) - 1) {
      last if (!exists ($hfcg->{$i}{weather}));

      $hfcg->{$i}{weather} = 999 if(!defined $hfcg->{$i}{weather});
      my $wcc              = $hfcg->{$i}{wcc} // '-';                                                        # Bewölkungsgrad ergänzen

      debugLog ($paref, 'graphic', "weather id beam number >$i< (start hour $hfcg->{$i}{time_str}): wid $hfcg->{$i}{weather} / wcc $wcc") if($ii < $maxhours);

      if (!$show_night && $hfcg->{$i}{weather} > 99
                       && !$hfcg->{$i}{beam1}
                       && !$hfcg->{$i}{beam2}) {

          debugLog ($paref, 'graphic', "weather id >$i< don't show night condition ... is skipped") if($ii < $maxhours);
          next;
      };
                                                                                                             # Lässt Nachticons aber noch durch wenn es einen Wert gibt , ToDo : klären ob die Nacht richtig gesetzt wurde
      $ii++;                                                                                                 # wieviele Stunden Icons haben wir bisher beechnet  ?
      last if($ii > $maxhours);
                                                                                                             # ToDo : weather_icon sollte im Fehlerfall Title mit der ID besetzen um in FHEMWEB sofort die ID sehen zu können
      my ($icon_name, $title) = $hfcg->{$i}{weather} > 100                            ?
                                weather_icon ($name, $lang, $hfcg->{$i}{weather}-100) :
                                weather_icon ($name, $lang, $hfcg->{$i}{weather});

      $wcc   += 0 if(isNumeric ($wcc));                                                                      # Javascript Fehler vermeiden: https://forum.fhem.de/index.php/topic,117864.msg1233661.html#msg1233661
      $title .= ': '.$wcc;

      if ($icon_name eq 'unknown') {
          debugLog ($paref, "graphic", "unknown weather id: ".$hfcg->{$i}{weather}.", please inform the maintainer");
      }

      $icon_name .= $hfcg->{$i}{weather} < 100 ? '@'.$colorw  : '@'.$colorwn;
      my $val     = FW_makeImage ($icon_name) // q{};

      if ($val =~ /title="$icon_name"/xs) {                                                                  # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
          $val = '<b>???<b/>';
          debugLog ($paref, "graphic", qq{ERROR - the icon "$weather_ids{$hfcg->{$i}{weather}}{icon}.svg" not found. Please check attribute "iconPath" of your FHEMWEB instance and/or update your FHEM software});
      }

      $ret .= "<td title='$title' class='solarfc' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";
  }

  $ret .= "<td class='solarfc'></td></tr>";                                                                  # freier Platz am Ende der Icon Zeile

return $ret;
}

################################################################
#                  Energieflußgrafik
################################################################
sub _flowGraphic {
  my $paref         = shift;
  my $hash          = $paref->{hash};
  my $name          = $paref->{name};
  my $flowgsize     = $paref->{flowgsize};
  my $flowgani      = $paref->{flowgani};
  my $flowgcons     = $paref->{flowgcons};
  my $flowgconX     = $paref->{flowgconX};
  my $flowgconPower = $paref->{flowgconsPower};
  my $flowgconTime  = $paref->{flowgconsTime};
  my $consDist      = $paref->{flowgconsDist};
  my $css           = $paref->{css};

  my $style      = 'width:98%; height:'.$flowgsize.'px;';
  my $animation  = $flowgani ? '@keyframes dash {  to {  stroke-dashoffset: 0;  } }' : '';             # Animation Ja/Nein
  my $cpv        = ReadingsNum ($name, 'Current_PV',              0);
  my $cgc        = ReadingsNum ($name, 'Current_GridConsumption', 0);
  my $cgfi       = ReadingsNum ($name, 'Current_GridFeedIn',      0);
  my $csc        = ReadingsNum ($name, 'Current_SelfConsumption', 0);
  my $cc         = CurrentVal  ($hash, 'consumption',             0);
  my $cc_dummy   = $cc;
  my $batin      = ReadingsNum ($name, 'Current_PowerBatIn',  undef);
  my $batout     = ReadingsNum ($name, 'Current_PowerBatOut', undef);
  my $soc        = ReadingsNum ($name, 'Current_BatCharge',     100);

  my $bat_color  = $soc < 26 ? 'flowg bat25' :
                   $soc < 76 ? 'flowg bat50' :
                   'flowg bat75';

  my $hasbat     = 1;

  if (!defined($batin) && !defined($batout)) {
      $hasbat = 0;
      $batin  = 0;
      $batout = 0;
      $soc    = 0;
  }
  else {
      #$csc -= $batout;
  }

  my $grid_color    = $cgfi   ? 'flowg grid_color1'               : 'flowg grid_color2';
  $grid_color       = 'flowg grid_color3'  if (!$cgfi && !$cgc && $batout);                    # dritte Farbe
  my $cgc_style     = $cgc    ? 'flowg active_in'                 : 'flowg inactive_in';
  my $batout_style  = $batout ? 'flowg active_out active_bat_out' : 'flowg inactive_in';

  my $cgc_direction = 'M490,305 L670,510';                                                     # Batterientladung ins Netz

  if($batout) {
      my $cgfo = $cgfi - $cpv;

      if($cgfo > 1) {
        $cgc_style     = 'flowg active_out';
        $cgc_direction = 'M670,510 L490,305';
        $cgfi         -= $cgfo;
        $cgc           = $cgfo;
      }
  }

  my $batout_direction = 'M902,305 L730,510';                                                  # Batterientladung aus Netz

  if($batin) {
      my $gbi = $batin - $cpv;

      if($gbi > 1) {
        $batin            -= $gbi;
        $batout_style      = 'flowg active_in';
        $batout_direction  = 'M730,510 L902,305';
        $batout            = $gbi;
      }
  }

  my $sun_color    = $cpv          ? 'flowg sun_active'              : 'flowg sun_inactive';
  my $batin_style  = $batin        ? 'flowg active_in active_bat_in' : 'flowg inactive_out';
  my $csc_style    = $csc && $cpv  ? 'flowg active_out'              : 'flowg inactive_out';
  my $cgfi_style   = $cgfi         ? 'flowg active_out'              : 'flowg inactive_out';

  my $vbox_default = !$flowgcons   ? '5 -25 800 480' :
                     $flowgconTime ? '5 -25 800 700' :
                     '5 -25 800 680';

  my $ret = << "END0";
      <style>
      $css
      $animation
      </style>

      <svg xmlns="http://www.w3.org/2000/svg" viewBox="$vbox_default" style="$style" id="SVGPLOT">

      <g transform="translate(400,50)">
        <g>
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(45)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(90)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(135)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(180)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(225)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(270)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(315)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <circle cx="0" cy="0" class="$sun_color" r="16" stroke-width="2"/>
      </g>

      <g id="home" fill="grey" transform="translate(352,310),scale(4)">
          <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
      </g>

      <g id="grid" class="$grid_color" transform="translate(215,150),scale(3.0)">
          <path d="M15.3,2H8.7L2,6.46V10H4V8H8v2.79l-4,9V22H6V20.59l6-3.27,6,3.27V22h2V19.79l-4-9V8h4v2h2V6.46ZM14,4V6H10V4ZM6.3,6,8,4.87V6Zm8,6L15,13.42,12,15,9,13.42,9.65,12ZM7.11,17.71,8.2,15.25l1.71.93Zm8.68-2.46,1.09,2.46-2.8-1.53ZM14,10H10V8h4Zm2-5.13L17.7,6H16Z"/>
      </g>
END0

  ## get consumer list and display in Graphics
  ##############################################
  my $pos_left       = 0;
  my $consumercount  = 0;
  my $consumer_start = 0;
  my $currentPower   = 0;
  my @consumers;

  if ($flowgcons) {
      my $type       = $paref->{type};

      for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {                            # definierte Verbraucher ermitteln
          next if(isConsumerNoshow ($hash, $c) =~ /^[13]$/xs);                                      # ausgeblendete Consumer nicht berücksichtigen
          push @consumers, $c;
      }

      $consumercount = scalar @consumers;

      if ($consumercount % 2) {
          $consumer_start = 350 - ($consDist  * (($consumercount -1) / 2));
      }
      else {
          $consumer_start = 350 - (($consDist / 2) * ($consumercount-1));
      }

      $pos_left = $consumer_start + 15;

      for my $c (@consumers) {
          my $calias     = ConsumerVal         ($hash, $c, "alias", "");                           # Name des Consumerdevices
          $currentPower  = ReadingsNum         ($name, "consumer${c}_currentPower", 0);
          my $cicon      = __substConsumerIcon ($hash, $c, $currentPower);                         # Icon des Consumerdevices
          $cc_dummy     -= $currentPower;

          $ret .= '<g id="consumer_'.$c.'" fill="grey" transform="translate('.$pos_left.',485),scale(0.1)">';
          $ret .= "<title>$calias</title>".FW_makeImage($cicon, '');
          $ret .= '</g> ';

          $pos_left += $consDist;
      }
  }

  if ($hasbat) {
      $ret .= << "END1";
      <g class="$bat_color" transform="translate(610,135),scale(.30) rotate (90)">
      <path d="m 134.65625,89.15625 c -6.01649,0 -11,4.983509 -11,11 l 0,180 c 0,6.01649 4.98351,11 11,11 l 95.5,0 c 6.01631,0 11,-4.9825 11,-11 l 0,-180 c 0,-6.016491 -4.98351,-11 -11,-11 l -95.5,0 z m 0,10 95.5,0 c 0.60951,0 1,0.390491 1,1 l 0,180 c 0,0.6085 -0.39231,1 -1,1 l -95.5,0 c -0.60951,0 -1,-0.39049 -1,-1 l 0,-180 c 0,-0.609509 0.39049,-1 1,-1 z"/>
      <path d="m 169.625,69.65625 c -6.01649,0 -11,4.983509 -11,11 l 0,14 10,0 0,-14 c 0,-0.609509 0.39049,-1 1,-1 l 25.5,0 c 0.60951,0 1,0.390491 1,1 l 0,14 10,0 0,-14 c 0,-6.016491 -4.98351,-11 -11,-11 l -25.5,0 z"/>
END1

      $ret .= '<path d="m 221.141,266.334 c 0,3.313 -2.688,6 -6,6 h -65.5 c -3.313,0 -6,-2.688 -6,-6 v -6 c 0,-3.314 2.687,-6 6,-6 l 65.5,-20 c 3.313,0 6,2.686 6,6 v 26 z"/>'     if ($soc > 12);
      $ret .= '<path d="m 221.141,213.667 c 0,3.313 -2.688,6 -6,6 l -65.5,20 c -3.313,0 -6,-2.687 -6,-6 v -20 c 0,-3.313 2.687,-6 6,-6 l 65.5,-20 c 3.313,0 6,2.687 6,6 v 20 z"/>' if ($soc > 38);
      $ret .= '<path d="m 221.141,166.667 c 0,3.313 -2.688,6 -6,6 l -65.5,20 c -3.313,0 -6,-2.687 -6,-6 v -20 c 0,-3.313 2.687,-6 6,-6 l 65.5,-20 c 3.313,0 6,2.687 6,6 v 20 z"/>' if ($soc > 63);
      $ret .= '<path d="m 221.141,120 c 0,3.313 -2.688,6 -6,6 l -65.5,20 c -3.313,0 -6,-2.687 -6,-6 v -26 c 0,-3.313 2.687,-6 6,-6 h 65.5 c 3.313,0 6,2.687 6,6 v 6 z"/>'          if ($soc > 88);
      $ret .= '</g>';
  }

  if ($flowgconX) {                                                                                # Dummy Consumer
      my $dumcol = $cc_dummy <= 0 ? '@grey' : q{};                                                 # Einfärbung Consumer Dummy
      $ret      .= '<g id="consumer_X" fill="grey" transform="translate(520,325),scale(0.09)">';
      $ret      .= "<title>consumer_X</title>".FW_makeImage('light_light_dim_100'.$dumcol, '');
      $ret      .= '</g> ';
   }

    $ret .= << "END2";
    <g transform="translate(50,50),scale(0.5)" stroke-width="27" fill="none">
    <path id="pv-home"   class="$csc_style"  d="M700,100 L700,510" />
    <path id="pv-grid"   class="$cgfi_style" d="M670,100 L490,270" />
    <path id="grid-home" class="$cgc_style"  d="$cgc_direction" />
END2

  if ($hasbat) {
      $ret .= << "END3";
      <path id="bat-home" class="$batout_style" d="$batout_direction" />
      <path id="pv-bat"   class="$batin_style"  d="M730,100 L910,270" />
END3
  }

   if ($flowgconX) {                                                                              # Dummy Consumer
      my $consumer_style = 'flowg inactive_out';
      $consumer_style    = 'flowg active_in' if($cc_dummy > 1);

      my $chain_color = "";                                                                       # Farbe der Laufkette Consumer-Dummy
      if($cc_dummy > 0.5) {
          $chain_color  = 'style="stroke: #'.substr(Color::pahColor(0,500,1000,$cc_dummy,[0,255,0, 127,255,0, 255,255,0, 255,127,0, 255,0,0]),0,6).';"';
          #$chain_color  = 'style="stroke: #DF0101;"';
      }

      $ret .= qq{<path id="home-consumer_X" class="$consumer_style" $chain_color d="M790,620 L930,620" />};
   }

  ## Consumer Laufketten
  ########################
  if ($flowgcons) {
      $pos_left          = $consumer_start * 2;
      my $pos_left_start = 0;
      my $distance       = 25;

      if ($consumercount % 2) {
          $pos_left_start = 700 - ($distance  * (($consumercount -1) / 2));
      }
      else {
          $pos_left_start = 700 - ((($distance ) / 2) * ($consumercount-1));
      }

      for my $c (@consumers) {
          my $power     = ConsumerVal ($hash, $c, "power",   0);
          my $rpcurr    = ConsumerVal ($hash, $c, "rpcurr", "");                                   # Reading für akt. Verbrauch angegeben ?
          $currentPower = ReadingsNum ($name, "consumer${c}_currentPower", 0);

          if (!$rpcurr && isConsumerPhysOn($hash, $c)) {                                           # Workaround wenn Verbraucher ohne Leistungsmessung
              $currentPower = $power;
          }

          my $p              = $currentPower;
          $p                 = (($currentPower / $power) * 100) if ($power > 0);

          my $consumer_style = 'flowg inactive_out';
          $consumer_style    = 'flowg active_out' if($p > $defpopercent);
          my $chain_color    = "";                                                                 # Farbe der Laufkette des Consumers

          if($p > 0.5) {
              $chain_color  = 'style="stroke: #'.substr(Color::pahColor(0,50,100,$p,[0,255,0, 127,255,0, 255,255,0, 255,127,0, 255,0,0]),0,6).';"';
              #$chain_color  = 'style="stroke: #DF0101;"';
          }

          $ret            .= qq{<path id="home-consumer_$c" class="$consumer_style" $chain_color d="M$pos_left_start,700 L$pos_left,850" />};   # Design Consumer Laufkette
          $pos_left       += ($consDist * 2);
          $pos_left_start += $distance;
      }
  }

  ## Angaben Dummy-Verbraucher
  #############################
  $cc_dummy = sprintf("%.0f",$cc_dummy);

  ## Textangaben an Grafikelementen
  ###################################
  $ret .= qq{<text class="flowg text" id="pv-txt"        x="800"  y="15"  style="text-anchor: start;">$cpv</text>}        if ($cpv);
  $ret .= qq{<text class="flowg text" id="bat-txt"       x="1110" y="300" style="text-anchor: start;">$soc %</text>}      if ($hasbat);                        # Lage Ladungs Text
  $ret .= qq{<text class="flowg text" id="pv_home-txt"   x="730"  y="300" style="text-anchor: start;">$csc</text>}        if ($csc && $cpv);
  $ret .= qq{<text class="flowg text" id="pv-grid-txt"   x="525"  y="200" style="text-anchor: end;">$cgfi</text>}         if ($cgfi);
  $ret .= qq{<text class="flowg text" id="grid-home-txt" x="515"  y="420" style="text-anchor: end;">$cgc</text>}          if ($cgc);
  $ret .= qq{<text class="flowg text" id="batout-txt"    x="880"  y="420" style="text-anchor: start;">$batout</text>}     if ($batout && $hasbat);
  $ret .= qq{<text class="flowg text" id="batin-txt"     x="880"  y="200" style="text-anchor: start;">$batin</text>}      if ($batin && $hasbat);
  $ret .= qq{<text class="flowg text" id="home-txt"      x="600"  y="640" style="text-anchor: end;">$cc</text>};                                               # Current_Consumption Anlage
  $ret .= qq{<text class="flowg text" id="dummy-txt"     x="1085" y="640" style="text-anchor: start;">$cc_dummy</text>}   if ($flowgconX && $flowgconPower);   # Current_Consumption Dummy

  ## Consumer Anzeige
  #####################
  if ($flowgcons) {
      $pos_left = ($consumer_start * 2) - 50;                                                         # -XX -> Start Lage Consumer Beschriftung

      for my $c (@consumers) {
          $currentPower    = sprintf "%.1f", ReadingsNum($name, "consumer${c}_currentPower", 0);
          $currentPower    =~ s/\.0$// if (int($currentPower) > 0);                                   # .0 am Ende interessiert nicht
          my $consumerTime = ConsumerVal ($hash, $c, "remainTime", "");                               # Restlaufzeit
          my $rpcurr       = ConsumerVal ($hash, $c, "rpcurr",     "");                               # Readingname f. current Power

          if (!$rpcurr) {                                                                             # Workaround wenn Verbraucher ohne Leistungsmessung
              $currentPower = isConsumerPhysOn($hash, $c) ? 'on' : 'off';
          }

          #$ret .= qq{<text class="flowg text" id="consumer-txt_$c"      x="$pos_left" y="1110" style="text-anchor: start;">$currentPower</text>} if ($flowgconPower);    # Lage Consumer Consumption
          #$ret .= qq{<text class="flowg text" id="consumer-txt_time_$c" x="$pos_left" y="1170" style="text-anchor: start;">$consumerTime</text>} if ($flowgconTime);     # Lage Consumer Restlaufzeit

          # Verbrauchszahl abhängig von der Größe entsprechend auf der x-Achse verschieben
          ##################################################################################
          if (length($currentPower) >= 5) {
               $pos_left -= 40;
          }
          elsif (length($currentPower) >= 4) {
              $pos_left -= 25;
          }
          elsif (length($currentPower) >= 3 and $currentPower ne "0.0") {
              $pos_left -= 5;
          }
          elsif (length($currentPower) >= 2 and $currentPower ne "0.0") {
              $pos_left += 7;
          }
          elsif (length($currentPower) == 1) {
              $pos_left += 25;
          }

          $ret .= qq{<text class="flowg text" id="consumer-txt_$c"      x="$pos_left" y="1110">$currentPower</text>} if ($flowgconPower);    # Lage Consumer Consumption
          $ret .= qq{<text class="flowg text" id="consumer-txt_time_$c" x="$pos_left" y="1170">$consumerTime</text>} if ($flowgconTime);     # Lage Consumer Restlaufzeit

          # Verbrauchszahl abhängig von der Größe entsprechend auf der x-Achse wieder zurück an den Ursprungspunkt
          #########################################################################################################
          if (length($currentPower) >= 5) {
              $pos_left += 40;
          }
          elsif (length($currentPower) >= 4) {
              $pos_left += 25;
          }
          elsif (length($currentPower) >= 3 and $currentPower ne "0.0") {
              $pos_left += 5;
          }
          elsif (length($currentPower) >= 2 and $currentPower ne "0.0") {
              $pos_left -= 7;
          }
          elsif (length($currentPower) == 1) {
              $pos_left -= 25;
          }

          $pos_left  += ($consDist * 2);
      }
  }

  $ret .= qq{</g></svg>};

return $ret;
}

################################################################
#       prüfe ob Verbrauchericon + Farbe angegeben ist
#       und setze ggf. Ersatzwerte
#       $c     - Consumer Nummer
################################################################
sub __substConsumerIcon {
  my $hash  = shift;
  my $c     = shift;
  my $pcurr = shift;

  my $name  = $hash->{NAME};
  my $cicon = ConsumerVal ($hash, $c, "icon", "");                           # Icon des Consumerdevices angegeben ?

  if (!$cicon) {
      $cicon = 'light_light_dim_100';
  }

  my $color;
  ($cicon,$color) = split '@', $cicon;

  if (!$color) {
      $color = isConsumerLogOn ($hash, $c, $pcurr) ? 'darkorange' : '';
  }

  $cicon .= '@'.$color if($color);

return $cicon;
}

################################################################
#                 Inject consumer icon
################################################################
sub consinject {
  my ($hash,$i,@consumers) = @_;
  my $name                 = $hash->{NAME};
  my $ret                  = "";

  my $debug = getDebug ($hash);                                                        # Debug Module

  for (@consumers) {
      if ($_) {
          my ($cons,$im,$start,$end) = split (':', $_);

          if($debug =~ /graphic/x) {
              Log3 ($name, 1, qq{$name DEBUG> Consumer to show -> $cons, relative to current time -> start: $start, end: $end}) if($i<1);
          }

          if ($im && ($i >= $start) && ($i <= $end)) {
              $ret .= FW_makeImage($im);
         }
      }
  }

return $ret;
}

###############################################################################
#                            Balkenbreite normieren
#
# Die Balkenbreite wird bestimmt durch den Wert.
# Damit alle Balken die gleiche Breite bekommen, müssen die Werte auf
# 6 Ausgabezeichen angeglichen werden.
# "align=center" gleicht gleicht es aus, alternativ könnte man sie auch
# komplett rechtsbündig ausgeben.
# Es ergibt bei fast allen Styles gute Ergebnisse, Ausnahme IOS12 & 6, da diese
# beiden Styles einen recht großen Font benutzen.
# Wird Wetter benutzt, wird die Balkenbreite durch das Icon bestimmt
#
###############################################################################
sub formatVal6 {
  my $v  = shift;
  my $kw = shift;
  my $w  = shift;

  my $n = '&nbsp;';                                         # positive Zahl

  if ($v < 0) {
      $n = '-';                                             # negatives Vorzeichen merken
      $v = abs($v);
  }

  if ($kw eq 'kWh') {                                       # bei Anzeige in kWh muss weniger aufgefüllt werden
      $v  = sprintf "%.1f",($v / 1000);
      $v  += 0;                                             # keine 0.0 oder 6.0 etc

      return ($n eq '-') ? ($v * -1) : $v if(defined $w);

      my $t = $v - int($v);                                 # Nachkommstelle ?

      if (!$t) {                                            # glatte Zahl ohne Nachkommastelle
          if(!$v) {
              return '&nbsp;';                              # 0 nicht anzeigen, passt eigentlich immer bis auf einen Fall im Typ diff
          }
          elsif ($v < 10) {
              return '&nbsp;&nbsp;'.$n.$v.'&nbsp;&nbsp;';
          }
          else {
              return '&nbsp;&nbsp;'.$n.$v.'&nbsp;';
          }
      }
      else {                                                # mit Nachkommastelle -> zwei Zeichen mehr .X
          if ($v < 10) {
              return '&nbsp;'.$n.$v.'&nbsp;';
          }
          else {
              return $n.$v.'&nbsp;';
          }
      }
  }

  return ($n eq '-') ? ($v * -1) : $v if(defined $w);

  # Werte bleiben in Watt
  if    (!$v)         { return '&nbsp;'; }                            ## no critic "Cascading" # keine Anzeige bei Null
  elsif ($v <    10)  { return '&nbsp;&nbsp;'.$n.$v.'&nbsp;&nbsp;'; } # z.B. 0
  elsif ($v <   100)  { return '&nbsp;'.$n.$v.'&nbsp;&nbsp;'; }
  elsif ($v <  1000)  { return '&nbsp;'.$n.$v.'&nbsp;'; }
  elsif ($v < 10000)  { return  $n.$v.'&nbsp;'; }
  else                { return  $n.$v; }                              # mehr als 10.000 W :)
}

###############################################################################
#         Zuordungstabelle "WeatherId" angepasst auf FHEM Icons
###############################################################################
sub weather_icon {
  my $name = shift;
  my $lang = shift;
  my $id   = shift;

  $id      = int $id;
  my $txt  = $lang eq "DE" ? "txtd" : "txte";

  if(defined $weather_ids{$id}) {
      return $weather_ids{$id}{icon}, encode("utf8", $weather_ids{$id}{$txt});
  }

return ('unknown','');
}

################################################################
#      benötigte Attribute im DWD Device checken
################################################################
sub checkdwdattr {
  my $name   = shift;
  my $dwddev = shift;
  my $amref  = shift;

  my @fcprop = map { trim($_) } split ",", AttrVal($dwddev, "forecastProperties", "pattern");
  my $fcr    = AttrVal($dwddev, "forecastResolution", 3);
  my $err;

  my @aneeded;
  for my $am (@$amref) {
      next if($am ~~ @fcprop);
      push @aneeded, $am;
  }

  if (@aneeded) {
      $err = qq{ERROR - device "$dwddev" -> attribute "forecastProperties" must contain: }.join ",",@aneeded;
  }

  if($fcr != 1) {
      $err .= ", " if($err);
      $err .= qq{ERROR - device "$dwddev" -> attribute "forecastResolution" must be set to "1"};
  }

  Log3 ($name, 1, "$name - $err") if($err);

return $err;
}

################################################################
#  Korrekturen und Qualität berechnen / speichern
#  sowie AI Quellen Daten hinzufügen
################################################################
sub calcValueImproves {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  my $t     = $paref->{t};                                                            # aktuelle Unix-Zeit

  my $idts = ReadingsTimestamp ($name, 'currentInverterDev', '');                     # Definitionstimestamp des Inverterdevice
  return if(!$idts);

  my ($acu, $aln) = isAutoCorrUsed ($name);

  if ($acu) {
      $idts = timestringToTimestamp ($idts);

      readingsSingleUpdate ($hash, '.pvCorrectionFactor_Auto_Soll', ($aln ? $acu : $acu.' noLearning'), 0) if($acu =~ /on/xs);

      if ($t - $idts < 7200) {
          my $rmh = sprintf "%.1f", ((7200 - ($t - $idts)) / 3600);
          readingsSingleUpdate ($hash, 'pvCorrectionFactor_Auto', "standby (remains in standby for $rmh hours)", 0);

          Log3 ($name, 4, "$name - Correction usage is in standby. It starts in $rmh hours.");

          return;
      }
      else {
          my $acuset = ReadingsVal ($name, '.pvCorrectionFactor_Auto_Soll', 'on_simple');
          readingsSingleUpdate     ($hash, 'pvCorrectionFactor_Auto', $acuset, 0);
      }
  }
  else {
      readingsSingleUpdate ($hash, '.pvCorrectionFactor_Auto_Soll', 'off', 0);
  }

  Log3 ($name, 4, "$name - INFO - The correction factors are now calculated and stored proactively independent of the autocorrection usage");

  $paref->{acu} = $acu;
  $paref->{aln} = $aln;

  for my $h (1..23) {
      next if(!$chour || $h > $chour);
      $paref->{h} = $h;

      _calcCaQcomplex   ($paref);                                            # Korrekturberechnung mit Bewölkung duchführen/speichern
      _calcCaQsimple    ($paref);                                            # einfache Korrekturberechnung duchführen/speichern
      _addHourAiRawdata ($paref);                                            # AI Raw Data hinzufügen

      delete $paref->{h};
  }

  delete $paref->{aln};
  delete $paref->{acu};

return;
}

################################################################
# PV Ist/Forecast ermitteln und Korrekturfaktoren, Qualität
# in Abhängigkeit Bewölkung errechnen und speichern (komplex)
################################################################
sub _calcCaQcomplex {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $debug = $paref->{debug};
  my $acu   = $paref->{acu};
  my $aln   = $paref->{aln};                                                                          # Autolearning
  my $h     = $paref->{h};

  my $maxvar = AttrVal     ($name, 'affectMaxDayVariance', $defmaxvar);                               # max. Korrekturvarianz
  my $sr     = ReadingsVal ($name, '.pvCorrectionFactor_'.sprintf("%02d",$h).'_cloudcover', '');

  if ($sr eq 'done') {
      # Log3 ($name, 1, "$name DEBUG> Complex Corrf -> factor Hour: ".sprintf("%02d",$h)." already calculated");
      return;
  }

  if (!$aln) {
      storeReading ('.pvCorrectionFactor_'.sprintf("%02d",$h).'_cloudcover', 'done');
      debugLog     ($paref, 'pvCorrection', "Autolearning is switched off for hour: $h -> skip the recalculation of the complex correction factor");
      return;
  }

  debugLog ($paref, 'pvCorrection', "start calculation complex correction factor for hour: $h");

  my $pvre = CircularVal ($hash, sprintf("%02d",$h), 'pvrl',    0);
  my $pvfc = CircularVal ($hash, sprintf("%02d",$h), 'pvapifc', 0);

  if (!$pvre || !$pvfc) {
      storeReading ('.pvCorrectionFactor_'.sprintf("%02d",$h).'_cloudcover', 'done');
      return;
  }

  $paref->{hour}                  = $h;
  my ($pvhis,$fchis,$dnum,$range) = __Pv_Fc_Complex_Dnum_Hist ($paref);                               # historische PV / Forecast Vergleichswerte ermitteln

  my ($oldfac, $oldq) = CircularAutokorrVal ($hash, sprintf("%02d",$h), $range, 0);                   # bisher definierter Korrekturfaktor/KF-Qualität der Stunde des Tages der entsprechenden Bewölkungsrange
  $oldfac             = 1 if(1 * $oldfac == 0);

  (my $factor, $dnum) = __calcNewFactor ({ name   => $name,
                                           oldfac => $oldfac,
                                           dnum   => $dnum,
                                           pvre   => $pvre,
                                           pvfc   => $pvfc,
                                           pvhis  => $pvhis,
                                           fchis  => $fchis
                                         }
                                        );

  if (abs($factor - $oldfac) > $maxvar) {
      $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvar : $oldfac - $maxvar);
      Log3 ($name, 3, "$name - new complex correction factor calculated (limited by affectMaxDayVariance): $factor (old: $oldfac) for hour: $h");
  }
  else {
      Log3 ($name, 3, "$name - new complex correction factor for hour $h calculated: $factor (old: $oldfac)");
  }

  $pvre = sprintf "%.0f", $pvre;
  $pvfc = sprintf "%.0f", $pvfc;

  debugLog ($paref, 'pvCorrection', "Complex Corrf -> determined values - hour: $h, cloudiness range: $range, average forecast: $pvfc, average real: $pvre, old corrf: $oldfac, new corrf: $factor, days: $dnum");

  if (defined $range) {
      my $type = $paref->{type};

      my $qual = __calcFcQuality ($pvfc, $pvre);                                                               # Qualität der Vorhersage für die vergangene Stunde

      debugLog ($paref, 'pvCorrection|saveData2Cache', "Complex Corrf -> write range correction values into Circular: hour: $h, cloudiness range: $range, factor: $factor, quality: $qual");

      $data{$type}{$name}{circular}{sprintf("%02d",$h)}{pvcorrf}{$range} = $factor;                            # Korrekturfaktor für Bewölkung der jeweiligen Stunde als Datenquelle eintragen
      $data{$type}{$name}{circular}{sprintf("%02d",$h)}{quality}{$range} = $qual;

      storeReading ('.pvCorrectionFactor_'.sprintf("%02d",$h).'_cloudcover', 'done');
  }
  else {
      $range = "";
  }

  if ($acu =~ /on_complex/xs) {
      storeReading ('pvCorrectionFactor_'.sprintf("%02d",$h), $factor." (automatic - old factor: $oldfac, cloudiness range: $range, days in range: $dnum)");
      storeReading ('pvCorrectionFactor_'.sprintf("%02d",$h).'_autocalc', 'done');
  }

return;
}

################################################################
# PV Ist/Forecast ermitteln und Korrekturfaktoren, Qualität
# ohne Nebenfaktoren errechnen und speichern (simple)
################################################################
sub _calcCaQsimple {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $date  = $paref->{date};
  my $acu   = $paref->{acu};
  my $aln   = $paref->{aln};                                                                          # Autolearning
  my $h     = $paref->{h};

  my $maxvar = AttrVal($name, 'affectMaxDayVariance', $defmaxvar);                                    # max. Korrekturvarianz
  my $sr     = ReadingsVal ($name, '.pvCorrectionFactor_'.sprintf("%02d",$h).'_apipercentil', '');

  if($sr eq "done") {
      # debugLog ($paref, 'pvCorrection', "Simple Corrf factor Hour: ".sprintf("%02d",$h)." already calculated");
      return;
  }

  if (!$aln) {
      storeReading ('.pvCorrectionFactor_'.sprintf("%02d",$h).'_apipercentil', 'done');
      debugLog     ($paref, 'pvCorrection', "Autolearning is switched off for hour: $h -> skip the recalculation of the simple correction factor");
      return;
  }

  debugLog ($paref, 'pvCorrection', "start calculation simple correction factor for hour: $h");

  my $pvre = CircularVal ($hash, sprintf("%02d",$h), 'pvrl',    0);
  my $pvfc = CircularVal ($hash, sprintf("%02d",$h), 'pvapifc', 0);

  if (!$pvre || !$pvfc) {
      storeReading ('.pvCorrectionFactor_'.sprintf("%02d",$h).'_apipercentil', 'done');
      return;
  }

  $paref->{hour}           = $h;
  my ($pvhis,$fchis,$dnum) = __Pv_Fc_Simple_Dnum_Hist ($paref);                                       # historischen Percentilfaktor / Qualität ermitteln

  my ($oldfac, $oldq) = CircularAutokorrVal ($hash, sprintf("%02d",$h), 'percentile', 0);
  $oldfac             = 1 if(1 * $oldfac == 0);

  (my $factor, $dnum) = __calcNewFactor ({ name   => $name,
                                           oldfac => $oldfac,
                                           dnum   => $dnum,
                                           pvre   => $pvre,
                                           pvfc   => $pvfc,
                                           pvhis  => $pvhis,
                                           fchis  => $fchis
                                         }
                                        );

  if (abs($factor - $oldfac) > $maxvar) {
      $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvar : $oldfac - $maxvar);
      Log3 ($name, 3, "$name - new simple correction factor calculated (limited by affectMaxDayVariance): $factor (old: $oldfac) for hour: $h");
  }
  else {
      Log3 ($name, 3, "$name - new simple correction factor for hour $h calculated: $factor (old: $oldfac)");
  }

  $pvre    = sprintf "%.0f", $pvre;
  $pvfc    = sprintf "%.0f", $pvfc;

  my $qual = __calcFcQuality ($pvfc, $pvre);                                                         # Qualität der Vorhersage für die vergangene Stunde

  debugLog ($paref, 'pvCorrection',                "Simple Corrf -> determined values - average forecast: $pvfc, average real: $pvre, old corrf: $oldfac, new corrf: $factor, days: $dnum");
  debugLog ($paref, 'pvCorrection|saveData2Cache', "Simple Corrf -> write percentile correction values into Circular - hour: $h, factor: $factor, quality: $qual");

  my $type = $paref->{type};

  $data{$type}{$name}{circular}{sprintf("%02d",$h)}{pvcorrf}{percentile} = $factor;                  # Korrekturfaktor der jeweiligen Stunde als Datenquelle eintragen
  $data{$type}{$name}{circular}{sprintf("%02d",$h)}{quality}{percentile} = $qual;

  storeReading ('.pvCorrectionFactor_'.sprintf("%02d",$h).'_apipercentil', 'done');

  if ($acu =~ /on_simple/xs) {
      storeReading ('pvCorrectionFactor_'.sprintf("%02d",$h), $factor." (automatic - old factor: $oldfac, average days: $dnum)");
      storeReading ('pvCorrectionFactor_'.sprintf("%02d",$h).'_autocalc', 'done');
  }

return;
}

################################################################
#       AI Daten für die abgeschlossene Stunde hinzufügen
################################################################
sub _addHourAiRawdata {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $aln   = $paref->{aln};                                                                          # Autolearning
  my $h     = $paref->{h};

  my $rho = sprintf "%02d", $h;
  my $sr  = ReadingsVal ($name, ".signaldone_".$rho, "");

  return if($sr eq "done");

  if (!$aln) {
      storeReading ('.signaldone_'.sprintf("%02d",$h), 'done');
      debugLog     ($paref, 'pvCorrection', "Autolearning is switched off for hour: $h -> skip add AI raw data");
      return;
  }

  debugLog ($paref, 'aiProcess', "start add AI raw data for hour: $h");

  $paref->{ood} = 1;                                              # Only One Day
  $paref->{rho} = $rho;

  aiAddRawData ($paref);                                          # Raw Daten für AI hinzufügen und sichern

  delete $paref->{ood};
  delete $paref->{rho};

  storeReading ('.signaldone_'.sprintf("%02d",$h), 'done');

return;
}

################################################################
#   ermittle PV Vorhersage / PV Ertrag aus PV History
#   unter Berücksichtigung der maximal zu nutzenden Tage
#   und der relevanten Bewölkung
################################################################
sub __Pv_Fc_Complex_Dnum_Hist {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hour  = $paref->{hour};                                                          # Stunde des Tages für die der Durchschnitt bestimmt werden soll
  my $day   = $paref->{day};                                                           # aktueller Tag

  $hour     = sprintf("%02d",$hour);
  my $pvhh  = $data{$type}{$name}{pvhist};

  my ($dnum , $pvrl, $pvfc) = (0,0,0);
  my ($usenhd, $calcd)      = __useNumHistDays ($name);                                # ist Attr affectNumHistDays gesetzt ? und welcher Wert

  my @k     = sort {$a<=>$b} keys %{$pvhh};
  my $ile   = $#k;                                                                     # Index letztes Arrayelement
  my ($idx) = grep {$k[$_] eq "$day"} (0..@k-1);                                       # Index des aktuellen Tages

  return if(!defined $idx);

  my $ei = $idx-1;
  $ei    = $ei < 0 ? $ile : $ei;
  my @efa;

  for my $e (0..$calcd) {
      last if($e == $calcd || $k[$ei] == $day);
      unshift @efa, $k[$ei];
      $ei--;
  }

  my $chwcc = HistoryVal ($hash, $day, $hour, "wcc", undef);                           # Wolkenbedeckung Heute & abgefragte Stunde

  if(!defined $chwcc) {
      debugLog ($paref, 'pvCorrection', "Complex Corrf -> Day $day has no cloudiness value set for hour $hour, no past averages can be calculated");
      return;
  }

  my $range = cloud2bin ($chwcc);

  if (scalar(@efa)) {
      debugLog ($paref, 'pvCorrection', "Complex Corrf -> Raw Days ($calcd) for average check: ".join " ",@efa);
  }
  else {
      debugLog ($paref, 'pvCorrection', "Complex Corrf -> Day $day has index $idx. Use only current day for average calc");
      return (undef,undef,undef,$range);
  }

  debugLog ($paref, 'pvCorrection', "Complex Corrf -> cloudiness range of day/hour $day/$hour is: $range");

  for my $dayfa (@efa) {
      my $histwcc = HistoryVal ($hash, $dayfa, $hour, "wcc", undef);                   # historische Wolkenbedeckung

      if(!defined $histwcc) {
          debugLog ($paref, 'pvCorrection', "Complex Corrf -> Day $dayfa has no cloudiness value set for hour $hour, this history dataset is ignored.");
          next;
      }

      $histwcc = cloud2bin ($histwcc);                                                 # V 0.50.1

      if($range == $histwcc) {
          $pvrl  += HistoryVal ($hash, $dayfa, $hour, 'pvrl', 0);
          $pvfc  += HistoryVal ($hash, $dayfa, $hour, 'pvfc', 0);
          $dnum++;

          debugLog ($paref, 'pvCorrection', "Complex Corrf -> historical Day/hour $dayfa/$hour included - cloudiness range: $range");

          last if( $dnum == $calcd);
      }
      else {
          debugLog ($paref, 'pvCorrection', "Complex Corrf -> cloudiness range different: $range/$histwcc (current/historical) -> ignore stored Day:$dayfa, hour:$hour");
      }
  }

  if(!$dnum) {
      debugLog ($paref, 'pvCorrection', "Complex Corrf -> all cloudiness ranges were different/not set -> no historical averages calculated");
      return (undef,undef,undef,$range);
  }

  my $pvhis = sprintf "%.2f", $pvrl;
  my $fchis = sprintf "%.2f", $pvfc;

  debugLog ($paref, 'pvCorrection', "Complex Corrf -> Summary - cloudiness range: $range, days: $dnum, pvHist:$pvhis, fcHist:$fchis");

return ($pvhis,$fchis,$dnum,$range);
}

################################################################
#   ermittle PV Vorhersage / PV Ertrag aus PV History
#   unter Berücksichtigung der maximal zu nutzenden Tage
#   OHNE Bewölkung
################################################################
sub __Pv_Fc_Simple_Dnum_Hist {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hour  = $paref->{hour};                                                             # Stunde des Tages für die der Durchschnitt bestimmt werden soll
  my $day   = $paref->{day};                                                              # aktueller Tag

  $hour     = sprintf("%02d",$hour);
  my $pvhh  = $data{$type}{$name}{pvhist};

  my ($dnum , $pvrl, $pvfc) = (0,0,0);
  my ($usenhd, $calcd)      = __useNumHistDays ($name);                                   # ist Attr affectNumHistDays gesetzt ? und welcher Wert

  my @k     = sort {$a<=>$b} keys %{$pvhh};
  my $ile   = $#k;                                                                        # Index letztes Arrayelement
  my ($idx) = grep {$k[$_] eq "$day"} (0..@k-1);                                          # Index des aktuellen Tages

  return ($pvrl, $pvfc, $dnum) if(!defined $idx);

  my $ei = $idx-1;
  $ei    = $ei < 0 ? $ile : $ei;

  my @efa;

  for my $e (0..$calcd) {                                                                 # old: $calcmaxd
      last if($e == $calcd || $k[$ei] == $day);                                           # old: $calcmaxd
      unshift @efa, $k[$ei];
      $ei--;
  }

  if(scalar(@efa)) {
      debugLog ($paref, "pvCorrection", "Simple Corrf -> Raw Days ($calcd) for average check: ".join " ",@efa);
  }
  else {
      debugLog ($paref, "pvCorrection", "Simple Corrf -> Day $day has index $idx. Use only current day for average calc");
      return ($pvrl, $pvfc, $dnum);
  }

  for my $dayfa (@efa) {
      $pvrl  += HistoryVal ($hash, $dayfa, $hour, 'pvrl', 0);
      $pvfc  += HistoryVal ($hash, $dayfa, $hour, 'pvfc', 0);
      $dnum++;

      debugLog ($paref, "pvCorrection", "Simple Corrf -> historical Day/hour $dayfa/$hour included -> PVreal: $pvrl, PVforecast: $pvfc");
      last if($dnum == $calcd);
  }

  $dnum = 0 if(!$pvrl && !$pvfc);                                                         # es gab keine gespeicherten Werte in pvHistory

  if(!$dnum) {
      Log3 ($name, 5, "$name - PV History -> no historical PV data forecast and real found");
      return ($pvrl, $pvfc, $dnum);
  }

  my $pvhis = sprintf "%.2f", $pvrl;
  my $fchis = sprintf "%.2f", $pvfc;

return ($pvhis, $fchis, $dnum);
}

################################################################
#    den neuen Korrekturfaktur berechnen
################################################################
sub __calcNewFactor {
  my $paref = shift;

  my $name   = $paref->{name};
  my $oldfac = $paref->{oldfac};
  my $dnum   = $paref->{dnum};
  my $pvre   = $paref->{pvre};
  my $pvfc   = $paref->{pvfc};
  my $pvhis  = $paref->{pvhis};
  my $fchis  = $paref->{fchis};

  my $factor;
  my ($usenhd) = __useNumHistDays ($name);                                                            # ist Attr affectNumHistDays gesetzt ?

  if ($dnum) {                                                                                        # Werte in History vorhanden -> haben Prio !
      $dnum++;
      $pvre   = ($pvre + $pvhis) / $dnum;                                                             # Ertrag aktuelle Stunde berücksichtigen
      $pvfc   = ($pvfc + $fchis) / $dnum;                                                             # Vorhersage aktuelle Stunde berücksichtigen
      $factor = sprintf "%.2f", ($pvre / $pvfc);                                                      # Faktorberechnung: reale PV / Prognose
  }
  elsif ($oldfac && !$usenhd) {                                                                       # keine Werte in History vorhanden, aber in CircularVal && keine Beschränkung durch Attr affectNumHistDays
      $dnum   = 1;
      $factor = sprintf "%.2f", ($pvre / $pvfc);
      $factor = sprintf "%.2f", ($factor + $oldfac) / 2;
  }
  else {                                                                                              # ganz neuer Wert
      $dnum   = 1;
      $factor = sprintf "%.2f", ($pvre / $pvfc);
  }

  $factor = 1.00 if(1 * $factor == 0);                                                                # 0.00-Werte ignorieren (Schleifengefahr)

return ($factor, $dnum);
}

################################################################
#       Ist Attribut 'affectNumHistDays' gesetzt ?
#       $usenhd: 1 - ja, 0 - nein
#       $nhd   : Anzahl der zu verwendenden HistDays
################################################################
sub __useNumHistDays {
  my $name = shift;

  my $usenhd = 0;
  my $nhd    = AttrVal($name, 'affectNumHistDays', $calcmaxd+1);

  if($nhd == $calcmaxd+1) {
      $nhd = $calcmaxd;
  }
  else {
      $usenhd = 1;
  }

return ($usenhd, $nhd);
}

################################################################
#            Qualität der Vorhersage berechnen
################################################################
sub __calcFcQuality {
  my $pvfc = shift;                                                        # PV Vorhersagewert
  my $pvre = shift;                                                        # PV reale Erzeugung

  return if(!$pvfc || !$pvre);

  my $diff = $pvfc - $pvre;
  my $hdv  = 1 - abs ($diff / $pvre);                                      # Abweichung der Stunde, 1 = bestmöglicher Wert

  $hdv = $hdv < 0 ? 0 : $hdv;
  $hdv = sprintf "%.2f", $hdv;

return $hdv;
}

###############################################################
#    Eintritt in den KI Train Prozess normal/Blocking
###############################################################
sub manageTrain {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  if (CircularVal ($hash, 99, 'runTimeTrainAI', 0) < $aibcthhld) {
      BlockingKill ($hash->{HELPER}{AIBLOCKRUNNING}) if(defined $hash->{HELPER}{AIBLOCKRUNNING});
      debugLog     ($paref, 'aiProcess', qq{AI Training is started in main process});
      aiTrain      ($paref);
  }
  else {
     delete $hash->{HELPER}{AIBLOCKRUNNING} if(defined $hash->{HELPER}{AIBLOCKRUNNING}{pid} && $hash->{HELPER}{AIBLOCKRUNNING}{pid} =~ /DEAD/xs);

     if (defined $hash->{HELPER}{AIBLOCKRUNNING}{pid}) {
         Log3 ($name, 3, qq{$name - another AI Training with PID "$hash->{HELPER}{AIBLOCKRUNNING}{pid}" is already running ... start Training aborted});
         return;
     }

     $paref->{block} = 1;

     $hash->{HELPER}{AIBLOCKRUNNING} = BlockingCall ( "FHEM::SolarForecast::aiTrain",
                                                      $paref,
                                                      "FHEM::SolarForecast::finishTrain",
                                                      $aitrblto,
                                                      "FHEM::SolarForecast::abortTrain",
                                                      $hash
                                                    );


     if (defined $hash->{HELPER}{AIBLOCKRUNNING}) {
         $hash->{HELPER}{AIBLOCKRUNNING}{loglevel} = 3;                                                       # Forum https://forum.fhem.de/index.php/topic,77057.msg689918.html#msg689918

         debugLog ($paref, 'aiProcess', qq{AI Training BlockingCall PID "$hash->{HELPER}{AIBLOCKRUNNING}{pid}" with Timeout "$aitrblto" started});
     }
  }

return;
}

###############################################################
#    Restaufgaben nach Update
###############################################################
sub finishTrain {
  my $serial = decode_base64 (shift);

  my $paref = eval { thaw ($serial) };                                             # Deserialisierung
  my $name  = $paref->{name};
  my $hash  = $defs{$name};
  my $type  = $hash->{TYPE};

  delete($hash->{HELPER}{AIBLOCKRUNNING}) if(defined $hash->{HELPER}{AIBLOCKRUNNING});

  my $aicanuse       = $paref->{aicanuse};
  my $aiinitstate    = $paref->{aiinitstate};
  my $aitrainstate   = $paref->{aitrainstate};
  my $runTimeTrainAI = $paref->{runTimeTrainAI};

  $data{$type}{$name}{current}{aicanuse}            = $aicanuse       if(defined $aicanuse);
  $data{$type}{$name}{current}{aiinitstate}         = $aiinitstate    if(defined $aiinitstate);
  $data{$type}{$name}{circular}{99}{runTimeTrainAI} = $runTimeTrainAI if(defined $runTimeTrainAI);  # !! in Circular speichern um zu persistieren, setTimeTracking speichert zunächst in Current !!

  if ($aitrainstate eq 'ok') {
      _readCacheFile ({ hash      => $hash,
                        name      => $name,
                        type      => $type,
                        file      => $aitrained.$name,
                        cachename => 'aitrained',
                        title     => 'aiTrainedData'
                      }
                     );
  }

return;
}

####################################################################################################
#                    Abbruchroutine BlockingCall Timeout
####################################################################################################
sub abortTrain {
  my $hash   = shift;
  my $cause  = shift // "Timeout: process terminated";
  my $name   = $hash->{NAME};
  my $type   = $hash->{TYPE};

  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{AIBLOCKRUNNING}{fn} pid:$hash->{HELPER}{AIBLOCKRUNNING}{pid} aborted: $cause");

  delete($hash->{HELPER}{AIBLOCKRUNNING});

  $data{$type}{$name}{current}{aitrainstate} = 'Traing (Child) process timed out';

return;
}

################################################################
#     KI Instanz(en) aus Raw Daten Hash
#     $data{$type}{$name}{aidectree}{airaw} hinzufügen
################################################################
sub aiAddInstance {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $taa   = $paref->{taa};          # do train after add

  return if(!isPrepared4AI ($hash));

  my $err;
  my $dtree = AiDetreeVal ($hash, 'object', undef);

  if (!$dtree) {
      $err = aiInit ($paref);
      return if($err);
      $dtree = AiDetreeVal ($hash, 'object', undef);
  }

  for my $idx (sort keys %{$data{$type}{$name}{aidectree}{airaw}}) {
      next if(!$idx);

      my $pvrl = AiRawdataVal ($hash, $idx, 'pvrl', undef);
      next if(!defined $pvrl);

      my $hod  = AiRawdataVal ($hash, $idx, 'hod', undef);
      next if(!defined $hod);

      my $rad1h = AiRawdataVal ($hash, $idx, 'rad1h', 0);
      next if($rad1h <= 0);

      my $temp  = AiRawdataVal ($hash, $idx, 'temp', 20);
      my $wcc   = AiRawdataVal ($hash, $idx, 'wcc',   0);
      my $wrp   = AiRawdataVal ($hash, $idx, 'wrp',   0);

      eval { $dtree->add_instance (attributes => { rad1h => $rad1h,
                                                   temp  => $temp,
                                                   wcc   => $wcc,
                                                   wrp   => $wrp,
                                                   hod   => $hod
                                                 },
                                                 result => $pvrl
                                  )
           }
           or do { Log3 ($name, 1, "$name - aiAddInstance ERROR: $@");
                   $data{$type}{$name}{current}{aiaddistate} = $@;
                   return;
                 };

      debugLog ($paref, 'aiProcess', qq{AI Instance added - hod: $hod, rad1h: $rad1h, pvrl: $pvrl, wcc: $wcc, wrp: $wrp, temp: $temp});
  }

  $data{$type}{$name}{aidectree}{object}    = $dtree;
  $data{$type}{$name}{current}{aiaddistate} = 'ok';

  if ($taa) {
      manageTrain ($paref);
  }

return;
}

################################################################
#     KI trainieren
################################################################
sub aiTrain {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $block = $paref->{block} // 0;

  my $serial;

  if (!isPrepared4AI ($hash)) {
      my $err = CurrentVal ($hash, 'aicanuse', '');
      $serial = encode_base64 (Serialize ( {name => $name, aicanuse => $err} ), "");
      $block ? return ($serial) : return \&finishTrain ($serial);
  }

  my $cst = [gettimeofday];                                           # Zyklus-Startzeit

  my $err;
  my $dtree = AiDetreeVal ($hash, 'object', undef);

  if (!$dtree) {
      $err = aiInit ($paref);

      if ($err) {
          $serial = encode_base64 (Serialize ( {name => $name, aiinitstate => $err} ), "");
          $block ? return ($serial) : return \&finishTrain ($serial);
      }

      $dtree = AiDetreeVal ($hash, 'object', undef);
  }

  eval { $dtree->train
       }
       or do { Log3 ($name, 1, "$name - aiTrain ERROR: $@");
               $data{$type}{$name}{current}{aitrainstate} = $@;
               $serial = encode_base64 (Serialize ( {name => $name, aitrainstate => $@} ), "");
               $block ? return ($serial) : return \&finishTrain ($serial);
             };

  $data{$type}{$name}{aidectree}{aitrained} = $dtree;
  $err                                      = writeCacheToFile ($hash, 'aitrained', $aitrained.$name);

  if (!$err) {
      debugLog ($paref, 'aiData',    qq{AI trained: }.Dumper $data{$type}{$name}{aidectree}{aitrained});
      debugLog ($paref, 'aiProcess', qq{AI trained and saved data into file: }.$aitrained.$name);
      debugLog ($paref, 'aiProcess', qq{Training instances and their associated information where purged from the AI object});
      $data{$type}{$name}{current}{aitrainstate} = 'ok';
  }

  setTimeTracking ($hash, $cst, 'runTimeTrainAI');                   # Zyklus-Laufzeit ermitteln

  $serial = encode_base64 (Serialize ( {name           => $name,
                                        aitrainstate   => CurrentVal ($hash, 'aitrainstate',   ''),
                                        runTimeTrainAI => CurrentVal ($hash, 'runTimeTrainAI', '')
                                       }
                                     )
                                     , "");

  delete $data{$type}{$name}{current}{runTimeTrainAI};

  $block ? return ($serial) : return \&finishTrain ($serial);

return;
}

################################################################
#     AI Ergebnis für ermitteln
################################################################
sub aiGetResult {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hod   = $paref->{hod};
  my $nhidx = $paref->{nhidx};

  return 'the AI usage is not prepared' if(!isPrepared4AI ($hash, 'full'));

  my $dtree = AiDetreeVal ($hash, 'aitrained', undef);

  if (!$dtree) {
      return 'AI trained object is missed';
  }

  my $rad1h = NexthoursVal ($hash, $nhidx, "rad1h", 0);
  return "no rad1h for hod: $hod" if($rad1h <= 0);

  my $wcc  = NexthoursVal ($hash, $nhidx, "cloudcover",  0);
  my $wrp  = NexthoursVal ($hash, $nhidx, "rainprob",    0);
  my $temp = NexthoursVal ($hash, $nhidx, "temp",       20);

  my $tbin = temp2bin  ($temp);
  my $cbin = cloud2bin ($wcc);
  my $rbin = rain2bin  ($wrp);

  my $pvaifc;

  eval { $pvaifc = $dtree->get_result (attributes => { rad1h => $rad1h,
                                                       temp  => $tbin,
                                                       wcc   => $cbin,
                                                       wrp   => $rbin,
                                                       hod   => $hod
                                                     }
                                      );
       };

  if ($@) {
      Log3 ($name, 1, "$name - aiGetResult ERROR: $@");
      return $@;
  }

  if (defined $pvaifc) {
      debugLog ($paref, 'aiData', qq{accurate result AI: pvaifc: $pvaifc (hod: $hod, rad1h: $rad1h, wcc: $wcc, wrp: $rbin, temp: $tbin)});
      return ('', $pvaifc);
  }

  my $msg = 'no decition delivered';

  ($msg, $pvaifc) = _aiGetSpread ( { hash  => $hash,
                                     name  => $name,
                                     type  => $type,
                                     rad1h => $rad1h,
                                     temp  => $tbin,
                                     wcc   => $cbin,
                                     wrp   => $rbin,
                                     hod   => $hod,
                                     dtree => $dtree,
                                     debug => $paref->{debug}
                                   }
                                 );

  if (defined $pvaifc) {
      return ('', $pvaifc);
  }

return $msg;
}

################################################################
#  AI Ergebnis aus einer positiven und negativen
#  rad1h-Abweichung schätzen
################################################################
sub _aiGetSpread {
  my $paref = shift;
  my $rad1h = $paref->{rad1h};
  my $temp  = $paref->{temp};
  my $wcc   = $paref->{wcc};
  my $wrp   = $paref->{wrp};
  my $hod   = $paref->{hod};
  my $dtree = $paref->{dtree};

  my $dtn  = 20;                               # positive und negative rad1h Abweichung testen mit Schrittweite "$step"
  my $step = 10;

  my ($pos, $neg, $p, $n);

  debugLog ($paref, 'aiData', qq{no accurate result AI found with initial value "$rad1h"});
  debugLog ($paref, 'aiData', qq{test AI estimation with variance "$dtn", positive/negative step "$step"});

  for ($p = $rad1h; $p <= $rad1h + $dtn; $p += $step) {
      $p = sprintf "%.2f", $p;

      eval { $pos = $dtree->get_result (attributes => { rad1h => $p,
                                                        temp  => $temp,
                                                        wcc   => $wcc,
                                                        wrp   => $wrp,
                                                        hod   => $hod
                                                      }
                                          );
           };

      if ($@) {
          return $@;
      }

      if ($pos) {
          debugLog ($paref, 'aiData', qq{AI estimation with test value "$p": $pos});
          last;
      }
  }

  for ($n = $rad1h; $n >= $rad1h - $dtn; $n -= $step) {
      last if($n <= 0);
      $n = sprintf "%.2f", $n;

      eval { $neg = $dtree->get_result (attributes => { rad1h => $n,
                                                        temp  => $temp,
                                                        wcc   => $wcc,
                                                        wrp   => $wrp,
                                                        hod   => $hod
                                                      }
                                          );
           };

      if ($@) {
          return $@;
      }

      if ($neg) {
          debugLog ($paref, 'aiData', qq{AI estimation with test value "$n": $neg});
          last;
      }
  }

  my $pvaifc = $pos && $neg ? sprintf "%.0f", (($pos + $neg) / 2) : undef;

  if (defined $pvaifc) {
      debugLog ($paref, 'aiData', qq{appreciated result AI: pvaifc: $pvaifc (hod: $hod, wcc: $wcc, wrp: $wrp, temp: $temp)});
      return ('', $pvaifc);
  }

return 'no decition delivered';
}

################################################################
#     KI initialisieren
################################################################
sub aiInit {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};

  if (!isPrepared4AI ($hash)) {
      my $err = CurrentVal ($hash, 'aicanuse', '');

      debugLog ($paref, 'aiProcess', $err);

      $data{$type}{$name}{current}{aiinitstate} = $err;
      return $err;
  }

  my $dtree = new AI::DecisionTree ( verbose => 0, noise_mode => 'pick_best' );

  $data{$type}{$name}{aidectree}{object}    = $dtree;
  $data{$type}{$name}{current}{aiinitstate} = 'ok';

  Log3 ($name, 3, "$name - AI::DecisionTree initialized");

return;
}

################################################################
#    Daten der Raw Datensammlung hinzufügen
################################################################
sub aiAddRawData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $day   = $paref->{day} // strftime "%d",  localtime(time);           # aktueller Tag (range 01 to 31)
  my $ood   = $paref->{ood} // 0;                                         # only one (current) day
  my $rho   = $paref->{rho};                                              # only this hour of day

  delete $data{$type}{$name}{current}{aitrawstate};

  my ($err, $dosave);

  for my $pvd (sort keys %{$data{$type}{$name}{pvhist}}) {
      next if(!$pvd);

      if ($ood) {
          next if($pvd ne $paref->{day});
      }

      last if(int $pvd > int $day);

      for my $hod (sort keys %{$data{$type}{$name}{pvhist}{$pvd}}) {
          next if(!$hod || $hod eq '99' || ($rho && $hod ne $rho));

          my $pvrlvd = HistoryVal ($hash, $pvd, $hod, 'pvrlvd', 1);

          if (!$pvrlvd) {                                                        # Datensatz ignorieren wenn als invalid gekennzeichnet
              debugLog ($paref, 'aiProcess', qq{AI raw data is marked as invalid and is ignored - day: $pvd, hod: $hod});
              next;
          }

          my $rad1h = HistoryVal ($hash, $pvd, $hod, 'rad1h', undef);
          next if(!$rad1h || $rad1h <= 0);

          my $pvrl  = HistoryVal ($hash, $pvd, $hod, 'pvrl', undef);
          next if(!$pvrl || $pvrl <= 0);

          my $ridx = _aiMakeIdxRaw ($pvd, $hod);

          my $temp = HistoryVal ($hash, $pvd, $hod, 'temp', 20);
          my $wcc  = HistoryVal ($hash, $pvd, $hod, 'wcc',   0);
          my $wrp  = HistoryVal ($hash, $pvd, $hod, 'wrp',   0);

          my $tbin = temp2bin  ($temp);
          my $cbin = cloud2bin ($wcc);
          my $rbin = rain2bin  ($wrp);

          $data{$type}{$name}{aidectree}{airaw}{$ridx}{rad1h} = $rad1h;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{temp}  = $tbin;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{wcc}   = $cbin;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{wrp}   = $rbin;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{hod}   = $hod;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{pvrl}  = $pvrl;

          $dosave = 1;

          debugLog ($paref, 'aiProcess', qq{AI raw data added - idx: $ridx, day: $pvd, hod: $hod, rad1h: $rad1h, pvrl: $pvrl, wcc: $cbin, wrp: $rbin, temp: $tbin});
      }
  }

  if ($dosave) {
      $err = writeCacheToFile ($hash, 'airaw', $airaw.$name);

      if (!$err) {
          $data{$type}{$name}{current}{aitrawstate} = 'ok';
          debugLog ($paref, 'aiProcess', qq{AI raw data saved into file: }.$airaw.$name);
      }
  }

return;
}

################################################################
#    Daten aus Raw Datensammlung löschen welche die maximale
#    Haltezeit (Tage) überschritten haben
################################################################
sub aiDelRawData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};

  if (!keys %{$data{$type}{$name}{aidectree}{airaw}}) {
      return;
  }

  my $hd   = AttrVal ($name, 'ctrlAIdataStorageDuration', $aistdudef);          # Haltezeit KI Raw Daten (Tage)
  my $ht   = time - ($hd * 86400);
  my $day  = strftime "%d", localtime($ht);
  my $didx = _aiMakeIdxRaw ($day, '00', $ht);                                   # Daten mit idx <= $didx löschen

  debugLog ($paref, 'aiProcess', qq{AI Raw delete data equal or less than index >$didx<});

  delete $data{$type}{$name}{current}{aitrawstate};

  my ($err, $dosave);

  for my $idx (sort keys %{$data{$type}{$name}{aidectree}{airaw}}) {
      next if(!$idx || $idx > $didx);
      delete $data{$type}{$name}{aidectree}{airaw}{$idx};

      $dosave = 1;

      debugLog ($paref, 'aiProcess', qq{AI Raw data deleted - idx: $idx});
  }

  if ($dosave) {
      $err = writeCacheToFile ($hash, 'airaw', $airaw.$name);

      if (!$err) {
          $data{$type}{$name}{current}{aitrawstate} = 'ok';
          debugLog ($paref, 'aiProcess', qq{AI raw data saved into file: }.$airaw.$name);
      }
  }

return;
}

################################################################
#  den Index für AI raw Daten erzeugen
################################################################
sub _aiMakeIdxRaw {
  my $day = shift;
  my $hod = shift;
  my $t   = shift // time;

  my $ridx = strftime "%Y%m", localtime($t);
  $ridx   .= $day.$hod;

return $ridx;
}

################################################################
#   History-Hash verwalten
################################################################
sub setPVhistory {
  my $paref          = shift;
  my $hash           = $paref->{hash};
  my $name           = $paref->{name};
  my $t              = $paref->{t};                                        # aktuelle Unix-Zeit
  my $nhour          = $paref->{nhour};
  my $day            = $paref->{day};
  my $dayname        = $paref->{dayname};                                  # aktueller Wochentagsname
  my $histname       = $paref->{histname}      // qq{};
  my $pvrlvd         = $paref->{pvrlvd};                                   # 1: Eintrag 'pvrl' wird im Lernprozess berücksichtigt
  my $ethishour      = $paref->{ethishour}     // 0;
  my $etotal         = $paref->{etotal};
  my $batinthishour  = $paref->{batinthishour};                            # Batterieladung in Stunde
  my $btotin         = $paref->{batintotal};                               # totale Batterieladung
  my $batoutthishour = $paref->{batoutthishour};                           # Batterieentladung in Stunde
  my $btotout        = $paref->{batouttotal};                              # totale Batterieentladung
  my $batmaxsoc      = $paref->{batmaxsoc};                                # max. erreichter SOC des Tages
  my $batsetsoc      = $paref->{batsetsoc};                                # berechneter optimaler SOC für den laufenden Tag
  my $calcpv         = $paref->{calcpv}        // 0;
  my $gcthishour     = $paref->{gctotthishour} // 0;                       # Netzbezug
  my $fithishour     = $paref->{gftotthishour} // 0;                       # Netzeinspeisung
  my $con            = $paref->{con}           // 0;                       # realer Hausverbrauch Energie
  my $confc          = $paref->{confc}         // 0;                       # Verbrauchsvorhersage
  my $consumerco     = $paref->{consumerco};                               # Verbrauch eines Verbrauchers
  my $wid            = $paref->{wid}           // -1;
  my $wcc            = $paref->{wcc}           // 0;                       # Wolkenbedeckung
  my $wrp            = $paref->{wrp}           // 0;                       # Wahrscheinlichkeit von Niederschlag
  my $pvcorrf        = $paref->{pvcorrf}       // "1.00/0";                # pvCorrectionFactor
  my $temp           = $paref->{temp};                                     # Außentemperatur
  my $val            = $paref->{val}           // qq{};                    # Wert zur Speicherung in pvHistory (soll mal generell verwendet werden -> Change)
  my $rad1h          = $paref->{rad1h};                                    # Strahlungsdaten speichern
  my $reorg          = $paref->{reorg}         // 0;                       # Neuberechnung von Werten in Stunde "99" nach Löschen von Stunden eines Tages
  my $reorgday       = $paref->{reorgday}      // q{};                     # Tag der reorganisiert werden soll

  my $type = $hash->{TYPE};

  $data{$type}{$name}{pvhist}{$day}{99}{dayname} = $dayname if($day);

  if ($histname eq "batinthishour") {                                                             # Batterieladung
      $val = $batinthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batin} = $batinthishour;

      my $batinsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $batinsum += HistoryVal ($hash, $day, $k, "batin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{batin} = $batinsum;
  }

  if ($histname eq "batoutthishour") {                                                            # Batterieentladung
      $val = $batoutthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batout} = $batoutthishour;

      my $batoutsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $batoutsum += HistoryVal ($hash, $day, $k, "batout", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{batout} = $batoutsum;
  }

  if ($histname eq "batmaxsoc") {                                                                 # max. erreichter SOC des Tages
      $val = $batmaxsoc;
      $data{$type}{$name}{pvhist}{$day}{99}{batmaxsoc} = $batmaxsoc;
  }

  if ($histname eq "batsetsoc") {                                                                 # optimaler SOC für den Tages
      $val = $batsetsoc;
      $data{$type}{$name}{pvhist}{$day}{99}{batsetsoc} = $batsetsoc;
  }

  if ($histname eq 'pvrl') {                                                                      # realer Energieertrag
      $val = $ethishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvrl}   = $ethishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvrlvd} = $pvrlvd;

      my $pvrlsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvrlsum += HistoryVal ($hash, $day, $k, 'pvrl', 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvrl} = $pvrlsum;
  }

  if ($histname eq "radiation") {                                                                 # irradiation
      $data{$type}{$name}{pvhist}{$day}{$nhour}{rad1h} = $rad1h;
  }

  if ($histname eq 'pvfc') {                                                                      # prognostizierter Energieertrag
      $val = $calcpv;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvfc} = $calcpv;

      my $pvfcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvfcsum += HistoryVal ($hash, $day, $k, 'pvfc', 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvfc} = $pvfcsum;
  }

  if ($histname eq "confc") {                                                                      # prognostizierter Hausverbrauch
      $val = $confc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{confc} = $confc;

      my $confcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $confcsum += HistoryVal ($hash, $day, $k, "confc", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{confc} = $confcsum;
  }

  if ($histname eq "cons") {                                                                      # bezogene Energie
      $val = $gcthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gcons} = $gcthishour;

      my $gcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gcsum += HistoryVal ($hash, $day, $k, "gcons", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gcons} = $gcsum;
  }

  if ($histname eq "gfeedin") {                                                                   # eingespeiste Energie
      $val = $fithishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gfeedin} = $fithishour;

      my $gfisum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gfisum += HistoryVal ($hash, $day, $k, "gfeedin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gfeedin} = $gfisum;
  }

  if ($histname eq "con") {                                                                      # Energieverbrauch des Hauses
      $val = $con;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{con} = $con;

      my $consum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $consum += HistoryVal ($hash, $day, $k, "con", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{con} = $consum;
  }

  if ($histname =~ /csm[et][0-9]+$/xs) {                                                         # Verbrauch eines Verbrauchers
      $val = $consumerco;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{$histname} = $consumerco;

      if($histname =~ /csme[0-9]+$/xs) {
          my $sum = 0;

          for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
              next if($k eq "99");
              my $csme = HistoryVal ($hash, $day, $k, "$histname", 0);
              next if(!$csme);

              $sum += $csme;
          }

          $data{$type}{$name}{pvhist}{$day}{99}{$histname} = sprintf "%.2f", $sum;
      }
  }

  if ($histname =~ /cyclescsm[0-9]+$/xs) {                                                         # Anzahl Tageszyklen des Verbrauchers
      $data{$type}{$name}{pvhist}{$day}{99}{$histname} = $val;
  }

  if ($histname =~ /minutescsm[0-9]+$/xs) {                                                        # Anzahl Aktivminuten des Verbrauchers
      $data{$type}{$name}{pvhist}{$day}{$nhour}{$histname} = $val;
      my $minutes = 0;
      my $num     = substr ($histname,10,2);

      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          my $csmm = HistoryVal ($hash, $day, $k, "$histname", 0);
          next if(!$csmm);

          $minutes += $csmm;
      }

      my $cycles = HistoryVal ($hash, $day, 99, "cyclescsm${num}", 0);
      $data{$type}{$name}{pvhist}{$day}{99}{"hourscsme${num}"} = sprintf "%.2f", ($minutes / 60 ) if($cycles);
  }

  if ($histname eq "etotal") {                                                                    # etotal des Wechselrichters
      $val = $etotal;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{etotal} = $etotal;
      $data{$type}{$name}{pvhist}{$day}{99}{etotal}     = q{};
  }

  if ($histname eq "batintotal") {                                                                # totale Batterieladung
      $val = $btotin;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batintotal} = $btotin;
      $data{$type}{$name}{pvhist}{$day}{99}{batintotal}     = q{};
  }

  if ($histname eq "batouttotal") {                                                               # totale Batterieentladung
      $val = $btotout;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batouttotal} = $btotout;
      $data{$type}{$name}{pvhist}{$day}{99}{batouttotal}     = q{};
  }

  if ($histname eq "weatherid") {                                                                 # Wetter ID
      $val = $wid;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{weatherid} = $wid;
      $data{$type}{$name}{pvhist}{$day}{99}{weatherid}     = q{};
  }

  if ($histname eq "weathercloudcover") {                                                         # Wolkenbedeckung
      $val = $wcc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wcc} = $wcc;
      $data{$type}{$name}{pvhist}{$day}{99}{wcc}     = q{};
  }

  if ($histname eq "weatherrainprob") {                                                           # Niederschlagswahrscheinlichkeit
      $val = $wrp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wrp} = $wrp;
      $data{$type}{$name}{pvhist}{$day}{99}{wrp}     = q{};
  }

  if ($histname eq "pvcorrfactor") {                                                              # pvCorrectionFactor
      $val = $pvcorrf;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvcorrf} = $pvcorrf;
      $data{$type}{$name}{pvhist}{$day}{99}{pvcorrf}     = q{};
  }

  if ($histname eq "temperature") {                                                               # Außentemperatur
      $val = $temp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{temp} = $temp;
      $data{$type}{$name}{pvhist}{$day}{99}{temp}     = q{};
  }

  if ($reorg) {                                                                                   # Reorganisation Stunde "99"
      if (!$reorgday) {
         Log3 ($name, 1, "$name - ERROR reorg pvHistory - the day of reorganization is invalid or empty: >$reorgday<");
         return;
      }

      my ($r1, $r2, $r3, $r4, $r5, $r6, $r7, $r8) = (0,0,0,0,0,0,0,0);

      for my $k (keys %{$data{$type}{$name}{pvhist}{$reorgday}}) {
          next if($k eq "99");

          $r1 += HistoryVal ($hash, $reorgday, $k, 'batin',   0);
          $r2 += HistoryVal ($hash, $reorgday, $k, 'batout',  0);
          $r3 += HistoryVal ($hash, $reorgday, $k, 'pvrl',    0);
          $r4 += HistoryVal ($hash, $reorgday, $k, 'pvfc',    0);
          $r5 += HistoryVal ($hash, $reorgday, $k, 'confc',   0);
          $r6 += HistoryVal ($hash, $reorgday, $k, 'gcons',   0);
          $r7 += HistoryVal ($hash, $reorgday, $k, 'gfeedin', 0);
          $r8 += HistoryVal ($hash, $reorgday, $k, 'con',     0);
      }

      $data{$type}{$name}{pvhist}{$reorgday}{99}{batin}   = $r1;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{batout}  = $r2;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{pvrl}    = $r3;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{pvfc}    = $r4;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{confc}   = $r5;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{gcons}   = $r6;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{gfeedin} = $r7;
      $data{$type}{$name}{pvhist}{$reorgday}{99}{con}     = $r8;

      debugLog ($paref, 'saveData2Cache', "setPVhistory -> PV History day >$reorgday< reorganized keys: batin, batout, pvrl, pvfc, con, confc, gcons, gfeedin");
  }

  if ($histname) {
      debugLog ($paref, 'saveData2Cache', "setPVhistory -> save PV History Day: $day, Hour: $nhour, Key: $histname, Value: $val");
  }

return;
}

################################################################
#           liefert aktuelle Einträge des in $htol
#           angegebenen internen Hash
################################################################
sub listDataPool {
  my $hash = shift;
  my $htol = shift;
  my $par  = shift // q{};

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my ($sq,$h);

  my $sub = sub {
      my $day = shift;
      my $ret;
      for my $key (sort {$a<=>$b} keys %{$h->{$day}}) {
          my $pvrl    = HistoryVal ($hash, $day, $key, 'pvrl',        '-');
          my $pvrlvd  = HistoryVal ($hash, $day, $key, 'pvrlvd',      '-');
          my $pvfc    = HistoryVal ($hash, $day, $key, 'pvfc',        '-');
          my $gcon    = HistoryVal ($hash, $day, $key, 'gcons',       '-');
          my $con     = HistoryVal ($hash, $day, $key, 'con',         '-');
          my $confc   = HistoryVal ($hash, $day, $key, 'confc',       '-');
          my $gfeedin = HistoryVal ($hash, $day, $key, 'gfeedin',     '-');
          my $wid     = HistoryVal ($hash, $day, $key, 'weatherid',   '-');
          my $wcc     = HistoryVal ($hash, $day, $key, 'wcc',         '-');
          my $wrp     = HistoryVal ($hash, $day, $key, 'wrp',         '-');
          my $temp    = HistoryVal ($hash, $day, $key, 'temp',      undef);
          my $pvcorrf = HistoryVal ($hash, $day, $key, 'pvcorrf',     '-');
          my $dayname = HistoryVal ($hash, $day, $key, 'dayname',   undef);
          my $etotal  = HistoryVal ($hash, $day, $key, 'etotal',      '-');
          my $btotin  = HistoryVal ($hash, $day, $key, 'batintotal',  '-');
          my $batin   = HistoryVal ($hash, $day, $key, 'batin',       '-');
          my $btotout = HistoryVal ($hash, $day, $key, 'batouttotal', '-');
          my $batout  = HistoryVal ($hash, $day, $key, 'batout',      '-');
          my $batmsoc = HistoryVal ($hash, $day, $key, 'batmaxsoc',   '-');
          my $batssoc = HistoryVal ($hash, $day, $key, 'batsetsoc',   '-');
          my $rad1h   = HistoryVal ($hash, $day, $key, 'rad1h',       '-');

          $ret .= "\n      " if($ret);
          $ret .= $key." => etotal: $etotal, pvfc: $pvfc, pvrl: $pvrl, pvrlvd: $pvrlvd, rad1h: $rad1h";
          $ret .= "\n            ";
          $ret .= "confc: $confc, con: $con, gcon: $gcon, gfeedin: $gfeedin";
          $ret .= "\n            ";
          $ret .= "batintotal: $btotin, batin: $batin, batouttotal: $btotout, batout: $batout";
          $ret .= "\n            ";
          $ret .= "batmaxsoc: $batmsoc, batsetsoc: $batssoc";
          $ret .= "\n            ";
          $ret .= "wid: $wid";
          $ret .= ", wcc: $wcc";
          $ret .= ", wrp: $wrp";
          $ret .= ", temp: $temp"       if($temp);
          $ret .= ", pvcorrf: $pvcorrf";
          $ret .= ", dayname: $dayname" if($dayname);

          my $csm;
          for my $c (1..$maxconsumer) {
              $c        = sprintf "%02d", $c;
              my $nl    = 0;
              my $csmc  = HistoryVal ($hash, $day, $key, "cyclescsm${c}",  undef);
              my $csmt  = HistoryVal ($hash, $day, $key, "csmt${c}",       undef);
              my $csme  = HistoryVal ($hash, $day, $key, "csme${c}",       undef);
              my $csmm  = HistoryVal ($hash, $day, $key, "minutescsm${c}", undef);
              my $csmh  = HistoryVal ($hash, $day, $key, "hourscsme${c}",  undef);

              if(defined $csmc) {
                  $csm .= "cyclescsm${c}: $csmc";
                  $nl   = 1;
              }

              if(defined $csmt) {
                  $csm .= ", " if($nl);
                  $csm .= "csmt${c}: $csmt";
                  $nl   = 1;
              }

              if(defined $csme) {
                  $csm .= ", " if($nl);
                  $csm .= "csme${c}: $csme";
                  $nl   = 1;
              }

              if(defined $csmm) {
                  $csm .= ", " if($nl);
                  $csm .= "minutescsm${c}: $csmm";
                  $nl   = 1;
              }

              if(defined $csmh) {
                  $csm .= ", " if($nl);
                  $csm .= "hourscsme${c}: $csmh";
                  $nl   = 1;
              }

              $csm .= "\n            " if($nl);
          }

          if($csm) {
              $ret .= "\n            ";
              $ret .= $csm;
          }
      }
      return $ret;
  };

  if ($htol eq "pvhist") {
      $h = $data{$type}{$name}{pvhist};

      if (!keys %{$h}) {
          return qq{PV cache is empty.};
      }

      for my $i (keys %{$h}) {
          if (!isNumeric ($i)) {
              delete $data{$type}{$name}{pvhist}{$i};
              Log3 ($name, 2, qq{$name - INFO - invalid key "$i" was deleted from pvHistory storage});
          }
      }

      for my $idx (sort{$a<=>$b} keys %{$h}) {
          next if($par && $idx ne $par);
          $sq .= $idx." => ".$sub->($idx)."\n";
      }
  }

  if ($htol eq "consumer") {
      $h = $data{$type}{$name}{consumers};
      if (!keys %{$h}) {
          return qq{Consumer cache is empty.};
      }

      for my $i (keys %{$h}) {
          if ($i !~ /^[0-9]{2}$/ix) {                                   # bereinigen ungültige consumer, Forum: https://forum.fhem.de/index.php/topic,117864.msg1173219.html#msg1173219
              delete $data{$type}{$name}{consumers}{$i};
              Log3 ($name, 2, qq{$name - INFO - invalid consumer key "$i" was deleted from consumer storage});
          }
      }

      for my $idx (sort{$a<=>$b} keys %{$h}) {
          next if($par && $idx ne $par);
          my $cret;

          for my $ckey (sort keys %{$h->{$idx}}) {
              if(ref $h->{$idx}{$ckey} eq "HASH") {
                  my $hk = qq{};
                  for my $f (sort {$a<=>$b} keys %{$h->{$idx}{$ckey}}) {
                      $hk .= " " if($hk);
                      $hk .= "$f=".$h->{$idx}{$ckey}{$f};
                  }
                  $cret .= $ckey." => ".$hk."\n      ";
              }
              else {
                  $cret .= $ckey." => ".ConsumerVal ($hash, $idx, $ckey, "")."\n      ";
              }
          }

          $sq .= $idx." => ".$cret."\n";
      }
  }

  if ($htol eq "circular") {
      $h = $data{$type}{$name}{circular};
      if (!keys %{$h}) {
          return qq{Circular cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $pvfc     = CircularVal ($hash, $idx, "pvfc",                '-');
          my $pvaifc   = CircularVal ($hash, $idx, "pvaifc",              '-');
          my $pvapifc  = CircularVal ($hash, $idx, "pvapifc",             '-');
          my $aihit    = CircularVal ($hash, $idx, "aihit",               '-');
          my $pvrl     = CircularVal ($hash, $idx, 'pvrl',                '-');
          my $confc    = CircularVal ($hash, $idx, "confc",               '-');
          my $gcons    = CircularVal ($hash, $idx, "gcons",               '-');
          my $gfeedin  = CircularVal ($hash, $idx, "gfeedin",             '-');
          my $wid      = CircularVal ($hash, $idx, "weatherid",           '-');
          my $wtxt     = CircularVal ($hash, $idx, "weathertxt",          '-');
          my $wccv     = CircularVal ($hash, $idx, "wcc",                 '-');
          my $wrprb    = CircularVal ($hash, $idx, "wrp",                 '-');
          my $temp     = CircularVal ($hash, $idx, "temp",                '-');
          my $pvcorrf  = CircularVal ($hash, $idx, "pvcorrf",             '-');
          my $quality  = CircularVal ($hash, $idx, "quality",             '-');
          my $batin    = CircularVal ($hash, $idx, "batin",               '-');
          my $batout   = CircularVal ($hash, $idx, "batout",              '-');
          my $tdayDvtn = CircularVal ($hash, $idx, "tdayDvtn",            '-');
          my $ydayDvtn = CircularVal ($hash, $idx, "ydayDvtn",            '-');
          my $ltsmsr   = CircularVal ($hash, $idx, 'lastTsMaxSocRchd',    '-');
          my $ntsmsc   = CircularVal ($hash, $idx, 'nextTsMaxSocChge',    '-');
          my $dtocare  = CircularVal ($hash, $idx, 'days2care',           '-');
          my $fitot    = CircularVal ($hash, $idx, "feedintotal",         '-');
          my $idfi     = CircularVal ($hash, $idx, "initdayfeedin",       '-');
          my $gcontot  = CircularVal ($hash, $idx, "gridcontotal",        '-');
          my $idgcon   = CircularVal ($hash, $idx, "initdaygcon",         '-');
          my $idbitot  = CircularVal ($hash, $idx, "initdaybatintot",     '-');
          my $bitot    = CircularVal ($hash, $idx, "batintot",            '-');
          my $idbotot  = CircularVal ($hash, $idx, "initdaybatouttot",    '-');
          my $botot    = CircularVal ($hash, $idx, "batouttot",           '-');
          my $rtaitr   = CircularVal ($hash, $idx, "runTimeTrainAI",      '-');

          no warnings 'numeric';

          my $pvcf = qq{};
          if(ref $pvcorrf eq "HASH") {
              for my $f (sort {$a<=>$b} keys %{$h->{$idx}{pvcorrf}}) {
                  next if($f eq 'percentile');
                  $pvcf .= " " if($pvcf);
                  $pvcf .= "$f=".$h->{$idx}{pvcorrf}{$f};
                  my $ct = ($pvcf =~ tr/=// // 0) / 10;
                  $pvcf .= "\n           " if($ct =~ /^([1-9])?$/);
              }

              if (defined $h->{$idx}{pvcorrf}{'percentile'}) {
                  $pvcf .= "\n           " if($pvcf && $pvcf !~ /\n\s+$/xs);
                  $pvcf .= " "             if($pvcf);
                  $pvcf .= "percentile=".$h->{$idx}{pvcorrf}{'percentile'};
              }
          }
          else {
              $pvcf = $pvcorrf;
          }

          my $cfq = qq{};
          if(ref $quality eq "HASH") {
              for my $q (sort {$a<=>$b} keys %{$h->{$idx}{quality}}) {
                  next if($q eq 'percentile');
                  $cfq   .= " " if($cfq);
                  $cfq   .= "$q=".$h->{$idx}{quality}{$q};
                  $cfq   .= "\n              " if($q eq 'percentile');
                  my $ct1 = ($cfq =~ tr/=// // 0) / 10;
                  $cfq   .= "\n              " if($ct1 =~ /^([1-9])?$/);
              }

              if (defined $h->{$idx}{quality}{'percentile'}) {
                  $cfq .= "\n              " if($cfq && $cfq !~ /\n\s+$/xs);
                  $cfq .= " "                if($cfq);
                  $cfq .= "percentile=".$h->{$idx}{quality}{'percentile'};
              }
          }
          else {
              $cfq = $quality;
          }

          use warnings;

          $sq .= "\n" if($sq);

          if($idx != 99) {
              $sq .= $idx." => pvapifc: $pvapifc, pvaifc: $pvaifc, pvfc: $pvfc, aihit: $aihit, pvrl: $pvrl\n";
              $sq .= "      batin: $batin, batout: $batout, confc: $confc, gcon: $gcons, gfeedin: $gfeedin, wcc: $wccv, wrp: $wrprb\n";
              $sq .= "      temp: $temp, wid: $wid, wtxt: $wtxt\n";
              $sq .= "      corr: $pvcf\n";
              $sq .= "      quality: $cfq";
          }
          else {
              $sq .= $idx." => tdayDvtn: $tdayDvtn, ydayDvtn: $ydayDvtn\n";
              $sq .= "      feedintotal: $fitot, initdayfeedin: $idfi\n";
              $sq .= "      gridcontotal: $gcontot, initdaygcon: $idgcon\n";
              $sq .= "      batintot: $bitot, initdaybatintot: $idbitot\n";
              $sq .= "      batouttot: $botot, initdaybatouttot: $idbotot\n";
              $sq .= "      lastTsMaxSocRchd: $ltsmsr, nextTsMaxSocChge: $ntsmsc, days2care:$dtocare \n";
              $sq .= "      runTimeTrainAI: $rtaitr\n";
          }
      }
  }

  if ($htol eq "nexthours") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhts    = NexthoursVal ($hash, $idx, 'starttime',  '-');
          my $hod     = NexthoursVal ($hash, $idx, 'hourofday',  '-');
          my $today   = NexthoursVal ($hash, $idx, 'today',      '-');
          my $pvfc    = NexthoursVal ($hash, $idx, 'pvfc',       '-');
          my $pvapifc = NexthoursVal ($hash, $idx, 'pvapifc',    '-');             # PV Forecast der API
          my $pvaifc  = NexthoursVal ($hash, $idx, 'pvaifc',     '-');             # PV Forecast der KI
          my $aihit   = NexthoursVal ($hash, $idx, 'aihit',      '-');             # KI ForeCast Treffer Status
          my $wid     = NexthoursVal ($hash, $idx, 'weatherid',  '-');
          my $neff    = NexthoursVal ($hash, $idx, 'cloudcover', '-');
          my $crange  = NexthoursVal ($hash, $idx, 'cloudrange', '-');
          my $r101    = NexthoursVal ($hash, $idx, 'rainprob',   '-');
          my $rrange  = NexthoursVal ($hash, $idx, 'rainrange',  '-');
          my $rad1h   = NexthoursVal ($hash, $idx, 'rad1h',      '-');
          my $pvcorrf = NexthoursVal ($hash, $idx, 'pvcorrf',    '-');
          my $temp    = NexthoursVal ($hash, $idx, 'temp',       '-');
          my $confc   = NexthoursVal ($hash, $idx, 'confc',      '-');
          my $confcex = NexthoursVal ($hash, $idx, 'confcEx',    '-');
          my $don     = NexthoursVal ($hash, $idx, 'DoN',        '-');
          $sq        .= "\n" if($sq);
          $sq        .= $idx." => starttime: $nhts, hourofday: $hod, today: $today\n";
          $sq        .= "              pvapifc: $pvapifc, pvaifc: $pvaifc, pvfc: $pvfc, aihit: $aihit, confc: $confc\n";
          $sq        .= "              confcEx: $confcex, DoN: $don, wid: $wid, wcc: $neff, wrp: $r101, temp=$temp\n";
          $sq        .= "              rad1h: $rad1h, rrange: $rrange, crange: $crange, correff: $pvcorrf";
      }
  }

  if ($htol eq "qualities") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhfc    = NexthoursVal ($hash, $idx, 'pvfc', undef);
          next if(!$nhfc);
          my $nhts    = NexthoursVal ($hash, $idx, 'starttime',  undef);
          my $neff    = NexthoursVal ($hash, $idx, 'cloudcover',   '-');
          my $crange  = NexthoursVal ($hash, $idx, 'cloudrange',   '-');
          my $r101    = NexthoursVal ($hash, $idx, 'rainprob',     '-');
          my $rrange  = NexthoursVal ($hash, $idx, 'rainrange',    '-');
          my $pvcorrf = NexthoursVal ($hash, $idx, 'pvcorrf',    '-/-');
          my ($f,$q)  = split "/", $pvcorrf;
          $sq        .= "\n" if($sq);
          $sq        .= "starttime: $nhts, wrp: $r101, rrange: $rrange, wcc: $neff, crange: $crange, quality: $q, factor: $f";
      }
  }

  if ($htol eq "current") {
      $h = $data{$type}{$name}{current};
      if (!keys %{$h}) {
          return qq{Current values cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          if (ref $h->{$idx} ne "ARRAY") {
              $sq .= $idx." => ".$h->{$idx}."\n";
          }
          else {
             my $aser = join " ",@{$h->{$idx}};
             $sq .= $idx." => ".$aser."\n";
          }
      }
  }

  my $git = sub {
      my $it     = shift;
      my @sorted = sort keys %$it;
      my $key    = shift @sorted;

      my $ret = {};
      $ret    = { $key => $it->{$key} } if($key);

      return $ret;
  };

  if ($htol eq "solApiData") {
      $h = $data{$type}{$name}{solcastapi};
      if (!keys %{$h}) {
          return qq{SolCast API values cache is empty.};
      }

      my $pve   = q{};
      my $itref = dclone $h;                                                         # Deep Copy von $h

      for my $idx (sort keys %{$itref}) {
          my $s1;
          my $sp1 = _ldpspaces ($idx, q{});
          $sq    .= $idx." => ";

          while (my ($tag, $item) = each %{$git->($itref->{$idx})}) {
              $sq .= ($s1 ? $sp1 : "").$tag." => ";

              if (ref $item eq "HASH") {
                  my $s2;
                  my $sp2 = _ldpspaces ($tag, $sp1);

                  while (my ($tag1, $item1) = each %{$git->($itref->{$idx}{$tag})}) {
                      $sq .= ($s2 ? $sp2 : "")."$tag1: ".$item1."\n";
                      $s2  = 1;
                      delete $itref->{$idx}{$tag}{$tag1};
                  }
              }

              $s1  = 1;
              $sq .= "\n" if($sq !~ /\n$/xs);

              delete $itref->{$idx}{$tag};
          }
      }
  }

  if ($htol eq "aiRawData") {
      $h         = $data{$type}{$name}{aidectree}{airaw};
      my $maxcnt = keys %{$h};
      if (!$maxcnt) {
          return qq{aiRawData values cache is empty.};
      }

      $sq = "<b>Number of datasets:</b> ".$maxcnt."\n";

      for my $idx (sort keys %{$h}) {
          my $hod   = AiRawdataVal ($hash, $idx, 'hod',   '-');
          my $rad1h = AiRawdataVal ($hash, $idx, 'rad1h', '-');
          my $wcc   = AiRawdataVal ($hash, $idx, 'wcc',   '-');
          my $wrp   = AiRawdataVal ($hash, $idx, 'wrp',   '-');
          my $pvrl  = AiRawdataVal ($hash, $idx, 'pvrl',  '-');
          my $temp  = AiRawdataVal ($hash, $idx, 'temp',  '-');
          $sq      .= "\n";
          $sq      .= "$idx => hod: $hod, rad1h: $rad1h, wcc: $wcc, wrp: $wrp, pvrl: $pvrl, temp: $temp";
      }
  }

return $sq;
}

################################################################
#  Berechnung führende Spaces für Hashanzeige
#  $str - String dessen Länge für die Anzahl Spaces
#         herangezogen wird
#  $sp  - vorhandener Space-String der erweitert wird
################################################################
sub _ldpspaces {
  my $str   = shift;
  my $sp    = shift // q{};
  my $const = shift // 4;

  my $le  = $const + length $str;
  my $spn = $sp;

  for (my $i = 0; $i < $le; $i++) {
      $spn .= " ";
  }

return $spn;
}

################################################################
#        validiert die aktuelle Anlagenkonfiguration
################################################################
sub checkPlantConfig {
  my $hash = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my $lang        = AttrVal        ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang));
  my $pcf         = ReadingsVal    ($name, 'pvCorrectionFactor_Auto', '');
  my $raname      = ReadingsVal    ($name, 'currentRadiationAPI',     '');
  my ($acu, $aln) = isAutoCorrUsed ($name);

  my $cf     = 0;                                                                                     # config fault: 1 -> Konfig fehlerhaft, 0 -> Konfig ok
  my $wn     = 0;                                                                                     # Warnung wenn 1
  my $io     = 0;                                                                                     # Info wenn 1

  my $ok     = FW_makeImage ('10px-kreis-gruen.png',     '');
  my $nok    = FW_makeImage ('10px-kreis-rot.png',       '');
  my $warn   = FW_makeImage ('message_attention@orange', '');
  my $info   = FW_makeImage ('message_info',             '');

  my $result = {                                                                                    # Ergebnishash
      'String Configuration'     => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
      'DWD Weather Attributes'   => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
      'Common Settings'          => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
      'FTUI Widget Files'        => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
  };

  my $sub = sub {
      my $string = shift;
      my $ret;

      for my $key (sort keys %{$data{$type}{$name}{strings}{$string}}) {
          $ret    .= ", " if($ret);
          $ret    .= $key.": ".$data{$type}{$name}{strings}{$string}{$key};
      }

      return $ret;
  };

  ## Check Strings
  ##################

  my $err = createStringConfig ($hash);

  if ($err) {
      $result->{'String Configuration'}{state}  = $nok;
      $result->{'String Configuration'}{result} = $err;
      $result->{'String Configuration'}{fault}  = 1;
  }

  for my $sn (sort keys %{$data{$type}{$name}{strings}}) {
      my $sp = $sn." => ".$sub->($sn)."<br>";
      $result->{'String Configuration'}{note} .= $sn." => ".$sub->($sn)."<br>";

      if ($data{$type}{$name}{strings}{$sn}{peak} >= 500) {
          $result->{'String Configuration'}{result} .= qq{The peak value of string "$sn" is very high. };
          $result->{'String Configuration'}{result} .= qq{It seems to be given in Wp instead of kWp. <br>};
          $result->{'String Configuration'}{state}   = $warn;
          $result->{'String Configuration'}{warn}    = 1;
      }

      if (!isSolCastUsed ($hash) && !isVictronKiUsed ($hash)) {
          if ($sp !~ /dir.*?peak.*?tilt/x) {
              $result->{'String Configuration'}{state}  = $nok;
              $result->{'String Configuration'}{fault}  = 1;                                    # Test Vollständigkeit: z.B. Süddach => dir: S, peak: 5.13, tilt: 45
          }
      }
      elsif (isVictronKiUsed ($hash)) {
          if($sp !~ /KI-based\s=>\speak/xs) {
              $result->{'String Configuration'}{state}  = $nok;
              $result->{'String Configuration'}{fault}  = 1;
          }
      }
      else {                                                                                    # Strahlungsdevice SolCast-API
          if($sp !~ /peak.*?pk/x) {
              $result->{'String Configuration'}{state}  = $nok;
              $result->{'String Configuration'}{fault}  = 1;                                    # Test Vollständigkeit
          }
      }
  }

  $result->{'String Configuration'}{result} = $hqtxt{fulfd}{$lang} if(!$result->{'String Configuration'}{fault} && !$result->{'String Configuration'}{warn});

  ## Check Attribute DWD Wetterdevice
  #####################################
  my $fcname = ReadingsVal ($name, 'currentWeatherDev', '');

  if (!$fcname || !$defs{$fcname}) {
      $result->{'DWD Weather Attributes'}{state}   = $nok;
      $result->{'DWD Weather Attributes'}{result} .= qq{The DWD device "$fcname" doesn't exist. <br>};
      $result->{'DWD Weather Attributes'}{fault}   = 1;
  }
  else {
      $result->{'DWD Weather Attributes'}{note} = qq{checked attributes of device "$fcname": <br>}. join ' ', @dweattrmust;
      $err                                      = checkdwdattr ($name, $fcname, \@dweattrmust);

      if ($err) {
          $result->{'DWD Weather Attributes'}{state}  = $nok;
          $result->{'DWD Weather Attributes'}{result} = $err;
          $result->{'DWD Weather Attributes'}{fault}  = 1;
      }
      else {
          $result->{'DWD Weather Attributes'}{result} = $hqtxt{fulfd}{$lang};
      }
  }

  ## Check Attribute DWD Radiation Device
  #########################################
  if (isDWDUsed ($hash)) {
      $result->{'DWD Radiation Attributes'}{state}  = $ok;
      $result->{'DWD Radiation Attributes'}{result} = '';
      $result->{'DWD Radiation Attributes'}{note}   = '';
      $result->{'DWD Radiation Attributes'}{fault}  = 0;

      if (!$raname || !$defs{$raname}) {
          $result->{'DWD Radiation Attributes'}{state}   = $nok;
          $result->{'DWD Radiation Attributes'}{result} .= qq{The DWD device "$raname" doesn't exist <br>};
          $result->{'DWD Radiation Attributes'}{fault}   = 1;
      }
      else {
          $result->{'DWD Radiation Attributes'}{note} .= qq{checked attributes of device "$raname": <br>}. join ' ', @draattrmust;
          $err                                         = checkdwdattr ($name, $raname, \@draattrmust);

          if ($err) {
              $result->{'DWD Radiation Attributes'}{state}  = $nok;
              $result->{'DWD Radiation Attributes'}{result} = $err;
              $result->{'DWD Radiation Attributes'}{fault}  = 1;
          }
          else {
              $result->{'DWD Radiation Attributes'}{result} = $hqtxt{fulfd}{$lang};
          }
      }
  }

  ## Check Rooftop und Roof Ident Pair Settings (SolCast)
  #########################################################
  if (isSolCastUsed ($hash)) {
      $result->{'Roof Ident Pair Settings'}{state}  = $ok;
      $result->{'Roof Ident Pair Settings'}{result} = '';
      $result->{'Roof Ident Pair Settings'}{note}   = '';
      $result->{'Roof Ident Pair Settings'}{fault}  = 0;

      $result->{'Rooftop Settings'}{state}          = $ok;
      $result->{'Rooftop Settings'}{result}         = '';
      $result->{'Rooftop Settings'}{note}           = '';
      $result->{'Rooftop Settings'}{fault}          = 0;

      my $rft = ReadingsVal($name, 'moduleRoofTops', '');

      if (!$rft) {
          $result->{'Rooftop Settings'}{state}   = $nok;
          $result->{'Rooftop Settings'}{result} .= qq{No RoofTops are defined <br>};
          $result->{'Rooftop Settings'}{note}   .= qq{Set your Rooftops with "set $name moduleRoofTops" command. <br>};
          $result->{'Rooftop Settings'}{fault}   = 1;

          $result->{'Roof Ident Pair Settings'}{state}   = $nok;
          $result->{'Roof Ident Pair Settings'}{result} .= qq{Setting the Rooftops is a necessary preparation for the definition of Roof Ident Pairs<br>};
          $result->{'Roof Ident Pair Settings'}{note}   .= qq{See the "Rooftop Settings" section below. <br>};
          $result->{'Roof Ident Pair Settings'}{fault}   = 1;
      }
      else {
          $result->{'Rooftop Settings'}{result} .= $hqtxt{fulfd}{$lang};
          $result->{'Rooftop Settings'}{note}   .= qq{Rooftops defined: }.$rft.qq{<br>};
      }

      my ($a,$h) = parseParams ($rft);

      while (my ($is, $pk) = each %$h) {
          my $rtid   = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'rtid',   '');
          my $apikey = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'apikey', '');

          if(!$rtid || !$apikey) {
              my $res  = qq{String "$is" has no Roof Ident Pair "$pk" defined or has no Rooftop-ID and/or SolCast-API key assigned. <br>};
              my $note = qq{Set the Roof Ident Pair "$pk" with "set $name roofIdentPair". <br>};

              $result->{'Roof Ident Pair Settings'}{state}   = $nok;
              $result->{'Roof Ident Pair Settings'}{result} .= $res;
              $result->{'Roof Ident Pair Settings'}{note}   .= $note;
              $result->{'Roof Ident Pair Settings'}{fault}   = 1;
          }
          else {
              $result->{'Roof Ident Pair Settings'}{result}  = $hqtxt{fulfd}{$lang} if(!$result->{'Roof Ident Pair Settings'}{fault});
              $result->{'Roof Ident Pair Settings'}{note}   .= qq{checked "$is" Roof Ident Pair "$pk":<br>rtid=$rtid, apikey=$apikey <br>};
          }
      }
  }

  ## Allgemeine Settings
  ########################
  my $eocr               = AttrVal       ($name, 'event-on-change-reading', '');
  my $aiprep             = isPrepared4AI ($hash, 'full');
  my $aiusemsg           = CurrentVal    ($hash, 'aicanuse', '');
  my ($cset, $lat, $lon) = locCoordinates();
  my $einstds            = "";

  if (!$eocr || $eocr ne '.*') {
      $einstds                              = 'to .*' if($eocr ne '.*');
      $result->{'Common Settings'}{state}   = $info;
      $result->{'Common Settings'}{result} .= qq{Attribute 'event-on-change-reading' is not set $einstds. <br>};
      $result->{'Common Settings'}{note}   .= qq{Setting attribute 'event-on-change-reading = .*' is recommended to improve the runtime performance.<br>};
      $result->{'Common Settings'}{info}    = 1;
  }

  if ($lang ne 'DE') {
      $result->{'Common Settings'}{state}   = $info;
      $result->{'Common Settings'}{result} .= qq{The language is set to '$lang'. <br>};
      $result->{'Common Settings'}{note}   .= qq{If the local attribute "ctrlLanguage" or the global attribute "language" is changed to "DE" most of the outputs are in German.<br>};
      $result->{'Common Settings'}{info}    = 1;
  }

  if (!$lat) {
      $result->{'Common Settings'}{state}   = $warn;
      $result->{'Common Settings'}{result} .= qq{Attribute latitude in global device is not set. <br>};
      $result->{'Common Settings'}{note}   .= qq{Set the coordinates of your installation in the latitude attribute of the global device.<br>};
      $result->{'Common Settings'}{warn}    = 1;
  }

  if (!$lon) {
      $result->{'Common Settings'}{state}   = $warn;
      $result->{'Common Settings'}{result} .= qq{Attribute longitude in global device is not set. <br>};
      $result->{'Common Settings'}{note}   .= qq{Set the coordinates of your installation in the longitude attribute of the global device.<br>};
      $result->{'Common Settings'}{warn}    = 1;
  }

  if (!$aiprep) {
      $result->{'Common Settings'}{state}   = $info;
      $result->{'Common Settings'}{result} .= qq{The AI support is not used. <br>};
      $result->{'Common Settings'}{note}   .= qq{$aiusemsg.<br>};
      $result->{'Common Settings'}{info}    = 1;
  }

  my ($cmerr, $cmupd, $cmmsg, $cmrec) = checkModVer ($name, '76_SolarForecast', 'https://fhem.de/fhemupdate/controls_fhem.txt');

  if (!$cmerr && !$cmupd) {
      $result->{'Common Settings'}{note}   .= qq{$cmmsg<br>};
      $result->{'Common Settings'}{note}   .= qq{checked module: <br>};
      $result->{'Common Settings'}{note}   .= qq{76_SolarForecast <br>};
  }

  if ($cmerr) {
      $result->{'Common Settings'}{state}   = $warn;
      $result->{'Common Settings'}{result} .= qq{$cmmsg <br>};
      $result->{'Common Settings'}{note}   .= qq{$cmrec <br>};
      $result->{'Common Settings'}{warn}    = 1;
  }

  if ($cmupd) {
      $result->{'Common Settings'}{state}   = $warn;
      $result->{'Common Settings'}{result} .= qq{$cmmsg <br>};
      $result->{'Common Settings'}{note}   .= qq{$cmrec <br>};
      $result->{'Common Settings'}{warn}    = 1;
  }

  ## allg. Settings bei Nutzung Forecast.Solar API
  #################################################
  if (isForecastSolarUsed ($hash)) {
      if (!$pcf || $pcf !~ /on/xs) {
          $result->{'Common Settings'}{state}   = $info;
          $result->{'Common Settings'}{result} .= qq{pvCorrectionFactor_Auto is set to "$pcf" <br>};
          $result->{'Common Settings'}{note}   .= qq{Set pvCorrectionFactor_Auto to "on*" if an automatic adjustment of the prescaler data should be done.<br>};
      }

      if (!$lat) {
          $result->{'Common Settings'}{state}   = $nok;
          $result->{'Common Settings'}{result} .= qq{Attribute latitude in global device is not set. <br>};
          $result->{'Common Settings'}{note}   .= qq{Set the coordinates of your installation in the latitude attribute of the global device.<br>};
          $result->{'Common Settings'}{fault}   = 1;
      }

      if (!$lon) {
          $result->{'Common Settings'}{state}   = $nok;
          $result->{'Common Settings'}{result} .= qq{Attribute longitude in global device is not set. <br>};
          $result->{'Common Settings'}{note}   .= qq{Set the coordinates of your installation in the longitude attribute of the global device.<br>};
          $result->{'Common Settings'}{fault}   = 1;
      }

      if (!$result->{'Common Settings'}{fault} && !$result->{'Common Settings'}{warn} && !$result->{'Common Settings'}{info}) {
          $result->{'Common Settings'}{result}  = $hqtxt{fulfd}{$lang};
          $result->{'Common Settings'}{note}   .= qq{checked parameters: <br>};
          $result->{'Common Settings'}{note}   .= qq{global latitude, global longitude <br>};
          $result->{'Common Settings'}{note}   .= qq{pvCorrectionFactor_Auto <br>};
      }
  }

  ## allg. Settings bei Nutzung SolCast
  #######################################
  if (isSolCastUsed ($hash)) {
      my $gdn = AttrVal     ('global', 'dnsServer',                '');
      my $osi = AttrVal     ($name,    'ctrlSolCastAPIoptimizeReq', 0);

      my $lam = SolCastAPIVal ($hash, '?All', '?All', 'response_message', 'success');

      if (!$pcf || $pcf !~ /on/xs) {
          $result->{'Common Settings'}{state}   = $info;
          $result->{'Common Settings'}{result} .= qq{pvCorrectionFactor_Auto is set to "$pcf" <br>};
          $result->{'Common Settings'}{note}   .= qq{set pvCorrectionFactor_Auto to "on*" is recommended if the SolCast efficiency factor is already adjusted.<br>};
      }

      if (!$osi) {
          $result->{'Common Settings'}{state}   = $warn;
          $result->{'Common Settings'}{result} .= qq{Attribute ctrlSolCastAPIoptimizeReq is set to "$osi" <br>};
          $result->{'Common Settings'}{note}   .= qq{set ctrlSolCastAPIoptimizeReq to "1" is recommended.<br>};
          $result->{'Common Settings'}{warn}    = 1;
      }

      if ($lam =~ /You have exceeded your free daily limit/i) {
          $result->{'API Access'}{state}        = $warn;
          $result->{'API Access'}{result}      .= qq{The last message from SolCast API is:<br>"$lam"<br>};
          $result->{'API Access'}{note}        .= qq{Wait until the next day when the limit resets.<br>};
          $result->{'API Access'}{warn}         = 1;
      }
      elsif ($lam ne 'success') {
          $result->{'API Access'}{state}        = $nok;
          $result->{'API Access'}{result}      .= qq{The last message from SolCast API is:<br>"$lam"<br>};
          $result->{'API Access'}{note}        .= qq{Check the validity of your API key and Rooftop identificators.<br>};
          $result->{'API Access'}{fault}        = 1;
      }

      if (!$gdn) {
          $result->{'API Access'}{state}        = $nok;
          $result->{'API Access'}{result}      .= qq{Attribute dnsServer in global device is not set. <br>};
          $result->{'API Access'}{note}        .= qq{set global attribute dnsServer to the IP Adresse of your DNS Server.<br>};
          $result->{'API Access'}{fault}        = 1;
      }

      if (!$result->{'Common Settings'}{fault} && !$result->{'Common Settings'}{warn} && !$result->{'Common Settings'}{info}) {
          $result->{'Common Settings'}{result}  = $hqtxt{fulfd}{$lang};
          $result->{'Common Settings'}{note}   .= qq{checked parameters: <br>};
          $result->{'Common Settings'}{note}   .= qq{ctrlSolCastAPIoptimizeReq <br>};
          $result->{'Common Settings'}{note}   .= qq{pvCorrectionFactor_Auto, event-on-change-reading, ctrlLanguage, global language, global dnsServer <br>};
      }
  }

  ## allg. Settings bei Nutzung DWD API
  #######################################
  if (isDWDUsed ($hash)) {
      my $lam = SolCastAPIVal ($hash, '?All', '?All', 'response_message', 'success');

      if ($aidtabs) {
          $result->{'Common Settings'}{state}   = $info;
          $result->{'Common Settings'}{result} .= qq{The Perl module AI::DecisionTree is missing. <br>};
          $result->{'Common Settings'}{note}   .= qq{If you want use AI support, please install it with e.g. "sudo apt-get install libai-decisiontree-perl".<br>};
          $result->{'Common Settings'}{info}    = 1;
      }

      if (!$pcf || $pcf !~ /on/xs) {
          $result->{'Common Settings'}{state}   = $info;
          $result->{'Common Settings'}{result} .= qq{pvCorrectionFactor_Auto is set to "$pcf" <br>};
          $result->{'Common Settings'}{note}   .= qq{Set pvCorrectionFactor_Auto to "on*" if an automatic adjustment of the prescaler data should be done.<br>};
      }

      if ($lam ne 'success') {
          $result->{'API Access'}{state}        = $nok;
          $result->{'API Access'}{result}      .= qq{DWD last message:<br>"$lam"<br>};
          $result->{'API Access'}{note}        .= qq{Check the setup of the device "$raname". <br>};
          $result->{'API Access'}{note}        .= qq{It is possible that not all readings are transmitted when "$raname" is newly set up. <br>};
          $result->{'API Access'}{note}        .= qq{In this case, wait until tomorrow and check again.<br>};
          $result->{'API Access'}{fault}        = 1;
      }

      if (!$result->{'Common Settings'}{fault} && !$result->{'Common Settings'}{warn} && !$result->{'Common Settings'}{info}) {
          $result->{'Common Settings'}{result}  = $hqtxt{fulfd}{$lang};
          $result->{'Common Settings'}{note}   .= qq{checked parameters: <br>};
          $result->{'Common Settings'}{note}   .= qq{pvCorrectionFactor_Auto, event-on-change-reading, ctrlLanguage, global language <br>};
          $result->{'Common Settings'}{note}   .= qq{checked Perl modules: <br>};
          $result->{'Common Settings'}{note}   .= qq{AI::DecisionTree <br>};
      }
  }

  ## allg. Settings bei Nutzung VictronKI-API
  #############################################
  if (isVictronKiUsed ($hash)) {
      my $gdn   = AttrVal       ('global', 'dnsServer', '');
      my $vrmcr = SolCastAPIVal ($hash, '?VRM', '?API', 'credentials', '');                   # Victron VRM Credentials gesetzt

      if ($pcf && $pcf !~ /off/xs) {
          $result->{'Common Settings'}{state}   = $warn;
          $result->{'Common Settings'}{result} .= qq{pvCorrectionFactor_Auto is set to "$pcf" <br>};
          $result->{'Common Settings'}{note}   .= qq{set pvCorrectionFactor_Auto to "off" is recommended because of this API is KI based.<br>};
          $result->{'Common Settings'}{warn}    = 1;
      }

      if (!$vrmcr) {
          $result->{'API Access'}{state}        = $nok;
          $result->{'API Access'}{result}      .= qq{The Victron VRM Portal credentials are not set. <br>};
          $result->{'API Access'}{note}        .= qq{set the credentials with command "set $name vrmCredentials".<br>};
          $result->{'API Access'}{fault}        = 1;
      }

      if (!$gdn) {
          $result->{'API Access'}{state}        = $nok;
          $result->{'API Access'}{result}      .= qq{Attribute dnsServer in global device is not set. <br>};
          $result->{'API Access'}{note}        .= qq{set global attribute dnsServer to the IP Adresse of your DNS Server.<br>};
          $result->{'API Access'}{fault}        = 1;
      }

      if (!$result->{'Common Settings'}{fault} && !$result->{'Common Settings'}{warn} && !$result->{'Common Settings'}{info}) {
          $result->{'Common Settings'}{result}  = $hqtxt{fulfd}{$lang};
          $result->{'Common Settings'}{note}   .= qq{checked parameters: <br>};
          $result->{'Common Settings'}{note}   .= qq{global dnsServer, global language <br>};
          $result->{'Common Settings'}{note}   .= qq{pvCorrectionFactor_Auto, vrmCredentials, event-on-change-reading, ctrlLanguage <br>};
      }
  }

  ## FTUI Widget Support
  ########################
  my $tpath = "$root/www/tablet/css";
  my $upd   = 0;
  $err      = 0;

  if (!-d $tpath) {
      $result->{'FTUI Widget Files'}{result}  .= $hqtxt{widnin}{$lang};
      $result->{'FTUI Widget Files'}{note}    .= qq{There is no need to install SolarForecast FTUI widgets.<br>};
  }
  else {
      my $cfurl = $bPath.$cfile.$pPath;

      for my $file (@fs) {
          ($cmerr, $cmupd, $cmmsg, $cmrec) = checkModVer ($name, $file, $cfurl);

          $err = 1 if($cmerr);
          $upd = 1 if($cmupd);
      }

      if ($err) {
          $result->{'FTUI Widget Files'}{state}   = $warn;
          $result->{'FTUI Widget Files'}{result} .= $hqtxt{widerr}{$lang}.'<br>';
          $result->{'FTUI Widget Files'}{result} .= $cmmsg.'<br>';
          $result->{'FTUI Widget Files'}{note}   .= qq{Update the FHEM Tablet UI Widget Files with the command:  <br>};
          $result->{'FTUI Widget Files'}{note}   .= qq{"get $name ftuiFramefiles".  <br>};
          $result->{'FTUI Widget Files'}{note}   .= qq{After that do the test again. If the error is permanent, please inform the maintainer.<br>};
          $result->{'FTUI Widget Files'}{warn}    = 1;

          $upd = 0;
      }

      if ($upd) {
          $result->{'FTUI Widget Files'}{state}   = $warn;
          $result->{'FTUI Widget Files'}{result} .= $hqtxt{widnup}{$lang};
          $result->{'FTUI Widget Files'}{note}   .= qq{Update the FHEM Tablet UI Widget Files with the command:  <br>};
          $result->{'FTUI Widget Files'}{note}   .= qq{"get $name ftuiFramefiles".  <br>};
          $result->{'FTUI Widget Files'}{warn}    = 1;
      }

      if (!$result->{'FTUI Widget Files'}{fault} && !$result->{'FTUI Widget Files'}{warn} && !$result->{'FTUI Widget Files'}{info}) {
          $result->{'FTUI Widget Files'}{result}  .= $hqtxt{widok}{$lang};
          $result->{'FTUI Widget Files'}{note}    .= qq{checked Files: <br>};
          $result->{'FTUI Widget Files'}{note}    .= (join ', ', @fs).qq{ <br>};
      }
  }

  ## Ausgabe
  ############
  my $out  = qq{<html>};
  $out    .= qq{<b>}.$hqtxt{plntck}{$lang}.qq{</b> <br><br>};

  $out    .= qq{<table class="roomoverview" style="text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;">};
  $out    .= qq{<tr style="font-weight:bold;">};
  $out    .= qq{<td style="text-decoration:underline; padding: 5px;"> $hqtxt{object}{$lang} </td>};
  $out    .= qq{<td style="text-decoration:underline;"> $hqtxt{state}{$lang} </td>};
  $out    .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>};
  $out    .= qq{<td style="text-decoration:underline;"> $hqtxt{result}{$lang} </td>};
  $out    .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>};
  $out    .= qq{<td style="text-decoration:underline;"> $hqtxt{note}{$lang} </td>};
  $out    .= qq{</tr>};
  $out    .= qq{<tr></tr>};

  my $hz = keys %{$result};
  my $hc = 0;

  for my $key (sort keys %{$result}) {
      $hc++;
      $cf   = $result->{$key}{fault} if($result->{$key}{fault});
      $wn   = $result->{$key}{warn}  if($result->{$key}{warn});
      $io   = $result->{$key}{info}  if($result->{$key}{info});
      $out .= qq{<tr>};
      $out .= qq{<td style="padding: 5px; white-space:nowrap;"> <b>$key</b>              </td>};
      $out .= qq{<td style="padding: 5px; text-align: center"> $result->{$key}{state}    </td>};
      $out .= qq{<td style="padding: 5px;"> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;               </td>};
      $out .= qq{<td style="padding: 0px;"> $result->{$key}{result}                      </td>};
      $out .= qq{<td style="padding: 0px;"> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;               </td>};
      $out .= qq{<td style="padding-right: 5px; text-align: left"> $result->{$key}{note} </td>};
      $out .= qq{</tr>};

      #if ($hc < $hz) {                                # Tabelle wird auf Tablet zu groß mit Zwischenzeilen
      #    $out .= qq{<tr>};
      #    $out .= qq{<td> &nbsp; </td>};
      #    $out .= qq{</tr>};
      #}

      $out .= qq{<tr></tr>};
  }

  $out .= qq{</table>};
  $out .= qq{</html>};

  $out .= "<br>";

  if($cf) {
      $out .= encode ("utf8", $hqtxt{strnok}{$lang});
  }
  elsif ($wn) {
      $out .= encode ("utf8", $hqtxt{strwn}{$lang});
  }
  else {
      $out .= encode ("utf8", $hqtxt{strok}{$lang});
  }

  $out =~ s/ (Bitte eventuelle Hinweise|Please note any information).*// if(!$io);
  $out =~ s/<I>/$info/gx;
  $out =~ s/<W>/$warn/gx;

return $out;
}

################################################################
#  Array auf eine festgelegte Anzahl Elemente beschränken,
#  Das älteste Element wird entfernt
#
#  $href  = Referenz zum Array
#  $limit = die Anzahl Elemente auf die gekürzt werden soll
#           (default 3)
#
################################################################
sub limitArray {
  my $href  = shift;
  my $limit = shift // 3;

  return if(ref $href ne "ARRAY");

  while (scalar @{$href} > $limit) {
      shift @{$href};
  }

return;
}

################################################################
#              Timestrings berechnen
#  gibt Zeitstring in lokaler Zeit zurück
################################################################
sub timestampToTimestring {
  my $epoch = shift;
  my $lang  = shift // '';

  return if($epoch !~ /[0-9]/xs);

  if (length ($epoch) == 13) {                                                                     # Millisekunden
      $epoch = $epoch / 1000;
  }

  my ($lyear,$lmonth,$lday,$lhour,$lmin,$lsec) = (localtime($epoch))[5,4,3,2,1,0];
  my $tm;

  $lyear += 1900;                                                                                  # year is 1900 based
  $lmonth++;                                                                                       # month number is zero based

  my ($sec,$min,$hour,$day,$mon,$year) = (localtime(time))[0,1,2,3,4,5];                           # Standard f. z.B. Readingstimstamp
  $year += 1900;
  $mon++;

  my $realtm = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year,$mon,$day,$hour,$min,$sec);          # engl. Variante von aktuellen timestamp
  my $tmdef  = sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,"00:00");             # engl. Variante von $epoch für Logging-Timestamps etc. (Minute/Sekunde == 00)
  my $tmfull = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $lyear,$lmonth,$lday,$lhour,$lmin,$lsec);  # engl. Variante Vollzeit von $epoch

  if($lang eq "DE") {
      $tm = sprintf("%02d.%02d.%04d %02d:%02d:%02d", $lday,$lmonth,$lyear,$lhour,$lmin,$lsec);     # deutsche Variante Vollzeit von $epoch
  }
  else {
      $tm = $tmfull;
  }

return ($tm, $tmdef, $realtm, $tmfull);
}

################################################################
#  einen Zeitstring YYYY-MM-TT hh:mm:ss in einen Unix
#  Timestamp umwandeln
################################################################
sub timestringToTimestamp {
  my $tstring = shift;

  my($y, $mo, $d, $h, $m, $s) = $tstring =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})\s([0-9]{2}):([0-9]{2}):([0-9]{2})/xs;
  return if(!$mo || !$y);

  my $timestamp = fhemTimeLocal($s, $m, $h, $d, $mo-1, $y-1900);

return $timestamp;
}

################################################################
#  einen Zeitstring YYYY-MM-TT hh:mm:ss in einen Unix
#  Timestamp GMT umwandeln
################################################################
sub timestringToTimestampGMT {
  my $tstring = shift;

  my($y, $mo, $d, $h, $m, $s) = $tstring =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})\s([0-9]{2}):([0-9]{2}):([0-9]{2})/xs;
  return if(!$mo || !$y);

  my $tsgm = fhemTimeGm ($s, $m, $h, $d, $mo-1, $y-1900);

return $tsgm;
}

################################################################
#  Zeitstring der Form 2023-05-27T14:24:30+02:00 formatieren
#  in YYYY-MM-TT hh:mm:ss
################################################################
sub timestringFormat {
  my $tstring = shift;

  return if(!$tstring);

  $tstring = (split '\+', $tstring)[0];
  $tstring =~ s/T/ /g;

return $tstring;
}

################################################################
# Speichern Readings, Wert, Zeit in zentralen Readings Store
################################################################
sub storeReading {
  my $rdg = shift;
  my $val = shift;
  my $ts1 = shift;

  my $cmps = $rdg.'<>'.$val;
  $cmps   .= '<>'.$ts1 if(defined $ts1);

  push @da, $cmps;

return;
}

################################################################
#             Readings aus Array erstellen
# $doevt:  1-Events erstellen, 0-keine Events erstellen
#
# readingsBulkUpdate($hash,$reading,$value,$changed,$timestamp)
#
################################################################
sub createReadingsFromArray {
  my $hash  = shift;
  my $doevt = shift // 0;

  return if(!scalar @da);

  readingsBeginUpdate ($hash);

  for my $elem (@da) {
      my ($rn,$rval,$ts) = split "<>", $elem, 3;

      readingsBulkUpdate ($hash, $rn, $rval, undef, $ts);
  }

  readingsEndUpdate ($hash, $doevt);

  undef @da;

return;
}

################################################################
#        "state" updaten
################################################################
sub singleUpdateState {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $val   = $paref->{state} // 'unknown';
  my $evt   = $paref->{evt}   // 0;

  readingsSingleUpdate ($hash, 'state', $val, $evt);

return;
}

################################################################
#  erstellt einen Debug-Eintrag im Log
################################################################
sub debugLog {
  my $paref = shift;
  my $dreg  = shift;                       # Regex zum Vergleich
  my $dmsg  = shift;                       # auszugebender Meldungstext

  my $name  = $paref->{name};
  my $debug = $paref->{debug};

  if ($debug =~ /$dreg/x) {
      Log3 ($name, 1, "$name DEBUG> $dmsg");
  }

return;
}

################################################################
#    alle Readings eines Devices oder nur Reading-Regex
#    löschen
################################################################
sub deleteReadingspec {
  my $hash = shift;
  my $spec = shift // ".*";

  my $readingspec = '^'.$spec.'$';

  for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
      readingsDelete ($hash, $reading);
  }

return;
}

######################################################################################
#     NOTIFYDEV und "Probably associated with" erstellen
######################################################################################
sub createAssociatedWith {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  RemoveInternalTimer($hash, "FHEM::SolarForecast::createAssociatedWith");

  if ($init_done) {
      my (@cd,@nd);
      my ($afc,$ara,$ain,$ame,$aba,$h);

      my $fcdev = ReadingsVal($name, 'currentWeatherDev',   '');             # Weather forecast Device
      ($afc,$h) = parseParams ($fcdev);
      $fcdev    = $afc->[0] // "";

      my $radev = ReadingsVal($name, 'currentRadiationAPI', '');             # Radiation forecast Device
      ($ara,$h) = parseParams ($radev);
      $radev    = $ara->[0] // "";

      my $indev = ReadingsVal($name, 'currentInverterDev',  '');             # Inverter Device
      ($ain,$h) = parseParams ($indev);
      $indev    = $ain->[0] // "";

      my $medev = ReadingsVal($name, 'currentMeterDev',     '');             # Meter Device
      ($ame,$h) = parseParams ($medev);
      $medev    = $ame->[0] // "";

      my $badev = ReadingsVal($name, 'currentBatteryDev',   '');             # Battery Device
      ($aba,$h) = parseParams ($badev);
      $badev    = $aba->[0] // "";

      for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {     # Consumer Devices
          my $consumer = AttrVal($name, "consumer${c}", "");
          my ($ac,$hc) = parseParams ($consumer);
          my $codev    = $ac->[0] // '';

          push @cd, $codev if($codev);

          my $dswitch = $hc->{switchdev} // '';                              # alternatives Schaltdevice

          push @cd, $dswitch if($dswitch);
      }

      @nd = @cd;

      push @nd, $fcdev;
      push @nd, $radev if($radev ne $fcdev && $radev !~ /SolCast-API/xs);
      push @nd, $indev;
      push @nd, $medev;
      push @nd, $badev;

      if(@nd) {
          $hash->{NOTIFYDEV} = join ",", @cd if(@cd);
          readingsSingleUpdate ($hash, ".associatedWith", join(" ",@nd), 0);
      }
  }
  else {
      InternalTimer(gettimeofday()+3, "FHEM::SolarForecast::createAssociatedWith", $hash, 0);
  }

return;
}

################################################################
#   Planungsdaten Consumer löschen
#   $c - Consumer Nummer
################################################################
sub deleteConsumerPlanning {
  my $hash = shift;
  my $c    = shift;

  my $type   = $hash->{TYPE};
  my $name   = $hash->{NAME};
  my $calias = ConsumerVal ($hash, $c, "alias", "");

  delete $data{$type}{$name}{consumers}{$c}{planstate};
  delete $data{$type}{$name}{consumers}{$c}{planSupplement};
  delete $data{$type}{$name}{consumers}{$c}{planswitchon};
  delete $data{$type}{$name}{consumers}{$c}{planswitchoff};
  delete $data{$type}{$name}{consumers}{$c}{plandelete};
  delete $data{$type}{$name}{consumers}{$c}{ehodpieces};

  deleteReadingspec ($hash, "consumer${c}.*");

  Log3($name, 3, qq{$name - Consumer planning of "$calias" deleted});

return;
}

################################################################
#  Internal MODEL und Model abhängige Setzungen / Löschungen
################################################################
sub setModel {
  my $hash = shift;

  my $api = ReadingsVal ($hash->{NAME}, 'currentRadiationAPI', 'DWD');

  if ($api =~ /SolCast/xs) {
      $hash->{MODEL} = 'SolCastAPI';
  }
  elsif ($api =~ /ForecastSolar/xs) {
      $hash->{MODEL} = 'ForecastSolarAPI';
  }
  elsif ($api =~ /VictronKI/xs) {
      $hash->{MODEL} = 'VictronKiAPI';
  }
  else {
      $hash->{MODEL} = 'DWD';
      deleteReadingspec ($hash, 'nextSolCastCall');
  }

return;
}

################################################################
#  Laufzeit Ergebnis erfassen und speichern
################################################################
sub setTimeTracking {
  my $hash = shift;
  my $st   = shift;                  # Startzeitstempel
  my $tkn  = shift;                  # Name des Zeitschlüssels

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  $data{$type}{$name}{current}{$tkn} = sprintf "%.4f", tv_interval($st);

return;
}

################################################################
#  Voraussetzungen zur Nutzung der KI prüfen, Status setzen
#  und Prüfungsergebnis (0/1) zurückgeben
################################################################
sub isPrepared4AI {
  my $hash = shift;
  my $full = shift // q{};                   # wenn true -> auch Auswertung ob on_.*_ai gesetzt ist

  my $name        = $hash->{NAME};
  my $type        = $hash->{TYPE};
  my ($acu, $aln) = isAutoCorrUsed ($name);

  my $err;

  if(!isDWDUsed ($hash)) {
      $err = qq(The selected SolarForecast model cannot use AI support);
  }
  elsif ($aidtabs) {
      $err = qq(The Perl module AI::DecisionTree is missing. Please install it with e.g. "sudo apt-get install libai-decisiontree-perl" for AI support);
  }
  elsif ($full && $acu !~ /ai/xs) {
      $err = 'The setting of pvCorrectionFactor_Auto does not contain AI support';
  }

  if ($err) {
      $data{$type}{$name}{current}{aicanuse} = $err;
      return 0;
  }

  $data{$type}{$name}{current}{aicanuse} = 'ok';

return 1;
}

################################################################
#  Funktion liefert 1 wenn Consumer physisch "eingeschaltet"
#  ist, d.h. der Wert onreg des Readings rswstate wahr ist
################################################################
sub isConsumerPhysOn {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};

my ($cname, $dswname) = getCDnames ($hash, $c);                          # Consumer und Switch Device Name

  if(!$defs{$dswname}) {
      Log3($name, 1, qq{$name - ERROR - the device "$dswname" is invalid. Please check device names in consumer "$c" attribute});
      return 0;
  }

  my $reg      = ConsumerVal ($hash, $c, 'onreg',       'on');
  my $rswstate = ConsumerVal ($hash, $c, 'rswstate', 'state');           # Reading mit Schaltstatus
  my $swstate  = ReadingsVal ($dswname, $rswstate,   'undef');

  if ($swstate =~ m/^$reg$/x) {
      return 1;
  }

return 0;
}

################################################################
#  Funktion liefert 1 wenn Consumer physisch "ausgeschaltet"
#  ist, d.h. der Wert offreg des Readings rswstate wahr ist
################################################################
sub isConsumerPhysOff {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};

  my ($cname, $dswname) = getCDnames ($hash, $c);                        # Consumer und Switch Device Name

  if(!$defs{$dswname}) {
      Log3($name, 1, qq{$name - ERROR - the device "$dswname" is invalid. Please check device names in consumer "$c" attribute});
      return 0;
  }

  my $reg      = ConsumerVal ($hash, $c, 'offreg',     'off');
  my $rswstate = ConsumerVal ($hash, $c, 'rswstate', 'state');           # Reading mit Schaltstatus
  my $swstate  = ReadingsVal ($dswname, $rswstate,    'undef');

  if ($swstate =~ m/^$reg$/x) {
      return 1;
  }

return 0;
}

################################################################
#  Funktion liefert 1 wenn Consumer logisch "eingeschaltet"
#  ist, d.h. wenn der Energieverbrauch über einem bestimmten
#  Schwellenwert oder der prozentuale Verbrauch über dem
#  Defaultwert $defpopercent ist.
#
#  Logisch "on" schließt physisch "on" mit ein.
################################################################
sub isConsumerLogOn {
  my $hash  = shift;
  my $c     = shift;
  my $pcurr = shift // 0;

  my $name  = $hash->{NAME};
  my $cname = ConsumerVal ($hash, $c, "name", "");                                         # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the "on" state can't be identified});
      return 0;
  }

  if(isConsumerPhysOff($hash, $c)) {                                                       # Device ist physisch ausgeschaltet
      return 0;
  }

  my $type       = $hash->{TYPE};
  my $nompower   = ConsumerVal ($hash, $c, "power",          0);                           # nominale Leistung lt. Typenschild
  my $rpcurr     = ConsumerVal ($hash, $c, "rpcurr",        "");                           # Reading für akt. Verbrauch angegeben ?
  my $pthreshold = ConsumerVal ($hash, $c, "powerthreshold", 0);                           # Schwellenwert (W) ab der ein Verbraucher als aktiv gewertet wird

  if (!$rpcurr && isConsumerPhysOn($hash, $c)) {                                           # Workaround wenn Verbraucher ohne Leistungsmessung
      $pcurr = $nompower;
  }

  my $currpowerpercent = $pcurr;
  $currpowerpercent    = ($pcurr / $nompower) * 100 if($nompower > 0);

  $data{$type}{$name}{consumers}{$c}{currpowerpercent} = $currpowerpercent;

  if($pcurr > $pthreshold || $currpowerpercent > $defpopercent) {                          # Verbraucher ist logisch aktiv
      return 1;
  }

return 0;
}

################################################################
#  Consumer $c in Grafik ausblenden (1) oder nicht (0)
#  0 - nicht aublenden (default)
#  1 - ausblenden
#  2 - nur in Consumerlegende ausblenden
#  3 - nur in Flowgrafik ausblenden
################################################################
sub isConsumerNoshow {
  my $hash = shift;
  my $c    = shift;

  my $noshow = ConsumerVal ($hash, $c, 'noshow', 0);                                 # Schalter "Ausblenden"

  if (!isNumeric ($noshow)) {                                                        # Key "noshow" enthält Signalreading
      my $rdg             = $noshow;
      my ($dev, $dswname) = getCDnames ($hash, $c);                                  # Consumer und Switch Device Name

      if ($noshow =~ /:/xs) {
          ($dev, $rdg) = split ":", $noshow;
      }

      $noshow = ReadingsNum ($dev, $rdg, 0);
  }

  if ($noshow !~ /^[0123]$/xs) {                                                    # nue Ergebnisse 0..3 zulassen
      $noshow = 0;
  }

return $noshow;
}

################################################################
#  Funktion liefert "1" wenn die zusätzliche Einschaltbedingung
#  aus dem Schlüssel "swoncond" im Consumer Attribut wahr ist
#
#  $info - den Info-Status
#  $err  - einen Error-Status
#
################################################################
sub isAddSwitchOnCond {
  my $hash = shift;
  my $c    = shift;

  my $info = q{};
  my $err  = q{};

  my $dswoncond = ConsumerVal ($hash, $c, 'dswoncond', '');                     # Device zur Lieferung einer zusätzlichen Einschaltbedingung

  if($dswoncond && !$defs{$dswoncond}) {
      $err = qq{ERROR - the device "$dswoncond" doesn't exist! Check the key "swoncond" in attribute "consumer${c}"};
      return (0, $info, $err);
  }

  my $rswoncond     = ConsumerVal ($hash, $c, 'rswoncond',     '');             # Reading zur Lieferung einer zusätzlichen Einschaltbedingung
  my $swoncondregex = ConsumerVal ($hash, $c, 'swoncondregex', '');             # Regex einer zusätzliche Einschaltbedingung
  my $condval       = ReadingsVal ($dswoncond, $rswoncond,     '');             # Wert zum Vergleich mit Regex

  if ($condval =~ m/^$swoncondregex$/x) {
      return (1, $info, $err);
  }

  $info = qq{The device "$dswoncond", reading "$rswoncond" doesn't match the Regex "$swoncondregex"};

return (0, $info, $err);
}

################################################################
#  Funktion liefert "1" wenn eine Ausschaltbedingung
#  erfüllt ist
#  ("swoffcond" oder "interruptable" im Consumer Attribut)
#  Der Inhalt von "interruptable" wird optional in $cond
#  übergeben.
#
#  $info - den Info-Status
#  $err  - einen Error-Status
#
################################################################
sub isAddSwitchOffCond {
  my $hash = shift;
  my $c    = shift;
  my $cond = shift // q{};
  my $hyst = shift // 0;                                                          # Hysterese

  my $swoff          = 0;
  my $info           = q{};
  my $err            = q{};
  my $dswoffcond     = q{};                                                       # Device zur Lieferung einer Ausschaltbedingung
  my $rswoffcond     = q{};                                                       # Reading zur Lieferung einer Ausschaltbedingung
  my $swoffcondregex = q{};                                                       # Regex der Ausschaltbedingung (wenn wahr)

  if ($cond) {
      ($dswoffcond, $rswoffcond, $swoffcondregex) = split ":", $cond;
  }
  else {
      $dswoffcond     = ConsumerVal ($hash, $c, 'dswoffcond',     '');
      $rswoffcond     = ConsumerVal ($hash, $c, 'rswoffcond',     '');
      $swoffcondregex = ConsumerVal ($hash, $c, 'swoffcondregex', '');
  }

  if ($dswoffcond && !$defs{$dswoffcond}) {
      $err = qq{ERROR - the device "$dswoffcond" doesn't exist! Check the key "swoffcond" or "interruptable" in attribute "consumer${c}"};
      return (0, $info, $err);
  }

  my $condval = ReadingsVal ($dswoffcond, $rswoffcond, undef);

  if (defined $condval) {
      if ($condval =~ m/^$swoffcondregex$/x) {
          $info   = qq{value "$condval" matches the Regex "$swoffcondregex" \n};
          $info  .= "-> !Interrupt! ";
          $swoff  = 1;
      }
      else {
          $info  = qq{value "$condval" doesn't match the Regex "$swoffcondregex" \n};
          $swoff = 0;
      }

      if ($hyst && isNumeric ($condval)) {                                                              # Hysterese berücksichtigen
          $condval -= $hyst;

          if ($condval =~ m/^$swoffcondregex$/x) {
              $info   = qq{value "$condval" (included hysteresis = $hyst) matches the Regex "$swoffcondregex" \n};
              $info  .= "-> !Interrupt! ";
              $swoff  = 1;
          }
          else {
              $info  = qq{device: "$dswoffcond", reading: "$rswoffcond" , value: "$condval" (included hysteresis = $hyst) doesn't match Regex: "$swoffcondregex" \n};
              $swoff = 0;
          }
      }

      $info .= qq{-> the effect depends on the switch context\n};
  }

return ($swoff, $info, $err);
}

################################################################
#  Funktion liefert "1" wenn die angegebene Bedingung
#  aus dem Consumerschlüssel 'spignorecond' erfüllt ist.
#
#  $info - den Info-Status
#  $err  - einen Error-Status
#
################################################################
sub isSurplusIgnoCond {
  my $hash  = shift;
  my $c     = shift;
  my $debug = shift;

  my $info = q{};
  my $err  = q{};

  my $digncond = ConsumerVal ($hash, $c, 'dspignorecond', '');                          # Device zur Lieferung einer "Überschuß Ignore-Bedingung"

  if($digncond && !$defs{$digncond}) {
      $err = qq{ERROR - the device "$digncond" doesn't exist! Check the key "spignorecond" in attribute "consumer${c}"};
      return (0, $info, $err);
  }

  my $rigncond          = ConsumerVal ($hash, $c, 'rigncond',          '');             # Reading zur Lieferung einer zusätzlichen Einschaltbedingung
  my $spignorecondregex = ConsumerVal ($hash, $c, 'spignorecondregex', '');             # Regex einer zusätzliche Einschaltbedingung
  my $condval           = ReadingsVal ($digncond, $rigncond,           '');             # Wert zum Vergleich mit Regex

  if ($condval && $debug =~ /consumerSwitching/x) {
      my $name = $hash->{NAME};
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - PV surplus ignore condition ist set - device: $digncond, reading: $rigncond, condition: $spignorecondregex});
  }

  if ($condval && $condval =~ m/^$spignorecondregex$/x) {
      return (1, $info, $err);
  }

  $info = qq{The device "$digncond", reading "$rigncond" doesn't match the Regex "$spignorecondregex"};

return (0, $info, $err);
}

################################################################
#  liefert den Status des Timeframe von Consumer $c
################################################################
sub isInTimeframe {
  my $hash = shift;
  my $c    = shift;

return ConsumerVal ($hash, $c, 'isIntimeframe', 0);
}

################################################################
#  liefert Entscheidung ob sich Consumer $c noch in der
#  Sperrzeit befindet
################################################################
sub isInLocktime {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};

  my $iilt = 0;
  my $rlt  = 0;
  my $lt   = 0;
  my $clt  = 0;

  my $ltt = isConsumerPhysOn  ($hash, $c) ? 'onlt'  :                             # Typ der Sperrzeit
            isConsumerPhysOff ($hash, $c) ? 'offlt' :
            '';

  my ($cltoff, $clton) = split ":", ConsumerVal ($hash, $c, 'locktime', '0:0');
  $clton             //= 0;                                                       # $clton undef möglich, da Angabe optional

  if ($ltt eq 'onlt') {
      $lt = ConsumerVal ($hash, $c, 'lastAutoOnTs', 0);
      $clt = $clton;
  }
  elsif ($ltt eq 'offlt') {
      $lt  = ConsumerVal ($hash, $c, 'lastAutoOffTs', 0);
      $clt = $cltoff;
  }

  if ($t - $lt <= $clt) {
      $iilt = 1;
      $rlt  = $clt - ($t - $lt);                                                  # remain lock time
  }

return ($iilt, $rlt);
}

################################################################
#  liefert den Status "Consumption Recommended" von Consumer $c
################################################################
sub isConsRcmd {
  my $hash = shift;
  my $c    = shift;

return ConsumerVal ($hash, $c, 'isConsumptionRecommended', 0);
}

################################################################
#       ist Batterie installiert ?
#       1 - ja, 0 - nein
################################################################
sub isBatteryUsed {
  my $name   = shift;

  my $badev  = ReadingsVal($name, 'currentBatteryDev', '');                  # aktuelles Meter device für Batteriewerte
  my ($a,$h) = parseParams ($badev);
  $badev     = $a->[0] // "";

  return if(!$badev || !$defs{$badev});

return ($badev, $a ,$h);
}

################################################################
#  ist Consumer $c unterbrechbar (1|2) oder nicht (0|3)
################################################################
sub isInterruptable {
  my $hash  = shift;
  my $c     = shift;
  my $hyst  = shift // 0;
  my $print = shift // 0;                                                                  # Print out Debug Info

  my $name    = $hash->{NAME};
  my $intable = ConsumerVal ($hash, $c, 'interruptable', 0);

  if ($intable eq '0') {
      return 0;
  }
  elsif ($intable eq '1') {
      return 1;
  }

  my $debug = getDebug ($hash);                                                            # Debug Module

  my ($swoffcond,$info,$err) = isAddSwitchOffCond ($hash, $c, $intable, $hyst);
  Log3 ($name, 1, "$name - $err") if($err);

  if ($print && $debug =~ /consumerSwitching/x) {
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - Interrupt Info: $info});
  }

  if ($swoffcond) {
      return 2;
  }
  else {
      return 3;
  }

return;
}

################################################################
#  Prüfung auf numerischen Wert (vorzeichenbehaftet)
################################################################
sub isNumeric {
  my $val = shift // q{empty};

  my $ret = 0;

  if($val =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/xs) {
      $ret = 1;
  }

return $ret;
}

################################################################
#  Prüfung auf Verwendung von DWD als Strahlungsquelle
################################################################
sub isDWDUsed {
  my $hash = shift;

  my $ret = 0;

  if ($hash->{MODEL} && $hash->{MODEL} eq 'DWD') {
      $ret = 1;
  }

return $ret;
}

################################################################
#  Prüfung auf Verwendung von SolCast API
################################################################
sub isSolCastUsed {
  my $hash = shift;

  my $ret = 0;

  if ($hash->{MODEL} && $hash->{MODEL} eq 'SolCastAPI') {
      $ret = 1;
  }

return $ret;
}

################################################################
#  Prüfung auf Verwendung von ForecastSolar API
################################################################
sub isForecastSolarUsed {
  my $hash = shift;

  my $ret = 0;

  if ($hash->{MODEL} && $hash->{MODEL} eq 'ForecastSolarAPI') {
      $ret = 1;
  }

return $ret;
}

################################################################
#  Prüfung auf Verwendung von Victron VRM API (KI basierend)
################################################################
sub isVictronKiUsed {
  my $hash = shift;

  my $ret = 0;

  if ($hash->{MODEL} && $hash->{MODEL} eq 'VictronKiAPI') {
      $ret = 1;
  }

return $ret;
}

################################################################
#       welche PV Autokorrektur wird verwendet ?
#       Standard bei nur "on" -> on_simple
#       $aln: 1 - Lernen aktiviert (default)
#             0 - Lernen deaktiviert
################################################################
sub isAutoCorrUsed {
  my $name = shift;

  my $cauto = ReadingsVal ($name, 'pvCorrectionFactor_Auto', 'off');

  my $acu = $cauto =~ /on_simple_ai/xs  ? 'on_simple_ai'  :
            $cauto =~ /on_simple/xs     ? 'on_simple'     :
            $cauto =~ /on_complex_ai/xs ? 'on_complex_ai' :
            $cauto =~ /on_complex/xs    ? 'on_complex'    :
            $cauto =~ /standby/xs       ? 'standby'       :
            $cauto =~ /on/xs            ? 'on_simple'     :
            q{};

  my $aln = $cauto =~ /noLearning/xs ? 0 : 1;

return ($acu, $aln);
}

################################################################
#  liefert Status ob SunPath in mintime gesetzt ist
################################################################
sub isSunPath {
  my $hash = shift;
  my $c    = shift;

  my $is      = 0;
  my $mintime = ConsumerVal ($hash, $c, 'mintime', $defmintime);

  if ($mintime =~ /SunPath/xsi) {
      $is = 1;

      my $sunset  = CurrentVal ($hash, 'sunsetTodayTs',  1);
      my $sunrise = CurrentVal ($hash, 'sunriseTodayTs', 5);

      if ($sunrise > $sunset) {
          $is      = 0;
          my $name = $hash->{NAME};

          Log3($name, 1, qq{$name - ERROR - consumer >$c< use >mintime=SunPath< but readings >Today_SunRise< / >Today_SunSet< are not set properly.});
      }
  }

return $is;
}

################################################################
#  Verschiebung von Sonnenaufgang / Sonnenuntergang
#  bei Verwendung von mintime = SunPath
################################################################
sub sunShift {
  my $hash = shift;
  my $c    = shift;

  my $riseshift = ConsumerVal ($hash, $c, 'sunriseshift', 0);                  # Verschiebung (Sekunden) Sonnenaufgang bei SunPath Verwendung
  my $setshift  = ConsumerVal ($hash, $c, 'sunsetshift',  0);                  # Verschiebung (Sekunden) Sonnenuntergang bei SunPath Verwendung


return ($riseshift, $setshift);
}

################################################################
#  Prüfung ob global Attr latitude und longitude gesetzt sind
#  gibt latitude und longitude zurück
################################################################
sub locCoordinates {

  my $set = 0;
  my $lat = AttrVal ('global', 'latitude',  '');
  my $lon = AttrVal ('global', 'longitude', '');

  if($lat && $lon) {
      $set = 1;
  }

return ($set, $lat, $lon);
}

################################################################
#  liefert die Zeit des letzten Schaltvorganges
################################################################
sub lastConsumerSwitchtime {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};

  my ($cname, $dswname) = getCDnames ($hash, $c);                              # Consumer und Switch Device Name

  if(!$defs{$dswname}) {
      Log3($name, 1, qq{$name - ERROR - The last switching time can't be identified due to the device "$dswname" is invalid. Please check device names in consumer "$c" attribute});
      return;
  }

  my $rswstate = ConsumerVal           ($hash, $c, 'rswstate', 'state');       # Reading mit Schaltstatus
  my $swtime   = ReadingsTimestamp     ($dswname, $rswstate,        '');       # Zeitstempel im Format 2016-02-16 19:34:24
  my $swtimets;
  $swtimets    = timestringToTimestamp ($swtime) if($swtime);                  # Unix Timestamp Format erzeugen

return ($swtime, $swtimets);
}

################################################################
#  transformiert den ausführlichen Consumerstatus in eine
#  einfache Form
################################################################
sub simplifyCstate {
  my $ps = shift;

  $ps = $ps =~ /planned/xs        ? 'planned'      :
        $ps =~ /suspended/xs      ? 'suspended'    :
        $ps =~ /switching\son/xs  ? 'starting'     :
        $ps =~ /switched\son/xs   ? 'started'      :
        $ps =~ /switching\soff/xs ? 'stopping'     :
        $ps =~ /switched\soff/xs  ? 'finished'     :
        $ps =~ /priority/xs       ? 'priority'     :
        $ps =~ /interrupting/xs   ? 'interrupting' :
        $ps =~ /interrupted/xs    ? 'interrupted'  :
        $ps =~ /continuing/xs     ? 'continuing'   :
        $ps =~ /continued/xs      ? 'continued'    :
        $ps =~ /noSchedule/xs     ? 'noSchedule'   :
        'unknown';

return $ps;
}

################################################################
#  Prüfung eines übergebenen Regex
################################################################
sub checkRegex {
  my $regexp = shift // return;

  eval { "Hallo" =~ m/^$regexp$/;
         1;
       }
       or do { my $err = (split " at", $@)[0];
               return "Bad regexp: ".$err;
             };

return;
}

################################################################
#                 prüfen Angabe hh[:mm]
################################################################
sub checkhhmm {
  my $val = shift;

  my $valid = 0;

  if ($val =~ /^([0-9]{1,2})(:[0-5]{1}[0-9]{1})?$/xs) {
      $valid = 1 if(int $1 < 24);
  }

return $valid;
}

################################################################
#          prüfen validen Code in $val
################################################################
sub checkCode {
  my $name = shift;
  my $val  = shift;
  my $cc1  = shift // 0;                                 # wenn 1 checkCode1 ausführen

  my $err;

  if (!$val || $val !~ m/^\s*\{.*\}\s*$/xs) {
      return qq{Usage of $name is wrong. The function has to be specified as "{<your own code>}"};
  }

  if ($cc1) {
      ($err, $val) = checkCode1 ($name, $val);
      return ($err, $val);
  }

  my %specials = ( "%DEVICE"  => $name,
                   "%READING" => $name,
                   "%VALUE"   => 1,
                   "%UNIT"    => 'kW',
                 );

  $err = perlSyntaxCheck ($val, %specials);
  return $err if($err);

  if ($val =~ m/^\{.*\}$/xs && $val =~ m/=>/ && $val !~ m/\$/ ) {           # Attr wurde als Hash definiert
      my $av = eval $val;

      return $@ if($@);

      $av  = eval $val;
      $val = $av if(ref $av eq "HASH");
  }

return ('', $val);
}

################################################################
#          prüfen validen Code in $val
################################################################
sub checkCode1 {
  my $name = shift;
  my $val  = shift;

  my $hash = $defs{$name};

  $val =~ m/^\s*(\{.*\})\s*$/xs;
  $val = $1;
  $val = eval $val;
  return $@ if($@);

return ('', $val);
}

################################################################
#  die eingestellte Modulsprache ermitteln
################################################################
sub getLang {
  my $hash = shift;

  my $name  = $hash->{NAME};
  my $glang = AttrVal ('global', 'language', $deflang);
  my $lang  = AttrVal ($name, 'ctrlLanguage', $glang);

return $lang;
}

################################################################
#  den eingestellte Debug Modus ermitteln
################################################################
sub getDebug {
  my $hash = shift;

  my $debug = AttrVal ($hash->{NAME}, 'ctrlDebug', 'none');

return $debug;
}

################################################################
#  Namen des Consumerdevices und des zugeordneten
#  Switch Devices ermitteln
################################################################
sub getCDnames {
  my $hash = shift;
  my $c    = shift;

  my $cname   = ConsumerVal ($hash, $c, "name",        "");                                  # Name des Consumerdevices
  my $dswname = ConsumerVal ($hash, $c, 'dswitch', $cname);                                  # alternatives Switch Device


return ($cname, $dswname);
}

################################################################
#  diskrete Temperaturen in "Bins" wandeln
################################################################
sub temp2bin {
  my $temp = shift;

  my $bin = $temp > 35 ? '35' :
            $temp > 32 ? '35' :
            $temp > 30 ? '30' :
            $temp > 27 ? '30' :
            $temp > 25 ? '25' :
            $temp > 22 ? '25' :
            $temp > 20 ? '20' :
            $temp > 17 ? '20' :
            $temp > 15 ? '15' :
            $temp > 12 ? '15' :
            $temp > 10 ? '10' :
            $temp > 7  ? '10' :
            $temp > 5  ? '05' :
            $temp > 2  ? '05' :
            $temp > 0  ? '00' :
            '-05';

return $bin;
}

################################################################
#  diskrete Bewölkung in "Bins" wandeln
################################################################
sub cloud2bin {
  my $wcc = shift;

  my $bin = $wcc == 100 ? '100' :
            $wcc >  97  ? '100' :
            $wcc >  95  ? '95'  :
            $wcc >  92  ? '95'  :
            $wcc >  90  ? '90'  :
            $wcc >  87  ? '90'  :
            $wcc >  85  ? '85'  :
            $wcc >  82  ? '85'  :
            $wcc >  80  ? '80'  :
            $wcc >  77  ? '80'  :
            $wcc >  75  ? '75'  :
            $wcc >  72  ? '75'  :
            $wcc >  70  ? '70'  :
            $wcc >  67  ? '70'  :
            $wcc >  65  ? '65'  :
            $wcc >  62  ? '65'  :
            $wcc >  60  ? '60'  :
            $wcc >  57  ? '60'  :
            $wcc >  55  ? '55'  :
            $wcc >  52  ? '55'  :
            $wcc >  50  ? '50'  :
            $wcc >  47  ? '50'  :
            $wcc >  45  ? '45'  :
            $wcc >  42  ? '45'  :
            $wcc >  40  ? '40'  :
            $wcc >  37  ? '40'  :
            $wcc >  35  ? '35'  :
            $wcc >  32  ? '35'  :
            $wcc >  30  ? '30'  :
            $wcc >  27  ? '30'  :
            $wcc >  25  ? '25'  :
            $wcc >  22  ? '25'  :
            $wcc >  20  ? '20'  :
            $wcc >  17  ? '20'  :
            $wcc >  15  ? '15'  :
            $wcc >  12  ? '15'  :
            $wcc >  10  ? '10'  :
            $wcc >  7   ? '10'  :
            $wcc >  5   ? '05'  :
            $wcc >  2   ? '05'  :
            '00';

return $bin;
}

################################################################
#  diskrete Rain Prob in "Bins" wandeln
################################################################
sub rain2bin {
  my $wrp = shift;

  my $bin = $wrp == 100 ? '100' :
            $wrp >  97  ? '100' :
            $wrp >  95  ? '95'  :
            $wrp >  92  ? '95'  :
            $wrp >  90  ? '90'  :
            $wrp >  87  ? '90'  :
            $wrp >  85  ? '85'  :
            $wrp >  82  ? '85'  :
            $wrp >  80  ? '80'  :
            $wrp >  77  ? '80'  :
            $wrp >  75  ? '75'  :
            $wrp >  72  ? '75'  :
            $wrp >  70  ? '70'  :
            $wrp >  67  ? '70'  :
            $wrp >  65  ? '65'  :
            $wrp >  62  ? '65'  :
            $wrp >  60  ? '60'  :
            $wrp >  57  ? '60'  :
            $wrp >  55  ? '55'  :
            $wrp >  52  ? '55'  :
            $wrp >  50  ? '50'  :
            $wrp >  47  ? '50'  :
            $wrp >  45  ? '45'  :
            $wrp >  42  ? '45'  :
            $wrp >  40  ? '40'  :
            $wrp >  37  ? '40'  :
            $wrp >  35  ? '35'  :
            $wrp >  32  ? '35'  :
            $wrp >  30  ? '30'  :
            $wrp >  27  ? '30'  :
            $wrp >  25  ? '25'  :
            $wrp >  22  ? '25'  :
            $wrp >  20  ? '20'  :
            $wrp >  17  ? '20'  :
            $wrp >  15  ? '15'  :
            $wrp >  12  ? '15'  :
            $wrp >  10  ? '10'  :
            $wrp >  7   ? '10'  :
            $wrp >  5   ? '05'  :
            $wrp >  2   ? '05'  :
            '00';

return $bin;
}

###############################################################################
#                    verscrambelt einen String
###############################################################################
sub chew {
  my $sstr = shift;

  $sstr    = encode_base64 ($sstr, '');
  my @key  = qw(1 3 4 5 6 3 2 1 9);
  my $len  = scalar @key;
  my $i    = 0;
  my $dstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //, $sstr;   ## no critic 'Map blocks';

return $dstr;
}

###############################################################################
#             entpackt einen mit chew behandelten String
###############################################################################
sub assemble {
  my $sstr = shift;

  my @key  = qw(1 3 4 5 6 3 2 1 9);
  my $len  = scalar @key;
  my $i    = 0;
  my $dstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //, $sstr;    ## no critic 'Map blocks';
  $dstr    = decode_base64 ($dstr);

return $dstr;
}

###############################################################
#                   Daten Serialisieren
###############################################################
sub Serialize {
  my $data = shift;
  my $name = $data->{name};

  my $serial = eval { freeze ($data)
                    }
                    or do { Log3 ($name, 1, "$name - Serialization ERROR: $@");
                            return;
                          };

return $serial;
}

################################################################
#  Funktion um mit Storable eine Struktur in ein File
#  zu schreiben
################################################################
sub fileStore {
  my $obj  = shift;
  my $file = shift;

  my $err;
  my $ret = eval { nstore ($obj, $file) };

  if (!$ret || $@) {
      $err = $@ ? $@ : 'I/O problems or other internal error';
  }

return $err;
}

################################################################
#  Funktion um mit Storable eine Struktur aus einem File
#  zu lesen
################################################################
sub fileRetrieve {
  my $file = shift;

  my ($err, $obj);

  if (-e $file) {
      eval { $obj = retrieve ($file) };

      if (!$obj || $@) {
          $err = $@ ? $@ : 'I/O error while reading';
      }
  }

return ($err, $obj);
}

###############################################################
#  erzeugt eine Zeile Leerzeichen. Die Anzahl der
#  Leerzeichen ist etwas größer als die Zeichenzahl des
#  längsten Teilstrings (Trenner \n)
###############################################################
sub lineFromSpaces {
  my $str = shift // return;
  my $an  = shift // 5;

  my @sps = split "\n", $str;
  my $mlen = 1;

  for my $s (@sps) {
      my $len = length (trim $s);
      $mlen   = $len if($len && $len > $mlen);
  }

  my $ret = "\n";
  $ret   .= "&nbsp;" x ($mlen + $an);

return $ret;
}

################################################################
#  Funktion um userspezifische Programmaufrufe nach
#  Aktualisierung aller Readings zu ermöglichen
################################################################
sub userExit {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  my $uefn = AttrVal ($name, 'ctrlUserExitFn', '');
  return if(!$uefn);

  $uefn =~ s/\s*#.*//g;                                             # Kommentare entfernen
  $uefn =  join ' ', split(/\s+/sx, $uefn);                         # Funktion aus Attr ctrlUserExitFn serialisieren

  if ($uefn =~ m/^\s*(\{.*\})\s*$/xs) {                             # unnamed Funktion direkt in ctrlUserExitFn mit {...}
      $uefn = $1;

      eval $uefn;

      if ($@) {
          Log3 ($name, 1, "$name - ERROR in specific userExitFn: ".$@);
      }
  }

return;
}

###############################################################################
#    Wert des pvhist-Hash zurückliefern
#    Usage:
#    HistoryVal ($hash, $day, $hod, $key, $def)
#
#    $day: Tag des Monats (01,02,...,31)
#    $hod: Stunde des Tages (01,02,...,24,99)
#    $key:    etotal      - totale PV Erzeugung (Wh)
#             pvrl        - realer PV Ertrag
#             pvfc        - PV Vorhersage
#             confc       - Vorhersage Hausverbrauch (Wh)
#             gcons       - realer Netzbezug
#             gfeedin     - reale Netzeinspeisung
#             batintotal  - totale Batterieladung (Wh)
#             batin       - Batterieladung der Stunde (Wh)
#             batouttotal - totale Batterieentladung (Wh)
#             batout      - Batterieentladung der Stunde (Wh)
#             batmsoc     - max. SOC des Tages (%)
#             batsetsoc   - optimaler (berechneter) SOC (%) für den Tag
#             weatherid   - Wetter ID
#             wcc         - Grad der Bewölkung
#             temp        - Außentemperatur
#             wrp         - Niederschlagswahrscheinlichkeit
#             pvcorrf     - PV Autokorrekturfaktor f. Stunde des Tages
#             dayname     - Tagesname (Kürzel)
#             csmt${c}    - Totalconsumption Consumer $c (1..$maxconsumer)
#             csme${c}    - Consumption Consumer $c (1..$maxconsumer) in $hod
#    $def: Defaultwert
#
###############################################################################
sub HistoryVal {
  my $hash = shift;
  my $day  = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if(defined($data{$type}{$name}{pvhist})                    &&
     defined($data{$type}{$name}{pvhist}{$day})              &&
     defined($data{$type}{$name}{pvhist}{$day}{$hod})        &&
     defined($data{$type}{$name}{pvhist}{$day}{$hod}{$key})) {
     return  $data{$type}{$name}{pvhist}{$day}{$hod}{$key};
  }

return $def;
}

#####################################################################################################
#    Wert des circular-Hash zurückliefern
#    Achtung: die Werte im circular-Hash haben nicht
#             zwingend eine Beziehung zueinander !!
#
#    Usage:
#    CircularVal ($hash, $hod, $key, $def)
#
#    $hod: Stunde des Tages (01,02,...,24) bzw. 99 (besondere Verwendung)
#    $key:    pvrl             - realer PV Ertrag
#             pvfc             - PV Vorhersage
#             confc            - Vorhersage Hausverbrauch (Wh)
#             gcons            - realer Netzbezug
#             gfeedin          - reale Netzeinspeisung
#             batin            - Batterieladung (Wh)
#             batout           - Batterieentladung (Wh)
#             weatherid        - DWD Wetter id
#             weathertxt       - DWD Wetter Text
#             wcc              - DWD Wolkendichte
#             wrp              - DWD Regenwahrscheinlichkeit
#             temp             - Außentemperatur
#             pvcorrf          - PV Autokorrekturfaktoren (HASH)
#             lastTsMaxSocRchd - Timestamp des letzten Erreichens von SoC >= maxSoC
#             nextTsMaxSocChge - Timestamp bis zu dem die Batterie mindestens einmal maxSoC erreichen soll
#             days2care        - verbleibende Tage bis der Batterie Pflege-SoC (default $maxSoCdef) erreicht sein soll
#             tdayDvtn         - heutige Abweichung PV Prognose/Erzeugung in %
#             ydayDvtn         - gestrige Abweichung PV Prognose/Erzeugung in %
#             initdayfeedin    - initialer Wert für "gridfeedin" zu Beginn des Tages (Wh)
#             feedintotal      - Einspeisung PV Energie total (Wh)
#             initdaygcon      - initialer Wert für "gcon" zu Beginn des Tages (Wh)
#             initdaybatintot  - initialer Wert für Batterie intotal zu Beginn des Tages (Wh)
#             batintot         - Batterie intotal (Wh)
#             initdaybatouttot - initialer Wert für Batterie outtotal zu Beginn des Tages (Wh)
#             batouttot        - Batterie outtotal (Wh)
#             gridcontotal     - Netzbezug total (Wh)
#
#    $def: Defaultwert
#
#####################################################################################################
sub CircularVal {
  my $hash = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if(defined($data{$type}{$name}{circular})              &&
     defined($data{$type}{$name}{circular}{$hod})        &&
     defined($data{$type}{$name}{circular}{$hod}{$key})) {
     return  $data{$type}{$name}{circular}{$hod}{$key};
  }

return $def;
}

################################################################
#    Wert des Autokorrekturfaktors und dessen Qualität
#    für eine bestimmte Bewölkungs-Range aus dem circular-Hash
#    zurückliefern
#    Usage:
#    ($f,$q) = CircularAutokorrVal ($hash, $hod, $range, $def)
#
#    $f:      Korrekturfaktor f. Stunde des Tages
#    $q:      Qualität des Korrekturfaktors
#
#    $hod:    Stunde des Tages (01,02,...,24)
#    $range:  Range Bewölkung (1...100) oder "percentile"
#    $def:    Defaultwert
#
################################################################
sub CircularAutokorrVal {
  my $hash  = shift;
  my $hod   = shift;
  my $range = shift;
  my $def   = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my $pvcorrf = $def;
  my $quality = $def;

  if(defined($data{$type}{$name}{circular})                         &&
     defined($data{$type}{$name}{circular}{$hod})                   &&
     defined($data{$type}{$name}{circular}{$hod}{pvcorrf})          &&
     defined($data{$type}{$name}{circular}{$hod}{pvcorrf}{$range})) {
     $pvcorrf = $data{$type}{$name}{circular}{$hod}{pvcorrf}{$range};
  }

  if(defined($data{$type}{$name}{circular})                         &&
     defined($data{$type}{$name}{circular}{$hod})                   &&
     defined($data{$type}{$name}{circular}{$hod}{quality})          &&
     defined($data{$type}{$name}{circular}{$hod}{quality}{$range})) {
     $quality = $data{$type}{$name}{circular}{$hod}{quality}{$range};
  }

return ($pvcorrf, $quality);
}

#########################################################################################
# Wert des nexthours-Hash zurückliefern
# Usage:
# NexthoursVal ($hash, $nhr, $key, $def)
#
# $nhr: nächste Stunde (NextHour00, NextHour01,...)
# $key: starttime  - Startzeit der abgefragten nächsten Stunde
#       hourofday  - Stunde des Tages
#       pvfc - PV Vorhersage in Wh
#       pvaifc 	   - erwartete PV Erzeugung der KI (Wh)
#       aihit      - Trefferstatus KI
#       weatherid  - DWD Wetter id
#       cloudcover - DWD Wolkendichte
#       cloudrange - berechnete Bewölkungsrange
#       rainprob   - DWD Regenwahrscheinlichkeit
#       rad1h      - Globalstrahlung (kJ/m2)
#       confc      - prognostizierter Hausverbrauch (Wh)
#       confcEx    - prognostizierter Hausverbrauch ohne registrierte Consumer (Wh)
#       today      - 1 wenn heute
#       correff    - verwendeter Korrekturfaktor / Qualität
#       DoN        - Sonnenauf- und untergangsstatus (0 - Nacht, 1 - Tag)
# $def: Defaultwert
#
#########################################################################################
sub NexthoursVal {
  my $hash = shift;
  my $nhr  = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if(defined($data{$type}{$name}{nexthours})              &&
     defined($data{$type}{$name}{nexthours}{$nhr})        &&
     defined($data{$type}{$name}{nexthours}{$nhr}{$key})) {
     return  $data{$type}{$name}{nexthours}{$nhr}{$key};
  }

return $def;
}

###################################################################################################
# Wert des current-Hash zurückliefern
# Usage:
# CurrentVal ($hash, $key, $def)
#
# $key: generation           - aktuelle PV Erzeugung
#       aiinitstate          - Initialisierungsstatus der KI
#       aitrainstate         - Traisningsstatus der KI
#       aiaddistate          - Add Instanz Status der KI
#       batcharge            - Bat SOC in %
#       batinstcap           - installierte Batteriekapazität in Wh
#       ctrunning            - aktueller Ausführungsstatus des Central Task
#       genslidereg          - Schieberegister PV Erzeugung (Array)
#       h4fcslidereg         - Schieberegister 4h PV Forecast (Array)
#       socslidereg          - Schieberegister Batterie SOC (Array)
#       consumption          - aktueller Verbrauch (W)
#       consumerdevs         - alle registrierten Consumerdevices (Array)
#       consumerCollected    - Statusbit Consumer Attr gesammelt und ausgewertet
#       gridconsumption      - aktueller Netzbezug
#       powerbatin           - Batterie Ladeleistung
#       powerbatout          - Batterie Entladeleistung
#       temp                 - aktuelle Außentemperatur
#       surplus              - aktueller PV Überschuß
#       tomorrowconsumption  - Verbrauch des kommenden Tages
#       invertercapacity     - Bemessungsleistung der Wechselrichters (max. W)
#       allstringspeak       - Peakleistung aller Strings nach temperaturabhängiger Korrektur
#       allstringscount      - aktuelle Anzahl der Anlagenstrings
#       tomorrowconsumption  - erwarteter Gesamtverbrauch am morgigen Tag
#       sunriseToday         - Sonnenaufgang heute
#       sunriseTodayTs       - Sonnenaufgang heute Unix Timestamp
#       sunsetToday          - Sonnenuntergang heute
#       sunsetTodayTs        - Sonnenuntergang heute Unix Timestamp
#
# $def: Defaultwert
#
###################################################################################################
sub CurrentVal {
  my $hash = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if (defined $data{$type}{$name}{current}       &&
      defined $data{$type}{$name}{current}{$key}) {
      return  $data{$type}{$name}{current}{$key};
  }

return $def;
}

###################################################################################################
# Wert des String Hash zurückliefern
# Usage:
# StringVal ($hash, $strg, $key, $def)
#
# $strg:        - Name des Strings aus modulePeakString
# $key:  peak   - Peakleistung aus modulePeakString
#        tilt   - Neigungswinkel der Module aus moduleTiltAngle
#        dir    - Ausrichtung der Module als Azimut-Bezeichner (N,NE,E,SE,S,SW,W,NW)
#        azimut - Ausrichtung der Module als Azimut Angabe -180 .. 0 .. 180
#
# $def:  Defaultwert
#
###################################################################################################
sub StringVal {
  my $hash = shift;
  my $strg = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if (defined $data{$type}{$name}{strings}              &&
      defined $data{$type}{$name}{strings}{$strg}       &&
      defined $data{$type}{$name}{strings}{$strg}{$key}) {
      return  $data{$type}{$name}{strings}{$strg}{$key};
  }

return $def;
}

###################################################################################################
# Wert AI::DecisionTree Objects zurückliefern
# Usage:
# AiDetreeVal ($hash, key, $def)
#
# key: object     - das AI Object
#      aitrained  - AI trainierte Daten
#      airaw      - Rohdaten für AI Input = Raw Trainigsdaten
#
# $def:  Defaultwert
#
###################################################################################################
sub AiDetreeVal {
  my $hash = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if (defined $data{$type}{$name}{aidectree}   &&
      defined $data{$type}{$name}{aidectree}{$key}) {
      return  $data{$type}{$name}{aidectree}{$key};
  }

return $def;
}

###################################################################################################
# Wert AI Raw Data zurückliefern
# Usage:
# AiRawdataVal ($hash, $idx, $key, $def)
# AiRawdataVal ($hash, '', '', $def)      -> den gesamten Hash airaw lesen
#
# $idx:            - Index
# $key: rad1h      - Strahlungsdaten
#       temp       - Temeperatur als Bin
#       wcc        - Bewölkung als Bin
#       wrp        - Regenwert als Bin
#       hod        - Stunde des Tages
#       pvrl       - reale PV Erzeugung
#
# $def:  Defaultwert
#
###################################################################################################
sub AiRawdataVal {
  my $hash = shift;
  my $idx  = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if (!$idx && !$key) {
      if (defined $data{$type}{$name}{aidectree}{airaw}) {
          return  $data{$type}{$name}{aidectree}{airaw};
      }
  }

  if (defined $data{$type}{$name}{aidectree}{airaw}          &&
      defined $data{$type}{$name}{aidectree}{airaw}{$idx}    &&
      defined $data{$type}{$name}{aidectree}{airaw}{$idx}{$key}) {
      return  $data{$type}{$name}{aidectree}{airaw}{$idx}{$key};
  }

return $def;
}

###################################################################################################################
# Wert des consumer-Hash zurückliefern
# Usage:
# ConsumerVal ($hash, $co, $key, $def)
#
# $co:  Consumer Nummer (01,02,03,...)
# $key: name            - Name des Verbrauchers (Device)
#       alias           - Alias des Verbrauchers (Device)
#       autoreading     - Readingname f. Automatiksteuerung
#       type            - Typ des Verbrauchers
#       state           - Schaltstatus des Consumers
#       power           - nominale Leistungsaufnahme des Verbrauchers in W
#       mode            - Planungsmode des Verbrauchers
#       icon            - Icon für den Verbraucher
#       mintime         - min. Einplanungsdauer
#       onreg           - Regex für phys. Zustand "ein"
#       offreg          - Regex für phys. Zustand "aus"
#       oncom           - Einschaltkommando
#       offcom          - Ausschaltkommando
#       physoffon       - physischer Schaltzustand ein/aus
#       onoff           - logischer ein/aus Zustand des am Consumer angeschlossenen Endverbrauchers
#       asynchron       - Arbeitsweise des FHEM Consumer Devices
#       retotal         - Reading der Leistungsmessung
#       uetotal         - Unit der Leistungsmessung
#       rpcurr          - Readingname des aktuellen Verbrauchs
#       powerthreshold  - Schwellenwert d. aktuellen Leistung(W) ab der ein Verbraucher als aktiv gewertet wird
#       energythreshold - Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird
#       upcurr          - Unit des aktuellen Verbrauchs
#       avgenergy       - initialer / gemessener Durchschnittsverbrauch pro Stunde
#       avgruntime      - durchschnittliche Einschalt- bzw. Zykluszeit (Minuten)
#       epieces         - prognostizierte Energiescheiben (Hash)
#       ehodpieces      - geplante Energiescheiben nach Tagesstunde (hour of day) (Hash)
#       dswoncond       - Device zur Lieferung einer zusätzliche Einschaltbedingung
#       planstate       - Planungsstatus
#       planSupplement  - Ergänzung zum Planungsstatus
#       rswoncond       - Reading zur Lieferung einer zusätzliche Einschaltbedingung
#       swoncondregex   - Regex einer zusätzliche Einschaltbedingung
#       dswoffcond      - Device zur Lieferung einer vorrangige Ausschaltbedingung
#       rswoffcond      - Reading zur Lieferung einer vorrangige Ausschaltbedingung
#       swoffcondregex  - Regex einer einer vorrangige Ausschaltbedingung
#       isIntimeframe   - ist Zeit innerhalb der Planzeit ein/aus
#       interruptable   - Consumer "on" ist während geplanter "ein"-Zeit unterbrechbar
#       lastAutoOnTs    - Timestamp des letzten On-Schaltens bzw. letzter Fortsetzung (nur Automatik-Modus)
#       lastAutoOffTs   - Timestamp des letzten Off-Schaltens bzw. letzter Unterbrechnung (nur Automatik-Modus)
#       hysteresis      - Hysterese
#       sunriseshift    - Verschiebung (Sekunden) Sonnenaufgang bei SunPath Verwendung
#       sunsetshift     - Verschiebung (Sekunden) Sonnenuntergang bei SunPath Verwendung
#
# $def: Defaultwert
#
####################################################################################################################
sub ConsumerVal {
  my $hash = shift;
  my $co   = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if (defined($data{$type}{$name}{consumers})             &&
      defined($data{$type}{$name}{consumers}{$co}{$key})  &&
      defined($data{$type}{$name}{consumers}{$co}{$key})) {
      return  $data{$type}{$name}{consumers}{$co}{$key};
  }

return $def;
}

##########################################################################################################################################################
# Wert des solcastapi-Hash zurückliefern
# Usage:
# SolCastAPIVal ($hash, $tring, $ststr, $key, $def)
#
# $tring:  Stringname aus "inverterStrings" (?All für allg. Werte)
# $ststr:  Startzeit der Form YYYY-MM-DD hh:00:00
# $key:    pv_estimate50 - PV Schätzung in Wh
#          Rad1h         - vorhergesagte Globalstrahlung (Model DWD)
# $def:    Defaultwert
#
# Sonderabfragen
# SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_time',      $def) - letzte Abfrage Zeitstring
# SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_timestamp', $def) - letzte Abfrage Unix Timestamp
# SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIrequests',    $def) - heute ausgeführte API Requests
# SolCastAPIVal ($hash, '?All', '?All', 'todayRemainingAPIrequests $def) - heute verbleibende API Requests
# SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIcalls',       $def) - heute ausgeführte API Calls (hat u.U. mehrere Requests)
# SolCastAPIVal ($hash, '?All', '?All', 'todayRemainingAPIcalls',  $def) - heute noch mögliche API Calls (ungl. Requests !)
# SolCastAPIVal ($hash, '?All', '?All', 'solCastAPIcallMultiplier',$def) - APIcalls = APIRequests * solCastAPIcallMultiplier
# SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval',      $def) - aktuelles API Request Intervall
# SolCastAPIVal ($hash, '?All', '?All', 'response_message',        $def) - letzte API Antwort
# SolCastAPIVal ($hash, '?All', $ststr, 'Rad1h',                   $def) - Globalstrahlung mit Startzeit
# SolCastAPIVal ($hash, '?All', '?All', 'place',                   $def) - ForecastSolarAPI -> Location der Anlage
# SolCastAPIVal ($hash, '?All', '?All', 'requests_limit',          $def) - ForecastSolarAPI -> Request Limit innerhalb der Periode
# SolCastAPIVal ($hash, '?All', '?All', 'requests_limit_period',   $def) - ForecastSolarAPI -> Periode für Request Limit
# SolCastAPIVal ($hash, '?All', '?All', 'requests_remaining',      $def) - ForecastSolarAPI -> verbleibende Requests innerhalb der laufenden Periode
# SolCastAPIVal ($hash, '?All', '?All', 'response_code',           $def) - ForecastSolarAPI -> letzter Antwortcode
# SolCastAPIVal ($hash, '?All', '?All', 'retryat_time',            $def) - ForecastSolarAPI -> Zwangsverzögerung des nächsten Calls bis Uhrzeit
# SolCastAPIVal ($hash, '?All', '?All', 'retryat_timestamp',       $def) - ForecastSolarAPI -> Zwangsverzögerung des nächsten Calls bis UNIX-Zeitstempel
#
# SolCastAPIVal ($hash, '?IdPair', '?<pk>', 'rtid',                $def) - RoofTop-ID, <pk> = Paarschlüssel
# SolCastAPIVal ($hash, '?IdPair', '?<pk>', 'apikey',              $def) - API-Key, <pk> = Paarschlüssel
#
##########################################################################################################################################################
sub SolCastAPIVal {
  my $hash   = shift;
  my $string = shift;
  my $ststr  = shift;
  my $key    = shift;
  my $def    = shift;

  my $name   = $hash->{NAME};
  my $type   = $hash->{TYPE};

  if(defined $data{$type}{$name}{solcastapi}                         &&
     defined $data{$type}{$name}{solcastapi}{$string}                &&
     defined $data{$type}{$name}{solcastapi}{$string}{$ststr}        &&
     defined $data{$type}{$name}{solcastapi}{$string}{$ststr}{$key}) {
     return  $data{$type}{$name}{solcastapi}{$string}{$ststr}{$key};
  }

return $def;
}

1;

=pod
=item summary    Visualization of solar predictions for PV systems and Consumer control
=item summary_DE Visualisierung von solaren Vorhersagen für PV Anlagen und Verbrauchersteuerung

=begin html

<a id="SolarForecast"></a>
<h3>SolarForecast</h3>
<br>
The SolarForecast module generates a forecast for the solar yield on the basis of the values
from generic sources and integrates further information as a basis for control systems based on this forecast. <br>

To create the solar forecast, the SolarForecast module can use different services and sources: <br><br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> <b>DWD</b>               </td><td>solar forecast based on the radiation forecast of the German Weather Service (Model DWD)                                              </td></tr>
        <tr><td> <b>SolCast-API </b>      </td><td>uses forecast data of the <a href='https://toolkit.solcast.com.au/rooftop-sites/' target='_blank'>SolCast API</a> (Model SolCastAPI)  </td></tr>
        <tr><td> <b>ForecastSolar-API</b> </td><td>uses forecast data of the <a href='https://doc.forecast.solar/api' target='_blank'>Forecast.Solar API</a> (Model ForecastSolarAPI)    </td></tr>
        <tr><td> <b>VictronKI-API</b>     </td><td>Victron Energy API of the <a href='https://www.victronenergy.com/blog/2023/07/05/new-vrm-solar-production-forecast-feature/' target='_blank'>VRM Portal</a> (Model VictronKiAPI) </td></tr>
     </table>
  </ul>
  <br>

AI support can be enabled when using the Model DWD. <br>
The use of the mentioned API's is limited to the respective free version of the selected service. <br>
In the assigned DWD_OpenData Device (Setter "currentWeatherDev") the suitable weather station is to be specified
to get meteorological data (cloudiness, sunrise, etc.) or a radiation forecast (Model DWD) for the plant
location. <br><br>

In addition to the PV generation forecast, consumption values or grid reference values are recorded and used for a
consumption forecast. <br>
The module calculates a future energy surplus from the forecast values, which is used to plan the operation of consumers.
Furthermore, the module offers <a href="#SolarForecast-Consumer">Consumer Integration</a> for integrated
planning and control of PV surplus dependent consumer circuits. <br><br>

At the first definition of the module the user is supported by a Guided Procedure to make all initial entries. <br>
At the end of the process and after relevant changes to the system or device configuration, it is essential to perform a
<a href="#SolarForecast-set-plantConfiguration">set &lt;name&gt; plantConfiguration ceck</a>
to ensure that the system configuration is correct.

<ul>
  <a id="SolarForecast-define"></a>
  <b>Define</b>
  <br><br>

  <ul>
    A SolarForecast Device is created with: <br><br>

    <ul>
      <b>define &lt;name&gt; SolarForecast </b>
    </ul>
    <br>

    After the definition of the device, depending on the forecast sources used, it is mandatory to store additional
    plant-specific information with the corresponding set commands. <br>
    The following set commands are used to store information that is relevant for the function of the module: <br><br>

      <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>currentWeatherDev</b>    </td><td>DWD_OpenData Device which provides meteorological data (e.g. cloud cover)     </td></tr>
            <tr><td> <b>currentRadiationAPI </b> </td><td>DWD_OpenData Device or API for the delivery of radiation data.                </td></tr>
            <tr><td> <b>currentInverterDev</b>   </td><td>Device which provides PV performance data                                     </td></tr>
            <tr><td> <b>currentMeterDev</b>      </td><td>Device which supplies network I/O data                                        </td></tr>
            <tr><td> <b>currentBatteryDev</b>    </td><td>Device which provides battery performance data (if available)                 </td></tr>
            <tr><td> <b>inverterStrings</b>      </td><td>Identifier of the existing plant strings                                      </td></tr>
            <tr><td> <b>moduleDirection</b>      </td><td>Alignment (azimuth) of the plant strings                                      </td></tr>
            <tr><td> <b>modulePeakString</b>     </td><td>the DC peak power of the plant strings                                        </td></tr>
            <tr><td> <b>roofIdentPair</b>        </td><td>the identification data (when using the SolCast API)                          </td></tr>
            <tr><td> <b>moduleRoofTops</b>       </td><td>the Rooftop parameters (when using the SolCast API)                           </td></tr>
            <tr><td> <b>moduleTiltAngle</b>      </td><td>the inclination angles of the plant modules                                   </td></tr>
         </table>
      </ul>
      <br>

    In order to enable an adjustment to the personal system, correction factors can be manually fixed or automatically
    applied dynamically.
    <br><br>
  </ul>

  <a id="SolarForecast-Consumer"></a>
  <b>Consumer Integration</b>
  <br><br>

  <ul>
    The user can register consumers (e.g. switchable sockets) directly in the module and let the SolarForecast module take
    over the planning of the on/off times as well as their execution. Registration is done using the
    <a href="#SolarForecast-attr-consumer">ConsumerXX attributes</a>. In addition to the FHEM consumer device, a number
    of mandatory or optional keys are specified in the attributes that influence the scheduling and switching behavior of
    the consumer. <br>
    The keys are described in detail in the ConsumerXX help.
    In order to learn how to use the consumer control, it is advisable to first create one or
    more dummies and register these devices as consumers.
    <br><br>

    A dummy device according to this pattern is suitable for this purpose:
    <br><br>

    <ul>
        define SolCastDummy dummy                                                                                                   <br>
        attr SolCastDummy userattr nomPower                                                                                         <br>
        attr SolCastDummy alias SolarForecast Consumer Dummy                                                                        <br>
        attr SolCastDummy cmdIcon on:remotecontrol/black_btn_GREEN off:remotecontrol/black_btn_RED                                  <br>
        attr SolCastDummy devStateIcon off:light_light_dim_100@grey on:light_light_dim_100@darkorange                               <br>
        attr SolCastDummy group Solarforecast                                                                                       <br>
        attr SolCastDummy icon solar_icon                                                                                           <br>
        attr SolCastDummy nomPower 1000                                                                                             <br>
        attr SolCastDummy readingList BatIn BatOut BatVal  BatInTot BatOutTot bezW einW Batcharge Temp automatic                    <br>
        attr SolCastDummy room Energy,Testroom                                                                                      <br>
        attr SolCastDummy setList BatIn BatOut BatVal BatInTot BatOutTot bezW einW Batcharge on off Temp                            <br>
        attr SolCastDummy userReadings actpow {ReadingsVal ($name, 'state', 'off') eq 'on' ? AttrVal ($name, 'nomPower', 100) : 0}  <br>
    </ul>

    <br><br>
  </ul>

  <a id="SolarForecast-set"></a>
  <b>Set</b>
  <ul>

    <ul>
      <a id="SolarForecast-set-aiDecTree"></a>
      <li><b>aiDecTree </b> <br><br>

      If AI support is enabled in the SolarForecast Device, various AI actions can be performed manually.
      The manual execution of the AI actions is generally not necessary, since the processing of all necessary steps is
      already performed automatically in the module.
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="10%"> <col width="90%"> </colgroup>
          <tr><td> <b>addInstances</b>  </td><td>- The AI is enriched with the currently available PV, radiation and environmental data.                </td></tr>
          <tr><td> <b>addRawData</b>    </td><td>- Relevant PV, radiation and environmental data are extracted and stored for later use.                </td></tr>
          <tr><td> <b>train</b>         </td><td>- The AI is trained with the available data.                                                           </td></tr>
          <tr><td>                      </td><td>&nbsp;&nbsp;Successfully generated decision data is stored in the file system.                         </td></tr>
        </table>
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-batteryTrigger"></a>
      <li><b>batteryTrigger &lt;1on&gt;=&lt;Value&gt; &lt;1off&gt;=&lt;Value&gt; [&lt;2on&gt;=&lt;Value&gt; &lt;2off&gt;=&lt;Value&gt; ...] </b> <br><br>

      Generates triggers when the battery charge exceeds or falls below certain values (SoC in %). <br>
      If the last three SoC measurements exceed a defined <b>Xon-Bedingung</b>, the reading <b>batteryTrigger_X = on</b>
      is created/set. <br>
      If the last three SoC measurements fall below a defined <b>Xoff-Bedingung</b>, the reading
      <b>batteryTrigger_X = off</b> is created/set. <br>
      Any number of trigger conditions can be specified. Xon/Xoff conditions do not necessarily have to be defined in pairs.
      <br>
      <br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; batteryTrigger 1on=30 1off=10 2on=70 2off=20 3on=15 4off=90<br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-consumerNewPlanning"></a>
      <li><b>consumerNewPlanning &lt;Consumer number&gt; </b> <br><br>

      The existing planning of the specified consumer is deleted. <br>
      The new planning is carried out immediately, taking into account the parameters set in the consumerXX attribute.
      <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; consumerNewPlanning 01 <br>
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-consumerImmediatePlanning"></a>
      <li><b>consumerImmediatePlanning &lt;Consumer number&gt; </b> <br><br>

      Immediate switching on of the consumer at the current time is scheduled.
      Any keys <b>notbefore</b>, <b>notafter</b> respectively <b>mode</b> set in the consumerXX attribute are ignored <br>
      <br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; consumerImmediatePlanning 01 <br>
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentBatteryDev"></a>
      <li><b>currentBatteryDev &lt;Battery Device Name&gt; pin=&lt;Readingname&gt;:&lt;Unit&gt; pout=&lt;Readingname&gt;:&lt;Unit&gt;
                               [intotal=&lt;Readingname&gt;:&lt;Unit&gt;] [outtotal=&lt;Readingname&gt;:&lt;Unit&gt;]
                               [cap=&lt;Option&gt;] [charge=&lt;Readingname&gt;]  </b> <br><br>

      Specifies an arbitrary Device and its Readings to deliver the battery performance data.
      The module assumes that the numerical value of the readings is always positive.
      It can also be a dummy device with corresponding readings. The meaning of the respective "Readingname" is:
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>pin</b>       </td><td>Reading which provides the current battery charging power                                         </td></tr>
          <tr><td> <b>pout</b>      </td><td>Reading which provides the current battery discharge rate                                         </td></tr>
          <tr><td> <b>intotal</b>   </td><td>Reading which provides the total battery charge as a continuous counter (optional)                </td></tr>
          <tr><td> <b>outtotal</b>  </td><td>Reading which provides the total battery discharge as a continuous counter (optional)             </td></tr>
          <tr><td> <b>cap</b>       </td><td>installed battery capacity (optional). Option can be:                                             </td></tr>
          <tr><td>                  </td><td><b>numerical value</b> - direct indication of the battery capacity in Wh                          </td></tr>
          <tr><td>                  </td><td><b>&lt;Readingname&gt;:&lt;unit&gt;</b> - Reading which provides the capacity and unit (Wh, kWh)  </td></tr>
          <tr><td> <b>charge</b>    </td><td>Reading which provides the current state of charge (SOC in percent) (optional)                    </td></tr>
          <tr><td> <b>Unit</b>      </td><td>the respective unit (W,Wh,kW,kWh)                                                                 </td></tr>
        </table>
      </ul>
      <br>

      <b>Special cases:</b> If the reading for pin and pout should be identical but signed,
      the keys pin and pout can be defined as follows: <br><br>
      <ul>
        pin=-pout  &nbsp;&nbsp;&nbsp;(a negative value of pout is used as pin)  <br>
        pout=-pin  &nbsp;&nbsp;&nbsp;(a negative value of pin is used as pout)
      </ul>
      <br>

      The unit is omitted in the particular special case. <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; currentBatteryDev BatDummy pin=BatVal:W pout=-pin intotal=BatInTot:Wh outtotal=BatOutTot:Wh cap=BatCap:kWh <br>
        <br>
        # Device BatDummy returns the current battery charge in the reading "BatVal" (W), the battery discharge in the same reading with negative sign, <br>
        # the summary charge in the reading "intotal" (Wh), as well as the summary discharge in the reading "outtotal". (Wh)
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentWeatherDev"></a>
      <li><b>currentWeatherDev </b> <br><br>

      Defines the device (type DWD_OpenData), which provides the required weather data (cloudiness, precipitation,
      sunrise/sunset, etc.).
      Ist noch kein Device dieses Typs vorhanden, muß es manuell definiert werden
      (look at <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      At least these attributes must be set in the selected DWD_OpenData Device: <br><br>

      <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                   </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>TTT,Neff,R101,ww,SunUp,SunRise,SunSet               </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                   </td></tr>
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Station code of the evaluated DWD station&gt;   </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentInverterDev"></a>
      <li><b>currentInverterDev &lt;Inverter Device Name&gt; pv=&lt;Readingname&gt;:&lt;Unit&gt; etotal=&lt;Readingname&gt;:&lt;Unit&gt; [capacity=&lt;max. WR-Leistung&gt;] </b> <br><br>

      Specifies any Device and its Readings to deliver the current PV generation values.
      It can also be a dummy device with appropriate readings.
      The values of several inverter devices are merged e.g. in a dummy device and this device is specified with the
      corresponding readings. <br>
      Specifying <b>capacity</b> is optional, but strongly recommended to optimize prediction accuracy.
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>pv</b>       </td><td>Reading which provides the current PV generation                                       </td></tr>
          <tr><td> <b>etotal</b>   </td><td>Reading which provides the total PV energy generated (a steadily increasing counter).  </td></tr>
          <tr><td> <b>Einheit</b>  </td><td>the respective unit (W,kW,Wh,kWh)                                                      </td></tr>
          <tr><td> <b>capacity</b> </td><td>Rated power of the inverter according to data sheet (max. possible output in watts)    </td></tr>
        </table>
      </ul>
      <br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; currentInverterDev STP5000 pv=total_pac:kW etotal=etotal:kWh capacity=5000 <br>
        <br>
        # Device STP5000 provides PV values. The current generated power in the reading "total_pac" (kW) and the daily generation in the reading "etotal" (kWh).
          The maximum power of the inverter is 5000 Watt.
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentMeterDev"></a>
      <li><b>currentMeterDev &lt;Meter Device Name&gt; gcon=&lt;Readingname&gt;:&lt;Unit&gt; contotal=&lt;Readingname&gt;:&lt;Unit&gt; gfeedin=&lt;Readingname&gt;:&lt;Unit&gt; feedtotal=&lt;Readingname&gt;:&lt;Unit&gt;   </b> <br><br>

      Sets any device and its readings for energy measurement.
      The module assumes that the numeric value of the readings is positive.
      It can also be a dummy device with corresponding readings. The meaning of the respective "Readingname" is:
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>gcon</b>       </td><td>Reading welches die aktuell aus dem Netz bezogene Leistung liefert                                          </td></tr>
          <tr><td> <b>contotal</b>   </td><td>Reading welches die Summe der aus dem Netz bezogenen Energie liefert (ein sich stetig erhöhender Zähler)    </td></tr>
          <tr><td> <b>gfeedin</b>    </td><td>Reading welches die aktuell in das Netz eingespeiste Leistung liefert                                       </td></tr>
          <tr><td> <b>feedtotal</b>  </td><td>Reading welches die Summe der in das Netz eingespeisten Energie liefert (ein sich stetig erhöhender Zähler) </td></tr>
          <tr><td> <b>Einheit</b>    </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                                                         </td></tr>
        </table>
      </ul>
      <br>

      <b>Special cases:</b> If the reading for gcon and gfeedin should be identical but signed,
      the keys gfeedin and gcon can be defined as follows: <br><br>
      <ul>
        gfeedin=-gcon  &nbsp;&nbsp;&nbsp;(a negative value of gcon is used as gfeedin)  <br>
        gcon=-gfeedin  &nbsp;&nbsp;&nbsp;(a negative value of gfeedin is used as gcon)
      </ul>
      <br>

      The unit is omitted in the particular special case. <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; currentMeterDev Meter gcon=Wirkleistung:W contotal=BezWirkZaehler:kWh gfeedin=-gcon feedtotal=EinWirkZaehler:kWh   <br>
        <br>
        # Device Meter provides the current grid reference in the reading "Wirkleistung" (W),
          the sum of the grid reference in the reading "BezWirkZaehler" (kWh), the current feed in "Wirkleistung" if "Wirkleistung" is negative,
          the sum of the feed in the reading "EinWirkZaehler". (kWh)
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentRadiationAPI"></a>
      <li><b>currentRadiationAPI </b> <br><br>

      Defines the source for the delivery of the solar radiation data. You can select a device of the type DWD_OpenData or
      an implemented API can be selected. <br><br>

      <b>SolCast-API</b> <br>

      API usage requires one or more API-keys (accounts) and one or more Rooftop-ID's in advance
      created on the <a href='https://toolkit.solcast.com.au/rooftop-sites/' target='_blank'>SolCast</a> website.
      A rooftop is equivalent to one <a href="#SolarForecast-set-inverterStrings">inverterString</a>
      in the SolarForecast context. <br>
      Free API usage is limited to one daily rate API requests. The number of defined strings (rooftops)
      increases the number of API requests required. The module optimizes the query cycles with the attribute
      <a href="#SolarForecast-attr-ctrlSolCastAPIoptimizeReq ">ctrlSolCastAPIoptimizeReq </a>.
      <br><br>

      <b>ForecastSolar-API</b> <br>

      Free use of the <a href='https://doc.forecast.solar/start' target='_blank'>Forecast.Solar API</a>.
      does not require registration. API requests are limited to 12 within one hour in the free version.
      There is no daily limit. The module automatically determines the optimal query interval
      depending on the configured strings.
      <br><br>

      <b>VictronKI-API</b> <br>

      This API can be applied by users of the Victron Energy VRM Portal. This API is AI based.
      As string the value "AI-based" has to be entered in the setup of the
      <a href="#SolarForecast-set-inverterStrings">inverterStrings</a>. <br>
      In the Victron Energy VRM Portal, the location of the PV system must be specified as a prerequisite. <br>
      See also the blog post
      <a href="https://www.victronenergy.com/blog/2023/07/05/new-vrm-solar-production-forecast-feature/">Introducing Solar Production Forecast</a>.
      <br><br>

      <b>DWD_OpenData Device</b> <br>

      The DWD service is integrated via a FHEM device of type DWD_OpenData.
      If there is no device of type DWD_OpenData yet, it must be defined in advance
      (look at <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      To obtain a good radiation forecast, a DWD station located near the plant site should be used. <br>
      Unfortunately, not all
      <a href="https://www.dwd.de/DE/leistungen/klimadatendeutschland/statliste/statlex_html.html;jsessionid=EC5F572A52EB69684D552DCF6198F290.live31092?view=nasPublication&nn=16102">DWD stations</a>
      provide the required Rad1h values. <br>
      Explanations of the stations are listed in
      <a href="https://www.dwd.de/DE/leistungen/klimadatendeutschland/stationsliste.html">Stationslexikon</a>. <br>
      At least the following attributes must be set in the selected DWD_OpenData Device: <br><br>

      <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                                                             </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>Rad1h                                                                                         </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                                                             </td></tr>
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Station code of the evaluated DWD station&gt;                                             </td></tr>
            <tr><td>                                </td><td><b>Note:</b> The selected DWD station must provide radiation values (Rad1h Readings).         </td></tr>
            <tr><td>                                </td><td>Not all stations provide this data!                                                           </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-energyH4Trigger"></a>
      <li><b>energyH4Trigger &lt;1on&gt;=&lt;Value&gt; &lt;1off&gt;=&lt;Value&gt; [&lt;2on&gt;=&lt;Value&gt; &lt;2off&gt;=&lt;Value&gt; ...] </b> <br><br>

      Generates triggers on exceeding or falling below the 4-hour PV forecast (NextHours_Sum04_PVforecast). <br>
      Überschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xon-Bedingung</b>, wird das Reading
      <b>energyH4Trigger_X = on</b> erstellt/gesetzt.
      If the last three measurements of the 4-hour PV predictions exceed a defined <b>Xon condition</b>,
      the Reading <b>energyH4Trigger_X = off</b> is created/set. <br>
      Any number of trigger conditions can be specified.
      Xon/Xoff conditions do not necessarily have to be defined in pairs. <br>
      <br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; energyH4Trigger 1on=2000 1off=1700 2on=2500 2off=2000 3off=1500 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-inverterStrings"></a>
      <li><b>inverterStrings &lt;Stringname1&gt;[,&lt;Stringname2&gt;,&lt;Stringname3&gt;,...] </b> <br><br>

      Designations of the active strings. These names are used as keys in the further
      settings. <br>
      When using an AI based API (e.g. VictronKI API) only "<b>KI-based</b>" has to be entered regardless of
      which real strings exist. <br><br>

      <ul>
        <b>Examples: </b> <br>
        set &lt;name&gt; inverterStrings eastroof,southgarage,S3 <br>
        set &lt;name&gt; inverterStrings KI-based <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-modulePeakString"></a>
      <li><b>modulePeakString &lt;Stringname1&gt;=&lt;Peak&gt; [&lt;Stringname2&gt;=&lt;Peak&gt; &lt;Stringname3&gt;=&lt;Peak&gt; ...] </b> <br><br>

      The DC peak power of the string "StringnameX" in kWp. The string name is a key value of the
      Reading <b>inverterStrings</b>. <br>
      When using an AI-based API (e.g. Model VictronKiAPI), the peak powers of all existing strings are to be assigned as
      a sum to the string name <b>KI-based</b>. <br><br>

      <ul>
        <b>Examples: </b> <br>
        set &lt;name&gt; modulePeakString eastroof=5.1 southgarage=2.0 S3=7.2 <br>
        set &lt;name&gt; modulePeakString KI-based=14.3 (for AI based API)<br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleDirection"></a>
      <li><b>moduleDirection &lt;Stringname1&gt;=&lt;dir&gt; [&lt;Stringname2&gt;=&lt;dir&gt; &lt;Stringname3&gt;=&lt;dir&gt; ...] </b> <br>
      (only model DWD, ForecastSolarAPI) <br><br>

      Alignment &lt;dir&gt; of the solar modules in the string "StringnameX". The string name is a key value of the
      <b>inverterStrings</b> reading. <br>
      The direction specification &lt;dir&gt; can be specified as an azimuth identifier or as an azimuth value: <br><br>

      <ul>
         <table>
         <colgroup> <col width="30%"> <col width="20%"> <col width="50%"> </colgroup>
            <tr><td> <b>Identifier</b></td><td><b>Azimuth</b></td><td>                            </td></tr>
            <tr><td> N                </td><td>-180          </td><td>North orientation           </td></tr>
            <tr><td> NE               </td><td>-135          </td><td>North-East orientation      </td></tr>
            <tr><td> E                </td><td>-90           </td><td>East orientation            </td></tr>
            <tr><td> SE               </td><td>-45           </td><td>South-east orientation      </td></tr>
            <tr><td> S                </td><td>0             </td><td>South orientation           </td></tr>
            <tr><td> SW               </td><td>45            </td><td>South-west orientation      </td></tr>
            <tr><td> W                </td><td>90            </td><td>West orientation            </td></tr>
            <tr><td> NW               </td><td>135           </td><td>North-West orientation      </td></tr>
         </table>
      </ul>
      <br>

      Azimuth values are integers in the range -180 to 180. Azimuth intermediate values that do not exactly match an
      identifier are abstracted to the nearest identifier if the selected API works with identifiers only.
      The module uses the more accurate azimuth value if the API supports its use, e.g. the
      ForecastSolar API.
      <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; moduleDirection eastroof=-90 southgarage=S S3=NW <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleRoofTops"></a>
      <li><b>moduleRoofTops &lt;Stringname1&gt;=&lt;pk&gt; [&lt;Stringname2&gt;=&lt;pk&gt; &lt;Stringname3&gt;=&lt;pk&gt; ...] </b> <br>
      (only when using Model SolCastAPI) <br><br>

      The string "StringnameX" is assigned to a key &lt;pk&gt;. The key &lt;pk&gt; was created with the setter
      <a href="#SolarForecast-set-roofIdentPair">roofIdentPair</a>. This is used to specify the rooftop ID and API key to
      be used in the SolCast API.  <br>
      The string nameX is a key value of the reading <b>inverterStrings</b>.
      <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; moduleRoofTops eastroof=p1 southgarage=p2 S3=p3 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleTiltAngle"></a>
      <li><b>moduleTiltAngle &lt;Stringname1&gt;=&lt;Angle&gt; [&lt;Stringname2&gt;=&lt;Angle&gt; &lt;Stringname3&gt;=&lt;Angle&gt; ...] </b> <br>
      (only model DWD, ForecastSolarAPI) <br><br>

      Tilt angle of the solar modules. The string name is a key value of the reading <b>inverterStrings</b>. <br>
      Possible angles of inclination are: 0,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90
      (0 = horizontal, 90 = vertical). <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; moduleTiltAngle eastroof=40 southgarage=60 S3=30 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-operatingMemory"></a>
      <li><b>operatingMemory backup | save | recover-&lt;File&gt; </b> <br><br>

      The pvHistory (PVH) and pvCircular (PVC) components of the internal cache database are stored in the file system. <br>
      The target directory is "../FHEM/FhemUtils". This process is carried out regularly by the module in the background.  <br><br>

      <ul>
         <table>
         <colgroup> <col width="17%"> <col width="83%"> </colgroup>
            <tr><td> <b>backup</b>               </td><td>Saves the active in-memory structures with the current timestamp.                                                                          </td></tr>
            <tr><td>                             </td><td><a href="#SolarForecast-attr-ctrlBackupFilesKeep">ctrlBackupFilesKeep</a> generations of the files are saved. Older versions are deleted.  </td></tr>
            <tr><td>                             </td><td>Files: PVH_SolarForecast_&lt;name&gt;_&lt;Timestamp&gt;, PVC_SolarForecast_&lt;name&gt;_&lt;Timestamp&gt;                                  </td></tr>
            <tr><td>                             </td><td>                                                                                                                                           </td></tr>
            <tr><td> <b>save</b>                 </td><td>The active in-memory structures are saved.                                                                                                 </td></tr>
            <tr><td>                             </td><td>Files: PVH_SolarForecast_&lt;name&gt;, PVC_SolarForecast_&lt;name&gt;                                                                      </td></tr>
            <tr><td>                             </td><td>                                                                                                                                           </td></tr>
            <tr><td> <b>recover-&lt;File&gt;</b> </td><td>Restores the data of the selected backup file as an active in-memory structure.                                                            </td></tr>
            <tr><td>                             </td><td>To avoid inconsistencies, the PVH.* and PVC.* files should be restored in pairs                                                            </td></tr>
            <tr><td>                             </td><td>with the same time stamp.                                                                                                                  </td></tr>
         </table>
      </ul>
      <br>
    </ul>
    </li>
    <br>

    <ul>
      <a id="SolarForecast-set-operationMode"></a>
      <li><b>operationMode  </b> <br><br>
      The SolarForecast device is deactivated with <b>inactive</b>. The <b>active</b> option reactivates the device.
      The behavior corresponds to the "disable" attribute, but is particularly suitable for use in Perl scripts as
      compared to the "disable" attribute, it is not necessary to save the device configuration.
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-plantConfiguration"></a>
      <li><b>plantConfiguration </b> <br><br>

      Depending on the selected command option, the following operations are performed: <br><br>

      <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>check</b>     </td><td>Checks the current plant configuration. A plausibility check                  </td></tr>
            <tr><td>                  </td><td>is performed and the result and any notes or errors are output.               </td></tr>
            <tr><td> <b>save</b>      </td><td>Secures important parameters of the plant configuration                       </td></tr>
            <tr><td> <b>restore</b>   </td><td>Restores a saved plant configuration                                          </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-powerTrigger"></a>
      <li><b>powerTrigger &lt;1on&gt;=&lt;Value&gt; &lt;1off&gt;=&lt;Value&gt; [&lt;2on&gt;=&lt;Value&gt; &lt;2off&gt;=&lt;Value&gt; ...] </b> <br><br>

      Generates triggers when certain PV generation values (Current_PV) are exceeded or not reached. <br>
      If the last three measurements of PV generation exceed a defined <b>Xon condition</b>, the Reading
      <b>powerTrigger_X = on</b> is created/set.
      If the last three measurements of the PV generation fall below a defined <b>Xoff-Bedingung</b>, the Reading
      <b>powerTrigger_X = off</b> is created/set.
      <br>
      Any number of trigger conditions can be specified. Xon/Xoff conditions do not necessarily have to be defined in pairs.
      <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; powerTrigger 1on=1000 1off=500 2on=2000 2off=1000 3on=1600 4off=1100<br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-pvCorrectionFactor_Auto"></a>
      <li><b>pvCorrectionFactor_Auto </b> <br><br>

      Switches the automatic prediction correction on/off.
      The mode of operation differs depending on the selected method.
      The correction behaviour can be influenced with the <a href="#SolarForecast-attr-affectNumHistDays">affectNumHistDays</a>
      and <a href="#SolarForecast-attr-affectMaxDayVariance">affectMaxDayVariance</a> attributes. <br>
      (default: off)

      <br><br>

      <b>on_simple(_ai):</b> <br>
      In this method, the hourly predicted amount of energy is compared with the real amount of energy generated and a
      correction factor used for the future for the respective hour. The forecast data provided by the selected API is
      <b>not</b> additionally related to other conditions such as cloud cover or temperatures. <br>
      If the AI support is switched on (on_simple_ai) and a PV forecast value is supplied by the AI, this value is used
      instead of the API value.
      <br><br>

      <b>on_complex(_ai):</b> <br>
      In this method, the hourly predicted amount of energy is compared with the real amount of energy generated and a
      correction factor used for the future for the respective hour. The forecast data provided by the selected API is
      also additionally linked to other conditions such as cloud cover or temperatures. <br>
      If AI support is switched on (on_complex_ai) and a PV forecast value is provided by the AI, this value is used
      instead of the API value.
      <br><br>

      <b>Note:</b> The automatic prediction correction is learning and needs time to optimise the correction values.
      After activation, optimal predictions cannot be expected immediately!

      <br><br>

      Nhe following are some API-specific tips that are merely best practice recommendations.

      <br><br>

      <b>Model SolCastAPI:</b> <br>
      The recommended autocorrection method is <b>on_simple</b>. <br>
      Before turning on autocorrection, optimise the forecast with the following steps: <br><br>
      <ul>
         <li>
         In the RoofTop editor of the SolCast API, define the
         <a href="https://articles.solcast.com.au/en/articles/2959798-what-is-the-efficiency-factor?_ga=2.119610952.1991905456.1665567573-1390691316.1665567573"><b>efficiency factor</b></a>
         according to the age of the plant. <br>
         With an 8-year-old plant, it would be 84 (100 - (8 x 2%)). <br>
         </li>
         <li>
         after sunset, the Reading Today_PVdeviation is created, which shows the deviation between the forecast and the real
         PV generation in percent.
         </li>
         </li>
         <li>
         according to the deviation, adjust the efficiency factor in steps until an optimum is found, i.e. the smallest
         daily deviation is found
         </li>
         <li>
         If you think you have found the optimal setting, you can set pvCorrectionFactor_Auto on*.
         </li>
      </ul>
      <br>

      Ideally, this process is carried out in a phase of stable meteorological conditions (uniform sun or cloud cover).
      cloud cover).
      <br><br>

      <b>Model VictronKiAPI:</b> <br>
      This model is based on Victron Energy's AI-supported API.
      Additional autocorrection is not recommended, i.e. the recommended autocorrection method is <b>off</b>. <br><br>

      <b>Model DWD:</b> <br>
      The recommended autocorrection method is <b>on_complex</b> or <b>on_complex_ai</b>. <br><br>

      <b>Model ForecastSolarAPI:</b> <br>
      The recommended autocorrection method is <b>on_complex</b>.
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-pvCorrectionFactor_" data-pattern="pvCorrectionFactor_.*"></a>
      <li><b>pvCorrectionFactor_XX &lt;Zahl&gt; </b> <br><br>

      Manual correction factor for hour XX of the day to adjust the forecast to the individual installation. <br>
      (default: 1.0)
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-reset"></a>
      <li><b>reset </b> <br><br>

       Deletes the data source selected from the drop-down list, readings belonging to the function or other internal
       data structures. <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>aiData</b>             </td><td>deletes an existing AI instance including all training data and reinitialises it                                        </td></tr>
            <tr><td> <b>batteryTriggerSet</b>  </td><td>deletes the trigger points of the battery storage                                                                       </td></tr>
            <tr><td> <b>consumerPlanning</b>   </td><td>deletes the planning data of all registered consumers                                                                   </td></tr>
            <tr><td>                           </td><td>To delete the planning data of only one consumer, use:                                                                  </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerPlanning &lt;Consumer number&gt; </ul>                                               </td></tr>
            <tr><td>                           </td><td>The module carries out an automatic rescheduling of the consumer circuit.                                               </td></tr>
            <tr><td> <b>consumerMaster</b>     </td><td>deletes the data of all registered consumers from the memory                                                            </td></tr>
            <tr><td>                           </td><td>To delete the data of only one consumer use:                                                                            </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerMaster &lt;Consumer number&gt; </ul>                                                 </td></tr>
            <tr><td> <b>consumption</b>        </td><td>deletes the stored consumption values of the house                                                                      </td></tr>
            <tr><td>                           </td><td>To delete the consumption values of a specific day:                                                                     </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumption &lt;Day&gt;   (e.g. set &lt;name&gt; reset consumption 08) </ul>                 </td></tr>
            <tr><td>                           </td><td>To delete the consumption values of a specific hour of a day:                                                           </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumption &lt;Day&gt; &lt;Hour&gt; (e.g. set &lt;name&gt; reset consumption 08 10) </ul>   </td></tr>
            <tr><td> <b>currentBatterySet</b>  </td><td>deletes the set battery device and corresponding data.                                                                  </td></tr>
            <tr><td> <b>currentInverterSet</b> </td><td>deletes the set inverter device and corresponding data.                                                                 </td></tr>
            <tr><td> <b>currentMeterSet</b>    </td><td>deletes the set meter device and corresponding data.                                                                    </td></tr>
            <tr><td> <b>energyH4TriggerSet</b> </td><td>deletes the 4-hour energy trigger points                                                                                </td></tr>
            <tr><td> <b>inverterStringSet</b>  </td><td>deletes the string configuration of the installation                                                                    </td></tr>
            <tr><td> <b>powerTriggerSet</b>    </td><td>deletes the trigger points for PV generation values                                                                     </td></tr>
            <tr><td> <b>pvCorrection</b>       </td><td>deletes the readings pvCorrectionFactor*                                                                                </td></tr>
            <tr><td>                           </td><td>To delete all previously stored PV correction factors from the caches:                                                  </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection cached </ul>                                                                    </td></tr>
            <tr><td>                           </td><td>To delete stored PV correction factors of a certain hour from the caches:                                               </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection cached &lt;Hour&gt;  </ul>                                                      </td></tr>
            <tr><td>                           </td><td><ul>(e.g. set &lt;name&gt; reset pvCorrection cached 10)       </ul>                                                    </td></tr>
            <tr><td> <b>pvHistory</b>          </td><td>deletes the memory of all historical days (01 ... 31)                                                                   </td></tr>
            <tr><td>                           </td><td>To delete a specific historical day:                                                                                    </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Day&gt;   (e.g. set &lt;name&gt; reset pvHistory 08) </ul>                     </td></tr>
            <tr><td>                           </td><td>To delete a specific hour of a historical day:                                                                          </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Day&gt; &lt;Hour&gt;  (e.g. set &lt;name&gt; reset pvHistory 08 10) </ul>      </td></tr>
            <tr><td> <b>moduleRoofTopSet</b>   </td><td>deletes the SolCast API Rooftops                                                                                        </td></tr>
            <tr><td> <b>roofIdentPair</b>      </td><td>deletes all saved SolCast API Rooftop ID / API Key pairs.                                                               </td></tr>
            <tr><td>                           </td><td>To delete a specific pair, specify its key &lt;pk&gt;:                                                                  </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset roofIdentPair &lt;pk&gt;   (e.g. set &lt;name&gt; reset roofIdentPair p1) </ul>              </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-roofIdentPair"></a>
      <li><b>roofIdentPair &lt;pk&gt; rtid=&lt;Rooftop-ID&gt; apikey=&lt;SolCast API Key&gt; </b> <br>
       (only when using Model SolCastAPI) <br><br>

       The retrieval of each rooftop created in
       <a href='https://toolkit.solcast.com.au/rooftop-sites' target='_blank'>SolCast Rooftop Sites</a> is to be identified
       by specifying a pair <b>Rooftop-ID</b> and <b>API-Key</b>. <br>
       The key &lt;pk&gt; uniquely identifies a linked Rooftop ID / API key pair. Any number of pairs can be created
       <b>one after the other</b>. In that case, a new name for "&lt;pk&gt;" is to be used in each case.
       <br><br>

       The key &lt;pk&gt; is assigned in the setter <a href="#SolarForecast-set-moduleRoofTops">moduleRoofTops</a> to the
       Rooftops (=Strings) to be retrieved.
       <br><br>

       <ul>
        <b>Examples: </b> <br>
        set &lt;name&gt; roofIdentPair p1 rtid=92fc-6796-f574-ae5f apikey=oNHDbkKuC_eGEvZe7ECLl6-T1jLyfOgC <br>
        set &lt;name&gt; roofIdentPair p2 rtid=f574-ae5f-92fc-6796 apikey=eGEvZe7ECLl6_T1jLyfOgC_oNHDbkKuC <br>
       </ul>

        <br>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-vrmCredentials"></a>
      <li><b>vrmCredentials user=&lt;Benutzer&gt; pwd=&lt;Paßwort&gt; idsite=&lt;idSite&gt; </b> <br>
      (only when using Model VictronKiAPI) <br><br>

       If the Victron VRM API is used, the required access data must be stored with this set command. <br><br>

      <ul>
         <table>
         <colgroup> <col width="10%"> <col width="90%"> </colgroup>
            <tr><td> <b>user</b>   </td><td>Username for the Victron VRM Portal                                              </td></tr>
            <tr><td> <b>pwd</b>    </td><td>Password for access to the Victron VRM Portal                                    </td></tr>
            <tr><td> <b>idsite</b> </td><td>idSite is the identifier "XXXXXX" in the Victron VRM Portal Dashboard URL.       </td></tr>
            <tr><td>               </td><td>URL of the Victron VRM Dashboard:                                                </td></tr>
            <tr><td>               </td><td>https://vrm.victronenergy.com/installation/<b>XXXXXX</b>/dashboard               </td></tr>
         </table>
      </ul>
      <br>

      To delete the stored credentials, only the argument <b>delete</b> must be passed to the command. <br><br>

       <ul>
        <b>Examples: </b> <br>
        set &lt;name&gt; vrmCredentials user=john@example.com pwd=somepassword idsite=212008 <br>
        set &lt;name&gt; vrmCredentials delete <br>
       </ul>

      </li>
    </ul>
    <br>

  </ul>
  <br>

  <a id="SolarForecast-get"></a>
  <b>Get</b>
  <ul>
    <ul>
      <a id="SolarForecast-get-data"></a>
      <li><b>data </b> <br><br>
      Starts data collection to determine the solar forecast and other values.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-forecastQualities"></a>
      <li><b>forecastQualities </b> <br><br>
      Shows the correction factors currently used to determine the PV forecast with the respective start time and the
      average forecast quality achieved so far for this period.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-ftuiFramefiles"></a>
      <li><b>ftuiFramefiles </b> <br><br>
      SolarForecast provides widgets for
      <a href='https://wiki.fhem.de/wiki/FHEM_Tablet_UI' target='_blank'>FHEM Tablet UI v2 (FTUI2)</a>. <br>
      If FTUI2 is installed on the system, the files for the framework can be loaded into the FTUI directory structure
      with this command. <br>
      The setup and use of the widgets is described in Wiki
      <a href='https://wiki.fhem.de/wiki/SolarForecast_FTUI_Widget' target='_blank'>SolarForecast FTUI Widget</a>.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-html"></a>
      <li><b>html </b> <br><br>
      The SolarForecast graphic is retrieved and displayed as HTML code. <br>
      <b>Note:</b> By the attribute <a href="#SolarForecast-attr-graphicHeaderOwnspec">graphicHeaderOwnspec</a>
      generated set or attribute commands in the user-specific area of the header are generally hidden for technical
      reasons. <br>
      One of the following selections can be given as an argument to the command:
      <br><br>

      <ul>
        <table>
        <colgroup> <col width="30%"> <col width="70%"> </colgroup>
        <tr><td> <b>both</b>                    </td><td>displays the header, consumer legend, energy flow graph and forecast graph (default)       </td></tr>
        <tr><td> <b>both_noHead</b>             </td><td>displays the consumer legend, energy flow graph and forecast graph                         </td></tr>
        <tr><td> <b>both_noCons</b>             </td><td>displays the header, energy flow and prediction graphic                                    </td></tr>
        <tr><td> <b>both_noHead_noCons</b>      </td><td>displays energy flow and prediction graphs                                                 </td></tr>
        <tr><td> <b>flow</b>                    </td><td>displays the header, the consumer legend and energy flow graphic                           </td></tr>
        <tr><td> <b>flow_noHead</b>             </td><td>displays the consumer legend and the energy flow graph                                     </td></tr>
        <tr><td> <b>flow_noCons</b>             </td><td>displays the header and the energy flow graph                                              </td></tr>
        <tr><td> <b>flow_noHead_noCons</b>      </td><td>displays the energy flow graph                                                             </td></tr>
        <tr><td> <b>forecast</b>                </td><td>displays the header, the consumer legend and the forecast graphic                          </td></tr>
        <tr><td> <b>forecast_noHead</b>         </td><td>displays the consumer legend and the forecast graph                                        </td></tr>
        <tr><td> <b>forecast_noCons</b>         </td><td>displays the header and the forecast graphic                                               </td></tr>
        <tr><td> <b>forecast_noHead_noCons</b>  </td><td>displays the forecast graph                                                                </td></tr>
        <tr><td> <b>none</b>                    </td><td>displays only the header and the consumer legend                                           </td></tr>
        </table>
      </ul>
      <br>

      The graphic can be retrieved and embedded in your own code. This can be done in a simple way by defining
      a weblink device: <br><br>

      <ul>
        define wl.SolCast5 weblink htmlCode { FHEM::SolarForecast::pageAsHtml ('SolCast5', '-', '&lt;argument&gt;') }
      </ul>
      <br>
      'SolCast5' is the name of the SolarForecast device to be included. <b>&lt;argument&gt;</b> is one of the above
      described selection options.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-nextHours"></a>
      <li><b>nextHours </b> <br><br>
      Lists the expected values for the coming hours. <br><br>

      <ul>
         <table>
         <colgroup> <col width="10%"> <col width="90%"> </colgroup>
            <tr><td> <b>aihit</b>     </td><td>delivery status of the AI for the PV forecast (0-no delivery, 1-delivery)       </td></tr>
            <tr><td> <b>confc</b>     </td><td>expected energy consumption including the shares of registered consumers        </td></tr>
            <tr><td> <b>confcEx</b>   </td><td>expected energy consumption without the shares of registered consumers          </td></tr>
            <tr><td> <b>crange</b>    </td><td>calculated cloud area                                                           </td></tr>
            <tr><td> <b>correff</b>   </td><td>correction factor/quality used                                                  </td></tr>
            <tr><td>                  </td><td>factor/- -> no quality defined                                                  </td></tr>
            <tr><td>                  </td><td>factor/0..1 - quality of the PV forecast (1 = best quality)                     </td></tr>
            <tr><td> <b>DoN</b>       </td><td>sunrise and sunset status (0 - night, 1 - day)                                  </td></tr>
            <tr><td> <b>hourofday</b> </td><td>current hour of the day                                                         </td></tr>
            <tr><td> <b>pvapifc</b>   </td><td>expected PV generation (Wh) of the used API incl. a possible correction         </td></tr>
            <tr><td> <b>pvaifc</b>    </td><td>expected PV generation of the AI (Wh)                                           </td></tr>
            <tr><td> <b>pvfc</b>      </td><td>PV generation forecast used (Wh)                                                </td></tr>
            <tr><td> <b>rad1h</b>     </td><td>predicted global radiation                                                      </td></tr>
            <tr><td> <b>rrange</b>    </td><td>calculated range of rain probability                                            </td></tr>
            <tr><td> <b>starttime</b> </td><td>start time of the record                                                        </td></tr>
            <tr><td> <b>temp</b>      </td><td>predicted outdoor temperature                                                   </td></tr>
            <tr><td> <b>today</b>     </td><td>has value '1' if start date on current day                                      </td></tr>
            <tr><td> <b>wrp</b>       </td><td>predicted degree of rain probability                                            </td></tr>
            <tr><td> <b>wid</b>       </td><td>ID of the predicted weather                                                     </td></tr>
            <tr><td> <b>wcc</b>       </td><td>predicted degree of cloudiness                                                  </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-pvHistory"></a>
      <li><b>pvHistory </b> <br><br>
      Shows the content of the pvHistory data memory sorted by date and hour. The selection list can be used to jump to a
      specific day. The drop-down list contains the days currently available in the memory.
      Without an argument, the entire data storage is listed.

      The hour specifications refer to the respective hour of the day, e.g. the hour 09 refers to the time from
      08 o'clock to 09 o'clock. <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>etotal</b>         </td><td>total energy yield (Wh) at the beginning of the hour                                                  </td></tr>
            <tr><td> <b>pvfc</b>           </td><td>the predicted PV yield (Wh)                                                                           </td></tr>
            <tr><td> <b>pvrl</b>           </td><td>real PV generation (Wh)                                                                               </td></tr>
            <tr><td> <b>pvrlvd</b>         </td><td>1-'pvrl' is valid and is taken into account in the learning process, 0-'pvrl' is assessed as abnormal </td></tr>
            <tr><td> <b>gcon</b>           </td><td>real power consumption (Wh) from the electricity grid                                                 </td></tr>
            <tr><td> <b>confc</b>          </td><td>expected energy consumption (Wh)                                                                      </td></tr>
            <tr><td> <b>con</b>            </td><td>real energy consumption (Wh) of the house                                                             </td></tr>
            <tr><td> <b>gfeedin</b>        </td><td>real feed-in (Wh) into the electricity grid                                                           </td></tr>
            <tr><td> <b>batintotal</b>     </td><td>total battery charge (Wh) at the beginning of the hour                                                </td></tr>
            <tr><td> <b>batin</b>          </td><td>Hour battery charge (Wh)                                                                              </td></tr>
            <tr><td> <b>batouttotal</b>    </td><td>total battery discharge (Wh) at the beginning of the hour                                             </td></tr>
            <tr><td> <b>batout</b>         </td><td>Battery discharge of the hour (Wh)                                                                    </td></tr>
            <tr><td> <b>batmaxsoc</b>      </td><td>maximum SOC (%) of the day                                                                            </td></tr>
            <tr><td> <b>batsetsoc</b>      </td><td>optimum SOC setpoint (%) for the day                                                                  </td></tr>
            <tr><td> <b>wid</b>            </td><td>Weather identification number                                                                         </td></tr>
            <tr><td> <b>wcc</b>            </td><td>effective cloud cover                                                                                 </td></tr>
            <tr><td> <b>wrp</b>            </td><td>Probability of precipitation > 0.1 mm during the respective hour                                      </td></tr>
            <tr><td> <b>pvcorrf</b>        </td><td>Autocorrection factor used / forecast quality achieved                                                </td></tr>
            <tr><td> <b>rad1h</b>          </td><td>global radiation (kJ/m2)                                                                              </td></tr>
            <tr><td> <b>csmtXX</b>         </td><td>total energy consumption of ConsumerXX                                                                </td></tr>
            <tr><td> <b>csmeXX</b>         </td><td>Energy consumption of ConsumerXX in the hour of the day (hour 99 = daily energy consumption)          </td></tr>
            <tr><td> <b>minutescsmXX</b>   </td><td>total active minutes in the hour of ConsumerXX                                                        </td></tr>
            <tr><td> <b>hourscsmeXX</b>    </td><td>average hours of an active cycle of ConsumerXX of the day                                             </td></tr>
            <tr><td> <b>cyclescsmXX</b>    </td><td>Number of active cycles of ConsumerXX of the day                                                      </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-pvCircular"></a>
      <li><b>pvCircular </b> <br><br>
      Lists the existing values in the ring buffer.
      The hours 01 - 24 refer to the hour of the day, e.g. the hour 09 refers to the time from
      08 - 09 o'clock. <br>
      Hour 99 has a special function. <br>
      Explanation of the values: <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>aihit</b>            </td><td>Delivery status of the AI for the PV forecast (0-no delivery, 1-delivery)                                             </td></tr>
            <tr><td> <b>batin</b>            </td><td>Battery charge (Wh)                                                                                                   </td></tr>
            <tr><td> <b>batout</b>           </td><td>Battery discharge (Wh)                                                                                                </td></tr>
            <tr><td> <b>batouttot</b>        </td><td>total energy drawn from the battery (Wh)                                                                              </td></tr>
            <tr><td> <b>batintot</b>         </td><td>total energy charged into the battery (Wh)                                                                            </td></tr>
            <tr><td> <b>confc</b>            </td><td>expected energy consumption (Wh)                                                                                      </td></tr>
            <tr><td> <b>corr</b>             </td><td>Autocorrection factors for the hour of the day, where "percentile" is the simple correction factor.                   </td></tr>
            <tr><td> <b>days2care</b>        </td><td>remaining days until the battery maintenance SoC (default 95%) is reached                                             </td></tr>
            <tr><td> <b>feedintotal</b>      </td><td>total PV energy fed into the public grid (Wh)                                                                         </td></tr>
            <tr><td> <b>gcon</b>             </td><td>real power drawn from the electricity grid                                                                            </td></tr>
            <tr><td> <b>gfeedin</b>          </td><td>real power feed-in to the electricity grid                                                                            </td></tr>
            <tr><td> <b>gridcontotal</b>     </td><td>total energy drawn from the public grid (Wh)                                                                          </td></tr>
            <tr><td> <b>initdayfeedin</b>    </td><td>initial PV feed-in value at the beginning of the current day (Wh)                                                     </td></tr>
            <tr><td> <b>initdaygcon</b>      </td><td>initial grid reference value at the beginning of the current day (Wh)                                                 </td></tr>
            <tr><td> <b>initdaybatintot</b>  </td><td>initial value of the total energy charged into the battery at the beginning of the current day. (Wh)                  </td></tr>
            <tr><td> <b>initdaybatouttot</b> </td><td>initial value of the total energy drawn from the battery at the beginning of the current day. (Wh)                    </td></tr>
            <tr><td> <b>lastTsMaxSocRchd</b> </td><td>Timestamp of last achievement of battery SoC >= maxSoC (default 95%)                                                  </td></tr>
            <tr><td> <b>nextTsMaxSocChge</b> </td><td>Timestamp by which the battery should reach maxSoC at least once                                                      </td></tr>
            <tr><td> <b>pvapifc</b>          </td><td>expected PV generation (Wh) of the API used                                                                           </td></tr>
            <tr><td> <b>pvaifc</b>           </td><td>PV forecast (Wh) of the AI for the next 24h from the current hour of the day                                          </td></tr>
            <tr><td> <b>pvfc</b>             </td><td>PV forecast used for the next 24h from the current hour of the day                                                    </td></tr>
            <tr><td> <b>pvrl</b>             </td><td>real PV generation of the last 24h (Attention: pvforecast and pvreal do not refer to the same period!)                </td></tr>
            <tr><td> <b>quality</b>          </td><td>Quality of the autocorrection factors (0..1), where "percentile" is the quality of the simple correction factor.      </td></tr>
            <tr><td> <b>runTimeTrainAI</b>   </td><td>Duration of the last AI training                                                                                      </td></tr>
            <tr><td> <b>tdayDvtn</b>         </td><td>Today's deviation PV forecast/generation in %                                                                         </td></tr>
            <tr><td> <b>temp</b>             </td><td>Outdoor temperature                                                                                                   </td></tr>
            <tr><td> <b>wcc</b>              </td><td>Degree of cloud cover                                                                                                 </td></tr>
            <tr><td> <b>wrp</b>              </td><td>Degree of probability of rain                                                                                         </td></tr>
            <tr><td> <b>wid</b>              </td><td>ID of the predicted weather                                                                                           </td></tr>
            <tr><td> <b>wtxt</b>             </td><td>Description of the predicted weather                                                                                  </td></tr>
            <tr><td> <b>ydayDvtn</b>         </td><td>Deviation PV forecast/generation in % on the previous day                                                             </td></tr>
         </table>
      </ul>

      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-rooftopData"></a>
      <li><b>rooftopData </b> <br><br>
      The expected solar radiation data or PV generation data are retrieved from the selected API.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-solApiData"></a>
      <li><b>solApiData </b> <br><br>

      Lists the data stored in the context of the API call.
      Administrative records are marked with a leading '?
      The predicted PV yield (Wh) data provided by the API is consolidated to one hour.
      <br><br>

      <ul>
         <table>
         <colgroup> <col width="37%"> <col width="63%"> </colgroup>
            <tr><td> <b>currentAPIinterval</b>        </td><td>the currently used API retrieval interval in seconds            </td></tr>
            <tr><td> <b>lastretrieval_time</b>        </td><td>Time of the last API call                                       </td></tr>
            <tr><td> <b>lastretrieval_timestamp</b>   </td><td>Unix timestamp of the last API call                             </td></tr>
            <tr><td> <b>pv_estimate</b>               </td><td>expected PV generation (Wh)                                     </td></tr>
            <tr><td> <b>todayDoneAPIrequests</b>      </td><td>Number of executed API requests on the current day              </td></tr>
            <tr><td> <b>todayRemainingAPIrequests</b> </td><td>Number of remaining SolCast API requests on the current day     </td></tr>
            <tr><td> <b>todayDoneAPIcalls</b>         </td><td>Number of executed API calls on the current day                 </td></tr>
            <tr><td> <b>todayRemainingAPIcalls</b>    </td><td>Number of SolCast API calls still possible on the current day   </td></tr>
            <tr><td>                                  </td><td>(one call can execute several SolCast API requests)             </td></tr>
            <tr><td> <b>todayMaxAPIcalls</b>          </td><td>Maximum number of SolCast API calls per day                     </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valConsumerMaster"></a>
      <li><b>valConsumerMaster </b> <br><br>
      Shows the data of the consumers currently registered in the SolarForecast Device. <br>
      The drop-down list can be used to jump to a specific consumer. The drop-down list contains the consumers
      or consumer numbers currently available in the data memory.
      Without an argument, the entire data memory is listed.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valCurrent"></a>
      <li><b>valCurrent </b> <br><br>
      Lists current operating data, key figures and status.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valDecTree"></a>
      <li><b>valDecTree </b> <br><br>

      If AI support is activated in the SolarForecast Device, various AI-relevant data can be displayed                      :
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="20%"> <col width="80%"> </colgroup>
          <tr><td> <b>aiRawData</b>     </td><td>The PV, radiation and environmental data currently stored for the AI.           </td></tr>
          <tr><td> <b>aiRuleStrings</b> </td><td>Returns a list that describes the AI's decision tree in the form of rules.      </td></tr>
          <tr><td>                      </td><td><b>Note:</b> While the order of the rules is not predictable, the               </td></tr>
          <tr><td>                      </td><td>order of criteria within each rule, however, reflects the order                 </td></tr>
          <tr><td>                      </td><td>in which the criteria are considered in the decision-making process.            </td></tr>
        </table>
      </ul>
    </li>
    </ul>
    <br>

  </ul>
  <br>

  <a id="SolarForecast-attr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
     <ul>
       <a id="SolarForecast-attr-affect70percentRule"></a>
       <li><b>affect70percentRule</b><br>
         If set, the predicted power is limited according to the 70% rule. <br><br>

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>0</b>       </td><td>No limit on the forecast PV generation (default)                                </td></tr>
            <tr><td> <b>1</b>       </td><td>the predicted PV generation is limited to 70% of the installed string power(s)  </td></tr>
            <tr><td> <b>dynamic</b> </td><td>the predicted PV generation is limited when 70% of the installed                </td></tr>
            <tr><td>                </td><td>string(s) power plus the predicted consumption is exceeded.                     </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-affectBatteryPreferredCharge"></a>
       <li><b>affectBatteryPreferredCharge </b><br>
         Consumers with the <b>can</b> mode are only switched on when the specified battery charge (%)
         is reached. <br>
         Consumers with the <b>must</b> mode do not observe the priority charging of the battery. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-affectConsForecastInPlanning"></a>
       <li><b>affectConsForecastInPlanning </b><br>
         If set, the consumption forecast is also taken into account in addition to the PV forecast when scheduling the
         consumer. <br>
         Standard consumer planning is based on the PV forecast only. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-affectConsForecastIdentWeekdays"></a>
       <li><b>affectConsForecastIdentWeekdays </b><br>
         If set, only the same weekdays (Mon..Sun) are included in the calculation of the consumption forecast. <br>
         Otherwise, all weekdays are used equally for calculation. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-affectMaxDayVariance"></a>
       <li><b>affectMaxDayVariance &lt;Zahl&gt; </b><br>
         Maximum change size of the PV prediction factor (Reading pvCorrectionFactor_XX) per day. <br>
         This setting has no influence on the learning and forecasting behavior of any AI support used
         (<a href="#SolarForecast-set-pvCorrectionFactor_Auto">pvCorrectionFactor_Auto</a>). <br>
         (default: 0.5)
       </li>
       <br>

       <a id="SolarForecast-attr-affectNumHistDays"></a>
       <li><b>affectNumHistDays </b><br>
         Number of historical days available in the caches to be used to calculate the PV forecast autocorrection
         values. <br>
         (default: all available data in pvHistory and pvCircular)
       </li>
       <br>

       <a id="SolarForecast-attr-affectSolCastPercentile"></a>
       <li><b>affectSolCastPercentile &lt;10 | 50 | 90&gt; </b><br>
         (only when using Model SolCastAPI) <br><br>

         Selection of the probability range of the delivered SolCast data.
         SolCast provides the 10 and 90 percent probability around the forecast mean (50). <br>
         (default: 50)
       </li>
       <br>

        <a id="SolarForecast-attr-alias"></a>
        <li><b>alias </b> <br>
          In connection with "ctrlShowLink" any display name.
        </li>
        <br>

       <a id="SolarForecast-attr-consumerAdviceIcon"></a>
       <li><b>consumerAdviceIcon </b><br>
         Defines the type of information about the planned switching times of a consumer in the consumer legend.
         <br><br>
         <ul>
         <table>
         <colgroup> <col width="18%"> <col width="82%"> </colgroup>
            <tr><td> <b>&lt;Icon&gt@&lt;Colour&gt</b> </td><td>Activation recommendation is represented by icon and colour (optional) (default: light_light_dim_100@gold)  </td></tr>
            <tr><td>                                  </td><td>(the planning data is displayed as mouse-over text)                                                         </td></tr>
            <tr><td> <b>times</b>                     </td><td>the planning status and the planned switching times are displayed as text                                   </td></tr>
            <tr><td> <b>none</b>                      </td><td>no display of the planning data                                                                             </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-consumerLegend"></a>
       <li><b>consumerLegend </b><br>
         Defines the position or display mode of the load legend if loads are registered in the SolarForecast Device.
         <br>
         (default: icon_top)
       </li>
       <br>

       <a id="SolarForecast-attr-consumerLink"></a>
       <li><b>consumerLink </b><br>
         If set, you can click on the respective consumer in the consumer list (consumerLegend) and get
         directly to the detailed view of the respective device on a new browser page. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-consumer" data-pattern="consumer.*"></a>
       <li><b>consumerXX &lt;Device Name&gt; type=&lt;type&gt; power=&lt;power&gt; [switchdev=&lt;device&gt;]<br>
                         [mode=&lt;mode&gt;] [icon=&lt;Icon&gt;] [mintime=&lt;minutes&gt; | SunPath[:&lt;Offset_Sunrise&gt;:&lt;Offset_Sunset&gt;]]                             <br>
                         [on=&lt;command&gt;] [off=&lt;command&gt;] [swstate=&lt;Readingname&gt;:&lt;on-Regex&gt;:&lt;off-Regex&gt] [asynchron=&lt;Option&gt]                   <br>
                         [notbefore=&lt;Expression&gt;] [notafter=&lt;Expression&gt;] [locktime=&lt;offlt&gt;[:&lt;onlt&gt;]]                                                   <br>
                         [auto=&lt;Readingname&gt;] [pcurr=&lt;Readingname&gt;:&lt;Unit&gt;[:&lt;Threshold&gt]] [etotal=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Threshold&gt]] <br>
                         [swoncond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [swoffcond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [spignorecond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] <br>
                         [interruptable=&lt;Option&gt] [noshow=&lt;Option&gt] </b><br>
                         <br>

        Registers a consumer &lt;Device Name&gt; with the SolarForecast Device. In this case, &lt;Device Name&gt;
        is a consumer device already created in FHEM, e.g. a switchable socket.
        Most of the keys are optional, but are a prerequisite for certain functionalities and are filled with
        default values. <br>
        If the dish is defined "auto", the automatic mode in the integrated consumer graphic can be switched with the
        corresponding push-buttons. If necessary, the specified reading is created in the consumer device if
        it is not available. <br><br>

        With the optional key <b>swoncond</b>, an <b>additional external condition</b> can be defined to enable the
        switch-on process of the consumer.
        If the condition (Regex) is not fulfilled, the load is not switched on, even if the other conditions such as
        other conditions such as scheduling, on key, auto mode and current PV power are fulfilled. Thus, there is an
        <b>AND-link</b> of the key swoncond with the further switch-on conditions. <br><br>

        The optional key <b>swoffcond</b> defines a <b>priority switch-off condition</b> (Regex).
        As soon as this condition is fulfilled, the consumer is switched off even if the planned end time
        (consumerXX_planned_stop) has not yet been reached (<b>OR link</b>). Further conditions such as off key and auto mode must be
        be fulfilled for automatic switch-off. <br><br>

        With the optional <b>interruptable</b> key, an automatic
        interruption and reconnection of the consumer during the planned switch-on time.
        The load is temporarily switched off (interrupted) and switched on again (continued) when the
        interrupt condition is no longer present.
        The remaining runtime is not affected by an interrupt!
        <br><br>

        The <b>power</b> key indicates the nominal power consumption of the consumer according to its data sheet.
        This value is used to schedule the switching times of the load and to control the switching depending on
        the actual PV surplus at the time of scheduling.
        This value is used to schedule the switching times of the load and to control the switching depending on
        the actual PV surplus at the time of scheduling.
        <br><br>

         <ul>
         <table>
         <colgroup> <col width="12%"> <col width="88%"> </colgroup>
            <tr><td> <b>type</b>           </td><td>Type of consumer. The following types are allowed:                                                                                             </td></tr>
            <tr><td>                       </td><td><b>dishwasher</b>     - Consumer is a dishwasher                                                                                               </td></tr>
            <tr><td>                       </td><td><b>dryer</b>          - Consumer is a tumble dryer                                                                                             </td></tr>
            <tr><td>                       </td><td><b>washingmachine</b> - Consumer is a washing machine                                                                                          </td></tr>
            <tr><td>                       </td><td><b>heater</b>         - Consumer is a heating rod                                                                                              </td></tr>
            <tr><td>                       </td><td><b>charger</b>        - Consumer is a charging device (battery, car, bicycle, etc.)                                                            </td></tr>
            <tr><td>                       </td><td><b>other</b>          - Consumer is none of the above types                                                                                    </td></tr>
            <tr><td>                       </td><td><b>noSchedule</b>     - there is no scheduling or automatic switching for the consumer.                                                        </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                                                    Display functions or manual switching are available.                                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>power</b>          </td><td>nominal power consumption of the consumer (see data sheet) in W                                                                                </td></tr>
            <tr><td>                       </td><td>(can be set to "0")                                                                                                                            </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>switchdev</b>      </td><td>The specified &lt;device&gt; is assigned to the consumer as a switch device (optional). Switching operations are performed with this device.   </td></tr>
            <tr><td>                       </td><td>The key is useful for consumers where energy measurement and switching is carried out with different devices                                   </td></tr>
            <tr><td>                       </td><td>e.g. Homematic or readingsProxy. If switchdev is specified, the keys on, off, swstate, auto, asynchronous refer to this device.                </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>mode</b>           </td><td>Consumer planning mode (optional). Allowed are:                                                                                                </td></tr>
            <tr><td>                       </td><td><b>can</b>  - Scheduling takes place at the time when there is probably enough PV surplus available (default).                                 </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The consumer is not started at the time of planning if the PV surplus is insufficient.        </td></tr>
            <tr><td>                       </td><td><b>must</b> - The consumer is optimally planned, even if there will probably not be enough PV surplus.                                         </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; The load is started even if there is insufficient PV surplus, provided that
                                                    a set "swoncond" condition is met and "swoffcond" is not met.                                                                                  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>icon</b>           </td><td>Icon to represent the consumer in the overview graphic (optional)                                                                              </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>mintime</b>        </td><td>Scheduling duration (minutes or "SunPath") of the consumer. (optional)                                                                         </td></tr>
            <tr><td>                       </td><td>By specifying <b>SunPath</b>, planning is done according to sunrise and sunset.                                                                </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td>                       </td><td><b>SunPath</b>[:&lt;Offset_Sunrise&gt;:&lt;Offset_Sunset&gt;] - scheduling takes place from sunrise to sunset.                                 </td></tr>
            <tr><td>                       </td><td> Optionally, a positive / negative shift (minutes) of the planning time regarding sunrise or sunset can be specified.                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td>                       </td><td>If mintime is not specified, a standard scheduling duration according to the following table is used.                                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td>                       </td><td><b>Default mintime by consumer type:</b>                                                                                                       </td></tr>
            <tr><td>                       </td><td>- dishwasher: 180 minutes                                                                                                                      </td></tr>
            <tr><td>                       </td><td>- dryer: 90 minutes                                                                                                                            </td></tr>
            <tr><td>                       </td><td>- washingmachine: 120 minutes                                                                                                                  </td></tr>
            <tr><td>                       </td><td>- heater: 240 minutes                                                                                                                          </td></tr>
            <tr><td>                       </td><td>- charger: 120 minutes                                                                                                                         </td></tr>
            <tr><td>                       </td><td>- other: 60 minutes                                                                                                                            </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>on</b>             </td><td>Set command for switching on the consumer (optional)                                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>off</b>            </td><td>Set command for switching off the consumer (optional)                                                                                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>swstate</b>        </td><td>Reading which indicates the switching status of the consumer (default: 'state').                                                               </td></tr>
            <tr><td>                       </td><td><b>on-Regex</b> - regular expression for the state 'on' (default: 'on')                                                                        </td></tr>
            <tr><td>                       </td><td><b>off-Regex</b> - regular expression for the state 'off' (default: 'off')                                                                     </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>asynchron</b>      </td><td>the type of switching status determination in the consumer device. The status of the consumer is only determined after a switching command     </td></tr>.
            <tr><td>                       </td><td>by polling within a data collection interval (synchronous) or additionally by event processing (asynchronous).                                 </td></tr>
            <tr><td>                       </td><td><b>0</b> - only synchronous processing of switching states (default)                                                                           </td></tr>
            <tr><td>                       </td><td><b>1</b> - additional asynchronous processing of switching states through event processing                                                     </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>notbefore</b>      </td><td>Schedule start time consumer not before specified time 'hour[:minute]' (optional)                                                              </td></tr>
            <tr><td>                       </td><td>The &lt;Expression&gt; has the format hh[:mm] or is Perl code enclosed in {...} that returns hh[:mm].                                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>notafter</b>       </td><td>Schedule start time consumer not after specified time 'hour[:minute]' (optional)                                                               </td></tr>
            <tr><td>                       </td><td>The &lt;Expression&gt; has the format hh[:mm] or is Perl code enclosed in {...} that returns hh[:mm].                                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>auto</b>           </td><td>Reading in the consumer device which enables or blocks the switching of the consumer (optional)                                                </td></tr>
            <tr><td>                       </td><td>If the key switchdev is given, the reading is set and evaluated in this device.                                                                </td></tr>
            <tr><td>                       </td><td>Reading value = 1 - switching enabled (default), 0: switching blocked                                                                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>pcurr</b>          </td><td>Reading:Unit (W/kW) which provides the current energy consumption (optional)                                                                   </td></tr>
            <tr><td>                       </td><td>:&lt;Threshold&gt; (W) - From this power reference on, the consumer is considered active. The specification is optional (default: 0)           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>etotal</b>         </td><td>Reading:Unit (Wh/kWh) of the consumer device that supplies the sum of the consumed energy (optional)                                           </td></tr>
            <tr><td>                       </td><td>:&lt;Threshold&gt (Wh) - From this energy consumption per hour, the consumption is considered valid. Optional specification (default: 0)       </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>swoncond</b>       </td><td>Condition that must also be fulfilled in order to switch on the consumer (optional). The scheduled cycle is started.                           </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device to supply the additional switch-on condition                                                                            </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading for delivery of the additional switch-on condition                                                                    </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regular expression that must be satisfied for a 'true' condition to be true                                                     </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>swoffcond</b>      </td><td>priority condition to switch off the consumer (optional). The scheduled cycle is stopped.                                                      </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device to supply the priority switch-off condition                                                                             </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading for the delivery of the priority switch-off condition                                                                 </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regular expression that must be satisfied for a 'true' condition to be true                                                     </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>spignorecond</b>   </td><td>Condition to ignore a missing PV surplus (optional). If the condition is fulfilled, the load is switched on according to                       </td></tr>
            <tr><td>                       </td><td>the planning even if there is no PV surplus at the time.                                                                                       </td></tr>
            <tr><td>                       </td><td><b>CAUTION:</b> Using both keys <I>spignorecond</I> and <I>interruptable</I> can lead to undesired behaviour!                                  </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device to deliver the condition                                                                                                </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading which contains the condition                                                                                          </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regular expression that must be satisfied for a 'true' condition to be true                                                     </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>interruptable</b>  </td><td>defines the possible interruption options for the consumer after it has been started (optional)                                                </td></tr>
            <tr><td>                       </td><td><b>0</b> - Load is not temporarily switched off even if the PV surplus falls below the required energy (default)                               </td></tr>
            <tr><td>                       </td><td><b>1</b> - Load is temporarily switched off if the PV surplus falls below the required energy                                                  </td></tr>
            <tr><td>                       </td><td><b>Device:Reading:Regex[:Hysteresis]</b> - Load is temporarily interrupted if the value of the specified                                       </td></tr>
            <tr><td>                       </td><td>Device:Readings match on the regex or if is insufficient PV surplus (if power not equal to 0).                                                 </td></tr>
            <tr><td>                       </td><td>If the value no longer matches, the interrupted load is switched on again if there is sufficient                                               </td></tr>
            <tr><td>                       </td><td>PV surplus provided (if power is not 0).                                                                                                       </td></tr>
            <tr><td>                       </td><td>If the optional <b>hysteresis</b> is specified, the hysteresis value is subtracted from the reading value and the regex is then applied.       </td></tr>
            <tr><td>                       </td><td>If this and the original reading value match, the consumer is temporarily interrupted.                                                         </td></tr>
            <tr><td>                       </td><td>The consumer is continued if both the original and the subtracted readings value do not (or no longer) match.                                  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>locktime</b>       </td><td>Blocking times in seconds for switching the consumer (optional).                                                                               </td></tr>
            <tr><td>                       </td><td><b>offlt</b> - Blocking time in seconds after the consumer has been switched off or interrupted                                                </td></tr>
            <tr><td>                       </td><td><b>onlt</b> - Blocking time in seconds after the consumer has been switched on or continued                                                    </td></tr>
            <tr><td>                       </td><td>The consumer is only switched again when the corresponding blocking time has elapsed.                                                          </td></tr>
            <tr><td>                       </td><td><b>Note:</b> The 'locktime' switch is only effective in automatic mode.                                                                        </td></tr>
            <tr><td>                       </td><td>                                                                                                                                               </td></tr>
            <tr><td> <b>noshow</b>         </td><td>Hide or show consumers in graphic (optional).                                                                                                  </td></tr>
            <tr><td>                       </td><td><b>0</b> - the consumer is displayed (default)                                                                                                 </td></tr>
            <tr><td>                       </td><td><b>1</b> - the consumer is hidden                                                                                                              </td></tr>
            <tr><td>                       </td><td><b>2</b> - the consumer is hidden in the consumer legend                                                                                       </td></tr>
            <tr><td>                       </td><td><b>3</b> - the consumer is hidden in the flow chart                                                                                            </td></tr>
            <tr><td>                       </td><td><b>[Device:]Reading</b> - Reading in the consumer or optionally an alternative device.                                                         </td></tr>
            <tr><td>                       </td><td>If the reading has the value 0 or is not present, the consumer is displayed.                                                                   </td></tr>
            <tr><td>                       </td><td>The effect of the possible reading values 1, 2 and 3 is as described.                                                                          </td></tr>
         </table>
         </ul>
       <br>

       <ul>
         <b>Examples: </b> <br>
         <b>attr &lt;name&gt; consumer01</b> wallplug icon=scene_dishwasher@orange type=dishwasher mode=can power=2500 on=on off=off notafter=20 etotal=total:kWh:5 <br>
         <b>attr &lt;name&gt; consumer02</b> WPxw type=heater mode=can power=3000 mintime=180 on="on-for-timer 3600" notafter=12 auto=automatic                     <br>
         <b>attr &lt;name&gt; consumer03</b> Shelly.shellyplug2 type=other power=300 mode=must icon=it_ups_on_battery mintime=120 on=on off=off swstate=state:on:off auto=automatic pcurr=relay_0_power:W etotal:relay_0_energy_Wh:Wh swoncond=EcoFlow:data_data_socSum:-?([1-7][0-9]|[0-9]) swoffcond:EcoFlow:data_data_socSum:100 <br>
         <b>attr &lt;name&gt; consumer04</b> Shelly.shellyplug3 icon=scene_microwave_oven type=heater power=2000 mode=must notbefore=07 mintime=600 on=on off=off etotal=relay_0_energy_Wh:Wh pcurr=relay_0_power:W auto=automatic interruptable=eg.wz.wandthermostat:diff-temp:(22)(\.[2-9])|([2-9][3-9])(\.[0-9]):0.2             <br>
         <b>attr &lt;name&gt; consumer05</b> Shelly.shellyplug4 icon=sani_buffer_electric_heater_side type=heater mode=must power=1000 notbefore=7 notafter=20:10 auto=automatic pcurr=actpow:W on=on off=off mintime=SunPath interruptable=1                                                                                       <br>
         <b>attr &lt;name&gt; consumer06</b> Shelly.shellyplug5 icon=sani_buffer_electric_heater_side type=heater mode=must power=1000 notbefore=07:05 notafter={return'20:05'} auto=automatic pcurr=actpow:W on=on off=off mintime=SunPath:60:-120 interruptable=1                                                                              <br>
         <b>attr &lt;name&gt; consumer07</b> SolCastDummy icon=sani_buffer_electric_heater_side type=heater mode=can power=600 auto=automatic pcurr=actpow:W on=on off=off mintime=15 asynchron=1 locktime=300:1200 interruptable=1 noshow=noShow                                                                                   <br>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlAIdataStorageDuration"></a>
       <li><b>ctrlAIdataStorageDuration &lt;Tage&gt;</b> <br>
         If the corresponding prerequisites are met, training data is collected and stored for the module-internal AI.
         Data that has exceeded the specified holding period (days) is deleted.  <br>
         (default: 1095)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlAutoRefresh"></a>
       <li><b>ctrlAutoRefresh</b> <br>
         If set, active browser pages of the FHEMWEB device that has called up the SolarForecast device are
         reloaded after the set time (seconds). If browser pages of a certain FHEMWEB device are to be reloaded
         instead, this device can be specified with the attribute "ctrlAutoRefreshFW".
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlAutoRefreshFW"></a>
       <li><b>ctrlAutoRefreshFW</b><br>
         If "ctrlAutoRefresh" is activated, this attribute can be used to determine the FHEMWEB device whose active browser pages
         should be regularly reloaded.
       </li>
       <br>
       
       <a id="SolarForecast-attr-ctrlBackupFilesKeep"></a>
       <li><b>ctrlBackupFilesKeep &lt;Integer&gt; </b><br>
         Defines the number of generations of backup files 
         (see also <a href="#SolarForecast-set-operatingMemory">set &lt;name&gt; operatingMemory backup</a>). <br>
         (default: 3)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlBatSocManagement"></a>
       <li><b>ctrlBatSocManagement lowSoc=&lt;Value&gt; upSoC=&lt;Value&gt; [maxSoC=&lt;Value&gt;] [careCycle=&lt;Value&gt;] </b> <br><br>
         If a battery device (currentBatteryDev) is installed, this attribute activates the battery SoC management. <br>
         The <b>Battery_OptimumTargetSoC</b> reading contains the optimum minimum SoC calculated by the module. <br>
         The <b>Battery_ChargeRequest</b> reading is set to '1' if the current SoC has fallen below the minimum SoC. <br>
         In this case, the battery should be forcibly charged, possibly with mains power. <br>
         The readings can be used to control the SoC (State of Charge) and to control the charging current used for the
         battery. <br>
         The module itself does not control the battery. <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>lowSoc</b>    </td><td>lower minimum SoC, the battery is not discharged lower than this value (> 0)                </td></tr>
            <tr><td> <b>upSoC</b>     </td><td>upper minimum SoC, the usual value of the optimum SoC is between 'lowSoC'                   </td></tr>
            <tr><td>                  </td><td>and this value.                                                                             </td></tr>
            <tr><td> <b>maxSoC</b>    </td><td>Maximum minimum SoC, SoC value that must be reached at least every 'careCycle' days         </td></tr>
            <tr><td>                  </td><td>in order to balance the charge in the storage network.                                      </td></tr>
            <tr><td>                  </td><td>The specification is optional (&lt;= 100, default: 95)                                      </td></tr>
            <tr><td> <b>careCycle</b> </td><td>Maximum interval in days that may occur between two states of charge                        </td></tr>
            <tr><td>                  </td><td>of at least 'maxSoC'. The specification is optional (default: 20)                           </td></tr>
         </table>
         </ul>
         <br>

         All values are whole numbers in %. The following applies: 'lowSoc' &lt; 'upSoC' &lt; 'maxSoC'. <br>
         The optimum SoC is determined according to the following scheme: <br><br>

         <table>
         <colgroup> <col width="2%"> <col width="98%"> </colgroup>
            <tr><td> 1. </td><td>Starting from 'lowSoc', the minimum SoC is increased by 5% on the following day but not higher than                    </td></tr>
            <tr><td>    </td><td>'upSoC', if 'maxSoC' has not been reached on the current day.                                                          </td></tr>
            <tr><td> 2. </td><td>If 'maxSoC' is reached (again) on the current day, the minimum SoC is reduced by 5%, but not lower than 'lowSoc'.      </td></tr>
            <tr><td> 3. </td><td>Minimum SoC is reduced so that the predicted PV energy of the current or following day                                 </td></tr>
            <tr><td>    </td><td>can be absorbed by the battery. Minimum SoC is not reduced lower than 'lowSoc'.                                        </td></tr>
            <tr><td> 4. </td><td>The module records the last point in time at the 'maxSoC' level in order to ensure a charge to 'maxSoC'                </td></tr>
            <tr><td>    </td><td>at least every 'careCycle' days. For this purpose, the optimized SoC is changed depending on the remaining days        </td></tr>
            <tr><td>    </td><td>until the next 'careCycle' point in such a way that 'maxSoC' is mathematically achieved by a daily 5% SoC increase     </td></tr>
            <tr><td>    </td><td>at the 'careCycle' time point. If 'maxSoC' is reached in the meantime, the 'careCycle' period starts again.            </td></tr>
         </table>
         <br>

       <ul>
         <b>Example: </b> <br>
         attr &lt;name&gt; ctrlBatSocManagement lowSoc=10 upSoC=50 maxSoC=99 careCycle=25 <br>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlConsRecommendReadings"></a>
       <li><b>ctrlConsRecommendReadings </b><br>
         Readings of the form <b>consumerXX_ConsumptionRecommended</b> are created for the selected consumers (number). <br>
         These readings indicate whether it is recommended to switch on this consumer depending on its consumption data and the current
         PV generation or the current energy surplus. The value of the reading created correlates
         with the calculated planning data of the consumer, but may deviate from the planning period. <br>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlDebug"></a>
       <li><b>ctrlDebug</b><br>
         Enables/disables various debug modules. If only "none" is selected, there is no DEBUG output.
         For the output of debug messages the verbose level of the device must be at least "1". <br>
         The debug level can be combined with each other: <br><br>

         <ul>
         <table>
         <colgroup> <col width="23%"> <col width="77%"> </colgroup>
            <tr><td> <b>aiProcess</b>            </td><td>Process flow of AI support                                                       </td></tr>
            <tr><td> <b>aiData</b>               </td><td>AI data                                                                          </td></tr>
            <tr><td> <b>apiCall</b>              </td><td>Retrieval API interface without data output                                      </td></tr>
            <tr><td> <b>apiProcess</b>           </td><td>API data retrieval and processing                                                </td></tr>
            <tr><td> <b>batteryManagement</b>    </td><td>Battery management control values (SoC)                                          </td></tr>
            <tr><td> <b>collectData</b>          </td><td>detailed data collection                                                         </td></tr>
            <tr><td> <b>consumerPlanning</b>     </td><td>Consumer scheduling processes                                                    </td></tr>
            <tr><td> <b>consumerSwitching</b>    </td><td>Operations of the internal consumer switching module                             </td></tr>
            <tr><td> <b>consumption</b>          </td><td>Consumption calculation and use                                                  </td></tr>
            <tr><td> <b>epiecesCalc</b>          </td><td>Calculation of specific energy consumption per operating hour and consumer       </td></tr>
            <tr><td> <b>graphic</b>              </td><td>Module graphic information                                                       </td></tr>
            <tr><td> <b>notifyHandling</b>       </td><td>Sequence of event processing in the module                                       </td></tr>
            <tr><td> <b>pvCorrection</b>         </td><td>Calculation and application PV correction factors                                </td></tr>
            <tr><td> <b>radiationProcess</b>     </td><td>Collection and processing of solar radiation data                                </td></tr>
            <tr><td> <b>saveData2Cache</b>       </td><td>Data storage in internal memory structures                                       </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlGenPVdeviation"></a>
       <li><b>ctrlGenPVdeviation </b><br>
         Specifies the method for calculating the deviation between predicted and real PV generation.
         The Reading <b>Today_PVdeviation</b> is created depending on this setting. <br><br>

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>daily</b>         </td><td>Calculation and creation of Today_PVdeviation is done after sunset (default) </td></tr>
            <tr><td> <b>continuously</b>  </td><td>Calculation and creation of Today_PVdeviation is done continuously           </td></tr>
         </table>
         </ul>
       </li><br>

       <a id="SolarForecast-attr-ctrlInterval"></a>
       <li><b>ctrlInterval &lt;Sekunden&gt; </b><br>
         Repetition interval of the data collection. <br>
         Regardless of the set interval, data is collected automatically a few seconds before the end and after the start
         of a full hour. <br>
         If ctrlInterval is explicitly set to "0", no automatic data collection takes place and must be carried out
         externally with "get &lt;name&gt; data". <br>
         (default: 70)
       </li><br>

       <a id="SolarForecast-attr-ctrlLanguage"></a>
       <li><b>ctrlLanguage &lt;DE | EN&gt; </b><br>
         Defines the used language of the device. The language definition has an effect on the module graphics and various
         reading contents. <br>
         If the attribute is not set, the language is defined by setting the global attribute "language". <br>
         (default: EN)
       </li><br>

       <a id="SolarForecast-attr-ctrlNextDayForecastReadings"></a>
       <li><b>ctrlNextDayForecastReadings &lt;01,02,..,24&gt; </b><br>
         If set, readings of the form <b>Tomorrow_Hour&lt;hour&gt;_PVforecast</b> are created. <br>
         These readings contain the expected PV generation of the coming day. Here &lt;hour&gt; is the
         hour of the day. <br>
       <br>

       <ul>
         <b>Example: </b> <br>
         attr &lt;name&gt; ctrlNextDayForecastReadings 09,11 <br>
         # creates readings for hour 09 (08:00-09:00) and 11 (10:00-11:00) of the coming day
       </ul>

       </li>
       <br>

       <a id="SolarForecast-attr-ctrlShowLink"></a>
       <li><b>ctrlShowLink </b><br>
         Display of the link to the detailed view of the device above the graphic area. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlSolCastAPImaxReq"></a>
       <li><b>ctrlSolCastAPImaxReq </b><br>
         (only when using Model SolCastAPI) <br><br>

         The setting of the maximum possible daily requests to the SolCast API. <br>
         This value is specified by SolCast and may change according to the SolCast
         license model. <br>
         (default: 50)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlSolCastAPIoptimizeReq"></a>
       <li><b>ctrlSolCastAPIoptimizeReq </b><br>
         (only when using Model SolCastAPI) <br><br>

         The default retrieval interval of the SolCast API is 1 hour. If this attribute is set, the interval is dynamically
         adjustment of the interval with the goal to use the maximum possible fetches within
         sunrise and sunset. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlStatisticReadings"></a>
       <li><b>ctrlStatisticReadings </b><br>
         Readings are created for the selected key figures and indicators with the
         naming scheme 'statistic_&lt;indicator&gt;'. Selectable key figures / indicators are: <br><br>

         <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>allStringsFullfilled</b>       </td><td>Fulfillment status of error-free generation of all strings                                                           </td></tr>
            <tr><td> <b>conForecastTillNextSunrise</b> </td><td>Consumption forecast from current hour to the coming sunrise                                                         </td></tr>
            <tr><td> <b>currentAPIinterval</b>         </td><td>the current call interval of the SolCast API (only model SolCastAPI) in seconds                                      </td></tr>
            <tr><td> <b>currentRunMtsConsumer_XX</b>   </td><td>the running time (minutes) of the consumer "XX" since the last switch-on. (0 - consumer is off)                      </td></tr>
            <tr><td> <b>dayAfterTomorrowPVforecast</b> </td><td>provides the forecast of PV generation for the day after tomorrow (if available) without autocorrection (raw data)   </td></tr>
            <tr><td> <b>daysUntilBatteryCare</b>       </td><td>Days until the next battery maintenance (reaching the charge 'maxSoC' from attribute ctrlBatSocManagement)           </td></tr>
            <tr><td> <b>lastretrieval_time</b>         </td><td>the last call time of the API (only Model SolCastAPI, ForecastSolarAPI)                                              </td></tr>
            <tr><td> <b>lastretrieval_timestamp</b>    </td><td>the timestamp of the last call time of the API (only Model SolCastAPI, ForecastSolarAPI)                             </td></tr>
            <tr><td> <b>response_message</b>           </td><td>the last status message of the API (only Model SolCastAPI, ForecastSolarAPI)                                         </td></tr>
            <tr><td> <b>runTimeCentralTask</b>         </td><td>the runtime of the last SolarForecast interval (total process) in seconds                                            </td></tr>
            <tr><td> <b>runTimeTrainAI</b>             </td><td>the runtime of the last AI training cycle in seconds                                                                 </td></tr>
            <tr><td> <b>runTimeLastAPIAnswer</b>       </td><td>the last response time of the API call to a request in seconds (only model SolCastAPI, ForecastSolarAPI)             </td></tr>
            <tr><td> <b>runTimeLastAPIProc</b>         </td><td>the last process time for processing the received API data (only model SolCastAPI, ForecastSolarAPI)                 </td></tr>
            <tr><td> <b>SunMinutes_Remain</b>          </td><td>the remaining minutes until sunset of the current day                                                                </td></tr>
            <tr><td> <b>SunHours_Remain</b>            </td><td>the remaining hours until sunset of the current day                                                                  </td></tr>
            <tr><td> <b>todayConsumptionForecast</b>   </td><td>Consumption forecast per hour of the current day (01-24)                                                             </td></tr>
            <tr><td> <b>todayConForecastTillSunset</b> </td><td>Consumption forecast from current hour to hour before sunset                                                         </td></tr>
            <tr><td> <b>todayDoneAPIcalls</b>          </td><td>the number of API calls executed on the current day (only model SolCastAPI, ForecastSolarAPI)                        </td></tr>
            <tr><td> <b>todayDoneAPIrequests</b>       </td><td>the number of API requests executed on the current day (only model SolCastAPI, ForecastSolarAPI)                     </td></tr>
            <tr><td> <b>todayGridConsumption</b>       </td><td>the energy drawn from the public grid on the current day                                                             </td></tr>
            <tr><td> <b>todayGridFeedIn</b>            </td><td>PV energy fed into the public grid on the current day                                                                </td></tr>
            <tr><td> <b>todayMaxAPIcalls</b>           </td><td>the maximum possible number of SolCast API calls (SolCastAPI model only).                                            </td></tr>
            <tr><td>                                   </td><td>A call can contain multiple API requests.                                                                            </td></tr>
            <tr><td> <b>todayRemainingAPIcalls</b>     </td><td>the number of SolCast API calls still possible on the current day (only model SolCastAPI)                            </td></tr>
            <tr><td> <b>todayRemainingAPIrequests</b>  </td><td>the number of SolCast API requests still possible on the current day (only model SolCastAPI)                         </td></tr>
            <tr><td> <b>todayBatIn</b>                 </td><td>the energy charged into the battery on the current day                                                               </td></tr>
            <tr><td> <b>todayBatOut</b>                </td><td>the energy taken from the battery on the current day                                                                 </td></tr>
         </table>
         </ul>
       <br>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlUserExitFn"></a>
       <li><b>ctrlUserExitFn {&lt;Code&gt;} </b><br>
         After each cycle (see the <a href="#SolarForecast-attr-ctrlInterval">ctrlInterval </a> attribute), the code given
         in this attribute is executed. The code is to be enclosed in curly brackets {...}. <br>
         The code is passed the variables <b>$name</b> and <b>$hash</b>, which contain the name of the SolarForecast
         device and its hash. <br>
         In the SolarForecast Device, readings can be created and modified using the <b>storeReading</b> function.
         <br>
         <br>

         <ul>
         <b>Beispiel: </b> <br>
            {                                                                                           <br>
              my $batdev = (split " ", ReadingsVal ($name, 'currentBatteryDev', ''))[0];                <br>
              my $pvfc   = ReadingsNum ($name, 'RestOfDayPVforecast',          0);                      <br>
              my $cofc   = ReadingsNum ($name, 'RestOfDayConsumptionForecast', 0);                      <br>
              my $diff   = $pvfc - $cofc;                                                               <br>
                                                                                                        <br>
              storeReading ('userFn_Battery_device',  $batdev);                                         <br>
              storeReading ('userFn_estimated_surplus', $diff);                                         <br>
            }
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicCss"></a>
       <li><b>flowGraphicCss </b><br>
         Defines the style for the energy flow graph. The attribute is automatically preset.
         To change the flowGraphicCss attribute, please accept the default and adjust it: <br><br>

         <ul>
           .flowg.text           { stroke: none; fill: gray; font-size: 60px; } <br>
           .flowg.sun_active     { stroke: orange; fill: orange; }              <br>
           .flowg.sun_inactive   { stroke: gray; fill: gray; }                  <br>
           .flowg.bat25          { stroke: red; fill: red; }                    <br>
           .flowg.bat50          { stroke: darkorange; fill: darkorange; }      <br>
           .flowg.bat75          { stroke: green; fill: green; }                <br>
           .flowg.grid_color1    { fill: green; }                               <br>
           .flowg.grid_color2    { fill: red; }                                 <br>
           .flowg.grid_color3    { fill: gray; }                                <br>
           .flowg.inactive_in    { stroke: gray;       stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }                                                                     <br>
           .flowg.inactive_out   { stroke: gray;       stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }                                                                     <br>
           .flowg.active_in      { stroke: red;        stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_out     { stroke: darkorange; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_bat_in  { stroke: darkorange; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_bat_out { stroke: green;      stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
         </ul>

       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicAnimate"></a>
       <li><b>flowGraphicAnimate </b><br>
         Animates the energy flow graph if displayed.
         Siehe auch Attribut <a href="#SolarForecast-attr-graphicSelect">graphicSelect</a>. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicConsumerDistance"></a>
       <li><b>flowGraphicConsumerDistance </b><br>
         Controls the spacing between consumer icons in the energy flow graph if displayed.
         Siehe auch Attribut <a href="#SolarForecast-attr-flowGraphicShowConsumer">flowGraphicShowConsumer</a>. <br>
         (default: 130)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumer"></a>
       <li><b>flowGraphicShowConsumer </b><br>
         Suppresses the display of loads in the energy flow graph when set to "0". <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumerDummy"></a>
       <li><b>flowGraphicShowConsumerDummy </b><br>
         Shows or suppresses the dummy consumer in the energy flow graph. <br>
         The dummy consumer is assigned the energy consumption that could not be assigned to other consumers. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumerPower"></a>
       <li><b>flowGraphicShowConsumerPower </b><br>
         Shows or suppresses the energy consumption of the loads in the energy flow graph. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumerRemainTime"></a>
       <li><b>flowGraphicShowConsumerRemainTime </b><br>
         Shows or suppresses the remaining time (in minutes) of the loads in the energy flow graph. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicSize"></a>
       <li><b>flowGraphicSize &lt;Pixel&gt; </b><br>
         Size of the energy flow graph if displayed.
         Siehe auch Attribut <a href="#SolarForecast-attr-graphicSelect">graphicSelect</a>. <br>
         (default: 400)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1Color"></a>
       <li><b>graphicBeam1Color </b><br>
         Color selection of the primary bars.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1FontColor"></a>
       <li><b>graphicBeam1FontColor </b><br>
         Selection of the font color of the primary bar. <br>
         (default: 0D0D0D)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1Content"></a>
       <li><b>graphicBeam1Content </b><br>
         Defines the content of the primary bars to be displayed.

         <ul>
         <table>
         <colgroup> <col width="45%"> <col width="55%"> </colgroup>
            <tr><td> <b>pvReal</b>              </td><td>real PV generation (default)      </td></tr>
            <tr><td> <b>pvForecast</b>          </td><td>Forecast PV generation            </td></tr>
            <tr><td> <b>gridconsumption</b>     </td><td>Energy purchase from the grid     </td></tr>
            <tr><td> <b>consumptionForecast</b> </td><td>predicted energy consumption      </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1MaxVal"></a>
       <li><b>graphicBeam1MaxVal &lt;0...val&gt; </b><br>
         Setting the maximum amount of the primary bar (hourly value) to calculate the maximum bar height.
         This results in an adjustment of the total allowed height of the graphic. <br>
         With the value "0" a dynamic adjustment takes place. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam2Color"></a>
       <li><b>graphicBeam2Color </b><br>
         Color selection of the secondary bars. The second color is only useful for the display device type "pvco" and "diff".
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam2FontColor"></a>
       <li><b>graphicBeam2FontColor </b><br>
         Selection of the font color of the secondary bar. <br>
         (default: 000000)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam2Content"></a>
       <li><b>graphicBeam2Content </b><br>
         Legt den darzustellenden Inhalt der sekundären Balken fest.

         <ul>
         <table>
         <colgroup> <col width="43%"> <col width="57%"> </colgroup>
            <tr><td> <b>pvForecast</b>          </td><td>prognostizierte PV-Erzeugung (default) </td></tr>
            <tr><td> <b>pvReal</b>              </td><td>reale PV-Erzeugung                     </td></tr>
            <tr><td> <b>gridconsumption</b>     </td><td>Energie Bezug aus dem Netz             </td></tr>
            <tr><td> <b>consumptionForecast</b> </td><td>prognostizierter Energieverbrauch      </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeamHeight"></a>
       <li><b>graphicBeamHeight &lt;value&gt; </b><br>
         Height of the bars in px and thus determination of the total height.
         In connection with "graphicHourCount" it is possible to create quite small graphic outputs. <br>
         (default: 200)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeamWidth"></a>
       <li><b>graphicBeamWidth &lt;value&gt; </b><br>
         Width of the bars of the bar chart in px. If no attribute is set, the width of the bars is determined by the
         module automatically. <br>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicEnergyUnit"></a>
       <li><b>graphicEnergyUnit &lt;Wh | kWh&gt; </b><br>
         Defines the unit for displaying the electrical power in the graph. The kilowatt hour is rounded to one
         decimal place. <br>
         (default: Wh)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderDetail"></a>
       <li><b>graphicHeaderDetail </b><br>
         Selection of the zones of the graphic header to be displayed. <br>
         (default: all)

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>all</b>        </td><td>all zones of the head area (default)        </td></tr>
            <tr><td> <b>co</b>         </td><td>show consumption range                      </td></tr>
            <tr><td> <b>pv</b>         </td><td>show creation area                          </td></tr>
            <tr><td> <b>own</b>        </td><td>user zone (see <a href="#SolarForecast-attr-graphicHeaderOwnspec">graphicHeaderOwnspec</a>)   </td></tr>
            <tr><td> <b>status</b>     </td><td>status information area                     </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderOwnspec"></a>
       <li><b>graphicHeaderOwnspec &lt;Label&gt;:&lt;Reading&gt;[@Device] &lt;Label&gt;:&lt;Set&gt;[@Device] &lt;Label&gt;:&lt;Attr&gt;[@Device] ... </b><br>
         Display of any readings, set commands and attributes of the device in the graphic header. <br>
         Readings, set commands and attributes of other devices can be displayed by specifying the optional [@Device]. <br>
         The values to be displayed are separated by spaces.
         Four values (fields) are displayed per line. <br>
         The input can be made in multiple lines. Values with the units "Wh" or "kWh" are converted according to the
         setting of the attribute <a href="#SolarForecast-attr-graphicEnergyUnit">graphicEnergyUnit</a>.
         <br><br>

         Each value is to be defined by a label and the corresponding reading connected by ":". <br>
         Spaces in the label are to be inserted by "&amp;nbsp;", a line break by "&lt;br&gt;". <br>
         An empty field in a line is created by ":". <br>
         A line title can be inserted by specifying "#:&lt;Text&gt;", an empty title by entering "#".
         <br><br>

       <ul>
         <b>Example: </b> <br>
         <table>
         <colgroup> <col width="33%"> <col width="67%"> </colgroup>
            <tr><td> attr &lt;name&gt; graphicHeaderOwnspec  </td><td>#                                                                                       </td></tr>
            <tr><td>                                         </td><td>AutarkyRate:Current_AutarkyRate                                                         </td></tr>
            <tr><td>                                         </td><td>Surplus:Current_Surplus                                                                 </td></tr>
            <tr><td>                                         </td><td>current&amp;nbsp;Gridconsumption:Current_GridConsumption                                </td></tr>
            <tr><td>                                         </td><td>:                                                                                       </td></tr>
            <tr><td>                                         </td><td>#                                                                                       </td></tr>
            <tr><td>                                         </td><td>CO&amp;nbsp;until&amp;nbsp;sunset:statistic_todayConForecastTillSunset                  </td></tr>
            <tr><td>                                         </td><td>PV&amp;nbsp;Day&amp;nbsp;after&amp;nbsp;tomorrow:statistic_dayAfterTomorrowPVforecast   </td></tr>
            <tr><td>                                         </td><td>:                                                                                       </td></tr>
            <tr><td>                                         </td><td>:                                                                                       </td></tr>
            <tr><td>                                         </td><td>#Battery                                                                                </td></tr>
            <tr><td>                                         </td><td>in&amp;nbsp;today:statistic_todayBatIn                                                  </td></tr>
            <tr><td>                                         </td><td>out&amp;nbsp;today:statistic_todayBatOut                                                </td></tr>
            <tr><td>                                         </td><td>:                                                                                       </td></tr>
            <tr><td>                                         </td><td>:                                                                                       </td></tr>
            <tr><td>                                         </td><td>#Settings                                                                               </td></tr>
            <tr><td>                                         </td><td>Autocorrection:pvCorrectionFactor_Auto : : :                                            </td></tr>
            <tr><td>                                         </td><td>Consumer&lt;br&gt;Replanning:consumerNewPlanning : : :                                  </td></tr>
            <tr><td>                                         </td><td>Consumer&lt;br&gt;Quickstart:consumerImmediatePlanning : : :                            </td></tr>
            <tr><td>                                         </td><td>Weather:graphicShowWeather : : :                                                        </td></tr>
            <tr><td>                                         </td><td>History:graphicHistoryHour : : :                                                        </td></tr>
            <tr><td>                                         </td><td>GraphicSize:flowGraphicSize : : :                                                       </td></tr>
            <tr><td>                                         </td><td>ShowNight:graphicShowNight : : :                                                        </td></tr>
            <tr><td>                                         </td><td>Debug:ctrlDebug : : :                                                                   </td></tr>
         </table>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderOwnspecValForm"></a>
       <li><b>graphicHeaderOwnspecValForm </b><br>
         The readings to be displayed with the attribute
         <a href="#SolarForecast-attr-graphicHeaderOwnspec">graphicHeaderOwnspec</a> can be manipulated with sprintf and
         other Perl operations.  <br>
         There are two basic notation options that cannot be combined with each other. <br>
         The notations are always specified within two curly brackets {...}.
         <br><br>

         <b>Notation 1: </b> <br>
         A simple formatting of readings of your own device with sprintf is carried out as shown in line
         'Current_AutarkyRate' or 'Current_GridConsumption'. <br>
         Other Perl operations are to be bracketed with (). The respective readings values and units are available via
         the variables $VALUE and $UNIT. <br>
         Readings of other devices are specified by '&lt;Device&gt;.&lt;Reading&gt;'.
         <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td>{                                        </td><td>                                               </td></tr>
            <tr><td> 'Current_AutarkyRate'                   </td><td> => "%.1f %%",                                 </td></tr>
            <tr><td> 'Current_GridConsumption'               </td><td> => "%.2f $UNIT",                              </td></tr>
            <tr><td> 'SMA_Energymeter.Cover_RealPower'       </td><td> => q/($VALUE)." W"/,                          </td></tr>
            <tr><td> 'SMA_Energymeter.L2_Cover_RealPower'    </td><td> => "($VALUE).' W'",                           </td></tr>
            <tr><td> 'SMA_Energymeter.L1_Cover_RealPower'    </td><td> => '(sprintf "%.2f", ($VALUE / 1000))." kW"', </td></tr>
            <tr><td>}                                        </td><td>                                               </td></tr>
         </table>
         </ul>
         <br>

         <b>Notation 2: </b> <br>
         The manipulation of reading values and units is done via Perl If ... else structures. <br>
         The device, reading, reading value and unit are available to the structure with the variables $DEVICE, $READING,
         $VALUE and $UNIT. <br>
         If the variables are changed, the new values are transferred to the display accordingly.
         <br><br>

         <ul>
         <table>
         <colgroup> <col width="5%"> <col width="95%"> </colgroup>
            <tr><td>{ </td><td>                                                   </td></tr>
            <tr><td>  </td><td> if ($READING eq 'Current_AutarkyRate') {          </td></tr>
            <tr><td>  </td><td> &nbsp;&nbsp; $VALUE = sprintf "%.1f", $VALUE;     </td></tr>
            <tr><td>  </td><td> &nbsp;&nbsp; $UNIT  = "%";                        </td></tr>
            <tr><td>  </td><td> }                                                 </td></tr>
            <tr><td>  </td><td> elsif ($READING eq 'Current_GridConsumption') {   </td></tr>
            <tr><td>  </td><td> &nbsp;&nbsp; ...                                  </td></tr>
            <tr><td>  </td><td> }                                                 </td></tr>
            <tr><td>} </td><td>                                                   </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderShow"></a>
       <li><b>graphicHeaderShow </b><br>
         Show/hide the graphic table header with forecast data and certain current and
         statistical values. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHistoryHour"></a>
       <li><b>graphicHistoryHour </b><br>
         Number of previous hours displayed in the bar graph. <br>
         (default: 2)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHourCount"></a>
       <li><b>graphicHourCount &lt;4...24&gt; </b><br>
         Number of bars/hours in the bar graph. <br>
         (default: 24)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHourStyle"></a>
       <li><b>graphicHourStyle </b><br>
         Format of the time in the bar graph. <br><br>

       <ul>
         <table>
           <colgroup> <col width="30%"> <col width="70%"> </colgroup>
           <tr><td> <b>nicht gesetzt</b>  </td><td>hours only without minutes (default)                    </td></tr>
           <tr><td> <b>:00</b>            </td><td>Hours as well as minutes in two digits, e.g. 10:00      </td></tr>
           <tr><td> <b>:0</b>             </td><td>Hours as well as minutes single-digit, e.g. 8:0         </td></tr>
         </table>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicLayoutType"></a>
       <li><b>graphicLayoutType &lt;single | double | diff&gt; </b><br>
       Layout of the bar graph. <br>
       The content of the bars to be displayed is determined by the <b>graphicBeam1Content</b> or
       <b>graphicBeam2Content</b> attributes.
       <br><br>

       <ul>
       <table>
       <colgroup> <col width="10%"> <col width="90%"> </colgroup>
          <tr><td> <b>double</b>  </td><td>displays the primary bar and the secondary bar (default)                                                       </td></tr>
          <tr><td> <b>single</b>  </td><td>displays only the primary bar                                                                                  </td></tr>
          <tr><td> <b>diff</b>    </td><td>difference display. It is valid: &lt;Difference&gt; = &lt;Value primary bar&gt; - &lt;Value secondary bar&gt;  </td></tr>
       </table>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicSelect"></a>
       <li><b>graphicSelect </b><br>
         Selects the graphic segments of the module to be displayed. <br>
         To customize the energy flow graphic, the <a href="#SolarForecast-attr-flowGraphicCss">flowGraphicCss</a>
         attribute is available in addition to the flowGraphic.* attributes.
         <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>both</b>       </td><td>displays the header, consumer legend, energy flow and prediction graph (default)        </td></tr>
            <tr><td> <b>flow</b>       </td><td>displays the header, the consumer legend and energy flow graphic                        </td></tr>
            <tr><td> <b>forecast</b>   </td><td>displays the header, the consumer legend and the prediction graphic                     </td></tr>
            <tr><td> <b>none</b>       </td><td>displays only the header and the consumer legend                                        </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicShowDiff"></a>
       <li><b>graphicShowDiff &lt;no | top | bottom&gt; </b><br>
         Additional display of the difference "graphicBeam1Content - graphicBeam2Content" in the header or footer area of the
         bar graphic. <br>
         (default: no)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicShowNight"></a>
       <li><b>graphicShowNight </b><br>
         Show/hide the night hours (without yield forecast) in the bar graph. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicShowWeather"></a>
       <li><b>graphicShowWeather </b><br>
         Show/hide weather icons in the bar graph. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicStartHtml"></a>
       <li><b>graphicStartHtml &lt;HTML-String&gt; </b><br>
         Specify any HTML string to be executed before the graphics code.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicEndHtml"></a>
       <li><b>graphicEndHtml &lt;HTML-String&gt; </b><br>
         Specify any HTML string that will be executed after the graphic code.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicSpaceSize"></a>
       <li><b>graphicSpaceSize &lt;value&gt; </b><br>
         Defines how much space in px above or below the bars (with display type differential (diff)) is kept free for
         displaying the values. For styles with large fonts the default value may be too small or a
         bar may slip over the baseline. In these cases please increase the value. <br>
         (default: 24)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicWeatherColor"></a>
       <li><b>graphicWeatherColor </b><br>
         Color of the weather icons in the bar graph for the daytime hours.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicWeatherColorNight"></a>
       <li><b>graphicWeatherColorNight </b><br>
         Color of the weather icons for the night hours.
       </li>
       <br>

     </ul>
  </ul>


</ul>
=end html
=begin html_DE

<a id="SolarForecast"></a>
<h3>SolarForecast</h3>
<br>

Das Modul SolarForecast erstellt auf Grundlage der Werte aus generischen Quellen eine
Vorhersage für den solaren Ertrag und integriert weitere Informationen als Grundlage für darauf aufbauende Steuerungen. <br>

Zur Erstellung der solaren Vorhersage kann das Modul SolarForecast unterschiedliche Dienste und Quellen nutzen: <br><br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> <b>DWD</b>               </td><td>solare Vorhersage basierend auf der Strahlungsprognose des Deutschen Wetterdienstes (Model DWD)                                         </td></tr>
        <tr><td> <b>SolCast-API </b>      </td><td>verwendet Prognosedaten der <a href='https://toolkit.solcast.com.au/rooftop-sites/' target='_blank'>SolCast API</a> (Model SolCastAPI)  </td></tr>
        <tr><td> <b>ForecastSolar-API</b> </td><td>verwendet Prognosedaten der <a href='https://doc.forecast.solar/api' target='_blank'>Forecast.Solar API</a> (Model ForecastSolarAPI)    </td></tr>
        <tr><td> <b>VictronKI-API</b>     </td><td>Victron Energy API des <a href='https://www.victronenergy.com/blog/2023/07/05/new-vrm-solar-production-forecast-feature/' target='_blank'>VRM Portals</a> (Model VictronKiAPI) </td></tr>
     </table>
  </ul>
  <br>

Bei Verwendung des Model DWD kann eine KI-Unterstützung aktiviert werden. <br>
Die Nutzung der erwähnten API's beschränkt sich auf die jeweils kostenlose Version des Dienstes. <br>
Im zugeordneten DWD_OpenData Device (Setter "currentWeatherDev") ist die passende Wetterstation
festzulegen um meteorologische Daten (Bewölkung, Sonnenaufgang, u.a.) bzw. eine Strahlungsprognose (Model DWD)
für den Anlagenstandort zu erhalten. <br><br>

Über die PV Erzeugungsprognose hinaus werden Verbrauchswerte bzw. Netzbezugswerte erfasst und für eine
Verbrauchsprognose verwendet. <br>
Das Modul errechnet aus den Prognosewerten einen zukünftigen Energieüberschuß der zur Betriebsplanung von Verbrauchern
genutzt wird. Weiterhin bietet das Modul eine <a href="#SolarForecast-Consumer">Consumer Integration</a> zur integrierten
Planung und Steuerung von PV Überschuß abhängigen Verbraucherschaltungen. <br><br>

Bei der ersten Definition des Moduls wird der Benutzer über eine Guided Procedure unterstützt um alle initialen Eingaben
vorzunehmen. <br>
Am Ende des Vorganges und nach relevanten Änderungen der Anlagen- bzw. Devicekonfiguration sollte unbedingt mit einem
<a href="#SolarForecast-set-plantConfiguration">set &lt;name&gt; plantConfiguration ceck</a>
die ordnungsgemäße Anlagenkonfiguration geprüft werden.

<ul>
  <a id="SolarForecast-define"></a>
  <b>Define</b>
  <br><br>

  <ul>
    Ein SolarForecast Device wird erstellt mit: <br><br>

    <ul>
      <b>define &lt;name&gt; SolarForecast </b>
    </ul>
    <br>

    Nach der Definition des Devices sind in Abhängigkeit der verwendeten Prognosequellen zwingend weitere
    anlagenspezifische Angaben mit den entsprechenden set-Kommandos zu hinterlegen. <br>
    Mit nachfolgenden set-Kommandos werden für die Funktion des Moduls maßgebliche Informationen
    hinterlegt: <br><br>

      <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>currentWeatherDev</b>    </td><td>DWD_OpenData Device welches meteorologische Daten (z.B. Bewölkung) liefert     </td></tr>
            <tr><td> <b>currentRadiationAPI </b> </td><td>DWD_OpenData Device bzw. API zur Lieferung von Strahlungsdaten                 </td></tr>
            <tr><td> <b>currentInverterDev</b>   </td><td>Device welches PV Leistungsdaten liefert                                       </td></tr>
            <tr><td> <b>currentMeterDev</b>      </td><td>Device welches Netz I/O-Daten liefert                                          </td></tr>
            <tr><td> <b>currentBatteryDev</b>    </td><td>Device welches Batterie Leistungsdaten liefert (sofern vorhanden)              </td></tr>
            <tr><td> <b>inverterStrings</b>      </td><td>Bezeichner der vorhandenen Anlagenstrings                                      </td></tr>
            <tr><td> <b>moduleDirection</b>      </td><td>Ausrichtung (Azimut) der Anlagenstrings                                        </td></tr>
            <tr><td> <b>modulePeakString</b>     </td><td>die DC-Peakleistung der Anlagenstrings                                         </td></tr>
            <tr><td> <b>roofIdentPair</b>        </td><td>die Identifikationsdaten (bei Nutzung der SolCast API)                         </td></tr>
            <tr><td> <b>moduleRoofTops</b>       </td><td>die Rooftop Parameter (bei Nutzung der SolCast API)                            </td></tr>
            <tr><td> <b>moduleTiltAngle</b>      </td><td>die Neigungswinkel der der Anlagenmodule                                       </td></tr>
         </table>
      </ul>
      <br>

    Um eine Anpassung an die persönliche Anlage zu ermöglichen, können Korrekturfaktoren manuell fest bzw. automatisiert
    dynamisch angewendet werden.
    <br><br>
  </ul>

  <a id="SolarForecast-Consumer"></a>
  <b>Consumer Integration</b>
  <br><br>

  <ul>
    Der Nutzer kann Verbraucher (z.B. Schaltsteckdosen) direkt im Modul registrieren und die Planung der
    Ein/Ausschaltzeiten sowie deren Ausführung vom SolarForecast Modul übernehmen lassen. Die Registrierung erfolgt mit den
    <a href="#SolarForecast-attr-consumer">ConsumerXX-Attributen</a>. In den Attributen werden neben dem FHEM Consumer Device eine Vielzahl von obligatorischen oder
    optionalen Schlüsseln angegeben die das Einplanungs- und Schaltverhalten des Consumers beeinflussen. <br>
    Die Schlüssel sind in der ConsumerXX-Hilfe detailliiert beschreiben.
    Um sich in den Umgang mit der Consumersteuerung anzueignen, bietet es sich an zunächst einen oder
    mehrere Dummies anzulegen und diese Devices als Consumer zu registrieren.
    <br><br>

    Zu diesem Zweck eignet sich ein Dummy Device nach diesem Muster:
    <br><br>

    <ul>
        define SolCastDummy dummy                                                                                                   <br>
        attr SolCastDummy userattr nomPower                                                                                         <br>
        attr SolCastDummy alias SolarForecast Consumer Dummy                                                                        <br>
        attr SolCastDummy cmdIcon on:remotecontrol/black_btn_GREEN off:remotecontrol/black_btn_RED                                  <br>
        attr SolCastDummy devStateIcon off:light_light_dim_100@grey on:light_light_dim_100@darkorange                               <br>
        attr SolCastDummy group Solarprognose                                                                                       <br>
        attr SolCastDummy icon solar_icon                                                                                           <br>
        attr SolCastDummy nomPower 1000                                                                                             <br>
        attr SolCastDummy readingList BatIn BatOut BatVal  BatInTot BatOutTot bezW einW Batcharge Temp automatic                    <br>
        attr SolCastDummy room Energie,Testraum                                                                                     <br>
        attr SolCastDummy setList BatIn BatOut BatVal BatInTot BatOutTot bezW einW Batcharge on off Temp                            <br>
        attr SolCastDummy userReadings actpow {ReadingsVal ($name, 'state', 'off') eq 'on' ? AttrVal ($name, 'nomPower', 100) : 0}  <br>
    </ul>

    <br><br>
  </ul>

  <a id="SolarForecast-set"></a>
  <b>Set</b>
  <ul>

    <ul>
      <a id="SolarForecast-set-aiDecTree"></a>
      <li><b>aiDecTree </b> <br><br>

      Ist der KI Support im SolarForecast Device aktiviert, können verschiedene KI-Aktionen manuell ausgeführt werden.
      Die manuelle Ausführung der KI Aktionen ist im Allgemeinen nicht notwendig, da die Abarbeitung aller nötigen Schritte
      bereits automatisch im Modul vorgenommen wird.
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="10%"> <col width="90%"> </colgroup>
          <tr><td> <b>addInstances</b>  </td><td>- Die KI wird mit den aktuell vorhandenen PV-, Strahlungs- und Umweltdaten angereichert.                                  </td></tr>
          <tr><td> <b>addRawData</b>    </td><td>- Relevante PV-, Strahlungs- und Umweltdaten werden extrahiert und für die spätere Verwendung gespeichert.                </td></tr>
          <tr><td> <b>train</b>         </td><td>- Die KI wird mit den verfügbaren Daten trainiert.                                                                        </td></tr>
          <tr><td>                      </td><td>&nbsp;&nbsp;Erfolgreich generierte Entscheidungsdaten werden im Filesystem gespeichert.                                   </td></tr>
        </table>
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-batteryTrigger"></a>
      <li><b>batteryTrigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>

      Generiert Trigger bei Über- bzw. Unterschreitung bestimmter Batterieladungswerte (SoC in %). <br>
      Überschreiten die letzten drei SoC-Messungen eine definierte <b>Xon-Bedingung</b>, wird das Reading
      <b>batteryTrigger_X = on</b> erstellt/gesetzt. <br>
      Unterschreiten die letzten drei SoC-Messungen eine definierte <b>Xoff-Bedingung</b>, wird das Reading
      <b>batteryTrigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; batteryTrigger 1on=30 1off=10 2on=70 2off=20 3on=15 4off=90<br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-consumerNewPlanning"></a>
      <li><b>consumerNewPlanning &lt;Verbrauchernummer&gt; </b> <br><br>

      Es wird die vorhandene Planung des angegebenen Verbrauchers gelöscht. <br>
      Die Neuplanung wird unter Berücksichtigung der im consumerXX Attribut gesetzten Parameter sofort vorgenommen.
      <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; consumerNewPlanning 01 <br>
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-consumerImmediatePlanning"></a>
      <li><b>consumerImmediatePlanning &lt;Verbrauchernummer&gt; </b> <br><br>

      Es wird das sofortige Einschalten des Verbrauchers zur aktuellen Zeit eingeplant.
      Eventuell im consumerXX Attribut gesetzte Schlüssel <b>notbefore</b>, <b>notafter</b> bzw. <b>mode</b> werden nicht
      beachtet. <br>
      <br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; consumerImmediatePlanning 01 <br>
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentBatteryDev"></a>
      <li><b>currentBatteryDev &lt;Batterie Device Name&gt; pin=&lt;Readingname&gt;:&lt;Einheit&gt; pout=&lt;Readingname&gt;:&lt;Einheit&gt;
                               [intotal=&lt;Readingname&gt;:&lt;Einheit&gt;] [outtotal=&lt;Readingname&gt;:&lt;Einheit&gt;]
                               [cap=&lt;Option&gt;] [charge=&lt;Readingname&gt;]  </b> <br><br>

      Legt ein beliebiges Device und seine Readings zur Lieferung der Batterie Leistungsdaten fest.
      Das Modul geht davon aus, dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>pin</b>       </td><td>Reading welches die aktuelle Batterieladeleistung liefert                                                </td></tr>
          <tr><td> <b>pout</b>      </td><td>Reading welches die aktuelle Batterieentladeleistung liefert                                             </td></tr>
          <tr><td> <b>intotal</b>   </td><td>Reading welches die totale Batterieladung als fortlaufenden Zähler liefert (optional)                    </td></tr>
          <tr><td> <b>outtotal</b>  </td><td>Reading welches die totale Batterieentladung als fortlaufenden Zähler liefert (optional)                 </td></tr>
          <tr><td> <b>cap</b>       </td><td>installierte Batteriekapazität (optional). Option kann sein:                                             </td></tr>
          <tr><td>                  </td><td><b>numerischer Wert</b> - direkte Angabe der Batteriekapazität in Wh                                     </td></tr>
          <tr><td>                  </td><td><b>&lt;Readingname&gt;:&lt;Einheit&gt;</b> - Reading welches die Kapazität liefert und Einheit (Wh, kWh) </td></tr>
          <tr><td> <b>charge</b>    </td><td>Reading welches den aktuellen Ladezustand (SOC in Prozent) liefert (optional)                            </td></tr>
          <tr><td> <b>Einheit</b>   </td><td>die jeweilige Einheit (W,Wh,kW,kWh)                                                                      </td></tr>
        </table>
      </ul>
      <br>

      <b>Sonderfälle:</b> Sollte das Reading für pin und pout identisch, aber vorzeichenbehaftet sein,
      können die Schlüssel pin und pout wie folgt definiert werden: <br><br>
      <ul>
        pin=-pout  &nbsp;&nbsp;&nbsp;(ein negativer Wert von pout wird als pin verwendet)  <br>
        pout=-pin  &nbsp;&nbsp;&nbsp;(ein negativer Wert von pin wird als pout verwendet)
      </ul>
      <br>

      Die Einheit entfällt in dem jeweiligen Sonderfall. <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentBatteryDev BatDummy pin=BatVal:W pout=-pin intotal=BatInTot:Wh outtotal=BatOutTot:Wh cap=BatCap:kWh <br>
        <br>
        # Device BatDummy liefert die aktuelle Batterieladung im Reading "BatVal" (W), die Batterieentladung im gleichen Reading mit negativen Vorzeichen, <br>
        # die summarische Ladung im Reading "intotal" (Wh), sowie die summarische Entladung im Reading "outtotal" (Wh)
      </ul>
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentWeatherDev"></a>
      <li><b>currentWeatherDev </b> <br><br>

      Legt das Device (Typ DWD_OpenData) fest, welches die benötigten Wetterdaten (Bewölkung, Niederschlag,
      Sonnenauf- bzw. untergang usw.) liefert.
      Ist noch kein Device dieses Typs vorhanden, muß es manuell definiert werden
      (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens diese Attribute gesetzt sein: <br><br>

      <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                   </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>TTT,Neff,R101,ww,SunUp,SunRise,SunSet               </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                   </td></tr>
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Stationscode der ausgewerteten DWD Station&gt;  </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentInverterDev"></a>
      <li><b>currentInverterDev &lt;Inverter Device Name&gt; pv=&lt;Readingname&gt;:&lt;Einheit&gt; etotal=&lt;Readingname&gt;:&lt;Einheit&gt; [capacity=&lt;max. WR-Leistung&gt;] </b> <br><br>

      Legt ein beliebiges Device und dessen Readings zur Lieferung der aktuellen PV Erzeugungswerte fest.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein.
      Die Werte mehrerer Inverterdevices führt man z.B. in einem Dummy Device zusammen und gibt dieses Device mit den
      entsprechenden Readings an. <br>
      Die Angabe von <b>capacity</b> ist optional, wird aber zur Optimierung der Vorhersagegenauigkeit dringend empfohlen.
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>pv</b>       </td><td>Reading welches die aktuelle PV-Erzeugung liefert                                       </td></tr>
          <tr><td> <b>etotal</b>   </td><td>Reading welches die gesamte erzeugte PV-Energie liefert (ein stetig aufsteigender Zähler) </td></tr>
          <tr><td> <b>Einheit</b>  </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                                     </td></tr>
          <tr><td> <b>capacity</b> </td><td>Bemessungsleistung des Wechselrichters gemäß Datenblatt (max. möglicher Output in Watt) </td></tr>
        </table>
      </ul>
      <br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentInverterDev STP5000 pv=total_pac:kW etotal=etotal:kWh capacity=5000 <br>
        <br>
        # Device STP5000 liefert PV-Werte. Die aktuell erzeugte Leistung im Reading "total_pac" (kW) und die tägliche Erzeugung im
          Reading "etotal" (kWh). Die max. Leistung des Wechselrichters beträgt 5000 Watt.
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentMeterDev"></a>
      <li><b>currentMeterDev &lt;Meter Device Name&gt; gcon=&lt;Readingname&gt;:&lt;Einheit&gt; contotal=&lt;Readingname&gt;:&lt;Einheit&gt; gfeedin=&lt;Readingname&gt;:&lt;Einheit&gt; feedtotal=&lt;Readingname&gt;:&lt;Einheit&gt;   </b> <br><br>

      Legt ein beliebiges Device und seine Readings zur Energiemessung fest.
      Das Modul geht davon aus, dass der numerische Wert der Readings positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>gcon</b>       </td><td>Reading welches die aktuell aus dem Netz bezogene Leistung liefert                                          </td></tr>
          <tr><td> <b>contotal</b>   </td><td>Reading welches die Summe der aus dem Netz bezogenen Energie liefert (ein sich stetig erhöhender Zähler)    </td></tr>
          <tr><td> <b>gfeedin</b>    </td><td>Reading welches die aktuell in das Netz eingespeiste Leistung liefert                                       </td></tr>
          <tr><td> <b>feedtotal</b>  </td><td>Reading welches die Summe der in das Netz eingespeisten Energie liefert (ein sich stetig erhöhender Zähler) </td></tr>
          <tr><td> <b>Einheit</b>    </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                                                         </td></tr>
        </table>
      </ul>
      <br>

      <b>Sonderfälle:</b> Sollte das Reading für gcon und gfeedin identisch, aber vorzeichenbehaftet sein,
      können die Schlüssel gfeedin und gcon wie folgt definiert werden: <br><br>
      <ul>
        gfeedin=-gcon  &nbsp;&nbsp;&nbsp;(ein negativer Wert von gcon wird als gfeedin verwendet)  <br>
        gcon=-gfeedin  &nbsp;&nbsp;&nbsp;(ein negativer Wert von gfeedin wird als gcon verwendet)
      </ul>
      <br>

      Die Einheit entfällt in dem jeweiligen Sonderfall. <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentMeterDev Meter gcon=Wirkleistung:W contotal=BezWirkZaehler:kWh gfeedin=-gcon feedtotal=EinWirkZaehler:kWh  <br>
        <br>
        # Device Meter liefert den aktuellen Netzbezug im Reading "Wirkleistung" (W),
          die Summe des Netzbezugs im Reading "BezWirkZaehler" (kWh), die aktuelle Einspeisung in "Wirkleistung" wenn "Wirkleistung" negativ ist,
          die Summe der Einspeisung im Reading "EinWirkZaehler" (kWh)
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentRadiationAPI"></a>
      <li><b>currentRadiationAPI </b> <br><br>

      Legt die Quelle zur Lieferung der solaren Strahlungsdaten fest. Es kann ein Device vom Typ DWD_OpenData oder
      eine implementierte API ausgewählt werden. <br><br>

      <b>SolCast-API</b> <br>

      Die API-Nutzung benötigt vorab ein oder mehrere API-keys (Accounts) sowie ein oder mehrere Rooftop-ID's
      die auf der <a href='https://toolkit.solcast.com.au/rooftop-sites/' target='_blank'>SolCast</a> Webseite angelegt
      werden müssen.
      Ein Rooftop ist im SolarForecast-Kontext mit einem <a href="#SolarForecast-set-inverterStrings">inverterString</a>
      gleichzusetzen. <br>
      Die kostenfreie API-Nutzung ist auf eine Tagesrate API-Anfragen begrenzt. Die Anzahl definierter Strings (Rooftops)
      erhöht die Anzahl erforderlicher API-Anfragen. Das Modul optimiert die Abfragezyklen mit dem Attribut
      <a href="#SolarForecast-attr-ctrlSolCastAPIoptimizeReq ">ctrlSolCastAPIoptimizeReq </a>.
      <br><br>

      <b>ForecastSolar-API</b> <br>

      Die kostenfreie Nutzung der <a href='https://doc.forecast.solar/start' target='_blank'>Forecast.Solar API</a>
      erfordert keine Registrierung. Die API-Anfragen sind in der kostenfreien Version auf 12 innerhalb einer Stunde
      begrenzt. Ein Tageslimit gibt es dabei nicht. Das Modul ermittelt automatisch das optimale Abfrageintervall
      in Abhängigkeit der konfigurierten Strings.
      <br><br>

      <b>VictronKI-API</b> <br>

      Diese API kann durch Nutzer des Victron Energy VRM Portals angewendet werden. Diese API ist KI basierend.
      Als String ist der Wert "KI-based" im Setup der <a href="#SolarForecast-set-inverterStrings">inverterStrings</a>
      einzutragen. <br>
      Im Victron Energy VRM Portal ist als Voraussetzung der Standort der PV-Anlage anzugeben. <br>
      Siehe dazu auch den Blog-Beitrag
      <a href="https://www.victronenergy.com/blog/2023/07/05/new-vrm-solar-production-forecast-feature/">Introducing Solar Production Forecast</a>.
      <br><br>

      <b>DWD_OpenData Device</b> <br>

      Der DWD-Dienst wird über ein FHEM Device vom Typ DWD_OpenData eingebunden.
      Ist noch kein Device des Typs DWD_OpenData vorhanden, muß es vorab definiert werden
      (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Um eine gute Strahlungsprognose zu erhalten, sollte eine nahe dem Anlagenstandort gelegene DWD-Station genutzt
      werden. <br>
      Leider liefern nicht alle
      <a href="https://www.dwd.de/DE/leistungen/klimadatendeutschland/statliste/statlex_html.html;jsessionid=EC5F572A52EB69684D552DCF6198F290.live31092?view=nasPublication&nn=16102">DWD-Stationen</a>
      die benötigten Rad1h-Werte. <br>
      Erläuterungen zu den Stationen sind im
      <a href="https://www.dwd.de/DE/leistungen/klimadatendeutschland/stationsliste.html">Stationslexikon</a> aufgeführt. <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens die folgenden Attribute gesetzt sein: <br><br>

      <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                                                             </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>Rad1h                                                                                         </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                                                             </td></tr>
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Stationscode der ausgewerteten DWD Station&gt;                                            </td></tr>
            <tr><td>                                </td><td><b>Hinweis:</b> Die ausgewählte DWD Station muß Strahlungswerte (Rad1h Readings) liefern.     </td></tr>
            <tr><td>                                </td><td>Nicht alle Stationen liefern diese Daten!                                                     </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-energyH4Trigger"></a>
      <li><b>energyH4Trigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>

      Generiert Trigger bei Über- bzw. Unterschreitung der 4-Stunden PV Vorhersage (NextHours_Sum04_PVforecast). <br>
      Überschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xon-Bedingung</b>, wird das Reading
      <b>energyH4Trigger_X = on</b> erstellt/gesetzt.
      Unterschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xoff-Bedingung</b>, wird das Reading
      <b>energyH4Trigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; energyH4Trigger 1on=2000 1off=1700 2on=2500 2off=2000 3off=1500 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-inverterStrings"></a>
      <li><b>inverterStrings &lt;Stringname1&gt;[,&lt;Stringname2&gt;,&lt;Stringname3&gt;,...] </b> <br><br>

      Bezeichnungen der aktiven Strings. Diese Bezeichnungen werden als Schlüssel in den weiteren
      Settings verwendet. <br>
      Bei Nutzung einer KI basierenden API (z.B. VictronKI-API) ist nur "<b>KI-based</b>" einzutragen unabhängig davon
      welche realen Strings existieren. <br><br>

      <ul>
        <b>Beispiele: </b> <br>
        set &lt;name&gt; inverterStrings Ostdach,Südgarage,S3 <br>
        set &lt;name&gt; inverterStrings KI-based <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-modulePeakString"></a>
      <li><b>modulePeakString &lt;Stringname1&gt;=&lt;Peak&gt; [&lt;Stringname2&gt;=&lt;Peak&gt; &lt;Stringname3&gt;=&lt;Peak&gt; ...] </b> <br><br>

      Die DC Peakleistung des Strings "StringnameX" in kWp. Der Stringname ist ein Schlüsselwert des
      Readings <b>inverterStrings</b>. <br>
      Bei Verwendung einer KI basierenden API (z.B. Model VictronKiAPI) sind die Peakleistungen aller vorhandenen
      Strings als Summe dem Stringnamen <b>KI-based</b> zuzuordnen. <br><br>

      <ul>
        <b>Beispiele: </b> <br>
        set &lt;name&gt; modulePeakString Ostdach=5.1 Südgarage=2.0 S3=7.2 <br>
        set &lt;name&gt; modulePeakString KI-based=14.3 (bei KI basierender API)<br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleDirection"></a>
      <li><b>moduleDirection &lt;Stringname1&gt;=&lt;dir&gt; [&lt;Stringname2&gt;=&lt;dir&gt; &lt;Stringname3&gt;=&lt;dir&gt; ...] </b> <br>
      (nur Model DWD, ForecastSolarAPI) <br><br>

      Ausrichtung &lt;dir&gt; der Solarmodule im String "StringnameX". Der Stringname ist ein Schlüsselwert des
      Readings <b>inverterStrings</b>. <br>
      Die Richtungsangabe &lt;dir&gt; kann als Azimut Kennung oder als Azimut Wert angegeben werden: <br><br>

      <ul>
         <table>
         <colgroup> <col width="30%"> <col width="20%"> <col width="50%"> </colgroup>
            <tr><td> <b>Kennung</b>   </td><td><b>Azimut</b> </td><td>                           </td></tr>
            <tr><td> N                </td><td>-180          </td><td>Nordausrichtung            </td></tr>
            <tr><td> NE               </td><td>-135          </td><td>Nord-Ost Ausrichtung       </td></tr>
            <tr><td> E                </td><td>-90           </td><td>Ostausrichtung             </td></tr>
            <tr><td> SE               </td><td>-45           </td><td>Süd-Ost Ausrichtung        </td></tr>
            <tr><td> S                </td><td>0             </td><td>Südausrichtung             </td></tr>
            <tr><td> SW               </td><td>45            </td><td>Süd-West Ausrichtung       </td></tr>
            <tr><td> W                </td><td>90            </td><td>Westausrichtung            </td></tr>
            <tr><td> NW               </td><td>135           </td><td>Nord-West Ausrichtung      </td></tr>
         </table>
      </ul>
      <br>

      Azimut Werte sind Ganzzahlen im Bereich von -180 bis 180. Azimut Zwischenwerte, die nicht exakt auf eine
      Kennung passen, werden auf die nächstgelegene Kennung abstrahiert wenn die gewählte API nur mit Kennungen
      arbeitet. Das Modul verwendet den genaueren Azimut Wert sofern die API die Verwendung unterstützt, z.B. die
      ForecastSolar-API.
      <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleDirection Ostdach=-90 Südgarage=S S3=NW <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleRoofTops"></a>
      <li><b>moduleRoofTops &lt;Stringname1&gt;=&lt;pk&gt; [&lt;Stringname2&gt;=&lt;pk&gt; &lt;Stringname3&gt;=&lt;pk&gt; ...] </b> <br>
      (nur bei Verwendung Model SolCastAPI) <br><br>

      Es erfolgt die Zuordnung des Strings "StringnameX" zu einem Schlüssel &lt;pk&gt;. Der Schlüssel &lt;pk&gt; wurde mit dem
      Setter <a href="#SolarForecast-set-roofIdentPair">roofIdentPair</a> angelegt. Damit wird bei Abruf des Rooftops (=String)
      in der SolCast API die zu verwendende Rooftop-ID sowie der zu verwendende API-Key festgelegt. <br>
      Der StringnameX ist ein Schlüsselwert des Readings <b>inverterStrings</b>.
      <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleRoofTops Ostdach=p1 Südgarage=p2 S3=p3 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleTiltAngle"></a>
      <li><b>moduleTiltAngle &lt;Stringname1&gt;=&lt;Winkel&gt; [&lt;Stringname2&gt;=&lt;Winkel&gt; &lt;Stringname3&gt;=&lt;Winkel&gt; ...] </b> <br>
      (nur Model DWD, ForecastSolarAPI) <br><br>

      Neigungswinkel der Solarmodule. Der Stringname ist ein Schlüsselwert des Readings <b>inverterStrings</b>. <br>
      Mögliche Neigungswinkel sind: 0,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90
      (0 = waagerecht, 90 = senkrecht). <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleTiltAngle Ostdach=40 Südgarage=60 S3=30 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-operatingMemory"></a>
      <li><b>operatingMemory backup | save | recover-&lt;Datei&gt; </b> <br><br>

      Die Komponenten pvHistory (PVH) und pvCircular (PVC) der internen Cache Datenbank werden im Filesystem gespeichert. <br>
      Das Zielverzeichnis ist "../FHEM/FhemUtils". Dieser Vorgang wird vom Modul regelmäßig im Hintergrund ausgeführt.  <br><br>

      <ul>
         <table>
         <colgroup> <col width="17%"> <col width="83%"> </colgroup>
            <tr><td> <b>backup</b>                </td><td>Sichert die aktiven In-Memory Strukturen mit dem aktuellen Zeitstempel.                                                                                      </td></tr>
            <tr><td>                              </td><td>Es werden <a href="#SolarForecast-attr-ctrlBackupFilesKeep">ctrlBackupFilesKeep</a> Generationen der Dateien gespeichert. Ältere Versionen werden gelöscht.  </td></tr>
            <tr><td>                              </td><td>Dateien: PVH_SolarForecast_&lt;name&gt;_&lt;Zeitstempel&gt;, PVC_SolarForecast_&lt;name&gt;_&lt;Zeitstempel&gt;                                              </td></tr>
            <tr><td>                              </td><td>                                                                                                                                                             </td></tr>
            <tr><td> <b>save</b>                  </td><td>Die aktiven In-Memory Strukturen werden gespeichert.                                                                                                         </td></tr>
            <tr><td>                              </td><td>Dateien: PVH_SolarForecast_&lt;name&gt;, PVC_SolarForecast_&lt;name&gt;                                                                                      </td></tr>
            <tr><td>                              </td><td>                                                                                                                                                             </td></tr>
            <tr><td> <b>recover-&lt;Datei&gt;</b> </td><td>Stellt die Daten der ausgewählten Sicherungsdatei als aktive In-Memory Struktur wieder her.                                                                  </td></tr>
            <tr><td>                              </td><td>Um Inkonsistenzen zu vermeiden, sollten die Dateien PVH.* und PVC.* mit dem gleichen                                                                         </td></tr>
            <tr><td>                              </td><td>Zeitstempel paarweise recovert werden.                                                                                                                       </td></tr>
         </table>
      </ul>
      <br>
    </ul>
    </li>
    <br>

    <ul>
      <a id="SolarForecast-set-operationMode"></a>
      <li><b>operationMode  </b> <br><br>
      Mit <b>inactive</b> wird das SolarForecast Gerät deaktiviert. Die <b>active</b> Option aktiviert das Gerät wieder.
      Das Verhalten entspricht dem "disable"-Attribut, eignet sich aber vor allem zum Einsatz in Perl-Skripten da
      gegenüber dem "disable"-Attribut keine Speicherung der Gerätekonfiguration nötig ist.
    </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-plantConfiguration"></a>
      <li><b>plantConfiguration </b> <br><br>

       Je nach ausgewählter Kommandooption werden folgende Operationen ausgeführt: <br><br>

      <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>check</b>     </td><td>Prüft die aktuelle Anlagenkonfiguration. Es wird eine Plausibilitätsprüfung                  </td></tr>
            <tr><td>                  </td><td>vorgenommen und das Ergebnis sowie eventuelle Hinweise bzw. Fehler ausgegeben.               </td></tr>
            <tr><td> <b>save</b>      </td><td>sichert wichtige Parameter der Anlagenkonfiguration                                          </td></tr>
            <tr><td> <b>restore</b>   </td><td>stellt eine gesicherte Anlagenkonfiguration wieder her                                       </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-powerTrigger"></a>
      <li><b>powerTrigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>

      Generiert Trigger bei Über- bzw. Unterschreitung bestimmter PV Erzeugungswerte (Current_PV). <br>
      Überschreiten die letzten drei Messungen der PV Erzeugung eine definierte <b>Xon-Bedingung</b>, wird das Reading
      <b>powerTrigger_X = on</b> erstellt/gesetzt.
      Unterschreiten die letzten drei Messungen der PV Erzeugung eine definierte <b>Xoff-Bedingung</b>, wird das Reading
      <b>powerTrigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; powerTrigger 1on=1000 1off=500 2on=2000 2off=1000 3on=1600 4off=1100<br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-pvCorrectionFactor_Auto"></a>
      <li><b>pvCorrectionFactor_Auto </b> <br><br>

      Schaltet die automatische Vorhersagekorrektur ein/aus.
      Die Wirkungsweise unterscheidet sich je nach gewählter Methode. <br>
      Das Korrekturverhalten kann mit den Attributen <a href="#SolarForecast-attr-affectNumHistDays">affectNumHistDays</a> und
      <a href="#SolarForecast-attr-affectMaxDayVariance">affectMaxDayVariance</a> beeinflusst werden. <br>
      (default: off)

      <br><br>

      <b>noLearning:</b> <br>
      Mit dieser Option wird die erzeugte PV Energie der aktuellen Stunde vom Lernprozess (Korrekturfaktoren
      sowie KI) ausgeschlossen. <br>
      Die zuvor eingestellte Autokorrekturmethode wird weiterhin angewendet.
      <br><br>

      <b>on_simple(_ai):</b> <br>
      Bei dieser Methode wird die stündlich vorhergesagte mit der real erzeugten Energiemenge verglichen und daraus ein
      für die Zukunft verwendeter Korrekturfaktor für die jeweilige Stunde erstellt. Die von der gewählten API gelieferten
      Prognosedaten werden <b>nicht</b> zusätzlich mit weiteren Bedingungen wie den Bewölkungszustand oder Temperaturen in
      Beziehung gesetzt.<br>
      Ist die KI-Unterstützung eingeschaltet (on_simple_ai) und wird durch die KI ein PV-Prognosewert geliefert, wird dieser Wert
      anstatt des API-Wertes verwendet.
      <br><br>

      <b>on_complex(_ai):</b> <br>
      Bei dieser Methode wird die stündlich vorhergesagte mit der real erzeugten Energiemenge verglichen und daraus ein
      für die Zukunft verwendeter Korrekturfaktor für die jeweilige Stunde erstellt. Die von der gewählten API gelieferten
      Prognosedaten werden außerdem zusätzlich mit weiteren Bedingungen wie den Bewölkungszustand oder Temperaturen
      verknüpft.<br>
      Ist die KI-Unterstützung eingeschaltet (on_complex_ai) und wird durch die KI ein PV-Prognosewert geliefert, wird dieser Wert
      anstatt des API-Wertes verwendet.
      <br><br>

      <b>Hinweis:</b> Die automatische Vorhersagekorrektur ist lernend und benötigt Zeit um die Korrekturwerte zu optimieren.
      Nach der Aktivierung sind nicht sofort optimale Vorhersagen zu erwarten!

      <br><br>

      Nachfolgend einige API-spezifische Hinweise die lediglich Best Practice Empfehlungen darstellen.

      <br><br>

      <b>Model SolCastAPI:</b> <br>
      Die empfohlene Autokorrekturmethode ist <b>on_simple</b>. <br>
      Bevor man die Autokorrektur eingeschaltet, ist die Prognose mit folgenden Schritten zu optimieren: <br><br>
      <ul>
         <li>
         definiere im RoofTop-Editor der SolCast API den
         <a href="https://articles.solcast.com.au/en/articles/2959798-what-is-the-efficiency-factor?_ga=2.119610952.1991905456.1665567573-1390691316.1665567573"><b>efficiency factor</b></a>
         entsprechend dem Alter der Anlage. <br>
         Bei einer 8 Jahre alten Anlage wäre er 84 (100 - (8 x 2%)). <br>
         </li>
         <li>
         nach Sonnenuntergang wird das Reading Today_PVdeviation erstellt, welches die Abweichung zwischen Prognose und
         realer PV Erzeugung in Prozent darstellt.
         </li>
         </li>
         <li>
         entsprechend der Abweichung passe den efficiency factor in Schritten an bis ein Optimum, d.h. die kleinste
         Tagesabweichung gefunden ist
         </li>
         <li>
         ist man der Auffassung die optimale Einstellung gefunden zu haben, kann pvCorrectionFactor_Auto on* gesetzt werden.
         </li>
      </ul>
      <br>

      Idealerweise wird dieser Prozess in einer Phase stabiler meteorologischer Bedingungen (gleichmäßige Sonne bzw.
      Bewölkung) durchgeführt.
      <br><br>

      <b>Model VictronKiAPI:</b> <br>
      Dieses Model basiert auf der KI gestützten API von Victron Energy.
      Eine zusätzliche Autokorrektur wird nicht empfohlen, d.h. die empfohlene Autokorrekturmethode ist <b>off</b>. <br><br>

      <b>Model DWD:</b> <br>
      Die empfohlene Autokorrekturmethode ist <b>on_complex</b> bzw. <b>on_complex_ai</b>. <br><br>

      <b>Model ForecastSolarAPI:</b> <br>
      Die empfohlene Autokorrekturmethode ist <b>on_complex</b>.
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-pvCorrectionFactor_" data-pattern="pvCorrectionFactor_.*"></a>
      <li><b>pvCorrectionFactor_XX &lt;Zahl&gt; </b> <br><br>

      Manueller Korrekturfaktor für die Stunde XX des Tages zur Anpassung der Vorhersage an die individuelle Anlage. <br>
      (default: 1.0)
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-reset"></a>
      <li><b>reset </b> <br><br>

       Löscht die aus der Drop-Down Liste gewählte Datenquelle, zu der Funktion gehörende Readings oder weitere interne
       Datenstrukturen. <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>aiData</b>             </td><td>löscht eine vorhandene KI Instanz inklusive aller Trainingsdaten und initialisiert sie neu                              </td></tr>
            <tr><td> <b>batteryTriggerSet</b>  </td><td>löscht die Triggerpunkte des Batteriespeichers                                                                          </td></tr>
            <tr><td> <b>consumerPlanning</b>   </td><td>löscht die Planungsdaten aller registrierten Verbraucher                                                                </td></tr>
            <tr><td>                           </td><td>Um die Planungsdaten nur eines Verbrauchers zu löschen verwendet man:                                                   </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerPlanning &lt;Verbrauchernummer&gt; </ul>                                             </td></tr>
            <tr><td>                           </td><td>Das Modul führt eine automatische Neuplanung der Verbraucherschaltung durch.                                            </td></tr>
            <tr><td> <b>consumerMaster</b>     </td><td>löscht die Daten aller registrierten Verbraucher aus dem Speicher                                                       </td></tr>
            <tr><td>                           </td><td>Um die Daten nur eines Verbrauchers zu löschen verwendet man:                                                           </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerMaster &lt;Verbrauchernummer&gt; </ul>                                               </td></tr>
            <tr><td> <b>consumption</b>        </td><td>löscht die gespeicherten Verbrauchswerte des Hauses                                                                     </td></tr>
            <tr><td>                           </td><td>Um die Verbrauchswerte eines bestimmten Tages zu löschen:                                                               </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumption &lt;Tag&gt;   (z.B. set &lt;name&gt; reset consumption 08) </ul>                 </td></tr>
            <tr><td>                           </td><td>Um die Verbrauchswerte einer bestimmten Stunde eines Tages zu löschen:                                                  </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumption &lt;Tag&gt; &lt;Stunde&gt; (z.B. set &lt;name&gt; reset consumption 08 10) </ul> </td></tr>
            <tr><td> <b>currentBatterySet</b>  </td><td>löscht das eingestellte Batteriedevice und korrespondierende Daten                                                      </td></tr>
            <tr><td> <b>currentInverterSet</b> </td><td>löscht das eingestellte Inverterdevice und korrespondierende Daten                                                      </td></tr>
            <tr><td> <b>currentMeterSet</b>    </td><td>löscht das eingestellte Meterdevice und korrespondierende Daten                                                         </td></tr>
            <tr><td> <b>energyH4TriggerSet</b> </td><td>löscht die 4-Stunden Energie Triggerpunkte                                                                              </td></tr>
            <tr><td> <b>inverterStringSet</b>  </td><td>löscht die Stringkonfiguration der Anlage                                                                               </td></tr>
            <tr><td> <b>powerTriggerSet</b>    </td><td>löscht die Triggerpunkte für PV Erzeugungswerte                                                                         </td></tr>
            <tr><td> <b>pvCorrection</b>       </td><td>löscht die Readings pvCorrectionFactor*                                                                                 </td></tr>
            <tr><td>                           </td><td>Um alle bisher gespeicherten PV Korrekturfaktoren aus den Caches zu löschen:                                            </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection cached </ul>                                                                    </td></tr>
            <tr><td>                           </td><td>Um gespeicherte PV Korrekturfaktoren einer bestimmten Stunde aus den Caches zu löschen:                                 </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection cached &lt;Stunde&gt;  </ul>                                                    </td></tr>
            <tr><td>                           </td><td><ul>(z.B. set &lt;name&gt; reset pvCorrection cached 10)       </ul>                                                    </td></tr>
            <tr><td> <b>pvHistory</b>          </td><td>löscht den Speicher aller historischen Tage (01 ... 31)                                                                 </td></tr>
            <tr><td>                           </td><td>Um einen bestimmten historischen Tag zu löschen:                                                                        </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Tag&gt;   (z.B. set &lt;name&gt; reset pvHistory 08) </ul>                     </td></tr>
            <tr><td>                           </td><td>Um eine bestimmte Stunde eines historischer Tages zu löschen:                                                           </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Tag&gt; &lt;Stunde&gt;  (z.B. set &lt;name&gt; reset pvHistory 08 10) </ul>    </td></tr>
            <tr><td> <b>moduleRoofTopSet</b>   </td><td>löscht die SolCast API Rooftops                                                                                         </td></tr>
            <tr><td> <b>roofIdentPair</b>      </td><td>löscht alle gespeicherten SolCast API Rooftop-ID / API-Key Paare                                                        </td></tr>
            <tr><td>                           </td><td>Um ein bestimmtes Paar zu löschen ist dessen Schlüssel &lt;pk&gt; anzugeben:                                            </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset roofIdentPair &lt;pk&gt;   (z.B. set &lt;name&gt; reset roofIdentPair p1) </ul>              </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-roofIdentPair"></a>
      <li><b>roofIdentPair &lt;pk&gt; rtid=&lt;Rooftop-ID&gt; apikey=&lt;SolCast API Key&gt; </b> <br>
       (nur bei Verwendung Model SolCastAPI) <br><br>

       Der Abruf jedes in <a href='https://toolkit.solcast.com.au/rooftop-sites' target='_blank'>SolCast Rooftop Sites</a>
       angelegten Rooftops ist mit der Angabe eines Paares <b>Rooftop-ID</b> und <b>API-Key</b> zu identifizieren. <br>
       Der Schlüssel &lt;pk&gt; kennzeichnet eindeutig ein verbundenes Paar Rooftop-ID / API-Key. Es können beliebig viele
       Paare <b>nacheinander</b> angelegt werden. In dem Fall ist jeweils ein neuer Name für "&lt;pk&gt;" zu verwenden.
       <br><br>

       Der Schlüssel &lt;pk&gt; wird im Setter <a href="#SolarForecast-set-moduleRoofTops">moduleRoofTops</a> der abzurufenden
       Rooftops (=Strings) zugeordnet.
       <br><br>

       <ul>
        <b>Beispiele: </b> <br>
        set &lt;name&gt; roofIdentPair p1 rtid=92fc-6796-f574-ae5f apikey=oNHDbkKuC_eGEvZe7ECLl6-T1jLyfOgC <br>
        set &lt;name&gt; roofIdentPair p2 rtid=f574-ae5f-92fc-6796 apikey=eGEvZe7ECLl6_T1jLyfOgC_oNHDbkKuC <br>
       </ul>

        <br>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-vrmCredentials"></a>
      <li><b>vrmCredentials user=&lt;Benutzer&gt; pwd=&lt;Paßwort&gt; idsite=&lt;idSite&gt; </b> <br>
      (nur bei Verwendung Model VictronKiAPI) <br><br>

       Wird die Victron VRM API genutzt, sind mit diesem set-Befehl die benötigten Zugangsdaten zu hinterlegen. <br><br>

      <ul>
         <table>
         <colgroup> <col width="10%"> <col width="90%"> </colgroup>
            <tr><td> <b>user</b>   </td><td>Benutzername für das Victron VRM Portal                                           </td></tr>
            <tr><td> <b>pwd</b>    </td><td>Paßwort für den Zugang zum Victron VRM Portal                                     </td></tr>
            <tr><td> <b>idsite</b> </td><td>idSite ist der Bezeichner "XXXXXX" in der Victron VRM Portal Dashboard URL.       </td></tr>
            <tr><td>               </td><td>URL des Victron VRM Dashboard ist:                                                </td></tr>
            <tr><td>               </td><td>https://vrm.victronenergy.com/installation/<b>XXXXXX</b>/dashboard                </td></tr>
         </table>
      </ul>
      <br>

      Um die gespeicherten Credentials zu löschen, ist dem Kommando nur das Argument <b>delete</b> zu übergeben. <br><br>

       <ul>
        <b>Beispiele: </b> <br>
        set &lt;name&gt; vrmCredentials user=john@example.com pwd=somepassword idsite=212008 <br>
        set &lt;name&gt; vrmCredentials delete <br>
       </ul>

      </li>
    </ul>
    <br>

  </ul>
  <br>

  <a id="SolarForecast-get"></a>
  <b>Get</b>
  <ul>
    <ul>
      <a id="SolarForecast-get-data"></a>
      <li><b>data </b> <br><br>
      Startet die Datensammlung zur Bestimmung der solaren Vorhersage und anderer Werte.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-forecastQualities"></a>
      <li><b>forecastQualities </b> <br><br>
      Zeigt die zur Bestimmung der PV Vorhersage aktuell verwendeten Korrekturfaktoren mit der jeweiligen Startzeit sowie
      die bisher im Durchschnitt erreichte Vorhersagequalität dieses Zeitraumes an.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-ftuiFramefiles"></a>
      <li><b>ftuiFramefiles </b> <br><br>
      SolarForecast stellt Widgets für
      <a href='https://wiki.fhem.de/wiki/FHEM_Tablet_UI' target='_blank'>FHEM Tablet UI v2 (FTUI2)</a> zur Verfügung. <br>
      Ist FTUI2 auf dem System installiert, können die Dateien für das Framework mit diesem Kommando in die
      FTUI-Verzeichnisstruktur geladen werden. <br>
      Die Einrichtung und Verwendung der Widgets ist im Wiki
      <a href='https://wiki.fhem.de/wiki/SolarForecast_FTUI_Widget' target='_blank'>SolarForecast FTUI Widget</a>
      beschrieben.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-html"></a>
      <li><b>html </b> <br><br>
      Die SolarForecast Grafik wird als HTML-Code abgerufen und wiedergegeben. <br>
      <b>Hinweis:</b> Durch das Attribut <a href="#SolarForecast-attr-graphicHeaderOwnspec ">graphicHeaderOwnspec</a>
      generierte set-Kommandos oder Attribut-Befehle im Anwender spezifischen Bereich des Headers werden aus technischen
      Gründen generell ausgeblendet. <br>
      Als Argument kann dem Befehl eine der folgenden Selektionen mitgegeben werden:
      <br><br>

      <ul>
        <table>
        <colgroup> <col width="30%"> <col width="70%"> </colgroup>
        <tr><td> <b>both</b>                    </td><td>zeigt den Header, die Verbraucherlegende, Energiefluß- und Vorhersagegrafik an (default)   </td></tr>
        <tr><td> <b>both_noHead</b>             </td><td>zeigt die Verbraucherlegende, Energiefluß- und Vorhersagegrafik an                         </td></tr>
        <tr><td> <b>both_noCons</b>             </td><td>zeigt den Header, Energiefluß- und Vorhersagegrafik an                                     </td></tr>
        <tr><td> <b>both_noHead_noCons</b>      </td><td>zeigt Energiefluß- und Vorhersagegrafik an                                                 </td></tr>
        <tr><td> <b>flow</b>                    </td><td>zeigt den Header, die Verbraucherlegende und Energieflußgrafik an                          </td></tr>
        <tr><td> <b>flow_noHead</b>             </td><td>zeigt die Verbraucherlegende und die Energieflußgrafik an                                  </td></tr>
        <tr><td> <b>flow_noCons</b>             </td><td>zeigt den Header und die Energieflußgrafik an                                              </td></tr>
        <tr><td> <b>flow_noHead_noCons</b>      </td><td>zeigt die Energieflußgrafik an                                                             </td></tr>
        <tr><td> <b>forecast</b>                </td><td>zeigt den Header, die Verbraucherlegende und die Vorhersagegrafik an                       </td></tr>
        <tr><td> <b>forecast_noHead</b>         </td><td>zeigt die Verbraucherlegende und die Vorhersagegrafik an                                   </td></tr>
        <tr><td> <b>forecast_noCons</b>         </td><td>zeigt den Header und die Vorhersagegrafik an                                               </td></tr>
        <tr><td> <b>forecast_noHead_noCons</b>  </td><td>zeigt die Vorhersagegrafik an                                                              </td></tr>
        <tr><td> <b>none</b>                    </td><td>zeigt nur den Header und die Verbraucherlegende an                                         </td></tr>
        </table>
      </ul>
      <br>

      Die Grafik kann abgerufen und in eigenen Code eingebettet werden. Auf einfache Weise kann dies durch die Definition
      eines weblink-Devices vorgenommen werden: <br><br>

      <ul>
        define wl.SolCast5 weblink htmlCode { FHEM::SolarForecast::pageAsHtml ('SolCast5', '-', '&lt;argument&gt;') }
      </ul>
      <br>
      'SolCast5' ist der Name des einzubindenden SolarForecast-Device. <b>&lt;argument&gt;</b> ist eine der oben
      beschriebenen Auswahlmöglichkeiten.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-nextHours"></a>
      <li><b>nextHours </b> <br><br>
      Listet die erwarteten Werte der kommenden Stunden auf. <br><br>

      <ul>
         <table>
         <colgroup> <col width="10%"> <col width="90%"> </colgroup>
            <tr><td> <b>aihit</b>     </td><td>Lieferstatus der KI für die PV Vorhersage (0-keine Lieferung, 1-Lieferung)         </td></tr>
            <tr><td> <b>confc</b>     </td><td>erwarteter Energieverbrauch inklusive der Anteile registrierter Verbraucher        </td></tr>
            <tr><td> <b>confcEx</b>   </td><td>erwarteter Energieverbrauch ohne der Anteile registrierter Verbraucher             </td></tr>
            <tr><td> <b>crange</b>    </td><td>berechneter Bewölkungsbereich                                                      </td></tr>
            <tr><td> <b>correff</b>   </td><td>verwendeter Korrekturfaktor/Qualität                                               </td></tr>
            <tr><td>                  </td><td>Faktor/- -> keine Qualität definiert                                               </td></tr>
            <tr><td>                  </td><td>Faktor/0..1 - Qualität der PV Prognose (1 = beste Qualität)                        </td></tr>
            <tr><td> <b>DoN</b>       </td><td>Sonnenauf- und untergangsstatus (0 - Nacht, 1 - Tag)                               </td></tr>
            <tr><td> <b>hourofday</b> </td><td>laufende Stunde des Tages                                                          </td></tr>
            <tr><td> <b>pvapifc</b>   </td><td>erwartete PV Erzeugung (Wh) der verwendeten API inkl. einer eventuellen Korrektur  </td></tr>
            <tr><td> <b>pvaifc</b>    </td><td>erwartete PV Erzeugung der KI (Wh)                                                 </td></tr>
            <tr><td> <b>pvfc</b>      </td><td>verwendete PV Erzeugungsprognose (Wh)                                              </td></tr>
            <tr><td> <b>rad1h</b>     </td><td>vorhergesagte Globalstrahlung                                                      </td></tr>
            <tr><td> <b>rrange</b>    </td><td>berechneter Bereich der Regenwahrscheinlichkeit                                    </td></tr>
            <tr><td> <b>starttime</b> </td><td>Startzeit des Datensatzes                                                          </td></tr>
            <tr><td> <b>temp</b>      </td><td>vorhergesagte Außentemperatur                                                      </td></tr>
            <tr><td> <b>today</b>     </td><td>hat Wert '1' wenn Startdatum am aktuellen Tag                                      </td></tr>
            <tr><td> <b>wrp</b>       </td><td>vorhergesagter Grad der Regenwahrscheinlichkeit                                    </td></tr>
            <tr><td> <b>wid</b>       </td><td>ID des vorhergesagten Wetters                                                      </td></tr>
            <tr><td> <b>wcc</b>       </td><td>vorhergesagter Grad der Bewölkung                                                  </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-pvHistory"></a>
      <li><b>pvHistory </b> <br><br>
      Zeigt den Inhalt des pvHistory Datenspeichers sortiert nach dem Tagesdatum und Stunde. Mit der Auswahlliste kann ein
      bestimmter Tag angesprungen werden. Die Drop-Down Liste enthält die aktuell im Speicher verfügbaren Tage.
      Ohne Argument wird der gesamte Datenspeicher gelistet.

      Die Stundenangaben beziehen sich auf die jeweilige Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit
      von 08 Uhr bis 09 Uhr. <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>etotal</b>         </td><td>totaler Energieertrag (Wh) zu Beginn der Stunde                                                </td></tr>
            <tr><td> <b>pvfc</b>           </td><td>der prognostizierte PV Ertrag (Wh)                                                             </td></tr>
            <tr><td> <b>pvrl</b>           </td><td>reale PV Erzeugung (Wh)                                                                        </td></tr>
            <tr><td> <b>pvrlvd</b>         </td><td>1-'pvrl' ist gültig und wird im Lernprozess berücksichtigt, 0-'pvrl' ist als abnormal bewertet </td></tr>
            <tr><td> <b>gcon</b>           </td><td>realer Leistungsbezug (Wh) aus dem Stromnetz                                                   </td></tr>
            <tr><td> <b>confc</b>          </td><td>erwarteter Energieverbrauch (Wh)                                                               </td></tr>
            <tr><td> <b>con</b>            </td><td>realer Energieverbrauch (Wh) des Hauses                                                        </td></tr>
            <tr><td> <b>gfeedin</b>        </td><td>reale Einspeisung (Wh) in das Stromnetz                                                        </td></tr>
            <tr><td> <b>batintotal</b>     </td><td>totale Batterieladung (Wh) zu Beginn der Stunde                                                </td></tr>
            <tr><td> <b>batin</b>          </td><td>Batterieladung der Stunde (Wh)                                                                 </td></tr>
            <tr><td> <b>batouttotal</b>    </td><td>totale Batterieentladung (Wh) zu Beginn der Stunde                                             </td></tr>
            <tr><td> <b>batout</b>         </td><td>Batterieentladung der Stunde (Wh)                                                              </td></tr>
            <tr><td> <b>batmaxsoc</b>      </td><td>maximaler SOC (%) des Tages                                                                    </td></tr>
            <tr><td> <b>batsetsoc</b>      </td><td>optimaler SOC Sollwert (%) für den Tag                                                         </td></tr>
            <tr><td> <b>wid</b>            </td><td>Identifikationsnummer des Wetters                                                              </td></tr>
            <tr><td> <b>wcc</b>            </td><td>effektive Wolkenbedeckung                                                                      </td></tr>
            <tr><td> <b>wrp</b>            </td><td>Wahrscheinlichkeit von Niederschlag > 0,1 mm während der jeweiligen Stunde                     </td></tr>
            <tr><td> <b>pvcorrf</b>        </td><td>verwendeter Autokorrekturfaktor / erreichte Prognosequalität                                   </td></tr>
            <tr><td> <b>rad1h</b>          </td><td>Globalstrahlung (kJ/m2)                                                                        </td></tr>
            <tr><td> <b>csmtXX</b>         </td><td>Energieverbrauch total von ConsumerXX                                                          </td></tr>
            <tr><td> <b>csmeXX</b>         </td><td>Energieverbrauch von ConsumerXX in der Stunde des Tages (Stunde 99 = Tagesenergieverbrauch)    </td></tr>
            <tr><td> <b>minutescsmXX</b>   </td><td>Summe Aktivminuten in der Stunde von ConsumerXX                                                </td></tr>
            <tr><td> <b>hourscsmeXX</b>    </td><td>durchschnittliche Stunden eines Aktivzyklus von ConsumerXX des Tages                           </td></tr>
            <tr><td> <b>cyclescsmXX</b>    </td><td>Anzahl aktive Zyklen von ConsumerXX des Tages                                                  </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-pvCircular"></a>
      <li><b>pvCircular </b> <br><br>
      Listet die vorhandenen Werte im Ringspeicher auf.
      Die Stundenangaben 01 - 24 beziehen sich auf die Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit von
      08 - 09 Uhr. <br>
      Die Stunde 99 hat eine Sonderfunktion. <br>
      Erläuterung der Werte: <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>aihit</b>            </td><td>Lieferstatus der KI für die PV Vorhersage (0-keine Lieferung, 1-Lieferung)                                                </td></tr>
            <tr><td> <b>batin</b>            </td><td>Batterieladung (Wh)                                                                                                       </td></tr>
            <tr><td> <b>batout</b>           </td><td>Batterieentladung (Wh)                                                                                                    </td></tr>
            <tr><td> <b>batouttot</b>        </td><td>total aus der Batterie entnommene Energie (Wh)                                                                            </td></tr>
            <tr><td> <b>batintot</b>         </td><td>total in die Batterie geladene Energie (Wh)                                                                               </td></tr>
            <tr><td> <b>confc</b>            </td><td>erwarteter Energieverbrauch (Wh)                                                                                          </td></tr>
            <tr><td> <b>corr</b>             </td><td>Autokorrekturfaktoren für die Stunde des Tages, wobei "percentile" der einfache (simple) Korrekturfaktor ist.             </td></tr>
            <tr><td> <b>days2care</b>        </td><td>verbleibende Tage bis der Batterie Pflege-SoC (default 95%) erreicht sein soll                                            </td></tr>
            <tr><td> <b>feedintotal</b>      </td><td>in das öffentliche Netz total eingespeiste PV Energie (Wh)                                                                </td></tr>
            <tr><td> <b>gcon</b>             </td><td>realer Leistungsbezug aus dem Stromnetz                                                                                   </td></tr>
            <tr><td> <b>gfeedin</b>          </td><td>reale Leistungseinspeisung in das Stromnetz                                                                               </td></tr>
            <tr><td> <b>gridcontotal</b>     </td><td>vom öffentlichen Netz total bezogene Energie (Wh)                                                                         </td></tr>
            <tr><td> <b>initdayfeedin</b>    </td><td>initialer PV Einspeisewert zu Beginn des aktuellen Tages (Wh)                                                             </td></tr>
            <tr><td> <b>initdaygcon</b>      </td><td>initialer Netzbezugswert zu Beginn des aktuellen Tages (Wh)                                                               </td></tr>
            <tr><td> <b>initdaybatintot</b>  </td><td>initialer Wert der total in die Batterie geladenen Energie zu Beginn des aktuellen Tages (Wh)                             </td></tr>
            <tr><td> <b>initdaybatouttot</b> </td><td>initialer Wert der total aus der Batterie entnommenen Energie zu Beginn des aktuellen Tages (Wh)                          </td></tr>
            <tr><td> <b>lastTsMaxSocRchd</b> </td><td>Timestamp des letzten Erreichens von Batterie SoC >= maxSoC (default 95%)                                                 </td></tr>
            <tr><td> <b>nextTsMaxSocChge</b> </td><td>Timestamp bis zu dem die Batterie mindestens einmal maxSoC erreichen soll                                                 </td></tr>
            <tr><td> <b>pvapifc</b>          </td><td>erwartete PV Erzeugung (Wh) der verwendeten API                                                                           </td></tr>
            <tr><td> <b>pvaifc</b>           </td><td>PV Vorhersage (Wh) der KI für die nächsten 24h ab aktueller Stunde des Tages                                              </td></tr>
            <tr><td> <b>pvfc</b>             </td><td>verwendete PV Prognose für die nächsten 24h ab aktueller Stunde des Tages                                                 </td></tr>
            <tr><td> <b>pvrl</b>             </td><td>reale PV Erzeugung der letzten 24h (Achtung: pvforecast und pvreal beziehen sich nicht auf den gleichen Zeitraum!)        </td></tr>
            <tr><td> <b>quality</b>          </td><td>Qualität der Autokorrekturfaktoren (0..1), wobei "percentile" die Qualität des einfachen (simple) Korrekturfaktors ist.   </td></tr>
            <tr><td> <b>runTimeTrainAI</b>   </td><td>Laufzeit des letzten KI Trainings                                                                                         </td></tr>
            <tr><td> <b>tdayDvtn</b>         </td><td>heutige Abweichung PV Prognose/Erzeugung in %                                                                             </td></tr>
            <tr><td> <b>temp</b>             </td><td>Außentemperatur                                                                                                           </td></tr>
            <tr><td> <b>wcc</b>              </td><td>Grad der Wolkenüberdeckung                                                                                                </td></tr>
            <tr><td> <b>wrp</b>              </td><td>Grad der Regenwahrscheinlichkeit                                                                                          </td></tr>
            <tr><td> <b>wid</b>              </td><td>ID des vorhergesagten Wetters                                                                                             </td></tr>
            <tr><td> <b>wtxt</b>             </td><td>Beschreibung des vorhergesagten Wetters                                                                                   </td></tr>
            <tr><td> <b>ydayDvtn</b>         </td><td>Abweichung PV Prognose/Erzeugung in % am Vortag                                                                           </td></tr>
         </table>
      </ul>

      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-rooftopData"></a>
      <li><b>rooftopData </b> <br><br>
      Die erwarteten solaren Strahlungsdaten bzw. PV Erzeugungsdaten werden von der gewählten API abgerufen.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-solApiData"></a>
      <li><b>solApiData </b> <br><br>

      Listet die im Kontext des API-Abrufs gespeicherten Daten auf.
      Verwaltungsdatensätze sind mit einem führenden '?' gekennzeichnet.
      Die von der API gelieferten Vorhersagedaten bzgl. des PV Ertrages (Wh) sind auf eine Stunde konsolidiert.
      <br><br>

      <ul>
         <table>
         <colgroup> <col width="37%"> <col width="63%"> </colgroup>
            <tr><td> <b>currentAPIinterval</b>        </td><td>das aktuell verwendete API Abrufintervall in Sekunden            </td></tr>
            <tr><td> <b>lastretrieval_time</b>        </td><td>Zeit des letzten API Abrufs                                      </td></tr>
            <tr><td> <b>lastretrieval_timestamp</b>   </td><td>Unix Timestamp des letzten API Abrufs                            </td></tr>
            <tr><td> <b>pv_estimate</b>               </td><td>erwartete PV Erzeugung (Wh)                                      </td></tr>
            <tr><td> <b>todayDoneAPIrequests</b>      </td><td>Anzahl der ausgeführten API Requests am aktuellen Tag            </td></tr>
            <tr><td> <b>todayRemainingAPIrequests</b> </td><td>Anzahl der verbleibenden SolCast API Requests am aktuellen Tag   </td></tr>
            <tr><td> <b>todayDoneAPIcalls</b>         </td><td>Anzahl der ausgeführten API Abrufe am aktuellen Tag              </td></tr>
            <tr><td> <b>todayRemainingAPIcalls</b>    </td><td>Anzahl der noch möglichen SolCast API Abrufe am aktuellen Tag    </td></tr>
            <tr><td>                                  </td><td>(ein Abruf kann mehrere SolCast API Requests ausführen)          </td></tr>
            <tr><td> <b>todayMaxAPIcalls</b>          </td><td>Anzahl der maximal möglichen SolCast API Abrufe pro Tag          </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valConsumerMaster"></a>
      <li><b>valConsumerMaster </b> <br><br>
      Zeigt die Daten der aktuell im SolarForecast Device registrierten Verbraucher. <br>
      Mit der Auswahlliste kann ein bestimmter Verbraucher angesprungen werden. Die Drop-Down Liste enthält die aktuell
      im Datenspeicher verfügbaren Verbraucher bzw. Verbrauchernummern. Ohne Argument wird der gesamte Datenspeicher gelistet.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valCurrent"></a>
      <li><b>valCurrent </b> <br><br>
      Listet aktuelle Betriebsdaten, Kennzahlen und Status auf.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valDecTree"></a>
      <li><b>valDecTree </b> <br><br>

      Ist der KI Support im SolarForecast Device aktiviert, können verschiedene KI relevante Daten angezeigt werden                  :
      <br><br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>aiRawData</b>     </td><td>Die aktuell für die KI gespeicherten PV-, Strahlungs- und Umweltdaten.                     </td></tr>
          <tr><td> <b>aiRuleStrings</b> </td><td>Gibt eine Liste zurück, die den Entscheidungsbaum der KI in Form von Regeln beschreibt.    </td></tr>
          <tr><td>                      </td><td><b>Hinweis:</b> Die Reihenfolge der Regeln ist zwar nicht vorhersehbar, die                </td></tr>
          <tr><td>                      </td><td>Reihenfolge der Kriterien innerhalb jeder Regel spiegelt jedoch die Reihenfolge            </td></tr>
          <tr><td>                      </td><td>wider, in der die Kriterien bei der Entscheidungsfindung geprüft werden.                   </td></tr>
        </table>
      </ul>
    </li>
    </ul>
    <br>

  </ul>
  <br>

  <a id="SolarForecast-attr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
     <ul>
       <a id="SolarForecast-attr-affect70percentRule"></a>
       <li><b>affect70percentRule</b><br>
         Wenn gesetzt, wird die prognostizierte Leistung entsprechend der 70% Regel begrenzt. <br><br>

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>0</b>       </td><td>keine Begrenzung der prognostizierten PV-Erzeugung (default)                                 </td></tr>
            <tr><td> <b>1</b>       </td><td>die prognostizierte PV-Erzeugung wird auf 70% der installierten Stringleistung(en) begrenzt  </td></tr>
            <tr><td> <b>dynamic</b> </td><td>die prognostizierte PV-Erzeugung wird begrenzt wenn 70% der installierten                    </td></tr>
            <tr><td>                </td><td>Stringleistung(en) zzgl. des prognostizierten Verbrauchs überschritten wird                  </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-affectBatteryPreferredCharge"></a>
       <li><b>affectBatteryPreferredCharge </b><br>
         Es werden Verbraucher mit dem Mode <b>can</b> erst dann eingeschaltet, wenn die angegebene Batterieladung (%)
         erreicht ist. <br>
         Verbraucher mit dem Mode <b>must</b> beachten die Vorrangladung der Batterie nicht. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-affectConsForecastInPlanning"></a>
       <li><b>affectConsForecastInPlanning </b><br>
         Wenn gesetzt, wird bei der Einplanung der Consumer zusätzlich zur PV Prognose ebenfalls die Prognose
         des Verbrauchs berücksichtigt. <br>
         Die Standardplanung der Consumer erfolgt lediglich auf Grundlage der PV Prognose. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-affectConsForecastIdentWeekdays"></a>
       <li><b>affectConsForecastIdentWeekdays </b><br>
         Wenn gesetzt, werden zur Berechnung der Verbrauchsprognose nur gleiche Wochentage (Mo..So) einbezogen. <br>
         Anderenfalls werden alle Wochentage gleichberechtigt zur Kalkulation verwendet. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-affectMaxDayVariance"></a>
       <li><b>affectMaxDayVariance &lt;Zahl&gt; </b><br>
         Maximale Änderungsgröße des PV Vorhersagefaktors (Reading pvCorrectionFactor_XX) pro Tag. <br>
         Auf das Lern- und Prognoseverhalten einer eventuell verwendeten KI-Unterstützung
         (<a href="#SolarForecast-set-pvCorrectionFactor_Auto">pvCorrectionFactor_Auto</a>) hat diese Einstellung keinen
         Einfluß. <br>
         (default: 0.5)
       </li>
       <br>

       <a id="SolarForecast-attr-affectNumHistDays"></a>
       <li><b>affectNumHistDays </b><br>
         Anzahl der in den Caches verfügbaren historischen Tage, die zur Berechnung der Autokorrekturwerte der
         PV Vorhersage verwendet werden sollen. <br>
         (default: alle verfügbaren Daten in pvHistory und pvCircular)
       </li>
       <br>

       <a id="SolarForecast-attr-affectSolCastPercentile"></a>
       <li><b>affectSolCastPercentile &lt;10 | 50 | 90&gt; </b><br>
         (nur bei Verwendung Model SolCastAPI) <br><br>

         Auswahl des Wahrscheinlichkeitsbereiches der gelieferten SolCast-Daten.
         SolCast liefert die 10- und 90-prozentige Wahrscheinlichkeit um den Prognosemittelwert (50) herum. <br>
         (default: 50)
       </li>
       <br>

        <a id="SolarForecast-attr-alias"></a>
        <li><b>alias </b> <br>
          In Verbindung mit "ctrlShowLink" ein beliebiger Anzeigename.
        </li>
        <br>

       <a id="SolarForecast-attr-consumerAdviceIcon"></a>
       <li><b>consumerAdviceIcon </b><br>
         Definiert die Art der Information über die geplanten Schaltzeiten eines Verbrauchers in der Verbraucherlegende.
         <br><br>
         <ul>
         <table>
         <colgroup> <col width="18%"> <col width="82%"> </colgroup>
            <tr><td> <b>&lt;Icon&gt@&lt;Farbe&gt</b>  </td><td>Aktivierungsempfehlung wird durch Icon und Farbe (optional) dargestellt (default: light_light_dim_100@gold)   </td></tr>
            <tr><td>                                  </td><td>(die Planungsdaten werden als Mouse-Over Text angezeigt)                                                      </td></tr>
            <tr><td> <b>times</b>                     </td><td>es werden der Planungsstatus und die geplanten Schaltzeiten als Text angezeigt                                </td></tr>
            <tr><td> <b>none</b>                      </td><td>keine Anzeige der Planungsdaten                                                                               </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-consumerLegend"></a>
       <li><b>consumerLegend </b><br>
         Definiert die Lage bzw. Darstellungsweise der Verbraucherlegende sofern Verbraucher im SolarForecast Device
         registriert sind. <br>
         (default: icon_top)
       </li>
       <br>

       <a id="SolarForecast-attr-consumerLink"></a>
       <li><b>consumerLink </b><br>
         Wenn gesetzt, kann man in der Verbraucher-Liste (consumerLegend) die jeweiligen Verbraucher anklicken und gelangt
         direkt zur Detailansicht des jeweiligen Geräts auf einer neuen Browserseite. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-consumer" data-pattern="consumer.*"></a>
       <li><b>consumerXX &lt;Device Name&gt; type=&lt;type&gt; power=&lt;power&gt; [switchdev=&lt;device&gt;]<br>
                         [mode=&lt;mode&gt;] [icon=&lt;Icon&gt;] [mintime=&lt;minutes&gt; | SunPath[:&lt;Offset_Sunrise&gt;:&lt;Offset_Sunset&gt;]]                                                <br>
                         [on=&lt;Kommando&gt;] [off=&lt;Kommando&gt;] [swstate=&lt;Readingname&gt;:&lt;on-Regex&gt;:&lt;off-Regex&gt] [asynchron=&lt;Option&gt]                                    <br>
                         [notbefore=&lt;Ausdruck&gt;] [notafter=&lt;Ausdruck&gt;] [locktime=&lt;offlt&gt;[:&lt;onlt&gt;]]                                                                          <br>
                         [auto=&lt;Readingname&gt;] [pcurr=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Schwellenwert&gt]] [etotal=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Schwellenwert&gt]]         <br>
                         [swoncond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [swoffcond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [spignorecond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] <br>
                         [interruptable=&lt;Option&gt] [noshow=&lt;Option&gt] </b><br>
                         <br>

        Registriert einen Verbraucher &lt;Device Name&gt; beim SolarForecast Device. Dabei ist &lt;Device Name&gt;
        ein in FHEM bereits angelegtes Verbraucher Device, z.B. eine Schaltsteckdose.
        Die meisten Schlüssel sind optional, sind aber für bestimmte Funktionalitäten Voraussetzung und werden mit
        default-Werten besetzt. <br>
        Ist der Schüssel "auto" definiert, kann der Automatikmodus in der integrierten Verbrauchergrafik mit den
        entsprechenden Drucktasten umgeschaltet werden. Das angegebene Reading wird ggf. im Consumer Device angelegt falls
        es nicht vorhanden ist. <br><br>

        Mit dem optionalen Schlüssel <b>swoncond</b> kann eine <b>zusätzliche externe Bedingung</b> definiert werden um den Einschaltvorgang des
        Consumers freizugeben. Ist die Bedingung (Regex) nicht erfüllt, erfolgt kein Einschalten des Verbrauchers auch wenn die
        sonstigen Voraussetzungen wie Zeitplanung, on-Schlüssel, auto-Mode und aktuelle PV-Leistung gegeben sind. Es erfolgt somit eine
        <b>UND-Verknüpfung</b> des Schlüssels swoncond mit den weiteren Einschaltbedingungen. <br><br>

        Der optionale Schlüssel <b>swoffcond</b> definiert eine <b>vorrangige Ausschaltbedingung</b> (Regex). Sobald diese
        Bedingung erfüllt ist, wird der Consumer ausgeschaltet auch wenn die geplante Endezeit (consumerXX_planned_stop)
        noch nicht erreicht ist (<b>ODER-Verknüpfung</b>). Weitere Bedingungen wie off-Schlüssel und auto-Mode müssen
        zum automatischen Ausschalten erfüllt sein. <br><br>

        Mit dem optionalen Schlüssel <b>interruptable</b> kann während der geplanten Einschaltzeit eine automatische
        Unterbrechung sowie Wiedereinschaltung des Verbrauchers vorgenommen werden.
        Der Verbraucher wird temporär ausgeschaltet (interrupted) und wieder eingeschaltet (continued) wenn die
        Interrupt-Bedingung nicht mehr vorliegt.
        Die verbleibende Laufzeit wird durch einen Interrupt nicht beeinflusst!
        <br><br>

        Der Schlüssel <b>power</b> gibt die nominale Leistungsaufnahme des Verbrauchers gemäß seines Datenblattes an.
        Dieser Wert wird verwendet um die Schaltzeiten des Verbrauchers zu planen und das Schalten in Abhängigkeit
        des tatsächlichen PV-Überschusses zum Einplanungszeitpunkt zu steuern.
        Ist <b>power=0</b> gesetzt, wird der Verbraucher unabhängig von einem ausreichend vorhandenem PV-Überschuß
        wie eingeplant geschaltet.
        <br><br>

         <ul>
         <table>
         <colgroup> <col width="12%"> <col width="88%"> </colgroup>
            <tr><td> <b>type</b>           </td><td>Typ des Verbrauchers. Folgende Typen sind erlaubt:                                                                                                 </td></tr>
            <tr><td>                       </td><td><b>dishwasher</b>     - Verbraucher ist eine Spülmaschine                                                                                          </td></tr>
            <tr><td>                       </td><td><b>dryer</b>          - Verbraucher ist ein Wäschetrockner                                                                                         </td></tr>
            <tr><td>                       </td><td><b>washingmachine</b> - Verbraucher ist eine Waschmaschine                                                                                         </td></tr>
            <tr><td>                       </td><td><b>heater</b>         - Verbraucher ist ein Heizstab                                                                                               </td></tr>
            <tr><td>                       </td><td><b>charger</b>        - Verbraucher ist eine Ladeeinrichtung (Akku, Auto, Fahrrad, etc.)                                                           </td></tr>
            <tr><td>                       </td><td><b>other</b>          - Verbraucher ist keiner der vorgenannten Typen                                                                              </td></tr>
            <tr><td>                       </td><td><b>noSchedule</b>     - für den Verbraucher erfolgt keine Einplanung oder automatische Schaltung.                                                  </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                                                    Anzeigefunktionen oder manuelle Schaltungen sind verfügbar.                                                                                        </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>power</b>          </td><td>nominale Leistungsaufnahme des Verbrauchers (siehe Datenblatt) in W                                                                                </td></tr>
            <tr><td>                       </td><td>(kann auf "0" gesetzt werden)                                                                                                                      </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>switchdev</b>      </td><td>Das angegebene &lt;device&gt; wird als Schalter Device dem Verbraucher zugeordnet (optional). Schaltvorgänge werden mit diesem Gerät               </td></tr>
            <tr><td>                       </td><td>ausgeführt. Der Schlüssel ist für Verbraucher nützlich bei denen Energiemessung und Schaltung mit verschiedenen Geräten vorgenommen                </td></tr>
            <tr><td>                       </td><td>wird, z.B. Homematic oder readingsProxy. Ist switchdev angegeben, beziehen sich die Schlüssel on, off, swstate, auto, asynchron auf dieses Gerät.  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>mode</b>           </td><td>Planungsmodus des Verbrauchers (optional). Erlaubt sind:                                                                                           </td></tr>
            <tr><td>                       </td><td><b>can</b>  - Die Einplanung erfolgt zum Zeitpunkt mit wahrscheinlich genügend verfügbaren PV Überschuß (default)                                  </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Der Start des Verbrauchers zum Planungszeitpunkt unterbleibt bei ungenügendem PV-Überschuß.       </td></tr>
            <tr><td>                       </td><td><b>must</b> - der Verbraucher wird optimiert eingeplant auch wenn wahrscheinlich nicht genügend PV Überschuß vorhanden sein wird                   </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Der Start des Verbrauchers erfolgt auch bei ungenügendem PV-Überschuß sofern eine
                                                    gesetzte "swoncond" Bedingung erfüllt und "swoffcond" nicht erfüllt ist.                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>icon</b>           </td><td>Icon zur Darstellung des Verbrauchers in der Übersichtsgrafik (optional)                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>mintime</b>        </td><td>Einplanungsdauer (Minuten oder "SunPath") des Verbrauchers. (optional)                                                                             </td></tr>
            <tr><td>                       </td><td>Mit der Angabe von <b>SunPath</b> erfolgt die Planung entsprechend des Sonnenauf- und untergangs.                                                  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td>                       </td><td><b>SunPath</b>[:&lt;Offset_Sunrise&gt;:&lt;Offset_Sunset&gt;] - die Einplanung erfolgt von Sonnenaufgang bis Sonnenuntergang.                      </td></tr>
            <tr><td>                       </td><td> Optional kann eine positive / negative Verschiebung (Minuten) der Planungszeit bzgl. Sonnenaufgang bzw. Sonnenuntergang angegeben werden.         </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td>                       </td><td>Ist mintime nicht angegeben, wird eine Standard Einplanungsdauer gemäß nachfolgender Tabelle verwendet.                                            </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td>                       </td><td><b>Default mintime nach Verbrauchertyp:</b>                                                                                                        </td></tr>
            <tr><td>                       </td><td>- dishwasher: 180 Minuten                                                                                                                          </td></tr>
            <tr><td>                       </td><td>- dryer: 90 Minuten                                                                                                                                </td></tr>
            <tr><td>                       </td><td>- washingmachine: 120 Minuten                                                                                                                      </td></tr>
            <tr><td>                       </td><td>- heater: 240 Minuten                                                                                                                              </td></tr>
            <tr><td>                       </td><td>- charger: 120 Minuten                                                                                                                             </td></tr>
            <tr><td>                       </td><td>- other: 60 Minuten                                                                                                                                </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>on</b>             </td><td>Set-Kommando zum Einschalten des Verbrauchers (optional)                                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>off</b>            </td><td>Set-Kommando zum Ausschalten des Verbrauchers (optional)                                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>swstate</b>        </td><td>Reading welches den Schaltzustand des Verbrauchers anzeigt (default: 'state').                                                                     </td></tr>
            <tr><td>                       </td><td><b>on-Regex</b> - regulärer Ausdruck für den Zustand 'ein' (default: 'on')                                                                         </td></tr>
            <tr><td>                       </td><td><b>off-Regex</b> - regulärer Ausdruck für den Zustand 'aus' (default: 'off')                                                                       </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>asynchron</b>      </td><td>die Art der Schaltstatus Ermittlung im Verbraucher Device. Die Statusermittlung des Verbrauchers nach einem Schaltbefehl erfolgt nur               </td></tr>
            <tr><td>                       </td><td>durch Abfrage innerhalb eines Datensammelintervals (synchron) oder zusätzlich durch Eventverarbeitung (asynchron).                                 </td></tr>
            <tr><td>                       </td><td><b>0</b> - ausschließlich synchrone Verarbeitung von Schaltzuständen  (default)                                                                    </td></tr>
            <tr><td>                       </td><td><b>1</b> - zusätzlich asynchrone Verarbeitung von Schaltzuständen durch Eventverarbeitung                                                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>notbefore</b>      </td><td>Startzeitpunkt Verbraucher nicht vor angegebener Zeit 'Stunde[:Minute]' einplanen (optional)                                                       </td></tr>
            <tr><td>                       </td><td>Der &lt;Ausdruck&gt; hat das Format hh[:mm] oder ist in {...} eingeschlossener Perl-Code der hh[:mm] zurückgibt.                                   </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>notafter</b>       </td><td>Startzeitpunkt Verbraucher nicht nach angegebener Zeit 'Stunde[:Minute]' einplanen (optional)                                                      </td></tr>
            <tr><td>                       </td><td>Der &lt;Ausdruck&gt; hat das Format hh[:mm] oder ist in {...} eingeschlossener Perl-Code der hh[:mm] zurückgibt.                                   </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>auto</b>           </td><td>Reading im Verbraucherdevice welches das Schalten des Verbrauchers freigibt bzw. blockiert (optional)                                              </td></tr>
            <tr><td>                       </td><td>Ist der Schlüssel switchdev angegeben, wird das Reading in diesem Device gesetzt und ausgewertet.                                                  </td></tr>
            <tr><td>                       </td><td>Readingwert = 1 - Schalten freigegeben (default),  0: Schalten blockiert                                                                           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>pcurr</b>          </td><td>Reading:Einheit (W/kW) welches den aktuellen Energieverbrauch liefert (optional)                                                                   </td></tr>
            <tr><td>                       </td><td>:&lt;Schwellenwert&gt; (W) - Ab diesem Leistungsbezug wird der Verbraucher als aktiv gewertet. Die Angabe ist optional (default: 0)                </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>etotal</b>         </td><td>Reading:Einheit (Wh/kWh) des Consumer Device, welches die Summe der verbrauchten Energie liefert (optional)                                        </td></tr>
            <tr><td>                       </td><td>:&lt;Schwellenwert&gt (Wh) - Ab diesem Energieverbrauch pro Stunde wird der Verbrauch als gültig gewertet. Optionale Angabe (default: 0)           </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>swoncond</b>       </td><td>Bedingung die zusätzlich erfüllt sein muß um den Verbraucher einzuschalten (optional). Der geplante Zyklus wird gestartet.                         </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der zusätzlichen Einschaltbedingung                                                                           </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading zur Lieferung der zusätzlichen Einschaltbedingung                                                                         </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für eine 'wahre' Bedingung erfüllt sein muß                                                                  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>swoffcond</b>      </td><td>vorrangige Bedingung um den Verbraucher auszuschalten (optional). Der geplante Zyklus wird gestoppt.                                               </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der vorrangigen Ausschaltbedingung                                                                            </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading zur Lieferung der vorrangigen Ausschaltbedingung                                                                          </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für eine 'wahre' Bedingung erfüllt sein muß                                                                  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>spignorecond</b>   </td><td>Bedingung um einen fehlenden PV Überschuß zu ignorieren (optional). Bei erfüllter Bedingung wird der Verbraucher entsprechend                      </td></tr>
            <tr><td>                       </td><td>der Planung eingeschaltet auch wenn zu dem Zeitpunkt kein PV Überschuß vorliegt.                                                                   </td></tr>
            <tr><td>                       </td><td><b>ACHTUNG:</b> Die Verwendung beider Schlüssel <I>spignorecond</I> und <I>interruptable</I> kann zu einem unerwünschten Verhalten führen!         </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der Bedingung                                                                                                 </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading welches die Bedingung enthält                                                                                             </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für eine 'wahre' Bedingung erfüllt sein muß                                                                  </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>interruptable</b>  </td><td>definiert die möglichen Unterbrechungsoptionen für den Verbraucher nachdem er gestartet wurde (optional)                                           </td></tr>
            <tr><td>                       </td><td><b>0</b> - Verbraucher wird nicht temporär ausgeschaltet auch wenn der PV Überschuß die benötigte Energie unterschreitet (default)                 </td></tr>
            <tr><td>                       </td><td><b>1</b> - Verbraucher wird temporär ausgeschaltet falls der PV Überschuß die benötigte Energie unterschreitet                                     </td></tr>
            <tr><td>                       </td><td><b>Device:Reading:Regex[:Hysterese]</b> - Verbraucher wird temporär unterbrochen wenn der Wert des angegebenen                                     </td></tr>
            <tr><td>                       </td><td>Device:Readings auf den Regex matched oder unzureichender PV Überschuß (wenn power ungleich 0) vorliegt.                                           </td></tr>
            <tr><td>                       </td><td>Matched der Wert nicht mehr, wird der unterbrochene Verbraucher wieder eingeschaltet sofern ausreichender                                          </td></tr>
            <tr><td>                       </td><td>PV Überschuß (wenn power ungleich 0) vorliegt.                                                                                                     </td></tr>
            <tr><td>                       </td><td>Ist die optionale <b>Hysterese</b> angegeben, wird der Hysteresewert vom Readingswert subtrahiert und danach der Regex angewendet.                 </td></tr>
            <tr><td>                       </td><td>Matched dieser und der originale Readingswert, wird der Verbraucher temporär unterbrochen.                                                         </td></tr>
            <tr><td>                       </td><td>Der Verbraucher wird fortgesetzt, wenn sowohl der originale als auch der substrahierte Readingswert nicht (mehr) matchen.                          </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>locktime</b>       </td><td>Sperrzeiten in Sekunden für die Schaltung des Verbrauchers (optional).                                                                             </td></tr>
            <tr><td>                       </td><td><b>offlt</b> - Sperrzeit in Sekunden nachdem der Verbraucher ausgeschaltet oder unterbrochen wurde                                                 </td></tr>
            <tr><td>                       </td><td><b>onlt</b> - Sperrzeit in Sekunden nachdem der Verbraucher eingeschaltet oder fortgesetzt wurde                                                   </td></tr>
            <tr><td>                       </td><td>Der Verbraucher wird erst wieder geschaltet wenn die entsprechende Sperrzeit abgelaufen ist.                                                       </td></tr>
            <tr><td>                       </td><td><b>Hinweis:</b> Der Schalter 'locktime' ist nur im Automatik-Modus wirksam.                                                                        </td></tr>
            <tr><td>                       </td><td>                                                                                                                                                   </td></tr>
            <tr><td> <b>noshow</b>         </td><td>Verbraucher in Grafik ausblenden oder einblenden (optional).                                                                                       </td></tr>
            <tr><td>                       </td><td><b>0</b> - der Verbraucher wird eingeblendet (default)                                                                                             </td></tr>
            <tr><td>                       </td><td><b>1</b> - der Verbraucher wird ausgeblendet                                                                                                       </td></tr>
            <tr><td>                       </td><td><b>2</b> - der Verbraucher wird in der Verbraucherlegende ausgeblendet                                                                             </td></tr>
            <tr><td>                       </td><td><b>3</b> - der Verbraucher wird in der Flußgrafik ausgeblendet                                                                                     </td></tr>
            <tr><td>                       </td><td><b>[Device:]Reading</b> - Reading im Verbraucher oder optional einem alternativen Device.                                                          </td></tr>
            <tr><td>                       </td><td>Hat das Reading den Wert 0 oder ist nicht vorhanden, wird der Verbraucher eingeblendet.                                                            </td></tr>
            <tr><td>                       </td><td>Die Wirkung der möglichen Readingwerte 1, 2 und 3 ist wie beschrieben.                                                                             </td></tr>
         </table>
         </ul>
       <br>

       <ul>
         <b>Beispiele: </b> <br>
         <b>attr &lt;name&gt; consumer01</b> wallplug icon=scene_dishwasher@orange type=dishwasher mode=can power=2500 on=on off=off notafter=20 etotal=total:kWh:5 <br>
         <b>attr &lt;name&gt; consumer02</b> WPxw type=heater mode=can power=3000 mintime=180 on="on-for-timer 3600" notafter=12 auto=automatic                     <br>
         <b>attr &lt;name&gt; consumer03</b> Shelly.shellyplug2 type=other power=300 mode=must icon=it_ups_on_battery mintime=120 on=on off=off swstate=state:on:off auto=automatic pcurr=relay_0_power:W etotal:relay_0_energy_Wh:Wh swoncond=EcoFlow:data_data_socSum:-?([1-7][0-9]|[0-9]) swoffcond:EcoFlow:data_data_socSum:100 <br>
         <b>attr &lt;name&gt; consumer04</b> Shelly.shellyplug3 icon=scene_microwave_oven type=heater power=2000 mode=must notbefore=07 mintime=600 on=on off=off etotal=relay_0_energy_Wh:Wh pcurr=relay_0_power:W auto=automatic interruptable=eg.wz.wandthermostat:diff-temp:(22)(\.[2-9])|([2-9][3-9])(\.[0-9]):0.2             <br>
         <b>attr &lt;name&gt; consumer05</b> Shelly.shellyplug4 icon=sani_buffer_electric_heater_side type=heater mode=must power=1000 notbefore=7 notafter=20:10 auto=automatic pcurr=actpow:W on=on off=off mintime=SunPath interruptable=1                                                                                       <br>
         <b>attr &lt;name&gt; consumer06</b> Shelly.shellyplug5 icon=sani_buffer_electric_heater_side type=heater mode=must power=1000 notbefore=07:20 notafter={return'20:05'} auto=automatic pcurr=actpow:W on=on off=off mintime=SunPath:60:-120 interruptable=1                                                                              <br>
         <b>attr &lt;name&gt; consumer07</b> SolCastDummy icon=sani_buffer_electric_heater_side type=heater mode=can power=600 auto=automatic pcurr=actpow:W on=on off=off mintime=15 asynchron=1 locktime=300:1200 interruptable=1 noshow=noShow                                                                                   <br>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlAIdataStorageDuration"></a>
       <li><b>ctrlAIdataStorageDuration &lt;Tage&gt;</b> <br>
         Sind die entsprechenden Voraussetzungen gegeben, werden Trainingsdaten für die modulinterne KI gesammelt und
         gespeichert. Daten welche die angegebene Haltedauer (Tage) überschritten haben, werden gelöscht.  <br>
         (default: 1095)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlAutoRefresh"></a>
       <li><b>ctrlAutoRefresh</b> <br>
         Wenn gesetzt, werden aktive Browserseiten des FHEMWEB-Devices welches das SolarForecast-Device aufgerufen hat, nach der
         eingestellten Zeit (Sekunden) neu geladen. Sollen statt dessen Browserseiten eines bestimmten FHEMWEB-Devices neu
         geladen werden, kann dieses Device mit dem Attribut "ctrlAutoRefreshFW" festgelegt werden.
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlAutoRefreshFW"></a>
       <li><b>ctrlAutoRefreshFW</b><br>
         Ist "ctrlAutoRefresh" aktiviert, kann mit diesem Attribut das FHEMWEB-Device bestimmt werden dessen aktive Browserseiten
         regelmäßig neu geladen werden sollen.
       </li>
       <br>
       
       <a id="SolarForecast-attr-ctrlBackupFilesKeep"></a>
       <li><b>ctrlBackupFilesKeep &lt;Ganzzahl&gt;</b><br>
         Legt die Anzahl der Generationen von Sicherungsdateien 
         (siehe <a href="#SolarForecast-set-operatingMemory">set &lt;name&gt; operatingMemory backup</a>) fest. <br>
         (default: 3)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlBatSocManagement"></a>
       <li><b>ctrlBatSocManagement lowSoc=&lt;Wert&gt; upSoC=&lt;Wert&gt; [maxSoC=&lt;Wert&gt;] [careCycle=&lt;Wert&gt;] </b> <br><br>
         Sofern ein Batterie Device (currentBatteryDev) installiert ist, aktiviert dieses Attribut das Batterie
         SoC-Management. <br>
         Das Reading <b>Battery_OptimumTargetSoC</b> enthält den vom Modul berechneten optimalen Mindest-SoC. <br>
         Das Reading <b>Battery_ChargeRequest</b> wird auf '1' gesetzt, wenn der aktuelle SoC unter den Mindest-SoC gefallen
         ist. <br>
         In diesem Fall sollte die Batterie, unter Umständen mit Netzstrom, zwangsgeladen werden. <br>
         Die Readings können zur Steuerung des SoC (State of Charge) sowie zur Steuerung des verwendeten Ladestroms
         der Batterie verwendet werden. <br>
         Durch das Modul selbst findet keine Steuerung der Batterie statt. <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>lowSoc</b>    </td><td>unterer Mindest-SoC, die Batterie wird nicht tiefer als dieser Wert entladen (> 0)        </td></tr>
            <tr><td> <b>upSoC</b>     </td><td>oberer Mindest-SoC, der übliche Wert des optimalen SoC bewegt sich zwischen 'lowSoC'      </td></tr>
            <tr><td>                  </td><td>und diesem Wert.                                                                          </td></tr>
            <tr><td> <b>maxSoC</b>    </td><td>maximaler Mindest-SoC, SoC Wert der mindestens im Abstand von 'careCycle' Tagen erreicht  </td></tr>
            <tr><td>                  </td><td>werden muß um den Ladungsausgleich im Speicherverbund auszuführen.                        </td></tr>
            <tr><td>                  </td><td>Die Angabe ist optional (&lt;= 100, default: 95)                                      </td></tr>
            <tr><td> <b>careCycle</b> </td><td>maximaler Abstand in Tagen, der zwischen zwei Ladungszuständen von mindestens 'maxSoC'    </td></tr>
            <tr><td>                  </td><td>auftreten darf. Die Angabe ist optional (default: 20)                                     </td></tr>
         </table>
         </ul>
         <br>

         Alle Werte sind ganze Zahlen in %. Dabei gilt: 'lowSoc' &lt; 'upSoC' &lt; 'maxSoC'. <br>
         Die Ermittlung des optimalen SoC erfolgt nach folgendem Schema: <br><br>

         <table>
         <colgroup> <col width="2%"> <col width="98%"> </colgroup>
            <tr><td> 1. </td><td>Ausgehend von 'lowSoc' wird der Mindest-SoC am folgenden Tag um 5%, aber nicht höher als                               </td></tr>
            <tr><td>    </td><td>'upSoC' inkrementiert, sofern am laufenden Tag 'maxSoC' nicht erreicht wurde.                                          </td></tr>
            <tr><td> 2. </td><td>Wird am laufenden Tag 'maxSoC' (wieder) erreicht, wird Mindest-SoC um 5%, aber nicht tiefer als 'lowSoc', verringert.  </td></tr>
            <tr><td> 3. </td><td>Mindest-SoC wird soweit verringert, dass die prognostizierte PV Energie des aktuellen bzw. des folgenden Tages         </td></tr>
            <tr><td>    </td><td>von der Batterie aufgenommen werden kann. Mindest-SoC wird nicht tiefer als 'lowSoc' verringert.                       </td></tr>
            <tr><td> 4. </td><td>Das Modul erfasst den letzten Zeitpunkt am 'maxSoC'-Level, um eine Ladung auf 'maxSoC' mindestens alle 'careCycle'     </td></tr>
            <tr><td>    </td><td>Tage zu realisieren. Zu diesem Zweck wird der optimierte SoC in Abhängigkeit der Resttage bis zum nächsten             </td></tr>
            <tr><td>    </td><td>'careCycle' Zeitpunkt derart verändert, dass durch eine tägliche 5% SoC-Steigerung 'maxSoC' am 'careCycle' Zeitpunkt   </td></tr>
            <tr><td>    </td><td>rechnerisch erreicht wird. Wird zwischenzeitlich 'maxSoC' erreicht, beginnt der 'careCycle' Zeitraum erneut.           </td></tr>
         </table>
         <br>

       <ul>
         <b>Beispiel: </b> <br>
         attr &lt;name&gt; ctrlBatSocManagement lowSoc=10 upSoC=50 maxSoC=99 careCycle=25 <br>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlConsRecommendReadings"></a>
       <li><b>ctrlConsRecommendReadings </b><br>
         Für die ausgewählten Consumer (Nummer) werden Readings der Form <b>consumerXX_ConsumptionRecommended</b> erstellt. <br>
         Diese Readings signalisieren ob das Einschalten dieses Consumers abhängig von seinen Verbrauchsdaten und der aktuellen
         PV-Erzeugung bzw. des aktuellen Energieüberschusses empfohlen ist. Der Wert des erstellten Readings korreliert
         mit den berechneten Planungsdaten das Consumers, kann aber von dem Planungszeitraum abweichen. <br>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlDebug"></a>
       <li><b>ctrlDebug</b><br>
         Aktiviert/deaktiviert verschiedene Debug Module. Ist ausschließlich "none" selektiert erfolgt keine DEBUG-Ausgabe.
         Zur Ausgabe von Debug Meldungen muß der verbose Level des Device mindestens "1" sein. <br>
         Die Debug Ebenen können miteinander kombiniert werden: <br><br>

         <ul>
         <table>
         <colgroup> <col width="23%"> <col width="77%"> </colgroup>
            <tr><td> <b>aiProcess</b>            </td><td>Prozessablauf der KI Unterstützung                                               </td></tr>
            <tr><td> <b>aiData</b>               </td><td>KI Daten                                                                         </td></tr>
            <tr><td> <b>apiCall</b>              </td><td>Abruf API Schnittstelle ohne Datenausgabe                                        </td></tr>
            <tr><td> <b>apiProcess</b>           </td><td>Abruf und Verarbeitung von API Daten                                             </td></tr>
            <tr><td> <b>batteryManagement</b>    </td><td>Steuerungswerte des Batterie Managements (SoC)                                   </td></tr>
            <tr><td> <b>collectData</b>          </td><td>detailliierte Datensammlung                                                      </td></tr>
            <tr><td> <b>consumerPlanning</b>     </td><td>Consumer Einplanungsprozesse                                                     </td></tr>
            <tr><td> <b>consumerSwitching</b>    </td><td>Operationen des internen Consumer Schaltmodul                                    </td></tr>
            <tr><td> <b>consumption</b>          </td><td>Verbrauchskalkulation und -nutzung                                               </td></tr>
            <tr><td> <b>epiecesCalc</b>          </td><td>Berechnung des spezifischen Energieverbrauchs je Betriebsstunde und Verbraucher  </td></tr>
            <tr><td> <b>graphic</b>              </td><td>Informationen der Modulgrafik                                                    </td></tr>
            <tr><td> <b>notifyHandling</b>       </td><td>Ablauf der Eventverarbeitung im Modul                                            </td></tr>
            <tr><td> <b>pvCorrection</b>         </td><td>Berechnung und Anwendung PV Korrekturfaktoren                                    </td></tr>
            <tr><td> <b>radiationProcess</b>     </td><td>Sammlung und Verarbeitung der Solarstrahlungsdaten                               </td></tr>
            <tr><td> <b>saveData2Cache</b>       </td><td>Datenspeicherung in internen Speicherstrukturen                                  </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlGenPVdeviation"></a>
       <li><b>ctrlGenPVdeviation </b><br>
         Legt die Methode zur Berechnung der Abweichung von prognostizierter und realer PV Erzeugung fest.
         Das Reading <b>Today_PVdeviation</b> wird in Abhängigkeit dieser Einstellung erstellt. <br><br>

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>daily</b>         </td><td>Berechnung und Erstellung von Today_PVdeviation erfolgt nach Sonnenuntergang (default) </td></tr>
            <tr><td> <b>continuously</b>  </td><td>Berechnung und Erstellung von Today_PVdeviation erfolgt fortlaufend                    </td></tr>
         </table>
         </ul>
       </li><br>

       <a id="SolarForecast-attr-ctrlInterval"></a>
       <li><b>ctrlInterval &lt;Sekunden&gt; </b><br>
         Wiederholungsintervall der Datensammlung. <br>
         Unabhängig vom eingestellten Intervall erfolgt einige Sekunden vor dem Ende sowie nach dem Beginn einer
         vollen Stunde eine automatische Datensammlung. <br>
         Ist ctrlInterval explizit auf "0" gesetzt, erfolgt keinerlei automatische Datensammlung und muss mit
         "get &lt;name&gt; data" extern erfolgen. <br>
         (default: 70)
       </li><br>

       <a id="SolarForecast-attr-ctrlLanguage"></a>
       <li><b>ctrlLanguage &lt;DE | EN&gt; </b><br>
         Legt die benutzte Sprache des Devices fest. Die Sprachendefinition hat Auswirkungen auf die Modulgrafik und
         verschiedene Readinginhalte. <br>
         Ist das Attribut nicht gesetzt, definiert sich die Sprache durch die Einstellung des globalen Attributs "language". <br>
         (default: EN)
       </li><br>

       <a id="SolarForecast-attr-ctrlNextDayForecastReadings"></a>
       <li><b>ctrlNextDayForecastReadings &lt;01,02,..,24&gt; </b><br>
         Wenn gesetzt, werden Readings der Form <b>Tomorrow_Hour&lt;hour&gt;_PVforecast</b> erstellt. <br>
         Diese Readings enthalten die voraussichtliche PV Erzeugung des kommenden Tages. Dabei ist &lt;hour&gt; die
         Stunde des Tages. <br>
       <br>

       <ul>
         <b>Beispiel: </b> <br>
         attr &lt;name&gt; ctrlNextDayForecastReadings 09,11 <br>
         # erstellt Readings für die Stunde 09 (08:00-09:00) und 11 (10:00-11:00) des kommenden Tages
       </ul>

       </li>
       <br>

       <a id="SolarForecast-attr-ctrlShowLink"></a>
       <li><b>ctrlShowLink </b><br>
         Anzeige des Links zur Detailansicht des Device über dem Grafikbereich <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlSolCastAPImaxReq"></a>
       <li><b>ctrlSolCastAPImaxReq </b><br>
         (nur bei Verwendung Model SolCastAPI) <br><br>

         Die Einstellung der maximal möglichen täglichen Requests an die SolCast API. <br>
         Dieser Wert wird von SolCast vorgegeben und kann sich entsprechend des SolCast
         Lizenzmodells ändern. <br>
         (default: 50)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlSolCastAPIoptimizeReq"></a>
       <li><b>ctrlSolCastAPIoptimizeReq </b><br>
         (nur bei Verwendung Model SolCastAPI) <br><br>

         Das default Abrufintervall der SolCast API beträgt 1 Stunde. Ist dieses Attribut gesetzt erfolgt ein dynamische
         Anpassung des Intervalls mit dem Ziel die maximal möglichen Abrufe innerhalb von Sonnenauf- und untergang
         auszunutzen. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlStatisticReadings"></a>
       <li><b>ctrlStatisticReadings </b><br>
         Für die ausgewählten Kennzahlen und Indikatoren werden Readings mit dem
         Namensschema 'statistic_&lt;Indikator&gt;' erstellt. Auswählbare Kennzahlen / Indikatoren sind: <br><br>

         <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>allStringsFullfilled</b>       </td><td>Erfüllungsstatus der fehlerfreien Generierung aller Strings                                                     </td></tr>
            <tr><td> <b>conForecastTillNextSunrise</b> </td><td>Verbrauchsprognose von aktueller Stunde bis zum kommenden Sonnenaufgang                                         </td></tr>
            <tr><td> <b>currentAPIinterval</b>         </td><td>das aktuelle Abrufintervall der SolCast API (nur Model SolCastAPI) in Sekunden                                  </td></tr>
            <tr><td> <b>currentRunMtsConsumer_XX</b>   </td><td>die Laufzeit (Minuten) des Verbrauchers "XX" seit dem letzten Einschalten. (0 - Verbraucher ist aus)            </td></tr>
            <tr><td> <b>dayAfterTomorrowPVforecast</b> </td><td>liefert die Vorhersage der PV Erzeugung für Übermorgen (sofern verfügbar) ohne Autokorrektur (Rohdaten).        </td></tr>
            <tr><td> <b>daysUntilBatteryCare</b>       </td><td>Tage bis zur nächsten Batteriepflege (Erreichen der Ladung 'maxSoC' aus Attribut ctrlBatSocManagement)          </td></tr>
            <tr><td> <b>lastretrieval_time</b>         </td><td>der letzte Abrufzeitpunkt der API (nur Model SolCastAPI, ForecastSolarAPI)                                      </td></tr>
            <tr><td> <b>lastretrieval_timestamp</b>    </td><td>der Timestamp der letzen Abrufzeitpunkt der API (nur Model SolCastAPI, ForecastSolarAPI)                        </td></tr>
            <tr><td> <b>response_message</b>           </td><td>die letzte Statusmeldung der API (nur Model SolCastAPI, ForecastSolarAPI)                                       </td></tr>
            <tr><td> <b>runTimeCentralTask</b>         </td><td>die Laufzeit des letzten SolarForecast Intervalls (Gesamtprozess) in Sekunden                                   </td></tr>
            <tr><td> <b>runTimeTrainAI</b>             </td><td>die Laufzeit des letzten KI Trainingszyklus in Sekunden                                                         </td></tr>
            <tr><td> <b>runTimeLastAPIAnswer</b>       </td><td>die letzte Antwortzeit des API Abrufs auf einen Request in Sekunden (nur Model SolCastAPI, ForecastSolarAPI)    </td></tr>
            <tr><td> <b>runTimeLastAPIProc</b>         </td><td>die letzte Prozesszeit zur Verarbeitung der empfangenen API Daten (nur Model SolCastAPI, ForecastSolarAPI)      </td></tr>
            <tr><td> <b>SunMinutes_Remain</b>          </td><td>die verbleibenden Minuten bis Sonnenuntergang des aktuellen Tages                                               </td></tr>
            <tr><td> <b>SunHours_Remain</b>            </td><td>die verbleibenden Stunden bis Sonnenuntergang des aktuellen Tages                                               </td></tr>
            <tr><td> <b>todayConsumptionForecast</b>   </td><td>Verbrauchsprognose pro Stunde des aktuellen Tages (01-24)                                                       </td></tr>
            <tr><td> <b>todayConForecastTillSunset</b> </td><td>Verbrauchsprognose von aktueller Stunde bis Stunde vor Sonnenuntergang                                          </td></tr>
            <tr><td> <b>todayDoneAPIcalls</b>          </td><td>die Anzahl der am aktuellen Tag ausgeführten API Calls (nur Model SolCastAPI, ForecastSolarAPI)                 </td></tr>
            <tr><td> <b>todayDoneAPIrequests</b>       </td><td>die Anzahl der am aktuellen Tag ausgeführten API Requests (nur Model SolCastAPI, ForecastSolarAPI)              </td></tr>
            <tr><td> <b>todayGridConsumption</b>       </td><td>die aus dem öffentlichen Netz bezogene Energie am aktuellen Tag                                                 </td></tr>
            <tr><td> <b>todayGridFeedIn</b>            </td><td>die in das öffentliche Netz eingespeiste PV Energie am aktuellen Tag                                            </td></tr>
            <tr><td> <b>todayMaxAPIcalls</b>           </td><td>die maximal mögliche Anzahl SolCast API Calls (nur Model SolCastAPI).                                           </td></tr>
            <tr><td>                                   </td><td>Ein Call kann mehrere API Requests enthalten.                                                                   </td></tr>
            <tr><td> <b>todayRemainingAPIcalls</b>     </td><td>die Anzahl der am aktuellen Tag noch möglichen SolCast API Calls (nur Model SolCastAPI)                         </td></tr>
            <tr><td> <b>todayRemainingAPIrequests</b>  </td><td>die Anzahl der am aktuellen Tag noch möglichen SolCast API Requests (nur Model SolCastAPI)                      </td></tr>
            <tr><td> <b>todayBatIn</b>                 </td><td>die am aktuellen Tag in die Batterie geladene Energie                                                           </td></tr>
            <tr><td> <b>todayBatOut</b>                </td><td>die am aktuellen Tag aus der Batterie entnommene Energie                                                        </td></tr>
         </table>
         </ul>
       <br>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlUserExitFn"></a>
       <li><b>ctrlUserExitFn {&lt;Code&gt;} </b><br>
         Nach jedem Zyklus (siehe Attribut <a href="#SolarForecast-attr-ctrlInterval ">ctrlInterval </a>) wird der in diesem
         Attribut abgegebene Code ausgeführt. Der Code ist in geschweifte Klammern {...} einzuschließen. <br>
         Dem Code werden die Variablen <b>$name</b> und <b>$hash</b> übergeben, die den Namen des SolarForecast Device und
         dessen Hash enthalten. <br>
         Im SolarForecast Device können Readings über die Funktion <b>storeReading</b> erzeugt und geändert werden.
         <br>
         <br>

         <ul>
         <b>Beispiel: </b> <br>
            {                                                                                           <br>
              my $batdev = (split " ", ReadingsVal ($name, 'currentBatteryDev', ''))[0];                <br>
              my $pvfc   = ReadingsNum ($name, 'RestOfDayPVforecast',          0);                      <br>
              my $cofc   = ReadingsNum ($name, 'RestOfDayConsumptionForecast', 0);                      <br>
              my $diff   = $pvfc - $cofc;                                                               <br>
                                                                                                        <br>
              storeReading ('userFn_Battery_device',  $batdev);                                         <br>
              storeReading ('userFn_estimated_surplus', $diff);                                         <br>
            }
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicCss"></a>
       <li><b>flowGraphicCss </b><br>
         Definiert den Style für die Energieflußgrafik. Das Attribut wird automatisch vorbelegt.
         Zum Ändern des flowGraphicCss-Attributes bitte den Default übernehmen und anpassen: <br><br>

         <ul>
           .flowg.text           { stroke: none; fill: gray; font-size: 60px; } <br>
           .flowg.sun_active     { stroke: orange; fill: orange; }              <br>
           .flowg.sun_inactive   { stroke: gray; fill: gray; }                  <br>
           .flowg.bat25          { stroke: red; fill: red; }                    <br>
           .flowg.bat50          { stroke: darkorange; fill: darkorange; }      <br>
           .flowg.bat75          { stroke: green; fill: green; }                <br>
           .flowg.grid_color1    { fill: green; }                               <br>
           .flowg.grid_color2    { fill: red; }                                 <br>
           .flowg.grid_color3    { fill: gray; }                                <br>
           .flowg.inactive_in    { stroke: gray;       stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }                                                                     <br>
           .flowg.inactive_out   { stroke: gray;       stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }                                                                     <br>
           .flowg.active_in      { stroke: red;        stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_out     { stroke: darkorange; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_bat_in  { stroke: darkorange; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_bat_out { stroke: green;      stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
         </ul>

       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicAnimate"></a>
       <li><b>flowGraphicAnimate </b><br>
         Animiert die Energieflußgrafik sofern angezeigt.
         Siehe auch Attribut <a href="#SolarForecast-attr-graphicSelect">graphicSelect</a>. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicConsumerDistance"></a>
       <li><b>flowGraphicConsumerDistance </b><br>
         Steuert den Abstand zwischen den Consumer-Icons in der Energieflußgrafik sofern angezeigt.
         Siehe auch Attribut <a href="#SolarForecast-attr-flowGraphicShowConsumer">flowGraphicShowConsumer</a>. <br>
         (default: 130)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumer"></a>
       <li><b>flowGraphicShowConsumer </b><br>
         Unterdrückt die Anzeige der Verbraucher in der Energieflußgrafik wenn auf "0" gesetzt. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumerDummy"></a>
       <li><b>flowGraphicShowConsumerDummy </b><br>
         Zeigt bzw. unterdrückt den Dummy-Verbraucher in der Energieflußgrafik. <br>
         Dem Dummy-Verbraucher wird der Energieverbrauch zugewiesen der anderen Verbrauchern nicht zugeordnet werden konnte. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumerPower"></a>
       <li><b>flowGraphicShowConsumerPower </b><br>
         Zeigt bzw. unterdrückt den Energieverbrauch der Verbraucher in der Energieflußgrafik. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicShowConsumerRemainTime"></a>
       <li><b>flowGraphicShowConsumerRemainTime </b><br>
         Zeigt bzw. unterdrückt die Restlaufzeit (in Minuten) der Verbraucher in der Energieflußgrafik. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-flowGraphicSize"></a>
       <li><b>flowGraphicSize &lt;Pixel&gt; </b><br>
         Größe der Energieflußgrafik sofern angezeigt.
         Siehe auch Attribut <a href="#SolarForecast-attr-graphicSelect">graphicSelect</a>. <br>
         (default: 400)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1Color"></a>
       <li><b>graphicBeam1Color </b><br>
         Farbauswahl der primären Balken.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1FontColor"></a>
       <li><b>graphicBeam1FontColor </b><br>
         Auswahl der Schriftfarbe des primären Balken. <br>
         (default: 0D0D0D)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1Content"></a>
       <li><b>graphicBeam1Content </b><br>
         Legt den darzustellenden Inhalt der primären Balken fest.

         <ul>
         <table>
         <colgroup> <col width="45%"> <col width="55%"> </colgroup>
            <tr><td> <b>pvReal</b>              </td><td>reale PV-Erzeugung (default)           </td></tr>
            <tr><td> <b>pvForecast</b>          </td><td>prognostizierte PV-Erzeugung           </td></tr>
            <tr><td> <b>gridconsumption</b>     </td><td>Energie Bezug aus dem Netz             </td></tr>
            <tr><td> <b>consumptionForecast</b> </td><td>prognostizierter Energieverbrauch      </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam1MaxVal"></a>
       <li><b>graphicBeam1MaxVal &lt;0...val&gt; </b><br>
         Festlegung des maximalen Betrags des primären Balkens (Stundenwert) zur Berechnung der maximalen Balkenhöhe.
         Dadurch erfolgt eine Anpassung der zulässigen Gesamthöhe der Grafik. <br>
         Mit dem Wert "0" erfolgt eine dynamische Anpassung. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam2Color"></a>
       <li><b>graphicBeam2Color </b><br>
         Farbauswahl der sekundären Balken. Die zweite Farbe ist nur sinnvoll für den Anzeigedevice-Typ "pvco" und "diff".
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam2FontColor"></a>
       <li><b>graphicBeam2FontColor </b><br>
         Auswahl der Schriftfarbe des sekundären Balken. <br>
         (default: 000000)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeam2Content"></a>
       <li><b>graphicBeam2Content </b><br>
         Legt den darzustellenden Inhalt der sekundären Balken fest.

         <ul>
         <table>
         <colgroup> <col width="43%"> <col width="57%"> </colgroup>
            <tr><td> <b>pvForecast</b>          </td><td>prognostizierte PV-Erzeugung (default) </td></tr>
            <tr><td> <b>pvReal</b>              </td><td>reale PV-Erzeugung                     </td></tr>
            <tr><td> <b>gridconsumption</b>     </td><td>Energie Bezug aus dem Netz             </td></tr>
            <tr><td> <b>consumptionForecast</b> </td><td>prognostizierter Energieverbrauch      </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeamHeight"></a>
       <li><b>graphicBeamHeight &lt;value&gt; </b><br>
         Höhe der Balken in px und damit Bestimmung der gesammten Höhe.
         In Verbindung mit "graphicHourCount" lassen sich damit auch recht kleine Grafikausgaben erzeugen. <br>
         (default: 200)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicBeamWidth"></a>
       <li><b>graphicBeamWidth &lt;value&gt; </b><br>
         Breite der Balken der Balkengrafik in px. Ohne gesetzen Attribut wird die Balkenbreite durch das Modul
         automatisch bestimmt. <br>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicEnergyUnit"></a>
       <li><b>graphicEnergyUnit &lt;Wh | kWh&gt; </b><br>
         Definiert die Einheit zur Anzeige der elektrischen Leistung in der Grafik. Die Kilowattstunde wird auf eine
         Nachkommastelle gerundet. <br>
         (default: Wh)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderDetail"></a>
       <li><b>graphicHeaderDetail </b><br>
         Auswahl der anzuzeigenden Zonen des Grafik Kopfbereiches. <br>
         (default: all)

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>all</b>        </td><td>alle Zonen des Kopfbereiches (default)        </td></tr>
            <tr><td> <b>co</b>         </td><td>Verbrauchsbereich anzeigen                    </td></tr>
            <tr><td> <b>pv</b>         </td><td>Erzeugungsbereich anzeigen                    </td></tr>
            <tr><td> <b>own</b>        </td><td>Nutzerzone (siehe <a href="#SolarForecast-attr-graphicHeaderOwnspec">graphicHeaderOwnspec</a>)   </td></tr>
            <tr><td> <b>status</b>     </td><td>Bereich der Statusinformationen               </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderOwnspec"></a>
       <li><b>graphicHeaderOwnspec &lt;Label&gt;:&lt;Reading&gt;[@Device] &lt;Label&gt;:&lt;Set&gt;[@Device] &lt;Label&gt;:&lt;Attr&gt;[@Device] ... </b><br>
         Anzeige beliebiger Readings, Set-Kommandos und Attribute des SolarForecast Devices im Grafikkopf. <br>
         Durch Angabe des optionalen [@Device] können Readings, Set-Kommandos und Attribute anderer Devices angezeigt werden. <br>
         Die anzuzeigenden Werte werden durch Leerzeichen getrennt.
         Es werden vier Werte (Felder) pro Zeile dargestellt. <br>
         Die Eingabe kann mehrzeilig erfolgen. Werte mit den Einheiten "Wh" bzw. "kWh" werden entsprechend der Einstellung
         des Attributs <a href="#SolarForecast-attr-graphicEnergyUnit">graphicEnergyUnit</a> umgerechnet.
         <br><br>

         Jeder Wert ist jeweils durch ein Label und das dazugehörige Reading verbunden durch ":" zu definieren. <br>
         Leerzeichen im Label sind durch "&amp;nbsp;" einzufügen, ein Zeilenumbruch durch "&lt;br&gt;". <br>
         Ein leeres Feld in einer Zeile wird durch ":" erzeugt. <br>
         Ein Zeilentitel kann durch Angabe von "#:&lt;Text&gt;" eingefügt werden, ein leerer Titel durch die Eingabe von "#".
         <br><br>

       <ul>
         <b>Beispiel: </b> <br>
         <table>
         <colgroup> <col width="35%"> <col width="65%"> </colgroup>
            <tr><td> attr &lt;name&gt; graphicHeaderOwnspec  </td><td>#                                                                             </td></tr>
            <tr><td>                                         </td><td>AutarkyRate:Current_AutarkyRate                                               </td></tr>
            <tr><td>                                         </td><td>Überschuß:Current_Surplus                                                     </td></tr>
            <tr><td>                                         </td><td>aktueller&amp;nbsp;Netzbezug:Current_GridConsumption                          </td></tr>
            <tr><td>                                         </td><td>:                                                                             </td></tr>
            <tr><td>                                         </td><td>#                                                                             </td></tr>
            <tr><td>                                         </td><td>CO&amp;nbsp;bis&amp;nbsp;Sonnenuntergang:statistic_todayConForecastTillSunset </td></tr>
            <tr><td>                                         </td><td>PV&amp;nbsp;Übermorgen:statistic_dayAfterTomorrowPVforecast                   </td></tr>
            <tr><td>                                         </td><td>InverterRelay:gridrelay_status@MySTP_5000                                     </td></tr>
            <tr><td>                                         </td><td>:                                                                             </td></tr>
            <tr><td>                                         </td><td>#Batterie                                                                     </td></tr>
            <tr><td>                                         </td><td>in&amp;nbsp;heute:statistic_todayBatIn                                        </td></tr>
            <tr><td>                                         </td><td>out&amp;nbsp;heute:statistic_todayBatOut                                      </td></tr>
            <tr><td>                                         </td><td>:                                                                             </td></tr>
            <tr><td>                                         </td><td>:                                                                             </td></tr>
            <tr><td>                                         </td><td>#Settings                                                                     </td></tr>
            <tr><td>                                         </td><td>Autokorrektur:pvCorrectionFactor_Auto : : :                                   </td></tr>
            <tr><td>                                         </td><td>Consumer&lt;br&gt;Neuplanung:consumerNewPlanning : : :                        </td></tr>
            <tr><td>                                         </td><td>Consumer&lt;br&gt;Sofortstart:consumerImmediatePlanning : : :                 </td></tr>
            <tr><td>                                         </td><td>Wetter:graphicShowWeather : : :                                               </td></tr>
            <tr><td>                                         </td><td>History:graphicHistoryHour : : :                                              </td></tr>
            <tr><td>                                         </td><td>GraphicSize:flowGraphicSize : : :                                             </td></tr>
            <tr><td>                                         </td><td>ShowNight:graphicShowNight : : :                                              </td></tr>
            <tr><td>                                         </td><td>Debug:ctrlDebug : : :                                                         </td></tr>
         </table>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderOwnspecValForm"></a>
       <li><b>graphicHeaderOwnspecValForm </b><br>
         Die mit dem Attribut <a href="#SolarForecast-attr-graphicHeaderOwnspec">graphicHeaderOwnspec</a> anzuzeigenden
         Readings können mit sprintf und anderen Perl Operationen manipuliert werden. <br>
         Es stehen zwei grundsätzliche, miteinander nicht kombinierbare Möglichkeiten der Notation zur Verfügung. <br>
         Die Angabe der Notationen erfolgt grundsätzlich innerhalb von zwei geschweiften Klammern {...}.
         <br><br>

         <b>Notation 1: </b> <br>
         Eine einfache Formatierung von Readings des eigenen Devices mit sprintf erfolgt wie in Zeile
         'Current_AutarkyRate' bzw. 'Current_GridConsumption' angegeben. <br>
         Andere Perl Operationen sind mit () zu klammern. Die jeweiligen Readingswerte und Einheiten stehen über
         die Variablen $VALUE und $UNIT zur Verfügung. <br>
         Readings anderer Devices werden durch die Angabe '&lt;Device&gt;.&lt;Reading&gt;' spezifiziert.
         <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td>{                                        </td><td>                                               </td></tr>
            <tr><td> 'Current_AutarkyRate'                   </td><td> => "%.1f %%",                                 </td></tr>
            <tr><td> 'Current_GridConsumption'               </td><td> => "%.2f $UNIT",                              </td></tr>
            <tr><td> 'SMA_Energymeter.Cover_RealPower'       </td><td> => q/($VALUE)." W"/,                          </td></tr>
            <tr><td> 'SMA_Energymeter.L2_Cover_RealPower'    </td><td> => "($VALUE).' W'",                           </td></tr>
            <tr><td> 'SMA_Energymeter.L1_Cover_RealPower'    </td><td> => '(sprintf "%.2f", ($VALUE / 1000))." kW"', </td></tr>
            <tr><td>}                                        </td><td>                                               </td></tr>
         </table>
         </ul>
         <br>

         <b>Notation 2: </b> <br>
         Die Manipulation von Readingwerten und Einheiten erfolgt über Perl If ... else Strukturen. <br>
         Der Struktur stehen Device, Reading, Readingwert und Einheit mit den Variablen $DEVICE, $READING, $VALUE und
         $UNIT zur Verfügung. <br>
         Bei Änderung der Variablen werden die neuen Werte entsprechend in die Anzeige übernommen.
         <br><br>

         <ul>
         <table>
         <colgroup> <col width="5%"> <col width="95%"> </colgroup>
            <tr><td>{ </td><td>                                                   </td></tr>
            <tr><td>  </td><td> if ($READING eq 'Current_AutarkyRate') {          </td></tr>
            <tr><td>  </td><td> &nbsp;&nbsp; $VALUE = sprintf "%.1f", $VALUE;     </td></tr>
            <tr><td>  </td><td> &nbsp;&nbsp; $UNIT  = "%";                        </td></tr>
            <tr><td>  </td><td> }                                                 </td></tr>
            <tr><td>  </td><td> elsif ($READING eq 'Current_GridConsumption') {   </td></tr>
            <tr><td>  </td><td> &nbsp;&nbsp; ...                                  </td></tr>
            <tr><td>  </td><td> }                                                 </td></tr>
            <tr><td>} </td><td>                                                   </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderShow"></a>
       <li><b>graphicHeaderShow </b><br>
         Anzeigen/Verbergen des Grafik Tabellenkopfes mit Prognosedaten sowie bestimmten aktuellen und
         statistischen Werten. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHistoryHour"></a>
       <li><b>graphicHistoryHour </b><br>
         Anzahl der vorangegangenen Stunden die in der Balkengrafik dargestellt werden. <br>
         (default: 2)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHourCount"></a>
       <li><b>graphicHourCount &lt;4...24&gt; </b><br>
         Anzahl der Balken/Stunden in der Balkengrafk. <br>
         (default: 24)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHourStyle"></a>
       <li><b>graphicHourStyle </b><br>
         Format der Zeitangabe in der Balkengrafik. <br><br>

       <ul>
         <table>
           <colgroup> <col width="30%"> <col width="70%"> </colgroup>
           <tr><td> <b>nicht gesetzt</b>  </td><td>nur Stundenangabe ohne Minuten (default)                </td></tr>
           <tr><td> <b>:00</b>            </td><td>Stunden sowie Minuten zweistellig, z.B. 10:00           </td></tr>
           <tr><td> <b>:0</b>             </td><td>Stunden sowie Minuten einstellig, z.B. 8:0              </td></tr>
         </table>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicLayoutType"></a>
       <li><b>graphicLayoutType &lt;single | double | diff&gt; </b><br>
       Layout der Balkengrafik. <br>
       Der darzustellende Inhalt der Balken wird durch die Attribute <b>graphicBeam1Content</b> bzw.
       <b>graphicBeam2Content</b> bestimmt.
       <br><br>

       <ul>
       <table>
       <colgroup> <col width="10%"> <col width="90%"> </colgroup>
          <tr><td> <b>double</b>  </td><td>zeigt den primären Balken und den sekundären Balken an (default)                                               </td></tr>
          <tr><td> <b>single</b>  </td><td>zeigt nur den primären Balken an                                                                               </td></tr>
          <tr><td> <b>diff</b>    </td><td>Differenzanzeige. Es gilt:  &lt;Differenz&gt; = &lt;Wert primärer Balken&gt; - &lt;Wert sekundärer Balken&gt;  </td></tr>
       </table>
       </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicSelect"></a>
       <li><b>graphicSelect </b><br>
         Wählt die anzuzeigenden Grafiksegmente des Moduls aus. <br>
         Zur Anpassung der Energieflußgrafik steht neben den flowGraphic.*-Attributen auch
         das Attribut <a href="#SolarForecast-attr-flowGraphicCss">flowGraphicCss</a> zur Verfügung. <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>both</b>       </td><td>zeigt den Header, die Verbraucherlegende, Energiefluß- und Vorhersagegrafik an (default)   </td></tr>
            <tr><td> <b>flow</b>       </td><td>zeigt den Header, die Verbraucherlegende und Energieflußgrafik an                          </td></tr>
            <tr><td> <b>forecast</b>   </td><td>zeigt den Header, die Verbraucherlegende und die Vorhersagegrafik an                       </td></tr>
            <tr><td> <b>none</b>       </td><td>zeigt nur den Header und die Verbraucherlegende an                                         </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-graphicShowDiff"></a>
       <li><b>graphicShowDiff &lt;no | top | bottom&gt; </b><br>
         Zusätzliche Anzeige der Differenz "graphicBeam1Content - graphicBeam2Content" im Kopf- oder Fußbereich der
         Balkengrafik. <br>
         (default: no)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicShowNight"></a>
       <li><b>graphicShowNight </b><br>
         Anzeigen/Verbergen der Nachtstunden (ohne Ertragsprognose) in der Balkengrafik. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicShowWeather"></a>
       <li><b>graphicShowWeather </b><br>
         Wettericons in der Balkengrafik anzeigen/verbergen. <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicStartHtml"></a>
       <li><b>graphicStartHtml &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der vor dem Grafik-Code ausgeführt wird.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicEndHtml"></a>
       <li><b>graphicEndHtml &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der nach dem Grafik-Code ausgeführt wird.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicSpaceSize"></a>
       <li><b>graphicSpaceSize &lt;value&gt; </b><br>
         Legt fest wieviel Platz in px über oder unter den Balken (bei Anzeigetyp Differential (diff)) zur Anzeige der
         Werte freigehalten wird. Bei Styles mit großen Fonts kann der default-Wert zu klein sein bzw. rutscht ein
         Balken u.U. über die Grundlinie. In diesen Fällen bitte den Wert erhöhen. <br>
         (default: 24)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicWeatherColor"></a>
       <li><b>graphicWeatherColor </b><br>
         Farbe der Wetter-Icons in der Balkengrafik für die Tagesstunden.
       </li>
       <br>

       <a id="SolarForecast-attr-graphicWeatherColorNight"></a>
       <li><b>graphicWeatherColorNight </b><br>
         Farbe der Wetter-Icons für die Nachtstunden.
       </li>
       <br>

     </ul>
  </ul>

</ul>

=end html_DE

=for :application/json;q=META.json 76_SolarForecast.pm
{
  "abstract": "Creation of solar forecasts of PV systems including consumption forecasts and consumer management",
  "x_lang": {
    "de": {
      "abstract": "Erstellung solarer Vorhersagen von PV Anlagen inklusive Verbrauchsvorhersagen und Verbrauchermanagement"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "forecast",
    "graphics",
    "Autarky",
    "Consumer",
    "PV"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
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
      "web": "https://wiki.fhem.de/wiki/SolarForecast_-_Solare_Prognose_(PV_Erzeugung)_und_Verbrauchersteuerung",
      "title": "SolarForecast - Solare Prognose (PV Erzeugung) und Verbrauchersteuerung"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut
