#################################################################################################################
# $Id$
#################################################################################################################
#
#  Copyright notice
#
#  Published according Creative Commons : Attribution-NonCommercial-ShareAlike 3.0 Unported (CC BY-NC-SA 3.0)
#  Details: https://creativecommons.org/licenses/by-nc-sa/3.0/
#
#  Credits:
#  - based on 77_SMASTP.pm by Volker Kettenbach with following credits:
#  - based on an Idea by SpenZerX and HDO
#  - Waldmensch for various improvements
#  - sbfspot (https://sbfspot.codeplex.com/)
#  - rewritten by Thomas Schoedl (sct14675) with inputs from Volker, waldmensch and DS_Starter
#  - adopted by MadMax 02.06.2021
#
#  Description:
#  This is an FHEM-Module for SMA Inverters.
#
#################################################################################################################

package main;

use strict;
use warnings;
eval "use IO::Socket::INET;1" or my $MissModulSocket   = "IO::Socket::INET";
eval "use DateTime;1"         or my $MissModulDateTime = "DateTime";
use Time::HiRes qw(gettimeofday tv_interval);
use Blocking;
use Time::Local;
eval "use FHEM::Meta;1"       or my $modMetaAbsent     = 1;

# Versions History by DS_Starter
our %SMAInverter_vNotesIntern = (
  "2.29.8" => "31.05.2025  fix Bug sum PDC",
  "2.29.7" => "29.05.2025  sum PDC",
  "2.29.6" => "04.05.2025  fix Bug inv_BAT_UDC ./FHEM/76_SMAInverter.pm line 1432",
  "2.29.5" => "06.04.2025  fix Bug SBS_3.7 BatTemp",
  "2.29.4" => "25.01.2025  fix Bug isn't Argument ''-'' numeric in multiplication (*) at ./FHEM/76_SMAInverter.pm line 1377",
  "2.29.3" => "18.01.2025  fix Bug BAT_P_Charge/Discarge",
  "2.29.2" => "31.12.2024  fix Bug STP X",
  "2.29.1" => "14.12.2024  bat_pwr whith detail-level 0, fix detail-level 0 bug",
  "2.29.0" => "09.12.2024  get Data detail-level",
  "2.28.3" => "01.12.2024  code optimized, remove given",
  "2.28.2" => "16.11.2024  code optimized, remove switch",
  "2.28.1" => "15.11.2024  code optimized",
  "2.28.0" => "10.11.2024  code optimized",
  "2.27.3" => "09.11.2024  fix read Insulation range",
  "2.27.2" => "08.11.2024  select Login user/installer",
  "2.27.1" => "08.11.2024  fix read Insulation",
  "2.27.0" => "02.11.2024  read Insulation",
  "2.26.0" => "18.08.2024  fix PW Lengs Bug (12 Char)",
  "2.25.3" => "17.08.2024  fix IDC2 bug 3MPP",
  "2.25.2" => "16.08.2024  fix IDC3 bug",
  "2.25.1" => "21.04.2024  read Bat_Status",
  "2.25.0" => "23.03.2024  PW Lengs set so max 18",
  "2.24.1" => "10.03.2024  GridConection (SI only)",
  "2.24.0" => "08.03.2024  add GridConection (SI/Hybrid-Inverter)",
  "2.23.8" => "21.01.2024  Voltage L1-L2-L3 bug",
  "2.23.7" => "25.12.2023  add DC-Power PV-Inverter",
  "2.23.6" => "24.09.2023  add BAT_P_Charge/Discarge",
  "2.23.5" => "25.06.2023  buxfix line 1267",
  "2.23.4" => "20.06.2023  buxfix DC-Power 2.0",
  "2.23.3" => "19.06.2023  buxfix DC-Power",
  "2.23.2" => "20.05.2023  add new SMAInverter_StatusText",
  "2.23.1" => "19.05.2023  add String 3 (only STP X Inverter)",
  "2.23.0" => "14.05.2023  read firmware version",
  "2.22.2" => "01.05.2023  fix name STPxxSE".
                           "add new Readings (GeneralOperatingStatus, OperatingStatus, BACKRELAYRELAY)",
  "2.22.1" => "23.04.2023  add STP X",
  "2.22.0" => "03.04.2023  add SI x.xM-13",
  "2.21.6" => "12.02.2023  read PV-Power (DC) from Hybridinverter, set state to PV-Power (Hybridinverter)",
  "2.21.5" => "08.02.2023  bugfix reset TODAY Counter",
  "2.21.4" => "28.01.2023  bugfix save INVCLASS && INVTYPE",
  "2.21.3" => "26.01.2023  bugfix SBFSpotComp reset DAYCOUNTER",
  "2.21.2" => "18.01.2023  fix reset TODAY Counter Batterry/PV only Hybrid/Batterie-Inverter",
  "2.21.1" => "16.01.2023  fix reset TODAY Counter",
  "2.21.0" => "15.01.2023  read EM-Data, disable suppressSleep (Batterie/Hybrid-Inverter)".
                           "add more Meterdata, add Backup Curre & Power (only Hybrid-Inverter)".
						   "set ETODAY, EPVTODAY, LOADTODAY, UNLOADTODAY at 0 out of opertime (https://forum.fhem.de/index.php/topic,56080.msg1257950.html#msg1257950)",
  "2.20.3" => "15.01.2023  fix show FVERSION ",
  "2.20.2" => "12.01.2023  new read SPOT_EPVTOTAL / SPOT_EPVTODAY (Hybrid Inverter)",
  "2.20.1" => "09.01.2023  fix BAT_UNLOADTODAY calculate",
  "2.20.0" => "08.01.2023  crypt Password",
  "2.19.1" => "07.01.2023  new read BAT_UNLOADTODAY / BAT_UNLOADTOTAL, included by 300P,",
  "2.19.0" => "04.01.2023  new read BAT_CAPACITY, included by 300P,",
  "2.18.3" => "11.10.2022  fix new ETOTAL/LOADTOTAL bug 2.0 ;)",
  "2.18.2" => "09.10.2022  fix new ETOTAL/LOADTOTAL bug",
  "2.18.1" => "03.10.2022  new SE Inverters fix BAT-Data, fix ETODAY bug",
  "2.18.0" => "30.09.2022  new SE Inverters",
  "2.17.1" => "12.07.2021  fix ETOTAL/LOADTOTAL bug",
  "2.17.0" => "01.07.2021  fix ETOTAL/LOADTOTAL bug",
  "2.16.1" => "21.06.2021  hide unavailable data",
  "2.16.0" => "21.06.2021  AC Voltage and AC Curren read fixed, read CosPhi included ",
  "2.15.1" => "18.06.2021  SBS1.5, SBS2.0, SBS2.5 read battery data included ",
  "2.15.0" => "14.06.2021  SBS5.0-10, SBS6.0-10, SBS3.7-10 read battery data included ",
  "2.14.2" => "02.06.2021  new inverter type 9359=SBS6.0-10 ",
  "2.14.1" => "27.02.2021  change save .etotal_yesterday, Forum: https://forum.fhem.de/index.php/topic,56080.msg1134664.html#msg1134664 ",
  "2.14.0" => "08.10.2019  readings bat_loadtotal (BAT_LOADTOTAL), bat_loadtoday (BAT_LOADTODAY) included by 300P, Forum: #topic,56080.msg986302.html#msg986302",
  "2.13.4" => "30.08.2019  STP10.0-3AV-40 298 included into %SMAInverter_devtypes ",
  "2.13.3" => "28.08.2019  commandref revised ",
  "2.13.2" => "27.08.2019  fix WARNING: Use of uninitialized value \$_ in substitution (s///) at /opt/fhem//FHEM/Blocking.pm line 238 ",
  "2.13.1" => "22.08.2019  commandref revised ",
  "2.13.0" => "20.08.2019  support of Meta.pm ",
  "2.12.0" => "20.08.2019  set warning to log if SPOT_ETODAY, SPOT_ETOTAL was not delivered or successfully ".
                           "calculated in SMAInverter_SMAcommand, Forum: https://forum.fhem.de/index.php/topic,56080.msg967823.html#msg967823 ",
  "2.11.0" => "17.08.2019  attr target-serial, target-susyid are set automatically if not defined, commandref revised ",
  "2.10.2" => "14.08.2019  new types to %SMAInverter_devtypes ",
  "2.10.1" => "28.04.2019  fix perl warnings, Forum:#56080.msg933276.html#msg933276 ",
  "2.10.0" => "29.06.2018  Internal MODEL added ",
  "2.9.2"  => "08.10.2017  adapted to use extended abortArg (Forum:77472) ",
  "2.9.1"  => "24.04.2017  fix for issue #24 (Wrong INV_TYPE for STP10000TL-20) and fix for issue #25 (unpack out of range for SB1.5-1VL-40) ",
  "2.9.0"  => "23.04.2017  fixed issue #22: wrong logon command for SunnyBoy systems ",
  "2.8.3"  => "19.04.2017  enhanced inverter Type-Hash ",
  "2.8.2"  => "23.03.2017  changed SMAInverter_SMAlogon sub ",
  "2.8.1"  => "06.12.2016  SMAInverter version as internal ",
  "2.8.0"  => "05.12.2016  changed commandsections to make sure getting only data from inverters with preset ".
                           "\$inv_susyid and \$inv_serial ",
  "2.7.4"  => "04.12.2016  change loading of IO::Socket::INET, DateTime ",
  "2.7.3"  => "04.12.2016  commandref adapted ",
  "2.7.2"  => "03.12.2016  use Time::HiRes qw(gettimeofday tv_interval ",
  "2.7.1"  => "02.12.2016  showproctime improved ",
  "2.7.0"  => "02.12.2016  showproctime added ",
  "2.6.1"  => "29.11.2016  SMAInverter_getstatusDoParse changed due to inititialized issues ",
  "2.6.0"  => "28.11.2016  bugfix warnings ParseDone redefine at startup, uninitialized value \$avg if FHEM was ".
                           "restarted in sleeptime, switched avg_energy to avg_power, commandref updated ",
  "2.5.2"  => "27.11.2016  bugfix average calc, bugfix warnings at startup ",
  "2.5.1"  => "26.11.2016  calc of averagebuf changed to 5, 10, 15 minutes ",
  "2.5.0"  => "26.11.2016  averagebuf changed, Attr timeout added ",
  "2.4.0"  => "26.11.2016  create ringbuffer for calculating average energy last 5, 10, 15 cycles ",
  "2.3.0"  => "25.11.2016  bugfixing ",
  "2.2.0"  => "24.11.2016  further optimize of non-blocking operation ",
  "2.1.0"  => "24.11.2016  avg_energy_lastcycles added ",
  "2.0.0"  => "24.11.2016  switched module to non-blocking operation ",
  "1.8.4"  => "23.11.2016  prepare non-blocking operation ",
  "1.8.3"  => "23.11.2016  readings opertime_start, opertime_stop ",
  "1.8.2"  => "22.11.2016  eliminate global vars, prepare non-blocking operation ",
  "1.8.1"  => "22.11.2016  eliminate global vars, create command array ",
  "1.8.0"  => "21.11.2016  eliminate \$r_OK, \$r_FAIL, create command-array ",
  "1.7.0"  => "21.11.2016  devtypes completed, minor bugfixes, commandref completed ",
  "1.6.1"  => "19.11.2016  bugfix perl warning during fhem start ",
  "1.6.0"  => "09.11.2016  added operation control by sunrise,sunset, Attr offset, suppressSleep added ",
  "1.5.0"  => "08.11.2016  added device classes hash ",
  "1.4.0"  => "07.11.2016  compatibility to SBFSpot improved, bilingual dependend on attr \"language\" of global-device ".
                           "added hash of SMA device types ",
  "1.3.0"  => "07.11.2016  Attr SBFSpotComp added to get compatibility mode with SBFSpot ",
  "1.2.0"  => "06.11.2016  function get data added, log output level changed to 4 in sub SMAInverter_Attr, some code changes ",
  "1.1.0"  => "06.11.2016  Attr mode manual, automatic added ",
  "1.0.0"  => "06.11.2016  Attr disable added, \$globalName replaced by \$name in all expressions (due to module redesign to non-blocking later) "
);

# Inverter Data fields and supported commands flags.
# $inv_SPOT_ETODAY                # Today yield
# $inv_SPOT_ETOTAL                # Total yield
# $inv_SPOT_PDC1                  # DC power input 1
# $inv_SPOT_PDC2                  # DC power input 2
# $inv_SPOT_PAC1                  # Power L1
# $inv_SPOT_PAC2                  # Power L2
# $inv_SPOT_PAC3                  # Power L3
# $inv_PACMAX1                    # Nominal power in Ok Mode
# $inv_PACMAX2                    # Nominal power in Warning Mode
# $inv_PACMAX3                    # Nominal power in Fault Mode
# $inv_PACMAX1_2                  # Maximum active power device (Some inverters like SB3300/SB1200)
# $inv_SPOT_PACTOT                # Total Power
# $inv_ChargeStatus               # Battery Charge status
# $inv_SPOT_UDC1                  # DC voltage input
# $inv_SPOT_UDC2                  # DC voltage input
# $inv_SPOT_IDC1                  # DC current input
# $inv_SPOT_IDC2                  # DC current input
# $inv_SPOT_UAC1                  # Grid voltage phase L1
# $inv_SPOT_UAC2                  # Grid voltage phase L2
# $inv_SPOT_UAC3                  # Grid voltage phase L3
# $inv_SPOT_UAC1_2                # Grid voltage phase L1 - L2
# $inv_SPOT_UAC2_3                # Grid voltage phase L2 - L3
# $inv_SPOT_UAC3_1                # Grid voltage phase L3 - L1
# $inv_SPOT_IAC1                  # Grid current phase L1
# $inv_SPOT_IAC2                  # Grid current phase L2
# $inv_SPOT_IAC3                  # Grid current phase L3
# $inv_BAT_UDC                    # Battery Voltage
# $inv_BAT_IDC                    # Battery Current
# $inv_BAT_CYCLES                 # Battery recharge cycles
# $inv_BAT_TEMP                   # Battery temperature
# $inv_SPOT_FREQ                  # Grid Frequency
# $inv_CLASS                      # Inverter Class
# $inv_TYPE                       # Inverter Type
# $inv_SPOT_OPERTM                # Operation Time
# $inv_SPOT_FEEDTM                # Feed-in time
# $inv_TEMP                       # Inverter temperature
# $inv_GRIDRELAY                  # Grid Relay/Contactor Status
# $inv_STATUS                     # Inverter Status
# $inv_BAT_LOADTODAY              # Today Batteryload
# $inv_BAT_LOADTOTAL              # Total Batteryload
# $inv_BAT_CAPACITY               # Battery Capacity (Percent) #TTT
# $inv_BAT_UNLOADTODAY            # Today Batteryunload
# $inv_BAT_UNLOADTOTAL            # Total Batteryunload

# Aufbau Wechselrichter Type-Hash
# https://github.com/SBFspot/SBFspot/blob/master/SBFspot/TagListDE-DE.txt
my %SMAInverter_devtypes = (
0000 => "Unknown Inverter Type",
9015 => "SB 700",
9016 => "SB 700U",
9017 => "SB 1100",
9018 => "SB 1100U",
9019 => "SB 1100LV",
9020 => "SB 1700",
9021 => "SB 1900TLJ",
9022 => "SB 2100TL",
9023 => "SB 2500",
9024 => "SB 2800",
9025 => "SB 2800i",
9026 => "SB 3000",
9027 => "SB 3000US",
9028 => "SB 3300",
9029 => "SB 3300U",
9030 => "SB 3300TL",
9031 => "SB 3300TL HC",
9032 => "SB 3800",
9033 => "SB 3800U",
9034 => "SB 4000US",
9035 => "SB 4200TL",
9036 => "SB 4200TL HC",
9037 => "SB 5000TL",
9038 => "SB 5000TLW",
9039 => "SB 5000TL HC",
9066 => "SB 1200",
9067 => "STP 10000TL-10",
9068 => "STP 12000TL-10",
9069 => "STP 15000TL-10",
9070 => "STP 17000TL-10",
9084 => "WB 3600TL-20",
9085 => "WB 5000TL-20",
9086 => "SB 3800US-10",
9098 => "STP 5000TL-20",
9099 => "STP 6000TL-20",
9100 => "STP 7000TL-20",
9101 => "STP 8000TL-10",
9102 => "STP 9000TL-20",
9103 => "STP 8000TL-20",
9104 => "SB 3000TL-JP-21",
9105 => "SB 3500TL-JP-21",
9106 => "SB 4000TL-JP-21",
9107 => "SB 4500TL-JP-21",
9108 => "SCSMC",
9109 => "SB 1600TL-10",
9131 => "STP 20000TL-10",
9139 => "STP 20000TLHE-10",
9140 => "STP 15000TLHE-10",
9157 => "Sunny Island 2012",
9158 => "Sunny Island 2224",
9159 => "Sunny Island 5048",
9160 => "SB 3600TL-20",
9168 => "SC630HE-11",
9169 => "SC500HE-11",
9170 => "SC400HE-11",
9171 => "WB 3000TL-21",
9172 => "WB 3600TL-21",
9173 => "WB 4000TL-21",
9174 => "WB 5000TL-21",
9175 => "SC 250",
9176 => "SMA Meteo Station",
9177 => "SB 240-10",
9171 => "WB 3000TL-21",
9172 => "WB 3600TL-21",
9173 => "WB 4000TL-21",
9174 => "WB 5000TL-21",
9179 => "Multigate-10",
9180 => "Multigate-US-10",
9181 => "STP 20000TLEE-10",
9182 => "STP 15000TLEE-10",
9183 => "SB 2000TLST-21",
9184 => "SB 2500TLST-21",
9185 => "SB 3000TLST-21",
9186 => "WB 2000TLST-21",
9187 => "WB 2500TLST-21",
9188 => "WB 3000TLST-21",
9189 => "WTP 5000TL-20",
9190 => "WTP 6000TL-20",
9191 => "WTP 7000TL-20",
9192 => "WTP 8000TL-20",
9193 => "WTP 9000TL-20",
9254 => "Sunny Island 3324",
9255 => "Sunny Island 4.0M",
9256 => "Sunny Island 4248",
9257 => "Sunny Island 4248U",
9258 => "Sunny Island 4500",
9259 => "Sunny Island 4548U",
9260 => "Sunny Island 5.4M",
9261 => "Sunny Island 5048U",
9262 => "Sunny Island 6048U",
9278 => "Sunny Island 3.0M",
9279 => "Sunny Island 4.4M",
9281 => "STP 10000TL-20",
9282 => "STP 11000TL-20",
9283 => "STP 12000TL-20",
9284 => "STP 20000TL-30",
9285 => "STP 25000TL-30",
9301 => "SB1.5-1VL-40",
9302 => "SB2.5-1VL-40",
9303 => "SB2.0-1VL-40",
9304 => "SB5.0-1SP-US-40",
9305 => "SB6.0-1SP-US-40",
9306 => "SB8.0-1SP-US-40",
9307 => "Energy Meter",
9313 => "SB50.0-3SP-40",
9319 => "SB3.0-1AV-40 (Sunny Boy 3.0 AV-40)",
9320 => "SB3.6-1AV-40 (Sunny Boy 3.6 AV-40)",
9321 => "SB4.0-1AV-40 (Sunny Boy 4.0 AV-40)",
9322 => "SB5.0-1AV-40 (Sunny Boy 5.0 AV-40)",
9324 => "SBS1.5-1VL-10 (Sunny Boy Storage 1.5)",
9325 => "SBS2.0-1VL-10 (Sunny Boy Storage 2.0)",
9326 => "SBS2.5-1VL-10 (Sunny Boy Storage 2.5)",
9327 => "SMA Energy Meter",
9331 => "SI 3.0M-12 (Sunny Island 3.0M)",
9332 => "SI 4.4M-12 (Sunny Island 4.4M)",
9333 => "SI 6.0H-12 (Sunny Island 6.0H)",
9334 => "SI 8.0H-12 (Sunny Island 8.0H)",
9335 => "SMA Com Gateway",
9336 => "STP 15000TL-30",
9337 => "STP 17000TL-30",
9344 => "STP4.0-3AV-40 (Sunny Tripower 4.0)",
9345 => "STP5.0-3AV-40 (Sunny Tripower 5.0)",
9346 => "STP6.0-3AV-40 (Sunny Tripower 6.0)",
9347 => "STP8.0-3AV-40 (Sunny Tripower 8.0)",
9348 => "STP10.0-3AV-40 (Sunny Tripower 10.0)",
9356 => "SBS3.7-1VL-10 (Sunny Boy Storage 3.7)",
9358 => "SBS5.0-10 (Sunny Boy Storage 5.0)",
9359 => "SBS6.0-10 (Sunny Boy Storage 6.0)",
9366 => "STP3.0-3AV-40 (Sunny Tripower 3.0)",
9401 => "SB3.0-1AV-41 (Sunny Boy 3.0 AV-41)",
9402 => "SB3.6-1AV-41 (Sunny Boy 3.6 AV-41)",
9403 => "SB4.0-1AV-41 (Sunny Boy 4.0 AV-41)",
9404 => "SB5.0-1AV-41 (Sunny Boy 5.0 AV-41)",
9405 => "SB6.0-1AV-41 (Sunny Boy 6.0 AV-41)",
9473 => "SI 3.0M-13 (Sunny Island 3.0M)",
9474 => "SI 4.4M-13 (Sunny Island 4.4M)",
9475 => "SI 6.0H-13 (Sunny Island 6.0H)",
9476 => "SI 8.0H-13 (Sunny Island 8.0H)",
19048 => "STP5.0SE (SUNNY TRIPOWER 5.0 SE)",
19049 => "STP6.0SE (SUNNY TRIPOWER 6.0 SE)",
19050 => "STP8.0SE (SUNNY TRIPOWER 8.0 SE)",
19051 => "STP10.0SE (SUNNY TRIPOWER 10.0 SE)",
9492 => "STP X 50-12 (SUNNY TRIPOWER X 50-12)",
9491 => "STP X 50-15 (SUNNY TRIPOWER X 50-15)",
9490 => "STP X 50-17 (SUNNY TRIPOWER X 50-17)",
9489 => "STP X 50-20 (SUNNY TRIPOWER X 50-20)",
9488 => "STP X 50-25 (SUNNY TRIPOWER X 50-25)",
);

# Wechselrichter Class-Hash DE
my %SMAInverter_classesDE = (
8000 => "Alle Geräte",
8001 => "Solar-Wechselrichter",
8002 => "Wind-Wechselrichter",
8007 => "Batterie-Wechselrichter",
8009 => "Hybrid-Wechselrichter",
8033 => "Verbraucher",
8064 => "Sensorik allgemein",
8065 => "Stromzähler",
8128 => "Kommunikationsprodukte",
);

# Wechselrichter Class-Hash EN
my %SMAInverter_classesEN = (
8000 => "All Devices",
8001 => "Solar Inverters",
8002 => "Wind Turbine Inverter",
8007 => "Batterie Inverters",
8009 => "Hybrid Inverters",
8033 => "Consumer",
8064 => "Sensor System in General",
8065 => "Electricity meter",
8128 => "Communication products",
);

###############################################################
#                  SMAInverter Initialize
###############################################################
sub SMAInverter_Initialize($) {
 my ($hash) = @_;

 $hash->{DefFn}     = "SMAInverter_Define";
 $hash->{UndefFn}   = "SMAInverter_Undef";
 $hash->{GetFn}     = "SMAInverter_Get";
 $hash->{AttrList}  = "interval " .
                      "detail-level:0,1,2 " .
					  "readEnergyMeter-data:0,1 " .
                      "disable:1,0 " .
					  "installerLogin:1,0 " .
                      "mode:manual,automatic ".
                      "offset ".
                      "suppressSleep:1,0 ".
                      "SBFSpotComp:1,0 " .
                      "showproctime:1,0 ".
                      "timeout " .
                      "target-susyid " .
                      "target-serial " .
                      $readingFnAttributes;
 
 $hash->{AttrFn}    = "SMAInverter_Attr";

 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };    # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;
}

###############################################################
#                  SMAInverter Define
###############################################################
sub SMAInverter_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t][ \t]*", $def);

 return "Error: Perl module ".$MissModulSocket." is missing.
        Install it on Debian with: sudo apt-get install libio-socket-multicast-perl" if($MissModulSocket);
 return "Error: Perl module ".$MissModulDateTime." is missing.
        Install it on Debian with: sudo apt-get install libdatetime-perl" if($MissModulDateTime);

 return "Wrong syntax: use define <name> SMAInverter <inv-userpwd> <inv-hostname/inv-ip > " if ((int(@a) < 4) and (int(@a) > 5));

 my $Pass = $a[2];                        
 my $password = SMAInverter_SMAencrypt($Pass);
 $Pass = SMAInverter_SMAdecrypt( $password );
 
 return "passwort longer then 12 char" if(length $Pass > 12); #check 1-12 Chars
 
 my $name                       = $hash->{NAME};
 $hash->{LASTUPDATE}            = 0;
 $hash->{INTERVAL}              = $hash->{HELPER}{INTERVAL} = AttrVal($name, "interval", 60);
 $hash->{HELPER}{FAULTEDCYCLES} = 0;
 delete($hash->{HELPER}{AVERAGEBUF}) if($hash->{HELPER}{AVERAGEBUF});

 # protocol related defaults
 $hash->{HELPER}{MYSUSYID}              = 233;                   # random number, has to be different from any device in local network
 $hash->{HELPER}{MYSERIALNUMBER}        = 123321123;             # random number, has to be different from any device in local network
 $hash->{HELPER}{DEFAULT_TARGET_SUSYID} = 0xFFFF;                # 0xFFFF is any susyid
 $hash->{HELPER}{DEFAULT_TARGET_SERIAL} = 0xFFFFFFFF;            # 0xFFFFFFFF is any serialnumber
 $hash->{HELPER}{PKT_ID}                = 0x8001;                # Packet ID
 $hash->{HELPER}{MAXBYTES}              = 300;                   # constant MAXBYTES scalar 300
 $hash->{HELPER}{MODMETAABSENT}         = 1 if($modMetaAbsent);  # Modul Meta.pm nicht vorhanden
 
 # Versionsinformationen setzen
 SMAInverter_setVersionInfo($hash);

 my ($IP,$Host,$Caps);


 
 # extract IP or Hostname from $a[3]
 if (!defined $Host) {
     if ( $a[3] =~ /^([A-Za-z0-9_.])/ ) {
         $Host = $a[3];
     }
 }

 if (!defined $Host) {
     return "Argument:{$a[3]} not accepted as Host or IP. Read device specific help file.";
 }

 $hash->{DEF} = "$password $Host";
 $hash->{PASS} = $password;
 $hash->{HOST} = $Host;

 InternalTimer(gettimeofday()+5, "SMAInverter_GetData", $hash, 0);      # Start Hauptroutine

