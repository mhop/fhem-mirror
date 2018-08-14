##############################################
# $Id$
# CUL HomeMatic device configuration data

#####################################################
# configuration data for CUL_HM -used to split code and configuration
package HMConfig;

use strict;
use warnings;

############globals############
use vars qw(%culHmModel);
use vars qw(%culHmRegDefShLg);
use vars qw(%culHmRegDefine);
use vars qw(%culHmRegGeneral);
use vars qw(%culHmRegType);
use vars qw(%culHmRegModel);
use vars qw(%culHmRegChan);
use vars qw(%culHmGlobalGets);
use vars qw(%culHmVrtGets);
use vars qw(%culHmSubTypeGets);
use vars qw(%culHmModelGets);
use vars qw(%culHmSubTypeDevSets);
use vars qw(%culHmGlobalSetsChn);
use vars qw(%culHmReglSets);
use vars qw(%culHmGlobalSets);
use vars qw(%culHmGlobalSetsVrtDev);
use vars qw(%culHmSubTypeSets);
use vars qw(%culHmModelSets);
use vars qw(%culHmChanSets);
use vars qw(%culHmFunctSets);
use vars qw(%culHmBits);
use vars qw(@culHmCmdFlags);
use vars qw(%culHmTpl);
use vars qw($K_actDetID);


# ----------------modul globals-----------------------
my $K_actDetID = '000000'; # id of actionDetector

