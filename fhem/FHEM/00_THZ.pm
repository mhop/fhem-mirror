##############################################
# 00_THZ
# $Id$
# by immi 9/2018
my $thzversion = "0.180";  #   
# this code is based on the hard work of Robert; I just tried to port it
# http://robert.penz.name/heat-pump-lwz/
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
use Blocking;

sub THZ_Read($);
sub THZ_ReadAnswer($);
sub THZ_Ready($);
sub THZ_Write($$);
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
sub THZ_Set($@);
sub function_heatSetTemp($$);
sub THZ_Get($@);

########################################################################################
#
# %parsinghash  - known type of message structure
# 
########################################################################################

my %parsinghash = (
  #msgtype => parsingrule  
  "01pxx206" => [["p37Fanstage1AirflowInlet: ", 4, 4, "hex", 1],    [" p38Fanstage2AirflowInlet: ", 8, 4, "hex", 1],    [" p39Fanstage3AirflowInlet: ", 12, 4, "hex", 1],
              [" p40Fanstage1AirflowOutlet: ", 16, 4, "hex", 1],    [" p41Fanstage2AirflowOutlet: ", 20, 4, "hex", 1],  [" p42Fanstage3AirflowOutlet: ", 24, 4, "hex", 1],
              [" p43UnschedVent3: ", 	       28, 4, "hex", 1],    [" p44UnschedVent2: ", 32, 4, "hex", 1],       		[" p45UnschedVent1: ", 36, 4, "hex", 1],
              [" p46UnschedVent0: ", 	       40, 4, "hex", 1],    [" p75PassiveCooling: ", 44, 4, "hex", 1]
              ],
  "01pxx214" => [["p37Fanstage1AirflowInlet: ", 4, 2, "hex", 1],[" p38Fanstage2AirflowInlet: ", 6, 2, "hex", 1],    [" p39Fanstage3AirflowInlet: ", 8, 2, "hex", 1],
	      [" p40Fanstage1AirflowOutlet: ", 10, 2, "hex", 1],    [" p41Fanstage2AirflowOutlet: ", 12, 2, "hex", 1],	[" p42Fanstage3AirflowOutlet: ", 14, 2, "hex", 1],
	      [" p43UnschedVent3: ", 	    16, 4, "hex", 1],	    [" p44UnschedVent2: ", 20, 4, "hex", 1],			[" p45UnschedVent1: ", 24, 4, "hex", 1],
	      [" p46UnschedVent0: ", 	    28, 4, "hex", 1],	    [" p75PassiveCooling: ", 32, 2, "hex", 1]
	      ],
  "03pxx206" => [["UpTempLimitDefrostEvaporatorEnd: ", 4, 4, "hex", 10],  [" MaxTimeDefrostEvaporator: ", 8, 4, "hex", 1], 	[" LimitTempCondenserElectBoost: ", 12, 4, "hex", 10],
	      [" LimitTempCondenserDefrostTerm: ", 16, 4, "hex", 10],   [" p47CompressorRestartDelay: ", 20, 2, "hex", 1], 	[" p48MainFanSpeed: ", 22, 2, "hex", 1]
 	      ],
  "04pxx206" => [["MaxDefrostDurationAAExchenger: ", 4, 2, "hex", 1],	[" DefrostStartThreshold: ", 6, 4, "hex", 10],		[" VolumeFlowFilterReplacement: ", 10, 4, "hex", 1]
	      ],
  "05pxx206" => [["p13GradientHC1: ", 	4, 4, "hex", 10],	[" p14LowEndHC1: ", 8, 4, "hex", 10],		        [" p15RoomInfluenceHC1: ", 12, 2, "hex", 10],
	      [" p16GradientHC2: ", 	14, 4, "hex", 10],	    [" p17LowEndHC2: ", 18, 4, "hex", 10],		        [" p18RoomInfluenceHC2: ", 22, 2, "hex", 10],
	      [" p19FlowProportionHC1: ", 24, 4, "hex", 1],	    [" p20FlowProportionHC2: ", 28, 4, "hex", 1],	    [" MaxSetHeatFlowTempHC1: ", 32, 4, "hex", 10],
	      [" MinSetHeatFlowTempHC1: ", 36, 4, "hex", 10],	[" MaxSetHeatFlowTempHC2: ", 40, 4, "hex", 10],     [" MinSetHeatFlowTempHC2: ", 44, 4, "hex", 10],
	      ],
  "06pxx206" => [["p21Hyst1: ", 	  4, 2, "hex", 10],	    [" p22Hyst2: ",             6, 2, "hex", 10],	    [" p23Hyst3: ", 8, 2, "hex", 10],
	      [" p24Hyst4: ", 		      10, 2, "hex", 10],    [" p25Hyst5: ",             12, 2, "hex", 10],	    [" p26Hyst6: ", 14, 2, "hex", 10],
	      [" p27Hyst7: ", 		      16, 2, "hex", 10],	[" p28Hyst8: ",             18, 2, "hex", 10],      [" p29HystAsymmetry: ", 20, 2, "hex", 1],
	      [" p30integralComponent: ", 22, 4, "hex", 1],	    [" p31MaxBoostStages: ",    26, 2, "hex", 1],	    [" MaxHeatFlowTemp: ", 28, 4, "hex", 10],
	      [" p49SummerModeTemp: ", 	  32, 4, "hex", 10],	[" p50SummerModeHysteresis: ", 36, 4, "hex", 10],   [" p77OutTempFilterTime: ", 40, 4, "hex", 1],
	      [" p78DualModePoint: ", 	  44, 4, "hex2int", 10],[" p79BoosterTimeoutHC: ",  48, 2, "hex", 1] 	      
          ],
  "07pxx206" => [["p32HystDHW: ", 	    4, 2, "hex", 10],   [" p33BoosterTimeoutDHW: ", 6, 2, "hex", 1],        [" p34TempLimitBoostDHW: ", 8, 4, "hex2int", 10],    	[" p35PasteurisationInterval: ", 12, 2, "hex", 1],
	      [" p36MaxDurationDHWLoad: ", 14, 2, "hex", 1],	[" pasteurisationTemp: ",   16, 4, "hex", 10],      [" maxBoostStagesDHW: ", 20, 2, "hex", 1],
          [" p84EnableDHWBuffer: ",     22, 2, "hex", 1]
	      ],
  "08pxx206" => [["p80EnableSolar: ", 	4, 2, "hex", 1],	[" p81DiffTempSolarLoading: ", 6, 4, "hex", 10],    [" p82DelayCompStartSolar: ", 10, 2, "hex", 1],
	      [" p84DHWTempSolarMode: ", 12, 4, "hex", 10],	    [" HystDiffTempSolar: ", 16, 4, "hex", 10],	        [" CollectLimitTempSolar: ", 20, 4, "hex", 10]
	      ],
  "09his" => [["compressorHeating: ", 	4, 4,  "hex", 1],	[" compressorCooling: ",  8, 4, "hex", 1],
	      [" compressorDHW: ",	    12, 4, "hex", 1],	    [" boosterDHW: ",	16, 4, "hex", 1],
	      [" boosterHeating: ",	    20, 4, "hex", 1]
	      ],
  "09his206" => [["operatingHours1: ", 	4, 4, "hex", 1],	[" operatingHours2: ",  8, 4, "hex", 1],
	      [" heatingHours: ",	    12, 4, "hex", 1],	    [" DHWhours: ",	16, 4, "hex", 1],
	      [" coolingHours: ",	    20, 4, "hex", 1]
	      ],
  "0Apxx206" => [["p54MinPumpCycles: ", 4, 2, "hex", 1],	[" p55MaxPumpCycles: ", 6, 4, "hex", 1],	 [" p56OutTempMaxPumpCycles: ", 10, 4, "hex", 10],
	      [" p57OutTempMinPumpCycles: ", 14, 4, "hex", 10], [" p58SuppressTempCaptPumpStart: ", 18, 4, "hex", 1]
	      ],
  "0Bpxx206" => [["progHC1StartTime: ", 	4, 4, "hex2time", 1], 	[" progHC1EndTime: ", 8, 4, "hex2time", 1],
	      [" progHC1Monday: ", 	    13, 1, "bit0", 1],      [" progHC1Tuesday: ", 	13, 1, "bit1", 1],	
		  [" progHC1Wednesday: ", 	13, 1, "bit2", 1],      [" progHC1Thursday: ", 13, 1, "bit3", 1],
		  [" progHC1Friday: ", 	    12, 1, "bit0", 1],      [" progHC1Saturday: ", 12, 1, "bit1", 1],
		  [" progHC1Sunday: ", 	    12, 1, "bit2", 1],      [" progHC1Enable: ", 	14, 2, "hex", 1],
	      [" progHC2StartTime: ",   16, 4, "hex2time", 1],	[" progHC2EndTime: ", 20, 4, "hex2time", 1],
	      [" progHC2Monday: ", 	    25, 1, "bit0", 1],      [" progHC2Tuesday: ", 	25, 1, "bit1", 1],	
		  [" progHC2Wednesday: ", 	25, 1, "bit2", 1],      [" progHC2Thursday: ", 25, 1, "bit3", 1],
		  [" progHC2Friday: ", 	    24, 1, "bit0", 1],      [" progHC2Saturday: ", 24, 1, "bit1", 1],
		  [" progHC2Sunday: ", 	    24, 1, "bit2", 1],      [" progHC2Enable: ", 26, 2, "hex", 1]
	      ],
  "0Cpxx206" => [["progDHWStartTime: ", 4, 4, "hex2time", 1],	[" progDHWEndTime: ", 8, 4, "hex2time", 1],
	      [" progDHWMonday: ", 	    13, 1, "bit0", 1],  [" progDHWTuesday: ", 	13, 1, "bit1", 1],	
		  [" progDHWWednesday: ", 	13, 1, "bit2", 1],  [" progDHWThursday: ", 13, 1, "bit3", 1],
		  [" progDHWFriday: ", 	    12, 1, "bit0", 1],  [" progDHWSaturday: ", 12, 1, "bit1", 1],
		  [" progDHWSunday: ", 	    12, 1, "bit2", 1],  [" progDHWEnable: ", 	14, 2, "hex", 1],
 	      ],
  "0Dpxx206" => [["progFAN1StartTime: ", 4, 4, "hex2time", 1], 	[" progFAN1EndTime: ", 8, 4, "hex2time", 1],
	      [" progFAN1Monday: ", 	13, 1, "bit0", 1], [" progFAN1Tuesday: ", 	13, 1, "bit1", 1],	
		  [" progFAN1Wednesday: ", 	13, 1, "bit2", 1], [" progFAN1Thursday: ", 13, 1, "bit3", 1],
		  [" progFAN1Friday: ", 	12, 1, "bit0", 1], [" progFAN1Saturday: ", 12, 1, "bit1", 1],
		  [" progFAN1Sunday: ", 	12, 1, "bit2", 1], [" progFAN1Enable: ", 	14, 2, "hex", 1],
	      [" progFAN2StartTime: ", 16, 4, "hex2time", 1],	[" progFAN2EndTime: ", 20, 4, "hex2time", 1],
	      [" progFAN2Monday: ", 	25, 1, "bit0", 1], [" progFAN2Tuesday: ", 	25, 1, "bit1", 1],	
		  [" progFAN2Wednesday: ", 	25, 1, "bit2", 1], [" progFAN2Thursday: ", 25, 1, "bit3", 1],
		  [" progFAN2Friday: ", 	24, 1, "bit0", 1], [" progFAN2Saturday: ", 24, 1, "bit1", 1],
		  [" progFAN2Sunday: ", 	24, 1, "bit2", 1], [" progFAN2Enable: ", 26, 2, "hex", 1]
 	      ],  
  "0Epxx206" => [["p59RestartBeforeSetbackEnd: ", 4, 4, "hex", 1]
	      ], 
  "0Fpxx206" => [["pA0DurationUntilAbsenceStart: ", 4, 4, "hex", 10], [" pA0AbsenceDuration: ", 8, 4, "hex", 10], [" pA0EnableAbsenceProg: ", 12, 2, "hex", 1]
	      ], 	 
  "10pxx206" => [["p70StartDryHeat: ", 	4, 2, "hex", 1],	[" p71BaseTemp: ", 6, 4, "hex", 10],	[" p72PeakTemp: ", 10, 4, "hex", 10],
	      [" p73TempDuration: ", 	14, 4, "hex", 1],	    [" p74TempIncrease: ", 18, 4, "hex", 10]
	      ],
  "16sol" => [["collectorTemp: ",	4, 4, "hex2int", 10],	[" dhwTemp: ", 	8, 4, "hex2int", 10],
	      [" flowTemp: ",		    12, 4, "hex2int", 10],	[" edSolPump: ",	16, 2, "hex2int", 1],
	      [" out: ",		        26, 4, "raw", 1],       [" status: ",		30, 2, "raw", 1]
	      ],
  "17pxx206" => [["p01RoomTempDay: ", 	4, 4,  "hex",  10],	[" p02RoomTempNight: ",		8,  4, "hex", 10],
	      [" p03RoomTempStandby: ",	12, 4,  "hex", 10], 	[" p04DHWsetTempDay: ",		16, 4,  "hex", 10], 
	      [" p05DHWsetTempNight: ",	20, 4,  "hex", 10], 	[" p06DHWsetTempStandby: ",	24, 4,  "hex", 10], 
	      [" p07FanStageDay: ",	    28, 2,  "hex", 1], 	    [" p08FanStageNight: ",		30, 2,  "hex", 1],
	      [" p09FanStageStandby: ",	32, 2,  "hex", 1], 	    [" p10HCTempManual: ",	34, 4,  "hex", 10],
	      [" p11DHWsetTempManual: ", 38, 4,  "hex", 10],  	[" p12FanStageManual: ",	42, 2,  "hex", 1],
	      ],
  "D1last" => [["number_of_faults: ",	4, 2, "hex", 1],	
	      [" fault0CODE: ",		8, 2,  "faultmap", 1],	[" fault0TIME: ",	12, 4, "turnhex2time", 1],  [" fault0DATE: ",	16, 4, "turnhexdate", 1],
	      [" fault1CODE: ",		20, 2, "faultmap", 1],	[" fault1TIME: ",	24, 4, "turnhex2time", 1],  [" fault1DATE: ",	28, 4, "turnhexdate", 1],
	      [" fault2CODE: ",		32, 2, "faultmap", 1],	[" fault2TIME: ",	36, 4, "turnhex2time", 1],  [" fault2DATE: ",	40, 4, "turnhexdate", 1],
	      [" fault3CODE: ",		44, 2, "faultmap", 1],	[" fault3TIME: ",	48, 4, "turnhex2time", 1],  [" fault3DATE: ",	52, 4, "turnhexdate", 1]
	      ],
  "D1last206" => [["number_of_faults: ",	4, 2, "hex", 1],	
	      [" fault0CODE: ",		8, 4,  "faultmap", 1],	[" fault0TIME: ",	12, 4, "hex2time", 1],  [" fault0DATE: ",	16, 4, "hexdate", 1],
	      [" fault1CODE: ",		20, 4, "faultmap", 1],	[" fault1TIME: ",	24, 4, "hex2time", 1],  [" fault1DATE: ",	28, 4, "hexdate", 1],
	      [" fault2CODE: ",		32, 4, "faultmap", 1],	[" fault2TIME: ",	36, 4, "hex2time", 1],  [" fault2DATE: ",	40, 4, "hexdate", 1],
	      [" fault3CODE: ",		44, 4, "faultmap", 1],	[" fault3TIME: ",	48, 4, "hex2time", 1],  [" fault3DATE: ",	52, 4, "hexdate", 1]
	      ],
  "E8fan"	=> [[" inputFanSpeed: ",        58, 2, "hex", 1],    # like in sGlobal
            [" outputFanSpeed: ",           60, 2, "hex", 1],    # like in sGlobal
			[" pFanstageXAirflowInlet: ",   62, 4, "hex", 1],    # m3/h  corresponding to p37Fanstage1AirflowInlet or p38Fanstage2AirflowInlet
			[" pFanstageXAirflowOutlet: ",  66, 4, "hex", 1],    # m3/h corresponding to p40Fanstage1AirflowOutlet or p41Fanstage2AirflowOutlet
			[" inputFanPower: ",            70, 2, "hex", 1],    # like in sGlobal
			[" outputFanPower: ",           72, 2, "hex", 1],	 # like in sGlobal		
		  ],
  "E8fan206" => [["statusAFC: ",         4, 4, "hex", 1], 	    # 0=init air flow calibration (16:00) 4=normal fan operation
            [" supplyFanSpeedCAL: ",    8, 4, "hex", 60], 	    # calibration speed
			[" exhaustFanSpeedCAL: ",   12, 4, "hex", 60], 		
			[" supplyFanAirflowCAL: ",  16, 4, "hex", 100], 	# calibration air flow volume
			[" exhaustFanAirflowCAL: ", 20, 4, "hex", 100],
			[" supplyFanSpeed: ",       24, 4, "hex", 1], 		# actual fan speed in 1/s
			[" exhaustFanSpeed: ",      28, 4, "hex", 1],
			[" supplyFanAirflowSet: ",  32, 4, "hex", 1],		# actual air flow volume setting in m3/h
			[" exhaustFanAirflowSet: ", 36, 4, "hex", 1],
			[" supplyFanSpeedTarget: ", 40, 4, "hex", 1],		# target fan speed in %
			[" exhaustFanSpeedTarget: ", 44, 4, "hex", 1],
			[" supplyFanSpeed0: ",      48, 4, "hex", 10], 			
			[" exhaustFanSpeed0: ",     52, 4, "hex", 10], 	
			[" supplyFanSpeed200: ",    56, 4, "hex", 10],
			[" exhaustFanSpeed200: ",   60, 4, "hex", 10],
			[" airflowTolerance: ",     64, 2, "hex", 1],
			[" airflowCalibrationInterval: ", 66, 2, "hex", 1],	# calibration interval
			[" timeToCalibration: ",    68, 2, "hex", 1]		# days to next calibration
		  ],
  "EEprg206" => [["opMode: ", 	4, 2, 	"opmode2", 1], 	[" ProgStateHC: ", 	10, 2, "opmodehc", 1], 	[" ProgStateDHW: ", 	12, 2, "opmodehc", 1],
	      [" ProgStateFAN: ", 	14, 2, 	"opmodehc", 1], [" BaseTimeAP0: ", 	16, 8, "hex", 1], 	    [" StatusAP0: ", 	24, 2, "hex", 1],
	      [" StartTimeAP0: ", 	26, 8, 	"hex", 1], 	    [" EndTimeAP0: ", 	34, 8, "hex", 1]
	      ],
  "F2ctrl"  => [["heatRequest: ", 		4, 2, "hex", 1],	    # 0=DHW 2=heat 5=off 6=defrostEva
			[" heatRequest2: ", 		6, 2, "hex", 1],		# same as heatRequest
			[" hcStage: ", 				8, 2, "hex", 1],  		# 0=off 1=solar 2=heatPump 3=boost1 4=boost2 5=boost3
			[" dhwStage: ",				10, 2, "hex", 1],		# 0=off, 1=solar, 2=heatPump 3=boostMax
			[" heatStageControlModul: ", 12, 2, "hex", 1], 		# either hcStage or dhwStage depending from heatRequest
			[" compBlockTime: ", 		14, 4, "hex2int", 1],	# remaining compressor block time
			[" pasteurisationMode: ", 	18, 2, "hex", 1], 		# 0=off 1=on
			[" defrostEvaporator: ", 	20, 2, "raw", 1],		# 10=off 30=defrostEva
			[" boosterStage2: ",		22, 1, 	"bit3", 1],		# booster 2		
			[" solarPump: ",			22, 1, 	"bit2", 1],		# solar pump
			[" boosterStage1: ",		22, 1, 	"bit1", 1],		# booster 1
			[" compressor: ",			22, 1, 	"bit0", 1],	    # compressor
			[" heatPipeValve: ",		23, 1, 	"bit3", 1],		# heat pipe valve
			[" diverterValve: ",		23, 1, 	"bit2", 1],		# diverter valve
			[" dhwPump: ",				23, 1, 	"bit1", 1],	    # dhw pump
			[" heatingCircuitPump: ",	23, 1, 	"bit0", 1],		# hc pump
			[" mixerOpen: ",			25, 1, 	"bit1", 1],		# mixer open
			[" mixerClosed: ",			25, 1, 	"bit0", 1],	    # mixer closed
			[" sensorBits1: ", 			26, 2, "raw", 1],		# sensor condenser temperature ??
			[" sensorBits2: ", 			28, 2, "raw", 1],		# sensor low pressure ??
			[" boostBlockTimeAfterPumpStart: ", 30, 4, "hex2int", 1],	# after each  pump start (dhw or heat circuit)
			[" boostBlockTimeAfterHD: ", 34, 4, "hex2int", 1]	# ??
          ],
  "F3dhw"  => [["dhwTemp: ",	4, 4, "hex2int", 10],	[" outsideTemp: ", 	    8, 4, "hex2int", 10],
	      [" dhwSetTemp: ",	    12, 4, "hex2int", 10],  [" compBlockTime: ",	16, 4, "hex2int", 1],
	      [" out: ", 		    20, 4, "raw", 1],	    [" heatBlockTime: ", 	24, 4, "hex2int", 1],
	      [" dhwBoosterStage: ",	28, 2, "hex", 1],	[" pasteurisationMode: ", 32, 2, "hex", 1],
	      [" dhwOpMode: ",		34, 2, "opmodehc", 1],	[" x36: ",		        36, 4, "raw", 1]
  	      ],
  "F4hc1"  => [["outsideTemp: ", 4, 4, "hex2int", 10],	    [" x08: ",	 	    8, 4, "hex2int", 10],
	      [" returnTemp: ",		12, 4, "hex2int", 10],      [" integralHeat: ",	16, 4, "hex2int", 1],
	      [" flowTemp: ",		20, 4, "hex2int", 10],	    [" heatSetTemp: ", 	24, 4, "hex2int", 10], 
	      [" heatTemp: ",		28, 4, "hex2int", 10],  
	      [" seasonMode: ",		38, 2, "somwinmode", 1],   			#[" x40: ",		40, 4, "hex2int", 1],
	      [" integralSwitch: ",	44, 4, "hex2int", 1],	    [" hcOpMode: ",		48, 2, "opmodehc", 1],
          #[" x52: ",		52, 4, "hex2int", 1],
	      [" roomSetTemp: ",	56, 4, "hex2int", 10],      [" x60: ", 		    60, 4, "hex2int", 10],
	      [" x64: ", 		    64, 4, "hex2int", 10],      [" insideTempRC: ", 68, 4, "hex2int", 10],
	      [" x72: ", 		    72, 4, "hex2int", 10],      [" x76: ", 		    76, 4, "hex2int", 10],
	      [" onHysteresisNo: ", 32, 2, "hex", 1],	        [" offHysteresisNo: ", 34, 2, "hex", 1],
	      [" hcBoosterStage: ",	36, 2, "hex", 1]
         ],
  "F4hc1214" => [["outsideTemp: ",  4, 4, "hex2int", 10],   [" x08: ",		    8, 4, "raw", 1],
 	      [" returnTemp: ",		    12, 4, "hex2int", 10],  [" integralHeat: ",	16, 4, "hex2int", 1],
	      [" flowTemp: ",		    20, 4, "hex2int", 10],	[" heatSetTemp: ", 	24, 4, "hex2int", 10], 
	      [" heatTemp: ",		    28, 4, "hex2int", 10],  
	      [" seasonMode: ",		    38, 2, "somwinmode", 1],
	      [" integralSwitch: ",	    44, 4, "hex2int", 1],	[" hcOpMode: ",		48, 2, "opmodehc", 1], 	      
          [" roomSetTemp: ",	    62, 4, "hex2int", 10],  [" x60: ", 		    60, 4, "hex2int", 10],
	      [" x64: ", 		        64, 4, "raw", 1],       [" insideTempRC: ", 68, 4, "hex2int", 10],
	      [" x72: ", 		        72, 4, "raw", 1],       [" x76: ", 		    76, 4, "raw", 1],
          [" onHysteresisNo: ", 	32, 2, "hex", 1],	    [" offHysteresisNo: ", 34, 2, "hex", 1],
          [" hcBoosterStage: ",	    36, 2, "hex", 1]
         ],
  "F5hc2"  => [["outsideTemp: ",     4, 4, "hex2int", 10],	[" returnTemp: ",	8, 4, "hex2int", 10],
	      [" vorlaufTemp: ",	    12, 4, "hex2int", 10],  [" heatSetTemp: ",	16, 4, "hex2int", 10],
	      [" heatTemp: ", 		    20, 4, "hex2int", 10],	[" stellgroesse: ",	24, 4, "hex2int", 10], 
	      [" seasonMode: ",		    30, 2, "somwinmode",1],	[" hcOpMode: ",		36, 2, "opmodehc", 1] 
         ],
  "F6sys206" => [["userSetFanStage: ", 30, 2, "hex", 1],	[" userSetFanRemainingTime: ", 36, 4, "hex", 1],
	      [" lastErrors: ",	        4, 8, "hex2error", 1],	     
         ],
  "FBglob" => [["outsideTemp: ",    8, 4, "hex2int", 10],	[" flowTemp: ",		        12, 4, "hex2int", 10],
	      [" returnTemp: ",		    16, 4, "hex2int", 10],	[" hotGasTemp: ", 	        20, 4, "hex2int", 10],
	      [" dhwTemp: ",	 	    24, 4, "hex2int", 10], 	[" flowTempHC2: ",	        28, 4, "hex2int", 10],
	      [" evaporatorTemp: ",	    36, 4, "hex2int", 10],  [" condenserTemp: ",	    40, 4, "hex2int", 10],
	      [" mixerOpen: ",		    45, 1, "bit0", 1],  	[" mixerClosed: ",		    45, 1, "bit1", 1],
	      [" heatPipeValve: ",	    45, 1, "bit2", 1],  	[" diverterValve: ",	    45, 1, "bit3", 1],
	      [" dhwPump: ",		    44, 1, "bit0", 1],  	[" heatingCircuitPump: ",	44, 1, "bit1", 1],
	      [" solarPump: ",		    44, 1, "bit3", 1],  	[" compressor: ",		    47, 1, "bit3", 1],
	      [" boosterStage3: ",	    46, 1, "bit0", 1],  	[" boosterStage2: ",		46, 1, "bit1", 1],
	      [" boosterStage1: ",	    46, 1, "bit2", 1],  	[" highPressureSensor: ",	49, 1, "nbit0", 1],
	      [" lowPressureSensor: ",	49, 1, "nbit1", 1], 	[" evaporatorIceMonitor: ",	49, 1, "bit2", 1],
	      [" signalAnode: ",	    49, 1, "bit3", 1],  	[" evuRelease: ",		    48, 1, "bit0", 1],
	      [" ovenFireplace: ",	    48, 1, "bit1", 1],  	[" STB: ",			        48, 1, "bit2", 1],
	      [" outputVentilatorPower: ",50, 4, "hex", 10],  	[" inputVentilatorPower: ",	54, 4, "hex", 10],	[" mainVentilatorPower: ",	58, 4, "hex", 10],
	      [" outputVentilatorSpeed: ",62, 4, "hex", 1],	    [" inputVentilatorSpeed: ",	66, 4, "hex", 1],  	[" mainVentilatorSpeed: ",	70, 4, "hex", 1],
	      [" outside_tempFiltered: ",74, 4, "hex2int", 10],	[" relHumidity: ",		    78, 4, "hex2int", 10],
	      [" dewPoint: ",		    82, 4, "hex2int", 10],
	      [" P_Nd: ",		        86, 4, "hex2int", 100],	[" P_Hd: ",			        90, 4, "hex2int", 100],
	      [" actualPower_Qc: ",	    94, 8, "esp_mant", 1],	[" actualPower_Pel: ",		102, 8, "esp_mant", 1],
	      [" collectorTemp: ",	    4,  4, "hex2int", 10],	[" insideTemp: ",		    32, 4, "hex2int", 10], 
	      [" windowOpen: ",	        47, 1, "bit2", 1], # board X18-1 clamp X4-FA (FensterAuf): window open - signal out 230V
		  [" quickAirVent: ",	    48, 1, "bit3", 1], # board X15-8 clamp X4-SL (SchnellLüftung): quickAirVent - signal in 230V
		  [" flowRate: ",	        110, 4, "hex", 10], # board X51 sensor P5 (on newer models B1 flow temp as well)
		  [" p_HCw: ",		        114, 4, "hex", 100],# board X4-1..3 sensor P4 HC water pressure
		  [" humidityAirOut: ",	    154, 4, "hex", 100] # board X4-4..6 sensor B15
          ],
  "FBglob214" => [["outsideTemp: ", 8, 4, "hex2int", 10],	[" flowTemp: ",		        12, 4, "hex2int", 10],
	      [" returnTemp: ",		    16, 4, "hex2int", 10],  [" hotGasTemp: ", 	        20, 4, "hex2int", 10],
	      [" dhwTemp: ",	 	    24, 4, "hex2int", 10],  [" flowTempHC2: ",	        28, 4, "hex2int", 10],
	      [" evaporatorTemp: ",	    36, 4, "hex2int", 10],  [" condenserTemp: ",	    40, 4, "hex2int", 10],
	      [" mixerOpen: ",		    47, 1, "bit1", 1],      [" mixerClosed: ",		    47, 1, "bit0", 1],
	      [" heatPipeValve: ",	    45, 1, "bit3", 1],      [" diverterValve: ",		45, 1, "bit2", 1],
	      [" dhwPump: ",		    45, 1, "bit1", 1],      [" heatingCircuitPump: ",	45, 1, "bit0", 1],
	      [" solarPump: ",		    44, 1, "bit2", 1],      [" compressor: ",		    44, 1, "bit0", 1],
          [" boosterStage2: ",	    44, 1, "bit3", 1],      [" boosterStage3: ",		44, 1, "n.a.", 1],
	      [" boosterStage1: ",	    44, 1, "bit1", 1],      [" highPressureSensor: ",	54, 1, "bit3", 1],
	      [" lowPressureSensor: ",	54, 1, "bit2", 1],      [" evaporatorIceMonitor: ",	55, 1, "bit3", 1],
	      [" signalAnode: ",	    54, 1, "bit1", 1],      [" evuRelease: ",		    48, 1, "n.a.", 1],
	      [" ovenFireplace: ",	    54, 1, "bit0", 1],      [" STB: ",			        48, 1, "n.a.", 1],
	      [" outputVentilatorPower: ",48, 2, "hex", 1],  	[" inputVentilatorPower: ",	50, 2, "hex", 1],	[" mainVentilatorPower: ",	52, 2, "hex", 255/100],         
          [" outputVentilatorSpeed: ",56, 2, "hex", 1],	    [" inputVentilatorSpeed: ",	58, 2, "hex", 1],  	[" mainVentilatorSpeed: ",	60, 2, "hex", 1],
          [" outsideTempFiltered: ",64, 4, "hex2int", 10],	[" relHumidity: ",		    70, 4, "n.a.", 1],
          [" dewPoint: ",		    5, 4, "n.a.", 1],
	      [" P_Nd: ",		        5, 4, "n.a.", 1],	    [" P_Hd: ",			        5, 4, "n.a.", 1],
	      [" actualPower_Qc: ",	    5, 8, "n.a.", 1],	    [" actualPower_Pel: ",		5, 8, "n.a.", 1],
	      [" collectorTemp: ",	    4,  4, "hex2int", 10],	[" insideTemp: ",		    32, 4, "hex2int", 10]
	      ],
  "FBglob206" => [["outsideTemp: ", 8, 4, "hex2int", 10],	[" flowTemp: ",		        12, 4, "hex2int", 10],
	      [" returnTemp: ",		    16, 4, "hex2int", 10],  [" hotGasTemp: ", 	        20, 4, "hex2int", 10],
	      [" dhwTemp: ",		    24, 4, "hex2int", 10],  [" flowTempHC2: ",	        28, 4, "hex2int", 10],
	      [" evaporatorTemp: ",	    36, 4, "hex2int", 10],  [" condenserTemp: ",	    40, 4, "hex2int", 10],
	      [" mixerOpen: ",		    47, 1, "bit1", 1],      [" mixerClosed: ",		    47, 1, "bit0", 1],
	      [" heatPipeValve: ",	    45, 1, "bit3", 1],      [" diverterValve: ",		45, 1, "bit2", 1],
	      [" dhwPump: ",		    45, 1, "bit1", 1],      [" heatingCircuitPump: ",	45, 1, "bit0", 1],
	      [" solarPump: ",		    44, 1, "n.a", 1],      	[" compressor: ",		    44, 1, "bit0", 1],
	      [" boosterStage3: ",	    44, 1, "bit3", 1],      [" boosterStage2: ",		44, 1, "bit2", 1], 	      
          [" boosterStage1: ",	    44, 1, "bit1", 1],      [" highPressureSensor: ",	54, 1, "bit3", 1],
	      [" lowPressureSensor: ",	54, 1, "bit2", 1],      [" evaporatorIceMonitor: ",	55, 1, "bit3", 1],
	      [" signalAnode: ",	    54, 1, "bit1", 1],      [" evuRelease: ",		    48, 1, "n.a.", 1],
	      [" ovenFireplace: ",	    54, 1, "bit0", 1],      [" STB: ",			        48, 1, "n.a.", 1],
	      [" outputVentilatorPower: ",48, 2, "hex", 1],  	[" inputVentilatorPower: ",	50, 2, "hex", 1],	[" mainVentilatorPower: ",	52, 2, "hex", 255/100],          
          [" outputVentilatorSpeed: ",56, 2, "hex", 1],	    [" inputVentilatorSpeed: ",	58, 2, "hex", 1],  	[" mainVentilatorSpeed: ",	60, 2, "hex", 1],
          [" outsideTempFiltered: ",64, 4, "hex2int", 10],	[" relHumidity: ",		    70, 4, "n.a.", 1],
          [" dewPoint: ",		    5, 4, "n.a.", 1],
	      [" P_Nd: ",		        5, 4, "n.a.", 1],	    [" P_Hd: ",			        5, 4, "n.a.", 1],
	      [" actualPower_Qc: ",	    5, 8, "n.a.", 1],	    [" actualPower_Pel: ",		5, 8, "n.a.", 1],
	      [" collectorTemp: ",	    4,  4, "hex2int", 10],	[" insideTemp: ",		    32, 4, "hex2int", 10] 
	      ],
  "FCtime" => [["Weekday: ",        5, 1,  "weekday", 1],   [" Hour: ",	                6, 2, "hex", 1],
	      [" Min: ",		        8, 2,  "hex", 1], 	    [" Sec: ",	                10, 2, "hex", 1],
	      [" Date: ", 		        12, 2, "year", 1],	    ["/", 		                14, 2, "hex", 1],
	      ["/", 			        16, 2, "hex", 1]
	     ],
  "FCtime206" => [["Weekday: ",     7, 1,  "weekday", 1],  	[" pClockHour: ",           8, 2, "hex", 1],
	      [" pClockMinutes: ",      10, 2,  "hex", 1],  	[" Sec: ",                  12, 2, "hex", 1],
	      [" pClockYear: ",         14, 2, "hex", 1],       [" pClockMonth: ",          18, 2, "hex", 1],
	      [" pClockDay: ",          20, 2, "hex", 1]
        ],
  "FDfirm" => [["version: ", 	4, 4, "hexdate", 1]
	     ],
  "FEfirmId" => [[" HW: ",	30,  2, "hex", 1], 		        [" SW: ",	32,  4, "swver", 1],
		 [" Date: ", 	36, 22, "hex2ascii", 1]
	     ],
  "0A0176Dis" => [[" switchingProg: ",	11, 1, "bit0", 1],  [" compressor: ",	11, 1, "bit1", 1],
	      [" heatingHC: ",		        11, 1, "bit2", 1],  [" heatingDHW: ",	10, 1, "bit0", 1],
	      [" boosterHC: ",		        10, 1, "bit1", 1],  [" filterBoth: ",	 9, 1, "bit0", 1],
	      [" ventStage: ",		         9, 1, "bit1", 1],  [" pumpHC: ",		 9, 1, "bit2", 1],
	      [" defrost: ",		         9, 1, "bit3", 1],  [" filterUp: ",		 8, 1, "bit0", 1],
	      [" filterDown: ",	             8, 1, "bit1", 1],  [" cooling: ",      11, 1, "bit3", 1],
          [" service: ", 10, 1, "bit2", 1]
	      ],
  "0clean"    => [["", 8, 2, "hex", 1]             
              ],
  "1clean"    => [["", 8, 4, "hex", 1]             
              ],
  "2opmode"   => [["", 8, 2, "opmode", 1]             
              ],
  "4temp"     => [["", 8, 4, "hex2int",2560]             
	      ],
  "5temp"     => [["", 8, 4, "hex2int",10]             
	      ],
  "6gradient" => [["", 8, 4, "hex", 100]             
              ],
  "7prog"     => [["", 8, 2, "quater", 1], 			["--", 10, 2, "quater", 1]
              ],
  "8party"    => [["", 10, 2, "quater", 1],			["--", 8, 2, "quater", 1]
              ],
  "9holy"     => [["", 10, 2, "quater", 1]
              ]
);