return undef;
}

###############################################################
#                  SMAInverter Undefine
###############################################################
sub SMAInverter_Undef($$) {
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  BlockingKill($hash->{HELPER}{RUNNING_PID});
return undef;
}

###############################################################
#                  SMAInverter Get
###############################################################
sub SMAInverter_Get($$) {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $opt  = shift @a;
 my $vel_1  = shift @a;
 my $timeout  = AttrVal($name, "timeout", 60);

 my  $getlist = "Unknown argument $opt, choose one of ".
                "data:-,0,1,2,parameter ";

 return "module is disabled" if(IsDisabled($name));

 if ($opt eq "data") {
	 $hash->{detailLevel} = $vel_1;
     SMAInverter_GetData($hash);
 } else {
     return "$getlist";
 }
return undef;
}

###############################################################
#                  SMAInverter Attr
###############################################################
sub SMAInverter_Attr(@) {
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    my $hash = $defs{$name};
    my $do;

    if ($aName eq "mode") {
        if ($cmd eq "set" && $aVal eq "manual") {
            $hash->{INTERVAL} = $aVal;
        } else {
            $hash->{INTERVAL} = $hash->{HELPER}{INTERVAL};
        }
    InternalTimer(time+5, 'SMAInverter_GetData', $hash, 0);
    }

    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val   = ($do == 1 ?  "disabled" : "initialized");

        readingsSingleUpdate($hash, "state", $val, 1);

        if ($do == 0) {
            my $mode = AttrVal($name, "mode", "automatic");
            RemoveInternalTimer($hash);
            InternalTimer(time+5, 'SMAInverter_GetData', $hash, 0);
        } else {
            RemoveInternalTimer($hash);
        }
    }

    if ($aName eq "detail-level") {
        delete $defs{$name}{READINGS};
    }

    if ($aName eq "SBFSpotComp") {
        delete $defs{$name}{READINGS};
    }

    if ($aName eq "interval") {
        if ($cmd eq "set") {
            $hash->{HELPER}{INTERVAL} = $aVal;
            $hash->{INTERVAL} = $aVal if(AttrVal($name, "mode", "") ne "manual");
            delete($hash->{HELPER}{AVERAGEBUF}) if($hash->{HELPER}{AVERAGEBUF});
            Log3 $name, 3, "$name - Set $aName to $aVal";
        } else {
            $hash->{INTERVAL} = $hash->{HELPER}{INTERVAL} = 60;
        }
    }

    if ($cmd eq "set" && $aName eq "offset") {
            if($aVal !~ /^\d+$/ || $aVal < 0 || $aVal > 7200) { return "The Value of $aName is not valid. Use value between 0 ... 7200 !";}
    }
    if ($cmd eq "set" && $aName eq "timeout") {
        unless ($aVal =~ /^[0-9]+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
    }
return;
}

##########################################################################
#                            Encrypt Passwort/Username übernommen aus 76_SMAEVCharger.pm author: Jürgen Allmich
##########################################################################

sub SMAInverter_SMAencrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /crypt:/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'.$encoded;
}

##########################################################################
#                            Decrypt Passwort/Username übernommen aus 76_SMAEVCharger.pm author: Jürgen Allmich
##########################################################################

sub SMAInverter_SMAdecrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}

###############################################################
#                  Hauptschleife Datenabruf
###############################################################
sub SMAInverter_GetData($) {
 my ($hash) = @_;
 my $name = $hash->{NAME};
 my $interval = AttrVal($name, "interval", 60);
 my $timeout  = AttrVal($name, "timeout", 60);
 
 RemoveInternalTimer($hash, "SMAInverter_GetData");

 if ($init_done != 1) {
     InternalTimer(gettimeofday()+5, "SMAInverter_GetData", $hash, 0);
     return;
 }

 return if(IsDisabled($name));

 if (exists($hash->{HELPER}{RUNNING_PID})) {
     Log3 ($name, 3, "SMAInverter $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} will be killed now to start a new BlockingCall");
     BlockingKill($hash->{HELPER}{RUNNING_PID});
 }

 Log3 ($name, 4, "$name - ###############################################################");
 Log3 ($name, 4, "$name - ##########  Begin of new SMAInverter get data cycle  ##########");
 Log3 ($name, 4, "$name - ###############################################################");
 Log3 ($name, 4, "$name - timeout cycles since module start: $hash->{HELPER}{FAULTEDCYCLES}, Interval: $interval");

 # decide of operation
 if(AttrVal($name,"mode","automatic") eq "automatic") {
     # automatic operation mode
     InternalTimer(gettimeofday()+$interval, "SMAInverter_GetData", $hash, 0);
 }
 
 ##################################################################
 #neuer Tag
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
 my $firtRunDay = 0;
 
 if(ReadingsNum($name, ".yesterday", 0) ne $mday)
 {
	Log3 $name, 4, "$name -> new Day";
	$firtRunDay = 1;
	
	readingsSingleUpdate($hash,".yesterday",$mday, 1);
	#BlockingInformParent("SMAInverter_setReadingFromBlocking", [$name, ".yesterday", $mday], 0);
 }
 
  # ETOTAL speichern für ETODAY-Berechnung wenn WR ETODAY nicht liefert # Abnullen der TODAY werte
 if ($firtRunDay == 1) {    
      my $INVCLASS = InternalVal($name, "INVCLASS", 0);
      my $INVTYPE  = InternalVal($name, "INVTYPE", 0);
 
     my $val = 0;
     $val = ReadingsNum($name, "etotal", 0)*1000 if (exists $defs{$name}{READINGS}{etotal});
     $val = ReadingsNum($name, "SPOT_ETOTAL", 0) if (exists $defs{$name}{READINGS}{SPOT_ETOTAL});
	 
	 readingsSingleUpdate($hash,".etotal_yesterday",$val, 1);

	 # EPVTOTAL speichern für EPVTODAY-Berechnung wenn WR EPVTODAY nicht liefert # Abnullen der TODAY werte
	 if ($INVCLASS eq "8009") {                           
		 $val = ReadingsNum($name, "epvtotal", 0)*1000 if (exists $defs{$name}{READINGS}{epvtotal});
		 $val = ReadingsNum($name, "SPOT_EPVTOTAL", 0) if (exists $defs{$name}{READINGS}{SPOT_EPVTOTAL});
		 
		 readingsSingleUpdate($hash,".epvtotal_yesterday",$val, 1);
	 }

	 # BATTERYLOAD_TOTAL speichern für BAT_LOADTODAY-Berechnung wenn WR BAT_LOADTODAY nicht liefert # Abnullen der TODAY werte
	 if ($INVCLASS eq "8009" || $INVCLASS eq "8007") {
		 $val = ReadingsNum($name, "bat_loadtotal", 0)*1000 if (exists $defs{$name}{READINGS}{bat_loadtotal});
		 $val = ReadingsNum($name, "BAT_LOADTOTAL", 0)      if (exists $defs{$name}{READINGS}{BAT_LOADTOTAL});
		 
		 readingsSingleUpdate($hash,".bat_loadtotal_yesterday",$val, 1);
	 }

	 # BATTERYUNLOAD_TOTAL speichern für BAT_UNLOADTODAY-Berechnung wenn WR BAT_UNLOADTODAY nicht liefert # Abnullen der TODAY werte
	 if ($INVCLASS eq "8009" || $INVCLASS eq "8007") {                                        # V2.14.1, Forum: https://forum.fhem.de/index.php/topic,56080.msg1134664.html#msg1134664
		 $val = ReadingsNum($name, "bat_unloadtotal", 0)*1000 if (exists $defs{$name}{READINGS}{bat_unloadtotal});
		 $val = ReadingsNum($name, "BAT_UNLOADTOTAL", 0)      if (exists $defs{$name}{READINGS}{BAT_UNLOADTOTAL});
		 
		 readingsSingleUpdate($hash,".bat_unloadtotal_yesterday",$val, 1);
	 }
 }

$hash->{HELPER}{firtRunDay} = $firtRunDay;

Log3 ($name, 4, "$name - start BlockingCall");
$hash->{HELPER}{RUNNING_PID} = BlockingCall("SMAInverter_getstatusDoParse", "$name", "SMAInverter_getstatusParseDone", $timeout, "SMAInverter_getstatusParseAborted", $hash);
$hash->{HELPER}{RUNNING_PID}{loglevel} = 4;

return;
}

