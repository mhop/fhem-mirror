########################################################################################################################
# $Id: 76_SolarForecast.pm 21735 2022-11-15 23:53:24Z DS_Starter $
#########################################################################################################################
#       76_SolarForecast.pm
#
#       (c) 2020-2022 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
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
#########################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 76_SolarForecast.pm
#
#########################################################################################################################
package FHEM::SolarForecast;                              ## no critic 'package'

use strict;
use warnings;
use POSIX;
use GPUtils qw(GP_Import GP_Export);                                       # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday tv_interval);

eval "use FHEM::Meta;1"                  or my $modMetaAbsent = 1;         ## no critic 'eval'
eval "use FHEM::Utility::CTZ qw(:all);1" or my $ctzAbsent     = 1;         ## no critic 'eval'

use Encode;
use Color;
use utf8;
use HttpUtils;
eval "use JSON;1;" or my $jsonabs = "JSON";                                ## no critic 'eval' # Debian: apt-get install libjson-perl

use FHEM::SynoModules::SMUtils qw(
                                   evaljson
                                   getClHash
                                   delClHash
                                   moduleVersion
                                   trim
                                 );                                        # Hilfsroutinen Modul

use Data::Dumper;
use Storable 'dclone';
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          attr
          asyncOutput
          AnalyzePerlCommand
          AttrVal
          AttrNum
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
          FmtDateTime
          FileWrite
          FileRead
          FileDelete
          FmtTime
          FW_makeImage
          getKeyValue
          HttpUtils_NonblockingGet
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3
          modules
          parseParams
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
          readingFnAttributes
          setKeyValue
          sortTopicNum
          FW_cmd
          FW_directNotify
          FW_ME
          FW_subdir
          FW_room
          FW_detail
          FW_wname
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
  "0.74.1" => "15.11.2022  ___planMust -> half -> ceil to floor changed , Model SolCast: first call from 60 minutes before sunrise ".
                           "Model SolCast: release planning only after the first API retrieval ".
                           "Model DWD: release planning from one hour before sunrise ",
  "0.74.0" => "13.11.2022  new attribute affectConsForecastInPlanning ",
  "0.73.0" => "12.11.2022  save Ehodpieces (___saveEhodpieces), use debug modules, revise comref,typos , maxconsumer 12 ".
                           "attr ctrlLanguage for local language support, bugfix MODE is set to Manual after restart if ".
                           "attr ctrlInterval is not set, new attr consumerLink, graphic tooltips and formatting ",
  "0.72.5" => "08.11.2022  calculate percentile correction factor instead of best percentile, exploit all available API requests ".
                           "graphicBeamWidth more values, add moduleTiltAngle: 5,15,35,55,65,75,85 , ".
                           "fix _estConsumptionForecast, delete Setter pvSolCastPercentile_XX ",
  "0.72.4" => "06.11.2022  change __solCast_ApiResponse -> special processing first dataset of current hour ",
  "0.72.3" => "05.11.2022  new status bit CurrentVal allStringsFullfilled ",
  "0.72.2" => "05.11.2022  minor changes in header, rename more attributes, edit commandref, associatedWith is working again ",
  "0.72.1" => "31.10.2022  fix 'connection lost ...' issue again, global language check in checkPlantConfig ",
  "0.72.0" => "30.10.2022  rename some graphic attributes ",
  "0.71.4" => "29.10.2022  flowgraphic some changes (https://forum.fhem.de/index.php/topic,117864.msg1241836.html#msg1241836) ",
  "0.71.3" => "28.10.2022  new circular keys tdayDvtn, ydayDvtn for calculation PV forecast/generation in header ",
  "0.71.2" => "27.10.2022  fix 'connection lost ...' issue ",
  "0.71.1" => "26.10.2022  save no datasets with pv_estimate = 0 (__solCast_ApiResponse) to save time/space ".
                           "changed some graphic default settings, typo todayRemaingAPIcalls, input check currentBatteryDev ".
                           "change attr Css to flowGraphicCss ",
  "0.71.0" => "25.10.2022  new attribute createStatisticReadings, changed some default settings and commandref ",
  "0.70.10"=> "24.10.2022  write best percentil in pvHistory (_calcCAQwithSolCastPercentil instead of ___readPercAndQuality) ".
                           "add global dnsServer to checkPlantConfig ",
  "0.70.9 "=> "24.10.2022  create additional percentile only for pvCorrectionFactor_Auto on, changed __solCast_ApiResponse ".
                           "changed _calcCAQwithSolCastPercentil ",
  "0.70.8 "=> "23.10.2022  change average calculation in _calcCAQwithSolCastPercentil, unuse Notify/createAssociatedWith ".
                           "extend Delete func, extend plantconfig check, revise commandref, change set reset pvCorrection ".
                           "rename runTimeCycleSummary to runTimeCentralTask ",
  "0.70.7 "=> "22.10.2022  minor changes (Display is/whereabouts Solacast Requests, SolCast Forecast Quality, setup procedure) ",
  "0.70.6 "=> "19.10.2022  fix  ___setLastAPIcallKeyData ",
  "0.70.5 "=> "18.10.2022  new hidden getter plantConfigCheck ",
  "0.70.4 "=> "16.10.2022  change attr historyHour to positive numbers, plantconfig check changed ",
  "0.70.3 "=> "15.10.2022  check event-on-change-reading in plantConfiguration check ",
  "0.70.2 "=> "15.10.2022  average calculation in _calcCAQwithSolCastPercentil, delete reduce by temp in __calcSolCastEstimates ",
  "0.70.1 "=> "14.10.2022  new function setTimeTracking ",
  "0.70.0 "=> "13.10.2022  delete Attr solCastPercentile, new manual Setter pvSolCastPercentile_XX ",
  "0.69.0 "=> "12.10.2022  Autocorrection function for model SolCast-API, __solCast_ApiRequest: request only 48 hours ",
  "0.68.7 "=> "07.10.2022  new function _calcCAQwithSolCastPercentil, check missed modules in _getRoofTopData ",
  "0.68.6 "=> "06.10.2022  new attribute solCastPercentile, change _calcMaxEstimateToday ",
  "0.68.5 "=> "03.10.2022  extent plant configuration check ",
  "0.68.4 "=> "03.10.2022  do ___setLastAPIcallKeyData if response_status, generate events of Today_MaxPVforecast.* in every cycle ".
                           "add SolCast section in _graphicHeader, change default colors and settings, new reading Today_PVreal ".
                           "fix sub __setConsRcmdState ",
  "0.68.3 "=> "19.09.2022  fix calculation of currentAPIinterval ",
  "0.68.2 "=> "18.09.2022  fix function _setpvCorrectionFactorAuto, new attr optimizeSolCastAPIreqInterval, change createReadingsFromArray ",
  "0.68.1 "=> "17.09.2022  new readings Today_MaxPVforecast, Today_MaxPVforecastTime ",
  "0.68.0 "=> "15.09.2022  integrate SolCast API, change attribute Wh/kWh to Wh_kWh, rename Reading nextPolltime to ".
                           "nextCycletime, rework plant config check, minor (bug)fixes ",
  "0.67.6 "=> "02.09.2022  add ___setPlanningDeleteMeth, consumer can be planned across daily boundaries ".
                           "fix JS Fehler (__weatherOnBeam) Forum: https://forum.fhem.de/index.php/topic,117864.msg1233661.html#msg1233661 ",
  "0.67.5 "=> "28.08.2022  add checkRegex ",
  "0.67.4 "=> "28.08.2022  ___switchConsumerOn -> no switch on if additional switch off condition is true ".
                           "__setConsRcmdState -> Consumer can be switched on in case of missing PV power if key power=0 is set ".
                           "new process and additional split for hysteresis ",
  "0.67.3 "=> "22.08.2022  show cloudcover in weather __weatherOnBeam ",
  "0.67.2 "=> "11.08.2022  fix no disabled Link after restart and disable=1 ",
  "0.67.1 "=> "10.08.2022  fix warning, Forum: https://forum.fhem.de/index.php/topic,117864.msg1231050.html#msg1231050 ",
  "0.67.0 "=> "31.07.2022  change _gethtml, _getftui ",
  "0.66.0 "=> "24.07.2022  insert function ___calcPeaklossByTemp to calculate peak power reduction by temperature ",
  "0.65.8 "=> "23.07.2022  change calculation of cloud cover in calcRange function ",
  "0.65.7 "=> "20.07.2022  change performance ratio in __calcDWDforecast to 0.85 ",
  "0.65.6 "=> "20.07.2022  change __calcEnergyPieces for consumer types with \$hef{\$cotype}{f} == 1 ",
  "0.65.5 "=> "13.07.2022  extend isInterruptable and isAddSwitchOffCond ",
  "0.65.4 "=> "11.07.2022  new function isConsumerLogOn, minor fixes ",
  "0.65.3 "=> "10.07.2022  consumer with mode=must are now interruptable, change hourscsme ",
  "0.65.2 "=> "08.07.2022  change avgenergy to W p. hour ",
  "0.65.1 "=> "07.07.2022  change logic of __calcEnergyPieces function and the \%hef hash ",
  "0.65.0 "=> "03.07.2022  feature key interruptable for consumer ",
  "0.64.2 "=> "23.06.2022  fix switch off by switch off condition in ___switchConsumerOff ",
  "0.64.1 "=> "07.06.2022  fixing simplifyCstate, sub ___setConsumerSwitchingState to improve safe consumer switching ",
  "0.64.0 "=> "04.06.2022  consumer type charger added, new attr createConsumptionRecReadings ",
  "0.63.2 "=> "21.05.2022  changed isConsumptionRecommended to isIntimeframe, renewed isConsumptionRecommended ",
  "0.63.1 "=> "19.05.2022  code review __switchConsumer ",
  "0.63.0 "=> "18.05.2022  new attr flowGraphicConsumerDistance ",
  "0.62.0 "=> "16.05.2022  new key 'swoffcond' in consumer attributes ",
  "0.61.0 "=> "15.05.2022  limit PV forecast to inverter capacity ",
  "0.60.1 "=> "15.05.2022  consumerHash -> new key avgruntime, don't modify mintime by avgruntime by default anymore ".
                           "debug switch conditions ",
  "0.60.0 "=> "14.05.2022  new key 'swoncond' in consumer attributes ",
  "0.59.0 "=> "01.05.2022  new attr createTomorrowPVFcReadings ",
  "0.58.0 "=> "20.04.2022  new setter consumerImmediatePlanning, functions isConsumerPhysOn isConsumerPhysOff ",
  "0.57.3 "=> "10.04.2022  some fixes (\$eavg in ___csmSpecificEpieces, useAutoCorrection switch to regex) ",
  "0.57.2 "=> "03.04.2022  area factor for 25° added ",
  "0.57.1 "=> "28.02.2022  new attr flowGraphicShowConsumerPower and flowGraphicShowConsumerRemainTime (Consumer remainTime in flowGraphic)",
  "0.56.11"=> "01.12.2021  comment: 'next if(\$surplus <= 0);' to resolve consumer planning problem if 'mode = must' and the ".
                           "current doesn't have suplus ",
  "0.56.10"=> "14.11.2021  change sub _flowGraphic (Max), https://forum.fhem.de/index.php/topic,117864.msg1186970.html#msg1186970, new reset consumerMaster ",
  "0.56.9" => "27.10.2021  change sub _flowGraphic (Max) ",
  "0.56.8" => "25.10.2021  change func  ___csmSpecificEpieces as proposed from Max : https://forum.fhem.de/index.php/topic,117864.msg1180452.html#msg1180452 ",
  "0.56.7" => "18.10.2021  new attr flowGraphicShowConsumerDummy ",
  "0.56.6" => "19.09.2021  bug fix ",
  "0.56.5" => "16.09.2021  fix sub ___csmSpecificEpieces (rows 2924-2927) ",
  "0.56.4" => "16.09.2021  new sub ___csmSpecificEpieces ",
  "0.56.3" => "15.09.2021  extent __calcEnergyPieces by MadMax calc (first test implementation) ",
  "0.56.2" => "14.09.2021  some fixes, new calculation of hourscsmeXX, new key minutescsmXX ",
  "0.56.1" => "12.09.2021  some fixes ",
  "0.56.0" => "11.09.2021  new Attr flowGraphicShowConsumer, extend calc consumer power consumption ",
  "0.55.3" => "08.09.2021  add energythreshold to etotal key ",
  "0.55.2" => "08.09.2021  minor fixes, use Color ",
  "0.55.1" => "05.09.2021  delete invalid consumer index, Forum: https://forum.fhem.de/index.php/topic,117864.msg1173219.html#msg1173219 ",
  "0.55.0" => "04.09.2021  new key pcurr for attr customerXX ",
  "0.54.5" => "29.08.2021  change metadata ",
  "0.54.4" => "12.07.2021  round Current_PV in _transferInverterValues ",
  "0.54.3" => "11.07.2021  fix _flowGraphic because of Current_AutarkyRate with powerbatout ",
  "0.54.2" => "01.07.2021  fix Current_AutarkyRate with powerbatout ",
  "0.54.1" => "23.06.2021  better log in  __weatherOnBeam ",
  "0.54.0" => "19.06.2021  new calcCorrAndQuality, new reset pvCorrection circular, behavior of attr 'numHistDays', fixes ",
  "0.53.0" => "17.06.2021  Logic for preferential charging battery, attr preferredChargeBattery ",
  "0.52.5" => "16.06.2021  sub __weatherOnBeam ",
  "0.52.4" => "15.06.2021  minor fix, possible avoid implausible inverter values ",
  "0.52.3" => "14.06.2021  consumer on/off icon gray if no on/off command is defined, more consumer debug log ",
  "0.52.2" => "13.06.2021  attr consumerAdviceIcon can be 'none', new attr debug, minor fixes, write consumers cachefile ",
  "0.52.1" => "12.06.2021  change Attr Css behavior, new attr consumerAdviceIcon ",
  "0.52.0" => "12.06.2021  new Attr Css ",
  "0.51.3" => "10.06.2021  more refactoring, add 'none' to graphicSelect ",
  "0.51.2" => "05.06.2021  minor fixes ",
  "0.51.1" => "04.06.2021  minor fixes ",
  "0.51.0" => "03.06.2021  some bugfixing, Calculation of PV correction factors refined, new setter plantConfiguration ".
                           "delete getter stringConfig ",
  "0.50.2" => "02.06.2021  more refactoring, delete attr headerAlignment, consumerlegend as table ",
  "0.50.1" => "02.06.2021  switch to mathematical rounding of cloudiness range ",
  "0.50.0" => "01.06.2021  real switch off time in consumerXX_planned_stop when finished, change key 'ready' to 'auto' ".
                           "consider switch on Time limits (consumer keys notbefore/notafter) ",
  "0.49.5" => "01.06.2021  change pv correction factor to 1 if no historical factors found (only with automatic correction) ",
  "0.49.4" => "01.06.2021  fix wrong display at month change and using historyHour ",
  "0.49.3" => "31.05.2021  improve __calcDWDforecast pvcorrfactor for multistring configuration ",
  "0.49.2" => "31.05.2021  fix time calc in sub forecastGraphic ",
  "0.49.1" => "30.05.2021  no consumer check during start Forum: https://forum.fhem.de/index.php/topic,117864.msg1159959.html#msg1159959  ",
  "0.49.0" => "29.05.2021  consumer legend, attr consumerLegend, no negative val Current_SelfConsumption, Current_PV ",
  "0.48.0" => "28.05.2021  new optional key ready in consumer attribute ",
  "0.47.0" => "28.05.2021  add flowGraphic, attr flowGraphicSize, graphicSelect, flowGraphicAnimate ",
  "0.46.1" => "21.05.2021  set <> reset pvHistory <day> <hour> ",
  "0.46.0" => "16.05.2021  integrate intotal, outtotal to currentBatteryDev, set maxconsumer to 9 ",
  "0.45.1" => "13.05.2021  change the calc of etotal at the beginning of every hour in _transferInverterValues ".
                           "fix createAssociatedWith for currentBatteryDev ",
  "0.45.0" => "12.05.2021  integrate consumptionForecast to graphic, change beamXContent to pvForecast, pvReal ",
  "0.44.0" => "10.05.2021  consumptionForecast for attr beamXContent, consumer are switched on/off ",
  "0.43.0" => "08.05.2021  plan Consumers ",
  "0.42.0" => "01.05.2021  new attr consumerXX, currentMeterDev is mandatory, new getter valConsumerMaster ".
                           "new commandref ancor syntax ",
  "0.41.0" => "28.04.2021  _estConsumptionForecast: implement Smoothing difference ",
  "0.40.0" => "25.04.2021  change checkdwdattr, new attr follow70percentRule ",
  "0.39.0" => "24.04.2021  new attr sameWeekdaysForConsfc, readings Current_SelfConsumption, Current_SelfConsumptionRate, ".
                           "Current_AutarkyRate ",
  "0.38.3" => "21.04.2021  minor fixes in sub calcCorrAndQuality, Traffic light indicator for prediction quality, some more fixes ",
  "0.38.2" => "20.04.2021  fix _estConsumptionForecast, add consumption values to graphic ",
  "0.38.1" => "19.04.2021  bug fixing ",
  "0.38.0" => "18.04.2021  consumption forecast for the next hours prepared ",
  "0.37.0" => "17.04.2021  _estConsumptionForecast, new getter forecastQualities, new setter currentRadiationDev ".
                           "language sensitive setup hints ",
  "0.36.1" => "14.04.2021  add dayname to pvHistory ",
  "0.36.0" => "14.04.2021  add con to pvHistory, add quality info to pvCircular, new reading nextPolltime ",
  "0.35.0" => "12.04.2021  create additional PVforecast events - PV forecast until the end of the coming day ",
  "0.34.1" => "11.04.2021  further improvement of cloud dependent calculation autocorrection ",
  "0.34.0" => "10.04.2021  only hours with the same cloud cover range are considered for pvCorrection, some fixes ",
  "0.33.0" => "09.04.2021  new setter currentBatteryDev, bugfix in _transferMeterValues ",
  "0.32.0" => "09.04.2021  currentMeterDev can have: gcon=-gfeedin ",
  "0.31.1" => "07.04.2021  write new values to pvhistory, change CO to Current_Consumption in graphic ",
  "0.31.0" => "06.04.2021  extend currentMeterDev by gfeedin, feedtotal ",
  "0.30.0" => "05.04.2021  estimate readings to the minute in sub _createSummaries, new setter energyH4Trigger ",
  "0.29.0" => "03.04.2021  new setter powerTrigger ",
  "0.28.0" => "03.04.2021  new attributes beam1FontColor, beam2FontColor, rename/new some readings ",
  "0.27.0" => "02.04.2021  additional readings ",
  "0.26.0" => "02.04.2021  rename attr maxPV to maxValBeam, bugfix in _specialActivities ",
  "0.25.0" => "28.03.2021  changes regarding perlcritic, new getter valCurrent ",
  "0.24.0" => "26.03.2021  the language setting of the system is taken into account in the weather texts ".
                           "rename weatherColor_night to weatherColorNight, history_hour to historyHour ",
  "0.23.0" => "25.03.2021  change attr layoutType, fix calc reading Today_PVforecast ",
  "0.22.0" => "25.03.2021  event management, move DWD values one hour to the future, some more corrections ",
  "0.21.0" => "24.03.2021  event management ",
  "0.20.0" => "23.03.2021  new sub CircularVal, NexthoursVal, some fixes ",
  "0.19.0" => "22.03.2021  new sub HistoryVal, some fixes ",
  "0.18.0" => "21.03.2021  implement sub forecastGraphic from Wzut ",
  "0.17.1" => "21.03.2021  bug fixes, delete Helper->NextHour ",
  "0.17.0" => "20.03.2021  new attr cloudFactorDamping / rainFactorDamping, fixes in Graphic sub ",
  "0.16.0" => "19.03.2021  new getter nextHours, some fixes ",
  "0.15.3" => "19.03.2021  corrected weather consideration for call __calcDWDforecast ",
  "0.15.2" => "19.03.2021  some bug fixing ",
  "0.15.1" => "18.03.2021  replace ThisHour_ by NextHour00_ ",
  "0.15.0" => "18.03.2021  delete overhanging readings in sub _transferDWDRadiationValues ",
  "0.14.0" => "17.03.2021  new getter PVReal, weatherData, consumption total in currentMeterdev ",
  "0.13.0" => "16.03.2021  changed sub forecastGraphic from Wzut ",
  "0.12.0" => "16.03.2021  switch etoday to etotal ",
  "0.11.0" => "14.03.2021  new attr history_hour, beam1Content, beam2Content, implement sub forecastGraphic from Wzut, ".
                           "rename attr beamColor, beamColor2 , more fixes ",
  "0.10.0" => "13.03.2021  hour shifter in sub _transferMeterValues, lot of fixes ",
  "0.9.0"  => "13.03.2021  more helper hashes Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251 ".
                           "cachefile pvhist is persistent ",
  "0.8.0"  => "07.03.2021  helper hash Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350 ",
  "0.7.0"  => "01.03.2021  add function DbLog_splitFn ",
  "0.6.0"  => "27.01.2021  change __calcDWDforecast from formula 1 to formula 2 ",
  "0.5.0"  => "25.01.2021  add multistring support, add reset inverterStrings ",
  "0.4.0"  => "24.01.2021  setter moduleDirection, add Area factor to __calcDWDforecast, add reset pvCorrection ",
  "0.3.0"  => "21.01.2021  add cloud correction, add rain correction, add reset pvHistory, setter writeHistory ",
  "0.2.0"  => "20.01.2021  use SMUtils, JSON, implement getter data,html,pvHistory, correct the 'disable' problem ",
  "0.1.0"  => "09.12.2020  initial Version "
);

## Konstanten
###############
my $deflang      = 'EN';                                                          # default Sprache wenn nicht konfiguriert
my @chours       = (5..21);                                                       # Stunden des Tages mit möglichen Korrekturwerten
my $kJtokWh      = 0.00027778;                                                    # Umrechnungsfaktor kJ in kWh
my $defmaxvar    = 0.5;                                                           # max. Varianz pro Tagesberechnung Autokorrekturfaktor
my $definterval  = 70;                                                            # Standard Abfrageintervall
my $defslidenum  = 3;                                                             # max. Anzahl der Arrayelemente in Schieberegistern

my $pvhcache     = $attr{global}{modpath}."/FHEM/FhemUtils/PVH_SolarForecast_";   # Filename-Fragment für PV History (wird mit Devicename ergänzt)
my $pvccache     = $attr{global}{modpath}."/FHEM/FhemUtils/PVC_SolarForecast_";   # Filename-Fragment für PV Circular (wird mit Devicename ergänzt)
my $plantcfg     = $attr{global}{modpath}."/FHEM/FhemUtils/PVCfg_SolarForecast_"; # Filename-Fragment für PV Anlagenkonfiguration (wird mit Devicename ergänzt)
my $csmcache     = $attr{global}{modpath}."/FHEM/FhemUtils/PVCsm_SolarForecast_"; # Filename-Fragment für Consumer Status (wird mit Devicename ergänzt)
my $scpicache    = $attr{global}{modpath}."/FHEM/FhemUtils/ScApi_SolarForecast_"; # Filename-Fragment für Werte aus SolCast API (wird mit Devicename ergänzt)

my $calcmaxd     = 30;                                                            # Anzahl Tage die zur Berechnung Vorhersagekorrektur verwendet werden
my @dweattrmust  = qw(TTT Neff R101 ww SunUp SunRise SunSet);                     # Werte die im Attr forecastProperties des Weather-DWD_Opendata Devices mindestens gesetzt sein müssen
my @draattrmust  = qw(Rad1h);                                                     # Werte die im Attr forecastProperties des Radiation-DWD_Opendata Devices mindestens gesetzt sein müssen
my $whistrepeat  = 900;                                                           # Wiederholungsintervall Cache File Daten schreiben

my $apirepetdef  = 3600;                                                          # default Abrufintervall SolCast API (s)
my $apimaxreqs   = 50;                                                            # max. täglich mögliche Requests SolCast API
my $leadtime     = 3600;                                                          # relative Zeit vor Sonnenaufgang zur Freigabe API Abruf / Verbraucherplanung                                                  

my $prdef        = 0.85;                                                          # default Performance Ratio (PR)
my $tempcoeffdef = -0.45;                                                         # default Temperaturkoeffizient Pmpp (%/°C) lt. Datenblatt Solarzelle
my $tempmodinc   = 25;                                                            # default Temperaturerhöhung an Solarzellen gegenüber Umgebungstemperatur bei wolkenlosem Himmel
my $tempbasedef  = 25;                                                            # Temperatur Module bei Nominalleistung
my $cldampdef    = 35;                                                            # Gewichtung (%) des Korrekturfaktors bzgl. effektiver Bewölkung, siehe: https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
my $cloud_base   = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung

my $rdampdef     = 10;                                                            # Gewichtung (%) des Korrekturfaktors bzgl. Niederschlag (R101)
my $rain_base    = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung

my $maxconsumer  = 12;                                                            # maximale Anzahl der möglichen Consumer (Attribut)
my $epiecHCounts = 10;                                                            # Anzahl Einschaltzyklen (Consumer) für verbraucherspezifische Energiestück Ermittlung
my @ctypes       = qw(dishwasher dryer washingmachine heater charger other);      # erlaubte Consumer Typen
my $defmintime   = 60;                                                            # default min. Einschalt- bzw. Zykluszeit in Minuten
my $defctype     = "other";                                                       # default Verbrauchertyp
my $defcmode     = "can";                                                         # default Planungsmode der Verbraucher
my $defpopercent = 0.5;                                                           # Standard % aktuelle Leistung an nominaler Leistung gemäß Typenschild
my $defhyst      = 0;                                                             # default Hysterese

my $caicondef    = 'clock@gold';                                                  # default consumerAdviceIcon
my $flowGSizedef = 400;                                                           # default flowGraphicSize
my $histhourdef  = 2;                                                             # default Anzeige vorangegangene Stunden
my $wthcolddef   = 'C7C979';                                                      # Wetter Icon Tag default Farbe
my $wthcolndef   = 'C7C7C7';                                                      # Wetter Icon Nacht default Farbe
my $b1coldef     = 'FFAC63';                                                      # default Farbe Beam 1
my $b1fontcoldef = '0D0D0D';                                                      # default Schriftfarbe Beam 1
my $b2coldef     = 'C4C4A7';                                                      # default Farbe Beam 2
my $b2fontcoldef = '000000';                                                      # default Schriftfarbe Beam 2
my $fgCDdef      = 130;                                                           # Abstand Verbrauchericons zueinander

                                                                                  # default CSS-Style
my $cssdef       = qq{.flowg.text           { stroke: none; fill: gray; font-size: 60px; }                                     \n}.
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
my @dd           = qw( none
                       collectData
                       consumerPlanning
                       consumerSwitching
                       consumption
                       graphic
                       pvCorrection
                       radiationProcess
                       saveData2Cache
                       solcastProcess
                     );

# Steuerhashes
###############

my %hset = (                                                                # Hash der Set-Funktion
  consumerImmediatePlanning => { fn => \&_setconsumerImmediatePlanning },
  currentForecastDev        => { fn => \&_setcurrentForecastDev        },
  currentRadiationDev       => { fn => \&_setcurrentRadiationDev       },
  modulePeakString          => { fn => \&_setmodulePeakString          },
  inverterStrings           => { fn => \&_setinverterStrings           },
  clientAction              => { fn => \&_setclientAction              },
  currentInverterDev        => { fn => \&_setinverterDevice            },
  currentMeterDev           => { fn => \&_setmeterDevice               },
  currentBatteryDev         => { fn => \&_setbatteryDevice             },
  energyH4Trigger           => { fn => \&_setenergyH4Trigger           },
  plantConfiguration        => { fn => \&_setplantConfiguration        },
  powerTrigger              => { fn => \&_setpowerTrigger              },
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
  writeHistory              => { fn => \&_setwriteHistory              },
);

my %hget = (                                                                # Hash für Get-Funktion (needcred => 1: Funktion benötigt gesetzte Credentials)
  data               => { fn => \&_getdata,                   needcred => 0 },
  html               => { fn => \&_gethtml,                   needcred => 0 },
  ftui               => { fn => \&_getftui,                   needcred => 0 },
  valCurrent         => { fn => \&_getlistCurrent,            needcred => 0 },
  valConsumerMaster  => { fn => \&_getlistvalConsumerMaster,  needcred => 0 },
  plantConfigCheck   => { fn => \&_setplantConfiguration,     needcred => 0 },
  pvHistory          => { fn => \&_getlistPVHistory,          needcred => 0 },
  pvCircular         => { fn => \&_getlistPVCircular,         needcred => 0 },
  forecastQualities  => { fn => \&_getForecastQualities,      needcred => 0 },
  nextHours          => { fn => \&_getlistNextHours,          needcred => 0 },
  roofTopData        => { fn => \&_getRoofTopData,            needcred => 0 },
  solCastData        => { fn => \&_getlistSolCastData,        needcred => 0 },
);

my %hattr = (                                                                # Hash für Attr-Funktion
  consumer                      => { fn => \&_attrconsumer            },
  createConsumptionRecReadings  => { fn => \&_attrcreateConsRecRdgs   },
  createStatisticReadings       => { fn => \&_attrcreateStatisticRdgs },
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
  cfd    => { EN => qq{Please select the Weather forecast device with "set LINK currentForecastDev"},
              DE => qq{Bitte geben sie das Wettervorhersage Device mit "set LINK currentForecastDev" an}                    },
  crd    => { EN => qq{Please select the radiation forecast service with "set LINK currentRadiationDev"},
              DE => qq{Bitte geben sie den Strahlungsvorhersage Dienst mit "set LINK currentRadiationDev" an}               },
  cid    => { EN => qq{Please specify the Inverter device with "set LINK currentInverterDev"},
              DE => qq{Bitte geben sie das Wechselrichter Device mit "set LINK currentInverterDev" an}                      },
  mid    => { EN => qq{Please specify the device for energy measurement with "set LINK currentMeterDev"},
              DE => qq{Bitte geben sie das Device zur Energiemessung mit "set LINK currentMeterDev" an}                     },
  ist    => { EN => qq{Please define all of your used string names with "set LINK inverterStrings"},
              DE => qq{Bitte geben sie alle von Ihnen verwendeten Stringnamen mit "set LINK inverterStrings" an}            },
  mps    => { EN => qq{Please enter the DC peak power of each string with "set LINK modulePeakString"},
              DE => qq{Bitte geben sie die DC Spitzenleistung von jedem String mit "set LINK modulePeakString" an}          },
  mdr    => { EN => qq{Please specify the module direction with "set LINK moduleDirection"},
              DE => qq{Bitte geben Sie die Modulausrichtung mit "set LINK moduleDirection" an}                              },
  mta    => { EN => qq{Please specify the module tilt angle with "set LINK moduleTiltAngle"},
              DE => qq{Bitte geben Sie den Modulneigungswinkel mit "set LINK moduleTiltAngle" an}                           },
  rip    => { EN => qq{Please specify at least one combination Rooftop-ID/SolCast-API with "set LINK roofIdentPair"},
              DE => qq{Bitte geben Sie mindestens eine Kombination Rooftop-ID/SolCast-API mit "set LINK roofIdentPair" an}  },
  mrt    => { EN => qq{Please set the assignment String / Rooftop identification with "set LINK moduleRoofTops"},
              DE => qq{Bitte setzen Sie die Zuordnung String / Rooftop Identifikation mit "set LINK moduleRoofTops"}        },
  cnsm   => { EN => qq{Consumer},
              DE => qq{Verbraucher}                                                                                         },
  eiau   => { EN => qq{Off/On},
              DE => qq{Aus/Ein}                                                                                             },
  auto   => { EN => qq{Auto},
              DE => qq{Auto}                                                                                                },
  lupt   => { EN => qq{last&nbsp;update:},
              DE => qq{Stand:}                                                                                              },
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
  tday   => { EN => qq{today},
              DE => qq{heute}                                                                                               },
  yday   => { EN => qq{yesterday},
              DE => qq{gestern}                                                                                             },
  after  => { EN => qq{after},
              DE => qq{nach}                                                                                                },
  nxtscc => { EN => qq{next SolCast call},
              DE => qq{n&auml;chste SolCast Abfrage}                                                                        },  
  pstate => { EN => qq{Planning&nbsp;status:&nbsp;<pstate><br>On:&nbsp;<start><br>Off:&nbsp;<stop>},
              DE => qq{Planungsstatus:&nbsp;<pstate><br>Ein:&nbsp;<start><br>Aus:&nbsp;<stop>}                              },
  fulfd  => { EN => qq{fulfilled},
              DE => qq{erf&uuml;llt}                                                                                        },
  pmtp   => { EN => qq{produced more than predicted :-D},
              DE => qq{mehr produziert als vorhergesagt :-D}                                                                },
  petp   => { EN => qq{produced same as predicted :-)},
              DE => qq{produziert wie vorhergesagt :-)}                                                                     },
  pltp   => { EN => qq{produced less than predicted :-(},
              DE => qq{weniger produziert als vorhergesagt :-(}                                                             },
  wusond => { EN => qq{wait until sunset},
              DE => qq{bis zum Sonnenuntergang warten}                                                                      },
  snbefb => { EN => qq{should not be empty - maybe you found a bug},
              DE => qq{sollte nicht leer sein, vielleicht haben Sie einen Bug gefunden}                                     },  
  awd    => { EN => qq{LINK is waiting for solar forecast data ... <br><br>(The configuration can be checked with "set LINK plantConfiguration check".) },
              DE => qq{LINK wartet auf Solarvorhersagedaten ... <br><br>(Die Konfiguration kann mit "set LINK plantConfiguration check" gepr&uuml;ft werden.)} },
  strok  => { EN => qq{Congratulations &#128522;, the system configuration is error-free. Please note any information (<I>).},
              DE => qq{Herzlichen Glückwunsch &#128522;, die Anlagenkonfiguration ist fehlerfrei. Bitte eventuelle Hinweise (<I>) beachten.}                   },
  strwn  => { EN => qq{Looks quite good &#128528;, the system configuration is basically OK. Please note the warnings (<W>).},
              DE => qq{Sieht ganz gut aus &#128528;, die Anlagenkonfiguration ist prinzipiell in Ordnung. Bitte beachten Sie die Warnungen (<W>).}             },
  strnok => { EN => qq{Oh no &#128577;, the system configuration is incorrect. Please check the settings and notes!},
              DE => qq{Oh nein &#128546;, die Anlagenkonfiguration ist fehlerhaft. Bitte überprüfen Sie die Einstellungen und Hinweise!}                       },
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
  connorec => { EN => qq{Consumption planning is outside current time\n(Click for immediate planning)},
                DE => qq{Verbrauchsplanung liegt ausserhalb aktueller Zeit\n(Klick f&#252;r sofortige Einplanung)} },
  pstate   => { EN => qq{Planning&nbsp;status:&nbsp;<pstate>\n\nOn:&nbsp;<start>\nOff:&nbsp;<stop>},
                DE => qq{Planungsstatus:&nbsp;<pstate>\n\nEin:&nbsp;<start>\nAus:&nbsp;<stop>}                     },
  akorron  => { EN => qq{Enable auto correction with:\nset <NAME> pvCorrectionFactor_Auto on},
                DE => qq{Einschalten Autokorrektur mit:\nset <NAME> pvCorrectionFactor_Auto on}                    },
  splus    => { EN => qq{PV surplus sufficient},
                DE => qq{PV-&#220;berschu&#223; ausreichend}                                                       },
  nosplus  => { EN => qq{PV surplus insufficient},
                DE => qq{PV-&#220;berschu&#223; unzureichend}                                                      },
  plchk    => { EN => qq{Configuration check of the plant},
                DE => qq{Konfigurationspr&#252;fung der Anlage}                                                    },
  scaresps => { EN => qq{SolCast API request successful},
                DE => qq{SolCast API Abfrage erfolgreich}                                                          },
  scarespf => { EN => qq{SolCast API request failed},
                DE => qq{SolCast API Abfrage fehlgeschlagen}                                                       },
  dapic    => { EN => qq{done API calls},
                DE => qq{bisherige API Abfragen}                                                                   },
  rapic    => { EN => qq{remaining API calls},
                DE => qq{verf&#252;gbare API Abfragen}                                                             },
  yheyfdl  => { EN => qq{You have exceeded your free daily limit!},
                DE => qq{Sie haben Ihr kostenloses Tageslimit &#252;berschritten!}                                 },
  scakdne  => { EN => qq{API key does not exist},
                DE => qq{API Schl&#252;ssel existiert nicht}                                                       },
  scrsdne  => { EN => qq{Rooftop site does not exist or is not accessible},
                DE => qq{Rooftop ID existiert nicht oder ist nicht abrufbar}                                       },
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
  "washingmachine" => { f => 0.30, m => 0.40, l => 0.30, mt => 120         },
);

my %hcsr = (                                                                                  # Funktiontemplate zur Erstellung optionaler Statistikreadings
  currentAPIinterval         => { fnr => 1, fn => \&SolCastAPIVal, def => 0           },
  lastretrieval_time         => { fnr => 1, fn => \&SolCastAPIVal, def => '-'         },
  lastretrieval_timestamp    => { fnr => 1, fn => \&SolCastAPIVal, def => '-'         },
  response_message           => { fnr => 1, fn => \&SolCastAPIVal, def => '-'         },
  todayMaxAPIcalls           => { fnr => 1, fn => \&SolCastAPIVal, def => $apimaxreqs },
  todayDoneAPIcalls          => { fnr => 1, fn => \&SolCastAPIVal, def => 0           },
  todayDoneAPIrequests       => { fnr => 1, fn => \&SolCastAPIVal, def => 0           },
  todayRemainingAPIcalls     => { fnr => 1, fn => \&SolCastAPIVal, def => $apimaxreqs },
  todayRemainingAPIrequests  => { fnr => 1, fn => \&SolCastAPIVal, def => $apimaxreqs },
  runTimeCentralTask         => { fnr => 2, fn => \&CurrentVal,    def => '-'         },
  runTimeLastAPIAnswer       => { fnr => 2, fn => \&CurrentVal,    def => '-'         },
  runTimeLastAPIProc         => { fnr => 2, fn => \&CurrentVal,    def => '-'         },
  allStringsFullfilled       => { fnr => 2, fn => \&CurrentVal,    def => 0           },
);

# Information zu verwendeten internen Datenhashes
# $data{$type}{$name}{circular}                                                  # Ringspeicher
# $data{$type}{$name}{current}                                                   # current values
# $data{$type}{$name}{pvhist}                                                    # historische Werte
# $data{$type}{$name}{nexthours}                                                 # NextHours Werte
# $data{$type}{$name}{consumers}                                                 # Consumer Hash
# $data{$type}{$name}{strings}                                                   # Stringkonfiguration
# $data{$type}{$name}{solcastapi}                                                # Zwischenspeicher Vorhersagewerte SolCast API

################################################################
#               Init Fn
################################################################
sub Initialize {
  my $hash = shift;

  my $fwd   = join ",", devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
  my $hod   = join ",", map { sprintf "%02d", $_} (01..24);
  my $srd   = join ",", sort keys (%hcsr);

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
  # $hash->{NotifyFn}           = \&Notify;                                              # wird zur Zeit nicht genutzt/verwendet
  $hash->{AttrList}           = "affect70percentRule:1,dynamic,0 ".
                                "affectBatteryPreferredCharge:slider,0,1,100 ".
                                "affectCloudfactorDamping:slider,0,1,100 ".
                                "affectConsForecastIdentWeekdays:1,0 ".
                                "affectConsForecastInPlanning:1,0 ".
                                "affectMaxDayVariance ".
                                "affectNumHistDays:slider,1,1,30 ".
                                "affectRainfactorDamping:slider,0,1,100 ".
                                "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                "consumerAdviceIcon ".
                                "consumerLink:0,1 ".
                                "ctrlAutoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "ctrlAutoRefreshFW:$fwd ".
                                "ctrlConsRecommendReadings:multiple-strict,$allcs ".
                                "ctrlDebug:multiple-strict,$dm ".
                                "ctrlInterval ".
                                "ctrlLanguage:DE,EN ".
                                "ctrlOptimizeSolCastInterval:1,0 ".
                                "ctrlNextDayForecastReadings:multiple-strict,$hod ".
                                "ctrlShowLink:1,0 ".
                                "ctrlStatisticReadings:multiple-strict,$srd ".
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
                                "graphicHeaderDetail:all,co,pv,pvco,statusLink ".
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

 $hash->{AttrRenameMap} = { "beam1Color"         => "graphicBeam1Color",
                            "beam1Content"       => "graphicBeam1Content",
                            "beam1FontColor"     => "graphicBeam1FontColor",
                            "beam2Color"         => "graphicBeam2Color",
                            "beam2Content"       => "graphicBeam2Content",
                            "beam2FontColor"     => "graphicBeam2FontColor",
                            "beamHeight"         => "graphicBeamHeight",
                            "beamWidth"          => "graphicBeamWidth",
                            "historyHour"        => "graphicHistoryHour",
                            "hourCount"          => "graphicHourCount",
                            "hourStyle"          => "graphicHourStyle",
                            "layoutType"         => "graphicLayoutType",
                            "maxValBeam"         => "graphicBeam1MaxVal",
                            "showDiff"           => "graphicShowDiff",
                            "showNight"          => "graphicShowNight",
                            "showWeather"        => "graphicShowWeather",
                            "spaceSize"          => "graphicSpaceSize",
                            "weatherColor"       => "graphicWeatherColor",
                            "weatherColorNight"  => "graphicWeatherColorNight",
                            "htmlStart"          => "graphicStartHtml",
                            "htmlEnd"            => "graphicEndHtml",
                            "showHeader"         => "headerShow",
                            "headerDetail"       => "graphicHeaderDetail",
                            "headerShow"         => "graphicHeaderShow",
                            "cloudFactorDamping" => "affectCloudfactorDamping",
                            "rainFactorDamping"  => "affectRainfactorDamping",
                            "numHistDays"        => "affectNumHistDays",
                            "maxVariancePerDay"  => "affectMaxDayVariance",
                            "follow70percentRule"=> "affect70percentRule",
                            "Wh_kWh"             => "graphicEnergyUnit",
                            "autoRefreshFW"      => "ctrlAutoRefreshFW",
                            "autoRefresh"        => "ctrlAutoRefresh",
                            "showLink"           => "ctrlShowLink",
                            "optimizeSolCastAPIreqInterval" => "ctrlOptimizeSolCastInterval",
                            "interval"           => "ctrlInterval",
                            "createStatisticReadings" => "ctrlStatisticReadings",
                            "createConsumptionRecReadings" => "ctrlConsRecommendReadings",
                            "createTomorrowPVFcReadings" => "ctrlNextDayForecastReadings",
                            "preferredChargeBattery" => "affectBatteryPreferredCharge",
                            "sameWeekdaysForConsfc"  => "affectConsForecastIdentWeekdays",
                            "debug"           => "ctrlDebug",
                          };

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
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden

  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 1,
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                        # Versionsinformationen setzen

  createAssociatedWith ($hash);

  $params->{file}       = $pvhcache.$name;                                         # Cache File PV History lesen wenn vorhanden
  $params->{cachename}  = "pvhist";
  _readCacheFile ($params);

  $params->{file}       = $pvccache.$name;                                         # Cache File PV Circular lesen wenn vorhanden
  $params->{cachename}  = "circular";
  _readCacheFile ($params);

  $params->{file}       = $csmcache.$name;                                         # Cache File Consumer lesen wenn vorhanden
  $params->{cachename}  = "consumers";
  _readCacheFile ($params);

  $params->{file}       = $scpicache.$name;                                        # Cache File SolCast API Werte lesen wenn vorhanden
  $params->{cachename}  = "solcastapi";
  _readCacheFile ($params);

  singleUpdateState ( {hash => $hash, state => 'initialized', evt => 1} );

  centralTask   ($hash);                                                                                 # Einstieg in Abfrage
  InternalTimer (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0); # Einstieg periodisches Schreiben historische Daten

return;
}

################################################################
#                   Cachefile lesen
################################################################
sub _readCacheFile {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $file      = $paref->{file};
  my $cachename = $paref->{cachename};

  my $name      = $hash->{NAME};

  my ($error, @content) = FileRead ($file);

  if(!$error) {
      my $json    = join "", @content;
      my $success = evaljson ($hash, $json);

      if($success) {
           $data{$hash->{TYPE}}{$name}{$cachename} = decode_json ($json);
           Log3($name, 3, qq{$name - SolarForecast cache "$cachename" restored});
      }
      else {
          Log3($name, 2, qq{$name - WARNING - The content of file "$file" is not readable and may be corrupt});
      }
  }

return;
}

###############################################################
#                  SolarForecast Set
###############################################################
sub Set {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name  = shift @a;
  my $opt   = shift @a;
  my @args  = @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
  my $prop1 = shift @a;
  my $prop2 = shift @a;

  return if(IsDisabled($name));

  my ($setlist,@fcdevs,@cfs,@scp,@condevs);
  my ($fcd,$ind,$med,$cf,$sp,$cons) = ("","","","","","noArg");

  my @re = qw( ConsumerMaster
               consumerPlanning
               currentBatteryDev
               currentForecastDev
               currentInverterDev
               currentMeterDev
               energyH4Trigger
               inverterStrings
               moduleRoofTops
               powerTrigger
               pvCorrection
               roofIdentPair
               pvHistory
             );
  my $resets = join ",",@re;

  @fcdevs = devspec2array("TYPE=DWD_OpenData");
  $fcd    = join ",", @fcdevs if(@fcdevs);

  push @fcdevs, 'SolCast-API';
  my $rdd = join ",", @fcdevs;

  for my $h (@chours) {
      push @cfs, 'pvCorrectionFactor_'. sprintf("%02d",$h);
  }
  $cf = join " ", @cfs;

  my $type  = $hash->{TYPE};

  for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {
      push @condevs, $c if($c);
  }
  $cons = join ",", @condevs if(@condevs);

  $setlist = "Unknown argument $opt, choose one of ".
             "consumerImmediatePlanning:$cons ".
             "currentForecastDev:$fcd ".
             "currentRadiationDev:$rdd ".
             "currentBatteryDev:textField-long ".
             "currentInverterDev:textField-long ".
             "currentMeterDev:textField-long ".
             "energyH4Trigger:textField-long ".
             "inverterStrings ".
             "modulePeakString ".
             "moduleTiltAngle ".
             "moduleDirection ".
             "moduleRoofTops ".
             "plantConfiguration:check,save,restore ".
             "powerTrigger:textField-long ".
             "pvCorrectionFactor_Auto:on,off ".
             "reset:$resets ".
             "roofIdentPair ".
             "writeHistory:noArg ".
             $cf
             ;

  my $params = {
      hash    => $hash,
      name    => $name,
      type    => $type,
      opt     => $opt,
      arg     => $arg,
      argsref => \@args,
      prop    => $prop,
      prop1   => $prop1,
      prop2   => $prop2
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
  my $evt     = $paref->{prop1} // 1;

  return qq{no consumer number specified} if(!$c);
  return qq{no valid consumer id "$c"}    if(!ConsumerVal ($hash, $c, "name", ""));

  my $startts  = time;
  my $stopdiff = ceil(ConsumerVal ($hash, $c, "mintime", $defmintime) / 60) * 3600;
  my $stopts   = $startts + $stopdiff;

  $paref->{consumer} = $c;
  $paref->{ps}       = "planned:";
  $paref->{startts}  = $startts;                                                # Unix Timestamp für geplanten Switch on
  $paref->{stopts}   = $stopts;                                                 # Unix Timestamp für geplanten Switch off

  ___setConsumerPlanningState ($paref);
  ___saveEhodpieces           ($paref);
  ___setPlanningDeleteMeth    ($paref);

  my $planstate = ConsumerVal ($hash, $c, "planstate", "");
  my $calias    = ConsumerVal ($hash, $c, "alias",     "");

  writeDataToFile ($hash, "consumers", $csmcache.$name);                        # Cache File Consumer schreiben

  Log3 ($name, 3, qq{$name - Consumer "$calias" $planstate}) if($planstate);

  centralTask ($hash, $evt);

return;
}

################################################################
#       Setter currentForecastDev (Wetterdaten)
################################################################
sub _setcurrentForecastDev {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no forecast device specified};

  if(!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData") {
      return qq{The device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};
  }

  readingsSingleUpdate ($hash, "currentForecastDev", $prop, 1);
  createAssociatedWith ($hash);
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentRadiationDev
################################################################
sub _setcurrentRadiationDev {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no radiation device specified};

  if($prop ne 'SolCast-API' && (!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData")) {
      return qq{The device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};
  }

  if ($prop eq 'SolCast-API') {
      return "The library FHEM::Utility::CTZ is missing. Please update FHEM completely." if($ctzAbsent);

      my $rmf = reqModFail();
      return "You have to install the required perl module: ".$rmf if($rmf);
  }

  readingsSingleUpdate ($hash, "currentRadiationDev", $prop, 1);
  createAssociatedWith ($hash);
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben
  setModel             ($hash);                                             # Model setzen

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

  writeDataToFile ($hash, "solcastapi", $scpicache.$name);                             # Cache File SolCast API Werte schreiben

  my $msg = qq{The Roof identification pair "$pk" has been saved. }.
            qq{Repeat the command if you want to save more Roof identification pairs.};

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
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

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

  readingsSingleUpdate ($hash, "currentInverterDev", $arg, 1);
  createAssociatedWith ($hash);
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

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
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                      # keine Stringkonfiguration wenn Setup noch nicht komplett

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

  readingsSingleUpdate ($hash, "currentMeterDev", $arg, 1);
  createAssociatedWith ($hash);
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentBatteryDev
################################################################
sub _setbatteryDevice {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
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

  readingsSingleUpdate ($hash, "currentBatteryDev", $arg, 1);
  createAssociatedWith ($hash);
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter powerTrigger
################################################################
sub _setpowerTrigger {                    ## no critic "not used"
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

  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

  readingsSingleUpdate($hash, "powerTrigger", $arg, 1);

return;
}

################################################################
#                      Setter energyH4Trigger
################################################################
sub _setenergyH4Trigger {                ## no critic "not used"
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

  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

  readingsSingleUpdate($hash, "energyH4Trigger", $arg, 1);

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
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

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

  readingsSingleUpdate  ($hash, "moduleTiltAngle", $arg, 1);
  writeDataToFile       ($hash, "plantconfig", $plantcfg.$name);                  # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                      # keine Stringkonfiguration wenn Setup noch nicht komplett

  my $ret = createStringConfig ($hash);
  return $ret if($ret);

return;
}

################################################################
#                 Setter moduleDirection
################################################################
sub _setmoduleDirection {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no module direction was provided};

  my $dirs  = "N|NE|E|SE|S|SW|W|NW";                                          # mögliche Richtungsangaben

  my ($a,$h) = parseParams ($arg);

  if(!keys %$h) {
      return qq{The provided module direction has wrong format};
  }

  while (my ($key, $value) = each %$h) {
      if($value !~ /^(?:$dirs)$/x) {
          return qq{The module direction of "$key" is wrong: $value};
      }
  }

  readingsSingleUpdate ($hash, "moduleDirection", $arg, 1);
  writeDataToFile      ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

  return if(_checkSetupNotComplete ($hash));                                      # keine Stringkonfiguration wenn Setup noch nicht komplett

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

  if($arg eq "check") {
      my $out = checkPlantConfig ($hash);
      $out    = qq{<html>$out</html>};

      ## asynchrone Ausgabe
      #######################
      #$err          = getClHash($hash);
      #$paref->{out} = $out;
      #InternalTimer(gettimeofday()+3, "FHEM::SolarForecast::__plantCfgAsynchOut", $paref, 0);

      return $out;
  }

  if($arg eq "save") {
      $err = writeDataToFile ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben
      if($err) {
          return $err;
      }
      else {
          return qq{Plant Configuration has been written to file "}.$plantcfg.$name.qq{"};
      }
  }

  if($arg eq "restore") {
      ($err, @pvconf) = FileRead ($plantcfg.$name);

      if(!$err) {
          my $rbit = 0;
          for my $elem (@pvconf) {
              my ($reading, $val) = split "<>", $elem;
              next if(!$reading || !defined $val);
              CommandSetReading (undef,"$name $reading $val");
              $rbit = 1;
          }

          if($rbit) {
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

  readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", $prop, 1);

  if($prop eq "off") {
      for my $n (1..24) {
          $n     = sprintf "%02d", $n;
          my $rv = ReadingsVal ($name, "pvCorrectionFactor_${n}", "");
          deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*")  if($rv !~ /manual/xs);
      }

      deleteReadingspec ($hash, "pvCorrectionFactor_.*_autocalc");
  }

   writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                    # Anlagenkonfiguration sichern

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

  if($prop eq "pvHistory") {
      my $day   = $paref->{prop1} // "";                                       # ein bestimmter Tag der pvHistory angegeben ?
      my $dhour = $paref->{prop2} // "";                                       # eine bestimmte Stunde eines Tages der pvHistory angegeben ?

      if ($day) {
          if($dhour) {
              delete $data{$type}{$name}{pvhist}{$day}{$dhour};
              Log3($name, 3, qq{$name - Hour "$dhour" of day "$day" deleted in pvHistory});
          }
          else {
              delete $data{$type}{$name}{pvhist}{$day};
              Log3($name, 3, qq{$name - Day "$day" deleted in pvHistory});
          }
      }
      else {
          delete $data{$type}{$name}{pvhist};
          Log3($name, 3, qq{$name - all days of pvHistory deleted});
      }
      return;
  }

  if($prop eq "pvCorrection") {
      for my $n (1..24) {
          $n = sprintf "%02d", $n;
          deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*");
      }

      my $circ  = $paref->{prop1} // 'no';                                   # alle pvKorr-Werte aus Caches löschen ?
      my $circh = $paref->{prop2} // q{};                                    # pvKorr-Werte einer bestimmten Stunde aus Caches löschen ?

      if ($circ eq "cached") {
          if ($circh) {
              delete $data{$type}{$name}{circular}{$circh}{pvcorrf};
              delete $data{$type}{$name}{circular}{$circh}{quality};

              for my $hid (keys %{$data{$type}{$name}{pvhist}}) {
                  delete $data{$type}{$name}{pvhist}{$hid}{$circh}{pvcorrf};
              }

              Log3($name, 3, qq{$name - stored PV correction factor / SolCast percentile of hour "$circh" from pvCircular and pvHistory deleted});
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

          Log3($name, 3, qq{$name - all stored PV correction factors / SolCast percentile from pvCircular and pvHistory deleted});
      }

      return;
  }

  if($prop eq "powerTrigger") {
      deleteReadingspec ($hash, "powerTrigger.*");
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);              # Anlagenkonfiguration File schreiben
      return;
  }

  if($prop eq "energyH4Trigger") {
      deleteReadingspec ($hash, "energyH4Trigger.*");
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);              # Anlagenkonfiguration File schreiben
      return;
  }

  if($prop eq "moduleRoofTops") {
      deleteReadingspec ($hash, "moduleRoofTops");
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);              # Anlagenkonfiguration File schreiben
      return;
  }

  readingsDelete($hash, $prop);

  if($prop eq "roofIdentPair") {
      my $pk   = $paref->{prop1} // "";                                       # ein bestimmter PairKey angegeben ?

      if ($pk) {
          delete $data{$type}{$name}{solcastapi}{'?IdPair'}{'?'.$pk};
          Log3 ($name, 3, qq{$name - roofIdentPair: pair key "$pk" deleted});
      }
      else {
          delete $data{$type}{$name}{solcastapi}{'?IdPair'};
          Log3($name, 3, qq{$name - roofIdentPair: all pair keys deleted});
      }

      writeDataToFile ($hash, "solcastapi", $scpicache.$name);                # Cache File SolCast API Werte schreiben
      return;
  }

  if($prop eq "currentMeterDev") {
      readingsDelete($hash, "Current_GridConsumption");
      readingsDelete($hash, "Current_GridFeedIn");
      delete $hash->{HELPER}{INITCONTOTAL};
      delete $hash->{HELPER}{INITFEEDTOTAL};
      delete $data{$type}{$name}{current}{gridconsumption};
      delete $data{$type}{$name}{current}{tomorrowconsumption};
      delete $data{$type}{$name}{current}{gridfeedin};
      delete $data{$type}{$name}{current}{consumption};
      delete $data{$type}{$name}{current}{autarkyrate};
      delete $data{$type}{$name}{current}{selfconsumption};
      delete $data{$type}{$name}{current}{selfconsumptionrate};

      writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                       # Anlagenkonfiguration File schreiben
  }

  if($prop eq "currentBatteryDev") {
      readingsDelete($hash, "Current_PowerBatIn");
      readingsDelete($hash, "Current_PowerBatOut");
      readingsDelete($hash, "Current_BatCharge");
      delete $data{$type}{$name}{current}{powerbatout};
      delete $data{$type}{$name}{current}{powerbatin};
      delete $data{$type}{$name}{current}{batcharge};

      writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                       # Anlagenkonfiguration File schreiben
  }

  if($prop eq "currentInverterDev") {
      readingsDelete    ($hash, "Current_PV");
      deleteReadingspec ($hash, ".*_PVreal" );
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);                     # Anlagenkonfiguration File schreiben
  }

  if($prop eq "consumerPlanning") {                                                  # Verbraucherplanung resetten
      my $c = $paref->{prop1} // "";                                                 # bestimmten Verbraucher setzen falls angegeben

      if ($c) {
          deleteConsumerPlanning ($hash, $c);
      }
      else {
          for my $cs (keys %{$data{$type}{$name}{consumers}}) {
              deleteConsumerPlanning ($hash, $cs);
          }
      }

      writeDataToFile ($hash, "consumers", $csmcache.$name);                         # Cache File Consumer schreiben
  }

  if($prop eq "consumerMaster") {                                                    # Verbraucherhash löschen
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

      writeDataToFile ($hash, "consumers", $csmcache.$name);                         # Cache File Consumer schreiben
  }

  createAssociatedWith ($hash);

return;
}

################################################################
#                      Setter writeHistory
################################################################
sub _setwriteHistory {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  my $ret;

  $ret = writeDataToFile ($hash, "circular", $pvccache.$name);             # Cache File für PV Circular schreiben
  $ret = writeDataToFile ($hash, "pvhist",   $pvhcache.$name);             # Cache File für PV History schreiben

return $ret;
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

  my $evt      = shift @args;                                                 # Readings Event (state nicht gesteuert)
  my $action   = shift @args;                                                 # z.B. set, setreading
  my $cname    = shift @args;                                                 # Consumername
  my $tail     = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @args;     ## no critic 'Map blocks' # restliche Befehlsargumente

  Log3($name, 4, qq{$name - Client Action received / execute: "$action $cname $tail"});

  if($action eq "set") {
      CommandSet (undef, "$cname $tail");
  }

  if($action eq "get") {
      if($tail eq 'data') {
          centralTask ($hash, $evt);
          return;
      }
  }

  if($action eq "setreading") {
      CommandSetReading (undef, "$cname $tail");
  }

  if($action eq "consumerImmediatePlanning") {
      CommandSet (undef, "$name $action $cname $evt");
      return;
  }

  centralTask ($hash, $evt);

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

  my $getlist = "Unknown argument $opt, choose one of ".
                "valConsumerMaster:noArg ".
                "data:noArg ".
                "forecastQualities:noArg ".
                "html:noArg ".
                "nextHours:noArg ".
                "pvCircular:noArg ".
                "pvHistory:noArg ".
                "roofTopData:noArg ".
                "solCastData:noArg ".
                "valCurrent:noArg "
                ;

  return if(IsDisabled($name));

  my $params = {
      hash  => $hash,
      name  => $name,
      type  => $hash->{TYPE},
      opt   => $opt,
      arg   => $arg
  };

  if($hget{$opt} && defined &{$hget{$opt}{fn}}) {
      my $ret = q{};

      if (!$hash->{CREDENTIALS} && $hget{$opt}{needcred}) {
          return qq{Credentials of $name are not set."};
      }

      $params->{force} = 1 if($opt eq 'roofTopData');

      $ret = &{$hget{$opt}{fn}} ($params);                              # forcierter (manueller) Abruf SolCast API
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
  my $name  = $paref->{name};
  my $force = $paref->{force} // 0;
  my $t     = $paref->{t}     // time;
  
  my $lang  = AttrVal ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang));

  if (!$force) {                                                                                   # regulärer SolCast API Abruf
      my $trr  = SolCastAPIVal($hash, '?All', '?All', 'todayRemainingAPIrequests', $apimaxreqs);
      my $etxt = $hqtxt{bnsas}{$lang};
      $etxt    =~ s{<WT>}{($leadtime/60)}eg;
      
      if ($trr <= 0) {                                                                            
          readingsSingleUpdate($hash, 'nextSolCastCall', $etxt, 1);
          return qq{SolCast free daily limit is used up};
      }

      my $date   = strftime "%Y-%m-%d", localtime($t);
      my $srtime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunRise", '23:59').':59');
      my $sstime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunSet",  '00:00').':00');

      if ($t < $srtime - $leadtime || $t > $sstime) {
          readingsSingleUpdate($hash, 'nextSolCastCall', $etxt, 1);
          return "The current time is not between sunrise minus ".($leadtime/60)." minutes and sunset";
      }

      my $lrt    = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_timestamp',            0);
      my $apiitv = SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval',      $apirepetdef);

      if ($lrt && $t < $lrt + $apiitv) {
          my $rt = $lrt + $apiitv - $t;
          return qq{The waiting time to the next SolCast API call has not expired yet. The remaining waiting time is $rt seconds};
      }
  }

  my $msg;
  if($ctzAbsent) {
      $msg = qq{The library FHEM::Utility::CTZ is missing. Please update FHEM completely.};
      Log3 ($name, 2, "$name - ERROR - $msg");
      return $msg;
  }

  my $rmf = reqModFail();
  if($rmf) {
      $msg = "You have to install the required perl module: ".$rmf;
      Log3 ($name, 2, "$name - ERROR - $msg");
      return $msg;
  }

  my $type = $hash->{TYPE};

  ## statische SolCast API Kennzahlen bereitstellen
  ###################################################
  my %seen;
  my @as     = map { $data{$type}{$name}{solcastapi}{'?IdPair'}{$_}{apikey}; } keys %{$data{$type}{$name}{solcastapi}{'?IdPair'}};
  my @unique = grep { !$seen{$_}++ } @as;
  my $upc    = scalar @unique;                                                                      # Anzahl unique API Keys

  my $asc    = CurrentVal ($hash, 'allstringscount', 1);                                            # Anzahl der Strings
  my $madr   = sprintf "%.0f", (($apimaxreqs / $asc) * $upc);                                       # max. tägliche Anzahl API Calls
  my $mpk    = sprintf "%.4f", ($apimaxreqs / $madr);                                               # Requestmultiplikator

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{solCastAPIcallMultiplier}  = $mpk;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayMaxAPIcalls}          = $madr;

  ##

  $paref->{allstrings} = ReadingsVal($name, 'inverterStrings', '');
  $paref->{lang}       = $lang;
  
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
  my $allstrings = $paref->{allstrings} // return;                                # alle Strings

  my $string;
  ($string, $allstrings) = split ",", $allstrings, 2;

  my $rft    = ReadingsVal ($name, "moduleRoofTops", "");
  my ($a,$h) = parseParams ($rft);

  my $pk     = $h->{$string} // q{};
  my $roofid = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'rtid',   '');
  my $apikey = SolCastAPIVal ($hash, '?IdPair', '?'.$pk, 'apikey', '');
  my $debug  = AttrVal       ($name, 'ctrlDebug', 'none');

  if(!$roofid || !$apikey) {
      my $err = qq{The roofIdentPair "$pk" of String "$string" has no Rooftop-ID and/or SolCast-API key assigned !};
      singleUpdateState ( {hash => $hash, state => $err, evt => 1} );
      return $err;
  }

  my $url = "https://api.solcast.com.au/rooftop_sites/".
            $roofid.
            "/forecasts?format=json".
            "&hours=48".
            "&api_key=".
            $apikey;

  if($debug =~ /solcastProcess/x) {                                                                                         # nur für Debugging
      Log3 ($name, 1, qq{$name DEBUG> Request SolCast API for string "$string": $url});
  }

  my $caller = (caller(0))[3];                                          # Rücksprungmarke

  my $param = {
      url        => $url,
      timeout    => 30,
      hash       => $hash,
      caller     => \&$caller,
      stc        => [gettimeofday],
      allstrings => $allstrings,
      string     => $string,
      lang       => $paref->{lang},
      method     => "GET",
      callback   => \&__solCast_ApiResponse
  };

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

  my $hash       = $paref->{hash};
  my $name       = $hash->{NAME};
  my $caller     = $paref->{caller};
  my $string     = $paref->{string};
  my $allstrings = $paref->{allstrings};
  my $stc        = $paref->{stc};                                                                          # Startzeit API Abruf
  my $lang       = $paref->{lang};
  
  my $type       = $hash->{TYPE};
  my $t          = time;

  my $msg;

  my $sta = [gettimeofday];                                                                                # Start Response Verarbeitung

  if ($err ne "") {
      $msg = 'SolCast API server response: '.$err;

      Log3 ($name, 2, "$name - $msg");

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

          Log3 ($name, 2, "$name - $msg");

          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          return;
      }

      my $jdata = decode_json ($myjson);
      my $debug = AttrVal     ($name, 'ctrlDebug', 'none');

      if($debug =~ /solcastProcess/x) {                                                                                         # nur für Debugging
          Log3 ($name, 1, qq{$name DEBUG> SolCast API server response for string "$string":\n}. Dumper $jdata);
      }

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

          ___setLastAPIcallKeyData ($hash, $lang, $t);

          $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = $jdata->{'response_status'}{'message'};

          singleUpdateState ( {hash => $hash, state => $msg, evt => 1} );
          $data{$type}{$name}{current}{runTimeLastAPIProc}   = sprintf "%.4f", tv_interval($sta);                             # Verarbeitungszeit ermitteln
          $data{$type}{$name}{current}{runTimeLastAPIAnswer} = sprintf "%.4f", (tv_interval($stc) - tv_interval($sta));       # API Laufzeit ermitteln

          return;
      }

      my $k = 0;
      my ($period,$starttmstr);

      while ($jdata->{'forecasts'}[$k]) {                                                                # vorhandene Startzeiten Schlüssel im SolCast API Hash löschen
          my $petstr          = $jdata->{'forecasts'}[$k]{'period_end'};
          ($err, $starttmstr) = ___convPendToPstart ($name, $lang, $petstr);

          if ($err) {
              Log3 ($name, 2, "$name - $err");

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

      $k      = 0;
      my $uac = ReadingsVal ($name, 'pvCorrectionFactor_Auto', 'off');                                   # Auto- oder manuelle Korrektur

      while ($jdata->{'forecasts'}[$k]) {
          if(!$jdata->{'forecasts'}[$k]{'pv_estimate'}) {                                                # keine PV Prognose -> Datensatz überspringen -> Verarbeitungszeit sparen
              $k++;
              next;
          }

          my $petstr          = $jdata->{'forecasts'}[$k]{'period_end'};
          ($err, $starttmstr) = ___convPendToPstart ($name, $lang, $petstr);

          my $pvest50         = $jdata->{'forecasts'}[$k]{'pv_estimate'};

          $period             = $jdata->{'forecasts'}[$k]{'period'};
          $period             =~ s/.*(\d\d).*/$1/;

          if($debug =~ /solcastProcess/x) {                                                                                  # nur für Debugging
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

  ___setLastAPIcallKeyData ($hash, $lang, $t);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{response_message} = 'success';

  my $param = {
      hash       => $hash,
      name       => $name,
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
sub ___setLastAPIcallKeyData {
  my $hash = shift;
  my $lang = shift;
  my $t    = shift // time;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_time}      = (timestampToTimestring ($t, $lang))[3];   # letzte Abrufzeit
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{lastretrieval_timestamp} = $t;                                       # letzter Abrufzeitstempel

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests} += 1;

  my $drr  = $apimaxreqs - SolCastAPIVal($hash, '?All', '?All', 'todayDoneAPIrequests', 0);
  $drr     = 0 if($drr < 0);

  my $ddc  = SolCastAPIVal($hash, '?All', '?All', 'todayDoneAPIrequests',     0) /
             SolCastAPIVal($hash, '?All', '?All', 'solCastAPIcallMultiplier', 0);                                   # ausgeführte API Calls
  my $drc  = SolCastAPIVal($hash, '?All', '?All', 'todayMaxAPIcalls', $apimaxreqs) - $ddc;                          # verbleibende SolCast API Calls am aktuellen Tag
  $drc     = 0 if($drc < 0);

  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIrequests} = $drr;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIcalls}    = $drc;
  $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIcalls}         = $ddc;

  ## Berechnung des optimalen Request Intervalls
  ################################################
  if (AttrVal($name, 'ctrlOptimizeSolCastInterval', 0)) {
      my $date   = strftime "%Y-%m-%d", localtime($t);
      my $sstime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunSet",  '00:00').':00');
      my $dart   = $sstime - $t;                                                                                    # verbleibende Sekunden bis Sonnenuntergang
      $dart      = 0 if($dart < 0);
      $drc      += 1;                                                                                               

      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $apirepetdef;
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = int ($dart / $drc) if($dart && $drc);

      # Log3 ($name, 1, qq{$name - madr: $madr, drc: $drc, dart: $dart, interval: }. SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval', ""));
  }
  else {
      $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{currentAPIinterval} = $apirepetdef;
  }

  ####

  my $apiitv = SolCastAPIVal ($hash, '?All', '?All', 'currentAPIinterval', $apirepetdef);

  readingsSingleUpdate ($hash, 'nextSolCastCall', $hqtxt{after}{$lang}.' '.(timestampToTimestring ($t + $apiitv, $lang))[0], 1);

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

return pageAsHtml ($name);
}

###############################################################
#                       Getter ftui
#                ohne Eintrag in Get-Liste
###############################################################
sub _getftui {
  my $paref = shift;
  my $name  = $paref->{name};

return pageAsHtml ($name, "ftui");
}

###############################################################
#                       Getter pvHistory
###############################################################
sub _getlistPVHistory {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "pvhist");

return $ret;
}

###############################################################
#                       Getter pvCircular
###############################################################
sub _getlistPVCircular {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "circular");

return $ret;
}

###############################################################
#                       Getter nextHours
###############################################################
sub _getlistNextHours {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "nexthours");

return $ret;
}

###############################################################
#                       Getter pvQualities
###############################################################
sub _getForecastQualities {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "qualities");

return $ret;
}

###############################################################
#                       Getter valCurrent
###############################################################
sub _getlistCurrent {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "current");

return $ret;
}

###############################################################
#                       Getter valConsumerMaster
###############################################################
sub _getlistvalConsumerMaster {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "consumer");

return $ret;
}

###############################################################
#                       Getter solCastData
###############################################################
sub _getlistSolCastData {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my $ret   = listDataPool ($hash, "solcastdata");

return $ret;
}

################################################################
sub Attr {
  my $cmd   = shift;
  my $name  = shift;
  my $aName = shift;
  my $aVal  = shift;
  my $hash  = $defs{$name};

  my ($do,$val);

  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value

  if($aName eq "disable") {
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do  = 0 if($cmd eq "del");
      $val = ($do == 1 ? "disabled" : "initialized");
      singleUpdateState ( {hash => $hash, state => $val, evt => 1} );
  }

  if($aName eq "ctrlNextDayForecastReadings") {
      deleteReadingspec ($hash, "Tomorrow_Hour.*");
  }

  if ($cmd eq "set") {
      if ($aName eq "ctrlInterval") {
          unless ($aVal =~ /^[0-9]+$/x) {
              return qq{The value for $aName is not valid. Use only figures 0-9 !};
          }
          InternalTimer(gettimeofday()+1.0, "FHEM::SolarForecast::centralTask", $hash, 0);
      }

      if ($aName eq "affectMaxDayVariance") {
          unless ($aVal =~ /^[0-9.]+$/x) {
              return qq{The value for $aName is not valid. Use only numbers with optional decimal places !};
          }
      }

      if ($init_done == 1 && $aName eq "ctrlOptimizeSolCastInterval") {
          if (!isSolCastUsed ($hash)) {
              return qq{The attribute $aName is only valid for device model "SolCastAPI".};
          }
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

  $aName = "consumer" if($aName =~ /consumer?(\d+)$/xs);

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
  my $aName = $paref->{aName};
  my $aVal  = $paref->{aVal};
  my $cmd   = $paref->{cmd};

  return if(!$init_done);                                                                  # Forum: https://forum.fhem.de/index.php/topic,117864.msg1159959.html#msg1159959

  my $err;

  if($cmd eq "set") {
      my ($a,$h) = parseParams ($aVal);
      my $codev  = $a->[0] // "";

      if(!$codev || !$defs{$codev}) {
          return qq{The device "$codev" doesn't exist!};
      }

      if(!$h->{type} || !exists $h->{power}) {
          return qq{The syntax of "$aName" is not correct. Please consider the commandref.};
      }

      my $alowt = $h->{type} ~~ @ctypes ? 1 : 0;
      if(!$alowt) {
        return qq{The type "$h->{type}" isn't allowed!};
      }

      if($h->{power} !~ /^[0-9]+$/xs) {
          return qq{The key "power" must be specified only by numbers without decimal places};
      }

      if($h->{mode} && $h->{mode} !~ /^(?:can|must)$/xs) {
          return qq{The mode "$h->{mode}" isn't allowed!}
      }

      if($h->{interruptable}) {                                                            # Check Regex/Hysterese
          my (undef,undef,$regex,$hyst) = split ":", $h->{interruptable};

          $err = checkRegex ($regex);
          return $err if($err);

          if ($hyst && !isNumeric ($hyst)) {
              return qq{The hysteresis of key "interruptable" must be a numeric value like "0.5" or "2"};
          }
      }

      if($h->{swoncond}) {                                                                 # Check Regex
          my (undef,undef,$regex) = split ":", $h->{swoncond};

          $err = checkRegex ($regex);
          return $err if($err);
      }

      if($h->{swoffcond}) {                                                                # Check Regex
          my (undef,undef,$regex) = split ":", $h->{swoffcond};

          $err = checkRegex ($regex);
          return $err if($err);
      }

      if($h->{swstate}) {                                                                # Check Regex
          my (undef,$onregex,$offregex) = split ":", $h->{swstate};

          $err = checkRegex ($onregex);
          return $err if($err);

          $err = checkRegex ($offregex);
          return $err if($err);
      }
  }
  else {
      my $day  = strftime "%d", localtime(time);                                           # aktueller Tag  (range 01 to 31)
      my $type = $hash->{TYPE};
      my ($c)  = $aName =~ /consumer([0-9]+)/xs;

      deleteReadingspec ($hash, "consumer${c}.*");

      for my $i (1..24) {                                                                  # Consumer aus History löschen
          delete $data{$type}{$name}{pvhist}{$day}{sprintf("%02d",$i)}{"csmt${c}"};
          delete $data{$type}{$name}{pvhist}{$day}{sprintf("%02d",$i)}{"csme${c}"};
      }

      delete $data{$type}{$name}{pvhist}{$day}{99}{"csmt${c}"};
      delete $data{$type}{$name}{pvhist}{$day}{99}{"csme${c}"};
      delete $data{$type}{$name}{consumers}{$c};                                           # Consumer Hash Verbraucher löschen
  }

  writeDataToFile ($hash, "consumers", $csmcache.$name);                                   # Cache File Consumer schreiben

  InternalTimer(gettimeofday()+5, "FHEM::SolarForecast::createAssociatedWith", $hash, 0);

return;
}

################################################################
#               Attr createConsumptionRecReadings
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
#               Attr createStatisticReadings
################################################################
sub _attrcreateStatisticRdgs {           ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aName = $paref->{aName};

  deleteReadingspec ($hash, "statistic_.*");

return;
}

###################################################################################
#       Eventverarbeitung
#       (wird zur Zeit nicht genutzt/verwendet)
###################################################################################
sub Notify {
  # Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
  # Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben.

  return;         # nicht genutzt zur Zeit


  my $myHash   = shift;
  my $dev_hash = shift;
  my $myName   = $myHash->{NAME};                                                         # Name des eigenen Devices
  my $devName  = $dev_hash->{NAME};                                                       # Device welches Events erzeugt hat

  return if(IsDisabled($myName) || !$myHash->{NOTIFYDEV});

  my $events = deviceEvents($dev_hash, 1);
  return if(!$events);

  my $cdref     = CurrentVal ($myHash, "consumerdevs", "");                                # alle registrierten Consumer
  my @consumers = ();
  @consumers    = @{$cdref} if(ref $cdref eq "ARRAY");

  return if(!@consumers);

  if($devName ~~ @consumers) {
      my $cindex;
      my $type = $myHash->{TYPE};
      for my $c (sort{$a<=>$b} keys %{$data{$type}{$myName}{consumers}}) {
          my $cname = ConsumerVal ($myHash, $c, "name", "");
          if($devName eq $cname) {
              $cindex = $c;
              last;
          }
      }

      my $autoreading = ConsumerVal ($myHash, $cindex, "autoreading", "");

      for my $event (@{$events}) {
          $event  = "" if(!defined($event));
          my @evl = split(/\s+/x, $event);

          my @parts   = split(/: /x,$event, 2);
          my $reading = shift @parts;

          if ($reading eq "state" || $reading eq $autoreading) {
              Log3 ($myName, 4, qq{$myName - start centralTask by Notify - $devName:$reading});
              RemoveInternalTimer($myHash, "FHEM::SolarForecast::centralTask");
              InternalTimer      (gettimeofday()+0.5, "FHEM::SolarForecast::centralTask", $myHash, 0);
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

  writeDataToFile ($hash, "pvhist",      $pvhcache.$name);             # Cache File für PV History schreiben
  writeDataToFile ($hash, "circular",    $pvccache.$name);             # Cache File für PV Circular schreiben
  writeDataToFile ($hash, "consumers",   $csmcache.$name);             # Cache File Consumer schreiben
  writeDataToFile ($hash, "solcastapi", $scpicache.$name);             # Cache File SolCast API Werte schreiben

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
 my $arg  = shift;

 RemoveInternalTimer($hash);

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

  my $file  = $pvhcache.$name;                                                # Cache File PV History löschen
  my $error = FileDelete($file);

  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error});
  }

  $error = qq{};
  $file  = $pvccache.$name;                                                   # Cache File PV Circular löschen
  $error = FileDelete($file);

  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error});
  }


  $error = qq{};
  $file  = $plantcfg.$name;                                                   # File Anlagenkonfiguration löschen
  $error = FileDelete($file);

  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error});
  }

  $error = qq{};
  $file  = $csmcache.$name;                                                   # File Consumer löschen
  $error = FileDelete($file);

  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error});
  }

  $error = qq{};
  $file  = $scpicache.$name;                                                  # File SolCast API Werte löschen
  $error = FileDelete($file);

  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error});
  }

  my $type = $hash->{TYPE};

  delete $data{$type}{$name}{circular};                                       # Ringspeicher
  delete $data{$type}{$name}{current};                                        # current values
  delete $data{$type}{$name}{pvhist};                                         # historische Werte
  delete $data{$type}{$name}{nexthours};                                      # NextHours Werte
  delete $data{$type}{$name}{consumers};                                      # Consumer Hash
  delete $data{$type}{$name}{strings};                                        # Stringkonfiguration
  delete $data{$type}{$name}{solcastapi};                                     # Zwischenspeicher Vorhersagewerte SolCast API


return;
}

################################################################
#        Timer für Cache File Daten schreiben
################################################################
sub periodicWriteCachefiles {
  my $hash = shift;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "FHEM::SolarForecast::periodicWriteCachefiles");
  InternalTimer      (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0);

  return if(IsDisabled($name));

  writeDataToFile ($hash, "circular",  $pvccache.$name);             # Cache File für PV Circular schreiben
  writeDataToFile ($hash, "pvhist",    $pvhcache.$name);             # Cache File für PV History schreiben

return;
}

################################################################
#             Daten in File wegschreiben
################################################################
sub writeDataToFile {
  my $hash      = shift;
  my $cachename = shift;
  my $file      = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my @data;

  if($cachename eq "plantconfig") {
      @data = _savePlantConfig ($hash);
      return "Plant configuration is empty, no data has been written" if(!@data);
  }
  else {
      return if(!$data{$type}{$name}{$cachename});
      my $json = encode_json ($data{$type}{$name}{$cachename});
      push @data, $json;
  }

  my $error = FileWrite($file, @data);

  if ($error) {
      my $err = qq{ERROR writing cache file "$file": $error};
      Log3 ($name, 1, "$name - $err");
      singleUpdateState ( {hash => $hash, state => "ERROR writing cache file $file - $error", evt => 1} );
      return $err;
  }
  else {
      my $lw = gettimeofday();
      $hash->{HISTFILE} = "last write time: ".FmtTime($lw)." File: $file" if($cachename eq "pvhist");
      singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );
  }

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
                     currentForecastDev
                     currentInverterDev
                     currentMeterDev
                     currentRadiationDev
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
#                       Zentraler Datenabruf
################################################################
sub centralTask {
  my $hash = shift;
  my $evt  = shift // 1;                                              # Readings Event generieren

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $cst  = [gettimeofday];                                          # Zyklus-Startzeit

  RemoveInternalTimer($hash, "FHEM::SolarForecast::centralTask");
  RemoveInternalTimer($hash, "FHEM::SolarForecast::singleUpdateState");

  ### nicht mehr benötigte Readings/Daten löschen - kann später wieder raus !!
  ##############################################################
  #for my $i (keys %{$data{$type}{$name}{pvhist}}) {
  #    delete $data{$type}{$name}{pvhist}{$i}{"00"};
  #    delete $data{$type}{$name}{pvhist}{$i} if(!$i);                # evtl. vorhandene leere Schlüssel entfernen
  #}

  for my $c (keys %{$data{$type}{$name}{consumers}}) {
      delete $data{$type}{$name}{consumers}{$c}{epiecEstart};      
      delete $data{$type}{$name}{consumers}{$c}{epiecStart};   
      delete $data{$type}{$name}{consumers}{$c}{epiecStartEnergy};
  }

  #deleteReadingspec ($hash, "CurrentHourPVforecast");
  #deleteReadingspec ($hash, "NextHours_Sum00_PVforecast");
  #deleteReadingspec ($hash, "nextPolltime");
  #delete $data{$type}{$name}{solcastapi}{'All'};
  #delete $data{$type}{$name}{solcastapi}{'#All'};
  #delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todaySolCastAPIcalls};
  delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemaingAPIcalls};

  for my $n (1..24) {
      $n = sprintf "%02d", $n;
      deleteReadingspec ($hash, "pvSolCastPercentile_${n}.*");
  }
  ###############################################################

  setModel ($hash);                                                                                # Model setzen

  if($init_done == 1) {
      my $interval = controlParams ($name);
      my @da;

      if(!$interval) {
          $hash->{MODE} = "Manual";
          push @da, "nextCycletime<>Manual";
      }
      else {
          my $new = gettimeofday() + $interval;
          InternalTimer($new, "FHEM::SolarForecast::centralTask", $hash, 0);                       # Wiederholungsintervall

          if(!IsDisabled($name)) {
              $hash->{MODE} = "Automatic - next Cycletime: ".FmtTime($new);
              push @da, "nextCycletime<>".FmtTime($new);
          }
      }

      return if(IsDisabled($name));

      if(!CurrentVal ($hash, 'allStringsFullfilled', 0)) {                                         # die String Konfiguration erstellen wenn noch nicht erfolgreich ausgeführt
          my $ret = createStringConfig ($hash);
          if ($ret) {
              singleUpdateState ( {hash => $hash, state => $ret, evt => 1} );
              return;
          }
      }

      my $t       = time;                                                                          # aktuelle Unix-Zeit
      my $date    = strftime "%Y-%m-%d", localtime($t);                                            # aktuelles Datum
      my $chour   = strftime "%H",       localtime($t);                                            # aktuelle Stunde
      my $minute  = strftime "%M",       localtime($t);                                            # aktuelle Minute
      my $day     = strftime "%d",       localtime($t);                                            # aktueller Tag  (range 01 to 31)
      my $dayname = strftime "%a",       localtime($t);                                            # aktueller Wochentagsname
      my $debug   = AttrVal              ($name, 'ctrlDebug', 'none');                             # Debug Module

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
          lang    => AttrVal ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang)),
          state   => 'running',
          evt     => 0,
          daref   => \@da
      };

      if ($debug !~ /^none$/xs) {
          Log3 ($name, 4, "$name DEBUG> ################################################################");
          Log3 ($name, 4, "$name DEBUG> ###                  New centralTask cycle                   ###");
          Log3 ($name, 4, "$name DEBUG> ################################################################");
          Log3 ($name, 4, "$name DEBUG> current hour of day: ".($chour+1));
      }

      singleUpdateState           ($centpars);
      $centpars->{state} = 'updated';

      collectAllRegConsumers      ($centpars);                                            # alle Verbraucher Infos laden
      _specialActivities          ($centpars);                                            # zusätzliche Events generieren + Sonderaufgaben
      _transferWeatherValues      ($centpars);                                            # Wetterwerte übertragen

      createReadingsFromArray ($hash, \@da, $evt);                                        # Readings erzeugen

      if (isSolCastUsed ($hash)) {
          _getRoofTopData                 ($centpars);                                    # SolCast API Strahlungswerte abrufen
          _transferSolCastRadiationValues ($centpars);                                    # SolCast API Strahlungswerte übertragen und Forecast erstellen
      }
      else {
          _transferDWDRadiationValues ($centpars);                                        # DWD Strahlungswerte übertragen und Forecast erstellen
      }

      _calcMaxEstimateToday       ($centpars);                                            # heutigen Max PV Estimate & dessen Tageszeit ermitteln
      _transferInverterValues     ($centpars);                                            # WR Werte übertragen
      _transferMeterValues        ($centpars);                                            # Energy Meter auswerten
      _transferBatteryValues      ($centpars);                                            # Batteriewerte einsammeln
      _manageConsumerData         ($centpars);                                            # Consumerdaten sammeln und planen
      _estConsumptionForecast     ($centpars);                                            # Verbrauchsprognose erstellen
      _evaluateThresholds         ($centpars);                                            # Schwellenwerte bewerten und signalisieren
      _calcReadingsTomorrowPVFc   ($centpars);                                            # zusätzliche Readings Tomorrow_HourXX_PVforecast berechnen
      _createSummaries            ($centpars);                                            # Zusammenfassungen erstellen
      _calcTodayPVdeviation       ($centpars);                                            # Vorhersageabweichung erstellen (nach Sonnenuntergang)

      createReadingsFromArray ($hash, \@da, $evt);                                        # Readings erzeugen

      calcCorrAndQuality          ($centpars);                                            # neue Korrekturfaktor/Qualität berechnen und speichern

      createReadingsFromArray ($hash, \@da, $evt);                                        # Readings erzeugen

      saveEnergyConsumption       ($centpars);                                            # Energie Hausverbrauch speichern

      setTimeTracking      ($hash, $cst, 'runTimeCentralTask');                           # Zyklus-Laufzeit ermitteln

      genStatisticReadings        ($centpars);                                            # optionale Statistikreadings erstellen

      createReadingsFromArray ($hash, \@da, $evt);                                        # Readings erzeugen

      if ($evt) {
          $centpars->{evt} = $evt;
          InternalTimer(gettimeofday()+1, "FHEM::SolarForecast::singleUpdateState", $centpars, 0);
      }
      else {
          $centpars->{evt} = 1;
          singleUpdateState ($centpars);
      }
  }
  else {
      InternalTimer(gettimeofday()+5, "FHEM::SolarForecast::centralTask", $hash, 0);
  }

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

  if(!@istrings) {
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
  else {                                                                                          # DWD Strahlungsquelle
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

      while (my ($key, $value) = each %$hd) {
          if ($key ~~ @istrings) {
              $data{$type}{$name}{strings}{$key}{dir} = $value;
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

  if(@tom) {
      return qq{Some Strings are not used. Please delete this string names from "inverterStrings" :}.join ",",@tom;
  }

  $data{$type}{$name}{current}{allStringsFullfilled} = 1;
return;
}

################################################################
#             Steuerparameter berechnen / festlegen
################################################################
sub controlParams {
  my $name = shift;

  my $interval = AttrVal($name, 'ctrlInterval', $definterval);           # 0 wenn manuell gesteuert

return $interval;
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
  my $daref = $paref->{daref};
  my $t     = $paref->{t};                                                 # aktuelle Zeit
  my $day   = $paref->{day};

  my ($ts,$ts1,$pvfc,$pvrl,$gcon);

  $ts1  = $date." ".sprintf("%02d",$chour).":00:00";

  $pvfc = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_PVforecast", 0);
  push @$daref, "LastHourPVforecast<>".$pvfc." Wh<>".$ts1;

  $pvrl = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_PVreal", 0);
  push @$daref, "LastHourPVreal<>".$pvrl." Wh<>".$ts1;

  $gcon = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_GridConsumption", 0);
  push @$daref, "LastHourGridconsumptionReal<>".$gcon." Wh<>".$ts1;

  ## Planungsdaten spezifisch löschen (Anfang und Ende nicht am selben Tag)
  ##########################################################################

  for my $c (keys %{$data{$type}{$name}{consumers}}) {
      next if(ConsumerVal ($hash, $c, "plandelete", "regular") eq "regular");

      my $planswitchoff = ConsumerVal    ($hash, $c, "planswitchoff", $t);
      my $pstate        = simplifyCstate (ConsumerVal ($hash, $c, "planstate", ""));

      if ($t > $planswitchoff && $pstate =~ /planned|finished|unknown/xs) {
          deleteConsumerPlanning ($hash, $c);

          $data{$type}{$name}{consumers}{$c}{minutesOn}       = 0;
          $data{$type}{$name}{consumers}{$c}{numberDayStarts} = 0;
          $data{$type}{$name}{consumers}{$c}{onoff}           = "off";
      }
  }

  ## bestimmte einmalige Aktionen
  ##################################

  my $tlim = "00";
  if($chour =~ /^($tlim)$/x) {
      if(!exists $hash->{HELPER}{H00DONE}) {
          $date = strftime "%Y-%m-%d", localtime($t-7200);                                   # Vortag (2 h Differenz reichen aus)
          $ts   = $date." 23:59:59";

          $pvfc = ReadingsNum($name, "Today_Hour24_PVforecast", 0);
          push @$daref, "LastHourPVforecast<>".$pvfc."<>".$ts;

          $pvrl = ReadingsNum($name, "Today_Hour24_PVreal", 0);
          push @$daref, "LastHourPVreal<>".$pvrl."<>".$ts;

          $gcon = ReadingsNum($name, "Today_Hour24_GridConsumption", 0);
          push @$daref, "LastHourGridconsumptionReal<>".$gcon."<>".$ts;

          writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                           # Anlagenkonfiguration sichern

          deleteReadingspec ($hash, "Today_Hour.*_Grid.*");
          deleteReadingspec ($hash, "Today_Hour.*_PV.*");
          deleteReadingspec ($hash, "Today_Hour.*_Bat.*");
          deleteReadingspec ($hash, "powerTrigger_.*");
          deleteReadingspec ($hash, "Today_MaxPVforecast.*");
          deleteReadingspec ($hash, "Today_PVdeviation");

          if(ReadingsVal ($name, "pvCorrectionFactor_Auto", "off") eq "on") {
              for my $n (1..24) {
                  $n = sprintf "%02d", $n;
                  deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*");
              }
          }

          delete $hash->{HELPER}{INITCONTOTAL};
          delete $hash->{HELPER}{INITFEEDTOTAL};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIrequests};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayDoneAPIcalls};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIrequests};
          delete $data{$type}{$name}{solcastapi}{'?All'}{'?All'}{todayRemainingAPIcalls};
          
          delete $data{$type}{$name}{current}{sunriseToday};
          delete $data{$type}{$name}{current}{sunriseTodayTs};

          $data{$type}{$name}{circular}{99}{ydayDvtn} = CircularVal ($hash, 99, 'tdayDvtn', '-');
          delete $data{$type}{$name}{circular}{99}{tdayDvtn};

          delete $data{$type}{$name}{pvhist}{$day};                                         # den (alten) aktuellen Tag aus History löschen
          Log3 ($name, 3, qq{$name - history day "$day" deleted});

          for my $c (keys %{$data{$type}{$name}{consumers}}) {                              # Planungsdaten regulär löschen
              next if(ConsumerVal ($hash, $c, "plandelete", "regular") ne "regular");

              deleteConsumerPlanning ($hash, $c);

              $data{$type}{$name}{consumers}{$c}{minutesOn}       = 0;
              $data{$type}{$name}{consumers}{$c}{numberDayStarts} = 0;
              $data{$type}{$name}{consumers}{$c}{onoff}           = "off";
          }

          writeDataToFile ($hash, "consumers", $csmcache.$name);                            # Cache File Consumer schreiben

          __createAdditionalEvents ($paref);                                                # zusätzliche Events erzeugen - PV Vorhersage bis Ende des kommenden Tages
          __delSolCastObsoleteData ($paref);                                                # Bereinigung obsoleter Daten im solcastapi Hash

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
  my $daref = $paref->{daref};

  for my $idx (sort keys %{$data{$type}{$name}{nexthours}}) {
      my $nhts = NexthoursVal ($hash, $idx, "starttime",  undef);
      my $nhfc = NexthoursVal ($hash, $idx, "pvforecast", undef);
      next if(!defined $nhts || !defined $nhfc);

      my ($dt, $h) = $nhts =~ /([\w-]+)\s(\d{2})/xs;
      push @$daref, "AllPVforecastsToEvent<>".$nhfc." Wh<>".$dt." ".$h.":59:59";
  }

return;
}

#############################################################################
#            solcastapi Hash veraltete Daten löschen
#############################################################################
sub __delSolCastObsoleteData {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $date  = $paref->{date};                                              # aktuelles Datum

  if (!keys %{$data{$type}{$name}{solcastapi}}) {
      return;
  }

  my $refts = timestringToTimestamp ($date.' 00:00:00');                   # Referenztimestring

  for my $idx (sort keys %{$data{$type}{$name}{solcastapi}}) {             # alle Datumschlüssel kleiner aktueller Tag 00:00:00 selektieren
      for my $scd (sort keys %{$data{$type}{$name}{solcastapi}{$idx}}) {
          my $ds = timestringToTimestamp ($scd);
          delete $data{$type}{$name}{solcastapi}{$idx}{$scd} if ($ds && $ds < $refts);
      }
  }

return;
}

################################################################
#    Strahlungsvorhersage Werte von DWD Device
#    ermitteln und übertragen
################################################################
sub _transferDWDRadiationValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                     # Epoche Zeit
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};

  my $raname = ReadingsVal($name, "currentRadiationDev", "");                                  # Radiation Forecast Device
  return if(!$raname || !$defs{$raname});

  my $type        = $paref->{type};
  my $debug       = $paref->{debug};
  my $lang        = $paref->{lang};
  my $err         = checkdwdattr ($name,$raname,\@draattrmust);
  $paref->{state} = $err if($err);

  if($debug =~ /radiationProcess/x) {
      Log3 ($name, 1, qq{$name DEBUG> collect Radiation data - device: $raname =>});
  }
      
  for my $num (0..47) {
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);

      if($fd > 1) {                                                                           # überhängende Werte löschen
          delete $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)};
          next;
      }

      my $fh1      = $fh+1;
      my $fh2      = $fh1 == 24 ? 23 : $fh1;
      my $rad      = ReadingsVal($raname, "fc${fd}_${fh2}_Rad1h", 0);

      my $time_str = "NextHour".sprintf "%02d", $num;
      my $wantts   = $t + (3600 * $num);
      my $wantdt   = (timestampToTimestring ($wantts, $lang))[1];
      my ($hod)    = $wantdt =~ /\s(\d{2}):/xs;
      $hod         = sprintf "%02d", int ($hod)+1;                                            # Stunde des Tages

      if($debug =~ /radiationProcess/x) {
          Log3 ($name, 1, qq{$name DEBUG> date: $wantdt, rad: fc${fd}_${fh2}_Rad1h, Rad1h: $rad});
      }

      my $params = {
          hash  => $hash,
          name  => $name,
          type  => $type,
          rad   => $rad,
          t     => $t,
          hod   => $hod,
          num   => $num,
          fh1   => $fh1,
          fd    => $fd,
          day   => $paref->{day},
          debug => $debug
      };

      my $calcpv = __calcDWDforecast ($params);                                               # Vorhersage gewichtet kalkulieren

      $data{$type}{$name}{nexthours}{$time_str}{pvforecast} = $calcpv;
      $data{$type}{$name}{nexthours}{$time_str}{starttime}  = $wantdt;
      $data{$type}{$name}{nexthours}{$time_str}{hourofday}  = $hod;
      $data{$type}{$name}{nexthours}{$time_str}{today}      = $fd == 0 ? 1 : 0;
      $data{$type}{$name}{nexthours}{$time_str}{Rad1h}      = $rad;                           # nur Info: original Vorhersage Strahlungsdaten

      if($num < 23 && $fh < 24) {                                                             # Ringspeicher PV forecast Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{pvfc} = $calcpv;
      }

      if($fd == 0 && int $calcpv > 0) {                                                       # Vorhersagedaten des aktuellen Tages zum manuellen Vergleich in Reading speichern
          push @$daref, "Today_Hour".sprintf("%02d",$fh1)."_PVforecast<>$calcpv Wh";
      }

      if($fd == 0 && $fh1) {
          $paref->{calcpv}   = $calcpv;
          $paref->{histname} = "pvfc";
          $paref->{nhour}    = sprintf("%02d",$fh1);
          setPVhistory ($paref);
          delete $paref->{histname};
      }
  }

  push @$daref, ".lastupdateForecastValues<>".$t;                                             # Statusreading letzter DWD update

return;
}

##################################################################################################
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
sub __calcDWDforecast {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $rad   = $paref->{rad};               # Nominale Strahlung aus DWD Device
  my $num   = $paref->{num};               # Nexthour
  my $t     = $paref->{t};                 # aktueller Unix Timestamp
  my $hod   = $paref->{hod};               # Stunde des Tages
  my $fh1   = $paref->{fh1};
  my $fd    = $paref->{fd};

  my $stch  = $data{$type}{$name}{strings};                                                           # String Configuration Hash

  my $reld       = $fd == 0 ? "today" : $fd == 1 ? "tomorrow" : "unknown";

  my $clouddamp  = AttrVal($name, "affectCloudfactorDamping", $cldampdef);                            # prozentuale Berücksichtigung des Bewölkungskorrekturfaktors
  my $raindamp   = AttrVal($name, "affectRainfactorDamping",   $rdampdef);                            # prozentuale Berücksichtigung des Regenkorrekturfaktors
  my @strings    = sort keys %{$stch};

  my $rainprob   = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "rainprob", 0);              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
  my $rcf        = 1 - ((($rainprob - $rain_base)/100) * $raindamp/100);                              # Rain Correction Faktor mit Steilheit

  my $cloudcover = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "cloudcover", 0);            # effektive Wolkendecke nächste Stunde X
  my $ccf        = 1 - ((($cloudcover - $cloud_base)/100) * $clouddamp/100);                          # Cloud Correction Faktor mit Steilheit und Fußpunkt

  my $temp       = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "temp", $tempbasedef);       # vorhergesagte Temperatur Stunde X

  my $debug               = $paref->{debug};
  my $range               = calcRange ($cloudcover);                                                  # Range errechnen
  $paref->{range}         = $range;
  my ($hcfound, $hc, $hq) = ___readCorrfAndQuality ($paref);                                          # liest den anzuwendenden Korrekturfaktor
  delete $paref->{range};

  my $pvsum   = 0;
  my $peaksum = 0;
  my ($lh,$sq);

  for my $st (@strings) {                                                                             # für jeden String der Config ..
      my $peak                 = $stch->{$st}{peak};                                                  # String Peak (kWp)

      $paref->{peak}           = $peak;
      $paref->{cloudcover}     = $cloudcover;
      $paref->{temp}           = $temp;

      my ($peakloss, $modtemp) = ___calcPeaklossByTemp ($paref);                                      # Reduktion Peakleistung durch Temperaturkoeffizienten der Module (vorzeichengehaftet)
      $peak                   += $peakloss;

      delete $paref->{peak};
      delete $paref->{cloudcover};
      delete $paref->{temp};

      $peak      *= 1000;                                                                             # kWp in Wp umrechnen
      my $ta      = $stch->{$st}{tilt};                                                               # Neigungswinkel Solarmodule
      my $moddir  = $stch->{$st}{dir};                                                                # Ausrichtung der Solarmodule

      my $af      = $hff{$ta}{$moddir} / 100;                                                         # Flächenfaktor: http://www.ing-büro-junge.de/html/photovoltaik.html

      my $pv      = sprintf "%.1f", ($rad * $af * $kJtokWh * $peak * $prdef * $ccf * $rcf);

      if(AttrVal ($name, 'verbose', 3) == 4) {
          $lh = {                                                                                     # Log-Hash zur Ausgabe
              "moduleDirection"                => $moddir,
              "modulePeakString"               => $peak." W",
              "moduleTiltAngle"                => $ta,
              "Module Temp (calculated)"       => $modtemp." &deg;C",
              "Loss String Peak Power by Temp" => $peakloss." kWP",
              "Area factor"                    => $af,
              "Estimated PV generation (calc)" => $pv." Wh",
          };

          $sq = q{};
          for my $idx (sort keys %{$lh}) {
              $sq .= $idx." => ".$lh->{$idx}."\n";
          }

          if($debug =~ /radiationProcess/x) {
              Log3 ($name, 1, "$name DEBUG> PV forecast calc (raw) for $reld Hour ".sprintf("%02d",$hod)." string $st ->\n$sq");
          }
      }

      $pvsum   += $pv;
      $peaksum += $peak;
  }

  $data{$type}{$name}{current}{allstringspeak} = $peaksum;                                           # temperaturbedingte Korrektur der installierten Peakleistung in W

  $pvsum *= $hc;                                                                                     # Korrekturfaktor anwenden
  $pvsum  = $peaksum if($pvsum > $peaksum);                                                          # Vorhersage nicht größer als die Summe aller PV-Strings Peak

  my $invcapacity = CurrentVal ($hash, "invertercapacity", 0);                                       # Max. Leistung des Invertrs

  if ($invcapacity && $pvsum > $invcapacity) {
      $pvsum = $invcapacity + ($invcapacity * 0.01);                                                 # PV Vorhersage auf WR Kapazität zzgl. 1% begrenzen

      if($debug =~ /radiationProcess/x) {
          Log3 ($name, 1, "$name DEBUG> PV forecast limited to $pvsum Watt due to inverter capacity");
      }
  }

  my $logao         = qq{};
  $paref->{pvsum}   = $pvsum;
  $paref->{peaksum} = $peaksum;
  ($pvsum, $logao)  = ___70percentRule ($paref);

  if(AttrVal ($name, 'verbose', 3) == 4) {
      $lh = {                                                                                        # Log-Hash zur Ausgabe
          "Cloudcover"             => $cloudcover,
          "CloudRange"             => $range,
          "CloudFactorDamping"     => $clouddamp." %",
          "Cloudfactor"            => $ccf,
          "Rainprob"               => $rainprob,
          "Rainfactor"             => $rcf,
          "RainFactorDamping"      => $raindamp." %",
          "Radiation"              => $rad,
          "Factor kJ to kWh"       => $kJtokWh,
          "CloudCorrFoundInStore"  => $hcfound,
          "Forecasted temperature" => $temp." &deg;C",
          "PV correction factor"   => $hc,
          "PV correction quality"  => $hq,
          "PV generation forecast" => $pvsum." Wh ".$logao,
      };

      $sq = q{};
      for my $idx (sort keys %{$lh}) {
          $sq .= $idx." => ".$lh->{$idx}."\n";
      }

      if($debug =~ /radiationProcess/x) {
          Log3 ($name, 1, "$name DEBUG> PV forecast calc for $reld Hour ".sprintf("%02d",$hod)." summary: \n$sq");
      }
  }

return $pvsum;
}

######################################################################
#  Liest den anzuwendenden Korrekturfaktor (Qualität) und
#  speichert die Werte im Nexthours / PVhistory Hash
######################################################################
sub ___readCorrfAndQuality {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $num   = $paref->{num};               # Nexthour
  my $fh1   = $paref->{fh1};
  my $fd    = $paref->{fd};
  my $range = $paref->{range};

  my $uac        = ReadingsVal ($name, "pvCorrectionFactor_Auto", "off");                             # Auto- oder manuelle Korrektur
  my $pvcorr     = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$fh1), 1.00);             # PV Korrekturfaktor (auto oder manuell)
  my $hc         = $pvcorr;                                                                           # Voreinstellung RAW-Korrekturfaktor
  my $hcfound    = "use manual correction factor";
  my $hq         = "m";

  if ($uac eq 'on') {                                                                                 # Autokorrektur soll genutzt werden
      $hcfound   = "yes";                                                                             # Status ob Autokorrekturfaktor im Wertevorrat gefunden wurde
      ($hc, $hq) = CircularAutokorrVal ($hash, sprintf("%02d",$fh1), $range, undef);                  # Korrekturfaktor/KF-Qualität der Stunde des Tages der entsprechenden Bewölkungsrange
      $hq      //= 0;
      if (!defined $hc) {
          $hcfound = "no";
          $hc      = 1;                                                                               # keine Korrektur
          $hq      = 0;
      }
  }

  $hc = sprintf "%.2f", $hc;

  $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{pvcorrf}    = $hc."/".$hq;
  $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{cloudrange} = $range;

  if($fd == 0 && $fh1) {
      $paref->{pvcorrf}  = $hc."/".$hq;
      $paref->{nhour}    = sprintf("%02d",$fh1);
      $paref->{histname} = "pvcorrfactor";
      setPVhistory ($paref);
      delete $paref->{histname};
  }

return ($hcfound, $hc, $hq);
}

################################################################
#  SolCast-API Strahlungsvorhersage Werte aus solcastapi-Hash
#  übertragen und ggf. manipulieren
################################################################
sub _transferSolCastRadiationValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $t     = $paref->{t};                                                                     # Epoche Zeit
  my $chour = $paref->{chour};
  my $date  = $paref->{date};
  my $daref = $paref->{daref};

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

      my $time_str = "NextHour".sprintf "%02d", $num;
      my ($hod)    = $wantdt =~ /\s(\d{2}):/xs;
      $hod         = sprintf "%02d", int ($hod)+1;                                           # Stunde des Tages

      my $params = {
          hash    => $hash,
          name    => $name,
          type    => $type,
          wantdt  => $wantdt,
          hod     => $hod,
          fh1     => $fh1,
          num     => $num,
          fd      => $fd,
          day     => $paref->{day},
          debug   => $paref->{debug}
      };

      my $est = __calcSolCastEstimates ($params);

      $data{$type}{$name}{nexthours}{$time_str}{pvforecast} = $est;
      $data{$type}{$name}{nexthours}{$time_str}{starttime}  = $wantdt;
      $data{$type}{$name}{nexthours}{$time_str}{hourofday}  = $hod;
      $data{$type}{$name}{nexthours}{$time_str}{today}      = $fd == 0 ? 1 : 0;
      $data{$type}{$name}{nexthours}{$time_str}{Rad1h}      = '-';                            # nur Info (nicht bei SolCast API)

      if($num < 23 && $fh < 24) {                                                             # Ringspeicher PV forecast Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
          $data{$type}{$name}{circular}{sprintf "%02d",$fh1}{pvfc} = $est;
      }

      if($fd == 0 && int $est > 0) {                                                          # Vorhersagedaten des aktuellen Tages zum manuellen Vergleich in Reading speichern
          push @$daref, "Today_Hour".sprintf ("%02d",$fh1)."_PVforecast<>$est Wh";
      }

      if($fd == 0 && $fh1) {
          $paref->{calcpv}   = $est;
          $paref->{histname} = 'pvfc';
          $paref->{nhour}    = sprintf "%02d", $fh1;
          setPVhistory ($paref);
          delete $paref->{histname};
      }
  }

  push @$daref, ".lastupdateForecastValues<>".$t;                                             # Statusreading letzter update

return;
}

################################################################
#       SolCast PV estimates berechnen
################################################################
sub __calcSolCastEstimates {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $wantdt  = $paref->{wantdt};
  my $hod     = $paref->{hod};
  my $fd      = $paref->{fd};
  my $num     = $paref->{num};

  my $reld    = $fd == 0 ? "today" : $fd == 1 ? "tomorrow" : "unknown";

  my $clouddamp  = AttrVal($name, "affectCloudfactorDamping", $cldampdef);                            # prozentuale Berücksichtigung des Bewölkungskorrekturfaktors
  my $raindamp   = AttrVal($name, "affectRainfactorDamping",   $rdampdef);                            # prozentuale Berücksichtigung des Regenkorrekturfaktors

  my $rainprob   = NexthoursVal ($hash, "NextHour".sprintf ("%02d", $num), "rainprob", 0);            # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
  my $rcf        = 1 - ((($rainprob - $rain_base)/100) * $raindamp/100);                              # Rain Correction Faktor mit Steilheit

  my $cloudcover = NexthoursVal ($hash, "NextHour".sprintf ("%02d", $num), "cloudcover", 0);          # effektive Wolkendecke nächste Stunde X
  my $ccf        = 1 - ((($cloudcover - $cloud_base)/100) * $clouddamp/100);                          # Cloud Correction Faktor mit Steilheit und Fußpunkt

  my $temp       = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "temp", $tempbasedef);       # vorhergesagte Temperatur Stunde X
  my $debug      = $paref->{debug};

  my ($hcfound, $perc, $hq) = ___readPercAndQuality ($paref);                                         # liest den anzuwendenden Korrekturfaktor

  my ($lh,$sq);
  my $pvsum   = 0;
  my $peaksum = 0;

  for my $string (sort keys %{$data{$type}{$name}{strings}}) {
      my $peak = $data{$type}{$name}{strings}{$string}{peak};                                         # String Peak (kWp)

      $peak *= 1000;

      my $est = SolCastAPIVal ($hash, $string, $wantdt, 'pv_estimate50', 0) * $perc;
      my $pv  = sprintf "%.1f", ($est * $ccf * $rcf);

      if(AttrVal ($name, 'verbose', 3) == 4) {
          $lh = {                                                                                     # Log-Hash zur Ausgabe
              "modulePeakString"                  => $peak." W",
              "Estimated PV generation (raw)"     => $est." Wh",
              "Estimated PV generation (calc)"    => $pv." Wh",
          };

          $sq = q{};
          for my $idx (sort keys %{$lh}) {
              $sq .= $idx." => ".$lh->{$idx}."\n";
          }

          if($debug =~ /radiationProcess/x) {
              Log3 ($name, 1, "$name DEBUG> PV estimate for $reld Hour ".sprintf ("%02d", $hod)." string $string ->\n$sq");
          }

      }

      $pvsum   += $pv;
      $peaksum += $peak;
  }

  $data{$type}{$name}{current}{allstringspeak} = $peaksum;                                           # temperaturbedingte Korrektur der installierten Peakleistung in W

  $pvsum  = $peaksum if($pvsum > $peaksum);                                                          # Vorhersage nicht größer als die Summe aller PV-Strings Peak

  my $invcapacity = CurrentVal ($hash, 'invertercapacity', 0);                                       # Max. Leistung des Invertrs

  if ($invcapacity && $pvsum > $invcapacity) {
      $pvsum = $invcapacity + ($invcapacity * 0.01);                                                 # PV Vorhersage auf WR Kapazität zzgl. 1% begrenzen

      if($debug =~ /radiationProcess/x) {
          Log3 ($name, 1, "$name DEBUG> PV forecast limited to $pvsum Watt due to inverter capacity");
      }
  }

  my $logao         = qq{};
  $paref->{pvsum}   = $pvsum;
  $paref->{peaksum} = $peaksum;
  ($pvsum, $logao)  = ___70percentRule ($paref);

  if(AttrVal ($name, 'verbose', 3) == 4) {
      $lh = {                                                                                        # Log-Hash zur Ausgabe
          "Starttime"                   => $wantdt,
          "Forecasted temperature"      => $temp." &deg;C",
          "Cloudcover"                  => $cloudcover,
          "CloudFactorDamping"          => $clouddamp." %",
          "Cloudfactor"                 => $ccf,
          "Rainprob"                    => $rainprob,
          "Rainfactor"                  => $rcf,
          "RainFactorDamping"           => $raindamp." %",
          "CloudCorrFoundInStore"       => $hcfound,
          "SolCast selected percentile" => $perc,
          "PV correction quality"       => $hq,
          "PV generation forecast"      => $pvsum." Wh ".$logao,
      };

      $sq = q{};
      for my $idx (sort keys %{$lh}) {
          $sq .= $idx." => ".$lh->{$idx}."\n";
      }

      if($debug =~ /radiationProcess/x) {
          Log3 ($name, 1, "$name DEBUG> PV estimate for $reld Hour ".sprintf ("%02d", $hod)." summary: \n$sq");
      }
  }

return $pvsum;
}

######################################################################
#  Liest das anzuwendende Percentil (Qualität) und
#  speichert die Werte im Nexthours / PVhistory Hash
######################################################################
sub ___readPercAndQuality {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $num   = $paref->{num};               # Nexthour
  my $fh1   = $paref->{fh1};
  my $fd    = $paref->{fd};

  my $uac        = ReadingsVal ($name, "pvCorrectionFactor_Auto", "off");                             # Auto- oder manuelle Korrektur
  my $perc       = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$fh1), 1.0);              # Estimate Percentilfaktor
  my $hcfound    = "use manual percentile selection";
  my $hq         = "m";

  if ($uac eq 'on') {                                                                                 # Autokorrektur soll genutzt werden
      $hcfound     = "yes";                                                                           # Status ob Autokorrekturfaktor im Wertevorrat gefunden wurde
      ($perc, $hq) = CircularAutokorrVal ($hash, sprintf("%02d",$fh1), 'percentile', undef);          # Korrekturfaktor/KF-Qualität der Stunde des Tages der entsprechenden Bewölkungsrange
      $hq        //= 0;

      if (!$perc) {
          $hcfound = "no";
          $perc    = 1.0;                                                                              # keine Korrektur
          $hq      = 0;
      }

      $perc = 1.0 if($perc >= 10);
  }

  $perc = sprintf "%.2f", $perc;

  $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{pvcorrf} = $perc."/".$hq;

return ($hcfound, $perc, $hq);
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

  my $modtemp      = $temp + ($tempmodinc * (1 - ($cloudcover/100)));                       # kalkulierte Modultemperatur

  my $peakloss     = sprintf "%.2f", $tempcoeffdef * ($temp - $tempbasedef) * $peak / 100;

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
  my $daref = $paref->{daref};
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

  push @$daref, "Today_MaxPVforecast<>".     $maxest." Wh";
  push @$daref, "Today_MaxPVforecastTime<>". $maxtim;

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
  my $daref = $paref->{daref};

  my $indev  = ReadingsVal($name, "currentInverterDev", "");
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

  push @$daref, "Current_PV<>". $pv." W";
  $data{$type}{$name}{current}{generation} = $pv;                                             # Hilfshash Wert current generation Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251

  push @{$data{$type}{$name}{current}{genslidereg}}, $pv;                                     # Schieberegister PV Erzeugung
  limitArray ($data{$type}{$name}{current}{genslidereg}, $defslidenum);

  my $etuf   = $etunit =~ /^kWh$/xi ? 1000 : 1;
  my $etotal = ReadingsNum ($indev, $edread, 0) * $etuf;                                      # Erzeugung total (Wh)
  
  my $debug = $paref->{debug};
  if($debug =~ /collectData/x) {
      Log3 ($name, 1, "$name DEBUG> collect Inverter data - device: $indev =>");
      Log3 ($name, 1, "$name DEBUG> pv: $pv W, etotal: $etotal Wh");
  }

  my $nhour  = $chour+1;

  my $histetot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "etotal", 0);               # etotal zu Beginn einer Stunde

  my $ethishour;
  if(!$histetot) {                                                                            # etotal der aktuelle Stunde gesetzt ?
      $paref->{etotal}   = $etotal;
      $paref->{nhour}    = sprintf("%02d",$nhour);
      $paref->{histname} = "etotal";
      setPVhistory ($paref);
      delete $paref->{histname};

      my $etot   = CurrentVal ($hash, "etotal", $etotal);
      $ethishour = int ($etotal - $etot);
  }
  else {
      $ethishour = int ($etotal - $histetot);
  }

  $data{$type}{$name}{current}{etotal} = $etotal;                                             # aktuellen etotal des WR speichern

  if($ethishour < 0) {
      $ethishour = 0;
  }

  push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_PVreal<>".$ethishour." Wh";
  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{pvrl} = $ethishour;                   # Ringspeicher PV real Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

  $paref->{ethishour} = $ethishour;
  $paref->{nhour}     = sprintf("%02d",$nhour);
  $paref->{histname}  = "pvrl";
  setPVhistory ($paref);
  delete $paref->{histname};

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
  my $daref = $paref->{daref};
  my $date  = $paref->{date};                                                                   # aktuelles Datum
  
  my $fcname = ReadingsVal($name, "currentForecastDev", "");                                    # Weather Forecast Device
  return if(!$fcname || !$defs{$fcname});

  my $err         = checkdwdattr ($name,$fcname,\@dweattrmust);
  $paref->{state} = $err if($err);

  my $type  = $paref->{type};
  my $debug = $paref->{debug};
  
  if($debug =~ /collectData/x) {
      Log3 ($name, 1, "$name DEBUG> collect Weather data - device: $fcname =>");
  }
  
  my ($time_str);

  my $fc0_SunRise = ReadingsVal($fcname, "fc0_SunRise", "23:59");                               # Sonnenaufgang heute
  my $fc0_SunSet  = ReadingsVal($fcname, "fc0_SunSet",  "00:00");                               # Sonnenuntergang heute
  my $fc1_SunRise = ReadingsVal($fcname, "fc1_SunRise", "23:59");                               # Sonnenaufgang morgen
  my $fc1_SunSet  = ReadingsVal($fcname, "fc1_SunSet",  "00:00");                               # Sonnenuntergang morgen
  
  $data{$type}{$name}{current}{sunriseToday}   = $date.' '.$fc0_SunRise.':00';
  $data{$type}{$name}{current}{sunriseTodayTs} = timestringToTimestamp ($date.' '.$fc0_SunRise.':00');
  
  if($debug =~ /collectData/x) {
      Log3 ($name, 1, "$name DEBUG> sunrise/sunset today: $fc0_SunRise / $fc0_SunSet, sunrise/sunset tomorrow: $fc1_SunRise / $fc1_SunSet");
  }

  push @$daref, "Today_SunRise<>".   $fc0_SunRise;
  push @$daref, "Today_SunSet<>".    $fc0_SunSet;
  push @$daref, "Tomorrow_SunRise<>".$fc1_SunRise;
  push @$daref, "Tomorrow_SunSet<>". $fc1_SunSet;

  my $fc0_SunRise_round = sprintf "%02d", (split ":", $fc0_SunRise)[0];
  my $fc0_SunSet_round  = sprintf "%02d", (split ":", $fc0_SunSet)[0];
  my $fc1_SunRise_round = sprintf "%02d", (split ":", $fc1_SunRise)[0];
  my $fc1_SunSet_round  = sprintf "%02d", (split ":", $fc1_SunSet)[0];

  for my $num (0..46) {
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      last if($fd > 1);

      my $fh1   = $fh+1;
      my $fh2   = $fh1 == 24 ? 23 : $fh1;
      my $wid   = ReadingsNum($fcname, "fc${fd}_${fh2}_ww",  -1);
      my $neff  = ReadingsNum($fcname, "fc${fd}_${fh2}_Neff", 0);                              # Effektive Wolkendecke
      my $r101  = ReadingsNum($fcname, "fc${fd}_${fh2}_R101", 0);                              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
      my $temp  = ReadingsNum($fcname, "fc${fd}_${fh2}_TTT",  0);                              # Außentemperatur

      my $fhstr = sprintf "%02d", $fh;                                                         # hier kann Tag/Nacht-Grenze verstellt werden

      if($fd == 0 && ($fhstr lt $fc0_SunRise_round || $fhstr gt $fc0_SunSet_round)) {          # Zeit vor Sonnenaufgang oder nach Sonnenuntergang heute
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
      }
      elsif ($fd == 1 && ($fhstr lt $fc1_SunRise_round || $fhstr gt $fc1_SunSet_round)) {      # Zeit vor Sonnenaufgang oder nach Sonnenuntergang morgen
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
      }

      my $txt = ReadingsVal($fcname, "fc${fd}_${fh2}_wwd", '');

      if($debug =~ /collectData/x) {
          Log3 ($name, 1, "$name DEBUG> wid: fc${fd}_${fh1}_ww, val: $wid, txt: $txt, cc: $neff, rp: $r101, temp: $temp");
      }

      $time_str                                             = "NextHour".sprintf "%02d", $num;
      $data{$type}{$name}{nexthours}{$time_str}{weatherid}  = $wid;
      $data{$type}{$name}{nexthours}{$time_str}{cloudcover} = $neff;
      $data{$type}{$name}{nexthours}{$time_str}{rainprob}   = $r101;
      $data{$type}{$name}{nexthours}{$time_str}{temp}       = $temp;

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
#    Werte Meter Device ermitteln und übertragen
################################################################
sub _transferMeterValues {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};

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

  if ($gf eq "-gcon") {                                                                       # Spezialfall gfeedin bei neg. gcon
      $params = {
          dev  => $medev,
          rdg  => $gc,
          rdgf => $gcuf
      };

      ($gco,$gfin) = substSpecialCases ($params);
  }

  push @$daref, "Current_GridConsumption<>".(int $gco)." W";
  $data{$type}{$name}{current}{gridconsumption} = int $gco;                                   # Hilfshash Wert current grid consumption Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251

  push @$daref, "Current_GridFeedIn<>".(int $gfin)." W";
  $data{$type}{$name}{current}{gridfeedin} = int $gfin;                                       # Hilfshash Wert current grid Feed in

  my $ctuf    = $ctunit =~ /^kWh$/xi ? 1000 : 1;
  my $gctotal = ReadingsNum ($medev, $gt, 0) * $ctuf;                                         # Bezug total (Wh)

  my $ftuf    = $ftunit =~ /^kWh$/xi ? 1000 : 1;
  my $fitotal = ReadingsNum ($medev, $ft, 0) * $ftuf;                                         # Einspeisung total (Wh)
  
  my $debug = $paref->{debug};
  if($debug =~ /collectData/x) {
      Log3 ($name, 1, "$name DEBUG> collect Meter data - device: $medev =>");
      Log3 ($name, 1, "$name DEBUG> gcon: $gco W, gfeedin: $gfin W, contotal: $gctotal Wh, feedtotal: $fitotal Wh");
  }

  my $gcdaypast = 0;
  my $gfdaypast = 0;

  for my $hour (0..int $chour) {                                                                     # alle bisherigen Erzeugungen des Tages summieren
      $gcdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridConsumption", 0);
      $gfdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridFeedIn",      0);
  }

  my $docon = 0;
  if ($gcdaypast == 0) {                                                                             # Management der Stundenberechnung auf Basis Totalwerte GridConsumtion
      if (defined $hash->{HELPER}{INITCONTOTAL}) {
          $docon = 1;
      }
      else {
          $hash->{HELPER}{INITCONTOTAL} = $gctotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITCONTOTAL}) {
      $hash->{HELPER}{INITCONTOTAL} = $gctotal-$gcdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  }
  else {
      $docon = 1;
  }

  if ($docon) {
      my $gctotthishour = int ($gctotal - ($gcdaypast + $hash->{HELPER}{INITCONTOTAL}));

      if($gctotthishour < 0) {
          $gctotthishour = 0;
      }

      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridConsumption<>".$gctotthishour." Wh";
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gcons} = $gctotthishour;                  # Hilfshash Wert Bezug (Wh) Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

      $paref->{gctotthishour} = $gctotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "cons";
      setPVhistory ($paref);
      delete $paref->{histname};
  }

  my $dofeed = 0;
  if ($gfdaypast == 0) {                                                                              # Management der Stundenberechnung auf Basis Totalwerte GridFeedIn
      if (defined $hash->{HELPER}{INITFEEDTOTAL}) {
          $dofeed = 1;
      }
      else {
          $hash->{HELPER}{INITFEEDTOTAL} = $fitotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITFEEDTOTAL}) {
      $hash->{HELPER}{INITFEEDTOTAL} = $fitotal-$gfdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridFeedIn", 0);
  }
  else {
      $dofeed = 1;
  }

  if ($dofeed) {
      my $gftotthishour = int ($fitotal - ($gfdaypast + $hash->{HELPER}{INITFEEDTOTAL}));

      if($gftotthishour < 0) {
          $gftotthishour = 0;
      }

      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridFeedIn<>".$gftotthishour." Wh";
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
  my $daref   = $paref->{daref};

  my $nhour       = $chour+1;
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

          push @$daref, "consumer${c}_currentPower<>". $pcurr." W";
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
              $pcurr       = sprintf("%.6f", $delta / (3600 * $timespan)) if($delta);              # Einheitenformel beachten !!: W = Wh / (3600 * s)

              $data{$type}{$name}{consumers}{$c}{old_etotal}   = $etot;
              $data{$type}{$name}{consumers}{$c}{old_etottime} = $t;

              push @$daref, "consumer${c}_currentPower<>". $pcurr." W";
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
      if(isConsumerLogOn ($hash, $c, $pcurr)) {                                               # Verbraucher ist logisch "an"
            if(ConsumerVal ($hash, $c, "onoff", "off") eq "off") {
                $data{$type}{$name}{consumers}{$c}{startTime}       = $t;
                $data{$type}{$name}{consumers}{$c}{onoff}           = "on";
                my $stimes                                          = ConsumerVal ($hash, $c, "numberDayStarts", 0);     # Anzahl der On-Schaltungen am Tag
                $data{$type}{$name}{consumers}{$c}{numberDayStarts} = $stimes+1;
                $data{$type}{$name}{consumers}{$c}{lastMinutesOn}   = ConsumerVal ($hash, $c, "minutesOn", 0);
            }

            $starthour = strftime "%H", localtime(ConsumerVal ($hash, $c, "startTime", $t));

            if($chour eq $starthour) {
                my $runtime                                   = (($t - ConsumerVal ($hash, $c, "startTime", $t)) / 60);                  # in Minuten ! (gettimeofday sind ms !)
                $data{$type}{$name}{consumers}{$c}{minutesOn} = ConsumerVal ($hash, $c, "lastMinutesOn", 0) + $runtime;
            }
            else {                                                                                                               # neue Stunde hat begonnen
                if(ConsumerVal ($hash, $c, "onoff", "off") eq "on") {
                    $data{$type}{$name}{consumers}{$c}{startTime}     = timestringToTimestamp ($date." ".sprintf("%02d",$chour).":00:00");
                    $data{$type}{$name}{consumers}{$c}{minutesOn}     = ($t - ConsumerVal ($hash, $c, "startTime", $t)) / 60;                # in Minuten ! (gettimeofday sind ms !)
                    $data{$type}{$name}{consumers}{$c}{lastMinutesOn} = 0;
                }
            }
      }
      else {                                                                                  # Verbraucher soll nicht aktiv sein
          $data{$type}{$name}{consumers}{$c}{onoff} = "off";
          $starthour                                = strftime "%H", localtime(ConsumerVal ($hash, $c, "startTime", $t));

          if($chour ne $starthour) {
              $data{$type}{$name}{consumers}{$c}{minutesOn} = 0;
              delete $data{$type}{$name}{consumers}{$c}{startTime};
          }
      }

      $paref->{val}      = ConsumerVal ($hash, $c, "numberDayStarts", 0);                     # Anzahl Tageszyklen des Verbrauchers speichern
      $paref->{histname} = "cyclescsm${c}";
      setPVhistory ($paref);
      delete $paref->{histname};

      $paref->{val}      = ceil ConsumerVal ($hash, $c, "minutesOn", 0);                      # Verbrauchsminuten akt. Stunde des Consumers
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
          if($consumerco) {
              $data{$type}{$name}{consumers}{$c}{avgenergy} = ceil ($consumerco/$runhours);                       # Durchschnittsverbrauch pro Stunde in Wh
          }
          else {
              delete $data{$type}{$name}{consumers}{$c}{avgenergy};
          }

          $data{$type}{$name}{consumers}{$c}{avgruntime} = (ceil($runhours/$dnum)) * 60;                          # Durchschnittslaufzeit am Tag in Minuten
      }

      $paref->{consumer} = $c;

      __calcEnergyPieces   ($paref);                                                                              # Energieverbrauch auf einzelne Stunden für Planungsgrundlage aufteilen
      __planSwitchTimes    ($paref);                                                                              # Consumer Switch Zeiten planen
      __setTimeframeState  ($paref);                                                                              # Timeframe Status ermitteln
      __setConsRcmdState   ($paref);                                                                              # Consumption Recommended Status setzen
      __switchConsumer     ($paref);                                                                              # Consumer schalten
      __remainConsumerTime ($paref);                                                                              # Restlaufzeit Verbraucher ermitteln

      ## Consumer Schaltstatus und Schaltzeit für Readings ermitteln
      ################################################################
      my $costate = isConsumerPhysOn  ($hash, $c) ? "on"  :
                    isConsumerPhysOff ($hash, $c) ? "off" :
                    "unknown";

      $data{$type}{$name}{consumers}{$c}{state} = $costate;

      my ($pstate,$starttime,$stoptime)         = __getPlanningStateAndTimes ($paref);

      push @$daref, "consumer${c}<>"              ."name='$alias' state='$costate' planningstate='$pstate' ";     # Consumer Infos
      push @$daref, "consumer${c}_planned_start<>"."$starttime" if($starttime);                                   # Consumer Start geplant
      push @$daref, "consumer${c}_planned_stop<>". "$stoptime"  if($stoptime);                                    # Consumer Stop geplant
  }

  delete $paref->{consumer};

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

      for my $h (1..$epiecHCounts) {
          delete $data{$type}{$name}{consumers}{$c}{"epiecHist_".$h};
          delete $data{$type}{$name}{consumers}{$c}{"epiecHist_".$h."_hours"};
      }
  }

  delete $data{$type}{$name}{consumers}{$c}{epieces};

  my $cotype  = ConsumerVal ($hash, $c, "type",    $defctype  );
  my $mintime = ConsumerVal ($hash, $c, "mintime", $defmintime);
  my $hours   = ceil ($mintime / 60);                                                          # Laufzeit in h

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

###################################################################
#  Verbraucherspezifische Energiestück Ermittlung
#
#  epiecHCounts = x gibt an wie viele Zyklen betrachtet werden
#                      sollen
#  epiecHist => x ist der Index des Speicherbereichs der aktuell
#               benutzt wird.
#
#  epiecHist_x => 1=x 2=x 3=x 4=x epieces eines Index
#  epiecHist_x_hours => x Stunden des Durchlauf bzw. wie viele
#                         Einträge epiecHist_x hat
#  epiecAVG => 1=x 2=x und epiecAVG_hours => x enthalten die
#              durchschnittlichen Werte der in epiecHCounts
#              vorgegebenen Durchläufe.
#
###################################################################
sub ___csmSpecificEpieces {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $etot  = $paref->{etot};
  my $t     = $paref->{t};

  if(ConsumerVal ($hash, $c, "onoff", "off") eq "on") {                                                 # Status "Aus" verzögern um Pausen im Waschprogramm zu überbrücken
      $data{$type}{$name}{consumers}{$c}{lastOnTime} = $t;
  }

  my $offTime = defined $data{$type}{$name}{consumers}{$c}{lastOnTime} ?
                $t - $data{$type}{$name}{consumers}{$c}{lastOnTime}    :
                99;

  if($offTime < 300) {                                                                                  # erst nach 60s ist das Gerät aus
      my $epiecHist       = "";
      my $epiecHist_hours = "";

      if(ConsumerVal ($hash, $c, "epiecHour", -1) < 0) {                                                # neue Aufzeichnung
          $data{$type}{$name}{consumers}{$c}{epiecStartTime} = $t;
          $data{$type}{$name}{consumers}{$c}{epiecHist}     += 1;
          $data{$type}{$name}{consumers}{$c}{epiecHist}      = 1 if(ConsumerVal ($hash, $c, "epiecHist", 0) > $epiecHCounts);

          $epiecHist = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0);
          delete $data{$type}{$name}{consumers}{$c}{$epiecHist};                                        # Löschen, wird neu erfasst
      }

      $epiecHist       = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0);                          # Namen fürs Speichern
      $epiecHist_hours = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0)."_hours";
      my $epiecHour    = floor (($t - ConsumerVal ($hash, $c, "epiecStartTime", $t)) / 60 / 60) + 1;    # aktuelle Betriebsstunde ermitteln, ( / 60min) mögliche wäre auch durch 15min        /Minute /Stunde

      if(ConsumerVal ($hash, $c, "epiecHour", 0) != $epiecHour) {                                       # Stundenwechsel? Differenz von etot noch auf die vorherige Stunde anrechnen
          my $epiecHour_last = $epiecHour - 1;

          $data{$type}{$name}{consumers}{$c}{$epiecHist}{$epiecHour_last} = sprintf '%.2f', ($etot - ConsumerVal ($hash, $c, "epiecStartEtotal", 0)) if($epiecHour > 1);
          $data{$type}{$name}{consumers}{$c}{epiecStartEtotal}            = $etot;
      }

      my $ediff                                                  = $etot - ConsumerVal ($hash, $c, "epiecStartEtotal", 0);
      $data{$type}{$name}{consumers}{$c}{$epiecHist}{$epiecHour} = sprintf '%.2f', $ediff;
      $data{$type}{$name}{consumers}{$c}{epiecHour}              = $epiecHour;
      $data{$type}{$name}{consumers}{$c}{$epiecHist_hours}       = $ediff ? $epiecHour : $epiecHour - 1; # wenn mehr als 1 Wh verbraucht wird die Stunde gezählt
  }
  else {                                                                                                 # Durchschnitt ermitteln
      if(ConsumerVal ($hash, $c, "epiecHour", 0) > 0) {                                                  # Durchschnittliche Stunden ermitteln
          my $hours = 0;

          for my $h (1..$epiecHCounts) {                                                                 # durchschnittliche Stunden über alle epieces ermitteln und aufrunden
              $hours += ConsumerVal ($hash, $c, "epiecHist_".$h."_hours", 0);
          }

          $hours                                             = ceil ($hours / $epiecHCounts);
          $data{$type}{$name}{consumers}{$c}{epiecAVG_hours} = $hours;

          delete $data{$type}{$name}{consumers}{$c}{epiecAVG};                                           # Durchschnitt für epics ermitteln

          for my $hour (1..$hours) {                                                                     # jede Stunde durchlaufen
              my $hoursE = 1;

              for my $h (1..$epiecHCounts) {                                                             # jedes epiec durchlaufen
                  my $epiecHist = "epiecHist_".$h;

                  if(defined $data{$type}{$name}{consumers}{$c}{$epiecHist}{$hour}) {
                      if($data{$type}{$name}{consumers}{$c}{$epiecHist}{$hour} > 5) {
                          $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} += $data{$type}{$name}{consumers}{$c}{$epiecHist}{$hour};
                          $hoursE += 1;
                      }
                  }

              }

              my $eavg = defined $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} ?
                         $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour}         :
                         0;

              $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} = sprintf('%.2f', $eavg / $hoursE);    # Durchschnitt ermittelt und in epiecAVG schreiben
          }
      }

      $data{$type}{$name}{consumers}{$c}{epiecHour} = -1;                                                # epiecHour auf initialwert setzen für nächsten durchlauf
  }

return;
}

###################################################################
#    Consumer Schaltzeiten planen
#
#    ToDo:  bei mode=can ->
#           die $epieceX aller bereits geplanten
#           Consumer der entsprechenden Stunde XX von $surplus
#           abziehen weil schon "verplant"
#
###################################################################
sub __planSwitchTimes {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $debug = $paref->{debug};
  
  #return if(ConsumerVal ($hash, $c, "planstate", undef));  
  
  my $dnp = ___noPlanRelease ($paref);
  if ($dnp) {
      if($debug =~ /consumerPlanning/x) {
          Log3 ($name, 4, qq{$name DEBUG> Planning consumer "$c" - name: }.ConsumerVal ($hash, $c, 'name', ''));
          Log3 ($name, 4, qq{$name DEBUG> Planning consumer "$c" - $dnp});
      }
      return;
  }
  
  if($debug =~ /consumerPlanning/x) {
      Log3 ($name, 1, qq{$name DEBUG> Planning consumer "$c" - name: }.ConsumerVal ($hash, $c, 'name', ''));
  }

  my $type   = $paref->{type};
  my $lang   = $paref->{lang};
  my $nh     = $data{$type}{$name}{nexthours};
  my $maxkey = (scalar keys %{$data{$type}{$name}{nexthours}}) - 1;
  my $cicfip = AttrVal ($name, 'affectConsForecastInPlanning', 0);                         # soll Consumption Vorhersage in die Überschußermittlung eingehen ?
  
  if($debug =~ /consumerPlanning/x) {
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - Consider consumption forecast in consumer planning: }.($cicfip ? 'yes' : 'no'));
  }
  
  my %max;
  my %mtimes;

  ## max. Überschuß ermitteln
  #############################
  for my $idx (sort keys %{$nh}) {
      my $pvfc    = NexthoursVal ($hash, $idx, "pvforecast", 0 );
      my $confcex = NexthoursVal ($hash, $idx, "confcEx",    0 );                          # prognostizierter Verbrauch ohne registrierte Consumer

      my $spexp   = $pvfc - ($cicfip ? $confcex : 0);                                      # prognostizierter Energieüberschuß (kann negativ sein)

      my ($hour)              = $idx =~ /NextHour(\d+)/xs;
      $max{$spexp}{starttime} = NexthoursVal ($hash, $idx, "starttime", "");
      $max{$spexp}{today}     = NexthoursVal ($hash, $idx, "today",      0);
      $max{$spexp}{nexthour}  = int ($hour);
  }

  my $order = 1;
  for my $k (reverse sort{$a<=>$b} keys %max) {
      $max{$order}{spexp}     = $k;
      $max{$order}{starttime} = $max{$k}{starttime};
      $max{$order}{nexthour}  = $max{$k}{nexthour};
      $max{$order}{today}     = $max{$k}{today};

      my $ts                  = timestringToTimestamp ($max{$k}{starttime});
      $mtimes{$ts}{spexp}     = $k;
      $mtimes{$ts}{starttime} = $max{$k}{starttime};
      $mtimes{$ts}{nexthour}  = $max{$k}{nexthour};
      $mtimes{$ts}{today}     = $max{$k}{today};

      delete $max{$k};

      $order++;
  }

  my $epiece1 = (~0 >> 1);
  my $epieces = ConsumerVal ($hash, $c, "epieces", "");

  if(ref $epieces eq "HASH") {
      $epiece1 = $data{$type}{$name}{consumers}{$c}{epieces}{1};
  }
  else {
      return;
  }

  if($debug =~ /consumerPlanning/x) {
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - epiece1: $epiece1});
  }

  my $mode     = ConsumerVal ($hash, $c, "mode",          "can");
  my $calias   = ConsumerVal ($hash, $c, "alias",            "");
  my $mintime  = ConsumerVal ($hash, $c, "mintime", $defmintime);
  my $stopdiff = ceil($mintime / 60) * 3600;

  $paref->{maxref}   = \%max;
  $paref->{mintime}  = $mintime;
  $paref->{stopdiff} = $stopdiff;

  if($mode eq "can") {                                                                                 # Verbraucher kann geplant werden
      if($debug =~ /consumerPlanning/x) {                                                            
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - mode: $mode, mintime: $mintime, relevant method: surplus});
          
          for my $m (sort{$a<=>$b} keys %mtimes) {
              Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - surplus expected: $mtimes{$m}{spexp}, }.
                              qq{starttime: }.$mtimes{$m}{starttime}.", ".
                              qq{nexthour: $mtimes{$m}{nexthour}, today: $mtimes{$m}{today}});
          }
      }

      for my $ts (sort{$a<=>$b} keys %mtimes) {
          if($mtimes{$ts}{spexp} >= $epiece1) {                                                        # die früheste Startzeit sofern Überschuß größer als Bedarf
              my $starttime       = $mtimes{$ts}{starttime};
              $paref->{starttime} = $starttime;
              $starttime          = ___switchonTimelimits ($paref);

              delete $paref->{starttime};

              my $startts       = timestringToTimestamp ($starttime);                                  # Unix Timestamp für geplanten Switch on

              $paref->{ps}      = "planned:";
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
              $paref->{ps} = "no planning: the max expected surplus is less $epiece1";

              ___setConsumerPlanningState ($paref);

              delete $paref->{ps};
          }
      }
  }
  else {                                                                                               # Verbraucher _muß_ geplant werden
      if($debug) {                                                                                 
          Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - mode: $mode, mintime: $mintime, relevant method: max});
          
          for my $o (sort{$a<=>$b} keys %max) {
              Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - surplus: $max{$o}{spexp}, }.
                              qq{starttime: }.$max{$o}{starttime}.", ".
                              qq{nexthour: $max{$o}{nexthour}, today: $max{$o}{today}});
          }
      }

      for my $o (sort{$a<=>$b} keys %max) {
          next if(!$max{$o}{today});                                                                   # der max-Wert ist _nicht_ heute
          $paref->{elem} = $o;
          ___planMust ($paref);
          last;
      }

      if(!ConsumerVal ($hash, $c, "planstate", undef)) {                                               # es konnte keine Planung mit max für den aktuellen Tag erstellt werden -> Zwangsplanung mit ersten Wert
              my $p = (sort{$a<=>$b} keys %max)[0];
              $paref->{elem} = $p;
              ___planMust ($paref);
      }
  }

  my $planstate = ConsumerVal ($hash, $c, "planstate", "");

  if($planstate) {
      Log3 ($name, 3, qq{$name - Consumer "$calias" $planstate});
  }

  writeDataToFile ($hash, "consumers", $csmcache.$name);                                               # Cache File Consumer schreiben

  ___setPlanningDeleteMeth ($paref);

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
  
  if(ConsumerVal ($hash, $c, "planstate", undef)) {                                        # Verbraucher ist schon geplant/gestartet/fertig
      $dnp = qq{consumer is already planned};
  }

  if (isSolCastUsed ($hash)) {
      if (!SolCastAPIVal ($hash, '?All', '?All', 'todayDoneAPIcalls', 0)) {                # Planung erst nach dem ersten API Abruf freigeben
           $dnp = qq{do not plan because off "todayDoneAPIcalls" not set};
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
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $c       = $paref->{consumer};
  my $ps      = $paref->{ps};                                                # Planstatus
  my $startts = $paref->{startts};                                           # Unix Timestamp für geplanten Switch on
  my $stopts  = $paref->{stopts};                                            # Unix Timestamp für geplanten Switch off
  my $lang    = $paref->{lang};
  
  my ($starttime,$stoptime);

  if ($startts) {
      (undef,undef,undef,$starttime)                   = timestampToTimestring ($startts, $lang);
      $data{$type}{$name}{consumers}{$c}{planswitchon} = $startts;
  }

  if ($stopts) {
      (undef,undef,undef,$stoptime)                     = timestampToTimestring ($stopts, $lang);
      $data{$type}{$name}{consumers}{$c}{planswitchoff} = $stopts;
  }

  $ps .= " "              if ($starttime || $stoptime);
  $ps .= $starttime       if ($starttime);
  $ps .= $stoptime        if (!$starttime && $stoptime);
  $ps .= " - ".$stoptime  if ($starttime  && $stoptime);

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

  my $maxts                         = timestringToTimestamp ($maxref->{$elem}{starttime});           # Unix Timestamp des max. Überschusses heute
  my $half                          = floor ($mintime / 2 / 60);                                     # die halbe Gesamtlaufzeit in h als Vorlaufzeit einkalkulieren
  my $startts                       = $maxts - ($half * 3600);
  my (undef,undef,undef,$starttime) = timestampToTimestring ($startts, $lang);

  $paref->{starttime}               = $starttime;
  $starttime                        = ___switchonTimelimits ($paref);
  delete $paref->{starttime};

  $startts                          = timestringToTimestamp ($starttime);
  my $stopts                        = $startts + $stopdiff;

  $paref->{ps}      = "planned:";
  $paref->{startts} = $startts;                                                                       # Unix Timestamp für geplanten Switch on
  $paref->{stopts}  = $stopts;                                                                        # Unix Timestamp für geplanten Switch off

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
################################################################
sub ___switchonTimelimits {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $c         = $paref->{consumer};
  my $starttime = $paref->{starttime};

  my $origtime    = $starttime;
  my $notbefore   = ConsumerVal ($hash, $c, "notbefore", 0);
  my $notafter    = ConsumerVal ($hash, $c, "notafter",  0);
  my ($starthour) = $starttime =~ /\s(\d{2}):/xs;

  my $change = q{};

  if($notbefore && int $starthour < int $notbefore) {
      $starthour = $notbefore;
      $change    = "notbefore";
  }

  if($notafter && int $starthour > int $notafter) {
      $starthour = $notafter;
      $change    = "notafter";
  }

  $starthour = sprintf("%02d", $starthour);
  $starttime =~ s/\s(\d{2}):/ $starthour:/x;

  if($change) {
      my $cname = ConsumerVal ($hash, $c, "name", "");
      Log3 ($name, 3, qq{$name - Planned starttime "$cname" changed from "$origtime" to "$starttime" due to $change condition});
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
  my $c     = $paref->{consumer};                                                         # aktueller Unixtimestamp
  my $daref = $paref->{daref};

  my $surplus  = CurrentVal  ($hash, "surplus",                    0);                    # aktueller Energieüberschuß
  my $nompower = ConsumerVal ($hash, $c, "power",                  0);                    # Consumer nominale Leistungsaufnahme (W)
  my $ccr      = AttrVal     ($name, 'ctrlConsRecommendReadings', '');                    # Liste der Consumer für die ConsumptionRecommended-Readings erstellt werden sollen
  my $rescons  = isConsumerPhysOn($hash, $c) ? 0 : $nompower;                             # resultierender Verbauch nach Einschaltung Consumer

  if (!$nompower || $surplus - $rescons > 0) {
      $data{$type}{$name}{consumers}{$c}{isConsumptionRecommended} = 1;                   # Einschalten des Consumers günstig
  }
  else {
      $data{$type}{$name}{consumers}{$c}{isConsumptionRecommended} = 0;
  }

  if ($ccr =~ /$c/xs) {
      push @$daref, "consumer${c}_ConsumptionRecommended<>". ConsumerVal ($hash, $c, 'isConsumptionRecommended', 0);
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

  my $pstate  = ConsumerVal ($hash, $c, "planstate",        "");
  my $startts = ConsumerVal ($hash, $c, "planswitchon",  undef);                                  # geplante Unix Startzeit
  my $oncom   = ConsumerVal ($hash, $c, "oncom",            "");                                  # Set Command für "on"
  my $auto    = ConsumerVal ($hash, $c, "auto",              1);
  my $cname   = ConsumerVal ($hash, $c, "name",             "");                                  # Consumer Device Name
  my $calias  = ConsumerVal ($hash, $c, "alias",            "");                                  # Consumer Device Alias

  my ($swoncond,$swoffcond,$info,$err);
  ($swoncond,$info,$err)  = isAddSwitchOnCond  ($hash, $c);                                       # zusätzliche Switch on Bedingung
  Log3 ($name, 1, "$name - $err") if($err);

  ($swoffcond,$info,$err) = isAddSwitchOffCond ($hash, $c);                                       # zusätzliche Switch off Bedingung
  Log3 ($name, 1, "$name - $err") if($err);

  if ($debug =~ /consumerSwitching/x) {                                                           # nur für Debugging
      my $cons   = CurrentVal  ($hash, 'consumption',  0);
      my $nompow = ConsumerVal ($hash, $c, 'power', '-');
      my $sp     = CurrentVal  ($hash, 'surplus',  0);

      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - general switching parameters => }.
                      qq{auto mode: $auto, current Consumption: $cons W, nompower: $nompow, surplus: $sp W, }.
                      qq{planning state: $pstate, start timestamp: }.($startts ? $startts : "undef")
           );
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - current Context is switching "on" => }.
                      qq{swoncond: $swoncond, on-command: $oncom }
           );
  }

  if ($auto && $oncom && $swoncond && !$swoffcond &&                                              # kein Einschalten wenn zusätzliche Switch off Bedingung zutrifft
      simplifyCstate($pstate) =~ /planned|priority|starting/xs &&
      isInTimeframe ($hash, $c)) {                                                                # Verbraucher Start ist geplant && Startzeit überschritten
      my $mode    = ConsumerVal ($hash, $c, "mode", $defcmode);                                   # Consumer Planungsmode
      my $enable  = ___enableSwitchByBatPrioCharge ($paref);                                      # Vorrangladung Batterie ?

      if($debug =~ /consumerSwitching/x) {
          Log3 ($name, 1, qq{$name DEBUG> Consumer switch enabled by battery: $enable});
      }

      if ($mode eq "can" && !$enable) {                                                           # Batterieladung - keine Verbraucher "Einschalten" Freigabe
          $paref->{ps} = "priority charging battery";

        ___setConsumerPlanningState ($paref);

        delete $paref->{ps};
      }
      elsif ($mode eq "must" || isConsRcmd($hash, $c)) {                                          # "Muss"-Planung oder Überschuß > Leistungsaufnahme
          CommandSet(undef,"$cname $oncom");
          my $stopdiff = ceil(ConsumerVal ($hash, $c, "mintime", $defmintime) / 60) * 3600;

          $paref->{ps} = "switching on:";

          ___setConsumerPlanningState ($paref);

          delete $paref->{ps};

          $state = qq{switching Consumer '$calias' to '$oncom'};

          writeDataToFile ($hash, "consumers", $csmcache.$name);                                  # Cache File Consumer schreiben

          Log3 ($name, 2, "$name - $state (Automatic = $auto)");
      }
  }
  elsif (((isInterruptable($hash, $c) == 1 && isConsRcmd ($hash, $c)) ||                          # unterbrochenen Consumer fortsetzen
          (isInterruptable($hash, $c) == 3 && isConsRcmd ($hash, $c)))    &&
         isInTimeframe    ($hash, $c)                                     &&
         simplifyCstate   ($pstate) =~ /interrupted|interrupting/xs       &&
         $auto && $oncom) {

      CommandSet(undef,"$cname $oncom");

      $paref->{ps} = "continuing:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      my $caution = isInterruptable($hash, $c) == 3 ? 'interrupt condition no longer present' : 'existing surplus';
      $state      = qq{switching Consumer '$calias' to '$oncom', caution: $caution};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                     # Cache File Consumer schreiben

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
  my $cname   = ConsumerVal ($hash, $c, "name",             "");                                  # Consumer Device Name
  my $calias  = ConsumerVal ($hash, $c, "alias",            "");                                  # Consumer Device Alias
  my $mode    = ConsumerVal ($hash, $c, "mode",      $defcmode);                                  # Consumer Planungsmode
  my $hyst    = ConsumerVal ($hash, $c, "hysteresis", $defhyst);                                  # Hysterese

  my $offcom                 = ConsumerVal        ($hash, $c, "offcom", "");                      # Set Command für "off"
  my ($swoffcond,$info,$err) = isAddSwitchOffCond ($hash, $c);                                    # zusätzliche Switch off Bedingung
  my $caution;

  Log3 ($name, 1, "$name - $err") if($err);

  if($debug =~ /consumerSwitching/x) {                                                            # nur für Debugging
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - current Context is switching "off" => }.
                      qq{swoffcond: $swoffcond, off-command: $offcom }
           );
  }

  if(($swoffcond || ($stopts && $t >= $stopts)) &&
     ($auto && $offcom && simplifyCstate($pstate) =~ /started|starting|stopping|interrupt|continu/xs)) {
      CommandSet(undef,"$cname $offcom");

      $paref->{ps} = "switching off:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      $caution = $swoffcond ? "switch-off condition (key swoffcond) is true" : "planned switch-off time reached/exceeded";
      $state   = qq{switching Consumer '$calias' to '$offcom', caution: $caution};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                                     # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state (Automatic = $auto)");
  }
  elsif (((isInterruptable($hash, $c, $hyst) && !isConsRcmd ($hash, $c)) || isInterruptable($hash, $c, $hyst) == 2) &&       # Consumer unterbrechen
         isInTimeframe    ($hash, $c)        && simplifyCstate ($pstate) =~ /started|continued|interrupting/xs      &&
         $auto && $offcom) {

      CommandSet(undef,"$cname $offcom");

      $paref->{ps} = "interrupting:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      $caution = isInterruptable($hash, $c, $hyst) == 2 ? 'interrupt condition' : 'surplus shortage';
      $state   = qq{switching Consumer '$calias' to '$offcom', caution: $caution};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                               # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state");
  }

return $state;
}

################################################################
#     Consumer aktuelle Schaltzustände ermitteln & setzen
#     Consumer "on" setzen wenn physisch ein und alter Status
#     "starting"
#     Consumer "off" setzen wenn physisch aus und alter Status
#     "stopping"
################################################################
sub ___setConsumerSwitchingState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};
  my $state = $paref->{state};

  my $pstate = simplifyCstate (ConsumerVal ($hash, $c, "planstate", ""));
  my $calias = ConsumerVal    ($hash, $c, "alias", "");                                      # Consumer Device Alias
  my $auto   = ConsumerVal    ($hash, $c, "auto",   1);

  if ($pstate eq 'starting' && isConsumerPhysOn ($hash, $c)) {
      my $stopdiff      = ceil(ConsumerVal ($hash, $c, "mintime", $defmintime) / 60) * 3600;

      $paref->{ps}      = "switched on:";
      $paref->{startts} = $t;
      $paref->{stopts}  = $t + $stopdiff;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{startts};
      delete $paref->{stopts};

      $state = qq{Consumer '$calias' switched on};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                  # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state");
  }
  elsif ($pstate eq 'stopping' && isConsumerPhysOff ($hash, $c)) {
      $paref->{ps}     = "switched off:";
      $paref->{stopts} = $t;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{stopts};

      $state = qq{Consumer '$calias' switched off};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state");
  }
  elsif ($pstate eq 'continuing' && isConsumerPhysOn ($hash, $c)) {
      $paref->{ps} = "continued:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      $state = qq{Consumer '$calias' switched on (continued)};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben

      Log3 ($name, 2, "$name - $state");
  }
  elsif ($pstate eq 'interrupting' && isConsumerPhysOff ($hash, $c)) {
      $paref->{ps} = "interrupted:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};

      $state = qq{Consumer '$calias' switched off (interrupted)};

      writeDataToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben

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
  my ($badev) = useBattery ($name);

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

  my $pstate  = ConsumerVal    ($hash, $c, "planstate", "");
  $pstate     = simplifyCstate ($pstate);

  my $startts = ConsumerVal ($hash, $c, "planswitchon",  "");
  my $stopts  = ConsumerVal ($hash, $c, "planswitchoff", "");

  my $starttime = '';
  my $stoptime  = '';
  $starttime    = (timestampToTimestring ($startts, $lang))[0] if($startts);
  $stoptime     = (timestampToTimestring ($stopts, $lang))[0]  if($stopts);

return ($pstate, $starttime, $stoptime);
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
  my $daref = $paref->{daref};

  my ($badev,$a,$h) = useBattery ($name);
  return if(!$badev);

  my $type = $paref->{type};

  my ($pin,$piunit)    = split ":", $h->{pin};                                                # Readingname/Unit für aktuelle Batterieladung
  my ($pou,$pounit)    = split ":", $h->{pout};                                               # Readingname/Unit für aktuelle Batterieentladung
  my ($bin,$binunit)   = split ":", $h->{intotal}  // "-:-";                                  # Readingname/Unit der total in die Batterie eingespeisten Energie (Zähler)
  my ($bout,$boutunit) = split ":", $h->{outtotal} // "-:-";                                  # Readingname/Unit der total aus der Batterie entnommenen Energie (Zähler)
  my $batchr           = $h->{charge} // "";                                                  # Readingname Ladezustand Batterie

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

  my $debug = $paref->{debug};
  if($debug =~ /collectData/x) {
      Log3 ($name, 1, "$name DEBUG> collect Battery data: device=$badev =>");
      Log3 ($name, 1, "$name DEBUG> pin=$pbi W, pout=$pbo W, totalin: $btotin Wh, totalout: $btotout Wh, soc: $soc");
  }

  my $params;

  if ($pin eq "-pout") {                                                                       # Spezialfall pin bei neg. pout
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

  my $nhour        = $chour+1;

######

  my $histbatintot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "batintotal", undef);   # totale Betterieladung zu Beginn einer Stunde

  my $batinthishour;
  if(!defined $histbatintot) {                                                                # totale Betterieladung der aktuelle Stunde gesetzt ?
      $paref->{batintotal} = $btotin;
      $paref->{nhour}      = sprintf("%02d",$nhour);
      $paref->{histname}   = "batintotal";
      setPVhistory ($paref);
      delete $paref->{histname};

      my $bitot      = CurrentVal ($hash, "batintotal", $btotin);
      $batinthishour = int ($btotin - $bitot);
  }
  else {
      $batinthishour = int ($btotin - $histbatintot);
  }

  if($batinthishour < 0) {
      $batinthishour = 0;
  }

  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{batin} = $batinthishour;                # Ringspeicher Battery In Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350

  $paref->{batinthishour} = $batinthishour;
  $paref->{nhour}         = sprintf("%02d",$nhour);
  $paref->{histname}      = "batinthishour";
  setPVhistory ($paref);
  delete $paref->{histname};

######

  my $histbatouttot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "batouttotal", undef);   # totale Betterieladung zu Beginn einer Stunde

  my $batoutthishour;
  if(!defined $histbatouttot) {                                                                 # totale Betterieladung der aktuelle Stunde gesetzt ?
      $paref->{batouttotal} = $btotout;
      $paref->{nhour}       = sprintf("%02d",$nhour);
      $paref->{histname}    = "batouttotal";
      setPVhistory ($paref);
      delete $paref->{histname};

      my $botot       = CurrentVal ($hash, "batouttotal", $btotout);
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
  $paref->{histname}       = "batoutthishour";
  setPVhistory ($paref);
  delete $paref->{histname};

######

  push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_BatIn<>". $batinthishour. " Wh";
  push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_BatOut<>".$batoutthishour." Wh";
  push @$daref, "Current_PowerBatIn<>". (int $pbi)." W";
  push @$daref, "Current_PowerBatOut<>".(int $pbo)." W";
  push @$daref, "Current_BatCharge<>".  $soc." %";

  $data{$type}{$name}{current}{powerbatin}  = int $pbi;                                       # Hilfshash Wert aktuelle Batterieladung
  $data{$type}{$name}{current}{powerbatout} = int $pbo;                                       # Hilfshash Wert aktuelle Batterieentladung
  $data{$type}{$name}{current}{batintotal}  = int $btotin;                                    # totale Batterieladung
  $data{$type}{$name}{current}{batouttotal} = int $btotout;                                   # totale Batterieentladung
  $data{$type}{$name}{current}{batcharge}   = $soc;                                           # aktuelle Batterieladung

return;
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
  my $debug = $paref->{debug};
  my $acref = $data{$type}{$name}{consumers};

  ## Verbrauchsvorhersage für den nächsten Tag
  ##############################################
  my $tomorrow   = strftime "%a", localtime($t+86400);                                                  # Wochentagsname kommender Tag
  my $totcon     = 0;
  my $dnum       = 0;
  my $consumerco = 0;
  #my $min        =  (~0 >> 1);
  #my $max        = -(~0 >> 1);

  for my $n (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {
      next if ($n eq $day);                                                                             # aktuellen (unvollständigen) Tag nicht berücksichtigen

      if ($swdfcfc) {                                                                                   # nur gleiche Tage (Mo...So) einbeziehen
          my $hdn = HistoryVal ($hash, $n, 99, 'dayname', undef);
          next if(!$hdn || $hdn ne $tomorrow);
      }

      my $dcon = HistoryVal ($hash, $n, 99, "con", 0);
      next if(!$dcon);

      #for my $c (sort{$a<=>$b} keys %{$acref}) {                                                        # historischen Verbrauch aller registrierten Verbraucher aufaddieren
      #    $consumerco += HistoryVal ($hash, $n, 99, "csme${c}", 0);
      #}

      #$dcon -= $consumerco if($dcon >= $consumerco);                                                    # Verbrauch registrierter Verbraucher aus Verbrauchsvorhersage eliminieren

      #$min  = $dcon if($dcon < $min);
      #$max  = $dcon if($dcon > $max);

      $totcon += $dcon;
      $dnum++;
  }

  if ($dnum) {
       #my $ddiff                                         = ($max - $min)/$dnum;                          # Glättungsdifferenz
       #my $tomavg                                        = int (($totcon/$dnum)-$ddiff);
       my $tomavg                                        = int ($totcon / $dnum);
       $data{$type}{$name}{current}{tomorrowconsumption} = $tomavg;                                      # prognostizierter Durchschnittsverbrauch aller (gleicher) Wochentage

       if($debug =~ /consumption/x) {
           Log3 ($name, 1, "$name DEBUG> estimated Consumption for tomorrow: $tomavg, days for avg: $dnum, hist. consumption registered consumers: ".sprintf "%.2f", $consumerco);
       }
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

  for my $k (sort keys %{$data{$type}{$name}{nexthours}}) {
      my $nhtime = NexthoursVal ($hash, $k, "starttime", undef);                                      # Startzeit
      next if(!$nhtime);

      $dnum       = 0;
      $consumerco = 0;
      #$min        =  (~0 >> 1);
      #$max        = -(~0 >> 1);
      my $utime   = timestringToTimestamp ($nhtime);
      my $nhday   = strftime "%a", localtime($utime);                                               # Wochentagsname des NextHours Key
      my $nhhr    = sprintf("%02d", (int (strftime "%H", localtime($utime))) + 1);                  # Stunde des Tages vom NextHours Key  (01,02,...24)

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

          #$hcon -= $consumerco if($hcon >= $consumerco);                                            # Verbrauch registrierter Verbraucher aus Verbrauch eliminieren
          $conhex->{$nhhr} += $hcon - $consumerco if($hcon >= $consumerco);                          # prognostizierter Verbrauch Ex registrierter Verbraucher
          #$min = $hcon if($hcon < $min);
          #$max = $hcon if($hcon > $max);

          $conh->{$nhhr} += $hcon;
          $dnum++;
      }

      if ($dnum) {
           #my $hdiff                                 = ($max - $min)/$dnum;                         # Glättungsdifferenz
           #my $conavg                                = int(($conh->{$nhhr}/$dnum)-$hdiff);
           $data{$type}{$name}{nexthours}{$k}{confcEx} = int ($conhex->{$nhhr} / $dnum);

           my $conavg                                  = int ($conh->{$nhhr} / $dnum);
           $data{$type}{$name}{nexthours}{$k}{confc}   = $conavg;                                   # Durchschnittsverbrauch aller gleicher Wochentage pro Stunde

           if (NexthoursVal ($hash, $k, "today", 0)) {                                              # nur Werte des aktuellen Tag speichern
               $data{$type}{$name}{circular}{sprintf("%02d",$nhhr)}{confc} = $conavg;

               $paref->{confc}    = $conavg;
               $paref->{nhour}    = sprintf("%02d",$nhhr);
               $paref->{histname} = "confc";
               setPVhistory ($paref);
               delete $paref->{histname};
           }

           if($debug =~ /consumption/x) {
               Log3 ($name, 1, "$name DEBUG> estimated Consumption for $nhday -> starttime: $nhtime, con: $conavg, days for avg: $dnum, hist. consumption registered consumers: ".sprintf "%.2f", $consumerco);
           }
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
  my $daref = $paref->{daref};

  my $pt    = ReadingsVal($name, "powerTrigger", "");
  my $eh4t  = ReadingsVal($name, "energyH4Trigger", "");

  if ($pt) {
      my $aaref = CurrentVal ($hash, "genslidereg", "");
      my @aa    = ();
      @aa       = @{$aaref} if (ref $aaref eq "ARRAY");

      if (scalar @aa >= $defslidenum) {
          $paref->{taref}  = \@aa;
          $paref->{tname}  = "powerTrigger";
          $paref->{tholds} = $pt;

          __evaluateArray ($paref);
      }
  }

  if ($eh4t) {
      my $aaref = CurrentVal ($hash, "h4fcslidereg", "");
      my @aa    = ();
      @aa       = @{$aaref} if (ref $aaref eq "ARRAY");

      if (scalar @aa >= $defslidenum) {
          $paref->{taref}  = \@aa;
          $paref->{tname}  = "energyH4Trigger";
          $paref->{tholds} = $eh4t;

          __evaluateArray ($paref);
      }
  }

  delete $paref->{taref};
  delete $paref->{tname};
  delete $paref->{tholds};

return;
}

################################################################
#     Threshold-Array auswerten und Readings vorbereiten
################################################################
sub __evaluateArray {
  my $paref  = shift;
  my $name   = $paref->{name};
  my $daref  = $paref->{daref};
  my $taref  = $paref->{taref};          # Referenz zum Threshold-Array
  my $tname  = $paref->{tname};          # Thresholdname, z.B. powerTrigger
  my $tholds = $paref->{tholds};         # Triggervorgaben, z.B. aus Reading powerTrigger

  my $gen1   = @$taref[0];
  my $gen2   = @$taref[1];
  my $gen3   = @$taref[2];

  my ($a,$h) = parseParams ($tholds);

  for my $key (keys %{$h}) {
      my ($knum,$cond) = $key =~ /^([0-9]+)(on|off)$/x;

      if($cond eq "on" && $gen1 > $h->{$key}) {
          next if($gen2 < $h->{$key});
          next if($gen3 < $h->{$key});
          push @$daref, "${tname}_${knum}<>on"  if(ReadingsVal($name, "${tname}_${knum}", "off") eq "off");
      }

      if($cond eq "off" && $gen1 < $h->{$key}) {
          next if($gen2 > $h->{$key});
          next if($gen3 > $h->{$key});
          push @$daref, "${tname}_${knum}<>off" if(ReadingsVal($name, "${tname}_${knum}", "on") eq "on");
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
  my $daref  = $paref->{daref};

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
      my $pvfc = NexthoursVal ($hash, $idx, 'pvforecast', 0);

      push @$daref, "Tomorrow_Hour".$h."_PVforecast<>".$pvfc." Wh";
  }

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
  my $daref  = $paref->{daref};
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

  my $rdh              = 24 - $chour - 1;                                                             # verbleibende Anzahl Stunden am Tag beginnend mit 00 (abzüglich aktuelle Stunde)
  my $remainminutes    = 60 - $minute;                                                                # verbleibende Minuten der aktuellen Stunde

  my $restofhourpvfc   = (NexthoursVal($hash, "NextHour00", "pvforecast", 0)) / 60 * $remainminutes;
  my $restofhourconfc  = (NexthoursVal($hash, "NextHour00", "confc",      0)) / 60 * $remainminutes;

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
      my $pvfc  = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), "pvforecast", 0);
      my $confc = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), "confc",      0);
      my $istdy = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), "today",      1);

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

      $restOfDaySum->{PV}          += $pvfc  if($h <= $rdh);
      $restOfDaySum->{Consumption} += $confc if($h <= $rdh);

      $tomorrowSum->{PV}           += $pvfc if(!$istdy);
  }

  for my $th (1..24) {
      $todaySumFc->{PV} += ReadingsNum($name, "Today_Hour".sprintf("%02d",$th)."_PVforecast", 0);
      $todaySumRe->{PV} += ReadingsNum($name, "Today_Hour".sprintf("%02d",$th)."_PVreal",     0);
  }

  push @{$data{$type}{$name}{current}{h4fcslidereg}}, int $next4HoursSum->{PV};                         # Schieberegister 4h Summe Forecast
  limitArray ($data{$type}{$name}{current}{h4fcslidereg}, $defslidenum);

  my $gcon    = CurrentVal ($hash, "gridconsumption",         0);                                       # aktueller Netzbezug
  my $tconsum = CurrentVal ($hash, "tomorrowconsumption", undef);                                       # Verbrauchsprognose für folgenden Tag
  my $pvgen   = CurrentVal ($hash, "generation",              0);
  my $gfeedin = CurrentVal ($hash, "gridfeedin",              0);
  my $batin   = CurrentVal ($hash, "powerbatin",              0);                                       # aktuelle Batterieladung
  my $batout  = CurrentVal ($hash, "powerbatout",             0);                                       # aktuelle Batterieentladung

  my $consumption         = int ($pvgen - $gfeedin + $gcon - $batin + $batout);
  my $selfconsumption     = int ($pvgen - $gfeedin - $batin + $batout);
  $selfconsumption        = $selfconsumption < 0 ? 0 : $selfconsumption;

  my $surplus             = int ($pvgen - $consumption);                                                # aktueller Überschuß
  $surplus                = 0 if($surplus < 0);                                                         # wegen Vergleich nompower vs. surplus

  my $selfconsumptionrate = 0;
  my $autarkyrate         = 0;
  $selfconsumptionrate    = sprintf("%.0f", $selfconsumption / $pvgen * 100) if($pvgen * 1 > 0);
  $autarkyrate            = sprintf("%.0f", $selfconsumption / ($selfconsumption + $gcon) * 100) if($selfconsumption);

  $data{$type}{$name}{current}{consumption}         = $consumption;
  $data{$type}{$name}{current}{selfconsumption}     = $selfconsumption;
  $data{$type}{$name}{current}{selfconsumptionrate} = $selfconsumptionrate;
  $data{$type}{$name}{current}{autarkyrate}         = $autarkyrate;
  $data{$type}{$name}{current}{surplus}             = $surplus;

  push @$daref, "Current_Consumption<>".         $consumption.              " W";
  push @$daref, "Current_SelfConsumption<>".     $selfconsumption.          " W";
  push @$daref, "Current_SelfConsumptionRate<>". $selfconsumptionrate.      " %";
  push @$daref, "Current_AutarkyRate<>".         $autarkyrate.              " %";

  push @$daref, "NextHours_Sum01_PVforecast<>".  (int $next1HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum02_PVforecast<>".  (int $next2HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum03_PVforecast<>".  (int $next3HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum04_PVforecast<>".  (int $next4HoursSum->{PV})." Wh";
  push @$daref, "RestOfDayPVforecast<>".         (int $restOfDaySum->{PV}). " Wh";
  push @$daref, "Tomorrow_PVforecast<>".         (int $tomorrowSum->{PV}).  " Wh";
  push @$daref, "Today_PVforecast<>".            (int $todaySumFc->{PV}).   " Wh";
  push @$daref, "Today_PVreal<>".                (int $todaySumRe->{PV}).   " Wh";

  push @$daref, "Tomorrow_ConsumptionForecast<>".           $tconsum.                          " Wh" if(defined $tconsum);
  push @$daref, "NextHours_Sum04_ConsumptionForecast<>".   (int $next4HoursSum->{Consumption})." Wh";
  push @$daref, "RestOfDayConsumptionForecast<>".          (int $restOfDaySum->{Consumption}). " Wh";

return;
}

################################################################
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
  my $daref = $paref->{daref};

  my $sstime = timestringToTimestamp ($date.' '.ReadingsVal($name, "Today_SunSet",  '22:00').':00');

  return if($t < $sstime);

  my $pvfc = ReadingsNum ($name, 'Today_PVforecast', 0);
  my $pvre = ReadingsNum ($name, 'Today_PVreal',     0);

  my $diff = $pvfc - $pvre;

  if($pvre) {
      my $dp                                      = sprintf "%.2f" , (100 * $diff / $pvre);
      $data{$type}{$name}{circular}{99}{tdayDvtn} = $dp;

      push @$daref, "Today_PVdeviation<>". $dp." %";
  }

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

  my $pvrl    = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_PVreal",          0);
  my $gfeedin = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridFeedIn",      0);
  my $gcon    = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  my $batin   = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_BatIn",           0);
  my $batout  = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_BatOut",          0);

  my $con = $pvrl - $gfeedin + $gcon - $batin + $batout;

  $paref->{con}      = $con;
  $paref->{nhour}    = sprintf("%02d",$chour+1);
  $paref->{histname} = "con";
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
  my $daref = $paref->{daref};

  my @csr = split ',', AttrVal($name, 'ctrlStatisticReadings', '');

  return if(!@csr);

  for my $kpi (@csr) {
      if ($hcsr{$kpi}{fnr} == 1) {
          push @$daref, 'statistic_'.$kpi.'<>'. &{$hcsr{$kpi}{fn}} ($hash, '?All', '?All', $kpi, $hcsr{$kpi}{def});
      }

      if ($hcsr{$kpi}{fnr} == 2) {
          push @$daref, 'statistic_'.$kpi.'<>'. &{$hcsr{$kpi}{fn}} ($hash, $kpi, $hcsr{$kpi}{def});
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

  delete $data{$type}{$name}{current}{consumerdevs};

  for my $c (1..$maxconsumer) {
      $c           = sprintf "%02d", $c;
      my $consumer = AttrVal ($name, "consumer${c}", "");
      next if(!$consumer);

      my ($ac,$hc) = parseParams ($consumer);
      $consumer    = $ac->[0] // "";

      if(!$consumer || !$defs{$consumer}) {
          my $err = qq{ERROR - the device "$consumer" doesn't exist anymore! Delete or change the attribute "consumer${c}".};
          Log3 ($name, 1, "$name - $err");
          next;
      }

      push @{$data{$type}{$name}{current}{consumerdevs}}, $consumer;                              # alle Consumerdevices in CurrentHash eintragen

      my $alias = AttrVal ($consumer, "alias", $consumer);

      my ($rtot,$utot,$ethreshold);
      if(exists $hc->{etotal}) {
          my $etotal                = $hc->{etotal};
          ($rtot,$utot,$ethreshold) = split ":", $etotal;
      }

      my ($rpcurr,$upcurr,$pthreshold);
      if(exists $hc->{pcurr}) {
          my $pcurr                     = $hc->{pcurr};
          ($rpcurr,$upcurr,$pthreshold) = split ":", $pcurr;
      }

      my ($rswstate,$onreg,$offreg);
      if(exists $hc->{swstate}) {
          ($rswstate,$onreg,$offreg) = split ":", $hc->{swstate};
      }

      my ($dswoncond,$rswoncond,$swoncondregex);
      if(exists $hc->{swoncond}) {                                                                # zusätzliche Einschaltbedingung
          ($dswoncond,$rswoncond,$swoncondregex) = split ":", $hc->{swoncond};
      }

      my ($dswoffcond,$rswoffcond,$swoffcondregex);
      if(exists $hc->{swoffcond}) {                                                               # vorrangige Ausschaltbedingung
          ($dswoffcond,$rswoffcond,$swoffcondregex) = split ":", $hc->{swoffcond};
      }

      my $interruptable = 0;
      my ($hyst);
      if(exists $hc->{interruptable} && $hc->{interruptable} ne '0') {
          $interruptable         = $hc->{interruptable};
          ($interruptable,$hyst) = $interruptable =~ /(.*):(.*)$/xs if($interruptable ne '1');
      }

      my $rauto     = $hc->{auto}     // q{};
      my $ctype     = $hc->{type}     // $defctype;
      my $auto      = 1;
      $auto         = ReadingsVal ($consumer, $rauto, 1) if($rauto);                               # Reading für Ready-Bit -> Einschalten möglich ?

      $data{$type}{$name}{consumers}{$c}{name}            = $consumer;                             # Name des Verbrauchers (Device)
      $data{$type}{$name}{consumers}{$c}{alias}           = $alias;                                # Alias des Verbrauchers (Device)
      $data{$type}{$name}{consumers}{$c}{type}            = $hc->{type}      // $defctype;         # Typ des Verbrauchers
      $data{$type}{$name}{consumers}{$c}{power}           = $hc->{power};                          # Leistungsaufnahme des Verbrauchers in W
      $data{$type}{$name}{consumers}{$c}{avgenergy}       = q{};                                   # Initialwert Energieverbrauch (evtl. Überschreiben in manageConsumerData)
      $data{$type}{$name}{consumers}{$c}{mintime}         = $hc->{mintime}   // $hef{$ctype}{mt};  # Initialwert min. Einschalt- bzw. Zykluszeit (evtl. Überschreiben in manageConsumerData)
      $data{$type}{$name}{consumers}{$c}{mode}            = $hc->{mode}      // $defcmode;         # Planungsmode des Verbrauchers
      $data{$type}{$name}{consumers}{$c}{icon}            = $hc->{icon}      // q{};               # Icon für den Verbraucher
      $data{$type}{$name}{consumers}{$c}{oncom}           = $hc->{on}        // q{};               # Setter Einschaltkommando
      $data{$type}{$name}{consumers}{$c}{offcom}          = $hc->{off}       // q{};               # Setter Ausschaltkommando
      $data{$type}{$name}{consumers}{$c}{autoreading}     = $rauto;                                # Readingname zur Automatiksteuerung
      $data{$type}{$name}{consumers}{$c}{auto}            = $auto;                                 # Automaticsteuerung: 1 - Automatic ein, 0 - Automatic aus
      $data{$type}{$name}{consumers}{$c}{retotal}         = $rtot            // q{};               # Reading der Leistungsmessung
      $data{$type}{$name}{consumers}{$c}{uetotal}         = $utot            // q{};               # Unit der Leistungsmessung
      $data{$type}{$name}{consumers}{$c}{energythreshold} = $ethreshold      // 0;                 # Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird
      $data{$type}{$name}{consumers}{$c}{rpcurr}          = $rpcurr          // q{};               # Reading der aktuellen Leistungsaufnahme
      $data{$type}{$name}{consumers}{$c}{upcurr}          = $upcurr          // q{};               # Unit der aktuellen Leistungsaufnahme
      $data{$type}{$name}{consumers}{$c}{powerthreshold}  = $pthreshold      // 0;                 # Schwellenwert d. aktuellen Leistung(W) ab der ein Verbraucher als aktiv gewertet wird
      $data{$type}{$name}{consumers}{$c}{notbefore}       = $hc->{notbefore} // q{};               # nicht einschalten vor Stunde in 24h Format (00-23)
      $data{$type}{$name}{consumers}{$c}{notafter}        = $hc->{notafter}  // q{};               # nicht einschalten nach Stunde in 24h Format (00-23)
      $data{$type}{$name}{consumers}{$c}{rswstate}        = $rswstate        // 'state';           # Schaltstatus Reading
      $data{$type}{$name}{consumers}{$c}{onreg}           = $onreg           // 'on';              # Regex für 'ein'
      $data{$type}{$name}{consumers}{$c}{offreg}          = $offreg          // 'off';             # Regex für 'aus'
      $data{$type}{$name}{consumers}{$c}{dswoncond}       = $dswoncond       // q{};               # Device zur Lieferung einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{rswoncond}       = $rswoncond       // q{};               # Reading zur Lieferung einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{swoncondregex}   = $swoncondregex   // q{};               # Regex einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{dswoffcond}      = $dswoffcond      // q{};               # Device zur Lieferung einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{rswoffcond}      = $rswoffcond      // q{};               # Reading zur Lieferung einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{swoffcondregex}  = $swoffcondregex  // q{};               # Regex einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{interruptable}   = $interruptable;                        # Ein-Zustand des Verbrauchers ist unterbrechbar
      $data{$type}{$name}{consumers}{$c}{hysteresis}      = $hyst            // $defhyst;          # Hysterese
  }

  # Log3 ($name, 5, "$name - all registered consumers:\n".Dumper $data{$type}{$name}{consumers});

return;
}

################################################################
#              FHEMWEB Fn
################################################################
sub FwFn {
  my ($FW_wname, $name, $room, $pageHash) = @_;                                  # pageHash is set for summaryFn.
  my $hash = $defs{$name};

  RemoveInternalTimer($hash, \&pageRefresh);
  $hash->{HELPER}{FW} = $FW_wname;

  my $ret = "<html>";
  $ret   .= entryGraphic ($name);
  $ret   .= "</html>";

  # Autorefresh nur des aufrufenden FHEMWEB-Devices
  my $al = AttrVal($name, "ctrlAutoRefresh", 0);
  if($al) {
      InternalTimer(gettimeofday()+$al, \&pageRefresh, $hash, 0);
      Log3 ($name, 5, "$name - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }

return $ret;
}

################################################################
sub pageRefresh {
  my $hash = shift;
  my $name = $hash->{NAME};

  # Seitenrefresh festgelegt durch SolarForecast-Attribut "ctrlAutoRefresh" und "ctrlAutoRefreshFW"
  my $rd = AttrVal($name, "ctrlAutoRefreshFW", $hash->{HELPER}{FW});
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }       ## no critic 'Map blocks'

  my $al = AttrVal($name, "ctrlAutoRefresh", 0);

  if($al) {
      InternalTimer(gettimeofday()+$al, \&pageRefresh, $hash, 0);
      Log3 ($name, 5, "$name - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }
  else {
      RemoveInternalTimer($hash, \&pageRefresh);
  }

return;
}

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub pageAsHtml {
  my $name = shift;
  my $ftui = shift;

  my $ret = "<html>";
  $ret   .= entryGraphic ($name, $ftui);
  $ret   .= "</html>";

return $ret;
}

################################################################
#                  Einstieg Grafikanzeige
################################################################
sub entryGraphic {
  my $name = shift;
  my $ftui = shift // "";

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
  my $alias      = AttrVal ($name, 'alias',            $name);                             # Linktext als Aliasname oder Devicename setzen
  my $gsel       = AttrVal ($name, 'graphicSelect',   'both');                             # Auswahl der anzuzeigenden Grafiken
  my $html_start = AttrVal ($name, 'graphicStartHtml', undef);                             # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_end   = AttrVal ($name, 'graphicEndHtml',   undef);                             # beliebige HTML Strings die nach der Grafik ausgegeben werden
  my $w          = $width * $maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  my $offset     = -1 * AttrNum ($name, 'graphicHistoryHour', $histhourdef);

  my $dlink      = qq{<a href="$FW_ME$FW_subdir?detail=$name">$alias</a>};

  my $paref = {
      hash           => $hash,
      name           => $name,
      type           => $hash->{TYPE},
      ftui           => $ftui,
      maxhours       => $maxhours,
      modulo         => 1,
      dstyle         => qq{style='padding-left: 10px; padding-right: 10px; padding-top: 3px; padding-bottom: 3px; white-space:nowrap;'},     # TD-Style
      offset         => $offset,
      hourstyle      => AttrVal ($name,    'graphicHourStyle',                  ''),
      colorb1        => AttrVal ($name,    'graphicBeam1Color',          $b1coldef),
      colorb2        => AttrVal ($name,    'graphicBeam2Color',          $b2coldef),
      fcolor1        => AttrVal ($name,    'graphicBeam1FontColor',  $b1fontcoldef),
      fcolor2        => AttrVal ($name,    'graphicBeam2FontColor',  $b2fontcoldef),
      beam1cont      => AttrVal ($name,    'graphicBeam1Content',         'pvReal'),
      beam2cont      => AttrVal ($name,    'graphicBeam2Content',     'pvForecast'),
      caicon         => AttrVal ($name,    'consumerAdviceIcon',        $caicondef),            # Consumer AdviceIcon
      clegend        => AttrVal ($name,    'consumerLegend',            'icon_top'),            # Lage und Art Cunsumer Legende
      clink          => AttrVal ($name,    'consumerLink'  ,                     1),            # Detail-Link zum Verbraucher
      debug          => AttrVal ($name,    'ctrlDebug',                     'none'),            # Debug Module
      lotype         => AttrVal ($name,    'graphicLayoutType',           'double'),
      kw             => AttrVal ($name,    'graphicEnergyUnit',               'Wh'),
      height         => AttrNum ($name,    'graphicBeamHeight',                200),
      width          => $width,
      fsize          => AttrNum ($name,    'graphicSpaceSize',                  24),
      maxVal         => AttrNum ($name,    'graphicBeam1MaxVal',                 0),            # dyn. Anpassung der Balkenhöhe oder statisch ?
      show_night     => AttrNum ($name,    'graphicShowNight',                   0),            # alle Balken (Spalten) anzeigen ?
      show_diff      => AttrVal ($name,    'graphicShowDiff',                 'no'),            # zusätzliche Anzeige $di{} in allen Typen
      weather        => AttrNum ($name,    'graphicShowWeather',                 1),
      colorw         => AttrVal ($name,    'graphicWeatherColor',      $wthcolddef),            # Wetter Icon Farbe Tag
      colorwn        => AttrVal ($name,    'graphicWeatherColorNight', $wthcolndef),            # Wetter Icon Farbe Nacht
      wlalias        => AttrVal ($name,    'alias',                          $name),
      sheader        => AttrNum ($name,    'graphicHeaderShow',                  1),            # Anzeigen des Grafik Headers
      hdrDetail      => AttrVal ($name,    'graphicHeaderDetail',            'all'),            # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten
      flowgsize      => AttrVal ($name,    'flowGraphicSize',        $flowGSizedef),            # Größe Energieflußgrafik
      flowgani       => AttrVal ($name,    'flowGraphicAnimate',                 0),            # Animation Energieflußgrafik
      flowgcons      => AttrVal ($name,    'flowGraphicShowConsumer',            1),            # Verbraucher in der Energieflußgrafik anzeigen
      flowgconX      => AttrVal ($name,    'flowGraphicShowConsumerDummy',       1),            # Dummyverbraucher in der Energieflußgrafik anzeigen
      flowgconsPower => AttrVal ($name,    'flowGraphicShowConsumerPower'     ,  1),            # Verbraucher Leistung in der Energieflußgrafik anzeigen
      flowgconsTime  => AttrVal ($name,    'flowGraphicShowConsumerRemainTime',  1),            # Verbraucher Restlaufeit in der Energieflußgrafik anzeigen
      flowgconsDist  => AttrVal ($name,    'flowGraphicConsumerDistance', $fgCDdef),            # Abstand Verbrauchericons zueinander
      css            => AttrVal ($name,    'flowGraphicCss',               $cssdef),            # flowGraphicCss Styles
      lang           => AttrVal ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang)),
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
      $ret .= "$legendtxt</td>";
      $ret .= "</tr>";

      $paref->{modulo}++;
  }

  $m = $paref->{modulo} % 2;

  if($gsel eq "both" || $gsel eq "forecast") {
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

  if($gsel eq "both" || $gsel eq "flow") {
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

  my $is    = ReadingsVal  ($name, "inverterStrings",          undef);                    # String Konfig
  my $fcdev = ReadingsVal  ($name, "currentForecastDev",       undef);                    # Device Vorhersage Wetterdaten (Bewölkung etc.)
  my $radev = ReadingsVal  ($name, "currentRadiationDev",      undef);                    # Device Strahlungsdaten Vorhersage
  my $indev = ReadingsVal  ($name, "currentInverterDev",       undef);                    # Inverter Device
  my $medev = ReadingsVal  ($name, "currentMeterDev",          undef);                    # Meter Device

  my $peaks = ReadingsVal  ($name, "modulePeakString",         undef);                    # String Peak
  my $dir   = ReadingsVal  ($name, "moduleDirection",          undef);                    # Modulausrichtung Konfig
  my $ta    = ReadingsVal  ($name, "moduleTiltAngle",          undef);                    # Modul Neigungswinkel Konfig
  my $mrt   = ReadingsVal  ($name, "moduleRoofTops",           undef);                    # RoofTop Konfiguration (SolCast API)
  my $rip   = 1 if(exists $data{$type}{$name}{solcastapi}{'?IdPair'});                    # es existiert mindestens ein Paar RoofTop-ID / API-Key

  my $pv0   = NexthoursVal ($hash, "NextHour00", "pvforecast", undef);                    # der erste PV ForeCast Wert

  my $link   = qq{<a href="$FW_ME$FW_subdir?detail=$name">$name</a>};
  my $height = AttrNum ($name, 'graphicBeamHeight', 200);
  my $lang   = AttrVal ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang));

  if(IsDisabled($name)) {
      $ret .= "<table class='roomoverview'>";
      $ret .= "<tr style='height:".$height."px'>";
      $ret .= "<td>";
      $ret .= qq{SolarForecast device $link is disabled};
      $ret .= "</td>";
      $ret .= "</tr>";
      $ret .= "</table>";

      return $ret;
  }

  if(!$is || !$fcdev || !$radev || !$indev || !$medev || !$peaks ||
     (isSolCastUsed ($hash) ? (!$rip || !$mrt) : (!$dir || !$ta )) ||
     !defined $pv0) {
      $ret    .= "<table class='roomoverview'>";
      $ret    .= "<tr style='height:".$height."px'>";
      $ret    .= "<td>";

      if(!$fcdev) {                                                                        ## no critic 'Cascading'
          $ret .= $hqtxt{cfd}{$lang};
      }
      elsif(!$radev) {
          $ret .= $hqtxt{crd}{$lang};
      }
      elsif(!$indev) {
          $ret .= $hqtxt{cid}{$lang};
      }
      elsif(!$medev) {
          $ret .= $hqtxt{mid}{$lang};
      }
      elsif(!$is) {
          $ret .= $hqtxt{ist}{$lang};
      }
      elsif(!$peaks) {
          $ret .= $hqtxt{mps}{$lang};
      }
      elsif(!$rip && isSolCastUsed ($hash)) {                                             # Verwendung SolCast API
          $ret .= $hqtxt{rip}{$lang};
      }
      elsif(!$mrt && isSolCastUsed ($hash)) {                                             # Verwendung SolCast API
          $ret .= $hqtxt{mrt}{$lang};
      }
      elsif(!$dir && !isSolCastUsed ($hash))  {                                           # Verwendung DWD Strahlungsdevice
          $ret .= $hqtxt{mdr}{$lang};
      }
      elsif(!$ta && !isSolCastUsed ($hash))   {                                           # Verwendung DWD Strahlungsdevice
          $ret .= $hqtxt{mta}{$lang};
      }
      elsif(!defined $pv0) {
          $ret .= $hqtxt{awd}{$lang};
      }

      $ret   .= "</td>";
      $ret   .= "</tr>";
      $ret   .= "</table>";
      $ret    =~ s/LINK/$link/gxs;

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

  my $pcfa      = ReadingsVal ($name,"pvCorrectionFactor_Auto",         "off");
  my $co4h      = ReadingsNum ($name,"NextHours_Sum04_ConsumptionForecast", 0);
  my $coRe      = ReadingsNum ($name,"RestOfDayConsumptionForecast",        0);
  my $coTo      = ReadingsNum ($name,"Tomorrow_ConsumptionForecast",        0);
  my $coCu      = ReadingsNum ($name,"Current_Consumption",                 0);
  my $pv4h      = ReadingsNum ($name,"NextHours_Sum04_PVforecast",          0);
  my $pvRe      = ReadingsNum ($name,"RestOfDayPVforecast",                 0);
  my $pvTo      = ReadingsNum ($name,"Tomorrow_PVforecast",                 0);
  my $pvCu      = ReadingsNum ($name,"Current_PV",                          0);

  my $pvcorrf00  = NexthoursVal($hash, "NextHour00", "pvcorrf", "-/m");
  my ($pcf,$pcq) = split "/", $pvcorrf00;
  my $pvcanz     = qq{factor: $pcf / quality: $pcq};                                              
  $pcq           =~ s/m/-1/xs;
  my $pvfc00     =  NexthoursVal($hash, "NextHour00", "pvforecast", undef);

  if ($kw eq 'kWh') {
      $co4h = sprintf("%.1f" , $co4h/1000)."&nbsp;kWh";
      $coRe = sprintf("%.1f" , $coRe/1000)."&nbsp;kWh";
      $coTo = sprintf("%.1f" , $coTo/1000)."&nbsp;kWh";
      $coCu = sprintf("%.1f" , $coCu/1000)."&nbsp;kW";
      $pv4h = sprintf("%.1f" , $pv4h/1000)."&nbsp;kWh";
      $pvRe = sprintf("%.1f" , $pvRe/1000)."&nbsp;kWh";
      $pvTo = sprintf("%.1f" , $pvTo/1000)."&nbsp;kWh";
      $pvCu = sprintf("%.1f" , $pvCu/1000)."&nbsp;kW";
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
  if($hdrDetail eq "all" || $hdrDetail eq "statusLink") {
      my ($upicon,$scicon,$img);

      my ($year, $month, $day, $time) = $lup =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
      $lup                            = "$year-$month-$day&nbsp;$time";

      if($lang eq "DE") {
         $lup = "$day.$month.$year&nbsp;$time";
      }

      my $cmdupdate = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction 0 get $name data')"};                               # Update Button generieren

      if ($ftui eq "ftui") {
          $cmdupdate = qq{"ftui.setFhemStatus('set $name clientAction 0 get $name data')"};
      }

      my $cmdplchk = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name plantConfigCheck', function(data){FW_okDialog(data)})"};          # Plant Check Button generieren

      if ($ftui eq "ftui") {
          $cmdplchk = qq{"ftui.setFhemStatus('get $name plantConfigCheck')"};
      }

      my $upstate = ReadingsVal($name, 'state', '');

      ## Anlagen Check-Icon
      #######################
      $img         = FW_makeImage('edit_settings@grey');
      my $chkicon  = "<a onClick=$cmdplchk>$img</a>";
      my $chktitle = $htitles{plchk}{$lang};

      ## Update-Icon
      ################
      my $naup = ReadingsVal ($name, 'nextCycletime', '');
      if ($upstate =~ /updated|successfully|switched/ix) {
          $img    = FW_makeImage('10px-kreis-gruen.png', $htitles{upd}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$naup.'');
          #$img    = FW_makeImage('10px-kreis-gruen.png', $htitles{upd}{$lang}.' ('.$htitles{natc}{$lang}.' '.$naup.')');
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

      ## Autokorrektur-Icon
      ######################
      my $acicon;
      if ($pcfa eq "on") {
          $acicon = FW_makeImage('10px-kreis-gruen.png', $htitles{on}{$lang});
      }
      elsif ($pcfa eq "off") {
          $htitles{akorron}{$lang} =~ s/<NAME>/$name/xs;
          $acicon = FW_makeImage('-', $htitles{akorron}{$lang});
      }
      elsif ($pcfa =~ /standby/ix) {
          my ($rtime) = $pcfa =~ /for (.*?) hours/x;
          $img        = FW_makeImage('10px-kreis-gelb.png', $htitles{dela}{$lang});
          $acicon     = "$img&nbsp;(Start in ".$rtime." h)";
      }
      else {
          $acicon = FW_makeImage('10px-kreis-rot.png', $htitles{undef}{$lang});
      }

      ## SolCast Sektion
      ####################
      my $api = isSolCastUsed ($hash) ? 'SolCast:' : q{};

      if($api) {
          my $nscc = ReadingsVal   ($name, 'nextSolCastCall', '?');
          my $lrt  = SolCastAPIVal ($hash, '?All', '?All', 'lastretrieval_time', '-');

          if ($lrt =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x) {
              my ($sly, $slmo, $sld, $slt) = $lrt =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
              $lrt                         = "$sly-$slmo-$sld&nbsp;$slt";

              if($lang eq "DE") {
                 $lrt = "$sld.$slmo.$sly&nbsp;$slt";
              }
          }

          $api    .= '&nbsp;'.$lrt;
          my $scrm = SolCastAPIVal ($hash, '?All', '?All', 'response_message', '-');

          if ($scrm eq 'success') {
              $img = FW_makeImage('10px-kreis-gruen.png', $htitles{scaresps}{$lang}.'&#10;'.$htitles{natc}{$lang}.' '.$nscc);
          }
          elsif ($scrm =~ /You have exceeded your free daily limit/i) {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{yheyfdl}{$lang});
          }
          elsif ($scrm =~ /ApiKey does not exist/i) {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{scakdne}{$lang});
          }
          elsif ($scrm =~ /Rooftop site does not exist or is not accessible/i) {
              $img = FW_makeImage('10px-kreis-rot.png', $htitles{scarespf}{$lang}.':&#10;'. $htitles{scrsdne}{$lang});
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

      ## Qualitäts-Icon
      ######################
      my $pcqicon;

      if (isSolCastUsed ($hash)) {
      $pcqicon = $pcq < 10 ? FW_makeImage('10px-kreis-rot.png',  $pvcanz) :
                 $pcq < 20 ? FW_makeImage('10px-kreis-gelb.png', $pvcanz) :
                 FW_makeImage('10px-kreis-gruen.png', $pvcanz);
      }
      else {
      $pcqicon = $pcq < 3 ? FW_makeImage('10px-kreis-rot.png',  $pvcanz) :
                 $pcq < 5 ? FW_makeImage('10px-kreis-gelb.png', $pvcanz) :
                 FW_makeImage('10px-kreis-gruen.png', $pvcanz);
      }

      $pcqicon = "-" if(!$pvfc00 || $pcq == -1);

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

      my $dvtntxt  = $hqtxt{dvtn}{$lang}.'&nbsp;';
      my $tdaytxt  = $hqtxt{tday}{$lang}.':&nbsp;'."<b>".$tdayDvtn."</b>";
      my $ydaytxt  = $hqtxt{yday}{$lang}.':&nbsp;'."<b>".$ydayDvtn."</b>";
      
      my $text_tdayDvtn = $tdayDvtn =~ /^-[1-9]/? $hqtxt{pmtp}{$lang} :
                          $tdayDvtn =~ /^0/     ? $hqtxt{petp}{$lang} :
                          $tdayDvtn =~ /^[1-9]/ ? $hqtxt{pltp}{$lang} :
                          $hqtxt{wusond}{$lang};

      my $text_ydayDvtn = $ydayDvtn =~ /^-[1-9]/? $hqtxt{pmtp}{$lang} :
                          $ydayDvtn =~ /^0/     ? $hqtxt{petp}{$lang} :
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
      $header  .= qq{<td colspan="3" align="left"  $dstyle>                                                                                          </td>};
      $header  .= qq{<td colspan="3" align="left"  $dstyle> $autoct &nbsp;&nbsp; $acicon &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; $lbpcq&nbsp; &nbsp; $pcqicon </td>};
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
  if($hdrDetail eq "all" || $hdrDetail eq "pv" || $hdrDetail eq "pvco") {
      $header .= "<tr>";
      $header .= "<td $dstyle><b>PV&nbsp;=></b></td>";
      $header .= "<td $dstyle><b>$lblPvCu</b></td> <td align=right $dstyle>$pvCu</td>";
      $header .= "<td $dstyle><b>$lblPv4h</b></td> <td align=right $dstyle>$pv4h</td>";
      $header .= "<td $dstyle><b>$lblPvRe</b></td> <td align=right $dstyle>$pvRe</td>";
      $header .= "<td $dstyle><b>$lblPvTo</b></td> <td align=right $dstyle>$pvTo</td>";
      $header .= "</tr>";
  }


  # Header Information co
  ########################
  if($hdrDetail eq "all" || $hdrDetail eq "co" || $hdrDetail eq "pvco") {
      $header .= "<tr>";
      $header .= "<td $dstyle><b>CO&nbsp;=></b></td>";
      $header .= "<td $dstyle><b>$lblPvCu</b></td><td align=right $dstyle>$coCu</td>";
      $header .= "<td $dstyle><b>$lblPv4h</b></td><td align=right $dstyle>$co4h</td>";
      $header .= "<td $dstyle><b>$lblPvRe</b></td><td align=right $dstyle>$coRe</td>";
      $header .= "<td $dstyle><b>$lblPvTo</b></td><td align=right $dstyle>$coTo</td>";
      $header .= "</tr>";
  }
  
  $header .= qq{<tr>};
  $header .= qq{<td colspan="9" align="left" $dstyle><hr></td>};
  $header .= qq{</tr>};

  $header .= qq{</table>};

return $header;
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
  my ($clegendstyle, $clegend) = split('_', $paref->{clegend});
  my $clink                    = $paref->{clink};
  
  my $type                     = $paref->{type};
  my @consumers                = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};              # definierte Verbraucher ermitteln

  $clegend                     = '' if(($clegendstyle eq 'none') || (!int(@consumers)));
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
  if($cnum > 1) {
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
      my $caicon     = $paref->{caicon};                                                            # Consumer AdviceIcon
      my $cname      = ConsumerVal ($hash, $c, "name",                    "");                      # Name des Consumerdevices
      my $calias     = ConsumerVal ($hash, $c, "alias",               $cname);                      # Alias des Consumerdevices
      my $cicon      = ConsumerVal ($hash, $c, "icon",                    "");                      # Icon des Consumerdevices
      my $oncom      = ConsumerVal ($hash, $c, "oncom",                   "");                      # Consumer Einschaltkommando
      my $offcom     = ConsumerVal ($hash, $c, "offcom",                  "");                      # Consumer Ausschaltkommando
      my $autord     = ConsumerVal ($hash, $c, "autoreading",             "");                      # Readingname f. Automatiksteuerung
      my $auto       = ConsumerVal ($hash, $c, "auto",                     1);                      # Automatic Mode

      my $cmdon      = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction 0 set $cname $oncom')"};
      my $cmdoff     = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction 0 set $cname $offcom')"};
      my $cmdautoon  = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction 0 setreading $cname $autord 1')"};
      my $cmdautooff = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction 0 setreading $cname $autord 0')"};
      my $implan     = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name clientAction 0 consumerImmediatePlanning $c')"};

      if ($ftui eq "ftui") {
          $cmdon      = qq{"ftui.setFhemStatus('set $name clientAction 0 set $cname $oncom')"};
          $cmdoff     = qq{"ftui.setFhemStatus('set $name clientAction 0 set $cname $offcom')"};
          $cmdautoon  = qq{"ftui.setFhemStatus('set $name clientAction 0 setreading $cname $autord 1')"};
          $cmdautooff = qq{"ftui.setFhemStatus('set $name clientAction 0 setreading $cname $autord 0')"};
          $implan     = qq{"ftui.setFhemStatus('set $name clientAction 0 consumerImmediatePlanning $c')"};
      }

      $cmdon      = q{} if(!$oncom);
      $cmdoff     = q{} if(!$offcom);
      $cmdautoon  = q{} if(!$autord);
      $cmdautooff = q{} if(!$autord);

      my $swicon  = q{};                                                                              # Schalter ein/aus Icon
      my $auicon  = q{};                                                                              # Schalter Automatic Icon
      my $isricon = q{};                                                                              # Zustand IsRecommended Icon

      $paref->{consumer} = $c;

      my ($planstate,$starttime,$stoptime) = __getPlanningStateAndTimes ($paref);
      my $pstate                           = $caicon eq "times"    ? $hqtxt{pstate}{$lang}  : $htitles{pstate}{$lang};
      my $surplusinfo                      = isConsRcmd($hash, $c) ? $htitles{splus}{$lang} : $htitles{nosplus}{$lang};

      $pstate =~ s/<pstate>/$planstate/xs;
      $pstate =~ s/<start>/$starttime/xs;
      $pstate =~ s/<stop>/$stoptime/xs;
      $pstate =~ s/\s+/&nbsp;/gxs         if($caicon eq "times");
      
      if ($clink) {
          $calias = qq{<a title="$cname" href="$FW_ME$FW_subdir?detail=$cname" style="color: inherit !important;" target="_blank">$calias</a>};
      }

      if($caicon ne "none") {
          if(isInTimeframe($hash, $c)) {                                                             # innerhalb Planungszeitraum ?
              if($caicon eq "times") {
                  $isricon = $pstate.'<br>'.$surplusinfo;
              }
              else {
                  $isricon = "<a title='$htitles{conrec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage($caicon, '')." </a>";
                  if($planstate =~ /priority/xs) {
                      my (undef,$color) = split('@', $caicon);
                      $color            = $color ? '@'.$color : '';
                      $isricon          = "<a title='$htitles{conrec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage('it_ups_charging'.$color, '')." </a>";
                  }
              }
          }
          else {
              if($caicon eq "times") {
                  $isricon =  $pstate.'<br>'.$surplusinfo;
              }
              else {
                  ($caicon) = split('@', $caicon);
                  $isricon  = "<a title='$htitles{connorec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage($caicon.'@grey', '')." </a>";
              }
          }
      }

      if($modulo % 2){
          $ctable .= qq{<tr>};
          $tro     = 1;
      }

      if(!$auto) {
          $staticon = FW_makeImage('ios_off_fill@red', $htitles{iaaf}{$lang});
          $auicon   = "<a title= '$htitles{iaaf}{$lang}' onClick=$cmdautoon> $staticon</a>";
      }

      if ($auto) {
          $staticon = FW_makeImage('ios_on_till_fill@orange', $htitles{ieas}{$lang});
          $auicon   = "<a title='$htitles{ieas}{$lang}' onClick=$cmdautooff> $staticon</a>";
      }

      if (isConsumerPhysOff($hash, $c)) {                                                       # Schaltzustand des Consumerdevices off
          if($cmdon) {
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
          my (undef,$co) = split('@', $cicon);
          $co            = '' if (!$co);

          $ctable .= "<td style='text-align:left'   $dstyle><font color='$co'>$calias </font></td>";
          $ctable .= "<td>                                                                   </td>";
          $ctable .= "<td>                                  $isricon                         </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$swicon                          </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$auicon                          </td>";
      }

      if(!($modulo % 2)) {
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
       $ctable .= qq{<tr><td colspan="12"><hr></td></tr>};
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

  my $t                                = NexthoursVal ($hash, "NextHour00", "starttime", '0000-00-00 24');
  my ($year,$month,$day_str,$thishour) = $t =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
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

      $val1 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "pvfc",  0);
      $val2 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "pvrl",  0);
      $val3 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "gcons", 0);
      $val4 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "confc", 0);

      # $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, "weatherid", 999);
      $hfcg->{0}{weather} = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'weatherid', 999);
      $hfcg->{0}{wcc}     = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, 'wcc',       '-');
  }
  else {
      $val1 = CircularVal ($hash, $hfcg->{0}{time_str}, "pvfc",  0);
      $val2 = CircularVal ($hash, $hfcg->{0}{time_str}, "pvrl",  0);
      $val3 = CircularVal ($hash, $hfcg->{0}{time_str}, "gcons", 0);
      $val4 = CircularVal ($hash, $hfcg->{0}{time_str}, "confc", 0);

      $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, "weatherid", 999);
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

              $val1 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "pvfc",  0);
              $val2 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "pvrl",  0);
              $val3 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "gcons", 0);
              $val4 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "confc", 0);

              $hfcg->{$i}{weather} = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'weatherid', 999);
              $hfcg->{$i}{wcc}     = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, 'wcc',       '-');
          }
          else {
              $nh = sprintf('%02d', $i+$offset);
          }
      }
      else {
          $nh = sprintf('%02d', $i);
      }

      if (defined($nh)) {
          $val1                = NexthoursVal ($hash, 'NextHour'.$nh, "pvforecast",   0);
          $val4                = NexthoursVal ($hash, 'NextHour'.$nh, "confc",        0);
          $hfcg->{$i}{weather} = NexthoursVal ($hash, 'NextHour'.$nh, "weatherid",  999);
          $hfcg->{$i}{wcc}     = NexthoursVal ($hash, 'NextHour'.$nh, 'cloudcover', '-');
          #$val4   = (ReadingsVal($name,"NextHour".$ii."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time}-1).$hourstyle;
      $hfcg->{$i}{beam1}    = ($beam1cont eq 'pvForecast') ? $val1 : ($beam1cont eq 'pvReal') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
      $hfcg->{$i}{beam2}    = ($beam2cont eq 'pvForecast') ? $val1 : ($beam2cont eq 'pvReal') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;

      # sicher stellen das wir keine undefs in der Liste haben !
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
      for my $i (0..($maxhours*2)-1) {                                                                           # gleiche Bedingung wie oben
          next if (!$show_night && ($hfcg->{$i}{weather} > 99)
                                && !$hfcg->{$i}{beam1}
                                && !$hfcg->{$i}{beam2});
          $ii++;                                                                                                 # wieviele Stunden haben wir bisher angezeigt ?

          last if ($ii > $maxhours);                                                                             # vorzeitiger Abbruch

          $val  = formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather});

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

  for my $i (0..($maxhours*2)-1) {                                                                               # gleiche Bedingung wie oben
      next if (!$show_night && defined($hfcg->{$i}{weather})
                            && ($hfcg->{$i}{weather} > 99)
                            && !$hfcg->{$i}{beam1}
                            && !$hfcg->{$i}{beam2});
      $ii++;
      last if ($ii > $maxhours);

      # Achtung Falle, Division by Zero möglich,
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
          $val = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});

          $ret .="<table width='100%' height='100%'>";                                                           # mit width=100% etwas bessere Füllung der Balken
          $ret .="<tr class='$htr{$m}{cl}' style='height:".$he."px'>";
          $ret .="<td class='solarfc' style='vertical-align:bottom; color:#$fcolor1;'>".$val.'</td></tr>';

          if ($hfcg->{$i}{beam1} || $show_night) {                                                               # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
              my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style   .= defined $colorb1 ? " background-color:#$colorb1\"" : '"';                              # Syntaxhilight

              $ret .= "<tr class='odd' style='height:".$z3."px;'>";
              $ret .= "<td align='center' class='solarfc' ".$style.">";

              my $sicon = 1;
              #$ret .= $is{$i} if (defined ($is{$i}) && $sicon);

              # inject the new icon if defined
              ##################################
              #$ret .= consinject($hash,$i,@consumers) if($s);

              $ret .= "</td></tr>";
          }
      }

      if ($lotype eq 'double') {
          my ($color1, $color2, $style1, $style2, $v);
          my $style =  "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";

          $ret .="<table width='100%' height='100%'>\n";                                                         # mit width=100% etwas bessere Füllung der Balken
                                                                                                                 # der Freiraum oben kann beim größten Balken ganz entfallen
          $ret .="<tr class='$htr{$m}{cl}' style='height:".$he."px'><td class='solarfc'></td></tr>" if ($he);

          if($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                                          # wer ist oben, Beam2 oder Beam1 ? Wert und Farbe für Zone 2 & 3 vorbesetzen
              $val     = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});
              $color1  = $colorb1;
              $style1  = $style." background-color:#$color1; color:#$fcolor1;'";

              if($z3) {                                                                                          # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
                  $v       = formatVal6($hfcg->{$i}{beam2},$kw,$hfcg->{$i}{weather});
                  $color2  = $colorb2;
                  $style2  = $style." background-color:#$color2; color:#$fcolor2;'";
              }
          }
          else {
              $val     = formatVal6($hfcg->{$i}{beam2},$kw,$hfcg->{$i}{weather});
              $color1  = $colorb2;
              $style1  = $style." background-color:#$color1; color:#$fcolor2;'";

              if($z3) {
                  $v       = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});
                  $color2  = $colorb1;
                  $style2  = $style." background-color:#$color2; color:#$fcolor1;'";
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

          $val = ($hfcg->{$i}{diff} > 0) ? formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather}) : '';
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
              $val  = ($hfcg->{$i}{diff} < 0) ? formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather}) : '&nbsp;';
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z4."px'>";
              $ret .= "<td class='solarfc' style='vertical-align:top'>".$val."</td></tr>";
          }
      }

      if ($show_diff eq 'bottom') {                                                                                                      # zusätzliche diff Anzeige
          $val  = formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather});
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

  my $m     = $paref->{modulo} % 2;
  my $debug = $paref->{debug};

  $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";                                              # freier Platz am Anfang

  my $ii;
  for my $i (0..($maxhours*2)-1) {
      last if (!exists($hfcg->{$i}{weather}));
      next if (!$show_night  && defined($hfcg->{$i}{weather})
                             && ($hfcg->{$i}{weather} > 99)
                             && !$hfcg->{$i}{beam1}
                             && !$hfcg->{$i}{beam2});
                                                                                                             # Lässt Nachticons aber noch durch wenn es einen Wert gibt , ToDo : klären ob die Nacht richtig gesetzt wurde
      $ii++;                                                                                                 # wieviele Stunden Icons haben wir bisher beechnet  ?
      last if ($ii > $maxhours);
                                                                                                             # ToDo : weather_icon sollte im Fehlerfall Title mit der ID besetzen um in FHEMWEB sofort die ID sehen zu können
      if (exists($hfcg->{$i}{weather}) && defined($hfcg->{$i}{weather})) {
          my ($icon_name, $title) = $hfcg->{$i}{weather} > 100                     ? 
                                    weather_icon ($name, $lang, $hfcg->{$i}{weather}-100) : 
                                    weather_icon ($name, $lang, $hfcg->{$i}{weather});

          my $wcc = $hfcg->{$i}{wcc} // "-";                                                                 # Bewölkungsgrad ergänzen

          if(isNumeric ($wcc)) {                                                                             # Javascript Fehler vermeiden: https://forum.fhem.de/index.php/topic,117864.msg1233661.html#msg1233661
              $wcc += 0;
          }

          $title .= ': '.$wcc;

          if($icon_name eq 'unknown') {
              if($debug =~ /graphic/x) {
                  Log3 ($name, 1, "$name DEBUG> unknown weather id: ".$hfcg->{$i}{weather}.", please inform the maintainer");
              }
          }

          $icon_name .= $hfcg->{$i}{weather} < 100 ? '@'.$colorw  : '@'.$colorwn;
          my $val     = FW_makeImage($icon_name) // q{};

          if ($val eq $icon_name) {                                                                          # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
              $val = '<b>???<b/>';

              if($debug =~ /graphic/x) {                                                                     # nur für Debugging
                  Log3 ($name, 1, qq{$name DEBUG> - the icon "$weather_ids{$hfcg->{$i}{weather}}{icon}" not found. Please check attribute "iconPath" of your FHEMWEB instance and/or update your FHEM software});
              }
          }

          $ret .= "<td title='$title' class='solarfc' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";
      }
      else {                                                                                                 # mit $hfcg->{$i}{weather} = undef kann man unten leicht feststellen ob für diese Spalte bereits ein Icon ausgegeben wurde oder nicht
          $ret .= "<td></td>";
          $hfcg->{$i}{weather} = undef;                                                                      # ToDo : prüfen ob noch nötig
      }
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
  my $cpv        = ReadingsNum($name, 'Current_PV',              0);
  my $cgc        = ReadingsNum($name, 'Current_GridConsumption', 0);
  my $cgfi       = ReadingsNum($name, 'Current_GridFeedIn',      0);
  my $csc        = ReadingsNum($name, 'Current_SelfConsumption', 0);
  my $cc         = ReadingsNum($name, 'Current_Consumption',     0);
  my $cc_dummy   = $cc;
  my $batin      = ReadingsNum($name, 'Current_PowerBatIn',  undef);
  my $batout     = ReadingsNum($name, 'Current_PowerBatOut', undef);
  my $soc        = ReadingsNum($name, 'Current_BatCharge',     100);

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
      $csc -= $batout;
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

  my $batout_direction  =  'M902,305 L730,510';                                                # Batterientladung aus Netz

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
  my $vbox_default = $flowgconTime ? '5 -25 800 700'                 : '5 -25 800 680';

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

  ## get consumer list and display it in Graphics
  ################################################
  my $pos_left       = 0;
  my $consumercount  = 0;
  my $consumer_start = 0;
  my $currentPower   = 0;
  my @consumers;

  if ($flowgcons) {
      my $type       = $paref->{type};
      @consumers     = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};                        # definierte Verbraucher ermitteln
      $consumercount = scalar @consumers;

      if ($consumercount % 2) {
          $consumer_start = 350 - ($consDist  * (($consumercount -1) / 2));
      }
      else {
          $consumer_start = 350 - (($consDist / 2) * ($consumercount-1));
      }

      #$consumer_start = 0 if $consumer_start < 0;
      $pos_left       = $consumer_start + 15;

      for my $c0 (@consumers) {
          my $calias      = ConsumerVal       ($hash, $c0, "alias", "");                            # Name des Consumerdevices
          $currentPower   = ReadingsNum       ($name, "consumer${c0}_currentPower", 0);
          my $cicon       = substConsumerIcon ($hash, $c0);                                         # Icon des Consumerdevices
          $cc_dummy      -= $currentPower;

          $ret .= '<g id="consumer_'.$c0.'" fill="grey" transform="translate('.$pos_left.',485),scale(0.1)">';
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

      for my $c1 (@consumers) {
          my $power          = ConsumerVal ($hash, $c1, "power",   0);
          my $rpcurr         = ConsumerVal ($hash, $c1, "rpcurr", "");                              # Reading für akt. Verbrauch angegeben ?
          $currentPower      = ReadingsNum ($name, "consumer${c1}_currentPower", 0);

          if (!$rpcurr && isConsumerPhysOn($hash, $c1)) {                                           # Workaround wenn Verbraucher ohne Leistungsmessung
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

          $ret            .= qq{<path id="home-consumer_$c1" class="$consumer_style" $chain_color d="M$pos_left_start,700 L$pos_left,850" />};   # Design Consumer Laufkette

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

      for my $c2 (@consumers) {
          $currentPower    = sprintf("%.1f", ReadingsNum($name, "consumer${c2}_currentPower", 0));
          $currentPower    =~ s/\.0$// if (int($currentPower) > 0);                                   # .0 am Ende interessiert nicht
          my $consumerTime = ConsumerVal ($hash, $c2, "remainTime", "");                              # Restlaufzeit
          my $rpcurr       = ConsumerVal ($hash, $c2, "rpcurr",     "");                              # Readingname f. current Power

          if (!$rpcurr) {                                                                             # Workaround wenn Verbraucher ohne Leistungsmessung
              $currentPower = isConsumerPhysOn($hash, $c2) ? 'on' : 'off';
          }

          #$ret .= qq{<text class="flowg text" id="consumer-txt_$c2"      x="$pos_left" y="1110" style="text-anchor: start;">$currentPower</text>} if ($flowgconPower);    # Lage Consumer Consumption
          #$ret .= qq{<text class="flowg text" id="consumer-txt_time_$c2" x="$pos_left" y="1170" style="text-anchor: start;">$consumerTime</text>} if ($flowgconTime);     # Lage Consumer Restlaufzeit
 
          # Verbrauchszahl abhängig von der Größe entsprechend auf der x-Achse verschieben
          # Hackeritis - geht mit Sicherheit auch einfacher/sinnvoller
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

          $ret .= qq{<text class="flowg text" id="consumer-txt_$c2"      x="$pos_left" y="1110">$currentPower</text>} if ($flowgconPower);    # Lage Consumer Consumption
          $ret .= qq{<text class="flowg text" id="consumer-txt_time_$c2" x="$pos_left" y="1170">$consumerTime</text>} if ($flowgconTime);     # Lage Consumer Restlaufzeit

          # Verbrauchszahl abhängig von der Größe entsprechend auf der x-Achse wieder zurück an den Ursprungspunkt
          # Hackeritis - geht mit Sicherheit auch einfacher/sinnvoller
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
sub substConsumerIcon {
  my $hash = shift;
  my $c    = shift;

  my $name = $hash->{NAME};

  my $cicon   = ConsumerVal ($hash, $c, "icon",        "");                  # Icon des Consumerdevices angegeben ?

  if (!$cicon) {
      $cicon = 'light_light_dim_100';
  }

  my $color;
  ($cicon,$color) = split '@', $cicon;

  if (!$color) {
      $color = isConsumerPhysOn($hash, $c) ? 'darkorange' : '';
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

  my $debug = AttrVal ($name, 'ctrlDebug', 'none');

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
  my ($v,$kw,$w) = @_;
  my $n          = '&nbsp;';                                # positive Zahl

  if($v < 0) {
      $n = '-';                                             # negatives Vorzeichen merken
      $v = abs($v);
  }

  if($kw eq 'kWh') {                                        # bei Anzeige in kWh muss weniger aufgefüllt werden
      $v  = sprintf('%.1f',($v/1000));
      $v  += 0;                                             # keine 0.0 oder 6.0 etc

      return ($n eq '-') ? ($v*-1) : $v if defined($w) ;

      my $t = $v - int($v);                                 # Nachkommstelle ?

      if(!$t) {                                             # glatte Zahl ohne Nachkommastelle
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

  return ($n eq '-') ? ($v*-1) : $v if defined($w);

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

return 'unknown','';
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

  Log3 ($name, 2, "$name - $err") if($err);

return $err;
}

################################################################
#       ist Batterie installiert ?
#       1 - ja, 0 - nein
################################################################
sub useBattery {
  my $name   = shift;

  my $badev  = ReadingsVal($name, "currentBatteryDev", "");                  # aktuelles Meter device für Batteriewerte
  my ($a,$h) = parseParams ($badev);
  $badev     = $a->[0] // "";
  return if(!$badev || !$defs{$badev});

return ($badev, $a ,$h);
}

################################################################
#       wird PV Autokorrektur verwendet ?
#       1 - ja, 0 - nein
################################################################
sub useAutoCorrection {
  my $name = shift;

  my $dcauto = ReadingsVal ($name, 'pvCorrectionFactor_Auto', 'off');

  return 1 if($dcauto =~ /^on/xs);

return;
}

################################################################
#  Korrekturen und Qualität berechnen / speichern
#  bei useAutoCorrection
################################################################
sub calcCorrAndQuality {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                              # aktuelle Unix-Zeit

  return if(!useAutoCorrection ($name));                                                # nur bei "on" automatische Varianzkalkulation

  my $idts = ReadingsTimestamp($name, "currentInverterDev", "");                        # Definitionstimestamp des Inverterdevice
  return if(!$idts);

  $idts = timestringToTimestamp ($idts);

  if($t - $idts < 7200) {
      my $rmh = sprintf "%.1f", ((7200 - ($t - $idts)) / 3600);

      Log3 ($name, 4, "$name - Variance calculation in standby. It starts in $rmh hours.");

      readingsSingleUpdate ($hash, "pvCorrectionFactor_Auto", "on (remains in standby for $rmh hours)", 0);
      return;
  }
  else {
      readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", "on", 0);
  }

  _calcCAQfromDWDcloudcover    ($paref);
  _calcCAQwithSolCastPercentil ($paref);

return;
}

################################################################
#  Korrekturfaktoren und Qualität in Abhängigkeit von DWD
#  Bewölkung errechnen:
#  Abweichung PVreal / PVforecast bei eingeschalteter automat.
#  Korrektur berechnen, im Circular Hash speichern
################################################################
sub _calcCAQfromDWDcloudcover {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};

  return if(isSolCastUsed ($hash));

  my $maxvar = AttrVal($name, 'affectMaxDayVariance', $defmaxvar);                                        # max. Korrekturvarianz
  my $debug  = $paref->{debug};

  for my $h (1..23) {
      next if(!$chour || $h > $chour);

      my $fcval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVforecast", 0);
      next if(!$fcval);

      my $pvval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVreal", 0);
      next if(!$pvval);

      my $cdone = ReadingsVal ($name, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc", "");

      if($cdone eq "done") {
          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, "$name DEBUG> pvCorrectionFactor Hour: ".sprintf("%02d",$h)." already calculated");
          }
          
          next;
      }

      $paref->{hour}                  = $h;
      my ($pvhis,$fchis,$dnum,$range) = __avgCloudcoverCorrFromHistory ($paref);                          # historische PV / Forecast Vergleichswerte ermitteln

      my ($oldfac, $oldq) = CircularAutokorrVal ($hash, sprintf("%02d",$h), $range, 0);                   # bisher definierter Korrekturfaktor/KF-Qualität der Stunde des Tages der entsprechenden Bewölkungsrange
      $oldfac             = 1 if(1 * $oldfac == 0);

      my $factor;
      my ($usenhd) = __useNumHistDays ($name);                                                            # ist Attr affectNumHistDays gesetzt ?

      if($dnum) {                                                                                         # Werte in History vorhanden -> haben Prio !
          $dnum   = $dnum + 1;
          $pvval  = ($pvval + $pvhis) / $dnum;                                                            # Ertrag aktuelle Stunde berücksichtigen
          $fcval  = ($fcval + $fchis) / $dnum;                                                            # Vorhersage aktuelle Stunde berücksichtigen
          $factor = sprintf "%.2f", ($pvval / $fcval);                                                    # Faktorberechnung: reale PV / Prognose
      }
      elsif($oldfac && !$usenhd) {                                                                        # keine Werte in History vorhanden, aber in CircularVal && keine Beschränkung durch Attr affectNumHistDays
          $dnum   = $oldq + 1;
          $factor = sprintf "%.2f", ($pvval / $fcval);
          $factor = sprintf "%.2f", ($factor + $oldfac) / 2;
      }
      else {                                                                                              # ganz neuer Wert
          $factor = sprintf "%.2f", ($pvval / $fcval);
          $dnum   = 1;
      }

      if($debug =~ /pvCorrection/x) {
          Log3 ($name, 1, "$name DEBUG> variance -> range: $range, hour: $h, days: $dnum, real: $pvval, forecast: $fcval, factor: $factor");
      }

      if(abs($factor - $oldfac) > $maxvar) {
          $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvar : $oldfac - $maxvar);
          Log3 ($name, 3, "$name - new limited Variance factor: $factor (old: $oldfac) for hour: $h");
      }
      else {
          Log3 ($name, 3, "$name - new Variance factor: $factor (old: $oldfac) for hour: $h calculated") if($factor != $oldfac);
      }

      if(defined $range) {
          my $type = $paref->{type};

          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, "$name DEBUG> write correction factor into circular Hash: Factor $factor, Hour $h, Range $range");
          }

          $data{$type}{$name}{circular}{sprintf("%02d",$h)}{pvcorrf}{$range} = $factor;                  # Korrekturfaktor für Bewölkung Range 0..10 für die jeweilige Stunde als Datenquelle eintragen
          $data{$type}{$name}{circular}{sprintf("%02d",$h)}{quality}{$range} = $dnum;                    # Korrekturfaktor Qualität
      }
      else {
          $range = "";
      }

      push @$daref, "pvCorrectionFactor_".sprintf("%02d",$h)."<>".$factor." (automatic - old factor: $oldfac, cloudiness range: $range, days in range: $dnum)";
      push @$daref, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc<>done";
  }

return;
}

################################################################
#   Berechne Durchschnitte PV Vorhersage / PV Ertrag
#   aus Werten der PV History
################################################################
sub __avgCloudcoverCorrFromHistory {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hour  = $paref->{hour};                                                             # Stunde des Tages für die der Durchschnitt bestimmt werden soll
  my $day   = $paref->{day};                                                              # aktueller Tag

  $hour     = sprintf("%02d",$hour);
  my $debug = $paref->{debug};
  my $pvhh  = $data{$type}{$name}{pvhist};

  my ($usenhd, $calcd) = __useNumHistDays ($name);                                        # ist Attr affectNumHistDays gesetzt ? und welcher Wert

  my @k     = sort {$a<=>$b} keys %{$pvhh};
  my $ile   = $#k;                                                                        # Index letztes Arrayelement
  my ($idx) = grep {$k[$_] eq "$day"} (0..@k-1);                                          # Index des aktuellen Tages

  if(defined $idx) {
      my $ei = $idx-1;
      $ei    = $ei < 0 ? $ile : $ei;
      my @efa;

      for my $e (0..$calcmaxd) {
          last if($e == $calcmaxd || $k[$ei] == $day);
          unshift @efa, $k[$ei];
          $ei--;
      }

      my $chwcc = HistoryVal ($hash, $day, $hour, "wcc", undef);                           # Wolkenbedeckung Heute & abgefragte Stunde

      if(!defined $chwcc) {
          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, "$name DEBUG> Day $day has no cloudiness value set for hour $hour, no past averages can be calculated");
          }
          return;
      }

      my $range = calcRange ($chwcc);                                                      # V 0.50.1

      if(scalar(@efa)) {
          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, "$name DEBUG> PV History -> Raw Days ($calcmaxd) for average check: ".join " ",@efa);
          }
      }
      else {                                                                               # vermeide Fehler: Illegal division by zero
          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, "$name DEBUG> PV History -> Day $day has index $idx. Use only current day for average calc");
          }
          return (undef,undef,undef,$range);
      }

      if($debug =~ /pvCorrection/x) {
          Log3 ($name, 1, "$name DEBUG> PV History -> cloudiness range of day/hour $day/$hour is: $range");
      }

      my $dnum         = 0;
      my ($pvrl,$pvfc) = (0,0);

      for my $dayfa (@efa) {
          my $histwcc = HistoryVal ($hash, $dayfa, $hour, "wcc", undef);                   # historische Wolkenbedeckung

          if(!defined $histwcc) {
              if($debug =~ /pvCorrection/x) {
                  Log3 ($name, 1, "$name DEBUG> PV History -> Day $dayfa has no cloudiness value set for hour $hour, this history dataset is ignored.");
              }
              next;
          }

          $histwcc = calcRange ($histwcc);                                                 # V 0.50.1

          if($range == $histwcc) {
              $pvrl  += HistoryVal ($hash, $dayfa, $hour, "pvrl", 0);
              $pvfc  += HistoryVal ($hash, $dayfa, $hour, "pvfc", 0);
              $dnum++;

              if($debug =~ /pvCorrection/x) {
                  Log3 ($name, 1, "$name DEBUG> PV History -> historical Day/hour $dayfa/$hour included - cloudiness range: $range");
              }

              last if( $dnum == $calcd);
          }
          else {
              if($debug =~ /pvCorrection/x) {
                  Log3 ($name, 1, "$name DEBUG> PV History -> current/historical cloudiness range different: $range/$histwcc Day/hour $dayfa/$hour discarded.");
              }
          }
      }

      if(!$dnum) {
          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, "$name DEBUG> PV History -> all cloudiness ranges were different/not set -> no historical averages calculated");
          }
          return (undef,undef,undef,$range);
      }

      my $pvhis = sprintf "%.2f", $pvrl;
      my $fchis = sprintf "%.2f", $pvfc;

      if($debug =~ /pvCorrection/x) {
          Log3 ($name, 1, "$name DEBUG> PV History -> Summary - cloudiness range: $range, days: $dnum, pvHist:$pvhis, fcHist:$fchis");
      }
      return ($pvhis,$fchis,$dnum,$range);
  }

return;
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
#  PVreal mit den SolCast Forecast vergleichen und den
#  Korrekturfaktor berechnen / speichern
################################################################
sub _calcCAQwithSolCastPercentil {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};                        # aktuelle Stunde
  my $date  = $paref->{date};
  my $daref = $paref->{daref};

  return if(!isSolCastUsed ($hash));

  my $debug = $paref->{debug};

  for my $h (1..23) {
      next if(!$chour || $h > $chour);

      my $pvval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVreal", 0);
      next if(!$pvval);

      my $cdone = ReadingsVal ($name, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc", "");

      if($cdone eq "done") {
          Log3 ($name, 5, "$name - pvCorrectionFactor Hour: ".sprintf("%02d",$h)." already calculated");
          next;
      }

      $paref->{hour}      = $h;
      my ($dnum,$avgperc) = __avgSolCastPercFromHistory ($paref);                                              # historischen Percentilfaktor / Qualität ermitteln

      my ($oldperc, $oldq) = CircularAutokorrVal ($hash, sprintf("%02d",$h), 'percentile', 1.0);               # bisher definiertes Percentil/Qualität der Stunde des Tages der entsprechenden Bewölkungsrange
      $oldperc             = 1.0 if(1 * $oldperc == 0 || $oldperc >= 10);

      my @sts   = split ",", ReadingsVal($name, 'inverterStrings', '');
      my $tmstr = $date.' '.sprintf("%02d",$h-1).':00:00';

      my $est50 = 0;

      for my $s (@sts) {
          $est50 += SolCastAPIVal ($hash, $s, $tmstr, 'pv_estimate50', 0);                                     # Standardpercentil
      }

      if(!$est50) {                                                                                            # kein Standardpercentile vorhanden
          if($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, qq{$name DEBUG> percentile -> hour: $h, the correction factor can't be calculated because of the default percentile has no value yet});
          }
          next;
      }

      my $perc = sprintf "%.2f", ($pvval / $est50);                                                            # berechneter Faktor der Stunde -> speichern in pvHistory

      $paref->{pvcorrf}  = $perc.'/1';                                                                         # Percentilfaktor in History speichern
      $paref->{nhour}    = sprintf("%02d",$h);
      $paref->{histname} = "pvcorrfactor";

      setPVhistory ($paref);

      delete $paref->{histname};
      delete $paref->{nhour};
      delete $paref->{pvcorrf};

      if ($debug =~ /pvCorrection/x) {                                                                                          # nur für Debugging
          Log3 ($name, 1, qq{$name DEBUG> PV estimates for hour of day "$h": $est50});
          Log3 ($name, 1, qq{$name DEBUG> correction factor -> number checked days: $dnum, pvreal: $pvval, correction factor: $perc});
      }

      my ($usenhd) = __useNumHistDays ($name);                                                               # ist Attr affectNumHistDays gesetzt ?

      if($dnum) {                                                                                            # Werte in History vorhanden -> haben Prio !
          $avgperc = $avgperc * $dnum;
          $dnum++;
          $perc    = sprintf "%.2f", (($avgperc + $perc) / $dnum);

          if ($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, qq{$name DEBUG> percentile -> old avg correction: }.($avgperc/($dnum-1)).qq{, new avg correction: }.$perc);
          }
      }
      elsif($oldperc && !$usenhd) {                                                                          # keine Werte in History vorhanden, aber in CircularVal && keine Beschränkung durch Attr affectNumHistDays
          $oldperc = $oldperc * $oldq;
          $dnum    = $oldq + 1;
          $perc    = sprintf "%.0f", (($oldperc + $perc) / $dnum);

          if ($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, qq{$name DEBUG> percentile -> old circular correction: }.($oldperc/$oldq).qq{, new correction: }.$perc);
          }
      }
      else {                                                                                                 # ganz neuer Wert
          $dnum = 1;

          if ($debug =~ /pvCorrection/x) {
              Log3 ($name, 1, qq{$name DEBUG> percentile -> new correction factor: }.$perc);
          }
      }

      if($debug =~ /saveData2Cache/x) {
          Log3 ($name, 1, "$name DEBUG> write correction factor into circular Hash: $perc, Hour $h");
      }

      my $type = $paref->{type};

      $data{$type}{$name}{circular}{sprintf("%02d",$h)}{pvcorrf}{percentile} = $perc;                        # bestes Percentil für die jeweilige Stunde speichern
      $data{$type}{$name}{circular}{sprintf("%02d",$h)}{quality}{percentile} = $dnum;                        # Percentil Qualität

      push @$daref, "pvCorrectionFactor_".sprintf("%02d",$h)."<>".$perc." (automatic - old factor: $oldperc, average days: $dnum)";
      push @$daref, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc<>done";
  }

return;
}

################################################################
#   Berechne das durchschnittlich verwendete Percentil
#   aus Werten der PV History
################################################################
sub __avgSolCastPercFromHistory {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hour  = $paref->{hour};                                                             # Stunde des Tages für die der Durchschnitt bestimmt werden soll
  my $day   = $paref->{day};                                                              # aktueller Tag

  $hour     = sprintf("%02d",$hour);
  my $debug = $paref->{debug};
  my $pvhh  = $data{$type}{$name}{pvhist};

  my ($usenhd, $calcd) = __useNumHistDays ($name);                                        # ist Attr affectNumHistDays gesetzt ? und welcher Wert

  my @k     = sort {$a<=>$b} keys %{$pvhh};
  my $ile   = $#k;                                                                        # Index letztes Arrayelement
  my ($idx) = grep {$k[$_] eq "$day"} (0..@k-1);                                          # Index des aktuellen Tages

  return 0 if(!defined $idx);

  my $ei = $idx-1;
  $ei    = $ei < 0 ? $ile : $ei;
  my @efa;

  for my $e (0..$calcmaxd) {
      last if($e == $calcmaxd || $k[$ei] == $day);
      unshift @efa, $k[$ei];
      $ei--;
  }

  if(scalar(@efa)) {
      if($debug =~ /pvCorrection/x) {
          Log3 ($name, 1, "$name DEBUG> PV History -> Raw Days ($calcmaxd) for average check: ".join " ",@efa);
      }
  }
  else {                                                                               # vermeide Fehler: Illegal division by zero
      if($debug =~ /pvCorrection/x) {
          Log3 ($name, 1, "$name DEBUG> PV History -> Day $day has index $idx. Use only current day for average calc");
      }
      return 0;
  }

  my ($dnum, $percsum) = (0,0);
  my ($perc, $qual)    = (1,0);

  for my $dayfa (@efa) {
      my $histval = HistoryVal ($hash, $dayfa, $hour, 'pvcorrf', undef);               # historischen Percentilfaktor/Qualität

      next if(!defined $histval);

      ($perc, $qual) = split "/", $histval;                                            # Percentilfaktor und Qualität splitten

      next if(!$perc || $qual eq 'm');                                                 # manuell eingestellte Percentile überspringen

      $perc = 1 if(!$perc || $perc >= 10);

      if($debug =~ /pvCorrection/x) {
          Log3 ($name, 1, "$name DEBUG> PV History -> historical Day/hour $dayfa/$hour included - percentile factor: $perc");
      }

      $dnum++;
      $percsum += $perc ;

      last if($dnum == $calcd);
  }

  if(!$dnum) {
      Log3 ($name, 5, "$name - PV History -> no historical percentile factor selected");
      return 0;
  }

  $perc = sprintf "%.2f", ($percsum/$dnum);

  if($debug =~ /pvCorrection/x) {
      Log3 ($name, 1, "$name DEBUG> PV History -> Summary - days: $dnum, average percentile factor: $perc");
  }

return ($dnum,$perc);
}

################################################################
#            Bewölkungs- bzw. Regenrange berechnen
################################################################
sub calcRange {
  my $range = shift;

  #$range = sprintf "%.0f", $range/10;
  $range = sprintf "%.0f", $range;

return $range;
}

################################################################
#   PV und PV Forecast in History-Hash speichern zur
#   Berechnung des Korrekturfaktors über mehrere Tage
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
  my $ethishour      = $paref->{ethishour}     // 0;
  my $etotal         = $paref->{etotal};
  my $batinthishour  = $paref->{batinthishour};                            # Batterieladung in Stunde
  my $btotin         = $paref->{batintotal};                               # totale Batterieladung
  my $batoutthishour = $paref->{batoutthishour};                           # Batterieentladung in Stunde
  my $btotout        = $paref->{batouttotal};                              # totale Batterieentladung
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

  my $type = $hash->{TYPE};

  $data{$type}{$name}{pvhist}{$day}{99}{dayname} = $dayname;

  if($histname eq "batinthishour") {                                                              # Batterieladung
      $val = $batinthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batin} = $batinthishour;

      my $batinsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $batinsum += HistoryVal ($hash, $day, $k, "batin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{batin} = $batinsum;
  }

  if($histname eq "batoutthishour") {                                                             # Batterieentladung
      $val = $batoutthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batout} = $batoutthishour;

      my $batoutsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $batoutsum += HistoryVal ($hash, $day, $k, "batout", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{batout} = $batoutsum;
  }

  if($histname eq "pvrl") {                                                                       # realer Energieertrag
      $val = $ethishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvrl} = $ethishour;

      my $pvrlsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvrlsum += HistoryVal ($hash, $day, $k, "pvrl", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvrl} = $pvrlsum;
  }

  if($histname eq "pvfc") {                                                                       # prognostizierter Energieertrag
      $val = $calcpv;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvfc} = $calcpv;

      my $pvfcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvfcsum += HistoryVal ($hash, $day, $k, "pvfc", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvfc} = $pvfcsum;
  }

  if($histname eq "confc") {                                                                       # prognostizierter Hausverbrauch
      $val = $confc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{confc} = $confc;

      my $confcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $confcsum += HistoryVal ($hash, $day, $k, "confc", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{confc} = $confcsum;
  }

  if($histname eq "cons") {                                                                       # bezogene Energie
      $val = $gcthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gcons} = $gcthishour;

      my $gcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gcsum += HistoryVal ($hash, $day, $k, "gcons", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gcons} = $gcsum;
  }

  if($histname eq "gfeedin") {                                                                    # eingespeiste Energie
      $val = $fithishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gfeedin} = $fithishour;

      my $gfisum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gfisum += HistoryVal ($hash, $day, $k, "gfeedin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gfeedin} = $gfisum;
  }

  if($histname eq "con") {                                                                       # Energieverbrauch des Hauses
      $val = $con;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{con} = $con;

      my $consum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $consum += HistoryVal ($hash, $day, $k, "con", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{con} = $consum;
  }

  if($histname =~ /csm[et][0-9]+$/xs) {                                                          # Verbrauch eines Verbrauchers
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

          $data{$type}{$name}{pvhist}{$day}{99}{$histname} = $sum;
      }
  }

  if($histname =~ /cyclescsm[0-9]+$/xs) {                                                          # Anzahl Tageszyklen des Verbrauchers
      $data{$type}{$name}{pvhist}{$day}{99}{$histname} = $val;
  }

  if($histname =~ /minutescsm[0-9]+$/xs) {                                                         # Anzahl Aktivminuten des Verbrauchers
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
      $data{$type}{$name}{pvhist}{$day}{99}{"hourscsme${num}"} = ceil ($minutes / 60 ) if($cycles);
  }

  if($histname eq "etotal") {                                                                     # etotal des Wechselrichters
      $val = $etotal;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{etotal} = $etotal;
      $data{$type}{$name}{pvhist}{$day}{99}{etotal}     = q{};
  }

  if($histname eq "batintotal") {                                                                 # totale Batterieladung
      $val = $btotin;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batintotal} = $btotin;
      $data{$type}{$name}{pvhist}{$day}{99}{batintotal}     = q{};
  }

  if($histname eq "batouttotal") {                                                                # totale Batterieentladung
      $val = $btotout;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batouttotal} = $btotout;
      $data{$type}{$name}{pvhist}{$day}{99}{batouttotal}     = q{};
  }

  if($histname eq "weatherid") {                                                                  # Wetter ID
      $val = $wid;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{weatherid} = $wid;
      $data{$type}{$name}{pvhist}{$day}{99}{weatherid}     = q{};
  }

  if($histname eq "weathercloudcover") {                                                          # Wolkenbedeckung
      $val = $wcc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wcc} = $wcc;
      $data{$type}{$name}{pvhist}{$day}{99}{wcc}     = q{};
  }

  if($histname eq "weatherrainprob") {                                                            # Niederschlagswahrscheinlichkeit
      $val = $wrp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wrp} = $wrp;
      $data{$type}{$name}{pvhist}{$day}{99}{wrp}     = q{};
  }

  if($histname eq "pvcorrfactor") {                                                               # pvCorrectionFactor
      $val = $pvcorrf;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvcorrf} = $pvcorrf;
      $data{$type}{$name}{pvhist}{$day}{99}{pvcorrf}     = q{};
  }

  if($histname eq "temperature") {                                                                # Außentemperatur
      $val = $temp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{temp} = $temp;
      $data{$type}{$name}{pvhist}{$day}{99}{temp}     = q{};
  }

  my $debug = $paref->{debug};
  if($debug =~ /saveData2Cache/x) {
      Log3 ($name, 1, "$name DEBUG> save PV History Day: $day, Hour: $nhour, Key: $histname, Value: $val");
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

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my ($sq,$h);

  my $sub = sub {
      my $day = shift;
      my $ret;
      for my $key (sort{$a<=>$b} keys %{$h->{$day}}) {
          my $pvrl    = HistoryVal ($hash, $day, $key, "pvrl",        "-");
          my $pvfc    = HistoryVal ($hash, $day, $key, "pvfc",        "-");
          my $gcon    = HistoryVal ($hash, $day, $key, "gcons",       "-");
          my $con     = HistoryVal ($hash, $day, $key, "con",         "-");
          my $confc   = HistoryVal ($hash, $day, $key, "confc",       "-");
          my $gfeedin = HistoryVal ($hash, $day, $key, "gfeedin",     "-");
          my $wid     = HistoryVal ($hash, $day, $key, "weatherid",   "-");
          my $wcc     = HistoryVal ($hash, $day, $key, "wcc",         "-");
          my $wrp     = HistoryVal ($hash, $day, $key, "wrp",         "-");
          my $temp    = HistoryVal ($hash, $day, $key, "temp",      undef);
          my $pvcorrf = HistoryVal ($hash, $day, $key, "pvcorrf",     "-");
          my $dayname = HistoryVal ($hash, $day, $key, "dayname",   undef);
          my $etotal  = HistoryVal ($hash, $day, $key, "etotal",      "-");
          my $btotin  = HistoryVal ($hash, $day, $key, "batintotal",  "-");
          my $batin   = HistoryVal ($hash, $day, $key, "batin",       "-");
          my $btotout = HistoryVal ($hash, $day, $key, "batouttotal", "-");
          my $batout  = HistoryVal ($hash, $day, $key, "batout",      "-");

          $ret .= "\n      " if($ret);
          $ret .= $key." => etotal: $etotal, pvfc: $pvfc, pvrl: $pvrl";
          $ret .= "\n            ";
          $ret .= "confc: $confc, con: $con, gcon: $gcon, gfeedin: $gfeedin";
          $ret .= "\n            ";
          $ret .= "batintotal: $btotin, batin: $batin, batouttotal: $btotout, batout: $batout";
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
      for my $idx (sort{$a<=>$b} keys %{$h}) {
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
              Log3 ($name, 3, qq{$name - INFO - invalid consumer key "$i" was deleted from consumer Hash});
          }
      }

      for my $idx (sort{$a<=>$b} keys %{$h}) {
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
          my $pvfc     = CircularVal ($hash, $idx, "pvfc",       "-");
          my $pvrl     = CircularVal ($hash, $idx, "pvrl",       "-");
          my $confc    = CircularVal ($hash, $idx, "confc",      "-");
          my $gcons    = CircularVal ($hash, $idx, "gcons",      "-");
          my $gfeedin  = CircularVal ($hash, $idx, "gfeedin",    "-");
          my $wid      = CircularVal ($hash, $idx, "weatherid",  "-");
          my $wtxt     = CircularVal ($hash, $idx, "weathertxt", "-");
          my $wccv     = CircularVal ($hash, $idx, "wcc",        "-");
          my $wrprb    = CircularVal ($hash, $idx, "wrp",        "-");
          my $temp     = CircularVal ($hash, $idx, "temp",       "-");
          my $pvcorrf  = CircularVal ($hash, $idx, "pvcorrf",    "-");
          my $quality  = CircularVal ($hash, $idx, "quality",    "-");
          my $batin    = CircularVal ($hash, $idx, "batin",      "-");
          my $batout   = CircularVal ($hash, $idx, "batout",     "-");
          my $tdayDvtn = CircularVal ($hash, $idx, "tdayDvtn",   "-");
          my $ydayDvtn = CircularVal ($hash, $idx, "ydayDvtn",   "-");

          my $pvcf = qq{};
          if(ref $pvcorrf eq "HASH") {
              for my $f (sort keys %{$h->{$idx}{pvcorrf}}) {
                  $pvcf .= " " if($pvcf);
                  $pvcf .= "$f=".$h->{$idx}{pvcorrf}{$f};
                  my $ct = ($pvcf =~ tr/=// // 0) / 10;
                  $pvcf .= "\n           " if($ct =~ /^([1-9])?$/);
              }
          }
          else {
              $pvcf = $pvcorrf;
          }

          my $cfq = qq{};
          if(ref $quality eq "HASH") {
              for my $q (sort {$a<=>$b} keys %{$h->{$idx}{quality}}) {
                  $cfq   .= " " if($cfq);
                  $cfq   .= "$q=".$h->{$idx}{quality}{$q};
                  my $ct1 = ($cfq =~ tr/=// // 0) / 10;
                  $cfq   .= "\n              " if($ct1 =~ /^([1-9])?$/);
              }
          }
          else {
              $cfq = $quality;
          }

          $sq .= "\n" if($sq);

          if($idx != 99) {
              $sq .= $idx." => pvfc: $pvfc, pvrl: $pvrl, batin: $batin, batout: $batout\n";
              $sq .= "      confc: $confc, gcon: $gcons, gfeedin: $gfeedin, wcc: $wccv, wrp: $wrprb\n";
              $sq .= "      temp: $temp, wid: $wid, wtxt: $wtxt\n";
              $sq .= "      corr: $pvcf\n";
              $sq .= "      quality: $cfq";
          }
          else {
              $sq .= $idx." => tdayDvtn: $tdayDvtn, ydayDvtn: $ydayDvtn";
          }
      }
  }

  if ($htol eq "nexthours") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhts    = NexthoursVal ($hash, $idx, "starttime",  "-");
          my $hod     = NexthoursVal ($hash, $idx, "hourofday",  "-");
          my $today   = NexthoursVal ($hash, $idx, "today",      "-");
          my $pvfc    = NexthoursVal ($hash, $idx, "pvforecast", "-");
          my $wid     = NexthoursVal ($hash, $idx, "weatherid",  "-");
          my $neff    = NexthoursVal ($hash, $idx, "cloudcover", "-");
          my $crange  = NexthoursVal ($hash, $idx, "cloudrange", "-");
          my $r101    = NexthoursVal ($hash, $idx, "rainprob",   "-");
          my $rad1h   = NexthoursVal ($hash, $idx, "Rad1h",      "-");
          my $pvcorrf = NexthoursVal ($hash, $idx, "pvcorrf",    "-");
          my $temp    = NexthoursVal ($hash, $idx, "temp",       "-");
          my $confc   = NexthoursVal ($hash, $idx, "confc",      "-");
          my $confcex = NexthoursVal ($hash, $idx, "confcEx",    "-");
          $sq        .= "\n" if($sq);
          $sq        .= $idx." => starttime: $nhts, hourofday: $hod, today: $today\n";
          $sq        .= "              pvfc: $pvfc, confc: $confc, confcEx: $confcex\n";
          $sq        .= "              wid: $wid, wcc: $neff, wrp: $r101, temp=$temp\n";
          $sq        .= "              Rad1h: $rad1h, crange: $crange, correff: $pvcorrf";
      }
  }

  if ($htol eq "qualities") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhfc    = NexthoursVal ($hash, $idx, "pvforecast", undef);
          next if(!$nhfc);
          my $nhts    = NexthoursVal ($hash, $idx, "starttime",  undef);
          my $neff    = NexthoursVal ($hash, $idx, "cloudcover",   "-");
          my $crange  = NexthoursVal ($hash, $idx, "cloudrange",   "-");
          my $pvcorrf = NexthoursVal ($hash, $idx, "pvcorrf",    "-/-");
          my ($f,$q)  = split "/", $pvcorrf;
          $sq        .= "\n" if($sq);
          $sq        .= "starttime: $nhts, wcc: $neff, crange: $crange, quality: $q, used factor: $f";
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

  if ($htol eq "solcastdata") {
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
  my $lang = AttrVal ($name, 'ctrlLanguage', AttrVal ('global', 'language', $deflang));
  my $cf   = 0;                                                                                     # config fault: 1 -> Konfig fehlerhaft, 0 -> Konfig ok
  my $wn   = 0;                                                                                     # Warnung wenn 1
  my $io   = 0;                                                                                     # Info wenn 1
  
  my $ok   = FW_makeImage('10px-kreis-gruen.png',     '');
  my $nok  = FW_makeImage('10px-kreis-rot.png',       '');
  my $warn = FW_makeImage('message_attention@orange', '');
  my $info = FW_makeImage('message_info',             '');

  my $result = {                                                                                    # Ergebnishash
      'String Configuration'     => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
      'DWD Weather Attributes'   => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
      'Common Settings'          => { 'state' => $ok, 'result' => '', 'note' => '', 'info' => 0, 'warn' => 0, 'fault' => 0 },
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

      if (!isSolCastUsed ($hash)) {                                                             # Strahlungsdevice DWD
          if ($sp !~ /dir.*?peak.*?tilt/x) {
              $result->{'String Configuration'}{state}  = $nok;
              $result->{'String Configuration'}{fault}  = 1;                                    # Test Vollständigkeit: z.B. Süddach => dir: S, peak: 5.13, tilt: 45
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
  my $fcname = ReadingsVal($name, 'currentForecastDev', '');

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
  if (!isSolCastUsed ($hash)) {
      $result->{'DWD Radiation Attributes'}{state}  = $ok;
      $result->{'DWD Radiation Attributes'}{result} = '';
      $result->{'DWD Radiation Attributes'}{note}   = '';
      $result->{'DWD Radiation Attributes'}{fault}  = 0;

      my $raname = ReadingsVal($name, 'currentRadiationDev', '');

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
  my $eocr    = AttrVal ($name, 'event-on-change-reading', '');
  my $einstds = "";

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

  ## allg. Settings bei Nutzung SolCast
  #######################################
  if (isSolCastUsed ($hash)) {
      my $gdn = AttrVal     ('global', 'dnsServer',                   '');
      my $cfd = AttrVal     ($name,    'affectCloudfactorDamping',    '');
      my $rfd = AttrVal     ($name,    'affectRainfactorDamping',     '');
      my $osi = AttrVal     ($name,    'ctrlOptimizeSolCastInterval',  0);
      my $pcf = ReadingsVal ($name,    'pvCorrectionFactor_Auto',     '');

      my $lam = SolCastAPIVal ($hash, '?All', '?All', 'response_message', 'success');

      if (!$pcf || $pcf ne 'on') {
          $result->{'Common Settings'}{state}   = $info;
          $result->{'Common Settings'}{result} .= qq{pvCorrectionFactor_Auto is set to "$pcf" <br>};
          $result->{'Common Settings'}{note}   .= qq{set pvCorrectionFactor_Auto to "on" is recommended if the SolCast efficiency factor is already adjusted.<br>};
      }

      if ($cfd eq '' || $cfd != 0) {
          $result->{'Common Settings'}{state}   = $warn;
          $result->{'Common Settings'}{result} .= qq{Attribute affectCloudfactorDamping is set to "$cfd" <br>};
          $result->{'Common Settings'}{note}   .= qq{set affectCloudfactorDamping explicitly to "0" is recommended.<br>};
          $result->{'Common Settings'}{warn}    = 1;
      }

      if ($rfd eq '' || $rfd != 0) {
          $result->{'Common Settings'}{state}   = $warn;
          $result->{'Common Settings'}{result} .= qq{Attribute affectRainfactorDamping is set to "$rfd" <br>};
          $result->{'Common Settings'}{note}   .= qq{set affectRainfactorDamping explicitly to "0" is recommended.<br>};
          $result->{'Common Settings'}{warn}    = 1;
      }

      if (!$osi) {
          $result->{'Common Settings'}{state}   = $warn;
          $result->{'Common Settings'}{result} .= qq{Attribute ctrlOptimizeSolCastInterval is set to "$osi" <br>};
          $result->{'Common Settings'}{note}   .= qq{set ctrlOptimizeSolCastInterval to "1" is recommended.<br>};
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

      if(!$result->{'Common Settings'}{fault} && !$result->{'Common Settings'}{warn} && !$result->{'Common Settings'}{info}) {
          $result->{'Common Settings'}{result}  = $hqtxt{fulfd}{$lang};
          $result->{'Common Settings'}{note}   .= qq{checked parameters: <br>};
          $result->{'Common Settings'}{note}   .= qq{affectCloudfactorDamping, affectRainfactorDamping, ctrlOptimizeSolCastInterval <br>};
          $result->{'Common Settings'}{note}   .= qq{pvCorrectionFactor_Auto, event-on-change-reading, ctrlLanguage, global language <br>};
      }
  }

  ## allg. Settings bei Nutzung DWD Radiation
  #############################################
  if (!isSolCastUsed ($hash)) {
      my $pcf = ReadingsVal ($name, 'pvCorrectionFactor_Auto', '');

       if (!$pcf || $pcf ne 'on') {
          $result->{'Common Settings'}{state}   = $warn;
          $result->{'Common Settings'}{result} .= qq{pvCorrectionFactor_Auto is set to "$pcf" <br>};
          $result->{'Common Settings'}{note}   .= qq{set pvCorrectionFactor_Auto to "on" is recommended<br>};
          $result->{'Common Settings'}{warn}    = 1;
      }

      if(!$result->{'Common Settings'}{warn} && !$result->{'Common Settings'}{info}) {
          $result->{'Common Settings'}{result}  = $hqtxt{fulfd}{$lang};
          $result->{'Common Settings'}{note}   .= qq{checked parameters: <br>};
          $result->{'Common Settings'}{note}   .= qq{pvCorrectionFactor_Auto, event-on-change-reading, ctrlLanguage, global language <br>};
      }
  }

  ## Ausgabe
  ############

  my $out  = qq{<html>};
  $out    .= qq{<b>}.$hqtxt{plntck}{$lang}.qq{</b> <br><br>};

  $out    .= qq{<table class="roomoverview" style="text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;">};
  $out    .= qq{<tr style="font-weight:bold;">};
  $out    .= qq{<td style="text-decoration:underline; padding: 5px;"> Object </td>};
  $out    .= qq{<td style="text-decoration:underline;"> State </td>};
  $out    .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>};
  $out    .= qq{<td style="text-decoration:underline;"> Result </td>};
  $out    .= qq{<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>};
  $out    .= qq{<td style="text-decoration:underline;"> Note </td>};
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
################################################################
sub timestampToTimestring {
  my $epoch = shift;
  my $lang  = shift;

  my ($lyear,$lmonth,$lday,$lhour,$lmin,$lsec) = (localtime($epoch))[5,4,3,2,1,0];
  my $ts;

  $lyear += 1900;                                                                             # year is 1900 based
  $lmonth++;                                                                                  # month number is zero based

  my ($sec,$min,$hour,$day,$mon,$year) = (localtime(time))[0,1,2,3,4,5];                      # Standard f. z.B. Readingstimstamp
  $year += 1900;
  $mon++;

  my $realts = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year,$mon,$day,$hour,$min,$sec);
  my $tsdef  = sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,"00:00");             # engl. Variante für Logging-Timestamps etc. (Minute/Sekunde == 00)
  my $tsfull = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $lyear,$lmonth,$lday,$lhour,$lmin,$lsec);  # engl. Variante Vollzeit

  if($lang eq "DE") {
      $ts = sprintf("%02d.%02d.%04d %02d:%02d:%02d", $lday,$lmonth,$lyear,$lhour,$lmin,$lsec);
  }
  else {
      $ts = $tsdef;
  }

return ($ts, $tsdef, $realts, $tsfull);
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
#                   Readings aus Array erstellen
#       $daref:  Referenz zum Array der zu erstellenden Readings
#                muß Paare <Readingname>:<Wert> enthalten
#       $doevt:  1-Events erstellen, 0-keine Events erstellen
#
# readingsBulkUpdate($hash,$reading,$value,$changed,$timestamp)
#
################################################################
sub createReadingsFromArray {
  my $hash  = shift;
  my $daref = shift;
  my $doevt = shift // 0;

  return if(!scalar @$daref);

  readingsBeginUpdate($hash);

  for my $elem (@$daref) {
      my ($rn,$rval,$ts) = split "<>", $elem, 3;
      readingsBulkUpdate ($hash, $rn, $rval, undef, $ts);
  }

  readingsEndUpdate($hash, $doevt);

  undef @$daref;

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
#    alle Readings eines Devices oder nur Reading-Regex
#    löschen
################################################################
sub deleteReadingspec {
  my $hash = shift;
  my $spec = shift // ".*";

  my $readingspec = '^'.$spec.'$';

  for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
      readingsDelete($hash, $reading);
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

  if($init_done == 1) {
      my @nd;
      my ($afc,$ara,$ain,$ame,$aba,$h);

      my $fcdev = ReadingsVal($name, "currentForecastDev",  "");             # Weather forecast Device
      ($afc,$h) = parseParams ($fcdev);
      $fcdev    = $afc->[0] // "";

      my $radev = ReadingsVal($name, "currentRadiationDev", "");             # Radiation forecast Device
      ($ara,$h) = parseParams ($radev);
      $radev    = $ara->[0] // "";

      my $indev = ReadingsVal($name, "currentInverterDev",  "");             # Inverter Device
      ($ain,$h) = parseParams ($indev);
      $indev    = $ain->[0] // "";

      my $medev = ReadingsVal($name, "currentMeterDev",     "");             # Meter Device
      ($ame,$h) = parseParams ($medev);
      $medev    = $ame->[0] // "";

      my $badev = ReadingsVal($name, "currentBatteryDev",   "");             # Battery Device
      ($aba,$h) = parseParams ($badev);
      $badev    = $aba->[0] // "";

      for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {     # Consumer Devices
          my $codev    = AttrVal($name, "consumer${c}", "");
          my ($ac,$hc) = parseParams ($codev);
          $codev       = $ac->[0] // "";

          push @nd, $codev if($codev);
      }

      push @nd, $fcdev;
      push @nd, $radev if($radev ne $fcdev && $radev !~ /SolCast-API/xs);
      push @nd, $indev;
      push @nd, $medev;
      push @nd, $badev;

      if(@nd) {
          # $hash->{NOTIFYDEV} = join ",", @nd;                                   # zur Zeit nicht benutzt
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

  if (isSolCastUsed ($hash)) {
      $hash->{MODEL} = 'SolCastAPI';
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
#  Funktion liefert 1 wenn Consumer physisch "eingeschaltet"
#  ist, d.h. der Wert onreg des Readings rswstate wahr ist
################################################################
sub isConsumerPhysOn {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};

  my $cname = ConsumerVal ($hash, $c, "name", "");                       # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the "on" state can't be identified});
      return 0;
  }

  my $reg      = ConsumerVal ($hash, $c, "onreg",       "on");
  my $rswstate = ConsumerVal ($hash, $c, "rswstate", "state");           # Reading mit Schaltstatus
  my $swstate  = ReadingsVal ($cname, $rswstate,     "undef");

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

  my $cname = ConsumerVal ($hash, $c, "name", "");                       # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the "off" state can't be identified});
      return 0;
  }

  my $reg      = ConsumerVal ($hash, $c, "offreg",     "off");
  my $rswstate = ConsumerVal ($hash, $c, "rswstate", "state");           # Reading mit Schaltstatus
  my $swstate  = ReadingsVal ($cname, $rswstate,     "undef");

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
  my $nompower   = ConsumerVal ($hash, $c, "power",           0);                          # nominale Leistung lt. Typenschild
  my $rpcurr     = ConsumerVal ($hash, $c, "rpcurr",         "");                          # Reading für akt. Verbrauch angegeben ?
  my $ethreshold = ConsumerVal ($hash, $c, "energythreshold", 0);                          # Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird

  if (!$rpcurr && isConsumerPhysOn($hash, $c)) {                                           # Workaround wenn Verbraucher ohne Leistungsmessung
      $pcurr = $nompower;
  }

  my $currpowerpercent = $pcurr;
  $currpowerpercent    = ($pcurr / $nompower) * 100 if($nompower > 0);

  $data{$type}{$name}{consumers}{$c}{currpowerpercent} = $currpowerpercent;

  if($pcurr > $ethreshold || $currpowerpercent > $defpopercent) {                          # Verbraucher ist logisch aktiv
      return 1;
  }

return 0;
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

  my $dswoncond = ConsumerVal ($hash, $c, "dswoncond", "");                     # Device zur Lieferung einer zusätzlichen Einschaltbedingung

  if($dswoncond && !$defs{$dswoncond}) {
      $err = qq{ERROR - the device "$dswoncond" doesn't exist! Check the key "swoncond" in attribute "consumer${c}"};
      return (0, $info, $err);
  }

  my $rswoncond     = ConsumerVal ($hash, $c, "rswoncond",     "");             # Reading zur Lieferung einer zusätzlichen Einschaltbedingung
  my $swoncondregex = ConsumerVal ($hash, $c, "swoncondregex", "");             # Regex einer zusätzliche Einschaltbedingung
  my $condval       = ReadingsVal ($dswoncond, $rswoncond,     "");             # Wert zum Vergleich mit Regex

  if ($condval =~ m/^$swoncondregex$/x) {
      return (1, $info, $err);
  }

  $info = qq{The device "$dswoncond", reading "$rswoncond" doen't match the Regex "$swoncondregex"};

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

  my $info           = q{};
  my $err            = q{};
  my $dswoffcond     = q{};                                                       # Device zur Lieferung einer Ausschaltbedingung
  my $rswoffcond     = q{};                                                       # Reading zur Lieferung einer Ausschaltbedingung
  my $swoffcondregex = q{};                                                       # Regex der Ausschaltbedingung (wenn wahr)

  if ($cond) {
      ($dswoffcond,$rswoffcond,$swoffcondregex) = split ":", $cond;
  }
  else {
      $dswoffcond     = ConsumerVal ($hash, $c, "dswoffcond",     "");
      $rswoffcond     = ConsumerVal ($hash, $c, "rswoffcond",     "");
      $swoffcondregex = ConsumerVal ($hash, $c, "swoffcondregex", "");
  }

  if($dswoffcond && !$defs{$dswoffcond}) {
      $err = qq{ERROR - the device "$dswoffcond" doesn't exist! Check the key "swoffcond" or "interruptable" in attribute "consumer${c}"};
      return (0, $info, $err);
  }

  my $condval = ReadingsVal ($dswoffcond, $rswoffcond, "");

  if ($hyst && isNumeric ($condval)) {                                            # Hysterese berücksichtigen
      $condval -= $hyst;
  }

  if ($condval && $condval =~ m/^$swoffcondregex$/x) {
      $info = qq{value "$condval" (hysteresis = $hyst) match the Regex "$swoffcondregex" \n}.
              qq{-> Switch-off condition or interrupt in the "switch-off context", DO NOT switch on or DO NOT continue in the "switch-on context"\n}
              ;
      return (1, $info, $err);
  }

  $info = qq{device: "$dswoffcond", reading: "$rswoffcond" , value: "$condval" (hysteresis = $hyst) doesn't match Regex: "$swoffcondregex" \n}.
          qq{-> DO NOT Switch-off or DO NOT interrupt in the "switch-off context", Switching on or continuing in the "switch-on" context\n}
          ;

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
#  liefert den Status "Consumption Recommended" von Consumer $c
################################################################
sub isConsRcmd {
  my $hash = shift;
  my $c    = shift;

return ConsumerVal ($hash, $c, 'isConsumptionRecommended', 0);
}

################################################################
#  ist Consumer $c unterbrechbar (1|2) oder nicht (0|3)
################################################################
sub isInterruptable {
  my $hash = shift;
  my $c    = shift;
  my $hyst = shift // 0;

  my $name    = $hash->{NAME};
  my $intable = ConsumerVal ($hash, $c, 'interruptable', 0);

  if ($intable eq '0') {
      return 0;
  }
  elsif ($intable eq '1') {
      return 1;
  }

  my $debug = AttrVal ($name, 'ctrlDebug', 'none');

  my ($swoffcond,$info,$err) = isAddSwitchOffCond ($hash, $c, $intable, $hyst);
  Log3 ($name, 1, "$name - $err") if($err);

  if ($debug =~ /consumerSwitching/x) {                                                   # nur für Debugging
      Log3 ($name, 1, qq{$name DEBUG> consumer "$c" - isInterruptable Info: $info});
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
#  Prüfung auf Verwendung von SolCast API
################################################################
sub isSolCastUsed {
  my $hash = shift;

  my $api = ReadingsVal ($hash->{NAME}, 'currentRadiationDev', 'DWD');
  my $ret = 0;

  if($api =~ /SolCast/xs) {
      $ret = 1;
  }

return $ret;
}


################################################################
#  liefert die Zeit des letzten Schaltvorganges
################################################################
sub lastConsumerSwitchtime {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};

  my $cname = ConsumerVal ($hash, $c, "name", "");                             # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the last switching time can't be identified});
      return;
  }

  my $rswstate = ConsumerVal           ($hash, $c, "rswstate", "state");       # Reading mit Schaltstatus
  my $swtime   = ReadingsTimestamp     ($cname, $rswstate,          "");       # Zeitstempel im Format 2016-02-16 19:34:24
  my $swtimets = timestringToTimestamp ($swtime) if($swtime);                  # Unix Timestamp Format erzeugen

return ($swtime, $swtimets);
}

################################################################
#  transformiert den ausführlichen Consumerstatus in eine
#  einfache Form
################################################################
sub simplifyCstate {
  my $ps = shift;

  $ps = $ps =~ /planned/xs        ? 'planned'      :
        $ps =~ /no\splanning/xs   ? 'suspended'    :
        $ps =~ /switching\son/xs  ? 'starting'     :
        $ps =~ /switched\son/xs   ? 'started'      :
        $ps =~ /switching\soff/xs ? 'stopping'     :
        $ps =~ /switched\soff/xs  ? 'finished'     :
        $ps =~ /priority/xs       ? 'priority'     :
        $ps =~ /interrupting/xs   ? 'interrupting' :
        $ps =~ /interrupted/xs    ? 'interrupted'  :
        $ps =~ /continuing/xs     ? 'continuing'   :
        $ps =~ /continued/xs      ? 'continued'    :
        "unknown";

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

#############################################################################
#    Wert des circular-Hash zurückliefern
#    Achtung: die Werte im circular-Hash haben nicht
#             zwingend eine Beziehung zueinander !!
#
#    Usage:
#    CircularVal ($hash, $hod, $key, $def)
#
#    $hod: Stunde des Tages (01,02,...,24)
#    $key:    pvrl       - realer PV Ertrag
#             pvfc       - PV Vorhersage
#             confc      - Vorhersage Hausverbrauch (Wh)
#             gcons      - realer Netzbezug
#             gfeedin    - reale Netzeinspeisung
#             batin      - Batterieladung (Wh)
#             batout     - Batterieentladung (Wh)
#             weatherid  - DWD Wetter id
#             weathertxt - DWD Wetter Text
#             wcc        - DWD Wolkendichte
#             wrp        - DWD Regenwahrscheinlichkeit
#             temp       - Außentemperatur
#             pvcorrf    - PV Autokorrekturfaktoren (HASH)
#             tdayDvtn   - heutige Abweichung PV Prognose/Erzeugung in %
#             ydayDvtn   - gestrige Abweichung PV Prognose/Erzeugung in %
#    $def: Defaultwert
#
#############################################################################
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
#    $range:  Range Bewölkung (1...10)
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
# NexthoursVal ($hash, $hod, $key, $def)
#
# $hod: nächste Stunde (NextHour00, NextHour01,...)
# $key: starttime  - Startzeit der abgefragten nächsten Stunde
#       hourofday  - Stunde des Tages
#       pvforecast - PV Vorhersage in Wh
#       weatherid  - DWD Wetter id
#       cloudcover - DWD Wolkendichte
#       cloudrange - berechnete Bewölkungsrange
#       rainprob   - DWD Regenwahrscheinlichkeit
#       Rad1h      - Globalstrahlung (kJ/m2)
#       confc      - prognostizierter Hausverbrauch (Wh)
#       confcEx    - prognostizierter Hausverbrauch ohne registrierte Consumer (Wh)
#       today      - 1 wenn heute
#       correff    - verwendeter Korrekturfaktor bzw. SolCast Percentil/Qualität
# $def: Defaultwert
#
#########################################################################################
sub NexthoursVal {
  my $hash = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if(defined($data{$type}{$name}{nexthours})              &&
     defined($data{$type}{$name}{nexthours}{$hod})        &&
     defined($data{$type}{$name}{nexthours}{$hod}{$key})) {
     return  $data{$type}{$name}{nexthours}{$hod}{$key};
  }

return $def;
}

###################################################################################################
# Wert des current-Hash zurückliefern
# Usage:
# CurrentVal ($hash, $key, $def)
#
# $key: generation           - aktuelle PV Erzeugung
#       genslidereg          - Schieberegister PV Erzeugung (Array)
#       h4fcslidereg         - Schieberegister 4h PV Forecast (Array)
#       consumption          - aktueller Verbrauch (W)
#       consumerdevs         - alle registrierten Consumerdevices (Array)
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

  if(defined($data{$type}{$name}{current})       &&
     defined($data{$type}{$name}{current}{$key})) {
     return  $data{$type}{$name}{current}{$key};
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
#       type            - Typ des Verbrauchers
#       power           - nominale Leistungsaufnahme des Verbrauchers in W
#       mode            - Planungsmode des Verbrauchers
#       icon            - Icon für den Verbraucher
#       mintime         - min. Einschalt- bzw. Zykluszeit
#       onreg           - Regex für phys. Zustand "ein"
#       offreg          - Regex für phys. Zustand "aus"
#       oncom           - Einschaltkommando
#       offcom          - Ausschaltkommando
#       onoff           - logischer ein/aus Zustand des am Consumer angeschlossenen Endverbrauchers
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
#       rswoncond       - Reading zur Lieferung einer zusätzliche Einschaltbedingung
#       swoncondregex   - Regex einer zusätzliche Einschaltbedingung
#       dswoffcond      - Device zur Lieferung einer vorrangige Ausschaltbedingung
#       rswoffcond      - Reading zur Lieferung einer vorrangige Ausschaltbedingung
#       swoffcondregex  - Regex einer einer vorrangige Ausschaltbedingung
#       isIntimeframe   - ist Zeit innerhalb der Planzeit ein/aus
#       interruptable   - Consumer "on" ist während geplanter "ein"-Zeit unterbrechbar
#       hysteresis      - Hysterese
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

  if(defined($data{$type}{$name}{consumers})             &&
     defined($data{$type}{$name}{consumers}{$co}{$key})  &&
     defined($data{$type}{$name}{consumers}{$co}{$key})) {
     return  $data{$type}{$name}{consumers}{$co}{$key};
  }

return $def;
}

#############################################################################################################################
# Wert des solcastapi-Hash zurückliefern
# Usage:
# SolCastAPIVal ($hash, $tring, $ststr, $key, $def)
#
# $tring:  Stringname aus "inverterStrings" (?All für allg. Werte)
# $ststr:  Startzeit der Form YYYY-MM-DD hh:00:00
# $key:    pv_estimate - PV Schätzung in Wh
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
# SolCastAPIVal ($hash, '?All', '?All', 'response_message',        $def) - letzte SolCast API Antwort
# SolCastAPIVal ($hash, '?IdPair', '?<pk>', 'rtid',                $def) - RoofTop-ID, <pk> = Paarschlüssel
# SolCastAPIVal ($hash, '?IdPair', '?<pk>', 'apikey',              $def) - API-Key, <pk> = Paarschlüssel
#
#############################################################################################################################
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

=end html
=begin html_DE

<a id="SolarForecast"></a>
<h3>SolarForecast</h3>
<br>

Das Modul SolarForecast erstellt auf Grundlage der Werte aus generischen Quellendevices eine
Vorhersage für den solaren Ertrag und integriert weitere Informationen als Grundlage für darauf aufbauende Steuerungen. <br>

Die solare Vorhersage basiert auf der durch den Deutschen Wetterdienst (Model DWD) oder der
<a href='https://toolkit.solcast.com.au/rooftop-sites/' target='_blank'>SolCast API</a> (Model SolCastAPI) prognostizierten
Globalstrahlung am Anlagenstandort. Wegen der erreichbaren Genauigkeit wird die Nutzung der SolCast API empfohlen! <br><br>

Die Nutzung der SolCast API beschränkt sich auf die kostenlose Version unter Verwendung von Rooftop Sites. <br>
In zugeordneten DWD_OpenData Device(s) ist die passende Wetterstation mit dem Attribut "forecastStation"
festzulegen um meteorologische Daten (Bewölkung, Sonnenaufgang, u.a.) bzw. eine Strahlungsprognose (Model DWD) für diesen
Standort zu erhalten. <br>
Über die PV Erzeugungsprognose hinaus werden Verbrauchswerte bzw. Netzbezugswerte erfasst und für eine
Verbrauchsprognose verwendet. <br><br>

Das Modul errechnet aus den Prognosewerten einen zukünftigen Energieüberschuß der zur Betriebsplanung von Verbrauchern
genutzt wird. Weiterhin bietet das Modul eine <a href="#SolarForecast-Consumer">Consumer Integration</a> zur integrierten
Planung und Steuerung von PV Überschuß abhängigen Verbraucherschaltungen.

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
            <tr><td> <b>currentForecastDev</b>   </td><td>DWD_OpenData Device welches meteorologische Daten (z.B. Bewölkung) liefert     </td></tr>
            <tr><td> <b>currentRadiationDev </b> </td><td>DWD_OpenData Device bzw. SolCast-API zur Lieferung von Strahlungsdaten         </td></tr>
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

    Um eine Anpassung an die persönliche Anlage zu ermöglichen, können Korrekturfaktoren manuell
    (set &lt;name&gt; pvCorrectionFactor_XX) bzw. automatisiert (set &lt;name&gt; pvCorrectionFactor_Auto on) bestimmt
    werden. Die manuelle Anpassung ist nur für das Model DWD einsetzbar.
    Weiterhin kann mit den Attributen <a href="#SolarForecast-attr-affectCloudfactorDamping">affectCloudfactorDamping</a>
    und <a href="#SolarForecast-attr-affectRainfactorDamping">affectRainfactorDamping</a> der Beeinflussungsgrad von
    Bewölkungs- und Regenprognosen eingestellt werden. <br><br>

    <b>Hinweis</b><br>
    Bei Nutzung des DWD für die solare Vorhersage wird empfohlen die automatische Vorhersagekorrektur unmittelbar
    einzuschalten, da das SolarForecast Device eine lange Zeit benötigt um die Optimierung der Korrekturfaktoren zu erreichen.

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
    Die Schlüssel sind in der ConsumerXX-Hilfe detailliiert beschreiben, erfordern unter Umständen aber eine gewisse
    Einarbeitung. Um sich in den Umgang mit der Consumersteuerung anzueignen, bietet es sich an zunächst einen oder
    mehrere Dummies anzulegen und diese Devices als Consumer zu registrieren. <br><br>

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
      <li><b>currentBatteryDev &lt;Meter Device Name&gt; pin=&lt;Readingname&gt;:&lt;Einheit&gt; pout=&lt;Readingname&gt;:&lt;Einheit&gt; [intotal=&lt;Readingname&gt;:&lt;Einheit&gt;] [outtotal=&lt;Readingname&gt;:&lt;Einheit&gt;] [charge=&lt;Readingname&gt;]  </b> <br><br>

      Legt ein beliebiges Device und seine Readings zur Lieferung der Batterie Leistungsdaten fest.
      Das Modul geht davon aus dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>pin</b>       </td><td>Reading welches die aktuelle Batterieladung liefert                         </td></tr>
          <tr><td> <b>pout</b>      </td><td>Reading welches die aktuelle Batterieentladung liefert                      </td></tr>
          <tr><td> <b>intotal</b>   </td><td>Reading welches die totale Batterieladung liefert (fortlaufender Zähler)    </td></tr>
          <tr><td> <b>outtotal</b>  </td><td>Reading welches die totale Batterieentladung liefert (fortlaufender Zähler) </td></tr>
          <tr><td> <b>charge</b>    </td><td>Reading welches den aktuellen Ladezustand (in Prozent) liefert              </td></tr>
          <tr><td> <b>Einheit</b>   </td><td>die jeweilige Einheit (W,Wh,kW,kWh)                                         </td></tr>
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
        set &lt;name&gt; currentBatteryDev BatDummy pin=BatVal:W pout=-pin intotal=BatInTot:Wh outtotal=BatOutTot:Wh  <br>
        <br>
        # Device BatDummy liefert die aktuelle Batterieladung im Reading "BatVal" (W), die Batterieentladung im gleichen Reading mit negativen Vorzeichen, <br>
        # die summarische Ladung im Reading "intotal" (Wh), sowie die summarische Entladung im Reading "outtotal" (Wh)
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-currentForecastDev"></a>
      <li><b>currentForecastDev </b> <br><br>

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
      <br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>pv</b>       </td><td>Reading welches die aktuelle PV-Erzeugung liefert                                       </td></tr>
          <tr><td> <b>etotal</b>   </td><td>Reading welches die gesamte erzeugten Energie liefert (ein stetig aufsteigender Zähler) </td></tr>
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
      Das Modul geht davon aus dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>

      <ul>
       <table>
       <colgroup> <col width="15%"> <col width="85%"> </colgroup>
          <tr><td> <b>gcon</b>       </td><td>Reading welches die aktuell aus dem Netz bezogene Leistung liefert       </td></tr>
          <tr><td> <b>contotal</b>   </td><td>Reading welches die Summe der aus dem Netz bezogenen Energie liefert     </td></tr>
          <tr><td> <b>gfeedin</b>    </td><td>Reading welches die aktuell in das Netz eingespeiste Leistung liefert    </td></tr>
          <tr><td> <b>feedtotal</b>  </td><td>Reading welches die Summe der in das Netz eingespeisten Energie liefert  </td></tr>
          <tr><td> <b>Einheit</b>    </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                      </td></tr>
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
      <a id="SolarForecast-set-currentRadiationDev"></a>
      <li><b>currentRadiationDev </b> <br><br>

      Legt die Quelle zur Lieferung der solaren Strahlungsdaten fest. Es kann ein Device vom Typ DWD_OpenData oder
      die SolCast API ausgewählt werden. Die Verwendung der SolCast API wird wegen Vorhersagequalität empfohlen. <br><br>

      Bei Nutzung der SolCast API müssen vorab ein oder mehrere API-keys (Accounts) sowie ein oder mehrere Rooftop-ID's
      auf der <a href='https://toolkit.solcast.com.au/rooftop-sites/' target='_blank'>SolCast</a> Webseite angelegt werden.
      Ein Rooftop ist im SolarForecast-Kontext mit einem <a href="#SolarForecast-set-inverterStrings">inverterString</a>
      gleichzusetzen. <br>
      Es wird empfohlen bei Einsatz der SolCast API die Attribute
      <a href="#SolarForecast-attr-affectCloudfactorDamping">affectCloudfactorDamping</a> und
      <a href="#SolarForecast-attr-affectRainfactorDamping">affectRainfactorDamping</a> <b>explizit auf 0</b> bzw.
      <a href="#SolarForecast-set-pvCorrectionFactor_Auto">pvCorrectionFactor_Auto</a> auf <b>"off"</b> zu setzen.

      <br><br>

      Soll der DWD-Dienst zur Lieferung von Strahlungsdaten dienen und ist noch kein Device des Typs DWD_OpenData vorhanden,
      muß es manuell definiert werden (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens diese Attribute gesetzt sein: <br><br>

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
      Settings verwendet. <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; inverterStrings Ostdach,Südgarage,S3 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-modulePeakString"></a>
      <li><b>modulePeakString &lt;Stringname1&gt;=&lt;Peak&gt; [&lt;Stringname2&gt;=&lt;Peak&gt; &lt;Stringname3&gt;=&lt;Peak&gt; ...] </b> <br><br>

      Die DC Peakleistung des Strings "StringnameX" in kWp. Der Stringname ist ein Schlüsselwert des
      Readings <b>inverterStrings</b>. <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; modulePeakString Ostdach=5.1 Südgarage=2.0 S3=7.2 <br>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-set-moduleDirection"></a>
      <li><b>moduleDirection &lt;Stringname1&gt;=&lt;dir&gt; [&lt;Stringname2&gt;=&lt;dir&gt; &lt;Stringname3&gt;=&lt;dir&gt; ...] </b> <br>
      (nur bei Verwendung des DWD_OpenData RadiationDev) <br><br>

      Ausrichtung &lt;dir&gt; der Solarmodule im String "StringnameX". Der Stringname ist ein Schlüsselwert des
      Readings <b>inverterStrings</b>. <br>
      Die Richtungsangabe &lt;dir&gt; kann eine der folgenden Werte sein: <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>N</b>  </td><td>Nordausrichtung            </td></tr>
            <tr><td> <b>NE</b> </td><td>Nord-Ost Ausrichtung       </td></tr>
            <tr><td> <b>E</b>  </td><td>Ostausrichtung             </td></tr>
            <tr><td> <b>SE</b> </td><td>Süd-Ost Ausrichtung        </td></tr>
            <tr><td> <b>S</b>  </td><td>Südausrichtung             </td></tr>
            <tr><td> <b>SW</b> </td><td>Süd-West Ausrichtung       </td></tr>
            <tr><td> <b>W</b>  </td><td>Westausrichtung            </td></tr>
            <tr><td> <b>NW</b> </td><td>Nord-West Ausrichtung      </td></tr>
         </table>
      </ul>
      <br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleDirection Ostdach=E Südgarage=S S3=NW <br>
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
      (nur bei Verwendung des DWD_OpenData RadiationDev) <br><br>

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
      <a id="SolarForecast-set-plantConfiguration"></a>
      <li><b>plantConfiguration </b> <br><br>

       Je nach ausgewählter Kommandooption werden folgende Operationen ausgeführt: <br><br>

      <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>check</b>     </td><td>Zeigt die aktuelle Stringkonfiguration. Es wird gleichzeitig eine Plausibilitätsprüfung      </td></tr>
            <tr><td>                  </td><td>vorgenommen und das Ergebnis sowie eventuelle Anweisungen zur Fehlerbehebung ausgegeben.     </td></tr>
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
      <li><b>pvCorrectionFactor_Auto on | off </b> <br><br>

      Schaltet die automatische Vorhersagekorrektur ein/aus.
      Die Wirkungsweise unterscheidet sich zwischen dem Model DWD und dem Model SolCastAPI. <br><br>

      <b>Model SolCastAPI:</b> <br>
      Eine eingeschaltete Autokorrektur ermittelt am Ende jeder relevanten Stunde durch Vergleich von PV Prognose und
      realer Erzeugung das beste Percentil (10-90).
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
         ist man der Auffassung die optimale Einstellung gefunden zu haben, kann pvCorrectionFactor_Auto on gesetzt werden um
         eine automatische Auswahl des optimalen Percentils zu aktivieren
         </li>
      </ul>
      <br>

      Idealerweise wird dieser Prozess in einer Phase stabiler meteorologischer Bedingungen (gleichmäßige Sonne bzw.
      Bewölkung) durchgeführt. <br>
      Ist die minimale Tagesabweichung gefunden, kann die Autokorrektur aktiviert werden um für jede Stunde separat das
      beste Percentil ermitteln zu lassen. Dieser Vorgang ist dynamisch und verwendet ebenso historische Werte zur
      Durchschnittsbildung.
      Siehe auch Attribut <a href="#SolarForecast-attr-affectNumHistDays">affectNumHistDays</a>.
      <br><br>

      <b>Model DWD:</b> <br>
      Ist die Autokorrektur eingeschaltet, wird für jede Stunde ein Korrekturfaktor der Solarvorhersage berechnet und
      intern gespeichert.
      Dazu wird die tatsächliche Energieerzeugung mit dem vorhergesagten Wert des aktuellen Tages und Stunde verglichen,
      die Korrekturwerte historischer Tage unter Berücksichtigung der Bewölkung einbezogen und daraus ein neuer Korrekturfaktor
      abgeleitet. Es werden nur historische Daten mit gleicher Bewölkungsrange einbezogen. <br>
      Zukünftig erwartete PV Erzeugungen werden mit den gespeicherten Korrekturfaktoren optimiert. <br>
      Bei aktivierter Autokorrektur haben die Attribute
      <a href="#SolarForecast-attr-affectCloudfactorDamping">affectCloudfactorDamping</a> und
      <a href="#SolarForecast-attr-affectRainfactorDamping">affectRainfactorDamping</a> nur noch eine untergeordnete
      Bedeutung. <br><br>
      <b>Die automatische Vorhersagekorrektur ist lernend und benötigt Zeit um die Korrekturwerte zu optimieren.
      Nach der Aktivierung sind nicht sofort optimale Vorhersagen zu erwarten!</b> <br>
      (default: off)
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
            <tr><td> <b>consumerPlanning</b>   </td><td>löscht die Planungsdaten aller registrierten Verbraucher                                                             </td></tr>
            <tr><td>                           </td><td>Um die Planungsdaten nur eines Verbrauchers zu löschen verwendet man:                                                </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerPlanning &lt;Verbrauchernummer&gt; </ul>                                          </td></tr>
            <tr><td>                           </td><td>Das Modul führt eine automatische Neuplanung der Verbraucherschaltung durch.                                         </td></tr>
            <tr><td> <b>consumerMaster</b>     </td><td>löscht die Daten aller registrierten Verbraucher aus dem Speicher                                                    </td></tr>
            <tr><td>                           </td><td>Um die Daten nur eines Verbrauchers zu löschen verwendet man:                                                        </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerMaster &lt;Verbrauchernummer&gt; </ul>                                            </td></tr>
            <tr><td> <b>currentBatteryDev</b>  </td><td>löscht das eingestellte Batteriedevice und korrespondierende Daten                                                   </td></tr>
            <tr><td> <b>currentForecastDev</b> </td><td>löscht das eingestellte Device für Wetterdaten                                                                       </td></tr>
            <tr><td> <b>currentInverterDev</b> </td><td>löscht das eingestellte Inverterdevice und korrespondierende Daten                                                   </td></tr>
            <tr><td> <b>currentMeterDev</b>    </td><td>löscht das eingestellte Meterdevice und korrespondierende Daten                                                      </td></tr>
            <tr><td> <b>energyH4Trigger</b>    </td><td>löscht die 4-Stunden Energie Triggerpunkte                                                                           </td></tr>
            <tr><td> <b>inverterStrings</b>    </td><td>löscht die Stringkonfiguration der Anlage                                                                            </td></tr>
            <tr><td> <b>powerTrigger</b>       </td><td>löscht die Triggerpunkte für PV Erzeugungswerte                                                                      </td></tr>
            <tr><td> <b>pvCorrection</b>       </td><td>löscht die Readings pvCorrectionFactor*                                                                              </td></tr>
            <tr><td>                           </td><td>Um alle bisher gespeicherten PV Korrekturfaktoren aus den Caches zu löschen:                                         </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection cached </ul>                                                                 </td></tr>
            <tr><td>                           </td><td>Um gespeicherte PV Korrekturfaktoren einer bestimmten Stunde aus den Caches zu löschen:                              </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection cached &lt;Stunde&gt;  </ul>                                                 </td></tr>
            <tr><td>                           </td><td><ul>(z.B. set &lt;name&gt; reset pvCorrection cached 10)       </ul>                                                 </td></tr>
            <tr><td> <b>pvHistory</b>          </td><td>löscht den Speicher aller historischen Tage (01 ... 31)                                                              </td></tr>
            <tr><td>                           </td><td>Um einen bestimmten historischen Tag zu löschen:                                                                     </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Tag&gt;   (z.B. set &lt;name&gt; reset pvHistory 08) </ul>                  </td></tr>
            <tr><td>                           </td><td>Um eine bestimmte Stunde eines historischer Tages zu löschen:                                                        </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Tag&gt; &lt;Stunde&gt;  (z.B. set &lt;name&gt; reset pvHistory 08 10) </ul> </td></tr>
            <tr><td> <b>moduleRoofTops</b>     </td><td>löscht die SolCast API Rooftops                                                                                      </td></tr>
            <tr><td> <b>roofIdentPair</b>      </td><td>löscht alle gespeicherten SolCast API Rooftop-ID / API-Key Paare                                                     </td></tr>
            <tr><td>                           </td><td>Um ein bestimmtes Paar zu löschen ist dessen Schlüssel &lt;pk&gt; anzugeben:                                         </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset roofIdentPair &lt;pk&gt;   (z.B. set &lt;name&gt; reset roofIdentPair p1) </ul>           </td></tr>

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
      <a id="SolarForecast-set-writeHistory"></a>
      <li><b>writeHistory </b> <br><br>

       Die vom Device gesammelten historischen PV Daten werden in eine Datei geschrieben. Dieser Vorgang wird per default
       regelmäßig im Hintergrund ausgeführt. Im Internal "HISTFILE" wird der Dateiname und der Zeitpunkt der letzten
       Speicherung dokumentiert. <br>
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
      Zeigt die aktuell verwendeten Korrekturfaktoren mit der jeweiligen Startzeit zur Bestimmung der PV Vorhersage sowie
      deren Qualitäten an.
      Die Qualität ergibt sich aus der Anzahl der bereits in der Vergangenheit bewerteten Tage mit einer
      identischen Bewölkungsrange.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-html"></a>
      <li><b>html </b> <br><br>
      Die Solar Grafik wird als HTML-Code abgerufen und wiedergegeben. <br>
      Die Grafik kann abgerufen und in eigenen Code eingebettet werden. Auf einfache Weise kann dies durch die Definition
      eines weblink-Devices vorgenommen werden: <br><br>

      <ul>
        define wl.SolCast5 weblink htmlCode { FHEM::SolarForecast::pageAsHtml ('SolCast5') }
      </ul>
      <br>
      'SolCast5' ist der Name des einzubindenden SolarForecast-Device.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-nextHours"></a>
      <li><b>nextHours </b> <br><br>
      Listet die erwarteten Werte der kommenden Stunden auf. <br><br>

      <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>starttime</b> </td><td>Startzeit des Datensatzes                                                          </td></tr>
            <tr><td> <b>hourofday</b> </td><td>laufende Stunde des Tages                                                          </td></tr>
            <tr><td> <b>pvfc</b>      </td><td>erwartete PV Erzeugung (Wh)                                                        </td></tr>
            <tr><td> <b>today</b>     </td><td>"1" wenn Startdatum am aktuellen Tag                                               </td></tr>
            <tr><td> <b>confc</b>     </td><td>erwarteter Energieverbrauch inklusive der Anteile registrierter Verbraucher        </td></tr>
            <tr><td> <b>confcEx</b>   </td><td>erwarteter Energieverbrauch ohne der Anteile registrierter Verbraucher             </td></tr>
            <tr><td> <b>wid</b>       </td><td>ID des vorhergesagten Wetters                                                      </td></tr>
            <tr><td> <b>wcc</b>       </td><td>vorhergesagter Grad der Bewölkung                                                  </td></tr>
            <tr><td> <b>crange</b>    </td><td>berechneter Bewölkungsbereich                                                      </td></tr>
            <tr><td> <b>correff</b>   </td><td>verwendeter Korrekturfaktor/Qualität                                               </td></tr>
            <tr><td>                  </td><td>Faktor/m - manuell                                                                 </td></tr>
            <tr><td>                  </td><td>Faktor/0 - Korrektur nicht in Store vorhanden (default wird verwendet)             </td></tr>
            <tr><td>                  </td><td>Faktor/1...X - Korrektur aus Store genutzt (höhere Zahl = bessere Qualität)        </td></tr>
            <tr><td> <b>wrp</b>       </td><td>vorhergesagter Grad der Regenwahrscheinlichkeit                                    </td></tr>
            <tr><td> <b>Rad1h</b>     </td><td>vorhergesagte Globalstrahlung                                                      </td></tr>
            <tr><td> <b>temp</b>      </td><td>vorhergesagte Außentemperatur                                                      </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-pvHistory"></a>
      <li><b>pvHistory </b> <br><br>
      Listet die historischen Werte der letzten Tage (max. 31) sortiert nach dem Tagesdatum und Stunde.
      Die Stundenangaben beziehen sich auf die jeweilige Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit
      von 08 - 09 Uhr. <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>etotal</b>         </td><td>totaler Energieertrag (Wh) zu Beginn der Stunde                             </td></tr>
            <tr><td> <b>pvfc</b>           </td><td>der prognostizierte PV Ertrag (Wh)                                          </td></tr>
            <tr><td> <b>pvrl</b>           </td><td>reale PV Erzeugung (Wh)                                                     </td></tr>
            <tr><td> <b>gcon</b>           </td><td>realer Leistungsbezug (Wh) aus dem Stromnetz                                </td></tr>
            <tr><td> <b>confc</b>          </td><td>erwarteter Energieverbrauch (Wh)                                            </td></tr>
            <tr><td> <b>con</b>            </td><td>realer Energieverbrauch (Wh) des Hauses                                     </td></tr>
            <tr><td> <b>gfeedin</b>        </td><td>reale Einspeisung (Wh) in das Stromnetz                                     </td></tr>
            <tr><td> <b>batintotal</b>     </td><td>totale Batterieladung (Wh) zu Beginn der Stunde                             </td></tr>
            <tr><td> <b>batin</b>          </td><td>Batterieladung der Stunde (Wh)                                              </td></tr>
            <tr><td> <b>batouttotal</b>    </td><td>totale Batterieentladung (Wh) zu Beginn der Stunde                          </td></tr>
            <tr><td> <b>batout</b>         </td><td>Batterieentladung der Stunde (Wh)                                           </td></tr>
            <tr><td> <b>wid</b>            </td><td>Identifikationsnummer des Wetters                                           </td></tr>
            <tr><td> <b>wcc</b>            </td><td>effektive Wolkenbedeckung                                                   </td></tr>
            <tr><td> <b>wrp</b>            </td><td>Wahrscheinlichkeit von Niederschlag > 0,1 mm während der jeweiligen Stunde  </td></tr>
            <tr><td> <b>pvcorrf</b>        </td><td>abgeleiteter Autokorrekturfaktor bzw. SolCast Percentil                     </td></tr>
            <tr><td> <b>csmtXX</b>         </td><td>Summe Energieverbrauch von ConsumerXX                                       </td></tr>
            <tr><td> <b>csmeXX</b>         </td><td>Anteil der jeweiligen Stunde des Tages am Energieverbrauch von ConsumerXX   </td></tr>
            <tr><td> <b>minutescsmXX</b>   </td><td>Summe Aktivminuten in der Stunde von ConsumerXX                             </td></tr>
            <tr><td> <b>hourscsmeXX</b>    </td><td>durchschnittliche Stunden eines Aktivzyklus von ConsumerXX des Tages        </td></tr>
            <tr><td> <b>cyclescsmXX</b>    </td><td>Anzahl aktive Zyklen von ConsumerXX des Tages                               </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-pvCircular"></a>
      <li><b>pvCircular </b> <br><br>
      Listet die vorhandenen Werte im Ringspeicher auf.
      Die Stundenangaben 00 - 24 beziehen sich auf die Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit von
      08 - 09 Uhr. <br>
      Die Stunde 99 hat eine Sonderfunktion. <br>
      Erläuterung der Werte: <br><br>

      <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>pvfc</b>     </td><td>PV Vorhersage für die nächsten 24h ab aktueller Stunde des Tages                                                   </td></tr>
            <tr><td> <b>pvrl</b>     </td><td>reale PV Erzeugung der letzten 24h (Achtung: pvforecast und pvreal beziehen sich nicht auf den gleichen Zeitraum!) </td></tr>
            <tr><td> <b>confc</b>    </td><td>erwarteter Energieverbrauch (Wh)                                                                                   </td></tr>
            <tr><td> <b>gcon</b>     </td><td>realer Leistungsbezug aus dem Stromnetz                                                                            </td></tr>
            <tr><td> <b>gfeedin</b>  </td><td>reale Leistungseinspeisung in das Stromnetz                                                                        </td></tr>
            <tr><td> <b>batin</b>    </td><td>Batterieladung                                                                                                     </td></tr>
            <tr><td> <b>batout</b>   </td><td>Batterieentladung                                                                                                  </td></tr>
            <tr><td> <b>wcc</b>      </td><td>Grad der Wolkenüberdeckung                                                                                         </td></tr>
            <tr><td> <b>wrp</b>      </td><td>Grad der Regenwahrscheinlichkeit                                                                                   </td></tr>
            <tr><td> <b>temp</b>     </td><td>Außentemperatur                                                                                                    </td></tr>
            <tr><td> <b>wid</b>      </td><td>ID des vorhergesagten Wetters                                                                                      </td></tr>
            <tr><td> <b>wtxt</b>     </td><td>Beschreibung des vorhergesagten Wetters                                                                            </td></tr>
            <tr><td> <b>corr</b>     </td><td>Autokorrekturfaktoren für die Stunde des Tages und der Bewölkungsrange (0..10)                                     </td></tr>
            <tr><td> <b>quality</b>  </td><td>Qualität der Autokorrekturfaktoren (max. 30), höhere Werte = höhere Qualität                                       </td></tr>
            <tr><td> <b>tdayDvtn</b> </td><td>heutige Abweichung PV Prognose/Erzeugung in %                                                                      </td></tr>
            <tr><td> <b>ydayDvtn</b> </td><td>gestrige Abweichung PV Prognose/Erzeugung in %                                                                     </td></tr>
         </table>
      </ul>

      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-roofTopData"></a>
      <li><b>roofTopData </b> <br>
      (nur bei Verwendung Model SolCastAPI) <br><br>

      Die erwarteten solaren Strahlungsdaten der definierten RoofTops werden von der SolCast API abgerufen.
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-solCastData"></a>
      <li><b>solCastData </b> <br>
      (nur bei Verwendung Model SolCastAPI) <br><br>

      Listet die im Kontext der SolCast-API gespeicherten Daten auf.
      Verwaltungsdatensätze sind mit einem führenden '?' gekennzeichnet.
      Die von der API gelieferten Vorhersagedaten bzgl. des PV Ertrages (Wh) sind auf eine Stunde konsolidiert.
      <br><br>

      <ul>
         <table>
         <colgroup> <col width="37%"> <col width="63%"> </colgroup>
            <tr><td> <b>currentAPIinterval</b>        </td><td>das aktuell verwendete API Abrufintervall in Sekunden    </td></tr>
            <tr><td> <b>lastretrieval_time</b>        </td><td>Zeit des letzten SolCast API Abrufs                      </td></tr>
            <tr><td> <b>lastretrieval_timestamp</b>   </td><td>Unix Timestamp des letzten SolCast API Abrufs            </td></tr>
            <tr><td> <b>pv_estimate</b>               </td><td>erwartete PV Erzeugung von SolCast API (Wh)              </td></tr>
            <tr><td> <b>todayDoneAPIrequests</b>      </td><td>Anzahl der ausgeführten API Requests am aktuellen Tag    </td></tr>
            <tr><td> <b>todayRemainingAPIrequests</b> </td><td>Anzahl der verbleibenden API Requests am aktuellen Tag   </td></tr>
            <tr><td> <b>todayDoneAPIcalls</b>         </td><td>Anzahl der ausgeführten API Abrufe am aktuellen Tag      </td></tr>
            <tr><td> <b>todayRemainingAPIcalls</b>    </td><td>Anzahl der noch möglichen API Abrufe am aktuellen Tag    </td></tr>
            <tr><td>                                  </td><td>(ein Abruf kann mehrere API Requests ausführen)          </td></tr>
            <tr><td> <b>todayMaxAPIcalls</b>          </td><td>Anzahl der maximal möglichen API Abrufe pro Tag          </td></tr>
         </table>
      </ul>
      </li>
    </ul>
    <br>

    <ul>
      <a id="SolarForecast-get-valConsumerMaster"></a>
      <li><b>valConsumerMaster </b> <br><br>
      Listet die aktuell ermittelten Stammdaten der im Device registrierten Verbraucher auf.
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

       <a id="SolarForecast-attr-affectCloudfactorDamping"></a>
       <li><b>affectCloudfactorDamping </b><br>
         Prozentuale Mehrgewichtung des Bewölkungsfaktors bei der solaren Vorhersage. <br>
         Größere Werte vermindern, kleinere Werte erhöhen tendenziell den prognostizierten PV Ertrag (Dämpfung der PV
         Prognose durch den Bewölkungsfaktor).<br>
         (default: 35)
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
         (nur bei Verwendung Model DWD) <br><br>

         Maximale Änderungsgröße des PV Vorhersagefaktors (Reading pvCorrectionFactor_XX) pro Tag. <br>
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

       <a id="SolarForecast-attr-affectRainfactorDamping"></a>
       <li><b>affectRainfactorDamping </b><br>
         Prozentuale Mehrgewichtung des Regenprognosefaktors bei der solaren Vorhersage. <br>
         Größere Werte vermindern, kleinere Werte erhöhen tendenziell den prognostizierten PV Ertrag (Dämpfung der PV
         Prognose durch den Regenfaktor).<br>
         (default: 10)
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
            <tr><td> <b>&lt;Icon&gt@&lt;Farbe&gt</b>  </td><td>Aktivierungsempfehlung  wird durch Icon und Farbe (optional) dargestellt (default: light_light_dim_100@gold)  </td></tr>
            <tr><td>                                  </td><td>(die Planungsdaten werden als Mouse-Over Text angezeigt                                                       </td></tr>
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
       <li><b>consumerXX &lt;Device Name&gt; type=&lt;type&gt; power=&lt;power&gt; [mode=&lt;mode&gt;] [icon=&lt;Icon&gt;] [mintime=&lt;minutes&gt;] <br>
                         [on=&lt;Kommando&gt;] [off=&lt;Kommando&gt;] [swstate=&lt;Readingname&gt;:&lt;on-Regex&gt;:&lt;off-Regex&gt] [notbefore=&lt;Stunde&gt;] [notafter=&lt;Stunde&gt;] <br>
                         [auto=&lt;Readingname&gt;] [pcurr=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Schwellenwert&gt]] [etotal=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Schwellenwert&gt]] <br>
                         [swoncond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [swoffcond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [interruptable=&lt;Option&gt] </b><br><br>

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
        Dieser Wert wird verwendet um das Schalten des Verbrauchers in Abhängigkeit des aktuellen PV-Überschusses zu
        steuern. Ist <b>power=0</b> gesetzt, wird der Verbraucher unabhängig von einem ausreichenden PV-Überschuß geschaltet.
        <br><br>

         <ul>
         <table>
         <colgroup> <col width="12%"> <col width="88%"> </colgroup>
            <tr><td> <b>type</b>           </td><td>Typ des Verbrauchers. Folgende Typen sind erlaubt:                                                                                             </td></tr>
            <tr><td>                       </td><td><b>dishwasher</b>     - Verbaucher ist eine Spülmaschine                                                                                       </td></tr>
            <tr><td>                       </td><td><b>dryer</b>          - Verbaucher ist ein Wäschetrockner                                                                                      </td></tr>
            <tr><td>                       </td><td><b>washingmachine</b> - Verbaucher ist eine Waschmaschine                                                                                      </td></tr>
            <tr><td>                       </td><td><b>heater</b>         - Verbaucher ist ein Heizstab                                                                                            </td></tr>
            <tr><td>                       </td><td><b>charger</b>        - Verbaucher ist eine Ladeeinrichtung (Akku, Auto, Fahrrad, etc.)                                                        </td></tr>
            <tr><td>                       </td><td><b>other</b>          - Verbraucher ist keiner der vorgenannten Typen                                                                          </td></tr>
            <tr><td> <b>power</b>          </td><td>nominale Leistungsaufnahme des Verbrauchers (siehe Datenblatt) in W                                                                            </td></tr>
            <tr><td>                       </td><td>(kann auf "0" gesetzt werden)                                                                                                                  </td></tr>
            <tr><td> <b>mode</b>           </td><td>Planungsmodus des Verbrauchers (optional). Erlaubt sind:                                                                                       </td></tr>
            <tr><td>                       </td><td><b>can</b>  - Die Einplanung erfolgt zum Zeitpunkt mit wahrscheinlich genügend verfügbaren PV Überschuß (default)                              </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Der Start des Verbrauchers zum Planungszeitpunkt unterbleibt bei ungenügendem PV-Überschuß.   </td></tr>
            <tr><td>                       </td><td><b>must</b> - der Verbaucher wird optimiert eingeplant auch wenn wahrscheinlich nicht genügend PV Überschuß vorhanden sein wird                </td></tr>
            <tr><td>                       </td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Der Start des Verbrauchers erfolgt auch bei ungenügendem PV-Überschuß.            </td></tr>
            <tr><td> <b>icon</b>           </td><td>Icon zur Darstellung des Verbrauchers in der Übersichtsgrafik (optional)                                                                       </td></tr>
            <tr><td> <b>mintime</b>        </td><td>Mindestlaufzeit bzw. typische Laufzeit des Verbrauchers nach dem initialen Einschalten in Minuten  (optional)                                  </td></tr>
            <tr><td>                       </td><td>Die Standard mintime richtet sich nach dem Verbrauchertyp, ist aber mindestens <b>60 Minuten</b>.                                              </td></tr>
            <tr><td>                       </td><td>Default pro Verbrauchertyp:                                                                                                                    </td></tr>
            <tr><td>                       </td><td>- dishwasher: 180 Minuten                                                                                                                      </td></tr>
            <tr><td>                       </td><td>- dryer: 90 Minuten                                                                                                                            </td></tr>
            <tr><td>                       </td><td>- washingmachine: 120 Minuten                                                                                                                  </td></tr>
            <tr><td>                       </td><td>- heater: 240 Minuten                                                                                                                          </td></tr>
            <tr><td>                       </td><td>- charger: 120 Minuten                                                                                                                         </td></tr>
            <tr><td> <b>on</b>             </td><td>Set-Kommando zum Einschalten des Verbrauchers (optional)                                                                                       </td></tr>
            <tr><td> <b>off</b>            </td><td>Set-Kommando zum Ausschalten des Verbrauchers (optional)                                                                                       </td></tr>
            <tr><td> <b>swstate</b>        </td><td>Reading welches den Schaltzustand des Consumers anzeigt (default: 'state').                                                                    </td></tr>
            <tr><td>                       </td><td><b>on-Regex</b> - regulärer Ausdruck für den Zustand 'ein' (default: 'on')                                                                     </td></tr>
            <tr><td>                       </td><td><b>off-Regex</b> - regulärer Ausdruck für den Zustand 'aus' (default: 'off')                                                                   </td></tr>
            <tr><td> <b>notbefore</b>      </td><td>Startzeitpunkt Verbraucher nicht vor angegebener Stunde (01..23) einplanen (optional)                                                          </td></tr>
            <tr><td> <b>notafter</b>       </td><td>Startzeitpunkt Verbraucher nicht nach angegebener Stunde (01..23) einplanen (optional)                                                         </td></tr>
            <tr><td> <b>auto</b>           </td><td>Reading im Verbraucherdevice welches das Schalten des Verbrauchers freigibt bzw. blockiert (optional)                                          </td></tr>
            <tr><td>                       </td><td>Readingwert = 1 - Schalten freigegeben (default),  0: Schalten blockiert                                                                       </td></tr>
            <tr><td> <b>pcurr</b>          </td><td>Reading:Einheit (W/kW) welches den aktuellen Energieverbrauch liefert (optional)                                                               </td></tr>
            <tr><td>                       </td><td>:&lt;Schwellenwert&gt (W) - aktuelle Leistung ab welcher der Verbraucher als aktiv gewertet wird.                                              </td></tr>
            <tr><td> <b>etotal</b>         </td><td>Reading:Einheit (Wh/kWh) des Consumer Device, welches die Summe der verbrauchten Energie liefert (optional)                                    </td></tr>
            <tr><td>                       </td><td>:&lt;Schwellenwert&gt (Wh) - Energieverbrauch pro Stunde ab dem der Verbraucher als aktiv gewertet wird.                                       </td></tr>
            <tr><td> <b>swoncond</b>       </td><td>zusätzliche Bedingung die erfüllt sein muß um den Verbraucher einzuschalten (optional). Der geplante Zyklus wird gestartet.                    </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der zusätzlichen Einschaltbedingung                                                                       </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading zur Lieferung der zusätzlichen Einschaltbedingung                                                                     </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für die Einschaltbedingung erfüllt sein muß                                                              </td></tr>
            <tr><td> <b>swoffcond</b>      </td><td>vorrangige Bedingung um den Verbraucher auszuschalten (optional). Der geplante Zyklus wird gestoppt.                                           </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der vorrangigen Ausschaltbedingung                                                                        </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading zur Lieferung der vorrangigen Ausschaltbedingung                                                                      </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für die Ausschaltbedingung erfüllt sein muß                                                              </td></tr>
            <tr><td> <b>interruptable</b>  </td><td>definiert die möglichen Unterbrechungsoptionen für den Verbraucher nachdem er gestartet wurde (optional)                                       </td></tr>
            <tr><td>                       </td><td><b>0</b> - Verbraucher wird nicht temporär ausgeschaltet auch wenn der PV Überschuß die benötigte Energie unterschreitet (default)             </td></tr>
            <tr><td>                       </td><td><b>1</b> - Verbraucher wird temporär ausgeschaltet falls der PV Überschuß die benötigte Energie unterschreitet                                 </td></tr>
            <tr><td>                       </td><td><b>Device:Reading:Regex[:Hysterese]</b> - Verbraucher wird temporär unterbrochen wenn der Wert des angegebenen                                 </td></tr>
            <tr><td>                       </td><td>Device:Readings auf den Regex matched oder unzureichender PV Überschuß (wenn power ungleich 0) vorliegt.                                       </td></tr>
            <tr><td>                       </td><td>Matched der Wert nicht mehr, wird der unterbrochene Verbraucher wieder eingeschaltet sofern ausreichender                                      </td></tr>
            <tr><td>                       </td><td>PV Überschuß (wenn power ungleich 0) vorliegt.                                                                                                 </td></tr>
            <tr><td>                       </td><td>Die optionale Hysterese ist ein numerischer Wert um den der Ausschaltpunkt gegenüber dem Soll-Einschaltpunkt                                   </td></tr>
            <tr><td>                       </td><td>angehoben wird sofern der ausgewertete Readingwert ebenfalls numerisch ist. (default: 0)                                                       </td></tr>
         </table>
         </ul>
       <br>

       <ul>
         <b>Beispiele: </b> <br>
         <b>attr &lt;name&gt; consumer01</b> wallplug icon=scene_dishwasher@orange type=dishwasher mode=can power=2500 on=on off=off notafter=20 etotal=total:kWh:5 <br>
         <b>attr &lt;name&gt; consumer02</b> WPxw type=heater mode=can power=3000 mintime=180 on="on-for-timer 3600" notafter=12 auto=automatic                     <br>
         <b>attr &lt;name&gt; consumer03</b> Shelly.shellyplug2 type=other power=300 mode=must icon=it_ups_on_battery mintime=120 on=on off=off swstate=state:on:off auto=automatic pcurr=relay_0_power:W etotal:relay_0_energy_Wh:Wh swoncond=EcoFlow:data_data_socSum:-?([1-7][0-9]|[0-9]) swoffcond:EcoFlow:data_data_socSum:100 <br>
         <b>attr &lt;name&gt; consumer04</b> Shelly.shellyplug3 icon=scene_microwave_oven type=heater power=2000 mode=must notbefore=07 mintime=600 on=on off=off etotal=relay_0_energy_Wh:Wh pcurr=relay_0_power:W auto=automatic interruptable=eg.wz.wandthermostat:diff-temp:(22)(\.[2-9])|([2-9][3-9])(\.[0-9]):0.2             <br>
       </ul>
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

       <a id="SolarForecast-attr-ctrlConsRecommendReadings"></a>
       <li><b>ctrlConsRecommendReadings </b><br>
         Für die ausgewählten Consumer (Nummer) werden Readings der Form <b>consumerXX_ConsumptionRecommended</b> erstellt. <br>
         Diese Readings signalisieren ob das Einschalten dieses Consumers abhängig von seinen Verbrauchsdaten und der aktuellen
         PV-Erzeugung bzw. des aktuellen Energieüberschusses empfohlen ist. Der Wert des erstellten Readings korreliert
         mit den berechneten Planungsdaten das Consumers, kann aber von dem Planungszeitraum abweichen. <br>
       <br>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlDebug"></a>
       <li><b>ctrlDebug</b><br>
         Aktiviert/deaktiviert verschiedene Debug Module. Ist ausschließlich "none" selektiert erfolgt keine DEBUG-Ausgabe.
         Zur Ausgabe von Debug Meldungen muß der verbose Level des Device mindestens "1" sein. <br>
         Die Debug Module können miteinander kombiniert werden: <br><br>

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>collectData</b>        </td><td>detailliierte Datensammlung                                    </td></tr>
            <tr><td> <b>consumerPlanning</b>   </td><td>Consumer Einplanungsprozesse                                   </td></tr>
            <tr><td> <b>consumerSwitching</b>  </td><td>Operationen des internen Consumer Schaltmodul                  </td></tr>
            <tr><td> <b>consumption</b>        </td><td>Verbrauchskalkulation und -nutzung                             </td></tr>
            <tr><td> <b>graphic</b>            </td><td>Informationen der Modulgrafik                                  </td></tr>
            <tr><td> <b>pvCorrection</b>       </td><td>Erstellung und Anwendung der Autokorrektur                     </td></tr>
            <tr><td> <b>radiationProcess</b>   </td><td>Sammlung und Verarbeitung der Solarstrahlungsdaten             </td></tr>
            <tr><td> <b>saveData2Cache</b>     </td><td>Datenspeicherung in internen Speicherstrukturen                </td></tr>
            <tr><td> <b>solcastProcess</b>     </td><td>Abruf und Verarbeitung von SolCast API Daten                   </td></tr>
         </table>
         </ul>
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlInterval"></a>
       <li><b>ctrlInterval &lt;Sekunden&gt; </b><br>
         Zeitintervall der Datensammlung. <br>
         Ist ctrlInterval explizit auf "0" gesetzt, erfolgt keine automatische Datensammlung und muss mit
         "get &lt;name&gt; data" manuell erfolgen. <br>
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

       <a id="SolarForecast-attr-ctrlOptimizeSolCastInterval"></a>
       <li><b>ctrlOptimizeSolCastInterval </b><br>
         (nur bei Verwendung Model SolCastAPI) <br><br>

         Das default Abrufintervall der SolCast API beträgt 1 Stunde. Ist dieses Attribut gesetzt erfolgt ein dynamische
         Anpassung des Intervalls mit dem Ziel die maximal möglichen Abrufe innerhalb von Sonnenauf- und untergang
         auszunutzen. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlShowLink"></a>
       <li><b>ctrlShowLink </b><br>
         Anzeige des Links zur Detailansicht des Device über dem Grafikbereich <br>
         (default: 1)
       </li>
       <br>

       <a id="SolarForecast-attr-ctrlStatisticReadings"></a>
       <li><b>ctrlStatisticReadings </b><br>
         Für die ausgewählten Kennzahlen und Indikatoren werden Readings erstellt. <br><br>

         <ul>
         <table>
         <colgroup> <col width="25%"> <col width="75%"> </colgroup>
            <tr><td> <b>allStringsFullfilled</b>      </td><td>Erfüllungsstatus der fehlerfreien Generierung aller Strings                                        </td></tr>
            <tr><td> <b>currentAPIinterval</b>        </td><td>das aktuelle Abrufintervall der SolCast API (nur Model SolCastAPI) in Sekunden                     </td></tr>
            <tr><td> <b>lastretrieval_time</b>        </td><td>der letze Abrufzeitpunkt der SolCast API (nur Model SolCastAPI)                                    </td></tr>
            <tr><td> <b>lastretrieval_timestamp</b>   </td><td>der letze Abrufzeitpunkt der SolCast API (nur Model SolCastAPI) als Timestamp                      </td></tr>
            <tr><td> <b>response_message</b>          </td><td>die letzte Statusmeldung der SolCast API (nur Model SolCastAPI)                                    </td></tr>
            <tr><td> <b>runTimeCentralTask</b>        </td><td>die Laufzeit des letzten SolarForecast Intervalls (Gesamtprozess) in Sekunden                      </td></tr>
            <tr><td> <b>runTimeLastAPIAnswer</b>      </td><td>die letzte Antwortzeit der SolCast API (nur Model SolCastAPI) auf einen Request in Sekunden        </td></tr>
            <tr><td> <b>runTimeLastAPIProc</b>        </td><td>die letzte Prozesszeit zur Verarbeitung der empfangenen SolCast API Daten (nur Model SolCastAPI)   </td></tr>
            <tr><td> <b>todayMaxAPIcalls</b>          </td><td>die maximal mögliche Anzahl SolCast API Calls (nur Model SolCastAPI).                              </td></tr>
            <tr><td>                                  </td><td>Ein Call kann mehrere API Requests enthalten.                                                      </td></tr>
            <tr><td> <b>todayDoneAPIcalls</b>         </td><td>die Anzahl der am aktuellen Tag ausgeführten SolCast API Calls (nur Model SolCastAPI)              </td></tr>
            <tr><td> <b>todayDoneAPIrequests</b>      </td><td>die Anzahl der am aktuellen Tag ausgeführten SolCast API Requests (nur Model SolCastAPI)           </td></tr>
            <tr><td> <b>todayRemainingAPIcalls</b>    </td><td>die Anzahl der am aktuellen Tag noch möglichen SolCast API Calls (nur Model SolCastAPI)            </td></tr>
            <tr><td> <b>todayRemainingAPIrequests</b> </td><td>die Anzahl der am aktuellen Tag noch möglichen SolCast API Requests (nur Model SolCastAPI)         </td></tr>
         </table>
         </ul>
       <br>
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
         Definiert die Einheit zur Anzeige der elektrischen Leistung in der Grafik. Der Wert wird auf eine
         Nachkommastelle gerundet. <br>
         (default: Wh)
       </li>
       <br>

       <a id="SolarForecast-attr-graphicHeaderDetail"></a>
       <li><b>graphicHeaderDetail </b><br>
         Detaillierungsgrad des Grafik Kopfbereiches. <br>
         (default: all)

         <ul>
         <table>
         <colgroup> <col width="15%"> <col width="85%"> </colgroup>
            <tr><td> <b>all</b>        </td><td>Anzeige Erzeugung (PV), Verbrauch (CO), Link zur Detailanzeige + Aktualisierungszeit (default)        </td></tr>
            <tr><td> <b>co</b>         </td><td>nur Verbrauch (CO)                                                                                    </td></tr>
            <tr><td> <b>pv</b>         </td><td>nur Erzeugung (PV)                                                                                    </td></tr>
            <tr><td> <b>pvco</b>       </td><td>Erzeugung (PV) und Verbrauch (CO)                                                                     </td></tr>
            <tr><td> <b>statusLink</b> </td><td>Link zur Detailanzeige + Statusinformationen                                                          </td></tr>
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
         Wählt die anzuzeigende Grafik des Moduls aus. <br>
         Zur Anpassung der Energieflußgrafik steht neben den flowGraphic.*-Attributen auch
         das Attribut <a href="#SolarForecast-attr-flowGraphicCss">flowGraphicCss</a> zur Verfügung. <br><br>

         <ul>
         <table>
         <colgroup> <col width="20%"> <col width="80%"> </colgroup>
            <tr><td> <b>both</b>       </td><td>zeigt Energiefluß- und Balkengrafik an (default)        </td></tr>
            <tr><td> <b>flow</b>       </td><td>zeigt die Energieflußgrafik an                          </td></tr>
            <tr><td> <b>forecast</b>   </td><td>zeigt die Balkengrafik an                               </td></tr>
            <tr><td> <b>none</b>       </td><td>es wird keine Grafik angezeigt                          </td></tr>
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
  "abstract": "Creation of solar predictions for PV systems",
  "x_lang": {
    "de": {
      "abstract": "Erstellung solarer Vorhersagen von PV Anlagen"
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
  "release_status": "testing",
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
        "Color": 0,
        "utf8": 0,
        "HttpUtils": 0,
        "JSON": 4.020,
        "FHEM::SynoModules::SMUtils": 1.0220,
        "Time::HiRes": 0
      },
      "recommends": {
        "FHEM::Meta": 0,
        "FHEM::Utility::CTZ": 1.00,
        "DateTime": 0,
        "DateTime::Format::Strptime": 0,
        "Storable": 0,
        "Data::Dumper": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
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