#my %culHmDevProps=(
#  "01" => { st => "AlarmControl",
#  "10" => { st => "switch",
#  "12" => { st => "outputUnit",
#  "20" => { st => "dimmer",
#  "30" => { st => "blindActuator",
#  "39" => { st => "ClimateControl",
#  "40" => { st => "remote",
#  "41" => { st => "sensor",
#  "42" => { st => "swi",
#  "43" => { st => "pushButton",
#  "44" => { st => "singleButton",
#  "51" => { st => "powerMeter",
#  "58" => { st => "thermostat",
#  "60" => { st => "KFM100",
#  "70" => { st => "THSensor",
#  "80" => { st => "threeStateSensor"
#  "81" => { st => "motionDetector",
#  "C0" => { st => "keyMatic",
#  "C1" => { st => "winMatic",
#  "C3" => { st => "tipTronic",
#  "CD" => { st => "smokeDetector",
#);
# chan supports autocreate of channels for the device
# Syntax  <chnName>:<chnNoStart>:<chnNoEnd>
# chn=>{btn:1:3,disp:4,aux:5:7} wil create
# <dev>_btn1,<dev>_btn2,<dev>_btn3 as channel 1 to 3
# <dev>_disp as channel 4
# <dev>_aux1,<dev>_aux2,<dev>_aux7 as channel 5 to 7
# autocreate for single channel devices is possible not recommended
#rxt - receivetype of the device------
# l: receive on lazy config - no idea how this works so far.....
# c: receive on config
# w: receive in wakeup
# b: receive on burst
# f: receive on burst if enabled
#register list definition - identifies valid register lists
# 1,3,5:3p.4.5 => list 1 valid for all channel
#              => list 3 for all channel
#              => list 5 only for channel 3 but assotiated with peers
#              => list 5 for channel 4 and 5 with peer=00000000
#
%culHmModel=(
  "0001" => {name=>"HM-LC-SW1-PL-OM54"       ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0002" => {name=>"HM-LC-SW1-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0003" => {name=>"HM-LC-SW4-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"0004" => {name=>"HM-LC-SW1-FM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0005" => {name=>"HM-LC-BL1-FM"            ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0006" => {name=>"HM-LC-BL1-SM"            ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0007" => {name=>"KS550"                   ,alias=>"HM-WDS100-C6-O"}
 ,"0008" => {name=>"HM-RC-4"                 ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",}
 ,"0009" => {name=>"HM-LC-SW2-FM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",}
 ,"000A" => {name=>"HM-LC-SW2-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",}
 ,"000B" => {name=>"HM-WS550"                ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",}
 ,"000D" => {name=>"ASH550"                  ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",}
 ,"000E" => {name=>"ASH550I"                 ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",}
 ,"000F" => {name=>"S550IA"                  ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p'            ,chn=>"",}
 ,"0011" => {name=>"HM-LC-SW1-PL"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0012" => {name=>"HM-LC-DIM1L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0013" => {name=>"HM-LC-DIM1L-PL"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0014" => {name=>"HM-LC-SW1-SM-ATMEGA168"  ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",}
 ,"0015" => {name=>"HM-LC-SW4-SM-ATMEGA168"  ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"0016" => {name=>"HM-LC-DIM2L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2",}
 ,"0018" => {name=>"CMM"                     ,st=>'remote'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",}
 ,"0019" => {name=>"HM-SEC-KEY"              ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"",}
 ,"001A" => {name=>"HM-RC-P1"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}
 ,"001B" => {name=>"HM-RC-SEC3"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",}
 ,"001C" => {name=>"HM-RC-SEC3-B"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",}
 ,"001D" => {name=>"HM-RC-KEY3"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",}
 ,"001E" => {name=>"HM-RC-KEY3-B"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",}
 ,"001F" => {name=>"KS888"                   ,alias=>"HM-WDS100-C6-O"}
 ,"0022" => {name=>"WS888"                   ,st=>''                  ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0026" => {name=>"HM-SEC-KEY-S"            ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"",}
 ,"0027" => {name=>"HM-SEC-KEY-O"            ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"",}
 ,"0028" => {name=>"HM-SEC-WIN"              ,st=>'winMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'1:1,3:1p'     ,chn=>"Win:1:1,Akku:2:2",}
 ,"0029" => {name=>"HM-RC-12"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:12",}
 ,"002A" => {name=>"HM-RC-12-B"              ,alias=>"HM-RC-12"}
 ,"002B" => {name=>"HM-WS550Tech"            ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",}
 ,"002C" => {name=>"KS550TECH"               ,alias=>"HM-WDS100-C6-O"}
 ,"002D" => {name=>"HM-LC-SW4-PCB"           ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"002E" => {name=>"HM-LC-DIM2L-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2",}
 ,"002F" => {name=>"HM-SEC-SC"               ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",} # remove wakeup - need retest
 ,"0030" => {name=>"HM-SEC-RHS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"",} # remove wakeup - need retest
 ,"0031" => {name=>"HM-WS550LCB"             ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",} 
 ,"0032" => {name=>"HM-WS550LCW"             ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",} 
 ,"0033" => {name=>"KS550LC"                 ,alias=>"HM-WDS100-C6-O"}
 ,"0034" => {name=>"HM-PBI-4-FM"             ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",} # HM Push Button Interface
 ,"0035" => {name=>"HM-PB-4-WM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",}
 ,"0036" => {name=>"HM-PB-2-WM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:2",} # RC file - see also 0BF  
 ,"0037" => {name=>"HM-RC-19"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,4:1p.2p.3p.4p.5p.6p.7p.8p.9p.10p.11p.12p.13p.14p.15p.16p'
                                                                                                                        ,chn=>"Btn:1:17,Disp:18:18",}
 ,"0038" => {name=>"HM-RC-19-B"              ,alias=>"HM-RC-19"}
 ,"0039" => {name=>"HM-CC-TC"                ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p:2p,5:2.3p,6:2',chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3",}
 ,"003A" => {name=>"HM-CC-VD"                ,st=>'thermostat'        ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'p,5'          ,chn=>"",}
 ,"003B" => {name=>"HM-RC-4-B"               ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",}
 ,"003C" => {name=>"HM-WDS20-TH-O"           ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:f'    ,lst=>'p'            ,chn=>"",} #:w  todo should be wakeup, does not react
 ,"003D" => {name=>"HM-WDS10-TH-O"           ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:f:w'  ,lst=>'p'            ,chn=>"",} #:w  todo should be wakeup, does not react
 ,"003E" => {name=>"HM-WDS30-T-O"            ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p'            ,chn=>"",} #:w remark: this device behaves on wakeup
 ,"003F" => {name=>"HM-WDS40-TH-I"           ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:f'    ,lst=>'p'            ,chn=>"",} #:w  todo should be wakeup, does not react
#,"0040" => {name=>"HM-WDS100-C6-O"          ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1'          ,chn=>"",} #:w  todo should be wakeup, does not react
 ,"0040" => {name=>"HM-WDS100-C6-O"          ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1,1:1p'     ,chn=>"",} #:w  todo should be wakeup, does not react
 ,"0041" => {name=>"HM-WDC7000"              ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>''       ,lst=>'1,4'          ,chn=>"",}
 ,"0042" => {name=>"HM-SEC-SD"               ,st=>'smokeDetector'     ,cyc=>'99:00' ,rxt=>'b'      ,lst=>'p'            ,chn=>"",}
 ,"0043" => {name=>"HM-SEC-TIS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}
 ,"0044" => {name=>"HM-SEN-EP"               ,st=>'sensor'            ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"Sen:1:2",}
 ,"0045" => {name=>"HM-SEC-WDS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}
 ,"0046" => {name=>"HM-SWI-3-FM"             ,st=>'swi'               ,cyc=>''      ,rxt=>'c'      ,lst=>'4'            ,chn=>"Sw:1:3",}
 ,"0047" => {name=>"KFM-Sensor"              ,st=>'KFM100'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"",}
 ,"0048" => {name=>"IS-WDS-TH-OD-S-R3"       ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",}
 ,"0049" => {name=>"KFM-Display"             ,st=>'KFM100'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"004A" => {name=>"HM-SEC-MDIR"             ,st=>'motionDetector'    ,cyc=>'00:20' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}
 ,"004B" => {name=>"HM-Sec-Cen"              ,st=>'AlarmControl'      ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"004C" => {name=>"HM-RC-12-SW"             ,alias=>"HM-RC-12"}
 ,"004D" => {name=>"HM-RC-19-SW"             ,alias=>"HM-RC-19"}
 ,"004E" => {name=>"HM-LC-DDC1-PCB"          ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",} # door drive controller 1-channel (PCB)
 ,"004F" => {name=>"HM-SEN-MDIR-SM"          ,st=>'motionDetector'    ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}
 ,"0050" => {name=>"HM-SEC-SFA-SM"           ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Siren:1:1,Flash:2:2",}
 ,"0051" => {name=>"HM-LC-SW1-PB-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",}
 ,"0052" => {name=>"HM-LC-SW2-PB-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Sw:1:2",}
 ,"0053" => {name=>"HM-LC-BL1-PB-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0054" => {name=>"DORMA_RC-H"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"",} # DORMA Remote 4 buttons
 ,"0056" => {name=>"HM-CC-SCD"               ,st=>'smokeDetector'     ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}
 ,"0057" => {name=>"HM-LC-DIM1T-PL"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0058" => {name=>"HM-LC-DIM1T-CV"          ,alias=>"HM-LC-DIM1T-PL"}
 ,"0059" => {name=>"HM-LC-DIM1T-FM"          ,alias=>"HM-LC-DIM1T-PL"}
 ,"005A" => {name=>"HM-LC-DIM2T-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",}#4virt- is this a faulty entry?
 ,"005C" => {name=>"HM-OU-CF-PL"             ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Led:1:1,Sound:2:2",}
 ,"005D" => {name=>"HM-Sen-MDIR-O"           ,st=>'motionDetector'    ,cyc=>'00:10' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}
 ,"005F" => {name=>"HM-SCI-3-FM"             ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"Sw:1:3",}
 ,"0060" => {name=>"HM-PB-4DIS-WM"           ,alias=>"HM-PB-4DIS-WM-2"}
 ,"0061" => {name=>"HM-LC-SW4-DR"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"0062" => {name=>"HM-LC-SW2-DR"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",}
 ,"0064" => {name=>"DORMA_atent"             ,st=>''                  ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"Btn:1:3",} # DORMA Remote 3 buttons
 ,"0065" => {name=>"DORMA_BRC-H"             ,st=>'singleButton'      ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"Btn:1:4",} # Dorma Remote 4 single buttons
 ,"0066" => {name=>"HM-LC-SW4-WM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"0067" => {name=>"HM-LC-Dim1PWM-CV"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"0068" => {name=>"HM-LC-Dim1TPBU-FM"       ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"0069" => {name=>"HM-LC-Sw1PBU-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"006A" => {name=>"HM-LC-Bl1PBU-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"006B" => {name=>"HM-PB-2-WM55"            ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:2",}
 ,"006C" => {name=>"HM-LC-SW1-BA-PCB"        ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"",}
 ,"006D" => {name=>"HM-OU-LED16"             ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'p,1'          ,chn=>"Led:1:16",}
 ,"006E" => {name=>"HM-LC-Dim1L-CV-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"006F" => {name=>"HM-LC-Dim1L-Pl-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"0070" => {name=>"HM-LC-Dim2L-SM-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2,Dim1_V:3:4,Dim2_V:5:6",}#
 ,"0071" => {name=>"HM-LC-Dim1T-Pl-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"0072" => {name=>"HM-LC-Dim1T-CV-644"      ,alias=>"HM-LC-Dim1T-Pl-644"}
 ,"0073" => {name=>"HM-LC-Dim1T-FM-644"      ,alias=>"HM-LC-Dim1T-Pl-644"}
 ,"0074" => {name=>"HM-LC-Dim2T-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2,Dim_V:3:4,Dim2_V:5:6",}#
 ,"0075" => {name=>"HM-OU-CFM-PL"            ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Led:1:1,Mp3:2:2",}
 ,"0076" => {name=>"HM-Sys-sRP-Pl"           ,st=>'repeater'          ,cyc=>''      ,rxt=>''       ,lst=>'p,2'          ,chn=>"",} # repeater
 ,"0078" => {name=>"HM-Dis-TD-T"             ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"",} #
 ,"0079" => {name=>"ROTO_ZEL-STG-RM-FWT"     ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p:2p,5:2.3p,6:2',chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3",}
 ,"007A" => {name=>"ROTO_ZEL-STG-RM-FSA"     ,st=>'thermostat'        ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'p,5'          ,chn=>"",}  #Roto VD
 ,"007B" => {name=>"ROTO_ZEL-STG-RM-FEP-230V",st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # radio-controlled blind actuator 1-channel (flush-mount)
 ,"007C" => {name=>"ROTO_ZEL-STG-RM-FZS"     ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # radio-controlled socket adapter switch actuator 1-channel
 ,"007D" => {name=>"ROTO_ZEL-STG-RM-WT-2"    ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}  # HM Push Button 2
 ,"007E" => {name=>"ROTO_ZEL-STG-RM-DWT-10"  ,alias=>"HM-PB-4DIS-WM-2"}
 ,"007F" => {name=>"ROTO_ZEL-STG-RM-FST-UP4" ,alias=>"HM-PBI-4-FM"}                                                                 # HM Push Button Interface
 ,"0080" => {name=>"ROTO_ZEL-STG-RM-HS-4"    ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}  # HM Remote 4 buttons
 ,"0081" => {name=>"ROTO_ZEL-STG-RM-FDK"     ,alias=>"HM-SEC-RHS"}
 ,"0082" => {name=>"Roto_ZEL-STG-RM-FFK"     ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}  # HM Shutter Contact
 ,"0083" => {name=>"Roto_ZEL-STG-RM-FSS-UP3" ,st=>'swi'               ,cyc=>''      ,rxt=>'c'      ,lst=>'4'            ,chn=>"",}  # HM Switch Interface 3 switches
 ,"0084" => {name=>"Schueco_263-160"         ,st=>'smokeDetector'     ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}  # HM SENSOR_FOR_CARBON_DIOXIDE
 ,"0086" => {name=>"Schueco_263-146"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # radio-controlled blind actuator 1-channel (flush-mount)
 ,"0087" => {name=>"Schueco_263-147"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # radio-controlled blind actuator 1-channel (flush-mount)
 ,"0088" => {name=>"Schueco_263-132"         ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # 1 channel dimmer L (ceiling voids)
 ,"0089" => {name=>"Schueco_263-134"         ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # 1 channel dimmer T (ceiling voids)
 ,"008A" => {name=>"Schueco_263-133"         ,alias=>"HM-LC-Dim1TPBU-FM"}                                                           # 1 channel dimmer TPBU (flush mount)
 ,"008B" => {name=>"Schueco_263-130"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # radio-controlled switch actuator 1-channel (flush-mount)
 ,"008C" => {name=>"Schueco_263-131"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}  # radio-controlled switch actuator 1-channel (flush-mount)
 ,"008D" => {name=>"Schueco_263-135"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}  # HM Push Button 2
 ,"008E" => {name=>"Schueco_263-155"         ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}  # HM Remote Display 4 buttons
 ,"008F" => {name=>"Schueco_263-145"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}  # HM Push Button Interface
 ,"0090" => {name=>"Schueco_263-162"         ,st=>'motionDetector'    ,cyc=>'00:30' ,rxt=>'c:w:l'  ,lst=>'1,3'          ,chn=>"",}  # HM radio-controlled motion detector
 ,"0091" => {name=>"Schueco_263-167"         ,st=>'smokeDetector'     ,cyc=>'99:00' ,rxt=>'b'      ,lst=>'p'            ,chn=>"",}  # HM Smoke Detector Schueco
 ,"0092" => {name=>"Schueco_263-144"         ,st=>'switch'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"",}  # HM Switch Interface 3 switches
 ,"0093" => {name=>"Schueco_263-158"         ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",}  #
 ,"0094" => {name=>"Schueco_263-157"         ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p'            ,chn=>"",}  #
 ,"0095" => {name=>"HM-CC-RT-DN"             ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p:1p.2p.4p.5p.6p,3:3p.6p,1,7:3p.4'
                                                                                                                        ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3,Clima:4:4,ClimaTeam:5:5,remote:6:6"} #
 ,"0096" => {name=>"WDF-solar"               ,st=>'blindActuatorSol'  ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"win:1:1,blind:2:3",} #
 ,"009B" => {name=>"Schueco_263-xxx"         ,st=>'tipTronic'         ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1:1.2,3:1p.3p',chn=>"act:1:1,sen:2:2,sec:3:3",} #
 ,"009F" => {name=>"HM-Sen-Wa-Od"            ,st=>'sensor'            ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",} #capacitive filling level sensor
 ,"00A0" => {name=>"HM-RC-4-2"               ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"Btn:1:4",} # init : ,01,01,1E
 ,"00A1" => {name=>"HM-LC-SW1-PL2"           ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",} #
 ,"00A2" => {name=>"ROTO_ZEL-STG-RM-FZS-2"   ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",} #radio-controlled socket adapter switch actuator 1-channel
 ,"00A3" => {name=>"HM-LC-Dim1L-Pl-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"00A4" => {name=>"HM-LC-Dim1T-Pl-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"00A5" => {name=>"HM-RC-Sec4-2"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"armInt:1:1,armExt:2:2,light:3:3,disarm:4:4",}
 ,"00A6" => {name=>"HM-RC-Key4-2"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"unlock:1:1,lock:2:2,light:3:3,open:4:4",}
 ,"00A7" => {name=>"HM-Sen-RD-O"             ,st=>'sensRain'          ,cyc=>''      ,rxt=>''       ,lst=>'1:1,4:1p'     ,chn=>"Rain:1:1,Heating:2:2",}#stc:70 THSensor
 ,"00A8" => {name=>"HM-WDS30-OT2-SM"         ,st=>'THSensor'          ,cyc=>'12:00' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"T1:1:1,T2:2:2,T1_T2:3:3,T2_T1:4:4,Event:5:5",}
 ,"00A9" => {name=>"HM-PB-6-WM55"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:6",}
 ,"00AA" => {name=>"HM-SEC-SD-2"             ,st=>'smokeDetector'     ,cyc=>'99:00' ,rxt=>'c:3'    ,lst=>'p'            ,chn=>"",} 
 ,"00AB" => {name=>"HM-LC-SW4-BA-PCB"        ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"00AC" => {name=>"HM-ES-PMSw1-Pl"          ,st=>'powerMeter'        ,cyc=>'00:10' ,rxt=>''       ,lst=>'1,3:1p,4:3p.4p.5p.6p'
                                                                                                                        ,chn=>"Sw:1:1,Pwr:2:2,SenPwr:3:3,SenI:4:4,SenU:5:5,SenF:6:6"}
 ,"00AD" => {name=>"HM-TC-IT-WM-W-EU"        ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:b'    ,lst=>'p:1p.2p.6p.7p,3:3p.6p,1,7:2.3p.7p,8:2,9:2'
                                                                                                                        ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3,remote:6:6,SwitchTr:7:7",}
 ,"00AE" => {name=>"HM-WDS100-C6-O-2"        ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p,1,1:1p,4'   ,chn=>"",}# odd: list one with and without peer on one channel
 ,"00AF" => {name=>"HM-OU-CM-PCB"            ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",}
 ,"00B1" => {name=>"HM-SEC-SC-2"             ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}
 ,"00B2" => {name=>"HM-SEC-WDS-2"            ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}
 ,"00B3" => {name=>"HM-LC-Dim1L-Pl-3"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"00B4" => {name=>"HM-LC-Dim1T-Pl-3"        ,alias=>"HM-LC-Dim1T-Pl-644"}
 ,"00B5" => {name=>"HM-LC-Dim1PWM-CV-2"      ,alias=>"HM-LC-Dim1PWM-CV"}
 ,"00B6" => {name=>"HM-LC-Dim1TPBU-FM-2"     ,alias=>"HM-LC-Dim1TPBU-FM"}
 ,"00B7" => {name=>"HM-LC-Dim1L-CV-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"00B8" => {name=>"HM-LC-Dim2L-SM-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2,Dim1_V:3:4,Dim2_V:5:6",}#
 ,"00B9" => {name=>"HM-LC-Dim1T-CV-2"        ,alias=>"HM-LC-Dim1T-Pl-644"}
 ,"00BA" => {name=>"HM-LC-Dim1T-FM-2"        ,alias=>"HM-LC-Dim1T-Pl-644"}
 ,"00BB" => {name=>"HM-LC-Dim2T-SM-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",}#
 ,"00BC" => {name=>"HM-WDS40-TH-I-2"         ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:f'    ,lst=>'p'            ,chn=>"",} #:w  todo should be wakeup, does not react
 ,"00BD" => {name=>"HM-CC-RT-DN-BoM"         ,alias=>"HM-CC-RT-DN"}
 ,"00BE" => {name=>"HM-MOD-Re-8"             ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"Sw:1:8",}
 ,"00BF" => {name=>"HM-PB-2-FM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"Btn:1:2",}
 ,"00C0" => {name=>"HM-SEC-MDIR-2"           ,alias=>"HM-SEC-MDIR"}
 ,"00C1" => {name=>"HM-Sen-MDIR-O-2"         ,st=>'motionDetector'    ,cyc=>'00:10' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}
 ,"00C2" => {name=>"HM-PB-2-WM55-2"          ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:2",}
 ,"00C3" => {name=>"HM-SEC-RHS-2"            ,alias=>"HM-SEC-RHS"}
 ,"00C7" => {name=>"HM-SEC-SCo"              ,st=>'threeStateSensor'  ,cyc=>'02:50' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",}
 ,"00C8" => {name=>"HM-LC-Sw1-Pl-3"          ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"00C9" => {name=>"HM-LC-Sw1-SM-2"          ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00CA" => {name=>"HM-LC-Sw1-FM-2"          ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00CB" => {name=>"HM-LC-Sw2-FM-2"          ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",}
 ,"00CC" => {name=>"HM-LC-Sw2-DR-2"          ,alias=>"HM-LC-Sw2-FM-2"}
 ,"00CD" => {name=>"HM-LC-Sw4-SM-2"          ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"00CE" => {name=>"HM-LC-Sw4-PCB-2"         ,alias=>"HM-LC-Sw4-SM-2"}
 ,"00CF" => {name=>"HM-LC-Sw4-WM-2"          ,alias=>"HM-LC-Sw4-SM-2"}
 ,"00D0" => {name=>"HM-LC-Sw4-DR-2"          ,alias=>"HM-LC-Sw4-SM-2"}
 ,"00D1" => {name=>"HM-LC-Bl1-SM-2"          ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",} # radio-controlled blind actuator 1-channel (flush-mount)
 ,"00D2" => {name=>"HM-LC-Bl1-FM-2"          ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",} # radio-controlled blind actuator 1-channel (flush-mount)
 # check config modess,"00D3" => {name=>"HM-Dis-WM55"             ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1'            ,chn=>"Dis:1:10",}
 ,"00D3" => {name=>"HM-Dis-WM55"             ,st=>'display'           ,cyc=>''      ,rxt=>'c'      ,lst=>'1,p'          ,chn=>"Dis:1:10",}
 ,"00D4" => {name=>"HM-RC-4-3"               ,st=>'remote'            ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:4",}
 ,"00D5" => {name=>"HM-RC-Sec4-3"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"armInt:1:1,armExt:2:2,light:3:3,disarm:4:4",}
 ,"00D6" => {name=>"HM-RC-Key4-3"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"unlock:1:1,lock:2:2,light:3:3,open:4:4",}
 ,"00D7" => {name=>"HM-ES-PMSw1-Pl-DN-R1"    ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00D8" => {name=>"HM-LC-Sw1-Pl-DN-R1"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00D9" => {name=>"HM-MOD-Em-8"             ,st=>'remote'            ,cyc=>''      ,rxt=>'l'      ,lst=>'1,4'          ,chn=>"Btn:1:8",}
 ,"00DA" => {name=>"HM-RC-8"                 ,st=>'remote'            ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:8",}
 ,"00DB" => {name=>"HM-Sen-MDIR-WM55"        ,st=>'motionAndBtn'      ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:2,Motion:3:3",}
 ,"00DC" => {name=>"HM-Sen-DB-PCB"           ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}
 ,"00DD" => {name=>"HM-PB-4DIS-WM-2"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:20",}
 ,"00DE" => {name=>"HM-ES-TX-WM"             ,st=>'powerSensor'       ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'1'            ,chn=>"IEC:1:2",}         # strom/gassensor
 ,"00E0" => {name=>"HM-RC-2-PBU-FM"          ,st=>'remote'            ,cyc=>''      ,rxt=>''       ,lst=>'1,4'          ,chn=>"Btn:1:2",}  # HM Wireless Sender 2-channel for brand switch systems, flush mount
 ,"00E1" => {name=>"HM-RC-Dis-H-x-EU"        ,st=>'remote'            ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:20",} #"HM Remote Control with Displays"
 ,"00E2" => {name=>"HM-ES-PMSw1-Pl-DN-R2"    ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00E3" => {name=>"HM-ES-PMSw1-Pl-DN-R3"    ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00E4" => {name=>"HM-ES-PMSw1-Pl-DN-R4"    ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00E5" => {name=>"HM-ES-PMSw1-Pl-DN-R5"    ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00E6" => {name=>"HM-LC-Sw1-Pl-DN-R2"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00E7" => {name=>"HM-LC-Sw1-Pl-DN-R3"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00E8" => {name=>"HM-LC-Sw1-Pl-DN-R4"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00E9" => {name=>"HM-LC-Sw1-Pl-DN-R5"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00EA" => {name=>"HM-ES-PMSw1-DR"          ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00EB" => {name=>"HM-LC-Sw1-Pl-CT-R1"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00EC" => {name=>"HM-LC-Sw1-Pl-CT-R2"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00ED" => {name=>"HM-LC-Sw1-Pl-CT-R3"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00EE" => {name=>"HM-LC-Sw1-Pl-CT-R4"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00EF" => {name=>"HM-LC-Sw1-Pl-CT-R5"      ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00F0" => {name=>"HM-LC-Sw1-DR"            ,alias=>"HM-LC-Sw1-Pl-3"}
 ,"00F3" => {name=>"SensoTimer-ST-6"         ,st=>'timer'             ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,4:5p.6p.7p.8p.9p' ,chn=>"Sw:1:2,Sen:3:4,Key:5:7,ecoKey:8:9",}
 ,"00F4" => {name=>"HM-LC-RGBW-WM"           ,st=>'rgb'               ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Color:2:2,Auto:3:3",}
 ,"00F5" => {name=>"HM-LC-Dim1T-FM-LF"       ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"00F6" => {name=>"HM-ES-PMSw1-SM"          ,alias=>"HM-ES-PMSw1-Pl"}
 ,"00F7" => {name=>"HM-SEC-MDIR-3"           ,alias=>"HM-SEC-MDIR"}
 ,"00F8" => {name=>"HM-RC-4-3-D"             ,st=>'remote'            ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:4",}
 ,"00F9" => {name=>"HM-Sec-Sir-WM"           ,st=>'siren'             ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,3'          ,chn=>"Sen:1:2,Panic:3:3,Arm:4:4",}
 ,"00FA" => {name=>"HM-OU-CFM-TW"            ,st=>'outputUnit'        ,cyc=>''      ,rxt=>'c:b'    ,lst=>'3'            ,chn=>"Led:1:1,Mp3:2:2",}
 ,"00FB" => {name=>"HM-Dis-EP-WM55"          ,st=>'display'           ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,4:1p.2p'    ,chn=>"Btn:1:2,Dis:3:3,Key:4:8",}
 ,"00FC" => {name=>"OLIGO-smart-iq-HM"       ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2,Dim1_V:3:4,Dim2_V:5:6",}
 ,"00FD" => {name=>"HM-Sen-LI-O"             ,st=>'senBright'         ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1'            ,chn=>""}

 ,"0101" => {name=>"HM-LC-Sw2PBU-FM"         ,alias=>"HM-LC-Sw2-FM-2"}
 ,"0102" => {name=>"HM-WDS30-OT2-SM-2"       ,alias=>"HM-WDS30-OT2-SM" }
 ,"0103" => {name=>"HM-LC-Sw1-PCB"           ,alias=>"HM-LC-Sw1-Pl-3" }
 ,"0104" => {name=>"HM-LC-AO-SM"             ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"0105" => {name=>"HM-LC-Dim1T-DR"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:1,Dim_V:2:3",}
 ,"0106" => {name=>"HM-MOD-EM-8Bit"          ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"Btn:1:2,Tr:3:3",}
 ,"0107" => {name=>"HM-LC-Ja1PBU-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}
 ,"0108" => {name=>"HM-HM-LC-DW-WM"          ,st=>'rgb'               ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Bright:1:1,Col:2:2,Bright_V1:3:3,Col_V1:4:4,Bright_V2:5:5,Col_V2:6:6",}
 ,"0109" => {name=>"HM-DW-WM"                ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Dim:1:2,Dim1_V:3:4,Dim2_V:5:6",}
 ,"010A" => {name=>"HM-Sen-MDIR-O-3"         ,alias=>"HM-Sen-MDIR-O-2" }

 ,"8001" => {name=>"PS-switch"               ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",}
 ,"8002" => {name=>"PS-Th-Sens"              ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'1,4'          ,chn=>"Sen:1:4",}
 ,"FFF0" => {name=>"CCU-FHEM"                ,st=>'virtual'           ,cyc=>''      ,rxt=>''       ,lst=>''             ,chn=>"Btn:1:50",}
 
  #  "HM-LGW-O-TW-W-EU" #Funk LAN Gateway
#################open:---------------------------
);

foreach my $al (keys %culHmModel){ # duplicate entries for alias devices
  next if (!defined $culHmModel{$al}{alias});

  foreach my $mt (keys %culHmModel){
    if (($culHmModel{$al}{alias}) eq $culHmModel{$mt}{name}){
      foreach(grep !/name/, keys %{$culHmModel{$mt}}){
        $culHmModel{$al}{$_} = $culHmModel{$mt}{$_};
      }
      last;
    }
  }
  delete $culHmModel{$al} if (!defined$culHmModel{$al}{st}); # not found - remove entry
}

##----------definitions for register settings-----------------
    # definition of Register for all devices
    # a: address, incl bits 13.4 4th bit in reg 13
    # s: size 2.0 = 2 byte, 0.5 = 5 bit. Max is 4.0!!
    # l: list number. List0 will be for channel 0
    #     List 1 will set peer to 00000000
    #     list 3 will need the input of a peer!
    # min: minimal input value
    # max: maximal input value
    # c: conversion, will point to a routine for calculation
    # f: factor to be used if c = 'factor'
    # u: unit for description
    # t: txt description
    # lit: if the command is a literal options will be entered here
    # d: if '1' the register will appear in Readings
    #
%culHmRegDefShLg = (# register that are available for short AND long button press. Will be merged to rgister list at init
#blindActuator mainly
  ActionType      =>{a=> 10.0,s=>0.2,l=>3,min=>0    ,max=>3     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3}},
  OffTimeMode     =>{a=> 10.6,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"off time meant absolut or at least"   ,lit=>{absolut=>0,minimal=>1}},
  OnTimeMode      =>{a=> 10.7,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"on time meant absolut or at least"    ,lit=>{absolut=>0,minimal=>1}},
  MaxTimeF        =>{a=> 29.0,s=>1.0,l=>3,min=>0    ,max=>25.5  ,c=>''         ,p=>'y',f=>10      ,u=>'s'   ,d=>0,t=>"max time first direction."            ,lit=>{unused=>25.5}},
  DriveMode       =>{a=> 31.0,s=>1.0,l=>3,min=>0    ,max=>3     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{direct=>0,viaUpperEnd=>1,viaLowerEnd=>2,viaNextEnd=>3}},
#dimmer mainly                                                                 
  OnDly           =>{a=>  6.0,s=>1.0,l=>3,min=>0    ,max=>111600,c=>'fltCvT'   ,p=>'y',f=>''      ,u=>'s'   ,d=>0,t=>"on delay"},
  OnTime          =>{a=>  7.0,s=>1.0,l=>3,min=>0    ,max=>111600,c=>'fltCvT'   ,p=>'y',f=>''      ,u=>'s'   ,d=>0,t=>"on time"                              ,lit=>{unused=>111600}},
  OffDly          =>{a=>  8.0,s=>1.0,l=>3,min=>0    ,max=>111600,c=>'fltCvT'   ,p=>'y',f=>''      ,u=>'s'   ,d=>0,t=>"off delay"},
  OffTime         =>{a=>  9.0,s=>1.0,l=>3,min=>0    ,max=>111600,c=>'fltCvT'   ,p=>'y',f=>''      ,u=>'s'   ,d=>0,t=>"off time"                             ,lit=>{unused=>111600}},
                                                                               
  ActionTypeDim   =>{a=> 10.0,s=>0.4,l=>3,min=>0    ,max=>8     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3,upDim=>4,downDim=>5,toggelDim=>6,toggelDimToCnt=>7,toggelDimToCntInv=>8}},
  OffDlyBlink     =>{a=> 14.5,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"blink when in off delay"              ,lit=>{off=>0,on=>1}},
  OnLvlPrio       =>{a=> 14.6,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{high=>0,low=>1}},
  OnDlyMode       =>{a=> 14.7,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{setToOff=>0,NoChange=>1}},
  OffLevel        =>{a=> 15.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"PowerLevel off"},
  OnMinLevel      =>{a=> 16.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"minimum PowerLevel"},
  OnLevel         =>{a=> 17.0,s=>1.0,l=>3,min=>0    ,max=>100.5 ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>1,t=>"PowerLevel on"                        ,lit=>{oldLevel=>100.5}},
  OnLevelArm      =>{a=> 17.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"onLevel on"                           ,lit=>{disarmed=>0,extSens=>50,allSens=>200}},
                                                                               
  OffLevelKm      =>{a=> 15.0,s=>1.0,l=>3,min=>0    ,max=>127.5 ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  OnLevelKm       =>{a=> 17.0,s=>1.0,l=>3,min=>0    ,max=>127.5 ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  RampOnSp        =>{a=> 34.0,s=>1.0,l=>3,min=>0    ,max=>1     ,c=>''         ,p=>'y',f=>200     ,u=>'s'   ,d=>0,t=>"Ramp on speed"},
  RampOffSp       =>{a=> 35.0,s=>1.0,l=>3,min=>0    ,max=>1     ,c=>''         ,p=>'y',f=>200     ,u=>'s'   ,d=>0,t=>"Ramp off speed"},
                                                                               
  RampSstep       =>{a=> 18.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"rampStartStep"},
  RampOnTime      =>{a=> 19.0,s=>1.0,l=>3,min=>0    ,max=>111600,c=>'fltCvT'   ,p=>'y',f=>''      ,u=>'s'   ,d=>0,t=>"rampOnTime"},
  RampOffTime     =>{a=> 20.0,s=>1.0,l=>3,min=>0    ,max=>111600,c=>'fltCvT'   ,p=>'y',f=>''      ,u=>'s'   ,d=>0,t=>"rampOffTime"},
  DimMinLvl       =>{a=> 21.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"dimMinLevel"},
  DimMaxLvl       =>{a=> 22.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"dimMaxLevel"},
  DimStep         =>{a=> 23.0,s=>1.0,l=>3,min=>0    ,max=>100   ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"dimStep"},
  OffDlyStep      =>{a=> 24.0,s=>1.0,l=>3,min=>0.1  ,max=>25.6  ,c=>''         ,p=>'y',f=>2       ,u=>'%'   ,d=>0,t=>"off delay step if blink is active"},
  OffDlyNewTime   =>{a=> 25.0,s=>1.0,l=>3,min=>0.1  ,max=>25.6  ,c=>''         ,p=>'y',f=>10      ,u=>'s'   ,d=>0,t=>"off delay blink time for low"},
  OffDlyOldTime   =>{a=> 26.0,s=>1.0,l=>3,min=>0.1  ,max=>25.6  ,c=>''         ,p=>'y',f=>10      ,u=>'s'   ,d=>0,t=>"off delay blink time for high"},
  DimElsOffTimeMd =>{a=> 38.6,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{absolut=>0,minimal=>1}},
  DimElsOnTimeMd  =>{a=> 38.7,s=>0.1,l=>3,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{absolut=>0,minimal=>1}},
  DimElsActionType=>{a=> 38.0,s=>0.4,l=>3,min=>0    ,max=>8     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3,upDim=>4,downDim=>5,toggelDim=>6,toggelDimToCnt=>7,toggelDimToCntInv=>8}},
#output Unit                                                                   
  ActTypeMp3      =>{a=> 36  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Tone or MP3 to be played"},
  ActTypeLed      =>{a=> 36  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"LED color"                            ,lit=>{no=>0x00,redS=>0x11,redL=>0x12,greenS=>0x21,greenL=>0x22,orangeS=>0x31,orangeL=>0x32}},
  ActTypeOuCf     =>{a=> 36  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"type sound or LED"                    ,lit=>{no=>0,short=>1,long=>2}},
  ActNum          =>{a=> 37  ,s=>1  ,l=>3,min=>1    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Number of repetitions"},
  Intense         =>{a=> 43  ,s=>1  ,l=>3,min=>10   ,max=>255   ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Volume"                               ,lit=>{vol_100=>255,vol_90=>250,vol_80=>246,vol_70=>240,vol_60=>234,vol_50=>227,vol_40=>218,vol_30=>207,vol_20=>190,vol_10=>162,vol_00=>10}},
# statemachines                                                                
  BlJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from on"                         ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn"                    ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff"                   ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOn      =>{a=> 13.0,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"                     ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOff     =>{a=> 13.4,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff"                    ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOn       =>{a=> 30.0,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from refOn"                      ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOff      =>{a=> 30.4,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from refOff"                     ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
                                                                               
  DimJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from on"                         ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtDlyOn      =>{a=> 12.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn"                    ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtDlyOff     =>{a=> 12.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff"                   ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"                     ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff"                    ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
                                                                               
  DimElsJtOn      =>{a=> 39.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"else Jump from on"                    ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtOff     =>{a=> 39.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"else Jump from off"                   ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtDlyOn   =>{a=> 40.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"else Jump from delayOn"               ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtDlyOff  =>{a=> 40.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"else Jump from delayOff"              ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtRampOn  =>{a=> 41.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"else Jump from rampOn"                ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtRampOff =>{a=> 41.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"else Jump from rampOff"               ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
                                                                               
  ttJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from on"                         ,lit=>{no=>0,on=>2,off=>5}},
  ttJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,on=>2,off=>5}},
                                                                                                                                                     
  SwJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from on"                         ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn"                    ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff"                   ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
                                                                                                                                                     
  KeyJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0    ,max=>7     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from on"                         ,lit=>{no=>0,dlyUnlock=>1,rampUnlock=>2,unLock=>3,dlyLock=>4,rampLock=>5,lock=>6,open=>8}},
  KeyJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0    ,max=>7     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,dlyUnlock=>1,rampUnlock=>2,unLock=>3,dlyLock=>4,rampLock=>5,lock=>6,open=>8}},
                                                                                                                                                     
  WinJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0    ,max=>9     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jump from off"                        ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
                                                                               
  CtRampOn        =>{a=>  1.0,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOn"         ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtRampOff       =>{a=>  1.4,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOff"        ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtDlyOn         =>{a=>  2.0,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOn"        ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtDlyOff        =>{a=>  2.4,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOff"       ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtOn            =>{a=>  3.0,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from on"             ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtOff           =>{a=>  3.4,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from off"            ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtValLo         =>{a=>  4.0,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Condition value low for CT table"  },
  CtValHi         =>{a=>  5.0,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Condition value high for CT table" },
  CtRefOn         =>{a=> 28.0,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from refOn"          ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtRefOff        =>{a=> 28.4,s=>0.4,l=>3,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from refOff"         ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
                                                                               
  TempRC          =>{a=> 45  ,s=>0.6,l=>3,min=>4.5  ,max=>30.5  ,c=>''         ,p=>'y',f=>2       ,u=>'C'   ,d=>0,t=>"temperature if required by CtrlRc reg"},
  CtrlRc          =>{a=> 46  ,s=>0.4,l=>3,min=>0    ,max=>6     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"set mode and/or temperature"          ,lit=>{no=>0,tempOnly=>1,auto=>2,autoAndTemp=>3,manuAndTemp=>4,boost=>5,toggle=>6}},
  ActHsvCol       =>{a=> 47  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"activate color value"},
  ActColPrgm      =>{a=> 48  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"activate color program"},
  ActMinBoarder   =>{a=> 49  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"activate minimal boarder"},
  ActMaxBoarder   =>{a=> 50  ,s=>1  ,l=>3,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"activate maximal boarder"},

);

%culHmRegDefine = (
#--- list 0, device  and protocol level-----------------
  burstRx         =>{a=>  1.0,s=>1.0,l=>0,min=>0    ,max=>255   ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>'device reacts on Burst'               ,lit=>{off=>0,on=>1}},
  intKeyVisib     =>{a=>  2.7,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>'visibility of internal channel'       ,lit=>{invisib=>0,visib=>1}},
  pairCentral     =>{a=> 10.0,s=>3.0,l=>0,min=>0    ,max=>16777215,c=>'hex'    ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>'pairing to central'},
#remote mainly                                                                 
  backlOnTime     =>{a=>  5.0,s=>0.6,l=>0,min=>0    ,max=>5     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Backlight ontime[s]"                  ,lit=>{0=>0,5=>1,10=>2,15=>3,20=>4,25=>5}},
  backlOnMode     =>{a=>  5.6,s=>0.2,l=>0,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Backlight mode"                       ,lit=>{off=>0,auto=>2}},
  backlOnMode2    =>{a=>  5.6,s=>0.2,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Backlight mode"                       ,lit=>{off=>0,on=>1}},
  ledMode         =>{a=>  5.6,s=>0.2,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"LED mode"                             ,lit=>{off=>0,on=>1}},
  displayInvert   =>{a=>  5.6,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"invert Display"                       ,lit=>{off=>0,on=>1}},
  statMsgTxtAlign =>{a=>  5.7,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Status message align"                 ,lit=>{right=>0,left=>1}},
  language        =>{a=>  7.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Language"                             ,lit=>{English=>0,German=>1}},
  backAtKey       =>{a=> 13.7,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Backlight at keystroke"               ,lit=>{off=>0,on=>1}},
  backAtMotion    =>{a=> 13.6,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Backlight at motion"                  ,lit=>{off=>0,on=>1}},
  backAtCharge    =>{a=> 13.5,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Backlight at Charge"                  ,lit=>{off=>0,on=>1}},
  stbyTime        =>{a=> 14.0,s=>1.0,l=>0,min=>1    ,max=>99    ,c=>''         ,p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"Standby Time"},
  stbyTime2       =>{a=> 14.0,s=>1.0,l=>0,min=>1    ,max=>120   ,c=>''         ,p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"Standby Time"},
  backOnTime      =>{a=> 14.0,s=>1.0,l=>0,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"Backlight On Time"},
  btnLock         =>{a=> 15.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Button Lock"                          ,lit=>{off=>0,on=>1}},#1 is proofen
# keymatic/winmatic secific register                                           
  keypressSignal  =>{a=>  3.0,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Keypress beep"                        ,lit=>{off=>0,on=>1}},
  lowBatSignal    =>{a=>  3.3,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Alarm on low battery"                 ,lit=>{off=>0,on=>1}},
  signal          =>{a=>  3.4,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Confirmation beep"                    ,lit=>{off=>0,on=>1}},
  signalTone      =>{a=>  3.6,s=>0.2,l=>0,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>""                                     ,lit=>{low=>0,mid=>1,high=>2,veryHigh=>3}},
                                                                              
  brightness      =>{a=>  4.0,s=>0.4,l=>0,min=>0    ,max=>15    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Display brightness"},
  energyOpt       =>{a=>  8.0,s=>1.0,l=>0,min=>0    ,max=>127   ,c=>''         ,p=>'n',f=>1       ,u=>'s'   ,d=>1,t=>"energy Option: Duration of ilumination",lit=>{permanent=>0}},
  powerSupply     =>{a=>  8.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"power supply option"                  ,lit=>{main=>0,bat=>1}},
# sec_mdir                                                                     
  cyclicInfoMsg   =>{a=>  9.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"cyclic message"                       ,lit=>{off=>0,on=>1,on_100=>200}},
  sabotageMsg     =>{a=> 16.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"enable sabotage message"              ,lit=>{off=>0,on=>1}},# sc needs 1 - others?
  cyclicInfoMsgDis=>{a=> 17.0,s=>1.0,l=>0,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"cyclic message"},
  lowBatLimit     =>{a=> 18.0,s=>1.0,l=>0,min=>10   ,max=>12    ,c=>''         ,p=>'n',f=>10      ,u=>'V'   ,d=>1,t=>"low batterie limit, step .1V"},
  lowBatLimitBA   =>{a=> 18.0,s=>1.0,l=>0,min=>5    ,max=>15    ,c=>''         ,p=>'n',f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  lowBatLimitBA2  =>{a=> 18.0,s=>1.0,l=>0,min=>0    ,max=>15    ,c=>''         ,p=>'n',f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  lowBatLimitBA3  =>{a=> 18.0,s=>1.0,l=>0,min=>0    ,max=>12    ,c=>''         ,p=>'n',f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  lowBatLimitFS   =>{a=> 18.0,s=>1.0,l=>0,min=>2    ,max=>3     ,c=>''         ,p=>'n',f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  lowBatLimitRT   =>{a=> 18.0,s=>1.0,l=>0,min=>2    ,max=>2.5   ,c=>''         ,p=>'n',f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  batDefectLimit  =>{a=> 19.0,s=>1.0,l=>0,min=>0.1  ,max=>2     ,c=>''         ,p=>'n',f=>100     ,u=>'Ohm' ,d=>1,t=>"batterie defect detection"},
  transmDevTryMax =>{a=> 20.0,s=>1.0,l=>0,min=>1    ,max=>10    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"max message re-transmit"},
  confBtnTime     =>{a=> 21.0,s=>1.0,l=>0,min=>1    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>'min' ,d=>0,t=>"255=permanent"                        ,lit=>{permanent=>255}},
#repeater                                                                      
  compMode        =>{a=> 23.0,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"compatibility moden"                  ,lit=>{off=>0,on=>1}},
  localResDis     =>{a=> 24.0,s=>1.0,l=>0,min=>1    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"local reset disable"                  ,lit=>{off=>0,on=>200}},
  globalBtnLock   =>{a=> 25.0,s=>1.0,l=>0,min=>1    ,max=>255   ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"global button lock"                   ,lit=>{off=>0,on=>200}},
  modusBtnLock    =>{a=> 26.0,s=>1.0,l=>0,min=>1    ,max=>255   ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"mode button lock"                     ,lit=>{off=>0,on=>200}},
  paramSel        =>{a=> 27.0,s=>1.0,l=>0,min=>0    ,max=>4     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"data transfered to peer"              ,lit=>{off=>0,T1=>1,T2=>2,T1_T2=>3,T2_T1=>4}},
  RS485IdleTime   =>{a=> 29.0,s=>1.0,l=>0,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"Idle Time"},
  speedMultiply   =>{a=> 30.0,s=>1.0,l=>0,min=>1    ,max=>5     ,c=>''         ,p=>'n',f=>''      ,u=>'x200Hz',d=>0,t=>"speed multiply"},
  devRepeatCntMax =>{a=> 31.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"act as repeater"},
  wakeupDefChan   =>{a=> 32.0,s=>1.0,l=>0,min=>0    ,max=>20    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"wakeup default channel"},
  wakeupBehavior  =>{a=> 33.0,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"wakeup behavior"                      ,lit=>{off=>0,on=>1}},
  wakeupBehavMsg  =>{a=> 33.1,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"wakeup behavior status message"           ,lit=>{off=>0,on=>1}},
  wakeupBehavMsg_R=>{a=> 33.2,s=>0.1,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"wakeup behavior status message resistance",lit=>{off=>0,on=>1}},
  alarmTimeMax    =>{a=> 34.0,s=>1.0,l=>0,min=>1    ,max=>900   ,c=>'fltCvT60' ,p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"maximum Alarm time"                   ,lit=>{unused=>0}},
                                                                               
  baudrate        =>{a=> 35.0,s=>1.0,l=>0,min=>0    ,max=>6     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"baudrate"                             ,lit=>{Bd300=>0,Bd600=>1,Bd1200=>2,Bd2400=>3,Bd4800=>4,Bd9600=>5,Bd19200=>6}},
  serialFormat    =>{a=> 36.0,s=>1.0,l=>0,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"serial Format"                        ,lit=>{s7D1PE1S=>0,s7D1PE2S=>1,s8D0PN1S=>2,s8D1PE1S=>3}},
  powerMode       =>{a=> 37.0,s=>1.0,l=>0,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"meter powermode"                      ,lit=>{mainPower=>0,batPower=>1}},
  protocolMode    =>{a=> 38.0,s=>1.0,l=>0,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"meter protocol mode"                  ,lit=>{modeA=>0,modeB=>1,modeC=>2,modeD=>3}},
  samplPerCycl    =>{a=> 39.0,s=>1.0,l=>0,min=>1    ,max=>10    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"samples per cycle"},
  
#rf_st_6_sh                r:TRANSMIT_DEV_TRY_MAX                     l:0   idx:20       size:1      type:integer    log## ty: integer    min:1.0        max:10.0       def:5.0        uni:           

 
#un-identified List0
# addr Dec!!
# SEC-WM55     02:01 (AES on?)
# CC-RT        02:01 16:00
# TC-IT        02:01 16:00
# SEC-WDS      02:01 16:01(sabotage) ?
# 4DIS         02:01 
# HM-SEC-MDIR  02:01 
# SEC-SC       02:00 
# Blind               9:00 10:00 20:00
# BL1TPBU      02:01 21:FF
# Dim1TPBU     02:01 21:FF 22:00
# HM-MOD-Re-8        30:49
# HM-ES-TX-WM        5C:38 F1:FC
# tx: D1E8  9158 

#Keymatic 3.3 unknown, seen 1 here

#--- list 1, Channel level------------------
#blindActuator mainly
  sign            =>{a=>  8.0,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"signature (AES)"                      ,lit=>{off=>0,on=>1}},
                                                                               
  driveDown       =>{a=> 11.0,s=>2.0,l=>1,min=>0    ,max=>6000.0,c=>''         ,p=>'n',f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveUp         =>{a=> 13.0,s=>2.0,l=>1,min=>0    ,max=>6000.0,c=>''         ,p=>'n',f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveTurn       =>{a=> 15.0,s=>1.0,l=>1,min=>0.5  ,max=>25.5  ,c=>''         ,p=>'n',f=>10      ,u=>'s'   ,d=>1,t=>"engine uncharge - fhem min = 0.5s for protection. HM min= 0s (use regBulk if necessary)"},
  refRunCounter   =>{a=> 16.0,s=>1.0,l=>1,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"start reference run after n non-end drives"},
#remote mainly                                                                 
  longPress       =>{a=>  4.4,s=>0.4,l=>1,min=>0.3  ,max=>1.8   ,c=>'m10s3'    ,p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"time to detect key long press"},
  dblPress        =>{a=>  9.0,s=>0.4,l=>1,min=>0    ,max=>1.5   ,c=>''         ,p=>'n',f=>10      ,u=>'s'   ,d=>0,t=>"time to detect double press"},
  msgShowTime     =>{a=> 45.0,s=>1.0,l=>1,min=>0.0  ,max=>120   ,c=>''         ,p=>'n',f=>2       ,u=>'s'   ,d=>1,t=>"Message show time(RC19). 0=always on"},
  beepAtAlarm     =>{a=> 46.0,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Beep Alarm"                           ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtService   =>{a=> 46.2,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Beep Service"                         ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtInfo      =>{a=> 46.4,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Beep Info"                            ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  backlAtAlarm    =>{a=> 47.0,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Backlight Alarm"                      ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtService  =>{a=> 47.2,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Backlight Service"                    ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtInfo     =>{a=> 47.4,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Backlight Info"                       ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
                                                                               
#dimmer  mainly                                                                
  loadErrCalib    =>{a=> 18.0,s=>1.0,l=>1,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>""    ,d=>0,t=>"Load Error Calibration"},
  transmitTryMax  =>{a=> 48.0,s=>1.0,l=>1,min=>1    ,max=>10    ,c=>''         ,p=>'n',f=>''      ,u=>""    ,d=>0,t=>"max message re-transmit"},
  loadAppearBehav =>{a=> 49.0,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>""    ,d=>1,t=>"behavior on load appearence at restart",lit=>{off=>0,last=>1,btnPress=>2,btnPressIfWasOn=>3}},
  ovrTempLvl      =>{a=> 50.0,s=>1.0,l=>1,min=>30   ,max=>100   ,c=>''         ,p=>'n',f=>''      ,u=>"C"   ,d=>0,t=>"overtemperatur level"},
  fuseDelay       =>{a=> 51.0,s=>1.0,l=>1,min=>0    ,max=>2.55  ,c=>''         ,p=>'n',f=>100     ,u=>"s"   ,d=>0,t=>"fuse delay"},
  redTempLvl      =>{a=> 52.0,s=>1.0,l=>1,min=>30   ,max=>100   ,c=>''         ,p=>'n',f=>''      ,u=>"C"   ,d=>0,t=>"reduced temperatur recover"},
  redLvl          =>{a=> 53.0,s=>1.0,l=>1,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>2       ,u=>"%"   ,d=>0,t=>"reduced power level"},
  powerUpAction   =>{a=> 86.0,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>""    ,d=>1,t=>"on: simulate short press of peer self01 (self02 if dual buttons) after power up",lit=>{off=>0,on=>1}},
  statusInfoMinDly=>{a=> 87.0,s=>0.5,l=>1,min=>0    ,max=>15.5  ,c=>''         ,p=>'n',f=>2       ,u=>"s"   ,d=>0,t=>"status message min delay"             ,lit=>{unused=>0}},
  statusInfoRandom=>{a=> 87.5,s=>0.3,l=>1,min=>0    ,max=>7     ,c=>''         ,p=>'n',f=>''      ,u=>"s"   ,d=>0,t=>"status message random delay"},
  characteristic  =>{a=> 88.0,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>""    ,d=>1,t=>""                                     ,lit=>{linear=>0,square=>1}},
  charactLvlLimit =>{a=> 88.1,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>""    ,d=>1,t=>""                                     ,lit=>{halfConst=>0,max=>1}},
  charactColAssign=>{a=> 88.2,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>""    ,d=>1,t=>""                                     ,lit=>{warm=>0,cold=>1}},
  charactBase     =>{a=> 88.4,s=>0.4,l=>1,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>""    ,d=>1,t=>""                                     ,lit=>{crossfade=>0,dim2warm=>1,dim2hot=>2}},
  logicCombination=>{a=> 89.0,s=>0.5,l=>1,min=>0    ,max=>16    ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{inactive=>0,or=>1,and=>2,xor=>3,nor=>4,nand=>5,orinv=>6,andinv=>7,plus=>8,minus=>9,mul=>10,plusinv=>11,minusinv=>12,mulinv=>13,invPlus=>14,invMinus=>15,invMul=>16}},
#SCD                                                                           
  msgScdPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position A"               ,lit=>{noMsg=>0,lvlNormal=>1}},
  msgScdPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position B"               ,lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  msgScdPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position C"               ,lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  msgScdPosD      =>{a=> 32.0,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position D"               ,lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
#wds - different literals                                                                                                                            
  msgWdsPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position A"               ,lit=>{noMsg=>0,dry=>1}},
  msgWdsPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position B"               ,lit=>{noMsg=>0,dry=>1,water=>2,wet=>3}},
  msgWdsPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position C"               ,lit=>{noMsg=>0,       water=>2,wet=>3}},
#rhs - different literals                                                                                                                            
  msgRhsPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position A"               ,lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  msgRhsPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position B"               ,lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  msgRhsPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position C"               ,lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
#SC - different literals                                                                                                                            
  msgScPosA       =>{a=> 32.6,s=>0.2,l=>1,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position A"               ,lit=>{noMsg=>0,closed=>1,open=>2}},
  msgScPosB       =>{a=> 32.4,s=>0.2,l=>1,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Message for position B"               ,lit=>{noMsg=>0,closed=>1,open=>2}},
# keymatic/winmatic specific register                                          
  holdTime        =>{a=> 20  ,s=>1,  l=>1,min=>0    ,max=>8.16  ,c=>''         ,p=>'n',f=>31.25   ,u=>'s'   ,d=>0,t=>"Holdtime for door opening"},
  holdPWM         =>{a=> 21  ,s=>1,  l=>1,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Holdtime pulse wide modulation"},
  setupDir        =>{a=> 22  ,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Rotation direction for locking"       ,lit=>{right=>0,left=>1}},
  setupPosition   =>{a=> 23  ,s=>1  ,l=>1,min=>0    ,max=>3000  ,c=>''         ,p=>'n',f=>0.06666 ,u=>'deg' ,d=>1,t=>"Rotation angle neutral position"},
  angelOpen       =>{a=> 24  ,s=>1  ,l=>1,min=>0    ,max=>3000  ,c=>''         ,p=>'n',f=>0.06666 ,u=>'deg' ,d=>1,t=>"Door opening angle"},
  angelMax        =>{a=> 25  ,s=>1  ,l=>1,min=>0    ,max=>3000  ,c=>''         ,p=>'n',f=>0.06666 ,u=>'deg' ,d=>1,t=>"Angle maximum"},
  angelLocked     =>{a=> 26  ,s=>1  ,l=>1,min=>0    ,max=>3000  ,c=>''         ,p=>'n',f=>0.06666 ,u=>'deg' ,d=>1,t=>"Angle Locked position"},
  pullForce       =>{a=> 28  ,s=>1  ,l=>1,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>2       ,u=>'%'   ,d=>1,t=>"pull force level"},
  pushForce       =>{a=> 29  ,s=>1  ,l=>1,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>2       ,u=>'%'   ,d=>1,t=>"push force level"},
  tiltMax         =>{a=> 30  ,s=>1  ,l=>1,min=>0    ,max=>255   ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"maximum tilt level"},
  ledFlashUnlocked=>{a=> 31.3,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"LED blinks when not locked"           ,lit=>{off=>0,on=>1}},
  ledFlashLocked  =>{a=> 31.6,s=>0.1,l=>1,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"LED blinks when locked"               ,lit=>{off=>0,on=>1}},
                                                                               
  seqPulse1       =>{a=> 36  ,s=>1  ,l=>1,min=>0    ,max=>4.08  ,c=>''         ,p=>'n',f=>62.5    ,u=>'s'   ,d=>1,t=>"Sequence Pulse. 0= unused, otherwise min= 0.032sec"},
  seqPulse2       =>{a=> 37  ,s=>1  ,l=>1,min=>0    ,max=>4.08  ,c=>''         ,p=>'n',f=>62.5    ,u=>'s'   ,d=>1,t=>"Sequence Pulse. 0= unused, otherwise min= 0.032sec"},
  seqPulse3       =>{a=> 38  ,s=>1  ,l=>1,min=>0    ,max=>4.08  ,c=>''         ,p=>'n',f=>62.5    ,u=>'s'   ,d=>1,t=>"Sequence Pulse. 0= unused, otherwise min= 0.032sec"},
  seqPulse4       =>{a=> 39  ,s=>1  ,l=>1,min=>0    ,max=>4.08  ,c=>''         ,p=>'n',f=>62.5    ,u=>'s'   ,d=>1,t=>"Sequence Pulse. 0= unused, otherwise min= 0.032sec"},
  seqPulse5       =>{a=> 40  ,s=>1  ,l=>1,min=>0    ,max=>4.08  ,c=>''         ,p=>'n',f=>62.5    ,u=>'s'   ,d=>1,t=>"Sequence Pulse. 0= unused, otherwise min= 0.032sec"},
  seqTolerance    =>{a=> 44  ,s=>1  ,l=>1,min=>0.016,max=>4.08  ,c=>''         ,p=>'n',f=>62.5    ,u=>'s'   ,d=>1,t=>"Sequence tolernace"},
                                                                               
  waterUppThr     =>{a=>  6.0,s=>1  ,l=>1,min=>0    ,max=>256   ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"water upper threshold"},
  waterlowThr     =>{a=>  7.0,s=>1  ,l=>1,min=>0    ,max=>256   ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"water lower threshold"},
    # change 90 to 91 due to log: reg 90 not available but 91 available...     
  caseDesign      =>{a=> 91.0,s=>1  ,l=>1,min=>1    ,max=>3      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"case desing"                          ,lit=>{verticalBarrel=>1,horizBarrel=>2,rectangle=>3}},
  caseHigh        =>{a=> 94.0,s=>2  ,l=>1,min=>100  ,max=>10000  ,c=>''        ,p=>'n',f=>''      ,u=>'cm'  ,d=>1,t=>"case hight"},
  fillLevel       =>{a=> 98.0,s=>2  ,l=>1,min=>100  ,max=>300    ,c=>''        ,p=>'n',f=>''      ,u=>'cm'  ,d=>1,t=>"fill level"},
  caseWidth       =>{a=>102.0,s=>2  ,l=>1,min=>100  ,max=>10000  ,c=>''        ,p=>'n',f=>''      ,u=>'cm'  ,d=>1,t=>"case width"},
  caseLength      =>{a=>106.0,s=>2  ,l=>1,min=>100  ,max=>10000  ,c=>''        ,p=>'n',f=>''      ,u=>'cm'  ,d=>1,t=>"case length"},
  meaLength       =>{a=>108.0,s=>2  ,l=>1,min=>110  ,max=>310    ,c=>''        ,p=>'n',f=>''      ,u=>'cm'  ,d=>1,t=>""},
  useCustom       =>{a=>110.0,s=>1  ,l=>1,min=>110  ,max=>310    ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"use custom"                           ,lit=>{off=>0,on=>200}},
                                                                               
  averaging       =>{a=>122.0,s=>1  ,l=>1,min=>1    ,max=>16     ,c=>''        ,p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"averaging period"},
  txMinDly        =>{a=>123.0,s=>0.7,l=>1,min=>0    ,max=>16     ,c=>''        ,p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"min transmit delay"},
  txThrPwr        =>{a=>124.0,s=>3  ,l=>1,min=>0.01 ,max=>3680   ,c=>''        ,p=>'n',f=>100     ,u=>'W'   ,d=>1,t=>"threshold power"                      ,lit=>{unused=>0}},
  txThrCur        =>{a=>127.0,s=>2  ,l=>1,min=>0    ,max=>16000  ,c=>''        ,p=>'n',f=>''      ,u=>'mA'  ,d=>1,t=>"threshold current"                    ,lit=>{unused=>0}},
  txThrVlt        =>{a=>129.0,s=>2  ,l=>1,min=>0.0  ,max=>230    ,c=>''        ,p=>'n',f=>10      ,u=>'V'   ,d=>1,t=>"threshold voltage"                    ,lit=>{unused=>0}},
  txThrFrq        =>{a=>131.0,s=>1  ,l=>1,min=>0.00 ,max=>2.55   ,c=>''        ,p=>'n',f=>100     ,u=>'Hz'  ,d=>1,t=>"threshold frequency"                  ,lit=>{unused=>0}},
                                                                               
  cndTxFalling    =>{a=>132.0,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"trigger if falling"                            ,lit=>{off=>0,on=>1}},
  cndTxRising     =>{a=>132.1,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"trigger if rising"                             ,lit=>{off=>0,on=>1}},
  cndTxCycBelow   =>{a=>132.2,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"cyclic trigger if level is below cndTxCycBelow",lit=>{off=>0,on=>1}},
  cndTxCycAbove   =>{a=>132.3,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"cyclic trigger if level is above cndTxDecAbove",lit=>{off=>0,on=>1}},
  cndTxDecAbove   =>{a=>133  ,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>''        ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"decission level for cndTxCycAbove"},
  cndTxDecBelow   =>{a=>134  ,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>''        ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"decission level for cndTxCycBelow"},
                                                                               
  txThrHiPwr      =>{a=>135.0,s=>4  ,l=>1,min=>0    ,max=>3680   ,c=>''        ,p=>'n',f=>'100'   ,u=>'W'   ,d=>1,t=>"threshold low power"},
  txThrLoPwr      =>{a=>139.0,s=>4  ,l=>1,min=>0    ,max=>3680   ,c=>''        ,p=>'n',f=>'100'   ,u=>'W'   ,d=>1,t=>"threshold high power"},
  txThrHiCur      =>{a=>135.0,s=>4  ,l=>1,min=>0    ,max=>16000  ,c=>''        ,p=>'n',f=>''      ,u=>'mA'  ,d=>1,t=>"threshold low current"},
  txThrLoCur      =>{a=>139.0,s=>4  ,l=>1,min=>0    ,max=>16000  ,c=>''        ,p=>'n',f=>''      ,u=>'mA'  ,d=>1,t=>"threshold high current"},
  txThrHiVlt      =>{a=>135.0,s=>4  ,l=>1,min=>115  ,max=>255    ,c=>''        ,p=>'n',f=>'10'    ,u=>'V'   ,d=>1,t=>"threshold low voltage"},
  txThrLoVlt      =>{a=>139.0,s=>4  ,l=>1,min=>115  ,max=>255    ,c=>''        ,p=>'n',f=>'10'    ,u=>'V'   ,d=>1,t=>"threshold high voltage"},
  txThrHiFrq      =>{a=>135.0,s=>4  ,l=>1,min=>48.72,max=>51.27  ,c=>''        ,p=>'n',f=>'100'   ,u=>'Hz'  ,d=>1,t=>"threshold low frequency"},
  txThrLoFrq      =>{a=>139.0,s=>4  ,l=>1,min=>48.72,max=>51.27  ,c=>''        ,p=>'n',f=>'100'   ,u=>'Hz'  ,d=>1,t=>"threshold high frequency"},
                                                                               
  voltage_0       =>{a=>173.0,s=>1  ,l=>1,min=>0    ,max=>0.2    ,c=>''        ,p=>'n',f=>'200'   ,u=>'%'   ,d=>1,t=>"lower Voltage"},
  voltage_100     =>{a=>174.0,s=>1  ,l=>1,min=>0.3  ,max=>1.0    ,c=>''        ,p=>'n',f=>'200'   ,u=>'%'   ,d=>1,t=>"higher Voltage"},
  relayDelay      =>{a=>175.0,s=>1  ,l=>1,min=>0    ,max=>111600 ,c=>'fltCvT'  ,p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"relay off delay time"},
                                                                               
  evtFltrPeriod   =>{a=>  1.0,s=>0.4,l=>1,min=>0.5  ,max=>7.5    ,c=>''        ,p=>'n',f=>2       ,u=>'s'   ,d=>1,t=>"event filter period"},
  evtFltrNum      =>{a=>  1.4,s=>0.4,l=>1,min=>1    ,max=>15     ,c=>''        ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"sensitivity - read each n-th puls"},
  minInterval     =>{a=>  2.0,s=>0.3,l=>1,min=>0    ,max=>4      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"interval in sec"                                         ,lit=>{15=>0,30=>1,60=>2,120=>3,240=>4}},
  captInInterval  =>{a=>  2.3,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"capture motion in interval, send result in next trigger" ,lit=>{off=>0,on=>1}},
  brightFilter    =>{a=>  2.4,s=>0.4,l=>1,min=>0    ,max=>7      ,c=>''        ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"7: filter fast changes to 0: no filter of light changes"},
  eventDlyTime    =>{a=> 33  ,s=>1  ,l=>1,min=>0    ,max=>7620   ,c=>'fltCvT60',p=>'n',f=>''      ,u=>'s'   ,d=>1,t=>"filters short events, causes reporting delay"},
  ledOnTime       =>{a=> 34  ,s=>1  ,l=>1,min=>0    ,max=>1.275  ,c=>''        ,p=>'n',f=>200     ,u=>'s'   ,d=>0,t=>"LED ontime"},
  eventFilterTime =>{a=> 35  ,s=>1  ,l=>1,min=>0    ,max=>7620   ,c=>'fltCvT60',p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"event filter time"},
  eventFilterTimeB=>{a=> 35  ,s=>1  ,l=>1,min=>5    ,max=>7620   ,c=>'fltCvT60',p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"event filter time"},
# - different range                                                            
  evtFltrTime     =>{a=> 35.0,s=>1  ,l=>1,min=>600  ,max=>1200   ,c=>'fltCvT'  ,p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"event filter time"},
                                                                               
# weather units                                                                
  sunThresh       =>{a=>  5  ,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>''        ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"Sunshine threshold"},
  stormUpThresh   =>{a=>  6  ,s=>1  ,l=>1,min=>0    ,max=>200    ,c=>''        ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"Storm upper threshold"},
  stormLowThresh  =>{a=>  7  ,s=>1  ,l=>1,min=>0    ,max=>200    ,c=>''        ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"Storm lower threshold"},
  windSpeedRsltSrc=>{a=> 10  ,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"wind result source"                   ,lit=>{average=>0,max=>1}},
# others                                                                       
  localResetDis   =>{a=>  7  ,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"LocalReset disable"                   ,lit=>{off=>0,on=>200}},
                                                                               
  cndTxThrhHi     =>{a=>135  ,s=>2  ,l=>1,min=>0    ,max=>3000   ,c=>''        ,p=>'n',f=>''      ,u=>'mV'  ,d=>0,t=>"threshold high condition"},
  cndTxThrhLo     =>{a=>139  ,s=>2  ,l=>1,min=>0    ,max=>3000   ,c=>''        ,p=>'n',f=>''      ,u=>'mV'  ,d=>0,t=>"threshold high condition"},
  highHoldTime    =>{a=>143  ,s=>1  ,l=>1,min=>60   ,max=>7620   ,c=>'fltCvT60',p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"hold time on high state"},
  evntRelFltTime  =>{a=>145  ,s=>1  ,l=>1,min=>1    ,max=>7620   ,c=>'fltCvT60',p=>'n',f=>''      ,u=>'s'   ,d=>0,t=>"event filter release time "},
  triggerMode     =>{a=>146.0,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"define type of event report "         ,lit=>{off=>0,sensor=>33,switch=>34,button=>35}},
  mtrType         =>{a=>149.0,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"type of measurement"                 ,lit=>{gas=>1,IR=>2,LED=>4,IEC=>8,unknown=>255}},
  mtrConstIr      =>{a=>150.0,s=>2  ,l=>1,min=>1    ,max=>65536  ,c=>''        ,p=>'n',f=>''      ,u=>'U/kWh',d=>0,t=>"constant IR"},
  mtrConstGas     =>{a=>152.0,s=>2  ,l=>1,min=>0.001,max=>65.536 ,c=>''        ,p=>'n',f=>1000    ,u=>'m3/I' ,d=>0,t=>"constant gas"},
  mtrConstLed     =>{a=>154.0,s=>2  ,l=>1,min=>1    ,max=>65536  ,c=>''        ,p=>'n',f=>''      ,u=>'i/kWh',d=>0,t=>"constant led"},
  mtrSensIr       =>{a=>156.0,s=>1  ,l=>1,min=>-99  ,max=>99     ,c=>''        ,p=>'n',f=>''      ,u=>'%'    ,d=>0,t=>"sensiblity IR"},
                                                                               
  humDesVal       =>{a=>157.0,s=>1  ,l=>1,min=>0    ,max=>7      ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"humidity desired value"},
  watDuration     =>{a=>158.0,s=>1  ,l=>1,min=>0    ,max=>90     ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"watering duration"},
  wat1_hour       =>{a=>159.0,s=>1  ,l=>1,min=>0    ,max=>24     ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"watering hour 1"},
  wat1_min        =>{a=>160.0,s=>1  ,l=>1,min=>0    ,max=>60     ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"watering minutes 1"},
  wat2_hour       =>{a=>161.0,s=>1  ,l=>1,min=>0    ,max=>24     ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"watering hour 2"},
  wat2_min        =>{a=>162.0,s=>1  ,l=>1,min=>0    ,max=>60     ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"watering minutes 2"},
  eco_days        =>{a=>163.0,s=>1  ,l=>1,min=>0    ,max=>7      ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"eco days"},
                                                                               
  waRed           =>{a=>164.0,s=>1  ,l=>1,min=>0    ,max=>100    ,c=>''        ,p=>'n',f=>''      ,u=>'%'    ,d=>0,t=>"whitebalance red"},
  waGreen         =>{a=>165.0,s=>1  ,l=>1,min=>0    ,max=>100    ,c=>''        ,p=>'n',f=>''      ,u=>'%'    ,d=>0,t=>"whitebalance green"},
  waBlue          =>{a=>166.0,s=>1  ,l=>1,min=>0    ,max=>100    ,c=>''        ,p=>'n',f=>''      ,u=>'%'    ,d=>0,t=>"whitebalance blue"},
  colChangeSpeed  =>{a=>167.0,s=>1  ,l=>1,min=>0    ,max=>255    ,c=>''        ,p=>'n',f=>''      ,u=>'s/U'  ,d=>0,t=>"color change speed"},
                                                                               
  acusticMultiDly =>{a=>169.7,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"acustic mutli exec delay"      ,lit=>{off=>0,on=>1}},
  acusticArmSens  =>{a=>169.4,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"acustic arm sensor"            ,lit=>{off=>0,on=>1}},
  acusticArmDly   =>{a=>169.3,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"acustic delay arm"             ,lit=>{off=>0,on=>1}},
  acusticExtArm   =>{a=>169.2,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"acustic external arm sensor"   ,lit=>{off=>0,on=>1}},
  acusticExtDly   =>{a=>169.1,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"acustic external delay arm"    ,lit=>{off=>0,on=>1}},
  acusticDisArm   =>{a=>169.0,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"acustic disarm "               ,lit=>{off=>0,on=>1}},
  opticMultiDly   =>{a=>170.7,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"optic mutli exec delay"        ,lit=>{off=>0,on=>1}},
  opticArmSens    =>{a=>170.4,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"optic arm sensor"              ,lit=>{off=>0,on=>1}},
  opticArmDly     =>{a=>170.3,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"optic delay arm"               ,lit=>{off=>0,on=>1}},
  opticExtArm     =>{a=>170.2,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"optic external arm sensor"     ,lit=>{off=>0,on=>1}},
  opticExtDly     =>{a=>170.1,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"optic external delay arm"      ,lit=>{off=>0,on=>1}},
  opticDisArm     =>{a=>170.0,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"optic disarm "                 ,lit=>{off=>0,on=>1}},
  soundId         =>{a=>171.0,s=>1  ,l=>1,min=>0    ,max=>72     ,c=>''        ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"sound ID"                     ,lit=>{unused=>0}},
                                                                               
  txThresPercent  =>{a=>172.0,s=>1  ,l=>1,min=>10   ,max=>100    ,c=>''        ,p=>'n',f=>''      ,u=>'%'    ,d=>0,t=>"threshold percent"            ,lit=>{unused=>0}},
  dataTransCond   =>{a=>176.0,s=>1  ,l=>1,min=>10   ,max=>111600 ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>1,t=>"dataTransmitCondition"        ,lit=>{lvlChng_H_L=>0,lvlChng_L_H=>1,lvlChng_any=>2,stbl4TimeEnable=>3,sndImmediateEnable=>4,stbl4TimeDisable=>5,sndImmediateDisable=>6}},
  stabFltTime     =>{a=>177.0,s=>1  ,l=>1,min=>10   ,max=>111600 ,c=>'fltCvT'  ,p=>'n',f=>''      ,u=>'s'    ,d=>0,t=>"stability filter time"},
                                                                               
  dInProp0        =>{a=>178.0,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp1        =>{a=>178.1,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp2        =>{a=>178.2,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp3        =>{a=>178.3,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp4        =>{a=>178.4,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp5        =>{a=>178.5,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp6        =>{a=>178.6,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
  dInProp7        =>{a=>178.7,s=>0.1,l=>1,min=>0    ,max=>1      ,c=>'lit'     ,p=>'n',f=>''      ,u=>''     ,d=>0,t=>"Data Input Propertie"         ,lit=>{off=>0,on=>1}},
                                                                               
  refRunTimeSlats =>{a=>179  ,s=>2  ,l=>1,min=>0    ,max=>10     ,c=>''        ,p=>'n',f=>50      ,u=>'s'    ,d=>0,t=>"reference run time slats"     ,lit=>{off=>0,on=>1}},
  posSaveTime     =>{a=>181  ,s=>1  ,l=>1,min=>0.1  ,max=>25.5   ,c=>''        ,p=>'n',f=>10      ,u=>'s'    ,d=>0,t=>"position save time"           ,lit=>{off=>0,on=>1}},
#rf_es_tx_wm               r:TX_THRESHOLD_POWER                       l:1   idx:124      size:3      type:integer    log## ty: float      min:0.01       max:160000.0   def:100.00     uni:W         Conv## ty: float_integer_scale            factor:100        offset:           
#rf_es_tx_wm               r:METER_TYPE                               l:1   idx:149      size:1      type:integer    log## ty: option     min:           max:           def:           uni:          Conv## ty: option_integer                 factor:           offset:           
#rf_es_tx_wm               r:POWER_STRING                             l:1   idx:54       size:16     type:string     log## ty: string     min:           max:           def:           uni:           
#rf_es_tx_wm               r:ENERGY_COUNTER_STRING                    l:1   idx:70       size:16     type:string     log## ty: string     min:           max:           def:           uni:           

#rf_hm-wds100-c6-o-2       r:SUNSHINE_THRESHOLD                       l:1   idx:5.0      size:1.0    type:integer    log## ty: integer    min:0          max:0xff       def:           uni:           
#rf_hm-wds100-c6-o-2       r:WIND_SPEED_RESULT_SOURCE                 l:1   idx:10       size:1.0    type:integer    log## ty: option     min:           max:           def:           uni:           
#rf_hm-wds100-c6-o-2       r:STORM_UPPER_THRESHOLD                    l:1   idx:6.0      size:1.0    type:integer    log## ty: integer    min:0          max:0xff       def:           uni:           
#rf_hm-wds100-c6-o-2       r:STORM_LOWER_THRESHOLD                    l:1   idx:7.0      size:1.0    type:integer    log## ty: integer    min:0          max:0xff       def:           uni:           


  #un-identified List1
# SEC-WM55 08:01 (AES on?)
# SEC-WDS  34:0x64 ?
# SEC-SC   08:00 ?
# RC19     08:00 ? RC19 Button 08:08
# Bl1PBU   08:00 09:00 10:00
# ES-PMSw1-Pl Ch1 : 93:20 94:45

#  logicCombination=>{a=> 89.0,s=>0.5,l=>1,min=>0  ,max=>16      ,c=>'lit'     ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"".
#                                                                                                              "inactive=>unused\n".
#                                                                                                              "or      =>max(state,chan)\n".
#                                                                                                              "and     =>min(state,chan)\n".
#                                                                                                              "xor     =>0 if both are != 0, else max\n".
#                                                                                                              "nor     =>100-max(state,chan)\n".
#                                                                                                              "nand    =>100-min(state,chan)\n".
#                                                                                                              "orinv   =>max((100-chn),state)\n".
#                                                                                                              "andinv  =>min((100-chn),state)\n".
#                                                                                                              "plus    =>state + chan\n".
#                                                                                                              "minus   =>state - chan\n".
#                                                                                                              "mul     =>state * chan\n".
#                                                                                                              "plusinv =>state + 100 - chan\n".
#                                                                                                              "minusinv=>state - 100 + chan\n".
#                                                                                                              "mulinv  =>state * (100 - chan)\n".
#                                                                                                              "invPlus =>100 - state - chan\n".
#                                                                                                              "invMinus=>100 - state + chan\n".
#                                                                                                              "invMul  =>100 - state * chan\n",lit=>{inactive=>0,or=>1,and=>2,xor=>3,nor=>4,nand=>5,orinv=>6,andinv=>7,plus=>8,minus=>9,mul=>10,plusinv=>11,minusinv=>12,mulinv=>13,invPlus=>14,invMinus=>15,invMul=>16}},
#
#
#CC-TC

#--- list 3, link level for actor - mainly in short/long hash, only specials here------------------
  lgMultiExec     =>{a=>138.5,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"execution per repeat message"         ,lit=>{off=>0,on=>1}},
  shMultiExec     =>{a=> 10.5,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>0,t=>"reg unused, placeholder only"         ,lit=>{off=>0,on=>1}},
#--- list 4, link level for Button ------------------                          
  peerNeedsBurst  =>{a=>  1.0,s=>0.1,l=>4,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"peer expects burst"                   ,lit=>{off=>0,on=>1}},
  expectAES       =>{a=>  1.7,s=>0.1,l=>4,min=>0    ,max=>1     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"expect AES"                           ,lit=>{off=>0,on=>1}},
  lcdSymb         =>{a=>  2.0,s=>0.1,l=>4,min=>0    ,max=>8     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"symbol to display on message"         ,lit=>{"none"=>0,"bulb"=>1,"switch"=>2,"window"=>3,"door"=>4,"blind"=>5,"scene"=>6,"phone"=>7,"bell"=>8}},
  lcdLvlInterp    =>{a=>  3.0,s=>0.1,l=>4,min=>0    ,max=>5     ,c=>'lit'      ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"bitmask for symbols"                  ,lit=>{"none"=>0,"light"=>1,"blind"=>2,"marquee"=>3,"door"=>4,"window"=>5}},
                                                                               
  fillLvlUpThr    =>{a=>  4.0,s=>1  ,l=>4,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"fill level upper threshold"},
  fillLvlLoThr    =>{a=>  5.0,s=>1  ,l=>4,min=>0    ,max=>255   ,c=>''         ,p=>'y',f=>''      ,u=>''    ,d=>1,t=>"fill level lower threshold"},

#rf_hm-wds100-c6-o-2       r:PEER_NEEDS_BURST                         l:4   idx:1.0      size:1.0    type:integer    log## ty: integer    min:0          max:0xff       def:           uni:           
  
#rf_st_6_sh                r:PEER_NEEDS_BURST                         l:4   idx:1.0      size:0.1    type:integer    log## ty: boolean    min:           max:           def:false      uni:           
#rf_st_6_sh                r:EXPECT_AES                               l:4   idx:1.7      size:0.1    type:integer    log## ty: boolean    min:           max:           def:false      uni:           
  
#--- list 5,6 parameter for channel --------------  ----
  displayMode     =>{a=>  1.0,s=>0.1,l=>5,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{"temp-only"=>0,"temp-hum"=>1}},
  displayTemp     =>{a=>  1.1,s=>0.1,l=>5,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{actual=>0,setpoint=>1}},
  displayTempUnit =>{a=>  1.2,s=>0.1,l=>5,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{celsius=>0,fahrenheit=>1}},
  controlMode     =>{a=>  1.3,s=>0.2,l=>5,min=>0    ,max=>3     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{manual=>0,auto=>1,central=>2,party=>3}},
  decalcDay       =>{a=>  1.5,s=>0.3,l=>5,min=>0    ,max=>7     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"Decalc weekday"                       ,lit=>{Sat=>0,Sun=>1,Mon=>2,Tue=>3,Wed=>4,Thu=>5,Fri=>6}},
  mdTempValve     =>{a=>  2.6,s=>0.2,l=>5,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>""                                     ,lit=>{auto=>0,close=>1,open=>2}},
  "day-temp"      =>{a=>  3  ,s=>0.6,l=>5,min=>6    ,max=>30    ,c=>''         ,p=>'n',f=>2       ,u=>'C'   ,d=>1,t=>"comfort or day temperatur"},
  "night-temp"    =>{a=>  4  ,s=>0.6,l=>5,min=>6    ,max=>30    ,c=>''         ,p=>'n',f=>2       ,u=>'C'   ,d=>1,t=>"lower or night temperatur"},
  tempWinOpen     =>{a=>  5  ,s=>0.6,l=>5,min=>6    ,max=>30    ,c=>''         ,p=>'y',f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Win open"},
  "party-temp"    =>{a=>  6  ,s=>0.6,l=>5,min=>6    ,max=>30    ,c=>''         ,p=>'n',f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Party"},
  decalMin        =>{a=>  8  ,s=>0.3,l=>5,min=>0    ,max=>50    ,c=>''         ,p=>'n',f=>0.1     ,u=>'min' ,d=>0,t=>"Decalc min"},
  decalHr         =>{a=>  8.3,s=>0.5,l=>5,min=>0    ,max=>23    ,c=>''         ,p=>'n',f=>''      ,u=>'h'   ,d=>0,t=>"Decalc hour"},
                                                                               
  partyEndHr      =>{a=> 97  ,s=>0.6,l=>6,min=>0    ,max=>23    ,c=>''         ,p=>'n',f=>''      ,u=>'h'   ,d=>1,t=>"Party end hour. Use cmd partyMode to set"},
  partyEndMin     =>{a=> 97.7,s=>0.1,l=>6,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>'min' ,d=>1,t=>"Party end min. Use cmd partyMode to set"   ,lit=>{"00"=>0,"30"=>1}},
  partyEndDay     =>{a=> 98  ,s=>1  ,l=>6,min=>0    ,max=>200   ,c=>''         ,p=>'n',f=>''      ,u=>'d'   ,d=>1,t=>"Party duration days. Use cmd partyMode to set"},
#Thermal-cc-VD                                                                 
  valveOffset     =>{a=>  9  ,s=>0.5,l=>5,min=>0    ,max=>25    ,c=>''         ,p=>'n',f=>''      ,u=>'%'   ,d=>1,t=>"Valve offset"},             # size actually 0.5
  valveErrorPos   =>{a=> 10  ,s=>1  ,l=>5,min=>0    ,max=>99    ,c=>''         ,p=>'n',f=>''      ,u=>'%'   ,d=>1,t=>"Valve position when error"},# size actually 0.7
                                                                               
  dayTemp         =>{a=>  1  ,s=>0.6,l=>7,min=>15   ,max=>30    ,c=>''         ,p=>'n',f=>'2'     ,u=>'C'   ,d=>1,t=>"comfort or day temperatur"},
  nightTemp       =>{a=>  2  ,s=>0.6,l=>7,min=>5    ,max=>25    ,c=>''         ,p=>'n',f=>'2'     ,u=>'C'   ,d=>1,t=>"lower or night temperatur"},
  tempMin         =>{a=>  3  ,s=>0.6,l=>7,min=>4.5  ,max=>14.5  ,c=>''         ,p=>'n',f=>'2'     ,u=>'C'   ,d=>0,t=>"minimum temperatur"},
  tempMax         =>{a=>  4  ,s=>0.6,l=>7,min=>15   ,max=>30.5  ,c=>''         ,p=>'n',f=>'2'     ,u=>'C'   ,d=>0,t=>"maximum temperatur"},
  winOpnTempI     =>{a=>  5  ,s=>0.6,l=>7,min=>5    ,max=>30    ,c=>''         ,p=>'n',f=>'2'     ,u=>'C'   ,d=>0,t=>"lowering temp when Window is opened - internal detector"},
  winOpnTemp      =>{a=>  5  ,s=>0.6,l=>7,min=>5    ,max=>30    ,c=>''         ,p=>'y',f=>'2'     ,u=>'C'   ,d=>0,t=>"lowering temp when Window is opened"},
  winOpnPeriod    =>{a=>  6  ,s=>0.4,l=>7,min=>0    ,max=>60    ,c=>''         ,p=>'n',f=>'0.2'   ,u=>'min' ,d=>0,t=>"period lowering when window is open"},
  decalcWeekday   =>{a=>  7  ,s=>0.3,l=>7,min=>0    ,max=>7     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"decalc at day"                        ,lit=>{Sat=>0,Sun=>1,Mon=>2,Tue=>3,Wed=>4,Thu=>5,Fri=>6}},
  decalcTime      =>{a=>  8  ,s=>0.6,l=>7,min=>0    ,max=>1410  ,c=>'min2time' ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"decalc at hour"},
  tempOffset      =>{a=>  9  ,s=>0.4,l=>7,min=>0    ,max=>15    ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"temperature offset"                   ,lit=>{"-3.5K"=>0,"-3.0K"=>1,"-2.5K"=>2,"-2.0K"=>3,"-1.5K"=>4,"-1.0K"=>5,"-0.5K"=>6,
                                                                                                                                        "0.0K"=>7, "0.5K"=>8, "1.0K"=>9, "1.5K"=>10, "2.0K"=>11, "2.5K"=>12, "3.0K"=>13, "3.5K"=>14}},
  btnNoBckLight   =>{a=>  9.4,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"button response without backlight"    ,lit=>{off=>0,on=>1}},
  showSetTemp     =>{a=>  9.5,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"show set or actual temperature"       ,lit=>{actTemp=>0,setTemp=>1}},
  showHumidity    =>{a=>  9.6,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"show temp only or also humidity"      ,lit=>{temp=>0,tempHum=>1}},
  sendWeatherData =>{a=>  9.7,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"send  weather data"                   ,lit=>{off=>0,on=>1}},
                                                                               
  boostPos        =>{a=> 10.0,s=>0.5,l=>7,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>'0.2'   ,u=>'%'   ,d=>1,t=>"valve boost position"},
  boostPeriod     =>{a=> 10.5,s=>0.3,l=>7,min=>0    ,max=>6     ,c=>'lit'      ,p=>'n',f=>''      ,u=>'min' ,d=>0,t=>"boost period [min]"                   ,lit=>{0=>0,5=>1,10=>2,15=>3,20=>4,25=>5,30=>6}},
  valveOffsetRt   =>{a=> 11  ,s=>0.7,l=>7,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>''      ,u=>'%'   ,d=>1,t=>"offset for valve"},
  valveMaxPos     =>{a=> 12  ,s=>0.7,l=>7,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>''      ,u=>'%'   ,d=>0,t=>"valve maximum position"},
  valveErrPos     =>{a=> 13  ,s=>0.7,l=>7,min=>0    ,max=>100   ,c=>''         ,p=>'n',f=>''      ,u=>'%'   ,d=>0,t=>"valve error position"},
                                                                               
  daylightSaveTime=>{a=> 14  ,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"set daylight saving time"             ,lit=>{off=>0,on=>1}},
  regAdaptive     =>{a=> 14.1,s=>0.2,l=>7,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"adaptive regu on or off with default or determined values",lit=>{offDefault=>0,offDeter=>1,on=>2}},
  showInfo        =>{a=> 14.3,s=>0.2,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"show date or time"                    ,lit=>{time=>0,date=>1}},
  winOpnBoost     =>{a=> 14.5,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"boost after window closed"            ,lit=>{off=>0,on=>1}},
  noMinMax4Manu   =>{a=> 14.6,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"min/max is irrelevant for manual mode",lit=>{off=>0,on=>1}},
  showWeekday     =>{a=> 14.7,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"show weekday"                         ,lit=>{off=>0,on=>1}},
                                                                               
  #hyst2point addr is 15 according to XML - not to my device. add "bug" register justin case
  hyst2pointRead  =>{a=> 21.0,s=>0.5,l=>7,min=>0    ,max=>2     ,c=>''         ,p=>'y',f=>'10'    ,u=>'C'   ,d=>1,t=>"hysteresis range",},
  hyst2pointWrite =>{a=> 15.0,s=>1  ,l=>7,min=>0    ,max=>2     ,c=>''         ,p=>'y',f=>'10'    ,u=>'C'   ,d=>1,t=>"hysteresis range",},
  heatCool        =>{a=> 15.7,s=>0.1,l=>7,min=>0    ,max=>1     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"select heating or cooling"            ,lit=>{heating=>0,cooling=>1}},
  weekPrgSel      =>{a=> 16.0,s=>1.0,l=>7,min=>0    ,max=>2     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"select week program"                  ,lit=>{prog1=>0,prog2=>1,prog3=>2}},
                                                                               
  modePrioParty   =>{a=> 18.0,s=>0.3,l=>7,min=>0    ,max=>5     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"allow tempChange for party only by: " ,lit=>{RT_TC_SC_SELF=>0,all=>1,RT_TC_CCU_SELF=>2,CCU=>3,self=>4}},
  modePrioManu    =>{a=> 18.3,s=>0.3,l=>7,min=>0    ,max=>5     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>1,t=>"allow tempChange for manual only by: ",lit=>{RT_TC_SC_SELF=>0,all=>1,RT_TC_CCU_SELF=>2,CCU=>3,self=>4}},
                                                                               
  winOpnMode      =>{a=> 19.5,s=>0.3,l=>7,min=>0    ,max=>4     ,c=>'lit'      ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"enable internal Window open in modes: ",lit=>{off=>0,auto=>1,auto_manu=>2,auto_party=>3,on=>4}},
  winOpnDetFall   =>{a=> 19.0,s=>0.5,l=>7,min=>0.5  ,max=>2.5   ,c=>''         ,p=>'n',f=>'10'    ,u=>'K'   ,d=>0,t=>"detect Window Open if temp falls more then..."},
                                                                               
  reguIntI        =>{a=>202.0,s=>1  ,l=>7,min=>10   ,max=>20    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"regulator I-param internal mode"},
  reguIntP        =>{a=>203.0,s=>1  ,l=>7,min=>25   ,max=>35    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"regulator P-param internal mode"},
  reguIntPstart   =>{a=>204.0,s=>1  ,l=>7,min=>5    ,max=>45    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"regulator P-param internal mode start value"},
  reguExtI        =>{a=>205.0,s=>1  ,l=>7,min=>10   ,max=>20    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"regulator I-param extern mode"},
  reguExtP        =>{a=>206.0,s=>1  ,l=>7,min=>25   ,max=>35    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"regulator P-param extern mode"},
  reguExtPstart   =>{a=>207.0,s=>1  ,l=>7,min=>5    ,max=>45    ,c=>''         ,p=>'n',f=>''      ,u=>''    ,d=>0,t=>"regulator P-param extern mode start value"},
  );

#'THSensor'
#'thermostat'
#'smokeDetector'
#'sensor'
#'KFM100'
#'AlarmControl'
#'singleButton'
#'outputUnit'
#'repeater'
#'blindActuatorSol'
#'powerMeter'

%culHmRegGeneral = (
  pairCentral     =>1
 ,sign            =>1
);
%culHmRegType = (
  swi                 =>{ peerNeedsBurst  =>1,expectAES       =>1}
 ,remote              =>{ peerNeedsBurst  =>1,expectAES       =>1,dblPress        =>1,longPress       =>1}
 ,blindActuator       =>{ intKeyVisib     =>1
                         ,driveUp         =>1,driveDown       =>1,driveTurn       =>1,refRunCounter   =>1
                         ,confBtnTime     =>1,localResDis     =>1
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1
                         ,MaxTimeF        =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffLevel        =>1,OnLevel         =>1
                         ,ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1,DriveMode       =>1
                         ,BlJtOn          =>1,BlJtOff         =>1,BlJtDlyOn       =>1,BlJtDlyOff      =>1
                         ,BlJtRampOn      =>1,BlJtRampOff     =>1,BlJtRefOn       =>1,BlJtRefOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1,CtRefOn         =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1,CtRefOff        =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,dimmer              =>{ intKeyVisib     =>1
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1
                         ,ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1
                         ,DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,switch              =>{ intKeyVisib     =>1,
                         ,OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
                         ,ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,winMatic            =>{ intKeyVisib     =>1,signal          =>1,signalTone      =>1,keypressSignal  =>1}
 ,keyMatic            =>{ signal          =>1,signalTone      =>1,keypressSignal  =>1
                         ,holdTime        =>1,holdPWM         =>1,setupDir        =>1,setupPosition   =>1
                         ,angelOpen       =>1,angelMax        =>1,angelLocked     =>1
                         ,ledFlashUnlocked=>1,ledFlashLocked  =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtOff           =>1
                         ,ActionType      =>1
                         ,KeyJtOn         =>1,KeyJtOff        =>1
                         ,OnTime          =>1
                        }
 ,motionDetector      =>{ evtFltrPeriod   =>1,evtFltrNum      =>1,minInterval     =>1
                         ,captInInterval  =>1,brightFilter    =>1,ledOnTime       =>1
                         ,peerNeedsBurst  =>1
                        }
###motionAndBtn#########################
 ,threeStateSensor    =>{ cyclicInfoMsg   =>1,                    transmDevTryMax =>1
                         ,                                        transmitTryMax  =>1
                         ,peerNeedsBurst  =>1,expectAES       =>1
                         }
 ,sensRain            =>{ transmDevTryMax =>1,localResDis     =>1}
 ,tipTronic           =>{ cyclicInfoMsg   =>1,cyclicInfoMsgDis=>1,localResDis     =>1,RS485IdleTime   =>1}
 ,senBright           =>{ cyclicInfoMsgDis=>1,localResDis     =>1,transmDevTryMax =>1}
 ,powerMeter          =>{ intKeyVisib     =>1
                         ,confBtnTime     =>1,localResDis     =>1
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1}
 ,outputUnit          =>{ intKeyVisib     =>1}
 ,powerSensor         =>{ transmitTryMax  =>1,transmDevTryMax =>1
                         ,mtrType         =>1,mtrConstIr      =>1,mtrConstGas     =>1,mtrConstLed     =>1  
                         ,mtrSensIr       =>1  
                         ,baudrate        =>1,serialFormat    =>1,powerMode       =>1
                         ,protocolMode    =>1,samplPerCycl    =>1
                         }

 ,siren               =>{ intKeyVisib     =>1
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1
                         ,alarmTimeMax    =>1,cyclicInfoMsg   =>1,sabotageMsg     =>1,signalTone      =>1
                         ,lowBatLimitRT   =>1,localResDis     =>1,lowBatSignal    =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OnTimeMode      =>1,OffTimeMode     =>1
                         ,ActionType      =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1                         
                         ,CtOn            =>1,CtDlyOn         =>1
                         ,CtOff           =>1,CtDlyOff        =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                         }
 ,rgb                 =>{ intKeyVisib     =>1,localResDis     =>1}
);
#clones - - - - - - - - - - - - - - -
$culHmRegType{pushButton}     = $culHmRegType{remote};

%culHmRegModel = (
  "HM-RC-12"          =>{ backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1}
 ,"HM-RC-19"          =>{ backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1,backAtCharge    =>1,language =>1}
 ,"HM-RC-4-2"         =>{ localResDis     =>1}

 ,"HM-LC-Dim1L-Pl"    =>{ confBtnTime     =>1,loadAppearBehav =>1,loadErrCalib     =>1}
 ,"HM-HM-LC-DW-WM"    =>{ confBtnTime     =>1,
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1
                         ,logicCombination=>1
                         ,speedMultiply   =>1
                         ,ActionTypeDim   =>1,
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OnTimeMode      =>1,OffTimeMode     =>1,OnDlyMode       =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1
                         ,DimJtOn         =>1,DimJtDlyOn      =>1,DimJtRampOff    =>1
                         ,DimJtOff        =>1,DimJtDlyOff     =>1,DimJtRampOn     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                        }

 ,"HM-LC-Dim1L-CV-2"  =>{ confBtnTime     =>1,loadAppearBehav =>1,loadErrCalib     =>1
                         ,logicCombination=>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"HM-LC-Dim1PWM-CV"  =>{ confBtnTime     =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,characteristic  =>1,localResDis     =>1
                         ,logicCombination=>1,speedMultiply   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"HM-LC-Dim1T-DR"    =>{ confBtnTime     =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,fuseDelay       =>1,localResDis     =>1,logicCombination=>1
                        }
 ,"HM-LC-DIM1T-PL"    =>{ confBtnTime     =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,fuseDelay       =>1,localResDis     =>1
                         ,logicCombination=>1
                        }
 ,"HM-LC-Dim1TPBU-FM" =>{                     ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,fuseDelay       =>1,localResDis     =>1
                         ,logicCombination=>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"OLIGO-smart-iq-HM" =>{ confBtnTime     =>1,
                         ,characteristic  =>1,localResDis     =>1
                         ,logicCombination=>1,speedMultiply   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"HM-CC-VD"          =>{ valveOffset     =>1,valveErrorPos   =>1}
 ,"HM-CC-TC"          =>{ burstRx         =>1,backlOnTime     =>1,backlOnMode     =>1,btnLock         =>1}
 ,"HM-CC-RT-DN"       =>{ btnLock         =>1,localResDis     =>1,globalBtnLock   =>1,modusBtnLock    =>1
                         ,cyclicInfoMsg   =>1,cyclicInfoMsgDis=>1
                         ,burstRx         =>1,lowBatLimitRT   =>1,backOnTime      =>1
                        }
 ,"HM-MOD-Em-8"       =>{ lowBatLimitBA2  =>1,transmDevTryMax =>1,localResDis     =>1  
                         ,ledMode         =>1
                         ,transmitTryMax  =>1,eventFilterTime =>1
                         ,msgScPosA       =>1,msgScPosA       =>1
                         ,triggerMode     =>1
                         }
 ,"HM-MOD-EM-8Bit"    =>{ lowBatLimitBA2  =>1,transmDevTryMax =>1,localResDis     =>1  
                         ,ledMode         =>1
                         ,transmitTryMax  =>1,eventFilterTime =>1
                         }

 ,"HM-PB-4DIS-WM"     =>{ peerNeedsBurst  =>1,expectAES       =>1,language        =>1,stbyTime        =>1}
 ,"HM-Dis-WM55"       =>{ intKeyVisib     =>1,stbyTime        =>1,language        =>1,localResDis     =>1}
 ,"HM-Dis-EP-WM55"    =>{ intKeyVisib     =>1,transmDevTryMax =>1
                         ,powerSupply     =>1,localResDis     =>1,wakeupBehavior  =>1
                         ,wakeupBehavMsg  =>1,wakeupBehavMsg_R=>1,statMsgTxtAlign =>1
                         ,displayInvert   =>1}
 
 ,"HM-WDS100-C6-O"    =>{ burstRx         =>1,sunThresh       =>1,stormUpThresh   =>1,stormLowThresh  =>1}
 ,"HM-WDS100-C6-O-2"  =>{ burstRx         =>1,sunThresh       =>1,stormUpThresh   =>1,stormLowThresh  =>1
                         ,windSpeedRsltSrc=>1,peerNeedsBurst  =>1,localResDis     =>1,cyclicInfoMsgDis=>1}
 ,"HM-OU-LED16"       =>{ brightness      =>1,energyOpt       =>1,localResDis     =>1}
 ,"HM-OU-CFM-PL"      =>{ localResetDis   =>1
                         ,OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
                         ,OnTimeMode      =>1,OffTimeMode     =>1,
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
                         ,ActionType      =>1,ActNum          =>1,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,"HM-OU-CF-PL"       =>{ ActTypeOuCf     =>1,ActNum          =>1}
 ,"HM-OU-CM-PCB"      =>{ localResetDis   =>1,
                         ,OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
                         ,OnTimeMode      =>1,OffTimeMode     =>1,
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
                         ,ActionType      =>1
                         ,ActTypeMp3      =>1,ActNum          =>1,Intense         =>1,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,"HM-SEC-MDIR"       =>{                     sabotageMsg     =>1}
 ,"HM-CC-SCD"         =>{ peerNeedsBurst  =>1,expectAES       =>1
                         ,                                        transmitTryMax  =>1,evtFltrTime     =>1
                         ,msgScdPosA      =>1,msgScdPosB      =>1,msgScdPosC      =>1,msgScdPosD      =>1}
 ,"HM-SEC-RHS"        =>{ msgRhsPosA      =>1,msgRhsPosB      =>1,msgRhsPosC      =>1
                         ,                    ledOnTime       =>1,eventDlyTime    =>1}
 ,"HM-SEC-SC"         =>{                     sabotageMsg     =>1
                         ,msgScPosA       =>1,msgScPosB       =>1
                         ,                    ledOnTime       =>1,eventDlyTime    =>1}
 ,"HM-SEC-SCo"        =>{                     sabotageMsg     =>1,localResDis     =>1,
                         ,msgScPosA       =>1,msgScPosB       =>1,eventDlyTime    =>1}
 ,"HM-SCI-3-FM"       =>{ msgScPosA       =>1,msgScPosB       =>1
                         ,                                        eventDlyTime    =>1}
 ,"HM-SEC-TIS"        =>{                     sabotageMsg     =>1
                         ,msgScPosA       =>1,msgScPosB       =>1
                         ,                    ledOnTime       =>1,eventFilterTime =>1}
 ,"HM-SEC-WDS"        =>{ msgWdsPosA      =>1,msgWdsPosB      =>1,msgWdsPosC      =>1
                         ,                                        eventFilterTimeB=>1}
 ,"HM-SEC-SFA-SM"     =>{ cyclicInfoMsg   =>1,sabotageMsg     =>1,transmDevTryMax =>1
                         ,lowBatLimit     =>1,batDefectLimit  =>1
                         ,                                        transmitTryMax  =>1}
 ,"HM-Dis-TD-T"       =>{ lowBatLimitFS   =>1,ledMode         =>1}
 ,"HM-RC-Dis-H-x-EU"  =>{ localResetDis   =>1,stbyTime2       =>1,language        =>1
                         ,wakeupDefChan   =>1,wakeupBehavior  =>1}

 ,"HM-LC-Sw1-PL"      =>{ confBtnTime     =>1,localResDis     =>1
                         ,transmitTryMax  =>1,powerUpAction   =>1,statusInfoMinDly=>1,statusInfoRandom=>1
                        }
 ,"HM-LC-Sw1PBU-FM"   =>{                     localResDis     =>1
                         ,transmitTryMax  =>1,powerUpAction   =>1,statusInfoMinDly=>1,statusInfoRandom=>1
                        }
 ,"HM-LC-SW1-BA-PCB"  =>{ lowBatLimitBA   =>1,ledMode         =>1}
 ,"HM-LC-SW4-BA-PCB"  =>{ lowBatLimitBA   =>1,ledMode         =>1,localResDis     =>1}
 ,"HM-Sen-DB-PCB"     =>{                     ledMode         =>1}
 ,"HM-MOD-Re-8"       =>{ lowBatLimitBA3  =>1,ledMode         =>1}
 ,"HM-Sys-sRP-Pl"     =>{ compMode        =>1}
 ,"KFM-Display"       =>{ CtDlyOn         =>1,CtDlyOff        =>1
                         ,CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,ActionType      =>1,OffTimeMode     =>1,OnTimeMode      =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1,DimJtDlyOff     =>1
                         ,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,"HM-Sen-Wa-Od"      =>{ cyclicInfoMsgDis=>1,                    transmDevTryMax =>1,localResDis     =>1
                         ,                    ledOnTime       =>1,transmitTryMax  =>1
                         ,waterUppThr     =>1,waterlowThr     =>1,caseDesign      =>1,caseHigh        =>1
                         ,fillLevel       =>1,caseWidth       =>1,caseLength      =>1,meaLength       =>1
                         ,useCustom       =>1,
                         ,fillLvlUpThr    =>1,fillLvlLoThr    =>1
                         ,expectAES       =>1,peerNeedsBurst  =>1
                        }
 ,"HM-WDS10-TH-O"     =>{ burstRx         =>1}
 ,"HM-WDS30-OT2-SM"   =>{ burstRx         =>1,cyclicInfoMsgDis=>1,localResDis     =>1,paramSel        =>1}
 ,"HM-TC-IT-WM-W-EU"  =>{ burstRx         =>1,cyclicInfoMsgDis=>1,localResDis     =>1,cyclicInfoMsg   =>1
                         ,btnLock         =>1,globalBtnLock   =>1,modusBtnLock    =>1,lowBatLimitRT   =>1
                        }
 ,"HM-SEN-EP"         =>{ seqPulse1       =>1,seqPulse2       =>1,seqPulse3       =>1,seqPulse4       =>1
                         ,seqPulse5       =>1,seqTolerance    =>1
                         ,peerNeedsBurst  =>1
                        }
 ,"HM-SEC-SD-2"       =>{ devRepeatCntMax =>1}
 ,"HM-LC-AO-SM"       =>{ voltage_0       =>1,voltage_100     =>1,relayDelay      =>1}
 ,"HM-LC-Ja1PBU-FM"   =>{ refRunTimeSlats =>1,posSaveTime     =>1}
);

#clones - - - - - - - - - - - - - - -
$culHmRegModel{"HM-LC-SW1-PL2"}         = 
$culHmRegModel{"HM-LC-SW1-SM"}          = 
$culHmRegModel{"HM-LC-SW2-SM"}          = 
$culHmRegModel{"HM-LC-SW4-SM"}          = 
$culHmRegModel{"HM-LC-SW4-PCB"}         = 
$culHmRegModel{"HM-LC-SW4-WM"}          = 
$culHmRegModel{"HM-LC-SW1-FM"}          = 
$culHmRegModel{"Schueco_263-130"}       = 
$culHmRegModel{"HM-LC-SW2-FM"}          = 
$culHmRegModel{"HM-LC-SW1-PB-FM"}       = 
$culHmRegModel{"HM-LC-SW2-PB-FM"}       = 
$culHmRegModel{"HM-LC-SW4-DR"}          = 
$culHmRegModel{"HM-LC-SW2-DR"}          = 
$culHmRegModel{"ROTO_ZEL-STG-RM-FZS"}   = 
$culHmRegModel{"ROTO_ZEL-STG-RM-FZS-2"} = 
$culHmRegModel{"HM-LC-Sw1-Pl-3"}        = 
$culHmRegModel{"HM-LC-Sw4-SM-2"}        = 
$culHmRegModel{"HM-LC-Sw4-PCB-2"}       = 
$culHmRegModel{"HM-LC-Sw4-WM-2"}        = 
$culHmRegModel{"HM-LC-Sw2-FM-2"}        = 
$culHmRegModel{"HM-LC-Sw4-DR-2"}        = $culHmRegModel{"HM-LC-Sw1-PL"};
$culHmRegModel{"HM-SEC-SC-2"}           = 
$culHmRegModel{"Roto_ZEL-STG-RM-FFK"}   = $culHmRegModel{"HM-SEC-SC"};
$culHmRegModel{"HM-LC-Dim1L-Pl-2"}      = 
$culHmRegModel{"HM-LC-DIM1L-CV"}        = 
$culHmRegModel{"Schueco-263-132"}       = 
$culHmRegModel{"HM-LC-DIM2L-CV"}        = 
$culHmRegModel{"HM-LC-DIM2L-SM"}        = $culHmRegModel{"HM-LC-Dim1L-Pl"};
$culHmRegModel{"HM-LC-Dim1L-Pl-644"}    = 
$culHmRegModel{"HM-LC-Dim1L-CV-644"}    = 
$culHmRegModel{"HM-LC-Dim1L-Pl-3"}      = $culHmRegModel{"HM-LC-Dim1L-CV-2"};

$culHmRegModel{"HM-LC-Dim1T-FM-LF"}     = 
$culHmRegModel{"Schueco-263-134"}       = $culHmRegModel{"HM-LC-DIM1T-PL"};

$culHmRegModel{"ASH550I"}               = 
$culHmRegModel{"ASH550"}                = 
$culHmRegModel{"Schueco_263-158"}       = 
$culHmRegModel{"HM-WDS20-TH-O"}         = 
$culHmRegModel{"HM-WDS40-TH-I"}         = 
$culHmRegModel{"Schueco_263-157"}       = 
$culHmRegModel{"IS-WDS-TH-OD-S-R3"}     = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"HM-PB-4DIS-WM-2"}       =
$culHmRegModel{"ROTO_ZEL-STG-RM-DWT-10"}= $culHmRegModel{"HM-PB-4DIS-WM"};
$culHmRegModel{"HM-RC-Sec4-2"}          = 
$culHmRegModel{"HM-RC-Key4-2"}          = $culHmRegModel{"HM-RC-4-2"};

$culHmRegModel{"Schueco_263-131"}       =                                   #rf_s_1conf_644
$culHmRegModel{"HM-LC-Bl1PBU-FM"}       = $culHmRegModel{"HM-LC-Sw1PBU-FM"};

$culHmRegModel{"HM-SEC-WDS-2"}          = $culHmRegModel{"HM-SEC-WDS"};                                        
                                        
$culHmRegModel{"ROTO_ZEL-STG-RM-FWT"}   = $culHmRegModel{"HM-CC-TC"};
$culHmRegModel{"ROTO_ZEL-STG-RM-FSA"}   = $culHmRegModel{"HM-CC-VD"};
                                        
$culHmRegModel{"HM-OU-CFM-TW"}          = $culHmRegModel{"HM-OU-CFM-PL"};


%culHmRegChan = (# if channelspecific then enter them here
  "HM-CC-TC02"        =>{ displayMode     =>1,displayTemp     =>1,displayTempUnit =>1
                         ,controlMode     =>1,decalcDay       =>1
                         ,"day-temp"      =>1,"night-temp"    =>1,"party-temp"    =>1
                         ,mdTempValve     =>1,partyEndDay     =>1
                         ,partyEndMin     =>1,partyEndHr      =>1
                         ,decalHr         =>1,decalMin        =>1
                         }
 ,"HM-CC-TC03"        =>{ tempWinOpen     =>1 } #window channel
 ,"HM-RC-1912"        =>{ msgShowTime     =>1, beepAtAlarm    =>1, beepAtService  =>1,beepAtInfo  =>1
                         ,backlAtAlarm    =>1, backlAtService =>1, backlAtInfo    =>1
                         }
 ,"HM-RC-1901"        =>{ lcdSymb         =>1, lcdLvlInterp   =>1}
 ,"HM-OU-CFM-PL01"    =>{ ActTypeLed      =>1}
 ,"HM-OU-CFM-PL02"    =>{ ActTypeMp3      =>1,Intense         =>1}
 ,"HM-SEC-WIN01"      =>{ setupDir        =>1,pullForce       =>1,pushForce       =>1,tiltMax         =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1
                         ,WinJtOn         =>1,WinJtOff        =>1,WinJtRampOn     =>1,WinJtRampOff    =>1
                         ,OnTime          =>1,OffTime         =>1,OffLevelKm      =>1,OnLevelKm       =>1
                         ,RampOnSp        =>1,RampOffSp       =>1
                         }
 ,"WDF-solar01"       =>{ WinJtOn         =>1,WinJtOff        =>1,WinJtRampOn     =>1,WinJtRampOff    =>1
                         ,OffLevel        =>1,OnLevel         =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1
                         ,RampOnSp        =>1,RampOffSp       =>1
                         ,OnTime          =>1,OffTime         =>1
                         }
 ,"Schueco_263-xxx01" =>{ statusInfoMinDly=>1,statusInfoRandom=>1,
                         ,#no long here!!!
                         ,shCtValLo       =>1,shCtValHi       =>1
                         ,shCtOn          =>1,shCtDlyOn       =>1,shCtOff         =>1,shCtDlyOff      =>1
                         ,shOnTime        =>1,shOffTime       =>1,shOnDly         =>1,shOffDly        =>1
                         ,shActionTypeDim =>1,shOnTimeMode    =>1,shOffTimeMode   =>1
                         ,shDimJtOn       =>1,shDimJtOff      =>1,shDimJtDlyOn    =>1
                         ,shDimJtDlyOff   =>1,shDimJtRampOn   =>1,shDimJtRampOff  =>1
                         ,shOnLevel       =>1
                         }
 ,"Schueco_263-xxx02" =>{ transmitTryMax  =>1,eventDlyTime    =>1}
 ,"Schueco_263-xxx03" =>{ ttJtOn          =>1,ttJtOff         =>1}
 ,"HM-Sen-RD-O01"     =>{ eventFilterTimeB=>1,transmitTryMax  =>1,peerNeedsBurst  =>1,expectAES       =>1
                         ,cndTxThrhHi     =>1,cndTxThrhLo     =>1,highHoldTime    =>1,evntRelFltTime  =>1
                         }
 ,"HM-CC-RT-DN03"     =>{ shCtValLo       =>1
                         ,winOpnTemp      =>1}
 ,"HM-CC-RT-DN04"     =>{ btnNoBckLight   =>1
                         ,dayTemp         =>1,nightTemp       =>1,tempMin         =>1,tempMax         =>1
                         ,tempOffset      =>1
                         ,decalcWeekday   =>1,decalcTime      =>1
                         ,boostPos        =>1,boostPeriod     =>1
                         ,daylightSaveTime=>1,regAdaptive     =>1
                         ,showInfo        =>1,noMinMax4Manu   =>1,showWeekday     =>1
                         ,valveOffsetRt   =>1,valveMaxPos     =>1,valveErrPos     =>1
                         ,modePrioManu    =>1,modePrioParty   =>1
                         ,reguIntI        =>1,reguIntP        =>1,reguIntPstart   =>1
                         ,reguExtI        =>1,reguExtP        =>1,reguExtPstart   =>1
                         ,winOpnTempI     =>1,winOpnPeriod    =>1,winOpnBoost     =>1,winOpnMode      =>1
                         ,winOpnDetFall   =>1
                         }
 ,"HM-CC-RT-DN06"     =>{                     CtrlRc          =>1,TempRC          =>1}
 ,"HM-TC-IT-WM-W-EU02"=>{ dayTemp         =>1,nightTemp       =>1,tempMin         =>1,tempMax         =>1,tempOffset      =>1
                                             ,heatCool        =>1,boostPeriod     =>1,winOpnBoost     =>1
                         ,showWeekday     =>1,showInfo        =>1,showSetTemp     =>1,showHumidity    =>1
                         ,noMinMax4Manu   =>1,daylightSaveTime=>1,sendWeatherData =>1
                         ,modePrioParty   =>1,modePrioManu    =>1,weekPrgSel      =>1
                         }
 ,"HM-TC-IT-WM-W-EU07"=>{ hyst2pointWrite =>1,hyst2pointRead  =>1}
 ,"HM-ES-PMSw1-Pl01"  =>{ OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
                         ,ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1,powerUpAction   =>1
                          }
 ,"HM-Sec-Sir-WM01"   =>{ soundId         =>1}
 ,"HM-Sec-Sir-WM04"   =>{ OnLevel         =>1
                         ,acusticMultiDly =>1,acusticArmSens  =>1,acusticArmDly   =>1,acusticExtArm   =>1,acusticExtDly   =>1,acusticDisArm   =>1
                         ,opticMultiDly   =>1,opticArmSens    =>1,opticArmDly     =>1,opticExtArm     =>1,opticExtDly     =>1,opticDisArm     =>1
                         ,OnLevelArm      =>1
                         }
 ,"HM-ES-PMSw1-Pl02"  =>{ averaging       =>1
                         ,txMinDly        =>1,txThrPwr        =>1,txThrCur        =>1,txThrVlt        =>1,txThrFrq        =>1
                          }
 ,"HM-ES-PMSw1-Pl03"  =>{ txThrLoPwr      =>1,txThrHiPwr      =>1,peerNeedsBurst  =>1,expectAES       =>1
                         ,ledOnTime       =>1,transmitTryMax  =>1,
                         ,cndTxFalling    =>1,cndTxRising     =>1,
                         ,cndTxCycBelow   =>1,cndTxCycAbove   =>1,cndTxDecAbove   =>1,cndTxDecBelow   =>1,
                          }
 ,"HM-ES-PMSw1-Pl04"  =>{ txThrLoCur      =>1,txThrHiCur      =>1,peerNeedsBurst  =>1,expectAES       =>1
                         ,ledOnTime       =>1,transmitTryMax  =>1,
                         ,cndTxFalling    =>1,cndTxRising     =>1,
                         ,cndTxCycBelow   =>1,cndTxCycAbove   =>1,cndTxDecAbove   =>1,cndTxDecBelow   =>1,
                          }
 ,"HM-ES-PMSw1-Pl05"  =>{ txThrLoVlt      =>1,txThrHiVlt      =>1,peerNeedsBurst  =>1,expectAES       =>1
                         ,ledOnTime       =>1,transmitTryMax  =>1,
                         ,cndTxFalling    =>1,cndTxRising     =>1,
                         ,cndTxCycBelow   =>1,cndTxCycAbove   =>1,cndTxDecAbove   =>1,cndTxDecBelow   =>1,
                          }
 ,"HM-ES-PMSw1-Pl06"  =>{ txThrLoFrq      =>1,txThrHiFrq      =>1,peerNeedsBurst  =>1,expectAES       =>1
                         ,ledOnTime       =>1,transmitTryMax  =>1,
                         ,cndTxFalling    =>1,cndTxRising     =>1,
                         ,cndTxCycBelow   =>1,cndTxCycAbove   =>1,cndTxDecAbove   =>1,cndTxDecBelow   =>1,
                          }
 ,"HM-Sen-MDIR-WM5500"=>{ intKeyVisib     =>1,cyclicInfoMsg   =>1,localResDis     =>1,transmDevTryMax =>1}
 ,"HM-Sen-MDIR-WM5501"=>{ peerNeedsBurst  =>1,expectAES       =>1,dblPress        =>1,longPress       =>1
                         ,ledOnTime       =>1,transmitTryMax  =>1,localResDis     =>1
                        }

 ,"HM-LC-RGBW-WM01"   =>{ OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1
                         ,ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,DimJtOn         =>1,DimJtDlyOn      =>1,DimJtRampOff    =>1
                         ,DimJtOff        =>1,DimJtDlyOff     =>1,DimJtRampOn     =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                        }
 ,"HM-LC-RGBW-WM02"   =>{ ActHsvCol       =>1,waRed           =>1,waGreen         =>1,waBlue          =>1}
 ,"HM-LC-RGBW-WM03"   =>{ ActColPrgm      =>1,ActMinBoarder   =>1,ActMaxBoarder   =>1,colChangeSpeed  =>1}

 ,"HM-HM-LC-DW-WM01"  =>{ characteristic  =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1}
 ,"HM-HM-LC-DW-WM02"  =>{ characteristic  =>1,charactLvlLimit =>1,charactColAssign=>1,charactBase     =>1}
 
 ,"HM-Sen-LI-O00"     =>{ txMinDly        =>1,txThresPercent  =>1}
 ,"SensoTimer-ST-601" =>{ humDesVal       =>1,watDuration     =>1,eco_days        =>1,
                         ,wat1_hour       =>1,wat1_min        =>1, 
                         ,wat2_hour       =>1,wat2_min        =>1, 
                         }
 ,"HM-Dis-EP-WM5501"  =>{ transmitTryMax  =>1,peerNeedsBurst  =>1,expectAES       =>1}
 ,"HM-Dis-EP-WM5503"  =>{ transmitTryMax  =>1}
 ,"HM-MOD-EM-8Bit03"  =>{ dataTransCond   =>1,stabFltTime     =>1
                         ,dInProp0        =>1,dInProp1        =>1,dInProp2        =>1,dInProp3        =>1
                         ,dInProp4        =>1,dInProp5        =>1,dInProp6        =>1,dInProp7        =>1
                        }
 ,"HM-DW01"           =>{ intKeyVisib     =>1
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1
                         ,logicCombination=>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1
                         ,ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1
                         ,DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                         ,confBtnTime     =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,characteristic  =>1,localResDis     =>1
                         ,speedMultiply   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"HM-DW02"           =>{ characteristic  =>1,charactLvlLimit =>1,charactColAssign=>1,charactBase     =>1
                         ,transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1
                         ,logicCombination=>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1
                         ,ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1
                         ,DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                         ,confBtnTime     =>1,localResDis     =>1
                         ,speedMultiply   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"HM-DW03"           =>{ transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1
                         ,logicCombination=>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1
                         ,ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1
                         ,DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                         ,confBtnTime     =>1,localResDis     =>1
                         ,speedMultiply   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 ,"HM-DW04"           =>{ transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1
                         ,logicCombination=>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1
                         ,ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1
                         ,OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1
                         ,RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1
                         ,DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1
                         ,DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1
                         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1
                         ,OffDlyStep      =>1,OffDlyNewTime   =>1,OffDlyOldTime   =>1
                         ,lgMultiExec     =>1,shMultiExec     =>1
                         ,confBtnTime     =>1,localResDis     =>1
                         ,logicCombination=>1,speedMultiply   =>1
                         ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
                         ,DimElsActionType=>1
                         ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
                         ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1
                        }
 );
 

#clones - - - - - - - - - - - - - - -

$culHmRegChan{"HM-DW05"}                = $culHmRegChan{"HM-DW03"};
$culHmRegChan{"HM-DW06"}                = $culHmRegChan{"HM-DW04"};

$culHmRegChan{"HM-Dis-EP-WM5502"}       = $culHmRegChan{"HM-Dis-EP-WM5501"};
$culHmRegChan{"HM-Sec-Sir-WM02"}        = 
$culHmRegChan{"HM-Sec-Sir-WM03"}        = $culHmRegChan{"HM-Sec-Sir-WM01"};
                                        
$culHmRegChan{"SensoTimer-ST-602"}      = $culHmRegChan{"SensoTimer-ST-601"};
$culHmRegChan{"HM-Sen-MDIR-WM5502"}     = $culHmRegChan{"HM-Sen-MDIR-WM5501"};
$culHmRegChan{"HM-Sen-MDIR-WM5503"}     = $culHmRegType{motionDetector};
                                        
$culHmRegChan{"WDF-solar02"}            = $culHmRegType{"dimmer"};      # type hash
                                        
$culHmRegChan{"HM-TC-IT-WM-W-EU03"}     = $culHmRegChan{"HM-CC-RT-DN03"};
$culHmRegChan{"HM-TC-IT-WM-W-EU06"}     = $culHmRegChan{"HM-CC-RT-DN06"};
                                        
$culHmRegChan{"ROTO_ZEL-STG-RM-FWT02"}  = $culHmRegChan{"HM-CC-TC02"};
$culHmRegChan{"ROTO_ZEL-STG-RM-FWT03"}  = $culHmRegChan{"HM-CC-TC03"};
$culHmRegChan{"HM-OU-CFM-TW01"}         = $culHmRegChan{"HM-OU-CFM-PL01"};
$culHmRegChan{"HM-OU-CFM-TW02"}         = $culHmRegChan{"HM-OU-CFM-PL02"};


##############################---templates---##################################
#en-block programming of funktions
%culHmTpl = (
   autoOff           => {p=>"time"             ,t=>"staircase - auto off after -time-, extend time with each trigger"
                    ,reg=>{ OnTime          =>"p0"
                           ,OffTime         =>"unused"
                           ,SwJtOn          =>"on"
                           ,SwJtOff         =>"dlyOn"
                           ,SwJtDlyOn       =>"no"
                           ,SwJtDlyOff      =>"dlyOn"
                           ,ActionType      =>"jmpToTarget"
                     }}
  ,SwToggle          => {p=>""                 ,t=>"Switch: toggle on trigger"
                    ,reg=>{ OnTime          =>"unused"
                           ,OffTime         =>"unused"
                           ,SwJtOn          =>"dlyOff"
                           ,SwJtOff         =>"dlyOn"
                           ,SwJtDlyOn       =>"on"
                           ,SwJtDlyOff      =>"off"
                           ,ActionType      =>"jmpToTarget"
                     }}
  ,SwOn              => {p=>""                 ,t=>"Switch: on if trigger"
                    ,reg=>{ OnTime          =>"unused"
                           ,OffTime         =>"unused"
                           ,SwJtOn          =>"no"
                           ,SwJtOff         =>"dlyOn"
                           ,SwJtDlyOn       =>"on"
                           ,SwJtDlyOff      =>"dlyOn"
                           ,ActionType      =>"jmpToTarget"
                     }}
  ,SwOff             => {p=>""                 ,t=>"Switch: off if trigger"
                    ,reg=>{ OnTime          =>"unused"
                           ,OffTime         =>"unused"
                           ,SwJtOn          =>"dlyOff"
                           ,SwJtOff         =>"no"
                           ,SwJtDlyOn       =>"dlyOff"
                           ,SwJtDlyOff      =>"off"
                           ,ActionType      =>"jmpToTarget"
                     }}
  ,DimOn             => {p=>""                 ,t=>"Dimmer: on if trigger"
                    ,reg=>{ OnTime          =>"unused"
                           ,OffTime         =>"unused"
                           ,DimJtOn         =>"no"
                           ,DimJtOff        =>"dlyOn"
                           ,DimJtDlyOn      =>"on"
                           ,DimJtDlyOff     =>"dlyOn"
                           ,DimJtRampOff    =>"dlyOn"
                           ,DimJtRampOn     =>"dlyOn"
                           ,ActionTypeDim   =>"jmpToTarget"
                     }}
  ,DimOff            => {p=>""                 ,t=>"Dimmer: off if trigger"
                    ,reg=>{ OnTime          =>"unused"
                           ,OffTime         =>"unused"
                           ,DimJtOn         =>"dlyOff"
                           ,DimJtOff        =>"no"
                           ,DimJtDlyOn      =>"dlyOff"
                           ,DimJtDlyOff     =>"off"
                           ,DimJtRampOff    =>"dlyOff"
                           ,DimJtRampOn     =>"dlyOff"
                           ,ActionTypeDim   =>"jmpToTarget"
                     }}
  ,motionOnDim       => {p=>"ontime brightness",t=>"Dimmer: on for time if MDIR-brightness below level"
                    ,reg=>{ CtDlyOn         =>"ltLo"
                           ,CtDlyOff        =>"ltLo"
                           ,CtOn            =>"ltLo"
                           ,CtOff           =>"ltLo"
                           ,CtValLo         =>"p1"
                           ,CtRampOn        =>"ltLo"
                           ,CtRampOff       =>"ltLo"
                           ,OffTime         =>"unused"
                           ,OnTime          =>"p0"

                           ,ActionTypeDim   =>"jmpToTarget"
                           ,DimJtOn         =>"on"
                           ,DimJtOff        =>"dlyOn"
                           ,DimJtDlyOn      =>"rampOn"
                           ,DimJtDlyOff     =>"dlyOn"
                           ,DimJtRampOn     =>"on"
                           ,DimJtRampOff    =>"dlyOn"
                     }}
  ,motionOnSw        => {p=>"ontime brightness",t=>"Switch: on for time if MDIR-brightness below level"
                    ,reg=>{ CtDlyOn         =>"ltLo"
                           ,CtDlyOff        =>"ltLo"
                           ,CtOn            =>"ltLo"
                           ,CtOff           =>"ltLo"
                           ,CtValLo         =>"p1"
                           ,OffTime         =>"unused"
                           ,OnTime          =>"p0"

                           ,ActionType      =>"jmpToTarget"
                           ,SwJtOn          =>"on"
                           ,SwJtOff         =>"dlyOn"
                           ,SwJtDlyOn       =>"on"
                           ,SwJtDlyOff      =>"dlyOn"
                    }}
  ,SwCondAbove       => {p=>"condition"        ,t=>"Switch: execute only if condition level is above limit"
                    ,reg=>{ CtDlyOn         =>"geLo"
                           ,CtDlyOff        =>"geLo"
                           ,CtOn            =>"geLo"
                           ,CtOff           =>"geLo"
                           ,CtValLo         =>"p0"
                     }}
  ,SwCondBelow       => {p=>"condition"        ,t=>"Switch: execute only if condition level is below limit"
                    ,reg=>{ CtDlyOn         =>"ltLo"
                           ,CtDlyOff        =>"ltLo"
                           ,CtOn            =>"ltLo"
                           ,CtOff           =>"ltLo"
                           ,CtValLo         =>"p0"
                     }}
  ,SwOnCond          => {p=>"level cond"       ,t=>"switch: execute only if condition [geLo|ltLo] level is below limit"
                    ,reg=>{ CtDlyOn         =>"p1"
                           ,CtDlyOff        =>"p1"
                           ,CtOn            =>"p1"
                           ,CtOff           =>"p1"
                           ,CtValLo         =>"p0"
                     }}
  ,BlStopDnLg        => {p=>""                 ,t=>"Blind: stop drive on any key - for long drive down"
                    ,reg=>{ ActionType      =>"jmpToTarget"
                           ,BlJtDlyOff      =>"refOff"
                           ,BlJtDlyOn       =>"dlyOff"
                           ,BlJtOff         =>"dlyOff"
                           ,BlJtOn          =>"dlyOff"
                           ,BlJtRampOff     =>"rampOff"
                           ,BlJtRampOn      =>"on"
                           ,BlJtRefOff      =>"rampOff"
                           ,BlJtRefOn       =>"on"
                    }}
  ,BlStopDnSh        => {p=>""                 ,t=>"Blind: stop drive on any key - for short drive down"
                    ,reg=>{ ActionType      =>"jmpToTarget"
                           ,BlJtDlyOff      =>"refOff"
                           ,BlJtDlyOn       =>"dlyOff"
                           ,BlJtOff         =>"dlyOff"
                           ,BlJtOn          =>"dlyOff"
                           ,BlJtRampOff     =>"off"
                           ,BlJtRampOn      =>"on"
                           ,BlJtRefOff      =>"rampOff"
                           ,BlJtRefOn       =>"on"
                    }}
  ,BlStopUpLg        => {p=>""                 ,t=>"Blind: stop drive on any key - for long drive up"
                    ,reg=>{ ActionType       =>"jmpToTarget"
                           ,BlJtDlyOff       =>"dlyOn"
                           ,BlJtDlyOn        =>"refOn"
                           ,BlJtOff          =>"dlyOn"
                           ,BlJtOn           =>"dlyOn"
                           ,BlJtRampOff      =>"off"
                           ,BlJtRampOn       =>"rampOn"
                           ,BlJtRefOff       =>"off"
                           ,BlJtRefOn        =>"rampOn"
                    }}
  ,BlStopUpSh        => {p=>""                 ,t=>"Blind: stop drive on"
                    ,reg=>{ ActionType       =>"jmpToTarget"
                           ,BlJtDlyOff       =>"dlyOn"
                           ,BlJtDlyOn        =>"refOn"
                           ,BlJtOff          =>"dlyOn"
                           ,BlJtOn           =>"dlyOn"
                           ,BlJtRampOff      =>"off"
                           ,BlJtRampOn       =>"on"
                           ,BlJtRefOff       =>"off"
                           ,BlJtRefOn        =>"rampOn"
                    }}                   
  ,wmOpen            => {p=>"speed"            ,t=>"winmatic: open window"     
                    ,reg=>{ WinJtOn          =>"rampOn"
                           ,WinJtOff         =>"rampOn"
                           ,WinJtRampOn      =>"on"
                           ,WinJtRampOff     =>"rampOnFast"
                           ,RampOnSp         =>"p0"
                    }}
  ,wmClose           => {p=>"speed"            ,t=>"winmatic: close window"    
                    ,reg=>{ WinJtOn          =>"rampOff"
                           ,WinJtOff         =>"rampOff"
                           ,WinJtRampOn      =>"on"
                           ,WinJtRampOff     =>"rampOnFast"
                           ,RampOffSp        =>"p0"
                    }}
  ,wmClosed          => {p=>""                 ,t=>"winmatic: lock window"     
                    ,reg=>{ OffLevelKm       =>"0"
                    }}
  ,wmLock            => {p=>""                 ,t=>"winmatic: lock window"     
                    ,reg=>{ OffLevelKm       =>"127.5"
                    }}
);

##############################---get---########################################
#define gets - try use same names as for set
%culHmGlobalGets = (
                    param      => "-param-",
                    reg        => "-addr- ... -list- -peer-",
                    regVal     => "-addr- ... -list- -peer-",
                    regList    => "",
                    cmdList    => "",
                    saveConfig => "-filename- ...",
);
%culHmVrtGets = (
                    param      => "-param-",
                    cmdList    => "",
);
%culHmSubTypeGets = (
                    none4Type  =>{ "test"=>"" }
);
%culHmModelGets = (
                    "CCU-FHEM"     =>{ "listDevice"=>""}
                   ,ActionDetector =>{ "listDevice"=>"[all|alive|unknown|dead|notAlive] ..." 
                                      ,"info"      =>""
                                     }
);

##############################---set---########################################
%culHmGlobalSets       = (# all but virtuals
                       regBulk       => "-list-:-peer- -addr1:data1- -addr2:data2- ..."
                      ,getRegRaw     => "[List0|List1|List2|List3|List4|List5|List6] ... [-PeerChannel-]"
                      ,getConfig     => ""
                      ,regSet        => "[prep|exec] -regName- -value- ... [-peerChannel-]"
                      ,clear         => "[readings|trigger|register|oldRegs|rssi|msgEvents|attack|all]"
                      ,templateDel   => "tmplt"
);
%culHmGlobalSetsVrtDev = (# virtuals and devices without subtype
                       virtual       => "-noButtons-"
                      ,clear         => "[readings|rssi|msgEvents|unknownDev]"
);

%culHmReglSets         = (# entities with regList
                      "0"              =>{  #this is a device
                                            raw           => "data ..."
                                           ,reset         => ""
                                           ,unpair        => ""
                                           ,assignHmKey   => ""
                                           ,deviceRename  => "newName"
                                           ,fwUpdate      =>"-filename- -bootTime- ..."
                                         }
                     ,"1"              =>{  #this is a channel
                                            sign          => "[on|off]"
                                         }
                     ,"3p"             =>{ press          =>"[long|short] -peer- [-repCount(long only)-] [-repDelay-] ..."
                                          ,eventL         =>"-peer- -cond-"
                                          ,eventS         =>"-peer- -cond-"
                                         }
                     ,"4p"             =>{ trgPressS      =>"[-peer-]"
                                          ,trgPressL      =>"[-peer-]"
                                          ,trgEventS      =>"[-peer-] -condition-"
                                          ,trgEventL      =>"[-peer-] -condition-"
                                         }
);

%culHmSubTypeDevSets   = (# device of this subtype
                      switch           =>{ getSerial      => ""
                                          ,pair           => ""
                                          ,getVersion     => ""
                                          ,getDevInfo     => ""
                                         }        
#                     ,winMatic         =>{ statusRequest => ""} not working at least for FW 1.6
                     ,keyMatic         =>{ statusRequest  => ""}
                     ,repeater         =>{ statusRequest  => ""
                                          ,getSerial      => ""
                                         }
);
$culHmSubTypeDevSets{dimmer}            = 
$culHmSubTypeDevSets{blindActuator}     = $culHmSubTypeDevSets{switch};

%culHmGlobalSetsChn    = (# all channels but virtuals
                      peerBulk      => "-peer1,peer2,...- [set|unset]"
);
%culHmSubTypeSets      = (# channels of this subtype
                      switch           =>{ "on-for-timer" =>"-ontime-"
                                          ,"on-till"      =>"-time-"
                                          ,on             =>""
                                          ,off            =>""
                                          ,toggle         =>""
                                          ,inhibit        =>"[on|off]"
                                          ,statusRequest  =>""
                                          ,peerIODev      =>"[IO] -btn- [set|unset]... not for future use"
                                         }
                     ,dimmer           =>{ "on-for-timer" =>"-ontime- [-ramptime-]..."
                                          ,"on-till"      =>"-time- [-ramptime-]..."
                                          ,on             =>""
                                          ,off            =>""
                                          ,old            =>""
                                          ,toggle         =>""
                                          ,pct            =>"[-value-|old] ... [-ontime-] [-ramptime-]"
                                          ,stop           =>""
                                          ,up             =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                          ,down           =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                          ,inhibit        =>"[on|off]"
                                          ,statusRequest  =>""
                                          ,peerIODev      =>"[IO] -btn- [set|unset]... not for future use"
                                         }
                     ,blindActuator    =>{ on             =>""
                                          ,off            =>""
                                          ,toggle         =>""
                                          ,toggleDir      =>""
                                          ,pct            =>"[-value-] ... [-ontime-]"
                                          ,stop           =>""
                                          ,up             =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                          ,down           =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                          ,inhibit        =>"[on|off]"
                                          ,statusRequest  =>""
                                          ,peerIODev      =>"[IO] -btn- [set|unset]... not for future use"
                                         }
                     ,remote           =>{ peerChan       =>"-btnNumber- -actChn- ... [single|dual|reverse] [set|unset] [actor|remote|both]"}
                     ,threeStateSensor =>{ peerChan       =>"-btnNumber- -actChn- ... single [set|unset] [actor|remote|both]"}
                     ,THSensor         =>{ peerChan       =>"0 -actChn- ... single [set|unset] [actor|remote|both]"}
                     ,virtual          =>{ peerChan       =>"-btnNumber- -actChn- ... [single|dual|reverse] [set|unset] [actor|remote|both]"
                                          ,press          =>"[long|short] [noBurst] [-repCount(long only)-] [-repDelay-] ..."
                                          ,postEvent      =>"-condition-"
                                         }
                     ,smokeDetector    =>{ peerChan       =>"-btnNumber- -actChn- ... single [set|unset] actor"}
                     ,keyMatic         =>{ lock           =>""
                                          ,unlock         =>"[-sec-] ..."
                                          ,open           =>"[-sec-] ..."
                                          ,inhibit        =>"[on|off]"
                                          ,statusRequest  =>""
                                         }
                     ,repeater         =>{ setRepeat      =>"[no1..36] -sendName- -recName- [bdcast-yes|no]"
                                          ,inhibit        =>"[on|off]"
                                          ,statusRequest  =>""
                                         }
                     ,KFM100           =>{ statusRequest  =>""}
);
# clones- - - - - - - - - - - - - - - - -
$culHmSubTypeSets{pushButton}           = 
$culHmSubTypeSets{swi}                  = $culHmSubTypeSets{remote};
$culHmSubTypeSets{blindActuatorSol}     = 
$culHmSubTypeSets{tipTronic}            = $culHmSubTypeSets{KFM100};
$culHmSubTypeSets{motionDetector}       = 
$culHmSubTypeSets{motionAndBtn}         = $culHmSubTypeSets{threeStateSensor};

%culHmModelSets = (# channels of this subtype-------------
                      "HM-CC-VD"         =>{ valvePos       =>"[off|0.0..99.0]"}
                     ,"HM-RC-19"         =>{ service        =>"-count-"
                                            ,alarm          => "-count-"
                                            ,display        => "-text- [comma|no] [unit] [off|1|2|3] [off|on|slow|fast] -symbol-"
                                           }
                     ,"HM-PB-4DIS-WM"    =>{ text           =>"-txt1- -txt2-..."
                                              #text         => "-btn- [on|off] -txt1- -txt2-...", old style will not be offered anymore
                                           }
                     ,"HM-OU-LED16"      =>{ led            =>"[off|red|green|orange]"
                                            ,ilum           => "[0-15] [0-127]"
                                            ,statusRequest  =>""
                                           }
                     ,"HM-OU-CFM-PL"     =>{ "on-for-timer" =>"-sec-"
                                            ,"on-till"      =>"-time-"
                                            ,on             =>""
                                            ,off            =>""
                                            ,toggle         =>""
                                            ,inhibit        =>"[on|off]"
                                           }
                     ,"HM-CC-RT-DN"      =>{ inhibit        =>"[on|off]"}
                     ,"HM-TC-IT-WM-W-EU" =>{ inhibit        =>"[on|off]"}
                     ,"HM-SEC-SD"        =>{ statusRequest  =>""}
                     ,"HM-SEC-SD-2"      =>{ statusRequest  =>""}
                     ,"ActionDetector"   =>{ clear          =>"[readings|all]"
                                            ,update         => ""
                                           }
                     ,"HM-LC-Ja1PBU-FM"  =>{ pctSlat        =>"[0-100]|old|noChng"
                                            ,pctLvlSlat     =>"-value-|old|noChng -slatValue-|old|noChng"
                                           }
);

#foreach(keys %HMConfig::culHmRegModel){$culHmModelSets{$_}{burstXmit}="" if(defined $HMConfig::culHmRegModel{$_})};
foreach(keys %HMConfig::culHmModel){$culHmModelSets{$HMConfig::culHmModel{$_}{name}}{burstXmit}="" if($HMConfig::culHmModel{$_}{rxt} =~ m/f/)};
 
# clones- - - - - - - - - - - - - - - - -

$culHmModelSets{"HM-OU-CM-PCB"}          = 
$culHmModelSets{"HM-OU-CF-PL"}           = 
$culHmModelSets{"HM-OU-CFM-TW"}          = $culHmModelSets{"HM-OU-CFM-PL"};
$culHmModelSets{"HM-PB-4DIS-WM-2"}       = 
$culHmModelSets{"HM-Dis-WM55"}           = 
$culHmModelSets{"HM-Dis-EP-WM55"}        = 
$culHmModelSets{"HM-ES-TX-WM"}           = 
$culHmModelSets{"HM-RC-Dis-H-x-EU"}      = 
$culHmModelSets{"ROTO_ZEL-STG-RM-DWT-10"}= $culHmModelSets{"HM-PB-4DIS-WM"};
                                         
#$culHmModelSets{"HM-OU-CFM-PL"}          = $culHmModelSets{"HM-SEC-SD"};# no statusrequest possible
$culHmModelSets{"HM-OU-CM-PCB"}          = $culHmModelSets{"HM-SEC-SD"};
$culHmModelSets{"HM-Sen-Wa-Od"}          = $culHmModelSets{"HM-SEC-SD"};
$culHmModelSets{"HM-HM-LC-DW-WM"}        = $culHmSubTypeSets{dimmer};   ##### reference subtype sets

%culHmChanSets = (
                      "HM-CC-TC00"           =>{ "desired-temp" =>"[on|off|6.0..30.0]"
                                                ,statusRequest  =>""
                                                ,sysTime        =>""
                                                ,getSerial      => ""
                                               }
                     ,"HM-CC-TC02"           =>{ peerChan       =>" 0 -actChn- ... single [set|unset] [actor|remote|both]"
                                                ,"desired-temp" =>"[on|off|6.0..30.0]"
                                                ,tempListSat    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListSun    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListMon    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListTue    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListThu    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListWed    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListFri    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListTmpl   =>"[verify|restore] [[-file-:]templateName] ..."
                                                ,tempTmplSet    =>"[[-file-:]templateName] ..."
                                                ,partyMode      =>"[prep|exec] HH:MM durationDays ..."
                                                ,displayMode    =>"[temp-only|temp-hum]"
                                                ,displayTemp    =>"[actual|setpoint]"
                                                ,displayTempUnit=>"[celsius|fahrenheit]"
                                                ,controlMode    =>"[auto|manual|central|party]"
                                                ,statusRequest  =>""
                                                ,sysTime        =>""
                                               }
                     ,"HM-OU-CFM-PL01"       =>{ led            =>"[redL|greenL|orangeL|redS|greenS|orangeS|pause][,-color2-...] [-repeat-]"}
                     ,"HM-OU-CFM-PL02"       =>{ playTone       =>"[replay|-MP3No-[,-MP3No-...]] [-repeat-]"
                                                ,pct            =>"[-value- ... [-ontime-]"}
                     ,"HM-SEC-WIN01"         =>{ stop           =>"",
                                                ,level          =>"-level- -relockDly- -speed-..."
                                                ,keydef         =>"-btn- -txt1- -txt2-"
                                                ,inhibit        =>"[on|off]"
                                                ,peerIODev      =>"[IO] -btn- [set|unset]... not for future use"
                                               }
                     ,"HM-Sen-RD-O02"        =>{ "on-for-timer" =>"-sec-"
                                                ,"on-till"      =>"-time-"
                                                ,on             =>""
                                                ,off            =>""
                                                ,toggle         =>""
                                               }
                     ,"HM-CC-RT-DN00"        =>{ sysTime        =>"" }
                     ,"HM-CC-RT-DN04"        =>{ controlMode    =>"[auto|manual|boost|day|night]"
                                                ,controlManu    =>"[on|off|5.0..30.0]"
                                                ,controlParty   =>"-temp- -startDate- -startTime- -endDate- -endTime-"
                                                ,tempListSat    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListSun    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListMon    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListTue    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListThu    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListWed    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListFri    =>"[prep|exec] HH:MM temp ..."
                                                ,tempListTmpl   =>"[verify|restore] [[-file-:]templateName] ..."
                                                ,tempTmplSet    =>"[[-file-:]templateName] ..."
                                                ,"desired-temp" =>"[on|off|5.0..30.0]"
                                                ,sysTime        =>""
                                               }
                     ,"HM-TC-IT-WM-W-EU00"   =>{ sysTime        =>""
                                                ,getSerial      => ""
                                               }
                     ,"HM-TC-IT-WM-W-EU01"   =>{ peerChan       =>"-btnNumber- -actChn- ... single [set|unset] [actor|remote|both]"}
                     ,"HM-TC-IT-WM-W-EU02"   =>{ controlMode    =>"[auto|manual|boost|day|night]"
                                                ,controlManu    =>"[on|off|5.0..30.0]"
                                                ,controlParty   =>"-temp- -startDate- -startTime- -endDate- -endTime-"
                                                ,tempListSat    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,tempListSun    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,tempListMon    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,tempListTue    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,tempListThu    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,tempListWed    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,tempListFri    =>"[prep|exec] [p1|p2|p3] HH:MM temp ..."
                                                ,"desired-temp" =>"[on|off|5.0..30.0]"
                                                ,tempListTmpl   =>"[verify|restore] [[-file-:]templateName] ..."
                                                ,tempTmplSet    =>"[[-file-:]templateName] ..."
                                                ,peerChan       =>"-btnNumber- -actChn- ... single [set|unset] [actor|remote|both]"
                                               }
                     ,"HM-ES-PMSw1-Pl01"     =>{ "on-for-timer" =>"-sec-"
                                                ,"on-till"      =>"-time-"
                                                ,on             =>""
                                                ,off            =>""
                                                ,toggle         =>""
                                                ,press          =>"[long|short] [-peer-] [-repCount(long only)-] [-repDelay-] ..."
                                                ,inhibit        =>"[on|off]"
                                                ,statusRequest  =>""
                                               }
                     ,"HM-ES-PMSw1-Pl00"     =>{ getSerial      => ""
                                                ,getDevInfo     => ""
                                               }
                     ,"HM-Dis-WM5501"        =>{ displayWM      =>"[long|short|help] -lineX- -textNo1- -color1- -icon1- [-textNo2- -color2- -icon2-] ...[-textNo6- -color6- -icon6-] "
                                                ,peerChan       =>"-btnNumber- -actChn- ... single [set|unset] [actor|remote|both]"}
                     ,"CCU-FHEM00"           =>{ update         =>""
                                                ,hmPairForSec   =>"-sec- ..."
                                                ,hmPairSerial   =>"-serial-"
                                                ,defIgnUnknown  =>""
                                                ,assignIO       =>"-IO- [set|unset]..."
                                               }
                     ,"HM-LC-RGBW-WM01"      =>{ "on-for-timer" =>"-ontime- [-ramptime-]..."
                                                ,"on-till"      =>"-time- [-ramptime-]..."
                                                ,on             =>""
                                                ,off            =>""
                                                ,toggle         =>""
                                                ,pct            =>"-value- ... [-ontime-] [-ramptime-]"
                                                ,stop           =>""
                                                ,up             =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                                ,down           =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                                ,inhibit        =>"[on|off]"
                                                ,statusRequest  =>""
                                                ,peerIODev      =>"[IO] -btn- [set|unset]... not for future use"
                                               }
                     ,"HM-LC-RGBW-WM02"      =>{ brightCol      =>"-bright[0-100]- -colVal[0-100]- -duration- -ramp- ..."
                                                ,color          =>"-colVal[0-100]-"
                                                ,on             =>""
                                                ,off            =>""
                                                ,up             =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                                ,down           =>"[-changeValue-] [-ontime-] [-ramptime-] ..."
                                               }
                     ,"HM-LC-RGBW-WM03"      =>{ brightAuto     =>"-bright- -colProg- -min- -max- -duration- -ramp- ..."
                                                ,colProgram     =>"[0|1|2|3|4|5|6]"
                                               }
                     ,"HM-Sec-Sir-WM01"      =>{ on             =>""
                                                ,off            =>""
                                                ,"on-for-timer" =>"-ontime-"
                                                ,"on-till"      =>"-time-"
                                                ,inhibit        =>"[on|off]"
                                               }
                     ,"HM-Sec-Sir-WM04"      =>{ alarmLevel     =>"[disarmed|armExtSens|armAll|armBlocked]"
                                               }
                     ,"HM-Dis-EP-WM5503"     =>{ displayEP      =>"text1,icon1:text2,icon2:text3,icon3 ... -sound- -repetition- -pause- -signal-"}                                       
 );
# clones- - - - - - - - - - - - - - - - -
$culHmChanSets{"HM-Sec-Sir-WM02"}       =
$culHmChanSets{"HM-Sec-Sir-WM03"}       = $culHmChanSets{"HM-Sec-Sir-WM01"};
$culHmChanSets{"HM-Dis-WM5502"}         = $culHmChanSets{"HM-Dis-WM5501"};
$culHmChanSets{"WDF-solar01"}           =
$culHmChanSets{"HM-Sen-RD-O01"}         =
$culHmChanSets{"HM-SEN-EP01"}           =
$culHmChanSets{"HM-SEN-EP02"}           =
$culHmChanSets{"HM-CC-RT-DN05"}         =
$culHmChanSets{"HM-ES-PMSw1-Pl03"}      = $culHmSubTypeSets{THSensor};
$culHmChanSets{"HM-OU-CM-PCB01"}        =
$culHmChanSets{"HM-OU-CFM-TW02"}        = $culHmChanSets{"HM-OU-CFM-PL02"};
$culHmChanSets{"HM-ES-PMSw1-Pl04"}      =
$culHmChanSets{"HM-ES-PMSw1-Pl05"}      =
$culHmChanSets{"HM-ES-PMSw1-Pl06"}      = $culHmChanSets{"HM-ES-PMSw1-Pl03"};
                                        
$culHmChanSets{"HM-ES-PMSw1-Pl01"}      = $culHmSubTypeSets{switch};
$culHmChanSets{"HM-ES-PMSw1-Pl02"}      = $culHmSubTypeSets{outputUnit};
                                        
$culHmChanSets{"WDF-solar02"}           = $culHmSubTypeSets{blindActuator};
                                        
$culHmChanSets{"HM-OU-CFM-TW01"}        = $culHmChanSets{"HM-OU-CFM-PL01"};
                                        
$culHmChanSets{"HM-CC-RT-DN02"}         = $culHmChanSets{"HM-CC-RT-DN00"};
$culHmChanSets{"HM-CC-RT-DN03"}         = $culHmChanSets{"HM-CC-RT-DN06"};
                                        
$culHmChanSets{"ROTO_ZEL-STG-RM-FWT00"} = $culHmChanSets{"HM-CC-TC00"};
$culHmChanSets{"ROTO_ZEL-STG-RM-FWT02"} = $culHmChanSets{"HM-CC-TC02"};
                                        
$culHmChanSets{"HM-LC-Sw1PBU-FM00"}     = $culHmChanSets{"HM-LC-Bl1PBU-FM00"};
$culHmChanSets{"HM-CC-RD-O00"}          = $culHmChanSets{"HM-LC-Bl1PBU-FM00"};
#$culHmChanSets{"HM-ES-PMSw1-Pl00"}      = $culHmChanSets{"HM-LC-Bl1PBU-FM00"};
$culHmChanSets{"HM-TC-IT-WM-W-EU07"}    = 
$culHmChanSets{"HM-Dis-EP-WM5501"}      = 
$culHmChanSets{"HM-Dis-EP-WM5502"}      = $culHmChanSets{"HM-TC-IT-WM-W-EU01"};


%culHmFunctSets = (# command depending on function
  sdLead1             =>{ alarmOn       =>""
                         ,alarmOff      =>""
                         ,teamCall      =>""
                         ,teamCallBat   =>""
                        },
  sdLead2             =>{ alarmOn       =>""
                         ,alarmOff      =>""
                         ,teamCall      =>"no ..."
                        },
  vdCtrl              =>{ valvePos      =>"[off|0.0..99.0]"},
  virtThSens          =>{ virtTemp      =>"[off|-20.0..50.0]",
                          virtHum       =>"[off|0.0..99.0]"}
);

#General $culHmFunctSets{"sdLead2"}          = $culHmFunctSets{"sdLead1"};

# RC send BCAST to specific address. Is the meaning understood?
@culHmCmdFlags = ("WAKEUP", "WAKEMEUP", "BCAST", "Bit3",
                   "BURST", "BIDI"    , "RPTED", "RPTEN");
                     #RPTEN    0x80: set in every message. Meaning?
                     #RPTED    0x40: repeated (repeater operation)
                     #BIDI     0x20: response is expected
                     #Burst    0x10: set if burst is required by device
                     #Bit3     0x08:
                     #BCAST    0x04: Broadcast - to all my peers parallel
                     #WAKEMEUP 0x02: awake - hurry up to send messages
                     #WAKEUP   0x01: send initially to keep the device awake

##############################---messages---###################################
%culHmBits = (
  "00"          => { txt => "DEVICE_INFO",  params => {
                     FIRMWARE       => '00,2',
                     TYPE           => "02,4",
                     SERIALNO       => '06,20,$val=pack("H*",$val)',
                     CLASS          => "26,2",
                     PEER_CHANNEL_A => "28,2",
                     PEER_CHANNEL_B => "30,2",
                     UNKNOWN        => "32,2", }},

  "01;p11=01"   => { txt => "CONFIG_PEER_ADD", params => {
                     CHANNEL        => "00,2",
                     PEER_ADDRESS   => "04,6",
                     PEER_CHANNEL_A => "10,2",
                     PEER_CHANNEL_B => "12,2", }},
  "01;p11=02"   => { txt => "CONFIG_PEER_REMOVE", params => {
                     CHANNEL        => "00,2",
                     PEER_ADDRESS   => '04,6,$val=CUL_HM_id2Name($val)',
                     PEER_CHANNEL_A => "10,2",
                     PEER_CHANNEL_B => "12,2", } },
  "01;p11=03"   => { txt => "CONFIG_PEER_LIST_REQ", params => {
                     CHANNEL => "0,2", },},
  "01;p11=04"   => { txt => "CONFIG_PARAM_REQ", params => {
                     CHANNEL        => "00,2",
                     PEER_ADDRESS   => "04,6",
                     PEER_CHANNEL   => "10,2",
                     PARAM_LIST     => "12,2", },},
  "01;p11=05"   => { txt => "CONFIG_START", params => {
                     CHANNEL        => "00,2",
                     PEER_ADDRESS   => "04,6",
                     PEER_CHANNEL   => "10,2",
                     PARAM_LIST     => "12,2", } },
  "01;p11=06"   => { txt => "CONFIG_END", params => {
                     CHANNEL => "0,2", } },
  "01;p11=07"   => { txt => "CONFIG_WRITE_INDEX", params => {
                     CHANNEL => "0,2",
                     ADDR => "4,2",
                     DATA => '6,,$val =~ s/(..)/ $1/g', } },
  "01;p11=08"   => { txt => "CONFIG_WRITE_INDEX", params => {
                     CHANNEL => "0,2",
                     DATA => '4,,$val =~ s/(..)(..)/ $1:$2/g', } },
  "01;p11=09"   => { txt => "CONFIG_SERIAL_REQ", params => { } },
  "01;p11=0A"   => { txt => "PAIR_SERIAL", params => {
                     SERIALNO       => '04,,$val=pack("H*",$val)', } },
  "01;p11=0E"   => { txt => "CONFIG_STATUS_REQUEST", params => {
                     CHANNEL => "0,2", } },

  "02;p01=00"   => { txt => "ACK"},
  "02;p01=01"   => { txt => "ACK_STATUS",  params => {
                     CHANNEL        => "02,2",
                     STATUS         => "04,2",
                     DOWN           => '06,02,$val=(hex($val)&0x20)?1:0',
                     UP             => '06,02,$val=(hex($val)&0x10)?1:0',
                     LOWBAT         => '06,02,$val=(hex($val)&0x80)?1:0',
                     RSSI           => '08,02,$val=(-1)*(hex($val))', }},
  "02;p01=02"   => { txt => "ACK2"}, # smokeDetector pairing only?
  "02;p01=04"   => { txt => "AES_req",  params => {#
                     Para1          => "02,4",
                     Para2          => "06,4",
                     Para3          => "10,4",
                     keyNo          => "14,2",}},
  "02;p01=80"   => { txt => "NACK"},
  "02;p01=84"   => { txt => "NACK_TARGET_INVALID"},
  "02"          => { txt => "ACK/NACK_UNKNOWN   "},

  "03"          => { txt => "AES reply",   params => { # send 'old' AES key to actor
                     DATA =>  "0," } },

  "04;p01=01"   => { txt => "To-HMLan:send AES code",   params => { # FHEM req HMLAN to send AES key to aktor ??
                     CHANNEL => "00,2",
                     TYPE    => "02,2" } },                         #00: old key? 01: new key?
  "04"          => { txt => "To-Actor:send AES key" ,   params => { # HMLAN sends AES key to actor ??
                     CODE    => "00" } },

  "10;p01=00"   => { txt => "INFO_SERIAL", params => {
                     SERIALNO => '02,20,$val=pack("H*",$val)'},},
  "10;p01=01"   => { txt => "INFO_PEER_LIST", params => {
                     PEER1 => '02,8,$val=CUL_HM_id2Name($val)',
                     PEER2 => '10,8,$val=CUL_HM_id2Name($val)',
                     PEER3 => '18,8,$val=CUL_HM_id2Name($val)',
                     PEER4 => '26,8,$val=CUL_HM_id2Name($val)'},},
  "10;p01=02"   => { txt => "INFO_PARAM_RESPONSE_PAIRS", params => {
                     DATA => "2,", },},
  "10;p01=03"   => { txt => "INFO_PARAM_RESPONSE_SEQ", params => {
                     OFFSET => "2,2",
                     DATA   => "4,", },},
  "10;p01=04"   => { txt => "INFO_PARAMETER_CHANGE", params => {
                     CHANNEL => "2,2",
                     PEER    => '4,8,$val=CUL_HM_id2Name($val)',
                     PARAM_LIST => "12,2",
                     DATA => '14,,$val =~ s/(..)(..)/ $1:$2/g', } },
  "10;p01=06"   => { txt => "INFO_ACTUATOR_STATUS", params => {
                     CHANNEL => "2,2",
                     STATUS  => '4,2',
                     UNKNOWN => "6,2",
                     RSSI    => '08,02,$val=(-1)*(hex($val))' } },
  "10;p01=0A"   => { txt => "INFO_TEMP", params => {
                     SET     => '2,4,$val=(hex($val)>>10)&0x3F',
                     ACT     => '2,4,$val=hex($val)&0x3FF',
                     ERR     => "6,2",
                     VALVE   => "6,2",
                     MODE    => "6,2" } },

  "11;p01=00"   => { txt => "INHIBIT0ff"  , params => {
                     CHANNEL  => "02,2" } },
  "11;p01=01"   => { txt => "INHIBIT0n"   , params => {
                     CHANNEL  => "02,2" } },
  "11;p01=02"   => { txt => "SET"         , params => {
                     CHANNEL  => "02,2",
                     VALUE    => "04,2",
                     RAMPTIME => '06,4,$val=CUL_HM_decodeTime16($val)',
                     DURATION => '10,4,$val=CUL_HM_decodeTime16($val)', } },
  "11;p01=03"   => { txt => "STOP_change" , params => {
                     CHANNEL  => "02,2"} },
  "11;p02=0400" => { txt => "RESET" },
  "11;p01=80"   => { txt => "LED"         , params => {
                     CHANNEL  => "02,2",
                     COLOR    => "04,2", } },
  "11;p02=8100" => { txt => "LEDall"      , params => {
                     Led1To16 => '04,8,$val= join(":",sprintf("%b",hex($val))=~ /(.{2})/g)',
                     } },
  "11;p01=81"   => { txt => "LEVEL"       , params => {#ALARM_COUNT/HANDLE_LOCK/LEVEL_SET/MANU_MODE_SET/SET_ALL_CHANNELS
                     CHANNEL  => "02,2",
                     TIME     => '04,2,$val=hex($val)',
                     SPEED    => '06,2,$val=hex($val)',
                     } },
  "11;p01=82"   => { txt => "Sleepmode"   , params => {#SET_WINTER_MODE/SET_LED_SLEEP_MODE/SERVICE_COUNT/PARTY_MODE_SET
                     CHANNEL  => "02,2",
                     MODE     => '04,2,$val=hex($val)',
                     } },
  "11;p01=83"   => { txt => "EnterBootLoader"   },#BOOST_MODE_SET/SET_HANDLE_LED_MODE
#  "11;p01=84"   => { txt => ""   },#SET_SHEV_POS/COMFORT_MODE_SET
#  "11;p01=85"   => { txt => ""   },#LOWERING_MODE_SET/SET_RELEASE_TURN
  "11;p01=86"   => { txt => "SetTemp"     , params => {
                     B1     => "02,2",
                     B2     => '04,2',
                     } },
  "11;p01=87"   => { txt => "AdaptionDriveSet"  },
  "11;p01=CA"   => { txt => "EnterBootLoader"   },#download? at the end?

  "12"          => { txt => "HAVE_DATA"},
  "3E"          => { txt => "SWITCH"      , params => {
                     PEER     => "00,6",
                     fix      => "06,2",
                     CHANNEL  => "08,2",
                     COUNTER  => "10,2", } },
  "3F"          => { txt => "TimeStamp"   , params => {
                     UNKNOWN  => "00,4",
                     TIME     => "04,2", } },
  "40"          => { txt => "REMOTE"      , params => {
                     BUTTON   => '00,2,$val=(hex($val)&0x3F)',
                     LONG     => '00,2,$val=(hex($val)&0x40)?1:0',
                     LOWBAT   => '00,2,$val=(hex($val)&0x80)?1:0',
                     COUNTER  => "02,2", } },
  "41"          => { txt => "Sensor_event", params => {
                     BUTTON   => '00,2,$val=(hex($val)&0x3F)',
                     LONG     => '00,2,$val=(hex($val)&0x40)?1:0',
                     LOWBAT   => '00,2,$val=(hex($val)&0x80)?1:0',
                     NBR      => '02,2,$val=(hex($val))',
                     VALUE    => '04,2,$val=(hex($val))',} },
  "42"          => { txt => "SwitchLevel" , params => {
                     BUTTON   => '00,2,$val=(hex($val)&0x3F)',
                     NBR      => '02,2,$val=(hex($val))',
                     LEVEL    => '04,2,$val=(hex($val))',} },
  "53"          => { txt => "SensorData"  , params => {
                     CMD => "00,2",
                     Fld1=> "02,2",
                     Val1=> '04,4,$val=(hex($val))',
                     Fld2=> "08,2",
                     Val2=> '10,4,$val=(hex($val))',
                     Fld3=> "14,2",
                     Val3=> '16,4,$val=(hex($val))',
                     Fld4=> "20,2",
                     Val4=> '24,4,$val=(hex($val))'} },
  "54"          => { txt => "GasEvent"    , params => {
                     energy   => '00,8,$val=((hex($val)) /1000)'
                    ,power    => '06,6,$val=((hex($val)) /1000)'
                     } },
  "58"          => { txt => "ClimateEvent", params => {
                     CMD      => "00,2",
                     ValvePos => '02,2,$val=(hex($val))', } },
  "59"          => { txt => "setTeamTemp" , params => {
                     CMD      => "00,2",
                     desTemp  => '02,2,$val=((hex($val)>>2) /2)',
                     mode     => '02,2,$val=(hex($val) & 0x3)',} },
  "5A"          => { txt => "ThermCtrl"   , params => {
                     setTemp  => '00,2,$val=(((hex($val)>>2)&0x3f) /2)',
                     actTemp  => '00,4,$val=((hex($val)>>6) /10)',
                     hum      => '04,2,$val=(hex($val) & 0x3)',} },
  "5E"          => { txt => "powerEvntCyc", params => {
                     energy   => '00,6,$val=((hex($val)) /10)',
                     power    => '06,6,$val=((hex($val)) /100)',
                     current  => '12,4,$val=((hex($val)) /1)',
                     voltage  => '16,4,$val=((hex($val)) /10)',
                     frequency=> '20,2,$val=((hex($val)) /100+50)',
                     } },
  "5F"          => { txt => "powerEvnt"   , params => {
                     energy   => '00,6,$val=((hex($val)) /10)',
                     power    => '06,6,$val=((hex($val)) /100)',
                     current  => '12,4,$val=((hex($val)) /1)',
                     voltage  => '16,4,$val=((hex($val)) /10)',
                     frequency=> '20,2,$val=((hex($val)) /100+50)',
                     } },
  "70"          => { txt => "WeatherEvent", params => {
                     TEMP     => '00,4,$val=((hex($val)&0x3FFF)/10)*((hex($val)&0x4000)?-1:1)',
                     HUM      => '04,2,$val=(hex($val))', } },
);


  foreach my $reg (keys %culHmRegDefShLg){ #update register list
    %{$culHmRegDefine{"sh".$reg}} = %{$culHmRegDefShLg{$reg}};
    %{$culHmRegDefine{"lg".$reg}} = %{$culHmRegDefShLg{$reg}};
    $culHmRegDefine{"lg".$reg}{a} +=0x80;
  }
  foreach my $rN  (keys %culHmRegDefine){ #create literal inverse for fast search
    if ($culHmRegDefine{$rN}{lit}){# literal assigned => create inverse
      foreach my $lit (keys %{$culHmRegDefine{$rN}{lit}}){
        $culHmRegDefine{$rN}{litInv}{$culHmRegDefine{$rN}{lit}{$lit}}=$lit;
      }
    }
  }
  foreach my $type (keys %culHmRegType) { #update references to register
    foreach my $reg (keys %{$culHmRegType{$type}}){
      if ($culHmRegDefShLg{$reg}){
        delete $culHmRegType{$type}{$reg};
        $culHmRegType{$type}{"sh".$reg} = 1;
        $culHmRegType{$type}{"lg".$reg} = 1;
      }
    }
  }
  foreach my $type (keys %culHmRegModel){ #update references to register
    foreach my $reg (keys %{$culHmRegModel{$type}}){
      if ($culHmRegDefShLg{$reg}){
        delete $culHmRegModel{$type}{$reg};
        $culHmRegModel{$type}{"sh".$reg} = 1;
        $culHmRegModel{$type}{"lg".$reg} = 1;
      }
    }
  }
  foreach my $type (keys %culHmRegChan) { #update references to register
    foreach my $reg (keys %{$culHmRegChan{$type}}){
      if ($culHmRegDefShLg{$reg}){
        delete $culHmRegChan{$type}{$reg};
        $culHmRegChan{$type}{"sh".$reg} = 1;
        $culHmRegChan{$type}{"lg".$reg} = 1;
      }
    }
  }

  foreach my $al (keys %culHmModel){ # duplicate entries for alias devices
    next if (!defined $culHmModel{$al}{alias});

    foreach my $mt (keys %culHmModel){
      if (($culHmModel{$al}{alias}) eq $culHmModel{$mt}{name}){
        my $md = $culHmModel{$mt}{name};
        my $ds = $culHmModel{$al}{name};
        $culHmModelSets{$ds}    = $culHmModelSets{$md} if($culHmModelSets{$md});
        $culHmModelGets{$ds}    = $culHmModelGets{$md} if($culHmModelSets{$md});
        foreach (grep /^$md/,keys %culHmChanSets){
          $culHmChanSets{$ds.substr($_,-2,2)}    = $culHmChanSets{$_};
        }
        $culHmRegModel{$ds}     = $culHmRegModel{$md}   if ($culHmRegModel{$md});
        foreach(grep  /^$md/,keys %culHmRegChan){
          $culHmRegChan{$ds.substr($_,-2,2)}    = $culHmRegChan{$_};
        }
        last;
      }
    }
    delete $culHmModel{$al} if (!defined$culHmModel{$al}{st}); # not found - remove entry
  }
  
1;