###############################################################
#          non-blocking Inverter Datenabruf
###############################################################
sub SMAInverter_getstatusDoParse($) {
 my ($name)   = @_;
 Log3 ($name, 4, "$name - running BlockingCall SMAInverter_getstatusDoParse");
  
 my $hash     = $defs{$name};
 my $interval = AttrVal($name, "interval", 60);
 my $sc       = AttrVal($name, "SBFSpotComp", 0);
 my ($sup_EnergyProduction,
     $sup_PVEnergyProduction,
	 $sup_Firmware,
     $sup_SpotDCPower,
	 $sup_SpotDCPower_2,
	 $sup_SpotDCPower_3,
     $sup_SpotACPower,
     $sup_MaxACPower,
     $sup_MaxACPower2,
     $sup_SpotACTotalPower,
     $sup_ChargeStatus,
     $sup_SpotDCVoltage,
	 $sup_SpotDCVoltage_2,
     $sup_SpotACVoltage,
	 $sup_SpotACCurrent,
	 $sup_SpotACCurrent_Backup,
     $sup_BatteryInfo,
	 $sup_BatteryInfo_2, 			#SBS(1.5|2.0|2.5)
	 $sup_BatteryInfo_3,
	 $sup_BatteryInfo_4, 
     $sup_BatteryInfo_5,	 
	 $sup_BatteryInfo_TEMP,
	 $sup_BatteryInfo_UDC,
	 $sup_BatteryInfo_IDC,
	 $sup_BatteryInfo_Capacity,
	 $sup_BatteryInfo_Capac,
	 $sup_BatteryInfo_Charge,
     $sup_SpotGridFrequency,
     $sup_TypeLabel,
     $sup_OperationTime,
     $sup_InverterTemperature,
     $sup_GridRelayStatus,
	 $sup_BackupRelayStatus,
	 $sup_GridConection,
	 $sup_OperatingStatus,
	 $sup_GeneralOperatingStatus,
	 $sup_WaitingTimeUntilFeedIn,
     $sup_SpotBatteryLoad,
     $sup_SpotBatteryUnload,
     $sup_DeviceStatus,
	 $sup_BatStatus,
	 $sup_Insulation,
	 $sup_lower_discharge_limit,
	 $sup_EM_1,
	 $sup_EM_2,
	 $sup_EM_3,
	 $sup_EM_4);
 
 my ($inv_TYPE, $inv_CLASS,
     $inv_SPOT_ETODAY, $inv_SPOT_ETOTAL,
	 $inv_SPOT_EPVTODAY, $inv_SPOT_EPVTOTAL,
     $inv_susyid,
     $inv_serial,
	 $inv_Firmware,
     $inv_SPOT_PDC,$inv_SPOT_PDC1, $inv_SPOT_PDC2, $inv_SPOT_PDC3, $inv_SPOT_PDC_sum,
     $inv_SPOT_PAC1, $inv_SPOT_PAC2, $inv_SPOT_PAC3, $inv_SPOT_PACTOT,
     $inv_PACMAX1, $inv_PACMAX2, $inv_PACMAX3, $inv_PACMAX1_2,
     $inv_ChargeStatus,
     $inv_SPOT_UDC1, $inv_SPOT_UDC2, $inv_SPOT_UDC3,
     $inv_SPOT_IDC1, $inv_SPOT_IDC2, $inv_SPOT_IDC3,
     $inv_SPOT_UAC1, $inv_SPOT_UAC2, $inv_SPOT_UAC3,
	 $inv_SPOT_UAC1_2, $inv_SPOT_UAC2_3, $inv_SPOT_UAC3_1,
     $inv_SPOT_IAC1, $inv_SPOT_IAC2, $inv_SPOT_IAC3,
	 $inv_SPOT_IAC1_Backup,$inv_SPOT_IAC2_Backup,$inv_SPOT_IAC3_Backup,
	 $sup_SpotACCurrentBackup, $inv_BAT_rated_capacity, $inv_BAT_Typ, $inv_BAT_STATUS,
	 $inv_SPOT_CosPhi,
     $inv_BAT_UDC, $inv_BAT_UDC_A, $inv_BAT_UDC_B, $inv_BAT_UDC_C, 
     $inv_BAT_IDC, $inv_BAT_IDC_A, $inv_BAT_IDC_B, $inv_BAT_IDC_C,
	 $inv_BAT_P_Charge, $inv_BAT_P_Discharge,
     $inv_BAT_CYCLES, $inv_BAT_CYCLES_A, $inv_BAT_CYCLES_B, $inv_BAT_CYCLES_C,
     $inv_BAT_TEMP, $inv_BAT_TEMP_A, $inv_BAT_TEMP_B, $inv_BAT_TEMP_C,
     $inv_BAT_LOADTODAY, $inv_BAT_LOADTOTAL, $inv_BAT_CAPACITY,$inv_BAT_UNLOADTODAY,$inv_BAT_UNLOADTOTAL,
	 $inv_BAT_Manufacturer,
	 $inv_BAT_lower_discharge_limit,
     $inv_SPOT_FREQ, $inv_SPOT_OPERTM, $inv_SPOT_FEEDTM, $inv_TEMP, $inv_GRIDRELAY, $inv_STATUS,
	 $inv_BACKUPRELAY, $inv_OperatingStatus, $inv_GeneralOperatingStatus, $inv_WaitingTimeUntilFeedIn, $inv_GridConection, 
	 $Meter_Grid_FeedIn, $Meter_Grid_Consumation,$Meter_Total_Yield,$Meter_Total_Consumation,
	 $Meter_Power_Grid_FeedIn,$Meter_Power_Grid_Consumation,
	 $Meter_Grid_FeedIn_PAC1, $Meter_Grid_FeedIn_PAC2, $Meter_Grid_FeedIn_PAC3, $Meter_Grid_Consumation_PAC1, $Meter_Grid_Consumation_PAC2, $Meter_Grid_Consumation_PAC3,
	 $inv_DC_insulation, $inv_DC_Residual_Current);

 my @row_array;
 my @array;
 my $avg = 0;
 my ($ist,$bst,$irt,$brt,$rt);
 my $INVCLASS 					= InternalVal($name, "INVCLASS", 0);
 my $INVTYPE  					= InternalVal($name, "INVTYPE", 0);
 my $INVTYPE_NAME 				= ReadingsVal($name,"INV_TYPE",ReadingsVal($name,"device_type",""));
 my $firtRunDay 				= $hash->{HELPER}{firtRunDay};
 my $readParameter 				= 0;
 my $INVFWMAIN 					= InternalVal($name, "INVFWMAIN", 0);
 my $installer 					= AttrVal($name, "installerLogin", "0");
  
 Log3 ($name, 4, "$name -> INVCLASS $INVCLASS");
 Log3 ($name, 4, "$name -> INVTYPE $INVTYPE");	
 
 if((InternalVal($name, "eventCount", 0) % 50) == 0)
 {
	Log3 $name, 4, "$name -> read Parameter";
	$readParameter = 1;
 }
 
 # Background-Startzeit
 $bst = [gettimeofday];
 
 Log3 ($name, 4, "$name -> start BlockingCall SMAInverter_getstatusDoParse");

 # set dependency from surise/sunset used for inverter operation time
 my $offset = AttrVal($name,"offset",0);
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();

 my ($sunrise_h,$sunrise_m,$sunrise_s) = split(":",sunrise_abs('-'.$offset));
 my ($sunset_h,$sunset_m,$sunset_s)    = split(":",sunset_abs('+'.$offset));

 my $oper_start   = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>$sunrise_h,minute=>$sunrise_m,second=>$sunrise_s,time_zone=>'local');
 my $oper_stop    = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>$sunset_h,minute=>$sunset_m,second=>$sunset_s,time_zone=>'local');
 #my $oper_start_d = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>00,minute=>10,second=>00,time_zone=>'local');
 my $dt_now       = DateTime->now(time_zone=>'local');

 # if(ReadingsNum($name, ".yesterday", 0) ne $mday)
 # {
	# Log3 $name, 4, "$name -> new Day";
	# $firtRunDay = 1;
	
	# BlockingInformParent("SMAInverter_setReadingFromBlocking", [$name, ".yesterday", $mday], 0);
 # }

 Log3 $name, 4, "$name - current time: ".$dt_now->dmy('.')." ".$dt_now->hms;
 Log3 $name, 4, "$name - operation time begin: ".$oper_start->dmy('.')." ".$oper_start->hms;
 Log3 $name, 4, "$name - operation time end: ".$oper_stop->dmy('.')." ".$oper_stop->hms;

 my $opertime_start = $oper_start->dmy('.')." ".$oper_start->hms;
 my $opertime_stop  = $oper_stop->dmy('.')." ".$oper_stop->hms;

 # ETOTAL speichern für ETODAY-Berechnung wenn WR ETODAY nicht liefert # Abnullen der TODAY werte
 if ($firtRunDay == 1) {                                        # V2.14.1, Forum: https://forum.fhem.de/index.php/topic,56080.msg1134664.html#msg1134664
     # my $val = 0;
     # $val = ReadingsNum($name, "etotal", 0)*1000 if (exists $defs{$name}{READINGS}{etotal});
     # $val = ReadingsNum($name, "SPOT_ETOTAL", 0) if (exists $defs{$name}{READINGS}{SPOT_ETOTAL});
     # BlockingInformParent("SMAInverter_setReadingFromBlocking", [$name, ".etotal_yesterday", $val], 0);
	 if ($sc) {	
		push(@row_array, "etoday 0\n");
	 }
	 else {
		push(@row_array, "SPOT_ETODAY 0\n");
	 }
}
 
 # EPVTOTAL speichern für EPVTODAY-Berechnung wenn WR EPVTODAY nicht liefert # Abnullen der TODAY werte
 if ($firtRunDay == 1 && $INVCLASS eq "8009") {                           
     # my $val = 0;
     # $val = ReadingsNum($name, "epvtotal", 0)*1000 if (exists $defs{$name}{READINGS}{epvtotal});
     # $val = ReadingsNum($name, "SPOT_EPVTOTAL", 0) if (exists $defs{$name}{READINGS}{SPOT_EPVTOTAL});
     # BlockingInformParent("SMAInverter_setReadingFromBlocking", [$name, ".epvtotal_yesterday", $val], 0);
	 if ($sc) {	
		push(@row_array, "epvtoday 0\n");
	 }
	 else {
		push(@row_array, "SPOT_EPVTODAY 0\n");
	 }
 }

 # BATTERYLOAD_TOTAL speichern für BAT_LOADTODAY-Berechnung wenn WR BAT_LOADTODAY nicht liefert # Abnullen der TODAY werte
 if ($firtRunDay == 1 && ($INVCLASS eq "8009" || $INVCLASS eq "8007")) {
     # my $val = 0;
     # $val = ReadingsNum($name, "bat_loadtotal", 0)*1000 if (exists $defs{$name}{READINGS}{bat_loadtotal});
     # $val = ReadingsNum($name, "BAT_LOADTOTAL", 0)      if (exists $defs{$name}{READINGS}{BAT_LOADTOTAL});
     # BlockingInformParent("SMAInverter_setReadingFromBlocking", [$name, ".bat_loadtotal_yesterday", $val], 0);
	 if ($sc) {	
		push(@row_array, "bat_loadtoday 0\n");
	 }
	 else {
		push(@row_array, "BAT_LOADTODAY 0\n");
	 }
 }

 # BATTERYUNLOAD_TOTAL speichern für BAT_UNLOADTODAY-Berechnung wenn WR BAT_UNLOADTODAY nicht liefert # Abnullen der TODAY werte
 if ($firtRunDay == 1 && ($INVCLASS eq "8009" || $INVCLASS eq "8007")) {                                        # V2.14.1, Forum: https://forum.fhem.de/index.php/topic,56080.msg1134664.html#msg1134664
     # my $val = 0;
     # $val = ReadingsNum($name, "bat_unloadtotal", 0)*1000 if (exists $defs{$name}{READINGS}{bat_unloadtotal});
     # $val = ReadingsNum($name, "BAT_UNLOADTOTAL", 0)      if (exists $defs{$name}{READINGS}{BAT_UNLOADTOTAL});
     # BlockingInformParent("SMAInverter_setReadingFromBlocking", [$name, ".bat_unloadtotal_yesterday", $val], 0);
	 if ($sc) {	
		push(@row_array, "bat_unloadtoday 0\n");
	 }
	 else {
		push(@row_array, "BAT_UNLOADTODAY 0\n");
	 }
 }
 
 my $suppressSleep = AttrVal($name,"suppressSleep",-1);
 
 if($suppressSleep < 0)
 {
	if($INVCLASS eq "8009" || $INVCLASS eq "8007")
	{
		$suppressSleep = 1;
	}
	else
	{
		$suppressSleep = 0;
	}
 }
 
 if (($oper_start <= $dt_now && $dt_now <= $oper_stop) || AttrVal($name,"suppressSleep",0)) {
     # normal operation or suppressed sleepmode

     # Abfrage Inverter Startzeit
     $ist = [gettimeofday];

     # Get the current attributes
	 my $detail_level  		= InternalVal($name, "detailLevel", "");
	 $detail_level  		= AttrVal($name, "detail-level", 0) if ($detail_level eq "" || $detail_level eq "-");
	 $hash->{detailLevel} 	= "";
	 
	 if($detail_level eq "parameter")
	 {
		 $detail_level  	= 2;
		 $readParameter 	= 1;
	 }
     
	 Log3 $name, 4, "$name - detail-level: ".$detail_level;
	 
     my $readEnergyMeter_data  = AttrVal($name, "readEnergyMeter-data", 0);
	  
     # Aufbau Command-Array
     my @commands = ("sup_TypeLabel",                  # Check TypeLabel
                     "sup_EnergyProduction",           # Check EnergyProduction
                     "sup_SpotDCPower",                # Check SpotDCPower
                     "sup_SpotACPower",                # Check SpotACPower
                     "sup_SpotACTotalPower"            # Check SpotACTotalPower             
                     );
	 
	 if($INVCLASS eq "8009" || $INVCLASS eq "8007")
	 {
		push(@commands, "sup_ChargeStatus"); 				# Check BatteryChargeStatus
		push(@commands, "sup_SpotBatteryLoad");       	    # Check Batteryload
		push(@commands, "sup_SpotBatteryUnload");       	# Check BatteryUnload
	 }
	 
	 if ($INVTYPE_NAME =~ /SBS(6\.0|5\.0|3\.7)/xs)
	 {
		push(@commands, "sup_BatteryInfo_UDC");     # Check BatteryInfo Voltage
		push(@commands, "sup_BatteryInfo_IDC");     # Check BatteryInfo current
	 }
	 elsif ($INVTYPE_NAME =~ /SBS(1\.5|2\.0|2\.5)/xs || $INVCLASS eq "8009")
	 {
		push(@commands, "sup_BatteryInfo_2");     # Check BatteryInfo Voltage
		push(@commands, "sup_BatteryInfo_Charge");
	 }
	 elsif($INVCLASS eq "8009" || $INVCLASS eq "8007")
	 {
		push(@commands, "sup_BatteryInfo");        	# Check BatteryInfo 
	 }
	 
	 push(@commands, "sup_PVEnergyProduction") if($INVCLASS eq "8009");    						# Check PV-EnergyProduction (Hybrid Inverter)
     push(@commands, "sup_SpotDCPower_3")      if($INVCLASS eq "8009" || $INVCLASS eq "8001");  # SpotDCPower summary
	 
     if($detail_level > 0) {
         # Detail Level 1 or 2 >> get voltage and current levels
         push(@commands, "sup_SpotDCVoltage");         # Check SpotDCVoltage
         push(@commands, "sup_SpotACVoltage");         # Check SpotACVoltage
		 push(@commands, "sup_SpotACCurrent");         # Check SpotACCurrent
		 
		 if($INVCLASS eq "8009")
		 {
			push(@commands, "sup_SpotACCurrentBackup");   # Check BatteryInfo 
		 }
     }

     if($detail_level > 1) {
          # Detail Level 2 >> get all data
          push(@commands, "sup_SpotGridFrequency");     # Check SpotGridFrequency
          push(@commands, "sup_OperationTime");         # Check OperationTime
          #push(@commands, "sup_InverterTemperature");   # Check InverterTemperature ?
          push(@commands, "sup_MaxACPower");            # Check MaxACPower
          push(@commands, "sup_MaxACPower2");           # Check MaxACPower2 ?
          push(@commands, "sup_GridRelayStatus");       # Check GridRelayStatus
          push(@commands, "sup_DeviceStatus");          # Check DeviceStatus

		  push(@commands, "sup_Firmware") if($readParameter == 1); #Read WR Firmwareversion
		  
		  if ($INVTYPE_NAME =~ /SBS(6\.0|5\.0|3\.7)/xs)
		  {
			push(@commands, "sup_BatteryInfo_TEMP");    # Check BatteryInfo Temperatur
			push(@commands, "sup_BatteryInfo_Capac") if($readParameter == 1);   # Check BatteryInfo capacity
		  }
		  
		  if ($INVCLASS eq "8007" || $INVCLASS eq "8009")
		  {
		    push(@commands, "sup_BatStatus");          # Check DeviceStatus
			push(@commands, "sup_BatteryInfo_Capacity") if($readParameter == 1);  # Check BatteryInfo capacity
			#push(@commands, "sup_BatteryInfo_3");     
			push(@commands, "sup_BatteryInfo_4") if($readParameter == 1);   # Check BatteryInfo rated apacity 
			#push(@commands, "sup_BatteryInfo_5");    
		  }
		  
		  push(@commands, "sup_lower_discharge_limit") if($readParameter == 1 && $INVCLASS eq "8009");
		  
		  push(@commands, "sup_Insulation") if($installer == 1);  # Isolationsüberwachung
		  	
		  push(@commands, "sup_GeneralOperatingStatus");			
		  push(@commands, "sup_OperatingStatus") if($INVCLASS eq "8009" || $INVTYPE_NAME =~ /SI/xs); 
		  push(@commands, "sup_BackupRelayStatus") if($INVCLASS eq "8009"); 
		  push(@commands, "sup_GridConection") if($INVTYPE_NAME =~ /SI/xs); #nur SI Wechselrichter (Hybrids haben diesen Wert auch aber diese ändert sich weder im WR noch im Reading also unnötig)
		  #push(@commands, "sup_WaitingTimeUntilFeedIn") if($INVCLASS eq "8009"); 
     }
	 
	 if($readEnergyMeter_data > 0) {
		push(@commands, "sup_EM_1");   # EM Data 1 
		push(@commands, "sup_EM_2");   # EM Data 2 
		push(@commands, "sup_EM_3");   # EM Data 3 
		push(@commands, "sup_EM_4");   # EM Data 4 
	 }

     Log3 $name, 5, "$name - ".ReadingsVal($name,"INV_TYPE","")."".ReadingsVal($name,"device_type","");
	 
	 
     if(SMAInverter_SMAlogon($hash->{HOST}, $hash->{PASS}, $hash)) {
         Log3 $name, 5, "$name - Logged in now";

         for my $i(@commands) {
             if ($i eq "sup_TypeLabel") {
			      Log3 $name, 5, "$name -> sup_TypeLabel";
                 ($sup_TypeLabel,$inv_TYPE,$inv_CLASS,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x58000200, 0x00821E00, 0x008220FF);
             }
             elsif ($i eq "sup_EnergyProduction") {
			      Log3 $name, 5, "$name -> sup_EnergyProduction";
                 ($sup_EnergyProduction,$inv_SPOT_ETODAY,$inv_SPOT_ETOTAL,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x00260100, 0x002622FF);
             }
			 elsif ($i eq "sup_PVEnergyProduction") {
			     Log3 $name, 5, "$name -> sup_PVEnergyProduction";
                 ($sup_PVEnergyProduction,$inv_SPOT_EPVTODAY,$inv_SPOT_EPVTOTAL,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x0046c300, 0x0046c3FF);
             }
             elsif ($i eq "sup_SpotDCPower") {
			      Log3 $name, 5, "$name -> sup_SpotDCPower";
                 ($sup_SpotDCPower,$inv_SPOT_PDC1,$inv_SPOT_PDC2,$inv_SPOT_PDC3,$inv_SPOT_PDC_sum,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x53800200, 0x00251E00, 0x00251EFF);
             }
			 elsif ($i eq "sup_SpotDCPower_3") {
			     Log3 $name, 5, "$name -> sup_SpotDCPower_3";
                 ($sup_SpotDCPower_3,$inv_SPOT_PDC,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x0046c200, 0x0046c2FF);
             }
             elsif ($i eq "sup_SpotACPower") {
			      Log3 $name, 5, "$name -> sup_SpotACPower";
                 ($sup_SpotACPower,$inv_SPOT_PAC1,$inv_SPOT_PAC2,$inv_SPOT_PAC3,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00464000, 0x004642FF);
             }
             elsif ($i eq "sup_SpotACTotalPower") {
			      Log3 $name, 5, "$name -> sup_SpotACTotalPower";
                 ($sup_SpotACTotalPower,$inv_SPOT_PACTOT,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00263F00, 0x00263FFF);
             }
             elsif ($i eq "sup_ChargeStatus") {
			      Log3 $name, 5, "$name -> sup_ChargeStatus";
                 ($sup_ChargeStatus,$inv_ChargeStatus,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00295A00, 0x00295AFF);
             }
             elsif ($i eq "sup_SpotDCVoltage") {
			      Log3 $name, 5, "$name -> sup_SpotDCVoltage";
                 ($sup_SpotDCVoltage,$inv_SPOT_UDC1,$inv_SPOT_UDC2,$inv_SPOT_UDC3,$inv_SPOT_IDC1,$inv_SPOT_IDC2,$inv_SPOT_IDC3,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x53800200, 0x00451F00, 0x004521FF);
             }
             elsif ($i eq "sup_SpotACVoltage") {
			      Log3 $name, 5, "$name -> sup_SpotACVoltage";
                 ($sup_SpotACVoltage,$inv_SPOT_UAC1,$inv_SPOT_UAC2,$inv_SPOT_UAC3,$inv_SPOT_UAC1_2,$inv_SPOT_UAC2_3,$inv_SPOT_UAC3_1,$inv_SPOT_CosPhi,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00464800, 0x004656FF);
             }
			 elsif ($i eq "sup_SpotACCurrent") {
				 Log3 $name, 5, "$name -> sup_SpotACCurrent";
                 ($sup_SpotACCurrent,$inv_SPOT_IAC1,$inv_SPOT_IAC2,$inv_SPOT_IAC3,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00465300, 0x004655FF);
             }
			 elsif ($i eq "sup_SpotACCurrentBackup") {
				 Log3 $name, 5, "$name -> sup_SpotACCurrentBackup";
                 ($sup_SpotACCurrent_Backup,$inv_SPOT_IAC1_Backup,$inv_SPOT_IAC2_Backup,$inv_SPOT_IAC3_Backup,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x40574600, 0x405748FF);
             }
		     elsif ($i eq "sup_BatteryInfo_TEMP") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo_TEMP";
                 ($sup_BatteryInfo_TEMP,$inv_BAT_TEMP,$inv_BAT_TEMP_A,$inv_BAT_TEMP_B,$inv_BAT_TEMP_C,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00495B00, 0x00495B10);
		     }    
			 elsif ($i eq "sup_BatteryInfo_UDC") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo_UDC";
                 ($sup_BatteryInfo_UDC,$inv_BAT_UDC,$inv_BAT_UDC_A,$inv_BAT_UDC_B,$inv_BAT_UDC_C,$inv_susyid,$inv_serial)     = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00495C00, 0x00495C10);
		     }  
			 elsif ($i eq "sup_BatteryInfo_IDC") {
				 Log3 $name, 5, "$name -> sup_BatteryInfo_IDC";
                 ($sup_BatteryInfo_IDC,$inv_BAT_IDC,$inv_BAT_IDC_A,$inv_BAT_IDC_B,$inv_BAT_IDC_C,$inv_susyid,$inv_serial)     = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00495D00, 0x00495D10);
		     }
			 elsif ($i eq "sup_BatteryInfo_Charge") {
				 Log3 $name, 5, "$name -> sup_BatteryInfo_Charge";
                 ($sup_BatteryInfo_Charge,$inv_BAT_P_Charge,$inv_BAT_P_Discharge,$inv_susyid,$inv_serial)     = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00496900, 0x00496AFF);
		     }
             elsif ($i eq "sup_BatteryInfo_Capacity") {
				 Log3 $name, 5, "$name -> sup_BatteryInfo_Capacity";
                 ($sup_BatteryInfo_Capacity,$inv_BAT_CAPACITY,$inv_susyid,$inv_serial)     = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00696E00, 0x00696E10);
		     }
		     elsif ($i eq "sup_BatteryInfo_Capac") {
				 Log3 $name, 5, "$name -> sup_BatteryInfo_Capac";
                 #($sup_BatteryInfo_IDC,$inv_BAT_IDC,$inv_BAT_IDC_A,$inv_BAT_IDC_B,$inv_BAT_IDC_C,$inv_susyid,$inv_serial)     = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00496800, 0x004968FF);
		     }  			 
             elsif ($i eq "sup_BatteryInfo") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo";
                 ($sup_BatteryInfo,$inv_BAT_CYCLES,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00491E00, 0x00495DFF);
             }
			 elsif ($i eq "sup_BatteryInfo_2") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo_2";
                 ($sup_BatteryInfo_2,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00491E00, 0x00495DFF);
		     }
			 elsif ($i eq "sup_BatteryInfo_3") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo_3";
                 ($sup_BatteryInfo_3,$inv_BAT_Manufacturer,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x58020200, 0x08822C00, 0x08822CFF);
             }
			 elsif ($i eq "sup_BatteryInfo_4") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo_4";
                 ($sup_BatteryInfo_4,$inv_BAT_rated_capacity,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x58000200, 0x00893700, 0x008937FF);
             }
			 elsif ($i eq "sup_BatteryInfo_5") {
			     Log3 $name, 5, "$name -> sup_BatteryInfo_5";
                 ($sup_BatteryInfo_5,$inv_BAT_Typ,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x58020200, 0x00B18900, 0x00B189FF);
             }			 
             elsif ($i eq "sup_SpotGridFrequency") {
			     Log3 $name, 5, "$name -> sup_SpotGridFrequency";
                 ($sup_SpotGridFrequency,$inv_SPOT_FREQ,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00465700, 0x004657FF);
             }
             elsif ($i eq "sup_OperationTime") {
			     Log3 $name, 5, "$name -> sup_OperationTime";
                 ($sup_OperationTime,$inv_SPOT_OPERTM,$inv_SPOT_FEEDTM,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x00462E00, 0x00462FFF);
             }
             elsif ($i eq "sup_InverterTemperature") {
			     Log3 $name, 5, "$name -> sup_InverterTemperature";
                 ($sup_InverterTemperature,$inv_TEMP,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x52000200, 0x00237700, 0x002377FF);
             }
             elsif ($i eq "sup_MaxACPower") {
			     Log3 $name, 5, "$name -> sup_MaxACPower";
                 ($sup_MaxACPower,$inv_PACMAX1,$inv_PACMAX2,$inv_PACMAX3,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00411E00, 0x004120FF);
             }
             elsif ($i eq "sup_MaxACPower2") {
			     Log3 $name, 5, "$name -> sup_MaxACPower2";
                 ($sup_MaxACPower2,$inv_PACMAX1_2,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00832A00, 0x00832AFF);
             }
             elsif ($i eq "sup_GridRelayStatus") {
			     Log3 $name, 5, "$name -> sup_GridRelayStatus";
                 ($sup_GridRelayStatus,$inv_GRIDRELAY,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x00416400, 0x004164FF);
             }
			 elsif ($i eq "sup_BackupRelayStatus") {
			     Log3 $name, 5, "$name -> sup_BackupRelayStatus";
                 ($sup_BackupRelayStatus,$inv_BACKUPRELAY,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x08412500, 0x084125FF);
             }
			 elsif ($i eq "sup_GridConection") {
			     Log3 $name, 5, "$name -> sup_GridConection";
                 ($sup_GridConection,$inv_GridConection,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x0846A600, 0x0846A6FF);
             }
			 elsif ($i eq "sup_OperatingStatus") {
                 Log3 $name, 5, "$name -> sup_OperatingStatus";
				 ($sup_OperatingStatus,$inv_OperatingStatus,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x08412B00, 0x08412BFF);
             }
			 elsif ($i eq "sup_GeneralOperatingStatus") {
                 Log3 $name, 5, "$name -> sup_GeneralOperatingStatus";
				 ($sup_GeneralOperatingStatus,$inv_GeneralOperatingStatus,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x08412800, 0x084128FF);
             }
			 elsif ($i eq "sup_WaitingTimeUntilFeedIn") {
                 Log3 $name, 5, "$name -> sup_WaitingTimeUntilFeedIn";
				 ($sup_WaitingTimeUntilFeedIn,$inv_WaitingTimeUntilFeedIn,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x00416600, 0x004166FF);
             }
             elsif ($i eq "sup_DeviceStatus") {
			     Log3 $name, 5, "$name -> sup_DeviceStatus";
                 ($sup_DeviceStatus,$inv_STATUS,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x00214800, 0x002148FF);
             }
			 elsif ($i eq "sup_BatStatus") {
			     Log3 $name, 5, "$name -> sup_BatStatus";
                 ($sup_BatStatus,$inv_BAT_STATUS,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51800200, 0x08214800, 0x082148FF);
             }
             elsif ($i eq "sup_SpotBatteryLoad") {
			     Log3 $name, 5, "$name -> sup_SpotBatteryLoad";
                 ($sup_SpotBatteryLoad,$inv_BAT_LOADTODAY,$inv_BAT_LOADTOTAL,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x00496700, 0x004967FF);
             }
             elsif ($i eq "sup_SpotBatteryUnload") {
			     Log3 $name, 5, "$name -> sup_SpotBatteryUnload";
                 ($sup_SpotBatteryUnload,$inv_BAT_UNLOADTODAY,$inv_BAT_UNLOADTOTAL,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x00496800, 0x004968FF);
             }
			 elsif ($i eq "sup_EM_1") {
			     Log3 ($name, 4, "$name -> EM 1");
                 ($sup_EM_1,$Meter_Total_Yield,$Meter_Total_Consumation,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x00462400, 0x004628FF);
             }
			 elsif ($i eq "sup_EM_2") {
			     Log3 ($name, 4, "$name -> EM 2");
                 ($sup_EM_2,$Meter_Grid_FeedIn,$Meter_Grid_Consumation,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x54000200, 0x40469100, 0x404692FF);
             }
			 elsif ($i eq "sup_EM_3") {
			     Log3 ($name, 4, "$name -> EM 3");
                 ($sup_EM_3,$Meter_Power_Grid_FeedIn,$Meter_Power_Grid_Consumation,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x40463600, 0x404637FF);
             }
			 elsif ($i eq "sup_EM_4") {
			     Log3 ($name, 4, "$name -> EM 4");
                 ($sup_EM_4,$Meter_Grid_FeedIn_PAC1, $Meter_Grid_FeedIn_PAC2, $Meter_Grid_FeedIn_PAC3, $Meter_Grid_Consumation_PAC1, $Meter_Grid_Consumation_PAC2, $Meter_Grid_Consumation_PAC3,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51000200, 0x0046E800, 0x0046EDFF);
             }
			 elsif ($i eq "sup_Insulation") {
			     Log3 ($name, 4, "$name -> sup_Insulation");
                 ($sup_Insulation,$inv_DC_Residual_Current,$inv_DC_insulation,,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x51020200, 0x40254E00, 0x40254FFF);
             }
			 elsif ($i eq "sup_Firmware") {
			     Log3 ($name, 4, "$name -> sup_Firmware");
                 ($sup_Firmware,$inv_Firmware,$INVFWMAIN,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x58000200, 0x00823400, 0x008234FF);
             }
			 elsif ($i eq "sup_lower_discharge_limit") {
			     Log3 ($name, 4, "$name -> sup_lower_discharge_limit");
                 ($sup_lower_discharge_limit,$inv_BAT_lower_discharge_limit,$inv_susyid,$inv_serial) = SMAInverter_SMAcommand($hash, $hash->{HOST}, 0x58000000, 0x40895B00, 0x40895BFF);
             }
		     else {Log3 ($name, 4, "$name -> sup no case");}
         }
		 
		 $INVCLASS = $inv_CLASS if(defined $inv_CLASS);
         $INVTYPE  = $inv_TYPE  if(defined $inv_TYPE);

         # nothing more to do, just log out
         SMAInverter_SMAlogout($hash,$hash->{HOST});

         # Inverter Laufzeit ermitteln
         $irt = tv_interval($ist);

         # Aufbau Ergebnis-Array
         push(@row_array, "modulstate normal"."\n");
         push(@row_array, "opertime_start ".$opertime_start."\n");
         push(@row_array, "opertime_stop ".$opertime_stop."\n");

         # Durchschnittswerteberechnung Energieerzeugung der letzten 5, 10, 15 Messungen

         my ($sum05, $sum10, $sum15);
         my $cnt05  = int(300/$interval);          # Anzahl der Zyklen innerhalb 5 Minuten
         my $cnt10  = int(600/$interval);          # Anzahl der Zyklen innerhalb 10 Minuten
         my $cnt15  = int(900/$interval);          # Anzahl der Zyklen innerhalb 15 Minuten = Summe aller Messzyklen
         my $cntsum = $cnt15+1;                    # Sicherheitszuschlag Summe Anzahl aller Zyklen
         my @averagebuf;
         if ($sup_TypeLabel && $sup_SpotACTotalPower && $inv_CLASS =~ /8001|8002|8007|8009/xs) {
		     my $power = $inv_SPOT_PACTOT;
			 $power = $inv_SPOT_PDC if($inv_CLASS =~ /8009/xs); #DC Leistung bei Hybrid verwenden
			 
             # only for this block because of warnings if values not set at restart
             no warnings 'uninitialized';
             if (!$hash->{HELPER}{AVERAGEBUF}) {
                 for my $count (0..$cntsum) {
                     # fill with new values
                     $power = $power // 0;
                     push(@averagebuf, $power);
                 }
             } else {
                 @averagebuf = split(/,/, $hash->{HELPER}{AVERAGEBUF})
             }

             pop(@averagebuf);                                                     # rechtes Element aus average buffer löschen
             unshift(@averagebuf, $power);                               # und links mit neuem Wert füllen
             $avg = join(',', @averagebuf);

             # calculate average energy and write to array for generate readings
             my $k = 1;
             my $avgsum = $averagebuf[0];
             while ($k < $cntsum) {
                 $avgsum = $avgsum + $averagebuf[$k] if($averagebuf[$k]);
                 if ($k == $cnt05) {
                     $sum05 = $avgsum;
                     Log3 $name, 5, "$name - CNT05: $cnt05 SUM05: $sum05";
                 }
                 if ($k == $cnt10) {
                     $sum10 = $avgsum;
                     Log3 $name, 5, "$name - CNT10: $cnt10 SUM10: $sum10";
                 }
                 if ($k == $cnt15) {
                     $sum15 = $avgsum;
                     Log3 $name, 5, "$name - CNT15: $cnt15 SUM15: $sum15";
                 }
                 $k++;
             }

             my $AvP05 = int( $sum05 / ($cnt05+1) );
             my $AvP10 = int( $sum10 / ($cnt10+1) );
             my $AvP15 = int( $sum15 / ($cnt15+1) );
             Log3 $name, 5, "$name - Content of Averagebuffer:";
             Log3 $name, 5, "$name - $avg";
             Log3 $name, 5, "$name - avg_power_lastminutes_05 = $AvP05, avg_power_lastminutes_10 = $AvP10, avg_power_lastminutes_15 = $AvP15";

             push(@row_array, "avg_power_lastminutes_05 ".$AvP05."\n");   # Average Energy (last) 5 minutes
             push(@row_array, "avg_power_lastminutes_10 ".$AvP10."\n");   # Average Energy (last) 10 minutes
             push(@row_array, "avg_power_lastminutes_15 ".$AvP15."\n");   # Average Energy (last) 15 minutes
				
             use warnings;
         }
		 
			 if($sup_TypeLabel) {
				 push(@row_array, ($sc?"device_type ":"INV_TYPE ").SMAInverter_devtype($inv_TYPE)."\n");
				 push(@row_array, ($sc?"device_class ":"INV_CLASS ").SMAInverter_classtype($inv_CLASS)."\n");
			 }
		 	 
			 if($sup_EM_1) {
		         push(@row_array, ($sc?"Meter_TOTAL_FeedIn ".($Meter_Total_Yield/1000):"Meter_TOTAL_FeedIn ".($Meter_Total_Yield))."\n") if ($Meter_Total_Yield ne "-");
                 push(@row_array, ($sc?"Meter_TOTAL_Consumation ".($Meter_Total_Consumation/1000):"Meter_TOTAL_Consumation ".$Meter_Total_Consumation)."\n") if ($Meter_Total_Consumation ne "-");
		     }
			 
			 if($sup_EM_2) {
		         push(@row_array, ($sc?"Meter_TOTAL_Grid_FeedIn ".($Meter_Grid_FeedIn/1000):"Meter_TOTAL_Grid_FeedIn ".$Meter_Grid_FeedIn)."\n") if ($Meter_Grid_FeedIn ne "-");
                 push(@row_array, ($sc?"Meter_TOTAL_Grid_Consumation ".($Meter_Grid_Consumation/1000):"Meter_TOTAL_Grid_Consumation ".$Meter_Grid_Consumation)."\n") if ($Meter_Grid_Consumation ne "-");
		     }
			 
			 if($sup_EM_3) {
		         push(@row_array, ($sc?"Meter_Power_Grid_FeedIn ".($Meter_Power_Grid_FeedIn/1000):"Meter_Power_Grid_FeedIn ".$Meter_Power_Grid_FeedIn)."\n") if ($Meter_Power_Grid_FeedIn ne "-");
                 push(@row_array, ($sc?"Meter_Power_Grid_Consumation ".($Meter_Power_Grid_Consumation/1000):"Meter_Power_Grid_Consumation ".$Meter_Power_Grid_Consumation)."\n") if ($Meter_Power_Grid_Consumation ne "-");
		     }
			 
			 if($sup_EM_4) {
		         push(@row_array, ($sc?"Meter_Grid_FeedIn_phase_1_pac ".($Meter_Grid_FeedIn_PAC1/1000):"Meter_Grid_FeedIn_PAC1 ".($Meter_Grid_FeedIn_PAC1))."\n") if ($Meter_Grid_FeedIn_PAC1 ne "-");
                 push(@row_array, ($sc?"Meter_Grid_FeedIn_phase_2_pac ".($Meter_Grid_FeedIn_PAC2/1000):"Meter_Grid_FeedIn_PAC2 ".($Meter_Grid_FeedIn_PAC2))."\n") if ($Meter_Grid_FeedIn_PAC2 ne "-");
				 push(@row_array, ($sc?"Meter_Grid_FeedIn_phase_3_pac ".($Meter_Grid_FeedIn_PAC3/1000):"Meter_Grid_FeedIn_PAC3 ".($Meter_Grid_FeedIn_PAC3))."\n") if ($Meter_Grid_FeedIn_PAC3 ne "-");
				 
				 push(@row_array, ($sc?"Meter_Grid_Consumation_phase_1_pac ".($Meter_Grid_Consumation_PAC1/1000):"Meter_Grid_Consumation_PAC1 ".($Meter_Grid_Consumation_PAC1))."\n") if ($Meter_Grid_Consumation_PAC1 ne "-");
                 push(@row_array, ($sc?"Meter_Grid_Consumation_phase_2_pac ".($Meter_Grid_Consumation_PAC2/1000):"Meter_Grid_Consumation_PAC2 ".($Meter_Grid_Consumation_PAC2))."\n") if ($Meter_Grid_Consumation_PAC2 ne "-");
				 push(@row_array, ($sc?"Meter_Grid_Consumation_phase_3_pac ".($Meter_Grid_Consumation_PAC3/1000):"Meter_Grid_Consumation_PAC3 ".($Meter_Grid_Consumation_PAC3))."\n") if ($Meter_Grid_Consumation_PAC3 ne "-");
		     }
		 
             if($sup_EnergyProduction) {
                 push(@row_array, ($sc?"etotal ".($inv_SPOT_ETOTAL/1000):"SPOT_ETOTAL ".$inv_SPOT_ETOTAL)."\n")  if ($inv_SPOT_ETOTAL ne "-");
                 push(@row_array, ($sc?"etoday ".($inv_SPOT_ETODAY/1000):"SPOT_ETODAY ".$inv_SPOT_ETODAY)."\n") if ($inv_SPOT_ETODAY ne "-");
             }
			 if($sup_PVEnergyProduction) {
                 push(@row_array, ($sc?"epvtotal ".($inv_SPOT_EPVTOTAL/1000):"SPOT_EPVTOTAL ".$inv_SPOT_EPVTOTAL)."\n")  if ($inv_SPOT_EPVTOTAL ne "-");
                 push(@row_array, ($sc?"epvtoday ".($inv_SPOT_EPVTODAY/1000):"SPOT_EPVTODAY ".$inv_SPOT_EPVTODAY)."\n") if ($inv_SPOT_EPVTODAY ne "-");
             }
             if($sup_SpotDCPower) {
                 push(@row_array, ($sc?"string_1_pdc ".sprintf("%.3f",$inv_SPOT_PDC1/1000):"SPOT_PDC1 ".$inv_SPOT_PDC1)."\n") if ($inv_SPOT_PDC1 ne "-");
                 push(@row_array, ($sc?"string_2_pdc ".sprintf("%.3f",$inv_SPOT_PDC2/1000):"SPOT_PDC2 ".$inv_SPOT_PDC2)."\n") if ($inv_SPOT_PDC2 ne "-");	
				 push(@row_array, ($sc?"string_3_pdc ".sprintf("%.3f",$inv_SPOT_PDC3/1000):"SPOT_PDC3 ".$inv_SPOT_PDC3)."\n") if ($inv_SPOT_PDC3 ne "-");	
				 push(@row_array, ($sc?"string_sum_pdc ".sprintf("%.3f",$inv_SPOT_PDC_sum/1000):"SPOT_PDC_SUM ".$inv_SPOT_PDC_sum)."\n") if ($inv_SPOT_PDC_sum ne "-");	
             }
			 if($sup_SpotDCPower_3) {
				 push(@row_array, ($sc?"strings_pdc ".sprintf("%.3f",$inv_SPOT_PDC/1000):"SPOT_PDC ".$inv_SPOT_PDC)."\n");
				 push(@row_array, ($sc?"state ".sprintf("%.3f",$inv_SPOT_PDC/1000):"state ".$inv_SPOT_PDC)."\n")  if ($INVCLASS eq "8009");
             }
             if($sup_SpotACPower) {
                 push(@row_array, ($sc?"phase_1_pac ".sprintf("%.3f",$inv_SPOT_PAC1/1000):"SPOT_PAC1 ".$inv_SPOT_PAC1)."\n") if ($inv_SPOT_PAC1 ne "-");
                 push(@row_array, ($sc?"phase_2_pac ".sprintf("%.3f",$inv_SPOT_PAC2/1000):"SPOT_PAC2 ".$inv_SPOT_PAC2)."\n") if ($inv_SPOT_PAC2 ne "-");
                 push(@row_array, ($sc?"phase_3_pac ".sprintf("%.3f",$inv_SPOT_PAC3/1000):"SPOT_PAC3 ".$inv_SPOT_PAC3)."\n") if ($inv_SPOT_PAC3 ne "-");
             }
             if($sup_SpotACTotalPower) {
                 push(@row_array, ($sc?"total_pac ".sprintf("%.3f",$inv_SPOT_PACTOT/1000):"SPOT_PACTOT ".$inv_SPOT_PACTOT)."\n");
                 push(@row_array, ($sc?"state ".sprintf("%.3f",$inv_SPOT_PACTOT/1000):"state ".$inv_SPOT_PACTOT)."\n") if ($INVCLASS ne "8009");
             }
             if($sup_ChargeStatus) {
                 push(@row_array, ($sc?"chargestatus ".$inv_ChargeStatus:"ChargeStatus ".$inv_ChargeStatus)."\n"); #TTT
             }

             if($inv_CLASS && $inv_CLASS eq 8007 && defined($inv_SPOT_PACTOT)) {                         # V2.10.1 28.04.2019
                 if($inv_SPOT_PACTOT < 0) {
                     push(@row_array, ($sc?"power_out "."0":"POWER_OUT "."0")."\n");
                     push(@row_array, ($sc?"power_in ".(-1 * $inv_SPOT_PACTOT):"POWER_IN ".(-1 * $inv_SPOT_PACTOT))."\n");
                 } 
                 else {
                     push(@row_array, ($sc?"power_out ".$inv_SPOT_PACTOT:"POWER_OUT ".$inv_SPOT_PACTOT)."\n");
                     push(@row_array, ($sc?"power_in "."0":"POWER_IN "."0")."\n");
                 }
             }
			 
			 if($sup_SpotBatteryLoad) {
				 push(@row_array, ($sc?"bat_loadtotal ".($inv_BAT_LOADTOTAL/1000):"BAT_LOADTOTAL ".$inv_BAT_LOADTOTAL)."\n") if ($inv_BAT_LOADTOTAL ne "-");
				 push(@row_array, ($sc?"bat_loadtoday ".($inv_BAT_LOADTODAY/1000):"BAT_LOADTODAY ".$inv_BAT_LOADTODAY)."\n") if ($inv_BAT_LOADTODAY ne "-");
			 }
			 if($sup_SpotBatteryUnload) {
				 push(@row_array, ($sc?"bat_unloadtotal ".($inv_BAT_UNLOADTOTAL/1000):"BAT_UNLOADTOTAL ".$inv_BAT_UNLOADTOTAL)."\n") if ($inv_BAT_UNLOADTOTAL ne "-");
				 push(@row_array, ($sc?"bat_unloadtoday ".($inv_BAT_UNLOADTODAY/1000):"BAT_UNLOADTODAY ".$inv_BAT_UNLOADTODAY)."\n") if ($inv_BAT_UNLOADTODAY ne "-");
			 }
			 
			 if($sup_BatteryInfo || $sup_BatteryInfo_2) {
				 if($INVTYPE_NAME =~ /STP(5\.0|6\.0|8\.0|10\.0)SE/xs)
				 {
					push(@row_array, ($sc?"bat_pdc ".(sprintf("%.0f",($inv_BAT_UDC * $inv_BAT_IDC))/1000):"BAT_PDC ".sprintf("%.0f",($inv_BAT_UDC * $inv_BAT_IDC)))."\n")  if ($inv_BAT_UDC ne "-" and $inv_BAT_IDC ne "-");
				 }
			 }
			 
			 if($sup_BatteryInfo_Charge) {
				 push(@row_array, ($sc?"bat_p_charge ".($inv_BAT_P_Charge/1000):"BAT_P_CHARGE ".($inv_BAT_P_Charge))."\n"); #TTT
				 push(@row_array, ($sc?"bat_p_discharge ".($inv_BAT_P_Discharge/1000):"BAT_P_DISCHARGE ".($inv_BAT_P_Discharge))."\n"); #TTT
			 }

             if($detail_level > 0) {
                 # For Detail Level 1
                 if($sup_SpotDCVoltage) {
                     push(@row_array, ($sc?"string_1_udc ":"SPOT_UDC1 ").$inv_SPOT_UDC1."\n") if($inv_SPOT_UDC1 ne "-");
                     push(@row_array, ($sc?"string_2_udc ":"SPOT_UDC2 ").$inv_SPOT_UDC2."\n") if($inv_SPOT_UDC2 ne "-");
					 push(@row_array, ($sc?"string_3_udc ":"SPOT_UDC3 ").$inv_SPOT_UDC3."\n") if($inv_SPOT_UDC3 ne "-");	
                     push(@row_array, ($sc?"string_1_idc ":"SPOT_IDC1 ").$inv_SPOT_IDC1."\n") if($inv_SPOT_IDC1 ne "-");
                     push(@row_array, ($sc?"string_2_idc ":"SPOT_IDC2 ").$inv_SPOT_IDC2."\n") if($inv_SPOT_IDC2 ne "-");
					 push(@row_array, ($sc?"string_3_idc ":"SPOT_IDC3 ").$inv_SPOT_IDC3."\n") if($inv_SPOT_IDC3 ne "-");	
                 }
                 if($sup_SpotACVoltage) {
                     push(@row_array, ($sc?"phase_1_uac ":"SPOT_UAC1 ").$inv_SPOT_UAC1."\n") if ($inv_SPOT_UAC1 ne "-");
                     push(@row_array, ($sc?"phase_2_uac ":"SPOT_UAC2 ").$inv_SPOT_UAC2."\n") if ($inv_SPOT_UAC2 ne "-");
                     push(@row_array, ($sc?"phase_3_uac ":"SPOT_UAC3 ").$inv_SPOT_UAC3."\n") if ($inv_SPOT_UAC3 ne "-");
                     push(@row_array, ($sc?"phase_1_2_uac ":"SPOT_UAC1_2 ").sprintf("%.3f",$inv_SPOT_UAC1_2)."\n") if ($inv_SPOT_UAC1_2 ne "-");
                     push(@row_array, ($sc?"phase_2_3_uac ":"SPOT_UAC2_3 ").sprintf("%.3f",$inv_SPOT_UAC2_3)."\n") if ($inv_SPOT_UAC2_3 ne "-");
                     push(@row_array, ($sc?"phase_3_1_uac ":"SPOT_UAC3_1 ").sprintf("%.3f",$inv_SPOT_UAC3_1)."\n") if ($inv_SPOT_UAC3_1 ne "-");
					 push(@row_array, ($sc?"cosphi ":"SPOT_CosPhi ").sprintf("%.3f",$inv_SPOT_CosPhi)."\n") if ($inv_SPOT_CosPhi ne "-");
                 }
				 if($sup_SpotACCurrent) {
                     push(@row_array, ($sc?"phase_1_iac ":"SPOT_IAC1 ").sprintf("%.2f",$inv_SPOT_IAC1)."\n") if ($inv_SPOT_IAC1 ne "-");
                     push(@row_array, ($sc?"phase_2_iac ":"SPOT_IAC2 ").sprintf("%.2f",$inv_SPOT_IAC2)."\n") if ($inv_SPOT_IAC2 ne "-");
                     push(@row_array, ($sc?"phase_3_iac ":"SPOT_IAC3 ").sprintf("%.2f",$inv_SPOT_IAC3)."\n") if ($inv_SPOT_IAC3 ne "-");
                 }
				 if($sup_SpotACCurrent_Backup) {
                     push(@row_array, ($sc?"phase_backup_1_iac ":"SPOT_Backup_IAC1 ").sprintf("%.2f",$inv_SPOT_IAC1_Backup)."\n") if ($inv_SPOT_IAC1_Backup ne "-");
                     push(@row_array, ($sc?"phase_backup_2_iac ":"SPOT_Backup_IAC2 ").sprintf("%.2f",$inv_SPOT_IAC2_Backup)."\n") if ($inv_SPOT_IAC2_Backup ne "-");
                     push(@row_array, ($sc?"phase_backup_3_iac ":"SPOT_Backup_IAC3 ").sprintf("%.2f",$inv_SPOT_IAC3_Backup)."\n") if ($inv_SPOT_IAC3_Backup ne "-");
					 
					 push(@row_array, ($sc?"phase_backup_1_pac ".sprintf("%.3f",$inv_SPOT_IAC1_Backup * $inv_SPOT_UAC1 /1000):"SPOT_Backup_PAC1 ".sprintf("%.0f",$inv_SPOT_IAC1_Backup * $inv_SPOT_UAC1))."\n") if ($inv_SPOT_IAC1_Backup ne "-");
					 push(@row_array, ($sc?"phase_backup_2_pac ".sprintf("%.3f",$inv_SPOT_IAC2_Backup * $inv_SPOT_UAC2 /1000):"SPOT_Backup_PAC2 ".sprintf("%.0f",$inv_SPOT_IAC2_Backup * $inv_SPOT_UAC2))."\n") if ($inv_SPOT_IAC2_Backup ne "-");
					 push(@row_array, ($sc?"phase_backup_3_pac ".sprintf("%.3f",$inv_SPOT_IAC3_Backup * $inv_SPOT_UAC3 /1000):"SPOT_Backup_PAC3 ".sprintf("%.0f",$inv_SPOT_IAC3_Backup * $inv_SPOT_UAC3))."\n") if ($inv_SPOT_IAC3_Backup ne "-");
                 }
                 if($sup_BatteryInfo || $sup_BatteryInfo_2) {
                     push(@row_array, ($sc?"bat_udc ":"BAT_UDC ").$inv_BAT_UDC."\n");
                     push(@row_array, ($sc?"bat_idc ":"BAT_IDC ").$inv_BAT_IDC."\n");
                 }
				 if($sup_BatteryInfo_UDC) {
                     push(@row_array, ($sc?"bat_udc ":"BAT_UDC ").$inv_BAT_UDC."\n");
					 push(@row_array, ($sc?"bat_udc_a ":"BAT_UDC_A ").$inv_BAT_UDC_A."\n") if ($inv_BAT_UDC_A ne "-");
					 push(@row_array, ($sc?"bat_udc_b ":"BAT_UDC_B ").$inv_BAT_UDC_B."\n") if ($inv_BAT_UDC_B ne "-");
					 push(@row_array, ($sc?"bat_udc_c ":"BAT_UDC_C ").$inv_BAT_UDC_C."\n") if ($inv_BAT_UDC_C ne "-");                                                        
                 }
				 if($sup_BatteryInfo_IDC) {
                     push(@row_array, ($sc?"bat_idc ":"BAT_IDC ").$inv_BAT_IDC."\n");                                                       
					 push(@row_array, ($sc?"bat_idc_a ":"BAT_IDC_A ").$inv_BAT_IDC_A."\n") if ($inv_BAT_IDC_A ne "-");
					 push(@row_array, ($sc?"bat_idc_b ":"BAT_IDC_B ").$inv_BAT_IDC_B."\n") if ($inv_BAT_IDC_B ne "-");
					 push(@row_array, ($sc?"bat_idc_c ":"BAT_IDC_C ").$inv_BAT_IDC_C."\n") if ($inv_BAT_IDC_C ne "-"); 
                 }
				 if($sup_BatteryInfo_Capacity) {
                     push(@row_array, ($sc?"bat_capacity ":"BAT_CAPACITY ").$inv_BAT_CAPACITY."\n"); #TTT
				 }
             }

             if($detail_level > 1) {
                 # For Detail Level 2
                 if($sup_BatteryInfo || $sup_BatteryInfo_2) {
                     push(@row_array, ($sc?"bat_temp ":"BAT_TEMP ").$inv_BAT_TEMP."\n") if ($inv_BAT_TEMP ne "-");
                 }
				 if($sup_BatteryInfo) {
                     push(@row_array, ($sc?"bat_cycles ":"BAT_CYCLES ").$inv_BAT_CYCLES."\n");
                 }
				 if($sup_BatteryInfo_4) {
                     push(@row_array, ($sc?"bat_rated_capacity ".($inv_BAT_rated_capacity / 1000):"BAT_RATED_CAPACITY ".$inv_BAT_rated_capacity)."\n");
                 }
				 
				 if($sup_lower_discharge_limit) {
                     push(@row_array, ($sc?"bat_lower_discharge_limit ":"BAT_Lower_discharge_limit ").$inv_BAT_lower_discharge_limit."\n");
                 }
				 
				 if($sup_BatteryInfo_TEMP) {
                     push(@row_array, ($sc?"bat_temp ":"BAT_TEMP ").$inv_BAT_TEMP."\n") if ($inv_BAT_TEMP ne "-");
					 push(@row_array, ($sc?"bat_temp_a ":"BAT_TEMP_A ").$inv_BAT_TEMP_A."\n") if ($inv_BAT_TEMP_A ne "-");
					 push(@row_array, ($sc?"bat_temp_b ":"BAT_TEMP_B ").$inv_BAT_TEMP_B."\n") if ($inv_BAT_TEMP_B ne "-");
					 push(@row_array, ($sc?"bat_temp_c ":"BAT_TEMP_C ").$inv_BAT_TEMP_C."\n") if ($inv_BAT_TEMP_C ne "-");
                 }
				 if($sup_BatStatus) {
                     push(@row_array, ($sc?"bat_status ":"BAT_STATUS ").SMAInverter_StatusText($inv_BAT_STATUS)."\n");
                 }
                 if($sup_SpotGridFrequency) {
                     push(@row_array, ($sc?"grid_freq ":"SPOT_FREQ ").sprintf("%.2f",$inv_SPOT_FREQ)."\n");
                 }
                 if($sup_TypeLabel) {
                     push(@row_array, ($sc?"susyid ":"SUSyID ").$inv_susyid." - SN: ".$inv_serial."\n") if($inv_susyid && $inv_serial);
                     push(@row_array, ($sc?"device_name ":"INV_NAME ")."SN: ".$inv_serial."\n") if($inv_serial);
                     push(@row_array, ($sc?"serial_number ":"Serialnumber ").$inv_serial."\n") if($inv_serial);
                 }
				 if($sup_Firmware) {
                     push(@row_array, ($sc?"device_firmware ":"INV_FIRMWARE ").$inv_Firmware."\n");
                 }
                 if($sup_MaxACPower) {
                     push(@row_array, ($sc?"pac_max_phase_1 ".($inv_PACMAX1/1000):"INV_PACMAX1 ".$inv_PACMAX1)."\n");
                     push(@row_array, ($sc?"pac_max_phase_2 ".($inv_PACMAX2/1000):"INV_PACMAX2 ".$inv_PACMAX2)."\n");
                     push(@row_array, ($sc?"pac_max_phase_3 ".($inv_PACMAX3/1000):"INV_PACMAX3 ".$inv_PACMAX3)."\n");
                 }
                 if($sup_MaxACPower2) {
                     push(@row_array, ($sc?"pac_max_phase_1_2 ":"INV_PACMAX1_2 ").$inv_PACMAX1_2."\n");
                 }
                 if($sup_InverterTemperature) {
                     push(@row_array, ($sc?"device_temperature ":"INV_TEMP ").sprintf("%.1f",$inv_TEMP)."\n");
                 }
                 if($sup_OperationTime) {
                     push(@row_array, ($sc?"feed-in_time ":"SPOT_FEEDTM ").$inv_SPOT_FEEDTM."\n");
                     push(@row_array, ($sc?"operation_time ":"SPOT_OPERTM ").$inv_SPOT_OPERTM."\n");
                 }
                 if($sup_GridRelayStatus) {
                     push(@row_array, ($sc?"gridrelay_status ":"INV_GRIDRELAY ").SMAInverter_StatusText($inv_GRIDRELAY)."\n");
                 }
                 if($sup_DeviceStatus) {
                     push(@row_array, ($sc?"device_status ":"INV_STATUS ").SMAInverter_StatusText($inv_STATUS)."\n");
                 }
				 
				 if($sup_BackupRelayStatus) {
                     push(@row_array, ($sc?"backuprelay_status ":"INV_BACKRELAYRELAY ").SMAInverter_StatusText($inv_BACKUPRELAY)."\n");
                 }
				 if($sup_GridConection) {
                     push(@row_array, ($sc?"GridConection ":"INV_GridConection ").SMAInverter_StatusText($inv_GridConection)."\n");
                 }
				 
				 if($sup_OperatingStatus) {
                     push(@row_array, ($sc?"operating_status ":"INV_OperatingStatus ").SMAInverter_StatusText($inv_OperatingStatus)."\n");
                 }
				 if($sup_GeneralOperatingStatus) {
                     push(@row_array, ($sc?"general_operating_status ":"INV_GeneralOperatingStatus ").SMAInverter_StatusText($inv_GeneralOperatingStatus)."\n");
                 }
				 if($sup_WaitingTimeUntilFeedIn) {
                     push(@row_array, ($sc?"waiting_time_until_feed_in ":"INV_WaitingTimeUntilFeedIn ").$inv_WaitingTimeUntilFeedIn."\n");
                 }

				if($sup_Insulation) {
                     push(@row_array, ($sc?"device_dc_insulation ":"INV_DC_Insulation ").$inv_DC_insulation."\n") if ($inv_DC_insulation ne "-");
                }
			    if($sup_Insulation) {
                     push(@row_array, ($sc?"device_dc_residual_current ":"INV_DC_Residual_Current ").$inv_DC_Residual_Current."\n") if ($inv_DC_Residual_Current ne "-");
                }
			 }
     } 
     else {
         # Login failed/not possible
         push(@row_array, "state Login failed"."\n");
         push(@row_array, "modulstate login failed"."\n");
     }
 } 
 else {
     # sleepmode at current time and not suppressed
     push(@row_array, "modulstate sleep"."\n");
     push(@row_array, "opertime_start ".$opertime_start."\n");
     push(@row_array, "opertime_stop ".$opertime_stop."\n");
     push(@row_array, "state done"."\n");
 }

 Log3 ($name, 5, "$name -> row_array before encoding:");
 for my $row (@row_array) {
     chomp $row;
     Log3 ($name, 5, "$name -> $row");
 }

 # encoding result
 my $rowlist = join('|', @row_array);
 $rowlist    = encode_base64($rowlist,"");

 # Background-Laufzeit ermitteln
 $brt = tv_interval($bst);

 $rt = ($irt?$irt:'').",".$brt;

 Log3 ($name, 4, "$name -> BlockingCall SMAInverter_getstatusDoParse finished");

