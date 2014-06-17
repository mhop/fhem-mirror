##############################################
# 00_THZ
# $Id$
# by immi 06/2014
my $thzversion = "0.106";
# this code is based on the hard work of Robert; I just tried to port it
# http://robert.penz.name/heat-pump-lwz/
# http://heatpumpmonitor.penz.name/heatpumpmonitorwiki/
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################
 

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use feature ":5.10";
use SetExtensions;

sub THZ_Read($);
sub THZ_ReadAnswer($);
sub THZ_Ready($);
sub THZ_Write($$);
sub THZ_Parse($$);
sub THZ_Parse1($$);
sub THZ_checksum($);
sub THZ_replacebytes($$$);
sub THZ_decode($);
sub THZ_overwritechecksum($);
sub THZ_encodecommand($$);
sub hex2int($);
sub quaters2time($);
sub time2quaters($);
sub THZ_debugread($);
sub THZ_GetRefresh($);
sub THZ_Refresh_all_gets($);
sub THZ_Get_Comunication($$);
sub THZ_PrintcurveSVG;
sub THZ_RemoveInternalTimer($);

#new by Jakob
sub mysubstr($$$$);



########################################################################################
#
# %sets - all supported protocols are listed  59E
# 
########################################################################################

my %sets = (
    "pOpMode"				=> {cmd2=>"0A0112", type =>"2opmode" },  # 1 Standby bereitschaft; 11 in Automatic; 3 DAYmode; SetbackMode; DHWmode; Manual; Emergency 
    "p01RoomTempDayHC1"			=> {cmd2=>"0B0005", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p02RoomTempNightHC1"		=> {cmd2=>"0B0008", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p03RoomTempStandbyHC1"		=> {cmd2=>"0B013D", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p01RoomTempDayHC1SummerMode"	=> {cmd2=>"0B0569", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p02RoomTempNightHC1SummerMode"	=> {cmd2=>"0B056B", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p03RoomTempStandbyHC1SummerMode"	=> {cmd2=>"0B056A", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p13GradientHC1"			=> {cmd2=>"0B010E", argMin => "0",  argMax =>  "5", 	type =>"6gradient",  unit =>""}, # 0..5 rappresentato/100
    "p14LowEndHC1"			=> {cmd2=>"0B059E", argMin => "0",  argMax => "20", 	type =>"5temp",  unit =>" K"},   #in °K 0..20°K rappresentato/10
    "p15RoomInfluenceHC1"		=> {cmd2=>"0B010F", argMin => "0",  argMax => "100",	type =>"0clean",  unit =>" %"},
    "p19FlowProportionHC1"		=> {cmd2=>"0B059D", argMin => "0",  argMax => "100",	type =>"1clean",  unit =>" %"}, #in % 0..100%
    "p01RoomTempDayHC2"			=> {cmd2=>"0C0005", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p02RoomTempNightHC2"		=> {cmd2=>"0C0008", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p03RoomTempStandbyHC2"		=> {cmd2=>"0C013D", argMin => "13", argMax => "28", 	type =>"5temp",  unit =>" °C"},
    "p01RoomTempDayHC2SummerMode"	=> {cmd2=>"0C0569", argMin => "13", argMax => "28",	type =>"5temp",  unit =>" °C"},
    "p02RoomTempNightHC2SummerMode"	=> {cmd2=>"0C056B", argMin => "13", argMax => "28",	type =>"5temp",  unit =>" °C"},
    "p03RoomTempStandbyHC2SummerMode"	=> {cmd2=>"0C056A", argMin => "13", argMax => "28",	type =>"5temp",  unit =>" °C"},
    "p16GradientHC2"			=> {cmd2=>"0C010E", argMin => "0",  argMax =>  "5",	type =>"6gradient",  unit =>""}, # /100
    "p17LowEndHC2"			=> {cmd2=>"0C059E", argMin => "0",  argMax => "20", 	type =>"5temp",  unit =>" K"},
    "p18RoomInfluenceHC2"		=> {cmd2=>"0C010F", argMin => "0",  argMax => "100",	type =>"1clean", unit =>" %"}, 
    "p04DHWsetDayTemp"			=> {cmd2=>"0A0013", argMin => "13", argMax => "49",	type =>"5temp",  unit =>" °C"},
    "p05DHWsetNightTemp"		=> {cmd2=>"0A05BF", argMin => "13", argMax => "49",	type =>"5temp",  unit =>" °C"},
    "p83DHWsetSolarTemp"		=> {cmd2=>"0A05BE", argMin => "13", argMax => "75",	type =>"5temp",  unit =>" °C"},
    "p06DHWsetStandbyTemp"		=> {cmd2=>"0A0581", argMin => "13", argMax => "49",	type =>"5temp",  unit =>" °C"},
    "p11DHWsetManualTemp"		=> {cmd2=>"0A0580", argMin => "13", argMax => "54",	type =>"5temp",  unit =>" °C"},
    "p07FanStageDay"			=> {cmd2=>"0A056C", argMin =>  "0", argMax =>  "3",	type =>"1clean",  unit =>""},
    "p08FanStageNight"			=> {cmd2=>"0A056D", argMin =>  "0", argMax =>  "3",	type =>"1clean",  unit =>""},
    "p09FanStageStandby"		=> {cmd2=>"0A056F", argMin =>  "0", argMax =>  "3",	type =>"1clean",  unit =>""},
    "p99FanStageParty"			=> {cmd2=>"0A0570", argMin =>  "0", argMax =>  "3",	type =>"1clean",  unit =>""},
    "p75passiveCooling"			=> {cmd2=>"0A0575", argMin =>  "0", argMax =>  "2",	type =>"1clean",  unit =>""},
    "p30integralComponent"		=> {cmd2=>"0A0162", argMin =>  "10", argMax =>  "999",	type =>"1clean",  unit =>" Kmin"}, 
    "p33BoosterTimeoutDHW"		=> {cmd2=>"0A0588", argMin =>  "0", argMax =>  "200",	type =>"1clean",  unit =>" min"}, #during DHW heating
    "p79BoosterTimeoutHC"		=> {cmd2=>"0A05A0", argMin =>  "0", argMax =>  "60" ,	type =>"1clean",  unit =>" min"}, #delayed enabling of booster heater
    "p46UnschedVent0"			=> {cmd2=>"0A0571", argMin =>  "0", argMax =>  "900",	type =>"1clean",  unit =>" min"},	 #in min
    "p45UnschedVent1"			=> {cmd2=>"0A0572", argMin =>  "0", argMax =>  "900",	type =>"1clean",  unit =>" min"},	 #in min
    "p44UnschedVent2"			=> {cmd2=>"0A0573", argMin =>  "0", argMax =>  "900",	type =>"1clean",  unit =>" min"},	 #in min
    "p43UnschedVent3"			=> {cmd2=>"0A0574", argMin =>  "0", argMax =>  "900",	type =>"1clean",  unit =>" min"},	 #in min
    "p37Fanstage1AirflowInlet"		=> {cmd2=>"0A0576", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#zuluft 
    "p38Fanstage2AirflowInlet"		=> {cmd2=>"0A0577", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#zuluft 
    "p39Fanstage3AirflowInlet"		=> {cmd2=>"0A0578", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#zuluft 
    "p40Fanstage1AirflowOutlet"		=> {cmd2=>"0A0579", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#abluft extrated
    "p41Fanstage2AirflowOutlet"		=> {cmd2=>"0A057A", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#abluft extrated
    "p42Fanstage3AirflowOutlet"		=> {cmd2=>"0A057B", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#abluft extrated
    "p49SummerModeTemp"			=> {cmd2=>"0A0116", argMin =>  "11", argMax =>  "24",	type =>"5temp",  unit =>" °C"},		#threshold for summer mode !! 
    "p50SummerModeHysteresis"		=> {cmd2=>"0A05A2", argMin =>  "0.5", argMax =>  "5",	type =>"5temp",  unit =>" K"},		#Hysteresis for summer mode !! 
    "p78DualModePoint"			=> {cmd2=>"0A01AC", argMin =>  "-10", argMax =>  "20",	type =>"5temp",  unit =>" °C"},
    "p54MinPumpCycles"			=> {cmd2=>"0A05B8", argMin =>  "1", 	argMax =>  "24",	type =>"1clean",  unit =>""},
    "p55MaxPumpCycles"			=> {cmd2=>"0A05B7", argMin =>  "25", 	argMax => "200",	type =>"1clean",  unit =>""},
    "p56OutTempMaxPumpCycles"		=> {cmd2=>"0A05BA", argMin =>  "0", 	argMax =>  "25",	type =>"5temp",  unit =>" °C"},
    "p57OutTempMinPumpCycles"		=> {cmd2=>"0A05B9", argMin =>  "0", 	argMax =>  "25",	type =>"5temp",  unit =>" °C"},
    "pHolidayBeginDay"			=> {cmd2=>"0A011B", argMin =>  "1", 	argMax =>  "31", 	type =>"0clean",  unit =>""},
    "pHolidayBeginMonth"		=> {cmd2=>"0A011C", argMin =>  "1", 	argMax =>  "12",	type =>"0clean",  unit =>""},
    "pHolidayBeginYear"			=> {cmd2=>"0A011D", argMin =>  "12", 	argMax =>  "20",	type =>"0clean",  unit =>""},
    "pHolidayBeginTime"			=> {cmd2=>"0A05D3", argMin =>  "00:00", argMax =>  "23:59", 	type =>"9holy",  unit =>""},
    "pHolidayEndDay"			=> {cmd2=>"0A011E", argMin =>  "1", 	argMax =>  "31",	type =>"0clean",  unit =>""},
    "pHolidayEndMonth"			=> {cmd2=>"0A011F", argMin =>  "1", 	argMax =>  "12",	type =>"0clean",  unit =>""},
    "pHolidayEndYear"			=> {cmd2=>"0A0120", argMin =>  "12", 	argMax =>  "20",	type =>"0clean",  unit =>""},
    "pHolidayEndTime"			=> {cmd2=>"0A05D4", argMin =>  "00:00", argMax =>  "23:59", 	type =>"9holy",  unit =>""}, # the answer look like  0A05D4-0D0A05D40029 for year 41 which is 10:15
    "party-time"			=> {cmd2=>"0A05D1", argMin =>  "00:00", argMax =>  "23:59", type =>"8party", unit =>""}, # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
    "programHC1_Mo_0"			=> {cmd2=>"0B1410", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
    "programHC1_Mo_1"			=> {cmd2=>"0B1411", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo_2"			=> {cmd2=>"0B1412", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Tu_0"			=> {cmd2=>"0B1420", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Tu_1"			=> {cmd2=>"0B1421", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Tu_2"			=> {cmd2=>"0B1422", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_We_0"			=> {cmd2=>"0B1430", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_We_1"			=> {cmd2=>"0B1431", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_We_2"			=> {cmd2=>"0B1432", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Th_0"			=> {cmd2=>"0B1440", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Th_1"			=> {cmd2=>"0B1441", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Th_2"			=> {cmd2=>"0B1442", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Fr_0"			=> {cmd2=>"0B1450", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Fr_1"			=> {cmd2=>"0B1451", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Fr_2"			=> {cmd2=>"0B1452", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Sa_0"			=> {cmd2=>"0B1460", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Sa_1"			=> {cmd2=>"0B1461", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Sa_2"			=> {cmd2=>"0B1462", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_So_0"			=> {cmd2=>"0B1470", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_So_1"			=> {cmd2=>"0B1471", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_So_2"			=> {cmd2=>"0B1472", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo-Fr_0"		=> {cmd2=>"0B1480", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo-Fr_1"		=> {cmd2=>"0B1481", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo-Fr_3"		=> {cmd2=>"0B1482", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Sa-So_0"		=> {cmd2=>"0B1490", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Sa-So_1"		=> {cmd2=>"0B1491", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Sa-So_3"		=> {cmd2=>"0B1492", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo-So_0"		=> {cmd2=>"0B14A0", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo-So_1"		=> {cmd2=>"0B14A1", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC1_Mo-So_3"		=> {cmd2=>"0B14A2", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo_0"			=> {cmd2=>"0C1510", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
    "programHC2_Mo_1"			=> {cmd2=>"0C1511", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo_2"			=> {cmd2=>"0C1512", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Tu_0"			=> {cmd2=>"0C1520", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Tu_1"			=> {cmd2=>"0C1521", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Tu_2"			=> {cmd2=>"0C1522", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_We_0"			=> {cmd2=>"0C1530", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_We_1"			=> {cmd2=>"0C1531", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_We_2"			=> {cmd2=>"0C1532", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Th_0"			=> {cmd2=>"0C1540", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Th_1"			=> {cmd2=>"0C1541", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Th_2"			=> {cmd2=>"0C1542", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Fr_0"			=> {cmd2=>"0C1550", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Fr_1"			=> {cmd2=>"0C1551", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Fr_2"			=> {cmd2=>"0C1552", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Sa_0"			=> {cmd2=>"0C1560", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Sa_1"			=> {cmd2=>"0C1561", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Sa_2"			=> {cmd2=>"0C1562", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_So_0"			=> {cmd2=>"0C1570", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_So_1"			=> {cmd2=>"0C1571", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_So_2"			=> {cmd2=>"0C1572", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo-Fr_0"		=> {cmd2=>"0C1580", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo-Fr_1"		=> {cmd2=>"0C1581", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo-Fr_3"		=> {cmd2=>"0C1582", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Sa-So_0"		=> {cmd2=>"0C1590", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Sa-So_1"		=> {cmd2=>"0C1591", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Sa-So_3"		=> {cmd2=>"0C1592", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo-So_0"		=> {cmd2=>"0C15A0", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo-So_1"		=> {cmd2=>"0C15A1", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programHC2_Mo-So_3"		=> {cmd2=>"0C15A2", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo_0"			=> {cmd2=>"0A1710", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo_1"			=> {cmd2=>"0A1711", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo_2"			=> {cmd2=>"0A1712", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Tu_0"			=> {cmd2=>"0A1720", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Tu_1"			=> {cmd2=>"0A1721", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Tu_2"			=> {cmd2=>"0A1722", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_We_0"			=> {cmd2=>"0A1730", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_We_1"			=> {cmd2=>"0A1731", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_We_2"			=> {cmd2=>"0A1732", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Th_0"			=> {cmd2=>"0A1740", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Th_1"			=> {cmd2=>"0A1741", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Th_2"			=> {cmd2=>"0A1742", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Fr_0"			=> {cmd2=>"0A1750", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Fr_1"			=> {cmd2=>"0A1751", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Fr_2"			=> {cmd2=>"0A1752", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Sa_0"			=> {cmd2=>"0A1760", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Sa_1"			=> {cmd2=>"0A1761", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Sa_2"			=> {cmd2=>"0A1762", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_So_0"			=> {cmd2=>"0A1770", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_So_1"			=> {cmd2=>"0A1771", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_So_2"			=> {cmd2=>"0A1772", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo-Fr_0"		=> {cmd2=>"0A1780", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo-Fr_1"		=> {cmd2=>"0A1781", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo-Fr_2"		=> {cmd2=>"0A1782", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Sa-So_0"		=> {cmd2=>"0A1790", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Sa-So_1"		=> {cmd2=>"0A1791", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Sa-So_2"		=> {cmd2=>"0A1792", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo-So_0"		=> {cmd2=>"0A17A0", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo-So_1"		=> {cmd2=>"0A17A1", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programDHW_Mo-So_2"		=> {cmd2=>"0A17A2", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo_0"			=> {cmd2=>"0A1D10", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo_1"			=> {cmd2=>"0A1D11", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo_2"			=> {cmd2=>"0A1D12", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Tu_0"			=> {cmd2=>"0A1D20", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Tu_1"			=> {cmd2=>"0A1D21", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Tu_2"			=> {cmd2=>"0A1D22", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_We_0"			=> {cmd2=>"0A1D30", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_We_1"			=> {cmd2=>"0A1D31", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_We_2"			=> {cmd2=>"0A1D32", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Th_0"			=> {cmd2=>"0A1D40", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Th_1"			=> {cmd2=>"0A1D41", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Th_2"			=> {cmd2=>"0A1D42", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Fr_0"			=> {cmd2=>"0A1D50", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Fr_1"			=> {cmd2=>"0A1D51", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Fr_2"			=> {cmd2=>"0A1D52", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Sa_0"			=> {cmd2=>"0A1D60", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Sa_1"			=> {cmd2=>"0A1D61", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Sa_2"			=> {cmd2=>"0A1D62", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_So_0"			=> {cmd2=>"0A1D70", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_So_1"			=> {cmd2=>"0A1D71", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_So_2"			=> {cmd2=>"0A1D72", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo-Fr_0"		=> {cmd2=>"0A1D80", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo-Fr_1"		=> {cmd2=>"0A1D81", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo-Fr_2"		=> {cmd2=>"0A1D82", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Sa-So_0"		=> {cmd2=>"0A1D90", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Sa-So_1"		=> {cmd2=>"0A1D91", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Sa-So_2"		=> {cmd2=>"0A1D92", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo-So_0"		=> {cmd2=>"0A1DA0", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo-So_1"		=> {cmd2=>"0A1DA1", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""},
    "programFan_Mo-So_2"		=> {cmd2=>"0A1DA2", argMin =>  "00:00", argMax =>  "23:59", type =>"7prog",  unit =>""}
  );




########################################################################################
#
# %gets - all supported protocols are listed without header and footer
#
########################################################################################

my %getsonly = (
#	"hallo"       			=> { },
#	"debug_read_raw_register_slow"	=> { },
	"sSol"				=> {cmd2=>"16", type =>"16sol", unit =>""},
	"sDHW"				=> {cmd2=>"F3", type =>"F3dhw", unit =>""},
	"sHC1"				=> {cmd2=>"F4", type =>"F4hc1", unit =>""},
	"sHC2"				=> {cmd2=>"F5", type =>"F5hc2", unit =>""},
	"sHistory"			=> {cmd2=>"09", type =>"09his", unit =>""},
	"sLast10errors"			=> {cmd2=>"D1", type =>"D1last", unit =>""},
        "sGlobal"	     		=> {cmd2=>"FB", type =>"FBglob", unit =>""},  #allFB
        "sTimedate" 			=> {cmd2=>"FC", type =>"FCtime", unit =>""},
        "sFirmware" 			=> {cmd2=>"FD", type =>"FDfirm", unit =>""},
	"sBoostDHWTotal" 		=> {cmd2=>"0A0924", cmd3=>"0A0925",	type =>"1clean", unit =>" kWh"},
	"sBoostHCTotal"	 		=> {cmd2=>"0A0928", cmd3=>"0A0929",	type =>"1clean", unit =>" kWh"},
	"sHeatRecoveredDay" 		=> {cmd2=>"0A03AE", cmd3=>"0A03AF",	type =>"1clean", unit =>" Wh"},
	"sHeatRecoveredTotal" 		=> {cmd2=>"0A03B0", cmd3=>"0A03B1",	type =>"1clean", unit =>" kWh"},
	"sHeatDHWDay" 			=> {cmd2=>"0A092A", cmd3=>"0A092B",	type =>"1clean", unit =>" Wh"},
	"sHeatDHWTotal" 		=> {cmd2=>"0A092C", cmd3=>"0A092D",	type =>"1clean", unit =>" kWh"},
	"sHeatHCDay" 			=> {cmd2=>"0A092E", cmd3=>"0A092F",	type =>"1clean", unit =>" Wh"},
	"sHeatHCTotal"	 		=> {cmd2=>"0A0930", cmd3=>"0A0931",	type =>"1clean", unit =>" kWh"},
	"sElectrDHWDay" 		=> {cmd2=>"0A091A", cmd3=>"0A091B",	type =>"1clean", unit =>" Wh"},
	"sElectrDHWTotal" 		=> {cmd2=>"0A091C", cmd3=>"0A091D",	type =>"1clean", unit =>" kWh"},
	"sElectrHCDay" 			=> {cmd2=>"0A091E", cmd3=>"0A091F",	type =>"1clean", unit =>" Wh"},
	"sElectrHCTotal"		=> {cmd2=>"0A0920", cmd3=>"0A0921",	type =>"1clean", unit =>" kWh"},
	#"sAllE8"			=> {cmd2=>"E8"},
	#"party-time"			=> {cmd2=>"0A05D1", argMin =>  "00:00", argMax =>  "23:59", type =>"8party", unit =>""} # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  );

my %gets=(%getsonly, %sets);
my %OpMode = ("1" =>"standby", "11" => "automatic", "3" =>"DAYmode", "4" =>"setback", "5" =>"DHWmode", "14" =>"manual", "0" =>"emergency");   
my %Rev_OpMode = reverse %OpMode;
my %OpModeHC = ("1" =>"normal", "2" => "setback", "3" =>"standby", "4" =>"restart", "5" =>"restart");
my %SomWinMode = ( "01" =>"winter", "02" => "summer");
my %weekday = ( "0" =>"Monday", "1" => "Tuesday", "2" =>"Wednesday", "3" => "Thursday", "4" => "Friday", "5" =>"Saturday", "6" => "Sunday" );
my $firstLoadAll = 0;
my $noanswerreceived = 0;
my $internalHash;

########################################################################################
#
# THZ_Initialize($)
# 
# Parameter hash
#
########################################################################################
sub THZ_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "THZ_Read";
  $hash->{WriteFn} = "THZ_Write";
  $hash->{ReadyFn} = "THZ_Ready";
  
# Normal devices
  $hash->{DefFn}   = "THZ_Define";
  $hash->{UndefFn} = "THZ_Undef";
  $hash->{GetFn}   = "THZ_Get";
  $hash->{SetFn}   = "THZ_Set";
  $hash->{AttrFn}  = "THZ_Attr"; 
  $hash->{AttrList}= "IODev do_not_notify:1,0  ignore:0,1 dummy:1,0 showtime:1,0 loglevel:0,1,2,3,4,5,6 "
		    ."interval_sGlobal:0,60,120,180,300,600,3600,7200,43200,86400 "
		    ."interval_sSol:0,60,120,180,300,600,3600,7200,43200,86400 "
		    ."interval_sDHW:0,60,120,180,300,600,3600,7200,43200,86400 "
		    ."interval_sHC1:0,60,120,180,300,600,3600,7200,43200,86400 "
		    ."interval_sHC2:0,60,120,180,300,600,3600,7200,43200,86400 "
		    ."interval_sHistory:0,3600,7200,28800,43200,86400 "
		    ."interval_sLast10errors:0,3600,7200,28800,43200,86400 "
		    ."interval_sHeatRecoveredDay:0,1200,3600,7200,28800,43200,86400 "
		    ."interval_sHeatRecoveredTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sHeatDHWDay:0,1200,3600,7200,28800,43200,86400 "
		    ."interval_sHeatDHWTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sHeatHCDay:0,1200,3600,7200,28800,43200,86400 "
		    ."interval_sHeatHCTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sElectrDHWDay:0,1200,3600,7200,28800,43200,86400 "
		    ."interval_sElectrDHWTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sElectrHCDay:0,1200,3600,7200,28800,43200,86400 "
		    ."interval_sElectrHCTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sBoostDHWTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sBoostDHWTotal:0,3600,7200,28800,43200,86400 " 
		    . $readingFnAttributes;
  $data{FWEXT}{"/THZ_PrintcurveSVG"}{FUNC} = "THZ_PrintcurveSVG";
}


########################################################################################
#
# THZ_define
#
# Parameter hash and configuration
#
########################################################################################
sub THZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  $hash->{VERSION} = $thzversion;
  return "wrong syntax. Correct is: define <name> THZ ".
  				"{devicename[\@baudrate]|ip:port}"
  				 if(@a != 3);
  				
  DevIo_CloseDev($hash);
  my $dev  = $a[2];

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "THZ_Refresh_all_gets");
  return $ret;
}

########################################################################################
#
# THZ_Refresh_all_gets - Called once refreshes current reading for all gets and initializes the regular interval calls
#
# Parameter $hash
# 
########################################################################################
sub THZ_Refresh_all_gets($) {
  my ($hash) = @_;
 # unlink("data.txt");
  THZ_RemoveInternalTimer("THZ_GetRefresh");
  my $timedelay= 5; 						#strart after 5 seconds
  foreach  my $cmdhash  (keys %gets) {
    my %par = (  hash => $hash, command => $cmdhash );
    RemoveInternalTimer(\%par);
    InternalTimer(gettimeofday() + ($timedelay) , "THZ_GetRefresh", \%par, 0);		#increment 0.6s $timedelay++
    $timedelay += 0.6;
  }  #refresh all registers; the register with interval_command ne 0 will keep on refreshing
}


########################################################################################
#
# THZ_GetRefresh - Called in regular intervals to obtain current reading
#
# Parameter (hash => $hash, command => "allFB" )
# it get the intervall directly from a attribute; the register with interval_command ne 0 will keep on refreshing
########################################################################################
sub THZ_GetRefresh($) {
	my ($par)=@_;
	my $hash=$par->{hash};
	my $command=$par->{command};
	my $interval = AttrVal($hash->{NAME}, ("interval_".$command), 0);
	my $replyc = "";
	if ($interval) {
			  $interval = 60 if ($interval < 60); #do not allow intervall <60 sec 
			  InternalTimer(gettimeofday()+ $interval, "THZ_GetRefresh", $par, 1) ;
	}
	if (!($hash->{STATE} eq "disconnected")) {
	  $replyc = THZ_Get($hash, $hash->{NAME}, $command);
	}
	return ($replyc);
}



#####################################
# THZ_Write -- simple write
# Parameter:  hash and message HEX
#
########################################################################################
sub THZ_Write($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $bstring;
    $bstring = $msg;

  Log $ll5, "$hash->{NAME} sending $bstring";

  DevIo_SimpleWrite($hash, $bstring, 1);
}


#####################################
# sub THZ_Read($)
# called from the global loop, when the select for hash reports data
# used just for testing the interface
########################################################################################
sub THZ_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  
Log $ll5, "$name/RAW: $data";
Log $ll2, "$name/RAW: $data";
  
}



#####################################
#
# THZ_Ready($) - Cchecks the status
#
# Parameter hash
#
########################################################################################
sub THZ_Ready($)
{
  my ($hash) = @_;
  if($hash->{STATE} eq "disconnected")
  { THZ_RemoveInternalTimer("THZ_GetRefresh");
  select(undef, undef, undef, 0.1); #equivalent to sleep 100ms
  return DevIo_OpenDev($hash, 1, "THZ_Refresh_all_gets")
  }	
    # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  if($po) {
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    return ($InBytes>0);
  }
  
}





#####################################
#
# THZ_Set - provides a method for setting the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Set($@){
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  return "\"set $name\" needs at least two parameters: <device-parameter> and <value-to-be-modified>" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my $arg1 = "00:00";
  my ($err, $msg) =("", " ");
  my $cmdhash = $sets{$cmd};
  return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets) if(!defined($cmdhash));
  return "\"set $name $cmd\" needs at least one further argument: <value-to-be-modified>" if(!defined($arg));
  my $cmdHex2 = $cmdhash->{cmd2};
  my $argMax = $cmdhash->{argMax};
  my $argMin = $cmdhash->{argMin};
  if  ((substr($cmdHex2,0,6) eq "0A05D1") or (substr($cmdHex2,2,2) eq "1D") or (substr($cmdHex2,2,2)  eq "17") or (substr($cmdHex2,2,2) eq "15") or (substr($cmdHex2,2,2)  eq "14")) {
    ($arg, $arg1)=split('--', $arg);
      if (($arg ne "n.a.") and ($arg1 ne "n.a.")) {
        return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg1 gt $argMax) or ($arg1 lt $argMin));
        return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg gt $argMax) or ($arg lt $argMin));
        }
    }
  elsif (substr($cmdHex2,0,6) eq "0A0112") {
    $arg1=$arg;
    $arg=$Rev_OpMode{$arg};
    return "Unknown argument $arg1: $cmd supports  " . join(" ", sort values %OpMode) if(!defined($arg));
    }
  else {
    return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg > $argMax) or ($arg < $argMin));
    }
    
  if 	((substr($cmdHex2,0,6) eq "0A0116") or (substr($cmdHex2,0,6) eq "0A05A2") or (substr($cmdHex2,0,6) eq "0A01AC"))	 {$arg=$arg*10} #summermode
  elsif  ((substr($cmdHex2,2,2) eq "1D") or (substr($cmdHex2,2,2)  eq "17") or (substr($cmdHex2,2,2) eq "15") or (substr($cmdHex2,2,2)  eq "14")) 	{$arg= time2quaters($arg) *256   + time2quaters($arg1)} # BeginTime-endtime, in the register is represented  begintime endtime
  elsif  (substr($cmdHex2,0,6) eq "0A05D1") 		  			{$arg= time2quaters($arg1) *256 + time2quaters($arg)} # PartyBeginTime-endtime, in the register is represented endtime begintime
  #partytime (0A05D1) non funziona; 
  elsif  ((substr($cmdHex2,0,6) eq "0A05D3") or (substr($cmdHex2,0,6) eq "0A05D4")) 	{$arg= time2quaters($arg)} # holidayBeginTime-endtime
  elsif  ((substr($cmdHex2,0,5) eq "0A056") or (substr($cmdHex2,0,5) eq "0A057") or (substr($cmdHex2,0,6) eq "0A0588") or (substr($cmdHex2,0,6) eq "0A05A0") or (substr($cmdHex2,0,6) eq "0B059D")      or (substr($cmdHex2,0,6) eq "0A05B7") or (substr($cmdHex2,0,6) eq "0A05B8")  or (substr($cmdHex2,0,6) eq "0A0162")   )	{ } 				# fann speed and boostetimeout: do not multiply
   elsif ((substr($cmdHex2,0,4) eq "0A01") or (substr($cmdHex2,2,4) eq "010F") )			 {$arg=$arg*256}		        	# shift 2 times -- the answer look like  0A0120-3A0A01200E00  for year 14
  elsif  (substr($cmdHex2,2,4) eq "010E") 					{$arg=$arg*100} 		#gradientHC1 &HC2
  else 			             						{$arg=$arg*10} 
  
  Log3 $hash->{NAME}, 5, "THZ_Set: '$cmd $arg' ... Check if port is open. State = '($hash->{STATE})'";

  $cmdHex2=THZ_encodecommand(($cmdHex2 . substr((sprintf("%04X", $arg)), -4)),"set");  #04X converts to hex and fills up 0s; for negative, it must be trunckated. 
  ($err, $msg) = THZ_Get_Comunication($hash,  $cmdHex2);
  if (defined($err))  {
    return ($cmdHex2 . "-". $msg ."--" . $err);}
  else {
    $msg=THZ_Get($hash, $name, $cmd);
    return ($msg);
  }
  
}




#####################################
#
# THZ_Get - provides a method for polling the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Get($@){
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
   my ($err, $msg2) =("", " ");

  if ($cmd eq "debug_read_raw_register_slow") {
    THZ_debugread($hash);
    return ("all raw registers read and saved");
    } 
  
  my $cmdhash = $gets{$cmd};
  return "Unknown argument $cmd, choose one of " .
        join(" ", sort keys %gets) if(!defined($cmdhash));

  Log3 $hash->{NAME}, 5, "THZ_Get: Try to get '$cmd'";
  my $cmdHex2 = $cmdhash->{cmd2};
  if(defined($cmdHex2) ) {
      $cmdHex2=THZ_encodecommand($cmdHex2,"get");
      ($err, $msg2) = THZ_Get_Comunication($hash,  $cmdHex2);
      if (defined($err))     {
             Log3 $hash->{NAME}, 5, "THZ_Get: Error msg2: '$err'";
             return ($msg2 ."\n msg2 " . $err);
      }
      $msg2 = THZ_Parse1($hash,$msg2);
  }
  
  my $cmdHex3 = $cmdhash->{cmd3};
  if(defined($cmdHex3)) {
      my $msg3= " ";
      $cmdHex3=THZ_encodecommand($cmdHex3,"get");
      ($err, $msg3) = THZ_Get_Comunication($hash,  $cmdHex3);
       if (defined($err))     {
             Log3 $hash->{NAME}, 5, "THZ_Get: Error msg3: '$err'";
             return ($msg3 ."\n msg3 " . $err);
      }
      $msg2 = THZ_Parse1($hash,$msg3) * 1000 + $msg2  ;
  }	            		
   
  my $unit = $cmdhash->{unit};
    $msg2 = $msg2 .  $unit  if(defined($unit)) ;
    
    
  my $activatetrigger =1;
  readingsSingleUpdate($hash, $cmd, $msg2, $activatetrigger);
  
  #open (MYFILE, '>>data.txt');
  #print MYFILE ($cmd . "-" . $msg2 . "\n");
  #close (MYFILE); 
  return ($msg2);	       
}



#####################################
#
# THZ_Get_Comunication- provides a method for reading comunication called from THZ_Get
#
# Parameter hash and CMD2 or 3 
#
########################################################################################
sub THZ_Get_Comunication($$) {
my ($hash, $cmdHex) = @_;
my ($err, $msg) =("", " ");

 Log3 $hash->{NAME}, 5, "THZ_Get_Comunication: Check if port is open. State = '($hash->{STATE})'";
 if (!(($hash->{STATE}) eq "opened"))  { return("closed connection", "");}
 
  THZ_Write($hash,  "02"); 			# STX start of text
  ($err, $msg) = THZ_ReadAnswer($hash);		#Expectedanswer1    is  "10"  DLE data link escape
  
   if ($msg eq "10")  {

      THZ_Write($hash,  $cmdHex); 		# send request   SOH start of heading -- Null 	-- ?? -- DLE data link escape -- EOT End of Text
     ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer2     is "1002",		DLE data link escape -- STX start of text
    }
    
  if ($msg eq "10") {
    ($err, $msg) = THZ_ReadAnswer($hash);
  }        

  if($msg eq "1002" || $msg eq "02") {
   THZ_Write($hash,  "10"); 		    	# DLE data link escape  // ack datatranfer
   #select(undef,undef,undef,0.010);
   ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer3 // read from the heatpump
   THZ_Write($hash,  "10");  
   }
   
   if (!(defined($err)))  {($err, $msg) = THZ_decode($msg);} 	#clean up and remove footer and header
   return($err, $msg) ;
}




#####################################
#
# THZ_ReadAnswer- provides a method for simple read
#
# Parameter hash and command to be sent to the interface
#
########################################################################################
sub THZ_ReadAnswer($) 
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 $hash->{NAME}, 5, "$hash->{NAME} start Funktion THZ_ReadAnswer";
        my $buf = DevIo_SimpleReadWithTimeout($hash, 0.8);
	if(!defined($buf)) {
	  Log3 $hash->{NAME}, 3, "$hash->{NAME} THZ_ReadAnswer got no answer from DevIo_SimpleRead. Maybe too slow?";
	  return ("InterfaceNotRespondig", "");
	}
	
	my $data =  uc(unpack('H*', $buf));
	
	if ((length($data) > 4) and ($data !~ m/1003$/m )) # sometimes the first read gets a trunkated buffer, second read makes sure all the buffer is read.
	{ my $buf1 = DevIo_SimpleReadWithTimeout($hash, 0.005);
	  Log3($hash->{NAME}, 5, "double read activated $data");
	  if(defined($buf1))
	  {
	  $buf = ($buf . $buf1) ;
	  $data =  uc(unpack('H*', $buf));
	   Log3($hash->{NAME}, 5, "double read result with buf1  $data");
	  }
	}
	
	if ((length($data) > 4) and ($data !~ m/1003$/m )) # sometimes the first read gets a trunkated buffer, third read makes sure all the buffer is read.
	{ my $buf2 = DevIo_SimpleReadWithTimeout($hash, 0.005);
	  Log3($hash->{NAME}, 5, "triple read activated $data");
	  if(defined($buf2))
	  {
	  $buf = ($buf . $buf2) ;
	  $data =  uc(unpack('H*', $buf));
	   Log3($hash->{NAME}, 5, "triple read result with buf2  $data");
	  }
	}
	
	
	if ((length($data) > 4) and ($data !~ m/1003$/m )) # sometimes the first read gets a trunkated buffer, fourth read makes sure all the buffer is read.
	{ my $buf3 = DevIo_SimpleReadWithTimeout($hash, 0.005);
	  Log3($hash->{NAME}, 5, "quadruple read activated $data");
	  if(defined($buf3))
	  {
	  $buf = ($buf . $buf3) ;
	  $data =  uc(unpack('H*', $buf));
	   Log3($hash->{NAME}, 5, "quadruple read result with buf3  $data");
	  }
	}
	
	
	Log3 $hash->{NAME}, 5, "THZ_ReadAnswer: uc unpack: '$data'";	
	return (undef, $data);
}

 
#####################################
#
# THZ_checksum - takes a string, removes the footer (4bytes) and computes checksum (without checksum of course)
#
# Parameter string
# returns the checksum 2bytes
#
########################################################################################
sub THZ_checksum($) {
  my ($stringa) = @_;
  my $ml = length($stringa) - 4;
  my $checksum = 0;
  for(my $i = 0; $i < $ml; $i += 2) {
    ($checksum= $checksum + hex(substr($stringa, $i, 2))) if ($i != 4);
  }
  return (sprintf("%02X", ($checksum %256)));
}

#####################################
#
# hex2int - convert from hex to int with sign 16bit
#
########################################################################################
sub hex2int($) {
  my ($num) = @_;
 $num = unpack('s', pack('S', hex($num)));
  return $num;
}

####################################
#
# quaters2time - convert from hex to time; specific to the week programm registers
#
# parameter 1 byte representing number of quarter from midnight
# returns   string representing time
#
# example: value 1E is converted to decimal 30 and then to a time  7:30 
########################################################################################
sub quaters2time($) {
  my ($num) = @_;
  return("n.a.") if($num eq "80"); 
  my $quarters= hex($num) %4;
  my $hour= (hex($num) - $quarters)/4 ;
  my $time = sprintf("%02u", ($hour)) . ":" . sprintf("%02u", ($quarters*15));
  return $time;
}




####################################
#
# time2quarters - convert from time to quarters in hex; specific to the week programm registers
#
# parameter: string representing time
# returns: 1 byte representing number of quarter from midnight
#
# example: a time  7:30  is converted to decimal 30 
########################################################################################
sub time2quaters($) {
   my ($stringa) = @_;
   return("128") if($stringa eq "n.a."); 
 my ($h,$m) = split(":", $stringa);
  $m = 0 if(!$m);
  $h = 0 if(!$h);
  my $num = $h*4 +  int($m/15);
  return ($num);
}


####################################
#
# THZ_replacebytes - replaces bytes in string
#
# parameters: string, bytes to be searched, replacing bytes 
# retunrns changed string
#
########################################################################################
sub THZ_replacebytes($$$) {
  my ($stringa, $find, $replace) = @_; 
  my $leng_str = length($stringa);
  my $leng_find = length($find);
  my $new_stringa ="";
  for(my $i = 0; $i < $leng_str; $i += 2) {
    if (substr($stringa, $i, $leng_find) eq $find){
      $new_stringa=$new_stringa . $replace;
      if ($leng_find == 4) {$i += 2;}
      }
    else {$new_stringa=$new_stringa . substr($stringa, $i, 2);};
  }
  return ($new_stringa);
}


## usage THZ_overwritechecksum("0100XX". $cmd."1003"); not needed anymore
sub THZ_overwritechecksum($) {
  my ($stringa) = @_;
  my $checksumadded=substr($stringa,0,4) . THZ_checksum($stringa) . substr($stringa,6);
  return($checksumadded);
}


####################################
#
# THZ_encodecommand - creates a telegram for the heatpump with a given command 
#
# usage THZ_encodecommand($cmd,"get") or THZ_encodecommand($cmd,"set");
# parameter string, 
# retunrns encoded string
#
########################################################################################

sub THZ_encodecommand($$) {
  my ($cmd,$getorset) = @_;
  my $header = "0100";
  $header = "0180" if ($getorset eq "set");	# "set" and "get" have differnt header
  my $footer ="1003";
  my $checksumadded=THZ_checksum($header . "XX" . $cmd . $footer) . $cmd;
  # each 2B byte must be completed by byte 18
  # each 10 byte must be repeated (duplicated)
  my $find = "10";
  my $replace = "1010";
  #$checksumadded =~ s/$find/$replace/g; #problems in 1% of the cases, in middle of a byte
  $checksumadded=THZ_replacebytes($checksumadded, $find, $replace);
  $find = "2B";
  $replace = "2B18";
  #$checksumadded =~ s/$find/$replace/g;
  $checksumadded=THZ_replacebytes($checksumadded, $find, $replace);
  return($header. $checksumadded .$footer);
}





####################################
#
# THZ_decode -	decodes a telegram from the heatpump -- no parsing here
#
# Each response has the same structure as request - header (four bytes), optional data and footer:
#   Header: 01
#    Read/Write: 00 for Read (get) response, 80 for Write (set) response; when some error occured, then device stores error code here; actually, I know only meaning of error 03 = unknown command
#    Checksum: ? 1 byte - the same algorithm as for request
#    Command: ? 1 byte - should match Request.Command
#    Data: ? only when Read, length depends on data type
#    Footer: 10 03
#
########################################################################################


sub THZ_decode($) {
  my ($message_orig) = @_;
  #  raw data received from device have to be de-escaped before header evaluation and data use:
  # - each sequece 2B 18 must be replaced with single byte 2B
  # - each sequece 10 10 must be replaced with single byte 10
  my $find = "1010";
  my $replace = "10";
  $message_orig=THZ_replacebytes($message_orig, $find, $replace);
  $find = "2B18";
  $replace = "2B";
  $message_orig=THZ_replacebytes($message_orig, $find, $replace);
  
  #Check if answer is NAK
  if (length($message_orig) == 2 && $message_orig eq "15") {
    return("NAK received from device",$message_orig);
  }
  
  #check header and if ok 0100, check checksum and return the decoded msg
  my $header = substr($message_orig,0,4);
  if ($header eq  "0100")
  {
    if (THZ_checksum($message_orig) eq substr($message_orig,4,2)) {
      $message_orig =~ /0100(.*)1003/; 
      my $message = $1;
      return (undef, $message);
    }
    else {return (THZ_checksum($message_orig) . "crc_error in answer", $message_orig)};
  }
  if ($header eq "0103")
  {
    return ("command not known", $message_orig);
  }
  if ($header eq "0102")
  {
    return ("CRC error in request", $message_orig);
  }
  if ($header eq "0104")
  {
    return ("UNKNOWN REQUEST", $message_orig);
  }
   if ($header eq "0180")
  {
    return (undef, $message_orig);
  }
  
  return ("new unknown answer " , $message_orig);
}




########################################################################################
#
# THZ_Parse -0A01
#
########################################################################################
	
sub THZ_Parse($$) {
  my ($hash,$message) = @_;
  Log3 $hash->{NAME}, 5, "Parse message: $message";	  
  my $length = length($message);
  Log3 $hash->{NAME}, 4, "Message length: $length";
  
  
  given (substr($message,2,2)) {
  when ("0A")    {
       if (substr($message,4,4) eq "0116")						{$message = hex2int(substr($message, 8,4))/10  } #done
      elsif (substr($message,4,4) eq "0112") 						{$message = $OpMode{hex(substr($message, 8,2))} } #done
      elsif ((substr($message,4,3) eq "011")	or (substr($message,4,3) eq "012")) 	{$message = hex(substr($message, 8,2))} #done #holiday						      # the answer look like  0A0120-3A0A01200E00  for year 14
      elsif ((substr($message,4,2) eq "1D") or (substr($message,4,2) eq "17")) 		{$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))} #done  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30  
      elsif (substr($message,4,4) eq "05D1") 				 		{$message = quaters2time(substr($message, 10,2)) ."--". quaters2time(substr($message, 8,2))}  #like above but before stop then start !!!!
      elsif ((substr($message,4,4) eq "05D3") or (substr($message,4,4) eq "05D4"))   	{$message = quaters2time(substr($message, 10,2)) }  #value 1Ch 28dec is 7 
      elsif ((substr($message,4,3) eq "056")  or (substr($message,4,4) eq "0570")  or (substr($message,4,4) eq "0575") or (substr($message,4,4) eq "03AE") or (substr($message,4,4) eq "03AF") or (substr($message,4,4) eq "03B0") or (substr($message,4,4) eq "03B1") or (substr($message,4,3) eq "091") or (substr($message,4,3) eq "092") or (substr($message,4,3) eq "093") or (substr($message,4,4) eq "05B7") or (substr($message,4,4) eq "05B8"))	{$message = hex(substr($message, 8,4))}
      elsif ( (substr($message,4,4) eq "0162") or (substr($message,4,4) eq "0588") or (substr($message,4,4) eq "05A0")  or (substr($message,4,4) eq "0571") or (substr($message,4,4) eq "0572") or (substr($message,4,4) eq "0573") or (substr($message,4,4) eq "0574")) {$message = hex(substr($message, 8,4))  } #done
      elsif (substr($message,4,3) eq "057")						{$message = hex(substr($message, 8,4))  }  #done
      elsif (substr($message,4,4) eq "05A2")						{$message = hex(substr($message, 8,4))/10  } #done
      else 										{$message = hex2int(substr($message, 8,4))/10 } #done
  }  
  when ("0B")    {							   #set parameter HC1
      if (substr($message,4,2) eq "14")  {$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
      elsif (substr($message,4,4) eq "059E")						{$message = hex(substr($message, 8,4))/10   } #done
      elsif (substr($message,4,4) eq "059D")						{$message = hex(substr($message, 8,4))  } #done
      elsif (substr($message,4,4) eq "010E")						{$message = hex(substr($message, 8,4))/100} #done
      elsif (substr($message,4,4) eq "010F")						{$message = hex(substr($message, 8,2)) } #done
      else 				 {$message = hex2int(substr($message, 8,4))/10 } #done
  }
  when ("0C")    {							   #set parameter HC2
      if (substr($message,4,2) eq "15")  {$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
      elsif (substr($message,4,4) eq "059E")						{$message = hex(substr($message, 8,4))/10  } #done
      elsif (substr($message,4,4) eq "010E")						{$message = hex(substr($message, 8,4))/100} #done
      elsif (substr($message,4,4) eq "010F")						{$message = hex(substr($message, 8,2)) } #done
      else 				 {$message = hex2int(substr($message, 8,4))/10  } #done
  }
  
    when ("16")    {                     #all16 Solar
    $message =
		"collector_temp: " 		. hex2int(substr($message, 4,4))/10 . " " .
        	"dhw_temp: " 			. hex2int(substr($message, 8,4))/10 . " " .
        	"flow_temp: "			. hex2int(substr($message,12,4))/10 . " " .
        	"ed_sol_pump_temp: "		. hex2int(substr($message,16,4))/10 . " " .
        	"x20: "	 	 		. hex2int(substr($message,20,4))    . " " .
        	"x24: "				. hex2int(substr($message,24,4))    . " " . 
		"x28: "				. hex2int(substr($message,28,4))    . " " . 
        	"x32: "				. hex2int(substr($message,32,2)) ;
  }
  
  
    when ("F3")    {                     #allF3 DHW
    $message =
		"dhw_temp: " 			. hex2int(substr($message, 4,4))/10 . " " .
        	"outside_temp: " 		. hex2int(substr($message, 8,4))/10 . " " .
        	"dhw_set_temp: "		. hex2int(substr($message,12,4))/10 . " " .
        	"comp_block_time: "		. hex2int(substr($message,16,4))    . " " .
        	"x20: " 			. hex2int(substr($message,20,4))    . " " .
        	"heat_block_time: "		. hex2int(substr($message,24,4))    . " " . 
		"x28: "				. hex2int(substr($message,28,4))    . " " . 
        	"x32: "				. hex2int(substr($message,32,4))    . " " .
        	"x36: "				. hex2int(substr($message,36,4));
  }
  
  when ("E8")    {                     #sAllE8
    $message =  $message . " " .
		"x04: " 			. hex2int(substr($message, 4,4)) . " " .
        	"x08: " 			. hex2int(substr($message, 8,4)) . " " .
        	"x12: "				. hex2int(substr($message,12,4)) . " " .
        	"x16: "				. hex2int(substr($message,16,4)) . " " .
        	"x20: " 			. hex2int(substr($message,20,4)) . " " .
        	"x24: "				. hex2int(substr($message,24,4)) . " " . 
		"x28: "				. hex2int(substr($message,28,4)) . " " . 
	      	"x32: "				. hex2int(substr($message,32,4)) . " " .
        	"x36: "			        . hex2int(substr($message,36,4)) . " " .
		"x40: "				. hex2int(substr($message,40,4)) . " " .
		"x44: "				. hex2int(substr($message,44,4)) . " " .
		"x48: "				. hex2int(substr($message,48,4)) . " " .
        	"x52: "				. hex2int(substr($message,52,4)) . " " .
        	"x52: "				. hex2int(substr($message,56,4)) . " " .
 	     	"x60d: " 			. hex2int(substr($message,60,4)) . " " .
 	    	"x64: "				. hex2int(substr($message,64,4)) . " " .
		"x68: "				. hex2int(substr($message,68,4)) . " " .
         	"x72: "				. hex2int(substr($message,72,4)) ;
  }  
  
  
  when ("F4")    {                     #allF4 HC1
    $message =
		"outsideTemp: " 		. hex2int(substr($message, 4,4))/10 . " " .
        	"x08: " 			. hex2int(substr($message, 8,4))/10 . " " .
        	"returnTemp: "			. hex2int(substr($message,12,4))/10 . " " .
        	"integralHeat: "		. hex2int(substr($message,16,4))    . " " .
        	"flowTemp: " 			. hex2int(substr($message,20,4))/10 . " " .
        	"heatSetTemp: "			. hex2int(substr($message,24,4))/10 . " " . #soll HC1
		"heatTemp: "			. hex2int(substr($message,28,4))/10 . " " . #ist
#	      	"x32: "				. hex2int(substr($message,32,4))/10 . " " .
        	"seasonMode: "		        . $SomWinMode{(substr($message,38,2))}  . " " .
#		"x40: "				. hex2int(substr($message,40,4))/10 . " " .
		"integralSwitch: "		. hex2int(substr($message,44,4))    . " " .
		"opMode: "			. $OpModeHC{hex(substr($message,48,2))}  . " " .
#       	"x52: "				. hex2int(substr($message,52,4)) . " " .
        	"roomSetTemp: "			. hex2int(substr($message,56,4))/10 ;
# 	     	"x60: " 			. hex2int(substr($message,60,4)) . " " .
# 	    	"x64: "				. hex2int(substr($message,64,4)) . " " .
#		"x68: "				. hex2int(substr($message,68,4)) . " " .
#       	"x72: "				. hex2int(substr($message,72,4)) . " " .
# 	     	"x76: "				. hex2int(substr($message,76,4)) . " " .
# 	    	"x80: "				. hex2int(substr($message,80,2))
  }
  when ("F5")    {                     #allF5  HC2
    $message =
		"outsideTemp: " 		. hex2int(substr($message, 4,4))/10 . " " .
        	"returnTemp: " 		. hex2int(substr($message, 8,4))/10 . " " .
        	"vorlaufTemp: "			. hex2int(substr($message,12,4))/10 . " " .
        	"heatSetTemp: "		. hex2int(substr($message,16,4))/10 . " " .
        	"heatTemp: " 			. hex2int(substr($message,20,4))/10 . " " .
        	"stellgroesse: "		. hex2int(substr($message,24,4))/10 . " " . 
	        "seasonMode: "		        . $SomWinMode{(substr($message,30,2))}  . " " .
#	     	"x32: "				. hex2int(substr($message,32,4)) . " " .
	    	"opMode: "			. $OpModeHC{hex(substr($message,36,2))} ;
# 	  	"x40: "				. hex2int(substr($message,40,4)) . " " .
#		"x44: "				. hex2int(substr($message,44,4)) . " " .
#		"x48: " 			. hex2int(substr($message,48,4));
  }

  
  when ("FD")    {                     #firmware_ver
    $message = "version: " . hex(substr($message,4,4))/100 ;
  }
  when ("FC")    {                     #timedate 00 - 0F 1E 08 - 0D 03 0B
    my %weekday = ( "0" =>"Monday", "1" => "Tuesday", "2" =>"Wednesday", "3" => "Thursday", "4" => "Friday", "5" =>"Saturday", "6" => "Sunday" );
    $message = 	  "Weekday: "		. $weekday{hex(substr($message, 4,2))}    . " " .
            	  "Hour: " 		. hex(substr($message, 6,2)) . " Min: " . hex(substr($message, 8,2)) . " Sec: " . hex(substr($message,10,2)) . " " .
              	  "Date: " 		. (hex(substr($message,12,2))+2000)  .	"/"		. hex(substr($message,14,2)) . "/"		. hex(substr($message,16,2));
  }
  when ("FB")    {                     #allFB
#          1         2         3         5         6         7         8         9
#012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789
#0DFBFDA8005D014E010602CF01CCFDA8FDA80007014C200813021C021C0258001A001E0013006100000000
    $message =    "outsideTemp: " 				. hex2int(substr($message, 8,4))/10 . " " .
        	  "flowTemp: "					. hex2int(substr($message,12,4))/10 . " " .  #Vorlauf Temperatur
        	  "returnTemp: "				. hex2int(substr($message,16,4))/10 . " " .  #Rücklauf Temperatur
        	  "hotGasTemp: " 				. hex2int(substr($message,20,4))/10 . " " .  #Heißgas Temperatur		
        	  "dhwTemp: "					. hex2int(substr($message,24,4))/10 . " " .  #Speicher Temperatur current cilinder water temperature
        	  "flowTempHC2: "				. hex2int(substr($message,28,4))/10 . " " .  #Vorlauf TemperaturHK2
		  "evaporatorTemp: "				. hex2int(substr($message,36,4))/10 . " " .  #Speicher Temperatur    
        	  "condenserTemp: "				. hex2int(substr($message,40,4))/10 . " " .  
        	  "mixerOpen: "					. ((hex(substr($message,45,1)) &  0b0001) / 0b0001) . " " .	#status bit
		  "mixerClosed: "				. ((hex(substr($message,45,1)) &  0b0010) / 0b0010) . " " .	#status bit
		  "heatPipeValve: "				. ((hex(substr($message,45,1)) &  0b0100) / 0b0100) . " " .	#status bit
		  "diverterValve: "				. ((hex(substr($message,45,1)) &  0b1000) / 0b1000) . " " .	#status bit
		  "dhwPump: "					. ((hex(substr($message,44,1)) &  0b0001) / 0b0001) . " " .	#status bit
		  "heatingCircuitPump: "			. ((hex(substr($message,44,1)) &  0b0010) / 0b0010) . " " .	#status bit
		  "solarPump: "					. ((hex(substr($message,44,1)) &  0b1000) / 0b1000) . " " .	#status bit
		  "compressor: "				. ((hex(substr($message,47,1)) &  0b1000) / 0b1000) . " " .	#status bit
		  "boosterStage3: "				. ((hex(substr($message,46,1)) &  0b0001) / 0b0001) . " " .	#status bit
		  "boosterStage2: "				. ((hex(substr($message,46,1)) &  0b0010) / 0b0010) . " " .	#status bit
		  "boosterStage1: "				. ((hex(substr($message,46,1)) &  0b0100) / 0b0100). " " .	#status bit
		  "highPressureSensor: "			. (1-((hex(substr($message,49,1)) &  0b0001) / 0b0001)) . " " .	#status bit  #P1 	inverterd?
		  "lowPressureSensor: "				. (1-((hex(substr($message,49,1)) &  0b0010) / 0b0010)) . " " .	#status bit  #P3  inverterd?
		  "evaporatorIceMonitor: "			. ((hex(substr($message,49,1)) &  0b0100) / 0b0100). " " .	#status bit  #N3
		  "signalAnode: "				. ((hex(substr($message,49,1)) &  0b1000) / 0b1000). " " .	#status bit  #S1
		  "rvuRelease: "				. ((hex(substr($message,48,1)) &  0b0001) / 0b0001). " " . 	#status bit 
		  "ovenFireplace: "				. ((hex(substr($message,48,1)) &  0b0010) / 0b0010). " " .  	#status bit
		  "STB: "					. ((hex(substr($message,48,1)) &  0b0100) / 0b0100). " " .	#status bit  	
		  "outputVentilatorPower: "			. hex(substr($message,50,4))/10  	. " " .
        	  "inputVentilatorPower: " 			. hex(substr($message,54,4))/10  	. " " .
        	  "mainVentilatorPower: "			. hex(substr($message,58,4))/10  	. " " .
        	  "outputVentilatorSpeed: "			. hex(substr($message,62,4))/1   	. " " .  # m3/h
        	  "inputVentilatorSpeed: " 			. hex(substr($message,66,4))/1   	. " " .  # m3/h
        	  "mainVentilatorSpeed: "			. hex(substr($message,70,4))/1   	. " " .  # m3/h
                  "outside_tempFiltered: "			. hex2int(substr($message,74,4))/10     . " " .
                  "relHumidity: "				. hex2int(substr($message,78,4))/10	. " " .
		  "dewPoint: "					. hex2int(mysubstr($hash,$message,82,4))/10	. " " .
		  "P_Nd: "					. hex2int(mysubstr($hash,$message,86,4))/100	. " " .	#bar
		  "P_Hd: "					. hex2int(mysubstr($hash,$message,90,4))/100	. " " .  #bar
		  "actualPower_Qc: "				. hex2int(mysubstr($hash,$message,94,8))/1      . " " .	#kw
		  "actualPower_Pel: "				. hex2int(mysubstr($hash,$message,102,8))/1     . " " .	#kw
		  "collectorTemp: " 				. hex2int(substr($message, 4,4))/10  . " " .	#kw
		  "insideTemp: " 				. hex2int(substr($message, 32,4))/10 ;	#Innentemperatur 
  }
  when ("09")    {                     #operating history
    $message =    "compressorHeating: "	. hex(substr($message, 4,4))    . " " .
                  "compressorCooling: "	. hex(substr($message, 8,4))    . " " .
                  "compressorDHW: "		. hex(substr($message, 12,4))    . " " .
                  "boosterDHW: "		. hex(substr($message, 16,4))    . " " .
                  "boosterHeating: "		. hex(substr($message, 20,4))   ;			
  }
  when ("D1")    {                     #last10errors tested only for 1 error   { THZ_Parse("6BD1010115008D07EB030000000000000000000")  }
    $message =    "number_of_faults: "		. hex(substr($message, 4,2))    . " " .
                  #empty
		  "fault0CODE: "		. hex(substr($message, 8,2))    . " " .
                  "fault0TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 14,2) . substr($message, 12,2))/100)))   . " " .
                  "fault0DATE: "		. (hex(substr($message, 18,2) . substr($message, 16,2))/100) . " " .
		  
		  "fault1CODE: "		. hex(substr($message, 20,2))    . " " .
                  "fault1TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 26,2) . substr($message, 24,2))/100)))   . " " .
                  "fault1DATE: "		. (hex(substr($message, 30,2) . substr($message, 28,2))/100) . " " .
		 
		  "fault2CODE: "		. hex(substr($message, 32,2))    . " " .
                  "fault2TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 38,2) . substr($message, 36,2))/100)))   . " " .
                  "fault2DATE: "		. (hex(substr($message, 42,2) . substr($message, 40,2))/100) . " " .
		
		  "fault3CODE: "		. hex(substr($message, 44,2))    . " " .
                  "fault3TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 50,2) . substr($message, 48,2))/100)))   . " " .
                  "fault3DATE: "		. (hex(substr($message, 54,2) . substr($message, 52,2))/100)  ;			
  }    
  }
  return (undef, $message);
}







#######################################
#mysubstr($$$)
#Same function as subst. But checks if offset + lenght is 
#available in the string. If not, returns zeros.
#######################################
sub mysubstr($$$$)
{
  my ($hash,$message,$start, $length) = @_; 
  my $ReturnValue = "";                
  if (length($message) < ($start + $length))
  {
    Log3 $hash->{NAME},5, "mysubstr: offset($start) + length($length) is greater then message : '$message'";
    my $msg;
    for(my $i = 0;$i < $length;$i++)
    {
            $msg += "0";
    }
    $ReturnValue = uc(unpack('H*',pack('H*', $msg)));
    Log3 $hash->{NAME},5,"mysubstr: retval instead '$ReturnValue'";
    return $ReturnValue;
  }
  return substr($message,$start,$length);	
}

local $SIG{__WARN__} = sub
{
  my $message = shift;
  
  if (!defined($internalHash)) {
    Log 3, "EXCEPTION in THZ: '$message'";
  }
  else
  {
    Log3 $internalHash->{NAME},3, "EXCEPTION in THZ: '$message'";
  }  
};



#######################################
#THZ_Parse1($) could be used in order to test an external config file; I do not know if I want it
#e.g. {THZ_Parse1("","F70B000500E6")}
#######################################

sub THZ_Parse1($$) {
my %parsinghash = (
  "09his"  => [["compressorHeating: ",	4, 4,  "hex", 1],	[" compressorCooling: ",  8, 4, "hex", 1],
	      [" compressorDHW: ",	12, 4, "hex", 1],	[" boosterDHW: ",	16, 4, "hex", 1],
	      [" boosterHeating: ",	20, 4, "hex", 1]
	      ],
  "16sol"  => [["collector_temp: ",	4, 4, "hex2int", 10],	[" dhw_temp: ", 	 8, 4, "hex2int", 10],
	      [" flow_temp: ",		12, 4, "hex2int", 10],	[" ed_sol_pump_temp: ",	16, 4, "hex2int", 10],
	      [" x20: ",		20, 4, "hex2int", 1],	[" x24: ",		24, 4, "hex2int", 1], 
	      [" x28: ",		28, 4, "hex2int", 1], 	[" x32: ",		32, 2, "hex2int", 1] 
	      ],
  "D1last" => [["number_of_faults: ",	4, 2, "hex", 1],	
	      [" fault0CODE: ",		8, 2, "hex", 1],	[" fault0TIME: ",	12, 4, "turnhex2time", 1],  [" fault0DATE: ",	16, 4, "turnhex", 100],
	      [" fault1CODE: ",		20, 2, "hex", 1],	[" fault1TIME: ",	24, 4, "turnhex2time", 1],  [" fault1DATE: ",	28, 4, "turnhex", 100],
	      [" fault2CODE: ",		32, 2, "hex", 1],	[" fault2TIME: ",	36, 4, "turnhex2time", 1],  [" fault2DATE: ",	40, 4, "turnhex", 100],
	      [" fault3CODE: ",		44, 2, "hex", 1],	[" fault3TIME: ",	48, 4, "turnhex2time", 1],  [" fault3DATE: ",	52, 4, "turnhex", 100]
	      ],
  "F3dhw"  => [["dhw_temp: ",		4, 4, "hex2int", 10],	[" outside_temp: ", 	8, 4, "hex2int", 10],
	      [" dhw_set_temp: ",	12, 4, "hex2int", 10],  [" comp_block_time: ",	16, 4, "hex2int", 1],
	      [" x20: ", 		20, 4, "hex2int", 1],	[" heat_block_time: ", 	24, 4, "hex2int", 1], 
	      [" x28: ",		28, 4, "hex2int", 1],	[" x32: ",		32, 4, "hex2int", 1],
	      [" x36: ",		36, 4, "hex", 1]
	      ],
  "F4hc1"  => [["outsideTemp: ", 	4, 4, "hex2int", 10],	[" x08: ",	 	8, 4, "hex2int", 10],
	      [" returnTemp: ",		12, 4, "hex2int", 10],  [" integralHeat: ",	16, 4, "hex2int", 1],
	      [" flowTemp: ",		20, 4, "hex2int", 10],	[" heatSetTemp: ", 	24, 4, "hex2int", 10], 
	      [" heatTemp: ",		28, 4, "hex2int", 10],  #[" x32: ",		32, 4, "hex2int", 1],
	      [" seasonMode: ",		38, 2, "somwinmode", 1],#[" x40: ",		40, 4, "hex2int", 1],
	      [" integralSwitch: ",	44, 4, "hex2int", 1],	[" opMode: ",		48, 2, "opmodehc", 1],
	      #[" x52: ",		52, 4, "hex2int", 1],
              [" roomSetTemp: ",	56, 4, "hex2int", 10]
	     ],
  "F5hc2"  => [["outsideTemp: ", 	4, 4, "hex2int", 10],	[" returnTemp: ",	8, 4, "hex2int", 10],
	      [" vorlaufTemp: ",	12, 4, "hex2int", 10],  [" heatSetTemp: ",	16, 4, "hex2int", 10],
	      [" heatTemp: ", 		20, 4, "hex2int", 10],	[" stellgroesse: ",	24, 4, "hex2int", 10], 
	      [" seasonMode: ",		30, 2, "somwinmode", 1],[" opMode: ",		36, 2, "opmodehc", 1]
	     ],
  "FBglob" => [["outsideTemp: ", 	8, 4, "hex2int", 10],	[" flowTemp: ",		12, 4, "hex2int", 10],
	      [" returnTemp: ",		16, 4, "hex2int", 10],	[" hotGasTemp: ", 	20, 4, "hex2int", 10],
	      [" dhwTemp: ",	 	24, 4, "hex2int", 10], 	[" flowTempHC2: ",	28, 4, "hex2int", 10],
	      [" evaporatorTemp: ",	36, 4, "hex2int", 10],  [" condenserTemp: ",	40, 4, "hex2int", 10],
	      [" mixerOpen: ",		45, 1, "bit0", 1],  	[" mixerClosed: ",		45, 1, "bit1", 1],
	      [" heatPipeValve: ",	45, 1, "bit2", 1],  	[" diverterValve: ",		45, 1, "bit3", 1],
	      [" dhwPump: ",		44, 1, "bit0", 1],  	[" heatingCircuitPump: ",	44, 1, "bit1", 1],
	      [" solarPump: ",		44, 1, "bit3", 1],  	[" compressor: ",		47, 1, "bit3", 1],
	      [" boosterStage3: ",	46, 1, "bit0", 1],  	[" boosterStage2: ",		46, 1, "bit1", 1],
	      [" boosterStage1: ",	46, 1, "bit2", 1],  	[" highPressureSensor: ",	49, 1, "nbit0", 1],
	      [" lowPressureSensor: ",	49, 1, "nbit1", 1],  	[" evaporatorIceMonitor: ",	49, 1, "bit2", 1],
	      [" signalAnode: ",	49, 1, "bit3", 1],  	[" rvuRelease: ",		48, 1, "bit0", 1],
	      [" ovenFireplace: ",	48, 1, "bit1", 1],  	[" STB: ",			48, 1, "bit2", 1],
	      [" outputVentilatorPower: ",	50, 4, "hex", 10],  	[" inputVentilatorPower: ",	54, 4, "hex", 10],	[" mainVentilatorPower: ",	58, 4, "hex", 10],
	      [" outputVentilatorSpeed: ",	62, 4, "hex", 1],	[" inputVentilatorSpeed: ",	66, 4, "hex", 1],  	[" mainVentilatorSpeed: ",	70, 4, "hex", 1],
	      [" outside_tempFiltered: ",	74, 4, "hex2int", 10],	[" relHumidity: ",		78, 4, "hex2int", 10],
	      [" dewPoint: ",			82, 4, "hex2int", 10],
	      [" P_Nd: ",			86, 4, "hex2int", 100],	[" P_Hd: ",			90, 4, "hex2int", 100],
	      [" actualPower_Qc: ",		94, 8, "hex2int", 1],	[" actualPower_Pel: ",		102, 8, "hex2int", 1],
	      [" collectorTemp: ",		4,  4, "hex2int", 10],	[" insideTemp: ",		32, 4, "hex2int", 10]
	      ],
  "FCtime" => [["Weekday: ", 		4, 1,  "weekday", 1],	[" Hour: ",	6, 2, "hex", 1],
	      [" Min: ",		8, 2,  "hex", 1], 	[" Sec: ",	10, 2, "hex", 1],
	      [" Date: ", 		12, 2, "year", 1],	["/", 		14, 2, "hex", 1],
	      ["/", 			16, 2, "hex", 1]
	     ],
  "FDfirm" => [["version: ", 	4, 4, "hex", 100]
	     ],
  "0clean"    => [["", 8, 2, "hex", 1]             
              ],
  "1clean"    => [["", 8, 4, "hex", 1]             
              ],
  "2opmode"   => [["", 8, 2, "opmode", 1]             
              ],
  "5temp"     => [["", 8, 4, "hex2int",10]             
	      ],
  "6gradient" => [["", 8, 4, "hex", 100]             
              ],
  "7prog"     => [["", 8, 2, "quater", 1], 	["--", 10, 2, "quater", 1]
              ],
  "8party"    => [["", 10, 2, "quater", 1],	["--", 8, 2, "quater", 1]
              ],
  "9holy"     => [["", 10, 2, "quater", 1]
              ]
);
  my ($hash,$message) = @_;
  Log3 $hash->{NAME}, 5, "Parse message: $message";	  
  my $length = length($message);
  Log3 $hash->{NAME}, 5, "Message length: $length";
  my $parsingcmd = substr($message,2,2);
  $parsingcmd = substr($message,2,6) if ($parsingcmd =~ m/(0A|0B|0C)/) ;
  my $msgtype;
  my $parsingrule;
  my $parsingelement;
  # search for the type in %gets
     foreach  my $cmdhash  (values %gets) {
    if ($cmdhash->{cmd2} eq $parsingcmd)
	{$msgtype = $cmdhash->{type} ;
	 last
	 }
    elsif (defined ($cmdhash->{cmd3}))
	{ if ($cmdhash->{cmd3} eq $parsingcmd)
	   {$msgtype = $cmdhash->{type} ;
	  last
	  }
	 }
  }
  $parsingrule = $parsinghash{$msgtype} if(defined($msgtype));
  
  my $ParsedMsg = $message;
  if(defined($parsingrule)) {
    $ParsedMsg = "";
    for  $parsingelement  (@$parsingrule) {
      my $parsingtitle = $parsingelement->[0];
      my $positionInMsg = $parsingelement->[1];
      my $lengthInMsg = $parsingelement->[2];
      my $Type = $parsingelement->[3];
      my $divisor = $parsingelement->[4];
      #check if parsing out of message, and fill with zeros; the other possibility is to skip the step.
      if (length($message) < ($positionInMsg + $lengthInMsg))    {
      	Log3 $hash->{NAME}, 3, "THZ_Parsing: offset($positionInMsg) + length($lengthInMsg) is longer then message : '$message'"; 
      	$message.= '0' x ($positionInMsg + $lengthInMsg - length($message)); # fill up with 0s to the end if needed
      	#Log3 $hash->{NAME},3, "after: '$message'"; 
      }
      my $value = substr($message, $positionInMsg, $lengthInMsg);
      given ($Type) {
        when ("hex")		{$value= hex($value);}
	when ("year")		{$value= hex($value)+2000;}
        when ("hex2int")	{$value= hex2int($value);}
	when ("turnhex")	{$value= hex(substr($value, 2,2) . substr($value, 0,2));}
	when ("turnhex2time")	{$value= sprintf(join(':', split("\\.", hex(substr($value, 2,2) . substr($value, 0,2))/100))) ;}
	when ("opmode")		{$value= $OpMode{hex($value)};}
	when ("opmodehc")	{$value= $OpModeHC{hex($value)};}
	when ("somwinmode")	{$value= $SomWinMode{($value)};}
	when ("weekday")	{$value= $weekday{($value)};}
	when ("quater")		{$value= quaters2time($value);}
	when ("bit0")		{$value= (hex($value) &  0b0001) / 0b0001;}
	when ("bit1")		{$value= (hex($value) &  0b0010) / 0b0010;}
	when ("bit2")		{$value= (hex($value) &  0b0100) / 0b0100;}
	when ("bit3")		{$value= (hex($value) &  0b1000) / 0b1000;}
	when ("nbit0")		{$value= 1-((hex($value) &  0b0001) / 0b0001);}
	when ("nbit1")		{$value= 1-((hex($value) &  0b0010) / 0b0010);}
      }
      $value = $value/$divisor if ($divisor != 1); 
      $ParsedMsg = $ParsedMsg . $parsingtitle . $value; 
    }
  }
  return (undef, $ParsedMsg);
}





########################################################################################
# only for debug
#
########################################################################################
sub THZ_debugread($){
  my ($hash) = @_;
  my ($err, $msg) =("", " ");
 # my @numbers=('01', '09', '16', 'D1', 'D2', 'E8', 'E9', 'F2', 'F3', 'F4', 'F5', 'F6', 'FB', 'FC', 'FD', 'FE');
 my @numbers=('0B0005','0A03AF', '0A03B0', '0A03B1'); 
  #my @numbers = (1..255);
  #my @numbers = (1..65535);
  #my @numbers = (1..2979);
  my $indice= "FF";
  unlink("data.txt"); #delete  debuglog
  foreach $indice(@numbers) {	
    #my $cmd = sprintf("%02X", $indice);
   # my $cmd = "0A" . sprintf("%04X",  $indice);
    my $cmd = $indice;
    my $cmdHex2 = THZ_encodecommand($cmd,"get");
    #($err, $msg) = THZ_Get_Comunication($hash,  $cmdHex2);
    #STX start of text
    THZ_Write($hash,  "02");
    ($err, $msg) = THZ_ReadAnswer($hash);  
    # send request
    THZ_Write($hash,  $cmdHex2);
    select(undef, undef, undef, 0.01);
    ($err, $msg) = THZ_ReadAnswer($hash);
    # ack datatranfer and read from the heatpump        
    THZ_Write($hash,  "10");
    select(undef, undef, undef, 0.1);
    ($err, $msg) = THZ_ReadAnswer($hash);
    THZ_Write($hash,  "10");
    
    #my $activatetrigger =1;
	#	  readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
	#	  open (MYFILE, '>>data.txt');
	#	  print MYFILE ($cmdHex2 . "-" . $msg . "\n");
	#	  close (MYFILE); 
    
    if (defined($err))  {return ($msg ."\n" . $err);}
    else {   #clean up and remove footer and header
	($err, $msg) = THZ_decode($msg);
	if (defined($err)) {$msg=$cmdHex2 ."-". $msg ."-". $err;} 
		  my $activatetrigger =1;
		 # readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
		  open (MYFILE, '>>data.txt');
		  print MYFILE ($cmd . "-" . $msg . "\n");
		  close (MYFILE); 
    }    
    select(undef, undef, undef, 0.05); #equivalent to sleep 200ms
  }
}

#######################################
#THZ_Attr($) 
#in case of change of attribute starting with interval_ refresh all
########################################################################################

sub THZ_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  if( $attrName =~ /^interval_/ ) {
  #DevIo_CloseDev($hash);
  THZ_RemoveInternalTimer("THZ_GetRefresh");
  #sleep 1;
  #DevIo_OpenDev($hash, 1, "THZ_Refresh_all_gets");
  THZ_Refresh_all_gets($hash);
  }
  return undef;
}



#####################################



sub THZ_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  THZ_RemoveInternalTimer("THZ_GetRefresh");
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $hash->{NAME}, $lev, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  DevIo_CloseDev($hash); 
  return undef;
}


##########################################
# THZ_RemoveInternalTimer($) 
# modified takes as an argument the function to be called, not the argument
########################################################################################
sub THZ_RemoveInternalTimer($)
{
  my ($callingfun) = @_;
  foreach my $a (keys %intAt) {
    delete($intAt{$a}) if($intAt{$a}{FN} eq $callingfun);
  }
}











#####################################
# sub THZ_PrintcurveSVG
# plots heat curve
#define wl_hr weblink htmlCode {THZ_PrintcurveSVG}
# da mettere dentro lo style per funzionare sopra        svg      { height:200px; width:800px;}
#define wl_hr2 weblink htmlCode <div class="SVGplot"><embed src="/fhem/THZ_PrintcurveSVG/" type="image/svg+xml" width="800" height="160" name="wl_7"/></div> <a href="/fhem?detail=wl_hr2">wl_hr2</a><br>
#####################################

sub THZ_PrintcurveSVG {
my $ret =  <<'END';
<?xml version="1.0" encoding="UTF-8"?> <!DOCTYPE svg> <svg width="800" height="163" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" >
<style type="text/css"><![CDATA[
text       { font-family:Times; font-size:12px; }
text.title { font-size:14	px; }
text.copy  { text-decoration:underline; stroke:none; fill:blue;    }
text.paste { text-decoration:underline; stroke:none; fill:blue;    }
polyline { stroke:black; fill:none; }
.border  { stroke:black; fill:url(#gr_bg); }
.vgrid   { stroke:gray;  stroke-dasharray:2,6; }
.hgrid   { stroke:gray;  stroke-dasharray:2,6; }
.pasted  { stroke:black; stroke-dasharray:1,1; }
.l0 { stroke:red;     }  text.l0 { stroke:none; fill:red;     } 
.l1 { stroke:green;   }  text.l1 { stroke:none; fill:green;   }
.l0dot   { stroke:red;   stroke-dasharray:2,4; }  text.ldot { stroke:none; fill:red; } 
]]></style>
<defs>
  <linearGradient id="gr_bg" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" style="stop-color:#FFFFF7; stop-opacity:1"/>
    <stop offset="100%" style="stop-color:#FFFFC7; stop-opacity:1"/>
  </linearGradient>
  <linearGradient id="gr_0" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" style="stop-color:#f00; stop-opacity:.6"/>
    <stop offset="100%" style="stop-color:#f88; stop-opacity:.4"/>
  </linearGradient>
  <linearGradient id="gr_1" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" style="stop-color:#291; stop-opacity:.6"/>
    <stop offset="100%" style="stop-color:#8f7; stop-opacity:.4"/>
  </linearGradient>
  <pattern id="gr0_stripe" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(-45 2 2)">
      <path d="M -1,2 l 6,0" stroke="#f00" stroke-width="0.5"/>
  </pattern>
  <pattern id="gr1_stripe" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(45 2 2)">
      <path d="M -1,2 l 6,0" stroke="green" stroke-width="0.5"/>
  </pattern>
  <linearGradient id="gr0_gyr" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" style="stop-color:#f00; stop-opacity:.6"/>
    <stop offset="50%" style="stop-color:#ff0; stop-opacity:.6"/>
    <stop offset="100%" style="stop-color:#0f0; stop-opacity:.6"/>
  </linearGradient>
</defs>
<rect x="48" y="19.2" width="704" height="121.6" rx="8" ry="8" fill="none" class="border"/>
<text x="12" y="80" text-anchor="middle" class="ylabel" transform="rotate(270,12,80)">HC1 heat SetTemp °C</text>
<text x="399" y="163.2" class="xlabel" text-anchor="middle">outside temperature filtered °C</text>
<text x="44" y="155" class="ylabel" text-anchor="middle">-15</text>
<text x="165" y="155" class="ylabel" text-anchor="middle">-9</text>  <polyline points="165,19.2 165,140.8" class="hgrid"/>
<text x="282" y="155" class="ylabel" text-anchor="middle">-3</text>  <polyline points="282,19.2 282,140.8" class="hgrid"/>
<text x="399" y="155" class="ylabel" text-anchor="middle">3</text>   <polyline points="399,19.2 399,140.8" class="hgrid"/>
<text x="517" y="155" class="ylabel" text-anchor="middle">9</text>   <polyline points="517,19.2 517,140.8" class="hgrid"/>
<text x="634" y="155" class="ylabel" text-anchor="middle">15</text>  <polyline points="634,19.2 634,140.8" class="hgrid"/>
<text x="751" y="155" class="ylabel" text-anchor="middle">21</text>  <polyline points="751,19.2 751,140.8" class="hgrid"/>
<g>
  <polyline points="44,140 49,140"/> <text x="39.2" y="144" class="ylabel" text-anchor="end">10</text>
  <polyline points="44,110 49,110"/> <text x="39.2" y="114" class="ylabel" text-anchor="end">20</text>
  <polyline points="44,80 49,80"/>   <text x="39.2" y="84" class="ylabel" text-anchor="end">30</text>
  <polyline points="44,49 49,49"/>   <text x="39.2" y="53" class="ylabel" text-anchor="end">40</text>
  <polyline points="44,19 49,19"/>   <text x="39.2" y="23" class="ylabel" text-anchor="end">50</text>
</g>
<g>
  <polyline points="751,140 756,140"/> <text x="760.8" y="144" class="ylabel">10</text>
  <polyline points="751,110 756,110"/> <text x="760.8" y="114" class="ylabel">20</text>
  <polyline points="751,80 756,80"/>   <text x="760.8" y="84" class="ylabel">30</text>
  <polyline points="751,49 756,49"/>   <text x="760.8" y="53" class="ylabel">40</text>
  <polyline points="751,19 756,19"/>   <text x="760.8" y="23" class="ylabel">50</text>
</g>
END

my $insideTemp=(split ' ',ReadingsVal("Mythz","sGlobal",14))[81];
$insideTemp="n.a." if ($insideTemp eq "-60"); #in case internal room sensor not connected
my $roomSetTemp =(split ' ',ReadingsVal("Mythz","sHC1",0))[21];
$roomSetTemp ="1" if ($roomSetTemp == 0); #division by 0 is bad
my $p13GradientHC1 = ReadingsVal("Mythz","p13GradientHC1",0.4);
my $heatSetTemp =(split ' ',ReadingsVal("Mythz","sHC1",17))[11];
my $p15RoomInfluenceHC1 = (split ' ',ReadingsVal("Mythz","p15RoomInfluenceHC1",0))[0];
my $outside_tempFiltered =(split ' ',ReadingsVal("Mythz","sGlobal",0))[65];
my $p14LowEndHC1 =(split ' ',ReadingsVal("Mythz","p14LowEndHC1",0))[0];


############willi data
#$insideTemp=24.6;
#$roomSetTemp = 21;
#$p13GradientHC1 = 0.26;
#$heatSetTemp = 21.3;
#$p15RoomInfluenceHC1 = 50;
#$outside_tempFiltered = 13.1;
#$p14LowEndHC1 =1.5;






#labels ######################
$ret .= '<text line_id="line_1" x="70" y="105.2" class="l1"> --- heat curve</text>' ;
$ret .= '<text  line_id="line_0" x="70" y="121.2"  class="l0"> --- working point: outside_tempFiltered=';
$ret .=  $outside_tempFiltered . ' heatSetTemp=' . $heatSetTemp . '</text>';


#title ######################
$ret .= '<text id="svg_title" x="400" y="14.4" class="title" text-anchor="middle">';
$ret .=  'roomSetTemp=' . $roomSetTemp . ' p13GradientHC1=' . $p13GradientHC1 . ' p14LowEndHC1=' . $p14LowEndHC1  .  ' p15RoomInfluenceHC1=' . $p15RoomInfluenceHC1 . " insideTemp=" . $insideTemp .' </text>';

#equation####################
$insideTemp=$roomSetTemp if ($insideTemp eq "n.a."); 
my $a= 1 + ($roomSetTemp * (1 + $p13GradientHC1 * 0.87)) + $p14LowEndHC1 + ($p15RoomInfluenceHC1 * $p13GradientHC1 * ($roomSetTemp - $insideTemp) /10); 
my $b= -14 * $p13GradientHC1 / $roomSetTemp; 
my $c= -1 * $p13GradientHC1 /75;
my $Simul_heatSetTemp; 


#point ######################
$ret .='<polyline id="line_0"   style="stroke-width:2" class="l0" points="';
my ($px,$py) = ((($outside_tempFiltered+15)*(750-49)/(15+21)+49),(($heatSetTemp-50)*(140-19)/(10-50)+19)); 
 $ret.= ($px-3) . "," . ($py)   ." " . ($px)  . "," . ($py-3) ." " . ($px+3) . "," . ($py) ." " . ($px)   . "," . ($py+3)  ." " . ($px-3)   . "," . ($py)  ." " . '"/>';

#curve ######################
$ret .='<polyline id="line_1"  title="Heat Curve" class="l1" points="';
for(my $i = -15; $i < 22; $i++) {
 $Simul_heatSetTemp = $i * $i * $c + $i * $b + $a; 
 $ret.= (($i+15)*(750-49)/(15+21)+49) . "," . (($Simul_heatSetTemp-50)*(140-19)/(10-50)+19) ." ";
}
$ret .= '"/> </svg>';

my $FW_RETTYPE = "image/svg+xml";
return ($FW_RETTYPE, $ret);
#return $ret;
}


#####################################









1;


=pod
=begin html

<a name="THZ"></a>
<h3>THZ</h3>
<ul>
  THZ module: comunicate through serial interface RS232/USB (eg /dev/ttyxx) or through ser2net (e.g 10.0.x.x:5555) with a Tecalor/Stiebel Eltron heatpump. <br>
   Tested on a THZ303/Sol (with serial speed 57600/115200@USB) and a THZ403 (with serial speed 115200) with the same Firmware 4.39. <br>
   Tested on a LWZ404 (with serial speed 115200) with Firmware 5.39. <br>
   Tested on fritzbox, nas-qnap, raspi and macos.<br>
   This module is not working if you have an older firmware; Nevertheless, "parsing" could be easily updated, because now the registers are well described.
  https://answers.launchpad.net/heatpumpmonitor/+question/100347  <br>
   Implemented: read of status parameters and read/write of configuration parameters.
   A complete description can be found in the 00_THZ wiki http://www.fhemwiki.de/wiki/Tecalor_THZ_Heatpump
  <br><br>

  <a name="THZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; THZ &lt;device&gt;</code> <br>
    <br>
    <code>device</code> can take the same parameters (@baudrate, @directio,
    TCP/IP, none) like the <a href="#CULdefine">CUL</a>,  e.g  57600 baud or 115200.<br>
    Example:
    direct connection   
    <ul><code>
      define Mytecalor 			THZ   /dev/ttyUSB0@115200<br>
      </code></ul>
      or network connection (like via ser2net)<br>
      <ul><code>
      define Myremotetecalor  	THZ  192.168.0.244:2323 
    </code></ul>
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      attr Mythz interval_sGlobal 	300      # internal polling interval 5min  <br>
      attr Mythz interval_sHistory 	28800  # internal polling interval 8h    <br>
      attr Mythz interval_sLast10errors 86400 # internal polling interval 24h    <br>
      attr Mythz interval_sSol	 	86400 # internal polling interval 24h    <br>
      attr Mythz interval_sDHW	 	86400 # internal polling interval 24h    <br>
      attr Mythz interval_sHC1	 	86400 # internal polling interval 24h    <br>
      attr Mythz interval_sHC2	 	86400 # internal polling interval 24h    <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
     <br> 
   If the attributes interval_allFB and interval_history are not defined (or 0), their internal polling is disabled.  
   Clearly you can also define the polling interval outside the module with the "at" command.
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      define atMythzFB at +*00:05:00 {fhem "get Mythz sGlobal","1";;return()}    <br>
      define atMythz09 at +*08:00:00 {fhem "get Mythz sHistory","1";;return()}   <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
      
  </ul>
  <br>
</ul>
 
=end html

=begin html_DE

<a name="THZ"></a>
<h3>THZ</h3>
<ul>
  THZ Modul: Kommuniziert mittels einem seriellen Interface RS232/USB (z.B. /dev/ttyxx), oder mittels ser2net (z.B. 10.0.x.x:5555) mit einer Tecalor / Stiebel  
  Eltron W&auml;rmepumpe. <br>
  Getestet mit einer Tecalor THZ303/Sol (Serielle Geschwindigkeit 57600/115200@USB) und einer THZ403 (Serielle Geschwindigkeit 115200) mit identischer 
  Firmware 4.39. <br>
  Getestet mit einer Stiebel LWZ404 (Serielle Geschwindigkeit 115200@USB) mit Firmware 5.39. <br>
  Getestet auf FritzBox, nas-qnap, Raspberry Pi and MacOS.<br>
  Dieses Modul funktioniert nicht mit &aumlterer Firmware; Gleichwohl, das "parsing" k&ouml;nnte leicht angepasst werden da die Register gut 
  beschrieben wurden.
  https://answers.launchpad.net/heatpumpmonitor/+question/100347  <br>
  Implementiert: Lesen der Statusinformation sowie Lesen und Schreiben einzelner Einstellungen.
  Genauere Beschreinung des Modules --> 00_THZ wiki http://www.fhemwiki.de/wiki/Tecalor_THZ_W%C3%A4rmepumpe
  <br><br>

  <a name="THZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; THZ &lt;device&gt;</code> <br>
    <br>
    <code>device</code> kann einige Parameter beinhalten (z.B. @baudrate, @direction,
    TCP/IP, none) wie das <a href="#CULdefine">CUL</a>, z.B. 57600 baud oder 115200.<br>
    Beispiel:<br>
    Direkte Verbindung
    <ul><code>
      define Mytecalor THZ /dev/ttyUSB0@115200<br>
      </code></ul>
      oder vir Netzwerk (via ser2net)<br>
      <ul><code>
      define Myremotetecalor THZ 192.168.0.244:2323 
    </code></ul>
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      attr Mythz interval_sGlobal 	 300            # Internes Polling Intervall 5min   <br>
      attr Mythz interval_sHistory 	 28800        # Internes Polling Intervall 8h     <br>
      attr Mythz interval_sLast10errors	 86400   # Internes Polling Intervall 24h    <br>
      attr Mythz interval_sSol		 86400  # Internes Polling Intervall 24h    <br>
      attr Mythz interval_sDHW		 86400  # Internes Polling Intervall 24h    <br>
      attr Mythz interval_sHC1		 86400  # Internes Polling Intervall 24h    <br>
      attr Mythz interval_sHC2		 86400  # Internes Polling Intervall 24h    <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
     <br> 
   Wenn die Attribute interval_allFB und interval_history nicht definiert sind (oder 0), ist das interne Polling deaktiviert.
   Nat&uuml;rlich kann das Polling auch mit dem "at" Befehl ausserhalb des Moduls definiert werden.
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      define atMythzFB at +*00:05:00 {fhem "get Mythz sGlobal","1";;return()}    <br>
      define atMythz09 at +*08:00:00 {fhem "get Mythz sHistory","1";;return()}   <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
      
  </ul>
  <br>
</ul>
 
=end html_DE


=cut