########################################################################################
#
# %sets - all supported protocols are listed  59E
# 
########################################################################################

my %sets439technician =(
#  "zResetLast10errors"			=> {cmd2=>"D1",     argMin =>   "0", argMax =>  "0",	type =>"0clean",  unit =>""},
#  "zPassiveCoolingtrigger"	=> {cmd2=>"0A0597", argMin =>   "0", argMax =>  "50",	type =>"1clean",  unit =>""},
  "zPumpHC"				=> {cmd2=>"0A0052", argMin =>   "0", argMax =>  "1",	type =>"0clean",  unit =>""},  
  "zPumpDHW"				=> {cmd2=>"0A0056", argMin =>   "0", argMax =>  "1",	type =>"0clean",  unit =>""}
 );



my %sets439539common = (
  "pOpMode"				        => {cmd2=>"0A0112", type   =>  "2opmode"},  # 1 Standby bereitschaft; 11 in Automatic; 3 DAYmode; SetbackMode; DHWmode; Manual; Emergency 
  "p01RoomTempDayHC1"			=> {cmd2=>"0B0005", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p02RoomTempNightHC1"			=> {cmd2=>"0B0008", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p03RoomTempStandbyHC1"		=> {cmd2=>"0B013D", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p01RoomTempDayHC1SummerMode"		=> {cmd2=>"0B0569", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p02RoomTempNightHC1SummerMode"	=> {cmd2=>"0B056B", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p03RoomTempStandbyHC1SummerMode"	=> {cmd2=>"0B056A", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p13GradientHC1"			    => {cmd2=>"0B010E", argMin => "0.1", argMax =>    "5", 	type =>"6gradient",  unit =>""}, # 0..5 rappresentato/100
  "p14LowEndHC1"			    => {cmd2=>"0B059E", argMin =>   "0", argMax =>   "10", 	type =>"5temp",  unit =>" K"},   #in °K 0..20°K rappresentato/10
  "p15RoomInfluenceHC1"			=> {cmd2=>"0B010F", argMin =>   "0", argMax =>  "100",	type =>"0clean", unit =>" %"},
  "p19FlowProportionHC1"		=> {cmd2=>"0B059D", argMin =>   "0", argMax =>  "100",	type =>"1clean", unit =>" %"}, #in % 0..100%
  "p01RoomTempDayHC2"			=> {cmd2=>"0C0005", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p02RoomTempNightHC2"			=> {cmd2=>"0C0008", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p03RoomTempStandbyHC2"		=> {cmd2=>"0C013D", argMin =>  "12", argMax =>   "28", 	type =>"5temp",  unit =>" °C"},
  "p01RoomTempDayHC2SummerMode"		=> {cmd2=>"0C0569", argMin =>  "12", argMax =>   "28",	type =>"5temp",  unit =>" °C"},
  "p02RoomTempNightHC2SummerMode"	=> {cmd2=>"0C056B", argMin =>  "12", argMax =>   "28",	type =>"5temp",  unit =>" °C"},
  "p03RoomTempStandbyHC2SummerMode"	=> {cmd2=>"0C056A", argMin =>  "12", argMax =>   "28",	type =>"5temp",  unit =>" °C"},
  "p16GradientHC2"		    	=> {cmd2=>"0C010E", argMin => "0.1", argMax =>    "5",	type =>"6gradient",  unit =>""}, # /100
  "p17LowEndHC2"		    	=> {cmd2=>"0C059E", argMin =>   "0", argMax =>   "10", 	type =>"5temp",  unit =>" K"},
  "p18RoomInfluenceHC2"			=> {cmd2=>"0C010F", argMin =>   "0", argMax =>  "100",	type =>"0clean", unit =>" %"}, 
  "p04DHWsetDayTemp"			=> {cmd2=>"0A0013", argMin =>  "10", argMax =>   "55",	type =>"5temp",  unit =>" °C"},
  "p05DHWsetNightTemp"			=> {cmd2=>"0A05BF", argMin =>  "10", argMax =>   "55",	type =>"5temp",  unit =>" °C"},
  "p83DHWsetSolarTemp"			=> {cmd2=>"0A05BE", argMin =>  "10", argMax =>   "75",	type =>"5temp",  unit =>" °C"},
  "p06DHWsetStandbyTemp"		=> {cmd2=>"0A0581", argMin =>  "10", argMax =>   "55",	type =>"5temp",  unit =>" °C"},
  "p11DHWsetManualTemp"			=> {cmd2=>"0A0580", argMin =>  "10", argMax =>   "55",	type =>"5temp",  unit =>" °C"},
  "p36DHWMaxTime"		    	=> {cmd2=>"0A0180", argMin =>  "6", argMax =>   "12",	type =>"1clean",  unit =>""},
  "p07FanStageDay"		    	=> {cmd2=>"0A056C", argMin =>   "0", argMax =>    "3",	type =>"1clean",  unit =>""},
  "p08FanStageNight"			=> {cmd2=>"0A056D", argMin =>   "0", argMax =>    "3",	type =>"1clean",  unit =>""},
  "p09FanStageStandby"			=> {cmd2=>"0A056F", argMin =>   "0", argMax =>    "3",	type =>"1clean",  unit =>""},
  "p99FanStageParty"			=> {cmd2=>"0A0570", argMin =>   "0", argMax =>    "3",	type =>"1clean",  unit =>""},
  "p21Hyst1"			    	=> {cmd2=>"0A05C0", argMin =>   "0", argMax =>   "10", 	type =>"5temp",  unit =>" K"},
  "p22Hyst2"			    	=> {cmd2=>"0A05C1", argMin =>   "0", argMax =>   "10", 	type =>"5temp",  unit =>" K"},
  "p23Hyst3"			    	=> {cmd2=>"0A05C2", argMin =>   "0", argMax =>    "5", 	type =>"5temp",  unit =>" K"},
  "p24Hyst4"			    	=> {cmd2=>"0A05C3", argMin =>   "0", argMax =>    "5", 	type =>"5temp",  unit =>" K"},
  "p25Hyst5"			    	=> {cmd2=>"0A05C4", argMin =>   "0", argMax =>    "5", 	type =>"5temp",  unit =>" K"},
  "p29HystAsymmetry"			=> {cmd2=>"0A05C5", argMin =>   "1", argMax =>    "5",	type =>"1clean",  unit =>""}, 
  "p30integralComponent"		=> {cmd2=>"0A0162", argMin =>  "10", argMax =>  "999",	type =>"1clean",  unit =>" Kmin"}, 
  "p32HystDHW"			    	=> {cmd2=>"0A0140", argMin =>   "0", argMax =>   "10", 	type =>"5temp",  unit =>" K"},
  "p33BoosterTimeoutDHW"		=> {cmd2=>"0A0588", argMin =>   "0", argMax =>  "200",	type =>"1clean",  unit =>" min"}, #during DHW heating
  "p79BoosterTimeoutHC"			=> {cmd2=>"0A05A0", argMin =>   "0", argMax =>   "60",	type =>"1clean",  unit =>" min"}, #delayed enabling of booster heater
  "p46UnschedVent0"			    => {cmd2=>"0A0571", argMin =>   "0", argMax =>  "1000",	type =>"1clean",  unit =>" min"},	 #in min
  "p45UnschedVent1"		    	=> {cmd2=>"0A0572", argMin =>   "0", argMax =>  "1000",	type =>"1clean",  unit =>" min"},	 #in min
  "p44UnschedVent2"		    	=> {cmd2=>"0A0573", argMin =>   "0", argMax =>  "1000",	type =>"1clean",  unit =>" min"},	 #in min
  "p43UnschedVent3"		    	=> {cmd2=>"0A0574", argMin =>   "0", argMax =>  "1000",	type =>"1clean",  unit =>" min"},	 #in min
  "p37Fanstage1AirflowInlet"	=> {cmd2=>"0A0576", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#zuluft 
  "p38Fanstage2AirflowInlet"	=> {cmd2=>"0A0577", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#zuluft 
  "p39Fanstage3AirflowInlet"	=> {cmd2=>"0A0578", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#zuluft 
  "p40Fanstage1AirflowOutlet"	=> {cmd2=>"0A0579", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#abluft extrated
  "p41Fanstage2AirflowOutlet"	=> {cmd2=>"0A057A", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#abluft extrated
  "p42Fanstage3AirflowOutlet"	=> {cmd2=>"0A057B", argMin =>  "50", argMax =>  "300",	type =>"1clean",  unit =>" m3/h"},	#abluft extrated
  "p49SummerModeTemp"			=> {cmd2=>"0A0116", argMin =>  "10", argMax =>   "24",	type =>"5temp",  unit =>" °C"},		#threshold for summer mode !! 
  "p50SummerModeHysteresis"		=> {cmd2=>"0A05A2", argMin => "0.5", argMax =>    "5",	type =>"5temp",  unit =>" K"},		#Hysteresis for summer mode !! 
  "p78DualModePoint"			=> {cmd2=>"0A01AC", argMin => "-10", argMax =>   "20",	type =>"5temp",  unit =>" °C"},
  "p54MinPumpCycles"			=> {cmd2=>"0A05B8", argMin =>  "1",  argMax =>   "24",	type =>"1clean",  unit =>""},
  "p55MaxPumpCycles"			=> {cmd2=>"0A05B7", argMin =>  "25", argMax =>  "200",	type =>"1clean",  unit =>""},
  "p56OutTempMaxPumpCycles"		=> {cmd2=>"0A05B9", argMin =>  "0",  argMax =>   "20",	type =>"5temp",  unit =>" °C"},
  "p57OutTempMinPumpCycles"		=> {cmd2=>"0A05BA", argMin =>  "0",  argMax =>   "25",	type =>"5temp",  unit =>" °C"},
  "p58SuppressTempCaptPumpStart" => {cmd2=>"0A0611", argMin =>  "0",  argMax =>  "120",	type =>"1clean",  unit =>" s"},
  "p76RoomThermCorrection"		=> {cmd2=>"0A0109", argMin =>  "-5", argMax =>    "5", 	type =>"4temp",  unit =>" K"},
  "p77OutThermFilterTime"		=> {cmd2=>"0A010C", argMin =>  "1",  argMax =>   "24", 	type =>"0clean",  unit =>" h"},
  "p35PasteurisationInterval"	=> {cmd2=>"0A0586", argMin =>  "1",  argMax =>   "30", 	type =>"1clean",  unit =>""},
  "p35PasteurisationTemp"		=> {cmd2=>"0A0587", argMin =>  "10", argMax =>   "65", 	type =>"5temp",  unit =>" °C"},
  "p34BoosterDHWTempAct"		=> {cmd2=>"0A0589", argMin => "-10", argMax =>  "10",	type =>"5temp",  unit =>" °C"},
  "p99DHWmaxFlowTemp"			=> {cmd2=>"0A058C", argMin =>  "10", argMax =>  "75",	type =>"5temp",  unit =>" °C"},
  "p99HC1maxFlowTemp"			=> {cmd2=>"0A0027", argMin =>  "10", argMax =>  "75",	type =>"5temp",  unit =>" °C"},
  "p89DHWeco"				    => {cmd2=>"0A058D", argMin =>  "0",  argMax =>   "1", 	type =>"1clean",  unit =>""},
  "p99startUnschedVent"			=> {cmd2=>"0A05DD", argMin =>  "0",  argMax =>   "3", 	type =>"1clean",  unit =>""},
  "p99FrostProtectionBoost"     => {cmd2=>"0A05B3", argMin =>  "10", argMax =>  "30",	type =>"5temp",  unit =>" °C"}, #added by TheTrumpeter __EINFRIERSCHUTZ NE
  "p99FrostProtectionCancel"    => {cmd2=>"0A05B4", argMin =>  "0", argMax =>  "20",	type =>"5temp",  unit =>" °C"}, #added by TheTrumpeter __ABTAUABBR.
  "pClockDay"				    => {cmd2=>"0A0122", argMin =>  "1",  argMax =>  "31", 	type =>"0clean",  unit =>""},
  "pClockMonth"				    => {cmd2=>"0A0123", argMin =>  "1",  argMax =>  "12",	type =>"0clean",  unit =>""},
  "pClockYear"				    => {cmd2=>"0A0124", argMin =>  "12", argMax =>  "20",	type =>"0clean",  unit =>""},
  "pClockHour"				    => {cmd2=>"0A0125", argMin =>  "0",  argMax =>  "23", 	type =>"0clean",  unit =>""},
  "pClockMinutes"			    => {cmd2=>"0A0126", argMin =>  "0",  argMax =>  "59", 	type =>"0clean",  unit =>""},
  "pHolidayBeginDay"			=> {cmd2=>"0A011B", argMin =>  "1",  argMax =>  "31", 	type =>"0clean",  unit =>""},
  "pHolidayBeginMonth"			=> {cmd2=>"0A011C", argMin =>  "1",  argMax =>  "12",	type =>"0clean",  unit =>""},
  "pHolidayBeginYear"			=> {cmd2=>"0A011D", argMin =>  "12", argMax =>  "20",	type =>"0clean",  unit =>""},
  "pHolidayBeginTime"			=> {cmd2=>"0A05D3", argMin =>  "00:00", argMax =>  "23:59", type =>"9holy",   unit =>""},
  "pHolidayEndDay"			    => {cmd2=>"0A011E", argMin =>  "1", 	argMax =>  "31",  type =>"0clean",  unit =>""},
  "pHolidayEndMonth"			=> {cmd2=>"0A011F", argMin =>  "1", 	argMax =>  "12",  type =>"0clean",  unit =>""},
  "pHolidayEndYear"			    => {cmd2=>"0A0120", argMin =>  "12", 	argMax =>  "20",  type =>"0clean",  unit =>""},
  "pHolidayEndTime"			    => {cmd2=>"0A05D4", argMin =>  "00:00", argMax =>  "23:59", type =>"9holy",  unit =>""}, # the answer look like  0A05D4-0D0A05D40029 for year 41 which is 10:15
  #"party-time"				    => {cmd2=>"0A05D1", argMin =>  "00:00", argMax =>  "23:59", type =>"8party", unit =>""}, # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  "programHC1_Mo_0"			    => {cmd2=>"0B1410", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  "programHC1_Mo_1"			    => {cmd2=>"0B1411", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo_2"			    => {cmd2=>"0B1412", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Tu_0"			    => {cmd2=>"0B1420", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Tu_1"			    => {cmd2=>"0B1421", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Tu_2"			    => {cmd2=>"0B1422", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_We_0"			    => {cmd2=>"0B1430", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_We_1"			    => {cmd2=>"0B1431", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_We_2"			    => {cmd2=>"0B1432", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Th_0"			    => {cmd2=>"0B1440", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Th_1"			    => {cmd2=>"0B1441", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Th_2"			    => {cmd2=>"0B1442", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Fr_0"			    => {cmd2=>"0B1450", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Fr_1"			    => {cmd2=>"0B1451", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Fr_2"			    => {cmd2=>"0B1452", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Sa_0"			    => {cmd2=>"0B1460", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Sa_1"			    => {cmd2=>"0B1461", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Sa_2"			    => {cmd2=>"0B1462", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_So_0"			    => {cmd2=>"0B1470", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_So_1"			    => {cmd2=>"0B1471", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_So_2"			    => {cmd2=>"0B1472", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo-Fr_0"			=> {cmd2=>"0B1480", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo-Fr_1"			=> {cmd2=>"0B1481", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo-Fr_2"			=> {cmd2=>"0B1482", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Sa-So_0"			=> {cmd2=>"0B1490", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Sa-So_1"			=> {cmd2=>"0B1491", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Sa-So_2"			=> {cmd2=>"0B1492", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo-So_0"			=> {cmd2=>"0B14A0", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo-So_1"			=> {cmd2=>"0B14A1", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC1_Mo-So_2"			=> {cmd2=>"0B14A2", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo_0"			    => {cmd2=>"0C1510", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  "programHC2_Mo_1"			    => {cmd2=>"0C1511", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo_2"			    => {cmd2=>"0C1512", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Tu_0"			    => {cmd2=>"0C1520", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Tu_1"			    => {cmd2=>"0C1521", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Tu_2"			    => {cmd2=>"0C1522", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_We_0"			    => {cmd2=>"0C1530", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_We_1"			    => {cmd2=>"0C1531", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_We_2"			    => {cmd2=>"0C1532", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Th_0"			    => {cmd2=>"0C1540", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Th_1"			    => {cmd2=>"0C1541", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Th_2"			    => {cmd2=>"0C1542", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Fr_0"			    => {cmd2=>"0C1550", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Fr_1"			    => {cmd2=>"0C1551", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Fr_2"			    => {cmd2=>"0C1552", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Sa_0"			    => {cmd2=>"0C1560", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Sa_1"			    => {cmd2=>"0C1561", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Sa_2"			    => {cmd2=>"0C1562", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_So_0"			    => {cmd2=>"0C1570", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_So_1"			    => {cmd2=>"0C1571", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_So_2"			    => {cmd2=>"0C1572", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo-Fr_0"			=> {cmd2=>"0C1580", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo-Fr_1"			=> {cmd2=>"0C1581", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo-Fr_2"			=> {cmd2=>"0C1582", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Sa-So_0"			=> {cmd2=>"0C1590", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Sa-So_1"			=> {cmd2=>"0C1591", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Sa-So_2"			=> {cmd2=>"0C1592", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo-So_0"			=> {cmd2=>"0C15A0", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo-So_1"			=> {cmd2=>"0C15A1", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programHC2_Mo-So_2"			=> {cmd2=>"0C15A2", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo_0"			    => {cmd2=>"0A1710", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo_1"			    => {cmd2=>"0A1711", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo_2"			    => {cmd2=>"0A1712", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Tu_0"			    => {cmd2=>"0A1720", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Tu_1"			    => {cmd2=>"0A1721", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Tu_2"			    => {cmd2=>"0A1722", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_We_0"			    => {cmd2=>"0A1730", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_We_1"			    => {cmd2=>"0A1731", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_We_2"			    => {cmd2=>"0A1732", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Th_0"			    => {cmd2=>"0A1740", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Th_1"			    => {cmd2=>"0A1741", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Th_2"			    => {cmd2=>"0A1742", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Fr_0"			    => {cmd2=>"0A1750", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Fr_1"			    => {cmd2=>"0A1751", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Fr_2"			    => {cmd2=>"0A1752", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Sa_0"			    => {cmd2=>"0A1760", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Sa_1"			    => {cmd2=>"0A1761", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Sa_2"			    => {cmd2=>"0A1762", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_So_0"			    => {cmd2=>"0A1770", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_So_1"			    => {cmd2=>"0A1771", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_So_2"			    => {cmd2=>"0A1772", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo-Fr_0"			=> {cmd2=>"0A1780", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo-Fr_1"			=> {cmd2=>"0A1781", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo-Fr_2"			=> {cmd2=>"0A1782", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Sa-So_0"			=> {cmd2=>"0A1790", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Sa-So_1"			=> {cmd2=>"0A1791", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Sa-So_2"			=> {cmd2=>"0A1792", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo-So_0"			=> {cmd2=>"0A17A0", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo-So_1"			=> {cmd2=>"0A17A1", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programDHW_Mo-So_2"			=> {cmd2=>"0A17A2", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo_0"			    => {cmd2=>"0A1D10", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo_1"			    => {cmd2=>"0A1D11", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo_2"			    => {cmd2=>"0A1D12", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Tu_0"			    => {cmd2=>"0A1D20", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Tu_1"			    => {cmd2=>"0A1D21", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Tu_2"			    => {cmd2=>"0A1D22", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_We_0"			    => {cmd2=>"0A1D30", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_We_1"			    => {cmd2=>"0A1D31", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_We_2"			    => {cmd2=>"0A1D32", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Th_0"			    => {cmd2=>"0A1D40", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Th_1"			    => {cmd2=>"0A1D41", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Th_2"			    => {cmd2=>"0A1D42", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Fr_0"			    => {cmd2=>"0A1D50", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Fr_1"			    => {cmd2=>"0A1D51", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Fr_2"			    => {cmd2=>"0A1D52", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Sa_0"			    => {cmd2=>"0A1D60", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Sa_1"			    => {cmd2=>"0A1D61", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Sa_2"			    => {cmd2=>"0A1D62", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_So_0"			    => {cmd2=>"0A1D70", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_So_1"			    => {cmd2=>"0A1D71", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_So_2"			    => {cmd2=>"0A1D72", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo-Fr_0"			=> {cmd2=>"0A1D80", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo-Fr_1"			=> {cmd2=>"0A1D81", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo-Fr_2"			=> {cmd2=>"0A1D82", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Sa-So_0"			=> {cmd2=>"0A1D90", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Sa-So_1"			=> {cmd2=>"0A1D91", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Sa-So_2"			=> {cmd2=>"0A1D92", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo-So_0"			=> {cmd2=>"0A1DA0", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo-So_1"			=> {cmd2=>"0A1DA1", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "programFan_Mo-So_2"			=> {cmd2=>"0A1DA2", argMin =>  "00:00", argMax =>  "24:00", type =>"7prog",  unit =>""},
  "pOvenFireplace"			    => {cmd2=>"0A057C", argMin =>  "0",     argMax =>  "4",     type =>"1clean",  unit =>""}, #Ofen / Kamin (0=Aus … 4= oeffner - ueberwachung)
    #OFF/    N-O_CONTACT_OFF/       N-C_CONTACT_OFF/     N-O_MONITORING/    N-C_MONITORING
    #LLWT = LuftLuftWärmeTauscher - AirAirHeatExchanger
  "p85MaxDefrostDur"	        => {cmd2=>"0A057D", argMin =>  "60", argMax =>   "250",	type =>"1clean",  unit =>" min"},
  "p85DefrStartThreshold"       => {cmd2=>"0A057E", argMin =>  "0",  argMax =>   "50",	type =>"1clean",  unit =>" %"},  #LLWT_Abtaubeginnschwelle (%) -
  "p85FilterSpeed"              => {cmd2=>"0A057F", argMin =>  "0",  argMax =>   "100",	type =>"1clean",  unit =>" %"}   #LLWT_DrehzahlFilter (%) - increase in VentSpeed to indicate dirt / replacement needed 
  );


  
my %sets439only =(
  "p75passiveCooling"			=> {cmd2=>"0A0575", argMin =>   "0", argMax =>    "2",	type =>"1clean",  unit =>""}   
 );
  
my %sets539only =(
  "p75passiveCooling"			=> {cmd2=>"0A0575", argMin =>   "0", argMax =>    "4",	type =>"1clean",  unit =>""},    
  "p99PumpRateHC"				=> {cmd2=>"0A02CB", argMin =>   "0", argMax =>  "100",	type =>"5temp",  unit =>" %"},  
  "p99PumpRateDHW"				=> {cmd2=>"0A02CC", argMin =>   "0", argMax =>  "100",	type =>"5temp",  unit =>" %"} ,
  "p99CoolingHC1Switch"			=> {cmd2=>"0B0287", argMin =>   "0", argMax =>    "1",	type =>"1clean",  unit =>""},
  "p99CoolingHC1SetTemp"		=> {cmd2=>"0B0582", argMin =>  "12", argMax =>  "27",	type =>"5temp",  unit =>" °C"},    #suggested by TheTrumpeter
  "p99CoolingHC1HystersisFlowTemp"		=> {cmd2=>"0B0583", argMin =>  "0.5", argMax =>  "5",	type =>"5temp",  unit =>" K"}, #suggested by TheTrumpeter
  "p99CoolingHC1HystersisRoomTemp"		=> {cmd2=>"0B0584", argMin =>  "0.5", argMax =>  "3",	type =>"5temp",  unit =>" K"}  #suggested by TheTrumpeter
);
  

my %sets206 = (
  "p01RoomTempDay"	        	=> {parent=>"p01-p12",      argMin => "10", 	argMax =>   "30", 	type =>"pclean", unit =>" °C"},
  "p02RoomTempNight"	        => {parent=>"p01-p12",      argMin => "10", 	argMax =>   "30", 	type =>"pclean", unit =>" °C"},
  "p03RoomTempStandby"	        => {parent=>"p01-p12",      argMin => "10", 	argMax =>   "30", 	type =>"pclean", unit =>" °C"},
  "p04DHWsetTempDay"	        => {parent=>"p01-p12",      argMin => "10", 	argMax =>   "55", 	type =>"pclean", unit =>" °C"},
  "p05DHWsetTempNight"	        => {parent=>"p01-p12",      argMin => "10", 	argMax =>   "55", 	type =>"pclean", unit =>" °C"},
  "p06DHWsetTempStandby"        => {parent=>"p01-p12",      argMin => "10", 	argMax =>   "55", 	type =>"pclean", unit =>" °C"},
  "p07FanStageDay"	        	=> {parent=>"p01-p12",      argMin => "0", 		argMax =>    "3", 	type =>"pclean", unit =>""},
  "p08FanStageNight"	        => {parent=>"p01-p12",      argMin => "0", 		argMax =>    "3", 	type =>"pclean", unit =>""},
  "p09FanStageStandby"	        => {parent=>"p01-p12",      argMin => "0", 		argMax =>    "3", 	type =>"pclean", unit =>""},
  "p10HCTempManual"	        	=> {parent=>"p01-p12",      argMin => "10", 	argMax =>   "65", 	type =>"pclean", unit =>" °C"},
  "p11DHWsetTempManual"	        => {parent=>"p01-p12",      argMin => "10", 	argMax =>   "65", 	type =>"pclean", unit =>" °C"},
  "p12FanStageManual"           => {parent=>"p01-p12",      argMin => "0", 		argMax =>    "3", 	type =>"pclean", unit =>""},
  "p13GradientHC1"			    => {parent=>"pHeat1", 		argMin => "0", 		argMax =>    "5", 	type =>"pclean", unit =>""},
  "p14LowEndHC1"			    => {parent=>"pHeat1", 		argMin => "0", 		argMax =>   "20", 	type =>"pclean", unit =>" K"},
  "p15RoomInfluenceHC1"			=> {parent=>"pHeat1", 		argMin => "0", 		argMax =>   "10",	type =>"pclean", unit =>""},
  "p16GradientHC2"		    	=> {parent=>"pHeat1", 		argMin => "0", 		argMax =>    "5",	type =>"pclean", unit =>""},
  "p17LowEndHC2"		    	=> {parent=>"pHeat1", 		argMin => "0", 		argMax =>   "10", 	type =>"pclean", unit =>" K"},
  "p18RoomInfluenceHC2"			=> {parent=>"pHeat1", 		argMin => "0", 		argMax =>   "10",	type =>"pclean", unit =>""},
  "p19FlowProportionHC1"		=> {parent=>"pHeat1", 		argMin => "0", 		argMax =>  "100",	type =>"pclean", unit =>" %"},
  "p20FlowProportionHC2"		=> {parent=>"pHeat1", 		argMin => "0", 		argMax =>  "100",	type =>"pclean", unit =>" %"},
  "p21Hyst1"			    	=> {parent=>"pHeat2", 		argMin => "0", 		argMax =>   "10", 	type =>"pclean", unit =>" K"},
  "p22Hyst2"			    	=> {parent=>"pHeat2", 		argMin => "0", 		argMax =>   "10", 	type =>"pclean", unit =>" K"},
  "p23Hyst3"			    	=> {parent=>"pHeat2", 		argMin => "0", 		argMax =>    "5", 	type =>"pclean", unit =>" K"},
  "p24Hyst4"			    	=> {parent=>"pHeat2", 		argMin => "0", 		argMax =>    "5", 	type =>"pclean", unit =>" K"},
  "p25Hyst5"			    	=> {parent=>"pHeat2", 		argMin => "0", 		argMax =>    "5", 	type =>"pclean", unit =>" K"},
  "p29HystAsymmetry"			=> {parent=>"pHeat2", 		argMin => "1", 		argMax =>    "5",	type =>"pclean", unit =>""},
  "p30integralComponent"		=> {parent=>"pHeat2", 		argMin => "10", 	argMax =>  "999",	type =>"pclean", unit =>" Kmin"},
  "p32HystDHW"			    	=> {parent=>"pDHW", 		argMin => "2", 		argMax =>   "10", 	type =>"pclean", unit =>" K"},
  "p33BoosterTimeoutDHW"		=> {parent=>"pDHW", 		argMin => "0",		argMax =>  "240",	type =>"pclean", unit =>" min"},
  "p34TempLimitBoostDHW"    	=> {parent=>"pDHW", 		argMin => "-10", 	argMax =>   "10", 	type =>"pclean", unit =>" °C"},
  "p35PasteurisationInterval"  	=> {parent=>"pDHW", 		argMin => "3", 		argMax =>   "30", 	type =>"pclean", unit =>" Days"},
  "p36MaxDurationDHWLoad"    	=> {parent=>"pDHW", 		argMin => "6", 		argMax =>   "12", 	type =>"pclean", unit =>" h"},
  "p37Fanstage1AirflowInlet"	=> {parent=>"pFan", 		argMin => "60", 	argMax =>  "250",	type =>"pclean", unit =>" m3/h"},
  "p38Fanstage2AirflowInlet"	=> {parent=>"pFan", 		argMin => "60", 	argMax =>  "250",	type =>"pclean", unit =>" m3/h"},
  "p39Fanstage3AirflowInlet"	=> {parent=>"pFan", 		argMin => "60", 	argMax =>  "250",	type =>"pclean", unit =>" m3/h"},
  "p40Fanstage1AirflowOutlet"	=> {parent=>"pFan", 		argMin => "60", 	argMax =>  "250",	type =>"pclean", unit =>" m3/h"},
  "p41Fanstage2AirflowOutlet"	=> {parent=>"pFan", 		argMin => "60", 	argMax =>  "250",	type =>"pclean", unit =>" m3/h"},
  "p42Fanstage3AirflowOutlet"	=> {parent=>"pFan", 		argMin => "60", 	argMax =>  "250",	type =>"pclean", unit =>" m3/h"},
  "p43UnschedVent3"				=> {parent=>"pFan", 		argMin => "0", 		argMax => "1000",	type =>"pclean", unit =>" min"},
  "p44UnschedVent2"				=> {parent=>"pFan", 		argMin => "0", 		argMax => "1000",	type =>"pclean", unit =>" min"},
  "p45UnschedVent1"				=> {parent=>"pFan", 		argMin => "0", 		argMax => "1000",	type =>"pclean", unit =>" min"},
  "p46UnschedVent0"	        	=> {parent=>"pFan", 		argMin => "0", 		argMax => "1000",	type =>"pclean", unit =>" min"},
  "p47CompressorRestartDelay"	=> {parent=>"pDefrostEva", 	argMin => "0", 		argMax =>   "20",	type =>"pclean", unit =>" min"},
  "p48MainFanSpeed"	        	=> {parent=>"pDefrostEva", 	argMin => "0", 		argMax =>  "100",	type =>"pclean", unit =>" %"},
  "p49SummerModeTemp"			=> {parent=>"pHeat2", 		argMin => "10", 	argMax =>   "24",	type =>"pclean", unit =>" °C"},
  "p50SummerModeHysteresis"		=> {parent=>"pHeat2", 		argMin => "1", 		argMax =>    "5",	type =>"pclean", unit =>" K"},
  "p54MinPumpCycles"			=> {parent=>"pCircPump", 	argMin => "1",  	argMax =>   "24",	type =>"pclean", unit =>" /Day"},
  "p55MaxPumpCycles"			=> {parent=>"pCircPump", 	argMin => "25", 	argMax =>  "288",	type =>"pclean", unit =>" /Day"},
  "p56OutTempMaxPumpCycles"		=> {parent=>"pCircPump", 	argMin => "0",  	argMax =>   "20",	type =>"pclean", unit =>" °C"},
  "p57OutTempMinPumpCycles"		=> {parent=>"pCircPump", 	argMin => "0",  	argMax =>   "25",	type =>"pclean", unit =>" °C"},
  "p58SuppressTempCaptPumpStart"=> {parent=>"pCircPump", 	argMin => "0",  	argMax =>  "120",	type =>"pclean", unit =>" s"},
  "p75PassiveCooling"			=> {parent=>"pFan", 		argMin => "0", 		argMax =>    "1",	type =>"pclean", unit =>""},
  "p77OutTempFilterTime"		=> {parent=>"pHeat2", 		argMin => "0",  	argMax =>   "24", 	type =>"pclean", unit =>" h"},
  "p78DualModePoint"			=> {parent=>"pHeat2", 		argMin => "-10", 	argMax =>   "20",	type =>"pclean", unit =>" °C"},
  "p79BoosterTimeoutHC"			=> {parent=>"pHeat2", 		argMin => "0", 		argMax =>   "60",	type =>"pclean", unit =>" min"},
  "p80EnableSolar"              => {parent=>"pSolar",       argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "pClockDay"                   => {parent=>"sTimedate",    argMin => "1", 		argMax =>   "31", 	type =>"pclean", unit =>""},
  "pClockMonth"                 => {parent=>"sTimedate",    argMin => "1", 		argMax =>   "12", 	type =>"pclean", unit =>""},
  "pClockYear"                  => {parent=>"sTimedate",    argMin => "12", 	argMax =>   "20", 	type =>"pclean", unit =>""},
  "pClockHour"                  => {parent=>"sTimedate",    argMin => "0", 		argMax =>   "23", 	type =>"pclean", unit =>""},
  "pClockMinutes"               => {parent=>"sTimedate",    argMin => "0", 		argMax =>   "59", 	type =>"pclean", unit =>""},
  "progDHWStartTime"            => {parent=>"pDHWProg",     argMin => "00:00",  argMax => "23:59",  type =>"ptime",  unit =>""},
  "progDHWEndTime"              => {parent=>"pDHWProg",     argMin => "00:00", 	argMax => "23:59",  type =>"ptime",  unit =>""},
  "progDHWEnable"               => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWMonday"               => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWTuesday"              => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWWednesday"            => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWThursday"             => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWFriday"               => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWSaturday"             => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progDHWSunday"               => {parent=>"pDHWProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1StartTime"            => {parent=>"pHeatProg",    argMin => "00:00", 	argMax => "23:59",  type =>"ptime",  unit =>""}, 
  "progHC1EndTime"              => {parent=>"pHeatProg",    argMin => "00:00", 	argMax => "23:59",  type =>"ptime",  unit =>""},
  "progHC1Enable"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Monday"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Tuesday"              => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Wednesday"            => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Thursday"             => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Friday"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Saturday"             => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC1Sunday"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2StartTime"            => {parent=>"pHeatProg",    argMin => "00:00", 	argMax => "23:59",  type =>"ptime",  unit =>""}, 
  "progHC2EndTime"              => {parent=>"pHeatProg",    argMin => "00:00", 	argMax => "23:59",  type =>"ptime",  unit =>""},
  "progHC2Enable"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Monday"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Tuesday"              => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Wednesday"            => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Thursday"             => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Friday"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Saturday"             => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progHC2Sunday"               => {parent=>"pHeatProg",    argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1StartTime"           => {parent=>"pFanProg",     argMin => "00:00",	argMax => "23:59",  type =>"ptime",  unit =>""}, 
  "progFAN1EndTime"             => {parent=>"pFanProg",     argMin => "00:00",	argMax => "23:59",  type =>"ütime",  unit =>""},
  "progFAN1Enable"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Monday"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Tuesday"             => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Wednesday"           => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Thursday"            => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Friday"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Saturday"            => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN1Sunday"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2StartTime"           => {parent=>"pFanProg",     argMin => "00:00", 	argMax =>  "23:59", type =>"ptime",  unit =>""}, 
  "progFAN2EndTime"             => {parent=>"pFanProg",     argMin => "00:00", 	argMax =>  "23:59", type =>"ptime",  unit =>""},
  "progFAN2Enable"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Monday"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Tuesday"             => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Wednesday"           => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Thursday"            => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Friday"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Saturday"            => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""},
  "progFAN2Sunday"              => {parent=>"pFanProg",     argMin => "0", 		argMax =>    "1", 	type =>"pclean", unit =>""}  
 );

my %setsonly214 = (
  "ResetErrors"			        => {cmd2=>"F8",             argMin =>   "0",    argMax =>    "0",	type =>"0clean", unit =>""}
);


########################################################################################
#
# %gets - all supported protocols are listed without header and footer
#
########################################################################################

my %getsonly439 = (
#"debug_read_raw_register_slow"	=> { },
  "sSol"			    => {cmd2=>"16", type =>"16sol", unit =>""},
  "sHistory"			=> {cmd2=>"09", type =>"09his", unit =>""},
  "sLast10errors"		=> {cmd2=>"D1", type =>"D1last", unit =>""},
  "sFan"  				=> {cmd2=>"E8", type =>"E8fan", unit =>""},
  "sDHW"			    => {cmd2=>"F3", type =>"F3dhw", unit =>""},
  "sHC1"			    => {cmd2=>"F4", type =>"F4hc1", unit =>""},
  "sHC2"			    => {cmd2=>"F5", type =>"F5hc2", unit =>""},
  "sControl"  			=> {cmd2=>"F2", type =>"F2ctrl", unit =>""},
  "sGlobal"	     		=> {cmd2=>"FB", type =>"FBglob", unit =>""},  #allFB
  "sTimedate" 			=> {cmd2=>"FC", type =>"FCtime", unit =>""},
  "sFirmware" 			=> {cmd2=>"FD", type =>"FDfirm", unit =>""},
  "sFirmware-Id" 		=> {cmd2=>"FE", type =>"FEfirmId", unit =>""},
  "sDisplay" 			=> {cmd2=>"0A0176", type =>"0A0176Dis", unit =>""},
  "sBoostDHWTotal" 		=> {cmd2=>"0A0924", cmd3=>"0A0925",	type =>"1clean", unit =>" kWh"},
  "sBoostHCTotal"	 	=> {cmd2=>"0A0928", cmd3=>"0A0929",	type =>"1clean", unit =>" kWh"},
  "sHeatRecoveredDay" 	=> {cmd2=>"0A03AE", cmd3=>"0A03AF",	type =>"1clean", unit =>" Wh"},
  "sHeatRecoveredTotal" => {cmd2=>"0A03B0", cmd3=>"0A03B1",	type =>"1clean", unit =>" kWh"},
  "sHeatDHWDay" 		=> {cmd2=>"0A092A", cmd3=>"0A092B",	type =>"1clean", unit =>" Wh"},
  "sHeatDHWTotal" 		=> {cmd2=>"0A092C", cmd3=>"0A092D",	type =>"1clean", unit =>" kWh"},
  "sHeatHCDay" 			=> {cmd2=>"0A092E", cmd3=>"0A092F",	type =>"1clean", unit =>" Wh"},
  "sHeatHCTotal"	 	=> {cmd2=>"0A0930", cmd3=>"0A0931",	type =>"1clean", unit =>" kWh"},
  "sElectrDHWDay" 		=> {cmd2=>"0A091A", cmd3=>"0A091B",	type =>"1clean", unit =>" Wh"},
  "sElectrDHWTotal" 	=> {cmd2=>"0A091C", cmd3=>"0A091D",	type =>"1clean", unit =>" kWh"},
  "sElectrHCDay" 		=> {cmd2=>"0A091E", cmd3=>"0A091F",	type =>"1clean", unit =>" Wh"},
  "sElectrHCTotal"		=> {cmd2=>"0A0920", cmd3=>"0A0921",	type =>"1clean", unit =>" kWh"},
  "party-time"			=> {cmd2=>"0A05D1", argMin =>  "00:00", argMax =>  "23:59", type =>"8party", unit =>""} # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  );


my %getsonly539 = (  #info from belu and godmorgon
  "sFlowRate"          	=> {cmd2=>"0A033B",   type =>"1clean", unit =>" cl/min"},
  "sHumMaskingTime"     => {cmd2=>"0A064F",   type =>"1clean", unit =>" min"},
  "sHumThreshold"		=> {cmd2=>"0A0650",   type =>"1clean", unit =>" %"},
  "sOutputReduction"    => {cmd2=>"0A06A4",   type =>"1clean", unit =>" %"},
  "sOutputIncrease"     => {cmd2=>"0A06A5",   type =>"1clean", unit =>" %"},
  "sHumProtection"		=> {cmd2=>"0A09D1",   type =>"1clean", unit =>""},
  "sSetHumidityMin"     => {cmd2=>"0A09D2",   type =>"1clean", unit =>" %"},
  "sSetHumidityMax"     => {cmd2=>"0A09D3",   type =>"1clean", unit =>" %"},
  "sCoolHCTotal"        => {cmd2=>"0A0648",   cmd3 =>"0A0649",  type =>"1clean", unit =>" kWh"},
  "sDewPointHC1"        => {cmd2=>"0B0264",   type =>"5temp",  unit =>" °C"}
 );
%getsonly539=(%getsonly539, %getsonly439);

my %getsonly2xx = (
  "pDefrostEva"			=> {cmd2=>"03", type =>"03pxx206", unit =>""},
  "pDefrostAA"			=> {cmd2=>"04", type =>"04pxx206", unit =>""},
  "pHeat1"			    => {cmd2=>"05", type =>"05pxx206", unit =>""},
  "pHeat2"			    => {cmd2=>"06", type =>"06pxx206", unit =>""},
  "pDHW"			    => {cmd2=>"07", type =>"07pxx206", unit =>""},
  "pSolar"			    => {cmd2=>"08", type =>"08pxx206", unit =>""},
  "sHistory"			=> {cmd2=>"09", type =>"09his206", unit =>""},
  "pCircPump"			=> {cmd2=>"0A", type =>"0Apxx206", unit =>""},
  "pHeatProg"			=> {cmd2=>"0B", type =>"0Bpxx206", unit =>""},
  "pDHWProg"			=> {cmd2=>"0C", type =>"0Cpxx206", unit =>""},
  "pFanProg"   			=> {cmd2=>"0D", type =>"0Dpxx206", unit =>""},
  "pRestart"			=> {cmd2=>"0E", type =>"0Epxx206", unit =>""},
  "pAbsence"			=> {cmd2=>"0F", type =>"0Fpxx206", unit =>""},
  "pDryHeat"			=> {cmd2=>"10", type =>"10pxx206", unit =>""},
  "sSol"			    => {cmd2=>"16", type =>"16sol",    unit =>""},
  "p01-p12"			    => {cmd2=>"17", type =>"17pxx206", unit =>""},
  "sProgram"  			=> {cmd2=>"EE", type =>"EEprg206", unit =>""},
  "sFan"  				=> {cmd2=>"E8", type =>"E8fan206", unit =>""},
  "sControl"  			=> {cmd2=>"F2", type =>"F2ctrl",   unit =>""},
  "sDHW"			    => {cmd2=>"F3", type =>"F3dhw",    unit =>""},
  "sHC2"			    => {cmd2=>"F5", type =>"F5hc2",    unit =>""},
  "sSystem"			    => {cmd2=>"F6", type =>"F6sys206", unit =>""},
  "sTimedate" 			=> {cmd2=>"FC", type =>"FCtime206", unit =>""},
  "inputVentilatorSpeed"=> {parent=>"sGlobal",              unit =>" %"},
  "outputVentilatorSpeed"=>{parent=>"sGlobal",              unit =>" %"},
  "mainVentilatorSpeed"	=> {parent=>"sGlobal",              unit =>" %"},
  "inputVentilatorPower"=> {parent=>"sGlobal",              unit =>" %"},
  "outputVentilatorPower"=>{parent=>"sGlobal",              unit =>" %"},
  "mainVentilatorPower"	=> {parent=>"sGlobal",              unit =>" %"}, 
 );
my %getsonly206 = (
  "sHC1"			    => {cmd2=>"F4", type =>"F4hc1",    unit =>""},
  "pFan"              	=> {cmd2=>"01", type =>"01pxx206", unit =>""},
  "sLast10errors"     	=> {cmd2=>"D1", type =>"D1last206", unit =>""},
  "sFirmware" 			=> {cmd2=>"FD", type =>"FDfirm",   unit =>""},
  "sGlobal"	     		=> {cmd2=>"FB", type =>"FBglob206", unit =>""}
 );

my %getsonly214 = (
  "pFan"          		=> {cmd2=>"01", type =>"01pxx214", unit =>""},
  "pExpert"			    => {cmd2=>"02", type =>"02pxx206", unit =>""},
  "sControl"  			=> {cmd2=>"F2", type =>"F2type", unit =>""},
  "sHC1"			    => {cmd2=>"F4", type =>"F4hc1214",    unit =>""},
  #"sLVR"  				=> {cmd2=>"E8", type =>"E8tyype", unit =>""},
  #"sF0"  				=> {cmd2=>"F0", type =>"F0type", unit =>""},
  #"sF1"  				=> {cmd2=>"F1", type =>"F1type", unit =>""},
  #"sEF"  				=> {cmd2=>"EF", type =>"EFtype", unit =>""},
  "sGlobal"	     		=> {cmd2=>"FB", type =>"FBglob214", unit =>""}  
 ); 


my %sets=       (%sets439539common, %sets439only);
my %gets=       (%getsonly439, %sets);
my %OpMode=     ("1" =>"standby", "11" => "automatic", "3" =>"DAYmode", "4" =>"setback", "5" =>"DHWmode", "14" =>"manual", "0" =>"emergency");   
my %Rev_OpMode= reverse %OpMode;
my %OpModeHC=   ("1" =>"normal", "2" => "setback", "3" =>"standby", "4" =>"restart", "5" =>"restart");
my %opMode2=    ("0" =>"manual", "1" => "automatic");
my %SomWinMode= ("01" =>"winter", "02" => "summer");
my %weekday=    ("0" =>"Monday", "1" => "Tuesday", "2" =>"Wednesday", "3" => "Thursday", "4" => "Friday", "5" =>"Saturday", "6" => "Sunday" );
#my %weekdaymap= ( "1" =>"Mon", "2" => "Tue", "3" =>"Wed", "4" => "Thu", "5" => "Fri", "6" =>"Sat", "7" => "Sun" );
my %faultmap=   ( "0" =>"n.a.", "1" => "F01_AnodeFault", "2" => "F02_SafetyTempDelimiterEngaged", "3" => "F03_HighPreasureGuardFault", "4" => "F04_LowPreasureGuardFault", "5" => "F05_OutletFanFault", "6" => "F06_InletFanFault", "7" => "F07_MainOutputFanFault", "11" => "F11_LowPreasureSensorFault", "12"=> "F12_HighPreasureSensorFault", "15" => "F15_DHW_TemperatureFault",  "17" => "F17_DefrostingDurationExceeded", "20" => "F20_SolarSensorFault", "21" => "F21_OutsideTemperatureSensorFault", "22" => "F22_HotGasTemperatureFault", "23" => "F23_CondenserTemperatureSensorFault", "24" => "F24_EvaporatorTemperatureSensorFault", "26" => "F26_ReturnTemperatureSensorFault", "28" => "F28_FlowTemperatureSensorFault", "29" => "F29_DHW_TemperatureSensorFault", "30" => "F30_SoftwareVersionFault", "31" => "F31_RAMfault", "32" => "F32_EEPromFault", "33" => "F33_ExtractAirHumiditySensor", "34" => "F34_FlowSensor", "35" => "F35_minFlowCooling", "36" => "F36_MinFlowRate", "37" => "F37_MinWaterPressure", "40" => "F40_FloatSwitch", "50" => "F50_SensorHeatPumpReturn", "51" => "F51_SensorHeatPumpFlow",  "52" => "F52_SensorCondenserOutlet" );
my $firstLoadAll= 0;
my $noanswerreceived= 0;
my $internalHash;
 
########################################################################################
#
# THZ_Initialize($)
# 
# Parameter hash
#
########################################################################################
sub THZ_Initialize($) {
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
  $hash->{FW_detailFn}  ="THZ_detailFn";
  $hash->{AttrList}= "IODev do_not_notify:1,0  ignore:0,1 dummy:1,0 showtime:1,0 "
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
		    ."interval_sBoostHCTotal:0,3600,7200,28800,43200,86400 "
		    ."interval_sFlowRate:0,3600,7200,28800,43200,86400 "
		    ."interval_sDisplay:0,60,120,180,300 "
		    ."firmware:4.39,2.06,2.14,5.39,4.39technician "
            ."interval_sDewPointHC1:0,60,120,180,300 "
            ."simpleReadTimeout:0.25,0.5,1,2,3,4,5,6,7,8,9,10 " #standard has been 0.5 since msg468515 If blocking attribut is NOT enabled then set the timeout value to a maximum value of 0.5 sec.
            ."nonblocking:0,1 "
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
sub THZ_Define($$) {
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
     Log3 $name, 2, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $hash->{DeviceName} = $dev;
  $attr{$name}{devStateIcon} = 'opened:10px-kreis-gruen disconnected:10px-kreis-rot';
  my $ret = DevIo_OpenDev($hash, 0, "THZ_Refresh_all_gets");
  #THZ_Testloopapproach($hash);
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
  RemoveInternalTimer(0, "THZ_GetRefresh");
  #THZ_RemoveInternalTimer("THZ_GetRefresh"); not needed since https://svn.fhem.de/trac/changeset/15667/ because now there is a second parameter for the function
  #Log3 $hash->{NAME}, 3, "THZ_GetRefresh_all ";
  Log3 $hash->{NAME}, 5, "thzversion = $thzversion ";
  my $timedelay= 65; 						#5 seconds were ok but considering winter 2017/2018 I prefer to increase
  foreach  my $cmdhash  (keys %gets) {
    my %par = (  hash => $hash, command => $cmdhash );
    #RemoveInternalTimer(\%par); #commented out in  v.0161 because appearently redundant; THZ_RemoveInternalTimer is more efficient and both are not needed
    InternalTimer(gettimeofday() + ($timedelay) , "THZ_GetRefresh", \%par, 0);		#increment 0.6 $timedelay++
    $timedelay += 1.6;                      #0.6 seconds were ok but considering winter 2017/2018 I prefer to increase
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
    my $name =$hash->{NAME};
	my $interval = AttrVal($name, ("interval_".$command), 0); 
	if (AttrVal($name, "nonblocking" , "0")  =~ /1/ ) {
        if (!(exists($hash->{helper}{RUNNING_PID}))) {
            DevIo_CloseDev($hash);          #close device in parent process
            #$hash->{STATE}="disconnected";
            my $bctimeout = (AttrVal($name, "simpleReadTimeout", "0.5"))*2 +1;
            my $dev = $hash->{DeviceName};
            #$hash->{connection} =$hash->{STATE} ."||". $hash->{USBDev} ."||". $hash->{TCPDev} ."||". $hash->{conn} ."||". $hash->{FD} ."||". $selectlist{"$name.$dev"} ;
            $hash->{connection} =$hash->{STATE} ."||". $hash->{TCPDev} ."||". $hash->{FD} ."||". $selectlist{"$name.$dev"} ;
            Log3 $hash, 3,  $hash->{connection};
            
            $hash->{helper}{RUNNING_PID} = BlockingCall("THZ_GetNB", $name."|".$command, "THZ_GetNBDone", $bctimeout, "THZ_GetNBAbort", $hash);
            Log3 $hash, 3, "[$name] THZ_GetRefresh($command) BlockingCall started";
        }
        else {
            Log3 $hash, 3, "[$name] THZ_GetRefresh($command) rescheduled (Blocking Call is still running)";
            InternalTimer(gettimeofday() + 2, "THZ_GetRefresh", $par, 1);
            return;
        }
    }
    else {
      THZ_Get($hash, $hash->{NAME}, $command) if ($hash->{STATE} ne "disconnected");
    }
    
    if (($interval) and ($hash->{STATE} ne "disconnected")) {
			  $interval = 60 if ($interval < 60); #do not allow intervall <60 sec 
			  InternalTimer(gettimeofday()+ $interval, "THZ_GetRefresh", $par, 1) ;
	}
    if ($command =~ "sFirmware") {  # model summary for statistics
        my $sFirmwareId = join('', (split(/ |:/, ReadingsVal($name,"sFirmware-Id"," : : : ")))[0..6]);
        my $sFirmware= (split(/ /, ReadingsVal($name,"sFirmware","  ")))[1];
        $hash->{model}= sprintf("%.5s%s%s", AttrVal($name,"firmware","n.a.")."______", $sFirmware, $sFirmwareId);
       }
    
    return;
}



#####################################
# THZ_Write -- simple write
# Parameter:  hash and message HEX
#
########################################################################################
sub THZ_Write($$) {
  my ($hash,$bstring) = @_;
  my $name = $hash->{NAME};
  Log3 $hash->{NAME}, 5, "$hash->{NAME} sending $bstring"; 
  DevIo_SimpleWrite($hash, $bstring, 1);
}


#####################################
# sub THZ_Read($)
# called from the global loop, when the select for hash reports data
# used just for testing the interface
########################################################################################
sub THZ_Read($) {
  my ($hash) = @_;
  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  $hash->{helper}{PARTIAL} .= uc(unpack('H*', $buf));
  my $msg=$hash->{helper}{PARTIAL};
  my $err;
  if ( !defined($hash->{helper}{step}) or (length($msg) == 1)  or (($msg =~ m/^01/) and ($msg !~ m/1003$/m ))) {} 
  else {
    if    ($hash->{helper}{step} eq "step0") { #Expectedanswer0    is  "10"  DLE data link escape
            if ($msg ne "10")   {$err .= " THZ_Get_Com: error found at step0 $msg"; $err .=" NAK!!" if ($msg eq "15");  THZ_Resethelper($hash);}
            else                { THZ_Write($hash, $hash->{helper}{cmdHex}); 		$hash->{helper}{step}="step1";       $hash->{helper}{PARTIAL}="";  }
        }    
    elsif ($hash->{helper}{step} eq "step1") { #Expectedanswer1     is "1002",		DLE data link escape -- STX start of text  
            if      ($msg eq "10") 	{ }
            elsif   ($msg eq "15")  { $err .=  " THZ_Get_Com: error found at step1  NAK!! ";    THZ_Resethelper($hash); }
            elsif   ($msg eq "1002" || $msg eq "02") {THZ_Write($hash,  "10"); 	                $hash->{helper}{step}="step2"; $hash->{helper}{PARTIAL}=""; }
        }
    elsif ($hash->{helper}{step} eq "step2") { #Expectedanswer2     is  message from the heatpump
            ($err, $msg) = THZ_decode($msg);
            $msg.=THZ_Parse1($hash,$msg);
            THZ_Write($hash,  "10");
            #THZ_Resethelper($hash);
        }    
    }   
Log3 $name, 3, "$name/RAW: $msg - $err - $hash->{helper}{step}";
}



#####################################
#
# THZ_Resethelper() 
#
# Parameter hash
#
########################################################################################

sub THZ_Resethelper($) {
    my ($hash) = @_;
    $hash->{helper}{step}="";
    $hash->{helper}{cmdHex}="";
    $hash->{helper}{PARTIAL}="";     
}



sub THZ_Testloopapproach($) {
    my ($hash) = @_;
    my $cmd="sGlobal";
    #my $cmd="sHC1";
    my $cmdhash = $gets{$cmd};
    THZ_Write($hash,  "02");
    $hash->{helper}{step}="step0";
    $hash->{helper}{cmdHex}=THZ_encodecommand($cmdhash->{cmd2},"get");
    $hash->{helper}{PARTIAL}="";     
}
  
sub THZ_testtimer($) {
    my ($hash) = @_;
 my $counter=1;
 my $stringa = ("starttest \n");
 foreach my $a (keys %intAt) 
 {
 if ($intAt{$a}{FN} eq "THZ_GetRefresh")	
 	{
		$stringa = $stringa . ("timer ". $counter ." ARG". $intAt{$a}{ARG} ."fn " . $intAt{$a}{FN} ."\n") ;
		$counter+=1;
	}
 }
 Log3 $hash->{NAME}, 5, $stringa;
}

     
#####################################
#
# THZ_Ready($) - Cchecks the status
#
# Parameter hash
#
########################################################################################
sub THZ_Ready($) {
  my ($hash) = @_;
  if($hash->{STATE} eq "disconnected")
  { #RemoveInternalTimer(0, "THZ_GetRefresh"); #non necessario in THZ_getrefresh non vengono piu' rinnoovati
   #THZ_testtimer($hash);
  select(undef, undef, undef, 0.010); #equivalent to sleep 10ms
  #Log3 $hash->{NAME}, 3, "THZ_Ready: readyevent";
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
  my ($hash,  @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME}; 
  return "\"set $name\" needs at least two parameters: <device-parameter> and <value-to-be-modified>" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my $arg1 = "00:00";
  my ($err, $msg) =("", " ");
  my $cmdhash = $sets{$cmd};
  #return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets) if(!defined($cmdhash));
  if(!defined($cmdhash)) {
    my $setList;
    foreach my $key (sort keys %sets) {
      my $value = $sets{$key};
      $setList .= $key;
      #if (($value->{type} eq "0clean" or $value->{type} eq "1clean") and $value->{unit} eq "") {
      if ($value->{type} =~ /clean/ ) {
        #if (($value->{argMax} - $value->{argMin})<2 ) {$setList .= ":uzsuToggle," . join (",", ($value->{argMin} .. $value->{argMax})) . " ";}
        if (($value->{argMax} - $value->{argMin})<13 ) {$setList .= ":uzsuSelectRadio," . join (",", ($value->{argMin} .. $value->{argMax})) . " ";}
        else  					 {$setList .= ":textField ";}
        #else						 {$setList .= ":slider,$value->{argMin},1,$value->{argMax} ";}
        #else						 {$setList .= ":knob,min:$value->{argMin},max:$value->{argMax},step:1 " ;}
	  }
      elsif ($value->{type} eq "2opmode"){
        $setList .= ":" . join (",", (sort {lc $a cmp lc $b} values %OpMode)) . " ";
        #$setList .= ":uzsuSelectRadio," . join (",", (sort {lc $a cmp lc $b} values %OpMode)) . " ";
        #attr Mythz widgetOverride pOpMode:uzsuDropDown,automatic,standby
	  }
      #elsif ($value->{type} eq "9holy"){
        #$setList .= ":time ";
        # $setList .= ":textField ";
	  # }
      #elsif ($value->{type} eq "5temp") {
        #   $setList .= ":slider,$value->{argMin},0.1,$value->{argMax},1 "  ;
      	#$setList .= ":knob,min:$value->{argMin},max:$value->{argMax},step:0.1 "  ;
	    #$setList .= ":knob,min:$value->{argMin},max:$value->{argMax},step:0.1,angleOffset:-125,angleArc:250 "
	    #attr Mythz widgetOverride p01RoomTempDayHC1:knob,min:22,max:26,step:0.1,angleOffset:-125,angleArc:250
	    #attr Mythz widgetOverride p01RoomTempDayHC1:slider,$value->{argMin},0.1,$value->{argMax}
	    #attr Mythz widgetOverride p01RoomTempDayHC1:uzsuDropDown,21,29
	    #attr Mythz widgetOverride p01RoomTempDayHC1:uzsuSelectRadio,44,234,21
	 # }
      #elsif ($value->{type} eq "6gradient") {
        #   $setList .= ":slider,$value->{argMin},0.01,$value->{argMax},1 " ;
        #$setList .= ":knob,min:$value->{argMin},max:$value->{argMax},step:0.01 "  ;
	  #   }
      else {
        #$setList .= ":textField ";
      $setList .= " ";
      }
    }
    return "Unknown argument $cmd, choose one of  $setList";
  }
  
  return "\"set $name $cmd\" needs at least one further argument: <value-to-be-modified>" if(!defined($arg));
 
  
  
  my $cmdHex2 = $cmdhash->{cmd2};
  my $argMax = $cmdhash->{argMax};
  my $argMin = $cmdhash->{argMin};
  
  #-- check the parameter range
  if ($cmdhash->{type} =~ /ptime/) {          
    $arg1=undef;
    return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if (($arg ne "n.a.")  and ($arg !~ /^(?:\d|[01]\d|2[0-3]):[0-5]\d$/ )) ;
    }
  elsif ($cmdhash->{type} =~ /7prog|8party/) {          
    ($arg, $arg1)=split('--', $arg);
    return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if (($arg ne "n.a.") and ($arg1 ne "n.a.") and (($arg !~ /^(?:\d|[01]\d|2[0-3]):[0-5]\d$/ )  or ($arg1 !~ /^(?:\d|[01]\d|2[0-3]):[0-5]\d$/ )) ) ;
    }
  elsif ($cmdhash->{type} eq "2opmode") {
    $arg1=undef;
    $arg=$Rev_OpMode{$arg};
    return "Unknown argument $arg1: $cmd supports  " . join(" ", sort values %OpMode) 	if(!defined($arg));
    }
  else {
    $arg1=undef;
    return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg > $argMax) or ($arg < $argMin));
    }
  #--
  my $i=0;  my $parsingrule;
  THZ_AvoidCollisions($hash);
  my $parent = $cmdhash->{parent};
  #if I have a father read from it: important for older firmwares
  if(defined($parent) ) {
      my $parenthash=$gets{$parent};
      $cmdHex2 = $parenthash->{cmd2};	#overwrite $cmdHex2 with the parent
	  Log3 $hash->{NAME}, 5, "searching for parent; parenthash= $parenthash, parent = $parent, cmdHex2 = $cmdHex2  ";
      $cmdHex2=THZ_encodecommand($cmdHex2, "get");  #read before write the register
      ($err, $msg) = THZ_Get_Comunication($hash,  $cmdHex2);
      if (defined($err))     {
		 Log3 $hash->{NAME}, 3, "THZ_Set: error reading register: '$err'";
		 return ($msg ."\n msg " . $err);
      }
      substr($msg, 0, 2, ""); 		#remove the checksum from the head of the payload
      Log3 $hash->{NAME}, 5, "read before write from THZ: $msg";
      #--
      $parsingrule = $parsinghash{$parenthash->{type}};
      for (@$parsingrule) {
	      last if ((@$parsingrule[$i]->[0]) =~ m/$cmd/);
	      $i++;
      }
      select(undef, undef, undef, 0.25);
  }
  else {
    $msg =  $cmdHex2 . "0000";
    my $msgtype =$cmdhash->{type};
    $parsingrule = $parsinghash{$msgtype} if(defined($msgtype));
  }
  my $pos = @$parsingrule[$i]->[1] -2; #I removed the checksum
  my $len = @$parsingrule[$i]->[2];
  my $parsingtype = @$parsingrule[$i]->[3];
  my $dec = @$parsingrule[$i]->[4];
  Log3 $hash->{NAME}, 5, "write command (parsed element/pos/len/dec/parsingtype): $i / $pos / $len / $dec / $parsingtype";
  
  $arg *= $dec                                                  if ($dec != 1);
  $arg  = time2quaters($arg)                                    if ($parsingtype eq "quater");
  $arg= join('', (split(':', $arg)))                            if ($parsingtype eq "hex2time"); # only in firmware 2.x
  #$arg= eval(join('*100+', (split(':', $arg))))                 if ($parsingtype eq "hex2time"); #just in case the above does not work
  $arg=(hex(substr($msg, $pos, 1)) & (15-2**$1)) | (2**$1*$arg) if ($parsingtype =~ /bit(\d)/);
  $arg  = substr((sprintf(("%0".$len."X"), $arg)), (-1*$len)); #04X converts to hex and fills up 0s; for negative, it must be trunckated. 
  substr($msg, $pos, $len, $arg);
 
  if (defined($arg1))  {		#only in case of "8party" or "7prog" 
    $arg1  = time2quaters($arg1);
    $arg1  = substr((sprintf(("%02X"), $arg1)), -2);
    $pos = @$parsingrule[($i+1)]->[1] -2;
    substr($msg, $pos, $len, $arg1);
  }
  Log3 $hash->{NAME}, 5, "THZ_Set: '$cmd $arg $msg' ... Check if port is open. State = '($hash->{STATE})'";
  $cmdHex2=THZ_encodecommand($msg,"set");
  ($err, $msg) = THZ_Get_Comunication($hash,  $cmdHex2);
  #$err=undef;
  if (defined($err))  {
    Log3 $hash->{NAME}, 3, "THZ_Set: Error msg:  $err -- $cmdHex2 -> $msg";
    return($cmdHex2 . "-". $msg ."--" . $err);
    }
  else {
	select(undef, undef, undef, 0.25);
    if (defined($gets{$cmd})) {
        $msg=THZ_Get($hash, $name, $cmd);
    }
    else {
          $msg=$cmd.": OK";
    }
    #because of F8 reset introduced by andre topic=33211 msg695420
    #take care of program of the week
	if ($a[1] =~ /Mo-So/){
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/Mo-So/Mo-Fr/;	$msg.= "\n" . THZ_Set($hash, @a);
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/Mo-Fr/Sa-So/;	$msg.="\n" . THZ_Set($hash, @a);
	  }
	elsif ($a[1] =~ /Mo-Fr/)  	{
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_Mo-Fr_/_Mo_/;	$msg.="\n" . THZ_Set($hash, @a);
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_Mo_/_Tu_/ ;	$msg.="\n" . THZ_Set($hash, @a);
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_Tu_/_We_/ ;	$msg.="\n" . THZ_Set($hash, @a);
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_We_/_Th_/ ;	$msg.="\n" . THZ_Set($hash, @a);
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_Th_/_Fr_/ ;  	$msg.="\n" . THZ_Set($hash, @a);
	  }
	 elsif ($a[1] =~ /Sa-So/){
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_Sa-So_/_Sa_/; 	$msg.="\n" . THZ_Set($hash, @a);
	    select(undef, undef, undef, 0.05);
	    $a[1] =~ s/_Sa_/_So_/ ;  	$msg.="\n" . THZ_Set($hash, @a);
	  }
	#split _ mo-fr when [3] undefined do nothing, when mo-fr  chiama gli altri
        return ($msg);
  }
}



########################################################################################
#
# THZ_GetNB - NonBlocking Get parameter from heatpump
#
# Parameters: "name | command" (single string)
#
########################################################################################
sub THZ_GetNB($){
  my ($string) = @_;
  my ($name, $cmd) = split("\\|", $string);
  my $hash = $defs{$name};
  my $dev = $hash->{DeviceName};
  my $ret = DevIo_OpenDev($hash, 0, undef);         #open device in child process
  #($hash->{STATE}, $hash->{USBDev} , $hash->{TCPDev} , $hash->{conn} , $hash->{FD} , $selectlist{"$name.$dev"}) =  split("\\|", $hash->{connection});  
  #($hash->{STATE},  $hash->{TCPDev} ,  $hash->{FD} , $selectlist{"$name.$dev"}) =  split("\\|", $hash->{connection});
  #$selectlist{"$name.$dev"} = $hash;
  #open (MYFILE, '>>data.txt');
  #print MYFILE ($hash->{connection} . "\n");
  #close (MYFILE);
  if (defined($ret)) {
    Log3 $hash, 3, "[$name] THZ_GetNB: open device $hash->{DeviceName} error:$ret";
    return ("$name|$cmd|$ret");
  }
  my $msg = THZ_Get($hash, $name, $cmd);
  DevIo_CloseDev($hash);                            #close device in child process
  if ($msg =~ m/\n/m) {                             #error message from get contains \n
    return ("$name|$cmd|[ERROR]");
  }
  else {
    return ("$name|$cmd|$msg");
  }
}


########################################################################################
#
# THZ_GetNBDone - Finish Function
#
# Parameters: "name | command | message" (single string)
#
########################################################################################
sub THZ_GetNBDone($){
  my ($string) = @_;
  my ($name, $cmd, $msg) = split("\\|", $string);
  my $hash = $defs{$name};
  Log3 $hash, 4, "[$name] THZ_GetNBDone: $cmd - $msg";
  readingsSingleUpdate($hash, $cmd, $msg, 1) if ($msg ne "[ERROR]");
  delete($hash->{helper}{RUNNING_PID}) if (defined($hash->{helper}{RUNNING_PID}));
  DevIo_OpenDev($hash, 1, undef); #  if($hash->{STATE} ne "opened");         #reopen device for parent process
  return;
 }

 
########################################################################################
#
# THZ_GetNBAbort - Abort Function
#
# Parameter: hash
#
########################################################################################
sub THZ_GetNBAbort($){
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID}) if (defined($hash->{helper}{RUNNING_PID}));
  DevIo_OpenDev($hash, 1, undef);#   if($hash->{STATE} ne "opened");         #reopen device for parent process
  Log3 $hash->{NAME}, 3, "BlockingCall for ".$hash->{NAME}." was aborted";
  return;
}


########################################################################################
#
# THZ_AvoidCollisions - prevents collisions between parent and child process is used at the beginning of THZ_Get and THZ_Set
#
# Parameter: hash
#
########################################################################################
sub THZ_AvoidCollisions($) {
    my ($hash) = @_;
    # if child found, wait 0,25 second, and kill it
    # maybe after 1 second child would have finished, but its THZ_GetNBDone is blocked
    if (defined($hash->{helper}{RUNNING_PID})){
    select(undef, undef, undef, 0.25);     
    BlockingKill($hash->{helper}{RUNNING_PID});
    delete($hash->{helper}{RUNNING_PID});
    DevIo_OpenDev($hash, 1, undef); #if($hash->{STATE} ne "opened");
    #reset heatpump
    THZ_Write($hash,  "10"); 		    	
    select(undef, undef, undef, 0.1);
    THZ_ReadAnswer($hash);	
    THZ_Write($hash,  "10");
    select(undef, undef, undef, 0.1);
    Log3 $hash->{NAME}, 3, "Possible collision in ".$hash->{NAME}." was aborted";
    }
    return;
}





#####################################
#
# THZ_Get - provides a method for polling the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Get($@) {
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
  my ($err, $msg2) =("", " ");
  
  if ($cmd eq "debug_read_raw_register_slow") {
    THZ_debugread($hash);
    return ("all raw registers read and saved");
  }
  if ($cmd eq "zBackupParameters") {
    $err=THZ_backup_readings($hash);
    return $err;
  }
  
  
  my $cmdhash = $gets{$cmd};
  #return "Unknown argument $cmd, choose one of " .   join(" ", sort keys %gets) if(!defined($cmdhash));
  if(!defined($cmdhash)) {
    my $getList;
    foreach my $key (sort keys %gets) {$getList .= "$key:noArg ";}
    $getList .= "zBackupParameters:noArg";
    return "Unknown argument $cmd, choose one of  $getList";
  }
  
  Log3 $hash->{NAME}, 5, "THZ_Get: Try to get '$cmd'";
  THZ_AvoidCollisions($hash);
  my $parent = $cmdhash->{parent};	#if I have a father read from it
  if(defined($parent) ) {
      my ($seconds, $microseconds) = gettimeofday();
      $seconds= abs($seconds - time_str2num(ReadingsTimestamp($name, $parent, "1970-01-01 01:00:00")));
      my $risultato=ReadingsVal($name, $parent, 0);
      $risultato=THZ_Get($hash, $name, $parent) if ($seconds > 20 );	#update of the parent: if under 20sec use the current value
      #$risultato=THZ_Parse1($hash,"B81700C800BE00A001C20190006402010000E601D602");
      my $parenthash=$gets{$parent}; my $parsingrule = $parsinghash{$parenthash->{type}};
      my $i=0; 
      for  (@$parsingrule) {
      last if ((@$parsingrule[$i]->[0]) =~ m/$cmd/);
	$i++;}
      $msg2=(split ' ', $risultato)[$i*2+1];
      Log3 $hash->{NAME}, 5, "THZ_split: $msg2 --- $risultato";
  }
  else { 
      my $cmdHex2 = $cmdhash->{cmd2};
      if(defined($cmdHex2) ) {
          #empty
          ($err, $msg2) = THZ_Get_Comunication($hash, THZ_encodecommand($cmdHex2,"get") );
          if (defined($err))     {
             Log3 $hash->{NAME}, 3, "THZ_Get: Error msg2:  $err -- $cmdHex2 -> $msg2";
             return ($msg2 ."\n msg2 " . $err);
          }
          $msg2 = THZ_Parse1($hash,$msg2);
      }
  
      my $cmdHex3 = $cmdhash->{cmd3};
      if(defined($cmdHex3)) {
          my $msg3= " ";
          #empty 
          ($err, $msg3) = THZ_Get_Comunication($hash,  THZ_encodecommand($cmdHex3,"get"));
           if (defined($err))     {
                Log3 $hash->{NAME}, 3, "THZ_Get: Error msg3:  $err -- $cmdHex3 -> $msg3";
                 return ($msg3 ."\n msg3 " . $err);
          }
          $msg2 = THZ_Parse1($hash,$msg3) * 1000 + $msg2  ;
      }	            		
  } 
  my $unit = $cmdhash->{unit};
  $msg2 = $msg2 .  $unit  if(defined($unit)) ;
    
    
  my $activatetrigger =1;
  readingsSingleUpdate($hash, $cmd, $msg2, $activatetrigger);
  return ($msg2);	       
}




#####################################
#
# THZ_Get_Comunication- provides a method for comunication called from THZ_Get or THZ_Set
#
# Parameter hash and CMD2 or 3 
#
########################################################################################
sub THZ_Get_Comunication($$) {
  my ($hash, $cmdHex) = @_;
  my ($err, $msg) =("", " ");
  Log3 $hash->{NAME}, 5, "THZ_Get_Comunication: Check if port is open. State = '($hash->{STATE})'";
  if (!(($hash->{STATE}) eq "opened"))  { return("closed connection", "");}
  
  select(undef, undef, undef, 0.001);
  THZ_Write($hash,  "02"); 			# step0 --> STX start of text 	
  ($err, $msg) = THZ_ReadAnswer($hash);

#Expectedanswer0    is  "10"  DLE data link escape

  if ($msg ne "10")    {$err .= " THZ_Get_Com: error found at step0 $msg"; $err .=" NAK!!" if ($msg eq "15"); select(undef, undef, undef, 0.1); return($err, $msg) ;}
  else  {
     THZ_Write($hash,  $cmdHex); 		# step1 --> send request   SOH start of heading -- Null 	-- ?? -- DLE data link escape -- EOT End of Text
     ($err, $msg) = THZ_ReadAnswer($hash);
  }
  
  if ((defined($err)))  { $err .=  " THZ_Get_Com: error found at step1 "; select(undef, undef, undef, 0.1); return($err, $msg) ;}

# Expectedanswer1     is "1002",		DLE data link escape -- STX start of text    

  if ($msg eq "10") 	{ ($err, $msg) = THZ_ReadAnswer($hash);}
  elsif ($msg eq "15") 	{ $err .=  " THZ_Get_Com: error found at step1  NAK!! "; select(undef, undef, undef, 0.1); return($err, $msg) ;}
  if ($msg eq "1002" || $msg eq "02") {
    THZ_Write($hash,  "10"); 		    	# step2 send  DLE data link escape  
    ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer2 // read from the heatpump
    THZ_Write($hash,  "10");  
  }
  
  if ((defined($err)))  { $err .= " THZ_Get_Com: error found at step2"; select(undef, undef, undef, 0.1);} 
  else  {($err, $msg) = THZ_decode($msg);} 	#clean up and remove footer and header
  return($err, $msg) ;
}










#####################################
#
# THZ_ReadAnswer- provides a method for simple read
#
# Parameter hash and command to be sent to the interface
#
########################################################################################
sub THZ_ReadAnswer($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $hash->{NAME}, 5, "$name start Function THZ_ReadAnswer";
	select(undef, undef, undef, 0.025) if( $^O =~ /Win/ ); ###delay of 25 ms for windows-OS, because SimpleReadWithTimeout does not wait
	my $rtimeout = (AttrVal($name, "simpleReadTimeout", "0.5")) / 2; #added for Andre he would like to have 8/2 second.
    $rtimeout = 0.5 if (AttrVal($name, "nonblocking", "0") eq 0); # set to 0.5s is nonblocking disabled
    my $buf = DevIo_SimpleReadWithTimeout($hash, $rtimeout);
    $buf = DevIo_SimpleReadWithTimeout($hash, $rtimeout) if(!defined($buf)) ; #added for karl msg468515
    return ("THZ_ReadAnswer: InterfaceNotRespondig. Maybe too slow", "") if(!defined($buf)) ;
	my $data =  uc(unpack('H*', $buf));
	my $count =1;
	my $countmax = 60;
	while (( (length($data) == 1) or (($data =~ m/^01/) and ($data !~ m/1003$/m ))) and ($count <= $countmax)){ 
	  select(undef, undef, undef, 0.005) if( $^O =~ /Win/ ); ###delay of 5 ms for windows-OS, because SimpleReadWithTimeout does not wait
	  my $buf1 = DevIo_SimpleReadWithTimeout($hash, 0.02);
	  Log3($hash->{NAME}, 5, "double read $count activated $data");
	  if(defined($buf1)) {
	    $buf .=  $buf1 ;
	    $data =  uc(unpack('H*', $buf));
	    Log3($hash->{NAME}, 5, "double read $count result with buf1  $data");
	    $count ++;
	    }
	  else{ $count += 5; }
	}
	return ("THZ_ReadAnswer: Interface max repeat limited to $countmax ", $data) if ($count == ($countmax +1));
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
# bitmap2string - convert from bitmap to concatenated string
#
# parameter: bitmap representing yes/no, hashref to stringmapping
# returns: concatenated string
#
########################################################################################
sub bitmap2string($$) {
  my($bitmap, $href) = @_;
  my $idx = 1;
  my $res = "";
  foreach my $bit (split //, $bitmap) {
    $res .= $href->{$idx} if ($bit);
    $idx++;
  }
  return $res;
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
  my $find = "1010";    # - each sequece 10 10 must be replaced with single byte 10
  my $replace = "10";
  $message_orig=THZ_replacebytes($message_orig, $find, $replace);
  $find = "2B18";       # - each sequece 2B 18 must be replaced with single byte 2B
  $replace = "2B";
  $message_orig=THZ_replacebytes($message_orig, $find, $replace);
  
  #Check if answer is NAK
  if (length($message_orig) == 2 && $message_orig eq "15") {
    return("decode: NAK received from device",$message_orig);
  }
  
  #check header and if ok 0100, check checksum and return the decoded msg
  my $header = substr($message_orig,0,4);
  if ($header eq "0100")  {
    if (THZ_checksum($message_orig) eq substr($message_orig,4,2)) {
      $message_orig =~ /0100(.*)1003/; 
      my $message = $1;
      return (undef, $message);
    }
    else {return(THZ_checksum($message_orig) . "decode: crc_error in answer", $message_orig)};
  }
  if ($header eq "0101")  { return ("decode: timing issue", $message_orig);}
  if ($header eq "0103")  { return ("decode: command not known", $message_orig);}
  if ($header eq "0102")  { return("decode: CRC error in request", $message_orig);}
  if ($header eq "0104")  { return("decode: UNKNOWN Register REQUEST", $message_orig);}
  if ($header eq "0180")  { return(undef, $message_orig);}
  
  return("decode: new unknown answer " , $message_orig);
}


###############################
#added by jakob do not know if needed
#
###############################

local $SIG{__WARN__} = sub {
  my $message = shift;
  
  if (!defined($internalHash)) {
    Log3 "Mythz", 3, "EXCEPTION in THZ: '$message'";
  }
  else
  {
    Log3 $internalHash->{NAME},3, "EXCEPTION in THZ: '$message'";
  }  
};



#######################################
#THZ_Parse1($) could be used in order to test an external config file; I do not know if I want it
#e.g. {THZ_Parse1(undef,"F70B000500E6")}
#######################################
sub THZ_Parse1($$) {
  my ($hash,$message) = @_;  
  Log3 $hash->{NAME}, 5, "Parse message: $message";	  
  my $length = length($message);
  Log3 $hash->{NAME}, 5, "Message length: $length";
  my $parsingcmd = substr($message,2,2);
  $parsingcmd = substr($message,2,6) if (($parsingcmd =~ m/(0A|0B|0C)/) and (AttrVal($hash->{NAME}, "firmware" , "4.39")  !~ /^2/) );
  my $msgtype;
  my $parsingrule;
  my $parsingelement;
  # search for the type in %gets
     foreach  my $cmdhash  (values %gets) {
    if (defined ($cmdhash->{cmd2}) and ($cmdhash->{cmd2} eq $parsingcmd))
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
      	Log3 $hash->{NAME}, 5, "THZ_Parsing: offset($positionInMsg) + length($lengthInMsg) is longer then message : '$message'"; 
      	#$message.= '0' x ($positionInMsg + $lengthInMsg - length($message)); # fill up with 0s to the end if needed
      	#line above redundant because of  else below added 9.2018; 
        #Log3 $hash->{NAME},3, "after: '$message'"; 
      }
      else {
          my $value = substr($message, $positionInMsg, $lengthInMsg);
          if    ($Type eq "hex")		{$value= hex($value);}
          elsif ($Type eq "year")		{$value= hex($value)+2000;}
          elsif ($Type eq "hex2int")	{$value= hex2int($value);}
          elsif ($Type eq "turnhexdate")	{$value= substr($value, 2,2) . substr($value, 0,2); $value= sprintf("%02u.%02u", hex($value)/100, hex($value)%100); }
          elsif ($Type eq "hexdate")	{$value= sprintf("%02u.%02u", hex($value)/100, hex($value)%100) ;}
          #elsif ($Type eq "turnhex2time")	{$value= sprintf(join(':', split("\\.", hex(substr($value, 2,2) . substr($value, 0,2))/100))) ;}
          #elsif ($Type eq "hex2time")	{$value= sprintf(join(':', split("\\.", hex(substr($value, 0,2) . substr($value, 2,2))/100))) ;}
          elsif ($Type eq "turnhex2time")	{$value= substr($value, 2,2) . substr($value, 0,2); $value= sprintf("%02u:%02u", hex($value)/100, hex($value)%100); }
          elsif ($Type eq "hex2time")	{$value= sprintf("%02u:%02u", hex($value)/100, hex($value)%100) ;}
          elsif ($Type eq "swver")		{$value= sprintf("%01u.%02u", hex(substr($value, 0,2)), hex(substr($value, 2,2)));}
          elsif ($Type eq "hex2ascii")	{$value= uc(pack('H*', $value));}
          elsif ($Type eq "opmode")		{$value= $OpMode{hex($value)};}
          elsif ($Type eq "opmode2")	{$value= $opMode2{hex($value)};}
          elsif ($Type eq "opmodehc")	{$value= $OpModeHC{hex($value)};}
          elsif ($Type eq "esp_mant") 	{$value= sprintf("%.3f", unpack('f', pack( 'L',  reverse(hex($value)))));}
          elsif ($Type eq "somwinmode")	{$value= $SomWinMode{($value)};}
          #elsif ($Type eq "hex2wday")	{$value= bitmap2string(unpack('b7', pack('H*',$value)), \%weekdaymap);}
          elsif ($Type eq "hex2error")	{$value= bitmap2string(unpack('b32', pack('H*',$value)), \%faultmap);}
          elsif ($Type eq "weekday")	{$value= $weekday{($value)};}
          elsif ($Type eq "faultmap")	{$value= $faultmap{(hex($value))};}
          elsif ($Type eq "quater")		{$value= quaters2time($value);}
          elsif ($Type eq "bit0")		{$value= (hex($value) &  0b0001) / 0b0001;}
          elsif ($Type eq "bit1")		{$value= (hex($value) &  0b0010) / 0b0010;}
          elsif ($Type eq "bit2")		{$value= (hex($value) &  0b0100) / 0b0100;}
          elsif ($Type eq "bit3")		{$value= (hex($value) &  0b1000) / 0b1000;}
          elsif ($Type eq "nbit0")		{$value= 1-((hex($value) &  0b0001) / 0b0001);}
          elsif ($Type eq "nbit1")		{$value= 1-((hex($value) &  0b0010) / 0b0010);}
          elsif ($Type eq "raw")		{;}
          elsif ($Type eq "n.a.")		{$value= "n.a.";}
          $value = $value/$divisor if ($divisor != 1); 
          $ParsedMsg .= $parsingtitle . $value; 
        }
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
  my @numbers=('01', '09', '16', 'D1', 'D2', 'E8', 'E9', 'F2', 'F3', 'F4', 'F5', 'F6', 'F8', 'FB', 'FC', 'FD', 'FE', 'FF');
  #my @numbers=('FB',  '0A0BA3', '0A057C', '0A057D', '0A057E', '0A057F' );
  #my @numbers=(1, 3, 4, 5, 8, 12, 13, 14, 15, 17, 18, 19, 20, 22, 26, 39, 40, 82, 83, 86, 87, 96, 117, 128, 239, 265, 268, 269, 270, 271, 274, 275, 278, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 297, 299, 317, 320, 354, 384, 410, 428, 440, 442, 443, 444, 445, 446, 603, 607, 612, 613, 634, 647, 650, 961, 1385, 1386, 1387, 1388, 1389, 1391, 1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, 1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, 1410, 1411, 1412, 830, 1414, 1415, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465, 1466, 1467, 1468, 1469, 1470, 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481, 2970, 2971, 2974, 2975, 2976, 2977, 2978, 2979, 1413, 1426, 1427, 474, 1499, 757, 758, 952, 955, 1501, 1502, 374, 1553, 1554, 1555, 272, 1489, 1490, 1491, 1492, 1631, 933, 934, 1634, 928, 718, 64990, 64991, 64992, 64993, 2372, 2016, 936, 937, 938, 939, 1632, 2350, 2351, 2352, 2353, 2346, 2347, 2348, 2349, 2334, 2335, 2336, 2337, 2330, 2331, 2332, 2333, 2344, 2345, 2340, 2341, 942, 943, 944, 945, 328, 2029, 2030, 2031, 2032, 2033);
  #my @numbers=(1, 3, 12, 13, 14, 15, 19, 20, 22, 26, 39,  82, 83, 86, 87, 96, 239, 265, 268, 274, 278, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 320, 354, 384, 410, 428, 440, 442, 443, 444, 445, 446, 613, 634, 961, 1388, 1389, 1391, 1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, 1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409,  1414, 1415, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465, 1466, 1467, 1468, 1470, 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 2970, 2971, 2975, 2976, 2977, 2978, 2979, 474, 1499, 757, 758, 952, 955, 1501, 1502, 374, 1553, 1554, 272, 1489, 1491, 1492, 1631, 718, 64990, 64991, 64992, 64993, 2372, 2016, 936, 937, 938, 939, 1632, 2350, 2351, 2352, 2353, 2346, 2347, 2348, 2349, 2334, 2335, 2336, 2337, 2330, 2331, 2332, 2333, 2344, 2345, 2340, 2341, 942, 943, 944, 945, 328, );
 # my @numbers=(239, 410, 603, 607, 634, 830, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1467, 1468, 1469, 1478, 1479, 1480, 1481, 2970, 2971, 2974, 2975, 2976, 2977, 2978, 2979, 1413, 1426, 1427, 474, 1501, 1502, 374, 1631, 718, 2372, 328);
  #my @numbers = (1..256);
  #my @numbers = (1..65535);
 # my @numbers = (1..3179);
  my $indice= "FF";
  unlink("data.txt"); #delete  debuglog
  #my $i=0;
  foreach $indice(@numbers) {
   # $i=$i+1;
   #my $cmd = sprintf("%02X", $indice);
  #  my $cmd = sprintf("%04X", $indice);
    #my $cmd = "0A" . sprintf("%04X",  $indice);
    my $cmd = $indice;
    my $cmdHex2 = THZ_encodecommand($cmd,"get"); 
    #($err, $msg) = THZ_Get_Comunication($hash,  $cmdHex2);
    #STX start of text
    THZ_Write($hash,  "02");
    ($err, $msg) = THZ_ReadAnswer($hash);
    #select(undef, undef, undef, (0.05*$i));
    #if you wait here more than 600ms connection dropped
    # send request
    THZ_Write($hash,  $cmdHex2);
    #select(undef, undef, undef, (0.05*$i));
    ($err, $msg) = THZ_ReadAnswer($hash);
    #expected 1002; if not following if takes care
    if ($msg eq "10") {
      select(undef, undef, undef, 0.01);
      ($err, $msg) = THZ_ReadAnswer($hash);
     }  
    # ack datatranfer and read from the heatpump        
    select(undef, undef, undef, 0.015);
    THZ_Write($hash,  "10");
    select(undef, undef, undef, 0.001);
    ($err, $msg) = THZ_ReadAnswer($hash);
    THZ_Write($hash,  "10");

    if (defined($err))  {return ($msg ."\n" . $err);}
    else {   #clean up and remove footer and header
	($err, $msg) = THZ_decode($msg);
	if (defined($err)) {
		  $msg = THZ_Parse1($hash,$msg);
		  $msg=$cmdHex2 ."-". $msg ."-". $err;} 
		  my $activatetrigger =1;
		 # readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
		  open (MYFILE, '>>data.txt');
		  print MYFILE ($cmdHex2 ."-". $cmd . "-" . $msg . "\n");
		  close (MYFILE);
		  #Log3 $hash->{NAME}, 3, "$cmd  -  $msg";
    }    
    select(undef, undef, undef, 0.2); 
  }
}

#######################################
#THZ_Attr($) 
#in case of change of attribute starting with interval_ refresh all
########################################################################################
sub THZ_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  
  $attrVal = "4.39" if (($cmd eq "del") and ($attrName eq "firmware"));
  
  if ( $attrName eq "firmware" )  {  
      if ($attrVal eq "2.06") {
         %sets = %sets206;
         %gets = (%getsonly2xx, %getsonly206, %sets);
         THZ_Refresh_all_gets($hash);
      }
      elsif ($attrVal eq "2.14") {
        %sets = (%sets206, %setsonly214);
        %gets = (%getsonly2xx, %getsonly214, %sets206);
        THZ_Refresh_all_gets($hash);
      }
      elsif ($attrVal eq "5.39") {
        %sets=(%sets439539common, %sets539only);
        %gets=(%getsonly539, %sets);
        THZ_Refresh_all_gets($hash);
      }
      elsif ($attrVal eq "4.39technician") {
        %sets=(%sets439539common, %sets439only, %sets439technician);
        %gets=(%getsonly439, %sets);
        THZ_Refresh_all_gets($hash);
      }
      else { #in all other cases I assume $attrVal eq "4.39" cambiato nella v0140
        %sets=(%sets439539common, %sets439only);
        %gets=(%getsonly439, %sets);
        THZ_Refresh_all_gets($hash);
      }
  }
  
  
  if( $attrName =~ /^interval_/ ) {
  #DevIo_CloseDev($hash);
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
  RemoveInternalTimer(0, "THZ_GetRefresh");
  #THZ_RemoveInternalTimer("THZ_GetRefresh");
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
  
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
  DevIo_CloseDev($hash); 
  return undef;
}




##########################################
# nearest rounds to the nearrest value multiple of the first argumen
# nearest_ceil(10, 45); --> 50
# nearest_floor(10, 45); --> 40
# for all other values outside the middlevalues they take he nearest
# modified takes as an argument the function to be called, not the argument
########################################################################################
sub nearest_ceil($$) {
    my $targ = abs(shift);
    my $Math1 = 0.5000000000003;
    my @res  = map { $targ * POSIX::floor(($_ + $Math1 * $targ) / $targ) } @_;

    return wantarray ? @res : $res[0];
}


sub nearest_floor($$) {
    my $targ = abs(shift);
    my $Math1 = 0.5000000000003;
    my @res  = map { $targ * POSIX::ceil(($_ - $Math1 * $targ) / $targ) } @_;

    return wantarray ? @res : $res[0];
}






##########################################
# THZ_RemoveInternalTimer($) 
# modified takes as an argument the function to be called, not the argument
########################################################################################
#sub THZ_RemoveInternalTimer($){
#  my ($callingfun) = @_;
#  foreach my $a (keys %intAt) {
#    delete($intAt{$a}) if($intAt{$a}{FN} eq $callingfun);
#  }
#}

################################
#

sub function_heatSetTemp($$) {
  my ($start, $stop) = @_;
  my ($p13GradientHC1, $p14LowEndHC1, $p15RoomInfluenceHC1);
  my $pOpMode = " ";

  my $devname; #normally Mythz but could be defined differently
  foreach   (keys %defs) { 
  $devname=$_;
  last if(($defs{$_}{TYPE}) =~ "THZ");
  }

  if (AttrVal($devname, "firmware" , "4.39")  =~ /^2/ )  {
    ($p13GradientHC1, $p14LowEndHC1, $p15RoomInfluenceHC1) = (split ' ',ReadingsVal($devname,"pHeat1",0))[1,3,5];
  }  
  else {
  $pOpMode = ReadingsVal($devname,"pOpMode"," ");
  $p13GradientHC1 	  = ReadingsVal($devname,"p13GradientHC1",0.4);
  $p15RoomInfluenceHC1 = (split ' ',ReadingsVal($devname,"p15RoomInfluenceHC1",0))[0];
  $p14LowEndHC1 	  = (split ' ',ReadingsVal($devname,"p14LowEndHC1",0))[0];
  }
  my ($heatSetTemp, $roomSetTemp, $insideTemp) = (split ' ',ReadingsVal($devname,"sHC1",0))[11,21,27];
  my $outside_tempFiltered =(split ' ',ReadingsVal($devname,"sGlobal",0))[65];
  if (!$roomSetTemp) {
  $insideTemp=23.8 ; $roomSetTemp = 19.5; $p13GradientHC1 = 0.31; $heatSetTemp = 15; $p15RoomInfluenceHC1 = 80;
  $pOpMode ="DEMO: no data";
  $outside_tempFiltered = 0; $p14LowEndHC1 =0.5; 
  }

  my $a= 0.7 + ($roomSetTemp * (1 + $p13GradientHC1 * 0.87)) + $p14LowEndHC1 + ($p15RoomInfluenceHC1 * $p13GradientHC1 * ($roomSetTemp - $insideTemp) /10); 
  my $a1= 0.7 + ($roomSetTemp * (1 + $p13GradientHC1 * 0.87)) + $p14LowEndHC1;
  my $b= -14 * $p13GradientHC1 / $roomSetTemp; 
  my $c= -1 * $p13GradientHC1 /75;
  
  my $Simul_heatSetTemp; my $Simul_heatSetTemp_simplified;  my @ret; 
  foreach ($start..$stop) {
   my $tmp =$_ * $_ * $c + $_ * $b;
   $Simul_heatSetTemp 		 = sprintf("%.1f", maxNum(5,( $tmp + $a)));
   #$Simul_heatSetTemp 		 =  8 if ($pOpMode eq "DHWmode"); # DHWmode is always at 8 grad C 
   $Simul_heatSetTemp_simplified = sprintf("%.1f", maxNum(5,($tmp + $a1)));
   push(@ret, [$_, $Simul_heatSetTemp, $Simul_heatSetTemp_simplified]);
  }
  my $titlestring =  'roomSetTemp=' . $roomSetTemp . '°C p13GradientHC1=' . $p13GradientHC1 . ' p14LowEndHC1=' . $p14LowEndHC1  .  'K p15RoomInfluenceHC1=' . $p15RoomInfluenceHC1 . "% insideTemp=" . $insideTemp .'°C';
  return (\@ret, $titlestring, $heatSetTemp, $outside_tempFiltered, $pOpMode);
}

#####################################
# sub THZ_PrintcurveSVG
# plots heat curve
#define wl_hr weblink htmlCode {THZ_PrintcurveSVG}
# da mettere dentro lo style per funzionare sopra        svg      { height:200px; width:800px;}
#define wl_hr2 weblink htmlCode <div class="SVGplot"><embed src="/fhem/THZ_PrintcurveSVG/" type="image/svg+xml" width="800" height="160" name="wl_7"/></div> <a href="/fhem?detail=wl_hr2">wl_hr2</a><br>
#####################################

sub THZ_PrintcurveSVG {
my ($ycurvevalues, $titlestring, $heatSetTemp, $outside_tempFiltered, $pOpMode) = function_heatSetTemp(-15,20);
my $v0min = minNum(15, ($ycurvevalues->[33][1]), ($ycurvevalues->[33][2]), $heatSetTemp);	#lower offset than 15, if out of scale
$v0min = maxNum(5, nearest_ceil(5, $v0min));					#start only from a multiple of 5, but do not go below 5
my $vstep= 5;
$vstep= 10 if ((($ycurvevalues->[0][1])>($v0min+4*$vstep)) or (($ycurvevalues->[0][2])>($v0min+4*$vstep))); #increase step, if out of scale
my $v1=$v0min+$vstep; my $v2=$v1+$vstep; my $v3=$v2+$vstep; my $v4=$v3+$vstep;
my $ret =  <<'END';
<?xml version="1.0" encoding="UTF-8"?> <!DOCTYPE svg> <svg width="800" height="164" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" >
<style type="text/css"><![CDATA[
text       { font-family:Times; font-size:12px; }
text.title { font-size:14px; }
text.copy  { text-decoration:underline; stroke:none; fill:blue;    }
text.paste { text-decoration:underline; stroke:none; fill:blue;    }
polyline { stroke:black; fill:none; }
.border  { stroke:black; fill:url(#gr_bg); }
.vgrid   { stroke:gray;  stroke-dasharray:2,6; }
.hgrid   { stroke:gray;  stroke-dasharray:2,6; }
.pasted  { stroke:black; stroke-dasharray:1,1; }
.l0 { stroke:red;     }  text.l0 { stroke:none; fill:red;     } 
.l1 { stroke:green;   }  text.l1 { stroke:none; fill:green;   }
.l3 { stroke:blue;   }  text.l3 { stroke:none; fill:blue;   }
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
<rect x="48"  y="19.2" width="704" height="121.6" rx="8" ry="8" fill="none" class="border"/>
<text x="12"  y="80" text-anchor="middle" class="ylabel" transform="rotate(270,12,80)">HC1 heat SetTemp °C</text>
<text x="399" y="163.5" class="xlabel" text-anchor="middle">outside temperature filtered °C</text>
<text x="44"  y="155" class="ylabel" text-anchor="middle">-15</text>
<text x="145" y="155" class="ylabel" text-anchor="middle">-10</text>	<polyline points="145,19 145,140" class="hgrid"/>
<text x="246" y="155" class="ylabel" text-anchor="middle">-5</text>		<polyline points="246,19 246,140" class="hgrid"/>
<text x="347" y="155" class="ylabel" text-anchor="middle">0</text>   	<polyline points="347,19 347,140" class="hgrid"/>
<text x="448" y="155" class="ylabel" text-anchor="middle">5</text>   	<polyline points="448,19 448,140" class="hgrid"/>
<text x="549" y="155" class="ylabel" text-anchor="middle">10</text>  	<polyline points="549,19 549,140" class="hgrid"/>
<text x="650" y="155" class="ylabel" text-anchor="middle">15</text>  	<polyline points="650,19 650,140" class="hgrid"/>
<text x="751" y="155" class="ylabel" text-anchor="middle">20</text>  	<polyline points="751,19 751,140" class="hgrid"/>
<g>
END

$ret .= '<polyline points="44,140 49,140"/> <text x="39" y="144" class="ylabel" text-anchor="end">' . $v0min . '</text>';
$ret .= '<polyline points="44,110 49,110"/> <text x="39" y="114" class="ylabel" text-anchor="end">' . $v1    . '</text>';
$ret .= '<polyline points="44,80 49,80"/>   <text x="39" y="84" class="ylabel" text-anchor="end">'  . $v2    . '</text>';
$ret .= '<polyline points="44,49 49,49"/>   <text x="39" y="53" class="ylabel" text-anchor="end">'  . $v3    . '</text>';
$ret .= '<polyline points="44,19 49,19"/>   <text x="39" y="23" class="ylabel" text-anchor="end">'  . $v4    . '</text>';
$ret .= '</g> <g>';
$ret .= '<polyline points="751,140 756,140"/> <text x="760" y="144" class="ylabel">'. $v0min .'</text>';
$ret .= '<polyline points="751,110 756,110"/> <text x="760" y="114" class="ylabel">'. $v1    .'</text>';
$ret .= '<polyline points="751,80 756,80"/>   <text x="760" y="84" class="ylabel">' . $v2    .'</text>';
$ret .= '<polyline points="751,49 756,49"/>   <text x="760" y="53" class="ylabel">' . $v3    .'</text>';
$ret .= '<polyline points="751,19 756,19"/>   <text x="760" y="23" class="ylabel">' . $v4    .'</text>';
$ret .= '</g>' ."\n";


#labels ######################
$ret .= '<text line_id="line_1" x="70" y="100" class="l1"> --- heat curve with insideTemp correction</text>' ;
$ret .= '<text line_id="line_3" x="70" y="115" class="l3"> --- heat curve simplified</text>' ;
$ret .= '<text  line_id="line_0" x="70" y="130"  class="l0"> --- working point: '; 
$ret .= 'outside_tempFiltered=' . $outside_tempFiltered . '°C heatSetTemp=' . $heatSetTemp . '°C </text>';
$ret .= '<text line_id="line_3" x="650" y="50" class="title"> -'. $pOpMode . '- </text>' ." \n" ;

#title ######################
$ret .= '<text id="svg_title" x="400" y="14.4" class="title" text-anchor="middle">';
$ret .=  $titlestring .' </text>' . "\n";

#point ######################
$ret .='<polyline id="line_0"   style="stroke-width:2" class="l0" points="';
my ($px,$py) = (sprintf("%.1f", (($outside_tempFiltered+15)*(750-49)/(15+20)+49)),sprintf("%.1f", (($heatSetTemp-$v4)*(140-19)/($v0min-$v4)+19))); 
$ret.= ($px-3) . "," . ($py)   ." " . ($px)  . "," . ($py-3) ." " . ($px+3) . "," . ($py) ." " . ($px)   . "," . ($py+3)  ." " . ($px-3)   . "," . ($py)  ." " . '"/>' . "\n";

#curve with inside temperature correction ######################
$ret .='<polyline id="line_1"  title="Heat Curve with insideTemp correction" style="stroke-width:1" class="l1" points="';
foreach (@{$ycurvevalues}) {
$ret.= (sprintf("%.1f", ($_->[0]+15)*(750-49)/(15+20)+49) ). "," . sprintf("%.1f", (($_->[1]-$v4)*(140-19)/($v0min-$v4)+19)) ." ";
}
$ret .= '"/> ' . "\n";

#curve without inside temperature correction ######################
$ret .='<polyline id="line_3"  title="Heat Curve simplified" style="stroke-width:1" class="l3" points="';
foreach (@{$ycurvevalues}) {
$ret.= (sprintf("%.1f", ($_->[0]+15)*(750-49)/(15+20)+49) ). "," . sprintf("%.1f", (($_->[2]-$v4)*(140-19)/($v0min-$v4)+19)) ." ";
}
$ret .= '"/> ' . "\n";
$ret .= '</svg>';

my $FW_RETTYPE = "image/svg+xml";
return ($FW_RETTYPE, $ret);
}






sub THZ_detailFn(@){
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d}; #$d is the name of the defined device 
  return '<div class="SVGplot"><embed src="/fhem/THZ_PrintcurveSVG/" type="image/svg+xml"  name="wl_hr22"/></div> <br>';
}

#####################################
sub THZ_backup_readings($){
  my ($hash) = @_;
  return "No statefile specified" if(!$attr{global}{statefile});
  my $backupfile=$attr{global}{statefile};
  my $t = localtime;
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  $month++;
  $year+=1900;
  #$year+=1900 - 2000;
  my $replacestr= "$hash->{NAME}-$year-$month-$mday.backup"; 
  $backupfile=~ s/fhem.save/$replacestr/g;  #saving to statefile path
  if(!open(BAFH, ">$backupfile")) {
    my $msg = "WriteStateFile: Cannot open $backupfile: $!";
    Log3 $hash->{NAME},3, $msg;
    return $msg;
  }
  print BAFH "#$t\n";
  my $r = $hash->{READINGS};
  foreach my $c (sort keys %{$r}) {
    my $rd = $r->{$c};
    if(($c =~ /^p[HOr0-9]/) and (defined($rd->{VAL}))) {
	my $val = $rd->{VAL};
	$val =~ s/;/;;/g;
	$val =~ s/\n/\\\n/g;
	print BAFH "set $hash->{NAME}  $c $val\n";
    }
  }
  return "$backupfile: $!" if(!close(BAFH));
  return "saved Readings in $backupfile";
}






1;


=pod
=item device
=item summary Monitors and controls Tecalor/StiebelEltron heatpumps via RS232 or ser2net
=item summary_DE Kommuniziert mittels RS232 oder ser2net mit einer Tecalor/SE W&auml;rmepumpe
=begin html

<a name="THZ"></a>
<h3>THZ</h3>
<ul>
  THZ module: comunicate through serial interface RS232/USB (eg /dev/ttyxx) or through ser2net (e.g 10.0.x.x:5555) with a Tecalor/Stiebel Eltron heatpump. <br>
   Tested on a THZ303/Sol (with serial speed 57600/115200@USB) and a THZ403 (with serial speed 115200) with the same Firmware 4.39. <br>
   Tested on a LWZ404 (with serial speed 115200) with Firmware 5.39. <br>
   Tested on fritzbox, nas-qnap, raspi and macos.<br>
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
      define Mythz THZ /dev/ttyUSB0@115200 			<br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz 	<br>
      attr Mythz event-min-interval s.*:4800			<br>
      attr Mythz event-on-change-reading .*			<br>
      attr Mythz interval_sDHW 400				<br>
      attr Mythz interval_sElectrDHWDay 2400			<br>
      attr Mythz interval_sElectrDHWTotal 43200			<br>
      attr Mythz interval_sGlobal 400				<br>
      attr Mythz interval_sHC1 400				<br>
      attr Mythz interval_sHeatDHWDay 2400			<br>
      attr Mythz interval_sHeatDHWTotal 43200			<br>
      attr Mythz interval_sHeatRecoveredDay 2400		<br>
      attr Mythz interval_sHeatRecoveredTotal 43200		<br>
      attr Mythz interval_sHistory 86400			<br>
      attr Mythz interval_sLast10errors 86400			<br>
      attr Mythz room pompa					<br>
      attr FileLog_Mythz  room pompa				<br>
      </code></ul>
     <br> 
   If the attributes interval_XXXX are not defined (or 0 seconds), their internal polling is disabled.
   <br>
   This module is starting to support older firmware 2.06 or newer firmware 5.39; the following attribute adapts decoding   <br>
    <br>
      <ul><code>
      attr Mythz firmware 2.06 <br>
      </code></ul>
     <br>
    <br>
      <ul><code>
      attr Mythz firmware 5.39 <br>
      </code></ul>
     <br>
     If no attribute firmware is set, it is assumed your firmware is compatible with 4.39.
     <br>
     A backup function has been implemented
     <ul><code>
     get Mythz zBackupParameters implemented
     </code></ul> 
    The command saves all pXXX in a backupfile with a special text format.
    All (or some) parameters can be easily restored with one copy&paste from the backupfile in a telnet fhem session.
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
      define Mythz THZ /dev/ttyUSB0@115200 			<br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz 	<br>
      attr Mythz event-min-interval s.*:4800			<br>
      attr Mythz event-on-change-reading .*			<br>
      attr Mythz interval_sDHW 400				<br>
      attr Mythz interval_sElectrDHWDay 2400			<br>
      attr Mythz interval_sElectrDHWTotal 43200			<br>
      attr Mythz interval_sGlobal 400				<br>
      attr Mythz interval_sHC1 400				<br>
      attr Mythz interval_sHeatDHWDay 2400			<br>
      attr Mythz interval_sHeatDHWTotal 43200			<br>
      attr Mythz interval_sHeatRecoveredDay 2400		<br>
      attr Mythz interval_sHeatRecoveredTotal 43200		<br>
      attr Mythz interval_sHistory 86400			<br>
      attr Mythz interval_sLast10errors 86400			<br>
      attr Mythz room pompa					<br>
      attr FileLog_Mythz  room pompa				<br>
      </code></ul>
     <br> 
   Wenn die Attribute interval_XXXXXXX nicht definiert sind (oder 0), ist das interne Polling deaktiviert.
      
  </ul>
  <br>
</ul>
 
=end html_DE
=cut