return "$name|$rowlist|$avg|$rt|$INVCLASS|$INVTYPE|$INVFWMAIN";
}

###############################################################
#         Auswertung non-blocking Inverter Datenabruf
###############################################################
sub SMAInverter_getstatusParseDone ($) {
 my ($string)                = @_;
 my @a                       = split("\\|",$string);
 my $name                    = $a[0];
 my $hash                    = $defs{$name};
 my $rowlist                 = decode_base64($a[1]);
 $hash->{HELPER}{AVERAGEBUF} = $a[2] if($a[2]);
 my $rt                      = $a[3];
 my ($irt,$brt)              = split(",", $rt);
 
 $hash->{INVCLASS} 			 = $a[4];
 $hash->{INVTYPE}  			 = $a[5];
 $hash->{INVFWMAIN}  		 = $a[6];

 Log3 ($name, 4, "$name -> Start BlockingCall SMAInverter_getstatusParseDone");

 # proctime Readings löschen
 if(!AttrVal($name, "showproctime", undef)) {
     delete($defs{$name}{READINGS}{inverter_processing_time});
     delete($defs{$name}{READINGS}{background_processing_time});
 } else {
     delete($defs{$name}{READINGS}{inverter_processing_time}) if(!$irt);
 }

 # Get current time
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
 $hash->{LASTUPDATE} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;

 my @row_array = split("\\|", $rowlist);

 Log3 ($name, 5, "$name -> row_array after decoding:");
 foreach my $row (@row_array) {
     chomp $row;
     Log3 ($name, 5, "$name -> $row");
 }

 readingsBeginUpdate($hash);
 foreach my $row (@row_array) {
     chomp $row;
     my @a = split(" ", $row, 2);
     $hash->{MODEL} = $a[1] if($a[0] eq "device_type");
     readingsBulkUpdate($hash, $a[0], $a[1]);
 }
 readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));
 readingsBulkUpdate($hash, "inverter_processing_time", sprintf("%.4f",$irt)) if(AttrVal($name, "showproctime", undef) && $irt);
 readingsEndUpdate($hash, 1);

 delete($hash->{HELPER}{RUNNING_PID});
 Log3 ($name, 4, "$name -> BlockingCall SMAInverter_getstatusParseDone finished");

return;
}

###############################################################
#           Abbruchroutine Timeout Inverter Abfrage
###############################################################
sub SMAInverter_getstatusParseAborted(@) {
  my ($hash,$cause) = @_;
  my $name      = $hash->{NAME};
  my $discycles = $hash->{HELPER}{FAULTEDCYCLES};
  $cause = $cause?$cause:"Timeout: process terminated";

  # count of timeouts since module start
  $discycles++;
  $hash->{HELPER}{FAULTEDCYCLES} = $discycles;

  Log3 ($name, 1, "SMAInverter $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} $cause");
  readingsSingleUpdate($hash,"state",$cause, 1);

  delete($hash->{HELPER}{RUNNING_PID});

return;
}

