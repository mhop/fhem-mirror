# $Id$

package main;
use strict;
use warnings;
my $cryptFunc;
my $xmlFunc;
my $xml;

eval "use Crypt::Rijndael";
if ($@) {
  $cryptFunc = 0;
} else {
  $cryptFunc = 1;
}
eval "use Crypt::Random qw(makerandom)";
if ($@) {
  $cryptFunc = 0;
} else {
  $cryptFunc = $cryptFunc == 1 ? 1 : 0;
}

eval "use XML::Simple";
if ($@) {
  $xmlFunc = 0;
} else {
  $xmlFunc = 1;
  $xml = new XML::Simple;
}

eval "use Data::Dumper";
if ($@) {
  $xmlFunc = 0;
} else {
  $xmlFunc = $xmlFunc == 1 ? 1 : 0;
}

use SetExtensions;

sub EnOcean_Define($$);
sub EnOcean_Initialize($);
sub EnOcean_Parse($$);
sub EnOcean_Get($@);
sub EnOcean_Set($@);
sub EnOcean_roomCtrlPanel_00Snd($$$$$$$$);
sub EnOcean_CheckSenderID($$$);
sub EnOcean_SndRadio($$$$$$$$);
sub EnOcean_ReadingScaled($$$$);
sub EnOcean_TimerSet($);
sub EnOcean_Undef($$);

my %EnO_rorgname = (
  "A5" => "4BS",      # 4BS, org 07
  "A6" => "ADT",      # adressing destination telegram
  "A7" => "SMREC",    # Smart Ack Relaim
  "B0" => "GPTI",     # GP teach-in request
  "B1" => "GPTR",     # GP teach-in response
  "B2" => "GPCD",     # GP complete data
  "B3" => "GPSD",     # GP selective data
  "C5" => "SYSEX",    # remote management >> packet type 7 used
  "C6" => "SMLRNREQ", # Smart Ack Learn Request
  "C7" => "SMLRNANS", # Smart Ack Learn Answer
  "D0" => "SIGNAL",   # Smart Ack Mail Box Functions
  "D1" => "MSC",      # MSC
  "D2" => "VLD",      # VLD
  "D4" => "UTE",      # UTE
  "D5" => "contact",  # 1BS, org 06
  "F6" => "switch",   # RPS, org 05
  "30" => "SEC",      # secure telegram
  "31" => "ENC",      # secure telegram with encapsulation
  "32" => "SECD",     # decrypted secure telegram
  "35" => "STE",      # secure Teach-In
  "40" => "CDM",      # chained data message
);

# switch commands
my @EnO_ptm200btn = ("AI", "A0", "BI", "B0", "CI", "C0", "DI", "D0");
my %EnO_ptm200btn;

# switch.00 commands
my %EnO_switch_00Btn = (
  "A0"         => 14,
  "AI"         => 13,
  "B0"         => 12,
  "BI"         => 11,
  "A0,B0"      => 7,
  "A0,BI"      => 10,
  "AI,B0"      => 5,
  "AI,BI"      => 9,
  "pressed"    => 8,
  "pressed34"  => 6,
  "released"   => 15,
  "teachInSec" => 253,
  "teachOut"   => 254,
  "teachIn"    => 255
);

# gateway commands
my @EnO_gwCmd = ("switching", "dimming", "setpointShift", "setpointBasic", "controlVar", "fanStage", "blindCmd");
my %EnO_gwCmd = (
  "switching"     => 1,
  "dimming"       => 2,
  "setpointShift" => 3,
  "setpointBasic" => 4,
  "controlVar"    => 5,
  "fanStage"      => 6,
  "blindCmd"      => 7,
);

# Some Manufacturers (e.g. Jaeger Direkt) also sell EnOcean products without an entry in the table below.
my %EnO_manuf = (
  "000" => "Reserved",
  "001" => "Peha",
  "002" => "Thermokon",
  "003" => "Servodan",
  "004" => "EchoFlex Solutions",
  "005" => "AWAG Elektrotechnik AG (Omnio)",
  "006" => "Hardmeier electronics",
  "007" => "Regulvar Inc",
  "008" => "Ad Hoc Electronics",
  "009" => "Distech Controls",
  "00A" => "Kieback + Peter",
  "00B" => "EnOcean GmbH",
  "00C" => "Probare",
  "00D" => "Eltako",
  "00E" => "Leviton",
  "00F" => "Honeywell",
  "010" => "Spartan Peripheral Devices",
  "011" => "Siemens",
  "012" => "T-Mac",
  "013" => "Reliable Controls Corporation",
  "014" => "Elsner Elektronik GmbH",
  "015" => "Diehl Controls",
  "016" => "BSC Computer",
  "017" => "S+S Regeltechnik GmbH",
  "018" => "ZENO Controls, LLC",
  "019" => "Intesis Software SL",
  "01A" => "Viessmann",
  "01B" => "Lutuo Technology",
  "01C" => "Schneider Electric",
  "01D" => "Sauter",
  "01E" => "Boot-Up",
  "01F" => "Osram Sylvania",
  "020" => "Unotech",
  "021" => "Delta Controls Inc",
  "022" => "Unitronic AG",
  "023" => "NanoSense",
  "024" => "The S4 Group",
  "025" => "MSR Solutions",
  "026" => "GE",
  "027" => "Maico",
  "028" => "Ruskin Company",
  "029" => "Magnum Engery Solutions",
  "02A" => "KM Controls",
  "02B" => "Ecologix Controls",
  "02C" => "Trio 2 Sys",
  "02D" => "Afriso-Euro-Index",
  "030" => "NEC Access Technica Ltd",
  "031" => "ITEC Corporation",
  "032" => "Simix Co Ltd",
  "033" => "Permundo GmbH",
  "034" => "EUROtronic Technology GmbH",
  "035" => "Art Japan Co. Ltd.",
  "036" => "Tiansu Automation Control System Co Ltd",
  "038" => "Gruppo Giordano, Idea Spa",
  "039" => "alphaEOS AG",
  "03A" => "Tag Technologies",
  "03B" => "Wattstopper",
  "03C" => "Pressac Communications Ltd.",
  "03E" => "GIGA-concept",
  "03F" => "Sensortec AG",
  "040" => "Jaeger Direkt",
  "041" => "Air System Components Inc.",
  "042" => "ERMINE Corp.",
  "043" => "SODA GmbH",
  "045" => "Holter Regelarmaturen GmbH Co. KG",
  "046" => "ID-RF",
  "047" => "DEUTA Controls GmbH",
  "048" => "Ewattch",
  "049" => "Micropelt GmbH",
  "04A" => "Caleffi Spa.",
  "04B" => "Digital Concepts GmbH",
  "04C" => "Emerson Climate Technologies",
  "04D" => "ADEE electronic",
  "04E" => "ALTECON srl",
  "04F" => "Nanjing Putian elecommunications Co.",
  "050" => "Terralux",
  "051" => "iEXERGY GmbH",
  "052" => "Connectivity Solutions GmbH",
  "053" => "Oventrop GmbH Co. KG",
  "054" => "Builing Automation Products",
  "055" => "Functional Devices, Inc.",
  "056" => "OGGA",
  "057" => "itho daalderop",
  "058" => "Resol",
  "059" => "Advanced Devices",
  "05A" => "Autani LLC.",
  "05B" => "Dr. Riedel GmbH",
  "05C" => "HOPPE Holding AG",
  "05D" => "SIEGENIA-AUBI KG",
  "05E" => "ADEO Services",
  "05F" => "EiMSIG, EFP GmbH",
  "060" => "VIMAR S.p.a.",
  "061" => "Glen Dimplex",
  "062" => "PMDM GmbH",
  "063" => "Hubbell Lighting",
  "064" => "Debflex S.A.",
  "065" => "Perfactory Sensorsystems",
  "066" => "Watty Corporation",
  "067" => "WAGO Kontakttechnik GmbH Co. KG",
  "068" => "Kessel AG",
  "069" => "Aug. GmbH Co. KG",
  "06A" => "DECELECT",
  "06B" => "MST Industries",
  "06C" => "Becker Antriebs GmbH",
  "06D" => "Nexelec",
  "06E" => "Wieland Electric GmbH",
  "06F" => "AVIDSEN",
  "070" => "CWS-boco International GmbH",
  "071" => "Roto Frank AG",
  "072" => "ALM Controls e.k.",
  "073" => "Tommaso Technologies Ltd.",
  "074" => "Rehaus AG + Co.",
  "075" => "Inaba Denki Sangyo Co. Ltd.",
  "076" => "Hager Control SAS",
  "7FF" => "Multi user Manufacturer ID"
);

my %EnO_eepConfig = (
  "A5.02.01" => {attr => {subType => "tempSensor.01"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.02" => {attr => {subType => "tempSensor.02"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.03" => {attr => {subType => "tempSensor.03"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.04" => {attr => {subType => "tempSensor.04"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.05" => {attr => {subType => "tempSensor.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.06" => {attr => {subType => "tempSensor.06"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.07" => {attr => {subType => "tempSensor.07"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.08" => {attr => {subType => "tempSensor.08"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.09" => {attr => {subType => "tempSensor.09"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.0A" => {attr => {subType => "tempSensor.0A"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.0B" => {attr => {subType => "tempSensor.0B"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.10" => {attr => {subType => "tempSensor.10"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.11" => {attr => {subType => "tempSensor.11"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.12" => {attr => {subType => "tempSensor.12"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.13" => {attr => {subType => "tempSensor.13"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.14" => {attr => {subType => "tempSensor.14"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.15" => {attr => {subType => "tempSensor.15"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.16" => {attr => {subType => "tempSensor.16"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.17" => {attr => {subType => "tempSensor.17"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.18" => {attr => {subType => "tempSensor.18"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.19" => {attr => {subType => "tempSensor.19"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.1A" => {attr => {subType => "tempSensor.1A"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.1B" => {attr => {subType => "tempSensor.1B"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.20" => {attr => {subType => "tempSensor.20"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.02.30" => {attr => {subType => "tempSensor.30"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.04.01" => {attr => {subType => "roomSensorControl.01"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.04.02" => {attr => {subType => "tempHumiSensor.02"}, GPLOT => "EnO_temp4humi6:Temp/Humi,EnO_voltage4:Voltage,"},
  "A5.04.03" => {attr => {subType => "tempHumiSensor.03"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.05.01" => {attr => {subType => "baroSensor.01"}, GPLOT => "EnO_airPressure4:Airpressure,"},
  "A5.06.01" => {attr => {subType => "lightSensor.01"}, GPLOT => "EnO_brightness4:Brightness,EnO_voltage4:Voltage,"},
  "A5.06.02" => {attr => {subType => "lightSensor.02"}, GPLOT => "EnO_brightness4:Brightness,EnO_voltage4:Voltage,"},
  "A5.06.03" => {attr => {subType => "lightSensor.03"}, GPLOT => "EnO_brightness4:Brightness,"},
  "A5.06.04" => {attr => {subType => "lightSensor.04"}, GPLOT => "EnO_temp4brightness4:Temp/Brightness,"},
  "A5.06.05" => {attr => {subType => "lightSensor.05"}, GPLOT => "EnO_brightness4:Brightness,EnO_voltage4:Voltage,"},
  "A5.07.01" => {attr => {subType => "occupSensor.01"}, GPLOT => "EnO_motion:Motion,EnO_voltage4current4:Voltage/Current,"},
  "A5.07.02" => {attr => {subType => "occupSensor.02"}, GPLOT => "EnO_motion:Motion4brightness4:Motion/Brightness,EnO_voltage4:Voltage,"},
  "A5.07.03" => {attr => {subType => "occupSensor.03"}, GPLOT => "EnO_motion:Motion4brightness4:Motion/Brightness,EnO_voltage4:Voltage,"},
  "A5.08.01" => {attr => {subType => "lightTempOccupSensor.01"}, GPLOT => "EnO_temp4brightness4:Temp/Brightness,EnO_voltage4:Voltage,"},
  "A5.08.02" => {attr => {subType => "lightTempOccupSensor.02"}, GPLOT => "EnO_temp4brightness4:Temp/Brightness,EnO_voltage4:Voltage,"},
  "A5.08.03" => {attr => {subType => "lightTempOccupSensor.03"}, GPLOT => "EnO_temp4brightness4:Temp/Brightness,EnO_voltage4:Voltage,"},
  "A5.09.01" => {attr => {subType => "COSensor.01"}, GPLOT => "EnO_A5-09-01:CO/Temp,"},
  "A5.09.02" => {attr => {subType => "COSensor.02"}, GPLOT => "EnO_A5-09-02:CO/Temp,EnO_voltage4:Voltage,"},
  "A5.09.04" => {attr => {subType => "tempHumiCO2Sensor.01"}, GPLOT => "EnO_CO2:CO2,EnO_temp4humi6:Temp/Humi,"},
  "A5.09.05" => {attr => {subType => "vocSensor.01"}, GPLOT => "EnO_A5-09-05:Concentration,"},
  "A5.09.06" => {attr => {subType => "radonSensor.01"}, GPLOT => "EnO_A5-09-06:Radon,"},
  "A5.09.07" => {attr => {subType => "particlesSensor.01"}, GPLOT => "EnO_A5-09-07:Particles,"},
  "A5.09.08" => {attr => {subType => "CO2Sensor.01"}, GPLOT => "EnO_CO2:CO2,"},
  "A5.09.09" => {attr => {subType => "CO2Sensor.01"}, GPLOT => "EnO_CO2:CO2,"},
  "A5.09.0A" => {attr => {subType => "HSensor.01"}, GPLOT => "EnO_A5-09-0A:H/Temp,EnO_voltage4:Voltage,"},
  "A5.09.0B" => {attr => {subType => "radiationSensor.01"}, GPLOT => "EnO_radioactivity4/Radioactivity,EnO_voltage4:Voltage,"},
  "A5.09.0C" => {attr => {subType => "vocSensor.01"}, GPLOT => "EnO_A5-09-05:Concentration,"},
  "A5.10.01" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.02" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.03" => {attr => {subType => "roomSensorControl.05", comMode => "confirm", subDef => "getNextID"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.04" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.05" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.06" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.07" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.08" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.09" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.0A" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.0B" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.0C" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.0D" => {attr => {subType => "roomSensorControl.05"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.10" => {attr => {subType => "roomSensorControl.01"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.10.11" => {attr => {subType => "roomSensorControl.01"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.10.12" => {attr => {subType => "roomSensorControl.01"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.10.13" => {attr => {subType => "roomSensorControl.01"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.10.14" => {attr => {subType => "roomSensorControl.01"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.10.15" => {attr => {subType => "roomSensorControl.02"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.16" => {attr => {subType => "roomSensorControl.02"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.17" => {attr => {subType => "roomSensorControl.02"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.18" => {attr => {subType => "roomSensorControl.18"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.19" => {attr => {subType => "roomSensorControl.19"}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "A5.10.1A" => {attr => {subType => "roomSensorControl.1A"}, GPLOT => "EnO_temp4:Temp,EnO_voltage4:Voltage,"},
  "A5.10.1B" => {attr => {subType => "roomSensorControl.1B"}, GPLOT => "EnO_temp4:Temp,EnO_voltage4:Voltage,"},
  "A5.10.1C" => {attr => {subType => "roomSensorControl.1C"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.1D" => {attr => {subType => "roomSensorControl.1D"}, GPLOT => "EnO_temp4humi6:Temp/Humi"},
  "A5.10.1E" => {attr => {subType => "roomSensorControl.1B"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.1F" => {attr => {subType => "roomSensorControl.1F"}, GPLOT => "EnO_temp4:Temp,"},
  "A5.10.20" => {attr => {subType => "roomSensorControl.20"}, GPLOT => "EnO_temp4humi4:Temp/Humi,"},
  "A5.10.21" => {attr => {subType => "roomSensorControl.20"}, GPLOT => "EnO_temp4humi4:Temp/Humi,"},
  "A5.10.22" => {attr => {subType => "roomSensorControl.22"}, GPLOT => "EnO_temp4humi4:Temp/Humi,"},
  "A5.10.23" => {attr => {subType => "roomSensorControl.22"}, GPLOT => "EnO_temp4humi4:Temp/Humi,"},
  "A5.11.01" => {attr => {subType => "lightCtrlState.01"}, GPLOT => "EnO_A5-11-01:Dim/Brightness,"},
  "A5.11.02" => {attr => {subType => "tempCtrlState.01"}, GPLOT => "EnO_A5-11-02:SetpointTemp/ControlVar,"},
  "A5.11.03" => {attr => {subType => "shutterCtrlState.01", subDef => "getNextID", subTypeSet => "gateway", gwCmd => "blindCmd", webCmd => "opens:stop:closes:position"}, GPLOT => "EnO_A5-11-03:Position/AnglePos,"},
  "A5.11.04" => {attr => {subType => "lightCtrlState.02", subDef => "getNextID", subTypeSet => "lightCtrl.01", webCmd => "on:off:dim:rgb"}, GPLOT => "EnO_dimFFRGB:DimRGB,"},
  "A5.11.05" => {attr => {subType => "switch.05"}},
  "A5.12.00" => {attr => {subType => "autoMeterReading.00"}, GPLOT => "EnO_A5-12-00:Value/Counter,"},
  "A5.12.01" => {attr => {subType => "autoMeterReading.01"}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "A5.12.02" => {attr => {subType => "autoMeterReading.02"}, GPLOT => "EnO_A5-12-02:Flowrate/Consumption,"},
  "A5.12.03" => {attr => {subType => "autoMeterReading.03"}, GPLOT => "EnO_A5-12-03:Flowrate/Consumption,"},
  "A5.12.04" => {attr => {subType => "autoMeterReading.04"}, GPLOT => "EnO_A5-12-04:Weight,EnO_A5-12-04_2:Temperature/Battery,"},
  "A5.12.05" => {attr => {subType => "autoMeterReading.05"}, GPLOT => "EnO_A5-12-05:Amount,EnO_A5-12-05_2:Temperature/Battery,"},
  "A5.12.10" => {attr => {subType => "autoMeterReading.10"}, GPLOT => "EnO_A5-12-10:Current/Change,"},
  "A5.13.01" => {attr => {subType => "environmentApp"}, GPLOT => "EnO_A5-13-01:WindSpeed/Raining,EnO_temp4brightness4:Temp/Brightness,"},
  "A5.13.02" => {attr => {subType => "environmentApp"}, GPLOT => "EnO_A5-13-02:SunIntensity,"},
  "A5.13.03" => {attr => {subType => "environmentApp"}},
  "A5.13.04" => {attr => {subType => "environmentApp"}},
  "A5.13.05" => {attr => {subType => "environmentApp"}},
  "A5.13.06" => {attr => {subType => "environmentApp"}},
  "A5.13.07" => {attr => {subType => "windSensor.01"}, GPLOT => "EnO_A5-13-07:WindSpeed,"},
  "A5.13.08" => {attr => {subType => "rainSensor.01"}, GPLOT => "EnO_A5-13-08:Raining,"},
  "A5.13.10" => {attr => {subType => "environmentApp"}, GPLOT => "EnO_solarRadiation4:SolarRadiation,"},
  "A5.14.01" => {attr => {subType => "multiFuncSensor"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.02" => {attr => {subType => "multiFuncSensor"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.03" => {attr => {subType => "multiFuncSensor"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.04" => {attr => {subType => "multiFuncSensor"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.05" => {attr => {subType => "multiFuncSensor"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.06" => {attr => {subType => "multiFuncSensor"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.07" => {attr => {subType => "doorContact"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.08" => {attr => {subType => "doorContact"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.09" => {attr => {subType => "windowContact"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.14.0A" => {attr => {subType => "windowContact"}, GPLOT => "EnO_A5-14-xx:Voltage/Brightness,EnO_A5-14-xx_2:Contact/Vibration,"},
  "A5.20.01" => {attr => {subType => "hvac.01", webCmd => "setpointTemp"}, GPLOT => "EnO_A5-20-01:Temp/SetpointTemp/Setpoint,EnO_A5-20-01_2:PID,"},
 #"A5.20.02" => {attr => {subType => "hvac.02"}},
 #"A5.20.03" => {attr => {subType => "hvac.03"}},
  "A5.20.04" => {attr => {subType => "hvac.04", webCmd => "setpointTemp"}, GPLOT => "EnO_A5-20-04:Temp/FeedTemp,EnO_A5-20-04_2:SetpointTemp/Setpoint,EnO_A5-20-04_3:PID,"},
  "A5.20.06" => {attr => {subType => "hvac.06", webCmd => "setpointTemp"}, GPLOT => "EnO_A5-20-06:Temp/SetpointTemp/FeedTemp/RoomTemp/Setpoint,EnO_A5-20-06_2:PID,"},
  "A5.20.10" => {attr => {subType => "hvac.10", comMode => "biDir", destinationID => "unicast", subDef => "getNextID"}, GPLOT => "EnO_A5-20-10:FanSpeed,"},
  "A5.20.11" => {attr => {subType => "hvac.11", comMode => "biDir", destinationID => "unicast", subDef => "getNextID"}},
 #"A5.20.12" => {attr => {subType => "hvac.12"}},
  "A5.30.01" => {attr => {subType => "digitalInput.01"}, GPLOT => "EnO_A5-30-01:Contact/Battery,"},
  "A5.30.02" => {attr => {subType => "digitalInput.02"}, GPLOT => "EnO_A5-30-02:Contact,"},
  "A5.30.03" => {attr => {subType => "digitalInput.03"}, GPLOT => "EnO_A5-30-03:Contact,EnO_temp4:Temp,"},
  "A5.30.04" => {attr => {subType => "digitalInput.04"}, GPLOT => "EnO_A5-30-04:Contact/Digital,"},
  "A5.30.05" => {attr => {subType => "digitalInput.05"}, GPLOT => "EnO_A5-30-05:Contact/Voltage,"},
  "A5.37.01" => {attr => {subType => "energyManagement.01", webCmd => "level:max"}, GPLOT => "EnO_A5-37-01:Level,"},
  "A5.38.08" => {attr => {subType => "gateway"}},
  "A5.38.09" => {attr => {subType => "lightCtrl.01"}, GPLOT => "EnO_dimFFRGB:DimRGB,"},
  "A5.3F.00" => {attr => {subType => "radioLinkTest", comMode => "biDir", destinationID => "unicast", subDef => "getNextID"}},
  "A5.3F.7F" => {attr => {subType => "manufProfile"}},
  "B0.00.00" => {attr => {subType => "genericProfile"}},
  "C5.00.00" => {attr => {subType => "remote", manufID => "7FF"}},
  "D2.01.00" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.01" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.02" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,EnO_power4energy4:Power/Energie,"},
  "D2.01.03" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,"},
  "D2.01.04" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,EnO_power4energy4:Power/Energie,"},
  "D2.01.05" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,EnO_power4energy4:Power/Energie,"},
  "D2.01.06" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.07" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.08" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.09" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,EnO_power4energy4:Power/Energie,"},
  "D2.01.0A" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.0B" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.0C" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.0D" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.0E" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.0F" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.10" => {attr => {subType => "actuator.01", defaultChannel => 0}, GPLOT => "EnO_power4energy4:Power/Energie,"},
  "D2.01.11" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.12" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.13" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.14" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.03.00" => {attr => {subType => "switch.00"}},
  "D2.03.0A" => {attr => {subType => "switch.0A"}},
  "D2.03.10" => {attr => {subType => "windowHandle.10"}, GPLOT => "EnO_windowHandle:WindowHandle,"},
  "D2.05.00" => {attr => {subType => "blindsCtrl.00", webCmd => "opens:stop:closes:position"}, GPLOT => "EnO_position4angle4:Position/AnglePos,"},
  "D2.05.01" => {attr => {subType => "blindsCtrl.01", webCmd => "opens:stop:closes:position"}},
  "D2.05.02" => {attr => {subType => "blindsCtrl.00", defaultChannel => 1, webCmd => "opens:stop:closes:position"}, GPLOT => "EnO_position4angle4:Position/AnglePos,"},
  "D2.06.01" => {attr => {subType => "multisensor.01"}, GPLOT => "EnO_temp4humi4:Temp/Humi,EnO_brightness4:Brightness,"},
  "D2.10.00" => {attr => {subType => "roomCtrlPanel.00", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.10.01" => {attr => {subType => "roomCtrlPanel.00", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.10.02" => {attr => {subType => "roomCtrlPanel.00", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.01" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.02" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.03" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.04" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.05" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.06" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.07" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.11.08" => {attr => {subType => "roomCtrlPanel.01", comMode => "biDir", webCmd => "setpointTemp"}, GPLOT => "EnO_D2-10-xx:Temp/SPT/Humi,"},
  "D2.14.30" => {attr => {subType => "multiFuncSensor.30"}, GPLOT => "EnO_temp4humi4:Temp/Humi,"},
  "D2.15.00" => {attr => {subType => "multiFuncSensor.00"}},
  "D2.20.00" => {attr => {subType => "fanCtrl.00", webCmd => "fanSpeed"}, GPLOT => "EnO_fanSpeed4humi4:FanSpeed/Humi,"},
  "D2.32.00" => {attr => {subType => "currentClamp.00"}, GPLOT => "EnO_D2-32-xx:Current,"},
  "D2.32.01" => {attr => {subType => "currentClamp.01"}, GPLOT => "EnO_D2-32-xx:Current,"},
  "D2.34.00" => {attr => {subType => "heatingActuator.00", defaultChannel => 0}, GPLOT => "EnO_D2-34-xx:setpointTemp/temperature,"},
  "D2.34.01" => {attr => {subType => "heatingActuator.00", defaultChannel => 0}, GPLOT => "EnO_D2-34-xx:setpointTemp/temperature,"},
  "D2.34.02" => {attr => {subType => "heatingActuator.00", defaultChannel => 0}, GPLOT => "EnO_D2-34-xx:setpointTemp/temperature,"},
  "D2.32.02" => {attr => {subType => "currentClamp.02"}, GPLOT => "EnO_D2-32-xx:Current,"},
  "D2.40.00" => {attr => {subType => "ledCtrlState.00"}, GPLOT => "EnO_dim4:Dim,"},
  "D2.40.01" => {attr => {subType => "ledCtrlState.01"}, GPLOT => "EnO_dim4RGB:DimRGB,"},
  "D2.50.00" => {attr => {subType => "heatRecovery.00", webCmd => "ventilation"}, GPLOT => "EnO_D2-50-xx:Temp/AirQuality,EnO_D2-50-xx_2:AirFlow/FanSpeed,"},
  "D2.50.01" => {attr => {subType => "heatRecovery.00", webCmd => "ventilation"}, GPLOT => "EnO_D2-50-xx:Temp/AirQuality,EnO_D2-50-xx_2:AirFlow/FanSpeed,"},
  "D2.50.10" => {attr => {subType => "heatRecovery.00", webCmd => "ventilation"}, GPLOT => "EnO_D2-50-xx:Temp/AirQuality,EnO_D2-50-xx_2:AirFlow/FanSpeed,"},
  "D2.50.11" => {attr => {subType => "heatRecovery.00", webCmd => "ventilation"}, GPLOT => "EnO_D2-50-xx:Temp/AirQuality,EnO_D2-50-xx_2:AirFlow/FanSpeed,"},
  "D2.A0.01" => {attr => {subType => "valveCtrl.00", defaultChannel => 0, webCmd => "opens:closes"}, GPLOT => "EnO_valveCtrl:Valve,"},
  "D2.B0.51" => {attr => {subType => "liquidLeakage.51"}, GPLOT => "EnO_liquidLeakage:LiquidLeakage,"},
  "D5.00.01" => {attr => {subType => "contact", manufID => "7FF"}, GPLOT => "EnO_contact:Contact,"},
  "F6.01.01" => {attr => {subType => "switch", sensorMode => "pushbutton"}},
  "F6.02.01" => {attr => {subType => "switch"}},
  "F6.02.02" => {attr => {subType => "switch"}},
  "F6.02.03" => {attr => {subType => "switch"}},
 #"F6.02.04" => {attr => {subType => "switch.04"}},
  "F6.03.01" => {attr => {subType => "switch"}},
  "F6.03.02" => {attr => {subType => "switch"}},
  "F6.04.01" => {attr => {subType => "keycard"}, GPLOT => "EnO_keycard:Keycard,"},
 #"F6.04.02" => {attr => {subType => "keycard.02"}, GPLOT => "EnO_keycard:Keycard,"},
  "F6.05.00" => {attr => {subType => "windSpeed.00"}},
  "F6.05.01" => {attr => {subType => "liquidLeakage"}, GPLOT => "EnO_liquidLeakage:LiquidLeakage,"},
  "F6.05.02" => {attr => {subType => "smokeDetector.02"}},
  "F6.10.00" => {attr => {subType => "windowHandle"}, GPLOT => "EnO_windowHandle:WindowHandle,"},
 #"F6.10.01" => {attr => {subType => "windowHandle.01"}, GPLOT => "EnO_windowHandle:WindowHandle,"},
  "F6.3F.7F" => {attr => {subType => "switch.7F"}},
 # special profiles
  "G5.07.01" => {attr => {subType => "occupSensor.01", eep => "A5-07-01", manufID => "00D", model => 'tracker'}, GPLOT => "EnO_motion:Motion,EnO_voltage4current4:Voltage/Current,"},
  "G5.10.12" => {attr => {subType => "roomSensorControl.01", eep => "A5-10-12", manufID => "00D", scaleMax => 40, scaleMin => 0, scaleDecimals => 1}, GPLOT => "EnO_temp4humi6:Temp/Humi,"},
  "G5.38.08" => {attr => {subType => "gateway", eep => "A5-38-08", gwCmd => "dimming", manufID => "00D", webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,"},
  "H5.38.08" => {attr => {subType => "gateway", comMode => "confirm", eep => "A5-38-08", gwCmd => "dimming", manufID => "00D", model => "Eltako_TF", teachMethod => "confirm", webCmd => "on:off:dim"}, GPLOT => "EnO_dim4:Dim,"},
  "G5.3F.7F" => {attr => {subType => "manufProfile", eep => "A5-3F-7F", manufID => "00D", webCmd => "opens:stop:closes"}},
  "H5.3F.7F" => {attr => {subType => "manufProfile", comMode => "confirm", eep => "A5-3F-7F", manufID => "00D", model => "Eltako_TF", sensorMode => 'pushbutton', settingAccuracy => "high", teachMethod => "confirm", webCmd => "opens:stop:closes"}},
  "M5.38.08" => {attr => {subType => "gateway", eep => "A5-38-08", gwCmd => "switching", manufID => "00D", webCmd => "on:off"}},
  "N5.38.08" => {attr => {subType => "gateway", comMode => "confirm", eep => "A5-38-08", gwCmd => "switching", manufID => "00D", model => "Eltako_TF", teachMethod => "confirm", webCmd => "on:off"}},
  "G5.ZZ.ZZ" => {attr => {subType => "PM101", manufID => "005"}, GPLOT => "EnO_motion:Motion,EnO_brightness4:Brightness,"},
  "L6.02.01" => {attr => {subType => "smokeDetector.02", eep => "F6-05-02", manufID => "00D"}},
  "ZZ.13.03" => {attr => {subType => "environmentApp", eep => "A5-13-03", devMode => "master", manufID => "7FF"}},
  "ZZ.13.04" => {attr => {subType => "environmentApp", eep => "A5-13-04", devMode => "master", manufID => "7FF"}},
  "ZZ.ZZ.ZZ" => {attr => {subType => "raw"}}
);

my %EnO_extendedRemoteFunctionCode = (
  0x210 => "remoteLinkTableInfo", # get
  0x211 => "remoteLinkTable",     # get
  0x212 => "remoteLinkTable",     # set
  0x213 => "remoteLinkTableGP",   # get
  0x214 => "remoteLinkTableGP",   # set
  0x220 => "remoteLearnMode",     # set
  0x221 => "remoteTeach",         # set
  0x224 => "remoteReset",         # set
  0x225 => "remoteRLT",           # set
  0x226 => "remoteApplyChanges",  # set
  0x227 => "remoteProductID",     # get
  0x230 => "remoteDevCfg",        # get
  0x231 => "remoteDevCfg",        # set
  0x232 => "remoteLinkCfg",       # get
  0x233 => "remoteLinkCfg",       # set
  0x240 => "remoteAck",           # parse
  0x250 => "remoteRepeater",      # get
  0x251 => "remoteRepeater",      # set
  0x252 => "remoteRepeaterFilter" # set
);

my %EnO_models = (
  "Eltako_FAE14" => {attr => {manufID => "00D"}},
  "Eltako_FHK14" => {attr => {manufID => "00D"}},
  "Eltako_FHK61" => {attr => {manufID => "00D"}},
  "Eltako_FSA12" => {attr => {manufID => "00D"}},
  "Eltako_FSB14" => {attr => {manufID => "00D"}},
  "Eltako_FSB61" => {attr => {manufID => "00D"}},
  "Eltako_FSB70" => {attr => {manufID => "00D"}},
  "Eltako_FSB_ACK" => {attr => {manufID => "00D"}},
  "Eltako_FSM12" => {attr => {manufID => "00D"}},
  "Eltako_FSM61" => {attr => {manufID => "00D"}},
  "Eltako_FT55" => {attr => {manufID => "00D"}},
  "Eltako_FTS12" => {attr => {manufID => "00D"}},
  "Eltako_TF"=> {attr => {manufID => "00D"}},
  "Eltako_TF_RWB"=> {attr => {manufID => "00D"}},
  "Holter_OEM" => {attr => {pidCtrl => "off"}},
  "Micropelt_MVA004" => {attr => {remoteCode => "FFFFFFFE", remoteEEP => "A5-20-01", remoteID => "getNextID", remoteManagement => "manager"}, xml => {productID => "0x004900000000", xmlDescrLocation => "/FHEM/lib/EnO_ReCom_Device_Descr.xml"}},
  other => {},
  tracker => {}
);

my @EnO_defaultChannel = ("all", "input", 0..29);

my %wakeUpCycle = (
  'auto' => 0x40,
      10 => 0,
      60 => 1,
      90 => 2,
     120 => 3,
     150 => 4,
     180 => 5,
     210 => 6,
     240 => 7,
     270 => 8,
     300 => 9,
     330 => 10,
     360 => 11,
     390 => 12,
     420 => 13,
     450 => 14,
     480 => 15,
     510 => 16,
     540 => 17,
     570 => 18,
     600 => 19,
     630 => 20,
     660 => 21,
     690 => 22,
     720 => 23,
     750 => 24,
     780 => 25,
     810 => 26,
     840 => 27,
     870 => 28,
     900 => 29,
     930 => 30,
     960 => 31,
     990 => 32,
    1020 => 33,
    1050 => 34,
    1080 => 35,
    1110 => 36,
    1140 => 37,
    1170 => 38,
    1200 => 39,
    1230 => 40,
    1260 => 41,
    1290 => 42,
    1320 => 43,
    1350 => 44,
    1380 => 45,
    1410 => 46,
    1440 => 47,
    1470 => 48,
    1500 => 49,
    1800 => 0x45,
    3600 => 0x46,
    7200 => 0x47,
   10800 => 50,
   21600 => 51,
   28800 => 0x48,
   32400 => 52,
   43200 => 53,
   54000 => 54,
   64800 => 55,
   75600 => 56,
   86400 => 57,
   97200 => 58,
  108000 => 59,
  118800 => 60,
  129600 => 61,
  140400 => 62,
  151200 => 63,
);

my %wakeUpCycleInv = (
   0 => 10,
   1 => 60,
   2 => 90,
   3 => 120,
   4 => 150,
   5 => 180,
   6 => 210,
   7 => 240,
   8 => 270,
   9 => 300,
  10 => 330,
  11 => 360,
  12 => 390,
  13 => 420,
  14 => 450,
  15 => 480,
  16 => 510,
  17 => 540,
  18 => 570,
  19 => 600,
  20 => 630,
  21 => 660,
  22 => 690,
  23 => 720,
  24 => 750,
  25 => 780,
  26 => 810,
  27 => 840,
  28 => 870,
  29 => 900,
  30 => 930,
  31 => 960,
  32 => 990,
  33 => 1020,
  34 => 1050,
  35 => 1080,
  36 => 1110,
  37 => 1140,
  38 => 1170,
  39 => 1200,
  40 => 1230,
  41 => 1260,
  42 => 1290,
  43 => 1320,
  44 => 1350,
  45 => 1380,
  46 => 1410,
  47 => 1440,
  48 => 1470,
  49 => 1500,
  50 => 10800,
  51 => 21600,
  52 => 32400,
  53 => 43200,
  54 => 54000,
  55 => 64800,
  56 => 75600,
  57 => 86400,
  58 => 97200,
  59 => 108000,
  60 => 118800,
  61 => 129600,
  62 => 140400,
  63 => 151200,
);

my @EnO_resolution = (1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32);

my @EnO_scaling = (0, 1, 10, 100, 1000, 10000, 100000, 1e6, 1e7, 0.1, 0.01, 0.001, 1e-6, 1e-9);

my %EnO_gpValueEnum = (
  1 => {name => "multipurpose", "02D" => {"00000009" => {0 => {name => "volume",
                                                               unit => "l"},
                                                         1 => {name => "interval",
                                                               unit => "h"},
                                                         2 => {name => "battery",
                                                               unit => "%"},
                                                         4 => {name => "status",
                                                               enum => {0 => "in_use", 1 => "not_used", 2 => "protection", 3 => "off"},
                                                               enumInv => {"in_use" => 0, "not_used" => 1, "protection" => 2, "off" => 3}}}}},
  2 => {name => "buildingMode", enum => {0 => "in_use", 1 => "not_used", 2 => "protection"},
                                enumInv => {"in_use" => 0, "not_used" => 1, "protection" => 2}},
  3 => {name => "occupanyMode", enum => {0 => "occupied", 1 => "standby", 2 => "not_occupied"},
                                enumInv => {"occupied" => 0,"standby" => 1,"not_occupied" => 2}},
  4 => {name => "hvacMode", enum => {0 => "auto", 1 => "comfort", 2 => "standby", 3 => "economy", 4 => "building_protection"},
                            enumInv => {"auto" => 0, "comfort" => 1, "standby" => 2, "economy" => 3, "building_protection" => 4}},
  5 => {name => "changeoverMode", enum => {0 => "auto", 1 => "cooling", 2 => "heating"},
                                  enumInv => {"auto" => 0,"cooling" => 1,"heating" => 2}},
  6 => {name => "time"},
  7 => {name => "battery", unit => "%"},
);

my %EnO_gpValueFlag = (
  1 => {name => "auto/man", flag => {0 => "man", 1 => "auto"},
                            flagInv => {"man" => 0,"auto" => 1}},
  2 => {name => "buttonPressed", flag => {0 => "not_pressed", 1 => "pressed"},
                                 flagInv => {"not_pressed" => 0,"pressed" => 1}},
  3 => {name => "buttonChanged", flag => {0 => "no_change", 1 => "change"},
                                 flagInv => {"no_change" => 0,"change" => 1}},
  4 => {name => "day/night", flag => {0 => "night", 1 => "day"},
                             flagInv => {"night" => 0,"day" => 1}},
  5 => {name => "down", flag => {0 => "no_change", 1 => "down"},
                        flagInv => {"no_change" => 0,"down" => 1}},
  6 => {name => "generalAlarm", flag => {0 => "manual", 1 => "alarm"},
                                flagInv => {"manual" => 0,"alarm" => 1}},
  7 => {name => "heat/cool", flag => {0 => "cool", 1 => "heat"},
                             flagInv => {"cool" => 0,"heat" => 1}},
  8 => {name => "high/low", flag => {0 => "low", 1 => "high"},
                            flagInv => {"low" => 0,"high" => 1}},
  9 => {name => "occupancy", flag => {0 => "unoccupied", 1 => "occupied"},
                             flagInv => {"unoccupied" => 0,"occupied" => 1}},
  10 => {name => "on/off", flag => {0 => "off", 1 => "on"},
                           flagInv => {"off" => 0,"on" => 1}},
  11 => {name => "open/closed", flag => {0 => "closed", 1 => "open"},
                                flagInv => {"closed" => 0,"open" => 1}},
  12 => {name => "powerAlarm", flag => {0 => "no_change", 1 => "alarm"},
                               flagInv => {"no_change" => 0,"alarm" => 1}},
  13 => {name => "start/stop", flag => {0 => "stop", 1 => "start"},
                               flagInv => {"stop" => 0,"start" => 1}},
  14 => {name => "up", flag => {0 => "no_change", 1 => "up"},
                       flagInv => {"no_change" => 0,"up" => 1}},
);

my %EnO_gpValueData = (
  1 => {name => "acceleration", unit => "m/s2"},
  2 => {name => "angle", unit => "deg"},
  3 => {name => "angular_velocity", unit => "rad/s"},
  4 => {name => "area", unit => "m&sup2;"},
  5 => {name => "concentration", unit => "ppm"},
  6 => {name => "current", unit => "A"},
  7 => {name => "distance", unit => "m"},
  8 => {name => "electric_field_strength", unit => "V/m"},
  9 => {name => "energy", unit => "J"},
  10 => {name => "number", unit => "N/A"},
  11 => {name => "force", unit => "N"},
  12 => {name => "frequency", unit => "Hz"},
  13 => {name => "heat_flux_density", unit => "W/m2"},
  14 => {name => "impulse", unit => "Ns"},
  15 => {name => "luminance_intensity", unit => "lux"},
  16 => {name => "magnetic_field_strength", unit => "A/m"},
  17 => {name => "mass", unit => "kg"},
  18 => {name => "mass_density", unit => "kg/m2"},
  19 => {name => "mass_flow", unit => "kg/s"},
  20 => {name => "power", unit => "W"},
  21 => {name => "pressure", unit => "Pa"},
  22 => {name => "relative_humidity", unit => "%"},
  23 => {name => "resistance", unit => "Ohm"},
  24 => {name => "temperature", unit => "C"},
  25 => {name => "time", unit => "s"},
  26 => {name => "torque", unit => "Nm"},
  27 => {name => "velocity", unit => "m/s"},
  28 => {name => "voltage", unit => "V"},
  29 => {name => "volume", unit => "m3"},
  30 => {name => "volumetric_flow", unit => "m3/s"},
  31 => {name => "sound_pressure_level", unit => "dB"},
  32 => {name => "correlated_color_temperature", unit => "K"},
);

# Initialize
sub
EnOcean_Initialize($)
{
  my ($hash) = @_;
  my %subTypeList;
  my @subTypeList;
  foreach my $eep (keys %EnO_eepConfig){
    push @subTypeList, $EnO_eepConfig{$eep}{attr}{subType};
  }
  my $subTypeList = join(",", sort grep { !$subTypeList{$_}++ } @subTypeList);

  $hash->{AutoCreate} = {"EnO.*" => {ATTR => "creator:autocreate", FILTER => "%NAME"}};
  $hash->{noAutocreatedFilelog} = 1;
  $hash->{Match} = "^EnOcean:";
  $hash->{DefFn} = "EnOcean_Define";
  $hash->{DeleteFn} = "EnOcean_Delete";
  $hash->{UndefFn} = "EnOcean_Undef";
  $hash->{ParseFn} = "EnOcean_Parse";
  $hash->{SetFn} = "EnOcean_Set";
 #$hash->{StateFn} = "EnOcean_State";
  $hash->{GetFn} = "EnOcean_Get";
  $hash->{NotifyFn} = "EnOcean_Notify";
  $hash->{AttrFn} = "EnOcean_Attr";
  $hash->{AttrList} = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                      "showtime:1,0 " .
                      "actualTemp angleMax:slider,-180,20,180 alarmAction " .
                      "angleMin:slider,-180,20,180 " .
                      "angleTime setCmdTrigger:man,refDev blockUnknownMSC:no,yes blockMotion:no,yes " .
                      "blockTemp:no,yes blockDisplay:no,yes blockDateTime:no,yes " .
                      "blockTimeProgram:no,yes blockOccupancy:no,yes blockSetpointTemp:no,yes " .
                      "blockFanSpeed:no,yes blockKey:no,yes " .
                      "brightnessDayNight brightnessDayNightCtrl:custom,sensor brightnessDayNightDelay " .
                      "brightnessSunny brightnessSunnySouth brightnessSunnyWest brightnessSunnyEast " .
                      "brightnessSunnyDelay brightnessSunnySouthDelay brightnessSunnyWestDelay brightnessSunnyEastDelay " .
                      "calAtEndpoints:no,yes comMode:confirm,biDir,uniDir creator:autocreate,manual " .
                      "daylightSavingTime:supported,not_supported dataEnc:VAES,AES-CBC " .
                      "defaultChannel:" . join(",", @EnO_defaultChannel) . " " .
                      "demandRespAction demandRespRefDev demandRespMax:A0,AI,B0,BI,C0,CI,D0,DI ".
                      "demandRespMin:A0,AI,B0,BI,C0,CI,D0,DI demandRespRandomTime " .
                      "demandRespThreshold:slider,0,1,15 demandRespTimeoutLevel:max,last destinationID " .
                      "devChannel devMode:master,slave devUpdate:off,auto,demand,polling,interrupt " .
                      "dimMax dimMin dimValueOn disable:0,1 disabledForIntervals " .
                      "displayContent:default,humidity,off,setpointTemp,tempertureExtern,temperatureIntern,time,no_change " .
                      "displayOrientation:0,90,180,270 " .
                      "eep gpDef gwCmd:" . join(",", sort @EnO_gwCmd) . " humitity humidityRefDev " .
                      "keyRcv keySnd macAlgo:no,3,4 measurementCtrl:disable,enable measurementTypeSelect:feed,room " .
                      "manufID:" . join(",", sort keys %EnO_manuf) . " " .
                      "model:" . join(",", sort keys %EnO_models) . " " .
                      "observe:on,off observeCmdRepetition:1,2,3,4,5 observeErrorAction observeInterval observeLogic:and,or " .
                      #observeCmds observeExeptions
                      "observeRefDev pidActorErrorAction:errorPos,freeze pidActorCallBeforeSetting pidActorErrorPos " .
                      "pidActorLimitLower pidActorLimitUpper pidCtrl:on,off pidDeltaTreshold pidFactor_D pidFactor_I " .
                      "pidFactor_P pidIPortionCallBeforeSetting pidSensorTimeout " .
                      "pollInterval postmasterID productID rampTime rcvRespAction ".
                      "releasedChannel:A,B,C,D,I,0,auto repeatingAllowed:yes,no remoteCode remoteEEP remoteID remoteManufID " .
                      "remoteManagement:client,manager,off rlcAlgo:no,2++,3++ rlcRcv rlcSnd rlcTX:true,false " .
                      "reposition:directly,opens,closes rltRepeat:16,32,64,128,256 rltType:1BS,4BS " .
                      "scaleDecimals:0,1,2,3,4,5,6,7,8,9 scaleMax scaleMin secMode:rcv,snd,bidir " .
                      "secLevel:encapsulation,encryption,off sendDevStatus:no,yes sendTimePeriodic sensorMode:switch,pushbutton " .
                      "serviceOn:no,yes settingAccuracy:high,low setpointRefDev setpointSummerMode:slider,0,5,100 " .
                      "signal:off,on signOfLife:off,on signOfLifeInterval setpointTempRefDev shutTime shutTimeCloses subDef " .
                      "subDef0 subDefI subDefA subDefB subDefC subDefD subDefH subDefW " .
                      "subType:$subTypeList subTypeSet:$subTypeList subTypeReading:$subTypeList " .
                      "summerMode:off,on switchMode:switch,pushbutton " .
                      "switchHysteresis switchType:direction,universal,channel,central " .
                      "teachMethod:1BS,4BS,confirm,GP,RPS,smartAck,STE,UTE temperatureRefDev " .
                      "temperatureScale:C,F,default,no_change timeNotation:12,24,default,no_change " .
                      "timeProgram1 timeProgram2 timeProgram3 timeProgram4 trackerWakeUpCycle:10,20,30,40,60,120,180,240,3600,86400 " .
                      "updateGlobalAttr:no,yes updateState:default,yes,no " .
                      "uteResponseRequest:yes,no " .
                      "wakeUpCycle:" . join(",", sort keys %wakeUpCycle) . " windowOpenCtrl:disable,enable " .
                      "windSpeedWindy windSpeedStormy windSpeedWindyDelay windSpeedStormyDelay " .
                      $readingFnAttributes;

  for (my $i = 0; $i < @EnO_ptm200btn; $i++) {
    $EnO_ptm200btn{$EnO_ptm200btn[$i]} = "$i:30";
  }
  $EnO_ptm200btn{released} = "0:20";
  if ($cryptFunc == 1){
    Log3 undef, 2, "EnOcean Cryptographic functions available.";
  } else {
    Log3 undef, 2, "EnOcean Cryptographic functions are not available.";
  }
  if ($xmlFunc == 1){
    Log3 undef, 2, "EnOcean XML functions available.";
  } else {
    Log3 undef, 2, "EnOcean XML functions are not available.";
  }
  #$hash->{NotifyOrderPrefix} = "45-";
  return undef;
}

# Define
sub EnOcean_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  my ($autocreateFilelog, $autocreateHash, $autocreateName, $autocreateDeviceRoom, $autocreateWeblinkRoom) =
     ('./log/' . $name . '-%Y.log', undef, 'autocreate', 'EnOcean', 'Plots');
  my ($cmd, $eep, $ret);
  my $filelogName = "FileLog_$name";
  $def = "00000000";
  if(@a > 2 && @a < 5) {
    # find autocreate device
    while (($autocreateName, $autocreateHash) = each(%defs)) {
      last if ($defs{$autocreateName}{TYPE} eq "autocreate");
    }
    $autocreateDeviceRoom = AttrVal($autocreateName, "device_room", $autocreateDeviceRoom) if (defined $autocreateName);
    $autocreateDeviceRoom = 'EnOcean' if ($autocreateDeviceRoom eq '%TYPE');
    $autocreateDeviceRoom = $name if ($autocreateDeviceRoom eq '%NAME');
    $autocreateDeviceRoom = AttrVal($name, "room", $autocreateDeviceRoom);
    if ($init_done) {
      Log3 $name, 2, "EnOcean define " . join(' ', @a);
      if (!defined(AttrVal($autocreateName, "disable", undef)) && !exists($defs{$filelogName})) {
        # create FileLog
        $autocreateFilelog = $attr{$autocreateName}{filelog} if (exists $attr{$autocreateName}{filelog});
        $autocreateFilelog =~ s/%NAME/$name/g;
        $cmd = "$filelogName FileLog $autocreateFilelog $name";
        Log3 $filelogName, 2, "EnOcean define $cmd";
        $ret = CommandDefine(undef, $cmd);
        if($ret) {
          Log3 $filelogName, 2, "EnOcean ERROR: $ret";
        } else {
          $attr{$filelogName}{room} = $autocreateDeviceRoom;
          $attr{$filelogName}{logtype} = 'text';
        }
      }
    }

    if ($a[2] eq "getNextID") {
      AssignIoPort($hash) if (!exists $hash->{IODev});
      if (exists $hash->{OLDDEF}) {
        delete $modules{EnOcean}{defptr}{$hash->{OLDDEF}};
      }
      $hash->{DEF} = $def;
      $def = EnOcean_CheckSenderID("getNextID", $hash->{IODev}{NAME}, "00000000");
      $hash->{DEF} = $def;
      $modules{EnOcean}{defptr}{$def} = $hash;
      $attr{$name}{manufID} = "7FF" if (!exists $attr{$name}{manufID});
      $attr{$name}{room} = $autocreateDeviceRoom;
      $attr{$name}{subType} = "raw" if (!exists $attr{$name}{subType});

    } elsif ($a[2] =~ m/^[A-Fa-f0-9]{8}$/i) {
      # DestinationID
      $def = uc($a[2]);
      $hash->{DEF} = $def;
      if (defined($a[3]) && $a[3] =~ m/^([A-Za-z0-9]{2})-([A-Za-z0-9]{2})-([A-Za-z0-9]{2})$/i) {
        # EEP
        my ($rorg, $func, $type) = (uc($1), uc($2), uc($3));
        $rorg = "F6" if ($rorg eq "05");
        $rorg = "D5" if ($rorg eq "06");
        $rorg = "A5" if ($rorg eq "07");
        $eep = "$rorg.$func.$type";
        if (exists $EnO_eepConfig{$eep}) {
          if ($eep eq 'A5.3F.00') {
            my ($rltHash, $rltName);
            foreach my $dev (keys %defs) {
              next if ($defs{$dev}{TYPE} ne 'EnOcean');
              next if (!exists($attr{$dev}{subType}));
              next if ($attr{$dev}{subType} ne 'radioLinkTest');
              $rltHash = $defs{$dev};
              $rltName = $rltHash->{NAME};
              last;
            }
            return "Radio Link Test device already defined, use $rltName" if ($rltHash);
          }
          AssignIoPort($hash) if (!exists $hash->{IODev});
          if (exists $hash->{OLDDEF}) {
            delete $modules{EnOcean}{defptr}{$hash->{OLDDEF}};
          }
          $modules{EnOcean}{defptr}{$def} = $hash;
          if (exists($attr{$name}{eep}) && $attr{$name}{eep} ne "$rorg-$func-$type") {
            delete $attr{$name};
            $attr{$filelogName}{logtype} = $EnO_eepConfig{$eep}{GPLOT} . 'text'
              if (exists $attr{$filelogName}{logtype});
            # delete SVG devices
            my ($weblinkName, $weblinkHash);
            while (($weblinkName, $weblinkHash) = each(%defs)) {
              if ($weblinkName =~ /^SVG_$name.*/) {
                CommandDelete(undef, $weblinkName);
                Log3 $hash->{NAME}, 2, "EnOcean $weblinkName deleted";
              }
            }
          }
          $attr{$name}{eep} = "$rorg-$func-$type";
          $attr{$name}{manufID} = "7FF" if (!exists $attr{$name}{manufID});
          $attr{$name}{room} = $autocreateDeviceRoom;
          foreach my $attrCntr (keys %{$EnO_eepConfig{$eep}{attr}}) {
            if ($attrCntr eq "subDef") {
              if (!exists $attr{$name}{$attrCntr}) {
                $attr{$name}{$attrCntr} = EnOcean_CheckSenderID($EnO_eepConfig{$eep}{attr}{$attrCntr}, $hash->{IODev}{NAME}, "00000000");
              }
            } else {
              $attr{$name}{$attrCntr} = $EnO_eepConfig{$eep}{attr}{$attrCntr};
            }
          }
          EnOcean_CreateSVG(undef, $hash, $a[3]);
        } else {
          return "EEP $rorg-$func-$type not supported";
        }
      } elsif (defined($a[3]) && $a[3] =~ m/^EnOcean:.*/) {
        # autocreate: parse received device telegram
        AssignIoPort($hash) if (!exists $hash->{IODev});
        $modules{EnOcean}{defptr}{$def} = $hash;
        my @msg = split(':', $a[3]);
        my $packetType = hex $msg[1];

        if ($packetType == 1) {
          my ($data, $rorg, $status);
          #EnOcean:PacketType:RORG:MessageData:SourceID:Status:OptionalData
          (undef, undef, $rorg, $data, undef, $status, undef) = @msg;
          $attr{$name}{subType} = $EnO_rorgname{$rorg};
          if ($attr{$name}{subType} eq "switch") {
            my $nu = (hex($status) & 0x10) >> 4;
            my $t21 = (hex($status) & 0x20) >> 5;
            $attr{$name}{manufID} = "7FF";
            if ($t21 && $nu) {
              $attr{$name}{eep} = "F6-02-01";
              readingsSingleUpdate($hash, "teach", "RPS teach-in accepted EEP F6-02-01 Manufacturer: no ID", 1);
              $attr{$name}{teachMethod} = 'RPS';
              Log3 $name, 2, "EnOcean $name teach-in EEP F6-02-01 Manufacturer: no ID";
            } elsif (!$t21 && $nu) {
              $attr{$name}{eep} = "F6-03-01";
              readingsSingleUpdate($hash, "teach", "RPS teach-in accepted EEP F6-03-01 Manufacturer: no ID", 1);
              $attr{$name}{teachMethod} = 'RPS';
              Log3 $name, 2, "EnOcean $name teach-in EEP F6-03-01 Manufacturer: no ID";
            } elsif ($t21 && !$nu) {
              $attr{$name}{subType} = "windowHandle";
              $attr{$name}{eep} = "F6-10-00";
              readingsSingleUpdate($hash, "teach", "RPS teach-in accepted EEP F6-10-00 Manufacturer: no ID", 1);
              $attr{$name}{teachMethod} = 'RPS';
              Log3 $name, 2, "EnOcean $name teach-in EEP F6-10-00 Manufacturer: no ID";
            }
          } elsif ($attr{$name}{subType} eq "contact" && hex($data) & 8) {
            $attr{$name}{eep} = "D5-00-01";
            $attr{$name}{manufID} = "7FF";
            readingsSingleUpdate($hash, "teach", "1BS teach-in accepted EEP D5-00-01 Manufacturer: no ID", 1);
            $attr{$name}{teachMethod} = '1BS';
            Log3 $name, 2, "EnOcean $name teach-in EEP D5-00-01 Manufacturer: no ID";
          } elsif ($attr{$name}{subType} eq "4BS" && hex(substr($data, 6, 2)) & 8) {
            $hash->{helper}{teachInWait} = "4BS";
            readingsSingleUpdate($hash, "teach", "4BS teach-in is missing", 1);
            Log3 $name, 2, "EnOcean $name 4BS teach-in is missing";
          } elsif ($attr{$name}{subType} eq "UTE") {
            $hash->{helper}{teachInWait} = "UTE";
          } elsif ($attr{$name}{subType} eq "VLD") {
            $hash->{helper}{teachInWait} = "UTE";
            readingsSingleUpdate($hash, "teach", "UTE teach-in is missing", 1);
            Log3 $name, 2, "EnOcean $name UTE teach-in is missing";
          } elsif ($attr{$name}{subType} eq "MSC") {
            readingsSingleUpdate($hash, "teach", "MSC not supported", 1);
            Log3 $name, 2, "EnOcean $name MSC not supported";
          } elsif ($attr{$name}{subType} =~ m/^SEC|ENC$/) {
            $hash->{helper}{teachInWait} = "STE";
            readingsSingleUpdate($hash, "teach", "STE teach-in is missing", 1);
            Log3 $name, 2, "EnOcean $name STE teach-in is missing";
          } elsif ($attr{$name}{subType} =~ m/^GPCD|GPSD$/) {
            $hash->{helper}{teachInWait} = "GPTI";
            readingsSingleUpdate($hash, "teach", "GP teach-in is missing", 1);
            Log3 $name, 2, "EnOcean $name GP teach-in is missing";
          }

        } elsif ($packetType == 4) {
          $hash->{helper}{smartAckLearnWait} = $name;

        } elsif ($packetType == 7) {
          # remote management
          #EnOcean:PacketType:RORG:MessageData:SourceID:DestinationID:FunctionNumber:ManufacturerID:RSSI:Delay
          if (hex($msg[6]) < 0x600) {
            $attr{$name}{remoteManagement} = 'client';
            # unlock device to send acknowledgment telegram
            $hash->{RemoteClientUnlock} = 1;
            RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlock}) if(exists $hash->{helper}{timer}{RemoteClientUnlock});
            $hash->{helper}{timer}{RemoteClientUnlock} = {hash => $hash, param => 'RemoteClientUnlock'};
            InternalTimer(gettimeofday() + 1, 'EnOcean_cdmClearHashVal', $hash->{helper}{timer}{RemoteClientUnlock}, 0);
          } else {
            $attr{$name}{remoteManagement} = 'manager';
          }
          $attr{$name}{eep} = 'C5-00-00';
          $attr{$name}{manufID} = substr($msg[7], 1);
          $attr{$name}{remoteEEP} = 'C5-00-00';
          $attr{$name}{remoteID} = $msg[4];
          $attr{$name}{remoteManufID} = substr($msg[7], 1);
          $attr{$name}{subType} = 'remote';
          $modules{EnOcean}{defptr}{$msg[4]} = $hash;
        }

        EnOcean_Parse($hash, $a[3]);
        if (exists $attr{$name}{eep}) {
          $attr{$name}{eep} =~ m/^([A-Za-z0-9]{2})-([A-Za-z0-9]{2})-([A-Za-z0-9]{2})$/i;
          $eep = uc("$1.$2.$3");
          if (exists($attr{$filelogName}{logtype}) && exists($EnO_eepConfig{$eep}{GPLOT})) {
            $attr{$filelogName}{logtype} = $EnO_eepConfig{$eep}{GPLOT} . 'text';
            EnOcean_CreateSVG(undef, $hash, undef);
          }
        }

      } else {
        # no device infos
        AssignIoPort($hash) if (!exists $hash->{IODev});
        # assign defptr
        if (exists $hash->{OLDDEF}) {
          delete $modules{EnOcean}{defptr}{$hash->{OLDDEF}};
        }
        $modules{EnOcean}{defptr}{$def} = $hash;
        $attr{$name}{manufID} = "7FF" if (!exists $attr{$name}{manufID});
        $attr{$name}{room} = $autocreateDeviceRoom;
        $attr{$name}{subType} = "raw" if (!exists $attr{$name}{subType});
      }

    } elsif ($a[2] =~ m/^([A-Za-z0-9]{2})-([A-Za-z0-9]{2})-([A-Za-z0-9]{2})$/i) {
      # EEP
      my ($rorg, $func, $type) = (uc($1), uc($2), uc($3));
      $rorg = "F6" if ($rorg eq "05");
      $rorg = "D5" if ($rorg eq "06");
      $rorg = "A5" if ($rorg eq "07");
      $eep = "$rorg.$func.$type";
      if (exists $EnO_eepConfig{$eep}) {
        if ($eep eq 'A5.3F.00') {
          # radio link test device
          my ($rltHash, $rltName);
          foreach my $dev (keys %defs) {
            next if ($defs{$dev}{TYPE} ne 'EnOcean');
            next if (!exists($attr{$dev}{subType}));
            next if ($attr{$dev}{subType} ne 'radioLinkTest');
            $rltHash = $defs{$dev};
            $rltName = $rltHash->{NAME};
            last;
          }
          return "Radio Link Test device already defined, use $rltName" if ($rltHash);
        }

        AssignIoPort($hash) if (!exists $hash->{IODev});
        if (exists($hash->{OLDDEF}) && $hash->{OLDDEF} =~ m/^[A-Fa-f0-9]{8}$/i) {
          delete $modules{EnOcean}{defptr}{$hash->{OLDDEF}};
          if ($hash->{DEF} =~ m/^([A-Za-z0-9]{2})-([A-Za-z0-9]{2})-([A-Za-z0-9]{2})$/i) {
            $def = $hash->{OLDDEF};
            $hash->{DEF} = $hash->{OLDDEF};
          }
        } else {
          $hash->{DEF} = $def;
          if ($eep eq 'A5.3F.00') {
            $attr{$name}{subDef} = EnOcean_CheckSenderID("getNextID", $hash->{IODev}{NAME}, "00000000");
          } elsif ($eep eq 'C5.00.00') {
            # remote management

          } else {
            $def = EnOcean_CheckSenderID("getNextID", $hash->{IODev}{NAME}, "00000000");
            $hash->{DEF} = $def;
          }
        }
        $modules{EnOcean}{defptr}{$def} = $hash;
        if (exists($attr{$name}{eep}) && $attr{$name}{eep} ne "$rorg-$func-$type") {
          delete $attr{$name};
          if (exists $attr{$filelogName}{logtype}) {
            if (exists$EnO_eepConfig{$eep}{GPLOT}) {
              $attr{$filelogName}{logtype} = $EnO_eepConfig{$eep}{GPLOT} . 'text';
            } else {
              $attr{$filelogName}{logtype} = 'text';
            }
          }
        }
        $attr{$name}{eep} = "$rorg-$func-$type";
        $attr{$name}{manufID} = "7FF" if (!exists $attr{$name}{manufID});
        $attr{$name}{room} = $autocreateDeviceRoom;
        foreach my $attrCntr (keys %{$EnO_eepConfig{$eep}{attr}}) {
          if ($attrCntr ne "subDef") {
            $attr{$name}{$attrCntr} = $EnO_eepConfig{$eep}{attr}{$attrCntr};
          }
        }
        EnOcean_CreateSVG('del', $hash, $a[2]);
      } else {
        return "EEP $rorg-$func-$type not supported";
      }
    } else {
      return "wrong syntax: define <name> EnOcean <8-digit-hex-code> [<EEP>]|getNextID|<EEP>";
    }

  } else {
    return "wrong syntax: define <name> EnOcean <8-digit-hex-code> [<EEP>]|getNextID|<EEP>";
  }

  # device specific actions
  if (exists($attr{$name}{subType}) && $attr{$name}{subType} =~ m/^hvac\.0(1|4|6)$/) {
    # pid parameter
    @{$hash->{helper}{calcPID}} = (undef, $hash, 'defined', '');
    $hash->{helper}{stopped} = 0;
    #delete $hash->{helper}{adjust};
  }

  # all notifys needed
  #$hash->{NOTIFYDEV} = "global";
  Log3 $name, 5, "EnOcean_define for device $name executed.";
  return undef;
}

# Get
sub EnOcean_Get($@)
{
  my ($hash, @a) = @_;
  return "no get value specified" if (@a < 2);
  my $name = $hash->{NAME};
  if (IsDisabled($name)) {
    Log3 $name, 4, "EnOcean $name get commands disabled.";
    return;
  }
  my $cmdID;
  my $cmdList = "";
  my $data;
  my $destinationID = AttrVal($name, "destinationID", undef);
  if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
    $destinationID = defined(AttrVal($name, "subDef", undef)) ? $hash->{DEF} : "FFFFFFFF";
    $destinationID = "FFFFFFFF" if (uc(AttrVal($name, "subDef", $hash->{DEF})) eq uc($hash->{DEF}));
  } elsif (!defined $destinationID || $destinationID eq "multicast") {
    $destinationID = "FFFFFFFF";
  } elsif ($destinationID eq "unicast") {
    $destinationID = defined(AttrVal($name, "subDef", undef)) ? $hash->{DEF} : "FFFFFFFF";
    $destinationID = "FFFFFFFF" if (uc(AttrVal($name, "subDef", $hash->{DEF})) eq uc($hash->{DEF}));
  } elsif ($destinationID !~ m/^[\dA-Fa-f]{8}$/) {
    return "DestinationID $destinationID wrong, choose <8-digit-hex-code>.";
  }
  $destinationID = uc($destinationID);
  my $eep = uc(AttrVal($name, "eep", "00-00-00"));
  if ($eep =~ m/^([A-Fa-f0-9]{2})-([A-Fa-f0-9]{2})-([A-Fa-f0-9]{2})$/i) {
    $eep = (((hex($1) << 6) | hex($2)) << 7) | hex($3);
  } else {
    $eep = (((hex("FF") << 6) | hex("3F")) << 7) | hex("7F");
  }
  my $manufID = uc(AttrVal($name, "manufID", ""));
  my $model = AttrVal($name, "model", "");
  my $packetType = 1;
  $packetType = 0x0A if (ReadingsVal($hash->{IODev}{NAME}, "mode", "00") eq "01");
  my $remoteID = AttrVal($name, "remoteID", undef);
  my $remoteManufID = uc(AttrVal($name, "remoteManufID", AttrVal($name, "manufID", "")));
  my $rorg;
  my $status = '00';
  my $st = AttrVal($name, "subType", "");
  my $stSet = AttrVal($name, "subTypeSet", undef);
  if (defined $stSet) {$st = $stSet;}
  my $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
  if ($subDef !~ m/^[\dA-F]{8}$/) {return "SenderID $subDef wrong, choose <8-digit-hex-code>.";}
  my $timeNow = TimeNow();
  if (AttrVal($name, "remoteManagement", "off") eq "manager") {
    # Remote Management
    $cmdList .= "remoteDevCfg remoteFunctions:noArg remoteID:noArg remoteLinkCfg remoteLinkTableInfo:noArg remoteLinkTable remoteLinkTableGP remotePing:noArg remoteProductID:noArg remoteRepeater:noArg remoteStatus:noArg ";
  }
  if (AttrVal($name, "signal", "off") eq "on") {
    # signal telegram
    $cmdList .= "signal:energy,revision,RXlevel,harvester ";
  }
  # control get actions
  # $updateState = -1: no get commands available e. g. sensors
  #                 0: execute get commands
  #                 1: execute get commands and and update reading state
  #                 2: execute get commands delayed
  my $updateState = 1;
  #Log3 $name, 5, "EnOcean $name EnOcean_Get command: " . join(" ", @a);
  shift @a;

  for (my $i = 0; $i < @a; $i++) {
    my $cmd = $a[$i];

    if ($cmd eq "remoteID") {
      $cmdID = 4;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "0004%04X%06X", $manufID, ($eep << 3);
      $destinationID = "FFFFFFFF";
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x604}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x604}) if(exists $hash->{helper}{timer}{0x604});
      $hash->{helper}{timer}{0x604} = {hash => $hash, param => 0x604};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x604}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remotePing") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 6;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "0006%04X", $manufID;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x606}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x606}) if(exists $hash->{helper}{timer}{0x606});
      $hash->{helper}{timer}{0x606} = {hash => $hash, param => 0x606};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x606}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteFunctions") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 7;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "0007%04X", $manufID;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x607}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x607}) if(exists $hash->{helper}{timer}{0x607});
      $hash->{helper}{timer}{0x607} = {hash => $hash, param => 0x607};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x607}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteStatus") {
      $cmdID = 8;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "0008%04X", $manufID;
      if (defined $remoteID) {
        $destinationID = $remoteID;
      } else {
        $destinationID = 'F' x 8;
      }
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x608}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x608}) if(exists $hash->{helper}{timer}{0x608});
      $hash->{helper}{timer}{0x608} = {hash => $hash, param => 0x608};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x608}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteLinkTableInfo") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x210;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "%04X%04X", $cmdID, $manufID;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x810}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x810}) if(exists $hash->{helper}{timer}{0x810});
      $hash->{helper}{timer}{0x810} = {hash => $hash, param => 0x810};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x810}, 0);
     Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteLinkTable") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x211;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      my $startRef;
      my $endRef;
      my $direction;
      if (defined($a[1]) && defined($a[2]) && defined($a[3]) && $a[1] =~ m/^in|out$/ && $a[2] =~ m/^[\dA-Fa-f]{2}$/ && $a[3] =~ m/^[\dA-Fa-f]{2}$/) {
        shift(@a);
        $direction = shift(@a);
        $direction = $direction eq 'out' ? '80' : '00';
        $startRef = uc(shift(@a));
        $endRef = uc(shift(@a));
        ($startRef, $endRef) = ($endRef, $startRef) if (hex($startRef) > hex($endRef));
      } else {
        return "Wrong parameter or direction/startRef/endRef not defined.";
      }
      $data = sprintf "%04X%04X%2s%2s%2s", $cmdID, $manufID, $direction, $startRef, $endRef;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x811}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x811}) if(exists $hash->{helper}{timer}{0x811});
      $hash->{helper}{timer}{0x811} = {hash => $hash, param => 0x811};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x811}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteLinkTableGP") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x213;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      my $direction;
      my $index;
      if (defined($a[1]) && defined($a[2]) && $a[1] =~ m/^in|out$/ && $a[2] =~ m/^[\dA-Fa-f]{2}$/) {
        shift(@a);
        $direction = shift(@a);
        $direction = $direction eq 'out' ? '80' : '00';
        $index = uc(shift(@a));
      } else {
        return "Wrong parameter or direction/index not defined.";
      }
      $data = sprintf "%04X%04X%2s%2s", $cmdID, $manufID, $direction, $index;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x813}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x813}) if(exists $hash->{helper}{timer}{0x813});
      $hash->{helper}{timer}{0x813} = {hash => $hash, param => 0x813};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x813}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteProductID") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x227;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "%04X%04X", $cmdID, $manufID;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x827}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x827}) if(exists $hash->{helper}{timer}{0x827});
      $hash->{helper}{timer}{0x827} = {hash => $hash, param => 0x827};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x827}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteDevCfg") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x230;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      my $startRef;
      my $endRef;
      my $paraLen = '00';
      if (defined($a[1]) && defined($a[2]) && $a[1] =~ m/^[\dA-Fa-f]{4}$/ && $a[2] =~ m/^[\dA-Fa-f]{4}$/) {
        shift(@a);
        $startRef = uc(shift(@a));
        $endRef = uc(shift(@a));
        ($startRef, $endRef) = ($endRef, $startRef) if (hex($startRef) > hex($endRef));
        if (defined($a[0]) && $a[0] =~ m/^[\dA-Fa-f]{2}$/) {
          $paraLen = uc(shift(@a));
        }
      } else {
        return "Wrong parameter or startRef/endRef not defined.";
      }
      $data = sprintf "%04X%04X%4s%4s%2s", $cmdID, $manufID, $startRef, $endRef, $paraLen;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x830}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x830}) if(exists $hash->{helper}{timer}{0x830});
      $hash->{helper}{timer}{0x830} = {hash => $hash, param => 0x830};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x830}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteLinkCfg") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x232;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      my $direction;
      my $idx;
      my $startRef;
      my $endRef;
      my $paraLen = '00';
      if (defined($a[1]) && defined($a[2]) && defined($a[3]) && defined($a[4])
          && $a[1] =~ m/^in|out$/ && $a[2] =~ m/^[\dA-Fa-f]{2}$/ && $a[3] =~ m/^[\dA-Fa-f]{4}$/ && $a[4] =~ m/^[\dA-Fa-f]{4}$/) {
        shift(@a);
        $direction = shift(@a);
        $direction = $direction eq 'out' ? '80' : '00';
        $idx = uc(shift(@a));
        $startRef = uc(shift(@a));
        $endRef = uc(shift(@a));
        ($startRef, $endRef) = ($endRef, $startRef) if (hex($startRef) > hex($endRef));
        if (defined($a[0]) && $a[0] =~ m/^[\dA-Fa-f]{2}$/) {
          $paraLen = uc(shift(@a));
        }
      } else {
        return "Wrong parameter or startRef/endRef not defined.";
      }
      $data = sprintf "%04X%04X%2s%2s%4s%4s%2s", $cmdID, $manufID, $direction, $idx, $startRef, $endRef, $paraLen;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x832}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x832}) if(exists $hash->{helper}{timer}{0x832});
      $hash->{helper}{timer}{0x832} = {hash => $hash, param => 0x832};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x832}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "remoteRepeater") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      $cmdID = 0x250;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      shift(@a);
      $data = sprintf "%04X%04X", $cmdID, $manufID;
      $destinationID = $remoteID;
      $status = '0F';
      $hash->{IODev}{helper}{remoteAnswerWait}{0x850}{hash} = $hash;
      RemoveInternalTimer($hash->{helper}{timer}{0x850}) if(exists $hash->{helper}{timer}{0x850});
      $hash->{helper}{timer}{0x850} = {hash => $hash, param => 0x850};
      InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', $hash->{helper}{timer}{0x850}, 0);
      Log3 $name, 3, "EnOcean get $name $cmd";

    } elsif ($cmd eq "signal") {
      # trigger status massage of device
      $rorg = "D0";
      $destinationID = $hash->{DEF} if ($destinationID eq 'F' x 8);
      shift(@a);
      my $trigger = shift(@a);
      my %trigger = ('energy' => '01', 'revision' => '02', 'RXlevel' => '03', 'harvester' => '04');
      if (defined $trigger) {
        if (exists $trigger{$trigger}) {
          $data = '04' . $trigger{$trigger};
        } else {
          return "$cmd <trigger> wrong, choose energy|revision|RXlevel|harvester.";
        }
      } else {
        return "$cmd <trigger> wrong, choose energy|revision|RXlevel|harvester.";
      }
      Log3 $name, 3, "EnOcean get $name $cmd $trigger";

    } elsif ($st eq "switch.05") {
      # Dual Channel Switch Actuator
      # (A5-11-05)
      $rorg = "A5";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "status" || $cmd eq "state" ) {
        # query state
        Log3 $name, 3, "EnOcean get $name $cmd";
        $data = "00000008";

      } else {
        $cmdList .= "status:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "lightCtrl.01") {
      # Central Command, Extended Lighting-Control
      # (A5-38-09)
      $rorg = "A5";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "status" || $cmd eq "state") {
        # query state
        Log3 $name, 3, "EnOcean get $name $cmd";
        $data = "00000008";

      } else {
        $cmdList .= "status:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "actuator.01") {
      # Electronic switches and dimmers with Energy Measurement and Local Control
      # (D2-01-00 - D2-01-14)
      $rorg = "D2";
      shift(@a);
      my $channel;
      if ($cmd !~ m/^roomCtrlMode$/) {
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          $channel = 30;
        } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {

        } else {
          return "$cmd <channel> wrong, choose 0...29|all|input.";
        }
      }

      if ($cmd eq "status" || $cmd eq "state") {
        $cmdID = 3;
        Log3 $name, 3, "EnOcean get $name $cmd $channel";
        $data = sprintf "%02X%02X", $cmdID, $channel;

      } elsif ($cmd eq "measurement") {
        $cmdID = 6;
        my $query = shift(@a);
        if (!defined $query) {
          return "$cmd <channel> <query> wrong, choose 0...30|all|input energy|power.";
        } elsif ($query eq "energy") {
          $query = 0;
        } elsif ($query eq "power") {
          $query = 1;
        } else {
          return "$cmd <channel> <query> wrong, choose 0...30|all|input energy|power.";
        }
        Log3 $name, 3, "EnOcean get $name $cmd $channel $query";
        $data = sprintf "%02X%02X", $cmdID, $query << 5 | $channel;

      } elsif ($cmd eq "roomCtrlMode") {
        Log3 $name, 3, "EnOcean get $name $cmd";
        $data = '09';

      } elsif ($cmd eq "settings") {
        $cmdID = 10;
        Log3 $name, 3, "EnOcean get $name $cmd $channel";
        $data = sprintf "%02X%02X", $cmdID, $channel;

      } elsif ($cmd eq "special") {
        $rorg = "D1";
        my $query = shift(@a);
        if ($manufID eq "033") {
          if (!defined $query) {
            return "$cmd <channel> <query> wrong, choose health|load|voltage|serialNumber.";
          } elsif ($query eq "health") {
            $query = 7;
          } elsif ($query eq "load") {
            $query = 8;
          } elsif ($query eq "voltage") {
            $query = 9;
          } elsif ($query eq "serialNumber") {
            $query = 0x81;
          } else {
            return "$cmd <channel> <query> wrong, choose health|load|voltage|serialNumber.";
          }
          $data = sprintf "0331%02X", $query;
          Log3 $name, 3, "EnOcean get $name $cmd $channel $query";
          readingsSingleUpdate($hash, "getParam", $query, 0);
        } elsif ($manufID eq "046") {
          if (!defined $query) {
            return "$cmd <channel> <query> wrong, choose reset|firmwareVersion|taughtInDevNum|taughtInDevID.";
          } elsif ($query eq "reset") {
            $query = 1;
            $data = sprintf "0046%02X", $query;
          } elsif ($query eq "firmwareVersion") {
            $query = 2;
            $data = sprintf "0046%02X", $query;
          } elsif ($query eq "taughtInDevNum") {
            $query = 4;
            $data = sprintf "0046%02X", $query;
          } elsif ($query eq "taughtInDevID") {
            $query = 6;
            my $taughtInDevNum = shift(@a);
            if (defined $taughtInDevNum && $taughtInDevNum =~ m/^\d+$/ && $taughtInDevNum >= 0 && $taughtInDevNum <= 23) {
              $data = sprintf "0046%02X%02X", $query, $taughtInDevNum;
            } else {
              return "Usage: taughtInDevID is not numeric or out of range";
            }
          } else {
            return "$cmd <channel> <query> wrong, choose reset|firmwareVersion|taughtInDevNum|taughtInDevID.";
          }
          Log3 $name, 3, "EnOcean get $name $cmd $channel $query";
          readingsSingleUpdate($hash, "getParam", $query, 0);
        }

      } else {
        if ($manufID =~ m/^033|046$/) {
          return "Unknown argument $cmd, choose one of " . $cmdList . "measurement roomCtrlMode:noArg settings special status";
        } else {
          return "Unknown argument $cmd, choose one of " . $cmdList . "measurement roomCtrlMode:noArg settings status";
        }
      }

    } elsif ($st =~ m/^blindsCtrl\.0[01]$/) {
      # Blinds Control for Position and Angle
      # (D2-05-xx)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "position") {
        # query position and angle
        $cmdID = 3;
        my $channel = shift(@a);
        if (!defined $channel) {
          $channel = AttrVal($name, "defaultChannel", 'all');
          $channel = $channel eq "all" ? 15 : $channel - 1;
        } elsif ($channel =~ m/^all$/) {
          $channel = 15;
        } elsif ($channel =~ m/^[1234]$/) {
          $channel -= 1;
        } else {
          return "$cmd parameter wrong, choose one of 1|2|3|4|all";
        }
        Log3 $name, 3, "EnOcean get $name $cmd";
        $data = sprintf "%02X", $channel << 4 | $cmdID;

      } else {
        $cmdList .= "position";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "multisensor.01") {
      # Multisensor Windows Handle
      # (D2-06-01)
      $rorg = "D2";
      shift(@a);
      $updateState = 2;
      my $waitingCmds = ReadingsVal($name, "waitingCmds", undef);
      if (defined $waitingCmds) {
        # check presence state
        $waitingCmds = ReadingsVal($name, "presence", "present") eq "absent" ? $waitingCmds & 0xDF | 32 : $waitingCmds & 0xDF;
      } else {
        $waitingCmds = ReadingsVal($name, "presence", "present") eq "absent" ? 32 : 0;
      }
      if ($cmd eq "config") {
        # query config
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds | 0x80, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";
      } elsif ($cmd eq "log") {
        # query log
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds | 0x40, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";
      } else {
        $cmdList .= "config:noArg log:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "roomCtrlPanel.00") {
      # Room Control Panel
      # (D2-10-00 - D2-10-02)
      $rorg = "D2";
      shift(@a);
      $updateState = 2;
      if ($cmd eq "data") {
        # data request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 1, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } elsif ($cmd eq "config") {
        # configuration request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 32, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } elsif ($cmd eq "roomCtrl") {
        # room control setup request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 128, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } elsif ($cmd eq "timeProgram") {
        # time program request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 256, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } else {
        $cmdList .= "data:noArg config:noArg roomCtrl:noArg timeProgram:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "fanCtrl.00") {
      # Fan Control
      # (D2-20-00 - D2-20-02)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "status" || $cmd eq "state") {
        # query position and angle
        $data = "F6FFFFFF";
        Log3 $name, 3, "EnOcean get $name $cmd DATA: $data";

      } else {
        $cmdList .= "status:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "heatingActuator.00") {
      # Heating Actuator
      # (D2-34-00 - D2-34-02)
      $rorg = "D2";
      shift(@a);
      my $channel = shift(@a);
      $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
      if (!defined($channel) || defined($channel) && ($channel eq "all" || $channel + 0 >= 30)) {
        $channel = 30;
      } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {

      } else {
        return "$cmd <channel> wrong, choose 0...29|all.";
      }
      if ($cmd eq "status") {
        $cmdID = 3;
      } elsif ($cmd eq "setpoint") {
        $cmdID = 6;
      } else {
        return "Unknown argument $cmd, choose one of " . $cmdList . "setpoint status";
      }
      $data = sprintf "%02X%02X", $channel << 3, $cmdID;
      Log3 $name, 3, "EnOcean get $name $cmd $channel";

    } elsif ($st eq "heatRecovery.00") {
      # heat recovery ventilation
      # (D2-50-00)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "basicState") {
        # query switch state
        $data = "00";
        Log3 $name, 3, "EnOcean get $name $cmd";

      } elsif ($cmd eq "extendedState") {
        # query switch state
        $data = "01";
        Log3 $name, 3, "EnOcean get $name $cmd";

      } else {
        $cmdList .= "basicState:noArg extendedState:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "valveCtrl.00" && AttrVal($name, "devMode", "master") eq "master") {
      # Valve Control
      # (D2-A0-01)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "status" || $cmd eq "state") {
        # query switch state
        $data = "00";
        readingsSingleUpdate($hash, "state", $cmd, 1);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } else {
        $cmdList .= "state:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "remote") {
      return "Unknown argument $cmd, choose one of $cmdList";

    } else {
      # subtype does not support get commands
      if (AttrVal($name, "remoteManagement", "off") eq "manager" || AttrVal($name, "signal", "off") eq "on") {
        return "Unknown argument $cmd, choose one of $cmdList";
      } else {
        return;
      }
    }

    if($updateState != 2) {
      EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
    }
  }
}

# Set
sub EnOcean_Set($@)
{
  my ($hash, @a) = @_;
  return "no set value specified" if (@a < 2);
  my $name = $hash->{NAME};
  if (IsDisabled($name)) {
    Log3 $name, 4, "EnOcean $name set commands disabled.";
    return;
  }
  my $cmdID;
  my $cmdList = "";
  my @cmdObserve = @a;
  my ($ctrl, $data, $err, $logLevel, $response);
  my $destinationID = AttrVal($name, "destinationID", undef);
  if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
    $destinationID = defined(AttrVal($name, "subDef", undef)) ? $hash->{DEF} : "FFFFFFFF";
    $destinationID = "FFFFFFFF" if (uc(AttrVal($name, "subDef", $hash->{DEF})) eq uc($hash->{DEF}));
  } elsif (!defined $destinationID || $destinationID eq "multicast") {
    $destinationID = "FFFFFFFF";
  } elsif ($destinationID eq "unicast") {
    $destinationID = defined(AttrVal($name, "subDef", undef)) ? $hash->{DEF} : "FFFFFFFF";
    $destinationID = "FFFFFFFF" if (uc(AttrVal($name, "subDef", $hash->{DEF})) eq uc($hash->{DEF}));
  } elsif ($destinationID !~ m/^[\dA-Fa-f]{8}$/) {
    return "DestinationID $destinationID wrong, choose <8-digit-hex-code>.";
  }
  $destinationID = uc($destinationID);
  my $IODev = $hash->{IODev}{NAME};
  my $IOHash = $defs{$IODev};
  my $manufID = uc(AttrVal($name, "manufID", ""));
  my $model = AttrVal($name, "model", "");
  my $packetType = 1;
  $packetType = 0x0A if (ReadingsVal($IODev, "mode", "00") eq "01");
  my $remoteID = AttrVal($name, "remoteID", undef);
  my $remoteManufID = uc(AttrVal($name, "remoteManufID", AttrVal($name, "manufID", "")));
  my $rorg;
  my $sendCmd = 1;
  my $status = "00";
  my $st = AttrVal($name, "subType", "");
  my $stSet = AttrVal($name, "subTypeSet", undef);
  if (defined $stSet) {$st = $stSet;}
  my $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
  if ($subDef !~ m/^[\dA-F]{8}$/) {return "SenderID $subDef wrong, choose <8-digit-hex-code>.";}
  my $switchMode = AttrVal($name, "switchMode", "switch");
  my $timeNow = TimeNow();
  my $remoteManagement = AttrVal($name, "remoteManagement", "off");
  if ($remoteManagement eq "manager") {
    # Remote Management Manager
    $cmdList = "remoteAction:noArg remoteApplyChanges:devCfg,linkTable,no_change remoteDevCfg remoteLinkCfg remoteLock:noArg remoteLearnMode remoteLinkTable remoteLinkTableGP remoteRepeater remoteRepeaterFilter remoteReset:devCfg,linkTableIn,linkTableOut,no_change remoteRLT remoteSetCode:noArg remoteTeach remoteUnlock:noArg ";
  } elsif ($remoteManagement eq "client" || $st eq "remote") {
    # Remote Management Client
    $cmdList .= "remoteLock:noArg remoteUnlock ";
  }
  # control set actions
  # $updateState = -1: no set commands available e. g. sensors
  #                 0: execute set commands
  #                 1: execute set commands and and update reading state
  #                 2: execute set commands delayed
  #                 3: internal command
  my $updateState = AttrVal($name, "comMode", "uniDir") eq "uniDir" ? 1 : 0;
  my $updateStateAttr = AttrVal($name, "updateState", "default");
  shift @a;

  for (my $i = 0; $i < @a; $i++) {
    my $cmd = $a[$i];
    my ($cmd1, $cmd2);

    if ($cmd eq "remoteUnlock") {
      if ($remoteManagement eq "manager") {
        # manager
        $cmdID = 1;
        my $remoteCode = AttrVal($name, "remoteCode", undef);
        return "Security Code not defined, set attr $name remoteCode <00000001 ... FFFFFFFE>!" if (!defined($remoteCode));
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $data = sprintf "%04X%04X%s", $cmdID, $manufID, uc($remoteCode);
        if (defined $remoteID) {
          $destinationID = $remoteID;
        } else {
          $destinationID = 'F' x 8;
        }
        $updateState = 0;
      } else {
        # client
        my $remoteUnlockPeriod = 1800;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 1800) {
            $remoteUnlockPeriod = $a[1];
            shift(@a);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
        $hash->{RemoteClientUnlock} = 1;
        RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlock}) if(exists $hash->{helper}{timer}{RemoteClientUnlock});
        $hash->{helper}{timer}{RemoteClientUnlock} = {hash => $hash, param => 'RemoteClientUnlock'};
        InternalTimer(gettimeofday() + $remoteUnlockPeriod, 'EnOcean_cdmClearHashVal', $hash->{helper}{timer}{RemoteClientUnlock}, 0);
        $updateState = 3;
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($cmd eq "remoteLock") {
      if ($remoteManagement eq "manager") {
        # manager
        $cmdID = 2;
        my $remoteCode = AttrVal($name, "remoteCode", undef);
        return "Security Code not defined, set attr $name remoteCode <00000001 ... FFFFFFFE>!" if (!defined($remoteCode));
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $data = sprintf "%04X%04X%s", $cmdID, $manufID, uc($remoteCode);
        if (defined $remoteID) {
          $destinationID = $remoteID;
        } else {
          $destinationID = 'F' x 8;
        }
        $updateState = 0;
      } else {
        # client
        delete $hash->{RemoteClientUnlock};
        RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlock}) if(exists $hash->{helper}{timer}{RemoteClientUnlock});
        $updateState = 3;
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($cmd eq "remoteSetCode") {
      $cmdID = 3;
      my $remoteCode = AttrVal($name, "remoteCode", undef);
      return "Security Code not defined, set attr $name remoteCode <00000001 ... FFFFFFFE>!" if (!defined($remoteCode));
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      $data = sprintf "%04X%04X%s", $cmdID, $manufID, uc($remoteCode);
      if (defined $remoteID) {
        $destinationID = $remoteID;
      } else {
        $destinationID = 'F' x 8;
      }
      Log3 $name, 3, "EnOcean set $name $cmd";
      $updateState = 0;

    } elsif ($cmd eq "remoteAction") {
      $cmdID = 5;
      $manufID = 0x7FF;
      $packetType = 7;
      $rorg = "C5";
      $data = sprintf "%04X%04X", $cmdID, $manufID;
      if (defined $remoteID) {
        $destinationID = $remoteID;
      } else {
        $destinationID = 'F' x 8;
      }
      Log3 $name, 3, "EnOcean set $name $cmd";
      $updateState = 0;

    } elsif ($cmd eq "remoteLinkTable") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] && defined $a[3] && defined $a[4] && defined $a[5] &&
          $a[1] =~ m/^in|out$/ && $a[2] =~ m/^[\dA-Fa-f]{2}$/ && $a[3] =~ m/^[\dA-Fa-f]{8}$/ && $a[4] =~ m/^[\dA-Fa-f]{2}-[\dA-Fa-f]{2}-[\dA-Fa-f]{2}$/ && $a[5] =~ m/^[\dA-Fa-f]{2}$/) {
        $cmdID = 0x212;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $a[4] =~ m/^(..)-(..)-(..)$/;
        $data = sprintf "%04X%04X%s%s%s%s%s%s%s", $cmdID, $manufID, $a[1] eq 'out' ? '80' : '00', uc($a[2]), uc($a[3]), uc($1), uc($2), uc($3), uc($a[5]);
        splice(@a,0,5);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd arguments needed or wrong.";
      }

    } elsif ($cmd eq "remoteLinkTableGP") {
      # gpDef example: ch2:O:1:24:1:7:-40:1:40:1
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] && defined $a[3] && $a[1] =~ m/^in|out$/ && $a[2] =~ m/^[\dA-Fa-f]{2}$/) {
        $cmdID = 0x214;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        my $direction = $a[1] eq 'out' ? '80' : '00';
        my $gpDef;
        my ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
          split(':', $a[3]);
        if ($channelDir eq "O" && $a[1] eq 'out' || $channelDir eq "I" && $a[1] eq 'in') {
          # add channel-, signal- and valuetype
          $gpDef .= substr(unpack('B8', pack('C', $channelType)), 6) .
                    unpack('B8', pack('C', $signalType)) .
                    substr(unpack('B8', pack('C', $valueType)), 6);
          if ($channelType == 1 || $channelType == 3) {
            # data, enumeration: add resolution
            $gpDef .= substr(unpack('B8', pack('C', $resolution)), 4);
          }
          if ($channelType == 1) {
            # data: add engineering and scaling
            $gpDef .= unpack('B8', pack('c', $engMin)) .
                      substr(unpack('B8', pack('C', $scalingMin)), 4) .
                      unpack('B8', pack('c', $engMax)) .
                      substr(unpack('B8', pack('C', $scalingMax)), 4);
          }
        } else {
          return "Usage: Link Table GP Entry Direction wrong.";
        }
        if (length($gpDef) % 8) {
          # fill with trailing zeroes to x bytes
          $gpDef .= 0 x (8 - length($gpDef) % 8);
        }
        $data = sprintf "%04X%04X%s%s%s", $cmdID, $manufID, $a[1] eq 'out' ? '80' : '00', uc($a[2]), EnOcean_convBitToHex($gpDef);
        splice(@a,0,3);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd arguments needed or wrong.";
      }

    } elsif ($cmd eq "remoteLearnMode") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1]) {
        $cmdID = 0x220;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        my $learnMode;
        my $cmdVal = 0;

        if ($a[1] eq 'in') {
          $learnMode = '00';
          shift(@a);
        } elsif ($a[1] eq 'out') {
          $learnMode = '40';
          shift(@a);
        } elsif ($a[1] eq 'off') {
          $learnMode = '80';
          shift(@a);
        } else {
          return "Usage: $cmd $a[1] argument unknown.";
        }
        if (defined $a[1] && $a[1] =~ m/^[\dA-Fa-f]{2}$/) {
          $cmdVal = $a[1];
          shift(@a);
        } else {
          return "Usage: $cmd <learnMode> argument needed or wrong.";
        }
        $data = sprintf "%04X%04X%s%s", $cmdID, $manufID, $learnMode, $cmdVal;
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      }

    } elsif ($cmd eq "remoteTeach") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && $a[1] =~ m/^[\dA-Fa-f]{2}$/) {
        $cmdID = 0x221;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        $data = sprintf "%04X%04X%s", $cmdID, $manufID, $a[1];
        shift(@a);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
        if (!exists($hash->{IODev}{Teach})) {
          # enable teach-in receiving for 3 sec
          $hash->{IODev}{Teach} = 1;
          RemoveInternalTimer($hash->{helper}{timer}{Teach}) if(exists $hash->{helper}{timer}{Teach});
          $hash->{helper}{timer}{Teach} = {hash => $IOHash, param => 'Teach'};
          InternalTimer(gettimeofday() + 3, 'EnOcean_cdmClearHashVal', $hash->{helper}{timer}{Teach}, 0);
        }
      } else {
        return "Usage: $cmd argument needed or wrong.";
      }

    } elsif ($cmd eq "remoteReset") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && $a[1] =~ m/^devCfg|linkTableIn|linkTableOut|no_change$/) {
        $cmdID = 0x224;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        my %changeCmd = ('devCfg' => '80', 'linkTableIn' => '40', 'linkTableOut' => '20', 'no_change' => '00');
        $data = sprintf "%04X%04X%s", $cmdID, $manufID, $changeCmd{$a[1]};
        shift(@a);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd argument needed or wrong.";
      }

    } elsif ($cmd eq "remoteRLT") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] && $a[1] =~ m/^off|on$/ && $a[2] =~ m/^[0-7][1-9A-Fa-f]$/) {
        $cmdID = 0x225;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        my $rltMode = hex $a[2];
        $rltMode |= 0x80 if ($a[1] eq 'on');
        $data = sprintf "%04X%04X%02X", $cmdID, $manufID, $rltMode;
        splice(@a,0,2);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      }

    } elsif ($cmd eq "remoteApplyChanges") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && $a[1] =~ m/^devCfg|linkTable|no_change$/) {
        $cmdID = 0x226;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        my %changeCmd = ('devCfg' => '40', 'linkTable' => '80', 'no_change' => '00');
        $data = sprintf "%04X%04X%s", $cmdID, $manufID, $changeCmd{$a[1]};
        shift(@a);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd argument needed or wrong.";
      }

    } elsif ($cmd eq "remoteDevCfg") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] && $a[1] =~ m/^[\dA-Fa-f]{4}$/ && $a[2] =~ m/^[\dA-Fa-f]{2}[\dA-Fa-f]*$/ && length($a[2]) % 2 == 0) {
        $cmdID = 0x231;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        $data = sprintf "%04X%04X%s%02X%s", $cmdID, $manufID, uc($a[1]), length($a[2]) / 2, uc($a[2]);
        splice(@a,0,2);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd arguments needed or wrong.";
      }

    } elsif ($cmd eq "remoteLinkCfg") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] && defined $a[3] && defined $a[4] &&
          $a[1] =~ m/^in|out$/ && $a[2] =~ m/^[\dA-Fa-f]{2}$/ && $a[3] =~ m/^[\dA-Fa-f]{4}$/ &&
          $a[4] =~ m/^[\dA-Fa-f]{2}[\dA-Fa-f]*$/ && length($a[4]) % 2 == 0) {
        $cmdID = 0x233;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        my $direction = $a[1] eq 'out' ? '80' : '00';
        $destinationID = $remoteID;
        $data = sprintf "%04X%04X%s%s%s%02X%s", $cmdID, $manufID, $direction, uc($a[2]), uc($a[3]), length($a[4]) / 2, uc($a[4]);
        splice(@a,0,4);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd arguments needed or wrong.";
      }

    } elsif ($cmd eq "remoteRepeater") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] && defined $a[3] &&
          $a[1] =~ m/^on|off|filter$/ && $a[2] =~ m/^[1-2]$/ && $a[3] =~ m/^AND|OR$/) {
        $cmdID = 0x251;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        my %repFunc = ('on' => 0x40, 'off' => 0, 'filter' => 0x80);
        my $cmdVal = $repFunc{$a[1]} | ($a[2] == 2 ? 0x20 : 0x10) | ($a[3] eq 'OR' ? 8 : 0);
        $destinationID = $remoteID;
        $data = sprintf "%04X%04X%02X", $cmdID, $manufID, $cmdVal;
        splice(@a,0,3);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd arguments needed or wrong.";
      }

    } elsif ($cmd eq "remoteRepeaterFilter") {
      return "Attribute remoteID is missing, please define it." if (!defined $remoteID);
      if (defined $a[1] && defined $a[2] &&
          $a[1] =~ m/^apply|block|delete|deleteAll$/ && $a[2] =~ m/^destinationID|sourceID|rorg|rssi$/) {
        my %repFilterCtrl = ('deleteAll' => 0x30, 'delete' => 0x20, 'apply' => 0x10, 'block' => 0);
        my $cmdVal = $repFilterCtrl{$a[1]};
        my $cmdAttr;
        if (defined $a[3]) {
          if ($a[2] =~ m/^destinationID$/ && $a[3] =~ m/^[\dA-Fa-f]{8}$/) {
            $cmdVal |= 3;
            $cmdAttr = $a[3];
          } elsif ($a[2] =~ m/^sourceID$/ && $a[3] =~ m/^[\dA-Fa-f]{8}$/) {
            $cmdVal |= 0;
            $cmdAttr = $a[3];
          } elsif ($a[2] =~ m/^rorg$/ && $a[3] =~ m/^[\dA-Fa-f]{2}$/) {
            $cmdVal |= 1;
            $cmdAttr = '0' x 6 . $a[3];
          } elsif ($a[2] =~ m/^rssi$/ && $a[3] =~ m/^-?\d+$/ && abs($a[3]) >= 0 && abs($a[3]) <= 255) {
            $cmdVal |= 2;
            $cmdAttr = sprintf "000000%02X", abs($a[3]);
          } else {
            return "Usage: $cmd $a[2] argument wrong.";
          }
        } else {
          return "Usage: $cmd $a[2] argument needed.";
        }
        $cmdID = 0x252;
        $manufID = 0x7FF;
        $packetType = 7;
        $rorg = "C5";
        $destinationID = $remoteID;
        $data = sprintf "%04X%04X%02X%s", $cmdID, $manufID, $cmdVal, $cmdAttr;
        splice(@a,0,3);
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 0;
      } else {
        return "Usage: $cmd arguments needed or wrong.";
      }
    } elsif ($st eq "switch") {
      # Rocker Switch, simulate a PTM200 switch module
      # separate first and second action
      ($cmd1, $cmd2) = split(",", $cmd, 2);
      # check values
      if (!defined($EnO_ptm200btn{$cmd1}) || ($cmd2 && !defined($EnO_ptm200btn{$cmd2}))) {
        $cmdList .= join(":noArg ", sort keys %EnO_ptm200btn) . ':noArg';
        return SetExtensions($hash, $cmdList, $name, @a);
      }
      my $channelA = ReadingsVal($name, "channelA", undef);
      my $channelB = ReadingsVal($name, "channelB", undef);
      my $channelC = ReadingsVal($name, "channelC", undef);
      my $channelD = ReadingsVal($name, "channelD", undef);
      my $lastChannel = ReadingsVal($name, ".lastChannel", "A");
      my $releasedChannel = AttrVal($name, "releasedChannel", "auto");
      my $subDefA = AttrVal($name, "subDefA", $subDef);
      my $subDefB = AttrVal($name, "subDefB", $subDef);
      my $subDefC = AttrVal($name, "subDefC", $subDef);
      my $subDefD = AttrVal($name, "subDefD", $subDef);
      my $subDefI = AttrVal($name, "subDefI", $subDef);
      my $subDef0 = AttrVal($name, "subDef0", $subDef);
      my $switchType = AttrVal($name, "switchType", "direction");

      # first action
      if ($cmd1 eq "released") {
        if ($switchType eq "central") {
          if ($releasedChannel eq "auto") {
            if ($lastChannel =~ m/0|I/) {
              $releasedChannel = $lastChannel;
            } else {
              $releasedChannel = 0;
            }
          } elsif ($releasedChannel !~ m/0|I/) {
            $releasedChannel = 0;
          }
        } elsif ($switchType eq "channel") {
          if ($releasedChannel eq "auto") {
            if ($lastChannel =~ m/A|B|C|D/) {
              $releasedChannel = $lastChannel;
            } else {
              $releasedChannel = "A";
            }
          } elsif ($releasedChannel !~ m/A|B|C|D/) {
            $releasedChannel = "A";
          }
        }
        $subDef = AttrVal($name, "subDef" . $releasedChannel, $subDef);
      } elsif ($switchType eq "central") {
        if ($cmd1 =~ m/.0/) {
          $subDef = $subDef0;
          $lastChannel = 0;
        } elsif ($cmd1 =~ m/.I/) {
          $subDef = $subDefI;
          $lastChannel = "I";
        }
      } elsif ($switchType eq "channel") {
        $lastChannel = substr($cmd1, 0, 1);
        $subDef = AttrVal($name, "subDef" . $lastChannel, $subDefA);
      } else {
        $lastChannel = substr($cmd1, 0, 1);
      }

      if ($switchType eq "universal") {
        if ($cmd1 =~ m/A./ && (!defined($channelA) || $cmd1 ne $channelA)) {
          $cmd1 = "A0";
        } elsif ($cmd1 =~ m/B./ && (!defined($channelB) || $cmd1 ne $channelB)) {
          $cmd1 = "B0";
        } elsif ($cmd1 =~ m/C./ && (!defined($channelC) || $cmd1 ne $channelC)) {
          $cmd1 = "C0";
        } elsif ($cmd1 =~ m/D./ && (!defined($channelD) || $cmd1 ne $channelD)) {
          $cmd1 = "D0";
        } elsif ($cmd1 eq "released") {

        } else {
          $sendCmd = undef;
        }
      }
      # second action
      if ($cmd2 && $switchType eq "universal") {
        if ($cmd2 =~ m/A./ && (!defined($channelA) || $cmd2 ne $channelA)) {
          $cmd2 = "A0";
        } elsif ($cmd2 =~ m/B./ && (!defined($channelB) || $cmd2 ne $channelB)) {
          $cmd2 = "B0";
        } elsif ($cmd2 =~ m/C./ && (!defined($channelC) || $cmd2 ne $channelC)) {
          $cmd2 = "C0";
        } elsif ($cmd2 =~ m/D./ && (!defined($channelD) || $cmd2 ne $channelD)) {
          $cmd2 = "D0";
        } else {
          $cmd2 = undef;
        }
        if ($cmd2 && undef($sendCmd)) {
          # only second action has changed, send as first action
          $cmd1 = $cmd2;
          $cmd2 = undef;
          $sendCmd = 1;
        }
      }
      # convert and send first and second command
      my $switchCmd;
      ($switchCmd, $status) = split(':', $EnO_ptm200btn{$cmd1}, 2);
      # reset T21 status flag if 4 rocker
      $status = '10' if ($switchCmd > 3);
      $switchCmd <<= 5;
      if ($cmd1 ne "released") {
        # set the pressed flag
        $switchCmd |= 0x10 ;
      }
      if($cmd2) {
        # execute second action
        if ($switchType =~ m/^central|channel$/) {
          # second action not supported
          $cmd = $cmd1;
        } else {
          my ($d2, undef) = split(':', $EnO_ptm200btn{$cmd2}, 2);
          # reset T21 status flag if 4 rocker
          $status = '10' if ($d2 > 3);
          $switchCmd |= ($d2 << 1) | 0x01;
        }
      }
      if (defined $sendCmd) {
        $data = sprintf "%02X", $switchCmd;
        $rorg = "F6";
        SetExtensionsCancel($hash);
        Log3 $name, 3, "EnOcean set $name $cmd";
        if ($updateState) {
          readingsSingleUpdate($hash, "channel" . $1, $cmd1, 1) if ($cmd1 =~ m/^([A-D])./);
          readingsSingleUpdate($hash, "channel" . $1, $cmd2, 1) if ($cmd2 && $cmd2 =~ m/^([A-D])./);
        }
        readingsSingleUpdate($hash, ".lastChannel", $lastChannel, 0);
      }

    } elsif ($st eq "switch.00") {
      my $switchCmd = join(",", sort split(",", $cmd, 2));
      ($cmd1, $cmd2) = split(",", $switchCmd, 2);
      $cmd = $switchCmd;
      if ((!defined($switchCmd)) || (!defined($EnO_switch_00Btn{$switchCmd}))) {
        # check values
        $cmdList .= join(":noArg ", keys %EnO_switch_00Btn);
        return SetExtensions($hash, $cmdList, $name, @a);
      } elsif ($switchCmd eq "teachIn") {
        ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, AttrVal($name, "comMode", "uniDir"),
                                              AttrVal($name, "uteResponseRequest", "no"), "in", 0, "D2-03-00");
        $updateState = 0;
      } elsif ($switchCmd eq "teachInSec") {
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        ($err, $response, $logLevel) = EnOcean_sec_createTeachIn(undef, $hash, "uniDir", "VAES", "D2-03-00", 3,
                                                                 "2++", "false", "encryption", $subDef, $destinationID);
        if ($err) {
          Log3 $name, $logLevel, "EnOcean $name Error: $err";
          return $err;
        } else {
          EnOcean_CommandSave(undef, undef);
          Log3 $name, $logLevel, "EnOcean $name $response";
          readingsSingleUpdate($hash, "teach", "STE teach-in sent", 1);
          return(undef);
        }
      } elsif ($switchCmd eq "teachOut") {
        ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, AttrVal($name, "comMode", "uniDir"),
                                              AttrVal($name, "uteResponseRequest", "no"), "out", 0, "D2-03-00");
        $updateState = 0;
      } else {
        $data = sprintf "%02X", $EnO_switch_00Btn{$switchCmd};
        $rorg = "D2";
        SetExtensionsCancel($hash);
      }
      Log3 $name, 3, "EnOcean set $name $switchCmd";

    } elsif ($st eq "roomSensorControl.01") {
      # Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)
      # [Thermokon SR04 * rH, Thanus SR *, untested]
      # $db[3] is the setpoint where 0x00 = min ... 0xFF = max
      # $db[2] is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db[1] is the temperature where 0x00 = 0°C ... 0xFA = +40°C
      # $db[0] bit D0 is the occupy button, pushbutton or slide switch
      $rorg = "A5";
      # primarily temperature from the reference device then the attribute actualTemp is read
      my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
      my $actualTemp = AttrVal($name, "actualTemp", 20);
      $actualTemp = ReadingsVal($temperatureRefDev, "temperature", 20) if (defined $temperatureRefDev);
      $actualTemp = 20 if ($actualTemp !~ m/^[+-]?\d+(\.\d+)?$/);
      $actualTemp = 0 if ($actualTemp < 0);
      $actualTemp = 40 if ($actualTemp > 40);
      $actualTemp = sprintf "%0.1f", $actualTemp;
      # primarily humidity from the reference device then the attribute humidity is read
      my $humidityRefDev = AttrVal($name, "humidityRefDev", undef);
      my $humidity = AttrVal($name, "humidity", 0);
      $humidity = ReadingsVal($humidityRefDev, "humidity", 0) if (defined $humidityRefDev);
      $humidity = 0 if ($humidity !~ m/^\d+(\.\d+)?$/);
      $humidity = 0 if ($humidity < 0);
      $humidity = 100 if ($humidity > 100);
      $humidity = sprintf "%d", $humidity;
      my $setCmd = 8;
      my $setpoint = ReadingsVal($name, "setpoint", 125);
      my $setpointScaled = ReadingsVal($name, "setpointScaled", undef);
      my $switch = ReadingsVal($name, "switch", "off");
      $setCmd |= 1 if ($switch eq "on");
      if ($cmd eq "teach") {
        if ($manufID eq "00D") {
          # teach-in EEP A5-10-12, Manufacturer "Eltako"
          $data = "40900D80";
          $attr{$name}{eep} = "A5-10-12";
        } else {
          # teach-in EEP A5-10-10, Manufacturer "Multi user Manufacturer ID"
          $data = "4087FF80";
          $attr{$name}{eep} = "A5-10-10";
        }
        CommandDeleteReading(undef, "$name .*");
        readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
        $updateState = 0;
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");

      } elsif ($cmd eq "setpoint") {
        #
        if (defined $a[1]) {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 255)) {
            $setpoint = $a[1];
            shift(@a);
            if (defined $setpointScaled) {
              $setpointScaled = EnOcean_ReadingScaled($hash, $setpoint, 0, 255);
            }
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "temperature", $actualTemp);
        readingsBulkUpdate($hash, "humidity", $humidity);
        readingsBulkUpdate($hash, "setpointScaled", $setpointScaled) if (defined $setpointScaled);
        readingsBulkUpdate($hash, "setpoint", $setpoint);
        readingsBulkUpdate($hash, "switch", $switch);
        readingsBulkUpdate($hash, "state", "T: $actualTemp H: $humidity SP: $setpoint SW: $switch");
        readingsEndUpdate($hash, 1);
        $actualTemp = $actualTemp / 40 * 250;
        $humidity = $humidity / 100 * 250;
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $humidity, $actualTemp, $setCmd;

      } elsif ($cmd eq "setpointScaled") {
        #
        if (defined $a[1]) {
          my $scaleMin = AttrVal($name, "scaleMin", undef);
          my $scaleMax = AttrVal($name, "scaleMax", undef);
          my ($rangeMin, $rangeMax);
          if (defined $scaleMax && defined $scaleMin &&
              $scaleMax =~ m/^[+-]?\d+(\.\d+)?$/ && $scaleMin =~ m/^[+-]?\d+(\.\d+)?$/) {
            if ($scaleMin > $scaleMax) {
              ($rangeMin, $rangeMax)= ($scaleMax, $scaleMin);
            } else {
              ($rangeMin, $rangeMax)= ($scaleMin, $scaleMax);
            }
          } else {
            return "Usage: Attributes scaleMin and/or scaleMax not defined or not numeric.";
          }
          if ($a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= $rangeMin && $a[1] <= $rangeMax) {
            $setpointScaled = $a[1];
            shift(@a);
            $setpoint = sprintf "%d", 255 * $scaleMin/($scaleMin-$scaleMax) - 255/($scaleMin-$scaleMax) * $setpointScaled;
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "temperature", $actualTemp);
        readingsBulkUpdate($hash, "humidity", $humidity);
        readingsBulkUpdate($hash, "setpointScaled", $setpointScaled) if (defined $setpointScaled);
        readingsBulkUpdate($hash, "setpoint", $setpoint);
        readingsBulkUpdate($hash, "switch", $switch);
        readingsBulkUpdate($hash, "state", "T: $actualTemp H: $humidity SP: $setpoint SW: $switch");
        readingsEndUpdate($hash, 1);
        $actualTemp = $actualTemp / 40 * 250;
        $humidity = $humidity / 100 * 250;
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $humidity, $actualTemp, $setCmd;

      } elsif ($cmd eq "switch") {
        #
        if (defined $a[1]) {
          if ($a[1] eq "on") {
            $switch = $a[1];
            $setCmd |= 1;
            shift(@a);
          } elsif ($a[1] eq "off"){
            $switch = $a[1];
            shift(@a);
          } else {
            return "Usage: $a[1] is unknown";
          }
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "temperature", $actualTemp);
        readingsBulkUpdate($hash, "humidity", $humidity);
        readingsBulkUpdate($hash, "setpointScaled", $setpointScaled) if (defined $setpointScaled);
        readingsBulkUpdate($hash, "setpoint", $setpoint);
        readingsBulkUpdate($hash, "switch", $switch);
        readingsBulkUpdate($hash, "state", "T: $actualTemp H: $humidity SP: $setpoint SW: $switch");
        readingsEndUpdate($hash, 1);
        $actualTemp = $actualTemp / 40 * 250;
        $humidity = $humidity / 100 * 250;
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $humidity, $actualTemp, $setCmd;

      } else {
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList . " setpoint:slider,0,1,255 setpointScaled switch:on,off teach:noArg"
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "roomSensorControl.05") {
      # Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)
      # [Eltako FTR55D, FTR55H, Thermokon SR04 *, Thanos SR *, untested]
      # $db[3] is the fan speed or night reduction for Eltako
      # $db[2] is the setpoint where 0x00 = min ... 0xFF = max or
      # reference temperature for Eltako where 0x00 = 0°C ... 0xFF = 40°C
      # $db[1] is the temperature where 0x00 = +40°C ... 0xFF = 0°C
      # $db[1]_bit_1 is blocking the aditional Room Sensor and Control Unit for Eltako FVS
      # $db[0]_bit_0 is the slide switch
      $rorg = "A5";
      # primarily temperature from the reference device then the attribute actualTemp is read
      my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
      my $actualTemp = AttrVal($name, "actualTemp", 20);
      $actualTemp = ReadingsVal($temperatureRefDev, "temperature", 20) if (defined $temperatureRefDev);
      $actualTemp = 20 if ($actualTemp !~ m/^[+-]?\d+(\.\d+)?$/);
      $actualTemp = 0 if ($actualTemp < 0);
      $actualTemp = 40 if ($actualTemp > 40);
      $actualTemp = sprintf "%0.1f", $actualTemp;
      my $setCmd = 8;
      if ($manufID eq "00D") {
        # EEP A5-10-06 plus DB3 [Eltako FVS]
        my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
        my $nightReduction = ReadingsVal($name, "nightReduction", 0);
        my $block = ReadingsVal($name, "block", "unlock");
        if ($cmd eq "teach") {
          # teach-in EEP A5-10-06 plus "FVS", Manufacturer "Eltako"
          $data = "40300D85";
          $attr{$name}{eep} = "A5-10-06";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "desired-temp" || $cmd eq "setpointTemp") {
          #
          if (defined $a[1]) {
            if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 40)) {
              $setpointTemp = sprintf "%0.1f", $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
          if (defined $a[1]) {
            if (($a[1] =~ m/^(lock|unlock)$/) ) {
              $block = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is unknown";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointTemp", $setpointTemp, 1);
          readingsSingleUpdate($hash, "nightReduction", $nightReduction, 1);
          readingsSingleUpdate($hash, "block", $block, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SPT: $setpointTemp NR: $nightReduction", 1);
          if ($nightReduction == 5) {
            $nightReduction = 31;
          } elsif ($nightReduction == 4) {
            $nightReduction = 25;
          } elsif ($nightReduction == 3) {
            $nightReduction = 19;
          } elsif ($nightReduction == 2) {
            $nightReduction = 12;
          } elsif ($nightReduction == 1) {
            $nightReduction = 6;
          } else {
            $nightReduction = 0;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $setpointTemp = $setpointTemp * 255 / 40;
          # control of the aditional Room Sensor and Control Unit
          if ($block eq "lock") {
            # temperature setting is locked
            $setCmd = 0x0D;
          } else {
            # setpointTemp may be subject to change at +/-3 K
            $setCmd = 0x0F;
          }
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $nightReduction, $setpointTemp, $actualTemp, $setCmd;

        } elsif ($cmd eq "nightReduction") {
          #
          if (defined $a[1]) {
            if ($a[1] =~ m/^[0-5]$/) {
              $nightReduction = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
          if (defined $a[1]) {
            if (($a[1] =~ m/^(lock|unlock)$/) ) {
              $block = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is unknown";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointTemp", $setpointTemp, 1);
          readingsSingleUpdate($hash, "nightReduction", $nightReduction, 1);
          readingsSingleUpdate($hash, "block", $block, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SPT: $setpointTemp NR: $nightReduction", 1);
          if ($nightReduction == 5) {
            $nightReduction = 31;
          } elsif ($nightReduction == 4) {
            $nightReduction = 25;
          } elsif ($nightReduction == 3) {
            $nightReduction = 19;
          } elsif ($nightReduction == 2) {
            $nightReduction = 12;
          } elsif ($nightReduction == 1) {
            $nightReduction = 6;
          } else {
            $nightReduction = 0;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 254;
          $setpointTemp = $setpointTemp * 254 / 40;
          # control of the aditional Room Sensor and Control Unit
          if ($block eq "lock") {
            # temperature setting is locked
            $setCmd = 0x0D;
          } else {
            # setpointTemp may be subject to change at +/-3 K
            $setCmd = 0x0F;
          }
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $nightReduction, $setpointTemp, $actualTemp, $setCmd;

        } else {
          return "Unknown argument " . $cmd . ", choose one of setpointTemp:slider,0,1,40 desired-temp nightReduction:0,1,2,3,4,5 teach:noArg"
        }

      } else {
        # EEP A5-10-02 or EEP A5-10-03
        my $setpoint = ReadingsVal($name, "setpoint", 128);
        my $setpointScaled = ReadingsVal($name, "setpointScaled", undef);
        my $fanStage = ReadingsVal($name, "fanStage", "auto");
        my $switch = ReadingsVal($name, "switch", "off");
        $setCmd |= 1 if ($switch eq "on");
        if ($cmd eq "teach") {
          if ($manufID eq "019") {
            # teach-in EEP A5-10-03, Manufacturer "Multi user Manufacturer ID"
            $data = "401FFF80";
            $attr{$name}{eep} = "A5-10-03";
          } else {
            # teach-in EEP A5-10-02, Manufacturer "Multi user Manufacturer ID"
            $data = "4017FF80";
            $attr{$name}{eep} = "A5-10-02";
          }
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "fanStage") {
          #
          if (defined $a[1] && ($a[1] =~ m/^[0-3]$/ || $a[1] eq "auto")) {
            $fanStage = $a[1];
            shift(@a);
            readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
            readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1) if (defined $setpointScaled);
            readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
            readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
            readingsSingleUpdate($hash, "switch", $switch, 1);
            readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
            if ($fanStage eq "auto"){
              $fanStage = 255;
            } elsif ($fanStage == 0) {
              $fanStage = 209;
            } elsif ($fanStage == 1) {
               $fanStage = 189;
            } elsif ($fanStage == 2) {
              $fanStage = 164;
            } else {
              $fanStage = 144;
            }
          } else {
            return "Usage: $a[1] is not numeric, out of range or unknown";
          }
          $actualTemp = (40 - $actualTemp) / 40 * 254;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;

        } elsif ($cmd eq "setpoint") {
          #
          if (defined $a[1]) {
            if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 255)) {
              $setpoint = $a[1];
              shift(@a);
              if (defined $setpointScaled) {
                $setpointScaled = EnOcean_ReadingScaled($hash, $setpoint, 0, 255);
              }
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }

          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1) if (defined $setpointScaled);
          readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
          readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
          readingsSingleUpdate($hash, "switch", $switch, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
          if ($fanStage eq "auto"){
            $fanStage = 255;
          } elsif ($fanStage == 0) {
            $fanStage = 209;
          } elsif ($fanStage == 1) {
            $fanStage = 189;
          } elsif ($fanStage == 2) {
            $fanStage = 164;
          } else {
            $fanStage = 144;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;

        } elsif ($cmd eq "setpointScaled") {
          #
          if (defined $a[1]) {
            my $scaleMin = AttrVal($name, "scaleMin", undef);
            my $scaleMax = AttrVal($name, "scaleMax", undef);
            my ($rangeMin, $rangeMax);
            if (defined $scaleMax && defined $scaleMin &&
                $scaleMax =~ m/^[+-]?\d+(\.\d+)?$/ && $scaleMin =~ m/^[+-]?\d+(\.\d+)?$/) {
              if ($scaleMin > $scaleMax) {
                ($rangeMin, $rangeMax)= ($scaleMax, $scaleMin);
              } else {
                ($rangeMin, $rangeMax)= ($scaleMin, $scaleMax);
              }
            } else {
              return "Usage: Attributes scaleMin and/or scaleMax not defined or not numeric.";
            }
            if ($a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= $rangeMin && $a[1] <= $rangeMax) {
              $setpointScaled = $a[1];
              shift(@a);
              $setpoint = sprintf "%d", 255 * $scaleMin/($scaleMin-$scaleMax) - 255/($scaleMin-$scaleMax) * $setpointScaled;
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1);
          readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
          readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
          readingsSingleUpdate($hash, "switch", $switch, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
          if ($fanStage eq "auto"){
            $fanStage = 255;
          } elsif ($fanStage == 0) {
            $fanStage = 209;
          } elsif ($fanStage == 1) {
            $fanStage = 189;
          } elsif ($fanStage == 2) {
            $fanStage = 164;
          } else {
            $fanStage = 144;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;

        } elsif ($cmd eq "switch") {
          #
          if (defined $a[1]) {
            if ($a[1] eq "on") {
              $switch = $a[1];
              $setCmd |= 1;
              shift(@a);
            } elsif ($a[1] eq "off"){
              $switch = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is unknown";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1) if (defined $setpointScaled);
          readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
          readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
          readingsSingleUpdate($hash, "switch", $switch, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
          if ($fanStage eq "auto"){
            $fanStage = 255;
          } elsif ($fanStage == 0) {
            $fanStage = 209;
          } elsif ($fanStage == 1) {
            $fanStage = 189;
          } elsif ($fanStage == 2) {
            $fanStage = 164;
          } else {
            $fanStage = 144;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;

        } else {
          return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "setpoint:slider,0,1,255 fanStage:auto,0,1,2,3 setpointScaled switch:on,off teach:noArg"
        }

      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "environmentApp" && AttrVal($name, "devMode", "slave") eq "master") {
      # sent EEP A5-13-03 / A5-13-04 telegram periodical (date, time)
      $rorg = "A5";
      if ($cmd eq "sendDate") {
        my ($sec, $min, $hour, $day, $month, $year, $weekday, $dayOfYearTag, $summerTime) = localtime();
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $day, $month + 1, $year - 100, 57;
      } elsif ($cmd eq "sendTime") {
        my ($sec, $min, $hour, $day, $month, $year, $weekday, $dayOfYearTag, $summerTime) = localtime();
        my @weekday = (7, 1, 2, 3, 4, 5, 6);
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $weekday[$weekday] << 5 | $hour, $min, $sec, 73;
      } elsif ($cmd eq "start") {
        $updateState = 3;
        @{$hash->{helper}{periodic}{time}} = ($hash, 'time', $attr{$name}{sendTimePeriodic}, 0, -1, undef);
        EnOcean_SndPeriodic($hash->{helper}{periodic}{time});
      } elsif ($cmd eq "stop") {
        $updateState = 3;
        @{$hash->{helper}{periodic}{time}} = ($hash, 'time', 'off', 0, -1, undef);
        EnOcean_SndPeriodic($hash->{helper}{periodic}{time});
      } elsif ($cmd eq "teachDate") {
        $attr{$name}{eep} = "A5-13-03";
        my $manufID = uc(AttrVal($name, "manufID", "7FF"));
        $updateState = 1;
        $data = sprintf "%06X80", 0x13 << 18 | 3 << 11 | hex($manufID) & 0x7FF;
      } elsif ($cmd eq "teachTime") {
        $attr{$name}{eep} = "A5-13-04";
        my $manufID = uc(AttrVal($name, "manufID", "7FF"));
        $updateState = 1;
        $data = sprintf "%06X80", 0x13 << 18 | 4 << 11 | hex($manufID) & 0x7FF;
      } else {
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "sendDate:noArg sendTime:noArg start:noArg stop:noArg teachDate:noArg teachTime:noArg";
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "hvac.01" || $st eq "MD15") {
      # Battery Powered Actuator (EEP A5-20-01)
      # [Kieback&Peter MD15-FTL-xx]
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $temperature = ReadingsVal($name, "temperature", 20);
      if ($cmd eq "setpoint") {
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "setpointSet", $a[1]);
          readingsBulkUpdate($hash, "waitingCmds", $cmd);
          readingsEndUpdate($hash, 0);
          # stop PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          CommandDeleteReading(undef, "$name setpointTempSet");
          Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 2;

      } elsif ($cmd =~ m/^desired-temp|setpointTemp$/) {
        if (defined $a[1] && $a[1] =~ m/^\d+(\.\d)?$/ && $a[1] >= 0 && $a[1] <= 40) {
          $cmd = "setpointTemp";
          $setpointTemp = $a[1];
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "setpointTempSet", sprintf("%0.1f", $setpointTemp));
          readingsBulkUpdate($hash, "waitingCmds", "setpointTemp");
          readingsEndUpdate($hash, 0);
          # PID regulator active
          my $activatePID = AttrVal($name, 'pidCtrl', 'off') eq 'on' ? 'start' : 'stop';
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, $activatePID, undef);
          CommandDeleteReading(undef, "$name setpointSet");
          Log3 $name, 3, "EnOcean set $name $cmd $setpointTemp";
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 2;

      } elsif ($cmd =~ m/^liftSet|runInit|valveOpens|valveCloses$/) {
        # unattended?
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "waitingCmds", $cmd);
        readingsEndUpdate($hash, 0);
        # stop PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTempSet");
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 2;

      } else {
        $cmdList .= "setpointTemp:slider,0,1,40 " if (AttrVal($name, "pidCtrl", 'on') eq 'on' || AttrVal($name, "manufID", '7FF') ne '049');
        $cmdList .= "setpoint:slider,0,5,100 desired-temp liftSet:noArg runInit:noArg valveOpens:noArg valveCloses:noArg";
        return "Unknown command " . $cmd . ", choose one of " . $cmdList;
      }

    } elsif ($st eq "hvac.04") {
     # heating radiator valve actuating drive (EEP A5-20-04)
      $rorg = "A5";
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $temperature = ReadingsVal($name, "temperature", 20);
      if ($cmd eq "setpoint") {
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "setpointSet", $a[1]);
          readingsBulkUpdate($hash, "waitingCmds", $cmd);
          readingsEndUpdate($hash, 0);
          # stop PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          CommandDeleteReading(undef, "$name setpointTempSet");
          Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 2;

      } elsif ($cmd =~ m/^desired-temp|setpointTemp$/) {
        if (defined $a[1] && $a[1] =~ m/^\d+(\.\d)?$/ && $a[1] >= 10 && $a[1] <= 30) {
          $cmd = "setpointTemp";
          $setpointTemp = $a[1];
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "setpointTempSet", sprintf("%0.1f", $setpointTemp));
          readingsBulkUpdate($hash, "waitingCmds", "setpointTemp");
          readingsEndUpdate($hash, 0);
          # PID regulator active
          my $activatePID = AttrVal($name, 'pidCtrl', 'on') eq 'on' ? 'start' : 'stop';
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, $activatePID, undef);
          CommandDeleteReading(undef, "$name setpointSet");
          Log3 $name, 3, "EnOcean set $name $cmd $setpointTemp";
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 2;

      } elsif ($cmd =~ m/^runInit|valveOpens|valveCloses$/) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "waitingCmds", $cmd);
        readingsEndUpdate($hash, 0);
        # stop PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTempSet");
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 2;

      } else {
        $cmdList .= "setpointTemp:slider,10,1,30 " if (AttrVal($name, "pidCtrl", 'on') eq 'on' || AttrVal($name, "model", '') eq 'Holter_OEM');
        $cmdList .= "setpoint:slider,0,5,100 " if (AttrVal($name, "pidCtrl", 'on') eq 'off' && AttrVal($name, "model", '') ne 'Holter_OEM');
        $cmdList .= "runInit:noArg valveCloses:noArg valveOpens:noArg";
        return "Unknown command " . $cmd . ", choose one of " . $cmdList;
      }

    } elsif ($st eq "hvac.06") {
      # Battery Powered Actuator (EEP A5-20-06)
      # [Micropelt iTRV MVA-005, OPUS Micropelt HOME]
      $rorg = "A5";
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $temperature = ReadingsVal($name, "temperature", 20);
      if ($cmd eq "setpoint") {
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "setpointSet", $a[1]);
          readingsBulkUpdate($hash, "waitingCmds", $cmd);
          readingsEndUpdate($hash, 0);
          # stop PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          CommandDeleteReading(undef, "$name setpointTempSet");
          Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 2;

      } elsif ($cmd =~ m/^desired-temp|setpointTemp$/) {
        if (defined $a[1] && $a[1] =~ m/^\d+(\.\d)?$/ && $a[1] >= 0 && $a[1] <= 40) {
          $cmd = "setpointTemp";
          $setpointTemp = $a[1];
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "setpointTempSet", sprintf("%0.1f", $setpointTemp));
          readingsBulkUpdate($hash, "waitingCmds", "setpointTemp");
          readingsEndUpdate($hash, 0);
          # PID regulator active
          my $activatePID = AttrVal($name, 'pidCtrl', 'off') eq 'on' ? 'start' : 'stop';
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, $activatePID, undef);
          CommandDeleteReading(undef, "$name setpointSet");
          Log3 $name, 3, "EnOcean set $name $cmd $setpointTemp";
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 2;

      } elsif ($cmd =~ m/^runInit|standby$/) {
        # unattended?
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "waitingCmds", $cmd);
        readingsEndUpdate($hash, 0);
        # stop PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name alarm");
        RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
        Log3 $name, 3, "EnOcean set $name $cmd";
        $updateState = 2;

      } else {
        $cmdList .= "setpointTemp:slider,0,1,40 setpoint:slider,0,5,100 desired-temp runInit:noArg standby:noArg";
        return "Unknown command " . $cmd . ", choose one of " . $cmdList;
      }

    } elsif ($st eq "hvac.10") {
      # Generic HVAC Interface (EEP A5-20-10)
      $rorg = "A5";
      my %ctrlFunc = (
        "off" => 1,
        "on" => 2,
        "occupancy" => 3,
        "ctrl" => 4,
        "fanSpeed" => 5,
        "vanePosition" => 6,
        "mode" => 7,
        "teach" => 255,
      );
      my %mode = (
        "auto" => 0,
        "heat" => 1,
        "morning_warmup" => 2,
        "cool" => 3,
        "night_purge" => 4,
        "precool" => 5,
        "off" => 6,
        "test" => 7,
        "emergency_heat" => 8,
        "fan_only" => 9,
        "free_cool" => 10,
        "ice" => 11,
        "max_heat" => 12,
        "eco" => 13,
        "dehumidification" => 14,
        "calibration" => 15,
        "emergency_cool" => 16,
        "emergency_stream" => 17,
        "max_cool" => 18,
        "hvc_load" => 19,
        "no_load" => 20,
        "auto_heat" => 31,
        "auto_cool" => 32,
      );
      my %vanePosition = (
        "auto" => 0,
        "horizontal" => 1,
        "position_2" => 2,
        "position_3" => 3,
        "position_4" => 4,
        "vertical" => 5,
        "swing" => 6,
        "vertical_swing" => 11,
        "horizontal_swing" => 12,
        "hor_vert_swing" => 13,
        "stop_swing" => 14,
      );
      my $ctrlFuncID;
      if (defined $ctrlFunc{$cmd}) {
        $ctrlFuncID = $ctrlFunc{$cmd};
      } else {
        $cmdList .= "ctrl mode:" . join(",", sort keys %mode) . " fanSpeed:auto,1,2,3,4,5,6,7,8,9,10,11,12,13,14 " .
                    "occupancy:occupied,off,standby,unoccupied on:noArg off:noArg teach:noArg vanePosition:" .
                    join(",", sort keys %vanePosition);
        return SetExtensions ($hash, $cmdList, $name, @a);
      }
      $ctrl = ReadingsVal($name, "ctrl", "auto");
      my $fanSpeed = ReadingsVal($name, "fanSpeed", "auto");
      my $mode = ReadingsVal($name, "mode", "off");
      my $occupancy = ReadingsVal($name, "occupancy", "off");
      my $powerSwitch = ReadingsVal($name, "powerSwitch", "off");
      my $vanePosition = ReadingsVal($name, "vanePosition", "auto");
      my ($ctrlParam1, $ctrlParam2, $ctrlParam3, $setCmd) = (0, 0, 0, 8);

      if($ctrlFuncID == 255) {
        # teach-in EEP A5-20-10, Manufacturer "Multi user Manufacturer ID"
        $ctrlParam1 = 0x80;
        $ctrlParam2 = 0x87;
        $ctrlParam3 = 0xFF;
        $setCmd = 0x80;
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
        EnOcean_4BSRespWait(undef, $hash, $subDef);
        readingsSingleUpdate($hash, "teach", "4BS teach-in sent, response requested", 1);
        $updateState = 0;
      } elsif ($ctrlFuncID == 1) {
        # off
        $powerSwitch = "off";
        $updateState = 0;
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "powerSwitch", "off");
        readingsBulkUpdate($hash, "state", "off");
        readingsEndUpdate($hash, 0);
        SetExtensionsCancel($hash);
      } elsif ($ctrlFuncID == 2) {
        # on
        $powerSwitch = "on";
        $updateState = 0;
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "powerSwitch", "on");
        readingsBulkUpdate($hash, "state", "off");
        readingsEndUpdate($hash, 0);
        SetExtensionsCancel($hash);
      } elsif ($ctrlFuncID == 3) {
        # occupancy
        if (defined $a[1] && $a[1] =~ m/^occupied|standby|unoccupied|off$/) {
          $occupancy = $a[1];
          readingsSingleUpdate($hash, "occupancy", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 4) {
        # ctrl
        if (defined $a[1] && ($a[1] =~ m/^auto$/ || $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100)) {
          $ctrl = $a[1];
          readingsSingleUpdate($hash, "ctrl", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 5) {
        # fanSpeed
        if (defined $a[1] && ($a[1] =~ m/^auto$/ || $a[1] =~ m/^\d+$/ && $a[1] > 0 && $a[1] < 15)) {
          $fanSpeed = $a[1];
          readingsSingleUpdate($hash, "fanSpeed", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 6) {
        # vanePosition
        my $vanePositionValues = join("|", keys %vanePosition);
        if (defined $a[1] && $a[1] =~ m/^$vanePositionValues$/) {
          $vanePosition = $a[1];
          readingsSingleUpdate($hash, "vanePosition", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 7) {
        # mode
        my $modeValues = join("|", keys %mode);
        if (defined $a[1] && $a[1] =~ m/^$modeValues$/) {
          $mode = $a[1];
          readingsSingleUpdate($hash, "mode", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      }
      if ($cmd ne "teach") {
        $ctrlParam1 = $mode{$mode};
        $vanePosition = $vanePosition{$vanePosition};
        $fanSpeed = 0 if ($fanSpeed eq "auto");
        $ctrlParam2 = $vanePosition << 4 || $fanSpeed;
        $ctrl = 255 if ($ctrl eq "auto");
        $ctrlParam3 = $ctrl;
        if ($occupancy eq "occupied") {
          $occupancy = 0;
        } elsif ($occupancy eq "standby") {
          $occupancy = 1;
        } elsif ($occupancy eq "unoccupied") {
          $occupancy = 2;
        } else {
          $occupancy = 3;
        }
        $powerSwitch = $powerSwitch eq "on" ? 1 : 0;
        $setCmd |= $occupancy << 1 | $powerSwitch;
      }
      $data = sprintf "%02X%02X%02X%02X", $ctrlParam1, $ctrlParam2, $ctrlParam3, $setCmd;
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "hvac.11") {
      # Generic HVAC Interface - Error Control (EEP A5-20-11)
      $rorg = "A5";
      my %ctrlFunc = (
        "externalDisable" => 1,
        "remoteCtrl" => 2,
        "window" => 3,
        "teach" => 255,
      );
      my $ctrlFuncID;
      if (defined $ctrlFunc{$cmd}) {
        $ctrlFuncID = $ctrlFunc{$cmd};
      } else {
        $cmdList .= "externalDisable:disabled,enabled remoteCtrl:disabled,enabled teach:noArg window:closed,opened";
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList;
      }
      my $extern = ReadingsVal($name, "externalDisable", "enable");
      my $remote = ReadingsVal($name, "remoteCtrl", "enable");
      my $window = ReadingsVal($name, "window", "closed");
      my ($ctrlParam1, $ctrlParam2, $ctrlParam3, $setCmd) = (0, 0, 0, 8);

      if($ctrlFuncID == 255) {
        # teach-in EEP A5-20-11, Manufacturer "Multi user Manufacturer ID"
        $ctrlParam1 = 0x80;
        $ctrlParam2 = 0x8F;
        $ctrlParam3 = 0xFF;
        $setCmd = 0x80;
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
        EnOcean_4BSRespWait(undef, $hash, $subDef);
        readingsSingleUpdate($hash, "teach", "4BS teach-in sent, response requested", 1);
        $updateState = 0;
      } elsif ($ctrlFuncID == 1) {
        # external disablement
        if (defined $a[1] && $a[1] =~ m/^disabled|enabled$/) {
          $extern = $a[1];
          readingsSingleUpdate($hash, "externalDisable", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 2) {
        # disable remote controller
        if (defined $a[1] && $a[1] =~ m/^disabled|enabled$/) {
          $remote = $a[1];
          readingsSingleUpdate($hash, "remoteCtrl", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 3) {
        # window contact
        if (defined $a[1] && $a[1] =~ m/^closed|opened$/) {
          $window = $a[1];
          readingsSingleUpdate($hash, "window", $a[1], 0);
          shift(@a);
        } else {
          return "Usage: $cmd value wrong.";
        }
        $updateState = 0;
      }
      if ($cmd ne "teach") {
        $ctrlParam3 = $extern eq "disabled" ? 1 : 0;
        $setCmd |= ($remote eq "disabled" ? 1 : 0) << 2 | ($window eq "closed" ? 1 : 0) << 1;
      }
      $data = sprintf "%02X%02X%02X%02X", $ctrlParam1, $ctrlParam2, $ctrlParam3, $setCmd;
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "gateway") {
      # Gateway (EEP A5-38-08)
      # select Command from attribute gwCmd or command line
      my $gwCmd = AttrVal($name, "gwCmd", undef);
      if ($gwCmd && $EnO_gwCmd{$gwCmd}) {
        # command from attribute gwCmd
        if ($EnO_gwCmd{$cmd}) {
          # shift $cmd
          $cmd = $a[1];
          shift(@a);
        }
      } elsif ($EnO_gwCmd{$cmd}) {
        # command from command line
        $gwCmd = $cmd;
        $cmd = $a[1];
        shift(@a);
      } else {
        return "Unknown Gateway command " . $cmd . ", choose one of " . $cmdList . join(" ", sort keys %EnO_gwCmd);
      }
      my $gwCmdID;
      $rorg = "A5";
      my $setCmd = 0;
      my $time = 0;
      if ($gwCmd eq "switching") {
        # Switching
        $gwCmdID = 1;
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          #$data = sprintf "%02X000000", $gwCmdID;
          if ($model =~ m/TF$/) {
            $data = "E0400D80";
          } else {
            $data = "E047FF80";
          }
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "on") {
          $setCmd = 9;
          readingsSingleUpdate($hash, "block", "unlock", 1);
          if ($a[1]) {
            return "Usage: $cmd [lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            if ($a[1] eq "lock") {
              $setCmd = $setCmd | 4;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          }
          #$updateState = 0;
          SetExtensionsCancel($hash);
          $data = sprintf "%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } elsif ($cmd eq "off") {
          if ($model =~ m/FSA12$/) {
            $setCmd = 0x0E;
          } else {
            $setCmd = 8;
          }
          readingsSingleUpdate($hash, "block", "unlock", 1);
          if ($a[1]) {
            return "Usage: $cmd [lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            if ($a[1] eq "lock") {
              $setCmd = $setCmd | 4;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          }
          #$updateState = 0;
          SetExtensionsCancel($hash);
          $data = sprintf "%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } elsif ($cmd eq "local") {
          if ($a[1]) {
            return "Usage: $cmd [learn]" if ($a[1] ne "learn");
            if ($a[1] eq "learn") {
              $cmd = 'off';
              $setCmd = $setCmd | 0x28;
              readingsSingleUpdate($hash, "block", "unlock", 1);
            }
            shift(@a);
          }
          #$updateState = 0;
          $data = sprintf "%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } else {
          my $cmdList = "local:learn on:noArg off:noArg teach:noArg";
          return SetExtensions ($hash, $cmdList, $name, @a);
        }

      } elsif ($gwCmd eq "dimming") {
        # Dimming
        $gwCmdID = 2;
        my $dimMax = AttrVal($name, "dimMax", 255);
        my $dimMin = AttrVal($name, "dimMin", "off");
        if ($dimMax =~ m/^\d+$/ && $dimMin =~ m/^\d+$/ && $dimMin > $dimMax) {
          ($dimMax, $dimMin) = ($dimMin , $dimMax);
        }
        my $dimVal = ReadingsVal($name, "dim", undef);
        my $rampTime = AttrVal($name, "rampTime", 1);
        my $sendDimCmd = 0;
        $setCmd = 9;

        if ($cmd =~ m/^\d+$/) {
          # interpretive numeric value as dimming
          unshift(@a, 'dim');
          $cmd = 'dim';
        }

        if ($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          #$data = "E047FF80";
          # teach-in Eltako
          if ($model =~ m/TF$/) {
            $data = "E0400D80";
          } else {
            $data = "02000000";
          }
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "dim") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 100);
          # for eltako relative (0-100) (but not compliant to EEP because DB0.2 is 0)
          # >> if manufID needed: set DB2.0
          $dimVal = $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "dimup") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 100);
          $dimVal += $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "dimdown") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 100);
          $dimVal -= $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "on") {
          $rampTime = 1;
          my $dimValueOn = AttrVal($name, "dimValueOn", 100);
          if ($dimValueOn eq "stored") {
            $dimVal = ReadingsVal($name, "dimValueStored", 100);
            if ($dimVal < 1) {
              $dimVal = 100;
              readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
            }
          } elsif ($dimValueOn eq "last") {
            $dimVal = ReadingsVal ($name, "dimValueLast", 100);
            if ($dimVal < 1) { $dimVal = 100; }
          } else {
            if ($dimValueOn !~ m/^\d+$/) {
              $dimVal = 100;
            } elsif ($dimValueOn > 100) {
              $dimVal = 100;
            } elsif ($dimValueOn < 1) {
              $dimVal = 1;
            } else {
              $dimVal = $dimValueOn;
            }
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "off") {
          $dimVal = 0;
          $rampTime = 1;
          $setCmd = 8;
          $sendDimCmd = 1;

        } elsif ($cmd eq "local") {
          if ($a[1]) {
            return "Usage: $cmd [learn]" if ($a[1] ne "learn");
            if ($a[1] eq "learn") {
              $cmd = 'off';
              $dimVal = 0;
              $rampTime = 1;
              $setCmd = 0x2C;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          }
          #$updateState = 0;
          SetExtensionsCancel($hash);
          $data = sprintf "%02X%02X%02X%02X", $gwCmdID, $dimVal, $rampTime, $setCmd;

        } else {
          my $cmdList = "dim:slider,0,1,100 local:learn on:noArg off:noArg teach:noArg";
          return SetExtensions ($hash, $cmdList, $name, @a);
        }
        if ($sendDimCmd) {
          readingsSingleUpdate($hash, "block", "unlock", 1);
          if (defined $a[1]) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] ne "lock" && $a[1] ne "unlock");
            # Eltako devices: lock dimming value
            if ($manufID eq "00D" && $a[1] eq "lock" ) {
              $setCmd = $setCmd | 4;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          } else {
            # Dimming value relative
            if ($manufID ne "00D") {$setCmd = $setCmd | 4;}
          }
          if ($cmd eq "off" && $dimMin =~ m/^\d+$/ && $dimMin == 0) {
            # switch off

          } elsif ($cmd eq "off" && $dimMin =~ m/^\d+$/) {
            $dimVal = $dimMin;
            $setCmd = 9;
          } elsif ($dimMax eq "off" || $dimVal == 0 && $dimMin eq "off" || $dimVal < 0) {
            # switch off
            $dimVal = 0;
            $setCmd = 8;
          } elsif ($dimMin eq "off") {

          } elsif ($dimVal < $dimMin) {
            $dimVal = $dimMin;
          }
          $dimVal = $dimMax if ($dimVal > $dimMax);
          $dimVal = 100 if ($dimVal > 100);
          $rampTime = 0 if ($rampTime < 0);
          $rampTime = 255 if ($rampTime > 255);
          #$updateState = 0;
          readingsSingleUpdate ($hash, "dim", $dimVal, 1);
          $data = sprintf "%02X%02X%02X%02X", $gwCmdID, $dimVal, $rampTime, $setCmd;
        }

      } elsif ($gwCmd eq "setpointShift") {
        $gwCmdID = 3;
        if ($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "shift") {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= -12.7) && ($a[1] <= 12.8)) {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, ($a[1] + 12.7) * 10;
            shift(@a);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        } else {
          return "Unknown argument $cmd, choose one of teach:noArg shift";
        }

      } elsif ($gwCmd eq "setpointBasic") {
        $gwCmdID = 4;
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "basic") {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 51.2)) {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, $a[1] * 5;
            shift(@a);
          } else {
            return "Usage: $cmd parameter is not numeric or out of range.";
          }
        } else {
          return "Unknown argument $cmd, choose one of teach:noArg basic";
        }

      } elsif ($gwCmd eq "controlVar") {
        $gwCmdID = 5;
        my $controlVar = ReadingsVal($name, "controlVar", 0);
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "presence") {
          if ($a[1] eq "standby") {
            $setCmd = 0x0A;
          } elsif ($a[1] eq "absent") {
            $setCmd = 9;
          } elsif ($a[1] eq "present") {
            $setCmd = 8;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "energyHoldOff") {
          if ($a[1] eq "normal") {
            $setCmd = 8;
          } elsif ($a[1] eq "holdoff") {
            $setCmd = 0x0C;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "controllerMode") {
          if ($a[1] eq "auto") {
            $setCmd = 8;
          } elsif ($a[1] eq "heating") {
            $setCmd = 0x28;
          } elsif ($a[1] eq "cooling") {
            $setCmd = 0x48;
          } elsif ($a[1] eq "off" || $a[1] eq "BI") {
            $setCmd = 0x68;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "controllerState") {
          if ($a[1] eq "auto") {
            $setCmd = 8;
          } elsif ($a[1] eq "override") {
            $setCmd = 0x18;
            if (defined $a[2] && ($a[2] =~ m/^[+-]?\d+$/) && ($a[2] >= 0) && ($a[2] <= 100) ) {
              $controlVar = $a[2] * 255;
              shift(@a);
            } else {
              return "Usage: Control Variable Override is not numeric or out of range.";
            }
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          #$updateState = 0;
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } else {
          return "Unknown argument, choose one of teach:noArg presence:absent,present,standby energyHoldOff:holdoff,normal controllerMode:cooling,heating,off controllerState:auto,override";
        }

      } elsif ($gwCmd eq "fanStage") {
        $gwCmdID = 6;
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "stage") {
          if ($a[1] eq "auto") {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, 255;
          } elsif ($a[1] && $a[1] =~ m/^[0-3]$/) {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, $a[1];
          } else {
            return "Usage: $cmd parameter is not numeric or out of range"
          }
          shift(@a);
        } else {
          return "Unknown argument, choose one of teach:noArg stage:auto,0,1,2,3";
        }

      } elsif ($gwCmd eq "blindCmd") {
        $gwCmdID = 7;
        my %blindFunc = (
          "status"         => 0,
          "stop"           => 1,
          "opens"          => 2,
          "closes"         => 3,
          "position"       => 4,
          "up"             => 5,
          "down"           => 6,
          "runtimeSet"     => 7,
          "angleSet"       => 8,
          "positionMinMax" => 9,
          "angleMinMax"    => 10,
          "positionLogic"  => 11,
          "teach"          => 255,
        );
        my @blindFunc = (
          "position:slider,0,1,100",
          "opens:noArg",
          "closes:noArg",
          "up",
          "down",
          "stop:noArg",
          "status:noArg",
          "runtimeSet",
          "angleSet",
          "positionMinMax",
          "angleMinMax",
          "positionLogic:normal,inverse",
          "teach:noArg",
        );
        my $blindFuncID;
        if (defined $blindFunc {$cmd}) {
          $blindFuncID = $blindFunc {$cmd};
        } elsif ($cmd =~ m/^\d+$/) {
          # interpretive numeric value as position
          unshift(@a, 'position');
          $cmd = 'position';
          $blindFuncID = 4;
        } else {
          return "Unknown Gateway Blind Central Function " . $cmd . ", choose one of ". join(" ", @blindFunc);
        }
        my $blindParam1 = 0;
        my $blindParam2 = 0;
        $setCmd = $blindFuncID << 4 | 8;

        if($blindFuncID == 255) {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $gwCmdID = 0xE0;
          $blindParam1 = 0x47;
          $blindParam2 = 0xFF;
          $setCmd = 0x80;
          $attr{$name}{eep} = "A5-38-08";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($blindFuncID == 0) {
          # status
          $updateState = 0;
        } elsif ($blindFuncID == 1) {
          # stop
          $updateState = 0;
        } elsif ($blindFuncID == 2) {
          # opens
          $updateState = 0;
        } elsif ($blindFuncID == 3) {
          # closes
          $updateState = 0;
        } elsif ($blindFuncID == 4) {
          # position
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $blindParam1 = $a[1];
            shift(@a);
            if (defined $a[1]) {
              if ($a[1] =~ m/^[+-]?\d+$/ && $a[1] >= -180 && $a[1] <= 180) {
                # set angle
                $blindParam2 = abs($a[1]) / 2;
                if ($a[1] < 0) {$blindParam2 |= 0x80;}
                shift(@a);
              } else {
                return "Usage: $cmd variable is not numeric or out of range.";
              }
            } else {
              # set angle defaults
              my $positionLogic = ReadingsVal($name, 'positionLogic', 'normal');
              my $angleMin = ReadingsVal($name, 'angleMin', -180);
              my $angleMax = ReadingsVal($name, 'angleMax', 180);
              if ($blindParam1 == 0) {
                $blindParam2 = $positionLogic eq 'normal' ? $angleMax : $angleMin;
              } elsif ($blindParam1 == 100) {
                $blindParam2 = $positionLogic eq 'normal' ? $angleMin : $angleMax;
              } else {
                $blindParam2 = $angleMin + ($angleMax - $angleMin) / 2;
              }
              if ($blindParam2 < 0) {
                $blindParam2 = abs($blindParam2) / 2;
                $blindParam2 |= 0x80;
              } else {
                $blindParam2 = $blindParam2 / 2;
              }
            }
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          # angle und position value available
          $setCmd |= 2;
          $updateState = 0;
        } elsif ($blindFuncID == 5 || $blindFuncID == 6) {
          # up / down
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[2] >= 0 && $a[2] <= 25.5) {
              $blindParam2 = $a[2] * 10;
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 7) {
          # runtimeSet
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= 0 && $a[2] <= 255) {
              $blindParam2 = $a[2];
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          readingsSingleUpdate($hash, "runTimeUp", $blindParam1, 1);
          readingsSingleUpdate($hash, "runTimeDown", $blindParam2, 1);
          $updateState = 0;
        } elsif ($blindFuncID == 8) {
          # angleSet
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= 0 && $a[1] <= 25.5) {
            $blindParam1 = $a[1] * 10;
            ##
            readingsSingleUpdate($hash, "angleTime", (sprintf "%0.1f", $a[1]), 1);
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 9) {
          # positionMinMax
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= 0 && $a[2] <= 100) {
              $blindParam2 = $a[2];
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            # angle und position value available
            $setCmd |= 2;
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          if ($blindParam1 > $blindParam2) {($blindParam1, $blindParam2) = ($blindParam2, $blindParam1);}
          readingsSingleUpdate($hash, "positionMin", $blindParam1, 1);
          readingsSingleUpdate($hash, "positionMax", $blindParam2, 1);
          $updateState = 0;
        } elsif ($blindFuncID == 10) {
          # angleMinMax
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= -180 && $a[1] <= 180) {
            if (!defined $a[2] || $a[2] !~ m/^[+-]?\d+$/ || $a[2] < -180 || $a[2] > 180) {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            if ($a[1] > $a[2]) {($a[1], $a[2]) = ($a[2], $a[1]);}
            $blindParam1 = abs($a[1]) / 2;
            if ($a[1] < 0) {$blindParam1 |= 0x80;}
            $blindParam2 = abs($a[2]) / 2;
            if ($a[2] < 0) {$blindParam2 |= 0x80;}
            # angle und position value available
            $setCmd |= 2;
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          readingsSingleUpdate($hash, "angleMin", $a[1], 1);
          readingsSingleUpdate($hash, "angleMax", $a[2], 1);
          splice (@a, 0, 2);
          shift(@a);
          $updateState = 0;
        } elsif ($blindFuncID == 11) {
          # positionLogic
          if ($a[1] eq "normal") {
            $blindParam1 = 0;
          } elsif ($a[1] eq "inverse") {
            $blindParam1 = 1;
          } else {
            return "Usage: $cmd variable is unknown.";
          }
          readingsSingleUpdate($hash, "positionLogic", $a[1], 1);
          shift(@a);
          $updateState = 0;
        } else {
        }
        $setCmd |= 4 if (AttrVal($name, "sendDevStatus", "no") eq "yes");
        $setCmd |= 1 if (AttrVal($name, "serviceOn", "no") eq "yes");
        $data = sprintf "%02X%02X%02X%02X", $gwCmdID, $blindParam1, $blindParam2, $setCmd;

      } else {
        return "Unknown Gateway command " . $cmd . ", choose one of ". $cmdList . join(" ", sort keys %EnO_gwCmd);
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "energyManagement.01") {
      # Energy Management, Demand Response (A5-37-01)
      $rorg = "A5";
      $updateState = 0;
      my $drLevel = 15;
      my $powerUsage = 100;
      my $powerUsageLevel = 1;
      my $powerUsageScale = 0;
      my $randomStart = 0;
      my $randomEnd = 0;
      my $randomTime = rand(AttrVal($name, "demandRespRandomTime", 1));
      my $setpoint = 255;
      my $timeout = 0;
      my $threshold = AttrVal($name, "demandRespThreshold", 8);

      if($cmd eq "teach") {
        # teach-in EEP A5-37-01, Manufacturer "Multi user Manufacturer ID"
        $data = "DC0FFF80";
        $attr{$name}{eep} = "A5-37-01";
        CommandDeleteReading(undef, "$name .*");
        readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
        $updateState = 0;
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "level") {
        return "Usage: $cmd 0...15 [max|rel [yes|no [yes|no [timeout/min]]]]"
          if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 15 );
        $drLevel = $a[1];
        $powerUsage = $a[1] / 15 * 100;
        $powerUsageLevel = $drLevel >= $threshold ? 1 : 0;
        $setpoint = $a[1] * 17;
        shift(@a);

      } elsif ($cmd eq "max") {

      } elsif ($cmd eq "min") {
        $drLevel = 0;
        $powerUsage = 0;
        $powerUsageLevel = 0;
        $setpoint = 0;

      } elsif ($cmd eq "power") {
        return "Usage: $cmd 0...100 [max|rel [yes|no [yes|no [timeout/min]]]]"
          if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 100);
        $drLevel = $a[1] / 100 * 15;
        $powerUsage = $a[1];
        $powerUsageLevel = $drLevel >= $threshold ? 1 : 0;
        $setpoint = $a[1] * 2.55;
        shift(@a);

      } elsif ($cmd eq "setpoint") {
        return "Usage: $cmd 0...255 [max|rel [yes|no [yes|no [timeout/min]]]]"
          if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 255 );
        $drLevel = $a[1] / 255 * 15 ;
        $powerUsage = $a[1] / 255 * 100;
        $powerUsageLevel = $drLevel >= $threshold ? 1 : 0;
        $setpoint = $a[1];
        shift(@a);

      } else {
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "level:slider,0,1,15 max:noArg min:noArg power:slider,0,5,100 setpoint:slider,0,5,255 teach:noArg"
      }

      if ($cmd ne "teach") {
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]" if($a[1] !~ m/^max|rel$/);
          $powerUsageScale = $a[1] eq "rel" ? 0x80 : 0;
          shift(@a);
        }
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]" if($a[1] !~ m/^yes|no$/);
          $randomStart = $a[1] eq "yes" ? 4 : 0;
          shift(@a);
        }
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]" if($a[1] !~ m/^yes|no$/);
          $randomEnd = $a[1] eq "yes" ? 2 : 0;
          shift(@a);
        }
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]"
            if($a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 3825);
          $timeout = int($a[1] / 15);
          shift(@a);
        }
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $powerUsageScale | $powerUsage, $timeout,
                                            $drLevel << 4 | $randomStart | $randomEnd | $powerUsageLevel | 8;
        my @db = ($drLevel << 4 | $randomStart | $randomEnd | $powerUsageLevel | 8,
                  $timeout, $powerUsageScale | $powerUsage, $setpoint);
        EnOcean_energyManagement_01Parse($hash, @db);
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "lightCtrl.01") {
      # Central Command, Extended Lighting-Control (EEP A5-38-09)
      $rorg = "A5";
      my %ctrlFunc = (
        "off"            => 1,
        "on"             => 2,
        "dimup"          => 3,
        "dimdown"        => 4,
        "stop"           => 5,
        "dim"            => 6,
        "rgb"            => 7,
        "scene"          => 8,
        "dimMinMax"      => 9,
        "lampOpHours"    => 10,
        "block"          => 11,
        "meteringValue"  => 12,
        "teach"          => 255,
      );
      my $ctrlFuncID;
      if (exists $ctrlFunc{$cmd}) {
        $ctrlFuncID = $ctrlFunc{$cmd};
      } elsif ($cmd =~ m/^\d+$/) {
        # interpretive numeric value as dimming
        unshift(@a, 'dim');
        $cmd = 'dim';
        $ctrlFuncID = 6;
      } else {
        $cmdList .= "dim:slider,0,5,255 dimup:noArg dimdown:noArg on:noArg off:noArg stop:noArg rgb:colorpicker,RGB scene dimMinMax lampOpHours block meteringValue teach:noArg";
        return SetExtensions ($hash, $cmdList, $name, @a);
      }
      my ($ctrlParam1, $ctrlParam2, $ctrlParam3) = (0, 0, 0);
      my $setCmd = $ctrlFuncID << 4 | 8;

      if($ctrlFuncID == 255) {
        # teach-in EEP A5-38-09, Manufacturer "Multi user Manufacturer ID"
        $ctrlParam1 = 0xE1;
        $ctrlParam2 = 0xC7;
        $ctrlParam3 = 0xFF;
        $setCmd = 0x80;
        $attr{$name}{eep} = "A5-38-09";
        CommandDeleteReading(undef, "$name .*");
        readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        $updateState = 0;
      } elsif ($ctrlFuncID == 1) {
        # off
        CommandDeleteReading(undef, "$name scene");
        SetExtensionsCancel($hash);
        $updateState = 0;
      } elsif ($ctrlFuncID == 2) {
        # on
        CommandDeleteReading(undef, "$name scene");
        SetExtensionsCancel($hash);
        $updateState = 0;
      } elsif ($ctrlFuncID == 3 || $ctrlFuncID == 4) {
        # dimup / dimdown
        my $rampTime = $a[1];
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+?$/ && $a[1] >= 0 && $a[1] <= 65535) {
            shift(@a);
          } else {
            return "Usage: $cmd ramping time value is not numeric or out of range.";
          }
        } else {
          $rampTime = AttrVal($name, "rampTime", 1);
        }
        $ctrlParam3 = $rampTime & 0xFF;
        $ctrlParam2 = ($rampTime & 0xFF00) >> 8;
        readingsSingleUpdate($hash, "rampTime", $rampTime, 1);
        CommandDeleteReading(undef, "$name scene");
        SetExtensionsCancel($hash);
        $updateState = 0;
      } elsif ($ctrlFuncID == 5) {
        # stop
        CommandDeleteReading(undef, "$name scene");
        SetExtensionsCancel($hash);
        $updateState = 0;
      } elsif ($ctrlFuncID == 6) {
        # dim
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
          $ctrlParam1 = $a[1];
          shift(@a);
        } else {
          return "Usage: $cmd dimming value is not numeric or out of range.";
        }
        my $rampTime = $a[1];
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+?$/ && $a[1] >= 0 && $a[1] <= 65535) {
            shift(@a);
          } else {
            return "Usage: $cmd ramping time value is not numeric or out of range.";
          }
        } else {
          $rampTime = AttrVal($name, "rampTime", 1);
        }
        $ctrlParam3 = $rampTime & 0xFF;
        $ctrlParam2 = ($rampTime & 0xFF00) >> 8;
        CommandDeleteReading(undef, "$name scene");
        readingsSingleUpdate($hash, "rampTime", $rampTime, 1);
        SetExtensionsCancel($hash);
        $updateState = 0;
      } elsif ($ctrlFuncID == 7) {
        # RGB
        if (@a > 1) {
          if ($a[1] =~ m/^[\dA-Fa-f]{6}$/) {
            # red
            $ctrlParam1 = hex substr($a[1], 0, 2);
            # green
            $ctrlParam2 = hex substr($a[1], 2, 2);
            # blue
            $ctrlParam3 = hex substr($a[1], 4, 2);
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "red", $ctrlParam1);
            readingsBulkUpdate($hash, "green", $ctrlParam2);
            readingsBulkUpdate($hash, "blue", $ctrlParam3);
            readingsBulkUpdate($hash, "rgb", uc($a[1]));
            readingsEndUpdate($hash, 0);
            shift(@a);
          } else {
            return "Usage: $cmd value is not hexadecimal or out of range.";
          }
        } else {
          return "Usage: $cmd values are missing";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 8) {
        # scene
          if (@a > 2) {
          if ($a[2] =~ m/^\d+?$/ && $a[2] >= 0 && $a[2] <= 15) {
            $ctrlParam3 = $a[2];
          } else {
            return "Usage: $cmd number is not numeric or out of range.";
          }
          if ($a[1] eq "drive") {
            readingsSingleUpdate($hash, "scene", $ctrlParam3, 1);
            splice(@a, 0, 2);
          } elsif ($a[1] eq "store") {
            $ctrlParam3 |= 0x80;
            splice(@a, 0, 2);
          } else {
            return "Usage: $cmd parameter is wrong.";
          }

        } else {
          return "Usage: $cmd values are missing";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 9) {
        # dimMinMax
        if (@a > 2) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            # dimming limit min
            $ctrlParam1 = $a[1];
            shift(@a);
          } else {
            return "Usage: $cmd value is not numeric or out of range.";
          }
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            # dimming limit max
            $ctrlParam2 = $a[1];
            shift(@a);
          } else {
            return "Usage: $cmd value is not numeric or out of range.";
          }
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "dimMin", $ctrlParam1);
          readingsBulkUpdate($hash, "dimMax", $ctrlParam2);
          readingsEndUpdate($hash, 1);
        } else {
          return "Usage: $cmd values are missing";
        }
          $updateState = 0;
        } elsif ($ctrlFuncID == 10) {
          # set operating hours of the lamp
          if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 65535) {
            $ctrlParam2 = $a[1] & 0xFF;
            $ctrlParam1 = ($a[1] & 0xFF00) >> 8;
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
      } elsif ($ctrlFuncID == 11) {
          # block
          if (!defined $a[1]) {
            return "Usage: $cmd values are missing";
          } elsif ($a[1] eq "unlock") {
          $ctrlParam3 = 0;
          } elsif ($a[1] eq "on") {
            $ctrlParam3 = 1;
          } elsif ($a[1] eq "off") {
            $ctrlParam3 = 2;
          } elsif ($a[1] eq "local") {
            $ctrlParam3 = 3;
          } else {
            return "Usage: $cmd variable is unknown.";
          }
          readingsSingleUpdate($hash, "block", $a[1], 1);
          shift(@a);
          $updateState = 0;
      } elsif ($ctrlFuncID == 12) {
          # meteringValues
          if (@a > 2) {
            my %unitEnum = (
              "mW"  => 0,
              "W"   => 1,
              "kW"  => 2,
              "MW"  => 3,
              "Wh"  => 4,
              "kWh" => 5,
              "MWh" => 6,
              "GWh" => 7,
              "mA"  => 8,
              "A"   => 9,
              "mV"  => 10,
              "V"   => 11,
            );
            if (exists $unitEnum{$a[2]}) {
              $ctrlParam3 = $unitEnum{$a[2]};
            } else {
              return "Unknown metering value choose one of " . join(" ", sort keys %unitEnum);
            }

            if ($ctrlParam3 == 9 || $ctrlParam3 == 11) {
              if ($a[1] =~ m/^\d+(\.\d+)?$/ && $a[1] >= 0 && $a[1] <= 6553.5) {
                $ctrlParam2 = int($a[1] * 10) & 0xFF;
                $ctrlParam1 = (int($a[1] * 10) & 0xFF00) >> 8;
              } else {
                return "Usage: $cmd value is not numeric or out of range.";
              }
            } else {
              if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 65535) {
                $ctrlParam2 = $a[1] & 0xFF;
                $ctrlParam1 = ($a[1] & 0xFF00) >> 8;
              } else {
                return "Usage: $cmd value is not numeric or out of range.";
              }
            }
            splice(@a, 0, 2);

          } else {
            return "Usage: $cmd values are missing";
          }
          $updateState = 0;
      }
      $setCmd |= 4 if (AttrVal($name, "sendDevStatus", "yes") eq "no");
      $setCmd |= 1 if (AttrVal($name, "serviceOn", "no") eq "yes");
      $data = sprintf "%02X%02X%02X%02X", $ctrlParam1, $ctrlParam2, $ctrlParam3, $setCmd;
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "radioLinkTest") {
      # Radio Link Test (A5-3F-00)
      $rorg = "A5";
      $updateState = 3;
      if($cmd =~ m/^standby|stop$/) {
        @{$hash->{helper}{rlt}{param}} = ($cmd, $hash, undef, $subDef, 'master', 0);
        EnOcean_RLT($hash->{helper}{rlt}{param});
      } else {
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "standby:noArg stop:noArg"
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "manufProfile") {
      if ($manufID eq "00D") {
        # Eltako Shutter
        my $angleMax = AttrVal($name, "angleMax", 90);
        my $angleMin = AttrVal($name, "angleMin", -90);
        my $anglePos = ReadingsVal($name, "anglePos", undef);
        my $anglePosStart;
        my $angleTime = AttrVal($name, "angleTime", 0);
        my $position = ReadingsVal($name, "position", undef);
        my $positionStart;
        my $setCmd = 8;
        my $settingAccuracy = 1;
        if (AttrVal($name, 'settingAccuracy', 'low') eq 'high') {
          $setCmd = 0x0A;
          $settingAccuracy = 10;
        }
        if ($cmd eq "?" || $cmd eq "stop") {

        } else {
          # check actual shutter position
	  my $actualState = ReadingsVal($name, "state", undef);
	  if (defined $actualState) {
	    if ($actualState eq "open") {
	      $position = 0;
	      $anglePos = 0;
	    } elsif ($actualState eq "closed") {
	      $position = 100;
	      $anglePos = $angleMax;
	    }
	  }
          $anglePosStart = $anglePos;
          $positionStart = $position;
          readingsSingleUpdate($hash, ".anglePosStart", $anglePosStart, 0);
          readingsSingleUpdate($hash, ".positionStart", $positionStart, 0);
        }
        $rorg = "A5";
        my $shutTime = AttrVal($name, "shutTime", 255);
        my $shutTimeCloses = AttrVal($name, "shutTimeCloses", $shutTime);
        $shutTimeCloses = $shutTime if ($shutTimeCloses < $shutTime);
        my $shutCmd = 0;
        $angleMax = 90 if ($angleMax !~ m/^[+-]?\d+$/);
        $angleMax = 180 if ($angleMax > 180);
        $angleMax = -180 if ($angleMax < -180);
        $angleMin = -90 if ($angleMin !~ m/^[+-]?\d+$/);
        $angleMin = 180 if ($angleMin > 180);
        $angleMin = -180 if ($angleMin < -180);
        ($angleMax, $angleMin) = ($angleMin, $angleMax) if ($angleMin > $angleMax);
        $angleMax ++ if ($angleMin == $angleMax);
        $angleTime = 6 if ($angleTime !~ m/^[+-]?\d+$/);
        $angleTime = 6 if ($angleTime > 6);
        $angleTime = 0 if ($angleTime < 0);
        $shutTime = 255 if ($shutTime !~ m/^[+-]?\d+$/);
        $shutTime = 255 if ($shutTime > 255);
        $shutTime = 1 if ($shutTime < 1);
        if ($cmd =~ m/^\d+$/) {
          # interpretive numeric value as position
          unshift(@a, 'position');
          $cmd = 'position';
        }
        if ($cmd eq "teach") {
          # teach-in EEP A5-3F-7F, Manufacturer "Eltako"
          $data = "FFF80D80";
          $attr{$name}{eep} = "A5-3F-7F";
          CommandDeleteReading(undef, "$name .*");
          readingsSingleUpdate($hash, "teach", "4BS teach-in sent", 1);
          $updateState = 0;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
          EnOcean_setTeachConfirmWaitHash(undef, $hash);
        } elsif ($cmd eq "stop") {
          # stop
          # delete readings, as they are undefined
          CommandDeleteReading(undef, "$name anglePos");
          CommandDeleteReading(undef, "$name position");
          readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
          readingsSingleUpdate($hash, "state", "stop", 1);
          $shutCmd = 0;
        } elsif ($cmd eq "opens") {
          # opens >> B0
          $anglePos = 0;
          $position = 0;
          readingsSingleUpdate($hash, "anglePos", $anglePos, 1);
          readingsSingleUpdate($hash, "position", $position, 1);
          readingsSingleUpdate($hash, "endPosition", "open", 1);
          $cmd = "open";
          $shutTime = $shutTimeCloses;
          $shutCmd = 1;
          #$updateState = 0;
        } elsif ($cmd eq "closes") {
          # closes >> BI
          $anglePos = $angleMax;
          $position = 100;
          readingsSingleUpdate($hash, "anglePos", $anglePos, 1);
      	  readingsSingleUpdate($hash, "position", $position, 1);
          readingsSingleUpdate($hash, "endPosition", "closed", 1);
          $cmd = "closed";
          $shutTime = $shutTimeCloses;
          $shutCmd = 2;
          #$updateState = 0;
        } elsif ($cmd eq "up") {
          # up
          if (defined $a[1]) {
            if ($a[1] =~ m/^[+-]?\d*[.]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
              $position = $positionStart - $a[1] / $shutTime * 100;
              if ($angleTime) {
                $anglePos = $anglePosStart - ($angleMax - $angleMin) * $a[1] / $angleTime;
                if ($anglePos < $angleMin) {
                  $anglePos = $angleMin;
                }
              } else {
                $anglePos = $angleMin;
              }
              if ($position <= 0) {
                $anglePos = 0;
                $position = 0;
                readingsSingleUpdate($hash, "endPosition", "open", 1);
                $cmd = "open";
              } else {
                readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
                $cmd = "not_reached";
              }
              $shutTime = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          } else {
            $anglePos = 0;
            $position = 0;
            readingsSingleUpdate($hash, "endPosition", "open", 1);
            $cmd = "open";
          }
          readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
      	  readingsSingleUpdate($hash, "position", sprintf("%d", $position), 1);
          $shutCmd = 1;
        } elsif ($cmd eq "down") {
          # down
          if (defined $a[1]) {
            if ($a[1] =~ m/^[+-]?\d*[.]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
              $position = $positionStart + $a[1] / $shutTime * 100;
              if ($angleTime) {
                $anglePos = $anglePosStart + ($angleMax - $angleMin) * $a[1] / $angleTime;
                if ($anglePos > $angleMax) {
                  $anglePos = $angleMax;
                }
              } else {
                $anglePos = $angleMax;
              }
              if($position >= 100) {
                $anglePos = $angleMax;
                $position = 100;
                readingsSingleUpdate($hash, "endPosition", "closed", 1);
                $cmd = "closed";
              } else {
                readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
                $cmd = "not_reached";
              }
              $shutTime = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          } else {
            $anglePos = $angleMax;
            $position = 100;
            readingsSingleUpdate($hash, "endPosition", "closed", 1);
            $cmd = "closed";
          }
          readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
          readingsSingleUpdate($hash, "position", sprintf("%d", $position), 1);
          $shutCmd = 2;
        } elsif ($cmd eq "position") {
          if (!defined $positionStart) {
            return "Position unknown, please first opens the blinds completely."
          } elsif ($angleTime > 0 && !defined $anglePosStart){
            return "Slats angle position unknown, please first opens the blinds completely."
          } else {
            my $shutTimeSet = $shutTime;
            if (defined $a[2]) {
              if ($a[2] =~ m/^[+-]?\d+$/ && $a[2] >= $angleMin && $a[2] <= $angleMax) {
                $anglePos = $a[2];
              } else {
                return "Usage: $a[1] $a[2] is not numeric or out of range";
              }
              splice(@a,2,1);
            } else {
              $anglePos = $angleMax;
            }
            if ($positionStart <= $angleTime * $angleMax / ($angleMax - $angleMin) / $shutTimeSet * 100) {
              $anglePosStart = $angleMax;
            }
            if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
              if ($positionStart < $a[1]) {
                # down
                $angleTime = $angleTime * ($angleMax - $anglePos) / ($angleMax - $angleMin);
                $shutTime = $shutTime  * ($a[1] - $positionStart) / 100 + $angleTime;
                # round up
                $angleTime = int($angleTime) + 1 if ($settingAccuracy == 1 && $angleTime > int($angleTime));
                $shutTime = int($shutTime) + 1 if ($settingAccuracy == 1 && $shutTime > int($shutTime));
                $position = $a[1] + $angleTime / $shutTimeSet * 100;
                if ($position >= 100) {
                  $position = 100;
                  $shutTime = $shutTimeCloses if (AttrVal($name, 'calAtEndpoints', 'no') eq 'yes');
                }
                $shutCmd = 2;
                if ($angleTime) {
                  my @timerCmd = ($name, "up", $angleTime);
                  my %par = (hash => $hash, timerCmd => \@timerCmd);
                  InternalTimer(gettimeofday() + $shutTime + 1, "EnOcean_TimerSet", \%par, 0);
                }
              } elsif ($positionStart > $a[1]) {
                # up
                $angleTime = $angleTime * ($anglePos - $angleMin) /($angleMax - $angleMin);
                $shutTime = $shutTime * ($positionStart - $a[1]) / 100 + $angleTime;
                # round up
                $angleTime = int($angleTime) + 1 if ($settingAccuracy == 1 && $angleTime > int($angleTime));
                $shutTime = int($shutTime) + 1 if ($settingAccuracy == 1 && $shutTime > int($shutTime));
                $position = $a[1] - $angleTime / $shutTimeSet * 100;
                if ($position <= 0) {
                  $position = 0;
                  $anglePos = 0;
                  $shutTime = $shutTimeCloses if (AttrVal($name, 'calAtEndpoints', 'no') eq 'yes');
                }
                $shutCmd = 1;
                if ($angleTime && $a[1] > 0) {
                  my @timerCmd = ($name, "down", $angleTime);
                  my %par = (hash => $hash, timerCmd => \@timerCmd);
                  InternalTimer(gettimeofday() + $shutTime + 1, "EnOcean_TimerSet", \%par, 0);
                }
              } else {
                if ($anglePosStart > $anglePos) {
                  # up >> reduce slats angle
                  $shutTime = $angleTime * ($anglePosStart - $anglePos)/($angleMax - $angleMin);
                  # round up
                  $shutTime = int($shutTime) + 1 if ($settingAccuracy == 1 && $shutTime > int($shutTime));
                  $shutCmd = 1;
                } elsif ($anglePosStart < $anglePos) {
                  # down >> enlarge slats angle
                  $shutTime = $angleTime * ($anglePos - $anglePosStart) /($angleMax - $angleMin);
                  # round up
                  $shutTime = int($shutTime) + 1 if ($settingAccuracy == 1 && $shutTime > int($shutTime));
                  $shutCmd = 2;
                } else {
                  # position and slats angle ok
                  $data = '00000008';
                  $shutCmd = 0;
                  $updateState = 3;
                }
              }
              if ($position == 0) {
                readingsSingleUpdate($hash, "endPosition", "open", 1);
                $cmd = "open";
              } elsif ($position == 100) {
                readingsSingleUpdate($hash, "endPosition", "closed", 1);
                $cmd = "closed";
              } else {
                readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
                $cmd = "not_reached";
              }
              readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
              readingsSingleUpdate($hash, "position", sprintf("%d", $position), 1);
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
        } elsif ($cmd eq "anglePos") {
          if (!defined $positionStart) {
            return "Position unknown, please first opens the blinds completely."
          } elsif ($angleTime > 0 && !defined $anglePosStart){
            return "Slats angle position unknown, please first opens the blinds completely."
          } else {
            if (defined $a[1]) {
              if ($a[1] =~ m/^[+-]?\d+$/ && $a[1] >= $angleMin && $a[1] <= $angleMax) {
                $anglePos = $a[1];
                shift(@a);
                if ($anglePosStart > $anglePos) {
                  # up >> reduce slats angle
                  $shutTime = $angleTime * ($anglePosStart - $anglePos)/($angleMax - $angleMin);
                  # round up
                  $shutTime = int($shutTime) + 1 if ($settingAccuracy == 1 && $shutTime > int($shutTime));
                  $shutCmd = 1;
                } elsif ($anglePosStart < $anglePos) {
                  # down >> enlarge slats angle
                  $shutTime = $angleTime * ($anglePos - $anglePosStart) /($angleMax - $angleMin);
                  # round up
                  $shutTime = int($shutTime) + 1 if ($settingAccuracy == 1 && $shutTime > int($shutTime));
                  $shutCmd = 2;
                } else {
                  # slats angle ok
                  $data = '00000008';
                  $shutCmd = 0;
                  $updateState = 3;
                }
                readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
              } else {
                return "Usage: $a[1] is not numeric or out of range";
              }
            } else {
              return "Usage: $cmd values are missing";
            }
          }
        } elsif ($cmd eq "local") {
          if ($a[1]) {
            return "Usage: $cmd [learn]" if ($a[1] ne "learn");
            if ($a[1] eq "learn") {
              $setCmd = $setCmd | 0x20;
            }
            shift(@a);
          }
          $updateState = 0;
          $data = sprintf "%04X%02X%02X", int($shutTime * $settingAccuracy), $shutCmd, $setCmd;

        } else {
          return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "position:slider,0,5,100 anglePos:slider,-180,5,180 closes:noArg down local:learn opens:noArg stop:noArg teach:noArg up"
        }
        if ($shutCmd || $cmd eq "stop") {
          #$updateState = 0;
          $data = sprintf "%04X%02X%02X", int($shutTime * $settingAccuracy), $shutCmd, $setCmd;
        }
        Log3 $name, 3, "EnOcean set $name $cmd";
      }

    } elsif ($st eq "actuator.01") {
      # Electronic switches and dimmers with Energy Measurement and Local Control
      # (D2-01-00 - D2-01-14)
      $rorg = "D2";
      #$updateState = 0;
      my $cmdID;
      my $channel;
      my $dimValTimer = 0;
      my $outputVal;

      if ($cmd =~ m/^\d+$/) {
        # interpretive numeric value as dimming
        unshift(@a, 'dim');
        $cmd = 'dim';
      }

      if ($cmd eq "on") {
        shift(@a);
        $cmdID = 1;
        my $dimValueOn = AttrVal($name, "dimValueOn", 100);
        if ($dimValueOn eq "stored") {
          $outputVal = ReadingsVal($name, "dimValueStored", 100);
          if ($outputVal < 1) {
            $outputVal = 100;
            readingsSingleUpdate ($hash, "dimValueStored", $outputVal, 1);
          }
        } elsif ($dimValueOn eq "last") {
          $outputVal = ReadingsVal ($name, "dimValueLast", 100);
          if ($outputVal < 1) { $outputVal = 100; }
        } else {
          if ($dimValueOn !~ m/^[+-]?\d+$/) {
            $outputVal = 100;
          } elsif ($dimValueOn > 100) {
            $outputVal = 100;
          } elsif ($dimValueOn < 1) {
            $outputVal = 1;
          } else {
            $outputVal = $dimValueOn;
          }
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name dim.*");
          readingsSingleUpdate($hash, "channelAll", "on", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          readingsSingleUpdate($hash, "channelInput", "on", 1);
          readingsSingleUpdate($hash, "dimInput", $outputVal, 1);
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name dim.*");
          readingsSingleUpdate($hash, "channelAll", "on", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {
          readingsSingleUpdate($hash, "channel" . $channel, "on", 1);
          readingsSingleUpdate($hash, "dim" . $channel, $outputVal, 1);
        } else {
          return "$cmd $channel wrong, choose 0...29|all|input.";
        }
        #readingsSingleUpdate($hash, "state", "on", 1);
        $data = sprintf "%02X%02X%02X", $cmdID, $dimValTimer << 5 | $channel, $outputVal;

      } elsif ($cmd eq "off") {
        shift(@a);
        $cmdID = 1;
        $outputVal = 0;
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name dim.*");
          readingsSingleUpdate($hash, "channelAll", "off", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          readingsSingleUpdate($hash, "channelInput", "off", 1);
          readingsSingleUpdate($hash, "dimInput", $outputVal, 1);
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name dim.*");
          readingsSingleUpdate($hash, "channelAll", "off", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
          readingsSingleUpdate($hash, "channel" . $channel, "off", 1);
          readingsSingleUpdate($hash, "dim" . $channel, $outputVal, 1);
        } else {
          return "$cmd $channel wrong, choose 0...39|all|input.";
        }
        #readingsSingleUpdate($hash, "state", "off", 1);
        $data = sprintf "%02X%02X%02X", $cmdID, $dimValTimer << 5 | $channel, $outputVal;

      } elsif ($cmd eq "dim") {
        shift(@a);
        $cmdID = 1;
        $outputVal = shift(@a);
        if (!defined $outputVal || $outputVal !~ m/^[+-]?\d+$/ || $outputVal < 0 || $outputVal > 100) {
          return "Usage: $cmd variable is not numeric or out of range.";
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel) {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name dim.*");
          if ($outputVal == 0) {
            readingsSingleUpdate($hash, "channelAll", "off", 1);
          } else {
            readingsSingleUpdate($hash, "channelAll", "on", 1);
          }
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } else {
          if ($channel eq "all") {
            CommandDeleteReading(undef, "$name channel.*");
            CommandDeleteReading(undef, "$name dim.*");
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channelAll", "off", 1);
            } else {
              readingsSingleUpdate($hash, "channelAll", "on", 1);
            }
            readingsSingleUpdate($hash, "dim", $outputVal, 1);
            $channel = 30;
          } elsif ($channel eq "input" || $channel + 0 == 31) {
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channelInput", "off", 1);
            } else {
              readingsSingleUpdate($hash, "channelInput", "on", 1);
            }
            readingsSingleUpdate($hash, "dimInput", $outputVal, 1);
            $channel = 31;
          } elsif ($channel + 0 >= 30) {
            CommandDeleteReading(undef, "$name channel.*");
            CommandDeleteReading(undef, "$name dim.*");
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channelAll", "off", 1);
            } else {
              readingsSingleUpdate($hash, "channelAll", "on", 1);
            }
            readingsSingleUpdate($hash, "dim", $outputVal, 1);
            $channel = 30;
          } elsif ($channel >= 0 && $channel <= 29) {
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channel" . $channel, "off", 1);
            } else {
              readingsSingleUpdate($hash, "channel" . $channel, "on", 1);
            }
            readingsSingleUpdate($hash, "dim" . $channel, $outputVal, 1);
          } else {
            return "Usage: $cmd $channel wrong, choose 0...39|all|input.";
          }
          $dimValTimer = shift(@a);
          if (defined $dimValTimer) {
            if ($dimValTimer eq "switch") {
              $dimValTimer = 0;
            } elsif ($dimValTimer eq "stop") {
              $dimValTimer = 4;
            } elsif ($dimValTimer =~ m/^[1-3]$/) {

            } else {
              return "Usage: $cmd <channel> $dimValTimer wrong, choose 1..3|switch|stop.";
            }
          } else {
            $dimValTimer = 0;
          }
        }
        if ($outputVal == 0) {
          $cmd = "off";
          #readingsSingleUpdate($hash, "state", "off", 1);
        } else {
          $cmd = "on";
          #readingsSingleUpdate($hash, "state", "on", 1);
        }
        $data = sprintf "%02X%02X%02X", $cmdID, $dimValTimer << 5 | $channel, $outputVal;

      } elsif ($cmd eq "local") {
        shift(@a);
        $updateState = 0;
        $cmdID = 2;
        # same configuration for all channels
        $channel = 30;
        my $dayNight = ReadingsVal($name, "dayNight", "day");
        my $dayNightCmd = ($dayNight eq "night")? 1:0;
        my $defaultState = ReadingsVal($name, "defaultState", "off");
        my $defaultStateCmd;
        if ($defaultState eq "off") {
          $defaultStateCmd = 0;
        } elsif ($defaultState eq "on") {
          $defaultStateCmd = 1;
        } elsif ($defaultState eq "last") {
          $defaultStateCmd = 2;
        } else {
          $defaultStateCmd = 0;
        }
        my $localControl = ReadingsVal($name, "localControl", "enabled");
        my $localControlCmd = ($localControl eq "enabled")? 1:0;
        my $overCurrentShutdown = ReadingsVal($name, "overCurrentShutdown", "off");
        my $overCurrentShutdownCmd = ($overCurrentShutdown eq "restart")? 1:0;
        my $overCurrentShutdownReset = "not_active";
        my $overCurrentShutdownResetCmd = 0;
        my $rampTime1 = ReadingsVal($name, "rampTime1", 0);
        my $rampTime1Cmd = $rampTime1 * 2;
        if ($rampTime1Cmd <= 0) {
           $rampTime1Cmd = 0;
        } elsif ($rampTime1Cmd >= 15) {
           $rampTime1Cmd = 15;
        }
        my $rampTime2 = ReadingsVal($name, "rampTime2", 0);
        my $rampTime2Cmd = $rampTime2 * 2;
        if ($rampTime2Cmd <= 0) {
           $rampTime2Cmd = 0;
        } elsif ($rampTime2Cmd >= 15) {
           $rampTime2Cmd = 15;
        }
        my $rampTime3 = ReadingsVal($name, "rampTime3", 0);
        my $rampTime3Cmd = $rampTime3 * 2;
        if ($rampTime3Cmd <= 0) {
           $rampTime3Cmd = 0;
        } elsif ($rampTime3Cmd >= 15) {
           $rampTime3Cmd = 15;
        }
        my $teachInDev = ReadingsVal($name, "teachInDev", "disabled");
        my $teachInDevCmd = ($teachInDev eq "enabled")? 1:0;
        my $powerFailure = ReadingsVal($name, "powerFailure", "disabled");
        my $powerFailureCmd = ($powerFailure eq "enabled") ? 1:0;
        my $localCmd = shift(@a);
        my $localCmdVal = shift(@a);
        if ($localCmd eq "dayNight") {
          if ($localCmdVal eq "day") {
            $dayNight = "day";
            $dayNightCmd = 0;
          } elsif ($localCmdVal eq "night") {
            $dayNight = "night";
            $dayNightCmd = 1;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose day night.";
          }
        } elsif ($localCmd eq "defaultState"){
          if ($localCmdVal eq "off") {
            $defaultState = "off";
            $defaultStateCmd = 0;
          } elsif ($localCmdVal eq "on") {
            $defaultState = "on";
            $defaultStateCmd = 1;
          } elsif ($localCmdVal eq "last") {
            $defaultState = "last";
            $defaultStateCmd = 2;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose on off last.";
          }
        } elsif ($localCmd eq "localControl"){
          if ($localCmdVal eq "disabled") {
            $localControl = "disabled";
            $localControlCmd = 0;
          } elsif ($localCmdVal eq "enabled") {
            $localControl = "enabled";
            $localControlCmd = 1;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose disabled enabled.";
          }
        } elsif ($localCmd eq "overCurrentShutdown"){
          if ($localCmdVal eq "off") {
            $overCurrentShutdown = "off";
            $overCurrentShutdownCmd = 0;
          } elsif ($localCmdVal eq "restart") {
            $overCurrentShutdown = "restart";
            $overCurrentShutdownCmd = 1;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose off restart.";
          }
        } elsif ($localCmd eq "overCurrentShutdownReset"){
          if ($localCmdVal eq "not_active") {
            $overCurrentShutdownReset = "not_active";
            $overCurrentShutdownResetCmd = 0;
          } elsif ($localCmdVal eq "trigger") {
            $overCurrentShutdownReset = "trigger";
            $overCurrentShutdownResetCmd = 1;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose not_active trigger.";
          }
        } elsif ($localCmd eq "rampTime1"){
          if ($localCmdVal >= 0 || $localCmdVal <= 7.5) {
            $rampTime1 = $localCmdVal;
            $rampTime1Cmd = $localCmdVal * 2;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose 0, 0.5, ..., 7, 7.5";
          }
        } elsif ($localCmd eq "rampTime2"){
          if ($localCmdVal >= 0 || $localCmdVal <= 7.5) {
            $rampTime2 = $localCmdVal;
            $rampTime2Cmd = $localCmdVal * 2;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose 0, 0.5, ..., 7, 7.5";
          }
        } elsif ($localCmd eq "rampTime3"){
          if ($localCmdVal >= 0 || $localCmdVal <= 7.5) {
            $rampTime3 = $localCmdVal;
            $rampTime3Cmd = $localCmdVal * 2;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose 0, 0.5, ..., 7, 7.5";
          }
        } elsif ($localCmd eq "teachInDev"){
          if ($localCmdVal eq "disabled") {
            $teachInDev = "disabled";
            $teachInDevCmd = 0;
          } elsif ($localCmdVal eq "enabled") {
            $teachInDev = "enabled";
            $teachInDevCmd = 1;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose disabled enabled.";
          }
        } elsif ($localCmd eq "powerFailure"){
          if ($localCmdVal eq "disabled") {
            $powerFailure = "disabled";
            $powerFailureCmd = 0;
          } elsif ($localCmdVal eq "enabled") {
            $powerFailure = "enabled";
            $powerFailureCmd = 1;
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose disabled enabled.";
          }
        } else {
          return "Usage: $cmd <localCmd> wrong, choose dayNight|defaultState|localControl|" .
          "overCurrentShutdown|overCurrentShutdownReset|rampTime1|rampTime2|rampTime3|teachInDev|powerFailure.";        }
        readingsSingleUpdate($hash, "dayNight", $dayNight, 1);
        readingsSingleUpdate($hash, "defaultState", $defaultState, 1);
        readingsSingleUpdate($hash, "localControl", $localControl, 1);
        readingsSingleUpdate($hash, "overCurrentShutdown", $overCurrentShutdown, 1);
        readingsSingleUpdate($hash, "overCurrentShutdownReset", $overCurrentShutdownReset, 1);
        readingsSingleUpdate($hash, "powerFailure", $powerFailure, 1);
        readingsSingleUpdate($hash, "rampTime1", $rampTime1, 1);
        readingsSingleUpdate($hash, "rampTime2", $rampTime2, 1);
        readingsSingleUpdate($hash, "rampTime3", $rampTime3, 1);
        readingsSingleUpdate($hash, "teachInDev", $teachInDev, 1);
        $data = sprintf "%02X%02X%02X%02X", $teachInDevCmd << 7 | $cmdID,
                  $overCurrentShutdownCmd << 7 | $overCurrentShutdownResetCmd << 6 | $localControlCmd << 5 | $channel,
                  int($rampTime2Cmd) << 4 | int($rampTime3Cmd),
                  $dayNightCmd << 7 | $powerFailureCmd << 6 | $defaultStateCmd << 4 | int($rampTime1Cmd);
      } elsif ($cmd eq "measurement") {
        shift(@a);
        $updateState = 0;
        $cmdID = 5;
        # same configuration for all channels
        $channel = 30;
        my $measurementMode = ReadingsVal($name, "measurementMode", "energy");
        my $measurementModeCmd = ($measurementMode eq "power")? 1:0;
        my $measurementReport = ReadingsVal($name, "measurementReport", "query");
        my $measurementReportCmd = ($measurementReport eq "auto")? 1:0;
        my $measurementReset = "not_active";
        my $measurementResetCmd = 0;
        my $measurementDelta = int(ReadingsVal($name, "measurementDelta", 0));
        if ($measurementDelta <= 0) {
           $measurementDelta = 0;
        } elsif ($measurementDelta >= 4095) {
           $measurementDelta = 4095;
        }
        my $unit = ReadingsVal($name, "measurementUnit", "Ws");
        my $unitCmd;
        if ($unit eq "Ws") {
          $unitCmd = 0;
        } elsif ($unit eq "Wh") {
          $unitCmd = 1;
        } elsif ($unit eq "KWh") {
          $unitCmd = 2;
        } elsif ($unit eq "W") {
          $unitCmd = 3;
        } elsif ($unit eq "KW") {
          $unitCmd = 4;
        } else {
          $unitCmd = 0;
        }
        my $responseTimeMax = ReadingsVal($name, "responseTimeMax", 10);
        my $responseTimeMaxCmd = $responseTimeMax / 10;
        if ($responseTimeMaxCmd <= 1) {
           $responseTimeMaxCmd = 1;
        } elsif ($responseTimeMaxCmd >= 255) {
           $responseTimeMaxCmd = 255;
        }
        my $responseTimeMin = ReadingsVal($name, "responseTimeMin", 1);
        if ($responseTimeMin <= 1) {
           $responseTimeMin = 1;
        } elsif ($responseTimeMin >= 255) {
           $responseTimeMin = 255;
        }
        my $measurementCmd = shift(@a);
        my $measurementCmdVal = shift(@a);
        if (!defined $measurementCmdVal) {
          return "Usage: $cmd $measurementCmd <value> needed.";
        }
        if (!defined $measurementCmd) {
          return "Usage: $cmd <measurementCmd> wrong, choose mode|report|" .
                 "reset|delta|unit|responseTimeMax|responseTimeMin.";
        } elsif ($measurementCmd eq "mode") {
          if ($measurementCmdVal eq "energy") {
            $measurementMode = "energy";
            $measurementModeCmd = 0;
          } elsif ($measurementCmdVal eq "power") {
            $measurementMode = "power";
            $measurementModeCmd = 1;
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose energy power.";
          }
        } elsif ($measurementCmd eq "report"){
          if ($measurementCmdVal eq "query") {
            $measurementReport = "query";
            $measurementReportCmd = 0;
          } elsif ($measurementCmdVal eq "auto") {
            $measurementReport = "auto";
            $measurementReportCmd = 1;
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose query auto.";
          }
        } elsif ($measurementCmd eq "reset"){
          if ($measurementCmdVal eq "not_active") {
            $measurementReset = "not_active";
            $measurementResetCmd = 0;
          } elsif ($measurementCmdVal eq "trigger") {
            $measurementReset = "trigger";
            $measurementResetCmd = 1;
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose not_active trigger.";
          }
        } elsif ($measurementCmd eq "unit"){
          if ($measurementCmdVal eq "Ws") {
            $unit = "Ws";
            $unitCmd = 0;
          } elsif ($measurementCmdVal eq "Wh") {
            $unit = "Wh";
            $unitCmd = 1;
          } elsif ($measurementCmdVal eq "KWh") {
            $unit = "KWh";
            $unitCmd = 2;
          } elsif ($measurementCmdVal eq "W") {
            $unit = "W";
            $unitCmd = 3;
          } elsif ($measurementCmdVal eq "KW") {
            $unit = "KW";
            $unitCmd = 4;
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose Ws Wh KWh W KW.";
          }
        } elsif ($measurementCmd eq "delta"){
          if ($measurementCmdVal >= 0 || $measurementCmdVal <= 4095) {
            $measurementDelta = int($measurementCmdVal);
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose 0 ... 4095";
          }
        } elsif ($measurementCmd eq "responseTimeMax"){
          if ($measurementCmdVal >= 10 || $measurementCmdVal <= 2550) {
            $responseTimeMax = int($measurementCmdVal);
            $responseTimeMaxCmd = int($measurementCmdVal) / 10;
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose 10 ... 2550";
          }
        } elsif ($measurementCmd eq "responseTimeMin"){
          if ($measurementCmdVal >= 1 || $measurementCmdVal <= 255) {
            $responseTimeMin = int($measurementCmdVal);
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose 1 ... 255";
          }
        } else {
          return "Usage: $cmd <measurementCmd> wrong, choose mode|report|" .
          "reset|delta|unit|responseTimeMax|responseTimeMin.";
        }
        readingsSingleUpdate($hash, "measurementMode", $measurementMode, 1);
        readingsSingleUpdate($hash, "measurementReport", $measurementReport, 1);
        readingsSingleUpdate($hash, "measurementReset", $measurementReset, 1);
        readingsSingleUpdate($hash, "measurementDelta", $measurementDelta, 1);
        readingsSingleUpdate($hash, "measurementUnit", $unit, 1);
        readingsSingleUpdate($hash, "responseTimeMax", $responseTimeMax, 1);
        readingsSingleUpdate($hash, "responseTimeMin", $responseTimeMin, 1);
        $data = sprintf "%02X%02X%02X%02X%02X%02X", $cmdID,
                  $measurementReportCmd << 7 | $measurementResetCmd << 6 | $measurementModeCmd << 5 | $channel,
                  ($measurementDelta & 0x000F) << 4 | $unitCmd, ($measurementDelta & 0x0FF0) >> 4,
                  $responseTimeMax, $responseTimeMin;

      } elsif ($cmd eq "roomCtrlMode") {
        shift(@a);
        $updateState = 0;
        $cmdID = 8;
        my $roomCtrlModeCmd = shift(@a);
        return "$cmd <channel> <roomCtrlMode> is missing, choose off|comfort|comfort-1|comfort-2|economy|buildingProtection." if (!defined $roomCtrlModeCmd);
        if ($roomCtrlModeCmd eq "off") {
          $roomCtrlModeCmd = 0;
        } elsif ($roomCtrlModeCmd eq "comfort") {
          $roomCtrlModeCmd = 1;
        } elsif ($roomCtrlModeCmd eq "economy") {
          $roomCtrlModeCmd = 2;
        } elsif ($roomCtrlModeCmd eq "buildingProtection") {
          $roomCtrlModeCmd = 3;
        } elsif ($roomCtrlModeCmd eq "comfort-1") {
          $roomCtrlModeCmd = 4;
        } elsif ($roomCtrlModeCmd eq "comfort-2") {
          $roomCtrlModeCmd = 5;
        } else {
          return "$cmd <channel> <roomCtrlMode> wrong, choose off|comfort|comfort-1|comfort-2|economy|buildingProtection.";
        }
        $data = sprintf "%02X%02X", $cmdID, $roomCtrlModeCmd;

      } elsif ($cmd eq "autoOffTime") {
        shift(@a);
        $updateState = 0;
        $cmdID = 0x0B;
        $outputVal = int(shift(@a) * 10);
        if (!defined $outputVal || $outputVal !~ m/^[+-]?\d+$/ || $outputVal < 0 || $outputVal > 65534) {
          return "Usage: $cmd variable is not numeric or out of range.";
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name autoOffTime.*");
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name autoOffTime.*");
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
        } else {
          return "$cmd $channel wrong, choose 0...31|all|input.";
        }
        my $extSwitchMode = ReadingsVal($name, "extSwitchMode", 'unavailable');
        my %extSwitchMode = (
          "unavailable" => 0,
          "switch" => 1,
          "pushbutton" => 2,
          "auto" => 3
        );
        if (exists $extSwitchMode{$extSwitchMode}) {
          $extSwitchMode = $extSwitchMode{$extSwitchMode};
        } else {
          $extSwitchMode = 0;
        }
        my $extSwitchType = ReadingsVal($name, "extSwitchType", 'toggle') eq 'direction' ? 1 : 0;
        $data = sprintf "%02X%02X%04XFFFF%02X", $cmdID, $channel, $outputVal, $extSwitchMode << 6 | $extSwitchType << 5;

      } elsif ($cmd eq "delayOffTime") {
        shift(@a);
        $updateState = 0;
        $cmdID = 0x0B;
        $outputVal = int(shift(@a) * 10);
        if (!defined $outputVal || $outputVal !~ m/^[+-]?\d+$/ || $outputVal < 0 || $outputVal > 65534) {
          return "Usage: $cmd variable is not numeric or out of range.";
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name delayOffTime.*");
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name delayOffTime.*");
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
        } else {
          return "$cmd $channel wrong, choose 0...31|all|input.";
        }
        my $extSwitchMode = ReadingsVal($name, "extSwitchMode", 'unavailable');
        my %extSwitchMode = (
          "unavailable" => 0,
          "switch" => 1,
          "pushbutton" => 2,
          "auto" => 3
        );
        if (exists $extSwitchMode{$extSwitchMode}) {
          $extSwitchMode = $extSwitchMode{$extSwitchMode};
        } else {
          $extSwitchMode = 0;
        }
        my $extSwitchType = ReadingsVal($name, "extSwitchType", 'toggle') eq 'direction' ? 1 : 0;
        $data = sprintf "%02X%02XFFFF%04X%02X", $cmdID, $channel, $outputVal, $extSwitchMode << 6 | $extSwitchType << 5;

      } elsif ($cmd eq "extSwitchMode") {
        shift(@a);
        $updateState = 0;
        $cmdID = 0x0B;
        my $extSwitchMode = shift(@a);
        return "Usage: $cmd variable is missing, choose unavailable|switch|pushbutton|auto." if (!defined $extSwitchMode);
        my %extSwitchMode = (
          "unavailable" => 0,
          "switch" => 1,
          "pushbutton" => 2,
          "auto" => 3
        );
        if (exists $extSwitchMode{$extSwitchMode}) {
          $extSwitchMode = $extSwitchMode{$extSwitchMode};
        } else {
          return "Usage: $cmd variable wrong, choose unavailable|switch|pushbutton|auto.";
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name extSwitchMode.*");
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name extSwitchMode.*");
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
        } else {
          return "$cmd $channel wrong, choose 0...31|all|input.";
        }
        my $extSwitchType = ReadingsVal($name, "extSwitchType", 'toggle') eq 'direction' ? 1 : 0;
        $data = sprintf "%02X%02XFFFFFFFF%02X", $cmdID, $channel, $extSwitchMode << 6 | $extSwitchType << 5;

      } elsif ($cmd eq "extSwitchType") {
        shift(@a);
        $updateState = 0;
        $cmdID = 0x0B;
        my $extSwitchType = shift(@a);
        return "Usage: $cmd variable is missing, choose toggle|direction." if (!defined $extSwitchType);
        my %extSwitchType = (
          "toggle" => 0,
          "direction" => 1,
        );
        if (exists $extSwitchType{$extSwitchType}) {
          $extSwitchType = $extSwitchType{$extSwitchType};
        } else {
          return "Usage: $cmd variable wrong, choose toggle|direction.";
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name extSwitchMode.*");
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name extSwitchMode.*");
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
        } else {
          return "$cmd $channel wrong, choose 0...31|all|input.";
        }
        my $extSwitchMode = ReadingsVal($name, "extSwitchMode", 'unavailable');
        my %extSwitchMode = (
          "unavailable" => 0,
          "switch" => 1,
          "pushbutton" => 2,
          "auto" => 3
        );
        if (exists $extSwitchMode{$extSwitchMode}) {
          $extSwitchMode = $extSwitchMode{$extSwitchMode};
        } else {
          $extSwitchMode = 0;
        }
        $data = sprintf "%02X%02XFFFFFFFF%02X", $cmdID, $channel, $extSwitchMode << 6 | $extSwitchType << 5;

      } elsif ($cmd eq "special") {
        $rorg = "D1";
        shift(@a);
        $updateState = 0;
        my $repeaterActive = 0;
        my $repeaterLevel = ReadingsVal($name, "repeaterLevel", "off");
        if ($repeaterLevel eq "off") {
	  $repeaterLevel = 0;
	} else {
	  $repeaterActive = 1;
	}
        my $specialCmd = shift(@a);
        if ($manufID eq "046") {
          if (!defined $specialCmd) {
            return "$cmd <command> wrong, choose repeaterLevel.";
          } elsif ($specialCmd eq "repeaterLevel") {
            $cmdID = 8;
            $repeaterLevel = shift(@a);
            if (defined $repeaterLevel && $repeaterLevel =~ m/^off|1|2$/) {
              if ($repeaterLevel eq "off") {
                $repeaterLevel = 0;
              } else {
                $repeaterActive = 1;
              }
            } else {
              return "Usage: repeaterLevel is wrong";
            }
          } else {
            return "$cmd $specialCmd <arg> wrong, choose repeaterLevel off|1|2.";
          }
        }
        readingsSingleUpdate($hash, "repeaterLevel", $repeaterLevel, 1);
        $data = sprintf "0046%02X%02X%02X", $cmdID, $repeaterActive, $repeaterLevel;

      } else {
        if ($manufID =~ m/^046$/) {
          $cmdList .= "dim:slider,0,1,100 on off autoOffTime delayOffTime extSwitchMode extSwitchType local measurement roomCtrlMode:off,buildingProtection,economy,comfort-2,comfort-1,comfort special";
        } else {
          $cmdList .= "dim:slider,0,1,100 on off autoOffTime delayOffTime extSwitchMode extSwitchType local measurement roomCtrlMode:off,buildingProtection,economy,comfort-2,comfort-1,comfort";
        }
        return SetExtensions ($hash, $cmdList, $name, @a);
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st =~ m/^blindsCtrl\.0[01]$/) {
      # Blinds Control for Position and Angle
      # (D2-05-xx)
      $rorg = "D2";
      $updateState = 0;
      my $cmdID;
      my $channel = AttrVal($name, "defaultChannel", 16) - 1;
      my $position = 127;
      my $angle = 127;
      my $repo = AttrVal($name, "reposition", "directly");
      if ($repo eq "directly") {
        $repo = 0;
      } elsif ($repo eq "opens") {
        $repo = 1;
      } elsif ($repo eq "closes") {
        $repo = 2;
      } else {
        $repo = 0;
      }
      my $lock = 0;

      if ($cmd =~ m/^\d+$/) {
        # interpretive numeric value as position
        unshift(@a, 'position');
        $cmd = 'position';
      }

      if ($cmd eq "position") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        if (defined $a[0]) {
          # position value
          if (($a[0] =~ m/^\d+$/) && ($a[0] >= 0) && ($a[0] <= 100)) {
            $position = shift(@a);

            if (defined $a[0]) {
            # angle value
              if (($a[0] =~ m/^\d+$/) && ($a[0] >= 0) && ($a[0] <= 100)) {
                $angle = shift(@a);

                if (defined $a[0]) {
                  # channel
                  $channel = shift(@a);
                  if ($channel =~ m/^all$/) {
                    $channel = 15;
                  } elsif ($channel =~ m/^[1234]$/) {
                    $channel -= 1;
                  } else {
                    return "Usage: $position $angle $channel argument unknown, choose one of 1|2|3|4|all";
                  }

                  if (defined $a[0]) {
                    # reposition value
                    $repo = shift(@a);
                    if ($repo eq "directly") {
                      $repo = 0;
                    } elsif ($repo eq "opens") {
                      $repo = 1;
                    } elsif ($repo eq "closes") {
                      $repo = 2;
                    } else {
                      return "Usage: $position $angle $channel $repo argument unknown, choose one of directly opens closes";
                    }
                  }
                }
                readingsSingleUpdate($hash, "anglePos", $angle, 1);
              } else {
                return "Usage: $position $a[0] is not numeric or out of range";
              }
            }
            readingsSingleUpdate($hash, "state", "in_motion", 1);
          } else {
            return "Usage: $a[0] is not numeric or out of range";
          }
        } else {
          return "Usage: set <name> position <position> [<angle> [<channel> [<repo>]]]";
        }
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "anglePos") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        if (defined $a[0]) {
          if (($a[0] =~ m/^\d+$/) && ($a[0] >= 0) && ($a[0] <= 100)) {
            $angle = shift(@a);
            if (defined $a[0]) {
              # channel
              $channel = shift(@a);
              if ($channel =~ m/^all$/) {
                $channel = 15;
              } elsif ($channel =~ m/^[1234]$/) {
                $channel -= 1;
              } else {
                return "Usage: $angle $channel argument unknown, choose one of 1|2|3|4|all";
              }
            }
            readingsSingleUpdate($hash, "state", "in_motion", 1);
          } else {
            return "Usage: $a[0] is not numeric or out of range";
          }
        } else {
          return "Usage: set <name> anglePos <angle>";
        }
        $repo = 0;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "stop") {
        $cmdID = 2;
        shift(@a);
        if (defined $a[0]) {
          # channel
          $channel = shift(@a);
          if ($channel =~ m/^all$/) {
            $channel = 15;
          } elsif ($channel =~ m/^[1234]$/) {
            $channel -= 1;
          } else {
            return "Usage: stop $channel argument unknown, choose one of 1|2|3|4|all";
          }
        }
        readingsSingleUpdate($hash, "state", "stopped", 1);
        $data = sprintf "%02X", $channel << 4 | $cmdID;

      } elsif ($cmd eq "opens") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        if (defined $a[0]) {
          # channel
          $channel = shift(@a);
          if ($channel =~ m/^all$/) {
            $channel = 15;
          } elsif ($channel =~ m/^[1234]$/) {
            $channel -= 1;
          } else {
            return "Usage: opens $channel argument unknown, choose one of 1|2|3|4|all";
          }
        }
        $position = 0;
        $repo = 0;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "closes") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        if (defined $a[0]) {
          # channel
          $channel = shift(@a);
          if ($channel =~ m/^all$/) {
            $channel = 15;
          } elsif ($channel =~ m/^[1234]$/) {
            $channel -= 1;
          } else {
            return "Usage: closes $channel argument unknown, choose one of 1|2|3|4|all";
          }
        }
        $position = 100;
        $repo = 0;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "unlock") {
        $cmdID = 1;
        shift(@a);
        if (defined $a[0]) {
          # channel
          $channel = shift(@a);
          if ($channel =~ m/^all$/) {
            $channel = 15;
          } elsif ($channel =~ m/^[1234]$/) {
            $channel -= 1;
          } else {
            return "Usage: unlock $channel argument unknown, choose one of 1|2|3|4|all";
          }
        }
        $repo = 0;
        $lock = 7;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "lock") {
        $cmdID = 1;
        shift(@a);
        if (defined $a[0]) {
          # channel
          $channel = shift(@a);
          if ($channel =~ m/^all$/) {
            $channel = 15;
          } elsif ($channel =~ m/^[1234]$/) {
            $channel -= 1;
          } else {
            return "Usage: lock $channel argument unknown, choose one of 1|2|3|4|all";
          }
        }
        $repo = 0;
        $lock = 1;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "alarm") {
        $cmdID = 1;
        shift(@a);
        if (defined $a[0]) {
          # channel
          $channel = shift(@a);
          if ($channel =~ m/^all$/) {
            $channel = 15;
          } elsif ($channel =~ m/^[1234]$/) {
            $channel -= 1;
          } else {
            return "Usage: alarm $channel argument unknown, choose one of 1|2|3|4|all";
          }
        }
        $repo = 0;
        $lock = 2;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } else {
        $cmdList .= "position:slider,0,1,100 anglePos:slider,0,1,100 stop opens closes lock unlock alarm";
        return "Unknown argument $cmd, choose one of $cmdList";
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "multisensor.01") {
      # Multisensor Windows Handle
      # (D2-06-01)
      $rorg = "D2";
      $updateState = 2;
      my $waitingCmds = ReadingsVal($name, "waitingCmds", undef);
      if (defined $waitingCmds) {
        # check presence state
        $waitingCmds = ReadingsVal($name, "presence", "present") eq "absent" ? $waitingCmds & 0xDF | 32 : $waitingCmds & 0xDF;
      } else {
        $waitingCmds = ReadingsVal($name, "presence", "present") eq "absent" ? 32 : 0;
      }
      if ($cmd eq "presence") {
        # set presence
        if (defined $a[1]) {
          if ($a[1] =~ m/^absent$/) {
            readingsSingleUpdate($hash, "presence", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds & 0xDF | 32, 0);
          } elsif ($a[1] =~ m/^present$/) {
            readingsSingleUpdate($hash, "presence", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds & 0xDF, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
      } elsif ($cmd eq "handleClosedClick") {
        # set battery closed click
        if (defined $a[1]) {
          if ($a[1] =~ m/^disable$/) {
            readingsSingleUpdate($hash, "handleClosedClick", $a[1] . 'd', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds & 0xE7 | 8, 0);
          } elsif ($a[1] =~ m/^enable$/) {
            readingsSingleUpdate($hash, "handleClosedClick", $a[1] . 'd', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds & 0xE7 | 16, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
      } elsif ($cmd eq "batteryLowClick") {
        # set battery click low
        if (defined $a[1]) {
          if ($a[1] =~ m/^disable$/) {
            readingsSingleUpdate($hash, "batteryLowClick", $a[1] . 'd', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds & 0xF9 | 2, 0);
          } elsif ($a[1] =~ m/^enable$/) {
            readingsSingleUpdate($hash, "batteryLowClick", $a[1] . 'd', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds & 0xF9 | 4, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
      } elsif ($cmd eq "updateInterval") {
        # set update interval
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 5 && $a[1] <= 65535) {
            readingsSingleUpdate($hash, "updateInterval", $a[1], 1);
            readingsSingleUpdate($hash, "updateIntervalSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds | 1, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
      } elsif ($cmd eq "blinkInterval") {
        # set blick interval
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 3 && $a[1] <= 255) {
            readingsSingleUpdate($hash, "blinkInterval", $a[1], 1);
            readingsSingleUpdate($hash, "blinkIntervalSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", $waitingCmds | 1, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
      } elsif ($cmd eq "teachSlave") {
        # teach slave
        $updateState = 0;
        $destinationID = "FFFFFFFF";
        if (defined $a[1]) {
          if ($a[1] =~ m/^contact$/) {
            $rorg = "D5";
            $data = '00';
            ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDefW", "biDir");
            readingsSingleUpdate($hash, "teachSlave", '1BS teach-in sent', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
          } elsif ($a[1] =~ m/^windowHandleOpen$/) {
            $rorg = "F6";
            $data = 'E0';
            $status = '20';
            ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDefH", "biDir");
            readingsSingleUpdate($hash, "teachSlave", 'RPS teach-in sent', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
          } elsif ($a[1] =~ m/^windowHandleClosed$/) {
            $rorg = "F6";
            $data = 'F0';
            $status = '20';
            ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDefH", "biDir");
            readingsSingleUpdate($hash, "teachSlave", 'RPS teach-in sent', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
          } elsif ($a[1] =~ m/^windowHandleTilted$/) {
            $rorg = "F6";
            $data = 'D0';
            $status = '20';
            ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDefH", "biDir");
            readingsSingleUpdate($hash, "teachSlave", 'RPS teach-in sent', 1);
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong";
          }
        }
      } else {
        $cmdList .= "presence:absent,present handleClosedClick:enable,disable batteryLowClick:enable,disable " .
                    "updateInterval blinkInterval teachSlave:contact,windowHandleClosed,windowHandleOpen,windowHandleTilted";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "roomCtrlPanel.00") {
      # Room Control Panel
      # (D2-10-00 - D2-10-02)
      $rorg = "D2";
      $updateState = 2;
      if ($cmd eq "desired-temp"|| $cmd eq "setpointTemp") {
        if (defined $a[1]) {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 40)) {
            $a[1] = sprintf "%0.1f", $a[1];
            readingsSingleUpdate($hash, "setpointTemp", $a[1], 1);
            readingsSingleUpdate($hash, "setpointTempSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name setpointTemp $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
           return "Usage: $a[1] is not numeric or out of range";
         }
        }

      } elsif ($cmd eq "economyTemp" || $cmd eq "preComfortTemp" || $cmd eq "buildingProtectionTemp" || $cmd eq "comfortTemp") {
        if (defined $a[1]) {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 40)) {
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            $cmd =~ s/(\b)([a-z])/$1\u$2/g;
            $a[1] = sprintf "%0.1f", $a[1];
            readingsSingleUpdate($hash, "setpoint" . $cmd, $a[1], 1);
            readingsSingleUpdate($hash, "setpoint" . $cmd . "Set", $a[1], 0);
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 8, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }

      } elsif ($cmd eq "fanSpeed") {
        if (defined $a[1]) {
          if ($a[1] >= 0 && $a[1] <= 100) {
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            readingsSingleUpdate($hash, "fanSpeedSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        }

      } elsif ($cmd eq "fanSpeedMode") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(central|local)$/) {
            readingsSingleUpdate($hash, "fanSpeedMode", $a[1], 1);
            readingsSingleUpdate($hash, "fanSpeedModeSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name fanSpeedMode $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }

      } elsif ($cmd eq "cooling") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(on|off|auto|no_change)$/) {
            readingsSingleUpdate($hash, "cooling", $a[1], 1);
            readingsSingleUpdate($hash, "coolingSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name cooling $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }

      } elsif ($cmd eq "heating") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(on|off|auto|no_change)$/) {
            readingsSingleUpdate($hash, "heating", $a[1], 1);
            readingsSingleUpdate($hash, "heatingSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name heating $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }

      } elsif ($cmd eq "roomCtrlMode") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(comfort|preComfort|economy|buildingProtection)$/) {
            readingsSingleUpdate($hash, "roomCtrlMode", $a[1], 1);
            readingsSingleUpdate($hash, "roomCtrlModeSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name roomCtrlMode $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }

      } elsif ($cmd eq "config") {
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 64, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "timeProgram") {
        # delete remote and send new time program
        delete $hash->{helper}{4}{telegramWait};
        for (my $messagePartCntr = 1; $messagePartCntr <= 4; $messagePartCntr ++) {
          if (defined AttrVal($name, "timeProgram" . $messagePartCntr, undef)) {
            $hash->{helper}{4}{telegramWait}{$messagePartCntr} = 1;
            Log3 $name, 3, "EnOcean $name EnOcean_Set timeProgram" . $messagePartCntr . " set";
          }
        }
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 528, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "deleteTimeProgram") {
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 512, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "time") {
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 4, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "window") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^closed|open$/) {
            readingsSingleUpdate($hash, "window", $a[1], 1);
            readingsSingleUpdate($hash, "windowSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name window $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }

      } elsif ($cmd eq "clearCmds") {
        CommandDeleteReading(undef, "$name waitingCmds");
        Log3 $name, 3, "EnOcean set $name $cmd";

      } else {
        $cmdList .= "cooling:auto,off,on,no_change desired-temp setpointTemp:slider,0,1,40 " .
                      "comfortTemp deleteTimeProgram:noArg " .
                      "economyTemp preComfortTemp buildingProtectionTemp config:noArg " .
                      "clearCmds:noArg fanSpeed:slider,0,1,100 heating:auto,off,on,no_change " .
                      "fanSpeedMode:central,local time:noArg " .
                      "roomCtrlMode:comfort,economy,preComfort,buildingProtection timeProgram:noArg window:closed,open";
        return "Unknown argument $cmd, choose one of $cmdList";
      }

    } elsif ($st eq "roomCtrlPanel.01") {
      # Room Control Panel
      # (D2-11-01 - D2-11-08)
      $rorg = "D2";
      $updateState = 0;
      my $cooling = ReadingsVal($name, "colling", 'off');
      my $fanSpeed = ReadingsVal($name, "fanSpeed", 'auto');
      my $heating = ReadingsVal($name, "heating", 'off');
      my $humidity = ReadingsVal($name, "humidity", 0);
      my $occupancy = ReadingsVal($name, "occupancy", 'unoccupied');
      my $setpointBase = ReadingsVal($name, "setpointBase", 20);
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $setpointShift = ReadingsVal($name, "setpointShift", 0);
      my $setpointShiftMax = ReadingsVal($name, "setpointShiftMax", 10);
      my $setpointType = ReadingsVal($name, "setpointType", 'setpointShift');
      my $temperature = ReadingsVal($name, "temperature", 20);
      my $waitingCmds = ReadingsVal($name, "waitingCmds", 0);
      my $window = ReadingsVal($name, "window", 'closed');
      if ($cmd eq "desired-temp"|| $cmd eq "setpointTemp") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+(\.\d)?$/ && $a[1] >= 5 && $a[1] <= 40) {
            $a[1] = sprintf "%d", $a[1];
            readingsBeginUpdate($hash);
            if ($a[1] < 15) {
              $setpointBase = 15;
              $setpointShift =  $a[1] - $setpointBase;
              $setpointShiftMax = $setpointBase - $a[1] if ($setpointShiftMax < -$setpointShift);
              readingsBulkUpdate($hash, "setpointShiftMax", $setpointShiftMax);
            } elsif ($a[1] > 30) {
              $setpointBase = 30;
              $setpointShift =  $a[1] - $setpointBase;
              $setpointShiftMax = $a[1] - $setpointBase  if ($setpointShiftMax < $setpointShift);
              readingsBulkUpdate($hash, "setpointShiftMax", $setpointShiftMax);
            } else {
              $setpointBase = $a[1];
              $setpointShift = 0;
            }
            readingsBulkUpdate($hash, "setpointShift", $setpointShift);
            readingsBulkUpdate($hash, "setpointBase", $setpointBase);
            $setpointTemp = $a[1];
            readingsBulkUpdate($hash, "setpointTemp", $a[1]);
            readingsBulkUpdate($hash, "state", "T: $temperature H: $humidity SPT: $setpointTemp F: $fanSpeed");
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 1);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name setpointTemp $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        } else {
          return "Usage: set <name> setpointTemp 5...40";
        }

      } elsif ($cmd eq "setpointShiftMax") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 1 && $a[1] <= 10) {
            readingsBeginUpdate($hash);
            if ($setpointTemp < 15 - $a[1]) {
              $setpointShiftMax = 15 - $setpointTemp;
            } elsif ($setpointTemp > 30 + $a[1]) {
              $setpointShiftMax = $setpointTemp - 30;
            } else {
              $setpointShiftMax = $a[1];
            }
            readingsBulkUpdate($hash, "setpointShiftMax", $setpointShiftMax);
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 2);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name setpointShiftMax $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        } else {
          return "Usage: set <name> setpointShiftMax 1...10";
        }

      } elsif ($cmd eq "setpointType") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^setpointTemp|setpointShift$/) {
            readingsBeginUpdate($hash);
            $setpointType = $a[1];
            readingsBulkUpdate($hash, "setpointType", $setpointType);
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 0x80);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name setpointType $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> setpointType setpointTemp|setpointShift";
        }

      } elsif ($cmd eq 'fanSpeed') {
        if (defined $a[1]) {
          if ($a[1] =~ m/^auto|off|1|2|3$/) {
            $fanSpeed = $a[1];
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "fanSpeed", $a[1]);
            readingsBulkUpdate($hash, "state", "T: $temperature H: $humidity SPT: $setpointTemp F: $fanSpeed");
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 4);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> fanspeed 1...3|auto|off";
        }

      } elsif ($cmd eq "cooling") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^on|off$/) {
            $cooling = $a[1];
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "cooling", $a[1]);
            if ($a[1] eq 'on') {
              $heating = 'off';
              readingsBulkUpdate($hash, "heating", 'off');
            }
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 0x20);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name cooling $a[1]";
            shift(@a);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> cooling on|off";
        }

      } elsif ($cmd eq "heating") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^on|off$/) {
            $heating = $a[1];
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "heating", $a[1]);
            if ($a[1] eq 'on') {
              $cooling = 'off';
              readingsBulkUpdate($hash, "cooling", 'off');
            }
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 0x40);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name heating $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> heating on|off";
        }

      } elsif ($cmd eq "occupancy") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^occupied|unoccupied$/) {
            $occupancy = $a[1];
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "occupancy", $a[1]);
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 8);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name occupancy $a[1]";
            shift(@a);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> occupancy occupied|unoccupied";
        }

      } elsif ($cmd eq "window") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^closed|open$/) {
            $window = $a[1];
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "window", $a[1]);
            readingsBulkUpdate($hash, "waitingCmds", $waitingCmds |= 0x10);
            readingsEndUpdate($hash, 1);
            CommandDeleteReading(undef, "$name smartAckMailbox");
            Log3 $name, 3, "EnOcean set $name window $a[1]";
            shift(@a);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> window open|closed";
        }

      } else {
        $cmdList .= "setpointTemp:slider,5,1,40 cooling:off,on desired-temp " .
                    "fanSpeed:auto,off,1,2,3 heating:off,on occupancy:occupied,unoccupied " .
                    "setpointShiftMax:slider,1,1,10 setpointType:setpointShift,setpointTemp window:closed,open";
        return "Unknown argument $cmd, choose one of $cmdList";
      }
      $setpointType = $setpointType eq 'setpointTemp' ? 0x80 : 0;
      $heating = $heating eq 'on' ? 0x40 : 0;
      $cooling = $cooling eq 'on' ? 0x20 : 0;
      $window = $window eq 'open' ? 0x10 : 0;
      $setpointShift = int(($setpointShift + $setpointShiftMax) * 255 / ($setpointShiftMax * 2));
      #$setpointShift = unpack('C', pack('c', $setpointShift));
      my %fanSpeed = ('auto' => 0, 'off' =>1, 1 => 2, 2 => 3, 3 => 4);
      $occupancy = $occupancy eq 'occupied' ? 1 : 0;
      $data = sprintf "%02X%02X%02X%02X", $setpointType | $heating | $cooling | $window | 1,
                                          $setpointShift, $setpointBase,
                                          $setpointShiftMax << 4 | $fanSpeed{$fanSpeed} << 1 | $occupancy;

    } elsif ($st eq "fanCtrl.00") {
      # Fan Control
      # (D2-20-00 - D2-20-02)
      $rorg = "D2";
      #$updateState = 0;
      my ($fanSpeed, $humiThreshold, $roomSize, $roomSizeRef, $humidityCtrl, $tempLevel, $opMode) =
         (255, 255, 15, 3, 3, 3, 15);
      my $messageType = 0;
      my @roomSizeTbl = (25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 325, 350);
      if ($cmd eq "fanSpeed") {
        $updateState = 0;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $fanSpeed = $a[1];
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
          } elsif ($a[1] eq "auto") {
            $fanSpeed = 253;
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
          } elsif ($a[1] eq "default") {
            $fanSpeed = 254;
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> fanspeed 0...100|auto|default";
        }
        shift(@a);

      } elsif ($cmd eq "on") {
        $opMode = 1;
        Log3 $name, 3, "EnOcean set $name $a[0]";
        shift(@a);

      } elsif ($cmd eq "off") {
        $opMode = 0;
        Log3 $name, 3, "EnOcean set $name $a[0]";
        shift(@a);

      } elsif ($cmd eq "desired-temp" || $cmd eq "setpointTemp") {
        $updateState = 0;
        my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
        return "attribute missing: attr $name temperatureRefDev <refDev> must be defined" if (!defined $temperatureRefDev);
        my $temperature = ReadingsVal($temperatureRefDev, "temperature", 20);
        my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
        my $switchHysteresis = AttrVal($name, "switchHysteresis", 1);
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 40) {
          $setpointTemp = $a[1];
          shift(@a);
        }
        if ($setpointTemp > $temperature + $switchHysteresis / 2) {
          $tempLevel = 2;
        } elsif ($setpointTemp < $temperature - $switchHysteresis / 2) {
          $tempLevel = 0;
        } else {
          $tempLevel = 1;
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "setpointTemp", sprintf("%.1f", $setpointTemp));
        readingsBulkUpdate($hash, "temperature", sprintf("%.1f", $temperature));
        readingsEndUpdate($hash, 1);
        Log3 $name, 3, "EnOcean set $name $cmd $setpointTemp";
        shift(@a);

      } elsif ($cmd eq "humidityThreshold") {
        $updateState = 0;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $humidityCtrl = 1;
            $humiThreshold = $a[1];
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";
            shift(@a);
          } elsif ($a[1] eq "auto") {
            $humidityCtrl = 1;
            $humiThreshold = 253;
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";
            shift(@a);
          } elsif ($a[1] eq "default") {
            $humidityCtrl = 2;
            $humiThreshold = 254;
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";
            shift(@a);
          } elsif ($a[1] eq "disabled") {
            $humidityCtrl = 0;
            $humiThreshold = 255;
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> humidityThreshold 0...100|auto|default|disabled";
        }
        shift(@a);

      } elsif ($cmd eq "roomSize") {
        $updateState = 0;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/) {
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";
            $roomSize = 14;
            for (my $i = 0; $i < @roomSizeTbl; $i++) {
              if ($a[1] <= $roomSizeTbl[$i]) {
                $roomSize = $i;
                last;
              }
            }
            $roomSizeRef = 0;
            shift(@a);
          } elsif ($a[1] eq "not_used") {
            $roomSizeRef = 1;
            $roomSize = 15;
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";
            shift(@a);
          } elsif ($a[1] eq "default") {
            $roomSizeRef = 2;
            $roomSize = 15;
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";
            shift(@a);
          } elsif ($a[1] eq "max") {
            $roomSizeRef = 0;
            $roomSize = 14;
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> roomSize 0...350|max|not_used|default";
        }
        shift(@a);

      } else {
        $cmdList .= "off:noArg on:noArg desired-temp fanSpeed setpointTemp:slider,0,1,40 " .
                      "humidityThreshold roomSize";
        return "Unknown argument $cmd, choose one of $cmdList";
      }
      $data = sprintf "%02X%02X%02X%02X", ($opMode << 4) | ($tempLevel << 1),
                                          ($humidityCtrl << 6) | ($roomSizeRef << 4) | $roomSize,
                                          $humiThreshold, $fanSpeed;

    } elsif ($st eq "heatingActuator.00") {
      # Heating Actuator
      # (D2-34-00 - D2-34-02)
      $rorg = "D2";
      my ($cmdID, $cfg, $channel, $overridePeriod, $setpointTemp, $setpointTempShift) = (5, 0, undef, 0, 20, 0);

      if ($cmd eq "setpointTempRefDev") {
        shift(@a);
        $cfg = 0;
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined($channel) || defined($channel) && ($channel eq "all" || $channel + 0 >= 30)) {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name overridePeriod.*");
          CommandDeleteReading(undef, "$name setpointTemp.*");
          CommandDeleteReading(undef, "$name setpointTempRefDev.*");
          CommandDeleteReading(undef, "$name setpointTempShift.*");
          readingsSingleUpdate($hash, "channelAll", "setpointTempRefDev", 1);
          $channel = 30;
        } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {
          CommandDeleteReading(undef, "$name overridePeriod" . $channel);
          CommandDeleteReading(undef, "$name setpointTemp" . $channel);
          CommandDeleteReading(undef, "$name setpointTempShift" . $channel);
          readingsSingleUpdate($hash, "channel" . $channel, "setpointTempRefDev", 1);
        } else {
          return "$cmd $channel wrong, choose 0...29|all.";
        }

      } elsif ($cmd eq "setpointTemp") {
        shift(@a);
        $cfg = 1;
        $setpointTemp = shift(@a);
        if (!defined($setpointTemp) || $setpointTemp !~ m/^[+-]?\d+(\.\d+)?$/ || $setpointTemp < 0 || $setpointTemp > 40) {
          return "Usage: $cmd variable is not numeric or out of range.";
        }
        $channel = shift(@a);
        if (defined $channel) {
          $overridePeriod = shift(@a);
          if (defined $overridePeriod) {
            if ($overridePeriod !~ m/^[+-]?\d+$/ || $overridePeriod < 0 || $overridePeriod > 63) {
              return "Usage: $cmd <setpointTemp> <channel> $overridePeriod is not numeric or out of range.";
            }
          }
        } else {
          $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", 'all'));
          $overridePeriod = 0;
        }
        if ($channel eq "all" || $channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name overridePeriod.*");
          CommandDeleteReading(undef, "$name setpointTemp.*");
          CommandDeleteReading(undef, "$name setpointTempRefDev.*");
          CommandDeleteReading(undef, "$name setpointTempShift.*");
          readingsSingleUpdate($hash, "overridePeriodAll", $overridePeriod, 1);
          readingsSingleUpdate($hash, "setpointTempAll", sprintf("%0.1f", $setpointTemp), 1);
          readingsSingleUpdate($hash, "channelAll", "setpointTemp", 1);
          $channel = 30;
        } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {
          readingsSingleUpdate($hash, "overridePeriod" . $channel, $overridePeriod, 1);
          readingsSingleUpdate($hash, "setpointTemp" . $channel, sprintf("%0.1f", $setpointTemp), 1);
          readingsSingleUpdate($hash, "channel" . $channel, "setpointTemp", 1);
        } else {
          return "Usage: $cmd <setpointTemp> $channel wrong, choose 0...29|all.";
        }

      } elsif ($cmd eq "setpointTempShift") {
        shift(@a);
        $setpointTempShift = shift(@a);
        if (!defined($setpointTempShift) || $setpointTempShift !~ m/^[+-]?\d+(\.\d+)?$/ || $setpointTempShift < -10 || $setpointTempShift > 10) {
          return "Usage: $cmd variable is not numeric or out of range.";
        }
        $channel = shift(@a);
        if (defined $channel) {
          $overridePeriod = shift(@a);
          if (defined $overridePeriod) {
            if ($overridePeriod !~ m/^[+-]?\d+$/ || $overridePeriod < 0 || $overridePeriod > 63) {
              return "Usage: $cmd <setpointTemp> <channel> $overridePeriod is not numeric or out of range.";
            }
          }
        } else {
          $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", 'all'));
          $overridePeriod = 0;
        }
        if ($channel eq "all" || $channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name overridePeriod.*");
          CommandDeleteReading(undef, "$name setpointTemp.*");
          CommandDeleteReading(undef, "$name setpointTempRefDev.*");
          CommandDeleteReading(undef, "$name setpointTempShift.*");
          readingsSingleUpdate($hash, "overridePeriodAll", $overridePeriod, 1);
          readingsSingleUpdate($hash, "setpointTempShiftAll", sprintf("%0.1f", $setpointTempShift), 1);
          readingsSingleUpdate($hash, "channelAll", "setpointTempShift", 1);
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
          readingsSingleUpdate($hash, "overridePeriod" . $channel, $overridePeriod, 1);
          readingsSingleUpdate($hash, "setpointTempShift" . $channel, sprintf("%0.1f", $setpointTempShift), 1);
          readingsSingleUpdate($hash, "channel" . $channel, "setpointTempShift", 1);
        } else {
          return "Usage: $cmd <setpointTempShift> <overridePeriod> $channel wrong, choose 0...29|all.";
        }
        $cfg = $setpointTempShift >= 0 ? 2 : 3;
        $setpointTempShift = abs($setpointTempShift * 10);

      } else {
        $cmdList .= "setpointTemp setpointTempRefDev setpointTempShift";
        return "Unknown argument $cmd, choose one of $cmdList";
      }
      Log3 $name, 3, "EnOcean set $name $cmd";
      $setpointTemp = abs($setpointTemp * 10);
      $data = sprintf "%02X%04X%02X%02X", $cfg << 6 | $overridePeriod, $setpointTempShift << 9 | $setpointTemp, $channel << 3, $cmdID;

    } elsif ($st eq "heatRecovery.00") {
      # heat recovery ventilation
      # (D2-50-00)
      $rorg = "D2";
      $updateState = 0;
      my $airQuatityThreshold = ReadingsVal($name, "airQuatityThreshold", 'default');
      $airQuatityThreshold = $airQuatityThreshold eq 'default' ? 127 : $airQuatityThreshold;
      my $CO2Threshold = ReadingsVal($name, "CO2Threshold", 'default');
      $CO2Threshold = $CO2Threshold eq 'default' ? 127 : $CO2Threshold;
      my $heatExchangerBypass = 0;
      my $humidityThreshold = ReadingsVal($name, "humidityThreshold", 'default');
      $humidityThreshold = $humidityThreshold eq 'default' ? 127 : $humidityThreshold;
      my $startTimerMode = 0;
      my $tempThreshold = ReadingsVal($name, "roomTempSet", 'default');
      $tempThreshold = $tempThreshold eq 'default' ? 0 : $tempThreshold;
      my $ventilation = 15;
      if ($cmd eq "ventilation") {
        $ventilation = $a[1];
        return "Usage: $cmd variable is missing, choose off|1...4|auto|demand|supplyAir|exhaustAir." if (!defined $ventilation);
        shift(@a);
        my %ventilation = (
          "off" => 0,
          1 => 1,
          2 => 2,
          3 => 3,
          4 => 4,
          "auto" => 11,
          "demand" => 12,
          "supplyAir" => 13,
          "exhaustAir" => 14
        );
        if (exists $ventilation{$ventilation}) {
          $ventilation = $ventilation{$ventilation};
        } else {
          return "Usage: $cmd variable wrong, choose off|1...4|auto|demand|supplyAir|exhaustAir.";
        }

      } elsif ($cmd eq "heatExchangerBypass") {
        $heatExchangerBypass = $a[1];
        return "Usage: $cmd variable is missing, choose opens|closes." if (!defined $heatExchangerBypass);
        shift(@a);
        my %heatExchangerBypass = (
          "closes" => 1,
          "opens" => 2
        );
        if (exists $heatExchangerBypass{$heatExchangerBypass}) {
          $heatExchangerBypass = $heatExchangerBypass{$heatExchangerBypass};
        } else {
          return "Usage: $cmd variable wrong, choose opens|closes.";
        }

      } elsif ($cmd eq "startTimerMode") {
        $startTimerMode = 1;

      } elsif ($cmd eq "CO2Threshold") {
        $CO2Threshold = $a[1];
        if (defined $CO2Threshold) {
          if ($CO2Threshold eq 'default') {
            $CO2Threshold = 127;
            readingsSingleUpdate($hash, "CO2Threshold", 'default', 1);
          } elsif ($CO2Threshold =~ m/^\d+$/ && $CO2Threshold >= 0 && $CO2Threshold <= 100) {
            readingsSingleUpdate($hash, "CO2Threshold", $CO2Threshold, 1);
          } else {
            return "Usage: $cmd variable is wrong, choose default|0 ... 100." ;
          }
        } else {
          return "Usage: $cmd variable is wrong, choose default|0 ... 100." ;
        }
        shift(@a);
      } elsif ($cmd eq "humidityThreshold") {
        $humidityThreshold = $a[1];
        if (defined $humidityThreshold) {
          if ($humidityThreshold eq 'default') {
            $humidityThreshold = 127;
            readingsSingleUpdate($hash, "humidityThreshold", 'default', 1);
          } elsif ($humidityThreshold =~ m/^\d+$/ && $humidityThreshold >= 0 && $humidityThreshold <= 100) {
            readingsSingleUpdate($hash, "humidityThreshold", $humidityThreshold, 1);
          } else {
            return "Usage: $cmd variable is wrong, choose default|0 ... 100." ;
          }
        } else {
          return "Usage: $cmd variable is wrong, choose default|0 ... 100." ;
        }
        shift(@a);
      } elsif ($cmd eq "airQuatityThreshold") {
        $airQuatityThreshold = $a[1];
        if (defined $airQuatityThreshold) {
          if ($airQuatityThreshold eq 'default') {
            $airQuatityThreshold = 127;
            readingsSingleUpdate($hash, "airQuatityThreshold", 'default', 1);
          } elsif ($airQuatityThreshold =~ m/^\d+$/ && $airQuatityThreshold >= 0 && $airQuatityThreshold <= 100) {
            readingsSingleUpdate($hash, "airQuatityThreshold", $airQuatityThreshold, 1);
          } else {
            return "Usage: $cmd variable is wrong, choose default|0 ... 100." ;
          }
        } else {
          return "Usage: $cmd variable is wrong, choose default|0 ... 100." ;
        }
        shift(@a);
      } elsif ($cmd eq "roomTemp") {
        $tempThreshold = $a[1];
        if (defined $tempThreshold) {
          if ($tempThreshold eq 'default') {
            $tempThreshold = 0;
            readingsSingleUpdate($hash, "roomTempSet", 'default', 1);
          } elsif ($tempThreshold =~ m/^[+-]?\d+$/ && $tempThreshold >= - 63 && $tempThreshold <= 63) {
            readingsSingleUpdate($hash, "roomTempSet", $tempThreshold, 1);
            $tempThreshold += 64;
            #$tempThreshold = abs($tempThreshold) | 0x40 if ($tempThreshold < 0);
          } else {
            return "Usage: $cmd variable is wrong, choose default|-63 ... 63." ;
          }
        } else {
          return "Usage: $cmd variable is wrong, choose default|-63 ... 63." ;
        }
        shift(@a);
      } else {
        $cmdList .= "ventilation:off,1,2,3,4,auto,demand,supplyAir,exhaustAir roomTemp heatExchangerBypass:closes,opens " .
                    "startTimerMode:noArg CO2Threshold humidityThreshold airQuatityThreshold";
        return "Unknown argument $cmd, choose one of $cmdList";
      }
      $data = sprintf "%02X%02X%02X%02X%02X%02X", 32 | $ventilation, $heatExchangerBypass << 4, $startTimerMode << 7 | $CO2Threshold,
                                                  $humidityThreshold, $airQuatityThreshold, $tempThreshold;
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "valveCtrl.00") {
      # Valve Control
      # (D2-A0-01)
      if (AttrVal($name, "devMode", "master") eq "slave") {
        # devNode slave
        if ($cmd eq "closed") {
          $rorg = "D2";
          $data = "01";
        } elsif ($cmd eq "open") {
          $rorg = "D2";
          $data = "02";
        } elsif ($cmd eq "teachIn") {
          $updateState = 0;
          ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, "biDir",
                                                AttrVal($name, "uteResponseRequest", "yes"), "in", 0, "D2-A0-01");
        } elsif ($cmd eq "teachOut") {
          $updateState = 0;
          ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, "biDir",
                                                AttrVal($name, "uteResponseRequest", "yes"), "out", 0, "D2-A0-01");
        } else {
          return "Unknown argument $cmd, choose one of " . $cmdList . "open:noArg closed:noArg teachIn:noArg teachOut:noArg";
        }
      } else {
      # devMode master
        if ($cmd eq "closes") {
          $rorg = "D2";
          $data = "01";
        } elsif ($cmd eq "opens") {
          $rorg = "D2";
          $data = "02";
        } else {
          return "Unknown argument $cmd, choose one of " . $cmdList . "opens:noArg closes:noArg";
        }
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "contact") {
      # 1BS Telegram
      # Single Input Contact (EEP D5-00-01)
      $rorg = "D5";
      my $setCmd;
      if ($cmd eq "teach") {
        $attr{$name}{eep} = "D5-00-01";
        CommandDeleteReading(undef, "$name .*");
        readingsSingleUpdate($hash, "teach", "1BS teach-in sent", 1);
        $setCmd = 0;
        $updateState = 0;
      } elsif ($cmd eq "closed") {
        $setCmd = 9;
      } elsif ($cmd eq "open") {
        $setCmd = 8;
      } else {
        return "Unknown argument $cmd, choose one of " . $cmdList . "open:noArg closed:noArg teach:noArg";
      }
      $data = sprintf "%02X", $setCmd;
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "genericProfile") {
      # Generic Profile
      my $channel = 0;
      my $devMode = AttrVal($name, "devMode", "master");
      my $header = 1;
      my ($setChannel, $setChannelName) = split(/-|:/, $cmd, 2);
      my ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax);
      my ($readingFormat, $readingName, $readingType, $readingUnit, $readingValue);
      my $gpDef = AttrVal($name, "gpDef", undef);
      return "Usage: Channel definition is missing" if (!defined $gpDef);
      my @gpDef = split("[ \t][ \t]*", $gpDef);
      if ($cmd eq "channelName") {
        # rename channel name
        ($setChannel, $setChannelName) = split(/-|:/, $a[1], 2);
        if (defined $gpDef[$setChannel]) {
          ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
          split(':', $gpDef[$setChannel]);
          # remove spaces und tabs
          #$channelName =~ tr/ \t//d;
          if ($setChannelName eq "?") {
            $channelName = "none";
            if ($channelType == 1 && defined $EnO_gpValueData{$signalType}{name}) {
              $channelName = $EnO_gpValueData{$signalType}{name};
            } elsif ($channelType == 2 && defined $EnO_gpValueFlag{$signalType}{name}) {
              $channelName = $EnO_gpValueFlag{$signalType}{name};
            } elsif ($channelType == 3 && defined $EnO_gpValueEnum{$signalType}{name}) {
              $channelName = $EnO_gpValueEnum{$signalType}{name};
            }
          } else {
            $channelName = $setChannelName;
          }
          $resolution = '' if (!defined $resolution);
          $engMin = '' if (!defined $engMin);
          $scalingMin = '' if (!defined $scalingMin);
          $engMax = '' if (!defined $engMax);
          $scalingMax = '' if (!defined $scalingMax);
          $gpDef[$setChannel] = $channelName . ':' . $channelDir . ':' . $channelType . ':' . $signalType . ':' . $valueType .
                                ':' . $resolution . ':' . $engMin . ':' . $scalingMin . ':' . $engMax . ':' . $scalingMax;
          $attr{$name}{gpDef} = join(' ', @gpDef);
          shift @a;
          $updateState = 3;
          $channelType = 255;
          EnOcean_CommandSave(undef, undef);
        } else {
          return "Wrong parameter, channel $setChannel not defined.";
        }
      } elsif ($cmd eq "teachIn" && $devMode eq "slave") {
        # teach-in generic profile
        $rorg = "B0";
        my ($gpDefO, $gpDefI, $formatPattern, $teachInInfo);
        my $channelDirSeq = "--";
        my $comMode = 0;
        $attr{$name}{comMode} = "uniDir";
        $attr{$name}{eep} = "B0-00-00";
        # multicast teach-in
        $destinationID = "FFFFFFFF";
	my $productID = AttrVal($name, "productID", undef);
	if (defined $productID) {
          # GP definition
          # V1.0: teach-in signal type length 8 bit?
          # V1.1: teach-in signal type length 6 bit?
	  $productID = '000000001000000100' . EnOcean_convHexToBit($productID);
	  #$productID = '0000001000000100' . EnOcean_convHexToBit($productID);
	} else {
	  $productID = '';
	}
        while ($gpDef[$channel]) {
          ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
          split(':', $gpDef[$channel]);
          if ($channelDir eq "O") {
            #Log3 $name, 3, "EnOcean set $name channel: $channel channelDir: $channelDir seq: $channelDirSeq";
            #Log3 $name, 3, "EnOcean set $name channel: $channel channelType: $channelType signalType: $signalType valueType: $valueType";
            return "Usage: attr $name gpDef: O/I sequence error" if $channelDirSeq =~ m/.I$/;
            $channelDirSeq = "O-";
            # add channel-, signal- and valuetype
            $gpDefO .= substr(unpack('B8', pack('C', $channelType)), 6) .
                       unpack('B8', pack('C', $signalType)) .
                       substr(unpack('B8', pack('C', $valueType)), 6);
            if ($channelType == 1 || $channelType == 3) {
              # data, enumeration: add resolution
              $gpDefO .= substr(unpack('B8', pack('C', $resolution)), 4);
            }
            if ($channelType == 1) {
              # data: add engineering and scaling
              $gpDefO .= unpack('B8', pack('c', $engMin)) .
                         substr(unpack('B8', pack('C', $scalingMin)), 4) .
                         unpack('B8', pack('c', $engMax)) .
                         substr(unpack('B8', pack('C', $scalingMax)), 4);
            }
          } elsif ($channelDir eq "I") {
            #Log3 $name, 3, "EnOcean set $name channel: $channel channelDir: $channelDir seq: $channelDirSeq";
            return "Usage: attr $name gpDef: O/I sequence error" if $channelDirSeq !~ m/^O./;
            $channelDirSeq = "OI";
            $gpDefI .= substr(unpack('B8', pack('C', $channelType)), 6) .
                       unpack('B8', pack('C', $signalType)) .
                       substr(unpack('B8', pack('C', $valueType)), 6);
            if ($channelType == 1 || $channelType == 3) {
              # data, enumeration: add resolution
              $gpDefI .= substr(unpack('B8', pack('C', $resolution)), 4);
            }
            if ($channelType == 1) {
              # data: add engineering and scaling
              $gpDefI .= unpack('B8', pack('c', $engMin)) .
                         substr(unpack('B8', pack('C', $scalingMin)), 4) .
                         unpack('B8', pack('c', $engMax)) .
                         substr(unpack('B8', pack('C', $scalingMax)), 4);
            }
          }
          $channel ++;
        }
        if ($channelDirSeq eq "OI") {
          # await teach-in response
          $comMode = 1;
          $attr{$name}{comMode} = "biDir";
          # set flag for response request
          $hash->{IODev}{helper}{gpRespWait}{AttrVal($name, "subDef", $hash->{DEF})}{teachInReq} = "in";
          $hash->{IODev}{helper}{gpRespWait}{AttrVal($name, "subDef", $hash->{DEF})}{hash} = $hash;
          # enable teach-in receiving for 3 sec
          $hash->{IODev}{Teach} = 1;
          RemoveInternalTimer($hash->{helper}{timer}{gpRespTimeout}) if(exists $hash->{helper}{timer}{gpRespTimeout});
          $hash->{helper}{timer}{gpRespTimeout} = {hash => $hash, function => "gpRespTimeout", helper => "gpRespWait"};
          InternalTimer(gettimeofday() + 3, 'EnOcean_RespTimeout', $hash->{helper}{timer}{gpRespTimeout}, 0);
        }
        $header = (0x7FF << 1 | $comMode) << 4;
        if ($channelDirSeq =~ m/.I$/) {
          # create teach-in information
          if (length($gpDefI) % 8) {
            # fill with trailing zeroes to x bytes
            $gpDefI .= 0 x (8 - length($gpDefI) % 8);
          }
          # GP definition
          # V1.0: teach-in signal type length 8 bit?
          # V1.1: teach-in signal type length 6 bit?
          #$teachInInfo = '0000000001' . unpack('B8', pack('C', length($gpDefI) / 4));
          $teachInInfo = '000000000100000000';
        }
        #Log3 $name, 3, "EnOcean set $name header: $header O: $gpDefO Info: $teachInInfo I: $gpDefI";
        # DophinView GP profile error if Product ID sent
        $data = $productID . $gpDefO . $teachInInfo . $gpDefI;
        #$data = $gpDefO . $teachInInfo . $gpDefI;
        if (length($data) % 8) {
          # fill with trailing zeroes to x bytes
          $data .= 0 x (8 - length($data) % 8);
        }
        $channelType = 0;
        EnOcean_CommandSave(undef, undef);
        $data = sprintf '%04X%s', $header, EnOcean_convBitToHex($data);
        my $teachInState = $comMode == 1 ? "teach-in sent, response requested" : "teach-in sent";
        readingsSingleUpdate($hash, "teach", "GP $teachInState", 1);

      } elsif ($cmd eq "teachOut" && $devMode eq "slave") {
        # teach out generic profile
        $rorg = "B0";
        $channelType = 0;
        my $comMode = 0;
	if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
          $comMode = 1;
          $hash->{IODev}{helper}{gpRespWait}{AttrVal($name, "subDef", $hash->{DEF})}{teachInReq} = "out";
          $hash->{IODev}{helper}{gpRespWait}{AttrVal($name, "subDef", $hash->{DEF})}{hash} = $hash;
          # enable teach-in receiving for 3 sec
          $hash->{IODev}{Teach} = 1;
          RemoveInternalTimer($hash->{helper}{timer}{gpRespTimeout}) if(exists $hash->{helper}{timer}{gpRespTimeout});
          $hash->{helper}{timer}{gpRespTimeout} = {hash => $hash, function => "gpRespTimeout", helper => "gpRespWait"};
          InternalTimer(gettimeofday() + 3, 'EnOcean_RespTimeout', $hash->{helper}{timer}{gpRespTimeout}, 0);
        }
        $data = sprintf '%04X', (0x7FF << 1 | $comMode) << 4 | 4;
        my $teachInState = $comMode == 1 ? "teach-in deletion sent, response requested" : "teach-in deletion sent";
        readingsSingleUpdate($hash, "teach", "GP $teachInState", 1);

      } elsif ($setChannel =~ m/^\d+$/ && defined $gpDef[$setChannel]) {
        # send selective data (GPSD)
        $rorg = "B3";
        # select channel
        ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
        split(':', $gpDef[$setChannel]);
        if ($channelName eq $setChannelName && $channelDir eq "O") {
          $channel = $setChannel;
        } else {
          return "Channel name wrong or no output channel";
        }
      } else {
        # command error
        my $channelCntr = 0;
        my @cmdList;
        while (defined $gpDef[$channelCntr]) {
          ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
          split(':', $gpDef[$channelCntr]);
          if ($channelDir ne "O") {
            $channelCntr ++;
            next;
          }
          if ($channelType == 1) {
            # data
            push @cmdList, sprintf('%02d', $channelCntr) . "-" . $channelName;
          } elsif ($channelType == 2) {
            # flag
            push @cmdList, sprintf('%02d', $channelCntr) . "-" . $channelName . ':' .
                           $EnO_gpValueFlag{$signalType}{flag}{0} . "," .
                           $EnO_gpValueFlag{$signalType}{flag}{1};
          } elsif ($channelType == 3) {
            # enumeration
            my $cmdListEnum = "";
            my $enum = 0;
            while (defined $EnO_gpValueEnum{$signalType}{enum}{$enum}) {
              $cmdListEnum .= $EnO_gpValueEnum{$signalType}{enum}{$enum} . ",";
              $enum ++;
            }
            push @cmdList, sprintf('%02d', $channelCntr) . "-" . $channelName . ':' . substr($cmdListEnum, 0, -1);
          }
          $channelCntr ++;
        }
        if (defined $cmdList[0] && $devMode eq "slave") {
          return "Unknown argument $cmd, choose one of " . $cmdList . 'channelName teachIn:noArg teachOut:noArg ' . join(" ", @cmdList);
        } elsif (defined $cmdList[0] && $devMode eq "master") {
          return "Unknown argument $cmd, choose one of " . $cmdList . 'channelName ' . join(" ", @cmdList);
        } else {
          return "Unknown argument $cmd, choose one of " . $cmdList . 'channelName';
        }
      }
      #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel";

      if ($channelType == 1) {
        # data
        if ($engMin * $EnO_scaling[$scalingMin] >  $engMax * $EnO_scaling[$scalingMax]) {
          return "Usage: numerical value is missing" if (!defined $a[1]);
          if ($a[1] =~ m/^[-+]?\d*\.?\d+([eE][-+]?\d+)?$/ &&
              $a[1] >= $engMax * $EnO_scaling[$scalingMax] &&
              $a[1] <= $engMin * $EnO_scaling[$scalingMin]) {
            $data = int(2**$EnO_resolution[$resolution] * ($a[1] - $engMin * $EnO_scaling[$scalingMin]) /
                                          ($engMax * $EnO_scaling[$scalingMax] - $engMin * $EnO_scaling[$scalingMin]));
            #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel resolution: " . $EnO_resolution[$resolution] . " data: $data";
            if ($data >= 2**$EnO_resolution[$resolution]) {
              $data = 2**$EnO_resolution[$resolution] - 1;
              #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel resolution: " . $EnO_resolution[$resolution] . " data: $data";
            }
            shift @a;
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        } else {
          return "Usage: numerical value is missing" if (!defined $a[1]);
          if ($a[1] =~ m/^[-+]?\d*\.?\d+([eE][-+]?\d+)?$/ &&
              $a[1] >= $engMin * $EnO_scaling[$scalingMin] &&
              $a[1] <= $engMax * $EnO_scaling[$scalingMax]) {
            $data = int(2**$EnO_resolution[$resolution] * ($a[1] - $engMin * $EnO_scaling[$scalingMin]) /
                    ($engMax * $EnO_scaling[$scalingMax] - $engMin * $EnO_scaling[$scalingMin]));
            #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel resolution: " . $EnO_resolution[$resolution] . " data: $data";
            if ($data >= 2**$EnO_resolution[$resolution]) {
              $data = 2**$EnO_resolution[$resolution] - 1;
              #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel resolution: " . $EnO_resolution[$resolution] . " data: $data";
            }
            shift @a;
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
        ($err, $logLevel, $response, $readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType) =
          EnOcean_gpConvDataToValue (undef, $hash, $channel, $data, $gpDef[$channel]);
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, $readingName, sprintf("$readingFormat", $readingValue));
        readingsBulkUpdate($hash, $readingName . "Unit", $readingUnit);
        readingsBulkUpdate($hash, $readingName . "ValueType", $valueType);
        readingsBulkUpdate($hash, $readingName . "ChannelType", $readingType);
        readingsEndUpdate($hash, 1);
        $data = EnOcean_gpConvSelDataToSndData($header, $channel, $EnO_resolution[$resolution], $data);

      } elsif ($channelType == 2) {
        # flag
        if (defined $EnO_gpValueFlag{$signalType}{flagInv}{$a[1]}) {
          $data = $EnO_gpValueFlag{$signalType}{flagInv}{$a[1]};
          #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel data: " . $EnO_gpValueFlag{$signalType}{flagInv}{$a[1]};
          shift @a;
        } else {
          return "Usage: $a[1] is unknown";
        }
        #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel data: $data";
        ($err, $logLevel, $response, $readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType)=
          EnOcean_gpConvDataToValue (undef, $hash, $channel, $data, $gpDef[$channel]);
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, $readingName, sprintf("$readingFormat", $readingValue));
        readingsBulkUpdate($hash, $readingName . "Unit", $readingUnit);
        readingsBulkUpdate($hash, $readingName . "ValueType", $valueType);
        readingsBulkUpdate($hash, $readingName . "ChannelType", $readingType);
        readingsEndUpdate($hash, 1);
        $data = sprintf '%04X', (($header << 6 | $channel) << 1 | $data) << 5;

      } elsif ($channelType == 3) {
        # enumeration
        if (defined $EnO_gpValueEnum{$signalType}{enumInv}{$a[1]}) {
          $data = $EnO_gpValueEnum{$signalType}{enumInv}{$a[1]};
          #Log3 $name, 3, "EnOcean set $name header: $header channel: $channel data: $data";
          shift @a;
        } elsif ($signalType == 6 && $a[1] =~ m/^\d+$/ && $a[1] <= 0xFFFFFFFF) {
          # time
          $data = shift @a;
        } elsif ($signalType == 7 && $a[1] =~ m/^\d+(\.\d+)?$/ && $a[1] <= 100) {
          # battery
          $data = int(shift(@a) * 2);
        } else {
          return "Usage: $a[1] is unknown";
        }
        ($err, $logLevel, $response, $readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType)=
          EnOcean_gpConvDataToValue (undef, $hash, $channel, $data, $gpDef[$channel]);
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, $readingName, sprintf("$readingFormat", $readingValue));
        readingsBulkUpdate($hash, $readingName . "Unit", $readingUnit);
        readingsBulkUpdate($hash, $readingName . "ValueType", $valueType);
        readingsBulkUpdate($hash, $readingName . "ChannelType", $readingType);
        readingsEndUpdate($hash, 1);
        $data = EnOcean_gpConvSelDataToSndData($header, $channel, $EnO_resolution[$resolution], $data);
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "raw") {
      # sent raw data
      if ($cmd eq "4BS"){
        # 4BS Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{8}$/) {
          $data = uc($a[1]);
          $rorg = "A5";
        } else {
          return "Wrong parameter, choose 4BS <data 4 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "1BS") {
        # 1BS Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2}$/) {
          $data = uc($a[1]);
          $rorg = "D5";
        } else {
          return "Wrong parameter, choose 1BS <data 1 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "RPS") {
        # RPS Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2}$/) {
          $data = uc($a[1]);
          $rorg = "F6";
        } else {
          return "Wrong parameter, choose RPS <data 1 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "MSC") {
        # MSC Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "D1";
        } else {
          return "Wrong parameter, choose MSC <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "UTE") {
        # UTE Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{14}$/) {
          $data = uc($a[1]);
          $rorg = "D4";
        } else {
          return "Wrong parameter, choose UTE <data 7 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "VLD") {
        # VLD Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "D2";
        } else {
          return "Wrong parameter, choose VLD <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPTI") {
        # GP teach-in request telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B0";
        } else {
          return "Wrong parameter, choose GPTI <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPTR") {
        # GP teach-in response telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B1";
        } else {
          return "Wrong parameter, choose GPTR <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPCD") {
        # GP complete date telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B2";
        } else {
          return "Wrong parameter, choose GPCD <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPSD") {
        # GP selective data telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B3";
        } else {
          return "Wrong parameter, choose GPSD <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "SEC") {
        # secure telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "30";
        } else {
          return "Wrong parameter, choose SEC <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "ENC") {
        # secure telegram with encapsulation
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "31";
        } else {
          return "Wrong parameter, choose ENC <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "STE") {
        # secure Teach-In
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "35";
        } else {
          return "Wrong parameter, choose STE <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }

      } else {
        return "Unknown argument $cmd, choose one of 1BS 4BS ENC GPCD GPSD GPTI GPTR MSC RPS SEC STE UTE VLD";
      }
      if ($a[2]) {
        if ($a[2] !~ m/^[\dA-Fa-f]{2}$/) {
          return "Wrong status parameter, choose $cmd $a[1] [status 1 Byte hex]";
        }
       $status = uc($a[2]);
       splice(@a,2,1);
      }
      $updateState = 0;
      readingsSingleUpdate($hash, "RORG", $cmd, 1);
      readingsSingleUpdate($hash, "dataSent", $data, 1);
      readingsSingleUpdate($hash, "statusSent", $status, 1);
      Log3 $name, 3, "EnOcean set $name $cmd $data $status";
      shift(@a);

    } elsif ($st eq "remote") {
      return "Unknown argument $cmd, choose one of $cmdList";

    } else {
######
      # subtype does not support set commands
      $updateState = -1;
      if (AttrVal($name, "remoteManagement", "off") eq "manager") {
        return "Unknown argument $cmd, choose one of $cmdList";
      } else {
        return;
        #return "Unknown argument $cmd, choose one of";
      }
    }

    # set reading state if confirmation telegram is not expected
    if($updateState == 1 && $updateStateAttr =~ m/^default|yes$/) {
      readingsSingleUpdate($hash, "state", $cmd, 1);
    } elsif ($updateState == 0 && $updateStateAttr eq "yes") {
      readingsSingleUpdate($hash, "state", $cmd, 1);
    #} elsif ($updateState == 3) {
      #internal command
    #} else {
    #  readingsSingleUpdate($hash, ".info", "await_confirm", 0);
    }

    # send commands
    if($updateState >= -1 && $updateState <= 1) {
      EnOcean_SndCdm(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
      EnOcean_observeInit(1, $hash, @cmdObserve);
      if ($switchMode eq "pushbutton" && $cmd1 ne "released") {
        my @timerCmd = ($name, "released");
	my %par = (hash => $hash, timerCmd => \@timerCmd);
	InternalTimer(gettimeofday() + 0.1, "EnOcean_TimerSet", \%par, 0);
      }
    }
    #Log3 $name, 3, "EnOcean set $name remainder of CmdArg: " . join(' ' ,@a) if (@a > 0);
  }

  return undef;
}

# parse and display the incoming telegrams
sub EnOcean_Parse($$)
{
  my ($iohash, $msg) = @_;
  my $IODev = $iohash->{NAME};
  my ($hash, $name, $filelogName, $rorgname);
  my ($ctrl, $err, $logLevel, $response);
  Log3 $IODev, 5, "EnOcean received via $IODev: $msg";
  my @msg = split(':', $msg);
  my ($rorg, $data, $senderID, $status, $odata, $subDef, $destinationID, $funcNumber, $manufID, $RSSI, $delay, $subTelNum);
  my $packetType = hex($msg[1]);
  my @event;

  if ($packetType == 1) {
    # packet type RADIO
    #EnOcean:PacketType:RORG:MessageData:SourceID:Status:OptionalData
    (undef, undef, $rorg, $data, $senderID, $status, $odata) = @msg;
    $odata =~ m/^(..)(........)(..)(..)$/;
    ($subTelNum, $destinationID, $RSSI) = (hex($1), $2, hex($3));
    if (exists $modules{EnOcean}{defptr}{$senderID}) {
      $hash = $modules{EnOcean}{defptr}{$senderID};
    } elsif ($destinationID ne 'FFFFFFFF') {
      $hash = $modules{EnOcean}{defptr}{$destinationID};
    }
    $rorgname = $EnO_rorgname{$rorg};
    if (!$rorgname) {
      if($hash) {
        Log3 $hash->{NAME}, 4, "EnOcean $hash->{NAME} RORG $rorg unknown.";
      } else {
        Log3 undef, 4, "EnOcean $senderID RORG $rorg unknown.";
      }
      return "";
    }

    if ($rorg eq "40") {
      # chained data message (CDM)
      $data =~ m/^(..)(.*)$/;
      # SEQ evaluation?
      my ($seq, $idx) = (hex($1) & 0xC0, hex($1) & 0x3F);
      $data = $2;
      if ($idx == 0) {
        # first message part
        delete $iohash->{helper}{"cdm_$senderID-$seq"};
        $data =~ m/^(....)(..)(.*)$/;
        $iohash->{helper}{"cdm_$senderID-$seq"}{len} = hex($1);
        $iohash->{helper}{"cdm_$senderID-$seq"}{rorg} = $2;
        $iohash->{helper}{"cdm_$senderID-$seq"}{data}{$idx} = $3;
        $iohash->{helper}{"cdm_$senderID-$seq"}{lenCounter} = length($3) / 2;
        RemoveInternalTimer($iohash->{helper}{timer}{"helperClear_$senderID-$seq"}) if(exists $iohash->{helper}{timer}{"helperClear_$senderID-$seq"});
        $iohash->{helper}{timer}{"helperClear_$senderID-$seq"} = {hash => $iohash, function => "cdm_$senderID-$seq"};
        InternalTimer(gettimeofday() + 3, 'EnOcean_helperClear', $iohash->{helper}{timer}{"helperClear_$senderID-$seq"}, 0);
        #Log3 $IODev, 3, "EnOcean $IODev CDM timer started";
      } else {
        $iohash->{helper}{"cdm_$senderID-$seq"}{data}{$idx} = $data;
        $iohash->{helper}{"cdm_$senderID-$seq"}{lenCounter} += length($data) / 2;
      }
      if ($iohash->{helper}{"cdm_$senderID-$seq"}{lenCounter} >= $iohash->{helper}{"cdm_$senderID-$seq"}{len}) {
        # data message complete
        # reconstruct RORG, DATA
        my ($idx, $dataPart, @data);
        while (($idx, $dataPart) = each(%{$iohash->{helper}{"cdm_$senderID-$seq"}{data}})) {
          $data[$idx] = $iohash->{helper}{"cdm_$senderID-$seq"}{data}{$idx};
        }
        $data = join('', @data);
        $msg[3] = $data;
        $rorg = $iohash->{helper}{"cdm_$senderID-$seq"}{rorg};
        $msg[2] = $rorg;
        $msg = join(':', @msg);
        $rorgname = $EnO_rorgname{$rorg};
        if (!$rorgname) {
          Log3 undef, 4, "EnOcean $senderID RORG $rorg unknown.";
          return "";
        }
        delete $iohash->{helper}{"cdm_$senderID-$seq"};
        RemoveInternalTimer($iohash->{helper}{timer}{"helperClear_$senderID-$seq"}) if(exists $iohash->{helper}{timer}{"helperClear_$senderID-$seq"});
        delete $iohash->{helper}{timer}{"helperClear_$senderID-$seq"} if (exists $iohash->{helper}{timer}{"helperClear_$senderID-$seq"});
        #Log3 $IODev, 5, "EnOcean $IODev CDM RORG: $rorg concatenated DATA $data";
      } else {
        # wait for next data message part
        return $IODev;
      }
    }

    if($hash) {
      $name = $hash->{NAME};
      if ($rorg eq 'A5' && !(hex(substr($data, 6, 2)) & 8) &&
          hex(substr($data, 0, 2)) >> 2 == 0x3F &&
          (hex(substr($data, 0, 4)) >> 3 & 0x7F) == 0) {
        # find Radio Link Test device
        my $rltHash;
        foreach my $dev (keys %defs) {
          next if ($defs{$dev}{TYPE} ne 'EnOcean');
          next if (!exists($attr{$dev}{subType}));
          next if ($attr{$dev}{subType} ne 'radioLinkTest');
          $rltHash = $defs{$dev};
          last;
        }
        if (defined $rltHash) {
          if ($rltHash != $hash) {
            if (ReadingsVal($rltHash->{NAME}, 'state', '') =~ m/^standby$/) {
              # device is temporarily subType radioLinkTest
              @{$rltHash->{helper}{rlt}{oldDev}} = ($hash, $name, $hash->{DEF});
              CommandModify(undef, "$name 00000000");
              delete $modules{EnOcean}{defptr}{$hash->{DEF}};
              $hash = $rltHash;
              $name = $hash->{NAME};
              CommandModify(undef, "$name $senderID");
              $modules{EnOcean}{defptr}{$senderID} = $hash;
            } else {
              # Radio Link Test Devices not ready at the moment
              return '';
            }
          }
          Log3 $name, 4, "EnOcean received RLT Query messsage DATA: $data from DeviceID: $senderID";
        } else {
          Log3 $name, 4, "EnOcean received RLT Query messsage DATA: $data from DeviceID: $senderID";
        }
      } else {
        Log3 $name, 4, "EnOcean $name received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $senderID STATUS: $status";
      }
      $manufID = uc(AttrVal($name, "manufID", ""));
      $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
      $filelogName = "FileLog_$name";

      #if ($IODev ne $hash->{IODev}{NAME}) {
        # transceiver wrong
      #  Log3 $name, 4, "EnOcean $name locked telegram via $IODev PacketType: $packetType RORG: $rorg DATA: $data SenderID: $senderID STATUS: $status";
      #  return "";
      #}

    } else {
      # SenderID unknown, created new device
      Log3 undef, 5, "EnOcean received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $senderID STATUS: $status";
      my $learningMode = AttrVal($IODev, "learningMode", "demand");
      my $learningDev = AttrVal($IODev, "learningDev", "teachMsg");
      my $ret = "UNDEFINED EnO_$senderID EnOcean $senderID $msg";

      if ($rorgname =~ m/^GPCD|GPSD|SMLRNANS|SMREC|SIGNAL$/) {
        Log3 undef, 4, "EnOcean Received $rorgname telegram to the unknown device with SenderID $senderID.";
        return '';

      } elsif ($learningDev eq 'teachMsg' && ($rorgname =~ m/^VLD|MSC|SEC|ENC$/ || $rorgname eq '4BS' && (hex(substr($data, 6, 2))) & 8)) {
        Log3 undef, 4, "EnOcean Received $rorgname telegram to the unknown device with SenderID $senderID.";
        return '';

      } elsif ($rorg eq 'A5' &&
               hex(substr($data, 0, 2)) >> 2 == 0x3F &&
               (hex(substr($data, 0, 4)) >> 3 & 0x7F) == 0 &&
               !(hex(substr($data, 6, 2)) & 8)) {
        # find Radio Link Test device
        my $rltHash;
        foreach my $dev (keys %defs) {
          next if ($defs{$dev}{TYPE} ne 'EnOcean');
          next if (!exists($attr{$dev}{subType}));
          next if ($attr{$dev}{subType} ne 'radioLinkTest');
          $rltHash = $defs{$dev};
          last;
        }
        if ($rltHash) {
          return '' if (ReadingsVal($rltHash->{NAME}, 'state', '') !~ m/^standby$/);
          $hash = $rltHash;
          $name = $hash->{NAME};
          CommandModify(undef, "$name $senderID");
          $modules{EnOcean}{defptr}{$senderID} = $hash;
          $filelogName = "FileLog_$name";
          Log3 $name, 4, "EnOcean RLT Query messsage DATA: $data from SenderID: $senderID received";
          $manufID = uc(AttrVal($name, "manufID", ""));
          $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
        } else {
          Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and RLT Query message, please define it.";
          return $ret;
        }

      } elsif (exists $iohash->{helper}{teachConfirmWaitHash}) {
        # teach-in response with confirm telegram, assign remote device
        $hash = $iohash->{helper}{teachConfirmWaitHash};
        $name = $hash->{NAME};
        # substitute subDef with DEF
        delete $modules{EnOcean}{defptr}{$hash->{DEF}};
        $modules{EnOcean}{defptr}{$senderID} = $hash;
        $attr{$name}{subDef} = $hash->{DEF};
        $subDef = $attr{$name}{subDef};
        $hash->{DEF} = $senderID;
        $attr{$name}{comMode} = "confirm";
        $manufID = uc(AttrVal($name, "manufID", ""));
        $filelogName = "FileLog_$name";
        # clear teach-in request
        delete $iohash->{helper}{teachConfirmWaitHash};
        # store changes
        EnOcean_CommandSave(undef, undef);
        push @event, "3:teach:4BS teach-in accepted";
        Log3 $name, 2, "EnOcean $name remote device with SenderID $senderID assigned";

      } elsif ($learningMode eq "demand" && $iohash->{Teach}) {
        Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, please define it.";
        return $ret;
      } elsif ($learningMode eq "nearfield" && $iohash->{Teach} && $RSSI <= 60) {
        Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, please define it.";
        return $ret;
      } elsif ($learningMode eq "always") {
        if ($rorgname =~ m/^UTE|GPTI|GPTR$/) {
          if ($iohash->{Teach}) {
            Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, please define it.";
            return $ret;
          } else {
            Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, activate learning mode.";
            return "";
          }
        } elsif ($rorgname =~ m/^SMLRNREQ$/) {
          if ($iohash->{SmartAckLearn}) {
            Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, please define it.";
            return $ret;
          } else {
            Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, activate learning mode.";
            return "";
          }
        } else {
          Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, please define it.";
          return $ret;
        }
      } else {
        Log3 undef, 4, "EnOcean Unknown device with SenderID $senderID and $rorgname telegram, activate learning mode.";
        return "";
      }
    }

  } elsif ($packetType == 2) {
    # packet type RESPONSE
    #EnOcean:PacketType:ResposeCode:MessageData:OptionalData
    (undef, undef, $funcNumber, $data, $odata) = @msg;
    $data = defined($data) ? $data : '';
    $odata = defined($odata) ? $odata : '';
    my %codes = (
      "00" => "OK",
      "01" => "ERROR",
      "02" => "NOT_SUPPORTED",
      "03" => "WRONG_PARAM",
      "04" => "OPERATION_DENIED",
      "82" => "FLASH_HW_ERROR",
      "90" => "BASEID_OUT_OF_RANGE",
      "91" => "BASEID_MAX_REACHED",
    );
    my $rcTxt = $codes{$funcNumber} if($codes{$funcNumber});
    if($hash) {
      $name = $hash->{NAME};
      $funcNumber = hex($funcNumber);
      Log3 $name, $funcNumber == 0 ? 5 : 2, "EnOcean $name RESPONSE: $rcTxt DATA: $data ODATA: $odata";
      return $name;
    } else {
      Log3 undef, $funcNumber == 0 ? 5 : 2, "EnOcean RESPONSE: $rcTxt DATA: $data ODATA: $odata";
      return "";
    }

  } elsif ($packetType == 4) {
    # packet type EVENT
    #EnOcean:PacketType:EventCode:MessageData
    (undef, undef, $funcNumber, $data) = @msg;
    Log3 undef, 5, "EnOcean EventCode: $funcNumber DATA: $data";
    $funcNumber = hex($funcNumber);
    if ($funcNumber == 2) {
      # smart Ack confirm learn
      my ($priority, $rorg, $func, $type, $postmasterID, $hopCount);
      my $responseTime = 150;
      my $sendData = '';
      my $sendHash = defined($hash) ? $hash : $iohash;
      my $sendName = $sendHash->{NAME};
      $data =~ m/^(..)(....)(..)(..)(..)(..)(........)(........)(..)$/;
      ($priority, $manufID, $rorg, $func, $type, $RSSI, $postmasterID, $senderID, $hopCount) = (hex($1), $2, $3, $4, $5, hex($6), $7, $8, $9);
      #Log3 undef, 2, "EnOcean IOHASH: $iohash PRIORITY: $priority SmartAckLearn: " . (exists($iohash->{SmartAckLearn}) ? 1 : 0) .
      #               " SmartAckLearnWait: " . (exists($iohash->{helper}{smartAckLearnWait}) ? $iohash->{helper}{smartAckLearnWait} : '');
      if ($iohash->{SmartAckLearn} ||
          exists($iohash->{helper}{smartAckLearnWait}) && $iohash->{helper}{smartAckLearnWait} eq $sendName) {
        my $subType = "$rorg.$func.$type";
        if (exists $EnO_eepConfig{$subType}) {
          # EEP supported
          if (exists $modules{EnOcean}{defptr}{$senderID}) {
            $hash = $modules{EnOcean}{defptr}{$senderID};
          }
          $rorgname = $EnO_rorgname{$rorg};
          if($hash) {
            delete $iohash->{helper}{smartAckLearnWait};
            $name = $hash->{NAME};
            $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
            if (($priority & 15) == 15) {
              # device exists, learn OUT
              # send response, to delete mailbox
              $rorg = substr(AttrVal($name, "eep", '  '), 0, 2);
              $sendData = sprintf "00%04X20", $responseTime;
              EnOcean_SndRadio(undef, $hash, 2, $rorg, $sendData, $subDef, '00', $hash->{DEF});
              Log3 $name, 2, "EnOcean $name Smart Ack teach-out send";
              Log3 $name, 2, "EnOcean $name device $name deleted";
              CommandDelete(undef, $name);
              EnOcean_CommandSave(undef, undef);
              return '';

            } else {
              # config device
              Log3 $name, 5, "EnOcean $name received PacketType: $packetType EventCode: $funcNumber DATA: $data";
              $attr{$name}{subType} = $EnO_eepConfig{$subType}{attr}{subType};
              $attr{$name}{eep} = "$rorg-$func-$type";
              $manufID = sprintf "%03X", hex($manufID) & 0x7FF;
              $attr{$name}{manufID} = $manufID;
              $manufID = $EnO_manuf{$manufID} if(exists $EnO_manuf{$manufID});
              $attr{$name}{postmasterID} = $postmasterID;
              $hash->{SmartAckRSSI} = $RSSI;
              $attr{$name}{teachMethod} = 'smartAck';
              foreach my $attrCntr (keys %{$EnO_eepConfig{$subType}{attr}}) {
                if ($attrCntr ne "subDef") {
                  $attr{$name}{$attrCntr} = $EnO_eepConfig{$subType}{attr}{$attrCntr};
                }
              }
              #if (defined AttrVal($name, 'subDef', undef)) {
              #  $subDef = $attr{$name}{subDef};
              #} else {
                #$subDef = $postmasterID;
                #$attr{$name}{subDef} = $postmasterID;
              #}
              $subDef = '0' x 8;
              $attr{$name}{subDef} = '0' x 8;
              # sent response to create mailbox
              $sendData = sprintf "00%04X00", $responseTime;
              EnOcean_SndRadio(undef, $hash, 2, $rorg, $sendData, $subDef, '00', $hash->{DEF});
              readingsSingleUpdate($hash, "teach", "Smart Ack teach-in accepted EEP $rorg-$func-$type Manufacturer: $manufID", 1);
              Log3 $name, 2, "EnOcean $name Smart Ack teach-in accepted EEP $rorg-$func-$type Manufacturer: $manufID";
              EnOcean_CommandSave(undef, undef);
              return $name;
            }
          } else {
            # device unknown
            if (($priority & 5) == 5) {
              # Smart Ack priority ok (place for mailbox, good RSSI, Local)
              Log3 undef, 1, "EnOcean Unknown device with SenderID $senderID and Smart Ack learn In message, please define it.";
              return "UNDEFINED EnO_$senderID EnOcean $senderID $msg";
            } elsif (($priority & 5) == 1) {
              # Smart Ack no place for mailbox
              $sendData = sprintf "00%04X12", $responseTime;
              EnOcean_SndRadio(undef, $sendHash, 2, $rorg, $sendData, $postmasterID, '00', $senderID);
              Log3 $sendName, 2, "EnOcean $sendName Smart Ack learn in from SenderID $senderID Discard learn in, postmaster has no place for further mailbox";
              return '';
            } else {
              # Smart Ack priority to low
              $sendData = sprintf "00%04X13", $responseTime;
              EnOcean_SndRadio(undef, $sendHash, 2, $rorg, $sendData, $postmasterID, '00', $senderID);
              Log3 $sendName, 2, "EnOcean $sendName Smart Ack learn in from SenderID $senderID Discard learn in, priority to low";
              return '';
            }
          }
        } else {
          # EEP not supported
          # sent response
          $sendData = sprintf "00%04X11", $responseTime;
          EnOcean_SndRadio(undef, $sendHash, 2, $rorg, $sendData, $postmasterID, '00', $senderID);
          Log3 $sendName, 2, "EnOcean $sendName Smart Ack learn in from SenderID $senderID with EEP $rorg-$func-$type not supported";
          return '';
        }
      } else {
        # smart ack learn not activated
        $sendData = sprintf "00%04XFF", $responseTime;
        EnOcean_SndRadio(undef, $sendHash, 2, $rorg, $sendData, $postmasterID, '00', $senderID);
        Log3 $sendName, 2, "EnOcean $sendName Smart Ack learn in from SenderID $senderID received, activate learning";
        return '';
      }
    }

  } elsif ($packetType == 6) {
    # packet type SMART ACK
    #EnOcean:PacketType:SmartAckCode:MessageData
    (undef, undef, $funcNumber, $data) = @msg;
    if($hash) {
      $name = $hash->{NAME};
      $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
      Log3 $name, 2, "EnOcean $name received PacketType: $packetType Function Number: $funcNumber DATA: $data";
    } else {
      Log3 undef, 2, "EnOcean received PacketType: $packetType Function Number: $funcNumber DATA: $data";
      return "";
    }
    $funcNumber = hex($funcNumber);

  } elsif ($packetType == 7) {
    # packet type REMOTE_MAN_COMMAND
    #EnOcean:PacketType:RORG:MessageData:SourceID:DestinationID:FunctionNumber:ManufacturerID:RSSI:Delay
    (undef, undef, $rorg, $data, $senderID, $destinationID, $funcNumber, $manufID, $RSSI, $delay) = @msg;
    if (exists $modules{EnOcean}{defptr}{$senderID}) {
      $hash = $modules{EnOcean}{defptr}{$senderID};
      $name = $hash->{NAME};
      if (!exists $attr{$name}{remoteID}) {
        $attr{$name}{remoteID} = $senderID;
        Log3 $name, 2, "EnOcean $name remoteID $senderID assigned";
        if (exists($iohash->{helper}{remoteAnswerWait}{hex($funcNumber)}{hash}) &&
            $iohash->{helper}{remoteAnswerWait}{hex($funcNumber)}{hash} == $hash) {
          delete $iohash->{helper}{remoteAnswerWait}{hex($funcNumber)}{hash};
        }
      }

    } elsif (exists($iohash->{helper}{remoteAnswerWait}{hex($funcNumber)}{hash})) {
      # the remoteID is assigned to the requesting device
      $hash = $iohash->{helper}{remoteAnswerWait}{hex($funcNumber)}{hash};
      $name = $hash->{NAME};
      $subDef = '0' x 8;
      $attr{$name}{remoteID} = $senderID;
      $modules{EnOcean}{defptr}{$senderID} = $hash;
      delete $iohash->{helper}{remoteAnswerWait}{hex($funcNumber)}{hash};
      Log3 $name, 2, "EnOcean $name remoteID $senderID assigned";
      #EnOcean_CommandSave(undef, undef);
    } elsif ($destinationID ne 'FFFFFFFF') {
      $hash = $modules{EnOcean}{defptr}{$destinationID};
    }
    #$funcNumber = substr($funcNumber, 1);
    if($hash) {
      $name = $hash->{NAME};
      $manufID = substr($manufID, 1);
      $rorgname = $EnO_rorgname{$rorg};
      $subDef = '0' x 8;
      Log3 $name, 4, "EnOcean $name received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $senderID
                      DestinationID $destinationID Function Number: " . substr($funcNumber, 1) . " ManufacturerID: $manufID";
      $delay = hex($delay);
      $funcNumber = hex($funcNumber);
      $RSSI = hex($RSSI);
    } else {
      if (hex($funcNumber) == 4) {
        #Log3 undef, 1, "EnOcean received remote management query ID from unknown SenderID $senderID, please define device.";
        #return "UNDEFINED EnO_$senderID EnOcean $senderID $msg";
        return '';
      } else {
        return '';
      }
    }
  }

  my $eep = AttrVal($name, "eep", undef);
  my $smartAckLearn = $hash->{IODev}{SmartAckLearn};
  my $teach = $hash->{IODev}{Teach};
  my ($deleteDevice, $oldDevice);

  if (AttrVal($name, "secLevel", "off") =~ m/^encapsulation|encryption$/ &&
      AttrVal($name, "secMode", "") =~ m/^rcv|biDir$/) {
    if ($rorg eq "30" || $rorg eq "31") {
      Log3 $name, 5, "EnOcean $name secure data RORG: $rorg DATA: $data SenderID: $senderID STATUS: $status";
      ($err, $rorg, $data) = EnOcean_sec_convertToNonsecure($hash, $rorg, $data);
      if (defined $err) {
        Log3 $name, 2, "EnOcean $name security ERROR: $err";
        return "";
      }
    } elsif ($rorg eq "35") {
      # pass second teach-in telegram

    } else {
      Log3 $name, 2, "EnOcean $name unsecure telegram locked";
      return "";
    }
    if ($rorg eq "32") {
      if (defined $eep) {
        # reconstruct RORG
        $rorg = substr($eep, 0, 2);
        Log3 $name, 5, "EnOcean $name decrypted data RORG: 32 >> $rorg DATA: $data SenderID: $senderID STATUS: $status";
      } else {
        # Teach-In telegram expected
        # telegram analyse needed >> 1BS, 4BS, UTE
        if (length($data) == 14) {
          # UTE
          $rorg = "D4";
        } elsif (length($data) == 8) {
          # 4BS
          $rorg = "A5";
        } elsif (length($data) == 2) {
          # 1BS
          $rorg = "D5";
        } else {
          Log3 $name, 2, "EnOcean $name security teach-in failed, UTE, 4BS or 1BS teach-in message is missing";
          return "";
        }
      }
    }
  }

  if ($rorg eq "A6") {
    # addressing destination telegram (ADT)
    # reconstruct RORG, DATA
    $data =~ m/^(..)(.*)(........)$/;
    ($rorg, $data) = ($1, $2);
    $rorgname = $EnO_rorgname{$rorg};
    if (!$rorgname) {
      Log3 undef, 4, "EnOcean $senderID RORG $rorg unknown.";
      return "";
    }
    if ($destinationID ne $3) {
      Log3 $name, 1, "EnOcean $name ADT DestinationID wrong.";
      return "";
    }
    Log3 $name, 1, "EnOcean $name ADT decapsulation RORG: $rorg DATA: $data DestinationID: $3";
  }

  # compute data
  # extract data bytes $db[x] ... $db[0]
  my @db;
  my $dbCntr = 0;
  for (my $strCntr = length($data) / 2 - 1; $strCntr >= 0; $strCntr --) {
    $db[$dbCntr] = hex substr($data, $strCntr * 2, 2);
    $dbCntr ++;
  }

  my $model = AttrVal($name, "model", "");
  my $st = AttrVal($name, "subType", "");
  my $subtypeReading = AttrVal($name, "subTypeReading", undef);
  $st = $subtypeReading if (defined $subtypeReading);

  if ($rorg eq "F6") {
    # RPS Telegram
    my $event = "state";
    my $nu =  (hex($status) & 0x10) >> 4;
    # unused flags (AFAIK)
    #push @event, "1:T21:".((hex($status) & 0x20) >> 5);
    #push @event, "1:NU:$nu";

    if ($st eq "FRW" || $st eq "smokeDetector.02") {
      # smoke detector
      if (!exists($hash->{helper}{lastEvent}) || $hash->{helper}{lastEvent} != $db[0] || ReadingsVal($name, 'alarm', '') eq 'dead_sensor') {
        if ($db[0] == 0x30) {
          push @event, "3:alarm:off";
          push @event, "3:battery:low";
          $msg = ReadingsVal($name, 'state', 'off');
        } elsif ($db[0] == 0x10) {
          push @event, "3:battery:ok";
          push @event, "3:alarm:smoke-alarm";
          $msg = "smoke-alarm";
        } elsif ($db[0] == 0) {
          push @event, "3:alarm:off";
          push @event, "3:battery:ok";
          $msg = "off";
        }
        push @event, "3:$event:$msg";
        $hash->{helper}{lastEvent} = $db[0];
      }
      if (AttrVal($name, "signOfLife", 'on') eq 'on') {
        RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 1440), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      }

    } elsif ($st eq "windSpeed.00") {
      # wind speed threshold detector
      if (!exists($hash->{helper}{lastEvent}) || $hash->{helper}{lastEvent} != $db[0] || ReadingsVal($name, 'alarm', '') eq 'dead_sensor') {
        push @event, "3:alarm:off";
        if ($db[0] == 0x30) {
          push @event, "3:battery:low";
          $msg = ReadingsVal($name, 'state', 'off');
        } elsif ($db[0] == 0x10) {
          push @event, "3:windSpeed:on";
          push @event, "3:battery:ok";
          $msg = "on";
        } elsif ($db[0] == 0) {
          push @event, "3:windSpeed:off";
          push @event, "3:battery:ok";
          $msg = "off";
        }
        push @event, "3:$event:$msg";
        $hash->{helper}{lastEvent} = $db[0];
      }
      RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
      @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
      InternalTimer(gettimeofday() + 1320, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);

    } elsif ($model =~ m/FAE14|FHK14|FHK61$/) {
      # heating/cooling relay FAE14, FHK14, untested
      $event = "controllerMode";
      if ($db[0] == 0x30) {
        # night reduction 2 K
        push @event, "3:energyHoldOff:holdoff";
        $msg = "auto";
      } elsif ($db[0] == 0x10) {
        # off
        push @event, "3:energyHoldOff:normal";
        $msg = "off";
      } elsif ($db[0] == 0x70) {
        # on
        push @event, "3:energyHoldOff:normal";
        $msg = "auto";
      } elsif ($db[0] == 0x50) {
        # night reduction 4 K
        push @event, "3:energyHoldOff:holdoff";
        $msg = "auto";
      }
      push @event, "3:$event:$msg";

    } elsif ($st eq "gateway") {
      # Eltako switching, dimming
      if ($db[0] == 0x70) {
        $msg = "on";
      } elsif ($db[0] == 0x50) {
        $msg = "off";
      } elsif ($db[0] == 0x30) {
        $event = 'alert';
        $msg = "on";
      } elsif ($db[0] == 0x10) {
        $event = 'alert';
        $msg = "off";
      }
      push @event, "3:$event:$msg";

    } elsif ($st eq "manufProfile" && $manufID eq "00D") {
      # Eltako shutter
      if ($db[0] == 0x70) {
        # open
        if ($model eq 'Eltako_FSB_ACK') {
          push @event, "3:position:0";
          push @event, "3:anglePos:" . AttrVal($name, "angleMin", -90);
        }
        push @event, "3:endPosition:open_ack";
        $msg = "open_ack";
      } elsif ($db[0] == 0x50) {
        # closed
        push @event, "3:position:100";
        push @event, "3:anglePos:" . AttrVal($name, "angleMax", 90);
        push @event, "3:endPosition:closed";
        $msg = "closed";
      } elsif ($db[0] == 0) {
        # not reached or not available
        push @event, "3:endPosition:not_reached";
        $msg = "not_reached";
      } elsif ($db[0] == 1) {
        # up
        push @event, "3:endPosition:not_reached";
        $msg = "up";
      } elsif ($db[0] == 2) {
        # down
        push @event, "3:endPosition:not_reached";
        $msg = "down";
      }
      push @event, "3:$event:$msg";

    } elsif ($st eq "occupSensor.01" && $model eq "tracker") {
      # tracker
      push @event, "3:button:" . ($db[0] & 0x70 ? "pressed" : "released");

    } elsif ($st eq "switch.7F" && $manufID eq "00D") {
      $msg  = $EnO_ptm200btn[($db[0] & 0xE0) >> 5];
      $msg .= "," . $EnO_ptm200btn[($db[0] & 0x0E) >> 1] if ($db[0] & 1);
      $msg .= " released" if (!($db[0] & 0x10));
      push @event, "3:buttons:" . ($db[0] & 0x10 ? "pressed" : "released");
      if ($msg =~ m/A0/) {push @event, "3:channelA:A0";}
      if ($msg =~ m/AI/) {push @event, "3:channelA:AI";}
      if ($msg =~ m/B0/) {push @event, "3:channelB:B0";}
      if ($msg =~ m/BI/) {push @event, "3:channelB:BI";}
      if ($msg =~ m/C0/) {push @event, "3:channelC:C0";}
      if ($msg =~ m/CI/) {push @event, "3:channelC:CI";}
      if ($msg =~ m/D0/) {push @event, "3:channelD:D0";}
      if ($msg =~ m/DI/) {push @event, "3:channelD:DI";}
      push @event, "3:$event:$msg";

    } else {
      if ($nu) {
        if ($st eq "keycard") {
          # Key Card, not tested
          $msg = "keycard_inserted" if ($db[0] == 112);
        } elsif ($st eq "liquidLeakage") {
          # liquid leakage sensor, not tested
          $msg = "wet" if ($db[0] == 0x11);
        } else {
          # Theoretically there can be a released event with some of the A0, BI
          # pins set, but with the plastic cover on this wont happen.
          $msg  = $EnO_ptm200btn[($db[0] & 0xE0) >> 5];
          $msg .= "," . $EnO_ptm200btn[($db[0] & 0x0E) >> 1] if ($db[0] & 1);
          $msg .= " released" if (!($db[0] & 0x10));
          push @event, "3:buttons:" . ($db[0] & 0x10 ? "pressed" : "released");
          if ($msg =~ m/A0/) {push @event, "3:channelA:A0";}
          if ($msg =~ m/AI/) {push @event, "3:channelA:AI";}
          if ($msg =~ m/B0/) {push @event, "3:channelB:B0";}
          if ($msg =~ m/BI/) {push @event, "3:channelB:BI";}
          if ($msg =~ m/C0/) {push @event, "3:channelC:C0";}
          if ($msg =~ m/CI/) {push @event, "3:channelC:CI";}
          if ($msg =~ m/D0/) {push @event, "3:channelD:D0";}
          if ($msg =~ m/DI/) {push @event, "3:channelD:DI";}
        }
      } else {
        if ($db[0] & 0xC0) {
          # Only a Mechanical Handle is setting these bits when NU = 0
          $msg = "closed"           if ($db[0] == 0xF0);
          $msg = "open"             if ($db[0] == 0xE0);
          $msg = "tilted"           if ($db[0] == 0xD0);
          $msg = "open_from_tilted" if ($db[0] == 0xC0);
        } elsif ($st eq "keycard") {
          $msg = "keycard_removed";
        } elsif ($st eq "liquidLeakage") {
          $msg = "dry";
        } else {
          $msg = (($db[0] & 0x10) ? "pressed" : "released");
          push @event, "3:buttons:" . ($db[0] & 0x10 ? "pressed" : "released");
        }
      }
      # released events are disturbing when using a remote, since it overwrites
      # the "real" state immediately. In the case of an Eltako FSB14, FSB61 ...
      # the state should remain released.
      if ($msg =~ m/released$/ &&
          AttrVal($name, "sensorMode", "switch") ne "pushbutton" &&
          $model !~ m/(FT55|FSB.*|FSM12|FSM61|FTS12)$/) {
        $event = "buttons";
        $msg = "released";
      } else {
        push @event, "3:$event:$msg";
      }
    }

  } elsif ($rorg eq "D5") {
    # 1BS telegram
    if ($st eq "radioLinkTest") {
      # Radio Link Test (EEP A5-3F-00)
      @{$hash->{helper}{rlt}{param}} = ('parse', $hash, $data, $subDef, 'master', $RSSI);
      EnOcean_RLT($hash->{helper}{rlt}{param});
    } else {
      # Single Input Contact (EEP D5-00-01)
      # [EnOcean EMCS, Eltako FTK, STM-250]
        if (!($db[0] & 8)) {
          # teach-in
          $attr{$name}{eep} = "D5-00-01";
          $attr{$name}{manufID} = "7FF";
          $attr{$name}{subType} = "contact";
          push @event, "3:teach:1BS teach-in accepted EEP D5-00-01 Manufacturer: no ID";
          Log3 $name, 2, "EnOcean $name teach-in EEP D5-00-01 Manufacturer: no ID";
          # store attr subType, manufID ...
          EnOcean_CommandSave(undef, undef);
        }
        push @event, "3:state:" . ($db[0] & 1 ? "closed" : "open");
        CommandDeleteReading(undef, "$name alarm");
        if (AttrVal($name, "signOfLife", 'off') eq 'on') {
          RemoveInternalTimer($hash->{helper}{timer}{alarm})  if(exists $hash->{helper}{timer}{alarm});
          @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
          InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 1980), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
        }
    }

  } elsif ($rorg eq "A5") {
  # 4BS telegram
    if (($db[0] & 8) == 0) {
    # Teach-In telegram
      if ($teach || AttrVal($hash->{IODev}{NAME}, "learningMode", "demand") eq "always" || $st eq "radioLinkTest") {

        if ($db[0] & 0x80) {
          # 4BS Teach-In telegram with EEP and manufacturer ID
          my $func = sprintf "%02X", ($db[3] >> 2);
          my $type = sprintf "%02X", ((($db[3] & 3) << 5) | ($db[2] >> 3));
          my $mid = sprintf "%03X", ((($db[2] & 7) << 8) | $db[1]);
          # manufID to account for vendor-specific features
          $attr{$name}{manufID} = $mid;
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          my $st = "A5.$func.$type";
          $attr{$name}{eep} = "A5-$func-$type";

          if ($db[0] & 0x10) {
            # 4BS teach-in bidirectional response received
            Log3 $name, 5, "EnOcean $name 4BS teach-in response message from $senderID received";
            if ($teach && exists($hash->{IODev}{helper}{"4BSRespWait"}{$destinationID})) {
              if ($db[0] & 0x40) {
                # EEP supported
                if ($db[0] & 0x20) {
                  # SenderID stored
                  Log3 $name, 2, "EnOcean $name 4BS teach-in accepted by $senderID";
                  push @event, "3:teach:4BS teach-in accepted EEP $rorg-$func-$type Manufacturer: $mid";
                  $attr{$name}{comMode} = "biDir";
                  $attr{$name}{destinationID} = "unicast";
                  # substitute subDef with DEF
                  $attr{$name}{subDef} = $hash->{DEF};
                  $hash->{DEF} = $senderID;
                  $modules{EnOcean}{defptr}{$senderID} = $hash;
                  delete $modules{EnOcean}{defptr}{$destinationID};
                  # clear teach-in request
                  delete $hash->{IODev}{helper}{"4BSRespWait"}{$destinationID};
                  # store attr subType, manufID ...
                  EnOcean_CommandSave(undef, undef);

                } else {
                  # SenderID not stored / deleted
                  Log3 $name, 2, "EnOcean $name 4BS request not accepted by $senderID";
                  push @event, "3:teach:4BS request not accepted EEP $rorg-$func-$type Manufacturer: $mid";
                }
              } else {
                # EEP not suppported
                Log3 $name, 2, "EnOcean $name 4BS EEP not supported by $senderID";
                push @event, "3:teach:4BS EEP not supported EEP $rorg-$func-$type Manufacturer: $mid";
              }
            } else {
              Log3 $name, 2, "EnOcean $name 4BS teach-in response message from $senderID ignored";
            }

          } else {
            # 4BS teach-in query
            $attr{$name}{teachMethod} = '4BS';
            if(exists $EnO_eepConfig{$st}{attr}) {
              push @event, "3:teach:4BS teach-in accepted EEP A5-$func-$type Manufacturer: $mid";
              Log3 $name, 2, "EnOcean $name 4BS teach-in accepted EEP A5-$func-$type Manufacturer: $mid";
              foreach my $attrCntr (keys %{$EnO_eepConfig{$st}{attr}}) {
                if ($attrCntr eq "subDef") {
                  if (!defined AttrVal($name, $attrCntr, undef)) {
                    $attr{$name}{$attrCntr} = EnOcean_CheckSenderID($EnO_eepConfig{$st}{attr}{$attrCntr}, $hash->{IODev}{NAME}, "00000000");
                  }
                } else {
                  $attr{$name}{$attrCntr} = $EnO_eepConfig{$st}{attr}{$attrCntr};
                }
              }
              if (exists($hash->{helper}{teachInWait}) && $hash->{helper}{teachInWait} =~ m/^4BS|STE$/) {
                $attr{$filelogName}{logtype} = $EnO_eepConfig{$st}{GPLOT} . 'text'
                  if (exists $attr{$filelogName}{logtype});
                EnOcean_CreateSVG(undef, $hash, undef);
                delete $hash->{helper}{teachInWait};
              }
              $st = $EnO_eepConfig{$st}{attr}{subType};
            } else {
              push @event, "3:teach:4BS EEP not supported EEP A5-$func-$type Manufacturer: $mid";
              Log3 $name, 2, "EnOcean $name 4BS EEP not supported EEP A5-$func-$type Manufacturer: $mid";
              $attr{$name}{subType} = "raw";
              $st = "raw";
            }

            if ($teach || $st eq "radioLinkTest") {
              # bidirectional 4BS teach-in
              if ($st eq "hvac.01" || $st eq "MD15") {
                # EEP A5-20-01
                $attr{$name}{comMode} = "biDir";
                $attr{$name}{destinationID} = "unicast";
                ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
                # teach-in response
                EnOcean_SndRadio(undef, $hash, $packetType, $rorg, "800FFFF0", $subDef, "00", $hash->{DEF});
                Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};
                readingsSingleUpdate($hash, 'operationMode', 'setpointTemp', 0);

              } elsif ($st eq "hvac.02") {
                # EEP A5-20-02 not supported
                # teach-in response
                $data = sprintf "%06X90", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
                EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, "00000000", "00", $hash->{DEF});
                Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};

              } elsif ($st eq "hvac.03") {
                # EEP A5-20-03 not supported
                # teach-in response
                $data = sprintf "%06X90", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
                EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, "00000000", "00", $hash->{DEF});
                Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};

              } elsif ($st eq "hvac.04" || $st eq "hvac.06") {
                # heating radiator valve actuating drive (EEP A5-20-04)
                # Battery Powered Actuator (EEP A5-20-06)
                $attr{$name}{comMode} = "biDir";
                $attr{$name}{destinationID} = "unicast";
                ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
                # teach-in response
                $data = sprintf "%06XF0", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
                EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, "00", $hash->{DEF});
                Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};
                readingsSingleUpdate($hash, 'operationMode', 'setpointTemp', 0);

              } elsif ($st eq "radioLinkTest") {
                # Radio Link Test (EEP A5-3F-00)
                if (ReadingsVal($name, "state", 'standby') eq 'standby') {
                  $attr{$name}{comMode} = "biDir";
                  $attr{$name}{destinationID} = "unicast";
                  ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
                  # teach-in response, SenderID not stored
                  $data = sprintf "%06XD0", (hex($func) << 7 | hex($type)) << 11 | hex($attr{$name}{manufID});
                  #$data = sprintf "%06XD0", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
                  #$data = sprintf "%06XF0", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
                  EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, "00", $hash->{DEF});
                  Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};
                  @{$hash->{helper}{rlt}{param}} = ('start', $hash, undef, $subDef, 'master', $RSSI);
                  EnOcean_RLT($hash->{helper}{rlt}{param});
                }

              #} elsif ($st =~ m/^hvac\.1[0-1]$/) {
                # EEP A5-20-10, A5-20-11
                # teach-in response
              #  $data = sprintf "%06XF0", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
              #  EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, "00000000", "00", $hash->{DEF});
              #  Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};

              } elsif (AttrVal($name, "comMode", "") =~ m/^confirm|biDir$/) {
                # confirm telegram requested, teach-in response sent
                ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
                $data = sprintf "%06XF0", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
                EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, "00", $hash->{DEF});
                Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};

              #} else {
                # EEP not supported
                # teach-in response
              #  $data = sprintf "%06X90", (hex($func) << 7 | hex($type)) << 11 | 0x7FF;
              #  EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, "00000000", "00", $hash->{DEF});
              #  Log3 $name, 2, "EnOcean $name 4BS teach-in response sent to " . $hash->{DEF};
              }

            }

          }
          # store attr subType, manufID ...
          EnOcean_CommandSave(undef, undef);
          # delete standard readings
          CommandDeleteReading(undef, "$name sensor[0-9]");
          CommandDeleteReading(undef, "$name D[0-9]");

        } else {
          # 4BS Teach-In without EEP and manufacturer ID
          push @event, "3:teach:4BS teach-in accepted: No EEP profile identifier and no Manufacturer ID";
          Log3 $name, 2, "EnOcean $name 4BS teach-in accepted. No EEP profile identifier and no Manufacturer ID";
          $attr{$name}{subType} = "raw";
          $st = "raw";
        }

      } else {
        Log3 $name, 4, "EnOcean $name teach-in with subType $st locked, set transceiver in teach mode.";
        return "";
      }

    } elsif ($st eq "hvac.01" || $st eq "MD15") {
      # Battery Powered Actuator (EEP A5-20-01)
      # [Kieback&Peter MD15-FTL-xx]
      push @event, "3:energyInput:" . (($db[2] & 0x40) ? "enabled" : "disabled");
      my $battery = ($db[2] & 0x10) ? "ok" : "low";
      my $energyStorage;
      if ($db[2] & 0x20) {
        $energyStorage = 'charged';
        $battery = 'ok';
      } else {
        $energyStorage = 'empty';
      }
      if (!exists($hash->{helper}{battery}) || $hash->{helper}{battery} ne $battery) {
        push @event, "3:battery:$battery";
        $hash->{helper}{battery} = $battery;
      }
      push @event, "3:energyStorage:$energyStorage";
      my $roomTemp = ReadingsVal($name, "roomTemp", 20);
      if ($db[2] & 4) {
        CommandDeleteReading(undef, "$name roomTemp");
      } else {
        $roomTemp = $db[1] * 40 / 255;
        push @event, "3:roomTemp:" . sprintf "%0.1f", $roomTemp;
      }
      my $setpoint = $db[3];
      push @event, "3:setpoint:$setpoint";
      my $maintenanceMode = ReadingsVal($name, "maintenanceMode", ($db[2] & 0x80) ? 'on' : 'off');
#      if ($db[2] & 0x80) {
#        $maintenanceMode = 'on' if (!defined($maintenanceMode));
#      } else {
#        $maintenanceMode = 'off';
#      }
      push @event, "3:cover:" . (($db[2] & 8) ? "open" : "closed");
      my $window = ($db[2] & 2) ? "open" : "closed";
      push @event, "3:window:$window";
      push @event, "3:actuatorState:". (($db[2] & 1) ? "obstructed" : "ok");
      push @event, "3:selfCtrl:" . (($db[0] & 4) ? "on" : "off");
      my $functionSelect = 0;
      my $setpointSelect = 0;
      my $setpointSet = ReadingsVal($name, "setpointSetRestore", ReadingsVal($name, "setpointSet", $setpoint));
      CommandDeleteReading(undef, "$name setpointSetRestore");
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $setpointTempSet = ReadingsVal($name, "setpointTempSet", $setpointTemp);
      my $temperature = ReadingsVal($name, 'temperature', $roomTemp);
      if (!defined(AttrVal($name, "temperatureRefDev", undef))) {
        if ($db[2] & 4) {
          CommandDeleteReading(undef, "$name temperature");
        } else {
          $temperature = $roomTemp;
          readingsSingleUpdate($hash, 'temperature', sprintf("%0.1f", $temperature), 1);
        }
      }

      Log3 $name, 5, "EnOcean $name EnOcean_parse SPT: $setpointTemp SPTS: $setpointTempSet";

      my $operationMode = ReadingsVal($name, "operationMode", 'setpointTemp');
      my $setpointSummerMode = AttrVal($name, "setpointSummerMode", 0);
      my $summerMode = AttrVal($name, "summerMode", "off");
      my $timeDiff = EnOcean_TimeDiff(ReadingsTimestamp($name, 'wakeUpCycle', undef));
      my $waitingCmds = ReadingsVal($name, "waitingCmds", "no_change");
      my $wakeUpCycle = 600;
      # calc wakeup cycle
      if ($summerMode eq 'off') {
        $summerMode = 0;
        if ($timeDiff == 0 || $window eq 'open') {
          $wakeUpCycle = 1200;
        } elsif ($timeDiff < 120) {
          $wakeUpCycle = 120;
        } elsif ($timeDiff > 1200) {
          $wakeUpCycle = 1200;
        } else {
          $wakeUpCycle = int($timeDiff);
        }
      } else {
        $summerMode = 8;
        # ignore all commands
        if ($waitingCmds ne "summerMode") {
          $waitingCmds = "no_change";
          CommandDeleteReading(undef, "$name waitingCmds");
        }
        if ($manufID eq '049') {
          $wakeUpCycle = 28800;
        } else {
          $wakeUpCycle = 3600;
        }
      }
      readingsSingleUpdate($hash, 'wakeUpCycle', $wakeUpCycle, 1);
      # set alarm timer
      CommandDeleteReading(undef, "$name alarm");
      RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
      @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'no_response_from_actuator', 1, 3);
      InternalTimer(gettimeofday() + $wakeUpCycle * 1.1, "EnOcean_readingsSingleUpdate", $hash->{helper}{timer}{alarm}, 0);

      my $actionCmd = AttrVal($name, "rcvRespAction", undef);
      if (defined $actionCmd) {
        my %specials = ("%ACTUATORSTATE" => (($db[2] & 1) ? "obstructed" : "ok"),
                        "%BATTERY" => $battery,
                        "%COVER" => (($db[2] & 8) ? "open" : "closed"),
                        "%ENERGYINPUT" => (($db[2] & 0x40) ? "enabled" : "disabled"),
                        "%ENERGYSTORAGE" => $energyStorage,
                        "%MAINTENANCEMODE" => $maintenanceMode,
                        "%NAME" => $name,
                        "%OPERATIONMODE" => $operationMode,
                        "%ROOMTEMP" => $roomTemp,
                        "%SELFCTRL" => (($db[0] & 4) ? "on" : "off"),
                        "%SETPOINT" => $setpoint,
                        "%SETPOINTTEMP" => $setpointTemp,
                        "%SUMMERMODE" => $summerMode,
                        "%TEMPERATURE" => $temperature,
                        "%WINDOW" => (($db[2] & 2) ? "open" : "closed"),
                       );
          # action exec
          $actionCmd = EvalSpecials($actionCmd, %specials);
          my $ret = AnalyzeCommandChain(undef, $actionCmd);
          Log3 $name, 2, "Encean $name rcvRespAction ERROR: $ret" if($ret);
          $maintenanceMode = ReadingsVal($name, "maintenanceMode", ($db[2] & 0x80) ? 'on' : 'off');
          $operationMode = ReadingsVal($name, "operationMode", 'setpointTemp');
          $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
          $setpointTempSet = ReadingsVal($name, "setpointTempSet", $setpointTemp);
          $temperature = ReadingsVal($name, 'temperature', $roomTemp);
          $waitingCmds = ReadingsVal($name, "waitingCmds", "no_change");
      }

      if (AttrVal($name, 'windowOpenCtrl', 'disable') eq 'enable' && $window eq 'open') {
        # valve will be closed if the window is open
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 0;
        $db[2] = (40 - $temperature) * 255 / 40;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:windowOpen";
        if ($operationMode ne 'windowOpen') {
          push @event, "3:waitingCmds:$operationMode";
        }
        $waitingCmds = 0;

      } elsif ($waitingCmds eq "valveOpens") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 100;
        $db[2] = 0x20;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:valveOpend:runInit";
        push @event, "3:operationMode:off";
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $functionSelect = 1;
        $waitingCmds = 0x20;

      } elsif ($waitingCmds eq "valveCloses") {
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        if ($maintenanceMode eq "valveOpend:runInit") {
          $setpointSet = 100;
          $db[2] = 0x20;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:runInit";
          push @event, "3:operationMode:off";
          $functionSelect = 1;
          $waitingCmds = 0x80;
        } else {
          $setpointSet = 0;
          $db[2] = 0x20;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:valveClosed";
          push @event, "3:operationMode:off";
          CommandDeleteReading(undef, "$name waitingCmds");
          $functionSelect = 1;
          $waitingCmds = 0x10;
        }
        # stop PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");

      } elsif ($waitingCmds eq "runInit") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 0;
        $db[2] = 0x20;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:runInit";
        push @event, "3:operationMode:off";
        push @event, "3:waitingCmds:$operationMode";
        #CommandDeleteReading(undef, "$name setpointSet");
        #CommandDeleteReading(undef, "$name setpointTemp");
        #CommandDeleteReading(undef, "$name setpointTempSet");
        #CommandDeleteReading(undef, "$name waitingCmds");
        $functionSelect = 1;
        $waitingCmds = 0x80;

      } elsif ($waitingCmds eq "liftSet") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 0;
        $db[2] = 0x20;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:listSet";
        push @event, "3:operationMode:off";
        push @event, "3:waitingCmds:$operationMode";
        #CommandDeleteReading(undef, "$name setpointSet");
        #CommandDeleteReading(undef, "$name setpointTemp");
        #CommandDeleteReading(undef, "$name setpointTempSet");
        #CommandDeleteReading(undef, "$name waitingCmds");
        $functionSelect = 1;
        $waitingCmds = 0x40;

      } elsif ($waitingCmds eq "setpoint") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($maintenanceMode eq "valveOpend:runInit") {
          $setpointSet = 100;
          $db[2] = 0x20;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:runInit";
          push @event, "3:operationMode:off";
          $functionSelect = 1;
          $waitingCmds = 0x80;
        } else {
          $db[2] = (40 - $temperature) * 255 / 40;
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpoint";
          CommandDeleteReading(undef, "$name setpointTemp");
          CommandDeleteReading(undef, "$name setpointTempSet");
          CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 0;
        }

      } elsif ($waitingCmds eq "setpointTemp") {
        if ($maintenanceMode eq "valveOpend:runInit") {
          # deactivate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          $setpointSet = 100;
          $db[2] = 0x20;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:runInit";
          push @event, "3:operationMode:off";
          $functionSelect = 1;
          $waitingCmds = 0x80;
        } else {
          if (AttrVal($name, "pidCtrl", 'on') eq 'on') {
            # activate PID regulator
            ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'actuator', undef);
            $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
          } else {
            # deactivate PID regulator
            ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
            # setpoint temperature
            $setpointSet = $setpointTempSet * 255 / 40;
            $setpointSelect = 4;
          }
          $setpointTemp = $setpointTempSet;
          $db[2] = (40 - $temperature) * 255 / 40;
          push @event, "3:setpointTemp:" . sprintf("%0.1f", $setpointTemp);
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpointTemp";
          CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 0;
        }

      } elsif ($waitingCmds eq "summerMode") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = $setpointSummerMode;
        $db[2] = (40 - $temperature) * 255 / 40;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:summerMode";
        #CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 0;

      } elsif ($operationMode eq "setpoint") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($maintenanceMode eq "valveOpend:runInit") {
          $setpointSet = 100;
          $db[2] = 0x20;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpoint";
          $functionSelect = 1;
          $waitingCmds = 0x80;
        } else {
          $db[2] = (40 - $temperature) * 255 / 40;
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpoint";
          $waitingCmds = 0;
        }

      } elsif ($operationMode eq "setpointTemp") {
        if ($maintenanceMode eq "valveOpend:runInit") {
          # deactivate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          $setpointSet = 100;
          $db[2] = 0x20;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpointTemp";
          $functionSelect = 1;
          $waitingCmds = 0x80;
        } else {
          if (AttrVal($name, "pidCtrl", 'on') eq 'on') {
            # activate PID regulator
            ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'actuator', undef);
            $setpointSet = ReadingsVal($name, "setpointSet", $setpointSet);
          } else {
            # deactivate PID regulator
            ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
            # setpoint temperature
            $setpointSet = $setpointTempSet * 255 / 40;
            $setpointSelect = 4;
          }
          $db[2] = (40 - $temperature) * 255 / 40;
          $setpointTemp = $setpointTempSet;
          push @event, "3:setpointTemp:" . sprintf("%.1f", $setpointTemp);
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpointTemp";
          $waitingCmds = 0;
        }

      } elsif ($operationMode eq "summerMode") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = $setpointSummerMode;
        $db[2] = (40 - $temperature) * 255 / 40;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:summerMode";
        $waitingCmds = 0;

       } elsif ($maintenanceMode eq "valveOpend:runInit") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = 100;
        $db[2] = 0x20;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:valveOpend:runInit";
        push @event, "3:operationMode:off";
        #CommandDeleteReading(undef, "$name setpointSet");
        #CommandDeleteReading(undef, "$name setpointTemp");
        #CommandDeleteReading(undef, "$name setpointTempSet");
        #CommandDeleteReading(undef, "$name waitingCmds");
        $functionSelect = 1;
        $waitingCmds = 0x20;

      } elsif ($maintenanceMode eq "valveClosed") {
        # stop PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = 0;
        $db[2] = 0x20;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:valveClosed";
        push @event, "3:operationMode:off";
        #CommandDeleteReading(undef, "$name setpointSet");
        #CommandDeleteReading(undef, "$name setpointTemp");
        #CommandDeleteReading(undef, "$name setpointTempSet");
        #CommandDeleteReading(undef, "$name waitingCmds");
        $functionSelect = 1;
        $waitingCmds = 0x10;

      } else {
        $db[2] = (40 - $temperature) * 255 / 40;
        $waitingCmds = 0;
      }
      push @event, "3:state:T: " . sprintf("%0.1f", $temperature) . " SPT: " . sprintf("%.1f", $setpointTemp) . " SP: $setpoint";
      # sent message to the actuator
      $data = sprintf "%02X%02X%02X08", $setpointSet, $db[2], $waitingCmds | $summerMode | $setpointSelect | $functionSelect;
      EnOcean_SndRadio(undef, $hash, $packetType, "A5", $data, $subDef, "00", $hash->{DEF});

    } elsif ($st eq "hvac.04") {
      # heating radiator valve actuating drive EEP A5-20-04)
      my %failureCode = (
        17 => "measurement_error",
        18 => "battery_empty",
        20 => "frost_protection",
        33 => "blocked_valve",
        36 => "end_point_detection_error",
        40 => "no_valve",
        49 => "not_taught_in",
        53 => "no_response_from_controller",
        54 => "teach-in_error"
      );
      my $battery = "ok";
      my %displayOrientation = (0 => 0, 90 => 1, 180 => 2, 270 => 3);
      my $feedTemp = ReadingsVal($name, "feedTemp", 20);
      my $roomTemp = ReadingsVal($name, "roomTemp", 20);
      my $setpoint = $db[3];
      push @event, "3:setpoint:$setpoint";
      my $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $setpointTempSet = ReadingsVal($name, "setpointTempSet", $setpointTemp);
      my $temperature = ReadingsVal($name, "temperature", $roomTemp);
      if ($db[0] & 2) {
        if ($setpointTemp == $setpointTempSet) {
          $setpointTemp = sprintf "%0.1f", ($db[2] * 20 / 255 + 10);
          if ($setpointTemp != $setpointTempSet) {
            # setpointTempSet has been changed by actuator
            $setpointTempSet = $setpointTemp;
            readingsSingleUpdate($hash, 'setpointTempSet', $setpointTempSet, 1);
          }
        } else {
          # setpointTempSet has been changed by Fhem
          $setpointTemp = sprintf "%0.1f", ($db[2] * 20 / 255 + 10);
        }
        push @event, "3:setpointTemp:$setpointTemp";

      } else {
        if ($db[0] & 0x80) {
          # temperature measurement inactive
          CommandDeleteReading(undef, "$name feedTemp");
        } else {
          $feedTemp = $db[2] * 60 / 255 + 20;
          push @event, "3:feedTemp:" . sprintf("%0.1f", $feedTemp);
        }
      }
      if ($db[0] & 1) {
        # failure code
        if (exists $failureCode{$db[1]}) {
          push @event, "3:alarm:" . $failureCode{$db[1]};
          $battery = "empty" if ($db[1] == 18);
        } else {
          CommandDeleteReading(undef, "$name alarm");
        }
      } else {
        if ($db[0] & 0x80) {
          # temperature measurement inactive
          CommandDeleteReading(undef, "$name roomTemp");
        } else {
          # room temperature
          $roomTemp = sprintf("%0.1f", ($db[1] * 20 / 255 + 10));
          push @event, "3:roomTemp:$roomTemp";
          CommandDeleteReading(undef, "$name alarm");
        }
      }
      if (!defined(AttrVal($name, "temperatureRefDev", undef))) {
        if ($db[0] & 0x80) {
          # temperature measurement needed, activate temperature measurement
          $attr{$name}{measurementCtrl} = 'enable';
          EnOcean_CommandSave(undef, undef);
        } else {
          $temperature = $roomTemp;
          readingsSingleUpdate($hash, 'temperature', $temperature, 1);
          #push @event, "3:temperature:$temperature";
        }
      }
      push @event, "3:measurementState:" . ($db[0] & 0x80 ? "inactive" : "active");
      push @event, "3:blockKey:" . ($db[0] & 4 ? "yes" : "no");
      if (!exists($hash->{helper}{battery}) || $hash->{helper}{battery} ne $battery) {
        push @event, "3:battery:$battery";
        $hash->{helper}{battery} = $battery;
      }
      #push @event, "3:state:T: $temperature SPT: $setpointTemp SP: $setpoint";

      if ($db[0] & 0x40) {
        # status request
        # action needed?
      }

      Log3 $name, 5, "EnOcean $name EnOcean_parse SPT: $setpointTemp SPTS: $setpointTempSet";

      my $activatePID = AttrVal($name, 'pidCtrl', 'on') eq 'on' ? 'actuator' : 'stop';
      my $blockKey = ((AttrVal($name, "blockKey", 'no') eq 'yes') ? 1 : 0) << 2;
      my $displayOrientation = $displayOrientation{AttrVal($name, "displayOrientation", 0)} << 4;
      my $maintenanceMode = ReadingsVal($name, "maintenanceMode", "off");
      my $measurementCtrl = (AttrVal($name, 'measurementCtrl', 'enable') eq 'enable') ? 0 : 0x40;
      #my $operationMode = ReadingsVal($name, "operationMode", "off");
      my $operationMode = ReadingsVal($name, "operationMode", ((AttrVal($name, 'pidCtrl', 'on') eq 'on') ? 'setpointTemp' : 'setpoint'));
      my $summerMode = AttrVal($name, "summerMode", "off");
      my $waitingCmds = ReadingsVal($name, "waitingCmds", "no_change");
      my $wakeUpCycle = $wakeUpCycle{AttrVal($name, "wakeUpCycle", 300)};
      if ($summerMode eq 'off' && $wakeUpCycle >= 50) {
        # set default Wake-up Cycle (300 s)
        $wakeUpCycle = 9;
      } elsif ($summerMode eq 'on') {
        if ($waitingCmds ne "summerMode") {
          $waitingCmds = "no_change";
          CommandDeleteReading(undef, "$name waitingCmds");
        }
        $setpointSet = 100;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        $wakeUpCycle = 50 if ($wakeUpCycle < 50);
      }

      my $actionCmd = AttrVal($name, "rcvRespAction", undef);
      if (defined $actionCmd) {
        my %specials = ("%BATTERY" => $battery,
                        "%FEEDTEMP" => $feedTemp,
                        "%MAINTENANCEMODE" => $maintenanceMode,
                        "%NAME" => $name,
                        "%OPERATIONMODE" => $operationMode,
                        "%ROOMTEMP" => $roomTemp,
                        "%SETPOINT" => $setpoint,
                        "%SETPOINTTEMP" => $setpointTemp,
                        "%SUMMERMODE" => $summerMode,
                        "%TEMPERATURE" => $temperature,
                       );
          # action exec
          $actionCmd = EvalSpecials($actionCmd, %specials);
          my $ret = AnalyzeCommandChain(undef, $actionCmd);
          Log3 $name, 2, "EnOcean $name rcvRespAction ERROR: $ret" if($ret);
          $maintenanceMode = ReadingsVal($name, "maintenanceMode", 'off');
          $operationMode = ReadingsVal($name, "operationMode", ((AttrVal($name, 'pidCtrl', 'on') eq 'on') ? 'setpointTemp' : 'setpoint'));
          $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
          $setpointTempSet = ReadingsVal($name, "setpointTempSet", $setpointTemp);
          $temperature = ReadingsVal($name, 'temperature', $roomTemp);
          $waitingCmds = ReadingsVal($name, "waitingCmds", "no_change");
      }

      if ($waitingCmds eq "valveOpens") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = 100;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:valveOpend:runInit";
        push @event, "3:operationMode:off";
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 1;

      } elsif ($waitingCmds eq "valveCloses") {
        if ($maintenanceMode eq "valveOpend:runInit") {
          $setpointSet = 100;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:runInit";
          push @event, "3:operationMode:off";
          $waitingCmds = 2;
        } else {
          $setpointSet = 0;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:valveClosed";
          push @event, "3:operationMode:off";
          CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 3;
        }
        # stop PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");

      } elsif ($waitingCmds eq "runInit") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = 100;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:runInit";
        push @event, "3:operationMode:off";
        CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 2;

      } elsif ($waitingCmds eq "setpoint") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($maintenanceMode eq "valveOpend:runInit") {
          $setpointSet = 100;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:runInit";
          push @event, "3:operationMode:off";
          $waitingCmds = 2;
        } else {
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpoint";
          #CommandDeleteReading(undef, "$name setpointSet");
          CommandDeleteReading(undef, "$name setpointTemp");
          CommandDeleteReading(undef, "$name setpointTempSet");
          CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 0;
        }

      } elsif ($waitingCmds eq "setpointTemp") {
        if ($maintenanceMode eq "valveOpend:runInit") {
          # deactivate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          $setpointSet = 100;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:runInit";
          push @event, "3:operationMode:off";
          $waitingCmds = 2;
        } else {
          # activate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, $activatePID, undef);
          $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
          $setpointTemp = $setpointTempSet;
          push @event, "3:setpointTemp:$setpointTemp";
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpointTemp";
          #CommandDeleteReading(undef, "$name setpointSet");
          #CommandDeleteReading(undef, "$name setpointTempSet");
          CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 0;
        }

      } elsif ($waitingCmds eq "summerMode") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = 100;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:summerMode";
        #CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 0;

      } elsif ($operationMode eq "setpoint") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($maintenanceMode eq "valveOpend:runInit") {
          $setpointSet = 100;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpoint";
          $waitingCmds = 2;
        } else {
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpoint";
          #CommandDeleteReading(undef, "$name setpointSet");
          #CommandDeleteReading(undef, "$name setpointTemp");
          #CommandDeleteReading(undef, "$name setpointTempSet");
          #CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 0;
        }

      } elsif ($operationMode eq "setpointTemp") {
        if ($maintenanceMode eq "valveOpend:runInit") {
          # deactivate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          $setpointSet = 100;
          readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpointTemp";
          $waitingCmds = 2;
        } else {
          # activate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, $activatePID, undef);
          $setpointSet = ReadingsVal($name, "setpointSet", $setpointSet);
          push @event, "3:setpointTemp:$setpointTemp";
          push @event, "3:maintenanceMode:off";
          push @event, "3:operationMode:setpointTemp";
          #CommandDeleteReading(undef, "$name setpointSet");
          #CommandDeleteReading(undef, "$name setpointTempSet");
          #CommandDeleteReading(undef, "$name waitingCmds");
          $waitingCmds = 0;
        }

      } elsif ($operationMode eq "summerMode") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = 100;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:summerMode";
        #CommandDeleteReading(undef, "$name setpointSet");
        #CommandDeleteReading(undef, "$name setpointTemp");
        #CommandDeleteReading(undef, "$name setpointTempSet");
        #CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 0;

      } else {
        $waitingCmds = 0;
      }
      push @event, "3:state:T: $temperature SPT: $setpointTemp SP: $setpoint";
      # sent message to the actuator
      $data = sprintf "%02X%02X%02X%02X", $setpointSet,
                                          ($setpointTempSet - 10) / 20 * 255,
                                          (AttrVal($name, 'pidCtrl', 'on') eq 'on' ? 0 : 0x80) | $measurementCtrl | $wakeUpCycle,
                                          $displayOrientation | 8 | $blockKey | $waitingCmds;
      EnOcean_SndRadio(undef, $hash, $packetType, "A5", $data, $subDef, "00", $hash->{DEF});

    } elsif ($st eq "hvac.06") {
      # Battery Powered Actuator (EEP A5-20-06)
      # [Micropelt iTRV MVA-005, OPUS Micropelt HOME]
      my $maintenanceMode = ReadingsVal($name, "maintenanceMode", 'off');
      push @event, "3:energyInput:" . (($db[0] & 0x40) ? "enabled" : "disabled");
      my $battery;
      my $energyStorage;
      if ($db[0] & 0x20) {
        $energyStorage = 'charged';
        $battery = 'ok';
      } else {
        $energyStorage = 'empty';
        $battery = 'low';
      }
      if (!exists($hash->{helper}{battery}) || $hash->{helper}{battery} ne $battery) {
        push @event, "3:battery:$battery";
        $hash->{helper}{battery} = $battery;
      }
      push @event, "3:energyStorage:$energyStorage";
      my $feedTemp = ReadingsVal($name, "feedTemp", 20);
      my $roomTemp = ReadingsVal($name, "roomTemp", 20);
      if ($db[0] & 0x80) {
        $feedTemp = $db[1] / 2;
        push @event, "3:feedTemp:" . sprintf "%0.1f", $db[1] / 2;
        CommandDeleteReading(undef, "$name roomTemp");
      } else {
        $roomTemp = $db[1] / 2;
        push @event, "3:roomTemp:" . sprintf "%0.1f", $db[1] / 2;
        CommandDeleteReading(undef, "$name feedTemp");
      }
      my $setpoint = $db[3];
      push @event, "3:setpoint:$setpoint";
      my $window = ($db[0] & 0x10) ? "open" : "closed";
      push @event, "3:window:$window";
      push @event, "3:radioComErr:" . (($db[0] & 4) ? "on" : "off");
      push @event, "3:radioSignalStrength:" . (($db[0] & 2) ? "weak" : "strong");
      push @event, "3:actuatorState:". (($db[0] & 1) ? "obstructed" : "ok");
      my $functionSelect = 0;
      my $setpointSelect = 0;
      my $setpointSet = ReadingsVal($name, "setpointSetRestore", ReadingsVal($name, "setpointSet", $setpoint));
      CommandDeleteReading(undef, "$name setpointSetRestore");
      my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
      my $setpointTempSet = ReadingsVal($name, "setpointTempSet", $setpointTemp);
      my %setpointTempOffset = (0 => 0, 1 => 1, 2 => 2, 3 => 3, 4 => 4, 5 => 5, 0x7B => -5, 0x7C => -4, 0x7D => -3, 0x7E => -2, 0x7F => -1);
      my $setpointTempLocal = $db[2] & 0x7F;
      if ($setpointTempSet == $setpointTemp) {
        # setpointTempSet has not been changed by Fhem
        if ($db[2] & 0x80) {
          $setpointTempLocal = $setpointTempLocal / 2;
        } else {
          $setpointTempLocal = $setpointTempSet + $setpointTempOffset{$setpointTempLocal};
        }
        if (AttrVal($name, "blockKey", 'no') eq 'no') {
          $setpointTempSet = $setpointTempLocal;
          readingsSingleUpdate($hash, 'setpointTempSet', $setpointTempSet, 1);
        }
      }

      my $temperature = ReadingsVal($name, 'temperature', $roomTemp);
      if (!defined(AttrVal($name, "temperatureRefDev", undef))) {
        if ($db[0] & 0x80) {
          CommandDeleteReading(undef, "$name temperature");
        } else {
          $temperature = $roomTemp;
          readingsSingleUpdate($hash, 'temperature', sprintf("%0.1f", $temperature), 1);
        }
      }

      Log3 $name, 5, "EnOcean $name EnOcean_parse SPT: $setpointTemp SPTS: $setpointTempSet";

      my $operationMode = ReadingsVal($name, "operationMode", 'setpointTemp');
      my $setpointSummerMode = AttrVal($name, "setpointSummerMode", 0);
      my $summerMode = AttrVal($name, "summerMode", "off");
      my $timeDiff = EnOcean_TimeDiff(ReadingsTimestamp($name, 'wakeUpCycle', undef));
      my $waitingCmds = ReadingsVal($name, "waitingCmds", "no_change");
      my $wakeUpCycle = 600;
      # calc wakeup cycle
      if ($summerMode eq 'off') {
        $summerMode = 0;
        if ($timeDiff == 0 || $window eq 'open') {
          $wakeUpCycle = 600;
        } elsif ($timeDiff < 120) {
          $wakeUpCycle = 120;
        } elsif ($timeDiff > 7200) {
          $wakeUpCycle = 7200;
        } else {
          $wakeUpCycle = int($timeDiff);
        }
      } else {
        $summerMode = 8;
        # ignore all commands
        if ($waitingCmds ne "summerMode") {
          $waitingCmds = "no_change";
          CommandDeleteReading(undef, "$name waitingCmds");
        }
        $wakeUpCycle = 28800;
      }
      readingsSingleUpdate($hash, 'wakeUpCycle', $wakeUpCycle, 1);
      # set alarm timer
      CommandDeleteReading(undef, "$name alarm");
      if ($waitingCmds ne "standby") {
        RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'no_response_from_actuator', 1, 3);
        InternalTimer(gettimeofday() + ($wakeUpCycle < 600 ? 600 : $wakeUpCycle) * 1.1, "EnOcean_readingsSingleUpdate", $hash->{helper}{timer}{alarm}, 0);
      }
      my $actionCmd = AttrVal($name, "rcvRespAction", undef);
      if (defined $actionCmd) {
        my %specials = ("%ACTUATORSTATE" => (($db[0] & 1) ? "obstructed" : "ok"),
                        "%BATTERY" => $battery,
                        "%ENERGYINPUT" => (($db[0] & 0x40) ? "enabled" : "disabled"),
                        "%ENERGYSTORAGE" => $energyStorage,
                        "%FEEDTEMP" => $feedTemp,
                        "%MAINTENANCEMODE" => $maintenanceMode,
                        "%NAME" => $name,
                        "%OPERATIONMODE" => $operationMode,
                        "%RADIOCOMERR" => (($db[0] & 4) ? "on" : "off"),
                        "%RADIOSIGNALSTRENGTH" => (($db[0] & 2) ? "weak" : "strong"),
                        "%ROOMTEMP" => $roomTemp,
                        "%SETPOINT" => $setpoint,
                        "%SETPOINTTEMP" => $setpointTemp,
                        "%SETPOINTTEMPLOCAL" => $setpointTempLocal,
                        "%SUMMERMODE" => $summerMode,
                        "%TEMPERATURE" => $temperature,
                        "%WINDOW" => (($db[0] & 0x10) ? "open" : "closed"),
                       );
          # action exec
          $actionCmd = EvalSpecials($actionCmd, %specials);
          my $ret = AnalyzeCommandChain(undef, $actionCmd);
          Log3 $name, 2, "Encean $name rcvRespAction ERROR: $ret" if($ret);
          $maintenanceMode = ReadingsVal($name, "maintenanceMode", ($db[2] & 0x80) ? 'on' : 'off');
          $operationMode = ReadingsVal($name, "operationMode", 'setpointTemp');
          $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
          $setpointTempSet = ReadingsVal($name, "setpointTempSet", $setpointTemp);
          $temperature = ReadingsVal($name, 'temperature', $roomTemp);
          $waitingCmds = ReadingsVal($name, "waitingCmds", "no_change");
      }

      if (AttrVal($name, 'windowOpenCtrl', 'disable') eq 'enable' && $window eq 'open') {
        # valve will be closed if the window is open
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 0;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:windowOpen";
        if ($operationMode ne 'windowOpen') {
          push @event, "3:waitingCmds:$operationMode";
        }
        $waitingCmds = 0;

      } elsif ($waitingCmds eq "runInit") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 0;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:runInit";
        push @event, "3:operationMode:off";
        push @event, "3:waitingCmds:$operationMode";
        $waitingCmds = 0x80;

      } elsif ($waitingCmds eq "standby") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = 0;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:standby";
        push @event, "3:waitingCmds:$operationMode";
        $functionSelect = 1;
        $waitingCmds = 0;

      } elsif ($waitingCmds eq "setpoint") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:setpoint";
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 0;

      } elsif ($waitingCmds eq "setpointTemp") {
        if (AttrVal($name, "pidCtrl", 'on') eq 'on') {
          # activate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'actuator', undef);
          $setpointSet = ReadingsVal($name, "setpointSet", $setpoint);
        } else {
          # deactivate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          # setpoint temperature
          $setpointSet = int($setpointTempSet * 2);
          $setpointSelect = 4;
        }
        $setpointTemp = $setpointTempSet;
        push @event, "3:setpointTemp:" . sprintf("%0.1f", $setpointTemp);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:setpointTemp";
        #CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 0;

      } elsif ($waitingCmds eq "summerMode") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        if ($operationMode eq 'setpoint') {
          readingsSingleUpdate($hash, 'setpointSetRestore', $setpointSet, 1);
        }
        $setpointSet = $setpointSummerMode;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:summerMode";
        #CommandDeleteReading(undef, "$name setpointSet");
        CommandDeleteReading(undef, "$name setpointTemp");
        CommandDeleteReading(undef, "$name setpointTempSet");
        CommandDeleteReading(undef, "$name waitingCmds");
        $waitingCmds = 0;

      } elsif ($operationMode eq "setpoint") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:setpoint";
        $waitingCmds = 0;

      } elsif ($operationMode eq "setpointTemp") {
        if (AttrVal($name, "pidCtrl", 'on') eq 'on') {
          # activate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'actuator', undef);
          $setpointSet = ReadingsVal($name, "setpointSet", $setpointSet);
        } else {
          # deactivate PID regulator
          ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
          # setpoint temperature
          $setpointSet = int($setpointTempSet * 2);
          $setpointSelect = 4;
        }
        $setpointTemp = $setpointTempSet;
        push @event, "3:setpointTemp:" . sprintf("%.1f", $setpointTemp);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:setpointTemp";
        $waitingCmds = 0;

      } elsif ($operationMode eq "summerMode") {
        # deactivate PID regulator
        ($err, $logLevel, $response) = EnOcean_setPID(undef, $hash, 'stop', undef);
        $setpointSet = $setpointSummerMode;
        readingsSingleUpdate($hash, 'setpointSet', $setpointSet, 1);
        push @event, "3:maintenanceMode:off";
        push @event, "3:operationMode:summerMode";
        $waitingCmds = 0;

      } else {
        $waitingCmds = 0;
      }

      if (defined(ReadingsVal($name, "temperature", undef))) {
        $db[2] = int($temperature * 4);
      } else {
        # use actuator-internal temperature sensor
        $db[2] = 0xFF;
      }
      $wakeUpCycle = AttrVal($name, "wakeUpCycle", "auto");
      if (lc($wakeUpCycle) eq 'auto') {
        $wakeUpCycle = 0;
      } elsif ($wakeUpCycle <= 120) {
        $wakeUpCycle = 0x10;
      } elsif ($wakeUpCycle <= 300) {
        $wakeUpCycle = 0x20;
      } elsif ($wakeUpCycle <= 600) {
        $wakeUpCycle = 0x30;
      } elsif ($wakeUpCycle <= 1200) {
        $wakeUpCycle = 0x40;
      } elsif ($wakeUpCycle <= 1800) {
        $wakeUpCycle = 0x50;
      } elsif ($wakeUpCycle <= 3600) {
        $wakeUpCycle = 0x60;
      } else {
        $wakeUpCycle = 0x70;
      }
      my $measurementTypeSelect = 0;
      if (AttrVal($name, "measurementTypeSelect", "room") eq 'feed') {
        if (AttrVal($name, "pidCtrl", 'on') eq 'on' && defined(AttrVal($name, "temperatureRefDev", undef))) {
          $measurementTypeSelect = 2;
        } elsif (AttrVal($name, "pidCtrl", 'on') eq 'off') {
          $measurementTypeSelect = 2;
        }
      }
      push @event, "3:state:T: " . sprintf("%0.1f", $temperature) . " SPT: " . sprintf("%.1f", $setpointTemp) . " SP: $setpoint";
      # sent message to the actuator
      $data = sprintf "%02X%02X%02X08", $setpointSet, $db[2], $waitingCmds | $wakeUpCycle | $summerMode | $setpointSelect | $measurementTypeSelect | $functionSelect;
      EnOcean_SndRadio(undef, $hash, $packetType, "A5", $data, $subDef, "00", $hash->{DEF});

    } elsif ($st eq "hvac.10") {
      # Generic HVAC Interface (EEP A5-20-10)
      my %mode = (
        0 => "auto",
        1 => "heat",
        2 => "morning_warmup",
        3 => "cool",
        4 => "night_purge",
        5 => "precool",
        6 => "off",
        7 => "test",
        8 => "emergency_heat",
        9 => "fan_only",
        10 => "free_cool",
        11 => "ice",
        12 => "max_heat",
        13 => "eco",
        14 => "dehumidification",
        15 => "calibration",
        16 => "emergency_cool",
        17 => "emergency_stream",
        18 => "max_cool",
        19 => "hvc_load",
        20 => "no_load",
        31 => "auto_heat",
        32 => "auto_cool",
      );
      if (exists $mode{$db[3]}) {
        push @event, "3:mode:$mode{$db[3]}";
      } else {
        push @event, "3:mode:unknown";
      }
      my %vanePosition = (
        0 => "auto",
        1 => "horizontal",
        2 => "position_2",
        3 => "position_3",
        4 => "position_4",
        5 => "vertical",
        6 => "swing",
        11 => "vertical_swing",
        12 => "horizontal_swing",
        13 => "hor_vert_swing",
        14 => "stop_swing",
      );
      my $vanePosition = $db[2] >> 4;
      if (exists $vanePosition{$vanePosition}) {
        push @event, "3:vanePosition:$vanePosition{$vanePosition}";
      } else {
        push @event, "3:vanePosition:unknown";
      }
      my $fanSpeed = $db[2] & 0x0F;
      if ($fanSpeed == 0) {
        push @event, "3:fanSpeed:auto";
      } elsif ($fanSpeed > 0 && $fanSpeed < 15) {
        push @event, "3:fanSpeed:" . $fanSpeed;
      } else {
        push @event, "3:fanSpeed:unknown";
      }
      if ($db[1] == 255) {
        push @event, "3:ctrl:auto";
      } elsif ($db[1] >= 0 && $db[1] <= 100) {
        push @event, "3:ctrl:" . $db[1];
      } else {
        push @event, "3:ctrl:unknown";
      }
      my $occupancy = ($db[0] & 6) >> 1;
      if ($occupancy == 0) {
        push @event, "3:occupancy:occupied";
      } elsif ($occupancy == 1) {
        push @event, "3:occupancy:standby";
      } elsif ($occupancy == 2) {
        push @event, "3:occupancy:unoccupied";
      } else {
        push @event, "3:occupancy:off";
      }
      push @event, "3:powerSwitch:" . ($db[0] & 1 ? "on" : "off");
      push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");

    } elsif ($st eq "hvac.11") {
      # Generic HVAC Interface - Error Control (EEP A5-20-11)
      push @event, "3:errorCode:" . hex(substr($data, 0, 4));
      push @event, "3:otherDisable:" . ($db[1] & 8 ? "disabled" : "enabled");
      push @event, "3:windowDisable:" . ($db[1] & 4 ? "disabled" : "enabled");
      push @event, "3:keyCardDisable:" . ($db[1] & 2 ? "disabled" : "enabled");
      push @event, "3:externalDisable:" . ($db[1] & 1 ? "disabled" : "enabled");
      push @event, "3:remoteCtrl:" . ($db[0] & 4 ? "disabled" : "enabled");
      push @event, "3:window:" . ($db[0] & 2 ? "closed" : "opened");
      push @event, "3:alarm:" . ($db[0] & 1 ? "error" : "ok");
      push @event, "3:state:" . ($db[0] & 1 ? "error" : "ok");

    } elsif ($st =~ m/^tempSensor/) {
      # Temperature Sensor with with different ranges (EEP A5-02-01 ... A5-02-1B)
      # $db[1] is the temperature where 0x00 = max °C ... 0xFF = min °C
      my $temp;
      $temp = sprintf "%0.1f",   0 - $db[1] / 6.375 if ($st eq "tempSensor.01");
      $temp = sprintf "%0.1f",  10 - $db[1] / 6.375 if ($st eq "tempSensor.02");
      $temp = sprintf "%0.1f",  20 - $db[1] / 6.375 if ($st eq "tempSensor.03");
      $temp = sprintf "%0.1f",  30 - $db[1] / 6.375 if ($st eq "tempSensor.04");
      $temp = sprintf "%0.1f",  40 - $db[1] / 6.375 if ($st eq "tempSensor.05");
      $temp = sprintf "%0.1f",  50 - $db[1] / 6.375 if ($st eq "tempSensor.06");
      $temp = sprintf "%0.1f",  60 - $db[1] / 6.375 if ($st eq "tempSensor.07");
      $temp = sprintf "%0.1f",  70 - $db[1] / 6.375 if ($st eq "tempSensor.08");
      $temp = sprintf "%0.1f",  80 - $db[1] / 6.375 if ($st eq "tempSensor.09");
      $temp = sprintf "%0.1f",  90 - $db[1] / 6.375 if ($st eq "tempSensor.0A");
      $temp = sprintf "%0.1f", 100 - $db[1] / 6.375 if ($st eq "tempSensor.0B");
      $temp = sprintf "%0.1f",  20 - $db[1] / 3.1875 if ($st eq "tempSensor.10");
      $temp = sprintf "%0.1f",  30 - $db[1] / 3.1875 if ($st eq "tempSensor.11");
      $temp = sprintf "%0.1f",  40 - $db[1] / 3.1875 if ($st eq "tempSensor.12");
      $temp = sprintf "%0.1f",  50 - $db[1] / 3.1875 if ($st eq "tempSensor.13");
      $temp = sprintf "%0.1f",  60 - $db[1] / 3.1875 if ($st eq "tempSensor.14");
      $temp = sprintf "%0.1f",  70 - $db[1] / 3.1875 if ($st eq "tempSensor.15");
      $temp = sprintf "%0.1f",  80 - $db[1] / 3.1875 if ($st eq "tempSensor.16");
      $temp = sprintf "%0.1f",  90 - $db[1] / 3.1875 if ($st eq "tempSensor.17");
      $temp = sprintf "%0.1f", 100 - $db[1] / 3.1875 if ($st eq "tempSensor.18");
      $temp = sprintf "%0.1f", 110 - $db[1] / 3.1875 if ($st eq "tempSensor.19");
      $temp = sprintf "%0.1f", 120 - $db[1] / 3.1875 if ($st eq "tempSensor.1A");
      $temp = sprintf "%0.1f", 130 - $db[1] / 3.1875 if ($st eq "tempSensor.1B");
      $temp = sprintf "%0.2f", 41.2 - (($db[2] << 8) | $db[1]) / 20 if ($st eq "tempSensor.20");
      $temp = sprintf "%0.1f", 62.3 - (($db[2] << 8) | $db[1]) / 10 if ($st eq "tempSensor.30");
      push @event, "3:temperature:$temp";
      push @event, "3:state:$temp";

    } elsif ($st eq "COSensor.01") {
      # Gas Sensor, CO Sensor (EEP A5-09-01)
      # [untested]
      # $db[3] is the CO concentration where 0x00 = 0 ppm ... 0xFF = 255 ppm
      # $db[1] is the temperature where 0x00 = 0 °C ... 0xFF = 255 °C
      # $db[0] bit D1 temperature sensor available 0 = no, 1 = yes
      my $coChannel1 = $db[3];
      push @event, "3:CO:$coChannel1";
      if ($db[0] & 2) {
        my $temp = $db[1];
        push @event, "3:temperature:$temp";
      }
      push @event, "3:state:$coChannel1";

    } elsif ($st eq "COSensor.02") {
      # Gas Sensor, CO Sensor (EEP A5-09-02)
      # [untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the CO concentration where 0x00 = 0 ppm ... 0xFF = 1020 ppm
      # $db[1] is the temperature where 0x00 = 0 °C ... 0xFF = 51 °C
      # $db[0]_bit_1 temperature sensor available 0 = no, 1 = yes
      my $coChannel1 = $db[2] << 2;
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      push @event, "3:CO:$coChannel1";
      if ($db[0] & 2) {
        my $temp = sprintf "%0.1f", $db[1] * 0.2;
        push @event, "3:temperature:$temp";
      }
      push @event, "3:voltage:$voltage";
      push @event, "3:state:$coChannel1";

    } elsif ($st eq "tempHumiCO2Sensor.01") {
      # Gas Sensor, CO2 Sensor (EEP A5-09-04)
      # [Thermokon SR04 CO2 *, Eltako FCOTF63, untested]
      # $db[3] is the humidity where 0x00 = 0 %rH ... 0xC8 = 100 %rH
      # $db[2] is the CO2 concentration where 0x00 = 0 ppm ... 0xFF = 2500 ppm
      # $db[1] is the temperature where 0x00 = 0°C ... 0xFF = +51 °C
      # $db[0] bit D2 humidity sensor available 0 = no, 1 = yes
      # $db[0] bit D1 temperature sensor available 0 = no, 1 = yes
      my $humi = "-";
      my $temp = "-";
      my $airQuality;
      if ($db[0] & 4) {
        $humi = $db[3] >> 1;
      push @event, "3:humidity:$humi";
      }
      my $co2 = sprintf "%d", $db[2] * 10;
      push @event, "3:CO2:$co2";
      if ($db[0] & 2) {
        $temp = sprintf "%0.1f", $db[1] * 51 / 255 ;
        push @event, "3:temperature:$temp";
      }
      if ($co2 <= 400) {
        $airQuality = "high";
      } elsif ($co2 <= 600) {
        $airQuality = "mean";
      }  elsif ($co2 <= 1000) {
        $airQuality = "moderate";
      } else {
        $airQuality = "low";
      }
      push @event, "3:airQuality:$airQuality";
      push @event, "3:state:T: $temp H: $humi CO2: $co2 AQ: $airQuality";

    } elsif ($st eq "radonSensor.01") {
      # Gas Sensor, Radon Sensor (EEP A5-09-06)
      # [untested]
      # $db[3]_bit_7 ... $db[2]_bit_6 is the radon activity where 0 = 0 Bq/m3 ... 1023 = 1023 Bq/m3
      my $rn = $db[3] << 2 | $db[2] >> 6;
      push @event, "3:Rn:$rn";
      push @event, "3:state:$rn";

    } elsif ($st eq "vocSensor.01") {
      # Gas Sensor, VOC Sensor (EEP A5-09-05, A5-09-0C)
      # [untested]
      # $db[3]_bit_7 ... $db[2]_bit_0 is the VOC concentration where 0 = 0 ppb ... 65535 = 65535 ppb
      # $db[1] is the VOC identification
      # $db[0]_bit_1 ... $db[0]_bit_0 is the scale multiplier
      my $vocSCM = $db[0] & 3;
      if ($vocSCM == 3) {
        $vocSCM = 10;
      } elsif ($vocSCM == 2) {
        $vocSCM = 1;
      } elsif ($vocSCM == 1) {
        $vocSCM = 0.1;
      } else {
        $vocSCM = 0.01;
      }
      my $vocConc = sprintf "%f", ($db[3] << 8 | $db[2]) * $vocSCM;
      my %vocID = (
        0 => "VOCT",
        1 => "Formaldehyde",
        2 => "Benzene",
        3 => "Styrene",
        4 => "Toluene",
        5 => "Tetrachloroethylene",
        6 => "Xylene",
        7 => "n-Hexane",
        8 => "n-Octane",
        9 => "Cyclopentane",
        10 => "Methanol",
        11 => "Ethanol",
        12 => "1-Pentanol",
        13 => "Acetone",
        14 => "Ethylene Oxide",
        15 => "Acetaldehyde ue",
        16 => "Acetic Acid",
        17 => "Propionice Acid",
        18 => "Valeric Acid",
        19 => "Butyric Acid",
        20 => "Ammoniac",
        22 => "Hydrogen Sulfide",
        23 => "Dimethylsulfide",
        24 => "2-Butanol",
        25 => "2-Methylpropanol",
        26 => "Diethyl Ether",
        27 => "Naphthalene",
        28 => "4-Phenylcyclohexene",
        29 => "Limonene",
        30 => "Tricloroethylene",
        31 => "Isovaleric Acid",
        32 => "Indole",
        33 => "Cadaverine",
        34 => "Putrescine",
        35 => "Caproic Acid",
        255 => "Ozone",
      );
      if (exists $vocID{$db[1]}) {
        push @event, "3:vocName:$vocID{$db[1]}";
      } else {
        push @event, "3:vocName:unknown";
      }
      push @event, "3:concentration:$vocConc";
      push @event, "3:concentrationUnit:" . $db[0] & 4 ? 'ug/m3' : 'ppb';
      push @event, "3:state:$vocConc";

    } elsif ($st eq "particlesSensor.01") {
      # Gas Sensor, Particles Sensor (EEP A5-09-07)
      # [untested]
      # $db[3]_bit_7 ... $db[2]_bit_7 is the particle concentration < 10 µm
      # where 0 = 0 µg/m3 ... 511 = 511 µg/m3
      # $db[2]_bit_6 ... $db[1]_bit_6 is the particle concentration < 2.5 µm
      # where 0 = 0 µg/m3 ... 511 = 511 µg/m3
      # $db[1]_bit_5 ... $db[0]_bit_5 is the particle concentration < 1 µm
      # where 0 = 0 µg/m3 ... 511 = 511 µg/m3
      # $db[0]_bit_2 = 1 = Sensor PM10 active
      # $db[0]_bit_1 = 1 = Sensor PM2_5 active
      # $db[0]_bit_0 = 1 = Sensor PM1 active
      my $pm_10 = "inactive";
      my $pm_2_5 = "inactive";
      my $pm_1 = "inactive";
      if ($db[0] & 4) {$pm_10 = $db[3] << 1 | $db[2] >> 7;}
      if ($db[0] & 2) {$pm_2_5 = ($db[2] & 0x7F) << 1 | $db[1] >> 7;}
      if ($db[0] & 1) {$pm_1 = ($db[1] & 0x3F) << 3 | $db[0] >> 5;}
      push @event, "3:particles_10:$pm_10";
      push @event, "3:particles_2_5:$pm_2_5";
      push @event, "3:particles_1:$pm_1";
      push @event, "3:state:PM10: $pm_10 PM2_5: $pm_2_5 PM1: $pm_1";

    } elsif ($st eq "CO2Sensor.01") {
      # CO2 Sensor (EEP A5-09-08, A5-09-09)
      # [untested]
      # $db[1] is the CO2 concentration where 0x00 = 0 ppm ... 0xFF = 2000 ppm
      # $db[0]_bit_2 is power failure detection
      my $co2 = $db[1] / 255 * 2000;
      push @event, "3:powerFailureDetection:" . ($db[0] & 4 ? "detected" : "not_detected");
      push @event, "3:CO2:$co2";
      push @event, "3:state:$co2";

    } elsif ($st eq "HSensor.01") {
      # H Sensor (EEP A5-09-0A)
      # [untested]
      # $db[3]_$db[2] is the H concentration where 0x00 = 0 ppm ... 0xFFFF = 2000 ppm
      my $hydro = ($db[3] << 8 | $db[2]) / 65535 * 2000;
      push @event, "3:voltage:" . sprintf("%0.1f", (($db[0] & 0xF0) >> 4) / 15 * 3 + 2)  if ($db[0] & 1);
      push @event, "3:temperature:" . sprintf("%0.1f", $db[1] / 255 * 80 - 20) if ($db[0] & 2);
      push @event, "3:H:" . sprintf "%0.2f", $hydro;
      push @event, "3:state:" . sprintf "%0.2f", $hydro;

    } elsif ($st eq "radiationSensor.01") {
      # Radiation Sensor (EEP A5-09-0B)
      # [untested]
      # $db[2]_$db[1] is the radioactivity where 0x00 = 0 ... 0xFFFF = 65535
      my %scaleMulti = (
        0 => 0.001,
        1 => 0.01,
        2 => 0.1,
        3 => 1,
        4 => 10,
        5 => 100,
        6 => 1000,
        7 => 10000,
        8 => 100000
      );
      my $scaleMulti = ($db[0] & 0xF0) >> 4;
      my $scaleDecimals;
      if ($scaleMulti <= 2) {
        $scaleDecimals = "%0." . (3 - $scaleMulti) . "f";
      } else {
        $scaleDecimals = "%d"
      }
      $scaleMulti = $scaleMulti{$scaleMulti} if (exists $scaleMulti{$scaleMulti});
      my %unit = (
        0 => "uSv/h",
        1 => "cpm",
        2 => "Bq/L",
        3 => "Bq/kg"
      );
      my $unit = ($db[0] & 6) >> 1;
      $unit = $unit{$unit};
      my $radioactivity = $db[2] << 8 | $db[1];
      push @event, "3:radioactivity:" . sprintf "$scaleDecimals", $radioactivity * $scaleMulti;
      push @event, "3:radioactivityUnit:$unit";
      push @event, "3:voltage:" . sprintf("%0.1f", (($db[3] & 0xF0) >> 4) / 15 * 3 + 2)  if ($db[0] & 1);
      push @event, "3:state:" . sprintf "$scaleDecimals", $radioactivity * $scaleMulti;

    } elsif ($st eq "roomSensorControl.05") {
      # Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)
      # [Eltako FTR55D, FTR55H, Thermokon SR04 *, Thanos SR *, untested]
      # $db[3] is the fan speed or night reduction for Eltako
      # $db[2] is the setpoint where 0x00 = min ... 0xFF = max or
      # reference temperature for Eltako where 0x00 = 0°C ... 0xFF = 40°C
      # $db[1] is the temperature where 0x00 = +40°C ... 0xFF = 0°C
      # $db[0]_bit_0 is the occupy button, pushbutton or slide switch
      my $temp = sprintf "%0.1f", 40 - $db[1] / 6.375;
      if ($manufID eq "00D") {
        my $nightReduction = 0;
        $nightReduction = 1 if ($db[3] == 0x06);
        $nightReduction = 2 if ($db[3] == 0x0C);
        $nightReduction = 3 if ($db[3] == 0x13);
        $nightReduction = 4 if ($db[3] == 0x19);
        $nightReduction = 5 if ($db[3] == 0x1F);
        my $setpointTemp = sprintf "%0.1f", $db[2] / 6.375;
        push @event, "3:state:T: $temp SPT: $setpointTemp NR: $nightReduction";
        push @event, "3:nightReduction:$nightReduction";
        push @event, "3:setpointTemp:$setpointTemp";
      } else {
        my $fspeed = 3;
        $fspeed = 2      if ($db[3] >= 145);
        $fspeed = 1      if ($db[3] >= 165);
        $fspeed = 0      if ($db[3] >= 190);
        $fspeed = "auto" if ($db[3] >= 210);
        my $switch = $db[0] & 1 ? "on" : "off";
        push @event, "3:state:T: $temp SP: $db[2] F: $fspeed SW: $switch";
        push @event, "3:fanStage:$fspeed";
        push @event, "3:switch:$switch";
        push @event, "3:setpoint:$db[2]";
        my $setpointScaled = EnOcean_ReadingScaled($hash, $db[2], 0, 255);
        if (defined $setpointScaled) {
          push @event, "3:setpointScaled:" . $setpointScaled;
        }
      }
      push @event, "3:temperature:$temp";

    } elsif ($st eq "roomSensorControl.01") {
      # Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)
      # [Thermokon SR04 * rH, Thanus SR *, untested]
      # $db[3] is the setpoint where 0x00 = min ... 0xFF = max
      # $db[2] is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db[1] is the temperature where 0x00 = 0°C ... 0xFA = +40°C
      # $db[0] bit D0 is the occupy button, pushbutton or slide switch
      my $temp = sprintf "%0.1f", $db[1] * 40 / 250;
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $switch = $db[0] & 1;
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";
      if ($manufID eq "039") {
        my $brightness = sprintf "%d", $db[3] * 117;
        push @event, "3:brightness:$brightness";
        push @event, "3:state:T: $temp H: $humi B: $brightness";
      } else {
        push @event, "3:setpoint:$db[3]";
        push @event, "3:state:T: $temp H: $humi SP: $db[3] SW: $switch";
        push @event, "3:switch:$switch";
        my $setpointScaled = EnOcean_ReadingScaled($hash, $db[3], 0, 255);
        if (defined $setpointScaled) {
          push @event, "3:setpointScaled:" . $setpointScaled;
        }
      }

    } elsif ($st eq "roomSensorControl.02") {
      # Room Sensor and Control Unit (A5-10-15 ... A5-10-17)
      # [untested]
      # $db[2] bit D7 ... D2 is the setpoint where 0 = min ... 63 = max
      # $db[2] bit D1 ... $db[1] bit D0 is the temperature where 0 = -10°C ... 1023 = +41.2°C
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $temp = sprintf "%0.2f", -10 + ((($db[2] & 3) << 8) | $db[1]) / 19.98;
      my $setpoint = ($db[2] & 0xFC) >> 2;
      my $presence = $db[0] & 1 ? "absent" : "present";
      push @event, "3:state:T: $temp SP: $setpoint P: $presence";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[2], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "roomSensorControl.18") {
      # Room Sensor and Control Unit (A5-10-18)
      # [untested]
      # $db[3] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[2] is the setpoint where 250 = 0 °C ... 0 = 40 °C
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux = $db[3] << 2;
      if ($db[3] == 251) {$lux = "over range";}
      my $setpoint = sprintf "%0.1f", 40 - $db[2] * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.19") {
      # Room Sensor and Control Unit (A5-10-19)
      # [untested]
      # $db[3] is the humidity where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[2] is the setpoint where 250 = 0 °C ... 0 = 40 °C
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany Button where 0 = pressed, 1 = released
      # $db[0]_bit_0 is Occupany enable where 0 = enabled, 1 = disabled
      my $humi = $db[3] / 2.5;
      my $setpoint = sprintf "%0.1f", 40 - $db[2] * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 1) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 2 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:humidity:$humi";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.1A") {
      # Room Sensor and Control Unit (A5-10-1A)
      # [untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is the setpoint where 250 = 0 °C ... 0 = 40 °C
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      my $setpoint = sprintf "%0.1f", 40 - $db[2] * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:T: $temp F: $fanSpeed SP: $setpoint P: $presence U: $voltage";

    } elsif ($st eq "roomSensorControl.1B") {
      # Room Sensor and Control Unit (A5-10-1B)
      # [untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      my $lux = $db[2] << 2;
      if ($db[2] == 251) {$lux = "over range";}
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:temperature:$temp";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed P: $presence U: $voltage";

    } elsif ($st eq "roomSensorControl.1C") {
      # Room Sensor and Control Unit (A5-10-1C)
      # [untested]
      # $db[3] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[2] is the illuminance setpoint where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux = $db[3] << 2;
      if ($db[3] == 251) {$lux = "over range";}
      my $setpoint = $db[2] << 2;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.1D") {
      # Room Sensor and Control Unit (A5-10-1D)
      # [untested]
      # $db[3] is the humidity where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[2] is the humidity setpoint where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $humi = sprintf "%d", $db[3] / 2.5;
      my $setpoint = $db[2] / 2.5;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:humidity:$humi";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.1F") {
      # Room Sensor and Control Unit (A5-10-1F)
      # [untested]
      # $db[3] is the fan speed
      # $db[2] is the setpoint where 0 = 0 ... 255 = 255
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_6 ... $db[0]_bit_4 are flags
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $fanSpeed = "unknown";
      if ($db[0] & 0x10) {
        $fanSpeed = 3;
        $fanSpeed = 2      if ($db[3] >= 145);
        $fanSpeed = 1      if ($db[3] >= 165);
        $fanSpeed = 0      if ($db[3] >= 190);
        $fanSpeed = "auto" if ($db[3] >= 210);
      }
      my $setpoint = "unknown";
      $setpoint = $db[2] if ($db[0] & 0x20);
      my $temp = "unknown";
      $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250 if ($db[0] & 0x40);
      my $presence = "unknown";
      $presence = "absent" if (!($db[0] & 2));
      $presence = "present" if (!($db[0] & 1));
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp F: $fanSpeed SP: $setpoint P: $presence";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[2], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "roomSensorControl.20") {
      # Room Operation Panel (A5-10-20, A5-10-21)
      # [untested]
      # $db[3] is the setpoint where 0 = 0 ... 255 = 255
      # $db[2] is the humidity setpoint where min 0x00 = 0 %rH, max 0xFA = 100 %rH
      # $db[1] is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db[0]_bit_6 ... $db[0]_bit_5 is setpoint mode
      # $db[0]_bit_4 is battery state 0 = ok, 1 = low
      # $db[0]_bit_0 is user activity where 0 = no, 1 = yes
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $setpoint = $db[3];
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $setpointMode;
      if ((($db[0] & 0x60) >> 5) == 3) {
        $setpointMode = "reserved";
      } elsif ((($db[0] & 0x60) >> 5) == 2) {
        $setpointMode = "auto";
      } elsif ((($db[0] & 0x60) >> 1) == 1){
        $setpointMode = "frostProtection";
      } else {
        $setpointMode = "setpoint";
      }
      my $battery = ($db[0] & 0x10) ? "low" : "ok";
      push @event, "3:activity:" . ($db[0] & 1 ? "yes" : "no");
      push @event, "3:battery:$battery";
      push @event, "3:humidity:$humi";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:setpointMode:$setpointMode";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi SP: $setpoint B: $battery";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[3], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "roomSensorControl.22") {
      # Room Operation Panel (A5-10-22, A5-10-23)
      my $setpoint = $db[3];
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $temp = sprintf "%0.1f", $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0xE0) >> 5) == 4) {
        $fanSpeed = 3;
      } elsif ((($db[0] & 0xE0) >> 5) == 3) {
        $fanSpeed = 2;
      } elsif ((($db[0] & 0xE0) >> 5) == 2) {
        $fanSpeed = 1;
      } elsif ((($db[0] & 0xE0) >> 5) == 1){
        $fanSpeed = "off";
      } else {
        $fanSpeed = "auto";
      }
      my $occupancy = ($db[0] & 1) ? "occupied" : "unoccupied";
      push @event, "3:occupancy:$occupancy";
      push @event, "3:humidity:$humi";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:fanSpeed:$fanSpeed";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi SP: $setpoint F: $fanSpeed O: $occupancy";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[3], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "tempHumiSensor.02") {
      # Temperatur and Humidity Sensor(EEP A5-04-02)
      # [Eltako FAFT60, FIFT63AP]
      # $db[3] is the voltage where 0x59 = 2.5V ... 0x9B = 4V, only at Eltako
      # $db[2] is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db[1] is the temperature where 0x00 = -20°C ... 0xFA = +60°C
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $temp = sprintf "%0.1f", -20 + $db[1] * 80 / 250;
      my $battery = "unknown";
      if ($manufID eq "00D") {
        # Eltako sensor
        my $voltage = sprintf "%0.1f", $db[3] * 6.58 / 255;
        my $energyStorage = "unknown";
        if ($db[3] <= 0x58) {
          $energyStorage = "empty";
          $battery = "low";
        }
        elsif ($db[3] <= 0xDC) {
          $energyStorage = "charged";
          $battery = "ok";
        }
        else {
          $energyStorage = "full";
          $battery = "ok";
        }
        if (!exists($hash->{helper}{battery}) || $hash->{helper}{battery} ne $battery) {
          push @event, "3:battery:$battery";
          $hash->{helper}{battery} = $battery;
        }
        push @event, "3:energyStorage:$energyStorage";
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:state:T: $temp H: $humi B: $battery";
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";
      CommandDeleteReading(undef, "$name alarm");
      if (AttrVal($name, "signOfLife", 'off') eq 'on') {
        RemoveInternalTimer($hash->{helper}{timer}{alarm})  if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 3300), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      }

    } elsif ($st eq "tempHumiSensor.03") {
      # Temperatur and Humidity Sensor(EEP A5-04-03)
      # [untested]
      # $db[3] is the humidity where 0x00 = 0%rH ... 0xFF = 100%rH
      # $db[2] .. $db[1] is the temperature where 0x00 = -20°C ... 0x3FF = +60°C
      my $humi = sprintf "%d", $db[3] / 2.55;
      my $temp = sprintf "%0.1f", -20 + ($db[2] << 8 | $db[1]) * 80 / 1023;
      push @event, "3:state:T: $temp H: $humi";
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";
      push @event, "3:telegramType:" . ($db[0] & 1 ? "event" : "heartbeat");
      CommandDeleteReading(undef, "$name alarm");
      if (AttrVal($name, "signOfLife", 'off') eq 'on') {
        RemoveInternalTimer($hash->{helper}{timer}{alarm})  if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 1540), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      }
    } elsif ($st eq "baroSensor.01") {
      # Barometric Sensor(EEP A5-04-03)
      # [untested]
      # $db[3] .. $db[2] is the barometric  where 0x00 = 500 hPa ... 0x3FF = 1150 hPa
      my $baro = sprintf "%d", 500 + ($db[2] << 8 | $db[1]) * 650 / 1023;
      push @event, "3:state:$baro";
      push @event, "3:airPressure:$baro";
      push @event, "3:telegramType:" . ($db[0] & 1 ? "event" : "heartbeat");

    } elsif ($st eq "lightSensor.01") {
      # Light Sensor (EEP A5-06-01)
      # [Eltako FAH60, FAH63, FIH63, Thermokon SR65 LI, untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[3] is the low illuminance for Eltako devices where
      # min 0x00 = 0 lx, max 0xFF = 100 lx, if $db[2] = 0
      # $db[2] is the illuminance (ILL2) where min 0x00 = 300 lx, max 0xFF = 30000 lx
      # $db[1] is the illuminance (ILL1) where min 0x00 = 600 lx, max 0xFF = 60000 lx
      # $db[0]_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      my $voltage = "unknown";
      if ($manufID eq "00D") {
        if($db[2] == 0) {
          $lux = sprintf "%d", $db[3] * 100 / 255;
        } else {
          $lux = sprintf "%d", $db[2] * 116.48 + 300;
        }
      } else {
        $voltage = sprintf "%0.1f", $db[3] * 0.02;
        if($db[0] & 1) {
          $lux = sprintf "%d", $db[2] * 116.48 + 300;
        } else {
          $lux = sprintf "%d", $db[1] * 232.94 + 600;
        }
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.02") {
      # Light Sensor (EEP A5-06-02)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the illuminance (ILL2) where min 0x00 = 0 lx, max 0xFF = 510 lx
      # $db[1] is the illuminance (ILL1) where min 0x00 = 0 lx, max 0xFF = 1020 lx
      # $db[0]_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if($db[0] & 1) {
        $lux = $db[2] << 1;
      } else {
        $lux = $db[1] << 2;
      }
      push @event, "3:voltage:$voltage";
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.03") {
      # Light Sensor (EEP A5-06-03)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2]_bit_7 ... $db[1]_bit_6 is the illuminance where min 0x000 = 0 lx, max 0x3E8 = 1000 lx
      my $lux = $db[2] << 2 | $db[1] >> 6;
      if ($lux == 1001) {$lux = "over range";}
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      push @event, "3:voltage:$voltage";
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.04") {
      # Light Sensor (EEP A5-06-04)
      my $temperature;
      if ($db[0] & 2) {
        $temperature = sprintf "%0.1f", $db[3] * 80 / 255 - 20;
        push @event, "3:temperature:$temperature";
      } else {
        $temperature = '-';
        CommandDeleteReading(undef, "$name temperature");
      }
      my $brightness;
      if ($db[0] & 1) {
        $brightness = $db[2] << 8 | $db[1];
        push @event, "3:brightness:$brightness";
      } else {
        $brightness = '-';
        CommandDeleteReading(undef, "$name brightness");
      }
      my $energyStorage = sprintf "%d", ($db[0] >> 4) * 100 / 15;
      my $battery;
      if ($energyStorage <= 6) {
        $battery = 'low';
        push @event, "3:battery:low";
        push @event, "3:energyStorage:$energyStorage";
      } else {
        $battery = 'ok';
        push @event, "3:battery:ok";
        push @event, "3:energyStorage:$energyStorage";
      }
      push @event, "3:state:T: $temperature E: $brightness B: $battery";

    } elsif ($st eq "lightSensor.05") {
      # Light Sensor (EEP A5-06-05)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the illuminance (ILL2) where min 0x00 = 0 lx, max 0xFF = 5100 lx
      # $db[1] is the illuminance (ILL1) where min 0x00 = 0 lx, max 0xFF = 1020000 lx
      # $db[0]_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      if($db[0] & 1) {
        $lux = sprintf "%d", $db[2] * 20;
      } else {
        $lux = sprintf "%d", $db[1] * 40;
      }
      push @event, "3:voltage:" . sprintf "%0.1f", $db[3] * 0.02;
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "occupSensor.01") {
      # Occupancy Sensor (EEP A5-07-01)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is solar panel current where =0 uA ... 0xFF = 127 uA
      # $db[1] is PIR Status (motion) where 0 ... 127 = off, 128 ... 255 = on
      my $motion = "off";
      if ($db[1] >= 128) {$motion = "on";}
      if ($db[0] & 1) {push @event, "3:voltage:" . sprintf "%0.1f", $db[3] * 0.02;}
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      if ($manufID eq "00B") {
        push @event, "3:current:" . sprintf "%0.1f", $db[2] / 2;
        if ($db[0] & 2) {
          push @event, "3:sensorType:ceiling";
        } else {
          push @event, "3:sensorType:wall";
        }
      }
      if ($model eq "tracker") {
        RemoveInternalTimer($hash->{helper}{timer}{motion}) if(exists $hash->{helper}{timer}{motion});
        RemoveInternalTimer($hash->{helper}{timer}{state}) if(exists $hash->{helper}{timer}{state});
        @{$hash->{helper}{timer}{motion}} = ($hash, 'motion', 'off', 1, 5);
        @{$hash->{helper}{timer}{state}} = ($hash, 'state', 'off', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, 'trackerWakeUpCycle', 30) * 1.1, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{motion}, 0);
        InternalTimer(gettimeofday() + AttrVal($name, 'trackerWakeUpCycle', 30) * 1.1, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{state}, 0);
      }
      if (!exists($hash->{helper}{lastVoltage}) || $hash->{helper}{lastVoltage} != $db[3]) {
        push @event, "3:battery:" . ($db[3] * 0.02 > 2.8 ? "ok" : "low");
        $hash->{helper}{lastVoltage} = $db[3];
      }
      push @event, "3:button:" . ($db[0] & 4 ? "released" : "pressed") if ($manufID eq "7FF");
      push @event, "3:motion:$motion";
      push @event, "3:state:$motion";

    } elsif ($st eq "occupSensor.02") {
      # Occupancy Sensor (EEP A5-07-02)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[0]_bit_7 is PIR Status (motion) where 0 = off, 1 = on
      my $motion = $db[0] >> 7 ? "on" : "off";
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      push @event, "3:battery:" . ($db[3] * 0.02 > 2.9 ? "ok" : "low");
      push @event, "3:motion:$motion";
      push @event, "3:voltage:" . sprintf "%0.1f", $db[3] * 0.02;
      push @event, "3:state:$motion";

    } elsif ($st eq "occupSensor.03") {
      # Occupancy Sensor (EEP A5-07-03)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2]_bit_7 ... $db[1]_bit_6 is the illuminance where min 0x000 = 0 lx, max 0x3E8 = 1000 lx
      # $db[0]_bit_7 is PIR Status (motion) where 0 = off, 1 = on
      my $motion = $db[0] >> 7 ? "on" : "off";
      my $lux = $db[2] << 2 | $db[1] >> 6;
      if ($lux == 1001) {$lux = "over range";}
      my $voltage = sprintf "%0.2f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      push @event, "3:battery:" . ($db[3] * 0.02 > 2.9 ? "ok" : "low");
      push @event, "3:brightness:$lux";
      push @event, "3:motion:$motion";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:M: $motion E: $lux U: $voltage";

    } elsif ($st =~ m/^lightTempOccupSensor/) {
      # Light, Temperatur and Occupancy Sensor (EEP A5-08-01 ... A5-08-03)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the illuminance where min 0x00 = 0 lx, max 0xFF = 510 lx, 1020 lx, (2048 lx)
      # $db[1] is the temperature whrere 0x00 = 0 °C ... 0xFF = 51 °C or -30 °C ... 50°C
      # $db[0]_bit_1 is PIR Status (motion) where 0 = on, 1 = off
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux;
      my $temp;
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      my $motion = $db[0] & 2 ? "off" : "on";
      my $presence = $db[0] & 1 ? "absent" : "present";

      if ($st eq "lightTempOccupSensor.01") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-01)
        # [Eltako FABH63, FBH55, FBH63, FIBH63, TF-BHSB]
        if ($manufID eq "00D") {
          if ( $model eq 'Eltako_TF') {
            $lux = $db[2] << 1;
            push @event, "3:state:M: $motion E: $lux U: $voltage";
            push @event, "3:voltage:$voltage";
          } else {
            $lux = sprintf "%d", $db[2] * 2048 / 255;
            push @event, "3:state:M: $motion E: $lux";
          }
        } else {
          $lux = $db[2] << 1;
          $temp = sprintf "%0.1f", $db[1] * 0.2;
          push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
          push @event, "3:presence:$presence";
          push @event, "3:temperature:$temp";
          push @event, "3:voltage:$voltage";
        }
      } elsif ($st eq "lightTempOccupSensor.02") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-02)
        $lux = $db[2] << 2;
        $temp = sprintf "%0.1f", $db[1] * 0.2;
        push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
        push @event, "3:presence:$presence";
        push @event, "3:temperature:$temp";
        push @event, "3:voltage:$voltage";
      } elsif ($st eq "lightTempOccupSensor.03") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-03)
        $lux = $db[2] * 6;
        $temp = sprintf "%0.1f", -30 + $db[1] * 80 / 255;
        push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
        push @event, "3:presence:$presence";
        push @event, "3:temperature:$temp";
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:motion:$motion";

    } elsif ($st eq "lightCtrlState.01") {
      # Lighting Controller State (EEP A5-11-01)
      # $db[3] is the illumination where 0x00 = 0 lx ... 0xFF = 510 lx
      # $db[2] is the illumination Setpoint where 0x00 = 0 ... 0xFF = 255
      # $db[1] is the Dimming Output Level where 0x00 = 0 ... 0xFF = 255
      # $db[0]_bit_7 is the Repeater state where 0 = disabled, 1 = enabled
      # $db[0]_bit_6 is the Power Relay Timer state where 0 = disabled, 1 = enabled
      # $db[0]_bit_5 is the Daylight Harvesting state where 0 = disabled, 1 = enabled
      # $db[0]_bit_4 is the Dimming mode where 0 = switching, 1 = dimming
      # $db[0]_bit_2 is the Magnet Contact state where 0 = open, 1 = closed
      # $db[0]_bit_1 is the Occupancy (prensence) state where 0 = absent, 1 = present
      # $db[0]_bit_0 is the Power Relay state where 0 = off, 1 = on
      push @event, "3:brightness:" . ($db[3] << 1);
      push @event, "3:illum:$db[2]";
      push @event, "3:dim:$db[1]";
      push @event, "3:powerRelayTimer:" . ($db[0] & 0x80 ? "enabled" : "disabled");
      push @event, "3:repeater:" . ($db[0] & 0x40 ? "enabled" : "disabled");
      push @event, "3:daylightHarvesting:" . ($db[0] & 0x20 ? "enabled" : "disabled");
      push @event, "3:mode:" . ($db[0] & 0x10 ? "dimming" : "switching");
      push @event, "3:contact:" . ($db[0] & 4 ? "closed" : "open");
      push @event, "3:presence:" . ($db[0] & 2 ? "present" : "absent");
      push @event, "3:powerSwitch:" . ($db[0] & 1 ? "on" : "off");
      push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");

    } elsif ($st eq "tempCtrlState.01") {
      # Temperature Controller Output (EEP A5-11-02)
      # $db[3] is the Control Variable where 0x00 = 0 % ... 0xFF = 100 %
      # $db[2] is the Fan Stage
      # $db[1] is the Actual Setpoint where 0x00 = 0 °C ... 0xFF = 51.2 °C
      # $db[0]_bit_7 is the Alarm state where 0 = no, 1 = yes
      # $db[0]_bit_6 ... $db[0]_bit_5 is the Controller Mode
      # $db[0]_bit_4 is the Controller State where 0 = auto, 1 = override
      # $db[0]_bit_2 is the Energy hold-off where 0 = normal, 1 = hold-off
      # $db[0]_bit_1 ... $db[0]_bit_0is the Occupancy (prensence) state where 0 = present
      # 1 = absent, 3 = standby, 4 = frost
      push @event, "3:controlVar:" . sprintf "%d", $db[3] * 100 / 255;
      if (($db[2] & 3) == 0) {
        push @event, "3:fan:0";
      } elsif (($db[2] & 3) == 1){
        push @event, "3:fan:1";
      } elsif (($db[2] & 3) == 2){
        push @event, "3:fan:2";
      } elsif (($db[2] & 3) == 3){
        push @event, "3:fan:3";
      } elsif ($db[2] == 255){
        push @event, "3:fan:unknown";
      }
      push @event, "3:fanMode:" . ($db[2] & 0x10 ? "auto" : "manual");
      my $setpointTemp = sprintf "%0.1f", $db[1] * 0.2;
      push @event, "3:setpointTemp:$setpointTemp";
      push @event, "3:alarm:" . ($db[0] & 1 ? "on" : "off");
      my $controllerMode = ($db[0] & 0x60) >> 5;
      if ($controllerMode == 0) {
        push @event, "3:controllerMode:auto";
      } elsif ($controllerMode == 1) {
        push @event, "3:controllerMode:heating";
      } elsif ($controllerMode == 2) {
        push @event, "3:controllerMode:cooling";
      } elsif ($controllerMode == 3) {
        push @event, "3:controllerMode:off";
      }
      push @event, "3:controllerState:" . ($db[0] & 0x10 ? "override" : "auto");
      push @event, "3:energyHoldOff:" . ($db[0] & 4 ? "holdoff" : "normal");
      if (($db[0] & 3) == 0) {
        push @event, "3:presence:present";
      } elsif (($db[0] & 3) == 1){
        push @event, "3:presence:absent";
      } elsif (($db[0] & 3) == 2){
        push @event, "3:presence:standby";
      } elsif (($db[0] & 3) == 3){
        push @event, "3:presence:frost";
      }
      push @event, "3:state:$setpointTemp";

    } elsif ($st eq "shutterCtrlState.01") {
      # Blind Status (EEP A5-11-03)
      # $db[3] is the Shutter Position where 0 = 0 % ... 100 = 100 %
      # $db[2]_bit_7 is the Angle sign where 0 = positive, 1 = negative
      # $db[2]_bit_6 ... $db[2]_bit_0 where 0 = 0° ... 90 = 180°
      # $db[1]_bit_7 is the Position Value Flag where 0 = no available, 1 = available
      # $db[1]_bit_6 is the Angle Value Flag where 0 = no available, 1 = available
      # $db[1]_bit_5 ... $db[1]_bit_4 is the Error State (alarm)
      # $db[1]_bit_3 ... $db[1]_bit_2 is the End-position State
      # $db[1]_bit_1 ... $db[1]_bit_0 is the Shutter State
      # $db[0]_bit_7 is the Service Mode where 0 = no, 1 = yes
      # $db[0]_bit_6 is the Position Mode where 0 = normal, 1 = inverse
      if ($db[1] & 0x80) {
        push @event, "3:position:" . $db[3];
      }
      my $anglePos = ($db[2] & 0x7F) << 1;
      if ($db[2] & 0x80) {$anglePos *= -1;}
      if ($db[1] & 0x40) {
        push @event, "3:anglePos:" . $anglePos;
      }
      my $alarm = ($db[1] & 0x30) >> 4;
      if ($alarm == 0) {
        push @event, "3:alarm:off";
      } elsif ($alarm == 1){
        push @event, "3:alarm:no_endpoints_defined";
      } elsif ($alarm == 2){
        push @event, "3:alarm:on";
      } elsif ($alarm == 3){
        push @event, "3:alarm:not_used";
      }
      my $endPosition = ($db[1] & 0x0C) >> 2;
      if ($endPosition == 0) {
        push @event, "3:endPosition:not_available";
        push @event, "3:state:not_available";
      } elsif ($endPosition == 1) {
        push @event, "3:endPosition:not_reached";
        push @event, "3:state:not_reached";
      } elsif ($endPosition == 2) {
        push @event, "3:endPosition:open";
        push @event, "3:state:open";
      } elsif ($endPosition == 3){
        push @event, "3:endPosition:closed";
        push @event, "3:state:closed";
      }
      my $shutterState = $db[1] & 3;
      if (($db[1] & 3) == 0) {
        push @event, "3:shutterState:not_available";
      } elsif (($db[1] & 3) == 1) {
        push @event, "3:shutterState:stopped";
      } elsif (($db[1] & 3) == 2){
        push @event, "3:shutterState:opens";
      } elsif (($db[1] & 3) == 3){
        push @event, "3:shutterState:closes";
      }
      push @event, "3:serviceOn:" . ($db[0] & 0x80 ? "yes" : "no");
      push @event, "3:positionMode:" . ($db[0] & 0x40 ? "inverse" : "normal");

    } elsif ($st eq "lightCtrlState.02") {
      # Extended Lighting Status (EEP A5-11-04)
      # $db[3] the contents of the variable depends on the parameter mode
      # $db[2] the contents of the variable depends on the parameter mode
      # $db[1] the contents of the variable depends on the parameter mode
      # $db[0]_bit_7 is the Service Mode where 0 = no, 1 = yes
      # $db[0]_bit_6 is the operating hours flag where 0 = not_available, 1 = available
      # $db[0]_bit_5 ... $db[0]_bit_4 is the Error State (alarm)
      # $db[0]_bit_2 ... $db[0]_bit_1 is the parameter mode
      # $db[0]_bit_0 is the lighting status where 0 = off, 1 = on
      push @event, "3:serviceOn:" . ($db[1] & 0x80 ? "yes" : "no");
      my $alarm = ($db[0] & 0x30) >> 4;
      if ($alarm == 0) {
        push @event, "3:alarm:off";
      } elsif ($alarm == 1){
        push @event, "3:alarm:lamp_failure";
      } elsif ($alarm == 2){
        push @event, "3:alarm:internal_failure";
      } elsif ($alarm == 3){
        push @event, "3:alarm:external_periphery_failure";
      }
      my $mode = ($db[0] & 6) >> 1;
      if ($mode == 0) {
        # dimmer value and lamp operating hours
        push @event, "3:dim:$db[3]";
        if ($db[0] & 40) {
          push @event, "3:lampOpHours:" . ($db[2] << 8 | $db[1]);
        } else {
          push @event, "3:lampOpHours:unknown";
        }
      } elsif ($mode == 1){
        # RGB value
        push @event, "3:red:$db[3]";
        push @event, "3:green:$db[2]";
        push @event, "3:blue:$db[1]";
        push @event, "3:rgb:" . substr($data, 0, 6);
      } elsif ($mode == 2){
        # energy metering value
        my @measureUnit = ("mW", "W", "kW", "MW", "Wh", "kWh", "MWh", "GWh",
                           "mA", "A", "mV", "V");
        if ($db[1] < 4) {
          push @event, "3:power:" . ($db[3] << 8 | $db[2]);
          push @event, "3:powerUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] < 8) {
          push @event, "3:energy:" . ($db[3] << 8 | $db[2]);
          push @event, "3:energyUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 8) {
          push @event, "3:current:" . ($db[3] << 8 | $db[2]);
          push @event, "3:currentUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 9) {
          push @event, "3:current:" . sprintf "%0.1f", ($db[3] << 8 | $db[2]) / 10;
          push @event, "3:currentUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 10) {
          push @event, "3:voltage:" . ($db[3] << 8 | $db[2]);
          push @event, "3:voltageUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 11) {
          push @event, "3:voltage:" . sprintf "%0.1f", ($db[3] << 8 | $db[2]) / 10;
          push @event, "3:voltageUnit:" . $measureUnit[$db[1]];
        } else {
          push @event, "3:measuredValue:" . ($db[3] << 8 | $db[2]);
          push @event, "3:measureUnit:unknown";
        }
      } elsif ($mode == 3){
        # not used
      }
      push @event, "3:powerSwitch:" . ($db[0] & 1 ? "on" : "off");
      push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");

    } elsif ($st eq "switch.05") {
      # Dual Channel Switch Actuator
      # (A5-11-05)
      if ($db[0] & 1) {
        push @event, "3:workingMode:" . (($db[0] & 0x70) >> 4);
        push @event, "3:channel1:" . ($db[0] & 2 ? "on" : "off");
        push @event, "3:channel2:" . ($db[0] & 4 ? "on" : "off");
        push @event, "3:state:1: " .  ($db[0] & 2 ? "on" : "off") . " 2: " . ($db[0] & 4 ? "on" : "off");
      }

    } elsif ($st =~ m/^autoMeterReading\.0[0-3]$/ || $st eq "actuator.01" && $manufID eq "033") {
      # Automated meter reading (AMR) (EEP A5-12-00 ... A5-12-03)
      # $db[3] (MSB) + $db[2] + $db[1] (LSB) is the Meter reading
      # $db[0]_bit_7 ... $db[0]_bit_4 is the Measurement channel
      # $db[0]_bit_2 is the Data type where 0 = cumulative value, 1 = current value
      # $db[0]_bit_1 ... $db[0]_bit_0 is the Divisor where 0 = x/1, 1 = x/10,
      # 2 = x/100, 3 = x/1000
      my $dataType = ($db[0] & 4) >> 2;
      my $divisor = $db[0] & 3;
      my $meterReading;
      if ($divisor == 3) {
        $meterReading = sprintf "%.3f", ($db[3] << 16 | $db[2] << 8 | $db[1]) / 1000;
      } elsif ($divisor == 2) {
        $meterReading = sprintf "%.2f", ($db[3] << 16 | $db[2] << 8 | $db[1]) / 100;
      } elsif ($divisor == 1) {
        $meterReading = sprintf "%.1f", ($db[3] << 16 | $db[2] << 8 | $db[1]) / 10;
      } else {
        $meterReading = $db[3] << 16 | $db[2] << 8 | $db[1];
      }
      my $channel = $db[0] >> 4;

      if ($st eq "autoMeterReading.00") {
        # Automated meter reading (AMR), Counter (EEP A5-12-01)
        # [Thermokon SR-MI-HS, untested]
        if ($dataType == 1) {
          # current value
          push @event, "3:currentValue" . sprintf('%02d', $channel) . ":$meterReading";
          push @event, "3:state:$meterReading";
        } else {
          # cumulative counter
          push @event, "3:counter" . sprintf('%02d', $channel) . ":$meterReading";
        }
      } elsif ($st eq "autoMeterReading.01" || $st eq "actuator.01" && $manufID eq "033") {
        # Automated meter reading (AMR), Electricity (EEP A5-12-01)
        # [Eltako FSS12, FWZ12, DSZ14DRS, DSZ14WDRS, DWZ61]
        # $db[0]_bit_7 ... $db[0]_bit_4 is the Tariff info
        # $db[0]_bit_2 is the Data type where 0 = cumulative value kWh,
        # 1 = current value W
        if ($db[0] == 0x8F && $manufID eq "00D") {
          # Eltako, read meter serial number
          my $serialNumber;
          if ($db[1] == 0) {
            # first 2 digits of the serial number
            $serialNumber = substr(ReadingsVal($name, "serialNumber", "S-------"), 4, 4);
            $serialNumber = sprintf "S-%01x%01x%4s", $db[3] >> 4, $db[3] & 0x0F, $serialNumber;
          } else {
            # last 4 digits of the serial number
            $serialNumber = substr(ReadingsVal($name, "serialNumber", "S---"), 0, 4);
            $serialNumber = sprintf "%4s%01x%01x%01x%01x", $serialNumber,
                            $db[2] >> 4, $db[2] & 0x0F, $db[3] >> 4, $db[3] & 0x0F;
          }
          push @event, "3:serialNumber:$serialNumber";
        } elsif ($dataType == 1) {
          # momentary power
          push @event, "3:power:$meterReading";
          if (!($st eq "actuator.01" && $manufID eq "033")) {
	    push @event, "3:state:$meterReading";
          }
        } else {
          # power consumption
          push @event, "3:energy$channel:$meterReading";
          push @event, "3:currentTariff:$channel";
        }
      } elsif ($st eq "autoMeterReading.02" || $st eq "autoMeterReading.03") {
        # Automated meter reading (AMR), Gas, Water (EEP A5-12-02, A5-12-03)
        if ($dataType == 1) {
          # current value
          push @event, "3:flowrate:$meterReading";
          push @event, "3:state:$meterReading";
        } else {
          # cumulative counter
          push @event, "3:consumption$channel:$meterReading";
          push @event, "3:currentTariff:$channel";
        }
      }

    } elsif ($st =~ m/^autoMeterReading\.0[45]$/) {
      # $db[1] is the temperature 0 .. 0xFF >> -40 ... 40
      # $db[0]_bit_1 ... $db[0]_bit_0 is the battery level
      my $temperature = sprintf "%0.1f", ($db[1] / 255 * 80) - 40;
      my $battery = $db[0] & 3;
      if ($battery == 3) {
        $battery = "empty";
      } elsif ($battery == 2) {
        $battery = "low";
      } elsif ($battery == 1) {
        $battery = "ok";
      } else {
        $battery = "full";
      }
      push @event, "3:battery:$battery";
      push @event, "3:temperature:$temperature";

      if ($st eq "autoMeterReading.04") {
        # Automated meter reading (AMR), Temperature, Load (EEP A5-12-04)
        # $db[3] ... $db[2]_bit_2 is the Current Value in gram
        my $weight = $db[3] << 6 | $db[2];
        push @event, "3:weight:$weight";
        push @event, "3:state:T: $temperature W: $weight B: $battery";

      } elsif ($st eq "autoMeterReading.05") {
        # Automated meter reading (AMR), Temperature, Container (EEP A5-12-05)
        # $db[3] ... $db[2]_bit_6 is position sensor
        my @sp;
        $sp[0] = ($db[3] & 128) >> 7;
        $sp[1] = ($db[3] & 64) >> 6;
        $sp[2] = ($db[3] & 32) >> 5;
        $sp[3] = ($db[3] & 16) >> 4;
        $sp[4] = ($db[3] & 8) >> 3;
        $sp[5] = ($db[3] & 4) >> 2;
        $sp[6] = ($db[3] & 2) >> 1;
        $sp[7] = $db[3] & 1;
        $sp[8] = ($db[2] & 128) >> 7;
        $sp[9] = ($db[2] & 64) >> 6;
        my $amount = 0;
        for (my $spCntr = 0; $spCntr <= 9; $spCntr ++) {
          push @event, "3:location" . $spCntr . ":" . ($sp[$spCntr] ? "possessed" : "not_possessed");
          $amount += $sp[$spCntr];
        }
        push @event, "3:amount:$amount";
        push @event, "3:state:T: $temperature L: " . $sp[0] . $sp[1] . " " . $sp[2] . $sp[3] .
                        " " . $sp[4] . $sp[5] . " " . $sp[6] . $sp[7] . " " . $sp[8] . $sp[9] . " B: $battery";
      }

    } elsif ($st eq "autoMeterReading.10") {
      # Automated meter reading (AMR), current meter 16 channels (EEP A5-12-10)
      my $meterReading = hex(substr($data, 0, 6)) / 10 ** ($db[0] & 3);
      my $channel = sprintf '%02d', $db[0] & 0xF0 >> 4;
      my $scaleDecimals = "%0." . ($db[0] & 3) . "f";
      push @event, "3:currentTariff:$channel";
      if ($db[0] & 4) {
        # current
        push @event, "3:current$channel:" . sprintf "$scaleDecimals", $meterReading;
        push @event, "3:state:" . sprintf "$scaleDecimals", $meterReading;
      } else {
        # electric charge
        push @event, "3:electricChange$channel:" . sprintf "$scaleDecimals", $meterReading;
      }

    } elsif ($st eq "environmentApp") {
      # Environmental Applications (EEP A5-13-01 ... EEP A5-13-06, EEP A5-13-10)
      # [Eltako FWS61]
      # $db[0]_bit_7 ... $db[0]_bit_4 is the Identifier
      my $identifier = $db[0] >> 4;
      if ($identifier == 1) {
        # Weather Station (EEP A5-13-01)
        # $db[3] is the dawn sensor where 0x00 = 0 lx ... 0xFF = 999 lx
        # $db[2] is the temperature where 0x00 = -40 °C ... 0xFF = 80 °C
        # $db[1] is the wind speed where 0x00 = 0 m/s ... 0xFF = 70 m/s
        # $db[0]_bit_2 is day / night where 0 = day, 1 = night
        # $db[0]_bit_1 is rain indication where 0 = no (no rain), 1 = yes (rain)
        my $dawn = sprintf "%d", $db[3] * 999 / 255;
        $hash->{helper}{brightness} = $dawn;
        if (exists($hash->{helper}{sunMax}) && $hash->{helper}{sunMax} >= 1000) {
          $dawn = $hash->{helper}{sunMax}
        } else {
          push @event, "3:brightness:$dawn";
        }
        my $temp = sprintf "%0.1f", -40 + $db[2] * 120 / 255;
        my $windSpeed = sprintf "%0.1f", $db[1] * 70 / 255;
        my $dayNight;
        if (AttrVal($name, "brightnessDayNightCtrl", 'sensor') eq 'sensor') {
          $dayNight = $db[0] & 4 ? "night" : "day";
        } else {
          $dayNight = EnOcean_swayCtrl($hash, "dayNight", $dawn, "brightnessDayNight", "brightnessDayNightDelay", 10, 20, 600, 600, 'night', 'day');
        }
        my $isRaining = $db[0] & 2 ? "yes" : "no";
        my @windStrength = (0.2, 1.5, 3.3, 5.4, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6);
        my $windStrength = 0;
        while($windSpeed > $windStrength[$windStrength] && $windStrength <= @windStrength + 1) {
          $windStrength ++;
        }
        push @event, "3:dayNight:$dayNight";
        push @event, "3:isRaining:$isRaining";
        push @event, "3:temperature:$temp";
        push @event, "3:windSpeed:$windSpeed";
        push @event, "3:windStrength:$windStrength";
        push @event, "3:isStormy:" . EnOcean_swayCtrl($hash, "isStormy", $windSpeed, "windSpeedStormy", "windSpeedStormyDelay", 13.9, 17.2, 60, 3, 'no', 'yes');
        push @event, "3:isWindy:" . EnOcean_swayCtrl($hash, "isWindy", $windSpeed, "windSpeedWindy", "windSpeedWindyDelay", 1.6, 3.4, 60, 3, 'no', 'yes');
        push @event, "3:state:T: $temp B: $dawn W: $windSpeed IR: $isRaining";
      } elsif ($identifier == 2) {
        # Sun Intensity (EEP A5-13-02)
        # $db[3] is the sun exposure west where 0x00 = 0 klx ... 0xFF = 150 klx
        # $db[2] is the sun exposure south where 0x00 = 0 klx ... 0xFF = 150 klx
        # $db[1] is the sun exposure east where 0x00 = 0 klx ... 0xFF = 150 klx
        # $db[0]_bit_2 is hemisphere where 0 = north, 1 = south
        my $brightness = exists($hash->{helper}{brightness}) ? $hash->{helper}{brightness} : 0;
        my $sunWest = sprintf "%d", $db[3] * 150000 / 255;
        my $sunSouth = sprintf "%d", $db[2] * 150000 / 255;
        my $sunEast = sprintf "%d", $db[1] * 150000 / 255;
        my @sunlight = ($sunSouth, $sunWest, $sunEast);
        my ($sunMin, $sunMax) = (sort {$a <=> $b} @sunlight)[0,-1];
        $hash->{helper}{sunMax} = $sunMax;
        $sunSouth = $sunSouth < 1000 ? $brightness : $sunSouth;
        $sunWest = $sunWest < 1000 ? $brightness : $sunWest;
        $sunEast = $sunEast < 1000 ? $brightness : $sunEast;
        if ($sunMax > 999) {
          push @event, "3:brightness:$sunMax";
          $brightness = $sunMax;
        }
        push @event, "3:hemisphere:" . ($db[0] & 4 ? "south" : "north");
        push @event, "3:sunWest:$sunWest";
        push @event, "3:sunSouth:$sunSouth";
        push @event, "3:sunEast:$sunEast";
        push @event, "3:isSunny:" . EnOcean_swayCtrl($hash, "isSunny", $brightness, "brightnessSunny", "brightnessSunnyDelay", 20000, 40000, 120, 30, 'no', 'yes');
        push @event, "3:isSunnySouth:" . EnOcean_swayCtrl($hash, "isSunnySouth", $sunSouth, "brightnessSunnySouth", "brightnessSunnySouthDelay", 20000, 40000, 120, 30, 'no', 'yes');
        push @event, "3:isSunnyWest:" . EnOcean_swayCtrl($hash, "isSunnyWest", $sunWest, "brightnessSunnyWest", "brightnessSunnyWestDelay", 20000, 40000, 120, 30, 'no', 'yes');
        push @event, "3:isSunnyEast:" . EnOcean_swayCtrl($hash, "isSunnyEast", $sunEast, "brightnessSunnyEast", "brightnessSunnyEastDelay", 20000, 40000, 120, 30, 'no', 'yes');
      } elsif ($identifier == 3) {
        # Date exchange (EEP A5-13-03)
        push @event, "3:date:" . sprintf("%04d-%02d-%02d", $db[1] + 2000, $db[2], $db[3]);
      } elsif ($identifier == 4) {
        # Time und Day exchange (EEP A5-13-04)
        my @day = ('', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday');
        my $day = $db[3] >> 5;
        push @event, "3:weekday:" . $day[$day];
        if ($db[0] & 4) {
          # 12 h time format
          push @event, "3:time:" . sprintf("%02d:%02d:%02d", ($db[3] & 0x1F), $db[2], $db[1]) . ' ' . ($db[0] & 2 ? 'PM' : 'AM');
        } else {
          push @event, "3:time:" . sprintf("%02d:%02d:%02d", ($db[3] & 0x1F), $db[2], $db[1]);
        }
        push @event, "3:timeSource:" . ($db[0] & 1 ? 'GPS' : 'RTC');
      } elsif ($identifier == 5) {
        # Direction exchange (EEP A5-13-05)
        my $elevation = $db[3] - 90;
        push @event, "3:elevation:$elevation";
        push @event, "3:azimuth:" . hex(substr($data, 2, 4));
        my $twilight = ($elevation + 12) / 18 * 100;
        $twilight = 0 if ($twilight < 0);
        $twilight = 100 if ($twilight > 100);
        push @event, "3:twilight:" . int($twilight);
      } elsif ($identifier == 6) {
        # Geographic Position exchange (EEP A5-13-06)
        push @event, "3:latitude:" . sprintf("%0.3f", hex(substr($data, 0, 1) . substr($data, 2, 2)) / 22.75 - 90);
        push @event, "3:longitude:" . sprintf("%0.3f", hex(substr($data, 1, 1) . substr($data, 4, 2)) / 13.375 - 180);

      } elsif ($identifier == 7) {
        # Sun Position and Radiation (EEP A5-13-10)
        # $db[3]_bit_7 ... $db[3]_bit_1 is Sun Elevation where 0 = 0 ° ... 90 = 90 °
        # $db[3]_bit_0 is day / night where 0 = day, 1 = night
        # $db[2] is Sun Azimuth where 0 = -90 ° ... 180 = 90 °
        # $db[1] and $db[0]_bit_2 ... $db[0]_bit_0 is Solar Radiation where
        # 0 = 0 W/m2 ... 2000 = 2000 W/m2
        my $sunElev = $db[3] >> 1;
        my $sunAzim = $db[2] - 90;
        my $solarRad = $db[1] << 3 | $db[0] & 7;
        push @event, "3:dayNight:" . ($db[3] & 1 ? "night" : "day");
        push @event, "3:solarRadiation:$solarRad";
        push @event, "3:sunAzimuth:$sunAzim";
        push @event, "3:sunElevation:$sunElev";
        push @event, "3:state:SRA: $solarRad SNA: $sunAzim SNE: $sunElev";
      } else {
      }

    } elsif ($st eq "windSensor.01") {
      # Wind Sensor (EEP A5-13-07)
      my @windDirection = ('NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW', 'N');
      push @event, "3:battery:" . ($db[0] & 1 ? 'low' : 'ok');
      push @event, "3:windDirection:" . $windDirection[$db[3]];
      push @event, "3:windSpeedAverage:" . $db[2] / 1.275;
      push @event, "3:windSpeedMax:" . $db[1] / 1.275;
      push @event, "3:state:" . $db[2] / 1.275;

    } elsif ($st eq "rainSensor.01") {
      # Rain Sensor (EEP A5-13-08)
      my $ras = ($db[3] & 0x40) >> 6;
      my $rfa = ($db[3] & 0x3F) / 10;
      my $rfc = hex(substr($data, 2, 4));
      my $rain = $rfc * 0.6875 * (1 + $ras * $rfa / 100);
      push @event, "3:battery:" . ($db[0] & 1 ? 'low' : 'ok');
      push @event, "3:rain:$rain";
      push @event, "3:state:$rain";

    } elsif ($st eq "multiFuncSensor") {
      # Multi-Func Sensor (EEP A5-14-01 ... A5-14-06)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[0]_bit_1 is Vibration where 0 = off, 1 = on
      # $db[0]_bit_0 is Contact where 0 = closed, 1 = open
      if (!exists($hash->{helper}{lastEvent}) || $hash->{helper}{lastEvent} ne $data) {
        my $lux = $db[2] << 2;
        if ($db[2] == 251) {$lux = "over range";}
        my $voltage = sprintf "%0.2f", $db[3] * 0.02;
        if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
        my $vibration = $db[0] & 2 ? "on" : "off";
        my $contact = $db[0] & 1 ? "open" : "closed";
        push @event, "3:brightness:$lux";
        push @event, "3:contact:$contact";
        push @event, "3:vibration:$vibration";
        push @event, "3:voltage:$voltage";
        push @event, "3:state:C: $contact V: $vibration E: $lux U: $voltage";
        $hash->{helper}{lastEvent} = $data;
      }
      CommandDeleteReading(undef, "$name alarm");
      if (AttrVal($name, "signOfLife", 'on') eq 'on') {
        RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 132), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      }
    } elsif ($st eq "doorContact") {
      # dual door contact (EEP A5-14-07, A5-14-08)
      if (!exists($hash->{helper}{lastEvent}) || $hash->{helper}{lastEvent} ne $data) {
        my $voltage = sprintf "%0.2f", $db[3] * 0.02;
        my $doorContact = $db[0] & 4 ? 'open' : 'closed';
        my $lockContact = $db[0] & 2 ? 'unlocked' : 'locked';
        my $vibration = $db[0] & 1 ? 'on' : 'off';
        push @event, "3:voltage:$voltage";
        push @event, "3:contact:$doorContact";
        push @event, "3:block:$lockContact";
        push @event, "3:vibration:$vibration";
        push @event, "3:state:C: $doorContact B: $lockContact V: $vibration U: $voltage";
        $hash->{helper}{lastEvent} = $data;
      }
      CommandDeleteReading(undef, "$name alarm");
      if (AttrVal($name, "signOfLife", 'on') eq 'on') {
        RemoveInternalTimer($hash->{helper}{timer}{alarm}) if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 132), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      }

    } elsif ($st eq "windowContact") {
      # window contact (EEP A5-14-09, A5-14-0A)
      if (!exists($hash->{helper}{lastEvent}) || $hash->{helper}{lastEvent} ne $data) {
        my $voltage = sprintf "%0.2f", $db[3] * 0.02;
        my %window = (0 => 'closed', 1 => 'tilt', 2 => 'reserved', 3 => 'open');
        my $window = $window{(($db[0] & 6) >> 1)};
        my $vibration = $db[0] & 1 ? 'on' : 'off';
        push @event, "3:voltage:$voltage";
        push @event, "3:window:$window";
        push @event, "3:vibration:$vibration";
        push @event, "3:state:W: $window V: $vibration U: $voltage";
        $hash->{helper}{lastEvent} = $data;
      }
      CommandDeleteReading(undef, "$name alarm");
      if (AttrVal($name, "signOfLife", 'on') eq 'on') {
        RemoveInternalTimer($hash->{helper}{timer}{alarm})  if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + AttrVal($name, "signOfLifeInterval", 132), 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      }

    } elsif ($st =~ m/^digitalInput\.0[12]$/) {
      # Digital Input (EEP A5-30-01, A5-30-02)
      my $contact;
      if ($st eq "digitalInput.01") {
        # Single Input Contact, Batterie Monitor (EEP A5-30-01)
        # [Thermokon SR65 DI, untested]
        # $db[2] is the supply voltage, if >= 121 = battery ok
        # $db[1] is the input state, if <= 195 = contact closed
        my $battery = $db[2] >= 121 ? "ok" : "low";
        $contact = $db[1] <= 195 ? "closed" : "open";
        push @event, "3:battery:$battery";
      } else {
        # Single Input Contact (EEP A5-30-02)
        # $db[0]_bit_0 is the input state where 0 = closed, 1 = open
        $contact = $db[0] & 1 ? "open" : "closed";
      }
      push @event, "3:contact:$contact";
      push @event, "3:state:$contact";

    } elsif ($st eq "digitalInput.03") {
      # 4 digital inputs, wake, temperature (EEP A5-30-03)
      my $temperature = sprintf "%0.1f", 40 - $db[2] * 40 / 255;
      push @event, "3:temperature:$temperature";
      if ($model eq 'Eltako_TF_RWB') {
        # Eltako TF-RWB smoke detector
        my $alarm = $db[1] & 16 ? 'off' : 'smoke-alarm';
        if (!exists($hash->{helper}{lastEvent}) || $hash->{helper}{lastEvent} ne $alarm || ReadingsVal($name, 'alarm', '') eq 'dead_sensor') {
          push @event, "3:alarm:$alarm";
          $hash->{helper}{lastEvent} = $alarm;
        }
        push @event, "3:state:$alarm";
        RemoveInternalTimer($hash->{helper}{timer}{alarm})  if(exists $hash->{helper}{timer}{alarm});
        @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
        InternalTimer(gettimeofday() + 1980, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
      } else {
        my $in0 = $db[1] & 1;
        my $in1 = ($db[1] & 2) > 1;
        my $in2 = ($db[1] & 4) > 2;
        my $in3 = ($db[1] & 8) > 3;
        my $wake = $db[1] & 16 ? 'high' : 'low';
        push @event, "3:in0:$in0";
        push @event, "3:in1:$in1";
        push @event, "3:in2:$in2";
        push @event, "3:in3:$in3";
        push @event, "3:wake:$wake";
        push @event, "3:state:T: $temperature I: " . $in0 . $in1 . $in2 . $in3 . " W: " . $wake;
      }

    } elsif ($st eq "digitalInput.04") {
      # 3 digital inputs, 1 digital input 8 bit (EEP A5-30-04)
      my $in0 = $db[0] & 1;
      my $in1 = ($db[0] & 2) > 1;
      my $in2 = ($db[0] & 4) > 2;
      my $in3 = $db[1];
      push @event, "3:in0:$in0";
      push @event, "3:in1:$in1";
      push @event, "3:in2:$in2";
      push @event, "3:in3:$in3";
      push @event, "3:state:" . $in0 . $in1 . $in2 . " " . $in3;

    } elsif ($st eq "digitalInput.05") {
      # single input contact, retransmission, battery monitor (EEP A5-30-05)
      my $signalIdx = $db[1] & 0x7F;
      my $signalIdxLast = ReadingsVal($name, "signalIdx", undef);
      my $signalType = $db[1] & 0x80 ? "heartbeat" : "event";
      push @event, "3:voltage:" . sprintf "%0.1f", $db[2] / 255 * 3.3;
      push @event, "3:signalIdx:$signalIdx";
      push @event, "3:telegramType:$signalType";
      if (defined $signalIdxLast) {
        if ($signalIdx == $signalIdxLast + 1 || $signalIdx == 0 && $signalIdxLast == 127) {
          push @event, "3:state:$signalType";
        } else {
          push @event, "3:state:error";
        }
      } else {
        push @event, "3:state:$signalType";
      }

    } elsif ($st eq "gateway") {
      # Gateway (EEP A5-38-08)
      # $db[3] is the command ID ($gwCmdID)
      # Eltako devices not send teach-in telegrams
      if(($db[0] & 8) == 0) {
        # teach-in, identify and store command type in attr gwCmd
        my $gwCmd = AttrVal($name, "gwCmd", undef);
        if (!$gwCmd) {
          $gwCmd = $EnO_gwCmd[$db[3] - 1];
          $attr{$name}{gwCmd} = $gwCmd;
        }
      }
      if ($db[3] == 1) {
        # Switching
        # Eltako devices not send A5 telegrams
        push @event, "3:executeTime:" . sprintf "%0.1f", (($db[2] << 8) | $db[1]) / 10;
        push @event, "3:block:" . ($db[0] & 4 ? "lock" : "unlock");
        push @event, "3:executeType" . ($db[0] & 2 ? "delay" : "duration");
        push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");
      } elsif ($db[3] == 2) {
        # Dimming
        # $db[0]_bit_2 is store final value, not used, because
        # dimming value is always stored
        push @event, "3:rampTime:$db[1]";
        push @event, "3:state:" . ($db[0] & 0x01 ? "on" : "off");
        if ($db[0] & 4) {
          # Relative Dimming Range
          push @event, "3:dim:" . sprintf "%d", $db[2] * 100 / 255;
        } else {
          push @event, "3:dim:$db[2]";
        }
        push @event, "3:dimValueLast:$db[2]" if ($db[2] > 0);
      } elsif ($db[3] == 3) {
        # Setpoint shift
        # $db1 is setpoint shift where 0 = -12.7 K ... 255 = 12.8 K
        my $setpointShift = sprintf "%0.1f", -12.7 + $db[1] / 10;
        push @event, "3:setpointShift:$setpointShift";
        push @event, "3:state:$setpointShift";
      } elsif ($db[3] == 4) {
        # Basic Setpoint
        # $db1 is setpoint where 0 = 0 °C ... 255 = 51.2 °C
        my $setpoint = sprintf "%0.1f", $db[1] / 5;
        push @event, "3:setpoint:$setpoint";
        push @event, "3:state:$setpoint";
      } elsif ($db[3] == 5) {
        # Control variable
        # $db1 is control variable override where 0 = 0 % ... 255 = 100 %
        push @event, "3:controlVar:" . sprintf "%d", $db[1] * 100 / 255;
        my $controllerMode = ($db[0] & 0x60) >> 5;
        if ($controllerMode == 0) {
          push @event, "3:controllerMode:auto";
          push @event, "3:state:auto";
        } elsif ($controllerMode == 1) {
          push @event, "3:controllerMode:heating";
          push @event, "3:state:heating";
        } elsif ($controllerMode == 2){
          push @event, "3:controllerMode:cooling";
          push @event, "3:state:cooling";
        } elsif ($controllerMode == 3){
          push @event, "3:controllerMode:off";
          push @event, "3:state:off";
        }
        push @event, "3:controllerState:" . ($db[0] & 0x10 ? "override" : "auto");
        push @event, "3:energyHoldOff:" . ($db[0] & 4 ? "holdoff" : "normal");
        my $occupancy = $db[0] & 3;
        if ($occupancy == 0) {
          push @event, "3:presence:present";
        } elsif ($occupancy == 1){
          push @event, "3:presence:absent";
        } elsif ($occupancy == 2){
          push @event, "3:presence:standby";
        }
      } elsif ($db[3] == 6) {
        # Fan stage
        if ($db[1] == 0) {
          push @event, "3:fan:0";
          push @event, "3:state:0";
        } elsif ($db[1] == 1) {
          push @event, "3:fan:1";
          push @event, "3:state:1";
        } elsif ($db[1] == 2) {
          push @event, "3:fan:2";
          push @event, "3:state:2";
        } elsif ($db[1] == 3) {
          push @event, "3:fan:3";
          push @event, "3:state:3";
        } elsif ($db[1] == 255) {
          push @event, "3:fan:auto";
          push @event, "3:state:auto";
        }
      } else {
        push @event, "3:state:Gateway Command ID $db[3] unknown.";
      }

    } elsif ($st eq "energyManagement.01") {
      # Energy Management, Demand Response
      # (A5-37-01)
      EnOcean_energyManagement_01Parse($hash, @db);

    } elsif ($st eq "manufProfile") {
      # Manufacturer Specific Applications (EEP A5-3F-7F)
      if ($manufID eq "002") {
        # [Thermokon SR65 3AI, untested]
        # $db[3] is the input 3 where 0x00 = 0 V ... 0xFF = 10 V
        # $db[2] is the input 2 where 0x00 = 0 V ... 0xFF = 10 V
        # $db[1] is the input 1 where 0x00 = 0 V ... 0xFF = 10 V
        my $input3 = sprintf "%0.2f", $db[3] * 10 / 255;
        my $input2 = sprintf "%0.2f", $db[2] * 10 / 255;
        my $input1 = sprintf "%0.2f", $db[1] * 10 / 255;
        push @event, "3:input1:$input1";
        push @event, "3:input2:$input2";
        push @event, "3:input3:$input3";
        push @event, "3:state:I1: $input1 I2: $input2 I3: $input3";

      } elsif ($manufID eq "005") {
        # omnio
        if ($db[0] == 0x0C) {
          # omnio UPH 2330/1x
          my $channel = ($db[1] & 0xF0) > 4;
          my $emergencyMode = $db[1] & 8 ? "on" : "off";
          my $window = $db[1] & 4 ? "open" : "closed";
          my $nightReduction = $db[1] & 2 ? "on" : "off";
          my $state = $db[1] & 1 ? "on" : "off";
          my $temperature = sprintf "%0.1f", $db[2] * 40 / 250;
          my $setpointTemp = sprintf "%0.1f", $db[3] * 40 / 250;
          push @event, "3:emergencyMode" . $channel . ":$emergencyMode";
          push @event, "3:window" . $channel . ":$window";
          push @event, "3:nightReduction" . $channel . ":$nightReduction";
          push @event, "3:temperature" . $channel . ":$temperature";
          push @event, "3:setpointTemp" . $channel . ":$setpointTemp";
          push @event, "3:state:$state";
        }

      } elsif ($manufID eq "00D") {
        # [Eltako shutter]
        my $angleMax = AttrVal($name, "angleMax", 90);
	my $angleMin = AttrVal($name, "angleMin", -90);
	my $anglePos = ReadingsVal($name, ".anglePosStart", undef);
	my $angleTime = AttrVal($name, "angleTime", 0);
	my $position = ReadingsVal($name, ".positionStart", undef);
        my $shutTime = AttrVal($name, "shutTime", 255);
        my $shutTimeStop = ($db[3] << 8 | $db[2]) * 0.1;
        my $state;
        $angleMax = 90 if ($angleMax !~ m/^[+-]?\d+$/);
        $angleMax = 180 if ($angleMax > 180);
        $angleMax = -180 if ($angleMax < -180);
        $angleMin = -90 if ($angleMin !~ m/^[+-]?\d+$/);
        $angleMin = 180 if ($angleMin > 180);
        $angleMin = -180 if ($angleMin < -180);
        ($angleMax, $angleMin) = ($angleMin, $angleMax) if ($angleMin > $angleMax);
        $angleMax ++ if ($angleMin == $angleMax);
        $angleTime = 0 if ($angleTime !~ m/^[+-]?\d+$/);
        $angleTime = 6 if ($angleTime > 6);
        $angleTime = 0 if ($angleTime < 0);
        $shutTime = 255 if ($shutTime !~ m/^[+-]?\d+$/);
        $shutTime = 255 if ($shutTime > 255);
        $shutTime = 1 if ($shutTime < 1);

        if ($db[0] == 0x0A) {
          push @event, "3:block:unlock";
        } elsif ($db[0] == 0x0E) {
          push @event, "3:block:lock";
        }
        if (defined $position) {
          if ($db[1] == 1) {
            # up
            $position -= $shutTimeStop / $shutTime * 100;
            if ($angleTime) {
              $anglePos -= ($angleMax - $angleMin) * $shutTimeStop / $angleTime;
              if ($anglePos < $angleMin) {
                $anglePos = $angleMin;
              }
            } else {
              $anglePos = $angleMin;
            }
            if ($position <= 0) {
              $anglePos = 0;
              $position = 0;
              push @event, "3:endPosition:open";
              $state = "open";
            } else {
              push @event, "3:endPosition:not_reached";
              $state = "stop";
            }
            push @event, "3:anglePos:" . sprintf("%d", $anglePos);
            push @event, "3:position:" . sprintf("%d", $position);
            push @event, "3:.anglePosStart:" . sprintf("%d", $anglePos);
            push @event, "3:.positionStart:" . sprintf("%d", $position);
          } elsif ($db[1] == 2) {
          # down
            $position += $shutTimeStop / $shutTime * 100;
            if ($angleTime) {
              $anglePos += ($angleMax - $angleMin) * $shutTimeStop / $angleTime;
              if ($anglePos > $angleMax) {
                $anglePos = $angleMax;
              }
            } else {
              $anglePos = $angleMax;
            }
            if($position >= 100) {
              $anglePos = $angleMax;
              $position = 100;
              push @event, "3:endPosition:closed";
              $state = "closed";
            } else {
              push @event, "3:endPosition:not_reached";
              $state = "stop";
            }
            push @event, "3:anglePos:" . sprintf("%d", $anglePos);
            push @event, "3:position:" . sprintf("%d", $position);
            push @event, "3:.anglePosStart:" . sprintf("%d", $anglePos);
            push @event, "3:.positionStart:" . sprintf("%d", $position);
          } else {
            $state = "not_reached";
          }
        push @event, "3:state:$state";
        }

      } else {
        # Unknown Application
        push @event, "3:state:Manufacturer Specific Application unknown";
      }

    } elsif ($st eq "contact" && $manufID eq "00D") {
      # Eltako TF-FKB voltage telegram
      push @event, "3:voltage:" . sprintf "%0.1f", $db[2] * 0.02;
      push @event, "3:energyStorage:" . sprintf "%0.1f", $db[3] * 0.02;

    } elsif ($st eq "PM101") {
      # Light and Presence Sensor [Omnio Ratio eagle-PM101]
      # The sensor also sends switching commands (RORG F6) with the senderID-1
      # $db[2] is the illuminance where 0x00 = 0 lx ... 0xFF = 1000 lx
      my $channel2 = $db[0] & 2 ? "on" : "off";
      push @event, "3:brightness:" . ($db[2] << 2);
      push @event, "3:channel1:" . ($db[0] & 1 ? "on" : "off");
      push @event, "3:channel2:" . $channel2;
      push @event, "3:motion:" . $channel2;
      push @event, "3:state:" . $channel2;

    } elsif ($st eq "radioLinkTest") {
      # Radio Link Test (EEP A5-3F-00)
      @{$hash->{helper}{rlt}{param}} = ('parse', $hash, $data, $subDef, 'master', $RSSI);
      EnOcean_RLT($hash->{helper}{rlt}{param});

    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";

    } else {
      # unknown devices
      push @event, "3:state:$db[3]";
      push @event, "3:sensor1:$db[3]";
      push @event, "3:sensor2:$db[2]";
      push @event, "3:sensor3:$db[1]";
      push @event, "3:D3:" . ($db[0] & 8 ? 1 : 0);
      push @event, "3:D2:" . ($db[0] & 4 ? 1 : 0);
      push @event, "3:D1:" . ($db[0] & 2 ? 1 : 0);
      push @event, "3:D0:" . ($db[0] & 1 ? 1 : 0);
    }

  } elsif ($rorg eq "D2") {
    # VLD telegram
    if ($st eq "roomCtrlPanel.00") {
      # EEP D2-10-01 - D2-10-03
      my ($key, $val);
      # message identifier
      my $mid = hex(substr($data, 0, 2)) >> 5;
      # message continuation flag
      my $mcf = hex(substr($data, 0, 2)) & 3;
      my ($irc, $fbc, $gmt);

      if ($mcf == 0) {
        # message complete
        # read stored telegrams
        if (!defined($hash->{helper}{$mid}{messagePart})) {
          $hash->{helper}{$mid}{messagePart} = 1;
          $hash->{helper}{$mid}{data}{1} = $data;
        } else {
          $hash->{helper}{$mid}{messagePart} += 1;
          $hash->{helper}{$mid}{data}{$hash->{helper}{$mid}{messagePart}} = $data;
        }

        if ($mid == 4) {
          CommandDeleteAttr(undef, "$name timeProgram1");
          CommandDeleteAttr(undef, "$name timeProgram2");
          CommandDeleteAttr(undef, "$name timeProgram3");
          CommandDeleteAttr(undef, "$name timeProgram4");
        }

        for (my $partCntr = $hash->{helper}{$mid}{messagePart}; $partCntr > 0; $partCntr --) {
          $data = $hash->{helper}{$mid}{data}{$partCntr};
          delete $hash->{helper}{$mid}{data}{$partCntr};
          if ($partCntr == 1) {
            delete $hash->{helper}{$mid}{messagePart};
          } else {
            $hash->{helper}{$mid}{messagePart} --;
          }
          $dbCntr = 0;
          for (my $strCntr = length($data) / 2 - 1; $strCntr >= 0; $strCntr --) {
            $db[$dbCntr] = hex substr($data, $strCntr * 2, 2);
            $dbCntr++;
          }

        #Log3 $name, 2, "EnOcean $name EnOcean_Parse write MID $mid DATA $data to part $partCntr";
        #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 1 MID $mid DATA $data to " . sprintf "%02X%02X%02X%02X%02X%02X", $db[5], $db[4], $db[3], $db[2], $db[1], $db[0];

          if ($mid == 0) {
            # general message
            $irc = ($db[0] & 56) >> 3;
            $fbc = ($db[0] & 6) >> 1;
            $gmt = $db[0] & 1;
            #push @event, "3:general:$data";

          } elsif ($mid == 1) {
            # data message
            my $temperature = "-";
            $temperature = sprintf "%.1f", $db[0] / 254 * 40 if ($db[2] & 1);
            push @event, "3:temperature:$temperature";
            my $setpointTemp = "-";
            $setpointTemp = sprintf "%.1f", $db[1] / 254 * 40 if ($db[2] & 2);
            push @event, "3:setpointTemp:$setpointTemp";
            my $roomCtrlMode = ($db[2] & 12) >> 2;
            if ($roomCtrlMode == 3) {
              $roomCtrlMode = "buildingProtection";
            } elsif ($roomCtrlMode == 2) {
              $roomCtrlMode = "preComfort";
            } elsif ($roomCtrlMode == 1) {
              $roomCtrlMode = "economy";
            } else{
              $roomCtrlMode = "comfort";
            }
            push @event, "3:roomCtrlMode:$roomCtrlMode";
            my $heating = ($db[2] & 48) >> 4;
            if ($heating == 3) {
              $heating = "auto";
            } elsif ($heating == 2) {
              $heating = "off";
            } elsif ($heating == 1) {
              $heating = "on";
            } else{
              $heating = "-";
            }
            if ($heating ne "-") {
              push @event, "3:heating:$heating";
            }
            my $cooling = ($db[2] & 192) >> 6;
            if ($cooling == 3) {
              $cooling = "auto";
            } elsif ($cooling == 2) {
              $cooling = "off";
            } elsif ($cooling == 1) {
              $cooling = "on";
            } else{
              $cooling = "-";
            }
            if ($cooling ne "-") {
              push @event, "3:cooling:$cooling";
            }
            my $occupancy = $db[3] & 3;
            if ($occupancy == 3) {
              $occupancy = "reserved";
            } elsif ($occupancy == 2) {
              $occupancy = "absent";
            } elsif ($occupancy == 1) {
              $occupancy = "present";
            } else{
              $occupancy = "-";
            }
            if ($occupancy eq "-") {
              $occupancy = ReadingsVal($name, "occupancy", "-");
            } else {
              push @event, "3:occupancy:$occupancy";
            }
            my $motion = ($db[3] & 12) >> 2;
            if ($motion == 3) {
              $motion = "reserved";
            } elsif ($motion == 2) {
              $motion = "on";
            } elsif ($motion == 1) {
              $motion = "off";
            } else{
              $motion = "-";
            }
            if ($motion eq "-") {
              $motion = ReadingsVal($name, "motion", "-");
            } else {
              push @event, "3:motion:$motion";
            }
            push @event, "3:solarPowered:" . ($db[3] & 16 ? "no" : "yes");
            my $battery = ($db[3] & 96) >> 5;
            if ($battery == 3) {
              $battery = "empty";
            } elsif ($battery == 2) {
              $battery = "low";
            } elsif ($battery == 1) {
              $battery = "ok";
            } else{
              $battery = "-";
            }
            if ($battery ne "-") {
              push @event, "3:battery:$battery";
            }
            my $window = $db[4] & 3;
            if ($window == 3) {
              $window = "reserved";
            } elsif ($window == 2) {
              $window = "open";
            } elsif ($window == 1) {
              $window = "closed";
            } else{
              $window = "-";
            }
            if ($window ne "-") {
              push @event, "3:window:$window";
            }
            push @event, "3:moldWarning:" . ($db[4] & 4 ? "on" : "off");
            push @event, "3:customWarning1:" . ($db[4] & 8 ? "on" : "off");
            push @event, "3:customWarning2:" . ($db[4] & 16 ? "on" : "off");
            push @event, "3:fanSpeedMode:" . ($db[4] & 64 ? "local" : "central");
            my $fanSpeed = 0;
            $fanSpeed = sprintf "%d", $db[5] & 127 if ($db[4] & 128);
            push @event, "3:fanSpeed:$fanSpeed";
            my $humi = "-";
            $humi = sprintf "%d", $db[6] / 2.55 if ($db[5] & 128);
            push @event, "3:humidity:$humi";
            push @event, "3:state:T: $temperature H: $humi F: $fanSpeed SPT: $setpointTemp O: $occupancy M: $motion";

          } elsif ($mid == 2) {
            # configuration message
            $attr{$name}{blockFanSpeed} = $db[6] & 1 ? "no" : "yes";
            $attr{$name}{blockSetpointTemp} = $db[6] & 2 ? "no" : "yes";
            $attr{$name}{blockOccupancy} = $db[6] & 4 ? "no" : "yes";
            $attr{$name}{blockTimeProgram} = $db[6] & 8 ? "no" : "yes";
            $attr{$name}{blockDateTime} = $db[6] & 16 ? "no" : "yes";
            $attr{$name}{blockDisplay} = $db[6] & 32 ? "no" : "yes";
            $attr{$name}{blockTemp} = $db[6] & 64 ? "no" : "yes";
            $attr{$name}{blockMotion} = $db[6] & 128 ? "no" : "yes";
            my $pollInterval = $db[5] >> 2;
            if ($pollInterval == 63) {
              $attr{$name}{pollInterval} = 1440;
            } elsif ($pollInterval == 62) {
              $attr{$name}{pollInterval} = 720;
            } elsif ($pollInterval == 61) {
              $attr{$name}{pollInterval} = 180;
            } else {
              $attr{$name}{pollInterval} = $pollInterval;
            }
            $attr{$name}{blockKey} = $db[5] & 2 ? "no" : "yes";
            my $displayContent = $db[4] >> 5;
            my %displayContent = (7 => "humidity",
                                  6 => "off",
                                  5 => "setpointTemp",
                                  4 => "tempertureExtern",
                                  3 => "temperatureIntern",
                                  2 => "time",
                                  1 => "default",
                                  0 => "no_change"
                                 );
            while (($key, $val) = each(%displayContent)) {
              $attr{$name}{displayContent} = $val if ($key == $displayContent);
            }
            my $temperatureScale = ($db[4] & 24) >> 3;
            my %temperatureScale = (3 => "F",
                                    2 => "C",
                                    1 => "default",
                                    0 => "no_change"
                                   );
            while (($key, $val) = each(%temperatureScale)) {
              $attr{$name}{temperatureScale} = $val if ($key == $temperatureScale);
            }
            $attr{$name}{daylightSavingTime} = $db[4] & 4 ? "not_supported" : "supported";
            my $timeNotation = $db[4] & 3;
            if ($timeNotation == 0) {
              $attr{$name}{timeNotation} = "no_change";
            } elsif ($timeNotation == 1) {
              $attr{$name}{timeNotation} = "default";
            } elsif ($timeNotation == 2) {
              $attr{$name}{timeNotation} = 24;
            } elsif ($timeNotation == 3) {
              $attr{$name}{timeNotation} = 12;
            }
            EnOcean_CommandSave(undef, undef);

          } elsif ($mid == 3) {
            # room control setup
            my $setpointComfort = "-";
            $setpointComfort = sprintf "%.1f", $db[1] / 254 * 40 if ($db[0] & 1);
            push @event, "3:setpointComfortTemp:$setpointComfort";
            my $setpointEconomy = "-";
            $setpointEconomy = sprintf "%.1f", $db[2] / 254 * 40 if ($db[0] & 2);
            push @event, "3:setpointEconomyTemp:$setpointEconomy";
            my $setpointPreComfort = "-";
            $setpointPreComfort = sprintf "%.1f", $db[3] / 254 * 40 if ($db[0] & 4);
            push @event, "3:setpointPreComfortTemp:$setpointPreComfort";
            my $setpointBuildingProtection = "-";
            $setpointBuildingProtection = sprintf "%.1f", $db[3] / 254 * 40 if ($db[0] & 8);
            push @event, "3:setpointBuildingProtectionTemp:$setpointBuildingProtection";

          } elsif ($mid == 4) {
            # time program setup
            my $timeProgram = "timeProgram" . $partCntr;
            my $period = $db[0] >> 4;
            my $periodVal = "";
            my %period = (15 => "FrMo",
                          14 => "FrSu",
                          13 => "ThFr",
                          12 => "WeFr",
                          11 => "TuTh",
                          10 => "MoWe",
                           9 => "Su",
                           8 => "Sa",
                           7 => "Fr",
                           6 => "Th",
                           5 => "We",
                           4 => "Tu",
                           3 => "Mo",
                           2 => "SaSu",
                           1 => "MoFr",
                           0 => "MoSu"
                          );
            while (($key, $val) = each(%period)) {
              $periodVal = $val if ($key == $period);
            }
            my $roomCtrlMode = ($db[0] & 12) >> 2;
            if ($roomCtrlMode == 3) {
              $roomCtrlMode = "buildingProtection";
            } elsif ($roomCtrlMode == 2) {
              $roomCtrlMode = "preComfort";
            } elsif ($roomCtrlMode == 1) {
              $roomCtrlMode = "economy";
            } else{
              $roomCtrlMode = "comfort";
            }
            my ($startHour, $startMinute, $endHour, $endMinute) = ($db[1], $db[2], $db[3], $db[4]);
            $startHour = $startHour < 10 ? $startHour = "0" . $startHour : $startHour;
            $startMinute = $startMinute < 10 ? $startMinute = "0" . $startMinute : $startMinute;
            $endHour = $endHour < 10 ? $endHour = "0" . $endHour : $endHour;
            $endMinute = $endMinute < 10 ? $endMinute = "0" . $endMinute : $endMinute;

          #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 2 MID $mid DATA $data to " . sprintf "%02X%02X%02X%02X%02X%02X", $db[5], $db[4], $db[3], $db[2], $db[1], $db[0];
          #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 3 MID $mid DATA $data to $timeProgram VAL: $periodVal $startHour:$startMinute $endHour:$endMinute $roomCtrlMode";

            $attr{$name}{$timeProgram} = "$periodVal $startHour:$startMinute $endHour:$endMinute $roomCtrlMode";

          #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 4 MID $mid DATA $data to $timeProgram VAL: $attr{$name}{$timeProgram}";

            EnOcean_CommandSave(undef, undef);
          }
        }
        ($err, $response) = EnOcean_roomCtrlPanel_00Snd(undef, $hash, $packetType, $mid, $mcf, $irc, $fbc, $gmt);

      } elsif ($mcf == 1) {
        # message incomplete
        if (!defined($hash->{helper}{$mid}{messagePart})) {
          $hash->{helper}{$mid}{messagePart} = 1;
        } elsif ($hash->{helper}{$mid}{messagePart} >= 4) {
          # max 4 message parts stored
          for (my $partCntr = 1; $partCntr < $hash->{helper}{$mid}{messagePart}; $partCntr ++) {
            $hash->{helper}{$mid}{data}{$partCntr} = $hash->{helper}{$mid}{data}{$partCntr + 1};
          }
        } else {
          $hash->{helper}{$mid}{messagePart} += 1;
        }
        $hash->{helper}{$mid}{data}{$hash->{helper}{$mid}{messagePart}} = $data;
        #Log3 $name, 2, "EnOcean $name EnOcean_Parse store MID $mid DATA $data to messagePart $hash->{helper}{$mid}{messagePart}";
        ($err, $response) = EnOcean_roomCtrlPanel_00Snd(undef, $hash, $packetType, $mid, $mcf, undef, undef, undef);
      }

    } elsif ($st eq "actuator.01") {
      # Electronic switches and dimmers with Energy Measurement and Local Control
      # (D2-01-00 - D2-01-12)
      my $channel = (hex substr($data, 2, 2)) & 0x1F;
      if ($channel == 31) {$channel = "Input";}
      my $cmd = hex substr($data, 1, 1);

      if ($cmd == 4) {
        # actuator status response
        my $overCurrentOff;
        my $error;
        my $localControl;
        my $dim;
        push @event, "3:powerFailure" . $channel . ":" . ($db[2] & 0x80 ? "enabled" : "disabled");
        push @event, "3:powerFailureDetection" . $channel . ":" . ($db[2] & 0x40 ? "detected" : "not_detected");
        if (($db[1] & 0x80) == 0) {
          $overCurrentOff = "ready";
        } else {
          $overCurrentOff = "executed";
        }
        push @event, "3:overCurrentOff" . $channel . ":" . $overCurrentOff;
        if ((($db[1] & 0x60) >> 5) == 1) {
          $error = "warning";
        } elsif ((($db[1] & 0x60) >> 5) == 2) {
          $error = "failure";
        } elsif ((($db[1] & 0x60) >> 5) == 3) {
          $error = "not_supported";
        } else {
          $error = "ok";
        }
        push @event, "3:error" . $channel . ":" . $error;
        if (($db[0] & 0x80) == 0) {
          $localControl = "disabled";
        } else {
          $localControl = "enabled";
        }
        push @event, "3:localControl" . $channel . ":" . $localControl;
        my $dimValue = $db[0] & 0x7F;
        if ($dimValue == 0) {
          push @event, "3:channel" . $channel . ":off";
          push @event, "3:state:off";
        } else {
          push @event, "3:channel" . $channel . ":on";
          push @event, "3:state:on";
        }
        if ($channel ne "Input") {
          push @event, "3:dim:" . $dimValue;
          push @event, "3:dim" . $channel . ":" . $dimValue;
        } else {
          push @event, "3:dim" . $channel . ":" . $dimValue;
        }

      } elsif ($cmd == 7) {
        # actuator measurement response
        my $unit = $db[4] >> 5;
        if ($unit == 1) {
          #$unit = "Wh";
          $unit = "KWh";
          push @event, "3:energyUnit" . $channel . ":" . $unit;
          push @event, "3:energy" . $channel . ":" . sprintf("%.3f", (hex substr($data, 4, 8)) / 1000);
        } elsif ($unit == 2) {
          $unit = "KWh";
          push @event, "3:energyUnit" . $channel . ":" . $unit;
          push @event, "3:energy" . $channel . ":" . hex substr($data, 4, 8);
        } elsif ($unit == 3) {
          $unit = "W";
          push @event, "3:powerUnit" . $channel . ":" . $unit;
          push @event, "3:power" . $channel . ":" . hex substr($data, 4, 8);
        } elsif ($unit == 4) {
          $unit = "KW";
          push @event, "3:powerUnit" . $channel . ":" . $unit;
          push @event, "3:power" . $channel . ":" . hex substr($data, 4, 8);
        } else {
          $unit = "Ws";
          push @event, "3:energyUnit" . $channel . ":" . $unit;
          push @event, "3:energy" . $channel . ":" . hex substr($data, 4, 8);
        }

      } elsif ($cmd == 10) {
        # pilot wire mode response
        my $roomCtrlMode = $db[0] & 7;
        my %roomCtrlMode = (
          0 => "off",
          1 => "comfort",
          2 => "economy",
          3 => "buildingProtection",
          4 => "comfort-1",
          5 => "comfort-2"
        );
        push @event, "3:roomCtrlMode" . $roomCtrlMode{$roomCtrlMode} if (exists $roomCtrlMode{$roomCtrlMode});

      } elsif ($cmd == 13) {
        # external interface settings
        push @event, "3:autoOffTime" . $channel . ":" . sprintf("%0.1f", hex(substr($data, 4, 4)) * 0.1);
        push @event, "3:delayOffTime" . $channel . ":" . sprintf("%0.1f", hex(substr($data, 8, 4)) * 0.1);
        my $extSwitchMode = ($db[0] & 0xC0) >> 6;
        my %extSwitchMode = (
          0 => "unavailable",
          1 => "switch",
          2 => "pushbutton",
          3 => "auto"
        );
        push @event, "3:extSwitchMode" . $extSwitchMode{$extSwitchMode} if (exists $extSwitchMode{$extSwitchMode});
        push @event, "3:extSwitchType" . ($db[0] & 0x20 ? 'direction' : 'toggle');

      } else {
        # unknown response
      }

    } elsif ($st eq "switch.00" || $st eq "windowHandle.10") {
      $db[0] &= 0x0F;
      if ($db[0] == 1) {
        push @event, "3:state:open_from_tilted";
      } elsif ($db[0] == 2) {
        push @event, "3:state:closed";
      } elsif ($db[0] == 3) {
        push @event, "3:state:open";
      } elsif ($db[0] == 4) {
        push @event, "3:state:tilted";
      } elsif ($db[0] == 5) {
        push @event, "3:state:AI,B0";
        push @event, "3:channelA:AI";
        push @event, "3:channelB:B0";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 6) {
        CommandDeleteReading(undef, "$name channel.*");
        push @event, "3:state:pressed34";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 7) {
        push @event, "3:state:A0,B0";
        push @event, "3:channelA:A0";
        push @event, "3:channelB:B0";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 8) {
        if (AttrVal($name, "sensorMode", "switch") eq "pushbutton") {
          push @event, "3:state:pressed";
        }
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 9) {
        push @event, "3:state:AI,BI";
        push @event, "3:channelA:AI";
        push @event, "3:channelB:BI";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 10) {
        push @event, "3:state:A0,BI";
        push @event, "3:channelA:A0";
        push @event, "3:channelB:BI";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 11) {
        push @event, "3:state:BI";
        push @event, "3:channelB:BI";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 12) {
        push @event, "3:state:B0";
        push @event, "3:channelB:B0";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 13) {
        push @event, "3:state:AI";
        push @event, "3:channelA:AI";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 14) {
        push @event, "3:state:A0";
        push @event, "3:channelA:A0";
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 15) {
        if (AttrVal($name, "sensorMode", "switch") eq "pushbutton") {
          push @event, "3:state:released";
        }
        push @event, "3:energyBow:released";
      }

    } elsif ($st eq "switch.0A") {
      # Push Button - Single Button EEP D2-03-0A
      if (!exists($hash->{helper}{batteryPercent}) || $hash->{helper}{batteryPercent} != $db[1]) {
        push @event, "3:batteryPercent:$db[1]";
        $hash->{helper}{batteryPercent} = $db[1];
      }
      if ($db[0] == 1) {
        push @event, "3:buttonS:on";
        RemoveInternalTimer($hash->{helper}{timer}{buttonS}) if (exists $hash->{helper}{timer}{buttonS});
        @{$hash->{helper}{timer}{buttonS}} = ($hash, 'buttonS', 'off', 1, 5);
        InternalTimer(gettimeofday() + 0.5, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{buttonS}, 0);
      } elsif ($db[0] == 2) {
        push @event, "3:buttonD:on";
        RemoveInternalTimer($hash->{helper}{timer}{buttonD}) if (exists $hash->{helper}{timer}{buttonD});
        @{$hash->{helper}{timer}{buttonD}} = ($hash, 'buttonD', 'off', 1, 5);
        InternalTimer(gettimeofday() + 0.5, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{buttonD}, 0);
      } elsif ($db[0] == 3) {
        push @event, "3:buttonL:on";
        push @event, "3:state:on";
      } elsif ($db[0] == 4) {
        push @event, "3:buttonL:off";
        push @event, "3:state:off";
      }

    } elsif ($st =~ m/^blindsCtrl\.0[01]$/) {
      # EEP D2-05-0x
      my $channel = (($db[0] & 0xF0) >> 4) + 1;
      my $cmd = $db[0] & 0x0F;
      if ($cmd == 4) {
        # actuator status response
        if ($db[3] == 0) {
          push @event, "3:state:open";
          push @event, "3:endPosition" . sprintf('%02d', $channel) . ":open";
          push @event, "3:position" . sprintf('%02d', $channel) . ":" . $db[3];
          push @event, "3:position:" . $db[3];
        } elsif ($db[3] == 100) {
          push @event, "3:state:closed";
          push @event, "3:endPosition" . sprintf('%02d', $channel) . ":closed";
          push @event, "3:position" . sprintf('%02d', $channel) . ":" . $db[3];
          push @event, "3:position:" . $db[3];
       } elsif ($db[3] == 127) {
          push @event, "3:state:unknown";
          push @event, "3:endPosition" . sprintf('%02d', $channel) . ":unknown";
          push @event, "3:position" . sprintf('%02d', $channel) . ":unknown";
          push @event, "3:position:" . $db[3];
        } else {
          push @event, "3:state:" . $db[3];
          push @event, "3:endPosition" . sprintf('%02d', $channel) . ":not_reached";
          push @event, "3:position" . sprintf('%02d', $channel) . ":" . $db[3];
          push @event, "3:position:" . $db[3];
        }
        if ($db[2] == 127) {
          push @event, "3:anglePos" . sprintf('%02d', $channel) . ":unknown";
        } else {
          push @event, "3:anglePos" . sprintf('%02d', $channel) . ":" . $db[2];
          push @event, "3:anglePos:" . $db[2];
        }
        if ($db[1] == 0) {
          push @event, "3:block" . sprintf('%02d', $channel) . ":unlock";
        } elsif ($db[1] == 1) {
          push @event, "3:block" . sprintf('%02d', $channel) . ":lock";
        } elsif ($db[1] == 2) {
          push @event, "3:block" . sprintf('%02d', $channel) . ":alarm";
        } else {
          push @event, "3:block" . sprintf('%02d', $channel) . ":reserved";
        }

      } else {
        # unknown response
      }

    } elsif ($st eq "multisensor.01") {
      # Multisensor Windows Handle
      # (D2-06-01)
      # message type
      my $msgType = hex(substr($data, 0, 2));
      my $blinkInterval = 0;
      my $updateInterval = 0;
      my $waitingCmds = ReadingsVal($name, "waitingCmds", undef);
      if ($msgType == 0) {
        # sensor values
        my %onOffTrigger = (
          0 => "off",
          1 => "on",
          14 => "invalid",
          15 => "not_supported",
        );
        my $onOffTrigger = $db[8] >> 4;
        if (exists $onOffTrigger{$onOffTrigger}) {
          push @event, "3:burglaryAlarm:$onOffTrigger{$onOffTrigger}";
        } else {
          push @event, "3:burglaryAlarm:unknown";
        }
        $onOffTrigger = $db[8] & 15;
        if (exists $onOffTrigger{$onOffTrigger}) {
          push @event, "3:protectionAlarm:$onOffTrigger{$onOffTrigger}";
        } else {
          push @event, "3:protectionAlarm:unknown";
        }
        my %handlePosition = (
          0 => "unknown",
          1 => "up",
          2 => "down",
          3 => "left",
          4 => "right",
          14 => "invalid",
          15 => "not_supported"
        );
        my %handleRPS = (
          1 => 'D0',
          2 => 'F0',
          3 => 'E0',
          4 => 'E0'
        );
        my $handlePosition = $db[7] >> 4;
        if (exists $handlePosition{$handlePosition}) {
          push @event, "3:handle:$handlePosition{$handlePosition}";
        } else {
          push @event, "3:handle:unknown";
        }
        # forward handle position (RPS telegam)
        if (exists($handleRPS{$handlePosition}) && defined(AttrVal($name, "subDefH", undef))) {
          EnOcean_SndRadio(undef, $hash, $packetType, "F6", $handleRPS{$handlePosition}, AttrVal($name, "subDefH", "00000000"), '20', 'FFFFFFFF');
        }
        my %windowState = (
          0 => "undef",
          1 => "not_tilted",
          2 => "tilted",
          14 => "invalid",
          15 => "not_supported"
        );
        my %window1BS = (
          1 => '09',
          2 => '08'
        );
        my $windowState = $db[7] & 15;
        if (exists $windowState{$windowState}) {
          push @event, "3:window:$windowState{$windowState}";
        } else {
          push @event, "3:window:unknown";
        }
        # forward window state (1BS telegam)
        if (exists($window1BS{$windowState}) && defined(AttrVal($name, "subDefW", undef))) {
          EnOcean_SndRadio(undef, $hash, $packetType, "D5", $window1BS{$windowState}, AttrVal($name, "subDefW", "00000000"), '00', 'FFFFFFFF');
        }
        my %button = (
          0 => "no_change",
          1 => "pressed",
          2 => "released",
          14 => "invalid",
          15 => "not_supported"
        );
        my $button = $db[6] >> 4;
        if (exists $button{$button}) {
          if ($button == 0 && ReadingsVal($name, "buttonRight", 'unknown') eq 'unknown') {
            push @event, "3:buttonRight:unknown";
          } elsif ($button == 0) {
          } else {
            push @event, "3:buttonRight:$button{$button}";
          }
        } else {
          push @event, "3:buttonRight:unknown";
        }
        $button = $db[6] & 15;
        if (exists $button{$button}) {
          if ($button == 0 && ReadingsVal($name, "buttonLeft", 'unknown') eq 'unknown') {
            push @event, "3:buttonLeft:unknown";
          } elsif ($button == 0) {
          } else {
            push @event, "3:buttonLeft:$button{$button}";
          }
        } else {
          push @event, "3:buttonLeft:unknown";
        }
        my $motion = $db[5] >> 4;
        if (exists $onOffTrigger{$motion}) {
          push @event, "3:motion:$onOffTrigger{$motion}";
        } else {
          push @event, "3:motion:unknown";
        }
        my %vacation = (
          0 => "no_change",
          1 => "absent",
          2 => "present",
          14 => "invalid",
          15 => "not_supported"
        );
        my $vacation = $db[5] & 15;
        if (exists $vacation{$vacation}) {
          if ($vacation == 0 && ReadingsVal($name, "presence", 'unknown') eq 'unknown') {
            push @event, "3:presence:unknown";
          } elsif ($vacation == 0) {
          } else {
            push @event, "3:presence:$vacation{$vacation}";
          }
        } else {
          push @event, "3:presence:unknown";
        }
        my $temperature;
        if ($db[4] <= 250) {
          $temperature = sprintf "%0.1f", $db[4] * 80 / 250 - 20;
          push @event, "3:temperature:$temperature";
        } elsif ($db[4] <= 254) {
          $temperature = '-';
          push @event, "3:temperature:invalid";
        } elsif ($db[4] <= 255) {
          $temperature = '-';
          push @event, "3:temperature:not_supported";
        } else {
          $temperature = '-';
          push @event, "3:temperature:unknown";
        }
        my $humidity;
        if ($db[3] <= 200) {
          $humidity = $db[3] / 2;
          push @event, "3:humidity:$humidity";
        } elsif ($db[3] <= 254) {
          $humidity = '-';
          push @event, "3:humidity:invalid";
        } elsif ($db[3] <= 255) {
          $humidity = '-';
          push @event, "3:humidity:not_supported";
        } else {
          $humidity = '-';
          push @event, "3:humidity:unknown";
        }
        my $brightness = hex(substr($data, 14, 4));
        if ($brightness <= 60000) {
          push @event, "3:brightness:$brightness";
        } elsif ($brightness == 60001) {
          $brightness = '-';
          push @event, "3:brightness:over_range";
        } elsif ($brightness == 65534) {
          $brightness = '-';
          push @event, "3:brightness:invalid";
        } elsif ($brightness == 65535) {
          $brightness = '-';
          push @event, "3:brightness:not_supported";
        } else {
          $brightness = '-';
          push @event, "3:brightness:unknown";
        }
        my $energyStorage = ($db[0] >> 3) * 5;
        my $battery;
        if ($energyStorage <= 5) {
          $battery = 'low';
          push @event, "3:battery:low";
          push @event, "3:energyStorage:$energyStorage";
        } elsif ($energyStorage <= 100) {
          $battery = 'ok';
          push @event, "3:battery:ok";
          push @event, "3:energyStorage:$energyStorage";
        } else {
          $battery = '-';
          push @event, "3:battery:-";
          $energyStorage = '-';
          push @event, "3:energyStorage:unknown";
        }

        push @event, "3:state:T: $temperature H: $humidity E: $brightness M: $onOffTrigger{$motion}";

      } elsif ($msgType == 0x10) {
        # configuration report
        if (defined $waitingCmds) {
           $waitingCmds = $db[3] & 0x80 ? $waitingCmds & 0xDF | 32 : $waitingCmds & 0xDF;
        }
        push @event, "3:presence:" . ($db[3] & 0x80 ? 'absent' : 'present');
        push @event, "3:handleClosedClick:" . ($db[3] & 0x40 ? 'enabled' : 'disabled');
        push @event, "3:batteryLowClick:" . ($db[3] & 0x20 ? 'enabled' : 'disabled');
        $updateInterval = hex(substr($data, 4, 4));
        if ($updateInterval <= 4) {
          $updateInterval = '-';
          push @event, "3:updateInterval:unknown";
        } else {
          push @event, "3:updateInterval:$updateInterval";
        }
        $blinkInterval = $db[0];
        if ($blinkInterval <= 2) {
          $blinkInterval = '-';
          push @event, "3:blinkInterval:unknown";
        } else {
          push @event, "3:blinkInterval:$blinkInterval";
        }

      } elsif ($msgType == 0x20) {
        # log data 01
        push @event, "3:powerOns:" . substr($data, 2, 8);
        push @event, "3:alarms:" . substr($data, 10, 8);

      } elsif ($msgType == 0x21) {
        # log data 02
        push @event, "3:handleMoveClosed:" . substr($data, 2, 8);
        push @event, "3:handleMoveOpend:" . substr($data, 10, 8);
        push @event, "3:handleMoveTilted:" . substr($data, 18, 8);

      } elsif ($msgType == 0x22) {
        # log data 03
        push @event, "3:windowTilts:" . substr($data, 2, 8);

      } elsif ($msgType == 0x23) {
        # log data 04
        push @event, "3:buttonRightPresses:" . substr($data, 2, 8);
        push @event, "3:buttonLeftPresses:" . substr($data, 10, 8);

      } else {

      }

      if (defined $waitingCmds) {
        $updateInterval = 0;
        $blinkInterval = 0;
        if ($waitingCmds & 1) {
          $waitingCmds &= 0xFE;
          $updateInterval = ReadingsVal($name, "updateIntervalSet", 0);
          $updateInterval = $updateInterval =~ m/^\d+$/ ? $updateInterval : 0;
          $blinkInterval = ReadingsVal($name, "blinkIntervalSet", 0);
          $blinkInterval = $blinkInterval =~ m/^\d+$/ ? $blinkInterval : 0;
          CommandDeleteReading(undef, "$name .*Set");
        }
        CommandDeleteReading(undef, "$name waitingCmds");
        $data = sprintf "80%02X%04X%02X", $waitingCmds, $updateInterval, $blinkInterval;
        EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
        #EnOcean_multisensor_01Snd($ctrl, $hash, $packetType);
      }

    } elsif ($st eq "roomCtrlPanel.01") {
      # Room Control Panel
      # (D2-11-01 - D2-11-08)
      my $msgType = hex(substr($data, 1, 1));
      my $setpointType = ReadingsVal($name, "setpointType", 'setpointShift');
      my $waitingCmds = ReadingsVal($name, "waitingCmds", 0);
      if (($waitingCmds & 0x80) == 0) {
        $setpointType = hex(substr($data, 0, 1)) & 8 ? 'setpointTemp' : 'setpointShift';
        push @event, "3:setpointType:$setpointType";
      }
      if ($msgType == 2) {
        my $trigger = ($db[5] & 0x60) >> 5;
        my %trigger = (0 => 'heartbeat', 1 => 'sensor', 2 => 'input');
        push @event, "3:trigger:" . $trigger{$trigger};
        my $temperature = sprintf "%0.1f", $db[4] / 255 * 40;
        push @event, "3:temperature:$temperature";
        my $humidity = sprintf "%d", $db[3] / 2.5;
        push @event, "3:humidity:$humidity";
        my $setpointShiftMax = ($db[0] & 0xF0) >> 4;
        push @event, "3:setpointShiftMax:$setpointShiftMax";
        my $setpointShift = int(0.5 + $db[2] * $setpointShiftMax / 128 * 10) / 10 - $setpointShiftMax;
        push @event, "3:setpointShift:" . sprintf "%0.1f", $setpointShift;
        push @event, "3:setpointBase:$db[1]";
        push @event, "3:setpointTemp:" . sprintf "%0.1f", ($db[1] + $setpointShift);
        my %fanSpeed = (0 => 'auto', 1 => 'off', 2 => 1, 3 => 2, 4 => 3);
        my $fanSpeed = ($db[0] & 0xE) >> 1;
        push @event, "3:fanSpeed:" . $fanSpeed{$fanSpeed};
        push @event, "3:occupancy:" . ($db[0] & 1 ? 'occupied' : 'unoccupied');
        push @event, "3:state:T: $temperature H: $humidity SPT: " . ($db[1] + $setpointShift) . " F: " . $fanSpeed{$fanSpeed};
      }
      CommandDeleteReading(undef, "$name waitingCmds");

    } elsif ($st eq "multiFuncSensor.00") {
      # people activity counter
      # (D2-15-00)
      my @energyStorage = ('ok', 'medium', 'low', 'critical');
      my @presence = ('present', 'absent', 'not_detectable', 'error');
      my $alarm = 'off';
      my $battery = $energyStorage[($db[2] & 0x30) >> 4];
      if (!exists($hash->{helper}{lastAlarm}) || $hash->{helper}{lastAlarm} ne $alarm || ReadingsVal($name, 'alarm', '') eq 'dead_sensor') {
        push @event, "3:alarm:" . $alarm;
      }
      push @event, "3:presence:" . $presence[($db[2] & 0xC0) >> 6];
      if (!exists($hash->{helper}{lastBattery}) || $hash->{helper}{lastBattery} ne $battery) {
        push @event, "3:battery:" . $battery;
      }
      my $activity;
      my $pirCounterCurrentTel = hex(substr($data, 2, 4));
      my $pirCounter;
      if (!exists($hash->{helper}{pirCounterLastTel}) || !exists($hash->{helper}{arrivalPreviousTelegram})) {
        $activity = 0;
      } else {
        if ($hash->{helper}{pirCounterLastTel} > $pirCounterCurrentTel) {
          # roll-over
          $pirCounter = 0xFFFF - $hash->{helper}{pirCounterLastTel} + $pirCounterCurrentTel;
        } else {
           $pirCounter = $pirCounterCurrentTel - $hash->{helper}{pirCounterLastTel};
        }
        $activity = $pirCounter / (gettimeofday() - $hash->{helper}{arrivalPreviousTelegram}) / (($db[2] & 0x0F) + 1);
      }
      push @event, "3:activity:" . $activity;
      push @event, "3:state:" . $activity;
      $hash->{helper}{arrivalPreviousTelegram} = gettimeofday();
      $hash->{helper}{lastAlarm} = $alarm;
      $hash->{helper}{lastBattery} = $battery;
      $hash->{helper}{pirCounterLastTel} = $pirCounterCurrentTel;
      RemoveInternalTimer($hash->{helper}{timer}{alarm}) if (exists $hash->{helper}{timer}{alarm});
      @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
      InternalTimer(gettimeofday() + 4320, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);
#####

    } elsif ($st eq "multiFuncSensor.30") {
      # Sensor for Smoke, Air quality, Hygrothermal comfort, Temperature and Humidity
      # (D2-14-30)
      my @airQuality = ('optimal', 'air_dry', 'humidity_high', 'temperature_humidity_high', '', '', 'error');
      my @comfort = ('good', 'medium', 'bad', 'error');
      my @energyStorage = ('ok', 'medium', 'low', 'critical');
      my $alarm = ($db[5] & 0x80) == 0 ? 'off' : 'smoke-alarm';
      my $battery = $energyStorage[($db[4] & 6) >> 1];
      if (!exists($hash->{helper}{lastAlarm}) || $hash->{helper}{lastAlarm} ne $alarm || ReadingsVal($name, 'alarm', '') eq 'dead_sensor') {
        push @event, "3:alarm:" . $alarm;
      }
      if (!exists($hash->{helper}{lastBattery}) || $hash->{helper}{lastBattery} ne $battery) {
        push @event, "3:battery:" . $battery;
      }
      push @event, "3:sensorFaultMode:" . (($db[5] & 0x40) == 0 ? 'off' : 'on');
      push @event, "3:smokeAlarmMaintenance:" . (($db[5] & 0x20) == 0 ? 'ok' : 'not_done');
      push @event, "3:smokeAlarmHumidity:" . (($db[5] & 0x10) == 0 ? 'ok' : 'not_ok');
      push @event, "3:smokeAlarmTemperature:" . (($db[5] & 8) == 0 ? 'ok' : 'not_ok');
      push @event, "3:maintenanceLast:" . (($db[5] & 7) << 5 | $db[4] >> 3);
      push @event, "3:endOffLife:" . (($db[4] & 1) << 7 | $db[3] >> 1);
      push @event, "3:temperature:" . sprintf "%0.1f", (($db[3] & 1) << 7 | $db[2] >> 1) / 5;
      push @event, "3:humidity:" . sprintf "%0.1f", (($db[2] & 1) << 7 | $db[1] >> 1) / 2;
      push @event, "3:hygrothermalComfort:" . $comfort[(($db[1] & 1) << 1 | $db[0] >> 7)];
      push @event, "3:airQuality:" . $airQuality[($db[0] & 0x70) >> 4];
      push @event, "3:state:" . $alarm;
      $hash->{helper}{lastAlarm} = $alarm;
      $hash->{helper}{lastBattery} = $battery;
      RemoveInternalTimer($hash->{helper}{timer}{alarm}) if (exists $hash->{helper}{timer}{alarm});
      @{$hash->{helper}{timer}{alarm}} = ($hash, 'alarm', 'dead_sensor', 1, 5);
      InternalTimer(gettimeofday() + 1440, 'EnOcean_readingsSingleUpdate', $hash->{helper}{timer}{alarm}, 0);

    } elsif ($st eq "fanCtrl.00") {
      # Fan Control
      # (D2-20-00 - D2-20-02)
      if ($db[3] & 1) {
        # fan status message
        my $fanSpeed = $db[0];
        my $humidity = $db[1];
        my $roomSize = $db[2] & 15;
        my $roomSizeRef = ($db[2] & 0x30) >> 4;
        my $humidityCtrl = ($db[2] & 0xC0) >> 6;
        my $serviceInfo = ($db[3] & 14) >> 1;
        my $opMode = ($db[3] & 0xF0) >> 4;
        my %roomSizeTbl = (
           0 => 25,
           1 => 50,
           2 => 75,
           3 => 100,
           4 => 125,
           5 => 150,
           6 => 175,
           7 => 200,
           8 => 225,
           9 => 250,
          10 => 275,
          11 => 300,
          12 => 325,
          13 => 350,
          14 => "max",
          15 => "no_change"
        );
        if ($opMode == 0) {
          push @event, "3:state:off";
        } elsif ($opMode == 1) {
          push @event, "3:state:on";
        } elsif ($opMode == 15) {
          push @event, "3:state:not_supported";
        }
        if ($serviceInfo == 0) {
          push @event, "3:error:ok";
        } elsif ($serviceInfo == 1) {
          push @event, "3:error:air_filter";
        } elsif ($serviceInfo == 2) {
          push @event, "3:error:hardware";
        } elsif ($serviceInfo == 7) {
          push @event, "3:error:not_supported";
        }
        if ($humidityCtrl == 0) {
          push @event, "3:humidityCtrl:disabled";
        } elsif ($humidityCtrl == 1) {
          push @event, "3:humidityCtrl:enabled";
        } elsif ($humidityCtrl == 3) {
          push @event, "3:humidityCtrl:not_supported";
        }
        if ($roomSizeRef == 0) {
          push @event, "3:roomSizeRef:used";
        } elsif ($roomSizeRef == 1) {
          push @event, "3:roomSizeRef:not_used";
        } elsif ($roomSizeRef == 3) {
          push @event, "3:roomSizeRef:not_supported";
        }
        if ($roomSize < 15) {
          push @event, "3:roomSize:" . $roomSizeTbl{$roomSize};
        }
        if ($humidity >= 0 && $humidity <= 100) {
          push @event, "3:humidity:$humidity";
        } elsif ($humidity == 255) {
          push @event, "3:humidity:not_supported";
        }
        if ($fanSpeed >= 0 && $fanSpeed <= 100) {
          push @event, "3:fanSpeed:$fanSpeed";
        } elsif ($fanSpeed == 255) {
          push @event, "3:fanSpeed:not_supported";
        }
      }

    } elsif ($st eq "currentClamp.00") {
      # AC current clamp (EEP D2-32-00)
      if ($db[2] & 0x80) {
        # power fail
        push @event, "3:current1:0";
        push @event, "3:state:I1: 0";
      } else {
        my $current1 = hex(substr($data, 2, 3));
        if ($db[2] & 0x40) {
          # divisor = 1/10
          $current1 = $current1 / 10;
          push @event, "3:current1:" . sprintf "%0.1f", $current1;
          push @event, "3:state:I1: " . sprintf "%0.1f", $current1;
        } else {
          push @event, "3:current1:" . $current1;
          push @event, "3:state:I1: " . $current1;
        }
      }

    } elsif ($st eq "currentClamp.01") {
      # AC current clamp (EEP D2-32-01)
      if ($db[3] & 0x80) {
        # power fail
        push @event, "3:current1:0";
        push @event, "3:current2:0";
        push @event, "3:state:I1: 0 I2: 0";
      } else {
        my $current1 = hex(substr($data, 2, 3));
        my $current2 = hex(substr($data, 5, 3));
        if ($db[3] & 0x40) {
          # divisor = 1/10
          $current1 = $current1 / 10;
          $current2 = $current2 / 10;
          push @event, "3:current1:" . sprintf "%0.1f", $current1;
          push @event, "3:current2:" . sprintf "%0.1f", $current2;
          push @event, "3:state:I1: " . sprintf("%0.1f", $current1) . " I2: " . sprintf("%0.1f", $current2);
        } else {
          push @event, "3:current1:" . $current1;
          push @event, "3:current2:" . $current2;
          push @event, "3:state:I1: $current1 I2: $current2";
        }
      }

    } elsif ($st eq "currentClamp.02") {
      # AC current clamp (EEP D2-32-02)
      if ($db[5] & 0x80) {
        # power fail
        push @event, "3:current1:0";
        push @event, "3:current2:0";
        push @event, "3:current3:0";
        push @event, "3:state:I1: 0 I2: 0 I3: 0";
      } else {
        my $current1 = hex(substr($data, 2, 3));
        my $current2 = hex(substr($data, 5, 3));
        my $current3 = hex(substr($data, 8, 3));
        if ($db[5] & 0x40) {
          # divisor = 1/10
          $current1 = $current1 / 10;
          $current2 = $current2 / 10;
          $current3 = $current3 / 10;
          push @event, "3:current1:" . sprintf "%0.1f", $current1;
          push @event, "3:current2:" . sprintf "%0.1f", $current2;
          push @event, "3:current3:" . sprintf "%0.1f", $current3;
          push @event, "3:state:I1: " . sprintf("%0.1f", $current1) . " I2: " . sprintf("%0.1f", $current2) . " I3: " . sprintf("%0.1f", $current3);
        } else {
          push @event, "3:current1:" . $current1;
          push @event, "3:current2:" . $current2;
          push @event, "3:current3:" . $current3;
          push @event, "3:state:I1: $current1 I2: $current2 I3: $current3";
        }
      }

    } elsif ($st eq "heatingActuator.00") {
      # Heating Actuator
      # (D2-34-00 - D2-34-02)
      my ($channel, $cmd) = (undef, $db[0] & 0x0F);
      if ($cmd == 4) {
        # actuator status response
        $channel = ((hex substr($data, 4, 4)) & 0x03E0) >> 5;
        my @operationMode = ('off', 'temperature_unknown', 'no_heating', 'heating');
        if ($channel == 30) {
          $channel = "All";
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name operationMode.*");
          CommandDeleteReading(undef, "$name overridePeriod.*");
          CommandDeleteReading(undef, "$name setpointTemp.*");
          CommandDeleteReading(undef, "$name setpointTempRefDev.*");
          CommandDeleteReading(undef, "$name setpointTempShift.*");
        }
        push @event, "3:temperature" . $channel . ":" . sprintf("%0.1f", (((hex(substr($data, 0, 4))) & 0xFF80) >> 7) / 10);
        push @event, "3:setpointTemp" . $channel . ":" . sprintf("%0.1f", (((hex(substr($data, 2, 4))) & 0x7FC0) >> 6) / 10);
        push @event, "3:operationMode" . $channel . ":" . $operationMode[($db[1] & 0x3C) >> 2];
        push @event, "3:state:" . $channel . ': ' . $operationMode[($db[1] & 0x3C) >> 2];

      } elsif ($cmd == 7) {
        # actuator setpoint response
        $channel = ($db[1] & 0x7C) >> 2;
        my @channel = ('setpointTempRefDev', 'setpointTemp', 'setpointTempShift', 'setpointTempShift');
        if ($channel == 30) {
          $channel = "All";
          CommandDeleteReading(undef, "$name channel.*");
          CommandDeleteReading(undef, "$name operationMode.*");
          CommandDeleteReading(undef, "$name overridePeriod.*");
          CommandDeleteReading(undef, "$name setpointTemp.*");
          CommandDeleteReading(undef, "$name setpointTempRefDev.*");
          CommandDeleteReading(undef, "$name setpointTempShift.*");
        }
        push @event, "3:channel" . $channel . ":" . $channel[($db[5] & 0xC0) >> 6];
        push @event, "3:overridePeriod" . $channel . ":" . ($db[5] & 0x3F);
        push @event, "3:setpointTempRefDev" . $channel . ":" . sprintf("%0.1f", (((hex(substr($data, 2, 4))) & 0xFF80) >> 7) / 10);
        push @event, "3:setpointTempShift" . $channel . ":" . sprintf("%0.1f", ($db[3] & 0x7F) / 10 * ((($db[5] & 0xC0) >> 6) == 3 ? -1 : 1));
        push @event, "3:setpointTemp" . $channel . ":" . sprintf("%0.1f", (((hex(substr($data, 6, 4))) & 0xFF80) >> 7) / 10);

      } else {
        # unknown response
      }

    } elsif ($st eq "ledCtrlState.00") {
      # LED Controller Status (EEP D2-40-00)
      if ($db[1] & 0x80) {
        # powerSwitch
        push @event, "3:powerSwitch:on";
        push @event, "3:state:on";
      } else {
        push @event, "3:powerSwitch:off";
        push @event, "3:state:off";
      }
      if ($db[1] & 0x40) {
        # Demand Response Mode
        push @event, "3:demandResp:on";
      } else {
        push @event, "3:demandResp:off";
      }
      if ($db[1] & 0x20) {
        # Daylight Harvesting
        push @event, "3:daylightHarvesting:on";
      } else {
        push @event, "3:daylightHarvesting:off";
      }
      my $occupancy = ($db[1] & 0x18) >> 3;
      if ($occupancy == 0) {
        push @event, "3:occupany:unoccupied";
      } elsif ($occupancy == 1) {
        push @event, "3:occupany:occupied";
      } else {
        push @event, "3:occupany:unknown";
      }
      push @event, "3:telegramType:" . ($db[1] & 4 ? "event" : "heartbeat");
      if ($db[0] >= 0 && $db[0] <= 200) {
        push @event, "3:dim:" . sprintf "%0.1f", $db[0] / 2;
      }

    } elsif ($st eq "ledCtrlState.01") {
      # LED Controller Status (EEP D2-40-01)
      if ($db[3] & 0x80) {
        # powerSwitch
        push @event, "3:powerSwitch:on";
        push @event, "3:state:on";
      } else {
        push @event, "3:powerSwitch:off";
        push @event, "3:state:off";
      }
      if ($db[3] & 0x40) {
        # Demand Response Mode
        push @event, "3:demandResp:on";
      } else {
        push @event, "3:demandResp:off";
      }
      if ($db[3] & 0x20) {
        # Daylight Harvesting
        push @event, "3:daylightHarvesting:on";
      } else {
        push @event, "3:daylightHarvesting:off";
      }
      my $occupancy = ($db[3] & 0x18) >> 3;
      if ($occupancy == 0) {
        push @event, "3:occupany:unoccupied";
      } elsif ($occupancy == 1) {
        push @event, "3:occupany:occupied";
      } else {
        push @event, "3:occupany:unknown";
      }
      push @event, "3:telegramType:" . ($db[3] & 4 ? "event" : "heartbeat");
      my ($red, $green, $blue) = ('00', '00', '00');
      if ($db[2] >= 0 && $db[2] <= 200) {
        push @event, "3:red:" . sprintf "%0.1f", $db[2] / 2;
        $red = sprintf "%02X", abs($db[2] / 200 * 255);
      }
      if ($db[1] >= 0 && $db[1] <= 200) {
        push @event, "3:green:" . sprintf "%0.1f", $db[1] / 2;
        $green = sprintf "%02X", abs($db[1] / 200 * 255);
      }
      if ($db[0] >= 0 && $db[0] <= 200) {
        push @event, "3:blue:" . sprintf "%0.1f", $db[0] / 2;
        $blue = sprintf "%02X", abs($db[0] / 200 * 255);
      }
      push @event, "3:rgb:" . $red . $green . $blue;

    } elsif ($st eq "heatRecovery.00") {
      # heat recovery ventilation
      # (D2-50-00)
      my $msgType = hex(substr($data, 0, 1)) >> 1;
      if ($msgType == 2) {
        my $ventilation = 'unknown';
        my %ventilation = (
          0 => "off",
          1 => 1,
          2 => 2,
          3 => 3,
          4 => 4,
          11 => "auto",
          12 => "demand",
          13 => "supplyAir",
          14 => "exhaustAir"
        );
        $ventilation = $db[13] & 15;
        $ventilation = $ventilation{$ventilation} if (exists $ventilation{$ventilation});
        push @event, "3:ventilation:$ventilation";
        push @event, "3:fireplaceSafetyMode:" . ($db[12] & 8 ? 'enabled' : 'disabled');
        push @event, "3:heatExchangerBypass:" . ($db[12] & 4 ? 'opened' : 'closed');
        push @event, "3:supplyAirFlap:" . ($db[12] & 2 ? 'opened' : 'closed');
        push @event, "3:exhaustAirFlap:" . ($db[12] & 1 ? 'opened' : 'closed');
        push @event, "3:defrost:" . ($db[11] & 0x80 ? 'on' : 'off');
        push @event, "3:coolingProtection:" . ($db[11] & 0x40 ? 'on' : 'off');
        push @event, "3:outdoorAirHeater:" . ($db[11] & 0x20 ? 'on' : 'off');
        push @event, "3:supplyAirHeater:" . ($db[11] & 0x10 ? 'on' : 'off');
        push @event, "3:drainHeater:" . ($db[11] & 8 ? 'on' : 'off');
        push @event, "3:timerMode:" . ($db[11] & 4 ? 'on' : 'off');
        push @event, "3:filterMaintenance:" . ($db[11] & 2 ? 'required' : 'not_required');
        push @event, "3:weeklyTimer:" . ($db[11] & 1 ? 'on' : 'off');
        push @event, "3:roomTempCtrl:" . ($db[10] & 0x80 ? 'on' : 'off');
        my $airQuatity = $db[10] & 0x7F;
        if ($airQuatity <= 100) {
          push @event, "3:airQuality1:$airQuatity";
        } else {
          CommandDeleteReading(undef, "$name airQuality1");
        }
        push @event, "3:deviceMode:" . ($db[9] & 0x80 ? 'slave' : 'master');
        $airQuatity = $db[9] & 0x7F;
        if ($airQuatity <= 100) {
          push @event, "3:airQuality2:$airQuatity";
        } else {
          CommandDeleteReading(undef, "$name airQuality2");
        }
        my $outdoorTemp = ($db[8] & 0xFE) >> 1;
        #$outdoorTemp -= $outdoorTemp if ($outdoorTemp & 0x40);
        $outdoorTemp -= 64;
        push @event, "3:outdoorTemp:$outdoorTemp";
        my $supplyTemp = ($db[8] & 1) << 6 | ($db[7] & 0xFC) >> 2;
        #$supplyTemp -= $supplyTemp if ($supplyTemp & 0x40);
        $supplyTemp -= 64;
        push @event, "3:supplyTemp:$supplyTemp";
        my $roomTemp = ($db[7] & 3) << 5 | ($db[6] & 0xF8) >> 3;
        #$roomTemp -= $roomTemp if ($roomTemp & 0x40);
        $roomTemp -= 64;
        push @event, "3:roomTemp:$roomTemp";
        my $exhaustTemp = ($db[6] & 7) << 4 | ($db[5] & 0xF0) >> 4;
        #$exhaustTemp -= $exhaustTemp if ($exhaustTemp & 0x40);
        $exhaustTemp -= 64;
        push @event, "3:exhaustTemp:$exhaustTemp";
        push @event, "3:supplyAirFlow:". (($db[5] & 0x0F) << 2 | ($db[4] & 0xFC) >> 2);
        push @event, "3:exhaustAirFlow:" . (($db[4] & 3) << 8 | $db[3]);
        push @event, "3:supplyFanSpeed:". ($db[2] << 4 | ($db[1] & 0xF0) >> 4);
        push @event, "3:exhaustFanSpeed:" . (($db[1] & 0x0F) << 8 | $db[0]);
        push @event, "3:state:$ventilation";

      } elsif ($msgType == 3) {
        push @event, "3:SWVersion:" . (($db[13] & 0x0F) << 8 | $db[12]);
        push @event, "3:operationHours:" . (($db[11] << 8 | $db[10]) * 3);
        push @event, "3:input:" . sprintf("%02b %02b", $db[9], $db[8]);
        push @event, "3:output:" . sprintf("%02b %02b", $db[7], $db[6]);
        push @event, "3:info:" . sprintf("%02b %02b", $db[5], $db[4]);
        push @event, "3:fault:" . sprintf("%02b %02b %02b %02b", $db[3], $db[2], $db[1], $db[0]);

      }

    } elsif ($st eq "valveCtrl.00") {
      # Valve Control
      # (D2-A0-01)
      $db[0] &= 3;
      if (AttrVal($name, "devMode", "master") eq "slave") {
        # devMode slave
        if ($db[0] == 1 || $db[0] == 3) {
          push @event, "3:state:closes";
        } elsif ($db[0] == 2) {
          push @event, "3:state:opens";
        } elsif ($db[0] == 0) {
          my $state = ReadingsVal($name, "state", "-");
          if ($state eq "closed" || $state eq "closes") {
            $state = "01";
          } elsif ($state eq "open" || $state eq "opens") {
            $state = "02";
          } else {
            $state = "00";
          }
          EnOcean_SndRadio(undef, $hash, 1, "D2", $state, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
        }
      } else {
        #devMode master
        if ($db[0] == 1) {
          push @event, "3:state:closed";
        } elsif ($db[0] == 2) {
          push @event, "3:state:open";
        } elsif ($db[0] == 0 || $db[0] == 3) {
          push @event, "3:state:-";
        }
      }

    } elsif ($st eq "liquidLeakage.51") {
      # liquid leakage sensor
      push @event, "3:state:" . $db[0] & 3 ? 'wet' : 'dry';

    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";
      # display data bytes $db[0] ... $db[x]
      for (my $dbCntr = 0; $dbCntr <= $#db; $dbCntr++) {
        push @event, "3:DB_" . $dbCntr . ":" . $db[$dbCntr];
      }

    } else {
      # unknown devices
      push @event, "3:state:$data";
    }

  } elsif ($rorg eq "D1") {
    # MSC telegram
    if ($st eq "actuator.01") {
      if ($manufID eq "033") {
        if (substr($data, 3, 1) == 4) {
          my $getParam = ReadingsVal($name, "getParam", 0);
          if ($getParam == 8) {
            push @event, "3:loadClassification:no";
            push @event, "3:loadLink:" . ($db[1] & 16 ? "connected" : "disconnected");
            push @event, "3:loadOperation:3-wire";
            push @event, "3:loadState:" . ($db[1] & 64 ? "on" : "off");
            CommandDeleteReading(undef, "$name getParam");
          } elsif ($getParam == 7) {
            if ($db[0] & 4) {
              push @event, "3:devTempState:warning";
            } elsif ($db[0] & 2) {
              push @event, "3:devTempState:max";
            } else {
              push @event, "3:devTempState:ok";
            }
            push @event, "3:mainsPower:" . ($db[0] & 8 ? "failure" : "ok");
            if ($db[1] == 0xFF) {
              push @event, "3:devTemp:invalid";
            } else {
              push @event, "3:devTemp:" . $db[1];
            }
            CommandDeleteReading(undef, "$name getParam");
          } elsif ($getParam == 9) {
            push @event, "3:voltage:" . sprintf("%.2f", (hex(substr($data, 4, 4)) * 0.01));
            CommandDeleteReading(undef, "$name getParam");
          } elsif ($getParam == 0x81) {
            $hash->{READINGS}{serialNumber}{VAL} = substr($data, 4, 4);
            $hash->{READINGS}{getParam}{VAL} = 0x82;
            EnOcean_SndRadio(undef, $hash, $packetType, "D1", "033182", AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
          } elsif ($getParam == 0x82) {
            push @event, "3:serialNumber:" . $hash->{READINGS}{serialNumber}{VAL} . substr($data, 4, 4);
            CommandDeleteReading(undef, "$name getParam");
          }
        }
      } elsif ($manufID eq "046") {
        my $cmd = hex(substr($data, 4, 2));
        if ($cmd == 3) {
          push @event, "3:firmwareVersion:" . substr($data, 6, 6);
        } elsif ($cmd == 5) {
          push @event, "3:taughtInDevNum:$db[0]";
        } elsif ($cmd == 7) {
          CommandDeleteReading(undef, "$name taughtInDevID.*");
          push @event, "3:taughtInDevID" . sprintf('%02d', $db[4]) . ":" . substr($data, 8, 8);
        }
      }

    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";
      push @event, "3:manufID:" . substr($data, 0, 3);
      # display data bytes $db[0] ... $db[x]
      for (my $dbCntr = 0; $dbCntr <= $#db; $dbCntr++) {
        push @event, "3:DB_" . $dbCntr . ":" . $db[$dbCntr];
      }
    } else {
      # unknown devices
      if(AttrVal($name, "blockUnknownMSC", "no") eq "yes") {
        push @event, "3:MSC:$data";
      }
    }

  } elsif ($rorg eq "D0") {
    # Signal Telegram
    my $signalMID = hex(substr($data, 0, 2));
    if ($signalMID == 1) {
      push @event, "3:smartAckMailbox:empty";
    } elsif ($signalMID == 2) {
      push @event, "3:smartAckMailbox:not_exits";
    } elsif ($signalMID == 3) {
      push @event, "3:smartAckMailbox:reset";
    } elsif ($signalMID == 4) {
      my $responseID = $subDef eq $hash->{DEF} ? $iohash->{ChipID} : $subDef;
      if ($db[0] == 0) {
      } elsif ($db[0] == 1) {
        # send MID 0x06
        EnOcean_SndRadio(undef, $hash, 1, 'D0', '0664', $responseID, '00', 'F' x 8);
      } elsif ($db[0] == 2) {
        # send MID 0x07
        my $swVersion = sprintf("%s", AttrVal('global', 'featurelevel', '99.99')) . '.00.00';
        #my @revision = split(/\./, $swVersion);
        $swVersion =~ /^(.*)\.(.*)\.(..)\.(..)$/;
        EnOcean_SndRadio(undef, $hash, 1, 'D0', sprintf("07%02X%02X%02X%02X00000000", $1, $2, $3, $4), $responseID, '00', 'F' x 8);
      } elsif ($db[0] == 3) {
        # send MID 0x0A
        if (exists($hash->{LASTInputDev}) && exists($hash->{"$hash->{LASTInputDev}_RSSI"}) &&
            exists($hash->{"$hash->{LASTInputDev}_RepeatingCounter"}) && exists($hash->{"$hash->{LASTInputDev}_SubTelNum"})) {
            my $data = '0A' . $iohash->{ChipID} . sprintf("%02X%02X%01X%01X", 127 - $hash->{"$hash->{LASTInputDev}_RSSI"},
                                                                              127 - $hash->{"$hash->{LASTInputDev}_RSSI"},
                                                                              $hash->{"$hash->{LASTInputDev}_SubTelNum"},
                                                                              $hash->{"$hash->{LASTInputDev}_RepeatingCounter"});
          EnOcean_SndRadio(undef, $hash, 1, 'D0', $data, $responseID, '00', 'F' x 8);
        }
      } elsif ($db[0] == 4) {
        # send MID 0x0D
        EnOcean_SndRadio(undef, $hash, 1, 'D0', '0D00', $responseID, '00', 'F' x 8);
      }
    } elsif ($signalMID == 5) {
      $hash->{Dev_ACK} = 'signal';
      DoTrigger($name, "SIGNAL: Dev_ACK", 1);
    } elsif ($signalMID == 6) {
      push @event, "3:batteryPercent:$db[0]";
    } elsif ($signalMID == 7) {
      push @event, "3:hwVersion:" . substr($data, 10, 8);
      push @event, "3:swVersion:" . substr($data, 2, 8);
    } elsif ($signalMID == 8) {
      push @event, "3:trigger:heartbeat";
    } elsif ($signalMID == 9) {
      DoTrigger($name, "SIGNAL: RX_WINDOW_OPEN", 1);
    } elsif ($signalMID == 10) {
      $hash->{Dev_EURID} = substr($data, 2, 8);
      if ($db[1] < 255) {$hash->{Dev_RSSImax} = 127 - $db[1]};
      if ($db[2] < 255) {$hash->{Dev_RSSImin} = 127 - $db[2]};
      my $subTelNum = $db[0] >> 4;
      if ($subTelNum > 0) {$hash->{Dev_SubTelNum} = $subTelNum};
      my $repeatingCounter = $db[0] & 0x0F;
      if ($repeatingCounter < 0x0F) {$hash->{Dev_RepeatingCounter} = $repeatingCounter};
    } elsif ($signalMID == 11) {
      DoTrigger($name, "SIGNAL: DUTYCYCLE_LIMIT: " . ($db[0] >> 4 == 1 ? 'released' : 'reached'), 1);
      Log3 $name, 2, "EnOcean $name SIGNAL DUTYCYCLE_LIMIT: " . ($db[0] >> 4 == 1 ? 'released' : 'reached');
    } elsif ($signalMID == 12) {
      DoTrigger($name, "SIGNAL: Dev_CHANGED", 1);
      Log3 $name, 2, "EnOcean $name SIGNAL Dev_CHANGED";
    } elsif ($signalMID == 13) {
      my @harvester = ('very_good', 'good', 'average', 'bad', 'very_bad');
      push @event, "3:harvester:" . $harvester[$db[0]];
    }

  } elsif ($rorg eq "B2") {
    # GP complete data (GPCD)
    my ($channel, $channelName, $value, $gpDef, $resolution) = (0, undef, undef, AttrVal($name, 'gpDef', undef), undef);
    return "generic profil not defined" if (!defined $gpDef);
    my @gpDef = split("[ \t][ \t]*", $gpDef);
    my ($readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType);
    $data = EnOcean_convHexToBit($data);

    while (defined $gpDef[$channel]) {
      ($channelName, undef, undef, undef, undef, $resolution, undef, undef, undef, undef) = split(':', $gpDef[$channel]);
      $resolution = 0 if (!defined $resolution);
      $data =~ m/^(.{$EnO_resolution[$resolution]})(.*)$/;
      $value = hex(unpack('H8', pack('B32', '0' x (32 - $EnO_resolution[$resolution]) . $1)));
      $data = $2;
      ($err, $logLevel, $response, $readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType)=
        EnOcean_gpConvDataToValue (undef, $hash, $channel, $value, $gpDef[$channel]);
      $channel ++;
      next if (defined $err);
      push @event, "3:$readingName:" . sprintf("$readingFormat", $readingValue);
      push @event, "3:" . $readingName . "Unit:$readingUnit";
      push @event, "3:" . $readingName . "ValueType:$valueType";
      push @event, "3:" . $readingName . "ChannelType:$readingType";
    }

  } elsif ($rorg eq "B3") {
    # GP selective data (GPSD)
    my $gpDef = AttrVal($name, "gpDef", undef);
    return "generic profil not defined" if (!defined $gpDef);
    my @gpDef = split("[ \t][ \t]*", $gpDef);
    my ($channel, $channelName, $resolution, $value);
    my ($readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType);
    #Log3 $name, 2, "EnOcean $name parse GPSD data: $data start";
    $data =~ m/^(.)(.*)$/;
    my $header = hex $1;
    $data = substr(EnOcean_convHexToBit($data), 4);
    #Log3 $name, 2, "EnOcean $name parse GPSD header: $header data: $data start";

    for (my $cntr = 1; $cntr <= $header; $cntr ++) {
      $data =~ m/^(.{6})(.*)$/;
      ($channel, $data) = (unpack('C', pack('B8', '00' . $1)), $2);
      #Log3 $name, 2, "EnOcean $name parse GPSD channel: $channel data: $data";
      if (defined $gpDef[$channel]) {
        ($channelName, undef, undef, undef, undef, $resolution, undef, undef, undef, undef) = split(':', $gpDef[$channel]);
        $resolution = 0 if (!defined $resolution || $resolution eq '');
        $data =~ m/^(.{$EnO_resolution[$resolution]})(.*)$/;
        $value = hex(unpack('H8', pack('B32', '0' x (32 - $EnO_resolution[$resolution]) . $1)));
        $data = $2;
        #Log3 $name, 2, "EnOcean $name parse GPSD channel: $channel value: " . $value . " data: $data";
        ($err, $logLevel, $response, $readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType) =
          EnOcean_gpConvDataToValue(undef, $hash, $channel, $value, $gpDef[$channel]);
        push @event, "3:$readingName:" . sprintf("$readingFormat", $readingValue);
        push @event, "3:" . $readingName . "Unit:$readingUnit";
        push @event, "3:" . $readingName . "ValueType:$valueType";
        push @event, "3:" . $readingName . "ChannelType:$readingType";
      }
    }

  } elsif ($rorg eq "B0" && $teach) {
    # GP teach in request (GPTI)
    #
    $data =~ m/^(....)(.*)$/;
    my $header = hex($1);
    $data = $2;
    my $purpose = ($header & 12) >> 2;
    if ($purpose == 0 || ($purpose == 2 && AttrVal($name, "subType", "") ne "genericProfile")) {
      # teach-in request
      $attr{$name}{comMode} = $header & 16 ? "biDir" : "uniDir";
      $attr{$name}{eep} = "B0-00-00";
      $attr{$name}{manufID} = sprintf "%03X", ($header & 0xFFE0) >> 5;
      $attr{$name}{subType} = "genericProfile";
      $attr{$name}{teachMethod} = 'GP';
      my $channel = 0;
      my $channelDir = "I";
      my $channelDef;
      my $channelName;
      my $channelType;
      my $cntr = 0;
      my $teachInDataLen = 0;
      my @gpDef;
      my $signalType;
      #Log3 $name, 2, "EnOcean $name parse GPTI header: $header data: $data start";
      $data = EnOcean_convHexToBit($data);
      #Log3 $name, 2, "EnOcean $name parse GPTI data: $data start";
      while (length($data) >= 12) {
        last if ($cntr > 64);
        $cntr ++;
        $data =~ m/^(..)(.*)$/;
        $channelType = unpack('C', pack('B8', '000000' . $1));
        $data = $2;
        if ($channelType == 0) {
          # GP definition
          # V1.0: teach-in signal type length S1 = 8 bit?
          # V1.1: teach-in signal type length S1 = 6 bit?
          $data =~ m/^(.{8})(.*)$/;
          $signalType =  unpack('C', pack('B8', $1));
          #$data =~ m/^(.{6})(.*)$/;
          #$signalType =  unpack('C', pack('B8', '00' . $1));
          $data = $2;
        } else {
          $data =~ m/^(.{8})(.*)$/;
          $signalType =  unpack('C', pack('B8', $1));
          $data = $2;
        }
        #Log3 $name, 2, "EnOcean $name parse GPTI channel: $channel channelType: $channelType signalType: $signalType data: $data";

        if ($channelType == 0) {
          # teach-in information
          $data =~ m/^(.{8})(.*)$/;
          $teachInDataLen = unpack('C', pack('B8', $1)) * 8;
          $data = $2;
          if ($signalType == 1) {
            # outbound channels description following
            $channelDir = "O";
          } elsif ($signalType == 2) {
            # produkt ID
            $data =~ m/^(.{$teachInDataLen})(.*)$/;
            $attr{$name}{productID} = EnOcean_convBitToHex($1);
            $data = $2;
          } elsif ($signalType == 3) {
#####
            # Connected GSI Sensor IDs
            my $gsiIdDataLen =  $teachInDataLen - 16;
            $data =~ m/^(.{8})(.{8})(.{$gsiIdDataLen})(.*)$/;
            $attr{$name}{gsiSocket} = unpack('C', pack('B8', $1));
            my ($sensors, $gsiIdData) = (unpack('C', pack('B8', $2)), $3);
            $data = $4;
            my $gsiSensorName;
            for (my $i = 0; $i <= $sensors; $i++) {
              $gsiIdData =~ m/^(.{8})(.{16})(.{24})(.*)$/;
              $gsiSensorName = sprintf "gsiSensor-%03d", $i;
              $attr{$name}{$gsiSensorName} = sprintf "%02s:%04s:%06s", EnOcean_convBitToHex($1), EnOcean_convBitToHex($2), EnOcean_convBitToHex($3);
              $gsiIdData = $4;
            }
          } else {
            if ($teachInDataLen == 0) {
              Log3 $name, 2, "EnOcean $name parse GPTI teach-in info signalType: $signalType not supported";
            } else {
              $data =~ m/^(.{$teachInDataLen})(.*)$/;
              Log3 $name, 2, "EnOcean $name parse GPTI teach-in info signalType: $signalType data: " . EnOcean_convBitToHex($1) . " not supported";
              $data = $2;
            }
          }

        } elsif ($channelType == 1) {
          # data
          $data =~ m/^(..)(....)(.{8})(....)(.{8})(....)(.*)$/;
          $channelDef = $channelDir . ':' . $channelType . ':' . $signalType . ':' .
                        unpack('C', pack('B8', '000000' . $1)) . ':' . unpack('C', pack('B8', '0000' . $2)) . ':' .
                        unpack('c', pack('B8', $3)) . ':' . unpack('C', pack('B8', '0000' . $4)) . ':' .
                        unpack('c', pack('B8', $5)) . ':' . unpack('C', pack('B8', '0000' . $6));
          $data = $7;
          if (defined $EnO_gpValueData{$signalType}{name}) {
            $channelName = $EnO_gpValueData{$signalType}{name};
          } else {
            $channelName = "none";
          }
          $gpDef[$channel] = $channelName . ':' . $channelDef;
          $channel ++;

        } elsif ($channelType == 2) {
          # flag
          $data =~ m/^(..)(.*)$/;
          $channelDef = $channelDir . ':' .$channelType . ':' . $signalType . ':' .
                        unpack('C', pack('B8', '000000' . $1));
          $data = $2;
          if (defined $EnO_gpValueFlag{$signalType}{name}) {
            $channelName = $EnO_gpValueFlag{$signalType}{name};
          } else {
            $channelName = "none";
          }
          $gpDef[$channel] = $channelName . ':' . $channelDef;
          $channel ++;

        } elsif ($channelType == 3) {
          # enumeration
          $data =~ m/^(..)(....)(.*)$/;
          $channelDef = $channelDir . ':' .$channelType . ':' . $signalType . ':' .
                        unpack('C', pack('B8', '000000' . $1)) . ':' . unpack('C', pack('B8', '0000' . $2));
          $data = $3;
          if (defined $EnO_gpValueEnum{$signalType}{name}) {
            $channelName = $EnO_gpValueEnum{$signalType}{name};
          } else {
            $channelName = "none";
          }
          $gpDef[$channel] = $channelName . ':' . $channelDef;
          $channel ++;
        }
      }
      $attr{$name}{gpDef} = join(' ', @gpDef);

      if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
        # send GP Teach-In Response message
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
        $data = sprintf "%04X", ((hex(AttrVal($name, "manufID", "7FF")) << 5) | 8);
        EnOcean_SndCdm(undef, $hash, $packetType, "B1", $data, $subDef, "00", $senderID);
        Log3 $name, 2, "EnOcean $name GP teach-in response sent to $senderID";
      }
      my $mid = $attr{$name}{manufID};
      $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
      push @event, "3:teach:GP teach-in accepted Manufacturer: $mid";
      Log3 $name, 2, "EnOcean $name GP teach-in accepted Manufacturer: $mid";
      # store attr subType, manufID, gpDef ...
      EnOcean_CommandSave(undef, undef);

    } elsif ($purpose == 1 || ($purpose == 2 && AttrVal($name, "subType", "") eq "genericProfile")) {
      # teach-in deletion request
      $deleteDevice = $name;
      if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
        # send GP Teach-In Deletion Response message
        $data = sprintf "%04X", (hex(AttrVal($name, "manufID", "7FF")) << 5) | 16;
        EnOcean_SndCdm(undef, $hash, $packetType, "B1", $data, AttrVal($name, "subDef", "00000000"), "00", $senderID);
        Log3 $name, 2, "EnOcean $name GP teach-in deletion response send to $senderID";
      }
      Log3 $name, 2, "EnOcean $name GP teach-in delete request executed";

    }

  } elsif ($rorg eq "B1" && $teach) {
    # GP teach-in response (GPTR)
    $data =~ m/^(....)(.*)$/;
    my $header = hex($1);
    $data = $2;
    my $mid = sprintf "%03X", ($header & 0xFFE0) >> 5;
    my $purpose = ($header & 24) >> 3;

    if (exists $hash->{IODev}{helper}{gpRespWait}{$destinationID}) {

      if ($purpose == 0) {
        # teach-in rejected generally
        if ($hash->{IODev}{helper}{gpRespWait}{$destinationID}{teachInReq} eq "in") {
          push @event, "3:teach:GP teach-in rejected";
          Log3 $name, 2, "EnOcean $name GP teach-in rejected by $senderID";
        }
        # clear teach-in request
        delete $hash->{IODev}{helper}{gpRespWait}{$destinationID};

      } elsif ($purpose == 1) {
        # teach-in accepted
        if ($hash->{IODev}{helper}{gpRespWait}{$destinationID}{teachInReq} eq "in") {
          $attr{$name}{manufID} = $mid;
          # substitute subDef with DEF
          $attr{$name}{subDef} = $hash->{DEF};
          $hash->{DEF} = $senderID;
          $modules{EnOcean}{defptr}{$senderID} = $hash;
          delete $modules{EnOcean}{defptr}{$destinationID};
          EnOcean_CommandSave(undef, undef);
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          push @event, "3:teach:GP teach-in accepted Manufacturer: $mid";
          Log3 $name, 2, "EnOcean $name GP teach-in accepted by $senderID";
        }
        # clear teach-in request
        delete $hash->{IODev}{helper}{gpRespWait}{$destinationID};

      } elsif ($purpose == 2) {
        # teach-out accepted
        if ($hash->{IODev}{helper}{gpRespWait}{$destinationID}{teachInReq} eq "out") {
          if (defined $attr{$name}{subDef}) {
            delete $modules{EnOcean}{defptr}{$hash->{DEF}};
            $hash->{DEF} = $attr{$name}{subDef};
            $modules{EnOcean}{defptr}{$hash->{DEF}} = $hash;
            delete $attr{$name}{subDef};
            EnOcean_CommandSave(undef, undef);
          }
          push @event, "3:teach:GP teach-out accepted";
          Log3 $name, 2, "EnOcean $name GP teach-out accepted";
        }
        # clear teach-in request
        delete $hash->{IODev}{helper}{gpRespWait}{$destinationID};

      } else {
        if ($hash->{IODev}{helper}{gpRespWait}{$destinationID}{teachInReq} eq "in") {
          # rejected channels outbound or inbound, sent teach-in response with teach-out
          $data = sprintf "%04X", (hex(AttrVal($name, "manufID", "7FF")) << 5) | 16;
          EnOcean_SndCdm(undef, $hash, $packetType, "B1", $data, $destinationID, "00", $senderID);
          push @event, "3:teach:GP teach-in channels rejected, sent teach-out";
          Log3 $name, 2, "EnOcean $name GP teach-in channels rejected, sent teach-out to $senderID";
        }
        # clear teach-in request
        delete $hash->{IODev}{helper}{gpRespWait}{$destinationID};

      }

    } else {
      Log3 $name, 2, "EnOcean $name GP teach-in response from $senderID received, teach-in request unknown";
    }

  } elsif ($rorg eq "D4" && $teach) {
    # UTE - Universal Uni- and Bidirectional Teach-In / Teach-Out
    #
    Log3 $name, 5, "EnOcean $name UTE teach-in received from $senderID";
    my $rorg = sprintf "%02X", $db[0];
    my $func = sprintf "%02X", $db[1];
    my $type = sprintf "%02X", $db[2];
    my $mid = sprintf "%03X", ((($db[3] & 7) << 8) | $db[4]);
    my $devChannel = $db[5];
    my $comMode = $db[6] & 0x80 ? "biDir" : "uniDir";
    my $comModeUTE = AttrVal($hash->{IODev}{NAME}, "comModeUTE", "auto");
    $comMode = $comModeUTE if ($comModeUTE ne 'auto');
    my $subType = "$rorg.$func.$type";
    if (($db[6] & 0xF) == 0) {
      # Teach-In Query telegram received
      my $teachInReq = ($db[6] & 0x30) >> 4;
      if ($teachInReq == 0 || $teachInReq == 2) {
        # Teach-In Request
        $attr{$name}{teachMethod} = 'UTE';
        if(exists $EnO_eepConfig{$subType}) {
          # Teach-In EEP supported
          foreach my $attrCntr (keys %{$EnO_eepConfig{$subType}{attr}}) {
            $attr{$name}{$attrCntr} = $EnO_eepConfig{$subType}{attr}{$attrCntr};
          }
          $attr{$name}{manufID} = $mid;
          $attr{$name}{devChannel} = $devChannel;
          $attr{$name}{comMode} = $comMode;
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          $attr{$name}{eep} = "$rorg-$func-$type";
          if (exists($hash->{helper}{teachInWait}) && $hash->{helper}{teachInWait} =~ m/^UTE|STE$/) {
            $attr{$filelogName}{logtype} = $EnO_eepConfig{$subType}{GPLOT} . 'text'
              if (exists $attr{$filelogName}{logtype});
            EnOcean_CreateSVG(undef, $hash, undef);
            delete $hash->{helper}{teachInWait};
          }
          $subType = $EnO_eepConfig{$subType}{attr}{subType};
          #$attr{$name}{subType} = $subType;
          push @event, "3:teach:UTE teach-in accepted EEP $rorg-$func-$type Manufacturer: $mid";
          if (!($db[6] & 0x40)) {
            # UTE Teach-In-Response expected
            # send UTE Teach-In Response message
            $data = (sprintf "%02X", $db[6] & 0x80 | 0x11) . substr($data, 2, 12);
            if ($comMode eq "biDir") {
              ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", $comMode);
            } else {
              $subDef = "00000000";
            }
            EnOcean_SndRadio(undef, $hash, $packetType, "D4", $data, $subDef, "00", $senderID);
            Log3 $name, 2, "EnOcean $name UTE teach-in response send to $senderID";
          }
          Log3 $name, 2, "EnOcean $name UTE teach-in accepted EEP $rorg-$func-$type Manufacturer: $mid";
        } else {
          # Teach-In EEP not supported
          $attr{$name}{subType} = "raw";
          $attr{$name}{manufID} = $mid;
          $attr{$name}{devChannel} = $devChannel;
          $attr{$name}{comMode} = $comMode;
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          push @event, "3:teach:UTE teach-in accepted EEP $rorg-$func-$type not supported Manufacturer: $mid";
          # send EEP Teach-In Response message
          if (!($db[6] & 0x40)) {
            # UTE Teach-In-Response expected
	    # send UTE Teach-In Response message
            $data = (sprintf "%02X", $db[6] & 0x80 | 0x31) . substr($data, 2, 12);
            EnOcean_SndRadio(undef, $hash, $packetType, "D4", $data, "00000000", "00", $senderID);
            Log3 $name, 2, "EnOcean $name UTE teach-in response send to $senderID";
          }
          Log3 $name, 2, "EnOcean $name UTE teach-in accepted EEP $rorg-$func-$type not supported Manufacturer: $mid";
        }
        # store attr subType, manufID ...
        EnOcean_CommandSave(undef, undef);

      } elsif ($teachInReq == 1) {
        # Teach-In Deletion Request
        $deleteDevice = $name;
        if (!($db[6] & 0x40)) {
          # UTE Teach-In Deletion Response expected
          # send UTE Teach-In Deletion Response message
          $data = (sprintf "%02X", $db[6] & 0x80 | 0x21) . substr($data, 2, 12);
          EnOcean_SndRadio(undef, $hash, $packetType, "D4", $data, AttrVal($name, "subDef", "00000000"), "00", $senderID);
          Log3 $name, 2, "EnOcean $name UTE teach-in deletion response send to $senderID";
        }
        Log3 $name, 2, "EnOcean $name UTE teach-in delete request executed";
      }
    } else {
      # Teach-In Respose telegram received
      my $teachInAccepted = ($db[6] & 0x30) >> 4;
      Log3 $name, 5, "EnOcean $name UTE teach-in response message from $senderID received";

      if (exists $hash->{IODev}{helper}{UTERespWait}{$destinationID}) {
        if ($comMode eq "uniDir") {
          $attr{$name}{manufID} = $mid;
          if ($teachInAccepted == 0) {
            $teachInAccepted = "request not accepted";
          } elsif ($teachInAccepted == 1){
            $teachInAccepted = "teach-in accepted";
          } elsif ($teachInAccepted == 2){
            $teachInAccepted = "teach-out accepted";
          } else {
            $teachInAccepted = "EEP not supported";
          }
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          push @event, "3:teach:UTE $teachInAccepted EEP $rorg-$func-$type Manufacturer: $mid";
          Log3 $name, 2, "EnOcean $name UTE $teachInAccepted EEP $rorg-$func-$type Manufacturer: $mid";
        } else {
          if ($hash->{IODev}{helper}{UTERespWait}{$destinationID}{teachInReq} eq "in") {
            # Teach-In Request
            if ($teachInAccepted == 0) {
              $teachInAccepted = "request not accepted";
            } elsif ($teachInAccepted == 1){
              $teachInAccepted = "teach-in accepted";
              $attr{$name}{subDef} = $hash->{DEF};
              $hash->{DEF} = $senderID;
              $modules{EnOcean}{defptr}{$senderID} = $hash;
              delete $modules{EnOcean}{defptr}{$destinationID};
              $attr{$name}{manufID} = $mid;
              # store attr subType, manufID ...
              EnOcean_CommandSave(undef, undef);

            } elsif ($teachInAccepted == 2){
              $teachInAccepted = "teach-out accepted";
            } else {
              $teachInAccepted = "EEP not supported";
            }
            $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
            push @event, "3:teach:UTE $teachInAccepted EEP $rorg-$func-$type Manufacturer: $mid";
            Log3 $name, 2, "EnOcean $name UTE $teachInAccepted EEP $rorg-$func-$type Manufacturer: $mid";

          } elsif ($hash->{IODev}{helper}{UTERespWait}{$destinationID}{teachInReq} eq "out") {
            # Teach-In Deletion Request
            if ($teachInAccepted == 0) {
              $teachInAccepted = "request not accepted";
            } elsif ($teachInAccepted == 1){
              $teachInAccepted = "teach-in accepted";
            } elsif ($teachInAccepted == 2){
              $teachInAccepted = "teach-out accepted";
              if (defined $attr{$name}{subDef}) {
                delete $modules{EnOcean}{defptr}{$hash->{DEF}};
                $hash->{DEF} = $attr{$name}{subDef};
                $modules{EnOcean}{defptr}{$hash->{DEF}} = $hash;
                delete $attr{$name}{subDef};
                EnOcean_CommandSave(undef, undef);
              }
            } else {
              $teachInAccepted = "EEP not supported";
            }
            $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
            push @event, "3:teach:UTE $teachInAccepted EEP $rorg-$func-$type Manufacturer: $mid";
            Log3 $name, 2, "EnOcean $name UTE $teachInAccepted EEP $rorg-$func-$type Manufacturer: $mid";
          }
        }
        # clear teach-in request
        delete $hash->{IODev}{helper}{UTERespWait}{$destinationID};

      } else {
        # teach-in request unknown, delete response device, no action
        $deleteDevice = $name;
        Log3 $name, 2, "EnOcean $name UTE teach-in request unknown";
      }
    }

  } elsif ($rorg eq "35" && $teach) {
    # Secure Teach-In
    ($err, $msg) = EnOcean_sec_parseTeachIn($hash, $data, $subDef, $destinationID);
    if (defined $err) {
      Log3 $name, 2, "EnOcean $name secure teach-in ERROR: $err";
      return "";
    }
    Log3 $name, 3, "EnOcean $name secure teach-in $msg";
    EnOcean_CommandSave(undef, undef);
    return "";

  } elsif ($rorg eq "C6" && $smartAckLearn) {
    # Smart Ack Learn Request
    $data =~ m/^(....)(..)(..)(..)(..)(........)$/;
    my $subType = "$2.$3.$4";
    my $postmasterID = '0' x 8;
    my $mid = '7FF';
    my $responseTime = 150;
    my $sendData = '';
    if (exists $EnO_eepConfig{$subType}) {
      if (($db[9] & 0xF8) == 0xF8) {
        # Smart Ack send by sensor
        $attr{$name}{subType} = $EnO_eepConfig{$subType}{attr}{subType};
        $attr{$name}{eep} = "$3-$4-$5";
        $mid = substr(sprintf("%04X", hex($1) & 0x7FF), 1);
        $attr{$name}{manufID} = $mid;
        $mid = $EnO_manuf{$mid} if(exists $EnO_manuf{$mid});
        $attr{$name}{repeaterID} = $6;
        $postmasterID = $6;
        $attr{$name}{postmasterID} = $postmasterID;
        $attr{$name}{teachMethod} = 'smartAck';
        $hash->{SmartAckRSSI} = - hex($db[4]);
        foreach my $attrCntr (keys %{$EnO_eepConfig{$subType}{attr}}) {
          if ($attrCntr ne "subDef") {
            $attr{$name}{$attrCntr} = $EnO_eepConfig{$subType}{attr}{$attrCntr};
          }
        }
        if (defined AttrVal($name, 'subDef', undef)) {
          $subDef = $attr{$name}{subDef};
        } else {
          $subDef = EnOcean_CheckSenderID('getNextID', $hash->{IODev}{NAME}, "00000000");
          $attr{$name}{subDef} = $subDef;
        }
        # create mailbox
        $sendData =  sprintf "03%04X00%04X%04X", $responseTime, $postmasterID, $hash->{DEF};
        EnOcean_SndRadio(undef, $hash, 6, $rorg, $sendData, $subDef, '00', $hash->{DEF});
        # next commands will be sent with a delay
        #usleep($responseTime * 1000);
        # send learn reply
        $sendData =  sprintf "01%04X00%04X", $responseTime, $hash->{DEF};
        EnOcean_SndRadio(undef, $hash, 1, 'C7', $sendData, $subDef, '00', $hash->{DEF});
        push @event, "3:teach:Smart Ack teach-in accepted EEP " . $attr{$name}{eep} . " Manufacturer: $mid";
        Log3 $name, 2, "EnOcean $name Smart Ack teach-in accepted EEP " . $attr{$name}{eep} . " Manufacturer: $mid";
        EnOcean_CommandSave(undef, undef);
      }
    } else {
      # EEP not supported
      # send learn reply
      $sendData = sprintf "01%04X10%04X", $responseTime, $hash->{DEF};
      EnOcean_SndRadio(undef, $hash, 1, 'C7', $sendData, '0' x 8, '00', $hash->{DEF});
      CommandDelete(undef, $name);
      Log3 $name, 2, "EnOcean $name Smart Ack teach-in not accepted EEP " . $attr{$name}{eep} . " Manufacturer: $mid";
    }

  } elsif ($packetType == 7) {
    # packet type REMOTE_MAN_COMMAND
    my $remoteCode = AttrVal($name, 'remoteCode', '0' x 8);
    my $remoteLastStatusReturnCode = $manufID eq '7FF' ? '00' : '04';
    my $remoteManagement = AttrVal($name, "remoteManagement", "off");
    my $sendData = '';
    push @event, "3:remoteLastFunctionNumber:" . sprintf("%03X", $funcNumber);

    if ($funcNumber == 1 && $remoteManagement eq 'client') {
      # unlock
      if ($data eq uc($remoteCode) && !exists($hash->{RemoteClientUnlockFailed})) {
        $hash->{RemoteClientUnlock} = 1;
        #my %functionHash = (hash => $hash, param => 'RemoteClientUnlock');
        #RemoveInternalTimer(\%functionHash);
        #InternalTimer(gettimeofday() + 1800, 'EnOcean_cdmClearHashVal', \%functionHash, 0);
        RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlock}) if(exists $hash->{helper}{timer}{RemoteClientUnlock});
        $hash->{helper}{timer}{RemoteClientUnlock} = {hash => $hash, param => 'RemoteClientUnlock'};
        InternalTimer(gettimeofday() + 1800, 'EnOcean_cdmClearHashVal', $hash->{helper}{timer}{RemoteClientUnlock}, 0);
        Log3 $name, 2, "EnOcean $name RMCC unlock request executed.";
      } else {
        $remoteLastStatusReturnCode = '02';
        $hash->{RemoteClientUnlockFailed} = 1;
        #my %functionHash = (hash => $hash, param => 'RemoteClientUnlockFailed');
        #RemoveInternalTimer(\%functionHash);
        #InternalTimer(gettimeofday() + 30, 'EnOcean_cdmClearHashVal', \%functionHash, 0);
        RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlockFailed}) if(exists $hash->{helper}{timer}{RemoteClientUnlockFailed});
        $hash->{helper}{timer}{RemoteClientUnlockFailed} = {hash => $hash, param => 'RemoteClientUnlockFailed'};
        InternalTimer(gettimeofday() + 30, 'EnOcean_cdmClearHashVal', $hash->{helper}{timer}{RemoteClientUnlockFailed}, 0);
        Log3 $name, 2, "EnOcean $name RMCC unlock request not executed, remote Code $data wrong.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 2 && $remoteManagement eq 'client') {
      # lock
      if ($hash->{RemoteClientUnlock} && $data eq uc($remoteCode)) {
        delete $hash->{RemoteClientUnlock};
        RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlock}) if(exists $hash->{helper}{timer}{RemoteClientUnlock});
        Log3 $name, 2, "EnOcean $name RMCC lock request executed.";
      } else {
        $remoteLastStatusReturnCode = '02';
        Log3 $name, 2, "EnOcean $name RMCC lock request not executed.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 3 && $remoteManagement eq 'client') {
      # set code
      if ($hash->{RemoteClientUnlock} && $data =~ m/^[A-Fa-f0-9]{8}$/ && uc($data) ne 'FFFFFFFF') {
        $attr{$name}{remoteCode} = $data;
        EnOcean_CommandSave(undef, undef);
        Log3 $name, 2, "EnOcean $name RMCC set code request executed.";
      } else {
        $remoteLastStatusReturnCode = '05';
        Log3 $name, 2, "EnOcean $name RMCC set code request not executed.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 4 && $remoteManagement eq 'client') {
      # query ID
      if ($hash->{RemoteClientUnlock}) {
        my $eepRcv = hex(substr($data, 0, 6)) >> 3;
        my $rorg = sprintf "%02X", ($eepRcv >> 13);
        my $func = sprintf "%02X", (($eepRcv & 0x1F80) >> 7);
        my $type = sprintf "%02X", ($eepRcv & 127);
        $eepRcv = "$rorg-$func-$type";
        if ($hash->{RemoteClientUnlock} && $eep eq $eepRcv) {
          $sendData = '06040' . AttrVal($name, 'manufID', '7FF') . substr($data, 0, 4) . sprintf("%02X", hex(substr($data, 4, 2)) & 0xF8);
          EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $sendData, '0' x 8, '0F', $senderID);
          Log3 $name, 2, "EnOcean $name RMCC query ID answer sent.";
        } else {
          $remoteLastStatusReturnCode = '03';
          Log3 $name, 2, "EnOcean $name RMCC query ID request not executed, EEP $eepRcv wrong or client locked.";
        }
      } else {
        $remoteLastStatusReturnCode = '07';
        Log3 $name, 2, "EnOcean $name RMCC query ID request not executed.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 5 && $remoteManagement eq 'client') {
      # action
      if ($hash->{RemoteClientUnlock}) {
        Log3 $name, 2, "EnOcean $name RMCC action request executed";
      } else {
        $remoteLastStatusReturnCode = '01';
        Log3 $name, 2, "EnOcean $name RMCC action request not executed.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 6 && $remoteManagement eq 'client') {
      # ping
      my $eep = AttrVal($name, "eep", "C5-00-00");
      if ($eep =~ m/^([A-Fa-f0-9]{2})-([A-Fa-f0-9]{2})-([A-Fa-f0-9]{2})$/i) {
        $eep = (((hex($1) << 6) | hex($2)) << 7) | hex($3);
      } else {
        $eep = (((hex("C5") << 6) | hex("00")) << 7) | hex("00");
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      push @event, "3:remoteRSSI:" . -$RSSI;
      $sendData = '06060' . AttrVal($name, 'manufID', '7FF') . sprintf("%04X%02X", $eep << 3, $RSSI);
      EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $sendData, '0' x 8, '0F', $senderID);
      Log3 $name, 2, "EnOcean $name RMCC ping answer executed";

    } elsif ($funcNumber == 7 && $remoteManagement eq 'client') {
      # query function
      if ($hash->{RemoteClientUnlock}) {
        $sendData = '06070' . AttrVal($name, 'manufID', '7FF') . '020107FF';
        EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $sendData, '0' x 8, '0F', $senderID);
        Log3 $name, 2, "EnOcean $name RMCC query function answer sent.";
      } else {
        $remoteLastStatusReturnCode = '07';
        Log3 $name, 2, "EnOcean $name RMCC query function request not executed.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 8 && $remoteManagement eq 'client') {
      # query status
      if ($hash->{RemoteClientUnlock}) {
        $sendData = '06080' . AttrVal($name, 'manufID', '7FF') . '000' . ReadingsVal($name, "remoteLastFunctionNumber", "000") .
                    ReadingsVal($name, "$remoteLastStatusReturnCode", '00');
        EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $sendData, '0' x 8, '0F', $senderID);
        Log3 $name, 2, "EnOcean $name RMCC query status answer sent.";
      } else {
        $remoteLastStatusReturnCode = '07';
        Log3 $name, 2, "EnOcean $name RMCC query status request not executed.";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 0x201) {
      $data =~ m/^(..)(..)(..)(..)$/;
      my ($rorg, $func, $type, $flag) = ($1, $2, $3, hex($4));
      if ($flag == 1) {
        # learn in
        if (exists $EnO_eepConfig{"$rorg.$func.$type"}) {
          $attr{$name}{eep} = "$rorg-$func-$type";
          #$attr{$name}{remoteID} = $remoteID if (defined $remoteID);
          $attr{$name}{remoteManagement} = "client";
          $attr{$name}{teachMethod} = 'RPC';
          foreach my $attrCntr (keys %{$EnO_eepConfig{"$rorg.$func.$type"}{attr}}) {
            if ($attrCntr eq "subDef") {
              if (!exists $attr{$name}{$attrCntr}) {
                $attr{$name}{$attrCntr} = EnOcean_CheckSenderID($EnO_eepConfig{"$rorg.$func.$type"}{attr}{$attrCntr}, $hash->{IODev}{NAME}, "00000000");
              }
            } else {
              $attr{$name}{$attrCntr} = $EnO_eepConfig{"$rorg.$func.$type"}{attr}{$attrCntr};
            }
          }
          EnOcean_CreateSVG(undef, $hash, $attr{$name}{eep});
          push @event, "3:teach:RPC teach-in accepted EEP $rorg-$func-$type Manufacturer: " .
                        (exists($EnO_manuf{$manufID}) ? $EnO_manuf{$manufID} : $manufID);
          Log3 $name, 2, "EnOcean $name RPC teach-in with EEP $rorg-$func-$type ManufacturerID: $manufID accepted.";
        } else {
          Log3 $name, 2, "EnOcean $name RPC teach-in with EEP $rorg-$func-$type ManufacturerID: $manufID not supported.";
        }

      } elsif ($flag == 3) {
        # learn out
        #Log3 $name, 2, "EnOcean $name device $name deleted";
        CommandDelete(undef, $name);
        Log3 $name, 2, "EnOcean $name RPC teach-out with EEP $rorg-$func-$type ManufacturerID: $manufID executed.";
        EnOcean_CommandSave(undef, undef);
      } else {

        Log3 $name, 2, "EnOcean $name RPC learn function $flag not supported";
      }
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";

    } elsif ($funcNumber == 0x240 && $remoteManagement eq 'manager') {
      # acknowledge
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RPC acknowledge received";

    } elsif ($funcNumber == 0x604 && $remoteManagement eq 'manager') {
      # query id answer
      my $eep = hex(substr($data, 0, 6)) >> 3;
      my $rorg = sprintf "%02X", ($eep >> 13);
      my $func = sprintf "%02X", (($eep & 0x1F80) >> 7);
      my $type = sprintf "%02X", ($eep & 127);
      $attr{$name}{remoteManufID} = $manufID;
      $manufID = $EnO_manuf{$manufID} if($EnO_manuf{$manufID});
      $attr{$name}{remoteEEP} = "$rorg-$func-$type";
      my $subType = "$rorg.$func.$type";
      #$attr{$name}{subType} = $EnO_eepConfig{$subType}{attr}{subType} if($EnO_manuf{$subType});
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RMCC query ID answer received EEP $rorg-$func-$type Manufacturer: $manufID";
      EnOcean_CommandSave(undef, undef);

    } elsif ($funcNumber == 0x606 && $remoteManagement eq 'manager') {
      # ping answer
      my $eep = hex(substr($data, 0, 6)) >> 3;
      my $rorg = sprintf "%02X", ($eep >> 13);
      my $func = sprintf "%02X", (($eep & 0x1F80) >> 7);
      my $type = sprintf "%02X", ($eep & 127);
      $attr{$name}{remoteManufID} = $manufID;
      $manufID = $EnO_manuf{$manufID} if($EnO_manuf{$manufID});
      $attr{$name}{remoteEEP} = "$rorg-$func-$type";
      my $subType = "$rorg.$func.$type";
      #$attr{$name}{subType} = $EnO_eepConfig{$subType}{attr}{subType} if($EnO_manuf{$subType});
      push @event, "3:remoteRSSI:" . -$RSSI;
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RMCC ping answer received EEP $rorg-$func-$type Manufacturer: $manufID";
      EnOcean_CommandSave(undef, undef);

    } elsif ($funcNumber == 0x607 && $remoteManagement eq 'manager') {
      # query function answer
      CommandDeleteReading(undef, "$name remoteFunction.*");
      my $count = 1;
      my $len = length($data);
      while ($len > 0) {
        $data =~ m/^.(...).(...)(.*)$/;
        push @event, "3:remoteFunction" . sprintf("%02d", $count) . ":$1:$2:" . (exists($EnO_extendedRemoteFunctionCode{hex($1)}) ? $EnO_extendedRemoteFunctionCode{hex($1)} : '-');
        $count ++;
        $data = $3;
        $len -= 8;
      }
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RMCC query function answer received";

    } elsif ($funcNumber == 0x608 && $remoteManagement eq 'manager') {
      # query status answer
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastFunctionNumber:" . substr($data, 3, 3);
      push @event, "3:remoteLastStatusReturnCode:" . substr($data, 6, 2);
      Log3 $name, 2, "EnOcean $name RMCC query status answer received LastFunction: " . substr($data, 3, 3) .
                      " LastFunctionCode: " . substr($data, 6, 2);

    } elsif ($funcNumber == 0x810 && $remoteManagement eq 'manager') {
      # teach-in supported link tables response
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      my $supportFlags = hex(substr($data, 0, 2));
      my $linkTableInCurrent = substr($data, 6, 2) && $supportFlags & 0x10 ? substr($data, 6, 2) : '00';
      my $linkTableInMax = substr($data, 8, 2) && $supportFlags & 0x10 ? substr($data, 8, 2) : '00';
      my $linkTableOutCurrent = substr($data, 2, 2) && $supportFlags & 0x20 ? substr($data, 2, 2) : '00';
      my $linkTableOutMax = substr($data, 4, 2) && $supportFlags & 0x20 ? substr($data, 4, 2) : '00';
      push @event, "3:remoteLearn:" . ($supportFlags & 0x80 ? 'supported' : 'not_supported');
      push @event, "3:remoteLinkTableIn:" . ($supportFlags & 0x10 ? 'supported' : 'not_supported');
      push @event, "3:remoteLinkTableOut:" . ($supportFlags & 0x20 ? 'supported' : 'not_supported');
      push @event, "3:remoteLinkTableInCurrent:" . $linkTableInCurrent if ($supportFlags & 0x10);
      push @event, "3:remoteLinkTableInMax:" . $linkTableInMax if ($supportFlags & 0x10);
      push @event, "3:remoteLinkTableOutCurrent:" . $linkTableOutCurrent if ($supportFlags & 0x20);
      push @event, "3:remoteLinkTableOutMax:" . $linkTableOutMax if ($supportFlags & 0x20);
      push @event, "3:remoteTeach:" . ($supportFlags & 0x40 ? 'supported' : 'not_supported');
      Log3 $name, 2, "EnOcean $name RPC teach-in supported link tables response received Data: $data";
      # request outbound table
      #$hash->{IODev}{helper}{remoteAnswerWait}{0x821}{hash} = $hash;
      #$hash->{IODev}{helper}{remoteLinkTableStartRef} = 0;
      #my %functionHash = (hash => $hash, param => 0x821);
      #RemoveInternalTimer(\%functionHash);
      #InternalTimer(gettimeofday() + 2.5, 'EnOcean_cdmClearRemoteWait', \%functionHash, 0);
      #$sendData = '022107FF';
      #EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $sendData, '0' x 8, '0F', $senderID);
      #Log3 $name, 2, "EnOcean $name RPC request teach-in outbound table";

    } elsif ($funcNumber == 0x811 && $remoteManagement eq 'manager') {
      # link table response
      CommandDeleteReading(undef, "$name remoteLinkTableDesc.*");
      $data =~ m/^(..)(.*)$/;
      my $direction = hex($1) & 0x80 ? 'Out' : 'In';
      $data = $2;
      while (length($data) > 0) {
        $data =~ m/^(..)(........)(..)(..)(..)(..)(.*)$/;
        push @event, "3:remoteLinkTableDesc" . $direction . "$1:S2:S3-S4-$5:$6";
        $data = $7;
      }
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RPC link table response received";

    } elsif ($funcNumber == 0x813 && $remoteManagement eq 'manager') {
      # link table GP response
      CommandDeleteReading(undef, "$name remoteLinkTableGPDesc.*");
      $data =~ m/^(..)(.*)$/;
      my $direction = hex($1) & 0x80 ? 'Out' : 'In';
      $data = $2;
      my $channel = 0;
      my $channelDir = hex($1) & 0x80 ? 'O' : 'I';
      my $channelDef;
      my $channelName;
      my $channelType;
      my $teachInDataLen = 0;
      my $gpData;
      my @gpDef;
      my $gpIdx;
      my $signalType;
      while (length($data) > 0) {
        $data =~ m/^(..)(.{12})(.*)$/;
        $gpIdx = $1;
        $gpData = EnOcean_convHexToBit($2);
        $data = $3;
        $gpData =~ m/^(..)(.{8})(.*)$/;
        $channelType = unpack('C', pack('B8', '000000' . $1));
        $signalType = unpack('C', pack('B8', $2));
        $data = $3;
        #Log3 $name, 2, "EnOcean $name parse RPC link table GP idx: $gpIdx channelType: $channelType signalType: $signalType data: $data";

        if ($channelType == 0) {
          # teach-in information
          if ($signalType == 1) {
            # outbound channel description

          } elsif ($signalType == 2) {
            # produkt ID
          }

        } elsif ($channelType == 1) {
          # data
          $gpData =~ m/^(..)(....)(.{8})(....)(.{8})(....)(.*)$/;
          $channelDef = $channelDir . ':' . $channelType . ':' . $signalType . ':' .
                        unpack('C', pack('B8', '000000' . $1)) . ':' . unpack('C', pack('B8', '0000' . $2)) . ':' .
                        unpack('c', pack('B8', $3)) . ':' . unpack('C', pack('B8', '0000' . $4)) . ':' .
                        unpack('c', pack('B8', $5)) . ':' . unpack('C', pack('B8', '0000' . $6));
          if (defined $EnO_gpValueData{$signalType}{name}) {
            $channelName = $EnO_gpValueData{$signalType}{name};
          } else {
            $channelName = "none";
          }
          $gpDef[$channel] = $channelName . ':' . $channelDef;

        } elsif ($channelType == 2) {
          # flag
          $gpData =~ m/^(..)(.*)$/;
          $channelDef = $channelDir . ':' .$channelType . ':' . $signalType . ':' .
                        unpack('C', pack('B8', '000000' . $1));
          if (defined $EnO_gpValueFlag{$signalType}{name}) {
            $channelName = $EnO_gpValueFlag{$signalType}{name};
          } else {
            $channelName = "none";
          }
          $gpDef[$channel] = $channelName . ':' . $channelDef;

        } elsif ($channelType == 3) {
          # enumeration
          $gpData =~ m/^(..)(....)(.*)$/;
          $channelDef = $channelDir . ':' .$channelType . ':' . $signalType . ':' .
                        unpack('C', pack('B8', '000000' . $1)) . ':' . unpack('C', pack('B8', '0000' . $2));
          if (defined $EnO_gpValueEnum{$signalType}{name}) {
            $channelName = $EnO_gpValueEnum{$signalType}{name};
          } else {
            $channelName = "none";
          }
          $gpDef[$channel] = $channelName . ':' . $channelDef;
        }
        push @event, "3:remoteLinkTableGPDesc" . $direction . "$gpIdx:$gpDef[0]";
      }
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RPC link table GP response received";

    } elsif ($funcNumber == 0x827 && $remoteManagement eq 'manager') {
      # product ID answer
      $manufID = substr($data, 1, 3);
      $attr{$name}{remoteManufID} = $manufID;
      $manufID = $EnO_manuf{$manufID} if($EnO_manuf{$manufID});
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      $sendData = '024007FF';
      EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $sendData, '0' x 8, '0F', $senderID);
      push @event, "3:remoteProductID:" . substr($data, 4, 8);
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RPC Product ID answer received ProductID: " . substr($data, 4, 8) . " Manufacturer: $manufID";
      Log3 $name, 2, "EnOcean $name RPC acknowledge sent";
      EnOcean_CommandSave(undef, undef);

    } elsif ($funcNumber == 0x830 && $remoteManagement eq 'manager') {
      # device config response
      CommandDeleteReading(undef, "$name remoteDevCfg.*");
      my $idx;
      my $valueLen;
      while (length($data) > 0) {
        $data =~ m/^(....)(..)(.*)$/;
        $idx = $1;
        $valueLen = hex($2) * 2;
        $data = $3;
        $data =~ m/^(.{$valueLen})(.*)$/;
        push @event, "3:remoteDevCfg$idx:S1";
        $data = $2;
      }
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RPC device configuration response received";

    } elsif ($funcNumber == 0x832 && $remoteManagement eq 'manager') {
      # link based configuration response
      $data =~ m/^(..)(..)(.*)$/;
      my $direction = hex($1) & 0x80 ? 'Out' : 'In';
      my $linkTableIdx = $2;
      CommandDeleteReading(undef, "$name remoteLinkCfg$direction$linkTableIdx.*");
      $data = $3;
      my $idx;
      my $valueLen;
      while (length($data) > 0) {
        $data =~ m/^(....)(..)(.*)$/;
        $idx = $1;
        $valueLen = hex($2) * 2;
        $data = $3;
        $data =~ m/^(.{$valueLen})(.*)$/;
        push @event, "3:remoteLinkCfg$direction$linkTableIdx:$idx:S1";
        $data = $2;
      }
      $remoteLastStatusReturnCode = '00';
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      push @event, "3:remoteLastStatusReturnCode:$remoteLastStatusReturnCode";
      Log3 $name, 2, "EnOcean $name RPC link table response received";

    } elsif ($funcNumber == 0x850 && $remoteManagement eq 'manager') {
      # query status answer
      delete $iohash->{helper}{remoteAnswerWait}{$funcNumber}{hash};
      my $repeaterFunction = 'off';
      if (($db[0] & 0xC0) == 0) {
        $repeaterFunction = 'off';
      } elsif (($db[0] & 0xC0) == 0x40) {
        $repeaterFunction = 'on';
      } elsif (($db[0] & 0xC0) == 0x80) {
        $repeaterFunction = 'filter';
      }
      push @event, "3:remoteRepeaterFunction:$repeaterFunction";
      push @event, "3:remoteRepeaterLevel:" . (($db[0] & 0x30) == 0x20 ? 2 : 1);
      push @event, "3:remoteRepeaterFilter:" . ($db[0] & 8 ? 'OR' : 'AND');
      Log3 $name, 2, "EnOcean $name RPC repeater functions response received";

    } else {
      Log3 $name, 2, "EnOcean $name RMCC/RPC function number " . sprintf("%03X", $funcNumber) . " not supported.";
    }

  } elsif ($rorg eq "C5" && $packetType == 1) {
    # remote management >> packetType = 7
    return $name;
  }

  readingsBeginUpdate($hash);
  for(my $i = 0; $i < int(@event); $i++) {
    # Flag & 1: reading, Flag & 2: changed. Currently ignored.
    my ($flag, $vn, $vv) = split(':', $event[$i], 3);
    readingsBulkUpdate($hash, $vn, $vv);
    my @cmdObserve = ($name, $vn, $vv);
    EnOcean_observeParse(2, $hash, @cmdObserve);
  }
  readingsEndUpdate($hash, 1);

  if (defined $deleteDevice) {
    # delete device and save config
    CommandDelete(undef, $deleteDevice);
    Log3 $name, 2, "EnOcean $name device $deleteDevice deleted";
    if (defined $oldDevice) {
      Log3 $name, 2, "EnOcean $name renamed $oldDevice to $deleteDevice";
      CommandRename(undef, "$oldDevice $deleteDevice");
      EnOcean_CommandSave(undef, undef);
      return $deleteDevice;
    } else {
      EnOcean_CommandSave(undef, undef);
      return '';
    }
  }
  return $name;
}

sub EnOcean_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  # return if attribute list is incomplete
  return undef if (!$init_done);
  my $err;
  my $loglevel = 2;
  my $waitingCmds = AttrVal($name, "waitingCmds", 0);

  if ($attrName eq "angleTime") {
    my $channel;
    my $data;
    if (!defined $attrVal) {
      if (AttrVal($name, "subType", "") =~ m/^blindsCtrl\.0[01]$/) {
        # no rotation
        $data = "7FFF0007F5";
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }

    } elsif (AttrVal($name, "subType", "") =~ m/^blindsCtrl\.0[01]$/) {
      my @attrVal = split(':', $attrVal);
      for (my $channel = 0; $channel <= $#attrVal && $channel < 4; $channel ++) {
        if ($attrVal[$channel] =~ m/^\d+(\.\d+)?$/ && $attrVal[$channel] >= 0 && $attrVal[$channel] <= 2.54) {
          if ($attrVal[$channel] < 0.01) {
            $attrVal[$channel] = 0;
          } else {
            $attrVal[$channel] = int($attrVal[$channel] * 100);
          }
          $data = sprintf "7FFF%02X07%02X", $attrVal[$channel], $channel << 4 | 5;
          EnOcean_SndRadio(0.2 + $channel * 0.5, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
        } else {
          $err = "attribute-value [$attrName] = $attrVal wrong";
        }
      }

    } elsif (AttrVal($name, "subType", "") eq "manufProfile" && AttrVal($name, "manufID", "") eq "00D" &&
             $attrVal =~ m/^[+-]?\d+?$/ && $attrVal >= 1 && $attrVal <= 6) {

    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      #Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      #CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "alarmAction") {
    my $data;
    if (!defined $attrVal) {
      if (AttrVal($name, "subType", "") =~ m/^blindsCtrl\.0[01]$/) {
        # no alarm action
        $data = "7FFFFF00F5";
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }

    } elsif (AttrVal($name, "subType", "") =~ m/^blindsCtrl\.0[01]$/) {
      my @attrVal = split(':', $attrVal);
      for (my $channel = 0; $channel <= $#attrVal && $channel < 4; $channel ++) {
        if ($attrVal =~ m/no|stop|opens|closes$/) {
          my $alarmAction = 0;
          if ($attrVal[$channel] eq "no") {
            $alarmAction = 0;
          } elsif ($attrVal[$channel] eq "stop") {
            $alarmAction = 1;
          } elsif ($attrVal[$channel] eq "opens") {
            $alarmAction = 2;
          } elsif ($attrVal[$channel] eq "closes") {
            $alarmAction = 3;
          } else {
            $err = "attribute-value [$attrName] = $attrVal wrong";
          }
          $data = sprintf "7FFFFF%02X%02X", $alarmAction, $channel << 4 | 5;
          EnOcean_SndRadio(0.2 + $channel * 0.5, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
        } else {
          $err = "attribute-value [$attrName] = $attrVal wrong";
        }
      }

    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName =~ m/^block.*/) {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^(no|yes)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "brightnessDayNightCtrl") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^custom|sensor$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName =~ m/^brightness(DayNight|Sunny).*$/) {
    if (!defined $attrVal) {

    } else {
      my ($attrVal0, $attrVal1) = split(':', $attrVal);
      if (!defined($attrVal0) && !defined($attrVal1)) {

      } else {
        if (!defined $attrVal0 || $attrVal0 eq '') {

        } elsif ($attrVal0 !~ m/^[+]?\d+$/ || $attrVal0 + 0 > 99000) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
        }
        if (!defined $attrVal1 || $attrVal1 eq '') {

        } elsif ($attrVal1 !~ m/^[+]?\d+$/ || $attrVal1 + 0 > 99000) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
        }
      }
    }

  } elsif ($attrName eq "calAtEndpoints") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^no|yes$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "comMode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^biDir|uniDir|confirm$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "creator") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^autocreate|manual$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "dataEnc") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^VAES|AES-CBC$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "daylightSavingTime") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^(supported|not_supported)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "defaultChannel") {
    my $defaultChannel = '';
    my $subType = AttrVal($name, "subType", "");
    if ($subType eq "actuator.01") {
      $defaultChannel = join("|", @EnO_defaultChannel);
    } elsif ($subType =~ m/^blindsCtrl\.0[01]$/) {
      $defaultChannel = '[1234]|all';
    }

    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^($defaultChannel)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "demandRespAction") {
    if (!defined $attrVal){

    } else {
      my %specials = ("%TARGETNAME" => $name,
                      "%NAME" => $name,
                      "%TARGETTYPE" => '',
                      "%TYPE" => '',
                      "%LEVEL" => '',
                      "%SETPOINT" => '',
                      "%POWERUSAGE" => '',
                      "%POWERUSAGESCALE" => '',
                      "%POWERUSAGELEVEL" => '',
                      "%TARGETSTATE" => '',
                      "%STATE" => ''
                     );
      $err = perlSyntaxCheck($attrVal, %specials);
    }

  } elsif ($attrName eq "demandRespRandomTime") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 1) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName =~ m/^(demandRespMax|demandRespMin)$/) {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^(A0|AI|B0|BI|C0|CI|D0|DI)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "demandRespThreshold") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 0 || $attrVal > 15) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "devChannel") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^[\dA-Fa-f]{2}$/) {
      # actions see EnOcean_Notify, global ATTR

    } elsif ($attrVal =~ m/^\d+$/ && $attrVal >= 0 && $attrVal <= 255) {

    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "devMode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^master|slave$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "devUpdate") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^(off|auto|demand|polling|interrupt)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName =~ m/^dimMax|dimMin$/) {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^off|[\d+]$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "displayContent") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^(humidity|off|setpointTemp|tempertureExtern|temperatureIntern|time|default|no_change)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "displayOrientation") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^0|90|180|270$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "eep" || $attrName eq "remoteEEP") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[\dA-Fa-f]{2}-[\dA-Fa-f]{2}-[\dA-Fa-f]{2}$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "model") {
    if (!defined $attrVal){

    } else {
      # set model specific attributes
      foreach my $attrCntr (keys %{$EnO_models{$attrVal}{attr}}) {
        if ($attrCntr eq "remoteID") {
          if (exists $hash->{DEF}) {
            $attr{$name}{$attrCntr} = $hash->{DEF};
          } else {
            $attr{$name}{$attrCntr} = EnOcean_CheckSenderID($EnO_models{$attrVal}{attr}{$attrCntr}, $hash->{IODev}{NAME}, "00000000");
          }
        } else {
          $attr{$name}{$attrCntr} = $EnO_models{$attrVal}{attr}{$attrCntr};
        }
      }
      if (exists $EnO_models{$attrVal}{xml}) {
        # read xml device description to $hash->{helper}
        if ($xmlFunc == 1) {
          my $xmlFile = $attr{global}{modpath} . $EnO_models{$attrVal}{xml}{xmlDescrLocation};
          if (-e -f -r $xmlFile) {
            $hash->{helper} = $xml->XMLin($xmlFile);
            if (exists $hash->{helper}{Device}) {

            } else {
              Log3 $name, 2, "EnOcean $name <attr> Device Description not defined";
            }
          } else {
            Log3 $name, 2, "EnOcean $name <attr> Device Description file $xmlFile not exists";
          }
        } else {
          Log3 $name, 2, "EnOcean $name <attr> XML functions are not available";
        }
      }
    }

  } elsif ($attrName eq "gpDef") {
    if (!defined $attrVal){

    } else {
      my @gpDef = split("[ \t][ \t]*", $attrVal);
      my ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax);
      for (my $channel = 0; $channel < @gpDef; $channel ++) {
        my @err;
        ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
          split(':', $gpDef[$channel]);
        push(@err, "channelName") if (!defined $channelName);
        push(@err, "channelDir") if (!defined($channelDir) || $channelDir !~ m/^O|I$/);
        push(@err, "channelType") if (!defined($channelType) || $channelType !~ m/^\d+$/ || $channelType > 3);
        push(@err, "signalType") if (!defined($signalType) || $signalType !~ m/^\d+$/ || $signalType > 255);
        push(@err, "valueType") if (!defined($valueType) || $valueType !~ m/^\d+$/ || $valueType > 3);
        if ($channelType == 1 || $channelType == 3) {
          push(@err, "resolution") if (!defined($resolution) || $resolution !~ m/^\d+$/ || $resolution > 12);
        }
        if ($channelType == 1) {
          push(@err, "engMin") if (!defined($engMin) || $engMin !~ m/^[+-]?\d+$/ || $engMin < -128 || $engMin > 127);
          push(@err, "scalingMin") if (!defined($scalingMin) || $scalingMin !~ m/^\d+$/ || $scalingMin < 1 || $scalingMin > 13);
          push(@err, "engMax") if (!defined($engMax) || $engMax !~ m/^[+-]?\d+$/ || $engMax < -128 || $engMax > 127);
          push(@err, "scalingMax") if (!defined($scalingMax) || $scalingMax !~ m/^\d+$/ || $scalingMax < 1 || $scalingMax > 13);
        }
        $err = "attribute-value $attrName/channel " . sprintf('%02d', $channel) . ": " .
                       join(', ', @err) . " wrong" if (defined $err[0]);
      }
    }

  } elsif ($attrName eq "humidity") {
    if (!defined $attrVal) {

    } elsif ($attrVal =~ m/^\d+$/ && $attrVal >= 0 && $attrVal <= 100) {

    } else {
      #RemoveInternalTimer($hash);
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName =~ m/^key/) {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[\dA-Fa-f]{32}$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "macAlgo") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^no|[3-4]$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "manufID" || $attrName eq "remoteManufID") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[0-7][\dA-Fa-f]{2}$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "measurementCtrl") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^disable|enable$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "measurementTypeSelect") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^feed|room$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "observe") {
    if (!defined $attrVal){

    } elsif (lc($attrVal) !~ m/^(off|on)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "observeCmdRepetition") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[1-5]$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "observeErrorAction") {
    if (!defined $attrVal){

    } else {
      my %specials = ("%NAME" => $name,
                      "%FAILEDDEV" => '',
                      "%TYPE"  => '',
                      "%EVENT" => ''
                     );
      $err = perlSyntaxCheck($attrVal, %specials);
    }

  } elsif ($attrName eq "observeInterval") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 1) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "observeLogic") {
    if (!defined $attrVal){

    } elsif (lc($attrVal) !~ m/^and|or$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "pidActorErrorAction") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^errorPos|freeze$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "pidCtrl") {
    if (!defined $attrVal){

    } elsif (lc($attrVal) eq "on") {
      EnOcean_setPID(undef, $hash, 'start', ReadingsVal($name, "setpoint", undef));
    } elsif (lc($attrVal) eq "off") {
      EnOcean_setPID(undef, $hash, 'stop', undef);
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "pidActorErrorPos") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 0 || $attrVal > 100) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "pidDeltaTreshold") {
    my $reFloatpos = '^([\\+]?\\d+\\.?\d*$)';
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/$reFloatpos/) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "pidSensorTimeout") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+?$/) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName =~ m/^pidActorLimitLower|pidActorLimitUpper$/) {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 0 || $attrVal > 100) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName =~ m/^pidFactor_.$/) {
    my $reFloatpos = '^([\\+]?\\d+\\.?\d*$)';
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/$reFloatpos/) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "pollInterval") {
    if (!defined $attrVal) {

    } elsif ($attrVal =~ m/^\d+?$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      #RemoveInternalTimer($hash);
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "productID") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[\dA-Fa-f]{8}$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "rampTime") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^\d+?$/) {
      if (AttrVal($name, "subType", "") eq "gateway") {
        if ($attrVal < 0 || $attrVal > 255) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
        }
      } elsif (AttrVal($name, "subType", "") eq "lightCtrl.01") {
        if ($attrVal < 0 || $attrVal > 65535) {
          $err = "attribute-value [$attrName] = $attrVal wrong";
        }
      } else {
        $err = "attribute-value [$attrName] = $attrVal wrong";
      }
    } else {
      $err = "attribute $attrName not supported for subType " . AttrVal($name, "subType", "");
    }

  } elsif ($attrName eq "releasedChannel") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^A|B|C|D|I|0|auto$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "rcvRespAction") {
    if (!defined $attrVal){

    } elsif (AttrVal($name, "subType", "") eq "hvac.01") {
      my %specials = ("%ACTUATORSTATE" => '',
                      "%BATTERY" => '',
                      "%COVER" => '',
                      "%ENERGYINPUT" => '',
                      "%ENERGYSTORAGE" => '',
                      "%MAINTENANCEMODE" => '',
                      "%NAME" => $name,
                      "%OPERATIONMODE" => '',
                      "%ROOMTEMP" => '',
                      "%SELFCTRL" => '',
                      "%SETPOINT" => '',
                      "%SETPOINTTEMP" => '',
                      "%SUMMERMODE" => '',
                      "%TEMPERATURE" => '',
                      "%WINDOW" => ''
                     );
      $err = perlSyntaxCheck($attrVal, %specials);
    } elsif (AttrVal($name, "subType", "") eq "hvac.04") {
      my %specials = ("%BATTERY" => '',
                      "%FEEDTEMP" => '',
                      "%MAINTENANCEMODE" => '',
                      "%NAME" => $name,
                      "%OPERATIONMODE" => '',
                      "%ROOMTEMP" => '',
                      "%SETPOINT" => '',
                      "%SETPOINTTEMP" => '',
                      "%SUMMERMODE" => '',
                      "%TEMPERATURE" => ''
                     );
      $err = perlSyntaxCheck($attrVal, %specials);
    } elsif (AttrVal($name, "subType", "") eq "hvac.06") {
      my %specials = ("%ACTUATORSTATE" => '',
                      "%BATTERY" => '',
                      "%ENERGYINPUT" => '',
                      "%ENERGYSTORAGE" => '',
                      "%FEEDTEMP" => '',
                      "%MAINTENANCEMODE" => '',
                      "%NAME" => $name,
                      "%OPERATIONMODE" => '',
                      "%RADIOCOMERR" => '',
                      "%RADIOSIGNALSTRENGTH" => '',
                      "%ROOMTEMP" => '',
                      "%SETPOINT" => '',
                      "%SETPOINTTEMP" => '',
                      "%SETPOINTTEMPLOCAL" => '',
                      "%SUMMERMODE" => '',
                      "%TEMPERATURE" => '',
                      "%WINDOW" => '',
                     );
      $err = perlSyntaxCheck($attrVal, %specials);
    }

  } elsif ($attrName eq "remoteID") {
    if (!defined $attrVal){
      # delete old pointer
      delete $modules{EnOcean}{defptr}{$attr{$name}{$attrName}} if (exists($attr{$name}{$attrName}) && $attr{$name}{$attrName} ne $hash->{DEF});
    } elsif ($attrVal =~ m/^[\dA-F]{8}$/) {
      # delete old pointer
      delete $modules{EnOcean}{defptr}{$attr{$name}{$attrName}} if (exists($attr{$name}{$attrName}) && $attr{$name}{$attrName} ne $hash->{DEF});
      $modules{EnOcean}{defptr}{$attrVal} = $hash;
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "remoteManagement") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^client|manager|off$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "reposition") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^directly|opens|closes$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName =~ m/^rlcRcv|rlcSnd$/) {
    if (!defined $attrVal){

    } elsif (AttrVal($name, "rlcAlgo", "") eq "2++" && $attrVal =~ m/^[\dA-Fa-f]{4}$/) {

    } elsif (AttrVal($name, "rlcAlgo", "") eq "3++" && $attrVal =~ m/^[\dA-Fa-f]{6}$/) {

    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "rlcAlgo") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^no|2++|3++$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "rlcTX") {
    if (!defined $attrVal){

    } elsif (lc($attrVal) !~ m/^true|false$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "rltType") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^1BS|4BS$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "rltRepeat") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^\d+?$/ && $attrVal >= 16 && $attrVal <= 256) {

    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "remoteCode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[\dA-Fa-f]{8}$/ || $attrVal eq "00000000" || uc($attrVal) eq "FFFFFFFF") {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "secLevel") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^encapsulation|encryption|off$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "secMode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^rcv|snd|bidir$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "sendDevStatus") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^no|yes$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "sendTimePeriodic") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^\d+|off$/) {
      @{$hash->{helper}{periodic}{time}} = ($hash, 'time', $attrVal, 0, -1, undef);
      EnOcean_SndPeriodic($hash->{helper}{periodic}{time});
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "serviceOn") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^(no|yes)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "setCmdTrigger") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^man|refDev$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "setpointSummerMode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^\d+$/ && $attrVal >= 0 && $attrVal <= 100) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "settingAccuracy") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^high|low$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "shutTime") {
    my $data;
    if (!defined $attrVal) {
      if (AttrVal($name, "subType", "") =~ m/^blindsCtrl\.0[01]$/) {
        # set shutTime to max
        $data = "7530FF07F5";
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }
    } elsif (AttrVal($name, "subType", "") =~ m/^blindsCtrl\.0[01]$/) {
      my @attrVal = split(':', $attrVal);
      for (my $channel = 0; $channel <= $#attrVal && $channel < 4; $channel ++) {
        if ($attrVal[$channel] =~ m/^\d+$/ && $attrVal[$channel] >= 5 && $attrVal[$channel] <= 300) {
          $attrVal[$channel] = int($attrVal[$channel] * 100);
          $data = sprintf "%04XFF07%02X", $attrVal[$channel], $channel << 4 | 5;
          EnOcean_SndRadio(0.2 + $channel * 0.5, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
        } else {
          $err = "attribute-value [$attrName] = $attrVal wrong";
        }
      }
    } elsif (AttrVal($name, "subType", "") eq "manufProfile" && AttrVal($name, "manufID", "") eq "00D" &&
             $attrVal =~ m/^[+-]?\d+$/ && $attrVal >= 1 && $attrVal <= 255) {

    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "signal") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^off|on$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "signOfLife") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^off|on$/) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "signOfLifeInterval") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 1 || $attrVal > 65535) {
      $err = "attribute-value [$attrName] = $attrVal is not a integer number or not valid";
    }

  } elsif ($attrName eq "summerMode") {
    if (!defined $attrVal){

    } elsif ($attrVal eq 'on') {
      if (AttrVal($name, 'subType', '') =~ m/^hvac\.0(1|4|6)$/ && AttrVal($name, 'summerMode', 'off') eq 'off') {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'waitingCmds', 'summerMode');
        readingsBulkUpdate($hash, 'operationModeRestore', ReadingsVal($name, 'operationMode', 'setpoint'));
        readingsBulkUpdate($hash, 'setpointTempRestore', ReadingsVal($name, 'setpointTemp', 20));
        readingsBulkUpdate($hash, 'operationMode', 'setpoint');
        readingsEndUpdate($hash, 0);

      } else {
        # attr not changed

      }
    } elsif ($attrVal eq 'off') {
      if (AttrVal($name, 'subType', '') =~ m/^hvac\.0(1|4|6)$/ && AttrVal($name, 'summerMode', 'off') eq 'on') {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'waitingCmds', 'runInit');
        readingsBulkUpdate($hash, 'operationMode', ReadingsVal($name, 'operationModeRestore', 'setpoint'));
        readingsBulkUpdate($hash, 'setpointTemp', ReadingsVal($name, 'setpointTempRestore', 20));
        readingsEndUpdate($hash, 0);
        CommandDeleteReading(undef, "$name .*Restore");

      } else {
       # attr not changed
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName =~ m/^subDef.?|postmasterID/) {
    if (!defined $attrVal){

    } elsif ($attrVal eq "getNextID") {
      # actions see EnOcean_Notify, global ATTR

    } elsif ($attrVal !~ m/^[\dA-Fa-f]{8}$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "switchHysteresis") {
    if (!defined $attrVal) {

    } elsif ($attrVal =~ m/^\d+(\.\d+)?$/ && $attrVal >= 0.1) {

    } else {
      #RemoveInternalTimer($hash);
      $err = "attribute-value [$attrName] = $attrVal is not a valid number";
    }

  } elsif ($attrName eq "teachMethod") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^1BS|4BS|confirm|GP|RPS|smartAck|STE|UTE$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "temperatureScale") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^(C|F|default|no_change)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "timeNotation") {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^(12|24|default|no_change)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName =~ m/^timeProgram[1-4]$/) {
    if (!defined $attrVal){

    } elsif ($attrVal =~ m/^(FrMo|FrSu|ThFr|WeFr|TuTh|MoWe|SaSu|MoFr|MoSu|Su|Sa|Fr|Th|We|Tu|Mo)\s+(\d*?):(00|15|30|45)\s+(\d*?):(00|15|30|45)\s+(comfort|economy|preComfort|buildingProtection)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        # delete remote and send new time program
        delete $hash->{helper}{4}{telegramWait};
        $hash->{helper}{4}{telegramWait}{substr($attrName,-1,1) + 0} = 1;
        for (my $messagePartCntr = 1; $messagePartCntr <= 4; $messagePartCntr ++) {
          if (defined AttrVal($name, "timeProgram" . $messagePartCntr, undef)) {
            $hash->{helper}{4}{telegramWait}{$messagePartCntr} = 1;
          }
        }
        $waitingCmds |= 528;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "trackerWakeUpCycle") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^10|20|30|40|60|120|180|240|3600|86400$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "updateGlobalAttr") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^yes|no$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "updateState") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^default|yes|no$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "uteResponseRequest") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^(yes|no)$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "wakeUpCycle") {
    my $wakeUpCycle = join("|", keys %wakeUpCycle);
    if (!defined $attrVal){

    } elsif (AttrVal($name, "subType", "") eq "hvac.04" && $attrVal =~ m/^$wakeUpCycle$/ && $wakeUpCycle{$attrVal} <= 63) {
      if ($attrVal >= 1500 && AttrVal($name, 'wakeUpCycle', 300) < 1500) {
        # switch to summer mode
        $attr{$name}{summerMode} = 'on';
        readingsSingleUpdate($hash, 'waitingCmds', 'summerMode', 0);
      } elsif ($attrVal < 1500 && AttrVal($name, 'wakeUpCycle', 300) >= 1500) {
        # runInit necessary before switch to operation mode
        $attr{$name}{summerMode} = 'off';
        readingsSingleUpdate($hash, 'waitingCmds', 'runInit', 0);
      }
    } elsif (AttrVal($name, "subType", "") eq "hvac.06" && $attrVal =~ m/^$wakeUpCycle$/) {
      if (lc($attrVal) eq 'auto') {

      } elsif ($attrVal > 7200 && AttrVal($name, 'wakeUpCycle', 300) <= 7200) {
        # switch to summer mode
        $attr{$name}{summerMode} = 'on';
        readingsSingleUpdate($hash, 'waitingCmds', 'summerMode', 0);
      } elsif ($attrVal <= 7200 && AttrVal($name, 'wakeUpCycle', 300) > 7200) {
        # runInit necessary before switch to operation mode
        $attr{$name}{summerMode} = 'off';
        readingsSingleUpdate($hash, 'waitingCmds', 'runInit', 0);
      }
    } else {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName eq "windowOpenCtrl") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^disable|enable$/) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
    }

  } elsif ($attrName =~ m/^windSpeed.*$/) {
    my ($attrVal0, $attrVal1) = split(':', $attrVal);
    if (!defined $attrVal1) {
      if (!defined $attrVal0) {

      } elsif ($attrVal0 !~ m/^[+]?\d+(\.\d)?$/ || $attrVal0 + 0 > 35) {
        $err = "attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");
      }
    } elsif ($attrVal1 !~ m/^[+]?\d+(\.\d)?$/ || $attrVal1 + 0 > 35) {
      $err = "attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    } else {
      if (!defined $attrVal0) {

      } elsif ($attrVal0 !~ m/^[+]?\d+(\.\d)?$/ || $attrVal0 + 0 > 35) {
        $err = "attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");
      }
    }
  }
  return $err;
}

sub EnOcean_Notify(@)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  my $devName = $dev->{NAME};
  return undef if (AttrVal($name ,"disable", 0) > 0);

  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if ($devName eq $name) {
      my @parts = split(/: | /, $s);
      if (exists($hash->{helper}{stopped}) && !$hash->{helper}{stopped} && $parts[0] eq "temperature") {
        # PID regulator: calc gradient for delta as base for d-portion calculation
        my $setpointTemp = ReadingsVal($name, "setpointTemp", undef);
        my $temperature = $parts[1];
        # ---- build difference current - old value
        # calc difference of delta/deltaOld
        my $delta = $setpointTemp - $temperature if (defined($setpointTemp));
        my $deltaOld = ($hash->{helper}{deltaOld} + 0) if (defined($hash->{helper}{deltaOld}));
        my $deltaDiff = ($delta - $deltaOld) if (defined($delta) && defined($deltaOld));
        # ----- build difference of timestamps
        my $deltaOldTsStr = $hash->{helper}{deltaOldTS};
        my $deltaOldTsNum = time_str2num($deltaOldTsStr) if (defined($deltaOldTsStr));
        my $nowTsNum = gettimeofday();
        my $tsDiff = ($nowTsNum - $deltaOldTsNum)
          if (defined($deltaOldTsNum) && (($nowTsNum - $deltaOldTsNum) > 0));
        # ----- calculate gradient of delta
        my $deltaGradient = $deltaDiff / $tsDiff
          if (defined($deltaDiff) && defined($tsDiff) && ($tsDiff > 0 ));
        $deltaGradient = 0 if ( !defined($deltaGradient) );
        # ----- store results
        $hash->{helper}{deltaGradient} = $deltaGradient;
        $hash->{helper}{deltaOld} = $delta;
        $hash->{helper}{deltaOldTS} = TimeNow();
        Log3 $name, 5, "EnOcean $name <notify> $devName $s";
      }

    } elsif ($devName eq "global" && $s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      if (defined AttrVal($name, "temperatureRefDev", undef)) {
        if (AttrVal($name, "temperatureRefDev", undef) eq $1) {
          CommandAttr(undef, "$name temperatureRefDev $2");
        }
      } elsif (defined AttrVal($name, "setpointRefDev", undef)) {
        if (AttrVal($name, "setpointRefDev", undef) eq $1) {
          CommandAttr(undef, "$name setpointRefDev $2");
        }
      } elsif (defined AttrVal($name, "setpointTempRefDev", undef)) {
        if (AttrVal($name, "setpointTempRefDev", undef) eq $1) {
          CommandAttr(undef, "$name setpointTempRefDev $2");
        }
      } elsif (defined AttrVal($name, "humidityRefDev", undef)) {
        if (AttrVal($name, "humidityRefDev", undef) eq $1) {
          CommandAttr(undef, "$name humidityRefDev $2");
        }
      } elsif (defined AttrVal($name, "observeRefDev", undef)) {
        if (AttrVal($name, "observeRefDev", undef) eq $1) {
          CommandAttr(undef, "$name observeRefDev $2");
        }
      } elsif (defined AttrVal($name, "demandRespRefDev", undef)) {
        if (AttrVal($name, "demandRespRefDev", undef) eq $1) {
          CommandAttr(undef, "$name demandRespRefDev $2");
        }
      }
      #Log3($name, 5, "EnOcean $name <notify> RENAMED old: $1 new: $2");

    } elsif ($devName eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      # delete attribute *RefDev
      if (defined AttrVal($name, "temperatureRefDev", undef)) {
        if (AttrVal($name, "temperatureRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name temperatureRefDev");
        }
      } elsif (defined AttrVal($name, "setpointRefDev", undef)) {
        if (AttrVal($name, "setpointRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name setpointRefDev");
        }
      } elsif (defined AttrVal($name, "setpointTempRefDev", undef)) {
        if (AttrVal($name, "setpointTempRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name setpointTempRefDev");
        }
      } elsif (defined AttrVal($name, "humidityRefDev", undef)) {
        if (AttrVal($name, "humidityRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name humidityRefDev");
        }
      } elsif (defined AttrVal($name, "observeRefDev", undef)) {
        if (AttrVal($name, "observeRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name observeRefDev");
        }
      } elsif (defined AttrVal($name, "demandRespRefDev", undef)) {
        if (AttrVal($name, "demandRespRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name demandRespRefDev");
        }
      }
      #Log3($name, 5, "EnOcean $name <notify> DELETED $1");

    } elsif ($devName eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      my $definedName = $1;
      if ($name eq $definedName) {
        if (exists $attr{$name}{subType}) {
          if ($attr{$name}{subType} =~ m/^hvac\.0(1|4|6)$/) {
            # control PID regulatior
            if (AttrVal($name, 'pidCtrl', 'on') eq 'on' && ReadingsVal($name, 'maintenanceMode', 'off') eq 'off') {
              EnOcean_setPID(undef, $hash, 'start', ReadingsVal($name, "setpoint", undef));
            } else {
              EnOcean_setPID(undef, $hash, 'stop', undef);
            }
          } elsif ($attr{$name}{subType} eq 'environmentApp' && AttrVal($name, 'devMode', 'slave') eq 'master') {
            @{$hash->{helper}{periodic}{time}} = ($hash, 'time', $attr{$name}{sendTimePeriodic}, 30, -1, undef);
            EnOcean_SndPeriodic($hash->{helper}{periodic}{time});
          }
        }
      }
      # teach-in response actions
      # delete temporary teach-in response device, see V9333_02
      #Log3($name, 2, "EnOcean $name <notify> DEFINED $definedName");

    } elsif ($devName eq "global" && $s =~ m/^INITIALIZED$/) {
      # assign remote management defptr
      if (exists $attr{$name}{remoteID}) {
        $modules{EnOcean}{defptr}{$attr{$name}{remoteID}} = $hash;
      }
      if (AttrVal($name ,"subType", "") eq "roomCtrlPanel.00") {
        CommandDeleteReading(undef, "$name waitingCmds");
      }
      if (exists $attr{$name}{subType}) {
        if ($attr{$name}{subType} =~ m/^hvac\.0(1|4|6)$/) {
          # control PID regulatior
          if (AttrVal($name, 'pidCtrl', 'on') eq 'on' && ReadingsVal($name, 'maintenanceMode', 'off') eq 'off') {
            EnOcean_setPID(undef, $hash, 'start', ReadingsVal($name, "setpoint", undef));
          } else {
            EnOcean_setPID(undef, $hash, 'stop', undef);
          }
        } elsif ($attr{$name}{subType} eq 'environmentApp' && AttrVal($name, 'devMode', 'slave') eq 'master') {
          @{$hash->{helper}{periodic}{time}} = ($hash, 'time', $attr{$name}{sendTimePeriodic}, 30, -1, undef);
          EnOcean_SndPeriodic($hash->{helper}{periodic}{time});
        } elsif ($attr{$name}{subType} eq "switch.05") {
          my @getCmd = ($name, 'state');
          EnOcean_Get($hash, @getCmd);
        }
      }

      EnOcean_ReadDevDesc(undef, $hash);
      #Log3($name, 2, "EnOcean $name <notify> INITIALIZED");

    } elsif ($devName eq "global" && $s =~ m/^REREADCFG$/) {
      # assign remote management defptr
      if (exists $attr{$name}{remoteID}) {
        $modules{EnOcean}{defptr}{$attr{$name}{remoteID}} = $hash;
      }
      if (AttrVal($name ,"subType", "") eq "roomCtrlPanel.00") {
        CommandDeleteReading(undef, "$name waitingCmds");
      }
      if (exists $attr{$name}{subType}) {
        if ($attr{$name}{subType} =~ m/^hvac\.0(1|4|6)$/) {
          # control PID regulatior
          if (AttrVal($name, 'pidCtrl', 'on') eq 'on' && ReadingsVal($name, 'maintenanceMode', 'off') eq 'off') {
            EnOcean_setPID(undef, $hash, 'start', ReadingsVal($name, "setpoint", undef));
          } else {
            EnOcean_setPID(undef, $hash, 'stop', undef);
          }
        } elsif ($attr{$name}{subType} eq 'environmentApp' && AttrVal($name, 'devMode', 'slave') eq 'master') {
          @{$hash->{helper}{periodic}{time}} = ($hash, 'time', $attr{$name}{sendTimePeriodic}, 30, -1, undef);
          EnOcean_SndPeriodic($hash->{helper}{periodic}{time});
        }
      }

      EnOcean_ReadDevDesc(undef, $hash);
      #Log3($name, 2, "EnOcean $name <notify> REREADCFG");

    } elsif ($devName eq "global" && $s =~ m/^ATTR ([^ ]*) ([^ ]*) ([^ ]*)$/) {
      my ($sdev, $attrName, $attrVal) = ($1, $2, $3);
      #Log3 $name, 5, "EnOcean $name <notify> ATTR $1 $2 $3";
      if ($name eq $sdev && $attrName =~ m/^subDef.?/ && $attrVal eq "getNextID") {
        $attr{$name}{$attrName} = '0' x 8;
        $attr{$name}{$attrName} = EnOcean_CheckSenderID("getNextID", $defs{$name}{IODev}{NAME}, "00000000");
        Log3 $name, 2, "EnOcean set $name attribute $attrName to " . $attr{$name}{$attrName};
      } elsif ($attrName eq "devChannel" && $attrVal =~ m/^[\dA-Fa-f]{2}$/) {
        # convert old format
        $attr{$name}{$attrName} = hex $attrVal;
      }

    } elsif ($devName eq "global" && $s =~ m/^DELETEATTR ([^ ]*)$/) {
      #Log3($name, 5, "EnOcean $name <notify> DELETEATTR $1");

    } elsif ($devName eq "global" && $s =~ m/^MODIFIED ([^ ]*)$/) {
      #Log3($name, 5, "EnOcean $name <notify> MODIFIED");

    } elsif ($devName eq "global" && $s =~ m/^SAVE$/) {
      #Log3($name, 5, "EnOcean $name <notify> SAVE");

    } elsif ($devName eq "global" && $s =~ m/^SHUTDOWN$/) {
      #Log3($name, 5, "EnOcean $name <notify> SHUTDOWN");

    } else {
      my @parts = split(/: | /, $s);

      if (defined AttrVal($name, "observeRefDev", undef)) {
        my @observeRefDev = split("[ \t][ \t]*", AttrVal($name, "observeRefDev", undef));
        if (grep /^$devName$/, @observeRefDev) {
          my ($reading, $value) = ("", "");
          $reading = shift @parts;
          if (!defined($parts[0]) || @parts > 1) {
            $value = $s;
            $reading = "state";
          } else {
            $value = $parts[0];
          }
          my @cmdObserve = ($devName, $reading, $value);
          EnOcean_observeParse(2, $hash, @cmdObserve);
          #Log3($name, 5, "EnOcean $name <notify> observeRefDev: $devName $reading: $value");
        }
      }

      if (defined AttrVal($name, "demandRespRefDev", undef)) {
        my @demandRespRefDev = split("[ \t][ \t]*", AttrVal($name, "demandRespRefDev", undef));
        if (grep /^$devName$/, @demandRespRefDev) {
          my @cmdDemandResponse;
          my $actionCmd = AttrVal($name, "demandRespAction", undef);
          if (defined $actionCmd) {
            if ($parts[0] =~ m/^on|off$/) {
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set $parts[0]");
              my %specials = ("%TARGETNAME" => $name,
                              "%NAME" => $devName,
                              "%TARGETTYPE" => $hash->{TYPE},
                              "%TYPE" => $dev->{TYPE},
                              "%LEVEL" => ReadingsVal($devName, "level", 15),
                              "%SETPOINT" => ReadingsVal($devName, "setpoint", 255),
                              "%POWERUSAGE" => ReadingsVal($devName, "powerUsage", 100),
                              "%POWERUSAGESCALE" => ReadingsVal($devName, "powerUsageScale", "max"),
                              "%POWERUSAGELEVEL" => ReadingsVal($devName, "powerUsageLevel", "max"),
                              "%TARGETSTATE" => ReadingsVal($name, "state", ""),
                              "%STATE" => ReadingsVal($devName, "state", "off")
                             );
              # action exec
              $actionCmd = EvalSpecials($actionCmd, %specials);
              my $ret = AnalyzeCommandChain(undef, $actionCmd);
              Log3 $name, 2, "EnOcean $name demandRespAction ERROR: $ret" if($ret);
            }

          } elsif (AttrVal($name, "subType", "") =~ m/^switch.*$/ || AttrVal($name, "subTypeSet", "") =~ m/^switch.*$/) {
            if ($parts[0] eq "powerUsageLevel" && $parts[1] eq "max") {
              @cmdDemandResponse = ($name, AttrVal($name, "demandRespMax", "B0"));
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            } elsif ($parts[0] eq "powerUsageLevel" && $parts[1] eq "min") {
              @cmdDemandResponse = ($name, AttrVal($name, "demandRespMin", "BI"));
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif (AttrVal($name, "subType", "") eq "gateway" && AttrVal($name, "gwCmd", "") eq "switching") {
            if ($parts[0] eq "powerUsageLevel" && $parts[1] eq "max") {
              @cmdDemandResponse = ($name, "on");
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            } elsif ($parts[0] eq "powerUsageLevel" && $parts[1] eq "min") {
              @cmdDemandResponse = ($name, "off");
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif ((AttrVal($name, "subType", "") eq "gateway" && AttrVal($name, "gwCmd", "") eq "dimming")
                   || AttrVal($name, "subType", "") eq "actuator.01") {
            if ($parts[0] eq "powerUsage") {
              if (ReadingsVal($devName, "powerUsageScale", "max") eq "rel") {
                @cmdDemandResponse = ($name, "dim", $parts[1] * ReadingsVal($name, "dimValueLast", 100) / 100);
              } else {
                @cmdDemandResponse = ($name, "dim", $parts[1]);
              }
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif ((AttrVal($name, "subType", "") eq "roomSensorControl.05" && AttrVal($name, "manufID", "") eq "00D")) {
            if ($parts[0] eq "level") {
              @cmdDemandResponse = ($name, "nightReduction", int(5 - 1/3 * $parts[1]));
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif (AttrVal($name, "subType", "") eq "lightCtrl.01") {
            if ($parts[0] eq "setpoint") {
              @cmdDemandResponse = ($name, "dim", $parts[1]);
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.01") {
            if ($parts[0] eq "setpoint") {
              @cmdDemandResponse = ($name, "setpoint", $parts[1]);
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.05") {
            if ($parts[0] eq "setpoint") {
              @cmdDemandResponse = ($name, $parts[0], $parts[1]);
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }

          } elsif (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
            if ($parts[0] eq "powerUsageLevel" && $parts[1] eq "max") {
              @cmdDemandResponse = ($name, "roomCtrlMode", "comfort");
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            } elsif ($parts[0] eq "powerUsageLevel" && $parts[1] eq "min") {
              @cmdDemandResponse = ($name, "roomCtrlMode", "economy");
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);
            }
          }
        }
      }

      if (defined(AttrVal($name, "humidityRefDev", undef)) && AttrVal($name, "setCmdTrigger", "man") eq "refDev") {
        if ($devName eq AttrVal($name, "humidityRefDev", "")) {
          if ($parts[0] eq "humidity") {
            if (AttrVal($name, "subType", "") eq "roomSensorControl.01") {
              my @setCmd = ($name, "setpoint");
              EnOcean_Set($hash, @setCmd);
            }
          }
        }
      #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
      }

      if (defined(AttrVal($name, "temperatureRefDev", undef)) && AttrVal($name, "setCmdTrigger", "man") eq "refDev") {
        # sent a setpoint or setpointTemp telegram
        if ($devName eq AttrVal($name, "temperatureRefDev", "")) {
          if ($parts[0] eq "temperature") {
            if (AttrVal($name, "subType", "") eq "roomSensorControl.05" && AttrVal($name, "manufID", "") eq "00D") {
              my @setCmd = ($name, "setpointTemp");
              EnOcean_Set($hash, @setCmd);
            } elsif (AttrVal($name, "subType", "") eq "fanCtrl.00") {
              my @setCmd = ($name, "setpointTemp");
              EnOcean_Set($hash, @setCmd);
            } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.01") {
              my @setCmd = ($name, "setpoint");
              EnOcean_Set($hash, @setCmd);
            } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.05") {
              my @setCmd = ($name, "setpoint");
              EnOcean_Set($hash, @setCmd);
            }
          }
        }
      #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
      }

      if (defined(AttrVal($name, "temperatureRefDev", undef)) &&
          $devName eq AttrVal($name, "temperatureRefDev", "") &&
          $parts[0] eq "temperature") {
        if (AttrVal($name, "subType", "") =~ m/^hvac\.0(1|4|6)$/) {
          readingsSingleUpdate($hash, "temperature", $parts[1], 1);
          #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
        }
      }

      if (defined(AttrVal($name, "setpointRefDev", undef)) &&
          $devName eq AttrVal($name, "setpointRefDev", "") &&
          $parts[0] eq "setpoint") {
        if (AttrVal($name, "subType", '') =~ m/^hvac\.0(1|4|6)$/) {
          my @setCmd = ($name, "setpoint", $parts[1]);
          EnOcean_Set($hash, @setCmd);
          #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
        }
      }

      if (defined(AttrVal($name, "setpointTempRefDev", undef)) &&
          $devName eq AttrVal($name, "setpointTempRefDev", "") &&
          $parts[0] eq "setpointTemp") {
        if (AttrVal($name, "subType", '') =~ m/^hvac\.0(1|4|6)$/) {
          if (ReadingsVal($name, "setpointTemp", 0) != $parts[1]) {
            my @setCmd = ($name, "setpointTemp", $parts[1]);
            EnOcean_Set($hash, @setCmd);
            #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
          }
        }
      }

    }
  }
  return undef;
}

sub EnOcean_swayCtrl($$$$$$$$$$$) {
  # sway range and delay calculation
  my ($hash, $readingName, $readingVal, $attrNameRange, $attrNameDelay, $swayRangeLow, $swayRangeHigh, $swayDelayLow, $swayDelayHigh, $swayRangeLowVal, $swayRangeHighVal) = @_;
  my ($swayRangeLowAttr, $swayRangeHighAttr) = split(':', AttrVal($hash->{NAME}, $attrNameRange, "$swayRangeLow:$swayRangeHigh"));
  my ($swayDelayLowAttr, $swayDelayHighAttr) = split(':', AttrVal($hash->{NAME}, $attrNameDelay, "$swayDelayLow:$swayDelayHigh"));
  my $swayValLast = exists($hash->{helper}{sway}{$readingName}) ? $hash->{helper}{sway}{$readingName} : $swayRangeLowVal;
  my $swayVal = $swayValLast;
  if (!defined($swayRangeLowAttr) && !defined($swayRangeHighAttr)) {
    $swayRangeLowAttr = $swayRangeLow;
    $swayRangeHighAttr = $swayRangeHigh;
  } elsif (!defined($swayRangeLowAttr) && $swayRangeHighAttr eq '' || !defined($swayRangeHighAttr) && $swayRangeLowAttr eq '') {
    $swayRangeLowAttr = $swayRangeLow;
    $swayRangeHighAttr = $swayRangeHigh;
  } elsif ($swayRangeHighAttr eq '' && $swayRangeLowAttr eq '') {
    $swayRangeLowAttr = $swayRangeLow;
    $swayRangeHighAttr = $swayRangeHigh;
  } elsif ($swayRangeLowAttr eq '') {
    $swayRangeLowAttr = $swayRangeHighAttr;
  } elsif ($swayRangeHighAttr eq '') {
    $swayRangeHighAttr = $swayRangeLowAttr;
  }
  ($swayRangeLowAttr, $swayRangeHighAttr) = ($swayRangeHighAttr, $swayRangeLowAttr) if ($swayRangeLowAttr > $swayRangeHighAttr);
  if ($readingVal < $swayRangeLowAttr) {
    $swayVal = $swayRangeLowVal;
  } elsif ($readingVal >= $swayRangeHighAttr) {
    $swayVal = $swayRangeHighVal;
  } elsif ($readingVal >= $swayRangeLowAttr && $swayVal eq $swayRangeLowVal) {
    $swayVal = $swayRangeLowVal;
  } elsif ($readingVal < $swayRangeHighAttr && $swayVal eq $swayRangeHighVal) {
    $swayVal = $swayRangeHighVal;
  }
  if (!defined($swayDelayLowAttr) && !defined($swayDelayHighAttr)) {
    $swayDelayLowAttr = $swayDelayLow;
    $swayDelayHighAttr = $swayDelayHigh;
  } elsif (!defined($swayDelayLowAttr) && $swayDelayHighAttr eq '' || !defined($swayDelayHighAttr) && $swayDelayLowAttr eq '') {
    $swayDelayLowAttr = $swayDelayLow;
    $swayDelayHighAttr = $swayDelayHigh;
  } elsif ($swayDelayHighAttr eq '' && $swayDelayLowAttr eq '') {
    $swayDelayLowAttr = $swayDelayLow;
    $swayDelayHighAttr = $swayDelayHigh;
  } elsif ($swayDelayLowAttr eq '') {
    $swayDelayLowAttr = $swayDelayHighAttr;
  } elsif ($swayDelayHighAttr eq '') {
    $swayDelayHighAttr = $swayDelayLowAttr;
  }
  if ($swayVal eq $swayValLast) {
    $hash->{helper}{sway}{$readingName} = $swayVal;
    if (exists $hash->{helper}{timer}{sway}{$readingName}{delay}) {
      # clear timer as sway reverses
      RemoveInternalTimer($hash->{helper}{timer}{sway}{$readingName}{delay});
      delete $hash->{helper}{timer}{sway}{$readingName}{delay};
    }
  } else {
    $hash->{helper}{sway}{$readingName} = $swayValLast;
    my $swayDelay = $swayVal eq $swayRangeHighVal ? $swayDelayHighAttr : $swayDelayLowAttr;
    if (exists $hash->{helper}{timer}{sway}{$readingName}{delay}) {
      $swayVal = $swayValLast;
    } elsif ($swayDelay > 0) {
      @{$hash->{helper}{timer}{sway}{$readingName}{delay}} = ($hash, $readingName, $swayVal, $swayDelay, 1, 5, 1);
      InternalTimer(gettimeofday() + $swayDelay, 'EnOcean_swayCtrlDelay', $hash->{helper}{timer}{sway}{$readingName}{delay}, 0);
      $swayVal = $swayValLast;
    }
  }
  return $swayVal;
}

sub EnOcean_swayCtrlDelay($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $delay, $ctrl, $log, $clear) = @$readingParam;
  if (defined $hash) {
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl);
    Log3 $hash->{NAME}, $log, " EnOcean " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
    $hash->{helper}{sway}{$readingName} = $readingVal;
    delete $hash->{helper}{timer}{sway}{$readingName}{delay} if ($clear == 1);
  }
  return;
}

# ADT encapsulation
sub
EnOcean_Encapsulation($$$$)
{
  my ($packetType, $rorg, $data, $destinationID) = @_;
  if ($destinationID eq "FFFFFFFF") {
    return ($rorg, $data);
  } else {
    $data = $rorg . $data;
    return ("A6", $data);
  }
}

# set PID regulator
sub EnOcean_setPID($$$$) {
  my ($ctrl, $hash, $cmd, $adjust) = @_;
  my $name = $hash->{NAME};
  my ($err, $response, $logLevel) = (undef, 'start', 5);
  @{$hash->{helper}{calcPID}} = (undef, $hash, $cmd, $adjust);
  if ($cmd eq 'stop' || AttrVal($name, 'pidCtrl', 'on') eq 'off') {
    $hash->{helper}{stopped} = 1;
    readingsSingleUpdate($hash, "pidState", 'stopped', 0);
    RemoveInternalTimer($hash->{helper}{calcPID});
    $response = 'stopped';
  } elsif ($cmd eq 'start' || $cmd eq 'actuator') {
    $hash->{helper}{stopped} = 0;
    #$hash->{helper}{adjust}  = $adjust;
    RemoveInternalTimer($hash->{helper}{calcPID});
    ($err, $logLevel, $response) = EnOcean_calcPID($hash->{helper}{calcPID});
  }
  return ($err, $logLevel, $response);
}

# calc valve setpoint (PID regulator)
sub EnOcean_calcPID($) {
  my ($pidParam) = @_;
  my ($ctrl, $hash, $cmd, $adjust) = @$pidParam;
  my $name = $hash->{NAME};
  my ($err, $response, $logLevel, $setpoint) = (undef, $cmd, 5, 0);
  my $reUINT     = '^([\\+]?\\d+)$';               # uint without whitespaces
  my $re01       = '^([0,1])$';                    # only 0,1
  my $reINT      = '^([\\+,\\-]?\\d+$)';           # int
  my $reFloatpos = '^([\\+]?\\d+\\.?\d*$)';        # gleitpunkt positiv float
  my $reFloat    = '^([\\+,\\-]?\\d+\\.?\d*$)';    # float
  my $sensor  = $name;
  my $reading = 'temperature';
  my $regexp  = $reFloat;
  my $DEBUG_Sensor    = AttrVal( $name, 'pidDebugSensor',    '0' ) eq '1';
  my $DEBUG_Actuation = AttrVal( $name, 'pidDebugActuation', '0' ) eq '1';
  my $DEBUG_Delta     = AttrVal( $name, 'pidDebugDelta',     '0' ) eq '1';
  my $DEBUG_Calc      = AttrVal( $name, 'pidDebugCalc',      '0' ) eq '1';
  my $DEBUG_Update    = AttrVal( $name, 'pidDebugUpdate',    '0' ) eq '1';
  my $DEBUG = $DEBUG_Sensor || $DEBUG_Actuation || $DEBUG_Calc || $DEBUG_Delta || $DEBUG_Update;
  my $actuation        = "";
  my $actuationDone    = ReadingsVal( $name, 'setpointSet', ReadingsVal( $name, 'setpoint', ""));
  my $actuationCalc    = ReadingsVal( $name, 'setpointCalc', "" );
  my $actuationCalcOld = $actuationCalc;
  my $actorTimestamp =
    ( $hash->{helper}{actorTimestamp} )
    ? $hash->{helper}{actorTimestamp}
    : FmtDateTime( gettimeofday() - 3600 * 24 );
  my $desired = '';
  my $sensorStr = ReadingsVal($name, 'temperature',"");
  my $sensorValue = "";
  my $sensorTS = ReadingsTimestamp($name, 'temperature', undef);
  my $sensorIsAlive = 0;
  my $iPortion = ReadingsVal( $name, 'p_i',   0 );
  my $pPortion = ReadingsVal( $name, 'p_p',   "" );
  my $dPortion = ReadingsVal( $name, 'p_d',   "" );
  my $stateStr = "";
  CommandDeleteReading(undef, "$name pidAlarm");
  my $deltaOld = ReadingsVal( $name, 'delta', 0 );
  my $delta    = "";
  my $deltaGradient    = ( $hash->{helper}{deltaGradient} ) ? $hash->{helper}{deltaGradient} : 0;
  my $calcReq          = 0;
  my $readingUpdateReq = '';

  # ---------------- check conditions
  while (1)
  {
    # --------------- retrive values from attributes
    my $wakeUpCycle = AttrVal($name, 'wakeUpCycle', ReadingsVal($name, 'wakeUpCycle', 300));
    my $pidCycle = $wakeUpCycle / 3;
    $pidCycle = 10 if ($pidCycle < 10);
    $hash->{helper}{actorInterval}  = 10;
    $hash->{helper}{actorThreshold} = 0;
    $hash->{helper}{actorKeepAlive} = $pidCycle;
    $hash->{helper}{actorValueDecPlaces} = 0;
    $hash->{helper}{actorErrorAction} = AttrVal($name, 'pidActorErrorAction', 'freeze');
    $hash->{helper}{actorErrorPos} = AttrVal($name, 'pidActorErrorPos',  0);
    $hash->{helper}{calcInterval} = $pidCycle;
    $hash->{helper}{deltaTreshold} = AttrVal($name, 'pidDeltaTreshold', 0);
    if (AttrVal($name, 'measurementCtrl', 'enable') eq 'enable') {
      $hash->{helper}{sensorTimeout} = $wakeUpCycle * 4;
    } else {
      $hash->{helper}{sensorTimeout} = AttrVal($name, 'pidSensorTimeout', 3600);
    }
    $hash->{helper}{reverseAction} = 0;
    $hash->{helper}{updateInterval} = $pidCycle;
    $hash->{helper}{actorLimitLower} = AttrVal($name, 'pidActorLimitLower', 0);
    my $actorLimitLower = $hash->{helper}{actorLimitLower};
    $hash->{helper}{actorLimitUpper} = AttrVal($name, 'pidActorLimitUpper', 100);
    my $actorLimitUpper = $hash->{helper}{actorLimitUpper};
    $hash->{helper}{factor_P} = AttrVal($name, 'pidFactor_P', 25);
    $hash->{helper}{factor_I} = AttrVal($name, 'pidFactor_I', 0.25);
    $hash->{helper}{factor_D} = AttrVal($name, 'pidFactor_D', 0);

    if ($hash->{helper}{stopped}) {
      $stateStr = "stopped";
      last;
    }

    $desired = ReadingsVal( $name, 'setpointTempSet', ReadingsVal($name, 'setpointTemp', ""));
    #my $desired = ReadingsVal( $name, $hash->{helper}{desiredName}, "" );

    # sensor found
    #PID20_Log $hash, 2, "--------------------------" if ($DEBUG);
    #PID20_Log $hash, 2, "S1 sensorStr:$sensorStr sensorTS:$sensorTS" if ($DEBUG_Sensor);
    if ( !$sensorStr && !$stateStr ) {
      $stateStr = "alarm";
      $err = 'no_temperature_value';
    }

    # sensor alive
    if ( $sensorStr && $sensorTS )
    {
      my $timeDiff = EnOcean_TimeDiff($sensorTS);
      $sensorIsAlive = 1 if ( $timeDiff <= $hash->{helper}{sensorTimeout} );
      $sensorStr =~ m/$regexp/;
      $sensorValue = $1;
      $sensorValue = "" if ( !defined($sensorValue) );
      #PID20_Log $hash, 2,
      #    "S2 timeOfDay:"
      #  . gettimeofday()
      #  . " timeDiff:$timeDiff sensorTimeout:"
      #  . $hash->{helper}{sensorTimeout}
      #  . " --> sensorIsAlive:$sensorIsAlive"
      #  if ($DEBUG_Sensor);
    }

    # sensor dead
    if (!$sensorIsAlive && !$stateStr) {
      $stateStr = "alarm";
      $err = 'dead_sensor';
    }

    # missing desired
    if ($desired eq "" && !$stateStr) {
      $stateStr = "alarm";
      $err = 'setpoint_device_missing';
    }

    # check delta threshold
    $delta = ( $desired ne "" && $sensorValue ne "" ) ? $desired - $sensorValue : "";
    $calcReq = 1 if ( !$stateStr && $delta ne "" && ( abs($delta) >= abs( $hash->{helper}{deltaTreshold} ) ) );

    #PID20_Log $hash, 2,
    #    "D1 desired[" . ( $desired ne "" ) ? sprintf( "%.1f", $desired )
    #  : "" . "] - sensorValue: [" . ( $sensorValue ne "" ) ? sprintf( "%.1f", $sensorValue )
    #  : "" . "] = delta[" .         ( $delta ne "" )       ? sprintf( "%.2f", $delta )
    #  : "" . "] calcReq:$calcReq"
    #  if ($DEBUG_Delta);

    #request for calculation
    # ---------------- calculation request
    if ($calcReq)
    {
      # reverse action requested
      my $workDelta = ( $hash->{helper}{reverseAction} == 1 ) ? -$delta : $delta;
      my $deltaOld = -$deltaOld if ( $hash->{helper}{reverseAction} == 1 );

      # calc p-portion
      $pPortion = $workDelta * $hash->{helper}{factor_P};

      # calc d-Portion
      $dPortion = ($deltaGradient) * $hash->{helper}{calcInterval} * $hash->{helper}{factor_D};

      # calc i-portion respecting windUp
      # freeze i-portion if windUp is active
      my $isWindup = $actuationCalcOld
        && ( ( $workDelta > 0 && $actuationCalcOld > $actorLimitUpper )
        || ( $workDelta < 0 && $actuationCalcOld < $actorLimitLower ) );
      $hash->{helper}{adjust} = $adjust if(defined $adjust);
      if (defined $hash->{helper}{adjust}) {
        $iPortion = $hash->{helper}{adjust} - ( $pPortion + $dPortion );
        $iPortion = $actorLimitUpper if ( $iPortion > $actorLimitUpper );
        $iPortion = $actorLimitLower if ( $iPortion < $actorLimitLower );
        #PID20_Log $hash, 5, "adjust request with:" . $hash->{helper}{adjust} . " ==> p_i:$iPortion";
        delete $hash->{helper}{adjust};
      } elsif ( !$isWindup )    # integrate only if no windUp
      {
        # normalize the intervall to minute=60 seconds
        $iPortion = $iPortion + $workDelta * $hash->{helper}{factor_I} * $hash->{helper}{calcInterval} / 60;
        $hash->{helper}{isWindUP} = 0;
      }

      $hash->{helper}{isWindUP} = $isWindup;

      # check callback for iPortion
      my $iportionCallBeforeSetting = AttrVal( $name, 'pidIPortionCallBeforeSetting', undef );
      if ( defined($iportionCallBeforeSetting) && exists &$iportionCallBeforeSetting )
      {
        #PID20_Log $hash, 5, 'start callback ' . $iportionCallBeforeSetting . ' with iPortion:' . $iPortion;
        no strict "refs";
        $iPortion = &$iportionCallBeforeSetting( $name, $iPortion );
        use strict "refs";
        #PID20_Log $hash, 5, 'return value of ' . $iportionCallBeforeSetting . ':' . $iPortion;
      }

      # calc actuation
      $actuationCalc = $pPortion + $iPortion + $dPortion;

      #PID20_Log $hash, 2, "P1 delta:" . sprintf( "%.2f", $delta ) . " isWindup:$isWindup" if ($DEBUG_Calc);

      #PID20_Log $hash, 2,
      #    "P2 pPortion:"
      #  . sprintf( "%.2f", $pPortion )
      #  . " iPortion:"
      #  . sprintf( "%.2f", $iPortion )
      #  . " dPortion:"
      #  . sprintf( "%.2f", $dPortion )
      #  . " actuationCalc:"
      #  . sprintf( "%.2f", $actuationCalc )
      #  if ($DEBUG_Calc);
    }

    $readingUpdateReq = 1;    # in each case update readings

    # ---------------- acutation request
    my $noTrouble = ( $desired ne "" && $sensorIsAlive );

    # check actor fallback in case of sensor fault
    if (!$sensorIsAlive && ($hash->{helper}{actorErrorAction} eq "errorPos")) {
      #$stateStr .= "- force pid-output to errorPos";
      $err .= ':actuator_in_errorPos';
      $actuationCalc = $hash->{helper}{actorErrorPos};
      $actuationCalc = "" if ( !defined($actuationCalc) );
    }

    # check acutation diff
    $actuation = $actuationCalc;

    # limit $actuation
    $actuation = $actorLimitUpper if ( $actuation ne "" && ( $actuation > $actorLimitUpper ) );
    $actuation = $actorLimitLower if ( $actuation ne "" && ( $actuation < $actorLimitLower ) );

    # check if round request
    my $fmt = "%." . $hash->{helper}{actorValueDecPlaces} . "f";
    $actuation = sprintf( $fmt, $actuation ) if ( $actuation ne "" );
    my $actuationDiff = abs( $actuation - $actuationDone )
      if ( $actuation ne "" && $actuationDone ne "" );
    #PID20_Log $hash, 2,
    #    "A1 act:$actuation actDone:$actuationDone "
    #  . " actThreshold:"
    #  . $hash->{helper}{actorThreshold}
    #  . " actDiff:$actuationDiff"
    #  if ($DEBUG_Actuation);

    # check threshold-condition for actuation
    my $rsTS = $actuationDone ne "" && $actuationDiff >= $hash->{helper}{actorThreshold};

    # ...... special handling if acutation is in the black zone between actorLimit and (actorLimit - actorThreshold)
    # upper range
    my $rsUp =
         $actuationDone ne ""
      && $actuation > $actorLimitUpper - $hash->{helper}{actorThreshold}
      && $actuationDiff != 0
      && $actuation >= $actorLimitUpper;

    # low range
    my $rsDown =
         $actuationDone ne ""
      && $actuation < $actorLimitLower + $hash->{helper}{actorThreshold}
      && $actuationDiff != 0
      && $actuation <= $actorLimitLower;

    # upper or lower limit are exceeded
    my $rsLimit = $actuationDone ne "" && ( $actuationDone < $actorLimitLower || $actuationDone > $actorLimitUpper );

    my $actuationByThreshold = ( ( $rsTS || $rsUp || $rsDown ) && $noTrouble );
    #PID20_Log $hash, 2, "A2 rsTS:$rsTS rsUp:$rsUp rsDown:$rsDown noTrouble:$noTrouble"
    #  if ($DEBUG_Actuation);

    # check time condition for actuation
    my $actTimeDiff = EnOcean_TimeDiff($actorTimestamp);    # $actorTimestamp is valid in each case
    my $actuationByTime = ($noTrouble) && ( $actTimeDiff > $hash->{helper}{actorInterval} );
    #PID20_Log $hash, 2,
    #    "A3 actTS:$actorTimestamp"
    #  . " actTimeDiff:"
    #  . sprintf( "%.2f", $actTimeDiff )
    #  . " actInterval:"
    #  . $hash->{helper}{actorInterval}
    #  . "-->actByTime:$actuationByTime "
    #  if ($DEBUG_Actuation);

    # check keep alive condition for actuation
    my $actuationKeepAliveReq = ( $actTimeDiff >= $hash->{helper}{actorKeepAlive} )
      if ( defined($actTimeDiff) && $actuation ne "" );

    # build total actuation request
    my $actuationReq = (
      ( $actuationByThreshold && $actuationByTime )
        || $actuationKeepAliveReq    # request by keep alive
        || $rsLimit                  # upper or lower limit are exceeded
        || $actuationDone eq ""      # startup condition
    ) && $actuation ne "";           # acutation is initialized

    #PID20_Log $hash, 2,
    #    "A4 (actByTh:$actuationByThreshold && actByTime:$actuationByTime)"
    #  . "||actKeepAlive:$actuationKeepAliveReq"
    #  . "||rsLimit:$rsLimit=actnReq:$actuationReq"
    #  if ($DEBUG_Actuation);

    # ................ perform output to actor
    if ($actuationReq)
    {
      $readingUpdateReq = 1;         # update the readings

      # check calback for actuation
      my $actorCallBeforeSetting = AttrVal( $name, 'pidActorCallBeforeSetting', undef );
      if ( defined($actorCallBeforeSetting) && exists &$actorCallBeforeSetting )
      {
        #PID20_Log $hash, 5, 'start callback ' . $actorCallBeforeSetting . ' with actuation:' . $actuation;
        no strict "refs";
        $actuation = &$actorCallBeforeSetting( $name, $actuation );
        use strict "refs";
        #PID20_Log $hash, 5, 'return value of ' . $actorCallBeforeSetting . ':' . $actuation;
      }

      #build command for fhem
      #PID20_Log $hash, 5,
      #    "actor:"
      #  . $hash->{helper}{actor}
      #  . " actorCommand:"
      #  . $hash->{helper}{actorCommand}
      #  . " actuation:"
      #  . $actuation;
      #my $cmd = sprintf( "set %s %s %g", $hash->{helper}{actor}, $hash->{helper}{actorCommand}, $actuation );

      # execute command
      my $ret;
      #$ret = fhem $cmd;

      $setpoint = $actuation;
      $actuationDone = $actuation;

      # note timestamp
      $hash->{helper}{actorTimestamp} = TimeNow();
      my $retStr = "";
      $retStr = " with return-value:" . $ret if ( defined($ret) && ( $ret ne '' ) );
      #PID20_Log $hash, 3, "<$cmd> " . $retStr;
    }
  # my $updateAlive = ($actuation ne "")
  #   && EnOcean_TimeDiff(ReadingsTimestamp($name, 'setpointSet', ReadingsTimestamp($name, 'setpoint', undef))) >= $hash->{helper}{updateInterval};
  #   && EnOcean_TimeDiff( ReadingsTimestamp( $name, 'setpointSet', gettimeofday() ) ) >= $hash->{helper}{updateInterval};
  # my $updateReq = ( ( $actuationReq || $updateAlive ) && $actuation ne "" );
  # PID20_Log $hash, 2, "U1 actReq:$actuationReq updateAlive:$updateAlive -->  updateReq:$updateReq" if ($DEBUG_Update);

    # ---------------- update request
    if ($readingUpdateReq) {
      readingsBeginUpdate($hash);
      #readingsBulkUpdate( $hash, $hash->{helper}{desiredName},  $desired )       if ( $desired ne "" );
      #readingsBulkUpdate( $hash, $hash->{helper}{measuredName}, $sensorValue )   if ( $sensorValue ne "" );
      readingsBulkUpdate( $hash, 'p_p', $pPortion ) if ( $pPortion ne "" );
      readingsBulkUpdate( $hash, 'p_d', $dPortion ) if ( $dPortion ne "" );
      readingsBulkUpdate( $hash, 'p_i', $iPortion ) if ( $iPortion ne "" );
      readingsBulkUpdate( $hash, 'setpointSet', $actuationDone) if ($actuationDone ne "");
      readingsBulkUpdate( $hash, 'setpointCalc', $actuationCalc) if ( $actuationCalc ne "" );
      readingsBulkUpdate( $hash, 'delta', $delta ) if ( $delta ne "" );
      readingsEndUpdate( $hash, 1 );
      #PID20_Log $hash, 5, "readings updated";
    }

    last;
  }    # end while

  # ........ update statePID.
  $stateStr = 'idle' if ($stateStr eq '' && !$calcReq);
  $stateStr = 'processing' if ($stateStr eq '' && $calcReq);
  #PID20_Log $hash, 2, "C1 stateStr:$stateStr calcReq:$calcReq" if ($DEBUG_Calc);

  #......... timer setup
  #my $next = gettimeofday() + $hash->{helper}{calcInterval};
  #RemoveInternalTimer($name);    # prevent multiple timers for same hash
  #InternalTimer( $next, "PID20_Calc", $name, 1 );

  #PID20_Log $hash, 2, "InternalTimer next:".FmtDateTime($next)." PID20_Calc name:$name DEBUG_Calc:$DEBUG_Calc";

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'pidState', $stateStr);
  readingsBulkUpdate($hash, 'pidAlarm', $err) if (defined $err);
  readingsEndUpdate($hash, 1);
  Log3($name, 5, "EnOcean $name EnOcean_calcPID Cmd: $cmd pidState: $stateStr T: $sensorValue SP: $setpoint SPT: $desired");
  @{$hash->{helper}{calcPID}} = (undef, $hash, 'periodic', undef);
  RemoveInternalTimer($hash->{helper}{calcPID});
  InternalTimer(gettimeofday() + $hash->{helper}{calcInterval} * 1.02, "EnOcean_calcPID", $hash->{helper}{calcPID}, 0);
  return ($err, $logLevel, $response);
}

# sent message to Multisnesor Window Handle (EEP D2-06-01)
sub
EnOcean_multisensor_01Snd($$$)
{
  my ($ctrl, $hash, $packetType) = @_;
  my $name = $hash->{NAME};
  my ($data, $err, $response, $logLevel);

  EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
  return ($err, $response);
}

# sent message to Room Control Panel (EEP D2-10-xx)
sub
EnOcean_roomCtrlPanel_00Snd($$$$$$$$)
{
  my ($ctrl, $hash, $packetType, $mid, $mcf, $irc, $fbc, $gmt) = @_;
  my $name = $hash->{NAME};
  my ($data, $err, $response, $logLevel);
  my $messagePart = 1;

  if ($mid == 0) {
    # general massage
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

    if (!defined($irc)) {

    } elsif ($irc == 0) {
      # acknowledge request

    } elsif ($irc == 1) {
      # data request

    } elsif ($irc == 2) {
      # configuration request

    } elsif ($irc == 3) {
      # room control request

    } elsif ($irc == 4) {
      # time program request

    }

    if (!defined($fbc)) {

    } elsif ($fbc == 0) {
      # acknowledge / heartbeat

    } elsif ($fbc == 1) {
      # telegram repetition request

    } elsif ($fbc == 2) {
      # message repetition request

    } elsif ($fbc == 3) {
      # reserved

    }

    if (!defined($gmt)) {

    } elsif ($gmt == 0) {
      # information request

    } elsif ($gmt == 1) {
      # feetback

    }

  } elsif ($mid == 1) {
    # data message
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  } elsif ($mid == 2) {
    # configuration message
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  } elsif ($mid == 3) {
    # room control setup
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  } elsif ($mid == 4) {
    # time program setup
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  }

  return ($err, $response);
}

# generate command to Room Control Panel (EEP D2-10-xx)
sub
EnOcean_roomCtrlPanel_00Cmd($$$$)
{
  my ($ctrl, $hash, $mcf, $messagePart) = @_;
  my $name = $hash->{NAME};
  my $data = "0000";
  my $err;
  my $response = "acknowledge send";
  my $logLevel = 4;
  # Waitings Commands (waitingCmds)
  # 1 = sent data request
  # 2 = sent data message
  # 4 = sent configuration message (time)
  # 8 = sent room control setup
  # 16 = sent time program setup
  # 32 = sent configuration request
  # 64 = sent configuration message
  # 128 = sent room control setup request
  # 256 = sent time program request
  # 512 = sent delete time program
  my $waitingCmds = ReadingsVal($name, "waitingCmds", 0);
  if ($mcf == 0) {
    # message complete
    if ($waitingCmds & 8) {
      # room control setup waiting
      my ($db5, $db4, $db3, $db2, $db1, $db0) = (96, 0, 0, 0, 0, 0, 0);
      if (defined ReadingsVal($name, "setpointComfortTempSet", undef)) {
        $db1 = ReadingsVal($name, "setpointComfortTempSet", 0) * 255 / 40;
        $db0 = $db0 | 1;
        CommandDeleteReading(undef, "$name setpointComfortTempSet");
      }
      if (defined ReadingsVal($name, "setpointEconomyTempSet", undef)) {
        $db2 = ReadingsVal($name, "setpointEconomyTempSet", 0) * 255 / 40;
        $db0 = $db0 | 2;
        CommandDeleteReading(undef, "$name setpointEconomyTempSet");
      }
      if (defined ReadingsVal($name, "setpointPreComfortTempSet", undef)) {
        $db3 = ReadingsVal($name, "setpointPreComfortTempSet", 0) * 255 / 40;
        $db0 = $db0 | 4;
        CommandDeleteReading(undef, "$name setpointPreComfortTempSet");
      }
      if (defined ReadingsVal($name, "setpointBuildingProtectionTempSet", undef)) {
        $db4 = ReadingsVal($name, "setpointBuildingProtectionTempSet", 0) * 255 / 40;
        $db0 = $db0 | 8;
        CommandDeleteReading(undef, "$name setpointBuildingProtectionTempSet");
      }
      $data = sprintf "%02X%02X%02X%02X%02X%02X", $db5, $db4, $db3, $db2, $db1, $db0;
      # clear command
      $waitingCmds = $waitingCmds & 247 + 0xFF00;
      $response = "room control setup send $data";
      $logLevel = 2;

    } elsif ($waitingCmds & 64 || $waitingCmds & 4) {
      # configuration message waiting
      my ($sec, $min, $hour, $day, $month, $year) = localtime();
      my ($key, $val);
      $month += 1;
      $year += 1900;
      my ($db7, $db6, $db5, $db4, $db1, $db0) = (64, 0, 0, 0, $min << 2, $hour << 3);
      $db6 |= 1 if (AttrVal($name, "blockFanSpeed", "no") ne "yes" );
      $db6 |= 2 if (AttrVal($name, "blockSetpointTemp", "no") ne "yes" );
      $db6 |= 4 if (AttrVal($name, "blockOccupancy", "no") ne "yes" );
      $db6 |= 8 if (AttrVal($name, "blockTimeProgram", "no") ne "yes" );
      $db6 |= 16 if (AttrVal($name, "blockDateTime", "no") ne "yes" );
      $db6 |= 32 if (AttrVal($name, "blockDisplay", "no") ne "yes" );
      $db6 |= 64 if (AttrVal($name, "blockTemp", "no") ne "yes" );
      $db6 |= 128 if (AttrVal($name, "blockMotion", "no") ne "yes" );
      $db5 = AttrVal($name, "pollInterval", 10);
      if ($db5 > 60 && $db5 <= 180) {
        $db5 = 61;
      } elsif ($db5 > 180 && $db5 <= 720) {
        $db5 = 62;
      } elsif ($db5 > 720) {
        $db5 = 63;
      }
      $db5 = $db5 << 2;
      $db5 |= 2 if (AttrVal($name, "blockKey", "no") ne "yes" );
      my $displayContent = AttrVal($name, "displayContent", "no_change");
      my $displayContentVal = 0;
      my %displayContent = ("humidity" => 7,
                            "off" => 6,
                            "setpointTemp" => 5,
                            "tempertureExtern" => 4,
                            "temperatureIntern" => 3,
                            "time" => 2,
                            "default" => 1,
                            "no_change" => 0
                           );
      while (($key, $val) = each(%displayContent)) {
        $displayContentVal = $val if ($key eq $displayContent);
      }
      my $temperatureScale = AttrVal($name, "temperatureScale", "no_change");
      my $temperatureScaleVal = 0;
      my %temperatureScale = ("F" => 3,
                              "C" => 2,
                              "default" => 1,
                              "no_change" => 0
                             );
      while (($key, $val) = each(%temperatureScale)) {
        $temperatureScaleVal = $val if ($key eq $temperatureScale);
      }
      my $daylightSavingTimeVal = 0;
      $daylightSavingTimeVal = 1 if (AttrVal($name, "daylightSavingTime", "supported") eq "not_supported");
      my $timeNotation = AttrVal($name, "timeNotation", "no_change");
      my $timeNotationVal = 0;
      if ($timeNotation eq "no_change") {
        $timeNotationVal = 0;
      } elsif ($timeNotation eq "default") {
        $timeNotationVal = 1;
      } elsif ($timeNotation == 24) {
        $timeNotationVal = 2;
      } elsif ($timeNotation == 12) {
        $timeNotationVal = 3;
      }
      $db4 = (($displayContentVal << 2 | $temperatureScaleVal) << 1 | $daylightSavingTimeVal) << 2 | $timeNotationVal;
      my $db32 = ($day << 4 | $month) << 7 | $year - 2000;
      if ($waitingCmds & 4) {
        $db0 |= 1;
        # clear time command
        $waitingCmds &= 251 + 0xFF00;
      }
      if ($waitingCmds & 64) {
        # clear config command
        $waitingCmds &= 191 + 0xFF00;
      }
      $data = sprintf "%02X%02X%02X%02X%04X%02X%02X", $db7, $db6, $db5, $db4, $db32, $db1, $db0;
      $response = "configuration message send $data";
      $logLevel = 2;

    } elsif ($waitingCmds & 2) {
      # data message waiting
      my ($db7, $db6, $db5, $db4, $db3, $db2, $db1, $db0) = (32, 0, 0, 0, 0, 0, 0, 0, 0);

      if (defined ReadingsVal($name, "setpointTempSet", undef)) {
        $db1 = ReadingsVal($name, "setpointTempSet", 0) * 255 / 40;
        $db2 |= 2;
        CommandDeleteReading(undef, "$name setpointTempSet");
      }

      my $heatingSet;
      if (defined ReadingsVal($name, "heatingSet", undef)) {
        $heatingSet = ReadingsVal($name, "heatingSet", 0);
      } else {
        $heatingSet = ReadingsVal($name, "heating", 0);
      }
      if ($heatingSet eq "no_change") {
        $heatingSet = 0;
      } elsif ($heatingSet eq "on") {
        $heatingSet = 1;
      } elsif ($heatingSet eq "off") {
        $heatingSet = 2;
      } elsif ($heatingSet eq "auto") {
        $heatingSet = 3;
      }
      $db2 |= $heatingSet << 4;
      CommandDeleteReading(undef, "$name heatingSet");

      my $coolingSet;
      if (defined ReadingsVal($name, "coolingSet", undef)) {
        $coolingSet = ReadingsVal($name, "coolingSet", 0);
      } else {
        $coolingSet = ReadingsVal($name, "cooling", 0);
      }
      if ($coolingSet eq "no_change") {
        $coolingSet = 0;
      } elsif ($coolingSet eq "on") {
        $coolingSet = 1;
      } elsif ($coolingSet eq "off") {
        $coolingSet = 2;
      } elsif ($coolingSet eq "auto") {
        $coolingSet = 3;
      }
      $db2 |= $coolingSet << 6;
      CommandDeleteReading(undef, "$name coolingSet");

      my $roomCtrlModeSet;
      if (defined ReadingsVal($name, "roomCtrlModeSet", undef)) {
        $roomCtrlModeSet = ReadingsVal($name, "roomCtrlModeSet", 0);
      } else {
        $roomCtrlModeSet = ReadingsVal($name, "roomCtrlMode", 0);
      }
      if ($roomCtrlModeSet eq "comfort") {
        $roomCtrlModeSet = 0;
      } elsif ($roomCtrlModeSet eq "economy") {
        $roomCtrlModeSet = 1;
      } elsif ($roomCtrlModeSet eq "preComfort") {
        $roomCtrlModeSet = 2;
      } elsif ($roomCtrlModeSet eq "buildingProtection") {
        $roomCtrlModeSet = 3;
      }
      $db2 |= $roomCtrlModeSet << 2;
      CommandDeleteReading(undef, "$name roomCtrlModeSet");

      my $windowSet;
      if (defined ReadingsVal($name, "windowSet", undef)) {
        $windowSet = ReadingsVal($name, "windowSet", 0);
      } else {
        $windowSet = ReadingsVal($name, "window", 0);
      }
      if ($windowSet eq "no_change") {
        $windowSet = 0;
      } elsif ($windowSet eq "closed") {
        $windowSet = 1;
      } elsif ($windowSet eq "open") {
        $windowSet = 2;
      } elsif ($windowSet eq "reserved") {
        $windowSet = 3;
      }
      $db4 |= $windowSet;
      CommandDeleteReading(undef, "$name windowSet");

      my $fanSpeedModeSet;
      if (defined ReadingsVal($name, "fanSpeedModeSet", undef)) {
        $fanSpeedModeSet = ReadingsVal($name, "fanSpeedModeSet", 0);
      } else {
        $fanSpeedModeSet = ReadingsVal($name, "fanSpeedMode", 0);
      }
      $db4 |= 64 if ($fanSpeedModeSet eq "local");
      CommandDeleteReading(undef, "$name fanSpeedModeSet");

      if (defined ReadingsVal($name, "fanSpeedSet", undef)) {
        $db5 = ReadingsVal($name, "fanSpeedSet", 0);
        $db4 |= 128;
        CommandDeleteReading(undef, "$name fanSpeedSet");
      }

      $data = sprintf "%02X%02X%02X%02X%02X%02X%02X%02X", $db7, $db6, $db5, $db4, $db3, $db2, $db1, $db0;
      # clear command
      $waitingCmds = $waitingCmds & 253 + 0xFF00;
      $response = "data message send";
      $logLevel = 2;

    } elsif ($waitingCmds & 512) {
      # delete time program command waiting
      $data = "800000000001";
      # clear command
      $waitingCmds = $waitingCmds & 0xFDFF;
      $response = "delete time program send";
      $logLevel = 2;

    } elsif ($waitingCmds & 16) {
      # time program setup waiting
      my ($db5, $endMinute, $endHour, $startMinute, $startHour, $db0) = (128, 0, 0, 0, 0, 0, 0);
      my ($key, $val);
      my $messagePartCntr;
      for ($messagePartCntr = 4; $messagePartCntr >= 1; $messagePartCntr --) {
        if ($hash->{helper}{4}{telegramWait}{$messagePartCntr}) {
          $hash->{helper}{4}{telegramWait}{$messagePartCntr} = 0;
          my $timeProgram = AttrVal($name, "timeProgram" . $messagePartCntr, undef);
          my @timeProgram = split("[ \t][ \t]*", $timeProgram);
          my ($period, $roomCtrlMode) = ($timeProgram[0], $timeProgram[3]);
          ($startHour, $startMinute) = split(':', $timeProgram[1]);
          ($endHour, $endMinute) = split(':', $timeProgram[2]);
          my $periodVal = 0;
          my %period = ("FrMo" => 15,
                        "FrSu" => 14,
                        "ThFr" => 13,
                        "WeFr" => 12,
                        "TuTh" => 11,
                        "MoWe" => 10,
                        "Su" => 9,
                        "Sa" => 8,
                        "Fr" => 7,
                        "Th" => 6,
                        "We" => 5,
                        "Tu" => 4,
                        "Mo" => 3,
                        "SaSu" => 2,
                        "MoFr" => 1,
                        "MoSu" => 0
                        );
          while (($key, $val) = each(%period)) {
            $periodVal = $val if ($key eq $period);
          }
          if ($roomCtrlMode eq "buildingProtection") {
            $roomCtrlMode = 3;
          } elsif ($roomCtrlMode eq "preComfort") {
            $roomCtrlMode = 2;
          } elsif ($roomCtrlMode eq "economy") {
            $roomCtrlMode = 1;
          } else{
            $roomCtrlMode = 0;
          }
          if ($messagePartCntr > 1) {
            # set mcf flag
            $db5 |= 1;
          } else {
            # clear command
            $waitingCmds = $waitingCmds & 239 + 0xFF00;
          }
          $data = sprintf "%02X%02X%02X%02X%02X%02X", $db5, $endMinute, $endHour, $startMinute, $startHour, $periodVal << 4 | $roomCtrlMode << 2;
          $response = "time program setup send";
          $logLevel = 2;
          last;
        }
      }

    } elsif ($waitingCmds & 1) {
      # data request waiting
      $data = "0009";
      # clear command
      $waitingCmds = $waitingCmds & 254 + 0xFF00;
      $response = "data request send";
      $logLevel = 2;

    } elsif ($waitingCmds & 32) {
      # configuration request waiting
      $data = "0011";
      # clear command
      $waitingCmds = $waitingCmds & 223 + 0xFF00;
      $response = "configuration request send";
      $logLevel = 2;

    } elsif ($waitingCmds & 128) {
      # room control setup request waiting
      $data = "0019";
      # clear command
      $waitingCmds = $waitingCmds & 127 + 0xFF00;
      $response = "room control setup request send";
      $logLevel = 2;

    } elsif ($waitingCmds & 256) {
      # time program request waiting
      $data = "0021";
      # clear command
      $waitingCmds = $waitingCmds & 0xFEFF;
      $response = "time program request send";
      $logLevel = 2;

    }

    if ($waitingCmds == 0) {
      CommandDeleteReading(undef, "$name waitingCmds");
    } else {
      readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
    }

  } elsif ($mcf == 1) {
    # message incomplete
    $response = "acknowledge send, wating for next part of the message";
    $logLevel = 2;

  } elsif ($mcf == 2) {
    # automatic message control
    $response = "acknowledge send, automatic message control";
    $logLevel = 2;

  } elsif ($mcf == 3) {
    # reserved
  }

  return ($err, $response, $data, $logLevel);
}

# create SVG devices
sub EnOcean_CreateSVG($$$)
{
  my ($ctrl, $hash, $eepSVG) = @_;
  my $name = $hash->{NAME};
  my ($autocreateHash, $autocreateName, $autocreateDeviceRoom, $autocreateWeblinkRoom) =
     (undef, 'autocreate', 'EnOcean', 'Plots');
  my $filelogName = "FileLog_$name";
  my ($cmd, $eep, $weblinkName, $weblinkHash, $ret);
  if (defined($eepSVG) && $eepSVG =~ m/^([A-Za-z0-9]{2})-([A-Za-z0-9]{2})-([A-Za-z0-9]{2})$/i) {
    $eep = uc("$1.$2.$3");
  } elsif (exists($attr{$name}{eep}) && $attr{$name}{eep} =~ m/^([A-Za-z0-9]{2})-([A-Za-z0-9]{2})-([A-Za-z0-9]{2})$/i) {
    $eep = uc("$1.$2.$3");
  } else {
    return undef;
  }
  # find autocreate device
  while (($autocreateName, $autocreateHash) = each(%defs)) {
    last if ($defs{$autocreateName}{TYPE} eq "autocreate");
  }
  # delete old SVG devices
  if (defined($ctrl) && $ctrl eq 'del' || !exists($defs{$filelogName})) {
    while (($weblinkName, $weblinkHash) = each(%defs)) {
      if ($weblinkName =~ /^SVG_$name.*/) {
        CommandDelete(undef, $weblinkName);
        Log3 $hash->{NAME}, 5, "EnOcean_CreateSVG: device $weblinkName deleted";
      }
    }
  }
  if (!defined(AttrVal($autocreateName, "disable", undef)) && exists($defs{$filelogName})) {
    if (exists $EnO_eepConfig{$eep}{GPLOT}) {
      # add GPLOT parameters
      $attr{$filelogName}{logtype} = $EnO_eepConfig{$eep}{GPLOT} . $attr{$filelogName}{logtype}
        if (!exists($attr{$filelogName}{logtype}) || $attr{$filelogName}{logtype} eq 'text');
      if (AttrVal($autocreateName, "weblink", 1)) {
        $autocreateWeblinkRoom = $attr{$autocreateName}{weblink_room} if (exists $attr{$autocreateName}{weblink_room});
        $autocreateWeblinkRoom = 'EnOcean' if ($autocreateWeblinkRoom eq '%TYPE');
        $autocreateWeblinkRoom = $name if ($autocreateWeblinkRoom eq '%NAME');
        $autocreateWeblinkRoom = $attr{$name}{room} if (exists $attr{$name}{room});
        my $wnr = 1;
        #create SVG devices
        foreach my $wdef (split(/,/, $EnO_eepConfig{$eep}{GPLOT})) {
          next if(!$wdef);
          my ($gplotfile, $stuff) = split(/:/, $wdef);
          next if(!$gplotfile);
          $weblinkName = "SVG_$name";
          $weblinkName .= "_$wnr" if($wnr > 1);
          $wnr++;
          next if (exists $defs{$weblinkName});
          $cmd = "$weblinkName SVG $filelogName:$gplotfile:CURRENT";
          Log3 $weblinkName, 2, "EnOcean define $cmd";
          $ret = CommandDefine(undef, $cmd);
          if($ret) {
            Log3 $weblinkName, 2, "EnOcean ERROR: define $cmd: $ret";
            last;
          }
          $attr{$weblinkName}{room} = $autocreateWeblinkRoom;
          $attr{$weblinkName}{title} = '"' . $name . ' Min $data{min1}, Max $data{max1}, Last $data{currval1}"';
          $ret = CommandSet(undef, "$weblinkName copyGplotFile");
          if($ret) {
            Log3 $weblinkName, 2, "EnOcean ERROR: set $weblinkName copyGplotFile: $ret";
            last;
          }
        }
      }
    }
  }
  return undef;
}

#CommandSave
sub EnOcean_CommandSave($$)
{
  my ($ctrl, $param) = @_;
  # find autocreate device
  my ($autocreateHash, $autocreateName);
  while (($autocreateName, $autocreateHash) = each(%defs)) {
    last if ($defs{$autocreateName}{TYPE} eq "autocreate");
  }
  my $autosave = AttrVal($autocreateName, "autosave", undef);
  if (!defined $autosave) {
    CommandSave($ctrl, $param) if (AttrVal("global", "autosave", 1));
  } elsif ($autosave) {
    CommandSave($ctrl, $param);
  }
  return;
}

sub EnOcean_readingsSingleUpdate($) {
  my ($readingParam) = @_;
  my ($hash, $readingName, $readingVal, $ctrl, $log) = @$readingParam;
  if (defined $hash) {
    readingsSingleUpdate($hash, $readingName, $readingVal, $ctrl) ;
    Log3 $hash->{NAME}, $log, "EnOcean " . $hash->{NAME} . " EVENT $readingName: $readingVal" if ($log);
  }
  return;
}

sub EnOcean_4BSRespWait($$$) {
  my ($ctrl, $hash, $subDef) = @_;
  my $IODev = $hash->{IODev}{NAME};
  my $IOHash = $defs{$IODev};
  $hash->{IODev}{helper}{"4BSRespWait"}{$subDef}{teachInReq} = "out";
  $hash->{IODev}{helper}{"4BSRespWait"}{$subDef}{hash} = $hash;
  # enable teach-in receiving for 3 sec
  $hash->{IODev}{Teach} = 1;
  RemoveInternalTimer($hash->{helper}{timer}{"4BSRespTimeout"}) if(exists $hash->{helper}{timer}{"4BSRespTimeout"});
  $hash->{helper}{timer}{"4BSRespTimeout"} = {hash => $hash, function => "4BSRespTimeout", helper => "4BSRespWait"};
  InternalTimer(gettimeofday() + 3, 'EnOcean_RespTimeout', $hash->{helper}{timer}{"4BSRespTimeout"}, 0);
  return;
}

# Check SenderIDs
sub EnOcean_CheckSenderID($$$)
{
  my ($ctrl, $IODev, $senderID) = @_;
  if (!defined $IODev) {
    my (@listIODev, %listIODev);
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listIODev, $defs{$dev}{IODev}{NAME});
    }
    @listIODev = sort grep(!$listIODev{$_}++, @listIODev);
    if (@listIODev == 1) {
      $IODev = $listIODev[0];
    }
  }
  my $unusedID = 0;
  $unusedID = hex($defs{$IODev}{BaseID}) if ($defs{$IODev}{BaseID});
  my $IDCntr1;
  my $IDCntr2;
  if ($unusedID == 0) {
    $IDCntr1 = 0;
    $IDCntr2 = 0;
  } else {
    $IDCntr1 = $unusedID + 1;
    $IDCntr2 = $unusedID + 127;
  }

  if ($ctrl eq "getBaseID") {
    # get TCM BaseID of the EnOcean device
    if ($defs{$IODev}{BaseID}) {
      $senderID = $defs{$IODev}{BaseID}
    } else {
      $senderID = "0" x 8;
    }

  } elsif ($ctrl eq "getUsedID") {
    # find and sort used SenderIDs
    my @listID;
    my %listID;
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listID, grep(hex($_) >= $IDCntr1 && hex($_) <= $IDCntr2, $defs{$dev}{DEF}));
      push(@listID, $attr{$dev}{subDef}) if ($attr{$dev}{subDef});
      push(@listID, $attr{$dev}{subDefA}) if ($attr{$dev}{subDefA});
      push(@listID, $attr{$dev}{subDefB}) if ($attr{$dev}{subDefB});
      push(@listID, $attr{$dev}{subDefC}) if ($attr{$dev}{subDefC});
      push(@listID, $attr{$dev}{subDefD}) if ($attr{$dev}{subDefD});
      push(@listID, $attr{$dev}{subDefI}) if ($attr{$dev}{subDefI});
      push(@listID, $attr{$dev}{subDefH}) if ($attr{$dev}{subDefH});
      push(@listID, $attr{$dev}{subDefW}) if ($attr{$dev}{subDefW});
      push(@listID, $attr{$dev}{subDef0}) if ($attr{$dev}{subDef0});
    }
    $senderID = join(" ", sort grep(!$listID{$_}++, @listID));

  } elsif ($ctrl eq "getFreeID") {
    # find and sort free SenderIDs
    my (@freeID, @listID, %listID, @intersection, @difference, %count, $element);
    for (my $IDCntr = $IDCntr1; $IDCntr <= $IDCntr2; $IDCntr++) {
      push(@freeID, sprintf "%08X", $IDCntr);
    }
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listID, grep(hex($_) >= $IDCntr1 && hex($_) <= $IDCntr2, $defs{$dev}{DEF}));
      push(@listID, $attr{$dev}{subDef}) if ($attr{$dev}{subDef} && $attr{$dev}{subDef} ne "00000000");
      push(@listID, $attr{$dev}{subDefA}) if ($attr{$dev}{subDefA} && $attr{$dev}{subDefA} ne "00000000");
      push(@listID, $attr{$dev}{subDefB}) if ($attr{$dev}{subDefB} && $attr{$dev}{subDefB} ne "00000000");
      push(@listID, $attr{$dev}{subDefC}) if ($attr{$dev}{subDefC} && $attr{$dev}{subDefC} ne "00000000");
      push(@listID, $attr{$dev}{subDefD}) if ($attr{$dev}{subDefD} && $attr{$dev}{subDefD} ne "00000000");
      push(@listID, $attr{$dev}{subDefI}) if ($attr{$dev}{subDefI} && $attr{$dev}{subDefI} ne "00000000");
      push(@listID, $attr{$dev}{subDefH}) if ($attr{$dev}{subDefH} && $attr{$dev}{subDefH} ne "00000000");
      push(@listID, $attr{$dev}{subDefW}) if ($attr{$dev}{subDefW} && $attr{$dev}{subDefW} ne "00000000");
      push(@listID, $attr{$dev}{subDef0}) if ($attr{$dev}{subDef0} && $attr{$dev}{subDef0} ne "00000000");
    }
    @listID = sort grep(!$listID{$_}++, @listID);
    foreach $element (@listID, @freeID) {
      $count{$element}++
    }
    foreach $element (keys %count) {
      push @{$count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    $senderID = ':' . join(" ", sort @difference);

  } elsif ($ctrl eq "getNextID") {
    # get next free SenderID
    my (@freeID, @listID, %listID, @intersection, @difference, %count, $element);
    for (my $IDCntr = $IDCntr1; $IDCntr <= $IDCntr2; $IDCntr++) {
      push(@freeID, sprintf "%08X", $IDCntr);
    }
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listID, grep(hex($_) >= $IDCntr1 && hex($_) <= $IDCntr2, $defs{$dev}{DEF}));
      push(@listID, $attr{$dev}{subDef}) if ($attr{$dev}{subDef} && $attr{$dev}{subDef} ne "00000000");
      push(@listID, $attr{$dev}{subDefA}) if ($attr{$dev}{subDefA} && $attr{$dev}{subDefA} ne "00000000");
      push(@listID, $attr{$dev}{subDefB}) if ($attr{$dev}{subDefB} && $attr{$dev}{subDefB} ne "00000000");
      push(@listID, $attr{$dev}{subDefC}) if ($attr{$dev}{subDefC} && $attr{$dev}{subDefC} ne "00000000");
      push(@listID, $attr{$dev}{subDefD}) if ($attr{$dev}{subDefD} && $attr{$dev}{subDefD} ne "00000000");
      push(@listID, $attr{$dev}{subDefI}) if ($attr{$dev}{subDefI} && $attr{$dev}{subDefI} ne "00000000");
      push(@listID, $attr{$dev}{subDefH}) if ($attr{$dev}{subDefH} && $attr{$dev}{subDefH} ne "00000000");
      push(@listID, $attr{$dev}{subDefW}) if ($attr{$dev}{subDefW} && $attr{$dev}{subDefW} ne "00000000");
      push(@listID, $attr{$dev}{subDef0}) if ($attr{$dev}{subDef0} && $attr{$dev}{subDef0} ne "00000000");
    }
    @listID = sort grep(!$listID{$_}++, @listID);
    foreach $element (@listID, @freeID) {
      $count{$element}++
    }
    foreach $element (keys %count) {
      push @{$count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    @difference = sort @difference;
    if (defined $difference[0]) {
      $senderID = $difference[0];
    } else {
      $senderID = "0" x 8;
      Log3 $IODev, 2, "EnOcean $IODev no free senderIDs available";
    }

  } else {

  }
  return $senderID;
}

# assign next free SenderID
sub EnOcean_AssignSenderID($$$$)
{
  my ($ctrl, $hash, $attrName, $comMode) = @_;
  my $def = $hash->{DEF};
  my $err;
  my $name = $hash->{NAME};
  my $IODev = $hash->{IODev}{NAME};
  my $senderID = AttrVal($name, $attrName, "");
  # SenderID valid
  return ($err, $senderID) if ($senderID =~ m/^[\dA-Fa-f]{8}$/);
  return ("no IODev", $def) if (!defined $IODev);
  # DEF is SenderID
  if (hex($def) >= hex($defs{$IODev}{BaseID}) && hex($def) <= hex($defs{$IODev}{BaseID}) + 127) {
    if ($comMode eq "biDir") {
      $attr{$name}{comMode} = $comMode;
    } else {
      $attr{$name}{comMode} = "uniDir";
    }
    return ($err, $def);
  } else {
    if ($comMode eq "biDir") {
      $attr{$name}{comMode} = $comMode;
    } else {
      $attr{$name}{comMode} = "confirm";
    }
    $senderID = EnOcean_CheckSenderID("getNextID", $IODev, "00000000");
  }
  #Log3 $name, 2, "EnOcean $name SenderID: $senderID assigned";
  #CommandAttr(undef, "$name $attrName $senderID");
  $attr{$name}{$attrName} = $senderID;
  return ($err, $senderID);
}

# split chained data message
sub EnOcean_SndCdm($$$$$$$$)
{
  my ($ctrl, $hash, $packetType, $rorg, $data, $senderID, $status, $destinationID) = @_;
  my $IODev = $hash->{IODev}{NAME};
  my $IOHash = $defs{$IODev};
  if (!defined $data) {
    Log3 $hash->{NAME}, 5, "EnOcean $hash->{NAME} EnOcean_SndCDM SenderID: $senderID DestinationID: $destinationID " .
    "PacketType: $packetType RORG: $rorg DATA: undef STATUS: $status";
    return;
  }
  my ($seq, $idx, $len, $dataPart, $dataPartLen) = (1, 0, length($data) / 2, undef, 14);
  if (exists $IOHash->{helper}{cdmSeq}) {
    if ($IOHash->{helper}{cdmSeq} < 3) {
      $IOHash->{helper}{cdmSeq} ++;
      $seq = $IOHash->{helper}{cdmSeq};
    } else {
      $IOHash->{helper}{cdmSeq} = $seq;
    }
  } else {
    $IOHash->{helper}{cdmSeq} = $seq;
  }
  # split telelegram with optional data
  $dataPartLen = 9 if ($destinationID ne "FFFFFFFF");
  if ($packetType == 1 && $len > $dataPartLen) {
    # first CDM telegram
    if ($dataPartLen == 14) {
      $data =~ m/^(....................)(.*)$/;
      $dataPart = (sprintf "%02X", $seq << 6 | $idx) . (sprintf "%04X", $len) . $rorg . $1;
      $data = $2;
    } else {
      $data =~ m/^(..........)(.*)$/;
      $dataPart = (sprintf "%02X", $seq << 6 | $idx) . (sprintf "%04X", $len) . $rorg . $1;
      $data = $2;
    }
    $idx ++;
    $len -= $dataPartLen - 5;
    EnOcean_SndRadio($ctrl, $hash, $packetType, "40", $dataPart, $senderID, $status, $destinationID);
    while ($len > 0) {
      if ($len > $dataPartLen - 2) {
        if ($dataPartLen == 14) {
          $data =~ m/^(..........................)(.*)$/;
          $dataPart = (sprintf "%02X", $seq << 6 | $idx) . $1;
          $data = $2;
        } else {
          $data =~ m/^(................)(.*)$/;
          $dataPart = (sprintf "%02X", $seq << 6 | $idx) . $1;
          $data = $2;
        }
        $idx ++;
        $len -= $dataPartLen - 2;
      } else {
        $dataPart = (sprintf "%02X", $seq << 6 | $idx) . $data;
        $len = 0;
      }
      EnOcean_SndRadio($ctrl, $hash, $packetType, "40", $dataPart, $senderID, $status, $destinationID);
    }
  } else {
    # not necessary to split
    EnOcean_SndRadio($ctrl, $hash, $packetType, $rorg, $data, $senderID, $status, $destinationID);
  }
  return;
}

# send ESP3 Packet Type Radio
sub EnOcean_SndRadio($$$$$$$$) {
  my ($ctrl, $hash, $packetType, $rorg, $data, $senderID, $status, $destinationID) = @_;
  if (!defined $data) {
    Log3 $hash->{NAME}, 5, "EnOcean $hash->{NAME} EnOcean_SndRadio SenderID: $senderID DestinationID: $destinationID " .
    "PacketType: $packetType RORG: $rorg DATA: undef STATUS: $status";
    return;
  }
  my ($err, $response, $loglevel);
  my $header;
  my $odata = "";
  my $odataLength = 0;
  if ($packetType == 1) {
    ($err, $rorg, $data, $response, $loglevel) = EnOcean_sec_convertToSecure($hash, $packetType, $rorg, $data);
    if (defined $err) {
      Log3 $hash->{NAME}, $loglevel, "EnOcean $hash->{NAME} Error: $err";
      return "";
    }
    if (AttrVal($hash->{NAME}, "repeatingAllowed", "yes") eq "no") {
      $status = substr($status, 0, 1) . "F";
    }
    if ($rorg eq "A6") {
      # ADT telegram
      $data .= $destinationID;
    } elsif ($destinationID ne "FFFFFFFF") {
      # SubTelNum = 03, DestinationID:8, RSSI = FF, secLevel = 00
      $odata = sprintf "03%sFF00", $destinationID;
      $odataLength = 7;
    }
    # Data Length:4 Optional Length:2 Packet Type:2
    $header = sprintf "%04X%02X%02X", (length($data) / 2 + 6), $odataLength, $packetType;
    Log3 $hash->{NAME}, 4, "EnOcean $hash->{NAME} sent PacketType: $packetType RORG: $rorg DATA: $data SenderID: $senderID STATUS: $status ODATA: $odata";
    $data = $rorg . $data . $senderID . $status . $odata;

  } elsif ($packetType == 2 || $packetType == 6) {
    # smart ack commands
    # Data Length:4 Optional Length:2 Packet Type:2
    $header = sprintf "%04X%02X%02X", length($data) / 2, 0, $packetType;
    Log3 $hash->{NAME}, 4, "EnOcean $hash->{NAME} sent PacketType: $packetType DATA: $data";

  } elsif ($packetType == 7) {
    my $delay = 0;
    $delay = 1 if ($destinationID eq "FFFFFFFF");
    $senderID = "00000000";
    #$senderID = "00000000" if ($destinationID eq "FFFFFFFF");
    $odata = sprintf "%s%sFF%02X", $destinationID, $senderID, $delay;
    $odataLength = 10;
    # Data Length:4 Optional Length:2 Packet Type:2
    $header = sprintf "%04X%02X%02X", (length($data) / 2), $odataLength, $packetType;
    Log3 $hash->{NAME}, 4, "EnOcean $hash->{NAME} sent PacketType: $packetType DATA: $data ODATA: $odata";
    $data .= $odata;
  }
  if (defined $ctrl) {
    # sent telegram delayed
    my @param = ($hash, $hash, $header, $data);
    InternalTimer(gettimeofday() + $ctrl, 'EnOcean_IOWriteTimer', \@param, 0);
  } else {
    IOWrite($hash, $hash, $header, $data);
  }
  return;
}

#
sub EnOcean_IOWriteTimer($) {
  my ($ioParam) = @_;
  my ($hash, $shash, $header, $data) = @$ioParam;
  IOWrite($hash, $shash, $header, $data);
  return;
}

#####
sub EnOcean_SndPeriodic($) {
  my ($param) = @_;
  my ($hash, $function, $period, $startDelay, $repetitions, $log) = @$param;
  @{$hash->{helper}{periodic}{$function}} = @$param;
  $period = defined($period) ? $period : 600;
  if ($period =~ m/^0|off$/) {
    RemoveInternalTimer($hash->{helper}{periodic}{$function}) if(exists $hash->{helper}{periodic}{$function});
    delete $hash->{helper}{periodic}{$function};
    $hash->{'Snd_' . ucfirst($function) . '_Periodic'} = 'off';
  } elsif ($function eq 'time') {
    my ($sec, $min, $hour, $day, $month, $year, $weekday, $dayOfYearTag, $summerTime) = localtime(time + $startDelay + 0.1);
    my @weekday = (7, 1, 2, 3, 4, 5, 6);
    my $data = sprintf "%02X%02X%02X%02X", $weekday[$weekday] << 5 | $hour, $min, $sec, 73;
    EnOcean_SndRadio($startDelay > 0 ? $startDelay : undef, $hash, 1, 'A5', $data, AttrVal($hash->{NAME}, "subDef", $hash->{DEF}), "00", 'FFFFFFFF');
    RemoveInternalTimer($hash->{helper}{periodic}{$function});
    if ($startDelay > 0) {
      $hash->{helper}{periodic}{time}[3] = 0;
    }
    InternalTimer(gettimeofday() + $period + $startDelay, "EnOcean_SndPeriodic", $hash->{helper}{periodic}{$function}, 0);
    $hash->{'Snd_' . ucfirst($function) . '_Periodic'} = 'active';
  }
  Log3 $hash->{NAME}, $log, "EnOcean " . $hash->{NAME} . " EVENT trigger $function" if ($log);
  return;
}

# Scale Readings
sub EnOcean_ReadingScaled($$$$)
{
  my ($hash, $readingVal, $readingMin, $readingMax) = @_;
  my $name = $hash->{NAME};
  my $valScaled;
  my $scaleDecimals = AttrVal($name, "scaleDecimals", undef);
  my $scaleMin = AttrVal($name, "scaleMin", undef);
  my $scaleMax = AttrVal($name, "scaleMax", undef);
  if (defined $scaleMax && defined $scaleMin &&
      $scaleMax =~ m/^[+-]?\d+(\.\d+)?$/ && $scaleMin =~ m/^[+-]?\d+(\.\d+)?$/) {
    $valScaled = ($readingMin*$scaleMax-$scaleMin*$readingMax)/
                 ($readingMin-$readingMax)+
                 ($scaleMin-$scaleMax)/($readingMin-$readingMax)*$readingVal;
  }
  if (defined $scaleDecimals && $scaleDecimals =~ m/^[0-9]?$/) {
    $scaleDecimals = "%0." . $scaleDecimals . "f";
    $valScaled = sprintf "$scaleDecimals", $valScaled;
  }
  return $valScaled;
}

# Reorganize Strings
sub EnOcean_ReorgList($)
{
  my ($list) = @_;
  my @list = split("[ \t][ \t]*", $list);
  my %list;
  @list = sort grep(!$list{$_}++, @list);
  $list = join(" ", @list) . " ";
  return $list;
}

# EnOcean_Set called from sub InternalTimer()
sub EnOcean_TimerSet($)
{
  my ($par) = @_;
  EnOcean_Set($par->{hash}, @{$par->{timerCmd}});
}

#
sub EnOcean_InternalTimer($$$$$)
{
  my ($modifier, $tim, $callback, $hash, $waitIfInitNotDone) = @_;
  my $mHash = {};
  my $timerName = "$hash->{NAME}_$modifier";
  if ($modifier eq "") {
    $mHash = $hash;
  } else {
    if (exists ($hash->{helper}{timer}{$timerName})) {
      $mHash = $hash->{helper}{timer}{$timerName};
      Log3 $hash->{NAME}, 5, "EnOcean_InternalTimer setting mHash with stored $timerName";
   } else {
      $mHash = {HASH => $hash, NAME => $timerName, MODIFIER => $modifier};
      $hash->{helper}{timer}{$timerName} = $mHash;
      Log3 $hash->{NAME}, 5, "EnOcean_InternalTimer setting mHash with $timerName";
    }
  }
  InternalTimer($tim, $callback, $mHash, $waitIfInitNotDone);
  Log3 $hash->{NAME}, 5, "EnOcean setting timer $timerName at " . strftime("%Y-%m-%d %H:%M:%S", localtime($tim));
  return;
}

#
sub EnOcean_RemoveInternalTimer($$)
{
  my ($modifier, $hash) = @_;
  my $mHash = {};
  my $timerName = "$hash->{NAME}_$modifier";
  if ($modifier eq "") {
    RemoveInternalTimer($hash);
  } else {
    $mHash = $hash->{helper}{timer}{$timerName};
    if (defined($mHash)) {
      delete $hash->{helper}{timer}{$timerName};
      RemoveInternalTimer($mHash);
    }
  }
  Log3 $hash->{NAME}, 5, "EnOcean removing timer $timerName";
  return;
}

#
sub EnOcean_observeInit($$@)
{
  #init observe
  my ($ctrl, $hash, @cmdValue) = @_;
  my ($err, $name) = (undef, $hash->{NAME});
  return (undef, $ctrl) if (lc(AttrVal($name, "observe", "off")) eq "off");
  return (undef, $ctrl) if (defined($hash->{helper}{observeCntr}) && $hash->{helper}{observeCntr} > 0);
  $hash->{helper}{observeCntr} = 1;
  #my @observeExeptions = split("[ \t][ \t]*", AttrVal($name, "observeExeptions", ""));
  my @observeRefDev = split("[ \t][ \t]*", AttrVal($name, "observeRefDev", $name));
  $hash->{helper}{observeRefDev} = \@observeRefDev;
  Log3 $name, 4, "EnOcean $name < observeRefDev " . join(" ", @{$hash->{helper}{observeRefDev}}) . " (init)";
  $hash->{helper}{lastCmdFunction} = "set";
  # @cmdValue = (<name>, <cmd>, <param1>, <param2>, ...)
  $hash->{helper}{lastCmdValue} = \@cmdValue;
  my $observeCmds = AttrVal($name, "observeCmds", undef);
  my @observeCmds;
  #my %observeCmds;
  my ($cmdPair, $cmdSent, $cmdReceived);
  if (defined $observeCmds) {
    @observeCmds = split("[ \t][ \t]*", $observeCmds);
    foreach my $cmdPair (@observeCmds) {
      ($cmdSent, $cmdReceived) = split(':', $cmdPair);
      $hash->{helper}{observeCmds}{$cmdSent} = $cmdReceived;
    }
  } else {
    $hash->{helper}{observeCmds}{$cmdValue[1]} = $cmdValue[1];
  }
  $hash->{helper}{observeCntr} = 1;
  readingsSingleUpdate($hash, "observeFailedDev", "", 0);
  RemoveInternalTimer($hash->{helper}{timer}{observe}) if(exists $hash->{helper}{timer}{observe});
  $hash->{helper}{timer}{observe} = {hash => $hash, function => "observe"};
  InternalTimer(gettimeofday() + AttrVal($name, "observeInterval", 1), "EnOcean_observeRepeat", $hash->{helper}{timer}{observe}, 0);
  Log3 $name, 4, "EnOcean set " . join(" ", @cmdValue) . " observing started";
  return ($err, $ctrl);
}

#
sub EnOcean_observeParse($$@)
{
  # observe acknowledge
  my ($ctrl, $hash, @cmdValue) = @_;
  my ($err, $name) = (undef, $hash->{NAME});
  return (undef, $ctrl) if (lc(AttrVal($name, "observe", "off")) eq "off");
  # observing disabled or ignore second and following acknowledgment telegrams
  return (undef, $ctrl) if (!exists($hash->{helper}{observeRefDev}) || @{$hash->{helper}{observeRefDev}} == 0);
  my $devName = shift @cmdValue;
  my $cmd = shift @cmdValue;
  $cmd = shift @cmdValue if ($cmd eq "state");
  my ($observeRefDevIdx) = grep{$hash->{helper}{observeRefDev}[$_] eq $devName} 0..$#{$hash->{helper}{observeRefDev}};
  # device not observed
  return (undef, $ctrl) if (!defined $observeRefDevIdx);
  Log3 $name, 4, "EnOcean $name < observeRefDev " . join(" ", @{$hash->{helper}{observeRefDev}}) . " parsed";
  Log3 $name, 4, "EnOcean $name < $devName $cmd " . join(" ", @cmdValue) . " received";

  if (@{$hash->{helper}{observeRefDev}} == 1) {
    # last acknowledgment telegram stops observing
    delete $hash->{helper}{observeCmds};
    delete $hash->{helper}{observeCntr};
    delete $hash->{helper}{observeRefDev};
    delete $hash->{helper}{lastCmdFunction};
    delete $hash->{helper}{lastCmdValue};
    RemoveInternalTimer($hash->{helper}{timer}{observe}) if(exists $hash->{helper}{timer}{observe});
    Log3 $name, 4, "EnOcean $name < $devName $cmd " . join(" ", @cmdValue) . " observing stopped";
  } else {
    # remove the device that has sent a telegram
    Log3 $name, 4, "EnOcean $name < observeRefDev " . $hash->{helper}{observeRefDev}[$observeRefDevIdx] . " removed";
    splice(@{$hash->{helper}{observeRefDev}}, $observeRefDevIdx, 1);

    if (lc(AttrVal($name, "observeLogic", "or")) eq "and") {
      # AND logic: remove the device that has sent a telegram and await further telegrams
      Log3 $name, 4, "EnOcean $name < observeRefDev " . join(" ", @{$hash->{helper}{observeRefDev}}) . " observing continued";

    } else {
    # OR logic: last acknowledgment telegram stops observing
      #shift @{$hash->{helper}{observeRefDev}};
      delete $hash->{helper}{observeCmds};
      delete $hash->{helper}{observeCntr};
      delete $hash->{helper}{observeRefDev};
      delete $hash->{helper}{lastCmdFunction};
      delete $hash->{helper}{lastCmdValue};
      RemoveInternalTimer($hash->{helper}{timer}{observe}) if(exists $hash->{helper}{timer}{observe});
      Log3 $name, 4, "EnOcean $name < $devName $cmd " . join(" ", @cmdValue) . " observing stopped";
    }
  }

#  if (defined($hash->{helper}{lastCmdValue}[1]) && $hash->{helper}{lastCmdValue}[1] eq $cmd) {
    # acknowledgment telegram ok, cancel the repetition of the command

#  } else {
    # acknowledgment telegram does not match the telegram sent, cancel the repetition of the command

#  }
  return ($err, $ctrl);
}

#
sub EnOcean_observeRepeat($)
{
  #timer expires without acknowledgment telegram, repeat command
  my ($functionHash) = @_;
  my $hash = $functionHash->{hash};
  my $name = $hash->{NAME};
  return if (AttrVal($name, "observe", "off") eq "off" || !defined($hash->{helper}{observeCntr}));

  #my @observeExeptions = split("[ \t][ \t]*", AttrVal($name, "observeExeptions", ""));
  if ($hash->{helper}{observeCntr} <= AttrVal($name, "observeCmdRepetition", 2)) {
    #repeat last command
    $hash->{helper}{observeCntr} += 1;
    Log3 $name, 4, "EnOcean set " . join(" ", @{$hash->{helper}{lastCmdValue}}) . " repeated";
    EnOcean_Set($hash, @{$hash->{helper}{lastCmdValue}});
    RemoveInternalTimer($functionHash);
    InternalTimer(gettimeofday() + AttrVal($name, "observeInterval", 1), "EnOcean_observeRepeat", $functionHash, 0);
  } else {
    # reached the maximum number of retries, clear last command
    Log3 $name, 2, "EnOcean set " . join(" ", @{$hash->{helper}{lastCmdValue}}) .
                   " observing " . join(" ", @{$hash->{helper}{observeRefDev}}) . " failed";
    #splice(@{$hash->{helper}{observeRefDev}}, 0);
    my $actionCmd = AttrVal($name, "observeErrorAction", undef);
    if (defined $actionCmd) {
      # error action exec
      my %specials = ("%NAME" => shift(@{$hash->{helper}{lastCmdValue}}),
                      "%FAILEDDEV" => join(" ", @{$hash->{helper}{observeRefDev}}),
                      "%TYPE"  => $hash->{TYPE},
                      "%EVENT" => ReplaceEventMap($name, join(" ", @{$hash->{helper}{lastCmdValue}}), 1)
                     );
      $actionCmd = EvalSpecials($actionCmd, %specials);
      my $ret = AnalyzeCommandChain(undef, $actionCmd);
      Log3 $name, 2, "EnOcean $name observeErrorAction ERROR: $ret" if($ret);
    }
    readingsSingleUpdate($hash, "observeFailedDev", join(" ", @{$hash->{helper}{observeRefDev}}), 1);
    delete $hash->{helper}{observeCmds};
    delete $hash->{helper}{observeCntr};
    delete $hash->{helper}{observeRefDev};
    delete $hash->{helper}{lastCmdFunction};
    delete $hash->{helper}{lastCmdValue};
    RemoveInternalTimer($functionHash);
  }
  return;
}

sub EnOcean_RLT($) {
  # Radio Link Test
  my ($rltParam) = @_;
  my ($ctrl, $hash, $dataRx, $subDef, $rltMode, $rssiMaster) = @$rltParam;
  my $name = $hash->{NAME};
  my $def = $hash->{DEF};
  my ($err, $logLevel, $response, $dataTx, $rorg, $msgID) = (undef, 5, undef, undef, undef, 0);
  my $rltCntrMax = AttrVal($name, 'rltRepeat', 16);
  my $rltType = AttrVal($name, 'rltType', '4BS');

  if ($rltType eq '1BS') {
    $msgID = $hash->{helper}{rlt}{cntr} & 0x3F if (exists($hash->{helper}{rlt}{cntr}));
    $dataTx = sprintf("%02X", ($msgID & 0x3C) << 2 | 8 | ($msgID & 3) << 1);
    $rorg = 'D5';
  } else {
    $dataTx = '0000000C';
    $rorg = 'A5';
  }
  if ($ctrl eq 'start') {
    RemoveInternalTimer($hash->{helper}{rlt}{param});
    $hash->{helper}{rlt}{cntr} = 0;
    $hash->{helper}{rlt}{param}[0] = 'periodic';
    readingsSingleUpdate($hash, 'state', 'active', 1);
    EnOcean_SndRadio(undef, $hash, 1, $rorg, $dataTx, $subDef, "00", $def);
    InternalTimer(gettimeofday() + 0.15, "EnOcean_RLT", $hash->{helper}{rlt}{param}, 0);

  } elsif ($ctrl eq 'parse') {
    $hash->{helper}{rlt}{param}[0] = 'periodic';
    if ($hash->{helper}{rlt}{cntr} < $rltCntrMax) {
      # store received RLT data from slave
      $hash->{helper}{rlt}{dataRx}[$hash->{helper}{rlt}{cntr}] = $dataRx;
      $hash->{helper}{rlt}{rssiMaster}[$hash->{helper}{rlt}{cntr}] = $rssiMaster;
      if ($hash->{helper}{rlt}{cntr} < $rltCntrMax - 1) {
        RemoveInternalTimer($hash->{helper}{rlt}{param});
        $hash->{helper}{rlt}{cntr} ++;
        EnOcean_SndRadio(undef, $hash, 1, $rorg, $dataTx, $subDef, "00", $def);
        InternalTimer(gettimeofday() + 0.15, "EnOcean_RLT", $hash->{helper}{rlt}{param}, 0);
      }
    } else {
      RemoveInternalTimer($hash->{helper}{rlt}{param});
      readingsSingleUpdate($hash, 'state', 'stopped', 1);
      EnOcean_RLTResult(undef, $hash, $rltType, $rltCntrMax);
      if (exists $hash->{helper}{rlt}{oldDev}) {
        # activate old device subType
        my $oldHash = $hash->{helper}{rlt}{oldDev}[0];
        my $oldName = $hash->{helper}{rlt}{oldDev}[1];
        my $oldDef = $hash->{helper}{rlt}{oldDev}[2];
        CommandModify(undef, "$oldName $oldDef");
        $modules{EnOcean}{defptr}{$oldDef} = $oldHash;
      }
      delete $hash->{helper}{rlt};
      # delete deviceID
      CommandModify(undef, "$name 00000000");
      delete $modules{EnOcean}{defptr}{$def};

    }

  } elsif ($ctrl eq 'periodic') {
    RemoveInternalTimer($hash->{helper}{rlt}{param});
    if ($hash->{helper}{rlt}{cntr} < $rltCntrMax - 1) {
      # no RLT_SlaveTest telegram received from slave
      $hash->{helper}{rlt}{param}[0] = 'periodic';
      $hash->{helper}{rlt}{cntr} ++;
      EnOcean_SndRadio(undef, $hash, 1, $rorg, $dataTx, $subDef, "00", $def);
      InternalTimer(gettimeofday() + 0.11, "EnOcean_RLT", $hash->{helper}{rlt}{param}, 0);

    } else {
      # waiting for last RLT_SlaveTest telegram
      $hash->{helper}{rlt}{param}[0] = 'waiting';
      InternalTimer(gettimeofday() + 0.15, "EnOcean_RLT", $hash->{helper}{rlt}{param}, 0);

    }

  } elsif ($ctrl eq 'waiting') {
    readingsSingleUpdate($hash, 'state', 'stopped', 1);
    EnOcean_RLTResult(undef, $hash, $rltType, $rltCntrMax);
    if (exists $hash->{helper}{rlt}{oldDev}) {
      # activate old device subType
      my $oldHash = $hash->{helper}{rlt}{oldDev}[0];
      my $oldName = $hash->{helper}{rlt}{oldDev}[1];
      my $oldDef = $hash->{helper}{rlt}{oldDev}[2];
      CommandModify(undef, "$oldName $oldDef");
      $modules{EnOcean}{defptr}{$oldDef} = $oldHash;
    }
    delete $hash->{helper}{rlt};
    # delete deviceID
    CommandModify(undef, "$name 00000000");
    delete $modules{EnOcean}{defptr}{$def};

  } elsif ($ctrl eq 'standby') {
    RemoveInternalTimer($hash->{helper}{rlt}{param});
    delete $hash->{helper}{rlt};
    readingsSingleUpdate($hash, 'state', 'standby', 1);
    # delete deviceID
    CommandModify(undef, "$name 00000000");
    delete $modules{EnOcean}{defptr}{$def};

  } elsif ($ctrl eq 'stop') {
    RemoveInternalTimer($hash->{helper}{rlt}{param});
    if (exists $hash->{helper}{rlt}{oldDev}) {
      # activate old device subType
      my $oldHash = $hash->{helper}{rlt}{oldDev}[0];
      my $oldName = $hash->{helper}{rlt}{oldDev}[1];
      my $oldDef = $hash->{helper}{rlt}{oldDev}[2];
      CommandModify(undef, "$oldName $oldDef");
      $modules{EnOcean}{defptr}{$oldDef} = $oldHash;
    }
    delete $hash->{helper}{rlt};
    readingsSingleUpdate($hash, 'state', 'stopped', 1);
    # delete deviceID
    CommandModify(undef, "$name 00000000");
    delete $modules{EnOcean}{defptr}{$def};

  }
  return ($err, $logLevel, $response);
}

sub EnOcean_RLTResult($$$$) {
  # show RLT results
  my ($ctrl, $hash, $rltType, $rltCntrMax) = @_;
  my $name = $hash->{NAME};
  my ($err, $logLevel, $response, $data, $msgCntr, $msgID, $subTelNum, $rssiMaster, $rssiMasterAvg, $rssiSlave, $rssiLevel1, $rssiLevel2, $rssiNonEnOcean) =
     (undef, 5, undef, undef, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  my %rssi = (0 => '-', 1 => '>= -31', 2 => '-32', 0x3F => '<= -93');
  my %rssiNonEnOcean =
       (0 => '-',
        1 => '>= -31',
        2 => '-32 ... -37',
        3 => '-38 ... -43',
        4 => '-44 ... -49',
        5 => '-50 ... -55',
        6 => '-56 ... -61',
        7 => '-62 ... -67',
        8 => '-68 ... -73',
        9 => '-74 ... -79',
        10 => '-80 ... -85',
        11 => '<= -92');

  for (my $cntr = 0; $cntr < $rltCntrMax; $cntr++) {
    $data = $hash->{helper}{rlt}{dataRx}[$cntr];
    if (defined $data) {
      $msgCntr ++;
      $rssiMaster = -$hash->{helper}{rlt}{rssiMaster}[$cntr];
      $rssiMasterAvg += $rssiMaster;
      if ($rltType eq '1BS') {
        $msgID = (hex($data) & 0xF0) >> 6 | (hex($data) & 6) >> 1;
        Log3 $name, 2, "EnOcean RLT DeviceID: " . $hash->{DEF} . " msgCntr: ". ($cntr + 1) . " msgID: $msgID RSSI Master: $rssiMaster response received";

      } else {
        $subTelNum = (hex(substr($data, 0, 2)) & 0xC0) >> 6;
        $rssiLevel2 = hex(substr($data, 0, 2)) & 0x3F;
        $rssiLevel2 = $rssi{$rssiLevel2} if (exists $rssi{$rssiLevel2});
        $rssiLevel1 = hex(substr($data, 2, 2));
        $rssiLevel1 = $rssi{$rssiLevel1} if (exists $rssi{$rssiLevel1});
        $rssiSlave = hex(substr($data, 4, 2));
        $rssiSlave = $rssi{$rssiSlave} if (exists $rssi{$rssiSlave});
        $rssiNonEnOcean = (hex(substr($data, 6, 2)) & 0xF0) >> 4;
        $rssiNonEnOcean = $rssiNonEnOcean{$rssiNonEnOcean} if (exists $rssiNonEnOcean{$rssiNonEnOcean});
        $msgID = (hex(substr($data, 6, 2)) & 6) >> 1;

        Log3 $name, 2, "EnOcean RLT DeviceID: " . $hash->{DEF} . " msgCntr: ". ($cntr + 1) . " subTelNum: $subTelNum " .
                       "RSSI Master: $rssiMaster RSSI Slave: $rssiSlave RSSI Level 1: $rssiLevel1 RSSI Level 2: $rssiLevel2 " .
                       "RSSI non EnOcean: $rssiNonEnOcean";

      }

    } else {
      Log3 $name, 2, "EnOcean RLT DeviceID: " . $hash->{DEF} . " msgCntr: ". ($cntr + 1) . " no answer";

    }
  }
  if ($msgCntr > 0) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'msgLost', (sprintf "%0.1f", ($rltCntrMax - $msgCntr) / $rltCntrMax * 100));
    readingsBulkUpdate($hash, 'rssiMasterAvg', (sprintf "%0.1f", $rssiMasterAvg / $msgCntr));
    readingsEndUpdate($hash, 1);
  } else {
    CommandDeleteReading(undef, "$name msgLost");
    CommandDeleteReading(undef, "$name rssiMasterAvg");
  }
  return ($err, $logLevel, $response);
}

#
sub EnOcean_energyManagement_01Parse($@)
{
  my ($hash, @db) = @_;
  my $name = $hash->{NAME};
  # [drLevel] = 15 : no requests for reduction in power consumptions
  my $drLevel = ($db[0] & 0xF0) >> 4;
  my $powerUsage = $db[2] & 0x7F;
  my $powerUsageLevel = $db[0] & 1 ? "max" : "min";
  my $powerUsageScale = $db[2] & 0x80 ? "rel" : "max";
  my $randomStart = $db[0] & 4 ? "yes" : "no";
  my $randomEnd = $db[0] & 2 ? "yes" : "no";
  my $randomTime = rand(AttrVal($name, "demandRespRandomTime", 1));
  my $setpoint = $db[3];
  my $timeout = $db[1] * 15 * 60;
  $randomTime = $randomTime > $timeout && $timeout > 0 ? rand($timeout) : rand($randomTime);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "randomEnd", $randomEnd);
  readingsBulkUpdate($hash, "randomStart", $randomStart);
  #my %timeoutHash = (hash => $hash, function => "demandResponseTimeout");
  #my %functionHash = (hash            => $hash,
  #                    function        => "demandResponseExec",
  #                    drLevel         => $drLevel,
  #                    powerUsage      => $powerUsage,
  #                    powerUsageLevel => $powerUsageLevel,
  #                    powerUsageScale => $powerUsageScale,
  #                    setpoint        => $setpoint
  #                   );
  $hash->{helper}{timer}{demandResponseTimeout} = {hash => $hash, function => "demandResponseTimeout"};
  $hash->{helper}{demandResponseExec} = {hash            => $hash,
                                         function        => "demandResponseExec",
                                         drLevel         => $drLevel,
                                         powerUsage      => $powerUsage,
                                         powerUsageLevel => $powerUsageLevel,
                                         powerUsageScale => $powerUsageScale,
                                         setpoint        => $setpoint
                                        };
  RemoveInternalTimer($hash->{helper}{timer}{demandResponseTimeout}) if (exists $hash->{helper}{timer}{demandResponseTimeout});
  RemoveInternalTimer($hash->{helper}{demandResponseExec}) if (exists $hash->{helper}{demandResponseExec});
  if ($timeout > 0 && $drLevel < 15) {
    # timeout timer
    InternalTimer(gettimeofday() + $timeout, "EnOcean_demandResponseTimeout", $hash->{helper}{timer}{demandResponseTimeout}, 0);
    my ($sec, $min, $hour, $day, $month, $year) = localtime(time + $timeout);
    $month += 1;
    $year += 1900;
    $min = $min < 10 ? $min = "0" . $min : $min;
    $hour = $hour < 10 ? $hour = "0" . $hour : $hour;
    $day = $day < 10 ? $day = "0" . $day : $day;
    $month = $month < 10 ? $ month = "0". $month : $month;
    readingsBulkUpdate($hash, "timeout", "$year-$month-$day $hour:$min:$sec");
  } else {
    CommandDeleteReading(undef, "$name timeout");
  }
  if ($randomStart eq "yes" && ReadingsVal($name, "level", 15) == 15) {
    readingsBulkUpdate($hash, "state", "waiting_for_start");
    Log3 $name, 3, "EnOcean set $name demand response waiting for start";
    InternalTimer(gettimeofday() + $randomTime, "EnOcean_demandResponseExec", $hash->{helper}{demandResponseExec}, 0);
  } elsif ($randomEnd eq "yes" && ReadingsVal($name, "level", 15) < 15) {
    readingsBulkUpdate($hash, "state", "waiting_for_stop");
    Log3 $name, 3, "EnOcean set $name demand response waiting for stop";
    InternalTimer(gettimeofday() + $randomTime, "EnOcean_demandResponseExec", $hash->{helper}{demandResponseExec}, 0);
  } else {
    EnOcean_demandResponseExec($hash->{helper}{demandResponseExec});
  }
  readingsEndUpdate($hash, 1);
  return;
}

#
sub EnOcean_demandResponseExec($)
{
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $drLevel = $functionHash->{drLevel};
  my $powerUsage = $functionHash->{powerUsage};
  my $powerUsageLevel = $functionHash->{powerUsageLevel};
  my $powerUsageScale = $functionHash->{powerUsageScale};
  my $setpoint = $functionHash->{setpoint};
  my $name = $hash->{NAME};
  my $actionCmd = AttrVal($name, "demandRespAction", undef);
  # save old values
  $hash->{helper}{drLevel} = ReadingsVal($name, "level", 15);
  $hash->{helper}{powerUsage} = ReadingsVal($name, "powerUsage", 100);
  $hash->{helper}{powerUsageLevel} = ReadingsVal($name, "powerUsageLevel", "max");
  $hash->{helper}{powerUsageScale} = ReadingsVal($name, "powerUsageScale", "max");
  $hash->{helper}{setpoint} = ReadingsVal($name, "setpoint", 255);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "level", $drLevel);
  readingsBulkUpdate($hash, "powerUsage", $powerUsage);
  readingsBulkUpdate($hash, "powerUsageLevel", $powerUsageLevel);
  readingsBulkUpdate($hash, "powerUsageScale", $powerUsageScale);
  readingsBulkUpdate($hash, "setpoint", $setpoint);
  if ($drLevel == 15) {
    readingsBulkUpdate($hash, "state", "off");
    Log3 $name, 3, "EnOcean set $name demand response off";
  } else {
    readingsBulkUpdate($hash, "state", "on");
    Log3 $name, 3, "EnOcean set $name demand response on";
  }
  readingsEndUpdate($hash, 1);
  if (defined $actionCmd) {
    # action exec
    my %specials= ("%NAME"  => $name,
                   "%TYPE"  => $hash->{TYPE},
                   "%LEVEL"  => $drLevel,
                   "%SETPOINT"  => $setpoint,
                   "%POWERUSAGE"  => $powerUsage,
                   "%POWERUSAGESCALE"  => $powerUsageScale,
                   "%POWERUSAGELEVEL"  => $powerUsageLevel,
                   "%STATE" => ReadingsVal($name, "state", "off")
                  );
    $actionCmd = EvalSpecials($actionCmd, %specials);
    my $ret = AnalyzeCommandChain(undef, $actionCmd);
    Log3 $name, 2, "EnOcean $name demandRespAction ERROR: $ret" if($ret);
  }
  return;
}

#
sub EnOcean_demandResponseTimeout($)
{
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $name = $hash->{NAME};
  my $actionCmd = AttrVal($name, "demandRespAction", undef);
  my $data;
  my $timeoutLevel = AttrVal($name, "demandRespTimeoutLevel", "max");
  RemoveInternalTimer($functionHash);
  CommandDeleteReading(undef, "$name timeout");
  my $drLevel = 15;
  my $powerUsage = 100;
  my $powerUsageLevel = "max";
  my $powerUsageScale = "max";
  my $setpoint = 255;
  my $timeout = 0;
  if ($timeoutLevel eq "last" && defined($hash->{helper}{drLevel})) {
    # restore old values
    $drLevel = $hash->{helper}{drLevel};
    $powerUsage = $hash->{helper}{powerUsage};
    $powerUsageScale = $hash->{helper}{powerUsageLevel};
    $powerUsageLevel = $hash->{helper}{powerUsageScale};
    $setpoint = $hash->{helper}{setpoint};
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "level", $drLevel);
  readingsBulkUpdate($hash, "powerUsage", $powerUsage);
  readingsBulkUpdate($hash, "powerUsageLevel", $powerUsageLevel);
  readingsBulkUpdate($hash, "powerUsageScale", $powerUsageScale);
  readingsBulkUpdate($hash, "setpoint", $setpoint);
  if ($drLevel == 15) {
    readingsBulkUpdate($hash, "state", "off");
    Log3 $name, 3, "EnOcean set $name demand response off";
  } else {
    readingsBulkUpdate($hash, "state", "on");
    Log3 $name, 3, "EnOcean set $name demand response on";
  }
  readingsEndUpdate($hash, 1);
    my %specials= ("%NAME"  => $name,
                   "%TYPE"  => $hash->{TYPE},
                   "%LEVEL"  => $drLevel,
                   "%SETPOINT"  => $setpoint,
                   "%POWERUSAGE"  => $powerUsage,
                   "%POWERUSAGESCALE"  => $powerUsageScale,
                   "%POWERUSAGELEVEL"  => $powerUsageLevel,
                   "%STATE" => ReadingsVal($name, "state", "off")
                  );
  $powerUsageLevel = $powerUsageLevel eq "max" ? 1 : 0;
  $powerUsageScale = $powerUsageScale eq "rel" ? 0x80 : 0;
  my $randomStart = ReadingsVal($name, "randomStart", "no") eq "yes" ? 4 : 0;
  my $randomEnd = ReadingsVal($name, "randomEnd", "no") eq "yes" ? 2 : 0;
  $data = sprintf "%02X%02X%02X%02X", $setpoint, $powerUsageScale | $powerUsage, $timeout,
                                      $drLevel << 4 | $randomStart | $randomEnd | $powerUsageLevel | 8;
  EnOcean_SndRadio(undef, $hash, 1, "A5", $data, AttrVal($name, "subDef", $hash->{DEF}), "00", "FFFFFFFF");

  if (defined $actionCmd) {
    # action exec
    $actionCmd = EvalSpecials($actionCmd, %specials);
    my $ret = AnalyzeCommandChain(undef, $actionCmd);
    Log3 $name, 2, "EnOcean $name demandRespAction ERROR: $ret" if($ret);
  }
  return;
}

# Send UTE Teach-In Telegrams
sub EnOcean_sndUTE($$$$$$$) {
  my ($ctrl, $hash, $comMode, $responseRequest, $teachInReq, $devChannel, $eep) = @_;
  my $name = $hash->{NAME};
  my ($err, $data) = (undef, "");
  my $IODev = $hash->{IODev}{NAME};
  my $IOHash = $defs{$IODev};
  my @db = (undef, undef, undef, "07", "FF", $devChannel);
  if ($eep =~ m/^(..)-(..)-(..)$/) {
    ($db[0], $db[1], $db[2]) = ($1, $2, $3);
  } else {
    return (1, undef, undef);
  }
  # set unidir/bidir operation
  $db[6] = $comMode eq "biDir" ? 0x80 : 0;
  $attr{$name}{comMode} = $comMode;
  # set teach mode
  if ($teachInReq eq "out") {
    $db[6] |= 0x10;
  } elsif ($teachInReq eq "inout") {
    $db[6] |= 0x20;
  }
  # set response message mode
  if ($responseRequest eq "no") {
    $db[6] |= 0x40;
    readingsSingleUpdate($hash, "teach", "EEP $eep UTE query sent", 1);
  } else {
    # set flag for response request,
    if ($teachInReq eq "in") {
      $hash->{IODev}{helper}{UTERespWait}{$hash->{DEF}}{teachInReq} = $teachInReq;
      $hash->{IODev}{helper}{UTERespWait}{$hash->{DEF}}{hash} = $hash;
    } elsif ($teachInReq eq "out") {
      $hash->{IODev}{helper}{UTERespWait}{AttrVal($name, "subDef", $hash->{DEF})}{teachInReq} = $teachInReq;
      $hash->{IODev}{helper}{UTERespWait}{AttrVal($name, "subDef", $hash->{DEF})}{hash} = $hash;
    } elsif ($teachInReq eq "inout") {
      $hash->{IODev}{helper}{UTERespWait}{$hash->{DEF}}{teachInReq} = $teachInReq;
      $hash->{IODev}{helper}{UTERespWait}{$hash->{DEF}}{hash} = $hash;
    }
    readingsSingleUpdate($hash, "teach", "EEP $eep UTE query sent, response requested", 1);
    # enable teach-in receiving for 3 sec
    $hash->{IODev}{Teach} = 1;
    RemoveInternalTimer($hash->{helper}{timer}{UTERespTimeout}) if(exists $hash->{helper}{timer}{UTERespTimeout});
    $hash->{helper}{timer}{UTERespTimeout} = {hash => $hash, function => "UTERespTimeout", helper => "UTERespWait"};
    InternalTimer(gettimeofday() + 3, 'EnOcean_RespTimeout', $hash->{helper}{timer}{UTERespTimeout}, 0);
  }
  $attr{$name}{devChannel} = $devChannel;
  $attr{$name}{eep} = $eep;
  $attr{$name}{manufID} = "7FF";
  $data = sprintf "%02X%02X%s%s%s%s%s", $db[6], $db[5], $db[4], $db[3], $db[2], $db[1], $db[0];
  return ($err, "D4", $data);
}

#
sub EnOcean_RespTimeout($) {
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $helper = $functionHash->{helper};
  delete $hash->{helper}{timer}{$function};
  delete $hash->{IODev}{helper}{$helper};
  delete $hash->{IODev}{Teach};
  return;
}

#
sub EnOcean_setTeachConfirmWaitHash($) {
  my ($ctrl, $hash) = @_;
  if (AttrVal($hash->{NAME}, "teachMethod", "") eq 'confirm') {
    $hash->{IODev}{helper}{teachConfirmWaitHash} = $hash;
    RemoveInternalTimer($hash->{helper}{timer}{teachConfirmWaitHash}) if(exists $hash->{helper}{timer}{teachConfirmWaitHash});
    $hash->{helper}{timer}{teachConfirmWaitHash} = {hash => $hash->{IODev}, function => "teachConfirmWaitHash"};
    InternalTimer(gettimeofday() + 5, 'EnOcean_helperClear', $hash->{helper}{timer}{teachConfirmWaitHash}, 0);
  }
  return;
}

#
sub EnOcean_ReadDevDesc($$) {
  # read xml device description to $hash->{helper}
  my ($ctrl, $hash) = @_;
  my $name = $hash->{NAME};
  if ($xmlFunc == 0) {
    Log3 $name, 2, "EnOcean $name XML functions are not available";
    return;
  }
  if (exists($hash->{TYPE}) && $hash->{TYPE} eq 'EnOcean' && exists($attr{$name}{model})) {
    if (exists $EnO_models{$attr{$name}{model}}) {
      if (exists $EnO_models{$attr{$name}{model}}{xml}{xmlDescrLocation}) {
        my $xmlFile = $attr{global}{modpath} . $EnO_models{$attr{$name}{model}}{xml}{xmlDescrLocation};
        if (-e -f -r $xmlFile) {
          my $xmlData = $xml->XMLin($xmlFile);
          $hash->{helper} = $xmlData;
          if (exists $xmlData->{Device}) {
            Log3 $name, 5, "EnOcean $name Beginn Device Description";
            Log3 $name, 5, "###";
            Log3 $name, 5, Dumper($xmlData);
            Log3 $name, 5, "###";
            Log3 $name, 5, "EnOcean $name End Device Description";
          } else {
            Log3 $name, 2, "EnOcean $name Device Description not defined";
          }
        } else {
          Log3 $name, 2, "EnOcean $name Device Description file $xmlFile not exists";
        }
      }
    }
  }
  return;
}

#
sub EnOcean_helperClear($) {
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  delete $hash->{helper}{$function};
  return;
}

#
sub EnOcean_cdmClearRemoteWait($) {
  my ($functionHash) = @_;
  my $hash = $functionHash->{hash};
  my $param = $functionHash->{param};
  delete $hash->{IODev}{helper}{remoteAnswerWait}{$param}{hash};
  #Log3 $hash->{NAME}, 3, "EnOcean $hash->{NAME} EnOcean_cdmClearRemoteWait executed.";
  return;
}

#
sub EnOcean_cdmClearHashVal($) {
  my ($functionHash) = @_;
  my $hash = $functionHash->{hash};
  my $param = $functionHash->{param};
  delete $hash->{$param};
  #Log3 $hash->{NAME}, 3, "EnOcean $hash->{NAME} EnOcean_cdmClearHashVal executed.";
  return;
}

#
sub EnOcean_CommandDelete($) {
  my ($functionHash) = @_;
  my $deleteDevice = $functionHash->{deleteDevice};
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $name = $hash->{NAME};
  my $oldDevice = $functionHash->{oldDevice};
  CommandDelete(undef, $deleteDevice);
  if (defined $oldDevice) {
    Log3 $name, 2, "EnOcean $name: $oldDevice renamed to $deleteDevice";
    CommandRename(undef, "$oldDevice $deleteDevice");
    CommandSave(undef, undef);
  } else {
    Log3 $name, 2, "EnOcean $name: $deleteDevice deleted";
    CommandSave(undef, undef);
  }
  return;
}

#
sub EnOcean_convBitToHex($) {
  # convert bit string to hex string
  my ($bitStr) = @_;
  my $hexStr = '';
  while(length($bitStr) > 0) {
    $bitStr =~ m/^(.*)(.{8})$/;
    $bitStr = $1;
    $hexStr = unpack('H2', pack('B8', $2)) . $hexStr;
  }
  return uc($hexStr);
}

#
sub EnOcean_convHexToBit($) {
  # convert unsign hex string to bit string
  my ($hexstr) = @_;
  my $bitstr = '';
  while (length($hexstr) > 0) {
    $hexstr =~ m/^(.*)(..)$/;
    $hexstr = $1;
    $bitstr = unpack('B8', pack('H2', $2)) . $bitstr;
  }
  return $bitstr;
}

#
sub EnOcean_convIntToBit($$) {
  # convert unsign number to bitstring
  my ($data, $resolution) = @_;
  Log3 undef, 3, "EnOcean EnOcean_convIntToBitstr input: $data";
  if ($data > 0xFFFF) {
    # unsigned long (32 bit)
    Log3 undef, 3, "EnOcean EnOcean_convIntToBitstr pack L: " . pack('L', $data);
    #$data = unpack('B32', pack('L', $data));
    $data = unpack('B32', $data);
  } elsif ($data > 0xFF) {
    # unsigned short (16 bit)
    Log3 undef, 3, "EnOcean EnOcean_convIntToBitstr pack S: " . pack('S', $data);
    #$data = '0' x 16 . unpack('B16', pack('S', $data));
    $data = '0' x 16 . unpack('B16', $data);
  } else {
    # unsigned char (8 bit)
    Log3 undef, 3, "EnOcean EnOcean_convIntToBitstr pack C: " . pack('C', $data);
    $data = '0' x 24 . unpack('B8', pack('C', $data));
  }
  Log3 undef, 3, "EnOcean EnOcean_convIntToBitstr pack B32: " . $data;
  $data = substr($data, 32 - $resolution);
  return $data;
}

sub EnOcean_gpConvSelDataToSndData($$$$) {
  # Generic Profiles, make selective data in hex
  my ($header, $channel, $resolution, $data) = @_;
  my $resolutionPattern = '%04B%06B%0' . $resolution . 'B';
  $data = sprintf "$resolutionPattern", $header, $channel, $data;
  if (($resolution + 10) % 8) {
    # fill with trailing zeroes to x bytes
    $data = $data . '0' x (8 - (10 + $resolution) % 8);
  }
  #Log3 undef, 3, "EnOcean EnOcean_gpConvSelDataToSndData header: $header channel: $channel data: $data";
  $data = EnOcean_convBitToHex($data);
  #Log3 undef, 3, "EnOcean EnOcean_gpConvSelDataToSndData header: $header channel: $channel data: $data";
  return $data;
}

#
sub EnOcean_gpConvDataToValue($$$$$) {
  # Generic Profiles, convert data to value
  my ($ctrl, $hash, $channel, $data, $dataDescr) = @_;
  my $name = $hash->{NAME};
  my ($err, $logLevel, $msg, $readingFormat, $readingType, $readingUnit, $readingValue, $valueType) =
     (undef, 5, 'ok', '%d', 'data', 'N/A', $data, 'value');
  my @channelTypeList = ("teachIn", "data", "flag", "enum");
  my @signalTypeList;
  my @valueTypeList = ("res", "value", "setpointAbs", "setpointRel");
  # extract channel definition
  my ($channelName, $channelDir, $channelType, $signalType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax);
  ($channelName, $channelDir, $channelType, $signalType, $valueType, $resolution, $engMin, $scalingMin, $engMax, $scalingMax) =
    split(':', $dataDescr);
  my $readingName = sprintf('%02d', $channel) . '-' . $channelName;
  $readingType = $channelTypeList[$channelType];
  $valueType = $valueTypeList[$valueType];

  if ($channelType == 3) {
    # enumeration
    if (defined $EnO_gpValueEnum{$signalType}{unit})  {
      $readingUnit = $EnO_gpValueEnum{$signalType}{unit};
    }
    if (defined $EnO_gpValueEnum{$signalType}{enum}{$data})  {
      $readingValue = $EnO_gpValueEnum{$signalType}{enum}{$data};
      $readingFormat = '%s';
    } elsif ($signalType == 7) {
      $readingValue = $data / 2;
      $readingFormat = '%0.1f';
    }

  } elsif ($channelType == 2) {
    # flag
    if (defined $EnO_gpValueFlag{$signalType}{flag}{$data})  {
      $readingValue = $EnO_gpValueFlag{$signalType}{flag}{$data};
      $readingFormat = '%s';
    }

  } elsif ($channelType == 1) {
    # data
    if (defined $EnO_gpValueData{$signalType}{unit})  {
      $readingUnit = $EnO_gpValueData{$signalType}{unit};
    }
    my @decimalDigits = (0, 1, 1, 2, 2, 2, 3, 4 , 4, 5, 7, 8, 10);
    $readingValue = $data / 2**$EnO_resolution[$resolution] *
                    ($engMax * $EnO_scaling[$scalingMax] - $engMin * $EnO_scaling[$scalingMin]) + $engMin * $EnO_scaling[$scalingMin];
    if ($readingValue =~ m/^[+-]?\d+$/) {

    } elsif ($readingValue < 1000) {
      $readingFormat = '%0.' . ($decimalDigits[$resolution] - 1) . 'f';
    } else {
      $readingFormat = '%.' . ($decimalDigits[$resolution] - 1) . 'g';
    }

  } else {
    # teach-in info ... not used
    my @valueList = ("res", "channelsDescription", "productID");
    if (defined $valueList[$signalType]) {
      $readingValue = $valueList[$signalType];
      $readingFormat = '%s';
    }
  }

  return ($err, $logLevel, $msg, $readingFormat, $readingName, $readingType, $readingUnit, $readingValue, $valueType);
}

# Parse Secure Teach-In Telegrams
sub EnOcean_sec_parseTeachIn($$$$) {
  my ($hash, $telegram, $subDef, $destinationID) = @_;
  my $name = $hash->{NAME};
  my ($err, $response, $logLevel);
  my $rlc; # Rolling code
  my $key1; # First part of private key
  my $key2; # Second part of private key

  # Extract byte fields from telegram
  # TEACH_IN_INFO, SLF, RLC/KEY/variable
  $telegram =~ /^(..)(..)(.*)/;	# TODO Parse error handling?
  my $teach_bin = unpack('B8',pack('H2', $1));	# Parse as ASCII HEX, unpack to bitstring
  my $slf_bin = unpack('B8',pack('H2', $2));	# Parse as ASCII HEX, unpack to bitstring
  my $crypt = $3;

  # Extract bit fields from teach-in info field
  # IDX, CNT, PSK, TYPE, INFO
  $teach_bin =~ /(..)(..)(.)(.)(..)/;	# TODO Parse error handling?
  my $idx = unpack('C',pack('B8', '000000'.$1));	# Padd to byte, parse as unsigned char
  my $cnt = unpack('C',pack('B8', '000000'.$2));  # Padd to byte, parse as unsigned char
  my $psk = $3;
  my $type = $4;
  my $info = unpack('C',pack('B8', '000000'.$5)); # Padd to byte, parse as unsigned char

  # Extract bit fields from SLF field
  # RLC_ALGO, RLC_TX, MAC_ALGO, DATA_ENC
  $slf_bin =~ /(..)(.)(..)(...)/;	# TODO Parse error handling?
  my $rlc_algo = unpack('C',pack('B8', '000000'.$1));	# Padd to byte, parse as unsigned char
  my $rlc_tx = $2;
  my $mac_algo = unpack('C',pack('B8', '000000'.$3));	# Padd to byte, parse as unsigned char
  my $data_enc = unpack('C',pack('B8', '00000'.$4));	# Padd to byte, parse as unsigned char

  # The teach-in information is split in two telegrams due to the ERP1 limitations on telegram length
  # So we should get a telegram with index 0 and count 2 with the first half of the infos needed
  if ($idx == 0 && $cnt == 2) {
    # First part of the teach in message

    # Decode teach in type
    if ($type == 0) {
      # 1BS, 4BS, UTE or GP teach-in expected
      if ($info == 0) {
        $attr{$name}{comMode} = "uniDir";
        $attr{$name}{secMode} = "rcv";
      } else {
        $attr{$name}{comMode} = "biDir";
        $attr{$name}{secMode} = "biDir";
      }
      $hash->{helper}{teachInWait} = "STE";
    } else {
      # switch teach-in
      $attr{$name}{teachMethod} = 'STE';
      if ($info == 0) {
        $attr{$name}{comMode} = "uniDir";
        $attr{$name}{eep} = "D2-03-00";
        $attr{$name}{manufID} = "7FF";
        $attr{$name}{secMode} = "rcv";
        foreach my $attrCntr (keys %{$EnO_eepConfig{"D2.03.00"}{attr}}) {
          $attr{$name}{$attrCntr} = $EnO_eepConfig{"D2.03.00"}{attr}{$attrCntr};
        }
        readingsSingleUpdate($hash, "teach", "STE teach-in accepted EEP D2-03-00 Manufacturer: " . $EnO_manuf{"7FF"}, 1);
        Log3 $name, 2, "EnOcean $name STE teach-in accepted EEP D2-03-00 Rocker A Manufacturer: " . $EnO_manuf{"7FF"};
      } else {
        $attr{$name}{comMode} = "uniDir";
        $attr{$name}{eep} = "D2-03-00";
        $attr{$name}{manufID} = "7FF";
        $attr{$name}{secMode} = "rcv";
        foreach my $attrCntr (keys %{$EnO_eepConfig{"D2.03.00"}{attr}}) {
          $attr{$name}{$attrCntr} = $EnO_eepConfig{"D2.03.00"}{attr}{$attrCntr};
        }
        readingsSingleUpdate($hash, "teach", "STE teach-in accepted EEP D2-03-00 Manufacturer: " . $EnO_manuf{"7FF"}, 1);
        Log3 $name, 2, "EnOcean $name STE teach-in accepted EEP D2-03-00 Rocker B Manufacturer: " . $EnO_manuf{"7FF"};
      }
    }

  # Decode RLC algorithm and extract RLC and private key (only first part most likely)
		if ($rlc_algo == 0) {
			# No RLC used in telegram or internally in memory, use case untested
			return ("Secure modes without RLC not tested or supported", undef);
		} elsif ($rlc_algo == 1) {
			# "RLC= 2-byte long. RLC algorithm consists on incrementing in +1 the previous RLC value

			# Extract RLC and KEY fields from data trailing SLF field
			# RLC, KEY, ID, STATUS
			$crypt =~ /^(....)(.*)$/;
			$rlc = $1;
			$key1 = $2;

			#print "RLC: $rlc\n";
			#print "Part 1 of KEY: $key1\n";

			# Store in device hash
			$attr{$name}{rlcAlgo} = '2++';
                        readingsSingleUpdate($hash, ".rlcRcv", $rlc, 0);
			# storing backup copy
			$attr{$name}{rlcRcv} = $rlc;
			$attr{$name}{keyRcv} = $key1;

		} elsif ($rlc_algo == 2) {
			# RLC= 3-byte long. RLC algorithm consists on incrementing in +1 the previous RLC value

			# Extract RLC and KEY fields from data trailing SLF field
			# RLC, KEY, ID, STATUS
			$crypt =~ /^(......)(.*)$/;
			$rlc = $1;
			$key1 = $2;

			#print "RLC: $rlc\n";
			#print "Part 1 of KEY: $key1\n";

			# Store in device hash
			$attr{$name}{rlcAlgo} = '3++';
                        readingsSingleUpdate($hash, ".rlcRcv", $rlc, 0);
			# storing backup copy
			$attr{$name}{rlcRcv} = $rlc;
			$attr{$name}{keyRcv} = $key1;
		} else {
			# Undefined RLC algorithm
			return ("Undefined RLC algorithm $rlc_algo", undef);
		}

		# RLC Transmission
		if ($rlc_tx == 0 ) {
			# Secure operation mode telegrams do not contain RLC, we store and track it ourself
			$attr{$name}{rlcTX} = 'false';
		} else {
			# Secure operation mode messages contain RLC, CAUTION untested
			$attr{$name}{rlcTX} = 'true';
		}

		# Decode MAC Algorithm
		if ($mac_algo == 0) {
			# No MAC included in the secure telegram
			# Doesn't make sense for RLC senders like the PTM215, as we can't verify the RLC then...
			#$attr{$name}{macAlgo} = 'no';
			return ("Secure mode without MAC algorithm unsupported", undef);
		} elsif ($mac_algo == 1) {
			# CMAC is a 3-byte-long code
			$attr{$name}{macAlgo} = '3';
		} elsif ($mac_algo == 2) {
			# MAC is a 4-byte-long code
			$attr{$name}{macAlgo} = '4';
		} else {
			# Undefined MAC algorith;
			# Nothing we can do either...
			#$attr{$name}{macAlgo} = 'no';
			return ("Undefined MAC algorithm $mac_algo", undef);
		}

		# Decode data encryption algorithm
		if ($data_enc == 0) {
			# Data not encrypted? Right now we will handle this like an error, concrete use case untested
			#$attr{$name}{secLevel} = 'encapsulation';
			return ("Secure mode message without data encryption unsupported", undef);
		} elsif ($data_enc == 1) {
			# Unspecified
			return ("Undefined data encryption algorithm $data_enc", undef);
		} elsif ($data_enc == 2) {
			# Unspecified
			return ("Undefined data encryption algorithm $data_enc", undef);
		} elsif ($data_enc == 3) {
			# Data will be encrypted/decrypted XORing with a string obtained from a AES128 encryption
			$attr{$name}{dataEnc} = 'VAES';
			$attr{$name}{secLevel} = 'encryption';
		} elsif ($data_enc == 4) {
			# Data will be encrypted/decrypted using the AES128 algorithm in CBC mode
			# Might be used in the future right now untested
			#$attr{$name}{dataEnc} = 'AES-CBC';
			#$attr{$name}{secLevel} = 'encryption';
			return ("Secure mode message with AES-CBC data encryption unsupported", undef);
		} else {
			# Something went horribly wrong
			return ("Could not parse data encryption information, $data_enc", undef);
		}

          $hash->{helper}{teachInSTE} = $cnt - 1;
          # Ok we got a lots of infos and the first part of the private key
          return (undef, "part 1 received Rlc: $rlc Key1: $key1");

	} elsif ($idx == 1 && exists($hash->{helper}{teachInSTE})) {
	  # Second part of the teach-in telegrams

	  # Extract byte fields from telegram
	  # Don't care about info fields, KEY, ID, don't care about status
	  $telegram =~ /^..(.*)$/;	# TODO Parse error handling?
	  $key2 = $1;

	  # We already should have gathered the infos from the first teach-in telegram
	  if (!defined($attr{$name}{keyRcv})) {
	    # We have missed the first telegram
	    return ("Missing first teach-in telegram", undef);
	  }

	  # Append second part of private key to first part of private key
	  $attr{$name}{keyRcv} .= $key2;

	  if ($attr{$name}{secMode} eq "biDir") {
            # bidirectional secure teach-in
            if (!defined $subDef) {
              $subDef = EnOcean_CheckSenderID("getNextID", $defs{$name}{IODev}{NAME}, "00000000");
              $attr{$name}{subDef} = $subDef;
            }
            ($err, $response, $logLevel) = EnOcean_sec_createTeachIn(undef, $hash, $attr{$name}{comMode},
                                                                     $attr{$name}{dataEnc}, $attr{$name}{eep},
                                                                     $attr{$name}{macAlgo}, $attr{$name}{rlcAlgo},
                                                                     $attr{$name}{rlcTX}, $attr{$name}{secLevel},
                                                                     $subDef, $destinationID);
            if ($err) {
              Log3 $name, $logLevel, "EnOcean $name Error: $err";
              return $err;
            } else {
              Log3 $name, $logLevel, "EnOcean $name $response";
            }
          }
	  delete $hash->{helper}{teachInSTE};
	  return (undef, "part 2 received Key2: $key2");
	}

	# Sequence error?
	return ("teach-in sequence error IDC: $idx CNT: $cnt", undef);
}

# Do VAES decyrption
# All parameters need to be passed as byte strings
#
# Parameter 1: Current rolling code, 16 bytes
# Parameter 2: Private key, 16bytes
# Paremeter 3: Encrypted data, 16bytes
#
# Returns: Decrypted data, 16 bytes
#
# Decryption of more than 16bytes of data is currently unsupported
#
sub EnOcean_sec_decodeVAES($$$) {
	my $rlc = $_[0];
	my $private_key = $_[1];
	my $data_enc = $_[2];
	# Public key according to EnOcean Security specification
	my $public_key = pack('H32', '3410de8f1aba3eff9f5a117172eacabd');

        # Input for VAES
        my $aes_in = $public_key ^ $rlc;

	#print "--\n";
        #print "Public Key  ".unpack('H32', $public_key)."\n";
        #print "RLC         ".unpack('H32', $rlc)."\n";
        #print "AES input   ".unpack('H32', $aes_in)."\n";
	#print "--\n";
        #print "Private Key ".unpack('H32', $private_key)."\n";

        my $cipher = Crypt::Rijndael->new( $private_key );
        my $aes_out = $cipher->encrypt($aes_in);

        #print "AES output  ".unpack('H32', $aes_out)."\n";
        #print "Data_enc:   ".unpack('H32', $data_enc)."\n";

        my $data_dec = $data_enc ^ $aes_out;

        #print "Data_dec:   ".unpack('H32', $data_dec)."\n";
	return $data_dec;
}

# Returns current RLC in hex format and increments the stored RLC
# Checks the boundaries of the RLC for roll-over
#
# Parameter 1: Sender ID in hexadecimal format for lookup in receivers hash
#
# Affects: receivers hash
#
# Returns: RLC in hexadecimal format
#
sub EnOcean_sec_getRLC($$$$) {
	my $hash = $_[0];
	my $rlcVar = $_[1];
	my $expectRlc = $_[2];
	my $rlc = $_[3];
        my $name = $hash->{NAME};
	my $old_rlc = $rlc;
	# Fetch newest RLC from receiver hash
	if ($expectRlc == 0) {
	  $old_rlc = ReadingsVal($name, "." . $rlcVar, $attr{$name}{$rlcVar});
	  if (hex($old_rlc) < hex($attr{$name}{$rlcVar})) {
	    $old_rlc = $attr{$name}{$rlcVar};
	  }
	}
	Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC old: $old_rlc " . hex($old_rlc);

	# Advance RLC by one
	my $new_rlc = hex($old_rlc) + 1;

	# Boundary check
	if ($attr{$name}{rlcAlgo} eq '2++') {
		if ($new_rlc > 65535) {
			#print "RLC rollover\n";
			Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC rollover";
			$new_rlc = 0;
		        $attr{$name}{$rlcVar} = "0000";
                        EnOcean_CommandSave(undef, undef);
		}
		readingsSingleUpdate($hash, "." . $rlcVar, uc(unpack('H4',pack('n', $new_rlc))), 0);
		$attr{$name}{$rlcVar} = uc(unpack('H4',pack('n', $new_rlc)));
	} elsif ($attr{$name}{rlcAlgo} eq '3++') {
		if ($new_rlc > 16777215) {
			#print "RLC rollover\n";
			Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC rollover";
			$new_rlc = 0;
		        $attr{$name}{$rlcVar} = "000000";
                        EnOcean_CommandSave(undef, undef);
		}
                readingsSingleUpdate($hash, "." . $rlcVar, sprintf("%06X", $new_rlc), 0);
		$attr{$name}{$rlcVar} = sprintf("%06X", $new_rlc);
	}

	Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC new: $attr{$name}{$rlcVar} $new_rlc";
	return $old_rlc;
}

# Generate MAC of data
#
# Parameter 1: private key as byte string, 16bytes
# Parameter 2: data fro which mac should be calculated in hexadecimal format, len variable
# Parameter 3: length of MAC to be generated in bytes
#
# Returns: MAC in hexadecimal format
#
# This function currently supports data with lentgh of less then 16bytes,
# MAC for longer data is untested but specified
#
sub EnOcean_sec_generateMAC($$$) {
	my $private_key = $_[0];
	my $data = $_[1];
	my $cmac_len = $_[2];

	#print "Calculating MAC for data $data\n";
        Log3 undef, 5, "EnOcean_sec_generateMAC Calculating MAC for data $data";
	Log3 undef, 5, "EnOcean_sec_generateMAC private key ".unpack('H32', $private_key);

	# Pack data to 16byte byte string, padd with 10..0 binary
	my $data_expanded = pack('H32', $data.'80');

	#print "Exp. data  ".unpack('H32', $data_expanded)."\n";

	# Constants according to specification
	my $const_zero = pack('H32','00');
	my $const_rb = pack('H32', '00000000000000000000000000000087');

	# Encrypt zero data with private key to get L
	my $cipher = Crypt::Rijndael->new($private_key);
        my $l = $cipher->encrypt($const_zero);
	#print "L          ".unpack('H32', $l)."\n";
	#print "L          ".unpack('B128', $l)."\n";

	# Expand L to 128bit string
	my $l_bit = unpack('B128', $l);

	# K1 and K2 stored as 128bit string
	my $k1_bit;
	my $k2_bit;

	# K1 and K2 as binary
	my $k1;
	my $k2;

	# Store L << 1 in K1
	$l_bit =~ /^.(.{127})/;
	$k1_bit = $1.'0';
	$k1 = pack('B128', $k1_bit);

	# If MSB of L == 1, K1 = K1 XOR const_Rb
	if($l_bit =~ m/^1/) {
		#print "MSB of L is set\n";
		$k1 = $k1 ^ $const_rb;
		$k1_bit = unpack('B128', $k1);
	} else {
		#print "MSB of L is unset\n";
	}

	# Store K1 << 1 in K2
	$k1_bit =~ /^.(.{127})/;
	$k2_bit = $1.'0';
	$k2 = pack('B128', $k2_bit);

	# If MSB of K1 == 1, K2 = K2 XOR const_Rb
	if($k1_bit =~ m/^1/) {
		#print "MSB of K1 is set\n";
		$k2 = $k2 ^ $const_rb;
	} else {
		#print "MSB of K1 is unset\n";
	}

	# XOR data with K2
	$data_expanded ^= $k2;

	# Encrypt data
	my $cmac = $cipher->encrypt($data_expanded);

	#print "CMAC ".unpack('H32', $cmac)."\n";
        Log3 undef, 5, "EnOcean_sec_generateMAC CMAC ".unpack('H32', $cmac);

	# Extract specified len of MAC
	my $cmac_pattern = '^(.{'.($cmac_len * 2).'})';
	unpack('H32', $cmac) =~ /$cmac_pattern/;
	Log3 undef, 5, "EnOcean_sec_generateMAC cutted CMAC ".unpack('H32', $1);

	# Return MAC in hexadecimal format
	return uc($1);
}

# Verify (MAC) and decode/decrypt secure mode message
#
# Parameter 1: content of radio telegram in hexadecimal format
#
# Returns: "ERROR-" + error description, "OK-" + EEP D2-03-00 telegram in hexadecimal format
#
# Right now we only decode PTM215 telegrams which are transmitted as RORG 30 and without
# encapsulation. Encapsulation of other telegrams is possible and specified but untested due to the
# lack of hardware suporting this.
#
sub EnOcean_sec_convertToNonsecure($$$) {
  my ($hash, $rorg, $crypt_data) = @_;
  my $name = $hash->{NAME};
  if ($cryptFunc == 0) {
    return ("Cryptographic functions are not available", undef, undef);
  }
  my $private_key;
  # Prefix of pattern to extract the different cryptographic infos
  my $crypt_pattern = "^(.*)";;
  # Flags and infos for fields to expect
  my $expect_rlc = 0;
  my $expect_mac = 0;
  my $mac_len;
  my $expect_enc = 0;

  # Check if RLC is transmitted and when, which length to expect
  if($attr{$name}{rlcTX} eq 'true') {
    # Message should contain RLC
    if ($attr{$name}{rlcAlgo} eq '2++') {
      $crypt_pattern .= "(....)";
      $expect_rlc = 1;
    } elsif ($attr{$name}{rlcAlgo} eq '3++') {
      $crypt_pattern .= "(......)";
      $expect_rlc = 1;
    } else {
      # RLC_TX but no info on RLC length
      return ("RLC_TX and RLC_ALGO inconsistent", undef, undef);
    }
  }

  # Check what length of MAC to expect
  if($attr{$name}{macAlgo} eq '3') {
    $crypt_pattern .= "(......)";
    $mac_len = 3;
    $expect_mac = 1;
  } elsif ($attr{$name}{macAlgo} eq '4') {
    $crypt_pattern .= "(........)";
    $mac_len = 4;
    $expect_mac = 1;
  } else {
    # According to the specification it's possible to transmit no MAC, bt we don't implement this for now
    return ("Secure mode messages without MAC unsupported", undef, undef);
  }

  # Suffix for crypt pattern
  $crypt_pattern .= '$';

  # Extract byte fields from message payload
  $crypt_data =~ /$crypt_pattern/;
  my $data_enc = $1;
  my $dataLength = length($data_enc);
  return ("Telegrams with a length of more than 16 bytes are not supported", undef, undef) if ($dataLength > 32);
  my $rlc;
  my $mac;
  if ($expect_rlc == 1 && $expect_mac == 1) {
    $rlc = $2;
    $mac = $3;
  } elsif ($expect_rlc == 0 && $expect_mac == 1) {
    $rlc = ReadingsVal($name, ".rlcRcv", $attr{$name}{rlcRcv});
    $rlc = $attr{$name}{rlcRcv} if (hex($rlc) < hex($attr{$name}{rlcRcv}));
    $mac = $2;
  }
  my $old_rlc = $rlc;
  Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure RORG: $rorg DATA_ENC: $data_enc";
  if ($expect_rlc == 1) {
    Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure RLC: $rlc";
  };
  Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure MAC: $mac";

  # Maximum RLC search window is 128
  foreach my $rlc_window (0..128) {
    #print "Trying RLC offset $rlc_window\n";
    # Fetch stored RLC
    $rlc = EnOcean_sec_getRLC($hash, "rlcRcv", $expect_rlc, $rlc);
    # Fetch private Key for VAES
    if ($attr{$name}{keyRcv} =~ /[\dA-F]{32}/) {
      $private_key = pack('H32',$attr{$name}{keyRcv});
    } else {
      return ("private key wrong, please teach-in the device new", undef, undef);
    }

    # Generate and check MAC over RORG+DATA+RLC fields
    if ($mac eq EnOcean_sec_generateMAC($private_key, $rorg.$data_enc.$rlc, $mac_len)) {
      #print "RLC verfified\n";
      # Expand RLC to 16byte
      my $rlc_expanded = pack('H32',$rlc);

      # Expand data to 16byte
      my $data_expanded = pack('H32',$data_enc);

      # Decode data using VAES
      my $data_dec = EnOcean_sec_decodeVAES($rlc_expanded, $private_key, $data_expanded);
      my $data_end = unpack('H32', $data_dec);
      if ($rorg eq '30') {
        $data_end =~ /^(.{$dataLength})/;
        return (undef, '32', uc($1));
        #if ($dataLength == 2) {
          # Extract one nibble of data
        #  $data_end =~ /^.(.)/;
        #  return (undef, '32', "0" . uc($1));
        #} else {
        #  $data_end =~ /^(.{$dataLength})/;
        #  return (undef, '32', uc($1));
        #}
      } else {
        $dataLength -= 2;
        $data_end =~ /^(..)(.{$dataLength})/;
        Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure RORG: " . uc($1) . " DATA: " . uc($2);
        return (undef, uc($1), uc($2));
      }
      # Couldn't verify or decrypt message, only one calculation if rlcTX = true
      return ("Can't verify or decrypt telegram", undef, undef) if ($expect_rlc == 1);
    }
  }
  # Couldn't verify or decrypt message in RLC window
  #####
  # restore old rlc
  readingsSingleUpdate($hash, ".rlcRcv", $old_rlc, 0);
  $attr{$name}{rlcRcv} = $old_rlc;
  return ("Can't verify or decrypt telegram", undef, undef);
}

#
sub EnOcean_sec_createTeachIn($$$$$$$$$$$)
{
  my ($ctrl, $hash, $comMode, $dataEnc, $eep, $macAlgo, $rlcAlgo, $rlcTX, $secLevel, $subDef, $destinationID) = @_;
  my $name = $hash->{NAME};
  my ($data, $err, $response, $loglevel);

  # THIS IS A BASIC IMPLEMENTATION WITH HARDCODED VALUES FOR
  # THE SECURITY PARAMETERS, WILL BE CUSTOMIZABLE IN FUTURE

  if ($cryptFunc == 0) {
    return ("Cryptographic functions are not available", undef, 2);
  }
  # generate random private key
  my $pKey;
  for (my $i = 1; $i < 5; $i++) {
    $pKey .= uc(unpack('H8', pack('L', makerandom(Size => 32, Strength => 1))));
  }
  $attr{$name}{keySnd} = AttrVal($name, "keySnd", $pKey);

  #generate random rlc, save to fhem.cfg and update readings
  my $rlc = ReadingsVal($name, ".rlcSnd", uc(unpack('H4', pack('n', makerandom(Size => 16, Strength => 1)))));
  readingsSingleUpdate($hash, ".rlcSnd", $rlc, 0);
  $attr{$name}{rlcSnd} = $rlc;

  $attr{$name}{comMode} = AttrVal($name, "comMode", $comMode);
  $attr{$name}{dataEnc} = AttrVal($name, "dataEnc", $dataEnc);
  $attr{$name}{eep} = $eep;
  $attr{$name}{macAlgo} = AttrVal($name, "macAlgo", $macAlgo);
  $attr{$name}{manufID} = "7FF";
  $attr{$name}{rlcAlgo} = AttrVal($name, "rlcAlgo", $rlcAlgo);
  $attr{$name}{rlcTX} = AttrVal($name, "rlcTX", $rlcTX);
  $attr{$name}{secLevel} = AttrVal($name, "secLevel", $secLevel);
  if (AttrVal($name, "secMode", "") =~ m/^rcv|bidir$/) {
    $attr{$name}{secMode} = "biDir";
  } else {
    $attr{$name}{secMode} = "snd";
  }

  # prepare 1st telegram

  #RORG = 35, TEACH_IN_INFO_0, SLF, RLC, KEY, ID, STATUS as defined in Security_of_EnOcean_Radio_Networks.pdf page 17
  #set TEACH_IN_INFO = 25 -> 0001.0101 -> IDX =0, CNT = 2, PSK = 0, TYPE = 1, INFO = 1
  #set SLF = 4B -> 0100.1011 -> RLC_ALGO=16bit, RLC-TX=0, MAC-ALGO = AES3BYTE, DATA_ENC = VAES128
  #save the fixed security parameters to fhem.cfg

  #get first 5 bytes of private key
  #data 1: 25 4B r1 r2 k1 k2 k3 k4 k5
  $data = "254B" . $rlc . substr($attr{$name}{keySnd}, 0, 5*2);
  EnOcean_SndRadio(undef, $hash, 1, "35", $data, $subDef, "00", $destinationID);

  # prepare 2nd telegram

  #RORG = 35, TEACH_IN_INFO_1, KEY, ID, STATUS as defined in Security_of_EnOcean_Radio_Networks.pdf page 17
  #set TEACH_IN_INFO = 40 -> 0100.0000 -> IDX =1, CNT = 0, PSK = 0, TYPE = 0, INFO = 0

  #get 2nd 11 bytes of private key
  #data 2: 40 k6 k7 k8 k9 k10 k11 k12 k13 k14 k15 k16
  $data = "40" . substr($attr{$name}{keySnd}, 10, 11*2);
  EnOcean_SndRadio(undef, $hash, 1, "35", $data, $subDef, "00", $destinationID);

  return (undef, "secure teach-in", 2);
}

#
sub EnOcean_sec_convertToSecure($$$$)
{
  my ($hash, $packetType, $rorg, $data) = @_;
  my ($err, $response, $loglevel);
  my $name = $hash->{NAME};
  my $secLevel = AttrVal($name, "secLevel", "off");
  # encryption needed?
  return ($err, $rorg, $data, $response, 5) if ($rorg =~ m/^F6|35$/ || $secLevel !~ m/^encapsulation|encryption$/);
  return ("Cryptographic functions are not available", undef, undef, $response, 2) if ($cryptFunc == 0);
  my $dataEnc = AttrVal($name, "dataEnc", undef);
  my $subType = AttrVal($name, "subType", "");

  # subType specific actions
  if ($subType eq "switch.00" || $subType eq "windowHandle.10") {
    # securemode for D2-03-00 and D2-03-10
    if (hex($data) > 15) {
      return("wrong data byte", $rorg, $data, $response, 2);
    }

    # set rorg to secure telegram
    $rorg = "30";

  } else {
    return("Cryptographic functions for $subType not available", $rorg, $data, $response, 2);
  }

  #Get and update RLC
  my $rlc = EnOcean_sec_getRLC($hash, "rlcSnd", 0, undef);
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: Got actual RLC: $rlc";

  #Get key of device
  my $pKey = AttrVal($name, "keySnd", undef);
  return("private key not defined", $rorg, $data, $response, 2) if (!defined $pKey);
  $pKey = pack('H32', $pKey);
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: key: " . AttrVal($name, "keySnd", "");
  #prepare data
  my $rlc_expanded = pack('H32', $rlc);
  my $data_expanded = pack('H32', $data);
  my $data_dec;
  if ($dataEnc eq "VAES") {
    $data_dec = EnOcean_sec_decodeVAES($rlc_expanded, $pKey, $data_expanded);
  } else {
    return("Cryptographic functions not available", $rorg, $data, $response, 2);
  }
  my $data_end = unpack('H32', $data_dec);
  #get the correct nibble
  $data_end =~ /^.(.)/;
  $data_end = uc("0$1");
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: Crypted Data: $data_end";
  # calc MAC
  my $macAlgo = AttrVal($name, "macAlgo", undef);
  return("MAC Algorithm not defined", $rorg, $data, $response, 2) if (!defined $macAlgo);
  my $mac = EnOcean_sec_generateMAC($pKey, $rorg . $data_end . $rlc, $macAlgo);
  # combine message
  $data = $data_end . uc($mac);
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: Crypted Payload: $data";
  return(undef, $rorg, $data, $response, 5);
}

#
sub
EnOcean_NumericSort
{
  if ($a < $b) {
    return -1;
  } elsif ($a == $b) {
    return 0;
  } else {
    return 1;
  }
}

sub EnOcean_TimeDiff($)
{
  my ($strTS) = @_;
  if (defined $strTS) {
    my $timeDiff = gettimeofday() - ($strTS eq "" ? gettimeofday() : time_str2num($strTS));
    $timeDiff = 0 if ($timeDiff < 0);
    return $timeDiff;
  } else {
    return 0;
  }
}

# Undef
sub
EnOcean_Undef($$)
{
  my ($hash, $name) = @_;
  delete $hash->{helper};
  delete $modules{EnOcean}{defptr}{uc($hash->{DEF})};
  delete $modules{EnOcean}{defptr}{uc($attr{$name}{remoteID})} if (exists $attr{$name}{remoteID});
  if (AttrVal($name, "remoteManagement", "off") eq "client") {
    delete $hash->{RemoteClientUnlock};
    RemoveInternalTimer($hash->{helper}{timer}{RemoteClientUnlock}) if(exists $hash->{helper}{timer}{RemoteClientUnlock});
  }
  return undef;
}

# Delete
sub
EnOcean_Delete($$)
{
  my ($hash, $name) = @_;
  my $logName = "FileLog_$name";
  my ($count, $gplotFile, $logFile, $weblinkName, $weblinkHash);
  Log3 $name, 2, "EnOcean $name deleted";
  # delete FileLog device and log files
  if (exists $defs{$logName}) {
    $logFile = $defs{$logName}{logfile};
    $logFile =~ /^(.*)($name).*\.(.*)$/;
    $logFile = $1 . $2 . "*." . $3;
    CommandDelete(undef, "FileLog_$name");
    Log3 $name, 2, "EnOcean FileLog_$name deleted";
    $count = unlink glob $logFile;
    Log3 $name, 2, "EnOcean $logFile >> $count files deleted";
  }
  # delete SVG devices and gplot files
  while (($weblinkName, $weblinkHash) = each(%defs)) {
    if ($weblinkName =~ /^SVG_$name.*/) {
      $gplotFile = "./www/gplot/" . $defs{$weblinkName}{GPLOTFILE} . "*.gplot";
      CommandDelete(undef, $weblinkName);
      Log3 $name, 2, "EnOcean $weblinkName deleted";
      $count = unlink glob $gplotFile;
      Log3 $name, 2, "EnOcean $gplotFile >> $count files deleted";
    }
  }
  return undef;
}

1;

=pod
=item device
=item summary    EnOcean Gateway and Actor
=item summary_DE EnOcean Gateway und Aktor
=begin html

<a name="EnOcean"></a>
<h3>EnOcean</h3>
<ul><br>
  <b>Quick Links</b>
  <ul>
  <li><a href="#EnOceanget">Get Commands</a></li>
  <li><a href="#EnOceanset">Set Commands</a></li>
  <li><a href="#EnOceanattr">Attributes</a></li>
  <li><a href="#EnOceanevents">Generated Events</a></li>
  </ul><br><br>
  EnOcean devices are sold by numerous hardware vendors (e.g. Eltako, Peha, etc),
  using the RF Protocol provided by the EnOcean Alliance.<br><br>
  Depending on the function of the device an specific device profile is used, called
  EnOcean Equipment Profile (EEP). The specific definition of a device is referenced by
  the EEP (RORG-FUNC-TYPE). Basically four groups (RORG) will be differed, e. g.
  RPS (switches), 1BS (contacts), 4BS, VLD (sensors and controller). Some manufacturers use
  additional proprietary extensions. RORG MSC is not supported except for few exceptions.
  Further technical information can be found at the
  <a href="http://www.enocean-alliance.org/de/enocean_standard/">EnOcean Alliance</a>,
  see in particular the
  <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>
  <br><br>
  The supplementary Generic Profiles approach instead defines a language to communicate the
  transmitted data types and ranges. The devices becomes self describing on their data
  structures in communication. The Generic Profiles include a language definition with
  a parameter selection that covers every possible measured value to be transmitted.
  Therefore, the approach does not only define parameters for the value recalculation algorithm
  but also includes specific signal definition. (e.g. physical units). Further technical
  information can be found at the
  <a href="https://www.enocean-alliance.org/fileadmin/redaktion/enocean_alliance/pdf/GenericProfiles_V1_Extract.pdf">Generic Profiles 1.0 Abstract</a>
  <br><br>
  Smart Acknowledge (Smart Ack) enables a special bidirectional communication. The communication is managed by a
  Controller that responds to the devices telegrams with acknowledges. Smart Ack is a bidirectional communication
  protocol between two actors. At least one actor must be an energy autarkic Sensor, and at least one must be a line
  powered Controller (Fhem). A sensor sends its data and expects the answer telegram in a predefined very short
  time slot. In this time Sensors receiver is active. For this purpose we declare a Post Master with Mail Boxes.
  A Mail Box is like a letter box for a Sensor and it specific to a single sender. Telegrams from Fhem are collected
  into the Mail Box. A Sensor can reclaim telegrams that are in his Mail Box.
  <br><br>
  Fhem recognizes a number of devices automatically. In order to teach-in, for
  some devices the sending of confirmation telegrams has to be turned on.
  Some equipment types and/or device models must be manually specified.
  Do so using the <a href="#EnOceanattr">attributes</a>
  <a href="#subType">subType</a> and <a href="#model">model</a>, see chapter
  <a href="#EnOceanset">Set</a> and
  <a href="#EnOceanevents">Generated events</a>. With the help of additional
  <a href="#EnOceanattr">attributes</a>, the behavior of the devices can be
  changed separately.
  <br><br>
  Fhem and the EnOcean devices must be trained with each other. To this, Fhem
  must be in the learning mode, see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>,
  <a href="#EnOcean_smartAck">Smart Ack Learning</a> and <a href="#TCM_learningMode">learningMode</a>.
  The teach-in procedure depends on the type of the devices.
  <br><br>
  Switches (EEP RPS) and contacts (EEP 1BS) are recognized when receiving the first message.
  Contacts can also send a teach-in telegram. Fhem not need this telegram.
  Sensors (EEP 4BS) has to send a teach-in telegram. The profile-less
  4BS teach-in procedure transfers no EEP profile identifier and no manufacturer
  ID. In this case Fhem does not recognize the device automatically. The proper
  device type must be set manually, use the <a href="#EnOceanattr">attributes</a>
  <a href="#subType">subType</a>, <a href="#manufID">manufID</a> and/or
  <a href="#model">model</a>. If the EEP profile identifier and the manufacturer
  ID are sent the device is clearly identifiable. Fhem automatically assigns
  these devices to the correct profile.
  <br><br>
  4BS devices can also be taught in special cases by using of confirmation telegrams. This method
  is used for the EnOcean Tipp-Funk devices. The function is activated via the attribute [<a href="#EnOcean_teachMethod">teachMethod</a>] = confirm.<br>
  For example the remote device Eltako TF100D can be learned as follows
  <ul><br>
  <code>define &lt;name&gt; EnOcean H5-38-08</code><br>
  set TF100D in learning mode<br>
  <code>set &lt;name&gt; teach</code>
  </ul>
  <br>
  Some 4BS, VLD or MSC devices must be paired bidirectional,
  see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.
  <br><br>
  Devices that communicate encrypted, has to taught-in through specific procedures.
  <br><br>
  Smart Ack Learning is a futher process where devices exchange information about each
  other in order to create the logical links in the EnOcean network and a Post Master Mail Box.
  It can result in Learn In or Learn Out, see <a href="#EnOcean_smartAck">Smart Ack Learning</a>.
  <br><br>
  Fhem supports many of most common EnOcean profiles and manufacturer-specific
  devices. Additional profiles and devices can be added if required.
  <br><br>
  In order to enable communication with EnOcean remote stations a
  <a href="#TCM">TCM</a> module is necessary.
  <br><br>
  Please note that EnOcean repeaters also send Fhem data telegrams again.
  Use the TCM <code>attr &lt;name&gt; <a href="#blockSenderID">blockSenderID</a> own</code>
  to block receiving telegrams with a TCM SenderIDs.
  <br><br>

  <b>Observing Functions</b><br>
  <ul>
    Interference or overloading of the radio transmission can prevent the reception of Fhem
    commands at the receiver. With the help of the observing function Fhem checks the reception
    of the acknowledgment telegrams of the actuator. If within one second no acknowledgment
    telegram is received, the last set command is sent again.
    The set command is repeated a maximum of 5 times. The maximum number can be specified in the attribute
    <a href="#EnOcean_observeCmdRepetition">observeCmdRepetition</a>.<br>
    The function can only be used if the actuator immediately after the reception of
    the set command sends an acknowledgment message.<br>
    The observing function is turned on by the Attribute <a href="#EnOcean_observe">observe.</a>
    In addition, further devices can be monitored. The names of this devices can be entered in the
    <a href="#EnOcean_observeRefDev">observeRefDev</a> attribute. If additional device are specified,
    the monitoring is stopped as soon as the first acknowledgment telegram of one of the devices was received (OR logic).
    If the <a href="#EnOcean_observeLogic">observeLogic</a> attribute is set to "and", the monitoring is stopped when a telegram
    was received by all devices (AND logic). Please note that the name of the own device has also to be entered in the
    <a href="#EnOcean_observeRefDev">observeRefDev</a> if required.<br>
    If the maximum number of retries is reached and still no all acknowledgment telegrams has been received, the reading
    "observeFailedDev" shows the faulty devices and the command can be executed, that is stored in the
    <a href="#EnOcean_observeErrorAction">observeErrorAction</a> attribute.
    <br><br>
  </ul>

  <b>Energy Management</b><br>
  <ul>
    <li><a href="#demand_response">Demand Response</a> (EEP A5-37-01)</li>
    Demand Response (DR) is a standard to allow utility companies to send requests for reduction in power
    consumption during peak usage times. It is also used as a means to allow users to reduce overall power
    comsumption as energy prices increase. The EEP was designed with a very flexible setting for the level
    (0...15) as well as a default level whereby the transmitter can specify a specific level for all
    controllers to use (0...100 % of either maximum or current power output, depending on the load type).
    The profile also includes a timeout setting to indicate how long the DR event should last if the
    DR transmitting device does not send heartbeats or subsequent new DR levels.<br>
    The DR actor controls the target actuators such as switches, dimmers etc. The DR actor
    is linked to the FHEM target actors via the attribute <a href="#EnOcean_demandRespRefDev">demandRespRefDev</a>.<br>
    <ul>
    <li>Standard actions are available for the following profiles:</li>
    <ul>
    <li>switch (setting the switching command for min, max by the attribute <a href="#EnOcean_demandRespMin">demandRespMin</a>,
    <a href="#EnOcean_demandRespMax">demandRespMax</a>)</li>
    <li>gateway/switching (on, off)</li>
    <li>gateway/dimming (dim 0...100, relative to the max or current set value)</li>
    <li>lightCtrl.01 (dim 0...255)</li>
    <li>actuator.01 (dim 0...100)</li>
    <li>roomSensorControl.01 (setpoint 0...255)</li>
    <li>roomSensorControl.05 (setpoint 0...255 or nightReduction 0...5 for Eltako devices)</li>
    <li>roomCtrlPanel.00 (roomCtrlMode comfort|economy)</li>
    </ul>
    <li>On the target actuator can be specified alternatively a freely definable command.
    The command sequence is stored in the attribute <a href="#EnOcean_demandRespAction">demandRespAction</a>.
    The command sequence can be designed similar to "notify". For the command sequence predefined variables can be used,
    eg. $LEVEL. This actions can be executed very flexible depending on the given energy
    reduction levels.
    </li>
    <li>Alternatively or additionally, a custom command sequence in the DR profile itself
    can be stored.
    </li>
    </ul>
    The profile has a master and slave mode.
    <ul>
    <li>In slave mode, demand response data telegrams received eg a control unit of the power utility,
    evaluated and the corresponding commands triggered on the linked target actuators. The behavior in
    slave mode can be changed by multiple attributes.
    </li>
    <li>In master mode, the demand response level is set by set commands and thus sends a corresponding
    data telegram and the associated target actuators are controlled. The demand response control
    value are specified by "level", "power", "setpoint" "max" or "min". Each other settings are
    calculated proportionally. In normal operation, ie without power reduction, the control value (level)
    is 15. Through the optional parameters "powerUsageScale", "randomStart", "randomEnd" and "timeout"
    the control behavior can be customized. The threshold at which the reading "powerUsageLevel"
    between "min" and "max" switch is specified with the attribute
    <a href="#EnOcean_demandRespThreshold">demandRespThreshold</a>.
    </li>
    </ul>
    Additional information about the profile itself can be found in the EnOcean EEP documentation.
  <br><br>
  </ul>

  <b>Remote Management</b><br>
  <ul>
    Remote Management allows EnOcean devices to be configured and maintained over the air.
    Thanks to Remote Management, sensors or switches IDs, for instance, can be stored or deleted from
    already installed actuators or gateways which are hard to access. Remote Management also allows querying
    debug information from the Remote Device and calling some manufacturer implemented functions.<br>
    Remote Management is performed by the Remote Manager, operated by the actor, on the
    managed Remote Device (Sensor, Gateway). The management is done through a series of
    commands and responding answers. Actor sends the commands to the Remote Device. Remote
    Device sends answers to the actor. The commands indicate the Remote Device what to do.
    Remote Device answers if requested by the command. The commands belong to one of the
    main use case categories, which are:
    <ul>
      <li>Security</li>
      <li>Locate / indentify remote device</li>
      <li>Get status</li>
      <li>Extended function</li>
    </ul>
    The management is often done with a group of Remote Devices. Commands are sent as
    addressed unicast telegrams, usually. In special cases broadcast transmission is also available.
    To avoid telegram collisions the Remote Devices respond to broadcast commands with a
    random delay.<br>
    The Security, Locate, and Get Status options provide to the actor basic operability of Remote
    management. Their purpose is to ensure the proper work of Remote Management when
    operating with several Remote Devices. These functions behave in the same way on every
    Remote Device. Every product that supports Remote Management provides these options.<br>
    Extended functions provide the real benefit of Remote Management. They vary from Remote
    Device to Remote Device. They depend on how and where the Remote Device is used.
    Therefore, not every Remote Device provides every extended function. It depends on the
    programmer / customer what extended functions he wants to add. There is a list of specified
    commands, but the manufacturer can also add manufacturer specific extended functions. These
    functions are identified by the manufacturer ID.<br>
    More information can be found on the <a href="http://www.enocean.com">EnOcean websites</a>.<br><ber>
    Fhem operates primarily as a remote manager. For tests but also a client device can be created.
    <br><br>
    The remote manager function must be activated for the desired device by
    <ul><br>
      <code>attr &lt;remote device name&gt; remote manager</code><br>
    </ul>
    <br><br>
    The remote client device must be defined as follows<br>
    <ul><br>
      <code>define &lt;client name&gt; EnOcean C5-00-00</code><br>
    </ul><br>
    and has to by unlocked for t seconds
    <ul><br>
      <code>set &lt;client name&gt; unlock &lt;t/s&gt;</code><br>
    </ul><br>
    Only one remote management client device should be defined.<br><br>

    For security reasons the remote management commands can only be accessed in the unlock
    period. The period can be entered in two cases:
    <ul>
      <li>Within 30min after device power-up if no CODE is set</li>
      <li>Within 30min after an unlock command with a correct 32bit security code is received</li>
    </ul>
    The unlock/lock period can be accessed only with the security code. The security code can be
    set whenever the Remote Device accepts remote management commands.<br>
    When the Remote Device is locked it does not respond to any command, but unlock and ping.
    When a wrong security code is received the Remote Device does not process unlock commands
    for a security period of 30 seconds.<br>
    Security code=0x000000 is the default value and has to be interpreted as: no CODE has been
    set. The actor can also set the security code to 0x000000 from a previously set value. If no
    security code is set, unlock after the unlock period is not processed. Only ping will be
    processed. Remote Management is not available until next power up. 0xFFFFFFFF is reserved
    and can not be used as security code.<br><br>
    To administrate a remote device whose Remote ID must be known. The Remote ID can be determined
    as follows:
    <ul><br>
      <code>attr &lt;name&gt; remote manager</code><br>
      power-up the remote device<br>
      <code>get &lt;name&gt; remoteID</code><br><br>
    </ul>
    All commands are described in the remote management chapters of the <a href="#EnOcean_remoteSet">set</a>-
    and <a href="#EnOcean_remoteGet">get</a>-commands.<br><br>
    The Remote Management Function is configured using the following attributes:<br>
    <ul>
      <li><a href="#EnOcean_remoteCode">remoteCode</a></li>
      <li><a href="#EnOcean_remoteEEP">remoteEEP</a></li>
      <li><a href="#EnOcean_remoteID">remoteID</a></li>
      <li><a href="#EnOcean_remoteManagement">remoteManagement</a></li>
      <li><a href="#EnOcean_remoteManufID">remoteManufID</a></li>
    </ul><br>
    The content of events is described in the chapter <a href="#EnOcean_remoteEvents">Remote Management Events</a><br><br>.
    The following extended functions are supported:
    <ul>
      <li>210:remoteLinkTableInfo</li>
      <li>211:remoteLinkTable</li>
      <li>212:remoteLinkTable</li>
      <li>213:remoteLinkTableGP</li>
      <li>214:remoteLinkTableGP</li>
      <li>220:remoteLearnMode</li>
      <li>221:remoteTeach</li>
      <li>224:remoteReset</li>
      <li>225:remoteRLT</li>
      <li>226:remoteApplyChanges</li>
      <li>227:remoteProductID</li>
      <li>230:remoteDevCfg</li>
      <li>231:remoteDevCfg</li>
      <li>232:remoteLinkCfg</li>
      <li>233:remoteLinkCfg</li>
      <li>240:remoteAck</li>
      <li>250:remoteRepeater</li>
      <li>251:remoteRepeater</li>
      <li>252:remoteRepeaterFilter</li>
    </ul>
    <br><br>
  </ul>

  <b>Signal Telegram</b><br>
  <ul>
    Signal Telegram as a feature is dedicated to signalize special events with optional data, trigger actions or
    request responses. It extends the functionality of the device independently of used EEPs or other
    communication profiles.<br>
    Target key functional fields are:
    <ul>
      <li>Communication flow control</li>
      <li>Energy harvesting and reporting</li>
      <li>Failure & issues reporting</li>
      <li>Radio link quality reporting</li>
    </ul>
    The Signal Telegram function commands are activated by the attribute <a href="#EnOcean_signal">signal</a>.
    All commands are described in the signal telegram chapter of the <a href="#EnOcean_signalGet">get</a>-commands.
    The content of events is described in the chapter <a href="#EnOcean_signalEvents">Signal Telegram Events</a>.
    <br><br>
  </ul>

  <b>Radio Link Test</b><br>
  <ul>
    Units supporting the Radio Link Test (RLT) shall offer a functionality that allows for radio link testing between them
    (Position A to Position B, point-to-point only). Fhem support at least 1BS and 4BS test messages. When two units
    perform radio link testing one unit needs to act in a mode called RLT Master and the other unit needs to act in
    a mode called RLT Slave. Fhem acts as RLT Master (subType radioLinkTest).<br>
    The Radio Link Test device must be defined as follows<br>
    <ul><br>
      <code>define &lt;name&gt; EnOcean A5-3F-00</code><br>
    </ul><br>
    and has to by activated
    <ul><br>
      <code>set &lt;name&gt; standby</code><br>
    </ul><br>
    Alternatively, the device can also be created automatically by autocreate. Only one RLT device may be defined in FHEM.<br>
    After activation the RLT Master listens for RLT Query messages. On reception of at least one RLT Query messsage the
    RLT Master responds and starts transmission of RLT MasterTest messages. After that the RLT Master awaits the response
    from the RLT Slave.<br>
    A radio link test communication consits of a minimum of 16 and a maximum of 256 RLT MasterTest messages. When the
    radio link test communication is completed the RLT Master gets deactivated automatically. The test results can be
    found in the log file.
    <br><br>
  </ul>

  <b>Security features</b><br>
  <ul>
    The receiving and sending of encrypted messages is supported. This module currently allows the secure operating mode of PTM 215
    based switches.<br>
    To receive secured telegrams, you first have to start the teach in mode via<br><br>
    <code>set &lt;IODev&gt; teach &lt;t/s&gt;</code><br><br>
    and then doing the following on the PTM 215 module:<br>
    <ul>
      <li>Remove the switch cover of the module</li>
      <li>Press both buttons of one rocker side (A0 & A1 or B0 & B1)</li>
      <li>While keeping the buttons pressed actuate the energy bow twice.</li><br>
    </ul>
    This generates two teach-in telegrams which create a Fhem device with the subType "switch.00" and synchronize the Fhem with
    the PTM 215. Both the Fhem and the PTM 215 now maintain a counter which is used to generate a rolling code encryption scheme.
    Also during teach-in, a private key is transmitted to the Fhem. The counter value is allowed to desynchronize for a maximum of
    128 counts, to allow compensating for missed telegrams, if this value is crossed you need to teach-in the PTM 215 again. Also
    if your Fhem installation gets erased including the state information, you need to teach in the PTM 215 modules again (which
    you would need to do anyway).<br><br>

    To send secured telegrams, you first have send a secure teach-in to the remode device<br><br>
    <ul>
      <code>set &lt;name&gt; teachInSec</code><br><br>
    </ul>
    As for the security of this solution, if someone manages to capture the teach-in telegrams, he can extract the private key,
    so the added security isn't perfect but relies on the fact, that none listens to you setting up your installation.
    <br><br>
    The cryptographic functions need the additional Perl modules Crypt/Rijndael and Crypt/Random. The module must be installed manually.
    With the help of CPAN at the operating system level, for example,<br><br>
    <ul>
      <code>/usr/bin/perl -MCPAN -e 'install Crypt::Rijndael'</code><br>
      <code>/usr/bin/perl -MCPAN -e 'install Crypt::Random'</code>
    </ul>
  <br><br>
  </ul>

  <a name="EnOceandefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EnOcean &lt;DEF&gt; [&lt;EEP&gt;]|getNextID|&lt;EEP&gt;</code>
    <br><br>

    Define an EnOcean device, connected via a <a href="#TCM">TCM</a> modul. The
    &lt;DEF&gt; is the SenderID/DestinationID of the device (8 digit hex number), for example
    <ul><br>
      <code>define switch1 EnOcean FFC54500</code><br>
    </ul><br>
    In order to control devices, you cannot reuse the SenderIDs/
    DestinationID of other devices (like remotes), instead you have to create
    your own, which must be in the allowed SenderID range of the underlying Fhem
    IO device, see <a href="#TCM">TCM</a> BaseID, LastID. For this first query the
    <a href="#TCM">TCM</a> with the <code>get &lt;tcm&gt; baseID</code> command
    for the BaseID. You can use up to 128 IDs starting with the BaseID shown there.
    If you are using an Fhem SenderID outside of the allowed range, you will see an
    ERR_ID_RANGE message in the Fhem log.<br>
    FHEM can assign a free SenderID alternatively, for example
    <ul><br>
      <code>define switch1 EnOcean getNextID</code><br>
    </ul><br>
    If the EEP is known, the appropriate device can be created with the basic parameters, for example
    <ul><br>
      <code>define sensor1 EnOcean FFC54500 A5-02-05</code><br>
    </ul><br>
    or
    <ul><br>
      <code>define sensor1 EnOcean A5-02-05</code><br>
    </ul><br>

   Inofficial EEP for special devices
   <ul>
     <li>G5-07-01 PioTek-Tracker<br></li>
     <li>G5-10-12 Room Sensor and Control Unit [Eltako FUTH65D]<br></li>
     <li>G5-38-08 Gateway, Dimming [Eltako FSG, FUD]<br></li>
     <li>H5-38-08 Gateway, Dimming [Eltako TF61D, TF100D]<br></li>
     <li>M5-38-08 Gateway, Switching [Eltako FSR14]<br></li>
     <li>N5-38-08 Gateway, Switching [Eltako TF61L, TF61R, TF100A, TF100L]<br></li>
     <li>G5-3F-7F Shutter [Eltako FSB]<br></li>
     <li>H5-3F-7F Shutter [Eltako TF61J]<br></li>
     <li>L6-02-01 Smoke Detector [Eltako FRW]<br></li>
     <li>G5-ZZ-ZZ Light and Presence Sensor [Omnio Ratio eagle-PM101]<br></li>
     <li>ZZ-13-03 Environmental Applications, Data Exchange (EEP A5-13-03)<br></li>
     <li>ZZ-13-04 Environmental Applications, Time and Day Exchange (EEP A5-13-04)<br></li>
     <li>ZZ-ZZ-ZZ EnOcean RAW profile<br></li>
     <br><br>
   </ul>

    The <a href="#autocreate">autocreate</a> module may help you if the actor or sensor send
    acknowledge messages or teach-in telegrams. In order to control this devices e. g. switches with
    additional SenderIDs you can use the attributes <a href="#subDef">subDef</a>,
    <a href="#subDef0">subDef0</a> and <a href="#subDefI">subDefI</a>.<br>
    Fhem communicates unicast, if bidirectional 4BS or UTE teach-in is used, see
    <a href="#EnOcean_teach-in"> Bidirectional Teach-In / Teach-Out</a>. In this case
    Fhem send unicast telegrams with its SenderID and the DestinationID of the device.
    <br><br>
  </ul>

  <a name="EnOceaninternals"></a>
  <b>Internals</b>
  <ul>
    <li>DEF: 0000000 ... FFFFFFFF|&lt;EEP&gt;<br>
      EnOcean DestinationID or SenderID<br>
      If the attributes subDef* are set, this values are used as EnOcean SenderID.<br>
      For an existing device, the device can be re-parameterized by entering the EEP.<br>
    </li>
    <li>Dev_EURID: 0000000 ... FFFFFFFF<br>
      EnOcean ChipID of the device<br>
    </li>
    <li>Dev_RepeatingCounter: 0...2<br>
      Number of forwardings by repeaters received by the device<br>
    </li>
    <li>Dev_RSSImax: LP/dBm<br>
      Largest field strength received by the device<br>
    </li>
    <li>Dev_RSSImin: LP/dBm<br>
      Smallest field strength received by the device<br>
    </li>
    <li>Dev_SubTelNum: 1...15<br>
      Number of sub telegrams received by the device<br>
    </li>
    <li>&lt;IODev&gt;_DestinationID: 0000000 ... FFFFFFFF<br>
      Received destination address, Broadcast radio: FFFFFFFF<br>
    </li>
    <li>&lt;IODev&gt;_PacketType: 1 ... 255<br>
      Number of the packet type of last data telegram received<br>
    </li>
    <li>&lt;IODev&gt;_ReceivingQuality: excellent|good|bad<br>
      excellent: RSSI >= -76 dBm (internal standard antenna sufficiently)<br>
      good: RSSI < -76 dBm and RSSI >= -87 dBm (good antenna necessary)<br>
      bad: RSSI < -87 dBm (repeater required)<br>
    </li>
    <li>&lt;IODev&gt;_RepeatingCounter: 0...2<br>
      Number of forwardings by repeaters<br>
    </li>
    <li>&lt;IODev&gt;_RSSI: LP/dBm<br>
      Received signal strength indication (best value of all received subtelegrams)<br>
    </li>
    <li>&lt;IODev&gt;_SubTelNum: 1...15<br>
      Number of sub telegrams received<br>
    </li>
    <br><br>
  </ul>

  <a name="EnOceanset"></a>
  <b>Set</b>
  <ul>
    <li><a name="EnOcean_teach-in">Teach-In / Teach-Out</a>
    <ul>
      <li>Teach-in remote devices</li>
      <br>
      <code>set &lt;IODev&gt; teach &lt;t/s&gt;</code>
      <br><br>
      Set Fhem in the learning mode.<br>
      A device, which is then also put in this state is to paired with
      Fhem. Bidirectional Teach-In / Teach-Out is used for some 4BS, VLD and MSC devices,
      e. g. EEP 4BS, RORG A5-20-01 (Battery Powered Actuator).<br>
      Bidirectional Teach-In for 4BS, UTE and Generic Profiles are supported.<br>
      <code>IODev</code> is the name of the TCM Module.<br>
      <code>t/s</code> is the time for the learning period.
      <br><br>
      Types of learning modes see <a href="#TCM_learningMode">learningMode</a>
      <br><br>
      Example:
      <ul><code>set TCM_0 teach 600</code></ul>
      <br>
      <li>RPS profiles Teach-In (switches)</li>
      <br>
      <code>set &lt;name&gt; A0|AI|B0|BI|C0|CI|D0|DI</code>
      <br><br>
      Send teach-in telegram to remote device.
      <br><br>
      <li>1BS profiles Teach-In (contact)</li>
      <br>
      <code>set &lt;name&gt; teach</code>
      <br><br>
      Send teach-in telegram to remote device.
      <br><br>
      <li>4BS profiles Teach-In (sensors, dimmer, room controller etc.)</li>
      <br>
      <code>set &lt;name&gt; teach</code>
      <br><br>
      Send teach-in telegram to remote device.<br>
      If no SenderID (attr subDef) was assigned before a learning telegram is sent for the first time, a free SenderID
      is assigned automatically.
      <br><br>
      <li>UTE - Universal Uni- and Bidirectional Teach-In</li>
      <br>
      <code>set &lt;name&gt; teachIn|teachOut</code>
      <br><br>
      Send teach-in telegram to remote device.<br>
      If no SenderID (attr subDef) was assigned before a learning telegram is sent for the first time, a free SenderID
      is assigned automatically.
      <br><br>
      <li>Generic Profiles Teach-In</li>
      <br>
      <code>set &lt;name&gt; teachIn|teachOut</code>
      <br><br>
      Send teach-in telegram to remote device.<br>
      If no SenderID (attr subDef) was assigned before a learning telegram is sent for the first time, a free SenderID
      is assigned automatically.
      <br><br>
      <li>Secure Devices Teach-In</li>
      <br>
      <code>set &lt;name&gt; teachInSec</code>
      <br><br>
      Secure teach-in to the remode device.<br>
      If no SenderID (attr subDef) was assigned before a learning telegram is sent for the first time, a free SenderID
      is assigned automatically.
      <br><br>
    </ul>
    </li>

    <li><a name="EnOcean_smartAck">Smart Ack Learning</a>
    <ul>
      <li>Teach-in remote Smart Ack devices</li>
      <br>
      <code>set &lt;IODev&gt; smartAckLearn &lt;t/s&gt;</code>
      <br><br>
      Set Fhem in the Smart Ack learning mode.<br>
      The post master fuctionality must be activated using the command <code>smartAckMailboxMax</code> in advance.<br>
      The simple learnmode is supported, see <a href="#TCM_smartAckLearnMode">smartAckLearnMode</a><br>
      A device, which is then also put in this state is to paired with
      Fhem. Bidirectional learn in for 4BS, UTE and Generic Profiles are supported.<br>
      <code>IODev</code> is the name of the TCM Module.<br>
      <code>t/s</code> is the time for the learning period.
      <br><br>
      Example:
      <ul><code>set TCM_0 smartAckLearn 600</code></ul>
      <br>
    </ul>
    </li>

    <li><a name="EnOcean_remoteSet">Remote Management</a>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>remoteAction<br>
          sent action command to perfoms an action, depending on the functionality of the device</li>
         <li>remoteApplyChanges devCfg|linkTable|no_change<br>
          apply changes</li>
         <li>remoteDevCfg &lt;index&gt; &lt;value&gt;<br>
          set configuration</li>
         <li>remoteLinkTable in|out &lt;index&gt; &lt;ID&gt; &lt;EEP&gt; &lt;channel&gt;<br>
          set link table content</li>
         <li>remoteLinkCfg in|out &lt;index&gt; &lt;data index&gt; &lt;value&gt;<br>
          set link based configuration</li>
         <li>remoteLinkTableGP in|out &lt;index&gt; &lt;GP channel description&gt;<br>
          set link table content</li>
         <li>remoteLock<br>
          locks the remote device or local client</li>
        <li>remoteLearnMode in|out|off &lt;index&gt;<br>
          initiate remote learn-in or learn-out of inbound index</li>
         <li>remoteReset devCfg|linkTableIn|linkTableOut|no_change<br>
          reset to defaults</li>
         <li>remoteRLT on|off &lt;number of RLT slaves&gt;<br>
          reset to defaults</li>
         <li>remoteRepeater on|off|filter &lt;level&gt; &lt;filter structure&gt;<br>
          set repeater functions</li>
         <li>remoteRepeaterFilter apply|block|delete|deleteAll destinationID|sourceID|rorg|rssi &lt;filter value&gt;<br>
          set repeater functions</li>
         <li>remoteSetCode<br>
          set the remote security code</li>
         <li>remoteTeach &lt;channel&gt;<br>
          request teach-in telegram from channel 00..FF</li>
         <li>remoteUnlock [1...1800]<br>
          unlocks the remote device or local client<br>
          The unlock period can be set in the client mode between 1s and 1800 s.</li>
          <br>
      [&lt;channel&gt;] = 00...FF<br>
      [&lt;EEP&gt;] = &lt;RORG&gt;-&lt;function&gt;-&lt;type&gt;<br>
      [&lt;filter structure&gt;] = AND|OR<br>
      [&lt;filter value&gt;] = &lt;destinationID&gt;|&lt;sourceID&gt;|&lt;RORG&gt;|&lt;LP/dBm&gt;<br>
      [&lt;GP channel description&gt;] = &lt;name of channel 00&gt;:&lt;O|I&gt;:&lt;channel type&gt;:&lt;signal type&gt;:&lt;value type&gt;[:&lt;resolution&gt;[:&lt;engineering min&gt;:&lt;scaling min&gt;:&lt;engineering max&gt;:&lt;scaling max&gt;]]<br>
      [&lt;ID&gt;] = 00000001...FFFFFFFE<br>
      [&lt;index&gt;] = 00...FF<br>
      [&lt;number of RLT slaves&gt;] = 01..7F<br>
      [&lt;level&gt;] = 1|2<br>
      [&lt;data index&gt;] = 0000...FFFF<br>
      [&lt;value&gt;] = n x 00...FF<br>
    </ul><br>
    </li><br>

    <li>Switch, Pushbutton Switch (EEP F6-02-01 ... F6-03-02)<br>
    RORG RPS [default subType]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of A0, AI, B0, BI, C0, CI, D0, DI,
    combinations of these and released.  First and second action can be sent
    simultaneously. Separate first and second action with a comma.<br>
    In fact we are trying to emulate a PT200 type remote.<br>
    If you define an <a href="#eventMap">eventMap</a> attribute with on/off,
    then you will be able to easily set the device from the <a
    href="#FHEMWEB">WEB</a> frontend.<br>
    <a href="#setExtensions">set extensions</a> are supported, if the corresponding
    <a href="#eventMap">eventMap</a> specifies the <code>on</code> and <code>off</code>
    mappings, for example <code>attr <name> eventMap on-till:on-till AI:on A0:off</code>.<br>
    With the help of additional <a href="#EnOceanattr">attributes</a>, the
    behavior of the devices can be adapt.<br>
    The attr subType must be switch. This is done if the device was created by autocreate.
    <br><br>
    Example:
    <ul><code>
      set switch1 BI<br>
      set switch1 B0,CI<br>
      attr eventMap BI:on B0:off<br>
      set switch1 on<br>
    </code></ul><br>
    </ul>
    </li>

    <li>Staircase off-delay timer (EEP F6-02-01 ... F6-02-02)<br>
        RORG RPS [Eltako FTN14, tested with Eltako FTN14 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>released<br>
        start timer</li>
    </ul><br>
    Set attr eventMap to B0:on BI:off, attr subType to switch, attr
    webCmd to on:released and if needed attr switchMode to pushbutton manually.<br>
    The attr subType must be switch. This is done if the device was created by autocreate.<br>
    Use the sensor type "Schalter" for Eltako devices. The Staircase
    off-delay timer is switched on when pressing "on" and the time will be started
    when pressing "released". "released" immediately after "on" is sent if
    the attr switchMode is set to "pushbutton".
    </li>
    <br><br>

    <li>Pushbutton Switch (EEP D2-03-00)<br>
         RORG VLD [EnOcean PTM 215 Modul]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>teachIn<br>
          initiate UTE teach-in</li>
       <li>teachInSec<br>
          initiate secure teach-in</li>
       <li>teachOut<br>
          initiate UTE teach-out</li>
        <li>A0|AI|B0|BI<br>
          issue switch command</li>
        <li>A0,B0|A0,AI|AI,B0|AI,BI<br>
          issue switch command</li>
       <li>pressed<br>
          energy bow pressed</li>
        <li>pressed34<br>
          3 or 4 buttons and energy bow pressed</li>
       <li>released<br>
          energy bow released</li><br>

    </ul>
    First and second action can be sent simultaneously. Separate first and second action with a comma.<br>
    If you define an <a href="#eventMap">eventMap</a> attribute with on/off,
    then you will be able to easily set the device from the <a href="#FHEMWEB">WEB</a> frontend.<br>
    <a href="#setExtensions">set extensions</a> are supported, if the corresponding
    <a href="#eventMap">eventMap</a> specifies the <code>on</code> and <code>off</code>
    mappings, for example <code>attr <name> eventMap on-till:on-till AI:on A0:off</code>.<br>
    If <a href="#EnOcean_comMode">comMode</a> is set to biDir the device can be controlled bidirectionally.<br>
    With the help of additional <a href="#EnOceanattr">attributes</a>, the behavior of the devices can be adapt.<br>
    The attr subType must be switch.00. This is done if the device was created by autocreate.
    <br><br>
    <ul>
    Example:
    <ul><code>
      set switch1 BI<br>
      set switch1 B0,CI<br>
      attr eventMap BI:on B0:off<br>
      set switch1 on<br>
    </code></ul><br>
    </ul>
    </li>

    <li>Single Input Contact, Door/Window Contact (EEP D5-00-01)<br>
        RORG 1BS [tested with Eltako FSR14]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>closed<br>
          issue closed command</li>
         <li>open<br>
          issue open command</li>
        <li>teach<br>
          initiate teach-in</li>
    </ul><br>
       The attr subType must be contact. The attribute must be set manually.
       A monitoring period can be set for signOfLife telegrams of the sensor, see
       <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
       Default is "off" and an interval of 1980 sec.<br>
       Set the manufID to 00D for Eltako devices that send a periodic voltage telegram. (For example TF-FKB)
    </li><br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-02)<br>
        [Thermokon SR04 PTS]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>setpoint [0 ... 255]<br>
          Set the actuator to the specifed setpoint.</li>
      <li>setpointScaled [&lt;floating-point number&gt;]<br>
          Set the actuator to the scaled setpoint.</li>
      <li>fanStage [auto|0|1|2|3]<br>
          Set fan stage</li>
      <li>switch [on|off]<br>
          Set switch</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      The scaling of the setpoint adjustment is device- and vendor-specific. Set the
      attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
      <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled setting
      setpointScaled.<br>
      The attr subType must be roomSensorControl.05. The attribute must be set manually.
    </li>
    <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-03)<br>
        [used for IntesisBox PA-AC-ENO-1i]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>setpoint [0 ... 255]<br>
          Set the actuator to the specifed setpoint.</li>
      <li>setpointScaled [&lt;floating-point number&gt;]<br>
          Set the actuator to the scaled setpoint.</li>
      <li>fanStage [auto|0|1|2|3]<br>
          Set fan stage</li>
      <li>switch [on|off]<br>
          Set switch</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      The scaling of the setpoint adjustment is device- and vendor-specific. Set the
      attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
      <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled setting
      setpointScaled.<br>
      The attr subType must be roomSensorControl.05 and attr manufID must be 019. The attribute must be set manually.
    </li>
    <br><br>

    <li>Room Sensor and Control Unit (A5-10-06 plus night reduction)<br>
        [Eltako FTR65DS, FTR65HS]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>desired-temp [t/&#176C [lock|unlock]]<br>
          Set the desired temperature.</li>
      <li>nightReduction [t/K [lock|unlock]]<br>
          Set night reduction</li>
      <li>setpointTemp [t/&#176C [lock|unlock]]<br>
          Set the desired temperature</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpointTemp
      command is sent when the reference device is updated.<br>
      This profil can be used with a further Room Sensor and Control Unit Eltako FTR55*
      to control a heating/cooling relay FHK12, FHK14 or FHK61. If Fhem and FTR55*
      is teached in, the temperature control of the FTR55* can be either blocked
      or to a setpoint deviation of +/- 3 K be limited. For this use the optional parameter
      [block] = lock|unlock, unlock is default.<br>
      The attr subType must be roomSensorControl.05 and attr manufID must be 00D.
      The attributes must be set manually.
    </li>
    <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-10)<br>
        [Thermokon SR04 * rH, Thanos SR *]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>setpoint [0 ... 255]<br>
          Set the actuator to the specifed setpoint.</li>
      <li>setpointScaled [&lt;floating-point number&gt;]<br>
          Set the actuator to the scaled setpoint.</li>
      <li>switch [on|off]<br>
          Set switch</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      The actual humidity will be taken from the humidity reported by
      a humidity reference device <a href="#EnOcean_humidityRefDev">humidityRefDev</a>
      primarily or from the attribute <a href="#EnOcean_humidity">humidity</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      The scaling of the setpoint adjustment is device- and vendor-specific. Set the
      attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
      <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled setting
      setpointScaled.<br>
      The attr subType must be roomSensorControl.01. The attribute must be set manually.
    </li>
    <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-12)<br>
        [Eltako FUTH65D]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>setpoint [0 ... 255]<br>
          Set the actuator to the specifed setpoint.</li>
      <li>setpointScaled [&lt;floating-point number&gt;]<br>
          Set the actuator to the scaled setpoint.</li>
      <li>switch [on|off]<br>
          Set switch</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      The attr subType must be roomSensorControl.01 and attr manufID must be 00D. The attribute must be set manually.
    </li>
    <br><br>

    <li>Environmental Applications<br>
        Data Exchange (EEP A5-13-03)<br>
        Time and Day Exchange (EEP A5-13-04)<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>sendDate<br>
        send a date telegram</li>
      <li>sendTime<br>
        send a time telegram</li>
      <li>start<br>
        start the periodic sending of the time</li>
      <li>stop<br>
        stop the periodic sending of the time</li>
      <li>teachDate<br>
        send the teach in telegram for date exchange</li>
      <li>teachTime<br>
        send the teach in telegram for time exchange</li>
    </ul><br>
       The periodic interval is configured using the attribute:<br>
       <ul>
       <li><a href="#EnOcean_sendTimePeriodic">sendTimePeriodic</a></li>
       </ul>
       The attr subType must be environmentApp and devMode is set to master. This is done with the help of the inofficial EEPs ZZ-13-03 or ZZ-13-04. Type
       <code>define <name> EnOcean ZZ-13-04 getNextID</code> manually.
    </li>
    <br><br>

    <li>Battery Powered Actuator (EEP A5-20-01)<br>
        [Kieback&Peter MD15-FTL-xx]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>setpoint setpoint/%<br>
          Set the actuator to the specifed setpoint (0...100). The setpoint can also be set by the
          <a href="#EnOcean_setpointRefDev">setpointRefDev</a> device if it is set.</li>
      <li>setpointTemp t/&#176C<br>
          Set the actuator to the specifed temperature setpoint. The temperature setpoint can also be set by the
          <a href="#EnOcean_setpointTempRefDev">setpointTempRefDev</a> device if it is set.<br>
          The FHEM PID controller calculates the actuator setpoint based on the temperature setpoint. The controller's
          operation can be set via the PID parameters <a href="#EnOcean_pidFactor_P">pidFactor_P</a>,
          <a href="#EnOcean_pidFactor_I">pidFactor_I</a> and <a href="#EnOcean_pidFactor_D">pidFactor_D</a>.<br>
          If the attribute pidCtrl is set to off, the PI controller of the actuator is used (selfCtrl mode). Please
          read the instruction manual of the device, whether the device has an internal PI controller.<br></li>
      <li>runInit<br>
          Maintenance Mode: Run init sequence</li>
      <li>valveOpens<br>
          Maintenance Mode: Valve opens<br>
          After the valveOpens command, the valve remains open permanently and can no longer be controlled by Fhem.
          By pressing the button on the device itself, the actuator is returned to its normal operating state.</li>
      <li>valveCloses<br>
          Maintenance Mode: Valve closes</li>
    </ul><br>
       The Heating Radiator Actuating Drive is configured using the following attributes:<br>
       <ul>
         <li><a href="#EnOcean_pidActorCallBeforeSetting">pidActorCallBeforeSetting</a></li>
         <li><a href="#EnOcean_pidActorErrorAction">pidActorErrorAction</a></li>
         <li><a href="#EnOcean_pidActorErrorPos">pidActorErrorPos</a></li>
         <li><a href="#EnOcean_pidActorLimitLower">pidActorLimitLower</a></li>
         <li><a href="#EnOcean_pidActorLimitUpper">pidActorLimitUpper</a></li>
         <li><a href="#EnOcean_pidCtrl">pidCtrl</a></li>
         <li><a href="#EnOcean_pidDeltaTreshold">pidDeltaTreshold</a></li>
         <li><a href="#EnOcean_pidFactor_P">pidFactor_P</a></li>
         <li><a href="#EnOcean_pidFactor_I">pidFactor_I</a></li>
         <li><a href="#EnOcean_pidFactor_D">pidFactor_D</a></li>
         <li><a href="#EnOcean_pidIPortionCallBeforeSetting">pidIPortionCallBeforeSetting</a></li>
         <li><a href="#EnOcean_pidSensorTimeout">pidSensorTimeout</a></li>
         <li><a href="#EnOcean_rcvRespAction">rcvRespAction</a></li>
         <li><a href="#EnOcean_setpointRefDev">setpointRefDev</a></li>
         <li><a href="#EnOcean_setpointSummerMode">setpointSummerMode</a></li>
         <li><a href="#EnOcean_setpointTempRefDev">setpointTempRefDev</a></li>
         <li><a href="#EnOcean_summerMode">summerMode</a></li>
         <li><a href="#temperatureRefDev">temperatureRefDev</a></li>
       </ul>
    The actual temperature will be reported by the Heating Radiator Actuating Drive or by the
    <a href="#temperatureRefDev">temperatureRefDev</a> if it is set. The internal temperature sensor
    of the Micropelt iTRV MVA-002 is not suitable as an actual temperature value for the PID controller.
    An external room thermostat is required.<br>
    The attr event-on-change-reading .* shut not by set. The PID controller expects periodic events.
    If these are missing, a communication alarm is signaled.<br>
    The attr subType must be hvac.01. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.<br>
    The command is not sent until the device wakes up and sends a message, usually
    every 10 minutes.
    </li>
    <br><br>

    <li>Heating Radiator Actuating Drive (EEP A5-20-04)<br>
        [Holter SmartDrive MX]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>setpoint setpoint/%<br>
          Set the actuator to the specifed setpoint (0...100). The setpoint can also be set by the
          <a href="#EnOcean_setpointRefDev">setpointRefDev</a> device if it is set.</li>
      <li>setpointTemp t/&#176C<br>
          Set the actuator to the specifed temperature setpoint. The temperature setpoint can also be set by the
          <a href="#EnOcean_setpointTempRefDev">setpointTempRefDev</a> device if it is set.<br>
          The FHEM PID controller calculates the actuator setpoint based on the temperature setpoint. The controller's
          operation can be set via the PID parameters <a href="#EnOcean_pidFactor_P">pidFactor_P</a>,
          <a href="#EnOcean_pidFactor_I">pidFactor_I</a> and <a href="#EnOcean_pidFactor_D">pidFactor_D</a>.</li>
      <li>runInit<br>
          Maintenance Mode: Run init sequence</li>
      <li>valveOpens<br>
          Maintenance Mode: Valve opens<br>
          After the valveOpens command, the valve remains open permanently and can no longer be controlled by Fhem.
          By pressing the button on the device itself, the actuator is returned to its normal operating state.</li>
      <li>valveCloses<br>
          Maintenance Mode: Valve closes</li>
    </ul><br>
       The Heating Radiator Actuating Drive is configured using the following attributes:<br>
       <ul>
         <li><a href="#EnOcean_blockKey">blockKey</a></li>
         <li><a href="#EnOcean_displayOrientation">displayOrientation</a></li>
         <li><a href="#EnOcean_measurementCtrl">measurementCtrl</a></li>
         <li><a href="#model">model</a></li>
         <li><a href="#EnOcean_pidActorCallBeforeSetting">pidActorCallBeforeSetting</a></li>
         <li><a href="#EnOcean_pidActorErrorAction">pidActorErrorAction</a></li>
         <li><a href="#EnOcean_pidActorErrorPos">pidActorErrorPos</a></li>
         <li><a href="#EnOcean_pidActorLimitLower">pidActorLimitLower</a></li>
         <li><a href="#EnOcean_pidActorLimitUpper">pidActorLimitUpper</a></li>
         <li><a href="#EnOcean_pidCtrl">pidCtrl</a></li>
         <li><a href="#EnOcean_pidDeltaTreshold">pidDeltaTreshold</a></li>
         <li><a href="#EnOcean_pidFactor_P">pidFactor_P</a></li>
         <li><a href="#EnOcean_pidFactor_I">pidFactor_I</a></li>
         <li><a href="#EnOcean_pidFactor_D">pidFactor_D</a></li>
         <li><a href="#EnOcean_pidIPortionCallBeforeSetting">pidIPortionCallBeforeSetting</a></li>
         <li><a href="#EnOcean_pidSensorTimeout">pidSensorTimeout</a></li>
         <li><a href="#EnOcean_rcvRespAction">rcvRespAction</a></li>
         <li><a href="#EnOcean_setpointRefDev">setpointRefDev</a></li>
         <li><a href="#EnOcean_setpointSummerMode">setpointSummerMode</a></li>
         <li><a href="#EnOcean_setpointTempRefDev">setpointTempRefDev</a></li>
         <li><a href="#EnOcean_summerMode">summerMode</a></li>
         <li><a href="#temperatureRefDev">temperatureRefDev</a></li>
         <li><a href="#EnOcean_wakeUpCycle">wakeUpCycle</a></li>
       </ul>
    The actual temperature will be reported by the Heating Radiator Actuating Drive or by the
    <a href="#temperatureRefDev">temperatureRefDev</a> if it is set.<br>
    The attr event-on-change-reading .* shut not by set. The PID controller expects periodic events.
    If these are missing, a communication alarm is signaled.<br>
    The attr subType must be hvac.04. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.<br>
    The OEM version of the Holter SmartDrive MX has an internal PID controller. This function is activated by
    attr <device> model Holter_OEM and attr <device> pidCtrl off.<br>
    The command is not sent until the device wakes up and sends a message, usually
    every 5 minutes.
    </li>
    <br><br>

    <li>Heating Radiator Actuating Drive (EEP A5-20-06)<br>
        [Micropelt iTRV MVA-005, OPUS Micropelt HOME]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>runInit<br>
          Maintenance Mode: Run init sequence</li>
      <li>setpoint setpoint/%<br>
          Set the actuator to the specifed setpoint (0...100). The setpoint can also be set by the
          <a href="#EnOcean_setpointRefDev">setpointRefDev</a> device if it is set.</li>
      <li>setpointTemp t/&#176C<br>
          Set the actuator to the specifed temperature setpoint. The temperature setpoint can also be set by the
          <a href="#EnOcean_setpointTempRefDev">setpointTempRefDev</a> device if it is set.<br>
          The FHEM PID controller calculates the actuator setpoint based on the temperature setpoint. The controller's
          operation can be set via the PID parameters <a href="#EnOcean_pidFactor_P">pidFactor_P</a>,
          <a href="#EnOcean_pidFactor_I">pidFactor_I</a> and <a href="#EnOcean_pidFactor_D">pidFactor_D</a>.</li>
      <li>standby<br>
          enter standby mode<br>
          After the standby command, the valve remains closed permanently and can no longer be controlled by Fhem.
          By pressing the button on the device itself, the actuator is returned to its normal operating state.</li>
    </ul><br>
       The Heating Radiator Actuating Drive is configured using the following attributes:<br>
       <ul>
         <li><a href="#EnOcean_blockKey">blockKey</a></li>
         <li><a href="#EnOcean_measurementTypeSelect">measurementTypeSelect</a></li>
         <li><a href="#model">model</a></li>
         <li><a href="#EnOcean_pidActorCallBeforeSetting">pidActorCallBeforeSetting</a></li>
         <li><a href="#EnOcean_pidActorErrorAction">pidActorErrorAction</a></li>
         <li><a href="#EnOcean_pidActorErrorPos">pidActorErrorPos</a></li>
         <li><a href="#EnOcean_pidActorLimitLower">pidActorLimitLower</a></li>
         <li><a href="#EnOcean_pidActorLimitUpper">pidActorLimitUpper</a></li>
         <li><a href="#EnOcean_pidCtrl">pidCtrl</a></li>
         <li><a href="#EnOcean_pidDeltaTreshold">pidDeltaTreshold</a></li>
         <li><a href="#EnOcean_pidFactor_P">pidFactor_P</a></li>
         <li><a href="#EnOcean_pidFactor_I">pidFactor_I</a></li>
         <li><a href="#EnOcean_pidFactor_D">pidFactor_D</a></li>
         <li><a href="#EnOcean_pidIPortionCallBeforeSetting">pidIPortionCallBeforeSetting</a></li>
         <li><a href="#EnOcean_pidSensorTimeout">pidSensorTimeout</a></li>
         <li><a href="#EnOcean_rcvRespAction">rcvRespAction</a></li>
         <li><a href="#EnOcean_setpointRefDev">setpointRefDev</a></li>
         <li><a href="#EnOcean_setpointSummerMode">setpointSummerMode</a></li>
         <li><a href="#EnOcean_setpointTempRefDev">setpointTempRefDev</a></li>
         <li><a href="#temperatureRefDev">temperatureRefDev</a></li>
         <li><a href="#EnOcean_summerMode">summerMode</a></li>
         <li><a href="#EnOcean_wakeUpCycle">wakeUpCycle</a></li>
         <li><a href="#EnOcean_windowOpenCtrl">windowOpenCtrl</a></li>
       </ul>
    The actual temperature will be reported by the Heating Radiator Actuating Drive or by the
    <a href="#temperatureRefDev">temperatureRefDev</a> if it is set.<br>
    The attr event-on-change-reading .* shut not by set. The PID controller expects periodic events.
    If these are missing, a communication alarm is signaled.<br>
    The attr subType must be hvac.06. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.<br>
    The actuator has an internal PID controller. This function is activated by
    attr <device> pidCtrl off.<br>
    The command is not sent until the device wakes up and sends a message, usually
    every 2 to 10 minutes.
    </li>
    <br><br>

    <li>Generic HVAC Interface (EEP A5-20-10)<br>
        [IntesisBox PA-AC-ENO-1i]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>ctrl auto|0...100<br>
          Set control variable</li>
      <li>fanSpeed auto|1...14<br>
          Set fan speed</li>
      <li>occupancy occupied|off|standby|unoccupied<br>
          Set room occupancy</li>
      <li>on<br>
          Set on</li>
      <li>off<br>
          Set off</li>
      <li>mode auto|heat|morning_warmup|cool|night_purge|precool|off|test|emergency_heat|fan_only|free_cool|ice|max_heat|eco|dehumidification|calibration|emergency_cool|emergency_stream|max_cool|hvc_load|no_load|auto_heat|auto_cool<br>
          Set mode</li>
      <li>teach<br>
          Teach-in</li>
      <li>vanePosition auto|horizontal|position_2|position_3|position_4|vertical|swing|vertical_swing|horizontal_swing|hor_vert_swing|stop_swing<br>
          Set vane position</li>
    </ul><br>
    The attr subType must be hvac.10. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Generic HVAC Interface - Error Control (EEP A5-20-11)<br>
        [IntesisBox PA-AC-ENO-1i]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>externalDisable disable|enable<br>
          Set external disablement</li>
      <li>remoteCtrl disable|enable<br>
          Dieable/enable remote controller</li>
      <li>teach<br>
          Teach-in</li>
      <li>window closed|opened<br>
          Set window state</li>
    </ul><br>
    The attr subType must be hvac.11. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Energy management, <a name="demand_response">demand response</a> (EEP A5-37-01)<br>
      demand response master commands<br>
      <ul>
        <code>set &lt;name&gt; &lt;value&gt;</code>
        <br><br>
        where <code>value</code> is
          <li>level 0...15 [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set demand response level</li>
          <li>max [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set power usage level to max</li>
          <li>min [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set power usage level to min</li>
          <li>power power/% [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set power</li>
          <li>setpoint 0...255 [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set setpoint</li>
          <li>teach<br>
            initiate teach-in</li>
      </ul><br>
        [&lt;powerUsageScale&gt;] = max|rel, [&lt;powerUsageScale&gt;] = max is default<br>
        [&lt;randomStart&gt;] = yes|no, [&lt;randomStart&gt;] = no is default<br>
        [&lt;randomEnd&gt;] = yes|no, [&lt;randomEnd&gt;] = no is default<br>
        [timeout] = 0/min | 15/min ... 3825/min, [timeout] = 0 is default<br>
        The attr subType must be energyManagement.01.<br>
        This is done if the device was created by autocreate.<br>
      </li>
      <br><br>

      <li><a name="Gateway">Gateway</a> (EEP A5-38-08)<br>
        The Gateway profile include 7 different commands (Switching, Dimming,
        Setpoint Shift, Basic Setpoint, Control variable, Fan stage, Blind Central Command).
        The commands can be selected by the attribute gwCmd or command line. The attribute
        entry has priority.<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>&lt;gwCmd&gt; &lt;cmd&gt; [subCmd]<br>
          initiate Gateway commands by command line</li>
        <li>&lt;cmd&gt; [subCmd]<br>
          initiate Gateway commands if attribute gwCmd is set.</li>
     </ul><br>
       The attr subType must be gateway. Attribute gwCmd can also be set to
       switching|dimming|setpointShift|setpointBasic|controlVar|fanStage|blindCmd.<br>
       This is done if the device was created by autocreate.<br>
       For Eltako devices attributes must be set manually.
    </li>
    <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Switching<br>
         [Eltako FLC61, FSA12, FSR14]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>on [lock|unlock]<br>
          issue switch on command</li>
        <li>off [lock|unlock]<br>
          issue switch off command</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be switching. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. For Eltako FSA12 attribute model must be set
        to Eltako_FSA12.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Dimming<br>
         [Eltako FUD12, FUD14, FUD61, FUD70, FSG14, ...]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>teach<br>
          initiate teach-in mode</li>
        <li>on [lock|unlock]<br>
          issue switch on command</li>
        <li>off [lock|unlock]<br>
          issue switch off command</li>
        <li>dim dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>dimup dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>dimdown dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        rampTime Range: t = 1 s ... 255 s or 0 if no time specified,
        for Eltako: t = 1 = fast dimming ... 255 = slow dimming or 0 = dimming speed on the dimmer used<br>
        The attr subType must be gateway and gwCmd must be dimming. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. Use the sensor type "PC/FVS" for Eltako devices.
     </li>
     <br><br>

    <li>Gateway (EEP A5-38-08)<br>
        Dimming of fluorescent lamps<br>
        [Eltako FSG70, tested with Eltako FSG70 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>off<br>
        issue switch off command</li>
      <li><a href="#setExtensions">set extensions</a> are supported.</li>
    </ul><br>
    The attr subType must be gateway and gwCmd must be dimming. Set attr eventMap to B0:on BI:off,
    attr subTypeSet to switch and attr switchMode to pushbutton manually.<br>
    Use the sensor type "Richtungstaster" for Eltako devices.
    </li>
    <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Setpoint shift<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>shift 1/K <br>
          issue Setpoint shift</li>
     </ul><br>
        Shift Range: T = -12.7 K ... 12.8 K<br>
        The attr subType must be gateway and gwCmd must be setpointShift.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Basic Setpoint<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>basic t/&#176C<br>
          issue Basic Setpoint</li>
     </ul><br>
        Setpoint Range: t = 0 &#176C ... 51.2 &#176C<br>
        The attr subType must be gateway and gwCmd must be setpointBasic.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Control variable<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>presence present|absent|standby<br>
          issue Room occupancy</li>
        <li>energyHoldOff normal|holdoff<br>
          issue Energy hold off</li>
        <li>controllerMode auto|heating|cooling|off<br>
          issue Controller mode</li>
        <li>controllerState auto|override <0 ... 100> <br>
          issue Control variable override</li>
     </ul><br>
        Override Range: cvov = 0 % ... 100 %<br>
        The attr subType must be gateway and gwCmd must be controlVar.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Fan stage<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>stage 0 ... 3|auto<br>
          issue Fan Stage override</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be fanStage.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         <a name="Blind Command Central">Blind Command Central</a><br>
         [not fully tested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>position/% [&alpha;/&#176]<br>
          drive blinds to position with angle value</li>
        <li>teach<br>
          initiate teach-in mode</li>
        <li>status<br>
          Status request</li>
        <li>opens<br>
          issue blinds opens command</li>
        <li>up tu/s ta/s<br>
          issue roll up command</li>
        <li>closes<br>
          issue blinds closes command</li>
        <li>down td/s ta/s<br>
          issue roll down command</li>
        <li>position position/% [&alpha;/&#176]<br>
          drive blinds to position with angle value</li>
        <li>stop<br>
          issue blinds stops command</li>
        <li>runtimeSet tu/s td/s<br>
          set runtime parameter</li>
        <li>angleSet ta/s<br>
          set angle configuration</li>
        <li>positionMinMax positionMin/% positionMax/%<br>
          set min, max values for position</li>
        <li>angleMinMax &alpha;o/&#176 &alpha;s/&#176<br>
          set slat angle for open and shut position</li>
        <li>positionLogic normal|inverse<br>
          set position logic</li>
     </ul><br>
        Runtime Range: tu|td = 0 s ... 255 s<br>
        Select a runtime up and a runtime down that is at least as long as the
        shading element or roller shutter needs to move from its end position to
        the other position.<br>
        Position Range: position = 0 % ... 100 %<br>
        Angle Time Range: ta = 0 s ... 25.5 s<br>
        Runtime value for the sunblind reversion time. Select the time to revolve
        the sunblind from one slat angle end position to the other end position.<br>
        Slat Angle: &alpha;|&alpha;o|&alpha;s = -180 &#176 ... 180 &#176<br>
        Position Logic, normal: Blinds fully opens corresponds to Position = 0 %<br>
        Position Logic, inverse: Blinds fully opens corresponds to Position = 100 %<br>
        The attr subType must be gateway and gwCmd must be blindCmd.<br>
        See also attributes <a href="#EnOcean_sendDevStatus">sendDevStatus and <a href="#EnOcean_serviceOn">serviceOn</a></a><br>
        The profile is linked with controller profile, see <a href="#Blind Status">Blind Status</a>.<br>
     </li>
     <br><br>

     <li>Extended Lighting Control (EEP A5-38-09)<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate remote teach-in</li>
        <li>on<br>
          issue switch on command</li>
        <li>off<br>
          issue switch off command</li>
        <li>dim dim [rampTime/s]<br>
          issue dim command</li>
        <li>dimup rampTime/s<br>
          issue dim command</li>
        <li>dimdown rampTime/s<br>
          issue dim command</li>
        <li>stop<br>
          stop dimming</li>
        <li>rgb &lt;red color value&gt&lt;green color value&gt&lt;blue color value&gt<br>
          issue color value command</li>
        <li>scene drive|store 0..15<br>
          store actual value in the scene or drive to scene value</li>
        <li>dimMinMax &lt;min value&gt &lt;max value&gt<br>
          set minimal and maximal dimmer value</li>
        <li>lampOpHours 0..65535<br>
          set the operation hours of the lamp</li>
        <li>block unlock|on|off|local<br>
          locking local operations</li>
        <li>meteringValues 0..65535 mW|W|kW|MW|Wh|kWh|MWh|GWh|mA|mV<br>
          set a new value for the energy metering (overwrite the actual value with the selected unit)</li>
        <li>meteringValues 0..6553.5 A|V<br>
          set a new value for the energy metering (overwrite the actual value with the selected unit)</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        color values: 00 ... FF hexadecimal<br>
        rampTime Range: t = 1 s ... 65535 s or 1 if no time specified, ramping time can be set by attribute
        <a href="#EnOcean_rampTime">rampTime</a><br>
        The attr subType or subTypSet must be lightCtrl.01. This is done if the device was created by autocreate.<br>
        The subType is associated with the subtype lightCtrlState.02.
     </li>
     <br><br>

    <li><a name="Manufacturer Specific Applications">Manufacturer Specific Applications</a> (EEP A5-3F-7F)<br>
        Shutter<br>
        [Eltako FSB12, FSB14, FSB61, FSB70, tested with Eltako devices only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>position/% [&alpha;/&#176]<br>
        drive blinds to position with angle value</li>
      <li>anglePos &alpha;/&#176<br>
        drive blinds to angle value</li>
      <li>closes<br>
        issue blinds closes command</li>
      <li>down td/s<br>
        issue roll down command</li>
      <li>opens<br>
        issue blinds opens command</li>
      <li>position position/% [&alpha;/&#176]<br>
        drive blinds to position with angle value</li>
      <li>stop<br>
        issue stop command</li>
     <li>teach<br>
        initiate teach-in mode</li>
      <li>up tu/s<br>
        issue roll up command</li>
    </ul><br>
      Run-time Range: tu|td = 1 s ... 255 s<br>
      Position Range: position = 0 % ... 100 %<br>
      Slat Angle Range: &alpha; = -180 &#176 ... 180 &#176<br>
      Angle Time Range: ta = 0 s ... 6 s<br>
      The devive can only fully controlled if the attributes <a href="#angleMax">angleMax</a>,
      <a href="#angleMin">angleMin</a>, <a href="#angleTime">angleTime</a>,
      <a href="#shutTime">shutTime</a> and <a href="#shutTimeCloses">shutTimeCloses</a>,
      are set correctly.
      If <a href="#EnOcean_settingAccuracy">settingAccuracy</a> is set to high, the run-time is sent in 1/10 increments.<br>
      Set attr subType to manufProfile, manufID to 00D and attr model to Eltako_FSB14|FSB61|FSB70|FSB_ACK manually.
      If the attribute model is set to Eltako_FSB_ACK, with the status "open_ack" the readings position and anglePos are also updated.<br>
      If the attribute <a href="#EnOcean_calAtEndpoints">calAtEndpoints</a>is to yes, the roller blind positions are calibrated when
      the endpoints are driven.<br>
      Use the sensor type "Szenentaster/PC" for Eltako devices.
    </li>
    <br><br>

    <li>Electronic switches and dimmers with Energy Measurement and Local Control (D2-01-00 - D2-01-12)<br>
        [Telefunken Funktionsstecker, PEHA Easyclick, AWAG Elektrotechnik AG Omnio UPS 230/xx,UPD 230/xx, NodOn in-wall module, smart plug]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>autoOffTime t/s [&lt;channel&gt;]<br>
        set auto Off timer</li>
      <li>delayOffTime t/s [&lt;channel&gt;]<br>
        set delay Off timer</li>
      <li>dim/% [&lt;channel&gt; [&lt;rampTime&gt;]]<br>
        issue dimming command</li>
      <li>extSwitchMode unavailable|switch|pushbutton|auto [&lt;channel&gt;]<br>
        set external interface mode</li>
      <li>extSwitchType toggle|direction [&lt;channel&gt;]<br>
        set external interface type</li>
      <li>on [&lt;channel&gt;]<br>
        issue switch on command</li>
      <li>off [&lt;channel&gt;]<br>
        issue switch off command</li>
      <li>dim dim/% [&lt;channel&gt; [&lt;rampTime&gt;]]<br>
        issue dimming command</li>
      <li>local dayNight day|night, day is default<br>
        set the user interface indication</li>
      <li>local defaultState on|off|last, off is default<br>
        set the default setting of the output channels when switch on</li>
      <li>local localControl enabled|disabled, enabled is default<br>
        enable the local control of the device</li>
      <li>local overCurrentShutdown off|restart, off is default<br>
        set the behavior after a shutdown due to an overcurrent</li>
      <li>local overCurrentShutdownReset not_active|trigger, not_active is default<br>
        trigger a reset after an overcurrent</li>
      <li>local powerFailure enabled|disabled, disabled is default<br>
        enable the power failure detection</li>
      <li>local rampTime&lt;1...3&gt; 0/s, 0.5/s ... 7/s, 7.5/s, 0 is default<br>
        set the dimming time of timer 1 ... 3</li>
      <li>local teachInDev enabled|disabled, disabled is default<br>
        enable the taught-in devices with different EEP</li>
      <li>measurement delta 0/s ... 4095/s, 0 is default<br>
        define the difference between two displayed measurements </li>
      <li>measurement mode energy|power, energy is default<br>
        define the measurand</li>
      <li>measurement report query|auto, query is default<br>
        specify the measurement method</li>
      <li>measurement reset not_active|trigger, not_active is default<br>
        resetting the measured values</li>
      <li>measurement responseTimeMax 10/s ... 2550/s, 10 is default<br>
        set the maximum time between two outputs of measured values</li>
      <li>measurement responseTimeMin 1/s ... 255/s, 1 is default<br>
        set the minimum time between two outputs of measured values</li>
      <li>measurement unit Ws|Wh|KWh|W|KW, Ws is default<br>
        specify the measurement unit</li>
      <li>roomCtrlMode off|comfort|comfort-1|comfort-2|economy|buildingProtection<br>
      set pilot wire mode</li>
      <li>special repeater off|1|2<br>
      set repeater level of device (additional NodOn command)
      </li>
    </ul><br>
       [autoOffTime] = 0 s ... 0.1 s ... 6553.4 s<br>
       [delayOffTime] = 0 s ... 0.1 s ... 6553.4 s<br>
       [channel] = 0...29|all|input, all is default<br>
       The default channel can be specified with the attr <a href="#EnOcean_defaultChannel">defaultChannel</a>.<br>
       [rampTime] = 1..3|switch|stop, switch is default<br>
       The attr subType must be actuator.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Blind Control for Position and Angle (D2-05-00 - D2-05-01)<br>
        [AWAG Elektrotechnik AG OMNIO UPJ 230/12, REGJ12/04M ]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>opens [&lt;channel&gt;]<br>
        issue blinds opens command</li>
      <li>closes [&lt;channel&gt;]<br>
        issue blinds closes command</li>
      <li>position position/% [[&alpha;/%] [[&lt;channel&gt;] [directly|opens|closes]]]<br>
        drive blinds to position with angle value</li>
      <li>anglePos &alpha;/%  [&lt;channel&gt;]<br>
        drive blinds to angle value</li>
      <li>stop  [&lt;channel&gt;]<br>
        issue stop command</li>
      <li>alarm  [&lt;channel&gt;]<br>
        set actuator to the "alarm" mode. When the actuator ist set to the "alarm" mode neither local
        nor central positioning and configuration commands will be executed. Before entering the "alarm"
        mode, the actuator will execute the "alarm action" as configured by the attribute <a href="#EnOcean_alarmAction">alarmAction</a>
      </li>
      <li>lock  [&lt;channel&gt;]<br>
        set actuator to the "blockade" mode. When the actuator ist set to the "blockade" mode neither local
        nor central positioning and configuration commands will be executed.
      </li>
      <li>unlock  [&lt;channel&gt;]<br>
        issue unlock command</li>
    </ul><br>
      Channel Range: 1 ... 4|all, default is all<br>
      Position Range: position = 0 % ... 100 %<br>
      Slat Angle Range: &alpha; = 0 % ... 100 %<br>
      The devive can only fully controlled if the attributes <a href="#EnOcean_alarmAction">alarmAction</a>,
      <a href="#angleTime">angleTime</a>, <a href="#EnOcean_reposition">reposition</a> and <a href="#shutTime">shutTime</a>
      are set correctly.<br>
      With the attribute <a name="EnOcean_defaultChannel">defaultChannel</a> the default channel can be specified.<br>
      The attr subType must be blindsCtrl.00 or blindsCtrl.01. This is done if the device was
      created by autocreate. To control the device, it must be bidirectional paired,
      see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Multisensor Windows Handle (D2-06-01)<br>
        [Soda GmbH]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>presence absent|present<br>
        set vacation mode</li>
      <li>handleClosedClick disable|enable<br>
        set handle closed click feature</li>
      <li>batteryLowClick disable|enable<br>
        set battery low click feature</li>
      <li>teachSlave contact|windowHandleClosed|windowHandleOpen|windowHandleTilted<br>
        sent teach-in to the slave devices (contact: EEP: D5-00-01, windowHandle: EEP F6-10-00)<br>
        The events window or handle will get forwarded once a slave-device contact or windowHandle is taught in.
        </li>
      <li>updateInterval t/s<br>
        set sensor update interval</li>
      <li>blinkInterval t/s<br>
        set vacation blink interval</li>
    </ul><br>
      sensor update interval Range: updateInterval = 5 ... 65535<br>
      vacation blick interval Range: blinkInterval = 3 ... 255<br>
      The multisensor window handle is configured using the following attributes:<br>
      <ul>
        <li><a href="#EnOcean_subDefH">subDefH</a></li>
        <li><a href="#EnOcean_subDefW">subDefW</a></li>
      </ul>
      The attr subType must be multisensor.01. This is done if the device was
      created by autocreate.
    </li>
    <br><br>

    <li>Room Control Panels (D2-10-00 - D2-10-02)<br>
        [Kieback & Peter RBW322-FTL]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>buildingProtectionTemp t/&#176C<br>
        set building protection temperature</li>
      <li>clearCmds [&lt;channel&gt;]<br>
        clear waiting commands</li>
      <li>comfortTemp t/&#176C<br>
        set comfort temperature</li>
      <li>config<br>
        Setting the configuration of the room controller, the configuration parameters are set using attributes.</li>
      <li>cooling auto|off|on|no_change<br>
        switch cooling</li>
      <li>deleteTimeProgram<br>
        delete time programs of the room controller</li>
      <li>desired-temp t/&#176C<br>
        set setpoint temperature</li>
      <li>economyTemp t/&#176C<br>
        set economy temperature</li>
      <li>fanSpeed fanspeed/%<br>
        set fan speed</li>
      <li>fanSpeedMode central|local<br>
        set fan speed mode</li>
      <li>heating auto|off|on|no_change<br>
        switch heating</li>
      <li>preComfortTemp t/&#176C<br>
        set pre comfort temperature</li>
      <li>roomCtrlMode buildingProtectionTemp|comfortTemp|economyTemp|preComfortTemp<br>
        select setpoint temperature</li>
      <li>setpointTemp t/&#176C<br>
        set current setpoint temperature</li>
      <li>time<br>
        set time and date of the room controller </li>
      <li>timeProgram<br>
        set time programms of the room contoller</li>
      <li>window closed|open<br>
        put the window state</li>
    </ul><br>
       Setpoint Range: t = 0 &#176C ... 40 &#176C<br>
       The room controller is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_blockDateTime">blockDateTime</a></li>
       <li><a href="#EnOcean_blockDisplay">blockDisplay</a></li>
       <li><a href="#EnOcean_blockFanSpeed">blockFanSpeed</a></li>
       <li><a href="#EnOcean_blockMotion">blockMotion</a></li>
       <li><a href="#EnOcean_blockProgram">blockProgram</a></li>
       <li><a href="#EnOcean_blockOccupany">blockOccupancy</a></li>
       <li><a href="#EnOcean_blockTemp">blockTemp</a></li>
       <li><a href="#EnOcean_blockTimeProgram">blockTimeProgram</a></li>
       <li><a href="#EnOcean_blockSetpointTemp">blockSetpointTemp</a></li>
       <li><a href="#EnOcean_daylightSavingTime">daylightSavingTime</a></li>
       <li><a href="#EnOcean_displayContent">displayContent</a></li>
       <li><a href="#EnOcean_pollInterval">pollInterval</a></li>
       <li><a href="#EnOcean_temperatureScale">temperatureScale</a></li>
       <li><a href="#EnOcean_timeNotation">timeNotation</a></li>
       <li><a href="#EnOcean_timeProgram[1-4]">timeProgram[1-4]</a></li>
       </ul>
       The attr subType must be roomCtrlPanel.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Room Control Panels (D2-11-01 - D2-11-08)<br>
        [Thermokon EasySens SR06 LCD-2T/-2T rh -4T/-4T rh]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>cooling on|off, default [colling] = off<br>
        set cooling symbol at the display</li>
      <li>desired-temp t/&#176C<br>
        set setpoint temperature</li>
      <li>fanSpeed auto|off|1|2|3<br>
        set fan speed</li>
      <li>heating on|off, default [heating] = off<br>
        set heating symbol at the display</li>
      <li>occupancy occupied|unoccupied<br>
        set occupancy state</li>
      <li>setpointTemp t/&#176C<br>
        set current setpoint temperature</li>
      <li>setpointShiftMax t/K<br>
        set setpoint shift max</li>
      <li>setpointType setpointTemp|setpointShift<br>
        set setpoint type</li>
      <li>window closed|open, default [window] = closed<br>
        set window open symbol at the display</li>
   </ul><br>
       Setpoint Range: t = 5 &#176C ... 40 &#176C<br>
       Setpoint Shift Max Range: t = 0 K ... 10 K<br>
       The attr subType must be roomCtrlPanel.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired by Smart Ack,
       see <a href="#EnOcean_smartAck">SmartAck Learning</a>.
    </li>
    <br><br>

    <li>Fan Control (D2-20-00 - D2-20-02)<br>
        [Maico ECA x RC/RCH, ER 100 RC, untested]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        fan on</li>
      <li>off<br>
        fan off</li>
      <li>desired-temp [t/&#176C]<br>
        set setpoint temperature</li>
      <li>fanSpeed fanspeed/%|auto|default<br>
        set fan speed</li>
      <li>humidityThreshold rH/%<br>
        set humidity threshold</li>
      <li>roomSize 0...350/m<sup>2</sup>|default|not_used<br>
        set room size</li>
      <li>setpointTemp [t/&#176C]<br>
        set current setpoint temperature</li>
    </ul><br>
       Setpoint Range: t = 0 &#176C ... 40 &#176C<br>
       The fan controller is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_setCmdTrigger">setCmdTrigger</a></li>
       <li><a href="#EnOcean_switchHysteresis">switchHysteresis</a></li>
       <li><a href="#temperatureRefDev">temperatureRefDev</a></li>
       </ul>
       The attr subType must be fanCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>. The profile
       behaves like a master. Only one fan can be taught as a slave.
    </li>
    <br><br>

    <li>Heating Actuator (D2-34-00 - D2-34-02)<br>
        [AWAG UPS230/10, UPS230/12, REGH12/08M]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>setpointTemp t/&#176C [&lt;channel&gt; [&lt;overrideTime/h&gt;]]<br>
         set the temperatur setpoint</li>
       <li>setpointTempRefDev [&lt;channel&gt;]<br>
         enable the temperature setpoint via room control unit</li>
      <li>setpointTempShift t/K [&lt;channel&gt; [&lt;overrideTime/h&gt;]]<br>
         set the temperatur setpoint shift</li>
    </ul><br>
       [setpointTemp] t = 0 &#176C ... 40 &#176C<br>
       [setpointTempShift] t = Range: t = -10 K ... 10 K<br>
       [channel] = 0...29|all, all is default<br>
       The default channel can be specified with the attr <a href="#EnOcean_defaultChannel">defaultChannel</a>.<br>
       [overrideTime] = 0 h ... 63 h, 0 is default (endless)<br>
       Duration of the override until fallback to the room control panel setpointTemp value.
       The attr subType must be heatingActuator.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Heat Recovery Ventilation (D2-50-00 - D2-50-11)<br>
        [untested]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>ventilation off|1...4|auto|demand|supplyAir|exhaustAir<br>
         select ventilation mode/level</li>
       <li>heatExchangerBypass opens|closes<br>
         override of automatic heat exchanger bypass control</li>
       <li>startTimerMode<br>
         enable timer operation mode</li>
       <li>CO2Threshold default|1/%<br>
         override CO2 threshold for CO2 control in automatic mode</li>
       <li>humidityThreshold default|rH/%<br>
         override humidity threshold for humidity control in automatic mode</li>
       <li>airQuatityThreshold default|1/%<br>
         override air qualidity threshold for air qualidity control in automatic mode</li>
       <li>roomTemp default|t/&#176C<br>
         override room temperature threshold for room temperature control mode</li>
    </ul><br>
       roomTemp Range: t = -63 &#176C ... 63 &#176C<br>
       xThreshold Range: 0 % ... 100 %<br>
       The attr subType must be heatRecovery.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Valve Control (EEP D2-A0-01)<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
         <li>closes<br>
          issue closes command (master)</li>
         <li>opens<br>
          issue opens command (master)</li>
         <li>closed<br>
          issue closed command (slave)</li>
         <li>open<br>
          issue open command (slave)</li>
         <li>teachIn<br>
          initiate UTE teach-in (slave)</li>
         <li>teachOut<br>
          initiate UTE teach-out (slave)</li>
    </ul><br>
       The valve controller is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_devMode">devMode</a></li>
       </ul>
       The attr subType must be valveCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>. The profile
       behaves like a master or slave, see <a href="#EnOcean_devMode">devMode</a>.
     </li>
    <br><br>

    <li>Generic Profiles<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>&lt;00 ... 64&gt;-&lt;channel name&gt; &lt;value&gt;<br>
        set channel value</li>
      <li>channelName &lt;channel number&gt;-&lt;channel name&gt;<br>
        rename channel</li>
      <li>teachIn<br>
        sent teach-in telegram</li>
      <li>teachOut<br>
        sent teach-out telegram</li>
    </ul><br>
       The generic profile device is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_comMode">comMode</a></li>
       <li><a href="#EnOcean_devMode">devMode</a></li>
       <li><a href="#EnOcean_gpDef">gpDef</a></li>
       <li><a href="#EnOcean_manufID">manufID</a></li>
       </ul>
       The attr subType must be genericProfile. This is done if the device was
       created by autocreate. If the profile in slave mode is operated, especially the channel
       definition in the gpDef attributes must be entered manually.
    </li>
    <br><br>

    <li>RAW Command<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>1BS|4BS|GPCD|GPSD|GPTI|GPTR|MSC|RPS|UTE|VLD data [status]<br>
        sent data telegram</li>
    </ul><br>
    [data] = &lt;1-byte hex ... 512-byte hex&gt;<br>
    [status] = 0x00 ... 0xFF<br>
    With the help of this command data messages in hexadecimal format can be sent.
    Telegram types (RORG) 1BS, 4BS, RPS, MSC, UTE, VLD, GPCD, GPSD, GPTI and GPTR are supported.
    For further information, see <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a> and
    Generic Profiles.
    </li>
    <br><br>

    <li>Radio Link Test<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>standby|stop<br>
        set RLT Master state
      </li>
      </ul><br>
        The Radio Link Test device is configured using the following attributes:<br>
      <ul>
        <li><a href="#EnOcean_rltRepeat">rltRepeat</a></li>
        <li><a href="#EnOcean_rltType">rltType</a></li>
      </ul>
      The attr subType must be readioLinkTest. This is done if the device was
      created by autocreate or manually by <code>define &lt;name&gt; EnOcean A5-3F-00</code><br>.
    </li>
    <br><br>

 </ul></ul>

  <a name="EnOceanget"></a>
  <b>Get</b>
  <ul>

    <li><a name="EnOcean_remoteGet">Remote Management</a>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>remoteDevCfg &lt;start data index&gt; &lt;end data index&gt;<br>
          get device configuration between start index and end index</li>
        <li>remoteFunctions<br>
          get a list of the supported extended functions</li>
         <li>remoteID<br>
          get the remote device ID</li>
        <li>remoteLinkTableInfo<br>
          query supported link table info</li>
        <li>remoteLinkCfg in|out &lt;index&gt; &lt;start data index&gt; &lt;end data index&gt; &lt;length&gt;<br>
          get link table between start index and end index</li>
        <li>remoteLinkTable in|out &lt;start index&gt; &lt;end index&gt;<br>
          get link table between start index and end index</li>
        <li>remoteLinkTableGP in|out &lt;index&gt;<br>
          get link table GP entry with index</li>
        <li>remotePing<br>
          get a ping response from the remote device</li>
        <li>remoteProductID<br>
          query product ID</li>
        <li>remoteRepeater<br>
          asks for the repeater status of the remote device</li>
        <li>remoteStatus<br>
          asks for the status info of the remote device</li>
        <br>
       [&lt;data index&gt;] = 0000...FFFF<br>
       [&lt;index&gt;] = 00...FF<br>
       [&lt;length&gt;] = n x 00...FF<br>
    </ul>
    </li><br><br>

    <li><a name="EnOcean_signalGet">Signal Telegram</a>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>signal energy<br>
          get the energy status</li>
        <li>signal revision<br>
          get the revision of the device</li>
         <li>signal RXlevel<br>
          get the RX level of receiced request</li>
        <li>signal harvester<br>
          get the energy current harvested reporting</li>
    </ul><br>
      Trigger status messages of the device.
    </li><br><br>

    <li>Dual Channel Switch Actuator (EEP A5-11-05)<br>
         [untested]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>status<br>
        status request</li>
    </ul><br>
        The attr subType or subTypSet must be switch.05. This is done if the device was created by autocreate.
    </li>
    <br><br>

    <li>Extended Lighting Control (EEP A5-38-09)<br>
         [untested]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>status<br>
        status request</li>
    </ul><br>
        The attr subType or subTypSet must be lightCtrl.01. This is done if the device was created by autocreate.<br>
        The subType is associated with the subtype lightCtrlState.02.
    </li>
    <br><br>

    <li>Electronic switches and dimmers with Energy Measurement and Local Control (D2-01-00 - D2-01-12)<br>
        [Telefunken Funktionsstecker, PEHA Easyclick, AWAG Elektrotechnik AG Omnio UPS 230/xx,UPD 230/xx, NodOn in-wall module, smart plug]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>roomCtrlMode<br>
       get pilot wire mode</li>
       <li>settings [&lt;channel&gt;]<br>
       get external interface settings</li>
       <li>status [&lt;channel&gt;]<br>
       </li>
       <li>measurement &lt;channel&gt; energy|power<br>
       </li>
       <li>special &lt;channel&gt; health|load|voltage|serialNumber<br>
       additional Permondo SmartPlug PSC234 commands
       </li>
       <li>special &lt;channel&gt; firmwareVersion|reset|taughtInDevID|taughtInDevNum<br>
       additional NodOn commands
       </li>

    </ul><br>
       The default channel can be specified with the attr <a href="#EnOcean_defaultChannel">defaultChannel</a>.<br>
       The attr subType must be actuator.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Blind Control for Position and Angle (D2-05-00)<br>
        [AWAG Elektrotechnik AG OMNIO UPJ 230/12, REGJ12/04M]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>position  [&lt;channel&gt;]<br>
        query position and angle value</li>
    </ul><br>
      Channel Range: 1 ... 4|all, default is all<br>
      The devive can only fully controlled if the attributes <a href="#EnOcean_alarmAction">alarmAction</a>,
      <a href="#angleTime">angleTime</a>, <a href="#EnOcean_reposition">reposition</a> and <a href="#shutTime">shutTime</a>
      are set correctly.<br>
      With the attribute <a name="EnOcean_defaultChannel">defaultChannel</a> the default channel can be specified.<br>
      The attr subType must be blindsCtrl.00 or blindsCrtl.01. This is done if the device was
      created by autocreate. To control the device, it must be bidirectional paired,
      see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Multisensor Windows Handle (D2-06-01)<br>
        [Soda GmbH]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>config<br>
        get configuration settings</li>
      <li>log<br>
        get log data</li>
    </ul><br>
      The multisensor window handle is configured using the following attributes:<br>
      <ul>
        <li><a href="#EnOcean_subDefH">subDefH</a></li>
        <li><a href="#EnOcean_subDefW">subDefW</a></li>
      </ul>
      The attr subType must be multisensor.01. This is done if the device was
      created by autocreate.
    </li>
    <br><br>

    <li>Room Control Panels (D2-10-00 - D2-10-02)<br>
        [Kieback & Peter RBW322-FTL]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>config<br>
         get the configuration of the room controler</li>
       <li>data<br>
         get data</li>
       <li>roomCtrl<br>
         get the parameter of the room controler</li>
       <li>timeProgram<br>
         get the time program</li>
    </ul><br>
       The attr subType must be roomCtrlPanel.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Fan Control (D2-20-00 - D2-20-02)<br>
        [Maico ECA x RC/RCH, ER 100 RC, untested]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>status<br>
         get the state of the room controler</li>
    </ul><br>
       The attr subType must be fanCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Heating Actuator (D2-34-00 - D2-34-02)<br>
        [AWAG UPS230/10, UPS230/12, REGH122/08M]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>setpoint [&lt;channel&gt;]<br>
         get the setpoint infos of the heating actuator</li>
       <li>status [&lt;channel&gt;]<br>
         get the state of the heating actuator</li>
    </ul><br>
       The attr subType must be heatingActuator.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Heat Recovery Ventilation (D2-50-00 - D2-50-11)<br>
        [untested]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>basicState<br>
         get the basic state</li>
       <li>extendedState<br>
         get the extended state</li>
    </ul><br>
       The attr subType must be heatRecovery.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Valve Control (EEP D2-A0-01)<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>state<br>
         get the state of the valve controler (master)</li>
    </ul><br>
      The attr subType must be valveCtrl.00. This is done if the device was
      created by autocreate. To control the device, it must be bidirectional paired,
      see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>. The profile
      behaves like a master or slave, see <a href="#EnOcean_devMode">devMode</a>.
    </li>
    <br><br>

  </ul><br>

  <a name="EnOceanattr"></a>
  <b>Attributes</b>
  <ul>
    <ul>
    <li><a name="actualTemp">actualTemp</a> t/&#176C<br>
      The value of the actual temperature, used by a Room Sensor and Control Unit
      or when controlling HVAC components e. g. Battery Powered Actuators (MD15 devices). Should by
      filled via a notify from a distinct temperature sensor.<br>
      If absent, the reported temperature from the HVAC components is used.
    </li>
    <li><a name="EnOcean_alarmAction">alarmAction</a> &lt;channel1&gt;[:&lt;channel2&gt;[:&lt;channel3&gt;[:&lt;channel4&gt;]]]<br>
      [alarmAction] = no|stop|opens|closes, default is no<br>
      Action that is executed before the actuator is entering the "alarm" mode.<br>
      Notice subType blindsCrtl.00, blindsCrtl.01: The attribute can only be set while the actuator is online.
    </li>
    <li><a name="angleMax">angleMax</a> &alpha;s/&#176, [&alpha;s] = -180 ... 180, 90 is default.<br>
      Slat angle end position maximum.<br>
      angleMax is supported for shutter.
    </li>
    <li><a name="angleMin">angleMin</a> &alpha;o/&#176, [&alpha;o] = -180 ... 180, -90 is default.<br>
      Slat angle end position minimum.<br>
      angleMin is supported for shutter.
    </li>
    <li><a name="angleTime">angleTime</a> &lt;channel1&gt;[:&lt;channel2&gt;[:&lt;channel3&gt;[:&lt;channel4&gt;]]]<br>
      subType blindsCtrl.00, blindsCtrl.01: [angleTime] = 0|0.01 .. 2.54, 0 is default.<br>
      subType manufProfile: [angleTime] = 0 ... 6, 0 is default.<br>
      Runtime value for the sunblind reversion time. Select the time to revolve
      the sunblind from one slat angle end position to the other end position.<br>
      Notice subType blindsCrtl.00: The attribute can only be set while the actuator is online.
    </li>
    <li><a name="EnOcean_blockDateTime">blockDateTime</a> yes|no, [blockDateTime] = no is default.<br>
      blockDateTime is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockDisplay">blockDisplay</a> yes|no, [blockDisplay] = no is default.<br>
      blockDisplay is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockFanSpeed">blockFanSpeed</a> yes|no, [blockFanSpeed] = no is default.<br>
      blockFanSpeed is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockKey">blockKey</a> yes|no, [blockKey] = no is default.<br>
      blockKey is supported for roomCtrlPanel.00 and hvac.04.
      </li>
    <li><a name="EnOcean_blockMotion">blockMotion</a> yes|no, [blockMotion] = no is default.<br>
      blockMotion is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockOccupany">blockOccupancy</a> yes|no, [blockOccupancy] = no is default.<br>
      blockOccupancy is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockTemp">blockTemp</a> yes|no, [blockTemp] = no is default.<br>
      blockTemp is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockTimeProgram">blockTimeProgram</a> yes|no, [blockTimeProgram] = no is default.<br>
      blockTimeProgram is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockSetpointTemp">blockSetpointTemp</a> yes|no, [blockSetpointTemp] = no is default.<br>
      blockSetPointTemp is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockUnknownMSC">blockUnknownMSC</a> yes|no,
      [blockUnknownMSC] = no is default.<br>
      If the structure of the MSC telegrams can not interpret the raw data to be output. Setting this attribute to yes,
      the output can be suppressed.
    </li>
    <li><a name="EnOcean_brightnessDayNight">brightnessDayNight</a> E_min/lx:E_max/lx,
      [brightnessDayNight] = 0...99000:0...99000, 10:20 is default.<br>
      Set switching thresholds for reading dayNight based on the reading brightness.
    </li>
    <li><a name="EnOcean_brightnessDayNightCtrl">brightnessDayNightCtrl</a> custom|sensor,
      [brightnessDayNightCtrl] = custom|sensor, sensor is default.<br>
      Control the dayNight reading through the device-specific or custom threshold and delay.
    </li>
    <li><a name="EnOcean_brightnessDayNightDelay">brightnessDayNightDelay</a> t_reset/s:t_set/s,
      [brightnessDayNightDelay] = 0...99000:0...99000, 600:600 is default.<br>
      Set switching delay for reading dayNight based on the reading brightness. The reading dayNight is reset or set
      if the thresholds are permanently undershot or exceed during the delay time.
    </li>
    <li><a name="EnOcean_brightnessSunny">brightnessSunny</a> E_min/lx:E_max/lx,
     [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
     Set switching thresholds for reading isSunny based on the reading brightness.
    </li>
   <li><a name="EnOcean_brightnessSunnyDelay">brightnessSunnyDelay</a> t_reset/s:t_set/s,
     [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
     Set switching delay for reading isSunny based on the reading brightness. The reading isSunny is reset or set
     if the thresholds are permanently undershot or exceed during the delay time.
   </li>
   <li><a name="EnOcean_brightnessSunnyEast">brightnessSunnyEast</a> E_min/lx:E_max/lx,
     [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
     Set switching thresholds for reading isSunnyEast based on the reading sunEast.
   </li>
   <li><a name="EnOcean_brightnessSunnyEastDelay">brightnessSunnyEastDelay</a> t_reset/s:t_set/s,
     [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
     Set switching delay for reading isSunnyEast based on the reading sunEast. The reading isSunnyEast is reset or set
     if the thresholds are permanently undershot or exceed during the delay time.
   </li>
   <li><a name="EnOcean_brightnessSunnySouth">brightnessSunnySouth</a> E_min/lx:E_max/lx,
     [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
     Set switching thresholds for reading isSunnySouth based on the reading sunSouth.
   </li>
   <li><a name="EnOcean_brightnessSunnySouthDelay">brightnessSunnySouthDelay</a> t_reset/s:t_set/s,
     [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
     Set switching delay for reading isSunnySouth based on the reading sunSouth. The reading isSunnySouth is reset or set
     if the thresholds are permanently undershot or exceed during the delay time.
   </li>
   <li><a name="EnOcean_brightnessSunnyWest">brightnessSunnyWest</a> E_min/lx:E_max/lx,
     [brightnessSunny] = 0...99000:0...99000, 20000:40000 is default.<br>
     Set switching thresholds for reading isSunnyWest based on the reading sunWest.
   </li>
   <li><a name="EnOcean_brightnessSunnyWestDelay">brightnessSunnyWestDelay</a> t_reset/s:t_set/s,
     [brightnessSunnyDelay] = 0...99000:0...99000, 120:30 is default.<br>
     Set switching delay for reading isSunnyWest based on the reading sunWest. The reading isSunnyWest is reset or set
     if the thresholds are permanently undershot or exceed during the delay time.
   </li>
   <li><a name="EnOcean_calAtEndpoints">calAtEndpoints</a> no|yes, [calAtEndpoints] = no is default<br>
     Callibrize shutter position at the endpoints. The shutter motor is switched on with the time of
     <a href="#shutTimeCloses">shutTimeCloses</a> if the end positions are selected.
   </li>
    <li><a name="EnOcean_comMode">comMode</a> biDir|confirm|uniDir, [comMode] = uniDir is default.<br>
      Communication Mode between an enabled EnOcean device and Fhem.<br>
      Unidirectional communication means a point-to-multipoint communication
      relationship. The EnOcean device e. g. sensors does not know the unique
      Fhem SenderID.<br>
      If the attribute is set to confirm Fhem awaits confirmation telegrams from the remote device.<br>
      Bidirectional communication means a point-to-point communication
      relationship between an enabled EnOcean device and Fhem. It requires all parties
      involved to know the unique Sender ID of their partners. Bidirectional communication
      needs a teach-in / teach-out process, see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <li><a name="EnOcean_dataEnc">dataEnc</a> VAES|AES-CBC, [dataEnc] = VAES is default<br>
      Data encryption algorithm
    </li>
    <li><a name="EnOcean_defaultChannel">defaultChannel</a> &lt;channel&gt;
      subType actuator.01: [defaultChannel] = all|input|0 ... 29, all is default.<br>
      subType blindsCtrl.00,  blindsCtrl.01: [defaultChannel] = all|1 ... 4, all is default.<br>
      Default device channel
    </li>
    <li><a name="EnOcean_daylightSavingTime">daylightSavingTime</a> supported|not_supported, [daylightSavingTime] = supported is default.<br>
      daylightSavingTime is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_demandRespAction">demandRespAction</a> &lt;command&gt;<br>
      Command being executed after an demand response command is set.  If &lt;command&gt; is enclosed in {},
      then it is a perl expression, if it is enclosed in "", then it is a shell command,
      else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the demand response
      readings $TYPE, $NAME, $LEVEL, $SETPOINT, $POWERUSAGE, $POWERUSAGESCALE, $POWERUSAGELEVEL, $STATE. In addition,
      the variables $TARGETNAME, $TARGETTYPE, $TARGETSTATE can be used if the action is executed
      on the target device. This data is available as a local variable in perl, as environment variable for shell
      scripts, and will be textually replaced for Fhem commands.
    </li>
    <li><a name="EnOcean_demandRespMax">demandRespMax</a> A0|AI|B0|BI|C0|CI|D0|DI, [demandRespMax] = B0 is default<br>
      Switch command which is executed if the demand response switches to a maximum.
    </li>
    <li><a name="EnOcean_demandRespMin">demandRespMin</a> A0|AI|B0|BI|C0|CI|D0|DI, [demandRespMax] = BI is default<br>
      Switch command which is executed if the demand response switches to a minimum.
    </li>
    <li><a name="EnOcean_demandRespRefDev">demandRespRefDev</a> &lt;name&gt;<br>
    </li>
    <li><a name="EnOcean_demandRespRandomTime">demandRespRandomTime</a> t/s [demandRespRandomTime] = 1 is default<br>
      Maximum length of the random delay at the start or end of a demand respose event in slave mode.
    </li>
    <li><a name="EnOcean_demandRespThreshold">demandRespThreshold</a> 0...15 [demandRespTheshold] = 8 is default<br>
      Threshold for switching the power usage level between minimum and maximum in the master mode.
    </li>
    <li><a name="EnOcean_demandRespTimeoutLevel">demandRespTimeoutLevel</a> max|last [demandRespTimeoutLevel] = max is default<br>
      Demand response timeout level in slave mode.
    </li>
    <li><a name="devChannel">devChannel</a> 00 ... FF, [devChannel] = FF is default<br>
      Number of the individual device channel, FF = all channels supported by the device
    </li>
    <li><a name="destinationID">destinationID</a> multicast|unicast|00000001 ... FFFFFFFF,
      [destinationID] = multicast is default<br>
      Destination ID, special values: multicast = FFFFFFFF, unicast = [DEF]
    </li>
    <li><a name="EnOcean_devMode">devMode</a> master|slave, [devMode] = master is default.<br>
      device operation mode.
    </li>
    <li><a href="#devStateIcon">devStateIcon</a></li>
    <li><a name="EnOcean_dimMax">dimMax</a> dim/%|off, [dimMax] = 255 is default.<br>
      maximum brightness value<br>
      dimMax is supported for the profile gateway/dimming.
      </li>
    <li><a name="EnOcean_dimMin">dimMin</a> dim/%|off, [dimMax] = off is default.<br>
      minimum brightness value<br>
      If [dimMax] = off, then the actuator takes down the ramp time set there.
      dimMin is supported for the profile gateway/dimming.
      </li>
    <li><a name="dimValueOn">dimValueOn</a> dim/%|last|stored,
      [dimValueOn] = 100 is default.<br>
      Dim value for the command "on".<br>
      The dimmer switched on with the value 1 % ... 100 % if [dimValueOn] =
      1 ... 100.<br>
      The dimmer switched to the last dim value received from the
      bidirectional dimmer if [dimValueOn] = last.<br>
      The dimmer switched to the last Fhem dim value if [dimValueOn] =
      stored.<br>
      dimValueOn is supported for the profile gateway/dimming.
      </li>
    <li><a href="#EnOcean_disable">disable</a> 0|1<br>
      If applied set commands will not be executed.
    </li>
    <li><a href="#EnOcean_disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...<br>
      Space separated list of HH:MM tupels. If the current time is between
      the two time specifications, set commands will not be executed. Instead of
      HH:MM you can also specify HH or HH:MM:SS. To specify an interval
      spawning midnight, you have to specify two intervals, e.g.:
      <ul>
        23:00-24:00 00:00-01:00
      </ul>
    </li>
    <li><a name="EnOcean_displayContent">displayContent</a>
      humidity|off|setpointTemp|temperatureExtern|temperatureIntern|time|default|no_change, [displayContent] = no_change is default.<br>
      displayContent is supported for roomCtrlPanel.00.
    </li>
    <li><a name="EnOcean_displayOrientation">displayOrientation</a> rad/&#176, [displayOrientation] = 0|90|180|270, 0 is default.<br>
      Display orientation of the actuator
    </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a name="EnOcean_eep">eep</a> &lt;00...FF&gt;-&lt;00...3F&gt;-&lt;00...7F&gt;<br>
      EnOcean Equipment Profile (EEP)
    <li><a href="#eventMap">eventMap</a></li>
    </li>
    <li><a name="EnOcean_gpDef">gpDef</a> &lt;name of channel 00&gt;:&lt;O|I&gt;:&lt;channel type&gt;:&lt;signal type&gt;:&lt;value type&gt;[:&lt;resolution&gt;[:&lt;engineering min&gt;:&lt;scaling min&gt;:&lt;engineering max&gt;:&lt;scaling max&gt;]] ...
                                          &lt;name of channel 64&gt;:&lt;O|I&gt;:&lt;channel type&gt;:&lt;signal type&gt;:&lt;value type&gt;[:&lt;resolution&gt;[:&lt;engineering min&gt;:&lt;scaling min&gt;:&lt;engineering max&gt;:&lt;scaling max&gt;]]
                                         <br>
      Generic Profiles channel definitions are set automatically in master mode. If the profile in slave mode is operated, the channel
      definition must be entered manually. For each channel, the channel definitions are to be given in ascending order. The channel
      parameters to be specified in decimal. First, the outgoing channels (direction = O) are to be defined, then the incoming channels
      (direction = I) should be described. The channel numbers are assigned automatically starting with 00th.
    </li>
    <li><a name="gwCmd">gwCmd</a> switching|dimming|setpointShift|setpointBasic|controlVar|fanStage|blindCmd<br>
      Gateway Command Type, see <a href="#Gateway">Gateway</a> profile
    </li>
    <li><a name="EnOcean_humidity">humidity</a> rH/%<br>
      The value of the actual humidity, used by a Room Sensor and Control Unit. Should by
      filled via a notify from a distinct humidity sensor.
    </li>
    <li><a name="EnOcean_humidityRefDev">humidityRefDev</a> &lt;name&gt;<br>
      Name of the device whose reference value is read. The reference values is
      the reading humidity.
    </li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a name="EnOcean_keyRcv">keyRcv</a> &lt;private key 16 byte hex&gt;<br>
      Private Key for receive direction
    </li>
    <li><a name="EnOcean_keySnd">keySnd</a> &lt;private key 16 byte hex&gt;<br>
      Private Key for send direction
    </li>
    <li><a name="EnOcean_macAlgo">macAlgo</a> no|3|4<br>
      MAC Algorithm
    </li>
    <li><a name="EnOcean_manufID">manufID</a> &lt;000 ... 7FF&gt;<br>
      Manufacturer ID number
    </li>
    <li><a name="EnOcean_measurementCtrl">measurementCtrl</a> enable|disable<br>
      Enable or disable the temperature measurements of the actuator. If the temperature
      measurements are turned off, the foot temperature may be displayed and an external temperature sensor must be exists, see attribute
      <a href="#temperatureRefDev">temperatureRefDev</a>.
    </li>
    <li><a name="EnOcean_measurementTypeSelect">measurementTypeSelect</a> foot|room<br>
      Select the temperature measurements type displayed by the actuator. If the temperature
      measurements are turned to foot, the foot temperature may be displayed and an external
      temperature sensor must be exists, see attribute <a href="#temperatureRefDev">temperatureRefDev</a>.
    </li>
    <li><a href="#model">model</a></li>
    <li><a name="EnOcean_observe">observe</a> off|on, [observe] = off is default.<br>
      Observing and repeating the execution of set commands
    </li>
    <li><a name="EnOcean_observeCmdRepetition">observeCmdRepetition</a> 1..5, [observeCmdRepetition] = 2 is default.<br>
      Maximum number of command retries
    </li>
    <li><a name="EnOcean_observeErrorAction">observeErrorAction</a> &lt;command&gt;<br>
      Command being executed after an error.  If &lt;command&gt; is enclosed in {},
      then it is a perl expression, if it is enclosed in "", then it is a shell command,
      else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the set
      command. $TYPE, $NAME, $FAILEDDEV, $EVENT, $EVTPART0, $EVTPART1, $EVTPART2, etc. contains the space separated
      set parts. The <a href="#eventMap">eventMap</a> replacements are taken into account. This data
      is available as a local variable in perl, as environment variable for shell
      scripts, and will be textually replaced for Fhem commands.
    </li>
    <li><a name="EnOcean_observeInterval">observeInterval</a> 1/s ... 255/s, [observeInterval] = 1 is default.<br>
      Interval between two observations
    </li>
    <li><a name="EnOcean_observeLogic">observeLogic</a> and|or, [observeLogic] = or is default.<br>
      Observe logic
    </li>
    <li><a name="EnOcean_observeRefDev">observeRefDev</a> &lt;name&gt; [&lt;name&gt; [&lt;name&gt;]],
      [observeRefDev] = &lt;name of the own device&gt; is default<br>
      Names of the devices to be observed. The list must be separated by spaces.
    </li>
    <li><a name="EnOcean_pidActorCallBeforeSetting">pidActorCallBeforeSetting</a>,
        [pidActorCallBeforeSetting] = not defined is default<br>
        Callback-function, which can manipulate the actorValue. Further information see modul PID20.
    </li>
    <li><a name="EnOcean_pidActorErrorAction">pidActorErrorAction</a> freeze|errorPos,
        [pidActorErrorAction] = freeze is default<br>
        required action on error
    </li>
    <li><a name="EnOcean_pidActorErrorPos">pidActorErrorPos</a> valvePos/%,
        [pidActorErrorPos] = 0...100, 0 is default<br>
        actor's position to be used in case of error
    </li>
    <li><a name="EnOcean_pidActorLimitLower">pidActorLimitLower</a> valvePos/%,
        [pidActorLimitLower] = 0...100, 0 is default<br>
        lower limit for actor
    </li>
    <li><a name="EnOcean_pidActorLimitUpper">pidActorLimitUpper</a> valvePos/%,
        [pidActorLimitUpper] = 0...100, 100 is default<br>
        upper limit for actor
    </li>
    <li><a name="EnOcean_pidCtrl">pidCtrl</a> on|off,
        [pidCtrl] = on is default<br>
        Activate the Fhem PID regulator
    </li>
    <li><a name="EnOcean_pidDeltaTreshold">pidDeltaTreshold</a> &lt;floating-point number&gt;,
        [pidDeltaTreshold] = 0 is default<br>
        if delta < delta-threshold the pid will enter idle state
    </li>
    <li><a name="EnOcean_pidFactor_P">pidFactor_P</a> &lt;floating-point number&gt;,
        [pidFactor_P] = 25 is default<br>
        P value for PID
    </li>
    <li><a name="EnOcean_pidFactor_I">pidFactor_I</a> &lt;floating-point number&gt;,
        [pidFactor_I] = 0.25 is default<br>
        I value for PID
    </li>
    <li><a name="EnOcean_pidFactor_D">pidFactor_D</a> &lt;floating-point number&gt;,
        [pidFactor_D] = 0 is default<br>
        D value for PID
    </li>
    <li><a name="EnOcean_pidIPortionCallBeforeSetting">pidIPortionCallBeforeSetting</a>
        [pidIPortionCallBeforeSetting] = not defined is default<br>
        Callback-function, which can manipulate the value of I-Portion. Further information see modul PID20.
    </li>
    <li><a name="EnOcean_pidSensorTimeout">pidSensorTimeout t/s</a>
        [pidSensorTimeout] = 3600 is default<br>
        number of seconds to wait before sensor <a href="#temperatureRefDev">temperatureRefDev</a> will be recognized n/a
    </li>
    <li><a name="EnOcean_pollInterval">pollInterval</a> t/s, [pollInterval] = 10 is default.<br>
      [pollInterval] = 1 ... 1440.<br>
      pollInterval is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_rampTime">rampTime</a> t/s or relative, [rampTime] = 1 is default.<br>
      No ramping or for Eltako dimming speed set on the dimmer if [rampTime] = 0.<br>
      Gateway/dimmung: Ramping time 1 s to 255 s or relative fast to low dimming speed if [rampTime] = 1 ... 255.<br>
      lightCtrl.01: Ramping time 1 s to 65535 s<br>
      rampTime is supported for gateway, command dimming and lightCtrl.01.
      </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="EnOcean_rcvRespAction">rcvRespAction</a> &lt;command&gt;<br>
      Command being executed after an message from the aktor is received and before an response message is sent.
      If &lt;command&gt; is enclosed in {}, then it is a perl expression, if it is enclosed in "", then it is a shell command,
      else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the name of the device by using $NAME
      and the current readings $ACTUATORSTATE, $BATTERY, $COVER, $ENERGYINPUT, $ENERGYSTORAGE, $MAINTENANCEMODE, $OPERATIONMODE,
      $ROOMTEMP, $SELFCTRL, $SETPOINT, $SETPOINTTEMP, $SUMMERMODE, $TEMPERATURE, $WINDOW for the subType hvac.01, $NAME,
      $BATTERY, $FEEDTEMP, $MAINTENANCEMODE, $OPERATIONMODE, $ROOMTEMP, $SETPOINT, $SETPOINTTEMP, $SUMMERMODE, $TEMPERATURE
      for the subType hvac.04 and $ACTUATORSTATE, $BATTERY, $ENERGYINPUT, $ENERGYSTORAGE, $FEEDTEMP, $MAINTENANCEMODE, $OPERATIONMODE,
      $RADIOCOMERR, $RADIOSIGNALSTRENGTH, $ROOMTEMP, $SETPOINT, $SETPOINTTEMP, $SETPOINTTEMPLOCAL, $SUMMERMODE, $TEMPERATURE, $WINDOW
      for the subType hvac.06.
      This data is available as a local variable in perl, as environment variable for shell
      scripts, and will be textually replaced for Fhem commands.
    </li>
    <li><a name="EnOcean_remoteCode">remoteCode</a> &lt;00000000...FFFFFFFE&gt;<br>
      Remote Management Security Code, 00000000 is interpreted as on code has been set.
    </li>
    <li><a name="EnOcean_remoteEEP">remoteEEP</a> &lt;00...FF&gt;-&lt;00...3F&gt;-&lt;00...7F&gt;<br>
      Remote Management EnOcean Equipment Profile (EEP)
    </li>
    <li><a name="EnOcean_remoteID">remoteID</a> &lt;00000001...FFFFFFFE&gt;<br>
      Remote Management Remote Device ID
    </li>
    <li><a name="EnOcean_remoteManagement">remoteManagement</a> client|manager|off,
      [remoteManagement] = off is default.<br>
      Enable Remote Management for the device.
    </li>
    <li><a name="EnOcean_remoteManufID">remoteManufID</a> &lt;000...7FF&gt;<br>
      Remote Management Manufacturer ID
    </li>
    <li><a name="repeatingAllowed">repeatingAllowed</a> yes|no,
      [repeatingAllowed] = yes is default.<br>
      EnOcean Repeater in the transmission range of Fhem may forward data messages
      of the device, if the attribute is set to yes.
    </li>
    <li><a name="EnOcean_releasedChannel">releasedChannel</a> A|B|C|D|I|0|auto, [releasedChannel] = auto is default.<br>
      Attribute releasedChannel determines via which SenderID (subDefA ... subDef0) the command released is sent.
      If [releasedChannel] = auto, the SenderID the last command A0, AI, B0, BI, C0, CI, D0 or DI is used.
      Attribute releasedChannel is supported for attr switchType = central and attr switchType = channel.
      </li>
    <li><a name="EnOcean_reposition">reposition</a> directly|opens|closes, [reposition] = directly is default.<br>
      Attribute reposition specifies how to adjust the internal positioning tracker before going to the new position.
      </li>
    <li><a name="EnOcean_rlcAlgo">rlcAlgo</a> 2++|3++<br>
      RLC Algorithm
    </li>
    <li><a name="EnOcean_rlcRcv">rlcRcv</a> &lt;rolling code 2 or 3 byte hex&gt;<br>
      Rolling Code for receive direction
    </li>
    <li><a name="EnOcean_rlcSnd">rlcSnd</a> &lt;rolling code 2 or 3 byte hex&gt;<br>
      Rolling Code for send direction
    </li>
    <li><a name="EnOcean_rlcTX">rlcTX</a> false|true<br>
      Rolling Code is expected in the received telegram
    </li>
    <li><a name="EnOcean_rltRepeat">rltRepeat</a> 16|32|64|128|256,
      [rltRepeat] = 16 is default.<br>
      Number of RLT MasterTest messages sent
    </li>
    <li><a name="EnOcean_rltType">rltType</a> 1BS|4BS,
      [rltType] = 4BS is default.<br>
      Type of RLT MasterTest message
    </li>
    <li><a name="scaleDecimals">scaleDecimals</a> 0 ... 9<br>
      Decimal rounding with x digits of the scaled reading setpoint
    </li>
    <li><a name="EnOcean_teachMethod">teachMethod</a> 1BS|4B|confirm|GP|RPS|smartAck|STE|UTE<br>
      teach-in method
    </li>
    <li><a name="scaleMax">scaleMax</a> &lt;floating-point number&gt;<br>
      Scaled maximum value of the reading setpoint
    </li>
    <li><a name="scaleMin">scaleMin</a> &lt;floating-point number&gt;<br>
      Scaled minimum value of the reading setpoint
    </li>
    <li><a name="EnOcean_secLevel">secLevel</a> encapsulation|encryption|off, [secLevel] = off is default<br>
      Security level of the data
    </li>
    <li><a name="EnOcean_secMode">secMode</a> rcv|snd|bidir<br>
      Telegram direction, which is secured
    </li>
    <li><a name="EnOcean_sendDevStatus">sendDevStatus</a> no|yes, [sendDevStatus] = no is default.<br>
      Send new status of the device.
    </li>
    <li><a name="EnOcean_sendTimePeriodic">sendTimePeriodic</a> t/s|off, [sendTimePeriodic] = off | 1 ... 86400, 600 is default.<br>
      Time period of time telegrams.
    </li>
    <li><a name="sensorMode">sensorMode</a> switch|pushbutton,
      [sensorMode] = switch is default.<br>
      The status "released" will be shown in the reading state if the
      attribute is set to "pushbutton".
    </li>
    <li><a name="EnOcean_serviceOn">serviceOn</a> no|yes,
      [serviceOn] = no is default.<br>
      Device in Service Mode.
    </li>
    <li><a name="EnOcean_setCmdTrigger">setCmdTrigger</a> man|refDev, [setCmdTrigger] = man is default.<br>
      Operation mode to send set commands<br>
      If the attribute is set to "refDev", a device-specific set command is sent when the reference device is updated.
      For the subType "roomSensorControl.05" and "fanCrtl.00"  the reference "temperatureRefDev" is supported.<br>
      For the subType "roomSensorControl.01" the references "humidityRefDev" and "temperatureRefDev" are supported.<br>
      </li>
    <li><a name="EnOcean_setpointRefDev">setpointRefDev</a> &lt;name&gt;<br>
      Name of the device whose reference value is read. The reference values is
      the reading setpoint.
    </li>
    <li><a name="EnOcean_setpointSummerMode">setpointSummerMode</a> valvePos/%,
        [setpointSummerMode] = 0...100, 0 is default<br>
      Valve position in summer operation
    </li>
    <li><a name="EnOcean_setpointTempRefDev">setpointTempRefDev</a> &lt;name&gt;<br>
      Name of the device whose reference value is read. The reference values is
      the reading setpointTemp.
    </li>
    <li><a name="EnOcean_settingAccuracy">settingAccuracy</a> high|low,
      [settingAccuracy] = low is default.<br>
      set setting accurancy.
    </li>
    <li><a href="#showtime">showtime</a></li>
    <li><a name="shutTime">shutTime</a> &lt;channel1&gt;[:&lt;channel2&gt;[:&lt;channel3&gt;[:&lt;channel4&gt;]]]<br>
      subType blindsCtrl.00,  blindsCtrl.01: [shutTime] = 5 ... 300, 300 is default.<br>
      subType manufProfile: [shutTime] = 1 ... 255, 255 is default.<br>
      Use the attr shutTime to set the time delay to the position "Halt" in
      seconds. Select a delay time that is at least as long as the shading element
      or roller shutter needs to move from its end position to the other position.<br>
      Notice subType blindsCrtl.00: The attribute can only be set while the actuator is online.
    </li>
    <li><a name="shutTimeCloses">shutTimeCloses</a> t/s, [shutTimeCloses] = 1 ... 255,
      [shutTimeCloses] = [shutTime] is default.<br>
      Set the attr shutTimeCloses to define the runtime used by the commands opens and closes.
      Select a runtime that is at least as long as the value set by the delay switch of the actuator.
      <br>
      shutTimeCloses is supported for shutter.
    </li>
    <li><a name="EnOcean_signal">signal</a> off|on,
      [signal] = off is default.<br>
      Activate the request functions of signal telegram messages.
    </li>
    <li><a name="EnOcean_signOfLife">signOfLife</a> off|on, [sifnOfLive] = off is default.<br>
      Monitoring signOfLife telegrams from sensors.
    </li>
    <li><a name="EnOcean_signOfLifeInterval">signOfLifeInterval</a> 1...65535<br>
      Monitoring period in seconds for signOfLife telegrams from sensors.
    </li>
    <li><a name="subDef">subDef</a> &lt;EnOcean SenderID&gt;,
      [subDef] = [DEF] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) to control a bidirectional switch or actor.<br>
      In order to control devices that send acknowledge telegrams, you cannot reuse the ID of this
      devices, instead you have to create your own, which must be in the
      allowed ID-Range of the underlying IO device. For this first query the
      <a href="#TCM">TCM</a> with the "<code>get &lt;tcm&gt; idbase</code>" command. You can use
      up to 128 IDs starting with the base shown there.<br>
      If [subDef] = getNextID FHEM can assign a free SenderID alternatively. The system configuration
      needs to be reloaded. The assigned SenderID will only displayed after the system configuration
      has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="subDefA">subDefA</a> &lt;EnOcean SenderID&gt;,
      [subDefA] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = A0|AI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefA is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefA] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="subDefB">subDefB</a> &lt;EnOcean SenderID&gt;,
      [subDefB] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = B0|BI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefB is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefB] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="subDefC">subDefC</a> &lt;EnOcean SenderID&gt;,
      [subDefC] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = C0|CI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefC is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefC] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="subDefD">subDefD</a> &lt;EnOcean SenderID&gt;,
      [subDefD] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = D0|DI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefD is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefD] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="subDef0">subDef0</a> &lt;EnOcean SenderID&gt;,
      [subDef0] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = A0|B0|C0|D0|released<br>
      Used with switch type "central". Set attr switchType to central.<br>
      Use the sensor type "zentral aus/ein" for Eltako devices.<br>
      subDef0 is supported for switches.<br>
      Second action is not sent.<br>
      If [subDef0] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="subDefI">subDefI</a> &lt;EnOcean SenderID&gt;,
      [subDefI] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = AI|BI|CI|DI<br>
      Used with switch type "central". Set attr switchType to central.<br>
      Use the sensor type "zentral aus/ein" for Eltako devices.<br>
      subDefI is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefI] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
    </li>
    <li><a name="EnOcean_subDefH">subDefH</a> &lt;EnOcean SenderID&gt;,
      [subDefH] = undef is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset)<br>
      Used with subType "multisensor.00". If the attribute subDefH is set, the position of the window handle as EEP F6-10-00
      (windowHandle) telegram is forwarded.<br>
      If [subDefH] = getNextID FHEM can assign a free SenderID alternatively.
    </li>
    <li><a name="EnOcean_subDefW">subDefW</a> &lt;EnOcean SenderID&gt;,
      [subDefW] = undef is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset)<br>
      Used with subType "multisensor.00". If the attribute subDefW is set, the window state as EEP D5-00-01
      (contact) telegram is forwarded.<br>
      If [subDefW] = getNextID FHEM can assign a free SenderID alternatively.
    </li>
    <li><a href="#subType">subType</a></li>
    <li><a name="subTypeSet">subTypeSet</a> &lt;type of device&gt;, [subTypeSet] = [subType] is default.<br>
      Type of device (EEP Profile) used for sending commands. Set the Attribute manually.
      The profile has to fit their basic profile. More information can be found in the basic profiles.
    </li>
    <li><a name="EnOcean_summerMode">summerMode</a> off|on,
      [summerMode] = off is default.<br>
      Put Battery Powered Actuator (hvac.01/hvac.06) or Heating Radiator Actuating Drive (hvac.04) in summer operation
      to reduce energy consumption. If [summerMode] = on, the set commands are not executed.
    </li>
    <li><a name="EnOcean_switchHysteresis">switchHysteresis</a> &lt;value&gt;,
      [switchHysteresis] = 1 is default.<br>
      Switch Hysteresis
    </li>
    <li><a name="switchMode">switchMode</a> switch|pushbutton,
      [switchMode] = switch is default.<br>
      The set command "released" immediately after &lt;value&gt; is sent if the
      attribute is set to "pushbutton".
    </li>
    <li><a name="switchType">switchType</a> direction|universal|central|channel,
      [switchType] = direction is default.<br>
      EnOcean Devices support different types of sensors, e. g. direction
      switch, universal switch or pushbutton, central on/off.<br>
      For Eltako devices these are the sensor types "Richtungstaster",
      "Universalschalter" or "Universaltaster", "Zentral aus/ein".<br>
      With the sensor type <code>direction</code> switch on/off commands are
      accepted, e. g. B0, BI, released. Fhem can control an device with this
      sensor type unique. This is the default function and should be
      preferred.<br>
      Some devices only support the <code>universal switch
      </code> or <code>pushbutton</code>. With a Fhem command, for example,
      B0 or BI is switched between two states. In this case Fhem cannot
      control this device unique. But if the Attribute <code>switchType
      </code> is set to <code>universal</code> Fhem synchronized with
      a bidirectional device and normal on/off commands can be used.
      If the bidirectional device response with the channel B
      confirmation telegrams also B0 and BI commands are to be sent,
      e g. channel A with A0 and AI. Also note that confirmation telegrams
      needs to be sent.<br>
      Partly for the switchType <code>central</code> two different SenderID
      are required. In this case set the Attribute <code>switchType</code> to
      <code>central</code> and define the Attributes
      <a href="#subDef0">subDef0</a> and <a href="#subDefI">subDefI</a>.<br>
      Furthermore, SenderIDs can be used depending on the channel A, B, C or D.
      In this case set the Attribute switchType to <code>channel</code> and define
      the Attributes <a href="#subDefA">subDefA</a>, <a href="#subDefB">subDefB</a>,
      <a href="#subDefC">subDefC</a>, or <a href="#subDefD">subDefD</a>.
      </li>
    <li><a name="temperatureRefDev">temperatureRefDev</a> &lt;name&gt;<br>
      Name of the device whose reference value is read. The reference values is
      the reading temperature.
    </li>
    <li><a name="EnOcean_temperatureScale">temperatureScale</a> F|C|default|no_change, [temperatureScale] = no_change is default.<br>
      temperatureScale is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_timeNotation">timeNotation</a> 12|24|default|no_change, [timeNotation] = no_change is default.<br>
      timeNotation is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_timeProgram[1-4]">timeProgram[1-4]</a> &lt;period&gt; &lt;starttime&gt; &lt;endtime&gt; &lt;roomCtrlMode&gt;, [timeProgam[1-4]] = &lt;none&gt; is default.<br>
      [period] = FrMo|FrSu|ThFr|WeFr|TuTh|MoWe|SaSu|MoFr|MoSu|Su|Sa|Fr|Th|We|Tu|Mo<br>
      [starttime] = [00..23]:[00|15|30|45]<br>
      [endtime] = [00..23]:[00|15|30|45]<br>
      [roomCtrlMode] = buildingProtection|comfort|economy|preComfort<br>
      The Room Control Panel Kieback & Peter RBW322-FTL supports only [roomCtrlMode] = comfort.<br>
      timeProgram is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_trackerWakeUpCycle">trackerWakeUpCycle</a> t/s, [wakeUpCycle] =10 s, 20 s, 30 s, 40 s, 60 s, 120 s, 180 s, 240 s, 3600, 86400 s, 30 s is default.<br>
      Transmission cycle of the tracker.
    </li>
    <li><a name="EnOcean_updateState">updateState</a> default|yes|no, [updateState] = default is default.<br>
      update reading state after set commands
      </li>
    <li><a name="EnOcean_uteResponseRequest">uteResponseRequest</a> yes|no<br>
      request UTE teach-in/teach-out response message, the standard value depends on the EEP profil
      </li>
    <li><a href="#verbose">verbose</a></li>
    <li><a name="EnOcean_wakeUpCycle">wakeUpCycle</a> t/s, [wakeUpCycle] = auto|10 s ... 151200 s, 300 s is default for hvac.04 and auto for hvac.06.<br>
      Transmission cycle of the actuator.
    </li>
    <li><a href="#webCmd">webCmd</a></li>
    <li><a name="EnOcean_windowOpenCtrl">windowOpenCtrl</a> disable|enable, disable s is default.<br>
      Window open detection. Valve will be closed if the window is open.
    </li>
    <li><a name="EnOcean_windSpeedStormy">windSpeedStormy</a> v_min/m/s:v_max/m/s,
     [windSpeedStormy] = 0...35:0...35, 13.9:17.2 is default.<br>
     Set switching thresholds for reading isStormy based on the reading windSpeed.
    </li>
    <li><a name="EnOcean_windSpeedStormyDelay">windSpeedStormyDelay</a> t_reset/s:t_set/s,
      [windSpeedStormyDelay] = 0...99000:0...99000, 60:3 is default.<br>
      Set switching delay for reading isStormy based on the reading windSpeed. The reading isStormy is reset or set
      if the thresholds are permanently undershot or exceed during the delay time.
    </li>
    <li><a name="EnOcean_windSpeedWindy">windSpeedWindy</a> v_min/m/s:v_max/m/s,
      [windSpeedWindy] = 0...35:0...35, 1.6:3.4 is default.<br>
      Set switching thresholds for reading isWindy based on the reading windSpeed.
    </li>
    <li><a name="EnOcean_windSpeedWindyDelay">windSpeedWindyDelay</a> t_reset/s:t_set/s,
      [windSpeedWindyDelay] = 0...99000:0...99000, 60:3 is default.<br>
      Set switching delay for reading isWindy based on the reading windSpeed. The reading isWindy is reset or set
      if the thresholds are permanently undershot or exceed during the delay time.
    </li>
    <li><a name="EnOcean_updateGlobalAttr">updateGlobalAttr</a> no|yes,
     [timeEvent] = no|yes, no is default.<br>
     Update the global attributes latitude and longitude with the received GPS coordinates.
    </li>
    </ul>
  </ul>
  <br>

  <a name="EnOceanevents"></a>
  <b>Generated events</b>
  <ul>
    <ul>

     <li><a name="EnOcean_remoteEvents">Remote Management</a><br>
     <ul>
         <li>remoteDevCfg&lt;0000...FFFF&gt;: &lt;device config&gt;</li>
         <li>remoteFunction&lt;01...99&gt;: &lt;remote function number&gt;:&lt;remote manufacturer ID&gt;:&lt;explanation&gt;</li>
         <li>remoteLastFunctionNumber: 001...FFF</li>
         <li>remoteLastStatusReturnCode: 00...FF</li>
         <li>remoteLearn: not_supported|supported</li>
         <li>remoteLinkCfg&lt;in|out&gt;&lt;00...FF&gt;: &lt;data index&gt;:&lt;device config&gt;</li>
         <li>remoteLinkTableDesc&lt;in|out&gt;&lt;00...FF&gt;: &lt;DeviceID&gt;:&lt;EEP&gt;:&lt;channel&gt;</li>
         <li>remoteLinkTableGPDesc&lt;in|out&gt;&lt;00...FF&gt;: &lt;name of channel 00&gt;:&lt;O|I&gt;:&lt;channel type&gt;:&lt;signal type&gt;:&lt;value type&gt;[:&lt;resolution&gt;[:&lt;engineering min&gt;:&lt;scaling min&gt;:&lt;engineering max&gt;:&lt;scaling max&gt;]]</li>
         <li>remoteProductID: 00000000...FFFFFFFF</li>
         <li>remoteRepeaterFilter: AND|OR</li>
         <li>remoteRepeaterFunction: on|off|filter</li>
         <li>remoteRepeaterLevel: 1|2</li>
         <li>remoteTeach: not_supported|supported</li>
         <li>remoteRSSI: LP/dBm</li>
         <li>teach: &lt;result of teach procedure&gt;</li>
     </ul>
     </li>
     <br><br>

     <li><a name="EnOcean_signalEvents">Signal Telegram</a><br>
     <ul>
         <li>harvester: very_good|good|average|bad|very_bad</li>
         <li>hwVersion: 00000000...FFFFFFFF</li>
         <li>trigger: heartbeat</li>
         <li>smartAckMailbox: empty|not_exists|reset</li>
         <li>swVersion: 00000000...FFFFFFFF</li>
     </ul>
     </li>
     <br><br>

     <li>Switch (EEP F6-02-01 ... F6-03-02)<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0 BI or D0 CI</li>
         <li>buttons: pressed|released</li>
         <li>state: &lt;BtnX&gt;[,&lt;BtnY&gt;]</li>
     </ul><br>
         Switches (remote controls) or actors with more than one
         (pair) keys may have multiple channels e. g. B0/BI, A0/AI with one
         SenderID or with separate addresses.
     </li>
     <br><br>

     <li>Pushbutton Switch, Pushbutton Input Module (EEP F6-02-01 ... F6-02-02, F6-01-01)<br>
         [Eltako FT55, FSM12, FSM61, FTS12]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI or D0,CI</li>
         <li>released</li>
         <li>buttons: pressed|released</li>
         <li>state: &lt;BtnX&gt;[,&lt;BtnY&gt;] [released]</li>
     </ul><br>
         The status of the device may become "released", this is not the case for a normal switch.<br>
         Set attr model to Eltako_FT55|FSM12|FSM61|FTS12 or attr sensorMode to pushbutton manually.
     </li>
     <br><br>

     <li>Pushbutton Switch (EEP F6-3F-7F)<br>
         [Eltako FGW14/FAM14 with internal decryption and RS-485 communication]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI or D0,CI</li>
         <li>released</li>
         <li>buttons: pressed|released</li>
         <li>state: &lt;BtnX&gt;[,&lt;BtnY&gt;] [released]</li>
     </ul><br>
         Set attr subType to switch.7F and manufID to 00D.<br>
         The status of the device may become "released", this is not the case for
         a normal switch. Set attr sensorMode to pushbutton manually.
     </li>
     <br><br>

     <li>Pushbutton Switch (EEP D2-03-00)<br>
         [EnOcean PTM 215 Modul]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI</li>
         <li>pressed</li>
         <li>released</li>
         <li>teach: &lt;result of teach procedure&gt;</li>
         <li>energyBow: pressed|released</li>
         <li>state: &lt;BtnX&gt;|&lt;BtnX&gt;,&lt;BtnY&gt;|released|pressed|teachIn|teachOut</li>
     </ul><br>
        The attr subType must be switch.00. This is done if the device was
        created by autocreate. Set attr sensorMode to pushbutton manually if needed.
     </li>
     <br><br>

     <li>Pushbutton Switch (EEP D2-03-0A)<br>
         [Nodon Soft Button]<br>
     <ul>
         <li>on</li>
         <li>off</li>
         <li>batteryPercent: r/% (Sensor Range: r = 1 % ... 100 %)</li>
         <li>buttonD: on|off</li>
         <li>buttonL: on|off</li>
         <li>buttonS: on|off</li>
         <li>state: on|off</li>
     </ul><br>
        The attr subType must be switch.0A. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Heating/Cooling Relay (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FAE14, FHK14, untested]<br>
     <ul>
         <li>controllerMode: auto|off</li>
         <li>energyHoldOff: normal|holdoff</li>
         <li>buttons: pressed|released</li>
     </ul><br>
        Set attr subType to switch and model to Eltako_FAE14|FHK14 manually. In addition
        every telegram received from a teached-in temperature sensor (e.g. FTR55H)
        is repeated as a confirmation telegram from the Heating/Cooling Relay
        FAE14, FHK14. In this case set attr subType to e. g. roomSensorControl.05
        and attr manufID to 00D.
     </li>
     <br><br>

     <li>Key Card Activated Switch (EEP F6-04-01)<br>
         [Eltako FKC, FKF, FZS, untested]<br>
     <ul>
         <li>keycard_inserted</li>
         <li>keycard_removed</li>
         <li>state: keycard_inserted|keycard_removed</li>
     </ul><br>
         Set attr subType to keycard manually.
     </li>
     <br><br>

     <li>Wind Speed Threshold Detector (EEP F6-05-00)<br>
     <ul>
         <li>on</li>
         <li>off</li>
         <li>alarm: dead_sensor|off</li>
         <li>windSpeed: dead_sensor|on|off</li>
         <li>battery: low|ok</li>
         <li>state: on|off</li>
     </ul><br>
        Set attr subType to windSpeed.00 manually.
     </li>
     <br><br>

     <li>Liquid Leakage Sensor (EEP F6-05-01)<br>
         [untested]<br>
     <ul>
         <li>dry</li>
         <li>wet</li>
         <li>state: dry|wet</li>
     </ul><br>
         Set attr subType to liquidLeakage manually.
     </li>
     <br><br>

     <li>Smoke Detector (EEP F6-05-02)<br>
         [Eltako FRW]<br>
     <ul>
         <li>smoke-alarm</li>
         <li>off</li>
         <li>alarm: dead_sensor|smoke-alarm|off</li>
         <li>battery: low|ok</li>
         <li>state: smoke-alarm|off</li>
     </ul><br>
        Set attr subType to smokeDetector.02 manually.
        A monitoring period can be set for signOfLife telegrams of the sensor, see
        <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
        Default is "on" and an interval of 1440 sec.

     </li>
     <br><br>

     <li>Window Handle (EEP F6-10-00, D2-03-10)<br>
         [HOPPE SecuSignal, Eltako FHF, Eltako FTKE]<br>
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>tilted</li>
         <li>open_from_tilted</li>
         <li>state: closed|open|tilted|open_from_tilted</li>
     </ul><br>
        The device windowHandle or windowHandle.10 should be created by autocreate.
     </li>
     <br><br>

     <li>Single Input Contact, Door/Window Contact<br>
         1BS Telegram (EEP D5-00-01)<br>
         [EnOcean EMCS, STM 320, STM 329, STM 250, Eltako FTK, Peha D 450 FU, Eltako TK-TKB]
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>alarm: dead_sensor</li>
         <li>battery: U/V (Range: U = 0 V ... 5 V</li>
         <li>energyStorage: U/V (Range: U = 0 V ... 5 V</li>
         <li>teach: &lt;result of teach procedure&gt;</li>
         <li>state: open|closed</li>
     </ul></li>
        The device should be created by autocreate. A monitoring period can be set for signOfLife telegrams of the sensor, see
       <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
       Default is "off" and an interval of 1980 sec.
     <br><br>

     <li>Temperature Sensors with with different ranges (EEP A5-02-01 ... A5-02-30)<br>
         [EnOcean STM 330, Eltako FTF55, Thermokon SR65 ...]<br>
     <ul>
       <li>t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = &lt;t min&gt; &#176C ... &lt;t max&gt; &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be tempSensor.01 ... tempSensor.30. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperatur and Humidity Sensor (EEP A5-04-02)<br>
         [Eltako FAFT60, FIFT63AP]<br>
     <ul>
       <li>T: t/&#176C H: rH/% B: unknown|low|ok</li>
       <li>battery: unknown|low|ok</li>
       <li>energyStorage: unknown|empty|charged|full</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 6.6 V)
       <li>state: T: t/&#176C H: rH/% B: unknown|low|ok</li>
     </ul><br>
       The attr subType must be tempHumiSensor.02 and attr
       manufID must be 00D for Eltako Devices. This is done if the device was
       created by autocreate.<br>
       A monitoring period can be set for signOfLife telegrams of the sensor, see
       <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
       Default is "off" and an interval of 3300 sec.
     </li>
     <br><br>

     <li>Temperatur and Humidity Sensor (EEP A5-04-03)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/%</li>
       <li>alarm: dead_sensor</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>telegramType: heartbeat|event</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>state: T: t/&#176C H: rH/%</li>
     </ul><br>
       The attr subType must be tempHumiSensor.03. This is done if the device was
       created by autocreate.<br>
       A monitoring period can be set for signOfLife telegrams of the sensor, see
       <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
       Default is "off" and an interval of 1540 sec.
     </li>
     <br><br>

     <li>Barometric Sensor (EEP A5-05-01)<br>
         [untested]<br>
     <ul>
       <li>P/hPa</li>
       <li>airPressure: P/hPa (Sensor Range: P = 500 hPa ... 1150 hPa</li>
       <li>telegramType: heartbeat|event</li>
       <li>state: P/hPa</li>
     </ul><br>
        The attr subType must be baroSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-01)<br>
         [Eltako FAH60, FAH63, FIH63, Thermokon SR65 LI]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 300 lx ... 30 klx, 600 lx ... 60 klx
       , Sensor Range for Eltako: E = 0 lx ... 100 lx, 300 lx ... 30 klx)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: E/lx</li>
     </ul><br>
        Eltako devices only support Brightness.<br>
        The attr subType must be lightSensor.01 and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-02)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 0 lx ... 1020 lx</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.1 V)</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-03)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-04)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C E: E/lx B: ok|low</li>
       <li>battery: ok|low</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 65535 lx)</li>
       <li>energyStorage: 1/%</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>state: T: t/&#176C E: E/lx B: ok|low</li>
     </ul><br>
        The attr subType must be lightSensor.04. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-05)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 0 lx ... 10200 lx</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.1 V)</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.05. This is done if the device was created by autocreate.
     </li>
     <br><br>

      <li>Occupancy Sensor (EEP A5-07-01, A5-07-02)<br>
         [EnOcean EOSW]<br>
     <ul>
       <li>on|off</li>
       <li>battery: ok|low</li>
       <li>button: pressed|released</li>
       <li>current: I/&#181;A (Sensor Range: I = 0 V ... 127.0 &#181;A)</li>
       <li>errorCode: 251 ... 255</li>
       <li>motion: on|off</li>
       <li>sensorType: ceiling|wall</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be occupSensor.<01|02>. This is done if the device was
        created by autocreate. Current is the solar panel current. Some values are
        displayed only for certain types of devices.
     </li>
     <br><br>

      <li>Eltako/PioTek-Tracker TF-TTB (EEP A5-07-01)<br>
     <ul>
       <li>on|off</li>
       <li>battery: ok|low</li>
       <li>button: pressed|released</li>
       <li>motion: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be occupSensor.01. This is done if the device was
        created by autocreate. The attr model has to be set manually to tracker.
        Alternatively, the profile will be defined with inofficial EEP G5-07-01.<br>
        The transmission cycle is set using the attribute <a href="#EnOcean_trackerWakeUpCycle">trackerWakeUpCycle</a>.
     </li>
     <br><br>

      <li>Occupancy Sensor (EEP A5-07-03)<br>
         [untested]<br>
     <ul>
       <li>M: on|off E: E/lx U: U/V</li>
       <li>battery: ok|low</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>motion: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: M: on|off E: E/lx U: U/V</li>
     </ul><br>
        The attr subType must be occupSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light, Temperatur and Occupancy Sensor (EEP A5-08-01 ... A5-08-03)<br>
         [Eltako FABH63, FBH55, FBH63, FIBH63, Thermokon SR-MDS, PEHA 482 FU-BM DE]<br>
     <ul>
       <li>M: on|off E: E/lx P: absent|present T: t/&#176C U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 510, 1020, 1530 or 2048 lx)</li>
       <li>motion: on|off</li>
       <li>presence: absent|present</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51 &#176C or -30 &#176C ... 50 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: M: on|off E: E/lx P: absent|present T: t/&#176C U: U/V</li>
     </ul><br>
        Eltako and PEHA devices only support Brightness and Motion.<br>
        The attr subType must be lightTempOccupSensor.<01|02|03> and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate. Set model to Eltako_TF manually for Eltako TF Devices.
     </li>
     <br><br>

     <li>Gas Sensor, CO Sensor (EEP A5-09-01)<br>
         [untested]<br>
     <ul>
       <li>CO: c/ppm (Sensor Range: c = 0 ppm ... 255 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 255 &#176C)</li>
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be COSensor.01. This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO Sensor (EEP A5-09-02)<br>
         [untested]<br>
     <ul>
       <li>CO: c/ppm (Sensor Range: c = 0 ppm ... 1020 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51.0 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be COSensor.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO2 Sensor (EEP A5-09-04)<br>
         [Thermokon SR04 CO2 *, Eltako FCOTF63, untested]<br>
     <ul>
       <li>airQuality: high|mean|moderate|low (Air Quality Classes DIN EN 13779)</li>
       <li>CO2: c/ppm (Sensor Range: c = 0 ppm ... 2550 ppm)</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% CO2: c/ppm AQ: high|mean|moderate|low</li>
     </ul><br>
        The attr subType must be tempHumiCO2Sensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Volatile organic compounds (VOC) Sensor (EEP A5-09-05, A5-09-0C)<br>
         [untested]<br>
     <ul>
       <li>concentration: c/[unit] (Sensor Range: c = 0 ...  655350</li>
       <li>concentrationUnit: ppb|&mu;/m3</li>
       <li>vocName: Name of last measured VOC</li>
       <li>state: c/[unit]</li>
     </ul><br>
        The attr subType must be vocSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Radon Sensor (EEP A5-09-06)<br>
         [untested]<br>
     <ul>
       <li>Rn: A m3/Bq (Sensor Range: A = 0 Bq/m3 ... 1023 Bq/m3)</li>
       <li>state: A m3/Bq</li>
     </ul><br>
        The attr subType must be radonSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Particles Sensor (EEP A5-09-07)<br>
         [untested]<br>
         Three channels with particle sizes of up to 10 &mu;m, 2.5 &mu;m and 1 &mu;m are supported<br>.
     <ul>
       <li>particles_10: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>particles_2_5: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>particles_1: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>state: PM10: p m3/&mu;g PM2_5: p m3/&mu;g PM1: p m3/&mu;g</li>
     </ul><br>
        The attr subType must be particlesSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>CO2 Sensor (EEP A5-09-08, A5-09-09)<br>
         [untested]<br>
     <ul>
       <li>CO2: c/ppm (Sensor Range: c = 0 ppm ... 2000 ppm)</li>
       <li>powerFailureDetection: detected|not_detected</li>
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be CO2Sensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>H Sensor (EEP A5-09-0A)<br>
         [untested]<br>
     <ul>
       <li>c/ppm</li>
       <li>voltage: U/V (Sensor Range: U = 2 V ... 5 V)</li>
       <li>H: c/ppm (Sensor Range: c = 0 ppm ... 2000 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be HSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Radiation Sensor (EEP A5-09-0B)<br>
         [untested]<br>
     <ul>
       <li>1/[unit]</li>
       <li>radioactivity: 1/[unit] (Sensor Range: c = 0 [unit] ... 65535 [unit])</li>
       <li>unit: uSv/h|cpm|Bq/L|Bq/kg</li>
       <li>voltage: U/V (Sensor Range: U = 2 V ... 5 V)</li>
       <li>state: 1/[unit]</li>
     </ul><br>
        The attr subType must be radiationSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)<br>
         [Eltako FTR55*, Thermokon SR04 *, Thanos SR *]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|auto SW: 0|1</li>
       <li>fanStage: 0|1|2|3|auto</li>
       <li>switch: on|off</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|auto SW: on|off</li><br>
       Alternatively for Eltako devices
       <li>T: t/&#176C SPT: t/&#176C NR: t/&#176C</li>
       <li>block: lock|unlock</li>
       <li>nightReduction: t/K</li>
       <li>setpointTemp: t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C SPT: t/&#176C NR: t/K</li><br>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.05 and attr
       manufID must be 00D for Eltako Devices. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)<br>
         [Eltako FUTH65D, Thermokon SR04 * rH, Thanos SR *]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SP: 0 ... 255 SW: 0|1</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>switch: 0|1</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>state: T: t/&#176C H: rH/% SP: 0 ... 255 SW: 0|1</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.01 and attr
       manufID must be 00D for Eltako Devices. This is
       done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-15 ... A5-10-17)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 63 P: absent|present</li>
       <li>presence: absent|present</li>
       <li>temperature: t/&#176C (Sensor Range: t = -10 &#176C ... 41.2 &#176C)</li>
       <li>setpoint: 0 ... 63</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>state: T: t/&#176C SP: 0 ... 63 P: absent|present</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.02. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-18)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.18. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-19)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.19. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1A)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled U: U/V</li>
       <li>errorCode: 251 ... 255</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: T: t/&#176C F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled U: U/V</li>
     </ul><br>
        The attr subType must be roomSensorControl.1A. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1B)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off P: absent|present|disabled U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off P: absent|present|disabled U: U/V</li>
     </ul><br>
        The attr subType must be roomSensorControl.1B. This is done if the device was
        created by autocreate.
     </li>
     <br><br>
     <li>Room Sensor and Control Unit (EEP A5-10-1C)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: E/lx P: absent|present|disabled</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: E/lx P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1C. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1D)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: rH/% P: absent|present|disabled</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: rH/% P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1D. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1F)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C F: 0|1|2|3|auto SP: 0 ... 255 P: absent|present|disabled</li>
       <li>fan: 0|1|2|3|auto</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C F: 0|1|2|3|auto SP: 0 ... 255 P: absent|present|disabled</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.1F. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Room Operation Panel (EEP A5-10-20, A5-10-21)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SP: 0 ... 255 B: ok|low</li>
       <li>activity: yes|no</li>
       <li>battery: ok|low</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointMode: auto|frostProtect|setpoint</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: t/&#176C H: rH/% SP: 0 ... 255 B: ok|low</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.20. This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Room Operation Panel (EEP A5-10-22, A5-10-23)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SP: 0 ... 255 F: auto|off|1|2|3 O: occupied|unoccupied</li>
       <li>fanSpeed: auto|off|1|2|3</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>occupancy: occupied|unoccupied</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: t/&#176C H: rH/% SP: 0 ... 255 F: auto|off|1|2|3 O: occupied|unoccupied</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.22.
       This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Lighting Controller State (EEP A5-11-01)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 510 lx)</li>
       <li>contact: open|closed</li>
       <li>daylightHarvesting: enabled|disabled</li>
       <li>dim: 0 ... 255</li>
       <li>presence: absent|present</li>
       <li>illum: 0 ... 255</li>
       <li>mode: switching|dimming</li>
       <li>powerRelayTimer: enabled|disabled</li>
       <li>powerSwitch: on|off</li>
       <li>repeater: enabled|disabled</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be lightCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperature Controller Output (EEP A5-11-02)<br>
         [untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>alarm: on|off</li>
       <li>controlVar: cvar (Sensor Range: cvar = 0 % ... 100 %)</li>
       <li>controllerMode: auto|heating|cooling|off</li>
       <li>controllerState: auto|override</li>
       <li>energyHoldOff: normal|holdoff</li>
       <li>fan: 0 ... 3|auto</li>
       <li>presence: present|absent|standby|frost</li>
       <li>setpointTemp: t/&#176C (Sensor Range: t = 0 &#176C ... 51.2 &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be tempCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li><a name="Blind Status">Blind Status</a> (EEP A5-11-03)<br>
         [untested, experimental status]<br>
     <ul>
       <li>open|closed|not_reached|not_available</li>
       <li>alarm: on|off|no endpoints defined|not used</li>
       <li>anglePos: &alpha;/&#176 (Sensor Range: &alpha; = -180 &#176 ... 180 &#176)</li>
       <li>endPosition: open|closed|not_reached|not_available</li>
       <li>position: pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
       <li>positionMode: normal|inverse</li>
       <li>serviceOn: yes|no</li>
       <li>shutterState: opens|closes|stopped|not_available</li>
       <li>state: open|closed|not_reached|not_available</li>
     </ul><br>
        The attr subType must be shutterCtrlState.01 This is done if the device was
        created by autocreate.<br>
        The profile is linked with <a href="#Blind Command Central">Blind Command Central</a>.
        The profile <a href="#Blind Command Central">Blind Command Central</a>
        controls the devices centrally. For that the attributes subDef, subTypeSet
        and gwCmd have to be set manually.
     </li>
     <br><br>

     <li>Extended Lighting Status (EEP A5-11-04)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>alarm: off|lamp_failure|internal_failure|external_periphery_failure</li>
       <li>blue: 0 ... 255</li>
       <li>current: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>currentUnit: mA|A</li>
       <li>dim: 0 ... 255</li>
       <li>energy: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>energyUnit: Wh|kWh|MWh|GWh</li>
       <li>green: 0 ... 255</li>
       <li>measuredValue: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>measureUnit: unknown</li>
       <li>lampOpHours: t/h |unknown (Sensor range: t = 0 h ... 65535 h)</li>
       <li>power: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>powerSwitch: on|off</li>
       <li>powerUnit: mW|W|kW|MW</li>
       <li>red: 0 ... 255</li>
       <li>rgb: RRGGBB (red (R), green (G) or blue (B) color component values: 00 ... FF)</li>
       <li>serviceOn: yes|no</li>
       <li>voltage: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>voltageUnit: mV|V</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be lightCtrlState.02 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Dual Channel Switch Actuator (EEP A5-11-05)<br>
         [untested]<br>
     <ul>
       <li>1: on|off 2: on|off</li>
       <li>channel1: on|off</li>
       <li>channel2: on|off</li>
       <li>workingMode: 1 ... 4</li>
       <li>state: 1: on|off 2: on|off</li>
     </ul><br>
        The attr subType must be switch.05. This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Counter (EEP A5-12-00)<br>
         [Thermokon SR-MI-HS, untested]<br>
     <ul>
       <li>1/s</li>
       <li>currentValue<00 ... 15>: 1/s</li>
       <li>counter<00 ... 15>: 0 ... 16777215</li>
       <li>state: 1/s</li>
     </ul><br>
        The attr subType must be autoMeterReading.00. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Electricity (EEP A5-12-01)<br>
         [Eltako FSS12, DSZ14DRS, DSZ14WDRS, Thermokon SR-MI-HS, untested]<br>
         [Eltako FWZ12-16A tested]<br>
     <ul>
       <li>P/W</li>
       <li>power: P/W</li>
       <li>energy<0 ... 15>: E/kWh</li>
       <li>currentTariff: 0 ... 15</li>
       <li>serialNumber: S-&lt;nnnnnn&gt;</li>
      <li>state: P/W</li>
     </ul><br>
        The attr subType must be autoMeterReading.01 and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Gas, Water (EEP A5-12-02, A5-12-03)<br>
         [untested]<br>
     <ul>
       <li>Vs/l</li>
       <li>flowrate: Vs/l</li>
       <li>consumption<0 ... 15>: V/m3</li>
       <li>currentTariff: 0 ... 15</li>
      <li>state: Vs/l</li>
     </ul><br>
        The attr subType must be autoMeterReading.02|autoMeterReading.03.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Temperatur, Load (EEP A5-12-04)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C W: m/g B: full|ok|low|empty</li>
       <li>battery: full|ok|low|empty</li>
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 40 &#176C)</li>
       <li>weight: m/g</li>
       <li>state: T: t/&#176C W: m/g B: full|ok|low|empty</li>
     </ul><br>
        The attr subType must be autoMeterReading.04.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Temperatur, Container Sensor (EEP A5-12-05)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C L: <location0 ... location9> B: full|ok|low|empty</li>
       <li>amount: 0 ... 10</li>
       <li>battery: full|ok|low|empty</li>
       <li>location<0 ... 9>: possessed|not_possessed</li>
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C L: <location0 ... location9> B: full|ok|low|empty</li>
     </ul><br>
        The attr subType must be autoMeterReading.05.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Current Meter 16 Channels (EEP A5-12-10)<br>
         [untested]<br>
     <ul>
       <li>I/mA</li>
       <li>current<00 ... 15>: I/mA (Sensor Range: I = 0 mA ... 16777215 mA)</li>
       <li>electricChange<00 ... 15>: Q/Ah (Sensor Range: Q = 0 Ah ... 16777215 Ah)</li>
       <li>currentTariff: 00 ... 15</li>
      <li>state: I/mA</li>
     </ul><br>
        The attr subType must be autoMeterReading.10. This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Weather Station (EEP A5-13-01)<br>
         Sun Intensity (EEP A5-13-02)<br>
         [AWAG XFJ, Eltako FWS61]<br>
     <ul>
       <li>T: t/&#176C B: E/lx W: Vs/m IR: yes|no</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 150 klx)</li>
       <li>dayNight: day|night</li>
       <li>hemisphere: north|south</li>
       <li>isRaining: yes|no</li>
       <li>isStormy: no|yes</li>
       <li>isSunny: no|yes</li>
       <li>isSunnyEast: no|yes</li>
       <li>isSunnySouth: no|yes</li>
       <li>isSunnyWest: no|yes</li>
       <li>isWindy: no|yes</li>
       <li>sunEast: E/lx (Sensor Range: E = 0 lx ... 150 klx)</li>
       <li>sunSouth: E/lx (Sensor Range: E = 0 lx ... 150 klx)</li>
       <li>sunWest: E/lx (Sensor Range: E = 0 lx ... 150 klx)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 80 &#176C)</li>
       <li>windSpeed: Vs/m (Sensor Range: V = 0 m/s ... 70 m/s)</li>
       <li>windStrength: B (Sensor Range: B = 0 Beaufort ... 12 Beaufort)</li>
       <li>state:T: t/&#176C B: E/lx W: Vs/m IR: yes|no</li>
     </ul><br>
        Brightness is the strength of the dawn light. SunEast,
        sunSouth and sunWest are the solar radiation from the respective
        compass direction. IsRaining is the rain indicator.<br>
        The attr subType must be environmentApp. This is done if the device was created by
        autocreate.<br>
        The Eltako Weather Station FWS61 supports not the day/night indicator
        (dayNight). The thresholds and delay times can be adjusted by the attributes<br>
        <a href="#EnOcean_brightnessDayNight">brightnessDayNight</a>,
        <a href="#EnOcean_brightnessDayNightCtrl">brightnessDayNightCtrl</a>,
        <a href="#EnOcean_brightnessDayNightDelay">brightnessDayNightDelay</a>,
        <a href="#EnOcean_brightnessSunny">brightnessSunny</a>,
        <a href="#EnOcean_brightnessSunnyDelay">brightnessSunnyDelay</a>,
        <a href="#EnOcean_brightnessSunnyEast">brightnessSunnyEast</a>,
        <a href="#EnOcean_brightnessSunnyEastDelay">brightnessSunnyEastDelay</a>,
        <a href="#EnOcean_brightnessSunnySouth">brightnessSunnySouth</a>,
        <a href="#EnOcean_brightnessSunnySouthDelay">brightnessSunnySouthDelay</a>,
        <a href="#EnOcean_brightnessSunnyWest">brightnessSunnyWest</a>,
        <a href="#EnOcean_brightnessSunnyWestDelay">brightnessSunnyWestDelay</a>,
        <a href="#EnOcean_windSpeedStormy">windSpeedStormy</a>,
        <a href="#EnOcean_windSpeedStormyDelay">windSpeedStormyDelay</a>,
        <a href="#EnOcean_windSpeedWindy">windSpeedWindy</a>,
        <a href="#EnOcean_windSpeedWindyDelay">windSpeedWindyDelay</a>.<br>
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Data Exchange (EEP A5-13-03)<br>
         Time and Day Exchange (EEP A5-13-04)<br>
         Direction Exchange (EEP A5-13-05)<br>
         Geographic Exchange (EEP A5-13-06)<br>
     <ul>
       <li>azimuth: &alpha;/&deg; (Sensor Range: &alpha; = 0 &deg; ... 359 &deg;)</li>
       <li>date: JJJJ-MM-DD</li>
       <li>elevation: &beta;/&deg; (Sensor Range: &beta; = -90 &deg; ... 90 &deg;)</li>
       <li>latitude: &phi;/&deg; (Sensor Range: &phi; = -90 &deg; ... 90 &deg;)</li>
       <li>longitude: &lambda;/&deg; (Sensor Range: &lambda; = -180 &deg; ... 180 &deg;)</li>
       <li>time: hh:mm:ss [AM|PM]</li>
       <li>timeSource: GPS|RTC</li>
       <li>twilight: T/% (Sensor Range: T = 0 % ... 100 %)</li>
       <li>weekday: Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday</li>
     </ul><br>
        The attr subType must be environmentApp. This is done if the device was created by
        autocreate. The global attributes latitude and longitude are set automatically if the attribute
        <a href="#EnOcean_updateGlobalAttr">updateGlobalAttr</a> is set.<br>
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Sun Position and Radiation (EEP A5-13-10)<br>
         [untested]<br>
     <ul>
       <li>SRA: E m2/W SNA: &alpha;/&deg; SNE: &beta;/&deg;</li>
       <li>dayNight: day|night</li>
       <li>solarRadiation: E m2/W (Sensor Range: E = 0 W/m2 ... 2000 W/m2)</li>
       <li>sunAzimuth: &alpha;/&deg; (Sensor Range: &alpha; = -90 &deg; ... 90 &deg;)</li>
       <li>sunElevation: &beta;/&deg; (Sensor Range: &beta; = 0 &deg; ... 90 &deg;)</li>
       <li>state:SRA: E m2/W SNA: &alpha;/&deg; SNE: &beta;/&deg;</li>
     </ul><br>
        The attr subType must be environmentApp. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Wind Sensor (EEP A5-13-07)<br>
         [Hideki, untested]<br>
     <ul>
       <li>Vh/km (Sensor Range: V = 0 km/h ... 199.9 km/h)</li>
       <li>battery: ok|low</li>
       <li>windSpeedAverage: Vh/km (Sensor Range: V = 0 km/h ... 199.9 km/h)</li>
       <li>windSpeedDirection: NNE|NE|ENE|E|ESE|SE|SSE|S|SSW|SW|WSW|W|WNW|NW|NNW|N</li>
       <li>windSpeedMax: Vh/km (Sensor Range: V = 0 km/h ... 199.9 km/h)</li>
       <li>state:Vh/km (Sensor Range: V = 0 km/h ... 199.9 km/h)</li>
     </ul><br>
        The attr subType must be windSensor.01. This is done if the device was created by
        autocreate.<br>
     </li>
     <br><br>

     <li>Rain Sensor (EEP A5-13-08)<br>
         [Hideki, untested]<br>
     <ul>
       <li>H/mm</li>
       <li>battery: ok|low</li>
       <li>rain: H/mm</li>
       <li>state:H/mm</li>
     </ul><br>
        The amount of rainfall is calculated at intervals of 183 s.<br>
        The attr subType must be rainSensor.01. This is done if the device was created by
        autocreate.<br>
     </li>
     <br><br>

     <li>Multi-Func Sensor (EEP A5-14-01 ... A5-14-06)<br>
         [untested]<br>
     <ul>
       <li>C: open|closed V: on|off E: E/lx U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>contact: open|closed</li>
       <li>errorCode: 251 ... 255</li>
       <li>vibration: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: C: open|closed V: on|off E: E/lx U: U/V</li>
     </ul><br>
        The attr subType must be multiFuncSensor. This is done if the device was
        created by autocreate.
        A monitoring period can be set for signOfLife telegrams of the sensor, see
        <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
        Default is "on" and an interval of 132 sec.
     </li>
     <br><br>

     <li>Dual Door Contact (EEP A5-14-07, A5-14-08)<br>
         [Eimsig EM-FSGE-00 sensor]<br>
     <ul>
       <li>C: open|closed B: unlocked|locked V: on|off U: U/V</li>
       <li>alarm: dead_sensor</li>
       <li>block: unlocked|locked</li>
       <li>contact: open|closed</li>
       <li>vibration: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: C: open|closed B: unlocked|locked V: on|off U: U/V</li>
     </ul><br>
        The attr subType must be doorContact. This is done if the device was
        created by autocreate.<br>
        A monitoring period can be set for signOfLife telegrams of the sensor, see
        <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
        Default is "on" and an interval of 132 sec.
     </li>
     <br><br>

     <li>Window/Door Contact (EEP A5-14-09, A5-14-0A)<br>
         [Eimsig EM-FSGE-00 sensor]<br>
     <ul>
       <li>W: open|tilt|closed B: unlocked|locked V: on|off U: U/V</li>
       <li>alarm: dead_sensor</li>
       <li>vibration: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>window: open|tilt|closed</li>
       <li>state: W: open|tilt|closed V: on|off U: U/V</li>
     </ul><br>
        The attr subType must be windowContact. This is done if the device was
        created by autocreate.<br>
        A monitoring period can be set for signOfLife telegrams of the sensor, see
        <a href="#EnOcean_signOfLife">signOfLife</a> and <a href="#EnOcean_signOfLifeInterval">signOfLifeInterval</a>.
        Default is "on" and an interval of 132 sec.
     </li>
     <br><br>

     <li>Battery Powered Actuator (EEP A5-20-01)<br>
         [Kieback&Peter MD15-FTL-xx]<br>
     <ul>
       <li>T: t/&#176C SPT: t/&#176C SP: setpoint/%</li>
       <li>actuatorState: obstructed|ok</li>
       <li>alarm: no_response_from_actuator</li>
       <li>battery: ok|low</li>
       <li>cover: open|closed</li>
       <li>delta: &lt;floating-point number&gt;</li>
       <li>energyInput: enabled|disabled</li>
       <li>energyStorage: charged|empty</li>
       <li>maintenanceMode: off|runInit|valveClosed|valveOpend:runInit</li>
       <li>operationMode: off|setpoint|setpointTemp</li>
       <li>p_d: &lt;floating-point number&gt;</li>
       <li>p_i: &lt;floating-point number&gt;</li>
       <li>p_p: &lt;floating-point number&gt;</li>
       <li>pidAlarm: actuator_in_errorPos|dead_sensor|no_temperature_value|setpoint_device_missing</li>
       <li>pidState: alarm|idle|processing|start|stop|</li>
       <li>roomTemp: t/&#176C</li>
       <li>selfCtl: on|off</li>
       <li>setpoint: setpoint/%</li>
       <li>setpointSet: setpoint/%</li>
       <li>setpointCalc: setpoint/%</li>
       <li>setpointTemp: t/&#176C</li>
       <li>setpointTempSet: t/&#176C</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C</li>
       <li>waitingCmds: no_change|runInit|setpoint|setpointTemp|valveCloses|valveOpens</li>
       <li>wakeUpCycle: t/s</li>
       <li>window: open|closed</li>
       <li>state: T: t/&#176C SPT: t/&#176C SP: setpoint/%</li>
     </ul><br>
         The internal temperature sensor (roomTemp) of the Micropelt iTRV is not suitable as
         a room thermostat.<br>
         The attr subType must be hvac.01. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Heating Radiator Actuating Drive (EEP A5-20-04)<br>
        [Holter SmartDrive MX]<br>
     <ul>
       <li>T: t/&#176C SPT: t/&#176C SP: setpoint/%</li>
       <li>alarm: no_response_from_actuator|measurement_error|battery_empty|frost_protection|blocked_valve|end_point_detection_error|no_valve|not_taught_in|no_response_from_controller|teach-in_error</li>
       <li>battery: ok|low</li>
       <li>blockKey: yes|no</li>
       <li>delta: &lt;floating-point number&gt;</li>
       <li>feedTemp: t/&#176C</li>
       <li>maintenanceMode: off|runInit|valveClosed|valveOpend:runInit</li>
       <li>measurementState: active|inactive</li>
       <li>operationMode: off|setpoint|setpointTemp</li>
       <li>p_d: &lt;floating-point number&gt;</li>
       <li>p_i: &lt;floating-point number&gt;</li>
       <li>p_p: &lt;floating-point number&gt;</li>
       <li>pidAlarm: actuator_in_errorPos|dead_sensor|no_temperature_value|setpoint_device_missing</li>
       <li>pidState: alarm|idle|processing|start|stop|</li>
       <li>roomTemp: t/&#176C</li>
       <li>setpoint: setpoint/%</li>
       <li>setpointSet: setpoint/%</li>
       <li>setpointCalc: setpoint/%</li>
       <li>setpointTemp: t/&#176C</li>
       <li>setpointTempSet: t/&#176C</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C</li>
       <li>waitingCmds: no_change|runInit|setpoint|setpointTemp|valveCloses|valveOpens</li>
       <li>wakeUpCycle: t/s</li>
       <li>state: T: t/&#176C SPT: t/&#176C SP: setpoint/%</li>
     </ul><br>
        The attr subType must be hvac.04. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Heating Radiator Actuating Drive (EEP A5-20-06)<br>
        [Micropelt iTRV MVA-005, OPUS Micropelt HOME]<br>
     <ul>
       <li>T: t/&#176C SPT: t/&#176C SP: setpoint/%</li>
       <li>alarm: no_response_from_actuator</li>
       <li>battery: ok|low</li>
       <li>blockKey: yes|no</li>
       <li>delta: &lt;floating-point number&gt;</li>
       <li>feedTemp: t/&#176C</li>
       <li>maintenanceMode: off|runInit|valveClosed|valveOpend:runInit</li>
       <li>measurementState: active|inactive</li>
       <li>operationMode: off|setpoint|setpointTemp</li>
       <li>p_d: &lt;floating-point number&gt;</li>
       <li>p_i: &lt;floating-point number&gt;</li>
       <li>p_p: &lt;floating-point number&gt;</li>
       <li>pidAlarm: actuator_in_errorPos|dead_sensor|no_temperature_value|setpoint_device_missing</li>
       <li>pidState: alarm|idle|processing|start|stop|</li>
       <li>radioComErr: off|on</li>
       <li>radioSignalStrength: obstructed|ok</li>
       <li>roomTemp: t/&#176C</li>
       <li>setpoint: setpoint/%</li>
       <li>setpointSet: setpoint/%</li>
       <li>setpointCalc: setpoint/%</li>
       <li>setpointTemp: t/&#176C</li>
       <li>setpointTempSet: t/&#176C</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C</li>
       <li>waitingCmds: no_change|runInit|setpoint|setpointTemp|standby</li>
       <li>wakeUpCycle: auto|t/s</li>
       <li>window: open|closed</li>
       <li>state: T: t/&#176C SPT: t/&#176C SP: setpoint/%</li>
     </ul><br>
        The attr subType must be hvac.06. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Generic HVAC Interface (EEP A5-20-10)<br>
         [IntesisBox PA-AC-ENO-1i]<br>
     <ul>
       <li>on|off</li>
       <li>ctrl: auto|0...100</li>
       <li>fanSpeed: auto|1...14</li>
       <li>occupancy: occupied|off|standby|unoccupied</li>
       <li>mode: auto|heat|morning_warmup|cool|night_purge|precool|off|test|emergency_heat|fan_only|free_cool|ice|max_heat|eco|dehumidification|calibration|emergency_cool|emergency_stream|max_cool|hvc_load|no_load|auto_heat|auto_cool</li>
       <li>vanePosition: auto|horizontal|position_2|position_3|position_4|vertical|swing|vertical_swing|horizontal_swing|hor_vert_swing|stop_swing</li>
       <li>powerSwitch: on|off</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be hvac.10. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Generic HVAC Interface - Error Control (EEP A5-20-11)<br>
         [IntesisBox PA-AC-ENO-1i]<br>
     <ul>
       <li>error|ok</li>
       <li>alarm: error|ok</li>
       <li>errorCode: 0...65535</li>
       <li>externalDisable: disable|enable</li>
       <li>keyCardDisable: disable|enable</li>
       <li>otherDisable: disable|enable</li>
       <li>powerSwitch: on|off</li>
       <li>remoteCtrl: disable|enable</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>window: closed|opened</li>
       <li>windowDisable: disable|enable</li>
       <li>state: error|ok</li>
     </ul><br>
        The attr subType must be hvac.11. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-01, A5-30-02)<br>
         [Thermokon SR65 DI, untested]<br>
     <ul>
       <li>open|closed</li>
       <li>battery: ok|low (only EEP A5-30-01)</li>
       <li>contact: open|closed</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: open|closed</li>
     </ul><br>
        The attr subType must be digitalInput.01 or digitalInput.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-03)<br>
         4 digital Inputs, Wake, Temperature [untested]<br>
     <ul>
       <li>T: t/&#176C I: 0|1 0|1 0|1 0|1 W: 0|1</li>
       <li>in0: 0|1</li>
       <li>in1: 0|1</li>
       <li>in2: 0|1</li>
       <li>in3: 0|1</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>wake: high|low</li>
       <li>state: T: t/&#176C I: 0|1 0|1 0|1 0|1 W: high|low</li>
     </ul><br>
        The attr subType must be digitalInput.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Smoke Detector (EEP A5-30-03)<br>
       [Eltako TF-RWB]<br>
     <ul>
       <li>smoke-alarm</li>
       <li>off</li>
       <li>alarm: dead_sensor|smoke-alarm|off</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: smoke-alarm|off</li>
     </ul><br>
        The attr subType must be digitalInput.03. This is done if the device was
        created by autocreate. Set attr model to Eltako_TF_RWB manually.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-04)<br>
         3 digital Inputs, 1 digital Input 8 bits [untested]<br>
     <ul>
       <li>0|1 0|1 0|1 0...255</li>
       <li>in0: 0|1</li>
       <li>in1: 0|1</li>
       <li>in2: 0|1</li>
       <li>in3: 0...255</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: 0|1 0|1 0|1 0...255</li>
     </ul><br>
        The attr subType must be digitalInput.04. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Digital Input, single input contact, retransmission, battery monitor (EEP A5-30-05)<br>
        [untested]<br>
     <ul>
       <li>error|event|heartbeat</li>
       <li>battery: U/V (Range: U = 0 V ... 3.3 V</li>
       <li>signalIdx: 0 ... 127</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>telegramType: event|heartbeat</li>
       <li>state: error|event|heartbeat</li>
     </ul><br>
       The attr subType must be digitalInput.05. This is done if the device was
       created by autocreate.
     </li>

     <li>Energy management, demand response (EEP A5-37-01)<br>
       <br>
     <ul>
       <li>on|off|waiting_for_start|waiting_for_stop</li>
       <li>level: 0...15</li>
       <li>powerUsage: powerUsage/%</li>
       <li>powerUsageLevel: max|min</li>
       <li>powerUsageScale: rel|max</li>
       <li>randomEnd: yes|no</li>
       <li>randomStart: yes|no</li>
       <li>setpoint: 0...255</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>timeout: yyyy-mm-dd hh:mm:ss</li>
       <li>state: on|off|waiting_for_start|waiting_for_stop</li>
     </ul><br>
        The attr subType must be energyManagement.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Switching<br>
         [Eltako FLC61, FSA12, FSR14]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>executeTime: t/s (Sensor Range: t = 0.1 s ... 6553.5 s or 0 if no time specified)</li>
       <li>executeType: duration|delay</li>
       <li>block: lock|unlock</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be switching. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. Eltako devices only send on/off.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Dimming<br>
         [Eltako FUD14, FUD61, FUD70, FSG14, ...]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>block: lock|unlock</li>
       <li>dim: dim/% (Sensor Range: dim = 0 % ... 100 %)</li>
       <li>dimValueLast: dim/%<br>
           Last value received from the bidirectional dimmer.</li>
       <li>dimValueStored: dim/%<br>
           Last value saved by <code>set &lt;name&gt; dim &lt;value&gt;</code>.</li>
       <li>rampTime: t/s (Sensor Range: t = 1 s ... 255 s or 0 if no time specified,
           for Eltako: t = 1 = fast dimming ... 255 = slow dimming or 0 = dimming speed on the dimmer used)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be dimming and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by autocreate.<br>
        For Eltako devices attributes must be set manually. Eltako devices only send on/off and dim.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Setpoint shift<br>
         [untested]<br>
     <ul>
       <li>1/K</li>
       <li>setpointShift: 1/K (Sensor Range: T = -12.7 K ... 12.8 K)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: 1/K</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be setpointShift.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Basic Setpoint<br>
         [untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 51.2 &#176C)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be setpointBasic.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Control variable<br>
         [untested]<br>
     <ul>
       <li>auto|heating|cooling|off</li>
       <li>controlVar: cvov (Sensor Range: cvov = 0 % ... 100 %)</li>
       <li>controllerMode: auto|heating|cooling|off</li>
       <li>controllerState: auto|override</li>
       <li>energyHoldOff: normal|holdoff</li>
       <li>presence: present|absent|standby</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: auto|heating|cooling|off</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be controlVar.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Fan stage<br>
         [untested]<br>
     <ul>
       <li>0 ... 3|auto</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: 0 ... 3|auto</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be fanStage.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Extended Lighting Control (EEP A5-38-09)<br>
         [untested]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>block: unlock|on|off|local</li>
       <li>blue: &lt;blue channel value&gt; (Range: blue = 0  ... 255)</li>
       <li>dimMax: &lt;maximum dimming value&gt; (Range: dim = 0  ... 255)</li>
       <li>dimMin: &lt;minimum dimming value&gt; (Range: dim = 0  ... 255)</li>
       <li>green: &lt;green channel value&gt; (Range: green = 0  ... 255)</li>
       <li>rampTime: t/s (Range: t = 0 s ... 65535 s)</li>
       <li>red: &lt;red channel value&gt; (Range: red = 0  ... 255)</li>
       <li>rgb: RRGGBB (red (R), green (G) or blue (B) color component values: 00 ... FF)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: on|off</li>
     </ul><br>
        Another readings, see subtype lightCtrlState.02.<br>
        The attr subType or subTypSet must be lightCtrl.01. This is done if the device was created by autocreate.<br>
        The subType is associated with the subtype lightCtrlState.02.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Wireless Analog Input Module<br>
         [Thermokon SR65 3AI, untested]<br>
     <ul>
       <li>I1: U/V I2: U/V I3: U/V</li>
       <li>input1: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>input2: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>input3: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: I1: U/V I2: U/V I3: U/V</li>
     </ul><br>
        The attr subType must be manufProfile and attr manufID must be 002
        for Thermokon Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Thermostat Actuator<br>
         [AWAG omnio UPH230/1x]<br>
     <ul>
       <li>on|off</li>
       <li>emergencyMode&lt;channel&gt;: on|off</li>
       <li>nightReduction&lt;channel&gt;: on|off</li>
       <li>setpointTemp&lt;channel&gt;: t/&#176C</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature&lt;channel&gt;: t/&#176C</li>
       <li>window&lt;channel&gt;: on|off</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be manufProfile and attr manufID must be 005
        for AWAG omnio Devices. This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Shutter (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FSB12, FSB14, FSB61, FSB70]<br>
     <ul>
        <li>open|open_ack<br>
            The status of the device will become "open" after the TOP endpoint is
            reached, or it has finished an "opens" or "position 0" command.</li>
        <li>closed<br>
            The status of the device will become "closed" if the BOTTOM endpoint is
            reached</li>
        <li>stop<br>
            The status of the device become "stop" if stop command is sent.</li>
        <li>not_reached<br>
            The status of the device become "not_reached" between one of the endpoints.</li>
        <li>anglePos: &alpha;/&#176 (Sensor Range: &alpha; = -180 &#176 ... 180 &#176)</li>
        <li>endPosition: open|open_ack|closed|not_reached|not_available</li>
        <li>position: pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
        <li>teach: &lt;result of teach procedure&gt;</li>
        <li>state: open|open_ack|closed|not_reached|stop|teach</li>
     </ul><br>
        The values of the reading position and anglePos are updated automatically,
        if the command position is sent or the reading state was changed
        manually to open or closed.<br>
        Set attr subType manufProfile, attr manufID to 00D and attr model to
        Eltako_FSB14|FSB61|FSB70|FSB_ACK manually.
        If the attribute model is set to Eltako_FSB_ACK, with the status "open_ack" the readings position and anglePos are also updated.<br>

     </li>
     <br><br>

     <li>Electronic switches and dimmers with Energy Measurement and Local Control (D2-01-00 - D2-01-12)<br>
        [Telefunken Funktionsstecker, PEHA Easyclick, AWAG Elektrotechnik AG Omnio UPS 230/xx,UPD 230/xx]<br>
     <ul>
        <li>on</li>
        <li>off</li>
        <li>autoOffTime&lt;1...29|All|Input&gt;: 1/s</li>
        <li>channel&lt;0...29|All|Input&gt;: on|off</li>
        <li>delayOffTime&lt;1...29|All|Input&gt;: 1/s</li>
        <li>dayNight: day|night</li>
        <li>defaultState: on|off|last</li>
        <li>devTemp: t/&#176C|invalid</li>
        <li>devTempState: ok|max|warning</li>
        <li>dim&lt;0...29|Input&gt;: dim/% (Sensor Range: dim = 0 % ... 100 %)</li>
        <li>energy&lt;channel&gt;: E/[Ws|Wh|KWh]</li>
        <li>energyUnit&lt;channel&gt;: Ws|Wh|KWh</li>
        <li>error&lt;channel&gt;: ok|warning|failure|not_supported</li>
        <li>extSwitchMode&lt;1...29|All|Input&gt;: unavailable|switch|pushbutton|auto</li>
        <li>extSwitchType&lt;1...29|All|Input&gt;: toggle|direction</li>
        <li>firmwareVersion: [000000 ... FFFFFF]</li>
        <li>loadClassification: no</li>
        <li>localControl&lt;channel&gt;: enabled|disabled</li>
        <li>loadLink: connected|disconnected</li>
        <li>loadOperation: 3-wire</li>
        <li>loadState: on|off</li>
        <li>measurementMode: energy|power</li>
        <li>measurementReport: auto|query</li>
        <li>measurementReset: not_active|trigger</li>
        <li>measurementDelta: E/[Ws|Wh|KWh|W|KW]</li>
        <li>measurementUnit: Ws|Wh|KWh|W|KW</li>
        <li>overCurrentOff&lt;channel&gt;: executed|ready</li>
        <li>overCurrentShutdown&lt;channel&gt;: off|restart</li>
        <li>overCurrentShutdownReset&lt;channel&gt;: not_active|trigger</li>
        <li>power&lt;channel&gt;: P/[W|KW]</li>
        <li>powerFailure&lt;channel&gt;: enabled|disabled</li>
        <li>powerFailureDetection&lt;channel&gt;: detected|not_detected</li>
        <li>powerUnit&lt;channel&gt;: W|KW</li>
        <li>rampTime&lt;1...3l&gt;: 1/s</li>
        <li>responseTimeMax: 1/s</li>
        <li>responseTimeMin: 1/s</li>
        <li>roomCtrlMode: off|comfort|comfort-1|comfort-2|economy|buildingProtection</li>
        <li>serialNumber: [00000000 ... FFFFFFFF]</li>
        <li>taughtInDevID&lt;00...23&gt;: [00000001 ... FFFFFFFE]</li>
        <li>taughtInDevNum: [0 ... 23]</li>
        <li>teach: &lt;result of teach procedure&gt;</li>
        <li>teachInDev: enabled|disabled</li>
        <li>state: on|off</li>
     </ul>
        <br>
        The attr subType must be actuator.01. This is done if the device was
        created by autocreate. To control the device, it must be bidirectional paired,
        see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Blind Control for Position and Angle (D2-05-00)<br>
         [AWAG Elektrotechnik AG OMNIO UPJ 230/12]<br>
     <ul>
        <li>open<br>
            The status of the device will become "open" after the TOP endpoint is
            reached, or it has finished an "opens" or "position 0" command.</li>
        <li>closed<br>
            The status of the device will become "closed" if the BOTTOM endpoint is
            reached</li>
        <li>stop<br>
            The status of the device become "stop" if stop command is sent.</li>
        <li>not_reached<br>
            The status of the device become "not_reached" between one of the endpoints.</li>
        <li>pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
        <li>anglePos&lt;channel&gt;: &alpha;/% (Sensor Range: &alpha; = 0 % ... 100 %)</li>
        <li>block&lt;channel&gt;: unlock|lock|alarm</li>
        <li>endPosition&lt;channel&gt;: open|closed|not_reached|unknown</li>
        <li>position&lt;channel&gt;: unknown|pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
        <li>teach: &lt;result of teach procedure&gt;</li>
        <li>state: open|closed|in_motion|stopped|pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
     </ul>
        <br>
        The attr subType must be blindsCtrl.00 or blindsCtrl.01. This is done if the device was
        created by autocreate. To control the device, it must be bidirectional paired,
        see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>
      <li>Multisensor Window Handle (D2-06-01)<br>
         [Soda GmbH]<br>
     <ul>
       <li>T: t/&#176C H: -|rH/% E: -|E/lx M: off|on|invalid|not_supported|unknown</li>
       <li>alarms: &lt;alarms&gt; (Range: alarms = 00000000 ... FFFFFFFF)</li>
       <li>battery: ok|low</li>
       <li>batteryLowClick: enabled|disabled</li>
       <li>burglaryAlarm: off|on|invalid|not_supported|unknown</li>
       <li>handle: up|down|left|right|invalid|not_supported|unknown</li>
       <li>blinkInterval: t/s|unknown (Range: t = 3 s ... 255 s)</li>
       <li>blinkIntervalSet: t/s|unknown (Range: t = 3 s ... 255 s)</li>
       <li>brightness: E/lx|over_range|invalid|not_supported|unknown (Sensor Range: E = 0 lx ... 60000 lx)</li>
       <li>buttonLeft: pressed|released|invalid|not_supported|unknown</li>
       <li>buttonLeftPresses: &lt;buttonLeftPresses&gt; (Range: buttonLeftPresses = 00000000 ... FFFFFFFF)</li>
       <li>buttonRight: pressed|released|invalid|not_supported|unknown</li>
       <li>buttonRightPresses: &lt;buttonRightPresses&gt; (Range: buttonRightPresses = 00000000 ... FFFFFFFF)</li>
       <li>energyStorage: 1/%|unknown</li>
       <li>handleClosedClick: enabled|disabled</li>
       <li>handleMoveClosed: &lt;handleMoveClosed&gt; (Range: handleMoveClosed = 00000000 ... FFFFFFFF)</li>
       <li>handleMoveOpend: &lt;handleMoveOpend&gt; (Range: handleMoveOpend = 00000000 ... FFFFFFFF)</li>
       <li>handleMoveTilted: &lt;handleMoveTilted&gt; (Range: handleMoveTilted = 00000000 ... FFFFFFFF)</li>
       <li>humidity: rH/%|invalid|not_supported|unknown</li>
       <li>motion: off|on|invalid|not_supported|unknown</li>
       <li>powerOns: &lt;powerOns&gt; (Range: powerOns = 00000000 ... FFFFFFFF)</li>
       <li>presence: absent|present|invalid|not_supported|unknown</li>
       <li>protectionAlarm: off|on|invalid|not_supported|unknown</li>
       <li>temperature: t/&#176C|invalid|not_supported|unknown (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>updateInterval: t/s|unknown (Range: t = 5 s ... 65535 s)</li>
       <li>updateIntervalSet: t/s|unknown (Range: t = 5 s ... 65535 s)</li>
       <li>waitingCmds: &lt;integer number&gt;</li>
       <li>window: undef|not_tilted|tilted|invalid|not_supported|unknown</li>
       <li>windowTilts: &lt;windowTilts&gt; (Range: windowTilts = 00000000 ... FFFFFFFF)</li>
       <li>state: T: t/&#176C H: -|rH/% E: -|E/lx M: off|on|invalid|not_supported|unknown</li>
     </ul><br>
       The attr subType must be multisensor.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

    <li>Room Control Panels (D2-10-00 - D2-10-02)<br>
         [Kieback & Peter RBW322-FTL]<br>
     <ul>
       <li>T: t/&#176C H: -|rH/% F: 0 ... 100/% SPT: t/&#176C O: -|absent|present M: -|on|off</li>
       <li>battery: ok|low|empty|-</li>
       <li>cooling: auto|on|off|-</li>
       <li>customWarning[1|2]: on|off</li>
       <li>fanSpeed: 0 ... 100/%</li>
       <li>fanSpeedMode: central|local</li>
       <li>heating: auto|on|off|-</li>
       <li>humidity: -|rH/%</li>
       <li>moldWarning: on|off</li>
       <li>motion: on|off|-</li>
       <li>occupancy: -|absent|present</li>
       <li>roomCtrlMode: buildingProtection|comfort|economy|preComfort</li>
       <li>setpointBuildingProtectionTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointComfortTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointEconomyTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointPreComfortTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointTemp: t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>solarPowered: yes|no</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>window: closed|open</li>
       <li>state: T: t/&#176C H: -|rH/% F: 0 ... 100/% SPT: t/&#176C O: -|absent|present M: -|on|off</li>
     </ul><br>
       The attr subType must be roomCtrlPanel.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

    <li>Room Control Panels (D2-11-01 - D2-11-08)<br>
        [Thermokon EasySens SR06 LCD-2T/-2T rh -4T/-4T rh]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SPT: t/&#176C F: auto|off|1|2|3</li>
       <li>cooling: on|off</li>
       <li>fanSpeed: auto|off|1|2|3</li>
       <li>heating: on|off</li>
       <li>humidity: rH/%</li>
       <li>occupancy: occupied|unoccupied</li>
       <li>setpointBase: t/&#176C (Range: t = 15 &#176C ... 30 &#176C)</li>
       <li>setpointShift: t/K (Range: t = -10 K ... 10 K)</li>
       <li>setpointShiftMax: t/K (Range: t = 0 K ... 10 K)</li>
       <li>setpointTemp: t/&#176C (Range: t = 5 &#176C ... 40 &#176C)</li>
       <li>setpointType: setpointTemp|setpointShift</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>trigger: heartbeat|sensor|input</li>
       <li>window: closed|open</li>
       <li>state: T: t/&#176C H: rH/% SPT: t/&#176C F: auto|off|1|2|3</li>
     </ul><br>
       The attr subType must be roomCtrlPanel.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired by Smart Ack,
       see <a href="#EnOcean_smartAck">SmartAck Learning</a>.
     </li>
     <br><br>

     <li>Sensor for Smoke, Air quality, Hygrothermal comfort, Temperature and Humidity (D2-14-30)<br>
        [INSAFE+ Origin I870EO untested]<br>
     <ul>
       <li>off|smoke-alarm</li>
       <li>airQuality: optimal|air_dry|humidity_high|teperature_humidity_high|error</li>
       <li>alarm: off|smoke-alarm|dead_sensor</li>
       <li>battery: ok|medium|low|critical</li>
       <li>endOffLife: t/month (Range t = 0...120 month</li>
       <li>humidity: rH/%</li>
       <li>hygrothermalComfort: good|medium|bad|error</li>
       <li>maintenanceLast: t/week (Range t = 0...250 week</li>
       <li>sensorFaultMode: off|on</li>
       <li>smokeAlarmHumidity: ok|not_ok</li>
       <li>smokeAlarmMaintenance: ok|not_done</li>
       <li>smokeAlarmTemperature: ok|not_ok</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 50 &#176C)</li>
       <li>state: off|smoke-alarm</li>
     </ul><br>
       The attr subType must be multiFuncSensor.30. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>People Activity Counter (D2-15-00)<br>
        [EOcean EASYFIT EPAC untested]<br>
     <ul>
       <li>0 ... 100/%</li>
       <li>activity: 0 ... 100/%</li>
       <li>alarm: off|dead_sensor</li>
       <li>battery: ok|medium|low|critical</li>
       <li>present: present|absent|not_detectable|error</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: 0 ... 100/%</li>
     </ul><br>
       The attr subType must be multiFuncSensor.00. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Fan Control (D2-20-00 - D2-20-02)<br>
        [Maico ECA x RC/RCH, ER 100 RC, untested]<br>
     <ul>
       <li>on|off|not_supported</li>
       <li>fanSpeed: 0 ... 100/%</li>
       <li>error: ok|air_filter|hardware|not_supported</li>
       <li>humidity: rH/%|not_supported</li>
       <li>humidityCtrl: disabled|enabled|not_supported</li>
       <li>roomSize: 0...350/m<sup>2</sup>|max</li>
       <li>roomSizeRef: unsed|not_used|not_supported</li>
       <li>setpointTemp: t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: on|off|not_supported</li>
     </ul><br>
       The attr subType must be fanCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>AC Current Clamp (D2-32-00 - D2-32-02)<br>
        [untested]<br>
     <ul>
       <li>I1: I/A I2: I/A I3: I/A</li>
       <li>current1: I/A (Range: I = 0 A ... 4095 A)</li>
       <li>current2: I/A (Range: I = 0 A ... 4095 A)</li>
       <li>current3: I/A (Range: I = 0 A ... 4095 A)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: I1: I/A I2: I/A I3: I/A</li>
     </ul><br>
       The attr subType must be currentClamp.00|currentClamp.01|currentClamp.02. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Heating Actuator (D2-34-00 - D2-34-02)<br>
        [AWAG UPS230/10, UPS230/12, REGH12/08M]<br>
     <ul>
        <li>&lt;0...29|All&gt;: heating</li>
        <li>&lt;0...29|All&gt;: no_heating</li>
        <li>&lt;0...29|All&gt;: off</li>
        <li>&lt;0...29|All&gt;: temperature_unknown</li>
        <li>channel&lt;0...29|All&gt;: setpointTempRefDev|setpointTemp|setpointTempShift</li>
        <li>operationMode&lt;1...29|All&gt;: heating|no_heating|off|temperature_unknown</li>
        <li>overridePeriod&lt;1...29|All|&gt;: t/h</li>
        <li>setpointTemp&lt;1...29|All&gt;: t/&#176C</li>
        <li>setpointTempRefDev&lt;1...29|All&gt;: t/&#176C</li>
        <li>setpointTempShift&lt;1...29|All&gt;: t/K</li>
        <li>teach: &lt;result of teach procedure&gt;</li>
        <li>temperature&lt;1...29|All&gt;: t/&#176C</li>
        <li>state: &lt;0...29|All&gt;: heating|no_heating|off|temperature_unknown</li>
     </ul>
        <br>
        The attr subType must be heatingActuator.00. This is done if the device was
        created by autocreate. To control the device, it must be bidirectional paired,
        see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>LED Controller Status (EEP D2-40-00 - D2-40-01)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>blue: 0 % ... 100 %</li>
       <li>daylightHarvesting: on|off</li>
       <li>demandResp: on|off</li>
       <li>dim: 0 % ... 100 %</li>
       <li>green: 0 % ... 100 %</li>
       <li>occupany: unoccupied|occupied|unknown</li>
       <li>powerSwitch: on|off</li>
       <li>red: 0 % ... 100 %</li>
       <li>rgb: RRGGBB (red (R), green (G) or blue (B) color component values: 00 ... FF)</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>telegramType: event|heartbeat</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be ledCtrlState.00|ledCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Heat Recovery Ventilation (D2-50-00 - D2-50-11)<br>
        [untested]<br>
     <ul>
        <li>off|1...4|auto|demand|supplyAir|exhaustAir</li>
        <li>airQualidity1: 1/%</li>
        <li>airQualidity2: 1/%</li>
        <li>airQualidityThreshold: default|1/%</li>
        <li>CO2Threshold: default|1/%</li>
        <li>coolingProtection: on|off</li>
        <li>defrost: on|off</li>
        <li>deviceMode: master|slave</li>
        <li>drainHeater: on|off</li>
        <li>exhaustAirFlap: closed|opend</li>
        <li>exhaustAirFlow: h/m3 (Sensor Range: Q = 0 m3/h ... 1023 m3/h)</li>
        <li>exhaustFanSpeed: min (Sensor Range: n = 0 / min ... 4095 / min)</li>
        <li>exhaustTemp: t/&#176C (Sensor Range: t = -63 &#176C ... 63 &#176C)</li>
        <li>fault: bbbbbbbb bbbbbbbb bbbbbbbb bbbbbbbb (b = 0|1)</li>
        <li>filterMaintenance: required|not_required</li>
        <li>fireplaceSafetyMode: disabled|enabled</li>
        <li>heatExchangerBypass: closed|opend</li>
        <li>humidityThreshold: default|rH/%</li>
        <li>info: bbbbbbbb bbbbbbbb (b = 0|1)</li>
        <li>input: bbbbbbbb bbbbbbbb (b = 0|1)</li>
        <li>operationHours: [0 ... 589815]</li>
        <li>output: bbbbbbbb bbbbbbbb (b = 0|1)</li>
        <li>outdoorAirHeater: on|off</li>
        <li>outdoorTemp: t/&#176C (Sensor Range: t = -63 &#176C ... 63 &#176C)</li>
        <li>roomTemp: t/&#176C (Sensor Range: t = -63 &#176C ... 63 &#176C)</li>
        <li>roomTempCtrl: on|off</li>
        <li>roomTempSet: default|t/&#176C (Sensor Range: t = -63 &#176C ... 63 &#176C)</li>
        <li>supplyAirFlow: h/m3 (Sensor Range: Q = 0 m3/h ... 1023 m3/h)</li>
        <li>supplyAirFlap: closed|opend</li>
        <li>supplyAirHeater: on|off</li>
        <li>supplyFanSpeed: min (Sensor Range: n = 0 / min ... 4095 / min)</li>
        <li>supplyTemp: t/&#176C (Sensor Range: t = -63 &#176C ... 63 &#176C)</li>
        <li>SWVersion: [0 ... 4095]</li>
        <li>timerMode: on|off</li>
        <li>weeklyTimer: on|off</li>
        <li>state: off|1...4|auto|demand|supplyAir|exhaustAir</li>
     </ul><br>
       The attr subType must be heatRecovery.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Valve Control (EEP D2-A0-01)<br>
     <ul>
       <li>opens</li>
       <li>open</li>
       <li>closes</li>
       <li>closed</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
       <li>state: opens|open|closes|closed|teachIn|teachOut</li>
     </ul><br>
       The attr subType must be valveCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Liquid Leakage Sensor (EEP D2-B0-51)<br>
         [untested]<br>
     <ul>
         <li>dry</li>
         <li>wet</li>
         <li>state: dry|wet</li>
     </ul><br>
       The attr subType must be liquidLeakage.51. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Generic Profiles<br>
     <ul>
       <li>&lt;00...64&gt;-&lt;channel name&gt;: &lt;value&gt;</li>
       <li>&lt;00...64&gt;-&lt;channel name&gt;Unit: &lt;value&gt;</li>
       <li>&lt;00...64&gt;-&lt;channel name&gt;ValueType: value|setpointAbs|setpointRel</li>
       <li>&lt;00...64&gt;-&lt;channel name&gt;ChannelType: teachIn|data|flag|enum</li>
       <li>teach: &lt;result of teach procedure&gt;</li>
     </ul><br>
       The attr subType must be genericProfile. This is done if the device was
       created by autocreate. If the profile in slave mode is operated, especially the channel
       definition in the gpDef attributes must be entered manually.
     </li>
     <br><br>

    <li>RAW Command<br>
    <ul>
       <li>RORG: 1BS|4BS|ENC|MCS|RPS|SEC|STE|UTE|VLD</li>
       <li>dataSent: data (Range: 1 Byte hex ... 512 Byte hex)</li>
       <li>statusSent: status (Range: 0x00 ... 0xFF)</li>
       <li>state: RORG: rorg DATA: data STATUS: status ODATA: odata</li>
    </ul><br>
    With the help of this command data messages in hexadecimal format can be sent and received.
    The telegram types (RORG) 1BS and RPS are always received protocol-specific.
    For further information, see
    <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>.
    <br>
    Set attr subType to raw manually.
    </li>
    <br><br>

    <li>Light and Presence Sensor<br>
        [Omnio Ratio eagle-PM101]<br>
    <ul>
      <li>on</li>
      <li>off</li>
      <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx)</li>
      <li>channel1: on|off<br>
      Motion message in depending on the brightness threshold</li>
      <li>channel2: on|off<br>
      Motion message</li>
      <li>motion: on|off<br>
      Channel 2</li>
      <li>state: on|off<br>
      Channel 2</li>
    </ul><br>
    The sensor also sends switching commands (RORG F6) with the SenderID-1.<br>
    Set attr subType to PM101 manually. Automatic teach-in is not possible,
    since no EEP and manufacturer ID are sent.
    </li>
    <br><br>

    <li>Radio Link Test<br>
    <ul>
      <li>standby|active|stopped</li>
      <li>msgLost: msgLost/%</li>
      <li>rssiMasterAvg: LP/dBm</li>
      <li>state: standby|active|stopped<br></li>
    </ul><br>
      The attr subType must be readioLinkTest. This is done if the device was
      created by autocreate or manually by <code>define &lt;name&gt; EnOcean A5-3F-00</code><br>.
    </li>

  </ul>
</ul>

=end html
=cut