##########################################################################
#                     SMA Command Execution
##########################################################################
sub SMAInverter_SMAcommand($$$$$) {
 # Parameters: $hash - host - command - first - last
 my ($hash,$host,$command,$first,$last) = @_;
 my $name       = $hash->{NAME};
 my $cmdheader  = "534D4100000402A00000000100";
 my $pktlength  = "26";                                                            # length = 38 for data commands
 my $esignature = "0010606509A0";
 my ($inv_TYPE, $inv_CLASS,
     $inv_SPOT_ETODAY, $inv_SPOT_ETOTAL,
	 $inv_SPOT_EPVTODAY, $inv_SPOT_EPVTOTAL,
     $inv_susyid,
     $inv_serial,
	 $inv_Firmware,
     $inv_SPOT_PDC, $inv_SPOT_PDC1, $inv_SPOT_PDC2, $inv_SPOT_PDC3, $inv_SPOT_PDC_sum,
     $inv_SPOT_PAC1, $inv_SPOT_PAC2, $inv_SPOT_PAC3, $inv_SPOT_PACTOT,
     $inv_PACMAX1, $inv_PACMAX2, $inv_PACMAX3, $inv_PACMAX1_2,
     $inv_ChargeStatus,
     $inv_SPOT_UDC1, $inv_SPOT_UDC2, $inv_SPOT_UDC3,
     $inv_SPOT_IDC1, $inv_SPOT_IDC2, $inv_SPOT_IDC3,
     $inv_SPOT_UAC1, $inv_SPOT_UAC2, $inv_SPOT_UAC3,
	 $inv_SPOT_UAC1_2, $inv_SPOT_UAC2_3, $inv_SPOT_UAC3_1,
     $inv_SPOT_IAC1, $inv_SPOT_IAC2, $inv_SPOT_IAC3,
	 $inv_SPOT_IAC1_Backup, $inv_SPOT_IAC2_Backup, $inv_SPOT_IAC3_Backup,
	 $inv_SPOT_CosPhi,
     $inv_BAT_UDC, $inv_BAT_UDC_A, $inv_BAT_UDC_B, $inv_BAT_UDC_C, 
     $inv_BAT_IDC, $inv_BAT_IDC_A, $inv_BAT_IDC_B, $inv_BAT_IDC_C,
	 $inv_BAT_P_Charge, $inv_BAT_P_Discharge,
     $inv_BAT_CYCLES, $inv_BAT_CYCLES_A, $inv_BAT_CYCLES_B, $inv_BAT_CYCLES_C,
     $inv_BAT_TEMP, $inv_BAT_TEMP_A, $inv_BAT_TEMP_B, $inv_BAT_TEMP_C,
     $inv_BAT_LOADTODAY, $inv_BAT_LOADTOTAL, $inv_BAT_CAPACITY,$inv_BAT_UNLOADTODAY,$inv_BAT_UNLOADTOTAL,
	 $inv_BAT_rated_capacity, $inv_BAT_STATUS,
	 $inv_BAT_lower_discharge_limit,
     $inv_SPOT_FREQ, $inv_SPOT_OPERTM, $inv_SPOT_FEEDTM, $inv_TEMP, $inv_GRIDRELAY, $inv_STATUS,
	 $inv_BACKUPRELAY, $inv_OperatingStatus, $inv_GeneralOperatingStatus, $inv_WaitingTimeUntilFeedIn, $inv_GridConection,
	 $Meter_Grid_FeedIn, $Meter_Grid_Consumation, $Meter_Total_FeedIn, $Meter_Total_Consumation,
	 $Meter_Power_Grid_FeedIn, $Meter_Power_Grid_Consumation,
	 $Meter_Grid_FeedIn_PAC1, $Meter_Grid_FeedIn_PAC2, $Meter_Grid_FeedIn_PAC3, $Meter_Grid_Consumation_PAC1, $Meter_Grid_Consumation_PAC2, $Meter_Grid_Consumation_PAC3,
	 $inv_DC_insulation, $inv_DC_Residual_Current);
 my $mysusyid       = $hash->{HELPER}{MYSUSYID};
 my $myserialnumber = $hash->{HELPER}{MYSERIALNUMBER};
 my ($cmd, $myID, $target_ID, $spkt_ID, $cmd_ID);
 my ($socket,$data,$size,$data_ID);
 my ($i, $temp, $count);                                                                  # Variables for loops and calculation

 my $INVTYPE_NAME = ReadingsVal($name,"INV_TYPE",ReadingsVal($name,"device_type",""));
 
 # Seriennummer und SuSyID des Ziel-WR setzen
 my $default_target_susyid = $hash->{HELPER}{DEFAULT_TARGET_SUSYID};
 my $default_target_serial = $hash->{HELPER}{DEFAULT_TARGET_SERIAL};
 my $target_susyid = AttrVal($name, "target-susyid", $default_target_susyid);
 my $target_serial = AttrVal($name, "target-serial", $default_target_serial);

 # Define own ID and target ID and packet ID
 $myID      = SMAInverter_ByteOrderShort(substr(sprintf("%04X",$mysusyid),0,4)) . SMAInverter_ByteOrderLong(sprintf("%08X",$myserialnumber));
 $target_ID = SMAInverter_ByteOrderShort(substr(sprintf("%04X",$target_susyid),0,4)) . SMAInverter_ByteOrderLong(sprintf("%08X",$target_serial));

 # Increasing Packet ID
 $hash->{HELPER}{PKT_ID} = $hash->{HELPER}{PKT_ID} + 1;
 $spkt_ID = SMAInverter_ByteOrderShort(sprintf("%04X",$hash->{HELPER}{PKT_ID}));

 $cmd_ID = SMAInverter_ByteOrderLong(sprintf("%08X",$command)) . SMAInverter_ByteOrderLong(sprintf("%08X",$first)) . SMAInverter_ByteOrderLong(sprintf("%08X",$last));

 #build final command to send
 $cmd = $cmdheader . $pktlength . $esignature . $target_ID . "0000" . $myID . "0000" . "00000000" . $spkt_ID . $cmd_ID . "00000000";

 # flush after every write
 $| = 1;

 # Create Socket and check if successful
 $socket = new IO::Socket::INET (PeerHost => $host, PeerPort => 9522, Proto => 'udp',); # open Socket

 if (!$socket) {
    # in case of error
    Log3 $name, 1, "$name - ERROR. Can't open socket to inverter: $!";
    return 0;
 };

 # Send Data
 $data = pack("H*",$cmd);
 $socket->send($data);
 Log3 $name, 3, "$name - Send request $cmd_ID to $host on port 9522";
 Log3 $name, 5, "$name - send: $cmd";

 # Receive Data and do a first check regarding length
 # receive data
 $socket->recv($data, $hash->{HELPER}{MAXBYTES});
 $size = length($data);

 # check if something was received
 if (defined $size) {
     my $received = unpack("H*", $data);
     Log3 $name, 5, "$name - Received: $received";
 }

 # Nothing received -> exit
 if (not defined $size) {
     Log3 $name, 1, "$name - Nothing received...";
     return 0;
 } 
 else {
     # We have received something!
     if ($size > 58) {
         # Check all parameters of answer
         my $r_susyid = unpack("v*", substr $data, 20, 2);
         my $r_serial = unpack("V*", substr $data, 22, 4);
         my $r_pkt_ID = unpack("v*", substr $data, 40, 2);
         my $r_error  = unpack("V*", substr $data, 36, 4);
         
         if (($r_susyid ne $mysusyid) || ($r_serial ne $myserialnumber) || ($r_pkt_ID ne $hash->{HELPER}{PKT_ID}) || ($r_error ne 0)) {
             # Response does not match the parameters we have sent, maybe different target
             Log3 $name, 3, "$name - Inverter answer does not match our parameters.";
             Log3 $name, 5, "$name - Request/Response: SusyID $mysusyid/$r_susyid, Serial $myserialnumber/$r_serial, Packet ID $hash->{HELPER}{PKT_ID}/$r_pkt_ID, Error $r_error";
             $socket->close();
             return 0;
         }
     } 
     else {
         Log3 $name, 3, "$name - Format of inverter response does not fit.";
         $socket->close();
         return 0;
     }
 }

 # All seems ok, data received
 $inv_susyid = unpack("v*", substr $data, 28, 2);
 $inv_serial = unpack("V*", substr $data, 30, 4);
 $socket->close();

 if (AttrVal($name, "target-serial", undef)) {
     return 0 unless($target_serial eq $inv_serial);
 }
 
 if (AttrVal($name, "target-susyid", undef)) {
     return 0 unless($target_susyid eq $inv_susyid);
 }

 # Check the data identifier
 $data_ID = unpack("v*", substr $data, 55, 2);
 Log3 ($name, 5, "$name - Data identifier $data_ID");

     #Meter
	 if ($data_ID == 0x4624) { 
		 if (length($data) >= 66) {
			 $Meter_Grid_FeedIn = unpack("V*", substr($data, 62, 4));
			 
			 if(($Meter_Grid_FeedIn eq -2147483648) || ($Meter_Grid_FeedIn eq 0xFFFFFFFF) || $Meter_Grid_FeedIn <= 0) {$Meter_Grid_FeedIn = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - Meter_Grid_FeedIn wasn't deliverd ... set it to \"0\" !");
			 $Meter_Grid_FeedIn = "-";
		 }
		 
		 if (length($data) >= 82) {
			 $Meter_Grid_Consumation = unpack("V*", substr($data, 78, 4));
			 
			 if(($Meter_Grid_Consumation eq -2147483648) || ($Meter_Grid_Consumation eq 0xFFFFFFFF) || $Meter_Grid_Consumation <= 0) {$Meter_Grid_Consumation = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - Meter_Grid_Consumation wasn't deliverd ... set it to \"0\" !");
			 $Meter_Grid_Consumation = "-";
		 }
		 
		 Log3 $name, 5, "$name - Data Meter_Grid_FeedIn=$Meter_Grid_FeedIn and Meter_Grid_Consumation=$Meter_Grid_Consumation";
		 return (1,$Meter_Grid_FeedIn,$Meter_Grid_Consumation,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x4691) {
		 if (length($data) >= 66) {
			 $Meter_Grid_FeedIn = unpack("V*", substr($data, 62, 4));
			 
			 if(($Meter_Grid_FeedIn eq -2147483648) || ($Meter_Grid_FeedIn eq 0xFFFFFFFF) || $Meter_Grid_FeedIn <= 0) {$Meter_Grid_FeedIn = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - Meter_Grid_FeedIn wasn't deliverd ... set it to \"0\" !");
			 $Meter_Grid_FeedIn = "-";
		 }
		 
		 if (length($data) >= 82) {
			 $Meter_Grid_Consumation = unpack("V*", substr($data, 78, 4));
			 
			 if(($Meter_Grid_Consumation eq -2147483648) || ($Meter_Grid_Consumation eq 0xFFFFFFFF) || $Meter_Grid_Consumation <= 0) {$Meter_Grid_Consumation = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - Meter_Grid_Consumation wasn't deliverd ... set it to \"0\" !");
			 $Meter_Grid_Consumation = "-";
		 }
		 
		 Log3 $name, 5, "$name - Data Meter_Grid_FeedIn=$Meter_Grid_FeedIn and Meter_Grid_Consumation=$Meter_Grid_Consumation";
		 return (1,$Meter_Grid_FeedIn,$Meter_Grid_Consumation,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x4636) {
		 if (length($data) >= 66) {
			 $Meter_Power_Grid_FeedIn = unpack("V*", substr($data, 62, 4));
			 
			 if(($Meter_Power_Grid_FeedIn eq -2147483648) || ($Meter_Power_Grid_FeedIn eq 0xFFFFFFFF) || $Meter_Power_Grid_FeedIn < 0) {$Meter_Grid_FeedIn = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - Meter_Power_Grid_FeedIn wasn't deliverd ... set it to \"0\" !");
			 $Meter_Grid_FeedIn = "-";
		 }
		 
		 if (length($data) >= 94) {
			 $Meter_Power_Grid_Consumation = unpack("V*", substr($data, 90, 4));
			 
			 if(($Meter_Power_Grid_Consumation eq -2147483648) || ($Meter_Power_Grid_Consumation eq 0xFFFFFFFF) || $Meter_Power_Grid_Consumation < 0) {$Meter_Power_Grid_Consumation = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - Meter_Power_Grid_Consumation wasn't deliverd ... set it to \"0\" !");
			 $Meter_Grid_Consumation = "-";
		 }
		 
		 Log3 $name, 5, "$name - Data Meter_Power_Grid_FeedIn=$Meter_Power_Grid_FeedIn and Meter_Power_Grid_Consumation=$Meter_Power_Grid_Consumation";
		 return (1,$Meter_Power_Grid_FeedIn,$Meter_Power_Grid_Consumation,$inv_susyid,$inv_serial);
	 }
	 
	  elsif ($data_ID == 0x46e8) {
		 $Meter_Grid_FeedIn_PAC1 = unpack("l*", substr $data, 62, 4);
		 if($Meter_Grid_FeedIn_PAC1 eq -2147483648) {$Meter_Grid_FeedIn_PAC1 = "-"; }   # Catch 0x80000000 as 0 value
		 $Meter_Grid_FeedIn_PAC2 = unpack("l*", substr $data, 90, 4);
		 if($Meter_Grid_FeedIn_PAC2 eq -2147483648) {$Meter_Grid_FeedIn_PAC2 = "-"; }   # Catch 0x80000000 as 0 value
		 $Meter_Grid_FeedIn_PAC3 = unpack("l*", substr $data, 118, 4);
		 if($Meter_Grid_FeedIn_PAC3 eq -2147483648) {$Meter_Grid_FeedIn_PAC3 = "-"; }   # Catch 0x80000000 as 0 value
		 Log3 $name, 5, "$name - Found Data Meter_Grid_FeedIn_PAC1=$Meter_Grid_FeedIn_PAC1 and Meter_Grid_FeedIn_PAC2=$Meter_Grid_FeedIn_PAC2 and Meter_Grid_FeedIn_PAC3=$Meter_Grid_FeedIn_PAC3";
		 
		 $Meter_Grid_Consumation_PAC1 = unpack("l*", substr $data, 146, 4);
		 if($Meter_Grid_Consumation_PAC1 eq -2147483648) {$Meter_Grid_Consumation_PAC1 = "-"; }   # Catch 0x80000000 as 0 value
		 $Meter_Grid_Consumation_PAC2 = unpack("l*", substr $data, 174, 4);
		 if($Meter_Grid_Consumation_PAC2 eq -2147483648) {$Meter_Grid_Consumation_PAC2 = "-"; }   # Catch 0x80000000 as 0 value
		 $Meter_Grid_Consumation_PAC3 = unpack("l*", substr $data, 202, 4);
		 if($Meter_Grid_Consumation_PAC3 eq -2147483648) {$Meter_Grid_Consumation_PAC3 = "-"; }   # Catch 0x80000000 as 0 value
		 Log3 $name, 5, "$name - Found Data Meter_Grid_Consumation_PAC1=$Meter_Grid_Consumation_PAC1 and Meter_Grid_Consumation_PAC2=$Meter_Grid_Consumation_PAC2 and Meter_Grid_Consumation_PAC3=$Meter_Grid_Consumation_PAC3";

		 return (1,$Meter_Grid_FeedIn_PAC1,$Meter_Grid_FeedIn_PAC2,$Meter_Grid_FeedIn_PAC3,$Meter_Grid_Consumation_PAC1,$Meter_Grid_Consumation_PAC2,$Meter_Grid_Consumation_PAC3,$inv_susyid,$inv_serial);
	 }
	#Meter end

	 elsif ($data_ID == 0x8234) {
		 $inv_Firmware = hex(unpack("H*", substr $data, 81, 1));
		 my $INVFWMAIN = $inv_Firmware;
		 $inv_Firmware = $inv_Firmware .".". hex(unpack("H*", substr $data, 80, 1));
		 $inv_Firmware = $inv_Firmware .".". hex(unpack("H*", substr $data, 79, 1));
		 
		 my $inv_Firmware_X = hex(unpack("H*", substr $data, 78, 1));
		 
		 if($inv_Firmware_X == 4)
		 {
			$inv_Firmware = $inv_Firmware ." R";
		 }
		 else
		 {
			$inv_Firmware = $inv_Firmware ." ?".$inv_Firmware_X;
		 }
		 
		 Log3 $name, 5, "$name - Found Data Firmware=$inv_Firmware data=$data";
		 return (1,$inv_Firmware,$INVFWMAIN,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x2601) {
		 if (length($data) >= 66) {
			 $inv_SPOT_ETOTAL = unpack("V*", substr($data, 62, 4));
			 
			 if(($inv_SPOT_ETOTAL eq -2147483648) || ($inv_SPOT_ETOTAL eq 0xFFFFFFFF) || $inv_SPOT_ETOTAL <= 0) {$inv_SPOT_ETOTAL = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - ETOTAL wasn't deliverd ... set it to \"0\" !");
			 $inv_SPOT_ETOTAL = "-";
		 }

		 $inv_SPOT_ETODAY = "-";
		 if (length($data) >= 82) {
			 $inv_SPOT_ETODAY = unpack("V*", substr ($data, 78, 4));
			 
			 if(($inv_SPOT_ETODAY eq -2147483648) || ($inv_SPOT_ETODAY eq 0xFFFFFFFF) || $inv_SPOT_ETODAY <= 0) {$inv_SPOT_ETODAY = "-"; }
		 }
		 
		 if($inv_SPOT_ETODAY eq "-" && $inv_SPOT_ETOTAL ne "-") {
			 # ETODAY wurde vom WR nicht geliefert, es wird versucht ihn zu berechnen
			 Log3 ($name, 3, "$name - ETODAY wasn't delivered from inverter, try to calculate it ...");
			 my $etotold = ReadingsNum($name, ".etotal_yesterday", 0);
			 
			 if($etotold && $inv_SPOT_ETOTAL > $etotold) {
				 $inv_SPOT_ETODAY = $inv_SPOT_ETOTAL - $etotold;
				 Log3 ($name, 3, "$name - ETODAY calculated successfully !");
			 } 
			 else {
				 Log3 ($name, 3, "$name - WARNING - unable to calculate ETODAY ... set it to \"0\" !");
				 $inv_SPOT_ETODAY = "-";
			 }
		 }

		 Log3 $name, 5, "$name - Data SPOT_ETOTAL=$inv_SPOT_ETOTAL and SPOT_ETODAY=$inv_SPOT_ETODAY";
		 return (1,$inv_SPOT_ETODAY,$inv_SPOT_ETOTAL,$inv_susyid,$inv_serial);
	 }
	 #PV Ertrag
	  elsif ($data_ID == 0x46C3) {
		 if (length($data) >= 66) {
			 $inv_SPOT_EPVTOTAL = unpack("V*", substr($data, 62, 4));
			 
			 if(($inv_SPOT_EPVTOTAL eq -2147483648) || ($inv_SPOT_EPVTOTAL eq 0xFFFFFFFF) || $inv_SPOT_EPVTOTAL <= 0) {$inv_SPOT_EPVTOTAL = "-"; }
		 } 
		 else {
			 Log3 ($name, 3, "$name - WARNING - EPVTOTAL wasn't deliverd ... set it to \"0\" !");
			 $inv_SPOT_EPVTOTAL = "-";
		 }

		 $inv_SPOT_EPVTODAY = "-";
		 if (length($data) >= 82) {
			 $inv_SPOT_EPVTODAY = unpack("V*", substr ($data, 78, 4));
			 
			 if(($inv_SPOT_EPVTODAY eq -2147483648) || ($inv_SPOT_EPVTODAY eq 0xFFFFFFFF) || $inv_SPOT_EPVTODAY <= 0) {$inv_SPOT_EPVTODAY = "-"; }
		 }
		 
		 if($inv_SPOT_EPVTODAY eq "-" && $inv_SPOT_EPVTOTAL ne "-") {
			 # EPVTODAY wurde vom WR nicht geliefert, es wird versucht ihn zu berechnen
			 Log3 ($name, 3, "$name - EPVTODAY wasn't delivered from inverter, try to calculate it ...");
			 my $etotold = ReadingsNum($name, ".epvtotal_yesterday", 0);
			 
			 if($etotold && $inv_SPOT_EPVTOTAL > $etotold) {
				 $inv_SPOT_EPVTODAY = $inv_SPOT_EPVTOTAL - $etotold;
				 Log3 ($name, 3, "$name - EPVTODAY calculated successfully !");
			 } 
			 else {
				 Log3 ($name, 3, "$name - WARNING - unable to calculate EPVTODAY ... set it to \"0\" !");
				 $inv_SPOT_EPVTODAY = "-";
			 }
		 }

		 Log3 $name, 5, "$name - Data SPOT_EPVTOTAL=$inv_SPOT_EPVTOTAL and SPOT_EPVTODAY=$inv_SPOT_EPVTODAY";
		 return (1,$inv_SPOT_EPVTODAY,$inv_SPOT_EPVTOTAL,$inv_susyid,$inv_serial);
	  }

	 elsif ($data_ID == 0x4967) {
		 if (length($data) >= 66) {
			 $inv_BAT_LOADTOTAL = unpack("V*", substr($data, 62, 4));
			 
			 if(($inv_BAT_LOADTOTAL eq -2147483648) || ($inv_BAT_LOADTOTAL eq 0xFFFFFFFF) || $inv_BAT_LOADTOTAL <= 0) {$inv_BAT_LOADTOTAL = "-"; }
		 } 
		 else {
			 Log3 $name, 3, "$name - WARNING - BATTERYLOAD_TOTAL wasn't deliverd ... set it to \"0\" !";
			 $inv_BAT_LOADTOTAL = "-";
		 }

		 $inv_BAT_LOADTODAY = "-";
		 if (length($data) >= 82) {
			 $inv_BAT_LOADTODAY = unpack("V*", substr ($data, 78, 4));
			 
			 if(($inv_BAT_LOADTODAY eq -2147483648) || ($inv_BAT_LOADTODAY eq 0xFFFFFFFF) || $inv_BAT_LOADTODAY <= 0) {$inv_BAT_LOADTODAY = "-"; }
		 } 
		 
		 if($inv_BAT_LOADTODAY eq "-" && $inv_BAT_LOADTOTAL ne "-")  {
			 # BATTERYLOAD_TODAY wurde vom WR nicht geliefert, es wird versucht ihn zu berechnen
			 Log3 $name, 3, "$name - BATTERYLOAD_TODAY wasn't delivered from inverter, try to calculate it ...";
			 my $bltotold = ReadingsNum($name, ".bat_loadtotal_yesterday", 0);
			 
			 if($bltotold && $inv_BAT_LOADTOTAL > $bltotold) {
				 $inv_BAT_LOADTODAY = $inv_BAT_LOADTOTAL - $bltotold;
				 Log3 $name, 3, "$name - BATTERYLOAD_TODAY calculated successfully !";
			 } 
			 else {
				 Log3 $name, 3, "$name - WARNING - unable to calculate BATTERYLOAD_TODAY ... set it to \"0\" !";
				 $inv_BAT_LOADTODAY = "-";
			 }
		 }

		 Log3 $name, 5, "$name - Data BAT_LOADTOTAL=$inv_BAT_LOADTOTAL and BAT_LOADTODAY=$inv_BAT_LOADTODAY";
		 return (1,$inv_BAT_LOADTODAY,$inv_BAT_LOADTOTAL,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x4968) {
		 if (length($data) >= 66) {
			 $inv_BAT_UNLOADTOTAL = unpack("V*", substr($data, 62, 4));
			 
			 if(($inv_BAT_UNLOADTOTAL eq -2147483648) || ($inv_BAT_UNLOADTOTAL eq 0xFFFFFFFF) || $inv_BAT_UNLOADTOTAL <= 0) {$inv_BAT_UNLOADTOTAL = "-"; }
		 } 
		 else {
			 Log3 $name, 3, "$name - WARNING - BATTERYUNLOAD_TOTAL wasn't deliverd ... set it to \"0\" !";
			 $inv_BAT_UNLOADTOTAL = "-";
		 }

		 $inv_BAT_UNLOADTODAY = "-";
		 if (length($data) >= 82) {
			 $inv_BAT_UNLOADTODAY = unpack("V*", substr ($data, 78, 4));
			 
			 if(($inv_BAT_UNLOADTODAY eq -2147483648) || ($inv_BAT_UNLOADTODAY eq 0xFFFFFFFF) || $inv_BAT_UNLOADTODAY <= 0) {$inv_BAT_UNLOADTODAY = "-"; }
		 } 
		 
		 if($inv_BAT_UNLOADTODAY eq "-" && $inv_BAT_UNLOADTOTAL ne "-")  {
			 # BATTERYUNLOAD_TODAY wurde vom WR nicht geliefert, es wird versucht ihn zu berechnen
			 Log3 $name, 3, "$name - BATTERYUNLOAD_TODAY wasn't delivered from inverter, try to calculate it ...";
			 my $bultotold = ReadingsNum($name, ".bat_unloadtotal_yesterday", 0);
			 
			 if($bultotold && $inv_BAT_UNLOADTOTAL > $bultotold) {
				 $inv_BAT_UNLOADTODAY = $inv_BAT_UNLOADTOTAL - $bultotold;
				 Log3 $name, 3, "$name - BATTERYUNLOAD_TODAY calculated successfully !";
			 } 
			 else {
				 Log3 $name, 3, "$name - WARNING - unable to calculate BATTERYUNLOAD_TODAY ... set it to \"0\" !";
				 $inv_BAT_UNLOADTODAY = "-";
			 }
		 }

		 Log3 $name, 3, "$name - Data BAT_UNLOADTOTAL=$inv_BAT_UNLOADTOTAL and BAT_UNLOADTODAY=$inv_BAT_UNLOADTODAY";
		 return (1,$inv_BAT_UNLOADTODAY,$inv_BAT_UNLOADTOTAL,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x251E) {
		 $inv_SPOT_PDC_sum = 0;
		 $inv_SPOT_PDC1 = unpack("l*", substr $data, 62, 4);
		 #$inv_SPOT_PDC1 = (abs($inv_SPOT_PDC1) eq 2147483648) ? 0 : $inv_SPOT_PDC1;
		 if(($inv_SPOT_PDC1 eq -2147483648) || ($inv_SPOT_PDC1 eq 0xFFFFFFFF)) {$inv_SPOT_PDC1 = "-"; }
		 else {$inv_SPOT_PDC_sum = $inv_SPOT_PDC1;}
		 
		 if($size < 90) {$inv_SPOT_PDC2 = "-"; }  else {
			$inv_SPOT_PDC2 = unpack("l*", substr $data, 90, 4);
			#$inv_SPOT_PDC2 = (abs($inv_SPOT_PDC2) eq 2147483648) ? 0 : $inv_SPOT_PDC2;
			if(($inv_SPOT_PDC2 eq -2147483648) || ($inv_SPOT_PDC2 eq 0xFFFFFFFF)) {$inv_SPOT_PDC2 = "-"; }
			else {$inv_SPOT_PDC_sum = $inv_SPOT_PDC_sum + $inv_SPOT_PDC2;}
		 } # catch short response, in case PDC2 not supported
		 if($size < 118) {$inv_SPOT_PDC3 = "-"; } else {
			$inv_SPOT_PDC3 = unpack("l*", substr $data, 118, 4); 
			#$inv_SPOT_PDC3 = (abs($inv_SPOT_PDC3) eq 2147483648) ? 0 : $inv_SPOT_PDC3;
			if(($inv_SPOT_PDC3 eq -2147483648) || ($inv_SPOT_PDC3 eq 0xFFFFFFFF)) {$inv_SPOT_PDC3 = "-"; }
			else {$inv_SPOT_PDC_sum = $inv_SPOT_PDC_sum + $inv_SPOT_PDC3;}
		 } # catch short response, in case PDC3 not supported
		 		 
		 Log3 $name, 5, "$name - Found Data SPOT_PDC1=$inv_SPOT_PDC1, SPOT_PDC2=$inv_SPOT_PDC2 and SPOT_PDC3=$inv_SPOT_PDC3, SPOT_PDC_SUM=$inv_SPOT_PDC_sum";
		 return (1,$inv_SPOT_PDC1,$inv_SPOT_PDC2,$inv_SPOT_PDC3,$inv_SPOT_PDC_sum,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x46C2) {
		 #$inv_SPOT_PDC = unpack("V*", substr $data, 62, 4);
		 #$inv_SPOT_PDC = ($inv_SPOT_PDC == 2147483648) ? 0 : $inv_SPOT_PDC;
		 $inv_SPOT_PDC = unpack("l*", substr $data, 62, 4);
		 if(($inv_SPOT_PDC eq -2147483648) || ($inv_SPOT_PDC eq 0xFFFFFFFF)) {$inv_SPOT_PDC = "-"; }
		 Log3 $name, 5, "$name - Found Data SPOT_PDC=$inv_SPOT_PDC";
		 return (1,$inv_SPOT_PDC,$inv_susyid,$inv_serial);
	 } 
	  
	 elsif ($data_ID == 0x4640) {
		 $inv_SPOT_PAC1 = unpack("l*", substr $data, 62, 4);
		 if($inv_SPOT_PAC1 eq -2147483648) {$inv_SPOT_PAC1 = "-"; }   # Catch 0x80000000 as 0 value
		 $inv_SPOT_PAC2 = unpack("l*", substr $data, 90, 4);
		 if($inv_SPOT_PAC2 eq -2147483648) {$inv_SPOT_PAC2 = "-"; }   # Catch 0x80000000 as 0 value
		 $inv_SPOT_PAC3 = unpack("l*", substr $data, 118, 4);
		 if($inv_SPOT_PAC3 eq -2147483648) {$inv_SPOT_PAC3 = "-"; }   # Catch 0x80000000 as 0 value
		 Log3 $name, 5, "$name - Found Data SPOT_PAC1=$inv_SPOT_PAC1 and SPOT_PAC2=$inv_SPOT_PAC2 and SPOT_PAC3=$inv_SPOT_PAC3";
		 return (1,$inv_SPOT_PAC1,$inv_SPOT_PAC2,$inv_SPOT_PAC3,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x411E) {
		 $inv_PACMAX1 = unpack("V*", substr $data, 62, 4);
		 $inv_PACMAX2 = unpack("V*", substr $data, 90, 4);
		 $inv_PACMAX3 = unpack("V*", substr $data, 118, 4);
		 Log3 $name, 5, "$name - Found Data INV_PACMAX1=$inv_PACMAX1 and INV_PACMAX2=$inv_PACMAX2 and INV_PACMAX3=$inv_PACMAX3";
		 return (1,$inv_PACMAX1,$inv_PACMAX2,$inv_PACMAX3,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x832A) {
		 $inv_PACMAX1_2 = unpack("V*", substr $data, 62, 4);
		 Log3 $name, 5, "$name - Found Data INV_PACMAX1_2=$inv_PACMAX1_2";
		 return (1,$inv_PACMAX1_2,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x263F) {
		 $inv_SPOT_PACTOT = unpack("l*", substr $data, 62, 4);
		 if($inv_SPOT_PACTOT eq -2147483648) {$inv_SPOT_PACTOT = 0; }   # Catch 0x80000000 as 0 value
		 
		 Log3 $name, 5, "$name - Found Data SPOT_PACTOT=$inv_SPOT_PACTOT";
		 return (1,$inv_SPOT_PACTOT,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x295A) {
		 $inv_ChargeStatus = unpack("V*", substr $data, 62, 4);
		 Log3 $name, 5, "$name - Found Data Battery Charge Status=$inv_ChargeStatus";
		 return (1,$inv_ChargeStatus,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x696E) {
		 $inv_BAT_CAPACITY = unpack("V*", substr $data, 62, 4);
		 Log3 $name, 5, "$name - Found Data Battery Capacity =$inv_BAT_CAPACITY"; #TTT
		 return (1,$inv_BAT_CAPACITY,$inv_susyid,$inv_serial);
	 }
	 elsif ($data_ID == 0x451F) {
		 $inv_SPOT_UDC1 = unpack("l*", substr $data, 62, 4);
		 # catch shorter responses in case not second string supported
		 if($size < 146) {
			$inv_SPOT_UDC2 = "-";
			$inv_SPOT_UDC3 = "-";
			$inv_SPOT_IDC1 = unpack("l*", substr $data, 90, 4);
			$inv_SPOT_IDC2 = "-";
			$inv_SPOT_IDC3 = "-";
		 } elsif($size < 194) {
			$inv_SPOT_UDC2 = unpack("l*", substr $data, 90, 4);
			$inv_SPOT_UDC3 = "-";
			$inv_SPOT_IDC1 = unpack("l*", substr $data, 118, 4);
			$inv_SPOT_IDC2 = unpack("l*", substr $data, 146, 4);
			$inv_SPOT_IDC3 = "-";
		 } else {
			$inv_SPOT_UDC2 = unpack("l*", substr $data, 90, 4);
			$inv_SPOT_UDC3 = unpack("l*", substr $data, 118, 4);
			$inv_SPOT_IDC1 = unpack("l*", substr $data, 146, 4);
			$inv_SPOT_IDC2 = unpack("l*", substr $data, 174, 4);
			$inv_SPOT_IDC3 = unpack("l*", substr $data, 202, 4);
		 }
		 if(($inv_SPOT_UDC1 eq -2147483648) || ($inv_SPOT_UDC1 eq 0xFFFFFFFF)) {$inv_SPOT_UDC1 = 0; } elsif($inv_SPOT_UDC1 ne "-") {$inv_SPOT_UDC1 = $inv_SPOT_UDC1 / 100; }    # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_UDC2 eq -2147483648) || ($inv_SPOT_UDC2 eq 0xFFFFFFFF)) {$inv_SPOT_UDC2 = 0; } elsif($inv_SPOT_UDC2 ne "-") {$inv_SPOT_UDC2 = $inv_SPOT_UDC2 / 100; }    # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_UDC3 eq -2147483648) || ($inv_SPOT_UDC3 eq 0xFFFFFFFF)) {$inv_SPOT_UDC3 = 0; } elsif($inv_SPOT_UDC3 ne "-") {$inv_SPOT_UDC3 = $inv_SPOT_UDC3 / 100; }    # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IDC1 eq -2147483648) || ($inv_SPOT_IDC1 eq 0xFFFFFFFF)) {$inv_SPOT_IDC1 = 0; } elsif($inv_SPOT_IDC1 ne "-") {$inv_SPOT_IDC1 = $inv_SPOT_IDC1 / 1000; }   # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IDC2 eq -2147483648) || ($inv_SPOT_IDC2 eq 0xFFFFFFFF)) {$inv_SPOT_IDC2 = 0; } elsif($inv_SPOT_IDC2 ne "-") {$inv_SPOT_IDC2 = $inv_SPOT_IDC2 / 1000; }   # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IDC3 eq -2147483648) || ($inv_SPOT_IDC3 eq 0xFFFFFFFF)) {$inv_SPOT_IDC3 = 0; } elsif($inv_SPOT_IDC3 ne "-") {$inv_SPOT_IDC3 = $inv_SPOT_IDC3 / 1000; }   # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 
		 Log3 $name, 5, "$name - Found Data SPOT_UDC1=$inv_SPOT_UDC1, SPOT_UDC2=$inv_SPOT_UDC2, SPOT_UDC3=$inv_SPOT_UDC3, SPOT_IDC1=$inv_SPOT_IDC1, SPOT_IDC2=$inv_SPOT_IDC2 and SPOT_IDC3=$inv_SPOT_IDC3";
		 return (1,$inv_SPOT_UDC1,$inv_SPOT_UDC2,$inv_SPOT_UDC3,$inv_SPOT_IDC1,$inv_SPOT_IDC2,$inv_SPOT_IDC3,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x4648) {
		 $inv_SPOT_UAC1 = unpack("l*", substr $data, 62, 4);
		 $inv_SPOT_UAC2 = unpack("l*", substr $data, 90, 4);
		 $inv_SPOT_UAC3 = unpack("l*", substr $data, 118, 4);
		 if($size >= 230) {
			$inv_SPOT_UAC1_2 = unpack("l*", substr $data, 146, 4);
			$inv_SPOT_UAC2_3 = unpack("l*", substr $data, 174, 4);
			$inv_SPOT_UAC3_1 = unpack("l*", substr $data, 202, 4);
		 }
		 else
		 {
			$inv_SPOT_UAC1_2 = "-";
			$inv_SPOT_UAC2_3 = "-";
			$inv_SPOT_UAC3_1 = "-";
		 }
		 
		 if($size >= 230) {
			 $inv_SPOT_CosPhi = unpack("l*", substr $data, 230, 4);
			 if(($inv_SPOT_CosPhi eq -2147483648) || ($inv_SPOT_CosPhi eq 0xFFFFFFFF)) {$inv_SPOT_CosPhi = "-"; } else {$inv_SPOT_CosPhi = $inv_SPOT_CosPhi / 100; }
		 }
		 else
		 {
			$inv_SPOT_CosPhi = "-";
		 }
		 
		 if(($inv_SPOT_UAC1 eq -2147483648) || ($inv_SPOT_UAC1 eq 0xFFFFFFFF) || $inv_SPOT_UAC1 < 0) {$inv_SPOT_UAC1 = "-"; } else {$inv_SPOT_UAC1 = $inv_SPOT_UAC1 / 100; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_UAC2 eq -2147483648) || ($inv_SPOT_UAC2 eq 0xFFFFFFFF) || $inv_SPOT_UAC2 < 0) {$inv_SPOT_UAC2 = "-"; } else {$inv_SPOT_UAC2 = $inv_SPOT_UAC2 / 100; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_UAC3 eq -2147483648) || ($inv_SPOT_UAC3 eq 0xFFFFFFFF) || $inv_SPOT_UAC3 < 0) {$inv_SPOT_UAC3 = "-"; } else {$inv_SPOT_UAC3 = $inv_SPOT_UAC3 / 100; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if($size >= 230) {
			if(($inv_SPOT_UAC1_2 eq -2147483648) || ($inv_SPOT_UAC1_2 eq 0xFFFFFFFF) || $inv_SPOT_UAC1_2 < 0) {$inv_SPOT_UAC1_2 = "-"; } else {$inv_SPOT_UAC1_2 = $inv_SPOT_UAC1_2 / 100; }   # Catch 0x80000000 and 0xFFFFFFFF as 0 value
			if(($inv_SPOT_UAC2_3 eq -2147483648) || ($inv_SPOT_UAC2_3 eq 0xFFFFFFFF) || $inv_SPOT_UAC2_3 < 0) {$inv_SPOT_UAC2_3 = "-"; } else {$inv_SPOT_UAC2_3 = $inv_SPOT_UAC2_3 / 100; }   # Catch 0x80000000 and 0xFFFFFFFF as 0 value
			if(($inv_SPOT_UAC3_1 eq -2147483648) || ($inv_SPOT_UAC3_1 eq 0xFFFFFFFF) || $inv_SPOT_UAC3_1 < 0) {$inv_SPOT_UAC3_1 = "-"; } else {$inv_SPOT_UAC3_1 = $inv_SPOT_UAC3_1 / 100; }   # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 }
		 Log3 $name, 5, "$name - Found Data SPOT_UAC1=$inv_SPOT_UAC1 and SPOT_UAC2=$inv_SPOT_UAC2 and SPOT_UAC3=$inv_SPOT_UAC3 and inv_SPOT_UAC1_2=$inv_SPOT_UAC1_2 and inv_SPOT_UAC2_3=$inv_SPOT_UAC2_3 and inv_SPOT_UAC3_1=$inv_SPOT_UAC3_1 and inv_SPOT_CosPhi=$inv_SPOT_CosPhi";
		 return (1,$inv_SPOT_UAC1,$inv_SPOT_UAC2,$inv_SPOT_UAC3,$inv_SPOT_UAC1_2,$inv_SPOT_UAC2_3,$inv_SPOT_UAC3_1,$inv_SPOT_CosPhi,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x4653) {
		 $inv_SPOT_IAC1 = unpack("l*", substr $data, 62, 4);
		 $inv_SPOT_IAC2 = unpack("l*", substr $data, 90, 4);
		 $inv_SPOT_IAC3 = unpack("l*", substr $data, 118, 4);
		 
		 if(($inv_SPOT_IAC1 eq -2147483648) || ($inv_SPOT_IAC1 eq 0xFFFFFFFF) || $inv_SPOT_IAC1 < 0) {$inv_SPOT_IAC1 = "-"; } else {$inv_SPOT_IAC1 = $inv_SPOT_IAC1 / 1000; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IAC2 eq -2147483648) || ($inv_SPOT_IAC2 eq 0xFFFFFFFF) || $inv_SPOT_IAC2 < 0) {$inv_SPOT_IAC2 = "-"; } else {$inv_SPOT_IAC2 = $inv_SPOT_IAC2 / 1000; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IAC3 eq -2147483648) || ($inv_SPOT_IAC3 eq 0xFFFFFFFF) || $inv_SPOT_IAC3 < 0) {$inv_SPOT_IAC3 = "-"; } else {$inv_SPOT_IAC3 = $inv_SPOT_IAC3 / 1000; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value

		 Log3 $name, 5, "$name - Found Data inv_SPOT_IAC1=$inv_SPOT_IAC1 and inv_SPOT_IAC2=$inv_SPOT_IAC2 and inv_SPOT_IAC3=$inv_SPOT_IAC3";
		 return (1,$inv_SPOT_IAC1,$inv_SPOT_IAC2,$inv_SPOT_IAC3,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x5746) {
		 $inv_SPOT_IAC1_Backup = unpack("l*", substr $data, 62, 4);
		 $inv_SPOT_IAC2_Backup = unpack("l*", substr $data, 90, 4);
		 $inv_SPOT_IAC3_Backup = unpack("l*", substr $data, 118, 4);
		 
		 if(($inv_SPOT_IAC1_Backup eq -2147483648) || ($inv_SPOT_IAC1_Backup eq 0xFFFFFFFF) || $inv_SPOT_IAC1_Backup < 0) {$inv_SPOT_IAC1_Backup = "-"; } else {$inv_SPOT_IAC1_Backup = $inv_SPOT_IAC1_Backup / 1000; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IAC2_Backup eq -2147483648) || ($inv_SPOT_IAC2_Backup eq 0xFFFFFFFF) || $inv_SPOT_IAC2_Backup < 0) {$inv_SPOT_IAC2_Backup = "-"; } else {$inv_SPOT_IAC2_Backup = $inv_SPOT_IAC2_Backup / 1000; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 if(($inv_SPOT_IAC3_Backup eq -2147483648) || ($inv_SPOT_IAC3_Backup eq 0xFFFFFFFF) || $inv_SPOT_IAC3_Backup < 0) {$inv_SPOT_IAC3_Backup = "-"; } else {$inv_SPOT_IAC3_Backup = $inv_SPOT_IAC3_Backup / 1000; }  # Catch 0x80000000 and 0xFFFFFFFF as 0 value

		 Log3 $name, 5, "$name - Found Data inv_SPOT_IAC1_Backup=$inv_SPOT_IAC1_Backup and inv_SPOT_IAC2_Backup=$inv_SPOT_IAC2_Backup and inv_SPOT_IAC3_Backup=$inv_SPOT_IAC3_Backup";
		 return (1,$inv_SPOT_IAC1_Backup,$inv_SPOT_IAC2_Backup,$inv_SPOT_IAC3_Backup,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x8937) {
		 $inv_BAT_rated_capacity   = unpack("V*", substr $data, 78, 4);
		 
		 Log3 $name, 5, "$name - Found Data and inv_BAT_rated_capacity=$inv_BAT_rated_capacity";
		 return (1,$inv_BAT_rated_capacity,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x895b) {
		 $inv_BAT_lower_discharge_limit   = unpack("V*", substr $data, 78, 4);
		 
		 Log3 $name, 5, "$name - Found Data and inv_BAT_lower_discharge_limit=$inv_BAT_lower_discharge_limit";
		 return (1,$inv_BAT_lower_discharge_limit,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x4969) {
		 $inv_BAT_P_Charge   	= unpack("V*", substr $data, 62, 4);
		 $inv_BAT_P_Discharge   = unpack("V*", substr $data, 90, 4);
		 
		 if(($inv_BAT_P_Charge eq -2147483648) 		|| ($inv_BAT_P_Charge eq 0xFFFFFFFF)	|| $inv_BAT_P_Charge < 0) 		{$inv_BAT_P_Charge = "-"; }
		 if(($inv_BAT_P_Discharge eq -2147483648) 	|| ($inv_BAT_P_Discharge eq 0xFFFFFFFF)	|| $inv_BAT_P_Discharge < 0) 	{$inv_BAT_P_Discharge = "-"; }
		 
		 Log3 $name, 5, "$name - Found Data inv_BAT_P_Charge=$inv_BAT_P_Charge and inv_BAT_P_Discharge=$inv_BAT_P_Discharge";
		 return (1,$inv_BAT_P_Charge,$inv_BAT_P_Discharge,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x495B) {
		 if ($INVTYPE_NAME =~ /STP(5\.0|6\.0|8\.0|10\.0)SE/xs) {

			 $inv_BAT_TEMP   = unpack("V*", substr $data, 62, 4) / 10;
			 $inv_BAT_UDC    = unpack("V*", substr $data, 90, 4) / 100;
			 $inv_BAT_IDC    = unpack("l*", substr $data, 118, 4);
			 
			 if($inv_BAT_IDC eq -2147483648) {                                                           # Catch 0x80000000 as 0 value
				 $inv_BAT_IDC = "-"; 
			 } 
			 else { 
				 $inv_BAT_IDC = $inv_BAT_IDC / 1000;
			 }
			 
			 Log3 $name, 5, "$name - Found Data and BAT_TEMP=$inv_BAT_TEMP and BAT_UDC=$inv_BAT_UDC and BAT_IDC=$inv_BAT_IDC (STPxxSE)";
			 return (1,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial);
		 }
		 elsif ($INVTYPE_NAME =~ /SBS(1\.5|2\.0|2\.5)/xs) {

			 $inv_BAT_TEMP   = unpack("V*", substr $data, 62, 4) / 10;
			 $inv_BAT_UDC    = unpack("V*", substr $data, 90, 4) / 100;
			 $inv_BAT_IDC    = unpack("l*", substr $data, 118, 4);
			 
			 if($inv_BAT_IDC eq -2147483648) {                                                           # Catch 0x80000000 as 0 value
				 $inv_BAT_IDC = "-"; 
			 } 
			 else { 
				 $inv_BAT_IDC = $inv_BAT_IDC / 1000;
			 }
			 
			 Log3 $name, 5, "$name - Found Data and BAT_TEMP=$inv_BAT_TEMP and BAT_UDC=$inv_BAT_UDC and BAT_IDC=$inv_BAT_IDC (SBS1.5-2.5)";
			 return (1,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial);
		 }
		 else{
			 $count = 0;
			 $inv_BAT_TEMP = 0;
			 $inv_BAT_TEMP_A = unpack("V*", substr $data, 62, 4);
			 $inv_BAT_TEMP_B = unpack("V*", substr $data, 90, 4);
			 $inv_BAT_TEMP_C = unpack("V*", substr $data, 118, 4);
			 if($inv_BAT_TEMP_A eq 2147483648 || $inv_BAT_TEMP_A eq -2147483648 || $inv_BAT_TEMP_A eq 0x80000000 || $inv_BAT_TEMP_A < 0) {$inv_BAT_TEMP_A = "-"; } else {$inv_BAT_TEMP_A = $inv_BAT_TEMP_A / 10; $count = $count + 1; $inv_BAT_TEMP = $inv_BAT_TEMP + $inv_BAT_TEMP_A;}
			 if($inv_BAT_TEMP_B eq 2147483648 || $inv_BAT_TEMP_B eq -2147483648 || $inv_BAT_TEMP_B eq 0x80000000 || $inv_BAT_TEMP_B < 0) {$inv_BAT_TEMP_B = "-"; } else {$inv_BAT_TEMP_B = $inv_BAT_TEMP_B / 10; $count = $count + 1; $inv_BAT_TEMP = $inv_BAT_TEMP + $inv_BAT_TEMP_B;}
			 if($inv_BAT_TEMP_C eq 2147483648 || $inv_BAT_TEMP_C eq -2147483648 || $inv_BAT_TEMP_C eq 0x80000000 || $inv_BAT_TEMP_C < 0) {$inv_BAT_TEMP_C = "-"; } else {$inv_BAT_TEMP_C = $inv_BAT_TEMP_C / 10; $count = $count + 1; $inv_BAT_TEMP = $inv_BAT_TEMP + $inv_BAT_TEMP_C;}
			 
			 if($count > 0) {$inv_BAT_TEMP = $inv_BAT_TEMP / $count;} else {$inv_BAT_TEMP = "-";}
			 
			 Log3 $name, 5, "$name - Found Data and BAT_TEMP=$inv_BAT_TEMP and BAT_TEMP_A=$inv_BAT_TEMP_A and BAT_TEMP_B=$inv_BAT_TEMP_B and BAT_TEMP_C=$inv_BAT_TEMP_C";
			 return (1,$inv_BAT_TEMP,$inv_BAT_TEMP_A,$inv_BAT_TEMP_B,$inv_BAT_TEMP_C,$inv_susyid,$inv_serial);
		 }
	 }
	 
	 elsif ($data_ID == 0x495C) {
		 $count = 0;
		 $inv_BAT_UDC = 0;
		 $inv_BAT_UDC_A = unpack("V*", substr $data, 62, 4);
		 $inv_BAT_UDC_B = unpack("V*", substr $data, 90, 4);
		 $inv_BAT_UDC_C = unpack("V*", substr $data, 118, 4);
		 if(($inv_BAT_UDC_A eq -2147483648) || ($inv_BAT_UDC_A eq 0xFFFFFFFF) || $inv_BAT_UDC_A < 0) {$inv_BAT_UDC_A = "-"; } else {$inv_BAT_UDC_A = $inv_BAT_UDC_A / 100; $count = $count + 1; $inv_BAT_UDC = $inv_BAT_UDC + $inv_BAT_UDC_A;}
		 if(($inv_BAT_UDC_B eq -2147483648) || ($inv_BAT_UDC_B eq 0xFFFFFFFF) || $inv_BAT_UDC_B < 0) {$inv_BAT_UDC_B = "-"; } else {$inv_BAT_UDC_B = $inv_BAT_UDC_B / 100; $count = $count + 1; $inv_BAT_UDC = $inv_BAT_UDC + $inv_BAT_UDC_B;}
		 if(($inv_BAT_UDC_C eq -2147483648) || ($inv_BAT_UDC_C eq 0xFFFFFFFF) || $inv_BAT_UDC_C < 0) {$inv_BAT_UDC_C = "-"; } else {$inv_BAT_UDC_C = $inv_BAT_UDC_C / 100; $count = $count + 1; $inv_BAT_UDC = $inv_BAT_UDC + $inv_BAT_UDC_C;}
		 
		 $inv_BAT_UDC = $inv_BAT_UDC / $count;
		 
		 Log3 $name, 5, "$name - Found Data and BAT_UDC=$inv_BAT_UDC and BAT_UDC_A=$inv_BAT_UDC_A and BAT_UDC_B=$inv_BAT_UDC_B and BAT_UDC_C=$inv_BAT_UDC_C";
		 return (1,$inv_BAT_UDC,$inv_BAT_UDC_A,$inv_BAT_UDC_B,$inv_BAT_UDC_C,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x495D) {
		 $count = 0;
		 $inv_BAT_IDC = 0;
		 $inv_BAT_IDC_A = unpack("l*", substr $data, 62, 4);
		 $inv_BAT_IDC_B = unpack("l*", substr $data, 90, 4);
		 $inv_BAT_IDC_C = unpack("l*", substr $data, 118, 4);
		 if(($inv_BAT_IDC_A eq -2147483648) || ($inv_BAT_IDC_A eq 0x80000000)) {$inv_BAT_IDC_A = "-"; } else {$inv_BAT_IDC_A = $inv_BAT_IDC_A / 1000; $count = $count + 1; $inv_BAT_IDC = $inv_BAT_IDC + $inv_BAT_IDC_A;}
		 if(($inv_BAT_IDC_B eq -2147483648) || ($inv_BAT_IDC_B eq 0x80000000)) {$inv_BAT_IDC_B = "-"; } else {$inv_BAT_IDC_B = $inv_BAT_IDC_B / 1000; $count = $count + 1; $inv_BAT_IDC = $inv_BAT_IDC + $inv_BAT_IDC_B;}
		 if(($inv_BAT_IDC_C eq -2147483648) || ($inv_BAT_IDC_C eq 0x80000000)) {$inv_BAT_IDC_C = "-"; } else {$inv_BAT_IDC_C = $inv_BAT_IDC_C / 1000; $count = $count + 1; $inv_BAT_IDC = $inv_BAT_IDC + $inv_BAT_IDC_C;}
		 
		 #$inv_BAT_IDC = $inv_BAT_IDC / $count;
		 
		 Log3 $name, 5, "$name - Found Data and BAT_IDC=$inv_BAT_IDC and BAT_IDC_A=$inv_BAT_IDC_A and BAT_IDC_B=$inv_BAT_IDC_B and BAT_IDC_C=$inv_BAT_IDC_C";
		 return (1,$inv_BAT_IDC,$inv_BAT_IDC_A,$inv_BAT_IDC_B,$inv_BAT_IDC_C,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x491E) {
		 $inv_BAT_CYCLES = unpack("V*", substr $data, 62, 4);
		 $inv_BAT_TEMP   = unpack("V*", substr $data, 90, 4) / 10;
		 $inv_BAT_UDC    = unpack("V*", substr $data, 118, 4) / 100;
		 $inv_BAT_IDC    = unpack("l*", substr $data, 146, 4);
		 
		 if($inv_BAT_IDC eq -2147483648) {                                                           # Catch 0x80000000 as 0 value
			 $inv_BAT_IDC = 0; 
		 } 
		 else { 
			 $inv_BAT_IDC = $inv_BAT_IDC / 1000;
		 }
		 
		 Log3 $name, 5, "$name - Found Data BAT_CYCLES=$inv_BAT_CYCLES and BAT_TEMP=$inv_BAT_TEMP and BAT_UDC=$inv_BAT_UDC and BAT_IDC=$inv_BAT_IDC";
		 return (1,$inv_BAT_CYCLES,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x495F) {
	 
		 $inv_BAT_CYCLES = unpack("V*", substr $data, 62, 4);
		 $inv_BAT_TEMP = unpack("V*", substr $data, 90, 4) / 10;
		 $inv_BAT_UDC = unpack("V*", substr $data, 118, 4) / 100;
		 $inv_BAT_IDC = unpack("l*", substr $data, 146, 4);
		 
		 if($inv_BAT_IDC eq -2147483648) {                                                          # Catch 0x80000000 as 0 value
			 $inv_BAT_IDC = "-"; 
		 } 
		 else { 
			 $inv_BAT_IDC = $inv_BAT_IDC / 1000;
		 } 	
		 
		 Log3 $name, 5, "$name - Found Data BAT_CYCLES=$inv_BAT_CYCLES and BAT_TEMP=$inv_BAT_TEMP and BAT_UDC=$inv_BAT_UDC and BAT_IDC=$inv_BAT_IDC";
		 return (1,$inv_BAT_CYCLES,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x2377) {
		 $inv_TEMP = unpack("l*", substr $data, 62, 4);
		 
		 if($inv_TEMP eq -2147483648) {                                                             # Catch 0x80000000 as 0 value
			 $inv_TEMP = 0; 
		 } 
		 else { 
			 $inv_TEMP = $inv_TEMP / 100;
		 }
		 
		 Log3 $name, 5, "$name - Found Data Inverter Temp=$inv_TEMP";
		 return (1,$inv_TEMP,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x462E) {
		 $inv_SPOT_OPERTM = int(unpack("V*", substr $data, 62, 4) / 36) / 100;
		 if($size > 78) {
			$inv_SPOT_FEEDTM = int(unpack("V*", substr $data, 78, 4) / 36) / 100;
			
			Log3 $name, 5, "$name - Found Data SPOT_OPERTM=$inv_SPOT_OPERTM and SPOT_FEEDTM=$inv_SPOT_FEEDTM";
			return (1,$inv_SPOT_OPERTM,$inv_SPOT_FEEDTM,$inv_susyid,$inv_serial);
		 }
		 else
		 {
			Log3 $name, 5, "$name - Found Data SPOT_OPERTM=$inv_SPOT_OPERTM and SPOT_FEEDTM=--";
			return (1,$inv_SPOT_OPERTM,0,$inv_susyid,$inv_serial);
		 }
	 }

	 elsif ($data_ID == 0x4657) {
		 $inv_SPOT_FREQ = unpack("V*", substr $data, 62, 4);
		 if(($inv_SPOT_FREQ eq -2147483648) || ($inv_SPOT_FREQ eq 0xFFFFFFFF)) {$inv_SPOT_FREQ = 0; } else {$inv_SPOT_FREQ = $inv_SPOT_FREQ / 100; }    # Catch 0x80000000 and 0xFFFFFFFF as 0 value
		 Log3 $name, 5, "$name - Found Data SPOT_FREQ=$inv_SPOT_FREQ";
		 return (1,$inv_SPOT_FREQ,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x821E) {
		 $inv_CLASS = unpack("V*", substr $data, 102, 4) & 0x00FFFFFF;
		 $i = 142;                                                                                  # start address of INV_TYPE
		 $inv_TYPE = 0;                                                                             # initialize to unknown inverter type
		 do {
			$temp = unpack("V*", substr $data, $i, 4);
			if(($temp & 0xFF000000) eq 0x01000000) { $inv_TYPE = $temp & 0x00FFFFFF; }              # in some models a catalogue is transmitted, right model marked with: 0x01000000 OR INV_Type
			$i = $i+4;
		 } while ((unpack("V*", substr $data, $i, 4) ne 0x00FFFFFE) && ($i<$size));                 # 0x00FFFFFE is the end marker for attributes

		 Log3 $name, 5, "$name - Found Data CLASS=$inv_CLASS and TYPE=$inv_TYPE";
		 return (1,$inv_TYPE,$inv_CLASS,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x4164) {
		 $i = 0;
		 $temp = 0;
		 $inv_GRIDRELAY = 0x00FFFFFD;                                                               # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_GRIDRELAY = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));            # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data INV_GRIDRELAY=$inv_GRIDRELAY";
			 return (1,$inv_GRIDRELAY,$inv_susyid,$inv_serial);
	 }

	 elsif ($data_ID == 0x2148) {
		 $i = 0;
		 $temp = 0;
		 $inv_STATUS = 0x00FFFFFD;      # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_STATUS = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));    # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data inv_STATUS=$inv_STATUS";
			 return (1,$inv_STATUS,$inv_susyid,$inv_serial);
	 }
	 
	 elsif ($data_ID == 0x414D) {
		 $i = 0;
		 $temp = 0;
		 $inv_BAT_STATUS = 0x00FFFFFD;      # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_BAT_STATUS = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));    # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data inv_BAT_STATUS=$inv_BAT_STATUS";
			 return (1,$inv_BAT_STATUS,$inv_susyid,$inv_serial);
	 } 

	 elsif ($data_ID == 0x4125) {
		 $i = 0;
		 $temp = 0;
		 $inv_BACKUPRELAY = 0x00FFFFFD;                                                               # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_BACKUPRELAY = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));            # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data inv_BACKUPRELAY=$inv_BACKUPRELAY";
			 return (1,$inv_BACKUPRELAY,$inv_susyid,$inv_serial);
	 }	

	 elsif ($data_ID == 0x46A6) {
		 $i = 0;
		 $temp = 0;
		 $inv_GridConection = 0x00FFFFFD;                                                               # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_GridConection = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));            # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data inv_GridConection=$inv_GridConection";
			 return (1,$inv_GridConection,$inv_susyid,$inv_serial);
	 }	
		 
	 elsif ($data_ID == 0x412b) {
		 $i = 0;
		 $temp = 0;
		 $inv_OperatingStatus = 0x00FFFFFD;                                                               # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_OperatingStatus = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));            # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data inv_OperatingStatus=$inv_OperatingStatus";
			 return (1,$inv_OperatingStatus,$inv_susyid,$inv_serial);
	 }	 
	 
	 elsif ($data_ID == 0x4128) {
		 $i = 0;
		 $temp = 0;
		 $inv_GeneralOperatingStatus = 0x00FFFFFD;                                                               # Code for No Information;
		 do {
			 $temp = unpack("V*", substr $data, 62 + $i*4, 4);
			 if(($temp & 0xFF000000) ne 0) { $inv_GeneralOperatingStatus = $temp & 0x00FFFFFF; }
			 $i = $i + 1;
		 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));            # 0x00FFFFFE is the end marker for attributes
			 Log3 $name, 5, "$name - Found Data inv_GeneralOperatingStatus=$inv_GeneralOperatingStatus";
			 return (1,$inv_GeneralOperatingStatus,$inv_susyid,$inv_serial);
	 }	

	 elsif ($data_ID == 0x254e) {
		 $inv_DC_Residual_Current = unpack("V*", substr $data, 62, 4);
		 $inv_DC_insulation = unpack("V*", substr $data, 90, 4);
		 
		 if(($inv_DC_Residual_Current eq 2147483648) || ($inv_DC_Residual_Current eq 0xFFFFFFFF) || $inv_DC_Residual_Current < 0) {$inv_DC_Residual_Current = "-"; } else {$inv_DC_Residual_Current = $inv_DC_Residual_Current / 1000;}
		 if(($inv_DC_insulation eq 2147483648) || ($inv_DC_insulation eq 0xFFFFFFFF) || $inv_DC_insulation < 0) {$inv_DC_insulation = "-"; }
		 
		 
		 Log3 $name, 5, "$name - Found Data inv_DC_Residual_Current=$inv_DC_Residual_Current and inv_DC_insulation=$inv_DC_insulation";
		 return (1,$inv_DC_Residual_Current,$inv_DC_insulation,$inv_susyid,$inv_serial);
	 } 
	 
	 elsif ($data_ID == 0x4166) {
		 $inv_WaitingTimeUntilFeedIn = unpack("l*", substr $data, 62, 4);
		 Log3 $name, 5, "$name - Found Data inv_WaitingTimeUntilFeedIn=$inv_WaitingTimeUntilFeedIn";
		 return (1,$inv_WaitingTimeUntilFeedIn,$inv_susyid,$inv_serial);
	 }

	 else {
		Log3 $name, 5, "$name - no case";
     }	 

return 0;
}

##########################################################################
#                                Login
##########################################################################
sub SMAInverter_SMAlogon($$$) {
 # Parameters: host - passcode
 my ($host,$pass,$hash)  = @_;
 my $cmdheader           = "534D4100000402A00000000100";
 my $pktlength           = "3A";                             # length = 58 for logon command (old 3A = 58)
 my $esignature          = "001060650EA0";
 my $name                = $hash->{NAME};
 my $mysusyid            = $hash->{HELPER}{MYSUSYID};
 my $myserialnumber      = $hash->{HELPER}{MYSERIALNUMBER};
 my $pkt_ID              = $hash->{HELPER}{PKT_ID};
 my ($cmd, $timestmp, $myID, $target_ID, $spkt_ID, $cmd_ID);
 my ($socket,$data,$size);

 # Seriennummer und SuSyID des Ziel-WR setzen
 my $default_target_susyid 	= $hash->{HELPER}{DEFAULT_TARGET_SUSYID};
 my $default_target_serial 	= $hash->{HELPER}{DEFAULT_TARGET_SERIAL};
 my $target_susyid 			= AttrVal($name, "target-susyid", $default_target_susyid);
 my $target_serial 			= AttrVal($name, "target-serial", $default_target_serial);
 my $installer 				= AttrVal($name, "installerLogin", "0");
 
 #Encode the password
 $pass = SMAInverter_SMAdecrypt( $pass );
 my $encpasswd 	= "888888888888888888888888"; # template for password user
 $encpasswd 	= "BBBBBBBBBBBBBBBBBBBBBBBB" if($installer == 1); # template for password installer
 for my $index (0..(length $pass) - 1 )        # encode password
 {
    if ( (hex(substr($encpasswd,($index*2),2)) + ord(substr($pass,$index,1))) < 256 ) {
        substr($encpasswd,($index*2),2) = substr(sprintf ("%lX", (hex(substr($encpasswd,($index*2),2)) + ord(substr($pass,$index,1)))),0,2);
    } else {
        substr($encpasswd,($index*2),2) = substr(sprintf ("%lX", (hex(substr($encpasswd,($index*2),2)) + ord(substr($pass,$index,1)))),1,2);
    }
 }

 # Get current timestamp in epoch format (unix format)
 $timestmp = SMAInverter_ByteOrderLong(sprintf("%08X",int(time())));

 # Define own ID and target ID and packet ID
 $myID      = SMAInverter_ByteOrderShort(substr(sprintf("%04X",$mysusyid),0,4)) . SMAInverter_ByteOrderLong(sprintf("%08X",$myserialnumber));
 $target_ID = SMAInverter_ByteOrderShort(substr(sprintf("%04X",$target_susyid),0,4)) . SMAInverter_ByteOrderLong(sprintf("%08X",$target_serial));
 $pkt_ID    = 0x8001;   # Reset to 0x8001
 $spkt_ID   = SMAInverter_ByteOrderShort(sprintf("%04X",$pkt_ID));
 my $user 	= "07000000";
 $user 		= "0A000000" if($installer == 1);
 #Logon command
 $cmd_ID = "0C04FDFF" . $user . "84030000";  # Logon command + User group "User" + (maybe) Timeout
 
 #$encpasswd = "0b111cebf0edebedecdcbbbb";
 
 #build final command to send
 $cmd = $cmdheader . $pktlength . $esignature . $target_ID . "0001" . $myID . "0001" . "00000000" . $spkt_ID . $cmd_ID . $timestmp . "00000000" . $encpasswd . "00000000";

 # flush after every write
 $| = 1;

 # Create Socket and check if successful
 $socket = new IO::Socket::INET (PeerHost => $host, PeerPort => 9522, Proto => 'udp',); # open Socket

 if (!$socket) {
     # in case of error
     Log3 $name, 1, "$name - ERROR - Can't open socket to inverter: $!";
     return 0;
 };

 # Send Data
 $data = pack("H*",$cmd);
 $socket->send($data);
 my $loginas = "user";
 $loginas = "installer" if($installer == 1);
 Log3 $name, 4, "$name - Send login to $host on Port 9522 with password $pass as $loginas";
 Log3 $name, 5, "$name - Send: $cmd ";

 # Receive Data and do a first check regarding length
 eval {
     $socket->recv($data, $hash->{HELPER}{MAXBYTES});
     $size = length($data);
 };

 # check if something was received
 if (defined $size) {
     my $received = unpack("H*", $data);
     Log3 $name, 5, "$name - Received: $received";
 }

 # Nothing received -> exit
 if (not defined $size) {
     Log3 $name, 1, "$name - Nothing received...";
     # send: cmd_logout
     $socket->close();
     SMAInverter_SMAlogout($hash,$host);
     return 0;
 } else {
    # We have received something!
    if ($size > 62) {
        # Check all parameters of answer
        my $r_susyid = unpack("v*", substr $data, 20, 2);
        my $r_serial = unpack("V*", substr $data, 22, 4);
        my $r_pkt_ID = unpack("v*", substr $data, 40, 2);
        my $r_cmd_ID = unpack("V*", substr $data, 42, 4);
        my $r_error  = unpack("V*", substr $data, 36, 4);

        if (($r_pkt_ID ne $pkt_ID) || ($r_cmd_ID ne 0xFFFD040D) || ($r_error ne 0)) {
            # Response does not match the parameters we have sent, maybe different target
            Log3 $name, 1, "$name - Inverter answer does not match our parameters.";
            Log3 $name, 5, "$name - Request/Response: SusyID $mysusyid/$r_susyid, Serial $myserialnumber/$r_serial, Packet ID $hash->{HELPER}{PKT_ID}/$r_pkt_ID, Command 0xFFFD040D/$r_cmd_ID, Error $r_error";
            # send: cmd_logout
            $socket->close();
            SMAInverter_SMAlogout($hash,$host);
            return 0;
        }
    } else {
        Log3 $name, 1, "$name - Format of inverter response does not fit.";
        # send: cmd_logout
        $socket->close();
        SMAInverter_SMAlogout($hash,$host);
        return 0;
    }
 }

 # All seems ok, logged in!
 my $inv_susyid = unpack("v*", substr $data, 28, 2);
 my $inv_serial = unpack("V*", substr $data, 30, 4);
 $socket->close();

 if (AttrVal($name, "target-serial", undef)) {
     return 0 unless($inv_serial eq $target_serial);
 } else {
     BlockingInformParent("SMAInverter_setAttrFromBlocking", [$name, "target-serial", $inv_serial], 0);   # Serial automatisch setzen, Forum: https://forum.fhem.de/index.php/topic,56080.msg967448.html#msg967448
 }

 if (AttrVal($name, "target-susyid", undef)) {
     return 0 unless($inv_susyid eq $target_susyid);
 } else {
     BlockingInformParent("SMAInverter_setAttrFromBlocking", [$name, "target-susyid", $inv_susyid], 0);   # SuSyId automatisch setzen, Forum: https://forum.fhem.de/index.php/topic,56080.msg967448.html#msg967448
 }

 Log3 $name, 4, "$name - logged in to inverter serial: $inv_serial, susyid: $inv_susyid";

return 1;
}

################################################################
#            Attributwert aus BlockingCall setzen
################################################################
sub SMAInverter_setAttrFromBlocking($$$) {
  my ($name,$attr,$val) = @_;
  my $hash             = $defs{$name};

  CommandAttr(undef,"$name $attr $val");

return;
}

################################################################
#            Readingwert aus BlockingCall setzen
################################################################
sub SMAInverter_setReadingFromBlocking($$$) {
  my ($name,$reading,$val) = @_;
  my $hash                 = $defs{$name};

  readingsSingleUpdate($hash, $reading, $val, 0);

return;
}

##########################################################################
#                               Logout
##########################################################################
sub SMAInverter_SMAlogout($$) {
 # Parameters: host
 my ($hash,$host)   = @_;
 my $name           = $hash->{NAME};
 my $cmdheader      = "534D4100000402A00000000100";
 my $pktlength      = "22";     # length = 34 for logout command
 my $esignature     = "0010606508A0";
 my $mysusyid       = $hash->{HELPER}{MYSUSYID};
 my $myserialnumber = $hash->{HELPER}{MYSERIALNUMBER};
 my $pkt_ID         = $hash->{HELPER}{PKT_ID};
 my ($cmd, $myID, $target_ID, $spkt_ID, $cmd_ID);
 my ($socket,$data,$size);

 # Seriennummer und SuSyID des Ziel-WR setzen
 my $default_target_susyid = $hash->{HELPER}{DEFAULT_TARGET_SUSYID};
 my $default_target_serial = $hash->{HELPER}{DEFAULT_TARGET_SERIAL};
 my $target_susyid = AttrVal($name, "target-susyid", $default_target_susyid);
 my $target_serial = AttrVal($name, "target-serial", $default_target_serial);

 # Define own ID and target ID and packet ID
 $myID      = SMAInverter_ByteOrderShort(substr(sprintf("%04X",$mysusyid),0,4)) . SMAInverter_ByteOrderLong(sprintf("%08X",$myserialnumber));
 $target_ID = SMAInverter_ByteOrderShort(substr(sprintf("%04X",$target_susyid),0,4)) . SMAInverter_ByteOrderLong(sprintf("%08X",$target_serial));
 # Increasing Packet ID
 $hash->{HELPER}{PKT_ID} = $hash->{HELPER}{PKT_ID} + 1;
 $spkt_ID = SMAInverter_ByteOrderShort(sprintf("%04X",$hash->{HELPER}{PKT_ID}));

 # Logout command
 $cmd_ID = "0E01FDFF" . "FFFFFFFF";  # Logout command

 # build final command to send
 $cmd = $cmdheader . $pktlength . $esignature . $target_ID . "0003" . $myID . "0003" . "00000000" . $spkt_ID . $cmd_ID . "00000000";

 # flush after every write
 $| = 1;

 # Create Socket and check if successful
 $socket = new IO::Socket::INET (PeerHost => $host, PeerPort => 9522, Proto => 'udp',); # open Socket

 if (!$socket) {
     # in case of error
     Log3 $name, 1, "$name - ERROR - Can't open socket to inverter: $!";
     return 0;
 };

 # Send Data
 $data = pack("H*",$cmd);
 $socket->send($data);
 Log3 $name, 4, "$name - Send logout to $host on Port 9522";
 Log3 $name, 5, "$name - Send: $cmd ";

 $target_serial = ($target_serial eq $default_target_serial)?"any inverter":$target_serial;
 $target_susyid = ($target_susyid eq $default_target_susyid)?"any susyid":$target_susyid;
 Log3 $name, 4, "$name - logged out now from inverter serial: $target_serial, susyid: $target_susyid";

 $socket->close();

return 1;
}

##########################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
##########################################################################
sub SMAInverter_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %SMAInverter_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;

  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
      if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/xsg;
      } else {
          $modules{$type}{META}{x_version} = $v;
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );
      }
  } else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }

return;
}

##########################################################################
#                             Sortierung
##########################################################################
sub SMAInverter_ByteOrderShort($) {
 my $input = $_[0];
 my $output = "";
 $output = substr($input, 2, 2) . substr($input, 0, 2);

return $output;
}

##########################################################################
#                             Sortierung
##########################################################################
sub SMAInverter_ByteOrderLong($) {
 my $input = $_[0];
 my $output = "";
 $output = substr($input, 6, 2) . substr($input, 4, 2) . substr($input, 2, 2) . substr($input, 0, 2);

return $output;
}

##########################################################################
#                        Texte for State
# Parameter is the code, return value is the Text or if not known then
# the code as string
##########################################################################
sub SMAInverter_StatusText($) {
 my $code = $_[0];

 if($code eq 51)       { return (AttrVal("global", "language", "EN") eq "DE") ? "geschlossen" : "Closed"; }
 if($code eq 311)      { return (AttrVal("global", "language", "EN") eq "DE") ? "offen" : "Open"; }
 if($code eq 16777213) { return (AttrVal("global", "language", "EN") eq "DE") ? "Information liegt nicht vor" : "No Information"; }
 
 if($code eq 235) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Netzparallelbetrieb" : "parallel grid operation"; }
 if($code eq 1463) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Ersatzstrombetrieb" : "backup"; }
 if($code eq 2119) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Abregelung" : "derating"; }
 if($code eq 569) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Eingeschaltet" : "activated"; }
 if($code eq 1295) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Standby" : "standby"; }
 if($code eq 295) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "MPP" : "MPP"; }
 if($code eq 1795) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Verriegelt" : "locked"; }
 if($code eq 1779) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Getrennt" : "disconnected"; }
 
 if($code eq 1780) 	   { return (AttrVal("global", "language", "EN") eq "DE") ? "Öffentliches Stromnetz" : "public grid"; }
 
 if($code eq 35)       { return (AttrVal("global", "language", "EN") eq "DE") ? "Fehler" : "Fault"; }
 if($code eq 303)      { return "Off"; }
 if($code eq 307)      { return "Ok"; }
 if($code eq 455)      { return (AttrVal("global", "language", "EN") eq "DE") ? "Warnung" : "Warning"; }

return sprintf("%d", $code);
}

##########################################################################
#                 identify inverter type
##########################################################################
sub SMAInverter_devtype ($) {
  my ($code) = @_;

  unless (exists($SMAInverter_devtypes{$code})) { return $code;}
  my $dev = $SMAInverter_devtypes{$code};

return ($dev);
}

##########################################################################
#                          identify device class
##########################################################################
sub SMAInverter_classtype ($) {
  my ($code) = @_;
  my $class;

  if(AttrVal("global", "language", "EN") eq "DE") {
      unless (exists($SMAInverter_classesDE{$code})) { return $code;}
      $class = $SMAInverter_classesDE{$code};
  } else {
      unless (exists($SMAInverter_classesEN{$code})) { return $code;}
      $class = $SMAInverter_classesEN{$code};
  }

return ($class);
}

1;

=pod
=item summary    Integration of SMA Inverters over it's Speedwire (=Ethernet) Interface
=item summary_DE Integration von SMA Wechselrichtern über Speedwire (=Ethernet) Interface

=begin html

<a name="SMAInverter"></a>
<h3>SMAInverter</h3>

Module for the integration of a SMA Inverter over it's Speedwire (=Ethernet) Interface.<br>
Tested on Sunny Tripower 6000TL-20 and Sunny Island 4.4 with Speedwire/Webconnect Piggyback.
<br><br>

Questions and discussions about this module you can find in the FHEM-Forum link:<br>
<a href="https://forum.fhem.de/index.php/topic,56080.msg476525.html#msg476525">76_SMAInverter.pm - Abfrage von SMA Wechselrichter</a>.
<br><br>

<b>Requirements</b>
<br><br>
This module requires:
<ul>
    <li>Perl Module: IO::Socket::INET  (apt-get install libio-socket-multicast-perl) </li>
    <li>Perl Module: Date::Time        (apt-get install libdatetime-perl) </li>
    <li>Perl Module: Time::HiRes</li>
    <li>FHEM Module: 99_SUNRISE_EL.pm</li>
    <li>FHEM Module: Blocking.pm</li>
</ul>
<br>
<br>


<b>Definition</b>
<ul>
<code>define &lt;name&gt; SMAInverter &lt;pin&gt; &lt;hostname/ip&gt; </code><br>
<br>
<li>pin: password of the inverter. Default is 0000. <br>
         <b>inverter without webinterface:</b> The password for the inverter can be changed by "Sunny Explorer" Client Software <br>
         <b>inverter with webinterface:</b> The password changed by the webinterface is also valid for the device definition. </li>
<li>hostname/ip: Hostname or IP-Adress of the inverter (or it's speedwire piggyback module).</li>
<li>The Speedwire port is 9522 by default. A Firewall has to allow connection on this port if present !</li>
</ul>


<b>Operation method</b>
<ul>
The module sends commands to the inverter and checks if they are supported by the inverter.<br>
In case of a positive answer the data is collected and displayed in the readings according to the detail-level. <br><br>

The normal operation time of the inverter is supposed from sunrise to sunset. In that time period the inverter will be polled.
The time of sunrise and sunset will be calculated by functions of FHEM module 99_SUNRISE_EL.pm which is loaded automatically by default.
Therefore the global attribute "longitude" and "latitude" should be set to determine the position of the solar system
(see <a href="#SUNRISE_EL">Commandref SUNRISE_EL</a>). <br><br>

By the attribute "suppressSleep" the sleep mode between sunset and sunrise can be suppressed. Using attribute "offset" you may prefer the sunrise and
defer the sunset virtually. So the working period of the inverter will be extended. <br><br>

In operating mode "automatic" the inverter will be requested periodically corresponding the preset attribute "interval". The operating mode can be
switched to "manual" to realize the retrieval manually (e.g. to synchronize the requst with a SMA energy meter by notify). <br><br>

During inverter operating time the average energy production of the last 5, 10 and 15 minutes will be calculated and displayed in the readings
"avg_power_lastminutes_05", "avg_power_lastminutes_10" and "avg_power_lastminutes_15". <b>Note:</b> To permit a precise calculation, you should
also set the real request interval into the attribute "interval" although you would use the "manual" operation mode ! <br><br>

The retrieval of the inverter will be executed non-blocking. You can adjust the timeout value for this background process by attribute "timeout". <br>
</ul>

<b>Get</b>
<br>
<ul>

  <li><b> get &lt;name&gt; data </b>
  <br><br>

  The request of the inverter will be executed. Those possibility is especifically created for the "manual" operation
  mode (see attribute "mode").
  <br>
  </li>

<br>
</ul>

<b>Attributes</b>
<ul>

  <a name="detail-level"></a>
  <li><b>detail-level [0|1|2] </b><br>
    Defines the complexity of the generated readings. <br><br>

        <ul>
        <table>
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> 0  </td><td>- only Power and Energy </td></tr>
          <tr><td> 1  </td><td>- as 0, additional voltage and current </td></tr>
		  <tr><td> 2  </td><td>- as 1, additional voltage and current </td></tr>
        </table>
        </ul>

  </li>
  <br>
  
  <a name="readEnergyMeter-data"></a>
  <li><b>readEnergyMeter-data [1|0]</b><br>
    Deactivates/activates the reading of the energy meter/smart meter data via the inverter.<br>
    The Readings Meter_xxx are then created and filled with data.
  </li>
  <br>
  
  <a name="disable"></a>
  <li><b>disable [1|0]</b><br>
    Deactivate/activate the module.
  </li>
  <br>

  <a name="interval"></a>
  <li><b>interval </b><br>
    Request cycle in seconds. (default: 60)
  </li>
  <br>

  <a name="mode"></a>
  <li><b>mode [automatic|manual] </b><br>
    The request mode of the inverter. (default: automatic) <br><br>

        <ul>
        <table>
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> automatic  </td><td>- the inverter will be polled regularly as defined by attribute "interval" </td></tr>
          <tr><td> manual     </td><td>- query only by command "get &lt;name&gt; data" </td></tr>
        </table>
        </ul>

  </li>
  <br>

  <a name="offset"></a>
  <li><b>offset &lt;0 - 7200&gt; </b><br>
    Time in seconds to forward the real sunrise respectively defer the real sunset.
    You will be able to extend the working period of the module.
  </li>
  <br>

  <a name="SBFSpotComp"></a>
  <li><b>SBFSpotComp [1|0]</b><br>
    The reading names are created like the SBFSpot-style. (default: 0)
  </li>
  <br>

  <a name="showproctime"></a>
  <li><b>showproctime [1|0]</b><br>
    Shows the processing time in background and the wasted time to retrieve inverter data. (default: 0)
  </li>
  <br>

  <a name="suppressSleep"></a>
  <li><b>suppressSleep [1|0]</b><br>
    The sleep mode (after sunset and before sunrise) is deactivated and the inverter will be polled continuously. (default: 0)
  </li>
  <br>

  <a name="target-serial"></a>
  <li><b>target-serial </b><br>
    In case of a Multigate the target serial number has to be defined. If more than one inverter is installed,
    you have to set the inverter serial number to assign the inverter to the device definition.
    If only one inverter available, the attribut is set automatically once the serial number of the inverter was detected.
    (default: 0xFFFFFFFF = means any serial number)
  </li>
  <br>

  <a name="target-susyid"></a>
  <li><b>target-susyid </b><br>
    In case of a Multigate the target SUSyID has to be defined. If more than one inverter is installed,
    you have to set the inverter-SUSyID to assign the inverter to the device definition.
    If only one inverter available, the attribut is set automatically once the SUSyID of the inverter was detected.
    (default: 0xFFFF = means any SUSyID)
  </li>
  <br>

  <a name="timeout"></a>
  <li><b>timeout </b><br>
    Setup timeout of inverter data request in seconds. (default 60)
  </li>
  <br>
  
  <a name="installerLogin"></a>
  <li><b>installerLogin </b><br>
    Logging in as an installer is required to read some parameters and instantaneous values. (default 0)
  </li>
  <br>
</ul>

<b>Readings</b>
<ul>
<li><b>BAT_CYCLES / bat_cycles</b>          		:  Battery recharge cycles </li>
<li><b>BAT_IDC [A,B,C] / bat_idc [A,B,C]</b>        :  Battery Current [A,B,C]</li>
<li><b>BAT_TEMP [A,B,C] / bat_temp [A,B,C]</b>      :  Battery temperature [A,B,C]</li>
<li><b>BAT_UDC [A,B,C] / bat_udc [A,B,C]</b>        :  Battery Voltage [A,B,C]</li>
<li><b>BAT_PDC / bat_pdc</b>       					:  Battery power (only Hybrid-Inverter), calculated from I and U</li>
<li><b>BAT_P_CHARGE / bat_p_charge</b> 				:  Battery chargepower (only Hybrid-Inverter)</li>
<li><b>BAT_P_DISCHARGE / bat_p_discharge</b> 		:  Battery dischargepower (only Hybrid-Inverter)</li>
<li><b>ChargeStatus / chargestatus</b>      		:  Battery Charge status </li>
<li><b>BAT_CAPACITY / bat_capacity</b>              :  Battery (remaining) Capacity (SOH)</li>
<li><b>BAT_RATED_CAPACITY / bat_rated_capacity</b>  :  Battery reted Capacity Wh/kWh</li>
<li><b>BAT_LOADTODAY</b>                    		:  Battery Load Today </li>
<li><b>BAT_LOADTOTAL</b>                    		:  Battery Load Total </li>
<li><b>BAT_UNLOADTODAY</b>                    		:  Battery Unload Today </li>
<li><b>BAT_UNLOADTOTAL</b>                    		:  Battery Unload Total </li>
<li><b>CLASS / device_class</b>             		:  Inverter Class </li>
<li><b>PACMAX1 / pac_max_phase_1</b>        		:  Nominal power in Ok Mode </li>
<li><b>PACMAX1_2 / pac_max_phase_1_2</b>    		:  Maximum active power device (Some inverters like SB3300/SB1200) </li>
<li><b>PACMAX2 / pac_max_phase_2</b>        		:  Nominal power in Warning Mode </li>
<li><b>PACMAX3 / pac_max_phase_3</b>        		:  Nominal power in Fault Mode </li>
<li><b>Serialnumber / serial_number</b>     		:  Inverter Serialnumber </li>
<li><b>SPOT_ETODAY / etoday</b>             		:  Today yield </li>
<li><b>SPOT_ETOTAL / etotal</b>             		:  Total yield </li>
<li><b>SPOT_EPVTODAY / epvtoday</b>             	:  Today PV yield </li>
<li><b>SPOT_EPVTOTAL / epvtotal</b>             	:  Total PV yield </li>
<li><b>SPOT_FEEDTM / feed-in_time</b>       		:  Feed-in time </li>
<li><b>SPOT_FREQ / grid_freq </b>           		:  Grid Frequency </li>
<li><b>SPOT_CosPhi / coshhi </b>           			:  displacement factor </li>
<li><b>SPOT_IAC1 / phase_1_iac</b>          		:  Grid current phase L1 </li>
<li><b>SPOT_IAC2 / phase_2_iac</b>          		:  Grid current phase L2 </li>
<li><b>SPOT_IAC3 / phase_3_iac</b>          		:  Grid current phase L3 </li>
<li><b>SPOT_IDC1 / string_1_idc</b>         		:  DC current input </li>
<li><b>SPOT_IDC2 / string_2_idc</b>         		:  DC current input </li>
<li><b>SPOT_IDC3 / string_3_idc</b>         		:  DC current input </li>
<li><b>SPOT_OPERTM / operation_time</b>     		:  Operation Time </li>
<li><b>SPOT_PAC1 / phase_1_pac</b>          		:  Power L1  </li>
<li><b>SPOT_PAC2 / phase_2_pac</b>          		:  Power L2  </li>
<li><b>SPOT_PAC3 / phase_3_pac</b>          		:  Power L3  </li>
<li><b>SPOT_PACTOT / total_pac</b>          		:  Total Power </li>
<li><b>SPOT_PDC1 / string_1_pdc</b>         		:  DC power input 1 </li>
<li><b>SPOT_PDC2 / string_2_pdc</b>         		:  DC power input 2 </li>
<li><b>SPOT_PDC3 / string_3_pdc</b>         		:  DC power input 3 </li>
<li><b>SPOT_PDC / strings_pds</b>    				:  DC power summary (only Hybrid-Inverter)</li>
<li><b>SPOT_UAC1 / phase_1_uac</b>          		:  Grid voltage phase L1 </li>
<li><b>SPOT_UAC2 / phase_2_uac</b>          		:  Grid voltage phase L2 </li>
<li><b>SPOT_UAC3 / phase_3_uac</b>          		:  Grid voltage phase L3 </li>
<li><b>SPOT_UAC1_2 / phase_1_2_uac</b>      		:  Grid voltage phase L1-L2 </li>
<li><b>SPOT_UAC2_3 / phase_2_3_uac</b>      		:  Grid voltage phase L2-L3 </li>
<li><b>SPOT_UAC3_1 / phase_3_1_uac</b>      		:  Grid voltage phase L3-L1 </li>
<li><b>SPOT_UDC1 / string_1_udc</b>         		:  DC voltage input </li>
<li><b>SPOT_UDC2 / string_2_udc</b>         		:  DC voltage input </li>
<li><b>SPOT_UDC3 / string_3_udc</b>         		:  DC voltage input </li>
<li><b>SUSyID / susyid</b>                  		:  Inverter SUSyID </li>
<li><b>INV_TEMP / device_temperature</b>    		:  Inverter temperature </li>
<li><b>INV_TYPE / device_type</b>           		:  Inverter Type </li>
<li><b>POWER_IN / power_in</b>              		:  Battery Charging power </li>
<li><b>POWER_OUT / power_out</b>            		:  Battery Discharging power </li>
<li><b>INV_GRIDRELAY / gridrelay_status</b> 		:  Grid Relay/Contactor Status</li>
<li><b>INV_BACKUPRELAY / backuprelay_status</b>     :  Backup Relay/Contactor Status (only Hybrid-Inverter)</li>
<li><b>INV_GridConection / grid_conection</b>       :  state of Gridconection (public grid/disconnected) (only SI-Inverter)</li>
<li><b>INV_GeneralOperatingStatus / general_operating_status</b> </li>    
<li>												:  General Status from the Inverter (MPP/Activated/Derating)</li>
<li><b>INV_OperatingStatus / operating_status</b> 	:  operating status from the Inverter (Parallel grid operation/Backup) (only Hybrid-Inverter)</li>
<li><b>INV_STATUS / device_status</b>       		:  Inverter Status </li>
<li><b>INV_FIRMWARE / device_firmware</b>       	:  Inverter firmware version </li>
<li><b>INV_DC_Insulation / device_dc_insulation</b> :  Insulation resistance in ohms on the DC side (only as Installer)</li>
<li><b>INV_DC_Residual_Current / device_dc_residual_current</b>:  Fault current in amperes on the DC side (only as Installer)</li>
<li><b>SPOT_BACKUP_IAC1 / phase_backup_1_iac</b>    :  Backup current phase L1 </li>
<li><b>SPOT_BACKUP_IAC2 / phase_backup_2_iac</b>    :  Backup current phase L2 </li>
<li><b>SPOT_BACKUP_IAC3 / phase_backup_3_iac</b>    :  Backup current phase L3 </li>
<li><b>SPOT_BACKUP_PAC1 / phase_backup_1_pac</b>    :  Backup power phase L1 </li>
<li><b>SPOT_BACKUP_PAC2 / phase_backup_2_pac</b>    :  Backup power phase L2 </li>
<li><b>SPOT_BACKUP_PAC3 / phase_backup_3_pac</b>    :  Backup power phase L3 </li>
<li><b>opertime_start</b>                   		:  Begin of iverter operating time corresponding the calculated time of sunrise with consideration of the
														attribute "offset" (if set) </li>
<li><b>opertime_stop</b>                    		:  End of iverter operating time corresponding the calculated time of sunrise with consideration of the
														attribute "offset" (if set) </li>
<li><b>modulstate</b>                       		:  shows the current module state "normal" or "sleep" if the inverter won't be requested at the time. </li>
<li><b>avg_power_lastminutes_05</b>         		:  average power of the last 5 minutes. </li>
<li><b>avg_power_lastminutes_10</b>         		:  average power of the last 10 minutes. </li>
<li><b>avg_power_lastminutes_15</b>         		:  average power of the last 15 minutes. </li>
<li><b>inverter_processing_time</b>         		:  wasted time to retrieve the inverter data </li>
<li><b>background_processing_time</b>       		:  total wasted time by background process (BlockingCall) </li>

<li><b>Meter_Grid_FeedIn_PACx / Meter_Grid_FeedIn_phase_x_pac</b>    			:  Power Grid_FeedIn phase Lx </li>
<li><b>Meter_Grid_Consumation_PACx / Meter_Grid_Consumation_phase_x_pac</b>    	:  Power Grid_Consumation phase Lx </li>
<li><b>Meter_Power_Grid_FeedIn / Meter_Power_Grid_FeedIn</b>    				:  total Power Grid_FeedIn </li>
<li><b>Meter_Power_Grid_Consumation / Meter_Power_Grid_Consumation</b>    		:  total Power Grid_Consumation </li>
<li><b>Meter_TOTAL_FeedIn / Meter_TOTAL_FeedIn</b>    							:  total Energie Grid_FeedIn</li>
<li><b>Meter_TOTAL_Consumation / Meter_TOTAL_Consumation</b>    				:  total Energie Grid_Consumation</li>
<li><b>Meter_TOTAL_Grid_FeedIn / Meter_TOTAL_Grid_FeedIn</b>    				:  total Energie Grid_FeedIn</li>
<li><b>Meter_TOTAL_Grid_Consumation / Meter_TOTAL_Grid_Consumation</b>    		:  total Energie Grid_Consumation</li>
</ul>
<br><br>

=end html


=begin html_DE

<a name="SMAInverter"></a>
<h3>SMAInverter</h3>

Modul zur Einbindung eines SMA Wechselrichters über Speedwire (Ethernet).<br>
Getestet mit Sunny Tripower 6000TL-20 und Sunny Island 4.4 mit Speedwire/Webconnect Piggyback.
<br><br>

Fragen und Diskussionen rund um dieses Modul finden sie im FHEM-Forum unter:<br>
<a href="https://forum.fhem.de/index.php/topic,56080.msg476525.html#msg476525">76_SMAInverter.pm - Abfrage von SMA Wechselrichter</a>.
<br><br>

<b>Voraussetzungen</b>
<br><br>
Dieses Modul benötigt:
<ul>
    <li>Perl Modul: IO::Socket::INET   (apt-get install libio-socket-multicast-perl) </li>
    <li>Perl Modul: Datetime           (apt-get install libdatetime-perl) </li>
    <li>Perl Modul: Time::HiRes</li>
    <li>FHEM Modul: 99_SUNRISE_EL.pm</li>
    <li>FHEM Modul: Blocking.pm</li>
</ul>
<br>
<br>

<b>Definition</b>
<ul>
<code>define &lt;name&gt; SMAInverter &lt;pin&gt; &lt;hostname/ip&gt;</code><br>
<br>
<li>pin: Passwort des Wechselrichters. Default ist 0000. <br>
         <b>Wechselrichter ohne Webinterface:</b> Das Passwort kann über die Client Software "Sunny Explorer" geändert werden. <br>
         <b>Wechselrichter mit Webinterface:</b> Das im Webinterface geänderte Passwort gilt auch für die Devicedefinition. </li>
<li>hostname/ip: Hostname oder IP-Adresse des Wechselrichters (bzw. dessen Speedwire Moduls mit Ethernetanschluss) </li>
<li>Der Speedwire-Port ist 9522. Dieser Port muss in der Firewall freigeschaltet sein !</li>
</ul>

<b>Arbeitsweise</b>
<ul>
Das Modul schickt Befehle an den Wechselrichter und überprüft, ob diese unterstützt werden.<br>
Bei einer positiven Antwort werden die Daten gesammelt und je nach Detail-Level in den Readings dargestellt. <br><br>

Die normale Betriebszeit des Wechselrichters wird in der Zeit vom Sonnenaufgang bis Sonnenuntergang angenommen. In dieser Periode werden die Wechselrichterdaten
abgefragt. Die Ermittlung von Sonnenaufgang / Sonnenuntergang wird über die Funktionen des FHEM-Moduls 99_SUNRISE_EL.pm vorgenommen. Zu diesem Zweck sollten die globalen
Attribute longitude und latitude gesetzt sein um den Standort der Anlage genau zu ermitteln. (siehe <a href="#SUNRISE_EL">Commandref SUNRISE_EL</a>) <br><br>

Mit dem Attribut "suppressSleep" kann der Schlafmodus unterdrückt werden. Das Attribut "offset" dient dazu den effektiven Zeitpunkt des Sonnenaufgangs / Sonnenuntergangs
um den Betrag "offset" vorzuziehen (Sonnenaufgang) bzw. zu verzögern (Sonnenuntergang) und somit die Abfrageperiode des Wechselrichters zu verlängern. <br><br>

Im Betriebsmodus "automatic" wird der Wechselrichter entsprechend des eingestellten Attributs "interval" abgefragt. Der Betriebsmodus kann in "manual"
umgestellt werden um eine manuelle Abfrage zu realisieren (z.B. Synchronisierung mit einem SMA Energymeter über ein Notify). <br><br>

Während der Betriebszeit des Wechselrichters wird die durchschnittliche Energieerzeugung der letzten 5, 10, 15 Minuten berechnet und in den Readings
"avg_power_lastminutes_05", "avg_power_lastminutes_10" und "avg_power_lastminutes_15" ausgegeben. <b>Hinweis:</b> Um eine korrekte Berechnung zu
ermöglichen, sollte auch im Betriebsmodus "manual" das tatsächliche Abfrageinterval im Attribute "interval" hinterlegt werden ! <br><br>

Die Abfrage des Wechselrichters wird non-blocking ausgeführt. Der Timeoutwert für diesen Hintergrundprozess kann mit dem Attribut "timeout" eingestellt werden. <br>

</ul>

<b>Get</b>
<br>
<ul>

  <li><b> get &lt;name&gt; data </b>
  <br><br>

  Die Datenabfrage des Wechselrichters wird ausgeführt. Diese Möglichkeit ist speziell für den Betriebsmodus "manual"
  vorgesehen (siehe Attribut "mode").
  <br>
  </li>
<br>
</ul>

<b>Attribute</b>
<br<br>
<ul>

  <a name="detail-level"></a>
  <li><b>detail-level [0|1|2] </b><br>
    Legt den Umfang der ausgegebenen Readings fest. <br><br>

        <ul>
        <table>
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> 0  </td><td>- nur Leistung und Energie </td></tr>
          <tr><td> 1  </td><td>- wie 0, zusätzlich Strom und Spannung </td></tr>
          <tr><td> 2  </td><td>- alle Werte </td></tr>
        </table>
        </ul>

  </li>
  <br>
  
  <a name="readEnergyMeter-data"></a>
  <li><b>readEnergyMeter-data [1|0]</b><br>
    Deaktiviert/aktiviert das lesen der Energymeter/Smartmeter Daten über den Wechselrichter.<br>
	Die Readings Meter_xxx werden dann angelegt und mit Daten befüllt.
  </li>
  <br>

  <a name="disable"></a>
  <li><b>disable [1|0]</b><br>
    Deaktiviert/aktiviert das Modul.
  </li>
  <br>

  <a name="interval"></a>
  <li><b>interval </b><br>
    Abfrageinterval in Sekunden. (default: 60)
  </li>
  <br>

  <a name="mode"></a>
  <li><b>mode [automatic|manual] </b><br>
    Abfragemodus des Wechselrichters. (default: automatic) <br><br>

        <ul>
        <table>
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> automatic  </td><td>- die Wechselrichterwerte werden im eingestellten Interval abgefragt (Attribut "interval") </td></tr>
          <tr><td> manual     </td><td>- Abfrage nur mit "get &lt;name&gt; data" </td></tr>
        </table>
        </ul>

  </li>
  <br>

  <a name="offset"></a>
  <li><b>offset &lt;0 - 7200&gt; </b><br>
    Zeit in Sekunden, um die der reale Sonnenaufgang vorgezogen bzw. reale Sonnenuntergang verzögert wird.
    Dadurch wird die effektive Aktivzeit des Moduls erweitert.
  </li>
  <br>

  <a name="SBFSpotComp"></a>
  <li><b>SBFSpotComp [1|0]</b><br>
    Die Readingnamen werden kompatibel zu SBFSpot-Ausgaben erzeugt. (default: 0)
  </li>
  <br>

  <a name="showproctime"></a>
  <li><b>showproctime [1|0]</b><br>
    Zeigt die für den Hintergrundprozess und die Abfrage des Wechselrichter verbrauchte Zeit. (default: 0)
  </li>
  <br>

  <a name="suppressSleep"></a>
  <li><b>suppressSleep [1|0]</b><br>
    Der Schlafmodus (nach Sonnenuntergang und vor Sonnenaufgang) wird ausgeschaltet und der WR abgefragt. (default: 0)
  </li>
  <br>

  <a name="target-serial"></a>
  <li><b>target-serial </b><br>
    Im Falle eines Multigate muss die Ziel-Seriennummer definiert werden. Ist mehr als ein Wechselrichter installiert,
    muß die Wechselreichter-Seriennummer gesetzt werden um den Wechselrichter der Device-Definition eindeutig zuzuweisen.
    Ist nur ein Wechselrichter vorhanden und das Attribut nicht gesetzt, wird es automatisch definiert sobald die
    Seriennummer des Wechselrichters erkannt wurde.
    (default: 0xFFFFFFFF = keine Einschränkung)
  </li>
  <br>

  <a name="target-susyid"></a>
  <li><b>target-susyid </b><br>
    Im Falle eines Multigate muss die Ziel-SUSyID definiert werden. Ist mehr als ein Wechselrichter installiert,
    muß die Wechselreichter-SUSyID gesetzt werden um den Wechselrichter der Device-Definition eindeutig zuzuweisen.
    Ist nur ein Wechselrichter vorhanden und das Attribut nicht gesetzt, wird es automatisch definiert sobald die
    SUSyID des Wechselrichters erkannt wurde.
    (default: 0xFFFF = keine Einschränkung)
  </li>
  <br>

  <a name="timeout"></a>
  <li><b>timeout </b><br>
    Einstellung des timeout für die Wechselrichterabfrage in Sekunden. (default 60)
  </li>
  <br>

  <a name="installerLogin"></a>
  <li><b>installerLogin </b><br>
    Einloggen als Installateur, wird benötig um manche Parameter und Momentanwerte zu lesen. (default 0)
  </li>
  <br>
</ul>

<b>Readings</b>
<ul>
<li><b>BAT_CYCLES / bat_cycles</b>          		:  Akku Ladezyklen </li>
<li><b>BAT_IDC [A,B,C] / bat_idc [A,B,C]</b>        :  Akku Strom [A,B,C]</li>
<li><b>BAT_TEMP [A,B,C] / bat_temp [A,B,C]</b>      :  Akku Temperatur [A,B,C]</li>
<li><b>BAT_UDC [A,B,C] / bat_udc [A,B,C]</b>        :  Akku Spannung [A,B,C]</li>
<li><b>BAT_PDC / bat_pdc</b> 						:  Akku Leistung (bei Hybridwechselrichtern), berechneter Wert aus Strom und Spannung</li>
<li><b>BAT_P_CHARGE / bat_p_charge</b> 				:  Akku Ladeleistung (bei Hybridwechselrichtern)</li>
<li><b>BAT_P_DISCHARGE / bat_p_discharge</b> 		:  Akku Entladeleistung (bei Hybridwechselrichtern)</li>
<li><b>ChargeStatus / chargestatus</b>      		:  Akku Ladestand </li>
<li><b>BAT_CAPACITY / bat_capacity</b>         		:  Battery (verbleibende) Kapazität (SOH)</li>
<li><b>BAT_RATED_CAPACITY / bat_rated_capacity</b>  :  Battery Nennkapazität Wh/kWh</li>
<li><b>BAT_LOADTODAY</b>                    		:  Battery Load Today </li>
<li><b>BAT_LOADTOTAL</b>                    		:  Battery Load Total </li>
<li><b>BAT_UNLOADTODAY</b>                    		:  Battery Unload Today </li>
<li><b>BAT_UNLOADTOTAL</b>                    		:  Battery Unload Total </li>
<li><b>CLASS / device_class</b>             		:  Wechselrichter Klasse </li>
<li><b>PACMAX1 / pac_max_phase_1</b>        		:  Nominelle Leistung in Ok Mode </li>
<li><b>PACMAX1_2 / pac_max_phase_1_2</b>    		:  Maximale Leistung (für einige Wechselrichtertypen) </li>
<li><b>PACMAX2 / pac_max_phase_2</b>        		:  Nominelle Leistung in Warning Mode </li>
<li><b>PACMAX3 / pac_max_phase_3</b>        		:  Nominelle Leistung in Fault Mode </li>
<li><b>Serialnumber / serial_number</b>     		:  Wechselrichter Seriennummer </li>
<li><b>SPOT_ETODAY / etoday</b>             		:  Energie heute</li>
<li><b>SPOT_EPVTOTAL / epvtotal</b>             	:  PV Energie Insgesamt </li>
<li><b>SPOT_EPVTODAY / epvtoday</b>             	:  PV Energie heute</li>
<li><b>SPOT_ETOTAL / etotal</b>             		:  Energie Insgesamt </li>
<li><b>SPOT_FEEDTM / feed-in_time</b>       		:  Einspeise-Stunden </li>
<li><b>SPOT_FREQ / grid_freq </b>           		:  Netz Frequenz </li>
<li><b>SPOT_CosPhi / coshhi </b>           			:  Verschiebungsfaktor </li>
<li><b>SPOT_IAC1 / phase_1_iac</b>          		:  Netz Strom phase L1 </li>
<li><b>SPOT_IAC2 / phase_2_iac</b>          		:  Netz Strom phase L2 </li>
<li><b>SPOT_IAC3 / phase_3_iac</b>          		:  Netz Strom phase L3 </li>
<li><b>SPOT_IDC1 / string_1_idc</b>         		:  DC Strom Eingang 1 </li>
<li><b>SPOT_IDC2 / string_2_idc</b>         		:  DC Strom Eingang 2 </li>
<li><b>SPOT_IDC3 / string_3_idc</b>         		:  DC Strom Eingang 3 </li>
<li><b>SPOT_OPERTM / operation_time</b>     		:  Betriebsstunden </li>
<li><b>SPOT_PAC1 / phase_1_pac</b>          		:  Leistung L1  </li>
<li><b>SPOT_PAC2 / phase_2_pac</b>          		:  Leistung L2  </li>
<li><b>SPOT_PAC3 / phase_3_pac</b>          		:  Leistung L3  </li>
<li><b>SPOT_PACTOT / total_pac</b>          		:  Gesamtleistung </li>
<li><b>SPOT_PDC1 / string_1_pdc</b>         		:  DC Leistung Eingang 1 </li>
<li><b>SPOT_PDC2 / string_2_pdc</b>         		:  DC Leistung Eingang 2 </li>
<li><b>SPOT_PDC3 / string_3_pdc</b>         		:  DC Leistung Eingang 3 </li>
<li><b>SPOT_PDC / strings_pds</b>       			:  DC Leistung gesamt (bei Hybridwechselrichtern)</li>
<li><b>SPOT_UAC1 / phase_1_uac</b>          		:  Netz Spannung phase L1 </li>
<li><b>SPOT_UAC2 / phase_2_uac</b>          		:  Netz Spannung phase L2 </li>
<li><b>SPOT_UAC3 / phase_3_uac</b>          		:  Netz Spannung phase L3 </li>
<li><b>SPOT_UAC1_2 / phase_1_2_uac</b>          	:  Netz Spannung phase L1-L2 </li>
<li><b>SPOT_UAC2_3 / phase_2_3_uac</b>          	:  Netz Spannung phase L2-L3 </li>
<li><b>SPOT_UAC3_1 / phase_3_1_uac</b>          	:  Netz Spannung phase L3-L1 </li>
<li><b>SPOT_UDC1 / string_1_udc</b>         		:  DC Spannung Eingang 1 </li>
<li><b>SPOT_UDC2 / string_2_udc</b>         		:  DC Spannung Eingang 2 </li>
<li><b>SPOT_UDC3 / string_3_udc</b>         		:  DC Spannung Eingang 3 </li>
<li><b>SUSyID / susyid</b>                  		:  Wechselrichter SUSyID </li>
<li><b>INV_TEMP / device_temperature</b>    		:  Wechselrichter Temperatur </li>
<li><b>INV_TYPE / device_type</b>           		:  Wechselrichter Typ </li>
<li><b>POWER_IN / power_in</b>              		:  Akku Ladeleistung </li>
<li><b>POWER_OUT / power_out</b>            		:  Akku Entladeleistung </li>
<li><b>INV_GRIDRELAY / gridrelay_status</b> 		:  Netz Relais Status </li>
<li><b>INV_BACKUPRELAY / backuprelay_status</b>     :  Backup Relais Status (bei Hybridwechselrichtern)</li>
<li><b>INV_GridConection / grid_conection</b>       :  Status des Netzanschlusses (Öffentliches Stromnetz/Getrennt) (nur SI-Inverter)</li>
<li><b>INV_GeneralOperatingStatus / general_operating_status</b> </li>    
<li>												:  Allgemeiner Betriebszustand des Wechselrichters (MPP/Eingeschaltet/Abregelung)</li>
<li><b>INV_OperatingStatus / operating_status</b> 	:  Betriebsstatus des Wechselrichters (Netzparallelbetrieb/Backup) (bei Hybridwechselrichtern)</li>
<li><b>INV_STATUS / device_status</b>       		:  Wechselrichter Status </li>
<li><b>INV_FIRMWARE / device_firmware</b>       	:  Wechselrichter Firmwareversion </li>
<li><b>INV_DC_Insulation / device_dc_insulation</b> :  Isolationswiderstand in Ohm der DC Seite (nur als Installateur zu lesen)</li>
<li><b>INV_DC_Residual_Current / device_dc_residual_current</b>:  Fehlerstrom in Ampere der DC Seite (nur als Installateur zu lesen)</li>
<li><b>SPOT_BACKUP_IAC1 / phase_backup_1_iac</b>    :  Backup Strom phase L1 </li>
<li><b>SPOT_BACKUP_IAC2 / phase_backup_2_iac</b>    :  Backup Strom phase L2 </li>
<li><b>SPOT_BACKUP_IAC3 / phase_backup_3_iac</b>    :  Backup Strom phase L3 </li>
<li><b>SPOT_BACKUP_PAC1 / phase_backup_1_pac</b>    :  Backup Leistung phase L1 </li>
<li><b>SPOT_BACKUP_PAC2 / phase_backup_2_pac</b>    :  Backup Leistung phase L2 </li>
<li><b>SPOT_BACKUP_PAC3 / phase_backup_3_pac</b>    :  Backup Leistung phase L3 </li>
<li><b>opertime_start</b>                   		:  Beginn Aktivzeit des Wechselrichters entsprechend des ermittelten Sonnenaufgangs mit Berücksichtigung des
														Attributs "offset" (wenn gesetzt) </li>
<li><b>opertime_stop</b>                    		:  Ende Aktivzeit des Wechselrichters entsprechend des ermittelten Sonnenuntergangs mit Berücksichtigung des
														Attributs "offset" (wenn gesetzt) </li>
<li><b>modulstate</b>                       		:  zeigt den aktuellen Modulstatus "normal" oder "sleep" falls der Wechselrichter nicht abgefragt wird. </li>
<li><b>avg_power_lastminutes_05</b>         		:  durchschnittlich erzeugte Leistung der letzten 5 Minuten. </li>
<li><b>avg_power_lastminutes_10</b>         		:  durchschnittlich erzeugte Leistung der letzten 10 Minuten. </li>
<li><b>avg_power_lastminutes_15</b>         		:  durchschnittlich erzeugte Leistung der letzten 15 Minuten. </li>
<li><b>inverter_processing_time</b>         		:  verbrauchte Zeit um den Wechelrichter abzufragen. </li>
<li><b>background_processing_time</b>       		:  gesamte durch den Hintergrundprozess (BlockingCall) verbrauchte Zeit. </li>

<li><b>Meter_Grid_FeedIn_PACx / Meter_Grid_FeedIn_phase_x_pac</b>    			:  Leistung Netzeinspeisung phase Lx </li>
<li><b>Meter_Grid_Consumation_PACx / Meter_Grid_Consumation_phase_x_pac</b>    	:  Leistung Netzbezug phase Lx </li>
<li><b>Meter_Power_Grid_FeedIn / Meter_Power_Grid_FeedIn</b>    				:  Summe Leistung Netzeinspeisung </li>
<li><b>Meter_Power_Grid_Consumation / Meter_Power_Grid_Consumation</b>    		:  Summe Leistung Netzbezug </li>
<li><b>Meter_TOTAL_FeedIn / Meter_TOTAL_FeedIn</b>    							:  Summe Energie Netzeinspeisung</li>
<li><b>Meter_TOTAL_Consumation / Meter_TOTAL_Consumation</b>    				:  Summe Energie Netzbezug</li>
<li><b>Meter_TOTAL_Grid_FeedIn / Meter_TOTAL_Grid_FeedIn</b>    				:  Summe Energie Netzeinspeisung</li>
<li><b>Meter_TOTAL_Grid_Consumation / Meter_TOTAL_Grid_Consumation</b>    		:  Summe Energie Netzbezug</li>
</ul>
<br><br>

=end html_DE

=for :application/json;q=META.json 76_SMAInverter.pm
{
  "abstract": "Integration of SMA Inverters over it's Speedwire (=Ethernet) Interface",
  "x_lang": {
    "de": {
      "abstract": "Integration von SMA Wechselrichtern ueber Speedwire (=Ethernet) Interface"
    }
  },
  "keywords": [
    "SMA",
    "photovoltaics",
    "PV",
    "inverter"
  ],
  "version": "v2.29.8",
  "release_status": "stable",
  "author": [
    "Maximilian Paries",
    "Heiko Maaz <heiko.maaz@t-online.de>",
    null
  ],
  "x_fhem_maintainer": [
    "MadMax",
    "DS_Starter",
    null
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "IO::Socket::INET": 0,
        "DateTime": 0,
        "Time::HiRes": 0,
        "Blocking": 0,
        "Time::Local": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
